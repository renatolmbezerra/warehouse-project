{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/TTB2/slv_tecpel_ttb2.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'ttb2') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, CODTB2FAT 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
