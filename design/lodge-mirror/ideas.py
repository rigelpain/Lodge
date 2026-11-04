"""ロッジの入口の横の大きな鏡の案（2026-11-04 代表「染色台の左、ロッジ入口の内側のすぐ横の壁に天井までの高さの大きな鏡を置いてほしい」）。
形は裁縫の道具と材料から借り、素材は props/common.py と kit.py の本番の物（木・フェルト・糸・真鍮・鋼）。鏡の面は銀糸を織り込んだ布（ラメ）。
  A  大きな刺繍枠   右下の小窓と同じ木の輪と真鍮のねじを、縦長にした枠。内に赤い糸のなみ縫い
  B  巻き尺の枠     藍のフェルトのロールの枠に、黄色の巻き尺を巻く。角に針山と待ち針
  C  糸巻きの柱     左右の柱は大きな糸巻きを積んだもの。上と下は木の物差し
ゲーム用の glb は game/mirror.gd が読む。鏡の面そのものはゲームが足す（描く面の大きさは下の SURFACE と game/mirror.gd の SURFACE を同じに）:
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/lodge-mirror/ideas.py -- --what A --export game/props/lodge_mirror
案の絵:
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/lodge-mirror/ideas.py -- --what A --views hero --prefix OUT --size 800x1000

寸法はゲームの大きさ (m)。原点は壁の面（y 0）の床の真ん中、+Y が部屋の側、+Z が上。幅 W は自動ドアの額縁と人台の桶の間、高さ H は 1 階の床から天井まで（lodge/dims.py）
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(ROOT, "props"))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--what", dict(default="A"))])
K.setup(A, fiber=1.5, scale=1.0, tris=14000)
C.HEX.update({"felt_indigo": "2B3D68", "felt_mustard": "D8B23C", "felt_madder": "9E3B3A", "felt_tomato": "C8402E", "felt_leaf": "5E8A4E",
              "felt_ivory": "EEE6D4", "yarn_indigo": "2B3D68", "yarn_mustard": "D9A23A", "yarn_madder": "B8402E", "yarn_moss": "6E7F4A", "wood_ruler": "D2B07E"})
C.SHINES = getattr(C, "SHINES", ())

EX = bool(A.export)
W = 3.10       # 枠の外の幅
H = 5.25       # 枠の外の高さ（床から天井）
SURFACE = {"A": (2.56, 4.55, 2.45, 0.42), "B": (2.54, 4.70, 2.625, 0.0), "C": (2.30, 4.86, 2.625, 0.0)}   # 鏡の面の 幅・高さ・真ん中の高さ・角の丸み


def rounded_path(w, h, r, cz, y, n=8, step=0.25):
    """角の丸い長方形の道筋（XZ の面）。長い辺の途中から始めて一周する（管の継ぎ目を目立たせない）"""
    pts = K.round_rect(w, h, r, n)
    out = []
    for i in range(len(pts)):
        a, b = Vector(pts[i]), Vector(pts[(i + 1) % len(pts)])
        k = max(1, int((b - a).length / step))
        for t in range(k):
            p = a.lerp(b, t / k)
            out.append(Vector((p.x, y, p.y + cz)))
    half = len(out) // 2 // 2
    return out[half:] + out[:half]


def lame_panel():
    """案の絵だけの鏡の面（銀糸を織り込んだ布）。ゲームでは game/mirror.gd のシェーダー"""
    if EX:
        return
    sw, sh, cz, r = SURFACE[A.what]
    m = C.M("lame", "felt_tin", "prop")
    poly = K.round_rect(sw, sh, max(r, 0.001), 8)
    vs = [m.bm.verts.new((x, 0.055, z + cz)) for x, z in poly]
    m.bm.faces.new(vs)
    o = m.done(smooth=False)
    mat = bpy.data.materials.new("lame")
    mat.use_nodes = True
    t = mat.node_tree
    b = t.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.74, 0.76, 0.80, 1)
    b.inputs["Metallic"].default_value = 0.85
    b.inputs["Roughness"].default_value = 0.46
    tc = t.nodes.new("ShaderNodeTexCoord")
    wave = t.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 90.0
    wave.inputs["Distortion"].default_value = 1.5
    noise = t.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.0
    bump = t.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.02
    mix = t.nodes.new("ShaderNodeMath")
    mix.operation = "ADD"
    t.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    t.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    t.links.new(wave.outputs["Fac"], mix.inputs[0])
    t.links.new(noise.outputs["Fac"], mix.inputs[1])
    t.links.new(mix.outputs[0], bump.inputs["Height"])
    t.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    o.data.materials.clear()
    o.data.materials.append(mat)


def make_a():
    """大きな刺繍枠: 外の輪・内の輪・真鍮のねじ・赤い糸のなみ縫い"""
    P = K.Parts("lodge_mirror")
    hoop_h = H - 0.34
    cz = hoop_h / 2 + 0.02
    # 外の輪（幅のある木の帯。角は大きく丸める）
    C.tube(P.m("wood_bent"), rounded_path(W - 0.2, hoop_h - 0.2, 0.56, cz, 0.13), 0.13, sides=16, side=(0, 1, 0), closed=True, ry=0.1, sq=3.4)
    # 内の輪（細く明るい）。布をはさむ
    C.tube(P.m("wood_light"), rounded_path(W - 0.5, hoop_h - 0.5, 0.45, cz, 0.08), 0.045, sides=12, side=(0, 1, 0), closed=True, ry=0.035, sq=3.0)
    # 赤い糸のなみ縫い（あなたの色）
    sw, sh, sc, r = SURFACE["A"]
    C.running_stitch(P.m("thread_red"), rounded_path(sw - 0.2, sh - 0.2, max(r - 0.1, 0.1), sc, 0.075, step=0.05), [Vector()], dash=0.11, gap=0.07, r=0.012)
    # 枠のねじ（上の真ん中）: 輪の切れ目の 2 枚の耳と、横に通した真鍮のねじ
    top = hoop_h + 0.02
    for s in (-1, 1):
        K.pbox(P, "wood", (s * 0.15, 0.14, top + 0.05), (0.09, 0.12, 0.19), n=5.0, nz=5.0, c=5)
    K.dowel(P, "brass", (-0.44, 0.14, top + 0.11), (0.44, 0.14, top + 0.11), 0.03)
    K.lathe(P, "brass", [(0, -0.06), (0.1, -0.06), (0.12, -0.03), (0.12, 0.03), (0.1, 0.06), (0, 0.06)], (0.5, 0.14, top + 0.11), 18, False, rot=(math.pi / 2, Vector((0, 1, 0))))
    # 裏板（壁との隙間をふさぐ）
    K.box(P, "felt_ivory", (0, 0.015, cz), (W - 0.44, 0.03, hoop_h - 0.44))
    P.finish(fuzz=0.0)


def make_b():
    """巻き尺の枠: 藍のフェルトのロール 4 本に、巻き尺をらせんに巻く。右上に針山と待ち針"""
    P = K.Parts("lodge_mirror")
    R = 0.18
    y = R - 0.02
    # ロール（左右は床から天井まで、上下はそのあいだ）
    for s in (-1, 1):
        K.tube(P, "felt_indigo", [(s * (W / 2 - R), y, 0.0), (s * (W / 2 - R), y, H)], R, sides=16)
        K.stitch_line(P, "thread", [(s * (W / 2 - 2 * R) - s * 0.0, y + R * 0.6, 0.1), (s * (W / 2 - 2 * R), y + R * 0.6, H - 0.1)], r=0.012, dash=0.12)
    for z in (R, H - R):
        K.tube(P, "felt_indigo", [(-W / 2 + R, y, z), (W / 2 - R, y, z)], R, sides=16)
    # 巻き尺: 右の柱に斜めに巻き、上のロールを渡って左の柱に垂れる。黄色の帯に黒い目盛り（数字はなし）
    def tape(pts, wide=0.075):
        C.tube(P.m("felt_mustard"), [Vector(p) for p in pts], 0.012, sides=8, closed=False, ry=wide, sq=4.0, side=(0, 1, 0))
    n = 20
    path = []
    cx = W / 2 - R
    for i in range(n * 8 + 1):
        t = i / 8.0
        a = t * math.tau / 2.4
        path.append((cx + (R + 0.012) * math.cos(a), y + (R + 0.012) * math.sin(a), 0.25 + t * 0.235))
    K.tube(P, "felt_mustard", path, 0.05, sides=8, ry=0.012, sq=4.0)
    # 目盛り
    for i in range(0, len(path), 2):
        p = Vector(path[i])
        K.box(P, "felt_charcoal", (p.x, p.y + 0.002, p.z), (0.012, 0.012, 0.06))
    # 針山（トマトの形）と待ち針
    c = (W / 2 - 0.22, 0.32, H - 0.34)
    K.pbox(P, "felt_tomato", c, (0.3, 0.26, 0.24), n=2.6, nz=2.4, seam_role=None)
    for k in range(5):   # へた
        a = k * math.tau / 5
        K.tube(P, "felt_leaf", [(c[0], c[1], c[2] + 0.24), (c[0] + 0.14 * math.cos(a), c[1] + 0.14 * math.sin(a), c[2] + 0.2)], 0.03, sides=6)
    for k, (dx, dz, col) in enumerate(((-0.2, 0.1, "brass"), (-0.05, 0.17, "felt_ivory"), (0.1, 0.12, "felt_indigo"), (-0.14, -0.08, "felt_mustard"), (0.06, -0.04, "felt_ivory"))):
        tip = Vector((c[0] + dx, c[1] + 0.2, c[2] + dz))
        head = tip + Vector((dx * 0.8, 0.34, dz * 0.8))
        K.dowel(P, "steel", tip, head, 0.009, sides=6)
        K.pbox(P, col, head, (0.035, 0.035, 0.035), n=2.0, nz=2.0, c=3)
    K.box(P, "felt_ivory", (0, 0.015, H / 2), (W - 0.5, 0.03, H - 0.5))
    P.finish(fuzz=0.008)


def spool(P, x, y, z, h, r, role):
    fl = 0.07
    K.lathe(P, "wood", [(0, 0), (r, 0), (r, fl * 0.7), (r * 0.72, fl), (r * 0.72, h - fl), (r, h - fl * 0.7), (r, h), (0, h)], (x, y, z), 24, False)
    K.lathe(P, role, [(r * 0.72, fl), (r * 0.88, fl + 0.03), (r * 0.91, h / 2), (r * 0.88, h - fl - 0.03), (r * 0.72, h - fl)], (x, y, z), 24, False)
    # 巻いた糸の筋
    for k in range(5):
        t = fl + 0.05 + (h - 2 * fl - 0.1) * k / 4
        K.ring(P, role, (x, y, z + t), r * 0.905, 0.008, axis="Z", n=24)


def make_c():
    """糸巻きの柱: 左右に大きな糸巻きを積み、上と下を木の物差しでつなぐ"""
    P = K.Parts("lodge_mirror")
    r = 0.25
    y = 0.08
    roles = ["yarn_madder", "yarn_indigo", "yarn_mustard", "yarn_moss", "yarn_indigo"]
    n = 5
    h = H / n
    for s in (-1, 1):
        for i in range(n):
            spool(P, s * (W / 2 - r), y, i * h, h, r, roles[(i + (0 if s > 0 else 2)) % len(roles)])
    # 物差し（目盛りだけ。数字はなし）
    for z, ht in ((H - 0.17, 0.26), (0.08, 0.16)):
        K.box(P, "wood_ruler", (0, 0.1, z), (W - 2 * r + 0.1, 0.05, ht))
        for i in range(-30, 31):
            L = 0.09 if i % 5 == 0 else 0.05
            K.box(P, "thread_dark", (i * 0.045, 0.128, z + ht / 2 - L / 2), (0.008, 0.006, L))
    K.box(P, "felt_ivory", (0, 0.015, H / 2), (W - 0.5, 0.03, H - 0.3))
    P.finish(fuzz=0.0)


{"A": make_a, "B": make_b, "C": make_c}[A.what]()
for role in ("wood", "wood_ruler"):   # 大きな物なので、木目を広く
    m = C.mat(role)
    for nd in m.node_tree.nodes:
        if nd.type == "TEX_WAVE":
            nd.inputs["Scale"].default_value *= 0.3
            nd.inputs["Distortion"].default_value *= 1.6
if EX:
    K.export_all(A.export)
    sys.exit(0)
lame_panel()
# 大きさの見本: いつもの人形を、ゲームと同じ大きさで立てる
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "game", "person", "kasa.glb"))
new = [o for o in bpy.data.objects if o not in before]
for o in list(new):
    if o.type == "MESH" and o.parent is None:
        new.remove(o)
        bpy.data.objects.remove(o)
g = bpy.data.objects.new("doll", None)
C.coll("prop").objects.link(g)
g.scale = (1.15, 1.15, 1.15)
g.location = (1.55, 1.7, 0)
g.rotation_euler = (0, 0, 2.6)
for o in new:
    if o.parent is None:
        o.parent = g
K.room(floor_size=16.0, wall_y=-0.05)
K.interior_light(0.8)
K.render_views(A, {"hero": ((2.6, 8.2, 2.4), (0, 0, 2.62), 30)})
