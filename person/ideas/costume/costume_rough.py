"""服・帽子・小物のラフ。人形の .blend を開き、身につけるものの形を足して 1 枚描く。保存はしない。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/costume/costume_rough.py -- --look kabuto --out person/ideas/costume/renders/01-kabuto.png

--look
  kabuto    ③ news   新聞紙の折り兜
  usagi     ③ news   兎の長耳の頭巾と、綿のしっぽ
  kitsune   ② origami 狐の耳の頭巾と、折り紙のしっぽ
  mino      ① kasa   紙の短冊を重ねた蓑
  muffler   ① kasa   風になびく長い毛糸のマフラー
  kago      ② origami 紙紐の背負い籠と毛糸玉
  nakama    ③ news   肩に乗る千代紙の小鳥と、足もとの折り紙の子狐
  tebukuro  （人形なし）手袋 3 組: 標準のフェルト、キルトの鍋つかみ、狐の指人形

素材・形の小道具は person/build_dolls.py から写した（あちらは import すると組み立てが走るため）。
外の素材は使わない。形も柄もコードで作る。向き: 前は +Y。
"""
import argparse
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ap = argparse.ArgumentParser()
ap.add_argument("--look", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--samples", type=int, default=64)
ap.add_argument("--size", default="800x1000")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BLEND = {"kabuto": "news", "usagi": "news", "nakama": "news", "kitsune": "origami", "kago": "origami",
         "mino": "kasa", "muffler": "kasa", "tebukuro": "kasa",
         "bonbon": "news", "donguri": "news", "itomaki": "news", "kuma": "kasa", "erimaki": "kasa", "tsuru": "kasa",
         "chochin": "origami", "export": ""}[A.look]
if BLEND:
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "person", "blend", BLEND + ".blend"))
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
RND = random.Random(7)


def lin(h):
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


def V(*a):
    return Vector(a)


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


# ================================================================ ③ 新聞紙の折り兜
def look_kabuto():
    """こどもの日に新聞紙で折る兜。頭巾を脱いで、新聞紙の頭に新聞紙の兜。目は兜のつばの下に出る"""
    rm("hood")
    news = mat("p_news")
    z0 = 0.80
    apex = V(0, -0.01, 1.14)
    base = [V(sx * 0.215, sy * 0.185, z0) for sx in (1, -1) for sy in (1, -1)]
    hull("kabuto", base + [apex], news, 1)
    # 前のつば: 下の縁を上へ折り返した帯
    brim = mesh("kabuto_brim", [V(-0.235, 0.198, 0.785), V(0.235, 0.198, 0.785), V(0.215, 0.178, 0.865), V(-0.215, 0.178, 0.865)],
                [(0, 1, 2, 3)], [news, news], seed=2)
    thicken(brim, 0.006)
    # 鍬形: 前の面から外上へ折り出した三角の耳
    for s in (1, -1):
        h = mesh("kuwagata", [V(s * 0.03, 0.172, 0.87), V(s * 0.16, 0.15, 0.865), V(s * 0.27, 0.1, 1.07)], [(0, 1, 2)], [news, news], seed=3)
        thicken(h, 0.005)
    # まんなかの小さな折り返し（ひし形の前立て）
    f = mesh("maedate", [V(0, 0.19, 0.87), V(0.05, 0.172, 0.93), V(0, 0.15, 1.0), V(-0.05, 0.172, 0.93)], [(0, 1, 2, 3)], [news, news], seed=4)
    thicken(f, 0.004)


# ================================================================ ③ 兎の長耳の頭巾
def bunny_hood(R=0.212):
    """build_dolls.py の頭巾から、とんがりを取って丸く。顔の窓は同じ"""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=1.0)
    hd = bpy.context.object
    hd.name = "bunny_hood"
    bm = bmesh.new()
    bm.from_mesh(hd.data)
    for v in bm.verts:
        c = v.co.copy()
        if c.y > 0.35:
            c.y += (c.y - 0.35) * 0.55
        v.co = V(c.x * R, c.y * R * 0.95, c.z * R)
    kill = [f for f in bm.faces if (f.calc_center_median().y > 0.1 and f.calc_center_median().x ** 2 + ((f.calc_center_median().z + 0.01) / 1.05) ** 2 < 0.122 ** 2)
            or f.calc_center_median().z < -0.165]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(hd.data)
    bm.free()
    hd.location = NEWS_HC + V(0, -0.004, 0.018)
    return hd


def look_usagi():
    rm("hood")
    cream = felt("felt_cream", "EEE6D8")
    pink = felt("felt_pink", "E2A3A0")
    hd = finish(bunny_hood(), cream, smooth=True, seed=2)
    m = hd.modifiers.new("sol", "SOLIDIFY")
    m.thickness = 0.03
    m.offset = 1.0
    soften(hd, 1)
    fuzz(hd, 2000, 0.005)
    hc = NEWS_HC
    # 右は立ち耳、左は途中で折れて垂れる。耳は頭の向きの矢印になる
    ears = {1: [hc + V(0.06, -0.03, 0.2), hc + V(0.08, -0.05, 0.36), hc + V(0.1, -0.07, 0.5), hc + V(0.105, -0.08, 0.55)],
            -1: [hc + V(-0.06, -0.03, 0.2), hc + V(-0.09, -0.05, 0.34), hc + V(-0.17, -0.06, 0.38), hc + V(-0.26, -0.08, 0.31)]}
    for s, path in ears.items():
        tube("ear", path, [(0.036, 0.011), (0.046, 0.012), (0.034, 0.01), (0.008, 0.006)], 14, cream, flat=False)
        inner = [p + V(0, 0.009, 0.0) for p in path]
        tube("ear_in", inner, [(0.02, 0.004), (0.03, 0.004), (0.022, 0.004), (0.005, 0.003)], 10, pink, flat=False)
    # 上着の背中のすそに、綿のしっぽ
    pompom("tail", V(0, -0.255, 0.37), 0.05, felt("felt_tail", "F4EFE6"))


