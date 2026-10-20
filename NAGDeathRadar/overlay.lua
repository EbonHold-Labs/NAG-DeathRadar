--- NAG Death Radar: the heatmap on the world map, on WorldMapFrame's canvas, redrawn when the map, the settings
--- or the canvas size changes (not on zoom: every zoom shows the same picture). Only where the client's
--- WorldMapFrame has a canvas (GetCanvas); elsewhere the module does nothing.
---
--- THE PICTURE is a FINE_GRID (200) x 200 grid per map: the file's `fine` cells when it has them for the map,
--- else its 100 grid upsampled bilinearly (ns.Upsample), where a fine cell is never in a lower colour band than
--- its own 100-cell's, so a cell the radar calls hot is red on the map too (with `fine`, the radar reads the fine
--- cells folded to 100: ns.MapData). Same-colour cells along a row are one
--- texture (ns.Runs: the band and the alpha rounded to ALPHA_STEP); over CAP textures the grid is folded to
--- 100, then 50, then 25 per side, keeping each bucket's hottest cell. A texture is anchored at its TOPLEFT and
--- BOTTOMRIGHT from the same edge formula as its neighbours, with pixel snapping off, so touching squares meet
--- on one edge: no gap, no double-blended line. Textures are pooled, never destroyed.
---
--- THE LAYER sits just above the map art and the explored-area overlays and below the pins and the player
--- arrow: its frame level is the map's own "PIN_FRAME_LEVEL_MAP_EXPLORATION" level plus one, read (never
--- changed) from the map's pin frame level manager; without that manager, one above the canvas. The levels are
--- contiguous, so that level is the next pin type's own. On Forever (Mainline map: PLUNDERSTORM_CIRCLE) and on
--- the Vanilla and TBC maps (GARRISON_PLOT) that type is unused there, so the layer is alone at its level. On
--- the Wrath and Cata maps (Titan Reforged, MoP Classic) it is QUEST_BLOB: the heat and the quest-area blobs
--- share the level and their order is not defined (both are see-through). Reserving a level of our own would
--- mean writing into Blizzard's manager (InsertFrameLevelAbove), which is not done: it would taint the map.
---
--- License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/legalcode)
--- Authors: @Rakizi, @Fonsas

local _, ns = ...

local type, pairs, pcall, floor = type, pairs, pcall, math.floor

local O = {}
table.insert(ns.modules, O)
ns.Overlay = O

O.CAP = 2500       -- textures at most; a denser picture is drawn at the next coarser grid
O.ALPHA_STEP = 0.02 -- a run's alpha is rounded to this step, so neighbours a shade apart share a texture

--- Fold a 0-based `from` x `from` grid (ns.GRID when absent) into n x n buckets (1-based, 1..n), keeping the
--- highest q per bucket. Returns the buckets and their count.
function ns.Rebucket(mapData, n, from)
    from = from or ns.GRID
    local out, count = {}, 0
    for ix, col in pairs(mapData) do
        local bx = floor(ix * n / from) + 1
        local o = out[bx]
        if not o then o = {}; out[bx] = o end
        for iy, q in pairs(col) do
            local by = floor(iy * n / from) + 1
            local had = o[by]
            if not had then count = count + 1 end
            if (had or 0) < q then o[by] = q end
        end
    end
    return out, count
end

--- The band ns.Color gives i, by ns.Color's own tests in its own order: 3 red, 2 yellow, 1 light blue, 0 none.
--- It never falls as i grows, whatever the order of the thresholds.
local function band(i, s)
    if i >= s.hot then return 3 end
    if i >= s.thrMid then return 2 end
    if i >= s.thrLow then return 1 end
    return 0
end

