# NAG Death Radar: in-game checklist

From the plan note's §3 (in game), plus everything the headless tests cannot show. Run on WoW Forever
first, then on one Classic-line client. Enable script errors first: `/console scriptErrors 1`. Note the
client build and anything odd.

## 0. First perspective version (Forever)

- [ ] Restart the client once to discover the new Lua files and Bindings.xml; confirm the addon version is the local perspective build.
- [ ] `/ndr mode perspective`: the old circle is absent. Journey need not be enabled.
- [ ] `/ndr preview on`: the view is clearly labelled synthetic; `/ndr preview off` returns to live data without changing the data file or world-map picture.
- [ ] With the camera behind the character, walk toward and around multiple areas. Turn the character: forward/left/right remain consistent. Gaps and holes stay open; no line closes a region at the 180-yard view edge.
- [ ] Open the world map: the perspective areas agree with its red regions, including after `/ndr threshold 0.4` and while browsing another map.
- [ ] Stand inside an area larger than the view: a quiet near-player tint and inside status remain even when no boundary is visible.
- [ ] Outside all areas with none ahead: no geometry or idle heading line remains. Missing data/map/position instead shows its explicit status and never stale shapes.
- [ ] Bind Hold danger-view details in WoW Key Bindings > NAG Death Radar. Hold: stronger contours/fill and approximate boundary distance. Release, rebind, open chat or leave/reenter the client: detail must not stick.
- [ ] `/ndr options`: adjust reach, width, height, size and offsets; verify `/reload` preserves them. All clicks through the drawing still reach the world.
- [ ] Hold Alt: a highlighted move field appears, including when no areas are visible or data is absent. Alt + left-drag moves the view; release Alt while dragging and verify movement stops and mouse clicks pass through. Test again at size 1.5 and confirm placement survives `/reload`. Switching modes or losing control while dragging must stop the move.
- [ ] `/ndr front` (or `/ndr ground`): the field extends upwards from 60 UI units above screen centre, in front of/above the character, with height 160 and no centre heading line. Fine-tune with Alt-drag. Custom placement survives `/reload`; old default offsets, including the centre and below-feet presets, migrate only once.
- [ ] During combat, rendering continues while coordinates are available; hidden/secret coordinates clear it without Lua errors or blocked actions.
- [ ] Dense real area at `/ndr reach 300`: check movement/turning remains responsive. Report build, map and symptoms if it does not.
- [ ] Rotate/pitch only the camera: confirm the known illustration limitation rather than accepting this as terrain/camera-anchored geometry.
- [ ] `/ndr options` offers explicit Perspective and Radar buttons with the current choice marked. `/ndr mode radar` (also `mode circle`) restores the original radar; `/ndr mode perspective` returns to the perspective view. Switching from either entry point updates the other and survives `/reload`. `/ndr probe` still works.

To try with data before the app drops the real file: copy `tests/fixtures/nagdeath_base0.lua` over
`NAGDeathRadar/Data/NAGDeathData.lua` and `/reload`. It has cells on Elwynn Forest (1429) and Durotar
(1411) only, so try it on a character in one of those zones. `tests/fixtures/nagdeath_fine.lua` is the same
deaths with the server's `fine` field (200 per side): swap it in to see the map draw the file's own fine cells.

## 0b. Plain look, minimap and totem radar (Forever, 2026-10-29)

- [ ] Fresh settings (or saved settings still on the old defaults): after `/reload` the circle radar shows, no
      ornament, a thin dark rim over a see-through field, the same size as NAG's totem radar.
- [ ] `/ndr art on`: the ornament ring and grid come back; `/ndr ring 8`, `/ndr grid 2` still work.
- [ ] Alt + right-click the radar: the menu opens. "Attach to the minimap": the radar sits on the minimap at its
      size, half see-through, no arrow of its own, north up; with Interface > Rotate Minimap on, it turns with you.
      The minimap's own clicks still work (without Alt). Untick it: back where it was.
