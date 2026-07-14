from backend.datasource.api import APICollector
from backend.datasource.sqlserver import SQLServerCollector
from dotenv import load_dotenv
from backend.contracts.schema import CompraSchema
from backend.tools.aws.client import S3Client

import time
import schedule
import logging

# Configuração básica de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

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


def sqlserverCollector(aws, db_name, table_name, time_column="transaction_time", full_load=False):
    # Repassando o time_column para a classe SQLServerCollector
    response = SQLServerCollector(
        aws_client=aws, 
        db_name=db_name, 
        table_name=table_name, 
        time_column=time_column
    ).start(full_load=full_load)

    if response:
        logging.info(f"Executei com sucesso (SQL Server - {db_name}.{table_name}): Arquivo salvo no S3.")
    else:
        logging.info(f"Executei (SQL Server - {db_name}.{table_name}), mas nenhum dado foi salvo.")

    return response

# ==========================================
# Rotinas em Lote (Múltiplas Tabelas)
# ==========================================

def run_tecpel_jobs(full_load=False):
    """
    Rotina que extrai todas as tabelas mapeadas do banco 'Tecpel'
    """
    logging.info(f"Iniciando rotina do banco Tecpel (Full Load: {full_load})")
    
    # Usando um dicionário para amarrar a tabela à sua coluna de data específica!
    tabelas_tecpel = {
        "TITMMOV": "DATA_CRIACAO",    # Substitua pelo nome real da coluna na tabela TITMMOV
        "TMOV": "DATA_EMISSAO"        # Substitua pelo nome real da coluna na tabela TMOV
    }
    
    for tabela, coluna_data in tabelas_tecpel.items():
        try:
            sqlserverCollector(aws, db_name="Tecpel", table_name=tabela, time_column=coluna_data, full_load=full_load)
        except Exception as e:
            logging.error(f"Erro ao extrair Tecpel.{tabela}: {e}")

def run_fluig_jobs(full_load=False):
    """
    Rotina que extrai as tabelas mapeadas do banco 'Fluig'
    """
    logging.info(f"Iniciando rotina do banco Fluig (Full Load: {full_load})")
    
    tabelas_fluig = {
        "ML001105": "DATA_CRIACAO",   # Coluna para a janela incremental
        "ML001106": "DATA_CRIACAO"    # Coluna para a janela incremental
    }
    
    for tabela, coluna_data in tabelas_fluig.items():
        try:
            sqlserverCollector(aws, db_name="Fluig", table_name=tabela, time_column=coluna_data, full_load=full_load)
        except Exception as e:
            logging.error(f"Erro ao extrair Fluig.{tabela}: {e}")

# ==========================================
# Agendamentos
# ==========================================

# 1. Extração da API (ex: a cada 1 minuto)
# schedule.every(1).minutes.do(apiCollector, schema, aws, 50)

# 2. Extrações de Banco de Dados (Carga Incremental a cada 1 hora no horário comercial)
# Define o horário comercial das 08:00 às 18:00
horarios_comerciais = [f"{h:02d}:00" for h in range(8, 19)]

for hora in horarios_comerciais:
    schedule.every().day.at(hora).do(run_tecpel_jobs, full_load=False)
    schedule.every().day.at(hora).do(run_fluig_jobs, full_load=False)

# (Descomente este bloco se quiser rodar na hora para testar)
# if __name__ == "__main__":
#     logging.info("Iniciando o agendador. Pressione Ctrl+C para sair.")
#     run_tecpel_jobs(full_load=True) # Exemplo: rodar manual a primeira vez
#     run_fluig_jobs(full_load=True)  # Exemplo: rodar manual a primeira vez
#     
#     while True:
#         schedule.run_pending()
#         time.sleep(1)