"""UAZ-469 soft-top, metre-scale authored mesh. Run using Blender 4.2+ Python (bpy).
References: factory 469 repair manual / UAZ 31512 dimension sheet;
https://auta5p.eu/srazy/roztoky_2003/roztoky_277.php (1972 469B, shape details)
https://commons.wikimedia.org/wiki/File:UAZ-469_(front).jpg (hood/windscreen)
https://www.njuskalo.hr/auti/uaz-469-2.3-d-oglas-48181350 (rear fittings)
Geometry is original. Reference photos are not included in the asset.
Coordinates in helpers: X left, Y up, Z forward (Godot); converted to Blender Z-up.
"""
import bpy, bmesh, math, random, os
from mathutils import Vector, Euler
from pathlib import Path
P=Path(__file__).resolve().parents[1]
OUT=P/'vehicles/russian/source'
OUT.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
random.seed(469)
materials={}; groups={'body':[], 'wheel':[]}; group='body'
def rgb(h):
    v=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return tuple((x/12.92 if x<.04045 else ((x+.055)/1.055)**2.4) for x in v)
def mat(name,h,rough=.6,metal=0,alpha=1):
    m=bpy.data.materials.new(name);m.diffuse_color=(*rgb(h),alpha);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*rgb(h),alpha)
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;p.inputs['Alpha'].default_value=alpha
    if alpha<1: m.surface_render_method='DITHERED';m.use_transparency_overlap=False
    m.use_backface_culling=True
    if name.startswith('Rust') or name=='Glass': m.use_backface_culling=False
    materials[name]=m;return m
mat('Military olive enamel','505b3c',.66,.12)
mat('Faded olive edges','687052',.78,.08)
mat('Canvas khaki','585941',.96)
mat('Canvas seams','444a35',.98)
mat('Rubber and chassis','222520',.91)
mat('Seat vinyl','383d30',.8)
mat('Aged steel','777b6b',.58,.65)
mat('Glass','84958c',.18,.05,.38)
mat('Headlight glass','d7d7bf',.18,.35)
mat('Amber lens','c56d17',.3)
mat('Red lens','982d21',.3)
mat('Rust dark','553728',.98)
mat('Rust orange','95603b',.96)
mat('Lettering','c8c4ad',.8)
PAINT='Military olive enamel';BLACK='Rubber and chassis';CANVAS='Canvas khaki'
def cv(p):return Vector((p[0],-p[2],p[1]))
def assign(o,name,material):
    o.name='GEO-'+name;o.data.materials.append(materials[material]);groups[group].append(o);return o
def mesh(name,verts,faces,material=PAINT,bevel=0,smooth=False):
    m=bpy.data.meshes.new(name);m.from_pydata([cv(p) for p in verts],[],faces);m.update()
    o=bpy.data.objects.new('GEO-'+name,m);bpy.context.collection.objects.link(o);assign(o,name,material)
    bm=bmesh.new();bm.from_mesh(m);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(m);bm.free()
    if bevel: bevel_obj(o,bevel)
    for f in m.polygons:f.use_smooth=smooth
    return o
def bevel_obj(o,width,segments=3):
    mod=o.modifiers.new('Panel edge radius','BEVEL');mod.width=width;mod.segments=segments
    mod.limit_method='ANGLE'
    n=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');n.keep_sharp=True;n.weight=30
    return o
def box(name,p,size,material=PAINT,bevel=.008):
    bpy.ops.mesh.primitive_cube_add(size=1,location=cv(p));o=bpy.context.object
    o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    assign(o,name,material)
    if bevel:bevel_obj(o,bevel,1 if group=='wheel' else 2)
    return o
def rod(name,a,b,r,material=PAINT,n=12):
    d=cv(b)-cv(a);bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=r,depth=d.length,location=(cv(a)+cv(b))/2)
    o=bpy.context.object;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();assign(o,name,material)
    for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
    return o
def sphere(name,p,scale,material=PAINT):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,radius=1,location=cv(p));o=bpy.context.object
    o.scale=(scale[0],scale[2],scale[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    assign(o,name,material)
    for f in o.data.polygons:f.use_smooth=True
    return o
def tube(name,points,r,material=PAINT,closed=False,n=8):
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.resolution_u=1;curve.bevel_depth=r;curve.bevel_resolution=0
    s=curve.splines.new('POLY');s.points.add(len(points)-1)
    for p,v in zip(s.points,points):p.co=(*cv(v),1)
    s.use_cyclic_u=closed
    o=bpy.data.objects.new('GEO-'+name,curve);bpy.context.collection.objects.link(o)
    o.data.materials.append(materials[material]);groups[group].append(o)
    return o

def side_panel(name,side,outline,x=.823,thick=.018,material=PAINT,bevel=.012):
    # yz outline; actual panel thickness, not a box laid over an opaque hull.
    vs=[(side*(x+t),y,z) for t in [0,thick] for z,y in outline];n=len(outline)
    fs=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,vs,fs,material,bevel)
def strip(name,rings,material=PAINT,cap=True,smooth=True):
    n=len(rings[0]);vs=[p for ring in rings for p in ring]
    fs=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(rings)-1) for i in range(n)]
    if cap:fs+=[tuple(range(n-1,-1,-1)),tuple(range((len(rings)-1)*n,len(rings)*n))]
    return mesh(name,vs,fs,material,smooth=smooth)
