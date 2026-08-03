{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/04_gold/sqlserver/Tecpel/gld_dim_cliente.parquet"
) }}

WITH CTE_TiposFamilia AS (
    -- Seleciona os tipos de faturamento distintos para cada cliente
    SELECT DISTINCT
        A.CODCFO,
        A.TIPOFAM
    FROM {{ ref('gld_fct_vendas_itens') }} A
    WHERE A.TIPOFAM IS NOT NULL
),

CTE_StringAgg AS (
    -- Concatena os tipos de faturamento distintos
    SELECT
        CODCFO,
        STRING_AGG(TIPOFAM, ', ' ORDER BY TIPOFAM ASC) AS TIPOS 
    FROM CTE_TiposFamilia
    GROUP BY CODCFO
),

CTE_ComprasCliente AS (
    -- Agrupa os dados principais de faturamento e junta com a CTE
    SELECT
        A.CODCFO,
        SA.TIPOS AS TIPOFAM,
        CAST(A.VALOR AS NUMERIC(18, 2)) AS VLR_ULT_COMPRA,
        SUM(CAST(A.VALOR AS NUMERIC(18, 2))) OVER(PARTITION BY A.CODCFO) AS VALOR_FAT,
        MIN(A.DATA) OVER(PARTITION BY A.CODCFO) AS PRIMEIRA_COMPRA,
        MAX(A.DATA) OVER(PARTITION BY A.CODCFO) AS ULTIMA_COMPRA,
        ROW_NUMBER() OVER(PARTITION BY A.CODCFO ORDER BY A.DATA DESC) AS RN
    FROM {{ ref('gld_fct_vendas_itens') }} A
    LEFT JOIN CTE_StringAgg SA
        ON A.CODCFO = SA.CODCFO
),

CTE_Maior_Compra AS (
    SELECT 
        CODCFO,
        DATA_MAIOR_COMPRA,
        MAIOR_COMPRA,
        ROW_NUMBER() OVER(PARTITION BY CODCFO ORDER BY MAIOR_COMPRA DESC) AS RN
    FROM (
        SELECT
            CODCFO,
            IDMOV,
            DATA AS DATA_MAIOR_COMPRA,
            CODTMV,
            SUM(VALOR) AS MAIOR_COMPRA
        FROM {{ ref('gld_fct_vendas_itens') }}
        GROUP BY IDMOV, CODCFO, CODTMV, DATA
    ) FAT
),

CTE_Maior_Atraso AS (
    SELECT 
        A.CODCFO,
        CAST(ROUND(
            MAX(
                CASE
                    WHEN A.DATABAIXA IS NULL AND CAST(A.DATAVENCIMENTO AS DATE) < CURRENT_DATE THEN DATE_DIFF('day', CAST(A.DATAVENCIMENTO AS DATE), CURRENT_DATE)
                    WHEN A.DATABAIXA IS NULL AND CAST(A.DATAVENCIMENTO AS DATE) >= CURRENT_DATE THEN 0.0
                    WHEN DATE_DIFF('day', CAST(A.DATAVENCIMENTO AS DATE), CAST(A.DATABAIXA AS DATE)) < 0 THEN 0.0
                    ELSE DATE_DIFF('day', CAST(A.DATAVENCIMENTO AS DATE), CAST(A.DATABAIXA AS DATE))
                END 
            ), 0
        ) AS NUMERIC(10,0)) AS MAIOR_ATRASO
    FROM {{ ref('slv_tecpel_flan') }} A
    LEFT JOIN {{ ref('slv_tecpel_tmov') }} B
        ON A.CODCOLIGADA = B.CODCOLIGADA
        AND A.IDMOV = B.IDMOV
    WHERE 
        A.CODCOLIGADA = 2
        AND A.PAGREC = 1
        AND A.NFOUDUP <> 1
        AND A.CODTDO IN ('001','002') 
        AND (A.STATUSLAN != 2 OR A.DATACANCELAMENTO IS NULL)
        AND B.CODTB3FLX NOT IN ('03', '50') 
    GROUP BY A.CODCFO
),

