"""ロッジを Blender で組む。寸法はすべて dims.py。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P lodge/build_lodge.py -- \
        --phase 4 --views hill,west --prefix lodge/renders/04-setsue

段階は積み上がる。
  1 塊: 長方形と屋根の外形だけ。重心とシルエットを見る
  2 開口: 丸太の壁、ガラスの壁、窓と戸（凹み・見込み・窓台）
  3 冠: 垂木の見える軒、雪の毛布、煙突の笠、手すり、外階段、デッキ、下屋
  4 設え: 中の家具、貸出、機械の置き場の目印
段階 3 までは素材を粘土の濃淡だけにして、形だけを見る。
"""
import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dims import *  # noqa: E402,F403

ap = argparse.ArgumentParser()
ap.add_argument("--phase", type=int, default=4)
ap.add_argument("--views", default="hill")
ap.add_argument("--prefix", default="/tmp/lodge")
ap.add_argument("--size", default="1280x800")
ap.add_argument("--blend", default="")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
PH = A.phase

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---------------------------------------------------------------- 素材（粘土の濃淡）
CLAY = {
    "log": (0.74, 0.69, 0.62), "post": (0.50, 0.45, 0.40), "frame": (0.90, 0.88, 0.82),
    "board": (0.68, 0.62, 0.54), "door": (0.46, 0.38, 0.31), "deck": (0.64, 0.58, 0.50),
    "rail": (0.60, 0.55, 0.48), "stone": (0.58, 0.57, 0.55), "roof": (0.17, 0.20, 0.40),
    "snow": (0.92, 0.93, 0.96), "glass": (0.10, 0.13, 0.18), "metal": (0.22, 0.22, 0.24),
    "dark": (0.05, 0.04, 0.04), "tatami": (0.76, 0.74, 0.56), "cushion": (0.70, 0.46, 0.36),
    "quilt": (0.66, 0.52, 0.40), "paper": (0.95, 0.92, 0.85), "felt_red": (0.62, 0.30, 0.25),
    "felt_blue": (0.28, 0.38, 0.60), "felt_green": (0.40, 0.52, 0.32), "felt_yellow": (0.80, 0.64, 0.30),
}
MAT = {}


def mat(role):
    if role not in MAT:
        m = bpy.data.materials.new(role)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*CLAY[role], 1)
        b.inputs["Roughness"].default_value = 0.06 if role == "glass" else 0.85
        MAT[role] = m
    return MAT[role]


def coll(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        sc.collection.children.link(c)
    return c


# ---------------------------------------------------------------- 形の集まり
class M:
    """1 つの物体にまとめる形。最後に done() で物体にする"""

    def __init__(self, name, role, group):
        self.name, self.role, self.group = name, role, group
        self.bm = bmesh.new()

    def box(self, x0, y0, z0, x1, y1, z1):
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        z0, z1 = sorted((z0, z1))
        if min(x1 - x0, y1 - y0, z1 - z0) < 1e-4:
            return
        mtx = Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)) @ Matrix.Diagonal(
            (x1 - x0, y1 - y0, z1 - z0, 1))
        bmesh.ops.create_cube(self.bm, size=1, matrix=mtx)

    def cyl(self, p0, p1, r, seg=12):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r,
                              depth=d.length, matrix=Matrix.Translation((p0 + p1) / 2) @ rot)

    def solid(self, bottom, top):
        """同じ数の頂点を持つ下と上の輪を面でつなぐ"""
        n = len(bottom)
        vs = [self.bm.verts.new(p) for p in list(bottom) + list(top)]
        self.bm.faces.new(vs[:n][::-1])
        self.bm.faces.new(vs[n:])
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((vs[i], vs[j], vs[n + j], vs[n + i]))

    def prism_x(self, prof, x0, x1):
        """y-z の多角形（反時計回り）を x0..x1 に押し出す"""
        self.solid([(x0, y, z) for y, z in prof][::-1], [(x1, y, z) for y, z in prof][::-1])

    def prism_y(self, prof, y0, y1):
        """x-z の多角形（反時計回り）を y0..y1 に押し出す"""
        self.solid([(x, y0, z) for x, z in prof], [(x, y1, z) for x, z in prof])

    def beam(self, p0, p1, w, h):
        """p0 から p1 へ渡す角材。断面は水平に w、鉛直に h"""
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        n = d.cross(Vector((0, 0, 1)))
        n = n.normalized() if n.length > 1e-6 else Vector((1, 0, 0))
        up = Vector((0, 0, h / 2))
        ring = [n * w / 2 - up, -n * w / 2 - up, -n * w / 2 + up, n * w / 2 + up]
        self.solid([p0 + v for v in ring], [p1 + v for v in ring])

    def hull(self, pts):
        vs = [self.bm.verts.new(p) for p in pts]
        bmesh.ops.convex_hull(self.bm, input=vs)

    def done(self, bevel=0.0, seg=2, array=None, smooth=False):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        self.bm.to_mesh(me)
        self.bm.free()
        o = bpy.data.objects.new(self.name, me)
        coll(self.group).objects.link(o)
        me.materials.append(mat(self.role))
        if smooth:
            me.shade_smooth()
            try:
                me.set_sharp_from_angle(angle=math.radians(40))
            except AttributeError:
                pass
        if array:
            count, off = array
            a = o.modifiers.new("array", "ARRAY")
            a.count = count
            a.use_relative_offset = False
            a.use_constant_offset = True
            a.constant_offset_displace = off
        if bevel:
            b = o.modifiers.new("bevel", "BEVEL")
            b.width = bevel
            b.segments = seg
            b.limit_method = "ANGLE"
        return o


def cutter(name, x0, y0, z0, x1, y1, z1):
    m = M(name, "dark", "cutters")
    m.box(x0, y0, z0, x1, y1, z1)
    o = m.done()
    o.hide_render = True
    o.display_type = "WIRE"
    return o


def cut(obj, cut_obj):
    b = obj.modifiers.new("cut_" + cut_obj.name, "BOOLEAN")
    b.operation = "DIFFERENCE"
    b.object = cut_obj
    b.use_self = True   # 雪の毛布と雪庇の円柱のように重なった形でも切れるように
    for solver in ("EXACT", "MANIFOLD", "FLOAT"):
        try:
            b.solver = solver
            break
        except TypeError:
            continue


def wbox(m, axis, fixed, sgn, u0, u1, v0, v1, z0, z1):
    """壁に沿った座標（u: 壁に沿う、v: 壁の芯から外へ、z）で箱を置く"""
    a, b = fixed + sgn * v0, fixed + sgn * v1
    if axis == "x":
        m.box(u0, a, z0, u1, b, z1)
    else:
        m.box(a, u0, z0, b, u1, z1)


# ---------------------------------------------------------------- 丸太の壁
R = LOG_D / 2


def courses(z0, z1, offset):
    """段の芯の高さの列。offset の壁は下に半分の丸太（土台）が入る"""
    out, i = [], 0
    while True:
        zc = z0 + offset + LOG_H * (i + 0.5)
        if zc + LOG_H / 2 > z1 + 0.02:
            return out
        out.append(zc)
        i += 1


