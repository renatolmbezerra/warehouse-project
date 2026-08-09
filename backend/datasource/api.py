import requests
import pandas as pd
import pyarrow.parquet as pq
import datetime
import logging
import json
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
        
        if response:
            # Salva o arquivo Raw no S3 antes de qualquer transformação
            raw_buffer = BytesIO(json.dumps(response).encode('utf-8'))
            data_atual = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            raw_file_name = f"01_raw/api/fakeapi/compras/incremental_{data_atual}.json"
            logging.info(f"Salvando arquivo Raw: {raw_file_name}")
            self._aws.upload_file(raw_buffer, raw_file_name)

        extracted = self.extractData(response)

        # Se não houver dados válidos, aborta para não gerar parquet vazio
        if not extracted:
            logging.info("Nenhum dado válido para processar.")
            return False
        
        df = self.transformDF(extracted)
        
        try:
            self.write_to_s3_parquet(df)
            return True
        except Exception as e:
            logging.error(f"Erro ao escrever arquivo Parquet: {e}")
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
            result["datasource"] = "api-fakeapi"
        return result

    def write_to_s3_parquet(self, df):
        import os
        import datetime
        from io import BytesIO
        
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        s3_path = f"02_bronze/api/fakeapi/compras/compras_{timestamp}.parquet"
        
        logging.info(f"Escrevendo no formato Parquet (Append-Only) em {s3_path}")
        
        buffer = BytesIO()
        df.to_parquet(buffer, index=False)
        self._aws.upload_file(buffer, s3_path)
