"""厨房の作業台と、卓に載せる調理の道具を Blender で組む。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_kitchen.py -- \
        --views all,press,dryer,pellets --prefix props/renders/18-kitchen

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_kitchen.py -- \
        --look flat --export game/props/kitchen

料理の考え方（代表、2026-10-28）: レジで食べ物のもとになるペレットを買い、アイロン台でプレスしたり、
乾燥機で温めたりすると食べられるようになる。そこで道具は卓に載る大きさにして、作業台に並べる。
  作業台     = 木の台に、方眼をなみ縫いしたフェルトのマット（裁縫の切り台の形）。下の棚に麻の籠
  アイロン台 = 卓上の小さなアイロン台。パッチワークの覆いに、熱をもった楕円。アイロンはかかとで立てる
  プレス機   = 服のプレス機。下の熱板に、蝶番で上の板をかぶせて押す。上の板は開けてある
  乾燥機     = 卓上の丸窓の箱。中に編み地の胴と、奥に熱をもったフェルト
  ペレット   = フェルトの毛玉の粒。ガラスの瓶、麻袋、紙袋、仕分けの盆に入れる
前は +Y。道具には、粒を入れる・押す所の目印 cook を入れる。
"""
import math
import os
import random
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）"))])
K.setup(A, fiber=3.0, scale=2.0, tris=2500)
EX = K.S["export"]
C.HEX.update({"felt_ivory": "EEE6D4", "felt_mustard": "C99A3A", "felt_indigo": "2E3F66", "felt_rust": "A8532E",
              "felt_moss": "6E7F4A", "felt_sky": "8FAFC8"})

PELLET = {"mix": ["felt_beige", "felt_brown", "felt_red", "felt_green", "felt_yellow"],
          "red": ["felt_red", "felt_red_dark", "felt_orange"], "green": ["felt_green", "felt_tea", "felt_moss"],
          "yellow": ["felt_yellow", "felt_beige", "felt_mustard"], "brown": ["felt_brown", "felt_tan", "felt_beige"]}


def moved(P, mtx, build):
    """build() で足した部品だけを mtx で動かす（蝶番で開けた板、立てたアイロン、など）"""
    before = {role: len(m.bm.verts) for role, m in P.ms.items()}
    build()
    for role, m in P.ms.items():
        C.place(m, before.get(role, 0), mtx)


def pellet(P, role, p, r=0.011, rnd=None):
    """粒ひとつ: 少しいびつなフェルトの毛玉"""
    m = P.m(role)
    n0 = len(m.bm.verts)
    C.superellipsoid(m, (0, 0, 0), (r, r, r * 0.9), n_xy=2.0, n_z=2.0, cuts=2 if EX else 4)
    rnd = rnd or random.Random(0)
    a = rnd.uniform(0, math.pi)
    C.place(m, n0, Matrix.Translation(p) @ Matrix.Rotation(a, 4, "Z"))


def pellet_mound(P, colors, center, R, h, n, seed=0, r=0.011, core=None):
    """粒の山: 中は詰め物の芯（見えない）で、表に粒を並べる"""
    rnd = random.Random(seed)
    c = Vector(center)
    if core:
        K.lathe(P, core, [(0.0, 0.0), (R * 0.92, 0.0), (R * 0.7, h * 0.6), (0.0, h * 0.85)], center=c, segs=16)
    for k in range(n):
        u = math.sqrt(rnd.random())
        a = rnd.uniform(0, 2 * math.pi)
        z = h * (1 - u * u) * 0.85 + r * 0.6
        pellet(P, rnd.choice(colors), c + Vector((R * u * math.cos(a), R * u * math.sin(a), z)), r * rnd.uniform(0.85, 1.1), rnd)


