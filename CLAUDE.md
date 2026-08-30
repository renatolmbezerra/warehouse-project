# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é isto

Um pipeline de ETL de data warehouse para a Tecpel (um ERP brasileiro) que extrai dados do SQL Server e de uma API de vendas fake, deposita-os no S3 em Parquet, transforma-os com dbt-duckdb (arquitetura medallion) e carrega o resultado tratado de volta em um SQL Server de destino (`DW_Tecpel`). Toda a regra de negócio (cálculos fiscais como ICMS/IPI/PIS/COFINS, precificação, etc.) é específica do domínio Tecpel e vive nos models gold do dbt.

## Comandos

As dependências são gerenciadas com `uv` (ver `pyproject.toml` / `uv.lock`, Python `>=3.12.10` fixado via `.python-version`).

```bash
uv sync                                   # instala as dependências
```

Não há suíte de testes neste repositório.

Etapas do pipeline (rodar nesta ordem; cada uma é um passo manual separado, não há script orquestrador):

```bash
# 1. Opcional: sobe a API de vendas fake usada por apiCollector() em backend/start.py
uv run uvicorn backend.fakeapi.start:app --reload   # padrão http://127.0.0.1:8000

# 2. Extração: SQL Server (Tecpel/Fluig) + API fake -> S3 bronze (Parquet)
uv run python -m backend.start

# 3. Transformação: dbt-duckdb lê o bronze do S3, constrói o silver (views deduplicadas) e o gold (fact/dim, Parquet externo)
cd dbt_warehouse && uv run dbt run

# 4. Carga: Parquet gold do S3 -> SQL Server de destino (DW_Tecpel), watermark + MERGE (upsert)
uv run python -m backend.jobs.load_gold
```

Rode tudo a partir da raiz do repositório (não há arquivos `__init__.py`; `backend` é usado como namespace package implícito, então imports como `from backend.datasource.api import APICollector` só resolvem quando a raiz do repositório está no `sys.path`/diretório atual).

Variáveis de ambiente exigidas (carregadas de um arquivo `.env` na raiz do repositório via `python-dotenv`):
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET_NAME`, `DELTA_LAKE_S3_PATH` — usadas por `S3Client` (`backend/tools/aws/client.py`) e pelo secret S3 do dbt em `dbt_warehouse/profiles.yml`.
- `DB_SERVER`, `DB_USER`, `DB_PASSWORD`, `DB_DRIVER` — credenciais compartilhadas do SQL Server; `get_engine(db_name)` em `backend/tools/sql/db/database_connection.py` troca só a parte `DATABASE=` a cada chamada (`Tecpel`, `Fluig` na extração, `DW_Tecpel` na carga final) e mantém as engines em cache por `db_name`.
- `API_BASE_URL` — opcional, padrão `http://127.0.0.1:8000`, usada por `APICollector`.

## Arquitetura

### Extração (`backend/`)

`backend/start.py` é o ponto de entrada da extração, com duas rotinas em lote: `run_tecpel_jobs(full_load_tables=None)` e `run_fluig_jobs(full_load_tables=None)`. Cada uma define:
- um dict `fatos` mapeando nome da tabela -> a coluna usada para filtrar a janela incremental;
- uma lista `dimensoes` com as tabelas que sempre recebem carga completa (full load, sem filtro de data).

`full_load_tables` permite forçar uma carga completa por execução: passe `["ALL"]` para todas as tabelas fato, ou nomes de tabelas específicas (case-insensitive) para forçar só essas, ex.: `run_tecpel_jobs(full_load_tables=["FLAN", "TMOV"])`.

Ambas as rotinas chamam `sqlserverCollector()`, um wrapper fino que injeta `window_days=INCREMENTAL_WINDOW_DAYS` (atualmente 7 dias, para cobrir com segurança fins de semana/feriados/falhas de execução) e delega para `SQLServerCollector` (`backend/datasource/sqlserver.py`). Seu `extract_data()`:
- roda `SELECT * FROM {table}` quando `full_load=True`;
- caso contrário, filtra `WHERE {time_column} >= DATEADD(day, -{window_days}, GETDATE())`;
- lê os resultados em lotes de 100 mil linhas via `pd.read_sql(..., chunksize=...)` para evitar timeouts em tabelas grandes (ex.: `FLAN`, `TITMMOV`).

A maioria das tabelas fato da Tecpel tem sua própria coluna `RECCREATEDON` (timestamp de inserção no sistema de origem) e a usa diretamente como `time_column` em vez de uma data de negócio, então o filtro incremental reflete o momento em que a linha apareceu na origem, e não uma data de negócio como a data de emissão de uma nota. Exceções: `ESTOQUE_SALDO_PRODUTO_MES` filtra por `DATA_SALDO` e `CLIENTESAB_DTBASE` por `DATA_COMPETENCIA` — são snapshots mensais sem `RECCREATEDON` útil. As fatos do Fluig (`ML001026`, `ML001094`) filtram por `dataEmissao`/`dataemissao`, que vêm como texto `DD/MM/YYYY`, então `sqlserverCollector()` recebe `date_format_style=103` para o parse.

