from pydantic import BaseModel, PositiveFloat
from datetime import datetime


class CompraSchema(BaseModel):
    ean: int
    price: PositiveFloat
    store: int
    dateTime: datetime
