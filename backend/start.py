from datasource.api import APICollector
from dotenv import load_dotenv
from contracts.schema import CompraShema
from tools.aws.client import S3Client

import schedule

# Carrega as variáveis do arquivo .env para o sistema
load_dotenv()

schema = CompraShema
aws = S3Client()

minha_classe = APICollector(schema, aws).start(5)

print(minha_classe)
