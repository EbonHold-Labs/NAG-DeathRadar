-- Pure projection maths for the experimental native navigation anchors.
-- Agreement with a waypoint projection is not proof of terrain height.
-- License: CC BY-NC 4.0
local _, ns = ...
local G = {}
ns.WorldProjection = G
local abs, min, max, sqrt = math.abs, math.min, math.max, math.sqrt
local function finite(x) return type(x)=='number' and x==x and abs(x)<1e10 end

-- Reference rectangle and two distinct holdouts. Map axes are east/south.
G.DIRECTIONS=8
function G.Anchors(v, quadrant)
    local a=v.facing+(quadrant or 0)*2*math.pi/G.DIRECTIONS
    local x,y=v.px-math.sin(a)*55/v.W,v.py-math.cos(a)*55/v.H
    local b={x0=x-18/v.W,x1=x+18/v.W,y0=y-15/v.H,y1=y+15/v.H}
    if b.x0<0 or b.x1>1 or b.y0<0 or b.y1>1 then return end
    return b,{{x=b.x0,y=b.y0},{x=b.x1,y=b.y0},{x=b.x1,y=b.y1},{x=b.x0,y=b.y1},
        {x=b.x0+(b.x1-b.x0)*.27,y=b.y0+(b.y1-b.y0)*.41},
        {x=b.x0+(b.x1-b.x0)*.73,y=b.y0+(b.y1-b.y0)*.62},{x=b.x0,y=b.y0}}
end

-- Unit square -> native screen quadrilateral; fitting excludes both holdouts.
function G.Fit(p)
    if type(p)~='table' or #p<4 then return end
    for i=1,4 do if not finite(p[i].x) or not finite(p[i].y) then return end end
    local a,b,c,d=p[1],p[2],p[3],p[4]
    local dx,dy=a.x-b.x+c.x-d.x,a.y-b.y+c.y-d.y
    local ex,ey=b.x-c.x,b.y-c.y
    local fx,fy=d.x-c.x,d.y-c.y
    local den=ex*fy-fx*ey
    if abs(den)<1 then return end
    local g,h=(dx*fy-fx*dy)/den,(ex*dy-dx*ey)/den
    if not finite(g) or not finite(h) or min(1+g,1+h,1+g+h)<.01 then return end
    -- Cross products alone accept very wide, nearly flat strips. Measure the
    -- reference plane's thickness in UI units, independent of its orientation.
    -- Do not inflate the mask to compensate for a shallow camera angle.
    local sign,area,span= nil,0,0
    for i=1,4 do
        local q,r,s=p[i],p[i%4+1],p[(i+1)%4+1]
        local cross=(r.x-q.x)*(s.y-r.y)-(r.y-q.y)*(s.x-r.x)
        if abs(cross)<4 or (sign and cross*sign<=0) then return end
        sign=cross
        area=area+q.x*r.y-r.x*q.y
        for j=i+1,4 do
            local t=p[j];span=max(span,(t.x-q.x)^2+(t.y-q.y)^2)
        end
    end
    if abs(area)/(2*sqrt(span))<6 then return nil,'shallow' end
    return {a.x,b.x-a.x+g*b.x,d.x-a.x+h*d.x,a.y,b.y-a.y+g*b.y,d.y-a.y+h*d.y,g,h}
end
function G.Point(h,u,v)
    local w=1+h[7]*u+h[8]*v
    if not finite(w) or w<.001 then return end
    local x,y=(h[1]+h[2]*u+h[3]*v)/w,(h[4]+h[5]*u+h[6]*v)/w
    if finite(x) and finite(y) then return {x=x,y=y} end
