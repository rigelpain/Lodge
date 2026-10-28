"""ロッジのそのほかの小物を Blender で組む。乾かす物干し、入口まわり、自動販売機、壁や窓の飾り。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_misc.py -- \
        --views all,dry,entry,vending,deco --prefix props/renders/16-misc

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_misc.py -- \
        --look flat --export game/props/misc

紙の人は濡れると困るので、ロッジで上着や手袋を乾かす（design/game-concept.md「休むと乾く」）。物干しは暖炉のそばに置く。
自動販売機は lodge の置き場の目印 slot_vending_* に置く形。缶はフェルトの缶（build_food.py）と同じ色。文字は使わない。
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
K.setup(A, fiber=2.0, scale=2.0)
EX = K.S["export"]
C.HEX.update({"felt_indigo": "2E3F66", "felt_mustard": "C99A3A", "felt_ivory": "EEE6D4", "felt_rust": "A8532E",
              "felt_moss": "6E7F4A", "felt_sky": "8FAFC8", "felt_rose": "B5636A", "felt_wet": "7A2E26",
              "felt_tree_tall": "2F5E47", "felt_tree_tall2": "3E7556"})


# ---------------------------------------------------------------- 乾かす
def coat(P, top, role, wet=False):
    """ハンガーに掛けたフェルトの上着: 肩から裾へ広がる身頃と袖。前を縫い目で閉じる"""
    t = Vector(top)
    K.tube(P, "wood", [t + Vector((-0.2, 0, -0.06)), t + Vector((0, 0, 0.0)), t + Vector((0.2, 0, -0.06))], 0.008, sides=6)
    K.tube(P, "thread_dark", [t, t + Vector((0, 0, 0.06)), t + Vector((0.025, 0, 0.08))], 0.003, sides=4)
    m = P.m(role)
    n0 = len(m.bm.verts)
    rings = []
    for j in range(9):
        v = j / 8
        z = -0.04 - 0.6 * v
        w = 0.2 + 0.06 * v
        d = 0.06 + 0.03 * v
        ring = []
        for i in range(24):
            a = 2 * math.pi * i / 24
            ring.append(m.bm.verts.new(t + Vector((w * math.cos(a), d * math.sin(a), z))))
        rings.append(ring)
    for j in range(8):
        for i in range(24):
            i2 = (i + 1) % 24
            m.bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))
    for sx in (-1, 1):   # 袖
        K.tube(P, role, [t + Vector((sx * 0.18, 0, -0.08)), t + Vector((sx * 0.26, 0.0, -0.3)), t + Vector((sx * 0.28, 0.02, -0.52))],
               [0.06, 0.055, 0.05], sides=12)
    K.stitch_line(P, "thread", [t + Vector((0, 0.07, -0.06)), t + Vector((0, 0.095, -0.64))], r=0.003, dash=0.025)
    for k in range(4):
        K.disc(P, "button", t + Vector((0.025, 0.095, -0.12 - 0.13 * k)), 0.014, 0.008, axis="Y", segs=10)
    if wet:   # 濡れたしるし: 裾に濃いしみと、しずくの綿
        K.pbox(P, "felt_wet", t + Vector((0.05, 0.09, -0.55)), (0.09, 0.006, 0.06), n=2.0, c=4)
        K.pbox(P, "felt_sky", t + Vector((-0.1, 0.06, -0.7)), (0.012, 0.012, 0.02), n=2.0, c=3)


def drying_rack(name):
    """物干し: 木の枠に、上着 2 着と、手袋・帽子・マフラーを糸の洗濯ばさみで留める"""
    P = K.Parts(name, kind="dry")
    W, H = 1.6, 1.7
    for sx in (-1, 1):
        K.tube(P, "wood", [(sx * W / 2, -0.3, 0), (sx * W / 2, 0, H), (sx * W / 2, 0.3, 0)], 0.022, sides=8)
    K.dowel(P, "wood", (-W / 2 - 0.04, 0, H), (W / 2 + 0.04, 0, H), 0.022, 10)
    K.dowel(P, "wood", (-W / 2, 0, 0.9), (W / 2, 0, 0.9), 0.016, 8)
    coat(P, (-0.38, 0, H - 0.02), "felt_red", wet=True)
    coat(P, (0.32, 0, H - 0.02), "felt_indigo")
    # 下の横木: 手袋 2 組、帽子、マフラー
    for k, (x, role) in enumerate(((-0.6, "felt_mustard"), (-0.45, "felt_mustard"), (0.0, "felt_rose"), (0.15, "felt_rose"))):
        K.pbox(P, role, (x, 0, 0.78), (0.045, 0.025, 0.075), n=2.4, nz=3.0, c=5)
        K.pbox(P, role, (x + 0.045 * (1 if k % 2 else -1), 0, 0.8), (0.018, 0.02, 0.035), n=2.0, c=4)   # 親指
        K.box(P, "wood_light", (x, 0, 0.88), (0.02, 0.03, 0.05))
    K.pbox(P, "felt_moss", (0.45, 0, 0.82), (0.11, 0.07, 0.08), n=2.0, nz=2.4, c=6)                     # 帽子
    K.pbox(P, "felt_ivory", (0.45, 0, 0.92), (0.03, 0.03, 0.03), n=2.0, c=4)
    K.box(P, "felt_indigo", (0.62, 0, 0.72), (0.12, 0.012, 0.36))                                         # マフラー
    for k in range(5):
        K.box(P, "felt_ivory", (0.62, 0.007, 0.6 + 0.06 * k), (0.12, 0.004, 0.015))
    P.mark("near_fire", (0, 0.8, 0))
    P.finish(fuzz=0.003)


def glove_dryer(name):
    """手袋干し: 木の台に立てた細い棒に、手袋をかぶせて乾かす（ストーブのそば）"""
    P = K.Parts(name, kind="dry")
    K.box(P, "wood", (0, 0, 0.02), (0.6, 0.2, 0.04))
    roles = ["felt_red", "felt_red", "felt_mustard", "felt_mustard", "felt_sky", "felt_sky"]
    for k, role in enumerate(roles):
        x = -0.25 + 0.1 * k
        K.dowel(P, "wood_light", (x, 0, 0.04), (x, 0, 0.3), 0.008, 6)
        K.pbox(P, role, (x, 0, 0.3), (0.04, 0.022, 0.07), n=2.4, nz=3.0, c=5)
    P.finish(fuzz=0.002)


# ---------------------------------------------------------------- 入口まわり
def hat_rack(name):
    """壁の帽子掛け: 木の板に木の釘、ニット帽とマフラー。前が +Y"""
    P = K.Parts(name, kind="entry")
    K.box(P, "wood", (0, 0.015, 0), (1.2, 0.03, 0.14))
    items = [("felt_red", "hat"), ("felt_indigo", "scarf"), ("felt_mustard", "hat"), (None, None), ("felt_moss", "hat")]
    for k, (role, kind) in enumerate(items):
        x = -0.48 + 0.24 * k
        K.dowel(P, "wood_dark", (x, 0.03, 0), (x, 0.12, 0.02), 0.012, 8)
        if kind == "hat":
            K.pbox(P, role, (x, 0.1, -0.02), (0.09, 0.07, 0.08), n=2.0, nz=2.4, c=6)
            K.ring(P, "felt_ivory", (x, 0.1, -0.08), 0.09, 0.015, n=24)
            K.pbox(P, "felt_ivory", (x, 0.1, 0.07), (0.028, 0.028, 0.028), n=2.0, c=4)
        elif kind == "scarf":
            K.box(P, role, (x - 0.04, 0.11, -0.25), (0.09, 0.012, 0.5))
            K.box(P, role, (x + 0.05, 0.1, -0.2), (0.09, 0.012, 0.4))
    P.finish(fuzz=0.003)


def boot_tray(name):
    """長靴の置き台: 木のすのこに、フェルトの長靴 2 足"""
    P = K.Parts(name, kind="entry")
    for k in range(6):
        K.box(P, "wood", (-0.3 + 0.12 * k, 0, 0.02), (0.1, 0.5, 0.025))
    for k, (x, role) in enumerate(((-0.25, "felt_red"), (-0.12, "felt_red"), (0.12, "felt_indigo"), (0.25, "felt_indigo"))):
        K.pbox(P, role, (x, 0.05, 0.06), (0.05, 0.12, 0.04), n=3.0, c=5)
        K.lathe(P, role, [(0.045, 0.0), (0.05, 0.2), (0.0, 0.2)], center=(x, -0.03, 0.06), segs=16, closed=False)
        K.ring(P, "felt_ivory", (x, -0.03, 0.26), 0.05, 0.012, n=20)
    P.finish(fuzz=0.003)


def ski_rack(name):
    """スキー立て: 木の柵に、色とりどりのフェルトのスキーを立てる（貸出）"""
    P = K.Parts(name, kind="entry")
    W = 1.6
    for z in (0.15, 0.95):
        K.dowel(P, "wood", (-W / 2, 0, z), (W / 2, 0, z), 0.025, 10)
    for x in (-W / 2, W / 2):
        K.dowel(P, "wood", (x, 0, 0), (x, 0, 1.05), 0.03, 10)
    roles = ["felt_red", "felt_mustard", "felt_sky", "felt_moss", "felt_rose", "felt_indigo", "felt_red", "felt_ivory"]
    for k, role in enumerate(roles):
        x = -W / 2 + 0.12 + k * (W - 0.24) / 7
        for dx in (-0.032, 0.032):
            pts = [(x + dx, 0.06, 0.02), (x + dx, 0.06, 1.55), (x + dx, 0.0, 1.68)]
            K.tube(P, role, pts, 0.03, sides=8, side=(1, 0, 0), ry=0.008, sq=4.0)   # 板の面を前へ
        K.stitch_line(P, "thread", [(x - 0.025, 0.07, 0.3), (x - 0.025, 0.07, 1.4)], r=0.002, dash=0.03)
    P.finish(fuzz=0.002)


# ---------------------------------------------------------------- 自動販売機
def vending(name, body="felt_red", trim="felt_ivory"):
    """自動販売機: 角の立った箱を組む。前の窓は一段奥まり、3 段の棚に缶の見本。缶ごとの押しボタン、
    右にお金の口と返却レバー、下に斜めのふたの取り出し口、上に光る看板、足もとに蹴込み。前は +Y"""
    P = K.Parts(name, kind="vending", slot="slot_vending")
    W, D, H = 1.0, 0.75, 1.83
    for role in (body, trim, "wood_dark", "felt_charcoal", "felt_tin"):
        P.hard[role] = 0.012
    fy = D / 2
    K.box(P, "wood_dark", (0, 0, 0.04), (W + 0.02, D + 0.02, 0.08))                       # 台
    K.box(P, body, (0, 0, 0.08 + (H - 0.08) / 2), (W, D, H - 0.08))                       # 胴
    K.box(P, body, (0, -0.01, H + 0.02), (W + 0.05, D + 0.05, 0.04))                     # 笠
    # 看板: 前に張り出した箱に、光る紙
    K.box(P, trim, (0, fy + 0.03, H - 0.13), (W - 0.06, 0.06, 0.18))
    K.box(P, "paper", (0, fy + 0.062, H - 0.13), (W - 0.16, 0.006, 0.11))
    # 窓: 枠（4 本の木）と、奥の明るい板、3 段の棚、缶、前のフィルム
    WX0, WX1, WZ0, WZ1 = -W / 2 + 0.22, W / 2 - 0.06, 0.9, H - 0.26   # 前から見て右にお金の板（x は前から見ると左右逆）
    wx, wz = (WX0 + WX1) / 2, (WZ0 + WZ1) / 2
    ww, wh = WX1 - WX0, WZ1 - WZ0
    for (cx, cz, sx, sz) in ((wx, WZ1 + 0.02, ww + 0.08, 0.04), (wx, WZ0 - 0.02, ww + 0.08, 0.04),
                             (WX0 - 0.02, wz, 0.04, wh), (WX1 + 0.02, wz, 0.04, wh)):
        K.box(P, trim, (cx, fy + 0.05, cz), (sx, 0.1, sz))
    K.box(P, "felt_ivory", (wx, fy + 0.004, wz), (ww, 0.008, wh))
    cans = ["felt_yellow", "felt_brown", "felt_navy2", "felt_tea", "felt_purple", "felt_rust"]
    rows = 3
    for r in range(rows):
        z = WZ0 + 0.02 + r * (wh / rows)
        K.box(P, "wood_dark", (wx, fy + 0.045, z), (ww, 0.08, 0.016))                     # 棚
        n = 5
        for c in range(n):
            x = WX0 + ww / n * (c + 0.5)
            role = cans[(c + r * 2) % len(cans)]
            K.lathe(P, role, [(0.0, 0.0), (0.028, 0.0), (0.03, 0.008), (0.03, 0.105), (0.026, 0.115), (0.0, 0.115)],
                    center=(x, fy + 0.045, z + 0.008), segs=16)
            K.disc(P, "felt_tin", (x, fy + 0.045, z + 0.125), 0.024, 0.006, segs=12)
            # 押しボタン: 棚の前の帯に、丸いボタン（赤は温かい、青は冷たい）
            K.box(P, "felt_charcoal", (x, fy + 0.098, z + 0.0), (0.05, 0.01, 0.03))
            K.disc(P, "felt_red" if r > 0 else "felt_sky", (x, fy + 0.105, z), 0.011, 0.01, axis="Y", segs=12)
    K.box(P, "glass", (wx, fy + 0.096, wz + 0.02), (ww, 0.004, wh - 0.04))
    # お金の板: 右の縦長の板に、硬貨の口・お札の口・返却レバー・おつりの口
    px = -W / 2 + 0.11
    K.box(P, "felt_charcoal", (px, fy + 0.03, 1.15), (0.16, 0.06, 0.5))
    K.box(P, "felt_tin", (px, fy + 0.062, 1.32), (0.07, 0.01, 0.03))
    K.box(P, "felt_charcoal", (px, fy + 0.066, 1.32), (0.04, 0.012, 0.006))               # 硬貨の口
    K.box(P, "felt_tin", (px, fy + 0.062, 1.2), (0.11, 0.01, 0.05))
    K.box(P, "felt_charcoal", (px, fy + 0.066, 1.2), (0.085, 0.012, 0.008))              # お札の口
    K.dowel(P, "felt_tin", (px, fy + 0.06, 1.08), (px - 0.04, fy + 0.1, 1.06), 0.01, 8)  # 返却レバー
    K.box(P, "felt_tin", (px, fy + 0.065, 0.96), (0.08, 0.02, 0.06))                    # おつりの口
    K.box(P, "felt_charcoal", (px, fy + 0.076, 0.955), (0.05, 0.004, 0.03))
    # 取り出し口: 奥まった口に、斜めのふた（上で吊る）
    K.box(P, trim, (0, fy + 0.03, 0.42), (W - 0.12, 0.06, 0.32))
    K.box(P, "felt_charcoal", (0, fy + 0.035, 0.41), (W - 0.26, 0.06, 0.2))
    K.box(P, "felt_tin", (0, fy + 0.075, 0.42), (W - 0.28, 0.012, 0.2), rot=(0.25, "X"))
    K.dowel(P, "felt_tin", (-(W - 0.28) / 2, fy + 0.07, 0.52), ((W - 0.28) / 2, fy + 0.07, 0.52), 0.008, 8)
    # 蹴込みと、前の角の縁取り（毛糸）
    K.box(P, "felt_charcoal", (0, fy + 0.01, 0.15), (W - 0.04, 0.03, 0.12))
    for sx in (-1, 1):
        K.dowel(P, "yarn_cream", (sx * (W / 2 + 0.002), fy + 0.002, 0.1), (sx * (W / 2 + 0.002), fy + 0.002, H), 0.009, 8)
    P.mark("button", (0, fy + 0.11, WZ0 + 0.1))
    P.mark("out", (0, fy + 0.08, 0.42))
    P.mark("light", (0, fy + 0.15, H - 0.13))
    P.finish(fuzz=0.003)


# ---------------------------------------------------------------- 飾り
def wall_clock(name):
    """掛け時計: 木の丸い枠に、フェルトの文字盤。数字の代わりに 12 の点。針は木"""
    P = K.Parts(name, kind="deco")
    K.disc(P, "wood", (0, 0.02, 0), 0.2, 0.04, axis="Y", segs=40)
    K.disc(P, "felt_ivory", (0, 0.042, 0), 0.17, 0.006, axis="Y", segs=40)
    for k in range(12):
        a = 2 * math.pi * k / 12
        r = 0.012 if k % 3 == 0 else 0.007
        K.disc(P, "felt_indigo", (0.14 * math.sin(a), 0.047, 0.14 * math.cos(a)), r, 0.004, axis="Y", segs=10)
    K.box(P, "wood_dark", (0.03, 0.05, 0.04), (0.012, 0.006, 0.1), rot=(-0.6, "Y"))
    K.box(P, "wood_dark", (-0.045, 0.052, 0.01), (0.012, 0.006, 0.12), rot=(1.3, "Y"))
    K.disc(P, "felt_red", (0, 0.056, 0), 0.012, 0.006, axis="Y", segs=10)
    P.finish(fuzz=0.0015)


def tapestry(name, palette, seed=0):
    """壁掛け: パッチワークの布を木の棒に下げる。裾に房。雪山と木のアップリケ"""
    P = K.Parts(name, kind="deco")
    rnd = random.Random(seed)
    W, H = 1.0, 1.3
    K.dowel(P, "wood", (-W / 2 - 0.08, 0.02, 0), (W / 2 + 0.08, 0.02, 0), 0.018, 10)
    K.tube(P, "hemp", [(-W / 2, 0.02, 0), (0, 0.02, 0.25), (W / 2, 0.02, 0)], 0.006, sides=5)
    hanging_cloth(P, "cloth", palette[0], -W / 2, W / 2, -0.02, H, pleats=2, depth=0.004, nu=K.cuts(28, 18), nv=K.cuts(36, 24), y0=0.008)
    # 雪山: 三角の山と白い頂、下に 3 本の木
    for (cx, h, role) in ((-0.15, 0.55, palette[1]), (0.2, 0.42, palette[2])):
        K.extrude(P, role, [(-cx - 0.32, 0.0), (-cx + 0.32, 0.0), (-cx, h)], 0.016, 0.022, plane="XZ", offset=(0, 0, -H + 0.2))
        K.extrude(P, "felt_ivory", [(-cx - 0.09, h - 0.15), (-cx + 0.09, h - 0.15), (-cx, h)], 0.023, 0.028, plane="XZ",
                  offset=(0, 0, -H + 0.2))
    for k in range(3):
        x = -0.25 + 0.25 * k
        K.extrude(P, "felt_tree_tall", [(x - 0.06, 0), (x + 0.06, 0), (x, 0.2)], 0.024, 0.03, plane="XZ", offset=(0, 0, -H + 0.08))
    K.disc(P, "felt_mustard", (-0.3, 0.025, -0.25), 0.07, 0.006, axis="Y", segs=20)   # 太陽
    K.stitch_line(P, "thread", [(-W / 2 + 0.04, 0.02, -0.06), (W / 2 - 0.04, 0.02, -0.06), (W / 2 - 0.04, 0.02, -H + 0.02),
                                (-W / 2 + 0.04, 0.02, -H + 0.02), (-W / 2 + 0.04, 0.02, -0.06)], r=0.003, dash=0.03)
    for k in range(20):
        x = -W / 2 + 0.03 + (W - 0.06) * k / 19
        K.tube(P, palette[1], [(x, 0.01, -H - 0.02), (x, 0.01, -H - 0.1)], 0.004, sides=4)
    P.finish(fuzz=0.002)


def hanging_cloth(P, name, role, x0, x1, top, H, pleats=8, depth=0.05, nu=40, nv=46, gather=1.0, y0=0.06):
    """上の端を留めて垂らす布（カーテン・壁掛け）: ひだを付けた布を、上の 1 列だけ留めて重力で落とす"""
    m = C.M("%s_%s" % (P.name, name), role)
    vs = []
    for j in range(nv + 1):
        v = j / nv
        row = []
        for i in range(nu + 1):
            u = i / nu
            x = x0 + (x1 - x0) * u * gather
            y = y0 + depth * math.sin(u * pleats * 2 * math.pi)
            row.append(m.bm.verts.new((x, y, top - v * H)))
        vs.append(row)
    for j in range(nv):
        for i in range(nu):
            m.bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    o = m.done(smooth=True)
    K.cloth_sim(o, [], frames=40, mass=0.3, stiff=14.0, bend=0.8, pin=lambda p: p.z > top - 0.01, thickness=0.006,
                solidify=0.012, subsurf=1)
    o.parent = P.root
    P.parts.append(o)
    return o


def curtain(name, role, W=1.4, H=1.8):
    """窓のカーテン: 左右 2 枚を上の棒から垂らす（ひだを付けて重力で落とす）。下の方を麻ひもで束ねる"""
    P = K.Parts(name, kind="deco")
    K.dowel(P, "wood", (-W / 2 - 0.1, 0.06, 0), (W / 2 + 0.1, 0.06, 0), 0.02, 10)
    for sx in (-1, 1):
        hanging_cloth(P, "panel%d" % (sx + 1), role, sx * (W / 2 + 0.05), sx * (W / 2 - 0.4), -0.03, H, pleats=6, depth=0.045,
                      nu=K.cuts(36, 24), nv=K.cuts(44, 30))
        K.ring(P, "hemp", (sx * (W / 2 - 0.18), 0.06, -H * 0.62), 0.12, 0.009, axis="Z", n=24)
        for k in range(6):
            K.ring(P, "thread", (sx * (W / 2 + 0.03 - 0.075 * k), 0.06, -0.01), 0.014, 0.003, axis="Y", n=10)
    P.finish(fuzz=0.002)


def plant(name, kind="round"):
    """鉢植え: 麻ひもを巻いた鉢に、フェルトの葉。round は丸い葉の株、tall は細い葉"""
    P = K.Parts(name, kind="deco")
    coil = []
    for i in range(8 * 24 + 1):
        a = 2 * math.pi * i / 24
        r = 0.12 + 0.03 * i / (8 * 24)
        coil.append((r * math.cos(a), r * math.sin(a), 0.014 + 0.026 * i / 24))
    K.tube(P, "hemp", coil, 0.014, sides=6)
    K.disc(P, "felt_brown", (0, 0, 0.2), 0.14, 0.01, segs=24)
    rnd = random.Random(len(name))
    if kind == "round":
        for k in range(9):
            a = 2 * math.pi * k / 9 + rnd.uniform(-0.2, 0.2)
            L = rnd.uniform(0.2, 0.35)
            base = Vector((0, 0, 0.2))
            tip = base + Vector((math.cos(a) * L * 0.6, math.sin(a) * L * 0.6, L))
            K.tube(P, "felt_moss", [base, tip], 0.006, sides=5)
            K.pbox(P, "felt_tree_tall2", tip, (0.06, 0.012, 0.05), n=2.0, c=5, rot=(a + math.pi / 2, "Z"))
    else:
        for k in range(14):
            a = 2 * math.pi * k / 14
            L = rnd.uniform(0.45, 0.7)
            pts = [(0, 0, 0.2), (math.cos(a) * 0.06, math.sin(a) * 0.06, 0.2 + L * 0.6),
                   (math.cos(a) * 0.18, math.sin(a) * 0.18, 0.2 + L)]
            K.tube(P, "felt_tree_tall2", pts, [0.02, 0.016, 0.003], sides=6, ry=[0.004, 0.004, 0.002])
    P.finish(fuzz=0.002)


def picture(name, scene="mountain"):
    """額: 木の枠に、紙に貼ったフェルトの絵（雪山とソリ / ロッジの灯り）"""
    P = K.Parts(name, kind="deco")
    W, H = 0.5, 0.38
    K.box(P, "wood_dark", (0, 0.01, 0), (W + 0.06, 0.02, H + 0.06))
    K.box(P, "paper_white", (0, 0.022, 0), (W, 0.004, H))
    if scene == "mountain":
        K.extrude(P, "felt_sky", [(-W / 2, -H / 2), (W / 2, -H / 2), (W / 2, H / 2), (-W / 2, H / 2)], 0.024, 0.026,
                  plane="XZ")
        K.extrude(P, "felt_ivory", [(-W / 2, -H / 2), (W / 2, -H / 2), (W / 2, -0.02), (0.05, 0.12), (-0.12, -0.01),
                                    (-W / 2, 0.05)], 0.026, 0.029, plane="XZ")
        K.extrude(P, "felt_red", [(-0.03, -0.1), (0.07, -0.1), (0.07, -0.07), (-0.03, -0.07)], 0.029, 0.032, plane="XZ")
    else:
        K.extrude(P, "felt_indigo", [(-W / 2, -H / 2), (W / 2, -H / 2), (W / 2, H / 2), (-W / 2, H / 2)], 0.024, 0.026,
                  plane="XZ")
        K.extrude(P, "felt_tan", [(-0.15, -0.15), (0.15, -0.15), (0.15, 0.0), (-0.15, 0.06)], 0.026, 0.029, plane="XZ")
        for k in range(3):
            K.extrude(P, "felt_mustard", K.round_rect(0.05, 0.04, 0.005), 0.029, 0.031, plane="XZ",
                      offset=(-0.09 + 0.09 * k, 0, -0.08))
    P.finish(fuzz=0.0015)


# ---------------------------------------------------------------- 組む
drying_rack("drying_rack")
glove_dryer("glove_dryer")
hat_rack("hat_rack")
boot_tray("boot_tray")
ski_rack("ski_rack")
vending("vending_red", "felt_red")
vending("vending_blue", "felt_sky", "felt_ivory")
wall_clock("wall_clock")
tapestry("tapestry_mountain", ["felt_indigo", "felt_sky", "felt_ivory"], 1)
tapestry("tapestry_warm", ["felt_rust", "felt_mustard", "felt_rose"], 2)
curtain("curtain_red", "felt_red")
curtain("curtain_indigo", "felt_indigo")
plant("plant_round", "round")
plant("plant_tall", "tall")
picture("picture_mountain", "mountain")
picture("picture_lodge", "lodge")

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    lay = {"drying_rack": (-4.0, 0.0, 0), "glove_dryer": (-2.6, 0.9, 0), "hat_rack": (-1.6, -1.45, 1.7),
           "boot_tray": (-1.6, -0.9, 0), "ski_rack": (0.6, -1.1, 0), "vending_red": (2.6, -0.9, 0), "vending_blue": (3.8, -0.9, 0),
           "wall_clock": (-0.3, -1.48, 2.2), "tapestry_mountain": (5.4, -1.48, 2.4), "tapestry_warm": (6.7, -1.48, 2.4),
           "curtain_red": (-3.6, -1.42, 2.6), "curtain_indigo": (8.2, -1.42, 2.6), "plant_round": (4.9, 0.0, 0),
           "plant_tall": (7.4, 0.0, 0), "picture_mountain": (-1.0, -1.48, 1.3), "picture_lodge": (0.0, -1.48, 1.55)}
    for n, (x, y, z) in lay.items():
        R[n].location = (x, y, z)
    K.room(floor_size=24.0, wall_y=-1.55)
    K.interior_light(1.2)
    cams = {
        "all": ((1.8, 9.5, 2.6), (1.8, -0.5, 1.1), 30),
        "dry": ((-2.6, 3.0, 1.5), (-3.6, 0.0, 1.0), 32),
        "entry": ((-0.4, 3.2, 1.4), (-0.6, -1.0, 1.0), 32),
        "vending": ((3.2, 3.6, 1.4), (3.2, -0.9, 1.0), 32),
        "deco": ((6.2, 3.4, 1.7), (6.3, -1.2, 1.5), 32),
    }
    K.render_views(A, cams)
