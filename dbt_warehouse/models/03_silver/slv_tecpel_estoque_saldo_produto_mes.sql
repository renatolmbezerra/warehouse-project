{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/ESTOQUE_SALDO_PRODUTO_MES/slv_tecpel_estoque_saldo_produto_mes.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'estoque_saldo_produto_mes') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODFILIAL, CODLOC, IDPRD, DATA_SALDO 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
