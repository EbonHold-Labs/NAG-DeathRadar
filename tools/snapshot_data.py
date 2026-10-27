"""Write the published death data into NAGDeathRadar/Data/NAGDeathData.lua for a release, so a copy installed
without the NAG app (CurseForge) has data from day one. The NAG app still replaces the file with each newer window.

It reads the same public routes as the NAG app (relay 3460; Tools AnalyticsServer/deaths.py "THE PUBLISHED
SNAPSHOT"): GET /v1/public/deaths/published/meta.json?flavor=<flavour>, then the window's NAGDeathData.lua by the
sha256 meta names, and keeps the file only when its sha256 is that one. The file is an aggregate (cells, killer npc
ids, level bands, instance counts and totals): no rows, names or accounts, and the server publishes no window under
its contributor floor. No sign-in.

    python3 -I tools/snapshot_data.py [--flavor camelot] [--server https://api.nextaction.guide]

One data file serves every client; the radar draws it only on the game in its `flavor` (core.lua, FlavorMatches).
Only Forever (camelot) collects today, so camelot is the default. A flavour with no published window (404) writes
nothing and exits 1, leaving the file as it is.
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "NAGDeathRadar" / "Data" / "NAGDeathData.lua"
SERVER = "https://api.nextaction.guide"
META = "/v1/public/deaths/published/meta.json"
LUA = "/v1/public/deaths/published/NAGDeathData.lua"
MAX_BYTES = 2 * 1000 * 1000   # the NAG app's own cap on the file (the server keeps it under 1 MB)


def get(server, path, params):
    url = server.rstrip("/") + path + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "NAGDeathRadar-snapshot"}),
                                timeout=30) as resp:
        return resp.read(MAX_BYTES + 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--flavor", default="camelot")
    ap.add_argument("--server", default=SERVER)
    args = ap.parse_args()
    try:
        meta = json.loads(get(args.server, META, {"flavor": args.flavor}))
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            sys.exit("%s: no published window (404); %s left as it is" % (args.flavor, OUT))
        raise
    sha = meta.get("sha256") if isinstance(meta, dict) else None
    if not (isinstance(sha, str) and len(sha) == 64):
        sys.exit("%s: meta.json names no sha256; nothing written" % args.flavor)
    body = get(args.server, LUA, {"flavor": args.flavor, "sha256": sha})
    if hashlib.sha256(body).hexdigest() != sha:
        sys.exit("%s: the file is not the one meta.json names (the window rolled?); run it again" % args.flavor)
    if len(body) > MAX_BYTES or not body.lstrip().startswith(b"NAGDeathData = {"):
        sys.exit("%s: the answer is not the data file (%d bytes); nothing written" % (args.flavor, len(body)))
    new = OUT.with_name(OUT.name + ".new")
    new.write_bytes(body)
    os.replace(new, OUT)
    print("wrote %s: %s, window %s .. %s, %d bytes, %s rows from %s contributors, sha256 %s"
          % (OUT, args.flavor, meta.get("window_start"), meta.get("window_end"), len(body), meta.get("rows"),
             meta.get("contributors"), sha))


if __name__ == "__main__":
    main()
