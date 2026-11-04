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
    "log": (0.74, 0.69, 0.62), "chink": (0.93, 0.90, 0.84), "post": (0.50, 0.45, 0.40), "frame": (0.90, 0.88, 0.82),
    "board": (0.68, 0.62, 0.54), "door": (0.46, 0.38, 0.31), "deck": (0.64, 0.58, 0.50), "tread": (0.64, 0.58, 0.50),
    "rail": (0.60, 0.55, 0.48), "stone": (0.58, 0.57, 0.55), "roof": (0.17, 0.20, 0.40),
    "snow": (0.92, 0.93, 0.96), "glass": (0.10, 0.13, 0.18), "metal": (0.22, 0.22, 0.24),
    "dark": (0.05, 0.04, 0.04), "tatami": (0.76, 0.74, 0.56), "cushion": (0.70, 0.46, 0.36),
    "quilt": (0.66, 0.52, 0.40), "paper": (0.95, 0.92, 0.85), "felt_red": (0.62, 0.30, 0.25),
    "felt_blue": (0.28, 0.38, 0.60), "felt_green": (0.40, 0.52, 0.32), "felt_yellow": (0.80, 0.64, 0.30),
    "mat_out": (0.55, 0.45, 0.32), "mat_out_edge": (0.25, 0.20, 0.16), "mat_in": (0.60, 0.40, 0.34), "mat_fringe": (0.90, 0.87, 0.80),
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


CHINK = []   # 丸太の継ぎ目の綿を詰める所 (axis, fixed, s0, s1, z)。build_walls が最後に形にする


def log_wall(m, axis, fixed, a0, a1, z0, z1, offset, holes=(), top=None):
    """丸太を段に積む。holes は (u0, u1, 下, 上)。top(z) はその高さで丸太が届く u の上限（妻）。
    段と段の継ぎ目には綿を詰める（CHINK に積んで、build_walls が外と中の両面に細い帯で置く）"""
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
                if zc + LOG_H < z1 + 0.02:   # この段と上の段の継ぎ目（上の段がある所だけ）
                    CHINK.append((axis, fixed, s0 + 0.05, s1 - 0.05, zc + LOG_H / 2))
        last = zc + LOG_H / 2
    return last


# ---------------------------------------------------------------- 窓と戸
def opening(F, G, D, axis, fixed, sgn, c, w, cb, ct, kind, tag=""):
    """窓・戸の枠。F 枠、G ガラス、D 戸板。cb..ct が丸太を抜いた範囲。tag は戸の名前（動く戸の部品の名前に使う）"""
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
            a, b = u0 + L + k * lw + 0.005, u0 + L + (k + 1) * lw - 0.005
            # 板の下端は床から 5.5 cm（敷居 3 cm の上）。開くと出入り口のマット（dims.DOORMATS）の上を、当たらずに通る
            swing_leaf("%s_%d" % (tag, k), axis, fixed, sgn, a, b, cb + 0.055, ct - L, -0.06, -0.01,
                       hinge_at_u0=(k == 0))


def swing_leaf(name, axis, fixed, sgn, u0, u1, z0, z1, v0, v1, hinge_at_u0=True, glass=0.55):
    """開き戸の板 1 枚を、別の部品 swingdoor_<name>（板）と swingdoor_<name>_glass（ガラス）にし、蝶番の軸の下の端に
    目印 hinge_swingdoor_<name> を置く。ゲームの lodge.gd が、近づいた人から見て押す向きにこの軸で回す（2026-11-02 代表
    「しまってる状態なら自分側から押して開く方に開いて、もし誰か開けてたりして引き戸の方に開いてたらそのまま開けて」）"""
    lm = M("swingdoor_" + name, "door", "walls")
    lg = M("swingdoor_%s_glass" % name, "glass", "walls")
    door_leaf(lm, lg, axis, fixed, sgn, u0, u1, z0, z1, v0, v1, glass=glass)
    lm.done(bevel=0.006)
    lg.done()
    hu = u0 if hinge_at_u0 else u1
    hv = fixed + sgn * (v0 + v1) / 2
    e = bpy.data.objects.new("hinge_swingdoor_" + name, None)
    e.empty_display_type = "SINGLE_ARROW"
    e.empty_display_size = 0.3
    e.location = (hu, hv, z0) if axis == "x" else (hv, hu, z0)
    coll("markers").objects.link(e)


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


def glass_wall(P, F, G, D, axis, fixed, sgn, posts, z0, z1, door_bay=None, plain=False):
    """柱とガラスの壁。各間に縦桟 1 本と欄間の横桟。plain は桟なしの 1 枚ガラス（柱と上下の枠だけ）"""
    posts = sorted(posts)
    for u in posts:
        wbox(P, axis, fixed, sgn, u - POST / 2, u + POST / 2, -POST / 2, POST / 2, z0, z1)
    for k, (a, b) in enumerate(zip(posts, posts[1:])):
        a, b = a + POST / 2, b - POST / 2
        wbox(F, axis, fixed, sgn, a, b, -0.09, 0.09, z0, z0 + 0.10)
        wbox(F, axis, fixed, sgn, a, b, -0.09, 0.09, z1 - 0.14, z1)
        wbox(F, axis, fixed, sgn, a - 0.02, b + 0.02, 0.09, 0.14, z0 - 0.02, z0 + 0.04)   # 外の水切り
        if plain:
            wbox(G, axis, fixed, sgn, a, b, -0.005, 0.005, z0 + 0.10, z1 - 0.14)
            continue
        wbox(F, axis, fixed, sgn, a, b, -0.05, 0.05, TRANSOM - 0.045, TRANSOM + 0.045)
        mid = (a + b) / 2
        if k == door_bay:
            for j, (u0, u1) in enumerate(((a, mid), (mid, b))):
                swing_leaf("glass_%s_%d" % (axis, j), axis, fixed, sgn, u0 + 0.01, u1 - 0.01, z0 + 0.10, TRANSOM - 0.045,
                           -0.04, 0.04, hinge_at_u0=(j == 0), glass=0.8)
            wbox(G, axis, fixed, sgn, a, b, -0.005, 0.005, TRANSOM, z1 - 0.14)
            continue
        wbox(F, axis, fixed, sgn, mid - 0.03, mid + 0.03, -0.05, 0.05, z0, z1)
        for u0, u1 in ((a, mid - 0.03), (mid + 0.03, b)):
            wbox(G, axis, fixed, sgn, u0, u1, -0.005, 0.005, z0 + 0.10, z1 - 0.14)


# ---------------------------------------------------------------- 段階 1: 塊
def build_massing():
    m = M("massing_lodge", "log", "massing")
    m.box(X0, Y0, FL1, X1, Y1, CEIL1)
    m.prism_x([(Y2_0, FL2), (Y2_1, FL2), (Y2_1, EAVE_N), (Y2_0, EAVE_S)], X2_0, X2_1)
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
    s.prism_x([(E["y_foot"], FL1), (E["y_land0"], E["z_land"]), (E["y_land0"], E["z_land"] - 0.3),
               (E["y_foot"], FL1 - 0.3)], E["x0"], E["x1"])
    s.prism_x([(E["y_land1"], E["z_land"]), (E["y_top"], FL2), (E["y_top"], FL2 - 0.3),
               (E["y_land1"], E["z_land"] - 0.3)], E["x0"], E["x1"])
    s.box(E["x0"], E["y_land0"], E["z_land"] - 0.15, E["x1"], E["y_land1"], E["z_land"])
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
    # 1 階の部屋の側へは出さない（壁の内の面まで）。大きな暖炉（props/build_nook.py）の炉の奥に入り込まないように
    m.box(c["x0"], Y1 - LOG_D / 2 - 0.02, 0, c["x1"], c["y1"], sh)
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
    m.done(bevel=0.03 if PH >= 3 else 0)
    # 炉の口・炉床・飾り棚・火は作らない。1 階の大きな暖炉は props/build_nook.py の品物を、ゲームが目印 slot_hearth に置き、
    # この煙突の塊（1 階の部屋へ出た所）をすっぽり覆う（2026-11-02）


