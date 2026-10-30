"""Unified catalog API: search and product lookup with field-level lineage."""
import json
import logging
from datetime import datetime

import snowflake.connector
from fastapi import Depends, FastAPI, HTTPException, Query
from pydantic import BaseModel
from snowflake.connector import DictCursor

from pipeline.db import get_connection

log = logging.getLogger("uvicorn.error")
app = FastAPI(title="Unified Catalog API")


class SearchHit(BaseModel):
    product_id: str
    product_name: str
    brand: str
    price: float
    score: float


class SearchResponse(BaseModel):
    query: str
    results: list[SearchHit]


class Product(BaseModel):
    product_id: str
    product_name: str
    brand: str
    category: str | None = None
    description: str | None = None
    price: float
    color: str | None = None
    sizes: list[str]
    material: str | None = None
    in_stock: bool | None = None
    updated_at: datetime | None = None
    source_records: list[str]
    lineage: dict


def get_cursor():
    """One connection per request: simple and robust. A pool would replace this at scale."""
    try:
        conn = get_connection()
    except snowflake.connector.errors.Error:
        log.exception("Snowflake error")
        raise HTTPException(status_code=503, detail="Warehouse unavailable")
    try:
        yield conn.cursor(DictCursor)
    finally:
        conn.close()


def _json(value):
    """Snowflake returns ARRAY/OBJECT columns as JSON strings."""
    return json.loads(value) if isinstance(value, str) else value


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/search", response_model=SearchResponse)
def search(
    q: str = Query(..., min_length=1, max_length=200),
    limit: int = Query(5, ge=1, le=20),
    cur=Depends(get_cursor),
):
    try:
        cur.execute(
            """
            WITH query AS (SELECT AI_EMBED('snowflake-arctic-embed-m', 'Represent this sentence for searching relevant passages: ' || LOWER(%(q)s)) AS v)
            SELECT g.product_id, g.product_name, g.brand, g.price,
                   VECTOR_COSINE_SIMILARITY(e.emb, query.v) AS score
            FROM gold_embeddings e
            JOIN gold_products g ON g.product_id = e.product_id
            CROSS JOIN query
            ORDER BY score DESC
            LIMIT %(limit)s
            """,
            {"q": q, "limit": limit},
        )
        rows = cur.fetchall()
    except snowflake.connector.errors.Error:
        log.exception("Snowflake error")
        raise HTTPException(status_code=503, detail="Search backend error")
    return SearchResponse(
        query=q,
        results=[
            SearchHit(
                product_id=r["PRODUCT_ID"], product_name=r["PRODUCT_NAME"], brand=r["BRAND"],
                price=float(r["PRICE"]), score=round(float(r["SCORE"]), 4),
            )
            for r in rows
        ],
    )


@app.get("/products/{product_id}", response_model=Product)
def get_product(product_id: str, cur=Depends(get_cursor)):
    try:
        cur.execute("SELECT * FROM gold_products WHERE product_id = %(id)s", {"id": product_id})
        r = cur.fetchone()
    except snowflake.connector.errors.Error:
        log.exception("Snowflake error")
        raise HTTPException(status_code=503, detail="Lookup backend error")
    if r is None:
        raise HTTPException(status_code=404, detail="Product not found")
    return Product(
        product_id=r["PRODUCT_ID"], product_name=r["PRODUCT_NAME"], brand=r["BRAND"],
        category=r["CATEGORY"], description=r["DESCRIPTION"], price=float(r["PRICE"]),
        color=r["COLOR"], sizes=_json(r["SIZES"]), material=r["MATERIAL"],
        in_stock=r["IN_STOCK"], updated_at=r["UPDATED_AT"],
        source_records=_json(r["SOURCE_RECORDS"]), lineage=_json(r["LINEAGE"]),
    )