def snap(z0, z1, offset, hb, ht):
    """開口が抜く段の範囲（芯が開口の中にある段を抜く）。窓の実際の上下になる"""
    cs = [zc for zc in courses(z0, z1, offset) if hb < zc < ht]
    if hb <= z0 + 1e-6:
        return z0, (cs[-1] + LOG_H / 2) if cs else ht
    return cs[0] - LOG_H / 2, cs[-1] + LOG_H / 2


def subtract(segs, h0, h1):
    out = []
    for s0, s1 in segs:
        if h1 <= s0 or h0 >= s1:
            out.append((s0, s1))
            continue
        if h0 > s0:
            out.append((s0, h0))
        if h1 < s1:
            out.append((h1, s1))
    return out


def log_wall(m, axis, fixed, a0, a1, z0, z1, offset, holes=(), top=None):
    """丸太を段に積む。holes は (u0, u1, 下, 上)。top(z) はその高さで丸太が届く u の上限（妻）"""
    if offset:
        segs = [(a0, a1)]
        for h0, h1, hb, ht in holes:
            if hb <= z0 + 1e-6:
                segs = subtract(segs, h0, h1)
        for s0, s1 in segs:
            p = (s0, fixed) if axis == "x" else (fixed, s0)
            q = (s1, fixed) if axis == "x" else (fixed, s1)
            m.box(p[0] - (0 if axis == "x" else R), p[1] - (R if axis == "x" else 0), z0,
                  q[0] + (0 if axis == "x" else R), q[1] + (R if axis == "x" else 0), z0 + offset)
    last = z0 + offset
    for zc in courses(z0, z1, offset):
        hi = a1 if top is None else min(a1, top(zc + R))
        segs = [(a0, hi)] if hi > a0 else []
        for h0, h1, hb, ht in holes:
            if hb < zc < ht or (hb <= z0 + 1e-6 and zc < ht):
                segs = subtract(segs, h0, h1)
        for s0, s1 in segs:
            if s1 - s0 > 0.08:
                if axis == "x":
                    m.cyl((s0, fixed, zc), (s1, fixed, zc), R)
                else:
                    m.cyl((fixed, s0, zc), (fixed, s1, zc), R)
        last = zc + LOG_H / 2
    return last


# ---------------------------------------------------------------- 窓と戸
def opening(F, G, D, axis, fixed, sgn, c, w, cb, ct, kind):
    """窓・戸の枠。F 枠、G ガラス、D 戸板。cb..ct が丸太を抜いた範囲"""
    t = R
    u0, u1 = c - w / 2, c + w / 2
    L = 0.045                                  # 見込みの板（壁の厚みいっぱい）
    wbox(F, axis, fixed, sgn, u0, u0 + L, -t - 0.01, t + 0.01, cb, ct)
    wbox(F, axis, fixed, sgn, u1 - L, u1, -t - 0.01, t + 0.01, cb, ct)
    wbox(F, axis, fixed, sgn, u0, u1, -t - 0.01, t + 0.01, ct - L, ct)
    if kind == "win":
        wbox(F, axis, fixed, sgn, u0, u1, -t - 0.01, t + 0.01, cb, cb + L)
    for s in (1, -1):                          # 外と中の額縁（丸太の木口を隠す）
        v0, v1 = (t, t + 0.03) if s > 0 else (-t - 0.03, -t)
        wbox(F, axis, fixed, sgn, u0 - 0.09, u0, v0, v1, cb if kind == "win" else cb, ct + 0.09)
        wbox(F, axis, fixed, sgn, u1, u1 + 0.09, v0, v1, cb, ct + 0.09)
        wbox(F, axis, fixed, sgn, u0 - 0.09, u1 + 0.09, v0, v1, ct, ct + 0.09)
    wbox(F, axis, fixed, sgn, u0 - 0.13, u1 + 0.13, t, t + 0.08, ct + 0.09, ct + 0.13)   # 水切り
    if kind == "win":
        wbox(F, axis, fixed, sgn, u0 - 0.15, u1 + 0.15, t - 0.02, t + 0.15, cb - 0.06, cb)   # 窓台
        wbox(F, axis, fixed, sgn, u0 - 0.05, u1 + 0.05, -t - 0.08, -t + 0.02, cb - 0.04, cb)   # 中の窓台
        i0, i1, j0, j1 = u0 + L, u1 - L, cb + L, ct - L
        S = 0.05
        wbox(F, axis, fixed, sgn, i0, i1, -0.03, 0.03, j0, j0 + S)
        wbox(F, axis, fixed, sgn, i0, i1, -0.03, 0.03, j1 - S, j1)
        wbox(F, axis, fixed, sgn, i0, i0 + S, -0.03, 0.03, j0, j1)
        wbox(F, axis, fixed, sgn, i1 - S, i1, -0.03, 0.03, j0, j1)
        wbox(F, axis, fixed, sgn, (i0 + i1) / 2 - 0.022, (i0 + i1) / 2 + 0.022, -0.025, 0.025, j0, j1)
        wbox(F, axis, fixed, sgn, i0, i1, -0.025, 0.025, (j0 + j1) / 2 - 0.022, (j0 + j1) / 2 + 0.022)
        wbox(G, axis, fixed, sgn, i0, i1, -0.006, 0.006, j0, j1)
    else:
        wbox(F, axis, fixed, sgn, u0 - 0.05, u1 + 0.05, -t, t + 0.06, cb, cb + 0.03)   # 敷居
        leaves = 2 if w > 1.2 else 1
        lw = (w - 2 * L) / leaves
        for k in range(leaves):
            door_leaf(D, G, axis, fixed, sgn, u0 + L + k * lw + 0.005, u0 + L + (k + 1) * lw - 0.005,
                      cb + 0.03, ct - L, -0.06, -0.01)


def door_leaf(D, G, axis, fixed, sgn, u0, u1, z0, z1, v0, v1, glass=0.55):
    """框戸。上にガラス、下に板"""
    S = 0.09
    g0 = z0 + (z1 - z0) * (1 - glass)
    wbox(D, axis, fixed, sgn, u0, u0 + S, v0, v1, z0, z1)
    wbox(D, axis, fixed, sgn, u1 - S, u1, v0, v1, z0, z1)
    wbox(D, axis, fixed, sgn, u0, u1, v0, v1, z1 - S, z1)
    wbox(D, axis, fixed, sgn, u0, u1, v0, v1, g0 - S, g0)
    wbox(D, axis, fixed, sgn, u0 + S, u1 - S, v0 + 0.015, v1 - 0.015, z0, g0 - S)
    wbox(G, axis, fixed, sgn, u0 + S, u1 - S, (v0 + v1) / 2 - 0.005, (v0 + v1) / 2 + 0.005, g0, z1 - S)


