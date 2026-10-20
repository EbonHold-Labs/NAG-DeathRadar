--- NAG Death Radar: settings, the data check, the cell index, the slash command and the load events.
--- An empty shell: it reads the NAGDeathData global (Data/NAGDeathData.lua, written by the NAG app) and draws it.
--- No network, no chat, no libraries; one SavedVariable, NAGDeathRadarSettings, holds the settings only.
--- Pure helpers live on ns so tests/run.lua can call them without a game client.
---
--- License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/legalcode)
--- Authors: @Rakizi, @Fonsas

local addonName, ns = ...

local type, pairs, ipairs, pcall, floor = type, pairs, ipairs, pcall, math.floor

ns.DATA_VERSION = 1 -- the NAGDeathData.v this addon reads
ns.GRID = 100       -- cells per side of every uiMapID in `map` (the radar's grid)
ns.FINE_GRID = 200  -- the world map's display grid: cells per side
ns.modules = {}     -- overlay and radar: Init(), Refresh(settings)

-- ============================ client reads ============================

--- True when the client marks v secret (clients with secret values only; false elsewhere).
function ns.IsSecret(v)
    local test = _G.issecretvalue
    return test ~= nil and test(v) == true
end

--- True when the game tooltip belongs to `owner`: IsOwned, else GetOwner.
function ns.TooltipOwnedBy(owner)
    local T = _G.GameTooltip
    if type(T) ~= "table" then return false end
    if type(T.IsOwned) == "function" then
        local ok, v = pcall(T.IsOwned, T, owner)
        return ok and v == true
    end
    if type(T.GetOwner) == "function" then
        local ok, o = pcall(T.GetOwner, T)
        return ok and o == owner
    end
    return false
end

function ns.InCombat()
    local f = _G.InCombatLockdown
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f)
    return ok and not ns.IsSecret(v) and v == true
end

-- ============================ settings ============================

ns.defaults = {
    radar = true,      -- the radar is shown
    overlay = true,    -- the heatmap on the world map
    mapAlpha = 1,      -- the heatmap's opacity, a multiplier on its squares only (the radar keeps its own)
    locked = false,    -- the radar cannot be dragged
    rimTint = true,    -- the radar's rim turns red while the player stands in a hot cell
    art = true,        -- Fonsas's ring and grid art over the plain rim and field
    ring = 1,          -- which ring art (ns.CHOICES.ring)
    grid = 1,          -- which grid art: 1 green, 2 blue
    scale = 1,         -- radar size
    yards = 100,       -- yards from the radar's centre to its rim
    hot = 0.25,        -- a cell is hot from this intensity (q / 100): red, the nearest-hot pointer and the rim tint
    thrLow = 0.02,     -- intensity colours below hot: light blue from thrLow, yellow from thrMid
    thrMid = 0.10,
    radarPos = { x = 0, y = -200 }, -- the radar's centre from UIParent's, in UIParent units
}

-- Numbers outside these bounds come back from the defaults.
ns.RANGES = { scale = { 0.5, 2 }, yards = { 30, 300 }, hot = { 0.05, 1 }, thrLow = { 0, 1 }, thrMid = { 0, 1 },
    mapAlpha = { 0.1, 1 } }
-- Settings that take one of a list (the art files under Media/).
ns.CHOICES = { ring = { 1, 2, 8, 10 }, grid = { 1, 2 } }

local function isChoice(key, v)
    for _, c in ipairs(ns.CHOICES[key]) do
        if v == c then return true end
    end
    return false
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

--- Fill missing, wrongly typed or out-of-range keys from the defaults; unknown keys stay.
function ns.InitSettings(sv)
    sv = type(sv) == "table" and sv or {}
    for k, v in pairs(ns.defaults) do
        local cur, r = sv[k], ns.RANGES[k]
        if type(cur) ~= type(v) or (r and (cur ~= cur or cur < r[1] or cur > r[2]))
            or (ns.CHOICES[k] and not isChoice(k, cur)) then
            sv[k] = copy(v)
        end
    end
    local p = sv.radarPos
    if type(p.x) ~= "number" or type(p.y) ~= "number" or p.x ~= p.x or p.y ~= p.y then
        sv.radarPos = copy(ns.defaults.radarPos)
    end
    return sv
end

-- ============================ data ============================

