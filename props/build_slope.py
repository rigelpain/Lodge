"""斜面の小物を Blender で組む。スピーカーの柱、コースの旗、毛糸の安全ネット、案内板。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_slope.py -- \
        --views line,speaker,sign,net --prefix props/renders/08-slope

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_slope.py -- \
        --look flat --export game/props

どれも木の棒にフェルトと毛糸を縫い付けた手芸作品。木や岩と同じく、20 cm の作品を引き伸ばした縮尺で、
縫い目と縁を太めにする。案内板は文字を使わず、型紙の記号のような矢印とアイコンのアップリケだけ。
スピーカーはラッパ型（design/sound-concept.md の「柱 1」）。ラッパの口の位置と向きを目印に入れる。
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

A = C.parse()
C.reset()
C.LOOK["v"] = A.look
if A.export:   # 焼き込み: 素材は描くときと同じに組む
    K.baking_mode()
TRIS = 1500   # 斜面の小物 1 つの三角の目安
EXPORT = bool(A.export)
DAY = A.look == "day"
made = []


def new_root(name, **extras):
    r = bpy.data.objects.new(name, None)
    C.coll("prop").objects.link(r)
    for k, v in extras.items():
        r[k] = v
    return r


def marker(name, loc, parent, parts):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    e.parent = parent
    C.coll("prop").objects.link(e)
    parts.append(e)
    return e


def snow_puff(name, center, rx, rz, parent, n=5, seed=0):
    """柱や板の上に積もった綿"""
    rnd = random.Random(seed)
    balls = [(Vector(center), rx * 0.8, (1.0, 1.0, rz / rx))]
    for i in range(n):
        a = 2 * math.pi * i / n + rnd.uniform(-0.3, 0.3)
        balls.append((Vector(center) + Vector((math.cos(a) * rx * 0.6, math.sin(a) * rx * 0.6, -rz * 0.3)), rx * 0.5))
    o = C.metablob(name, "cotton", balls, rx * (0.12 if EXPORT else 0.05), parent, lumps=0.12)
    if DAY:
        C.fuzz(o, rx * 0.12)
    return o


def snow_ring(name, center, r, parent, seed=0):
    """棒の根元の雪のふくらみ"""
    rnd = random.Random(seed)
    balls = []
    for i in range(9):
        a = 2 * math.pi * i / 9 + rnd.uniform(-0.2, 0.2)
        balls.append((Vector(center) + Vector((math.cos(a) * r, math.sin(a) * r, 0)), r * rnd.uniform(0.55, 0.8),
                      (1.4, 1.0, 0.55), a + math.pi / 2))
    o = C.metablob(name, "cotton", balls, r * (0.12 if EXPORT else 0.05), parent, lumps=0.12)
    if DAY:
        C.fuzz(o, r * 0.1)
    return o


def wood_pole(m, x, y, z0, z1, r):
    """ロクロで挽いた丸棒。上の端は丸く"""
    C.tube(m, [Vector((x, y, z0)), Vector((x, y, z1))], [r, r * 0.9], sides=14)
    bmesh.ops.create_uvsphere(m.bm, u_segments=14, v_segments=6, radius=r * 0.9,
                              matrix=Matrix.Translation((x, y, z1)))


# ---------------------------------------------------------------- スピーカーの柱
def speaker(name="speaker_pole", H=5.0, tilt=15.0):
    root = new_root(name, height=H)
    parts = []
    wood = C.M(name + "_wood", "pole")
    wood_pole(wood, 0, 0, -0.2, H, 0.075)
    # 腕木: 柱から前（+Y）へ
    arm_z = H - 0.45
    C.tube(wood, [Vector((0, -0.05, arm_z)), Vector((0, 0.42, arm_z))], 0.04, sides=10)
    C.tube(wood, [Vector((0, 0.0, arm_z - 0.35)), Vector((0, 0.3, arm_z - 0.02))], 0.028, sides=8)   # 方杖
    parts.append(wood.done(parent=root))
    # ラッパ: 指数の広がり。のど（後ろ）から口（前）へ、少し下を向く
    t = math.radians(tilt)
    fwd = Vector((0, math.cos(t), -math.sin(t)))
    base = Vector((0, 0.36, arm_z - 0.16))
    L, r0, R = 0.62, 0.055, 0.30
    n = 16
    pts, rad = [], []
    for i in range(n + 1):
        s = i / n
        pts.append(base + fwd * (L * s))
        rad.append(r0 * math.exp(math.log(R / r0) * s ** 1.6))
    outer = C.M(name + "_horn", "felt_horn")
    C.tube(outer, pts, rad, sides=28, caps=False)
    # 口の縁: 丸めたフェルトの耳
    rim = []
    side = fwd.cross(Vector((0, 0, 1))).normalized()
    up = side.cross(fwd).normalized() * -1
    for i in range(64):
        a = 2 * math.pi * i / 64
        rim.append(pts[-1] + fwd * 0.012 + side * math.cos(a) * (R + 0.012) + up * math.sin(a) * (R + 0.012))
    C.tube(outer, rim + [rim[0]], 0.022, sides=8, caps=False)
    # 後ろの駆動部: 丸い缶にフェルトをかぶせた形
    back = base - fwd * 0.16
    C.tube(outer, [back, base + fwd * 0.02], 0.10, sides=20)
    bmesh.ops.create_uvsphere(outer.bm, u_segments=20, v_segments=8, radius=0.10, matrix=Matrix.Translation(back))
    parts.append(outer.done(parent=root))
    inner = C.M(name + "_horn_in", "felt_horn_in")
    C.tube(inner, [p + fwd * 0.005 for p in pts[4:]], [r * 0.93 for r in rad[4:]], sides=28, caps=False)
    bmesh.ops.create_circle(inner.bm, cap_ends=True, segments=16, radius=rad[4] * 0.93,
                            matrix=Matrix.Translation(pts[4]) @ fwd.to_track_quat("Z", "Y").to_matrix().to_4x4())
    parts.append(inner.done(parent=root))
    # 縫い目: ラッパの上の継ぎ目を巻きかがり、口の縁をかがる
    th = C.M(name + "_stitch", "thread")
    for i in range(2, n, 1):
        p = pts[i] + up * (rad[i] + 0.004)
        q = pts[i] + up * (rad[i] + 0.004) + fwd * (L / n * 0.6)
        C.tube(th, [p - side * 0.018, (p + q) / 2 + up * 0.006, q + side * 0.018], 0.006, sides=4)
    for i in range(0, 64, 3):
        a = 2 * math.pi * i / 64
        o = side * math.cos(a) + up * math.sin(a)
        p = pts[-1] + fwd * 0.012 + o * (R + 0.012)
        C.tube(th, [p - fwd * 0.026, p + o * 0.022, p + fwd * 0.026], 0.005, sides=4)
    parts.append(th.done(parent=root))
    # 線: 黒い毛糸が柱に巻きついて下りる
    cable = C.M(name + "_cable", "thread_dark")
    cp = [back + Vector((0, -0.04, -0.05)), Vector((0.0, 0.12, arm_z - 0.25)), Vector((0.08, 0.04, arm_z - 0.45))]
    z = arm_z - 0.45
    a = 0.5
    while z > 0.4:
        cp.append(Vector((math.cos(a) * 0.085, math.sin(a) * 0.085, z)))
        z -= 0.06
        a += 0.35
    C.tube(cable, cp, 0.012, sides=6)
    parts.append(cable.done(parent=root))
    # 雪: 柱のてっぺんとラッパの上
    parts.append(snow_puff(name + "_cap", (0, 0, H + 0.06), 0.13, 0.08, root, seed=1))
    parts.append(snow_puff(name + "_hornsnow", pts[n // 2] + up * (rad[n // 2] + 0.03), 0.13, 0.05, root, seed=2))
    parts.append(snow_ring(name + "_base", (0, 0, 0.02), 0.16, root, seed=3))
    marker("horn", pts[-1], root, parts)
    root["horn_dir"] = [0.0, -math.sin(t), -math.cos(t)]   # Godot の座標（前は -Z）
    made.append((root, parts))
    return root


# ---------------------------------------------------------------- コースの旗
def flag(name, felt_role, H=1.7, seed=0):
    root = new_root(name, height=H)
    parts = []
    wood = C.M(name + "_wood", "pole")
    wood_pole(wood, 0, 0, -0.15, H, 0.028)
    parts.append(wood.done(parent=root))
    # 三角の旗: 少し波打つフェルト。棒の上に 2 か所で結ぶ
    fl = C.M(name + "_felt", felt_role)
    w, h, thick = 0.55, 0.34, 0.012
    top = H - 0.06
    nu, nv = 16, 8
    grid = []
    for i in range(nu + 1):
        u = i / nu
        col = []
        for j in range(nv + 1):
            v = j / nv
            x = 0.03 + u * w
            z = top - (1 - u) * h * v - u * h * 0.5   # 先へ向かって 1 点にすぼまる
            y = 0.035 * math.sin(u * 3.2 + seed) * u   # 風で少し波打つ
            col.append(Vector((x, y, z)))
        grid.append(col)
    for side_s in (1, -1):
        vs = [[fl.bm.verts.new(p + Vector((0, side_s * thick / 2, 0))) for p in col] for col in grid]
        for i in range(nu):
            for j in range(nv):
                f = (vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1])
                fl.bm.faces.new(f if side_s > 0 else tuple(reversed(f)))
        if side_s > 0:
            front = vs
        else:
            backv = vs
    # 縁を閉じる
    edge = [(i, 0) for i in range(nu + 1)] + [(nu, j) for j in range(1, nv + 1)] + \
           [(i, nv) for i in range(nu - 1, -1, -1)] + [(0, j) for j in range(nv - 1, 0, -1)]
    for k in range(len(edge)):
        a, b = edge[k], edge[(k + 1) % len(edge)]
        try:
            fl.bm.faces.new((front[a[0]][a[1]], front[b[0]][b[1]], backv[b[0]][b[1]], backv[a[0]][a[1]]))
        except ValueError:
            pass
    fo = fl.done(parent=root)
    if DAY:
        C.fuzz(fo, 0.004, layers=2, hexcol=C.HEX[felt_role], sheen=0.4)
    parts.append(fo)
    # なみ縫い: 縁の少し内側（両面）
    th = C.M(name + "_stitch", "thread")
    inset = 0.035
    tri = [Vector((0.03 + inset, 0, top - inset * 0.8)), Vector((0.03 + w - inset * 2.2, 0, top - h * 0.5)),
           Vector((0.03 + inset, 0, top - h + inset * 0.8))]
    path = []
    for k in range(3):
        a, b = tri[k], tri[(k + 1) % 3]
        for s in range(12):
            p = a.lerp(b, s / 12)
            u = (p.x - 0.03) / w
            path.append(Vector((p.x, 0.035 * math.sin(u * 3.2 + seed) * u, p.z)))
    path.append(path[0])
    for sd in (1, -1):
        C.running_stitch(th, [p + Vector((0, sd * (thick / 2 + 0.003), 0)) for p in path], [Vector()],
                         dash=0.035, gap=0.022, r=0.0045)
    # 結び目: 旗を棒に留める糸の輪
    for z in (top - 0.03, top - h + 0.03):
        ring = [Vector((math.cos(a) * 0.036, math.sin(a) * 0.036, z)) for a in [2 * math.pi * i / 12 for i in range(13)]]
        C.tube(th, ring, 0.006, sides=5, caps=False)
    parts.append(th.done(parent=root))
    parts.append(snow_ring(name + "_base", (0, 0, 0.0), 0.09, root, seed=seed + 4))
    parts.append(snow_puff(name + "_cap", (0, 0, H + 0.03), 0.045, 0.03, root, seed=seed + 5))
    made.append((root, parts))
    return root


# ---------------------------------------------------------------- 毛糸の安全ネット（1 区間）
def net_span(name="net_span", W=2.5, H=1.2, post_h=1.5, cell=0.22):
    """杭 1 本と、そこから W 先までの網。並べてつなぐ（次の区間の杭が、この網の端を受ける）"""
    root = new_root(name, span=W)
    parts = []
    wood = C.M(name + "_wood", "pole")
    wood_pole(wood, 0, 0, -0.3, post_h, 0.06)
    parts.append(wood.done(parent=root))
    yarn = C.M(name + "_yarn", "yarn_yellow")
    knots = C.M(name + "_knots", "yarn_yellow")
    z0 = 0.18

    def sag(u, v):
        """上の綱が杭のあいだでたるむ。網もいっしょに下がる"""
        return v - 0.10 * math.sin(math.pi * u / W) * (v / H)

    def P(u, v):
        return Vector((u, 0.02 * math.sin(math.pi * u / W) * (v / H), z0 + sag(u, v)))

    # 斜めの 2 方向の糸。長方形 [0, W] × [0, H] で切る
    for sgn in (1, -1):
        c = -H
        while c < W + H:
            seg = []
            steps = 12 if EXPORT else 60
            for k in range(steps + 1):
                v = H * k / steps
                u = c + sgn * v
                if 0 <= u <= W:
                    seg.append(P(u, v))
            if len(seg) >= 2:
                C.tube(yarn, seg, 0.011, sides=4 if EXPORT else 5)
            c += cell
    # 結び目: 交わる所
    # 糸は u - v = -H + i·cell と u + v = -H + j·cell。交わる所は
    for i in range(int((W + 2 * H) / cell) + 2):
        for j in range(int((W + 2 * H) / cell) + 2):
            ca, cb = -H + i * cell, -H + j * cell
            u = (ca + cb) / 2
            v = (cb - ca) / 2
            if 0.02 < u < W - 0.02 and 0.02 < v < H - 0.02:
                bmesh.ops.create_icosphere(knots.bm, subdivisions=0 if EXPORT else 1, radius=0.022,
                                           matrix=Matrix.Translation(P(u, v)))
    # 上と下の綱（太い毛糸）
    for v in (0.0, H):
        C.tube(yarn, [P(u, v) for u in [W * k / 24 for k in range(25)]], 0.02, sides=6)
    # 杭に結ぶ輪
    for v in (0.0, H * 0.5, H):
        p = P(0, v)
        ring = [Vector((math.cos(a) * 0.075, math.sin(a) * 0.075, p.z)) for a in [2 * math.pi * i / 12 for i in range(13)]]
        C.tube(yarn, ring, 0.014, sides=5, caps=False)
    yo = yarn.done(parent=root)
    parts.append(yo)
    parts.append(knots.done(parent=root))
    parts.append(snow_puff(name + "_cap", (0, 0, post_h + 0.05), 0.09, 0.06, root, seed=7))
    parts.append(snow_ring(name + "_base", (0, 0, 0.0), 0.13, root, seed=8))
    made.append((root, parts))
    return root


# ---------------------------------------------------------------- 案内板
def offset_poly(poly, d):
    """多角形を内側へ d だけ寄せる（角は二等分線の向きに）"""
    n = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    sgn = 1 if area > 0 else -1
    out = []
    for i in range(n):
        a, b, c = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % n])
        e1 = (b - a).normalized()
        e2 = (c - b).normalized()
        n1 = Vector((-e1.y, e1.x)) * sgn
        n2 = Vector((-e2.y, e2.x)) * sgn
        bis = (n1 + n2)
        if bis.length < 1e-6:
            bis = n1
        bis.normalize()
        k = d / max(0.3, bis.dot(n1))
        out.append(b + bis * k)
    return out


def applique(felt_m, thread_m, poly, y, thick, dash=0.022):
    """フェルトのアップリケ: 板の表（+Y）に貼った平たい形と、縁の内側のなみ縫い。poly は板の面の (x, z)"""
    vf = [felt_m.bm.verts.new((x, y + thick, z)) for x, z in poly]
    vb = [felt_m.bm.verts.new((x, y, z)) for x, z in poly]
    try:
        felt_m.bm.faces.new(vf)
        felt_m.bm.faces.new(list(reversed(vb)))
    except ValueError:
        pass
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        felt_m.bm.faces.new((vf[i], vb[i], vb[j], vf[j]))
    inner = offset_poly(poly, 0.018)
    path = [Vector((p.x, y + thick + 0.002, p.y)) for p in inner] + [Vector((inner[0].x, y + thick + 0.002, inner[0].y))]
    C.running_stitch(thread_m, path, [Vector()], dash=dash, gap=dash * 0.7, r=0.004)


def arrow_poly(x0, z0, L, w_shaft, w_head, head_len, notch=0.05):
    """型紙の記号の矢印: 太い軸、三角の先、尾は燕の尾のように切り込む"""
    h, H = w_shaft / 2, w_head / 2
    return [(x0, z0 + h), (x0 + L - head_len, z0 + h), (x0 + L - head_len, z0 + H), (x0 + L, z0),
            (x0 + L - head_len, z0 - H), (x0 + L - head_len, z0 - h), (x0, z0 - h), (x0 + notch, z0)]


def house_polys(cx, cz, s):
    """ロッジ: 片流れの屋根の家と煙突、戸"""
    body = [(cx - 0.5 * s, cz - 0.45 * s), (cx + 0.5 * s, cz - 0.45 * s), (cx + 0.5 * s, cz + 0.12 * s),
            (cx - 0.5 * s, cz + 0.12 * s)]
    roof = [(cx - 0.62 * s, cz + 0.08 * s), (cx + 0.62 * s, cz + 0.08 * s), (cx + 0.62 * s, cz + 0.2 * s),
            (cx - 0.62 * s, cz + 0.48 * s)]
    chim = [(cx + 0.18 * s, cz + 0.25 * s), (cx + 0.34 * s, cz + 0.25 * s), (cx + 0.34 * s, cz + 0.55 * s),
            (cx + 0.18 * s, cz + 0.55 * s)]
    door = [(cx - 0.1 * s, cz - 0.45 * s), (cx + 0.1 * s, cz - 0.45 * s), (cx + 0.1 * s, cz - 0.08 * s),
            (cx - 0.1 * s, cz - 0.08 * s)]
    return [("felt_navy2", body, 0), ("felt_red", roof, 0), ("felt_navy2", chim, 0), ("felt_yellow", door, 1)]


def sled_polys(cx, cz, s):
    """ソリの横顔: 座布団と、前で巻き上がる滑り木"""
    seat = [(cx - 0.55 * s, cz - 0.05 * s), (cx + 0.35 * s, cz - 0.05 * s), (cx + 0.38 * s, cz + 0.12 * s),
            (cx - 0.5 * s, cz + 0.15 * s), (cx - 0.55 * s, cz + 0.4 * s), (cx - 0.68 * s, cz + 0.4 * s),
            (cx - 0.68 * s, cz - 0.05 * s)]
    run = [(cx - 0.75 * s, cz - 0.28 * s), (cx + 0.42 * s, cz - 0.28 * s)]
    for k in range(9):   # 前の巻き上がり
        a = math.radians(-90 + k * 22)
        run.append((cx + 0.42 * s + math.cos(a) * 0.2 * s, cz - 0.08 * s + math.sin(a) * 0.2 * s))
    for k in range(8, -1, -1):
        a = math.radians(-90 + k * 22)
        run.append((cx + 0.42 * s + math.cos(a) * 0.11 * s, cz - 0.08 * s + math.sin(a) * 0.11 * s))
    run += [(cx + 0.42 * s, cz - 0.19 * s), (cx - 0.75 * s, cz - 0.19 * s)]
    return [("felt_red", seat, 0), ("felt_cream", run, 0)]


def sign(name, icon, H=1.55, seed=0):
    root = new_root(name, height=H)
    parts = []
    wood = C.M(name + "_wood", "pole")
    wood_pole(wood, 0, -0.05, -0.25, H - 0.05, 0.055)
    parts.append(wood.done(parent=root))
    # 板: 横向きの 2 枚の板
    bw, bh, bt = 1.0, 0.56, 0.05
    bz = H - 0.33
    board = C.M(name + "_board", "wood")
    for k, (z0, z1) in enumerate(((bz - bh / 2, bz - 0.01), (bz + 0.01, bz + bh / 2))):
        bmesh.ops.create_cube(board.bm, size=1.0, matrix=Matrix.Translation((0, 0.0, (z0 + z1) / 2))
                              @ Matrix.Diagonal((bw, bt, z1 - z0, 1)))
    bo = board.done(smooth=False, bevel=0.012, seg=3, parent=root)
    parts.append(bo)
    # アップリケ: 左にアイコン、右へ矢印
    th = C.M(name + "_stitch", "thread")
    felts = {}
    yb = bt / 2
    icons = house_polys(-0.24, bz + 0.0, 0.34) if icon == "lodge" else sled_polys(-0.2, bz + 0.02, 0.44)
    for role, poly, layer in icons + [("felt_cream", arrow_poly(0.02, bz, 0.42, 0.075, 0.2, 0.15), 0)]:
        if role not in felts:
            felts[role] = C.M(name + "_" + role, role)
        applique(felts[role], th, poly, yb + layer * 0.012, 0.012)   # layer 1 は下の布の上に重ねる（戸）
    for m in felts.values():
        o = m.done(smooth=False, parent=root)
        if DAY:
            C.fuzz(o, 0.003, layers=2, hexcol=C.HEX.get(m.role) or C.LM.HEX.get(m.role), sheen=0.4)
        parts.append(o)
    parts.append(th.done(parent=root))
    # 板の上の雪
    balls = []
    rnd = random.Random(seed)
    for i in range(9):
        x = -bw / 2 + 0.06 + (bw - 0.12) * i / 8
        balls.append((Vector((x, 0.0, bz + bh / 2 + 0.025)), rnd.uniform(0.05, 0.075), (1.6, 0.8, 0.6)))
    o = C.metablob(name + "_snow", "cotton", balls, 0.06 * (0.12 if EXPORT else 0.05), root, lumps=0.12)
    if DAY:
        C.fuzz(o, 0.008)
    parts.append(o)
    parts.append(snow_ring(name + "_base", (0, -0.05, 0.0), 0.12, root, seed=seed + 9))
    root["icon"] = icon
    made.append((root, parts))
    return root


# ---------------------------------------------------------------- 組む
speaker()
flag("flag_red", "felt_red", seed=1)
flag("flag_navy", "felt_navy2", seed=2)
net_span()
sign("sign_lodge", "lodge", seed=1)
sign("sign_slope", "slope", seed=2)

if not A.export:
    place = {"speaker_pole": (-3.0, 3.0, 0.0), "flag_red": (-0.4, 0.6, 0.4), "flag_navy": (0.6, 1.8, 0.3),
             "net_span": (2.0, 4.5, 0.0), "sign_lodge": (-1.6, -0.6, math.pi + 0.25), "sign_slope": (1.8, -0.2, math.pi - 0.3)}
    for root, parts in made:
        x, y, rz = place[root.name]
        root.location = (x, y, 0)
        root.rotation_euler.z = rz
    # 網は 3 区間つないで見せ、最後に杭を 1 本足す（描くときだけ）
    net_root = next(r for r, p in made if r.name == "net_span")
    kids = [o for o in bpy.data.objects if o.parent == net_root]
    span = net_root["span"]
    for k in (1, 2, 3):
        r2 = net_root.copy()
        C.coll("stage").objects.link(r2)
        r2.location = net_root.location + Vector((span * k, 0, 0))
        for o in kids:
            if k == 3 and ("_yarn" in o.name or "_knots" in o.name):
                continue
            c = o.copy()
            c.parent = r2
            C.coll("stage").objects.link(c)
    C.ground(80.0)
    C.light(elev=26.0, az=-40.0)
    C.setup_render(A.size)
    cams = {
        "line": ((-1.0, -7.5, 2.2), (0.0, 1.5, 1.3), 30),
        "speaker": ((-4.5, 6.2, 4.6), (-3.0, 3.3, 4.4), 34),
        "sign": ((-1.0, -3.6, 1.35), (-0.9, -0.6, 1.2), 34),
        "net": ((1.2, 1.2, 1.3), (4.2, 4.7, 0.8), 30),
        "flag": ((-0.9, -1.4, 1.4), (-0.1, 0.8, 1.4), 32),
    }
    for root, parts in made:
        print("triangles", root.name, C.tri_count(parts))
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    for v in A.views.split(","):
        loc, tgt, lens = cams[v]
        C.render(loc, tgt, lens, os.path.abspath("%s-%s.png" % (A.prefix, v)))
else:
    for root, parts in made:
        print("triangles", root.name, C.tri_count(parts))
        K.export_root(root, os.path.join(A.export, "%s.glb" % root.name), tris=TRIS)