# ================================================================ ② 狐の耳の頭巾と、しっぽ
def look_kitsune():
    orange = paper("p_fox", "D9772F", back="F6F2EA", tint=0.07)
    white = mat("p_white")
    hd = bpy.data.objects["hood"]
    hd.data.materials[0] = orange
    hd.data.materials[1] = white
    hc = ORI_HC
    for s in (1, -1):
        tip = hc + V(s * 0.17, -0.01, 0.4)
        hull("fox_ear", [hc + V(s * 0.05, -0.04, 0.245), hc + V(s * 0.17, -0.04, 0.17), hc + V(s * 0.12, 0.04, 0.2),
                         hc + V(s * 0.11, -0.1, 0.19), tip], orange, 4)
        inn = mesh("fox_ear_in", [hc + V(s * 0.075, 0.012, 0.245), hc + V(s * 0.155, 0.02, 0.2), tip + V(-s * 0.008, 0.012, -0.03)],
                   [(0, 1, 2)], [white, white], seed=5)
        thicken(inn, 0.004)
    # しっぽ: 腰のうしろから外へ曲がって上がる。先は白
    tail = ellipse_pts(V(0.0, -0.17, 0.52), 0.035, 0.035, 0, 6) + ellipse_pts(V(0.07, -0.33, 0.43), 0.095, 0.08, 0, 8, 0.3) + \
        ellipse_pts(V(0.17, -0.45, 0.5), 0.07, 0.065, 0, 7)
    hull("fox_tail", tail, orange, 6)
    hull("fox_tail_tip", ellipse_pts(V(0.17, -0.45, 0.5), 0.071, 0.066, 0, 7) + [V(0.25, -0.55, 0.63), V(0.22, -0.5, 0.6), V(0.27, -0.52, 0.56)], white, 7)


# ================================================================ ① 紙の短冊の蓑
def look_mino():
    straw = paper("p_straw", "C9A659", back="E9DCB4", tint=0.16, fiber=0.2)
    straw2 = paper("p_straw2", "B48E45", back="E9DCB4", tint=0.16, fiber=0.2)
    red = paper("p_mino_red", image=pattern_image("shippo_m", "shippo", "B23A2E", "E58A62"), img_scale=3.5)
    rnd = random.Random(3)
    # 肩から 3 段。前は開けて着物を見せる
    rows = [(0.875, 0.165, 0.175, 0.2, 30), (0.75, 0.215, 0.215, 0.22, 34), (0.62, 0.255, 0.245, 0.22, 38)]
    for ri, (z, rx, ry, L, n) in enumerate(rows):
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * ri) / n
            if math.sin(a) > 0.5:
                continue
            p = V(math.cos(a) * rx, math.sin(a) * ry, z)
            out = V(math.cos(a), math.sin(a), 0)
            tg = V(-math.sin(a), math.cos(a), 0)
            w = 0.03 + rnd.uniform(-0.004, 0.006)
            ln = L + rnd.uniform(-0.03, 0.02)
            b = p + out * (0.07 + rnd.uniform(0, 0.02)) + V(0, 0, -ln) + tg * rnd.uniform(-0.01, 0.01)
            m = [straw, straw2][rnd.random() < 0.4]
            # いちばん上の段の背中にだけ、千代紙の短冊を一枚まぜる（凝った版の見本）
            if ri == 0 and abs(i - n * 0.75) < 1.0:
                m = red
            st = mesh("mino", [p - tg * w, p + tg * w, b + tg * w * 1.15, b - tg * w * 1.15], [(0, 1, 2, 3)], [m, m], seed=ri * 100 + i)
            thicken(st, 0.003)
    # 首もとで結ぶ麻ひも
    tube("mino_cord", [V(math.cos(a) * 0.15, math.sin(a) * 0.12 + 0.005, 0.885) for a in np.linspace(-0.3, math.pi + 0.3, 12)] +
         [V(0.0, 0.13, 0.86), V(0.02, 0.15, 0.78)], [0.006] * 14, 6, plain("cord", "B79C6B", 0.9), flat=False)


