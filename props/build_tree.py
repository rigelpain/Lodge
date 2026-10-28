"""ミニチュアの木を Blender で組む。机の上の手芸作品を、そのまま丘の大きさにしたもの。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_tree.py -- \
        --kind all --views line --prefix props/renders/05-trees

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_tree.py -- \
        --kind all --look flat --export game/props

形の決まり（design/art-concept.md）: フェルトの円錐を 2 段重ね、てっぺんに雪の帽子（綿）、幹は木。
手芸作品らしさは「大きさに比べて太い縫い目と縁」で出す。高さ 20 cm の作品を 30 倍にした寸法で、
縫い目・縁の厚み・揺らぎを高さに比例させる（だから丘に置くと、ちいさく丸く見える）。

円錐は綿を詰めたフェルト: 少しふくらんだ横顔、丸い先、厚い縁。裾の切り方は種類ごとに
（波形の裁ちばさみ・ピンキングばさみ・まっすぐ切ってかがる）。脇に 1 本、縫い合わせの巻きかがり。
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

A = C.parse([("--kind", dict(default="all", choices=("tall", "round", "zigzag", "little", "all")))])
C.reset()
C.LOOK["v"] = A.look
if A.export:   # 焼き込み: 素材は描くときと同じに組む
    K.baking_mode()

C.HEX.update({
    "felt_tree_tall": "2F5E47", "felt_tree_tall2": "3E7556",
    "felt_tree_round": "4E7D43", "felt_tree_round2": "62914F",
    "felt_tree_zigzag": "2C5A5A", "felt_tree_zigzag2": "3B6E66",
    "felt_tree_little": "7A9445", "felt_tree_little2": "8FA851",
})

# 種類。高さ H（ゲームの m）。段は (裾の高さ, 先の高さ, 裾の半径, ふくらみ, 先の丸み) を H に対する割合で
TRIS = 500   # 木 1 本の三角の目安（ゲーム開発のセッションの目安）
KINDS = {
    "tall": dict(H=7.0, seed=1, hem="scallop", n_hem=9,
                 tiers=[(0.14, 0.78, 0.27, 0.10, 0.05), (0.46, 1.00, 0.20, 0.10, 0.04)],
                 trunk=(0.045, 0.20), cap=0.075, collar=True),
    "round": dict(H=5.0, seed=2, hem="whip", n_hem=0,
                  tiers=[(0.16, 0.74, 0.36, 0.22, 0.10), (0.48, 1.00, 0.28, 0.24, 0.09)],
                  trunk=(0.055, 0.22), cap=0.095, collar=False),
    "zigzag": dict(H=6.0, seed=3, hem="pinking", n_hem=22,
                   tiers=[(0.13, 0.76, 0.31, 0.12, 0.05), (0.45, 1.00, 0.23, 0.12, 0.05)],
                   trunk=(0.045, 0.20), cap=0.08, collar=True),
    "little": dict(H=3.0, seed=4, hem="scallop", n_hem=7,
                   tiers=[(0.20, 0.72, 0.40, 0.20, 0.10), (0.50, 1.00, 0.31, 0.22, 0.10)],
                   trunk=(0.07, 0.26), cap=0.13, collar=True),
}
NI, NJ = 72, 22   # 円錐の周と縦の割り


class Cone:
    """綿を詰めたフェルトの円錐。表面の点 S(θ, t) を返す（t は裾 0 → 先 1）"""

    def __init__(self, z0, z1, rb, bulge, tipr, hem, n_hem, rnd, H):
        self.z0, self.z1, self.rb, self.bulge, self.tipr = z0, z1, rb, bulge, tipr
        self.hem, self.n_hem, self.H = hem, n_hem, H
        self.ph = [rnd.uniform(0, 2 * math.pi) for _ in range(4)]
        self.lean = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * 0.012 * H   # 手作りの少しの傾き

    def hem_drop(self, th):
        """裾の切り方。下へ垂れる量"""
        d = 0.035 * self.H
        if self.hem == "scallop":   # 波形: 半円が並んで垂れる
            f = (th * self.n_hem / (2 * math.pi)) % 1.0
            return d * math.sqrt(max(0.0, 1 - (2 * f - 1) ** 2))
        if self.hem == "pinking":   # ピンキング: 細かい三角
            f = (th * self.n_hem / (2 * math.pi)) % 1.0
            return d * 0.55 * (1 - abs(2 * f - 1))
        return 0.0

    def radius(self, th, t):
        a = 1 - t
        p = math.sqrt(a * a + self.tipr ** 2) - self.tipr      # 先を丸める
        p /= math.sqrt(1 + self.tipr ** 2) - self.tipr
        r = self.rb * self.H * p * (1 + self.bulge * math.sin(math.pi * t) ** 0.8)
        w = 0.025 * (math.sin(2 * th + self.ph[0]) + 0.6 * math.sin(3 * th + self.ph[1])
                     + 0.5 * math.sin(5 * t + self.ph[2]))
        return r * (1 + w)

    def S(self, th, t, out=0.0):
        r = self.radius(th, t) + out
        z = self.z0 * self.H + (self.z1 - self.z0) * self.H * t - self.hem_drop(th) * (1 - t) ** 6
        return Vector((r * math.cos(th), r * math.sin(th), z)) + self.lean * t

    def N(self, th, t):
        e = 1e-3
        a = self.S(th + e, t) - self.S(th - e, t)
        b = self.S(th, min(1, t + e)) - self.S(th, max(0, t - e))
        n = b.cross(a)
        if n.length < 1e-9:
            return Vector((0, 0, 1))
        n.normalize()
        return n if n.dot(Vector((math.cos(th), math.sin(th), 0.3))) > 0 else -n

    def t_at(self, z):
        return max(0.0, min(1.0, (z - self.z0 * self.H) / ((self.z1 - self.z0) * self.H)))


def build_cone(m, cone, n_i=NI, n_j=NJ):
    rings = []
    for j in range(n_j + 1):
        t = (j / n_j) ** 1.15
        ring = [m.bm.verts.new(cone.S(2 * math.pi * i / n_i, t)) for i in range(n_i)]
        rings.append(ring)
    for j in range(n_j):
        for i in range(n_i):
            i2 = (i + 1) % n_i
            m.bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))
    # 先は 1 点に集める
    tip = m.bm.verts.new(cone.S(0, 1.0))
    for i in range(n_i):
        m.bm.faces.new((rings[-1][i], rings[-1][(i + 1) % n_i], tip))
    # 底: 少し凹んだ円板（中に綿が詰まっている）
    ctr = m.bm.verts.new(Vector((0, 0, cone.z0 * cone.H + 0.04 * cone.H)))
    for i in range(n_i):
        m.bm.faces.new((rings[0][(i + 1) % n_i], rings[0][i], ctr))


def hem_roll(m, cone, thick, n=180, sides=8):
    """裾の縁: 厚いフェルトの切り口を丸く"""
    pts = [cone.S(2 * math.pi * i / n, 0.0, out=-thick * 0.4) for i in range(n)]
    C.tube(m, pts + [pts[0]], thick, sides=sides, caps=False)


def side_seam(thread, cone, r):
    """脇の縫い合わせ: 裾から先まで、継ぎ目をまたぐ巻きかがり"""
    th0 = cone.ph[3]
    L = (cone.z1 - cone.z0) * cone.H
    n = max(8, int(L / (r * 7)))
    for k in range(n - 1):
        t = 0.04 + 0.86 * k / n
        dth = (r * 3.0) / max(0.05, cone.radius(th0, t))
        a = cone.S(th0 - dth, t, out=r * 0.6)
        b = cone.S(th0 + dth, t + 0.5 / n, out=r * 0.6)
        mid = (a + b) / 2 + cone.N(th0, t) * r * 1.2
        C.tube(thread, [a, mid, b], r, sides=4)


def hem_stitch(thread, cone, r, kind):
    """裾の飾り縫い。whip は縁をかがる、ほかは少し上をなみ縫い"""
    if kind == "whip":
        n = int(2 * math.pi * cone.rb * cone.H / (r * 5))
        for k in range(n):
            th = 2 * math.pi * k / n
            a = cone.S(th, 0.07, out=r * 0.4)
            b = cone.S(th + 0.5 / n * 2 * math.pi, 0.0, out=r * 0.4)
            c = Vector(b) + Vector((0, 0, -0.012 * cone.H))
            c2 = cone.S(th + 0.6 / n * 2 * math.pi, 0.0, out=-r * 1.5) + Vector((0, 0, -0.016 * cone.H))
            C.tube(thread, [a, b + cone.N(th, 0.0) * r * 1.5, c + cone.N(th, 0.0) * r * 1.2, c2], r, sides=4)
        return
    pts = []
    for i in range(240):
        pts.append(cone.S(2 * math.pi * i / 240, 0.08, out=r * 0.5))
    pts.append(pts[0])
    C.running_stitch(thread, pts, [Vector((0, 0, 0))], dash=r * 6, gap=r * 4, r=r)


def snow_sheet(name, cone, t_lo, t_hi, T, parent, n_i=72, n_j=14, rnd=None, both=False):
    """円錐の表面に、厚み T の綿をかぶせる。t_lo(θ) から t_hi まで。
    縁は四分円の横顔で丸くふくらむ（綿の縁）。both なら上の縁も丸める（肩の雪の輪）"""
    m = C.M(name, "cotton")
    ph = [rnd.uniform(0, 6.28) for _ in range(4)] if rnd else [0, 0, 0, 0]
    rings = []
    for j in range(n_j + 1):
        u = j / n_j
        ring = []
        for i in range(n_i):
            th = 2 * math.pi * i / n_i
            lo = t_lo(th)
            t = lo + (t_hi - lo) * u
            if both:
                sh = math.sin(math.pi * u) ** 0.45
            else:
                sh = math.sqrt(max(0.0, 1 - (1 - min(1.0, u * 3.0)) ** 2))
            fade = 1.0 if both else (1 - u) ** 2   # 先のほうは凸凹を消して丸く
            lump = 1 + fade * (0.18 * math.sin(3 * th + ph[0] + 4 * u) + 0.12 * math.sin(7 * th + ph[1] - 3 * u))
            out = T * sh * lump
            ring.append(m.bm.verts.new(cone.S(th, t, out=0.0) + cone.N(th, t) * out))
        rings.append(ring)
    for j in range(n_j):
        for i in range(n_i):
            i2 = (i + 1) % n_i
            m.bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))
    if not both:   # 先は 1 点に
        tip = m.bm.verts.new(sum((v.co for v in rings[-1]), Vector()) / n_i)
        for i in range(n_i):
            m.bm.faces.new((rings[-1][i], rings[-1][(i + 1) % n_i], tip))
    o = m.done(parent=parent)
    if C.LOOK["v"] == "day":
        s = o.modifiers.new("soft", "SUBSURF")
        s.levels = s.render_levels = 1
        C.fuzz(o, T * 0.22)
    return o


def build(kind, ox=0.0, export=False):
    K = KINDS[kind]
    H = K["H"]
    rnd = random.Random(K["seed"])
    root = bpy.data.objects.new("tree_" + kind, None)
    C.coll("prop").objects.link(root)
    root["height"] = H
    parts = []
    thread = C.M("stitches_" + kind, "thread")
    cones = []
    for k, (z0, z1, rb, bulge, tipr) in enumerate(K["tiers"]):
        cone = Cone(z0, z1, rb, bulge, tipr, K["hem"], K["n_hem"], rnd, H)
        cones.append(cone)
        role = "felt_tree_%s%s" % (kind, "2" if k else "")
        m = C.M("tier%d_%s" % (k, kind), role)
        build_cone(m, cone, n_i=48 if export else NI, n_j=16 if export else NJ)
        hem_roll(m, cone, 0.011 * H, *((cone.n_hem * 8 or 72, 5) if export else (180, 8)))
        o = m.done(parent=root)
        parts.append(o)
        if C.LOOK["v"] == "day":   # フェルトの輪郭の短い毛羽
            C.fuzz(o, 0.006 * H, layers=3, hexcol=C.HEX[role])
        side_seam(thread, cone, 0.0055 * H)
        hem_stitch(thread, cone, 0.005 * H, K["hem"])
    parts.append(thread.done(parent=root))
    # 幹: ロクロで挽いた丸棒。下の段の中まで差し込む
    tr, th = K["trunk"]
    wood = C.M("trunk_" + kind, "trunk")
    pts = [Vector((0, 0, -0.05 * H)), Vector((0, 0, (th + 0.04) * H))]
    C.tube(wood, pts, [tr * H, tr * H * 0.85], sides=16)
    parts.append(wood.done(parent=root))
    # 雪の帽子: 先にかぶせた綿。縁は丸くふくらみ、ところどころ舌のように垂れる
    top = cones[-1]
    cr = K["cap"] * H
    tip_z = top.S(0, 1.0).z
    drips = [(2 * math.pi * i / 5 + rnd.uniform(-0.3, 0.3), cr * rnd.uniform(0.5, 1.3)) for i in range(5)]

    def cap_lo(th):
        d = cr * 1.0
        for a, L in drips:
            da = math.atan2(math.sin(th - a), math.cos(th - a))
            d += L * math.exp(-(da / 0.28) ** 2)
        return top.t_at(tip_z - d)

    nij = (36, 7) if export else (96, 16)
    parts.append(snow_sheet("cap_" + kind, top, cap_lo, 1.0, cr * 0.55, root, *nij, rnd=rnd))
    # 先に載せた丸い綿玉。垂れた綿とつながって、丸い帽子になる
    puff = C.M("puff_" + kind, "cotton")
    C.superellipsoid(puff, top.S(0, 1.0) + Vector((0, 0, -cr * 0.2)), (cr * 0.95, cr * 0.95, cr * 0.7),
                     n_xy=2.0, n_z=2.0, cuts=4 if export else 7)
    for v in puff.bm.verts:   # 綿のむら
        v.co += (v.co - top.S(0, 1.0)).normalized() * cr * 0.08 * math.sin(v.co.x * 9 / cr + v.co.y * 7 / cr) * math.cos(v.co.z * 8 / cr)
    po = puff.done(parent=root)
    if C.LOOK["v"] == "day":
        sd = po.modifiers.new("soft", "SUBSURF")
        sd.levels = sd.render_levels = 1
        C.fuzz(po, cr * 0.12)
    parts.append(po)
    # 下の段の肩に積もった綿: 上の段の裾のすぐ外から、少し下まで
    if K["collar"]:
        low = cones[0]
        want = top.rb * H * 0.92
        tc = next((t / 200 for t in range(200) if low.radius(0, t / 200) < want), 0.5)
        band = 0.10 * H / ((low.z1 - low.z0) * H)
        ph2 = rnd.uniform(0, 6.28)
        parts.append(snow_sheet("collar_" + kind, low,
                                lambda th: tc - band * (0.8 + 0.35 * math.sin(4 * th + ph2) + 0.2 * math.sin(9 * th)),
                                tc + 0.02, 0.028 * H, root, *nij, rnd=rnd, both=True))
    root.location.x = ox
    return root, parts


if A.kind == "all":
    LINE = (("tall", -7.5), ("zigzag", -1.5), ("round", 4.5), ("little", 9.5))
else:
    LINE = ((A.kind, 0.0),)
built = [build(k, ox, bool(A.export)) for k, ox in LINE]

if not A.export:
    C.ground(120.0)
    C.light()
    C.setup_render(A.size)
    cams = {
        "line": ((-2.0, -24.0, 3.2), (1.0, 0.0, 3.0), 32),
        "line_high": ((-6.0, -22.0, 12.0), (1.0, 0.0, 2.0), 32),
        "one": ((-3.5, -9.0, 3.0), (0.0, 0.0, 3.2), 35),
        "close": ((-10.0, -6.5, 6.4), (-7.5, 0.0, 4.6), 38),
        "low": ((-1.5, -6.5, 1.0), (0.0, 0.0, 2.0), 28),
    }
    for root, parts in built:
        print("triangles", root.name, C.tri_count(parts))
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    for v in A.views.split(","):
        loc, tgt, lens = cams[v]
        C.render(loc, tgt, lens, os.path.abspath("%s-%s.png" % (A.prefix, v)))
else:
    for root, parts in built:
        print("triangles", root.name, C.tri_count(parts))
        K.export_root(root, os.path.join(A.export, "%s.glb" % root.name), tris=TRIS)
