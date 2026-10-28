"""ロッジの落ち着く場所の調度品と灯りを Blender で組む。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_furniture.py -- \
        --views all,seats,lights,shelf --prefix props/renders/12-furniture

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_furniture.py -- \
        --look flat --export game/props/furniture

ふっくらしたフェルトの椅子とソファ、毛糸で編んだプフ、木の卓と本棚、膝掛け。灯りは紙（光る）で、
プリーツ、提灯の骨、行灯の格子。灯りには `light` の目印を入れ、ゲームではそこに暖色の灯りをともす。
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）"))])
K.setup(A, fiber=1.5, scale=2.0)
EX = K.S["export"]

C.HEX.update({"felt_indigo": "2E3F66", "felt_mustard": "C99A3A", "felt_rose": "B5636A", "felt_moss": "6E7F4A",
              "felt_charcoal": "3A3836", "felt_ivory": "EEE6D4", "felt_rust": "A8532E", "felt_sky": "8FAFC8",
              "yarn_ivory": "EDE4CF", "yarn_moss": "7A8A52", "yarn_rust": "B0603A"})


# ---------------------------------------------------------------- 椅子とソファ
def legs(P, w, d, h, r=0.025, role="wood"):
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.lathe(P, role, [(r * 0.7, 0.0), (r, 0.03), (r * 0.8, h * 0.5), (r, h)], center=(sx * w, sy * d, 0), segs=12)


def armchair(name, role, frame="wood"):
    """ひじ掛け椅子: 木の枠（脚・台・ひじ掛けの板・背の枠）に、綿の座と背のクッション（布の計算で沈む・ふくらむ）"""
    P = K.Parts(name, kind="seat")
    for r in (frame, "wood_dark"):
        P.hard[r] = 0.008
    W, D = 0.78, 0.76
    SZ = 0.36          # 座の板の高さ
    # 脚と台
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.box(P, frame, (sx * (W / 2 - 0.05), sy * (D / 2 - 0.05), SZ / 2), (0.06, 0.06, SZ))
    K.box(P, frame, (0, 0, SZ - 0.03), (W, D, 0.06))
    K.box(P, "wood_dark", (0, D / 2 - 0.005, SZ - 0.06), (W - 0.08, 0.012, 0.05))      # 前の幕板
    # ひじ掛け: 板と、上にフェルトの当て
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.04)
        K.box(P, frame, (x, 0.0, SZ + 0.14), (0.08, D, 0.28))
        K.box(P, frame, (x, 0.02, SZ + 0.3), (0.12, D + 0.04, 0.04))
        K.pbox(P, role, (x, 0.02, SZ + 0.34), (0.055, D / 2, 0.025), n=6.0, nz=2.5, c=6)
    # 背の枠
    K.box(P, frame, (0, -D / 2 + 0.04, SZ + 0.38), (W, 0.07, 0.76), rot=(-0.1, "X"))
    fl = K.collider_box((0, 0, SZ - 0.01), (W, D, 0.02))
    arms = [K.collider_box((sx * (W / 2 - 0.04), 0, SZ + 0.15), (0.08, D, 0.3)) for sx in (-1, 1)]
    back = K.collider_box((0, -D / 2 + 0.04, SZ + 0.38), (W, 0.07, 0.76))
    # 座: 台の上に落として沈ませる
    K.cushion(P, "seat", role, (0, 0.04, SZ + 0.1), (W - 0.18, D - 0.12, 0.13), pressure=3.0,
              colliders=[fl] + arms + [back], tuft=True)
    # 背: 後ろの面を枠に留め、前へふくらませる
    by = -D / 2 + 0.13
    K.cushion(P, "back", role, (0, by, SZ + 0.46), (W - 0.18, 0.14, 0.5), pressure=3.5,
              pin=lambda p: p.y < by - 0.05, colliders=arms, tuft=True)
    for c in [fl, back] + arms:
        K.drop(c)
    P.mark("sit", (0, 0.06, SZ + 0.18))
    P.finish(fuzz=0.003)


def sofa(name, role, seats=3, pillow_roles=(), frame="wood"):
    """ソファ: 木の枠に、座の座布団と背のクッションを人数分（布の計算）。両端は木のひじと丸い当て。飾りのクッション"""
    P = K.Parts(name, kind="seat")
    for r in (frame, "wood_dark"):
        P.hard[r] = 0.008
    CW = 0.62
    W, D, SZ = CW * seats + 0.2, 0.84, 0.34
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.box(P, frame, (sx * (W / 2 - 0.05), sy * (D / 2 - 0.05), SZ / 2), (0.06, 0.06, SZ))
    K.box(P, frame, (0, 0, SZ - 0.03), (W, D, 0.06))
    K.box(P, "wood_dark", (0, D / 2 - 0.005, SZ - 0.06), (W - 0.08, 0.012, 0.05))
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.05)
        K.box(P, frame, (x, 0, SZ + 0.16), (0.1, D, 0.32))
        K.lathe(P, role, [(0.0, -D / 2), (0.07, -D / 2), (0.08, -D / 2 + 0.03), (0.08, D / 2 - 0.03), (0.07, D / 2), (0.0, D / 2)],
                center=(x, 0.0, SZ + 0.36), segs=20, rot=(math.pi / 2, "X"))
        K.ring(P, "thread", (x, D / 2 + 0.002, SZ + 0.36), 0.07, 0.003, axis="Y", n=24)
    K.box(P, frame, (0, -D / 2 + 0.05, SZ + 0.36), (W, 0.08, 0.72), rot=(-0.1, "X"))
    fl = K.collider_box((0, 0, SZ - 0.01), (W, D, 0.02))
    side = [K.collider_box((sx * (W / 2 - 0.05), 0, SZ + 0.16), (0.1, D, 0.32)) for sx in (-1, 1)]
    back = K.collider_box((0, -D / 2 + 0.05, SZ + 0.36), (W, 0.08, 0.72))
    by = -D / 2 + 0.15
    for i in range(seats):
        x = -W / 2 + 0.1 + CW * (i + 0.5)
        K.cushion(P, "seat%d" % i, role, (x, 0.05, SZ + 0.1), (CW - 0.04, D - 0.16, 0.13), pressure=3.0,
                  colliders=[fl] + side + [back], tuft=False)
        K.cushion(P, "back%d" % i, role, (x, by, SZ + 0.42), (CW - 0.04, 0.15, 0.46), pressure=3.5,
                  pin=lambda p, by=by: p.y < by - 0.05, colliders=side, tuft=False)
        P.mark("sit_%d" % i, (x, 0.06, SZ + 0.18))
    for k, pr in enumerate(pillow_roles):   # 飾りのクッション: 角に立てかける
        x = -W / 2 + 0.3 + k * (W - 0.6)
        K.pbox(P, pr, (x, -0.1, SZ + 0.38), (0.17, 0.06, 0.17), n=3.0, nz=3.0, seam_role="thread",
               rot=((-0.3, "X"), (0.3 * (1 if k else -1), "Y")))
    for c in [fl, back] + side:
        K.drop(c)
    P.finish(fuzz=0.003)


def pouf(name, role, body):
    """毛糸で編んだプフ（丸い足のせ）: 縦のなわ編みの畝と、上下の縁は毛糸"""
    P = K.Parts(name, kind="seat")
    m = P.m(body)
    R, H = 0.28, 0.36
    nu = 72 if not EX else 36
    nv = 14 if not EX else 8
    rings = []
    for j in range(nv + 1):
        t = j / nv
        z = H * t
        bulge = 1 + 0.12 * math.sin(math.pi * t)
        ring = []
        for i in range(nu):
            a = 2 * math.pi * i / nu
            rib = 0.012 * abs(math.sin(a * 8 + 0.6 * math.sin(t * 12) * (1 if (i // 9) % 2 else -1)))   # なわ編み
            r = R * bulge + rib
            ring.append(m.bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for j in range(nv):
        for i in range(nu):
            i2 = (i + 1) % nu
            m.bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))
    for ring_, z in ((rings[0], 0.0), (rings[-1], H)):
        c = m.bm.verts.new((0, 0, z + (0.03 if z else 0)))
        for i in range(nu):
            m.bm.faces.new((ring_[i], ring_[(i + 1) % nu], c))
    for z in (0.01, H - 0.005):
        K.ring(P, role, (0, 0, z), R + 0.012, 0.016, n=48)
    P.mark("sit", (0, 0, H))
    P.finish()


# ---------------------------------------------------------------- 卓と棚
def doily(P, center, R):
    """かぎ針編みの敷物: 糸の輪を重ね、縁を扇に"""
    c = Vector(center)
    for k, r in enumerate((R * 0.2, R * 0.45, R * 0.7)):
        K.ring(P, "thread", c + Vector((0, 0, 0.002)), r, 0.0025, n=40)
    for k in range(16):
        a = 2 * math.pi * k / 16
        pts = [c + Vector(((R * 0.7 + R * 0.25 * math.sin(math.pi * t)) * math.cos(a + (t - 0.5) * 0.35),
                           (R * 0.7 + R * 0.25 * math.sin(math.pi * t)) * math.sin(a + (t - 0.5) * 0.35), 0.002))
               for t in [i / 8 for i in range(9)]]
        K.tube(P, "thread", pts, 0.0025, sides=4)


def side_table(name, role="wood"):
    P = K.Parts(name, kind="table")
    K.disc(P, role, (0, 0, 0.56), 0.25, 0.035, segs=40)
    K.lathe(P, role, [(0.03, 0.0), (0.05, 0.05), (0.035, 0.25), (0.05, 0.45), (0.035, 0.54)], segs=16)
    K.lathe(P, role, [(0.0, 0.0), (0.18, 0.0), (0.16, 0.03), (0.0, 0.03)], segs=24)
    doily(P, (0, 0, 0.578), 0.18)
    P.mark("top", (0, 0, 0.58))
    P.finish()


def chabudai(name):
    """ちゃぶ台: 丸い低い卓。脚は 4 本"""
    P = K.Parts(name, kind="table")
    K.disc(P, "wood", (0, 0, 0.32), 0.42, 0.04, segs=48)
    K.ring(P, "wood_dark", (0, 0, 0.32), 0.42, 0.012, n=48)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        K.box(P, "wood_dark", (0.24 * math.cos(a), 0.24 * math.sin(a), 0.15), (0.05, 0.05, 0.3))
    P.mark("top", (0, 0, 0.34))
    P.finish()


def bookshelf(name, seed=0):
    """本棚: 木の棚に、フェルトの背表紙の本と、小さな飾り"""
    P = K.Parts(name, kind="shelf")
    rnd = random.Random(seed)
    W, D, H = 1.0, 0.32, 1.6
    for x in (-W / 2, W / 2):
        K.box(P, "wood", (x, 0, H / 2), (0.03, D, H))
    K.box(P, "wood", (0, -D / 2 + 0.008, H / 2), (W, 0.016, H))
    shelves = [0.04, 0.42, 0.8, 1.18, 1.58]
    for z in shelves:
        K.box(P, "wood", (0, 0, z), (W, D, 0.03))
    roles = ["felt_rust", "felt_indigo", "felt_mustard", "felt_moss", "felt_rose", "felt_ivory", "felt_charcoal", "felt_sky"]
    for si, z in enumerate(shelves[:-1]):
        x = -W / 2 + 0.03
        end = W / 2 - (0.25 if si % 2 else 0.04)
        while x < end:
            bw = rnd.uniform(0.025, 0.05)
            bh = rnd.uniform(0.2, 0.31)
            lean = 0.0
            if x + bw > end:
                break
            role = rnd.choice(roles)
            K.pbox(P, role, (x + bw / 2, 0.0, z + 0.015 + bh / 2), (bw / 2, D * 0.38, bh / 2), n=8.0, c=3)
            K.box(P, "felt_gold" if rnd.random() < 0.5 else "felt_ivory", (x + bw / 2, D * 0.385, z + 0.015 + bh * 0.75),
                  (bw * 0.8, 0.003, 0.012))
            x += bw + 0.003
        if si % 2:   # 空いた所に小さな飾り: 毛玉の雪だるまか、木の小箱
            if si == 1:
                K.pbox(P, "cotton", (W / 2 - 0.12, 0, z + 0.07), (0.05, 0.05, 0.05), n=2.0, c=5)
                K.pbox(P, "cotton", (W / 2 - 0.12, 0, z + 0.14), (0.035, 0.035, 0.035), n=2.0, c=5)
                K.box(P, "felt_red", (W / 2 - 0.12, 0, z + 0.115), (0.08, 0.075, 0.012))
            else:
                K.pbox(P, "felt_tan", (W / 2 - 0.12, 0, z + 0.06), (0.07, 0.07, 0.045), n=6.0, c=4, seam_role="thread")
    P.finish(fuzz=0.002)


def blanket(name, role, stripe):
    """膝掛け: たたんで重ねた毛布。端に房。帯の色"""
    P = K.Parts(name, kind="textile")
    for k in range(3):
        K.pbox(P, role, (0, 0, 0.02 + 0.035 * k), (0.32, 0.22, 0.02), n=8.0, nz=2.2, c=6)
        K.box(P, stripe, (0, 0.221, 0.02 + 0.035 * k), (0.64, 0.004, 0.012))
    for k in range(16):   # 房
        x = -0.3 + 0.6 * k / 15
        K.tube(P, role, [(x, -0.22, 0.02), (x, -0.27, 0.005)], 0.004, sides=4)
    P.finish(fuzz=0.002)


# ---------------------------------------------------------------- 灯り
def pleated(P, role, z0, z1, r0, r1, n=24, depth=0.012):
    """プリーツの紙の筒（傘）: 山と谷を交互に折った紙"""
    m = P.m(role)
    k = n * 2
    rings = []
    for j, (z, r) in enumerate(((z0, r0), (z1, r1))):
        ring = []
        for i in range(k):
            a = 2 * math.pi * i / k
            rr = r + (depth if i % 2 else 0.0) * (r / max(r0, r1))
            ring.append(m.bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rings.append(ring)
    for i in range(k):
        i2 = (i + 1) % k
        m.bm.faces.new((rings[0][i], rings[0][i2], rings[1][i2], rings[1][i]))


def pendant(name, kind, cord=1.0):
    """吊り灯り。drum: プリーツの筒、lantern: 提灯（骨の輪と紙）、cone: 円錐の傘"""
    P = K.Parts(name, kind="light")
    if kind == "drum":
        pleated(P, "paper", -0.22, 0.0, 0.24, 0.24, n=28)
        for z in (-0.22, 0.0):
            K.ring(P, "wood", (0, 0, z), 0.25, 0.008, n=48)
    elif kind == "lantern":
        prof = []
        for j in range(17):
            t = j / 16
            z = -0.4 + 0.4 * t
            prof.append((0.06 + 0.16 * math.sin(math.pi * t) ** 0.7, z))
        K.lathe(P, "paper", prof, segs=32, closed=False)
        for j in range(1, 16, 2):   # 骨: 細い木の輪
            K.ring(P, "wood_dark", (0, 0, prof[j][1]), prof[j][0] + 0.002, 0.0025, n=40)
        for z in (-0.405, 0.0):
            K.disc(P, "wood_dark", (0, 0, z), 0.065, 0.025, segs=20)
    else:
        pleated(P, "paper", -0.2, 0.0, 0.26, 0.08, n=22)
        K.ring(P, "wood", (0, 0, -0.2), 0.27, 0.007, n=48)
    K.tube(P, "yarn_red" if kind == "lantern" else "thread_dark", [(0, 0, 0.0), (0, 0, cord)], 0.006, sides=6)
    P.mark("light", (0, 0, -0.15 if kind != "lantern" else -0.2))
    P.mark("hang", (0, 0, cord))
    P.finish()


def floor_lamp(name):
    P = K.Parts(name, kind="light")
    K.lathe(P, "wood", [(0.0, 0.0), (0.18, 0.0), (0.17, 0.035), (0.03, 0.05), (0.0, 0.05)], segs=24)
    K.dowel(P, "wood", (0, 0, 0.04), (0, 0, 1.5), 0.018, 10)
    pleated(P, "paper", 1.3, 1.62, 0.25, 0.15, n=24)
    for z, r in ((1.3, 0.255), (1.62, 0.155)):
        K.ring(P, "wood", (0, 0, z), r, 0.006, n=40)
    P.mark("light", (0, 0, 1.45))
    P.finish()


def andon(name):
    """行灯: 木の細い格子に紙を張った四角の灯り。床に置く"""
    P = K.Parts(name, kind="light")
    W, H = 0.32, 0.7
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.box(P, "wood_dark", (sx * W / 2, sy * W / 2, H / 2 + 0.04), (0.022, 0.022, H))
    for z in (0.06, H * 0.5, H + 0.03):
        for (cx, cy, sx_, sy_) in ((0, W / 2, W, 0.016), (0, -W / 2, W, 0.016), (W / 2, 0, 0.016, W), (-W / 2, 0, 0.016, W)):
            K.box(P, "wood_dark", (cx, cy, z), (sx_, sy_, 0.016))
    for (cx, cy, sx_, sy_) in ((0, W / 2 - 0.004, W - 0.02, 0.003), (0, -W / 2 + 0.004, W - 0.02, 0.003),
                               (W / 2 - 0.004, 0, 0.003, W - 0.02), (-W / 2 + 0.004, 0, 0.003, W - 0.02)):
        K.box(P, "paper", (cx, cy, H / 2 + 0.05), (sx_, sy_, H - 0.04))
    K.box(P, "wood_dark", (0, 0, 0.02), (W + 0.04, W + 0.04, 0.04))
    P.mark("light", (0, 0, H * 0.5))
    P.finish()


def sconce(name):
    """壁の灯り: 木の板に、半分の筒の紙の傘。前が +Y"""
    P = K.Parts(name, kind="light")
    K.box(P, "wood", (0, 0.01, 0), (0.16, 0.02, 0.32))
    m = P.m("paper")
    prof = [(0.11, -0.12), (0.12, 0.12)]
    n0 = len(m.bm.verts)
    rings = []
    for (r, z) in prof:
        ring = []
        for i in range(17):
            a = math.pi * i / 16
            ring.append(m.bm.verts.new((r * math.cos(a), 0.02 + r * math.sin(a) * 0.8, z)))
        rings.append(ring)
    for i in range(16):
        m.bm.faces.new((rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i]))
    for z in (-0.12, 0.12):
        pts = [(0.115 * math.cos(math.pi * i / 16), 0.02 + 0.092 * math.sin(math.pi * i / 16), z) for i in range(17)]
        K.tube(P, "wood", pts, 0.005, sides=5)
    P.mark("light", (0, 0.07, 0))
    P.finish()


def table_lamp(name, role="felt_mustard"):
    P = K.Parts(name, kind="light")
    K.pbox(P, role, (0, 0, 0.09), (0.08, 0.08, 0.09), n=2.0, nz=2.4, seam_role="thread")
    K.dowel(P, "wood", (0, 0, 0.17), (0, 0, 0.3), 0.01, 8)
    pleated(P, "paper", 0.25, 0.42, 0.15, 0.09, n=18, depth=0.008)
    P.mark("light", (0, 0, 0.33))
    P.finish(fuzz=0.002)


def garland(name, n=9, span=2.0):
    """紙の玉の灯りを毛糸でつないだ飾り。両端を掛ける（たるむ）"""
    P = K.Parts(name, kind="light")
    pts = [(-span / 2 + span * t, 0, -0.25 * math.sin(math.pi * t)) for t in [i / 40 for i in range(41)]]
    K.tube(P, "yarn_red", pts, 0.004, sides=5)
    for k in range(n):
        t = (k + 0.5) / n
        x = -span / 2 + span * t
        z = -0.25 * math.sin(math.pi * t) - 0.06
        K.pbox(P, "paper", (x, 0, z), (0.035, 0.035, 0.04), n=2.0, c=5)
        K.dowel(P, "yarn_red", (x, 0, z + 0.04), (x, 0, z + 0.06), 0.004, 5)
        if k % 3 == 1:
            P.mark("light_%d" % k, (x, 0, z))
    P.finish()


# ---------------------------------------------------------------- 組む
armchair("armchair_rust", "felt_rust")
armchair("armchair_indigo", "felt_indigo")
armchair("armchair_mustard", "felt_mustard")
sofa("sofa_indigo", "felt_indigo", 3, ("felt_mustard", "felt_rose"))
sofa("sofa_moss", "felt_moss", 2, ("felt_ivory",))
pouf("pouf_ivory", "yarn_ivory", "felt_ivory")
pouf("pouf_rust", "yarn_rust", "felt_rust")
pouf("pouf_moss", "yarn_moss", "felt_moss")
side_table("side_table")
chabudai("chabudai")
bookshelf("bookshelf_a", 1)
bookshelf("bookshelf_b", 2)
blanket("blanket_red", "felt_red", "felt_ivory")
blanket("blanket_indigo", "felt_indigo", "felt_mustard")
pendant("pendant_drum", "drum")
pendant("pendant_lantern", "lantern")
pendant("pendant_cone", "cone")
floor_lamp("floor_lamp")
andon("andon")
sconce("sconce")
table_lamp("table_lamp")
garland("garland")

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    lay = {
        "sofa_indigo": (0.0, -0.6, 0), "armchair_rust": (-1.9, 0.6, 0), "armchair_mustard": (1.9, 0.6, 0),
        "armchair_indigo": (4.4, -0.6, 0), "sofa_moss": (6.2, -0.6, 0),
        "pouf_ivory": (-0.8, 1.5, 0), "pouf_rust": (0.9, 1.6, 0), "pouf_moss": (4.0, 1.0, 0),
        "side_table": (-2.6, -0.4, 0), "chabudai": (0.0, 0.9, 0), "bookshelf_a": (-4.2, -1.3, 0), "bookshelf_b": (-3.1, -1.3, 0),
        "blanket_red": (0.0, 0.9, 0.34), "blanket_indigo": (-0.6, -0.5, 0.47),
        "pendant_drum": (-1.6, 0.3, 2.0), "pendant_lantern": (0.0, 0.3, 2.1), "pendant_cone": (1.6, 0.3, 2.0),
        "floor_lamp": (-2.6, -1.0, 0), "andon": (2.8, -0.9, 0), "sconce": (5.3, -1.45, 1.6), "table_lamp": (-2.6, -0.4, 0.58),
        "garland": (5.3, -1.3, 2.4),
    }
    for n, (x, y, z) in lay.items():
        R[n].location = (x, y, z)
    R["armchair_rust"].rotation_euler.z = -0.6
    R["armchair_mustard"].rotation_euler.z = 0.6
    R["blanket_indigo"].rotation_euler.z = 0.2
    # 灯りの紙の中に、描くときだけ暖色の灯り
    for r, parts in K.made:
        for o in parts:
            if o.name.startswith("light"):
                L = bpy.data.objects.new("bulb", bpy.data.lights.new("bulb", "POINT"))
                C.coll("stage").objects.link(L)
                L.location = r.matrix_world @ o.location if r.parent is None else o.location
                L.location = r.location + Vector(o.location)
                L.data.energy = 25
                L.data.color = (1.0, 0.7, 0.42)
                L.data.shadow_soft_size = 0.1
    K.room(floor_size=16.0, wall_y=-1.5)
    K.interior_light(0.8)
    cams = {
        "all": ((1.0, 7.5, 3.0), (1.0, -0.2, 0.9), 28),
        "seats": ((-0.2, 4.2, 1.5), (-0.2, 0.0, 0.5), 32),
        "lights": ((0.8, 3.2, 1.6), (0.6, 0.0, 1.6), 30),
        "shelf": ((-2.4, 2.0, 1.3), (-3.5, -1.2, 0.9), 32),
        "right": ((5.6, 3.2, 1.6), (5.0, -0.6, 0.9), 30),
    }
    K.render_views(A, cams)