def roof_cutters():
    c = CH
    return cutter("cut_chimney_roof", c["ux0"] - 0.03, c["uy0"] - 0.03, 0, c["ux1"] + 0.03, c["uy1"] + 0.03, 20)


def build_roof(chim_cut):
    ys, yn = Y2_0 - EAVE_OUT_S, Y2_1 + EAVE_OUT_N
    lift = RAFTER["h"] if PH >= 3 else 0.0
    tv = ROOF_T / math.cos(math.atan(ROOF_PITCH))
    zs, zn = roof_z(ys) + lift, roof_z(yn) + lift
    xa, xb = X2_0 - VERGE_OUT, X1 + VERGE_OUT
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
    h, hb = L["post"] / 2, L["post"] * 0.9   # 柱の半幅と、台の半幅
    for y in L["posts"]:
        p.box(L["x_post"] - h, y - h, 0, L["x_post"] + h, y + h, zr(L["x_post"]))
        if PH >= 3:
            p.box(L["x_post"] - hb, y - hb, 0, L["x_post"] + hb, y + hb, 0.18)   # 石の束の代わりの台
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
    walls.append(("2F_S", "x", Y2_0, -1, X2_0 - ext, X1 + ext, FL2, EAVE_S, 0.0, [], None))
    walls.append(("2F_N", "x", Y1, 1, X2_0 - ext, X1 + ext, FL2, EAVE_N, 0.0, [(c["ux0"], c["ux1"], -1, 99)], None))
    gable_top = lambda z: Y1 - (z - EAVE_N) / ROOF_PITCH if z > EAVE_N else 99   # noqa: E731
    walls.append(("2F_W", "y", X2_0, -1, Y2_0 - ext, Y1 + ext, FL2, EAVE_S, LOG_H / 2, [], gable_top))   # 西の端はテラス
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
            opening(F, G, D, axis, fixed, sgn, cc, w, cb, ct, kind, tag=("%s_%d" % (key, round(cc * 10))).replace("-", "m"))
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
    # 正面（南）は桟を抜いた 1 枚ガラス（2026-11-03 代表「ロッジ正面側のガラスの格子外して」。見通しのため）
    glass_wall(P, F, G, D, "x", Y0, -1, GLASS_S_POSTS, FL1, CEIL1, plain=True)
    glass_wall(P, F, G, D, "y", X0, -1, GLASS_W_POSTS, FL1, CEIL1, door_bay=GLASS_W_DOOR_BAY)
    # 2 階の南の壁を受ける梁と丸柱
    Bm = M("beam", "post", "walls")
    Bm.box(X0, Y2_0 - R, CEIL1 - 0.30, X1, Y2_0 + R + 0.12, CEIL1)
    Bm.done(bevel=0.015)
    Cl = M("columns", "post", "walls")
    for x, y in COLS:
        Cl.cyl((x, y, FL1), (x, y, FL2), COL_D / 2, seg=28)
        Cl.cyl((x, y, FL2), (x, y, roof_z(y) + (RAFTER["h"] if PH >= 3 else 0)), COL_D / 2 * 0.85, seg=28)
    Cl.done(smooth=True)
    build_vestibule()
    # 継ぎ目の綿: 丸太の丸みのくぼみに、外と中の両面から見える細い帯（厚み 2 cm の箱 1 本。丸太にほぼ埋まり、くぼみにだけ出る）
    Ck = M("chinking", "chink", "walls")
    for axis, fixed, s0, s1, z in CHINK:
        if s1 - s0 < 0.1:
            continue
        hw = R * 0.5
        if axis == "x":
            Ck.box(s0, fixed - hw, z - 0.011, s1, fixed + hw, z + 0.011)
        else:
            Ck.box(fixed - hw, s0, z - 0.011, fixed + hw, s1, z + 0.011)
    Ck.done()
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
    """風除室: 1 階の屋根まである木のアーチの両開き戸（外へ開け放す）。中は自販機とマット、マットの両横は格子の溝"""
    V, A = VEST, ARCH
    cx, r, zs = V["cx"], A["r"], A["spring"]
    y0, yb = Y0 - V["d"], Y0 - V["d"] + V["t"]          # 前の壁の外面と内面
    # 床: マットの帯と自販機の前は木の床。マットの両横は、雪が下へ落ちる鉄の格子（溝蓋）を敷いた浅い溝
    mx0, mx1 = cx - 1.6, cx + 1.6                        # マット
    gy0, gy1 = yb + 0.15, Y0 - 0.95                      # 格子の溝の南北（北は自販機の前を空ける）
    gx_ = [(V["x0"] + V["t"] + 0.05, mx0 - 0.08), (mx1 + 0.08, V["x1"] - V["t"] - 0.05)]
    PIT = 0.22
    fl = M("vest_floor", "deck", "walls")
    fl.box(V["x0"], y0, 0, V["x1"], Y0, FL1 - PIT)
    fl.box(V["x0"], y0, FL1 - PIT, V["x1"], gy0, FL1)            # 前の壁の内の帯
    fl.box(V["x0"], gy1, FL1 - PIT, V["x1"], Y0, FL1)            # 自販機の前の帯
    fl.box(V["x0"], gy0, FL1 - PIT, gx_[0][0], gy1, FL1)        # 壁際
    fl.box(gx_[0][1], gy0, FL1 - PIT, gx_[1][0], gy1, FL1)      # マットの帯
    fl.box(gx_[1][1], gy0, FL1 - PIT, V["x1"], gy1, FL1)
    fl.done(bevel=0.012)
    # 玄関前の広場: 風除室の前から外階段の登り口まで一続き。外まわりの段で東・南・西から上がれ、デッキにもつながる
    P = PLAZA
    pz = M("plaza", "deck", "walls")
    for k in range(P["steps"]):
        d = (P["steps"] - 1 - k) * P["tread"]
        z = FL1 * (k + 1) / P["steps"]
        pz.box(P["x0"] - d, P["y0"] - d, 0, P["x1"] + d, P["y1"], z)
        pz.box(P["x0"] - d, P["y1"], 0, V["x0"], DECK["y0"], z)        # 風除室の西（外階段の下を通ってデッキへ）
        pz.box(V["x1"], P["y1"], 0, P["x1"] + d, DECK["y0"], z)        # 風除室の東
    pz.done(bevel=0.012)
    pit = M("vest_drain", "dark", "walls")                        # 溝の底（暗い）
    grate = M("vest_grating", "metal", "walls")
    for a, b in gx_:
        pit.box(a, gy0, FL1 - PIT, b, gy1, FL1 - PIT + 0.01)
        grate.box(a, gy0, FL1 - 0.05, a + 0.03, gy1, FL1)         # 受けの枠
        grate.box(b - 0.03, gy0, FL1 - 0.05, b, gy1, FL1)
        grate.box(a, gy0, FL1 - 0.05, b, gy0 + 0.03, FL1)
        grate.box(a, gy1 - 0.03, FL1 - 0.05, b, gy1, FL1)
        n = int((b - a - 0.06) / 0.045)
        for i in range(1, n):                                     # 南北に通る受けの平鋼（人の歩く向き）
            x = a + 0.03 + (b - a - 0.06) * i / n
            grate.box(x - 0.0045, gy0, FL1 - 0.05, x + 0.0045, gy1, FL1)
        m = int((gy1 - gy0) / 0.10)
        for j in range(1, m):                                     # 東西のねじり棒
            y = gy0 + (gy1 - gy0) * j / m
            grate.box(a, y - 0.005, FL1 - 0.012, b, y + 0.005, FL1)
    pit.done()
    grate.done()
    # 前の壁（縦羽目の板）。アーチの左右と、アーチの上の三角を細い帯で
    # 壁は本体と同じ丸太。前の壁はアーチの形に切り抜く（丸の切り抜きは Blender のブール演算）
    Lv = M("vest_logs", "log", "walls")
    log_wall(Lv, "x", y0 + R, V["x0"] - LOG_OUT, V["x1"] + LOG_OUT, FL1, V["h"], 0.0, [(cx - r, cx + r, FL1, zs)])
    lv = Lv.done(smooth=True, cap_uv=True)
    Ls = M("vest_logs_side", "log", "walls")   # 両脇（切り抜かないので別の物体に）
    for x in (V["x0"] + R, V["x1"] - R):
        log_wall(Ls, "y", x, y0 - LOG_OUT, Y0, FL1, V["h"], LOG_H / 2)
    Ls.done(smooth=True, cap_uv=True)
    ac = M("cut_vest_arch", "dark", "cutters")
    ac.cyl((cx, y0 - 0.6, zs), (cx, yb + 0.6, zs), r, seg=48)
    aco = ac.done()
    aco.hide_render = True
    aco.display_type = "WIRE"
    cut(lv, aco)
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
    # 中: 靴の雪を落とすマット（溝の刻まれたゴム）、吊り灯り
    mt = M("vest_mat", "dark", "interior")
    mt.box(mx0, yb + 0.25, FL1, mx1, Y0 - 0.15, FL1 + 0.015)
    mt.done(bevel=0.004)
    rb = M("vest_mat_ribs", "metal", "interior")
    rb.box(mx0 + 0.05, yb + 0.30, FL1 + 0.015, mx0 + 0.09, Y0 - 0.20, FL1 + 0.035)
    rb.done(array=(int((mx1 - mx0 - 0.1) / 0.08), (0.08, 0, 0)))
    doormat_marker("vest", mx0, yb + 0.25, mx1, Y0 - 0.15, FL1)
    # 自販機は組まない。ゲームが目印 slot_vending_4・5（自動ドアの左右）に props/ の自販機を置く
    lp = M("vest_lamp", "paper", "interior")
    lp.cyl((cx, (yb + Y0) / 2, V["h"] - 0.95), (cx, (yb + Y0) / 2, V["h"] - 0.45), 0.32, seg=24)
    lp.done(smooth=True)
    cd = M("vest_lamp_cord", "dark", "interior")
    cd.cyl((cx, (yb + Y0) / 2, V["h"] - 0.45), (cx, (yb + Y0) / 2, V["h"]), 0.008, seg=6)
    cd.done()



