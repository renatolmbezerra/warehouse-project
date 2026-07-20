{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/TMARCA/slv_tecpel_tmarca.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'tmarca') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, IDMARCA 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
