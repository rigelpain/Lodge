"""ロッジの中の小物の台本が使う、共通の組み立て部品（common.py の上に載せる）。

どの台本も「品物ごとに 1 つの根元の節点（空）と部品の列」を made に積み、
描くときは並べて撮り、書き出すときは品物ごとに 1 つの glb にする。
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C

S = {"export": False, "day": True, "scale": 1.0, "tris": 3000}
made = []


def setup(args, fiber=1.0, scale=1.0, tris=3000):
    """fiber: フェルトの繊維の細かさの倍率。手に持つ小物は 4 くらい。
    scale: 書き出すときの大きさの倍率（2026-10-28 代表: 食べ物 1.5 倍、ほか 2 倍）。描く画像は元の大きさのまま。
    書き出しでは素材を描くときと同じに組み（焼き込みの元にする）、毛羽の層は作らない"""
    C.reset()
    C.FIBER["k"] = fiber
    S["export"] = bool(args.export)
    S["scale"] = scale
    S["tris"] = tris
    if S["export"] and not getattr(args, "flat", False):
        C.LOOK["v"] = "day"
        C.NOFUZZ["v"] = True
        S["day"] = False
    else:
        C.LOOK["v"] = args.look
        S["day"] = args.look == "day"


def root(name, **extras):
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
    return e


class Parts:
    """品物ひとつ分の部品箱。素材の役割ごとに 1 つの M を持つ"""

    def __init__(self, name, **extras):
        self.name = name
        self.root = root(name, **extras)
        self.ms = {}
        self.parts = []
        self.hard = {}   # 役割 → 角の丸めの幅。硬い物（箱・板）は角を少しだけ丸め、面は平らに塗る

    def m(self, role):
        if role not in self.ms:
            self.ms[role] = C.M("%s_%s" % (self.name, role), role)
        return self.ms[role]

    def finish(self, fuzz=0.0, cotton_fuzz=0.0):
        for role, m in self.ms.items():
            if not m.bm.verts:
                m.bm.free()
                continue
            if role in self.hard:
                o = m.done(smooth=False, bevel=self.hard[role], seg=3, parent=self.root)
                o.modifiers["bevel"].harden_normals = True
            else:
                o = m.done(parent=self.root)
            self.parts.append(o)
            if S["day"] and fuzz and role.startswith("felt") and role != "felt_heat":
                C.fuzz(o, fuzz, layers=2, hexcol=C.HEX.get(role) or C.LM.HEX.get(role), sheen=0.4)
            if S["day"] and cotton_fuzz and role == "cotton":
                C.fuzz(o, cotton_fuzz)
        made.append((self.root, self.parts))
        return self.root

    def transform(self, mtx):
        """ここまでに組んだ部品をまとめて動かす（立てて組んだ物を寝かせる、など）"""
        for m in self.ms.values():
            for v in m.bm.verts:
                v.co = mtx @ v.co

    def mark(self, name, loc):
        marker(name, loc, self.root, self.parts)


def cuts(hi=9, lo=5):
    return lo if S["export"] else hi


def pbox(P, role, center, half, n=6.0, nz=None, seam_role=None, rot=None, dent=None, c=None):
    """ふっくらしたフェルトの箱。seam_role を決めると横に一周、縫い代の耳を巻きかがる"""
    felt = P.m(role)
    thread = P.m(seam_role) if seam_role else None
    n0 = len(felt.bm.verts)
    t0 = len(thread.bm.verts) if thread else 0
    C.superellipsoid(felt, (0, 0, 0), half, n_xy=n, n_z=nz or n, cuts=c or cuts(), dent=dent)
    if thread is not None:
        a, b, _ = half
        pts, nrm = C.ellipse_ring(a, b, n=n, count=max(16, int(2 * (a + b) * 2 / (0.06 if S["export"] else 0.035))),
                                  z=0.0, inset=0.003)
        sc = min(1.0, max(0.25, (a + b) / 1.2))
        C.seam_whip(felt, thread, pts, nrm, out=0.012 * sc, th=0.006 * sc, r=0.005 * sc, every=2 if S["export"] else 1)
    mtx = Matrix.Translation(center)
    if rot:
        for ang, ax in (rot if isinstance(rot[0], (list, tuple)) else [rot]):
            mtx = mtx @ Matrix.Rotation(ang, 4, ax)
    C.place(felt, n0, mtx)
    if thread is not None:
        C.place(thread, t0, mtx)


def box(P, role, center, size, rot=None):
    m = P.m(role)
    mt = Matrix.Translation(center)
    if rot:
        mt = mt @ Matrix.Rotation(rot[0], 4, rot[1])
    bmesh.ops.create_cube(m.bm, size=1.0, matrix=mt @ Matrix.Diagonal((size[0], size[1], size[2], 1)))


def dowel(P, role, p0, p1, r, sides=12):
    C.tube(P.m(role), [Vector(p0), Vector(p1)], r, sides=sides)


def lathe(P, role, prof, center=(0, 0, 0), segs=32, closed=True, rot=None):
    m = P.m(role)
    n0 = len(m.bm.verts)
    C.lathe(m, prof, segs, closed)
    mt = Matrix.Translation(center)
    if rot:
        mt = mt @ Matrix.Rotation(rot[0], 4, rot[1])
    C.place(m, n0, mt)


def disc(P, role, center, r, thick, axis="Z", segs=32):
    """円板。axis の向きに厚み"""
    rot = {"X": (math.pi / 2, "Y"), "Y": (math.pi / 2, "X"), "Z": None}[axis]
    lathe(P, role, [(r * 0.94, -thick / 2), (r, -thick / 2 + min(0.01, thick * 0.2)), (r, thick / 2 - min(0.01, thick * 0.2)),
                    (r * 0.94, thick / 2)], center, segs, True, rot)


def tube(P, role, pts, r, **kw):
    C.tube(P.m(role), [Vector(p) for p in pts], r, **kw)


def ring(P, role, center, R, r, axis="Z", n=40, z=0.0):
    """輪（糸の巻き、縁の巻き）"""
    c = Vector(center)
    pts = []
    for k in range(n + 1):
        a = 2 * math.pi * k / n
        if axis == "Z":
            pts.append(c + Vector((R * math.cos(a), R * math.sin(a), 0)))
        elif axis == "Y":
            pts.append(c + Vector((R * math.cos(a), 0, R * math.sin(a))))
        else:
            pts.append(c + Vector((0, R * math.cos(a), R * math.sin(a))))
    C.tube(P.m(role), pts, r, sides=6, caps=False)


def stitch_ring(P, role, center, R, r=0.003, axis="Z", dash=None):
    c = Vector(center)
    pts = []
    for k in range(73):
        a = 2 * math.pi * k / 72
        if axis == "Z":
            pts.append(c + Vector((R * math.cos(a), R * math.sin(a), 0)))
        elif axis == "Y":
            pts.append(c + Vector((R * math.cos(a), 0, R * math.sin(a))))
        else:
            pts.append(c + Vector((0, R * math.cos(a), R * math.sin(a))))
    d = dash or max(0.006, R * 0.15)
    C.running_stitch(P.m(role), pts, [Vector()], dash=d, gap=d * 0.65, r=r)


def stitch_line(P, role, pts, r=0.003, dash=0.02):
    C.running_stitch(P.m(role), [Vector(p) for p in pts], [Vector()], dash=dash, gap=dash * 0.65, r=r)


def extrude(P, role, poly, z0, z1, plane="XY", offset=(0, 0, 0), rot=None):
    """多角形を押し出す。plane は多角形の面（XY: 床に寝かせる、XZ: 前に立てる）"""
    m = P.m(role)
    n0 = len(m.bm.verts)

    def v(x, y, z):
        return (x, y, z) if plane == "XY" else (x, z, y)
    vb = [m.bm.verts.new(v(x, y, z0)) for x, y in poly]
    vt = [m.bm.verts.new(v(x, y, z1)) for x, y in poly]
    try:
        m.bm.faces.new(vt)
        m.bm.faces.new(list(reversed(vb)))
    except ValueError:
        pass
    for i in range(len(poly)):
        j = (i + 1) % len(poly)
        m.bm.faces.new((vb[i], vb[j], vt[j], vt[i]))
    mt = Matrix.Translation(offset)
    if rot:
        mt = mt @ Matrix.Rotation(rot[0], 4, rot[1])
    C.place(m, n0, mt)


def blob(P, name, role, balls, res, lumps=0.12, fuzz=0.0):
    """メタボールの綿・湯気・ふくらみ"""
    o = C.metablob("%s_%s" % (P.name, name), role, balls, res * (2.0 if S["export"] else 1.0), P.root, lumps=lumps)
    if S["day"] and fuzz:
        C.fuzz(o, fuzz, hexcol=None if role == "cotton" else (C.HEX.get(role) or C.LM.HEX.get(role)),
               sheen=1.0 if role == "cotton" else 0.4)
    P.parts.append(o)
    return o


def steam(P, center, h, r, seed=0):
    """湯気（描く画像と、ゲームでの煙の大きさの目安）: 上へ広がる柱に、大小の丸いかたまりを房にして重ねる。
    ゲームでは game/props.gd が、この形を隠して煙の粒子に替える"""
    rnd = random.Random(seed)
    balls = []
    levels = 6
    for j in range(levels):
        t = j / (levels - 1)
        cx = Vector(center) + Vector((r * 0.9 * math.sin(t * 3 + seed), r * 0.6 * math.cos(t * 2.5 + seed), h * t))
        R = r * (0.7 + 1.6 * t)
        for k in range(3 + j // 2):
            a = rnd.uniform(0, 2 * math.pi)
            off = Vector((math.cos(a), math.sin(a), rnd.uniform(-0.3, 0.4))) * R * rnd.uniform(0.3, 0.75)
            balls.append((cx + off, R * rnd.uniform(0.55, 0.85)))
    return blob(P, "steam%d" % seed, "cotton", balls, r * 0.1, lumps=0.08, fuzz=r * 0.25)


def circle_poly(r, n=32, cx=0.0, cy=0.0, sx=1.0, sy=1.0):
    return [(cx + r * sx * math.cos(2 * math.pi * k / n), cy + r * sy * math.sin(2 * math.pi * k / n)) for k in range(n)]


def round_rect(w, h, r, n=6):
    """角の丸い長方形（中心 0）"""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# ---------------------------------------------------------------- 並べて描く・書き出す
def interior_light(strength=1.0):
    """ロッジの中: 電球色より少し赤みの灯りと、窓からの青い光"""
    sc = bpy.context.scene
    w = bpy.data.worlds.new("room")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.30, 0.26, 0.22, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    sc.world = w
    warm = (1.0, 0.76, 0.52)
    for (x, y, z, e) in ((-2.0, 2.5, 3.2, 700), (2.5, 3.0, 3.0, 550), (0.0, -0.8, 3.4, 350), (-4.5, 1.0, 2.6, 300),
                         (5.0, 1.5, 2.8, 400)):
        L = bpy.data.objects.new("lamp", bpy.data.lights.new("lamp", "POINT"))
        C.coll("stage").objects.link(L)
        L.location = (x, y, z)
        L.data.energy = e * strength
        L.data.color = warm
        L.data.shadow_soft_size = 0.6
    sun = bpy.data.objects.new("window", bpy.data.lights.new("window", "SUN"))
    C.coll("stage").objects.link(sun)
    sun.data.energy = 1.2
    sun.data.color = (0.75, 0.85, 1.0)
    sun.rotation_euler = (math.radians(60), 0, math.radians(160))


def room(floor_size=12.0, wall_y=-1.5):
    fl = C.M("floor", "floor", "stage")
    bmesh.ops.create_grid(fl.bm, x_segments=2, y_segments=2, size=floor_size)
    fl.done(smooth=False)
    wall = C.M("wall", "felt_beige", "stage")
    bmesh.ops.create_cube(wall.bm, size=1.0, matrix=Matrix.Translation((0, wall_y, 3.0)) @ Matrix.Diagonal((30, 0.1, 6.0, 1)))
    wall.done(smooth=False)


def table(x, y, z, w, d, role="wood"):
    """描くときだけの卓（小物を載せる）"""
    m = C.M("table", role, "stage")
    bmesh.ops.create_cube(m.bm, size=1.0, matrix=Matrix.Translation((x, y, z - 0.02)) @ Matrix.Diagonal((w, d, 0.04, 1)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            C.tube(m, [Vector((x + sx * (w / 2 - 0.05), y + sy * (d / 2 - 0.05), 0)),
                       Vector((x + sx * (w / 2 - 0.05), y + sy * (d / 2 - 0.05), z - 0.04))], 0.025, sides=10)
    m.done(smooth=False)


def grid_place(items, cols, dx, dy, x0=0.0, y0=0.0, z=0.0):
    """品物を格子に並べる。items は根元の節点の列"""
    for i, r in enumerate(items):
        r.location = (x0 + (i % cols) * dx, y0 - (i // cols) * dy, z)


def descendants(r):
    out = []
    for o in bpy.data.objects:
        p = o.parent
        while p is not None:
            if p == r:
                out.append(o)
                break
            p = p.parent
    return out


# ---------------------------------------------------------------- 布の重力
def cloth_grid(name, role, w, d, nu, nv, center, parent=None):
    """垂らす布の元: 細かく割った平らな四角（z を上にして center に置く）"""
    m = C.M(name, role)
    bmesh.ops.create_grid(m.bm, x_segments=nu, y_segments=nv, size=0.5,
                          matrix=Matrix.Translation(center) @ Matrix.Diagonal((w, d, 1, 1)))
    C.plan_uv(m, center[0], center[1])
    o = m.done(smooth=True)
    if parent is not None:
        o.parent = parent
    return o


def cloth_sim(o, colliders=(), frames=40, pressure=0.0, pin=None, mass=0.3, stiff=15.0, bend=0.6, shrink=0.0,
              thickness=0.006, solidify=0.0, subsurf=1):
    """Blender の布の計算で、重力で垂らす・つぶす。colliders は当たる物。pressure は袋を内から押す力（座布団など）。
    pin は動かさない頂点を選ぶ関数 f(位置) → bool。計算のあと形を当てて、厚み（solidify）と丸み（subsurf）を足す"""
    sc = bpy.context.scene
    tmp = []
    for c in colliders:
        md = c.modifiers.new("collision", "COLLISION")
        c.collision.thickness_outer = thickness
        c.collision.cloth_friction = 8.0
        tmp.append(c)
    if pin is not None:
        vg = o.vertex_groups.new(name="pin")
        mw = o.matrix_world
        vg.add([v.index for v in o.data.vertices if pin(mw @ v.co)], 1.0, "REPLACE")
    cl = o.modifiers.new("cloth", "CLOTH")
    st = cl.settings
    st.quality = 10
    st.mass = mass
    st.tension_stiffness = st.compression_stiffness = stiff
    st.shear_stiffness = stiff * 0.5
    st.bending_stiffness = bend
    st.air_damping = 2.0
    if shrink:
        st.shrink_min = shrink
    if pin is not None:
        st.vertex_group_mass = "pin"
    if pressure:
        st.use_pressure = True
        st.uniform_pressure_force = pressure
        st.pressure_factor = 1.0
    cl.collision_settings.distance_min = thickness
    cl.collision_settings.use_self_collision = pressure == 0.0
    cl.collision_settings.self_distance_min = thickness * 0.8
    cl.point_cache.frame_start = 1
    cl.point_cache.frame_end = frames
    sc.frame_start, sc.frame_end = 1, frames
    for f in range(1, frames + 1):
        sc.frame_set(f)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="cloth")
    sc.frame_set(1)
    for c in tmp:
        c.modifiers.remove(c.modifiers["collision"])
    if pin is not None:
        o.vertex_groups.remove(o.vertex_groups["pin"])
    if solidify:
        sd = o.modifiers.new("thick", "SOLIDIFY")
        sd.thickness = solidify
        sd.offset = 1.0
    if subsurf:
        ss = o.modifiers.new("soft", "SUBSURF")
        ss.levels = ss.render_levels = subsurf
    return o


def cushion(P, name, role, center, size, pressure=4.0, pin=None, colliders=(), rot=None, cuts_n=12, frames=30,
            tuft=False):
    """綿を詰めた袋（座布団・座・背のクッション）: 箱を細かく割って、内から押し、重さで沈ませる（布の計算）。
    pin(p) が真の頂点は動かさない（背の後ろを枠に留める、など）。tuft なら真ん中を綴じてくぼませる"""
    m = C.M("%s_%s" % (P.name, name), role)
    mt = Matrix.Translation(center)
    if rot:
        mt = mt @ Matrix.Rotation(rot[0], 4, rot[1])
    ret = bmesh.ops.create_cube(m.bm, size=1.0, matrix=mt @ Matrix.Diagonal((size[0], size[1], size[2], 1)))
    es = list({e for v in ret["verts"] for e in v.link_edges})
    bmesh.ops.subdivide_edges(m.bm, edges=es, cuts=cuts(cuts_n, max(6, cuts_n - 4)), use_grid_fill=True)
    o = m.done(smooth=True)
    c = Vector(center)
    pf = pin
    if tuft:
        pf = (lambda p, pin=pin: (pin(p) if pin else False) or ((p - c).x ** 2 + (p - c).y ** 2) ** 0.5 < min(size[0], size[1]) * 0.06)
    cloth_sim(o, colliders, frames=frames, pressure=pressure, mass=0.25, stiff=12.0, bend=0.25, pin=pf,
              thickness=0.004, subsurf=1)
    o.parent = P.root
    P.parts.append(o)
    return o


def collider_box(center, size):
    """計算のあいだだけ使う、当たる箱（あとで消す）"""
    m = C.M("collider", "felt_charcoal", "stage")
    bmesh.ops.create_cube(m.bm, size=1.0, matrix=Matrix.Translation(center) @ Matrix.Diagonal((size[0], size[1], size[2], 1)))
    o = m.done(smooth=False)
    return o


def drop(o):
    bpy.data.objects.remove(o, do_unlink=True)


# ---------------------------------------------------------------- 焼き込み
BAKE = {"density": 160, "min": 64, "max": 1024, "ready": False}
NO_BAKE = ("thread", "yarn", "hemp", "glass", "paper", "cotton")   # 細い糸・透ける物・光る紙・綿は焼かない（ゲームで質感を重ねる）


def _cycles():
    if BAKE["ready"]:
        return
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type != "CPU"
        sc.cycles.device = "GPU"
        print("cycles devices", [(d.name, d.type, d.use) for d in prefs.devices])
    except Exception as e:   # GPU が使えなければ CPU で焼く
        print("cycles gpu", e)
    sc.cycles.samples = 8
    sc.render.bake.margin = 16
    BAKE["ready"] = True


def _grime(m):
    """焼く素材に、くぼみの陰と使い込んだ汚れを足す: AO で暗く、ゆるい雑音で少しくすむ"""
    t = m.node_tree
    bsdf = next((n for n in t.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return
    inp = bsdf.inputs["Base Color"]
    src = inp.links[0].from_socket if inp.links else None
    base = tuple(inp.default_value)
    ao = t.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.12 * S["scale"]
    ao.samples = 8
    ramp = t.nodes.new("ShaderNodeMapRange")
    ramp.inputs["To Min"].default_value = 0.5
    t.links.new(ao.outputs["AO"], ramp.inputs["Value"])
    noise = t.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.5
    noise.inputs["Detail"].default_value = 4.0
    nmap = t.nodes.new("ShaderNodeMapRange")
    nmap.inputs["From Min"].default_value = 0.45
    nmap.inputs["From Max"].default_value = 0.75
    nmap.inputs["To Min"].default_value = 1.0
    nmap.inputs["To Max"].default_value = 0.86
    t.links.new(noise.outputs["Fac"], nmap.inputs["Value"])
    mul1 = t.nodes.new("ShaderNodeMix")
    mul1.data_type = "RGBA"
    mul1.blend_type = "MULTIPLY"
    mul1.inputs["Factor"].default_value = 1.0
    if src is not None:
        t.links.new(src, mul1.inputs[6])
    else:
        mul1.inputs[6].default_value = base
    comb = t.nodes.new("ShaderNodeMath")
    comb.operation = "MULTIPLY"
    t.links.new(ramp.outputs["Result"], comb.inputs[0])
    t.links.new(nmap.outputs["Result"], comb.inputs[1])
    t.links.new(comb.outputs[0], mul1.inputs[7])
    t.links.new(mul1.outputs[2], inp)


def _bake_object(o, role):
    me = o.data
    area = sum(p.area for p in me.polygons)
    px = int(math.sqrt(max(area, 1e-6)) * BAKE["density"])
    size = BAKE["min"]
    while size < px and size < BAKE["max"]:
        size *= 2
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    cloth_uv = me.uv_layers.get("cloth")   # パッチワークの柄の座標。焼く UV は別に作り、焼いたら捨てる
    if cloth_uv is not None:
        bake_uv = me.uv_layers.new(name="bake")
        me.uv_layers.active = bake_uv
        bake_uv.active_render = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.03)
    bpy.ops.object.mode_set(mode="OBJECT")
    src = o.active_material
    mat = src.copy()
    o.data.materials[0] = mat
    _grime(mat)
    out = {}
    for kind in ("DIFFUSE", "NORMAL"):
        img = bpy.data.images.new("%s_%s_%s" % (o.name, role, kind.lower()), size, size, alpha=False)
        if kind == "NORMAL":
            img.colorspace_settings.name = "Non-Color"
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        mat.node_tree.nodes.active = node
        if kind == "DIFFUSE":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
        else:
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_clear=True)
        img.pack()
        out[kind] = img
    # 焼いた画像だけの素材に替える（名前は役割。Godot が役割で細部を重ねる）
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    tc = m.node_tree.nodes.new("ShaderNodeTexImage")
    tc.image = out["DIFFUSE"]
    m.node_tree.links.new(tc.outputs["Color"], b.inputs["Base Color"])
    tn = m.node_tree.nodes.new("ShaderNodeTexImage")
    tn.image = out["NORMAL"]
    nm = m.node_tree.nodes.new("ShaderNodeNormalMap")
    m.node_tree.links.new(tn.outputs["Color"], nm.inputs["Color"])
    m.node_tree.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.6 if role.startswith(("wood", "pole", "button", "trunk", "floor")) else 0.95
    o.data.materials[0] = m
    if me.uv_layers.get("cloth") is not None:
        me.uv_layers.remove(me.uv_layers["cloth"])


def _flat(o, role):
    """焼かない部品: 役割の名前と色だけの素材にする"""
    hexcol = C.HEX.get(role) or C.LM.HEX.get(role) or "CCCCCC"
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = C.LM.lin(hexcol)
    b.inputs["Roughness"].default_value = 0.9
    o.data.materials[0] = m


GLOW = ("paper",)                                   # 光る紙（灯りの笠）
FIRE = ("fire", "felt_flame")                       # 炎
WOODS = ("wood", "pole", "trunk", "button", "floor")


def group_of(role):
    """軽い形の組（Godot の素材 1 つ＝描画 1 回）。糸は焼くだけ（離れて垂れた糸は felt の組に形を残す）"""
    if role.startswith("thread"):
        return None
    if role in ("glass", "snow") or role in GLOW or role == "felt_heat" or role in C.SHINES:
        return role
    if role.startswith(FIRE):
        return "fire"
    if role.startswith(WOODS):
        return "wood"
    return "felt"


def _steam_marker(o, root):
    """湯気の形を、根元に置いた目印（大きさ: x＝幅、y＝高さ）に替える。Godot が煙の粒子を出す"""
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    e = bpy.data.objects.new(o.name.split(".")[0], None)
    C.coll("prop").objects.link(e)
    e.parent = root
    e.location = root.matrix_world.inverted() @ Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    w = max(hi.x - lo.x, hi.y - lo.y)
    e.scale = (w, w, hi.z - lo.z)   # Blender の z（高さ）は glTF で y になる
    bpy.data.objects.remove(o)


def _join_world(objs, name):
    """部品を世界の座標で 1 つの形に（素材なし）"""
    bm = bmesh.new()
    for o in objs:
        me = o.data.copy()
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    C.coll("prop").objects.link(o)
    return o


def _active(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def _decimate(o, target):
    n = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if n > target:
        d = o.modifiers.new("lighter", "DECIMATE")
        d.ratio = max(0.01, target / n)
        _active(o)
        bpy.ops.object.convert(target="MESH")
    o.data.shade_smooth()


def _bake_to(low, highs, role, extrude):
    """highs（細かい形。縫い目の糸も）の色と凹凸を、low（軽い形）の 1 枚の画像に焼く"""
    me = low.data
    area = sum(p.area for p in me.polygons)
    px = int(math.sqrt(max(area, 1e-6)) * BAKE["density"])
    size = BAKE["min"]
    while size < px and size < BAKE["max"]:
        size *= 2
    _active(low)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.6 if role == "wood" else 0.95
    me.materials.clear()
    me.materials.append(m)
    out = {}
    for kind in ("DIFFUSE", "NORMAL"):
        img = bpy.data.images.new("%s_%s" % (low.name, kind.lower()), size, size, alpha=False)
        if kind == "NORMAL":
            img.colorspace_settings.name = "Non-Color"
        node = m.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        m.node_tree.nodes.active = node
        bpy.ops.object.select_all(action="DESELECT")
        for h in highs:
            h.select_set(True)
        low.select_set(True)
        bpy.context.view_layer.objects.active = low
        kw = dict(use_selected_to_active=True, cage_extrusion=extrude, max_ray_distance=extrude * 5, use_clear=True)
        if kind == "DIFFUSE":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, **kw)
        else:
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", **kw)
        img.pack()
        out[kind] = (node, img)
    m.node_tree.links.new(out["DIFFUSE"][0].outputs["Color"], b.inputs["Base Color"])
    nm = m.node_tree.nodes.new("ShaderNodeNormalMap")
    m.node_tree.links.new(out["NORMAL"][0].outputs["Color"], nm.inputs["Color"])
    m.node_tree.links.new(nm.outputs["Normal"], b.inputs["Normal"])


def _far_threads(o):
    """面に沿わせなかった（離れて垂れた）糸だけを残した写し。なければ None"""
    me = o.data
    if "seated" not in me.attributes:
        return None
    seated = [d.value for d in me.attributes["seated"].data]
    if all(seated):
        return None
    c = o.copy()
    c.data = me.copy()
    C.coll("prop").objects.link(c)
    bm = bmesh.new()
    bm.from_mesh(c.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if seated[v.index]], context="VERTS")
    bm.to_mesh(c.data)
    bm.free()
    return c


def prepare(r):
    """書き出す前: 大きさを当て、モディファイアを当て、糸を面に沿わせ、細かい形を軽い形に焼く。
    軽い形は素材の組（felt・wood・光る物・ガラス・雪）ごとに 1 つ、画像は組ごとに 1 枚。三角の目安は r["tris"] か S["tris"]。
    湯気の形は目印に替える（Godot が煙の粒子を出す）"""
    objs = [r] + descendants(r)
    k = S["scale"]
    if k != 1.0:   # 形と目印の位置を k 倍（根元の大きさは 1 のまま。Godot で置くとき大きさを触っても狂わない）
        for o in objs[1:]:
            o.location = o.location * k
            if o.type == "MESH":
                o.data.transform(Matrix.Scale(k, 4))
                for md in o.modifiers:
                    if md.type == "BEVEL":
                        md.width *= k
                    elif md.type == "DISPLACE":
                        md.strength *= k
                        if md.texture is not None and hasattr(md.texture, "noise_scale"):
                            md.texture.noise_scale *= k
    bpy.context.view_layer.update()
    for o in objs:
        if o.type == "MESH" and o.data.materials and o.modifiers:
            _active(o)
            bpy.ops.object.convert(target="MESH")
    objs = [r] + descendants(r)
    for o in [o for o in objs if o.type == "MESH" and "steam" in o.name]:
        _steam_marker(o, r)
    objs = [r] + descendants(r)
    seat_threads(objs)
    highs = [o for o in objs if o.type == "MESH" and o.data.materials and sum(p.area for p in o.data.polygons) > 0]
    _cycles()
    for o in highs:   # 焼く元の素材に、品物ごとの汚れとくぼみの陰を足す
        role = _role(o)
        if role not in ("glass", "snow"):
            m = o.active_material.copy()
            _grime(m)
            o.data.materials[0] = m
    groups = {}
    threads = [o for o in highs if _role(o).startswith("thread")]
    for o in highs:
        g = group_of(_role(o))
        if g is None:
            far = _far_threads(o)
            if far is not None:
                groups.setdefault("felt", ([], []))[0].append(far)
                groups["felt"][1].append(far)
            continue
        groups.setdefault(g, ([], []))
        groups[g][0].append(o)   # 軽い形の元
        groups[g][1].append(o)   # 焼く元
    tris = {g: sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in src) for g, (src, _h) in groups.items()}
    total = max(1, sum(tris.values()))
    budget = r.get("tris", S["tris"])
    dims = [max(o.dimensions) for o in highs] or [1.0]
    extrude = max(0.006, max(dims) * 0.025)   # 軽くした形のずれを拾える幅
    lows = []
    for g, (src, hs) in groups.items():
        low = _join_world(src, "prop_%s_%s" % (r.name, g))
        _decimate(low, max(120, int(budget * tris[g] / total)))
        if g in ("glass", "snow") or g in C.SHINES:   # 焼かない: 役割と色だけ（Godot が透明な素材・雪の素材・光る素材にする）
            low.data.materials.append(src[0].active_material)
            _flat(low, g)
        else:
            _bake_to(low, hs + (threads if g in ("felt", "wood") else []), g, extrude)
        lows.append(low)
    for o in highs:
        bpy.data.objects.remove(o)
    for low in lows:
        low.parent = r
        low.matrix_parent_inverse = r.matrix_world.inverted()


def _role(o):
    return o.active_material.name.split(".")[0] if o.type == "MESH" and o.data.materials else ""


def seat_threads(objs, sink=0.25, reach=0.1):
    """縫い目の糸を、本体の面（書き出す粗さの形）に沿わせて少し沈める。
    糸の部品を 1 本ずつ（つながった頂点のかたまり）見て、面からいちばん低い所が面より少し下に来るよう、
    各頂点をその下の面の向きに動かす（巻きかがりの輪の形はそのまま）。糸の芯は面より半径の sink 倍だけ下。
    面から reach より離れた糸（垂れた糸など）は触らない"""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    verts, polys = [], []
    for o in objs:
        role = _role(o)
        if not role or role.startswith(("thread", "cotton")):
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in me.vertices]
        polys += [[base + i for i in p.vertices] for p in me.polygons]
        ev.to_mesh_clear()
    if not polys:
        return
    tree = BVHTree.FromPolygons(verts, polys)
    for o in objs:
        if not _role(o).startswith("thread"):
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        lay = bm.verts.layers.int.get("seated") or bm.verts.layers.int.new("seated")
        mw, mwi = o.matrix_world, o.matrix_world.inverted()
        seen = set()
        for v0 in bm.verts:
            if v0 in seen:
                continue
            isl, stack, emin = [], [v0], 1e9
            seen.add(v0)
            while stack:
                v = stack.pop()
                isl.append(v)
                for e in v.link_edges:
                    emin = min(emin, e.calc_length())
                    w = e.other_vert(v)
                    if w not in seen:
                        seen.add(w)
                        stack.append(w)
            pts = [mw @ v.co for v in isl]
            near = [tree.find_nearest(p) for p in pts]
            if any(q is None for q, *_ in near) or min(d for *_, d in near) > reach:
                continue
            for v in isl:
                v[lay] = 1
            r = emin / 1.414 * mw.to_scale()[0]   # 糸の管の太さ（断面 4 角の辺から）
            hs = [(p - q).dot(n) for p, (q, n, _i, _d) in zip(pts, near)]
            delta = -(1 + sink) * r - min(hs)
            for v, p, (q, n, _i, _d) in zip(isl, pts, near):
                v.co = mwi @ (p + n * delta)
        bm.to_mesh(o.data)
        bm.free()


def export_root(root, path, scale=1.0, tris=None):
    """kit を使わない台本（ソリ・木・雪・斜面・機械）の書き出し: 大きさを当てて焼き、glb にする"""
    S["scale"] = scale
    if tris:
        root["tris"] = tris
    prepare(root)
    objs = [root] + descendants(root)
    print("triangles", root.name, C.tri_count(objs))
    C.export(objs, path, root)


def baking_mode():
    """書き出しで焼くときの設定: 素材は描くときと同じに組み、毛羽の層は作らない"""
    C.LOOK["v"] = "day"
    C.NOFUZZ["v"] = True
    S["export"] = True


def export_all(folder, only=None):
    for r, parts in made:
        if r.parent is not None or (only and r.name not in only):
            continue
        prepare(r)
        objs = [r] + descendants(r)
        print("triangles", r.name, C.tri_count(objs))
        C.export(objs, os.path.join(folder, "%s.glb" % r.name), r)


def render_views(args, cams):
    for r, parts in made:   # 描く画像でも、糸を面に沿わせる
        if r.parent is None:
            seat_threads([r] + descendants(r))
    C.setup_render(args.size)
    bpy.context.scene.view_settings.exposure = 0.0
    for r, parts in made:
        if r.parent is None:
            print("triangles", r.name, C.tri_count([r] + descendants(r)))
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
    for v in args.views.split(","):
        loc, tgt, lens = cams[v]
        C.render(loc, tgt, lens, os.path.abspath("%s-%s.png" % (args.prefix, v)))
