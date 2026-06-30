import requests
import pandas as pd
import pyarrow.parquet as pq
import datetime
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
            print("Nenhum dado válido para processar.")
            return False
        
        df = self.transformDF(extracted)
        parquet_buffer = self.convertToParquet(df)

        if parquet_buffer is not None:
            file_name = self.fileName()
            print(f"Salvando arquivo: {file_name}")
            self._aws.upload_file(parquet_buffer, file_name)
            return True

        return False

    def getData(self, param):
        if param > 1:
            url = f"http://127.0.0.1:8000/gerar_compras/{param}"
        else:
            url = f"http://127.0.0.1:8000/gerar_compra"

        try:
            response = requests.get(url)
            if response.status_code == 200:
                return response.json()
            else:
                print(f"Erro na API! Status: {response.status_code} | Resposta: {response.text}")
                return []
        except requests.exceptions.ConnectionError:
            print(f"Erro de Conexão: A API no endereço {url} está desligada.")
            return []
        except Exception as e:
            print(f"Erro inesperado: {e}")
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
                print(f"Erro de validação no item {item}:")
                print(e.errors())
        return result

    def transformDF(self, response):
        result = pd.DataFrame(response)
        return result

    def convertToParquet(self, df):
        self._buffer = BytesIO()
        try:
            df.to_parquet(self._buffer)
            self._buffer.seek(0) # Retorna o ponteiro do buffer para o início
            return self._buffer
        except Exception as e:
            print(f"Erro ao transformar o DF em parquet: {e} ")
            return None

    def fileName(self):
        data_atual = datetime.datetime.now().isoformat() 
        match = data_atual.split(".")
        return f"api/api-response-compra/{match[0]}.parquet"
        