def rounded_outline(width,height,r,n=5):
    pts=[]
    for cx,cy,start in [(width/2-r,height/2-r,0),(-width/2+r,height/2-r,90),(-width/2+r,-height/2+r,180),(width/2-r,-height/2+r,270)]:
        for i in range(n+1):
            a=math.radians(start+90*i/n);pts.append((cx+r*math.cos(a),cy+r*math.sin(a)))
    return pts

def front_round(name,x,y,z,w,h,r,material,depth=.015):
    outline=rounded_outline(w,h,r)
    return strip(name,[[(x+u,y+v,z-depth) for u,v in outline],[(x+u,y+v,z) for u,v in outline]],material,smooth=False)

def glass_panel(name,points,frame=PAINT):
    rounded=[]
    for i,p in enumerate(points):
        p=Vector(p);prev=Vector(points[(i-1)%len(points)]);nxt=Vector(points[(i+1)%len(points)])
        a=p+(prev-p).normalized()*.035;b=p+(nxt-p).normalized()*.035
        for j in range(5):
            t=j/4;rounded.append(tuple((1-t)**2*a+2*t*(1-t)*p+t*t*b))
    points=rounded
    tube(name+' rubber seal',points,.016,BLACK,True)
    mesh(name+' glass',points,[tuple(range(len(points)))],'Glass')
    # Frame is separate from glazing, guaranteeing a clear view from the cockpit.

# Subdivide the pressed arch contour with a Catmull-Rom curve, preserving endpoints.
def soften(points,steps=4):
    out=[]
    pts=[Vector(p) for p in points]
    for i in range(len(pts)-1):
        a=pts[max(0,i-1)];b=pts[i];c=pts[i+1];d=pts[min(len(pts)-1,i+2)]
        for j in range(steps):
            t=j/steps;out.append(tuple(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)))
    return out+[points[-1]]
def profile_at(points,z):
    for a,b in zip(points,points[1:]):
        if a[0]<=z<=b[0]:
            t=(z-a[0])/(b[0]-a[0]);return a[1]+t*(b[1]-a[1])
    return points[0][1] if z<points[0][0] else points[-1][1]

def wheelhouse(name,side,profile,outer,inner):
    # A real return flange and inner liner, using exactly the opening contour.
    rings=[]
    for z,y in profile:
        rings.append([(side*outer,y+.048,z),(side*(outer+.020),y+.026,z),
                      (side*(outer+.024),y+.008,z),(side*(outer+.016),y-.004,z),
                      (side*(outer-.015),y-.008,z),(side*(outer-.025),y+.012,z)])
    strip(name+' rolled steel return',rings,PAINT,cap=True)
    vs=[]
    for z,y in profile:vs.extend([(side*(outer-.020),y+.014,z),(side*inner,y+.014,z)])
    liner=mesh(name+' inner wheel tub',vs,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(profile)-1)],BLACK,smooth=True)
    mod=liner.modifiers.new('Wheel tub sheet thickness','SOLIDIFY');mod.thickness=.012

# Ladder chassis, portal axles, springs, tanks: military ground clearance 0.30 m.
for x in [-.48,.48]:box('ladder chassis',(x,.48,-.04),(.09,.12,3.55),BLACK)
for z in [-1.19,1.19]:
    rod('axle',(-.69,.40,z),(.69,.40,z),.055,BLACK)
    sphere('differential',(0,.41,z),(.13,.11,.13),BLACK)
    for x in [-.48,.48]:
        for layer in range(3):
            tube('leaf spring',[(x,.46+layer*.012+.05*(t*t),z+t*.39) for t in [-1,-.75,-.5,0,.5,.75,1]],.012,BLACK)
for z in [-1.5,-.3,.8]:box('cross member',(0,.47,z),(1.04,.075,.08),BLACK)
box('cabin floor',(0,.58,-.68),(1.65,.045,2.32),PAINT)
for side in [-1,1]:box('fuel tank',(side*.57,.49,-.20),(.38,.20,.75),BLACK,.04)
rod('exhaust',(-.45,.35,.35),(-.48,.35,-1.90),.027,BLACK)

