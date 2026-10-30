# Decisions and evidence

Working log for the catalog consolidation exercise. The writeup is built from this file.

## What the data actually contains (differs from the exercise doc)
- StyleHaus has 94 rows and UrbanThread has 70, not 100 each as the doc says.
- Rows are product-level, not SKU-level. The only size variants are the Air Max 90 (2 rows per catalog).
- 34 brands appear in both catalogs after punctuation/case normalization.
- Brand aliases that normalization misses: HOKA vs HOKA ONE ONE; Carhartt vs Carhartt WIP.
- All 70 UrbanThread brands are uppercase; 43 of 70 UrbanThread titles end with the size.
- UrbanThread availability is "In Stock" for every row, so it carries no signal.
- StyleHaus colors are mostly marketing names (Navy Blazer, TNF Black), not simple abbreviations.
- Update timestamps overlap (StyleHaus 2026-08-15..10-15, UrbanThread 2026-09-20..10-18), so recency does not always favor one source.

## Design decisions
1. **Platform:** Snowflake. Cortex `AI_EMBED` (snowflake-arctic-embed-m, 768 dims) and `AI_COMPLETE`.
2. **Match level:** same model and same colorway is the same product. Size is a variant attribute, not a matching key.
3. **Embedding text:** brand key + cleaned name + color. Size and price are excluded. Category and material are excluded because UrbanThread category granularity differs from StyleHaus (they go to the LLM as context instead).
4. **Embeddings are a recall-oriented candidate filter inside brand blocks. The LLM decides.**
   Calibration on hand-written pairs: duplicate 0.924, different colorway 0.936, different model 0.886, unrelated 0.727. A colorway variant scored higher than a true duplicate, so no similarity cutoff separates them.
5. **Validation lives in SQL.** Each stage ends with checks (first column named `chk`) that must return zero rows; the runner fails the run otherwise. This is how it would work at GB scale: data is never pulled out to be checked.

## Threshold: 0.85
- Candidate pairs per cutoff: 0.70 -> 187, 0.75 -> 175, 0.80 -> 138, 0.85 -> 69, 0.90 -> 36.
- I hand-labeled the top 70 pairs from names and colors: 32 true pairs (30 UrbanThread products; the Air Max 90 contributes 4 pairs).
- Lowest-scoring true pair: 0.904 (Air Jordan 1 "Red/Black" vs "Bred"). False pairs score above it: Barbour Bedale vs Ashby 0.949, AF1 Black vs White 0.939, Nuptse Red vs Black 0.928.
- 0.90 would keep every labeled pair but with a 0.004 margin. 0.85 keeps a 0.054 margin and sends only 69 pairs to the LLM.
- Limits: labels are mine, from the same data the rules were shaped on. Pairs below 0.849 were never reviewed.

## Prompt iteration log (cheap model: llama3.1-8b)
- **v1:** 8 hard pairs. 5 of 6 decided pairs right; missed Air Jordan ("Bred" treated as a model name). Numeric confidence and `reason` text were unreliable.
- **v2:** added compare-in-order rule and a confidence scale. HOKA regressed to no-match because I passed `brand_raw` (HOKA vs HOKA ONE ONE) to the LLM instead of the normalized brand key. The model ignored the confidence scale.
- **v3:** passed `brand_key`; replaced numeric confidence with match / no_match / unsure. 6 of 6 decided pairs right, **but the prompt contained "Bedale vs Ashby", "Bred" and "Panda", the answers to three test pairs.** Result discarded as contaminated. `unsure` was never used (0 of 8).
- **v4:** examples replaced with ones not in the data. Run on all 69 pairs >= 0.85. Held-out (61 pairs, excluding the 8 tuned on): 28 of 28 true pairs found; precision 28/31. The 3 false positives were same-colorway, different-model pairs (Air Max 90 vs Dunk Low x2; Old Skool vs SK8-Hi).
- Lessons: the LLM only reasons over what it is given (normalize before prompting); never put test answers in the prompt; small models do not abstain or calibrate confidence reliably; the `reason` text is not trustworthy evidence.

