"""Read-only profile of both raw catalogs. Changes nothing."""
import re
import pandas as pd

SOURCES = {
    "stylehaus": dict(path="data/stylehaus_products.csv", id="sku", name="product_name",
                      brand="brand", category="category", color="color", size="size",
                      price="price", ts="updated_at", stock="in_stock", desc="description"),
    "urbanthread": dict(path="data/urbanthread_products.csv", id="product_code", name="title",
                        brand="manufacturer", category="type", color="colour", size="dimensions",
                        price="retail_price", ts="last_modified", stock="availability", desc="details"),
}


def norm_brand(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def profile(label: str, c: dict) -> pd.DataFrame:
    df = pd.read_csv(c["path"], dtype=str)
    print(f"\n=== {label} ===")
    print(f"rows={len(df)} | distinct ids={df[c['id']].nunique()} | distinct names={df[c['name']].nunique()}")

    nulls = df.isna().sum()
    blanks = df.apply(lambda col: (col.str.strip() == "").sum())
    print("nulls:", nulls[nulls > 0].to_dict() or "none", "| blanks:", blanks[blanks > 0].to_dict() or "none")

    print("bad prices:", pd.to_numeric(df[c["price"]], errors="coerce").isna().sum(),
          "| bad timestamps:", pd.to_datetime(df[c["ts"]], errors="coerce").isna().sum())
    print("stock values:", df[c["stock"]].value_counts().to_dict())
    print("description length (chars):", df[c["desc"]].str.len().describe()[["min", "mean", "max"]].round(0).to_dict())

    for key in ("brand", "category", "color", "size"):
        vals = sorted(df[c[key]].unique())
        print(f"\n{key} ({len(vals)} distinct):", vals)

    dup_names = df[df[c["name"]].duplicated(keep=False)][[c["id"], c["name"], c["size"], c["price"]]]
    print("\nrepeated names:\n", dup_names.to_string() if len(dup_names) else "none")
    return df


if __name__ == "__main__":
    frames = {k: profile(k, v) for k, v in SOURCES.items()}
    sh = {norm_brand(b) for b in frames["stylehaus"][SOURCES["stylehaus"]["brand"]]}
    ut = {norm_brand(b) for b in frames["urbanthread"][SOURCES["urbanthread"]["brand"]]}
    print("\n=== brand overlap after normalization ===")
    print("shared:", len(sh & ut))
    print("stylehaus only:", sorted(sh - ut))
    print("urbanthread only:", sorted(ut - sh))