# Four separately outlined doors, rear body tub and front cowl.
front_door=[(.47,1.29),(-.35,1.29),(-.35,.58),(.16,.58),(.40,.67)]
# The door cutout, quarter panel and folded lip share one continuous curve.
rear_arch=soften([(-1.78,.58),(-1.69,.73),(-1.56,.94),(-1.43,1.005),
                  (-1.02,1.005),(-.87,.93),(-.74,.70),(-.69,.62)],6)
rear_split=-1.135
rear_y=profile_at(rear_arch,rear_split)
rear_door=[(-.36,1.29),(-1.13,1.29),(-1.13,rear_y)]+[(z,y) for z,y in rear_arch if z>-1.13]+[(-.36,.58)]
rear_quarter=[(-1.14,1.29),(-1.85,1.29),(-1.85,.59)]+[(z,y) for z,y in rear_arch if z<-1.14]+[(-1.14,rear_y)]
for side in [-1,1]:
    for name,outline in [('front door',front_door),('rear door',rear_door),('rear quarter',rear_quarter)]:
        side_panel(name,side,outline,bevel=.012)
        tube(name+' seam',[(side*.845,y,z) for z,y in outline],.003,BLACK,True)
    side_panel('cowl',side,[(.48,.67),(.69,.75),(.72,1.24),(.48,1.38)],x=.818)
    box('side step',(side*.85,.53,-.03),(.085,.045,.91),BLACK,.014)
    # Pressed recessed door belt and exposed hardware.
    for front,back in [(.40,-.29),(-.42,-.99)]:
        tube('door pressing',[(side*.847,1.17,front),(side*.855,1.14,(front+back)/2),(side*.847,1.17,back)],.009)
        z=back+.12
        box('handle mount',(side*.858,1.20,z),(.012,.05,.14),BLACK,.015)
        tube('door handle',[(side*.869,1.20,z-.05),(side*.887,1.20,z-.035),(side*.887,1.20,z+.035),(side*.869,1.20,z+.05)],.008,'Aged steel')
    for z in [.435,-.375]:
        for y in [.75,1.13]:
            box('external hinge leaf',(side*.862,y,z),(.022,.055,.09),PAINT,.004)
            rod('hinge pin',(side*.882,y-.035,z),(side*.882,y+.035,z),.012,'Aged steel',10)
            for dz in [-.026,.026]:rod('hinge screw',(side*.872,y,z+dz),(side*.878,y,z+dz),.006,'Aged steel',8)
    # Dual tank filler necks below rear doors.
    rod('fuel filler recess',(side*.844,.89,-.55),(side*.852,.89,-.55),.056,BLACK,20)
    rod('fuel cap',(side*.854,.89,-.55),(side*.867,.89,-.55),.043,PAINT,20)
    box('filler grip',(side*.878,.89,-.55),(.018,.013,.053),'Aged steel',.004)
    wheelhouse('rear arch',side,rear_arch,.835,.565)
    # Close the inboard wheelhouse above the tire without filling the opening.
    side_panel('rear inner wing',side,[(-1.80,1.20),(-.68,1.20)]+list(reversed(rear_arch)),x=.555,material=BLACK,bevel=.004)
    # Mudflaps mounted behind each wheel.
    for z in [1.19,-1.19]:box('mud flap',(side*.725,.39,z-.41),(.25,.33,.025),BLACK,.006)

# Dark engine bay and inner wheelhouses prevent seeing daylight through the vehicle.
box('engine block',(0,.91,1.09),(.99,.50,1.29),BLACK,.055)
box('radiator',(0,.99,1.65),(1.13,.42,.08),BLACK,.015)
for side in [-1,1]:
    side_panel('inner front wheelhouse',side,[(.50,.72),(.65,.72),(.78,.99),(.90,1.08),(1.48,1.08),(1.65,.93),(1.77,.67),(1.77,1.22),(.50,1.28)],x=.57,material=BLACK,bevel=.01)

# Rounded bonnet: wide centre crown, shoulder roll, slightly tapered front.
hood=[]
for j in range(15):
    t=j/14;z=.50+1.27*t;w=.832-.055*t
    y=1.365-.075*t
    ring=[]
    for i in range(25):
        u=-1+2*i/24
        crown=.033*(1-u*u)-.11*(abs(u)**8)
        ring.append((u*w,y+crown,z))
    ring.extend([(w,y-.15,z),(-w,y-.15,z)])
    hood.append(ring)
