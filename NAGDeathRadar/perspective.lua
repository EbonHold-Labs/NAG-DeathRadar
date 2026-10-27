-- Character-heading illustration, deliberately independent of the gameplay
-- camera and terrain. No Journey code/art, camera setters, or waypoint writes.
-- License: CC BY-NC 4.0
local _, ns = ...
local P = { detail = false, preview = false, MAX_LINES = 3000, MAX_TRIANGLES = 2500 }
ns.Perspective = P
table.insert(ns.modules, P)
local frame, driver, statusText, label, tint, mover
local lines, triangles, usedLines, usedTriangles = {}, {}, 0, 0
local cachedRuns, cachedN, prepared, previewAnchor
local elapsedSince = 0
local suspended = false
local TICK = 1/60
local lastContext

local function secret(v)
    local ok, hidden = pcall(ns.IsSecret, v)
    return not ok or hidden == true
end
local function number(v, lo, hi)
    return not secret(v) and type(v) == 'number' and v == v
        and v ~= math.huge and v ~= -math.huge and v >= lo and v <= hi
end
local function enabled()
    local s = NAGDeathRadarSettings
    return s and s.radar and (s.mode == 'perspective' or (s.mode == 'world' and P.fallback~=nil))
end
local function altDown()
    if type(_G.IsAltKeyDown)~='function' then return false end
    local ok,on=pcall(_G.IsAltKeyDown)
    return ok and not secret(on) and on==true
end
local function placeMover(s)
    mover:SetSize(s.viewWidth,s.viewHeight); mover:SetScale(s.viewScale)
    mover:ClearAllPoints(); mover:SetPoint('BOTTOM',UIParent,'CENTER',s.viewX/s.viewScale,s.viewY/s.viewScale)
end
local function stopDrag()
    if not P.dragging then return end
    P.dragging=false
    mover:StopMovingOrSizing()
    local cx,cy=mover:GetCenter()
    local ux,uy=UIParent:GetCenter()
    local s=NAGDeathRadarSettings
    if number(cx,-1e7,1e7) and number(cy,-1e7,1e7) and number(ux,-1e7,1e7) and number(uy,-1e7,1e7) then
        local x=cx*s.viewScale-ux
        local y=(cy-s.viewHeight/2)*s.viewScale-uy
        s.viewX=math.max(ns.RANGES.viewX[1],math.min(ns.RANGES.viewX[2],math.floor(x+.5)))
        s.viewY=math.max(ns.RANGES.viewY[1],math.min(ns.RANGES.viewY[2],math.floor(y+.5)))
    end
    placeMover(s)
    if ns.RefreshPanel then ns.RefreshPanel() end
end
function P.UpdateMover()
    if not mover then return end
    local show=enabled() and not suspended and altDown()
    if not show then stopDrag() end
    if P.moverShown~=show then
        P.moverShown=show
        mover:EnableMouse(show); mover:SetShown(show)
        -- Recover a missed modifier release, including without data.
        mover:SetScript('OnUpdate',show and P.UpdateMover or nil)
    end
end
local function clear()
    for i=1,usedLines do lines[i]:Hide() end
    for i=1,usedTriangles do triangles[i]:Hide() end
    usedLines, usedTriangles = 0, 0
    if frame then
        tint:Hide()
        statusText:SetText(''); label:SetText(''); frame:Hide()
    end
end
local function note(state, text)
    clear()
    P.state, P.lastModel = state, nil
    if frame and enabled() and text then
        statusText:SetText(text); label:SetText(P.fallback and (P.fallback.replay and 'REPLAY - APPROXIMATE DIRECTION VIEW' or 'APPROXIMATE DIRECTION VIEW')
            or (P.preview and 'SYNTHETIC PREVIEW' or ''))
        frame:Show()
    end
    return state
end
local function context()
    local ok, state, map, px, py = pcall(ns.Radar.MapRead)
    if not ok or secret(state) or state ~= 'plain' or not number(map,1,1e7)
        or map ~= math.floor(map) or not number(px,0,1) or not number(py,0,1) then return end
    local good, headingState, facing = pcall(ns.Radar.FacingRead)
    if not good or secret(headingState) or headingState ~= 'plain' or not number(facing,-1e7,1e7) then return end
    local sized, W, H = pcall(ns.MapYards,map)
    if not sized or not number(W,1,1e7) or not number(H,1,1e7) then return end
    return map, {px=px,py=py,W=W,H=H,facing=facing}
end

