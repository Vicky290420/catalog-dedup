CREATE FILE FORMAT IF NOT EXISTS csv_fmt
  TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"';

CREATE OR REPLACE TABLE raw_stylehaus (
  sku STRING, product_name STRING, brand STRING, category STRING, description STRING,
  price STRING, color STRING, size STRING, material STRING, in_stock STRING, updated_at STRING,
  _source_file STRING, _loaded_at TIMESTAMP_NTZ);

CREATE OR REPLACE TABLE raw_urbanthread (
  product_code STRING, title STRING, manufacturer STRING, type STRING, details STRING,
  retail_price STRING, colour STRING, dimensions STRING, fabric STRING, availability STRING,
  last_modified STRING, _source_file STRING, _loaded_at TIMESTAMP_NTZ);

COPY INTO raw_stylehaus
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @raw_stage/stylehaus_products.csv)
FILE_FORMAT = (FORMAT_NAME = 'csv_fmt') ON_ERROR = ABORT_STATEMENT;

COPY INTO raw_urbanthread
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @raw_stage/urbanthread_products.csv)
FILE_FORMAT = (FORMAT_NAME = 'csv_fmt') ON_ERROR = ABORT_STATEMENT;

-- Checks (zero rows expected)
SELECT 'empty raw table' AS chk FROM (SELECT 1)
WHERE (SELECT COUNT(*) FROM raw_stylehaus) = 0 OR (SELECT COUNT(*) FROM raw_urbanthread) = 0;

SELECT 'stylehaus null/dup key' AS chk FROM raw_stylehaus
HAVING COUNT(*) <> COUNT(DISTINCT sku) OR COUNT(sku) <> COUNT(*);

SELECT 'urbanthread null/dup key' AS chk FROM raw_urbanthread
HAVING COUNT(*) <> COUNT(DISTINCT product_code) OR COUNT(product_code) <> COUNT(*);