strip('rounded bonnet',hood,cap=True)
for side in [-1,1]:
    tube('bonnet seam',[(side*(.834-.055*t),1.365-.075*t-.105,.5+1.27*t) for t in [i/16 for i in range(17)]],.0045,BLACK)
    # Rubber latches and hinge plates.
    box('bonnet latch',(side*.855,1.16,.80),(.025,.11,.05),BLACK,.007)
    rod('bonnet latch eye',(side*.866,1.21,.80),(side*.875,1.24,.80),.014,'Aged steel')
    for z in [.67,1.35]:
        tube('bonnet tie down',[(side*.47,1.375-.06*(z-.5),z-.04),(side*.47,1.401-.06*(z-.5),z-.04),(side*.47,1.401-.06*(z-.5),z+.04),(side*.47,1.375-.06*(z-.5),z+.04)],.008)
box('cowl vent',(0,1.395,.54),(.53,.018,.12),PAINT,.025)
for x in [-.55,.55]:box('bonnet hinge',(x,1.383,.515),(.14,.013,.065),'Aged steel',.005)

# Bulged front wings with cut-away wheel openings. Outer sheet rounds into hood.
arch_top=[(.49,.64),(.61,.72),(.73,.99),(.88,1.075),(1.46,1.075),(1.61,.98),(1.73,.70),(1.79,.66)]
arch_top=soften(arch_top)
for side in [-1,1]:
    rings=[]
    for z,low in arch_top:
        high=1.245-.018*(z-.5)
        rings.append([(side*.725,high,z),(side*.795,high+.018,z),(side*.849,high+.002,z),(side*.880,high-.025,z),(side*.8925,high-.065,z),(side*.8925,low+.040,z),(side*.881,low+.014,z),(side*.859,low+.005,z),(side*.837,low+.019,z),(side*.825,low+.045,z)])
    strip('front rounded wing',rings,cap=True)
    # The inner liner joins the wing's folded edge, rather than a floating trim tube.
    vs=[]
    for z,y in arch_top:vs.extend([(side*.839,y+.023,z),(side*.57,y+.023,z)])
    liner=mesh('front wing inner return',vs,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(arch_top)-1)],BLACK,smooth=True)
    mod=liner.modifiers.new('Pressed liner thickness','SOLIDIFY');mod.thickness=.012
    # Close the rear termination into the cowl and the leading edge into the nose.
    side_panel('wing cowl junction',side,[(.475,.66),(.535,.69),(.535,1.25),(.475,1.30)],x=.816,thick=.045,bevel=.018)
    side_panel('wing nose junction',side,[(1.755,.66),(1.805,.66),(1.805,1.19),(1.755,1.23)],x=.765,thick=.095,bevel=.018)

# Front panel with TWO rounded horizontal grille openings, not Jeep vertical slots.
front_round('nose backing',0,.99,1.782,1.52,.49,.10,PAINT,.04)
for y,w,h in [(1.155,.79,.105),(.961,.92,.115)]:
    front_round('recessed grille aperture',0,y,1.811,w+.035,h+.025,h*.50,BLACK,.012)
    front_round('grille black inner',0,y,1.817,w,h,h*.48,BLACK,.008)
    # Fine diamond mesh, bounded to the rounded opening.
    for slope in [-.60,.60]:
        for k in range(-19,20):
            x0=k*.027;points=[]
            for i in range(11):
                v=-h*.43+i*h*.086;u=x0+slope*v
                if abs(u)<w/2-h*.20:points.append((u,y+v,1.822))
            if len(points)>1:tube('grille diamond mesh',points,.002,'Aged steel')
for x in [-.275,0,.275]:front_round('lower cooling slot',x,.828,1.813,.21,.045,.022,BLACK)
# Characteristic small UAZ wing emblem.
tube('wing emblem',[(-.08,1.272,1.811),(-.028,1.248,1.821),(0,1.265,1.826),(.028,1.248,1.821),(.08,1.272,1.811)],.006,'Aged steel')
for side in [-1,1]:
    x=side*.633
    rod('headlamp rubber seal',(x,1.083,1.772),(x,1.083,1.813),.135,BLACK,32)
    rod('painted headlamp ring',(x,1.083,1.805),(x,1.083,1.833),.126,PAINT,32)
    sphere('convex headlamp lens',(x,1.083,1.828),(.108,.108,.023),'Headlight glass')
    # Optical ribbing in the glass follows the circular lens.
    for i in range(-6,7):
        dx=i*.014;dy=math.sqrt(max(0,.099**2-dx**2))
        rod('headlight fluting',(x+dx,1.083-dy,1.846),(x+dx,1.083+dy,1.846),.0018,'Aged steel',6)
    rod('indicator base',(side*.654,.837,1.79),(side*.654,.837,1.817),.057,PAINT,24)
    sphere('round front indicator',(side*.654,.837,1.831),(.047,.047,.021),'Amber lens')
    rod('side marker',(side*.883,1.10,.69),(side*.898,1.10,.69),.028,'Amber lens',16)
