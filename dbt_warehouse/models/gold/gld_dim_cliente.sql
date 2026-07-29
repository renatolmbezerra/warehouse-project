{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/gold/sqlserver/Tecpel/gld_dim_cliente.parquet"
) }}

SELECT
    C.CODCOLIGADA,
    C.CODCFO,
    C.NOMEFANTASIA AS NOME,
    C.CGCCFO AS CNPJ_CPF,
    C.CODETD AS UF,
    CASE C.CONTRIBUINTE
        WHEN 0 THEN 'NÃO CONTRIBUINTE'
        WHEN 1 THEN 'CONTRIBUINTE'
        WHEN 2 THEN 'ISENTO'
    END AS TIPO_CONTRIBUINTE,
    C.dt_extracao,
    C.datasource
FROM {{ ref('slv_tecpel_fcfo') }} C
WHERE C.CODCOLIGADA = 2