# ================================================================ ① 風になびく長い毛糸のマフラー
def look_muffler():
    red = knit("knit_red", "B8352B")
    cream = knit("knit_cream", "EFE5D2")
    # 首の輪: 髪を中に入れて巻く
    ring = [V(math.cos(a) * 0.2, math.sin(a) * 0.15 + 0.01, 0.87 + 0.012 * math.sin(2 * a)) for a in np.linspace(0, 2 * math.pi, 24)]
    tube("muffler_ring", ring, [(0.045, 0.024)] * len(ring), 12, red, flat=False, caps=False)
    # 前に垂れる端と、風でうしろへ流れる端。縞は 2 色の区切りで
    hang = [V(0.07, 0.165, 0.87), V(0.085, 0.18, 0.78), V(0.075, 0.185, 0.68), V(0.09, 0.18, 0.58), V(0.085, 0.18, 0.5)]
    fly = [V(-0.15, -0.09, 0.86), V(-0.26, -0.2, 0.88), V(-0.4, -0.27, 0.84), V(-0.54, -0.31, 0.88), V(-0.68, -0.33, 0.85)]
    for path, rad in ((hang, (0.05, 0.016)), (fly, (0.05, 0.016))):
        fine = []
        for i in range(len(path) - 1):
            for k in range(3):
                fine.append(path[i].lerp(path[i + 1], k / 3))
        fine.append(path[-1])
        for i in range(len(fine) - 1):
            seg = [fine[max(0, i - 1)].lerp(fine[i], 0.999), fine[i], fine[i + 1]] if i else [fine[i], fine[i + 1]]
            tube("muffler", seg, [rad] * len(seg), 12, [red, cream][(i // 2) % 2], flat=False, caps=False)
        pompom("muffler_pom", path[-1] + (path[-1] - path[-2]).normalized() * 0.03, 0.04, knit("knit_pom", "EFE5D2", 200.0))


# ================================================================ ② 紙紐の背負い籠と毛糸玉
def look_kago():
    cord = burlap("cord_weave", "9A7447", 120.0)
    cord_plain = plain("cord_plain", "8A6840", 0.9)
    # 籠: 下がすぼまった筒。上は開ける
    n = 18
    rings = [(0.56, 0.1, 0.075), (0.7, 0.13, 0.09), (0.86, 0.15, 0.1), (1.0, 0.16, 0.11)]
    verts, faces = [], []
    for z, rx, ry in rings:
        for i in range(n):
            a = 2 * math.pi * i / n
            verts.append(V(math.cos(a) * rx, -0.23 + math.sin(a) * ry, z))
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
    faces.append(tuple(range(n))[::-1])
    kago = mesh("kago", verts, faces, cord, smooth=True, seed=1)
    thicken(kago, 0.012, rim_white=False)
    rim = [V(math.cos(a) * 0.162, -0.23 + math.sin(a) * 0.112, 1.0) for a in np.linspace(0, 2 * math.pi, 25)]
    tube("kago_rim", rim, [0.012] * len(rim), 8, cord_plain, flat=False, caps=False)
    # 背負い紐: 籠の上 → 肩 → 胸の前 → 脇の下 → 籠の下
    for s in (1, -1):
        path = [V(s * 0.09, -0.2, 0.97), V(s * 0.12, -0.08, 1.04), V(s * 0.13, 0.05, 1.02), V(s * 0.135, 0.13, 0.9),
                V(s * 0.16, 0.08, 0.8), V(s * 0.16, -0.06, 0.72), V(s * 0.09, -0.21, 0.6)]
        tube("kago_strap", path, [0.011] * len(path), 8, cord_plain, flat=False)
    # 毛糸玉（あなた・仲間の色）と、編み針
    for loc, r, col in ((V(0.055, -0.24, 1.02), 0.065, "B8352B"), (V(-0.06, -0.21, 1.01), 0.058, "2F4A7A"), (V(0.0, -0.3, 1.0), 0.055, "D9A42C")):
        sphere("yarn", loc, r, yarn_ball("yarn_" + col, col))
    wood = plain("needle", "C79A62", 0.5)
    for s, lean in ((1, 0.12), (-1, 0.2)):
        a = V(s * 0.03, -0.27, 0.95)
        b = a + V(s * lean, -0.08, 0.3)
        tube("knit_needle", [a, b], [0.005, 0.005], 6, wood, flat=False)
        sphere("needle_end", b, 0.012, plain("needle_ball", "B8352B", 0.4))


# ================================================================ ③ 肩の千代紙の小鳥と、足もとの折り紙の子狐
def build_bird(chiyo, white, beak, ink):
    """千代紙の小鳥。部品を「体」と「頭」に分けて返す（ゲームでは頭だけ回す）"""
    P = {"body": [], "head": []}
    P["body"].append(hull("bird_body", [V(0, 0.05, 0.035), V(0, -0.05, 0.03), V(0.026, 0.0, 0.025), V(-0.026, 0.0, 0.025), V(0, 0.0, 0.0), V(0, 0.01, 0.055)], chiyo, 1))
    P["head"].append(hull("bird_head", [V(0, 0.045, 0.05), V(0.017, 0.058, 0.062), V(-0.017, 0.058, 0.062), V(0, 0.068, 0.085), V(0, 0.062, 0.045)], chiyo, 2))
    P["head"].append(hull("bird_beak", [V(0.006, 0.072, 0.065), V(-0.006, 0.072, 0.065), V(0, 0.07, 0.072), V(0, 0.1, 0.062)], beak, 3))
    for s in (1, -1):
        w = mesh("bird_wing", [V(s * 0.024, 0.025, 0.04), V(s * 0.03, -0.05, 0.035), V(s * 0.05, -0.065, 0.07)], [(0, 1, 2)], [chiyo, white], seed=4)
        P["body"].append(thicken(w, 0.003))
        P["head"].append(sphere("bird_eye", V(s * 0.016, 0.066, 0.068), 0.004, ink))
    t = mesh("bird_tail", [V(0.012, -0.045, 0.032), V(-0.012, -0.045, 0.032), V(0, -0.11, 0.075)], [(0, 1, 2)], [chiyo, white], seed=5)
    P["body"].append(thicken(t, 0.003))
    return P


def build_kit(orange, cream, dark):
    """多面体の折り紙の子狐（座った形）。部品を「体」「頭」「しっぽ」に分けて返す"""
    P = {"body": [], "head": [], "tail": []}
    P["body"].append(hull("kit_body", ellipse_pts(V(0, -0.03, 0.0), 0.08, 0.1, 0, 7) + ellipse_pts(V(0, -0.04, 0.08), 0.085, 0.09, 0, 7) +
                          ellipse_pts(V(0, 0.04, 0.2), 0.045, 0.04, 0, 6), orange, 11))
    P["body"].append(hull("kit_chest", [V(0, 0.08, 0.03), V(0.035, 0.065, 0.09), V(-0.035, 0.065, 0.09), V(0.03, 0.06, 0.2), V(-0.03, 0.06, 0.2), V(0, 0.088, 0.14)], cream, 12))
    P["head"].append(hull("kit_head", [V(0.052, 0.04, 0.27), V(-0.052, 0.04, 0.27), V(0.04, 0.015, 0.315), V(-0.04, 0.015, 0.315), V(0, 0.0, 0.305),
                                       V(0, 0.06, 0.225), V(0, 0.165, 0.255), V(0.022, 0.12, 0.25), V(-0.022, 0.12, 0.25), V(0, 0.1, 0.29)], orange, 13))
    P["head"].append(hull("kit_cheek", [V(0.045, 0.06, 0.245), V(-0.045, 0.06, 0.245), V(0, 0.07, 0.228), V(0, 0.165, 0.253), V(0.02, 0.12, 0.243), V(-0.02, 0.12, 0.243)], cream, 14))
    P["head"].append(hull("kit_nose", [V(0, 0.17, 0.258), V(0.01, 0.155, 0.262), V(-0.01, 0.155, 0.262), V(0, 0.157, 0.25), V(0, 0.155, 0.272)], dark, 15))
    for s in (1, -1):
        P["head"].append(hull("kit_ear", [V(s * 0.018, 0.03, 0.305), V(s * 0.058, 0.035, 0.29), V(s * 0.04, 0.0, 0.3), V(s * 0.052, 0.025, 0.385)], orange, 16))
        P["head"].append(hull("kit_eye", [V(s * 0.03, 0.098, 0.283), V(s * 0.045, 0.085, 0.29), V(s * 0.038, 0.094, 0.278), V(s * 0.033, 0.09, 0.29)], dark, 17))
        P["body"].append(tube("kit_leg", [V(s * 0.03, 0.06, 0.15), V(s * 0.03, 0.075, 0.0)], [0.014, 0.012], 5, dark, seed=18))
    P["tail"].append(hull("kit_tail", [V(0.07, -0.09, 0.02), V(0.09, -0.11, 0.06), V(0.13, -0.02, 0.0), V(0.15, 0.02, 0.05), V(0.14, 0.06, 0.0), V(0.1, -0.05, 0.08)], orange, 19))
    P["tail"].append(hull("kit_tail_tip", [V(0.14, 0.055, 0.0), V(0.152, 0.04, 0.045), V(0.12, 0.13, 0.0), V(0.13, 0.12, 0.03), V(0.145, 0.06, 0.03)], cream, 20))
    return P


def look_nakama():
    before = {o.name for o in sc.objects}
    build_bird(paper("p_bird", image=pattern_image("seigaiha_b", "seigaiha", "B8473A", "E8A07A"), img_scale=6.0),
               paper("p_bwhite", "F4F0E8"), paper("p_beak", "D9A42C"), plain("bink", "1E1A18", 0.4))
    # 頭巾のてっぺんに止まって、頭と一緒に回る（目線の矢印が一本ふえる）
    group("bird", made_since(before), loc=(0.035, 0.04, 0.94), rot_z=-6, scale=1.7)

    before = {o.name for o in sc.objects}
    build_kit(paper("p_kit", "D27330", tint=0.08), paper("p_kitw", "F2EBDD"), paper("p_kitd", "4A3326"))
    # 子狐は人形の右前に座って、人形の見ている方（前）を一緒に見る
    group("kit", made_since(before), loc=(0.34, 0.16, 0.0), rot_z=-12, scale=1.2)


# ================================================================ ゲーム用の書き出し（--look export --out <フォルダ>）
def join_parts(name, objs, pivot, scale):
    """部品を、修飾（厚み）を当てたうえで 1 つの形にまとめる。pivot が原点（回す軸）になる"""
    # 評価した形（evaluated_get）を使うと、空の場面では Blender 5.2 が落ちるので、厚みは bmesh で付ける
    bm = bmesh.new()
    mats = []
    for o in objs:
        part = bmesh.new()
        part.from_mesh(o.data)
        sol = o.modifiers.get("sol")
        if sol:
            bmesh.ops.solidify(part, geom=part.faces[:], thickness=sol.thickness)
        part.transform(o.matrix_world)
        remap = []
        for slot in o.material_slots:
            if slot.material not in mats:
                mats.append(slot.material)
            remap.append(mats.index(slot.material))
        for f in part.faces:
            f.material_index = remap[min(f.material_index, len(remap) - 1)] if remap else 0
        tmp = bpy.data.meshes.new("tmp")
        part.to_mesh(tmp)
        part.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    for v in bm.verts:
        v.co = (v.co - pivot) * scale
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = False
    ob = link(bpy.data.objects.new(name, me))
    ob.location = pivot * scale
    return ob


def look_export():
    """小鳥と子狐を glb にする。素材は名前だけの単色（ゲームでは look.gd の紙と和柄に置き換える）"""
    out = os.path.abspath(A.out)
    os.makedirs(out, exist_ok=True)
    m = {k: plain(k, c, 0.8) for k, c in (("chiyo", "B8473A"), ("white", "F4F0E8"), ("beak", "D9A42C"), ("ink", "1E1A18"),
                                            ("orange", "D27330"), ("cream", "F2EBDD"), ("dark", "4A3326"))}
    for name, P, pivots, scale in (
            ("bird", build_bird(m["chiyo"], m["white"], m["beak"], m["ink"]), {"body": V(0, 0, 0), "head": V(0, 0.045, 0.05)}, 1.7),
            ("kit", build_kit(m["orange"], m["cream"], m["dark"]), {"body": V(0, 0, 0), "head": V(0, 0.04, 0.22), "tail": V(0.07, -0.08, 0.03)}, 1.2)):
        parts = [o for v in P.values() for o in v]
        joined = [join_parts(k, P[k], pivots[k], scale) for k in P]
        for o in parts:
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.object.select_all(action="DESELECT")
        for o in joined:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format="GLB", use_selection=True, export_yup=True)
        print("wrote", os.path.join(out, name + ".glb"))
        for o in joined:
            bpy.data.objects.remove(o, do_unlink=True)
    sys.exit(0)


# ================================================================ 手袋 3 組（人形なし）
def look_tebukuro():
    for o in list(sc.objects):
        if o.type == "MESH" and o.name != "Plane":
            bpy.data.objects.remove(o, do_unlink=True)

    def mitten(name, x, y, s, body, cuff, flat=1.0, rot=0.0):
        """立てたミトン。s=1 が右手（親指が -X）。前は +Y"""
        before = {o.name for o in sc.objects}
        th = 0.022 * flat
        h = hull(name, ellipse_pts(V(0, 0, 0.04), 0.045, th, 0, 10) + ellipse_pts(V(0, 0, 0.13), 0.05, th * 1.05, 0, 10) +
                 ellipse_pts(V(0, 0, 0.18), 0.035, th * 0.85, 0, 10) + [V(0, 0, 0.198)], body, 1)
        soften(h, 2)
        tb = hull(name + "_thumb", ellipse_pts(V(-s * 0.04, 0, 0.07), 0.016, th * 0.7, 0, 8) +
                  ellipse_pts(V(-s * 0.068, 0, 0.115), 0.013, th * 0.6, 0, 8) + [V(-s * 0.072, 0, 0.13)], body, 2)
        soften(tb, 2)
        cf = tube(name + "_cuff", [V(0, 0, 0.0), V(0, 0, 0.045)], [(0.05, th * 1.15), (0.047, th * 1.1)], 16, cuff, flat=False)
        soften(cf, 1)
        g = group(name, made_since(before), loc=(x, y, 0.0), rot_z=rot)
        return g

    red = felt("felt_red", "B8352B")
    cuff = knit("knit_cuff", "EFE5D2", 160.0)
    # 1. 標準: 赤いフェルトのミトン。2 つを毛糸の紐でつなぐ
    mitten("std_r", -0.1, -0.16, 1, red, cuff, rot=8)
    mitten("std_l", -0.25, -0.18, -1, red, cuff, rot=-6)
    tube("std_cord", [V(-0.1, -0.16, 0.02), V(-0.13, -0.12, 0.004), V(-0.18, -0.11, 0.003), V(-0.23, -0.14, 0.004), V(-0.25, -0.18, 0.02)],
         [0.004] * 5, 6, knit("knit_cord", "EFE5D2", 300.0), flat=False)
    # 2. キルトの鍋つかみ: 端切れのパッチと、ひし形の縫い目。手首に掛けひもの輪
    q = quilt("quilt", ["C45A3C", "E2C27A", "3F6E8C", "EDE3D0", "7C8F4E", "B88AA0"])
    edge = felt("felt_bias", "7A2E26")
    mitten("q_r", 0.25, -0.18, 1, q, edge, flat=1.35, rot=-8)
    mitten("q_l", 0.1, -0.16, -1, q, edge, flat=1.35, rot=6)
    for x in (0.25, 0.1):
        tube("q_loop", [V(x + 0.03 * math.cos(a), -0.17, -0.005 + 0.03 * math.sin(a)) for a in np.linspace(-math.pi * 0.9, -math.pi * 0.1, 7)],
             [0.004] * 7, 6, edge, flat=False)
    # 3. 狐の指人形の手袋: 先が鼻先。ボタンの目、三角の耳、白い口もと
    fox = felt("felt_fox", "D27330")
    fwhite = felt("felt_foxw", "F2EBDD")
    button = plain("button", "0B0B0C", 0.18, coat=1.0)
    shine = plain("shine", "FFFFFF", 0.3)
    for name, x, s, rot in (("fox_r", 0.075, 1, 4), ("fox_l", -0.075, -1, -4)):
        before = {o.name for o in sc.objects}
        g = mitten(name, 0, 0, s, fox, knit("knit_fox", "4A3326", 160.0), rot=0)
        parts = []
        for e in (1, -1):
            parts.append(soften(hull("fox_glove_ear", [V(e * 0.012, -0.006, 0.18), V(e * 0.045, -0.006, 0.165), V(e * 0.03, 0.006, 0.17),
                                                     V(e * 0.03, -0.016, 0.17), V(e * 0.04, -0.005, 0.245)], fox, 3), 1))
            parts.append(sphere("fox_glove_eye", V(e * 0.02, 0.023, 0.15), 0.009, button, scale=(1, 0.5, 1)))
            parts.append(sphere("fox_glove_shine", V(e * 0.02 - 0.003, 0.028, 0.153), 0.0025, shine, scale=(1, 0.4, 1)))
        parts.append(soften(hull("fox_glove_mouth", ellipse_pts(V(0, 0.018, 0.17), 0.03, 0.01, 0, 8) + ellipse_pts(V(0, 0.016, 0.195), 0.012, 0.008, 0, 6) +
                                 [V(0, 0.022, 0.13)], fwhite, 4), 1))
        parts.append(sphere("fox_glove_nose", V(0, 0.012, 0.2), 0.008, button))
        for p in parts:
            p.parent = g
        g.location = (x, 0.16, 0.0)
        g.rotation_euler = (0, 0, math.radians(rot))


# ================================================================ 2 回目（2026-10-28）: ほかの案
def cap_dome(name, center, scale, mat_, cut=0.0):
    """半球の帽子: 球の z < cut を落として、縦横を伸ばす"""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=36, ring_count=18, radius=1.0)
    ob = bpy.context.object
    ob.name = name
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < cut], context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    ob.location = center
    ob.scale = scale
    finish(ob, mat_, smooth=True)
    m = ob.modifiers.new("sol", "SOLIDIFY")
    m.thickness = 0.012
    m.offset = 1.0
    return ob