# Steel channel bumper, no SUV chrome trim.
box('front steel bumper',(0,.655,1.855),(1.70,.12,.10),BLACK,.015)
for x in [-.47,.47]:
    tube('towing shackle',[(x-.034,.70,1.903),(x-.04,.745,1.90),(x,.765,1.90),(x+.04,.745,1.90),(x+.034,.70,1.903)],.011,'Aged steel')
    for dx in [-.065,.065]:rod('bumper bolt',(x+dx,.665,1.905),(x+dx,.665,1.915),.011,'Aged steel',6)

# Windscreen assembly. Early 469 split screen; wipers pivot at the TOP edge.
def wind(x,y):return (x,y,.50-(y-1.40)*.40)
outer=[wind(-.817,1.39),wind(.817,1.39),wind(.756,1.963),wind(-.756,1.963)]
tube('folding windscreen frame',outer,.030,PAINT,True)
for side in [-1,1]:
    points=[wind(side*.024,1.435),wind(side*.765,1.435),wind(side*.714,1.925),wind(side*.024,1.925)]
    glass_panel('split windscreen',points)
    x=side*.40
    rod('upper wiper pivot',wind(x,1.94),tuple(Vector(wind(x,1.94))+Vector((0,0,.025))),.017,BLACK)
    a=tuple(Vector(wind(x,1.94))+Vector((0,0,.025)))
    b=tuple(Vector(wind(x-side*.11,1.67))+Vector((0,0,.033)))
    rod('wiper arm',a,b,.006,BLACK,8)
    rod('wiper blade',tuple(Vector(b)+Vector((-.13,.035,-.014))),tuple(Vector(b)+Vector((.13,-.035,.014))),.009,BLACK,8)
    box('windscreen folding hinge',(side*.69,1.391,.505),(.11,.035,.05),PAINT,.007)
rod('windscreen divider',wind(0,1.42),wind(0,1.94),.013,PAINT)
# Door upper frames with front quarter panes and rear rounded rectangular glazing.
for side in [-1,1]:
    x=side*.827
    front=[(x,1.325,.43),(x,1.325,-.31),(side*.773,1.922,-.31),(side*.773,1.922,.236)]
    rear=[(x,1.325,-.39),(x,1.325,-1.10),(side*.773,1.922,-1.10),(side*.773,1.922,-.39)]
    for name,pts in [('front door window',front),('rear door window',rear)]:
        tube(name+' metal frame',pts,.020,PAINT,True)
        center=sum((Vector(p) for p in pts),Vector())/4
        glass_panel(name,[tuple(Vector(p).lerp(center,.065)) for p in pts])
    rod('quarterlight divider',(x,1.34,.21),(side*.773,1.90,.05),.009,PAINT)
    # Long stalk mirrors, driver's round searchlight at windshield base.
    tube('mirror stalk',[(side*.833,1.30,.42),(side*.94,1.42,.40),(side*1.00,1.61,.41)],.010,BLACK)
    box('mirror back',(side*1.00,1.65,.40),(.032,.18,.13),BLACK,.035)
    box('mirror face',(side*1.00,1.65,.329),(.027,.155,.006),'Aged steel',.025)
rod('searchlight stem',(.85,1.34,.50),(.92,1.45,.56),.014,PAINT)
sphere('searchlight housing',(.92,1.49,.57),(.078,.078,.065),PAINT)
rod('searchlight lens',(.92,1.49,.621),(.92,1.49,.632),.065,'Headlight glass',24)

# Canvas: crowned cross-section, gentle sag between bows, stitched edge & tied hem.
zs=[.25,.17,-.15,-.40,-.70,-1.05,-1.38,-1.68,-1.82]
roof_rings=[]
for z in zs:
    ring=[]
    sag=.012*math.sin((z-.17)*math.pi/.55)**2
    for i in range(17):
        u=-1+2*i/16
        ring.append((u*.80,2.05-.10*abs(u)**3-sag,z))
    roof_rings.append(ring)
# Open strip (do not join first and last vertices across the interior).
vs=[p for ring in roof_rings for p in ring];fs=[]
for j in range(len(zs)-1):
    for i in range(16):fs.append((j*17+i,j*17+i+1,(j+1)*17+i+1,(j+1)*17+i))
roof=mesh('canvas crowned roof',vs,fs,CANVAS,smooth=True)
for z in [.26,-1.82]:
    skirt=[]
    for i in range(17):
        u=-1+2*i/16
        skirt.extend([(u*.80,1.935,z),(u*.80,2.05-.10*abs(u)**3,z)])
    mesh('canvas crown end skirt',skirt,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(16)],CANVAS,smooth=True)
