{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/gold/sqlserver/Tecpel/gld_dim_produto.parquet"
) }}

SELECT A.IDPRD            AS IDPRD
     , A.CODIGOREDUZIDO   AS CODPRD
     , A.DESCRICAO        AS PRODUTO
     , A.CODTB1FAT        AS CODFAM
     , T1.DESCRICAO       AS FAMILIA
     , A.CODTB2FAT        AS CODGRUPO
     , T2.DESCRICAO       AS GRUPO
     , A.CODTB3FAT        AS CODSUBGRUPO
     , T3.DESCRICAO       AS SUBGRUPO
     , T4.DESCRICAO       AS CLASSEFISCAL
     , CASE A.INATIVO 
        WHEN 0 THEN 'A' 
        WHEN 1 THEN 'I'
        ELSE '' END       AS SIT    
     , CAST(A.DTCADASTRAMENTO AS DATE) AS DATA_CADASTRO
     , CASE 
           WHEN A.CODTB1FAT = '72' THEN 'C. VISUAL'
           WHEN A.CODTB1FAT = '08' THEN 'SUBLIMAÇÃO'
           WHEN A.CODTB1FAT = '09' THEN 'OUTDOOR'
           WHEN STRPOS(T3.DESCRICAO, ' ') = 0 THEN 'OUTROS'
           WHEN SUBSTRING(T3.DESCRICAO, 1, STRPOS(T3.DESCRICAO, ' ')-1) = 'BOBINAS' THEN 'BOBINAS'
           WHEN SUBSTRING(T3.DESCRICAO, 1, STRPOS(T3.DESCRICAO, ' ')-1) = 'CUT' THEN 'CUT-SIZE'
           WHEN SUBSTRING(T3.DESCRICAO, 1, STRPOS(T3.DESCRICAO, ' ')-1) = 'RESMAS' THEN 'RESMAS'
           WHEN SUBSTRING(T3.DESCRICAO, 1, STRPOS(T3.DESCRICAO, ' ')-1) = 'PAPEIS' THEN 'PAP. DIV.'
           ELSE 'OUTROS'
       END AS CLASSEPRODUTO
     , CASE WHEN A.REFERENCIACP IN (1,2,6,7) THEN 'IMPORTADA' ELSE 'NACIONAL' END AS PROCEDENCIA
     , CASE A.CODTB4FAT WHEN '01' THEN 'IMUNE' ELSE 'COMERCIAL' END AS COM_IMU
     , D.DESCRICAO AS TIPOFAM
     , A.ESPESSURA
     , B.IDMARCA
     , C.DESCMARCA AS MARCA
     , A.NUMEROCCF AS NCM
     , I.ALIQUOTA AS ALQ_II
     , A.dt_extracao
     , A.datasource
FROM {{ ref('slv_tecpel_tprd') }} A
    LEFT JOIN {{ ref('slv_tecpel_tprodutodef') }} B
        ON A.CODCOLIGADA = B.CODCOLIGADA
       AND A.IDPRD = B.IDPRD
    LEFT JOIN {{ ref('slv_tecpel_tmarca') }} C
        ON B.CODCOLIGADA = C.CODCOLIGADA
       AND B.IDMARCA = C.IDMARCA
    LEFT JOIN {{ ref('slv_tecpel_ttb1') }} T1
        ON A.CODCOLIGADA = T1.CODCOLIGADA
       AND A.CODTB1FAT = T1.CODTB1FAT
    LEFT JOIN {{ ref('slv_tecpel_ttb2') }} T2
        ON A.CODCOLIGADA = T2.CODCOLIGADA
       AND A.CODTB2FAT = T2.CODTB2FAT
    LEFT JOIN {{ ref('slv_tecpel_ttb3') }} T3
        ON A.CODCOLIGADA = T3.CODCOLIGADA
       AND A.CODTB3FAT = T3.CODTB3FAT
    LEFT JOIN {{ ref('slv_tecpel_ttb4') }} T4
        ON A.CODCOLIGADA = T4.CODCOLIGADA
       AND A.CODTB4FAT = T4.CODTB4FAT
    LEFT JOIN {{ ref('slv_tecpel_ttrbprd') }} I
        ON A.CODCOLIGADA = I.CODCOLIGADA
       AND A.IDPRD = I.IDPRD
       AND I.CODTRB = 'II'
    LEFT JOIN {{ ref('slv_tecpel_zmd_categoria') }} D
        ON T1.CAMPOLIVRE = D.ID_CATEGORIA
       AND T1.CODCOLIGADA = 2
WHERE
        A.CODCOLIGADA = 2
    AND A.ULTIMONIVEL = 1
    AND A.CODTB5FAT = '01'
    AND T3.INATIVO = 0
