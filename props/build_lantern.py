"""持ち歩くランタン（装備）を Blender で組む。帯に提げて、持ち主のまわりを照らす。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_lantern.py -- --views quarter,close --prefix props/renders/40-lantern

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_lantern.py -- --look flat --export game/props/lantern

2026-10-29 代表「キャラの周囲を照らすためのランタンをモデリングして装備できるようにしてください」から。
  lantern_box    木の手提げランタン（標準）。木の枠に、フィルムと白い糸の枠の「ガラス」（design/art-concept.md）、
                 毛糸を巻いた取っ手、中に和紙で包んだ灯りと、それを載せる綿
  lantern_paper  和紙の提灯。細い木の骨の輪に紙を張り、上下に濃い木の口。毛糸の紐で提げる
提げる所（取っ手のてっぺん）が原点で、体は下（-Z）。目印: hang（提げる所＝原点）、light（灯りの芯。Godot はここに灯りをともす）。
実寸（m）。ゲームでは人形の大きさに合わせて縮める（game/lantern.gd）。
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）"))])
K.setup(A, fiber=4.0, scale=1.0, tris=2400)


def wrapped_bail(P, role, wrap_role, c, R, r, turns=22):
    """半円の取っ手（XZ の面）。曲げ木の芯に、毛糸をらせんに巻く"""
    arc = []
    for k in range(25):
        a = math.pi * k / 24
        arc.append(Vector((c[0] + R * math.cos(a), c[1], c[2] + R * math.sin(a))))
    K.tube(P, role, arc, r, sides=8)
    helix = []
    n = turns * 8
    for k in range(n + 1):
        t = k / n
        a = math.pi * (0.12 + 0.76 * t)   # 両端は木のまま見せる
        radial = Vector((math.cos(a), 0, math.sin(a)))
        w = 2 * math.pi * turns * t
        p = Vector(c) + radial * R + (radial * math.cos(w) + Vector((0, 1, 0)) * math.sin(w)) * (r + 0.0025)
        helix.append(p)
    K.tube(P, wrap_role, helix, 0.0032, sides=5)


def lantern_box(name):
    P = K.Parts(name, kind="lantern")
    H = 0.07                       # 枠の半分の幅
    zt, zb = -0.10, -0.28          # 枠の上と下
    # 取っ手と、提げる麻ひもの輪
    wrapped_bail(P, "wood_bent", "yarn_red", (0, 0, -0.072), 0.062, 0.0055)
    K.ring(P, "hemp", (0, 0, -0.004), 0.011, 0.0028, axis="Y", n=16)
    # 屋根（四角すい）と煙出し
    K.lathe(P, "wood_dark", [(0.0, -0.062), (0.03, -0.066), (0.108, -0.098), (0.108, -0.104), (0.0, -0.104)],
            segs=4, rot=(math.pi / 4, "Z"))
    K.lathe(P, "wood_dark", [(0.0, -0.05), (0.02, -0.05), (0.022, -0.056), (0.022, -0.068), (0.0, -0.068)], segs=10)
    # 上と下の板、四隅の柱
    K.box(P, "wood", (0, 0, zt - 0.006), (2 * H + 0.02, 2 * H + 0.02, 0.014))
    K.box(P, "wood", (0, 0, zb - 0.012), (2 * H + 0.03, 2 * H + 0.03, 0.026))
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.dowel(P, "wood", (sx * H, sy * H, zb), (sx * H, sy * H, zt), 0.0085, sides=6)
    # 4 面の「ガラス」: 透明なフィルムと、白い糸のなみ縫いの枠（まんなかに横の桟も糸で）
    w = H - 0.006
    zt2, zb2 = zt - 0.016, zb + 0.006
    for k in range(4):
        a = math.pi / 2 * k
        ca, sa = math.cos(a), math.sin(a)

        def at(u, z, d=H - 0.001):
            return (ca * d - sa * u, sa * d + ca * u, z)
        K.box(P, "glass", at(0, (zt2 + zb2) / 2), (0.002 if abs(ca) > 0.5 else 2 * w, 2 * w if abs(ca) > 0.5 else 0.002, zt2 - zb2 + 0.01))
        d = H + 0.0015
        K.stitch_line(P, "thread", [at(-w + 0.008, zt2, d), at(w - 0.008, zt2, d), at(w - 0.008, zb2, d), at(-w + 0.008, zb2, d), at(-w + 0.008, zt2, d)],
                      r=0.0016, dash=0.011)
        zm = (zt2 + zb2) / 2
        K.stitch_line(P, "thread", [at(-w + 0.008, zm, d), at(w - 0.008, zm, d)], r=0.0016, dash=0.011)
    # 中の灯り: 和紙で包んだ芯（光る紙）を、小さな木の皿の綿に載せる
    K.disc(P, "wood_dark", (0, 0, zb + 0.008), 0.034, 0.008, segs=16)
    prof = []
    for j in range(9):
        t = j / 8
        prof.append((0.004 + 0.03 * math.sin(math.pi * t) ** 0.8, zb + 0.03 + 0.085 * t))
    K.lathe(P, "paper", prof, segs=20, closed=False)
    K.ring(P, "thread_red", (0, 0, zb + 0.072), 0.0335, 0.0018, n=20)   # 包んだ紙を赤い糸で結ぶ
    K.blob(P, "cotton", "cotton", [((0.0, 0.0, zb + 0.026), 0.028), ((0.018, 0.008, zb + 0.02), 0.018),
                                    ((-0.016, -0.01, zb + 0.021), 0.018), ((0.004, -0.019, zb + 0.02), 0.015)],
           0.006, lumps=0.1, fuzz=0.004)
    P.mark("hang", (0, 0, 0))
    P.mark("light", (0, 0, zb + 0.072))
    P.finish()


def lantern_paper(name):
    P = K.Parts(name, kind="lantern")
    K.tube(P, "yarn_red", [(0, 0, 0.0), (0, 0, -0.045)], 0.0035, sides=6)   # 提げる毛糸
    K.ring(P, "yarn_red", (0, 0, -0.004), 0.010, 0.003, axis="Y", n=14)
    z0, z1 = -0.055, -0.235
    prof = []
    for j in range(13):
        t = j / 12
        prof.append((0.03 + 0.045 * math.sin(math.pi * t) ** 0.65, z1 + (z0 - z1) * t))
    K.lathe(P, "paper", prof, segs=20, closed=False)
    for j in range(1, 12):   # 骨: 細い木の輪
        K.ring(P, "wood_dark", (0, 0, prof[j][1]), prof[j][0] + 0.0015, 0.0016, n=28)
    for z in (z0 - 0.002, z1 + 0.002):
        K.disc(P, "wood_dark", (0, 0, z), 0.034, 0.014, segs=16)
    K.tube(P, "yarn_red", [(0, 0, z1 - 0.008), (0, 0, z1 - 0.04)], 0.004, sides=6)   # 下の房
    for k in range(6):
        a = 2 * math.pi * k / 6
        K.tube(P, "yarn_red", [(0, 0, z1 - 0.035), (0.008 * math.cos(a), 0.008 * math.sin(a), z1 - 0.07)], 0.0022, sides=4)
    P.mark("hang", (0, 0, 0))
    P.mark("light", (0, 0, (z0 + z1) / 2))
    P.finish()


lantern_box("lantern_box")
lantern_paper("lantern_paper")

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    R["lantern_box"].location = (-0.16, 0, 0.42)
    R["lantern_paper"].location = (0.16, 0, 0.42)
    for r, parts in K.made:   # 灯りの芯に、描くときだけ暖色の灯り
        for o in parts:
            if o.name.startswith("light"):
                L = bpy.data.objects.new("bulb", bpy.data.lights.new("bulb", "POINT"))
                C.coll("stage").objects.link(L)
                L.location = r.location + Vector(o.location)
                L.data.energy = 2
                L.data.color = (1.0, 0.7, 0.42)
                L.data.shadow_soft_size = 0.02
    K.room(floor_size=3.0, wall_y=0.5)
    K.interior_light(0.8)
    cams = {
        "quarter": ((0.55, -0.85, 0.55), (0.0, 0.0, 0.27), 50),
        "front": ((0.0, -1.0, 0.3), (0.0, 0.0, 0.29), 55),
        "close": ((-0.05, -0.45, 0.3), (-0.16, 0.0, 0.25), 60),
    }
    K.render_views(A, cams)
