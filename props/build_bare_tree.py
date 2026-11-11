"""葉の落ちた木の案（2026-11-11。旭ヶ丘のワールド用）。本物の斜面の両脇は、葉の落ちたカラマツ・シラカバ・雑木がほとんど。
今あるフェルトの円錐の木（build_tree.py）と同じ机の上の手芸作品として、裁縫の素材から形を借りる:

  zoki  雑木      針金に毛糸を巻いた枝（モールの要領）。幹から 3 回ふた股・み股に分かれ、股に綿の雪
  kaba  シラカバ  白いフェルトを巻いた細い幹に、黒い糸の横の縫い目（樹皮の横すじ）と脇の巻きかがり。上は細い毛糸の枝
  kara  カラマツ  フェルトを巻いたまっすぐな幹に、毛糸の短い枝を段々に輪に挿す。上ほど短く、全体は細い円錐
  kiri  切り抜き  厚いフェルトを枝の形に切り抜いた板を 2 枚、十字に組む。まんなかをなみ縫い（いちばん軽い案）

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_bare_tree.py -- --views line,grove --prefix /tmp/bare

ゲームに入れる書き出し（代表が ①②③ を選んだ。tree_bare_zoki / kaba / kara.glb）:

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_bare_tree.py -- --look flat --export game/props
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse()
C.reset()
C.LOOK["v"] = A.look
LO = bool(A.export)   # ゲームに入れる書き出し: 枝の数と筒の角数を減らした軽い形を組んで、色と凹凸を焼く（1 本 500 三角が目安）
if LO:
    K.baking_mode()

C.HEX.update({
    "yarn_bark": "5C4C42", "yarn_twig": "46352F", "yarn_larch": "74604E",
    "felt_birch": "EFEAE0", "felt_bark": "5E4E42", "felt_bark2": "5F4E42", "thread_bark": "2E2A28",
})


def limb(m, p0, p1, r0, r1, rnd, bend=0.06, sides=6, **kw):
    """少し曲がった枝（p0 から p1。太さ r0 → r1）。戻り値は道筋の点"""
    p0, p1 = Vector(p0), Vector(p1)
    L = (p1 - p0).length
    side = (p1 - p0).cross(Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0.3))).normalized()
    n = 4
    if LO:   # 軽い形: 細い枝は 3 角の筒・1 区間、太い枝は 4 角・2 区間、幹（10 角以上で頼まれた物）は 6 角
        n = 1 if sides <= 5 else 2
        sides = 3 if sides <= 5 else (4 if sides < 10 else 6)
    pts = [p0.lerp(p1, k / n) + side * math.sin(math.pi * k / n) * L * bend * rnd.uniform(0.4, 1.0) for k in range(n + 1)]
    C.tube(m, pts, [r0 + (r1 - r0) * k / n for k in range(n + 1)], sides=sides, **kw)
    return pts


def puff(m, at, r, rnd, flat=0.7):
    """綿の雪のひとかたまり"""
    if LO:   # 軽い形: 20 面の玉をつぶす
        ret = bmesh.ops.create_icosphere(m.bm, subdivisions=1, radius=1.0)
        for v in ret["verts"]:
            v.co = Vector(at) + Vector((v.co.x * r * 1.05, v.co.y * r * 1.05, (v.co.z + 0.6) * r * flat))
        return
    C.superellipsoid(m, Vector(at) + Vector((0, 0, r * flat * 0.6)), (r * rnd.uniform(0.9, 1.2), r * rnd.uniform(0.9, 1.2), r * flat),
                     n_xy=2.0, n_z=2.0, cuts=3)


def finish(root, parts, snow, H):
    so = snow.done(parent=root)
    if C.LOOK["v"] == "day":
        s = so.modifiers.new("soft", "SUBSURF")
        s.levels = s.render_levels = 1
        C.fuzz(so, 0.006 * H)
    parts.append(so)
    root["height"] = H
    return root, parts


def new_root(name):
    root = bpy.data.objects.new("tree_" + name, None)
    C.coll("prop").objects.link(root)
    return root


def out_dir(az, up):
    return Vector((math.cos(az) * math.cos(up), math.sin(az) * math.cos(up), math.sin(up)))


def build_zoki(seed=11, H=8.0):
    """雑木: 針金に毛糸を巻いた枝"""
    rnd = random.Random(seed)
    root = new_root("zoki")
    yarn = C.M("limbs_zoki", "yarn_bark")
    snow = C.M("snow_zoki", "cotton")
    top = Vector((rnd.uniform(-0.03, 0.03) * H, rnd.uniform(-0.03, 0.03) * H, 0.36 * H))
    limb(yarn, (0, 0, -0.05 * H), top, 0.050 * H, 0.040 * H, rnd, bend=0.03, sides=12)

    def grow(p, d, L, r, depth):
        e = p + d * L
        limb(yarn, p, e, r, r * 0.75, rnd, sides=8 if depth < 2 else 6)
        if depth == 3:
            if rnd.random() < (0.3 if LO else 0.5):
                puff(snow, e, 0.034 * H, rnd)
            return
        if rnd.random() < (0.45 if LO else 0.8):
            puff(snow, e + Vector((0, 0, r)), r * 2.2, rnd, flat=0.55)   # 股の雪
        n = 3 if depth == 0 else 2
        a0 = rnd.uniform(0, 6.28)
        for k in range(n):
            az = a0 + 6.28 * k / n + rnd.uniform(-0.4, 0.4)
            tilt = rnd.uniform(0.45, 0.8) if depth == 0 else rnd.uniform(0.35, 0.75)
            nd = (d + out_dir(az, 0.0) * math.tan(tilt)).normalized()
            nd.z = max(nd.z, 0.25)
            grow(e, nd.normalized(), 0.27 * H * rnd.uniform(0.85, 1.1) if depth == 0 else L * rnd.uniform(0.66, 0.8), r * 0.7, depth + 1)

    grow(top, Vector((0, 0, 1)), 0.02 * H, 0.040 * H, 0)
    return finish(root, [yarn.done(parent=root)], snow, H)


def build_kaba(seed=12, H=9.5):
    """シラカバ: 白いフェルトを巻いた幹に、黒い糸の横の縫い目"""
    rnd = random.Random(seed)
    root = new_root("kaba")
    felt = C.M("trunk_kaba", "felt_birch")
    mark = C.M("marks_kaba", "thread_bark")
    yarn = C.M("twigs_kaba", "yarn_twig")
    snow = C.M("snow_kaba", "cotton")
    lean = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * 0.03 * H
    Ht = 0.74 * H

    def axis(t):   # 幹の芯（t = 0 根もと 〜 1 幹の先）
        return Vector((0, 0, -0.05 * H)).lerp(Vector((0, 0, Ht)), t) + lean * t * t

    def rad(t):
        return (0.045 - 0.022 * t) * H

    nt = 4 if LO else 10
    C.tube(felt, [axis(k / nt) for k in range(nt + 1)], [rad(k / nt) for k in range(nt + 1)], sides=8 if LO else 14)
    # 樹皮の横すじ: 黒い糸を、幹を半周ほど回して刺す。ところどころ枝のあとの「目」（山形）
    for k in range(20):
        t = rnd.uniform(0.04, 0.97)
        a0 = rnd.uniform(0, 6.28)
        span = rnd.uniform(0.5, 1.6)
        r = rad(t) + 0.0025 * H
        c = axis(t)
        pts = [c + Vector((math.cos(a0 + span * q / 5) * r, math.sin(a0 + span * q / 5) * r, 0)) for q in range(6)]
        C.tube(mark, pts, 0.0050 * H * rnd.uniform(0.8, 1.3), sides=5)
        if k % 5 == 0:
            m0 = c + Vector((math.cos(a0) * r, math.sin(a0) * r, 0))
            tang = Vector((-math.sin(a0), math.cos(a0), 0)) * 0.02 * H
            C.tube(mark, [m0 - tang + Vector((0, 0, -0.018 * H)), m0 + Vector((0, 0, 0.012 * H)), m0 + tang + Vector((0, 0, -0.018 * H))], 0.006 * H, sides=5)
    # 脇の巻きかがり（フェルトを巻いた合わせ目）: 生成りの糸
    seam = C.M("seam_kaba", "thread")
    for k in range(24):
        t = 0.03 + 0.93 * k / 24
        r = rad(t) + 0.002 * H
        c = axis(t)
        a, b = c + Vector((r, -0.018 * H, 0)), axis(t + 0.014) + Vector((r, 0.018 * H, 0))
        C.tube(seam, [a, (a + b) / 2 + Vector((0.006 * H, 0, 0)), b], 0.0042 * H, sides=5)
    # 上の細い枝: 急な角度で上へ、先は少し垂れる
    for k in range(7):
        t = 0.52 + 0.48 * k / 6
        az = k * 2.4 + rnd.uniform(-0.4, 0.4)
        p = axis(t)
        L = (0.30 - 0.12 * (k / 6)) * H
        d = out_dir(az, rnd.uniform(0.85, 1.15))
        e = p + d * L
        limb(yarn, p, e, 0.015 * H, 0.010 * H, rnd, bend=0.08, sides=6)
        for q in range(1):
            s = p.lerp(e, rnd.uniform(0.35, 0.75))
            d2 = out_dir(az + rnd.uniform(-1.2, 1.2), rnd.uniform(0.2, 0.7))
            e2 = s + d2 * L * 0.45
            limb(yarn, s, e2 + Vector((0, 0, -0.03 * H)), 0.010 * H, 0.008 * H, rnd, bend=0.12, sides=5)
        if rnd.random() < 0.6:
            puff(snow, p.lerp(e, 0.5), 0.028 * H, rnd, flat=0.5)
    limb(yarn, axis(1.0), axis(1.0) + Vector((0, 0, 0.26 * H)) + lean * 0.4, rad(1.0), 0.010 * H, rnd, bend=0.04, sides=6)
    puff(snow, axis(1.0) + Vector((0, 0, 0.26 * H)) + lean * 0.4, 0.034 * H, rnd)
    parts = [felt.done(parent=root), mark.done(parent=root), seam.done(parent=root), yarn.done(parent=root)]
    return finish(root, parts, snow, H)


def build_kara(seed=13, H=11.0):
    """カラマツ: まっすぐな幹に、毛糸の短い枝を段々に輪に挿す"""
    rnd = random.Random(seed)
    root = new_root("kara")
    felt = C.M("trunk_kara", "felt_bark")
    yarn = C.M("twigs_kara", "yarn_larch")
    seam = C.M("seam_kara", "thread")
    snow = C.M("snow_kara", "cotton")
    lean = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * 0.012 * H

    def axis(z):
        return Vector((0, 0, z)) + lean * (z / H)

    def rad(z):
        return (0.038 - 0.028 * max(0.0, z / H)) * H

    nt = 4 if LO else 12
    zs = [-0.05 * H + 1.04 * H * k / nt for k in range(nt + 1)]
    C.tube(felt, [axis(z) for z in zs], [rad(z) for z in zs], sides=6 if LO else 12)
    # 巻いたフェルトの合わせ目を、らせんのなみ縫いで
    sp = [axis(z) + Vector((math.cos(z * 1.3) * (rad(z) + 0.002 * H), math.sin(z * 1.3) * (rad(z) + 0.002 * H), 0))
          for z in [0.02 * H + 0.9 * H * k / 160 for k in range(161)]]
    C.running_stitch(seam, sp, [Vector((0, 0, 0))], dash=0.03 * H, gap=0.022 * H, r=0.0042 * H)
    z = 0.20 * H
    k = 0
    while z < 0.95 * H:
        f = (z / H - 0.20) / 0.75
        L = (0.24 * (1 - f) ** 0.85 + 0.035) * H
        n = (5 if f < 0.6 else 4) if LO else (6 if f < 0.6 else 4)
        a0 = k * 0.7
        for q in range(n):
            az = a0 + 6.28 * q / n + rnd.uniform(-0.25, 0.25)
            p = axis(z + rnd.uniform(-0.012, 0.012) * H)
            d = out_dir(az, rnd.uniform(0.12, 0.38))
            e = p + d * L * rnd.uniform(0.75, 1.1) + Vector((0, 0, -0.02 * H))   # 先は少し垂れる
            limb(yarn, p, e, 0.012 * H, 0.008 * H, rnd, bend=0.06, sides=6)
            if f < 0.75 and not LO:   # 小枝を 1 本
                s = p.lerp(e, rnd.uniform(0.4, 0.7))
                limb(yarn, s, s + out_dir(az + rnd.choice((-1, 1)) * rnd.uniform(0.6, 1.0), 0.25) * L * 0.38, 0.008 * H, 0.007 * H, rnd, sides=5)
            if rnd.random() < (0.12 if LO else 0.22):
                puff(snow, p.lerp(e, rnd.uniform(0.3, 0.8)), 0.024 * H, rnd, flat=0.45)
        z += ((0.135 if LO else 0.105) - 0.03 * f) * H
        k += 1
    puff(snow, axis(0.985 * H), 0.03 * H, rnd)
    parts = [felt.done(parent=root), seam.done(parent=root), yarn.done(parent=root)]
    return finish(root, parts, snow, H)


def build_kiri(seed=14, H=8.0):
    """切り抜き: 厚いフェルトを枝の形に切った板を 2 枚、十字に組む"""
    rnd = random.Random(seed)
    root = new_root("kiri")
    snow = C.M("snow_kiri", "cotton")
    thread = C.M("stitch_kiri", "thread")
    parts = []
    for i, role in enumerate(("felt_bark", "felt_bark2")):
        m = C.M("board%d_kiri" % i, role)
        rot = Matrix.Rotation(math.pi / 2 * i + 0.1, 4, "Z")
        nrm = rot @ Vector((0, 1, 0))
        th = 0.018 * H

        def strip(p0, p1, w0, w1):
            a, b = rot @ Vector(p0), rot @ Vector(p1)
            C.tube(m, [a, a.lerp(b, 0.5), b], [w0, (w0 + w1) / 2, w1], sides=8, side=nrm, ry=th, sq=5.0)
            return b

        top = strip((0, 0, -0.05 * H), (0, 0, 0.40 * H), 0.060 * H, 0.050 * H)
        C.running_stitch(thread, [rot @ Vector((0, 0.0, 0.02 * H)) + nrm * (th + 0.002 * H), rot @ Vector((0, 0, 0.38 * H)) + nrm * (th + 0.002 * H)],
                         [Vector((0, 0, 0))], dash=0.035 * H, gap=0.025 * H, r=0.0048 * H)

        def grow(p, ang, L, w, depth):
            e = (p[0] + math.sin(ang) * L, 0, p[2] + math.cos(ang) * L)
            strip(p, e, w, w * 0.72)
            if depth == 2:
                if rnd.random() < 0.5:
                    puff(snow, rot @ Vector(e), 0.034 * H, rnd)
                return
            if rnd.random() < 0.7:
                puff(snow, rot @ Vector(e), w * 1.3, rnd, flat=0.5)
            for s in ((-1, 1) if depth else (-1, 0, 1)):
                grow(e, ang + s * rnd.uniform(0.45, 0.8) + rnd.uniform(-0.1, 0.1), 0.26 * H * rnd.uniform(0.85, 1.1) if depth == -1 else L * rnd.uniform(0.62, 0.75), w * 0.68, depth + 1)

        grow((0, 0, 0.40 * H), 0.0, 0.03 * H, 0.050 * H, -1)
        o = m.done(parent=root)
        if C.LOOK["v"] == "day":
            C.fuzz(o, 0.005 * H, layers=3, hexcol=C.HEX[role])
        parts.append(o)
    parts.append(thread.done(parent=root))
    return finish(root, parts, snow, H)


def copy_tree(root, at, yaw, k):
    """同じ形を写して置く（群れの絵用。形のデータは共有）"""
    r2 = bpy.data.objects.new(root.name + "_c", None)
    C.coll("prop").objects.link(r2)
    for ch in root.children:
        c = ch.copy()
        C.coll("prop").objects.link(c)
        c.parent = r2
    r2.location = at
    r2.rotation_euler.z = yaw
    r2.scale = (k, k, k)
    return r2


BUILD = {"zoki": build_zoki, "kaba": build_kaba, "kara": build_kara, "kiri": build_kiri}
if LO:   # 書き出し: 代表が選んだ ①②③（2026-11-11「①②③ で入れて」）。1 本ずつ原点に組む
    for name in ("zoki", "kaba", "kara"):
        root, parts = BUILD[name]()
        root.name = "tree_bare_" + name
        K.export_root(root, os.path.join(A.export, "%s.glb" % root.name), tris=520)
    sys.exit(0)

LINE = (("zoki", -9.0), ("kaba", -3.0), ("kara", 3.0), ("kiri", 9.0))
built = {}
for name, ox in LINE:
    root, parts = BUILD[name]()
    root.location.x = ox
    built[name] = root
    print("triangles", name, C.tri_count(parts))

# 背くらべの棒（人の背 1.3 m。赤いフェルト）
pole = C.M("person_pole", "felt_red")
C.tube(pole, [Vector((-12.5, 0, 0)), Vector((-12.5, 0, 1.3))], 0.16, sides=10)
pole.done()


def conifer(at, k):
    """今あるフェルトの円錐の木（ゲームの glb）を、背くらべに置く"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "props", "tree_tall.glb")
    if not os.path.exists(path):
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    tops = [o for o in set(bpy.data.objects) - before if o.parent is None]
    for o in tops:
        o.location = Vector(at)
        o.scale = (k, k, k)


