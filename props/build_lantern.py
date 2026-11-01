"""持ち歩くランタン（装備）を Blender で組む。帯に提げて、持ち主のまわりを照らす。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_lantern.py -- --views quarter,close --prefix props/renders/40-lantern

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_lantern.py -- --sheet --prefix design/lantern-variety/01

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_lantern.py -- --look flat --export game/props/lantern

2026-10-29 代表「キャラの周囲を照らすためのランタンをモデリングして装備できるようにしてください」から。
  lantern_box    木の手提げランタン（標準）。木の枠に、フィルムと白い糸の枠の「ガラス」（design/art-concept.md）、
                 毛糸を巻いた取っ手、中に和紙で包んだ灯りと、それを載せる綿
  lantern_paper  和紙の提灯。細い木の骨の輪に紙を張り、上下に濃い木の口。毛糸の紐で提げる
2026-11-01 代表「ランタンのバリエーションも増やして売って欲しい」から、裁縫の道具と材料で形を借りた売り物（LANTERNS の表）。
光る所は役割 paper / paper_<色>（Godot は名前に paper の入る部品を光らせ、色は game/lantern.gd の LOOK で決める）。
提げる所（取っ手のてっぺん）が原点で、体は下（-Z）。目印: hang（提げる所＝原点）、light（灯りの芯。Godot はここに灯りをともす）。
実寸（m）。ゲームでは人形の大きさに合わせて縮める（game/lantern.gd）。
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）")),
              ("--sheet", dict(action="store_true", help="売り物を竿に提げて並べた案の絵"))])
K.setup(A, fiber=4.0, scale=1.0, tris=2400)


def lathe_at(P, role, prof, mtx, segs=12, closed=True):
    """回転体を mtx の向きと所に置く（lathe の軸 Z が、mtx の Z になる）"""
    m = P.m(role)
    n0 = len(m.bm.verts)
    C.lathe(m, prof, segs, closed)
    C.place(m, n0, mtx)


def facing(c, a):
    """c に置いて、水平の向き a（ラジアン）の外を向く（軸 Z を外へ）"""
    return Matrix.Translation(c) @ Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "Y")


def ball(P, role, c, r, segs=10):
    prof = [(r * math.sin(math.pi * j / 6), -r * math.cos(math.pi * j / 6)) for j in range(7)]
    K.lathe(P, role, prof, c, segs=segs)


def hang_loop(P, role="hemp", z=-0.03, r=0.0028):
    """てっぺんの提げる輪と、下へのひも"""
    K.ring(P, role, (0, 0, -0.004), 0.011, r, axis="Y", n=14)
    K.tube(P, role, [(0, 0, -0.012), (0, 0, z)], r, sides=6)


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


def lantern_box(name, wood="wood", dark="wood_dark", bent="wood_bent", wrap="yarn_red", thread="thread", glow="paper",
                inlay=None):
    """木の手提げ。螺鈿の灯籠は役割を漆・金の糸に替え、inlay（貝）を板と柱にはめる"""
    P = K.Parts(name, kind="lantern")
    H = 0.07                       # 枠の半分の幅
    zt, zb = -0.10, -0.28          # 枠の上と下
    # 取っ手と、提げる麻ひもの輪
    wrapped_bail(P, bent, wrap, (0, 0, -0.072), 0.062, 0.0055)
    K.ring(P, "hemp", (0, 0, -0.004), 0.011, 0.0028, axis="Y", n=16)
    # 屋根（四角すい）と煙出し
    K.lathe(P, dark, [(0.0, -0.062), (0.03, -0.066), (0.108, -0.098), (0.108, -0.104), (0.0, -0.104)],
            segs=4, rot=(math.pi / 4, "Z"))
    K.lathe(P, dark, [(0.0, -0.05), (0.02, -0.05), (0.022, -0.056), (0.022, -0.068), (0.0, -0.068)], segs=10)
    # 上と下の板、四隅の柱
    K.box(P, wood, (0, 0, zt - 0.006), (2 * H + 0.02, 2 * H + 0.02, 0.014))
    K.box(P, wood, (0, 0, zb - 0.012), (2 * H + 0.03, 2 * H + 0.03, 0.026))
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.dowel(P, wood, (sx * H, sy * H, zb), (sx * H, sy * H, zt), 0.0085, sides=6)
    if inlay:   # 螺鈿: 下の板の 4 面に菱形の貝を 3 枚ずつ、柱に細い貝を 2 枚ずつ
        for k in range(4):
            a = math.pi / 2 * k
            for u in (-0.045, 0.0, 0.045):
                c = Vector((math.cos(a) * (H + 0.0155) - math.sin(a) * u, math.sin(a) * (H + 0.0155) + math.cos(a) * u, zb - 0.012))
                lathe_at(P, inlay, [(0.0, -0.0008), (0.0075, -0.0008), (0.0075, 0.0008), (0.0, 0.0008)], facing(c, a), segs=4)
        for sx in (-1, 1):
            for sy in (-1, 1):
                for z in (zt - 0.05, zb + 0.05):
                    K.box(P, inlay, (sx * (H + 0.006), sy * (H + 0.006), z), (0.004, 0.004, 0.022))
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
        K.stitch_line(P, thread, [at(-w + 0.008, zt2, d), at(w - 0.008, zt2, d), at(w - 0.008, zb2, d), at(-w + 0.008, zb2, d), at(-w + 0.008, zt2, d)],
                      r=0.0016, dash=0.011)
        zm = (zt2 + zb2) / 2
        K.stitch_line(P, thread, [at(-w + 0.008, zm, d), at(w - 0.008, zm, d)], r=0.0016, dash=0.011)
    # 中の灯り: 和紙で包んだ芯（光る紙）を、小さな木の皿の綿に載せる
    K.disc(P, dark, (0, 0, zb + 0.008), 0.034, 0.008, segs=16)
    prof = []
    for j in range(9):
        t = j / 8
        prof.append((0.004 + 0.03 * math.sin(math.pi * t) ** 0.8, zb + 0.03 + 0.085 * t))
    K.lathe(P, glow, prof, segs=20, closed=False)
    K.ring(P, "thread_red", (0, 0, zb + 0.072), 0.0335, 0.0018, n=20)   # 包んだ紙を赤い糸で結ぶ
    K.blob(P, "cotton", "cotton", [((0.0, 0.0, zb + 0.026), 0.028), ((0.018, 0.008, zb + 0.02), 0.018),
                                    ((-0.016, -0.01, zb + 0.021), 0.018), ((0.004, -0.019, zb + 0.02), 0.015)],
           0.006, lumps=0.1, fuzz=0.004)
    if inlay:   # 漆の灯籠には、下に茜の房
        K.tube(P, "yarn_red", [(0, 0, zb - 0.025), (0, 0, zb - 0.05)], 0.004, sides=6)
        for k in range(8):
            a = 2 * math.pi * k / 8
            K.tube(P, "yarn_red", [(0, 0, zb - 0.045), (0.009 * math.cos(a), 0.009 * math.sin(a), zb - 0.095)], 0.0022, sides=4)
        K.disc(P, "brass", (0, 0, zb - 0.047), 0.007, 0.008, segs=12)
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




# ---------------------------------------------------------------- 売り物（2026-11-01）
# 光る所の役割。書き出しはどれも paper（Godot が名前で光らせ、色は lantern.gd の LOOK）、案の絵では色ごとの役割で光らせる
GLOW_HEX = {"honey": "F4BE6A", "rose": "F29C78", "linen": "F4E7CC", "peach": "F7B48C", "gold": "F6C24C",
            "firefly": "CBEA6A", "moon": "DCE8F4", "amber": "F0A23A"}


def G(color):
    return "paper" if A.export else "paper_" + color


def lantern_spool(name):
    """糸巻き: 木の糸巻きのつばを上下に、胴は光る紙の筒。生成りの糸を 3 つの帯に巻き、帯のすき間から光が出る"""
    P = K.Parts(name, kind="lantern")
    hang_loop(P, "hemp", -0.04)
    K.ring(P, "brass", (0, 0, -0.044), 0.006, 0.002, axis="Y", n=12)   # つばに打った真鍮の目
    z0, z1 = -0.055, -0.235
    for z in (z0, z1):
        K.lathe(P, "wood", [(0.0, z - 0.012), (0.068, z - 0.012), (0.075, z - 0.006), (0.075, z + 0.006), (0.068, z + 0.012), (0.0, z + 0.012)], segs=28)
    K.ring(P, "wood_dark", (0, 0, z0 + 0.012), 0.02, 0.003, n=16)   # 糸巻きの穴の縁
    K.lathe(P, G("honey"), [(0.046, z1 + 0.012), (0.046, z0 - 0.012)], segs=24, closed=False)
    for za, zb in ((-0.075, -0.103), (-0.130, -0.160), (-0.187, -0.215)):
        n = int((za - zb) / 0.0042)
        for j in range(n + 1):
            K.ring(P, "thread", (0, 0, zb + j * 0.0042), 0.0495, 0.0022, n=28)
    K.tube(P, "thread", [(0.051, 0.0, -0.104), (0.06, -0.01, -0.12), (0.058, -0.016, -0.14), (0.062, -0.012, -0.152)], 0.0018, sides=5)
    P.mark("hang", (0, 0, 0))
    P.mark("light", (0, 0, -0.145))
    P.finish()


def lantern_knit(name):
    """編み帽子: 光る紙の芯に、透かし編みの毛糸の帽子をかぶせる（茜と生成りの縞、裾はゴム編み、てっぺんにぼんぼり）"""
    P = K.Parts(name, kind="lantern")
    hang_loop(P, "yarn_red", -0.03, 0.003)
    z0, z1 = -0.065, -0.245
    prof = [(0.012 + 0.052 * math.sin(math.pi * (0.12 + 0.88 * j / 12)) ** 0.6, z1 + (z0 - z1) * (1 - j / 12)) for j in range(13)]
    prof = list(reversed(prof))
    K.lathe(P, G("rose"), [(0.004, z0 + 0.004)] + prof[1:], segs=20, closed=False)
    rows = 14
    for j in range(rows):
        t = (j + 0.5) / rows
        z = z0 + (z1 + 0.02 - z0) * t
        rr = 0.012 + 0.052 * math.sin(math.pi * (0.12 + 0.88 * (z - z0) / (z1 - z0))) ** 0.6
        role = "yarn_cream" if j % 4 == 2 else "yarn_red"
        K.ring(P, role, (0, 0, z), rr + 0.004, 0.0042, n=28)
    for j in range(4):   # 裾のゴム編み
        K.ring(P, "yarn_red", (0, 0, z1 + 0.012 - j * 0.0075), 0.046, 0.005, n=28)
    K.blob(P, "pom", "yarn_cream", [((0, 0, z0 + 0.012), 0.024), ((0.006, 0.004, z0 + 0.018), 0.018), ((-0.006, -0.004, z0 + 0.016), 0.018)],
           0.004, lumps=0.25, fuzz=0.005)
    P.mark("hang", (0, 0, 0))
    P.mark("light", (0, 0, -0.16))
    P.finish()


def lantern_hoop(name):
    """刺繍枠: 木の刺繍枠を上下に 2 つ、間に麻布の筒を張る。布に赤い糸のクロスステッチで雪の結晶。麻ひも 3 本で提げる"""
    P = K.Parts(name, kind="lantern", tris=3200)   # 細かい粒・糸が多いので、軽くするときの三角を多めに
    K.ring(P, "brass", (0, 0, -0.006), 0.009, 0.0024, axis="Y", n=12)
    R = 0.07
    z0, z1 = -0.085, -0.245
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        K.tube(P, "hemp", [(0, 0, -0.014), (R * math.cos(a), R * math.sin(a), z0 + 0.006)], 0.0018, sides=5)
    for z in (z0, z1):
        K.ring(P, "wood_light", (0, 0, z), R + 0.004, 0.0048, n=36)
        K.ring(P, "wood_light", (0, 0, z - 0.008), R + 0.004, 0.0048, n=36)
        K.box(P, "brass", (R + 0.012, 0, z - 0.004), (0.012, 0.01, 0.016))   # 枠のねじ
        K.dowel(P, "brass", (R + 0.008, -0.012, z - 0.004), (R + 0.008, 0.012, z - 0.004), 0.003, sides=8)
    K.lathe(P, G("linen"), [(R, z1 - 0.004), (R, z0 - 0.004)], segs=32, closed=False)
    K.disc(P, "wood_light", (0, 0, z1 - 0.01), R - 0.004, 0.006, segs=28)
    # 雪の結晶（十字と斜めの腕）を、クロスステッチの × で 6 つ
    flake = [(0, 0)] + [(i * d[0], i * d[1]) for d in ((1, 0), (-1, 0), (0, 1), (0, -1)) for i in (1, 2, 3)] + \
            [(i * d[0], i * d[1]) for d in ((1, 1), (-1, 1), (1, -1), (-1, -1)) for i in (1, 2)]
    cell = 0.0062
    for k in range(6):
        a = 2 * math.pi * k / 6
        zc = -0.165 + (0.035 if k % 2 else -0.035)
        for (u, v) in flake:
            au = a + u * cell / R
            for (s0, s1) in (((-1, -1), (1, 1)), ((-1, 1), (1, -1))):
                p0 = ((R + 0.0012) * math.cos(au + s0[0] * cell * 0.4 / R), (R + 0.0012) * math.sin(au + s0[0] * cell * 0.4 / R), zc + v * cell + s0[1] * cell * 0.4)
                p1 = ((R + 0.0012) * math.cos(au + s1[0] * cell * 0.4 / R), (R + 0.0012) * math.sin(au + s1[0] * cell * 0.4 / R), zc + v * cell + s1[1] * cell * 0.4)
                K.tube(P, "thread_red", [p0, p1], 0.0011, sides=4)
    P.mark("hang", (0, 0, 0))
    P.mark("light", (0, 0, -0.16))
    P.finish()


def lantern_yarnball(name):
    """糸玉: 風船に毛糸を巻いて固めた玉（手芸の糸玉ランプ）。中に光る紙の小さな玉"""
    P = K.Parts(name, kind="lantern", tris=3600)   # 細かい粒・糸が多いので、軽くするときの三角を多めに
    hang_loop(P, "hemp", -0.036)
    K.disc(P, "brass", (0, 0, -0.038), 0.012, 0.006, segs=14)
    c = Vector((0, 0, -0.125))
    R = 0.08
    import random
    rnd = random.Random(7)
    for k in range(16):
        ax = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized()
        u = ax.orthogonal().normalized()
        v = ax.cross(u)
        pts = [c + (u * math.cos(2 * math.pi * i / 48) + v * math.sin(2 * math.pi * i / 48)) * (R + rnd.uniform(-0.003, 0.003)) for i in range(49)]
        K.tube(P, "yarn_yellow" if k % 3 else "hemp", pts, 0.0026, sides=5)
    ball(P, G("peach"), tuple(c), 0.04, segs=16)
    P.mark("hang", (0, 0, 0))
    P.mark("light", tuple(c))
    P.finish()


def lantern_thimble(name):
    """指ぬき: 大きな真鍮の指ぬきを伏せる。くぼみの穴から光が粒になって漏れる。口に真鍮の縁、毛糸の房で提げる"""
    P = K.Parts(name, kind="lantern", tris=4500)   # 細かい粒・糸が多いので、軽くするときの三角を多めに
    hang_loop(P, "yarn_red", -0.035, 0.003)
    K.ring(P, "brass", (0, 0, -0.036), 0.007, 0.0022, axis="Y", n=12)
    zt, zb = -0.045, -0.225
    prof = [(0.0, zt), (0.022, zt - 0.002), (0.04, zt - 0.012), (0.05, zt - 0.03), (0.055, zt - 0.05), (0.058, zb + 0.02), (0.06, zb)]
    K.lathe(P, "brass", prof, segs=32, closed=False)
    K.ring(P, "brass", (0, 0, zb + 0.004), 0.061, 0.004, n=36)
    K.ring(P, "brass", (0, 0, zb + 0.016), 0.0605, 0.002, n=36)
    for j in range(9):   # くぼみの穴: 段ごとに半分ずらして並べる
        z = zt - 0.045 - j * 0.0135
        if z < zb + 0.03:
            break
        rr = 0.055 + 0.003 * (j / 8)
        n = 20
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * (j % 2)) / n
            ball(P, G("gold"), (rr * math.cos(a), rr * math.sin(a), z), 0.0036, segs=8)
    for i in range(10):   # 天のくぼみ
        a = 2 * math.pi * i / 10
        ball(P, G("gold"), (0.03 * math.cos(a), 0.03 * math.sin(a), zt - 0.009), 0.0032, segs=8)
    K.disc(P, G("gold"), (0, 0, zb + 0.03), 0.045, 0.004, segs=24)   # 中の灯り（下からのぞく）
    P.mark("hang", (0, 0, 0))
    P.mark("light", (0, 0, -0.15))
    P.finish()


def lantern_hotaru(name):
    """蛍かご: 木の六角の板を上下に、麻ひもを縦に張って横に編んだ虫かご。中にフェルトの蛍が 5 匹、おしりが光る"""
    P = K.Parts(name, kind="lantern", tris=3000)   # 細かい粒・糸が多いので、軽くするときの三角を多めに
    hang_loop(P, "hemp", -0.045)
    z0, z1 = -0.07, -0.245
    R = 0.068
    K.lathe(P, "wood_dark", [(0.0, z0 + 0.03), (0.016, z0 + 0.03), (R + 0.012, z0 + 0.004), (R + 0.012, z0 - 0.004), (0.0, z0 - 0.004)], segs=6)
    K.lathe(P, "wood_dark", [(0.0, z1 - 0.012), (R + 0.01, z1 - 0.012), (R + 0.01, z1 + 0.004), (0.0, z1 + 0.004)], segs=6)
    for i in range(24):
        a = 2 * math.pi * i / 24
        rr = R / math.cos(((a + math.pi / 6) % (math.pi / 3)) - math.pi / 6)   # 六角の辺の上
        K.tube(P, "hemp", [(rr * math.cos(a), rr * math.sin(a), z1), (rr * math.cos(a), rr * math.sin(a), z0)], 0.0016, sides=4)
    for j in range(1, 6):
        z = z1 + (z0 - z1) * j / 6
        K.ring(P, "hemp", (0, 0, z), R / math.cos(math.pi / 6) * 0.995, 0.0017, n=6)
    for k in range(5):   # 草（フェルトの細い葉）
        a = 2 * math.pi * k / 5 + 0.3
        b = Vector((0.02 * math.cos(a), 0.02 * math.sin(a), z1 + 0.004))
        K.tube(P, "felt_green", [b, b + Vector((0.01 * math.cos(a), 0.01 * math.sin(a), 0.04)), b + Vector((0.025 * math.cos(a), 0.025 * math.sin(a), 0.06))],
               [0.004, 0.003, 0.0008], sides=4)
    flies = [((0.02, 0.01, -0.12), 0.4), ((-0.025, 0.015, -0.16), 2.2), ((0.01, -0.03, -0.19), 4.0), ((-0.01, -0.01, -0.1), 3.1), ((0.03, -0.01, -0.21), 5.2)]
    for (p, a) in flies:
        p = Vector(p)
        d = Vector((math.cos(a), math.sin(a), 0.15)).normalized()
        K.tube(P, "felt_charcoal", [p, p + d * 0.016], [0.0045, 0.0035], sides=6)
        ball(P, "felt_red", tuple(p + d * 0.019), 0.003, segs=6)
        ball(P, G("firefly"), tuple(p - d * 0.006), 0.0062, segs=10)
    P.mark("hang", (0, 0, 0))
    P.mark("light", (0, 0, -0.16))
    P.finish()


def lantern_pearl(name):
    """白蝶貝のボタン: 真鍮の輪から糸を垂らし、白蝶貝のボタンを鱗のように重ねて連ねる。中に月白の光る紙"""
    P = K.Parts(name, kind="lantern", tris=5000)   # 細かい粒・糸が多いので、軽くするときの三角を多めに
    hang_loop(P, "thread", -0.03, 0.0022)
    K.lathe(P, "brass", [(0.0, -0.03), (0.016, -0.034), (0.032, -0.046), (0.032, -0.05), (0.0, -0.05)], segs=20)
    K.ring(P, "brass", (0, 0, -0.05), 0.064, 0.0028, n=36)
    for k in range(3):
        a = 2 * math.pi * k / 3
        K.tube(P, "brass", [(0.03 * math.cos(a), 0.03 * math.sin(a), -0.048), (0.064 * math.cos(a), 0.064 * math.sin(a), -0.05)], 0.0018, sides=5)
    K.lathe(P, G("moon"), [(0.0, -0.05), (0.028, -0.07), (0.036, -0.12), (0.03, -0.17), (0.012, -0.2), (0.0, -0.205)], segs=18)
    n = 12
    for i in range(n):
        a = 2 * math.pi * i / n
        rows = 4 if i % 2 else 5
        for j in range(rows):
            z = -0.066 - j * 0.032 - (0.016 if i % 2 else 0.0)
            rr = 0.066 - 0.004 * j
            c = Vector((rr * math.cos(a), rr * math.sin(a), z))
            lathe_at(P, "pearl", [(0.0, -0.0016), (0.0145, -0.0016), (0.016, 0.0), (0.0145, 0.0016), (0.0, 0.0016)],
                     facing(c, a) @ Matrix.Rotation(-0.25, 4, "Y"), segs=16)
            for (hu, hv) in ((-0.004, 0.0), (0.004, 0.0)):   # ボタンの 2 つ穴
                q = c + Vector((math.cos(a), math.sin(a), 0)) * 0.0018 + Vector((-math.sin(a), math.cos(a), 0)) * hu
                ball(P, "thread", tuple(q), 0.0018, segs=6)
        K.tube(P, "thread", [(0.066 * math.cos(a), 0.066 * math.sin(a), -0.05), (0.06 * math.cos(a), 0.06 * math.sin(a), -0.066 - (rows - 1) * 0.032)], 0.0008, sides=4)
    ball(P, "pearl", (0, 0, -0.218), 0.009, segs=12)
    P.mark("hang", (0, 0, 0))
    P.mark("light", (0, 0, -0.13))
    P.finish()


## 売り物の表: [名前, 作る関数, 案の名前, 値段（木のボタンの何個分。0 ははじめから）, 光の色, 揺れ方]
LANTERNS = [
    ("lantern_box", lambda n: lantern_box(n), "木の手提げ", 0, "電球色", "ゆっくり揺らぐ"),
    ("lantern_paper", lantern_paper, "和紙の提灯", 0, "電球色", "ゆっくり揺らぐ"),
    ("lantern_spool", lantern_spool, "糸巻き", 40, "蜜色", "じっと灯る"),
    ("lantern_knit", lantern_knit, "毛糸の編み帽子", 80, "茜", "ゆっくり揺らぐ"),
    ("lantern_hoop", lantern_hoop, "刺繍枠と麻布", 120, "生成りの白", "息をするように明暗"),
    ("lantern_yarnball", lantern_yarnball, "糸玉", 200, "杏色", "まだらの光がゆっくり回る"),
    ("lantern_thimble", lantern_thimble, "真鍮の指ぬき", 300, "金色", "ろうそくのようにちらつく"),
    ("lantern_hotaru", lantern_hotaru, "麻ひもの蛍かご", 500, "黄緑", "蛍が 1 匹ずつ明滅"),
    ("lantern_pearl", lantern_pearl, "白蝶貝のボタン", 1000, "月白", "青白くきらめく"),
    ("lantern_raden", lambda n: lantern_box(n, wood="lacquer", dark="lacquer", bent="lacquer", wrap="thread_gold", thread="thread_gold",
                                            glow=G("amber"), inlay="shell"), "螺鈿の漆の灯籠", 1500, "山吹", "ゆっくり揺らぐ"),
]

for role, hexcol in GLOW_HEX.items():
    C.HEX["paper_" + role] = hexcol
    if not A.export and C.LOOK["v"] == "day":
        C._MAT["paper_" + role] = C.LM.emissive("paper_" + role, hexcol, 2.0).m
        C._MAT["paper_" + role].name = "paper_" + role

for nm, fn, *_rest in LANTERNS:
    fn(nm)


def font():
    base = os.path.dirname(bpy.app.binary_path) + "/../Resources"
    for ver in os.listdir(base):
        p = os.path.join(base, ver, "datafiles", "fonts", "Noto Sans CJK Regular.woff2")
        if os.path.exists(p):
            return bpy.data.fonts.load(p)
    return None


def label(text, at, size, hexcol):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = text
    cu.align_x = "CENTER"
    cu.size = size
    f = font()
    if f:
        cu.font = f
    o = bpy.data.objects.new("label", cu)
    C.coll("stage").objects.link(o)
    o.data.materials.append(C.LM.emissive("ink_" + hexcol, hexcol, 1.0).m)
    o.location = at
    o.rotation_euler = (math.radians(90), 0, 0)
    return o


def light_in(r, hexcol, energy=2.0):
    for o in [o for o in K.descendants(r) if o.name.startswith("light")]:
        L = bpy.data.objects.new("bulb", bpy.data.lights.new("bulb", "POINT"))
        C.coll("stage").objects.link(L)
        L.location = o.matrix_world.translation
        L.data.energy = energy
        L.data.color = tuple(c for c in C.LM.lin(hexcol)[:3])
        L.data.shadow_soft_size = 0.02


if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
elif A.sheet:
    # 竿に提げて 2 段に並べる。後ろは藍のフェルトの壁、灯りは弱い室内の光と、ランタンそれぞれの色の灯り
    R = {r.name: r for r, p in K.made}
    cols, dx, dz = 5, 0.36, 0.66
    for i, (nm, fn, title, price, color, sway) in enumerate(LANTERNS):
        col, row = i % cols, i // cols
        x = (col - (cols - 1) / 2) * dx
        z = 1.5 - row * dz
        R[nm].location = (x, 0, z)
        bpy.context.view_layer.update()
        key = {"電球色": None, "蜜色": "honey", "茜": "rose", "生成りの白": "linen", "杏色": "peach", "金色": "gold", "黄緑": "firefly",
               "月白": "moon", "山吹": "amber"}[color]
        light_in(R[nm], GLOW_HEX[key] if key else "FFB36B", 4.0 if key == "moon" else 2.4)
        label("L%d %s" % (i + 1, title), (x, -0.08, z - 0.36), 0.036, "F1E8D6")
        label("%s ・ %s" % ("はじめから" if price == 0 else "ボタン %d" % price, color), (x, -0.08, z - 0.41), 0.03, "E2CFA8")
        label(sway, (x, -0.08, z - 0.455), 0.027, "C8B590")
    for row in range(2):   # 竿
        z = 1.5 - row * dz + 0.004
        rod = C.M("rod%d" % row, "wood", "stage")
        C.tube(rod, [Vector((-1.1, 0.0, z + 0.012)), Vector((1.1, 0.0, z + 0.012))], 0.012, sides=12)
        rod.done()
    wall = C.M("wall", "felt_navy2", "stage")
    import bmesh
    bmesh.ops.create_cube(wall.bm, size=1.0, matrix=Matrix.Translation((0, 0.25, 1.2)) @ Matrix.Diagonal((4.0, 0.05, 3.0, 1)))
    wall.done(smooth=False)
    K.interior_light(0.3)
    bpy.data.objects.remove(bpy.data.objects["window"])   # 窓の青い光は、この絵では要らない
    bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.2
    A.views = "sheet"
    K.render_views(A, {"sheet": ((0.0, -3.55, 0.94), (0.0, 0.0, 0.94), 62)})
else:
    R = {r.name: r for r, p in K.made}
    R["lantern_box"].location = (-0.16, 0, 0.42)
    R["lantern_paper"].location = (0.16, 0, 0.42)
    for nm in list(R):
        if nm not in ("lantern_box", "lantern_paper"):
            R[nm].hide_render = True
            for o in K.descendants(R[nm]):
                o.hide_render = True
    for r, parts in K.made:   # 灯りの芯に、描くときだけ暖色の灯り
        if r.hide_render:
            continue
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
