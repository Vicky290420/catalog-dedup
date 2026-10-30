from fastapi.testclient import TestClient

from api.main import app, get_cursor


class FakeCursor:
    def __init__(self, rows):
        self.rows = rows

    def execute(self, sql, params=None):
        self.sql, self.params = sql, params

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return self.rows[0] if self.rows else None


def client_with(rows):
    app.dependency_overrides[get_cursor] = lambda: FakeCursor(rows)
    return TestClient(app)


def teardown_function():
    app.dependency_overrides.clear()


def test_search_returns_ranked_hits_with_rounded_scores():
    rows = [
        {"PRODUCT_ID": "P1", "PRODUCT_NAME": "Nike Air Max 90", "BRAND": "Nike", "PRICE": 129.99, "SCORE": 0.906412},
        {"PRODUCT_ID": "P2", "PRODUCT_NAME": "Nike Air Max 97", "BRAND": "Nike", "PRICE": 179.99, "SCORE": 0.4057},
    ]
    r = client_with(rows).get("/search", params={"q": "air max", "limit": 2})
    assert r.status_code == 200
    body = r.json()
    assert [h["product_id"] for h in body["results"]] == ["P1", "P2"]
    assert body["results"][0]["score"] == 0.9064


def test_search_validates_input():
    c = client_with([])
    assert c.get("/search", params={"q": ""}).status_code == 422
    assert c.get("/search", params={"q": "x", "limit": 99}).status_code == 422


def test_unknown_product_is_404():
    assert client_with([]).get("/products/NOPE").status_code == 404


def test_product_includes_parsed_lineage():
    row = {
        "PRODUCT_ID": "P1", "PRODUCT_NAME": "Nike Air Max 90 White/Black", "BRAND": "Nike",
        "CATEGORY": "Men's Running Shoes", "DESCRIPTION": "d", "PRICE": 129.99, "COLOR": "White/Black",
        "SIZES": '["10","11"]', "MATERIAL": "Mesh", "IN_STOCK": True, "UPDATED_AT": None,
        "SOURCE_RECORDS": '["stylehaus:SH-1","urbanthread:UT-1"]',
        "LINEAGE": '{"price":{"source":"stylehaus","source_id":"SH-1"}}',
    }
    r = client_with([row]).get("/products/P1")
    assert r.status_code == 200
    body = r.json()
    assert body["sizes"] == ["10", "11"]
    assert body["lineage"]["price"]["source"] == "stylehaus"
