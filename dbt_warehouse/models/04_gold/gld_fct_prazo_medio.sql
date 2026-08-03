{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/04_gold/sqlserver/Tecpel/gld_fct_prazo_medio.parquet"
) }}

WITH CTE_Base AS (
    SELECT 
        A.CODFILIAL,
        B.CODLOC,
        CONCAT(A.CODFILIAL, '.', B.CODLOC) AS IDLOC,
        C.CODVEN,
        A.CODCFO,
        A.IDMOV,
        CAST(A.DATAEMISSAO AS DATE) AS DATAEMISSAO,
        COUNT(A.IDMOV) AS QTDE_PARCELAS,
        SUM(CAST(A.VALORORIGINAL AS NUMERIC(18,2))) AS VALOR_NF,
        SUM(DATE_DIFF('day', CAST(A.DATAEMISSAO AS DATE), CAST(A.DATAVENCIMENTO AS DATE))) AS TOTAL_DIASVENC,
        A.dt_extracao,
        A.datasource
    FROM {{ ref('slv_tecpel_flan') }} A
    LEFT JOIN {{ ref('slv_tecpel_tmov') }} B
        ON A.CODCOLIGADA = B.CODCOLIGADA
        AND A.IDMOV = B.IDMOV
    LEFT JOIN {{ ref('slv_tecpel_fcfodef') }} C
        ON A.CODCOLIGADA = C.CODCOLIGADA
        AND C.CODCOLCFO = 2
        AND A.CODCFO = C.CODCFO
    WHERE
        A.CODCOLIGADA = 2
        AND B.CODTMV IN (SELECT CODTMV FROM {{ ref('gld_dim_tipo_movimento') }} WHERE CATEGORIA = 'Faturamento')
        AND C.CODVEN IS NOT NULL
        AND CAST(A.DATAEMISSAO AS DATE) >= DATE '2020-01-01'
        AND B.CODTMV != '2.2.38'
    GROUP BY 
        A.CODFILIAL,
        B.CODLOC,
        C.CODVEN,
        A.CODCFO,
        CAST(A.DATAEMISSAO AS DATE),
        A.IDMOV,
        A.dt_extracao,
        A.datasource
)

SELECT 
    CODFILIAL,
    CODLOC,
    IDLOC,
    CODVEN,
    CODCFO,
    IDMOV,
    DATAEMISSAO,
    QTDE_PARCELAS,
    VALOR_NF,
    TOTAL_DIASVENC,
    (TOTAL_DIASVENC / QTDE_PARCELAS) AS PMR_POR_NF,
    (TOTAL_DIASVENC / QTDE_PARCELAS) * VALOR_NF AS VALOR_PONDERADO,
    dt_extracao,
    datasource
FROM CTE_Base
WHERE (TOTAL_DIASVENC / QTDE_PARCELAS) > 0
