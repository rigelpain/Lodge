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
ap.add_argument("--look", default="clay", choices=("clay", "day", "dusk", "flat"))
ap.add_argument("--export", default="", help="この場所に lodge.glb と lodge_collision.glb を書き出す（描画しない）")
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
    "floor": (0.55, 0.45, 0.36), "ceiling": (0.70, 0.64, 0.54), "fire": (0.9, 0.5, 0.2), "tree": (0.30, 0.42, 0.34), "trunk": (0.36, 0.25, 0.16), "far": (0.78, 0.83, 0.90),
}
MAT = {}


def mat(role):
    if role not in MAT and A.look == "flat":   # 書き出し用: 役割の名前と色だけ。Godot で look.gd の素材に差し替える
        import materials
        m = bpy.data.materials.new(role)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = materials.lin(materials.HEX[role])
        b.inputs["Roughness"].default_value = 0.06 if role == "glass" else 0.9
        if role == "glass":
            b.inputs["Alpha"].default_value = 0.32
        if role in ("paper", "fire"):
            b.inputs["Emission Color"].default_value = materials.lin(materials.HEX[role])
            b.inputs["Emission Strength"].default_value = 2.0
        MAT[role] = m
    if role not in MAT and A.look != "clay":
        import materials
        MAT[role] = materials.make(role, A.look)
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

    def done(self, bevel=0.0, seg=2, array=None, smooth=False, cap_uv=False):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        if cap_uv:   # 丸太の木口に渦を描くための UV（木口は u = 2..3、胴は 0.1）
            self.bm.normal_update()
            uvl = self.bm.loops.layers.uv.new("UVMap")
            for f in self.bm.faces:
                if len(f.verts) >= 8:
                    c = f.calc_center_median()
                    e1 = Vector((0, 1, 0)) if abs(f.normal.x) > 0.5 else Vector((1, 0, 0))
                    for lp in f.loops:
                        d = lp.vert.co - c
                        lp[uvl].uv = (2.5 + d.dot(e1) / (4 * R), 0.5 + d.z / (4 * R))
                else:
                    for lp in f.loops:
                        lp[uvl].uv = (0.1, 0.1)
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
    elif kind == "auto":   # 自動ドア: 金属の細い框のガラス 2 枚。ゲームで左右へ引き分ける（autodoor_l / _r）
        wbox(F, axis, fixed, sgn, u0 - 0.05, u1 + 0.05, -t, t + 0.06, cb, cb + 0.03)   # 敷居
        lw = (w - 2 * L) / 2
        for k, side in enumerate(("l", "r")):
            lm = M("autodoor_" + side, "metal", "walls")
            lg = M("autodoor_glass_" + side, "glass", "walls")
            a, b = u0 + L + k * lw + 0.004, u0 + L + (k + 1) * lw - 0.004
            S = 0.05
            for q0, q1, r0, r1 in ((a, a + S, cb + 0.03, ct - L), (b - S, b, cb + 0.03, ct - L),
                                   (a, b, cb + 0.03, cb + 0.13), (a, b, ct - L - S, ct - L)):
                wbox(lm, axis, fixed, sgn, q0, q1, -0.03, 0.03, r0, r1)
            wbox(lm, axis, fixed, sgn, (a + b) / 2 - 0.15, (a + b) / 2 + 0.15, -0.035, 0.035, cb + 0.95, cb + 1.0)   # 押し板
            wbox(lg, axis, fixed, sgn, a + S, b - S, -0.006, 0.006, cb + 0.13, ct - L - S)
            lm.done(bevel=0.004)
            lg.done()
        wbox(F, axis, fixed, sgn, u0, u1, t + 0.01, t + 0.04, ct - 0.02, ct + 0.22)   # 外の幕板
        sn = M("autodoor_sensor", "metal", "walls")
        wbox(sn, axis, fixed, sgn, (u0 + u1) / 2 - 0.25, (u0 + u1) / 2 + 0.25, t + 0.04, t + 0.12, ct + 0.02, ct + 0.12)
        sn.done(bevel=0.01)
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
    fl = M("floor2", "ceiling", "walls")
    fl.box(X0 - 0.09, Y0 - 0.09, CEIL1, X1 + 0.09, Y1 + 0.09, FL2)
    f = fl.done(bevel=0.015 if PH >= 2 else 0)
    if PH >= 2:
        I = INSTAIR
        cut(f, cutter("cut_stairwell", I["x0"] - 0.05, I["hole_y0"], CEIL1 - 0.1, I["x1"] + 0.2,
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
        fw_, fh_ = c["fire_w"], c["fire_h"]
        cut(ch, cutter("cut_firebox", cx - fw_ / 2, c["y0"] - 0.1, FL1 + 0.18, cx + fw_ / 2, c["y0"] + 0.8, FL1 + fh_))
        h = M("hearth", "stone", "walls")
        h.box(c["x0"] - 0.25, c["y0"] - 0.65, FL1, c["x1"] + 0.25, c["y0"], FL1 + 0.12)
        h.done(bevel=0.02)
        mt = M("mantel", "board", "walls")
        mt.box(c["x0"] - 0.10, c["y0"] - 0.26, FL1 + fh_ + 0.15, c["x1"] + 0.10, c["y0"] + 0.02, FL1 + fh_ + 0.27)
        mt.done(bevel=0.012)
        fr = M("fire", "fire", "walls")   # 炉の火（光る板と、くべた薪）
        fr.box(cx - fw_ / 2 + 0.12, c["y0"] + 0.65, FL1 + 0.20, cx + fw_ / 2 - 0.12, c["y0"] + 0.70, FL1 + fh_ - 0.25)
        fr.done()
        fw = M("firewood", "log", "walls")
        for k, dz in ((-0.2, 0.0), (0.2, 0.0), (0.0, 0.1)):
            fw.cyl((cx - fw_ / 2 + 0.2, c["y0"] + 0.35 + k * 0.4, FL1 + 0.28 + dz), (cx + fw_ / 2 - 0.2, c["y0"] + 0.35 - k * 0.4, FL1 + 0.28 + dz), 0.10)
        fw.done(smooth=True, cap_uv=True)


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
            ops = [((DOOR_IN["x0"] + DOOR_IN["x1"]) / 2, DOOR_IN["x1"] - DOOR_IN["x0"], cb, ct, "auto")]
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
    glass_wall(P, F, G, D, "y", X0, -1, GLASS_W_POSTS, FL1, CEIL1, door_bay=GLASS_W_DOOR_BAY)
    # 2 階の南の壁を受ける梁と丸柱
    Bm = M("beam", "post", "walls")
    Bm.box(X0, Y2_0 - R, CEIL1 - 0.30, X1, Y2_0 + R + 0.12, CEIL1)
    Bm.done(bevel=0.015)
    Cl = M("columns", "post", "walls")
    for x, y in COLS:
        Cl.cyl((x, y, FL1), (x, y, FL2), COL_D / 2, seg=20)
        Cl.cyl((x, y, FL2), (x, y, roof_z(y) + (RAFTER["h"] if PH >= 3 else 0)), COL_D / 2 * 0.85, seg=20)
    Cl.done(smooth=True)
    build_vestibule()
    Lg.done(smooth=True, cap_uv=True)
    F.done(bevel=0.006)
    G.done()
    D.done(bevel=0.006)
    P.done(bevel=0.02)


# ---------------------------------------------------------------- 段階 3: 手すり・外階段
def arch_top(x):
    """アーチ戸の開口の上端の高さ（x は世界座標）"""
    r, cx = ARCH["r"], VEST["cx"]
    d = min(abs(x - cx), r)
    return ARCH["spring"] + math.sqrt(max(r * r - d * d, 0.0))


def arch_ring(m, cx, zs, r0, r1, y0, y1, n=18):
    """半円の帯（アーチの額縁）を y0..y1 の厚みで"""
    for i in range(n):
        a0, a1 = math.pi * i / n, math.pi * (i + 1) / n
        ring = [(cx + rr * math.cos(a), zs + rr * math.sin(a)) for a, rr in ((a0, r0), (a1, r0), (a1, r1), (a0, r1))]
        m.solid([(x, y0, z) for x, z in ring], [(x, y1, z) for x, z in ring])


def build_vestibule():
    """風除室: 1 階の屋根まである木のアーチの両開き戸（外へ開け放す）、両脇は金網、中は自販機とマット"""
    V, A = VEST, ARCH
    cx, r, zs = V["cx"], A["r"], A["spring"]
    y0, yb = Y0 - V["d"], Y0 - V["d"] + V["t"]          # 前の壁の外面と内面
    # 床（デッキより先へ出る分も）と、アーチの前の 3 段
    fl = M("vest_floor", "deck", "walls")
    fl.box(V["x0"], y0, 0, V["x1"], Y0, FL1)
    for k in range(3):
        fl.box(cx - r - 0.6, y0 - 0.35 * (3 - k), 0, cx + r + 0.6, y0, FL1 * (k + 1) / 3)
    fl.done(bevel=0.012)
    # 前の壁（縦羽目の板）。アーチの左右と、アーチの上の三角を細い帯で
    fw = M("vest_front", "board", "walls")
    fw.box(V["x0"], y0, FL1, cx - r, yb, V["h"])
    fw.box(cx + r, y0, FL1, V["x1"], yb, V["h"])
    n = 24
    for i in range(n):
        xa, xb = cx - r + 2 * r * i / n, cx - r + 2 * r * (i + 1) / n
        fw.prism_y([(xa, arch_top(xa)), (xb, arch_top(xb)), (xb, V["h"]), (xa, V["h"])], y0, yb)
    bmesh.ops.recalc_face_normals(fw.bm, faces=fw.bm.faces)
    fw.done(bevel=0.006)
    # アーチの額縁（濃い木）と、縦の枠
    fr = M("vest_arch_frame", "post", "walls")
    arch_ring(fr, cx, zs, r, r + 0.22, y0 - 0.06, yb + 0.02)
    fr.box(cx - r - 0.22, y0 - 0.06, FL1, cx - r, yb + 0.02, zs)
    fr.box(cx + r, y0 - 0.06, FL1, cx + r + 0.22, yb + 0.02, zs)
    fr.box(cx - r - 0.05, y0 - 0.02, FL1, cx + r + 0.05, yb, FL1 + 0.04)   # 敷居
    bmesh.ops.recalc_face_normals(fr.bm, faces=fr.bm.faces)
    fr.done(bevel=0.01)
    # アーチ戸 2 枚: 縦の板を並べ、外へ 180° 開いて前の壁に沿わせる（蝶番は開口の両端）
    lf = M("arch_doors", "door", "walls")
    st = M("arch_door_straps", "metal", "walls")
    planks = 8
    yo0, yo1 = y0 - 0.14, y0 - 0.02            # 開いた戸の厚み（前の壁の外）
    for sgn in (-1, 1):                         # -1 西の戸、+1 東の戸
        hinge = cx + sgn * r
        top = lambda d: zs + math.sqrt(max(r * r - (r - d) ** 2, 0.0))   # 蝶番から d 離れた所の戸の上端  # noqa: E731
        for i in range(planks):
            d0, d1 = r * i / planks + 0.006, r * (i + 1) / planks - 0.006
            xa, xb = sorted((hinge + sgn * d0, hinge + sgn * d1))
            ta, tb = (top(d0), top(d1)) if sgn > 0 else (top(d1), top(d0))
            lf.prism_y([(xa, FL1 + 0.04), (xb, FL1 + 0.04), (xb, tb), (xa, ta)], yo0, yo1)
        for zb in (FL1 + 0.55, FL1 + 1.75, zs - 0.15):   # 横の桟と、黒い鉄の帯
            x_end = hinge + sgn * (r - 0.12)
            xa, xb = sorted((hinge + sgn * 0.05, x_end))
            lf.box(xa, yo0 - 0.06, zb - 0.09, xb, yo0, zb + 0.09)
            xa, xb = sorted((hinge + sgn * 0.02, hinge + sgn * r * 0.75))
            st.box(xa, yo0 - 0.085, zb - 0.045, xb, yo0 - 0.06, zb + 0.045)
            st.cyl((hinge + sgn * r * 0.75, yo0 - 0.085, zb), (hinge + sgn * r * 0.75, yo0 - 0.06, zb), 0.07, seg=12)
        hx = hinge + sgn * (r - 0.25)
        st.cyl((hx, yo0 - 0.04, FL1 + 1.15), (hx, yo0 - 0.0, FL1 + 1.15), 0.05, seg=10)   # 取っ手の座
        st.box(hx - 0.012, yo0 - 0.10, FL1 + 0.95, hx + 0.012, yo0 - 0.04, FL1 + 1.15)  # 輪の取っ手
    bmesh.ops.recalc_face_normals(lf.bm, faces=lf.bm.faces)
    lf.done(bevel=0.008)
    st.done(bevel=0.004)
    # 両脇の金網: 柱と上下の枠に、細い鉄の格子
    pf = M("vest_mesh_frame", "post", "walls")
    wire = M("vest_mesh", "metal", "walls")
    for x in (V["x0"], V["x1"] - 0.16):
        pf.box(x, yb, FL1, x + 0.16, yb + 0.16, V["h"])                  # 前の角の柱
        pf.box(x, Y0 - 0.16, FL1, x + 0.16, Y0, V["h"])                  # 1 階の壁際の柱
        pf.box(x, (yb + Y0) / 2 - 0.07, FL1, x + 0.16, (yb + Y0) / 2 + 0.07, V["h"])   # 中の柱
        pf.box(x, yb, FL1, x + 0.16, Y0, FL1 + 0.12)                    # 下の枠（雪は下から抜ける）
        pf.box(x, yb, V["h"] - 0.16, x + 0.16, Y0, V["h"])               # 上の枠
        pf.box(x, yb, FL1 + 1.05, x + 0.16, Y0, FL1 + 1.15)              # 腰の桟
        xm = x + 0.08
        step = 0.15
        ny = int((Y0 - yb) / step)
        for j in range(1, ny):
            y = yb + j * step
            wire.box(xm - 0.008, y - 0.008, FL1 + 0.12, xm + 0.008, y + 0.008, V["h"] - 0.16)
        nz = int((V["h"] - 0.16 - FL1 - 0.12) / step)
        for j in range(1, nz):
            z = FL1 + 0.12 + j * step
            wire.box(xm - 0.008, yb, z - 0.008, xm + 0.008, Y0, z + 0.008)
    pf.done(bevel=0.01)
    wire.done()
    ce = M("vest_ceiling", "ceiling", "walls")   # 板張りの天井
    ce.box(V["x0"], yb, V["h"] - 0.04, V["x1"], Y0, V["h"])
    ce.done()
    # 屋根（1 階の屋根の高さ、テラスの床の下）と雪
    vr = M("vest_roof", "roof", "crown")
    o = V["roof_out"]
    zr = V["h"]
    vr.box(V["x0"] - o, y0 - o, zr, V["x1"] + o, Y0, zr + 0.18)
    vr.done(bevel=0.02)
    vs = M("vest_snow", "snow", "crown")
    vs.box(V["x0"] - o + 0.05, y0 - o + 0.05, zr + 0.17, V["x1"] + o - 0.05, Y0 - 0.05, zr + 0.36)
    vs.done(bevel=0.07, seg=4, smooth=True)
    # 中: 靴の雪を落とすマット（溝の刻まれたゴム）、自販機 2 台、吊り灯り
    mt = M("vest_mat", "dark", "interior")
    mx0, mx1 = cx - 1.6, cx + 1.6
    mt.box(mx0, yb + 0.25, FL1, mx1, Y0 - 0.15, FL1 + 0.015)
    mt.done(bevel=0.004)
    rb = M("vest_mat_ribs", "metal", "interior")
    rb.box(mx0 + 0.05, yb + 0.30, FL1 + 0.015, mx0 + 0.09, Y0 - 0.20, FL1 + 0.035)
    rb.done(array=(int((mx1 - mx0 - 0.1) / 0.08), (0.08, 0, 0)))
    VM = VENDING
    for k, (body, face) in enumerate((("felt_red", "paper"), ("felt_blue", "paper"))):
        x0 = V["x0"] + 0.30 + k * (VM["w"] + VM["gap"])
        x1 = x0 + VM["w"]
        ya = Y0 - 0.05 - VM["d"]
        vb = M("vending_%d" % k, body, "interior")
        vb.box(x0, ya, FL1, x1, Y0 - 0.05, FL1 + VM["h"])
        vb.done(bevel=0.02)
        vf = M("vending_face_%d" % k, face, "interior")   # 飲み物の並ぶ明るい窓
        vf.box(x0 + 0.08, ya - 0.01, FL1 + 0.95, x1 - 0.08, ya + 0.02, FL1 + VM["h"] - 0.12)
        vf.done(bevel=0.005)
        vd = M("vending_slot_%d" % k, "dark", "interior")  # 取り出し口とお金の口
        vd.box(x0 + 0.12, ya - 0.01, FL1 + 0.15, x1 - 0.12, ya + 0.02, FL1 + 0.40)
        vd.box(x1 - 0.22, ya - 0.01, FL1 + 0.65, x1 - 0.12, ya + 0.02, FL1 + 0.85)
        vd.done(bevel=0.004)
    lp = M("vest_lamp", "paper", "interior")
    lp.cyl((cx, (yb + Y0) / 2, V["h"] - 0.95), (cx, (yb + Y0) / 2, V["h"] - 0.45), 0.32, seg=24)
    lp.done(smooth=True)
    cd = M("vest_lamp_cord", "dark", "interior")
    cd.cyl((cx, (yb + Y0) / 2, V["h"] - 0.45), (cx, (yb + Y0) / 2, V["h"]), 0.008, seg=6)
    cd.done()



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
    # 1 階の床板（土間でなく木の床。外のデッキと同じ高さ）
    fb = M("floor1", "floor", "interior")
    fb.box(X0 + R, Y0 + 0.05, FL1, X1 - R, Y1 - R, FL1 + 0.02)
    fb.done()
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
    mb = M("menu_board", "felt_green", "interior")   # 色あせたフェルトの案内板
    mid = (COUNTER["x0"] + COUNTER["x1"]) / 2
    for k in (-1, 0, 1):   # 3 枚並べて吊る
        mb.box(mid + k * 1.6 - 0.65, COUNTER["y1"] - 0.03, FL1 + 2.6, mid + k * 1.6 + 0.65, COUNTER["y1"] + 0.01, FL1 + 3.4)
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
    for src in (tsrc, csrc, usrc):   # 元の形は書き出さない置き場へ
        coll("interior").objects.unlink(src)
        coll("sources").objects.link(src)
        src.hide_render = True
    # 窓向きのカウンター（南のガラス面いっぱい）と、一人用の高い椅子
    wb = WINDOW_BAR
    bar = M("window_bar", "board", "interior")
    yb0, yb1 = wb["y0"], wb["y0"] + wb["d"]
    bar.box(wb["x0"], yb0 - 0.02, FL1 + wb["h"] - wb["t"], wb["x1"], yb1 + 0.03, FL1 + wb["h"])   # 天板
    bar.box(wb["x0"], yb0, FL1, wb["x1"], yb0 + 0.06, FL1 + wb["h"] - wb["t"])                  # 腰板（ガラス側）
    n_leg = int((wb["x1"] - wb["x0"]) / 2.4) + 1
    for i in range(n_leg + 1):   # 天板を受ける板脚
        x = wb["x0"] + (wb["x1"] - wb["x0"]) * i / n_leg
        bar.box(x - 0.03, yb0, FL1, x + 0.03, yb1 - 0.05, FL1 + wb["h"] - wb["t"])
    bar.box(wb["x0"], yb1 - 0.12, FL1 + 0.25, wb["x1"], yb1 - 0.06, FL1 + 0.29)                  # 足掛けの横木
    bar.done(bevel=0.012)
    st = STOOL
    sm = M("stool_src", "post", "interior")
    sm.cyl((0, 0, 0), (0, 0, 0.02), 0.20, seg=20)                       # 台
    sm.cyl((0, 0, 0.02), (0, 0, st["seat"] - 0.06), 0.035, seg=10)       # 柱
    sm.cyl((0, 0, 0.30), (0, 0, 0.33), 0.17, seg=20)                     # 足掛けの輪
    sm.cyl((0, 0, st["seat"] - 0.06), (0, 0, st["seat"] - 0.02), st["r"], seg=24)
    ssrc = sm.done(bevel=0.008, smooth=True)
    sc_ = M("stool_cushion_src", "cushion", "interior")
    sc_.cyl((0, 0, st["seat"] - 0.02), (0, 0, st["seat"] + 0.04), st["r"] - 0.01, seg=24)
    scsrc = sc_.done(bevel=0.02, seg=3, smooth=True)
    n_st = int((wb["x1"] - wb["x0"] - 0.4) / st["step"])
    off = (wb["x1"] - wb["x0"] - (n_st - 1) * st["step"]) / 2
    for i in range(n_st):
        x = wb["x0"] + off + i * st["step"]
        instance(ssrc, "stool_%d" % i, (x, st["y"], FL1))
        instance(scsrc, "stool_cushion_%d" % i, (x, st["y"], FL1))
    for src in (ssrc, scsrc):
        coll("interior").objects.unlink(src)
        coll("sources").objects.link(src)
        src.hide_render = True
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
    # 内階段: 東の壁際を北へ上り、北の壁際の踊り場で折り返して、南へ上って 2 階に出る
    I = INSTAIR
    st = M("instair", "board", "interior")
    n, n1, tr = I["risers"], I["n1"], I["tread"]
    ri = (FL2 - FL1) / n
    for k in range(1, n1):                       # 1 本目（東）: 北へ
        z = FL1 + k * ri
        y = I["y_bottom"] + (k - 1) * tr
        st.box(I["xm"], y - 0.03, z - 0.05, I["x1"], y + tr, z)
    st.box(I["x0"], I["y_land"], I["z_land"] - 0.15, I["x1"], I["y_top"], I["z_land"])   # 踊り場
    for k in range(1, n - n1):                   # 2 本目（西）: 南へ
        z = I["z_land"] + k * ri
        y = I["y_land"] - k * tr
        st.box(I["x0"], y, z - 0.05, I["xm"], y + tr + 0.03, z)
    st.beam((I["xm"] + 0.03, I["y_bottom"] - 0.05, FL1 + 0.05), (I["xm"] + 0.03, I["y_land"], I["z_land"] - 0.05), 0.06, 0.3)
    st.beam((I["xm"] - 0.03, I["y_land"], I["z_land"] + 0.05), (I["xm"] - 0.03, I["hole_y0"], FL2 - 0.05), 0.06, 0.3)
    st.beam((I["x0"] + 0.03, I["y_land"], I["z_land"] + 0.05), (I["x0"] + 0.03, I["hole_y0"], FL2 - 0.05), 0.06, 0.3)
    st.box(I["x0"], I["y_land"] + 0.1, FL1, I["x0"] + 0.12, I["y_land"] + 0.22, I["z_land"] - 0.15)   # 踊り場の柱
    st.done(bevel=0.01)
    ir = M("instair_rail", "rail", "interior")
    rail_run(ir, (I["xm"] + 0.04, I["y_bottom"], FL1 + ri), (I["xm"] + 0.04, I["y_land"], I["z_land"]), h=0.9,
             posts_every=5, name="bal_instair_1")
    rail_run(ir, (I["x0"] + 0.04, I["y_land"], I["z_land"]), (I["x0"] + 0.04, I["hole_y0"], FL2), h=0.9,
             posts_every=5, name="bal_instair_2")
    rail_run(ir, (I["x0"] - 0.05, I["hole_y0"], FL2), (I["x0"] - 0.05, I["y_top"], FL2), h=RAIL_H,
             name="bal_stairwell_w")
    rail_run(ir, (I["xm"], I["hole_y0"], FL2), (I["x1"], I["hole_y0"], FL2), h=RAIL_H,   # 2 本目の上がり口は空ける
             name="bal_stairwell_s")
    ir.done(bevel=0.01)
    # 1 階の吊り灯り（卓の上）と 2 階の紙の灯り
    lp = M("lamps", "paper", "interior")
    for x, y in TABLES:
        for j in (0.25, 0.75):
            cx, cy = x + tw * j, y + td / 2
            lp.cyl((cx, cy, CEIL1 - 0.9), (cx, cy, CEIL1 - 0.55), 0.22, seg=20)
    for x, ky in KOTATSU:
        cx = x + KOTATSU_W / 2
        cy = ky + KOTATSU_D / 2
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
    pits = []
    for i, (x, ky0) in enumerate(KOTATSU):
        ky1 = ky0 + KOTATSU_D
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
    for x, ky0 in KOTATSU:
        ky1 = ky0 + KOTATSU_D
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
    b2.box(INSTAIR["x0"] - 2.0, INSTAIR["hole_y0"] - 0.5, FL2, INSTAIR["x0"] - 0.5, INSTAIR["hole_y0"] - 0.15, FL2 + 0.9)   # 下足箱
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
    # 灯りの場所の目印。glTF の灯りは明るさの単位が合わないので、ゲームの側で灯りを置く
    lights = [("light_lamp_%d" % i, (x + tw * j, y + td / 2, CEIL1 - 0.75))
              for i, (x, y, j) in enumerate((x, y, j) for x, y in TABLES for j in (0.25, 0.75))]
    lights += [("light_lantern_%d" % i, (x + KOTATSU_W / 2, ky + KOTATSU_D / 2, FL2 + TATAMI["h"] + 1.95))
               for i, (x, ky) in enumerate(KOTATSU)]
    lights.append(("light_fire", ((CH["x0"] + CH["x1"]) / 2, CH["y0"] - 0.35, FL1 + 0.6)))
    lights.append(("light_kitchen", (gx(3.7), gy(0.8), CEIL1 - 0.4)))
    lights.append(("light_vestibule", (VEST["cx"], Y0 - VEST["d"] / 2, VEST["h"] - 1.1)))
    for name, loc in lights:
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "SPHERE"
        e.empty_display_size = 0.2
        e.location = loc
        coll("markers").objects.link(e)


# ---------------------------------------------------------------- 地面・光・カメラ
def build_ground():
    g = M("ground", "snow", "ground")
    g.box(-300, -300, -0.3, 300, 300, 0)
    g.done()
    me = bpy.data.meshes.new("hill")
    verts, faces, N = [], [], 64
    for j in range(N + 1):
        for i in range(N + 1):
            x = -120 + i * 240 / N
            y = HILL_Y - j * 90 / N
            d = HILL_Y - y
            verts.append((x, y, (d ** 1.3) * 0.18))
    for j in range(N):
        for i in range(N):
            a = j * (N + 1) + i
            faces.append([a, a + N + 1, a + N + 2, a + 1])   # 上向き
    me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new("hill", me)
    coll("ground").objects.link(o)
    me.materials.append(mat("snow"))
    me.shade_smooth()


def build_scenery():
    """ロッジのまわりのフェルトの木と、遠くの山なみ（書き出さない）"""
    import random
    rnd = random.Random(7)
    T = M("trees", "tree", "scenery")
    S = M("tree_snow", "snow", "scenery")
    W = M("trunks", "trunk", "scenery")
    spots = [(-52, 28), (-62, 8), (-44, 52), (-24, 60), (4, 66), (32, 58), (54, 40), (66, 12), (60, -18),
             (48, 80), (-72, 60), (-88, 24), (80, 52), (16, 92), (-56, -56), (-68, -88), (60, -64), (76, -96),
             (-92, -36), (92, -12), (28, -60), (44, -88), (16, -120), (60, -124), (-80, -112), (-16, -144), (80, -160),
             (-52, -168)]
    for x, y in spots:
        k = rnd.uniform(0.85, 1.5)
        x += rnd.uniform(-2, 2)
        y += rnd.uniform(-2, 2)
        z = ((HILL_Y - y) ** 1.3) * 0.18 if y < HILL_Y else 0.0
        W.cyl((x, y, z - 0.2), (x, y, z + 1.0 * k), 0.20 * k)
        for z0, r, h in ((0.8, 1.7, 2.6), (2.5, 1.2, 2.3)):
            bmesh.ops.create_cone(T.bm, cap_ends=True, segments=20, radius1=r * k, radius2=0.0, depth=h * k,
                                  matrix=Matrix.Translation((x, y, z + (z0 + h / 2) * k)))
        bmesh.ops.create_cone(S.bm, cap_ends=True, segments=20, radius1=0.62 * k, radius2=0.0, depth=0.95 * k,
                              matrix=Matrix.Translation((x, y, z + (2.5 + 2.3 - 0.95 / 2 - 0.05) * k)))
    T.done(bevel=0.05, seg=2, smooth=True)
    S.done(bevel=0.04, seg=2, smooth=True)
    W.done(smooth=True)
    F = M("far_hills", "far", "scenery")
    for x, y, sx, sz in ((-130, 280, 90, 16), (-10, 300, 120, 22), (120, 285, 90, 14), (230, 250, 80, 12),
                         (-240, 240, 80, 12)):
        bmesh.ops.create_uvsphere(F.bm, u_segments=32, v_segments=16, radius=1.0,
                                  matrix=Matrix.Translation((x, y, 0)) @ Matrix.Diagonal((sx, 18, sz, 1)))
    F.done(smooth=True)


def point(name, loc, watts, color, radius=0.15, shadow=True):
    L = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
    coll("lights").objects.link(L)
    L.location = loc
    L.data.energy = watts
    L.data.color = color
    L.data.shadow_soft_size = radius
    L.data.use_shadow = shadow
    return L


def build_light():
    """光源: 昼は南西から高度 28 度の午後の光（暖色）、環境は空の青。夕方は高度 6 度の橙、空は藍。
    中は卓の上の紙の灯り、2 階の紙の行灯、北の炉の火。色相は外の青と中の橙の 2 つ"""
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    coll("lights").objects.link(sun)
    sun.data.angle = math.radians(2)
    if A.look == "dusk":
        sun.data.energy = 2.2
        sun.data.color = (1.0, 0.52, 0.30)
        sun.rotation_euler = (math.radians(84), 0, math.radians(-62))
    else:
        sun.data.energy = 4.5 if A.look == "day" else 4.5
        sun.data.color = (1.0, 0.86, 0.68) if A.look == "day" else (1, 1, 1)
        sun.rotation_euler = (math.radians(62), 0, math.radians(-45))   # 南西から、高度 28 度
    if A.look == "clay":
        w = bpy.data.worlds.new("w")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.70, 0.85, 1)
        w.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    else:
        import materials
        w = materials.world(A.look)
    sc.world = w
    if PH < 4:
        return
    if A.look == "clay":   # 中を見るための仮の灯り
        for x, y, z, e in [(gx(3), gy(3.5), 3.4, 250), (gx(7), gy(4.6), 3.4, 250), (gx(10), gy(3.0), 3.4, 250),
                           (gx(3), gy(1.0), 3.0, 150), (gx(5), gy(2.6), FL2 + 2.6, 220), (gx(9), gy(2.6), FL2 + 2.6, 220)]:
            point("lamp", (x, y, z), e, (1.0, 0.86, 0.68), 0.5)
        return
    k = 2.6 if A.look == "dusk" else 1.8
    warm = (1.0, 0.68, 0.40)   # 電球色より少し赤み
    tw, td = TABLE["w"], TABLE["d"]
    for x, y in TABLES:
        for j in (0.25, 0.75):
            point("lamp_1f", (x + tw * j, y + td / 2, CEIL1 - 0.75), 45 * k, warm, 0.2, shadow=False)
    for x, ky in KOTATSU:
        point("lantern_2f", (x + KOTATSU_W / 2, ky + KOTATSU_D / 2, FL2 + TATAMI["h"] + 1.95), 70 * k, warm, 0.25)
    point("kitchen", (gx(3.7), gy(0.8), CEIL1 - 0.4), 120 * k, (1.0, 0.74, 0.48), 0.4)
    point("rental", (gx(0.8), gy(0.9), CEIL1 - 0.4), 60 * k, (1.0, 0.74, 0.48), 0.4)
    point("vestibule", (VEST["cx"], Y0 - VEST["d"] / 2, VEST["h"] - 1.1), 90 * k, warm, 0.3)
    ar = bpy.data.objects.new("fill_2f", bpy.data.lights.new("fill_2f", "AREA"))   # 2 階の天井の柔らかい灯り
    coll("lights").objects.link(ar)
    ar.data.shape = "RECTANGLE"
    ar.data.size, ar.data.size_y = 28.0, 9.0
    ar.data.energy = 1300 * k
    ar.data.color = warm
    ar.location = (gx(6.5), gy(2.6), roof_z(gy(2.6)) - 0.2)
    cx = (CH["x0"] + CH["x1"]) / 2
    point("fire", (cx, CH["y0"] - 0.35, FL1 + 0.6), 260, (1.0, 0.45, 0.16), 0.3)
    point("fire_glow", (cx, CH["y0"] - 1.6, FL1 + 0.4), 90, (1.0, 0.5, 0.2), 0.6)


CAMS = {
    "hill": ((-34, -76, 24), (1, -4, 7.5), 35),
    "west": ((-88, -14, 12), (0, 0, 7.5), 36),
    "east": ((80, -44, 18), (0, -2, 7), 36),
    "north": ((28, 80, 18), (0, 0, 6.5), 36),
    "aerial": ((-68, -84, 68), (0, -2, 4), 32),
    "close": ((-19, -42, 4.5), (-7, -13, 7.0), 30),
    "in1": ((gx(2.5), Y0 + 1.0, FL1 + 1.55), (gx(9.0), Y1 - 1.0, FL1 + 1.2), 20),
    "in2": ((gx(0.5), gy(3.6), FL2 + 1.55), (gx(10.5), gy(2.4), FL2 + 0.55), 22),
    "kotatsu": ((gx(5.3), gy(1.2), FL2 + TATAMI["h"] + 1.05), (gx(3.0), Y0 - 8, FL2 + 1.6), 24),
    "entrance": ((VEST["cx"] - 9, Y0 - VEST["d"] - 13, 3.2), (VEST["cx"], Y0 - VEST["d"], 2.8), 30),
    "vest_in": ((VEST["cx"] + 2.6, Y0 - VEST["d"] + 0.8, FL1 + 1.6), (VEST["x0"] + 0.8, Y0 - 0.4, FL1 + 1.0), 22),
    "stair1": ((gx(8.2), gy(3.2), FL1 + 1.6), (INSTAIR["xm"], INSTAIR["y_land"], 2.6), 24),
    "stair2": ((INSTAIR["x0"] - 4.0, INSTAIR["hole_y0"] - 4.5, FL2 + 1.6), (INSTAIR["xm"], INSTAIR["y_land"], FL2 - 0.8), 24),
    "bar": ((gx(4.2), Y0 + 2.6, FL1 + 1.6), (gx(9.5), Y0 + 0.2, FL1 + 0.9), 24),
    "terrace": ((gx(7.0), Y2_0 - 0.7, FL2 + 1.55), (gx(3.0), Y0 - 30, 4.5), 24),
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


# ---------------------------------------------------------------- 当たり判定（書き出し用）
def build_collision():
    """箱と坂だけの当たり判定。名前の -colonly で、Godot は見た目なしの当たり判定として読み込む。
    戸の開口は抜き、窓は塞ぐ。椅子・灯り・小物は入れない"""
    groups = {}

    def g(name):
        if name not in groups:
            groups[name] = M("col_%s-colonly" % name, "dark", "collision")
        return groups[name]

    def wall(m, axis, fixed, a0, a1, z0, z1, gaps=(), t=LOG_D):
        """壁を箱で。gaps は戸の開口 (u0, u1, 上端)"""
        segs = [(a0, a1)]
        for u0, u1, zt in gaps:
            segs = subtract(segs, u0, u1)
            wbox(m, axis, fixed, 1, u0, u1, -t / 2, t / 2, zt, z1)
        for u0, u1 in segs:
            wbox(m, axis, fixed, 1, u0, u1, -t / 2, t / 2, z0, z1)

    def ramp_y(m, x0, x1, ya, za, yb, zb, t=0.25):
        """y 方向に上る坂（階段の代わり）"""
        prof = [(ya, za - t), (yb, zb - t), (yb, zb), (ya, za)]
        if yb < ya:
            prof = prof[::-1]
        m.prism_x(prof[::-1], x0, x1)

    F, Wl, Rf, St, Fu = g("floor"), g("walls"), g("roof"), g("stairs"), g("furniture")
    # 床: 基壇、デッキ、2 階の床（階段の穴を抜く）
    F.box(X0 - 0.15, Y0 - 0.15, 0, X1 + 0.15, Y1 + 0.15, FL1)
    D_ = DECK
    F.box(D_["x0"], D_["y0"], 0, D_["x1"], D_["y1"], D_["z"])
    I = INSTAIR
    hx, hy = I["x0"] - 0.05, I["hole_y0"]
    F.box(X0 - 0.09, Y0 - 0.09, CEIL1, hx, Y1 + 0.09, FL2)
    F.box(hx, Y0 - 0.09, CEIL1, X1 + 0.09, hy, FL2)
    F.box(TATAMI["x0"], TATAMI["y0"], FL2, TATAMI["x1"], TATAMI["y1"], FL2 + TATAMI["h"])
    # 1 階の壁（ガラスの壁も塞ぐ）
    dw = DOOR1["w"]
    c1 = [c for c, k in OPENINGS["1F_N"] if k == "door1"][0]
    wall(Wl, "x", Y1, X0, X1, FL1, CEIL1, [(c1 - dw / 2, c1 + dw / 2, FL1 + DOOR1["h"])])
    wall(Wl, "y", X1, Y0, Y1, FL1, CEIL1)
    wall(Wl, "x", Y0, X0, GLASS_S_X0, FL1, CEIL1, [(DOOR_IN["x0"], DOOR_IN["x1"], FL1 + DOOR_IN["h"])])
    wall(Wl, "x", Y0, GLASS_S_X0, X1, FL1, CEIL1, t=POST)
    wp = sorted(GLASS_W_POSTS)
    wall(Wl, "y", X0, Y0, Y1, FL1, CEIL1, [(wp[GLASS_W_DOOR_BAY] + POST / 2, wp[GLASS_W_DOOR_BAY + 1] - POST / 2, TRANSOM)], t=POST)
    V, A_ = VEST, ARCH
    y0v, cx = Y0 - V["d"], V["cx"]
    F.box(V["x0"], y0v, 0, V["x1"], Y0, FL1)
    ramp_y(St, cx - A_["r"] - 0.6, cx + A_["r"] + 0.6, y0v - 1.05, 0, y0v, FL1)   # アーチの前の 3 段は坂に
    Wl.box(V["x0"], y0v + V["t"], FL1, V["x0"] + 0.16, Y0, V["h"])          # 金網
    Wl.box(V["x1"] - 0.16, y0v + V["t"], FL1, V["x1"], Y0, V["h"])
    wall(Wl, "x", y0v + V["t"] / 2, V["x0"], V["x1"], FL1, V["h"],
         [(cx - A_["r"], cx + A_["r"], A_["spring"] + A_["r"] * 0.7)], t=V["t"])
    for sgn in (-1, 1):                                                      # 開いたアーチ戸
        h0 = cx + sgn * A_["r"]
        Wl.box(min(h0, h0 + sgn * A_["r"]), y0v - 0.14, FL1, max(h0, h0 + sgn * A_["r"]), y0v, A_["spring"])
    Rf.box(V["x0"] - V["roof_out"], y0v - V["roof_out"], V["h"], V["x1"] + V["roof_out"], Y0, V["h"] + 0.36)
    VM = VENDING
    Fu.box(V["x0"] + 0.30, Y0 - 0.05 - VM["d"], FL1, V["x0"] + 0.30 + 2 * VM["w"] + VM["gap"], Y0, FL1 + VM["h"])
    # 2 階の壁（テラスへの戸を抜く）。妻は屋根の勾配まで
    c2 = [c for c, k in OPENINGS["2F_S"] if k == "door2"][0]
    wall(Wl, "x", Y2_0, X0, X1, FL2, EAVE_S, [(c2 - DOOR2["w"] / 2, c2 + DOOR2["w"] / 2, FL2 + DOOR2["h"])])
    wall(Wl, "x", Y1, X0, X1, FL2, EAVE_N)
    for x in (X0, X1):
        Wl.solid([(x - R, Y2_0, FL2), (x + R, Y2_0, FL2), (x + R, Y1, FL2), (x - R, Y1, FL2)],
                 [(x - R, Y2_0, roof_z(Y2_0)), (x + R, Y2_0, roof_z(Y2_0)), (x + R, Y1, roof_z(Y1)), (x - R, Y1, roof_z(Y1))])
    for x, y in COLS:
        Wl.box(x - COL_D / 2, y - COL_D / 2, FL1, x + COL_D / 2, y + COL_D / 2, roof_z(y))
    # 煙突と炉
    c = CH
    Wl.box(c["x0"], c["y0"], 0, c["x1"], c["y1"], FL2)
    Wl.box(c["ux0"], c["uy0"], FL2, c["ux1"], c["uy1"], c["top"] + 0.56)
    # 屋根（雪まで含めた厚み）と下屋の屋根
    ys, yn = Y2_0 - EAVE_OUT_S, Y2_1 + EAVE_OUT_N
    tv = (RAFTER["h"] + ROOF_T + SNOW_T) / math.cos(math.atan(ROOF_PITCH))
    Rf.prism_x([(ys, roof_z(ys)), (yn, roof_z(yn)), (yn, roof_z(yn) + tv), (ys, roof_z(ys) + tv)][::-1],
               X0 - VERGE_OUT, X1 + VERGE_OUT)
    L = LEAN
    Rf.prism_y([(L["x_out"], L["z_out"]), (X0, L["z_wall"]), (X0, L["z_wall"] + 0.4), (L["x_out"], L["z_out"] + 0.4)],
               L["y0"], L["y1"])
    for y in L["posts"]:
        Wl.box(L["x_post"] - 0.10, y - 0.10, 0, L["x_post"] + 0.10, y + 0.10, L["z_out"])
    # 手すり（テラス・外階段・吹き抜け）
    for b in ((X0 + K, Y0, FL2, X1, Y0 + 0.12, FL2 + RAIL_H), (X1 - 0.12, Y0, FL2, X1, Y2_0, FL2 + RAIL_H),
              (X0, Y0, FL2, X0 + 0.12, Y2_0, FL2 + RAIL_H),
              (hx - 0.1, hy, FL2, hx, Y1, FL2 + RAIL_H), (I["xm"], hy - 0.1, FL2, X1, hy, FL2 + RAIL_H)):
        Wl.box(*b)
    # 階段は坂にする（外階段 2 本と踊り場、内階段、デッキの東の段）
    E = ESTAIR
    ramp_y(St, *E["x_lo"], E["y_start"], FL1, E["y_land"], E["z_land"])
    ramp_y(St, *E["x_up"], E["y_land"], E["z_land"], E["y_start"], FL2)
    St.box(E["x_lo"][0], E["y_land"] - E["landing"], E["z_land"] - 0.15, E["x_up"][1], E["y_land"], E["z_land"])
    St.box(E["x_up"][0], E["y_start"], FL2 - 0.15, E["x_up"][1], Y0, FL2)
    for x in (E["x_lo"][0], E["x_up"][1] - 0.08):
        St.box(x, E["y_land"] - E["landing"], E["z_land"], x + 0.08, E["y_land"], E["z_land"] + 1.0)
    St.box(E["x_lo"][0], E["y_land"] - E["landing"], E["z_land"], E["x_up"][1], E["y_land"] - E["landing"] + 0.08,
           E["z_land"] + 1.0)
    ramp_y(St, I["xm"], I["x1"], I["y_bottom"] - I["tread"], FL1, I["y_land"], I["z_land"])
    St.box(I["x0"], I["y_land"], I["z_land"] - 0.15, I["x1"], I["y_top"], I["z_land"])
    ramp_y(St, I["x0"], I["xm"], I["y_land"], I["z_land"], I["hole_y0"], FL2)
    Wl.box(I["xm"] - 0.04, I["hole_y0"], I["z_land"], I["xm"] + 0.04, I["y_land"], FL2 + 1.0)   # 2 本の間の手すり
    St.prism_y([(D_["x1"], D_["z"]), (D_["x1"] + 0.6, 0.0), (D_["x1"], 0.0)][::-1], D_["y0"], D_["y1"])
    # 家具（座れる・ぶつかるもの）
    for x, y in TABLES:
        Fu.box(x, y, FL1, x + TABLE["w"], y + TABLE["d"], FL1 + TABLE["h"])
    for cc in (COUNTER, RENTAL):
        Fu.box(cc["x0"], cc["y0"], FL1, cc["x1"], cc["y1"], FL1 + cc["h"])
    Fu.box(BACK["x0"], BACK["y0"], FL1, BACK["x1"], BACK["y1"], FL1 + BACK["h"])
    Fu.box(WINDOW_BAR["x0"], WINDOW_BAR["y0"], FL1, WINDOW_BAR["x1"], WINDOW_BAR["y0"] + WINDOW_BAR["d"],
           FL1 + WINDOW_BAR["h"])
    for x in (KITCHEN["x0"], KITCHEN["x1"]):
        Fu.box(x - 0.06, KITCHEN["y_front"], FL1, x + 0.06, Y1, CEIL1 - 0.3)
    for x0, y0, x1, y1 in HEARTH_BENCH:
        Fu.box(x0, y0, FL1, x1, y1, FL1 + 0.45)
    Fu.box(c["x0"] - 0.25, c["y0"] - 0.65, FL1, c["x1"] + 0.25, c["y0"], FL1 + 0.12)
    S_ = SKI_RACK
    Fu.box(S_["x0"], S_["y0"], FL1, S_["x1"], S_["y1"], FL1 + 1.75)
    zt = FL2 + TATAMI["h"]
    for x, ky in KOTATSU:
        Fu.box(x - 0.12, ky - 0.12, zt, x + KOTATSU_W + 0.12, ky + KOTATSU_D + 0.12, zt + 0.40)
    Fu.box(*BENCH2[:2], FL2, *BENCH2[2:], FL2 + 0.42)
    Fu.box(TABLE2[0], TABLE2[1], FL2, TABLE2[2], TABLE2[3], FL2 + 0.72)
    return [m.done() for m in groups.values()]


def export(folder):
    """lodge.glb（見た目と置き場の目印）と lodge_collision.glb（当たり判定）"""
    os.makedirs(folder, exist_ok=True)
    keep = ("walls", "crown", "interior", "setsue", "markers")

    def write(objs, name):
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.hide_set(False)
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        path = os.path.abspath(os.path.join(folder, name))
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_lights=False, export_cameras=False, export_yup=True)
        print("wrote", path)

    write([o for c in keep if bpy.data.collections.get(c) for o in bpy.data.collections[c].objects], "lodge.glb")
    write(build_collision(), "lodge_collision.glb")



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
if A.look in ("day", "dusk"):
    build_scenery()
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
if A.look in ("day", "dusk"):
    sc.eevee.taa_render_samples = 64
    if hasattr(sc.eevee, "shadow_pool_size"):
        sc.eevee.shadow_pool_size = "1024"
    for attr, v in (("use_raytracing", True), ("use_shadows", True), ("use_gtao", True)):
        if hasattr(sc.eevee, attr):
            setattr(sc.eevee, attr, v)
    if hasattr(sc.eevee, "fast_gi_method"):
        sc.eevee.use_fast_gi = True
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = -0.35 if A.look == "day" else 0.0
if A.look in ("day", "dusk") and PH >= 4:
    # 中に光の箱を置いて焼く。空の青が丸太の壁を抜けて中に回り込まないように
    bpy.ops.object.lightprobe_add(type="VOLUME", location=(0, (Y0 + Y1) / 2, (FL1 + EAVE_S) / 2))
    pv = bpy.context.object
    pv.scale = ((X1 - X0) / 2 - 0.2, (Y1 - Y0) / 2 - 0.2, (EAVE_S - FL1) / 2 - 0.1)
    for attr, v in (("resolution_x", 24), ("resolution_y", 14), ("resolution_z", 10)):
        if hasattr(pv.data, attr):
            setattr(pv.data, attr, v)
    try:
        bpy.ops.object.lightprobe_cache_bake(subset="ALL")
    except Exception as e:   # 焼けないときはそのまま描く
        print("bake failed", e)
if A.blend:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
if A.export:
    export(A.export)
for v in ([] if A.export else A.views.split(",")):
    render(v, os.path.abspath("%s-%s.png" % (A.prefix, v)))
