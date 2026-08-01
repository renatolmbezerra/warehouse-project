{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/slv_tecpel_clientesab_dtbase.parquet"
) }}

SELECT *
FROM {{ source('bronze_tecpel', 'clientesab_dtbase') }}
