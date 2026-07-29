{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/gold/sqlserver/Tecpel/gld_dim_tipo_movimento.parquet"
) }}

WITH CTE_ULTMOV AS (
    SELECT A.CODTMV
         , MAX(B.DATAMOVIMENTO) AS ULT_MOV
    FROM {{ ref('slv_tecpel_ttmv') }} A
    LEFT JOIN {{ ref('slv_tecpel_tmov') }} B
           ON A.CODCOLIGADA = B.CODCOLIGADA
          AND A.CODTMV        = B.CODTMV
    WHERE A.CODCOLIGADA = 2
      AND LENGTH(A.CODTMV) > 3
    GROUP BY A.CODTMV
),

CTE_TMOV AS (
    SELECT A.CODTMV
         , A.NOME
         , C.ULT_MOV
         , CASE SUBSTRING(A.NOME, 1, 1)
               WHEN 'E' THEN 'ENTRADA'
               WHEN 'S' THEN 'SAIDA' 
           ELSE 'N/A' END AS NATUREZA
         , CASE 
               WHEN SUBSTRING(A.NOME, 1, 1) IN ('E', 'S') THEN SUBSTRING(A.NOME, STRPOS(A.NOME, ' - ') + 3, STRPOS(A.NOME, ' | ') - STRPOS(A.NOME, ' - ') - 3)
               ELSE 'N/A'
           END AS COD_CATEGORIA
         , A.dt_extracao
         , A.datasource
    FROM {{ ref('slv_tecpel_ttmv') }} A
    JOIN CTE_ULTMOV C
        ON A.CODTMV = C.CODTMV
    WHERE A.CODCOLIGADA = 2
      AND LENGTH(A.CODTMV) > 3
)

SELECT *
     , CASE COD_CATEGORIA
           WHEN 'PED COM' THEN 'Pedido Compra'
           WHEN 'NFE COM' THEN 'Compra'
           WHEN 'PED VEN' THEN 'Pedido Venda'
           WHEN 'PED BON' THEN 'Pedido Bonificação'
           WHEN 'NFE FAT' THEN 'Faturamento'
           WHEN 'NFE REM' THEN 'Remessa'
           WHEN 'NFE TRN' THEN 'Transferência'
           WHEN 'NFE OUT' THEN 'Outros'
           WHEN 'NFE ARM' THEN 'Armazenagem'
           WHEN 'NFE VEN' THEN 'Venda'
           WHEN 'NFE DEV' THEN 'Devolução'
           WHEN 'NFE BON' THEN 'Bonificação'
           WHEN 'NFE PER' THEN 'Perda'
           WHEN 'NFE USO' THEN 'Uso e Consumo'
           WHEN 'NFE RTB' THEN 'Remessa Tributada'
           WHEN 'NFE INS' THEN 'Insumos'
           WHEN 'NFE REV' THEN 'Revenda'
           ELSE 'N/A'
       END AS CATEGORIA
FROM CTE_TMOV