def doormat_marker(name, x0, y0, x1, y1, z):
    """マットの目印 doormat_<name>: 真ん中の床の上。拡大（x, y）がマットの半分の大きさ。ゲームの audio.gd が足音に使う"""
    e = bpy.data.objects.new("doormat_" + name, None)
    e.empty_display_type = "CUBE"
    e.empty_display_size = 1.0
    e.location = ((x0 + x1) / 2, (y0 + y1) / 2, z)
    e.scale = ((x1 - x0) / 2, (y1 - y0) / 2, 1.0)
    coll("markers").objects.link(e)


def build_doormats():
    """出入り口の内と外のマット（dims.DOORMATS）。外は目の粗い棕櫚に濃い縁の帯、中は裂き織りに両端の房。
    床に置くだけ（当たり判定なし）"""
    t = DOORMAT_T
    for name, kind, x0, y0, x1, y1, z in DOORMATS:
        if kind == "out":
            b = 0.065   # 縁の帯（棕櫚の目を包む濃い布）
            body = M("doormat_body_" + name, "mat_out", "crown")
            body.box(x0 + b, y0 + b, z, x1 - b, y1 - b, z + t)
            body.done(bevel=0.003)
            ed = M("doormat_edge_" + name, "mat_out_edge", "crown")
            for q in ((x0, y0, x1, y0 + b), (x0, y1 - b, x1, y1), (x0, y0 + b, x0 + b, y1 - b), (x1 - b, y0 + b, x1, y1 - b)):
                ed.box(q[0], q[1], z, q[2], q[3], z + t + 0.002)
            ed.done(bevel=0.004)
        else:
            body = M("doormat_body_" + name, "mat_in", "interior")
            body.box(x0, y0, z, x1, y1, z + t)
            body.done(bevel=0.004)
            # 房: 短い 2 辺から、たて糸の束を床に垂らす
            fr = M("doormat_fringe_" + name, "mat_fringe", "interior")
            gap, ln, w = 0.045, 0.07, 0.014
            if x1 - x0 >= y1 - y0:   # 長い辺が x: 房は西と東の端
                n = int((y1 - y0 - 0.04) / gap)
                for xa, xb in ((x0 - ln, x0), (x1, x1 + ln)):
                    fr.box(xa, y0 + 0.02, z, xb, y0 + 0.02 + w, z + 0.004)
            else:
                n = int((x1 - x0 - 0.04) / gap)
                for ya, yb_ in ((y0 - ln, y0), (y1, y1 + ln)):
                    fr.box(x0 + 0.02, ya, z, x0 + 0.02 + w, yb_, z + 0.004)
            off = (0, gap, 0) if x1 - x0 >= y1 - y0 else (gap, 0, 0)
            fr.done(array=(n + 1, off))
        doormat_marker(name, x0, y0, x1, y1, z)


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
    rail_run(Rm, (X0 + 0.07, Y0 + 0.07, zt), (ESTAIR["x0"], Y0 + 0.07, zt), name="bal_terrace_sw")   # 外階段の所は空ける
    rail_run(Rm, (ESTAIR["x1"], Y0 + 0.07, zt), (X1 - 0.07, Y0 + 0.07, zt), name="bal_terrace_s")
    rail_run(Rm, (X1 - 0.07, Y0 + 0.07, zt), (X1 - 0.07, Y2_0 - R - 0.02, zt), name="bal_terrace_e")
    # テラスは南と西の端の L 字（2026-11-03 代表「外からの入口がつながってる木板床のスペースをごっそり外にしてテラス化」）。
    # 西と北の縁にも手すり。北の手すりは 2 階の西の壁（X2_0）の外の面まで
    rail_run(Rm, (X0 + 0.07, Y0 + 0.07, zt), (X0 + 0.07, Y1 - 0.07, zt), name="bal_terrace_w")
    rail_run(Rm, (X0 + 0.07, Y1 - 0.07, zt), (X2_0 - R - 0.02, Y1 - 0.07, zt), name="bal_terrace_n")
    # テラスの床板（南の帯は東西いっぱい、西の端は 2 階の西の壁の外の面まで）
    tb = M("terrace_boards", "deck", "crown")
    n = int((Y2_0 - R - Y0) / 0.15)
    tb.box(X0, Y0 - 0.02, FL2, X1, Y0 + 0.13, FL2 + 0.03)
    tb.done(bevel=0.008, array=(n, (0, 0.15, 0)))
    y0w = Y0 + n * 0.15
    tw_ = M("terrace_boards_w", "deck", "crown")
    tw_.box(X0, y0w - 0.02, FL2, X2_0 - R, y0w + 0.13, FL2 + 0.03)
    tw_.done(bevel=0.008, array=(int((Y1 + 0.09 - y0w) / 0.15), (0, 0.15, 0)))
    # 外階段: 玄関前の広場から北へまっすぐ上り、踊り場を挟んでテラスの南の縁に着く
    E = ESTAIR
    T = M("stair_treads", "tread", "crown")   # 段板・踊り場・ミニテラス（Godot では板が東西に通る）
    S = M("stair_frame", "post", "crown")
    ri, tr = E["rise"], E["tread"]
    xa, xb = E["x0"], E["x1"]
    n1, n2 = E["n1"], E["risers"] - E["n1"]
    for ys, z0, n in ((E["y_foot"], FL1, n1), (E["y_land1"], E["z_land"], n2)):
        for k in range(1, n):
            z = z0 + k * ri
            y0_, y1_ = ys + (k - 1) * tr, ys + k * tr
            if z0 == FL1 and k <= E["flare"]:   # 登り口の段は左右に広げ、広場から三方で踏み込める
                w = 0.3 * (E["flare"] - k + 1)
                T.box(xa - w, y0_ - 0.03 * (k == 1), FL1, xb + w, y1_, z)
            else:
                T.box(xa + 0.06, y0_ - 0.03, z - 0.05, xb - 0.06, y1_, z)
        ye, ze = ys + (n - 1) * tr, z0 + n * ri
        yb_ = ys + E["flare"] * tr if z0 == FL1 else ys
        zb_ = z0 + (E["flare"] * ri if z0 == FL1 else 0.0)
        for x in (xa + 0.03, xb - 0.03):   # 側桁
            S.beam((x, yb_ - 0.05, zb_ - 0.02), (x, ye + 0.05, ze - 0.02), 0.06, 0.30)
            rail_run(Rm, (x + (0.02 if x < (xa + xb) / 2 else -0.02), yb_, zb_ + ri), (x + (0.02 if x < (xa + xb) / 2 else -0.02), ye, ze),
                     h=1.0, posts_every=3, name="bal_stair_%d_%s" % (round(z0 * 10), "w" if x < (xa + xb) / 2 else "e"))
    yl0, yl1 = E["y_land0"], E["y_land1"]
    T.box(xa, yl0, E["z_land"] - 0.12, xb, yl1, E["z_land"])                 # 踊り場
    h = 0.16   # 柱の半幅（2026-11-03 代表「柱の半径を倍に」で 0.08 → 0.16。外の面は踊り場の縁にそろえたまま）
    for x in (xa + h, xb - h):
        for y in (yl0 + h, yl1 - h):
            S.box(x - h, y - h, 0, x + h, y + h, E["z_land"] - 0.12)
        S.box(x - h, (yl1 + E["y_top"]) / 2 - h, 0, x + h, (yl1 + E["y_top"]) / 2 + h,
              (E["z_land"] + FL2) / 2 - 0.3)                                  # 2 本目の中ほどの柱
    rail_run(Rm, (xb - 0.05, yl0, E["z_land"]), (xb - 0.05, yl1, E["z_land"]), h=1.0, name="bal_landing_e")
    # 踊り場の西のミニテラス（踊り場と一続きの床）。手すりで囲む（自販機 2 台はゲームが西の手すりを背に置く）
    Mi = MINI
    zt_ = Mi["z"]
    T.box(Mi["x0"], Mi["y0"], zt_ - 0.12, Mi["x1"], Mi["y1"], zt_)
    S.box(Mi["x0"], Mi["y0"], zt_ - 0.40, Mi["x1"], Mi["y0"] + 0.12, zt_ - 0.12)     # 縁の梁
    S.box(Mi["x0"], Mi["y1"] - 0.12, zt_ - 0.40, Mi["x1"], Mi["y1"], zt_ - 0.12)
    S.box(Mi["x0"], Mi["y0"], zt_ - 0.40, Mi["x0"] + 0.12, Mi["y1"], zt_ - 0.12)
    h = 0.18   # 0.09 → 0.18（同じく倍）
    for x in (Mi["x0"] + h + 0.01, (Mi["x0"] + Mi["x1"]) / 2):
        for y in (Mi["y0"] + h + 0.01, Mi["y1"] - h - 0.01):
            S.box(x - h, y - h, 0, x + h, y + h, zt_ - 0.40)
    rail_run(Rm, (Mi["x0"] + 0.05, Mi["y0"] + 0.05, zt_), (Mi["x1"], Mi["y0"] + 0.05, zt_), h=1.0, name="bal_mini_s")
    rail_run(Rm, (Mi["x0"] + 0.05, Mi["y1"] - 0.05, zt_), (Mi["x1"], Mi["y1"] - 0.05, zt_), h=1.0, name="bal_mini_n")
    rail_run(Rm, (Mi["x0"] + 0.05, Mi["y0"] + 0.05, zt_), (Mi["x0"] + 0.05, Mi["y1"] - 0.05, zt_), h=1.0, name="bal_mini_w")
    rail_run(Rm, (xa - 0.05, Mi["y0"] + 0.05, zt_), (xa - 0.05, yl0, zt_), h=1.0, name="bal_mini_es")   # 階段との境
    rail_run(Rm, (xa - 0.05, yl1, zt_), (xa - 0.05, Mi["y1"] - 0.05, zt_), h=1.0, name="bal_mini_en")
    # 自販機は組まない。ゲームが目印 slot_vending_6・7（西の手すりを背に）に props/ の自販機を置く
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


