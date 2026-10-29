-- Shared map/perspective source and integration controls. No live data-file reads.
local S = assert(loadfile('tests/wowstub.lua'))()
local count, failed = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if not ok then failed = failed + 1; io.write('FAIL '..name..': '..tostring(err)..'\n') end
end
local function boot(fixture)
    S.reset()
    if fixture then assert(loadfile('tests/fixtures/'..fixture))() end
    local ns = {}
    for _,name in ipairs({'core','options','overlay','radar','perspective-geometry'}) do
        assert(loadfile('NAGDeathRadar/'..name..'.lua'))('NAGDeathRadar',ns)
    end
    NAGDeathRadarSettings={mode='perspective',lookVersion=1} -- these tests drive the perspective view
    S.fire('ADDON_LOADED','NAGDeathRadar')
    return ns
end

test('circle default (owner 2026-10-29) preserves old settings and validates all layout ranges',function()
    local ns=boot()
    local s=ns.InitSettings({radar=false,ring=8,yards=150,custom='kept',reach=0,viewWidth=0,viewHeight=0,
        viewScale=1/0,viewX=0/0,viewY=1e20})
    assert(s.mode=='circle' and s.reach==180 and s.viewWidth==720 and s.viewHeight==160)
    assert(s.viewScale==1 and s.viewX==0 and s.viewY==60)
    assert(s.radar==false and s.ring==8 and s.yards==150 and s.custom=='kept')
    assert(ns.InitSettings({mode='bad'}).mode=='circle')
    assert(ns.InitSettings({mode='perspective',lookVersion=1}).mode=='perspective')
    assert(ns.InitSettings({mode='circle'}).mode=='circle')
end)

test('front layout migrates old defaults once and preserves custom layout',function()
    local ns=boot()
    local old=ns.InitSettings({viewHeight=280,viewY=-200,viewX=12,reach=240})
    assert(old.viewHeight==160 and old.viewY==60 and old.viewX==12 and old.reach==240)
    local custom=ns.InitSettings({viewHeight=210,viewY=286,viewX=32})
    assert(custom.viewHeight==210 and custom.viewY==286 and custom.viewX==32)
    old.viewHeight,old.viewY=280,-200
    ns.InitSettings(old)
    assert(old.viewHeight==280 and old.viewY==-200,'explicit old values must survive subsequent loads')
end)

test('near-feet preset moves up once while manually adjusted layouts stay',function()
    local ns=boot()
    local s=ns.InitSettings({viewY=-400,viewHeight=160,viewX=0,viewLayoutVersion=1})
    assert(s.viewY==60 and s.viewHeight==160 and s.viewLayoutVersion==3)
    s.viewY=-400; ns.InitSettings(s); assert(s.viewY==-400)
    local custom=ns.InitSettings({viewY=-175,viewHeight=210,viewX=32,viewLayoutVersion=1})
    assert(custom.viewY==-175 and custom.viewHeight==210 and custom.viewX==32 and custom.viewLayoutVersion==3)
end)

test('centre preset moves higher once and preserves custom offsets',function()
    local ns=boot()
    local s=ns.InitSettings({viewY=0,viewLayoutVersion=2})
    assert(s.viewY==60 and s.viewLayoutVersion==3)
    s.viewY=0; ns.InitSettings(s); assert(s.viewY==0)
    local custom=ns.InitSettings({viewY=40,viewLayoutVersion=2})
    assert(custom.viewY==40 and custom.viewLayoutVersion==3)
end)

test('front command and ground alias change only position and height, without a full reset',function()
    local ns=boot()
    local s=ns.InitSettings({viewX=32,viewY=286,viewHeight=210,viewWidth=900,viewScale=1.3,
        reach=240,hot=.4,mode='circle',radar=false})
    ns.Command(s,'front extra'); assert(s.viewY==286 and s.viewHeight==210)
    ns.Command(s,'front')
    assert(s.viewX==0 and s.viewY==60 and s.viewHeight==160)
    s.viewY=286; ns.Command(s,'ground'); assert(s.viewY==60)
    assert(s.viewWidth==900 and s.viewScale==1.3 and s.reach==240 and s.hot==.4)
    assert(s.mode=='circle' and s.radar==false)
end)

