-- Explicitly started experimental camera-following view. Uses the single public
-- user waypoint, never Journey, injected camera functions, or terrain claims.
-- No automatic restart after reload, navigation takeover, combat or control loss.
-- License: CC BY-NC 4.0
local _,ns=...
local W={state='stopped',armed=false,active=false,quadrant=0,stats={}}
ns.WorldView=W;table.insert(ns.modules,W)
local G=ns.WorldProjection
local frame,driver,status,caption
local lines,triangles,usedLines,usedTriangles={},{},0,0
local cachedRuns,cachedN,prepared
local function public(v)
    local ok,secret=pcall(ns.IsSecret,v)
    return ok and not secret
end
local function number(x,lo,hi)
    return public(x) and type(x)=='number' and x==x and x>=lo and x<=hi
end
local function read(fn,...)
    if type(fn)~='function' then error('API unavailable') end
    local ok,a,b=pcall(fn,...)
    if not ok then error(public(a) and type(a)=='string' and a or 'API call failed',0) end
    if not public(a) or not public(b) then error('API unreadable') end
    return a,b
end
function W.IsSelected()
    local s=NAGDeathRadarSettings
    return s and s.radar and s.mode=='world'
end
local function same(a,b)
    -- Native waypoint coordinates can be rounded to float32 by the client.
    return a and b and a.map==b.map and math.abs(a.x-b.x)<1e-6 and math.abs(a.y-b.y)<1e-6
end
local function snapshot()
    local M,T=_G.C_Map,_G.C_SuperTrack
    if type(M)~='table' or type(T)~='table' then error('Navigation unavailable') end
    local point=read(M.GetUserWaypoint)
    local p
    if point then
        local xy=point.position
        if not public(xy) or type(xy)~='table' or not number(point.uiMapID,1,1e7)
            or not number(xy.x,0,1) or not number(xy.y,0,1) then error('Waypoint unreadable') end
        p={map=point.uiMapID,x=xy.x,y=xy.y}
    end
    local quest,user,kind=read(T.GetSuperTrackedQuestID),read(T.IsSuperTrackingUserWaypoint),read(T.GetHighestPrioritySuperTrackingType)
    -- Forever returns nil when no quest is tracked (for example on a new character).
    if quest==nil then quest=0 end
    if not number(quest,0,1e9) or type(user)~='boolean' or (kind~=nil and not number(kind,0,100)) then error('Tracking unreadable') end
    return {point=p,quest=quest,user=user,kind=kind}
end
local function owned(s)
    return W.backup and same(s.point,W.ours) and s.user and s.kind==1 and s.quest==W.ownedQuest
end
local function waypointKind(s) return s.kind==nil or s.kind==0 or s.kind==1 end
local function release()
    if not W.backup then return true end
    if ns.InCombat() then error('Restore deferred until out of combat') end
    local s=snapshot()
    -- Never replace an external waypoint or restore an old quest over a new one.
    if same(s.point,W.ours) then
        -- A setter can throw after writing the point or clearing the quest.
        -- Only the original quest or its empty state is an attributable change.
        W.restoreTarget=owned(s) or (W.selecting and waypointKind(s)
            and (s.quest==0 or s.quest==W.backup.quest))
        W.restoreQuest=s.quest
        read(C_Map.ClearUserWaypoint)
        s=snapshot()
        if s.point then error('Waypoint restore incomplete') end
    end
    if W.restoreTarget and not s.point and s.quest==W.restoreQuest and waypointKind(s) then
        if W.backup.quest>0 then read(C_SuperTrack.SetSuperTrackedQuestID,W.backup.quest)
        else read(C_SuperTrack.SetSuperTrackedUserWaypoint,false) end
        local restored=snapshot()
        if restored.user or restored.quest~=W.backup.quest then error('Tracking restore incomplete') end
    end
    W.backup,W.ours,W.restoreTarget,W.restoreQuest,W.ownedQuest,W.selecting=nil,nil,nil,nil,nil,nil
    return true
end
local function tryRelease()
    local ok,why=pcall(release)
    W.restorePoll=not ok and .25 or nil
    W.lastRestoreError=not ok and tostring(why) or nil
    return ok
