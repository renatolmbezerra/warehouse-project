{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/TTB4/slv_tecpel_ttb4.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'ttb4') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, CODTB4FAT 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
