{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/CLIENTESAB_DTBASE/slv_tecpel_clientesab_dtbase.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'clientesab_dtbase') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY IDLAN, DATA_COMPETENCIA 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