def ring_pts(c, rx, ry, n=25, a0=0.0, a1=2 * math.pi):
    return [c + V(math.cos(a) * rx, math.sin(a) * ry, 0) for a in np.linspace(a0, a1, n)]


def look_bonbon():
    """③ 標準の毛糸のぼんぼん帽。折り返しのある藍の編み地に、山吹のぼんぼん"""
    rm("hood")
    hc = NEWS_HC
    indigo = knit("knit_indigo", "2F4A7A", 90.0)
    cap_dome("bonbon_cap", hc + V(0, -0.01, 0.045), (0.192, 0.178, 0.2), indigo)
    ring = ring_pts(hc + V(0, -0.01, 0.06), 0.198, 0.184)
    tube("bonbon_cuff", ring, [(0.035, 0.016)] * len(ring), 12, knit("knit_cuff2", "2F4A7A", 160.0), flat=False, caps=False)
    pompom("bonbon_pom", hc + V(0, -0.015, 0.26), 0.075, knit("knit_pom2", "D9A42C", 200.0))


def look_kuma():
    """① 笠を脱いで、熊の丸耳のニット帽。閉じた目と頬は帽子の下に出る"""
    rm("kasa", "kasa_ring")
    hc = KASA_HC
    brown = knit("knit_bear", "7A5236", 90.0)
    cap_dome("kuma_cap", hc + V(0, -0.012, 0.045), (0.168, 0.172, 0.18), brown)
    ring = ring_pts(hc + V(0, -0.012, 0.06), 0.172, 0.176)
    tube("kuma_cuff", ring, [(0.026, 0.013)] * len(ring), 12, knit("knit_bear2", "5E3F2A", 160.0), flat=False, caps=False)
    for s in (1, -1):
        sphere("kuma_ear", hc + V(s * 0.125, -0.02, 0.205), 0.066, brown, scale=(1, 0.45, 1))
        sphere("kuma_ear_in", hc + V(s * 0.125, 0.004, 0.203), 0.04, felt("felt_bear_in", "C9A27A"), scale=(1, 0.3, 1))


