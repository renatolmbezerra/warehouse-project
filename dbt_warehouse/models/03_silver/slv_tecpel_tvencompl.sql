{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/TVENCOMPL/slv_tecpel_tvencompl.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'tvencompl') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, CODVEN 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
