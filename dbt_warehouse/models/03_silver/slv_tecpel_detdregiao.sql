{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/DETDREGIAO/slv_tecpel_detdregiao.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'detdregiao') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, IDREGIAO, CODETD 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
