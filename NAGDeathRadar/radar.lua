--- NAG Death Radar: the radar. A round frame with the player at the centre, `yards` yards to the rim, THE FACING
--- UP: the picture turns with the character and the arrow never does (with no facing to read it is north up).
--- The data cells around the player are round blips in the intensity colours (light blue, yellow, red), each at
--- its true spot and cut by the radar's circle. The nearest HOT cell (q / 100 at or above the `hot` setting) has a
--- marker at its spot, held at the rim when it lies past it, and its distance under the radar. While the player
--- stands in a hot cell the rim turns red (setting rimTint, on by default; no glow and no sound, relay 3459 Q1).
---
--- WHERE THINGS ARE. Everything is measured on the map the player stands on: the player's and the cells' map
--- fractions, turned into yards by the map's size in yards, which is read through C_Map.GetWorldPosFromMapPos at
--- the map's corners (C_Map.GetMapWorldSize where those give nothing). UnitPosition is never read, so two yard
--- sources are never mixed. Every client read is guarded with pcall and issecretvalue; a read that is not plain
--- shows "no position here" and draws nothing; that and "no data for this map" dim the radar to 30 %.
---
--- PAINT AND TURN. A paint every 0.1 s (where the player is, which cells are near); between two paints the
--- facing is followed every frame and only the pieces that moved are touched (SetPoint on a change only). The
--- OnUpdate runs only while the radar is shown and there is data: with no data the centre says "no data yet"
--- and nothing ticks.
---
--- MOUSE. The radar takes the mouse only while Alt is held, so clicks on the world under it are never
--- swallowed: Alt + left-drag moves it (unless locked), Alt + right-click opens the settings and Alt + hover
--- shows the data line (both out of combat).
---
--- The geometry and the drawing helpers (ToPlane, ToScreen, circleMask, maskWith, placeAt, the build, the
--- drag and the OnUpdate) are copied from NAG's Shaman totem radar (NAG/camelot/etn1.lua), and the position and
--- facing reads from NAG's totem reach (NAG/camelot/mnc3.lua mapRead, facingRead), same organisation, same
--- licence. The ring and grid art (Media/frame1, 2, 8, 10 and radarGrids1, 2) are Fonsas's own, from
--- FonsasDeathRadar, free to use (relay 3457); a plain ring and field drawn under them stay if the art does
--- not load or is switched off. His frame7 is left out: a red ring would read as the hot tint.
---
--- License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/legalcode)
--- Authors: @Rakizi, @Fonsas

local _, ns = ...

local type, pairs, pcall, floor, ceil, sqrt = type, pairs, pcall, math.floor, math.ceil, math.sqrt
local min, max = math.min, math.max

local R = {}
table.insert(ns.modules, R)
ns.Radar = R

local RADIUS = 60         -- pixels from the centre to the rim (the field)
local BORDER = 4          -- the plain ring outside the field, pixels
local POINTER = 12        -- the nearest-hot marker, pixels
local ARROW_SIZE = 14
local BLIP_MIN = 4        -- the smallest blip, pixels
local MAX_BLIPS = 80      -- blips at most; the hottest are kept
local TICK = 0.1          -- seconds between two paints
local MEDIA = "Interface\\AddOns\\NAGDeathRadar\\Media\\"
local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local DISC = CIRCLE_MASK  -- a white disc on transparent: tinted, a round blip
local ARROW = "Interface\\Minimap\\MinimapArrow"
-- Fonsas's rings (Media/frameN.png, 250 x 250), each as a share of the width. `hole`: the widest radius of the
-- hole (alpha > 128, 72 rays out of the centre), so no gap shows between the field and the ring. `outer`: the
-- furthest corner of any opaque pixel from the centre (125, 125), every pixel read, so the frame holds it all.
local RINGS = {
    [1] = { file = "frame1.png", hole = 0.314, outer = 0.509 },  -- dark iron, dragons (hole 78.5 px, edge 127.35)
    [2] = { file = "frame2.png", hole = 0.342, outer = 0.457 },  -- plain silver (85.5, 114.28)
    [8] = { file = "frame8.png", hole = 0.284, outer = 0.490 },  -- spiked dark (71, 122.43)
    [10] = { file = "frame10.png", hole = 0.354, outer = 0.495 }, -- cyan tech (88.5, 123.82)
}
-- The hot ring (Media/HotRing.tga, ours, tools/make_hotring.py): a white band from HOT_INNER to HOT_OUTER of its
-- width from the centre, tinted red and laid OVER the ring art while the player stands in a hot cell, so the
-- cue is the same plain red whatever the art's colours (a tint of the art itself turns cyan or iron dark, not
-- red). With the art: its inner edge on the art's hole. Without: its outer edge on the plain rim's.
local HOT_RING = "HotRing.tga"
local HOT_INNER, HOT_OUTER = 0.425, 0.5
local HOT_COLOR = { 1, 0.1, 0.1, 0.9 }
-- The grids (Media/radarGridsN.png, 250 x 250): both discs measure the same, radius 98.5 to 102 px.
local GRIDS = { [1] = "radarGrids1.png", [2] = "radarGrids2.png" } -- green, blue
local GRID_DISC = 0.40    -- the disc's radius as a share of the width (100 of 250 px)
local DIM = 0.3           -- the radar's alpha with no position or no data for the map
local RIM_COLOR, RIM_HOT = { 0.1, 0.1, 0.1, 1 }, { 0.9, 0.1, 0.1, 1 }
local NO_POSITION = "no position here"

