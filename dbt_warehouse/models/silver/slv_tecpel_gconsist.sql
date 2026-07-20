{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/GCONSIST/slv_tecpel_gconsist.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'gconsist') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, CODTABELA, CODCLIENTE, CODINTERNO 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