def build_terrace_set():
    """2 階のテラスの卓と椅子（2026-11-03 代表「二階テラスにテーブルと椅子を配置してほしい」）。外に置く物なので、
    木の卓と椅子に雪を少しかぶせる（天板の北の端と角、椅子の背の上の桟）。座布団はフェルト（素材 cushion。
    game/seats.gd が 1 階の椅子と同じく席として見つけ、卓の当たり（col_furniture）で向きを決める）。
    椅子の形と高さは 1 階の食堂の椅子にそろえる（座る姿勢は doll.gd の _sit_chair）。背は板 1 枚でなく横桟 2 本"""
    T_, C_ = TERRACE_TABLE, TERRACE_CHAIR
    w, d, h = T_["w"], T_["d"], T_["h"]
    lx, ly = w / 2 - 0.10, d / 2 - 0.12          # 脚の芯
    tm = M("terrace_table_src", "board", "interior")
    tm.box(-w / 2, -d / 2, h - 0.06, w / 2, d / 2, h)                       # 厚い天板
    for sx in (-1, 1):
        for sy in (-1, 1):
            tm.box(sx * lx - 0.045, sy * ly - 0.045, 0, sx * lx + 0.045, sy * ly + 0.045, h - 0.06)
        tm.box(sx * lx - 0.02, -ly, h - 0.16, sx * lx + 0.02, ly, h - 0.06)   # 幕板（長い辺）
        tm.box(sx * lx - 0.025, -ly, 0.12, sx * lx + 0.025, ly, 0.18)         # 貫（長い辺の下）
    tm.box(-lx, -0.03, 0.12, lx, 0.03, 0.18)                                # 貫（真ん中を東西に）
    tsrc = tm.done(bevel=0.012)
    ts = M("terrace_table_snow_src", "snow", "interior")                   # 天板の北の端に積もった雪と、南の角のひとかたまり
    ts.box(-w / 2 + 0.04, d / 2 - 0.58, h - 0.005, w / 2 - 0.03, d / 2 - 0.02, h + 0.035)
    ts.box(-w / 2 + 0.06, -d / 2 + 0.05, h - 0.005, -w / 2 + 0.30, -d / 2 + 0.26, h + 0.03)
    tssrc = ts.done(bevel=0.018, seg=3, smooth=True)
    ch = M("terrace_chair_src", "board", "interior")                       # 正面は -y、背は +y
    ch.box(-0.22, -0.21, 0.43, 0.22, 0.21, 0.47)                            # 座板
    for sx in (-0.18, 0.18):
        ch.box(sx - 0.022, -0.19, 0, sx + 0.022, -0.15, 0.43)              # 前の脚
        ch.box(sx - 0.022, 0.16, 0, sx + 0.022, 0.205, 0.92)               # 後ろの脚（背の柱まで通す）
    for z0, z1 in ((0.60, 0.68), (0.80, 0.88)):
        ch.box(-0.20, 0.165, z0, 0.20, 0.200, z1)                           # 背の横桟
    ch.box(-0.18, -0.02, 0.16, 0.18, 0.02, 0.20)                            # 貫
    csrc = ch.done(bevel=0.008)
    cu = M("terrace_cushion_src", "cushion", "interior")
    cu.box(-0.20, -0.19, 0.47, 0.20, 0.15, 0.52)
    usrc = cu.done(bevel=0.02, seg=3)
    cs = M("terrace_chair_snow_src", "snow", "interior")                   # 背の上の桟と柱の頭に載った雪
    cs.box(-0.215, 0.158, 0.875, 0.215, 0.208, 0.915)
    cssrc = cs.done(bevel=0.012, seg=3, smooth=True)
    z0 = FL2 + 0.03   # テラスの床板の上
    for k, (cx, cy) in enumerate(TERRACE_TABLES):
        instance(tsrc, "terrace_table_%d" % k, (cx, cy, z0))
        instance(tssrc, "terrace_table_snow_%d" % k, (cx, cy, z0))
        for side, rz in ((-1, math.pi / 2), (1, -math.pi / 2)):   # 西の椅子は東を向く（背が西）、東の椅子は西を向く
            x = cx + side * (w / 2 + C_["gap"])
            for j, dy in enumerate((-C_["along"], C_["along"])):
                tag = "%d_%s%d" % (k, "w" if side < 0 else "e", j)
                instance(csrc, "terrace_chair_" + tag, (x, cy + dy, z0), rz)
                instance(usrc, "terrace_cushion_" + tag, (x, cy + dy, z0), rz)
                instance(cssrc, "terrace_chair_snow_" + tag, (x, cy + dy, z0), rz)
    for src in (tsrc, tssrc, csrc, usrc, cssrc):   # 元の形は書き出さない置き場へ
        coll("interior").objects.unlink(src)
        coll("sources").objects.link(src)
        src.hide_render = True


