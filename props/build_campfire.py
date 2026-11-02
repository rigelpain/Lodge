"""外の焚き火の案（薪・炎・煙を 4 つずつ）を、本番の素材（フェルト・毛糸・紙・綿の毛羽）で描く。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_campfire.py -- \
        --views logs,flames,smokes --cpu --prefix design/campfire/proposal --size 1500x600

2026-11-01 代表「焚き火の木と煙のアートワークがアートコンセプトに合わないと思う」。
形は裁縫・手芸の道具と材料から借りる（design/art-concept.md）。どの列も、左から 1〜4 番。
  薪の列: 1 巻いたフェルトのロール（暖炉の薪と同じ。木口に渦の糸） 2 木の糸巻きの芯（毛糸が少し残る）
          3 太い木の編み棒（頭に毛糸の玉） 4 木のボタンを麻ひもに通して重ねた棒
  炎の列（薪は 1 番）: 1 フェルトのしずく形 3 枚（暖炉と同じ） 2 フェルトを舌の形に切って重ねる（いまのゲーム）
          3 赤・橙・黄の毛糸の房 4 薄葉紙をくしゃっと重ねる
  煙の列（薪 1・炎 1）: 1 綿のかたまりの柱（厨房の湯気と同じ） 2 引き伸ばした綿の帯（白い息と同じ）
          3 灰色のチュールの帯を重ねる 4 ほどけた灰色のモヘアの毛糸
石の輪はどれもフェルトの小石（暖炉の基壇と同じ）。
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--rows", dict(default="logs,flames,smokes", help="組む列（カンマで）")),
              ("--cpu", dict(action="store_true", help="CPU の Cycles で描く（画面が眠っていて GPU の EEVEE が進まないとき）"))])
if A.cpu:
    _setup = C.setup_render

    def _setup_cpu(size):
        _setup(size)
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 48
        sc.cycles.use_denoising = True
    C.setup_render = _setup_cpu
K.setup(A, fiber=1.5, scale=2.0)
C.HEX.update({"felt_tan": "C8925A", "yarn_flame_r": "D8442A", "yarn_flame_o": "EE8A2C", "yarn_flame_y": "F5C84A",
              "yarn_mohair": "9A9690", "yarn_spool": "B8402E", "wood_light": "D2B07E", "button": "8F6440",
              "paper_flame_r": "E0482A", "paper_flame_o": "F08A2C", "paper_flame_y": "F7C84A", "tulle": "B8B6B2"})

GAP = 1.15         # 案と案のあいだ (m)
ROWS = {"logs": 0.0, "flames": 8.0, "smokes": 16.0}   # 列ごとに横へずらす（撮るときに、ほかの列が前に入らない）
GLOW = []          # 光る素材の名前（あとで光らせる）


# ---------------------------------------------------------------- 石の輪
def stones(P, c, seed=0):
    rnd = random.Random(seed)
    for i in range(9):
        a = 2 * math.pi * i / 9 + rnd.uniform(-0.1, 0.1)
        r = rnd.uniform(0.075, 0.095)
        C.superellipsoid(P.m("felt_stone" if i % 2 else "felt_stone2"), c + Vector((math.cos(a), math.sin(a), 0)) * 0.36 + Vector((0, 0, r * 0.5)),
                         (r * 1.15, r, r * 0.7), n_xy=2.2, n_z=2.2, cuts=6)
    K.disc(P, "felt_charcoal", c + Vector((0, 0, 0.006)), 0.3, 0.012)


def teepee(P, c, make, n=5, foot=0.24, top=0.42, lying=True):
    """櫓: 下を輪の内に、上を真ん中に寄せる。下に横たえた 2 本"""
    if lying:
        for i in range(2):
            a = i * math.pi / 2 + 0.3
            d = Vector((math.cos(a), math.sin(a), 0)) * 0.24
            make(c - d + Vector((0, 0, 0.05 + i * 0.05)), c + d + Vector((0, 0, 0.05 + i * 0.05)), i)
    for i in range(n):
        a = 2 * math.pi * i / n + 0.2
        f = c + Vector((math.cos(a), math.sin(a), 0)) * foot + Vector((0, 0, 0.03))
        t = c + Vector((math.cos(a), math.sin(a), 0)) * 0.04 + Vector((0, 0, top))
        make(f, t, i + 2)


def _axes(p0, p1):
    ax = (p1 - p0).normalized()
    up = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    s = ax.cross(up).normalized()
    return ax, s, s.cross(ax).normalized()


# ---------------------------------------------------------------- 薪 4 つ
def log_felt(P):
    """1: 巻いたフェルトのロール。木口に渦の糸（暖炉の薪と同じ）"""
    def make(p0, p1, i):
        r = 0.034
        K.tube(P, "felt_tan" if i % 2 else "felt_brown", [p0, p1], r, sides=K.cuts(16, 10))
        ax, s, u = _axes(p0, p1)
        for end, sg in ((p0, -1), (p1, 1)):
            sp = []
            for k in range(36):
                t = k / 35 * 3
                rr = r * (0.1 + 0.8 * t / 3)
                sp.append(end + ax * sg * 0.002 + s * rr * math.cos(t * 2 * math.pi) + u * rr * math.sin(t * 2 * math.pi))
            K.tube(P, "felt_brown" if i % 2 else "felt_tan", sp, r * 0.05, sides=4)
    return make


def log_spool(P):
    """2: 木の糸巻きの芯。両端につば、胴の真ん中に赤い毛糸が少し残る"""
    def make(p0, p1, i):
        ax, s, u = _axes(p0, p1)
        L = (p1 - p0).length
        K.tube(P, "wood_light", [p0, p1], 0.026, sides=K.cuts(16, 10))
        for end in (p0 + ax * 0.012, p1 - ax * 0.012):
            K.tube(P, "wood_light", [end - ax * 0.012, end + ax * 0.012], 0.046, sides=K.cuts(20, 12))
        pts = []
        turns = 9
        for k in range(turns * 12 + 1):   # 毛糸を巻いた所（真ん中の半分）
            t = k / (turns * 12)
            a = t * turns * 2 * math.pi
            pts.append(p0 + ax * (L * (0.3 + 0.4 * t)) + (s * math.cos(a) + u * math.sin(a)) * 0.033)
        K.tube(P, "yarn_spool" if i % 3 else "yarn_cream", pts, 0.007, sides=6)
    return make


def log_needle(P):
    """3: 太い木の編み棒。先は細く、頭に毛糸の玉"""
    def make(p0, p1, i):
        ax, s, u = _axes(p0, p1)
        L = (p1 - p0).length
        K.tube(P, "wood", [p0 + ax * 0.06, p1], 0.017, sides=K.cuts(12, 8))
        for k, rr in enumerate((0.014, 0.010, 0.006, 0.003)):   # とがった先（下）
            K.tube(P, "wood", [p0 + ax * (0.06 - 0.015 * k), p0 + ax * (0.06 - 0.015 * (k + 1))], rr, sides=8)
        C.superellipsoid(P.m(["felt_red", "felt_navy", "felt_yellow", "felt_green"][i % 4]), p1 + ax * 0.02, (0.03, 0.03, 0.03), n_xy=2.0, n_z=2.0, cuts=5)
        if i % 2 == 0:   # 編みかけの数目が残っている
            for k in range(5):
                c = p0 + ax * (L * (0.55 + 0.05 * k))
                K.tube(P, "yarn_cream", [c + s * 0.03, c + u * 0.03, c - s * 0.03, c - u * 0.03, c + s * 0.03], 0.006, sides=5)
    return make


def log_button(P):
    """4: 木のボタンを麻ひもに通して、棒の形に重ねたもの"""
    def make(p0, p1, i):
        ax, s, u = _axes(p0, p1)
        L = (p1 - p0).length
        K.tube(P, "hemp", [p0 - ax * 0.02, p1 + ax * 0.02], 0.006, sides=6)
        n = int(L / 0.022)
        for k in range(n):
            c = p0 + ax * (L * (k + 0.5) / n)
            r = 0.032 if k % 3 else 0.036
            K.tube(P, "button", [c - ax * 0.008, c + ax * 0.008], r, sides=K.cuts(18, 12))
    return make


LOGS = [log_felt, log_spool, log_needle, log_button]


# ---------------------------------------------------------------- 炎 4 つ
def flame_drop(P, c, h=0.62, w=0.26, seed=0):
    """1: フェルトのしずく形を 3 枚、十字に重ねる（暖炉の炎と同じ）"""
    rnd = random.Random(seed)
    for k, (role, sc) in enumerate((("felt_flame_r", 1.0), ("felt_flame_o", 0.75), ("felt_flame_y", 0.5))):
        pts = []
        for i in range(24):
            t = 2 * math.pi * i / 24
            x = w * sc * 0.5 * math.sin(t) * (1 - 0.15 * math.cos(t))
            z = h * sc * (0.5 - 0.5 * math.cos(t)) ** 1.2
            x += 0.03 * h * math.sin(z / h * 6 + seed) * (z / h)
            pts.append((x, z))
        pts.reverse()
        for ang in (0.0, math.pi / 2):
            K.extrude(P, role, pts, -0.006 + 0.004 * k, 0.006 - 0.004 * k + 0.012, plane="XZ", offset=c,
                      rot=(ang + rnd.uniform(-0.2, 0.2), "Z"))


def _tongues(w, h, tips, rnd):
    pts = []
    for j in range(7):
        a = math.pi * (0.05 + 0.9 * j / 6)
        pts.append((math.cos(a) * w, -math.sin(a) * w * 0.35))
    for t in range(tips):
        x0 = -w + 2 * w * t / tips
        x1 = -w + 2 * w * (t + 1) / tips
        mid = (x0 + x1) / 2
        cen = 1 - abs(mid) / w
        th = h * (0.55 + 0.45 * cen) * rnd.uniform(0.85, 1.1)
        pts += [(x0 * 0.92, h * (0.12 if t == 0 else 0.18 + 0.2 * cen)), (x0 + (mid - x0) * 0.25, th * 0.55),
                (x0 + (mid - x0) * 0.6, th * 0.85), (mid, th), (x1 + (mid - x1) * 0.55, th * 0.8), (x1 + (mid - x1) * 0.2, th * 0.5)]
    pts.append((w * 0.95, h * 0.12))
    return list(reversed(pts))


def flame_cut(P, c, seed=0):
    """2: フェルトを舌の形に切って 3 枚重ね、十字に差す（いまのゲームの形）"""
    rnd = random.Random(seed)
    for k, (role, sc, tips) in enumerate((("felt_flame_r", 1.0, 3), ("felt_flame_o", 0.7, 2), ("felt_flame_y", 0.42, 1))):
        pts = _tongues(0.25 * sc, 0.9 * sc * 0.75, tips, rnd)
        for ang in (0.4, 0.4 + math.pi / 2):
            K.extrude(P, role, pts, -0.005 + 0.006 * k, 0.005 + 0.006 * k, plane="XZ", offset=c, rot=(ang, "Z"))


def flame_tassel(P, c, seed=0):
    """3: 赤・橙・黄の毛糸の房。束ねた根元から上へ、ゆらりと曲がって細く"""
    rnd = random.Random(seed)
    for k, (role, n, h, R) in enumerate((("yarn_flame_r", 40, 0.8, 0.17), ("yarn_flame_o", 28, 0.62, 0.11), ("yarn_flame_y", 18, 0.45, 0.06))):
        for j in range(n):
            a = rnd.uniform(0, 2 * math.pi)
            rr = R * math.sqrt(rnd.uniform(0.2, 1.0))
            base = c + Vector((math.cos(a) * rr, math.sin(a) * rr, 0.02))
            hh = h * rnd.uniform(0.7, 1.1) * (1.0 - 0.5 * rr / max(R, 1e-3) * (k == 0))
            ph = rnd.uniform(0, 6)
            pts = []
            for q in range(9):
                t = q / 8
                lean = -Vector((math.cos(a), math.sin(a), 0)) * rr * t * 0.8   # 上で真ん中へ寄る
                wob = Vector((math.cos(a + 1.6), math.sin(a + 1.6), 0)) * 0.025 * math.sin(t * 5 + ph) * t
                pts.append(base + lean + wob + Vector((0, 0, hh * t)))
            K.tube(P, role, pts, 0.011 * (1.0 if k else 1.2), sides=6)


def flame_tissue(P, c, seed=0):
    """4: 薄葉紙をくしゃっと重ねる。花びらのような紙を、外から赤・橙・黄"""
    rnd = random.Random(seed)
    for k, (role, n, h, R) in enumerate((("paper_flame_r", 7, 0.6, 0.14), ("paper_flame_o", 5, 0.46, 0.09), ("paper_flame_y", 4, 0.32, 0.05))):
        for j in range(n):
            a = 2 * math.pi * j / n + rnd.uniform(-0.3, 0.3) + k
            pts = []
            for i in range(14):
                t = math.pi * i / 13
                x = 0.13 * (1 - 0.3 * k) * math.sin(t) * (1 - 0.6 * (i / 13))   # 上ですぼまる
                z = h * (1 - math.cos(t)) / 2 * rnd.uniform(0.95, 1.05)
                pts.append((x - 0.065 * (1 - 0.3 * k), z))
            # しわ: 点を少しずらす
            pts = [(x + rnd.uniform(-0.008, 0.008), z + rnd.uniform(-0.01, 0.01)) for x, z in pts]
            K.extrude(P, role, pts, -0.002, 0.002, plane="XZ", offset=c + Vector((math.cos(a), math.sin(a), 0)) * R * 0.5,
                      rot=(a + math.pi / 2 + rnd.uniform(-0.4, 0.4), "Z"))


FLAMES = [flame_drop, flame_cut, flame_tassel, flame_tissue]


# ---------------------------------------------------------------- 煙 4 つ
def smoke_puffs(P, c, seed=0):
    """1: 綿のかたまりの柱（厨房の湯気と同じ作り）"""
    K.steam(P, c + Vector((0, 0, 0.42)), 1.0, 0.12, seed=seed)


def smoke_band(P, c, seed=0):
    """2: 引き伸ばした綿の帯。細く出て、上で太く薄くほどける（白い息と同じ考え）"""
    rnd = random.Random(seed)
    balls = []
    for j in range(40):
        t = j / 39
        p = c + Vector((0.12 * math.sin(t * 4 + 1), 0.08 * math.cos(t * 3), 0.4 + 1.2 * t))
        balls.append((p + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * 0.03 * t, 0.025 + 0.07 * t))
    K.blob(P, "band%d" % seed, "cotton", balls, 0.02, lumps=0.05, fuzz=0.03)


def smoke_tulle(P, c, seed=0):
    """3: 灰色のチュール（網目の薄い布）の帯を 3 枚、ねじりながら重ねる"""
    rnd = random.Random(seed)
    for b in range(3):
        m = P.m("tulle")
        ph = rnd.uniform(0, 6)
        rows = []
        for i in range(24):
            t = i / 23
            cx = c + Vector((0.1 * math.sin(t * 4 + ph), 0.1 * math.cos(t * 3 + ph), 0.4 + 1.25 * t))
            w = 0.05 + 0.18 * t
            ang = ph + t * 2.5 + b * 1.0
            d = Vector((math.cos(ang), math.sin(ang), 0)) * w
            rows.append((m.bm.verts.new(cx - d), m.bm.verts.new(cx + d)))
        for i in range(len(rows) - 1):
            m.bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))


def smoke_mohair(P, c, seed=0):
    """4: ほどけた灰色のモヘアの毛糸が、くねりながら上へ広がる"""
    rnd = random.Random(seed)
    for j in range(7):
        ph = rnd.uniform(0, 6)
        spread = rnd.uniform(0.1, 0.3)
        a = rnd.uniform(0, 2 * math.pi)
        pts = []
        for q in range(30):
            t = q / 29
            pts.append(c + Vector((math.cos(a) * spread * t + 0.06 * math.sin(t * 9 + ph),
                                   math.sin(a) * spread * t + 0.06 * math.cos(t * 7 + ph), 0.38 + 1.2 * t)))
        K.tube(P, "yarn_mohair", pts, 0.006, sides=6)


SMOKES = [smoke_puffs, smoke_band, smoke_tulle, smoke_mohair]


# ---------------------------------------------------------------- 並べる
def campfire(name, c, log_i, flame_i, smoke_i, small=False):
    P = K.Parts(name)
    c = Vector(c)
    stones(P, c, seed=len(name))
    teepee(P, c, LOGS[log_i](P), n=6 if log_i == 2 else 5, top=0.5 if log_i == 2 else 0.42)
    if small:   # 薪と煙の列: 薪が見えるよう、炎は小さく
        flame_drop(P, c + Vector((0, 0, 0.05)), h=0.34, w=0.2, seed=len(name))
    else:
        FLAMES[flame_i](P, c + Vector((0, 0, 0.05)), seed=len(name))
    if smoke_i >= 0:
        SMOKES[smoke_i](P, c, seed=len(name))
    P.finish(fuzz=0.004, cotton_fuzz=0.02)
    L = bpy.data.objects.new(name + "_light", bpy.data.lights.new(name + "_light", "POINT"))
    C.coll("stage").objects.link(L)
    L.location = c + Vector((0, 0, 0.3))
    L.data.energy = 60
    L.data.color = (1.0, 0.6, 0.3)
    L.data.shadow_soft_size = 0.15


ROWS_ON = A.rows.split(",")
for i in range(4):
    x = (i - 1.5) * GAP
    if "logs" in ROWS_ON:
        campfire("log%d" % (i + 1), (ROWS["logs"] + x, 0, 0), i, 0, -1, small=True)
    if "flames" in ROWS_ON:
        campfire("flame%d" % (i + 1), (ROWS["flames"] + x, 0, 0), 0, i, -1)
    if "smokes" in ROWS_ON:
        campfire("smoke%d" % (i + 1), (ROWS["smokes"] + x, 0, 0), 0, 0, i, small=True)
    print("built", i, flush=True)


def _glow(name, hexcol, strength, alpha=1.0, transmit=0.0):
    """光る素材（毛糸の房・薄葉紙の炎）と、透ける素材（チュール）"""
    m = bpy.data.materials.get(name)
    if m is None:
        return
    b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None:
        return
    if strength:
        b.inputs["Emission Color"].default_value = C.LM.lin(hexcol)
        b.inputs["Emission Strength"].default_value = strength
    if transmit:
        b.inputs["Transmission Weight"].default_value = transmit
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
        m.use_backface_culling = False


for role in ("yarn_flame_r", "yarn_flame_o", "yarn_flame_y"):
    _glow(role, C.HEX[role], 0.8)
for role in ("paper_flame_r", "paper_flame_o", "paper_flame_y"):
    _glow(role, C.HEX[role], 0.9, alpha=0.85, transmit=0.4)
_glow("tulle", "B8B6B2", 0.0, alpha=0.4)

C.ground(90.0)
C.light(elev=14.0, az=-50.0)
cams = {}
for row, x in [(r, ROWS[r]) for r in ROWS_ON]:
    cams[row] = ((x, -4.0, 1.3) if row != "smokes" else (x, -4.6, 1.2), (x, 0, 0.35 if row != "smokes" else 0.95), 34)
K.render_views(A, cams)
