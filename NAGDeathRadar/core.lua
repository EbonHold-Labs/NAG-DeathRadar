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
ns.GRID = 100       -- cells per side of every uiMapID
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
    return {
        map = maps, maps = nMaps, cells = nCells, base = base,
        stamp = published or (isNum(raw.generated) and raw.generated or nil), -- epoch seconds, published first
        rows = isInt(raw.rows) and raw.rows or nil,
        contributors = isInt(raw.contributors) and raw.contributors or nil,
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

--- One line on the data: "no data yet", or its date and size.
function ns.StatusLine()
    local d = ns.data
    if not d then return ns.NO_DATA end
    local line = "death data from " .. (ns.DateText(d.stamp) or "an unknown date")
    if d.rows and d.contributors then
        line = line .. (": %d deaths, %d players"):format(d.rows, d.contributors)
    end
    return line .. (", %d maps"):format(d.maps)
end

--- The data's grid for a uiMapID, or nil.
function ns.MapData(map)
    local d = ns.data
    return d and type(map) == "number" and d.map[map] or nil
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

--- The danger colours, ONE scale for the radar and the world map: light blue / yellow / red by the settings'
--- bands, alpha growing with intensity i (q / 100) inside a band; nil below thrLow. This alpha is the radar's:
--- red (i >= hot) starts at 0.5 + 0.3 * hot (0.575 at the default 0.25).
function ns.Color(i, s)
    if i >= s.hot then return 1, 0, 0, 0.5 + 0.3 * math.min(i, 1) end
    if i >= s.thrMid then return 1, 1, 0, 0.3 + 0.6 * i end
    if i >= s.thrLow then return 0, 0.8, 1, 0.3 + 0.6 * i end
end

ns.MAP_RED_FLOOR = 0.4

--- The world map's colour for intensity i: the same bands (ns.Color), at the lighter weight the map's first
--- ramp had, 0.25 + 0.45 * i, so the map art reads through; red never under MAP_RED_FLOOR. Times the mapAlpha
--- setting. nil below thrLow.
function ns.MapColor(i, s)
    local r, g, b = ns.Color(i, s)
    if not r then return nil end
    local a = 0.25 + 0.45 * math.min(i, 1)
    if i >= s.hot and a < ns.MAP_RED_FLOOR then a = ns.MAP_RED_FLOOR end
    return r, g, b, a * s.mapAlpha
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
