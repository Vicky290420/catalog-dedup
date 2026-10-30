-- Embed each product once; the vector is stored, never recomputed in a join
CREATE OR REPLACE TABLE stg_embeddings AS
SELECT source, source_id, brand_key, name_clean, color_std,
       LOWER(brand_key || ' ' || name_clean || ' ' || color_std) AS match_text,
       AI_EMBED('snowflake-arctic-embed-m',
                LOWER(brand_key || ' ' || name_clean || ' ' || color_std)) AS emb
FROM stg_products;

-- All cross-catalog pairs within the same brand block; the threshold is applied later
CREATE OR REPLACE TABLE candidate_pairs AS
SELECT s.source_id AS sh_id, u.source_id AS ut_id, s.brand_key,
       VECTOR_COSINE_SIMILARITY(s.emb, u.emb) AS sim,
       RANK() OVER (PARTITION BY u.source_id ORDER BY VECTOR_COSINE_SIMILARITY(s.emb, u.emb) DESC) AS rank_for_ut,
       RANK() OVER (PARTITION BY s.source_id ORDER BY VECTOR_COSINE_SIMILARITY(s.emb, u.emb) DESC) AS rank_for_sh
FROM stg_embeddings s
JOIN stg_embeddings u
  ON s.brand_key = u.brand_key AND s.source = 'stylehaus' AND u.source = 'urbanthread';

-- Checks (zero rows expected)
SELECT 'null embedding' AS chk, source_id FROM stg_embeddings WHERE emb IS NULL;
SELECT 'no candidate pairs' AS chk FROM (SELECT 1) WHERE (SELECT COUNT(*) FROM candidate_pairs) = 0;
