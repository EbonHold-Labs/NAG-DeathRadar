--- NAG Death Radar: the settings panel. Plain frames, five check boxes and two buttons that step through the
--- ring and grid art, registered with the Settings API where the client has it
--- (Settings.RegisterCanvasLayoutCategory), else with the old interface options (InterfaceOptions_AddCategory);
--- both are probed, neither is assumed. The numbers (size, range, threshold) are set with /ndr.
---
--- License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/legalcode)
--- Authors: @Rakizi, @Fonsas

local _, ns = ...

local type, ipairs, pairs, pcall = type, ipairs, pairs, pcall

local TITLE = "NAG Death Radar"
local BOXES = {
    { "radar", "Show the danger view" },
    { "overlay", "Heatmap on the world map" },
    { "locked", "Lock the circle (unlocked: Alt + drag moves it)" },
    { "rimTint", "Highlight when inside a danger area" },
    { "art", "Circle mode: ornament ring and grid art (off: the totem radar's plain look)" },
    { "worldAnchors", "Experimental camera projection (moves map pins)" },
}
-- Buttons that step through a setting's choices (no dropdown: its template differs between clients).
local CYCLES = {
    { "ring", "Ring" },
    { "grid", "Grid", { [1] = "green", [2] = "blue" } },
    { "dock", "Place", { free = "free", minimap = "minimap", totem = "totem radar" } },
}
local VIEW_MODES = { { "perspective", "Perspective" }, { "circle", "Radar" }, { "world", "World (test)" } }

local ALPHA_STEPS = { 0.4, 0.6, 0.8, 1 }
local VIEW_CONTROLS = {
    { key = "reach", label = "View range (yd)", step = 10 },
    { key = "viewWidth", label = "View width", step = 20 },
    { key = "viewHeight", label = "View height", step = 10 },
    { key = "viewScale", label = "View size", step = 0.05 },
    { key = "viewX", label = "Horizontal offset", step = 20 },
    { key = "viewY", label = "Vertical offset", step = 20 },
    { key = "viewOutline", label = "Contour strength", step = 0.1 },
    { key = "viewFill", label = "Fill strength", step = 0.1 },
}

local function viewLabel(it, value)
    local fractional=it.key=="viewScale" or it.key=="viewOutline" or it.key=="viewFill"
    return it.label .. ": " .. (fractional and ("%.2f"):format(value) or ("%.0f"):format(value))
end

