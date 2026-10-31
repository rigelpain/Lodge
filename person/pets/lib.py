"""頭・肩の小物とミニオンの台本が使う、素材と形の小道具。
person/ideas/costume/costume_rough.py（もとは person/build_dolls.py）から写した。あちらは import すると組み立てが走るため。
向き: 前は +Y、上は +Z。長さは m。
"""
import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sc = bpy.context.scene


def V(*a):
    return Vector(a)


def lin(h):
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)



# ================================================================ 柄（千代紙。build_dolls.py から写した）
def pattern_image(name, kind, base, ink, px=512):
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    m = np.zeros((px, px), np.float32)
    if kind == "seigaiha":
        r = 1 / 8
        best = np.full((px, px), -1.0)
        dist = np.zeros((px, px))
        for j in range(-1, 18):
            for i in range(-1, 6):
                cx = i * 2 * r + (r if j % 2 else 0)
                cy = j * r * 0.5
                d = np.hypot(((x - cx + 0.5) % 1) - 0.5, y - cy)
                hit = (d < r) & (j >= best)
                best = np.where(hit, j, best)
                dist = np.where(hit, d, dist)
        ring = (dist / r * 4) % 1
        m = ((ring < 0.22) & (best >= 0)).astype(np.float32)
    elif kind == "shippo":
        r = 1 / 8
        for j in range(-1, 9):
            for i in range(-1, 9):
                for ox, oy in ((0, 0), (r, r)):
                    d = np.hypot(x - (i * 2 * r + ox), y - (j * 2 * r + oy))
                    m = np.maximum(m, (np.abs(d - r * 1.414) < 0.006).astype(np.float32))
    b = np.array(lin(base)[:3])
    k = np.array(lin(ink)[:3])
    img = b[None, None] * (1 - m[..., None]) + k[None, None] * m[..., None]
    rgba = np.concatenate([img, np.ones((px, px, 1))], axis=2)[::-1]
    im = bpy.data.images.new(name, px, px)
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.pack()
    return im


