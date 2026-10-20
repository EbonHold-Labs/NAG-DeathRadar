--- NAG Death Radar: the heatmap on the world map. One square texture per bucket on WorldMapFrame's canvas,
--- redrawn when the map, the zoom bucket or the canvas size changes. Textures are pooled, never destroyed.
--- Only where the client's WorldMapFrame has a canvas (GetCanvas); elsewhere the module does nothing.
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

O.CAP = 2500 -- textures at most; a denser picture is drawn at the next coarser bucket size

--- Merge the 0-based 100 x 100 grid into n x n buckets (1-based, 1..n), keeping the highest q per bucket.
--- Returns the buckets and their count.
function ns.Rebucket(mapData, n)
    local out, count = {}, 0
    local GRID = ns.GRID
    for ix, col in pairs(mapData) do
        local bx = floor(ix * n / GRID) + 1
        local o = out[bx]
        if not o then o = {}; out[bx] = o end
        for iy, q in pairs(col) do
            local by = floor(iy * n / GRID) + 1
            local had = o[by]
            if not had then count = count + 1 end
            if (had or 0) < q then o[by] = q end
        end
    end
    return out, count
end

--- Zoomed out -> coarse, zoomed in -> the full grid. z: 0 .. 1 (the canvas zoom percent).
function ns.BucketsForZoom(z)
    if type(z) ~= "number" or z < 1 / 3 then return 25 end
    if z < 2 / 3 then return 50 end
    return 100
end

--- The buckets to draw for zoom bucket n, under the texture cap: halve n until the count fits.
function ns.CappedBuckets(mapData, n, cap)
    local b, count = ns.Rebucket(mapData, n)
    while count > cap and n > 25 do
        n = n / 2
        b, count = ns.Rebucket(mapData, n)
    end
    return b, n, count
end

--- Yellow (few deaths) -> red (the map's worst spot).
function ns.Ramp(q)
    local t = math.min(q, 100) / 100
    return 1, 1 - t, 0, 0.25 + 0.45 * t
end

local layer, label
local pool, used = {}, 0
local lastMap, lastN

local function mapFrame()
    local W = _G.WorldMapFrame
    if type(W) == "table" and type(W.GetCanvas) == "function" then return W end
end

local function currentMap(W)
    local ok, map = pcall(W.GetMapID, W)
    if ok and not ns.IsSecret(map) and type(map) == "number" then return map end
end

--- The canvas zoom 0..1. A map with a single zoom scale answers 0 % (PercentageBetween with min == max), which
--- would draw it at the coarsest level for good: such a map is drawn at full detail (1).
local function zoom(W)
    if type(W.GetScaleForMinZoom) == "function" and type(W.GetScaleForMaxZoom) == "function" then
        local okLo, lo = pcall(W.GetScaleForMinZoom, W)
        local okHi, hi = pcall(W.GetScaleForMaxZoom, W)
        if okLo and okHi and not ns.IsSecret(lo) and not ns.IsSecret(hi) and type(lo) == "number"
            and type(hi) == "number" and hi <= lo then
            return 1
        end
    end
    if type(W.GetCanvasZoomPercent) ~= "function" then return nil end
    local ok, z = pcall(W.GetCanvasZoomPercent, W)
    if ok and not ns.IsSecret(z) then return z end
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

function O.Redraw(force)
    if not layer then return end
    local s = NAGDeathRadarSettings
    local W = mapFrame()
    local map = W and currentMap(W)
    local n = W and ns.BucketsForZoom(zoom(W)) or 25
    if not force and map == lastMap and n == lastN then return end
    lastMap, lastN = map, n
    hideAll()
    if not s.overlay then return say(nil) end
    if not ns.data then return say(ns.NO_DATA) end
    local md = ns.MapData(map)
    if not md then return say(ns.NO_MAP_DATA) end
    say(nil)
    local buckets, drawn = ns.CappedBuckets(md, n, O.CAP)
    local cw, ch = layer:GetWidth() / drawn, layer:GetHeight() / drawn
    for bx, col in pairs(buckets) do
        for by, q in pairs(col) do
            used = used + 1
            local t = pool[used]
            if not t then
                t = layer:CreateTexture(nil, "ARTWORK")
                pool[used] = t
            end
            t:SetColorTexture(ns.Ramp(q))
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", layer, "TOPLEFT", (bx - 1) * cw, -(by - 1) * ch)
            t:SetSize(cw, ch)
            t:Show()
        end
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
    layer = CreateFrame("Frame", nil, canvas)
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
    if type(W.OnCanvasScaleChanged) == "function" then
        hooksecurefunc(W, "OnCanvasScaleChanged", function() O.Redraw() end)
    end
    W:HookScript("OnShow", function() O.Redraw(true) end)
end

function O.Refresh()
    O.Redraw(true)
end

function ns.OverlayCount() return used end -- for the tests
function ns.OverlayNote() return label and label:IsShown() and label.text:GetText() or nil end
function ns.OverlayLevel() return layer and layer:GetFrameLevel() end
