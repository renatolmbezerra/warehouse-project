from fastapi import FastAPI


app = FastAPI()


@app.get("/gerar_compra")
async def gerar_compra():
    return 