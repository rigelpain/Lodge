"""ソリの立てかけ台の案（2026-11-04 代表「ソリ屋の隣に、ソリ立てかけスペース」）。
形は裁縫の道具と材料から借り、素材は props/common.py と kit.py の本番の物。ソリは game/props の本番の glb、人形は game/person の本番。
  A  待ち針の針山   長い針山に太い待ち針を刺し、玉の頭にソリをもたせかける
  B  糸立て         大きな糸巻きを立てて並べ、上に大きな物差しを渡す。物差しにもたせかける
  C  刺繍枠の衝立   刺繍をした大きな枠を並べた後ろの壁に、物差しの横木を渡す
  D  代表の組み合わせ（2026-11-04）: 後ろに刺繍枠の衝立、枠と枠のあいだに糸巻きと物差しの横木、手前へ伸ばした床の板に待ち針のストッパー
  story1 story2 story3  「持ってきてしまう」の意味を聞く絵（いま・台へ戻る・台の前に出る）
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/sled-rack/ideas.py -- --what A --views hero --prefix OUT --size 1200x800
代表の選んだ形をゲームへ:
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/sled-rack/ideas.py -- --what D --export game/props/sled_rack

寸法はゲームの大きさ (m)。台は X に長く、人の側は +Y。ソリは鼻を上に、裏を台へ向けて 60° で立てかける。
大（長さ 4.8 m）で背は約 4.2 m。下屋の屋根の下は壁ぎわで 4.7 m あるので、台は壁の側に置く
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(ROOT, "props"))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--what", dict(default="A"))])
K.setup(A, fiber=1.5, scale=1.0, tris=12000)
C.HEX.update({"felt_indigo": "2B3D68", "felt_rust": "A8532E", "felt_mustard": "C99A3A", "felt_madder": "9E3B3A",
              "felt_ivory": "EEE6D4", "felt_moss": "6E7F4A", "felt_teal": "3F7F86", "felt_plum": "6B4A78"})

LEAN = math.radians(60)
RAIL_Z = 1.15              # 背の低い小（1.6 m）も届く高さ
RAIL_Y = -RAIL_Z / math.tan(LEAN)
LEN = 12.0                 # 台の長さ。大なら 5 台、小なら 12 台ほど
W = {"large": 2.4, "mid": 1.7, "small": 0.95}
PIN_Y = 0.46               # 待ち針の列（足もとから手前へ）。大の厚み 0.45 m が 60° に立って、お尻の角がここまで来る
PIN_H = 0.34               # 針の丈（玉の下まで）
PIN_STEP = 0.42            # 針の間
COLS = ("felt_indigo", "felt_rust", "felt_mustard", "felt_madder", "felt_moss", "felt_teal", "felt_plum")


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and o.parent is None and "Icosphere" in o.name:
            new.remove(o)
            bpy.data.objects.remove(o)
    return new


def box_of(objs):
    bpy.context.view_layer.update()
    lo, hi = Vector((9e9,) * 3), Vector((-9e9,) * 3)
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            for k in range(3):
                lo[k] = min(lo[k], p[k])
                hi[k] = max(hi[k], p[k])
    return lo, hi


def holder(objs, name):
    g = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(g)
    for o in objs:
        if o.parent is None:
            o.parent = g
    return g


def sled(kind, loc, rot):
    """本番のソリ。足もと・お尻の端を原点にした節。rot は (X の傾き, Z の向き)"""
    objs = import_glb(os.path.join(ROOT, "game", "props", "sled_%s.glb" % kind))
    lo, hi = box_of(objs)
    for o in objs:
        if o.parent is None:
            o.location -= Vector(((lo.x + hi.x) / 2, lo.y, lo.z))   # 鼻は +Y（game の -Z）
    outer = bpy.data.objects.new("sled_" + kind, None)
    bpy.context.scene.collection.objects.link(outer)
    for o in objs:
        if o.parent is None:
            o.parent = outer
    outer.rotation_mode = "ZXY"
    outer.rotation_euler = (rot[0], 0, rot[1])
    outer.location = loc
    return outer


def lean_sled(kind, x):
    """台に立てかける: 鼻を上（台の側）へ、座る面を人の側へ"""
    return sled(kind, (x, 0.02, 0.02), (-LEAN, math.pi))


def doll(name, loc, yaw, scale=1.15):
    objs = import_glb(os.path.join(ROOT, "game", "person", name + ".glb"))
    lo, hi = box_of(objs)
    g = bpy.data.objects.new("doll", None)
    bpy.context.scene.collection.objects.link(g)
    for o in objs:
        if o.parent is None:
            o.location -= Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
            o.parent = g
    g.scale = (scale,) * 3
    g.location = loc
    g.rotation_euler = (0, 0, yaw)
    return g


def foot(P):
    """ソリの滑り木を受ける、低い木の縁（全案とも。ゲームの置き方が同じになる）"""
    K.box(P, "wood_dark", (0, 0.18, 0.05), (LEN + 0.4, 0.14, 0.10))
    K.box(P, "wood", (0, -0.5, 0.03), (LEN + 0.4, 1.3, 0.06))


def ruler(P, z=RAIL_Z, y=RAIL_Y):
    """大きな物差し: 竹色の板に、墨の目盛り（1 尺ごとに長く）"""
    K.box(P, "wood", (0, y - 0.02, z), (LEN + 0.5, 0.07, 0.22))
    n = int(LEN / 0.19)
    for i in range(n + 1):
        x = -LEN / 2 + i * 0.19
        h = 0.10 if i % 5 == 0 else 0.05
        K.box(P, "wood_dark", (x, y + 0.016, z + 0.11 - h / 2), (0.016, 0.006, h))


def make_a(P):
    """待ち針の針山"""
    foot(P)
    K.pbox(P, "felt_madder", (0, -1.35, 0.52), (LEN / 2 + 0.2, 0.62, 0.52), n=3.2, nz=2.6, c=10)
    for i in range(14):   # 針山を締める糸
        x = -LEN / 2 + i * LEN / 13
        K.stitch_ring(P, "thread", (x, -1.35, 0.52), 0.58, axis="X", dash=0.05)
    pins = 11
    for i in range(pins):
        x = -LEN / 2 + 0.4 + i * (LEN - 0.8) / (pins - 1)
        K.dowel(P, "steel", (x, -1.2, 0.7), (x, RAIL_Y - 0.18, RAIL_Z - 0.04), 0.04)
        ball = COLS[i % len(COLS)]
        K.pbox(P, ball, (x, RAIL_Y - 0.13, RAIL_Z), (0.22, 0.22, 0.22), n=2.0, nz=2.0, c=10)
    for x, y, c in ((-5.9, -1.5, "felt_mustard"), (5.9, -1.5, "felt_teal")):   # 両端の目印の、背の高い針
        K.dowel(P, "steel", (x, y, 0.7), (x, y, 2.9), 0.05)
        K.pbox(P, c, (x, y, 3.1), (0.28, 0.28, 0.28), n=2.0, nz=2.0, c=10)


def make_b(P):
    """糸立て"""
    foot(P)
    K.box(P, "wood_dark", (0, -1.05, 0.10), (LEN + 0.4, 1.0, 0.20))
    n = 6
    for i in range(n):
        x = -LEN / 2 + 0.3 + i * (LEN - 0.6) / (n - 1)
        h = RAIL_Z - 0.11 - 0.20
        K.lathe(P, "wood", [(0, 0), (0.42, 0), (0.42, 0.06), (0.26, 0.10), (0.26, h - 0.10), (0.42, h - 0.06), (0.42, h), (0, h)], (x, RAIL_Y - 0.28, 0.20), 28, False)
        K.lathe(P, COLS[i % len(COLS)], [(0.26, 0.10), (0.39, 0.14), (0.40, h / 2), (0.39, h - 0.14), (0.26, h - 0.10)], (x, RAIL_Y - 0.28, 0.20), 28, False)
    ruler(P)


def make_c(P):
    """刺繍枠の衝立"""
    foot(P)
    n = 5
    R = 1.22
    y = -1.75
    K.box(P, "wood_dark", (0, y, 0.09), (LEN + 0.4, 0.5, 0.18))
    for i in range(n):
        x = -LEN / 2 + 1.2 + i * (LEN - 2.4) / (n - 1)
        z = R + 0.18
        K.ring(P, "wood", (x, y, z), R, 0.055, axis="Y", n=48)
        K.ring(P, "wood", (x, y + 0.05, z), R - 0.015, 0.035, axis="Y", n=48)
        K.disc(P, COLS[i % len(COLS)], (x, y, z), R - 0.03, 0.03, axis="Y", segs=48)
        K.box(P, "brass", (x, y, z + R + 0.08), (0.2, 0.12, 0.12))   # 枠のねじ
        for k in range(6):   # 刺繍: 雪の結晶
            a = k * math.pi / 3
            K.tube(P, "thread", [(x, y + 0.03, z), (x + math.cos(a) * 0.8, y + 0.03, z + math.sin(a) * 0.8)], 0.016)
            for s in (-1, 1):
                b = a + s * 0.7
                m = Vector((x + math.cos(a) * 0.5, y + 0.03, z + math.sin(a) * 0.5))
                K.tube(P, "thread", [tuple(m), (m.x + math.cos(b) * 0.25, m.y, m.z + math.sin(b) * 0.25)], 0.013)
    for i in range(n):   # 物差しを受ける腕
        x = -LEN / 2 + 1.2 + i * (LEN - 2.4) / (n - 1)
        K.box(P, "wood_dark", (x, (y + RAIL_Y) / 2, RAIL_Z - 0.14), (0.14, abs(y - RAIL_Y), 0.08))
    ruler(P)


def make_d(P):
    """代表の組み合わせ: 刺繍枠の衝立 ＋ 枠と枠のあいだの糸巻き ＋ 床の板に刺した待ち針のストッパー。
    2026-11-04 代表「糸巻きは刺繍枠と刺繍枠の間に置くのが良い」
    「まち針は床の板を伸ばしてたくさん刺して、まるいとこでソリが滑り落ちてくるの止めるストッパーにする」"""
    K.box(P, "wood", (0, 0.05, 0.03), (LEN + 0.8, PIN_Y * 2 + 0.6, 0.06))     # 手前へ伸ばした床の板
    K.box(P, "wood_dark", (0, -1.25, 0.10), (LEN + 0.8, 1.5, 0.20))           # 奥の土台
    n, R, y, step = 4, 1.06, -1.72, 3.0
    z = R + 0.20
    for i in range(n):   # 後ろの刺繍枠
        x = (i - (n - 1) / 2) * step
        K.ring(P, "wood", (x, y, z), R, 0.05, axis="Y", n=48)
        K.ring(P, "wood", (x, y + 0.05, z), R - 0.015, 0.032, axis="Y", n=48)
        K.disc(P, COLS[i % len(COLS)], (x, y, z), R - 0.03, 0.03, axis="Y", segs=48)
        K.box(P, "brass", (x, y, z + R + 0.07), (0.18, 0.11, 0.11))
        for k in range(6):   # 刺繍: 雪の結晶
            a = k * math.pi / 3
            K.tube(P, "thread", [(x, y + 0.03, z), (x + math.cos(a) * 0.7, y + 0.03, z + math.sin(a) * 0.7)], 0.015)
            for sgn in (-1, 1):
                b = a + sgn * 0.7
                m = Vector((x + math.cos(a) * 0.44, y + 0.03, z + math.sin(a) * 0.44))
                K.tube(P, "thread", [tuple(m), (m.x + math.cos(b) * 0.22, m.y, m.z + math.sin(b) * 0.22)], 0.012)
    h = RAIL_Z - 0.11 - 0.20
    for i in range(n + 1):   # 枠と枠のあいだの糸巻き（土台と物差しのあいだに立ち、物差しを受ける）
        x = (i - n / 2) * step
        K.lathe(P, "wood", [(0, 0), (0.38, 0), (0.38, 0.06), (0.24, 0.10), (0.24, h - 0.10), (0.38, h - 0.06), (0.38, h), (0, h)], (x, RAIL_Y - 0.26, 0.20), 28, False)
        K.lathe(P, COLS[(i + 3) % len(COLS)], [(0.24, 0.10), (0.35, 0.14), (0.36, h / 2), (0.35, h - 0.14), (0.24, h - 0.10)], (x, RAIL_Y - 0.26, 0.20), 28, False)
    ruler(P)
    pins = int(LEN / PIN_STEP) + 1
    for i in range(pins):   # 床の板に刺した待ち針。玉でソリのお尻を止める
        x = (i - (pins - 1) / 2) * PIN_STEP
        K.dowel(P, "steel", (x, PIN_Y, 0.05), (x, PIN_Y, PIN_H), 0.018, sides=6)
        K.pbox(P, COLS[(i * 3) % len(COLS)], (x, PIN_Y, PIN_H + 0.04), (0.085, 0.085, 0.085), n=2.0, nz=2.0, c=5)


def hill(x, y):
    d = x - 11.0
    return 0.0 if d < 0 else 0.0016 * d ** 2 * (3.0 + 0.04 * d) + 0.02 * max(0.0, d)


FORM = {"A": make_a, "B": make_b, "C": make_c, "D": make_d}
what = A.what
key = what if what in FORM else "B"
P = K.Parts("sled_rack")
FORM[key](P)
P.finish(fuzz=0.008)
for role in ("wood", "wood_dark"):
    for nd in C.mat(role).node_tree.nodes:
        if nd.type == "TEX_WAVE":
            nd.inputs["Scale"].default_value *= 0.3

if A.export:   # ゲームの glb（game/sled_rack.gd が読む）。ソリと人形はゲームが足す
    K.export_all(A.export)
    sys.exit(0)
if what in FORM:
    lean_sled("large", -4.4)
    lean_sled("mid", -1.9)
    lean_sled("small", -0.4)
    doll("kasa", (2.2, 2.2, 0), -0.5)
    C.ground(300.0)
    C.light(40.0, -30.0)
    cams = {"hero": ((5.5, 15.5, 3.4), (0.0, -0.6, 1.6), 31), "side": ((12.0, 3.2, 2.4), (0.0, -0.6, 1.6), 30)}
else:
    C.ground(300.0, hill=hill)
    C.light(40.0, -30.0)
    if what == "story1":
        sled("mid", (19.0, -1.0, hill(19.0, -1.0) + 0.03), (0.0, -1.3))
    elif what == "story2":
        lean_sled("mid", 1.0)
    elif what == "story3":
        sled("mid", (2.6, 3.0, 0.0), (0.0, 1.2))
    doll("kasa", (-1.6, 2.4, 0), -0.4)
    cams = {"hero": ((2.0, 25.0, 6.0), (6.5, 0.0, 2.0), 30)}
K.render_views(A, cams)