Todo DataFrame extraído recebe as colunas `dt_extracao` (timestamp de extração) e `datasource` (`transform_add_columns`) antes de ser escrito, um arquivo Parquet por execução, em `s3://.../02_bronze/{sqlserver|api}/{db}/{table}/..._{full|incremental}_{timestamp}.parquet` — o bronze é append-only; nada ali é sobrescrito.

`backend/tools/sql/db/database_connection.py` e `backend/tools/aws/client.py` são os clientes compartilhados de SQL Server / S3 usados tanto na extração quanto na carga.

### Transformação (`dbt_warehouse/`)

Projeto dbt sobre DuckDB (`dbt-duckdb`), configurado para rodar inteiramente em memória (`path: ':memory:'` em `profiles.yml`) com a extensão `httpfs` para acesso ao S3.

- `models/02_bronze/src_*.yml` — sources do dbt apontando para os caminhos Parquet do bronze no S3 (um arquivo por sistema de origem: `src_tecpel.yml`, `src_fluig.yml`, `src_api.yml`).
- `models/03_silver/slv_<system>_<table>.sql` — uma view por tabela bronze, deduplicada via `QUALIFY ROW_NUMBER() OVER (PARTITION BY <colunas de chave primária> ORDER BY dt_extracao DESC) = 1`, de modo que o snapshot bronze mais recente por PK prevalece entre execuções incrementais sobrepostas. Materializadas como views (ver `dbt_project.yml`).
- `models/04_gold/gld_dim_*.sql` / `gld_fct_*.sql` — models de dimensão/fato cruzando vários models silver, materializados como Parquet externo no S3 (`04_gold/sqlserver/Tecpel/` para os models Tecpel, `04_gold/api/fakeapi/` para o model da API). É aqui que vivem as regras de negócio específicas da Tecpel (cálculos fiscais, faixas de precificação, margens, etc.) — leia um model gold existente (ex.: `gld_fct_vendas_itens.sql`) antes de adicionar um novo, para seguir a mesma estrutura de CTEs e convenções de nomenclatura de colunas já em uso.
- Convenção de chaves: todo model gold da Tecpel (fato e dimensão) carrega `CODCOLIGADA` e ela é a primeira coluna da PK em `PK_DICT` (rastreabilidade da coligada de origem no ERP). Ao criar um novo model gold Tecpel, inclua `CODCOLIGADA` e comece a PK por ela.

### Carga (`backend/jobs/load_gold.py`)

`load_gold_to_sqlserver()` lista todo arquivo Parquet sob `04_gold/` no S3 e, para cada tabela gold:
1. Detecta um watermark consultando `MAX(dt_extracao)` na tabela de destino (se ela já existir).
2. Se existir um watermark **e** a tabela tiver uma entrada em `PK_DICT` (suas colunas de chave primária), filtra o DataFrame recebido para `dt_extracao > watermark` e faz um **MERGE** incremental: estagia o delta em `stg_{table}`, depois roda um `MERGE ... WHEN MATCHED THEN UPDATE ... WHEN NOT MATCHED BY TARGET THEN INSERT` usando as colunas da PK.
3. Caso contrário (primeira carga, ou sem PK registrada), faz um `to_sql(..., if_exists='replace')` completo e reconstrói um índice columnstore clusterizado na tabela.

Ao adicionar um novo model gold que deve suportar carga incremental via MERGE, adicione sua chave primária em `PK_DICT` neste arquivo — caso contrário, ele silenciosamente cai para replace completo a cada execução.

### Mudança de schema em model gold

O MERGE incremental não tolera divergência de colunas entre o Parquet gold e a tabela de destino: uma coluna nova quebra o `INSERT`, e uma coluna removida fica órfã com dados desatualizados no destino. Ao adicionar ou remover coluna de um model gold, o fluxo é: editar o `.sql` → `dbt run` (gera o Parquet novo no S3) → `DROP TABLE {tabela}` no `DW_Tecpel` → `uv run python -m backend.jobs.load_gold` (recria a tabela via replace completo).

### Decisões arquiteturais registradas (ver `.llm/prd.md`)

- **Sem `row_hash`**: o MERGE atualiza todas as linhas do delta mesmo quando só `dt_extracao` mudou. Um `row_hash` sobre as colunas de negócio evitaria esses `UPDATE`s, mas a decisão foi manter o comportamento atual pela simplicidade — reavaliar só se houver gargalo de I/O comprovado nos MERGEs.
- **Sem SCD Type 2**: dimensões carregam apenas o estado corrente. Adiado até haver requisito analítico concreto de histórico ("qual era a filial do vendedor no momento daquela venda?").
