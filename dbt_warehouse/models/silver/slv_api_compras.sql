{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/api/fakeapi/slv_api_compras.parquet"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_api', 'compras') }}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ean, store, dateTime 
        ORDER BY dateTime DESC
    ) = 1
)

SELECT * FROM deduplicated
