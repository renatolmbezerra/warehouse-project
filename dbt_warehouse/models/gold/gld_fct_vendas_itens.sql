{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/gold/sqlserver/Tecpel/gld_fct_vendas_itens.parquet"
) }}

WITH CTE_Datas AS (
    SELECT 
        MAKE_DATE(YEAR(CURRENT_DATE) - 5, 1, 1) AS dtInicial,
        CURRENT_DATE AS dtFinal
),

CTE_Custo_Pond_Subgrupo AS (
    SELECT
          CODFILIAL, CODLOC, TIPOFAM, DATA_SALDO, DATA_DESLOC
        , CODSUBGRUPO, PROCEDENCIA_PRD
        , MAX(CUSTO_POND_SUBGRUPO) AS CUSTO_POND_SUBGRUPO
    FROM {{ ref('gld_fct_estoque') }}
    WHERE DATA_DESLOC >= '2025-12-01'
      AND TIPOFAM IN ('PAPEL', 'EMBALAGEM')
    GROUP BY CODFILIAL, CODLOC, TIPOFAM, DATA_SALDO, DATA_DESLOC, CODSUBGRUPO, PROCEDENCIA_PRD
),

CTE_AliquotaInterestadual AS (
    SELECT
          CODETDORIGEM, CODETDDESTINO
        , ALIQUOTA AS ALIQ_ICMS
        , CASE WHEN CODETDORIGEM = CODETDDESTINO THEN 'D' ELSE 'F' END AS DIFAL
    FROM {{ ref('slv_tecpel_daliqinterestadual') }}
    WHERE CODCOLIGADA = 2
),

CTE_Preco_Visual AS (
    SELECT
          P.IDPRECO, P.CODCOLIGADA, P.CODFILIAL, P.CODLOC
        , P.CODIGOREDUZIDO, P.PROCEDENCIA, P.DIFALDENTROFORA
        , P.SOLICITACAO_FLUIG
        , CAST((P.MARGEMDIRETORIA + 1.5) / 100 AS NUMERIC(10,4)) AS MARGEM_V
        , CAST( P.MARGEMDIRETORIA        / 100 AS NUMERIC(10,4)) AS MARGEM_M
        , CAST((P.MARGEMDIRETORIA - 1.5) / 100 AS NUMERIC(10,4)) AS MARGEM_G
        , CAST((P.MARGEMDIRETORIA - 3)   / 100 AS NUMERIC(10,4)) AS MARGEM_D
        , P.VENDEDOR, P.VENDEDORM, P.GERENTE, P.DIRETORIA
    FROM {{ ref('slv_tecpel_zmd_tabpreco') }} P
    WHERE P.CODCOLIGADA  = 2
      AND P.PAPELOUVISUAL = 'V'
      AND P.DATAINICIO    >= '2026-03-01'
),

CTE_Preco_Papel AS (
    SELECT
          P.IDPRECO, P.CODCOLIGADA, P.CODFILIAL, P.CODLOC
        , P.CODTB3FAT AS CODSUBGRUPO, P.PROCEDENCIA, P.DIFALDENTROFORA
        , P.SOLICITACAO_FLUIG
        , CAST((P.MARGEMDIRETORIA + 1.5) / 100 AS NUMERIC(10,4)) AS MARGEM_V
        , CAST( P.MARGEMDIRETORIA        / 100 AS NUMERIC(10,4)) AS MARGEM_M
        , CAST((P.MARGEMDIRETORIA - 1.5) / 100 AS NUMERIC(10,4)) AS MARGEM_G
        , CAST((P.MARGEMDIRETORIA - 3)   / 100 AS NUMERIC(10,4)) AS MARGEM_D
        , P.VENDEDOR, P.VENDEDORM, P.GERENTE, P.DIRETORIA
    FROM {{ ref('slv_tecpel_zmd_tabpreco') }} P
    WHERE P.CODCOLIGADA  = 2
      AND P.PAPELOUVISUAL IN ('P', 'E')
      AND P.DATAINICIO    >= '2026-03-01'
),

CTE_Prazo_Medio AS (
    SELECT
          IDMOV
        , AVG(CAST(DATE_DIFF('day', DATAEMISSAO, DATAVENCIMENTO) AS NUMERIC(10,2))) AS PMR
    FROM {{ ref('slv_tecpel_flan') }}
    WHERE CODCOLIGADA = 2
      AND DATAEMISSAO BETWEEN (SELECT dtInicial FROM CTE_Datas) AND (SELECT dtFinal FROM CTE_Datas)
    GROUP BY IDMOV
),

