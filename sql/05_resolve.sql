-- 1. Proposed: cheap model says match AND each side is the other's best candidate
CREATE OR REPLACE TABLE proposed_pairs AS
SELECT c.sh_id, c.ut_id, c.sim
FROM candidate_pairs c
JOIN llm_verdicts v ON v.sh_id = c.sh_id AND v.ut_id = c.ut_id
  AND v.model = '__CHEAP_MODEL__' AND v.prompt_version = 'v4'
WHERE c.sim >= __SIM_THRESHOLD__ AND v.verdict = 'match'
  AND c.rank_for_ut = 1 AND c.rank_for_sh = 1;

-- 2. Audit: LLM said match but the pair lost to a better partner
CREATE OR REPLACE TABLE dropped_pairs AS
SELECT c.sh_id, c.ut_id, c.sim, c.rank_for_ut, c.rank_for_sh
FROM candidate_pairs c
JOIN llm_verdicts v ON v.sh_id = c.sh_id AND v.ut_id = c.ut_id
  AND v.model = '__CHEAP_MODEL__' AND v.prompt_version = 'v4'
WHERE v.verdict = 'match' AND NOT (c.rank_for_ut = 1 AND c.rank_for_sh = 1);

-- 3. Strong model confirms every proposed pair
INSERT INTO llm_verdicts (sh_id, ut_id, model, prompt_version, raw_response)
SELECT f.sh_id, f.ut_id, '__STRONG_MODEL__', 'v4',
  AI_COMPLETE('__STRONG_MODEL__', p.text
  || '\n\nA: ' || a.brand_key || ' | ' || a.name_clean || ' | color: ' || a.color_std
  || ' | category: ' || a.category_std || ' | material: ' || COALESCE(a.material, '')
  || '\nB: ' || b.brand_key || ' | ' || b.name_clean || ' | color: ' || b.color_std
  || ' | category: ' || b.category_std || ' | material: ' || COALESCE(b.material, ''))
FROM proposed_pairs f
JOIN stg_products a ON a.source = 'stylehaus'   AND a.source_id = f.sh_id
JOIN stg_products b ON b.source = 'urbanthread' AND b.source_id = f.ut_id
JOIN prompts p ON p.version = 'v4'
WHERE NOT EXISTS (SELECT 1 FROM llm_verdicts v WHERE v.sh_id = f.sh_id AND v.ut_id = f.ut_id
                  AND v.model = '__STRONG_MODEL__' AND v.prompt_version = 'v4');

UPDATE llm_verdicts SET
  verdict = TRY_PARSE_JSON(REGEXP_SUBSTR(raw_response, '\\{[^}]*\\}')):verdict::STRING,
  reason  = TRY_PARSE_JSON(REGEXP_SUBSTR(raw_response, '\\{[^}]*\\}')):reason::STRING
WHERE prompt_version = 'v4' AND verdict IS NULL AND raw_response IS NOT NULL;

UPDATE llm_verdicts SET is_match = IFF(verdict = 'unsure', NULL, verdict = 'match')
WHERE prompt_version = 'v4' AND verdict IS NOT NULL;

SELECT 'proposed pair without parsed strong verdict' AS chk, f.sh_id, f.ut_id
FROM proposed_pairs f
LEFT JOIN llm_verdicts v ON v.sh_id = f.sh_id AND v.ut_id = f.ut_id
  AND v.model = '__STRONG_MODEL__' AND v.prompt_version = 'v4'
WHERE v.verdict IS NULL;

-- 4. Final pairs: proposed AND confirmed
CREATE OR REPLACE TABLE final_pairs AS
SELECT f.sh_id, f.ut_id, f.sim
FROM proposed_pairs f
JOIN llm_verdicts v ON v.sh_id = f.sh_id AND v.ut_id = f.ut_id
  AND v.model = '__STRONG_MODEL__' AND v.prompt_version = 'v4'
WHERE v.verdict = 'match';

SELECT 'cascade produced too few matches' AS chk FROM (SELECT 1)
WHERE (SELECT COUNT(*) FROM final_pairs) < 0.8 * (SELECT COUNT(*) FROM proposed_pairs);

-- 5. Clusters (two propagation passes, enough for components this small)
CREATE OR REPLACE TABLE product_clusters AS
WITH ut_min AS (SELECT ut_id, MIN(sh_id) AS m FROM final_pairs GROUP BY ut_id),
     sh_min AS (SELECT f.sh_id, MIN(u.m) AS cluster_key
                FROM final_pairs f JOIN ut_min u ON u.ut_id = f.ut_id GROUP BY f.sh_id),
     ut_fin AS (SELECT f.ut_id, MIN(s.cluster_key) AS cluster_key
                FROM final_pairs f JOIN sh_min s ON s.sh_id = f.sh_id GROUP BY f.ut_id)
SELECT 'stylehaus' AS source, sh_id AS source_id, cluster_key FROM sh_min
UNION ALL
SELECT 'urbanthread', ut_id, cluster_key FROM ut_fin;

SELECT 'bad cluster' AS chk, cluster_key, COUNT(*) AS n FROM product_clusters
GROUP BY cluster_key HAVING COUNT(*) > 4 OR COUNT(DISTINCT source) < 2;
