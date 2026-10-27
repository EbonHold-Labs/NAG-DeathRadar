# NAG Death Radar

A small, free World of Warcraft addon from the Next Action Guide team. It shows where players died while
levelling:

- a **heatmap on the world map**: the danger zones of the open map in a smooth colour ramp, from a faint light
  blue at 0.02 through teal-green and gold at 0.10 to orange, then reds from the `threshold` setting (the
  radar's own red line), deepening with the danger, so a cell the radar points at is red on the map too;
  drawn 200 x 200 per map at every zoom, smoothed between cells (the file's `fine` cells where it has them);
  lighter than on the radar so the map art reads through, with its own opacity (`/ndr alpha`) and an on/off box on the map;
- a **perspective danger view** in front of the character (the default), showing the map's red areas as
  quiet filled contours up to 180 yards ahead. It follows character heading, not the gameplay camera:
  this is an illustration, best with the camera behind your character, not a terrain-attached overlay;
- an optional **circle radar** that turns with you (the direction you face is up), shows the death cells around you and
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

Only Forever collects deaths today. The radar draws a file only on the game named in its `flavor`, so every
other client shows "no data for this game" (or "no data yet" when no file is there at all).

## Commands

| Command | Effect |
|---|---|
| `/ndr` or `/ndr help` | the data line and this list |
| `/ndr show`, `/ndr hide` | the selected danger view |
| `/ndr mode perspective`, `/ndr mode radar`, `/ndr mode world` | select Perspective (default), Radar, or World (test), which uses an approximate direction view unless camera sampling is explicitly enabled; `mode circle` remains an alias |
| `/ndr world start`, `/ndr world stop`, `/ndr world status` | start/resume, stop/release navigation, or print World view status and any captured API error; it never starts automatically after reload |
| `/ndr world preview` | preview a moved and scaled copy of a map outline, clearly marked as a replay, using the current World sampling choice; original danger data stays untouched |
| `/ndr world anchors on`, `/ndr world anchors off` | opt into or stop experimental camera sampling; **off by default** because sampling moves the map/minimap waypoint pin. With it off, World uses an approximate character-heading view without waypoint writes |
| `/ndr outline 0.5-2`, `/ndr fill 0-2` | independently adjust contour strength and fill opacity; `fill 0` leaves outlines |
| `/ndr reach 30-300` | perspective range in yards (default 180) |
| `/ndr width 320-1400`, `/ndr height 120-700` | perspective dimensions (default 720 x 160, a shallow ground plane) |
| `/ndr size 0.5-2` | perspective scale (default 1) |
| `/ndr x -2000..2000`, `/ndr y -1000..1000` | perspective bottom offset from screen centre (default 0, 60; view extends upwards) |
| `/ndr front` (also `/ndr ground`) | restore the position in front of/above the character and shallow height, preserving other settings |
| `/ndr preview [on\|off]` | clearly labelled synthetic test areas; does not change the live data file |
| `/ndr lock [on\|off]` | lock the radar; unlocked, **Alt + drag** moves it (without Alt, clicks go through to the world) |
| `/ndr ring 1\|2\|8\|10` | the ring art: 1 dark iron (default), 2 plain silver, 8 spiked dark, 10 cyan tech |
| `/ndr grid 1\|2` | the grid art: 1 green (default), 2 blue |
| `/ndr art [on\|off]` | the ring and grid art; off leaves a plain ring and field |
| `/ndr map [on\|off]` | the heatmap on the world map. Also on the map itself: on Forever, "Show deaths heatmap" under "NAG Death Radar" in the map's filter menu; on the Classic clients (whose maps have no filter menu), the **Deaths** box in the map's top-right corner |
| `/ndr alpha 0.1-1` | the heatmap's opacity (default 1: the light weight, map art reads through); also a slider in the panel |
| `/ndr tint [on\|off]` | the red rim while you stand in a danger zone (on by default) |
| `/ndr scale 0.5-2` | circle radar size (default 1) |
| `/ndr range 30-300` | yards from the circle radar's centre to its rim (default 100) |
| `/ndr threshold 0.05-1` | a cell is a danger zone from this intensity (default 0.25) |
| `/ndr options` | the settings panel (also under Options > AddOns, or **Alt + right-click** the radar out of combat) |
| `/ndr reset` | the defaults |
| `/ndr probe` | a copyable report of camera and world-projection capabilities; opens out of combat |

For a projection capability check, run `/reload` after updating the addon, then `/ndr probe` out of combat.
The report is selected in a scrollable text window: **Ctrl+A, Ctrl+C**, then paste it into the support chat.
Running the command again takes a fresh snapshot. It reports the client build, named API candidates and
protected results from known read-only getters; missing APIs, lookup/call errors and secret values are
marked explicitly. Function presence alone does not prove usable world projection. The check does not
change waypoints, tracking, the camera or addon settings, and collects no player names.
Probe v2 also calls `C_Commentator.IsSpectating`, `GetCamera` and `GetCameraPosition` with `pcall` in the
current gameplay context, including when not spectating. Camera coordinates are included when returned;
the camera values are labelled in return order. No spectator mode is enabled. Nil/no returns, errors and
secrets remain explicit; a successful call or zero-filled output does not prove a live gameplay camera.
To compare samples, keep the character still, close the report, rotate only the camera, then run `/ndr probe`
again and copy the second report.

Probe v3 additionally reads the existing navigation frame's screen geometry, visibility and scale,
player/target world coordinates, and up to eight existing nameplate units. It checks `C_UI.GetWorldFrame`
against the global frame and labels navigation states and clamping. All getters use protected calls;
secret results and forbidden frame geometry are skipped. No names or GUIDs are collected. Coordinates
are included when public. These samples investigate possible anchors; they do not prove usable camera
reconstruction. The probe does not rotate the camera, select targets, change tracking or enable nameplates.

## Testing the perspective view in Forever

The perspective view is standalone: Journey is not required. Its red regions come from the very same
capped picture as the world map, including decoded fine data and interpolation. It draws the actual data
boundaries, preserving gaps and holes; there is no suggested route, preferred side, or green "safe" area.
When outside all areas with none in the forward field, the view disappears. Inside an area it retains a
quiet tint and status even if the boundary lies beyond the view. Missing map data or unavailable position
produce distinct status text; stale geometry is cleared. It remains active in combat while the client
provides plain position and heading values. The drawing takes no mouse input. Holding **Alt** reveals
a highlighted move field: **Alt + left-drag** repositions the view and saves its screen offsets. Release
Alt to restore click-through. This move field is also available when there are no danger areas or no data.
The default field is now 720 x 160 at offset (0, 60), extending upwards from slightly above screen centre,
in front of/above the character. There is no centre heading line. Vertical depth is about 43% smaller than
the first version. Old default offsets, including the previous centre and below-feet presets, migrate once;
other saved offsets are preserved. Use `/ndr front` to apply the new
position and height to an already customized view, then Alt-drag to fine-tune it. Width, scale, range and danger thresholds
are retained. This remains an illustration; it does not acquire the terrain's height or camera pitch.

After installing this first version, restart the client so its new files and `Bindings.xml` are discovered.
Subsequent Lua/layout edits can be loaded with `/reload`. Use the explicit **Perspective** and **Radar**
buttons in `/ndr options` to select a view; the selected button is marked `[x]`. The panel also adjusts reach, dimensions,
scale and screen offsets. In WoW's **Key Bindings > NAG Death Radar**, assign **Hold danger-view details**
to a key of your choice; nothing is assigned automatically. Hold it for stronger contours/fill and the
approximate distance to the nearest relevant data boundary, then release to return to the quiet view.

Use `/ndr preview on` to exercise the illustration with explicitly labelled synthetic areas, then
`/ndr preview off` to return to live data. The preview never replaces `Data/NAGDeathData.lua` or the map's
published data. A blank space in a death dataset does not establish safe terrain or a traversable path.

Development uses a junction to the installed addon. NAG Helper can therefore replace the local data file
while the source is being edited. Preserve that runtime export; tests use isolated fixtures and it should
not be included in a feature commit.

## Experimental World view

**Current behavior, `0.3.0-dev12`:** normal viewing does not move any waypoint.
World starts in a clearly labelled approximate character-heading view. This avoids
the repeated map/minimap pin changes caused by camera sampling. Enable
`/ndr world anchors on` only when deliberately testing native camera projection;
the same option in settings explicitly warns that it moves map pins. Run
`/ndr world anchors off` to release the temporary waypoint and keep the risk view.
An existing user waypoint remains untouched in normal viewing.

With native sampling enabled, clamped/invalid/shallow samples, failed validation,
and projected filled areas thinner than eight UI pixels per screen extent use
the approximate direction view instead of a disappearing or flattened world mask.
Combat, an external navigation takeover or an API pause stop waypoint sampling;
the read-only direction view continues where position/data remain available.
Native sampling must be restarted explicitly. Stop/hide/mode changes and control
or map loss clear both views. A replay retains the same copied map outline and
its replay label when switching to the direction view.

Leaving combat keeps the direction view active. Layout changes preserve a paused
sampler and the replay's original map position; help, options and diagnostics do
not restart sampling. Perspective recovers from temporary position/heading loss
even while standing still. Dense views stop geometry construction at the drawing
budget and show a range-reduction notice instead of rendering partial regions.

Moving direction views repaint at up to 60 FPS and reuse stationary geometry.
An accepted camera projection follows player translation between measurement
batches for at most 350 ms; failed validation removes it immediately. These are
display improvements, **not terrain-height correction**. A single plane still
cannot follow a sloping landscape. The approximate view is deliberately labelled
and does not claim to be attached to terrain. The read-only fallback also avoids
the native sampling timeout at low frame rates; the native 30 FPS limit remains.
Contour and fill controls are separate in settings and via `/ndr outline` and
`/ndr fill`. Existing installations need `/reload`.

The following notes describe the earlier native-projection experiments.
Restart the client once after installing `0.3.0-dev6`, then select **World (test)** in
`/ndr options` or run `/ndr mode world`. This standalone view samples four native navigation
anchors, checks two separate points and repeats the first anchor to reject camera movement
during sampling. All nearby red map-mask shapes share the resulting projection. At 120 FPS
the feasibility test reached about 17 complete batches per second; this is not a performance
guarantee for every map, frame rate or camera angle.

`0.3.0-dev7` also supports a new character with no tracked quest: Forever can return
`nil` for that empty state. Existing dev6 installations need only `/reload` for this fix.
On Stress Test build 70532, stationary replay testing showed camera-following outlines
and successful release back to no waypoint or tracked quest. Some camera angles lost
calibration, and the replay looked extremely shallow. This is still a feasibility view;
those observations do not establish reliable terrain alignment or shape readability.

`0.3.0-dev8` waits two rendered updates after each waypoint change, because a native
probe recorded the previous target on the first update. It searches eight directions
in 45-degree steps when anchors are invalid or clamped. Nearly edge-on reference
planes are hidden with a request to tilt the camera down; the mask is never stretched
to make it look taller. A Beta client test on 2026-10-22 showed contours updating
after camera changes and short local movements, at 6.1 accepted batches per second
over the mixed test. Some angles hid the contour and buildings did not occlude it.
These replay screenshots do not validate actual danger locations or terrain height. At 120 FPS, two
updates per point limit the seven-point batch to roughly eight accepted updates per
second before other work. Low frame rates, movement or camera drift can still reject
the batch; this is not yet a reliable running aid.

`0.3.0-dev9` fixes a reproduced Forever startup failure: selecting the temporary
waypoint clears the tracked quest, which previously looked like an external takeover.
The view now distinguishes its own tracking state from the quest saved for restoration,
including partial setter failures; external navigation changes still stop sampling.
Failed restoration retries are limited to once per 250 ms and appear in status.
The movement guard permits two yards per batch, while both independent holdouts and
repeated-anchor drift must still stay below four UI pixels. An independent camera
simulation covers running at seven yards per second at 60 FPS. This is not a native
running guarantee: a short Beta client test at 60 FPS accepted zero batches while
moving, hid the contour during the movement, and recovered after stopping. The
sequence still needs a method that accounts for camera movement during sampling.
At 30 FPS the two-update sampling also exceeds its 350 ms timeout.
Replay containment uses the exact moved rectangles, and its inside indicator says
"Inside replay area". Existing installations need `/reload` for dev9.

`0.3.0-dev10` compensates player translation between the seven measurements.
Each sample uses its own player-relative map coordinate; four corners fit the
projection, two spatial holdouts and the repeated anchor independently check it.
The repeated-anchor limit applies to the compensated prediction, not the raw
screen displacement caused by running. Both error limits remain four UI pixels,
with the same two-yard movement guard and 350 ms timeout. Rendering, containment
and boundary distance use the player position at the end of the batch. A temporary
holdout/drift failure retries the visible reference before searching other directions.

In a short Beta client run at observed 60 FPS, the final dev10 test accepted nine
batches while moving. Their maximum raw anchor displacement was 15.1 UI pixels,
and the largest compensated validation residual was 0.6 pixels. The mixed
stationary/running report was 421 attempts, 418 accepted and two holdout rejections,
with an attempt in progress. An earlier dev10 test briefly hid the contour during
camera adjustment at movement start; this is progress, not proof of uninterrupted
running under every camera angle. The copied map shape and entry indicator were
visible in the client; the location was explicitly marked as a replay. Real danger
boundary alignment, terrain height, combat and low-FPS operation remain unverified.
Both installed addon links use this source; existing installations need `/reload`.

`/ndr world status` reports attempts, accepted batches, rejected batches and counts
by rejection cause, including attempts that fail before fitting. `clamped` means an
anchor is pinned to the screen edge, `shallow` means the reference plane is too thin,
`holdout`/`drift` mean measured points disagree, `movement` means the character moved
over two yards during sampling, and `expired` means sampling reached the 350 ms limit.
`accepted while moving` counts accepted batches with more than a quarter yard of
player displacement during that batch; it does not measure continuous running.
For accepted moving batches, `moving max raw` reports the largest uncorrected
repeat displacement and `compensated` the largest independent validation residual.
An in-progress attempt is included in attempts; the displayed residuals belong to
the most recently completed batch. This report reads existing state without starting
navigation or collecting names.

The fill is deliberately faint and the contour stronger. Since dev11, uncertain or
clamped samples replace the camera projection with a labelled direction view.
Offscreen geometry is clipped before perspective division.
The existing details binding strengthens the contours and shows approximate boundary distance.
Screen placement and size controls apply to Perspective and the approximate direction
view. Only the opt-in camera projection follows the native camera.

When waypoint camera sampling is explicitly enabled, World temporarily borrows the client's **single user waypoint**, so it cannot coexist with
other waypoint navigation. It refuses an existing user waypoint, restores the previous quest
when stopped, and pauses sampling if a different waypoint or quest takes over. It also pauses sampling on combat,
control loss, a map transition or an API error. Restoration blocked by combat is deferred until
combat ends. Run `/ndr world start` explicitly to resume; a saved World choice never starts
sampling automatically after reload. `/ndr world stop` releases its navigation target.

This is a camera-following UI overlay with **unverified terrain height**, and it can draw over
buildings. It does not provide depth occlusion or prove that a gap is traversable. Terrain data
is not consumed by this version. Client evidence covers stationary camera tests and short
local replay runs; sustained running, combat behavior and low-FPS use still require native verification. Perspective and Radar remain
available while this mode is evaluated.

Use `/ndr world preview` for a labelled replay of a nearby map shape moved/scaled in memory;
it is not a real danger area at the replay location. Stop the preview before normal play.

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
  fine = { grid = 200, cellBase = 0, levels = 64,  -- optional: finer cells (14 days, a per-cell floor)
           [uiMapID] = { "packed runs", ... } },
  -- killers, bands, instances and any other field: ignored by the addon
}
```

- **The cell base.** The server bins a map position 0..10000 as `x * 100 // 10001`, so its cells are 0..99.
  The file states its base in `cellBase`; when the field is absent the addon reads cells as 1..100 (the
  first contract). The side that writes the file must state the base.
- **The world map draws 200 x 200 per map.** From `fine` where the file has it for the map; else from `map`,
  each cell upsampled bilinearly between cell centres; a fine cell of a cell the radar calls hot that smooths
  under the threshold takes that cell's q, so the radar's red stays red on the map. The colours are a ramp of 24
  shades under the threshold (light blue, teal-green, gold, orange; the alpha rising from 0.18 to 0.5) and 8
  shades of red above it (orange-red to deep red, alpha 0.5 to 0.75). Touching cells of one
  shade along a row are one texture; past 2,500 textures the picture is folded to 100, 50 or 25 per side,
  keeping each square's hottest cell.
- **`fine`, optional (the server's, Tools PR #1142).** `grid` is the cells per side (200, 300 or 400), `cellBase`
  0 or 1 (0 when absent), `levels` 2..64 (64 when absent): a cell's level is 1..levels - 1, the map's hottest
  cell is levels - 1, read as `q = 100 * level / (levels - 1)`. Each map is a list of strings of whole runs
  along a row: `Y` (2 characters), `X` (2), `N` (1), then `N` level characters for the cells `x .. x+N-1` of
  row `y`; level 0 is an empty cell. Every character is a base64 digit (`A-Z a-z 0-9 + /`, its index is its
  value; two-digit numbers high digit first). Where a map has `fine`, the radar reads it too, folded to 100
  per side (each cell its hottest fine cell), so a cell the radar calls hot holds a fine cell drawn red, and
  both keep the server's per-cell floor; `map` stays for older copies and for maps `fine` leaves out. A bad
  `fine` is ignored whole; a map whose strings break the rules is ignored alone and falls back to `map`.
- **Unknown fields are ignored**, so the server can add fields without an addon update.
- **"No data yet"** is one state for every unusable file: missing, `NAGDeathData` nil, another `v`, a
  `map` that is not a table or holds no valid cell, or a bad `cellBase`. Nothing errors and nothing ticks.
- **"No data for this game"**: the file's `flavor` is not the running client's, told as NAG tells it
  (interface 16000..19999 or a 1.60+ build is Forever, `camelot`; then `vanilla`/`sod`, `tbc`, `wrath`/`titan`,
  `cata`, `mists`, `mainline`). The file is not loaded: nothing is drawn on the map or the radar. A file
  without `flavor` (only Forever ever wrote one) draws on Forever only.
- On a map the file has no cells for, the radar and the world map say **"no data for this map"**.

The settings panel and `/ndr` show the data's date (UTC) and, when the file carries them, its row and
player counts.

## Privacy

The file holds aggregates only: per map, a smoothed and normalised intensity per cell, never a single
death, a name, a realm, a GUID or an account. A map is published only when at least three different
players died there (the published snapshot of relay 3460 also withholds the whole file until the
flavour has three contributors). Deaths caused by other players and deaths above the flavour's level cap
are never counted; deaths at the cap are.

## Tests

```
luajit tests/run.lua
lua5.1 tests/run.lua
luajit tests/perspective_geometry.lua
luajit tests/perspective_shared.lua
luajit tests/perspective_runtime.lua
luajit tests/world_projection.lua
luajit tests/world_view.lua
```

The runner loads the addon in toc order against `tests/wowstub.lua`, a strict WoW API stub (a widget
method the stub does not know raises), and checks the data states, the cell base, the radar's maths
(facing up, the rim clamp, yards, the nearest danger zone), the heatmap (the upsampling and its band floor,
the `fine` decoder, the row runs and the cap, the shared edges), the slash command and the settings panel. The fixtures in `tests/fixtures/` are written by the server's own export code:

```
python3 -I tools/make_fixtures.py --tools-repo <a NextActionGuide-Tools clone> [--rev origin/main]
```

`nagdeath_fine.lua` needs a revision with the server's `fine()` (Tools PR #1142 and after); a revision
without it leaves that fixture as it is.

The radar's hot ring, `Media/HotRing.tga`, is ours: `python3 -I tools/make_hotring.py` writes it.

The in-game checks are in [CHECKLIST.md](CHECKLIST.md).

## Licence

CC BY-NC 4.0, the same as Next Action Guide; see [LICENSE](LICENSE). The radar's geometry and drawing
helpers come from NAG's Shaman totem radar. The ring and grid art (`Media/frame1.png`, `frame2.png`,
`frame8.png`, `frame10.png`, `radarGrids1.png`, `radarGrids2.png`) are Fonsas's own, from his
FonsasDeathRadar. Nothing is taken from Deathlog or DeathNotificationLib.

The addon is free.
