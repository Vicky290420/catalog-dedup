from pipeline.run import run_file


class Cur:
    def __init__(self, cols, rows):
        self.description = [(c,) for c in cols]
        self._rows = rows

    def fetchall(self):
        return self._rows


class Conn:
    def __init__(self, cursors):
        self.cursors, self.last_sql = cursors, None

    def execute_string(self, sql):
        self.last_sql = sql
        return self.cursors


def _sql_file(tmp_path, text="select 1"):
    p = tmp_path / "x.sql"
    p.write_text(text)
    return p


def test_check_returning_rows_is_reported(tmp_path):
    problems = run_file(Conn([Cur(["CHK"], [("bad",)])]), _sql_file(tmp_path), {})
    assert problems and "check failed" in problems[0]


def test_check_returning_no_rows_passes(tmp_path):
    assert run_file(Conn([Cur(["CHK"], [])]), _sql_file(tmp_path), {}) == []


def test_non_check_statements_are_ignored(tmp_path):
    assert run_file(Conn([Cur(["N"], [(1,)])]), _sql_file(tmp_path), {}) == []


def test_placeholders_are_substituted(tmp_path):
    conn = Conn([])
    run_file(conn, _sql_file(tmp_path, "model = '__CHEAP_MODEL__'"), {"__CHEAP_MODEL__": "m1"})
    assert conn.last_sql == "model = 'm1'"