def glass_wall(P, F, G, D, axis, fixed, sgn, posts, z0, z1, door_bay=None):
    """柱とガラスの壁。各間に縦桟 1 本と欄間の横桟"""
    posts = sorted(posts)
    for u in posts:
        wbox(P, axis, fixed, sgn, u - POST / 2, u + POST / 2, -POST / 2, POST / 2, z0, z1)
    for k, (a, b) in enumerate(zip(posts, posts[1:])):
        a, b = a + POST / 2, b - POST / 2
        wbox(F, axis, fixed, sgn, a, b, -0.09, 0.09, z0, z0 + 0.10)
        wbox(F, axis, fixed, sgn, a, b, -0.09, 0.09, z1 - 0.14, z1)
        wbox(F, axis, fixed, sgn, a, b, -0.05, 0.05, TRANSOM - 0.045, TRANSOM + 0.045)
        wbox(F, axis, fixed, sgn, a - 0.02, b + 0.02, 0.09, 0.14, z0 - 0.02, z0 + 0.04)   # 外の水切り
        mid = (a + b) / 2
        if k == door_bay:
            for u0, u1 in ((a, mid), (mid, b)):
                door_leaf(D, G, axis, fixed, sgn, u0 + 0.01, u1 - 0.01, z0 + 0.10, TRANSOM - 0.045,
                          -0.04, 0.04, glass=0.8)
            wbox(G, axis, fixed, sgn, a, b, -0.005, 0.005, TRANSOM, z1 - 0.14)
            continue
        wbox(F, axis, fixed, sgn, mid - 0.03, mid + 0.03, -0.05, 0.05, z0, z1)
        for u0, u1 in ((a, mid - 0.03), (mid + 0.03, b)):
            wbox(G, axis, fixed, sgn, u0, u1, -0.005, 0.005, z0 + 0.10, z1 - 0.14)


# ---------------------------------------------------------------- 段階 1: 塊
def build_massing():
    m = M("massing_lodge", "log", "massing")
    m.box(X0, Y0, FL1, X1, Y1, CEIL1)
    m.prism_x([(Y2_0, FL2), (Y2_1, FL2), (Y2_1, EAVE_N), (Y2_0, EAVE_S)], X0, X1)
    m.box(VEST["x0"], Y0 - VEST["d"], FL1, VEST["x1"], Y0, VEST["h"])
    m.done()
    r = M("massing_rail", "log", "massing")
    r.box(X0, Y0, FL2, X1, Y0 + 0.08, FL2 + RAIL_H)
    r.done()
    g = M("massing_glass", "glass", "massing")
    g.box(GLASS_S_X0, Y0 - 0.01, FL1 + 0.1, X1, Y0, CEIL1 - 0.14)
    g.box(X0 - 0.01, Y0, FL1 + 0.1, X0, Y1, CEIL1 - 0.14)
    g.done()
    s = M("massing_stair", "deck", "massing")
    E = ESTAIR
    s.prism_x([(E["y_start"], FL1), (E["y_land"], E["z_land"]), (E["y_land"], E["z_land"] - 0.3),
               (E["y_start"], FL1 - 0.3)][::-1], *E["x_lo"])
    s.prism_x([(E["y_land"], E["z_land"]), (E["y_start"], FL2), (E["y_start"], FL2 - 0.3),
               (E["y_land"], E["z_land"] - 0.3)], *E["x_up"])
    s.box(E["x_lo"][0], E["y_land"] - E["landing"], E["z_land"] - 0.15, E["x_up"][1], E["y_land"], E["z_land"])
    s.box(E["x_up"][0], E["y_start"], FL2 - 0.15, E["x_up"][1], Y0, FL2)
    s.done()


# ---------------------------------------------------------------- 共通: 基壇・床・煙突・下屋の屋根・デッキ
def build_base():
    st = M("plinth", "stone", "walls")
    st.box(X0 - 0.15, Y0 - 0.15, 0, X1 + 0.15, Y1 + 0.15, PLINTH)
    st.done(bevel=0.03 if PH >= 3 else 0)
    fl = M("floor2", "board", "walls")
    fl.box(X0 - 0.09, Y0 - 0.09, CEIL1, X1 + 0.09, Y1 + 0.09, FL2)
    f = fl.done(bevel=0.015 if PH >= 2 else 0)
    if PH >= 2:
        I = INSTAIR
        cut(f, cutter("cut_stairwell", I["x0"] - 0.05, I["y_bottom"] + 0.8, CEIL1 - 0.1, I["x1"] + 0.2,
                      I["y_top"] + 0.05, FL2 + 0.1))
    dk = M("deck", "deck", "crown")
    D_ = DECK
    if PH >= 3:
        dk.box(D_["x0"], D_["y0"], D_["z"] - 0.30, D_["x1"], D_["y1"], D_["z"] - 0.05)   # 鼻隠しの箱
        dk.box(D_["x1"], D_["y0"], 0, D_["x1"] + 0.30, D_["y1"], D_["z"] - 0.15)          # 東の段
        dk.box(D_["x1"] + 0.30, D_["y0"], 0, D_["x1"] + 0.60, D_["y1"], D_["z"] - 0.30)
        dk.done(bevel=0.012)
        n = int((D_["y1"] - D_["y0"]) / 0.15)
        b = M("deck_boards", "deck", "crown")
        b.box(D_["x0"] - 0.03, D_["y0"] - 0.03, D_["z"] - 0.05, D_["x1"], D_["y0"] + 0.135, D_["z"])
        b.done(bevel=0.01, array=(n, (0, 0.15, 0)))
    else:
        dk.box(D_["x0"], D_["y0"], 0, D_["x1"], D_["y1"], D_["z"])
        dk.done()


def build_chimney():
    c = CH
    m = M("chimney", "stone", "walls")
    sh = FL2 - 0.40
    m.box(c["x0"], c["y0"], 0, c["x1"], c["y1"], sh)
    if PH >= 3:
        m.hull([(x, y, sh) for x in (c["x0"], c["x1"]) for y in (c["y0"], c["y1"])] +
               [(x, y, FL2 + 0.35) for x in (c["ux0"], c["ux1"]) for y in (c["uy0"], c["uy1"])])
        m.box(c["ux0"], c["uy0"], FL2 + 0.35, c["ux1"], c["uy1"], c["top"])
        o = c["cap_out"]
        m.box(c["ux0"] - o / 2, c["uy0"] - o / 2, c["top"], c["ux1"] + o / 2, c["uy1"] + o / 2, c["top"] + 0.12)
        for x, y in ((c["ux0"], c["uy0"]), (c["ux1"] - 0.24, c["uy0"]), (c["ux0"], c["uy1"] - 0.24),
                     (c["ux1"] - 0.24, c["uy1"] - 0.24)):
            m.box(x, y, c["top"] + 0.12, x + 0.24, y + 0.24, c["top"] + 0.40)
        m.box(c["ux0"] - o, c["uy0"] - o, c["top"] + 0.40, c["ux1"] + o, c["uy1"] + o, c["top"] + 0.40 + c["cap_t"])
    else:
        m.box(c["ux0"], c["uy0"], sh, c["ux1"], c["uy1"], c["top"])
    ch = m.done(bevel=0.03 if PH >= 3 else 0)
    if PH >= 2:   # 炉の口（1 階の中へ）
        cx = (c["x0"] + c["x1"]) / 2
        cut(ch, cutter("cut_firebox", cx - 0.55, c["y0"] - 0.1, FL1 + 0.18, cx + 0.55, c["y0"] + 0.55, FL1 + 1.05))
        h = M("hearth", "stone", "walls")
        h.box(c["x0"] - 0.25, c["y0"] - 0.65, FL1, c["x1"] + 0.25, c["y0"], FL1 + 0.12)
        h.done(bevel=0.02)
        mt = M("mantel", "board", "walls")
        mt.box(c["x0"] - 0.10, c["y0"] - 0.22, FL1 + 1.45, c["x1"] + 0.10, c["y0"] + 0.02, FL1 + 1.55)
        mt.done(bevel=0.012)


