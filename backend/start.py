from datasource.api import APICollector
from contracts.schema import CompraShema

schema = CompraShema

minha_classe = APICollector(schema).start(5)

print(minha_classe)