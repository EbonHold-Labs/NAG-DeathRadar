-- Headless runtime/lifecycle tests. Never loads the user's Helper data file.
local S=assert(loadfile('tests/wowstub.lua'))()
local total,failed=0,0
local function test(name,f)
    total=total+1
    local ok,err=pcall(f)
    if not ok then failed=failed+1; io.write('FAIL '..name..': '..tostring(err)..'\n') end
end
local function boot(noData,build)
    S.reset({secrets=true,build=build})
    if not noData then assert(loadfile('tests/fixtures/nagdeath_base0.lua'))() end
    local ns={}
    for _,name in ipairs({'core','options','overlay','radar','perspective-geometry','perspective'}) do
        assert(loadfile('NAGDeathRadar/'..name..'.lua'))('NAGDeathRadar',ns)
    end
    S.player.map,S.player.x,S.player.y,S.player.facing=1429,.5,.5,0
    S.worldBounds[1429]={600,600,0,0}
    S.fire('ADDON_LOADED','NAGDeathRadar'); S.fire('PLAYER_LOGIN')
    local runs={}
    for y=65,78 do runs[#runs+1]={x0=78,x1=92,y=y,step=1000} end
    for y=55,65 do runs[#runs+1]={x0=112,x1=123,y=y,step=1000} end
    ns.Overlay.Picture=function(map) if map==1429 then return runs,200 end end
    ns.Apply()
    return ns,ns.Perspective,runs
end
test('perspective keeps the wrong-game note through refresh, context changes and preview exit',function()
    local ns,p=boot(false,{'2.5.5','65000','',20505})
    assert(not ns.data and ns.dataReason=='flavor' and p.state=='no_data')
    assert(p.statusText:GetText()=='no data for this game')
    ns.Apply();S.fire('PLAYER_ENTERING_WORLD')
    assert(p.statusText:GetText()=='no data for this game' and S.liveUpdates()==0)
    p.SetPreview(true);assert(p.preview and p.state=='ok')
    p.SetPreview(false)
    assert(p.state=='no_data' and p.statusText:GetText()=='no data for this game')
    assert(S.liveUpdates()==0)
end)
test('perspective accepts matching Forever data after the flavor integration',function()
    local ns,p=boot(false,{'1.60.1','70450','',16001})
    assert(ns.data and p.state=='ok' and p.frame:IsShown())
end)
test('perspective replaces circle with two visible regions',function()
    local ns,p=boot()
    assert(NAGDeathRadarSettings.mode=='perspective' and not ns.RadarFrame:IsShown())
    assert(p.state=='ok' and p.frame:IsShown())
    local regions={}; for _,s in ipairs(p.lastModel.strokes) do regions[s.region]=true end
    local count=0; for _ in pairs(regions) do count=count+1 end
    assert(count==2 and p.lastModel.nearestDistance>0)
end)
test('view and driver stay mouse transparent and have one update',function()
    local _,p=boot()
    assert(not p.frame._mouse and not p.driver._mouse and S.liveUpdates()==1)
    for name,script in pairs(p.frame._scripts) do assert(not name:find('Mouse') and not name:find('Drag')) end
end)
test('movement renders on each 60 FPS update while stationary frames reuse the last model',function()
    local ns,p=boot();local original=ns.PerspectiveGeometry.Compute
    local paints=0
    ns.PerspectiveGeometry.Compute=function(...)paints=paints+1;return original(...)end
    for _=1,30 do S.frame(1/60) end
    assert(paints==0,'stationary geometry must not be rebuilt every frame')
    for _=1,6 do S.player.x=S.player.x+.0001;S.frame(1/60) end
    assert(paints==6 and p.frame:IsShown(),tostring(paints))
end)
test('contour and fill controls are separate and invalid numbers are rejected',function()
    local _,p=boot()
    SlashCmdList.NAGDEATHRADAR('outline 1.5');SlashCmdList.NAGDEATHRADAR('fill 0')
    assert(NAGDeathRadarSettings.viewOutline==1.5 and NAGDeathRadarSettings.viewFill==0)
    assert(S.panels[1].panel.viewSliders.viewOutline.Text:GetText():find('1.50',1,true))
    for _,o in ipairs(S.objects) do if o._parent==p.frame and o:IsShown() then
        if o._kind==S.KINDS.LINE then assert(math.abs(o._thickness-1.95)<1e-6) end
        if o._kind==S.KINDS.TEXTURE and o._color then assert(o._color[4]==0) end
    end end
    SlashCmdList.NAGDEATHRADAR('outline nan');SlashCmdList.NAGDEATHRADAR('fill inf')
    assert(NAGDeathRadarSettings.viewOutline==1.5 and NAGDeathRadarSettings.viewFill==0)
end)

test('Alt exposes a separate mover even with an empty view or no data',function()
    for _,noData in ipairs({false,true}) do
        local _,p=boot(noData)
        assert(not p.mover:IsShown() and not p.mover._mouse)
        if not noData then S.player.facing=math.pi; S.frame(.11); assert(not p.frame:IsShown()) end
        S.player.alt=true; S.fire('MODIFIER_STATE_CHANGED','LALT',1)
        assert(p.mover:IsShown() and p.mover._mouse and not p.frame._mouse)
        S.player.alt=false; S.fire('MODIFIER_STATE_CHANGED','LALT',0)
        assert(not p.mover:IsShown() and not p.mover._mouse)
    end
end)

test('Alt drag saves the bottom offset correctly at non-default scale',function()
    local ns,p=boot()
    p.mover._scripts.OnDragStart(); assert(not p.dragging)
    NAGDeathRadarSettings.viewScale=1.5; ns.Apply()
    S.player.alt=true; S.fire('MODIFIER_STATE_CHANGED','LALT',1)
    p.mover._scripts.OnDragStart(); assert(p.dragging and p.mover._moving)
    p.mover._cx,p.mover._cy=400,320
    p.mover._scripts.OnDragStop()
    assert(not p.dragging and not p.mover._moving)
    assert(NAGDeathRadarSettings.viewX==100 and NAGDeathRadarSettings.viewY==10)
    ns.Apply()
    assert(math.abs(p.mover._point[4]-100/1.5)<1e-8 and math.abs(p.mover._point[5]-10/1.5)<1e-8)
    assert(p.frame._point[2]==p.mover)
end)

test('missed Alt release stops drag and restores click-through without data',function()
    local _,p=boot(true)
    S.player.alt=true; S.fire('MODIFIER_STATE_CHANGED','LALT',1)
    p.mover._scripts.OnDragStart(); assert(p.dragging)
    S.player.alt=false; S.frame(.01)
    assert(not p.dragging and not p.mover:IsShown() and not p.mover._mouse and S.liveUpdates()==0)
end)

test('mode disable and control loss cancel an active move',function()
    for _,action in ipairs({'mode','control','hide'}) do
        local ns,p=boot()
        S.player.alt=true; S.fire('MODIFIER_STATE_CHANGED','LALT',1)
        p.mover._scripts.OnDragStart(); assert(p.dragging)
        if action=='mode' then NAGDeathRadarSettings.mode='circle'; ns.Apply()
        elseif action=='hide' then NAGDeathRadarSettings.radar=false; ns.Apply()
        else S.fire('PLAYER_CONTROL_LOST') end
        assert(not p.dragging and not p.mover._moving and not p.mover:IsShown() and not p.mover._mouse)
    end
end)

test('drag positions are bounded and invalid positions never overwrite saved values',function()
    local _,p=boot()
    S.player.alt=true; S.fire('MODIFIER_STATE_CHANGED','LALT',1)
    p.mover._scripts.OnDragStart(); p.mover._cx,p.mover._cy=100000,-100000
    p.mover._scripts.OnMouseUp(p.mover,'LeftButton')
    assert(NAGDeathRadarSettings.viewX==2000 and NAGDeathRadarSettings.viewY==-1000)
    p.mover._scripts.OnDragStart(); p.mover._cx,p.mover._cy=0/0,math.huge
    p.mover._scripts.OnDragStop()
    assert(NAGDeathRadarSettings.viewX==2000 and NAGDeathRadarSettings.viewY==-1000)
end)
test('heading turn hides then recovers without hiding driver',function()
    local _,p=boot()
    S.player.facing=math.pi; S.frame(.11)
    assert(p.state=='empty' and not p.frame:IsShown() and p.driver:IsShown())
    S.player.facing=0; S.frame(.11)
    assert(p.state=='ok' and p.frame:IsShown())
end)
test('movement changes true boundary distance and projected contour',function()
    local _,p=boot()
    local distance=p.lastModel.nearestDistance
    local y=p.lastModel.strokes[1].y1
    S.player.y=.47; S.frame(.11)
    assert(p.lastModel.nearestDistance<distance and p.lastModel.strokes[1].y1~=y)
end)

test('front layout flattens vertical depth without changing danger regions or distances',function()
    local ns,p=boot()
    NAGDeathRadarSettings.viewHeight=280; ns.Apply()
    local tall=p.lastModel
    SlashCmdList.NAGDEATHRADAR('front')
    local flat=p.lastModel
    assert(flat and #flat.strokes==#tall.strokes and #flat.fills==#tall.fills)
    assert(flat.inside==tall.inside and flat.nearestRegion==tall.nearestRegion)
    assert(flat.nearestDistance==tall.nearestDistance)
    for i,line in ipairs(flat.strokes) do
        local old=tall.strokes[i]
        assert(line.region==old.region and line.x1==old.x1 and line.x2==old.x2)
        assert(math.abs(line.y1-old.y1*160/280)<1e-8 and math.abs(line.y2-old.y2*160/280)<1e-8)
    end
    assert(p.mover._point[4]==0 and p.mover._point[5]==60)
end)

test('only danger contours draw lines and both view selectors switch immediately',function()
    local ns,p=boot()
    local function checkLines()
        local visible=0
        for _,o in ipairs(S.objects) do
            if o._kind==S.KINDS.LINE and o._parent==p.frame and o:IsShown() then visible=visible+1 end
        end
        assert(visible==#p.lastModel.strokes,'no independent centre line')
    end
    checkLines()
    local panel=S.panels[1].panel
    panel.modeButtons.circle._scripts.OnClick()
    assert(ns.RadarFrame:IsShown() and not p.frame:IsShown())
    SlashCmdList.NAGDEATHRADAR('mode perspective')
    assert(not ns.RadarFrame:IsShown() and p.frame:IsShown())
    checkLines()
    SlashCmdList.NAGDEATHRADAR('mode radar')
    assert(ns.RadarFrame:IsShown() and not p.frame:IsShown())
    panel.modeButtons.perspective._scripts.OnClick()
    assert(not ns.RadarFrame:IsShown() and p.frame:IsShown())
end)
test('inside mark remains when range does not reach outer boundary',function()
    local ns,p,runs=boot()
    for i=#runs,1,-1 do runs[i]=nil end
    for y=1,200 do runs[#runs+1]={x0=1,x1=200,y=y,step=1000} end
    NAGDeathRadarSettings.reach=30; ns.Apply()
    assert(p.state=='ok' and p.lastModel.inside and p.statusText:GetText():find('In a danger area',1,true))
    assert(#p.lastModel.strokes==0 and p.frame:IsShown())
end)
test('detail holds and releases on explicit key up',function()
    local _,p=boot()
    S.bindings.NAGDEATHRADAR_DETAIL={'G'}; S.keys.G=true
    NAGDeathRadar_SetDetail(true)
    assert(p.detail and p.statusText:GetText():find('yd to nearest area boundary',1,true))
    NAGDeathRadar_SetDetail(false)
    assert(not p.detail and p.statusText:GetText()=='')
end)
test('physical release resets a missed key up',function()
    local _,p=boot()
    S.bindings.NAGDEATHRADAR_DETAIL={'SHIFT-G'}; S.keys.G,S.keys.SHIFT=true,true
    p.SetDetail(true); assert(p.detail)
    S.keys.G=false; S.frame(.11); assert(not p.detail)
end)
test('binding reset and chat focus cancel detail',function()
    local _,p=boot()
    S.bindings.NAGDEATHRADAR_DETAIL={'G'}; S.keys.G=true
    p.SetDetail(true); S.fire('UPDATE_BINDINGS'); assert(not p.detail)
    p.SetDetail(true); S.keyboardFocus={}; S.frame(.11); assert(not p.detail)
end)
test('absent optional keyboard APIs still support explicit release',function()
    local _,p=boot()
    GetBindingKey,IsKeyDown,GetCurrentKeyBoardFocus=nil,nil,nil
    p.SetDetail(true); assert(p.detail)
    p.SetDetail(false); assert(not p.detail)
end)
test('world leave and control loss clear immediately and suspend redraw',function()
    local _,p=boot()
    for _,events in ipairs({{'PLAYER_LEAVING_WORLD','PLAYER_ENTERING_WORLD'},{'PLAYER_CONTROL_LOST','PLAYER_CONTROL_GAINED'}}) do
        p.SetDetail(true); S.fire(events[1]); assert(not p.frame:IsShown() and not p.detail)
        S.frame(.11); assert(not p.frame:IsShown())
        S.fire(events[2]); S.frame(.11); assert(p.state=='ok')
    end
end)
test('zone event clears old geometry immediately',function()
    local _,p=boot()
    S.fire('ZONE_CHANGED_NEW_AREA')
    assert(not p.frame:IsShown() and p.lastModel==nil and p.Counts()==0)
    S.frame(.11); assert(p.state=='ok')
end)
test('combat with plain values keeps drawing',function()
    local _,p=boot(); S.player.combat=true; S.frame(.11)
    assert(p.state=='ok' and p.frame:IsShown())
end)
test('missing map data gives explicit status with no stale primitives',function()
    local _,p=boot(); S.player.map=1411; S.worldBounds[1411]={600,600,0,0}; S.frame(.11)
    assert(p.state=='no_map' and p.Counts()==0 and p.statusText:GetText()=='no data for this map')
end)
test('invalid and secret map/heading values clear without throwing',function()
    local ns,p=boot()
    local mapRead,facingRead=ns.Radar.MapRead,ns.Radar.FacingRead
    for _,value in ipairs({S.SECRET,0/0,math.huge,-math.huge,2}) do
        ns.Radar.MapRead=function() return 'plain',1429,value,.5 end
        assert(p.Paint()=='no_position' and p.Counts()==0)
    end
    ns.Radar.MapRead=mapRead
    for _,value in ipairs({S.SECRET,0/0,math.huge,-math.huge}) do
        ns.Radar.FacingRead=function() return 'plain',value end
        assert(p.Paint()=='no_position' and p.Counts()==0)
    end
    ns.Radar.FacingRead=facingRead; assert(p.Paint()=='ok')
    ns.Radar.MapRead=function() error('client restriction') end
    assert(p.Paint()=='no_position')
end)
test('invalid map dimensions clear safely',function()
    local ns,p=boot()
    for _,value in ipairs({S.SECRET,0/0,math.huge,-math.huge,0}) do
        ns.MapYards=function() return value,600 end
        assert(p.Paint()=='no_position' and p.Counts()==0)
    end
end)

test('position and heading recovery repaint even when the character stays still',function()
    for _,source in ipairs({'map','heading','size'}) do
        local ns,p=boot()
        local original
        if source=='map' then
            original=ns.Radar.MapRead;ns.Radar.MapRead=function()error('temporarily unavailable')end
        elseif source=='heading' then
            original=ns.Radar.FacingRead;ns.Radar.FacingRead=function()return 'secret',S.SECRET end
        else
            original=ns.MapYards;ns.MapYards=function()return nil end
        end
        S.frame(1/60);assert(p.state=='no_position',source)
        if source=='map' then ns.Radar.MapRead=original
        elseif source=='heading' then ns.Radar.FacingRead=original
        else ns.MapYards=original end
        S.frame(1/60)
        assert(p.state=='ok' and p.frame:IsShown(),source..' recovery kept the unavailable note')
    end
end)
test('no data has a status but no polling',function()
    local _,p=boot(true)
    assert(p.state=='no_data' and S.liveUpdates()==0 and p.statusText:GetText()=='no data yet')
    S.fire('ZONE_CHANGED'); assert(p.state=='no_data' and p.frame:IsShown())
    S.fire('PLAYER_LEAVING_WORLD'); assert(not p.frame:IsShown())
    S.fire('PLAYER_ENTERING_WORLD'); assert(p.state=='no_data' and p.frame:IsShown())
end)
test('mode switch and master disable reset preview detail and updates',function()
    local ns,p=boot(); p.SetPreview(true)
    NAGDeathRadarSettings.mode='circle'; ns.Apply()
    assert(not p.preview and not p.detail and not p.frame:IsShown() and ns.RadarFrame:IsShown())
    NAGDeathRadarSettings.radar=false; ns.Apply(); assert(S.liveUpdates()==0)
end)
test('preview works without data and never writes source or saved data',function()
    local ns,p=boot(true)
    local raw,data=NAGDeathData,ns.data
    p.SetPreview(true)
    assert(p.preview and p.state=='ok' and p.label:GetText():find('SYNTHETIC PREVIEW',1,true))
    assert(NAGDeathData==raw and ns.data==data and NAGDeathRadarSettings.preview==nil)
    assert(S.liveUpdates()==1)
    p.SetPreview(false); assert(p.state=='no_data' and S.liveUpdates()==0)
end)
test('preview is frozen while character moves and turns',function()
    local _,p=boot()
    p.SetPreview(true); local distance=p.lastModel.nearestDistance
    S.player.y=.47; S.frame(.11); assert(p.lastModel.nearestDistance<distance)
    S.player.facing=math.pi; S.frame(.11); assert(p.state=='empty')
    S.player.facing=0; S.frame(.11); assert(p.state=='ok')
end)
test('preview stops on map change and returns to real data state',function()
    local _,p=boot(); p.SetPreview(true)
    S.player.map=1411; S.worldBounds[1411]={600,600,0,0}; S.frame(.11)
    assert(not p.preview and p.state=='no_map')
end)
test('pool reuse is bounded with no new widgets on unchanged paints',function()
    local _,p=boot(); local count=#S.objects
    for i=1,20 do S.frame(.11) end
    assert(#S.objects==count)
    local l,t,allL,allT=p.Counts()
    assert(l>0 and t>0 and allL<=p.MAX_LINES and allT<=p.MAX_TRIANGLES)
end)
test('over-budget model fails visibly without partial region drawing',function()
    local ns,p=boot(); local compute=ns.PerspectiveGeometry.Compute
    ns.PerspectiveGeometry.Compute=function(...)
        local m=compute(...)
        for i=#m.strokes+1,p.MAX_LINES+1 do m.strokes[i]=m.strokes[1] end
        return m
    end
    assert(p.Paint()=='complexity' and p.Counts()==0)
    assert(p.statusText:GetText():find('Dense area',1,true))
end)

test('a dense map picture reports the geometry budget failure without a blank view',function()
    local ns,p,runs=boot()
    for i=#runs,1,-1 do runs[i]=nil end
    for y=40,64 do for x=40,89 do
        if (x+y)%2==0 then runs[#runs+1]={x0=x,x1=x,y=y,step=1000} end
    end end
    S.player.x,S.player.y=.325,.4;ns.Apply()
    assert(p.state=='complexity' and p.Counts()==0)
    assert(p.statusText:GetText():find('Dense area',1,true))
end)
test('invalid geometry coordinates never reach UI primitives',function()
    local ns,p=boot(); local count=#S.objects
    ns.PerspectiveGeometry.Compute=function() return {status='ok',strokes={{x1=0/0}},fills={}} end
    assert(p.Paint()=='invalid' and p.Counts()==0 and #S.objects==count)
end)
test('optional vertex method loss produces explicit outline fallback',function()
    local _,p=boot(); local vertex=S.KINDS.TEXTURE.SetVertexOffset
    S.KINDS.TEXTURE.SetVertexOffset=nil
    assert(p.Paint()=='ok' and p.statusText:GetText():find('Outlines only',1,true))
    local _,t=p.Counts(); assert(t==0)
    S.KINDS.TEXTURE.SetVertexOffset=vertex
end)
test('missing native line API fails visibly instead of throwing',function()
    local create=S.KINDS.FRAME.CreateLine
    S.KINDS.FRAME.CreateLine=nil
    local _,p=boot()
    assert(p.state=='unsupported' and p.Counts()==0)
    S.KINDS.FRAME.CreateLine=create
end)
io.write(total..' perspective runtime tests, '..failed..' failed\n')
os.exit(failed==0 and 0 or 1)
