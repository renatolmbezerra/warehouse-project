from datasource.api import APICollector
from dotenv import load_dotenv
from contracts.schema import CompraShema
from tools.aws.client import S3Client

import time
import schedule

# Carrega as variáveis do arquivo .env para o sistema
load_dotenv()

schema = CompraShema
aws = S3Client()

def apiCollector(schema, aws, repeat):
    response = APICollector(schema, aws).start(repeat)
    print('Executei')
    return response

schedule.every(1).minutes.do(apiCollector, schema, aws, 50)

while True:
    schedule.run_pending()
    time.sleep(1)


