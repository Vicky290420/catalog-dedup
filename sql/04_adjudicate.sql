CREATE TABLE IF NOT EXISTS prompts (version STRING, text STRING);

INSERT INTO prompts SELECT 'v4',
$$You decide whether two product listings from different retailers are the SAME product.

Compare in this order: brand, then model name and number (ignore color words), then colorway.

Rules:
- Same product means same brand, same model, and same colorway.
- Ignore size, price, capitalization, abbreviations, punctuation and description wording.
- Colorway nicknames such as Chicago, Royal and Shadow are color names, not model names.
- Color wording can differ for the same colorway (for example Black/White vs Black White).
- A different model name or number (for example Alpha 3 vs Alpha 5) means no_match.
- A different colorway means no_match.

Verdict values:
- "match": brand, model and colorway all agree.
- "no_match": brand, model or colorway clearly differs.
- "unsure": the listings could be the same product but you cannot tell. Use it instead of guessing.

Reply with JSON only: {"verdict": "match" or "no_match" or "unsure", "reason": "the single deciding difference, or none"}$$
WHERE NOT EXISTS (SELECT 1 FROM prompts WHERE version = 'v4');

CREATE TABLE IF NOT EXISTS llm_verdicts (
  sh_id STRING, ut_id STRING, model STRING, prompt_version STRING, raw_response STRING,
  verdict STRING, is_match BOOLEAN, reason STRING,
  created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());

INSERT INTO llm_verdicts (sh_id, ut_id, model, prompt_version, raw_response)
SELECT c.sh_id, c.ut_id, '__CHEAP_MODEL__', 'v4',
  AI_COMPLETE('__CHEAP_MODEL__', p.text
  || '\n\nA: ' || a.brand_key || ' | ' || a.name_clean || ' | color: ' || a.color_std
  || ' | category: ' || a.category_std || ' | material: ' || COALESCE(a.material, '')
  || '\nB: ' || b.brand_key || ' | ' || b.name_clean || ' | color: ' || b.color_std
  || ' | category: ' || b.category_std || ' | material: ' || COALESCE(b.material, ''))
FROM candidate_pairs c
JOIN stg_products a ON a.source = 'stylehaus'   AND a.source_id = c.sh_id
JOIN stg_products b ON b.source = 'urbanthread' AND b.source_id = c.ut_id
JOIN prompts p ON p.version = 'v4'
WHERE c.sim >= __SIM_THRESHOLD__
  AND NOT EXISTS (SELECT 1 FROM llm_verdicts v WHERE v.sh_id = c.sh_id AND v.ut_id = c.ut_id
                  AND v.model = '__CHEAP_MODEL__' AND v.prompt_version = 'v4');

UPDATE llm_verdicts SET
  verdict = TRY_PARSE_JSON(REGEXP_SUBSTR(raw_response, '\\{[^}]*\\}')):verdict::STRING,
  reason  = TRY_PARSE_JSON(REGEXP_SUBSTR(raw_response, '\\{[^}]*\\}')):reason::STRING
WHERE prompt_version = 'v4' AND verdict IS NULL AND raw_response IS NOT NULL;

UPDATE llm_verdicts SET is_match = IFF(verdict = 'unsure', NULL, verdict = 'match')
WHERE prompt_version = 'v4' AND verdict IS NOT NULL;

-- Check: every candidate above the threshold has a parsed verdict (zero rows expected)
SELECT 'pair without parsed verdict' AS chk, c.sh_id, c.ut_id
FROM candidate_pairs c
LEFT JOIN llm_verdicts v ON v.sh_id = c.sh_id AND v.ut_id = c.ut_id
  AND v.model = '__CHEAP_MODEL__' AND v.prompt_version = 'v4'
WHERE c.sim >= __SIM_THRESHOLD__ AND v.verdict IS NULL;