- [ ] As a Shaman with the totem radar shown: the menu offers "Unify with the totem radar (one ring)". Ticked, one
      ring shows (the totem radar's) with the death cells inside it, on its 40-yard scale (a death cell 40 yd away
      sits on the rim; free, the same cell sits at 40 % of the radius); drag or resize the totem radar, or put it on
      the minimap: the death radar follows. Hide the totem radar (`/nagtotem off`): the death radar stands on its
      own with its own ring; `/nagtotem on`: it joins again.
- [ ] Without the client's context menu (no MenuUtil), Alt + right-click opens the settings panel instead.
- [ ] `/ndr minimap`, `/ndr unify` toggle the same; the choice survives `/reload`.

## 1. Load without NAG
- [ ] With NAG disabled, the addon list shows "NAG Death Radar", not flagged out of date (on Forever the
      `_camelot` toc loads; on Classic Era, Anniversary, Titan and MoP Classic the main toc).
- [ ] No Lua error on login, `/reload` or a zone change.

## 2. No data yet
- [ ] With `tests/fixtures/nagdeath_placeholder.lua` (the placeholder of releases before 0.3.0) over
      `Data/NAGDeathData.lua`, `/reload`: the radar's centre says "no data yet"; the
      world map says "NAG Death Radar: no data yet" at its bottom; `/ndr` says "no data yet".
- [ ] Delete `Data/NAGDeathData.lua`, `/reload`: the same, no error.
- [ ] Put `NAGDeathData = { v = 2, map = {} }` in the file, `/reload`: the same.

## 3. The heatmap (with the fixture)
- [ ] Forever 16001 has the world map canvas: the map of Elwynn Forest shows the heat as a smooth ramp, a
      faint light blue through teal-green, gold and orange to reds that deepen with the danger, with no hard
      steps between shades; the gold still reads on the Barrens' and Durotar's yellow-brown ground; the red is
      where the radar's red is.
- [ ] The squares sit over the map art and the explored-area art, BELOW the pins (flight points, quest
      markers) and the player arrow.
- [ ] Titan Reforged and MoP Classic only: with a quest whose objective area shows on the map, note
      whether the heat squares draw over or under the quest area. They share its frame level there, so
      either is possible; check that both stay readable.
- [ ] The squares are 200 per side at every zoom: zooming in and out only scales them, and nothing lags.
      The picture is smooth between cells (no single blocks of 1/100 of the map). The cells under the spot
      the radar points at are red at every zoom, and `/ndr threshold 0.4` turns the same cells yellow on the
      map and the radar.
- [ ] No seams: zoomed in and at in-between zoom levels, touching squares of one colour show no gap and no
      darker line where they meet.
- [ ] Resize or maximise the map window: the squares stay aligned with the map.
- [ ] A continent, or a zone without data: no squares, the note "no data for this map".
- [ ] `/ndr map off` hides the squares and the note; `/ndr map on` brings them back.
- [ ] Forever: the world map's filter button opens its menu with a "NAG Death Radar" section at the
      bottom and a "Show deaths heatmap" check box; ticking it hides and shows the squares at once. There is
      no Deaths box on the Forever map.
- [ ] Classic Era, Anniversary, Titan Reforged and MoP Classic (no filter button on their maps): the
      **Deaths** box sits in the top-right corner of the map area, above the pins, hides with the map and
      overlaps none of Blizzard's buttons, maximised and windowed:
  - [ ] Classic Era and Anniversary (Vanilla and TBC maps): clear of the close and maximise buttons and the
        dropdown bar above the map.
  - [ ] Titan Reforged (Wrath map) and MoP Classic (Cata map): clear of the floor dropdown and its up/down
        buttons, maximised (in the bar) and windowed (top left of the map).
- [ ] The menu entry (or the box), `/ndr map` and the panel's check box move each other, and the choice survives `/reload`.
- [ ] At the default opacity the map art reads through the squares and red still reads red. `/ndr alpha 0.4`
      and the panel's slider (or its step button) lighten the squares only; the radar does not change.
- [ ] The squares near a corner of Elwynn line up with the edge (cell 99/0 is the top-right corner cell).