def look_donguri():
    """③ どんぐりの帽子: 麻ひもを編んだ浅いかさと、てっぺんの小さな柄"""
    rm("hood")
    hc = NEWS_HC
    cup = burlap("acorn_cup", "7A5530", 150.0)
    cap_dome("donguri_cap", hc + V(0, -0.005, 0.07), (0.2, 0.186, 0.135), cup)
    ring = ring_pts(hc + V(0, -0.005, 0.072), 0.203, 0.189)
    tube("donguri_rim", ring, [0.022] * len(ring), 10, cup, flat=False, caps=False)
    tube("donguri_stem", [hc + V(0, -0.01, 0.19), hc + V(0.01, -0.02, 0.25), hc + V(0.035, -0.03, 0.28)], [0.016, 0.013, 0.011], 8,
         felt("felt_stem", "4A3326"), flat=False)


def look_itomaki():
    """③ 糸巻きの帽子: 木の糸巻きに赤い糸。針が刺さり、糸の端が肩へ垂れる"""
    rm("hood")
    hc = NEWS_HC
    wood = plain("spool_wood", "C79A62", 0.55)
    for z, r, d in ((0.15, 0.15, 0.024), (0.3, 0.15, 0.024)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r, depth=d, location=hc + V(0, -0.01, z))
        disc = bpy.context.object
        finish(disc, wood, smooth=False)
        b = disc.modifiers.new("bev", "BEVEL")
        b.width = 0.006
        b.segments = 2
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.112, depth=0.128, location=hc + V(0, -0.01, 0.225))
    finish(bpy.context.object, yarn_ball("spool_thread", "B8352B"), smooth=True)
    steel = plain("needle_steel", "B9BEC4", 0.25)
    tube("needle", [hc + V(0.06, 0.02, 0.29), hc + V(0.11, 0.05, 0.42)], [0.004, 0.002], 6, steel, flat=False)
    tube("thread_end", [hc + V(0.11, 0.03, 0.225), hc + V(0.16, 0.04, 0.16), hc + V(0.19, 0.06, 0.02), hc + V(0.2, 0.07, -0.12)],
         [0.003] * 4, 5, plain("thread_red", "B8352B", 0.8), flat=False)


