{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/TRELSLD/slv_tecpel_trelsld.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'trelsld') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, IDPRD, CODLOC, DATAMOVIMENTO, SEQUENCIAL 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
