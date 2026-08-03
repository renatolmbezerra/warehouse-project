{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/TLOC/slv_tecpel_tloc.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'tloc') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, CODFILIAL, CODLOC 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
