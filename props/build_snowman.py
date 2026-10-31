"""ご飯係の雪だるまと、雪だるまが入る冷蔵庫を Blender で組む。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snowman.py -- \
        --views front,quarter,side,door,face --prefix props/renders/30-snowman

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snowman.py -- --apart \
        --views s_front,s_quarter,s_side,s_back --prefix props/renders/31-snowman-alone

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snowman.py -- --export game/props

ロッジの食べ物・飲み物は雪玉で払い、店番は雪だるま（design/game-design.md「雪玉で払う」）。ロッジは暖かいので、
雪だるまは扉を開けっぱなしにした大きな冷蔵庫の中に立つ。どちらも手芸の素材（白いフェルトの玉・毛糸のマフラー・
フェルトの外板と縫い目・木のボタンの取っ手）で作る。顔はボタンの目と小さな鼻だけ。

動かせるように、雪だるまは段ごとに節点を分ける（base → chest → head・arm_l・arm_r）。節点の原点が回す支点。
冷蔵庫の扉も節点 door（支点は蝶番の軸）。大きさは本物のまま（書き出しの倍率 1）。前は +Y（Godot の -Z）。
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--apart", dict(action="store_true", help="雪だるまを冷蔵庫の横に出して描く")),
             ("--only", dict(default="", help="書き出す品物（snowman,snowman_fridge）"))])
K.setup(A, fiber=1.5, scale=1.0)
EX = K.S["export"]
C.HEX.update({"felt_snowman": "F2F0EA", "felt_apron": "C4574A", "button_eye": "2B2725",
              "felt_mint": "9FC4B2", "felt_mint_dark": "77A08E", "felt_liner": "EEF0EC", "felt_frost_blue": "CFE0E6",
              "yarn_gasket": "C4C8C4", "thread_blue": "7FA6C0", "felt_mustard": "C99A3A"})


# ---------------------------------------------------------------- 共通
def oriented(P, role, build, at, normal, spin=0.0):
    """build() が原点に z 上向きで組んだ形を、at に normal の向きで置く"""
    m = P.m(role)
    n0 = len(m.bm.verts)
    build()
    q = Vector((0, 0, 1)).rotation_difference(Vector(normal).normalized())
    C.place(m, n0, Matrix.Translation(at) @ q.to_matrix().to_4x4() @ Matrix.Rotation(spin, 4, "Z"))


def patch(P, role, f, nu, nv, th=0.006, border=None):
    """面に沿う布（前掛けなど）: f(u, v) → (位置, 外向きの向き)。厚み th の板にし、border の糸で縁をなみ縫い"""
    m = P.m(role)
    grid = [[f(i / nu, j / nv) for i in range(nu + 1)] for j in range(nv + 1)]
    out = [[m.bm.verts.new(p + n * th / 2) for p, n in row] for row in grid]
    inn = [[m.bm.verts.new(p - n * th / 2) for p, n in row] for row in grid]
    for j in range(nv):
        for i in range(nu):
            m.bm.faces.new((out[j][i], out[j][i + 1], out[j + 1][i + 1], out[j + 1][i]))
            m.bm.faces.new((inn[j][i], inn[j + 1][i], inn[j + 1][i + 1], inn[j][i + 1]))
    ring = [(0, j) for j in range(nv)] + [(i, nv) for i in range(nu)] + [(nu, j) for j in range(nv, 0, -1)] + \
           [(i, 0) for i in range(nu, 0, -1)]
    for k in range(len(ring)):
        (i0, j0), (i1, j1) = ring[k], ring[(k + 1) % len(ring)]
        m.bm.faces.new((out[j0][i0], inn[j0][i0], inn[j1][i1], out[j1][i1]))
    if border:
        e = 0.06
        pts = []
        loop = [(e + (1 - 2 * e) * k / 20, e) for k in range(21)] + [(1 - e, e + (1 - 2 * e) * k / 20) for k in range(1, 21)] + \
               [(1 - e - (1 - 2 * e) * k / 20, 1 - e) for k in range(1, 21)] + [(e, 1 - e - (1 - 2 * e) * k / 20) for k in range(1, 21)]
        for u, v in loop:
            p, n = f(u, v)
            pts.append(p + n * (th / 2 + 0.001))
        C.running_stitch(P.m(border), pts, [Vector()], dash=0.016, gap=0.011, r=0.0025)


def shift_part(P, pivot, parent=None, parent_pivot=(0, 0, 0)):
    """組んだ部品を支点 pivot の節点に移す（形は世界の位置のまま、節点の原点が支点になる）"""
    pv = Vector(pivot)
    for o in bpy.data.objects:
        if o.parent == P.root:
            o.location -= pv
    P.root.parent = parent
    P.root.location = pv - Vector(parent_pivot)


# ---------------------------------------------------------------- 雪だるま
def ball(P, role, c, R, sq=0.9, gores=6, seed=0, flat=None, thread="thread"):
    """白いフェルトの玉: 舟形の布 gores 枚を縫い合わせて綿を詰めた形。縫い目は少しくぼみ、なみ縫いの糸。
    手作りの少しのゆがみ。flat を決めると底を平らに（置いて立つ）。位置と向きを返す関数 (θ: 下 0 〜 上 π, φ)"""
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 2 * math.pi) for _ in range(3)]
    c = Vector(c)
    off = math.pi / 2 + math.pi / gores   # 前のまんなかは布の中ほど
    span = 2 * math.pi / gores

    def k(th, phi):
        dd = (phi - off) % span
        dist = min(dd, span - dd)
        groove = 0.035 * max(0.0, 1 - dist / (span * 0.22)) ** 2 * math.sin(th) ** 0.5
        lump = 0.022 * math.sin(2 * phi + ph[0]) * math.sin(th) + 0.015 * math.sin(3 * th + ph[1]) * math.cos(phi + ph[2])
        return (1 - groove) * (1 + lump)

    def pos(th, phi, lift=0.0):
        s = k(th, phi) * R + lift
        z = -s * sq * math.cos(th)
        if flat is not None:
            z = max(z, flat)
        return c + Vector((s * math.sin(th) * math.cos(phi), s * math.sin(th) * math.sin(phi), z))

    def nrm(th, phi):
        return Vector((math.sin(th) * math.cos(phi), math.sin(th) * math.sin(phi), -math.cos(th) / sq)).normalized()

    m = P.m(role)
    segs, rings = (28, 16) if EX else (48, 28)
    bot = m.bm.verts.new(pos(0.0, 0.0))
    top = m.bm.verts.new(pos(math.pi, 0.0))
    rows = []
    for j in range(1, rings):
        th = math.pi * j / rings
        rows.append([m.bm.verts.new(pos(th, 2 * math.pi * i / segs)) for i in range(segs)])
    for j in range(len(rows) - 1):
        for i in range(segs):
            i2 = (i + 1) % segs
            m.bm.faces.new((rows[j][i], rows[j][i2], rows[j + 1][i2], rows[j + 1][i]))
    for i in range(segs):
        i2 = (i + 1) % segs
        m.bm.faces.new((rows[0][i2], rows[0][i], bot))
        m.bm.faces.new((rows[-1][i], rows[-1][i2], top))
    for g in range(gores):   # 縫い目
        phi = off + span * g
        pts = [pos(0.25 + (math.pi - 0.5) * t / 30, phi, 0.002) for t in range(31)]
        C.running_stitch(P.m(thread), pts, [Vector()], dash=0.022, gap=0.014, r=0.003)
    return pos, nrm


def button_eye(P, at, n):
    """ボタンの目: 黒い木のボタンに、白い糸の × 留め"""
    oriented(P, "button_eye", lambda: C.lathe(P.m("button_eye"), [(0.0, -0.004), (0.03, -0.004), (0.032, 0.004), (0.027, 0.011),
                                                                   (0.0, 0.010)], 20), at, n)
    for a in (0.785, 2.356):
        oriented(P, "thread", lambda a=a: C.tube(P.m("thread"), [Vector((-0.011 * math.cos(a), -0.011 * math.sin(a), 0.012)),
                                                                Vector((0.011 * math.cos(a), 0.011 * math.sin(a), 0.012))],
                                                0.0028, sides=4), at, n)


def twig(P, pts, r0, r1, forks=()):
    """木の枝の腕: 根元から先へ細る。forks は (何本目の点から, 向き, 長さ) の小枝"""
    rs = [r0 + (r1 - r0) * i / (len(pts) - 1) for i in range(len(pts))]
    K.tube(P, "trunk", pts, rs, sides=7)
    for i, d, L in forks:
        p = Vector(pts[i])
        d = Vector(d).normalized()
        K.tube(P, "trunk", [p - d * 0.01, p + d * L * 0.6, p + d * L + Vector((0, 0, 0.004))], [rs[i] * 0.7, rs[i] * 0.55, rs[i] * 0.35], sides=6)


def snowman():
    """ご飯係の雪だるま。3 段の白いフェルトの玉、ボタンの目、橙のフェルトの鼻、からし色の毛糸のマフラー、
    赤い前掛け、頭に小さなバケツ。右手（+X）にお玉、左手に小さな手振りのベル"""
    top = K.root("snowman", kind="snowman", height=1.41)
    # 段の中心と大きさ
    cb, Rb, sb = Vector((0, 0, 0.29)), 0.33, 0.88
    cc, Rc, sc = Vector((0, 0, 0.745)), 0.25, 0.9
    ch, Rh, sh = Vector((0, 0, 1.105)), 0.19, 0.92
    waist, neck = Vector((0, 0, 0.55)), Vector((0, 0, 0.95))

    # ---- 下の段（支点は足もと: 体を揺らす）
    B = K.Parts("base")
    pb, nb = ball(B, "felt_snowman", cb, Rb, sb, gores=6, seed=1, flat=-0.275)
    # 前掛けの下（腰から垂れ、裾に向かって少し広がり、ひだが寄る）
    th_top, th_hem = 2.36, 1.12

    def skirt(u, v):
        w = math.radians(40 + 22 * v)
        phi = math.pi / 2 + (u - 0.5) * 2 * w
        th = th_top + (th_hem - th_top) * v
        p = pb(max(th, math.pi / 2), phi, 0.012 + 0.02 * v * v + 0.006 * math.sin(phi * 14) * v)
        if th < math.pi / 2:   # 腹より下は布がまっすぐ垂れる
            q = pb(th, phi)
            p = Vector((p.x, p.y, q.z))
        return p, nb(max(th, math.pi / 2), phi)
    patch(B, "felt_apron", skirt, 16, 10, border="thread")

    def pocket(u, v):
        phi = math.pi / 2 + math.radians(-6 - 26 * u)
        th = 1.72 + (1.4 - 1.72) * v
        return pb(max(th, math.pi / 2), phi, 0.024 + 0.02 * ((th_top - th) / (th_top - th_hem)) ** 2), nb(max(th, math.pi / 2), phi)
    patch(B, "felt_apron", pocket, 5, 4, th=0.005, border="thread")
    # 腰ひも: 腰に一周、後ろで蝶結び
    zr = 0.53
    rr = Rb * math.sqrt(max(0.0, 1 - ((zr - cb.z) / (Rb * sb)) ** 2)) + 0.012
    band = [Vector((rr * math.cos(a), rr * math.sin(a), zr)) for a in (2 * math.pi * i / 40 for i in range(41))]
    C.tube(B.m("felt_apron"), band, 0.008, sides=6, ry=0.016, caps=False)
    back = Vector((0, -rr - 0.01, zr))
    for sx in (-1, 1):
        K.tube(B, "felt_apron", [back, back + Vector((sx * 0.05, -0.015, 0.03)), back + Vector((sx * 0.08, -0.01, 0.0)),
                                 back + Vector((sx * 0.05, -0.012, -0.025)), back], 0.009, sides=6)
        K.tube(B, "felt_apron", [back, back + Vector((sx * 0.03, -0.02, -0.06)), back + Vector((sx * 0.05, -0.015, -0.12))],
               0.008, sides=6, ry=0.003)
    B.finish(fuzz=0.004)

    # ---- 中の段（支点は腰: おじぎ）
    Cp = K.Parts("chest")
    pc, nc = ball(Cp, "felt_snowman", cc, Rc, sc, gores=6, seed=2)

    def bib(u, v):
        th = 0.86 + (2.25 - 0.86) * v
        phi = math.pi / 2 + (u - 0.5) * 2 * math.radians(30 - 6 * v)
        return pc(th, phi, 0.01), nc(th, phi)
    patch(Cp, "felt_apron", bib, 10, 10, border="thread")
    # マフラー: 首に二巻き（毛糸）。片方の端を前に垂らし、からしとクリームの縞、先に房
    for k, (r0, z0, tilt) in enumerate(((0.13, 0.94, 0.06), (0.125, 0.985, -0.08))):
        ring = []
        for i in range(41):
            a = 2 * math.pi * i / 40
            ring.append(Vector((r0 * math.cos(a), r0 * math.sin(a), z0 + tilt * 0.12 * math.sin(a + k))))
        C.tube(Cp.m("yarn_yellow"), ring, 0.042, sides=10, ry=0.04, caps=False)
    phi_t = math.radians(62)
    tail = [Vector((0.135 * math.cos(phi_t), 0.135 * math.sin(phi_t), 0.95))]
    for t in range(1, 9):
        th = 2.2 - 1.15 * t / 8
        p = pc(th, phi_t + 0.04 * t / 8, 0.028)
        tail.append(p)
    side = Vector((-math.sin(phi_t), math.cos(phi_t), 0))
    for s in range(4):   # 縞ごとに分けて
        seg = tail[s * 2: s * 2 + 3]
        C.tube(Cp.m("yarn_yellow" if s % 2 == 0 else "yarn_cream"), seg, 0.05, sides=8, ry=0.014, side=side, sq=4.0)
    end = tail[-1]
    for f in range(6):
        x = (f - 2.5) / 2.5 * 0.042
        q = end + side * x
        K.tube(Cp, "yarn_yellow", [q, q + Vector((0, 0.008, -0.05 - 0.01 * (f % 2)))], 0.006, sides=4)
    Cp.finish(fuzz=0.004)

    # ---- 頭（支点は首: うなずく・首をかしげる）
    Hp = K.Parts("head")
    phd, nhd = ball(Hp, "felt_snowman", ch, Rh, sh, gores=6, seed=3)
    for sx in (-1, 1):   # 目: 前から左右に 20°、まんなかより少し上
        th, phi = 1.66, math.pi / 2 + sx * math.radians(21)
        button_eye(Hp, phd(th, phi, -0.004), nhd(th, phi))
    th, phi = 1.5, math.pi / 2   # 鼻: 小さな橙のフェルトの円錐、少し下向き
    n = (nhd(th, phi) + Vector((0, 0, -0.25))).normalized()
    oriented(Hp, "felt_orange", lambda: C.lathe(Hp.m("felt_orange"), [(0.0, -0.01), (0.024, -0.01), (0.022, 0.02), (0.013, 0.045),
                                                                         (0.0, 0.06)], 14), phd(th, phi, -0.006), n)
    oriented(Hp, "thread", lambda: C.running_stitch(Hp.m("thread"), [Vector((0.0225 * math.cos(a), 0.0225 * math.sin(a), 0.006))
                                                                     for a in (2 * math.pi * i / 24 for i in range(25))],
                                                    [Vector()], dash=0.008, gap=0.006, r=0.0018), phd(th, phi, -0.006), n)
    # バケツ: 灰色のフェルトの小さなバケツを逆さに、少し傾けて
    bk = Matrix.Translation(ch + Vector((0.025, -0.01, Rh * sh - 0.035))) @ Matrix.Rotation(-0.2, 4, "Y") @ Matrix.Rotation(0.1, 4, "X")
    m = Hp.m("felt_tin")
    n0 = len(m.bm.verts)
    C.lathe(m, [(0.0, 0.0), (0.112, 0.0), (0.118, 0.012), (0.096, 0.13), (0.09, 0.14), (0.0, 0.14)], 28)
    C.place(m, n0, bk)
    for z, R in ((0.016, 0.119), (0.075, 0.108)):
        ring = [bk @ Vector((R * math.cos(a), R * math.sin(a), z)) for a in (2 * math.pi * i / 36 for i in range(37))]
        C.tube(Hp.m("felt_tin"), ring, 0.006, sides=6, caps=False)
    handle = [bk @ Vector((0.11 * math.cos(a), 0.11 * math.sin(a) * 0.35, 0.05 - 0.07 * math.sin(a))) for a in
              (math.pi * i / 16 for i in range(17))]
    K.tube(Hp, "thread_dark", handle, 0.004, sides=5)
    Hp.mark("eyes", ch + Vector((0, Rh * 0.9, 0.02)))   # 目線の目印（ゲームで顔を向ける先の基準）
    Hp.finish(fuzz=0.003)

    # ---- 腕（支点は肩: 振る）。右手（+X）にお玉、左手（-X）にベル
    arms = []
    for name, sx in (("arm_r", 1), ("arm_l", -1)):
        Ap = K.Parts(name)
        sh_p = cc + Vector((sx * 0.2, 0.03, 0.06))
        hand = cc + Vector((sx * 0.35, 0.36, 0.14 if sx > 0 else 0.1))
        mid = sh_p.lerp(hand, 0.5) + Vector((0, 0, 0.04))
        twig(Ap, [sh_p, sh_p.lerp(mid, 0.5), mid, mid.lerp(hand, 0.5), hand], 0.021, 0.011,
             forks=((2, (sx * 0.2, -0.3, 1.0), 0.07), (4, (sx * 1.0, 0.3, 0.6), 0.05), (4, (sx * 0.4, 0.6, 1.0), 0.055),
                    (4, (sx * 0.5, 1.0, -0.4), 0.045)))
        if sx > 0:   # お玉: 木の柄を立てて持ち、上に丸い椀
            a, b = hand + Vector((0.0, 0.0, -0.1)), hand + Vector((0.02, 0.03, 0.27))
            K.dowel(Ap, "wood_light", a, b, 0.012, 10)
            bowl = b + Vector((-0.078, 0.0, -0.025))   # 椀の底。柄の先が内へ曲がって椀の縁につながる
            oriented(Ap, "wood_light", lambda: C.lathe(Ap.m("wood_light"), [(0.002, 0.0), (0.03, 0.004), (0.05, 0.022), (0.058, 0.05),
                                                                            (0.053, 0.053), (0.048, 0.046), (0.041, 0.024),
                                                                            (0.024, 0.011), (0.002, 0.008)], 20),
                     bowl, (-0.15, 0.25, 1.0))
            K.tube(Ap, "wood_light", [b, b + Vector((-0.002, 0.0, 0.03)), b + Vector((-0.016, 0.0, 0.042)), b + Vector((-0.028, 0.0, 0.03))],
                   0.011, sides=8)
        else:        # 手振りのベル: 木の柄を握り、下に真鍮の鐘
            K.dowel(Ap, "wood_dark", hand + Vector((0, 0, 0.05)), hand + Vector((0, 0, -0.07)), 0.013, 10)
            K.lathe(Ap, "brass", [(0.0, 0.0), (0.05, 0.0), (0.046, 0.012), (0.034, 0.04), (0.026, 0.065), (0.016, 0.078), (0.0, 0.08)],
                    center=hand + Vector((0, 0, -0.155)), segs=24)
            K.ring(Ap, "brass", hand + Vector((0, 0, -0.153)), 0.049, 0.005, n=28)
            K.lathe(Ap, "felt_charcoal", [(0.0, 0.0), (0.012, 0.004), (0.013, 0.014), (0.0, 0.02)], center=hand + Vector((0, 0, -0.17)),
                    segs=10)
        Ap.mark("hand_" + name[-1], hand)
        Ap.finish()
        arms.append((Ap, sh_p))

    for P_, n in ((B, 1400), (Cp, 1800), (Hp, 1500)) + tuple((Ap, 450) for Ap, _ in arms):
        P_.root["tris"] = n
    shift_part(B, (0, 0, 0), top)
    shift_part(Cp, waist, B.root, (0, 0, 0))
    shift_part(Hp, neck, Cp.root, waist)
    for Ap, sh_p in arms:
        shift_part(Ap, sh_p, Cp.root, waist)
    K.made.append((top, []))
    return top, [B.root, Cp.root, Hp.root] + [Ap.root for Ap, _ in arms]


# ---------------------------------------------------------------- 冷蔵庫
W, D, H, Z0 = 1.1, 0.85, 2.0, 0.07     # 幅・奥行き・高さ・足の高さ
CW, CY0, CZ0, CZ1 = W / 2 - 0.075, -D / 2 + 0.075, 0.2, H - 0.075   # 中（半幅・奥の壁・床・天井）
NB = 7.0                                # 外板の角の丸み（超楕円の次数。小さいほど丸い）
BC = Vector((0, 0, Z0 + (H - Z0) / 2))
BH = Vector((W / 2, D / 2, (H - Z0) / 2))


def body_y(x, z, lift=0.0):
    """外板の前の面の y（x, z の所）"""
    s = 1 - (abs(x) / BH.x) ** NB - (abs(z - BC.z) / BH.z) ** NB
    return BH.y * max(0.0, s) ** (1 / NB) + lift


def fridge():
    """昔の大きな冷蔵庫: 角の丸い箱をミントのフェルトでくるみ、口の縁に玉縁。扉は開けっぱなし（蝶番は前から見て右）。
    中は白い裏地で、上に冷凍の小部屋（ふたが開いて霜）、奥の壁に冷やす管のジグザグの縫い目。床から綿の冷気が少し流れ出る"""
    P = K.Parts("snowman_fridge", kind="fridge", box=[W, H, D], door_open=100.0)
    C.superellipsoid(P.m("felt_mint"), BC, BH, n_xy=NB, n_z=NB, cuts=K.cuts(16, 9))
    # 口の玉縁と、縁のなみ縫い
    cz, ch = (CZ0 + CZ1) / 2, (CZ1 - CZ0) / 2
    pts, _n = C.ellipse_ring(CW + 0.012, ch + 0.012, n=12.0, count=120)
    pip = [Vector((p.x, body_y(p.x, cz + p.y, 0.004), cz + p.y)) for p in pts]
    C.tube(P.m("felt_mint_dark"), pip + [pip[0]], 0.017, sides=8, caps=False)
    pts, _n = C.ellipse_ring(CW + 0.045, ch + 0.045, n=12.0, count=200)
    C.running_stitch(P.m("thread"), [Vector((p.x, body_y(p.x, cz + p.y, 0.001), cz + p.y)) for p in pts + [pts[0]]], [Vector()],
                     dash=0.022, gap=0.014, r=0.003)
    # 足もとの通気口（毛糸の 3 本の桟）と、木の丸い足 4 つ
    for z in (0.095, 0.125, 0.155):
        K.tube(P, "felt_mint_dark", [(x, body_y(x, z, 0.006), z) for x in (-0.36 + 0.72 * i / 12 for i in range(13))], 0.009, sides=6)
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.lathe(P, "wood_dark", [(0.0, 0.0), (0.045, 0.0), (0.05, 0.03), (0.04, 0.07), (0.0, 0.075)],
                    center=(sx * (W / 2 - 0.12), sy * (D / 2 - 0.12), 0.0), segs=14)
    # 蝶番（前から見て右 = -X の縁）
    for z in (0.32, 1.86):
        K.lathe(P, "wood_dark", [(0.0, -0.05), (0.022, -0.05), (0.024, 0.05), (0.0, 0.05)], center=(-W / 2 + 0.012, D / 2 + 0.04, z), segs=12)
    # 冷凍の小部屋: 天井の下に棚板と、上で吊ったふた（手前へ開いている）
    fz = 1.68
    K.box(P, "felt_liner", (0, (CY0 + D / 2 - 0.08) / 2, fz), (2 * CW, D / 2 - 0.08 - CY0, 0.03))
    K.box(P, "felt_frost_blue", (0, D / 2 - 0.13, fz + 0.12), (2 * CW - 0.08, 0.02, 0.22), rot=(-1.0, "X"))
    K.lathe(P, "felt_mint_dark", [(0.0, -0.02), (0.016, -0.02), (0.016, 0.02), (0.0, 0.02)], center=(0, D / 2 - 0.02, fz + 0.15),
            segs=10, rot=(math.pi / 2, "X"))
    # 奥の壁: 冷やす管のジグザグ（青い糸のなみ縫い）
    zig = []
    for i in range(9):
        z = 0.45 + i * 0.13
        zig += [Vector((-CW + 0.12, CY0 + 0.004, z)), Vector((CW - 0.12, CY0 + 0.004, z + 0.065))]
    C.running_stitch(P.m("thread_blue"), zig, [Vector()], dash=0.03, gap=0.016, r=0.004)
    # 霜: 冷凍の棚の手前の縁に、つながった綿の帯と小さなしずく。上の隅の壁にうすく
    rnd = random.Random(5)
    frost = []
    for i in range(31):
        x = -CW + 0.03 + (2 * CW - 0.06) * i / 30
        frost.append(((x, D / 2 - 0.085 + rnd.uniform(-0.006, 0.006), fz - 0.03), rnd.uniform(0.075, 0.085), (1.4, 1.0, 0.6)))
        if i % 3 == 1:
            frost.append(((x, D / 2 - 0.09, fz - 0.05 - rnd.uniform(0, 0.02)), 0.045, (0.7, 0.7, 1.5)))
    for sx in (-1, 1):
        for k in range(9):
            frost.append(((sx * (CW - 0.004), CY0 + 0.06 + k * 0.06, fz - 0.03 - 0.05 * abs(math.sin(k * 1.7))),
                          rnd.uniform(0.1, 0.13), (0.22, 1.2, 0.8)))
        for k in range(6):
            frost.append(((sx * (CW - 0.04 - k * 0.06), CY0 + 0.004, fz - 0.03 - 0.04 * abs(math.sin(k * 2.1))), 0.11, (1.2, 0.22, 0.8)))
    K.blob(P, "frost", "cotton", frost, 0.01, lumps=0.12, fuzz=0.006)
    # 冷気: 床に溜まった綿の雲が、口の縁からもくもくとこぼれ、前の床に小さくちぎれる
    chill = []
    for i in range(12):   # 床に溜まる雲
        chill.append(((-0.36 + 0.065 * i, rnd.uniform(-0.2, 0.25), CZ0 + 0.03), rnd.uniform(0.11, 0.14), (1.1, 1.1, 0.75)))
    for row, (n, dy, z, r) in enumerate(((9, 0.03, CZ0 + 0.01, 0.13), (7, 0.08, CZ0 - 0.07, 0.115), (5, 0.13, 0.065, 0.1))):
        for i in range(n):   # 口の縁から、もくもくとこぼれる
            x = (-0.33 + 0.66 * i / (n - 1)) * (1 - 0.12 * row) + rnd.uniform(-0.02, 0.02)
            chill.append(((x, D / 2 + dy + rnd.uniform(-0.01, 0.01), z + rnd.uniform(-0.01, 0.01)), r * rnd.uniform(0.85, 1.1), (1.1, 1.0, 0.85)))
    for i in range(6):    # 前の床に、ちぎれた小さな雲
        x = rnd.uniform(-0.4, 0.4)
        chill.append(((x, D / 2 + rnd.uniform(0.22, 0.4), 0.035), rnd.uniform(0.06, 0.085), (1.2, 1.1, 0.8)))
    K.blob(P, "chill", "cotton", chill, 0.014, lumps=0.25, fuzz=0.012)
    P.root["tris"] = 4000
    P.mark("snowman_spot", (0, 0.04, CZ0))
    P.mark("chill_spot", (0, D / 2, CZ0))
    P.finish(fuzz=0.0)

    # 中をくりぬく（くりぬいた面は裏地の色。口の角は玉縁で隠れる）
    body = next(o for o in P.parts if o.name.startswith("snowman_fridge_felt_mint") and "dark" not in o.name)
    cut = C.M("cutter", "felt_liner", "stage")
    yc, yh = (CY0 + D / 2 + 0.25) / 2, (D / 2 + 0.25 - CY0) / 2
    C.superellipsoid(cut, (0, yc, cz), (CW, yh, ch), n_xy=12.0, n_z=12.0, cuts=K.cuts(16, 9))
    co = cut.done(smooth=True)
    md = body.modifiers.new("cavity", "BOOLEAN")
    md.operation, md.solver, md.object = "DIFFERENCE", "EXACT", co
    md.material_mode = "TRANSFER"
    K._active(body)
    bpy.ops.object.modifier_apply(modifier="cavity")
    bpy.data.objects.remove(co)
    if K.S["day"]:
        C.fuzz(body, 0.003, layers=2, hexcol=C.HEX["felt_mint"], sheen=0.4)

    # ---- 扉（節点 door の原点が蝶番の軸。閉じた形で組んでから開く）
    Dp = K.Parts("door", tris=2600)
    dz0, dz1, dt = 0.21, H - 0.03, 0.11
    zc, h = (dz0 + dz1) / 2, dz1 - dz0
    yc = D / 2 + dt / 2
    K.pbox(Dp, "felt_mint", (0, yc, zc), (W / 2 - 0.01, h / 2, dt / 2), n=NB, nz=2.4, seam_role="thread", rot=(math.pi / 2, "X"))

    def face_y(x, z):
        s = ((abs(x) / (W / 2 - 0.01)) ** NB + (abs(z - zc) / (h / 2)) ** NB) ** (2.4 / NB)
        return yc + dt / 2 * max(0.0, 1 - s) ** (1 / 2.4)
    # 外: 縁の内側のなみ縫い、上に赤いフェルトの雪の結晶のしるし、右の縁に太い木の取っ手（両端を大きなボタンで留める）
    pts, _n = C.ellipse_ring(W / 2 - 0.09, h / 2 - 0.09, n=NB, count=160)
    C.running_stitch(Dp.m("thread"), [Vector((p.x, face_y(p.x, zc + p.y) + 0.002, zc + p.y)) for p in pts + [pts[0]]], [Vector()],
                     dash=0.022, gap=0.014, r=0.003)
    bz = zc + 0.55
    by = face_y(0, bz)
    K.extrude(Dp, "felt_red", K.circle_poly(0.1, 28, sx=1.25), by - 0.004, by + 0.006, plane="XZ", offset=(0, 0, bz))
    for a in range(3):   # 雪の結晶: 3 本の線と、先の小さな V
        ang = math.pi * a / 3
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        K.stitch_line(Dp, "thread", [Vector((0, by + 0.008, bz)) - d * 0.07, Vector((0, by + 0.008, bz)) + d * 0.07], r=0.0028, dash=0.012)
        for s in (-1, 1):
            tip = Vector((0, by + 0.008, bz)) + d * s * 0.05
            for b in (-0.6, 0.6):
                K.tube(Dp, "thread", [tip, tip + (d * s).lerp(Vector((-d.z, 0, d.x)) * b, 0.6).normalized() * 0.02], 0.0026, sides=4)
    hx, hz0, hz1 = W / 2 - 0.12, zc - 0.12, zc + 0.3
    hy0, hy1 = face_y(hx, hz0), face_y(hx, hz1)
    K.tube(Dp, "wood_dark", [(hx, hy0, hz0), (hx, hy0 + 0.05, hz0 + 0.03), (hx, hy0 + 0.075, hz0 + 0.1), (hx, hy1 + 0.075, hz1 - 0.1),
                             (hx, hy1 + 0.05, hz1 - 0.03), (hx, hy1, hz1)], 0.028, sides=12)
    for z, y in ((hz0, hy0), (hz1, hy1)):
        K.disc(Dp, "felt_mint_dark", (hx, y + 0.003, z), 0.05, 0.012, axis="Y", segs=20)
        K.disc(Dp, "button", (hx, y + 0.014, z), 0.034, 0.014, axis="Y", segs=20)
        for a in (0.785, 2.356):
            K.tube(Dp, "thread", [(hx - 0.011 * math.cos(a), y + 0.022, z - 0.011 * math.sin(a)),
                                  (hx + 0.011 * math.cos(a), y + 0.022, z + 0.011 * math.sin(a))], 0.003, sides=4)
    K.disc(Dp, "steel", (W / 2 - 0.01, yc, zc + 0.08), 0.022, 0.012, axis="X", segs=16)   # 留めのスナップ
    # 内: 裏地の板、ふちに毛糸のパッキン、3 段の扉の棚（卵・ジャムとバター・瓶の牛乳）
    yi = D / 2
    K.extrude(Dp, "felt_liner", K.round_rect(W - 0.24, h - 0.24, 0.14), yi - 0.025, yi + 0.002, plane="XZ", offset=(0, 0, zc))
    gk = K.round_rect(W - 0.1, h - 0.1, 0.18, n=8)
    C.tube(Dp.m("yarn_gasket"), [Vector((x, yi - 0.004, zc + z)) for x, z in gk + [gk[0]]], 0.018, sides=8, caps=False)
    sw = W - 0.3
    for k, z in enumerate((zc - 0.55, zc - 0.02, zc + 0.48)):
        K.box(Dp, "felt_liner", (0, yi - 0.09, z), (sw, 0.13, 0.018))
        K.box(Dp, "felt_frost_blue", (0, yi - 0.153, z + 0.045), (sw, 0.014, 0.085))
        for sx in (-1, 1):
            K.box(Dp, "felt_frost_blue", (sx * (sw / 2 - 0.007), yi - 0.09, z + 0.045), (0.014, 0.13, 0.085))
        K.stitch_line(Dp, "thread_blue", [(-sw / 2 + 0.03, yi - 0.162, z + 0.07), (sw / 2 - 0.03, yi - 0.162, z + 0.07)], r=0.0025, dash=0.016)
        zt = z + 0.009
        if k == 2:     # 卵
            for i in range(6):
                K.lathe(Dp, "felt_bun", [(0.0, 0.0), (0.014, 0.002), (0.021, 0.015), (0.022, 0.03), (0.017, 0.046), (0.008, 0.055), (0.0, 0.057)],
                        center=(-0.3 + 0.12 * i, yi - 0.085, zt), segs=12)
        elif k == 1:   # ジャムの瓶 2 つとバター
            for x, role in ((-0.28, "felt_red"), (-0.14, "felt_orange")):
                K.lathe(Dp, role, [(0.0, 0.0), (0.04, 0.0), (0.043, 0.01), (0.043, 0.075), (0.036, 0.085), (0.0, 0.085)],
                        center=(x, yi - 0.085, zt), segs=16)
                K.disc(Dp, "paper_white", (x, yi - 0.085, zt + 0.092), 0.046, 0.016, segs=16)
                K.ring(Dp, "thread_red", (x, yi - 0.085, zt + 0.088), 0.046, 0.003, n=24)
            K.box(Dp, "felt_yellow", (0.12, yi - 0.085, zt + 0.03), (0.16, 0.07, 0.06))
            K.box(Dp, "paper_white", (0.12, yi - 0.085, zt + 0.03), (0.05, 0.074, 0.064))
        else:          # 瓶の牛乳 3 本（紙のふたに赤いふち）
            for i in range(3):
                x = -0.2 + 0.11 * i
                K.lathe(Dp, "felt_rice", [(0.0, 0.0), (0.03, 0.0), (0.032, 0.01), (0.032, 0.09), (0.024, 0.13), (0.018, 0.15),
                                          (0.019, 0.162), (0.0, 0.162)], center=(x, yi - 0.085, zt), segs=16)
                K.disc(Dp, "paper_white", (x, yi - 0.085, zt + 0.166), 0.02, 0.008, segs=12)
                K.ring(Dp, "felt_red", (x, yi - 0.085, zt + 0.163), 0.02, 0.003, n=16)
    Dp.finish(fuzz=0.003)
    shift_part(Dp, (-W / 2 + 0.012, D / 2 + 0.04, 0.0), P.root)
    Dp.root.rotation_euler.z = math.radians(100)
    return P.root, [Dp.root]


# ---------------------------------------------------------------- 書き出す
def export_tree(top, subs, path):
    """節点ごとに軽い形へ焼いてから、木のまま 1 つの glb に。subs は親から子の順"""
    saved = [(s, s.parent, s.matrix_basis.copy()) for s in subs]
    for s in reversed(subs):
        mw = s.matrix_world.copy()
        s.parent = None
        s.matrix_world = mw
    bpy.context.view_layer.update()
    for r in [top] + subs:
        if any(o.type == "MESH" for o in bpy.data.objects if o.parent == r):
            K.prepare(r)
            for o in [o for o in bpy.data.objects if o.parent == r and o.type == "MESH"]:
                o.data.transform(o.matrix_parent_inverse)   # 形を節点の座標に
                o.matrix_parent_inverse = Matrix.Identity(4)
    for s, par, mb in saved:
        s.parent = par
        s.matrix_parent_inverse = Matrix.Identity(4)
        s.matrix_basis = mb
    top.location = (0, 0, 0)   # 焼くあいだ離していたのを原点に戻す
    bpy.context.view_layer.update()
    objs = [top] + K.descendants(top)
    print("triangles", top.name, C.tri_count(objs))
    C.export(objs, path, top)


SM, SM_SUBS = snowman()
FR, FR_SUBS = fridge()

if A.export:
    SM.location = (20.0, 0.0, 0.0)   # 焼くとき、互いの陰（くぼみの陰）が写らないよう離す
    bpy.context.view_layer.update()
    only = A.only.split(",") if A.only else ["snowman", "snowman_fridge"]
    if "snowman" in only:
        export_tree(SM, SM_SUBS, os.path.join(A.export, "snowman.glb"))
    if "snowman_fridge" in only:
        export_tree(FR, FR_SUBS, os.path.join(A.export, "snowman_fridge.glb"))
else:
    spot = next(o for o in bpy.data.objects if o.name == "snowman_spot")
    SM.location = (2.1, 1.4, 0.0) if A.apart else spot.location
    K.room(floor_size=24.0, wall_y=-0.6)
    K.interior_light(1.0)
    s = Vector(SM.location)
    cams = {
        "front": ((0.0, 4.8, 1.25), (0.0, 0.0, 1.0), 35),
        "quarter": ((2.7, 3.7, 1.65), (-0.1, 0.1, 0.95), 35),
        "side": ((4.4, 0.9, 1.15), (0.0, 0.1, 0.95), 35),
        "door": ((0.4, 2.4, 1.35), (-0.85, 0.8, 1.0), 35),
        "face": ((0.45, 1.8, 1.4), (0.0, 0.1, 1.2), 40),
        "s_front": (tuple(s + Vector((0, 3.4, 0.9))), tuple(s + Vector((0, 0, 0.72))), 40),
        "s_quarter": (tuple(s + Vector((2.0, 2.6, 1.2))), tuple(s + Vector((0, 0, 0.72))), 40),
        "s_side": (tuple(s + Vector((3.3, 0.0, 0.9))), tuple(s + Vector((0, 0, 0.72))), 40),
        "s_back": (tuple(s + Vector((-0.9, -1.75, 1.3))), tuple(s + Vector((0, 0, 0.72))), 40),
    }
    K.render_views(A, cams)