def look_chochin():
    """② 背中の紙ちょうちん: 腰の紐に挿した竹の竿から下げる。中に灯り。頭より高くしない"""
    wood = plain("bamboo", "B79C6B", 0.6)
    tube("chochin_belt", ring_pts(V(0, -0.005, 0.86), 0.16, 0.12), [0.008] * 25, 6, plain("belt", "8A4E2E", 0.8), flat=False, caps=False)
    pole = [V(0.03, -0.12, 0.84), V(0.03, -0.17, 1.05), V(0.03, -0.22, 1.26), V(0.03, -0.3, 1.33), V(0.03, -0.38, 1.33)]
    tube("chochin_pole", pole, [0.01] * len(pole), 8, wood, flat=False)
    c = V(0.03, -0.38, 1.13)
    tube("chochin_string", [V(0.03, -0.38, 1.33), c + V(0, 0, 0.12)], [0.0025, 0.0025], 5, plain("str", "2B211C", 0.8), flat=False)
    M = Mat("chochin_paper")
    co = M.obj_coords(1.0)
    w = M.n("ShaderNodeTexWave", wave_type="RINGS", rings_direction="Z", Scale=60.0)
    M.l(co, 0, w, "Vector")
    bp = M.n("ShaderNodeBump", Strength=0.6, Distance=0.003)
    M.l(w, "Fac", bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Base Color"].default_value = lin("F2D9A8")
    M.b.inputs["Emission Color"].default_value = lin("FF9A3C")
    M.b.inputs["Emission Strength"].default_value = 3.0
    M.b.inputs["Roughness"].default_value = 0.8
    sphere("chochin", c, 0.075, M.m, scale=(1, 1, 1.35), seg=32)
    lacquer = plain("lacquer", "1E1A18", 0.3, coat=0.6)
    for dz in (0.1, -0.1):
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.045, depth=0.022, location=c + V(0, 0, dz))
        finish(bpy.context.object, lacquer, smooth=True)
    L = bpy.data.lights.new("chochin_light", "POINT")
    L.energy = 6.0
    L.color = lin("FF9A3C")[:3]
    L.shadow_soft_size = 0.05
    link(bpy.data.objects.new("chochin_light", L)).location = c


