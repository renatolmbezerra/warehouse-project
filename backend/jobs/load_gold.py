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
            
            # 5. Inserir os dados na tabela
            logger.info(f"[{table_name}] Iniciando inserção na tabela em lotes controlados...")
            
            # Criar a tabela vazia ou substituir a antiga enviando 0 linhas
            df.head(0).to_sql(table_name, con=engine, if_exists='replace', index=False)
            
            # Inserir os dados aos poucos
            chunk_size = 2000
            total_chunks = (len(df) // chunk_size) + 1
            
            for i in range(total_chunks):
                start_idx = i * chunk_size
                end_idx = min((i + 1) * chunk_size, len(df))
                chunk_df = df.iloc[start_idx:end_idx]
                
                if not chunk_df.empty:
                    chunk_df.to_sql(table_name, con=engine, if_exists='append', index=False)
                    logger.info(f"[{table_name}] Lote {i+1}/{total_chunks} inserido ({(end_idx/len(df))*100:.1f}%)")
                    
        logger.info("Carga de todas as tabelas Gold concluída com sucesso!")
        
    except Exception as e:
        logger.exception("Erro durante a carga da camada Gold:")

if __name__ == "__main__":
    load_gold_to_sqlserver()
