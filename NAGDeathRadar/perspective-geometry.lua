-- Pure geometry; no WoW APIs. Map coordinates are normalized, screen y grows
-- from the player (0) toward the horizon (height). This is an illustrative
-- character-heading projection, not the actual gameplay camera or terrain.
local _, ns = ...
local G = {}
ns.PerspectiveGeometry = G
local abs, sqrt, min, max = math.abs, math.sqrt, math.min, math.max
local EPS, TAN = 1e-8, math.sqrt(3)
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function integer(v) return finite(v) and v==math.floor(v) end

-- Prepared fields are deliberately exposed for deterministic tests:
-- occupancy[y][x] = 4-connected region id; regions[id].cells = cell count;
-- edges use x1/y1/x2/y2, rects use x0/y0/x1/y1 (all normalized), plus region.
-- Rectangles exactly cover the hot cells; holes and diagonal gaps stay empty.
function G.Build(runs,n)
    local p={valid=false,n=n,occupancy={},regions={},edges={},rects={}}
    if not integer(n) or n<1 or type(runs)~='table' then return p end
    -- Match the capped map-picture contract before allocating its occupancy
    -- grid. Over-budget inputs must not leak partially prepared geometry.
    if n>200 or #runs>2500 then p.reason='complexity'; return p end
    local grid=p.occupancy
    for y=1,n do grid[y]={} end
    for _,r in ipairs(runs) do
        if type(r)~='table' or not integer(r.x0) or not integer(r.x1) or not integer(r.y)
            or not finite(r.step) or r.x0<1 or r.x1<r.x0 or r.x1>n or r.y<1 or r.y>n then return p end
        if r.step>=1000 then for x=r.x0,r.x1 do grid[r.y][x]=0 end end
    end
    local function cell(x,y) return grid[y] and grid[y][x] end
    for y=1,n do for x=1,n do if cell(x,y)==0 then
        local id=#p.regions+1
        local region={id=id,cells=0,x0=(x-1)/n,x1=x/n,y0=(y-1)/n,y1=y/n}; p.regions[id]=region
        local qx,qy={x},{y}; grid[y][x]=id
        local head=1
        while head<=#qx do
            local cx,cy=qx[head],qy[head]; head=head+1; region.cells=region.cells+1
            region.x0=min(region.x0,(cx-1)/n); region.x1=max(region.x1,cx/n)
            region.y0=min(region.y0,(cy-1)/n); region.y1=max(region.y1,cy/n)
            local function visit(nx,ny)
                if cell(nx,ny)==0 then grid[ny][nx]=id; qx[#qx+1]=nx; qy[#qy+1]=ny end
            end
            visit(cx-1,cy); visit(cx+1,cy); visit(cx,cy-1); visit(cx,cy+1)
        end
    end end end
    -- Scan grid lines and join collinear exterior segments. Shared cell edges
    -- are absent, including shared edges between distinct source runs.
    for y=0,n do
        local start,rid
        for x=1,n+1 do
            local above,below=cell(x,y),cell(x,y+1)
            local id=(above~=below) and (above or below) or nil
            if id~=rid then
                if rid then p.edges[#p.edges+1]={x1=(start-1)/n,y1=y/n,x2=(x-1)/n,y2=y/n,region=rid} end
                start,rid=x,id
            end
        end
    end
    for x=0,n do
        local start,rid
        for y=1,n+1 do
            local left,right=cell(x,y),cell(x+1,y)
            local id=(left~=right) and (left or right) or nil
            if id~=rid then
                if rid then p.edges[#p.edges+1]={x1=x/n,y1=(start-1)/n,x2=x/n,y2=(y-1)/n,region=rid} end
                start,rid=y,id
            end
        end
    end
    -- Merge matching horizontal spans vertically without bridging a hole.
    local previous={}
    for y=1,n do
        local current={}; local x=1
        while x<=n do
            local id=cell(x,y)
            if id then
                local first=x
                repeat x=x+1 until x>n or cell(x,y)~=id
                local key=id..':'..first..':'..x
                local rect=previous[key]
                if rect then rect.y1=y/n else
                    rect={x0=(first-1)/n,x1=(x-1)/n,y0=(y-1)/n,y1=y/n,region=id}
                    p.rects[#p.rects+1]=rect
                end
                current[key]=rect
            else x=x+1 end
        end
        previous=current
    end
    p.valid=true
    return p
end

-- Sutherland-Hodgman half-plane clipping, with a*f+b*r+c >= 0.
local function clipPoly(poly,a,b,c)
    local out={}
    if #poly==0 then return out end
    local previous=poly[#poly]; local pd=a*previous.f+b*previous.r+c
    for _,point in ipairs(poly) do
        local d=a*point.f+b*point.r+c
        if (d>=0)~=(pd>=0) then
            local t=pd/(pd-d)
            out[#out+1]={f=previous.f+(point.f-previous.f)*t,r=previous.r+(point.r-previous.r)*t}
        end
        if d>=0 then out[#out+1]=point end
        previous,pd=point,d
    end
    return out
end
local function clipCirclePoly(poly,radius)
    -- 48-sided inscribed circle: bounded sub-yard approximation at 180 yd.
    local apothem=radius*math.cos(math.pi/48)
    for i=0,47 do
        local a=(i+.5)*2*math.pi/48
        poly=clipPoly(poly,-math.cos(a),-math.sin(a),apothem)
        if #poly<3 then return {} end
    end
    return poly
end
local function hasArea(poly)
    if #poly<3 then return false end
    local area=0
    local previous=poly[#poly]
    for _,point in ipairs(poly) do
        area=area+previous.f*point.r-point.f*previous.r
        previous=point
    end
    return abs(area)>EPS
end
local function clipSegment(a,b,range)
    local df,dr=b.f-a.f,b.r-a.r
    local lo,hi=0,1
    local function plane(c,d)
        if abs(d)<EPS then return c>=0 end
        local t=-c/d
        if d>0 then lo=max(lo,t) else hi=min(hi,t) end
        return lo<=hi
    end
    if not plane(a.f,df) or not plane(TAN*a.f-a.r,TAN*df-dr)
        or not plane(TAN*a.f+a.r,TAN*df+dr) then return end
    local aa=df*df+dr*dr
    if aa<EPS then return end
    local bb=2*(a.f*df+a.r*dr)
    local cc=a.f*a.f+a.r*a.r-range*range
    local disc=bb*bb-4*aa*cc
    if disc<0 then return end
    local root=sqrt(max(0,disc))
    lo=max(lo,(-bb-root)/(2*aa)); hi=min(hi,(-bb+root)/(2*aa))
    if hi-lo<EPS then return end
    return {f=a.f+df*lo,r=a.r+dr*lo},{f=a.f+df*hi,r=a.r+dr*hi}
end
local function boundaryDistance(a,b)
    local df,dr=b.f-a.f,b.r-a.r
    local length=df*df+dr*dr
    local t=length>0 and max(0,min(1,-(a.f*df+a.r*dr)/length)) or 0
    local f,r=a.f+t*df,a.r+t*dr
    return sqrt(f*f+r*r)
end

function G.Compute(p,v,opts)
    local result={status='invalid',inside=false,strokes={},fills={}}
    if type(p)~='table' or not p.valid or type(v)~='table' or type(opts)~='table' then return result end
    for _,k in ipairs({'px','py','W','H','facing'}) do if not finite(v[k]) then return result end end
    for _,k in ipairs({'range','width','height'}) do
        if not finite(opts[k]) or opts[k]<1 or opts[k]>10000 then return result end
    end
    if v.px<0 or v.px>1 or v.py<0 or v.py>1 or v.W<1 or v.H<1 or v.W>1e7 or v.H>1e7
        or abs(v.facing)>1e7 then return result end
    local range,width,height=opts.range,opts.width,opts.height
    local cos,sin=math.cos(v.facing),math.sin(v.facing)
    local function relative(x,y)
        local north,west=(v.py-y)*v.H,(v.px-x)*v.W
        return {f=north*cos+west*sin,r=north*sin-west*cos}
    end
    local depth=40
    local yscale=height*(depth+range)/range
    local xscale=width*(depth+range)/(2*TAN*range)
    local function project(point)
        local den=depth+point.f
        return {x=max(0,min(width,width/2+point.r*xscale/den)),y=max(0,min(height,point.f*yscale/den))}
    end
    local row=p.occupancy[min(p.n,math.floor(v.py*p.n)+1)]
    local inside=row and row[min(p.n,math.floor(v.px*p.n)+1)]
    result.inside=inside~=nil
    local candidates={}
    for id,region in ipairs(p.regions) do
        local dx=max(0,region.x0-v.px,v.px-region.x1)*v.W
        local dy=max(0,region.y0-v.py,v.py-region.y1)*v.H
        if dx*dx+dy*dy<=range*range or id==inside then candidates[id]=true end
    end
    local visible,distances={},{}
    local segments={}
    for _,edge in ipairs(p.edges) do
        if candidates[edge.region] then
        local a,b=relative(edge.x1,edge.y1),relative(edge.x2,edge.y2)
        local distance=boundaryDistance(a,b)
        distances[edge.region]=min(distances[edge.region] or math.huge,distance)
        local ca,cb=clipSegment(a,b,range)
        if ca then
            visible[edge.region]=true
            segments[#segments+1]={a=ca,b=cb,region=edge.region}
        end
        end
    end
    local polygons={}
    for _,rect in ipairs(p.rects) do
        if candidates[rect.region] then
        if v.px>=rect.x0 and v.px<rect.x1 and v.py>=rect.y0 and v.py<rect.y1 then
            inside=rect.region;result.inside=true
        end
        local poly={relative(rect.x0,rect.y0),relative(rect.x1,rect.y0),relative(rect.x1,rect.y1),relative(rect.x0,rect.y1)}
        poly=clipPoly(poly,1,0,0); poly=clipPoly(poly,TAN,-1,0); poly=clipPoly(poly,TAN,1,0)
        if hasArea(poly) then
            local clipped=clipCirclePoly(poly,range)
            if hasArea(clipped) then
                visible[rect.region]=true
                polygons[#polygons+1]={poly=poly,region=rect.region}
            end
        end
        end
    end
    local nearest,nearestDistance
    if inside then nearest,nearestDistance=inside,distances[inside] else
        for id in pairs(visible) do
            if not nearestDistance or distances[id]<nearestDistance or (distances[id]==nearestDistance and id<nearest) then
                nearest,nearestDistance=id,distances[id]
            end
        end
    end
    result.nearestRegion,result.nearestDistance=nearest,nearestDistance
    for _,segment in ipairs(segments) do
        local df,dr=segment.b.f-segment.a.f,segment.b.r-segment.a.r
        -- Subdivide only existing contour edges. A long edge can pass close to
        -- the player and reach the outer radius: each part needs its own fade.
        local pieces=max(1,math.ceil(sqrt(df*df+dr*dr)/8))
        for piece=1,pieces do
            local t0,t1=(piece-1)/pieces,piece/pieces
            local pa={f=segment.a.f+df*t0,r=segment.a.r+dr*t0}
            local pb={f=segment.a.f+df*t1,r=segment.a.r+dr*t1}
            local a,b=project(pa),project(pb)
            local mf,mr=(pa.f+pb.f)/2,(pa.r+pb.r)/2
            local radius=sqrt(mf*mf+mr*mr)
            local fade=max(0,min(1,(range-radius)/(range*.25)))
            local alpha=(segment.region==nearest and .8 or .45)*(opts.detail and 1.2 or 1)*(.12+.88*fade)
            result.strokes[#result.strokes+1]={x1=a.x,y1=a.y,x2=b.x,y2=b.y,alpha=min(1,alpha),region=segment.region}
        end
    end
    -- Nested translucent fills make the outer range fade without introducing
    -- any contour at those clipping limits. All original holes remain empty.
    local bands={{1,.018},{.93,.028},{.82,.044}}
    for _,polygon in ipairs(polygons) do for _,band in ipairs(bands) do
        local poly=clipCirclePoly(polygon.poly,range*band[1])
        if hasArea(poly) then
            local points={}; for _,point in ipairs(poly) do points[#points+1]=project(point) end
            result.fills[#result.fills+1]={points=points,alpha=band[2]*(polygon.region==nearest and 1.35 or 1)*(opts.detail and 2 or 1),region=polygon.region}
        end
    end end
    result.status=(inside or #result.strokes>0 or #result.fills>0) and 'ok' or 'empty'
    return result
end
