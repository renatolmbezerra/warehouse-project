{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/TITMMOVCOMPL/slv_tecpel_titmmovcompl.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'titmmovcompl') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, IDMOV, NSEQITMMOV 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