def look_erimaki():
    """① 狐の襟巻き: フェルトの狐が首に巻きつく。顔は閉じた目の弧（人の顔と取り違えないように）"""
    hc = KASA_HC
    fox = felt("felt_fox2", "D27330")
    cream = felt("felt_fox2w", "F2EBDD")
    ink = plain("fox_ink", "2B211C", 0.5)
    body = [V(math.cos(a) * 0.21, math.sin(a) * 0.16 + 0.01, 0.92 + 0.01 * math.sin(a)) for a in np.linspace(math.radians(48), math.radians(-232), 26)]
    body += [V(-0.16, 0.19, 0.86), V(-0.17, 0.24, 0.77), V(-0.165, 0.27, 0.69)]
    rad = [0.042] * 26 + [0.05, 0.055, 0.046]
    tube("erimaki", body, rad, 14, fox, flat=False, caps=False)
    tube("erimaki_tip", [V(-0.165, 0.27, 0.69), V(-0.162, 0.28, 0.65), V(-0.158, 0.28, 0.61)], [0.046, 0.036, 0.01], 14, cream, flat=False)
    h0 = body[0]
    h0 = h0 + V(0.01, 0.03, 0.01)
    soften(hull("erimaki_head", ellipse_pts(h0 + V(0, 0.0, -0.035), 0.055, 0.05, 0, 8) + ellipse_pts(h0 + V(0, 0.01, 0.035), 0.05, 0.045, 0, 8) +
                [h0 + V(0.01, 0.1, -0.012)], fox, 1), 1)
    sphere("erimaki_nose", h0 + V(0.01, 0.1, -0.01), 0.01, ink)
    for s in (1, -1):
        e = h0 + V(s * 0.026, 0.052, 0.022)
        tube("erimaki_eye", [e + V(-0.012, 0, 0.002), e + V(-0.004, 0.002, -0.004), e + V(0.004, 0.002, -0.004), e + V(0.012, 0, 0.002)],
             [0.0025] * 4, 5, ink, flat=False)
        hull("erimaki_ear", [h0 + V(s * 0.012, -0.005, 0.06), h0 + V(s * 0.052, -0.005, 0.045), h0 + V(s * 0.035, 0.012, 0.05),
                             h0 + V(s * 0.04, -0.01, 0.12)], fox, 2)


