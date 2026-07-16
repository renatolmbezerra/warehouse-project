import pandas as pd
import logging
from backend.tools.sql.db.database_connection import get_engine

logger = logging.getLogger(__name__)
import datetime
from io import BytesIO
from backend.tools.aws.client import S3Client

class SQLServerCollector:
    def __init__(self, aws_client: S3Client, db_name: str, table_name: str, time_column: str = "transaction_time", date_format_style: int = None):
        self.db_name = db_name
        self.table_name = table_name
        self.time_column = time_column # Coluna usada para filtrar os 30 dias
        self.date_format_style = date_format_style
        self._buffer = None
        self._aws = aws_client

    def start(self, full_load: bool = False):
        """
        Inicia o processo de extração.
        Se full_load=True, traz a tabela inteira.
        Se full_load=False (padrão), traz a janela incremental de 30 dias.
        """
        df = self.extract_data(full_load)
        if df.empty:
            logger.warning(f"Nenhum dado encontrado para {self.db_name}.{self.table_name}")
            return False

        logger.info(f"Extração concluída. Linhas processadas: {len(df)}")
        df = self.transform_add_columns(df, "sqlserver")
        logger.info("Processo transform com sucesso")
        self.convert_to_delta(df)

        if self._buffer is not None:
            file_name = self.generate_file_name(full_load)
            logger.info(f"Enviando para S3: {file_name}")
            self._aws.upload_file(self._buffer, file_name)
            return True

        return False

    def extract_data(self, full_load: bool) -> pd.DataFrame:
        engine = get_engine(self.db_name)
        
        if full_load:
            # Carga Full: traz a tabela completa
            query = f"SELECT * FROM {self.table_name}"
        else:
            # Carga Incremental: janela de 7 dias usando SQL Server syntax
            time_expr = self.time_column
            if self.date_format_style is not None:
                time_expr = f"TRY_CONVERT(DATETIME, {self.time_column}, {self.date_format_style})"
            
            query = f"SELECT * FROM {self.table_name} WHERE {time_expr} >= DATEADD(day, -7, GETDATE())"
            
        logger.debug(f"Executando query: {query}")
        return pd.read_sql(query, con=engine)

    def transform_add_columns(self, df: pd.DataFrame, datasource_value: str) -> pd.DataFrame:
        df["dt_extracao"] = datetime.datetime.now().isoformat()
        df["datasource"] = datasource_value
        return df

    def convert_to_delta(self, df: pd.DataFrame):
        try:
            # Converte o DataFrame do pandas para formato Parquet e joga no buffer
            self._buffer = BytesIO()
            df.to_parquet(self._buffer, index=False)
        except Exception as e:
            logger.exception("Erro ao converter DataFrame para Parquet")
            self._buffer = None

    def generate_file_name(self, full_load: bool) -> str:
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        prefix = "full" if full_load else "incremental"
        return f"bronze/sqlserver/{self.db_name}/{self.table_name}/{prefix}_{timestamp}.parquet"
