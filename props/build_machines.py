"""ロッジの中の機械と小物を Blender で組む。布と糸を扱う道具の形を借りる。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_machines.py -- \
        --views line,craft,cook,cup --prefix props/renders/09-lodge

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_machines.py -- \
        --look flat --export game/props

design/game-concept.md の「ロッジで作る・買う・休む」:
  制作機   = 大きなミシンの形。ソリや服を縫う（slot_craft_rental に置く）
  焼き台   = アイロン台。台が鉄板で、アイロンで押さえて焼く（slot_food_kitchen）
  スチーマー = 服のスチーマーの湯気を、麻ひもを巻いたせいろに送って蒸す
  乾燥機   = 丸い窓の箱で、あたためる。窓は透明なフィルムに白い糸の枠（art-concept の「ガラス」）
  カップ   = 木の器に毛糸のカバー。両手で包んで持つ
  食べ物の粒 = 材料のペレット。フェルトの毛玉と、短い円柱
機械は人（背 1.6 m）が前に立って使う大きさ。ふっくらしたフェルトの箱を縫い合わせた、ぬいぐるみの機械。
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


def pbox(felt, thread, center, half, n=6.0, nz=None, seam=True, rot=None):
    """ふっくらしたフェルトの箱。横に一周、縫い合わせの耳を巻きかがる。rot は (角度, 軸)"""
    n0, t0 = len(felt.bm.verts), len(thread.bm.verts) if thread else 0
    C.superellipsoid(felt, (0, 0, 0), half, n_xy=n, n_z=nz or n, cuts=5 if EXPORT else 9)
    if seam and thread is not None:
        a, b, c = half
        pts, nrm = C.ellipse_ring(a, b, n=n, count=max(20, int(2 * (a + b) * 2 / (0.06 if EXPORT else 0.04))),
                                  z=0.0, inset=0.003)
        C.seam_whip(felt, thread, pts, nrm, out=0.012, th=0.006, r=0.005, every=2 if EXPORT else 1)
    mtx = Matrix.Translation(center)
    if rot:
        mtx = mtx @ Matrix.Rotation(rot[0], 4, rot[1])
    C.place(felt, n0, mtx)
    if thread is not None:
        C.place(thread, t0, mtx)


def dowel(m, p0, p1, r, sides=12):
    C.tube(m, [Vector(p0), Vector(p1)], r, sides=sides)


def disc(m, center, r, thick, axis="X", segs=32):
    """円板（はずみ車、つまみ）。axis の向きに厚み"""
    n0 = len(m.bm.verts)
    C.lathe(m, [(r * 0.92, -thick / 2), (r, -thick / 2 + 0.01), (r, thick / 2 - 0.01), (r * 0.92, thick / 2)], segs)
    rot = {"X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(math.pi / 2, 4, "X"), "Z": Matrix()}[axis]
    C.place(m, n0, Matrix.Translation(center) @ rot)


def steam(name, center, h, parent, seed=0, r=0.05):
    """綿の湯気: 上へ行くほど大きく薄くなる、ゆるく曲がった綿の連なり"""
    rnd = random.Random(seed)
    balls = []
    for k in range(10):
        t = k / 9
        balls.append((Vector(center) + Vector((r * 0.8 * math.sin(t * 5 + seed), r * 0.6 * math.cos(t * 4), h * t)),
                      r * (1.0 + 1.0 * t) * rnd.uniform(0.9, 1.1)))
    o = C.metablob(name, "cotton", balls, r * (0.25 if EXPORT else 0.12), parent, lumps=0.2)
    if DAY:
        C.fuzz(o, r * 0.3)
    return o


def done_all(root, parts, ms, fuzz=None):
    for m in ms:
        if m is None:
            continue
        o = m.done(parent=root)
        parts.append(o)
        if DAY and fuzz and m.role.startswith("felt") and m.role != "felt_heat":
            C.fuzz(o, fuzz, layers=2, hexcol=C.HEX.get(m.role), sheen=0.4)


# ---------------------------------------------------------------- 動かす部品
class Mover:
    """ゲームで動かす部品（針・押さえ・はずみ車など）。根元の空 mv_<key> を回す・動かす中心（pivot）に置き、
    形は pivot からの座標で持つ。書き出しでは本体と別に焼き、本体の根元の子にする（export_with_movers）"""

    def __init__(self, base, key, pivot, parent, tris=400):
        self.key, self.pivot = key, Vector(pivot)
        self.root = new_root("mv_" + key, tris=tris)
        self.root.location = self.pivot
        self.root.parent = parent
        self.base = base
        self.ms = {}
        self.parts = []

    def m(self, role):
        if role not in self.ms:
            self.ms[role] = C.M("%s_%s_%s" % (self.base, self.key, role), role)
        return self.ms[role]

    def mark(self, name, loc):
        marker(name, Vector(loc) - self.pivot, self.root, self.parts)

    def finish(self, parts, fuzz=None):
        for m in self.ms.values():
            bmesh.ops.translate(m.bm, verts=m.bm.verts, vec=-self.pivot)
        done_all(self.root, self.parts, list(self.ms.values()), fuzz=fuzz)
        parts.extend(self.parts)


# ---------------------------------------------------------------- 制作機（大きなミシン）
def craft_machine(name="craft_machine"):
    """動く部品は別の根元に分ける（game/sewing_machine.gd が動かす）:
    mv_needle（針棒と針。上下）、mv_presser（押さえ。上下）、mv_balance（はずみ車。X 軸で回る。名前の末尾に wheel を付けると Godot が車輪の節点にしてしまう）、
    mv_spool_red（立てた赤い糸巻き。Z 軸）、mv_spool_cream（寝かせたクリームの糸巻き。X 軸）、
    mv_pedal（足踏み。X 軸で揺れる）、mv_feed（布送りの歯）、mv_thread（糸の道。ゲームでは隠して張り具合を描く）。
    mv_table（作業台）は動かさないが、別に焼く"""
    root = new_root(name, slot="slot_craft_rental")
    parts = []
    wood = C.M(name + "_wood", "wood")
    body = C.M(name + "_body", "felt_navy2")
    gold = C.M(name + "_gold", "felt_gold")
    red = C.M(name + "_red", "felt_red")
    th = C.M(name + "_stitch", "thread")
    lamp = C.M(name + "_lamp", "paper")
    mv = lambda key, pivot, tris=400: Mover(name, key, pivot, root, tris)   # noqa: E731
    # 作業台: 天板と、ロクロの脚、足踏みの板。台は動かないが、本体と分けて焼く
    # （フェルトの胴と同じ組で減らすと、木の三角の取り分が少なすぎて天板や足踏みが消えていた）
    TZ = 0.85
    table = mv("table", (0, 0, 0), tris=900)
    tw = table.m("wood")
    bmesh.ops.create_cube(tw.bm, size=1.0, matrix=Matrix.Translation((0, 0, TZ - 0.03)) @ Matrix.Diagonal((2.8, 1.2, 0.06, 1)))
    for x in (-1.3, 1.3):
        for y in (-0.5, 0.5):
            C.lathe(tw, [(0.035, 0.0), (0.05, 0.05), (0.04, 0.2), (0.055, 0.4), (0.04, 0.6), (0.05, TZ - 0.06)], 12)
            C.place(tw, len(tw.bm.verts) - 12 * 6 - 2, Matrix.Translation((x, y, 0)))
    pedal = mv("pedal", (0, 0.05, 0.12))
    bmesh.ops.create_cube(pedal.m("wood").bm, size=1.0, matrix=Matrix.Translation((0, 0.05, 0.12)) @ Matrix.Rotation(-0.2, 4, "X")
                          @ Matrix.Diagonal((1.2, 0.5, 0.04, 1)))   # 足踏み
    dowel(tw, (-1.3, 0.0, 0.25), (1.3, 0.0, 0.25), 0.03)   # 脚をつなぐ貫
    # ミシンの胴: 台（ベッド）、右の柱、上の腕、左の頭
    pbox(body, th, (0, -0.05, TZ + 0.13), (1.15, 0.38, 0.13), n=10.0)
    pbox(body, th, (0.82, -0.12, TZ + 0.62), (0.24, 0.27, 0.42), n=8.0)
    pbox(body, th, (0.05, -0.12, TZ + 1.08), (0.98, 0.25, 0.17), n=10.0)
    pbox(body, th, (-0.8, -0.1, TZ + 0.9), (0.2, 0.28, 0.32), n=8.0)
    # 金の帯と、赤い帯（アップリケ）
    for x in (-0.55, -0.15, 0.25, 0.65):   # 金の小さな花の飾り
        for k in range(5):
            a = 2 * math.pi * k / 5
            pbox(gold, None, (x + 0.035 * math.cos(a), 0.13, TZ + 1.08 + 0.035 * math.sin(a) + 0.07),
                 (0.022, 0.006, 0.012), n=2.5, seam=False, rot=(a, "Y"))
    # 針棒と押さえ、針（木）
    nx, ny = -0.8, 0.08
    needle = mv("needle", (nx, ny, TZ + 0.6))
    dowel(needle.m("wood"), (nx, ny, TZ + 0.6), (nx, ny, TZ + 0.38), 0.025)
    C.tube(needle.m("wood"), [Vector((nx, ny, TZ + 0.38)), Vector((nx, ny, TZ + 0.29))], [0.012, 0.003], sides=8)
    needle.mark("eye", (nx, ny + 0.02, TZ + 0.33))   # 針の糸の通る所
    presser = mv("presser", (nx, ny, TZ + 0.6))
    bmesh.ops.create_cube(presser.m("wood").bm, size=1.0,
                          matrix=Matrix.Translation((nx, ny + 0.04, TZ + 0.275)) @ Matrix.Diagonal((0.12, 0.16, 0.02, 1)))
    dowel(presser.m("wood"), (nx - 0.05, ny - 0.02, TZ + 0.6), (nx - 0.05, ny + 0.02, TZ + 0.3), 0.012)
    # 布送りの歯: 押さえの前に、台から少しのぞく金の歯（動きを見せるため 2026-10-28 に足した）
    feed = mv("feed", (nx, ny + 0.17, TZ + 0.262))
    bmesh.ops.create_cube(feed.m("felt_gold").bm, size=1.0,
                          matrix=Matrix.Translation((nx, ny + 0.17, TZ + 0.262)) @ Matrix.Diagonal((0.11, 0.05, 0.008, 1)))
    for k in range(3):
        bmesh.ops.create_cube(feed.m("felt_gold").bm, size=1.0,
                              matrix=Matrix.Translation((nx, ny + 0.152 + 0.018 * k, TZ + 0.27)) @ Matrix.Diagonal((0.1, 0.008, 0.01, 1)))
    # はずみ車（右）
    wheel = mv("balance", (1.1, -0.12, TZ + 0.95))
    disc(wheel.m("wood"), (1.1, -0.12, TZ + 0.95), 0.27, 0.07, "X", 40)
    disc(wheel.m("wood"), (1.16, -0.12, TZ + 0.95), 0.07, 0.08, "X", 16)
    dowel(wheel.m("wood"), (1.16, -0.12 + 0.18, TZ + 0.95 + 0.0), (1.24, -0.12 + 0.18, TZ + 0.95), 0.025)   # 取っ手
    # 糸巻き: 腕の上に立てた赤い糸と、寝かせたクリームの糸
    spools = [mv("spool_red", (0.35, -0.12, TZ + 1.25)), mv("spool_cream", (-0.25, -0.12, TZ + 1.37))]
    for sp, (sx, role, lying) in zip(spools, ((0.35, "yarn_red", False), (-0.25, "yarn_cream", True))):
        sw, col = sp.m("wood"), sp.m(role)
        n0 = len(sw.bm.verts)
        C.lathe(sw, [(0.03, 0.0), (0.13, 0.0), (0.13, 0.025), (0.06, 0.03), (0.06, 0.21), (0.13, 0.215), (0.13, 0.24),
                     (0.03, 0.24)], 24)
        n1 = len(col.bm.verts)
        C.lathe(col, [(0.06, 0.03), (0.105, 0.035), (0.11, 0.12), (0.105, 0.205), (0.06, 0.21)], 24, closed=False)
        mt = Matrix.Translation((sx, -0.12, TZ + 1.25)) @ (Matrix.Rotation(math.pi / 2, 4, "Y") @ Matrix.Translation((-0.12, 0, -0.12))
                                                          if lying else Matrix())
        C.place(sw, n0, mt)
        C.place(col, n1, mt)
    dowel(wood, (0.35, -0.12, TZ + 1.22), (0.35, -0.12, TZ + 1.55), 0.015)
    # 糸の道: 糸巻きから頭の上を通って針へ。通る点を目印 thread_0..4 に残す（最後は針の eye）
    tp = [Vector((0.35, -0.02, TZ + 1.4)), Vector((0.0, 0.04, TZ + 1.3)), Vector((-0.6, 0.12, TZ + 1.26)),
          Vector((-0.78, 0.17, TZ + 1.1)), Vector((-0.8, 0.13, TZ + 0.8)), Vector((nx, ny + 0.02, TZ + 0.33))]
    thread = mv("thread", (0, 0, 0))
    C.tube(thread.m("yarn_red"), tp, 0.008, sides=5)
    # 頭の下の小さな紙の灯り
    C.superellipsoid(lamp, (-0.62, 0.0, TZ + 0.56), (0.07, 0.07, 0.05), n_xy=2.0, n_z=2.0, cuts=4)
    done_all(root, parts, [wood, body, gold, red, th, lamp], fuzz=0.004)
    for m in (table, pedal, needle, presser, feed, wheel, *spools, thread):
        m.finish(parts, fuzz=0.004)
    for k, p in enumerate(tp[:-1]):
        marker("thread_%d" % k, p, root, parts)
    marker("lamp", (-0.62, 0.0, TZ + 0.56), root, parts)   # 紙の灯りの中（ゆらぐ灯りを置く）
    marker("work", (nx, ny, TZ + 0.28), root, parts)       # 縫う物が通る所（針の下）
    marker("out", (nx, 0.45, TZ), root, parts)             # できた物が滑り出て止まる所（天板の前）
    marker("stand", (0.0, 1.1, 0.0), root, parts)          # 人が立つ所
    marker("pedal", (0.9, 0.95, 0.0), root, parts)         # もう一人が立って足踏みを踏む所
    made.append((root, parts))


# ---------------------------------------------------------------- アイロン台の焼き台
def board_outline(L=1.5, W=0.46, n=40):
    """アイロン台の形: 後ろは四角く丸め、前はとがる"""
    pts = []
    for i in range(n + 1):   # 右の縁: 後ろ → 前
        t = i / n
        y = -L / 2 + L * t
        w = W / 2 * (1 - max(0, (t - 0.45) / 0.55) ** 1.8 * 0.85)
        pts.append((w, y))
    we = pts[-1][0]   # 前の端は丸く
    tip = [(we * math.cos(math.pi * k / 8), L / 2 + we * math.sin(math.pi * k / 8)) for k in range(1, 8)]
    left = [(-x, y) for (x, y) in reversed(pts)]
    return pts + tip + left


def extrude_poly(m, poly, z0, z1):
    vb = [m.bm.verts.new((x, y, z0)) for x, y in poly]
    vt = [m.bm.verts.new((x, y, z1)) for x, y in poly]
    m.bm.faces.new(vt)
    m.bm.faces.new(list(reversed(vb)))
    for i in range(len(poly)):
        j = (i + 1) % len(poly)
        m.bm.faces.new((vb[i], vb[j], vt[j], vt[i]))


def iron_grill(name="iron_grill"):
    root = new_root(name, slot="slot_food_kitchen")
    parts = []
    wood = C.M(name + "_wood", "wood")
    cover = C.M(name + "_cover", "patch_warm")
    heat = C.M(name + "_heat", "felt_heat")
    iron = C.M(name + "_iron", "felt_red")
    sole = C.M(name + "_sole", "felt_heat")
    th = C.M(name + "_stitch", "thread")
    cord = C.M(name + "_cord", "yarn_cream")
    BZ = 0.9
    poly = board_outline()
    extrude_poly(wood, poly, BZ - 0.06, BZ - 0.03)
    # 綿を詰めたパッチワークの覆い
    inner = [(x * 1.0, y) for x, y in poly]
    extrude_poly(cover, inner, BZ - 0.035, BZ + 0.02)
    # X の脚
    for sx in (-0.17, 0.17):
        dowel(wood, (sx, -0.45, BZ - 0.06), (sx, 0.35, 0.0), 0.022)
        dowel(wood, (sx, 0.25, BZ - 0.06), (sx, -0.55, 0.0), 0.022)
    dowel(wood, (-0.2, 0.35, 0.02), (0.2, 0.35, 0.02), 0.022)
    dowel(wood, (-0.2, -0.55, 0.02), (0.2, -0.55, 0.02), 0.022)
    # 熱をもった所: 台の上の橙のフェルト（ここで焼く）
    hp = [(0.17 * math.cos(2 * math.pi * k / 32), -0.1 + 0.3 * math.sin(2 * math.pi * k / 32)) for k in range(32)]
    extrude_poly(heat, hp, BZ + 0.02, BZ + 0.03)
    path = [Vector((0.14 * math.cos(2 * math.pi * k / 48), -0.1 + 0.26 * math.sin(2 * math.pi * k / 48), BZ + 0.034))
            for k in range(49)]
    C.running_stitch(th, path, [Vector()], dash=0.03, gap=0.02, r=0.004)
    # アイロン: 台の後ろに立てて休ませる。前がとがった、ふっくらした胴と木の取っ手
    n0 = len(iron.bm.verts)
    C.superellipsoid(iron, (0, 0, 0), (0.13, 0.22, 0.09), n_xy=3.0, n_z=3.0, cuts=8)
    for v in C.new_verts(iron, n0):
        t = (v.co.y + 0.22) / 0.44
        v.co.x *= 1 - 0.65 * t ** 2
        v.co.z = max(v.co.z, -0.04) + (0.0 if v.co.z < 0 else 0.03 * (1 - t))
    s0 = len(sole.bm.verts)
    so = [(0.13 * (1 - 0.65 * ((y + 0.22) / 0.44) ** 2) * math.copysign(1, x), y) for x, y in
          [(1, -0.22 + 0.44 * k / 12) for k in range(13)] + [(-1, 0.22 - 0.44 * k / 12) for k in range(13)]]
    extrude_poly(sole, so, -0.065, -0.04)
    h0 = len(wood.bm.verts)
    C.tube(wood, [Vector((0, -0.12, 0.06)), Vector((0, -0.1, 0.17)), Vector((0, 0.05, 0.19)), Vector((0, 0.12, 0.08))],
           0.028, sides=10)
    mt = Matrix.Translation((0.0, -0.55, BZ + 0.24)) @ Matrix.Rotation(-math.pi / 2 + 0.05, 4, "X")
    C.place(iron, n0, mt)
    C.place(sole, s0, mt)
    C.place(wood, h0, mt)
    # 線: クリームの毛糸が台の後ろから垂れる
    C.tube(cord, [mt @ Vector((0, -0.24, 0.0)), Vector((0.03, -0.8, BZ - 0.05)), Vector((0.05, -0.85, 0.5)),
                  Vector((0.06, -0.82, 0.02)), Vector((0.2, -0.75, 0.01))], 0.012, sides=6)
    done_all(root, parts, [wood, cover, heat, iron, sole, th, cord], fuzz=0.004)
    marker("cook", (0.0, -0.1, BZ + 0.04), root, parts)
    marker("stand", (0.0, 0.0, 0.0), root, parts)
    made.append((root, parts))


# ---------------------------------------------------------------- スチーマー
def steamer(name="steamer"):
    root = new_root(name, slot="slot_food_kitchen")
    parts = []
    wood = C.M(name + "_wood", "wood")
    tank = C.M(name + "_tank", "felt_cream")
    th = C.M(name + "_stitch", "thread")
    hose = C.M(name + "_hose", "yarn_red")
    head = C.M(name + "_head", "felt_navy2")
    hemp = C.M(name + "_basket", "hemp")
    # 湯の缶と、立てた棒
    pbox(tank, th, (-0.35, 0, 0.26), (0.22, 0.22, 0.24), n=2.0, nz=6.0)
    dowel(wood, (-0.35, -0.1, 0.48), (-0.35, -0.1, 1.65), 0.025)
    C.tube(wood, [Vector((-0.35, -0.1, 1.65)), Vector((-0.35, -0.1, 1.72)), Vector((-0.28, -0.1, 1.74)),
                  Vector((-0.24, -0.1, 1.68))], 0.015, sides=8)   # 掛ける鉤
    # 台: 木の小さな卓にせいろを載せる
    SZ = 0.72
    bmesh.ops.create_cube(wood.bm, size=1.0, matrix=Matrix.Translation((0.3, 0, SZ - 0.025)) @ Matrix.Diagonal((0.7, 0.6, 0.05, 1)))
    for x in (0.0, 0.6):
        for y in (-0.25, 0.25):
            dowel(wood, (x, y, 0.0), (x, y, SZ - 0.05), 0.025)
    # せいろ: 麻ひもを巻き上げた 2 段の籠と蓋
    coil = []
    turns, r0, z0 = 9, 0.24, SZ
    for i in range(turns * 32 + 1):
        a = 2 * math.pi * i / 32
        coil.append(Vector((0.3 + r0 * math.cos(a), r0 * math.sin(a), z0 + 0.03 * i / 32)))
    C.tube(hemp, coil, 0.016, sides=6)
    lid = []
    for i in range(6 * 32):   # 蓋: 渦巻きに巻いた円板
        a = 2 * math.pi * i / 32
        rr = r0 + 0.02 - 0.24 * i / (6 * 32)
        lid.append(Vector((0.3 + rr * math.cos(a), rr * math.sin(a), z0 + 0.03 * turns + 0.03 + 0.02 * (1 - rr / r0))))
    C.tube(hemp, lid, 0.016, sides=6)
    C.tube(hemp, [Vector((0.3, 0, z0 + 0.32)), Vector((0.3, 0, z0 + 0.37)), Vector((0.33, 0, z0 + 0.37))], 0.02, sides=6)
    # スチーマーの頭: 毛糸のホースで缶からつなぎ、せいろの横へ湯気を吹く
    hp = [Vector((-0.35, 0.12, 0.5))]
    for k in range(1, 16):
        t = k / 15
        hp.append(Vector((-0.35 + 0.55 * t + 0.04 * math.sin(t * 14), 0.12 + 0.05 * math.cos(t * 14), 0.5 + 0.55 * math.sin(t * 2.6))))
    C.tube(hose, hp, 0.022, sides=8)
    pbox(head, th, (0.12, 0.14, 1.05), (0.08, 0.05, 0.12), n=3.0, rot=(-0.6, "Y"))
    done_all(root, parts, [wood, tank, th, hose, head, hemp], fuzz=0.004)
    parts.append(steam(name + "_steam", (0.3, 0.0, z0 + 0.4), 0.45, root, seed=1, r=0.06))
    parts.append(steam(name + "_steam2", (0.2, 0.12, 1.0), 0.3, root, seed=2, r=0.04))
    marker("cook", (0.3, 0.0, z0 + 0.05), root, parts)
    marker("stand", (0.0, 0.7, 0.0), root, parts)
    made.append((root, parts))


# ---------------------------------------------------------------- 乾燥機
def dryer(name="dryer"):
    root = new_root(name, slot="slot_food_kitchen")
    parts = []
    wood = C.M(name + "_wood", "wood")
    body = C.M(name + "_body", "felt_cream")
    navy = C.M(name + "_navy", "felt_navy2")
    th = C.M(name + "_stitch", "thread")
    film = C.M(name + "_film", "glass")
    drum = C.M(name + "_drum", "knit_drum")
    red = C.M(name + "_red", "felt_red")
    # 木の台と、ふっくらした箱
    bmesh.ops.create_cube(wood.bm, size=1.0, matrix=Matrix.Translation((0, 0, 0.07)) @ Matrix.Diagonal((0.8, 0.75, 0.14, 1)))
    BZ = 0.14 + 0.46
    pbox(body, th, (0, 0, BZ), (0.38, 0.35, 0.46), n=14.0)
    pbox(navy, None, (0, 0.0, BZ + 0.36), (0.39, 0.36, 0.035), n=14.0, seam=False)   # 上の藍の帯
    # 丸い戸: 厚いフェルトの輪、透明なフィルム、白い糸の枠、中の編み地の胴
    fy = 0.35
    cz = BZ - 0.05
    ring = [Vector((0.22 * math.cos(a), fy + 0.02, cz + 0.22 * math.sin(a))) for a in [2 * math.pi * k / 48 for k in range(48)]]
    C.tube(navy, ring + [ring[0]], 0.045, sides=10, caps=False)
    disc(film, (0, fy + 0.015, cz), 0.2, 0.006, "Y", 40)
    st = [Vector((0.185 * math.cos(a), fy + 0.024, cz + 0.185 * math.sin(a))) for a in [2 * math.pi * k / 60 for k in range(61)]]
    C.running_stitch(th, st, [Vector()], dash=0.022, gap=0.012, r=0.004)
    for k in range(6):   # フィルムを縫い留める放射の糸
        a = 2 * math.pi * k / 6 + 0.3
        C.tube(th, [Vector((0.15 * math.cos(a), fy + 0.022, cz + 0.15 * math.sin(a))),
                    Vector((0.2 * math.cos(a), fy + 0.022, cz + 0.2 * math.sin(a)))], 0.004, sides=4)
    n0 = len(drum.bm.verts)
    C.lathe(drum, [(0.19, 0.0), (0.19, -0.3), (0.0, -0.3)], 32, closed=False)
    C.place(drum, n0, Matrix.Translation((0, fy, cz)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    # つまみ: 木の丸いつまみと、目盛りを縫ったフェルトの盤
    disc(wood, (0.24, fy + 0.03, BZ + 0.3), 0.045, 0.04, "Y", 20)
    disc(red, (-0.22, fy + 0.012, BZ + 0.3), 0.06, 0.012, "Y", 24)
    for k in range(7):
        a = math.pi * (0.2 + 0.6 * k / 6)
        p = Vector((-0.22 + 0.075 * math.cos(a), fy + 0.02, BZ + 0.3 + 0.075 * math.sin(a)))
        C.tube(th, [p, p + Vector((0.018 * math.cos(a), 0, 0.018 * math.sin(a)))], 0.004, sides=4)
    done_all(root, parts, [wood, body, navy, th, film, drum, red], fuzz=0.004)
    marker("cook", (0, fy - 0.15, cz), root, parts)
    marker("stand", (0.0, 0.9, 0.0), root, parts)
    made.append((root, parts))


# ---------------------------------------------------------------- カップ
def cup(name="cup"):
    """両手で包む木の器。毛糸のカバーを巻き、湯気が立つ。実寸（直径 9 cm）"""
    root = new_root(name)
    parts = []
    wood = C.M(name + "_wood", "wood_light")
    knit = C.M(name + "_cozy", "yarn_red")
    cocoa = C.M(name + "_drink", "felt_brown")
    th = C.M(name + "_stitch", "yarn_cream")
    R, H = 0.045, 0.1
    C.lathe(wood, [(0.0, 0.0), (R * 0.8, 0.0), (R * 0.92, 0.006), (R, H * 0.3), (R * 1.04, H), (R * 0.9, H),
                   (R * 0.86, H * 0.3), (0.0, 0.012)], 40)
    # 毛糸のカバー: 縦のゴム編みの畝
    segs = 48
    prof = []
    rings = []
    for j in range(9):
        z = H * (0.18 + 0.62 * j / 8)
        rr = R * (1 + 0.04 * (z / H)) + 0.006
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            rib = 0.0035 * (0.5 + 0.5 * math.cos(a * 12))
            ring.append(knit.bm.verts.new(((rr + rib) * math.cos(a), (rr + rib) * math.sin(a), z)))
        rings.append(ring)
    for j in range(8):
        for i in range(segs):
            i2 = (i + 1) % segs
            knit.bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))
    for z in (H * 0.18, H * 0.8):   # 上下の縁の巻き
        rr = R * (1 + 0.04 * (z / H)) + 0.008
        pts = [Vector((rr * math.cos(a), rr * math.sin(a), z)) for a in [2 * math.pi * k / 40 for k in range(41)]]
        C.tube(knit, pts, 0.005, sides=6, caps=False)
    # 飾りの糸: クリームのなみ縫いの線
    pts = [Vector(((R * 1.03 + 0.012) * math.cos(a), (R * 1.03 + 0.012) * math.sin(a), H * 0.5)) for a in
           [2 * math.pi * k / 60 for k in range(61)]]
    C.running_stitch(th, pts, [Vector()], dash=0.012, gap=0.007, r=0.002)
    bmesh.ops.create_circle(cocoa.bm, cap_ends=True, segments=32, radius=R * 0.88, matrix=Matrix.Translation((0, 0, H * 0.85)))
    done_all(root, parts, [wood, knit, cocoa, th])
    parts.append(steam(name + "_steam", (0, 0, H * 0.95), 0.12, root, seed=3, r=0.014))
    marker("hand_l", (-R - 0.02, 0, H * 0.5), root, parts)
    marker("hand_r", (R + 0.02, 0, H * 0.5), root, parts)
    made.append((root, parts))


# ---------------------------------------------------------------- 食べ物の粒
def pellets(name="food_pellets"):
    """材料のペレット: フェルトの毛玉 4 色と、短い円柱 2 色。pellet_0..5"""
    root = new_root(name)
    parts = []
    rnd = random.Random(5)
    specs = [("ball", "felt_beige"), ("ball", "felt_brown"), ("ball", "felt_red"), ("ball", "felt_green"),
             ("rod", "felt_yellow"), ("rod", "felt_beige")]
    for i, (kind, role) in enumerate(specs):
        m = C.M("pellet_%d" % i, role)
        r = 0.022
        if kind == "ball":
            C.superellipsoid(m, (0, 0, r), (r, r, r * 0.92), n_xy=2.0, n_z=2.0, cuts=4 if EXPORT else 7)
        else:
            C.superellipsoid(m, (0, 0, r * 0.7), (r * 0.7, r * 1.4, r * 0.7), n_xy=2.0, n_z=2.0, cuts=4 if EXPORT else 7)
            for v in m.bm.verts:   # 円柱: 長い向きの両端を平らに
                v.co.y = max(-r * 1.2, min(r * 1.2, v.co.y))
        for v in m.bm.verts:
            v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * r * 0.04
        o = m.done(parent=root)
        o.location = (i * 0.07 - 0.18, 0, 0)
        if DAY:
            C.fuzz(o, r * 0.12, layers=3, hexcol=C.HEX[role], sheen=0.5)
        parts.append(o)
    made.append((root, parts))


# ---------------------------------------------------------------- 組む
craft_machine()
iron_grill()
steamer()
dryer()
cup()
pellets()


def interior_light():
    """ロッジの中: 電球色より少し赤みの灯りと、暗めの環境"""
    sc = bpy.context.scene
    w = bpy.data.worlds.new("room")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.30, 0.26, 0.22, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    sc.world = w
    warm = (1.0, 0.76, 0.52)
    for (x, y, z, e) in ((-2.0, 2.5, 3.2, 700), (2.5, 3.0, 3.0, 550), (0.0, -0.8, 3.4, 350), (-4.5, 1.0, 2.6, 300)):
        L = bpy.data.objects.new("lamp", bpy.data.lights.new("lamp", "POINT"))
        C.coll("stage").objects.link(L)
        L.location = (x, y, z)
        L.data.energy = e
        L.data.color = warm
        L.data.shadow_soft_size = 0.6
    sun = bpy.data.objects.new("window", bpy.data.lights.new("window", "SUN"))   # 窓からの外の青い光
    C.coll("stage").objects.link(sun)
    sun.data.energy = 1.2
    sun.data.color = (0.75, 0.85, 1.0)
    sun.rotation_euler = (math.radians(60), 0, math.radians(160))


if not A.export:
    place = {"craft_machine": (-3.2, 0.0, 0.0), "iron_grill": (0.0, -0.2, 0.0), "steamer": (1.3, 0.0, 0.0),
             "dryer": (2.7, 0.0, 0.0), "cup": (0.62, 0.55, 0.62), "food_pellets": (0.9, 0.6, 0.62)}
    # カップと粒を載せる小さな卓（描くときだけ）
    side = C.M("side_table", "wood", "stage")
    bmesh.ops.create_cube(side.bm, size=1.0, matrix=Matrix.Translation((0.8, 0.6, 0.6)) @ Matrix.Diagonal((0.6, 0.4, 0.04, 1)))
    for x in (0.55, 1.05):
        for y in (0.45, 0.75):
            dowel(side, (x, y, 0.0), (x, y, 0.58), 0.02)
    side.done(smooth=False)
    for root, parts in made:
        x, y, z = place[root.name]
        root.location = (x, y, z)
    # 床: ロッジの床板。奥に板の壁
    fl = C.M("floor", "floor", "stage")
    bmesh.ops.create_grid(fl.bm, x_segments=2, y_segments=2, size=8.0)
    fl.done(smooth=False)
    wall = C.M("wall", "felt_beige", "stage")
    bmesh.ops.create_cube(wall.bm, size=1.0, matrix=Matrix.Translation((0, -1.2, 3.0)) @ Matrix.Diagonal((16, 0.1, 6.0, 1)))
    wall.done(smooth=False)
    interior_light()
    C.setup_render(A.size)
    bpy.context.scene.view_settings.exposure = 0.0
    cams = {
        "line": ((-0.6, 7.6, 2.3), (-0.5, 0.0, 0.9), 27),
        "craft": ((-1.6, 3.0, 1.9), (-3.2, 0.0, 1.3), 34),
        "cook": ((1.9, 2.8, 1.6), (1.4, 0.0, 0.8), 32),
        "cup": ((0.95, 1.35, 0.95), (0.78, 0.6, 0.66), 42),
    }
    for root, parts in made:
        print("triangles", root.name, C.tri_count(parts))
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    for v in A.views.split(","):
        loc, tgt, lens = cams[v]
        C.render(loc, tgt, lens, os.path.abspath("%s-%s.png" % (A.prefix, v)))
else:
    def export_with_movers(root, path, k, tris):
        """動かす部品（mv_*）を本体から外して別に焼き、本体を焼いてから子に戻して 1 つの glb に"""
        movers = [o for o in root.children if o.name.startswith("mv_")]
        K.S["scale"] = k
        for o in movers:
            o.parent = None
            o.location = o.location * k
            K.prepare(o)
        root["tris"] = tris
        K.prepare(root)
        for o in movers:
            o.parent = root
        objs = [root] + K.descendants(root)
        print("triangles", root.name, C.tri_count(objs))
        C.export(objs, path, root)

    for root, parts in made:
        print("triangles", root.name, C.tri_count(parts))
        k = 1.5 if root.name in ("craft_machine", "cup", "food_pellets") else 2.0   # ミシンは貸出に収まるよう、手に持つ物は食べ物と同じ 1.5 倍
        tris = 1200 if root.name in ("cup", "food_pellets") else 4000
        path = os.path.join(A.export, "%s.glb" % root.name)
        if any(o.name.startswith("mv_") for o in root.children):
            export_with_movers(root, path, k, tris)
        else:
            K.export_root(root, path, k, tris=tris)