CTE_Atrasos_Medio AS (
    SELECT 
        A.CODCFO,
        CAST(ROUND(
            SUM((
                CASE
                    WHEN A.DATABAIXA IS NULL AND CAST(A.DATAVENCIMENTO AS DATE) < CURRENT_DATE THEN DATE_DIFF('day', CAST(A.DATAVENCIMENTO AS DATE), CURRENT_DATE)
                    WHEN A.DATABAIXA IS NULL AND CAST(A.DATAVENCIMENTO AS DATE) >= CURRENT_DATE THEN 0.0
                    WHEN DATE_DIFF('day', CAST(A.DATAVENCIMENTO AS DATE), CAST(A.DATABAIXA AS DATE)) < 0 THEN 0.0
                    ELSE DATE_DIFF('day', CAST(A.DATAVENCIMENTO AS DATE), CAST(A.DATABAIXA AS DATE))
                END 
            ) * A.VALORORIGINAL) / NULLIF(SUM(A.VALORORIGINAL), 0), 0
        ) AS NUMERIC(10,0)) AS ATRASO_MEDIO
    FROM {{ ref('slv_tecpel_flan') }} A
    WHERE 
        A.CODCOLIGADA = 2
        AND A.PAGREC = 1
        AND A.NFOUDUP <> 1
        AND A.CODTDO IN ('001','002')
        AND (A.STATUSLAN != 2 OR A.DATACANCELAMENTO IS NULL)
        AND CAST(A.DATAEMISSAO AS DATE) <> CAST(A.DATAVENCIMENTO AS DATE)
        AND CAST(A.DATAVENCIMENTO AS DATE) BETWEEN (CURRENT_DATE - INTERVAL '6' MONTH) AND CURRENT_DATE
    GROUP BY A.CODCFO
),

CTE_LTM AS (
    SELECT 
        CODCFO,
        SUM(CAST(VALOR AS NUMERIC(18,2))) AS LTM_VLR,
        COUNT(DISTINCT IDMOV) AS LTM_QTD_VEN,
        SUM(CAST(VALOR AS NUMERIC(18,2))) / NULLIF(COUNT(DISTINCT IDMOV), 0) AS TICKET_MED_LTM
    FROM {{ ref('gld_fct_vendas_itens') }}
    WHERE 
        DATA BETWEEN (CURRENT_DATE - INTERVAL '1' YEAR) AND CURRENT_DATE
    GROUP BY CODCFO
),

CTE_Rotas AS (
    SELECT
        A.CODCOLIGADA,
        A.IDREGIAO,
        SUBSTRING(B.DESCRICAO, 6, STRPOS(B.DESCRICAO, ' - ') - (STRPOS(B.DESCRICAO, ' ') + 1)) AS ROTA,
        A.CODETD
    FROM {{ ref('slv_tecpel_detdregiao') }} A
    INNER JOIN {{ ref('slv_tecpel_dregiao') }} B
        ON A.CODCOLIGADA = B.CODCOLIGADA
        AND A.IDREGIAO = B.IDREGIAO
    WHERE 
        A.CODCOLIGADA = 2
        AND B.DESCRICAO LIKE '%ROTA%'
),

CTE_Primeiro_Vendedor AS (
    SELECT * FROM (
        SELECT 
            CODCFO,
            CODVEN,
            IDMOV,
            DATA,
            ROW_NUMBER() OVER (PARTITION BY CODCFO ORDER BY DATA ASC, IDMOV ASC) AS RN_PRI
        FROM {{ ref('gld_fct_vendas_itens') }}
    ) Pri_Vendedor
    WHERE RN_PRI = 1
),

CTE_Ultimo_Vendedor AS (
    SELECT * FROM (
        SELECT 
            CODCFO,
            CODVEN,
            IDMOV,
            DATA,
            ROW_NUMBER() OVER (PARTITION BY CODCFO ORDER BY DATA DESC, IDMOV DESC) AS RN_ULT
        FROM {{ ref('gld_fct_vendas_itens') }}
    ) Ult_Vendedor
    WHERE RN_ULT = 1
),

CTE_Prazo_Medio AS (
    SELECT 
        CODCFO,
        AVG(PMR_POR_NF) AS PRAZO_MEDIO
    FROM {{ ref('gld_fct_prazo_medio') }}
    GROUP BY CODCFO
),

CTE_Maxima_Exposicao AS (
    SELECT 
        C.CODCFO,
        strftime(CAST(DATA_COMPETENCIA AS DATE), '%m/%Y') AS MESANO_EXPOSICAO,
        C.VALOR_ABERTO AS MAX_EXPOSICAO,
        ROW_NUMBER() OVER(PARTITION BY C.CODCFO ORDER BY C.VALOR_ABERTO DESC, DATA_COMPETENCIA) AS RN
    FROM (
        SELECT 
            CODCFO,
            DATA_COMPETENCIA,
            SUM(VALOR_ABERTO) AS VALOR_ABERTO
        FROM {{ ref('slv_tecpel_clientesab_dtbase') }}
        GROUP BY CODCFO, DATA_COMPETENCIA
    ) AS C
)