# ---------------------------------------------------------------- 作業台
def work_table(name, mat):
    """作業台: 木の台に方眼のフェルトのマット。下の棚に麻の籠と粒"""
    P = K.Parts(name, kind="work_table", size=[0.9, 0.45], height=0.47)
    for r in ("wood", "wood_dark"):
        P.hard[r] = 0.004
    W, D, H = 0.9, 0.45, 0.46
    K.box(P, "wood", (0, 0, H - 0.015), (W, D, 0.03))
    for (cx, cy, sx, sy) in ((0, D / 2 - 0.03, W - 0.08, 0.02), (0, -D / 2 + 0.03, W - 0.08, 0.02),
                             (W / 2 - 0.03, 0, 0.02, D - 0.08), (-W / 2 + 0.03, 0, 0.02, D - 0.08)):
        K.box(P, "wood_dark", (cx, cy, H - 0.055), (sx, sy, 0.05))                           # 幕板
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.box(P, "wood", (sx * (W / 2 - 0.035), sy * (D / 2 - 0.035), (H - 0.03) / 2), (0.035, 0.035, H - 0.03))
    K.box(P, "wood", (0, 0, 0.08), (W - 0.05, D - 0.05, 0.018))                               # 下の棚
    # マット: 方眼のなみ縫い（切り台の目盛り）と、縁の糸
    mw, md = W - 0.06, D - 0.06
    K.pbox(P, mat, (0, 0, H + 0.004), (mw / 2, md / 2, 0.005), n=12.0, nz=4.0, c=K.cuts(8, 5))
    z = H + 0.0095
    k = 1
    while -mw / 2 + 0.075 * k < mw / 2 - 0.02:
        x = -mw / 2 + 0.075 * k
        K.stitch_line(P, "thread", [(x, -md / 2 + 0.02, z), (x, md / 2 - 0.02, z)], r=0.0018, dash=0.012)
        k += 1
    k = 1
    while -md / 2 + 0.075 * k < md / 2 - 0.02:
        y = -md / 2 + 0.075 * k
        K.stitch_line(P, "thread", [(-mw / 2 + 0.02, y, z), (mw / 2 - 0.02, y, z)], r=0.0018, dash=0.012)
        k += 1
    rim = K.round_rect(mw - 0.01, md - 0.01, 0.01, n=3)
    K.stitch_line(P, "thread_gold", [(x, y, z) for x, y in rim + rim[:1]], r=0.0022, dash=0.016)
    # 下の棚: 麻の籠に粒
    K.lathe(P, "hemp", [(0.0, 0.0), (0.075, 0.0), (0.09, 0.06), (0.085, 0.062), (0.07, 0.006), (0.0, 0.006)],
            center=(-0.22, 0.0, 0.089), segs=K.cuts(28, 18))
    K.ring(P, "hemp", (-0.22, 0.0, 0.089 + 0.06), 0.088, 0.008, n=28)
    pellet_mound(P, PELLET["mix"], (-0.22, 0.0, 0.1), 0.07, 0.035, 18 if EX else 26, seed=3, core="felt_beige")
    K.lathe(P, "hemp", [(0.0, 0.0), (0.075, 0.0), (0.09, 0.06), (0.085, 0.062), (0.07, 0.006), (0.0, 0.006)],
            center=(0.2, 0.02, 0.089), segs=K.cuts(28, 18))
    K.ring(P, "hemp", (0.2, 0.02, 0.089 + 0.06), 0.088, 0.008, n=28)
    pellet_mound(P, PELLET["red"], (0.2, 0.02, 0.1), 0.07, 0.035, 18 if EX else 26, seed=4, core="felt_red_dark")
    P.mark("top", (0, 0, H + 0.01))
    for i, x in enumerate((-0.25, 0.25)):
        P.mark("stand_%d" % i, (x, -D / 2 - 0.25, 0))   # 人が立って使う所（前は -Y＝カウンターの側に向けて置く）
    P.finish(fuzz=0.0015)


# ---------------------------------------------------------------- アイロン台とアイロン
def board_outline(L, W, n=24):
    """アイロン台の形: 後ろは四角く丸め、前はとがる"""
    pts = []
    for i in range(n + 1):
        t = i / n
        y = -L / 2 + L * t
        w = W / 2 * (1 - max(0, (t - 0.45) / 0.55) ** 1.8 * 0.8)
        pts.append((w, y))
    we = pts[-1][0]
    tip = [(we * math.cos(math.pi * k / 8), L / 2 + we * math.sin(math.pi * k / 8)) for k in range(1, 8)]
    return pts + tip + [(-x, y) for (x, y) in reversed(pts)]


def iron(P, body, s=0.36):
    """アイロン: 前がとがったふっくらした胴、熱い底、木の取っ手（原点は胴の真ん中、前は +Y）"""
    m = P.m(body)
    n0 = len(m.bm.verts)
    C.superellipsoid(m, (0, 0, 0), (0.13 * s, 0.22 * s, 0.09 * s), n_xy=3.0, n_z=3.0, cuts=K.cuts(8, 6))
    for v in C.new_verts(m, n0):
        t = (v.co.y / s + 0.22) / 0.44
        v.co.x *= 1 - 0.65 * t ** 2
        v.co.z = max(v.co.z, -0.04 * s) + (0.0 if v.co.z < 0 else 0.03 * s * (1 - t))
    so = [(0.13 * s * (1 - 0.65 * ((y + 0.22) / 0.44) ** 2) * sx, y * s) for sx, y in
          [(1, -0.22 + 0.44 * k / 12) for k in range(13)] + [(-1, 0.22 - 0.44 * k / 12) for k in range(13)]]
    K.extrude(P, "felt_heat", so, -0.065 * s, -0.04 * s)
    K.tube(P, "wood", [(0, -0.12 * s, 0.06 * s), (0, -0.1 * s, 0.17 * s), (0, 0.05 * s, 0.19 * s), (0, 0.12 * s, 0.08 * s)],
           0.028 * s, sides=10)
    K.disc(P, "felt_ivory", (0.085 * s * 0.8, -0.05 * s, 0.05 * s), 0.025 * s, 0.01 * s, axis="X", segs=16)   # 温度のつまみ


