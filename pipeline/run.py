"""Run the full pipeline: python -m pipeline.run"""
import os
import sys
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv

from pipeline.db import get_connection

SQL_DIR = Path("sql")
CSVS = ["data/stylehaus_products.csv", "data/urbanthread_products.csv"]


def settings() -> dict:
    """Placeholders substituted into the SQL files; override via .env if a model is unavailable."""
    return {
        "__CHEAP_MODEL__": os.getenv("CHEAP_MODEL", "llama3.1-8b"),
        "__STRONG_MODEL__": os.getenv("STRONG_MODEL", "claude-sonnet-4-5"),
        "__SIM_THRESHOLD__": os.getenv("SIM_THRESHOLD", "0.85"),
    }


def bootstrap() -> None:
    """Create warehouse, database and schema named in .env (connects with no database context)."""
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"], user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"], role=os.environ.get("SNOWFLAKE_ROLE") or None,
    )
    try:
        cur = conn.cursor()
        wh, db, sc = (os.environ[k] for k in ("SNOWFLAKE_WAREHOUSE", "SNOWFLAKE_DATABASE", "SNOWFLAKE_SCHEMA"))
        cur.execute(f"CREATE WAREHOUSE IF NOT EXISTS {wh} WAREHOUSE_SIZE='XSMALL' "
                    "AUTO_SUSPEND=60 AUTO_RESUME=TRUE INITIALLY_SUSPENDED=TRUE")
        cur.execute(f"CREATE DATABASE IF NOT EXISTS {db}")
        cur.execute(f"CREATE SCHEMA IF NOT EXISTS {db}.{sc}")
    finally:
        conn.close()


def upload_csvs(conn) -> None:
    cur = conn.cursor()
    cur.execute("CREATE STAGE IF NOT EXISTS raw_stage")
    for f in CSVS:
        path = Path(f).resolve().as_posix()
        cur.execute(f"PUT 'file://{path}' @raw_stage OVERWRITE=TRUE AUTO_COMPRESS=FALSE")


def run_file(conn, path: Path, subs: dict) -> list[str]:
    """Run one SQL file. A statement whose first result column is named CHK is a check:
    it must return zero rows."""
    sql = path.read_text(encoding="utf-8")
    for key, val in subs.items():
        sql = sql.replace(key, val)
    problems = []
    for cur in conn.execute_string(sql):
        if cur.description and cur.description[0][0].upper() == "CHK":
            rows = cur.fetchall()
            if rows:
                problems.append(f"{path.name}: check failed ({len(rows)} row(s)), e.g. {rows[0]}")
    return problems


def main() -> int:
    load_dotenv()
    subs = settings()
    bootstrap()
    with get_connection() as conn:
        upload_csvs(conn)
        for path in sorted(SQL_DIR.glob("[0-9][0-9]_*.sql")):
            print(f"running {path.name} ...")
            try:
                problems = run_file(conn, path, subs)
            except snowflake.connector.errors.Error as e:
                print(f"FAILED in {path.name}: {e}")
                return 1
            if problems:
                print("\n".join(problems))
                return 1
    print("pipeline complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
