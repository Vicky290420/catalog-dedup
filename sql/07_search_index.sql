CREATE OR REPLACE TABLE gold_embeddings AS
SELECT product_id,
       AI_EMBED('snowflake-arctic-embed-m', LOWER(brand || ' ' || product_name)) AS emb
FROM gold_products;

SELECT 'missing embedding' AS chk, product_id FROM gold_embeddings WHERE emb IS NULL;
SELECT 'embedding count mismatch' AS chk FROM (SELECT 1)
WHERE (SELECT COUNT(*) FROM gold_embeddings) <> (SELECT COUNT(*) FROM gold_products);
