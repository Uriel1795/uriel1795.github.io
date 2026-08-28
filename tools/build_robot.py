import numpy as np, trimesh
from trimesh.creation import box, cylinder
from trimesh.visual.material import PBRMaterial
from trimesh.visual import TextureVisuals

# --- VEX IQ palette -------------------------------------------------
CREAM  = (0.910, 0.894, 0.855)   # IQ structural beams
BLUE   = (0.180, 0.494, 0.745)   # IQ gears / plates
LTBLUE = (0.412, 0.667, 0.847)
DARK   = (0.215, 0.225, 0.235)   # tyres, tread
MOTOR  = (0.420, 0.443, 0.470)
BRAIN  = (0.600, 0.627, 0.647)
SCREEN = (0.110, 0.125, 0.140)

def mat(rgb, rough=0.75, metal=0.0):
    return PBRMaterial(baseColorFactor=[*rgb, 1.0],
                       roughnessFactor=rough, metallicFactor=metal)

parts = []
def add(mesh, rgb, rough=0.75, metal=0.0, T=None):
    if T is not None:
        mesh.apply_transform(T)
    mesh.visual = TextureVisuals(material=mat(rgb, rough, metal))
    parts.append(mesh)
    return mesh

def rotY(a): return trimesh.transformations.rotation_matrix(a, [0,1,0])
def rotZ(a): return trimesh.transformations.rotation_matrix(a, [0,0,1])
def rotX(a): return trimesh.transformations.rotation_matrix(a, [1,0,0])
def move(x,y,z): return trimesh.transformations.translation_matrix([x,y,z])

def beam(length, pos, rgb=CREAM, w=0.013, h=0.026, rot=None):
    """A structural beam running along +X unless rotated."""
    m = box(extents=[length, h, w])
    T = move(*pos)
    if rot is not None:
        T = T @ rot
    return add(m, rgb, rough=0.82, T=T)

# ====================================================================
# BASE CHASSIS  (X = length, front is +X;  Y = up;  Z = width)
# ====================================================================
L, W = 0.320, 0.205          # outer footprint
y0   = 0.038                 # frame height above floor

for z in (-W/2, W/2):
    beam(L, (0, y0, z))                                   # side rails
for x in (-L/2 + 0.010, L/2 - 0.010):
    beam(W, (x, y0, 0), rot=rotY(np.pi/2))                # end rails
beam(W, (0.02, y0, 0), rot=rotY(np.pi/2))                 # mid crossmember
beam(W, (-0.10, y0, 0), rot=rotY(np.pi/2))

# ---- drivetrain: dark wheels + blue idler gears between them -------
WR, WT = 0.030, 0.020
for z in (-(W/2 - 0.018), (W/2 - 0.018)):
    for x in (-0.105, 0.075):
        add(cylinder(radius=WR, height=WT, sections=24), DARK, rough=0.95,
            T=move(x, WR, z))
        add(cylinder(radius=0.012, height=WT + 0.004, sections=16), CREAM,
            T=move(x, WR, z))
    # gear train linking the two wheels along each side
    for x in (-0.055, -0.005, 0.040):
        add(cylinder(radius=0.024, height=0.007, sections=28), BLUE, rough=0.6,
            T=move(x, WR, z - 0.014))

# ---- brain, low and central, ports facing +X -----------------------
add(box(extents=[0.098, 0.030, 0.076]), BRAIN, rough=0.55,
    T=move(-0.012, 0.062, 0.0))
add(box(extents=[0.004, 0.020, 0.052]), SCREEN, rough=0.4,
    T=move(0.038, 0.062, 0.0))

# ====================================================================
# INCLINED SUPERSTRUCTURE  — rises from front-low to rear-high
# ====================================================================
x_lo, y_lo = 0.120, 0.050
x_hi, y_hi = -0.115, 0.205
dx, dy = x_hi - x_lo, y_hi - y_lo
span  = float(np.hypot(dx, dy))
angle = float(np.arctan2(dy, dx))
midx, midy = (x_lo + x_hi)/2, (y_lo + y_hi)/2

