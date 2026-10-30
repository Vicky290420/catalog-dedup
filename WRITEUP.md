# Writeup: Product Catalog Consolidation

## Approach
The whole pipeline is numbered Snowflake SQL files (raw, standardize, candidates, LLM matching, resolve, gold, search index) run in order by a small Python runner; a FastAPI app serves the gold table. I kept the data in the warehouse on purpose: at larger volumes validation has to run where the data lives, so every stage ends with SQL checks that must return zero rows or the run fails.

Standardization maps both schemas to one shape, normalizes brands (case, punctuation, plus a hand-kept alias list for HOKA and Carhartt), expands the three abbreviations that appear in titles (WHT, BLK, JKT), strips the trailing size that 43 of 70 UrbanThread titles carry, and converts categories to one format. Candidate generation embeds each product once (brand + cleaned name + color) and pairs StyleHaus with UrbanThread products inside the same brand block.

One early measurement shaped the design: on test pairs, a different colorway of the same model scored higher (0.936) than a true duplicate with different formatting (0.924). Similarity alone cannot tell a duplicate from a variant, so embeddings are only a recall-oriented filter and an LLM makes the match decision.

## Similarity threshold: 0.85
I labeled the top 70 candidate pairs by hand: 32 true pairs, covering 30 UrbanThread products (the Air Max 90 size variants add extra pairs). The lowest-scoring true pair was 0.904, and several false pairs scored higher (Barbour Bedale vs Ashby 0.949, a different-colorway Air Force 1 0.939, Nuptse Red vs Black 0.928), so no cutoff separates them. I chose 0.85 because it keeps every labeled duplicate with a 0.054 margin and sends only 69 pairs to the LLM; 0.90 would keep them too but with a 0.004 margin. Limits: the labels are mine, from the same data the rules were shaped on, and I never reviewed pairs below 0.849.

## LLM prompt design and what I learned
The prompt asks the model to compare brand, then model name and number, then colorway, and to return JSON with a verdict (match, no_match, unsure) and a one-line reason. I iterated on a tuning set of 8 hard pairs with a small model (llama3.1-8b) to save cost.
- v2 regressed because I passed the raw brand (HOKA vs HOKA ONE ONE) instead of my normalized key: the model only reasons over what it is given.
- v3 scored 6 of 6, but I had written test answers into the prompt as examples (Bedale vs Ashby, Bred, Panda), so that result was contaminated and I discarded it. v4 uses examples that are not in the data.
- Small models did not calibrate: numeric confidence was meaningless and the model never answered "unsure" (0 of 8), so I do not use either for routing. The model's reason text sometimes contradicted its verdict, so I treat it as a note, not evidence.
- On the 61 pairs not used for tuning, the small model found all 28 true pairs but had 3 false positives (same colorway, different model: Air Max 90 vs Dunk Low twice, Old Skool vs SK8-Hi), about 90% precision.

## Resolving matches and edge cases
Two further steps fix those errors. First, a pair is accepted only if each product is the other's best candidate; this removes all three false positives and keeps the four-pair Air Max 90 size group together (ties count as best). I designed this rule after seeing the errors, so it is not independent evidence. Second, a stronger model (claude-sonnet-4-5) re-checks every proposed pair (32 calls). It rejected one: Barbour Bedale vs Ashby, which the cheap model and rank rule had accepted. That is one rejection, a tiny sample, not a precision figure. A product that matches two others is handled by the best-match rule, and dropped pairs are kept in a table for audit.

Result: 31 matched pairs form 28 clusters (58 records), giving 134 gold products from 164 source records. One known miss is Converse Chuck Taylor All Star vs Hi, which the cheap model rejected; I left it unmerged because a surviving duplicate is cheaper than a wrong merge.

## Gold catalog and lineage
Merge rules follow the brief: longest name and description, lowest price, most recent record for the other fields, with a JSON lineage column mapping every field to the source brand and record that supplied it. Two deviations: brand uses the StyleHaus spelling when available (a literal "most recent wins" would show uppercase brands), and sizes are merged into a list. Known defects: character length is a weak proxy for "more descriptive" (a Levis 501 name beat the more complete Levi's one by 2 characters), and title-casing produced "Tnf Red".

## Trade-offs
- Speed and cost vs accuracy: a cheap first pass, a strong model only on the survivors. Whole-project usage was about 0.062 Cortex AI credits plus 1.25 warehouse credits (cumulative including development, from usage views that lag, so a lower bound; I did not isolate the cost of one run).
- Precision vs recall: I preferred missing a duplicate to merging two different products.
- Simplicity: two-pass clustering, a hand-kept brand alias list, and SQL checks instead of a testing framework. The API has unit tests with a fake database cursor; SQL logic is covered by the in-pipeline checks, not by separate tests.
- Search: query embeddings need the model's retrieval prefix (without it, single-word queries like "nuptse" returned unrelated shoes). Scores are relative rankings and there is no minimum score.

## What I would improve with more time
Evaluate on more labeled pairs, including a sample from below the threshold, and add a human review queue instead of trusting the models' "unsure". Score name descriptiveness by informative tokens, extract the model name as its own field for the matcher, replace the alias list with a brand reference table, add a hybrid keyword and vector search, and make product IDs persistent.

## Handling 10M products
- Candidates: brand blocks do not scale (pairs grow with the square of block size). Use finer blocking keys plus approximate nearest-neighbor search to take the top-k per product; with k = 5 that is up to 50M pairs before any filtering.
- LLM cost scales with candidate pairs, not products, so use score bands (auto-reject low, auto-accept only on exact normalized matches, LLM in the middle) and a cheap-then-strong cascade. Cache verdicts by pair, model and prompt version (already done here) and re-judge only on prompt or model changes.
- Process incrementally (changed records only) with merge statements and a persistent id table; replace the two-pass clustering with real connected components plus guards on cluster size.
- Ingest by column name with schema evolution and continuous loading (the positional COPY here breaks silently if a column is added); run the zero-row checks as scheduled data-quality tests.
- Monitoring: sample and re-label pairs regularly to track precision and recall, since model or prompt changes can shift both.