-- Frozen map-relative synthetic patches. Movement/turns change the view, never
-- move the patches. Use a 600-yard local map solely for preview precision.
local function seedPreview(map,v)
    local runs, n = {}, 200
    local c,s = math.cos(v.facing),math.sin(v.facing)
    for y=1,n do
        local start
        for x=1,n+1 do
            local north,east=(.5-(y-.5)/n)*600,((x-.5)/n-.5)*600
            local forward,right=north*c-east*s,north*s+east*c
            local hot=x<=n and ((forward>=60 and forward<=95 and right>=-50 and right<=-12)
                or (forward>=110 and forward<=145 and right>=25 and right<=65)
                or (forward>=100 and forward<=135 and right>=-35 and right<=0))
            if hot and not start then start=x end
            if not hot and start then runs[#runs+1]={x0=start,x1=x-1,y=y,step=1000}; start=nil end
        end
    end
    previewAnchor={map=map,px=v.px,py=v.py,W=v.W,H=v.H,p=ns.PerspectiveGeometry.Build(runs,n)}
end
local function previewModel(map,v)
    if previewAnchor and previewAnchor.map ~= map then
        P.preview=false; previewAnchor=nil
        return nil,'preview-ended'
    end
    if not previewAnchor then seedPreview(map,v) end
    local a=previewAnchor
    local x,y=.5+(v.px-a.px)*a.W/600,.5+(v.py-a.py)*a.H/600
    if x<0 or x>1 or y<0 or y>1 then return nil,'preview-outside' end
    return a.p,{px=x,py=y,W=600,H=600,facing=v.facing}
end

local function keyDown(key)
    if type(_G.IsKeyDown) ~= 'function' then return nil end
    local ok,value=pcall(_G.IsKeyDown,key,true)
    if not ok or secret(value) or type(value)~='boolean' then return nil end
    return value
end
local function bindingDown(binding)
    if secret(binding) or type(binding)~='string' or binding=='' then return false end
    local key=binding
    for modifier,getter in pairs({SHIFT='IsShiftKeyDown',CTRL='IsControlKeyDown',ALT='IsAltKeyDown'}) do
        if key:find(modifier..'-',1,true) then
            local f=_G[getter]
            if type(f)~='function' then return nil end
            local ok,on=pcall(f)
            if not ok or secret(on) then return nil end
            if on~=true then return false end
            key=key:gsub(modifier..'%-','')
        end
    end
    return keyDown(key)
end
local function checkHold()
    if not P.detail then return end
    if type(_G.GetCurrentKeyBoardFocus)=='function' then
        local ok,focus=pcall(_G.GetCurrentKeyBoardFocus)
        if ok and not secret(focus) and focus~=nil then P.detail=false; return end
    end
    if type(_G.GetBindingKey)~='function' or type(_G.IsKeyDown)~='function' then return end
    local ok,a,b=pcall(_G.GetBindingKey,'NAGDEATHRADAR_DETAIL')
    if not ok or secret(a) or secret(b) then return end
    local first,second=bindingDown(a),bindingDown(b)
    if first==false and second==false then P.detail=false end
end
P.CheckHold=checkHold

local function validModel(m,s)
    if type(m)~='table' or type(m.strokes)~='table' or type(m.fills)~='table' then return false end
    local triangleCount=0
    for _,line in ipairs(m.strokes) do
        if type(line)~='table' or not number(line.x1,0,s.viewWidth) or not number(line.x2,0,s.viewWidth)
            or not number(line.y1,0,s.viewHeight) or not number(line.y2,0,s.viewHeight)
            or not number(line.alpha,0,1) then return false end
    end
    for _,fill in ipairs(m.fills) do
        if type(fill)~='table' or type(fill.points)~='table' or #fill.points<3 or not number(fill.alpha,0,1) then return false end
        for _,point in ipairs(fill.points) do
            if type(point)~='table' or not number(point.x,0,s.viewWidth) or not number(point.y,0,s.viewHeight) then return false end
        end
        triangleCount=triangleCount+#fill.points-2
    end
    if #m.strokes>P.MAX_LINES or triangleCount>P.MAX_TRIANGLES then return false,'complexity' end
    return true
end
local function lineAt(i)
    if not lines[i] then lines[i]=frame:CreateLine(nil,'OVERLAY') end
    return lines[i]
end
local function triangleAt(i)
    if not triangles[i] then
        local t=frame:CreateTexture(nil,'ARTWORK')
        t:SetSize(1,1); t:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',0,0)
        triangles[i]=t
    end
    return triangles[i]
end
local function triangle(t,a,b,c,alpha)
    -- UL=A, UR=B, LL=LR=C collapses the native quad to a triangle.
    t:SetVertexOffset(1,a.x,a.y-1); t:SetVertexOffset(3,b.x-1,b.y-1)
    t:SetVertexOffset(2,c.x,c.y); t:SetVertexOffset(4,c.x-1,c.y)
    t:SetColorTexture(1,.12,.06,alpha); t:Show()
end
local function draw(m,s)
    clear()
    P.lastModel=m
    local fillSupported=true
    if #m.fills>0 then
        local test=triangleAt(1)
        fillSupported=type(test.SetVertexOffset)=='function'
        if fillSupported then
            for _,fill in ipairs(m.fills) do
                local points=fill.points
                for i=2,#points-1 do
                    usedTriangles=usedTriangles+1
                    triangle(triangleAt(usedTriangles),points[1],points[i],points[i+1],math.min(1,fill.alpha*s.viewFill))
                end
            end
        else test:Hide() end
    end
    for _,stroke in ipairs(m.strokes) do
        usedLines=usedLines+1
        local l=lineAt(usedLines)
        l:SetStartPoint('BOTTOMLEFT',frame,stroke.x1,stroke.y1)
        l:SetEndPoint('BOTTOMLEFT',frame,stroke.x2,stroke.y2)
        l:SetThickness((P.detail and 2 or 1.3)*s.viewOutline)
        l:SetColorTexture(1,.24,.12,math.min(1,stroke.alpha*s.viewOutline)); l:Show()
    end
    tint:SetShown(m.inside and s.rimTint)
    local text=m.inside and (P.fallback and P.fallback.replay and 'Inside replay area' or 'In a danger area') or ''
    if P.detail and number(m.nearestDistance,0,1e8) then
        text=text..(text~='' and '  |  ' or '')..('~%d yd to nearest area boundary'):format(math.floor(m.nearestDistance+.5))
    end
    if not fillSupported then text=text..(text~='' and '  |  ' or '')..'Outlines only: fill unavailable' end
    statusText:SetText(text)
    label:SetText(P.fallback and (P.fallback.replay and 'REPLAY: MOVED MAP OUTLINE - APPROXIMATE DIRECTION VIEW'
        or 'APPROXIMATE DIRECTION VIEW - CHARACTER HEADING')
        or (P.preview and 'SYNTHETIC PREVIEW - illustrative character-heading view' or ''))
    frame:Show()
end

function P.Paint(knownMap,knownView)
    if not frame then return end
    if not enabled() then return note('disabled') end
    if suspended then return note('suspended') end
    checkHold()
    if not ns.data and not P.preview then return note('no_data',ns.NO_DATA) end
    local map,v=knownMap,knownView
    if not map then map,v=context() end
    if not map then return note('no_position','No position or heading here') end
    local p
    lastContext={map=map,px=v.px,py=v.py,facing=v.facing,W=v.W,H=v.H,detail=P.detail}
    if P.fallback then
        if map~=P.fallback.map then return note('no_map',ns.NO_MAP_DATA) end
        p=P.fallback.geometry
    elseif P.preview then
        local reason
        p,reason=previewModel(map,v)
        if not p then
            if reason=='preview-ended' then P.Refresh(NAGDeathRadarSettings); return P.state end
            return note('preview_outside','Synthetic preview: outside preview area; enable again to reset')
        end
        v=reason
    else
        local ok,runs,n=pcall(ns.Overlay.Picture,map,NAGDeathRadarSettings)
        if not ok or not runs then return note('no_map',ns.NO_MAP_DATA) end
        if runs~=cachedRuns or n~=cachedN then
            cachedRuns,cachedN=runs,n
            local built,value=pcall(ns.PerspectiveGeometry.Build,runs,n)
            prepared=built and value or nil
        end
        p=prepared
    end
    if not p or not p.valid then
        return note('complexity','Dense area: lower view range')
    end
    local s=NAGDeathRadarSettings
    local ok,m=pcall(ns.PerspectiveGeometry.Compute,p,v,{range=s.reach,width=s.viewWidth,height=s.viewHeight,detail=P.detail})
    if not ok or not m or m.status=='invalid' then return note('invalid','Danger view unavailable') end
    local valid,reason=validModel(m,s)
    if not valid then return note(reason or 'invalid',reason=='complexity' and 'Dense area: lower view range' or 'Danger view unavailable') end
    if m.status=='empty' then return note('empty',P.preview and 'SYNTHETIC PREVIEW - no preview areas ahead' or nil) end
    if type(frame.CreateLine)~='function' then return note('unsupported','Danger view unavailable: line drawing unsupported') end
    draw(m,s)
    P.state='ok'
    return P.state
end
function P.SetDetail(on)
    P.detail=on==true and (enabled() or (ns.WorldView and ns.WorldView.IsSelected())) or false
    if frame then P.Paint() end
end
_G.NAGDeathRadar_SetDetail=function(on) P.SetDetail(on) end

function P.SetPreview(on)
    P.preview=on==true and enabled() or false
    previewAnchor=nil
    if frame then P.Refresh(NAGDeathRadarSettings) end
end
local function onUpdate(_,elapsed)
    elapsedSince=elapsedSince+(elapsed or 0)
    if elapsedSince+1e-8>=TICK then
        elapsedSince=0
        local map,v=context()
        checkHold()
        local old=lastContext
        if not v or not old or old.map~=map or old.px~=v.px or old.py~=v.py
            or old.facing~=v.facing or old.W~=v.W or old.H~=v.H or old.detail~=P.detail then
            P.Paint(map,v)
        end
    end
end
function P.SetFallback(value)
    local old=P.fallback
    if old==value or (old and value and old.geometry==value.geometry and old.map==value.map and old.replay==value.replay) then return end
    P.fallback=value
    if frame then P.Refresh(NAGDeathRadarSettings) end
end
function P.Refresh(s)
    if not frame then return end
    stopDrag()
    placeMover(s)
    frame:SetSize(s.viewWidth,s.viewHeight); frame:SetScale(s.viewScale)
    frame:ClearAllPoints(); frame:SetPoint('BOTTOM',mover,'BOTTOM',0,0)
    tint:SetSize(math.min(300,s.viewWidth*.5),22)
    cachedRuns,cachedN,prepared=nil,nil,nil
    if s.mode~='world' or not s.radar then P.fallback=nil end
    if not enabled() then
        if s.mode~='world' then P.detail=false end
        P.preview,previewAnchor=false,nil
    end
    local run=enabled() and (ns.data~=nil or P.preview)
    driver:SetShown(run); driver:SetScript('OnUpdate',run and onUpdate or nil)
    elapsedSince=0;lastContext=nil
    P.UpdateMover()
    P.Paint()
end
function P.Init()
    if frame then return end
    driver=CreateFrame('Frame',nil,UIParent)
    driver:EnableMouse(false)
    mover=CreateFrame('Frame',nil,UIParent)
    mover:SetFrameStrata('MEDIUM'); mover:SetMovable(true); mover:SetClampedToScreen(true)
    mover:RegisterForDrag('LeftButton')
    local background=mover:CreateTexture(nil,'BACKGROUND')
    background:SetAllPoints(mover); background:SetColorTexture(.7,.5,.2,.12)
    local moveLabel=mover:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    moveLabel:SetPoint('CENTER',mover,'CENTER',0,0); moveLabel:SetText('Alt + left-drag: move danger view')
    mover:SetScript('OnDragStart',function()
        if not enabled() or suspended or not altDown() then return end
        mover:StartMoving(); P.dragging=true
    end)
    mover:SetScript('OnDragStop',stopDrag)
    mover:SetScript('OnMouseUp',function(_,button) if button=='LeftButton' then stopDrag() end end)
    mover:EnableMouse(false); mover:Hide()
    frame=CreateFrame('Frame','NAGDeathRadarPerspectiveFrame',UIParent)
    frame:SetFrameStrata('LOW'); frame:EnableMouse(false); frame:Hide()
    statusText=frame:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    statusText:SetPoint('TOP',frame,'BOTTOM',0,-6)
    label=frame:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    label:SetPoint('BOTTOM',frame,'TOP',0,6)
    tint=frame:CreateTexture(nil,'BACKGROUND')
    tint:SetPoint('BOTTOM',frame,'BOTTOM',0,0); tint:SetColorTexture(1,.1,.05,.13); tint:Hide()
    driver:SetScript('OnEvent',function(_,event)
        if event=='MODIFIER_STATE_CHANGED' then P.UpdateMover(); return end
        P.detail=false
        if event=='UPDATE_BINDINGS' then P.Paint(); return end
        if event=='PLAYER_LEAVING_WORLD' or event=='PLAYER_CONTROL_LOST' then suspended=true end
        if event=='PLAYER_ENTERING_WORLD' or event=='PLAYER_CONTROL_GAINED' then suspended=false end
        stopDrag(); P.UpdateMover()
        clear(); cachedRuns,cachedN,prepared=nil,nil,nil;lastContext=nil
        P.state='context_changed'; P.lastModel=nil
        -- With no data there is deliberately no ticker to restore this note.
        if not suspended and enabled() and not ns.data and not P.preview then P.Paint() end
    end)
    for _,event in ipairs({'MODIFIER_STATE_CHANGED','UPDATE_BINDINGS','PLAYER_LEAVING_WORLD','PLAYER_ENTERING_WORLD',
        'ZONE_CHANGED','ZONE_CHANGED_INDOORS','ZONE_CHANGED_NEW_AREA','PLAYER_CONTROL_LOST','PLAYER_CONTROL_GAINED'}) do
        driver:RegisterEvent(event)
    end
    P.frame,P.driver,P.statusText,P.label,P.mover=frame,driver,statusText,label,mover
    ns.PerspectiveFrame=frame
end
function P.Counts() return usedLines,usedTriangles,#lines,#triangles end