def roof_cutters():
    c = CH
    return cutter("cut_chimney_roof", c["ux0"] - 0.03, c["uy0"] - 0.03, 0, c["ux1"] + 0.03, c["uy1"] + 0.03, 20)


def build_roof(chim_cut):
    ys, yn = Y2_0 - EAVE_OUT_S, Y2_1 + EAVE_OUT_N
    lift = RAFTER["h"] if PH >= 3 else 0.0
    tv = ROOF_T / math.cos(math.atan(ROOF_PITCH))
    zs, zn = roof_z(ys) + lift, roof_z(yn) + lift
    xa, xb = X0 - VERGE_OUT, X1 + VERGE_OUT
    r = M("roof", "roof", "crown")
    r.prism_x([(ys, zs), (yn, zn), (yn, zn + tv), (ys, zs + tv)][::-1], xa, xb)
    ro = r.done(bevel=0.03 if PH >= 3 else 0, seg=2)
    cut(ro, chim_cut)
    sv = SNOW_T / math.cos(math.atan(ROOF_PITCH))
    s = M("roof_snow", "snow", "crown")
    s.prism_x([(ys + 0.06, zs + tv - 0.02), (yn + 0.04, zn + tv - 0.02), (yn + 0.04, zn + tv + sv),
               (ys + 0.06, zs + tv + sv)][::-1], xa + 0.10, xb - 0.10)
    if PH >= 3:   # 北の軒先で雪が垂れる（雪庇）
        s.cyl((xa + 0.25, yn + 0.06, zn + tv + 0.02), (xb - 0.25, yn + 0.06, zn + tv + 0.02), 0.17, seg=16)
    so = s.done(bevel=0.10 if PH >= 3 else 0, seg=4, smooth=PH >= 3)
    cut(so, chim_cut)
    if PH >= 3:
        # 垂木: 北の軒から南の軒まで、半間ごと。南の軒の下に木口が並ぶ
        w, h = RAFTER["w"], RAFTER["h"]
        x = xa + 0.25
        n = int((xb - 0.25 - x) / RAFTER["step"]) + 1
        rf = M("rafters", "post", "crown")
        rf.prism_x([(ys + 0.02, roof_z(ys + 0.02)), (yn - 0.02, roof_z(yn - 0.02)),
                    (yn - 0.02, roof_z(yn - 0.02) + h), (ys + 0.02, roof_z(ys + 0.02) + h)][::-1], x - w / 2, x + w / 2)
        rfo = rf.done(bevel=0.01, array=(n, (RAFTER["step"], 0, 0)))
        cut(rfo, chim_cut)
        # 野地板: 垂木の上、屋根の板の下。2 階の中から見える天井
        ln = M("roof_lining", "board", "crown")
        ln.prism_x([(ys, zs - 0.025), (yn, zn - 0.025), (yn, zn), (ys, zs)][::-1], xa + 0.05, xb - 0.05)
        lno = ln.done()
        cut(lno, chim_cut)
        # 妻の破風板（けらばの下端を見せる）
        bg = M("barge", "board", "crown")
        for xx in (xa + 0.02, xb - 0.08):
            bg.prism_x([(ys, zs - 0.10), (yn, zn - 0.10), (yn, zn + 0.02), (ys, zs + 0.02)][::-1], xx, xx + 0.06)
        bg.done(bevel=0.01)
        # 厨房の排気の筒
        vt = M("vents", "metal", "crown")
        for vx in VENTS:
            vy = Y2_0 + 0.9
            z = roof_z(vy) + lift + tv + sv
            vt.cyl((vx, vy, z - 0.6), (vx, vy, z + 0.75), 0.09, seg=16)
            vt.cyl((vx, vy, z + 0.75), (vx, vy, z + 0.83), 0.20, seg=16)
        vt.done(smooth=True)


def build_lean_to():
    L = LEAN
    zr = lambda x: L["z_wall"] + (x - X0) * (L["z_wall"] - L["z_out"]) / (X0 - L["x_out"])   # noqa: E731
    p = M("lean_posts", "post", "crown")
    for y in L["posts"]:
        p.box(L["x_post"] - 0.10, y - 0.10, 0, L["x_post"] + 0.10, y + 0.10, zr(L["x_post"]))
        if PH >= 3:
            p.box(L["x_post"] - 0.18, y - 0.18, 0, L["x_post"] + 0.18, y + 0.18, 0.18)   # 石の束の代わりの台
    if PH >= 3:
        p.box(L["x_post"] - 0.09, L["y0"], zr(L["x_post"]) - 0.24, L["x_post"] + 0.09, L["y1"], zr(L["x_post"]))   # 桁
        p.box(X0 - 0.30, L["y0"], L["z_wall"] - 0.24, X0 - 0.13, L["y1"], L["z_wall"])                           # 壁の受け
    p.done(bevel=0.012 if PH >= 3 else 0)
    t = 0.20
    r = M("lean_roof", "roof", "crown")
    r.prism_y([(L["x_out"], zr(L["x_out"])), (X0 - 0.13, zr(X0 - 0.13)), (X0 - 0.13, zr(X0 - 0.13) + t),
               (L["x_out"], zr(L["x_out"]) + t)], L["y0"], L["y1"])
    r.done(bevel=0.025 if PH >= 3 else 0)
    s = M("lean_snow", "snow", "crown")
    s.prism_y([(L["x_out"] + 0.05, zr(L["x_out"]) + t - 0.02), (X0 - 0.13, zr(X0 - 0.13) + t - 0.02),
               (X0 - 0.13, zr(X0 - 0.13) + t + 0.20), (L["x_out"] + 0.05, zr(L["x_out"]) + t + 0.20)],
              L["y0"] + 0.08, L["y1"] - 0.08)
    s.done(bevel=0.08 if PH >= 3 else 0, seg=4, smooth=PH >= 3)


# ---------------------------------------------------------------- 段階 2: 壁と開口
def holes_for(key, axis, z0, z1, offset):
    out = []
    for c, kind in OPENINGS.get(key, []):
        if kind == "win":
            w, hb, ht = WIN["w"], z0 + WIN["sill"], z0 + WIN["sill"] + WIN["h"]
        else:
            d = DOOR1 if kind == "door1" else DOOR2
            w, hb, ht = d["w"], z0, z0 + d["h"]
        cb, ct = snap(z0, z1, offset, hb, ht)
        out.append((c, w, cb, ct, "win" if kind == "win" else "door"))
    return out