def press_board(name, cover="patch_warm", body="felt_red"):
    """卓上のアイロン台: 短い脚の板に綿を詰めた覆い、熱をもった楕円。アイロンはかかとで立てて、後ろで休ませる"""
    P = K.Parts(name, kind="cook", tool="press")
    P.hard["wood"] = 0.003
    L, W = 0.34, 0.13
    poly = board_outline(L, W)
    K.extrude(P, "wood", poly, 0.04, 0.05)
    for y in (-L / 2 + 0.05, L / 2 - 0.09):   # 脚: 横木 2 本
        K.box(P, "wood_dark", (0, y, 0.02), (W * 0.8 if y < 0 else W * 0.5, 0.025, 0.04))
    m = P.m(cover)
    m.uv_scale = 3.5   # 小さな台なので端切れを細かく
    n0 = len(m.bm.verts)
    K.extrude(P, cover, poly, 0.05, 0.068)
    for v in C.new_verts(m, n0):   # 覆いは縁を丸める（綿の詰め物）
        if v.co.z > 0.06:
            v.co.x *= 0.96
            v.co.y = v.co.y * 0.97
    hp = K.circle_poly(1.0, 32, 0.0, 0.02, sx=0.035, sy=0.075)
    K.extrude(P, "felt_heat", hp, 0.068, 0.071)
    K.stitch_line(P, "thread", [(x * 1.25, 0.02 + (y - 0.02) * 1.18, 0.0715) for x, y in hp + hp[:1]], r=0.0015, dash=0.008)
    # アイロン: 台の横の鍋敷き（灰色のフェルト）に寝かせる。前は台と同じ向き
    ix = W / 2 + 0.075
    K.pbox(P, "felt_charcoal", (ix, -0.06, 0.005), (0.055, 0.09, 0.005), n=6.0, nz=3.0, c=K.cuts(6, 4))
    moved(P, Matrix.Translation((ix, -0.06, 0.01 + 0.065 * 0.36)), lambda: iron(P, body))
    # 線: クリームの毛糸が、アイロンの後ろから卓に垂れる
    K.tube(P, "yarn_cream", [(ix, -0.06 - 0.06, 0.035), (ix + 0.01, -0.06 - 0.1, 0.025), (ix + 0.02, -0.06 - 0.13, 0.005),
                             (ix + 0.06, -0.06 - 0.16, 0.004), (ix + 0.12, -0.06 - 0.15, 0.004)], 0.005, sides=6)
    P.mark("cook", (0, 0.02, 0.072))
    P.finish(fuzz=0.0012)


# ---------------------------------------------------------------- プレス機
def heat_press_body(P, body):
    """服のプレス機の本体: 木の台に下の熱板、後ろの柱の蝶番で上の板を開ける。上の板の前に取っ手、柱に目盛り"""
    K.box(P, "wood", (0, 0, 0.02), (0.22, 0.27, 0.04))
    K.box(P, "felt_charcoal", (0, 0.02, 0.05), (0.18, 0.2, 0.02))
    hp = K.round_rect(0.16, 0.18, 0.02, n=4)
    K.extrude(P, "felt_heat", [(x, y + 0.02) for x, y in hp], 0.06, 0.065)
    K.stitch_line(P, "thread", [(x * 0.85, y * 0.85 + 0.02, 0.0655) for x, y in hp + hp[:1]], r=0.0015, dash=0.008)
    K.box(P, "wood_dark", (0, -0.115, 0.13), (0.06, 0.04, 0.18))                                # 柱
    hz = 0.2
    K.dowel(P, "felt_tin", (-0.045, -0.1, hz), (0.045, -0.1, hz), 0.012, 12)                   # 蝶番
    # 目盛り: 柱の前の丸い盤に糸の目と針
    K.disc(P, "felt_ivory", (0, -0.093, 0.12), 0.022, 0.006, axis="Y", segs=20)
    for k in range(7):
        a = math.pi * (0.15 + 0.7 * k / 6)
        p = Vector((0.017 * math.cos(a), -0.089, 0.12 + 0.017 * math.sin(a)))
        K.tube(P, "thread_dark", [p, p + Vector((0.005 * math.cos(a), 0, 0.005 * math.sin(a)))], 0.0012, sides=4)
    K.tube(P, "felt_red_dark", [(0, -0.088, 0.12), (0.01, -0.088, 0.132)], 0.0015, sides=4)

    def lid():
        K.box(P, "wood_dark", (0, 0.06, 0.0), (0.04, 0.14, 0.03))                              # 腕
        K.pbox(P, body, (0, 0.12, -0.03), (0.095, 0.105, 0.028), n=6.0, seam_role="thread", c=K.cuts(7, 5))
        K.extrude(P, "felt_heat", [(x, y + 0.12) for x, y in hp], -0.063, -0.058)
        K.tube(P, "wood", [(-0.05, 0.225, -0.02), (-0.05, 0.27, -0.01), (0.05, 0.27, -0.01), (0.05, 0.225, -0.02)],
               0.008, sides=8)
        K.disc(P, "button", (0, 0.12, 0.002), 0.018, 0.012, segs=12)
    moved(P, Matrix.Translation((0, -0.1, hz)) @ Matrix.Rotation(math.radians(38), 4, "X"), lid)
    # 押されて平らになった粒が、熱板にひとつ
    K.pbox(P, "felt_tan", (0.02, 0.04, 0.071), (0.035, 0.03, 0.006), n=3.0, c=4)


