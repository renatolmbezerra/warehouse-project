{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/ZMD_CATEGORIA/slv_tecpel_zmd_categoria.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'zmd_categoria') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ID_CATEGORIA 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
