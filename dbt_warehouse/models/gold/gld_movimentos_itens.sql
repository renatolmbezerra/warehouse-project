{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/gold/sqlserver/Tecpel/gld_movimentos_itens.parquet"
) }}

WITH tmov AS (
    SELECT * FROM {{ ref('slv_tecpel_tmov') }}
),

titmmov AS (
    SELECT * FROM {{ ref('slv_tecpel_titmmov') }}
)

SELECT 
    t.CODCOLIGADA,
    t.IDMOV,
    t.NUMEROMOV,
    t.DATAEMISSAO,
    t.VALORBRUTO,
    i.IDPRD,
    i.QUANTIDADE,
    i.PRECOUNITARIO
FROM tmov t
INNER JOIN titmmov i
    ON t.CODCOLIGADA = i.CODCOLIGADA
    AND t.IDMOV = i.IDMOV
LIMIT 1000