## 4. The radar
- [ ] The art loads: Fonsas's ring (`Media/frame1.png`) and the green grid (`Media/radarGrids1.png`)
      show. If a PNG does not load on this client, a plain dark ring and a dark field remain; note which.
- [ ] Each ring lines up: its hole meets the field with no gap and no field showing past it, and the
      radar's drag box (Alt + hover shows the tooltip at its top edge) holds the whole ring:
  - [ ] `/ndr ring 1` (dark iron, dragons)
  - [ ] `/ndr ring 2` (plain silver)
  - [ ] `/ndr ring 8` (spiked dark)
  - [ ] `/ndr ring 10` (cyan tech)
- [ ] `/ndr grid 2`: the blue grid fills the field like the green one; the light-blue blips stay readable
      on it (the reason green is the default).
- [ ] `/ndr art off`: the ring and grid go, a plain dark ring and field remain, the radar shrinks to them;
      `/ndr art on` brings them back. The red rim tint shows in both.
- [ ] Turn in place: the picture turns, the arrow in the middle never does; what is ahead of the
      character is at the top.
- [ ] The cells are round blips (light blue, yellow, red), cut at the radar's circle.
- [ ] Walk away from a red spot past 100 yd: the red marker sits on the rim, pointing at it; the line
      under the radar says "danger N yd" and N grows as you walk away. Walk back: the marker leaves the
      rim when the spot comes within range.
- [ ] Westfall or the Barrens (maps that are not square): walking straight east and straight north
      moves the picture at the same speed.
- [ ] Stand in a red cell: a plain red band lies over the ring's inner edge and the line says "danger: you
      stand in a hot zone"; it reads red on `/ndr ring 1`, `2`, `8`, `10` and with `/ndr art off` (then over
      the plain rim). This checks that `Media/HotRing.tga` loads. Step out: it goes. `/ndr tint off`: no
      band. No screen glow, no sound.
- [ ] In a dungeon or a battleground: "no position here" or "no data for this map", no error; the radar
      dims to about 30 % and the note stays readable. Back outside, it is full again.
- [ ] `/ndr range 50` and `/ndr scale 1.5`: the picture zooms and the radar grows, in place.

## 5. Mouse, drag, settings
- [ ] Without Alt, clicking or right-click-turning the camera over the radar acts on the world (the radar
      takes no click).
- [ ] Alt + drag moves the radar; releasing Alt ends the drag. `/ndr lock`: Alt + drag does nothing.
- [ ] Hover a bag item or an NPC so its tooltip shows, then press and release Shift, Ctrl and Alt: that
      tooltip stays (with the radar shown and with `/ndr hide`).
- [ ] Hold Alt and hover the radar: a tooltip with the data line and "Right-click: settings". Alt +
      right-click opens the settings panel; in combat neither shows. Without Alt, a right-click on it turns
      the camera as usual.
- [ ] Options > AddOns lists "NAG Death Radar" with its five check boxes, the Ring and Grid buttons and the
      data line; `/ndr options` opens it (out of combat).
- [ ] The ring, grid and art choice survive `/reload` and a cold start.
- [ ] The place, size and switches survive `/reload` AND a cold start (quit the client, start again):
      Forever's SavedVariables history makes the cold start the real test.

## 6. Combat and taint
- [ ] Fight with the radar shown and the world map opened and closed: no error, no
      "action blocked" / taint message (`/console taintLog 1`, then check `Logs/taint.log`).
- [ ] In an instance: positions hidden by the client show "no position here", nothing errors.

## 7. Quiet by design
- [ ] The addon sends no chat or addon messages.
- [ ] CPU stays small while walking (profiling on:
      `/run UpdateAddOnCPUUsage() print(GetAddOnCPUUsage("NAGDeathRadar"))`).

