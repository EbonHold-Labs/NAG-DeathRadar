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

test("the shipped data file is data only: it defines NAGDeathData alone, a v = 1 table with its flavor", function()
    local env = {}
    local chunk = assert(loadfile(ADDON .. DATA_FILE))
    setfenv(chunk, env)
    chunk()
    local d = env.NAGDeathData
    env.NAGDeathData = nil
    eq(next(env), nil, "no other global")
    eq(type(d), "table", "NAGDeathData")
    eq(d.v, 1, "v"); eq(type(d.flavor), "string", "flavor"); eq(type(d.map), "table", "map")
    -- The game runs this file, and an empty environment skips code behind an `if`: outside its strings the text is
    -- only braces, brackets, "=", ",", numbers and the export's field names (tools/snapshot_data.py's check, as the
    -- app's), so no call or statement can hide in it.
    local fh = assert(io.open(ADDON .. DATA_FILE, "rb")); local text = fh:read("*a"); fh:close()
    local bare = text:gsub('"[^"\\\r\n]*"', '""')
    local FIELDS = { NAGDeathData = true, v = true, generated = true, flavor = true, cellBase = true, published = true,
        ["next"] = true, rows = true, contributors = true, map = true, killers = true, bands = true, instances = true,
        fine = true, grid = true, levels = true }
    for name in bare:gmatch("[%a_][%w_]*") do
        assert(FIELDS[name], "a name that is not an export field: " .. name)
    end
    local other = bare:gsub('""', ""):gsub("[%w_%s%[%]{}=,%-%.]", "")
    eq(other, "", "characters other than data")
    assert(not bare:find("%.%.", 1), "no concatenation")
end)