def look_tsuru():
    """① 笠の縁に千代紙の折り鶴を一羽。笠の向き（目線）と同じ前を向く"""
    before = {o.name for o in sc.objects}
    chiyo = paper("p_crane", image=pattern_image("seigaiha_c", "seigaiha", "2F5A8F", "8FB3D9"), img_scale=6.0)
    white = paper("p_cwhite", "F4F0E8")
    hull("crane_body", [V(0, 0.035, 0.02), V(0, -0.035, 0.02), V(0.02, 0, 0.015), V(-0.02, 0, 0.015), V(0, 0, 0.0), V(0, 0, 0.04)], chiyo, 1)
    for pts in ([V(0.004, 0.025, 0.02), V(-0.004, 0.025, 0.02), V(0, 0.1, 0.11)], [V(0.004, -0.025, 0.02), V(-0.004, -0.025, 0.02), V(0, -0.1, 0.1)]):
        t = mesh("crane_spike", pts, [(0, 1, 2)], [chiyo, white], seed=2)
        thicken(t, 0.004)
    t = mesh("crane_head", [V(0.003, 0.095, 0.105), V(-0.003, 0.095, 0.105), V(0, 0.13, 0.085)], [(0, 1, 2)], [chiyo, white], seed=3)
    thicken(t, 0.004)
    for s in (1, -1):
        w = mesh("crane_wing", [V(s * 0.004, 0.03, 0.035), V(s * 0.004, -0.03, 0.035), V(s * 0.12, -0.02, 0.1)], [(0, 1, 2)], [chiyo, white], seed=4)
        thicken(w, 0.003)
    a = math.radians(55)
    r = 0.33
    z = 1.07 + 0.3 * (1 - r / 0.43)
    group("crane", made_since(before), loc=(math.cos(a) * r, math.sin(a) * r, z - 0.005), rot_z=-10, scale=1.8)


LOOKS = {
    "export": (look_export, "", {}),
    "kabuto": (look_kabuto, "③ 新聞紙の折り兜", dict(top=1.14, ang=28)),
    "usagi": (look_usagi, "③ 兎の長耳の頭巾", dict(top=1.28, ang=30)),
    "kitsune": (look_kitsune, "② 狐の頭巾としっぽ", dict(top=1.66, ang=55, dx=0.05)),
    "mino": (look_mino, "① 紙の短冊の蓑", dict(top=1.47, ang=115)),
    "muffler": (look_muffler, "① なびく毛糸のマフラー", dict(top=1.47, ang=20, dx=-0.18, dist=1.12)),
    "kago": (look_kago, "② 紙紐の背負い籠と毛糸玉", dict(top=1.45, ang=135)),
    "nakama": (look_nakama, "③ 頭の小鳥と、ついてくる子狐", dict(top=1.02, ang=22, dx=0.14, dist=1.18)),
    "tebukuro": (look_tebukuro, "手袋 3 組（標準・キルト・狐）", dict(top=0.3, ang=8, lift=1.9, dist=2.0)),
    "bonbon": (look_bonbon, "③ 毛糸のぼんぼん帽", dict(top=1.1, ang=25)),
    "kuma": (look_kuma, "① 熊の丸耳のニット帽", dict(top=1.3, ang=25)),
    "donguri": (look_donguri, "③ どんぐりの帽子", dict(top=1.05, ang=25)),
    "itomaki": (look_itomaki, "③ 糸巻きの帽子", dict(top=1.12, ang=30)),
    "chochin": (look_chochin, "② 背中の紙ちょうちん", dict(top=1.5, ang=140)),
    "erimaki": (look_erimaki, "① 狐の襟巻き", dict(top=1.47, ang=25)),
    "tsuru": (look_tsuru, "① 笠の折り鶴", dict(top=1.47, ang=30)),
}
build, label, cam_opt = LOOKS[A.look]
build()

# ================================================================ 描く（光と撮影台は .blend にあるものを使う）
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
sc.eevee.taa_render_samples = A.samples
for attr, v in (("use_raytracing", True), ("use_shadows", True), ("use_gtao", True)):
    if hasattr(sc.eevee, attr):
        setattr(sc.eevee, attr, v)
rx, ry = (int(v) for v in A.size.split("x"))
sc.render.resolution_x, sc.render.resolution_y = rx, ry
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast"
sc.view_settings.exposure = -0.45

cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
cam.data.lens = 80
sc.camera = cam
top = cam_opt["top"]
tgt = V(cam_opt.get("dx", 0.0), 0, top * 0.52)
a = math.radians(cam_opt["ang"])
dist = top * 3.3 * cam_opt.get("dist", 1.0)
cam.location = tgt + V(math.sin(a) * dist, math.cos(a) * dist, top * cam_opt.get("lift", 0.18))
d = tgt - cam.location
cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, math.atan2(d.y, d.x) - math.pi / 2)
bg = bpy.data.objects["Plane"]
bg.rotation_euler = (0, 0, -a)
bg.scale = (2.5, 2.5, 2.5)   # 背中から撮っても撮影台の端が入らないように

# 下に名札（カメラに付けた板と文字。光に左右されないよう発光で）
font = None
for fn in ("Noto Sans CJK Regular.woff2",):
    for base in (os.path.dirname(bpy.app.binary_path) + "/../Resources",):
        for ver in os.listdir(base):
            p = os.path.join(base, ver, "datafiles", "fonts", fn)
            if os.path.exists(p):
                font = bpy.data.fonts.load(p)
cu = bpy.data.curves.new("label", "FONT")
cu.body = label
cu.align_x = "CENTER"
cu.size = 0.03
if font:
    cu.font = font
txt = link(bpy.data.objects.new("label", cu))
txt.data.materials.append(glow("label_ink", "2B211C", 1.0))
txt.parent = cam
txt.location = (0, -0.2, -1.0)
bpy.ops.mesh.primitive_plane_add(size=1)
plate = bpy.context.object
plate.data.materials.append(glow("label_plate", "F3EDE2", 2.4))
plate.parent = cam
plate.location = (0, -0.19, -1.001)
plate.scale = (0.36, 0.04, 1)

sc.render.filepath = os.path.abspath(A.out)
bpy.ops.render.render(write_still=True)
print("wrote", sc.render.filepath)