SELECT 
    A.CODCFO,
    A.CGCCFO AS CPFCNPJ,
    A.NOME AS CLIENTE,
    A.PESSOAFISOUJUR AS CATEGORIA,
    TC.DESCRICAO AS TIPO_CLIENTE,
    CAST(A.DATACRIACAO AS DATE) AS DATA_CADASTRO,
    CAST(A.LIMITECREDITO AS NUMERIC(18, 2)) AS LIMITE_CREDITO,
    CASE A.ATIVO
        WHEN 0 THEN 'I'
        WHEN 1 THEN 'A'
    END AS SITUACAO,
    A.TELEFONE,
    A.EMAIL,
    A.RUA,
    A.NUMERO,
    A.COMPLEMENTO,
    A.BAIRRO,
    A.CIDADE,
    A.CODETD AS UF,
    H.NOME AS ESTADO,
    A.PAIS,
    A.CODETD || ', ' || A.PAIS AS UF_PAIS,
    A.CIDADE || ', ' || A.CODETD || ', ' || A.PAIS AS LOCALIZACAO,
    CASE A.CONTRIBUINTE
        WHEN 0 THEN 'NÃO CONTRIBUINTE'
        WHEN 1 THEN 'CONTRIBUINTE'
        WHEN 2 THEN 'ISENTO'
    END AS CONTRIBUINTE_ICMS,
    B.CODVEN,
    V.NOME AS VENDEDOR,
    G.DESCRICAO AS GESTOR,
    E.VALOR_FAT,
    E.TIPOFAM,
    F.CODVEN AS PRIMEIRO_VENDEDOR,
    I.CODVEN AS ULTIMO_VENDEDOR,
    E.PRIMEIRA_COMPRA,
    E.ULTIMA_COMPRA,
    E.VLR_ULT_COMPRA,
    DATE_DIFF('day', CAST(E.ULTIMA_COMPRA AS DATE), CURRENT_DATE) AS DIAS_SEM_COMPRA,
    J.LTM_VLR,
    J.LTM_QTD_VEN,
    J.TICKET_MED_LTM,
    Q.ROTA,
    L.MAIOR_COMPRA,
    L.DATA_MAIOR_COMPRA,
    A.LIMITECREDITO,
    M.PRAZO_MEDIO,
    N.MAIOR_ATRASO,
    P.ATRASO_MEDIO,
    O.MAX_EXPOSICAO,
    O.MESANO_EXPOSICAO,
    A.dt_extracao,
    A.datasource
FROM {{ ref('slv_tecpel_fcfo') }} A
LEFT JOIN {{ ref('slv_tecpel_fcfodef') }} B 
    ON A.CODCOLIGADA = B.CODCOLIGADA 
    AND B.CODCOLCFO = 2 
    AND A.CODCFO = B.CODCFO
LEFT JOIN {{ ref('slv_tecpel_tven') }} V
    ON B.CODCOLIGADA = V.CODCOLIGADA
    AND B.CODVEN = V.CODVEN
LEFT JOIN {{ ref('slv_tecpel_tvencompl') }} CV
    ON V.CODCOLIGADA = CV.CODCOLIGADA
    AND V.CODVEN = CV.CODVEN
LEFT JOIN {{ ref('slv_tecpel_gconsist') }} G
    ON CV.CODCOLIGADA = G.CODCOLIGADA 
    AND CV.GESTOR = G.CODINTERNO
    AND G.CODTABELA = 'GESTOR'
LEFT JOIN CTE_ComprasCliente E
    ON A.CODCFO = E.CODCFO
    AND E.RN = 1
LEFT JOIN CTE_Primeiro_Vendedor F 
    ON A.CODCFO = F.CODCFO
    AND E.PRIMEIRA_COMPRA = F.DATA
LEFT JOIN CTE_Ultimo_Vendedor I 
    ON A.CODCFO = I.CODCFO
    AND E.ULTIMA_COMPRA = I.DATA
LEFT JOIN {{ ref('slv_tecpel_ftcf') }} TC 
    ON A.CODCOLIGADA = TC.CODCOLIGADA 
    AND A.CODTCF = TC.CODTCF
LEFT JOIN {{ ref('slv_tecpel_getd') }} H 
    ON A.CODETD = H.CODETD
LEFT JOIN CTE_LTM J
    ON A.CODCFO = J.CODCFO
LEFT JOIN CTE_Maior_Compra L
    ON A.CODCFO = L.CODCFO
    AND L.RN = 1
LEFT JOIN CTE_Prazo_Medio M
    ON A.CODCFO = M.CODCFO
LEFT JOIN CTE_Maior_Atraso N
    ON A.CODCFO = N.CODCFO
LEFT JOIN CTE_Maxima_Exposicao O
    ON A.CODCFO = O.CODCFO
    AND O.RN = 1
LEFT JOIN CTE_Atrasos_Medio P
    ON A.CODCFO = P.CODCFO
LEFT JOIN CTE_Rotas Q
    ON A.CODCOLIGADA = Q.CODCOLIGADA
    AND A.CODETD = Q.CODETD
WHERE 
    A.CODCOLIGADA = 2
    AND A.PAGREC IN (1, 3)
