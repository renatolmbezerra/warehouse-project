from datasource.api import APICollector
from contracts.schema import CompraShema
from tools.aws.client import S3Client

import schedule

schema = CompraShema
aws = S3Client()

minha_classe = APICollector(schema, aws).start(5)

print(minha_classe)
