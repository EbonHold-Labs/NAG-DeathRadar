# NAG Death Radar: in-game checklist

From the plan note's §3 (in game), plus everything the headless tests cannot show. Run on WoW Forever
first, then on one Classic-line client. Enable script errors first: `/console scriptErrors 1`. Note the
client build and anything odd.

To try with data before the app drops the real file: copy `tests/fixtures/nagdeath_base0.lua` over
`NAGDeathRadar/Data/NAGDeathData.lua` and `/reload`. It has cells on Elwynn Forest (1429) and Durotar
(1411) only, so try it on a character in one of those zones.

## 1. Load without NAG
- [ ] With NAG disabled, the addon list shows "NAG Death Radar", not flagged out of date (on Forever the
      `_camelot` toc loads; on Classic Era, Anniversary, Titan and MoP Classic the main toc).
- [ ] No Lua error on login, `/reload` or a zone change.

## 2. No data yet
- [ ] With the shipped placeholder `Data/NAGDeathData.lua`: the radar's centre says "no data yet"; the
      world map says "NAG Death Radar: no data yet" at its bottom; `/ndr` says "no data yet".
- [ ] Delete `Data/NAGDeathData.lua`, `/reload`: the same, no error.
- [ ] Put `NAGDeathData = { v = 2, map = {} }` in the file, `/reload`: the same.

## 3. The heatmap (with the fixture)
- [ ] Forever 16001 has the world map canvas: the map of Elwynn Forest shows yellow-to-red squares.
- [ ] The squares sit over the map art and the explored-area art, BELOW the pins (flight points, quest
      markers) and the player arrow.
- [ ] Titan Reforged and MoP Classic only: with a quest whose objective area shows on the map, note
      whether the heat squares draw over or under the quest area. They share its frame level there, so
      either is possible; check that both stay readable.
- [ ] On a zoomable map, zooming in and out changes the square size (25 -> 50 -> 100 per side) and nothing
      lags. On a map that cannot zoom (a city or small zone where the mouse wheel does nothing), the
      squares are at full detail (100 per side).
- [ ] Resize or maximise the map window: the squares stay aligned with the map.
- [ ] A continent, or a zone without data: no squares, the note "no data for this map".
- [ ] `/ndr map off` hides the squares and the note; `/ndr map on` brings them back.
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