end
local function hide()
    for i=1,usedLines do lines[i]:Hide() end
    for i=1,usedTriangles do triangles[i]:Hide() end
    usedLines,usedTriangles=0,0;W.alpha=0
    if frame then frame:Hide() end
end
local MESSAGES={stopped='World view paused: /ndr world start',combat='World view paused during combat',
    navigation_changed='World view paused: navigation changed; /ndr world start to resume',
    waypoint_busy='World view paused: finish or remove your existing waypoint first',
    unavailable='World view unavailable on this client',no_position='World view: position unavailable',
    no_data=ns.NO_DATA,no_map=ns.NO_MAP_DATA,complexity='World view: dense area; lower view range',
    control='World view paused; /ndr world start to resume',error='World view paused after an API error; /ndr world start to retry',
    restoring='World view paused: waiting to restore navigation',
    shallow='World view: camera angle too shallow; tilt the camera down'}
local function captionText()
    return W.replayMode and 'REPLAY: MOVED + SCALED MAP OUTLINE - NOT REAL DANGER HERE'
        or 'EXPERIMENTAL WORLD VIEW - terrain height unverified'
end
local function fallback(on)
    if ns.Perspective and ns.Perspective.SetFallback then
        ns.Perspective.SetFallback(on and W.active and W.sourceGeometry and {
            geometry=W.sourceGeometry,map=W.sessionMap,replay=W.replayMode==true} or nil)
    end
end
local function note(reason)
    W.state=reason
    if status then
        local approximate=ns.Perspective and ns.Perspective.fallback
        local message=reason=='no_data' and ns.NoDataText() or MESSAGES[reason] or ''
        status:SetText(W.IsSelected() and not approximate and message or '')
        caption:SetText(W.IsSelected() and not approximate and W.armed and reason~='empty'
            and captionText() or '')
    end
end
local function ticker()
    if not driver then return end
    local run=W.active or W.backup~=nil or (W.alpha or 0)>0
    driver:SetScript('OnUpdate',run and function(_,dt) W.Update(dt) end or nil)
    driver:SetShown(run)
end
function W.Stop(reason,keepFallback)
    W.active=keepFallback==true and W.IsSelected() or false
    W.armed=false;W.samples=nil;W.mesh=nil;W.pose=nil;hide()
    W.pauseReason=W.active and reason or nil
    if not W.active then W.replay=nil;W.sourceGeometry=nil end
    fallback(W.active)
    local ok=tryRelease()
    note(ok and (reason or 'stopped') or 'restoring');ticker()
end
local function checkOwner(s)
    if owned(s) then return true end
    W.navigationChange=('quest %s -> %s, waypoint %s, user %s, type %s'):format(
        tostring(W.ownedQuest),tostring(s.quest),same(s.point,W.ours) and 'ours' or 'changed',
        tostring(s.user),tostring(s.kind))
    W.Stop('navigation_changed',true);return false
end
local function context()
    local state,map,x,y=ns.Radar.MapRead()
    local heading,facing=ns.Radar.FacingRead()
    if not public(state) or state~='plain' or not number(map,1,1e7) or map~=math.floor(map)
        or not number(x,0,1) or not number(y,0,1) or not public(heading) or heading~='plain'
        or not number(facing,-1e7,1e7) then return end
    local width,height=ns.MapYards(map)
    if not number(width,1,1e7) or not number(height,1,1e7) then return end
    return {map=map,px=x,py=y,W=width,H=height,facing=facing}
end
local function geometry(v)
    local runs,n=ns.Overlay.Picture(v.map,NAGDeathRadarSettings)
    if not runs then return nil,'no_map' end
    if runs~=cachedRuns or n~=cachedN then
        cachedRuns,cachedN=runs,n;prepared=ns.PerspectiveGeometry.Build(runs,n)
    end
    if not prepared or not prepared.valid then return nil,'complexity' end
    return prepared
