import os
import pyodbc
import logging

logger = logging.getLogger(__name__)
from sqlalchemy import create_engine, Engine
from typing import Dict
from dotenv import load_dotenv
from pathlib import Path

# Caminho para o .env na raiz do projeto
root_dir = Path(__file__).resolve().parent.parent.parent.parent.parent
load_dotenv(dotenv_path=root_dir / ".env", override=True)

# Cache de engines mapeado pelo nome do banco de dados (db_name)
_engines: Dict[str, Engine] = {}

def get_engine(db_name: str) -> Engine:
    """
    Retorna a engine SQLAlchemy para um banco de dados específico no SQL Server.
    Utiliza cache para reaproveitar conexões.
    """
    if db_name in _engines:
        return _engines[db_name]

    # Credenciais do servidor
    DB_SERVER = os.getenv("DB_SERVER")
    DB_USER = os.getenv("DB_USER")
    DB_PASSWORD = os.getenv("DB_PASSWORD")
    DB_DRIVER = os.getenv("DB_DRIVER")

    if not all([DB_SERVER, DB_USER, DB_PASSWORD, DB_DRIVER]):
        raise ValueError("Variáveis de ambiente do servidor SQL não estão totalmente definidas.")

    conn_str = (
        f"DRIVER={{{DB_DRIVER}}};"
        f"SERVER={DB_SERVER};"
        f"DATABASE={db_name};" # Única parte que varia por banco
        f"UID={DB_USER};"
        f"PWD={DB_PASSWORD};"
        f"TrustServerCertificate=yes;"
    )

    engine = create_engine(
        "mssql+pyodbc://",
        creator=lambda: pyodbc.connect(conn_str),
        pool_pre_ping=True,
        fast_executemany=True # Otimização extrema para Bulk Inserts em Pandas
    )
    
    _engines[db_name] = engine
    return engine

# Teste de conexao com o bancos de dados
if __name__ == "__main__":
    from sqlalchemy import text
    
    databases_test = ["Tecpel", "Fluig"]
    
    for database in databases_test:
        try:
            logger.info(f"Tentando conectar ao banco de dados: {database}...")
            engine_banco = get_engine(database)
            
            with engine_banco.connect() as connection:
                result = connection.execute(text("SELECT 1"))
                logger.info(f"[SUCESSO] Conexão com '{database}' estabelecida! (SELECT 1 retornou: {result.scalar()})")
                
        except Exception as e:
            logger.exception(f"Falha ao conectar em '{database}'")