R.RADIUS, R.BORDER, R.POINTER, R.MAX_BLIPS, R.TICK, R.DIM = RADIUS, BORDER, POINTER, MAX_BLIPS, TICK, DIM
R.LIMIT = RADIUS - POINTER / 2 -- the rim clamp: the marker's whole circle stays inside the field

local isSecret = ns.IsSecret

-- ============================ the picture's maths (etn1) ============================

--- Screen offsets from the centre for a spot dx yards north and dy yards west of the player, for a player facing
--- `facing` (radians from north, turning left; nil = north), at `scale` pixels per yard. THE FACING IS UP: a spot
--- ahead is above the centre, one to the left is left of it. The TRUE spot, however far.
function R.ToPlane(dx, dy, facing, scale)
    local c, s = math.cos(facing or 0), math.sin(facing or 0)
    local ahead, left = dx * c + dy * s, dy * c - dx * s
    return -left * scale, ahead * scale
end

--- The same spot held inside the rim: a spot past it keeps its direction at the border.
function R.ToScreen(dx, dy, facing, scale, limit)
    local x, y = R.ToPlane(dx, dy, facing, scale)
    limit = limit or R.LIMIT
    local r = sqrt(x * x + y * y)
    if r > limit then x, y = x * limit / r, y * limit / r end
    return x, y
end

--- Yards north and west from the player (map fractions px, py) to the middle of 0-based cell (ix, iy) on a map
--- W x H yards. Map fractions grow east (x) and south (y).
function R.CellVector(px, py, ix, iy, W, H)
    return (py - ns.CellCentre(iy)) * H, (px - ns.CellCentre(ix)) * W
end

