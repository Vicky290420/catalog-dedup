CREATE OR REPLACE TABLE stg_products AS
WITH sh AS (
  SELECT 'stylehaus' AS source, sku AS source_id, product_name AS name_raw,
         REPLACE(product_name, ' - ', ' ') AS name_clean,
         brand AS brand_raw, category AS category_std, description,
         TRY_TO_NUMBER(price, 10, 2) AS price, color AS color_raw,
         size AS size_std, material,
         (LOWER(in_stock) = 'true') AS in_stock,
         TRY_TO_TIMESTAMP(updated_at) AS updated_at
  FROM raw_stylehaus
),
ut AS (
  SELECT 'urbanthread' AS source, product_code AS source_id, title AS name_raw,
         CASE WHEN UPPER(SPLIT_PART(title, ' ', -1)) IN
                   (UPPER(REGEXP_REPLACE(dimensions, '^(US|EU) ', '')),
                    UPPER(SPLIT_PART(REGEXP_REPLACE(dimensions, '^(US|EU) ', ''), 'x', 1)),
                    'W' || UPPER(REGEXP_REPLACE(dimensions, '^(US|EU) ', '')))
              AND dimensions <> 'One Size'
              THEN REGEXP_REPLACE(title, ' [^ ]+$', '') ELSE title END AS name_clean,
         manufacturer AS brand_raw,
         CASE WHEN CONTAINS(type, ' - ')
              THEN CASE SPLIT_PART(type, ' - ', 2) WHEN 'MEN' THEN 'Men''s ' WHEN 'WOMEN' THEN 'Women''s '
                        ELSE INITCAP(SPLIT_PART(type, ' - ', 2)) || ' ' END
                   || INITCAP(SPLIT_PART(type, ' - ', 1))
              ELSE INITCAP(type) END AS category_std,
         details AS description, TRY_TO_NUMBER(retail_price, 10, 2) AS price,
         colour AS color_raw, REGEXP_REPLACE(dimensions, '^US ', '') AS size_std,
         fabric AS material, (availability = 'In Stock') AS in_stock,
         TRY_TO_TIMESTAMP(last_modified) AS updated_at
  FROM raw_urbanthread
),
unioned AS (SELECT * FROM sh UNION ALL SELECT * FROM ut)
SELECT source, source_id, name_raw,
       REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(name_clean,
         '(^| )WHT( |$)', '\\1White\\2', 1, 0, 'i'),
         '(^| )BLK( |$)', '\\1Black\\2', 1, 0, 'i'),
         '(^| )JKT( |$)', '\\1Jacket\\2', 1, 0, 'i') AS name_clean,
       brand_raw,
       CASE REGEXP_REPLACE(LOWER(brand_raw), '[^a-z0-9]', '')
            WHEN 'hokaoneone' THEN 'hoka' WHEN 'carharttwip' THEN 'carhartt'
            ELSE REGEXP_REPLACE(LOWER(brand_raw), '[^a-z0-9]', '') END AS brand_key,
       category_std, description, price,
       REGEXP_REPLACE(INITCAP(color_raw), '(^|/)Blk($|/)', '\\1Black\\2') AS color_std,
       size_std, material, in_stock, updated_at
FROM unioned;

-- Checks (zero rows expected)
SELECT 'null critical field' AS chk, source_id FROM stg_products
WHERE price IS NULL OR updated_at IS NULL OR brand_key = '' OR name_clean IS NULL;

SELECT 'abbreviation left' AS chk, source_id FROM stg_products
WHERE REGEXP_LIKE(name_clean, '.*(^| )(WHT|BLK|JKT)( |$).*', 'i');

SELECT 'dup key' AS chk FROM stg_products
HAVING COUNT(*) <> COUNT(DISTINCT source || source_id);
