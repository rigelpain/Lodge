"""紙細工屋さんのエレガントなテントの案（2026-11-04 代表「紙細工士さんはエレガントなテントで営業させよう。プレイキャラが近くにいないときはテントの入口を閉めてる感じで」）。
素材は婦人と同じ紙（roughs.py の roles: 墨のクレープ紙・金と朱の花の紙・朱の和紙・真鍮）。形も婦人の持ち物と、売る物（提灯）から借りる:
  A  墨のドレスの天幕   婦人の裾をそのまま天幕にした形。ひだの屋根、花の紙の波の飾り幕。閉じると幕の上が胸の V のように朱をのぞかせ、開くと左右へ寄せて朱の紐で留める
  B  蛇の目の大傘       花の紙と朱の和紙を張った大きな和傘を屋根に。幕は墨と花の紙の蛇腹で、屏風のように左右へ畳む
  C  提灯の天幕         売り物の提灯を大きくした形。竹の骨に和紙を張り、中の灯りで薄く光る。入口は提灯の蛇腹が上へ畳まれて開く
  D  和紙のドレスの天幕 A の形と飾りのまま、全部を和紙に。花の紙も生成りの地（代表「A いい。C の和紙もすき。形と意匠がないのが微妙なだけ」）
  E  墨の屋根の和紙の天幕 A の形のまま、屋根と飾り幕と垂れは墨、壁と幕は光る和紙

代表は E を選んだ（2026-11-04）。絵は design/paper-lady-tent/00-proposals.jpg。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/kamizaiku/tent_ideas.py -- --out DIR --what A --open 0
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/kamizaiku/tent_ideas.py -- --export game/props/paper_lady --part body|curtain

--export: ゲーム用の glb。body は paper_tent.glb（幕を除くテント）、curtain は paper_tent_curtain.glb（前の幕の絵。平らな板 2 枚で、幕の形はゲームの paper_tent.gd が作る）

寸法はゲームの大きさ (m)。原点はテントの真ん中の床、前は +Y（glb を Godot で 180° 回すと婦人の正面 +Z）。-X が婦人の左手（スタンドの側）
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ROUGHS = os.path.join(HERE, "roughs.py")

ap = argparse.ArgumentParser()
ap.add_argument("--out", default="")
ap.add_argument("--what", default="A")
ap.add_argument("--open", type=float, default=0.0)
ap.add_argument("--tris", type=int, default=9000)
ap.add_argument("--export", default="", help="ゲーム用の glb をこのフォルダーに書き出す")
ap.add_argument("--part", default="body", choices=("body", "curtain"))
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

src = open(ROUGHS, encoding="utf-8").read()
ns = {"__file__": ROUGHS, "__name__": "borrowed"}
_argv = sys.argv
sys.argv = ["blender"]
exec(compile(src[:src.index("if A.motion:")], ROUGHS, "exec"), ns)
sys.argv = _argv
C, V, part, rope, roles, tassel_src = ns["C"], ns["V"], ns["part"], ns["rope"], ns["roles"], None
facet_ball = ns["facet_ball"]
_node, _export_tree = ns["_node"], ns["_export_tree"]

# 案ごとの素材: 屋根・壁・前の幕・飾り幕と垂れと裾の花の紙
PAL = {"A": ("crepe", "crepe", "crepe_lt", "flowers"),
       "D": ("washi_white", "washi_white", "washi_white", "flowers_washi"),
       "E": ("crepe", "washi_white", "washi_white", "flowers")}
P = PAL["E"] if A.export else PAL.get(A.what, PAL["A"])

RX, RY = 1.68, 1.15      # テントの床の楕円の半径（x, y）
E = 50.0                 # 入口の開きの半分の角度（前から左右へ）
EAVE = 2.82              # 軒の高さ
RAIL = 2.5               # 幕の上の縁


def pl(th, k=1.0, z=0.0):
    """楕円の上の点。th は度（90 が前）、k は楕円の何倍か"""
    a = math.radians(th)
    return V(math.cos(a) * RX * k, math.sin(a) * RY * k, z)


def grid(m, rows, loop=False):
    vs = [[m.bm.verts.new(p) for p in r] for r in rows]
    for a, b in zip(vs, vs[1:]):
        for i in range(len(a) - 1):
            m.bm.faces.new((a[i], b[i], b[i + 1], a[i + 1]))
        if loop:
            m.bm.faces.new((a[-1], b[-1], b[0], a[0]))


def sheet(name, role, rows, loop=False, smooth=False, solid=0.0):
    return part(name, role, lambda m: grid(m, rows, loop), smooth=smooth, solid=solid)


def stick_arc(name, role, pts, r=0.012, sides=5):
    return part(name, role, lambda m: C.tube(m, pts, r, sides=sides), smooth=False)


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def finial(z, h=0.5):
    stick_arc("finial_rod", "brass", [V(0, 0, z - 0.1), V(0, 0, z + h)], 0.016, 8)
    part("finial_b1", "brass", lambda m: facet_ball(m, V(0, 0, z + 0.04), (0.075, 0.075, 0.06), 10, 6, 0.0, 3), smooth=True)
    part("finial_b2", "brass", lambda m: facet_ball(m, V(0, 0, z + h * 0.62), (0.04, 0.04, 0.05), 10, 6, 0.0, 4), smooth=True)
    part("finial_b3", "brass", lambda m: facet_ball(m, V(0, 0, z + h), (0.024, 0.024, 0.04), 8, 5, 0.0, 5), smooth=True)


def tassel(name, top, L=0.26, role="washi_red", cap="brass"):
    part(name + "_head", cap, lambda m: facet_ball(m, top, (0.024, 0.024, 0.028), 8, 5, 0.0, 9), smooth=True)
    def b(m):
        n = 12
        rows = []
        for z, r in ((0.0, 0.016), (0.05, 0.026), (L, 0.05)):
            rows.append([top + V(math.cos(2 * math.pi * i / n) * r, math.sin(2 * math.pi * i / n) * r, -z - 0.02) for i in range(n)])
        grid(m, rows, loop=True)
    part(name, role, b, smooth=False)


# ---------------------------------------------------------------- A 墨のドレスの天幕
def roof_a():
    prof = [(0.03, 4.25), (0.07, 4.0), (0.13, 3.75), (0.23, 3.5), (0.38, 3.27), (0.58, 3.07), (0.8, 2.92), (0.97, 2.82), (1.05, 2.72)]
    n = 112
    rows = [[pl(360.0 * i / n, k * (1.0 + (0.014 if i % 2 else -0.006)) , z) for i in range(n)] for k, z in prof]
    sheet("roof", P[0], rows, loop=True)
    for i in range(14):   # 真鍮の細い骨: てっぺんから軒へ
        th = 360.0 * (i + 0.5) / 14
        stick_arc("rib", "brass", [pl(th, k * 1.018, z + 0.006) for k, z in prof[1:]], 0.009)
    finial(4.2)
    # 花の紙の波の飾り幕と、波の先の朱の房
    peaks = 22
    def wave(th):
        return abs(math.sin(math.radians(th) * peaks / 2))
    rows = []
    n = peaks * 8
    for f in (0.0, 0.4, 0.75, 1.0):
        rows.append([pl(360.0 * i / n, 1.05 + 0.005 * f, 2.78 - f * (0.27 + 0.13 * wave(360.0 * i / n))) for i in range(n)])
    sheet("valance", P[3], rows, loop=True)
    rows = []
    for f in (0.97, 1.0):
        rows.append([pl(360.0 * i / n, 1.058, 2.78 - f * (0.27 + 0.13 * wave(360.0 * i / n)) - (f - 0.97) * 0.8) for i in range(n)])
    sheet("valance_edge", "washi_red", rows, loop=True)
    for i in range(peaks):
        th = 360.0 * (i + 0.5) * 2 / (peaks * 2) 
        tassel("v_tassel", pl(th, 1.058, 2.38), 0.13)


def wall_a():
    n = 64
    a0, a1 = 90.0 + E, 450.0 - E
    rows = []
    for z, k in ((2.72, 1.0), (1.8, 1.0), (0.8, 1.01), (0.25, 1.03), (0.0, 1.05)):
        rows.append([pl(a0 + (a1 - a0) * i / n, k * (1.0 + (0.012 if i % 2 else -0.004)), z) for i in range(n + 1)])
    sheet("wall", P[1], rows)
    # 上がけ: 婦人の裾と同じ、花の紙の尖った垂れを二段に（入口の左右と横と後ろ）
    for tier, (top, cor, tip, span, cnt) in enumerate(((2.6, 1.45, 0.95, 28.0, 10), (2.65, 2.05, 1.72, 22.0, 13))):
        for j in range(cnt):
            c = a0 + (a1 - a0) * (j + 0.5) / cnt
            rows = []
            for z, w in ((top, span / 2), (cor, span / 2), (tip, 0.0)):
                rows.append([pl(c + w * (-1 + 2 * i / 6), 1.03 + tier * 0.012 + 0.006 * math.cos(i * 1.05), z) for i in range(7)])
            sheet("flap", P[3], rows)


def curtain_a(s, e):
    """前の幕（s=1 が -X でなく +X の側。th は 90 から離れる側）。e=0 閉じる、1 開く。外は墨、内は朱の紙。閉じると上の真ん中が V にあいて朱がのぞく"""
    cols, hs = 28, 9
    def pt(u, f, inset):
        # u=0 柱の側、1 真ん中の側。f=0 上、1 裾
        z = RAIL + 0.03 - f * (RAIL + 0.01)
        tie = math.exp(-((z - 1.05) / 0.5) ** 2) * e        # 留める高さの所は余計に寄る
        span_c = E + 0.8
        span_o = 13.0 * (1.0 - 0.55 * tie)
        span = span_c + (span_o - span_c) * e
        th = 90.0 + s * (E - u * span)
        amp = 0.012 + 0.05 * e
        folds = 7
        k = 1.03 - inset + amp * math.sin(u * folds * 2 * math.pi) * (0.6 + 0.4 * f)
        return pl(th, k, z)
    def v_top(u):   # 閉じたときの V: 真ん中の上を切る
        return 0.62 * smooth(0.62, 1.0, u)
    # 外の墨の幕
    rows = []
    for j in range(hs + 1):
        f = j / hs
        row = []
        for i in range(cols + 1):
            u = i / cols
            cut = v_top(u) / (RAIL + 0.01)
            row.append(pt(u, cut + (1 - cut) * f, 0.0))
        rows.append(row)
    sheet("curtain", P[2], rows)
    # 内の朱の紙（V の所にも通る）
    rows = [[pt(i / cols, j / hs, 0.014) for i in range(cols + 1)] for j in range(hs + 1)]
    sheet("lining", "washi_red", rows)
    # 花の紙の裾の帯。上の縁はぎざぎざに
    rows = []
    for f0 in (0.0, 1.0):
        row = []
        for i in range(cols + 1):
            u = i / cols
            top = 0.74 + 0.05 * (1 if i % 4 < 2 else -1)
            row.append(pt(u, top + (1.0 - top) * f0, -0.006))
        rows.append(row)
    sheet("hem", P[3], rows)
    # 金の縁（V と真ん中の縁）
    edge = [pt(1.0, f / 8.0 * (1 - 0.62 / 2.5) + 0.62 / 2.5, -0.01) for f in range(9)]
    stick_arc("edge", "brass", edge, 0.006)
    # 朱の紐と房: 開くと幕を束ね、閉じると柱に垂れる
    jamb = pl(90.0 + s * E, 1.045, 1.05)
    if e > 0.5:
        loop = [pt(u / 8.0, (RAIL + 0.03 - 1.05) / (RAIL + 0.01), -0.05) for u in range(9)]
        rope("tie", "washi_red", loop, r=0.014, sides=6)
        tassel("tie_t", loop[-1] + V(0, 0.03, -0.02), 0.2)
    else:
        rope("tie", "washi_red", [jamb + V(0, 0, 0.1), jamb + V(0, 0.02, -0.1)], r=0.012, sides=6)
        tassel("tie_t", jamb + V(0, 0.02, -0.12), 0.2)


def build_a(e):
    roof_a()
    wall_a()
    for s in (1, -1):
        stick_arc("jamb", "brass", [pl(90.0 + s * E, 1.02, 0.0), pl(90.0 + s * E, 1.02, RAIL + 0.15)], 0.016, 8)
        curtain_a(s, e)
    rail = [pl(90 - E + 2 * E * i / 24, 1.035, RAIL + 0.02) for i in range(25)]
    stick_arc("rail", "brass", rail, 0.012)


# ---------------------------------------------------------------- B 蛇の目の大傘
def canopy_b():
    ribs = 44
    n = ribs * 2
    def z_of(k, i):
        sag = 0.012 * (0 if i % 2 == 0 else 1) * min(1.0, k * 2)
        return 4.42 - 1.52 * k ** 1.1 - sag
    def k_of(k, i):
        return k * (1.0 - (0.012 if i % 2 else 0.0) * k)
    def ring(name, role, k0, k1):
        ks = [k0 + (k1 - k0) * j / 3 for j in range(4)]
        rows = [[pl(360.0 * i / n, k_of(k, i), z_of(k, i)) for i in range(n)] for k in ks]
        sheet(name, role, rows, loop=True)
    ring("cap", "sumi", 0.01, 0.15)
    ring("red", "washi_red", 0.15, 0.55)
    ring("white", "washi_white", 0.55, 0.68)
    ring("flowers", "flowers", 0.68, 1.1)
    # 骨: 傘の裏の細い竹。外から見える先だけ少し出す。糸のかがりの輪
    for i in range(ribs):
        th = 360.0 * i / ribs
        stick_arc("rib", "wood_dark", [pl(th, k, z_of(k, 0) - 0.012) for k in (0.1, 0.5, 0.9, 1.115)], 0.009)
    for k, role in ((0.15, "brass"), (0.55, "brass"), (1.1, "wood_dark")):
        stick_arc("thread", role, [pl(360.0 * i / n, k_of(k, 0), z_of(k, 0) + 0.004) for i in range(n + 1)], 0.008)
    finial(4.38, 0.34)


def strips_b(e):
    # 壁: 墨のクレープ紙の下地に、墨と花の紙の短冊を交互に
    n = 64
    a0, a1 = 90.0 + E, 450.0 - E
    rows = []
    for z, k in ((2.92, 0.98), (1.5, 0.99), (0.0, 1.01)):
        rows.append([pl(a0 + (a1 - a0) * i / n, k, z) for i in range(n + 1)])
    sheet("wall", "crepe", rows)
    cnt = 22
    for j in range(cnt):
        c0 = a0 + (a1 - a0) * j / cnt
        c1 = a0 + (a1 - a0) * (j + 1) / cnt
        role = "flowers" if j % 2 else "sumi"
        rows = []
        for z, k in ((2.92, 1.0), (1.5, 1.01), (0.02, 1.03)):
            rows.append([pl(c0 + (c1 - c0) * i / 3, k + 0.012 * (1 if i in (1, 2) else 0), z) for i in range(4)])
        sheet("strip", role, rows)


def bellows_b(s, e):
    """前の幕: 墨と花の紙の板をつないだ蛇腹。開くと屏風のように柱へ畳む"""
    panels = 8
    top = 2.74
    span = (E + 0.5) + (9.0 - (E + 0.5)) * e
    amp = 0.012 + 0.11 * e
    for j in range(panels):
        u0, u1 = j / panels, (j + 1) / panels
        def p(u, zig, z):
            th = 90.0 + s * (E - u * span)
            return pl(th, 1.02 + amp * zig, z)
        z0, z1 = (1 if j % 2 else -1), (-1 if j % 2 else 1)
        rows = []
        for z in (top, 0.02):
            rows.append([p(u0, z0, z), p(u1, z1, z)])
        sheet("fold", "flowers" if j % 2 else "sumi", rows, solid=0.004)
        rope("fold_edge", "brass", [p(u1, z1, top), p(u1, z1, 0.02)], r=0.005, sides=4)
    tassel("fold_t", pl(90.0 + s * (E - span), 1.04, 1.25), 0.22)


def build_b(e):
    canopy_b()
    strips_b(e)
    for s in (1, -1):
        stick_arc("jamb", "brass", [pl(90.0 + s * E, 1.02, 0.0), pl(90.0 + s * E, 1.02, 2.95)], 0.016, 8)
        bellows_b(s, e)
    stick_arc("rail", "brass", [pl(90 - E + 2 * E * i / 24, 1.03, 2.76) for i in range(25)], 0.012)


# ---------------------------------------------------------------- C 提灯の天幕
BULGE = [(0.0, 0.92), (0.3, 0.97), (0.8, 1.0), (1.4, 1.03), (2.0, 1.0), (2.5, 0.88), (2.9, 0.72), (3.2, 0.54), (3.42, 0.36)]


def kz(z):
    for (z0, k0), (z1, k1) in zip(BULGE, BULGE[1:]):
        if z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3 - 2 * t) * 0.3 + t * 0.7
            return k0 + (k1 - k0) * t
    return BULGE[-1][1]


DOOR = 2.42   # 入口の上の高さ


def skin_c(e):
    hoop = 0.16
    n = 96
    zs = []
    z = 0.12
    while z < 3.42:
        zs.append(z)
        z += hoop
    zs.append(3.42)
    def lift(z, th):
        """入口の幅の所は、開くと DOOR より下の皮が上へ畳まれる"""
        d = abs(((th - 90.0 + 180.0) % 360.0) - 180.0)
        if d >= E or z >= DOOR:
            return z
        return z + (DOOR + (z - DOOR) * 0.12 - z) * e
    rows = []
    for a, b in zip(zs, zs[1:]):
        for f, inset in ((0.0, 0.012), (0.5, -0.006), (1.0, 0.012)):
            zz = a + (b - a) * f
            rows.append([pl(360.0 * i / n + 0.0, kz(lift(zz, 360.0 * i / n)) * (1.0 - inset), lift(zz, 360.0 * i / n)) for i in range(n)])
    sheet("skin", "washi_white", rows, loop=True, smooth=True)
    for z in zs:
        pts = [pl(360.0 * i / 48, kz(lift(z, 360.0 * i / 48)) * 1.002, lift(z, 360.0 * i / 48)) for i in range(49)]
        stick_arc("bamboo", "wood_dark", pts, 0.009, 3)
    # 口輪: てっぺんと裾の黒い輪、裾の花の紙の帯
    n2 = 72
    rows = [[pl(360.0 * i / n2, k, z) for i in range(n2)] for k, z in ((0.02, 3.8), (0.22, 3.8), (0.46, 3.66), (0.5, 3.34), (0.47, 3.28))]
    sheet("crown", "sumi", rows, loop=True)
    finial(3.78, 0.38)
    a0, a1 = 90.0 + E, 450.0 - E
    rows = [[pl(a0 + (a1 - a0) * i / 60, kz(z) * 1.012, z) for i in range(61)] for z in (0.0, 0.14, 0.42, 0.48)]
    sheet("foot_flowers", "flowers", rows)
    rows = [[pl(a0 + (a1 - a0) * i / 60, kz(z) * 1.018, z) for i in range(61)] for z in (0.46, 0.5)]
    sheet("foot_line", "washi_red", rows)
    # 動く裾（入口の幅）: 開くと一緒に上がる
    zb = lift(0.1, 90.0)
    rows = [[pl(90.0 - E + 2 * E * i / 24, kz(zb + d) * 1.016, zb + d) for i in range(25)] for d in (-0.1 + 0.1 * e, 0.02)]
    sheet("door_rail", "sumi", rows)
    for s in (1, -1):
        stick_arc("jamb", "brass", [pl(90.0 + s * E, kz(0) * 1.012, 0.0), pl(90.0 + s * E, kz(1.2) * 1.012, 1.2), pl(90.0 + s * E, kz(DOOR) * 1.012, DOOR + 0.1)], 0.014, 8)
    if e < 0.5:
        tassel("door_t", pl(90.0, kz(0.2) * 1.03, 0.62), 0.22)


def build_c(e):
    skin_c(e)


def washi_flowers():
    """婦人の花の紙の地（墨）を、生成りの和紙の色に替えた紙"""
    import numpy as np
    base = ns["flower_image"]()
    w, h = base.size
    px = np.array(base.pixels[:], dtype=np.float32).reshape(h, w, 4)
    q = np.round(px[:, :, :3] * 64).astype(np.int32)
    keys, cnt = np.unique(q[:, :, 0] * 10000 + q[:, :, 1] * 100 + q[:, :, 2], return_counts=True)
    ground = keys[np.argmax(cnt)]
    mask = (q[:, :, 0] * 10000 + q[:, :, 1] * 100 + q[:, :, 2]) == ground
    px[mask, 0], px[mask, 1], px[mask, 2] = 0.855, 0.807, 0.716   # 生成り（EEE8DC の線形の値）
    img = bpy.data.images.new("flowers_washi", w, h)
    img.colorspace_settings.name = base.colorspace_settings.name
    img.pixels[:] = px.ravel()
    img.pack()
    C._MAT["flowers_washi"] = ns["print_paper"]("flowers_washi", img, 1.3, back="EEE8DC", fiber=0.5)


BUILDS = {"A": build_a, "B": build_b, "C": build_c, "D": build_a, "E": build_a}


CURTAIN_W, CURTAIN_H = 1.62, RAIL + 0.01   # 前の幕の片側の布の大きさ (m)。ゲームの paper_tent.gd の u・f の 0〜1 に当たる


def flat(name, role, rows_uf, depth):
    """布の座標 (u, f) の列を、平らな板に（前は -Y）"""
    rows = [[V(u * CURTAIN_W, -depth, CURTAIN_H * (1.0 - f)) for u, f in row] for row in rows_uf]
    return sheet(name, role, rows)


def bake_flat(K, low, highs, role, size):
    """highs の色と凹凸を、low の決まった UV のまま 1 枚の画像へ（kit._bake_to の UV を作らない形）"""
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.95
    low.data.materials.clear()
    low.data.materials.append(m)
    out = {}
    for kind in ("DIFFUSE", "NORMAL"):
        img = bpy.data.images.new("%s_%s" % (low.name, kind.lower()), size, size, alpha=False)
        if kind == "NORMAL":
            img.colorspace_settings.name = "Non-Color"
        node = m.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        m.node_tree.nodes.active = node
        bpy.ops.object.select_all(action="DESELECT")
        for h in highs:
            h.select_set(True)
        low.select_set(True)
        bpy.context.view_layer.objects.active = low
        kw = dict(use_selected_to_active=True, cage_extrusion=0.02, max_ray_distance=0.05, use_clear=True)
        if kind == "DIFFUSE":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, **kw)
        else:
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", **kw)
        img.pack()
        out[kind] = (node, img)
    m.node_tree.links.new(out["DIFFUSE"][0].outputs["Color"], b.inputs["Base Color"])
    nm = m.node_tree.nodes.new("ShaderNodeNormalMap")
    m.node_tree.links.new(out["NORMAL"][0].outputs["Color"], nm.inputs["Color"])
    m.node_tree.links.new(nm.outputs["Normal"], b.inputs["Normal"])


def export_curtain(K, folder):
    """前の幕の絵: 和紙に花の紙の裾（上の縁はぎざぎざ）、真ん中の縁に金の線。裏の朱の和紙は別の板"""
    root = _node("paper_tent_curtain", None, V(0, 0, 0))
    grid_uf = lambda n=2: [[(i / n, j / n) for i in range(n + 1)] for j in range(n + 1)]
    base = flat("c_base", "washi_white", grid_uf(), 0.001)
    cols = 28
    def zig(i):
        return 0.74 + 0.05 * (1 if i % 4 < 2 else -1)
    hem = flat("c_hem", "flowers", [[(i / cols, zig(i)) for i in range(cols + 1)], [(i / cols, 1.0) for i in range(cols + 1)]], 0.003)
    gold = flat("c_gold", "washi_ochre", [[(0.988, 0.0), (1.0, 0.0)], [(0.988, 1.0), (1.0, 1.0)]], 0.004)
    red = flat("c_red", "washi_red", grid_uf(), 0.001)
    red.location.x = 4.0
    bpy.context.view_layer.update()
    K._cycles()
    highs = {"curtain_outer": [base, hem, gold], "curtain_lining": [red]}
    lows = []
    for name, hs in highs.items():
        off = hs[0].location.x
        def low_build(m):
            vs = [m.bm.verts.new(V(off + x * CURTAIN_W, 0.0, CURTAIN_H * (1.0 - f))) for x, f in ((0, 0), (0, 1), (1, 1), (1, 0))]
            m.bm.faces.new(vs)
        low = part(name, "washi_white", low_build, smooth=False)
        while low.data.uv_layers:   # 形の道具が作る空の層は捨てる（残すと、そちらへ焼いてしまう）
            low.data.uv_layers.remove(low.data.uv_layers[0])
        uv = low.data.uv_layers.new(name="UVMap")
        for lp in low.data.loops:
            co = low.data.vertices[lp.vertex_index].co
            uv.data[lp.index].uv = ((co.x - off) / CURTAIN_W, co.z / CURTAIN_H)
        for h in hs:
            h.data.materials[0] = h.active_material.copy()
            K._grime(h.active_material)
        bake_flat(K, low, hs, "paper_curtain", 1024 if name == "curtain_outer" else 256)
        low.parent = root
        lows.append(low)
    for o in [base, hem, gold, red]:
        bpy.data.objects.remove(o)
    C.export([root] + lows, os.path.join(folder, "paper_tent_curtain.glb"), root)


def export_body(K, folder):
    """幕を除くテント: 屋根・飾り幕・壁・垂れ・柱・竿と、柱に掛けた朱の紐と房"""
    before = set(bpy.data.objects)
    roof_a()
    wall_a()
    for s in (1, -1):
        stick_arc("jamb", "brass", [pl(90.0 + s * E, 1.02, 0.0), pl(90.0 + s * E, 1.02, RAIL + 0.15)], 0.016, 8)
        jamb = pl(90.0 + s * E, 1.045, 1.05)
        rope("tie", "washi_red", [jamb + V(0, 0, 0.1), jamb + V(0, 0.02, -0.1)], r=0.012, sides=6)
        tassel("tie_t", jamb + V(0, 0.02, -0.12), 0.2)
    stick_arc("rail", "brass", [pl(90 - E + 2 * E * i / 24, 1.035, RAIL + 0.02) for i in range(25)], 0.012)
    objs = list(set(bpy.data.objects) - before)
    root = _node("paper_tent", None, V(0, 0, 0))
    root["tris"] = A.tris
    for o in objs:
        o.parent = root
    _export_tree(K, root, [], os.path.join(folder, "paper_tent.glb"), "paper_tent")


def main():
    import kit as K
    K.BAKE["max"] = 2048
    C.reset()
    C.LOOK["v"] = "day"
    C.NOFUZZ["v"] = True
    K.S["scale"] = 1.0
    roles()
    washi_flowers()
    if A.export:
        os.makedirs(A.export, exist_ok=True)
        (export_body if A.part == "body" else export_curtain)(K, A.export)
        return
    before = set(bpy.data.objects)
    BUILDS[A.what](A.open)
    objs = list(set(bpy.data.objects) - before)
    root = _node("tent_" + A.what, None, V(0, 0, 0))
    root["tris"] = A.tris
    for o in objs:
        o.parent = root
    os.makedirs(A.out, exist_ok=True)
    _export_tree(K, root, [], os.path.join(A.out, "tent_%s_%d.glb" % (A.what, round(A.open * 10))), "paper_tent")


main()