def heat_press(name, body="felt_red"):
    """卓上のプレス機"""
    P = K.Parts(name, kind="cook", tool="press")
    for r in ("wood", "wood_dark", "felt_charcoal"):
        P.hard[r] = 0.003
    heat_press_body(P, body)
    P.mark("cook", (0, 0.02, 0.07))
    P.finish(fuzz=0.0012)


# ---------------------------------------------------------------- 卓上の乾燥機
def dryer_body(P, body, band, knob):
    """乾燥機の本体: 背の高いふっくらした箱（幅 0.24、高さ 0.34）。上に操作盤（大きなつまみ・ボタン・灯り）、
    真ん中に丸い戸（透明なフィルムを白い糸で留め、中に羽根のある編み地の胴、奥に熱）、下に蹴込みの帯と通気の溝"""
    D = DRYER
    K.box(P, "wood", (0, 0, 0.008), (0.27, 0.27, 0.016))
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.disc(P, "button", (sx * 0.105, sy * 0.105, 0.02), 0.013, 0.012, segs=10)
    BZ = 0.025 + 0.16
    K.pbox(P, body, (0, 0, BZ), (0.12, 0.12, 0.16), n=10.0, nz=8.0, seam_role="thread")
    K.pbox(P, band, (0, 0, 0.3), (0.123, 0.123, 0.035), n=10.0, nz=6.0, c=K.cuts(6, 4))      # 操作盤
    K.pbox(P, band, (0, 0, 0.05), (0.122, 0.122, 0.02), n=10.0, nz=6.0, c=K.cuts(6, 4))      # 蹴込み
    fy = D["fy"]
    for k in range(4):   # 蹴込みの通気の溝
        K.box(P, "felt_charcoal", (-0.045 + 0.03 * k, fy + 0.002, 0.05), (0.02, 0.004, 0.006))
    # 操作盤: 右に大きなつまみと目盛り、左にボタン 3 つと灯り
    K.disc(P, "wood", (0.075, fy + 0.008, 0.3), 0.024, 0.016, axis="Y", segs=20)
    K.box(P, "wood_dark", (0.075, fy + 0.017, 0.31), (0.004, 0.003, 0.016))
    for k in range(7):
        a = math.pi * (0.1 + 0.8 * k / 6)
        p = Vector((0.075 + 0.032 * math.cos(a), fy + 0.006, 0.3 + 0.032 * math.sin(a) - 0.004))
        K.tube(P, "thread", [p, p + Vector((0.006 * math.cos(a), 0, 0.006 * math.sin(a)))], 0.0014, sides=4)
    for k, role in enumerate(("felt_ivory", "felt_ivory", knob)):
        K.pbox(P, role, (-0.085 + 0.028 * k, fy + 0.006, 0.295), (0.01, 0.006, 0.008), n=3.0, c=4)
    K.disc(P, "felt_heat", (-0.03, fy + 0.006, 0.31), 0.006, 0.004, axis="Y", segs=12)        # 動いている灯り
    # 丸い戸
    cz, R = D["cz"], D["R"]
    K.tube(P, band, [(R * math.cos(a), fy + 0.008, cz + R * math.sin(a)) for a in
                     [2 * math.pi * k / 48 for k in range(49)]], 0.016, sides=8, caps=False)
    K.disc(P, "glass", (0, fy + 0.006, cz), R - 0.006, 0.003, axis="Y", segs=32)
    K.stitch_ring(P, "thread", (0, fy + 0.012, cz), R - 0.012, r=0.0016, axis="Y", dash=0.008)
    for sz in (-1, 1):   # 蝶番
        K.box(P, "felt_tin", (-R - 0.012, fy + 0.006, cz + sz * 0.035), (0.016, 0.01, 0.014))
    K.tube(P, "wood", [(R + 0.004, fy + 0.012, cz - 0.03), (R + 0.02, fy + 0.026, cz - 0.03),
                       (R + 0.02, fy + 0.026, cz + 0.03), (R + 0.004, fy + 0.012, cz + 0.03)], 0.006, sides=8)
    # 中: 編み地の胴に羽根 3 枚、奥に熱
    K.lathe(P, "knit_drum", [(R - 0.01, 0.0), (R - 0.01, -0.18), (0.0, -0.18)], center=(0, fy, cz), segs=24, closed=False,
            rot=(-math.pi / 2, "X"))
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        K.box(P, "felt_charcoal", ((R - 0.022) * math.cos(a), fy - 0.09, cz + (R - 0.022) * math.sin(a)), (0.02, 0.16, 0.012),
              rot=(-a, "Y"))
    K.disc(P, "felt_heat", (0, fy - 0.175, cz), R - 0.02, 0.006, axis="Y", segs=24)
    for k, (dx, dz) in enumerate(((-0.02, -0.045), (0.018, -0.05), (0.0, -0.034))):
        pellet(P, PELLET["mix"][k], (dx, fy - 0.07, cz + dz), 0.012)


DRYER = dict(fy=0.121, cz=0.17, R=0.075)   # 乾燥機の戸の前の面・中心の高さ・半径（卓上の大きさ）