--- The hot cells of a map's grid: every cell at or above the threshold (q / 100), as { ix, iy } pairs.
function R.HotCells(md, hot)
    local list = {}
    for ix, col in pairs(md) do
        for iy, q in pairs(col) do
            if q / 100 >= hot then list[#list + 1] = { ix, iy } end
        end
    end
    return list
end

--- The nearest hot cell: its distance in yards and its vector (yards north, yards west), or nil.
function R.NearestHot(list, px, py, W, H)
    local best, bx, by
    for i = 1, #list do
        local dx, dy = R.CellVector(px, py, list[i][1], list[i][2], W, H)
        local d = dx * dx + dy * dy
        if not best or d < best then best, bx, by = d, dx, dy end
    end
    if best then return sqrt(best), bx, by end
end

-- ============================ client reads (mnc3, adapted) ============================

--- The player's map and map position: its state, and when plain the uiMapID and the fractions x, y.
local function mapRead()
    local M = _G.C_Map
    if type(M) ~= "table" or type(M.GetBestMapForUnit) ~= "function" or type(M.GetPlayerMapPosition) ~= "function" then
        return "n/a"
    end
    local ok, mapID = pcall(M.GetBestMapForUnit, "player")
    if not ok then return "error" end
    if isSecret(mapID) then return "hidden" end
    if type(mapID) ~= "number" then return "nil" end
    local okPos, pos = pcall(M.GetPlayerMapPosition, mapID, "player")
    if not okPos then return "error" end
    if isSecret(pos) then return "hidden" end
    if pos == nil then return "nil" end
    local okXY, x, y = pcall(function() return pos:GetXY() end)
    if not okXY then return "error" end
    if isSecret(x) or isSecret(y) then return "hidden" end
    if type(x) ~= "number" or type(y) ~= "number" then return "nil" end
    return "plain", mapID, x, y
end
R.MapRead = mapRead

--- GetPlayerFacing: its state, and when plain the radians (from north, turning left).
local function facingRead()
    local f = _G.GetPlayerFacing
    if type(f) ~= "function" then return "n/a" end
    local ok, v = pcall(f)
    if not ok then return "error" end
    if isSecret(v) then return "hidden" end
    if type(v) ~= "number" then return "nil" end
    return "plain", v
end
R.FacingRead = facingRead

--- One world position (x north, y west, yards) of a map fraction, or nil.
local function worldAt(M, map, fx, fy)
    local okV, v = pcall(_G.CreateVector2D, fx, fy)
    if not okV or v == nil then return nil end
    local ok, continent, world = pcall(M.GetWorldPosFromMapPos, map, v)
    if not ok or isSecret(continent) or isSecret(world) or world == nil then return nil end
    local okXY, x, y = pcall(function() return world:GetXY() end)
    if not okXY or isSecret(x) or isSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end

--- A map's size in yards (W east-west, H north-south), or nil. From the world positions of its north-west and
--- south-east corners (world X points north, world Y points west); C_Map.GetMapWorldSize where those give
--- nothing. Cached per map once read plainly.
local sizeCache = {}
local function mapYards(map)
    local c = sizeCache[map]
    if c then return c[1], c[2] end
    local M = _G.C_Map
    if type(M) ~= "table" then return nil end
    local W, H
    if type(M.GetWorldPosFromMapPos) == "function" and type(_G.CreateVector2D) == "function" then
        local top, left = worldAt(M, map, 0, 0)
        local bottom, right = worldAt(M, map, 1, 1)
        if top and bottom then W, H = left - right, top - bottom end
    end
    if not (W and H and W > 0 and H > 0) and type(M.GetMapWorldSize) == "function" then
        local ok, w, h = pcall(M.GetMapWorldSize, map)
        if ok and not isSecret(w) and not isSecret(h) and type(w) == "number" and type(h) == "number" then
            W, H = w, h
        end
    end
    if not (W and H and W > 0 and H > 0) then return nil end
    sizeCache[map] = { W, H }
    return W, H
end
ns.MapYards = mapYards

local function altDown()
    local f = _G.IsAltKeyDown
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f)
    return ok and not isSecret(v) and v == true
end

-- ============================ drawing helpers (etn1) ============================

