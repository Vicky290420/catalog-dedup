# Product Catalog Consolidation (StyleHaus + UrbanThread)

Ingests two product catalogs into Snowflake, finds duplicate products across them with
embeddings plus an LLM cascade, builds a gold catalog with field-level lineage, and serves
it through a FastAPI app. Design decisions and evidence: see DECISIONS.md and WRITEUP.md.

## Requirements
- Python 3.10+ (developed on 3.14, Windows 11 with Git Bash)
- A Snowflake account where your role can create a warehouse, database and schema, and can
  use Cortex AI functions (`AI_EMBED`, `AI_COMPLETE`) in your region
- Models used: `snowflake-arctic-embed-m` (embeddings), `llama3.1-8b` (first-pass matching),
  `claude-sonnet-4-5` (confirmation). Override the two LLMs in `.env` if unavailable.

## Setup
```
python -m venv .venv
source .venv/bin/activate          # Windows Git Bash: source .venv/Scripts/activate
pip install -r requirements.txt
cp .env.example .env               # then fill in your Snowflake credentials
```
Never commit `.env`. The pipeline creates the warehouse, database and schema named in `.env`.

## Run the pipeline
```
python -m pipeline.run
```
Runs `sql/01_*.sql` through `sql/07_*.sql` in order. Any data check that returns rows stops
the run and prints the file name and the offending row. A successful run ends with
`pipeline complete`.

**Warning:** tables in the configured schema (raw_*, stg_*, candidate_pairs, proposed/final
pairs, gold_*) are dropped and recreated on every run. Use a dedicated schema.
`prompts` and `llm_verdicts` persist, so reruns in the same schema do not repeat LLM calls.

**Cost of a first run in an empty schema:** about 300 embeddings, 69 calls to the cheap
model and 32 calls to the strong model. Measured: whole project to date, including development iterations and one clean end-to-end run: about 0.062 Cortex AI credits and 1.25 XSMALL warehouse credits (lower bound, see DECISIONS.md).

| Stage | File | Output |
|---|---|---|
| Ingest | 01_ingest.sql | raw_stylehaus, raw_urbanthread |
| Standardize | 02_stg_products.sql | stg_products |
| Candidates | 03_candidates.sql | stg_embeddings, candidate_pairs |
| LLM matching | 04_adjudicate.sql | prompts, llm_verdicts |
| Resolve | 05_resolve.sql | proposed_pairs, final_pairs, product_clusters |
| Gold | 06_gold.sql | gold_products (with lineage), gold_membership |
| Search index | 07_search_index.sql | gold_embeddings |

`sql/eval/` holds the hand-labeled pairs and threshold evidence. It is not run by the pipeline.

## Run the API
```
uvicorn api.main:app --reload
```
Run it from the project root. It reads the same `.env` as the pipeline.
- `GET /search?q=nuptse&limit=5` returns the top matches with a similarity score
- `GET /products/{product_id}` returns the product, its source records and per-field lineage
- `GET /health`
- Interactive docs at http://127.0.0.1:8000/docs

## Tests
```
python -m pytest -q
```
API and runner unit tests (no Snowflake connection needed). Data validation lives in the SQL
files as checks that fail the pipeline run.

## Configuration
| Variable | Purpose |
|---|---|
| SNOWFLAKE_ACCOUNT, USER, PASSWORD, ROLE | Connection |
| SNOWFLAKE_WAREHOUSE, DATABASE, SCHEMA | Where objects are created |
| CHEAP_MODEL, STRONG_MODEL, SIM_THRESHOLD | Optional overrides (defaults in `.env.example`) |

## Known limitations
- Search is weak on very short or off-catalog queries and has no minimum score; scores are
  relative rankings.
- One ambiguous pair (Converse Chuck Taylor All Star vs Hi) is not merged.
- Brand aliases are a hand-maintained list; clustering is sized for this data.