conifer((15.5, 0, 0), 12.0 / 7.0)
views = A.views.split(",")
if "grove" in views:   # 群れの絵: シラカバの壁、カラマツの林、雑木のまじった縁
    rnd = random.Random(5)
    for k in range(13):
        copy_tree(built["kaba"], (-22 + k * 2.6 + rnd.uniform(-0.6, 0.6), 34 + rnd.uniform(-1.5, 1.5), 0), rnd.uniform(0, 6.28), rnd.uniform(0.85, 1.15))
    for k in range(26):
        copy_tree(built["kara"], (16 + (k % 7) * 3.4 + rnd.uniform(-1, 1), 30 + (k // 7) * 3.6 + rnd.uniform(-1, 1), 0), rnd.uniform(0, 6.28), rnd.uniform(0.85, 1.2))
    for k in range(10):
        copy_tree(built["zoki"], (-24 + k * 5.2 + rnd.uniform(-1.5, 1.5), 42 + rnd.uniform(-2, 3), 0), rnd.uniform(0, 6.28), rnd.uniform(0.9, 1.3))
    for k in range(8):
        copy_tree(built["kiri"], (44 + (k % 4) * 4.5 + rnd.uniform(-1, 1), 30 + (k // 4) * 5 + rnd.uniform(-1, 1), 0), rnd.uniform(0, 6.28), rnd.uniform(0.9, 1.3))

    for k in range(5):
        conifer((-30 + k * 3.5 + rnd.uniform(-1, 1), 48 + rnd.uniform(-2, 2), 0), rnd.uniform(1.5, 2.0))

C.ground(240.0)
C.light()
C.setup_render(A.size)
cams = {
    "line": ((1.5, -31.0, 3.4), (1.5, 0.0, 5.0), 30),
    "close_kaba": ((-6.5, -7.0, 5.0), (-3.0, 0.0, 5.4), 40),
    "close_kara": ((0.5, -8.0, 5.5), (3.0, 0.0, 5.8), 40),
    "close_zoki": ((-12.5, -7.5, 4.2), (-9.0, 0.0, 4.4), 40),
    "close_kiri": ((5.5, -7.5, 4.2), (9.0, 0.0, 4.4), 40),
    "grove": ((8.0, -22.0, 2.2), (12.0, 34.0, 5.5), 24),
}
if A.blend:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
for v in views:
    loc, tgt, lens = cams[v]
    C.render(loc, tgt, lens, os.path.abspath("%s-%s.png" % (A.prefix, v)))
