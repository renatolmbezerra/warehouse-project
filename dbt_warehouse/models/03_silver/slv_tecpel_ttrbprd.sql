{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/TTRBPRD/slv_tecpel_ttrbprd.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'ttrbprd') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, IDPRD, CODTRB 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
