"""食べ物を買うカウンターまわりを Blender で組む。メニュー板・レジ・お盆・給水機・ティッシュ・卓の小物。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_counter.py -- \
        --views all,menus,register,table --prefix props/renders/14-counter

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_counter.py -- \
        --look flat --export game/props/counter

メニューは文字を使わない（design/art-concept.md「画面の文字と表示」）。料理の絵をフェルトのアップリケで並べ、
値段は金のフェルトの丸の数で示す（1 つ = 安い、5 つ = 高い）。前は +Y。
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
K.setup(A, fiber=3.0, scale=2.0, tris=2500)
EX = K.S["export"]
C.HEX.update({"felt_ivory": "EEE6D4", "felt_mustard": "C99A3A", "felt_indigo": "2E3F66", "felt_rust": "A8532E",
              "felt_sky": "8FAFC8", "felt_water": "BFD8E6"})


# ---------------------------------------------------------------- メニューの絵（中心 0、大きさ約 0.12）
def ic_ramen():
    bowl = [(0.06 * math.cos(a), -0.06 * math.sin(a) * 0.8) for a in [math.pi * k / 16 for k in range(17)]]
    noodle = [(-0.05, 0.0), (0.05, 0.0), (0.05, 0.012), (-0.05, 0.012)]
    stick = [(-0.01, 0.01), (0.06, 0.06), (0.055, 0.066), (-0.015, 0.016)]
    return [("felt_red", bowl), ("felt_yellow", noodle), ("wood_light", stick)]


def ic_curry():
    plate = K.circle_poly(0.065, 24, sy=0.45)
    rice = [(x, y) for x, y in K.circle_poly(0.035, 16, -0.018, 0.004, sy=0.6)]
    roux = [(x, y) for x, y in K.circle_poly(0.03, 16, 0.025, -0.002, sy=0.55)]
    return [("felt_ivory", plate), ("felt_rice", rice), ("felt_curry", roux)]


def ic_onigiri():
    tri = [(-0.05, -0.04), (0.05, -0.04), (0.0, 0.05)]
    nori = [(-0.025, -0.04), (0.025, -0.04), (0.025, -0.005), (-0.025, -0.005)]
    return [("felt_rice", tri), ("felt_nori", nori)]


def ic_oden():
    stick = [(-0.003, -0.06), (0.003, -0.06), (0.003, 0.065), (-0.003, 0.065)]
    tri = [(-0.025, -0.045), (0.025, -0.045), (0.0, -0.01)]
    return [("wood_light", stick), ("felt_konnyaku", tri), ("felt_daikon", K.circle_poly(0.022, 16, 0, 0.015)),
            ("felt_tan", K.circle_poly(0.016, 14, 0, 0.05))]


def ic_can(role):
    body = K.round_rect(0.05, 0.1, 0.008)
    band = [(-0.025, 0.012), (0.025, 0.012), (0.025, 0.028), (-0.025, 0.028)]
    return [(role, body), ("felt_ivory", band)]


def ic_cup(role):
    cup = [(-0.032, -0.04), (0.032, -0.04), (0.04, 0.03), (-0.04, 0.03)]
    handle = [(0.036, 0.0), (0.06, 0.004), (0.06, 0.024), (0.038, 0.026), (0.038, 0.018), (0.05, 0.016), (0.05, 0.008),
              (0.036, 0.008)]
    steam = [(-0.008, 0.04), (0.0, 0.04), (0.008, 0.065), (0.0, 0.065)]
    return [(role, cup), (role, handle), ("felt_ivory", steam)]


def ic_taiyaki():
    body = [(0.055 * math.cos(t), 0.03 * math.sin(t) * (0.6 + 0.4 * math.cos(t))) for t in [2 * math.pi * k / 24 for k in range(24)]]
    tail = [(-0.05, 0.0), (-0.075, 0.024), (-0.068, 0.0), (-0.075, -0.024)]
    return [("felt_tan", body), ("felt_tan", tail), ("felt_brown", K.circle_poly(0.005, 8, 0.035, 0.008))]


def ic_dango():
    stick = [(-0.06, -0.003), (0.065, -0.003), (0.065, 0.003), (-0.06, 0.003)]
    return [("wood_light", stick), ("felt_green", K.circle_poly(0.018, 14, -0.035, 0)),
            ("felt_rice", K.circle_poly(0.018, 14, 0.0, 0)), ("felt_pink", K.circle_poly(0.018, 14, 0.035, 0))]


def ic_bun():
    dome = [(0.05 * math.cos(a), 0.045 * math.sin(a) - 0.02) for a in [math.pi * k / 16 for k in range(17)]]
    return [("felt_bun", dome), ("paper_white", [(-0.06, -0.03), (0.06, -0.03), (0.06, -0.02), (-0.06, -0.02)])]


def ic_mikan():
    return [("felt_orange", K.circle_poly(0.045, 20)), ("felt_green", K.circle_poly(0.014, 10, 0.015, 0.045, sy=0.5))]


def menu_board(name, rows, frame="wood_dark", cloth="felt_indigo"):
    """メニュー板: 木の枠に藍のフェルトを張り、行ごとに絵と値段の丸。上から麻ひもで吊る"""
    P = K.Parts(name, kind="menu")
    W, RH = 0.9, 0.22
    H = RH * len(rows) + 0.1
    K.box(P, frame, (0, 0, 0), (W + 0.06, 0.04, H + 0.06))
    K.box(P, cloth, (0, 0.021, 0), (W - 0.02, 0.004, H - 0.02))
    K.stitch_line(P, "thread", [(-W / 2 + 0.03, 0.025, H / 2 - 0.03), (W / 2 - 0.03, 0.025, H / 2 - 0.03),
                                (W / 2 - 0.03, 0.025, -H / 2 + 0.03), (-W / 2 + 0.03, 0.025, -H / 2 + 0.03),
                                (-W / 2 + 0.03, 0.025, H / 2 - 0.03)], r=0.003, dash=0.025)
    for i, (icon, price) in enumerate(rows):
        z = H / 2 - 0.05 - RH * (i + 0.5)
        # 前（+Y）から見ると x が左右逆になるので、絵は x を反転して、見る人の左（+x）に置く
        for role, poly in icon:
            K.extrude(P, role, [(-x * 1.7 + 0.24, y * 1.7) for x, y in reversed(poly)], 0.024, 0.03, plane="XZ",
                      offset=(0, 0, z))
        for k in range(price):   # 値段: 金の丸。見る人の右へ並ぶ
            K.disc(P, "felt_gold", (-0.04 - 0.075 * k, 0.027, z), 0.028, 0.006, axis="Y", segs=16)
        if i < len(rows) - 1:
            K.stitch_line(P, "thread", [(-W / 2 + 0.06, 0.025, z - RH / 2), (W / 2 - 0.06, 0.025, z - RH / 2)], r=0.002,
                          dash=0.015)
    for sx in (-1, 1):   # 吊るす麻ひも
        K.tube(P, "hemp", [(sx * (W / 2 - 0.08), 0, H / 2 + 0.03), (0, 0, H / 2 + 0.3)], 0.008, sides=6)
    P.mark("hang", (0, 0, H / 2 + 0.3))
    P.finish(fuzz=0.002)


# ---------------------------------------------------------------- レジと呼び鈴
def register(name, body="felt_red"):
    """レジ: 引き出しの台の上に、横から見て台形の胴（後ろが高く、前は打ち鍵の斜面）。斜面に打ち鍵が段に並び、
    後ろの塔に札を出す窓、右に回す取っ手、前に引き出しのつまみ"""
    P = K.Parts(name, kind="register")
    for r in ("wood", "wood_dark", body, "felt_ivory", "felt_mustard", "felt_charcoal", "paper_white"):
        P.hard[r] = 0.004
    W = 0.42
    K.box(P, "wood", (0, 0, 0.06), (W + 0.04, 0.42, 0.12))                                # 引き出しの台
    K.box(P, "wood_dark", (0, 0.212, 0.06), (W - 0.04, 0.008, 0.08))
    K.disc(P, "button", (0, 0.222, 0.06), 0.016, 0.014, axis="Y", segs=12)
    # 胴: 台形の横顔を左右に押し出す（前が +Y）
    prof = [(-0.19, 0.0), (0.19, 0.0), (0.19, 0.06), (-0.05, 0.2), (-0.19, 0.2)]
    K.extrude(P, body, [(y, z) for y, z in prof], -W / 2, W / 2, plane="XZ", offset=(0, 0, 0.12), rot=(math.pi / 2, "Z"))
    # 打ち鍵: 斜面に 4 段 × 6 列の四角いキー
    import math as _m
    ang = _m.atan2(0.14, 0.24)
    for r in range(4):
        t = (r + 0.5) / 4
        y = 0.19 - 0.24 * t
        z = 0.12 + 0.06 + 0.14 * t + 0.012
        for c in range(6):
            x = -W / 2 + 0.05 + (W - 0.1) * c / 5
            role = "felt_mustard" if c == 5 else ("felt_charcoal" if r == 0 else "felt_ivory")
            K.box(P, role, (x, y, z), (0.042, 0.042, 0.022), rot=(ang, "X"))
    # 塔: 札を出す窓（紙の札と数字の代わりの丸）
    K.box(P, body, (0, -0.13, 0.12 + 0.2 + 0.07), (0.24, 0.1, 0.14))
    K.box(P, "paper_white", (0, -0.078, 0.12 + 0.2 + 0.07), (0.18, 0.006, 0.07))
    for k in range(3):
        K.disc(P, "felt_charcoal", (-0.05 + 0.05 * k, -0.074, 0.39), 0.012, 0.004, axis="Y", segs=10)
    # 取っ手
    K.disc(P, "wood", (W / 2 + 0.02, -0.02, 0.24), 0.06, 0.025, axis="X", segs=24)
    K.dowel(P, "wood", (W / 2 + 0.035, -0.02 + 0.04, 0.24 + 0.03), (W / 2 + 0.06, 0.04, 0.2), 0.01, 6)
    K.disc(P, "button", (W / 2 + 0.07, 0.045, 0.2), 0.016, 0.03, axis="X", segs=10)
    P.finish(fuzz=0.0015)


def bell(name):
    """呼び鈴: フェルトの丸い鈴に木のつまみ"""
    P = K.Parts(name, kind="register")
    K.disc(P, "wood", (0, 0, 0.008), 0.05, 0.016, segs=24)
    K.lathe(P, "felt_tin", [(0.0, 0.016), (0.042, 0.016), (0.04, 0.035), (0.03, 0.052), (0.0, 0.058)], segs=24)
    K.dowel(P, "wood_dark", (0, 0, 0.058), (0, 0, 0.07), 0.004, 6)
    K.disc(P, "button", (0, 0, 0.074), 0.009, 0.008, segs=10)
    P.finish(fuzz=0.001)


# ---------------------------------------------------------------- お盆
def tray(name, shape="rect", role="wood"):
    """お盆: 縁の立った木の盆。round は赤いフェルトを張った丸盆"""
    P = K.Parts(name, kind="tray")
    if shape == "rect":
        K.extrude(P, role, K.round_rect(0.44, 0.32, 0.03), 0.0, 0.012)
        rim = K.round_rect(0.44, 0.32, 0.03)
        K.tube(P, role, [(x, y, 0.022) for x, y in rim] + [(rim[0][0], rim[0][1], 0.022)], 0.012, sides=6, ry=0.016)
    else:
        K.disc(P, role, (0, 0, 0.006), 0.19, 0.012, segs=40)
        K.ring(P, role, (0, 0, 0.02), 0.19, 0.012, n=48)
        K.stitch_ring(P, "felt_gold", (0, 0, 0.0125), 0.15, r=0.0025)
    P.mark("top", (0, 0, 0.013))
    P.finish(fuzz=0.0015)


# ---------------------------------------------------------------- 給水機と紙コップ
def paper_cup(P, center, h=0.09, r0=0.028, r1=0.038, role="paper_white"):
    K.lathe(P, role, [(0.0, 0.0), (r0, 0.0), (r1, h), (r1 - 0.003, h), (r0 - 0.003, 0.004), (0.0, 0.004)], center=center,
            segs=K.cuts(20, 12))
    K.ring(P, role, Vector(center) + Vector((0, 0, h)), r1, 0.002, n=24)


def water_server(name):
    """給水機: 木の台に、透明なフィルムの大きな瓶（水色）を逆さに。前に注ぎ口、横に紙コップの筒"""
    P = K.Parts(name, kind="water")
    for r in ("wood", "wood_dark", "felt_charcoal"):
        P.hard[r] = 0.006
    K.box(P, "wood", (0, 0, 0.45), (0.4, 0.36, 0.9))
    K.box(P, "wood_dark", (0, 0.185, 0.3), (0.3, 0.012, 0.42))                    # 前の戸
    for z in (0.14, 0.46):   # 蝶番
        K.box(P, "felt_tin", (-0.155, 0.19, z), (0.016, 0.01, 0.05))
    K.disc(P, "button", (0.11, 0.19, 0.3), 0.012, 0.012, axis="Y", segs=10)
    K.pbox(P, "felt_ivory", (0, 0, 0.93), (0.19, 0.17, 0.04), n=6.0, seam_role="thread")
    K.lathe(P, "glass", [(0.0, 1.45), (0.15, 1.42), (0.17, 1.35), (0.17, 1.08), (0.06, 1.0), (0.04, 0.97)], segs=K.cuts(32, 18),
            closed=False)
    K.lathe(P, "felt_water", [(0.0, 1.32), (0.155, 1.32), (0.155, 1.08), (0.055, 1.01), (0.0, 1.0)], segs=K.cuts(32, 18))
    K.stitch_ring(P, "thread", (0, 0, 1.2), 0.173, r=0.003)
    # 注ぎ口: 赤（温）と青（冷）のフェルトのつまみ
    for x, role in ((-0.06, "felt_red"), (0.06, "felt_sky")):
        K.box(P, "felt_charcoal", (x, 0.19, 0.72), (0.04, 0.05, 0.04))
        K.pbox(P, role, (x, 0.22, 0.75), (0.018, 0.018, 0.02), n=3.0, c=4)
    K.box(P, "felt_charcoal", (0, 0.2, 0.6), (0.24, 0.06, 0.012))   # 受け皿
    # 紙コップの筒（横）
    K.lathe(P, "glass", [(0.045, 0.55), (0.045, 0.85)], center=(0.24, 0.05, 0), segs=16, closed=False)
    for k in range(6):
        paper_cup(P, (0.24, 0.05, 0.56 + 0.04 * k), h=0.07, r0=0.026, r1=0.036)
    P.mark("tap", (0, 0.22, 0.7))
    P.finish(fuzz=0.0015)


def cup_stack(name, n=8):
    P = K.Parts(name, kind="water")
    for k in range(n):
        paper_cup(P, (0, 0, 0.012 * k))
    P.finish()


# ---------------------------------------------------------------- 卓の小物
def tissue(name, role, pattern=None):
    """ティッシュの箱: フェルトの箱、楕円の口から紙がふわりと出る"""
    P = K.Parts(name, kind="table_item")
    P.m(role).uv_scale = 2.5   # パッチワークなら端切れを細かく
    K.pbox(P, role, (0, 0, 0.045), (0.12, 0.06, 0.045), n=8.0, seam_role="thread", c=7)
    K.extrude(P, "felt_charcoal", K.circle_poly(0.05, 20, sy=0.3), 0.0898, 0.0905)
    if pattern:   # 箱の横のアップリケ（花）
        for k in range(5):
            a = 2 * math.pi * k / 5
            K.extrude(P, pattern, K.circle_poly(0.008, 10, 0.04 + 0.012 * math.cos(a), 0.045 + 0.012 * math.sin(a)),
                      0.0605, 0.062, plane="XZ")
        K.extrude(P, "felt_mustard", K.circle_poly(0.006, 10, 0.04, 0.045), 0.0615, 0.0635, plane="XZ")
    # 紙: 波打った 1 枚が口から立つ
    m = P.m("paper_white")
    nu, nv = 10, 6
    vs = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            u = (i / nu - 0.5)
            v = j / nv
            x = u * 0.1 * (1 - 0.3 * v)
            y = 0.01 * math.sin(u * 9 + v * 3) + 0.012 * v
            z = 0.088 + 0.07 * v + 0.012 * math.sin(u * 6) * v
            row.append(m.bm.verts.new((x, y, z)))
        vs.append(row)
    for j in range(nv):
        for i in range(nu):
            m.bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    P.finish(fuzz=0.0015)


def chopstick_box(name):
    P = K.Parts(name, kind="table_item")
    K.box(P, "wood", (0, 0, 0.06), (0.1, 0.1, 0.12))
    K.box(P, "wood_dark", (0, 0, 0.115), (0.104, 0.104, 0.01))
    rnd = random.Random(4)
    for k in range(10):
        x, y = rnd.uniform(-0.03, 0.03), rnd.uniform(-0.03, 0.03)
        K.tube(P, "wood_light", [(x, y, 0.02), (x * 1.6, y * 1.6, 0.24)], [0.003, 0.0045], sides=6)
    P.finish()


def condiments(name):
    """薬味: 七味のひょうたん、醤油さし、つまようじ入れを小さな木の盆に"""
    P = K.Parts(name, kind="table_item")
    K.extrude(P, "wood", K.round_rect(0.2, 0.1, 0.015), 0.0, 0.01)
    K.pbox(P, "felt_rust", (-0.06, 0, 0.035), (0.025, 0.025, 0.025), n=2.0, c=6)                # ひょうたん
    K.pbox(P, "felt_rust", (-0.06, 0, 0.075), (0.017, 0.017, 0.018), n=2.0, c=6)
    K.disc(P, "wood", (-0.06, 0, 0.097), 0.008, 0.012, segs=10)
    K.lathe(P, "glass", [(0.0, 0.01), (0.022, 0.01), (0.024, 0.05), (0.014, 0.07), (0.0, 0.07)], center=(0.0, 0, 0), segs=16)
    K.lathe(P, "felt_brown", [(0.0, 0.012), (0.02, 0.012), (0.021, 0.04), (0.0, 0.04)], center=(0.0, 0, 0), segs=16)
    K.pbox(P, "felt_red", (0.0, 0, 0.078), (0.015, 0.015, 0.012), n=2.0, c=4)
    K.tube(P, "felt_red", [(0.01, 0, 0.08), (0.03, 0, 0.088)], 0.004, sides=6)
    K.lathe(P, "wood_light", [(0.0, 0.01), (0.018, 0.01), (0.018, 0.06), (0.0, 0.06)], center=(0.065, 0, 0), segs=14)
    for k in range(6):
        a = 2 * math.pi * k / 6
        K.dowel(P, "wood_light", (0.065 + 0.008 * math.cos(a), 0.008 * math.sin(a), 0.02), (0.065 + 0.01 * math.cos(a), 0.01 * math.sin(a), 0.085), 0.0012, 4)
    P.finish(fuzz=0.001)


def counter(name, front="patch_warm"):
    """カウンター 1 区画（幅 1.8 m）: 木の天板、前はパッチワークのフェルト張り、足もとに木の蹴込み。並べてつなぐ"""
    P = K.Parts(name, kind="counter", span=1.8)
    for r in ("wood", "wood_dark"):
        P.hard[r] = 0.008
    W, D, H = 1.8, 0.6, 1.05
    K.box(P, "wood", (0, 0, H - 0.025), (W, D + 0.08, 0.05))
    K.box(P, "wood_dark", (0, 0, (H - 0.05) / 2), (W, D, H - 0.05))
    K.pbox(P, front, (0, D / 2 + 0.01, H * 0.5), (W / 2 - 0.04, 0.025, H * 0.36), n=8.0, nz=8.0, c=6)
    K.stitch_line(P, "thread", [(-W / 2 + 0.06, D / 2 + 0.037, H * 0.83), (W / 2 - 0.06, D / 2 + 0.037, H * 0.83)], r=0.003, dash=0.03)
    K.stitch_line(P, "thread", [(-W / 2 + 0.06, D / 2 + 0.037, H * 0.17), (W / 2 - 0.06, D / 2 + 0.037, H * 0.17)], r=0.003, dash=0.03)
    K.box(P, "wood", (0, D / 2 - 0.02, 0.05), (W, 0.06, 0.1))
    P.mark("top", (0, 0, H))
    P.finish(fuzz=0.002)


# ---------------------------------------------------------------- 組む
menu_board("menu_food", [(ic_ramen(), 4), (ic_curry(), 4), (ic_oden(), 2), (ic_onigiri(), 1)])
menu_board("menu_drink", [(ic_can("felt_yellow"), 1), (ic_cup("felt_brown"), 2), (ic_can("felt_navy2"), 1), (ic_cup("felt_tea"), 1)],
           cloth="felt_rust")
menu_board("menu_sweet", [(ic_bun(), 2), (ic_taiyaki(), 2), (ic_dango(), 1), (ic_mikan(), 1)], cloth="felt_moss" if "felt_moss" in C.HEX else "felt_green")
register("register")
register("register_navy", "felt_navy2")
bell("bell")
tray("tray_wood", "rect", "wood")
tray("tray_dark", "rect", "wood_dark")
tray("tray_round_red", "round", "felt_red")
water_server("water_server")
cup_stack("paper_cups")
tissue("tissue_ivory", "felt_ivory", "felt_rust")
tissue("tissue_patch", "patch_rose")
tissue("tissue_indigo", "felt_indigo", "felt_ivory")
chopstick_box("chopstick_box")
condiments("condiments")
counter("counter_patch")
counter("counter_indigo", "felt_indigo")

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    R["counter_patch"].location = (-0.9, 0, 0)
    R["counter_indigo"].location = (0.9, 0, 0)
    T = 1.05
    for n, (x, y, z) in {"register": (-1.2, 0.0, T), "bell": (-0.75, 0.15, T), "tray_wood": (-0.25, 0.05, T),
                         "tray_dark": (0.3, 0.05, T), "tray_round_red": (0.85, 0.05, T), "paper_cups": (1.35, 0.1, T),
                         "chopstick_box": (1.6, -0.1, T), "condiments": (0.85, 0.05, T + 0.013),
                         "tissue_ivory": (-1.65, -0.15, T), "register_navy": (3.4, 0.6, 0.75), "tissue_patch": (3.0, 0.4, 0.75),
                         "tissue_indigo": (3.75, 0.25, 0.75), "water_server": (2.4, -0.7, 0),
                         "menu_food": (-1.0, -0.9, 2.1), "menu_drink": (0.0, -0.9, 2.1), "menu_sweet": (1.0, -0.9, 2.1)}.items():
        R[n].location = (x, y, z)
    K.table(3.4, 0.4, 0.75, 1.1, 0.7)
    K.room(floor_size=14.0, wall_y=-1.3)
    K.interior_light(1.0)
    cams = {
        "all": ((0.8, 5.5, 2.3), (0.6, -0.3, 1.3), 30),
        "menus": ((0.0, 2.2, 1.9), (0.0, -0.9, 2.0), 32),
        "register": ((-0.6, 1.4, 1.6), (-0.8, 0.0, 1.15), 34),
        "table": ((3.4, 1.7, 1.3), (3.35, 0.35, 0.82), 36),
        "water": ((2.0, 1.4, 1.2), (2.4, -0.7, 0.8), 34),
    }
    K.render_views(A, cams)