--- A circle mask on `parent`, laid over `over` when one is given; nil where the client has no mask textures.
local function circleMask(parent, over)
    if type(parent.CreateMaskTexture) ~= "function" then return nil end
    local ok, mask = pcall(parent.CreateMaskTexture, parent)
    if not ok or not mask then return nil end
    pcall(mask.SetTexture, mask, CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if over then pcall(mask.SetAllPoints, mask, over) end
    return mask
end

local function maskWith(texture, mask)
    if mask then pcall(texture.AddMaskTexture, texture, mask) end
end

--- Put a piece (x, y) from the centre. Touched only on a change.
local function placeAt(frame, e, x, y)
    if x ~= e.lastX or y ~= e.lastY or not e.placed then
        e.placed, e.lastX, e.lastY = true, x, y
        e.tex:ClearAllPoints()
        e.tex:SetPoint("CENTER", frame, "CENTER", x, y)
    end
end

-- ============================ state ============================

local frame
local blips = {}      -- { tex, dx, dy, lastX, lastY, placed, size }
local nBlips = 0      -- blips in use this paint
local pointer         -- { tex, dx, dy, ... } the nearest hot cell
local hotList, hotKey -- the current map's hot cells and what they were built for
local facing = 0      -- the last plain facing
local placedFacing    -- the facing the pieces were last placed for
local rimHot          -- the rim's current tint
local sinceTick = 0

local function setRim(hot)
    if not frame or rimHot == hot then return end
    rimHot = hot
    local c = hot and RIM_HOT or RIM_COLOR
    frame.rim:SetColorTexture(c[1], c[2], c[3], c[4])
    frame.hot:SetShown(hot)
end

local function clearPieces()
    for i = 1, nBlips do blips[i].tex:Hide() end
    nBlips = 0
    if pointer then pointer.tex:Hide(); pointer.dx = nil end
    if frame then frame.dist:SetText("") end
end

--- The radar's alpha: DIM, or full. Touched only on a change.
local dimmed
local function dim(on)
    if dimmed == on then return end
    dimmed = on
    frame:SetAlpha(on and DIM or 1)
end

--- The centre note ("no data yet", "no data for this map", "no position here"), or nil for the picture.
--- `dimOn`: the radar dims behind the note (no position, no data for the map); the note keeps its own alpha.
local function note(text, dimOn)
    if not frame then return end
    dim(dimOn == true)
    if text then
        clearPieces()
        setRim(false)
        frame.note:SetText(text)
        frame.note:Show()
        frame.arrow:Hide()
    else
        frame.note:Hide()
        frame.arrow:Show()
    end
end

local function viewFacing()
    local state, f = facingRead()
    if state == "plain" then facing = f end
    return facing
end

--- Put every piece where it is for a player facing `f`: the blips at their true spots (the circle cuts them),
--- the pointer held inside the rim.
function R.Place(f)
    if not frame then return end
    local scale = RADIUS / NAGDeathRadarSettings.yards
    for i = 1, nBlips do
        local e = blips[i]
        placeAt(frame, e, R.ToPlane(e.dx, e.dy, f, scale))
    end
    if pointer and pointer.dx then
        placeAt(frame, pointer, R.ToScreen(pointer.dx, pointer.dy, f, scale))
    end
    placedFacing = f
end

local function blipAt(i)
    local e = blips[i]
    if not e then
        local t = frame:CreateTexture(nil, "ARTWORK")
        t:SetTexture(DISC)
        maskWith(t, frame.clip)
        e = { tex = t }
        blips[i] = e
    end
    return e
end

--- One paint: where the player is, the cells around, the nearest hot cell, the rim. Returns the state shown
--- ("ok" or the centre note) for the tests.
function R.Paint()
    if not frame then return end
    local s = NAGDeathRadarSettings
    if not ns.data then local why = ns.NoDataText(); note(why); return why end
    local state, map, px, py = mapRead()
    if state ~= "plain" then note(NO_POSITION, true); return NO_POSITION end
    local md = ns.MapData(map)
    if not md then note(ns.NO_MAP_DATA, true); return ns.NO_MAP_DATA end
    local W, H = mapYards(map)
    if not W then note(NO_POSITION, true); return NO_POSITION end
    note(nil)
    local GRID = ns.GRID
    local ix, iy = ns.CellIndex(px), ns.CellIndex(py)
    local here = ix and iy and ns.Q(md, ix, iy) or 0
    setRim(s.rimTint and here / 100 >= s.hot)

    -- The cells within the rim: a window of cells around the player's, then the circle.
    local cellW, cellH = W / GRID, H / GRID
    local cx = min(GRID - 1, max(0, floor(px * GRID)))
    local cy = min(GRID - 1, max(0, floor(py * GRID)))
    local rx, ry = ceil(s.yards / cellW) + 1, ceil(s.yards / cellH) + 1
    local reach = s.yards + sqrt(cellW * cellH) / 2
    local found = {}
    local y0, y1 = cy - ry, cy + ry
    for x = max(0, cx - rx), min(GRID - 1, cx + rx) do
        local col = md[x]
        if col then
            for y, q in pairs(col) do -- a column's cells, not its 100 rows: a small map's window is the whole grid
                if y >= y0 and y <= y1 and q / 100 >= s.thrLow then
                    local dx, dy = R.CellVector(px, py, x, y, W, H)
                    if dx * dx + dy * dy <= reach * reach then found[#found + 1] = { dx, dy, q } end
                end
            end
        end
    end
    if #found > MAX_BLIPS then
        table.sort(found, function(a, b) return a[3] > b[3] end)
    end
    local scale = RADIUS / s.yards
    local size = max(BLIP_MIN, sqrt(cellW * cellH) * scale * 1.15)
    local n = min(#found, MAX_BLIPS)
    for i = n + 1, nBlips do blips[i].tex:Hide() end
    for i = 1, n do
        local e, c = blipAt(i), found[i]
        e.dx, e.dy = c[1], c[2]
        if e.size ~= size then e.size = size; e.tex:SetSize(size, size) end
        local r, g, b, a = ns.Color(c[3] / 100, s)
        e.tex:SetVertexColor(r, g, b, a)
        e.tex:Show()
    end
    nBlips = n

    -- The nearest hot cell, at the rim when it is past it.
    local key = map .. ":" .. s.hot
    if hotKey ~= key then hotKey, hotList = key, R.HotCells(md, s.hot) end
    local d, hx, hy = R.NearestHot(hotList, px, py, W, H)
    if d then
        pointer.dx, pointer.dy = hx, hy
        pointer.tex:Show()
        frame.dist:SetText(here / 100 >= s.hot and "danger: you stand in a hot zone"
            or ("danger %d yd"):format(floor(d + 0.5)))
    else
        pointer.dx = nil
        pointer.tex:Hide()
        frame.dist:SetText("")
    end
    R.Place(viewFacing())
    return "ok"
end

-- ============================ the frame ============================

local function onUpdate(_, elapsed)
    sinceTick = sinceTick + (elapsed or 0)
    if sinceTick >= TICK then
        sinceTick = 0
        R.Paint()
        return
    end
    -- Between two paints the turn is followed every frame; nothing is touched unless the facing moved.
    local f = viewFacing()
    if f ~= placedFacing then R.Place(f) end
end
R.OnUpdate = onUpdate

local function savePosition()
    local s = NAGDeathRadarSettings
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local scale = frame:GetScale() -- the frame answers its centre in its own units; the place is kept in UIParent's
    if cx and cy and ux and uy then
        s.radarPos.x, s.radarPos.y = floor(cx * scale - ux + 0.5), floor(cy * scale - uy + 0.5)
    end
end

local function placeFrame(s)
    frame:SetScale(s.scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", s.radarPos.x / s.scale, s.radarPos.y / s.scale)
end

--- The mouse only while Alt is held: clicks on the world under it go through. With Alt, a left-drag moves it
--- (unless locked) and a right-click opens the settings (out of combat).
function R.UpdateMouse()
    if not frame or R.dragging then return end
    local s = NAGDeathRadarSettings
    local want = s.radar and altDown() or false
    if want ~= R.mouse then
        R.mouse = want
        frame:EnableMouse(want)
    end
end

local function stopDrag()
    if not R.dragging then return end
    R.dragging = nil
    pcall(frame.StopMovingOrSizing, frame)
    savePosition()
    placeFrame(NAGDeathRadarSettings)
    R.UpdateMouse()
end

--- The look: the ring and grid art (or none) and the frame fitted to what is drawn, so the drag box and the
--- screen clamp hold the whole ring.
function R.ApplyLook(s)
    if not frame then return end
    local ring = RINGS[s.ring] or RINGS[1]
    local artSize = (RADIUS + BORDER / 2) / ring.hole
    frame.art:SetTexture(MEDIA .. ring.file)
    frame.art:SetSize(artSize, artSize)
    frame.grid:SetTexture(MEDIA .. (GRIDS[s.grid] or GRIDS[1]))
    frame.art:SetShown(s.art)
    frame.grid:SetShown(s.art)
    local edge = s.art and artSize * ring.outer or RADIUS + BORDER
    frame:SetSize(edge * 2, edge * 2)
    local hot = s.art and (RADIUS + BORDER / 2) / HOT_INNER or (RADIUS + BORDER) / HOT_OUTER
    frame.hot:SetSize(hot, hot)
    frame.dist:ClearAllPoints()
    frame.dist:SetPoint("TOP", frame, "CENTER", 0, -edge - 2)
end

--- A modifier change or a leave hides the tooltip only when it is the radar's own, never another owner's.
local function hideTooltip()
    if ns.TooltipOwnedBy(frame) then GameTooltip:Hide() end
end

local function showTooltip()
    if not altDown() or ns.InCombat() then return end
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:AddLine("NAG Death Radar")
    GameTooltip:AddLine(ns.StatusLine(), 1, 1, 1)
    GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move" .. (NAGDeathRadarSettings.locked and " (locked: /ndr lock)" or ""), 1, 1, 1)
    GameTooltip:Show()
end

--- A region that keeps its own alpha whatever the radar's: true when the client has SetIgnoreParentAlpha.
local function ownAlpha(r)
    return type(r.SetIgnoreParentAlpha) == "function" and pcall(r.SetIgnoreParentAlpha, r, true) or false
end

--- Build the frame once.
function R.Init()
    if frame then return end
    local size = (RADIUS + BORDER) * 2
    frame = CreateFrame("Frame", "NAGDeathRadarFrame", UIParent)
    frame:Hide()
    frame:SetSize(size, size)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    -- The radar's circle: the field and every blip are cut by it.
    local clip = circleMask(frame)
    if clip then
        clip:SetSize(RADIUS * 2, RADIUS * 2)
        clip:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    frame.clip = clip
    -- The plain ring: a disc RADIUS + BORDER wide under the field, cut round by its own circle.
    local rim = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    rim:SetSize(size, size)
    rim:SetPoint("CENTER", frame, "CENTER", 0, 0)
    rim:SetColorTexture(RIM_COLOR[1], RIM_COLOR[2], RIM_COLOR[3], RIM_COLOR[4])
    maskWith(rim, circleMask(frame, rim))
    frame.rim = rim
    local field = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    field:SetSize(RADIUS * 2, RADIUS * 2)
    field:SetPoint("CENTER", frame, "CENTER", 0, 0)
    field:SetColorTexture(0, 0, 0, 0.5)
    maskWith(field, clip)
    frame.field = field
    local grid = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    grid:SetSize(RADIUS / GRID_DISC, RADIUS / GRID_DISC)
    grid:SetPoint("CENTER", frame, "CENTER", 0, 0)
    grid:SetAlpha(0.8)
    maskWith(grid, clip)
    frame.grid = grid
    -- The ring art over the rim; its hole just inside the plain ring (R.ApplyLook sets the file and the size).
    local art = frame:CreateTexture(nil, "OVERLAY", nil, 0)
    art:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.art = art
    -- The hot ring over the art (R.ApplyLook sizes it, setRim shows it).
    local hotRing = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    hotRing:SetPoint("CENTER", frame, "CENTER", 0, 0)
    hotRing:SetTexture(MEDIA .. HOT_RING)
    hotRing:SetVertexColor(HOT_COLOR[1], HOT_COLOR[2], HOT_COLOR[3], HOT_COLOR[4])
    hotRing:Hide()
    frame.hot = hotRing
    -- The player: the facing is up, so the arrow never turns.
    local arrow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    arrow:SetTexture(ARROW)
    frame.arrow = arrow
    -- The nearest hot cell's marker: a red disc with a dark edge.
    local mark = frame:CreateTexture(nil, "OVERLAY", nil, 3)
    mark:SetSize(POINTER, POINTER)
    mark:SetTexture(DISC)
    mark:SetVertexColor(1, 0.15, 0.1, 1)
    mark:Hide()
    pointer = { tex = mark }
    -- The texts: the centre note and the distance line under the ring.
    local noteText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    noteText:SetWidth(RADIUS * 2 - 8)
    ownAlpha(noteText) -- readable while the radar is dimmed
    noteText:Hide()
    frame.note = noteText
    local dist = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dist:SetText("")
    frame.dist = dist

    frame:SetScript("OnDragStart", function()
        if NAGDeathRadarSettings.locked or not altDown() then return end
        frame:StartMoving()
        R.dragging = true
    end)
    frame:SetScript("OnDragStop", stopDrag)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and altDown() and not ns.InCombat() and ns.OpenPanel then ns.OpenPanel() end
    end)
    frame:SetScript("OnEnter", showTooltip)
    frame:SetScript("OnLeave", hideTooltip)
    frame:SetScript("OnEvent", function(_, event)
        if event == "MODIFIER_STATE_CHANGED" then
            if R.dragging and not altDown() then stopDrag() end
            if not altDown() then hideTooltip() end
            R.UpdateMouse()
        end
    end)
    frame:RegisterEvent("MODIFIER_STATE_CHANGED")
    -- After the drag scripts: setting a mouse script turns the frame's mouse on.
    frame:EnableMouse(false)
    R.mouse = false
    ns.RadarFrame = frame
end

--- Apply the settings: size, place, shown, and the OnUpdate only while shown with data.
function R.Refresh(s)
    if not frame then return end
    if R.dragging then stopDrag() end
    placeFrame(s)
    R.ApplyLook(s)
    hotKey = nil
    frame:SetShown(s.radar)
    local run = s.radar and ns.data ~= nil
    frame:SetScript("OnUpdate", run and onUpdate or nil)
    if not ns.data then
        note(ns.NoDataText()) -- full alpha: nothing to dim for, the note is the whole radar
    elseif run then
        sinceTick = 0
        R.Paint()
    end
    R.UpdateMouse()
end

-- For the tests.
function R.BlipCount() return nBlips end
function R.Pointer() return pointer end
function R.Blip(i) return blips[i] end
function R.RimHot() return rimHot == true end