local function isInt(v)
    return type(v) == "number" and v == floor(v)
end

local function isNum(v)
    return type(v) == "number" and v == v
end

-- THE OPTIONAL `fine` FIELD (the server's, Tools PR #1142, relay 3726): finer cells for the world map, beside
-- `map`, which stays for older copies.
--   fine = { grid = 200, cellBase = 0, levels = 64, [uiMapID] = { "packed", "packed", ... } }
-- grid: cells per side, a multiple of 100 from FINE_GRID to 400 (never coarser than the map draws, which would leave
-- holes; a whole multiple, so each fine cell folds into one radar cell, where the server binned its deaths).
-- cellBase: 0 or 1, 0 when absent. levels: 2..64, 64 when absent; a cell's level is 1..levels - 1, the map's
-- hottest cell is levels - 1, read as q = 100 * level / (levels - 1). Each string holds whole runs along a row:
-- Y (2 chars), X (2 chars), N (1 char, 1 or more), then N level characters for the cells x .. x + N - 1 of row y;
-- a level 0 is an empty cell (it bridges a short gap). Every character is a base64 digit (FINE_B64) whose value
-- is its index; two-digit numbers are high digit first. A field that breaks any of this is ignored and the map
-- draws from `map`; a map whose strings break it is ignored alone.
ns.FINE_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
ns.FINE_MAX_GRID = 400

local B64 = {} -- a character's byte -> its digit value
for i = 1, #ns.FINE_B64 do B64[ns.FINE_B64:byte(i)] = i - 1 end

--- One map's list of packed strings -> its 0-based grid { [x] = { [y] = q } } and cell count, or nil.
function ns.DecodeFineMap(list, grid, base, levels)
    if type(list) ~= "table" or #list == 0 then return nil end
    local out, n = {}, 0
    for i = 1, #list do
        local s = list[i]
        if type(s) ~= "string" then return nil end
        local p, len = 1, #s
        while p <= len do
            if p + 4 > len then return nil end
            local y1, y2, x1, x2, c = B64[s:byte(p)], B64[s:byte(p + 1)], B64[s:byte(p + 2)], B64[s:byte(p + 3)],
                B64[s:byte(p + 4)]
            if not (y1 and y2 and x1 and x2 and c) or c < 1 or p + 4 + c > len then return nil end
            local y, x = y1 * 64 + y2 - base, x1 * 64 + x2 - base
            if y < 0 or y >= grid or x < 0 or x + c > grid then return nil end
            for k = 0, c - 1 do
                local q = B64[s:byte(p + 5 + k)]
                if not q or q >= levels then return nil end
                if q > 0 then
                    local col = out[x + k]
                    if not col then col = {}; out[x + k] = col end
                    if col[y] == nil then n = n + 1 end
                    col[y] = 100 * q / (levels - 1)
                end
            end
            p = p + 5 + c
        end
    end
    if n == 0 then return nil end
    return out, n
end

--- A 0-based grid of `from` cells per side folded to the 0-based ns.GRID grid, keeping each cell's highest q.
function ns.FoldToGrid(src, from)
    local out = {}
    for jx, col in pairs(src) do
        local ix = floor(jx * ns.GRID / from)
        local o = out[ix]
        if not o then o = {}; out[ix] = o end
        for jy, q in pairs(col) do
            local iy = floor(jy * ns.GRID / from)
            if (o[iy] or 0) < q then o[iy] = q end
        end
    end
    return out
end

--- The `fine` field -> { map = { [uiMapID] = grid }, grid = cells per side, maps = count } and "ok", or nil and a
--- reason ("absent", "format", "grid", "cellBase", "levels", "empty").
function ns.LoadFine(raw)
    local f = raw.fine
    if f == nil then return nil, "absent" end
    if type(f) ~= "table" then return nil, "format" end
    local grid, base, levels = f.grid, f.cellBase, f.levels
    if base == nil then base = 0 end
    if levels == nil then levels = #ns.FINE_B64 end
    if not isInt(grid) or grid % ns.GRID ~= 0 or grid < ns.FINE_GRID or grid > ns.FINE_MAX_GRID then
        return nil, "grid"
    end
    if base ~= 0 and base ~= 1 then return nil, "cellBase" end
    if not isInt(levels) or levels < 2 or levels > #ns.FINE_B64 then return nil, "levels" end
    local maps, coarse, nMaps = {}, {}, 0
    for m, list in pairs(f) do
        if isInt(m) and m > 0 then
            local g = ns.DecodeFineMap(list, grid, base, levels)
            if g then maps[m], coarse[m], nMaps = g, ns.FoldToGrid(g, grid), nMaps + 1 end
        end
    end
    if nMaps == 0 then return nil, "empty" end
    return { map = maps, coarse = coarse, grid = grid, maps = nMaps }, "ok"
end

-- ============================ flavor ============================

-- The plain toc loads on Classic Era, TBC, Wrath, Titan and Mists, and the data file the app drops is one game's
-- deaths (its `flavor`: today only "camelot", WoW Forever, collects). The radar draws a file only on the game it
-- came from. The client is named as NAG names it (Version.lua GetExpansion), mirrored here so the radar needs no
-- NAG: Forever reports interface 16001 and WOW_PROJECT_ID 1 like mainline, so the interface (16000..19999) or
-- the 1.60+ build string tells it, never the project id.
local FOREVER_MIN_INTERFACE = 16000

local function isForeverBuild(version, interface)
    if interface and interface >= FOREVER_MIN_INTERFACE and interface < 20000 then return true end
    local minor = type(version) == "string" and tonumber(version:match("^1%.(%d+)"))
    return minor ~= nil and minor >= 60
end

--- The running client's flavor, in NAG's names: "camelot" (WoW Forever), "vanilla", "sod", "tbc", "wrath",
--- "titan", "cata", "mists", "mainline"; nil when the client cannot be told (no GetBuildInfo).
function ns.ClientFlavor()
    local gbi = rawget(_G, "GetBuildInfo")
    if type(gbi) ~= "function" then return nil end
    local ok, version, _, _, interface = pcall(gbi)
    if not ok then return nil end
    interface = tonumber(interface) or 0
    local major = floor(interface / 10000)
    if interface <= 0 and type(version) == "string" then major = tonumber(version:match("^(%d+)")) or 0 end
    if major == 1 then
        if isForeverBuild(version, interface) then return "camelot" end
        local engraving = rawget(_G, "C_Engraving")
        if type(engraving) == "table" and type(engraving.IsEngravingEnabled) == "function" then
            local okE, on = pcall(engraving.IsEngravingEnabled)
            if okE and on == true then return "sod" end
        end
        return "vanilla"
    elseif major == 2 then
        return "tbc"
    elseif major == 3 then
        local minor = type(version) == "string" and tonumber(version:match("^3%.(%d+)"))
        return (minor and minor >= 80) and "titan" or "wrath"
    elseif major == 4 then
        return "cata"
    elseif major == 5 then
        return "mists"
    elseif major >= 10 then
        return "mainline"
    end
end

--- True when a data file's flavor is the running game's. A file without one is the first contract's, which only
--- WoW Forever ever wrote: it draws on Forever only. A client that cannot be told takes any file.
function ns.FlavorMatches(flavor)
    local client = ns.ClientFlavor()
    if client == nil then return true end
    if flavor == nil then return client == "camelot" end
    return flavor == client
end

ns.NO_DATA_GAME = "no data for this game"

--- The data check. Reads only the fields it knows and ignores every other one. Returns the data or nil, and a
--- reason. The data's cells are normalised to 0-based indices (0..99) whatever the file's base:
--- `cellBase` is read from the file, 1 when absent (relay 3460 plus the cell-base amendment). Every way the file
--- can be unusable (absent, nil, another `v`, no map table, a bad cell base, no valid cell) is the same "no data
--- yet" state for the reader; the reason is only for /ndr.
function ns.LoadData(raw)
    if type(raw) ~= "table" then return nil, "missing" end
    if raw.v ~= ns.DATA_VERSION then return nil, "version" end
    local base = raw.cellBase
    if base == nil then base = 1 end
    if base ~= 0 and base ~= 1 then return nil, "cellBase" end
    if type(raw.map) ~= "table" then return nil, "map" end
    if not ns.FlavorMatches(raw.flavor) then return nil, "flavor" end
    local GRID = ns.GRID
    local maps, nMaps, nCells = {}, 0, 0
    for m, cols in pairs(raw.map) do
        if isInt(m) and m > 0 and type(cols) == "table" then
            local grid, n = {}, 0
            for x, col in pairs(cols) do
                local ix = isInt(x) and x - base
                if ix and ix >= 0 and ix < GRID and type(col) == "table" then
                    for y, q in pairs(col) do
                        local iy = isInt(y) and y - base
                        if iy and iy >= 0 and iy < GRID and isNum(q) and q >= 1 and q <= 100 then
                            local g = grid[ix]
                            if not g then g = {}; grid[ix] = g end
                            g[iy] = q
                            n = n + 1
                        end
                    end
                end
            end
            if n > 0 then
                maps[m] = grid
                nMaps, nCells = nMaps + 1, nCells + n
            end
        end
    end
    if nMaps == 0 then return nil, "empty" end
    local published = isNum(raw.published) and raw.published or nil
    -- `fine` only adds: whatever it holds, the data above stands (a decode that raises reads no fine at all).
    local okFine, fine, fineReason = pcall(ns.LoadFine, raw)
    if not okFine then fine, fineReason = nil, "error" end
    return {
        map = maps, maps = nMaps, cells = nCells, base = base,
        stamp = published or (isNum(raw.generated) and raw.generated or nil), -- epoch seconds, published first
        rows = isInt(raw.rows) and raw.rows or nil,
        contributors = isInt(raw.contributors) and raw.contributors or nil,
        fine = fine, fineReason = fineReason,
    }, "ok"
end

--- An epoch second as a UTC date, or nil.
function ns.DateText(stamp)
    local d = _G.date
    if not isNum(stamp) or type(d) ~= "function" then return nil end
    local ok, s = pcall(d, "!%Y-%m-%d", stamp) -- UTC: a published window starts at 00:00 UTC
    return ok and type(s) == "string" and s or nil
end

ns.NO_DATA = "no data yet"
ns.NO_MAP_DATA = "no data for this map"

--- The note when nothing is drawn for the whole file: "no data for this game" for another game's file, else
--- "no data yet".
function ns.NoDataText()
    return ns.dataReason == "flavor" and ns.NO_DATA_GAME or ns.NO_DATA
end

--- One line on the data: "no data yet", or its date and size.
function ns.StatusLine()
    local d = ns.data
    if not d then return ns.NoDataText() end
    local line = "death data from " .. (ns.DateText(d.stamp) or "an unknown date")
    if d.rows and d.contributors then
        line = line .. (": %d deaths, %d players"):format(d.rows, d.contributors)
    end
    return line .. (", %d maps"):format(d.maps)
end

--- The radar's grid (ns.GRID per side) for a uiMapID, or nil: the file's `fine` cells folded to it (each cell its
--- hottest fine cell, so a cell the radar calls hot holds a fine cell the world map draws in the same red, and
--- the server's per-cell floor holds on both), else `map`.
function ns.MapData(map)
    local d = ns.data
    if not d or type(map) ~= "number" then return nil end
    return d.fine and d.fine.coarse[map] or d.map[map]
end

--- A map position 0..1 -> its 0-based cell 0..99, exactly as the server bins a death: the addon stores
--- floor(p * 10000 + 0.5) and the server takes n * 100 // 10001 (AnalyticsServer/deaths.py). Off the map: nil.
function ns.CellIndex(p)
    if not isNum(p) or p < 0 or p > 1 then return nil end
    local n = floor(p * 10000 + 0.5)
    local c = floor(n * ns.GRID / 10001)
    return c < ns.GRID and c or ns.GRID - 1
end

--- The middle of a 0-based cell as a map fraction.
function ns.CellCentre(i)
    return (i + 0.5) / ns.GRID
end

function ns.Q(mapData, ix, iy)
    local col = mapData and mapData[ix]
    return col and col[iy] or 0
end

--- The radar's danger colours: light blue / yellow / red by the settings' bands (the world map ramps instead,
--- ns.MapColor, and shares only the red: i >= hot), alpha growing with intensity i (q / 100) inside a band; nil below thrLow. This alpha is the radar's:
--- red (i >= hot) starts at 0.5 + 0.3 * hot (0.575 at the default 0.25).
function ns.Color(i, s)
    if i >= s.hot then return 1, 0, 0, 0.5 + 0.3 * math.min(i, 1) end
    if i >= s.thrMid then return 1, 1, 0, 0.3 + 0.6 * i end
    if i >= s.thrLow then return 0, 0.8, 1, 0.3 + 0.6 * i end
end

ns.MAP_RED_FLOOR = 0.5
ns.MAP_RAMP_STEPS = 24 -- shades under hot: enough to blend, few enough that touching cells share a texture
ns.MAP_RED_STEPS = 8   -- shades of red from hot, orange-red to deep red

-- The ramp's colours under hot (Rakizi, 2026-10-20: three flat bands read as stair-steps, the low blue as a
-- blanket; then, in game, yellow vanished on the Barrens' and Durotar's yellow-brown ground while a flat red
-- dominated): a light blue at thrLow, a teal-green halfway to thrMid (a straight blue-to-gold blend goes a
-- muddy grey there, lost on tan ground), a deeper gold at thrMid, orange just under hot, the alpha rising
-- linearly from a faint 0.18 to 0.5, so the middle (gold, about 0.34) still reads on yellow-brown terrain.
-- Each stop sits at a quarter of the ramp; thrMid is at its middle.
local RAMP = { { 0.35, 0.75, 1 }, { 0.3, 0.85, 0.55 }, { 1, 0.78, 0.08 }, { 1, 0.62, 0.06 }, { 1, 0.45, 0.05 } }
local RAMP_A_LOW, RAMP_A_HOT = 0.18, 0.5
-- Red from hot: orange-red at hot to deep red at the map's hottest, the alpha 0.5 to 0.75. Never blue, green at
-- most 0.2: the red family, which the ramp under hot (green 0.45 and more, some blue) never reaches.
local RED_LO, RED_HI = { 1, 0.2, 0 }, { 0.8, 0, 0 }
local RED_A_HI = 0.75

--- The world map's colour for intensity i: nil under thrLow; from thrLow to hot a ramp of MAP_RAMP_STEPS shades
--- (light blue, teal-green, gold at thrMid, orange), the alpha rising linearly; from hot (ns.Color's own test, so a cell
--- the radar calls hot is red on the map) the red family in MAP_RED_STEPS shades, orange-red to deep red, alpha
--- MAP_RED_FLOOR to 0.75. Times the mapAlpha setting. The fifth value names the step: equal steps are equal
--- colours. Thresholds in any order: where thrMid is not between thrLow and hot, the ramp goes straight from
--- blue to orange.
function ns.MapColor(i, s)
    if i >= s.hot then
        local u = s.hot < 1 and (math.min(i, 1) - s.hot) / (1 - s.hot) or 0
        local k = math.min(ns.MAP_RED_STEPS - 1, floor(u * ns.MAP_RED_STEPS))
        local w = (k + 0.5) / ns.MAP_RED_STEPS
        return RED_LO[1] + (RED_HI[1] - RED_LO[1]) * w, RED_LO[2] + (RED_HI[2] - RED_LO[2]) * w, 0,
            (ns.MAP_RED_FLOOR + (RED_A_HI - ns.MAP_RED_FLOOR) * w) * s.mapAlpha, 1000 + k
    end
    if i < s.thrLow then return nil end
    local lo, mid, hot = s.thrLow, s.thrMid, s.hot
    local t
    if mid > lo and mid < hot then
        t = i < mid and 0.5 * (i - lo) / (mid - lo) or 0.5 + 0.5 * (i - mid) / (hot - mid)
    else
        t = (i - lo) / (hot - lo)
    end
    local n = ns.MAP_RAMP_STEPS
    local k = math.max(0, math.min(n - 1, floor(t * n)))
    local tq = (k + 0.5) / n
    local seg = math.min(#RAMP - 1, floor(tq * (#RAMP - 1)) + 1)
    local a, b, w = RAMP[seg], RAMP[seg + 1], tq * (#RAMP - 1) - (seg - 1)
    return a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w, a[3] + (b[3] - a[3]) * w,
        (RAMP_A_LOW + (RAMP_A_HOT - RAMP_A_LOW) * tq) * s.mapAlpha, k
end

-- ============================ slash ============================

local function onOff(arg, cur)
    if arg == "on" then return true elseif arg == "off" then return false end
    return not cur
end

local NUMBERS = { scale = "scale", range = "yards", threshold = "hot", alpha = "mapAlpha" }

ns.HELP = {
    "/ndr show | hide: the radar",
    "/ndr lock: lock or unlock the radar (drag it with Alt held)",
    "/ndr map [on|off]: the heatmap on the world map (also in the map's filter menu, or its Deaths box), alpha 0.1-1: its opacity",
    "/ndr tint [on|off]: the rim turns red where you stand in a hot cell",
    "/ndr art [on|off], ring 1|2|8|10, grid 1|2 (1 green, 2 blue): the radar's look",
    "/ndr scale 0.5-2, range 30-300 (yards), threshold 0.05-1 (hot from this intensity)",
    "/ndr options (or Alt + right-click the radar): the settings panel; /ndr reset: the defaults; /ndr help: this list",
}

--- Pure: returns the settings (a new table after reset), the reply lines, and an action ("panel") or nil.
function ns.Command(s, msg)
    local cmd, arg = (type(msg) == "string" and msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "show" or cmd == "hide" then
        s.radar = cmd == "show"
        return s, { "radar " .. (s.radar and "shown" or "hidden") }
    elseif cmd == "lock" then
        s.locked = onOff(arg, s.locked)
        return s, { "radar " .. (s.locked and "locked" or "unlocked: drag it with Alt held") }
    elseif cmd == "map" then
        s.overlay = onOff(arg, s.overlay)
        return s, { "heatmap " .. (s.overlay and "on" or "off") }
    elseif cmd == "tint" then
        s.rimTint = onOff(arg, s.rimTint)
        return s, { "rim tint " .. (s.rimTint and "on" or "off") }
    elseif cmd == "art" then
        s.art = onOff(arg, s.art)
        return s, { "radar art " .. (s.art and "on" or "off") }
    elseif ns.CHOICES[cmd] then
        local n = tonumber(arg)
        if not isChoice(cmd, n) then
            return s, { ("%s takes %s (now %s)"):format(cmd, table.concat(ns.CHOICES[cmd], ", "), tostring(s[cmd])) }
        end
        s[cmd] = n
        return s, { cmd .. " " .. n }
    elseif NUMBERS[cmd] then
        local key, n, r = NUMBERS[cmd], tonumber(arg), ns.RANGES[NUMBERS[cmd]]
        -- tonumber reads "nan" and "inf": NaN fails every comparison, so it is refused by name, inf with it.
        if not n or n ~= n or n == math.huge or n == -math.huge or n < r[1] or n > r[2] then
            return s, { ("%s takes %s to %s (now %s)"):format(cmd, r[1], r[2], tostring(s[key])) }
        end
        s[key] = n
        return s, { cmd .. " " .. n }
    elseif cmd == "reset" then
        return ns.InitSettings(nil), { "settings reset" }
    elseif cmd == "options" or cmd == "config" then
        return s, {}, "panel"
    end
    local lines = { ns.StatusLine() }
    for _, l in ipairs(ns.HELP) do lines[#lines + 1] = l end
    return s, lines
end

function ns.Say(msg)
    print("|cffff5555NAG Death Radar|r: " .. msg)
end

--- Push the settings to every module.
function ns.Apply()
    for _, m in ipairs(ns.modules) do
        if m.Refresh then m.Refresh(NAGDeathRadarSettings) end
    end
    if ns.RefreshPanel then ns.RefreshPanel() end
end

SLASH_NAGDEATHRADAR1 = "/ndr"
SlashCmdList.NAGDEATHRADAR = function(msg)
    local lines, action
    NAGDeathRadarSettings, lines, action = ns.Command(NAGDeathRadarSettings, msg)
    for _, l in ipairs(lines) do ns.Say(l) end
    if action == "panel" and ns.OpenPanel then ns.OpenPanel() end
    ns.Apply()
end

-- ============================ load ============================

local loggedIn = false
local function initModules()
    for _, m in ipairs(ns.modules) do
        if m.Init then m.Init() end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        NAGDeathRadarSettings = ns.InitSettings(NAGDeathRadarSettings)
        ns.data, ns.dataReason = ns.LoadData(_G.NAGDeathData)
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_WorldMap" and loggedIn then
        initModules() -- each Init runs once; the overlay's waits for the world map
        ns.Apply()
    elseif event == "PLAYER_LOGIN" then
        loggedIn = true
        initModules()
        if ns.BuildPanel then ns.BuildPanel() end
        ns.Apply()
    end
end)
