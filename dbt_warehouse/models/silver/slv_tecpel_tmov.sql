{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/TMOV/slv_tecpel_tmov.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'tmov') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, IDMOV 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
