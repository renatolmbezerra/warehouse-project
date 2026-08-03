{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/03_silver/sqlserver/Tecpel/DETDREGIAO/slv_tecpel_detdregiao.parquet"
) }}

SELECT *
FROM {{ source('bronze_tecpel', 'detdregiao') }}
