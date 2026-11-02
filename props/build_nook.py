"""ロッジ 1 階の暖炉と、そのまわりの居場所（毛足の長いラグ・揺り椅子・ビーズクッション・大きなソファ）を Blender で組む。

2026-11-02 代表「暖炉がちゃっちい。暖炉前のベンチもなんか味気ない。まんなかに毛足の長いラグ、その周りに揺り椅子がいくつか、
ビーズクッションがいくつか、大きなソファがいくつかって感じが良い」から。

案の絵（暖炉の形 3 つと、家具の並べ方 3 つ）:

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_nook.py -- --plan 1 --views room,plan,sit \
        --prefix design/hearth-nook/proposal-1

暖炉は 3 つ。どれも裁縫の道具と材料から形を借りる（design/art-concept.md）。
  pebble: フェルトの小石を天井まで積み、炉の両脇に大きな木の糸巻き、飾り棚は木の物差し
  thimble: フェルトのレンガに、銅の指ぬきの形のフード（くぼみの点が並ぶ）、棚の縁にかぎ針のレース
  sweater: 炉のまわりはフェルトの小石、上の煙突の胸はなわ編みのセーターを着せて、脇に木のボタン
向き: 前は +Y。暖炉の前の面が Y = 0、壁は Y = -BACK。床は z = 0。単位は m（人の大きさ。2 倍しない）
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
             ("--plan", dict(default="1", help="案の番号 1・2・3")),
             ("--cpu", dict(action="store_true", help="CPU の Cycles で描く（ほかの Godot が GPU を使っていて EEVEE が進まないとき）"))])
if A.cpu:
    _setup = C.setup_render

    def _setup_cpu(size):
        _setup(size)
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 40
        sc.cycles.use_denoising = True
    C.setup_render = _setup_cpu
K.setup(A, fiber=1.5, scale=1.0)
EX = K.S["export"]
C.HEX.update({
    "felt_pebble1": "8A8178", "felt_pebble2": "A39A8C", "felt_pebble3": "6F757A", "felt_pebble4": "B8AD9A",
    "felt_pebble5": "8C6E58", "felt_mortar": "3B3532", "felt_copper": "B8703E", "felt_copper_dark": "8A4E2A",
    "felt_brick": "A4573C", "felt_brick2": "8E4A34", "felt_brick3": "B66A48", "felt_rust": "A8532E",
    "felt_mustard": "C99A3A", "felt_moss": "6E7F4A", "felt_indigo": "2E3F66", "felt_ivory": "EEE6D4",
    "felt_soot": "2A2624", "yarn_ivory": "EFE6D2", "yarn_oat": "D9C9A8", "yarn_rust": "A8532E",
    "yarn_mustard": "C99A3A", "yarn_indigo": "2E3F66", "yarn_moss": "6E7F4A", "yarn_rose": "B5636A",
    "yarn_brown": "7A5232", "thread_lace": "F4EEE2",
})

# 寸法（暖炉）
FW = 6.0        # 暖炉の幅
BACK = 2.1      # 壁から前の面まで
MANTEL = 2.75   # 飾り棚の高さ
TOP = 5.25      # 1 階の天井（lodge/dims.py の CEIL1 - FL1）
BW, BD = 4.2, 1.5   # 上の煙突の胸の幅と、壁からの奥行き
OW, OH = 2.7, 2.05  # 炉の口の幅と高さ（炉床の上から）
HEARTH_H = 0.32     # 炉床（石の台）の高さ
HEARTH_D = 1.05     # 炉床の前への張り出し


def knit_mat(role, hexcol, scale=6.0):
    """なわ編みのセーターの地: ロッジの雪と同じメリヤスの V を、毛糸の色で"""
    n = C.LM.snow(scale)
    base = C.LM.lin(hexcol)
    for nd in n.t.nodes:
        if nd.type == "MIX" and nd.data_type == "RGBA":
            nd.inputs[6].default_value = tuple(c * 0.72 for c in base[:3]) + (1,)
            nd.inputs[7].default_value = base
    n.m.name = role
    C._MAT[role] = n.m
    return n.m


knit_mat("knit_ivory", "E9DFC9", 7.0)
knit_mat("knit_oat", "CDBB98", 7.0)


def seat_mark(P, name, x, y, objs, fallback):
    """座る所の目印（ゲームの hearth_nook.gd が席にする）: 布の計算のあとの座面の上。x, y の真上から下へ探って、いちばん高い面"""
    dg = bpy.context.evaluated_depsgraph_get()
    best = None
    for o in objs:
        inv = o.matrix_world.inverted()
        org = inv @ Vector((x, y, 3.0))
        dr = (inv.to_3x3() @ Vector((0, 0, -1))).normalized()
        hit, loc, _n, _i = o.ray_cast(org, dr, depsgraph=dg)
        if hit:
            z = (o.matrix_world @ loc).z
            best = z if best is None else max(best, z)
    P.mark(name, (x, y, best if best is not None else fallback))


# ---------------------------------------------------------------- 暖炉の部品
def opening(x, z):
    """炉の口の中か（x は真ん中から、z は炉床の上から）。肩から上はアーチ"""
    if abs(x) > OW / 2:
        return False
    sh = OH - OW / 2 * 0.45
    if z < sh:
        return True
    return ((x / (OW / 2)) ** 2 + ((z - sh) / (OH - sh)) ** 2) < 1.0


def pebbles(P, rect, plane, rnd, roles, skip=None, depth=0.07, row=(0.22, 0.32), wid=(0.24, 0.46)):
    """フェルトの小石を面に積む。rect = (u0, u1, v0, v1)（v は高さ）。plane は (u, v) → 位置 と、外向きの向き"""
    to3, nrm = plane
    u0, u1, v0, v1 = rect
    v = v0
    while v < v1 - 0.05:
        h = min(rnd.uniform(*row), v1 - v)
        u = u0 - rnd.uniform(0, 0.2)
        while u < u1:
            w = rnd.uniform(*wid)
            a, b = max(u, u0), min(u + w, u1)
            cu, cv = (a + b) / 2, v + h / 2
            if b - a > 0.08 and not (skip and skip(cu, cv)):
                c = to3(cu, cv) + nrm * (depth * 0.4)
                half = Vector((0, 0, 0))
                hu, hv = (b - a) / 2 - 0.012, h / 2 - 0.012
                if abs(nrm.y) > 0.5:
                    half = (hu, depth, hv)
                else:
                    half = (depth, hu, hv)
                K.pbox(P, rnd.choice(roles), c, half, n=2.4 + rnd.random() * 0.6, nz=2.6, c=2 if EX else 4,
                       rot=(rnd.uniform(-0.06, 0.06), "Y" if abs(nrm.y) > 0.5 else "X"))
            u += w
        v += h


def bricks(P, rect, plane, rnd, roles, skip=None, bw=0.44, bh=0.17):
    """フェルトのレンガを互い違いに積む"""
    to3, nrm = plane
    u0, u1, v0, v1 = rect
    v, row = v0, 0
    while v < v1 - 0.03:
        h = min(bh, v1 - v)
        u = u0 - (bw / 2 if row % 2 else 0)
        while u < u1:
            a, b = max(u, u0), min(u + bw, u1)
            cu, cv = (a + b) / 2, v + h / 2
            if b - a > 0.05 and not (skip and skip(cu, cv)):
                c = to3(cu, cv) + nrm * 0.02
                hu, hv = (b - a) / 2 - 0.01, h / 2 - 0.01
                half = (hu, 0.045, hv) if abs(nrm.y) > 0.5 else (0.045, hu, hv)
                K.pbox(P, rnd.choice(roles), c, half, n=6.0, nz=5.0, c=3)
            u += bw
        v += h
        row += 1


def shell(P, role, depth_lo, depth_hi):
    """暖炉の芯（目地の暗いフェルト）: 下の箱と、上の煙突の胸。炉の口はあけて、中は煤けた暗いフェルト"""
    m = P.m(role)
    # 下: 口の左右と、口の上
    side = (FW - OW) / 2
    for sx in (-1, 1):
        K.box(P, role, (sx * (OW / 2 + side / 2), -depth_lo / 2, (HEARTH_H + MANTEL) / 2), (side, depth_lo - 0.02, MANTEL - HEARTH_H))
    K.box(P, role, (0, -depth_lo / 2, (HEARTH_H + OH + MANTEL) / 2), (OW, depth_lo - 0.02, MANTEL - HEARTH_H - OH))
    K.box(P, role, (0, -BACK + depth_hi / 2, (MANTEL + TOP) / 2), (BW, depth_hi, TOP - MANTEL))
    return m


def firebox(P):
    """炉の中: 奥・横・天井は煤けた暗いフェルト。底は灰の綿"""
    d = 1.15
    K.box(P, "felt_soot", (0, -d, HEARTH_H + OH / 2), (OW, 0.06, OH))
    for sx in (-1, 1):
        K.box(P, "felt_soot", (sx * (OW / 2 - 0.03), -d / 2, HEARTH_H + OH / 2), (0.06, d, OH))
    K.box(P, "felt_soot", (0, -d / 2, HEARTH_H + OH - 0.02), (OW, d, 0.06))
    K.box(P, "felt_charcoal", (0, -d / 2, HEARTH_H + 0.01), (OW, d, 0.02))


def hearth_slab(P, role="felt_pebble2", rnd=None):
    """炉床: 前へ張り出した低い石の台（腰かけられる高さより低い）。上は平たいフェルトの板石"""
    K.box(P, "felt_mortar", (0, (HEARTH_D - 0.15) / 2, HEARTH_H / 2), (FW + 0.5, HEARTH_D + 0.15, HEARTH_H - 0.02))
    rnd = rnd or random.Random(5)
    x = -FW / 2 - 0.25
    while x < FW / 2 + 0.25:
        w = rnd.uniform(0.5, 0.8)
        b = min(x + w, FW / 2 + 0.25)
        for y0, y1 in ((-0.1, HEARTH_D * 0.5), (HEARTH_D * 0.5, HEARTH_D)):
            K.pbox(P, rnd.choice((role, "felt_pebble1", "felt_pebble4")), ((x + b) / 2, (y0 + y1) / 2, HEARTH_H - 0.02),
                   ((b - x) / 2 - 0.015, (y1 - y0) / 2 - 0.015, 0.035), n=4.0, nz=2.5, c=3)
        x = b


def logs_and_fire(P, seed=0):
    """炉の中の薪（巻いたフェルト）。炎は描く画像だけ（ゲームでは flame.gd の薄葉紙の炎）"""
    rnd = random.Random(seed)
    z = HEARTH_H + 0.12
    for k, (dx, dy, dz, ang) in enumerate(((-0.35, -0.55, 0, 0.12), (0.35, -0.6, 0, -0.1), (0.0, -0.45, 0.17, 0.05),
                                            (-0.75, -0.75, 0, 0.5), (0.8, -0.7, 0, -0.45))):
        L = 0.95
        a = Vector((math.cos(ang) * L / 2, math.sin(ang) * L / 2, 0))
        c = Vector((dx, dy, z + dz))
        K.log_felt(P, c - a, c + a, 0.1, "felt_tan" if k % 2 else "felt_brown")
    if not EX:
        for k, (x, h) in enumerate(((0.0, 1.05), (-0.42, 0.75), (0.4, 0.8))):
            flame_paper(P, (x, -0.5, z + 0.12), h, h * 0.5, seed + k)


def flame_paper(P, center, h, w, seed=0):
    """薄葉紙をくしゃっと重ねた炎（描く画像だけ。game/flame.gd と同じ考え）: 赤・橙・黄の花びらを十字に"""
    rnd = random.Random(seed)
    c = Vector(center)
    for role, sc, n in (("felt_flame_r", 1.0, 5), ("felt_flame_o", 0.75, 4), ("felt_flame_y", 0.5, 3)):
        for i in range(n):
            ang = math.pi * i / n + rnd.uniform(-0.2, 0.2)
            pts = []
            for k in range(20):
                t = 2 * math.pi * k / 20
                x = w * sc * 0.5 * math.sin(t) * (1 - 0.15 * math.cos(t))
                z = h * sc * (0.5 - 0.5 * math.cos(t)) * (0.6 + 0.4 * (1 if t < math.pi else 0.9))
                pts.append((x, z))
            K.extrude(P, role, pts, -0.004, 0.004, plane="XZ", offset=tuple(c), rot=(ang, "Z"))


def spool(P, center, h, r_core, r_flange, thread_role, rnd):
    """大きな木の糸巻き: 上下のつば、芯に糸が巻いてある（巻いた糸の筋）"""
    c = Vector(center)
    fl = 0.08
    for z in (fl / 2, h - fl / 2):
        K.disc(P, "wood", c + Vector((0, 0, z)), r_flange, fl, segs=40)
    K.lathe(P, "wood", [(0.0, fl), (r_core * 0.8, fl), (r_core * 0.8, h - fl), (0.0, h - fl)], center=tuple(c), segs=28)
    # 巻いた糸: 少しふくらんだ胴と、斜めに巻いた筋
    rt = r_core + 0.06
    prof = [(0.0, fl + 0.01)] + [(rt + 0.02 * math.sin(math.pi * t / 10), fl + 0.01 + (h - 2 * fl - 0.02) * t / 10) for t in range(11)] + [(0.0, h - fl - 0.01)]
    K.lathe(P, thread_role, prof, center=tuple(c), segs=36)
    turns = 26
    pts = []
    for k in range(turns * 24 + 1):
        t = k / (turns * 24)
        a = 2 * math.pi * turns * t
        z = fl + 0.03 + (h - 2 * fl - 0.06) * t
        rr = rt + 0.02 * math.sin(math.pi * t) + 0.004
        pts.append(c + Vector((rr * math.cos(a), rr * math.sin(a), z)))
    K.tube(P, thread_role, pts, 0.008, sides=4, caps=False)


def ruler(P, center, length, depth, thick):
    """木の物差しの飾り棚: 前の縁に目盛り（5 cm ごとに短い線、50 cm ごとに長い線）"""
    c = Vector(center)
    P.hard["wood_light"] = 0.01
    K.box(P, "wood_light", c, (length, depth, thick))
    n = int(length / 0.05)
    for i in range(1, n):
        x = -length / 2 + i * 0.05
        L = 0.09 if i % 10 == 0 else (0.06 if i % 2 == 0 else 0.035)
        K.box(P, "wood_dark", c + Vector((x, depth / 2 + 0.002, thick / 2 - L / 2 - 0.01)), (0.006, 0.004, L))


def lace_edge(P, x0, x1, y, z, scallop=0.12):
    """かぎ針のレースの縁: 扇の輪を並べ、輪の中に小さな輪"""
    n = int((x1 - x0) / scallop)
    for i in range(n):
        cx = x0 + (i + 0.5) * scallop
        pts = [(cx + scallop / 2 * math.cos(a), y, z - scallop * 0.45 * math.sin(a))
               for a in [math.pi * k / 10 for k in range(11)]]
        K.tube(P, "thread_lace", pts, 0.006, sides=4, caps=False)
        K.ring(P, "thread_lace", (cx, y, z - scallop * 0.22), scallop * 0.13, 0.004, axis="Y", n=12)


def thimble_hood(P, z0, z1, r0, r1, rnd):
    """銅の指ぬきの形のフード（壁に半分を寄せた半円）: 上ほど細く、てっぺんは丸み。くぼみの点が並び、裾は縁を巻く"""
    m = P.m("felt_copper")
    n0 = len(m.bm.verts)
    segs, rows = 180, 120   # くぼみ 1 つに 4 目ほど（書き出しでも、焼く元は細かく）
    cy = -BACK
    grid = []
    for j in range(rows + 1):
        t = j / rows
        z = z0 + (z1 - z0) * t
        r = r0 + (r1 - r0) * t ** 1.4
        ring = []
        for i in range(segs + 1):
            a = math.pi * i / segs     # 0..π（壁の前の半分）
            # くぼみ: 互い違いの点の並び（裾の 12% と上端は平ら）
            d = 0.0
            if 0.12 < t < 0.97:
                u = a * r / 0.2
                v = (z - z0) / 0.2
                fu, fv = u - math.floor(u + (0.5 if int(math.floor(v)) % 2 else 0.0)), v - math.floor(v)
                rr = (fu - 0.5) ** 2 + (fv - 0.5) ** 2
                d = 0.05 * max(0.0, 1 - rr / 0.1)
            ring.append(m.bm.verts.new((math.cos(a) * (r - d), cy + math.sin(a) * (r - d), z)))
        grid.append(ring)
    for j in range(rows):
        for i in range(segs):
            m.bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    # 裾の巻いた縁
    pts = [(math.cos(math.pi * k / 48) * (r0 + 0.03), cy + math.sin(math.pi * k / 48) * (r0 + 0.03), z0 + 0.02) for k in range(49)]
    K.tube(P, "felt_copper_dark", pts, 0.05, sides=10)


def cable_knit_breast(P, rnd):
    """煙突の胸に着せた、なわ編みのセーター: 編み地の箱、縦のなわ（2 本を撚った太い畝）、裾のゴム編み、脇の木のボタン"""
    y_front = -BACK + BD
    knit, rib = "knit_ivory", "knit_oat"
    z0, z1 = MANTEL + 0.35, TOP
    K.pbox(P, knit, (0, y_front - BD / 2 + 0.05, (z0 + z1) / 2), (BW / 2 + 0.14, BD / 2 + 0.06, (z1 - z0) / 2 + 0.04), n=8.0, nz=12.0)
    # 裾のゴム編み（縦の畝）
    K.pbox(P, rib, (0, y_front - BD / 2 + 0.05, MANTEL + 0.2), (BW / 2 + 0.1, BD / 2 + 0.06, 0.2), n=8.0, nz=6.0)
    for i in range(int((BW + 0.2) / 0.07)):
        x = -BW / 2 - 0.1 + 0.035 + i * 0.07
        K.tube(P, rib, [(x, y_front + 0.1, MANTEL + 0.03), (x, y_front + 0.1, MANTEL + 0.37)], 0.022, sides=6)
    # 縦のなわ: 2 本の太い毛糸を撚って 1 本の畝に
    for cx in (-1.35, -0.45, 0.45, 1.35):
        for ph in (0.0, math.pi):
            pts = []
            for k in range(140):
                z = z0 + 0.05 + (z1 - z0 - 0.1) * k / 139
                a = (z - z0) / 0.34 * math.pi + ph
                pts.append((cx + 0.11 * math.sin(a), y_front + 0.09 + 0.05 * math.cos(a), z))
            K.tube(P, knit, pts, 0.07, sides=8, ry=0.055)
        for sx in (-1, 1):   # なわの両脇の細い畝（裏目）
            K.tube(P, rib, [(cx + sx * 0.26, y_front + 0.06, z0 + 0.04), (cx + sx * 0.26, y_front + 0.06, z1 - 0.04)], 0.03, sides=6)
    # 脇の打ち合わせと木のボタン
    for k in range(5):
        z = z0 + 0.45 + k * 0.42
        K.disc(P, "button", (BW / 2 + 0.06, y_front - 0.35, z), 0.11, 0.05, axis="X", segs=24)
        for dy, dz in ((0.03, 0.03), (-0.03, -0.03), (0.03, -0.03), (-0.03, 0.03)):
            K.disc(P, "felt_soot", (BW / 2 + 0.088, y_front - 0.35 + dy, z + dz), 0.012, 0.01, axis="X", segs=8)


def fireplace(name, kind):
    """ロッジの真ん中の大きな暖炉。前は +Y、前の面が Y = 0"""
    P = K.Parts(name, kind="hearth")
    rnd = random.Random({"pebble": 3, "thimble": 7, "sweater": 11}[kind])
    shell(P, "felt_mortar", BACK, BD)
    firebox(P)
    hearth_slab(P, rnd=rnd)
    front = (lambda u, v: Vector((u, 0.0, v)), Vector((0, 1, 0)))
    breast = (lambda u, v: Vector((u, -BACK + BD, v)), Vector((0, 1, 0)))
    left = (lambda u, v: Vector((-FW / 2, -u, v)), Vector((-1, 0, 0)))
    right = (lambda u, v: Vector((FW / 2, -u, v)), Vector((1, 0, 0)))
    bleft = (lambda u, v: Vector((-BW / 2, -u, v)), Vector((-1, 0, 0)))
    bright = (lambda u, v: Vector((BW / 2, -u, v)), Vector((1, 0, 0)))
    in_mouth = lambda u, v: opening(u, v - HEARTH_H)   # noqa: E731
    stones = ["felt_pebble1", "felt_pebble2", "felt_pebble3", "felt_pebble4", "felt_pebble5"]
    low = (-FW / 2, FW / 2, HEARTH_H, MANTEL)
    if kind in ("pebble", "sweater"):
        pebbles(P, low, front, rnd, stones, skip=in_mouth)
        for pl in (left, right):
            pebbles(P, (0.0, BACK, HEARTH_H, MANTEL), pl, rnd, stones)
        if kind == "pebble":
            pebbles(P, (-BW / 2, BW / 2, MANTEL + 0.18, TOP), breast, rnd, stones)
            for pl in (bleft, bright):
                pebbles(P, (BACK - BD, BACK, MANTEL + 0.18, TOP), pl, rnd, stones)
        # アーチの要石: 口のまわりに放射に並べた細長い小石
        sh = HEARTH_H + OH - OW / 2 * 0.45
        for k in range(11):
            a = math.pi * k / 10
            rx, rz = OW / 2 + 0.17, OH - (OH - OW / 2 * 0.45) + 0.17
            c = Vector((rx * math.cos(a), 0.06, sh + rz * math.sin(a)))
            K.pbox(P, rnd.choice(stones[:4]), c, (0.11, 0.09, 0.2), n=2.6, nz=2.6, c=3, rot=(a - math.pi / 2, "Y"))
    else:   # thimble: フェルトのレンガ
        reds = ["felt_brick", "felt_brick2", "felt_brick3", "felt_rust"]
        bricks(P, low, front, rnd, reds, skip=in_mouth)
        for pl in (left, right):
            bricks(P, (0.0, BACK, HEARTH_H, MANTEL), pl, rnd, reds)
        bricks(P, (-BW / 2, BW / 2, MANTEL + 0.18, TOP), breast, rnd, reds)   # 煙突の胸もレンガ（フードの後ろと脇に見える）
        for pl in (bleft, bright):
            bricks(P, (BACK - BD, BACK, MANTEL + 0.18, TOP), pl, rnd, reds)
        sh = HEARTH_H + OH - OW / 2 * 0.45   # 口のアーチ: 放射のレンガ
        for k in range(15):
            a = math.pi * k / 14
            c = Vector(((OW / 2 + 0.12) * math.cos(a), 0.05, sh + (OW / 2 * 0.45 + 0.12) * math.sin(a)))
            K.pbox(P, rnd.choice(reds), c, (0.07, 0.07, 0.17), n=6.0, nz=5.0, c=3, rot=(a - math.pi / 2, "Y"))
        thimble_hood(P, MANTEL + 0.5, TOP + 0.02, BW / 2 + 0.25, BW / 2 - 0.55, rnd)
    # 飾り棚
    if kind == "pebble":
        ruler(P, (0, 0.12, MANTEL + 0.08), FW + 0.4, 0.5, 0.16)
        for sx in (-1, 1):   # 口の両脇の大きな木の糸巻き（炉床の上に立つ）
            spool(P, (sx * (OW / 2 + 0.5), 0.32, HEARTH_H), MANTEL - HEARTH_H - 0.04, 0.2, 0.44,
                  "yarn_rust" if sx < 0 else "yarn_indigo", rnd)
    elif kind == "thimble":
        P.hard["wood"] = 0.012
        K.box(P, "wood", (0, 0.1, MANTEL + 0.08), (FW + 0.4, 0.46, 0.16))
        lace_edge(P, -FW / 2 - 0.15, FW / 2 + 0.15, 0.335, MANTEL + 0.0)
    else:
        P.hard["wood_dark"] = 0.012
        K.box(P, "wood_dark", (0, 0.1, MANTEL + 0.08), (FW + 0.4, 0.46, 0.18))
        cable_knit_breast(P, rnd)
    logs_and_fire(P, seed=rnd.randint(0, 99))
    P.mark("fire_at", (0, -0.4, HEARTH_H + 0.6))   # 炉の中のまんなか（灯りはロッジの light_fire。props.gd が灯りを足さない名前）
    P.finish(fuzz=0.004)
    return P.root


# ---------------------------------------------------------------- ラグ
def shag_rug(name, rx, ry, pattern):
    """毛足の長いラグ: フェルトの土台に、毛糸の房を植える（房は 2 本の糸が立ち上がって倒れる）。
    pattern: cream（生成り一色）・rings（同心の輪）・rya（北欧のリヤ。菱形の柄）"""
    P = K.Parts(name, kind="rug")
    rnd = random.Random(len(name))
    base = {"cream": "felt_ivory", "rings": "felt_mustard", "rya": "felt_indigo"}[pattern]
    K.extrude(P, base, K.circle_poly(1.0, 64, sx=rx, sy=ry), 0.0, 0.02)

    def col(x, y):
        e = math.hypot(x / rx, y / ry)
        if pattern == "cream":
            return "yarn_ivory" if rnd.random() < 0.8 else "yarn_oat"
        if pattern == "rings":
            k = int(e * 6)
            return ["yarn_ivory", "yarn_mustard", "yarn_ivory", "yarn_rust", "yarn_oat", "yarn_rust"][min(k, 5)]
        u = abs(x) / 0.55 + abs(y) / 0.55   # 菱形
        k = int(u) % 4
        if e > 0.86:
            return "yarn_indigo"
        return ["yarn_rose", "yarn_mustard", "yarn_ivory", "yarn_moss"][k] if rnd.random() < 0.9 else "yarn_ivory"
    step = 0.075 if EX else 0.055
    y = -ry
    while y < ry:
        x = -rx
        while x < rx:
            px, py = x + rnd.uniform(-step * 0.4, step * 0.4), y + rnd.uniform(-step * 0.4, step * 0.4)
            if (px / rx) ** 2 + (py / ry) ** 2 < 0.97:
                role = col(px, py)
                L = rnd.uniform(0.12, 0.17)
                for s in range(2):
                    a = rnd.uniform(0, 2 * math.pi)
                    d = Vector((math.cos(a), math.sin(a), 0))
                    p0 = Vector((px, py, 0.015))
                    pts = [p0, p0 + Vector((0, 0, L * 0.45)) + d * L * 0.15, p0 + Vector((0, 0, L * 0.6)) + d * L * 0.5,
                           p0 + Vector((0, 0, L * 0.45)) + d * L * 0.85]
                    K.tube(P, role, pts, 0.013, sides=4)
            x += step
        y += step
    P.finish()
    return P.root


# ---------------------------------------------------------------- 揺り椅子
def rocking_chair(name, role, throw_role):
    """揺り椅子: 曲げ木の弓の脚（揺れる）、背の細い棒は編み棒（頭に丸い玉）、座に編んだ座布団、背に掛けたモチーフ編みの膝掛け"""
    P = K.Parts(name, kind="rocker")
    for r in ("wood", "wood_dark", "wood_bent"):
        P.hard[r] = 0.006
    W, D, SZ = 0.68, 0.56, 0.44
    R = 1.4   # 弓の半径
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.01)
        pts = []
        for k in range(17):
            t = -0.5 + k / 16
            ang = t * 0.95
            pts.append((x, R * math.sin(ang) - 0.05, R - R * math.cos(ang) + 0.035))
        K.tube(P, "wood_bent", pts, 0.045, sides=8, ry=0.028)
        for sy in (-1, 1):   # 脚: 弓から座へ
            y = sy * (D / 2 - 0.05)
            K.dowel(P, "wood", (x * 0.97, y, R - math.sqrt(R * R - (y + 0.05) ** 2) + 0.04), (x * 0.95, y, SZ), 0.024)
        K.dowel(P, "wood", (x * 0.97, -D / 2 + 0.05, 0.18), (x * 0.97, D / 2 - 0.05, 0.18), 0.014)   # 貫
    K.box(P, "wood", (0, 0, SZ - 0.02), (W + 0.04, D, 0.04))
    # 背: 2 本の柱（編み棒）と、あいだの細い棒、上の笠木
    back_t = -0.2
    top = SZ + 0.86
    for sx in (-1, 1):
        p0 = Vector((sx * (W / 2 - 0.02), -D / 2 + 0.03, SZ - 0.03))
        p1 = Vector((sx * (W / 2 - 0.04), -D / 2 - 0.15, top + 0.04))
        K.dowel(P, "wood", p0, p1, 0.03)
        K.lathe(P, "felt_red" if sx < 0 else "felt_mustard", [(0.0, -0.045), (0.035, -0.03), (0.045, 0.0), (0.035, 0.03), (0.0, 0.045)],
                center=tuple(p1 + Vector((0, 0, 0.045))), segs=16)   # 編み棒の頭の玉
    for i in range(5):
        x = -W / 2 + 0.13 + i * (W - 0.26) / 4
        K.dowel(P, "wood_light", (x, -D / 2 + 0.02, SZ + 0.02), (x * 0.96, -D / 2 - 0.13, top - 0.04), 0.016)
    pts = [(x, -D / 2 - 0.14 - 0.03 * (1 - (x / (W / 2)) ** 2), top) for x in [(-W / 2 + 0.02) + k * (W - 0.04) / 10 for k in range(11)]]
    K.tube(P, "wood", pts, 0.035, sides=8, ry=0.05)
    # ひじ掛け
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.01)
        K.tube(P, "wood", [(x, -D / 2 - 0.05, SZ + 0.25), (x, 0.0, SZ + 0.24), (x, D / 2 + 0.02, SZ + 0.22)], 0.03, sides=8, ry=0.02)
        K.dowel(P, "wood", (x, D / 2 - 0.05, SZ), (x, D / 2 - 0.02, SZ + 0.22), 0.018)
    fl = K.collider_box((0, 0, SZ - 0.01), (W + 0.04, D, 0.02))
    back = K.collider_box((0, -D / 2 - 0.07, SZ + 0.36), (W, 0.06, 0.72))
    seat = K.cushion(P, "seat", role, (0, 0.02, SZ + 0.07), (W - 0.06, D - 0.06, 0.08), pressure=2.5, colliders=[fl, back],
                     tuft=True, cuts_n=10)
    # 背に掛けたモチーフ編みの膝掛け: 上を笠木に留めて垂らす
    if not EX:
        bar = K.collider_box((0, -D / 2 - 0.16, top), (W, 0.08, 0.08))
        o = K.cloth_grid("%s_throw" % name, throw_role, 0.7, 0.75, 22, 24, (0, -D / 2 - 0.08, top + 0.06))
        o.rotation_euler = (math.radians(70), 0, 0)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        K.cloth_sim(o, [bar, back, fl], frames=35, pin=lambda p: p.z > top + 0.05 and abs(p.y - (-D / 2 - 0.12)) < 0.12,
                    solidify=0.008)
        o.parent = P.root
        P.parts.append(o)
        K.drop(bar)
    for c in (fl, back):
        K.drop(c)
    seat_mark(P, "seat_0", 0, 0.02, [seat], SZ + 0.1)
    P.finish(fuzz=0.003)
    return P.root


# ---------------------------------------------------------------- ビーズクッション
def beanbag(name, role):
    """ビーズクッション: 大きな布の袋に、綿とビーズ。床に落として裾が広がり、上に座った形のくぼみ（布の計算）。
    縫い目を一周かがり、後ろに持ち手のループ"""
    P = K.Parts(name, kind="beanbag")
    m = C.M("%s_bag" % name, role)
    bmesh.ops.create_uvsphere(m.bm, u_segments=40, v_segments=24, radius=1.0,   # 書き出しでも同じ細かさ（粗いと袋がつぶれない）
                              matrix=Matrix.Translation((0, 0, 0.55)) @ Matrix.Diagonal((0.6, 0.58, 0.52, 1)))
    if role in C.PATCH:
        C.box_uv(m, 1.0)
        m.uv_set = True
    o = m.done(smooth=True)
    fl = K.collider_box((0, 0, -0.01), (3, 3, 0.02))
    seat = K.collider_box((0, 0.08, 0.95), (0.42, 0.42, 0.3))   # 座った形: 上から押す（計算のあいだ下へ動かす）
    seat.animation_data_create()
    seat.location = (0, 0.08, 0.95)
    seat.keyframe_insert("location", frame=1)
    seat.location = (0, 0.08, 0.62)
    seat.keyframe_insert("location", frame=40)
    K.cloth_sim(o, [fl, seat], frames=60, pressure=1.1, mass=0.4, stiff=10.0, bend=0.15, thickness=0.006, subsurf=1)
    o.parent = P.root
    P.parts.append(o)
    K.drop(fl)
    K.drop(seat)
    # 後ろの持ち手
    K.tube(P, "felt_brown" if role != "felt_brown" else "felt_tan",
           [(-0.09, -0.42, 0.55), (-0.08, -0.5, 0.62), (0.0, -0.53, 0.65), (0.08, -0.5, 0.62), (0.09, -0.42, 0.55)], 0.018,
           sides=6, ry=0.008)
    seat_mark(P, "seat_0", 0, 0.08, [o], 0.36)
    P.finish(fuzz=0.004)
    return P.root


# ---------------------------------------------------------------- 大きなソファ
def big_sofa(name, role, seats=3, throw_role=None, pillows=()):
    """大きなソファ: 綿を詰めたふっくらした胴（下に木の丸い足）、太く巻いたひじ、厚い座と背のクッション（布の計算）、
    ひじに掛けた膝掛けと、飾りのクッション"""
    P = K.Parts(name, kind="sofa")
    P.hard["wood_dark"] = 0.01
    CW = 0.9
    W, D = CW * seats + 0.5, 1.2
    BASE = 0.3   # 胴の上（座のクッションの下）
    for sx in (-1, 0, 1) if seats > 3 else (-1, 1):
        for sy in (-1, 1):
            K.lathe(P, "wood_dark", [(0.0, 0.0), (0.045, 0.0), (0.055, 0.04), (0.04, 0.08), (0.0, 0.08)],
                    center=(sx * (W / 2 - 0.12), sy * (D / 2 - 0.12), 0.0), segs=16)
    K.pbox(P, role, (0, 0, (0.07 + BASE) / 2 + 0.01), (W / 2, D / 2, (BASE - 0.07) / 2 + 0.02), n=8.0, nz=4.0,
           seam_role="thread")
    # ひじ: ふっくらした箱の上に、太い巻き
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.15)
        K.pbox(P, role, (x, 0.02, BASE + 0.2), (0.15, D / 2, 0.22), n=5.0, nz=4.0)
        K.lathe(P, role, [(0.0, -D / 2 - 0.02), (0.15, -D / 2 - 0.02), (0.19, -D / 2 + 0.05), (0.19, D / 2 - 0.02),
                          (0.15, D / 2 + 0.04), (0.0, D / 2 + 0.04)],
                center=(x + sx * 0.02, 0.0, BASE + 0.44), segs=24, rot=(math.pi / 2, "X"))
        K.stitch_ring(P, "thread", (x + sx * 0.02, D / 2 + 0.045, BASE + 0.44), 0.12, axis="Y")
    # 背の板（胴の後ろ）
    K.pbox(P, role, (0, -D / 2 + 0.13, BASE + 0.4), (W / 2 - 0.3, 0.13, 0.42), n=6.0, nz=4.0)
    fl = K.collider_box((0, 0, BASE - 0.01), (W, D, 0.02))
    side = [K.collider_box((sx * (W / 2 - 0.15), 0, BASE + 0.3), (0.32, D, 0.6)) for sx in (-1, 1)]
    back = K.collider_box((0, -D / 2 + 0.13, BASE + 0.4), (W - 0.6, 0.26, 0.84))
    by = -D / 2 + 0.36
    for i in range(seats):
        x = -W / 2 + 0.3 + CW * (i + 0.5) - 0.05 * (i - (seats - 1) / 2) / max(1, seats - 1) * 0
        cu = K.cushion(P, "seat%d" % i, role, (x, 0.1, BASE + 0.12), (CW - 0.03, D - 0.36, 0.17), pressure=3.2,
                       colliders=[fl] + side + [back], cuts_n=12)
        K.cushion(P, "back%d" % i, role, (x, by, BASE + 0.56), (CW - 0.03, 0.22, 0.6), pressure=3.4,
                  pin=lambda p, by=by: p.y < by - 0.07, colliders=side, cuts_n=12)
        seat_mark(P, "seat_%d" % i, x, 0.12, [cu], BASE + 0.2)
    for k, pr in enumerate(pillows):
        x = (-W / 2 + 0.55) if k == 0 else (W / 2 - 0.55)
        K.pbox(P, pr, (x, -0.06, BASE + 0.42), (0.2, 0.07, 0.2), n=3.0, nz=3.0, seam_role="thread",
               rot=((-0.35, "X"), (0.35 * (1 if k else -1), "Y")))
    if throw_role and not EX:   # ひじに掛けた膝掛け（ガーター編みの毛布）
        x = -W / 2 + 0.13
        arm = K.collider_box((x, 0.0, BASE + 0.44), (0.4, D + 0.06, 0.38))
        o = K.cloth_grid("%s_throw" % name, throw_role, 0.6, 0.9, 20, 26, (x, 0.0, BASE + 0.7))
        K.cloth_sim(o, [arm, fl] + side, frames=40, solidify=0.01)
        o.parent = P.root
        P.parts.append(o)
        K.drop(arm)
    for c in [fl, back] + side:
        K.drop(c)
    P.finish(fuzz=0.003)
    return P.root


# ---------------------------------------------------------------- 薪のかごと灯り（脇役）
def log_basket(name):
    """麻ひもを巻き上げたかごに、巻いたフェルトの薪"""
    P = K.Parts(name, kind="prop")
    K.lathe(P, "hemp", [(0.0, 0.0), (0.3, 0.0), (0.34, 0.15), (0.35, 0.42), (0.31, 0.42), (0.3, 0.03), (0.0, 0.03)], segs=32)
    for z in [0.03 + 0.035 * k for k in range(12)]:
        K.ring(P, "hemp", (0, 0, z), 0.305 + 0.04 * z / 0.42, 0.016, n=32)
    rnd = random.Random(2)
    for k in range(7):
        a = 2 * math.pi * k / 7
        x, y = 0.16 * math.cos(a), 0.16 * math.sin(a)
        K.log_felt(P, (x, y, 0.04), (x + rnd.uniform(-0.05, 0.05), y + rnd.uniform(-0.05, 0.05), 0.62), 0.07,
                   "felt_tan" if k % 2 else "felt_brown")
    P.finish(fuzz=0.003)
    return P.root


# kit に巻いたフェルトの薪の部品がないので、ここで足す（build_hearth.py の log と同じ）
def _log_felt(P, p0, p1, r, role="felt_tan", end_role="felt_brown"):
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
        K.tube(P, end_role if role != end_role else "felt_tan", sp, r * 0.045, sides=4)


K.log_felt = _log_felt


# ---------------------------------------------------------------- 並べ方（案）
# 暖炉の前の面のまんなかが原点。+Y が部屋の側（ロッジでは南）。[品物, x, y, 向き（度。0 で +Y を向く）]
FIRE_AT = Vector((0.0, 4.2))   # ラグのまんなか

PLANS = {
    "1": dict(fire="pebble", rug=("cream", 2.5, 1.75), title="案 1 向かい合わせ", items=[
        ("sofa_a", -3.75, 4.2, -90), ("sofa_b", 3.75, 4.2, 90),
        ("rocker_a", -2.35, 1.85, -125), ("rocker_b", 2.35, 1.85, 125),
        ("bean_a", -1.25, 5.55, 175), ("bean_b", 0.15, 5.85, 180), ("bean_c", 1.45, 5.5, 185),
        ("basket", -3.6, 0.55, 0),
    ]),
    "2": dict(fire="thimble", rug=("rings", 2.4, 1.8), title="案 2 コの字", items=[
        ("sofa_c", 0.0, 7.0, 180), ("sofa_a", -4.0, 4.2, -90), ("sofa_b", 4.0, 4.2, 90),
        ("rocker_a", -3.85, 1.3, -140), ("rocker_b", 3.85, 1.3, 140),
        ("bean_a", -1.45, 2.65, 195), ("bean_b", 0.05, 2.35, 180), ("bean_c", 1.5, 2.7, 165),
        ("basket", 3.75, 0.45, 0),
    ]),
    "3": dict(fire="sweater", rug=("rya", 2.6, 1.9), title="案 3 半円", items=[
        ("sofa_a", -3.45, 5.9, -125), ("sofa_b", 3.45, 5.9, 125),
        ("rocker_a", -3.6, 1.7, -110), ("rocker_b", 3.6, 1.7, 110), ("rocker_c", 0.0, 7.4, 180),
        ("bean_a", -1.3, 3.1, 200), ("bean_b", 1.3, 3.1, 160), ("bean_c", -0.65, 4.85, 185), ("bean_d", 0.85, 4.95, 175),
        ("basket", -3.7, 0.5, 0),
    ]),
}


def dup(root, loc, rot_deg):
    """品物（根元と部品）を写して置く。形は使い回す"""
    new_root = root.copy()
    C.coll("prop").objects.link(new_root)
    for o in K.descendants(root):
        if o.parent == root:
            c = o.copy()
            c.parent = new_root
            for col in o.users_collection:
                col.objects.link(c)
    new_root.location = (loc[0], loc[1], 0)
    new_root.rotation_euler = (0, 0, math.radians(rot_deg))
    return new_root


def room():
    """描く画像だけ: 板の床と、巻いたフェルトの丸太の北の壁（ロッジと同じ素材）"""
    fl = C.M("floor", "floor", "stage")
    bmesh.ops.create_grid(fl.bm, x_segments=2, y_segments=2, size=1.0,
                          matrix=Matrix.Translation((0, 4.0, 0)) @ Matrix.Diagonal((11, 9, 1, 1)))
    C.plan_uv(fl)
    fl.done(smooth=False)
    wall = C.M("wall_logs", "log", "stage")
    r = 0.18
    z = r
    while z < TOP + 0.3:
        C.tube(wall, [Vector((-11, -BACK - r, z)), Vector((11, -BACK - r, z))], r, sides=16)
        z += 2 * r * 0.95
    wall.done()
    for sx in (-1, 1):   # 東西の壁（奥行きを見せる）
        side = C.M("wall_side", "log", "stage")
        z = r
        while z < TOP + 0.3:
            C.tube(side, [Vector((sx * 9.5, -BACK - r, z)), Vector((sx * 9.5, 12.0, z))], r, sides=16)
            z += 2 * r * 0.95
        side.done()


def calm_flames():
    """描く画像の炎: 光を抑えて、薄葉紙の赤・橙・黄に見えるように"""
    for m in bpy.data.materials:
        if m.name.startswith("felt_flame") and m.node_tree:
            for nd in m.node_tree.nodes:
                if nd.type == "BSDF_PRINCIPLED":
                    nd.inputs["Emission Strength"].default_value = 0.12


if A.export:
    # ゲームの品物（game/props/nook/）。暖炉は --plan の案のもの。ラグは game/hearth_nook.gd が毛足を作る
    made = [(fireplace("fireplace_%s" % PLANS[A.plan]["fire"], PLANS[A.plan]["fire"]), 40000),   # 小石 1 つに 60 三角ほど
            (big_sofa("sofa_patch", "patch_warm", 4, None, ("felt_indigo", "felt_rust")), 6000),
            (big_sofa("sofa_rust", "felt_rust", 4, None, ("felt_ivory", "felt_mustard")), 6000),
            (rocking_chair("rocker_indigo", "felt_indigo", None), 3000),
            (beanbag("bean_mustard", "felt_mustard"), 1600),
            (beanbag("bean_patch", "patch_mix"), 1600),
            (log_basket("log_basket"), 1500)]
    for r, tris in made:
        r["tris"] = tris
    K.export_all(A.export, A.only.split(",") if A.only else None)

if not A.export:
    plan = PLANS[A.plan]
    fp = fireplace("fireplace_%s" % plan["fire"], plan["fire"])
    rug = shag_rug("rug_%s" % plan["rug"][0], plan["rug"][1], plan["rug"][2], plan["rug"][0])
    rug.location = (FIRE_AT.x, FIRE_AT.y, 0)
    src = {
        "sofa_a": big_sofa("sofa_patch", "patch_warm", 4, "felt_mustard", ("felt_indigo", "felt_rust")),
        "sofa_b": big_sofa("sofa_rust", "felt_rust", 4, "patch_cool", ("felt_ivory", "felt_mustard")),
        "rocker_a": rocking_chair("rocker_indigo", "felt_indigo", "patch_rose"),
        "bean_a": beanbag("bean_mustard", "felt_mustard"),
        "bean_b": beanbag("bean_patch", "patch_mix"),
        "basket": log_basket("log_basket"),
    }
    if any(it[0] == "sofa_c" for it in plan["items"]):
        src["sofa_c"] = big_sofa("sofa_moss", "felt_moss", 4, "felt_ivory", ("patch_rose", "felt_mustard"))
    used = set()
    for key, x, y, ang in plan["items"]:
        base = key if key in src else {"rocker_b": "rocker_a", "rocker_c": "rocker_a", "bean_c": "bean_a", "bean_d": "bean_b"}[key]
        r = src[base]
        if base in used:
            dup(r, (x, y), ang)
        else:
            r.location = (x, y, 0)
            r.rotation_euler = (0, 0, math.radians(ang))
            used.add(base)
    room()
    calm_flames()
    for kind, x, y in (("kasa", 1.9, 6.9), ("golem", -2.2, 7.4)):   # 大きさの目安に、人形を立たせる
        bpy.ops.import_scene.gltf(filepath=os.path.join(C.ROOT, "game", "person", kind + ".glb"))
        for o in bpy.context.selected_objects:
            if o.parent is None:
                o.location = (x, y, 0)
                o.rotation_euler = (0, 0, math.pi)
    K.interior_light(0.45)
    bpy.context.scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.12, 0.09, 1)
    for o in [o for o in bpy.data.objects if o.name.startswith("fire_at")]:
        L = bpy.data.objects.new("fire", bpy.data.lights.new("fire", "POINT"))
        C.coll("stage").objects.link(L)
        L.location = o.matrix_world.translation + Vector((0, 0.6, 0.2))
        L.data.energy = 600
        L.data.color = (1.0, 0.55, 0.25)
        L.data.shadow_soft_size = 0.5
    cams = {
        "room": ((5.4, 11.2, 3.5), (0.0, 2.6, 1.1), 22),
        "plan": ((0.0, 3.4, 24.0), (0.0, 3.41, 0.0), 42),
        "sit": ((0.2, 6.6, 1.05), (0.0, 0.0, 1.6), 24),
    }
    K.render_views(A, cams)