def table_dryer(name, body="felt_cream", band="felt_navy2", knob="felt_red"):
    """卓上の乾燥機"""
    P = K.Parts(name, kind="cook", tool="warm")
    dryer_body(P, body, band, knob)
    P.mark("cook", (0, DRYER["fy"] - 0.06, DRYER["cz"]))
    P.finish(fuzz=0.0015)


# ---------------------------------------------------------------- 巨大な装置（厨房の顔。人が前に立って使う）
def giant_press_board(name, cover="patch_warm", body="felt_red"):
    """巨大なアイロン台: 長さ 1.7（ゲームで 3.4 m）、面の高さ 0.5（1 m）。X の脚で立ち、後ろの四角い所に
    灰色の鍋敷きと、寝かせた大きなアイロン。前の熱い楕円から湯気、押された粒がひとつ"""
    P = K.Parts(name, kind="cook", tool="press", giant=True, tris=5000)
    for r in ("wood", "wood_dark"):
        P.hard[r] = 0.008
    L, W, H = 1.7, 0.62, 0.5
    poly = board_outline(L, W, n=40)
    K.extrude(P, "wood", poly, H - 0.04, H - 0.02)
    m = P.m(cover)
    n0 = len(m.bm.verts)
    K.extrude(P, cover, poly, H - 0.02, H + 0.03)
    for v in C.new_verts(m, n0):   # 綿を詰めた覆いの縁を丸める
        if v.co.z > H:
            v.co.x *= 0.97
            v.co.y *= 0.985
    hp = K.circle_poly(1.0, 48, 0.0, 0.2, sx=0.17, sy=0.3)
    K.extrude(P, "felt_heat", hp, H + 0.03, H + 0.036)
    K.stitch_line(P, "thread", [(x * 1.15, 0.2 + (y - 0.2) * 1.1, H + 0.037) for x, y in hp + hp[:1]], r=0.005, dash=0.03)
    K.pbox(P, "felt_tan", (0.04, 0.24, H + 0.044), (0.09, 0.065, 0.01), n=3.0, c=5)
    # X の脚と、床の横木
    for sx in (-0.2, 0.2):
        K.dowel(P, "wood", (sx, -0.55, H - 0.04), (sx, 0.42, 0.0), 0.028, 12)
        K.dowel(P, "wood", (sx, 0.32, H - 0.04), (sx, -0.65, 0.0), 0.028, 12)
    K.dowel(P, "wood_dark", (-0.24, 0.42, 0.025), (0.24, 0.42, 0.025), 0.028, 12)
    K.dowel(P, "wood_dark", (-0.24, -0.65, 0.025), (0.24, -0.65, 0.025), 0.028, 12)
    K.dowel(P, "felt_tin", (-0.23, -0.04, 0.27), (0.23, -0.04, 0.27), 0.02, 12)               # 脚の交わる所の軸
    # 後ろの鍋敷きに大きなアイロン
    s = 1.2
    K.pbox(P, "felt_charcoal", (0, -0.58, H + 0.042), (0.17, 0.26, 0.012), n=6.0, nz=3.0)
    moved(P, Matrix.Translation((0, -0.58, H + 0.054 + 0.065 * s)), lambda: iron(P, body, s))
    K.tube(P, "yarn_cream", [(0, -0.58 - 0.2 * s, H + 0.1), (0.02, -0.92, H + 0.05), (0.06, -0.97, 0.25),
                             (0.1, -0.95, 0.012), (0.3, -0.9, 0.012), (0.5, -0.98, 0.012)], 0.012, sides=8)
    K.steam(P, (0.0, 0.18, H + 0.04), 0.45, 0.05, seed=4)
    P.mark("cook", (0, 0.2, H + 0.04))
    P.finish(fuzz=0.003)


def giant_heat_press(name, body="felt_red"):
    """巨大なプレス機: 引き出しの付いた木の台に、卓上のプレス機を 3.5 倍にして載せる（熱板の高さはゲームで 1 m）"""
    P = K.Parts(name, kind="cook", tool="press", giant=True, tris=5000)
    for r in ("wood", "wood_dark", "felt_charcoal"):
        P.hard[r] = 0.01
    k, B = 3.5, 0.25
    K.box(P, "wood", (0, 0, B / 2), (0.8, 0.98, B))
    for x in (-0.2, 0.2):   # 引き出しとつまみ
        K.box(P, "wood_dark", (x, 0.492, B / 2), (0.34, 0.012, 0.16))
        K.disc(P, "button", (x, 0.505, B / 2), 0.03, 0.025, axis="Y", segs=16)
    moved(P, Matrix.Translation((0, 0, B)) @ Matrix.Scale(k, 4), lambda: heat_press_body(P, body))
    K.steam(P, (0.05, 0.15, B + 0.07 * k), 0.35, 0.05, seed=5)
    P.mark("cook", (0, 0.02 * k, B + 0.07 * k))
    P.finish(fuzz=0.003)


