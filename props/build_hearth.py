"""暖炉・ストーブ・やかん・薪を Blender で組む。ロッジの「ゆるむ」場所の芯。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_hearth.py -- \
        --views all,fire,stoves,kettles --prefix props/renders/13-hearth

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_hearth.py -- \
        --look flat --export game/props/hearth

炎はフェルトのしずく形を赤・橙・黄の 3 枚重ねにして光らせる（ゲームでは目印 light_fire に揺れる灯りを置く）。
薪は巻いたフェルトのロール（ロッジの丸太と同じ考え）で、木口に渦。暖炉はフェルトの小石か、フェルトのレンガ。
ストーブとやかんは、鉄の代わりに濃い灰のフェルトと、薄い灰のフェルト。
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
C.HEX.update({"felt_ivory": "EEE6D4", "felt_mustard": "C99A3A", "felt_enamel": "E9E2D2", "felt_copper": "B8703E",
              "felt_rust": "A8532E", "felt_tree_tall2": "3E7556"})


# ---------------------------------------------------------------- 薪と炎
def log(P, p0, p1, r, role="felt_tan", end_role="felt_brown"):
    """巻いたフェルトの薪。両端の木口に渦の糸"""
    p0, p1 = Vector(p0), Vector(p1)
    K.tube(P, role, [p0, p1], r, sides=K.cuts(16, 10))
    ax = (p1 - p0).normalized()
    up = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    s = ax.cross(up).normalized()
    u = s.cross(ax).normalized()
    for end, sg in ((p0, -1), (p1, 1)):
        sp = []
        for k in range(36):
            t = k / 35 * 3
            rr = r * (0.1 + 0.8 * t / 3)
            a = t * 2 * math.pi
            sp.append(end + ax * sg * 0.002 + s * rr * math.cos(a) + u * rr * math.sin(a))
        K.tube(P, end_role, sp, r * 0.045, sides=4)


def flame(P, center, h, w, seed=0):
    """炎: しずく形を 3 枚、向きを変えて十字に重ねる（赤 → 橙 → 黄）"""
    rnd = random.Random(seed)
    c = Vector(center)
    for k, (role, sc) in enumerate((("felt_flame_r", 1.0), ("felt_flame_o", 0.75), ("felt_flame_y", 0.5))):
        pts = []
        for i in range(24):
            t = 2 * math.pi * i / 24
            x = w * sc * 0.5 * math.sin(t) * (1 - 0.15 * math.cos(t))
            z = h * sc * (0.5 - 0.5 * math.cos(t)) ** 1.2
            x += 0.03 * h * math.sin(z / h * 6 + seed) * (z / h)
            pts.append((x, z))
        pts.reverse()
        for ang in (0.0, math.pi / 2):
            K.extrude(P, role, pts, -0.006 + 0.004 * k, 0.006 - 0.004 * k + 0.012, plane="XZ", offset=c + Vector((0, 0.0, 0)),
                      rot=(ang + rnd.uniform(-0.2, 0.2), "Z"))


def log_pile_fire(P, center, scale=1.0, seed=0):
    c = Vector(center)
    s = scale
    log(P, c + Vector((-0.25, -0.06, 0.06)) * s, c + Vector((0.25, 0.06, 0.06)) * s, 0.06 * s)
    log(P, c + Vector((-0.22, 0.1, 0.06)) * s, c + Vector((0.22, -0.02, 0.07)) * s, 0.055 * s, "felt_brown", "felt_tan")
    log(P, c + Vector((-0.05, -0.15, 0.13)) * s, c + Vector((0.08, 0.15, 0.14)) * s, 0.05 * s)
    flame(P, c + Vector((0.0, 0.0, 0.08)) * s, 0.42 * s, 0.26 * s, seed)
    flame(P, c + Vector((-0.12, 0.02, 0.06)) * s, 0.26 * s, 0.16 * s, seed + 1)
    flame(P, c + Vector((0.13, -0.02, 0.06)) * s, 0.3 * s, 0.17 * s, seed + 2)


# ---------------------------------------------------------------- 暖炉
def fireplace(name, kind="stone"):
    """暖炉: 炉の口（アーチ）、奥は暗いフェルト、炉床の石、木の飾り棚。前は +Y"""
    P = K.Parts(name, kind="hearth")
    W, H, D = 1.8, 2.4, 0.6
    OW, OH = 0.9, 0.75
    # 炉のまわりの壁: 口の左右と上
    if kind == "stone":
        K.box(P, "stone", (-(W + OW) / 4, 0, H / 2), ((W - OW) / 2, D, H))
        K.box(P, "stone", ((W + OW) / 4, 0, H / 2), ((W - OW) / 2, D, H))
        K.box(P, "stone", (0, 0, (OH + 0.08 + H) / 2 + 0.06), (OW, D, H - OH - 0.08 - 0.12))
    else:   # フェルトのレンガを互い違いに積む
        rnd = random.Random(4)
        bw, bh = 0.3, 0.12
        row = 0
        z = 0.06
        while z < H:
            x = -W / 2 + (bw / 2 if row % 2 else 0)
            while x < W / 2:
                x0, x1 = max(x, -W / 2), min(x + bw, W / 2)
                inside = (z < OH + 0.15) and (x1 > -OW / 2 and x0 < OW / 2)
                if not inside and x1 - x0 > 0.03:
                    role = "felt_brick" if rnd.random() < 0.8 else "felt_rust"
                    K.pbox(P, role, ((x0 + x1) / 2, D / 2 - 0.03, z), ((x1 - x0) / 2 - 0.006, 0.04, bh / 2 - 0.006),
                           n=6.0, c=3)
                x += bw
            z += bh
            row += 1
        for (cx, sx_) in ((-(W + OW) / 4, (W - OW) / 2), ((W + OW) / 4, (W - OW) / 2)):   # レンガの裏（口はあける）
            K.box(P, "felt_charcoal", (cx, -0.02, H / 2), (sx_, D - 0.06, H))
        K.box(P, "felt_charcoal", (0, -0.02, (OH + 0.08 + H) / 2 + 0.06), (OW, D - 0.06, H - OH - 0.08 - 0.12))
    # 口のアーチの木の枠
    arch = []
    for i in range(13):
        a = math.pi * i / 12
        arch.append((OW / 2 * math.cos(a), D / 2 + 0.01, OH - 0.12 + 0.18 * math.sin(a)))
    K.tube(P, "wood_dark", [(OW / 2, D / 2 + 0.01, 0.1)] + arch + [(-OW / 2, D / 2 + 0.01, 0.1)], 0.035, sides=8)
    # 炉の中: 奥と横と天井は暗く、底に薪と炎
    K.box(P, "felt_charcoal", (0, -0.1, OH / 2 + 0.06), (OW - 0.04, 0.04, OH))
    K.box(P, "felt_charcoal", (0, 0.05, OH + 0.05), (OW, D - 0.1, 0.04))
    for sx in (-1, 1):
        K.box(P, "felt_charcoal", (sx * (OW / 2 - 0.02), 0.05, OH / 2 + 0.06), (0.04, D - 0.1, OH))
    K.box(P, "stone" if kind == "stone" else "felt_brick", (0, 0.35, 0.04), (W + 0.2, D + 0.5, 0.08))   # 炉床
    log_pile_fire(P, (0, 0.08, 0.08), 1.0, seed=len(name))
    # 飾り棚: 木の梁、上に紙の灯りの小さなろうそくと、フェルトの小さな木
    K.box(P, "wood", (0, 0.08, H * 0.58), (W + 0.16, D + 0.16, 0.1))
    for x in (-0.6, -0.48):
        K.lathe(P, "felt_ivory", [(0.0, 0.0), (0.03, 0.0), (0.03, 0.12), (0.0, 0.12)], center=(x, 0.25, H * 0.58 + 0.05), segs=16)
        K.pbox(P, "paper", (x, 0.25, H * 0.58 + 0.2), (0.014, 0.014, 0.03), n=2.0, c=4)
    for k, x in enumerate((0.45, 0.6)):
        h = 0.22 - 0.06 * k
        K.lathe(P, "felt_tree_tall2", [(0.0, 0.0), (0.07 - 0.015 * k, 0.0), (0.0, h)], center=(x, 0.22, H * 0.58 + 0.05), segs=16)
    P.mark("light_fire", (0, 0.15, 0.35))
    P.mark("warm", (0, 1.4, 0))   # あたる人が立つ・座る所
    P.finish(fuzz=0.003)


# ---------------------------------------------------------------- ストーブ
def wood_stove(name):
    """薪ストーブ: 濃い灰のフェルトの箱に丸い窓。上に煙突、横に薪の取っ手"""
    P = K.Parts(name, kind="stove")
    P.hard["felt_charcoal"] = 0.01
    P.hard["felt_tin"] = 0.006
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.lathe(P, "felt_charcoal", [(0.03, 0.0), (0.035, 0.03), (0.022, 0.1), (0.03, 0.18)], center=(sx * 0.22, sy * 0.18, 0), segs=12)
    K.box(P, "felt_charcoal", (0, 0, 0.5), (0.6, 0.52, 0.64))                       # 火室
    K.box(P, "felt_charcoal", (0, 0, 0.84), (0.68, 0.6, 0.04))                      # 天板
    K.box(P, "felt_charcoal", (0, 0, 0.19), (0.64, 0.56, 0.03))                     # 底の縁
    for sx in (-1, 1):   # 横の放熱の畝
        for k in range(5):
            K.box(P, "felt_charcoal", (sx * 0.305, -0.15 + 0.075 * k, 0.5), (0.02, 0.025, 0.5))
    # 戸: 前の枠と蝶番
    K.box(P, "felt_charcoal", (0, 0.27, 0.5), (0.42, 0.03, 0.42))
    for z in (0.37, 0.63):
        K.box(P, "felt_tin", (-0.215, 0.285, z), (0.03, 0.02, 0.05))
    # 窓: 透明なフィルムに白い糸の枠、中に炎
    K.ring(P, "felt_charcoal", (0, 0.262, 0.5), 0.13, 0.025, axis="Y", n=40)
    K.disc(P, "glass", (0, 0.255, 0.5), 0.12, 0.004, axis="Y", segs=32)
    K.stitch_ring(P, "thread", (0, 0.262, 0.5), 0.11, r=0.003, axis="Y")
    flame(P, (0, 0.1, 0.38), 0.24, 0.15, 3)
    K.disc(P, "wood", (0.2, 0.275, 0.5), 0.025, 0.04, axis="Y", segs=12)   # 取っ手
    # 煙突: 縫い目の輪が並ぶ筒
    K.tube(P, "felt_charcoal", [(0, -0.08, 0.86), (0, -0.08, 2.4)], 0.075, sides=K.cuts(20, 12))
    for z in (1.1, 1.5, 1.9, 2.3):
        K.ring(P, "thread", (0, -0.08, z), 0.077, 0.004, n=28)
    P.mark("light_fire", (0, 0.1, 0.5))
    P.mark("top", (0, 0.05, 0.87))
    P.finish(fuzz=0.003)


def round_stove(name, body="felt_charcoal"):
    """丸い石油ストーブ（だるまの形）: 胴の真ん中に光る帯、まわりに糸の囲い"""
    P = K.Parts(name, kind="stove")
    K.lathe(P, body, [(0.0, 0.0), (0.2, 0.0), (0.22, 0.04), (0.22, 0.2), (0.17, 0.22), (0.17, 0.36), (0.2, 0.38),
                      (0.2, 0.5), (0.13, 0.56), (0.0, 0.57)], segs=K.cuts(36, 20))
    K.lathe(P, "felt_heat", [(0.172, 0.22), (0.172, 0.36)], segs=K.cuts(36, 20), closed=False)
    for z in (0.24, 0.29, 0.34):
        K.ring(P, "felt_flame_y", (0, 0, z), 0.174, 0.004, n=36)
    # 囲い: 糸の輪と縦の糸
    for z in (0.08, 0.3, 0.5):
        K.ring(P, "thread_dark", (0, 0, z), 0.27, 0.005, n=40)
    for k in range(12):
        a = 2 * math.pi * k / 12
        K.dowel(P, "thread_dark", (0.27 * math.cos(a), 0.27 * math.sin(a), 0.08), (0.27 * math.cos(a), 0.27 * math.sin(a), 0.5),
                0.005, 5)
    K.disc(P, "wood", (0.0, 0.0, 0.58), 0.05, 0.02, segs=16)
    P.mark("light_fire", (0, 0, 0.3))
    P.mark("top", (0, 0, 0.57))
    P.finish(fuzz=0.003)


# ---------------------------------------------------------------- やかん
def kettle(name, body, handle="wood"):
    """やかん: ふくらんだ胴、注ぎ口、木の取っ手の弧、ふたのつまみ。湯気"""
    P = K.Parts(name, kind="kettle")
    K.lathe(P, body, [(0.0, 0.0), (0.1, 0.0), (0.115, 0.03), (0.11, 0.09), (0.08, 0.13), (0.06, 0.14), (0.06, 0.15),
                      (0.0, 0.16)], segs=K.cuts(36, 18))
    K.ring(P, "thread", (0, 0, 0.142), 0.062, 0.003, n=32)
    K.disc(P, handle, (0, 0, 0.17), 0.02, 0.025, segs=12)
    K.tube(P, body, [(0.09, 0, 0.05), (0.14, 0, 0.1), (0.17, 0, 0.15)], [0.025, 0.016, 0.012], sides=12)
    arc = [(0.07 * math.cos(math.pi * i / 12), 0.0, 0.12 + 0.11 * math.sin(math.pi * i / 12)) for i in range(13)]
    for sx in (-1, 1):   # 取っ手の付け根: 胴の肩の小さな耳
        K.pbox(P, body, (sx * 0.07, 0, 0.122), (0.014, 0.01, 0.016), n=3.0, c=3)
    K.tube(P, handle, arc, 0.012, sides=8)
    K.stitch_ring(P, "thread", (0, 0, 0.06), 0.116, r=0.0025)
    K.steam(P, (0.18, 0, 0.16), 0.16, 0.014, seed=len(name))
    P.finish(fuzz=0.0015)


# ---------------------------------------------------------------- 薪
def log_rack(name):
    """薪置き: 木の枠に、巻いたフェルトの薪を積む"""
    P = K.Parts(name, kind="firewood")
    W, D, H = 0.8, 0.4, 0.9
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.box(P, "wood_dark", (sx * W / 2, sy * D / 2, H / 2), (0.04, 0.04, H))
        K.box(P, "wood_dark", (sx * W / 2, 0, 0.05), (0.04, D, 0.04))
    K.box(P, "wood_dark", (0, 0, 0.05), (W, 0.3, 0.03))
    rnd = random.Random(2)
    z = 0.12
    for row in range(6):
        n = 6 if row % 2 == 0 else 5
        for k in range(n):
            x = -W / 2 + 0.07 + (W - 0.14) * (k + (0.5 if row % 2 else 0)) / 5.5
            r = rnd.uniform(0.05, 0.062)
            role = rnd.choice(["felt_tan", "felt_brown", "felt_tan"])
            log(P, (x, -D / 2 + 0.02, z), (x, D / 2 - 0.02, z), r, role, "felt_brown" if role == "felt_tan" else "felt_tan")
        z += 0.11
    P.finish(fuzz=0.003)


def log_basket(name):
    """薪のかご: 麻ひもを巻き上げたかごに、薪を立てて入れる"""
    P = K.Parts(name, kind="firewood")
    coil = []
    turns, r0 = 12, 0.24
    for i in range(turns * 32 + 1):
        a = 2 * math.pi * i / 32
        coil.append((r0 * math.cos(a), r0 * math.sin(a), 0.025 * i / 32 + 0.016))
    K.tube(P, "hemp", coil, 0.017, sides=6)
    K.disc(P, "hemp", (0, 0, 0.01), r0, 0.02, segs=32)
    for sx in (-1, 1):
        K.tube(P, "hemp", [(sx * r0, -0.06, 0.3), (sx * (r0 + 0.04), 0, 0.36), (sx * r0, 0.06, 0.3)], 0.014, sides=6)
    rnd = random.Random(5)
    for k in range(7):
        a = 2 * math.pi * k / 7
        rr = 0.11 if k else 0.0
        x, y = rr * math.cos(a), rr * math.sin(a)
        h = rnd.uniform(0.38, 0.48)
        log(P, (x, y, 0.03), (x + rnd.uniform(-0.03, 0.03), y + rnd.uniform(-0.03, 0.03), h), 0.05,
            rnd.choice(["felt_tan", "felt_brown"]))
    P.finish(fuzz=0.003)


# ---------------------------------------------------------------- 組む
fireplace("fireplace_stone", "stone")
fireplace("fireplace_brick", "brick")
wood_stove("stove_wood")
round_stove("stove_round")
round_stove("stove_round_red", "felt_red")
kettle("kettle_tin", "felt_tin")
kettle("kettle_red", "felt_red")
kettle("kettle_enamel", "felt_enamel", "wood_dark")
log_rack("log_rack")
log_basket("log_basket")

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    lay = {"fireplace_stone": (-1.2, -1.2, 0), "fireplace_brick": (1.6, -1.2, 0), "stove_wood": (3.8, -0.8, 0),
           "stove_round": (5.0, 0.0, 0), "stove_round_red": (5.8, 0.4, 0), "kettle_tin": (3.8, -0.75, 0.87),
           "kettle_red": (5.0, 0.0, 0.57), "kettle_enamel": (5.8, 0.4, 0.57), "log_rack": (-3.1, -0.9, 0),
           "log_basket": (0.1, -0.4, 0)}
    for n, (x, y, z) in lay.items():
        R[n].location = (x, y, z)
    for r, parts in K.made:   # 炎の中に、描くときだけ橙の灯り
        for o in parts:
            if o.name.startswith("light"):
                L = bpy.data.objects.new("fire", bpy.data.lights.new("fire", "POINT"))
                C.coll("stage").objects.link(L)
                L.location = r.location + Vector(o.location) + Vector((0, 0.15, 0))
                L.data.energy = 30
                L.data.color = (1.0, 0.6, 0.3)
                L.data.shadow_soft_size = 0.2
    K.room(floor_size=16.0, wall_y=-1.55)
    K.interior_light(0.7)
    cams = {
        "all": ((1.3, 6.5, 2.4), (1.3, -0.5, 0.9), 28),
        "fire": ((-0.6, 2.4, 1.0), (-1.2, -1.0, 0.6), 34),
        "stoves": ((4.6, 2.6, 1.3), (4.8, -0.2, 0.55), 32),
        "kettles": ((5.2, 1.4, 1.05), (5.1, 0.1, 0.65), 36),
        "brick": ((2.2, 2.6, 1.3), (1.6, -1.0, 0.9), 32),
    }
    K.render_views(A, cams)