sol=roof.modifiers.new('Canvas thickness','SOLIDIFY');sol.thickness=.006
for side in [-1,1]:
    tube('canvas roof sewn edge',[(side*.802,1.947-.012*math.sin((z-.17)*math.pi/.55)**2,z) for z in zs],.009,'Canvas seams')
    # Back side curtain only: doors retain their own window frames.
    for outline in [
        [(-1.12,1.28),(-1.84,1.28),(-1.84,1.49),(-1.12,1.49)],
        [(-1.12,1.84),(-1.84,1.84),(-1.82,1.945),(-1.12,1.945)],
        [(-1.12,1.49),(-1.24,1.49),(-1.24,1.84),(-1.12,1.84)],
        [(-1.71,1.49),(-1.84,1.49),(-1.84,1.84),(-1.71,1.84)]]:
        side_panel('canvas rear side curtain',side,outline,x=.798,thick=.007,material=CANVAS,bevel=.004)
    pts=[(side*.809,1.50,-1.25),(side*.809,1.50,-1.70),(side*.809,1.83,-1.70),(side*.809,1.83,-1.25)]
    glass_panel('rear curtain flexible window',pts,CANVAS)
    for z in [-1.16,-1.39,-1.64,-1.80]:
        tube('canvas tension fold',[(side*.851,1.30,z),(side*.819,1.39,z+.03),(side*.806,1.54,z+.06)],.004,'Canvas seams')
        box('canvas tie strap',(side*.865,1.285,z),(.014,.12,.027),'Canvas seams',.003)
        rod('canvas fastening button',(side*.859,1.235,z),(side*.877,1.235,z),.009,'Aged steel',8)
# Cloth overlaps the steel tub; a rounded apron bridges the inset upper curtain
# to the outside of the body. All hems sit on cloth, not across an air gap.
for side in [-1,1]:
    rings=[]
    for z in [-1.115,-1.30,-1.52,-1.73,-1.845]:
        rings.append([(side*.801,1.405,z),(side*.811,1.345,z),
                      (side*.843,1.298,z),(side*.858,1.267,z),
                      (side*.854,1.228,z),(side*.842,1.228,z),
                      (side*.831,1.275,z),(side*.797,1.38,z)])
    strip('canvas overlapping side apron',rings,CANVAS,cap=True)
    tube('canvas lower side welt',[(side*.858,1.239,z) for z in [-1.115,-1.30,-1.52,-1.73,-1.845]],.006,'Canvas seams')
rings=[]
for x in [-.854,-.65,-.35,0,.35,.65,.854]:
    rings.append([(x,1.405,-1.829),(x,1.345,-1.842),(x,1.298,-1.867),
                  (x,1.267,-1.878),(x,1.228,-1.874),(x,1.228,-1.862),
                  (x,1.275,-1.850),(x,1.38,-1.817)])
strip('canvas overlapping rear apron',rings,CANVAS,cap=True)
tube('canvas lower rear welt',[(x,1.239,-1.878) for x in [-.85,-.55,0,.55,.85]],.006,'Canvas seams')
for side in [-1,1]:
    # Cover the upright rear corner and turn the hem smoothly around it.
    corner=[]
    for y in [1.23,1.28,1.40,1.65,1.94]:
        outx=.854 if y<1.3 else .805
        outz=-1.875 if y<1.3 else -1.838
        corner.append([(side*outx,y,outz+.035),(side*outx,y,outz+.014),
                       (side*(outx-.010),y,outz),(side*(outx-.035),y,outz)])
    strip('canvas rear corner binding',corner,CANVAS,cap=True)
for x in [-.70,-.48,0,.48,.70]:
    box('rear canvas tie strap',(x,1.29,-1.886),(.027,.12,.012),'Canvas seams',.003)
    rod('rear canvas fastening button',(x,1.24,-1.886),(x,1.24,-1.898),.009,'Aged steel',8)

# Rear curtain with a real central aperture.
for x,w in [(-.60,.40),(.60,.40)]:box('rear canvas edge',(x,1.64,-1.826),(w,.61,.012),CANVAS,.015)
box('rear canvas below window',(0,1.40,-1.826),(.80,.14,.012),CANVAS,.01)
box('rear canvas above window',(0,1.91,-1.826),(.80,.11,.012),CANVAS,.01)
glass_panel('rear canvas window',[(-.39,1.48,-1.835),(.39,1.48,-1.835),(.39,1.85,-1.835),(-.39,1.85,-1.835)],CANVAS)
for z in [-.37,-1.10,-1.71]:
    tube('canvas bow seam',[(u*.80,2.054-.10*abs(u)**3,z) for u in [-1,-.8,-.5,0,.5,.8,1]],.0035,'Canvas seams')