## 8. Experimental World view (0.3.0-dev8)
- [x] Stress Test 70532: World (test), Perspective and Radar selected through settings; World preview/stop/status exercised through commands. Dev7 loaded after `/reload`.
- [ ] `/ndr world preview` is clearly marked as a moved/scaled replay, with faint fill and readable contours.
- [x] Stress Test 70532: camera yaw/pitch changed the replay's screen position; some angles hid it and a flatter angle recovered it. The outline was extremely shallow. Reliable alignment remains unproven.
- [ ] Hold the details binding: contours strengthen; release it: they return to normal.
- [ ] `/ndr world stop` removes the temporary waypoint and restores the previous quest target.
- [ ] Change to a different waypoint/quest while World runs: it pauses and preserves the new target.
- [ ] Starting World with an existing user waypoint leaves it untouched and explains the pause.
- [x] Stress Test 70532: `/reload` with World selected reported stopped, accepted 0/0, tracking released; no temporary minimap waypoint appeared.
- [ ] Test near actual red regions while moving; compare boundaries and holes with the map. Replay is not this proof.
- [ ] Enter combat: sampling pauses; deferred navigation restoration finishes after combat, without automatic resume.
- [ ] Check slopes, water, bridges, buildings and low frame rates; terrain height and occlusion remain unverified.
- [x] Stress Test 70532: a new character with nil quest/type starts after the dev7 fix. Stop restored waypoint=nil, quest=nil, user=false, type=nil. Restoration of an actual tracked quest remains unchecked above.
- [x] Lua 5.1 and LuaJIT: 179 checks passed per engine, including malformed tracking rejection, nil-quest restoration, captured error diagnostics, and persistent replay warning during recalibration.

Dev8 follow-up:
- [x] Lua 5.1 and LuaJIT: 187 checks pass per engine, including delayed native projection, diagonal-only visibility, shallow-plane rejection, early rejection accounting, and a recorded native batch regression.
- [ ] Fresh native test: two-update settling still follows camera changes and releases navigation correctly.
- [ ] Rotate the camera independently of character heading, including diagonal views; check recovery.
- [ ] A nearly edge-on reference plane hides the drawing and requests a downward camera tilt; no inflated shapes.
- [ ] `/ndr world status` includes early rejections while repeatedly losing calibration and while moving.

2026-10-22: fresh native test blocked. Reconnect returned WOW51900308 and requested
login. Battle.net Play was disabled with "This game cannot be played yet" and
"Available November 4, 2026"; Stress Test was absent from its version list.
Dev8 source and manifests match both installed junctions. Blocker evidence is local
in `../artifacts/world-dev8-20261022/`; this is not dev8 runtime validation.

Client evidence from 2026-10-21 is kept locally in `../artifacts/stress-client-dev6-20261021/`.
NAG 5.6.41-beta10, NAGJourney 1.0.2 and NAGDeathRadar loaded together. The real map
heatmap rendered in Mulgore; Radar reported the nearest danger at 392 yd, outside the
180 yd view range. A single brief movement key tap is not a running/boundary test.
Replay screenshots do not validate actual danger locations, terrain heights or combat behavior.

Dev9 audit, 2026-10-22 (Forever Beta):
- [x] Dev8 startup failure reproduced with existing quest 1505. The client's waypoint switch returned quest=nil; the old ownership guard paused and left an empty user-tracking flag.
- [x] Dev9 loaded in the client. Replay starts from that same tracked-quest state; stop returns quest=1505, user=false, waypoint=nil.
- [x] An external change to quest 772 pauses the view, removes its own waypoint and preserves quest=772, user=false.
- [x] Lua 5.1 and LuaJIT: 197 checks pass per engine. Includes native quest clearing, partial tracking-setter failures, throttled restoration, simulated 60 FPS running, retained drift limits and replay containment/gaps.
- [x] Short local movement at verified 60 FPS: contour hid during movement and returned after stopping. Status recorded attempts=700, accepted=675, rejected=24 (clamped=21, drift=2, holdout=1), accepted while moving=0. Most accepted batches were stationary; this fails continuous running validation.
- [ ] Replace or compensate sequential camera sampling and repeat the moving test before calling this a usable world risk view.
- [ ] Replay inside indicator is covered automatically; verify it in the native client without treating replay as actual danger data.
- [ ] Actual danger boundaries, terrain height, slopes, occlusion and combat remain unvalidated for dev9.

