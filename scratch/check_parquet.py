import pandas as pd
from backend.tools.aws.client import S3Client
from io import BytesIO

def check_types():
    aws = S3Client()
    print("Baixando gld_dim_cliente.parquet...")
    file_obj = aws.s3.get_object(Bucket=aws._envs['s3_bucket'], Key='04_gold/sqlserver/Tecpel/gld_dim_cliente.parquet')
    df = pd.read_parquet(BytesIO(file_obj['Body'].read()))
    
    print("\n--- Tipos de dados (pandas) ---")
    print(df.dtypes)
    
    print("\n--- Analisando colunas do tipo 'object' ---")
    for col in df.select_dtypes(include=['object']).columns:
        sample = df[col].dropna().head(1)
        if len(sample) > 0:
            val = sample.iloc[0]
            print(f"{col}: tipo interno = {type(val)}")

if __name__ == "__main__":
    check_types()