def giant_dryer(name, body="felt_cream", band="felt_navy2", knob="felt_red"):
    """巨大な乾燥機: 卓上の乾燥機を 5 倍に（ゲームで幅 2.4 m、高さ 3.4 m、戸の径 1.5 m）。胴の底に大きな粒が転がる"""
    P = K.Parts(name, kind="cook", tool="warm", giant=True, tris=5000)
    P.hard["wood"] = 0.01
    k = 5.0
    moved(P, Matrix.Scale(k, 4), lambda: dryer_body(P, body, band, knob))
    fy, cz, R = DRYER["fy"] * k, DRYER["cz"] * k, (DRYER["R"] - 0.01) * k
    rnd = random.Random(8)
    for i in range(22):
        y = fy - rnd.uniform(0.12, 0.55)
        x = rnd.uniform(-0.6, 0.6) * R
        z = cz - math.sqrt(max(0.0, R * R - x * x)) + 0.05 + rnd.uniform(0.0, 0.06)
        pellet(P, rnd.choice(PELLET["mix"]), (x, y, z), 0.045, rnd)
    # 上の漏斗: ここから粒を入れる。縁に縫い目、中に粒の山
    top = (0.025 + 0.32) * k
    hx, hy = 0.38, -0.12
    K.lathe(P, knob, [(0.0, top - 0.02), (0.08, top - 0.02), (0.08, top + 0.08), (0.22, top + 0.3), (0.235, top + 0.32),
                      (0.205, top + 0.31), (0.065, top + 0.09), (0.0, top + 0.09)], center=(hx, hy, 0), segs=K.cuts(40, 24))
    K.stitch_ring(P, "thread", (hx, hy, top + 0.27), 0.205, r=0.006, dash=0.04)
    pellet_mound(P, PELLET["mix"], (hx, hy, top + 0.2), 0.12, 0.06, 14 if EX else 20, seed=9, r=0.04, core=PELLET["mix"][0])
    # 横の排気: 毛糸のホースが上へ曲がり、先から湯気
    hose = [(0.6, -0.25, 1.0), (0.72, -0.25, 1.05), (0.8, -0.28, 1.3), (0.8, -0.3, 1.75), (0.76, -0.3, 1.9)]
    K.tube(P, "yarn_red" if knob != "felt_red" else "yarn_cream", hose, 0.05, sides=10)
    K.ring(P, band, hose[0], 0.065, 0.02, axis="X", n=24)
    K.steam(P, (0.76, -0.3, 1.92), 0.4, 0.06, seed=6)
    P.mark("hopper", (hx, hy, top + 0.3))
    P.mark("cook", (0, fy - 0.3, cz))
    P.finish(fuzz=0.004)


# ---------------------------------------------------------------- ペレットの入れ物
def pellet_jar(name, colors, lid="felt_red", seed=0):
    """ガラスの瓶: 粒をいっぱいに入れ、フェルトの蓋を麻ひもで縛る"""
    P = K.Parts(name, kind="pellets")
    rnd = random.Random(seed)
    Rj, H = 0.045, 0.115
    K.lathe(P, "glass", [(0.0, 0.0), (Rj - 0.004, 0.0), (Rj, 0.006), (Rj, H - 0.015), (Rj - 0.008, H - 0.006),
                         (Rj - 0.009, H)], segs=K.cuts(32, 20), closed=False)
    # 粒: 中は芯で埋め、ガラスに触れる外側と上に並べる
    r = 0.0095
    layers = int((H - 0.024) / (r * 1.8))
    zt = 0.004 + r + (layers - 1) * r * 1.8
    K.lathe(P, colors[0], [(0.0, 0.004), (Rj - 0.012, 0.004), (Rj - 0.012, zt), (0.0, zt)], segs=12)
    for j in range(layers):
        z = 0.004 + r + j * r * 1.8
        n = 13
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * (j % 2)) / n + rnd.uniform(-0.08, 0.08)
            pellet(P, rnd.choice(colors), (math.cos(a) * (Rj - r - 0.002), math.sin(a) * (Rj - r - 0.002), z), r, rnd)
    pellet_mound(P, colors, (0, 0, zt - r * 0.5), Rj - 0.012, 0.01, 12, seed=seed + 7, r=r)
    # 蓋: 布をかぶせて麻ひもで縛る
    K.pbox(P, lid, (0, 0, H + 0.006), (Rj + 0.004, Rj + 0.004, 0.008), n=2.0, nz=3.0, c=K.cuts(6, 4))
    m = P.m(lid)
    n0 = len(m.bm.verts)
    K.lathe(P, lid, [(Rj + 0.002, H - 0.012), (Rj + 0.012, H - 0.018), (Rj + 0.009, H), (Rj + 0.002, H + 0.004)],
            segs=K.cuts(24, 16), closed=False)
    for v in C.new_verts(m, n0):   # 布の裾を波打たせる
        a = math.atan2(v.co.y, v.co.x)
        if v.co.z < H - 0.005:
            v.co.z += 0.004 * math.sin(a * 7)
    K.ring(P, "hemp", (0, 0, H - 0.008), Rj + 0.003, 0.0025, n=32)
    K.tube(P, "hemp", [(Rj + 0.003, 0, H - 0.008), (Rj + 0.012, 0.004, H - 0.02), (Rj + 0.014, 0.0, H - 0.03)], 0.0022, sides=5)
    P.mark("top", (0, 0, H + 0.014))
    P.finish(fuzz=0.001)


