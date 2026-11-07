"""染め桶と衣装掛けを一つの施設にまとめる案（2026-11-04 代表「染め桶と衣装掛けは一つの施設に統合できたら嬉しい。アートコンセプトに則って3案ほしいな」）。
形は裁縫の道具と材料から借り、素材は props/common.py と kit.py の本番の物（木・フェルト・麻・糸・真鍮）。人形は game/person の本番の 7 体。
  A  染め場の干し櫓   高い櫓から染めた反物が長く垂れて、舟形の桶に浸かる。人形の竿は桶の真上
  B  大きな人台        大きなトルソーの裾が、染めた布のスカートになって桶に浸かる。腰の輪に人形が掛かる
  C  大きな裁縫箱      ふたを開けた木の裁縫箱。ふたの裏がキルトの壁で、竿はその前。箱の中の 3 つの仕切りが染め液
代表「2 が一番好きだけど 1 の長く伸ばされた布が染物屋感を強く感じる」から、B に A の長い布を足した 2 通り:
  D  人台と後ろの干し竿  人台の後ろの高い竿から、3 本の反物が桶へ落ちる。腰の輪は後ろをあける
  E  人台と天井の輪      天井から吊った大きな輪から、長い布が人台の後ろを囲んで桶へ落ちる。ロッジの天井があって成り立つ

代表は E を選び、裾は白に（2026-11-04 代表「トルソーのスカート的部分の布の色は白がいいです」）。
腰の輪と裾の始まりは、胴のくびれの高さへ（同日 代表「人形もうちょっと高いほうが良い」「トルソーの腰のクビレの位置に持っていったら今の意味不明なスカート始まり位置も良くなる」）。
ゲーム用の glb は game/wardrobe.gd が読む。染め液・ハンガー・人形はゲームが足す:
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/dye-wardrobe/ideas.py -- --what E --export game/props/dress_form

    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/dye-wardrobe/ideas.py -- --what A --views hero --prefix OUT --size 1200x900

寸法はゲームの大きさ (m)。竿の高さ 1.85 m・人形の背丈 0.62 m は game/wardrobe.gd と同じ。天井は床から 5.25 m（lodge/dims.py）。前は +Y
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(ROOT, "props"))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--what", dict(default="A"))])
K.setup(A, fiber=1.5, scale=1.0, tris=9000)
C.HEX.update({"felt_indigo": "2B3D68", "felt_rust": "A8532E", "felt_mustard": "C99A3A", "felt_madder": "9E3B3A",
              "felt_ivory": "EEE6D4", "felt_moss": "6E7F4A", "felt_indigo2": "22325A", "felt_white": "F5F2EA", "felt_white2": "E8E4DA",
              "dye_indigo": "1C2A4E", "dye_rust": "7E3A1E", "dye_mustard": "A87C22"})

EX = bool(A.export)
DOLLS = ["kasa", "origami", "news", "robo", "musha", "ningyo", "golem"]
RAIL_Y = 1.85
WAIST_Z = 3.12   # 胴のくびれの高さ（SECS）
HANG = 0.62


def import_doll(name, height=None, scale=None):
    """本番の人形を読み、足もとを原点、前を +Y にした箱の節にまとめる"""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "game", "person", name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):   # 読み込みが作る骨の表示用の球は、人形ではない
        if o.type == "MESH" and o.parent is None:
            new.remove(o)
            bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    lo, hi = Vector((9e9,) * 3), Vector((-9e9,) * 3)
    for o in new:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    g = bpy.data.objects.new("doll_" + name, None)
    C.coll("prop").objects.link(g)
    h = hi.z - lo.z
    s = scale if scale else (height / h)
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    inner = bpy.data.objects.new("inner", None)
    C.coll("prop").objects.link(inner)
    inner.parent = g
    inner.scale = (s, s, s)
    inner.location = (-cx * s, -cy * s, -lo.z * s)
    for o in new:
        if o.parent is None:
            o.parent = inner
    return g, h * s


def hang(P, name, pos, yaw=0.0):
    """竿の pos に、ハンガーと人形を掛ける。pos は竿の芯。yaw は人形の向き（0 で +Y）"""
    x, y, z = pos
    fx, fy = math.cos(yaw), math.sin(yaw)
    K.tube(P, "brass", [(x, y, z + 0.035), (x, y, z - 0.09)], 0.008)
    K.ring(P, "brass", (x, y, z), 0.036, 0.007, axis="X", n=16)
    K.dowel(P, "wood_dark", (x - fx * 0.17, y - fy * 0.17, z - 0.1), (x + fx * 0.17, y + fy * 0.17, z - 0.1), 0.014)
    g, h = import_doll(name, height=HANG)
    g.location = (x, y, z - 0.11 - h)
    g.rotation_euler = (0, 0, yaw)


def drape(P, role, x0, x1, y, zt, zb, folds=4, amp=0.03, lean=0.0, nu=44, nv=26):
    """上の縁で吊った布。縦のひだが下へ行くほど深くなる"""
    m = P.m(role)
    rows = []
    for j in range(nv + 1):
        t = j / nv
        row = []
        for i in range(nu + 1):
            u = i / nu
            x = x0 + (x1 - x0) * (u + (u - 0.5) * 0.03 * t)
            yy = y + amp * (0.35 + 0.65 * t) * math.sin(u * folds * math.tau + 0.6 * t) + lean * t
            row.append(m.bm.verts.new((x, yy, zt + (zb - zt) * t)))
        rows.append(row)
    for a, b in zip(rows, rows[1:]):
        for i in range(nu):
            m.bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))


def tub(P, r, h, n=26):
    """木の板を輪で締めた丸い桶（game/dye_vat.gd と同じ作り）"""
    w = math.tau * r / n * 1.03
    for i in range(n):
        a = math.tau * i / n
        role = "wood_dark" if i % 3 == 0 else "wood"
        K.box(P, role, (r * math.cos(a), r * math.sin(a), h / 2), (0.06, w, h), rot=(a, "Z"))
    K.disc(P, "wood_dark", (0, 0, 0.03), r, 0.05, segs=48)
    for z in (0.14, h - 0.13):
        K.ring(P, "hemp", (0, 0, z), r + 0.04, 0.024, n=96)


def paddle(P, base, top, blade=0.14):
    K.dowel(P, "wood", base, top, 0.024)
    b = Vector(base)
    K.box(P, "wood", (b.x, b.y, b.z + 0.12), (blade, 0.025, 0.3))


# ---------------------------------------------------------------- A 染め場の干し櫓
def make_a():
    P = K.Parts("a")
    P.hard = {"wood": 0.01, "wood_dark": 0.01}
    # すのこ
    for i in range(16):
        K.box(P, "wood_dark", (-2.55 + i * 0.34, 0, 0.04), (0.28, 2.0, 0.07))
    # 櫓: 両端に 2 本ずつの柱、上の梁、麻で縛る
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.dowel(P, "pole", (sx * 2.3, sy * 0.62, 0.07), (sx * 2.3, sy * 0.28, 4.45), 0.075)
        K.dowel(P, "wood", (sx * 2.3, -0.5, 2.4), (sx * 2.3, 0.5, 2.4), 0.05)
        for z in (2.4,):
            for sy in (-1, 1):
                K.ring(P, "hemp", (sx * 2.3, sy * 0.47, z), 0.1, 0.014, n=20)
        K.ring(P, "hemp", (sx * 2.3, 0.0, 4.47), 0.12, 0.016, axis="X", n=22)
    K.dowel(P, "wood", (-2.62, 0.0, 4.5), (2.62, 0.0, 4.5), 0.08)
    # 反物 3 本: 梁に掛かり、桶の中へ落ちる
    for role, x0, x1 in (("felt_indigo", -1.75, -0.65), ("felt_rust", -0.55, 0.55), ("felt_mustard", 0.65, 1.75)):
        # 梁に掛かる所は、布の上の縁をかぶせて見せる
        drape(P, role, x0, x1, -0.09, 4.58, 0.56, folds=3, amp=0.05)
        drape(P, role, x0, x1, 0.09, 4.58, 3.75, folds=3, amp=0.012)
        K.stitch_line(P, "thread", [(x0 + 0.03, 0.105, 3.82), (x1 - 0.03, 0.105, 3.82)], r=0.006, dash=0.035)
        K.lathe(P, role, [(0.09, 0), (0.095, 0.01), (0.095, x1 - x0 - 0.01), (0.09, x1 - x0)],
                (x0, 0, 4.5), 20, False, (math.pi / 2, "Y"))
    # 舟形の桶: 長い板の箱に麻の締め
    L, D, H = 4.0, 1.24, 0.66
    for sy in (-1, 1):
        K.box(P, "wood", (0, sy * D / 2, 0.07 + H / 2), (L, 0.07, H))
    for sx in (-1, 1):
        K.box(P, "wood_dark", (sx * L / 2, 0, 0.07 + H / 2), (0.1, D + 0.1, H + 0.06))
    for x in (-1.2, 0.0, 1.2):
        for sy in (-1, 1):
            K.box(P, "wood_dark", (x, sy * (D / 2 + 0.04), 0.07 + H / 2), (0.12, 0.03, H + 0.02))
        K.tube(P, "hemp", [(x, -D / 2 - 0.07, 0.07 + H - 0.1), (x, D / 2 + 0.07, 0.07 + H - 0.1)], 0.001)
    K.box(P, "dye_indigo", (0, 0, 0.07 + H - 0.1), (L - 0.1, D - 0.07, 0.02))
    # 縁に掛けた試し染めの布と櫂
    for role, x in (("felt_indigo", -1.5), ("felt_madder", 1.45)):
        drape(P, role, x - 0.2, x + 0.2, D / 2 + 0.06, 0.07 + H + 0.03, 0.2, folds=2, amp=0.012, nu=14, nv=10)
    paddle(P, (0.9, 0.42, 0.52), (1.35, 0.72, 1.55))
    # 人形の竿: 桶の真上、反物の手前
    y = 0.34
    K.dowel(P, "wood_dark", (-2.3, y, RAIL_Y), (2.3, y, RAIL_Y), 0.035)
    for sx in (-1, 1):
        K.dowel(P, "wood_dark", (sx * 2.3, 0.1, RAIL_Y), (sx * 2.3, y + 0.02, RAIL_Y), 0.04)
    for i, n in enumerate(DOLLS):
        hang(P, n, (-1.74 + i * 0.58, y, RAIL_Y))
    P.finish(fuzz=0.008)


# ---------------------------------------------------------------- B 大きな人台
SECS = [(2.42, 0.60, 0.46), (2.70, 0.66, 0.50), (3.12, 0.50, 0.37), (3.50, 0.60, 0.44), (3.78, 0.70, 0.46),
        (4.02, 0.72, 0.40), (4.16, 0.46, 0.27), (4.27, 0.19, 0.165), (4.50, 0.15, 0.14)]


def _sec_at(z):
    for a, b in zip(SECS, SECS[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            t = t * t * (3 - 2 * t) * 0.5 + t * 0.5
            return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
    return SECS[-1][1:]


def _body_pt(th, z, p=2.5, off=0.0):
    rx, ry = _sec_at(z)
    c, s = math.cos(th), math.sin(th)
    k = (abs(c) ** p + abs(s) ** p) ** (-1 / p)
    return (c * k * (rx + off), s * k * (ry + off), z)


def long_cloth(P, what):
    """A の長い布を人台に足す"""
    if what == "D":
        y, zb = -1.3, 0.6
        for sx in (-1, 1):
            K.dowel(P, "pole", (sx * 2.0, y - 0.3, 0.0), (sx * 2.0, y, 4.95), 0.07)
            K.dowel(P, "pole", (sx * 2.0, y + 0.3, 0.0), (sx * 2.0, y, 4.95), 0.07)
            K.ring(P, "hemp", (sx * 2.0, y, 4.9), 0.1, 0.014, axis="X", n=20)
        K.dowel(P, "wood", (-2.3, y, 4.95), (2.3, y, 4.95), 0.07)
        for role, x0, x1 in (("felt_rust", -1.2, -0.44), ("felt_mustard", -0.38, 0.38), ("felt_madder", 0.44, 1.2)):
            drape(P, role, x0, x1, y - 0.08, 5.03, zb, folds=2, amp=0.05)
            drape(P, role, x0, x1, y + 0.08, 5.03, 4.25, folds=2, amp=0.012)
            K.lathe(P, role, [(0.08, 0), (0.085, 0.01), (0.085, x1 - x0 - 0.01), (0.08, x1 - x0)], (x0, y, 4.95), 20, False, (math.pi / 2, "Y"))
            K.stitch_line(P, "thread", [(x0 + 0.03, y + 0.095, 4.32), (x1 - 0.03, y + 0.095, 4.32)], r=0.006, dash=0.035)
    elif what == "E":
        R0 = 1.62
        K.ring(P, "wood_dark", (0, 0, 4.92), R0, 0.04, n=120)
        K.box(P, "wood_dark", (0, 0, 5.17), (4.4, 0.34, 0.16))   # 天井の梁（上の面が 1 階の天井）
        for sx in (-1, 1):
            K.tube(P, "hemp", [(sx * R0, 0, 4.94), (sx * R0, 0, 5.1)], 0.014)
        # 長い布は、書き出すときは焼かない。近づくと液から昇るように、ゲームが作る（game/dress_form_cloth.gd。2026-11-07 代表）
        roles = () if EX else ("felt_rust", "felt_mustard", "felt_madder", "felt_moss", "felt_rust")
        for k, role in enumerate(roles):   # 後ろの半分あまりに 5 枚。前はあける
            a0 = math.radians(150 + 48 * k)
            a1 = a0 + math.radians(40)
            rm = P.m(role)
            rows = []
            for j in range(29):
                t = j / 28
                row = []
                for i in range(19):
                    u = i / 18
                    a = a0 + (a1 - a0) * u
                    r = R0 + 0.05 * (0.3 + t) * math.sin(u * math.tau * 2) + 0.03 * math.sin(t * 3)
                    row.append(rm.bm.verts.new((r * math.cos(a), r * math.sin(a), 4.96 + (0.6 - 4.96) * t)))
                rows.append(row)
            for a, b in zip(rows, rows[1:]):
                for i in range(18):
                    rm.bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
            K.stitch_line(P, "thread", [(1.6 * math.cos(a0 + (a1 - a0) * u / 16), 1.6 * math.sin(a0 + (a1 - a0) * u / 16), 4.8) for u in range(17)], r=0.006, dash=0.035)


def make_b(what="B"):
    P = K.Parts("dress_form" if EX else "b")
    waist = what == "E"          # E は腰の輪と裾の始まりがくびれの高さ
    hz = WAIST_Z if waist else RAIL_Y
    in_r, in_z = (0.62, WAIST_Z + 0.03) if waist else (0.72, 2.28)
    tub(P, 1.8, 0.74)
    if not EX:   # 染め液はゲームが足す（染めた色に変わるので）
        K.disc(P, "dye_indigo", (0, 0, 0.62), 1.76, 0.02, segs=72)
    # 芯の棒と腰の輪（クリノリンの骨）
    K.dowel(P, "wood_dark", (0, 0, 0.1), (0, 0, 2.5), 0.1)
    if what == "D":   # 後ろの反物の通り道をあけた C の字の輪
        arc = [math.radians(-40 + 260 * j / 80) for j in range(81)]
        K.tube(P, "wood_dark", [(1.5 * math.cos(a), 1.5 * math.sin(a), RAIL_Y) for a in arc], 0.035)
    else:
        K.ring(P, "wood_dark", (0, 0, hz), 1.5, 0.035, n=120)
    K.ring(P, "wood_dark", (0, 0, in_z), in_r, 0.024, n=72)
    spokes = [math.radians(-40 + 260 * j / 5) for j in range(6)] if what == "D" else [math.tau * (i + 0.5) / 7 + math.pi / 2 for i in range(7)]
    for a in spokes:
        K.dowel(P, "wood_dark", (in_r * math.cos(a), in_r * math.sin(a), in_z),
                (1.5 * math.cos(a), 1.5 * math.sin(a), hz), 0.022)
    # 胴: 布を張った人台
    m = P.m("felt_cream")
    n, rows = 64, []
    zs = [2.42 + (4.5 - 2.42) * j / 60 for j in range(61)]
    for z in zs:
        rows.append([m.bm.verts.new(_body_pt(math.tau * i / n, z)) for i in range(n)])
    for a, b in zip(rows, rows[1:]):
        for i in range(n):
            m.bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    m.bm.faces.new(rows[0][::-1])
    # 胴の線: 前の真ん中と腰と胸に赤い糸、脇の切り替えは濃い糸で縫う
    def line(th, z0, z1, role, dash=0.035):
        K.stitch_line(P, role, [_body_pt(th, z0 + (z1 - z0) * j / 30, off=0.004) for j in range(31)], r=0.007, dash=dash)
    line(math.pi / 2, 2.45, 4.45, "thread_red")
    for th in (math.pi / 2 - 0.62, math.pi / 2 + 0.62, -math.pi / 2 - 0.62, -math.pi / 2 + 0.62, 0.0, math.pi):
        line(th, 2.45, 4.1, "thread_dark")
    for z in (3.12, 3.72):
        K.stitch_line(P, "thread_red", [_body_pt(math.tau * j / 80, z, off=0.004) for j in range(81)], r=0.007, dash=0.035)
    # 首の木のふたと真鍮のつまみ、腰のふち
    K.disc(P, "wood_dark", (0, 0, 4.52), 0.2, 0.05)
    K.lathe(P, "brass", [(0.0, 0.0), (0.05, 0.0), (0.03, 0.05), (0.055, 0.1), (0.0, 0.15)], (0, 0, 4.54), 20, False)
    if waist:   # くびれに巻いた麻の帯
        K.tube(P, "hemp", [_body_pt(math.tau * j / 72, WAIST_Z + 0.04, off=0.012) for j in range(73)], 0.02)
    else:
        K.ring(P, "hemp", (0, 0, 2.44), 0.68, 0.02, n=72)
    # 巻き尺を首に掛ける
    pts = [_body_pt(math.tau * j / 24 + math.pi / 2, 4.27, off=0.022) for j in range(25)]
    K.tube(P, "felt_mustard", pts, 0.03, ry=0.006, sides=8)
    for sx in (-0.13, 0.15):
        K.tube(P, "felt_mustard", [_body_pt(math.pi / 2 + sx, z, off=0.02) for z in (4.26, 4.12, 3.95, 3.75, 3.5 if sx < 0 else 3.28)], 0.03, ry=0.006, sides=8)
    # 裾: 布を腰から桶の中へ垂らす 14 枚はぎ
    roles = ("felt_white", "felt_white2") if what == "E" else ("felt_indigo", "felt_indigo2")
    panels = 14
    for k in range(panels):
        rm = P.m(roles[k % len(roles)])
        a0 = math.tau * k / panels
        a1 = math.tau * (k + 1) / panels
        rows2 = []
        for j in range(19):
            t = j / 18
            z = (WAIST_Z if waist else 2.46) + (0.6 - (WAIST_Z if waist else 2.46)) * t
            row = []
            for i in range(13):
                u = i / 12
                a = a0 + (a1 - a0) * u
                if waist:   # くびれの楕円から腰をよけて広がり、桶で丸くなる
                    r = 0.51 + (1.32 - 0.51) * (t ** 0.6) + 0.035 * (0.1 + t) * math.sin(u * math.tau * 1.5)
                    rx, ry = r, r * (0.76 + 0.24 * t ** 0.6)
                else:
                    r = 0.62 + (1.32 - 0.62) * (t ** 0.85) + 0.035 * (0.3 + t) * math.sin(u * math.tau * 1.5)
                    rx, ry = r, r * (0.8 + 0.2 * t)
                row.append(rm.bm.verts.new((rx * math.cos(a), ry * math.sin(a), z)))
            rows2.append(row)
        for a, b in zip(rows2, rows2[1:]):
            for i in range(12):
                rm.bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    paddle(P, (1.2, 1.0, 0.5), (1.68, 1.25, 1.3))
    # 腰の輪に人形を掛ける。人は外から選ぶので、人形は外を向く
    long_cloth(P, what)
    for i, nm in enumerate([] if EX else DOLLS):
        a = math.pi / 2 + (math.radians(36) * (i - 3) if what in "DE" else math.tau * (i - 3) / 7)
        hang(P, nm, (1.5 * math.cos(a), 1.5 * math.sin(a), hz), a - math.pi / 2)
    P.finish(fuzz=0.008)


# ---------------------------------------------------------------- C 大きな裁縫箱
def make_c():
    P = K.Parts("c")
    P.hard = {"wood": 0.012, "wood_dark": 0.012}
    W, D, H, T = 4.6, 1.5, 0.82, 0.08
    # 箱
    K.box(P, "wood_dark", (0, 0, 0.05), (W, D, 0.1))
    for sy in (-1, 1):
        K.box(P, "wood", (0, sy * (D - T) / 2, H / 2), (W, T, H))
    for sx in (-1, 1):
        K.box(P, "wood", (sx * (W - T) / 2, 0, H / 2), (T, D - 2 * T, H))
    # 仕切りと 3 つの染め液
    for x in (-W / 6, W / 6):
        K.box(P, "wood", (x, 0, H / 2 - 0.02), (T, D - 2 * T, H - 0.04))
    for role, x in (("dye_indigo", -W / 3), ("dye_rust", 0.0), ("dye_mustard", W / 3)):
        K.box(P, role, (x, 0, H - 0.12), (W / 3 - T, D - 2 * T, 0.02))
    # 前の引き出しと、ボタンのつまみ
    for x in (-W / 3, W / 3):
        K.box(P, "wood_dark", (x, D / 2 + 0.012, H / 2 - 0.05), (W / 3 - 0.18, 0.02, H - 0.34))
        K.disc(P, "button", (x, D / 2 + 0.04, H / 2 - 0.05), 0.06, 0.04, axis="Y", segs=20)
    # 真ん中の留め金と角の真鍮
    K.box(P, "brass", (0, D / 2 + 0.012, H - 0.16), (0.16, 0.02, 0.22))
    for sx in (-1, 1):
        K.box(P, "brass", (sx * (W / 2 - 0.05), D / 2 + 0.006, 0.17), (0.14, 0.02, 0.14))
        K.box(P, "brass", (sx * (W / 2 - 0.05), D / 2 + 0.006, H - 0.07), (0.14, 0.02, 0.14))
    # ふた: 後ろの蝶番で開いて、少し後ろへ倒れた壁
    LH = 3.1
    tilt = math.radians(-7)
    y0, z0 = -D / 2 - 0.02, H
    cy, cz = y0 + math.sin(-tilt) * -LH / 2, z0 + math.cos(tilt) * LH / 2
    P.m("wood")
    K.box(P, "wood", (0, cy, cz), (W, T, LH), rot=(-tilt, "X"))
    def on_lid(x, s, out):
        """ふたの内側の面の上の点。s は蝶番からの高さ、out は面から手前へ"""
        return (x, y0 + math.sin(-tilt) * -s + math.cos(tilt) * (T / 2 + out), z0 + math.cos(tilt) * s + math.sin(-tilt) * (T / 2 + out))
    # ふたの裏のキルト
    cols = ("felt_indigo", "felt_ivory", "felt_rust", "felt_moss", "felt_mustard", "felt_madder", "felt_ivory", "felt_indigo")
    nx, nz = 8, 5
    pw, ph = (W - 0.3) / nx, (LH - 0.3) / nz
    for i in range(nx):
        for j in range(nz):
            c = cols[(i * 3 + j * 5) % len(cols)]
            x = -W / 2 + 0.15 + pw * (i + 0.5)
            s = 0.15 + ph * (j + 0.5)
            K.pbox(P, c, on_lid(x, s, 0.012), (pw / 2 - 0.006, 0.04, ph / 2 - 0.006), n=7.0, nz=7.0, rot=(-tilt, Vector((1, 0, 0))), c=6)
            K.stitch_line(P, "thread", [on_lid(x - pw / 2 + 0.03, s + ph / 2 - 0.03, 0.057), on_lid(x + pw / 2 - 0.03, s + ph / 2 - 0.03, 0.057)], r=0.005, dash=0.03)
            K.stitch_line(P, "thread", [on_lid(x - pw / 2 + 0.03, s - ph / 2 + 0.03, 0.057), on_lid(x + pw / 2 - 0.03, s - ph / 2 + 0.03, 0.057)], r=0.005, dash=0.03)
    # ふたの上の取っ手と蝶番
    for sx in (-1, 1):
        K.box(P, "brass", (sx * 1.5, y0 - 0.05, H), (0.26, 0.05, 0.14))
    K.tube(P, "brass", [on_lid(-0.45, LH + 0.02, 0.0), on_lid(-0.42, LH + 0.13, 0.0), on_lid(0.42, LH + 0.13, 0.0), on_lid(0.45, LH + 0.02, 0.0)], 0.022)
    # 竿: ふたから腕木で手前へ出す。人形は染め液の真上
    y = -0.15
    K.dowel(P, "wood_dark", (-2.1, y, RAIL_Y), (2.1, y, RAIL_Y), 0.035)
    s_rail = (RAIL_Y - H) / math.cos(tilt)
    base = on_lid(0, s_rail, 0.05)
    for x in (-2.1, 2.1):
        K.dowel(P, "brass", (x, base[1], RAIL_Y), (x, y + 0.03, RAIL_Y), 0.022)
    for i, n in enumerate(DOLLS):
        hang(P, n, (-1.74 + i * 0.58, y, RAIL_Y))
    # 床に置いた大きな糸巻き（箱から出した道具）
    for x, yy, role in ((3.05, 0.8, "felt_madder"), (3.7, 0.05, "felt_indigo")):
        K.lathe(P, "wood", [(0, 0), (0.34, 0), (0.34, 0.06), (0.2, 0.09), (0.2, 0.74), (0.34, 0.77), (0.34, 0.83), (0, 0.83)], (x, yy, 0), 28, False)
        K.lathe(P, role, [(0.2, 0.09), (0.3, 0.12), (0.31, 0.42), (0.3, 0.71), (0.2, 0.74)], (x, yy, 0), 28, False)
    P.finish(fuzz=0.008)


{"A": make_a, "B": make_b, "C": make_c, "D": lambda: make_b("D"), "E": lambda: make_b("E")}[A.what]()
for role in ("wood", "wood_dark", "pole"):   # 大きな物なので、木目を広く。染め液は毛羽の照りを消す
    m = C.mat(role)
    for nd in m.node_tree.nodes:
        if nd.type == "TEX_WAVE":
            nd.inputs["Scale"].default_value *= 0.3
            nd.inputs["Distortion"].default_value *= 1.6
for role in ("dye_indigo", "dye_rust", "dye_mustard"):
    for nd in C.mat(role).node_tree.nodes:
        if nd.type == "BSDF_PRINCIPLED":
            nd.inputs["Sheen Weight"].default_value = 0.0
            nd.inputs["Specular IOR Level"].default_value = 0.15
if EX:
    K.export_all(A.export)
    sys.exit(0)
# 大きさの見本: いつもの人形を、ゲームと同じ大きさで立てる
g, _ = import_doll("kasa", scale=1.15)
SAMPLE = {"A": (-3.2, 1.7), "B": (-2.75, 1.9), "C": (-3.0, 1.9), "D": (-2.9, 1.9), "E": (-2.9, 1.9)}[A.what]
g.location = (SAMPLE[0], SAMPLE[1], 0)
g.rotation_euler = (0, 0, -0.55)

K.room(floor_size=16.0, wall_y=-2.6)
K.interior_light(0.72)
cams = {
    "A": {"hero": ((4.1, 8.4, 2.6), (0, 0, 2.15), 28), "near": ((0.9, 4.2, 1.45), (0, 0, 1.45), 30)},
    "B": {"hero": ((3.9, 8.4, 2.7), (0, 0, 2.25), 28), "near": ((1.1, 5.0, 1.45), (0, 0, 1.65), 30)},
    "D": {"hero": ((3.9, 9.0, 2.7), (0, -0.3, 2.45), 28), "near": ((1.1, 5.0, 1.45), (0, 0, 1.75), 30)},
    "E": {"hero": ((3.9, 9.0, 2.7), (0, 0, 2.55), 28), "near": ((1.1, 5.0, 1.45), (0, 0, 1.75), 30)},
    "C": {"hero": ((4.1, 8.0, 2.5), (0, 0, 1.75), 28), "near": ((0.9, 4.4, 1.45), (0, 0, 1.3), 30)},
}[A.what]
K.render_views(A, cams)