end
-- Four samples collected while running have four different camera origins.
-- Express their map positions relative to the player at each measurement, then
-- fit those arbitrary source points. The screen-quality checks remain intact;
-- neither the two spatial holdouts nor the repeated anchor enters this fit.
function G.FitMoving(samples,points,bounds)
    local quality,why=G.Fit(samples)
    if not quality then return nil,why end
    local x0,y0=samples[1].x,samples[1].y
    local scale=1
    for i=2,4 do scale=max(scale,abs(samples[i].x-x0),abs(samples[i].y-y0)) end
    local rows={}
    for i=1,4 do
        local p=points[i]
        if not p or not finite(p.x) or not finite(p.y) then return end
        local u,v=(p.x-bounds.x0)/(bounds.x1-bounds.x0),(p.y-bounds.y0)/(bounds.y1-bounds.y0)
        local x,y=(samples[i].x-x0)/scale,(samples[i].y-y0)/scale
        rows[#rows+1]={1,u,v,0,0,0,-x*u,-x*v,x}
        rows[#rows+1]={0,0,0,1,u,v,-y*u,-y*v,y}
    end
    for col=1,8 do
        local pivot=col
        for row=col+1,8 do if abs(rows[row][col])>abs(rows[pivot][col]) then pivot=row end end
        if not finite(rows[pivot][col]) or abs(rows[pivot][col])<1e-9 then return end
        rows[col],rows[pivot]=rows[pivot],rows[col]
        local d=rows[col][col]
        for j=col,9 do rows[col][j]=rows[col][j]/d end
        for row=1,8 do if row~=col then
            local f=rows[row][col]
            for j=col,9 do rows[row][j]=rows[row][j]-f*rows[col][j] end
        end end
    end
    local a={};for i=1,8 do a[i]=rows[i][9];if not finite(a[i]) then return end end
    local h={scale*a[1]+x0,scale*a[2]+x0*a[7],scale*a[3]+x0*a[8],
        scale*a[4]+y0,scale*a[5]+y0*a[7],scale*a[6]+y0*a[8],a[7],a[8]}
    for i=1,4 do
        if not G.Point(h,(points[i].x-bounds.x0)/(bounds.x1-bounds.x0),
            (points[i].y-bounds.y0)/(bounds.y1-bounds.y0)) then return end
    end
    return h
end
function G.Rebase(point,origin,current)
    return {x=point.x+origin.px-current.px,y=point.y+origin.py-current.py}
end
function G.ShiftBounds(bounds,origin,current)
    local dx,dy=current.px-origin.px,current.py-origin.py
    return {x0=bounds.x0+dx,x1=bounds.x1+dx,y0=bounds.y0+dy,y1=bounds.y1+dy}
end
-- A projected area that has collapsed into a thin strip is not a useful world
-- risk surface. Measure total filled area against its screen extent; never
-- stretch the mask to disguise a shallow camera. Direction view can take over.
function G.Readable(model)
    local area,x0,x1,y0,y1=0,math.huge,-math.huge,math.huge,-math.huge
    for _,poly in ipairs(model.fills) do
        local a=poly[#poly];local sum=0
        for _,b in ipairs(poly) do
            sum=sum+a.x*b.y-b.x*a.y;a=b
            x0=min(x0,b.x);x1=max(x1,b.x);y0=min(y0,b.y);y1=max(y1,b.y)
        end
        area=area+abs(sum)/2
    end
    if #model.fills==0 then return model.inside and #model.strokes==0 end
    local span=sqrt((x1-x0)^2+(y1-y0)^2)
    return span>0 and area/span>=8
end
function G.Validate(h,points,samples,bounds,first,last)
    local worst=0
    for i=first or 5,last or 6 do
        local q=points[i]
        local p=G.Point(h,(q.x-bounds.x0)/(bounds.x1-bounds.x0),(q.y-bounds.y0)/(bounds.y1-bounds.y0))
        local s=samples[i]
        if not p or not s or not finite(s.x) or not finite(s.y) then return math.huge end
        worst=max(worst,sqrt((p.x-s.x)^2+(p.y-s.y)^2))
    end
    return worst
end

local function clip(poly, distance)
    local out={}
    if #poly==0 then return out end
    local a=poly[#poly];local da=distance(a)
    for _,b in ipairs(poly) do
        local db=distance(b)
        if (da>=0)~=(db>=0) then
            local t=da/(da-db)
            local q={x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t}
            if a.w then q.w=a.w+(b.w-a.w)*t end
            out[#out+1]=q
        end
        if db>=0 then out[#out+1]=b end
        a,da=b,db
    end
    return out
end
local function circleSegment(a,b,r)
    local dx,dy=b.x-a.x,b.y-a.y
    local aa=dx*dx+dy*dy
    if aa<1e-10 then return end
    local bb=2*(a.x*dx+a.y*dy);local cc=a.x*a.x+a.y*a.y-r*r
    local disc=bb*bb-4*aa*cc
    if disc<0 then return end
    local lo,hi=max(0,(-bb-sqrt(disc))/(2*aa)),min(1,(-bb+sqrt(disc))/(2*aa))
    if lo>=hi then return end
    return {x=a.x+dx*lo,y=a.y+dy*lo},{x=a.x+dx*hi,y=a.y+dy*hi}
end
local function boundary(a,b)
    local dx,dy=b.x-a.x,b.y-a.y
    local den=dx*dx+dy*dy
    local t=den>0 and max(0,min(1,-(a.x*dx+a.y*dy)/den)) or 0
    return sqrt((a.x+t*dx)^2+(a.y+t*dy)^2)
end

-- Keep the exact map mask, its holes, and only original contour edges.
-- Clip fills to a 48-sided radius without drawing an invented range contour.
function G.Near(p,v,range)
    local mesh={v=v,lines={},fills={},inside=false}
    local row=p.occupancy[min(p.n,math.floor(v.py*p.n)+1)]
    mesh.inside=row and row[min(p.n,math.floor(v.px*p.n)+1)]~=nil or false
    local candidates={}
    for id,r in ipairs(p.regions) do
        local dx=max(0,r.x0-v.px,v.px-r.x1)*v.W
        local dy=max(0,r.y0-v.py,v.py-r.y1)*v.H
        if dx*dx+dy*dy<=range*range then candidates[id]=true end
    end
    local function xy(x,y) return {x=(x-v.px)*v.W,y=(y-v.py)*v.H} end
    for _,e in ipairs(p.edges) do if candidates[e.region] then
        local a,b=xy(e.x1,e.y1),xy(e.x2,e.y2)
        local d=boundary(a,b);mesh.distance=min(mesh.distance or math.huge,d)
        a,b=circleSegment(a,b,range)
        if a then
            mesh.lines[#mesh.lines+1]={a,b}
            if #mesh.lines>1200 then return nil,'complexity' end
        end
    end end
    local apothem=range*math.cos(math.pi/48)
    for _,r in ipairs(p.rects) do if candidates[r.region] then
        -- Replays move exact rectangles without rebuilding a rounded occupancy
        -- grid. Use those rectangles for containment too, retaining any gaps.
        if v.px>=r.x0 and v.px<r.x1 and v.py>=r.y0 and v.py<r.y1 then mesh.inside=true end
        local poly={xy(r.x0,r.y0),xy(r.x1,r.y0),xy(r.x1,r.y1),xy(r.x0,r.y1)}
        for i=0,47 do
            local a=(i+.5)*2*math.pi/48;local c,s=math.cos(a),math.sin(a)
            poly=clip(poly,function(q) return apothem-q.x*c-q.y*s end)
            if #poly<3 then break end
        end
        if #poly>=3 then
            mesh.fills[#mesh.fills+1]=poly
            if #mesh.fills>600 then return nil,'complexity' end
        end
    end end
    if #mesh.lines>1200 or #mesh.fills>600 then return nil,'complexity' end
    mesh.empty=#mesh.lines==0 and #mesh.fills==0 and not mesh.inside
    return mesh
end

-- Screen clipping happens before perspective division, including the horizon.
function G.Render(mesh,h,b,width,height)
    local m={strokes={},fills={},inside=mesh.inside,nearestDistance=mesh.distance}
    local planes={function(q)return q.w-.001 end,function(q)return q.x end,
        function(q)return width*q.w-q.x end,function(q)return q.y end,function(q)return height*q.w-q.y end}
    local function transform(p)
        local v=mesh.v
        local u=(v.px+p.x/v.W-b.x0)/(b.x1-b.x0)
        local w=(v.py+p.y/v.H-b.y0)/(b.y1-b.y0)
        return {x=h[1]+h[2]*u+h[3]*w,y=h[4]+h[5]*u+h[6]*w,w=1+h[7]*u+h[8]*w}
    end
    local function divide(q)
        return {x=max(0,min(width,q.x/q.w)),y=max(0,min(height,q.y/q.w))}
    end
    for _,line in ipairs(mesh.lines) do
        local a,c=transform(line[1]),transform(line[2]);local lo,hi=0,1
        for _,plane in ipairs(planes) do
            local x,y=plane(a),plane(c)
            if x<0 and y<0 then lo=2;break end
            if (x>=0)~=(y>=0) then
                local t=x/(x-y)
                if x<0 then lo=max(lo,t) else hi=min(hi,t) end
            end
        end
        if lo<hi then
            local function at(t)return divide({x=a.x+(c.x-a.x)*t,y=a.y+(c.y-a.y)*t,w=a.w+(c.w-a.w)*t})end
            local p,q=at(lo),at(hi)
            m.strokes[#m.strokes+1]={x1=p.x,y1=p.y,x2=q.x,y2=q.y}
        end
    end
    local triangles=0
    for _,poly in ipairs(mesh.fills) do
        local out={};for _,p in ipairs(poly) do out[#out+1]=transform(p) end
        for _,plane in ipairs(planes) do out=clip(out,plane) end
        if #out>=3 then
            local points={};for _,p in ipairs(out) do points[#points+1]=divide(p) end
            m.fills[#m.fills+1]=points;triangles=triangles+#points-2
        end
    end
    if triangles>2000 then return nil,'complexity' end
    return m
end
