"""食べ物と飲み物を Blender で組む。どれも実寸（手で持つ大きさ）の、フェルトと毛糸の手芸の食べ物。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_food.py -- \
        --views all,buns,ramen,cans,snacks --prefix props/renders/10-food

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_food.py -- \
        --look flat --export game/props/food

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_food.py -- --icons game/props/food/icons

食べ物はフェルトで形を作り、麺は毛糸、湯気とご飯の白は綿、包み紙は紙。缶はフェルトを巻いた筒に、
アップリケのラベル（文字なし。中身を絵で見せる）。日本のゲレンデのロッジで食べるもの。
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

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）")),
              ("--icons", dict(default="", help="この場所に、品物ごとのアイコン（背景を透かした絵）を描く"))])
K.setup(A, fiber=4.0, scale=1.5, tris=1200)
EX = K.S["export"]


# ---------------------------------------------------------------- 中華まん
def bun(name, role, mark=None, mark_role=None):
    """ふっくらした生地のてっぺんに、ひだが渦を巻いて集まる。下に包み紙"""
    P = K.Parts(name, kind="food")
    m = P.m(role)
    R, Hh = 0.052, 0.04
    n0 = len(m.bm.verts)
    C.superellipsoid(m, (0, 0, 0), (R, R, Hh), n_xy=2.0, n_z=2.3, cuts=K.cuts(12, 6))
    for v in C.new_verts(m, n0):
        x, y, z = v.co
        rr = math.hypot(x, y) / R
        if z > 0:
            th = math.atan2(y, x)
            pleat = 0.006 * math.cos(14 * th + 7.0 * rr) * (1 - rr) ** 0.5
            v.co.z = z + pleat + 0.012 * (1 - rr) ** 3      # てっぺんのつまみ
            v.co.x *= 1 + pleat * 3
            v.co.y *= 1 + pleat * 3
        else:
            v.co.z = max(z, -Hh * 0.55)                      # 底は平ら
        v.co.z += Hh * 0.55
    if mark == "dot":   # あんまんの赤い点
        K.pbox(P, mark_role, (0, 0, Hh * 0.55 + Hh + 0.012), (0.008, 0.008, 0.002), n=2.0, c=4)
    elif mark == "line":   # カレーまんの焼き印のような 2 本線
        for dx in (-0.006, 0.006):
            K.box(P, mark_role, (dx, 0.0, Hh * 0.55 + Hh + 0.006), (0.003, 0.024, 0.002))
    K.extrude(P, "paper_white", K.round_rect(0.1, 0.1, 0.01), 0.0, 0.002)
    P.finish(fuzz=0.0015)


def bun_case(name="bun_case"):
    """中華まんのショーケース: 木の枠に透明なフィルム、2 段の棚、上に紙の灯り、湯気"""
    P = K.Parts(name, kind="fixture")
    W, D, H = 0.6, 0.45, 0.55
    for x in (-W / 2, W / 2):
        for y in (-D / 2, D / 2):
            K.dowel(P, "wood", (x, y, 0), (x, y, H), 0.015, 8)
    K.box(P, "wood", (0, 0, 0.015), (W + 0.04, D + 0.04, 0.03))
    K.box(P, "wood", (0, 0, H + 0.02), (W + 0.06, D + 0.06, 0.04))
    K.box(P, "wood", (0, 0, H * 0.48), (W - 0.02, D - 0.02, 0.012))
    for (cx, cy, sx, sy) in ((0, D / 2, W, 0.003), (0, -D / 2, W, 0.003), (W / 2, 0, 0.003, D), (-W / 2, 0, 0.003, D)):
        K.box(P, "glass", (cx, cy, H / 2), (sx, sy, H - 0.04))
    K.stitch_line(P, "thread", [(-W / 2 + 0.02, D / 2 + 0.004, H - 0.03), (W / 2 - 0.02, D / 2 + 0.004, H - 0.03),
                                (W / 2 - 0.02, D / 2 + 0.004, 0.05), (-W / 2 + 0.02, D / 2 + 0.004, 0.05),
                                (-W / 2 + 0.02, D / 2 + 0.004, H - 0.03)], r=0.0025, dash=0.02)
    K.pbox(P, "paper", (0, 0, H - 0.05), (W * 0.35, 0.03, 0.02), n=4.0, c=5)
    # 中の中華まん（小さく、形だけ）
    rnd = random.Random(3)
    for shelf_z in (0.03, H * 0.48 + 0.006):
        for k in range(4):
            x = -W / 2 + 0.09 + k * (W - 0.18) / 3
            for y in (-0.08, 0.08):
                role = rnd.choice(["felt_bun", "felt_bun", "felt_tan"])
                K.pbox(P, role, (x, y, shelf_z + 0.03), (0.045, 0.045, 0.032), n=2.0, nz=2.4, c=5)
    K.steam(P, (0.0, 0.0, H * 0.48 + 0.08), 0.08, 0.012, seed=2)
    P.mark("front", (0, D / 2, 0))
    P.finish(fuzz=0.0015)


# ---------------------------------------------------------------- 缶の飲み物
def can(name, label, band, icon, hot=True):
    """フェルトを巻いた缶。上と下の縁を巻き、ふたにプルタブ。ラベルは中身の絵のアップリケ"""
    P = K.Parts(name, kind="drink")
    R, H = 0.0265, 0.104
    K.lathe(P, label, [(R * 0.9, 0.004), (R, 0.012), (R, H - 0.014), (R * 0.88, H - 0.004)], segs=K.cuts(36, 20),
            closed=False)
    K.lathe(P, "felt_tin", [(0.0, 0.0), (R * 0.9, 0.0), (R * 0.92, 0.006)], segs=K.cuts(36, 20), closed=False)
    K.lathe(P, "felt_tin", [(R * 0.86, H - 0.006), (R * 0.84, H - 0.002), (0.0, H - 0.002)], segs=K.cuts(36, 20), closed=False)
    K.ring(P, "felt_tin", (0, 0, H - 0.004), R * 0.9, 0.0035)
    K.ring(P, "felt_tin", (0, 0, 0.006), R * 0.93, 0.0035)
    # プルタブ: ふたの上の小さな輪と舌
    K.ring(P, "thread_dark", (0.0, 0.006, H), 0.006, 0.0012)
    K.box(P, "felt_tin", (0.0, -0.002, H + 0.0005), (0.008, 0.012, 0.0015))
    # 帯（温かい飲み物は赤い帯）と縫い目
    K.lathe(P, band, [(R + 0.0008, H * 0.68), (R + 0.0008, H * 0.8)], segs=K.cuts(36, 20), closed=False)
    K.stitch_ring(P, "thread", (0, 0, H * 0.66), R + 0.0012, r=0.0007, dash=0.004)
    if hot:
        K.lathe(P, "felt_red", [(R + 0.0009, H * 0.84), (R + 0.0009, H * 0.86)], segs=K.cuts(36, 20), closed=False)
    # 絵: 前（+Y）に平たいアップリケ
    y = R + 0.0015
    for role, poly in icon:
        K.extrude(P, role, poly, y, y + 0.0015, plane="XZ")
    P.finish(fuzz=0.0008)


def icon_corn():
    cob = K.circle_poly(0.009, 16, 0.0, 0.045, sx=0.7, sy=1.6)
    leaf = [(-0.004, 0.028), (-0.014, 0.036), (-0.012, 0.05), (-0.006, 0.04)]
    leaf2 = [(0.004, 0.028), (0.014, 0.036), (0.012, 0.05), (0.006, 0.04)]
    return [("felt_yellow", cob), ("felt_green", leaf), ("felt_green", leaf2)]


def icon_cup(body_role="felt_cream"):
    cup = [(-0.009, 0.034), (0.009, 0.034), (0.011, 0.054), (-0.011, 0.054)]
    handle = [(0.011, 0.04), (0.016, 0.042), (0.016, 0.05), (0.011, 0.051), (0.012, 0.048), (0.0135, 0.047),
              (0.0135, 0.044), (0.0115, 0.043)]
    return [(body_role, cup), (body_role, handle)]


def icon_heart(role="felt_cream", cy=0.045, s=0.012):
    pts = []
    for k in range(24):
        t = 2 * math.pi * k / 24
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 17 * s, cy + y / 17 * s))
    return [(role, pts)]


def icon_bean(role="felt_brown"):
    return [(role, K.circle_poly(0.008, 16, 0.0, 0.045, sx=0.75, sy=1.2))]


def icon_leaf(role="felt_green"):
    pts = [(0.0, 0.03)]
    for k in range(1, 12):
        t = k / 12
        pts.append((0.009 * math.sin(math.pi * t), 0.03 + 0.03 * t))
    pts.append((0.0, 0.06))
    for k in range(11, 0, -1):
        t = k / 12
        pts.append((-0.009 * math.sin(math.pi * t), 0.03 + 0.03 * t))
    return [(role, pts)]


# ---------------------------------------------------------------- ラーメン
def ramen(name, bowl, broth, rim, toppings, seed=0):
    P = K.Parts(name, kind="food")
    rnd = random.Random(seed)
    Rt, H = 0.1, 0.085
    seg = K.cuts(48, 24)
    K.lathe(P, bowl, [(0.0, 0.0), (0.042, 0.0), (0.045, 0.008), (0.06, 0.02), (0.09, 0.055), (Rt, H),
                      (Rt - 0.006, H + 0.002), (Rt - 0.01, H - 0.006), (0.084, 0.055), (0.05, 0.022), (0.0, 0.018)],
            segs=seg)
    # 器の外: 縁の下に雷紋のようなジグザグの縫い目
    zz = []
    for k in range(97):
        a = 2 * math.pi * k / 96
        rr = Rt - 0.004 + 0.0012
        z = H - 0.012 - (0.006 if k % 2 else 0.0)
        zz.append((rr * math.cos(a), rr * math.sin(a), z))
    K.tube(P, rim, zz, 0.0013, sides=4)
    # 汁
    K.disc(P, broth, (0, 0, H - 0.014), Rt - 0.012, 0.004, segs=seg)
    # 麺: 毛糸が波打って重なる
    for k in range(18 if not EX else 10):
        a0 = rnd.uniform(0, 2 * math.pi)
        pts = []
        for i in range(24):
            t = i / 23
            ang = a0 + t * rnd.uniform(1.5, 3.0)
            r = 0.02 + 0.055 * t
            pts.append((r * math.cos(ang) + 0.004 * math.sin(t * 40 + k), r * math.sin(ang) + 0.004 * math.cos(t * 37 + k),
                        H - 0.01 + 0.006 * (1 - t) + 0.002 * math.sin(t * 25 + k)))
        K.tube(P, "yarn_noodle", pts, 0.0032, sides=5)
    top = H - 0.004
    if "chashu" in toppings:   # 焼き豚: 茶色の円板に明るい縁
        for i, (x, y, tilt) in enumerate(((0.035, -0.02, 0.25), (0.048, 0.012, 0.3))):
            K.disc(P, "felt_brown", (x, y, top + 0.004), 0.028, 0.005, segs=24)
            K.ring(P, "felt_tan", (x, y, top + 0.0045), 0.026, 0.0028)
    if "naruto" in toppings:   # なると: 白い円板に桃色の渦
        K.disc(P, "felt_rice", (-0.035, 0.03, top + 0.005), 0.016, 0.004, segs=24)
        sp = [(-0.035 + 0.013 * (t / 3) * math.cos(t * 2 * math.pi), 0.03 + 0.013 * (t / 3) * math.sin(t * 2 * math.pi),
               top + 0.0075) for t in [i / 30 * 3 for i in range(31)]]
        K.tube(P, "felt_pink", sp, 0.0016, sides=4)
    if "egg" in toppings:   # 半分の卵
        K.pbox(P, "felt_rice", (-0.02, -0.04, top + 0.006), (0.018, 0.013, 0.008), n=2.0, nz=2.0, c=6)
        K.disc(P, "felt_yellow", (-0.02, -0.04, top + 0.013), 0.009, 0.003, segs=16)
    if "nori" in toppings:   # のり: 後ろに立てる
        K.box(P, "felt_nori", (0.0, 0.07, top + 0.025), (0.05, 0.003, 0.055), rot=(0.25, "X"))
    if "negi" in toppings:   # ねぎの小口切り
        for k in range(14):
            a = rnd.uniform(0, 2 * math.pi)
            r = rnd.uniform(0.0, 0.05)
            K.ring(P, "felt_green", (r * math.cos(a), r * math.sin(a), top + 0.006), 0.004, 0.0015, n=10)
    if "corn" in toppings:
        for k in range(16):
            a = rnd.uniform(-1.0, 0.6)
            r = rnd.uniform(0.02, 0.05)
            K.pbox(P, "felt_yellow", (r * math.cos(a) - 0.03, r * math.sin(a) + 0.01, top + 0.006), (0.004, 0.004, 0.003),
                   n=2.0, c=3)
    if "butter" in toppings:
        K.pbox(P, "felt_cream", (0.0, 0.0, top + 0.012), (0.012, 0.012, 0.008), n=6.0, c=4)
    if "menma" in toppings:
        for k in range(5):
            K.box(P, "felt_tan", (0.04 + 0.006 * k, -0.045 + 0.004 * k, top + 0.005), (0.005, 0.028, 0.004), rot=(0.4, "Z"))
    # 箸: 器の縁に渡す
    for dx in (-0.006, 0.006):
        K.tube(P, "wood_light", [(-0.13 + dx, -0.03, H + 0.004), (0.12 + dx, 0.05, H + 0.004)], [0.0035, 0.002], sides=6)
    K.steam(P, (0.0, 0.0, H + 0.01), 0.07, 0.009, seed=seed)
    P.finish(fuzz=0.0012)


# ---------------------------------------------------------------- そのほかの食べ物
def onigiri(name, filling):
    P = K.Parts(name, kind="food")
    m = P.m("felt_rice")
    n0 = len(m.bm.verts)
    C.superellipsoid(m, (0, 0, 0), (0.042, 0.018, 0.04), n_xy=2.4, n_z=2.4, cuts=K.cuts(10, 5))
    for v in C.new_verts(m, n0):   # 三角に: 上ほど細く
        t = (v.co.z + 0.04) / 0.08
        v.co.x *= 1.15 - 0.75 * t
        v.co.z += 0.04
    K.box(P, "felt_nori", (0, 0, 0.018), (0.05, 0.04, 0.03))   # のり: 下に巻く
    if filling == "ume":
        K.pbox(P, "felt_red", (0, 0.019, 0.05), (0.007, 0.002, 0.007), n=2.0, c=4)
    elif filling == "salmon":
        K.pbox(P, "felt_orange", (0, 0.019, 0.05), (0.01, 0.002, 0.006), n=3.0, c=4)
    elif filling == "konbu":
        K.pbox(P, "felt_brown", (0, 0.019, 0.05), (0.009, 0.002, 0.006), n=3.0, c=4)
    P.finish(fuzz=0.001)


def oden(name):
    """おでんの串: 三角のこんにゃく、輪切りの大根、丸い練り物 2 つ。立てて組み、卓に寝かせる"""
    P = K.Parts(name, kind="food")
    K.dowel(P, "wood_light", (0, 0, -0.03), (0, 0, 0.2), 0.0025, 6)
    tri = [(-0.025, 0.02), (0.025, 0.02), (0.0, 0.062)]
    K.extrude(P, "felt_konnyaku", tri, -0.007, 0.007, plane="XZ")
    K.disc(P, "felt_daikon", (0, 0, 0.092), 0.026, 0.02, axis="Y", segs=K.cuts(24, 12))
    K.ring(P, "felt_tan", (0, 0, 0.092), 0.024, 0.003, axis="Y", n=24)
    K.pbox(P, "felt_tan", (0, 0, 0.137), (0.018, 0.018, 0.018), n=2.0, c=6)
    K.pbox(P, "felt_brown", (0, 0, 0.172), (0.015, 0.015, 0.015), n=2.0, c=6)
    P.transform(Matrix.Translation((0, 0, 0.027)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    P.finish(fuzz=0.001)


# たい焼きの横から見た輪郭（x は頭が +、z は上が +。m）。写真で確かめた形（2026-11-01、Wikimedia Commons の Taiyaki_003.jpg）:
# 頭が大きく丸い深い体、前の下に小さな口、背に低く長いひれ、腹に小さなひれ、くびれた付け根から上下に尖った 2 つの先の尾びれ
TAI_OUTLINE = [
    (0.061, 0.003), (0.059, 0.013), (0.053, 0.023), (0.043, 0.031), (0.031, 0.036), (0.020, 0.039),
    (0.012, 0.041), (0.006, 0.040), (0.0, 0.042), (-0.006, 0.040), (-0.012, 0.041), (-0.018, 0.038), (-0.024, 0.038),   # 背びれ（ぎざぎざ）
    (-0.029, 0.031), (-0.035, 0.022), (-0.039, 0.017),   # 付け根のくびれ
    (-0.047, 0.025), (-0.057, 0.034), (-0.067, 0.042), (-0.072, 0.040),   # 尾びれの上の先
    (-0.068, 0.025), (-0.063, 0.011), (-0.064, 0.0), (-0.063, -0.011), (-0.068, -0.025),   # 尾の切れ込み
    (-0.072, -0.040), (-0.067, -0.042), (-0.057, -0.034), (-0.047, -0.025), (-0.039, -0.017),
    (-0.035, -0.022), (-0.029, -0.029), (-0.022, -0.033), (-0.016, -0.037), (-0.010, -0.034), (-0.004, -0.036),   # 腹びれ
    (0.004, -0.034), (0.016, -0.033), (0.028, -0.030), (0.040, -0.024), (0.049, -0.017), (0.055, -0.011),
    (0.058, -0.007), (0.054, -0.004), (0.060, -0.002),   # 口
]


def _seg_dist(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz + 1e-12)))
    return math.hypot(px - ax - t * dx, pz - az - t * dz), (ax + t * dx, az + t * dz)


def _outline_info(poly, x, z):
    """輪郭の中か、縁までの距離、縁のいちばん近い点"""
    inside = False
    best, near = 1e9, (x, z)
    n = len(poly)
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        if (az > z) != (bz > z) and x < (bx - ax) * (z - az) / (bz - az) + ax:
            inside = not inside
        d, q = _seg_dist(x, z, ax, az, bx, bz)
        if d < best:
            best, near = d, q
    return inside, best, near


def _tai_thick(x, d):
    """表の面の高さ（片側）: 胴はふっくら 14 mm、尾とひれは薄く。縁へ丸く落ちる"""
    body = 0.011 if x > -0.024 else (0.0035 if x < -0.042 else 0.0035 + 0.0075 * (x + 0.042) / 0.018)
    k = min(d / 0.011, 1.0)
    return body * math.sqrt(max(0.0, 1.0 - (1.0 - k) ** 3))   # 上は平たく、縁できりっと落ちる


def taiyaki(name):
    """たい焼き: きつね色のフェルト 2 枚を縁で縫い合わせた鯛。盛り上がった線（えら・うろこ・ひれの筋・目の輪）は、
    焼き色のフェルトのひもを縫い付けて表す。寝かせて置く（片面が上）。長さ 13 cm、高さ 8 cm、厚さ 2.2 cm"""
    P = K.Parts(name, kind="food", tris=2600)
    poly = TAI_OUTLINE
    step = 0.0025 if not EX else 0.003
    xs = [-0.075 + step * i for i in range(int(0.14 / step) + 2)]
    zs = [-0.045 + step * j for j in range(int(0.09 / step) + 2)]
    info = {}
    for i, x in enumerate(xs):
        for j, z in enumerate(zs):
            info[i, j] = _outline_info(poly, x, z)

    def height(x, z):
        ins, d, _q = _outline_info(poly, x, z)
        return _tai_thick(x, d) if ins else 0.0

    for side in (1, -1):   # 表（+Y）と裏。胴はきつね色、尾とひれの先は焼き色が濃い
        verts = {}

        def v(i, j, role):
            if (role, i, j) not in verts:
                ins, d, near = info[i, j]
                x, z = (xs[i], zs[j]) if ins else near   # 外の点は縁へ寄せる（縁で表と裏が合う）
                y = _tai_thick(x, d) if ins else 0.0
                verts[role, i, j] = P.m(role).bm.verts.new((x, side * y, z))
            return verts[role, i, j]

        for i in range(len(xs) - 1):
            for j in range(len(zs) - 1):
                corners = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                if not any(info[c][0] for c in corners):
                    continue
                cx, cz = xs[i] + step / 2, zs[j] + step / 2
                toast = cx < -0.041 or abs(cz) > 0.034
                role = "felt_toast" if toast else "felt_taiyaki"
                vs = [v(c[0], c[1], role) for c in corners]
                if len({id(q) for q in vs}) < 3:
                    continue
                if side < 0:
                    vs.reverse()
                try:
                    P.m(role).bm.faces.new(vs)
                except ValueError:
                    pass

        def on(x, z, lift=0.0012):
            return (x, side * (height(x, z) + lift), z)

        def cord(pts, r=0.0013, role="felt_curry"):
            K.tube(P, role, [on(x, z) for x, z in pts], r, sides=5)

        # 目: 二重の輪と、まんなかの粒
        ex, ez = 0.043, 0.014
        for rr in (0.0045, 0.0085):
            cord([(ex + rr * math.cos(a), ez + rr * math.sin(a)) for a in [2 * math.pi * k / 20 for k in range(21)]], 0.0011)
        K.pbox(P, "felt_brown", on(ex, ez, 0.0008), (0.0025, 0.0018, 0.0025), n=2.0, c=3)
        # えら: 目の後ろの大きな弧（上から下へ、尾の側へふくらむ）
        cord([(0.05 - 0.032 * math.cos(a), 0.032 * math.sin(a) * 0.95) for a in [math.radians(t) for t in range(-62, 63, 6)]], 0.0016)
        # 口
        cord([(0.058, -0.0045), (0.052, -0.006), (0.047, -0.004)], 0.001)
        # うろこ: 半円の弧（開きは頭の側）を互い違いの列に
        for c in range(6):
            x0 = 0.012 - 0.0072 * c
            for r in range(-3, 4):
                z0 = r * 0.0078 + (0.0039 if c % 2 else 0.0)
                if not _outline_info(poly, x0 - 0.004, z0)[0] or _outline_info(poly, x0 - 0.004, z0)[1] < 0.007:
                    continue
                cord([(x0 - 0.004 * math.sin(a), z0 + 0.004 * math.cos(a)) for a in [math.pi * k / 8 for k in range(9)]], 0.0009)
        # 胸びれ: えらの後ろの小さな扇
        for k in range(4):
            a = math.radians(-150 + 22 * k)
            cord([(0.016, -0.012), (0.016 + 0.011 * math.cos(a), -0.012 + 0.011 * math.sin(a))], 0.0009)
        # 尾びれの筋: 付け根から扇に
        for k in range(7):
            t = k / 6
            tip = (-0.069, 0.036 - 0.072 * t)
            mid = (-0.055, 0.02 - 0.04 * t)
            cord([(-0.04, 0.0), mid, tip], 0.0011)
        # 背びれ・腹びれの筋
        for k in range(5):
            x = 0.012 - 0.008 * k
            cord([(x, 0.031), (x - 0.002, 0.038)], 0.0009)
        for k in range(3):
            x = -0.004 - 0.006 * k
            cord([(x, -0.028), (x - 0.002, -0.034)], 0.0009)
    for role in ("felt_taiyaki", "felt_toast"):   # 縁に寄せて重なった点を合わせ（表と裏もここで閉じる）、潰れた面を消す
        bm = P.m(role).bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0003)
        bmesh.ops.dissolve_degenerate(bm, dist=0.0003, edges=bm.edges)
    # 縁: 2 枚を合わせた縫い目（ふくらんだ縁と、なみ縫い）
    ring = poly + [poly[0]]
    K.tube(P, "felt_toast", [(x, 0.0, z) for x, z in ring], 0.0022, sides=6)
    K.stitch_line(P, "thread_dark", [(x * 1.0, 0.0024, z * 1.0) for x, z in ring], r=0.0007, dash=0.004)
    # 寝かせる: 表（+Y）を上へ
    P.transform(Matrix.Translation((0, 0, 0.0115)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    P.finish(fuzz=0.0004)   # 皮はぱりっと: 毛羽は控えめ


def mikan(name, n=3):
    """みかん: 橙のフェルトの玉にへたと葉。重ねて盛る"""
    P = K.Parts(name, kind="food")
    pos = [(0, 0, 0.03), (0.055, 0.0, 0.03), (0.027, 0.045, 0.03), (0.027, 0.016, 0.075)][:n]
    for i, (x, y, z) in enumerate(pos):
        K.pbox(P, "felt_orange", (x, y, z), (0.032, 0.032, 0.028), n=2.0, c=7)
        K.disc(P, "felt_green", (x, y, z + 0.028), 0.006, 0.002, segs=10)
        if i == len(pos) - 1:
            K.extrude(P, "felt_green", K.circle_poly(0.012, 14, sx=1.0, sy=0.45), -0.001, 0.001, plane="XY",
                      offset=(x + 0.01, y, z + 0.03), rot=(0.4, "Y"))
    P.finish(fuzz=0.0012)


def yunomi(name, role, tea="felt_tea"):
    """湯のみ: 太い木の器にお茶。縁の下を一周なみ縫い"""
    P = K.Parts(name, kind="drink")
    R, H = 0.036, 0.085
    K.lathe(P, role, [(0.0, 0.0), (R * 0.85, 0.0), (R, 0.01), (R * 1.02, H), (R * 0.9, H), (R * 0.86, 0.012), (0.0, 0.012)],
            segs=K.cuts(36, 20))
    K.disc(P, tea, (0, 0, H - 0.012), R * 0.86, 0.003, segs=K.cuts(36, 20))
    K.stitch_ring(P, "thread", (0, 0, H - 0.015), R * 1.02 + 0.0015, r=0.0012, dash=0.006)
    K.steam(P, (0, 0, H), 0.05, 0.006, seed=5)
    P.finish(fuzz=0.001)


def dango(name):
    """三色団子: 桃・白・緑の玉を串に。卓に寝かせる"""
    P = K.Parts(name, kind="food")
    K.dowel(P, "wood_light", (0, 0, -0.03), (0, 0, 0.13), 0.0025, 6)
    for z, role in ((0.025, "felt_green"), (0.058, "felt_rice"), (0.091, "felt_pink")):
        K.pbox(P, role, (0, 0, z), (0.017, 0.017, 0.016), n=2.0, c=7)
    P.transform(Matrix.Translation((0, 0, 0.017)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    P.finish(fuzz=0.001)


def curry(name):
    """カレーライス: 楕円の皿に、綿のご飯の山と、茶色の汁。具の角切り"""
    P = K.Parts(name, kind="food")
    rnd = random.Random(8)
    K.lathe(P, "felt_cream", [(0.0, 0.0), (0.08, 0.0), (0.11, 0.015), (0.125, 0.025), (0.118, 0.027), (0.1, 0.018),
                              (0.0, 0.012)], segs=K.cuts(40, 20))
    K.pbox(P, "felt_rice", (-0.03, 0.0, 0.025), (0.05, 0.07, 0.025), n=2.0, nz=2.2, c=8)
    K.extrude(P, "felt_curry", K.circle_poly(0.06, 24, 0.03, 0.0, sx=0.9, sy=1.25), 0.014, 0.02, plane="XY")
    for k in range(7):
        x, y = rnd.uniform(0.0, 0.07), rnd.uniform(-0.05, 0.05)
        role = rnd.choice(["felt_orange", "felt_tan", "felt_brown"])
        K.pbox(P, role, (x, y, 0.024), (0.008, 0.008, 0.006), n=4.0, c=3)
    K.tube(P, "felt_tin", [(0.06, -0.09, 0.03), (0.11, 0.05, 0.03)], 0.004, sides=6)   # さじ
    K.pbox(P, "felt_tin", (0.05, -0.105, 0.03), (0.012, 0.018, 0.004), n=2.0, c=4, rot=(0.35, "Z"))
    P.finish(fuzz=0.001)


def mug(name, body, drink, topping=None):
    """マグ: ふっくらしたフェルトの器に取っ手、縁をかがる。中の飲み物と、上の飾り（綿のマシュマロ・ゆずの輪切り）"""
    P = K.Parts(name, kind="drink")
    R, H = 0.042, 0.095
    K.lathe(P, body, [(0.0, 0.0), (R * 0.9, 0.0), (R, 0.01), (R * 1.04, H * 0.6), (R, H), (R * 0.88, H), (R * 0.86, 0.012),
                      (0.0, 0.012)], segs=K.cuts(36, 20))
    K.ring(P, "thread", (0, 0, H - 0.002), R * 0.98, 0.0022, n=36)
    K.tube(P, body, [(R * 0.95, 0, H * 0.78), (R + 0.03, 0, H * 0.72), (R + 0.034, 0, H * 0.45), (R + 0.02, 0, H * 0.25),
                     (R * 0.98, 0, H * 0.22)], 0.009, sides=10)
    K.disc(P, drink, (0, 0, H - 0.014), R * 0.86, 0.003, segs=K.cuts(36, 20))
    if topping == "marshmallow":
        for k, (dx, dy) in enumerate(((0.0, 0.0), (0.016, 0.01), (-0.012, 0.015), (0.008, -0.016))):
            K.pbox(P, "cotton", (dx, dy, H - 0.006), (0.009, 0.009, 0.008), n=4.0, c=3)
    elif topping == "yuzu":
        K.disc(P, "felt_yellow", (0.008, 0.0, H - 0.01), 0.018, 0.003, segs=16)
        K.ring(P, "felt_cream", (0.008, 0.0, H - 0.008), 0.014, 0.0015, n=16)
    elif topping == "corn":
        rnd = random.Random(30)
        for k in range(10):
            a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.0, R * 0.7)
            K.pbox(P, "felt_gold", (r * math.cos(a), r * math.sin(a), H - 0.01), (0.003, 0.003, 0.0025), n=3.0, c=2)
        for k in range(4):
            K.pbox(P, "felt_green", (0.01 * k - 0.015, 0.006 * (k % 2), H - 0.009), (0.002, 0.002, 0.001), n=2.0, c=2)
    elif topping == "teabag":
        K.tube(P, "thread", [(-R * 0.6, 0.0, H - 0.012), (-R * 0.95, 0.0, H + 0.004), (-R - 0.006, 0.0, H - 0.02), (-R - 0.007, 0.0, H - 0.035)],
               0.0007, sides=4)
        K.box(P, "paper_white", (-R - 0.008, 0.0, H - 0.043), (0.002, 0.016, 0.018))
        K.box(P, "felt_red", (-R - 0.0095, 0.0, H - 0.038), (0.001, 0.012, 0.004))
    K.steam(P, (0, 0, H), 0.06, 0.007, seed=len(name))
    P.mark("hand", (R + 0.03, 0, H * 0.5))
    P.finish(fuzz=0.001)


def noodle_bowl(name, bowl, broth, noodle_role, thick, toppings, seed=0):
    """そば・うどん: 器と汁、毛糸の麺。かき揚げ（ふくらんだ茶色）か、きつね（三角の油揚げ）"""
    P = K.Parts(name, kind="food")
    rnd = random.Random(seed)
    Rt, H = 0.095, 0.075
    seg = K.cuts(48, 24)
    K.lathe(P, bowl, [(0.0, 0.0), (0.04, 0.0), (0.045, 0.008), (0.085, 0.05), (Rt, H), (Rt - 0.006, H + 0.002),
                      (Rt - 0.01, H - 0.006), (0.08, 0.05), (0.04, 0.02), (0.0, 0.018)], segs=seg)
    K.stitch_ring(P, "thread", (0, 0, H - 0.012), Rt - 0.004 + 0.0015, r=0.0013, dash=0.008)
    K.disc(P, broth, (0, 0, H - 0.014), Rt - 0.012, 0.004, segs=seg)
    for k in range(14 if not EX else 8):
        a0 = rnd.uniform(0, 2 * math.pi)
        pts = []
        for i in range(20):
            t = i / 19
            ang = a0 + t * rnd.uniform(1.2, 2.4)
            r = 0.015 + 0.055 * t
            pts.append((r * math.cos(ang), r * math.sin(ang), H - 0.01 + 0.005 * (1 - t) + 0.002 * math.sin(t * 20 + k)))
        K.tube(P, noodle_role, pts, thick, sides=5)
    top = H - 0.004
    if "kakiage" in toppings:
        K.pbox(P, "felt_tan", (0.01, 0.0, top + 0.012), (0.04, 0.035, 0.014), n=2.0, c=6)
        for k in range(8):
            a = rnd.uniform(0, 2 * math.pi)
            K.pbox(P, rnd.choice(["felt_orange", "felt_green", "felt_tan"]), (0.01 + 0.03 * math.cos(a), 0.025 * math.sin(a), top + 0.022),
                   (0.006, 0.003, 0.004), n=3.0, c=3)
    if "kitsune" in toppings:
        K.extrude(P, "felt_tan", [(-0.04, -0.03), (0.04, -0.03), (0.0, 0.04)], top + 0.004, top + 0.012)
    if "negi" in toppings:
        for k in range(10):
            a = rnd.uniform(0, 2 * math.pi)
            r = rnd.uniform(0.0, 0.05)
            K.ring(P, "felt_green", (r * math.cos(a), r * math.sin(a), top + 0.006), 0.004, 0.0015, n=10)
    if "kamaboko" in toppings:
        K.pbox(P, "felt_pink", (-0.045, 0.02, top + 0.006), (0.012, 0.005, 0.008), n=3.0, c=3)
    K.steam(P, (0.0, 0.0, H + 0.01), 0.07, 0.009, seed=seed)
    P.finish(fuzz=0.0012)


# ---------------------------------------------------------------- 雪だるまの店の料理（2026-11-01 代表と決めた品書き。design/snowman-food/）
C.HEX.update({"felt_azuki": "6A2A34", "yarn_sauce": "9A5A2A", "felt_crumb": "C98A3E", "felt_silver": "9AA6B0",
              "felt_shell": "8E8A84", "felt_potato": "E8C878", "felt_syrup": "8A4A1E",
              "felt_taiyaki": "C98838", "felt_toast": "9E5E22"})


def plate(P, role, R, rim="thread"):
    """浅い皿: フェルトの円い皿の縁をかがる"""
    K.lathe(P, role, [(0.0, 0.0), (R * 0.72, 0.0), (R * 0.92, 0.01), (R, 0.018), (R * 0.95, 0.02), (R * 0.8, 0.012), (0.0, 0.008)],
            segs=K.cuts(40, 20))
    K.stitch_ring(P, rim, (0, 0, 0.0165), R * 0.97, r=0.0011, dash=0.007)


def crumbs(P, rnd, cx, cy, rx, ry, z, n, role="felt_crumb"):
    """衣のパン粉: 小さなフェルトの粒を、楕円の上にばらまく"""
    for k in range(n if not EX else n // 3):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.0, 1.0) ** 0.5
        K.pbox(P, role, (cx + rx * r * math.cos(a), cy + ry * r * math.sin(a), z - 0.004 * r * r), (0.003, 0.003, 0.002), n=3.0, c=2)


def korokke(name):
    """コロッケ: クラフト紙に、パン粉の衣の小判形を 2 つ。脇にキャベツの千切り（毛糸）"""
    P = K.Parts(name, kind="food")
    rnd = random.Random(21)
    K.box(P, "paper_kraft", (0, 0, 0.001), (0.15, 0.12, 0.002), rot=(0.12, "Z"))
    for x, y in ((-0.028, -0.005), (0.032, 0.012)):
        K.pbox(P, "felt_gold", (x, y, 0.016), (0.034, 0.024, 0.014), n=2.0, nz=2.6, c=6)
        crumbs(P, rnd, x, y, 0.03, 0.02, 0.03, 40)
    for k in range(12 if not EX else 5):
        a0 = rnd.uniform(-0.4, 0.4)
        x0, y0 = -0.035 + rnd.uniform(-0.02, 0.02), 0.045 + rnd.uniform(-0.008, 0.008)
        K.tube(P, "thread_green",
               [(x0, y0, 0.004), (x0 + 0.03 * math.cos(a0), y0 + 0.012 * math.sin(a0) + 0.004, 0.006)], 0.0016, sides=4)
    P.finish(fuzz=0.0012)


def hashbrown(name):
    """ハッシュドポテト: 紙の袋（上が開く）に、細切りを押し固めた小判形。表に細切りの筋を縫う"""
    P = K.Parts(name, kind="food")
    K.extrude(P, "paper_white", K.round_rect(0.085, 0.022, 0.006), 0.0, 0.055)
    K.stitch_line(P, "thread_red", [(-0.04, 0.0115, 0.045), (0.04, 0.0115, 0.045)], r=0.0012, dash=0.008)
    K.pbox(P, "felt_gold", (0, 0.0, 0.065), (0.04, 0.009, 0.032), n=2.4, nz=2.4, c=6)
    rnd = random.Random(22)
    for side in (1, -1):
        for k in range(9):
            x = -0.03 + 0.0075 * k
            z0 = 0.05 + rnd.uniform(0.0, 0.01)
            K.stitch_line(P, "thread_dark", [(x, side * 0.0095, z0), (x + rnd.uniform(-0.006, 0.006), side * 0.0095, z0 + 0.03)],
                          r=0.0008, dash=0.005)
    P.finish(fuzz=0.0012)


def fries(name):
    """ポテト: 赤いフェルトの紙箱（前が低い）に、細い棒のポテトを立てて差す"""
    P = K.Parts(name, kind="food")
    K.lathe(P, "felt_red", [(0.0, 0.0), (0.028, 0.0), (0.042, 0.08), (0.038, 0.08), (0.025, 0.004), (0.0, 0.004)],
            segs=K.cuts(4, 4), rot=(math.pi / 4, "Z"))
    K.stitch_ring(P, "thread", (0, 0, 0.07), 0.043, r=0.0011, dash=0.007)
    rnd = random.Random(23)
    for k in range(16 if not EX else 9):
        x, y = rnd.uniform(-0.016, 0.016), rnd.uniform(-0.012, 0.012)
        tx = rnd.uniform(-0.15, 0.15)
        h = rnd.uniform(0.085, 0.115)
        K.box(P, "felt_potato", (x + math.sin(tx) * h / 2, y, math.cos(tx) * h / 2 + 0.012), (0.008, 0.008, h), rot=(tx, "Y"))
    P.finish(fuzz=0.001)


def hotsand(name):
    """ホットサンド: 三角に切った 2 切れを紙に。焼き色の格子を縫い、切り口からチーズ（黄のフェルト）"""
    P = K.Parts(name, kind="food")
    K.box(P, "paper_white", (0, 0, 0.001), (0.15, 0.12, 0.002), rot=(-0.1, "Z"))
    for s, dx in ((1, 0.018), (-1, -0.018)):
        tri = [(0.0, -0.055 * s), (0.0, 0.055 * s), (0.06 * s, 0.0)] if s > 0 else [(0.0, 0.055), (0.0, -0.055), (-0.06, 0.0)]
        K.extrude(P, "felt_gold", tri, 0.002, 0.024, offset=(dx, 0, 0))
        for k in range(3):
            o = 0.012 + 0.014 * k
            K.stitch_line(P, "thread_dark", [(dx + s * o, -0.045 + o * 0.8, 0.0245), (dx + s * o, 0.045 - o * 0.8, 0.0245)],
                          r=0.0011, dash=0.006)
        K.box(P, "felt_yellow", (dx + s * 0.002, 0.0, 0.013), (0.006, 0.07, 0.006))
    P.finish(fuzz=0.0012)


def yakiimo(name):
    """焼き芋: 新聞紙（クラフト紙）にくるんだ紫の芋を、半分に割って黄色い中身。綿の湯気"""
    P = K.Parts(name, kind="food")
    K.extrude(P, "paper_kraft", [(-0.075, -0.05), (0.06, -0.06), (0.075, 0.05), (-0.06, 0.06)], 0.0, 0.003)
    K.pbox(P, "paper_kraft", (-0.04, 0.0, 0.015), (0.035, 0.045, 0.015), n=2.0, nz=2.0, c=5)
    K.pbox(P, "felt_purple", (0.0, 0.022, 0.022), (0.055, 0.021, 0.019), n=2.0, nz=2.2, c=6)   # 丸ごと 1 本
    # 割った半分: 黄色い断面を上へ向けて斜めに立てかける
    half = Matrix.Translation((0.01, -0.026, 0.02)) @ Matrix.Rotation(-0.7, 4, "Y")
    m = P.m("felt_purple")
    n0 = len(m.bm.verts)
    C.superellipsoid(m, (-0.02, 0, 0), (0.028, 0.02, 0.018), n_xy=2.0, n_z=2.2, cuts=K.cuts(10, 6))
    for v in C.new_verts(m, n0):
        v.co.x = min(v.co.x, 0.0)
    C.place(m, n0, half)
    m = P.m("felt_yellow")
    n0 = len(m.bm.verts)
    C.superellipsoid(m, (0.0, 0, 0), (0.004, 0.0185, 0.0165), n_xy=2.0, n_z=2.0, cuts=K.cuts(8, 5))
    C.place(m, n0, half)
    K.steam(P, (0.03, -0.026, 0.05), 0.06, 0.008, seed=24)
    P.finish(fuzz=0.0012)


def hotcake(name):
    """ホットケーキ: クリームの皿に、厚い生地を 2 枚。上にバターの角と、垂れるシロップ（茶のフェルト）"""
    P = K.Parts(name, kind="food")
    plate(P, "felt_cream", 0.1)
    for k, z in enumerate((0.012, 0.036)):
        K.lathe(P, "felt_tan", [(0.0, z), (0.062, z), (0.066, z + 0.01), (0.062, z + 0.022), (0.0, z + 0.022)], segs=K.cuts(36, 18))
        K.disc(P, "felt_gold", (0, 0, z + 0.0225), 0.06, 0.002, segs=K.cuts(36, 18))
    K.extrude(P, "felt_syrup", K.circle_poly(0.045, 20, 0.004, 0.0, sx=1.0, sy=0.85), 0.0595, 0.0615)
    for a in (0.4, 2.3, 4.0):   # 縁から垂れる
        K.box(P, "felt_syrup", (0.0645 * math.cos(a), 0.0645 * math.sin(a), 0.05), (0.003, 0.012, 0.02), rot=(a, "Z"))
    K.pbox(P, "felt_cream", (0.0, 0.0, 0.07), (0.012, 0.012, 0.008), n=6.0, c=4)
    P.finish(fuzz=0.0012)


def sanma(name):
    """焼きサンマ: 藍の長皿に、銀のフェルトの細い魚。背は濃く、焼き目を縫う。大根おろし（綿）とすだち"""
    P = K.Parts(name, kind="food")
    K.pbox(P, "felt_navy2", (0, 0, 0.007), (0.13, 0.045, 0.007), n=6.0, c=6)
    K.pbox(P, "felt_silver", (-0.005, 0.0, 0.026), (0.1, 0.014, 0.012), n=2.0, nz=2.0, c=8)
    K.pbox(P, "felt_charcoal", (-0.005, 0.0, 0.034), (0.095, 0.008, 0.006), n=2.0, nz=2.0, c=6)
    K.extrude(P, "felt_silver", [(0.092, 0.0), (0.122, 0.016), (0.116, 0.0), (0.122, -0.016)], 0.02, 0.032)
    for k in range(5):
        x = -0.07 + 0.03 * k
        K.stitch_line(P, "thread_dark", [(x, -0.012, 0.035), (x + 0.012, 0.012, 0.035)], r=0.0011, dash=0.005)
    K.disc(P, "felt_charcoal", (-0.09, 0.0125, 0.03), 0.003, 0.002, axis="Y", segs=10)   # 目
    K.pbox(P, "cotton", (-0.085, 0.03, 0.02), (0.016, 0.012, 0.01), n=2.0, c=5)          # 大根おろし
    K.disc(P, "felt_green", (-0.06, 0.032, 0.018), 0.011, 0.006, axis="Y", segs=14)        # すだち
    K.disc(P, "felt_yellow", (-0.06, 0.0355, 0.018), 0.009, 0.001, axis="Y", segs=14)
    P.finish(fuzz=0.001)


def kaki(name):
    """焼き牡蠣: 白い角皿に、ごつごつした灰色の殻を 2 つ。中にふっくらした身と、レモン"""
    P = K.Parts(name, kind="food")
    rnd = random.Random(26)
    K.pbox(P, "felt_cream", (0, 0, 0.005), (0.11, 0.07, 0.005), n=6.0, c=6)
    for x, y, yaw in ((-0.045, -0.01, 0.3), (0.05, 0.012, -0.4)):
        m = P.m("felt_shell")
        n0 = len(m.bm.verts)
        C.superellipsoid(m, (0, 0, 0), (0.045, 0.03, 0.012), n_xy=2.0, n_z=2.0, cuts=K.cuts(10, 6))
        for v in C.new_verts(m, n0):   # ごつごつ
            v.co *= 1.0 + 0.12 * math.sin(v.co.x * 160 + rnd.random()) * math.cos(v.co.y * 140)
        C.place(m, n0, Matrix.Translation((x, y, 0.018)) @ Matrix.Rotation(yaw, 4, "Z"))
        K.pbox(P, "felt_cream", (x, y, 0.028), (0.026, 0.017, 0.008), n=2.0, c=5, rot=(yaw, "Z"))
        K.ring(P, "felt_tan", (x, y, 0.027), 0.022, 0.0025, n=20)
    K.extrude(P, "felt_yellow", [(0.0, 0.0), (0.03, -0.006), (0.03, 0.006)], 0.01, 0.022, offset=(0.02, -0.045, 0))
    P.finish(fuzz=0.001)


def yakisoba(name):
    """焼きそば: クリームの皿に、ソースの色の毛糸の麺。キャベツ・豚・紅しょうが・青のり"""
    P = K.Parts(name, kind="food")
    rnd = random.Random(27)
    plate(P, "felt_cream", 0.1)
    for k in range(20 if not EX else 10):
        a0 = rnd.uniform(0, 2 * math.pi)
        pts = []
        for i in range(18):
            t = i / 17
            ang = a0 + t * rnd.uniform(1.0, 2.2)
            r = 0.012 + 0.05 * t
            pts.append((r * math.cos(ang), r * math.sin(ang), 0.022 + 0.012 * (1 - t) + 0.003 * math.sin(t * 30 + k)))
        K.tube(P, "yarn_sauce", pts, 0.003, sides=5)
    for k in range(8):
        a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.0, 0.045)
        K.pbox(P, rnd.choice(["felt_green", "felt_green", "felt_tan"]), (r * math.cos(a), r * math.sin(a), 0.036),
               (0.008, 0.006, 0.002), n=3.0, c=3, rot=(rnd.uniform(0, 3), "Z"))
    for k in range(4):
        K.box(P, "felt_red", (0.018 + 0.004 * k, -0.012 + 0.003 * k, 0.04), (0.012, 0.002, 0.002), rot=(0.5, "Z"))
    for k in range(18 if not EX else 6):
        a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.0, 0.05)
        K.pbox(P, "felt_green", (r * math.cos(a), r * math.sin(a), 0.038), (0.0015, 0.0015, 0.001), n=2.0, c=2)
    K.steam(P, (0, 0, 0.045), 0.05, 0.007, seed=27)
    P.finish(fuzz=0.0012)


def wan(P, role, R, H):
    """お椀"""
    K.lathe(P, role, [(0.0, 0.0), (R * 0.45, 0.0), (R * 0.5, 0.008), (R * 0.85, H * 0.5), (R, H), (R * 0.94, H + 0.001),
                      (R * 0.8, H * 0.55), (R * 0.4, 0.014), (0.0, 0.012)], segs=K.cuts(40, 20))
    K.stitch_ring(P, "thread", (0, 0, H - 0.008), R * 0.99, r=0.0011, dash=0.006)


def oshiruko(name):
    """お汁粉: 赤い椀にあずき色の汁と小豆の粒。焼き目のついた白い餅を 2 つ。綿の湯気"""
    P = K.Parts(name, kind="drink")
    rnd = random.Random(28)
    R, H = 0.055, 0.055
    wan(P, "felt_red", R, H)
    K.disc(P, "felt_azuki", (0, 0, H - 0.01), R * 0.88, 0.003, segs=K.cuts(36, 18))
    for k in range(14 if not EX else 6):
        a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.0, R * 0.8)
        K.pbox(P, "felt_azuki", (r * math.cos(a), r * math.sin(a), H - 0.008), (0.004, 0.003, 0.003), n=2.0, c=2)
    for x, y, yaw in ((-0.012, 0.006, 0.3), (0.016, -0.01, -0.2)):
        K.pbox(P, "felt_rice", (x, y, H - 0.004), (0.016, 0.013, 0.008), n=3.0, c=4, rot=(yaw, "Z"))
        K.disc(P, "felt_tan", (x + 0.004, y, H + 0.004), 0.005, 0.0015, segs=10)
    K.steam(P, (0, 0, H), 0.06, 0.007, seed=28)
    P.finish(fuzz=0.001)


def corn_potage(name):
    """コーンポタージュ: クリームのマグに黄色のスープ。コーンの粒とパセリ"""
    mug(name, "felt_cream", "felt_yellow", "corn")


def clam_chowder(name):
    """クラムチャウダー: 藍の深皿にクリームのスープ。人参・じゃがいもの角切りと小さな貝。横にクラッカー"""
    P = K.Parts(name, kind="drink")
    rnd = random.Random(29)
    R, H = 0.065, 0.045
    wan(P, "felt_navy2", R, H)
    K.disc(P, "felt_cream", (0, 0, H - 0.008), R * 0.88, 0.003, segs=K.cuts(36, 18))
    for k in range(9):
        a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.0, R * 0.75)
        K.pbox(P, rnd.choice(["felt_orange", "felt_potato", "felt_potato"]), (r * math.cos(a), r * math.sin(a), H - 0.005),
               (0.005, 0.005, 0.004), n=4.0, c=3)
    for k in range(3):
        a = k * 2.1 + 0.4
        K.extrude(P, "felt_shell", K.circle_poly(0.008, 10, 0, 0, sx=1.0, sy=0.7), H - 0.006, H - 0.002,
                  offset=(0.03 * math.cos(a), 0.03 * math.sin(a), 0))
    K.pbox(P, "felt_tan", (R + 0.03, -0.02, 0.004), (0.022, 0.022, 0.004), n=6.0, c=4)   # クラッカー
    for i in range(3):
        for j in range(3):
            K.disc(P, "felt_brown", (R + 0.016 + 0.014 * i, -0.034 + 0.014 * j, 0.0085), 0.0015, 0.001, segs=6)
    K.steam(P, (0, 0, H), 0.05, 0.006, seed=29)
    P.finish(fuzz=0.001)


def milk_tea(name):
    """ミルクティー: 桃色のマグに、ミルクティーの色。縁からティーバッグの糸と紙の札"""
    mug(name, "felt_pink", "felt_tan", "teabag")


# ---------------------------------------------------------------- 組む
bun("nikuman", "felt_bun")
bun("anman", "felt_bun", "dot", "felt_red")
bun("pizzaman", "felt_tan")
bun("curryman", "felt_yellow", "line", "felt_brown")
bun_case()
can("can_cornsoup", "felt_yellow", "felt_cream", icon_corn())
can("can_cocoa", "felt_brown", "felt_cream", icon_cup("felt_cream") + icon_heart("felt_red", 0.066, 0.006))
can("can_coffee", "felt_navy2", "felt_tan", icon_bean("felt_tan"))
can("can_tea", "felt_tea", "felt_cream", icon_leaf("felt_green"))
can("can_shiruko", "felt_purple", "felt_cream", icon_heart("felt_cream"))
ramen("ramen_shoyu", "felt_red", "felt_broth", "thread", ["chashu", "naruto", "egg", "nori", "negi", "menma"], seed=1)
ramen("ramen_miso", "felt_navy2", "felt_broth_miso", "thread", ["chashu", "corn", "butter", "negi", "menma"], seed=2)
ramen("ramen_shio", "felt_cream", "felt_broth_shio", "thread_red", ["chashu", "egg", "naruto", "negi"], seed=3)
onigiri("onigiri_ume", "ume")
onigiri("onigiri_salmon", "salmon")
onigiri("onigiri_konbu", "konbu")
oden("oden")
taiyaki("taiyaki")
mikan("mikan", 4)
yunomi("yunomi_wood", "wood_light")
yunomi("yunomi_navy", "felt_navy2")
dango("dango")
curry("curry")
mug("mug_cocoa", "felt_red", "felt_brown", "marshmallow")
mug("mug_milk", "felt_navy2", "felt_cream")
mug("mug_yuzu", "felt_cream", "felt_yellow", "yuzu")
noodle_bowl("soba", "felt_charcoal" if "felt_charcoal" in C.HEX else "felt_navy2", "felt_broth", "yarn_soba", 0.0028,
            ["kakiage", "negi"], seed=4)
noodle_bowl("udon", "felt_cream", "felt_broth_shio", "yarn_cream", 0.0055, ["kitsune", "negi", "kamaboko"], seed=5)
korokke("korokke")
hashbrown("hashbrown")
fries("fries")
hotsand("hotsand")
yakiimo("yakiimo")
hotcake("hotcake")
sanma("sanma")
kaki("kaki")
yakisoba("yakisoba")
oshiruko("oshiruko")
corn_potage("mug_corn")
clam_chowder("clam_chowder")
milk_tea("mug_milktea")

SHOP_MENU = ["onigiri_salmon", "taiyaki", "nikuman", "korokke", "hashbrown", "fries", "hotsand", "yakiimo", "hotcake", "sanma", "kaki",
             "yakisoba", "ramen_shoyu", "udon", "soba", "mug_cocoa", "oshiruko", "mug_corn", "clam_chowder", "yunomi_navy", "mug_milk",
             "mug_milktea"]   # 雪だるまの店の品書きの順（design/snowman-food/）

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
elif A.icons:   # 雪だるまの店の画面のアイコン（game/props/food/icons/）
    K.render_icons(A.icons, [n for n in SHOP_MENU if not A.only or n in A.only.split(",")], size=256, pad=1.12)
else:
    groups = {
        "buns": ["nikuman", "anman", "pizzaman", "curryman"],
        "cans": ["can_cornsoup", "can_cocoa", "can_coffee", "can_tea", "can_shiruko"],
        "ramen": ["ramen_shoyu", "ramen_miso", "ramen_shio"],
        "snacks": ["onigiri_ume", "onigiri_salmon", "onigiri_konbu", "oden", "taiyaki", "mikan", "yunomi_wood",
                   "yunomi_navy", "dango", "curry"],
        "more": ["mug_cocoa", "mug_milk", "mug_yuzu", "soba", "udon"],
        "shop": ["korokke", "hashbrown", "fries", "hotsand", "yakiimo", "hotcake", "sanma"],
        "shop2": ["kaki", "yakisoba", "oshiruko", "mug_corn", "clam_chowder", "mug_milktea"],
    }
    roots = {r.name: r for r, p in K.made}
    TZ = 0.75
    K.table(0.55, -0.45, TZ, 1.9, 1.5)
    K.grid_place([roots[n] for n in groups["buns"]], 4, 0.13, 0.0, x0=-0.25, y0=0.05, z=TZ)
    K.grid_place([roots[n] for n in groups["cans"]], 5, 0.075, 0.0, x0=0.4, y0=0.12, z=TZ)
    K.grid_place([roots[n] for n in groups["ramen"]], 3, 0.27, 0.0, x0=-0.15, y0=-0.25, z=TZ)
    K.grid_place([roots[n] for n in groups["snacks"]], 5, 0.16, 0.2, x0=0.0, y0=-0.62, z=TZ)
    K.grid_place([roots[n] for n in groups["more"]], 5, 0.18, 0.0, x0=0.25, y0=-0.98, z=TZ)
    if A.views.startswith("taiyaki"):   # たい焼きだけ
        for r, _p in K.made:
            if r.name != "taiyaki":
                for o in [r] + K.descendants(r):
                    o.hide_render = True
        roots["taiyaki"].location = (0.0, -0.2, TZ)
        roots["taiyaki"].rotation_euler.z = 0.35
    if A.views.startswith("shop"):   # 雪だるまの店の新しい料理だけを、明るい卓に並べる
        for r, _p in K.made:
            if r.name not in groups["shop"] + groups["shop2"]:
                for o in [r] + K.descendants(r):
                    o.hide_render = True
        K.grid_place([roots[n] for n in groups["shop"]], 7, 0.26, 0.0, x0=-0.25, y0=-0.05, z=TZ)
        K.grid_place([roots[n] for n in groups["shop2"]], 6, 0.27, 0.0, x0=-0.15, y0=-0.45, z=TZ)
    roots["bun_case"].location = (1.25, 0.05, TZ)
    roots["oden"].rotation_euler.z = 0.3
    K.room()
    K.interior_light()
    cams = {
        "all": ((0.6, 1.3, 1.75), (0.55, -0.3, 0.75), 30),
        "buns": ((0.0, 0.45, 0.95), (-0.06, 0.04, 0.77), 40),
        "cans": ((0.55, 0.42, 0.88), (0.55, 0.12, 0.8), 42),
        "ramen": ((0.12, 0.3, 1.05), (0.12, -0.25, 0.77), 34),
        "snacks": ((0.35, -0.05, 1.05), (0.35, -0.75, 0.77), 34),
        "case": ((1.25, 0.9, 1.15), (1.25, 0.05, 1.0), 36),
        "more": ((0.6, -0.45, 1.02), (0.6, -1.0, 0.78), 36),
        "shop": ((0.55, 0.75, 1.45), (0.55, -0.25, 0.78), 34),
        "shop_a": ((0.13, 0.42, 1.0), (0.13, -0.05, 0.77), 34),
        "shop_b": ((0.95, 0.42, 1.0), (0.95, -0.05, 0.77), 34),
        "shop_c": ((0.35, 0.0, 1.0), (0.35, -0.45, 0.77), 34),
        "shop_d": ((1.0, 0.0, 1.0), (1.0, -0.45, 0.77), 34),
        "taiyaki": ((0.0, 0.0, 1.05), (0.0, -0.2, 0.75), 26),
        "taiyaki_side": ((0.25, -0.02, 0.85), (0.0, -0.2, 0.76), 30),
    }
    K.render_views(A, cams)
