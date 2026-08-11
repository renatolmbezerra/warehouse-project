from backend.datasource.api import APICollector
from backend.datasource.sqlserver import SQLServerCollector
from dotenv import load_dotenv
from backend.contracts.schema import CompraSchema
from backend.tools.aws.client import S3Client

import time
import schedule
import logging

# Configuração básica de logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)

# Carrega as variáveis do arquivo .env para o sistema
load_dotenv(override=True)

schema = CompraSchema
aws = S3Client()


def apiCollector(schema, aws, repeat):
    response = APICollector(schema, aws).start(repeat)

    if response:
        logging.info("Executei com sucesso (API): Arquivo salvo no S3.")
    else:
        logging.info("Executei (API), mas nenhum dado foi salvo (vazio ou erro).")

    return response


def sqlserverCollector(
    aws,
    db_name,
    table_name,
    time_column="transaction_time",
    full_load=False,
    date_format_style=None,
    custom_where=None,
):
    # Repassando todos os parâmetros para a classe SQLServerCollector
    response = SQLServerCollector(
        aws_client=aws,
        db_name=db_name,
        table_name=table_name,
        time_column=time_column,
        date_format_style=date_format_style,
        custom_where=custom_where,
    ).start(full_load=full_load)

    if response:
        logging.info(
            f"Executei com sucesso (SQL Server - {db_name}.{table_name}): Arquivo salvo no S3."
        )
    else:
        logging.info(
            f"Executei (SQL Server - {db_name}.{table_name}), mas nenhum dado foi salvo."
        )

    return response


# ==========================================
# Rotinas em Lote (Múltiplas Tabelas)
# ==========================================


def run_tecpel_jobs(full_load_tables=None):
    """
    Rotina que extrai as tabelas mapeadas do banco 'Tecpel' separando fatos e dimensões.

    Parâmetro 'full_load_tables':
    - None (vazio)       -> Carga Incremental em todas as Fatos (Comportamento padrão de produção).
    - ["ALL"]            -> Força Carga Full em TODAS as tabelas Fato.
    - ["NOME_DA_TABELA"] -> Força Carga Full apenas na Fato especificada (ex: ["FLAN", "TMOV"]).
    """
    if full_load_tables is None:
        full_load_tables = []

    logging.info(
        f"Iniciando rotina do banco Tecpel (Full Load Tables: {full_load_tables})"
    )

    fatos = {
        "TITMMOV": "CUSTOM_WHERE",
        "TMOV": "DATASAIDA",
        "TTRBMOV": "CUSTOM_WHERE",
        "TMOVCOMPL": "CUSTOM_WHERE",
        "TITMMOVCOMPL": "CUSTOM_WHERE",
        "FLAN": "DATACRIACAO",
        "TRELSLD": "DATAMOVIMENTO",
        "ESTOQUE_SALDO_PRODUTO_MES": "DATA_SALDO",
        "CLIENTESAB_DTBASE": "DATA_COMPETENCIA",
        "ZMD_TABPRECO": "RECCREATEDON",
    }

    # Subqueries customizadas para tabelas filhas que não possuem data própria
    custom_wheres = {
        "TITMMOV": "EXISTS (SELECT 1 FROM TMOV WHERE TMOV.CODCOLIGADA = TITMMOV.CODCOLIGADA AND TMOV.IDMOV = TITMMOV.IDMOV AND TMOV.DATASAIDA >= DATEADD(day, -3, GETDATE()))",
        "TTRBMOV": "EXISTS (SELECT 1 FROM TMOV WHERE TMOV.CODCOLIGADA = TTRBMOV.CODCOLIGADA AND TMOV.IDMOV = TTRBMOV.IDMOV AND TMOV.DATASAIDA >= DATEADD(day, -3, GETDATE()))",
        "TMOVCOMPL": "EXISTS (SELECT 1 FROM TMOV WHERE TMOV.CODCOLIGADA = TMOVCOMPL.CODCOLIGADA AND TMOV.IDMOV = TMOVCOMPL.IDMOV AND TMOV.DATASAIDA >= DATEADD(day, -3, GETDATE()))",
        "TITMMOVCOMPL": "EXISTS (SELECT 1 FROM TMOV WHERE TMOV.CODCOLIGADA = TITMMOVCOMPL.CODCOLIGADA AND TMOV.IDMOV = TITMMOVCOMPL.IDMOV AND TMOV.DATASAIDA >= DATEADD(day, -3, GETDATE()))",
    }

    for tabela, coluna_data in fatos.items():
        try:
            custom_where_clause = (
                custom_wheres.get(tabela) if coluna_data == "CUSTOM_WHERE" else None
            )
            
            # Tratamento case-insensitive para a verificação de full load
            tabelas_full_load_upper = [t.upper() for t in full_load_tables]
            is_full_load = (tabela.upper() in tabelas_full_load_upper) or ("ALL" in tabelas_full_load_upper)
            
            sqlserverCollector(
                aws,
                db_name="Tecpel",
                table_name=tabela,
                time_column=coluna_data,
                full_load=is_full_load,
                custom_where=custom_where_clause,
            )
        except Exception as e:
            logging.error(f"Erro ao extrair Fato Tecpel.{tabela}: {e}")

    # 2. Tabelas Dimensão (Carga sempre Full Load, sem precisar de coluna de data)
    dimensoes = [
        "FCFO",
        "TPRD",
        "DALIQINTERESTADUAL",
        "TVEN",
        "TVENCOMPL",
        "GCONSIST",
        "ZMD_CATEGORIA",
        "TPRODUTODEF",
        "TMARCA",
        "GFILIAL",
        "FCFODEF",
        "TCPG",
        "FTB3",
        "TTRA",
        "TTB1",
        "TTB2",
        "TTB3",
        "TTB4",
        "TTRBPRD",
        "TTMV",
        "TLOC",
        "FTCF",
        "GETD",
        "DREGIAO",
        "DETDREGIAO",
    ]

    for tabela in dimensoes:
        try:
            sqlserverCollector(
                aws,
                db_name="Tecpel",
                table_name=tabela,
                time_column=None,
                full_load=True,
            )
        except Exception as e:
            logging.error(f"Erro ao extrair Dimensão Tecpel.{tabela}: {e}")


