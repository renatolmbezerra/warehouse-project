{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/04_gold/sqlserver/Tecpel/gld_dim_vendedor.parquet"
) }}

WITH CTE_Carteira AS (
    SELECT B.CODVEN
         , COUNT(DISTINCT A.CODCFO) AS CARTEIRA
    FROM {{ ref('slv_tecpel_fcfo') }} A
    LEFT JOIN {{ ref('slv_tecpel_fcfodef') }} B
        ON A.CODCOLIGADA = B.CODCOLIGADA
        AND A.CODCFO = B.CODCFO
    WHERE A.CODCOLIGADA = 2
      AND A.ATIVO = 1
      AND A.PAGREC IN (1, 3)
      AND B.CODVEN IS NOT NULL
    GROUP BY CODVEN
)

SELECT T.CODVEN
     , T.NOME AS VENDEDOR
     , T.CARGO AS TIPO_VENDEDOR
     , C.GESTOR AS COD_GESTOR
     , G.DESCRICAO AS GESTOR
     , 'UNID ' || SUBSTRING(T.CARGO, STRPOS(T.CARGO, ' ') + 1, LENGTH(T.CARGO)) AS UNIDADE_VEN
     , SUBSTRING(T.CARGO, STRPOS(T.CARGO, ' ') + 1, LENGTH(T.CARGO)) AS UNID
     , CASE
            WHEN T.INATIVO = 0 THEN 'A'
            WHEN T.INATIVO = 1 THEN 'I'
       END AS SIT_VEN
     , COALESCE(A.CARTEIRA, 0) AS CARTEIRA
     , C.CODLOC
     , T.CODFILIAL
     , B.KPIS
     , B.TICKETMIN
     , B.TICKETMAX
     , B.DIASSVENDMIN
     , B.DIASSVENDMAX
     , B.PERFILVENDEDOR AS CODPERFIL
     , P.DESCRICAO AS PERFILVENDEDOR
     , T.dt_extracao
     , T.datasource
FROM {{ ref('slv_tecpel_tven') }} T
LEFT JOIN {{ ref('slv_tecpel_tvencompl') }} C
    ON T.CODCOLIGADA = C.CODCOLIGADA
    AND T.CODVEN = C.CODVEN
LEFT JOIN {{ ref('slv_tecpel_gconsist') }} G
    ON C.CODCOLIGADA = G.CODCOLIGADA 
   AND G.CODTABELA = 'GESTOR' 
   AND C.GESTOR = G.CODINTERNO
LEFT JOIN CTE_Carteira A
    ON T.CODVEN = A.CODVEN
LEFT JOIN {{ ref('slv_tecpel_tvencompl') }} B
    ON T.CODCOLIGADA = B.CODCOLIGADA
   AND T.CODVEN = B.CODVEN
LEFT JOIN {{ ref('slv_tecpel_gconsist') }} P
    ON B.PERFILVENDEDOR = P.CODCLIENTE
   AND P.CODTABELA = 'PERFILVEND'
   AND P.CODCOLIGADA = 2
WHERE 
    T.CODCOLIGADA = 2
    AND T.CARGO LIKE 'VENDEDOR%'
