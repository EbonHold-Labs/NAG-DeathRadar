"""Write the test fixtures under tests/fixtures/ with the SERVER'S OWN export code, so they cannot drift from
the real file the NAG app drops into Data/NAGDeathData.lua.

The death rows below are synthetic (fixed seed, made-up contributors). They go through the server's own
pipeline from NextActionGuide-Tools AnalyticsServer/deaths.py: validate_file / validate_row, record into an
in-memory store, build (the privacy floor, the kernel, the normalisation) and to_lua. Nothing here touches a
real store or the network.

    python3 -I tools/make_fixtures.py --tools-repo <a NextActionGuide-Tools clone> [--rev origin/main]

deaths.py and store_guard.py are read from <rev> with `git show` into a temporary folder and imported from
there. deaths.py imports pysqlite3, a drop-in build of the stdlib sqlite3; where it is not installed (python -I
leaves the user site out) the stdlib module stands in for it.

What is added AFTER to_lua, because the server does not emit it yet:
- nagdeath_base0.lua: the fields of relay 3460 (published, next, rows, contributors), the cell-base amendment
  (cellBase = 0, the server's own 0..99 cells) and one field no reader knows (an unknown field must be ignored).
- nagdeath_base1.lua: the same aggregate with every cell moved to 1..100 and no cellBase (the shape the
  prototype read), so the two fixtures must land on the same cells.
"""
import argparse
import copy
import importlib
import random
import subprocess
import sys
import tempfile
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "tests" / "fixtures"
NOW = 1792368000            # 2026-10-19 00:00 UTC: the aggregate's `generated`
PUBLISHED = NOW - 86400     # a 3-day window start (relay 3460)
FLAVOR = "camelot"
SEED = 20261019

# Elwynn Forest and Durotar: five players each (the floor is three). Spots as 0..10000 map positions.
SPOTS = {
    1429: [(4210, 6630, 14), (2600, 3800, 8), (9995, 50, 5)],   # the last one sits in the corner cell (99, 0)
    1411: [(5200, 4400, 12), (500, 9990, 6)],
}
LONELY_MAP = 1438  # two players only: the privacy floor must keep it out of the export


def load_server(repo: Path, rev: str, into: Path):
    for name in ("deaths.py", "store_guard.py"):
        body = subprocess.run(["git", "-C", str(repo), "show", f"{rev}:AnalyticsServer/{name}"],
                              check=True, capture_output=True).stdout
        (into / name).write_bytes(body)
    sha = subprocess.run(["git", "-C", str(repo), "rev-parse", rev], check=True, capture_output=True,
                         text=True).stdout.strip()
    try:
        importlib.import_module("pysqlite3")
    except ImportError:
        sys.modules["pysqlite3"] = importlib.import_module("sqlite3")
    sys.path.insert(0, str(into))
    return importlib.import_module("deaths"), sha


def rows_for(rng, spots, start_id):
    out, n = [], start_id
    for x, y, count in spots:
        for _ in range(count):
            out.append({"id": n, "t": NOW - rng.randint(3600, 86400 * 5), "m": None, "x": max(0, min(10000, x + rng.randint(-40, 40))),
                        "y": max(0, min(10000, y + rng.randint(-40, 40))), "lv": rng.randint(2, 25), "cap": 30,
                        "c": rng.randint(1, 11), "r": rng.randint(1, 8), "k": "npc", "s": rng.choice((299, 3098, 113)),
                        "sp": 0, "hc": 0, "av": "5.6.40", "cb": "1.60.1"})
            n += 1
    return out


def aggregate(D):
    rng = random.Random(SEED)
    conn = D.connect_for_tests(":memory:")
    D.init_schema(conn)
    rows_in = 0
    for p in range(5):
        contributor = D.contributor_id("synthetic-player-%d" % p)
        file, why = D.validate_file({"schema": 1, "session": 1760000000 + p, "flavor": FLAVOR,
                                     "addonVersion": "5.6.40", "clientBuild": "1.60.1"})
        assert file, why
        raw, nid = [], 1
        for m, spots in SPOTS.items():
            batch = rows_for(rng, spots, nid)
            for r in batch:
                r["m"] = m
            raw += batch
            nid += len(batch)
        if p < 2:  # the lonely map: two players
            lonely = rows_for(rng, [(5000, 5000, 3)], nid)
            for r in lonely:
                r["m"] = LONELY_MAP
            raw += lonely
        clean = []
        for r in raw:
            c, why = D.validate_row(r, file)
            assert c, why
            clean.append(c)
        for i in range(0, len(clean), D.MAX_ROWS):
            out = D.record(conn, contributor, file, clean[i:i + D.MAX_ROWS], now=NOW)
            rows_in += out["inserted"]
    agg = D.build(conn, FLAVOR, now=NOW)
    assert str(LONELY_MAP) not in agg["maps"], "the privacy floor let a two-player map through"
    return agg, rows_in


def add_fields(lua: str, fields: str) -> str:
    head, sep, tail = lua.partition("v = 1,\n")
    assert sep, "to_lua's output no longer starts with v = 1"
    return head + sep + fields + tail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tools-repo", type=Path, required=True)
    ap.add_argument("--rev", default="origin/main")
    a = ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        D, sha = load_server(a.tools_repo, a.rev, Path(tmp))
        agg, rows = aggregate(D)
        lua0 = D.to_lua(agg)
        agg1 = copy.deepcopy(agg)
        for e in agg1["maps"].values():
            e["cells"] = [[x + 1, y + 1, q] for x, y, q in e["cells"]]
        lua1 = D.to_lua(agg1)
    note = ("-- Test fixture: SYNTHETIC deaths through NextActionGuide-Tools %s AnalyticsServer/deaths.py\n"
            "-- (validate_row, record, build, to_lua). Written by tools/make_fixtures.py; do not edit by hand.\n" % sha[:12])
    base0 = add_fields(lua0, "cellBase = 0,\npublished = %d,\nnext = %d,\nrows = %d,\ncontributors = 5,\n"
                       'futureField = {note = "a field no reader knows", [1] = 2},\n'
                       % (PUBLISHED, PUBLISHED + 259200, rows))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "nagdeath_base0.lua").write_text(note + "-- 0-based cells (cellBase = 0) plus the relay 3460 fields and an unknown field.\n"
                                            + base0, encoding="utf-8", newline="\n")
    (OUT / "nagdeath_base1.lua").write_text(note + "-- The same cells moved to 1..100, no cellBase, no published.\n"
                                            + lua1, encoding="utf-8", newline="\n")
    print("wrote %s and %s (%d rows, maps %s)" % (OUT / "nagdeath_base0.lua", OUT / "nagdeath_base1.lua", rows,
                                                 ",".join(sorted(agg["maps"]))))


if __name__ == "__main__":
    main()
