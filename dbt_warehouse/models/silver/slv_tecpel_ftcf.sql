{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/slv_tecpel_ftcf.parquet"
) }}

SELECT *
FROM {{ source('bronze_tecpel', 'ftcf') }}