def build_walls():
    Lg = M("logs", "log", "walls")
    F = M("frames", "frame", "walls")
    G = M("glass", "glass", "walls")
    D = M("doors", "door", "walls")
    P = M("posts", "post", "walls")
    ext = R + LOG_OUT
    walls = []   # (key, axis, fixed, sgn, a0, a1, z0, z1, offset, extra holes, top)
    c = CH
    walls.append(("1F_N", "x", Y1, 1, X0 + POST / 2, X1 + ext, FL1, CEIL1, 0.0,
                  [(c["x0"], c["x1"], -1, 99)], None))
    walls.append(("1F_E", "y", X1, 1, Y0 + POST / 2, Y1 + ext, FL1, CEIL1, LOG_H / 2, [], None))
    walls.append(("1F_SW", "x", Y0, -1, X0 + POST / 2, GLASS_S_X0 - POST / 2, FL1, CEIL1, 0.0,
                  [(DOOR_IN["x0"], DOOR_IN["x1"], FL1, FL1 + DOOR_IN["h"])], None))
    walls.append(("2F_S", "x", Y2_0, -1, X0 - ext, X1 + ext, FL2, EAVE_S, 0.0, [], None))
    walls.append(("2F_N", "x", Y1, 1, X0 - ext, X1 + ext, FL2, EAVE_N, 0.0, [(c["ux0"], c["ux1"], -1, 99)], None))
    gable_top = lambda z: Y1 - (z - EAVE_N) / ROOF_PITCH if z > EAVE_N else 99   # noqa: E731
    walls.append(("2F_W", "y", X0, -1, Y2_0 - ext, Y1 + ext, FL2, EAVE_S, LOG_H / 2, [], gable_top))
    walls.append(("2F_E", "y", X1, 1, Y2_0 - ext, Y1 + ext, FL2, EAVE_S, LOG_H / 2, [], gable_top))
    for key, axis, fixed, sgn, a0, a1, z0, z1, off, extra, top in walls:
        ops = holes_for(key, axis, z0, z1, off)
        if key == "1F_SW":
            cb, ct = snap(z0, z1, off, FL1, FL1 + DOOR_IN["h"])
            extra = [(DOOR_IN["x0"], DOOR_IN["x1"], cb, ct)]
            ops = [((DOOR_IN["x0"] + DOOR_IN["x1"]) / 2, DOOR_IN["x1"] - DOOR_IN["x0"], cb, ct, "door")]
        holes = [(cc - w / 2, cc + w / 2, cb, ct) for cc, w, cb, ct, _ in ops] + list(extra)
        last = log_wall(Lg, axis, fixed, a0, a1, z0, z1, off, holes, top)
        for cc, w, cb, ct, kind in ops:
            opening(F, G, D, axis, fixed, sgn, cc, w, cb, ct, kind)
        if top is None and z1 - last > 0.01:   # 桁（最後の段から屋根まで）
            segs = [(a0 if a0 < X0 else a0, a1)]
            for h0, h1, hb, ht in extra:
                if ht > 50:
                    segs = subtract(segs, h0, h1)
            for s0, s1 in segs:
                wbox(Lg, axis, fixed, sgn, s0, s1, -R, R, last - 0.04, z1)
        if top is not None:   # 妻の上端: 屋根の勾配に沿って切った板
            u0, u1 = Y2_0 - R, Y1 + R
            Lg.solid([(fixed - R, u0, roof_z(u0) - LOG_H - 0.04), (fixed + R, u0, roof_z(u0) - LOG_H - 0.04),
                      (fixed + R, u1, roof_z(u1) - LOG_H - 0.04), (fixed - R, u1, roof_z(u1) - LOG_H - 0.04)],
                     [(fixed - R, u0, roof_z(u0)), (fixed + R, u0, roof_z(u0)),
                      (fixed + R, u1, roof_z(u1)), (fixed - R, u1, roof_z(u1))])
    # 1 階のガラスの壁（南の東 8.5 間、西の全面）。西の北の間は貸出への戸
    glass_wall(P, F, G, D, "x", Y0, -1, GLASS_S_POSTS, FL1, CEIL1)
    glass_wall(P, F, G, D, "y", X0, -1, GLASS_W_POSTS, FL1, CEIL1, door_bay=4)
    # 2 階の南の壁を受ける梁と丸柱
    Bm = M("beam", "post", "walls")
    Bm.box(X0, Y2_0 - R, CEIL1 - 0.30, X1, Y2_0 + R + 0.12, CEIL1)
    Bm.done(bevel=0.015)
    Cl = M("columns", "post", "walls")
    for x, y in COLS:
        Cl.cyl((x, y, FL1), (x, y, FL2), COL_D / 2, seg=20)
        Cl.cyl((x, y, FL2), (x, y, roof_z(y) + (RAFTER["h"] if PH >= 3 else 0)), COL_D / 2 * 0.85, seg=20)
    Cl.done(smooth=True)
    # 風除室（縦羽目の小屋）
    V = VEST
    Vb = M("vestibule", "board", "walls")
    y0 = Y0 - V["d"]
    Vb.box(V["x0"], y0, FL1, V["x0"] + 0.12, Y0, V["h"])
    Vb.box(V["x1"] - 0.12, y0, FL1, V["x1"], Y0, V["h"])
    cx = (V["x0"] + V["x1"]) / 2
    dw = DOOR_OUT["w"]
    Vb.box(V["x0"], y0, FL1, cx - dw / 2, y0 + 0.12, V["h"])
    Vb.box(cx + dw / 2, y0, FL1, V["x1"], y0 + 0.12, V["h"])
    Vb.box(cx - dw / 2, y0, FL1 + DOOR_OUT["h"], cx + dw / 2, y0 + 0.12, V["h"])
    Vb.done(bevel=0.01)
    opening(F, G, D, "x", y0 + 0.06, -1, cx, dw, FL1, FL1 + DOOR_OUT["h"], "door")
    vr = M("vest_roof", "roof", "crown")
    o = V["roof_out"]
    vr.box(V["x0"] - o, y0 - o, V["h"], V["x1"] + o, Y0, V["h"] + 0.22)
    vr.done(bevel=0.02)
    vs = M("vest_snow", "snow", "crown")
    vs.box(V["x0"] - o + 0.05, y0 - o + 0.05, V["h"] + 0.21, V["x1"] + o - 0.05, Y0, V["h"] + 0.40)
    vs.done(bevel=0.07, seg=4, smooth=True)
    for m in (Lg,):
        m.done(smooth=True)
    F.done(bevel=0.006)
    G.done()
    D.done(bevel=0.006)
    P.done(bevel=0.02)


# ---------------------------------------------------------------- 段階 3: 手すり・外階段
def rail_run(Rm, p0, p1, h=RAIL_H, posts_every=K, name=None):
    """p0→p1（歩く面の上の線）に沿う手すり。上桟・下桟・柱は Rm に、縦材は配列の物体"""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    up = Vector((0, 0, 1))
    Rm.beam(p0 + up * (h - 0.03), p1 + up * (h - 0.03), 0.14, 0.06)
    Rm.beam(p0 + up * 0.14, p1 + up * 0.14, 0.07, 0.05)
    flat = Vector((d.x, d.y, 0)).length
    n_post = max(1, round(flat / posts_every))
    for i in range(n_post + 1):
        q = p0 + d * (i / n_post)
        Rm.box(q.x - 0.06, q.y - 0.06, q.z, q.x + 0.06, q.y + 0.06, q.z + h)
    n = int(flat / BALUSTER)
    if n < 2:
        return
    step = d / flat * BALUSTER
    q = p0 + step * 0.5
    b = M(name or "balusters", "rail", "crown")
    b.box(q.x - 0.022, q.y - 0.022, q.z + 0.16, q.x + 0.022, q.y + 0.022, q.z + h - 0.06)
    b.done(array=(n, tuple(step)))