local NO_DATA_STATES = {
    { "an older install's placeholder (it defines nothing)", "nagdeath_placeholder.lua" },
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

-- Clients by GetBuildInfo (version, build, date, interface), as each reports itself.
local FOREVER = { "1.60.1", "70450", "Oct 1 2026", 16001 }
local TBC = { "2.5.5", "65000", "Oct 1 2026", 20505 }

test("flavor: each client is named as NAG names it, without NAG", function()
    local cases = {
        { { "1.15.7", "61000", "", 11507 }, false, "vanilla" },
        { { "1.15.7", "61000", "", 11507 }, true, "sod" },
        { FOREVER, true, "camelot" },
        { { "1.60.1", "70450", "", 0 }, false, "camelot" },
        { TBC, false, "tbc" },
        { { "3.4.4", "60000", "", 30404 }, false, "wrath" },
        { { "3.80.0", "60000", "", 38000 }, false, "titan" },
        { { "4.4.2", "60000", "", 40402 }, false, "cata" },
        { { "5.5.0", "60000", "", 50500 }, false, "mists" },
        { { "11.2.5", "60000", "", 110205 }, false, "mainline" },
    }
    for _, c in ipairs(cases) do
        local ns = boot(false, { build = c[1], engraving = c[2] })
        eq(ns.ClientFlavor(), c[3], ("%s %s%s"):format(c[1][1], tostring(c[1][4]), c[2] and " +engraving" or ""))
    end
    local ns = boot(false)
    eq(ns.ClientFlavor(), nil, "no GetBuildInfo: the client cannot be told")
end)

test("flavor: data from another game is refused everywhere, 'no data for this game'", function()
    local ns = boot("nagdeath_base0.lua", { build = TBC })
    eq(ns.data, nil, "camelot data on a TBC client is not loaded")
    eq(ns.dataReason, "flavor")
    eq(ns.StatusLine(), "no data for this game")
    -- R.Refresh's own note (the one shown at load and after any settings change), before Paint can overwrite it.
    local f = ns.RadarFrame
    eq(f.note:GetText(), "no data for this game", "the radar's note at load")
    f.note:SetText(nil)
    ns.Radar.Refresh(NAGDeathRadarSettings)
    eq(f.note:GetText(), "no data for this game", "the radar's note after a Refresh")
    S.mapID = ELWYNN
    WorldMapFrame:OnMapChanged()
    eq(ns.OverlayCount(), 0, "the map draws nothing")
    eq(ns.OverlayNote(), "NAG Death Radar: no data for this game")
    S.worldBounds[ELWYNN] = ELWYNN_BOUNDS
    S.player.map, S.player.x, S.player.y = ELWYNN, 0.42, 0.66
    eq(ns.Radar.Paint(), "no data for this game", "the radar draws nothing and says so")
end)

test("flavor: data from this game draws", function()
    local ns = boot("nagdeath_base0.lua", { build = FOREVER })
    assert(ns.data, "camelot data on Forever: " .. tostring(ns.dataReason))
    S.mapID = ELWYNN
    WorldMapFrame:OnMapChanged()
    assert(ns.OverlayCount() > 0, "the map draws")
    assert(ns.StatusLine():find("death data from", 1, true), "the status line has the data")
end)

test("the shipped snapshot draws on its own game and says 'no data for this game' on the others", function()
    local ns = boot(nil, { build = FOREVER })
    assert(ns.data, "the shipped file on Forever: " .. tostring(ns.dataReason))
    assert(ns.StatusLine():find("death data from", 1, true), "the status line has the data")
    ns = boot(nil, { build = TBC })
    eq(ns.data, nil, "the shipped camelot file on a TBC client")
    eq(ns.StatusLine(), "no data for this game")
end)

test("flavor: a file without a flavor field draws on Forever only", function()
    local raw = readFixture("nagdeath_base0.lua")
    raw.flavor = nil
    local ns = boot(raw, { build = FOREVER })
    assert(ns.data, "no flavor field on Forever: drawn (only Forever has ever collected)")
    raw = readFixture("nagdeath_base0.lua")
    raw.flavor = nil
    ns = boot(raw, { build = TBC })
    eq(ns.data, nil, "no flavor field elsewhere: refused")
    eq(ns.StatusLine(), "no data for this game")
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

--- A lone cell's inner fine value: bilinear 0.75 x 0.75 of q, or q itself where q is hot (25 at the default) and
--- the smoothed value is not.
local function loneInner(q)
    local v = 0.5625 * q
    return (q >= 25 and v < 25) and q or v
end


--- The map's red family (ns.MapColor from hot): orange-red to deep red, no blue. The ramp under hot never is.
local function redFamily(r, g, b) return r ~= nil and r >= 0.8 and g <= 0.2 and b == 0 end
local function isMapRed(c) return c ~= nil and redFamily(c[1], c[2], c[3]) end

test("rebucket from any grid, same-colour runs per row and the texture cap", function()
    local ns = boot(false)
    local md = { [0] = { [0] = 10 }, [3] = { [3] = 50 }, [4] = { [4] = 30 }, [99] = { [99] = 7 } }
    local b25, n25 = ns.Rebucket(md, 25)
    eq(b25[1][1], 50, "0..3 merge, max kept"); eq(b25[2][2], 30, "4 -> bucket 2"); eq(b25[25][25], 7, "edge")
    eq(n25, 3, "count")
    local f = { [0] = { [0] = 10 }, [1] = { [1] = 40 }, [199] = { [199] = 7 } }
    local b100, n100 = ns.Rebucket(f, 100, 200)
    eq(b100[1][1], 40, "a 200 grid's 2 x 2 fold into one 100 bucket, max kept"); eq(b100[100][100], 7); eq(n100, 2)
    eq(ns.BucketsForZoom, nil, "no zoom ladder: every zoom draws the full grid")
    local s = ns.InitSettings(nil)
    local function sorted(runs)
        table.sort(runs, function(a, b) return a.y < b.y or (a.y == b.y and a.x0 < b.x0) end)
        return runs
    end
    local runs = sorted(ns.Runs({ [1] = { [1] = 50 }, [2] = { [1] = 50 }, [3] = { [1] = 50 }, [5] = { [1] = 50 },
        [6] = { [1] = 10 }, [7] = { [2] = 50 } }, 200, s))
    eq(#runs, 4, "1..3 one run; 5 after a gap; 6 another colour; row 2 its own")
    eq(runs[1].x0, 1); eq(runs[1].x1, 3); eq(runs[2].x0, 5); eq(runs[2].x1, 5); eq(runs[3].x0, 6); eq(runs[4].y, 2)
    assert(redFamily(runs[1].r, runs[1].g, runs[1].b), "q 50 red"); eq(runs[1].a, select(4, ns.MapColor(0.5, s)), "the ramp's alpha")
    eq(#ns.Runs({ [1] = { [1] = 50 }, [2] = { [1] = 51 } }, 200, s), 1, "q 50 and 51: one red step, one run")
    eq(#ns.Runs({ [1] = { [1] = 50 }, [2] = { [1] = 60 } }, 200, s), 2, "q 50 and 60: two red steps, two runs")
    eq(#ns.Runs({ [1] = { [1] = 1 } }, 200, s), 0, "below the low band: no run")
    -- A checkerboard of red and yellow never merges at 200; folded to 100 every bucket keeps its red.
    local dense = {}
    for x = 0, 199 do dense[x] = {}; for y = 0, 199 do dense[x][y] = (x + y) % 2 == 0 and 50 or 10 end end
    local capped, n = ns.CappedRuns(dense, 200, 200, 2500, s)
    eq(n, 100, "40000 runs over the cap: 100 per side"); eq(#capped, 100, "one red run per row")
    local _, nMin = ns.CappedRuns(dense, 200, 200, 10, s)
    eq(nMin, 25, "never coarser than 25")
end)

test("upsample: bilinear 100 -> 200, edges clamped, a fine cell never under its parent's band", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    local up = ns.Upsample({ [10] = { [10] = 100 } }, s)
    local n = 0
    for _, col in pairs(up) do for _ in pairs(col) do n = n + 1 end end
    eq(n, 16, "a lone cell spreads over 4 x 4 fine cells")
    near(up[20][20], 56.25, "inner"); near(up[21][21], 56.25, "inner")
    near(up[19][20], 18.75, "edge"); near(up[22][21], 18.75, "edge")
    near(up[19][19], 6.25, "corner"); near(up[22][22], 6.25, "corner")
    eq(up[18], nil, "nothing past the bilinear support")
    up = ns.Upsample({ [10] = { [10] = 30 } }, s) -- bilinear 16.875 would be yellow; the radar calls 30 hot
    near(up[20][20], 30, "raised to its own cell's q: red where the radar points")
    near(up[19][20], 5.625, "a cell of an empty parent is not raised")
    up = ns.Upsample({ [10] = { [10] = 12 } }, s)
    near(up[20][20], 6.75, "a parent that is not hot: smoothed, not lifted (the ramp has no band to keep)")
    up = ns.Upsample({ [10] = { [10] = 1 } }, s)
    near(up[20][20], 0.5625, "below the low band: not raised")
    up = ns.Upsample({ [0] = { [0] = 40 } }, s)
    near(up[0][0], 40, "the corner fine cell reads its own cell only")
    near(up[1][1], 40, "0.5625 x 40 = 22.5 is yellow: its own cell's q")
    up = ns.Upsample({ [99] = { [99] = 40 } }, s)
    near(up[199][199], 40, "the far corner"); eq(up[200], nil, "nothing past the grid")
    s.hot = 0.4
    up = ns.Upsample({ [10] = { [10] = 30 } }, s)
    near(up[20][20], 16.875, "hot from 0.4: 30 is yellow, and so is 16.875: not raised")
end)

test("upsample: at every threshold the addon takes, a lone hot cell's own fine cells draw red", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    local bad = {}
    for h = 50, 1000 do -- every three-decimal /ndr threshold, 0.050 .. 1.000
        s.hot = h / 1000
        local q = math.ceil(s.hot * 100 - 1e-9) -- the coolest whole q the radar calls hot
        if q / 100 < s.hot then q = q + 1 end
        if q <= 100 then
            local up = ns.Upsample({ [10] = { [10] = q } }, s)
            for jx = 20, 21 do
                for jy = 20, 21 do
                    local r, g, b = ns.MapColor(up[jx][jy] / 100, s)
                    if not redFamily(r, g, b) then bad[#bad + 1] = ("%s q %d"):format(s.hot, q) end
                end
            end
        end
    end
    eq(#bad, 0, "thresholds whose hot cell draws another colour: " .. table.concat(bad, ", ", 1, math.min(#bad, 8)))
    s = ns.InitSettings(nil)
    s.thrLow = 0.167 -- the low band is not lifted: a lone q-17 cell smooths to 9.6 and fades out of the haze
    local up = ns.Upsample({ [10] = { [10] = 17 } }, s)
    near(up[20][20], 0.5625 * 17, "smoothed, not lifted"); eq(ns.MapColor(up[20][20] / 100, s), nil, "under the low band: not drawn")
end)


--- One run in the server's packed grammar (Tools PR #1142 _pack): Y(2) X(2) N(1) and N levels, base64 digits.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function digit(v) return B64:sub(v + 1, v + 1) end
local function run(y, x, levels)
    local s = digit(math.floor(y / 64)) .. digit(y % 64) .. digit(math.floor(x / 64)) .. digit(x % 64) .. digit(#levels)
    for _, l in ipairs(levels) do s = s .. digit(l) end
    return s
end

test("fine: the server's packed field decodes to the cells its encoder was given; a bad one is ignored", function()
    local ns = boot(false)
    local raw = readFixture("nagdeath_fine.lua")
    local d = assert(ns.LoadData(raw))
    assert(d.fine, "fine read: " .. tostring(d.fineReason))
    eq(d.fine.grid, 200); eq(d.fine.maps, 2)
    for m, cells in pairs(raw.fineExpect) do
        local got = 0
        for _, col in pairs(d.fine.map[m]) do for _ in pairs(col) do got = got + 1 end end
        eq(got, #cells, "map " .. m .. ": every cell, no other")
        for _, c in ipairs(cells) do
            near(d.fine.map[m][c[1]][c[2]], 100 * c[3] / 63, ("map %d cell %d,%d"):format(m, c[1], c[2]))
        end
    end
    local plain = assert(ns.LoadData(readFixture("nagdeath_base0.lua")))
    eq(d.cells, plain.cells, "the 100 grid is read as without fine")
    local function fineOf(f)
        local r = readFixture("nagdeath_base0.lua")
        r.fine = f
        local dd, why = ns.LoadData(r)
        assert(dd, "fine never makes the data unusable: " .. tostring(why))
        return dd.fine, dd.fineReason
    end
    local one = { run(0, 0, { 1 }) }
    eq(select(2, fineOf(nil)), "absent")
    eq(select(2, fineOf("x")), "format")
    for _, g in ipairs({ 100, 199, 250, 401, 200.5, "200" }) do eq(select(2, fineOf({ grid = g, [1] = one })), "grid", tostring(g)) end
    near(fineOf({ grid = 300, [1] = { run(299, 299, { 63 }) } }).map[1][299][299], 100, "a 300 grid reads; the map folds it to 200")
    eq(select(2, fineOf({ grid = 200, cellBase = 2, [1] = one })), "cellBase")
    for _, l in ipairs({ 1, 65, 2.5 }) do eq(select(2, fineOf({ grid = 200, levels = l, [1] = one })), "levels", tostring(l)) end
    eq(select(2, fineOf({ grid = 200, [1] = { "!" } })), "empty", "no valid map")
    local f = fineOf({ grid = 200, [1] = { run(5, 7, { 63, 0, 0, 31 }) .. run(6, 0, { 2 }), run(199, 190, { 1 }) } })
    near(f.map[1][7][5], 100, "x 7 row 5, level 63 of 64 is 100"); eq(f.map[1][8], nil, "a level 0 bridges: no cell")
    near(f.map[1][10][5], 100 * 31 / 63, "x 7 + 3"); near(f.map[1][0][6], 100 * 2 / 63, "a second run in one string")
    near(f.map[1][190][199], 100 / 63, "a second string, the last row")
    local cases = {
        { { run(0, 0, { 1 }) .. "!" }, "a bad character" },
        { { run(0, 0, { 1 }):sub(1, 4) }, "a header cut short" },
        { { run(0, 0, { 1 }):sub(1, 5) }, "a run with fewer levels than N" },
        { { run(0, 0, {}) }, "N 0" },
        { { run(0, 198, { 1, 1, 1 }) }, "a run past the last column" },
        { { run(200, 0, { 1 }) }, "a row past the grid" },
        { { run(0, 0, { 0 }) }, "only empty cells" },
        { { run(0, 0, { 1 }), 7 }, "a string list holding a number" },
        { {}, "an empty list" },
        { run(0, 0, { 1 }), "a bare string, not a list" },
    }
    for i, c in ipairs(cases) do
        f = fineOf({ grid = 200, [1] = c[1], [2] = one })
        eq(f.map[1], nil, c[2] .. ": its map is dropped"); assert(f.map[2], c[2] .. ": the other map stays")
    end
    f = fineOf({ grid = 200, levels = 4, [1] = { run(1, 1, { 3 }) }, [2] = { run(1, 1, { 4 }) } })
    near(f.map[1][1][1], 100, "level 3 of 4 is 100"); eq(f.map[2], nil, "a level past levels - 1")
    f = fineOf({ grid = 200, cellBase = 1, [1] = { run(1, 200, { 63 }) }, [2] = { run(0, 1, { 63 }) } })
    assert(f.map[1][199][0], "1-based: x 200, y 1 is the last column's first row"); eq(f.map[2], nil, "1-based: y 0 is off")
    f = fineOf({ grid = 200, [1] = one, ["x"] = one, [0] = one, [-3] = one, [2.5] = one })
    eq(f.maps, 1, "only positive integer map keys")
    local r = readFixture("nagdeath_fine.lua"); r.map = nil
    eq(select(2, ns.LoadData(r)), "map", "fine alone is not data: the 100 grid stays required")
end)

test("colours: thresholds to light blue, yellow, red", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    eq(ns.Color(0.01, s), nil, "below low")
    local r, g, b = ns.Color(0.05, s); eq(r, 0); eq(g, 0.8); eq(b, 1)
    r, g, b = ns.Color(0.1, s); eq(r, 1); eq(g, 1); eq(b, 0)
    r, g, b = ns.Color(0.25, s); eq(r, 1); eq(g, 0); eq(b, 0)
end)

test("map colours: a ramp from a faint blue haze to orange-red under hot, red from hot, nothing under the low band", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    eq(ns.MapColor(0.019, s), nil, "under the low band: nothing")
    local shades, lastA, lastStep = {}, 0, -1
    for k = 20, 249 do
        local i = k / 1000
        local r, g, b, a, step = ns.MapColor(i, s)
        assert(r, "drawn at " .. i)
        assert(not redFamily(r, g, b), "not red under hot: " .. i)
        assert(a >= lastA, ("alpha never falls: %s at %s after %s"):format(a, i, lastA)); lastA = a
        assert(step >= lastStep, "steps rise with i"); lastStep = step
        shades[step] = shades[step] or { r, g, b, a }
        local c = shades[step]
        eq(c[1] .. c[2] .. c[3] .. c[4], r .. g .. b .. a, "one step, one colour")
    end
    local n = 0
    for _ in pairs(shades) do n = n + 1 end
    eq(n, ns.MAP_RAMP_STEPS, "every shade of the ramp under hot")
    assert(ns.MAP_RAMP_STEPS >= 16, "enough shades to read smooth")
    local r, g, b, a = ns.MapColor(0.02, s)
    assert(b > r and a >= 0.15 and a <= 0.22, ("the faintest cell: light blue, faint but seen: %s %s %s %s"):format(r, g, b, a))
    r, g, b, a = ns.MapColor(0.10, s)
    assert(r > 0.9 and g > 0.7 and g < 0.9 and b < 0.2, ("gold where the radar turns yellow: %s %s %s"):format(r, g, b))
    assert(a >= 0.3 and a <= 0.37, "gold at about a third: it reads on yellow-brown ground, alpha " .. a)
    r, g, b = ns.MapColor(0.249, s)
    assert(r == 1 and g > 0.35 and g < 0.55, ("orange just under hot: %s %s %s"):format(r, g, b))
    local redA, redR, redG = 0, 1, 1
    for k = 250, 1000, 5 do
        local rr, gg, bb, aa = ns.MapColor(k / 1000, s)
        assert(redFamily(rr, gg, bb), "red from hot: " .. k / 1000)
        assert(aa >= 0.5 and aa >= redA, "red at least at its floor, never fading as i grows"); redA = aa
        assert(rr <= redR and gg <= redG, "red deepens as i grows"); redR, redG = rr, gg
    end
    r, g = ns.MapColor(0.25, s)
    assert(g >= 0.15, "orange-red at hot")
    r, g, b, a = ns.MapColor(1, s)
    assert(r <= 0.85 and g <= 0.02 and a >= 0.7, ("deep red at q 100: %s %s %s %s"):format(r, g, b, a))
    s.mapAlpha = 0.5
    local _, _, _, half = ns.MapColor(0.5, s)
    s.mapAlpha = 1
    local _, _, _, full = ns.MapColor(0.5, s)
    near(half, full * 0.5, "the opacity setting scales it")
    for _, order in ipairs({ { 0.3, 0.2, 0.25 }, { 0.02, 0.5, 0.25 }, { 0.3, 0.3, 0.25 } }) do
        s.thrLow, s.thrMid, s.hot = order[1], order[2], order[3]
        for k = 0, 1000, 7 do
            local rr, gg, bb = ns.MapColor(k / 1000, s)
            local wantRed = k / 1000 >= s.hot
            if rr then eq(redFamily(rr, gg, bb), wantRed, ("order %s/%s/%s at %s"):format(order[1], order[2], order[3], k / 1000))
            else assert(not wantRed, "a hot cell is drawn") end
        end
    end
end)

test("map colours: a cell exactly at hot draws the red family (red team LOW-1, relay 3839)", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    for _, h in ipairs({ 0.05, 0.1, 0.167, 0.25, 0.3, 0.333, 0.7, 1 }) do
        s.hot = h
        local r, g, b, a, step = ns.MapColor(h, s)
        assert(redFamily(r, g, b), ("i == hot %s: red family, got %s %s %s"):format(h, tostring(r), tostring(g), tostring(b)))
        assert(step >= 1000 and a >= 0.5, "i == hot " .. h .. ": red's first step")
    end
end)

test("map colours: a red cell beside a ramp cell of the same step index stays its own run (red team LOW-2)", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    local _, _, _, _, rampStep = ns.MapColor(0.02, s)
    local _, _, _, _, redStep = ns.MapColor(0.25, s)
    eq(rampStep, 0, "the ramp's first step"); eq(redStep % 1000, 0, "red's first step has the same index")
    local runs = ns.Runs({ [1] = { [1] = 2 }, [2] = { [1] = 25 } }, 200, s)
    eq(#runs, 2, "two runs, not one")
    table.sort(runs, function(x, y) return x.x0 < y.x0 end)
    local want1 = { ns.MapColor(0.02, s) }
    local want2 = { ns.MapColor(0.25, s) }
    eq(runs[1].r .. runs[1].g .. runs[1].b .. runs[1].a, want1[1] .. want1[2] .. want1[3] .. want1[4], "the ramp cell's own colour")
    eq(runs[2].r .. runs[2].g .. runs[2].b .. runs[2].a, want2[1] .. want2[2] .. want2[3] .. want2[4], "the red cell's own colour")
    assert(redFamily(runs[2].r, runs[2].g, runs[2].b), "and it is red")
end)

test("map colours: thrMid outside thrLow..hot, the ramp runs straight from blue to orange over thrLow..hot", function()
    local ns = boot(false)
    local s = ns.InitSettings(nil)
    for _, mid in ipairs({ 0.01, 0.05, 0.25, 0.6 }) do -- under thrLow, at it, at hot, above hot
        s.thrLow, s.thrMid, s.hot = 0.05, mid, 0.25
        for _, i in ipairs({ 0.05, 0.08, 0.1, 0.15, 0.2, 0.249 }) do
            local _, _, _, _, step = ns.MapColor(i, s)
            eq(step, math.min(23, math.floor((i - 0.05) / 0.2 * 24)), ("thrMid %s, i %s: the straight step"):format(mid, i))
        end
        local r, g, b = ns.MapColor(0.05, s)
        assert(b > r, "blue at thrLow")
        r, g, b = ns.MapColor(0.249, s)
        assert(r == 1 and g > 0.35 and g < 0.55, "orange just under hot")
    end
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

--- The shown overlay texture over canvas point (px, py) (y down from the top), from its TOPLEFT and BOTTOMRIGHT.
local function textureAt(px, py)
    for _, o in ipairs(S.objects) do
        local tl, br = o._points and o._points.TOPLEFT, o._points and o._points.BOTTOMRIGHT
        if o._color and o._shown and tl and br and tl[4] <= px and px < br[4] and -tl[5] <= py and py < -br[5] then
            return o
        end
    end
end

--- The texture over 0-based cell (jx, jy) of n per side (200 by default) on the stub's 1000 x 700 canvas.
local function cellTex(jx, jy, n)
    n = n or 200
    return textureAt((jx + 0.5) * 1000 / n, (jy + 0.5) * 700 / n)
end

local function shownTextures()
    local list = {}
    for _, o in ipairs(S.objects) do
        if o._color and o._shown and o._points and o._points.TOPLEFT then list[#list + 1] = o end
    end
    return list
end

test("overlay: draws 200 per side on map change, the same at every zoom, no data for this map, off", function()
    local ns = boot("nagdeath_base0.lua")
    eq(ns.OverlayLevel(), 2004, "just above the explored-area level, below every pin")
    eq(_G.NAGDeathRadarMapLayer and _G.NAGDeathRadarMapLayer:GetFrameLevel(), 2004, "the layer is named, for probes")
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    local drawn = ns.OverlayCount()
    assert(drawn > 0, "drawn")
    eq(#shownTextures(), drawn, "every texture anchored at two corners")
    local s = NAGDeathRadarSettings
    for ix, col in pairs(ns.data.map[ELWYNN]) do
        for iy, q in pairs(col) do
            if ns.MapColor(q / 100, s) then
                for jx = 2 * ix, 2 * ix + 1 do
                    for jy = 2 * iy, 2 * iy + 1 do assert(cellTex(jx, jy), ("cell %d,%d's fine %d,%d"):format(ix, iy, jx, jy)) end
                end
            end
        end
    end
    for _, o in ipairs(shownTextures()) do
        local tl, br = o._points.TOPLEFT, o._points.BOTTOMRIGHT
        near(-br[5] - -tl[5], 3.5, "one fine row high", 1e-9)
        local w = br[4] - tl[4]
        near(w / 5, math.floor(w / 5 + 0.5), "a whole number of fine cells wide", 1e-9)
    end
    eq(ns.OverlayNote(), nil, "no note over data")
    for _, z in ipairs({ 0, 0.5 }) do
        S.zoom = z
        WorldMapFrame:OnCanvasScaleChanged()
        eq(ns.OverlayCount(), drawn, "zoom " .. z .. ": the same picture")
    end
    S.mapID = NO_DATA_MAP
    WorldMapFrame:OnMapChanged()
    eq(ns.OverlayCount(), 0, "nothing drawn"); eq(ns.OverlayNote(), "NAG Death Radar: no data for this map")
    S.mapID = ELWYNN
    SlashCmdList.NAGDEATHRADAR("map off")
    eq(ns.OverlayCount(), 0, "overlay off"); eq(ns.OverlayNote(), nil, "and quiet")
    SlashCmdList.NAGDEATHRADAR("map on")
    eq(ns.OverlayCount(), drawn, "back")
end)

test("overlay: a map that cannot zoom and a zoomable one, zoomed out, draw the same full picture", function()
    local ns = boot("nagdeath_base0.lua")
    S.mapID, S.zoom, S.minScale, S.maxScale = ELWYNN, 0.5, 1, 1 -- one zoom scale: the client answers 0 %
    WorldMapFrame:OnMapChanged()
    local full = ns.OverlayCount()
    assert(full > 0)
    S.minScale, S.maxScale, S.zoom = 0.5, 2, 0
    WorldMapFrame:OnMapChanged()
    S.mapID = DUROTAR; WorldMapFrame:OnMapChanged(); S.mapID = ELWYNN; WorldMapFrame:OnMapChanged()
    eq(ns.OverlayCount(), full, "zoomable and zoomed out: every fine cell")
end)

test("overlay: seams: touching runs share their edge exactly, snapping off, on an odd canvas size", function()
    local ns = boot("nagdeath_base0.lua")
    S.canvas._w, S.canvas._h = 1002.7, 668.1
    S.mapID = ELWYNN
    _G.NAGDeathRadarMapLayer._scripts.OnSizeChanged(_G.NAGDeathRadarMapLayer)
    local list = shownTextures()
    assert(#list > 0)
    local touchX, touchY = 0, 0
    for _, a in ipairs(list) do
        eq(a._snap, false, "SetSnapToPixelGrid(false)"); eq(a._texelBias, 0, "SetTexelSnappingBias(0)")
        local abr = a._points.BOTTOMRIGHT
        for _, b in ipairs(list) do
            local btl = b._points.TOPLEFT
            if a ~= b and math.abs(abr[4] - btl[4]) < 1e-6 and btl[5] == a._points.TOPLEFT[5] then
                touchX = touchX + 1
                eq(abr[4], btl[4], "a row's touching runs: one edge, bit for bit")
            end
            if a ~= b and math.abs(abr[5] - btl[5]) < 1e-6 then
                touchY = touchY + 1
                eq(abr[5], btl[5], "touching rows: one edge, bit for bit")
            end
        end
    end
    assert(touchX > 0 and touchY > 0, ("touching pairs found: %d across, %d down"):format(touchX, touchY))
    for _, o in ipairs(list) do
        local tl, br = o._points.TOPLEFT, o._points.BOTTOMRIGHT
        local x0, x1 = tl[4] / (1002.7 / 200), br[4] / (1002.7 / 200)
        near(x0, math.floor(x0 + 0.5), "left edge on the grid", 1e-6); near(x1, math.floor(x1 + 0.5), "right edge on the grid", 1e-6)
    end
end)

test("overlay: the corner cell of a 0-based file is drawn in the top-right corner", function()
    local ns = boot("nagdeath_base0.lua")
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    local t = assert(cellTex(199, 0), "the top-right fine cell is drawn")
    eq(t._points.BOTTOMRIGHT[4], 1000, "at the right edge"); eq(t._points.TOPLEFT[5], 0, "at the top edge")
end)

test("overlay: with `fine`, the map draws the file's own 200 cells, not the upsampled 100 grid", function()
    local raw = readFixture("nagdeath_fine.lua")
    local ns = boot("nagdeath_fine.lua")
    local s = NAGDeathRadarSettings
    for _, m in ipairs({ ELWYNN, DUROTAR }) do
        S.mapID = m
        WorldMapFrame:OnMapChanged()
        local inFine = {}
        for _, c in ipairs(raw.fineExpect[m]) do
            inFine[c[1] * 1000 + c[2]] = true
            local r, g, b, a = ns.MapColor(c[3] / 63, s)
            local tex = cellTex(c[1], c[2])
            if r then
                assert(tex, ("map %d fine %d,%d drawn"):format(m, c[1], c[2]))
                eq(tex._color[1], r); eq(tex._color[2], g); eq(tex._color[3], b)
                eq(tex._color[4], a, "alpha")
            else
                eq(tex, nil, ("map %d fine %d,%d under the low band"):format(m, c[1], c[2]))
            end
        end
        -- A cell the encoder left empty that the upsampled 100 grid would colour: not drawn.
        local up, shown = ns.Upsample(ns.data.map[m], s), 0
        for jx, col in pairs(up) do
            for jy, q in pairs(col) do
                if not inFine[jx * 1000 + jy] and ns.MapColor(q / 100, s) then
                    shown = shown + 1
                    eq(cellTex(jx, jy), nil, ("map %d fine %d,%d: from fine, not the upsample"):format(m, jx, jy))
                end
            end
        end
        assert(shown > 0, "map " .. m .. ": the upsample would colour a cell fine leaves empty")
    end
    raw.fine[ELWYNN] = "50,74,!"
    ns = boot(raw)
    S.mapID = ELWYNN
    WorldMapFrame:OnMapChanged()
    local up = ns.Upsample(ns.data.map[ELWYNN], NAGDeathRadarSettings)
    for jx, col in pairs(up) do
        for jy, q in pairs(col) do
            if ns.MapColor(q / 100, NAGDeathRadarSettings) then assert(cellTex(jx, jy), "a bad fine map falls back to the upsample") end
        end
    end
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
    WorldMapFrame:OnMapChanged()
    for _, z in ipairs({ 0, 0.5, 1 }) do
        S.zoom = z
        WorldMapFrame:OnCanvasScaleChanged()
        for jx = 90, 91 do
            for jy = 56, 57 do
                local sq = assert(cellTex(jx, jy), ("zoom %s: hot fine cell %d,%d drawn"):format(z, jx, jy))
                assert(isMapRed(sq._color), ("zoom %s: fine %d,%d red, got %s %s %s"):format(z, jx, jy, sq._color[1], sq._color[2], sq._color[3]))
                assert(sq._color[4] >= 0.5, "at least red's floor, alpha " .. sq._color[4])
            end
        end
        local quiet = cellTex(62, 32)
        assert(quiet and not isMapRed(quiet._color), "zoom " .. z .. ": a q-5 cell is not red")
    end
end)

test("fine: the radar reads the fine cells folded to its grid, so its hot cells are red on the map", function()
    local raw = readFixture("nagdeath_fine.lua")
    local ns = boot("nagdeath_fine.lua")
    local s = NAGDeathRadarSettings
    for _, m in ipairs({ ELWYNN, DUROTAR }) do
        local md = ns.MapData(m)
        local fine = ns.data.fine.map[m]
        local n, hot = 0, 0
        for ix, col in pairs(md) do
            for iy, q in pairs(col) do
                n = n + 1
                local best = 0
                for jx = 2 * ix, 2 * ix + 1 do
                    for jy = 2 * iy, 2 * iy + 1 do best = math.max(best, fine[jx] and fine[jx][jy] or 0) end
                end
                eq(q, best, ("map %d cell %d,%d: its hottest fine cell"):format(m, ix, iy))
                if q / 100 >= s.hot then hot = hot + 1 end
            end
        end
        assert(n > 0 and hot > 0, "map " .. m .. ": cells and hot cells to check")
        assert(ns.data.map[m] ~= md, "not the 100 grid")
        S.mapID = m
        WorldMapFrame:OnMapChanged()
        for ix, col in pairs(md) do
            for iy, q in pairs(col) do
                if q / 100 >= s.hot then
                    local red = false
                    for jx = 2 * ix, 2 * ix + 1 do
                        for jy = 2 * iy, 2 * iy + 1 do
                            local tex = cellTex(jx, jy)
                            if tex and isMapRed(tex._color) then red = true end
                        end
                    end
                    assert(red, ("map %d: the radar's hot cell %d,%d has a red fine cell on the map"):format(m, ix, iy))
                end
            end
        end
    end
    eq(ns.MapData(NO_DATA_MAP), nil)
    local plain = boot("nagdeath_base0.lua")
    eq(plain.MapData(ELWYNN), plain.data.map[ELWYNN], "without fine, the radar reads map")
end)

test("overlay: a threshold changed past the 14th digit redraws the picture", function()
    local ns = boot({ v = 1, cellBase = 0, map = { [ELWYNN] = { [10] = { [10] = 25 } } } })
    S.mapID = ELWYNN
    WorldMapFrame:OnMapChanged()
    assert(isMapRed(cellTex(20, 20)._color), "q 25 red at 0.25")
    SlashCmdList.NAGDEATHRADAR("threshold 0.250000000000001")
    local want = { ns.Color(0.25, NAGDeathRadarSettings) }
    eq(want[2], 1, "ns.Color (the radar) calls 0.25 yellow now")
    local tex = cellTex(20, 20)
    assert(tex and not isMapRed(tex._color), "the map follows: not red, not the cached red")
    -- The other way: drawn first at 0.250000000000001, the upsample does not lift q 25 (yellow there); at 0.25 the
    -- upsample must be built again, lifted, red.
    ns = boot({ v = 1, cellBase = 0, map = { [ELWYNN] = { [10] = { [10] = 25 } } } }, { saved = { hot = 0.250000000000001 } })
    S.mapID = ELWYNN
    WorldMapFrame:OnMapChanged()
    tex = cellTex(20, 20)
    assert(tex and not isMapRed(tex._color), "q 25 not red at 0.250000000000001")
    SlashCmdList.NAGDEATHRADAR("threshold 0.25")
    tex = cellTex(20, 20)
    assert(tex and isMapRed(tex._color), "at 0.25: red, not the cached unlifted grid")
end)

test("overlay: red on the map exactly where the radar calls a lone cell hot, for q 1, 9, 10, 24, 25, 100", function()
    local md = { [10] = { [10] = 1 }, [20] = { [20] = 9 }, [30] = { [30] = 10 }, [40] = { [40] = 24 },
        [50] = { [50] = 25 }, [60] = { [60] = 100 } }
    local ns = boot({ v = 1, cellBase = 0, map = { [ELWYNN] = md } })
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    local s = NAGDeathRadarSettings
    for ix, col in pairs(md) do
        for iy, q in pairs(col) do
            local sq = cellTex(2 * ix, 2 * iy)
            local want = { ns.MapColor(loneInner(q) / 100, s) }
            if not want[1] then
                eq(sq, nil, "q " .. q .. ": smoothed under the low band, not drawn")
            else
                assert(sq, "q " .. q .. " drawn")
                for k = 1, 4 do eq(sq._color[k], want[k], ("q %d channel %d"):format(q, k)) end
                eq(isMapRed(sq._color), q >= 25, "q " .. q .. ": red exactly when the radar calls it hot")
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
    assert(isMapRed(cellTex(90, 56)._color), "map: red at 0.25")
    SlashCmdList.NAGDEATHRADAR("threshold 0.4")
    assert(not isMapRed(cellTex(90, 56)._color), "map: no longer red at 0.4")
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
    assert(isMapRed(cellTex(90, 56)._color), "map: red again")
    ns.Radar.Paint()
    assert(isRed(blip.tex._vertex), "radar: red again")
end)

test("overlay: each lone cell draws its ramp colour; red never under its floor", function()
    local md = {}
    local qs = { 2, 9, 10, 24, 25, 32, 100 }
    for i, q in ipairs(qs) do md[i * 10] = { [i * 10] = q } end
    local ns = boot({ v = 1, cellBase = 0, map = { [ELWYNN] = md } })
    eq(NAGDeathRadarSettings.mapAlpha, 1, "default opacity 1")
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    for i, q in ipairs(qs) do
        local want = { ns.MapColor(loneInner(q) / 100, NAGDeathRadarSettings) }
        local sq = cellTex(i * 20, i * 20)
        if want[1] then
            assert(sq, "q " .. q)
            for k = 1, 4 do eq(sq._color[k], want[k], ("q %d channel %d"):format(q, k)) end
            if isMapRed(sq._color) then assert(sq._color[4] >= 0.5, "red floor") end
        else
            eq(sq, nil, "q " .. q .. " smoothed under the low band")
        end
    end
    SlashCmdList.NAGDEATHRADAR("threshold 0.05") -- red from q 5: q 9 is hot, its fine cells lifted to red
    local sq = cellTex(40, 40)
    assert(isMapRed(sq._color) and sq._color[4] >= 0.5, "q 9 red at its floor")
end)

test("overlay: /ndr alpha scales the map squares only, refuses nan, inf and out of range, and persists", function()
    local ns = boot(barrensLike())
    S.worldBounds[ELWYNN] = ELWYNN_BOUNDS
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    SlashCmdList.NAGDEATHRADAR("alpha 0.5")
    eq(NAGDeathRadarSettings.mapAlpha, 0.5)
    local s = NAGDeathRadarSettings
    near(cellTex(90, 56)._color[4], select(4, ns.MapColor(0.32, s)), "hot cell at half (its own q 32)", 1e-9)
    near(cellTex(62, 32)._color[4], select(4, ns.MapColor(0.05, s)), "quiet cell at half", 1e-9)
    s.mapAlpha = 1
    local full = select(4, ns.MapColor(0.05, s))
    s.mapAlpha = 0.5
    near(cellTex(62, 32)._color[4], full * 0.5, "half the full weight", 1e-9)
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

--- A menu description as Blizzard_Menu's root: records what the callback adds.
local function fakeRoot()
    local r = { added = {} }
    function r:CreateDivider() table.insert(self.added, { kind = "divider" }) end
    function r:CreateTitle(t) table.insert(self.added, { kind = "title", text = t }) end
    function r:Insert(d) table.insert(self.added, d) end
    return r
end

test("overlay: on a map with the filter button, the toggle is an entry in its menu (Forever)", function()
    local ns = boot("nagdeath_base0.lua", { menu = true, filterButton = true })
    eq(#S.modified, 1, "ModifyMenu once"); eq(S.modified[1].tag, "MENU_WORLD_MAP_TRACKING")
    eq(ns.MapToggle(), nil, "no box on the map")
    S.fire("ADDON_LOADED", "Blizzard_WorldMap") -- a second Init pass registers nothing more
    eq(#S.modified, 1, "still once")
    local root = fakeRoot()
    S.modified[1].callback(WorldMapFrame.WorldMapTrackingOptionsButton, root, {})
    eq(#root.added, 3, "a divider, a title and a checkbox")
    eq(root.added[1].kind, "divider"); eq(root.added[2].kind, "title"); eq(root.added[2].text, "NAG Death Radar")
    local cb = root.added[3]
    eq(cb.kind, "checkbox"); eq(cb.text, "Show deaths heatmap")
    eq(cb.isSelected(), true, "follows the setting")
    S.mapID, S.zoom = ELWYNN, 1
    WorldMapFrame:OnMapChanged()
    assert(ns.OverlayCount() > 0)
    cb.setSelected()
    eq(NAGDeathRadarSettings.overlay, false, "flips the setting"); eq(ns.OverlayCount(), 0, "and applies")
    eq(cb.isSelected(), false)
    SlashCmdList.NAGDEATHRADAR("map on")
    eq(cb.isSelected(), true, "/ndr map moves it"); assert(ns.OverlayCount() > 0)
    eq(S.panels[1].panel.boxes.overlay:GetChecked(), true, "the panel follows")
end)

test("overlay: the Menu API without the map's filter button (the Classic maps) keeps the box", function()
    local ns = boot("nagdeath_base0.lua", { menu = true })
    eq(#S.modified, 0, "no menu entry where no filter button shows it")
    assert(ns.MapToggle(), "the box")
    ns = boot("nagdeath_base0.lua")
    assert(ns.MapToggle(), "no Menu API at all: the box, nothing errors")
end)

test("overlay: the map's own toggle, /ndr map and the panel stay in step, and it is saved", function()
    local ns = boot("nagdeath_base0.lua")
    local t = assert(ns.MapToggle(), "a toggle on the world map")
    eq(t._parent, WorldMapFrame, "on the map frame, hidden with it")
    eq(t._template, "UICheckButtonTemplate")
    eq(t._point[1], "TOPRIGHT"); eq(t._point[2], WorldMapFrame:GetCanvasContainer(), "in the map area's top-right corner")
    eq(t:GetChecked(), true, "on")
    assert(t:GetFrameLevel() > 2719, "above the topmost pin level (2700 .. 2719), got " .. t:GetFrameLevel())
    assert(t:GetFrameLevel() > ns.OverlayLevel() and t:GetFrameLevel() > S.canvas:GetFrameLevel(), "above the layer and the canvas")
    t:SetFrameLevel(2) -- a level reset by the client
    WorldMapFrame._scripts.OnShow(WorldMapFrame)
    assert(t:GetFrameLevel() > 2719, "re-asserted on map show")
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
    assert((sl._h or 0) > 0 and (sl._w or 0) > 0, "the slider has a width and a height to draw in")
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