# ================================================================ 素材
class Mat:
    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        self.t = self.m.node_tree
        # 名前は UI の言語で訳されることがあるので種類で探す
        self.b = next(n for n in self.t.nodes if n.type == "BSDF_PRINCIPLED")

    def n(self, kind, **kw):
        node = self.t.nodes.new(kind)
        for k, v in kw.items():
            if k in node.inputs:
                node.inputs[k].default_value = v
            else:
                setattr(node, k, v)
        return node

    def l(self, a, ao, b, bi):
        self.t.links.new(a.outputs[ao], b.inputs[bi])

    def mix(self, fac, a, b, blend="MIX"):
        mx = self.n("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        self.l(fac[0], fac[1], mx, 0)
        for slot, src in ((6, a), (7, b)):
            if isinstance(src, tuple) and len(src) == 2 and not isinstance(src[0], float):
                self.l(src[0], src[1], mx, slot)
            else:
                mx.inputs[slot].default_value = src
        return mx

    def obj_coords(self, scale=1.0):
        tc = self.n("ShaderNodeTexCoord")
        mp = self.n("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (scale, scale, scale)
        self.l(tc, "Object", mp, "Vector")
        return mp

    def math(self, op, a, b=None, c=None):
        node = self.n("ShaderNodeMath", operation=op)
        for i, src in enumerate((a, b, c)):
            if src is None:
                continue
            if isinstance(src, (int, float)):
                node.inputs[i].default_value = src
            else:
                self.l(src[0], src[1], node, i)
        return (node, 0)


def fiber_bump(M, co, strength=0.12, scale=380.0):
    no = M.n("ShaderNodeTexNoise", Scale=scale, Detail=10.0, Roughness=0.65)
    M.l(co, 0, no, "Vector")
    st = M.n("ShaderNodeMapping")
    st.inputs["Scale"].default_value = (1.0, 7.0, 1.0)
    M.l(co, 0, st, "Vector")
    vo = M.n("ShaderNodeTexVoronoi", Scale=scale * 0.18)
    vo.feature = "DISTANCE_TO_EDGE"
    M.l(st, 0, vo, "Vector")
    ad = M.n("ShaderNodeMath", operation="MULTIPLY_ADD")
    M.l(vo, "Distance", ad, 0)
    ad.inputs[1].default_value = 0.6
    M.l(no, "Fac", ad, 2)
    bp = M.n("ShaderNodeBump", Strength=strength, Distance=0.0015)
    M.l(ad, 0, bp, "Height")
    return bp


def paper(name, color="F3EFE6", image=None, img_scale=3.0, back="F6F2EA", tint=0.07, rough=0.82, fiber=0.12):
    """紙: 表は色か柄、裏は白。面ごとの明るさの違い（tint 属性）、繊維の凹凸"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    if image is not None:
        tex = M.n("ShaderNodeTexImage", projection="BOX", projection_blend=0.25, interpolation="Linear")
        tex.image = image
        mp = M.obj_coords(img_scale)
        M.l(mp, 0, tex, "Vector")
        front = (tex, "Color")
    else:
        front = lin(color)
    bf = M.n("ShaderNodeNewGeometry")
    side = M.mix((bf, "Backfacing"), front, lin(back))
    at = M.n("ShaderNodeAttribute", attribute_name="tint", attribute_type="GEOMETRY")
    sh = M.n("ShaderNodeMapRange", data_type="FLOAT")
    M.l(at, "Fac", sh, "Value")
    sh.inputs["To Min"].default_value = 1 - tint
    sh.inputs["To Max"].default_value = 1 + tint
    mul = M.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    mul.inputs[0].default_value = 1.0
    M.l(side, 2, mul, 6)
    cm = M.n("ShaderNodeCombineColor")
    for k in range(3):
        M.l(sh, 0, cm, k)
    M.l(cm, 0, mul, 7)
    M.l(mul, 2, M.b, "Base Color")
    M.l(fiber_bump(M, co, fiber), 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = rough
    M.b.inputs["Subsurface Weight"].default_value = 0.08
    M.b.inputs["Subsurface Radius"].default_value = (0.01, 0.008, 0.006)
    M.b.inputs["Specular IOR Level"].default_value = 0.25
    return M.m


def burlap(name, color, weave=260.0):
    """麻布・紙紐の編み: 縦横が入れ替わる織り目（build_dolls.py から写した）"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    wx = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X", Scale=weave / 20, Distortion=4.0, Detail=3.0)
    wz = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Z", Scale=weave / 20, Distortion=4.0, Detail=3.0)
    M.l(co, 0, wx, "Vector")
    M.l(co, 0, wz, "Vector")
    ck = M.n("ShaderNodeTexChecker", Scale=weave / 10)
    M.l(co, 0, ck, "Vector")
    sel = M.n("ShaderNodeMix", data_type="FLOAT")
    M.l(ck, "Fac", sel, 0)
    M.l(wx, "Fac", sel, 2)
    M.l(wz, "Fac", sel, 3)
    no = M.n("ShaderNodeTexNoise", Scale=weave * 0.6, Detail=8.0)
    M.l(co, 0, no, "Vector")
    big = M.n("ShaderNodeTexNoise", Scale=4.0, Detail=3.0)
    M.l(co, 0, big, "Vector")
    h = M.n("ShaderNodeMath", operation="MULTIPLY_ADD")
    M.l(sel, 0, h, 0)
    h.inputs[1].default_value = 0.8
    M.l(no, "Fac", h, 2)
    bp = M.n("ShaderNodeBump", Strength=0.75, Distance=0.004)
    M.l(h, 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    base = lin(color)
    dark = tuple(c * 0.62 for c in base[:3]) + (1,)
    lite = tuple(min(1, c * 1.18) for c in base[:3]) + (1,)
    c1 = M.mix((sel, 0), dark, lite)
    c2 = M.mix((big, "Fac"), (c1, 2), lite)
    M.l(c2, 2, M.b, "Base Color")
    M.b.inputs["Roughness"].default_value = 1.0
    M.b.inputs["Sheen Weight"].default_value = 1.0
    M.b.inputs["Sheen Roughness"].default_value = 0.5
    M.b.inputs["Specular IOR Level"].default_value = 0.1
    return M.m


def felt(name, color, bump=0.35):
    """フェルト: 細かい繊維の凹凸、大きな色むら、毛羽の光（シーン）"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    fine = M.n("ShaderNodeTexNoise", Scale=260.0, Detail=12.0, Roughness=0.7)
    M.l(co, 0, fine, "Vector")
    bp = M.n("ShaderNodeBump", Strength=bump, Distance=0.002)
    M.l(fine, "Fac", bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    big = M.n("ShaderNodeTexNoise", Scale=5.0, Detail=3.0)
    M.l(co, 0, big, "Vector")
    base = lin(color)
    dark = tuple(c * 0.86 for c in base[:3]) + (1,)
    lite = tuple(min(1, c * 1.1) for c in base[:3]) + (1,)
    c = M.mix((big, "Fac"), dark, lite)
    M.l(c, 2, M.b, "Base Color")
    M.b.inputs["Roughness"].default_value = 1.0
    M.b.inputs["Sheen Weight"].default_value = 0.7
    M.b.inputs["Sheen Roughness"].default_value = 0.4
    M.b.inputs["Specular IOR Level"].default_value = 0.1
    return M.m


def knit(name, color, s=70.0):
    """毛糸の編み地: 列ごとの V（メリヤス）を x の山で z をずらした鋸歯で、列の溝も少し"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    sep = M.n("ShaderNodeSeparateXYZ")
    M.l(co, 0, sep, 0)
    fx = M.math("FRACT", M.math("MULTIPLY", (sep, 0), s))
    ab = M.math("ABSOLUTE", M.math("SUBTRACT", fx, 0.5))
    row = M.math("FRACT", M.math("MULTIPLY_ADD", (sep, 2), s * 0.75, M.math("MULTIPLY", ab, 0.9)))
    h = M.math("MULTIPLY_ADD", ab, -0.6, row)
    fz = M.n("ShaderNodeTexNoise", Scale=400.0, Detail=6.0)
    M.l(co, 0, fz, "Vector")
    hh = M.math("MULTIPLY_ADD", (fz, "Fac"), 0.3, h)
    bp = M.n("ShaderNodeBump", Strength=0.6, Distance=0.003)
    M.l(hh[0], 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    base = lin(color)
    dark = tuple(c * 0.7 for c in base[:3]) + (1,)
    c = M.mix(row, dark, base)
    M.l(c, 2, M.b, "Base Color")
    M.b.inputs["Roughness"].default_value = 1.0
    M.b.inputs["Sheen Weight"].default_value = 1.0
    M.b.inputs["Sheen Roughness"].default_value = 0.35
    M.b.inputs["Specular IOR Level"].default_value = 0.08
    return M.m


def yarn_ball(name, color):
    """毛糸玉: ゆがめた縞で、巻いた糸の筋"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    w = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL", Scale=22.0, Distortion=9.0, Detail=2.0, **{"Detail Scale": 1.5})
    M.l(co, 0, w, "Vector")
    bp = M.n("ShaderNodeBump", Strength=0.7, Distance=0.004)
    M.l(w, "Fac", bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    base = lin(color)
    dark = tuple(c * 0.6 for c in base[:3]) + (1,)
    c = M.mix((w, "Fac"), dark, base)
    M.l(c, 2, M.b, "Base Color")
    M.b.inputs["Roughness"].default_value = 1.0
    M.b.inputs["Sheen Weight"].default_value = 1.0
    return M.m


def quilt(name, colors):
    """キルトの鍋つかみ: 端切れのパッチ（色はボロノイの片ごと）、ひし形の縫い目でふくらむ"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    vo = M.n("ShaderNodeTexVoronoi", Scale=18.0, Randomness=0.6)
    M.l(co, 0, vo, "Vector")
    sp = M.n("ShaderNodeSeparateColor")
    M.l(vo, "Color", sp, 0)
    ramp = M.n("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    while len(els) < len(colors):
        els.new(0.5)
    for i, c in enumerate(colors):
        els[i].position = i / len(colors)
        els[i].color = lin(c)
    M.l(sp, 0, ramp, "Fac")
    ed = M.n("ShaderNodeTexVoronoi", Scale=18.0, Randomness=0.6)
    ed.feature = "DISTANCE_TO_EDGE"
    M.l(co, 0, ed, "Vector")
    seam = M.n("ShaderNodeMapRange")
    M.l(ed, "Distance", seam, 0)
    seam.inputs["From Max"].default_value = 0.04
    seam.inputs["To Min"].default_value = 0.55
    sh = M.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    sh.inputs[0].default_value = 1.0
    M.l(ramp, 0, sh, 6)
    cm = M.n("ShaderNodeCombineColor")
    for k in range(3):
        M.l(seam, 0, cm, k)
    M.l(cm, 0, sh, 7)
    M.l(sh, 2, M.b, "Base Color")
    w1 = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL", Scale=14.0)
    M.l(co, 0, w1, "Vector")
    mir = M.n("ShaderNodeMapping")
    mir.inputs["Scale"].default_value = (-1.0, 1.0, 1.0)
    M.l(co, 0, mir, "Vector")
    w2 = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL", Scale=14.0)
    M.l(mir, 0, w2, "Vector")
    h = M.math("MINIMUM", (w1, "Fac"), (w2, "Fac"))
    bp = M.n("ShaderNodeBump", Strength=0.5, Distance=0.004)
    M.l(h[0], 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 0.95
    M.b.inputs["Sheen Weight"].default_value = 0.5
    return M.m


def plain(name, color, rough=0.6, coat=0.0):
    M = Mat(name)
    M.b.inputs["Base Color"].default_value = lin(color)
    M.b.inputs["Roughness"].default_value = rough
    if coat:
        M.b.inputs["Coat Weight"].default_value = coat
        M.b.inputs["Coat Roughness"].default_value = 0.08
    return M.m


def glow(name, color, strength=1.0):
    M = Mat(name)
    em = M.n("ShaderNodeEmission", Strength=strength)
    em.inputs["Color"].default_value = lin(color)
    out = next(n for n in M.t.nodes if n.type == "OUTPUT_MATERIAL")
    M.l(em, 0, out, "Surface")
    return M.m


# ================================================================ 形の小道具（build_dolls.py から写した）
def link(ob):
    sc.collection.objects.link(ob)
    return ob


def add_tint(me, seed):
    rnd = random.Random(seed)
    at = me.attributes.get("tint") or me.attributes.new("tint", "FLOAT", "FACE")
    at.data.foreach_set("value", [rnd.random() for _ in me.polygons])


def finish(ob, mat, smooth=False, seed=0):
    ob.data.materials.clear()
    for m in (mat if isinstance(mat, (list, tuple)) else [mat]):
        ob.data.materials.append(m)
    for p in ob.data.polygons:
        p.use_smooth = smooth
    add_tint(ob.data, seed)
    return ob


def hull(name, pts, mat, seed=0, smooth=False):
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return finish(link(bpy.data.objects.new(name, me)), mat, smooth, seed)


def mesh(name, verts, faces, mat, smooth=False, seed=0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate()
    return finish(link(bpy.data.objects.new(name, me)), mat, smooth, seed)


def thicken(ob, t, rim_white=True):
    mod = ob.modifiers.new("sol", "SOLIDIFY")
    mod.thickness = t
    mod.offset = 0.0
    mod.use_even_offset = True
    if rim_white and len(ob.data.materials) >= 2:
        mod.material_offset_rim = 1
    return ob


def soften(ob, levels=2):
    for p in ob.data.polygons:
        p.use_smooth = True
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return ob


def tube(name, pts, radii, sides, mat, seed=0, flat=True, caps=True):
    """折れ線に沿った筒。radii は数か (u 方向, v 方向) の組"""
    n = len(pts)
    rings = []
    u = None
    for k in range(n):
        tin = (pts[k] - pts[k - 1]).normalized() if k > 0 else (pts[1] - pts[0]).normalized()
        tout = (pts[k + 1] - pts[k]).normalized() if k < n - 1 else tin
        t = (tin + tout).normalized()
        if u is None:
            u = t.cross(Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))).normalized()
        u = (u - t * u.dot(t)).normalized()
        v = t.cross(u)
        r = radii[k]
        ring = []
        for a in range(sides):
            ang = 2 * math.pi * (a + 0.5) / sides
            rr = r if isinstance(r, float) else ((r[0] * math.cos(ang)) ** 2 + (r[1] * math.sin(ang)) ** 2) ** 0.5
            ring.append(pts[k] + (u * math.cos(ang) + v * math.sin(ang)) * rr)
        rings.append(ring)
    verts = [p for ring in rings for p in ring]
    faces = []
    for k in range(n - 1):
        for a in range(sides):
            b = (a + 1) % sides
            faces.append((k * sides + a, k * sides + b, (k + 1) * sides + b, (k + 1) * sides + a))
    if caps:
        faces.append(tuple(range(sides))[::-1])
        faces.append(tuple((n - 1) * sides + a for a in range(sides)))
    ob = mesh(name, verts, faces, mat, not flat, seed)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = not flat
    add_tint(ob.data, seed)
    return ob


def ellipse_pts(c, rx, ry, z, n, rot=0.0):
    return [c + V(math.cos(rot + 2 * math.pi * i / n) * rx, math.sin(rot + 2 * math.pi * i / n) * ry, z) for i in range(n)]


def sphere(name, loc, r, mat, scale=(1, 1, 1), seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = scale
    return finish(ob, mat, smooth=True)


def pompom(name, loc, r, mat):
    """ぼんぼん: 小さな玉から毛糸の毛を立てる"""
    ob = sphere(name, loc, r * 0.7, mat)
    ob.modifiers.new("fuzz", "PARTICLE_SYSTEM")
    ps = ob.particle_systems[-1].settings
    ps.type = "HAIR"
    ps.count = 600
    ps.hair_length = r * 0.55
    ps.use_advanced_hair = True
    ps.factor_random = 0.003
    ps.child_type = "INTERPOLATED"
    ps.rendered_child_count = 8
    ps.roughness_endpoint = r * 0.1
    ps.root_radius = 1.0
    ps.tip_radius = 0.6
    ps.radius_scale = r * 0.07
    ps.material_slot = ob.data.materials[0].name
    return ob


def fuzz(ob, count=2500, length=0.012):
    """布の毛羽（build_dolls.py の麻布と同じ作り）"""
    ob.modifiers.new("fuzz", "PARTICLE_SYSTEM")
    ps = ob.particle_systems[-1].settings
    ps.type = "HAIR"
    ps.count = count
    ps.hair_length = length
    ps.use_advanced_hair = True
    ps.factor_random = 0.008
    ps.brownian_factor = 0.006
    ps.child_type = "INTERPOLATED"
    ps.rendered_child_count = 6
    ps.child_length = 0.8
    ps.child_length_threshold = 0.3
    ps.roughness_endpoint = 0.004
    ps.roughness_1 = 0.004
    ps.root_radius = 1.0
    ps.tip_radius = 0.3
    ps.radius_scale = 0.0012
    ps.material_slot = ob.data.materials[0].name


def rm(*names):
    for n in names:
        ob = bpy.data.objects.get(n)
        if ob:
            bpy.data.objects.remove(ob, do_unlink=True)


def group(name, obs, loc=(0, 0, 0), rot_z=0.0, scale=1.0):
    """形の束を一つの置き台（空の物体）に下げて、まとめて置く"""
    e = link(bpy.data.objects.new(name, None))
    for o in obs:
        o.parent = e
    e.location = loc
    e.rotation_euler = (0, 0, math.radians(rot_z))
    e.scale = (scale, scale, scale)
    return e


def made_since(before):
    return [o for o in sc.objects if o.name not in before and o.parent is None]


def mat(name):
    return bpy.data.materials[name]


# ================================================================ 人形ごとの寸法（build_dolls.py の値）
NEWS_HC = V(0, 0, 0.73)
ORI_HC = V(0, 0, 1.24)
KASA_HC = V(0, 0, 1.02)