CTE_MovBase AS (
    SELECT
          A.CODCOLIGADA, A.CODFILIAL, A.CODLOC, A.CODTMV
        , A.IDMOV, A.NUMEROMOV, A.DATASAIDA
        , A.CODCFO, A.CODVEN1, A.CODDEPARTAMENTO
        , A.CODCPG, A.FRETECIFOUFOB, A.CODTB3FLX
        , CASE WHEN A.CODFILIAL = 1 AND A.CODLOC = '1.20'
               THEN 7 
               ELSE A.CODFILIAL
          END AS COD_UNID_VENDA
        , C.CODPRD AS CODIGOREDUZIDO
        , C.ESPESSURA AS PESOLIQUIDO
        , C.PROCEDENCIA
        , CASE WHEN C.PROCEDENCIA = 'NACIONAL' THEN 'NAC' ELSE 'IMP' END AS PROCEDENCIA_A
        , B.NSEQITMMOV
        , C.IDPRD
        , C.CODFAM AS CODTB1FAT
        , C.CODGRUPO AS CODTB2FAT
        , C.CODSUBGRUPO AS CODTB3FAT
        , C.COM_IMU AS CODTB4FAT
        , B.QUANTIDADE
        , B.VALORFINANCEIRO
        , B.PRECOUNITARIO
        , B.RATEIOFRETE
        , A.CODTRA
        , C.TIPOFAM
        , A.dt_extracao
        , A.datasource
    FROM {{ ref('slv_tecpel_tmov') }} A
    INNER JOIN {{ ref('slv_tecpel_titmmov') }} B
        ON A.CODCOLIGADA = B.CODCOLIGADA
       AND A.IDMOV = B.IDMOV
    LEFT JOIN {{ ref('gld_dim_produto') }} C
        ON B.IDPRD = C.IDPRD
    WHERE A.CODCOLIGADA  = 2
      AND A.STATUS      <> 'C'
      AND A.VALORLIQUIDO <> 0
      AND A.DATASAIDA BETWEEN (SELECT dtInicial FROM CTE_Datas) AND (SELECT dtFinal FROM CTE_Datas)
),