--- A 0-based ns.GRID grid -> the 0-based FINE_GRID grid, bilinear between cell centres (an edge cell repeats past
--- the edge). A fine cell whose value falls in a lower band than its own 100-cell's (settings s) takes that
--- cell's q, so its band is the same by the same tests, with no rounding in between. Only cells above 0.
function ns.Upsample(md, s)
    local from, to = ns.GRID, ns.FINE_GRID
    local k = to / from
    local function q(x, y)
        if x < 0 then x = 0 elseif x >= from then x = from - 1 end
        if y < 0 then y = 0 elseif y >= from then y = from - 1 end
        local col = md[x]
        return col and col[y] or 0
    end
    -- The fine cells a source cell i reaches: |(j + 0.5) / k - 0.5 - i| < 1.
    local function span(i)
        local lo, hi = floor((i - 0.5) * k - 0.5) + 1, math.ceil((i + 1.5) * k - 0.5) - 1
        return lo < 0 and 0 or lo, hi >= to and to - 1 or hi
    end
    local out, seen = {}, {}
    for ix, col in pairs(md) do
        local x0, x1 = span(ix)
        for iy in pairs(col) do
            local y0, y1 = span(iy)
            for jx = x0, x1 do
                for jy = y0, y1 do
                    local id = jx * to + jy
                    if not seen[id] then
                        seen[id] = true
                        local u, v = (jx + 0.5) / k - 0.5, (jy + 0.5) / k - 0.5
                        local ux, vy = floor(u), floor(v)
                        local tx, ty = u - ux, v - vy
                        local val = (1 - tx) * (1 - ty) * q(ux, vy) + tx * (1 - ty) * q(ux + 1, vy)
                            + (1 - tx) * ty * q(ux, vy + 1) + tx * ty * q(ux + 1, vy + 1)
                        local parent = q(floor(jx / k), floor(jy / k))
                        if parent > val and band(val / 100, s) < band(parent / 100, s) then val = parent end
                        if val > 0 then
                            local o = out[jx]
                            if not o then o = {}; out[jx] = o end
                            o[jy] = val
                        end
                    end
                end
            end
        end
    end
    return out
end

