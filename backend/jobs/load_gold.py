import io
import sys
import os
from pathlib import Path
import pandas as pd

# Adiciona a raiz do projeto no path para que os imports 'backend.x' funcionem
project_root = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(project_root))

import logging
from backend.tools.aws.client import S3Client
from backend.tools.sql.db.database_connection import get_engine
from dotenv import load_dotenv

# Configuração básica de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Carrega as variáveis de ambiente (necessário para o S3Client e get_engine)
load_dotenv(override=True)

def load_gold_to_sqlserver():
    try:
        aws = S3Client()
        
        # 1. Listar todos os arquivos da camada Gold no S3
        prefix = "04_gold/"
        logger.info(f"Listando arquivos Parquet no prefixo {prefix}...")
        
        try:
            objects = aws.list_object(prefix)
        except KeyError:
            logger.warning(f"Nenhum arquivo encontrado no prefixo {prefix}.")
            return
            
        parquet_files = [obj['Key'] for obj in objects if obj['Key'].endswith('.parquet')]
        
        if not parquet_files:
            logger.warning("Nenhum arquivo Parquet encontrado na camada Gold.")
            return
            
        # 2. Conectar ao Data Warehouse no SQL Server
        db_name = "DW_Tecpel"
        logger.info(f"Conectando ao banco de dados destino: {db_name}...")
        engine = get_engine(db_name)
        
        for s3_key in parquet_files:
            # Extrair o nome da tabela a partir do nome do arquivo (ex: gld_dim_cliente.parquet -> gld_dim_cliente)
            table_name = s3_key.split('/')[-1].replace('.parquet', '')
            
            # 3. Baixar o arquivo Parquet do S3 para a memória
            logger.info(f"Baixando {s3_key} do S3...")
            file_obj = aws.download_file(s3_key)
            if not file_obj:
                logger.error(f"Não foi possível baixar o arquivo {s3_key}.")
                continue
                
            # 4. Ler o Parquet usando Pandas direto da memória (BytesIO)
            df = pd.read_parquet(io.BytesIO(file_obj['Body'].read()))
            logger.info(f"[{table_name}] DataFrame carregado com {len(df)} linhas e {len(df.columns)} colunas.")
            
            # --- Tratamento de Segurança PyODBC ---
            # Previne o erro f405 do Bulk Insert (fast_executemany) que quebra com Decimals e NaNs
            import decimal
            import numpy as np
            for col in df.columns:
                if df[col].dtype == 'object':
                    sample = df[col].dropna().head(1)
                    if len(sample) > 0 and isinstance(sample.iloc[0], decimal.Decimal):
                        df[col] = df[col].astype('float64')
                    else:
                        df[col] = df[col].replace({np.nan: None})
            # ----------------------------------------
            
            # 5. Inserir os dados na tabela
            logger.info(f"[{table_name}] Iniciando inserção de alta performance (Bulk Insert)...")
            
            # Grava o dataframe todo usando o motor binário do pyodbc, quebrando apenas a cada 100 mil registros para evitar timeout
            df.to_sql(table_name, con=engine, if_exists='replace', index=False, chunksize=100000)
            logger.info(f"[{table_name}] Inserção concluída com sucesso!")
            
            # 6. Criar Índice Columnstore para Alta Performance Analítica (OLAP)
            from sqlalchemy import text
            with engine.connect() as conn:
                try:
                    logger.info(f"[{table_name}] Criando Clustered Columnstore Index...")
                    conn.execute(text(f"CREATE CLUSTERED COLUMNSTORE INDEX CCI_{table_name} ON {table_name}"))
                    conn.commit()
                    logger.info(f"[{table_name}] Índice Columnstore criado com sucesso!")
                except Exception as idx_err:
                    logger.warning(f"[{table_name}] Aviso: Não foi possível criar o índice Columnstore: {idx_err}")
                    
        logger.info("Carga de todas as tabelas Gold concluída com sucesso!")
        
    except Exception as e:
        logger.exception("Erro durante a carga da camada Gold:")

if __name__ == "__main__":
    load_gold_to_sqlserver()
