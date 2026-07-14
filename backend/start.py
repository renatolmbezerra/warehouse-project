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


def sqlserverCollector(aws, db_name, table_name, time_column="transaction_time", full_load=False, date_format_style=None):
    # Repassando o time_column e date_format_style para a classe SQLServerCollector
    response = SQLServerCollector(
        aws_client=aws, 
        db_name=db_name, 
        table_name=table_name, 
        time_column=time_column,
        date_format_style=date_format_style
    ).start(full_load=full_load)

    if response:
        logging.info(f"Executei com sucesso (SQL Server - {db_name}.{table_name}): Arquivo salvo no S3.")
    else:
        logging.info(f"Executei (SQL Server - {db_name}.{table_name}), mas nenhum dado foi salvo.")

    return response

# ==========================================
# Rotinas em Lote (Múltiplas Tabelas)
# ==========================================

def run_tecpel_jobs(force_full_load=False):
    """
    Rotina que extrai as tabelas mapeadas do banco 'Tecpel' separando fatos e dimensões.
    """
    logging.info(f"Iniciando rotina do banco Tecpel (Force Full Load em Fatos: {force_full_load})")
    
    # 1. Tabelas Fato (Carga Incremental por padrão, a menos que force_full_load=True)
    fatos = {      
        "TITMMOV": "DATAEMISSAO",  
        "TMOV": "DATASAIDA"       
    }
    
    for tabela, coluna_data in fatos.items():
        try:
            sqlserverCollector(aws, db_name="Tecpel", table_name=tabela, time_column=coluna_data, full_load=force_full_load)
        except Exception as e:
            logging.error(f"Erro ao extrair Fato Tecpel.{tabela}: {e}")

    # 2. Tabelas Dimensão (Carga sempre Full Load, sem precisar de coluna de data)
    dimensoes = [
        "FCFO", 
        "TPRD"
    ]
    
    for tabela in dimensoes:
        try:
            sqlserverCollector(aws, db_name="Tecpel", table_name=tabela, time_column=None, full_load=True)
        except Exception as e:
            logging.error(f"Erro ao extrair Dimensão Tecpel.{tabela}: {e}")


def run_fluig_jobs(force_full_load=False):
    """
    Rotina que extrai as tabelas mapeadas do banco 'Fluig' separando fatos e dimensões.
    """
    logging.info(f"Iniciando rotina do banco Fluig (Force Full Load em Fatos: {force_full_load})")
    
    # 1. Tabelas Fato (Carga Incremental)
    fatos = {
        "ML001026": "dataEmissao",   
        "ML001094": "dataemissao"    
    }
    
    for tabela, coluna_data in fatos.items():
        try:
            # Fluig usa data no formato DD/MM/YYYY em texto, então passamos o estilo 103
            sqlserverCollector(aws, db_name="Fluig", table_name=tabela, time_column=coluna_data, full_load=force_full_load, date_format_style=103)
        except Exception as e:
            logging.error(f"Erro ao extrair Fato Fluig.{tabela}: {e}")

    # 2. Tabelas Dimensão (Sempre Full Load)
    dimensoes = [
        "ML001048"
    ]
    
    for tabela in dimensoes:
        try:
            sqlserverCollector(aws, db_name="Fluig", table_name=tabela, time_column=None, full_load=True)
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
    run_tecpel_jobs(force_full_load=False) # Exemplo: rodar manual a primeira vez
    run_fluig_jobs(force_full_load=False)  # Exemplo: rodar manual a primeira vez
    apiCollector(schema, aws, 50)   # Roda a extração da API manualmente

    
    # while True:
    #     schedule.run_pending()
    #     time.sleep(1)
