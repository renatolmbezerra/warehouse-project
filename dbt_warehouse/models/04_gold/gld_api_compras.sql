{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/04_gold/api/fakeapi/gld_api_compras.parquet"
) }}

WITH silver AS (
    SELECT *
    FROM {{ ref('slv_api_compras') }}
)

SELECT 
    ean,
    price AS preco,
    store AS loja,
    CAST(dateTime AS TIMESTAMP) AS data_compra,
    dt_extracao,
    datasource
FROM silver
