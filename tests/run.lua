-- Headless tests for NAG Death Radar. From the repo root:
--   luajit tests/run.lua      or      lua5.1 tests/run.lua
-- Each boot loads the addon files in toc order against tests/wowstub.lua (STRICT: an unknown widget method
-- raises) and fires the client's load events; the tests drive the player and read back what was drawn.
--
-- License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/legalcode)

local base = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]run%.lua$") or "."
package.path = base .. "/tests/?.lua;" .. package.path
local S = require("wowstub")
local ADDON = base .. "/NAGDeathRadar/"
local FIXTURES = base .. "/tests/fixtures/"

local function out(s) io.write(s, "\n") end
local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1; out("ok   " .. name)
    else fail = fail + 1; out("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, what)
    if a ~= b then error((what or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function near(a, b, what, tol)
    if math.abs(a - b) > (tol or 1e-9) then error((what or "") .. ": expected " .. b .. ", got " .. a, 2) end
end

local function tocLines(name)
    local files, meta = {}, {}
    for line in io.lines(ADDON .. name) do
        local k, v = line:match("^## ([%w]+): (.*)$")
        if k then meta[k] = v
        elseif line:match("%S") and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    return files, meta
end
local FILES = tocLines("NAGDeathRadar.toc")
local DATA_FILE = "Data/NAGDeathData.lua"

--- Load the addon as the client would: toc order, (addonName, ns) varargs, then the load events.
--- data: nil = the shipped placeholder; a string = a fixture file in its place; a table (or false for nil) = the
--- global set as it is, no data file read.
local function boot(data, opts)
    S.reset(opts)
    local ns = {}
    for _, f in ipairs(FILES) do
        if f == DATA_FILE and data ~= nil then
            if type(data) == "string" then assert(loadfile(FIXTURES .. data))() else NAGDeathData = data or nil end
        else
            assert(loadfile(ADDON .. f))("NAGDeathRadar", ns)
        end
    end
    if opts and opts.saved then NAGDeathRadarSettings = opts.saved end
    S.fire("ADDON_LOADED", "NAGDeathRadar")
    S.fire("PLAYER_LOGIN")
    return ns
end

local function readFixture(name)
    local env = {}
    local chunk = assert(loadfile(FIXTURES .. name))
    setfenv(chunk, env)
    chunk()
    return env.NAGDeathData
end

-- Elwynn Forest in the stub's world: 3470 x 2315 yards (top, left, bottom, right).
local ELWYNN, DUROTAR, NO_DATA_MAP = 1429, 1411, 947
local ELWYNN_BOUNDS = { 1500, 1000, -815, -2470 }
local W_ELWYNN, H_ELWYNN = 3470, 2315

-- ============================ tocs and the stub ============================

test("tocs: the same files; main covers the Classic line, _camelot is Forever only", function()
    local c, cm = tocLines("NAGDeathRadar_camelot.toc")
    local _, mm = tocLines("NAGDeathRadar.toc")
    eq(table.concat(c, ","), table.concat(FILES, ","), "file list")
    eq(FILES[1], DATA_FILE, "the data loads first")
    eq(mm.Interface, "11509, 20506, 38000, 38002, 50504", "main interfaces")
    eq(mm.SavedVariables, "NAGDeathRadarSettings"); eq(cm.SavedVariables, "NAGDeathRadarSettings")
    eq(cm.Interface, "16001"); eq(cm.AllowLoadGameType, "camelot")
end)

test("strict stub: an unknown widget method raises, a probed one reads nil", function()
    S.reset()
    local f = CreateFrame("Frame")
    assert(not pcall(function() return f:NoSuchMethod() end), "unknown frame method must raise")
    assert(not pcall(function() return f:CreateTexture():SetText("x") end), "a texture has no SetText")
    assert(not pcall(function() return f:CreateFontString():SetTexture("x") end), "a font string has no SetTexture")
    eq(f.GetCanvasZoomPercent, nil, "probed name")
end)

-- ============================ data ============================

test("the shipped data file is a placeholder: it defines no global", function()
    local env = {}
    local chunk = assert(loadfile(ADDON .. DATA_FILE))
    setfenv(chunk, env)
    chunk()
    eq(next(env), nil, "no global")
end)

local NO_DATA_STATES = {
    { "missing file (the placeholder)", nil },
    { "nil global", false },
    { "wrong v", { v = 2, map = { [ELWYNN] = { [1] = { [1] = 50 } } } } },
    { "map = {}", { v = 1, map = {} } },
    { "map of a bad type", { v = 1, map = "x" } },
    { "a map entry of a bad type", { v = 1, map = { [ELWYNN] = "x" } } },
    { "cells of bad types only", { v = 1, map = { [ELWYNN] = { [1] = { [1] = "hot", [2] = 0 }, x = {} } } } },
    { "cellBase of a bad type", { v = 1, cellBase = "0", map = { [ELWYNN] = { [1] = { [1] = 50 } } } } },
    { "cellBase out of range", { v = 1, cellBase = 2, map = { [ELWYNN] = { [1] = { [1] = 50 } } } } },
    { "v of a bad type", { v = "1", map = { [ELWYNN] = { [1] = { [1] = 50 } } } } },
}

for _, st in ipairs(NO_DATA_STATES) do
    test("no data yet: " .. st[1] .. " -> one state on the radar and the map, nothing ticks", function()
        local ns = boot(st[2])
        eq(ns.data, nil, "no data")
        local f = ns.RadarFrame
        eq(f.note:IsShown(), true, "radar note shown"); eq(f.note:GetText(), "no data yet", "radar note")
        eq(S.liveUpdates(), 0, "no OnUpdate")
        eq(ns.Radar.BlipCount(), 0, "no blips")
        S.mapID = ELWYNN
        WorldMapFrame:OnMapChanged()
        eq(ns.OverlayCount(), 0, "nothing drawn")
        eq(ns.OverlayNote(), "NAG Death Radar: no data yet", "map note")
        S.frame(1) -- a client frame passes: nothing runs, nothing errors
        eq(ns.StatusLine(), "no data yet")
    end)
end

test("fixtures from the server's to_lua: cells in range for their base, q 1..100", function()
    for name, b in pairs({ ["nagdeath_base0.lua"] = 0, ["nagdeath_base1.lua"] = 1 }) do
        local d = readFixture(name)
        eq(d.v, 1, name .. " v"); eq(type(d.generated), "number", name .. " generated is epoch seconds")
        local cells = 0
        for m, cols in pairs(d.map) do
            for x, col in pairs(cols) do
                assert(x >= b and x <= b + 99, name .. " x " .. x)
                for y, q in pairs(col) do
                    assert(y >= b and y <= b + 99 and q >= 1 and q <= 100, ("%s %d %d %d %s"):format(name, m, x, y, q))
                    cells = cells + 1
                end
            end
        end
        assert(cells > 20, name .. " cells " .. cells)
    end
    eq(readFixture("nagdeath_base0.lua").cellBase, 0); eq(readFixture("nagdeath_base1.lua").cellBase, nil)
end)

test("cell base: the 0-based and the 1-based fixture land on the same cells", function()
    local ns = boot(false)
    local d0 = assert(ns.LoadData(readFixture("nagdeath_base0.lua")))
    local d1 = assert(ns.LoadData(readFixture("nagdeath_base1.lua")))
    eq(d0.base, 0); eq(d1.base, 1)
    local n = 0
    for m, cols in pairs(d0.map) do
        for ix, col in pairs(cols) do
            for iy, q in pairs(col) do
                eq(d1.map[m][ix][iy], q, ("cell %d %d %d"):format(m, ix, iy)); n = n + 1
            end
        end
    end
    eq(n, d0.cells, "every cell compared"); eq(d1.cells, d0.cells, "same count")
    eq(d0.map[ELWYNN][99][0] ~= nil, true, "the corner cell (99, 0) of the 0-based file is kept")
    eq(d1.map[ELWYNN][99][0], d0.map[ELWYNN][99][0], "the 1-based file's cell (100, 1) is the same corner")
end)

test("unknown fields are ignored; published is shown as a date, else generated", function()
    local raw = readFixture("nagdeath_base0.lua")
    assert(raw.futureField and raw.killers and raw.bands and raw.instances, "the fixture carries other fields")
    local ns = boot("nagdeath_base0.lua")
    assert(ns.data, ns.dataReason)
    eq(ns.StatusLine(), "death data from 2026-10-18: 231 deaths, 5 players, 2 maps")
    ns = boot("nagdeath_base1.lua")
    eq(ns.StatusLine(), "death data from 2026-10-19, 2 maps")
    local d = ns.LoadData({ v = 1, map = { [ELWYNN] = { [1] = { [1] = 9 } } }, extra = function() end, generated = "x" })
    assert(d, "a field of an unknown type is still ignored")
    eq(d.stamp, nil, "a generated that is not epoch seconds gives no date")
end)

-- ============================ pure maths ============================

test("CellIndex: the server's binning, 0..99, off the map nil", function()
    local ns = boot(false)
    eq(ns.CellIndex(0), 0); eq(ns.CellIndex(1), 99); eq(ns.CellIndex(0.5), 49); eq(ns.CellIndex(0.505), 50)
    eq(ns.CellIndex(0.01), 0, "the server's cells are 100.01 units wide"); eq(ns.CellIndex(0.0101), 1)
    eq(ns.CellIndex(-0.001), nil); eq(ns.CellIndex(1.001), nil); eq(ns.CellIndex(nil), nil); eq(ns.CellIndex(0 / 0), nil)
    for n = 0, 10000, 37 do -- the addon's own floor(p * 10000 + 0.5), then the server's n * 100 // 10001
        eq(ns.CellIndex(n / 10000), math.floor(n * 100 / 10001), "n " .. n)
    end
end)

test("rotation: the facing is up", function()
    local ns = boot(false)
    local R = ns.Radar
    local x, y = R.ToPlane(10, 0, 0, 1)            -- north, facing north: straight up
    near(x, 0, "north x"); near(y, 10, "north y")
    x, y = R.ToPlane(0, 10, 0, 1)                   -- west, facing north: left
    near(x, -10, "west x"); near(y, 0, "west y")
    x, y = R.ToPlane(0, 10, math.pi / 2, 1)         -- west, facing west: up
    near(x, 0, "facing west x"); near(y, 10, "facing west y")
    x, y = R.ToPlane(10, 0, math.pi / 2, 1)         -- north, facing west: right
    near(x, 10, "north when facing west x"); near(y, 0, "north when facing west y")
    x, y = R.ToPlane(10, 0, math.pi, 2)             -- north, facing south: down, at 2 px per yard
    near(x, 0, "facing south x"); near(y, -20, "facing south y")
end)

test("rim clamp: a spot past the rim keeps its direction at the border", function()
    local ns = boot(false)
    local R = ns.Radar
    local x, y = R.ToScreen(300, 400, 0, 1)         -- 500 yd away at 1 px per yard
    near(math.sqrt(x * x + y * y), R.LIMIT, "on the rim")
    near(x / y, -400 / 300, "same direction")
    x, y = R.ToScreen(3, 4, 0, 1)                    -- inside: untouched
    near(x, -4, "inside x"); near(y, 3, "inside y")
end)

test("yard scaling: a cell's vector is in yards on a 3:2 map", function()
    local ns = boot(false)
    local R = ns.Radar
    -- The player in the middle of cell (50, 50); the cell east of it is one cell width east (negative west).
    local px, py = ns.CellCentre(50), ns.CellCentre(50)
    local dn, dw = R.CellVector(px, py, 51, 50, W_ELWYNN, H_ELWYNN)
    near(dn, 0, "east: no north"); near(dw, -W_ELWYNN / 100, "east: one cell width", 1e-6)
    dn, dw = R.CellVector(px, py, 50, 49, W_ELWYNN, H_ELWYNN)
    near(dn, H_ELWYNN / 100, "north: one cell height", 1e-6); near(dw, 0, "north: no west")
end)

test("map yards: from GetWorldPosFromMapPos at the corners, GetMapWorldSize after, unknown nil", function()
    local ns = boot(false, { worldSize = true, secrets = true })
    S.worldBounds[9001] = { 500, 1200, -1500, 200 }
    local W, H = ns.MapYards(9001)
    near(W, 1000, "width = left - right"); near(H, 2000, "height = top - bottom")
    S.worldSize[9002] = { 3000, 1500 }
    local w2, h2 = ns.MapYards(9002)
    near(w2, 3000, "world size fallback"); near(h2, 1500)
    eq(ns.MapYards(9003), nil, "nothing known")
    S.worldBounds[9004] = S.SECRET
    eq(ns.MapYards(9004), nil, "a secret world position is not read")
end)

test("nearest hot cell: distance and vector in yards, heading on the radar", function()
    local ns = boot(false)
    local R = ns.Radar
    local md = { [10] = { [10] = 90, [12] = 20 }, [40] = { [40] = 100 } }
    local hot = R.HotCells(md, 0.25)
    eq(#hot, 2, "two cells at or above 25")
    -- The player at the middle of cell (13, 10) on a 1000 x 1000 yd map: (10, 10) is 30 yd due west.
    local d, dn, dw = R.NearestHot(hot, ns.CellCentre(13), ns.CellCentre(10), 1000, 1000)
    near(d, 30, "distance", 1e-6); near(dn, 0, "north", 1e-6); near(dw, 30, "west", 1e-6)
    local x, y = R.ToScreen(dn, dw, 0, 1)          -- facing north: due west is left on the radar
    near(x, -30, "left", 1e-6); near(y, 0, "level", 1e-6)
    x, y = R.ToScreen(dn, dw, math.pi / 2, 1)      -- facing west: straight ahead
    near(x, 0, "ahead x", 1e-6); near(y, 30, "ahead y", 1e-6)
    eq(R.NearestHot({}, 0.5, 0.5, 1000, 1000), nil, "no hot cell")
end)

test("rebucket, zoom and the texture cap", function()
    local ns = boot(false)
    local md = { [0] = { [0] = 10 }, [3] = { [3] = 50 }, [4] = { [4] = 30 }, [99] = { [99] = 7 } }
    local b25, n25 = ns.Rebucket(md, 25)
    eq(b25[1][1], 50, "0..3 merge, max kept"); eq(b25[2][2], 30, "4 -> bucket 2"); eq(b25[25][25], 7, "edge")
    eq(n25, 3, "count")
    local b100, n100 = ns.Rebucket(md, 100)
    eq(b100[1][1], 10); eq(b100[100][100], 7); eq(n100, 4)
    eq(ns.BucketsForZoom(0), 25); eq(ns.BucketsForZoom(0.5), 50); eq(ns.BucketsForZoom(1), 100)
    eq(ns.BucketsForZoom(nil), 25, "no zoom API")
    local dense = {}
    for x = 0, 99 do dense[x] = {}; for y = 0, 99 do dense[x][y] = 50 end end
    local _, n, count = ns.CappedBuckets(dense, 100, 2500)
    eq(n, 50, "10000 cells over the cap: 50 per side"); eq(count, 2500)
    _, n, count = ns.CappedBuckets(dense, 100, 100)
    eq(n, 25, "never coarser than 25"); eq(count, 625)
end)

test("colours: thresholds to light blue, yellow, red", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    eq(ns.Color(0.01, s), nil, "below low")
    local r, g, b = ns.Color(0.05, s); eq(r, 0); eq(g, 0.8); eq(b, 1)
    r, g, b = ns.Color(0.1, s); eq(r, 1); eq(g, 1); eq(b, 0)
    r, g, b = ns.Color(0.25, s); eq(r, 1); eq(g, 0); eq(b, 0)
end)

test("slash parser", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    s = ns.Command(s, "hide"); eq(s.radar, false)
    s = ns.Command(s, "show"); eq(s.radar, true)
    s = ns.Command(s, "lock"); eq(s.locked, true, "toggle")
    s = ns.Command(s, "lock off"); eq(s.locked, false, "explicit off")
    s = ns.Command(s, "map off"); eq(s.overlay, false)
    s = ns.Command(s, "tint"); eq(s.rimTint, false)
    s = ns.Command(s, "scale 1.5"); eq(s.scale, 1.5)
    local _, reply = ns.Command(s, "scale 5"); eq(s.scale, 1.5, "out of range kept"); assert(reply[1]:find("0.5"), reply[1])
    s = ns.Command(s, "range 150"); eq(s.yards, 150)
    s = ns.Command(s, "threshold 0.4"); eq(s.hot, 0.4)
    local _, _, action = ns.Command(s, "options"); eq(action, "panel")
    local _, help = ns.Command(s, ""); eq(help[1], "no data yet", "bare /ndr: the data line first"); eq(#help, 1 + #ns.HELP)
    s = ns.Command(s, "reset"); eq(s.radar, true); eq(s.hot, 0.25); eq(s.overlay, true); eq(s.yards, 100)
end)

test("slash: nan and inf are refused and leave the settings as they were", function()
    local ns = boot(false)
    for _, msg in ipairs({ "range nan", "range inf", "range -inf", "threshold nan", "threshold inf", "scale nan" }) do
        local s = ns.InitSettings(nil)
        local reply
        s, reply = ns.Command(s, msg)
        eq(s.yards, 100, msg .. " yards"); eq(s.hot, 0.25, msg .. " hot"); eq(s.scale, 1, msg .. " scale")
        assert(reply[1]:find(" takes ", 1, true), msg .. ": the usage line, got " .. tostring(reply[1]))
    end
end)

test("settings: missing, wrongly typed and out-of-range keys come back from defaults", function()
    local ns = boot(false)
    local s = ns.InitSettings({ scale = "big", yards = 5000, hot = 0 / 0, radar = false, custom = 1, radarPos = { x = "a" } })
    eq(s.scale, 1); eq(s.yards, 100); eq(s.hot, 0.25); eq(s.radar, false, "kept"); eq(s.custom, 1, "unknown kept")
    eq(s.radarPos.y, -200, "position reset")
    eq(ns.InitSettings(nil).rimTint, true, "rim tint on by default")
end)

test("addon never talks to the network or chat channels", function()
    for _, f in ipairs(FILES) do
        local src = assert(io.open(ADDON .. f)):read("*a")
        for _, api in ipairs({ "SendAddonMessage", "SendChatMessage", "C_ChatInfo", "JoinChannel",
            "RegisterAddonMessagePrefix", "C_Club", "BNSend" }) do
            assert(not src:find(api, 1, true), f .. " uses " .. api)
        end
    end
end)

-- ============================ the heatmap ============================

test("overlay: draws on map change, coarser zoomed out, no data for this map, off", function()
    local ns = boot("nagdeath_base0.lua")
    eq(ns.OverlayLevel(), 2004, "just above the explored-area level, below every pin")
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    local cells = 0
    for _, col in pairs(ns.data.map[ELWYNN]) do for _ in pairs(col) do cells = cells + 1 end end
    eq(ns.OverlayCount(), cells, "every Elwynn cell at full zoom")
    eq(ns.OverlayNote(), nil, "no note over data")
    S.zoom = 0
    WorldMapFrame:OnCanvasScaleChanged()
    assert(ns.OverlayCount() > 0 and ns.OverlayCount() < cells, "rebucketed " .. ns.OverlayCount())
    S.mapID = NO_DATA_MAP
    WorldMapFrame:OnMapChanged()
    eq(ns.OverlayCount(), 0, "nothing drawn"); eq(ns.OverlayNote(), "NAG Death Radar: no data for this map")
    S.mapID = ELWYNN
    SlashCmdList.NAGDEATHRADAR("map off")
    eq(ns.OverlayCount(), 0, "overlay off"); eq(ns.OverlayNote(), nil, "and quiet")
    SlashCmdList.NAGDEATHRADAR("map on")
    assert(ns.OverlayCount() > 0, "back")
end)

test("overlay: a map that cannot zoom is drawn at full detail; a zoomable one by its zoom", function()
    local ns = boot("nagdeath_base0.lua")
    local cells = 0
    for _, col in pairs(ns.data.map[ELWYNN]) do for _ in pairs(col) do cells = cells + 1 end end
    S.mapID, S.zoom, S.minScale, S.maxScale = ELWYNN, 0.5, 1, 1 -- one zoom scale: the client answers 0 %
    WorldMapFrame:OnMapChanged()
    eq(ns.OverlayCount(), cells, "single scale: every cell")
    S.minScale, S.maxScale, S.zoom = 0.5, 2, 0
    WorldMapFrame:OnCanvasScaleChanged()
    assert(ns.OverlayCount() < cells, "zoomable and zoomed out: coarser, got " .. ns.OverlayCount())
    S.zoom = 1
    WorldMapFrame:OnCanvasScaleChanged()
    eq(ns.OverlayCount(), cells, "zoomable and zoomed in: every cell")
end)

test("overlay: the corner cell of a 0-based file is drawn in the top-right corner", function()
    local ns = boot("nagdeath_base0.lua")
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    local found
    for _, o in ipairs(S.objects) do
        local p = o._point
        if o._color and o._shown and p and p[1] == "TOPLEFT" and p[4] == 99 * 10 and p[5] == 0 then found = true end
    end
    assert(found, "a texture at x = 99 cells, y = 0")
end)

test("overlay: a client without the world map canvas draws nothing and nothing errors", function()
    local ns = boot("nagdeath_base0.lua", { canvas = false })
    eq(ns.OverlayLevel(), nil, "no layer")
    eq(ns.OverlayCount(), 0)
end)

-- ============================ the radar ============================

local function hottestIn(ns, map)
    local bx, by, bq
    for ix, col in pairs(ns.data.map[map]) do
        for iy, q in pairs(col) do
            if not bq or q > bq then bx, by, bq = ix, iy, q end
        end
    end
    return bx, by, bq
end

local function standAt(map, ix, iy, facing)
    S.player.map, S.player.x, S.player.y = map, (ix + 0.5) / 100, (iy + 0.5) / 100
    S.player.facing = facing or 0
end

local function bootRadar(opts)
    local ns = boot("nagdeath_base0.lua", opts)
    S.worldBounds[ELWYNN] = ELWYNN_BOUNDS
    S.worldBounds[DUROTAR] = { 0, 0, -3000, -3000 }
    return ns
end

--- The overlay square at bucket (bx, by) of n per side on the stub's 1000 x 700 canvas, or nil.
local function squareAt(bx, by, n)
    local cw, ch = 1000 / n, 700 / n
    for _, o in ipairs(S.objects) do
        local p = o._point
        if o._color and o._shown and p and p[1] == "TOPLEFT" and math.abs(p[4] - (bx - 1) * cw) < 1e-6
            and math.abs(p[5] + (by - 1) * ch) < 1e-6 then
            return o
        end
    end
end

local function isRed(c) return c and c[1] == 1 and c[2] == 0 and c[3] == 0 end
local function isYellow(c) return c and c[1] == 1 and c[2] == 1 and c[3] == 0 end

-- One q-32 cell at (45, 28) among q-5 cells, as Rakizi's Barrens test showed: hot for the radar (0.32 >= 0.25).
local function barrensLike()
    local md = {}
    for x = 30, 60 do
        md[x] = {}
        for y = 15, 40 do md[x][y] = 5 end
    end
    md[45][28] = 32
    return { v = 1, cellBase = 0, map = { [ELWYNN] = md } }
end

test("overlay: a hot cell reads red on the map at every zoom, where the radar points", function()
    local ns = boot(barrensLike())
    S.worldBounds[ELWYNN] = ELWYNN_BOUNDS
    standAt(ELWYNN, 52, 30, 0)
    eq(ns.Radar.Paint(), "ok")
    local p = ns.Radar.Pointer()
    assert(p.tex:IsShown(), "the radar points at the hot cell")
    -- The pointer's vector is the hot cell's: (45, 28) from the player at (52, 30).
    local dn, dw = ns.Radar.CellVector(ns.CellCentre(52), ns.CellCentre(30), 45, 28, W_ELWYNN, H_ELWYNN)
    near(p.dx, dn, "north", 1e-6); near(p.dy, dw, "west", 1e-6)
    S.mapID = ELWYNN
    for _, z in ipairs({ { 0, 25 }, { 0.5, 50 }, { 1, 100 } }) do
        S.zoom = z[1]
        WorldMapFrame:OnCanvasScaleChanged()
        local n = z[2]
        local sq = squareAt(math.floor(45 * n / 100) + 1, math.floor(28 * n / 100) + 1, n)
        assert(sq, n .. " per side: the hot square is drawn")
        assert(isRed(sq._color), ("%d per side: the hot square is red, got %s %s %s"):format(n, sq._color[1], sq._color[2], sq._color[3]))
        assert(sq._color[4] >= 0.4, n .. " per side: at least red's floor, alpha " .. sq._color[4])
        local quiet = squareAt(math.floor(31 * n / 100) + 1, math.floor(16 * n / 100) + 1, n)
        assert(quiet and not isRed(quiet._color), n .. " per side: a q-5 square is not red")
    end
end)

test("overlay: the map's bands are the radar's, for q 1, 9, 10, 24, 25, 100", function()
    local md = { [10] = { [10] = 1 }, [20] = { [20] = 9 }, [30] = { [30] = 10 }, [40] = { [40] = 24 },
        [50] = { [50] = 25 }, [60] = { [60] = 100 } }
    local ns = boot({ v = 1, cellBase = 0, map = { [ELWYNN] = md } })
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    local s = NAGDeathRadarSettings
    for ix, col in pairs(md) do
        for iy, q in pairs(col) do
            local want = { ns.Color(q / 100, s) }
            local sq = squareAt(ix + 1, iy + 1, 100)
            if not want[1] then
                eq(sq, nil, "q " .. q .. ": below the low band, not drawn (as on the radar)")
            else
                assert(sq, "q " .. q .. " drawn")
                for k = 1, 3 do eq(sq._color[k], want[k], ("q %d channel %d"):format(q, k)) end
            end
        end
    end
end)

test("overlay and radar: a changed hot threshold moves both", function()
    local ns = boot(barrensLike())
    S.worldBounds[ELWYNN] = ELWYNN_BOUNDS
    standAt(ELWYNN, 45, 28, 0)
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    assert(isRed(squareAt(46, 29, 100)._color), "map: red at 0.25")
    SlashCmdList.NAGDEATHRADAR("threshold 0.4")
    assert(isYellow(squareAt(46, 29, 100)._color), "map: yellow at 0.4")
    ns.Radar.Paint()
    local blip
    for i = 1, ns.Radar.BlipCount() do
        local e = ns.Radar.Blip(i)
        if e.dx == 0 and e.dy == 0 then blip = e end
    end
    assert(blip, "the radar's blip under the player")
    assert(isYellow(blip.tex._vertex), "radar: yellow at 0.4")
    eq(ns.Radar.Pointer().tex:IsShown(), false, "radar: no hot cell left")
    SlashCmdList.NAGDEATHRADAR("threshold 0.25")
    assert(isRed(squareAt(46, 29, 100)._color), "map: red again")
    ns.Radar.Paint()
    assert(isRed(blip.tex._vertex), "radar: red again")
end)

-- The old ramp's weight (0.25 + 0.45 q/100), red never under 0.4, times the opacity setting.
local function mapWeight(q, red, mapAlpha)
    local a = 0.25 + 0.45 * math.min(q, 100) / 100
    if red and a < 0.4 then a = 0.4 end
    return a * (mapAlpha or 1)
end

test("overlay: at the default each band weighs what the old ramp did; red never under its floor", function()
    local md = {}
    local qs = { 2, 9, 10, 24, 25, 32, 100 }
    for i, q in ipairs(qs) do md[i * 10] = { [i * 10] = q } end
    local ns = boot({ v = 1, cellBase = 0, map = { [ELWYNN] = md } })
    eq(NAGDeathRadarSettings.mapAlpha, 1, "default opacity 1")
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    for i, q in ipairs(qs) do
        local sq = assert(squareAt(i * 10 + 1, i * 10 + 1, 100), "q " .. q)
        local red = isRed(sq._color)
        eq(red, q >= 25, "q " .. q .. " red from the hot threshold")
        near(sq._color[4], mapWeight(q, red), "q " .. q .. " weight", 1e-9)
        if red then assert(sq._color[4] >= 0.4, "red floor") end
    end
    SlashCmdList.NAGDEATHRADAR("threshold 0.05") -- red from q 5: the floor holds q 9's red at 0.4
    near(squareAt(21, 21, 100)._color[4], 0.4, "q 9 red at its floor", 1e-9)
end)

test("overlay: /ndr alpha scales the map squares only, refuses nan, inf and out of range, and persists", function()
    local ns = boot(barrensLike())
    S.worldBounds[ELWYNN] = ELWYNN_BOUNDS
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    SlashCmdList.NAGDEATHRADAR("alpha 0.5")
    eq(NAGDeathRadarSettings.mapAlpha, 0.5)
    near(squareAt(46, 29, 100)._color[4], mapWeight(32, true, 0.5), "hot square at half", 1e-9)
    near(squareAt(32, 17, 100)._color[4], mapWeight(5, false, 0.5), "quiet square at half", 1e-9)
    standAt(ELWYNN, 45, 28, 0)
    ns.Radar.Paint()
    for i = 1, ns.Radar.BlipCount() do
        local e = ns.Radar.Blip(i)
        if e.dx == 0 and e.dy == 0 then
            local _, _, _, a = ns.Color(0.32, NAGDeathRadarSettings)
            eq(e.tex._vertex[4], a, "the radar keeps its own alpha")
        end
    end
    for _, msg in ipairs({ "alpha nan", "alpha inf", "alpha -inf", "alpha 0.05", "alpha 2", "alpha x" }) do
        local _, reply = ns.Command(NAGDeathRadarSettings, msg)
        eq(NAGDeathRadarSettings.mapAlpha, 0.5, msg .. " refused")
        assert(reply[1]:find(" takes ", 1, true), msg .. ": the usage line")
    end
    ns = boot(barrensLike(), { saved = { mapAlpha = 0.7 } })
    eq(NAGDeathRadarSettings.mapAlpha, 0.7, "kept")
    eq(ns.InitSettings({ mapAlpha = 0 }).mapAlpha, 1, "out of range reset")
end)

test("overlay: the map's own toggle, /ndr map and the panel stay in step, and it is saved", function()
    local ns = boot("nagdeath_base0.lua")
    local t = assert(ns.MapToggle(), "a toggle on the world map")
    eq(t._parent, WorldMapFrame, "on the map frame, hidden with it")
    eq(t._template, "UICheckButtonTemplate")
    eq(t._point[1], "TOPRIGHT"); eq(t._point[2], WorldMapFrame:GetCanvasContainer(), "in the map area's top-right corner")
    eq(t:GetChecked(), true, "on")
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    assert(ns.OverlayCount() > 0)
    t:SetChecked(false); t._scripts.OnClick(t)
    eq(NAGDeathRadarSettings.overlay, false, "the toggle drives the map setting"); eq(ns.OverlayCount(), 0, "squares gone")
    local panel = S.panels[1].panel
    eq(panel.boxes.overlay:GetChecked(), false, "the panel follows")
    SlashCmdList.NAGDEATHRADAR("map on")
    eq(t:GetChecked(), true, "/ndr map moves the toggle"); assert(ns.OverlayCount() > 0)
    panel.boxes.overlay:SetChecked(false); panel.boxes.overlay._scripts.OnClick(panel.boxes.overlay)
    eq(t:GetChecked(), false, "the panel moves the toggle")
    S.player.alt = false
    t:SetChecked(true); t._scripts.OnClick(t)
    t._scripts.OnEnter(t)
    eq(GameTooltip._lines[1], "Death heatmap: on", "its tooltip")
    t._scripts.OnLeave(t)
    eq(GameTooltip._shown, false)
    ns = boot("nagdeath_base0.lua", { saved = { overlay = false } })
    eq(ns.MapToggle():GetChecked(), false, "saved")
end)

test("radar: in a hot cell the rim turns red and the line says so; with tint off it does not", function()
    local ns = bootRadar()
    local hx, hy = hottestIn(ns, ELWYNN)
    standAt(ELWYNN, hx, hy)
    eq(ns.Radar.Paint(), "ok")
    eq(ns.Radar.RimHot(), true, "tinted")
    eq(ns.RadarFrame.rim._color[1], 0.9, "red rim")
    eq(ns.RadarFrame.dist:GetText(), "danger: you stand in a hot zone")
    assert(ns.Radar.BlipCount() > 0, "cells drawn")
    SlashCmdList.NAGDEATHRADAR("tint off")
    ns.Radar.Paint()
    eq(ns.Radar.RimHot(), false, "tint off")
    SlashCmdList.NAGDEATHRADAR("tint on")
    standAt(ELWYNN, 5, 5)
    ns.Radar.Paint()
    eq(ns.Radar.RimHot(), false, "a quiet cell")
end)

test("radar: the nearest hot cell far away points from the rim, in its direction", function()
    local ns = bootRadar()
    -- Elwynn's eastern hot spot is around cells (41..42, 65..66); stand 18 cells (about 620 yd) due east of it.
    standAt(ELWYNN, 60, 66, 0)
    eq(ns.Radar.Paint(), "ok")
    local p = ns.Radar.Pointer()
    assert(p.tex:IsShown(), "pointer shown")
    local x, y = p.lastX, p.lastY
    near(math.sqrt(x * x + y * y), ns.Radar.LIMIT, "on the rim", 1e-6)
    assert(x < 0 and math.abs(y) < -x * 0.2, ("west of the player is left when facing north: %f %f"):format(x, y))
    assert(ns.RadarFrame.dist:GetText():match("^danger %d+ yd$"), ns.RadarFrame.dist:GetText())
    -- Turn to face west (facing = pi / 2, turning left from north): the spot is ahead, up.
    S.player.facing = math.pi / 2
    S.frame(0.016)
    x, y = p.lastX, p.lastY
    assert(y > 0 and math.abs(x) < y * 0.2, ("ahead after the turn: %f %f"):format(x, y))
end)

test("radar: SetPoint only on a change", function()
    local ns = bootRadar()
    local hx, hy = hottestIn(ns, ELWYNN)
    standAt(ELWYNN, hx - 1, hy)
    ns.Radar.Paint()
    assert(ns.Radar.BlipCount() > 0)
    local before = S.setPoints
    S.frame(0.016); S.frame(0.016)
    eq(S.setPoints, before, "the same facing: nothing moved")
    ns.Radar.Paint()
    eq(S.setPoints, before, "a paint at the same place and facing: nothing moved")
    S.player.facing = 0.3
    S.frame(0.016)
    assert(S.setPoints > before, "a turn moves the pieces")
    local moved = 0 -- every piece not at the centre itself: a turn leaves the centre where it is
    for i = 1, ns.Radar.BlipCount() do
        local e = ns.Radar.Blip(i)
        if e.dx ~= 0 or e.dy ~= 0 then moved = moved + 1 end
    end
    local p = ns.Radar.Pointer()
    if p.dx and (p.dx ~= 0 or p.dy ~= 0) then moved = moved + 1 end
    assert(moved > 1, "pieces off the centre")
    eq(S.setPoints - before, moved, "each piece that moved, once")
end)

test("radar: the 0.1 s paint runs from OnUpdate; facing is followed between paints", function()
    local ns = bootRadar()
    standAt(ELWYNN, 40, 60)
    eq(S.liveUpdates(), 1, "one OnUpdate")
    local paints = 0
    local real = ns.Radar.Paint
    ns.Radar.Paint = function() paints = paints + 1; return real() end
    for _ = 1, 5 do S.frame(0.03) end -- 0.15 s
    ns.Radar.Paint = real
    eq(paints, 1, "one paint in 0.15 s")
end)

test("radar: no position, no data for this map, and back", function()
    local ns = bootRadar({ secrets = true })
    standAt(ELWYNN, 40, 60)
    S.player.x = S.SECRET
    eq(ns.Radar.Paint(), "no position here")
    eq(ns.Radar.BlipCount(), 0, "nothing drawn"); eq(ns.RadarFrame.note:GetText(), "no position here")
    S.player.map = S.SECRET
    eq(ns.Radar.Paint(), "no position here", "a secret map")
    standAt(NO_DATA_MAP, 40, 60)
    eq(ns.Radar.Paint(), "no data for this map")
    eq(ns.RadarFrame.note:GetText(), "no data for this map")
    standAt(ELWYNN, 40, 60)
    eq(ns.Radar.Paint(), "ok"); eq(ns.RadarFrame.note:IsShown(), false, "the note goes")
    S.worldBounds[DUROTAR] = nil
    standAt(DUROTAR, 50, 50)
    eq(ns.Radar.Paint(), "no position here", "no map size")
end)

test("radar: a secret facing keeps the last plain one", function()
    local ns = bootRadar({ secrets = true })
    standAt(ELWYNN, 60, 66, 1)
    ns.Radar.Paint()
    local x, y = ns.Radar.Pointer().lastX, ns.Radar.Pointer().lastY
    S.player.facing = S.SECRET
    ns.Radar.Paint()
    eq(ns.Radar.Pointer().lastX, x, "x kept"); eq(ns.Radar.Pointer().lastY, y, "y kept")
end)

test("radar: the OnUpdate stops on hide and comes back on show", function()
    local ns = bootRadar()
    eq(S.liveUpdates(), 1)
    SlashCmdList.NAGDEATHRADAR("hide")
    eq(S.liveUpdates(), 0, "stopped"); eq(ns.RadarFrame:IsShown(), false, "hidden")
    eq(NAGDeathRadarSettings.radar, false, "kept in the settings")
    SlashCmdList.NAGDEATHRADAR("show")
    eq(S.liveUpdates(), 1, "back"); eq(ns.RadarFrame:IsShown(), true)
end)

test("radar: the mouse only while Alt is held; a lock stops the drag", function()
    local ns = bootRadar()
    local f = ns.RadarFrame
    eq(f._mouse, false, "no mouse by default: world clicks go through")
    S.player.alt = true; S.fire("MODIFIER_STATE_CHANGED")
    eq(f._mouse, true, "Alt held")
    f._scripts.OnDragStart(f)
    eq(f._moving, true, "drag starts")
    f._cx, f._cy = 700, 450
    S.player.alt = false; S.fire("MODIFIER_STATE_CHANGED")
    eq(f._moving, false, "Alt released ends the drag"); eq(f._mouse, false, "and the mouse")
    eq(NAGDeathRadarSettings.radarPos.x, 200, "saved x"); eq(NAGDeathRadarSettings.radarPos.y, 100, "saved y")
    SlashCmdList.NAGDEATHRADAR("lock")
    S.player.alt = true; S.fire("MODIFIER_STATE_CHANGED")
    eq(f._mouse, true, "locked: Alt still takes the mouse, for the settings click")
    f._moving = false
    f._scripts.OnDragStart(f)
    eq(f._moving, false, "locked: no drag")
end)

local RING_GEOMETRY = { [1] = { 0.314, 0.509 }, [2] = { 0.342, 0.457 }, [8] = { 0.284, 0.490 }, [10] = { 0.354, 0.495 } }

local function artPath(t) return (t._texture or ""):match("[^\\]+$") end

test("radar: ring, grid and art choices persist and apply the art and the ring's geometry", function()
    local ns = bootRadar()
    local f, R = ns.RadarFrame, ns.Radar
    eq(NAGDeathRadarSettings.ring, 1, "default ring"); eq(NAGDeathRadarSettings.grid, 1, "default grid")
    eq(NAGDeathRadarSettings.art, true, "art on by default")
    for ring, g in pairs(RING_GEOMETRY) do
        SlashCmdList.NAGDEATHRADAR("ring " .. ring)
        eq(NAGDeathRadarSettings.ring, ring, "saved")
        eq(artPath(f.art), "frame" .. ring .. ".png", "ring " .. ring .. " art")
        local art = (R.RADIUS + R.BORDER / 2) / g[1]
        near(f.art._w, art, "ring " .. ring .. " art size", 1e-6)
        near(f._w, 2 * art * g[2], "ring " .. ring .. ": the frame is the ring's outer edge", 1e-6)
        eq(f._w, f._h, "square")
    end
    local before = NAGDeathRadarSettings.ring
    local _, reply = ns.Command(NAGDeathRadarSettings, "ring 3")
    eq(NAGDeathRadarSettings.ring, before, "ring 3 refused"); assert(reply[1]:find("1, 2, 8, 10", 1, true), reply[1])
    SlashCmdList.NAGDEATHRADAR("grid 2")
    eq(artPath(f.grid), "radarGrids2.png", "blue grid")
    SlashCmdList.NAGDEATHRADAR("art off")
    eq(f.art:IsShown(), false, "ring art hidden"); eq(f.grid:IsShown(), false, "grid art hidden")
    eq(f.rim:IsShown(), true, "plain rim stays"); eq(f.field:IsShown(), true, "plain field stays")
    eq(f._w, (R.RADIUS + R.BORDER) * 2, "art off: the frame is the plain rim")
    -- Persisted: a new session reads them back.
    ns = bootRadar({ saved = { ring = 8, grid = 2, art = false } })
    eq(artPath(ns.RadarFrame.art), "frame8.png"); eq(artPath(ns.RadarFrame.grid), "radarGrids2.png")
    eq(ns.RadarFrame.art:IsShown(), false, "art off kept")
    eq(ns.InitSettings({ ring = 7, grid = 3, art = "yes" }).ring, 1, "an unknown ring is reset")
    eq(ns.InitSettings({ grid = 3 }).grid, 1, "an unknown grid is reset")
end)

test("radar: right-click opens the settings only with Alt, out of combat; the tooltip with Alt", function()
    local ns = bootRadar()
    local f = ns.RadarFrame
    eq(f._mouse, false, "no Alt: no mouse")
    f._scripts.OnMouseUp(f, "RightButton")
    eq(#S.opened, 0, "no Alt: nothing opens")
    f._scripts.OnEnter(f)
    eq(GameTooltip._shown, false, "no Alt: no tooltip")
    S.player.alt = true; S.fire("MODIFIER_STATE_CHANGED")
    eq(f._mouse, true, "Alt: the mouse")
    f._scripts.OnEnter(f)
    eq(GameTooltip._shown, true, "Alt: the tooltip")
    eq(GameTooltip._lines[2], ns.StatusLine(), "the data line")
    eq(GameTooltip._lines[3], "Right-click: settings")
    f._scripts.OnLeave(f)
    eq(GameTooltip._shown, false, "leave hides it")
    f._scripts.OnMouseUp(f, "LeftButton")
    eq(#S.opened, 0, "a left click opens nothing")
    S.player.combat = true
    f._scripts.OnMouseUp(f, "RightButton")
    eq(#S.opened, 0, "in combat: nothing opens")
    f._scripts.OnEnter(f)
    eq(GameTooltip._shown, false, "in combat: no tooltip")
    S.player.combat = false
    f._scripts.OnMouseUp(f, "RightButton")
    eq(S.opened[1], 77, "Alt + right-click out of combat: the panel")
end)

test("radar: a modifier change hides only our tooltip, never another owner's", function()
    local ns = bootRadar()
    local f = ns.RadarFrame
    local bag = CreateFrame("Frame")
    for _, shown in ipairs({ true, false }) do
        SlashCmdList.NAGDEATHRADAR(shown and "show" or "hide")
        GameTooltip:SetOwner(bag, "ANCHOR_RIGHT"); GameTooltip:Show()
        S.player.alt = false; S.fire("MODIFIER_STATE_CHANGED") -- a Shift or Ctrl press
        eq(GameTooltip._shown, true, "another owner's tooltip survives, radar shown = " .. tostring(shown))
        f._scripts.OnLeave(f)
        eq(GameTooltip._shown, true, "and our OnLeave leaves it alone")
    end
    SlashCmdList.NAGDEATHRADAR("show")
    S.player.alt = true; S.fire("MODIFIER_STATE_CHANGED")
    f._scripts.OnEnter(f)
    eq(GameTooltip:GetOwner(), f, "ours"); eq(GameTooltip._shown, true)
    S.player.alt = false; S.fire("MODIFIER_STATE_CHANGED")
    eq(GameTooltip._shown, false, "ours hides on Alt release")
end)

test("radar: the hot rim is a red ring over the art on every ring, and with the art off", function()
    local ns = bootRadar()
    local f, R = ns.RadarFrame, ns.Radar
    local hx, hy = hottestIn(ns, ELWYNN)
    for _, look in ipairs({ "ring 1", "ring 2", "ring 8", "ring 10", "art off" }) do
        SlashCmdList.NAGDEATHRADAR(look)
        standAt(ELWYNN, hx, hy)
        R.Paint()
        local hot = f.hot
        eq(hot:IsShown(), true, look .. ": the hot ring shows")
        eq(hot._layer, "OVERLAY", look .. ": over the art")
        local c = hot._vertex
        assert(c[1] >= 0.9 and c[2] <= 0.2 and c[3] <= 0.2, look .. ": red")
        assert(hot._w <= f._w + 1e-6, look .. ": inside the frame")
        standAt(ELWYNN, 5, 5)
        R.Paint()
        eq(hot:IsShown(), false, look .. ": cleared when not hot")
    end
    SlashCmdList.NAGDEATHRADAR("art on")
    SlashCmdList.NAGDEATHRADAR("tint off")
    standAt(ELWYNN, hx, hy)
    R.Paint()
    eq(f.hot:IsShown(), false, "tint off: no hot ring")
end)

test("radar: dimmed without a position or data for the map, the note readable; undimmed after", function()
    local ns = bootRadar({ secrets = true })
    local f = ns.RadarFrame
    standAt(ELWYNN, 40, 60)
    ns.Radar.Paint()
    eq(f._alpha, 1, "a position: full")
    S.player.x = S.SECRET
    ns.Radar.Paint()
    eq(f._alpha, 0.3, "no position: dimmed"); eq(f.note._ownAlpha, true, "the note keeps its own alpha")
    standAt(ELWYNN, 40, 60)
    ns.Radar.Paint()
    eq(f._alpha, 1, "back")
    standAt(NO_DATA_MAP, 40, 60)
    ns.Radar.Paint()
    eq(f._alpha, 0.3, "no data for this map: dimmed")
end)

-- ============================ the settings panel ============================

test("panel: the Settings API where present, else the interface options, else none", function()
    local ns = boot(false)
    eq(ns.PanelRegistration(), "settings")
    SlashCmdList.NAGDEATHRADAR("options")
    eq(S.opened[1], 77, "opened by category id")
    ns = boot(false, { settingsApi = false, interfaceOptions = true })
    eq(ns.PanelRegistration(), "interface options")
    ns = boot(false, { settingsApi = false })
    eq(ns.PanelRegistration(), nil, "no panel API: no error")
    SlashCmdList.NAGDEATHRADAR("options")
end)

test("panel: check boxes follow the settings", function()
    local ns = boot("nagdeath_base0.lua")
    local cat = S.panels[1]
    local p = cat.panel
    eq(p.boxes.radar:GetChecked(), true)
    p.boxes.radar:SetChecked(false)
    p.boxes.radar._scripts.OnClick(p.boxes.radar)
    eq(NAGDeathRadarSettings.radar, false); eq(S.liveUpdates(), 0, "unticked: the radar stops")
    eq(p.status:GetText(), ns.StatusLine())
    eq(p.cycles.ring:GetText(), "Ring: 1"); eq(p.cycles.grid:GetText(), "Grid: green")
    for _, want in ipairs({ 2, 8, 10, 1 }) do
        p.cycles.ring._scripts.OnClick(p.cycles.ring)
        eq(NAGDeathRadarSettings.ring, want, "the ring button steps")
    end
    p.cycles.grid._scripts.OnClick(p.cycles.grid)
    eq(NAGDeathRadarSettings.grid, 2); eq(p.cycles.grid:GetText(), "Grid: blue")
    eq(artPath(ns.RadarFrame.grid), "radarGrids2.png", "applied at once")
    eq(p.boxes.art:GetChecked(), true, "the art box")
    -- The map opacity slider (UISliderTemplateWithLabels on every target client).
    local sl = assert(p.mapAlpha, "a slider")
    eq(S.lastTemplate, "UISliderTemplateWithLabels"); eq(sl._min, 0.1); eq(sl._max, 1); eq(sl:GetValue(), 1)
    sl._scripts.OnValueChanged(sl, 0.6, true)
    eq(NAGDeathRadarSettings.mapAlpha, 0.6, "the slider sets the opacity")
    SlashCmdList.NAGDEATHRADAR("alpha 0.33")
    eq(sl:GetValue(), 0.33, "/ndr alpha moves the slider")
    eq(NAGDeathRadarSettings.mapAlpha, 0.33, "and the slider does not snap it to its 0.05 steps")
end)

test("panel: without the slider template, a step button sets the map opacity", function()
    boot("nagdeath_base0.lua", { sliderTemplate = false })
    local p = S.panels[1].panel
    local b = assert(p.mapAlphaStep, "the step button")
    eq(p.mapAlpha, nil, "no slider")
    eq(b:GetText(), "Map opacity: 100%")
    b._scripts.OnClick(b)
    eq(NAGDeathRadarSettings.mapAlpha, 0.4, "1 -> 0.4, wrapping round")
    eq(b:GetText(), "Map opacity: 40%")
    b._scripts.OnClick(b)
    eq(NAGDeathRadarSettings.mapAlpha, 0.6)
end)

out(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