--- Same-colour runs along each row of n x n buckets (1-based) in the map's colours: a list of
--- { x0 = first bucket, x1 = last bucket, y = row, r, g, b, a }. Nothing below the low band.
function ns.Runs(buckets, n, s)
    local rows = {}
    for bx, col in pairs(buckets) do
        for by, q in pairs(col) do
            local r, g, b, a = ns.MapColor(q / 100, s)
            if r then
                local row = rows[by]
                if not row then row = {}; rows[by] = row end
                row[#row + 1] = { bx, r, g, b, floor(a / O.ALPHA_STEP + 0.5) }
            end
        end
    end
    local runs = {}
    for by, row in pairs(rows) do
        table.sort(row, function(p, q) return p[1] < q[1] end)
        local cur
        for _, c in ipairs(row) do
            if cur and c[1] == cur.x1 + 1 and c[2] == cur.r and c[3] == cur.g and c[4] == cur.b and c[5] == cur.step then
                cur.x1 = c[1]
            else
                cur = { x0 = c[1], x1 = c[1], y = by, r = c[2], g = c[3], b = c[4], step = c[5], a = c[5] * O.ALPHA_STEP }
                runs[#runs + 1] = cur
            end
        end
    end
    return runs
end

--- The runs of a 0-based `from` grid drawn n per side, under the texture cap: halve n until they fit (25 at
--- the least). Returns the runs and n.
function ns.CappedRuns(src, from, n, cap, s)
    local runs = ns.Runs(ns.Rebucket(src, n, from), n, s)
    while #runs > cap and n > 25 do
        n = n / 2
        runs = ns.Runs(ns.Rebucket(src, n, from), n, s)
    end
    return runs, n
end

local layer, label, toggle, menuEntry
local pool, used = {}, 0
local lastMap
-- A number in a cache key at full precision: "..", like tostring, keeps 14 digits, and two thresholds that differ
-- past them would share a key.
local function exact(v) return ("%.17g"):format(v) end
local upCache = {}  -- the last map's upsampled grid, for its 100 grid and bands
local runCache = {} -- the last picture's runs, for its source grid and colours (a map reopens without rework)

local function mapFrame()
    local W = _G.WorldMapFrame
    if type(W) == "table" and type(W.GetCanvas) == "function" then return W end
end

local function currentMap(W)
    local ok, map = pcall(W.GetMapID, W)
    if ok and not ns.IsSecret(map) and type(map) == "number" then return map end
end

local function hideAll()
    for i = 1, used do pool[i]:Hide() end
    used = 0
end

local function say(text)
    if not label then return end
    if text then
        label.text:SetText("NAG Death Radar: " .. text)
        label:Show()
    else
        label:Hide()
    end
end

--- The grid the map draws for a uiMapID and its cells per side: the file's `fine` cells for the map, else its
--- 100 grid upsampled to FINE_GRID. nil without data for the map.
function O.Source(map, s)
    local d = ns.data
    local fine = d and d.fine and type(map) == "number" and d.fine.map[map]
    if fine then return fine, d.fine.grid end
    local md = ns.MapData(map)
    if not md then return nil end
    local key = exact(s.hot) .. ":" .. exact(s.thrMid) .. ":" .. exact(s.thrLow)
    if upCache.md ~= md or upCache.key ~= key then
        upCache.md, upCache.key, upCache.grid = md, key, ns.Upsample(md, s)
    end
    return upCache.grid, ns.FINE_GRID
end

--- Pixel snapping off, where the client has the calls: a square's edges stay where they are set.
local function noSnap(t)
    if type(t.SetSnapToPixelGrid) == "function" then t:SetSnapToPixelGrid(false) end
    if type(t.SetTexelSnappingBias) == "function" then t:SetTexelSnappingBias(0) end
end

function O.Redraw(force)
    if not layer then return end
    local s = NAGDeathRadarSettings
    local W = mapFrame()
    local map = W and currentMap(W)
    if not force and map == lastMap then return end
    lastMap = map
    hideAll()
    if not s.overlay then return say(nil) end
    if not ns.data then return say(ns.NO_DATA) end
    local src, from = O.Source(map, s)
    if not src then return say(ns.NO_MAP_DATA) end
    say(nil)
    local key = exact(s.hot) .. ":" .. exact(s.thrMid) .. ":" .. exact(s.thrLow) .. ":" .. exact(s.mapAlpha) .. ":" .. O.CAP
    if runCache.src ~= src or runCache.key ~= key then
        runCache.src, runCache.key = src, key
        runCache.runs, runCache.n = ns.CappedRuns(src, from, ns.FINE_GRID, O.CAP, s)
    end
    local runs, n = runCache.runs, runCache.n
    local cw, ch = layer:GetWidth() / n, layer:GetHeight() / n
    -- The radar's own bands (ns.MapColor: ns.Color's colours at the map's lighter weight). Both corners come from
    -- one edge formula, k * cw and k * ch, so a run ends exactly where its neighbour starts.
    for _, run in ipairs(runs) do
        used = used + 1
        local t = pool[used]
        if not t then
            t = layer:CreateTexture(nil, "ARTWORK")
            noSnap(t)
            pool[used] = t
        end
        t:SetColorTexture(run.r, run.g, run.b, run.a)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", layer, "TOPLEFT", (run.x0 - 1) * cw, -(run.y - 1) * ch)
        t:SetPoint("BOTTOMRIGHT", layer, "TOPLEFT", run.x1 * cw, -run.y * ch)
        t:Show()
    end
end

--- The frame level just above the explored-area overlays, from the map's own pin levels.
local function layerLevel(W, canvas)
    if type(W.GetPinFrameLevelsManager) == "function" then
        local ok, mgr = pcall(W.GetPinFrameLevelsManager, W)
        if ok and type(mgr) == "table" and type(mgr.GetValidFrameLevel) == "function" then
            local okLevel, level = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
            if okLevel and type(level) == "number" then return level + 1 end
        end
    end
    return canvas:GetFrameLevel() + 1
end

function O.Init()
    if layer then return end
    local W = mapFrame()
    if not W then return end
    local ok, canvas = pcall(W.GetCanvas, W)
    if not ok or type(canvas) ~= "table" then return end
    layer = CreateFrame("Frame", "NAGDeathRadarMapLayer", canvas) -- named for in-game probes
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel(layerLevel(W, canvas))
    layer:SetScript("OnSizeChanged", function() O.Redraw(true) end)
    -- The note ("no data yet", "no data for this map") on the map's visible part, not the scrolled canvas.
    local holder = type(W.GetCanvasContainer) == "function" and W:GetCanvasContainer() or canvas
    label = CreateFrame("Frame", nil, holder)
    label:SetSize(320, 20)
    label:SetPoint("BOTTOM", holder, "BOTTOM", 0, 8)
    label:SetFrameLevel(layer:GetFrameLevel() + 1)
    label.text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label.text:SetAllPoints()
    label:Hide()
    if type(W.OnMapChanged) == "function" then
        hooksecurefunc(W, "OnMapChanged", function() O.Redraw() end)
    end
    W:HookScript("OnShow", function()
        O.RaiseToggle()
        O.Redraw(true)
    end)
    if not O.AddMenuEntry(W) then O.BuildToggle(W) end
end

local MENU_TAG = "MENU_WORLD_MAP_TRACKING"

--- THE SWITCH IN THE MAP'S FILTER MENU: a "NAG Death Radar" section (divider, title, check box) added to the
--- world map's tracking menu through Blizzard's public Menu.ModifyMenu, bound to the same `overlay` setting as
--- /ndr map and the panel. Only where the map shows that menu's button (WorldMapTrackingOptionsButton: the
--- Mainline map, Forever). Every target client has the Menu API, but the Classic maps (Vanilla, TBC, Wrath,
--- Cata) define the button's template and never create it, so their menu never opens: they keep the box.
--- Registered once; true when the entry is in place.
function O.AddMenuEntry(W)
    if menuEntry then return true end
    local M, MU = _G.Menu, _G.MenuUtil
    if type(M) ~= "table" or type(M.ModifyMenu) ~= "function" or type(MU) ~= "table"
        or type(MU.CreateCheckbox) ~= "function" or type(W.WorldMapTrackingOptionsButton) ~= "table" then
        return false
    end
    local function isSelected() return NAGDeathRadarSettings.overlay == true end
    local function setSelected()
        NAGDeathRadarSettings.overlay = not NAGDeathRadarSettings.overlay
        ns.Apply()
    end
    local ok = pcall(M.ModifyMenu, MENU_TAG, function(_, root)
        pcall(function()
            root:CreateDivider()
            root:CreateTitle("NAG Death Radar")
            root:Insert(MU.CreateCheckbox("Show deaths heatmap", isSelected, setSelected))
        end)
    end)
    menuEntry = ok
    return ok
end

--- The box's frame level: above every pin. A child of WorldMapFrame sits at the map's level + 1, under the
--- canvas's pins (from about 2000, MAP_CANVAS_PIN_FRAME_LEVEL_DEFAULT); so it takes the pin manager's highest
--- level (the topmost type's last) plus a margin for a pin's own children, and never less than the heat
--- layer's plus 100. The strata is left as the map's own (the Vanilla and TBC maps go FULLSCREEN when
--- maximised). Set again on every map show, as the client can reset levels.
local TOGGLE_MARGIN, LAYER_MARGIN = 20, 100

function O.RaiseToggle()
    if not toggle then return end
    local level = layer and layer:GetFrameLevel() + LAYER_MARGIN or 0
    local W = mapFrame()
    if W and type(W.GetPinFrameLevelsManager) == "function" then
        local ok, mgr = pcall(W.GetPinFrameLevelsManager, W)
        if ok and type(mgr) == "table" and type(mgr.GetValidFrameLevel) == "function" then
            local okTop, top = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_TOPMOST", 10000)
            if okTop and type(top) == "number" and top + TOGGLE_MARGIN > level then level = top + TOGGLE_MARGIN end
        end
    end
    if level > 0 and toggle:GetFrameLevel() ~= level then toggle:SetFrameLevel(level) end
end

local function toggleTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Death heatmap: " .. (NAGDeathRadarSettings.overlay and "on" or "off"))
    GameTooltip:AddLine(ns.StatusLine(), 1, 1, 1)
    GameTooltip:Show()
end

--- THE BOX ON THE MAP, where the map has no filter menu (the Classic maps): a check box in the top-right corner
--- of the map area, a child of WorldMapFrame so it hides with the map; our frame and our SetPoint, nothing
--- written into Blizzard's frames. It drives the same `overlay` setting as /ndr map and the panel. In the
--- wow-ui-source clones that corner is free on the Classic maps: the Vanilla and TBC maps keep their dropdowns,
--- zoom-out and close buttons in the bar above the map area and the "zoom out" magnifier at its top left; Wrath
--- and Cata keep the floor dropdown in that bar (maximised) or at the map area's top left (windowed). On Forever
--- (Mainline map) the "Dungeon map" and Map Filter buttons sit in that corner in game, so Forever uses the menu.
function O.BuildToggle(W)
    if toggle then return end
    local holder = type(W.GetCanvasContainer) == "function" and W:GetCanvasContainer() or W
    toggle = CreateFrame("CheckButton", nil, W, "UICheckButtonTemplate")
    toggle:SetSize(24, 24)
    toggle:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -6, -6)
    local text = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("RIGHT", toggle, "LEFT", -2, 0)
    text:SetText("Deaths")
    toggle:SetScript("OnClick", function(self)
        NAGDeathRadarSettings.overlay = self:GetChecked() and true or false
        ns.Apply()
        if ns.TooltipOwnedBy(self) then toggleTip(self) end
    end)
    toggle:SetScript("OnEnter", toggleTip)
    toggle:SetScript("OnLeave", function(self)
        if ns.TooltipOwnedBy(self) then GameTooltip:Hide() end
    end)
    toggle:SetChecked(NAGDeathRadarSettings.overlay)
    O.RaiseToggle()
end

function O.Refresh(s)
    if toggle then toggle:SetChecked(s.overlay) end
    O.Redraw(true)
end

function ns.OverlayCount() return used end -- for the tests
function ns.OverlayNote() return label and label:IsShown() and label.text:GetText() or nil end
function ns.OverlayLevel() return layer and layer:GetFrameLevel() end
function ns.MapToggle() return toggle end
