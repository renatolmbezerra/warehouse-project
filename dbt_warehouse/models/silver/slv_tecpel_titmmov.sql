{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    format='iceberg',
    unique_key=['CODCOLIGADA', 'IDMOV', 'NSEQITMMOV'],
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/TITMMOV"
) }}

WITH source AS (
    SELECT *
    FROM {{ source('bronze_tecpel', 'titmmov') }}
    
    {% if is_incremental() %}
    -- Lê apenas os dados da Bronze extraídos após a última carga desta tabela Silver
    WHERE dt_extracao > (SELECT MAX(dt_extracao) FROM {{ this }})
    {% endif %}
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