## Resolving matches
- **Mutual-best rule:** accept a pair only if each product is the other's best candidate (rank 1 on both sides; ties count, which keeps the 4-pair Air Max 90 group). On the labeled candidate list (computed from the exported candidates): all 32 true pairs pass; false pairs drop from 38 to 4. It removes the 3 LLM false positives. It was designed after seeing those errors, so it is not independent evidence.
- **Cascade:** the strong model (claude-sonnet-4-5) re-checks every proposed pair (32 calls). It rejected 1: Barbour Bedale vs Ashby ("different model names"), which the cheap model plus the rank rule had accepted. 31 pairs confirmed. Sonnet's prompt had no Bedale/Ashby example.
- Result: 31 final pairs, 28 clusters, 58 clustered records, 134 gold products (164 - 58 + 28).
- **Known miss:** Converse Chuck Taylor All Star vs Chuck Taylor Hi was rejected by the cheap model (a defensible call: different silhouette). I count it as a documented miss. A surviving duplicate is cheaper than a wrong merge.
- Ambiguous but accepted: UGG Classic Short II vs Classic Short.
- Edge cases handled: Air Max 90 size variants (4 records -> 1 product); Nuptse Red/Black, AF1 Black/White and Kanken Green/Pink stay separate; a product matching two others is resolved by the best-match rule (dropped pairs are kept in `dropped_pairs`).

## Gold merge rules
- Name: longest cleaned name, tie to StyleHaus; title-cased if the winner is all uppercase.
- Description: longest. Price: lowest.
- Category, color, material, in_stock: from the most recently updated record. updated_at: latest.
- **Deviation:** brand uses the StyleHaus spelling when the product has a StyleHaus record, else title-cased UrbanThread. A literal "most recent wins" would show NIKE-style uppercase brands.
- Sizes: merged array of all distinct sizes in the cluster (lineage source: "merged").
- Lineage: one JSON column mapping each field to {source, source_id}.
- product_id: "P" + first 12 hex chars of MD5(cluster key). Limit: derived from the smallest StyleHaus id in the cluster, so it changes if that record disappears. A persistent id table would fix this.

## Search
- Query embeddings use the model's retrieval prefix ("Represent this sentence for searching relevant passages: "); documents are embedded without it.
- Without the prefix, single-word queries failed (nuptse and barbour returned unrelated shoes at 0.68-0.75). With it, the right products rank first with a clear gap.
- Scores are relative rankings, not percent match. There is no minimum score, so nonsense queries still return results.

## Known defects
- Color shows "Tnf Red" (INITCAP mangles the acronym).
- "Levis 501 Original Jeans Indigo" won the name over "Levi's 501 Original Fit Jeans" because it is 2 characters longer. Character length is not descriptiveness; counting informative tokens would be better.
- Title-casing UrbanThread-only brands can mangle acronyms (ECCO -> Ecco).
- Brand aliases (HOKA, Carhartt) are a hand-maintained list.
- Clustering uses two propagation passes, enough for components this small; at scale use a real connected-components algorithm.
- `INSERT`-based LLM steps dedupe on (pair, model, prompt version); `CREATE OR REPLACE` stages rebuild every run.

## Process incidents (kept for the writeup)
- Prompt answer leakage (v3) hid real failures; fixed in v4 and by evaluating on held-out pairs.
- Strong-model verdicts were stored but not parsed, so `final_pairs` came out empty. Shape checks still passed; a guard check ("cascade produced too few matches") now catches it.
- Python and the SQL worksheet pointed at different schemas; the runner now creates objects in the schema from `.env` and no SQL file names a schema.

## Cost
- First run in an empty schema: about 300 embeddings, 69 cheap-model calls, 32 strong-model calls.
- Measured credits: about 0.062 Cortex AI credits (ACCOUNT_USAGE view, Snowsight assistant rows excluded, 30 usage rows) and 1.25 warehouse credits (WAREHOUSE_METERING_HISTORY for CATALOG_WH, 2026-10-27 to 2026-10-29). Both are cumulative for the whole project including development, not per run. The usage views lag, so treat them as lower bounds. Cost per run in an empty schema was not isolated..