def pellet_sack(name, colors, stamp="felt_red", seed=0):
    """麻袋: 口を外に折り返し、粒の山に木の匙を挿す。前にフェルトの丸いしるし"""
    P = K.Parts(name, kind="pellets")
    rnd = random.Random(seed)
    m = P.m("hemp")
    n0 = len(m.bm.verts)
    prof = [(0.0, 0.0), (0.07, 0.0), (0.09, 0.015), (0.098, 0.06), (0.095, 0.12), (0.085, 0.17), (0.088, 0.18)]
    K.lathe(P, "hemp", prof, segs=K.cuts(32, 20), closed=False)
    for v in C.new_verts(m, n0):   # 中身の重みで、ふくらみがむらになる
        a = math.atan2(v.co.y, v.co.x)
        k = 1 + 0.05 * math.sin(a * 3 + seed) * min(1, v.co.z / 0.06) + 0.03 * math.sin(a * 5 + 1.3)
        v.co.x *= k
        v.co.y *= k
    K.lathe(P, "hemp", [(0.088, 0.18), (0.1, 0.185), (0.104, 0.16), (0.1, 0.15)], segs=K.cuts(32, 20), closed=False)   # 折り返し
    K.ring(P, "hemp", (0, 0, 0.183), 0.096, 0.007, n=32)
    pellet_mound(P, colors, (0, 0, 0.15), 0.08, 0.04, 22 if EX else 34, seed=seed + 2, r=0.012, core=colors[0])
    # 匙: 木の小さな器と柄
    K.lathe(P, "wood_light", [(0.0, 0.0), (0.02, 0.002), (0.028, 0.016), (0.026, 0.018), (0.018, 0.006), (0.0, 0.004)],
            center=(0.025, 0.01, 0.19), segs=16, rot=(0.7, "Y"))
    K.dowel(P, "wood_light", (0.035, 0.01, 0.2), (0.1, 0.01, 0.27), 0.006, 8)
    # しるし
    sm = P.m(stamp)
    s0 = len(sm.bm.verts)
    RS = 0.106   # 袋の胴の丸みにそって曲げる
    K.extrude(P, stamp, K.circle_poly(0.028, 20), 0.0, 0.003, plane="XZ", offset=(0, RS, 0.085))
    for v in C.new_verts(sm, s0):
        v.co.y = math.sqrt(RS ** 2 - v.co.x ** 2) + (v.co.y - RS)
    K.stitch_line(P, "thread", [(0.02 * math.cos(a), math.sqrt((RS + 0.004) ** 2 - (0.02 * math.cos(a)) ** 2),
                                 0.085 + 0.02 * math.sin(a)) for a in [2 * math.pi * k / 24 for k in range(25)]],
                  r=0.0016, dash=0.007)
    P.mark("top", (0, 0, 0.19))
    P.finish(fuzz=0.0012)


def pellet_bag(name, sticker="felt_red", colors=None):
    """レジで買った紙袋: 口を 2 回折り、赤いフェルトのシールで留める。横に粒がこぼれる"""
    P = K.Parts(name, kind="pellets")
    P.hard["paper_kraft"] = 0.003
    K.box(P, "paper_kraft", (0, 0, 0.055), (0.09, 0.055, 0.11))
    K.box(P, "paper_kraft", (0, -0.002, 0.112), (0.092, 0.05, 0.012), rot=(0.25, "X"))
    K.box(P, "paper_kraft", (0, -0.008, 0.12), (0.092, 0.04, 0.01), rot=(0.5, "X"))
    for z in (0.02, 0.1):   # 折り目
        K.box(P, "paper_kraft", (0, 0.0281, z), (0.088, 0.001, 0.002))
    K.disc(P, sticker, (0, 0.03, 0.105), 0.016, 0.004, axis="Y", segs=16)
    K.stitch_ring(P, "thread", (0, 0.033, 0.105), 0.011, r=0.0012, axis="Y", dash=0.005)
    rnd = random.Random(2)
    for k, (x, y) in enumerate(((0.07, 0.03), (0.085, 0.0), (0.06, 0.05))):
        pellet(P, (colors or PELLET["mix"])[k % len(colors or PELLET["mix"])], (x, y, 0.009), 0.01, rnd)
    P.mark("top", (0, 0, 0.13))
    P.finish(fuzz=0.001)


