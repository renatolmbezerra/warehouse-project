import requests
import pandas as pd
import pyarrow.parquet as pq
import datetime
import logging
import os
from io import BytesIO
from pydantic import ValidationError
# from contracts.schema import GenericSchema, CompraShema
# from typing import List


class APICollector:
    def __init__(self, schema, aws):
        self._schema = schema
        self._aws = aws
        self._buffer = None

    def start(self, param):
        response = self.getData(param)
        extracted = self.extractData(response)

        # Se não houver dados válidos, aborta para não gerar parquet vazio
        if not extracted:
            logging.info("Nenhum dado válido para processar.")
            return False
        
        df = self.transformDF(extracted)
        parquet_buffer = self.convertToParquet(df)

        if parquet_buffer is not None:
            file_name = self.fileName()
            logging.info(f"Salvando arquivo: {file_name}")
            self._aws.upload_file(parquet_buffer, file_name)
            return True

        return False

    def getData(self, param):
        base_url = os.environ.get("API_BASE_URL", "http://127.0.0.1:8000")
        if param > 1:
            url = f"{base_url}/gerar_compras/{param}"
        else:
            url = f"{base_url}/gerar_compra"

        try:
            response = requests.get(url)
            if response.status_code == 200:
                return response.json()
            else:
                logging.error(f"Erro na API! Status: {response.status_code} | Resposta: {response.text}")
                return []
        except requests.exceptions.ConnectionError:
            logging.error(f"Erro de Conexão: A API no endereço {url} está desligada.")
            return []
        except Exception as e:
            logging.error(f"Erro inesperado: {e}")
            return []

    def extractData(self, response):
        result = []

        if isinstance(response, dict):
            response = [response]

        for item in response:
            try:
                # O Pydantic valida o dicionário aqui
                validated_item = self._schema(**item)
                # .model_dump() converte o objeto Pydantic de volta para dicionário
                result.append(validated_item.model_dump())
            except ValidationError as e:
                logging.error(f"Erro de validação no item {item}:")
                logging.error(e.errors())
        return result

    def transformDF(self, response):
        result = pd.DataFrame(response)
        if not result.empty:
            result["dt_extracao"] = datetime.datetime.now().isoformat()
            result["datasource"] = "fakeapi"
        return result

    def convertToParquet(self, df):
        self._buffer = BytesIO()
        try:
            df.to_parquet(self._buffer)
            self._buffer.seek(0) # Retorna o ponteiro do buffer para o início
            return self._buffer
        except Exception as e:
            logging.error(f"Erro ao transformar o DF em parquet: {e} ")
            return None

    def fileName(self):
        data_atual = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        # Padronizando com a camada Bronze: bronze/<origem>/<sistema_ou_banco>/<tabela_ou_endpoint>/prefixo_timestamp.parquet
        return f"bronze/api/fakeapi/compras/incremental_{data_atual}.parquet"