end
-- A copied real map outline, moved/scaled only in this in-memory preview.
local function replay(p,v)
    local chosen,distance
    for _,r in ipairs(p.regions) do
        local dx=math.max(0,r.x0-v.px,v.px-r.x1)*v.W
        local dy=math.max(0,r.y0-v.py,v.py-r.y1)*v.H
        local d=dx*dx+dy*dy
        if not distance or d<distance then chosen,distance=r,d end
    end
    if not chosen then return end
    local cx,cy=(chosen.x0+chosen.x1)/2,(chosen.y0+chosen.y1)/2
    local scale=55/((chosen.x1-chosen.x0)*v.W)
    local tx,ty=v.px-math.sin(v.facing)*72/v.W,v.py-math.cos(v.facing)*72/v.H
    local function x(q)return tx+(q-cx)*scale end
    local function y(q)return ty+(q-cy)*scale end
    local q={valid=true,n=200,occupancy={},regions={{id=1,x0=x(chosen.x0),x1=x(chosen.x1),y0=y(chosen.y0),y1=y(chosen.y1)}},edges={},rects={}}
    for _,e in ipairs(p.edges) do if e.region==chosen.id then
        q.edges[#q.edges+1]={x1=x(e.x1),y1=y(e.y1),x2=x(e.x2),y2=y(e.y2),region=1}
    end end
    for _,r in ipairs(p.rects) do if r.region==chosen.id then
        q.rects[#q.rects+1]={x0=x(r.x0),x1=x(r.x1),y0=y(r.y0),y1=y(r.y1),region=1}
    end end
    return q
end
local function acquire(v)
    if W.backup then return true end
    local s=snapshot()
    if s.point or s.user or (s.kind~=nil and s.kind~=0) then W.Stop('waypoint_busy',true);return false end
    if read(C_Map.CanSetUserWaypointOnMap,v.map)~=true then W.Stop('unavailable',true);return false end
    if type(_G.UiMapPoint)~='table' or type(UiMapPoint.CreateFromCoordinates)~='function'
        or type(_G.C_Navigation)~='table' then W.Stop('unavailable',true);return false end
    W.backup=s
    return true
end
local function selectPoint(i)
    if W.ours and not checkOwner(snapshot()) then return end
    local p=W.points[i]
    W.ours={map=W.batch.map,x=p.x,y=p.y}
    W.selecting=true
    if read(C_Map.SetUserWaypoint,UiMapPoint.CreateFromCoordinates(W.ours.map,p.x,p.y))~=true then error('Waypoint rejected') end
    read(C_SuperTrack.SetSuperTrackedUserWaypoint,true)
    local s=snapshot();W.selecting=false
    -- Forever clears the quest when switching to waypoint tracking. Remember
    -- that state separately from the quest to restore when sampling stops.
    if s.quest==0 or s.quest==W.backup.quest then W.ownedQuest=s.quest end
    if not checkOwner(s) then return end
    W.index,W.age,W.settleFrames=i,0,0;W.stats.switches=W.stats.switches+1
end
local function reject(reason,search)
    W.stats.rejected=W.stats.rejected+1
    W.stats.reasons[reason]=(W.stats.reasons[reason] or 0)+1
    W.stats.lastReject=reason
    W.samples=nil;W.pose=nil;hide();W.fading=false;fallback(true)
    if search then W.quadrant=(W.quadrant+1)%G.DIRECTIONS end
    note(reason=='shallow' and 'shallow' or 'calibrating')
end
local function begin(v)
    local p,reason=geometry(v)
    if not ns.data then W.Stop('no_data');return end
    if not p then W.Stop(reason or 'no_map');return end
    if W.replayMode then
        W.replay=W.replay or replay(p,v)
        p=W.replay
        if not p then W.Stop('empty');return end
    end
    local mesh,why=G.Near(p,v,NAGDeathRadarSettings.reach)
    if not mesh then W.Stop(why);return end
    if mesh.empty then
        if W.backup then tryRelease() end
        hide();W.pose=nil;fallback(false);note('empty');W.poll=.15;return
    end
    W.sourceGeometry,W.sessionMap=p,v.map
    if not W.pose then fallback(true) end
    if not W.armed then note(W.pauseReason or 'directional');W.poll=.1;return end
    W.stats.attempts=W.stats.attempts+1
    local bounds,points=G.Anchors(v,W.quadrant)
    if not bounds then reject('map_edge',true);W.poll=.05;return end
    if not acquire(v) then return end
    W.mesh,W.bounds,W.points,W.batch,W.samples,W.batchAge=mesh,bounds,points,v,{},0
    W.sourcePoints,W.sourceGeometry={},p
    W.sessionMap=v.map
    selectPoint(1)
end
local function sample()
    local f=read(C_Navigation.GetFrame)
    if not f or read(f.IsForbidden,f)~=false then return nil,'no_frame' end
    local x,y=read(f.GetCenter,f)
    local scale=read(f.GetEffectiveScale,f)/read(UIParent.GetEffectiveScale,UIParent)
    if read(C_Navigation.HasValidScreenPosition)~=true then return nil,'invalid_position' end
    if read(C_Navigation.WasClampedToScreen)~=false then return nil,'clamped' end
    if not number(x,-1e7,1e7) or not number(y,-1e7,1e7) or not number(scale,.01,100) then return nil,'invalid_sample' end
    return {x=x*scale,y=y*scale}
end
local function draw(m)
    fallback(false)
    hide();W.alpha=1;frame:SetAlpha(1)
    if not m.inside and #m.strokes==0 and #m.fills==0 then
        hide();status:SetText('');caption:SetText('');W.state='empty';W.lastModel=m;W.fading=false;return
    end
    local detail=ns.Perspective and ns.Perspective.detail
    for _,s in ipairs(m.strokes) do
        usedLines=usedLines+1
        local l=lines[usedLines]
        if not l then l=frame:CreateLine(nil,'OVERLAY');lines[usedLines]=l end
        l:SetStartPoint('BOTTOMLEFT',frame,s.x1,s.y1);l:SetEndPoint('BOTTOMLEFT',frame,s.x2,s.y2)
        l:SetThickness((detail and 2.4 or 1.5)*NAGDeathRadarSettings.viewOutline)
        l:SetColorTexture(1,.18,.09,math.min(1,(detail and .95 or .7)*NAGDeathRadarSettings.viewOutline));l:Show()
    end
    for _,points in ipairs(m.fills) do for i=2,#points-1 do
        usedTriangles=usedTriangles+1
        local t=triangles[usedTriangles]
        if not t then
            t=frame:CreateTexture(nil,'ARTWORK');t:SetSize(1,1);t:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',0,0)
            triangles[usedTriangles]=t
        end
        local a,b,c=points[1],points[i],points[i+1]
        if type(t.SetVertexOffset)=='function' then
            t:SetVertexOffset(1,a.x,a.y-1);t:SetVertexOffset(3,b.x-1,b.y-1)
            t:SetVertexOffset(2,c.x,c.y);t:SetVertexOffset(4,c.x-1,c.y)
            t:SetColorTexture(1,.1,.05,math.min(1,(detail and .1 or .045)*NAGDeathRadarSettings.viewFill));t:Show()
        end
    end end
    local text=m.inside and NAGDeathRadarSettings.rimTint
        and (W.replayMode and 'Inside replay area' or 'In a danger area') or ''
    if detail and m.nearestDistance then text=text..('  ~%d yd to boundary'):format(math.floor(m.nearestDistance+.5)) end
    status:SetText(text)
    caption:SetText(captionText())
    frame:Show();W.lastModel=m;W.fading=false;W.state='ok'
end
local function step(dt)
    if W.backup and not W.armed and not ns.InCombat() then
        W.restorePoll=math.max(0,(W.restorePoll or 0)-dt)
        if W.restorePoll==0 and tryRelease() and not W.active then note('stopped') end
    end
    if not W.active then
        ticker();return
    end
    if not W.IsSelected() then W.Stop();return end
    W.stats.elapsed=(W.stats.elapsed or 0)+dt
    if W.armed and ns.InCombat() then W.Stop('combat',true);return end
    if type(_G.UnitIsDeadOrGhost)=='function' and read(UnitIsDeadOrGhost,'player')==true then W.Stop('control');return end
    if ns.Perspective and ns.Perspective.CheckHold then ns.Perspective.CheckHold() end
    local v=context()
    if not v then W.Stop('no_position',true);return end
    if W.sessionMap and v.map~=W.sessionMap then W.Stop('control');return end
    if W.ours and not checkOwner(snapshot()) then return end
    if W.pose then
        local pose=W.pose
        pose.age=pose.age+dt;W.drawElapsed=(W.drawElapsed or 0)+dt
        if pose.age>=.35 then W.pose=nil;hide();fallback(true)
        elseif W.drawElapsed+1e-8>=1/60 then
            W.drawElapsed=0
            local m=G.Render(pose.mesh,pose.h,G.ShiftBounds(pose.bounds,pose.origin,v),frame:GetWidth(),frame:GetHeight())
            if m and G.Readable(m) then draw(m) else W.pose=nil;hide();fallback(true) end
        end
    end
    W.poll=math.max(0,(W.poll or 0)-dt)
    if not W.samples then if W.poll==0 then begin(v) end;return end
    -- A seven-point batch takes about 233 ms at 60 FPS. The old one-yard
    -- guard rejected ordinary running before either independent check ran.
    -- Allow up to two yards, compensating the measured player translation.
    -- Independent holdouts and the repeated-anchor residual must both stay
    -- below four UI pixels, including while the player moves.
    if v.map~=W.batch.map or ((v.px-W.batch.px)*v.W)^2+((v.py-W.batch.py)*v.H)^2>4 then
        reject('movement',false);return
    end
    W.age,W.batchAge=W.age+dt,W.batchAge+dt
    W.settleFrames=W.settleFrames+1
    -- The native navigation frame can still project the previous waypoint on
    -- the first OnUpdate after a setter. Give it two rendered updates to settle.
    if W.batchAge>=.35 then reject('expired',false);return end
    if W.settleFrames<2 or W.age<1/144 then return end
    local q,why=sample()
    if not q then
        reject(why,true);W.poll=.05;return
    end
    W.samples[W.index]=q
    W.sourcePoints[W.index]=G.Rebase(W.points[W.index],W.batch,v)
    if W.index<7 then selectPoint(W.index+1);return end
    local a,b=W.samples[1],W.samples[7]
    local rawDrift=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    local h,fitReason=G.FitMoving(W.samples,W.sourcePoints,W.bounds)
    local err=h and G.Validate(h,W.sourcePoints,W.samples,W.bounds) or math.huge
    local drift=h and G.Validate(h,W.sourcePoints,W.samples,W.bounds,7,7) or math.huge
    W.stats.batches=W.stats.batches+1;W.stats.lastError,W.stats.lastDrift=err,drift
    W.stats.lastRawDrift=rawDrift
    if h and err<4 and drift<4 and W.batchAge<.35 then
        local width,height=frame:GetWidth(),frame:GetHeight()
        if not number(width,1,20000) or not number(height,1,20000) then error('Screen size unavailable') end
        -- Render the fixed map mask at the latest player position. Rebuilding
        -- also keeps containment and boundary distance current while running.
        local mesh=G.Near(W.sourceGeometry,v,NAGDeathRadarSettings.reach)
        local model=mesh and G.Render(mesh,h,G.ShiftBounds(W.bounds,W.batch,v),width,height)
        if model and G.Readable(model) then
            W.pose={mesh=mesh,h=h,bounds=W.bounds,origin=W.batch,age=0};W.drawElapsed=0
            draw(model);W.stats.accepted=W.stats.accepted+1
            if ((v.px-W.batch.px)*v.W)^2+((v.py-W.batch.py)*v.H)^2>.25^2 then
                W.stats.movingAccepted=(W.stats.movingAccepted or 0)+1
                W.stats.movingRawDrift=math.max(W.stats.movingRawDrift or 0,rawDrift)
                W.stats.movingResidual=math.max(W.stats.movingResidual or 0,err,drift)
            end
        else reject(model and 'sliver' or 'complexity',false) end
    else
        -- A changing camera can invalidate a visible reference temporarily.
        -- Retry it before searching offscreen directions; clamped/invalid
        -- anchors already trigger that search in the sample path above.
        reject(not h and (fitReason or 'fit') or (err>=4 and 'holdout' or 'drift'),not h)
    end
    W.samples=nil;begin(v)
end
function W.Update(dt)
    local ok,why=pcall(step,dt)
    if not ok then W.lastError=tostring(why);W.Stop('error',true) end
end
function W.Start(preview)
    W.Stop();W.replayMode=preview==true;W.quadrant=0;W.poll=0;W.fading=false;W.sessionMap=nil
    if not W.IsSelected() then return end
    W.lastError=nil;W.lastModel=nil;W.navigationChange=nil;W.pauseReason=nil
    W.stats={attempts=0,rejected=0,reasons={},batches=0,accepted=0,switches=0}
    W.active=true
    W.armed=NAGDeathRadarSettings.worldAnchors==true and not W.backup and not ns.InCombat()
    note(ns.InCombat() and 'combat' or (W.armed and 'calibrating' or 'directional'));ticker()
end
function W.Refresh(s)
    if not frame then return end
    local restart=W.active and W.IsSelected();local preview=W.replayMode
    W.Stop()
    cachedRuns,cachedN,prepared=nil,nil,nil
    status:ClearAllPoints();status:SetPoint('CENTER',UIParent,'CENTER',s.viewX,s.viewY-20)
    caption:ClearAllPoints();caption:SetPoint('BOTTOM',status,'TOP',0,4)
    if restart then W.Start(preview) end
end
function W.Init()
    if frame then return end
    frame=CreateFrame('Frame','NAGDeathRadarWorldFrame',UIParent)
    frame:SetAllPoints(UIParent);frame:SetFrameStrata('LOW');frame:EnableMouse(false);frame:Hide()
    driver=CreateFrame('Frame',nil,UIParent);driver:EnableMouse(false)
    -- Text lives outside the fading geometry frame.
    local text=CreateFrame('Frame',nil,UIParent);text:SetAllPoints(UIParent);text:SetFrameStrata('LOW');text:EnableMouse(false)
    status=text:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    caption=text:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    driver:SetScript('OnEvent',function(_,event)
        if event=='PLAYER_REGEN_ENABLED' and W.backup then
            if tryRelease() and not W.active then note('stopped') end;ticker();return
        end
        if event=='PLAYER_REGEN_DISABLED' then if W.active then W.Stop('combat',true) end;return end
        if W.active or W.backup then W.Stop('control') end
    end)
    for _,e in ipairs({'PLAYER_LEAVING_WORLD','PLAYER_CONTROL_LOST','PLAYER_LOGOUT','ZONE_CHANGED_NEW_AREA',
        'PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED'}) do driver:RegisterEvent(e) end
    W.frame,W.driver,W.statusText,W.caption=frame,driver,status,caption
end
function W.Status()
    local s=W.stats
    local report=('World view: %s; attempts %d; accepted %d; rejected %d; %.1f accepted/s; tracking %s'):format(
        W.state,s.attempts or 0,s.accepted or 0,s.rejected or 0,
        (s.accepted or 0)/math.max(.001,s.elapsed or 0),W.backup and 'borrowed' or 'released')
    local reasons={}
    report=report..'; waypoint sampling '..(W.armed and 'on' or 'off')
        ..'; display '..((ns.Perspective and ns.Perspective.fallback) and 'approximate character direction' or (W.pose and 'camera projection' or 'hidden'))
    for reason,n in pairs(s.reasons or {}) do reasons[#reasons+1]=reason..'='..n end
    table.sort(reasons)
    if #reasons>0 then report=report..'; '..table.concat(reasons,', ') end
    if s.lastReject then report=report..'; last reject '..s.lastReject end
    report=report..('; accepted while moving %d'):format(s.movingAccepted or 0)
    if s.movingRawDrift then
        report=report..('; moving max raw %.1f px, compensated %.1f px'):format(s.movingRawDrift,s.movingResidual)
    end
    if s.lastError then report=report..('; holdout %.1f px, drift %.1f px'):format(s.lastError,s.lastDrift) end
    if W.state=='error' and W.lastError then report=report..'; '..W.lastError end
    if W.state=='navigation_changed' and W.navigationChange then report=report..'; '..W.navigationChange end
    if W.lastRestoreError then report=report..'; restore error: '..W.lastRestoreError end
    return report
end