def pellet_tray(name):
    """仕分けの盆: 木の盆を 3 × 2 に仕切り、色ごとに粒を盛る"""
    P = K.Parts(name, kind="pellets")
    P.hard["wood"] = 0.003
    W, D = 0.3, 0.2
    K.extrude(P, "wood", K.round_rect(W, D, 0.02), 0.0, 0.01)
    rim = K.round_rect(W, D, 0.02)
    K.tube(P, "wood", [(x, y, 0.022) for x, y in rim + rim[:1]], 0.008, sides=6)
    for x in (-W / 6, W / 6):
        K.box(P, "wood", (x, 0, 0.02), (0.008, D - 0.01, 0.02))
    K.box(P, "wood", (0, 0, 0.02), (W - 0.01, 0.008, 0.02))
    keys = ["mix", "red", "green", "yellow", "brown", "mix"]
    for i in range(6):
        cx = -W / 3 + (i % 3) * W / 3
        cy = D / 4 - (i // 3) * D / 2
        pellet_mound(P, PELLET[keys[i]], (cx, cy, 0.01), 0.035, 0.018, 9 if EX else 12, seed=10 + i, r=0.0095)
    P.mark("top", (0, 0, 0.03))
    P.finish(fuzz=0.001)


# ---------------------------------------------------------------- 組む
work_table("work_table_moss", "felt_moss")
work_table("work_table_indigo", "felt_indigo")
work_table("work_table_rust", "felt_rust")
press_board("press_board", "patch_warm", "felt_red")
press_board("press_board_cool", "patch_cool", "felt_sky")
heat_press("heat_press", "felt_red")
heat_press("heat_press_mustard", "felt_mustard")
table_dryer("table_dryer", "felt_cream", "felt_navy2", "felt_red")
table_dryer("table_dryer_red", "felt_red", "felt_ivory", "felt_mustard")
giant_press_board("giant_press_board", "patch_warm", "felt_red")
giant_press_board("giant_press_board_cool", "patch_cool", "felt_sky")
giant_heat_press("giant_heat_press", "felt_red")
giant_heat_press("giant_heat_press_mustard", "felt_mustard")
giant_dryer("giant_dryer", "felt_cream", "felt_navy2", "felt_red")
giant_dryer("giant_dryer_red", "felt_red", "felt_ivory", "felt_mustard")
pellet_jar("pellet_jar_mix", PELLET["mix"], "felt_red", 1)
pellet_jar("pellet_jar_red", PELLET["red"], "felt_ivory", 2)
pellet_jar("pellet_jar_green", PELLET["green"], "felt_mustard", 3)
pellet_jar("pellet_jar_yellow", PELLET["yellow"], "felt_indigo", 4)
pellet_sack("pellet_sack_mix", PELLET["mix"], "felt_red", 1)
pellet_sack("pellet_sack_green", PELLET["green"], "felt_indigo", 2)
pellet_sack("pellet_sack_brown", PELLET["brown"], "felt_mustard", 3)
pellet_bag("pellet_bag")
pellet_tray("pellet_tray")

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    T = 0.47
    place = {"work_table_moss": (-1.0, 0, 0), "work_table_indigo": (0.0, 0, 0), "work_table_rust": (1.0, 0, 0),
             "press_board": (-1.2, 0.0, T), "pellet_jar_mix": (-0.78, 0.1, T), "pellet_bag": (-0.85, -0.12, T),
             "heat_press": (-0.15, 0.0, T), "pellet_tray": (0.2, 0.02, T),
             "table_dryer": (0.82, 0.0, T), "table_dryer_red": (1.18, 0.0, T),
             "press_board_cool": (-1.0, 1.0, 0), "heat_press_mustard": (-0.55, 1.0, 0),
             "pellet_jar_red": (-0.2, 1.0, 0), "pellet_jar_green": (-0.08, 1.0, 0), "pellet_jar_yellow": (0.04, 1.0, 0),
             "pellet_sack_mix": (0.35, 1.0, 0), "pellet_sack_green": (0.6, 1.0, 0), "pellet_sack_brown": (0.85, 1.0, 0)}
    place.update({"giant_press_board": (4.2, 0.55, 0), "giant_heat_press": (6.3, 0.45, 0), "giant_dryer": (8.4, 0.5, 0)})
    for n, (x, y, z) in place.items():
        R[n].location = (x, y, z)
    R["giant_press_board"].rotation_euler = (0, 0, math.radians(90))
    for n in ("giant_press_board_cool", "giant_heat_press_mustard", "giant_dryer_red"):
        for o in [R[n]] + K.descendants(R[n]):
            o.hide_render = True
    ref = C.M("person_ref", "felt_beige", "stage")   # 人の大きさの目安（背 1.7 m ＝ 2 倍する前は 0.85）
    C.superellipsoid(ref, (5.3, 1.3, 0.425), (0.17, 0.17, 0.425), n_xy=2.0, n_z=2.0, cuts=6)
    ref.done()
    K.room(floor_size=20.0, wall_y=-0.6)
    K.interior_light(0.5)
    cams = {
        "all": ((0.3, 3.6, 1.6), (0.0, 0.4, 0.4), 30),
        "press": ((-1.5, 0.6, 0.8), (-1.15, 0.0, 0.52), 40),
        "hpress": ((0.05, 0.6, 0.75), (-0.12, 0.0, 0.56), 40),
        "dryer": ((0.95, 0.75, 0.75), (1.0, 0.0, 0.58), 40),
        "pellets": ((0.2, 1.75, 0.45), (0.25, 1.0, 0.1), 40),
        "giant": ((6.4, 6.4, 2.0), (6.3, 0.5, 0.6), 26),
        "giant_press": ((3.0, 2.6, 1.4), (4.2, 0.5, 0.5), 30),
        "giant_dryer": ((7.4, 3.4, 1.3), (8.4, 0.5, 0.85), 30),
    }
    K.render_views(A, cams)
