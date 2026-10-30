CREATE OR REPLACE TABLE gold_membership AS
SELECT 'P' || SUBSTR(MD5(COALESCE(c.cluster_key, p.source || ':' || p.source_id)), 1, 12) AS product_id,
       p.source, p.source_id
FROM stg_products p
LEFT JOIN product_clusters c ON c.source = p.source AND c.source_id = p.source_id;

CREATE OR REPLACE TABLE gold_products AS
WITH rec AS (
  SELECT m.product_id, p.*, IFF(p.source = 'stylehaus', 0, 1) AS src_rank
  FROM gold_membership m
  JOIN stg_products p ON p.source = m.source AND p.source_id = m.source_id
),
name_w   AS (SELECT * FROM rec QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY LENGTH(name_clean) DESC, src_rank, source_id) = 1),
desc_w   AS (SELECT * FROM rec QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY LENGTH(description) DESC, src_rank, source_id) = 1),
price_w  AS (SELECT * FROM rec QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY price, src_rank, source_id) = 1),
recent_w AS (SELECT * FROM rec QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY updated_at DESC, src_rank, source_id) = 1),
brand_w  AS (SELECT * FROM rec QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY src_rank, source_id) = 1),
agg AS (
  SELECT product_id,
         ARRAY_AGG(DISTINCT size_std) WITHIN GROUP (ORDER BY size_std) AS sizes,
         ARRAY_AGG(source || ':' || source_id) AS source_records,
         MAX(updated_at) AS updated_at, COUNT(*) AS n_records
  FROM rec GROUP BY product_id)
SELECT a.product_id,
  IFF(n.name_clean = UPPER(n.name_clean), INITCAP(n.name_clean), n.name_clean) AS product_name,
  IFF(b.source = 'stylehaus', b.brand_raw, INITCAP(b.brand_raw)) AS brand,
  r.category_std AS category, d.description, p.price, r.color_std AS color,
  a.sizes, r.material, r.in_stock, a.updated_at, a.n_records, a.source_records,
  OBJECT_CONSTRUCT(
    'product_name', OBJECT_CONSTRUCT('source', n.source, 'source_id', n.source_id),
    'brand',        OBJECT_CONSTRUCT('source', b.source, 'source_id', b.source_id),
    'description',  OBJECT_CONSTRUCT('source', d.source, 'source_id', d.source_id),
    'price',        OBJECT_CONSTRUCT('source', p.source, 'source_id', p.source_id),
    'category',     OBJECT_CONSTRUCT('source', r.source, 'source_id', r.source_id),
    'color',        OBJECT_CONSTRUCT('source', r.source, 'source_id', r.source_id),
    'material',     OBJECT_CONSTRUCT('source', r.source, 'source_id', r.source_id),
    'in_stock',     OBJECT_CONSTRUCT('source', r.source, 'source_id', r.source_id),
    'sizes',        OBJECT_CONSTRUCT('source', 'merged', 'source_ids', a.source_records)
  ) AS lineage
FROM agg a
JOIN name_w   n ON n.product_id = a.product_id
JOIN desc_w   d ON d.product_id = a.product_id
JOIN price_w  p ON p.product_id = a.product_id
JOIN recent_w r ON r.product_id = a.product_id
JOIN brand_w  b ON b.product_id = a.product_id;

-- Checks (zero rows expected)
SELECT 'dup product_id' AS chk, product_id FROM gold_products GROUP BY product_id HAVING COUNT(*) > 1;

SELECT 'null critical' AS chk, product_id FROM gold_products
WHERE product_name IS NULL OR brand IS NULL OR price IS NULL;

SELECT 'record not in exactly one product' AS chk, source, source_id FROM gold_membership
GROUP BY source, source_id HAVING COUNT(*) <> 1;

SELECT 'price above a source price' AS chk, g.product_id
FROM gold_products g
JOIN gold_membership m ON m.product_id = g.product_id
JOIN stg_products s ON s.source = m.source AND s.source_id = m.source_id
WHERE g.price > s.price;

SELECT 'no merges happened' AS chk FROM (SELECT 1)
WHERE (SELECT COUNT(*) FROM gold_products) >= (SELECT COUNT(*) FROM stg_products);
