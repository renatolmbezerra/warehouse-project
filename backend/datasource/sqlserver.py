import pandas as pd
import logging
from backend.tools.sql.db.database_connection import get_engine

logger = logging.getLogger(__name__)
import datetime
from io import BytesIO
from backend.tools.aws.client import S3Client


class SQLServerCollector:
    def __init__(
        self,
        aws_client: S3Client,
        db_name: str,
        table_name: str,
        time_column: str = "transaction_time",
        date_format_style: int = None,
        custom_where: str = None,
    ):
        self.db_name = db_name
        self.table_name = table_name
        self.time_column = (
            time_column  # Coluna usada para filtrar os 3 dias da janela incremental
        )
        self.date_format_style = date_format_style
        self.custom_where = custom_where
        self._buffer = None
        self._aws = aws_client

    def start(self, full_load: bool = False):
        """
        Inicia o processo de extração.
        Se full_load=True, traz a tabela inteira.
        Se full_load=False (padrão), traz a janela incremental de 3 dias.
        """
        df = self.extract_data(full_load)
        if df.empty:
            logger.warning(
                f"Nenhum dado encontrado para {self.db_name}.{self.table_name}"
            )
            return False

        num_chunks = (len(df) + 99999) // 100000
        logger.info(
            f"Extração concluída. Linhas processadas: {len(df)} (em {num_chunks} lotes)"
        )
        df = self.transform_add_columns(df, f"sqlserver-{self.db_name.lower()}")
        logger.info("Processo transform com sucesso")
        
        try:
            self.write_to_s3_parquet(df, full_load)
            return True
        except Exception as e:
            logger.error(f"Erro ao escrever arquivo Parquet: {e}")
            return False

    def extract_data(self, full_load: bool) -> pd.DataFrame:
        engine = get_engine(self.db_name)

        if full_load:
            # Carga Full: traz a tabela completa
            query = f"SELECT * FROM {self.table_name}"
        else:
            # Carga Incremental: janela de 3 dias usando SQL Server syntax ou custom_where
            if self.custom_where:
                query = f"SELECT * FROM {self.table_name} WHERE {self.custom_where}"
            else:
                time_expr = self.time_column
                if self.date_format_style is not None:
                    time_expr = f"TRY_CONVERT(DATETIME, {self.time_column}, {self.date_format_style})"

                query = f"SELECT * FROM {self.table_name} WHERE {time_expr} >= DATEADD(day, -3, GETDATE())"

        logger.info(f"Executando query: {query}")

        # Leitura em lotes (chunks) previne erros de Timeout (10054) em tabelas massivas (ex: FLAN, TITMMOV)
        try:
            chunks = []
            for chunk in pd.read_sql(query, con=engine, chunksize=100000):
                chunks.append(chunk)
                logger.debug(
                    f"Lote de {len(chunk)} linhas lido da tabela {self.table_name}..."
                )

            if not chunks:
                return pd.DataFrame()

            return pd.concat(chunks, ignore_index=True)
        except Exception as e:
            logger.error(f"Erro crítico durante a extração: {e}")
            raise

    def transform_add_columns(
        self, df: pd.DataFrame, datasource_value: str
    ) -> pd.DataFrame:
        df = (
            df.copy()
        )  # Desfragmenta a memória após o concat e evita o PerformanceWarning
        df["dt_extracao"] = datetime.datetime.now().isoformat()
        df["datasource"] = datasource_value
        return df

    def write_to_s3_parquet(self, df: pd.DataFrame, full_load: bool):
        import datetime
        from io import BytesIO
        
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        suffix = "full" if full_load else "incremental"
        s3_path = f"02_bronze/sqlserver/{self.db_name}/{self.table_name}/{self.table_name}_{suffix}_{timestamp}.parquet"
        
        logger.info(f"Escrevendo no formato Parquet (Append-Only) em {s3_path}")
        
        buffer = BytesIO()
        df.to_parquet(buffer, index=False)
        self._aws.upload_file(buffer, s3_path)