--- The map opacity step after `cur`, wrapping round (the panel's button where the client has no slider).
function ns.NextStep(cur)
    for _, v in ipairs(ALPHA_STEPS) do
        if v > cur + 1e-9 then return v end
    end
    return ALPHA_STEPS[1]
end

--- The next choice after `cur` in the setting's list, wrapping round.
function ns.NextChoice(key, cur)
    local list = ns.CHOICES[key]
    for i, c in ipairs(list) do
        if c == cur then return list[i % #list + 1] end
    end
    return list[1]
end

local panel, category, registeredWith
local settingSlider -- true while the code sets the slider: its OnValueChanged then changes nothing

function ns.RefreshPanel()
    if not panel then return end
    local s = NAGDeathRadarSettings
    for key, cb in pairs(panel.boxes) do cb:SetChecked(s[key] == true) end
    for _, it in ipairs(CYCLES) do
        local v = s[it[1]]
        panel.cycles[it[1]]:SetText(("%s: %s"):format(it[2], it[3] and it[3][v] or tostring(v)))
    end
    local pct = ("Map opacity: %d%%"):format(math.floor(s.mapAlpha * 100 + 0.5))
    if panel.mapAlpha then
        settingSlider = true
        panel.mapAlpha:SetValue(s.mapAlpha)
        settingSlider = false
        panel.mapAlpha.Text:SetText(pct)
    elseif panel.mapAlphaStep then
        panel.mapAlphaStep:SetText(pct)
    end
    panel.status:SetText(ns.StatusLine())
    for _, it in ipairs(VIEW_MODES) do
        panel.modeButtons[it[1]]:SetText((s.mode == it[1] and "[x] " or "[ ] ") .. it[2])
    end
    for _, it in ipairs(VIEW_CONTROLS) do
        local slider = panel.viewSliders[it.key]
        local button = panel.viewSteps[it.key]
        if slider then
            settingSlider = true
            slider:SetValue(s[it.key])
            settingSlider = false
            slider.Text:SetText(viewLabel(it, s[it.key]))
        elseif button then button:SetText(viewLabel(it, s[it.key])) end
    end
end

function ns.BuildPanel()
    if panel then return end
    panel = CreateFrame("Frame")
    panel.name = TITLE
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText(TITLE)
    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -42)
    panel.status = status
    panel.viewSliders, panel.viewSteps = {}, {}
    panel.boxes = {}
    for i, it in ipairs(BOXES) do
        local key = it[1]
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -40 - i * 30)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(it[2])
        cb:SetScript("OnClick", function(self)
            NAGDeathRadarSettings[key] = self:GetChecked() and true or false
            ns.Apply()
        end)
        panel.boxes[key] = cb
    end
    panel.cycles = {}
    for i, it in ipairs(CYCLES) do
        local key = it[1]
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(110, 22)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 20 + (i - 1) * 120, -40 - (#BOXES + 1) * 30)
        b:SetScript("OnClick", function()
            NAGDeathRadarSettings[key] = ns.NextChoice(key, NAGDeathRadarSettings[key])
            ns.Apply()
        end)
        panel.cycles[key] = b
    end
    -- The map opacity: a slider (UISliderTemplateWithLabels, in every target client's shared templates); a
    -- client without it, found at run time, gets a button that steps through ALPHA_STEPS.
    local rowY = -40 - (#BOXES + 2) * 30 - 14
    local okSlider, sl = pcall(CreateFrame, "Slider", nil, panel, "UISliderTemplateWithLabels")
    if okSlider and type(sl) == "table" and type(sl.SetMinMaxValues) == "function" and sl.Text then
        sl:SetSize(200, 17) -- the templates set no size: without a height the bar has nothing to draw in
        sl:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, rowY)
        sl:SetMinMaxValues(0.1, 1)
        sl:SetValueStep(0.05)
        if type(sl.SetObeyStepOnDrag) == "function" then sl:SetObeyStepOnDrag(true) end
        if sl.Low then sl.Low:SetText("10%") end
        if sl.High then sl.High:SetText("100%") end
        sl:SetValue(NAGDeathRadarSettings.mapAlpha)
        sl:SetScript("OnValueChanged", function(_, value, userInput)
            if settingSlider or userInput == false then return end -- set by /ndr alpha or a refresh, not dragged
            value = math.floor(value * 20 + 0.5) / 20 -- the 0.05 steps
            local r = ns.RANGES.mapAlpha
            if value ~= value or value < r[1] or value > r[2] or value == NAGDeathRadarSettings.mapAlpha then return end
            NAGDeathRadarSettings.mapAlpha = value
            ns.Apply()
        end)
        panel.mapAlpha = sl
    else
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(160, 22)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, rowY)
        b:SetScript("OnClick", function()
            NAGDeathRadarSettings.mapAlpha = ns.NextStep(NAGDeathRadarSettings.mapAlpha)
            ns.Apply()
        end)
        panel.mapAlphaStep = b
    end
    local modeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    modeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, rowY - 28)
    modeLabel:SetText("Visualization")
    panel.modeButtons = {}
    for i, it in ipairs(VIEW_MODES) do
        local mode = it[1]
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(104, 22)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", 20 + (i - 1) * 108, rowY - 46)
        button:SetScript("OnClick", function()
            NAGDeathRadarSettings.mode = mode
            ns.Apply()
            if mode=='world' and ns.WorldView then ns.WorldView.Start() end
        end)
        panel.modeButtons[mode] = button
    end
    for i, it in ipairs(VIEW_CONTROLS) do
        local key, bounds = it.key, ns.RANGES[it.key]
        local ok, slider = pcall(CreateFrame, "Slider", nil, panel, "UISliderTemplateWithLabels")
        if ok and type(slider) == "table" and slider.Text then
            slider:SetSize(200, 17)
            slider:SetPoint("TOPLEFT", panel, "TOPLEFT", 370, -82 - (i - 1) * 54)
            slider:SetMinMaxValues(bounds[1], bounds[2])
            slider:SetValueStep(it.step)
            if type(slider.SetObeyStepOnDrag) == "function" then slider:SetObeyStepOnDrag(true) end
            if slider.Low then slider.Low:SetText(tostring(bounds[1])) end
            if slider.High then slider.High:SetText(tostring(bounds[2])) end
            slider:SetScript("OnValueChanged", function(_, v, userInput)
                if settingSlider or userInput == false or ns.IsSecret(v) or type(v) ~= "number" or v ~= v then return end
                v = math.floor(v / it.step + 0.5) * it.step
                if v < bounds[1] or v > bounds[2] or v == NAGDeathRadarSettings[key] then return end
                NAGDeathRadarSettings[key] = v
                ns.Apply()
            end)
            panel.viewSliders[key] = slider
        else
            local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            button:SetSize(220, 22)
            button:SetPoint("TOPLEFT", panel, "TOPLEFT", 360, -72 - (i - 1) * 48)
            button:SetScript("OnClick", function()
                local v = NAGDeathRadarSettings[key] + it.step
                NAGDeathRadarSettings[key] = v > bounds[2] and bounds[1] or v
                ns.Apply()
            end)
            panel.viewSteps[key] = button
        end
    end
    local y = rowY - 80
    for _, line in ipairs({
        "Direction views are approximate and follow character heading, without moving waypoints.",
        "Hold Alt and left-drag the highlighted field to move the view.",
        "Assign Hold danger-view details in WoW Key Bindings > NAG Death Radar.",
        "Hold that key for stronger contours and approximate boundary distance.",
        "/ndr preview on: synthetic test areas; /ndr preview off: live data.",
        "Camera projection is opt-in: it moves map pins and has unverified terrain height.",
        "An approximate direction view takes over during camera loss or combat. Alt-drag moves it.",
    }) do
        local t = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
        t:SetWidth(320)
        t:SetHeight(28)
        t:SetJustifyH("LEFT")
        t:SetText(line)
        y = y - 32
    end
    panel:SetScript("OnShow", ns.RefreshPanel)

    local S = _G.Settings
    if type(S) == "table" and type(S.RegisterCanvasLayoutCategory) == "function"
        and type(S.RegisterAddOnCategory) == "function" then
        local ok, cat = pcall(S.RegisterCanvasLayoutCategory, panel, TITLE)
        if ok and cat then
            pcall(S.RegisterAddOnCategory, cat)
            category, registeredWith = cat, "settings"
        end
    elseif type(_G.InterfaceOptions_AddCategory) == "function" then
        if pcall(_G.InterfaceOptions_AddCategory, panel) then registeredWith = "interface options" end
    end
    ns.RefreshPanel()
