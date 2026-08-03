{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/TTRBMOV/slv_tecpel_ttrbmov.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'ttrbmov') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, IDMOV, NSEQITMMOV, CODTRB 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