def run_fluig_jobs(full_load_tables=None):
    """
    Rotina que extrai as tabelas mapeadas do banco 'Fluig' separando fatos e dimensões.

    Parâmetro 'full_load_tables':
    - None (vazio)       -> Carga Incremental em todas as Fatos (Comportamento padrão de produção).
    - ["ALL"]            -> Força Carga Full em TODAS as tabelas Fato.
    - ["NOME_DA_TABELA"] -> Força Carga Full apenas na Fato especificada.
    """
    if full_load_tables is None:
        full_load_tables = []

    logging.info(
        f"Iniciando rotina do banco Fluig (Full Load Tables: {full_load_tables})"
    )

    # 1. Tabelas Fato (Carga Incremental)
    fatos = {
        "ML001026": "dataEmissao",
        "ML001094": "dataemissao"
    }

    for tabela, coluna_data in fatos.items():
        try:
            # Fluig usa data no formato DD/MM/YYYY em texto, então passamos o estilo 103
            is_full_load = (tabela in full_load_tables) or ("ALL" in full_load_tables)
            sqlserverCollector(
                aws,
                db_name="Fluig",
                table_name=tabela,
                time_column=coluna_data,
                full_load=is_full_load,
                date_format_style=103,
            )
        except Exception as e:
            logging.error(f"Erro ao extrair Fato Fluig.{tabela}: {e}")

    # 2. Tabelas Dimensão (Sempre Full Load)
    dimensoes = ["ML001048"]

    for tabela in dimensoes:
        try:
            sqlserverCollector(
                aws,
                db_name="Fluig",
                table_name=tabela,
                time_column=None,
                full_load=True,
            )
        except Exception as e:
            logging.error(f"Erro ao extrair Dimensão Fluig.{tabela}: {e}")


# ==========================================
# Agendamentos
# ==========================================

# 1. Extração da API (ex: a cada 1 minuto)
# schedule.every(1).minutes.do(apiCollector, schema, aws, 50)

# 2. Extrações de Banco de Dados (Carga Incremental a cada 1 hora no horário comercial)
# Define o horário comercial das 08:00 às 18:00

# horarios_comerciais = [f"{h:02d}:00" for h in range(8, 19)]

# for hora in horarios_comerciais:
#     schedule.every().day.at(hora).do(run_tecpel_jobs, force_full_load=False)
#     schedule.every().day.at(hora).do(run_fluig_jobs, force_full_load=False)

# (Descomente este bloco se quiser rodar na hora para testar)
if __name__ == "__main__":
    logging.info("Iniciando o agendador. Pressione Ctrl+C para sair.")
    run_tecpel_jobs(full_load_tables=[])  # Exemplo: ["ALL"] para tudo, ou ["FLAN", "TMOV"] para tabelas específicas
    
    run_fluig_jobs(full_load_tables=[])  # Exemplo: rodar manual a primeira vez

    apiCollector(schema, aws, 50)  # Roda a extração da API manualmente

    logging.info("ETAPA 1 CONCLUÍDA: Extração dos dados e carregamento (Load) no S3 finalizados com sucesso!")

    # while True:
    #     schedule.run_pending()
    #     time.sleep(1)
