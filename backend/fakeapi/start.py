from fastapi import FastAPI
from faker import Faker
import pandas as pd


app = FastAPI()
fake = Faker()

file_name = 'backend/fakeapi/products.csv'
df = pd.read_csv(file_name)

lojapadraoonline = 11

@app.get("/gerar_compra") # Rota para gerar única linha
async def gerar_compra():
    row = df.sample(n=1).iloc[0]
    return [{
            "client": fake.name(),
            "creditcard": fake.credit_card_provider(),
            "product": row["Product Name"],
            "ean": int(row["EAN"]),
            "price":  round(float(row["Price"])*1.2,2),
            "clientPosition": fake.location_on_land(),
            "store": lojapadraoonline,
            "dateTime": fake.iso8601()
        }]

@app.get("/gerar_compras/{numero_registro}") # Rota para trazer a quantidade de linhas de acordo com o parametro passado
async def gerar_compra(numero_registro: int):
    
    if numero_registro < 1:
        return {"error" : "O número deve ser maior que 1"}
    
    respostas = []

 

    for _ in range(numero_registro):
        row = df.sample(n=1).iloc[0]
        compra = {
                "client": fake.name(),
                "creditcard": fake.credit_card_provider(),
                "product": row["Product Name"],
                "ean": int(row["EAN"]),
                "price":  round(float(row["Price"])*1.2,2),
                # "price":  "hoje é de graça",
                "clientPosition": fake.location_on_land(),
                "store": lojapadraoonline,
                "dateTime": fake.iso8601()
                }
        respostas.append(compra)
        
    return respostas