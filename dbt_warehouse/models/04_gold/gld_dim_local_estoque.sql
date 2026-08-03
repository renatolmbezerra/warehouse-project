{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/04_gold/sqlserver/Tecpel/gld_dim_local_estoque.parquet"
) }}

WITH CTE_Gestor AS (
    SELECT DISTINCT
           CODLOC
         , COD_GESTOR
         , GESTOR
    FROM {{ ref('gld_dim_vendedor') }}
    WHERE SIT_VEN = 'A'
)

SELECT
      L.CODFILIAL
    , L.CODLOC
    , L.CODFILIAL || '.' || L.CODLOC AS IDLOC
    , L.NOME
    , CASE L.INATIVO
        WHEN 0 THEN 'A'
        WHEN 1 THEN 'I'
      END AS STATUS
    , G.COD_GESTOR
    , G.GESTOR
    , L.CODETD
    , L.dt_extracao
    , L.datasource
FROM {{ ref('slv_tecpel_tloc') }} L
LEFT JOIN CTE_Gestor G
    ON L.CODLOC = G.CODLOC
WHERE L.CODCOLIGADA = 2
      AND LENGTH(L.CODLOC) = 4