# Tailgate and rear military fittings.
box('tailgate',(0,.97,-1.842),(1.64,.58,.036),PAINT,.035)
for side in [-1,1]:
    box('rear bumperette',(side*.64,.61,-1.91),(.45,.12,.11),BLACK,.018)
    rod('rear red lamp base',(side*.68,1.05,-1.87),(side*.68,1.05,-1.895),.068,BLACK,24)
    rod('rear red lens',(side*.68,1.05,-1.895),(side*.68,1.05,-1.912),.055,'Red lens',24)
    rod('rear reflector',(side*.68,.82,-1.87),(side*.68,.82,-1.89),.035,'Red lens',16)
    box('tailgate hinge',(side*.46,.71,-1.874),(.14,.044,.034),PAINT,.007)
    tube('rear handle',[(side*.66,1.23,-1.87),(side*.66,1.23,-1.90),(side*.52,1.23,-1.90),(side*.52,1.23,-1.87)],.009,PAINT)
rod('tow hitch',(0,.48,-1.85),(0,.48,-2.01),.035,'Aged steel')
tube('tow hook',[(0,.48,-2.00),(0,.43,-2.02),(0,.40,-1.98),(0,.43,-1.94)],.025,'Aged steel')
# Number plates, restrained fictional military markings (no real unit identifiers).
for y,z in [(.665,1.918),(.94,-1.895)]:
    x=0 if z>0 else -.39
    box('military plate',(x,y,z),(.40,.13,.012),BLACK,.006)
    for i in range(6):box('plate stencil',(x-.14+i*.052,y,z+(.008 if z>0 else -.008)),(.018,.055,.002),'Lettering',.001)

# Functional-looking period interior, no modern headrests / dashboard screen.
for x in [-.41,.41]:
    box('front seat cushion',(x,.76,-.03),(.50,.15,.51),'Seat vinyl',.06)
    o=box('front seat back',(x,1.02,-.28),(.50,.49,.13),'Seat vinyl',.06);o.rotation_euler.x=math.radians(-8)
    for dx in [-.18,.18]:rod('seat frame',(x+dx,.59,-.20),(x+dx,.76,-.20),.013,BLACK)
box('rear bench cushion',(0,.78,-.92),(1.26,.14,.43),'Seat vinyl',.05)
box('rear bench back',(0,1.00,-1.12),(1.26,.42,.12),'Seat vinyl',.05)
box('front firewall',(0,.96,.46),(1.63,.73,.035),PAINT,.015)
box('windscreen cowl sill',(0,1.378,.475),(1.63,.04,.12),PAINT,.012)
box('metal dashboard',(0,1.25,.43),(1.50,.22,.065),PAINT,.018)
for x,y,r in [(.40,1.28,.064),(.23,1.28,.031),(.12,1.28,.031),(-.01,1.28,.031),(-.13,1.28,.031)]:
    rod('instrument bezel',(x,y,.387),(x,y,.379),r,'Aged steel',24)
    rod('instrument dial',(x,y,.378),(x,y,.374),r*.86,BLACK,24)
    for j in range(12):
        a=math.tau*j/12
        rod('dial tick',(x+math.cos(a)*r*.65,y+math.sin(a)*r*.65,.371),(x+math.cos(a)*r*.77,y+math.sin(a)*r*.77,.371),.0012,'Lettering',4)
    rod('instrument needle',(x,y,.371),(x+r*.5,y+r*.25,.371),.002,'Lettering',6)
rod('steering column',(.42,1.15,.40),(.42,1.34,.12),.024,BLACK)
# Steering wheel plane inclined around the transverse axis.
center=Vector((.42,1.34,.12));u=Vector((1,0,0));v=Vector((0,.55,.835))
pts=[tuple(center+.18*(u*math.cos(i*math.tau/32)+v*math.sin(i*math.tau/32))) for i in range(32)]
tube('three spoke steering wheel',pts,.014,BLACK,True)
for a in [0,2.094,4.189]:rod('steering spoke',tuple(center),tuple(center+.17*(u*math.cos(a)+v*math.sin(a))),.007,'Aged steel')
for x,z,h in [(0,.05,.37),(-.10,.16,.25),(-.16,.20,.22)]:
    rod('gear lever',(x,.61,z),(x,.61+h,z-.08),.009,'Aged steel');sphere('gear knob',(x,.61+h,z-.08),(.025,.025,.025),BLACK)