def build_rails_and_stair():
    Rm = M("rails", "rail", "crown")
    zt = FL2
    rail_run(Rm, (X0 + K, Y0 + 0.07, zt), (X1 - 0.07, Y0 + 0.07, zt), name="bal_terrace_s")
    rail_run(Rm, (X1 - 0.07, Y0 + 0.07, zt), (X1 - 0.07, Y2_0 - R - 0.02, zt), name="bal_terrace_e")
    rail_run(Rm, (X0 + 0.07, Y0 + 0.07, zt), (X0 + 0.07, Y2_0 - R - 0.02, zt), name="bal_terrace_w")
    # テラスの床板
    tb = M("terrace_boards", "deck", "crown")
    n = int((Y2_0 - R - Y0) / 0.15)
    tb.box(X0, Y0 - 0.02, FL2, X1, Y0 + 0.13, FL2 + 0.03)
    tb.done(bevel=0.008, array=(n, (0, 0.15, 0)))
    # 外階段
    E = ESTAIR
    T = M("stair_treads", "deck", "crown")
    S = M("stair_frame", "post", "crown")
    ri, tr = E["rise"], E["tread"]
    nf = E["risers"] // 2
    for (xa, xb), ys, z0, dirn in ((E["x_lo"], E["y_start"], FL1, -1), (E["x_up"], E["y_land"], E["z_land"], 1)):
        for k in range(1, nf):
            z = z0 + k * ri
            y_lo = ys + dirn * (k - 1) * tr
            y_hi = ys + dirn * k * tr
            T.box(xa + 0.06, y_lo - dirn * 0.03, z - 0.05, xb - 0.06, y_hi, z)
        ye = ys + dirn * (nf - 1) * tr
        ze = z0 + nf * ri
        for x in (xa + 0.03, xb - 0.03):   # 側桁
            S.beam((x, ys - dirn * 0.05, z0 - 0.02), (x, ye + dirn * 0.05, ze - 0.02), 0.06, 0.30)
        rail_run(Rm, (xa + 0.05, ys, z0 + ri), (xa + 0.05, ye, ze), h=1.0, posts_every=3,
                 name="bal_stair_%d_w" % dirn)
        rail_run(Rm, (xb - 0.05, ys, z0 + ri), (xb - 0.05, ye, ze), h=1.0, posts_every=3,
                 name="bal_stair_%d_e" % dirn)
    xa, xb = E["x_lo"][0], E["x_up"][1]
    yl0, yl1 = E["y_land"] - E["landing"], E["y_land"]
    T.box(xa, yl0, E["z_land"] - 0.12, xb, yl1, E["z_land"])                 # 踊り場
    T.box(E["x_up"][0], E["y_start"], FL2 - 0.12, E["x_up"][1], Y0, FL2)     # テラスへの渡り
    for x in (xa + 0.08, xb - 0.08):
        for y in (yl0 + 0.08, yl1 - 0.08):
            S.box(x - 0.08, y - 0.08, 0, x + 0.08, y + 0.08, E["z_land"] - 0.12)
    rail_run(Rm, (xa + 0.05, yl0 + 0.05, E["z_land"]), (xb - 0.05, yl0 + 0.05, E["z_land"]), h=1.0,
             name="bal_landing_s")
    rail_run(Rm, (xa + 0.05, yl1, E["z_land"]), (xa + 0.05, yl0 + 0.05, E["z_land"]), h=1.0, name="bal_landing_w")
    rail_run(Rm, (xb - 0.05, yl1, E["z_land"]), (xb - 0.05, yl0 + 0.05, E["z_land"]), h=1.0, name="bal_landing_e")
    rail_run(Rm, (E["x_up"][1] - 0.05, E["y_start"], FL2), (E["x_up"][1] - 0.05, Y0, FL2), h=RAIL_H,
             name="bal_bridge")
    T.done(bevel=0.012)
    S.done(bevel=0.012)
    Rm.done(bevel=0.012)


# ---------------------------------------------------------------- 段階 4: 設え（中と貸出）
def instance(src, name, loc, rot_z=0.0, group="interior"):
    o = bpy.data.objects.new(name, src.data)
    o.location = loc
    o.rotation_euler = (0, 0, rot_z)
    for md in src.modifiers:
        n = o.modifiers.new(md.name, md.type)
        for attr in ("width", "segments", "limit_method"):
            if hasattr(md, attr):
                setattr(n, attr, getattr(md, attr))
    coll(group).objects.link(o)
    return o


