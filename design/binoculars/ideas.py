"""双眼鏡と、テラスの双眼鏡台の案（2026-11-07 代表「アイテムとしての双眼鏡と、テラスに固定の双眼鏡台が欲しいです。よく観光地にあるやつ」）。
形は観光地の据え付け双眼鏡（幅広の頭・丸い目 2 つ・Y の受け・支柱・丸い足の板）から借り、素材は props/common.py と kit.py の本番の物。人形は game/person の本番。
  A  ふっくらフェルトの頭に、大きな 4 つ穴ボタンの目
  B  糸巻きを 2 本並べた筒。毛糸を巻いた胴と、木のつばの目
  C  フェルトの庇つきの頭に、刺繍枠の目（となりのソリの立てかけ台と同じ枠）
  hand  持ち歩く双眼鏡の 3 案を並べる（A・B・C の順）
代表の選んだ形をゲームへ（2026-11-07 代表「双眼鏡台はまんなか、手持ち双眼鏡は左が良いかな」＝台は B、手持ちは hand_a）:
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/binoculars/ideas.py -- --what B --export game/props/binocular_stand
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/binoculars/ideas.py -- --what hand --export game/props/binoculars
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/binoculars/ideas.py -- --what A --views front,back --prefix OUT --size 1000x1000

寸法はゲームの大きさ (m)。人の側は +Y、景色の側は -Y。原点は足の板の真ん中の床。
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(ROOT, "props"))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--what", dict(default="A"))])
K.setup(A, fiber=2.0, scale=1.0, tris=12000)
C.HEX.update({"felt_teal": "3F7F86", "felt_indigo": "2B3D68", "felt_ivory": "EEE6D4", "felt_dark": "23262E", "felt_snowball": "F4F4F0",
              "yarn_teal": "3F7F86", "yarn_mustard": "C99A3A", "paper_kraft": "C7A676", "thread": "EEE6D4"})

HEAD_Z = 1.20       # 頭の真ん中の高さ。人形の目は低い（笠 1.16 m、折り紙 1.36 m、小さい人形は 0.6〜0.8 m）。00-stands.jpg は 1.40 で描いた案
EYE_X = 0.135       # 景色の側の目の間
PEEP_X = 0.07       # 人の側ののぞき口の間（人の目の間に近く）
YOKE_W = 0.345      # B の受けの腕の間の半分
ROLL = (math.pi / 2, "X")   # 旋盤の軸を -Y へ


def foot_and_pole(P):
    """足の板・支柱・Y の受け。3 案とも同じ（観光地の物の形）"""
    K.disc(P, "felt_dark", (0, 0, 0.012), 0.46, 0.024, segs=48)
    K.disc(P, "wood", (0, 0, 0.05), 0.42, 0.06, segs=48)
    K.stitch_ring(P, "thread", (0, 0, 0.082), 0.37, r=0.005, dash=0.035)
    for k in range(4):   # 床に留める大きなボタン
        a = math.pi / 4 + k * math.pi / 2
        x, y = 0.29 * math.cos(a), 0.29 * math.sin(a)
        K.disc(P, "brass", (x, y, 0.09), 0.042, 0.02, segs=20)
    K.lathe(P, "wood", [(0, 0), (0.17, 0), (0.17, 0.02), (0.085, 0.09), (0.075, 0.13), (0.075, 0.86), (0.095, 0.89), (0.095, 0.92), (0, 0.92)],
            (0, 0, 0.08), 24, False)
    for z in range(16):   # 支柱の真ん中に巻いた麻ひも（手で触る所）
        K.ring(P, "hemp", (0, 0, 0.32 + z * 0.021), 0.078, 0.011, n=20)
    # 首の回り: 糸巻きの形
    K.lathe(P, "wood_dark", [(0, 0), (0.12, 0), (0.12, 0.03), (0.08, 0.04), (0.08, 0.075), (0.12, 0.085), (0.12, 0.11), (0, 0.11)], (0, 0, 0.99), 24, False)
    pocket(P)


def pocket(P):
    """料金の袋（2026-11-07 代表「双眼鏡台は木のボタン1枚か雪玉で起動してほしい」）。支柱の人の側の、手の高さ。上の口から入れる。
    前に、入れる物の見本（木のボタンと毛糸の雪玉）を縫い付けて、字を使わずに値段を見せる"""
    y, z = 0.155, 0.72
    K.pbox(P, "felt_indigo", (0, y, z), (0.125, 0.075, 0.115), n=3.4, nz=3.0, seam_role="thread", c=10)
    K.ring(P, "thread", (0, y, z + 0.098), 0.078, 0.007, n=24)
    K.disc(P, "felt_dark", (0, y, z + 0.095), 0.074, 0.012, segs=24)
    K.lathe(P, "button", [(0, 0), (0.036, 0), (0.037, 0.006), (0.034, 0.012), (0, 0.009)], (-0.052, y + 0.076, z - 0.015), 20, False, (-math.pi / 2, "X"))
    K.pbox(P, "felt_snowball", (0.052, y + 0.085, z - 0.015), (0.036, 0.036, 0.036), n=2.0, nz=2.0, c=6)
    K.box(P, "wood_dark", (0, 0.095, z), (0.06, 0.05, 0.05))   # 支柱への留め


def yoke(P, half_w, z=HEAD_Z):
    """Y の受け: 曲げ木の腕 2 本を、真鍮の鋲で頭の横に留める"""
    z0 = 1.10
    pts = lambda s: [(0, 0, z0 - 0.01), (s * half_w * 0.5, 0, z0 - 0.015), (s * half_w * 0.92, 0, z0 + 0.0), (s * half_w, 0, z0 + 0.04), (s * half_w, 0, z)]
    for s in (-1, 1):
        K.tube(P, "wood", pts(s), 0.024, sides=10)
        K.disc(P, "brass", (s * (half_w + 0.028), 0, z), 0.038, 0.016, axis="X", segs=20)


def button_eye(P, x, y, z, r, flip=-1):
    """4 つ穴の大きなボタン（y の面に、景色の側へ向く）"""
    K.lathe(P, "button", [(0, 0), (r, 0), (r * 1.02, 0.012), (r * 0.96, 0.03), (r * 0.74, 0.024), (r * 0.70, 0.012), (0, 0.012)], (x, y, z), 40, False, ROLL)
    for i, j in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        K.disc(P, "felt_dark", (x + i * r * 0.24, y - 0.014, z + j * r * 0.24), r * 0.12, 0.006, axis="Y", segs=12)
    K.tube(P, "thread", [(x - r * 0.24, y - 0.018, z - r * 0.24), (x + r * 0.24, y - 0.018, z + r * 0.24)], 0.004)
    K.tube(P, "thread", [(x + r * 0.24, y - 0.018, z - r * 0.24), (x - r * 0.24, y - 0.018, z + r * 0.24)], 0.004)


def peep(P, x, y, z, r=0.042, L=0.07):
    """のぞき口: 短い糸巻きの筒。y から +Y へ"""
    K.lathe(P, "wood_dark", [(r * 0.62, 0.0), (r, 0.0), (r, 0.018), (r * 0.82, 0.024), (r * 0.82, L - 0.022), (r * 1.14, L - 0.012), (r * 1.14, L), (r * 0.62, L), (r * 0.62, 0.0)],
            (x, y, z), 24, True, (-math.pi / 2, "X"))
    K.disc(P, "felt_dark", (x, y + L * 0.72, z), r * 0.66, 0.004, axis="Y", segs=16)


def make_b_head(P):
    """B の頭（上下に振る所）。足と支柱と受けは別の部品"""
    for s in (-1, 1):
        spool_barrel(P, s * 0.158, HEAD_Z, "yarn_teal")
        peep(P, s * PEEP_X, 0.20, HEAD_Z + 0.03)
    K.box(P, "wood_dark", (0, 0.02, HEAD_Z + 0.075), (0.25, 0.22, 0.03))
    K.box(P, "wood_dark", (0, 0.02, HEAD_Z - 0.075), (0.25, 0.22, 0.03))
    K.dowel(P, "wood", (-0.31, 0, HEAD_Z), (0.31, 0, HEAD_Z), 0.018)
    K.box(P, "wood_dark", (0, 0.17, HEAD_Z + 0.03), (0.16, 0.05, 0.12))


def make_a(P):
    """ふっくらフェルトの頭 ＋ 4 つ穴ボタンの目"""
    foot_and_pole(P)
    yoke(P, 0.335)
    K.pbox(P, "felt_teal", (0, 0, HEAD_Z), (0.31, 0.205, 0.195), n=3.4, nz=3.0, seam_role="thread", c=14)
    for s in (-1, 1):
        x = s * EYE_X
        K.disc(P, "felt_ivory", (x, -0.205, HEAD_Z + 0.015), 0.128, 0.018, axis="Y", segs=40)
        K.stitch_ring(P, "felt_indigo", (x, -0.216, HEAD_Z + 0.015), 0.116, r=0.004, axis="Y", dash=0.022)
        button_eye(P, x, -0.215, HEAD_Z + 0.015, 0.098)
        peep(P, s * PEEP_X, 0.18, HEAD_Z + 0.03)


def spool_barrel(P, x, z, yarn):
    """横に寝かせた糸巻きの筒。景色の側に大きなつば"""
    L = 0.52
    y0 = 0.22
    K.lathe(P, "wood", [(0.0, 0.0), (0.086, 0.0), (0.086, 0.02), (0.078, 0.04), (0.078, L - 0.05), (0.145, L - 0.025), (0.15, L), (0.118, L + 0.004), (0.112, L - 0.012), (0.0, L - 0.012)],
            (x, y0, z), 36, False, ROLL)
    n = 17
    for i in range(n):   # 毛糸を巻いた胴
        y = y0 - 0.052 - i * (L - 0.115) / (n - 1)
        K.ring(P, yarn, (x, y, z), 0.098 + 0.004 * math.sin(i * 1.3), 0.0145, axis="Y", n=28)
    K.disc(P, "felt_dark", (x, y0 - L + 0.009, z), 0.112, 0.006, axis="Y", segs=32)


def make_b(P):
    """糸巻きを 2 本並べた筒 ＋ 毛糸の胴（2026-11-07 代表の選んだ形）"""
    foot_and_pole(P)
    yoke(P, YOKE_W)
    make_b_head(P)


def hoop_eye(P, x, y, z, R):
    """刺繍枠の目: 木の二重の輪・真鍮のねじ・張った藍のフェルトに白糸の十字"""
    K.ring(P, "wood", (x, y, z), R, 0.015, axis="Y", n=48)
    K.ring(P, "wood", (x, y + 0.012, z), R - 0.004, 0.011, axis="Y", n=48)
    K.box(P, "brass", (x, y, z + R + 0.018), (0.034, 0.024, 0.024))
    K.disc(P, "felt_indigo", (x, y + 0.006, z), R - 0.004, 0.008, axis="Y", segs=40)
    K.stitch_ring(P, "thread", (x, y - 0.002, z), R * 0.62, r=0.0035, axis="Y", dash=0.024)


def make_c(P):
    """フェルトの庇つきの頭 ＋ 刺繍枠の目"""
    foot_and_pole(P)
    yoke(P, 0.335)
    K.pbox(P, "felt_teal", (0, 0, HEAD_Z), (0.31, 0.19, 0.185), n=5.0, nz=4.0, seam_role="thread", c=14)
    # 庇: 景色の側へ少し張り出すフェルトの板。雪よけ
    K.pbox(P, "felt_teal", (0, -0.17, HEAD_Z + 0.168), (0.30, 0.10, 0.022), n=4.0, nz=2.2, c=8, rot=(-0.22, "X"))
    K.stitch_line(P, "thread", [(-0.27, -0.255, HEAD_Z + 0.163), (0.27, -0.255, HEAD_Z + 0.163)], r=0.0035, dash=0.024)
    for s in (-1, 1):
        hoop_eye(P, s * EYE_X, -0.20, HEAD_Z, 0.112)
        peep(P, s * PEEP_X, 0.165, HEAD_Z + 0.03)


# ---- 持ち歩く双眼鏡。手のひらの大きさ。X に並ぶ 2 本の筒。原点は真ん中
def strap(P, role, x, y):
    """首にかける毛糸のひも（机の上に垂らす）"""
    pts = []
    for k in range(29):
        a = math.pi * k / 28
        pts.append((x - 0.098 * math.cos(a), y + 0.11 * math.sin(a), 0.052 * (1 - math.sin(a)) ** 2 + 0.006))
    K.tube(P, role, pts, 0.0045, sides=6)


def strap_hang(P, role, x):
    """ひもを手の下へ短く垂らす（ゲームの形）"""
    pts = []
    for k in range(13):
        a = math.pi * k / 12
        pts.append((x - 0.098 * math.cos(a), 0.03, 0.052 - 0.11 * math.sin(a)))
    K.tube(P, role, pts, 0.0045, sides=5)


def hand_a(P, cx, hang=False):
    """フェルトを巻いた筒 ＋ ボタンの目"""
    z = 0.052
    for s in (-1, 1):
        x = cx + s * 0.048
        K.lathe(P, "felt_teal", [(0, 0), (0.036, 0), (0.044, 0.006), (0.046, 0.05), (0.052, 0.09), (0.052, 0.125), (0, 0.125)], (x, 0.065, z), 24, False, ROLL)
        K.stitch_ring(P, "thread", (x, 0.065 - 0.03, z), 0.0465, r=0.0018, axis="Y", dash=0.011)
        K.stitch_ring(P, "thread", (x, 0.065 - 0.105, z), 0.0528, r=0.0018, axis="Y", dash=0.011)
        button_eye(P, x, 0.065 - 0.125, z, 0.043)
        K.disc(P, "felt_dark", (x, 0.066, z), 0.022, 0.003, axis="Y", segs=16)
    K.pbox(P, "felt_teal", (cx, 0.03, z + 0.022), (0.03, 0.024, 0.012), n=3.0, nz=2.4, c=6)
    (strap_hang(P, "yarn_mustard", cx) if hang else strap(P, "yarn_mustard", cx, 0.03))


def hand_b(P, cx):
    """小さな糸巻きを 2 本 ＋ 毛糸の胴"""
    z = 0.055
    for s in (-1, 1):
        x = cx + s * 0.05
        K.lathe(P, "wood", [(0, 0), (0.034, 0), (0.034, 0.008), (0.026, 0.015), (0.026, 0.105), (0.05, 0.116), (0.05, 0.13), (0.04, 0.13), (0.038, 0.122), (0, 0.122)], (x, 0.065, z), 24, False, ROLL)
        for i in range(8):
            K.ring(P, "yarn_teal", (x, 0.065 - 0.024 - i * 0.0108, z), 0.0325, 0.0055, axis="Y", n=20)
        K.disc(P, "felt_dark", (x, 0.065 - 0.124, z), 0.038, 0.002, axis="Y", segs=20)
        K.disc(P, "felt_dark", (x, 0.066, z), 0.02, 0.003, axis="Y", segs=16)
    K.box(P, "wood_dark", (cx, 0.0, z + 0.034), (0.07, 0.09, 0.012))
    K.box(P, "wood_dark", (cx, 0.0, z - 0.034), (0.07, 0.09, 0.012))
    strap(P, "yarn_mustard", cx, 0.03)


def hand_c(P, cx):
    """クラフト紙の紙筒 ＋ 刺繍枠の輪"""
    z = 0.052
    for s in (-1, 1):
        x = cx + s * 0.048
        K.lathe(P, "paper_kraft", [(0, 0), (0.038, 0), (0.042, 0.004), (0.042, 0.12), (0, 0.12)], (x, 0.065, z), 24, False, ROLL)
        K.ring(P, "felt_teal", (x, 0.065 - 0.035, z), 0.0425, 0.006, axis="Y", n=24)
        K.ring(P, "felt_teal", (x, 0.065 - 0.05, z), 0.0425, 0.006, axis="Y", n=24)
        K.ring(P, "wood", (x, 0.065 - 0.12, z), 0.044, 0.0062, axis="Y", n=32)
        K.box(P, "brass", (x, 0.065 - 0.12, z + 0.052), (0.013, 0.01, 0.01))
        K.disc(P, "felt_indigo", (x, 0.065 - 0.1215, z), 0.041, 0.003, axis="Y", segs=24)
        K.disc(P, "felt_dark", (x, 0.066, z), 0.024, 0.003, axis="Y", segs=16)
    K.box(P, "wood_dark", (cx, 0.0, z + 0.03), (0.055, 0.03, 0.01))
    strap(P, "yarn_mustard", cx, 0.03)


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and o.parent is None and "Icosphere" in o.name:
            new.remove(o)
            bpy.data.objects.remove(o)
    return new


def doll(name, loc, yaw):
    objs = import_glb(os.path.join(ROOT, "game", "person", name + ".glb"))
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
    g = bpy.data.objects.new("doll", None)
    bpy.context.scene.collection.objects.link(g)
    for o in objs:
        if o.parent is None:
            o.location -= Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
            o.parent = g
    g.scale = (1.15,) * 3
    g.location = loc
    g.rotation_euler = (0, 0, yaw)


def smooth_wood():
    for role in ("wood", "wood_dark"):   # 細い支柱で木目が縞にならないように
        for nd in C.mat(role).node_tree.nodes:
            if nd.type == "TEX_WAVE":
                nd.inputs["Scale"].default_value *= 0.3


def export_stand():
    """台を 3 つに分ける: 動かない足と支柱・左右に回る受け・上下に振る頭（原点は振る軸）"""
    base = K.Parts("binocular_stand", tris=7000)
    foot_and_pole(base)
    base.finish()
    yk = K.Parts("binocular_yoke", tris=900)
    yoke(yk, YOKE_W)
    yk.finish()
    head = K.Parts("binocular_head", tris=14000)
    make_b_head(head)
    head.transform(Matrix.Translation((0, 0, -HEAD_Z)))
    head.finish()
    smooth_wood()
    K.export_all(A.export)


def export_hand():
    """持ち歩く双眼鏡（左の案）。ひもは手の下へ短く垂らす。原点は筒の真ん中"""
    h = K.Parts("binoculars", tris=3500)
    hand_a(h, 0.0, hang=True)
    h.transform(Matrix.Translation((0, 0, -0.052)))
    h.finish()
    K.export_all(A.export)


if A.export:
    C.FIBER["k"] = 4.0 if A.what == "hand" else 2.0
    (export_hand if A.what == "hand" else export_stand)()
    sys.exit(0)
FORM = {"A": make_a, "B": make_b, "C": make_c}
what = A.what
P = K.Parts("binocular_stand" if what in FORM else "binoculars_hand")
if what in FORM:
    FORM[what](P)
    P.finish(fuzz=0.006)
    smooth_wood()
    C.ground(60.0)
    C.light(40.0, -30.0)
    doll("kasa", (-1.05, 0.1, 0), -0.5)
    cams = {"front": ((-1.5, -3.6, 1.8), (-0.3, 0, 0.92), 44), "back": ((-1.9, 3.6, 1.7), (-0.3, 0, 0.92), 44),
            "near": ((-0.45, -1.15, 1.55), (0, 0, 1.38), 46)}
else:
    hand_a(P, -0.22)
    hand_b(P, 0.0)
    hand_c(P, 0.22)
    P.finish(fuzz=0.002)
    C.ground(30.0)
    C.light(46.0, -30.0)
    cams = {"front": ((-0.16, -0.62, 0.42), (0.0, -0.01, 0.04), 38), "back": ((0.12, 0.62, 0.42), (0.0, 0.03, 0.04), 38)}
K.render_views(A, cams)
