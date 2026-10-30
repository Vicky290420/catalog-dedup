from pipeline.db import get_connection

FILES = ["data/stylehaus_products.csv", "data/urbanthread_products.csv"]

with get_connection() as conn:
    cur = conn.cursor()
    cur.execute("USE SCHEMA CATALOG_DB.CATALOG_SCHEMA;")
    cur.execute("CREATE STAGE IF NOT EXISTS raw_stage")
    for f in FILES:
        cur.execute(f"PUT file://{f} @raw_stage OVERWRITE=TRUE AUTO_COMPRESS=FALSE")