end

function ns.OpenPanel()
    if ns.InCombat() then return ns.Say("the settings open out of combat") end
    local S = _G.Settings
    if category and type(S) == "table" and type(S.OpenToCategory) == "function" then
        local okID, id = pcall(category.GetID, category)
        pcall(S.OpenToCategory, okID and id or category)
    elseif panel and type(_G.InterfaceOptionsFrame_OpenToCategory) == "function" then
        _G.InterfaceOptionsFrame_OpenToCategory(panel)
        _G.InterfaceOptionsFrame_OpenToCategory(panel) -- the old panel needs two calls on its first open
    end
end

--- For the tests: how the panel was registered.
function ns.PanelRegistration()
    return registeredWith
end

-- A snapshot on demand, with ordinary EditBox selection/copy. No saved report,
-- timer, waypoint changes or camera changes. Reopening takes a fresh snapshot.
local probeWindow
function ns.OpenProjectionProbe()
    if ns.InCombat() then return ns.Say("the probe opens out of combat") end
    local report = ns.ProjectionReport()
    if not probeWindow then
        local f = CreateFrame("Frame", "NAGDeathRadarProbe", UIParent)
        f:SetSize(640, 480)
        f:SetPoint("CENTER", UIParent, "CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetColorTexture(0.035, 0.035, 0.045, 0.98)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
        title:SetText("NAG Death Radar: projection probe")
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
        hint:SetText("Ctrl+A, Ctrl+C to copy the full report. Paste it into Codex. Esc closes this window.")
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -64)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 48)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(0)
        edit:SetFontObject(GameFontHighlightSmall)
        edit:SetWidth(580)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(100, 24)
        close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
        close:SetText("Close")
        close:SetScript("OnClick", function() f:Hide() end)
        f:SetScript("OnHide", function() edit:ClearFocus() end)
        f.edit, f.scroll = edit, scroll
        probeWindow = f
    end
    local _, breaks = report:gsub("\n", "")
    probeWindow.edit:SetHeight((breaks + 2) * 16)
    probeWindow.edit:SetText(report)
    probeWindow:Show()
    -- Include wrapped lines, not only explicit newlines, in the scroll extent.
    probeWindow.edit:SetHeight(math.max(breaks + 2, probeWindow.edit:GetNumLines() + 2) * 16)
    probeWindow.scroll:SetVerticalScroll(0)
    probeWindow.edit:SetCursorPosition(0)
    probeWindow.edit:SetFocus()
    probeWindow.edit:HighlightText()
end
