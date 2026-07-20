{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/FLAN/slv_tecpel_flan.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'flan') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, IDLAN 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
