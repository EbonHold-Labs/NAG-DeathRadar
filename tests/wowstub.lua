-- A WoW API stub for headless runs (lua5.1 / luajit). STRICT: a widget answers only the methods listed here
-- for its kind (frame, check button, texture, mask, font string); calling or reading any other capitalised
-- method raises, so a misspelt or missing API fails a test instead of passing silently. Names the addon PROBES
-- with type(x.Name) (a method some clients lack) read as nil when the stub does not define them.
-- S.reset() installs fresh globals; tests drive the player through S.player and read back what was drawn.
--
-- License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/legalcode)

local S = {}

local PROBED = { CreateMaskTexture = true, GetCanvas = true, GetCanvasContainer = true, GetCanvasZoomPercent = true,
    GetScaleForMinZoom = true, GetScaleForMaxZoom = true, WorldMapTrackingOptionsButton = true,
    GetPinFrameLevelsManager = true, OnMapChanged = true, OnCanvasScaleChanged = true }

local REGION, FRAME, CHECK, BUTTON, SLIDER, TEXTURE, MASK, FONT, TOOLTIP = {}, {}, {}, {}, {}, {}, {}, {}, {}

local function new(kind, parent)
    local o = { _kind = kind, _shown = true, _scripts = {}, _parent = parent, _w = nil, _h = nil }
    S.objects[#S.objects + 1] = o
    return setmetatable(o, { __index = function(_, k)
        local m = kind[k] or REGION[k]
        if m then return m end
        if type(k) ~= "string" or not k:match("^%u") or PROBED[k] then return nil end
        error("strict stub: unknown method " .. k, 2)
    end })
end
S.new = new

-- Regions (every kind).
-- _point is the last SetPoint; _points holds every anchor set since the last ClearAllPoints, by its point.
function REGION:SetPoint(...)
    self._point = { ... }
    self._points = self._points or {}
    self._points[(...)] = self._point
    S.setPoints = S.setPoints + 1
end
function REGION:ClearAllPoints() self._point, self._points = nil, nil end
function REGION:SetAllPoints(rel) self._point = { "ALL", rel } end
function REGION:SetSize(w, h) self._w, self._h = w, h end
function REGION:SetWidth(w) self._w = w end
function REGION:GetWidth() return self._w or (self._point and self._point[1] == "ALL" and self._point[2] and self._point[2]:GetWidth()) or 1000 end
function REGION:GetHeight() return self._h or (self._point and self._point[1] == "ALL" and self._point[2] and self._point[2]:GetHeight()) or 700 end
function REGION:Show() self._shown = true end
function REGION:Hide() self._shown = false end
function REGION:SetShown(v) self._shown = v and true or false end
function REGION:IsShown() return self._shown end
function REGION:SetAlpha(a) self._alpha = a end

-- Frames.
-- As the client does: a mouse or drag script turns the frame's mouse on.
local MOUSE_SCRIPTS = { OnDragStart = true, OnDragStop = true, OnMouseDown = true, OnMouseUp = true, OnEnter = true,
    OnLeave = true }
function FRAME:SetScript(k, f)
    self._scripts[k] = f
    if f and MOUSE_SCRIPTS[k] then self._mouse = true end
end
function FRAME:GetScript(k) return self._scripts[k] end
function FRAME:HookScript(k, f)
    local old = self._scripts[k]
    self._scripts[k] = function(...) if old then old(...) end f(...) end
end
function FRAME:RegisterEvent(e)
    S.events[e] = S.events[e] or {}
    table.insert(S.events[e], self)
end
function FRAME:CreateTexture(_, layer) local t = new(TEXTURE, self); t._layer = layer; return t end
function FRAME:CreateMaskTexture() return new(MASK, self) end
function FRAME:CreateFontString() return new(FONT, self) end
function FRAME:SetFrameLevel(l) self._level = l end
function FRAME:GetFrameLevel() return self._level or 1 end
function FRAME:SetScale(s) self._scale = s end
function FRAME:GetScale() return self._scale or 1 end
function FRAME:GetCenter() return self._cx or 500, self._cy or 350 end
function FRAME:SetClampedToScreen() end
function FRAME:SetMovable(v) self._movable = v end
function FRAME:EnableMouse(v) self._mouse = v and true or false end
function FRAME:RegisterForDrag() end
function FRAME:StartMoving() self._moving = true end
function FRAME:StopMovingOrSizing() self._moving = false end
for k, v in pairs(FRAME) do CHECK[k] = v; BUTTON[k] = v; SLIDER[k] = v end
function SLIDER:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function SLIDER:SetValueStep(v) self._step = v end
function SLIDER:SetObeyStepOnDrag(v) self._obey = v end
-- As the client does: a new value fires OnValueChanged (userInput false when set by code).
function SLIDER:SetValue(v)
    local changed = v ~= self._value
    self._value = v
    local f = self._scripts.OnValueChanged
    if changed and f then f(self, v, false) end
end
function SLIDER:GetValue() return self._value end
function BUTTON:SetText(t) self._text = t end
function BUTTON:GetText() return self._text end
function CHECK:SetChecked(v) self._checked = v and true or false end
function CHECK:GetChecked() return self._checked end

-- Textures and masks.
function TEXTURE:SetTexture(path) self._texture = path end
function TEXTURE:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function TEXTURE:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
function TEXTURE:AddMaskTexture(m) self._masks = (self._masks or 0) + 1; self._mask = m end
function TEXTURE:SetSnapToPixelGrid(v) self._snap = v end
function TEXTURE:SetTexelSnappingBias(v) self._texelBias = v end
function MASK:SetTexture(path) self._texture = path end

-- Font strings.
function FONT:SetText(t) self._text = t end
function FONT:GetText() return self._text end
function FONT:SetIgnoreParentAlpha(v) self._ownAlpha = v end

-- The game tooltip.
function TOOLTIP:SetOwner(owner) self._owner = owner; self._lines = {} end
function TOOLTIP:AddLine(t) table.insert(self._lines, t) end
function TOOLTIP:GetOwner() return self._owner end
function TOOLTIP:IsOwned(f) return self._owner == f end


S.KINDS = { REGION = REGION, FRAME = FRAME, TEXTURE = TEXTURE, FONT = FONT }

local function vector(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

S.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

--- Fresh state and globals. opts.settingsApi = false drops Settings; opts.interfaceOptions = true adds the old
--- InterfaceOptions_AddCategory; opts.canvas = false gives a WorldMapFrame without GetCanvas; opts.worldSize
--- adds C_Map.GetMapWorldSize; opts.secrets = true defines issecretvalue.
function S.reset(opts)
    opts = opts or {}
    S.objects, S.events, S.prints, S.setPoints = {}, {}, {}, 0
    S.mapID, S.zoom, S.worldBounds, S.worldSize = 0, 1, {}, {}
    S.minScale, S.maxScale = 0.5, 2 -- the open map's zoom scales; equal on a map that cannot zoom
    S.player = { map = nil, x = nil, y = nil, facing = 0, alt = false, combat = false }
    S.panels, S.opened = {}, {}
    S.sliderTemplate = opts.sliderTemplate ~= false -- false: a client without UISliderTemplateWithLabels
    -- opts.menu: the Menu API (Menu.ModifyMenu, MenuUtil.CreateCheckbox); S.modified records each ModifyMenu.
    S.modified = {}
    if opts.menu then
        _G.Menu = { ModifyMenu = function(tag, cb) table.insert(S.modified, { tag = tag, callback = cb }) end }
        _G.MenuUtil = { CreateCheckbox = function(text, isSelected, setSelected)
            return { kind = "checkbox", text = text, isSelected = isSelected, setSelected = setSelected }
        end }
    else
        _G.Menu, _G.MenuUtil = nil, nil
    end

    _G.NAGDeathData, _G.NAGDeathRadarSettings, _G.NAGDeathRadarMapLayer = nil, nil, nil
    _G.UIParent = new(FRAME)
    _G.GameTooltip = new(TOOLTIP)
    _G.GameTooltip._shown, _G.GameTooltip._lines = false, {}
    _G.SlashCmdList = {}
    _G.print = function(...) table.insert(S.prints, table.concat({ ... }, " ")) end
    _G.date = os.date
    _G.CreateFrame = function(kind, name, parent, template)
        if kind == "Slider" then
            if template ~= "UISliderTemplateWithLabels" or not S.sliderTemplate then
                error("CreateFrame: Couldn't find inherited node \"" .. tostring(template) .. "\"")
            end
            local sl = new(SLIDER, parent)
            sl.Text, sl.Low, sl.High = new(FONT, sl), new(FONT, sl), new(FONT, sl)
            S.lastTemplate = template
            return sl
        end
        local o = new(kind == "CheckButton" and CHECK or kind == "Button" and BUTTON or FRAME, parent)
        o._template, o._name = template, name
        if name then _G[name] = o end -- as the client does: a named frame is a global
        return o
    end
    _G.hooksecurefunc = function(t, name, f)
        local old = t[name]
        t[name] = function(...) old(...); f(...) end
    end
    _G.InCombatLockdown = function() return S.player.combat end
    _G.GetPlayerFacing = function() return S.player.facing end
    _G.IsAltKeyDown = function() return S.player.alt end
    _G.CreateVector2D = vector
    _G.issecretvalue = opts.secrets and function(v) return v == S.SECRET end or nil

    local W = new(FRAME)
    local canvas = new(FRAME, W)
    local container = new(FRAME, W)
    canvas._level, canvas._w, canvas._h = 3, 1000, 700
    if opts.canvas ~= false then
        W.GetCanvas = function() return canvas end
        W.GetCanvasContainer = function() return container end
        -- PercentageBetween(scale, min, max) answers 0 when min == max, whatever the scale.
        W.GetCanvasZoomPercent = function() return S.minScale == S.maxScale and 0 or S.zoom end
        W.GetScaleForMinZoom = function() return S.minScale end
        W.GetScaleForMaxZoom = function() return S.maxScale end
        W.GetPinFrameLevelsManager = function()
            -- As MapCanvasPinFrameLevelsManagerMixin: the topmost type starts at 2700 with a range of 20.
            return { GetValidFrameLevel = function(_, kind, index)
                if kind == "PIN_FRAME_LEVEL_TOPMOST" then return 2700 + math.max(1, math.min(index or 1, 20)) - 1 end
                return kind == "PIN_FRAME_LEVEL_MAP_EXPLORATION" and 2003 or 2000
            end }
        end
    end
    W.GetMapID = function() return S.mapID end
    if opts.filterButton then W.WorldMapTrackingOptionsButton = new(FRAME, W) end
    W.OnMapChanged = function() end
    W.OnCanvasScaleChanged = function() end
    S.canvas = canvas
    _G.WorldMapFrame = W

    _G.C_Map = {
        GetBestMapForUnit = function() return S.player.map end,
        GetPlayerMapPosition = function()
            if S.player.x == S.SECRET then return S.SECRET end
            if S.player.x then return vector(S.player.x, S.player.y) end
        end,
        -- World X points north, world Y points west. S.worldBounds[map] = { top, left, bottom, right }.
        GetWorldPosFromMapPos = function(map, v)
            local b = S.worldBounds[map]
            if b == S.SECRET then return 0, S.SECRET end
            if not b then return nil end
            local fx, fy = v:GetXY()
            return 0, vector(b[1] + (b[3] - b[1]) * fy, b[2] + (b[4] - b[2]) * fx)
        end,
    }
    if opts.worldSize then
        _G.C_Map.GetMapWorldSize = function(map)
            local s = S.worldSize[map]
            if s then return s[1], s[2] end
            return 0, 0
        end
    end

    if opts.settingsApi ~= false then
        _G.Settings = {
            RegisterCanvasLayoutCategory = function(panel, name)
                local cat = { name = name, panel = panel, GetID = function() return 77 end }
                table.insert(S.panels, cat)
                return cat
            end,
            RegisterAddOnCategory = function() end,
            OpenToCategory = function(id) table.insert(S.opened, id) end,
        }
    else
        _G.Settings = nil
    end
    _G.InterfaceOptions_AddCategory = opts.interfaceOptions and function(panel) table.insert(S.panels, panel) end or nil
    _G.InterfaceOptionsFrame_OpenToCategory = opts.interfaceOptions and function(p) table.insert(S.opened, p) end or nil
end

function S.fire(event, ...)
    for _, f in ipairs(S.events[event] or {}) do f._scripts.OnEvent(f, event, ...) end
end

--- One client frame: every shown frame's OnUpdate.
function S.frame(elapsed)
    for _, o in ipairs(S.objects) do
        local f = o._scripts and o._scripts.OnUpdate
        if f and o._shown then f(o, elapsed or 0.016) end
    end
end

--- Frames with an OnUpdate set: the addon's only tickers.
function S.liveUpdates()
    local n = 0
    for _, o in ipairs(S.objects) do
        if o._scripts and o._scripts.OnUpdate then n = n + 1 end
    end
    return n
end

return S