Audit evidence is local in `../artifacts/world-dev9-audit-20261022/`.

Dev10 motion compensation, 2026-10-22 (Forever Beta):
- [x] Independent source-coordinate fit compensates per-sample player translation; two spatial holdouts and the repeated anchor remain outside fitting with four UI pixel limits.
- [x] Lua 5.1 and LuaJIT: 200 checks pass per engine, including sideways/diagonal running, large raw drift, end-position reprojection, source degeneracy and rejected camera drift.
- [x] Final source loaded in Beta at observed 60 FPS. Short local run: attempts=421, accepted=418, rejected=2 (holdout), accepted while moving=9, maximum raw moving drift=15.1 px, maximum compensated residual=0.6 px. One attempt was in progress; the overall 4.3 accepted/s includes stationary time.
- [x] A copied real map outline stays recognisable as the player approaches it. Entry into the earlier dev10 replay showed the explicitly labelled inside indicator.
- [x] Replay stopped and temporary user waypoint released. Test FPS settings restored to their previous values.
- [ ] Validate sustained movement with camera turns, actual risk boundaries, slopes, terrain height, occlusion, combat and low frame rates. Earlier dev10 footage still showed a brief hide during camera adjustment at movement start.

Evidence: `../artifacts/world-dev10-motion-20261022/`. The preview is a moved/scaled copy of real map geometry, not actual danger at the test location.

Dev11 direction fallback and quiet map, 2026-10-22:
- [x] Normal World mode defaults to `worldAnchors=false`. Regression tests assert zero navigation reads/writes even with an existing user pin and throwing navigation getters.
- [x] Camera sampling requires an explicit settings/slash opt-in that warns about moving map/minimap pins. Switching it off releases the temporary pin and retains the direction view.
- [x] Clamped/invalid/shallow samples and collapsed projected fills select the labelled approximate view using the exact same geometry, including moved replay shapes.
- [x] Combat and external navigation takeover keep a read-only direction view without automatically restarting sampling; explicit stop/mode/hide clear it.
- [x] Direction view follows movement at up to 60 FPS and reuses stationary geometry. Camera projections translate between validated batches, with a 350 ms maximum age.
- [x] Separate finite, bounded contour/fill controls. Lua 5.1 and LuaJIT each passed 211 checks before the native test.
- [x] Native dev11 reload and quiet replay: status recorded zero sampling attempts, waypoint sampling off and no user waypoint. Map/minimap inspection showed no experimental pin. The copied replay outline and all new settings controls were visible. Replay was stopped before returning to normal data.
- [ ] Native preservation of an existing user pin in quiet mode remains untested; zero-navigation behavior with an existing pin is covered automatically.
- [ ] Native combat, sustained running, actual boundary alignment and terrain height remain separate checks. This change does not solve the elevation difference in the user's screenshots.

PR #6 review fixes, 0.3.0-dev12, 2026-10-27:
- [x] Quiet World viewing survives leaving combat without navigation access. Settings retain paused sampling after combat or an external quest takeover; explicit start or a fresh sampling opt-in can resume it.
- [x] Help, options, probe and status do not interrupt active sampling or change navigation. Layout changes preserve a replay's original map position.
- [x] Perspective redraws after temporary map, heading or map-size loss even when the character remains stationary.
- [x] Contour and nested-fill budgets are checked before constructing the full draw model. Dense input returns an explicit complexity state with no partial regions.
- [x] All six suites pass in Lua 5.1 and LuaJIT: 228 checks per interpreter, zero failures. A separate differential check preserves all model fields in 60 under-budget cases per interpreter.
- [x] A local synthetic 2500-run stress case fell from 318 ms to 7 ms in Lua 5.1 and from 56 ms to 5 ms in LuaJIT by rejecting the over-budget model early. These timings are host-specific and do not measure native client FPS.
- [ ] Repeat combat exit, settings after a pause, stationary position recovery and dense-region behavior in Forever. These review fixes have automated validation only.