def build_interior():
    # 間仕切り（厨房の両脇）
    W = M("partitions", "board", "interior")
    for x in (KITCHEN["x0"], KITCHEN["x1"]):
        W.box(x - 0.06, KITCHEN["y_front"], FL1, x + 0.06, Y1 - R, CEIL1 - 0.3)
    W.done(bevel=0.01)
    # カウンター（レジ・配膳、貸出）と裏の台、上にメニュー板
    C = M("counters", "board", "interior")
    for c in (COUNTER, RENTAL):
        C.box(c["x0"], c["y0"] + 0.06, FL1, c["x1"], c["y1"], c["h"] + FL1 - 0.05)
        C.box(c["x0"] - 0.04, c["y0"] - 0.06, FL1 + c["h"] - 0.05, c["x1"] + 0.04, c["y1"] + 0.03, FL1 + c["h"])
    C.box(BACK["x0"], BACK["y0"], FL1, BACK["x1"], BACK["y1"], FL1 + BACK["h"])
    C.box(RENTAL["x0"], BACK["y0"], FL1, RENTAL["x1"], BACK["y1"], FL1 + 1.9)      # 貸出の棚
    for z in (0.5, 1.0, 1.5):
        C.box(RENTAL["x0"] - 0.02, BACK["y0"] - 0.04, FL1 + z, RENTAL["x1"] + 0.02, BACK["y0"], FL1 + z + 0.03)
    C.done(bevel=0.012)
    mb = M("menu_board", "paper", "interior")
    mid = (COUNTER["x0"] + COUNTER["x1"]) / 2
    for k in (-1, 0, 1):   # 3 枚並べて吊る
        mb.box(mid + k * 1.0 - 0.45, COUNTER["y1"] - 0.03, FL1 + 2.45, mid + k * 1.0 + 0.45, COUNTER["y1"] + 0.01, FL1 + 3.05)
    mb.done(bevel=0.01)
    # 卓 6 つと椅子（3 脚ずつ向かい合う）
    tw, td, th = TABLE["w"], TABLE["d"], TABLE["h"]
    tm = M("table_src", "board", "interior")
    tm.box(0, 0, th - 0.05, tw, td, th)
    for lx in (0.12, tw - 0.12):
        tm.box(lx - 0.04, 0.12, 0, lx + 0.04, td - 0.12, th - 0.05)
    tm.box(0.12, td / 2 - 0.03, 0.12, tw - 0.12, td / 2 + 0.03, 0.2)
    tsrc = tm.done(bevel=0.012)
    ch = M("chair_src", "board", "interior")
    ch.box(-0.21, -0.21, 0.43, 0.21, 0.21, 0.47)
    for sx in (-0.17, 0.17):
        for sy in (-0.17, 0.17):
            ch.box(sx - 0.02, sy - 0.02, 0, sx + 0.02, sy + 0.02, 0.43)
    ch.box(-0.20, 0.17, 0.47, 0.20, 0.21, 0.88)
    csrc = ch.done(bevel=0.008)
    cu = M("cushion_src", "cushion", "interior")
    cu.box(-0.19, -0.19, 0.47, 0.19, 0.17, 0.52)
    usrc = cu.done(bevel=0.02, seg=3)
    k = 0
    for x, y in TABLES:
        instance(tsrc, "table_%d" % k, (x, y, FL1))
        for j in range(3):
            cx = x + tw * (j + 0.5) / 3
            for cy, rz in ((y - 0.32, math.pi), (y + td + 0.32, 0.0)):
                instance(csrc, "chair_%d_%d_%d" % (k, j, rz > 0), (cx, cy, FL1), rz)
                instance(usrc, "cushion_%d_%d_%d" % (k, j, rz > 0), (cx, cy, FL1), rz)
        k += 1
    tsrc.location.z = csrc.location.z = usrc.location.z = -50   # 元の形は地面の下へ
    # 炉を囲む長椅子（コの字）
    B = M("hearth_bench", "board", "interior")
    Cu = M("hearth_cushion", "cushion", "interior")
    for x0, y0, x1, y1 in HEARTH_BENCH:
        B.box(x0, y0, FL1, x1, y1, FL1 + 0.40)
        Cu.box(x0 + 0.02, y0 + 0.02, FL1 + 0.40, x1 - 0.02, y1 - 0.02, FL1 + 0.47)
    B.done(bevel=0.015)
    Cu.done(bevel=0.025, seg=3)
    # 内のスキー置場（西のガラス際）
    S = SKI_RACK
    sk = M("ski_rack", "board", "interior")
    sk.box(S["x0"], S["y0"], FL1, S["x1"], S["y1"], FL1 + 0.12)
    sk.box(S["x0"], S["y0"], FL1 + 1.10, S["x1"], S["y1"], FL1 + 1.16)
    sk.done(bevel=0.01)
    step = (S["y1"] - S["y0"]) / S["n"]
    for i, role in enumerate(("felt_red", "felt_blue", "felt_green", "felt_yellow")):
        sm = M("skis_in_%s" % role, role, "interior")
        y = S["y0"] + step * (i + 0.5)
        sm.box((S["x0"] + S["x1"]) / 2 - 0.05, y - 0.03, FL1 + 0.12, (S["x0"] + S["x1"]) / 2 + 0.05, y + 0.03,
               FL1 + 1.75)
        sm.done(bevel=0.02, seg=3, array=(math.ceil((S["n"] - i) / 4), (0, step * 4, 0)))
    # 内階段（北へ上る）
    I = INSTAIR
    st = M("instair", "board", "interior")
    n = I["risers"]
    ri = (FL2 - FL1) / n
    tr = (I["y_top"] - I["y_bottom"]) / (n - 1)
    for k in range(1, n):
        z = FL1 + k * ri
        st.box(I["x0"], I["y_bottom"] + (k - 1) * tr - 0.03, z - 0.05, I["x1"], I["y_bottom"] + k * tr, z)
    st.beam((I["x0"] + 0.03, I["y_bottom"] - 0.05, FL1 + 0.05), (I["x0"] + 0.03, I["y_top"], FL2 - 0.05), 0.06, 0.3)
    st.done(bevel=0.01)
    ir = M("instair_rail", "rail", "interior")
    rail_run(ir, (I["x0"] + 0.04, I["y_bottom"], FL1 + ri), (I["x0"] + 0.04, I["y_top"] - 0.3, FL2), h=0.9,
             posts_every=5, name="bal_instair")
    rail_run(ir, (I["x0"] - 0.05, I["y_bottom"] + 0.8, FL2), (I["x0"] - 0.05, I["y_top"], FL2), h=RAIL_H,
             name="bal_stairwell_w")
    rail_run(ir, (I["x0"] - 0.05, I["y_bottom"] + 0.8, FL2), (I["x1"], I["y_bottom"] + 0.8, FL2), h=RAIL_H,
             name="bal_stairwell_s")
    ir.done(bevel=0.01)
    # 1 階の吊り灯り（卓の上）と 2 階の紙の灯り
    lp = M("lamps", "paper", "interior")
    for x, y in TABLES:
        for j in (0.25, 0.75):
            cx, cy = x + tw * j, y + td / 2
            lp.cyl((cx, cy, CEIL1 - 0.9), (cx, cy, CEIL1 - 0.55), 0.22, seg=20)
    for x in KOTATSU:
        cx = x + KOTATSU_W / 2
        cy = sum(KOTATSU_Y) / 2
        lp.cyl((cx, cy, FL2 + TATAMI["h"] + 1.75), (cx, cy, FL2 + TATAMI["h"] + 2.2), 0.30, seg=24)
    lp.done(bevel=0.03, seg=3, smooth=True)
    cords = M("cords", "metal", "interior")
    for x, y in TABLES:
        for j in (0.25, 0.75):
            cords.cyl((x + tw * j, y + td / 2, CEIL1 - 0.55), (x + tw * j, y + td / 2, CEIL1), 0.008, seg=6)
    cords.done()

    # ---- 2 階: 小上がりの畳と掘りごたつ ----
    T_ = TATAMI
    zt = FL2 + T_["h"]
    pl = M("tatami_platform", "board", "interior")
    pl.box(T_["x0"], T_["y0"], FL2, T_["x1"], T_["y1"], zt - 0.03)
    plo = pl.done(bevel=0.01)
    ky0, ky1 = KOTATSU_Y
    pits = []
    for i, x in enumerate(KOTATSU):
        pits.append((x - 0.25, ky0 - 0.45, x + KOTATSU_W + 0.25, ky1 + 0.45))
        cut(plo, cutter("cut_pit_%d" % i, x - 0.25, ky0 - 0.45, zt - PIT_DEPTH, x + KOTATSU_W + 0.25, ky1 + 0.45, zt + 0.1))
    # 畳: 半間 x 1 間を目地で並べる。掘りごたつの穴にかかる畳は外す
    tt = M("tatami", "tatami", "interior")
    nx = int(round((T_["x1"] - T_["x0"]) / (K / 2)))
    ny = int(round((T_["y1"] - T_["y0"]) / K))
    for i in range(nx):
        for j in range(ny):
            x0 = T_["x0"] + i * K / 2
            y0 = T_["y0"] + j * K + (K / 2 if i % 2 else 0)
            for ya, yb in ((y0, min(y0 + K, T_["y1"])), (T_["y0"], y0) if (i % 2 and j == 0) else (0, 0)):
                if yb - ya < 0.05:
                    continue
                if any(x0 < p[2] and x0 + K / 2 > p[0] and ya < p[3] and yb > p[1] for p in pits):
                    continue
                tt.box(x0 + 0.006, ya + 0.006, zt - 0.03, x0 + K / 2 - 0.006, yb - 0.006, zt)
    tt.done(bevel=0.006)
    pe = M("pit_edge", "board", "interior")
    for x0, y0, x1, y1 in pits:
        for a in ((x0, y0, x0 + 0.06, y1), (x1 - 0.06, y0, x1, y1), (x0, y0, x1, y0 + 0.06), (x0, y1 - 0.06, x1, y1)):
            pe.box(a[0], a[1], zt - 0.03, a[2], a[3], zt + 0.005)
    pe.done(bevel=0.006)
    kt = M("kotatsu", "board", "interior")
    qu = M("kotatsu_quilt", "quilt", "interior")
    zb = M("zabuton", "cushion", "interior")
    for x in KOTATSU:
        kt.box(x, ky0, zt + 0.36, x + KOTATSU_W, ky1, zt + 0.40)
        qu.box(x - 0.12, ky0 - 0.12, zt + 0.02, x + KOTATSU_W + 0.12, ky1 + 0.12, zt + 0.36)
        for j in range(3):
            cx = x + KOTATSU_W * (j + 0.5) / 3
            zb.box(cx - 0.27, ky0 - 0.98, zt, cx + 0.27, ky0 - 0.42, zt + 0.08)
            zb.box(cx - 0.27, ky1 + 0.42, zt, cx + 0.27, ky1 + 0.98, zt + 0.08)
        cy = (ky0 + ky1) / 2
        zb.box(x - 0.98, cy - 0.27, zt, x - 0.42, cy + 0.27, zt + 0.08)
        zb.box(x + KOTATSU_W + 0.42, cy - 0.27, zt, x + KOTATSU_W + 0.98, cy + 0.27, zt + 0.08)
    kt.done(bevel=0.012)
    qu.done(bevel=0.06, seg=4, smooth=True)
    zb.done(bevel=0.03, seg=3, smooth=True)
    b2 = M("bench2", "board", "interior")
    x0, y0, x1, y1 = BENCH2
    b2.box(x0, y0, FL2, x1, y1, FL2 + 0.42)
    x0, y0, x1, y1 = TABLE2
    b2.box(x0, y0, FL2 + 0.68, x1, y1, FL2 + 0.72)
    for lx in (x0 + 0.1, x1 - 0.1):
        b2.box(lx - 0.04, y0 + 0.1, FL2, lx + 0.04, y1 - 0.1, FL2 + 0.68)
    b2.box(INSTAIR["x0"] - 1.6, gy(3.25), FL2, INSTAIR["x0"] - 0.3, gy(2.95), FL2 + 0.9)   # 下足箱
    b2.done(bevel=0.012)

    # ---- 下屋: 貸出のスキー立てと腰掛け ----
    L = LEAN
    rk = M("rental_rack", "board", "setsue")
    xr = L["x_post"] + 0.35
    rk.box(xr - 0.05, L["y0"] + 0.4, 0, xr + 0.05, L["y1"] - 0.4, 0.15)
    rk.box(xr - 0.05, L["y0"] + 0.4, 1.20, xr + 0.05, L["y1"] - 0.4, 1.26)
    rk.done(bevel=0.01)
    span = (L["y1"] - 0.4) - (L["y0"] + 0.4)
    n = int(span / 0.22)
    for i, role in enumerate(("felt_red", "felt_blue", "felt_green", "felt_yellow")):
        sm = M("skis_out_%s" % role, role, "setsue")
        y = L["y0"] + 0.4 + 0.22 * (i + 0.5)
        sm.box(xr - 0.05, y - 0.04, 0.15, xr + 0.05, y + 0.04, 1.80)
        sm.done(bevel=0.025, seg=3, array=(math.ceil((n - i) / 4), (0, 0.88, 0)))
    bn = M("rental_benches", "board", "setsue")
    for j in range(3):
        y0 = gy(6.7) + j * 0.4
        bn.box(gx(-1.4), y0, 0, gx(-0.6), y0 + 0.3, 0.42)
    bn.done(bevel=0.012)
    # 機械の置き場（代表があとで置く）: 空の目印
    for name, loc in SLOTS.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "CUBE"
        e.empty_display_size = 0.4
        e.location = loc
        coll("markers").objects.link(e)


