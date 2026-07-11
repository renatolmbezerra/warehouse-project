import os
import sys
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker


def getDbConnectionById(id: int):
    configs = {
        "DB_USER": os.getenv(f"DB_USER{id}"),
        "DB_PASSWORD": os.getenv(f"DB_PASSWORD{id}"),
        "DB_HOST": os.getenv(f"DB_HOST{id}"),
        "DB_NAME": os.getenv(f"DB_NAME{id}"),
        "DB_DRIVER": os.getenv(f"DB_DRIVER{id}", "ODBC Driver 18 for SQL Server"),
    }

    for var in configs:
        if configs[var] is None:
            print(f"A variável de ambiente {var} não está definida.")
            sys.exit(1)

    # Adicionado TrustServerCertificate=yes para evitar problemas com certificados no Driver 18
    driver_param = configs['DB_DRIVER'].replace(" ", "+")
    DATABASE_URI = f"mssql+pyodbc://{configs['DB_USER']}:{configs['DB_PASSWORD']}@{configs['DB_HOST']}/{configs['DB_NAME']}?driver={driver_param}&TrustServerCertificate=yes"

    engine = create_engine(DATABASE_URI)
    Session = sessionmaker(bind=engine)
    return Session()