CTE_Faturamento AS (
    SELECT
          md5(CAST(A.CODCOLIGADA AS VARCHAR) || '|' || CAST(A.CODTMV AS VARCHAR) || '|' || CAST(A.NSEQITMMOV AS VARCHAR)) AS UUID
        , A.CODCOLIGADA
        , A.CODFILIAL
        , J.ESTADO AS FILIAL
        , A.COD_UNID_VENDA        
        , F.UNIDADE_VEN AS UNID_VENDA
        , A.CODFILIAL || '.' || A.CODLOC AS IDLOC
        , A.CODLOC
        , A.CODTMV
        , A.NUMEROMOV AS NOTAFISCAL
        , A.CODDEPARTAMENTO
        , A.IDMOV
        , A.NSEQITMMOV
        , A.DATASAIDA AS DATA
        , MONTH(A.DATASAIDA) AS MES
        , YEAR(A.DATASAIDA) AS ANO
        , A.CODCFO
        , A.IDPRD
        , A.CODIGOREDUZIDO AS CODPRD
        , A.CODTB1FAT AS CODFAM
        , A.CODTB2FAT AS CODGRUPO
        , A.CODTB3FAT AS CODSUBGRUPO
        , A.CODVEN1   AS CODVEN
        , F.COD_GESTOR
        , A.CODTRA AS COD_TRANSP
        , Q.NOME AS TRANSPORTADORA
        , COALESCE(TR.IPI,      0) AS IPI
        , CASE
              WHEN A.CODFILIAL = 6 AND O.DIFAL = 'F' AND A.CODTB4FAT <> '01' AND A.DATASAIDA >= '2026-01-01'
              THEN 0
              ELSE COALESCE(TR.ICMS_VALOR, 0)
          END AS ICMS
        , COALESCE(TR.COFINS,   0) AS COFINS
        , COALESCE(TR.COFIMP,   0) AS COFIMP
        , COALESCE(TR.PIS,      0) AS PIS
        , COALESCE(TR.PISIMP,   0) AS PISIMP
        , COALESCE(TR.ICMS_ST,  0) AS ICMS_ST
        , COALESCE(TR.ICMS_DES, 0) AS ICMS_DES
        , COALESCE(A.VALORFINANCEIRO, 0) AS CUSTO
        , A.QUANTIDADE
        , A.PESOLIQUIDO
        , (A.QUANTIDADE * A.PESOLIQUIDO) AS PESO_TOTAL
        , (A.QUANTIDADE * A.PRECOUNITARIO)
            + COALESCE(TR.IPI, 0)
            + COALESCE(A.RATEIOFRETE, 0)
            - COALESCE(TR.ICMS_DES, 0)
            + CASE
                  WHEN TR.ICMS_ST IS NULL OR TR.ICMS_ST = 0.01 OR TR.ICMS_ST = 0.00 THEN 0
                  ELSE TR.ICMS_ST - COALESCE(TR.ICMS_VALOR, 0)
              END AS VALOR
        , CASE
              WHEN A.CODTB3FLX = '50'
              THEN   ((A.QUANTIDADE * A.PRECOUNITARIO)
                      + COALESCE(TR.IPI, 0)
                      + COALESCE(A.RATEIOFRETE, 0)
                      - COALESCE(TR.ICMS_DES, 0)
                      + CASE
                            WHEN TR.ICMS_ST IS NULL OR TR.ICMS_ST = 0.01 OR TR.ICMS_ST = 0.00 THEN 0
                            ELSE TR.ICMS_ST - COALESCE(TR.ICMS_VALOR, 0)
                        END) * PM.PMR * (0.0122 / 30)
              ELSE 0
          END AS TECPELPAY
        , C.CATEGORIA
        , CASE WHEN C.CATEGORIA = 'Devolução' THEN -1 ELSE 1 END AS FATOR
        , A.TIPOFAM
        , A.PROCEDENCIA_A AS PROCEDENCIA
        , CASE
              WHEN A.CODTB4FAT = '01' OR A.CODTMV <> '2.2.28' OR J.ESTADO = 'CE' THEN 0                                     
              WHEN O.DIFAL = 'D'                                                 THEN (TR.ICMS_BASE * O.ALIQ_ICMS / 100)    
              WHEN O.DIFAL = 'F' AND A.PROCEDENCIA = 'NACIONAL'                  THEN (TR.ICMS_BASE * O.ALIQ_ICMS / 100)    
              WHEN O.DIFAL = 'F' AND A.PROCEDENCIA = 'IMPORTADA'                 THEN (TR.ICMS_BASE * 4 / 100)              
              ELSE 0
          END AS ICMS_FUTURA
        , O.DIFAL
        , CASE A.CODTB4FAT WHEN '01' THEN 'IMU' ELSE 'CML' END AS NAT_FISCAL
        , CASE
              WHEN N.CUSTO_POND_SUBGRUPO IS NOT NULL
              THEN A.QUANTIDADE * A.PESOLIQUIDO * N.CUSTO_POND_SUBGRUPO
              ELSE A.VALORFINANCEIRO
          END AS CUSTO_TT_POND_SUB
        , N.CUSTO_POND_SUBGRUPO
        , A.VALORFINANCEIRO / NULLIF((A.QUANTIDADE * A.PESOLIQUIDO), 0) AS CUSTO_UNIT
        , L.CODETD AS UF_CLIENTE
        , A.CODCPG
        , G.NOME   AS COND_PGTO
        , A.FRETECIFOUFOB AS CODFRETE
        , CASE
              WHEN A.FRETECIFOUFOB = 0 THEN 'TERCEIRO'
              WHEN A.FRETECIFOUFOB = 1 THEN 'CIF'
              WHEN A.FRETECIFOUFOB = 2 THEN 'FOB'
              WHEN A.FRETECIFOUFOB = 9 THEN 'SEM FRETE'
              WHEN A.FRETECIFOUFOB = 3 THEN 'PROPRIO REMETENTE'
              WHEN A.FRETECIFOUFOB = 4 THEN 'PROPRIO DESTINARIO'
              ELSE ''
          END AS TIPOFRETE
        , CASE L.CONTRIBUINTE
              WHEN 0 THEN 'NÃO CONTRIBUINTE'
              WHEN 1 THEN 'CONTRIBUINTE'
              WHEN 2 THEN 'ISENTO'
          END AS TIPO_CONTRIBUINTE
        , A.CODTB3FLX AS CODFPGTO
        , H.DESCRICAO AS FORMA_PGTO
        , R.SOLICITACAO_FLUIG
        , U.SOLTABITEM AS SOLICITACAO_PRECO
        , CAST(PM.PMR AS INT) AS PMR
        , CASE 
              WHEN A.TIPOFAM = 'VISUAL' THEN V.VENDEDORM
              ELSE P.VENDEDORM
          END AS PRECO_TABPRECO
        , CASE 
              WHEN A.TIPOFAM = 'VISUAL' THEN V.VENDEDORM * A.QUANTIDADE
              ELSE P.VENDEDORM * A.QUANTIDADE * A.PESOLIQUIDO
          END AS FAT_TABPRECO
        , CASE 
              WHEN A.TIPOFAM = 'VISUAL' THEN V.VENDEDORM * A.QUANTIDADE * V.MARGEM_M
              ELSE P.VENDEDORM * A.QUANTIDADE * A.PESOLIQUIDO * P.MARGEM_M
          END AS LUCRO_TABPRECO
        , A.dt_extracao
        , A.datasource
    FROM CTE_MovBase A
    INNER JOIN {{ ref('gld_dim_tipo_movimento') }} C
        ON A.CODTMV = C.CODTMV
        AND C.CATEGORIA IN ('Faturamento', 'Devolução')
    LEFT JOIN {{ ref('gld_fct_impostos_item') }} TR
        ON A.CODCOLIGADA = TR.CODCOLIGADA
       AND A.IDMOV       = TR.IDMOV
       AND A.NSEQITMMOV  = TR.NSEQITMMOV
    LEFT JOIN {{ ref('gld_dim_vendedor') }} F
        ON A.CODVEN1 = F.CODVEN
    LEFT JOIN {{ ref('slv_tecpel_gfilial') }} J
        ON A.CODCOLIGADA = J.CODCOLIGADA
       AND A.CODFILIAL = J.CODFILIAL
    LEFT JOIN {{ ref('slv_tecpel_fcfo') }} L
        ON A.CODCOLIGADA = L.CODCOLIGADA 
       AND A.CODCFO = L.CODCFO
    LEFT JOIN CTE_Custo_Pond_Subgrupo N
        ON A.CODFILIAL   = N.CODFILIAL
       AND A.CODLOC      = N.CODLOC
       AND A.CODTB3FAT   = N.CODSUBGRUPO
       AND A.DATASAIDA   >= N.DATA_DESLOC
       AND A.DATASAIDA   < N.DATA_DESLOC + INTERVAL 1 MONTH
       AND A.PROCEDENCIA_A = N.PROCEDENCIA_PRD
       AND N.TIPOFAM IN ('PAPEL', 'EMBALAGEM')
    LEFT JOIN {{ ref('slv_tecpel_tcpg') }} G
        ON A.CODCOLIGADA = G.CODCOLIGADA 
       AND A.CODCPG = G.CODCPG
    LEFT JOIN {{ ref('slv_tecpel_ftb3') }} H
        ON A.CODCOLIGADA = H.CODCOLIGADA 
       AND A.CODTB3FLX = H.CODTB3FLX
    LEFT JOIN {{ ref('slv_tecpel_tmovcompl') }} R
        ON R.CODCOLIGADA = A.CODCOLIGADA 
       AND R.IDMOV = A.IDMOV
    LEFT JOIN {{ ref('slv_tecpel_titmmovcompl') }} U
        ON A.CODCOLIGADA = U.CODCOLIGADA 
       AND A.IDMOV = U.IDMOV 
       AND A.NSEQITMMOV = U.NSEQITMMOV
    LEFT JOIN CTE_AliquotaInterestadual O
        ON J.ESTADO = O.CODETDORIGEM
       AND L.UF = O.CODETDDESTINO
    LEFT JOIN CTE_Prazo_Medio PM
        ON A.IDMOV = PM.IDMOV
    LEFT JOIN {{ ref('slv_tecpel_ttra') }} Q
        ON A.CODCOLIGADA = Q.CODCOLIGADA
       AND A.CODTRA = Q.CODTRA
    LEFT JOIN CTE_Preco_Visual V
        ON A.CODCOLIGADA    = V.CODCOLIGADA
       AND A.COD_UNID_VENDA = V.CODFILIAL
       AND A.CODLOC         = V.CODLOC
       AND A.CODIGOREDUZIDO = V.CODIGOREDUZIDO
       AND A.PROCEDENCIA_A  = V.PROCEDENCIA
       AND U.SOLTABITEM     = V.SOLICITACAO_FLUIG
    LEFT JOIN CTE_Preco_Papel P
        ON A.CODCOLIGADA    = P.CODCOLIGADA
       AND A.COD_UNID_VENDA = P.CODFILIAL
       AND A.CODLOC         = P.CODLOC
       AND A.CODTB3FAT      = P.CODSUBGRUPO
       AND A.PROCEDENCIA_A  = P.PROCEDENCIA
       AND U.SOLTABITEM     = P.SOLICITACAO_FLUIG
)

