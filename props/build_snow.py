"""ふわふわの雪を Blender で組む。柔らかい積雪は綿、パウダーはちぎった綿と小さな毛玉。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snow.py -- \
        --views scene,close --prefix props/renders/06-snow

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snow.py -- \
        --look flat --export game/props

雪の硬さで素材を変える（design/art-concept.md の「質感の作り方」）:
  踏み固めた雪 = 目の詰んだメリヤス編み（丘の地面。ゲームのシェーダーにある）
  柔らかい積雪 = ふっくらした綿。輪郭がにじむ（吹きだまり、雪の山、岩に積もった雪）
  パウダー     = ちぎった綿か小さな毛玉（滑ると散る粒）
岩はフェルトを縫い合わせて綿を詰めた小石。木と同じく 20 cm の作品を 30 倍にした縮尺。
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
TRIS = 800   # 岩・雪の山 1 つの三角の目安
EXPORT = bool(A.export)
DAY = A.look == "day"

made = []   # (根元の節点, 部品の列)


def new_root(name, **extras):
    r = bpy.data.objects.new(name, None)
    C.coll("prop").objects.link(r)
    for k, v in extras.items():
        r[k] = v
    return r


def soften(o, fuzz_len, level=1):
    """描くときだけ: なめらかにして、毛羽の層を重ねる"""
    if DAY:
        s = o.modifiers.new("soft", "SUBSURF")
        s.levels = s.render_levels = level
        C.fuzz(o, fuzz_len)


# ---------------------------------------------------------------- 吹きだまり
# 風上はゆるい坂、風下は切り立って、てっぺんが庇のように張り出す。横顔（u: 風上 -1 → 風下 +1, z）
DRIFT_PROFILE = [(-1.0, -0.04), (-1.0, 0.0), (-0.75, 0.18), (-0.40, 0.55), (-0.05, 0.86), (0.25, 1.00),
                 (0.45, 1.00), (0.60, 0.90), (0.64, 0.78), (0.56, 0.68), (0.50, 0.58), (0.56, 0.40),
                 (0.68, 0.16), (0.78, 0.0), (0.78, -0.04)]


def drift(name, L, W, Hd, bend, seed):
    rnd = random.Random(seed)
    root = new_root(name, size=[W * 2, Hd, L])
    m = C.M(name + "_cotton", "cotton")
    ns = 18 if EXPORT else 28
    ph = [rnd.uniform(0, 6.28) for _ in range(3)]
    rings = []
    for k in range(ns + 1):
        s = 0.03 + 0.94 * k / ns
        env = math.sin(math.pi * s)
        w = W * env ** 0.55 * (1 + 0.08 * math.sin(7 * s + ph[0]))
        h = Hd * env ** 0.75 * (1 + 0.12 * math.sin(5 * s + ph[1]) + 0.06 * math.sin(13 * s + ph[2]))
        x = L * (s - 0.5)
        y = bend * math.sin(math.pi * s)
        dy = bend * math.pi * math.cos(math.pi * s) / L
        side = Vector((-dy, 1, 0)).normalized()   # 道筋に直交する、地面の上の向き
        ring = []
        for (u, z) in DRIFT_PROFILE:
            ring.append(m.bm.verts.new(Vector((x, y, 0)) + side * (u * w) + Vector((0, 0, z * h))))
        rings.append(ring)
    n = len(DRIFT_PROFILE)
    for k in range(ns):
        for i in range(n - 1):
            m.bm.faces.new((rings[k][i], rings[k][i + 1], rings[k + 1][i + 1], rings[k + 1][i]))
    for ring in (rings[0], rings[-1]):   # 両端は細く閉じる
        c = m.bm.verts.new(sum((v.co for v in ring), Vector()) / n)
        for i in range(n - 1):
            m.bm.faces.new((ring[i], ring[i + 1], c))
    o = m.done(parent=root)
    tex = bpy.data.textures.new(name + "_tex", "CLOUDS")   # ちぎった綿のむら
    tex.noise_scale = 0.35
    tex.noise_depth = 2
    d = o.modifiers.new("lumps", "DISPLACE")
    d.texture, d.texture_coords, d.strength, d.mid_level = tex, "OBJECT", 0.12, 0.5
    soften(o, 0.05, level=2)
    if EXPORT:   # 書き出しも 1 段なめらかに（庇の丸み）
        sd = o.modifiers.new("soft", "SUBSURF")
        sd.levels = sd.render_levels = 1
    o.modifiers.move(o.modifiers.find("lumps"), len(o.modifiers) - 1)
    made.append((root, [o]))
    return root


# ---------------------------------------------------------------- 雪の山（ちぎった綿を積んだ）
def pile(name, R, Hp, n, seed):
    rnd = random.Random(seed)
    root = new_root(name, radius=R, height=Hp)
    balls = [(Vector((0, 0, Hp * 0.2)), R * 0.6, (1.0, 1.0, Hp / R * 0.8))]
    for i in range(n):   # ちぎった綿のかたまりを、山の形に積む。平たく、向きはばらばら
        a = rnd.uniform(0, 2 * math.pi)
        d = math.sqrt(rnd.uniform(0.0, 1.0)) * R * 0.9
        h = Hp * (1 - (d / R) ** 1.6)
        r = R * rnd.uniform(0.2, 0.32)
        balls.append((Vector((d * math.cos(a), d * math.sin(a), h * rnd.uniform(0.55, 0.95))), r,
                      (rnd.uniform(1.1, 1.6), rnd.uniform(0.8, 1.1), rnd.uniform(0.55, 0.8)), rnd.uniform(0, 3.14)))
    o = C.metablob(name + "_cotton", "cotton", balls, R * (0.08 if EXPORT else 0.03), root, lumps=0.25)
    for v in o.data.vertices:   # 地面より下は平らに
        v.co.z = max(v.co.z, -0.03)
    soften(o, 0.035)
    made.append((root, [o]))
    return root


# ---------------------------------------------------------------- フェルトの岩と、積もった雪
class Rock:
    """縫い合わせたフェルトの小石。方向ごとの半径に雑音をかけた超楕円体"""

    def __init__(self, center, half, seed, n=2.6):
        self.c, self.half, self.n = Vector(center), half, n
        rnd = random.Random(seed)
        self.ph = [rnd.uniform(0, 6.28) for _ in range(6)]

    def wob(self, d):
        p = self.ph
        return 1 + 0.07 * math.sin(3 * d.x + 2 * d.y + p[0]) + 0.05 * math.sin(5 * d.y - 3 * d.z + p[1]) \
            + 0.04 * math.sin(7 * d.x + 5 * d.z + p[2])

    def surf(self, d):
        """方向 d（単位）の表面の点（中心から）"""
        ax, ay, az = self.half
        lo, hi = 0.0, 4 * max(self.half)
        for _ in range(36):
            t = (lo + hi) / 2
            f = (abs(t * d.x) / ax) ** self.n + (abs(t * d.y) / ay) ** self.n + (abs(t * d.z) / az) ** self.n
            lo, hi = (t, hi) if f < 1 else (lo, t)
        return d * lo * self.wob(d)


def rock(name, parts_spec, seed, snow_T, snow_drop):
    """岩（1 つか数個の小石）と、上に積もった綿の雪"""
    rnd = random.Random(seed)
    root = new_root(name)
    felt = C.M(name + "_felt", "felt_stone" if seed % 2 else "felt_stone2")
    thread = C.M(name + "_stitch", "thread_dark")
    snow = C.M(name + "_snow", "cotton")
    cuts = 5 if EXPORT else 12
    hid = snow.bm.verts.layers.int.new("hidden")   # 岩の中にしまう頂点の印（あとで消す）
    for (center, half) in parts_spec:
        R = Rock(center, half, seed + len(felt.bm.verts))
        n0 = len(felt.bm.verts)
        ret = bmesh.ops.create_cube(felt.bm, size=2.0)
        es = list({e for v in ret["verts"] for e in v.link_edges})
        bmesh.ops.subdivide_edges(felt.bm, edges=es, cuts=cuts, use_grid_fill=True)
        rv = C.new_verts(felt, n0)
        dirs = [v.co.normalized() for v in rv]
        for v, d in zip(rv, dirs):
            v.co = R.c + R.surf(d)
        # 雪: 同じ形を外へ膨らませ、ある高さより下は岩の中にしまう。縁は垂れる
        top = R.c.z + R.half[2] * 0.68
        ph = rnd.uniform(0, 6.28)
        n1 = len(snow.bm.verts)
        bmesh.ops.create_cube(snow.bm, size=2.0)
        sv_all = C.new_verts(snow, n1)
        es = list({e for v in sv_all for e in v.link_edges})
        bmesh.ops.subdivide_edges(snow.bm, edges=es, cuts=cuts, use_grid_fill=True)
        for v in C.new_verts(snow, n1):
            d = v.co.normalized()
            p = R.c + R.surf(d)
            th = math.atan2(d.y, d.x)
            line = top - snow_drop * (0.5 + 0.5 * math.sin(3 * th + ph)) ** 3 * R.half[2] * 0.6
            k = (p.z - line) / (R.half[2] * 0.12)
            k = max(0.0, min(1.0, k))
            k = k * k * (3 - 2 * k)
            if k <= 0.0:
                v[hid] = 1
            nrm = (p - R.c).normalized()
            nrm = (nrm + Vector((0, 0, 0.6))).normalized()
            lump = 1 + 0.25 * math.sin(4 * th + 3 * d.z + ph) * math.sin(2 * th - ph)
            v.co = p + nrm * (snow_T * k * lump - 0.004 * (1 - k)) + Vector((0, 0, snow_T * 0.5 * k * max(0, d.z) ** 2))
        # 縫い目: 横に一周、巻きかがり
        ring = []
        for i in range(64):
            a = 2 * math.pi * i / 64
            d = Vector((math.cos(a), math.sin(a), -0.05)).normalized()
            ring.append(R.c + R.surf(d) * 1.003)
        for i in range(0, 64, 1 if not EXPORT else 2):
            a, b = ring[i], ring[(i + 1) % 64]
            out = (a - R.c).normalized()
            C.tube(thread, [a + Vector((0, 0, 0.02)), a + out * 0.012, b - Vector((0, 0, 0.02))], 0.006, sides=4)
    # 岩の中にしまった雪は消す（毛羽の層が岩の表面から突き出さないように）。頂点を数え終えてから
    bmesh.ops.delete(snow.bm, geom=[v for v in snow.bm.verts if v[hid]], context="VERTS")
    po = []
    for m, fl in ((felt, 0.0), (snow, 0.03)):
        o = m.done(parent=root)
        if DAY:
            s = o.modifiers.new("soft", "SUBSURF")
            s.levels = s.render_levels = 1
            if m is not felt:   # 岩のフェルトは毛羽の層を重ねるとごま塩にざらつくので、素材の凹凸だけ
                C.fuzz(o, fl)
        po.append(o)
    po.append(thread.done(parent=root))
    made.append((root, po))
    return root


# ---------------------------------------------------------------- パウダー: ちぎった綿と毛玉
def powder(name):
    """滑ると散る粒。ゲームの粒子の形に使う。powder_0..3 の 4 つ"""
    root = new_root(name)
    po = []
    rnd = random.Random(11)
    specs = [("pill", 0.035), ("pill", 0.025), ("wisp", 0.07), ("wisp", 0.05)]
    for i, (kind, r) in enumerate(specs):
        if kind == "pill":   # 毛玉: 小さな丸い玉
            balls = [(Vector((0, 0, 0)), r)] + [
                (Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized() * r * 0.5, r * 0.6)
                for _ in range(3)]
        else:                # ちぎった綿: 平たく伸びた、ふちのほつれたかたまり
            balls = [(Vector((rnd.uniform(-1, 1) * r, rnd.uniform(-0.4, 0.4) * r, rnd.uniform(-0.15, 0.15) * r)),
                      r * rnd.uniform(0.35, 0.6), (1.4, 0.8, 0.45), rnd.uniform(0, 3)) for _ in range(5)]
        o = C.metablob("powder_%d" % i, "cotton", balls, r * (0.35 if EXPORT else 0.15), root, lumps=0.25)
        o.location = (i * 0.25 - 0.4, 0, 0)
        soften(o, r * 0.35)
        po.append(o)
    made.append((root, po))
    return root


# ---------------------------------------------------------------- 組む
drift("snow_drift", L=7.0, W=1.6, Hd=0.9, bend=0.8, seed=1)
pile("snow_pile_a", R=1.1, Hp=0.9, n=26, seed=2)
pile("snow_pile_b", R=0.6, Hp=0.45, n=14, seed=3)
rock("rock_a", [((0, 0, 0.32), (0.62, 0.52, 0.45))], seed=5, snow_T=0.10, snow_drop=1.0)
rock("rock_b", [((0, 0, 0.18), (1.05, 0.75, 0.30))], seed=6, snow_T=0.12, snow_drop=0.6)
rock("rock_c", [((-0.25, 0.0, 0.17), (0.32, 0.28, 0.24)), ((0.25, 0.12, 0.12), (0.22, 0.2, 0.16)),
                ((0.05, -0.32, 0.09), (0.16, 0.14, 0.12))], seed=7, snow_T=0.05, snow_drop=0.8)
powder("powder")

if not A.export:
    # 並べる: 吹きだまりを奥に、手前に岩と雪の山、足もとにパウダーを散らす
    place = {"snow_drift": (0.5, 7.0, 0, 0.2), "snow_pile_a": (-3.4, 2.4, 0, 0), "snow_pile_b": (-1.7, 0.6, 0, 0),
             "rock_a": (1.6, 2.2, 0, 0.6), "rock_b": (3.6, 3.8, 0, -0.3), "rock_c": (0.1, 0.0, 0, 1.0),
             "powder": (0.0, -2.5, 0.0, 0)}
    for root, parts in made:
        x, y, z, rz = place[root.name]
        root.location = (x, y, z)
        root.rotation_euler.z = rz
    # パウダーを雪の上に散らす（描くときだけ。粒の形を写して増やす）
    rnd = random.Random(21)
    src = [o for o in bpy.data.objects if o.name.startswith("powder_") and "_fuzz" not in o.name]
    shells = {o.name: [f for f in bpy.data.objects if f.name.startswith(o.name + "_fuzz")] for o in src}
    for i in range(70):
        o = rnd.choice(src)
        loc = Vector((rnd.gauss(-0.6, 0.9), rnd.gauss(-0.6, 0.6), 0.01))
        rz, sc = rnd.uniform(0, 6.28), rnd.uniform(0.7, 1.4)
        for g in [o] + shells[o.name]:   # 毛羽の層もいっしょに
            c = g.copy()
            c.parent = None
            c.location = loc
            c.rotation_euler = (0, 0, rz)
            c.scale = (sc, sc, sc)
            C.coll("stage").objects.link(c)
    C.ground(80.0)
    C.light(elev=20.0, az=-60.0)
    C.setup_render(A.size)
    cams = {
        "scene": ((-3.0, -7.5, 2.0), (0.6, 2.8, 0.4), 30),
        "high": ((-6.0, -9.0, 6.5), (0.5, 3.0, 0.0), 30),
        "close": ((-1.6, -2.2, 0.7), (0.2, 0.3, 0.2), 34),
        "drift": ((-2.5, 11.5, 1.4), (0.5, 7.0, 0.5), 30),
        "powder": ((-0.6, -3.4, 0.45), (-0.4, -1.0, 0.0), 40),
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