# ---------------------------------------------------------------- 地面・光・カメラ
def build_ground():
    g = M("ground", "snow", "ground")
    g.box(-90, -90, -0.3, 90, 90, 0)
    g.done()
    me = bpy.data.meshes.new("hill")
    verts, faces, N = [], [], 48
    for j in range(N + 1):
        for i in range(N + 1):
            x = -80 + i * 160 / N
            y = HILL_Y - j * 70 / N
            d = HILL_Y - y
            verts.append((x, y, (d ** 1.3) * 0.18))
    for j in range(N):
        for i in range(N):
            a = j * (N + 1) + i
            faces.append([a, a + 1, a + N + 2, a + N + 1])
    me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new("hill", me)
    coll("ground").objects.link(o)
    me.materials.append(mat("snow"))


def build_light():
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = 4.5
    sun.data.angle = math.radians(2)
    sun.rotation_euler = (math.radians(62), 0, math.radians(-45))   # 南西から、高度 28 度
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.70, 0.85, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    if PH >= 4:   # 中を見るための仮の灯り（段階 3 で光を組み直す）
        for x, y, z, e in [(gx(3), gy(3.5), 3.4, 250), (gx(7), gy(4.6), 3.4, 250), (gx(10), gy(3.0), 3.4, 250),
                           (gx(3), gy(1.0), 3.0, 150), (gx(5), gy(2.6), FL2 + 2.6, 220), (gx(9), gy(2.6), FL2 + 2.6, 220)]:
            L = bpy.data.objects.new("lamp", bpy.data.lights.new("lamp", "POINT"))
            sc.collection.objects.link(L)
            L.location = (x, y, z)
            L.data.energy = e
            L.data.shadow_soft_size = 0.5
            L.data.color = (1.0, 0.86, 0.68)


CAMS = {
    "hill": ((-17, -38, 12.5), (0.5, -2, 4.4), 35),
    "west": ((-44, -7, 6.5), (0, 0, 4.4), 36),
    "east": ((40, -22, 9), (0, -1, 4.2), 36),
    "north": ((14, 40, 9), (0, 0, 4.0), 36),
    "aerial": ((-34, -42, 34), (0, -1, 2), 32),
    "close": ((-9.5, -21, 3.2), (-3.5, -6.5, 4.6), 30),
    "in1": ((gx(2.5), Y0 + 1.0, FL1 + 1.55), (gx(9.0), Y1 - 1.0, FL1 + 1.2), 20),
    "in2": ((gx(0.5), gy(3.6), FL2 + 1.55), (gx(10.5), gy(2.4), FL2 + 0.55), 22),
    "terrace": ((gx(7.0), Y2_0 - 0.7, FL2 + 1.55), (gx(3.0), Y0 - 18, 3.5), 24),
}


def render(view, path):
    loc, tgt, lens = CAMS[view]
    cam = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.location = loc
    d = Vector(tgt) - Vector(loc)
    cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, math.atan2(d.y, d.x) - math.pi / 2)
    cam.data.lens = lens
    cam.data.clip_start = 0.05
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("wrote", path)


# ---------------------------------------------------------------- 組む
if PH == 1:
    build_massing()
else:
    build_walls()
build_base()
build_chimney()
build_roof(roof_cutters())
build_lean_to()
if PH >= 3:
    build_rails_and_stair()
if PH >= 4:
    build_interior()
build_ground()
build_light()
for c in ("cutters",):
    if bpy.data.collections.get(c):
        bpy.data.collections[c].hide_render = True

for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
rx, ry = (int(v) for v in A.size.split("x"))
sc.render.resolution_x, sc.render.resolution_y = rx, ry
sc.view_settings.view_transform = "AgX"
if A.blend:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
for v in A.views.split(","):
    render(v, os.path.abspath("%s-%s.png" % (A.prefix, v)))
