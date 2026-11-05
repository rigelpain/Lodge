"""食べ物の形の道具（build_food.py が使う）。2 枚合わせのふっくらした形、海苔のような薄い板、食べ口（かじった跡と切り口）。

2026-11-05 代表「食べるは大事な要素」「食べてる途中の食べ口と中身も作ってほしい」。
食べ口はブーリアンでくり抜き、切り口の面は別の役割（中身の色）へ移す。粒（米粒・具のかけら）は thread の役割にして焼くだけにする。
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
import kit as K


def mouth(cx, cz, R, cy=0.0, ys=1.7, a0=0.0, a1=2 * math.pi, lobes=5):
    """ひと口の切り抜き: 大きな丸（口）のまわりに、歯の跡の小さな丸を並べる。[(中心, 半径, y の伸び)] を返す。
    (cx, cz) は正面（XZ）から見た口の中心。a0〜a1 は歯の跡を並べる弧（ラジアン）"""
    out = [(Vector((cx, cy, cz)), R, ys)]
    for k in range(lobes):
        a = a0 + (a1 - a0) * (k + 0.5) / lobes
        out.append((Vector((cx + R * 0.78 * math.cos(a), cy, cz + R * 0.78 * math.sin(a))), R * 0.42, ys))
    return out


def inside(p, cutters, grow=0.0):
    for c, r, ys in cutters:
        d = p - c
        if d.x * d.x + (d.y / ys) ** 2 + d.z * d.z < (r + grow) ** 2:
            return True
    return False


def tris_of(faces):
    """面を、点をまくための三角の列に（面の向きと広さつき）"""
    out = []
    for f in faces:
        vs = [v.co.copy() for v in f.verts]
        n = f.normal.copy()
        for i in range(1, len(vs) - 1):
            a = (vs[i] - vs[0]).cross(vs[i + 1] - vs[0]).length / 2
            if a > 0:
                out.append((vs[0], vs[i], vs[i + 1], n, a))
    return out


def surface(P, role):
    """いまの形の外向きの三角の列"""
    bm = P.m(role).bm
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    return tris_of(list(bm.faces))


def carve(P, role, cutters, inner=None, shrink=0.0):
    """P の role の形から cutters をくり抜く。切り口の面は inner の役割へ移す（None ならそのまま）。
    返すのは (外の三角, 切り口の三角)。shrink は切り抜きを小さくする分（中の具を切り口より少し盛り上げる）"""
    m = P.m(role)
    bmesh.ops.recalc_face_normals(m.bm, faces=m.bm.faces)
    me = bpy.data.meshes.new("carve_tmp")
    m.bm.to_mesh(me)
    o = bpy.data.objects.new("carve_tmp", me)
    sc = bpy.context.scene.collection
    sc.objects.link(o)
    tools = []
    for c, r, ys in cutters:
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=22, radius=max(r - shrink, 1e-4))
        for v in bm.verts:
            v.co.y *= ys
            v.co += c
        cm = bpy.data.meshes.new("carve_cut")
        bm.to_mesh(cm)
        bm.free()
        co = bpy.data.objects.new("carve_cut", cm)
        sc.objects.link(co)
        tools.append(co)
        md = o.modifiers.new("cut", "BOOLEAN")
        md.operation = "DIFFERENCE"
        md.solver = "EXACT"
        md.object = co
        md.use_self = True
        md.use_hole_tolerant = True
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    res = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    m.bm.clear()
    m.bm.from_mesh(res)
    m.uv = m.bm.loops.layers.uv.verify()
    for ob in [o] + tools:
        bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(res)
    bmesh.ops.recalc_face_normals(m.bm, faces=m.bm.faces)
    m.bm.normal_update()
    tight = [(c, r - shrink, ys) for c, r, ys in cutters]
    cav = [f for f in m.bm.faces if inside(f.calc_center_median(), tight, 0.0009)]
    cav_set = set(cav)
    outer_t, cav_t = tris_of([f for f in m.bm.faces if f not in cav_set]), tris_of(cav)
    if inner is not None and cav:
        t = P.m(inner)
        t.keep_normals = m.keep_normals = True
        for f in cav:
            t.bm.faces.new([t.bm.verts.new(v.co) for v in f.verts])
        bmesh.ops.delete(m.bm, geom=cav, context="FACES_ONLY")
        bmesh.ops.delete(m.bm, geom=[v for v in m.bm.verts if not v.link_faces], context="VERTS")
    return outer_t, cav_t


def cull(P, role, cutters, grow=0.0):
    """飾り（糸・ひも）のうち、かじって無くなった所を消す"""
    if role not in P.ms:
        return
    bm = P.m(role).bm
    gone = [f for f in bm.faces if inside(f.calc_center_median(), cutters, grow)]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")


def scatter(P, role, tris, n, size, rnd, keep=None):
    """三角の列の上に、小さな粒をまく。粒は焼くだけ（thread の役割）で、軽い形には入らない"""
    if not tris or n <= 0:
        return
    m = P.m(role)
    a, b, c = size
    for t in rnd.choices(tris, weights=[t[4] for t in tris], k=n):
        u, v = rnd.random(), rnd.random()
        if u + v > 1:
            u, v = 1 - u, 1 - v
        p = t[0] + (t[1] - t[0]) * u + (t[2] - t[0]) * v
        if keep and not keep(p):
            continue
        nrm = t[3]
        k = rnd.uniform(0.8, 1.2)
        n0 = len(m.bm.verts)
        C.superellipsoid(m, (0, 0, 0), (a * k, b * k, c), n_xy=2.0, n_z=2.0, cuts=2)
        C.place(m, n0, Matrix.Translation(p + nrm * c * 0.2) @ nrm.to_track_quat("Z", "Y").to_matrix().to_4x4()
                @ Matrix.Rotation(rnd.uniform(0, math.pi), 4, "Z"))


def stitch_runs(P, role, pts, cutters, r=0.0007, dash=0.0045, gap=0.01):
    """なみ縫い。かじって無くなった所と、点が飛んでいる所で線を切る"""
    cur, last = [], None
    for p in list(pts) + [None]:
        broke = p is None or inside(Vector(p), cutters, 0.002) or (last is not None and (Vector(p) - Vector(last)).length > gap)
        if broke:
            if len(cur) > 1:
                K.stitch_line(P, role, cur, r=r, dash=dash)
            cur = []
        if p is not None and not inside(Vector(p), cutters, 0.002):
            cur.append(p)
        last = p


def rounded_poly(corners, rc, n=8):
    """凸の多角形（反時計回り）の角を半径 rc で丸めた輪郭の点"""
    out = []
    N = len(corners)
    for i, (x, z) in enumerate(corners):
        px, pz = corners[i - 1]
        qx, qz = corners[(i + 1) % N]
        a0 = math.atan2(-(x - px), z - pz)       # 前の辺の外向き
        a1 = math.atan2(-(qx - x), qz - z)       # 次の辺の外向き
        if a1 < a0:
            a1 += 2 * math.pi
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            out.append((x + rc * math.cos(a), z + rc * math.sin(a)))
    return out


def radial_of(poly, cx, cz):
    """輪郭の点から、中心 (cx, cz) から見た向き → 半径の関数を作る"""
    tab = sorted((math.atan2(z - cz, x - cx), math.hypot(x - cx, z - cz)) for x, z in poly)
    tab = [(tab[-1][0] - 2 * math.pi, tab[-1][1])] + tab + [(tab[0][0] + 2 * math.pi, tab[0][1])]

    def r_of(th):
        th = math.atan2(math.sin(th), math.cos(th))
        for (a0, r0), (a1, r1) in zip(tab, tab[1:]):
            if a0 <= th <= a1 and a1 > a0:
                return r0 + (r1 - r0) * (th - a0) / (a1 - a0)
        return tab[0][1]
    return r_of


def pillow(m, cx, cz, r_of, T, p=2.6, rings=None, segs=None):
    """2 枚合わせのふっくらした形（フェルトの手芸の作り）。正面は XZ、厚みは Y（片側 T）。閉じた形。
    返すのは、正面の (x, z) での厚みの関数"""
    rings = rings or K.cuts(14, 9)
    segs = segs or K.cuts(64, 40)

    def yy(s):
        return T * max(0.0, 1.0 - s ** p) ** (1.0 / p)

    bm = m.bm
    grid = {}
    for side in (1, -1):
        for k in range(1, rings):
            s = math.sin(k / rings * math.pi / 2)
            for j in range(segs):
                th = 2 * math.pi * j / segs
                r = r_of(th) * s
                grid[side, k, j] = bm.verts.new((cx + r * math.cos(th), side * yy(s), cz + r * math.sin(th)))
    edge = []
    for j in range(segs):
        th = 2 * math.pi * j / segs
        r = r_of(th)
        edge.append(bm.verts.new((cx + r * math.cos(th), 0.0, cz + r * math.sin(th))))
    for side in (1, -1):
        pole = bm.verts.new((cx, side * T, cz))
        for j in range(segs):
            j2 = (j + 1) % segs
            bm.faces.new((pole, grid[side, 1, j], grid[side, 1, j2]))
            for k in range(1, rings - 1):
                bm.faces.new((grid[side, k, j], grid[side, k + 1, j], grid[side, k + 1, j2], grid[side, k, j2]))
            bm.faces.new((grid[side, rings - 1, j], edge[j], edge[j2], grid[side, rings - 1, j2]))

    def surf(x, z):
        th = math.atan2(z - cz, x - cx)
        return yy(min(math.hypot(x - cx, z - cz) / r_of(th), 1.0))
    return surf


def solid_grid(m, outer, inner):
    """2 枚の格子（外と内）を、縁でつないで閉じた薄い板にする（ブーリアンで切れるように）"""
    bm = m.bm
    nu, nv = len(outer), len(outer[0])
    a = [[bm.verts.new(p) for p in row] for row in outer]
    b = [[bm.verts.new(p) for p in row] for row in inner]
    for i in range(nu - 1):
        for j in range(nv - 1):
            bm.faces.new((a[i][j], a[i + 1][j], a[i + 1][j + 1], a[i][j + 1]))
            bm.faces.new((b[i][j + 1], b[i + 1][j + 1], b[i + 1][j], b[i][j]))
    for i in range(nu - 1):
        bm.faces.new((a[i][0], b[i][0], b[i + 1][0], a[i + 1][0]))
        bm.faces.new((a[i + 1][nv - 1], b[i + 1][nv - 1], b[i][nv - 1], a[i][nv - 1]))
    for j in range(nv - 1):
        bm.faces.new((a[0][j + 1], b[0][j + 1], b[0][j], a[0][j]))
        bm.faces.new((a[nu - 1][j], b[nu - 1][j], b[nu - 1][j + 1], a[nu - 1][j + 1]))


def lumps(P, role, center, half, n, spread, rnd):
    """具のかたまり: 丸すぎないよう、1 つの閉じた形をでこぼこに歪める（重ねた形だとブーリアンが崩れて具が消える）"""
    m = P.m(role)
    n0 = len(m.bm.verts)
    C.superellipsoid(m, (0, 0, 0), half, n_xy=2.0, n_z=2.0, cuts=K.cuts(10, 8))
    waves = [(rnd.uniform(0.6, 1.6) * n * 0.4, rnd.uniform(0.6, 1.6) * n * 0.4, rnd.uniform(0.6, 1.6) * n * 0.4, rnd.uniform(0, 6.3)) for _k in range(3)]
    for v in C.new_verts(m, n0):
        u = Vector((v.co.x / half[0], v.co.y / half[1], v.co.z / half[2]))
        d = sum(math.sin(a * u.x + b * u.y + c * u.z + ph) for a, b, c, ph in waves) / 3.0
        v.co = Vector(center) + v.co * (1.0 + spread * 0.45 * d)


def mouth_top(cx, cy, cz, R, a0=0.0, a1=2 * math.pi, lobes=5):
    """皿の上の物のひと口: 上から見た（XY）丸と歯の跡。mouth の向き違い"""
    out = [(Vector((cx, cy, cz)), R, 1.0)]
    for k in range(lobes):
        a = a0 + (a1 - a0) * (k + 0.5) / lobes
        out.append((Vector((cx + R * 0.8 * math.cos(a), cy + R * 0.8 * math.sin(a), cz)), R * 0.36, 1.0))
    return out


def koban(w, h, cz, n=2.4, count=64):
    """小判の輪郭（正面 XZ の点）"""
    pts = []
    for k in range(count):
        a = 2 * math.pi * k / count
        c, s = math.cos(a), math.sin(a)
        pts.append((w * math.copysign(abs(c) ** (2 / n), c), cz + h * math.copysign(abs(s) ** (2 / n), s)))
    return pts


def wrap_band(P, role, surf, r_of, cx, cz, w, top, out=0.0016, inn=0.0014, wobble=0.0012):
    """2 枚合わせの形の下半分を巻く帯（海苔・包み紙）。正面の上の縁 top から底をまわって背中へ。切れるように閉じた板にする。
    返すのは、面の上の点を求める関数 at(x, z, d)"""

    def z_edge(x):
        lo, hi = cz - 0.2, cz
        for _ in range(26):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if math.hypot(x - cx, mid - cz) > r_of(math.atan2(mid - cz, x - cx)) else (lo, mid)
        return hi

    def push(x, y, z, d):
        v = Vector((x - cx, y, z - cz))
        v = v * (1 + d / max(v.length, 1e-4))
        return (v.x + cx, v.y, v.z + cz)

    outer, inner = [], []
    nu, nv = K.cuts(24, 14), K.cuts(12, 8)
    for i in range(nu + 1):
        x = -w + 2 * w * i / nu
        tp = top - 0.0035 * (abs(x) / w) ** 8 + wobble * math.sin(x * 90)   # 角が少し丸く、手で切った縁
        ze = z_edge(x)
        col = [(1, tp + (ze - tp) * (j / nv) ** 0.65) for j in range(nv)] + [(0, ze)]
        col += [(-1, tp + (ze - tp) * (j / nv) ** 0.65) for j in range(nv - 1, -1, -1)]
        outer.append([push(x, sd * surf(x, z), z, out) for sd, z in col])
        inner.append([push(x, sd * surf(x, z), z, -inn) for sd, z in col])
    solid_grid(P.m(role), outer, inner)

    def at(x, z, d=0.0022):
        return push(x, surf(x, z), z, d)
    return at


def sleeve(P, role, poly, h, dip=0.0, t=0.0012):
    """紙の袋・箱: 輪郭 poly（上から見た点。中心 0）の、上の開いた薄い入れ物。手前（+Y）の縁は dip だけ低く弧に下がる"""
    m = P.m(role)
    bm = m.bm
    xs = [abs(p[0]) for p in poly] or [1.0]
    W = max(xs)

    def top(x, y):
        return h - (dip * (1 - (x / W) ** 2) if y > 0 else 0.0)

    def inset(p):
        L = max(math.hypot(p[0], p[1]), 1e-5)
        return (p[0] * (1 - t / L), p[1] * (1 - t / L))

    n = len(poly)
    ob = [bm.verts.new((p[0], p[1], 0.0)) for p in poly]
    ot = [bm.verts.new((p[0], p[1], top(p[0], p[1]))) for p in poly]
    ins = [inset(p) for p in poly]
    it = [bm.verts.new((p[0], p[1], top(p[0], p[1]))) for p in ins]
    ib = [bm.verts.new((p[0], p[1], t)) for p in ins]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
        bm.faces.new((ot[i], ot[j], it[j], it[i]))
        bm.faces.new((it[i], it[j], ib[j], ib[i]))
    bm.faces.new(list(reversed(ob)))
    bm.faces.new(ib)
    return top
