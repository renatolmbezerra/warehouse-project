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
        
        # 1. Baixar o arquivo Parquet do S3 para a memória
        s3_key = "gold/sqlserver/Tecpel/gld_fct_vendas_itens.parquet"
        logger.info(f"Baixando {s3_key} do S3...")
        
        file_obj = aws.download_file(s3_key)
        if not file_obj:
            logger.error("Arquivo não encontrado no S3.")
            return
            
        # 2. Ler o Parquet usando Pandas direto da memória (BytesIO)
        logger.info("Lendo arquivo Parquet para DataFrame Pandas...")
        df = pd.read_parquet(io.BytesIO(file_obj['Body'].read()))
        logger.info(f"DataFrame carregado com {len(df)} linhas e {len(df.columns)} colunas.")
        
        # 3. Conectar ao Data Warehouse no SQL Server
        db_name = "DW_Tecpel"
        logger.info(f"Conectando ao banco de dados destino: {db_name}...")
        engine = get_engine(db_name)
        
        # 4. Inserir os dados na tabela
        table_name = "fct_vendas"
        logger.info(f"Iniciando inserção na tabela {table_name} em lotes controlados...")
        
        # Primeiro, criamos a tabela vazia ou substituímos a antiga (if_exists='replace') enviando 0 linhas
        df.head(0).to_sql(table_name, con=engine, if_exists='replace', index=False)
        
        # Agora inserimos os dados aos poucos (append) para não travar a memória RAM, e mostramos o progresso
        chunk_size = 2000
        total_chunks = (len(df) // chunk_size) + 1
        
        for i in range(total_chunks):
            start_idx = i * chunk_size
            end_idx = min((i + 1) * chunk_size, len(df))
            chunk_df = df.iloc[start_idx:end_idx]
            
            if not chunk_df.empty:
                chunk_df.to_sql(table_name, con=engine, if_exists='append', index=False)
                logger.info(f"Lote {i+1}/{total_chunks} inserido com sucesso ({(end_idx/len(df))*100:.1f}%)")
                
        logger.info("Carga concluída com sucesso!")
        
    except Exception as e:
        logger.exception("Erro durante a carga da camada Gold:")

if __name__ == "__main__":
    load_gold_to_sqlserver()
