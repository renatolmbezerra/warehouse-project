import os
import yaml

# Dictionary of table names and their primary keys for deduplication
TABLES = {
    "ttrbmov": ["CODCOLIGADA", "IDMOV", "NSEQITMMOV", "CODTRB"],
    "daliqinterestadual": ["CODCOLIGADA", "CODETDORIGEM", "CODETDDESTINO"],
    "tven": ["CODCOLIGADA", "CODVEN"],
    "tvencompl": ["CODCOLIGADA", "CODVEN"],
    "gconsist": ["CODCOLIGADA", "CODTABELA", "CODCLIENTE", "CODINTERNO"],
    "zmd_tabpreco": ["CODCOLIGADA", "IDPRECO"],
    "zmd_categoria": ["ID_CATEGORIA"],
    "flan": ["CODCOLIGADA", "IDLAN"],
    "tprd": ["CODCOLIGADA", "IDPRD"],
    "tprodutodef": ["CODCOLIGADA", "IDPRD"],
    "tmarca": ["CODCOLIGADA", "IDMARCA"],
    "gfilial": ["CODCOLIGADA", "CODFILIAL"],
    "fcfo": ["CODCOLIGADA", "CODCFO"],
    "fcfodef": ["CODCOLIGADA", "CODCFO"],
    "tcpg": ["CODCOLIGADA", "CODCPG"],
    "ftb3": ["CODCOLIGADA", "CODTB3FLX"],
    "tmovcompl": ["CODCOLIGADA", "IDMOV"],
    "titmmovcompl": ["CODCOLIGADA", "IDMOV", "NSEQITMMOV"],
    "ttra": ["CODCOLIGADA", "CODTRA"],
    "ttb1": ["CODCOLIGADA", "CODTB1FAT"],
    "ttb2": ["CODCOLIGADA", "CODTB2FAT"],
    "ttb3": ["CODCOLIGADA", "CODTB3FAT"],
    "ttb4": ["CODCOLIGADA", "CODTB4FAT"],
    "ttrbprd": ["CODCOLIGADA", "IDPRD", "CODTRB"],
    "ttmv": ["CODCOLIGADA", "CODTMV"],
    "trelsld": ["CODCOLIGADA", "IDPRD", "CODLOC", "DATAMOVIMENTO", "SEQUENCIAL"],
    "estoque_saldo_produto_mes": ["CODFILIAL", "CODLOC", "IDPRD", "DATA_SALDO"],
    "tloc": ["CODCOLIGADA", "CODFILIAL", "CODLOC"]
}

# 1. Update sources.yml
sources_path = "dbt_warehouse/models/sources.yml"

with open(sources_path, "r") as f:
    sources_data = yaml.safe_load(f)

# Find the bronze_tecpel source
tecpel_source = next(s for s in sources_data["sources"] if s["name"] == "bronze_tecpel")
existing_tables = [t["name"] for t in tecpel_source.get("tables", [])]

for table_name in TABLES.keys():
    if table_name not in existing_tables:
        tecpel_source["tables"].append({
            "name": table_name,
            "meta": {
                "external_location": f"s3://{{{{ env_var('S3_BUCKET_NAME') }}}}/bronze/sqlserver/Tecpel/{table_name.upper()}/*.parquet"
            }
        })

with open(sources_path, "w") as f:
    yaml.dump(sources_data, f, sort_keys=False, default_flow_style=False)

# 2. Generate Silver SQL files
silver_dir = "dbt_warehouse/models/silver"
os.makedirs(silver_dir, exist_ok=True)

SQL_TEMPLATE = """{{{{ config(
    location="s3://" ~ env_var('S3_BUCKET_NAME') ~ "/silver/sqlserver/Tecpel/{table_upper}/slv_tecpel_{table_lower}.parquet"
) }}}}

WITH source AS (
    SELECT *
    FROM {{{{ source('bronze_tecpel', '{table_lower}') }}}}
),

deduplicated AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY {partition_keys} 
        ORDER BY dt_extracao DESC
    ) = 1
)

SELECT * FROM deduplicated
"""

for table_lower, pk_cols in TABLES.items():
    file_path = os.path.join(silver_dir, f"slv_tecpel_{table_lower}.sql")
    if not os.path.exists(file_path):
        sql_content = SQL_TEMPLATE.format(
            table_lower=table_lower,
            table_upper=table_lower.upper(),
            partition_keys=", ".join(pk_cols)
        )
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(sql_content)
        print(f"Created {file_path}")
