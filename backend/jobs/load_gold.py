import io
import sys
import os
from pathlib import Path
import pandas as pd

project_root = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(project_root))

import logging
from backend.tools.aws.client import S3Client
from backend.tools.sql.db.database_connection import get_engine
from dotenv import load_dotenv
from sqlalchemy import text

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

load_dotenv(override=True)

# Dicionário de Chaves Primárias para o MERGE Incremental
PK_DICT = {
    'gld_dim_cliente': ['CODCOLIGADA', 'CODCFO'],
    'gld_dim_local_estoque': ['CODCOLIGADA', 'CODFILIAL', 'CODLOC'],
    'gld_dim_produto': ['CODCOLIGADA', 'IDPRD'],
    'gld_dim_tipo_movimento': ['CODCOLIGADA', 'CODTMV'],
    'gld_dim_vendedor': ['CODCOLIGADA', 'CODVEN'],
    'gld_fct_estoque': ['CODCOLIGADA', 'IDPRD', 'CODLOC', 'CODFILIAL', 'DATA_SALDO'],
    'gld_fct_vendas_itens': ['CODCOLIGADA', 'IDMOV', 'NSEQITMMOV'],
    'gld_fct_prazo_medio': ['CODCOLIGADA', 'IDMOV'],
    'gld_api_compras': ['ean', 'loja', 'data_compra'],
    'gld_fct_impostos_item': ['CODCOLIGADA', 'IDMOV', 'NSEQITMMOV']
}

def load_gold_to_sqlserver():
    try:
        aws = S3Client()
        
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
            
        db_name = "DW_Tecpel"
        logger.info(f"Conectando ao banco de dados destino: {db_name}...")
        engine = get_engine(db_name)
        
        for s3_key in parquet_files:
            table_name = s3_key.split('/')[-1].replace('.parquet', '')
            
            logger.info(f"Baixando {s3_key} do S3...")
            file_obj = aws.download_file(s3_key)
            if not file_obj:
                continue
                
            df = pd.read_parquet(io.BytesIO(file_obj['Body'].read()))
            logger.info(f"[{table_name}] DataFrame carregado com {len(df)} linhas.")
            
            # --- Tratamento de Segurança PyODBC ---
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
            
            table_pk = PK_DICT.get(table_name)
            
            # Watermark: descobrir a última data no SQL Server
            max_date = None
            if 'dt_extracao' in df.columns:
                try:
                    with engine.connect() as conn:
                        max_date_val = conn.execute(text(f"SELECT MAX(dt_extracao) FROM {table_name}")).fetchone()[0]
                        if max_date_val:
                            max_date = pd.to_datetime(max_date_val)
                except Exception:
                    pass

            load_mode = 'replace'
            df_to_load = df
            
            if max_date and table_pk:
                logger.info(f"[{table_name}] Watermark detectado: {max_date}. Filtrando apenas Deltas...")
                df['dt_extracao'] = pd.to_datetime(df['dt_extracao'])
                
                # Se a tabela usa timezone, converte para ingênuo ou ajusta
                if df['dt_extracao'].dt.tz is not None and max_date.tzinfo is None:
                    max_date = max_date.tz_localize(df['dt_extracao'].dt.tz)
                    
                df_to_load = df[df['dt_extracao'] > max_date]
                
                if df_to_load.empty:
                    logger.info(f"[{table_name}] Nenhum dado novo desde a última carga. Pulando...")
                    continue
                load_mode = 'merge'
                
            if load_mode == 'replace':
                logger.info(f"[{table_name}] Iniciando carga Full Overwrite ({len(df_to_load)} linhas)...")
                df_to_load.to_sql(table_name, con=engine, if_exists='replace', index=False, chunksize=100000)
                
                # Cria o índice só na carga full
                with engine.begin() as conn:
                    try:
                        conn.execute(text(f"CREATE CLUSTERED COLUMNSTORE INDEX CCI_{table_name} ON {table_name}"))
                        logger.info(f"[{table_name}] Índice Columnstore criado com sucesso!")
                    except Exception as idx_err:
                        pass
            else:
                logger.info(f"[{table_name}] Iniciando carga Incremental ({len(df_to_load)} linhas) via MERGE...")
                temp_table = f"stg_{table_name}"
                
                # Joga na staging table do SQL Server
                df_to_load.to_sql(temp_table, con=engine, if_exists='replace', index=False, chunksize=100000)
                
                join_cond = " AND ".join([f"Target.{pk} = Source.{pk}" for pk in table_pk])
                update_cols = [col for col in df_to_load.columns if col not in table_pk]
                
                if update_cols:
                    update_set = ", ".join([f"Target.{col} = Source.{col}" for col in update_cols])
                    update_stmt = f"WHEN MATCHED THEN UPDATE SET {update_set}"
                else:
                    update_stmt = ""
                    
                insert_cols = ", ".join(df_to_load.columns)
                insert_vals = ", ".join([f"Source.{col}" for col in df_to_load.columns])
                
                merge_sql = f"""
                MERGE {table_name} AS Target
                USING {temp_table} AS Source
                ON {join_cond}
                {update_stmt}
                WHEN NOT MATCHED BY TARGET THEN
                    INSERT ({insert_cols})
                    VALUES ({insert_vals});
                """
                
                with engine.begin() as conn:
                    conn.execute(text(merge_sql))
                    conn.execute(text(f"DROP TABLE {temp_table}"))
                    
                logger.info(f"[{table_name}] MERGE concluído com sucesso!")
                    
        logger.info("ETAPA 3 CONCLUÍDA: Carga final no SQL Server (Load Gold) finalizada com sucesso! PIPELINE FINALIZADA!")
        
    except Exception as e:
        logger.exception("Erro durante a carga da camada Gold:")

if __name__ == "__main__":
    load_gold_to_sqlserver()
