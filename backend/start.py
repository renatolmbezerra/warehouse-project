from datasource.api import APICollector
from dotenv import load_dotenv
from contracts.schema import CompraSchema
from tools.aws.client import S3Client

import time
import schedule

# Carrega as variáveis do arquivo .env para o sistema
load_dotenv()

schema = CompraSchema
aws = S3Client()

def apiCollector(schema, aws, repeat):
    response = APICollector(schema, aws).start(repeat)

    if response:
        print(f"[{time.strftime('%H:%M:%S')}] Executei com sucesso: Arquivo salvo no S3.")
    else:
        print(f"[{time.strftime('%H:%M:%S')}] Executei, mas nenhum dado foi salvo (vazio ou erro).")

    return response

# Agenda a execução a cada 1 minuto passando o parâmetro 50
schedule.every(1).minutes.do(apiCollector, schema, aws, 50)

print("Iniciando o agendador. Pressione Ctrl+C para sair.")

while True:
    schedule.run_pending()
    time.sleep(1)