# Small localized paint chips: nonuniform patches around lower seams/hinges only.
# Not an all-over orange noise filter. Geometry is baked into two shared surfaces.
for side in [-1,1]:
    for i in range(38):
        z=random.choice([random.uniform(-.30,.15),random.uniform(-1.82,-1.70),random.uniform(-.63,-.40)])
        y=random.uniform(.62,.73) if z>-.65 else random.uniform(.64,.88)
        x=side*.8465
        rz=random.uniform(.004,.017);ry=random.uniform(.003,.010)
        ring=[]
        for k in range(7):
            a=k*math.tau/7;s=random.uniform(.65,1.2);ring.append((x,y+math.sin(a)*ry*s,z+math.cos(a)*rz*s))
        mesh('edge paint chip',ring,[tuple(range(7))],'Rust dark' if i%7 else 'Rust orange')
    for z in [.435,-.375]:
        for y in [.75,1.13]:
            box('hinge rust stain',(side*.875,y-.039,z),(.002,.013,.026),'Rust dark',0)

# Bake body before making a reusable tire mesh.
def join_group(name,items):
    bpy.ops.object.select_all(action='DESELECT')
    for o in items:
        bpy.context.view_layer.objects.active=o;o.select_set(True)
        if o.type=='CURVE':bpy.ops.object.convert(target='MESH')
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        o.select_set(False)
    for o in items:o.select_set(True)
    bpy.context.view_layer.objects.active=items[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return o
body=join_group('UAZ469_Body',groups['body'])
group='wheel'
# Bias-ply military tire: 215 mm wide, 780 mm diameter; steel 15-inch wheel.
profile=[(-.1075,.235),(-.108,.285),(-.10,.341),(-.078,.372),(-.05,.381),(.05,.381),(.078,.372),(.10,.341),(.108,.285),(.1075,.235)]
rings=[[(x,r*math.sin(i*math.tau/32),r*math.cos(i*math.tau/32)) for i in range(32)] for x,r in profile]
strip('rounded tire carcass',rings,BLACK,cap=False)
# Two rows of alternating chevron tread blocks; no oversize monster-truck tires.
for i in range(32):
    a=i*math.tau/32
    for side in [-1,1]:
        o=box('zigzag tread',(side*.048,.381*math.sin(a),.381*math.cos(a)),(.092,.028,.049),BLACK,.004)
        # local z in Blender is radial; orient box in Godot radial Y/Z then map.
        o.rotation_euler=(Euler((math.pi/2-a,0,0)).to_matrix() @ Euler((0,0,side*.23)).to_matrix()).to_euler()
for side in [-1,1]:
    for rad,depth,x,material in [(.244,.016,.105,BLACK),(.218,.018,.112,PAINT),(.185,.016,.115,'Faded olive edges'),(.156,.020,.116,PAINT),(.078,.045,.140,PAINT),(.037,.054,.152,BLACK)]:
        rod('pressed steel rim',(side*(x-depth/2),0,0),(side*(x+depth/2),0,0),rad,material,32)
    for i in range(5):
        a=i*math.tau/5
        y,z=math.sin(a)*.101,math.cos(a)*.101
        rod('wheel lug nut',(side*.132,y,z),(side*.150,y,z),.012,'Aged steel',6)
        y,z=math.sin(a+.30)*.166,math.cos(a+.30)*.166
        rod('rim ventilation recess',(side*.128,y,z),(side*.133,y,z),.023,BLACK,12)
    # Raised tire sidewall moulding rings.
    for r in [.265,.324]:
        tube('sidewall moulding',[(side*.109,r*math.sin(i*math.tau/32),r*math.cos(i*math.tau/32)) for i in range(32)],.0025,BLACK,True)
wheel=join_group('UAZ469_Wheel_Template',groups['wheel'])
# Spare identical to road wheels, bolted to tailgate, facing rearward.
spare=wheel.copy();spare.data=wheel.data.copy();bpy.context.collection.objects.link(spare)
spare.name='GEO-tailgate spare';spare.rotation_euler.z=math.pi/2;spare.location=cv((.28,1.12,-1.920))
# Merge spare into static body; overall length including plates/spare is about 4.025 m.
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);spare.select_set(True);bpy.context.view_layer.objects.active=body;bpy.ops.object.join()
for suffix,x,z in [('fl',.7265,1.19),('rl',.7265,-1.19),('fr',-.7265,1.19),('rr',-.7265,-1.19)]:
    o=wheel.copy();o.data=wheel.data;bpy.context.collection.objects.link(o);o.name='UAZ469_Wheel_'+suffix;o.location=cv((x,.39,z))
bpy.data.objects.remove(wheel,do_unlink=True)
# Export only the vehicle. Preserve editable source; the source directory is ignored by Godot.
(OUT/'.gdignore').write_text('')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uaz469.blend'),compress=True)
bpy.ops.export_scene.gltf(filepath='/tmp/gta67_uaz469.glb',export_format='GLB',export_apply=True,export_yup=True,export_materials='EXPORT')
print('UAZ469 EXPORTED',len(body.data.polygons),'body faces')

import sys
sys.stdout.flush()
if bpy.app.background and "blender" not in Path(sys.executable).name.lower():
    os._exit(0)
