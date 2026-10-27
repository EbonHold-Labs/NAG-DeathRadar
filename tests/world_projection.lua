local ns={};assert(loadfile('NAGDeathRadar/perspective-geometry.lua'))('NAGDeathRadar',ns)
assert(loadfile('NAGDeathRadar/world-projection.lua'))('NAGDeathRadar',ns)
local G=ns.WorldProjection
local count,fail=0,0
local function test(name,f)
    count=count+1;local ok,why=pcall(f)
    if not ok then fail=fail+1;print('FAIL '..name..': '..tostring(why)) end
end
local function near(a,b)assert(math.abs(a-b)<1e-6,tostring(a)..' ~= '..tostring(b))end
local v={px=.5,py=.5,W=600,H=600,facing=0}
test('world readability rejects a thin strip at any angle without inflating it',function()
    for _,angle in ipairs({0,math.pi/3,math.pi/2}) do
        local function model(height)
            local poly={}
            for _,q in ipairs({{0,0},{700,0},{700,height},{0,height}}) do
                poly[#poly+1]={x=800+q[1]*math.cos(angle)-q[2]*math.sin(angle),
                    y=100+q[1]*math.sin(angle)+q[2]*math.cos(angle)}
            end
            return {fills={poly},strokes={}}
        end
        assert(not G.Readable(model(1)))
        assert(G.Readable(model(30)))
    end
end)
test('anchors have four corners, two distinct holdouts, and a repeated first point',function()
    local b,p=G.Anchors(v,0);assert(#p==7)
    near((b.x1-b.x0)*600,36);near((b.y1-b.y0)*600,30)
    near(p[1].x,p[7].x);near(p[1].y,p[7].y)
    for i=5,6 do
        assert(p[i].x>b.x0 and p[i].x<b.x1 and p[i].y>b.y0 and p[i].y<b.y1)
    end
    assert(p[5].x~=p[6].x)
end)
test('fitted projection agrees with an independent camera at both holdouts',function()
    local b,p=G.Anchors(v,0);local samples={}
    local function camera(q)
        local x,y=q.x*600,q.y*600
        return {x=(32+3*x+.6*y)/(1+.002*x+.001*y),y=(20+.3*x+2*y)/(1+.002*x+.001*y)}
    end
    for _,q in ipairs(p) do samples[#samples+1]=camera(q) end
    local h=G.Fit(samples);assert(h);assert(G.Validate(h,p,samples,b)<1e-6)
    samples[5].x=samples[5].x+15;assert(G.Validate(h,p,samples,b)>14)
end)
test('folded, collinear and nonfinite native corners are rejected',function()
    assert(not G.Fit({{x=0,y=0},{x=10,y=10},{x=0,y=10},{x=10,y=0}}))
    assert(not G.Fit({{x=0,y=0},{x=10,y=0},{x=20,y=0},{x=30,y=0}}))
    assert(not G.Fit({{x=0/0,y=0},{x=10,y=0},{x=20,y=0},{x=30,y=0}}))
end)
test('motion compensation fits different sample origins and renders at the current origin',function()
    local bounds,points=G.Anchors(v,0)
    for _,velocity in ipairs({{7,0},{0,-7},{4.2,-5.6},{-4.2,5.6}}) do
        local samples,sources={},{}
        local function camera(q,origin)
            local x,y=(q.x-origin.px)*600,(q.y-origin.py)*600
            local den=1-y*.004
            return {x=(500+8*x)/den,y=(350-4*y)/den}
        end
        local current
        for i=1,7 do
            current={px=v.px+velocity[1]*i/30/600,py=v.py+velocity[2]*i/30/600}
            samples[i]=camera(points[i],current);sources[i]=G.Rebase(points[i],v,current)
        end
        local h=assert(G.FitMoving(samples,sources,bounds))
        assert(G.Validate(h,sources,samples,bounds)<1e-6)
        assert(G.Validate(h,sources,samples,bounds,7,7)<1e-6)
        local shifted=G.ShiftBounds(bounds,v,current)
        local expected=camera(points[5],current)
        local actual=assert(G.Point(h,(points[5].x-shifted.x0)/(shifted.x1-shifted.x0),
            (points[5].y-shifted.y0)/(shifted.y1-shifted.y0)))
        near(actual.x,expected.x);near(actual.y,expected.y)
        local endView={px=current.px,py=current.py,W=600,H=600}
        local function localPoint(q)return {x=(q.x-current.px)*600,y=(q.y-current.py)*600}end
        local mesh={v=endView,inside=false,lines={{localPoint(points[5]),localPoint(points[6])}},fills={}}
        local rendered=assert(G.Render(mesh,h,shifted,2000,1200))
        assert(#rendered.strokes==1)
        near(rendered.strokes[1].x1,expected.x);near(rendered.strokes[1].y1,expected.y)
        local other=camera(points[6],current)
        near(rendered.strokes[1].x2,other.x);near(rendered.strokes[1].y2,other.y)
        samples[7].x=samples[7].x+20
        assert(G.Validate(h,sources,samples,bounds,7,7)>19.9)
    end
end)
test('motion fitting rejects a degenerate or nonfinite source without weakening screen checks',function()
    local samples={{x=10,y=10},{x=210,y=10},{x=210,y=110},{x=10,y=110}}
    local b={x0=0,x1=1,y0=0,y1=1}
    local sources={{x=0,y=0},{x=1,y=0},{x=2,y=0},{x=3,y=0}}
    assert(not G.FitMoving(samples,sources,b))
    sources[3].x=0/0;assert(not G.FitMoving(samples,sources,b))
end)

test('a wide edge-on projection is rejected without inflating its height',function()
    for _,angle in ipairs({0,math.pi/3,math.pi/2}) do
        local p={}
        for _,q in ipairs({{0,0},{900,0},{900,3},{0,3}}) do
            p[#p+1]={x=100+q[1]*math.cos(angle)-q[2]*math.sin(angle),
                y=100+q[1]*math.sin(angle)+q[2]*math.cos(angle)}
        end
        local h,why=G.Fit(p);assert(not h and why=='shallow')
    end
    assert(G.Fit({{x=0,y=0},{x=900,y=0},{x=900,y=30},{x=0,y=30}}))
end)

test('anchor search covers diagonal camera directions and retains the rectangle size',function()
    local centers={}
    for i=0,G.DIRECTIONS-1 do
        local b=assert(G.Anchors(v,i))
        local x,y=((b.x0+b.x1)/2-v.px)*v.W,((b.y0+b.y1)/2-v.py)*v.H
        near(math.sqrt(x*x+y*y),55)
        near((b.x1-b.x0)*v.W,36);near((b.y1-b.y0)*v.H,30)
        centers[#centers+1]={x=x,y=y}
    end
    assert(#centers==8)
    near(centers[2].x,-55/math.sqrt(2));near(centers[2].y,-55/math.sqrt(2))
end)

test('a recorded Forever batch preserves depth and passes independent holdouts',function()
    -- Native replay capture, 2026-10-21, near-replay run 4 last batch. These
    -- screen measurements are regression input, not a fresh client test.
    local b={x0=.46474490161035,x1=.47368193566708,y0=.57160597290095,y1=.5783087484435}
    local points={{x=b.x0,y=b.y0},{x=b.x1,y=b.y0},{x=b.x1,y=b.y1},{x=b.x0,y=b.y1},
        {x=b.x0,y=.57495736067223},{x=.47256480640999,y=.57495736067223}}
    local samples={{x=754.29479980469,y=1000.8862915039},{x=1477.7659912109,y=1036.6362304688},
        {x=1664.5578613281,y=1003.6654052734},{x=773.02081298828,y=945.17401123047},
        {x=762.36395263672,y=976.87927246094},{x=1481.8198242188,y=1017.4356079102}}
    local h=assert(G.Fit(samples))
    assert(G.Validate(h,points,samples,b)<.001)
    for i=1,4 do
        local q=G.Point(h,(points[i].x-b.x0)/(b.x1-b.x0),(points[i].y-b.y0)/(b.y1-b.y0))
        near(q.x,samples[i].x);near(q.y,samples[i].y)
    end
    assert(math.abs(samples[1].y-samples[4].y)>55)
end)
test('range clipping keeps genuine hole boundaries and creates no circular outlines',function()
    local runs={{x0=1,x1=3,y=1,step=1000},{x0=1,x1=1,y=2,step=1000},
        {x0=3,x1=3,y=2,step=1000},{x0=1,x1=3,y=3,step=1000}}
    local p=ns.PerspectiveGeometry.Build(runs,3)
    local vv={px=.5,py=.5,W=300,H=300,facing=0}
    local mesh=G.Near(p,vv,110);assert(not mesh.inside)
    for _,poly in ipairs(mesh.fills) do
        local cx,cy=0,0
        for _,q in ipairs(poly) do cx=cx+q.x;cy=cy+q.y end
        assert(math.abs(cx/#poly)>=50-1e-6 or math.abs(cy/#poly)>=50-1e-6)
    end
    for _,line in ipairs(mesh.lines) do
        for _,q in ipairs(line) do assert(math.abs(math.abs(q.x)-50)<1e-6 or math.abs(math.abs(q.y)-50)<1e-6) end
    end
end)
test('screen clipping bounds every point and drops the hidden side of the horizon',function()
    local mesh={inside=false,v={px=0,py=0,W=1,H=1},lines={{{x=-2,y=1},{x=3,y=1}}},
        fills={{{x=-2,y=-1},{x=3,y=-1},{x=3,y=3},{x=-2,y=3}}}}
    local b={x0=0,x1=1,y0=0,y1=1}
    local h={30,50,0,30,0,50,0,0}
    local m=G.Render(mesh,h,b,100,100)
    assert(#m.strokes==1 and #m.fills==1)
    for _,poly in ipairs(m.fills) do for _,q in ipairs(poly) do
        assert(q.x>=0 and q.x<=100 and q.y>=0 and q.y<=100)
    end end
    h={30,50,0,30,0,50,0,-1}
    m=G.Render(mesh,h,b,100,100)
    assert(m)
    for _,poly in ipairs(m.fills) do for _,q in ipairs(poly) do
        assert(q.x==q.x and q.y==q.y and q.x>=0 and q.x<=100 and q.y>=0 and q.y<=100)
    end end
end)
test('nearby separate regions remain separate fills',function()
    local p=ns.PerspectiveGeometry.Build({{x0=3,x1=3,y=2,step=1000},{x0=6,x1=6,y=2,step=1000}},8)
    local mesh=G.Near(p,{px=.5,py=.5,W=160,H=160},180)
    assert(#mesh.fills==2 and #mesh.lines==8)
end)
test('moved replay rectangles detect inside status and preserve their gaps',function()
    local p={n=200,occupancy={},regions={{x0=.4,x1=.6,y0=.4,y1=.6}},edges={},
        rects={{x0=.4,x1=.45,y0=.4,y1=.6,region=1},{x0=.55,x1=.6,y0=.4,y1=.6,region=1}}}
    local v={px=.425,py=.5,W=600,H=600}
    assert(G.Near(p,v,180).inside)
    v.px=.5;assert(not G.Near(p,v,180).inside)
end)
print(('World projection: %d checks, %d failures'):format(count,fail))
if fail>0 then os.exit(1) end
