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
    { "radar", "Show the radar" },
    { "overlay", "Heatmap on the world map" },
    { "locked", "Lock the radar (unlocked: Alt + drag moves it)" },
    { "rimTint", "Tint the radar's rim red while you stand in a hot zone" },
    { "art", "Show the ring and grid art (off: a plain ring)" },
}
-- Buttons that step through a setting's choices (no dropdown: its template differs between clients).
local CYCLES = {
    { "ring", "Ring" },
    { "grid", "Grid", { [1] = "green", [2] = "blue" } },
}

local ALPHA_STEPS = { 0.4, 0.6, 0.8, 1 }

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
        sl:SetWidth(200)
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
    local y = rowY - 40
    for _, line in ipairs(ns.HELP) do
        local t = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
        t:SetText(line)
        y = y - 18
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
