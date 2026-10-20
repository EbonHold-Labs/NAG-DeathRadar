# NAG Death Radar

A small, free World of Warcraft addon from the Next Action Guide team. It shows where players died while
levelling:

- a **heatmap on the world map**: the danger zones of the open map in the radar's own colours (light
  blue from 0.02, yellow from 0.10, red from the `threshold` setting), so a cell the radar points at is red on the map too;
  lighter than on the radar so the map art reads through, with its own opacity (`/ndr alpha`) and an on/off box on the map;
- a **radar** that turns with you (the direction you face is up), shows the death cells around you and
  points to the nearest danger zone, from the rim when it is further than the radar reaches. While you
  stand in a danger zone the radar's rim turns red. Where there is no position (instances) or no data
  for the map, it dims and says so.

It is an empty shell: it only reads one data file, `Data/NAGDeathData.lua`, which the NAG app writes and
refreshes. The addon itself has no network access, sends no chat or addon messages, embeds no
libraries and keeps one SavedVariable, `NAGDeathRadarSettings`, for its settings only.

## Install

Copy the `NAGDeathRadar/` folder into `Interface/AddOns/` (or let the NAG app install it). It loads
without NAG.

| Client | Toc | Interface |
|---|---|---|
| WoW Forever | `NAGDeathRadar_camelot.toc` (`AllowLoadGameType: camelot`) | 16001 |
| Classic Era, Anniversary (TBC), Titan Reforged, MoP Classic | `NAGDeathRadar.toc` | 11509, 20506, 38000, 38002, 50504 |

Only Forever collects deaths today, so every other client shows "no data yet".

## Commands

| Command | Effect |
|---|---|
| `/ndr` or `/ndr help` | the data line and this list |
| `/ndr show`, `/ndr hide` | the radar |
| `/ndr lock [on\|off]` | lock the radar; unlocked, **Alt + drag** moves it (without Alt, clicks go through to the world) |
| `/ndr ring 1\|2\|8\|10` | the ring art: 1 dark iron (default), 2 plain silver, 8 spiked dark, 10 cyan tech |
| `/ndr grid 1\|2` | the grid art: 1 green (default), 2 blue |
| `/ndr art [on\|off]` | the ring and grid art; off leaves a plain ring and field |
| `/ndr map [on\|off]` | the heatmap on the world map. Also on the map itself: on Forever, "Show deaths heatmap" under "NAG Death Radar" in the map's filter menu; on the Classic clients (whose maps have no filter menu), the **Deaths** box in the map's top-right corner |
| `/ndr alpha 0.1-1` | the heatmap's opacity (default 1: the light weight, map art reads through); also a slider in the panel |
| `/ndr tint [on\|off]` | the red rim while you stand in a danger zone (on by default) |
| `/ndr scale 0.5-2` | radar size (default 1) |
| `/ndr range 30-300` | yards from the radar's centre to its rim (default 100) |
| `/ndr threshold 0.05-1` | a cell is a danger zone from this intensity (default 0.25) |
| `/ndr options` | the settings panel (also under Options > AddOns, or **Alt + right-click** the radar out of combat) |
| `/ndr reset` | the defaults |

## The data

`Data/NAGDeathData.lua` ships as a placeholder that defines nothing: a fresh install shows **"no data
yet"** on the radar and on the world map. The NAG app replaces the file with the published export
(relay 3460, route A, `GET /v1/public/deaths/published/NAGDeathData.lua?flavor=<flavour>`); WoW reads it on
the next login or `/reload`.

```lua
NAGDeathData = {
  v = 1,                     -- the only version this addon reads
  cellBase = 0,              -- 0: cells 0..99; absent: 1 (cells 1..100)
  generated = 1792368000,    -- epoch seconds
  published = 1792281600,    -- epoch seconds, the 3-day window's start (shown when present, else generated)
  next = 1792540800, rows = 231, contributors = 5,
  flavor = "camelot",
  map = { [uiMapID] = { [x] = { [y] = q } } },   -- a 100 x 100 grid per map, q 1..100
  -- killers, bands, instances and any other field: ignored by the addon
}
```

- **The cell base.** The server bins a map position 0..10000 as `x * 100 // 10001`, so its cells are 0..99.
  The file states its base in `cellBase`; when the field is absent the addon reads cells as 1..100 (the
  first contract). The side that writes the file must state the base.
- **Unknown fields are ignored**, so the server can add fields without an addon update.
- **"No data yet"** is one state for every unusable file: missing, `NAGDeathData` nil, another `v`, a
  `map` that is not a table or holds no valid cell, or a bad `cellBase`. Nothing errors and nothing ticks.
- On a map the file has no cells for, the radar and the world map say **"no data for this map"**.

The settings panel and `/ndr` show the data's date (UTC) and, when the file carries them, its row and
player counts.

## Privacy

The file holds aggregates only: per map, a smoothed and normalised intensity per cell, never a single
death, a name, a realm, a GUID or an account. A map is published only when at least three different
players died there (the published snapshot of relay 3460 also withholds the whole file until the
flavour has three contributors). Deaths caused by other players and deaths at the level cap are never
counted.

## Tests

```
luajit tests/run.lua
lua5.1 tests/run.lua
```

The runner loads the addon in toc order against `tests/wowstub.lua`, a strict WoW API stub (a widget
method the stub does not know raises), and checks the data states, the cell base, the radar's maths
(facing up, the rim clamp, yards, the nearest danger zone), the heatmap, the slash command and the
settings panel. The fixtures in `tests/fixtures/` are written by the server's own export code:

```
python3 -I tools/make_fixtures.py --tools-repo <a NextActionGuide-Tools clone> [--rev origin/main]
```

The radar's hot ring, `Media/HotRing.tga`, is ours: `python3 -I tools/make_hotring.py` writes it.

The in-game checks are in [CHECKLIST.md](CHECKLIST.md).

## Licence

CC BY-NC 4.0, the same as Next Action Guide; see [LICENSE](LICENSE). The radar's geometry and drawing
helpers come from NAG's Shaman totem radar. The ring and grid art (`Media/frame1.png`, `frame2.png`,
`frame8.png`, `frame10.png`, `radarGrids1.png`, `radarGrids2.png`) are Fonsas's own, from his
FonsasDeathRadar. Nothing is taken from Deathlog or DeathNotificationLib.

The addon is free.