def build_interior():
    # 1 階の床板（土間でなく木の床。外のデッキと同じ高さ）
    fb = M("floor1", "floor", "interior")
    fb.box(X0 + R, Y0 + 0.05, FL1, X1 - R, Y1 - R, FL1 + 0.02)
    fb.done()
    # 厨房の奥の台（北の壁ぎわ）と貸出の棚（西のガラスの壁の外、下屋）、厨房の前にメニュー板。
    # 間仕切りと前のカウンターは置かない（2026-10-29 代表「ミシンの前の塀を消し」、
    # 2026-10-31 代表「仕切りを無くしたい。ご飯の前の塀も消してほしい」）
    C = M("counters", "board", "interior")
    C.box(BACK["x0"], BACK["y0"], FL1, BACK["x1"], BACK["y1"], FL1 + BACK["h"])
    C.box(RENTAL["x0"], RENTAL["y0"], 0, RENTAL["x1"], RENTAL["y1"], RENTAL["h"])      # 貸出の棚（外の下屋の雪の上）
    for z in (0.5, 1.0, 1.5):   # 棚板の縁（口は西）
        C.box(RENTAL["x0"] - 0.04, RENTAL["y0"] - 0.02, z, RENTAL["x0"], RENTAL["y1"] + 0.02, z + 0.03)
    C.done(bevel=0.012)
    mb = M("menu_board", "felt_green", "interior")   # 色あせたフェルトの案内板（ゲームでは隠し、装置ごとの品書きの板を吊る: game/menu_board.gd）
    mid = (BACK["x0"] + BACK["x1"]) / 2
    for k in (-1, 0, 1):   # 3 枚並べて吊る
        mb.box(mid + k * 1.6 - 0.65, MENU_Y - 0.03, FL1 + 2.6, mid + k * 1.6 + 0.65, MENU_Y + 0.01, FL1 + 3.4)
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
    sm.cyl((0, 0, 0), (0, 0, 0.02), 0.20, seg=12)                       # 台
    sm.cyl((0, 0, 0.02), (0, 0, st["seat"] - 0.06), 0.035, seg=6)        # 柱
    sm.cyl((0, 0, 0.30), (0, 0, 0.33), 0.17, seg=12)                     # 足掛けの輪
    sm.cyl((0, 0, st["seat"] - 0.06), (0, 0, st["seat"] - 0.02), st["r"], seg=16)
    ssrc = sm.done(bevel=0.008, smooth=True)
    sc_ = M("stool_cushion_src", "cushion", "interior")
    sc_.cyl((0, 0, st["seat"] - 0.02), (0, 0, st["seat"] + 0.04), st["r"] - 0.01, seg=16)
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
    # 内階段: 部屋の内側（西）を北へ上り、北の壁際の踊り場で折り返して、東の壁際を南へ上って 2 階に出る
    I = INSTAIR
    st = M("instair", "board", "interior")
    n, n1, tr = I["risers"], I["n1"], I["tread"]
    ri = (FL2 - FL1) / n
    for k in range(1, n1):                       # 1 本目（西）: 北へ
        z = FL1 + k * ri
        y = I["y_bottom"] + (k - 1) * tr
        st.box(I["x0"], y - 0.03, z - 0.05, I["xm"], y + tr, z)
    st.box(I["x0"], I["y_land"], I["z_land"] - 0.15, I["x1"], I["y_top"], I["z_land"])   # 踊り場
    for k in range(1, n - n1):                   # 2 本目（東）: 南へ
        z = I["z_land"] + k * ri
        y = I["y_land"] - k * tr
        st.box(I["xm"], y, z - 0.05, I["x1"], y + tr + 0.03, z)
    st.beam((I["x0"] + 0.03, I["y_bottom"] - 0.05, FL1 + 0.05), (I["x0"] + 0.03, I["y_land"], I["z_land"] - 0.05), 0.06, 0.3)
    st.beam((I["xm"] - 0.03, I["y_bottom"] - 0.05, FL1 + 0.05), (I["xm"] - 0.03, I["y_land"], I["z_land"] - 0.05), 0.06, 0.3)
    st.beam((I["xm"] + 0.03, I["y_land"], I["z_land"] + 0.05), (I["xm"] + 0.03, I["hole_y0"], FL2 - 0.05), 0.06, 0.3)
    # 踊り場の柱は 2026-11-03 に 0.12 角 → 0.24 角（代表「柱の半径を倍に」）
    st.box(I["x0"], I["y_top"] - 0.34, FL1, I["x0"] + 0.24, I["y_top"] - 0.10, I["z_land"] - 0.15)   # 踊り場の柱（北西の角）
    st.box(I["x0"], I["y_land"] + 0.10, FL1, I["x0"] + 0.24, I["y_land"] + 0.34, I["z_land"] - 0.15)   # 踊り場の柱（南西の角）
    st.done(bevel=0.01)
    # 2 本目の下（東の壁際）は板で塞ぐ。1 本目の脇から 2 本目の裏へ入り込まないように
    sp = M("instair_panel", "board", "interior")
    sp.prism_x([(I["hole_y0"], FL1), (I["hole_y0"], FL2 - 0.32), (I["y_land"], I["z_land"] - 0.32), (I["y_land"], FL1)],
               I["xm"] + 0.01, I["xm"] + 0.05)
    sp.done(bevel=0.005)
    ir = M("instair_rail", "rail", "interior")
    rail_run(ir, (I["x0"] + 0.04, I["y_bottom"], FL1 + ri), (I["x0"] + 0.04, I["y_land"], I["z_land"]), h=0.9,
             posts_every=5, name="bal_instair_1")
    rail_run(ir, (I["x0"] + 0.04, I["y_land"], I["z_land"]), (I["x0"] + 0.04, I["y_top"], I["z_land"]), h=0.9,
             name="bal_instair_land")
    rail_run(ir, (I["xm"] + 0.04, I["y_land"], I["z_land"]), (I["xm"] + 0.04, I["hole_y0"], FL2), h=0.9,
             posts_every=5, name="bal_instair_2")
    rail_run(ir, (I["x0"] - 0.05, I["hole_y0"], FL2), (I["x0"] - 0.05, I["y_top"], FL2), h=RAIL_H,
             name="bal_stairwell_w")
    rail_run(ir, (I["x0"] - 0.05, I["hole_y0"], FL2), (I["xm"], I["hole_y0"], FL2), h=RAIL_H,   # 2 本目の上がり口（東）は空ける
             name="bal_stairwell_s")
    ir.done(bevel=0.01)
    # 1 階の吊り灯り（卓の上）。2 階のこたつの上の灯りは game/main.gd が目印 slot_pendant_<番号>（天井）に吊る
    lp = M("lamps", "paper", "interior")
    for x, y in TABLES:
        for j in (0.25, 0.75):
            cx, cy = x + tw * j, y + td / 2
            lp.cyl((cx, cy, CEIL1 - 0.9), (cx, cy, CEIL1 - 0.55), 0.22, seg=20)
    lp.done(bevel=0.03, seg=3, smooth=True)
    for i, (x, ky) in enumerate(KOTATSU):
        e = bpy.data.objects.new("slot_pendant_%d" % i, None)
        e.empty_display_type = "SPHERE"
        e.empty_display_size = 0.2
        e.location = (x + KOTATSU_W / 2, ky + KOTATSU_D / 2, roof_z(ky + KOTATSU_D / 2) + RAFTER["h"] - 0.025)   # 野地板の下面
        coll("markers").objects.link(e)
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
        pits.append((x - PIT_OUT, ky0 - PIT_OUT, x + KOTATSU_W + PIT_OUT, ky1 + PIT_OUT))
        cut(plo, cutter("cut_pit_%d" % i, *pits[-1][:2], zt - PIT_DEPTH, *pits[-1][2:], zt + 0.1))
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
    # こたつ（卓・布団・天板）と座布団は、ゲームが props の場面を置く（props/build_room.py の kotatsu_lodge）。
    # ここは置き場の目印だけ: 穴のまんなか、畳の面
    for i, (x, ky0) in enumerate(KOTATSU):
        e = bpy.data.objects.new("slot_kotatsu_%d" % i, None)
        e.empty_display_type = "CUBE"
        e.empty_display_size = 0.4
        e.location = (x + KOTATSU_W / 2, ky0 + KOTATSU_D / 2, zt)
        coll("markers").objects.link(e)
    build_terrace_set()
    b2 = M("bench2", "board", "interior")
    b2.box(TATAMI["x1"] + 0.10, INSTAIR["hole_y0"] - 1.9, FL2, TATAMI["x1"] + 0.45, INSTAIR["hole_y0"] - 0.4, FL2 + 0.9)   # 下足箱（畳の東の縁）。西の端の長椅子と卓はテラスへ（build_terrace_set）
    b2.done(bevel=0.012)
    build_doormats()

    # ---- 下屋: 腰掛け（スキー立ては 2026-11-04 代表「邪魔だから全撤去」でなくした）----
    bn = M("rental_benches", "board", "setsue")
    for j in range(3):
        y0 = gy(6.7) + j * 0.4
        bn.box(gx(-1.4), y0, 0, gx(-0.6), y0 + 0.3, 0.42)
    bn.done(bevel=0.012)
    # 機械の置き場: 空の目印。向きは目印の回転（ゲームは目印の +Z 側＝向きの側へ機械の正面を向ける）
    for name, (x, y, z, rot) in SLOTS.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "CUBE"
        e.empty_display_size = 0.4
        e.location = (x, y, z)
        e.rotation_euler = (0, 0, math.radians(rot))
        coll("markers").objects.link(e)
    # 灯りの場所の目印。glTF の灯りは明るさの単位が合わないので、ゲームの側で灯りを置く
    # 灯りは少なく（スマホでも動くように）: 食堂は炉と天井の 3 つの計 4 つ、座敷は 2 つ、風除室に 1 つ。影はなし
    lights = [("light_lamp_%d" % i, (x, y, CEIL1 - 1.0)) for i, (x, y) in enumerate(LAMPS)]
    ky = (KOTATSU[0][1] + KOTATSU[-1][1] + KOTATSU_D) / 2
    lights += [("light_lantern_%d" % i, ((KOTATSU[a][0] + KOTATSU[a + 1][0] + KOTATSU_W) / 2, ky, FL2 + TATAMI["h"] + KOTATSU_LAMP - 0.3))
               for i, a in enumerate((0, 2))]
    lights.append(("light_fire", (HEARTH_CX, HEARTH["front"] + 0.3, FL1 + 0.95)))   # 大きな暖炉の炉の口の前（props/build_nook.py）
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
        point("lantern_2f", (x + KOTATSU_W / 2, ky + KOTATSU_D / 2, FL2 + TATAMI["h"] + KOTATSU_LAMP - 0.3), 70 * k, warm, 0.25)
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
    "in2": ((X2_0 + 0.9, gy(4.4), FL2 + 1.55), (gx(10.5), gy(2.4), FL2 + 0.55), 22),   # 西の壁の内の板の通り道から
    "kotatsu": ((gx(5.3), gy(1.2), FL2 + TATAMI["h"] + 1.05), (gx(3.0), Y0 - 8, FL2 + 1.6), 24),
    "mini": ((ESTAIR["x1"] + 0.3, MINI["y0"] + 0.4, MINI["z"] + 1.6), (MINI["x0"], (MINI["y0"] + MINI["y1"]) / 2, MINI["z"] + 0.8), 26),
    "plaza": ((VEST["cx"] - 4, PLAZA["y0"] - 12, 4.5), (ESTAIR["x0"] + 1.5, ESTAIR["y_land0"] - 1, 2.0), 32),
    "entrance": ((VEST["cx"] - 9, Y0 - VEST["d"] - 13, 3.2), (VEST["cx"], Y0 - VEST["d"], 2.8), 30),
    "vest_in": ((VEST["cx"] + 2.6, Y0 - VEST["d"] + 0.8, FL1 + 1.6), (VEST["x0"] + 0.8, Y0 - 0.4, FL1 + 1.0), 22),
    "stair1": ((gx(8.2), gy(3.2), FL1 + 1.6), (INSTAIR["x0"] + 1.2, INSTAIR["y_land"], 2.6), 24),
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
    """箱と坂の当たり判定（食堂の丸柱だけ円柱）。名前の -colonly で、Godot は見た目なしの当たり判定として読み込む。
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
    P = PLAZA                                                                 # 玄関前の広場と、外まわりの段（坂）
    F.box(P["x0"], P["y0"], 0, P["x1"], P["y1"], FL1)
    F.box(P["x0"], P["y1"], 0, V["x0"], DECK["y0"], FL1)
    F.box(V["x1"], P["y1"], 0, P["x1"], DECK["y0"], FL1)
    run = P["steps"] * P["tread"]
    ramp_y(St, P["x0"], P["x1"], P["y0"] - run, 0, P["y0"], FL1)
    for xa_, xb_ in ((P["x0"] - run, P["x0"]), (P["x1"] + run, P["x1"])):
        prof = [(xa_, -0.25), (xb_, FL1 - 0.25), (xb_, FL1), (xa_, 0.0)]
        St.prism_y(prof if xa_ < xb_ else prof[::-1], P["y0"], DECK["y0"])
        # 南の角: 見た目の段は角を回り込む（入れ子の箱）ので、角は南の坂と横の坂の低いほう。
        # 前は南の坂を角まで延ばしていて、角に見えない背（最大 0.25 m）ができ、つまずいていた
        corner = [(xb_, P["y0"], FL1), (xa_, P["y0"], 0.0), (xb_, P["y0"] - run, 0.0), (xa_, P["y0"] - run, 0.0)]
        St.hull([(x, y, z) for x, y, z in corner] + [(x, y, z - 0.25) for x, y, z in corner])
    # 前のデッキの東の 2 段（0.30 m ずつ）も坂に。広場の段と同じく段鼻を通す（足音は坂の下の雪の帯を雪にする。game/audio.gd）
    xa_, xb_ = D_["x1"] + 0.90, D_["x1"]
    St.prism_y([(xa_, -0.25), (xb_, FL1 - 0.25), (xb_, FL1), (xa_, 0.0)][::-1], D_["y0"], D_["y1"])
    Wl.box(V["x0"], y0v + V["t"], FL1, V["x0"] + V["t"], Y0, V["h"])        # 両脇の壁（溝の格子は床として歩ける）
    Wl.box(V["x1"] - V["t"], y0v + V["t"], FL1, V["x1"], Y0, V["h"])
    wall(Wl, "x", y0v + V["t"] / 2, V["x0"], V["x1"], FL1, V["h"],
         [(cx - A_["r"], cx + A_["r"], A_["spring"] + A_["r"] * 0.7)], t=V["t"])   # 丸太の壁
    for sgn in (-1, 1):                                                      # 開いたアーチ戸
        h0 = cx + sgn * A_["r"]
        Wl.box(min(h0, h0 + sgn * A_["r"]), y0v - 0.14, FL1, max(h0, h0 + sgn * A_["r"]), y0v, A_["spring"])
    Rf.box(V["x0"] - V["roof_out"], y0v - V["roof_out"], V["h"], V["x1"] + V["roof_out"], Y0, V["h"] + 0.36)
    # 2 階の壁（西の壁のテラスへの戸を抜く）。妻は屋根の勾配まで
    c2 = [c for c, k in OPENINGS["2F_W"] if k == "door2"][0]
    wall(Wl, "x", Y2_0, X2_0, X1, FL2, EAVE_S)
    wall(Wl, "x", Y1, X2_0, X1, FL2, EAVE_N)
    wall(Wl, "y", X2_0, Y2_0, Y1, FL2, EAVE_N, [(c2 - DOOR2["w"] / 2, c2 + DOOR2["w"] / 2, FL2 + DOOR2["h"])])
    Wl.solid([(X2_0 - R, Y2_0, EAVE_N - 0.05), (X2_0 + R, Y2_0, EAVE_N - 0.05), (X2_0 + R, Y1, EAVE_N - 0.05),
              (X2_0 - R, Y1, EAVE_N - 0.05)],
             [(X2_0 - R, Y2_0, roof_z(Y2_0)), (X2_0 + R, Y2_0, roof_z(Y2_0)), (X2_0 + R, Y1, roof_z(Y1)),
              (X2_0 - R, Y1, roof_z(Y1))])
    for x in (X1,):
        Wl.solid([(x - R, Y2_0, FL2), (x + R, Y2_0, FL2), (x + R, Y1, FL2), (x - R, Y1, FL2)],
                 [(x - R, Y2_0, roof_z(Y2_0)), (x + R, Y2_0, roof_z(Y2_0)), (x + R, Y1, roof_z(Y1)), (x - R, Y1, roof_z(Y1))])
    for x, y in COLS:   # 丸柱は丸いまま（径 1 m の箱だと、柱のない角に当たる）
        Wl.cyl((x, y, FL1), (x, y, FL2), COL_D / 2, seg=12)
        Wl.cyl((x, y, FL2), (x, y, roof_z(y)), COL_D / 2 * 0.85, seg=12)
    # 煙突と炉
    c = CH
    Wl.box(c["x0"], Y1 - LOG_D / 2 - 0.02, 0, c["x1"], c["y1"], FL2)   # 部屋の側の暖炉の当たりは game/hearth_nook.gd
    Wl.box(c["ux0"], c["uy0"], FL2, c["ux1"], c["uy1"], c["top"] + 0.56)
    # 屋根（雪まで含めた厚み）と下屋の屋根
    ys, yn = Y2_0 - EAVE_OUT_S, Y2_1 + EAVE_OUT_N
    tv = (RAFTER["h"] + ROOF_T + SNOW_T) / math.cos(math.atan(ROOF_PITCH))
    Rf.prism_x([(ys, roof_z(ys)), (yn, roof_z(yn)), (yn, roof_z(yn) + tv), (ys, roof_z(ys) + tv)][::-1],
               X2_0 - VERGE_OUT, X1 + VERGE_OUT)
    L = LEAN
    Rf.prism_y([(L["x_out"], L["z_out"]), (X0, L["z_wall"]), (X0, L["z_wall"] + 0.4), (L["x_out"], L["z_out"] + 0.4)],
               L["y0"], L["y1"])
    for y in L["posts"]:
        Wl.box(L["x_post"] - L["post"] / 2, y - L["post"] / 2, 0, L["x_post"] + L["post"] / 2, y + L["post"] / 2, L["z_out"])
    # 手すり（テラス・外階段・吹き抜け）
    for b in ((X0, Y0, FL2, ESTAIR["x0"], Y0 + 0.12, FL2 + RAIL_H), (ESTAIR["x1"], Y0, FL2, X1, Y0 + 0.12, FL2 + RAIL_H),
              (X1 - 0.12, Y0, FL2, X1, Y2_0, FL2 + RAIL_H),
              (X0, Y0, FL2, X0 + 0.12, Y1, FL2 + RAIL_H), (X0, Y1 - 0.12, FL2, X2_0 - R, Y1, FL2 + RAIL_H),
              (hx - 0.1, hy, FL2, hx, Y1, FL2 + RAIL_H), (hx - 0.1, hy - 0.1, FL2, I["xm"], hy, FL2 + RAIL_H)):
        Wl.box(*b)
    # 階段は坂にする（外階段 2 本と踊り場、内階段、デッキの東の段）
    E = ESTAIR
    # 坂は 1 段手前で上の床の高さに届かせ、縁まで平らにつなぐ（縁の角に足もとが引っかからないように）
    ramp_y(St, E["x0"], E["x1"], E["y_foot"], FL1, E["y_land0"] - E["tread"], E["z_land"])
    St.box(E["x0"], E["y_land0"] - E["tread"], E["z_land"] - 0.25, E["x1"], E["y_land0"] + 0.05, E["z_land"])
    fw_ = 0.3 * E["flare"]
    ramp_y(St, E["x0"] - fw_, E["x1"] + fw_, E["y_foot"], FL1, E["y_foot"] + E["flare"] * E["tread"],
           FL1 + E["flare"] * E["rise"])                                       # 広げた登り口
    ramp_y(St, E["x0"], E["x1"], E["y_land1"], E["z_land"], E["y_top"] - E["tread"], FL2)
    St.box(E["x0"], E["y_top"] - E["tread"], FL2 - 0.25, E["x1"], Y0 + 0.3, FL2)
    St.box(E["x0"], E["y_land0"], E["z_land"] - 0.15, E["x1"], E["y_land1"], E["z_land"])
    St.box(E["x1"] - 0.08, E["y_land0"], E["z_land"], E["x1"], E["y_land1"], E["z_land"] + 1.0)   # 踊り場の東の手すり
    Mi = MINI                                                                  # ミニテラスの床・手すり
    St.box(Mi["x0"], Mi["y0"], Mi["z"] - 0.15, Mi["x1"], Mi["y1"], Mi["z"])
    for b in ((Mi["x0"], Mi["y0"], Mi["x1"], Mi["y0"] + 0.08), (Mi["x0"], Mi["y1"] - 0.08, Mi["x1"], Mi["y1"]),
              (Mi["x0"], Mi["y0"], Mi["x0"] + 0.08, Mi["y1"]),
              (Mi["x1"] - 0.08, Mi["y0"], Mi["x1"], E["y_land0"]), (Mi["x1"] - 0.08, E["y_land1"], Mi["x1"], Mi["y1"])):
        St.box(b[0], b[1], Mi["z"], b[2], b[3], Mi["z"] + 1.0)
    # 内階段: 1 本目（西）は北へ、踊り場、2 本目（東）は南へ。外階段と同じく、坂は 1 段手前で上の床の高さに届かせる
    ri_ = (FL2 - FL1) / I["risers"]
    ramp_y(St, I["x0"], I["xm"], I["y_bottom"] - I["tread"], FL1, I["y_land"] - I["tread"], I["z_land"])
    St.box(I["x0"], I["y_land"] - I["tread"], I["z_land"] - 0.25, I["x1"], I["y_top"], I["z_land"])
    ramp_y(St, I["xm"], I["x1"], I["y_land"], I["z_land"], I["hole_y0"] + I["tread"], FL2)
    St.box(I["xm"], I["hole_y0"] - 0.05, FL2 - 0.25, I["x1"], I["hole_y0"] + I["tread"], FL2)
    Wl.box(I["xm"] - 0.04, I["hole_y0"], FL1, I["xm"] + 0.06, I["y_land"] - I["tread"], FL2 + 1.0)   # 2 本の間（2 本目の下の板と手すり）
    ramp_y(Wl, I["x0"] - 0.04, I["x0"] + 0.04, I["y_bottom"] + I["tread"], FL1 + 2 * ri_ + 1.0, I["y_land"] - I["tread"],
           I["z_land"] + 1.0, t=1.0)                                               # 1 本目の西の手すり
    Wl.box(I["x0"] - 0.04, I["y_land"] - I["tread"], I["z_land"], I["x0"] + 0.04, I["y_top"], I["z_land"] + 1.0)   # 踊り場の西の手すり
    St.prism_y([(D_["x1"], D_["z"]), (D_["x1"] + 0.6, 0.0), (D_["x1"], 0.0)][::-1], D_["y0"], D_["y1"])
    # 家具（座れる・ぶつかるもの）
    for x, y in TABLES:
        Fu.box(x, y, FL1, x + TABLE["w"], y + TABLE["d"], FL1 + TABLE["h"])
    # 前のカウンター（貸出・レジ）はない
    Fu.box(BACK["x0"], BACK["y0"], FL1, BACK["x1"], BACK["y1"], FL1 + BACK["h"])
    Fu.box(WINDOW_BAR["x0"], WINDOW_BAR["y0"], FL1, WINDOW_BAR["x1"], WINDOW_BAR["y0"] + WINDOW_BAR["d"],
           FL1 + WINDOW_BAR["h"])
    Fu.box(RENTAL["x0"], RENTAL["y0"], 0, RENTAL["x1"], RENTAL["y1"], RENTAL["h"])   # 貸出の棚（外の下屋）
    # 暖炉とまわりの家具の当たりは、ゲーム（game/hearth_nook.gd）が品物に合わせて置く
    zt = FL2 + TATAMI["h"]
    for x, ky in KOTATSU:   # こたつ: 天板と、穴へ垂れた布団（props の kotatsu_lodge）の外形
        Fu.box(x - KOTATSU_FLARE, ky - KOTATSU_FLARE, zt, x + KOTATSU_W + KOTATSU_FLARE, ky + KOTATSU_D + KOTATSU_FLARE,
               zt + KOTATSU_TOP)
    zd = FL2 + 0.03   # テラスの卓（椅子は 1 階の椅子と同じく当たりなし。卓の当たりで game/seats.gd が椅子の向きを決める）
    for cx, cy in TERRACE_TABLES:
        T_ = TERRACE_TABLE
        Fu.box(cx - T_["w"] / 2, cy - T_["d"] / 2, zd, cx + T_["w"] / 2, cy + T_["d"] / 2, zd + T_["h"])
    for m in groups.values():
        bmesh.ops.recalc_face_normals(m.bm, faces=m.bm.faces)
    return [m.done() for m in groups.values()]


def lighten(objs):
    """ゲーム向けに軽くする（目安: ロッジ全体で三角形 10 万以下）。面取りは外し、形はまとめて 1 つの物体に（描く回数を素材の数まで減らす）。
    建物と中の小物は分けて 2 つに。ゲームが名前で動かす物（自動ドア）と、目印（空の節点）はそのまま残す"""
    meshes = [o for o in objs if o.type == "MESH"]
    marks = [o for o in objs if o.type != "MESH"]
    for o in meshes:
        for md in list(o.modifiers):
            if md.type == "BEVEL":        # 面取りはゲームでは外す（三角形が箱の 3〜4 倍になる）
                o.modifiers.remove(md)
        if o.data.users > 1:
            o.data = o.data.copy()
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.convert(target="MESH")      # 面取り・配列・切り抜きを形にする
    moving = [o for o in meshes if o.name.startswith(("autodoor", "swingdoor"))]   # 動く戸は 1 つにまとめない
    # 中の家具と小物（卓・椅子・腰掛け・灯り・自販機・マット…）は別の 1 つ（lodge_props_interior）に。
    # ゲームの 360° 映像は名前に prop を含む物を映さない
    inner = set(o.name for o in bpy.data.collections["interior"].objects) if bpy.data.collections.get("interior") else set()
    props = [o for o in meshes if o not in moving and o.name in inner]
    rest = [o for o in meshes if o not in moving and o not in props]
    out = []
    for group, name in ((rest, "lodge_body"), (props, "lodge_props_interior")):
        if not group:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in group:
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        bpy.ops.object.join()
        one = bpy.context.view_layer.objects.active
        one.name = name
        print("lighten: %s %d objects, %d tris, %d materials" % (name, len(group),
              sum(len(p.vertices) - 2 for p in one.data.polygons), len(one.data.materials)))
        out.append(one)
    return out + moving + marks


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

    objs = [o for c in keep if bpy.data.collections.get(c) for o in bpy.data.collections[c].objects]
    write(lighten(objs), "lodge.glb")
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
