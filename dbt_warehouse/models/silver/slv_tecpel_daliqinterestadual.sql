{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/DALIQINTERESTADUAL/slv_tecpel_daliqinterestadual.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'daliqinterestadual') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CODCOLIGADA, CODETDORIGEM, CODETDDESTINO 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