SELECT UUID
     , CODCOLIGADA
     , CODFILIAL
     , FILIAL
     , UNID_VENDA
     , IDLOC
     , CODLOC
     , CODTMV
     , CODDEPARTAMENTO
     , NOTAFISCAL
     , IDMOV
     , DATA
     , MES
     , ANO
     , CODCFO
     , IDPRD
     , CODPRD
     , CODFAM
     , CODGRUPO
     , CODSUBGRUPO
     , CODVEN
     , COD_GESTOR
     , COD_TRANSP
     , TRANSPORTADORA
     , PMR
     , TECPELPAY
     , IPI                           * FATOR AS IPI
     , ICMS                          * FATOR AS ICMS
     , COFINS                        * FATOR AS COFINS
     , COFIMP                        * FATOR AS COFIMP
     , PIS                           * FATOR AS PIS
     , PISIMP                        * FATOR AS PISIMP
     , ICMS_ST                       * FATOR AS ICMS_ST
     , ICMS_DES                      * FATOR AS ICMS_DES
     , ICMS_FUTURA                   * FATOR AS ICMS_FUTURA
     , CUSTO                         * FATOR AS CUSTO_CONTABIL
     , CUSTO_TT_POND_SUB             * FATOR AS CUSTO
     , QUANTIDADE                    * FATOR AS QUANTIDADE
     , PESO_TOTAL                    * FATOR AS PESO_TOTAL
     , PESOLIQUIDO                   * FATOR AS PESOLIQUIDO
     , CASE
          WHEN TIPOFAM IN ('P', 'E') THEN VALOR / NULLIF(PESO_TOTAL, 0)
          ELSE VALOR / NULLIF(QUANTIDADE, 0) 
       END AS PRECO_VENDA
     , VALOR * FATOR AS VALOR
     , (VALOR - IPI - ICMS - COFINS - COFIMP - PIS - PISIMP - ICMS_ST + ICMS_DES - CUSTO - ICMS_FUTURA - TECPELPAY)             * FATOR AS LUCROBRUTO_CONTABIL
     , (VALOR - IPI - ICMS - COFINS - COFIMP - PIS - PISIMP - ICMS_ST + ICMS_DES - CUSTO_TT_POND_SUB - ICMS_FUTURA - TECPELPAY) * FATOR AS LUCROBRUTO
     , CUSTO_UNIT          * FATOR           AS CUSTO_UNIT_CONTABIL
     , CUSTO_POND_SUBGRUPO * FATOR           AS CUSTO_UNIT_POND
     , PRECO_TABPRECO
     , FAT_TABPRECO
     , LUCRO_TABPRECO
     , CASE
           WHEN (VALOR * FATOR) - FAT_TABPRECO < 0 THEN ABS((VALOR * FATOR) - FAT_TABPRECO)
           ELSE 0
       END AS VLR_DESCONTO
     , CASE
           WHEN (VALOR * FATOR) - FAT_TABPRECO > 0 THEN (VALOR * FATOR) - FAT_TABPRECO
           ELSE 0
       END AS VLR_ACRESCIMO
     , CATEGORIA
     , TIPOFAM
     , PROCEDENCIA
     , TIPO_CONTRIBUINTE
     , NAT_FISCAL
     , DIFAL
     , UF_CLIENTE
     , CODCPG
     , COND_PGTO
     , CODFRETE
     , TIPOFRETE
     , CODFPGTO
     , FORMA_PGTO
     , SOLICITACAO_FLUIG
     , SOLICITACAO_PRECO
     , dt_extracao
     , datasource
FROM CTE_Faturamento
