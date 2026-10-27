-- Standalone pure-Lua geometry regression suite. Run from the repository root.
local ns = {}
local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, why = pcall(fn)
    if not ok then failures = failures + 1; print('FAIL '..name..': '..tostring(why)) end
end
local function eq(a,b) assert(a == b, tostring(a)..' ~= '..tostring(b)) end
local function near(a,b) assert(math.abs(a-b)<0.00001,tostring(a)..' ~= '..tostring(b)) end
local function run(x0,x1,y,step) return {x0=x0,x1=x1,y=y,step=step or 1000} end
local loaded, problem = pcall(function() assert(loadfile('NAGDeathRadar/perspective-geometry.lua'))('NAGDeathRadar',ns) end)
if not loaded then print('FAIL load: '..tostring(problem)); os.exit(1) end
local G=ns.PerspectiveGeometry
local function view(px,py,w,h,f) return {px=px,py=py,W=w or 100,H=h or 100,facing=f or 0} end
local opts={range=180,width=720,height=280}

test('empty and threshold',function()
    local p=G.Build({run(1,1,1,999)},2)
    eq(#p.regions,0); eq(G.Compute(p,view(.5,.5),opts).status,'empty')
    eq(#G.Build({run(1,1,1,1000)},2).regions,1)
end)
test('adjacent cells merge, diagonal cells stay separate',function()
    local p=G.Build({run(1,2,1),run(3,3,2)},3)
    eq(#p.regions,2); eq(#p.edges,8); eq(#p.rects,2)
end)
test('hole keeps inner boundary and no fill',function()
    local p=G.Build({run(1,3,1),run(1,1,2),run(3,3,2),run(1,3,3)},3)
    eq(#p.regions,1); eq(#p.edges,8); eq(p.occupancy[2][2],nil)
    for _,r in ipairs(p.rects) do
        assert(not (.5>r.x0 and .5<r.x1 and .5>r.y0 and .5<r.y1))
    end
end)
test('rectangle merge removes internal edges',function()
    local p=G.Build({run(1,3,1),run(1,3,2),run(1,3,3)},3)
    eq(#p.edges,4); eq(#p.rects,1)
end)
test('nearest is boundary, not centre',function()
    local p=G.Build({run(5,6,4)},10)
    local c=G.Compute(p,view(.5,.5),opts)
    eq(c.status,'ok'); eq(c.inside,false); near(c.nearestDistance,10)
end)
test('rotation and nonsquare metrics',function()
    local p=G.Build({run(3,3,5)},10)
    local north=G.Compute(p,view(.5,.5,200,100,0),opts)
    eq(north.status,'empty')
    local west=G.Compute(p,view(.5,.5,200,100,math.pi/2),opts)
    eq(west.status,'ok'); near(west.nearestDistance,40)
end)
test('behind, outside wide field, and beyond range hidden',function()
    eq(G.Compute(G.Build({run(5,5,8)},10),view(.5,.5),opts).status,'empty')
    eq(G.Compute(G.Build({run(1,1,5)},10),view(.5,.5),opts).status,'empty')
    eq(G.Compute(G.Build({run(5,5,1)},10),view(.5,.9,1000,1000),opts).status,'empty')
end)
test('behind region touching view origin has no phantom fill',function()
    local c=G.Compute(G.Build({run(5,5,6)},10),view(.5,.5),opts)
    eq(c.status,'empty'); eq(#c.fills,0); eq(#c.strokes,0)
end)
test('north aligns with screen centre and east appears right',function()
    local c=G.Compute(G.Build({run(5,6,3)},10),view(.5,.7),opts)
    local left,right=720,0
    for _,s in ipairs(c.strokes) do left=math.min(left,s.x1,s.x2); right=math.max(right,s.x1,s.x2) end
    near(360-left,right-360)
    local east=G.Compute(G.Build({run(7,7,3)},10),view(.5,.7),opts)
    for _,s in ipairs(east.strokes) do assert(s.x1>360 and s.x2>360) end
end)
test('all visible disconnected regions retained',function()
    local runs={run(3,3,2),run(5,5,2),run(7,7,2)}
    local c=G.Compute(G.Build(runs,10),view(.5,.8),opts)
    local ids={}; for _,f in ipairs(c.fills) do ids[f.region]=true end
    local n=0; for _ in pairs(ids) do n=n+1 end; eq(n,3)
end)
test('clipping never invents closing contour edges',function()
    -- Huge filled region contains the entire viewing radius. Only fills, no
    -- original boundaries within range; clipping must not add a ring/triangle.
    local p=G.Build({run(1,1,1)},1)
    local c=G.Compute(p,view(.5,.5,2000,2000),opts)
    eq(c.status,'ok'); eq(c.inside,true); eq(#c.strokes,0)
    assert(#c.fills>0); near(c.nearestDistance,1000)
end)
test('range and viewport clipping finite, detail increases alpha',function()
    local p=G.Build({run(2,8,1),run(2,8,2)},10)
    local c=G.Compute(p,view(.5,.5,500,500),opts)
    local d=G.Compute(p,view(.5,.5,500,500),{range=180,width=720,height=280,detail=true})
    eq(c.status,'ok'); assert(#c.strokes>0); eq(#c.strokes,#d.strokes)
    for i,s in ipairs(c.strokes) do
        assert(s.x1>=0 and s.x1<=720 and s.x2>=0 and s.x2<=720)
        assert(s.y1>=0 and s.y1<=280 and s.y2>=0 and s.y2<=280)
        assert(d.strokes[i].alpha>=s.alpha)
    end
end)
test('invalid inputs distinguished from empty',function()
    for _,v in ipairs({view(0/0,.5),view(.5,.5,0),view(1.1,.5),view(.5,.5,math.huge)}) do
        eq(G.Compute(G.Build({},10),v,opts).status,'invalid')
    end
    eq(G.Compute(G.Build({run(0,1,1)},10),view(.5,.5),opts).status,'invalid')
    eq(G.Compute(G.Build({},0),view(.5,.5),opts).status,'invalid')
    eq(G.Compute(G.Build({},10),view(.5,.5),{range=0,width=720,height=280}).status,'invalid')
end)
test('extreme finite values rejected before arithmetic',function()
    local p=G.Build({},10)
    for _,key in ipairs({'W','H','facing'}) do
        local v=view(.5,.5); v[key]=1e308
        eq(G.Compute(p,v,opts).status,'invalid')
    end
    for _,key in ipairs({'range','width','height'}) do
        local o={range=180,width=720,height=280}; o[key]=1e308
        eq(G.Compute(p,view(.5,.5),o).status,'invalid')
        o[key]=1e-308
        eq(G.Compute(p,view(.5,.5),o).status,'invalid')
    end
    eq(G.Build({},401).valid,false)
end)
test('long true contour stays strong near player and fades at range',function()
    -- Rectangle's left boundary runs from 10yd in front to beyond range.
    local runs={}; for y=1,49 do runs[#runs+1]=run(51,70,y) end
    local c=G.Compute(G.Build(runs,100),view(.5,.5,1000,1000),opts)
    local nearAlpha,farAlpha=0,1
    for _,s in ipairs(c.strokes) do
        if math.abs(s.x1-360)<.0001 and math.abs(s.x2-360)<.0001 then
            if math.min(s.y1,s.y2)<100 then nearAlpha=math.max(nearAlpha,s.alpha) end
            if math.max(s.y1,s.y2)>275 then farAlpha=math.min(farAlpha,s.alpha) end
        end
    end
    assert(nearAlpha>.7,'near contour faded: '..nearAlpha)
    assert(farAlpha<.3,'far contour too bright: '..farAlpha)
end)
test('over-budget picture rejected before occupancy allocation',function()
    local runs={}
    for y=1,400 do for x=1,400 do
        if (x+y)%2==0 then runs[#runs+1]=run(x,x,y) end
    end end
    local p=G.Build(runs,400)
    eq(p.valid,false); eq(p.reason,'complexity')
    eq(next(p.occupancy),nil); eq(#p.regions,0); eq(#p.edges,0); eq(#p.rects,0)
    local tooMany={}; for i=1,2501 do tooMany[i]=run(1,1,1) end
    p=G.Build(tooMany,200)
    eq(p.valid,false); eq(p.reason,'complexity'); eq(next(p.occupancy),nil)
end)
test('maximum allowed fragmented input bounds component count',function()
    local runs={}
    for y=1,50 do for x=1,100 do
        if (x+y)%2==0 then runs[#runs+1]=run(x,x,y) end
    end end
    eq(#runs,2500)
    local p=G.Build(runs,200)
    eq(p.valid,true); eq(#p.regions,2500)
    assert(#p.regions<=#runs)
end)
print(string.format('%d geometry tests, %d failed',count,failures))
if failures>0 then os.exit(1) end
