"""形の確かめ（長方形と屋根の外形だけ）。白い粘土の塊で、丘から見たシルエットと重心を見る。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P lodge/massing.py -- 出力.png [カメラ]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dims import *  # noqa: E402,F403

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/massing.png"
VIEW = argv[1] if len(argv) > 1 else "hill"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = 0.9
    return m


CLAY = mat("clay", (0.78, 0.76, 0.72))
ROOF = mat("roof", (0.30, 0.34, 0.50))
SNOW = mat("snow", (0.92, 0.93, 0.95))


def box(name, x0, y0, z0, x1, y1, z1, m=CLAY):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    o = bpy.context.object
    o.name = name
    o.scale = (x1 - x0, y1 - y0, z1 - z0)
    o.data.materials.append(m)
    return o


def prism(name, prof, x0, x1, m):
    """y-z の多角形を x0..x1 に押し出す"""
    me = bpy.data.meshes.new(name)
    n = len(prof)
    verts = [(x0, y, z) for y, z in prof] + [(x1, y, z) for y, z in prof]
    faces = [list(range(n))[::-1], list(range(n, 2 * n))]
    faces += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    o.data.materials.append(m)
    return o


fas0 = DECK_Z - FASCIA_H
box("ground", -60, -60, -0.2, 60, 60, 0, SNOW)
box("plinth", X0 - 0.1, Y0 - 0.1, 0, X1 + 0.1, Y1 + 0.1, PLINTH)
box("1F", X0, Y0, PLINTH, X1, Y1, fas0)
box("deck", X0, Y0 - CANTI, fas0, X1, Y1, DECK_Z)
box("bay", PORCH_X0, BAY_Y, fas0, PORCH_X1, Y0, DECK_Z)
for px in (PORCH_X0, PORCH_X1):
    box("bay_post", px - BAY_POST / 2, BAY_Y + 0.12 - BAY_POST / 2, 0, px + BAY_POST / 2, BAY_Y + 0.12 + BAY_POST / 2, fas0)
box("porch_void", PORCH_X0 + 0.05, Y0 - 0.2, 0, PORCH_X1 - 0.05, Y0 + PORCH_DEPTH, fas0 - 0.1, mat("void", (0.1, 0.1, 0.12)))
box("2F", X2_0, Y2_0, FL2, X2_1, Y2_1, EAVE_Z)
gable = [(Y2_0, EAVE_Z)] + ROOF_LINE[2:5] + [(Y2_1, EAVE_Z)]
prism("gable", gable, X2_0, X2_1, CLAY)
ro = offset_line(ROOF_LINE, ROOF_T)
prism("roof", ROOF_LINE + list(reversed(ro)), X2_0 - VERGE_OUT, X2_1 + VERGE_OUT, ROOF)
up = offset_line(ro[2:5], SNOW_T)
prism("snow", ro[2:5] + list(reversed(up)), X2_0 - VERGE_OUT + 0.25, X2_1 + VERGE_OUT - 0.25, SNOW)
# 下屋（片流れ）
wz = lambda x: W_HIGH - (x - WX0) * W_PITCH
me = bpy.data.meshes.new("wing")
vs = [(WX0, WY0, 0), (WX1, WY0, 0), (WX1, WY1, 0), (WX0, WY1, 0),
      (WX0, WY0, wz(WX0)), (WX1, WY0, wz(WX1)), (WX1, WY1, wz(WX1)), (WX0, WY1, wz(WX0))]
me.from_pydata(vs, [], [[3, 2, 1, 0], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]])
w = bpy.data.objects.new("wing", me)
sc.collection.objects.link(w)
w.data.materials.append(CLAY)
e = WX1 + W_EAVE_OUT


def shed(name, x0, x1, y0, y1, lift, t, m):
    """x とともに下がる片流れの板"""
    me = bpy.data.meshes.new(name)
    vs = []
    for dz in (0, t):
        vs += [(x0, y0, wz(x0) + lift + dz), (x1, y0, wz(x1) + lift + dz), (x1, y1, wz(x1) + lift + dz), (x0, y1, wz(x0) + lift + dz)]
    me.from_pydata(vs, [], [[3, 2, 1, 0], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]])
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    o.data.materials.append(m)


shed("wing_roof", WX0, e, WY0 - 0.3, WY1 + 0.3, 0, ROOF_T, ROOF)
shed("wing_snow", WX0, e - 0.25, WY0 - 0.1, WY1 + 0.1, ROOF_T, 0.28, SNOW)
# 煙突
box("chim_lo", X0 - CH_D0, CH_Y - CH_W0 / 2, 0, X0, CH_Y + CH_W0 / 2, CH_SHOULDER)
box("chim_hi", X0 - CH_D1, CH_Y - CH_W1 / 2, CH_SHOULDER, X0, CH_Y + CH_W1 / 2, CH_TOP)
box("chim_cap", X0 - CH_D1 - CH_CAP_OUT, CH_Y - CH_W1 / 2 - CH_CAP_OUT, CH_TOP + 0.16, X0 + CH_CAP_OUT,
    CH_Y + CH_W1 / 2 + CH_CAP_OUT, CH_TOP + 0.3)
# 手すり（板で代用）
box("rail_s", X0, Y0 - CANTI, DECK_Z, X1, Y0 - CANTI + 0.06, DECK_Z + RAIL_H, CLAY)

# 丘（南へ上る）
me = bpy.data.meshes.new("hill")
verts, faces, N = [], [], 40
for j in range(N + 1):
    for i in range(N + 1):
        x = -70 + i * 140 / N
        y = -22 - j * 60 / N
        d = -22 - y
        verts.append((x, y, (d ** 1.3) * 0.18))
for j in range(N):
    for i in range(N):
        a = j * (N + 1) + i
        faces.append([a, a + 1, a + N + 2, a + N + 1])
me.from_pydata(verts, [], faces)
h = bpy.data.objects.new("hill", me)
sc.collection.objects.link(h)
h.data.materials.append(SNOW)

# 光: 南西の低い午後の太陽
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sc.collection.objects.link(sun)
sun.data.energy = 4.5
sun.data.angle = math.radians(2)
sun.rotation_euler = (math.radians(62), 0, math.radians(-45))   # 南西から北東へ、高度 28 度
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.70, 0.85, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.32

cams = {"hill": ((-16, -34, 11.5), (1.5, 0, 3.6), 38), "west": ((-34, -8, 5), (0, 0, 4.5), 40),
        "aerial": ((-30, -40, 30), (2, 0, 2), 35)}
loc, tgt, lens = cams[VIEW]
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
cam.location = loc
d = [tgt[i] - loc[i] for i in range(3)]
cam.rotation_euler = (math.atan2(math.hypot(d[0], d[1]), -d[2]), 0, math.atan2(d[1], d[0]) - math.pi / 2)
cam.data.lens = lens
sc.camera = cam

for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
sc.render.resolution_x, sc.render.resolution_y = 1280, 800
sc.view_settings.view_transform = "AgX"
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("wrote", OUT)