for z in (-0.078, 0.078):                    # main inclined rails, doubled
    for off in (0.0, 0.030):
        beam(span, (midx, midy + off, z), rot=rotZ(angle))

for t in np.linspace(0.12, 0.88, 5):         # rungs across the incline
    beam(0.156, (x_lo + dx*t, y_lo + dy*t + 0.015, 0), rot=rotY(np.pi/2))

for z in (-0.052, 0.052):                    # blue diagonal bracing
    beam(span*0.82, (midx + 0.012, midy - 0.012, z), rgb=BLUE,
         w=0.011, h=0.020, rot=rotZ(angle))

# ---- corner uprights + top cross beams -----------------------------
for z in (-W/2, W/2):
    for x in (0.130, -0.120):
        h = 0.150 if x > 0 else 0.185
        beam(h, (x, y0 + h/2, z), rot=rotZ(np.pi/2))
for x in (0.130, -0.120):
    beam(W, (x, y0 + (0.150 if x > 0 else 0.185), 0), rot=rotY(np.pi/2))
beam(0.250, (0.005, 0.215, -W/2), )
beam(0.250, (0.005, 0.215,  W/2), )

# ---- large blue gears on lateral axles, rear of the incline --------
def gear(radius, thick, teeth, pos, rgb=BLUE):
    T = move(*pos)
    add(cylinder(radius=radius, height=thick, sections=32), rgb, rough=0.6, T=T)
    for i in range(teeth):
        a = 2*np.pi*i/teeth
        tooth = box(extents=[0.008, thick, 0.010])
        Tt = (move(*pos)
              @ trimesh.transformations.rotation_matrix(a, [0,0,1])
              @ move(radius, 0, 0))
        add(tooth, rgb, rough=0.6, T=Tt)
    add(cylinder(radius=0.009, height=thick + 0.006, sections=14), CREAM, T=T)

for z in (-0.088, 0.088):
    gear(0.052, 0.009, 24, (-0.098, 0.128, z))
    add(cylinder(radius=0.026, height=0.008, sections=24), LTBLUE, rough=0.6,
        T=move(-0.040, 0.100, z))

# ---- axle stubs ----------------------------------------------------
for x, y in ((-0.098, 0.128), (-0.040, 0.100)):
    add(cylinder(radius=0.005, height=0.208, sections=12), DARK, rough=0.5,
        T=move(x, y, 0))

# ====================================================================
# FRONT INTAKE — two motors splayed outward, tread over sprockets
# ====================================================================
for sgn in (-1, 1):
    splay = rotY(sgn * 0.36)
    base  = move(0.168, 0.052, sgn * 0.082) @ splay
    add(box(extents=[0.062, 0.042, 0.038]), MOTOR, rough=0.5, T=base)
    add(box(extents=[0.030, 0.006, 0.030]), LTBLUE, rough=0.6,
        T=base @ move(-0.004, 0.024, 0))
    # sprocket + tread ring
    Ts = base @ move(0.040, -0.006, 0)
    add(cylinder(radius=0.020, height=0.016, sections=20), CREAM, T=Ts)
    for i in range(18):
        a = 2*np.pi*i/18
        link = box(extents=[0.011, 0.016, 0.008])
        add(link, DARK, rough=0.9,
            T=(base @ move(0.040, -0.006, 0)
               @ trimesh.transformations.rotation_matrix(a, [0,0,1])
               @ move(0.026, 0, 0)))

# ---- a couple of drive bands along the incline ---------------------
for z in (-0.064, 0.064):
    add(cylinder(radius=0.0035, height=span*0.9, sections=8), DARK, rough=0.9,
        T=move(midx, midy + 0.040, z) @ rotZ(angle) @ rotY(np.pi/2))

# ====================================================================
scene = trimesh.Scene(parts)
scene.export("/mnt/user-data/outputs/models/2024-iq-robot.glb")

tris = sum(len(p.faces) for p in parts)
print(f"parts: {len(parts)}   triangles: {tris}")
print("bounds (m):", np.round(scene.bounds, 3).tolist())
