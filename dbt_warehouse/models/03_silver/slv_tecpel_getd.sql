{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/GETD/slv_tecpel_getd.parquet"
) }}

SELECT *
FROM {{ source('bronze_tecpel', 'getd') }}
