-- Native anchors are simulated with an independent projective camera. Tests
-- exercise ownership and bad samples, not just the successful rendering path.
local S=assert(loadfile('tests/wowstub.lua'))()
local count,failed=0,0
local function test(name,f)
    count=count+1;local ok,why=pcall(f)
    if not ok then failed=failed+1;io.write('FAIL '..name..': '..tostring(why)..'\n') end
end
local function boot(opts)
    opts=opts or {};S.reset({secrets=true})
    assert(loadfile('tests/fixtures/nagdeath_base0.lua'))()
    local ns={}
    for _,name in ipairs({'core','options','overlay','radar','perspective-geometry','perspective','world-projection','world-view'}) do
        assert(loadfile('NAGDeathRadar/'..name..'.lua'))('NAGDeathRadar',ns)
    end
    local nav={quest=99411,user=false,point=nil,writes=0,camera=0,bad=false,clamped=false}
    local function camera(p)
        local x,y=(p.position.x-.5)*600,(.5-p.position.y)*600
        local den=35+y*.35
        return 500+(x*170+nav.camera*y)/den,250+y*130/den
    end
    nav.frame=S.new(S.KINDS.FRAME)
    nav.frame.GetCenter=function()if not nav.point then return 500,300 end;return camera(nav.point) end
    _G.UiMapPoint={CreateFromCoordinates=function(map,x,y)return {uiMapID=map,position={x=x,y=y}}end}
    _G.C_SuperTrack={GetSuperTrackedQuestID=function()return nav.quest end,
        IsSuperTrackingUserWaypoint=function()return nav.user end,
        GetHighestPrioritySuperTrackingType=function()return nav.kind or (nav.user and 1 or 0) end,
        SetSuperTrackedUserWaypoint=function(on)
            nav.user=on;nav.writes=nav.writes+1
            -- Forever clears the quest when selecting a user waypoint. Observed
            -- directly with quest 1505 in Beta on 2026-10-22.
            if on and not opts.retainQuest then nav.quest=nil end
            if on and nav.trackFail then error('Tracking failed after switching') end
        end,
        SetSuperTrackedQuestID=function(id)
            if nav.restoreFail then error('Restore blocked') end
            nav.quest=id;nav.user=false;nav.writes=nav.writes+1
        end}
    C_Map.GetUserWaypoint=function()return nav.point end
    C_Map.CanSetUserWaypointOnMap=function()return true end
    C_Map.SetUserWaypoint=function(p)
        nav.point=p;nav.writes=nav.writes+1
        if nav.writeFail then error('Setter failed after writing') end
        return true
    end
    C_Map.ClearUserWaypoint=function()nav.point=nil;nav.writes=nav.writes+1 end
    _G.C_Navigation={GetFrame=function()if nav.bad then error('Native unavailable') end;return nav.frame end,
        HasValidScreenPosition=function()return not nav.bad end,WasClampedToScreen=function()return nav.clamped end}
    _G.UnitIsDeadOrGhost=function()return false end
    S.player.map,S.player.x,S.player.y,S.player.facing=1429,.5,.5,0
    S.worldBounds[1429]={600,600,0,0}
    local runs={}
    for y=70,80 do runs[#runs+1]={x0=85,x1=115,y=y,step=1000} end
    ns.Overlay.Picture=function()return runs,200 end
    S.fire('ADDON_LOADED','NAGDeathRadar')
    NAGDeathRadarSettings.worldAnchors=opts.anchors~=false -- native-path fixtures explicitly opt in
    S.fire('PLAYER_LOGIN')
    local function tick(n,dt)for _=1,n or 16 do S.frame(dt or .009) end end
    return ns,ns.WorldView,nav,tick,runs
end

test('mode is opt-in and a saved world choice does not start navigation',function()
    local ns,w,n=boot();assert(n.writes==0)
    NAGDeathRadarSettings.mode='world';ns.Apply();assert(not w.armed and n.writes==0)
    SlashCmdList.NAGDEATHRADAR('mode world');assert(w.armed)
end)
test('world selector produces weak fill, transparent frames, and restores tracking',function()
    local ns,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(24)
    assert(w.state=='ok',w.state..' '..tostring(w.lastError))
    assert(w.lastModel and #w.lastModel.strokes>0 and #w.lastModel.fills>0)
    assert(not w.frame._mouse and not w.driver._mouse)
    local fill
    for _,o in ipairs(S.objects) do if o._parent==w.frame and o._kind==S.KINDS.TEXTURE then fill=o;break end end
    assert(fill and fill._color[4]<=.05)
    SlashCmdList.NAGDEATHRADAR('world stop');assert(not w.armed and not w.backup and not n.point and not n.user and n.quest==99411)
end)

test('a new character with nil quest and tracking type can start and restore navigation',function()
    local _,w,n,tick=boot();n.quest=nil
    C_SuperTrack.GetHighestPrioritySuperTrackingType=function() if n.user then return 1 end end
    SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    assert(w.state=='ok',tostring(w.lastError))
    SlashCmdList.NAGDEATHRADAR('world stop')
    assert(not w.backup and not n.point and not n.user and n.quest==nil)
end)

test('native waypoint selection can clear a quest without causing a takeover',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    assert(w.armed and w.state=='ok' and n.quest==nil,w.state)
    SlashCmdList.NAGDEATHRADAR('world stop')
    assert(n.quest==99411 and not n.point and not n.user and not w.backup)
end)

test('clients retaining the quest during waypoint selection are still supported',function()
    local _,w,n,tick=boot({retainQuest=true});SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    assert(w.armed and w.state=='ok' and n.quest==99411)
    SlashCmdList.NAGDEATHRADAR('world stop')
    assert(n.quest==99411 and not n.point and not n.user)
end)

test('a partial tracking setter failure restores the cleared quest and empty flag',function()
    local _,w,n,tick=boot();n.trackFail=true
    SlashCmdList.NAGDEATHRADAR('world preview');tick(3)
    assert(not w.armed and not w.backup and not n.point and not n.user and n.quest==99411)
end)

test('malformed quest values are rejected without navigation writes',function()
    local _,w,n,tick=boot();n.quest=false
    SlashCmdList.NAGDEATHRADAR('world preview');tick(3)
    assert(w.state=='error' and not w.armed and n.writes==0)
end)
test('camera rotation changes projection without changing source mask',function()
    local _,w,n,tick,runs=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(24)
    local x=w.lastModel.strokes[1].x1;n.camera=35;tick(24)
    assert(w.lastModel.strokes[1].x1~=x and runs[1].x0==85)
end)

test('a native frame that lags one update behind each waypoint is allowed to settle',function()
    local _,w,n,tick=boot()
    local getCenter=n.frame.GetCenter
    local setter=C_Map.SetUserWaypoint
    local stale
    C_Map.SetUserWaypoint=function(p)
        stale=true;return setter(p)
    end
    n.frame.GetCenter=function()
        assert(not stale,'sampled before the native projection settled')
        return getCenter()
    end
    SlashCmdList.NAGDEATHRADAR('mode world')
    for _=1,40 do
        -- The first update still belongs to the previous target. Native state
        -- catches up before the next update, as observed in the client probe.
        local first=w.samples and w.settleFrames==0
        tick(1)
        if first then stale=false end
    end
    assert(w.state=='ok' and w.stats.accepted>0)
end)

test('sampling rejections count attempts that never reach fitting',function()
    local _,w,n,tick=boot();n.clamped=true
    SlashCmdList.NAGDEATHRADAR('world preview');tick(60)
    assert(w.stats.attempts>0 and w.stats.rejected>0 and w.stats.batches==0)
    assert(w.stats.reasons.clamped==w.stats.rejected)
    assert(w.stats.attempts==w.stats.accepted+w.stats.rejected+(w.samples and 1 or 0))
    assert(w.Status():find('clamped=',1,true) and w.Status():find('attempts ',1,true))
    assert(w.quadrant>=0 and w.quadrant<8)
end)

test('a diagonal-only visible anchor rectangle can be found',function()
    local _,w,n,tick=boot()
    C_Navigation.WasClampedToScreen=function()return w.quadrant~=1 end
    SlashCmdList.NAGDEATHRADAR('mode world');tick(50)
    assert(w.stats.accepted>0 and w.quadrant==1)
    assert(w.stats.reasons.clamped==1)
end)

test('shallow reference planes use the labelled direction fallback instead of a flat strip',function()
    local ns,w,n,tick=boot();local original=n.frame.GetCenter
    n.frame.GetCenter=function()
        local x,y=original();return x,300+y*.01
    end
    SlashCmdList.NAGDEATHRADAR('world preview');tick(32)
    assert(w.state=='shallow' and w.stats.reasons.shallow>0 and w.stats.accepted==0)
    assert(not w.frame:IsShown())
    assert(w.statusText:GetText()=='' and w.caption:GetText()=='')
    assert(ns.Perspective.frame:IsShown() and ns.Perspective.label:GetText():find('REPLAY',1,true))
    assert(ns.Perspective.label:GetText():find('APPROXIMATE',1,true))
end)

test('movement and slow-frame expiry are visible rejection causes',function()
    local _,w,_,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(1)
    S.player.y=S.player.y-.01;tick(1)
    assert(w.stats.reasons.movement==1)
    SlashCmdList.NAGDEATHRADAR('world stop')
    SlashCmdList.NAGDEATHRADAR('mode world');tick(30,.04)
    assert(w.stats.accepted==0 and w.stats.reasons.expired>0)
end)
test('steady running at 60 FPS can calibrate with independent validation',function()
    local _,w,n,tick=boot()
    n.frame.GetCenter=function()
        local x=(n.point.position.x-S.player.x)*600
        local y=(S.player.y-n.point.position.y)*600
        local den=35+y*.35
        return 500+x*170/den,250+y*130/den
    end
    SlashCmdList.NAGDEATHRADAR('world preview')
    for _=1,120 do S.player.y=S.player.y-7/60/600;tick(1,1/60) end
    assert(w.stats.accepted>0 and w.stats.movingAccepted>0,w.Status())
    assert(w.stats.lastError<4 and w.stats.lastDrift<4)
end)
test('sideways and diagonal running accept motion exceeding the raw four-pixel limit',function()
    local largestRaw=0
    for _,velocity in ipairs({{7,0},{4.2,-5.6},{-7,0}}) do
        local _,w,n,tick=boot()
        n.frame.GetCenter=function()
            local x=(n.point.position.x-S.player.x)*600
            local y=(S.player.y-n.point.position.y)*600
            local den=35+y*.35
            return 500+x*170/den,250+y*130/den
        end
        SlashCmdList.NAGDEATHRADAR('world preview')
        for _=1,120 do
            S.player.x=S.player.x+velocity[1]/60/600;S.player.y=S.player.y+velocity[2]/60/600
            tick(1,1/60)
        end
        assert(w.stats.movingAccepted>=7,w.Status())
        largestRaw=math.max(largestRaw,w.stats.lastRawDrift)
        assert(w.stats.lastDrift<1e-6 and w.stats.lastError<1e-6,w.Status())
        assert(w.lastModel and #w.lastModel.strokes>0 and w.frame:IsShown())
    end
    assert(largestRaw>4,tostring(largestRaw))
end)
test('running does not relax the repeated-anchor camera drift limit',function()
    local _,w,n,tick=boot()
    n.frame.GetCenter=function()
        local x=(n.point.position.x-S.player.x)*600
        local y=(S.player.y-n.point.position.y)*600
        local den=35+y*.35
        return 500+x*170/den+(w.index==7 and 20 or 0),250+y*130/den
    end
    SlashCmdList.NAGDEATHRADAR('world preview')
    for _=1,120 do S.player.y=S.player.y-7/60/600;tick(1,1/60) end
    assert(w.stats.accepted==0 and w.stats.reasons.drift>0 and not w.frame:IsShown())
    assert(w.quadrant==0,'a visible reference should be retried after temporary camera drift')
end)
test('external waypoint takeover pauses without overwriting the new target',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(12)
    local p=UiMapPoint.CreateFromCoordinates(1429,.12,.23);n.point=p
    local writes=n.writes;tick(2)
    assert(not w.armed and w.state=='navigation_changed' and n.point==p and n.writes==writes)
end)
test('external quest change is preserved when releasing our temporary point',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(12)
    n.quest=77;n.user=false;tick(2)
    assert(not w.armed and n.quest==77 and not n.point and not n.user)
end)
test('a foreign quest changed inside a setter is never adopted as our own',function()
    local _,w,n,tick=boot();local setter=C_SuperTrack.SetSuperTrackedUserWaypoint
    C_SuperTrack.SetSuperTrackedUserWaypoint=function(on)
        setter(on);if on then n.quest=77 end
    end
    SlashCmdList.NAGDEATHRADAR('world preview');tick(3)
    assert(not w.armed and w.state=='navigation_changed' and n.quest==77 and not n.point)
end)
test('a higher-priority map target pauses without restoring over it',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(12)
    n.kind=2;tick(2)
    assert(not w.armed and n.kind==2 and not n.point and n.user)
end)
test('native coordinate rounding does not falsely trigger a navigation takeover',function()
    local _,w,n,tick=boot()
    local setter=C_Map.SetUserWaypoint
    C_Map.SetUserWaypoint=function(p)
        p.position.x=math.floor(p.position.x*1e7+.5)/1e7
        p.position.y=math.floor(p.position.y*1e7+.5)/1e7
        return setter(p)
    end
    SlashCmdList.NAGDEATHRADAR('mode world');tick(24)
    assert(w.armed and w.state=='ok')
end)
test('existing user waypoint is never borrowed',function()
    local _,w,n,tick=boot();n.point=UiMapPoint.CreateFromCoordinates(1429,.1,.2);n.user=true
    local p=n.point;SlashCmdList.NAGDEATHRADAR('mode world');tick(2)
    assert(w.state=='waypoint_busy' and n.point==p and n.writes==0)
end)
test('combat stops writes, defers restore, and never resumes automatically',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(12)
    S.player.combat=true;local writes=n.writes;S.fire('PLAYER_REGEN_DISABLED');tick(3)
    assert(not w.armed and w.backup and n.writes==writes)
    S.player.combat=false;S.fire('PLAYER_REGEN_ENABLED');tick(2)
    assert(not w.armed and not w.backup and n.quest==99411 and not n.user and not n.point)
end)
test('partial setter failure restores only our own point',function()
    local _,w,n,tick=boot();n.writeFail=true;SlashCmdList.NAGDEATHRADAR('mode world');tick(3)
    assert(not w.armed and not n.point and not n.user and n.quest==99411)
end)
test('restore failure after clearing the point is retried without losing the quest',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(12)
    n.restoreFail=true;SlashCmdList.NAGDEATHRADAR('world stop')
    assert(w.backup and not n.point)
    n.restoreFail=false;tick(40)
    assert(not w.backup and not n.user and n.quest==99411)
end)
test('failed restoration is throttled and its cause is available in status',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    local tries=0;local setter=C_SuperTrack.SetSuperTrackedQuestID
    C_SuperTrack.SetSuperTrackedQuestID=function(id)tries=tries+1;return setter(id)end
    n.restoreFail=true;SlashCmdList.NAGDEATHRADAR('world stop');tick(20)
    assert(w.backup and w.state=='restoring' and tries==1,tostring(tries))
    assert(w.Status():find('restore error',1,true))
    n.restoreFail=false;tick(40)
    assert(not w.backup and n.quest==99411 and not n.user)
end)
test('a new quest during a deferred restoration is preserved',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    n.restoreFail=true;SlashCmdList.NAGDEATHRADAR('world stop')
    n.quest=77;n.user=false;n.restoreFail=false;tick(40)
    assert(not w.backup and n.quest==77 and not n.point and not n.user)
end)
test('clamped samples fade geometry out within 160ms',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(24)
    assert(w.frame:IsShown());n.clamped=true;tick(25)
    assert(w.alpha==0 and not w.frame:IsShown())
    n.clamped=false;tick(35);assert(w.frame:IsShown() and w.alpha==1)
end)
test('an inconsistent holdout is rejected rather than stretching the shape',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(24)
    local original=n.frame.GetCenter
    n.frame.GetCenter=function()
        local x,y=original()
        if w.index==5 then x=x+80 end
        return x,y
    end
    tick(40);assert(w.alpha==0 and w.stats.lastError>4)
end)
test('no red data in range keeps navigation and drawing idle',function()
    local _,w,n,tick,runs=boot();for _,r in ipairs(runs) do r.y=1 end
    SlashCmdList.NAGDEATHRADAR('mode world');tick(40)
    assert(w.state=='empty' and not w.frame:IsShown() and not n.point and n.writes==0 and w.caption:GetText()=='')
end)
test('details binding strengthens world contours and release restores them',function()
    local _,w,_,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(24)
    S.bindings.NAGDEATHRADAR_DETAIL={'H'};S.keys.H=true;NAGDeathRadar_SetDetail(true);tick(16)
    local line
    for _,o in ipairs(S.objects) do if o._parent==w.frame and o._kind==S.KINDS.LINE then line=o;break end end
    assert(line and line._thickness==2.4 and w.statusText:GetText():find('yd to boundary',1,true))
    S.keys.H=false;tick(16);assert(line._thickness==1.5)
end)
test('position changes rebuild the mesh while retaining the map anchored source',function()
    local _,w,_,tick,runs=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(24)
    local old=w.lastModel.nearestDistance
    S.player.y=S.player.y-.005;tick(24)
    assert(w.state=='ok' and w.lastModel.nearestDistance<old and runs[1].y==70)
end)
test('new world selection is available in the settings panel',function()
    local _,w,_,tick=boot();local button=S.panels[1].panel.modeButtons.world
    assert(button);button._scripts.OnClick();tick(24);assert(w.armed and w.state=='ok')
end)
test('switching view or hiding restores quest and stops the world ticker',function()
    for _,command in ipairs({'mode perspective','mode radar','hide'}) do
        local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(15)
        SlashCmdList.NAGDEATHRADAR(command);tick(2)
        assert(not w.armed and not w.backup and not w.driver:GetScript('OnUpdate') and not n.point and not n.user)
    end
end)
test('world replay is marked, copied, and explicitly stopped',function()
    local _,w,_,tick,runs=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    assert(w.state=='ok' and w.caption:GetText():find('NOT REAL DANGER HERE',1,true))
    assert(runs[1].y==70 and runs[1].x0==85 and w.replay)
    SlashCmdList.NAGDEATHRADAR('world stop');assert(not w.replay)
end)
test('entering the copied replay shape shows an explicitly replay-labelled indicator',function()
    local _,w,_,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    local r=w.replay.rects[1]
    S.player.x,S.player.y=(r.x0+r.x1)/2,(r.y0+r.y1)/2
    tick(40)
    assert(w.lastModel and w.lastModel.inside)
    assert(w.statusText:GetText():find('Inside replay area',1,true))
    assert(w.caption:GetText():find('NOT REAL DANGER HERE',1,true))
end)
test('replay warning survives camera recalibration in the approximate fallback and disappears when stopped',function()
    local ns,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    n.clamped=true;tick(25)
    assert(w.state=='calibrating' and ns.Perspective.label:GetText():find('REPLAY',1,true))
    assert(w.caption:GetText()=='' and w.frame:IsShown()==false)
    SlashCmdList.NAGDEATHRADAR('world stop');assert(w.caption:GetText()=='')
end)

test('default world mode never reads or writes waypoint navigation and preserves an existing pin',function()
    local ns,w,n,tick=boot({anchors=false})
    assert(ns.defaults.worldAnchors==false)
    n.point=UiMapPoint.CreateFromCoordinates(1429,.12,.23);n.user=true
    local original=n.point
    C_Navigation.GetFrame=function()error('quiet view must not read navigation')end
    C_Map.GetUserWaypoint=function()error('quiet view must not borrow navigation')end
    SlashCmdList.NAGDEATHRADAR('world start');tick(50,1/30)
    assert(w.active and not w.armed and n.writes==0 and n.point==original and n.user)
    assert(ns.Perspective.frame:IsShown() and ns.Perspective.fallback and w.state=='directional')
    assert(w.Status():find('waypoint sampling off',1,true))
    SlashCmdList.NAGDEATHRADAR('world stop');tick(2)
    assert(n.writes==0 and not ns.Perspective.frame:IsShown() and not w.driver:GetScript('OnUpdate'))
end)
test('a failed native projection falls back using the exact map geometry and recovers automatically',function()
    local ns,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    local replay=w.replay
    n.clamped=true;tick(20)
    assert(not w.frame:IsShown() and ns.Perspective.frame:IsShown())
    assert(ns.Perspective.fallback.geometry==replay and ns.Perspective.fallback.replay)
    assert(ns.Perspective.label:GetText():find('APPROXIMATE',1,true))
    n.clamped=false;tick(35)
    assert(w.frame:IsShown() and not ns.Perspective.frame:IsShown() and not ns.Perspective.fallback)
end)
test('world camera projection follows player translation between complete native batches',function()
    local _,w,_,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(16,1/60)
    assert(w.pose and w.lastModel,w.Status())
    local accepted,x=w.stats.accepted,w.lastModel.strokes[1].x1
    S.player.x=S.player.x+.0002;tick(1,1/60)
    assert(w.stats.accepted==accepted and w.lastModel.strokes[1].x1~=x)
    assert(w.pose and w.state=='ok')
end)
test('combat retains a read-only direction view and never resumes waypoint writes automatically',function()
    local ns,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    S.player.combat=true;local writes=n.writes;S.fire('PLAYER_REGEN_DISABLED');tick(30)
    assert(w.active and not w.armed and n.writes==writes)
    assert(ns.Perspective.frame:IsShown() and ns.Perspective.fallback.geometry==w.replay)
    S.player.combat=false;S.fire('PLAYER_REGEN_ENABLED');tick(3)
    assert(not w.backup and not n.point and n.quest==99411)
    writes=n.writes;S.player.x=S.player.x+.001;tick(30)
    assert(n.writes==writes and not w.armed and ns.Perspective.frame:IsShown())
end)
test('an external waypoint remains visible and untouched while the direction fallback continues',function()
    local ns,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    local external=UiMapPoint.CreateFromCoordinates(1429,.12,.23);n.point=external
    local writes=n.writes;tick(40)
    assert(w.active and not w.armed and n.point==external and n.writes==writes)
    assert(ns.Perspective.frame:IsShown())
end)
test('a collapsed projected danger shape uses the fallback without stretching the map mask',function()
    local ns,w,_,tick=boot();local original=ns.WorldProjection.Render
    ns.WorldProjection.Render=function(...)
        local m=original(...);m.fills={{{x=10,y=300},{x=710,y=300},{x=710,y=301},{x=10,y=301}}}
        return m
    end
    SlashCmdList.NAGDEATHRADAR('world preview');tick(30)
    assert(w.stats.reasons.sliver>0 and w.stats.accepted==0 and not w.frame:IsShown())
    assert(ns.Perspective.frame:IsShown() and ns.Perspective.fallback.geometry==w.replay)
end)
test('slow native sampling keeps the approximate view available at 30 FPS',function()
    local ns,w,_,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(60,1/30)
    assert(w.stats.reasons.expired>0 and not w.frame:IsShown())
    assert(ns.Perspective.frame:IsShown() and ns.Perspective.fallback)
end)
test('switching waypoint sampling off releases our pin immediately and keeps the risk view',function()
    local ns,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('world preview');tick(24)
    SlashCmdList.NAGDEATHRADAR('world anchors off');tick(30)
    assert(not NAGDeathRadarSettings.worldAnchors and w.active and not w.armed)
    assert(not n.point and not n.user and n.quest==99411 and ns.Perspective.frame:IsShown())
    local writes=n.writes;tick(50);assert(n.writes==writes)
end)
test('map/control changes stop sampling and release ownership',function()
    for _,event in ipairs({'PLAYER_LOGOUT','PLAYER_CONTROL_LOST','PLAYER_LEAVING_WORLD','ZONE_CHANGED_NEW_AREA'}) do
        local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(12);S.fire(event);tick(2)
        assert(not w.armed and not w.backup and not n.point)
    end
end)
test('secret samples stop without arithmetic on the secret',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(1)
    n.frame.GetCenter=function()return S.SECRET,200 end;tick(3)
    assert(not w.armed and not n.point)
end)

test('status reports the captured runtime error after releasing navigation',function()
    local _,w,n,tick=boot();SlashCmdList.NAGDEATHRADAR('mode world');tick(1)
    n.bad=true;tick(3)
    assert(w.state=='error' and not w.armed and not n.point)
    assert(w.lastError and w.Status():find(w.lastError,1,true))
end)

io.write(('World view: %d checks, %d failures\n'):format(count,failed))
if failed>0 then os.exit(1) end