test('slash layout controls validate finite values and preserve the circle range separately',function()
    local ns=boot(); local s=ns.InitSettings(nil)
    for command,key in pairs({reach='reach',width='viewWidth',height='viewHeight',size='viewScale',x='viewX',y='viewY'}) do
        local before=s[key]
        for _,bad in ipairs({'nan','inf','-inf','1e99'}) do
            s=ns.Command(s,command..' '..bad); assert(s[key]==before,command..' '..bad)
        end
    end
    s=ns.Command(s,'mode circle'); assert(s.mode=='circle')
    s=ns.Command(s,'mode radar'); assert(s.mode=='circle')
    s=ns.Command(s,'mode invalid'); assert(s.mode=='circle')
    s=ns.Command(s,'mode perspective'); assert(s.mode=='perspective')
    s=ns.Command(s,'reach 240'); assert(s.reach==240 and s.yards==100)
    s=ns.Command(s,'width 900'); s=ns.Command(s,'height 350'); s=ns.Command(s,'size 1.2')
    s=ns.Command(s,'x -100'); s=ns.Command(s,'y -250')
    assert(s.viewWidth==900 and s.viewHeight==350 and s.viewScale==1.2 and s.viewX==-100 and s.viewY==-250)
    local _,_,action=ns.Command(s,'preview on'); assert(action=='preview-on')
    local _,_,toggle=ns.Command(s,'preview'); assert(toggle=='preview-toggle')
end)

for _,fixture in ipairs({'nagdeath_base0.lua','nagdeath_fine.lua'}) do
    for _,threshold in ipairs({.05,.25,.8}) do
        for _,cap in ipairs({2500,3}) do
            test(fixture..' threshold '..threshold..' cap '..cap..' has the exact rendered red mask',function()
                local ns=boot(fixture); local s=NAGDeathRadarSettings
                s.hot=threshold; ns.Overlay.CAP=cap
                local runs,n=ns.Overlay.Picture(1429,s)
                assert(runs and n and n<=200)
                local p=ns.PerspectiveGeometry.Build(runs,n); assert(p.valid)
                local expected={}
                for _,r in ipairs(runs) do if r.step>=1000 then
                    for x=r.x0,r.x1 do expected[(r.y-1)*n+x]=true end
                end end
                for y=1,n do for x=1,n do
                    assert((p.occupancy[y][x]~=nil)==(expected[(y-1)*n+x] or false),'mask mismatch')
                end end
                s.overlay=false; WorldMapFrame:Hide()
                local hiddenRuns,hiddenN=ns.Overlay.Picture(1429,s)
                assert(hiddenRuns==runs and hiddenN==n,'independent of map visibility/toggle')
                s.mapAlpha=.4
                local fadedRuns,fadedN=ns.Overlay.Picture(1429,s)
                local faded=ns.PerspectiveGeometry.Build(fadedRuns,fadedN)
                assert(faded.n==p.n)
                for y=1,n do for x=1,n do
                    assert((faded.occupancy[y][x]~=nil)==(p.occupancy[y][x]~=nil),'map opacity changes mask')
                end end
            end)
        end
    end
end

test('view settings panel updates sliders and mode without altering circle range',function()
    local ns=boot('nagdeath_base0.lua'); S.fire('PLAYER_LOGIN')
    local panel=S.panels[1].panel
    panel.viewSliders.reach._scripts.OnValueChanged(panel.viewSliders.reach,220,true)
    assert(NAGDeathRadarSettings.reach==220 and NAGDeathRadarSettings.yards==100)
    assert(panel.viewSliders.reach:GetValue()==220)
    assert(panel.modeButtons.perspective:GetText()=='[x] Perspective')
    panel.modeButtons.circle._scripts.OnClick()
    assert(NAGDeathRadarSettings.mode=='circle' and ns.RadarFrame:IsShown())
    assert(panel.modeButtons.circle:GetText()=='[x] Radar')
    panel.modeButtons.perspective._scripts.OnClick()
    assert(NAGDeathRadarSettings.mode=='perspective' and not ns.RadarFrame:IsShown())
    SlashCmdList.NAGDEATHRADAR('mode radar')
    assert(ns.RadarFrame:IsShown() and panel.modeButtons.circle:GetText()=='[x] Radar')
end)

test('detail binding has key-up handling and never assigns keys automatically',function()
    local f=assert(io.open('NAGDeathRadar/Bindings.xml')); local xml=f:read('*a'); f:close()
    assert(xml:find('name="NAGDEATHRADAR_DETAIL"',1,true))
    assert(xml:find('runOnUp="true"',1,true))
    assert(xml:find('keystate == "down"',1,true))
    assert(not xml:find('SetBinding',1,true))
end)

io.write(count..' shared-source/control tests, '..failed..' failed\n')
os.exit(failed==0 and 0 or 1)
