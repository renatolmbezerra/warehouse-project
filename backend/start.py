from datasource.api import APICollector
from dotenv import load_dotenv
from contracts.schema import CompraSchema
from tools.aws.client import S3Client

import time
import schedule
import logging

# Configuração básica de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Carrega as variáveis do arquivo .env para o sistema
load_dotenv()

schema = CompraSchema
aws = S3Client()

def apiCollector(schema, aws, repeat):
    response = APICollector(schema, aws).start(repeat)

    if response:
        logging.info("Executei com sucesso: Arquivo salvo no S3.")
    else:
        logging.info("Executei, mas nenhum dado foi salvo (vazio ou erro).")

    return response

# Agenda a execução a cada 1 minuto passando o parâmetro 50
schedule.every(1).minutes.do(apiCollector, schema, aws, 50)

logging.info("Iniciando o agendador. Pressione Ctrl+C para sair.")

while True:
    schedule.run_pending()
    time.sleep(1)


