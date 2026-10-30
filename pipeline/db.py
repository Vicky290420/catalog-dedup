import os
import snowflake.connector
from dotenv import load_dotenv


def get_connection():
    load_dotenv()
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role=os.environ.get("SNOWFLAKE_ROLE") or None,
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
        schema=os.environ["SNOWFLAKE_SCHEMA"],
    )


if __name__ == "__main__":
    with get_connection() as conn:
        print(conn.cursor().execute("SELECT CURRENT_USER(), CURRENT_WAREHOUSE()").fetchone())
