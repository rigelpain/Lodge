"""人の 3 つの見本を Blender で組んで描く。外の素材は使わず、形も柄もコードで作る。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/build_dolls.py -- --doll origami --views quarter,front --prefix person/renders/02

--doll
  kasa     ① 笠と千代紙の人形: 黄色い紙の笠、閉じた目の小さな顔、黒い紙の長い髪、千代紙を重ねて折った着物
  origami  ② 多面体の折り紙の人: 大きな平らな面と稜線。白・クリーム・青の紙、頭巾、エプロン
  news     ③ 新聞紙と麻布の人形: 新聞紙を貼った張り子の頭と体、大きなボタンの目、毛羽立った麻布の頭巾と上着

形の作り方: 部品ごとに要の点を決め、それを包む凸の多面体にする（大きな平面と鋭い稜線）。
紙の板は表が柄、裏と縁が白。面ごとに明るさを少しずつ変える（折った面の光の違い）。
向き: 前は +Y。
"""
import argparse
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ap = argparse.ArgumentParser()
ap.add_argument("--doll", default="origami", choices=("kasa", "origami", "news"))
ap.add_argument("--views", default="quarter,front")
ap.add_argument("--prefix", default="/tmp/doll")
ap.add_argument("--size", default="800x1000")
ap.add_argument("--samples", type=int, default=96)
ap.add_argument("--blend", default="")
ap.add_argument("--export", default="", help="骨を入れ、質感を焼いて、このフォルダに <doll>.glb を書き出す（描画しない）")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
HERE = os.path.dirname(os.path.abspath(__file__))
RND = random.Random(11)


def lin(h):
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


# ================================================================ 柄（千代紙）を numpy で描く
def pattern_image(name, kind, base, ink, px=512, accent=None):
    """kind: seigaiha 青海波 / kikko 亀甲 / shippo 七宝 / sakura 桜 / asanoha 麻の葉。色は sRGB の 16 進"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    m = np.zeros((px, px), np.float32)   # 1 で墨
    a2 = None
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
    elif kind == "kikko":
        s = 6
        q = np.stack([x * s * 1.1547, y * s + x * s * 0.57735])
        f = [np.abs((q[0] % 1) - 0.5), np.abs((q[1] % 1) - 0.5), np.abs(((q[0] + q[1]) % 1) - 0.5)]
        e = np.minimum(np.minimum(f[0], f[1]), f[2])
        m = (e < 0.045).astype(np.float32)
    elif kind == "shippo":
        r = 1 / 8
        m = np.zeros((px, px))
        for j in range(-1, 9):
            for i in range(-1, 9):
                for ox, oy in ((0, 0), (r, r)):
                    d = np.hypot(x - (i * 2 * r + ox), y - (j * 2 * r + oy))
                    m = np.maximum(m, (np.abs(d - r * 1.414) < 0.006).astype(np.float32))
    elif kind == "sakura":
        rng = np.random.default_rng(4)
        a2 = np.zeros((px, px), np.float32)
        for _ in range(26):
            cx, cy = rng.random(2)
            rr = rng.uniform(0.035, 0.07)
            rot = rng.uniform(0, 6.28)
            dx = ((x - cx + 0.5) % 1) - 0.5
            dy = ((y - cy + 0.5) % 1) - 0.5
            th = np.arctan2(dy, dx) + rot
            d = np.hypot(dx, dy)
            petal = rr * (0.55 + 0.45 * np.abs(np.cos(2.5 * th)))
            m = np.maximum(m, (d < petal).astype(np.float32))
            a2 = np.maximum(a2, (d < rr * 0.18).astype(np.float32))
    elif kind == "asanoha":
        s = 4
        u = x * s
        v = y * s / 0.866
        for k in range(3):
            ang = k * math.pi / 3
            t = (u * math.cos(ang) + v * 0.866 * math.sin(ang)) * 2
            m = np.maximum(m, (np.abs((t % 1) - 0.5) < 0.03).astype(np.float32))
        t = (u - v * 0.5) * 2
        m = np.maximum(m, (np.abs(((v * 0.866 / 0.866) * 2 % 1) - 0.5) < 0.0).astype(np.float32))
    b = np.array(lin(base)[:3])
    k = np.array(lin(ink)[:3])
    img = b[None, None] * (1 - m[..., None]) + k[None, None] * m[..., None]
    if a2 is not None and accent:
        c = np.array(lin(accent)[:3])
        img = img * (1 - a2[..., None]) + c[None, None] * a2[..., None]
    rgba = np.concatenate([img, np.ones((px, px, 1))], axis=2)[::-1]
    im = bpy.data.images.new(name, px, px)
    im.colorspace_settings.name = "Linear Rec.709" if "Linear Rec.709" in [c.name for c in im.colorspace_settings.bl_rna.properties["name"].enum_items] else im.colorspace_settings.name
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.pack()
    return im


# ================================================================ 素材
class Mat:
    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        self.t = self.m.node_tree
        self.b = self.t.nodes["Principled BSDF"]

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

    def mix(self, fac, a, b, ao=None, bo=None, blend="MIX"):
        """色を混ぜる。a, b は色のタプルか (node, 出口)"""
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


def fiber_bump(M, co, strength=0.12, scale=380.0):
    """紙の繊維: 細かいノイズに、細長い繊維の筋（引き伸ばしたボロノイ）を足す"""
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
    """紙: 表は色か柄、裏は白。面ごとの明るさの違い（tint 属性）、繊維の凹凸、わずかな透け"""
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
    # tint は 0.5 が中立。明るさを (1 ± tint) 倍
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
    """麻布: 縦糸と横糸が上下に入れ替わる太い織り目、糸の太さのむら、毛羽の光（シーン）"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    sep = M.n("ShaderNodeSeparateXYZ")
    M.l(co, 0, sep, 0)
    # 箱の投影の代わりに、面の向きでおおまかに 2 軸を選ぶ（球に近い形ならこれで十分）
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


def newsprint_paste(name, image):
    """新聞紙を貼った張り子: 細胞状に区切った片ごとに、新聞の向きと位置を変え、継ぎ目に少し影"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    vo = M.n("ShaderNodeTexVoronoi", Scale=6.0, Randomness=0.9)
    M.l(co, 0, vo, "Vector")
    ang = M.n("ShaderNodeMath", operation="MULTIPLY")
    sepc = M.n("ShaderNodeSeparateColor")
    M.l(vo, "Color", sepc, 0)
    M.l(sepc, 0, ang, 0)
    ang.inputs[1].default_value = 6.283
    off = M.n("ShaderNodeVectorMath", operation="SCALE")
    M.l(vo, "Color", off, 0)
    off.inputs["Scale"].default_value = 3.0
    rot = M.n("ShaderNodeVectorRotate", rotation_type="Y_AXIS")
    sc2 = M.n("ShaderNodeVectorMath", operation="SCALE")
    M.l(co, 0, sc2, 0)
    sc2.inputs["Scale"].default_value = 0.75
    M.l(sc2, 0, rot, "Vector")
    M.l(ang, 0, rot, "Angle")
    add = M.n("ShaderNodeVectorMath", operation="ADD")
    M.l(rot, 0, add, 0)
    M.l(off, 0, add, 1)
    tex = M.n("ShaderNodeTexImage", projection="BOX", projection_blend=0.3)
    tex.image = image
    M.l(add, 0, tex, "Vector")
    # 裏の印刷がうっすら透ける（鏡に映した同じ紙を薄く重ねる）
    mir = M.n("ShaderNodeMapping")
    mir.inputs["Scale"].default_value = (-1.0, 1.0, 1.0)
    mir.inputs["Location"].default_value = (0.37, 0.11, 0.0)
    M.l(add, 0, mir, "Vector")
    tex2 = M.n("ShaderNodeTexImage", projection="BOX", projection_blend=0.3)
    tex2.image = image
    M.l(mir, 0, tex2, "Vector")
    thru = M.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    thru.inputs[0].default_value = 0.14
    M.l(tex, "Color", thru, 6)
    M.l(tex2, "Color", thru, 7)
    # 新聞の紙: 灰色の細かい粒と、繊維のむら
    sp = M.n("ShaderNodeTexNoise", Scale=900.0, Detail=2.0)
    M.l(co, 0, sp, "Vector")
    spr = M.n("ShaderNodeMapRange")
    M.l(sp, "Fac", spr, 0)
    spr.inputs["From Min"].default_value = 0.62
    spr.inputs["From Max"].default_value = 0.72
    spr.inputs["To Min"].default_value = 1.0
    spr.inputs["To Max"].default_value = 0.8
    speck = M.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    speck.inputs[0].default_value = 1.0
    M.l(thru, 2, speck, 6)
    spc = M.n("ShaderNodeCombineColor")
    for k in range(3):
        M.l(spr, 0, spc, k)
    M.l(spc, 0, speck, 7)
    # 片の縁の影（重なり）と、紙の黄ばみのむら
    ed = M.n("ShaderNodeTexVoronoi", Scale=6.0, Randomness=0.9)
    ed.feature = "DISTANCE_TO_EDGE"
    M.l(co, 0, ed, "Vector")
    rmp = M.n("ShaderNodeMapRange")
    M.l(ed, "Distance", rmp, 0)
    rmp.inputs["From Max"].default_value = 0.06
    rmp.inputs["To Min"].default_value = 0.72
    shade = M.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    shade.inputs[0].default_value = 1.0
    M.l(speck, 2, shade, 6)
    cm = M.n("ShaderNodeCombineColor")
    for k in range(3):
        M.l(rmp, 0, cm, k)
    M.l(cm, 0, shade, 7)
    M.l(shade, 2, M.b, "Base Color")
    # しわ: 片ごとに向きの違う大きな折れと、細かな繊維
    bp = M.n("ShaderNodeBump", Strength=0.55, Distance=0.004)
    wr = M.n("ShaderNodeTexVoronoi", Scale=26.0, Randomness=1.0)
    wr.feature = "F2"
    M.l(co, 0, wr, "Vector")
    fb = M.n("ShaderNodeTexNoise", Scale=500.0, Detail=8.0, Roughness=0.7)
    M.l(co, 0, fb, "Vector")
    hh = M.n("ShaderNodeMath", operation="ADD")
    M.l(wr, "Distance", hh, 0)
    M.l(rmp, 0, hh, 1)
    h2 = M.n("ShaderNodeMath", operation="MULTIPLY_ADD")
    M.l(fb, "Fac", h2, 0)
    h2.inputs[1].default_value = 0.25
    M.l(hh, 0, h2, 2)
    M.l(h2, 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 0.95
    M.b.inputs["Specular IOR Level"].default_value = 0.08
    M.b.inputs["Subsurface Weight"].default_value = 0.05
    return M.m


def plain(name, color, rough=0.6, coat=0.0):
    M = Mat(name)
    M.b.inputs["Base Color"].default_value = lin(color)
    M.b.inputs["Roughness"].default_value = rough
    if coat:
        M.b.inputs["Coat Weight"].default_value = coat
        M.b.inputs["Coat Roughness"].default_value = 0.08
    return M.m


# ================================================================ 形の小道具
def link(ob):
    sc.collection.objects.link(ob)
    return ob


def add_tint(me, seed):
    """面ごとの明るさの違い（0〜1、0.5 が中立）"""
    rnd = random.Random(seed)
    at = me.attributes.get("tint") or me.attributes.new("tint", "FLOAT", "FACE")
    at.data.foreach_set("value", [rnd.random() for _ in me.polygons])


def finish(ob, mat, smooth=False, seed=0):
    ob.data.materials.clear()
    if isinstance(mat, (list, tuple)):
        for m in mat:
            ob.data.materials.append(m)
    else:
        ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = smooth
    add_tint(ob.data, seed)
    return ob


def hull(name, pts, mat, seed=0):
    """点を包む凸の多面体（折り紙の大きな面）"""
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return finish(link(bpy.data.objects.new(name, me)), mat, seed=seed)


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


def tube(name, pts, radii, sides, mat, seed=0, flat=True, twist=0.0):
    """折れ線に沿った角筒（腕・脚）。関節は折り目"""
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
            ang = 2 * math.pi * (a + 0.5) / sides + twist
            rr = r if isinstance(r, float) else (r[0] * math.cos(ang) ** 2 + r[1] * math.sin(ang) ** 2) ** 0.5
            ring.append(pts[k] + (u * math.cos(ang) + v * math.sin(ang)) * rr)
        rings.append(ring)
    verts = [p for ring in rings for p in ring]
    faces = []
    for k in range(n - 1):
        for a in range(sides):
            b = (a + 1) % sides
            faces.append((k * sides + a, k * sides + b, (k + 1) * sides + b, (k + 1) * sides + a))
    faces.append(tuple(range(sides))[::-1])
    faces.append(tuple((n - 1) * sides + a for a in range(sides)))
    ob = mesh(name, verts, faces, mat, not flat, seed)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    add_tint(me, seed)
    for p in me.polygons:
        p.use_smooth = not flat
    return ob


def V(*a):
    return Vector(a)


def surface_hit(ob, origin, direction):
    """ob の表面で、origin から direction に進んで当たる所と外向きの法線（世界座標）"""
    inv = ob.matrix_world.inverted()
    ok, loc, nrm, _ = ob.ray_cast(inv @ origin, (inv.to_3x3() @ direction).normalized())
    if not ok:
        return origin, -direction
    n = (ob.matrix_world.to_3x3() @ nrm).normalized()
    return ob.matrix_world @ loc, (n if n.dot(direction) < 0 else -n)


def ellipse_pts(c, rx, ry, z, n, rot=0.0, wob=0.0, rnd=None):
    rnd = rnd or RND
    return [c + V(math.cos(rot + 2 * math.pi * i / n) * rx * (1 + rnd.uniform(-wob, wob)),
                  math.sin(rot + 2 * math.pi * i / n) * ry * (1 + rnd.uniform(-wob, wob)), z) for i in range(n)]


# ================================================================ ② 多面体の折り紙の人
def build_origami():
    W = paper("p_white", "F4F0E8")
    C = paper("p_cream", "E9DDC6")
    B = paper("p_blue", "3B5F99", back="EDE7DA", tint=0.06)
    F = paper("p_face", "D9BE97", tint=0.06)
    rnd = random.Random(5)
    # 4 頭身、背 1.45 m。頭は 0.36 m
    # 頭: 鼻すじの稜線、ほお・あごの面、うしろは丸く
    hc = V(0, 0, 1.24)
    head = [hc + V(0, 0.02, 0.18), hc + V(0, 0.13, 0.1), hc + V(0, 0.165, -0.01), hc + V(0, 0.12, -0.12),
            hc + V(0, 0.06, -0.165), hc + V(0.09, 0.09, -0.12), hc + V(-0.09, 0.09, -0.12),
            hc + V(0.15, 0.07, 0.02), hc + V(-0.15, 0.07, 0.02), hc + V(0.13, 0.06, 0.12), hc + V(-0.13, 0.06, 0.12),
            hc + V(0.14, -0.06, 0.06), hc + V(-0.14, -0.06, 0.06), hc + V(0.1, -0.1, -0.08), hc + V(-0.1, -0.1, -0.08),
            hc + V(0, -0.15, 0.04), hc + V(0, -0.08, 0.17), hc + V(0.05, 0.13, 0.05), hc + V(-0.05, 0.13, 0.05)]
    hob = hull("head", head, F, 1)
    # 目: 鼻すじの両脇に、折り紙らしい小さなアーモンド形（濃い茶の紙）
    eye_m = plain("eye", "2A1E18", 0.45)
    for s in (1, -1):
        p, n = surface_hit(hob, hc + V(s * 0.055, 0.4, -0.005), V(0, -1, 0))
        u = n.cross(V(0, 0, 1)).normalized()
        w_ = u.cross(n).normalized()
        pts = [p + n * 0.003 + u * (math.cos(a) * 0.026) + w_ * (math.sin(a) * 0.016 * (1.0 if math.sin(a) > 0 else 0.7))
               for a in [2 * math.pi * k / 6 for k in range(6)]]
        mesh("eye", pts, [tuple(range(6))], eye_m, seed=20)
    # 髪: 濃い茶の紙。頭巾の下から前髪と横の髪がのぞく
    hair = paper("p_hair", "4A3326", back="5A4232", tint=0.06, rough=0.7)
    hull("bangs", [hc + V(x, y, z) for x in (-0.12, 0.0, 0.12) for y in (0.115, 0.16) for z in (0.045, 0.13)] + [hc + V(0, 0.17, 0.03)], hair, 21)
    for s in (1, -1):
        hull("lock", [hc + V(s * x, y, z) for x in (0.11, 0.15) for y in (0.03, 0.12) for z in (-0.11, 0.1)] + [hc + V(s * 0.13, 0.1, -0.15)], hair, 22)
    # 頭巾: 頭を包む一枚。ひさしを前に出して、おでこまで深くかぶる。あごの下で合わせ、肩へ広がる。縁は折り返して白
    hood = [hc + V(0, 0.05, 0.25), hc + V(0.15, 0.05, 0.2), hc + V(-0.15, 0.05, 0.2), hc + V(0.18, -0.05, 0.12), hc + V(-0.18, -0.05, 0.12),
            hc + V(0.17, -0.14, -0.02), hc + V(-0.17, -0.14, -0.02), hc + V(0, -0.2, 0.06), hc + V(0, -0.17, -0.16),
            hc + V(0.19, -0.02, -0.12), hc + V(-0.19, -0.02, -0.12), hc + V(0.17, 0.09, -0.08), hc + V(-0.17, 0.09, -0.08),
            hc + V(0.22, 0.0, -0.26), hc + V(-0.22, 0.0, -0.26), hc + V(0, -0.14, -0.3), hc + V(0.0, 0.12, -0.24),
            hc + V(0.14, 0.13, 0.08), hc + V(-0.14, 0.13, 0.08),
            hc + V(0.13, 0.2, 0.1), hc + V(-0.13, 0.2, 0.1), hc + V(0, 0.215, 0.13)]
    hd = hull("hood", hood, [W, W], 2)
    bm = bmesh.new()
    bm.from_mesh(hd.data)
    kill = [f for f in bm.faces if f.normal.y > 0.35 and hc.z - 0.17 < f.calc_center_median().z < hc.z + 0.06 and abs(f.calc_center_median().x) < 0.14]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(hd.data)
    bm.free()
    add_tint(hd.data, 2)
    thicken(hd, 0.008)
    # 胴（ブラウス）: 肩の張った、前に面のある多面体
    tz = 0.98
    torso = [V(0.17, 0, tz), V(-0.17, 0, tz), V(0.12, 0.09, tz - 0.02), V(-0.12, 0.09, tz - 0.02), V(0.12, -0.09, tz - 0.01), V(-0.12, -0.09, tz - 0.01),
             V(0.06, 0.03, tz + 0.06), V(-0.06, 0.03, tz + 0.06), V(0.14, 0.08, 0.78), V(-0.14, 0.08, 0.78), V(0.14, -0.08, 0.78), V(-0.14, -0.08, 0.78),
             V(0, 0.12, 0.86), V(0, -0.1, 0.86)]
    hull("blouse", torso, W, 3)
    # スカート: 腰からくるぶしまで。すそはひだ（山と谷を交互に）
    waist = 0.8
    hem = 0.07
    n = 14
    verts = []
    faces = []
    for i in range(n):
        a = 2 * math.pi * i / n
        verts.append(V(math.cos(a) * 0.15, math.sin(a) * 0.11, waist))
    for i in range(n):
        a = 2 * math.pi * i / n
        r = 0.34 if i % 2 == 0 else 0.29
        verts.append(V(math.cos(a) * r, math.sin(a) * r * 0.85 + 0.02, hem + (0.015 if i % 2 else 0.0)))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    faces.append(tuple(range(n))[::-1])
    faces.append(tuple(range(n, 2 * n)))
    sk = mesh("skirt", verts, faces, C, seed=4)
    sk.modifiers.new("tri", "TRIANGULATE")
    # エプロン: 胸当てと前掛け。紙の板を少し折って前に重ねる
    ap_ = [V(-0.11, 0.115, 0.98), V(0.11, 0.115, 0.98), V(0.13, 0.12, 0.82), V(0.25, 0.27, 0.26), V(0.0, 0.31, 0.24),
           V(-0.25, 0.27, 0.26), V(-0.13, 0.12, 0.82)]
    apron = mesh("apron", ap_ + [V(0, 0.15, 0.6)], [(0, 1, 2, 6), (6, 2, 7), (2, 3, 4, 7), (6, 7, 4, 5)], [B, W], seed=5)
    thicken(apron, 0.005)
    # 腕: 肩から手首まで一本の角筒（袖は白、ひじで折れる）。手は面で作った小さな手
    for s in (1, -1):
        sh = V(0.17 * s, 0.0, 0.96)
        el = V(0.22 * s, 0.07, 0.74)
        wr = V(0.12 * s, 0.2, 0.68)
        tube("arm." + str(s), [sh + V(-0.03 * s, 0, 0), sh, el, wr], [0.062, 0.062, 0.056, 0.048], 5, W, seed=6 + s)
        hd_c = wr + V(-0.02 * s, 0.04, 0.0)
        hull("hand." + str(s), [hd_c + V(0.025, 0.0, 0.025), hd_c + V(-0.025, 0.0, 0.025), hd_c + V(0.02, 0.02, -0.03),
                                hd_c + V(-0.02, 0.0, -0.03), hd_c + V(0, 0.055, 0.0), hd_c + V(0.0, -0.025, 0.0), hd_c + V(-0.03 * s, 0.03, 0.02)], F, 8)
        # 靴: くるぶしからつま先へ折った舟形
        f = V(0.08 * s, 0.03, 0.0)
        hull("shoe." + str(s), [f + V(0.04, -0.06, 0.0), f + V(-0.04, -0.06, 0.0), f + V(0.045, 0.09, 0.0), f + V(-0.04, 0.1, 0.0),
                                 f + V(0.0, 0.16, 0.015), f + V(0.03, -0.04, 0.07), f + V(-0.03, -0.04, 0.07), f + V(0, 0.06, 0.05)], C, 9)
    # 首まわりの巻き布: 頭巾の端をあごの下で重ねて、首を隠す
    for s in (1, -1):
        wrap = mesh("wrap", [V(s * 0.16, 0.0, 1.1), V(-s * 0.02, 0.12, 1.08), V(-s * 0.1, 0.1, 0.97), V(s * 0.14, -0.02, 0.95)], [(0, 1, 2, 3)], [W, W], seed=11 + s)
        thicken(wrap, 0.008)
    # 首
    hull("neck", ellipse_pts(V(0, 0, 1.03), 0.035, 0.035, 0, 5) + ellipse_pts(V(0, 0.005, 1.11), 0.03, 0.03, 0, 5), F, 10)


# ================================================================ ① 笠と千代紙の人形
def build_kasa():
    yellow = paper("p_kasa", "D2A436", tint=0.05, fiber=0.18)
    face = paper("p_face", "F0D2A6", tint=0.03)
    hair = paper("p_hair", "1F1B1E", back="2A2528", tint=0.05, rough=0.7)
    teal = paper("p_teal", image=pattern_image("seigaiha", "seigaiha", "3E7F86", "6FA9AD"), img_scale=2.0)
    blue = paper("p_blue", image=pattern_image("kikko", "kikko", "2F5A8F", "5D86B8"), img_scale=3.0)
    green = paper("p_lace", image=pattern_image("sakura", "sakura", "3E6E66", "CFE0D6", accent="E8EFE6"), img_scale=1.6)
    white = paper("p_collar", "F1ECE2")
    red = paper("p_obi", image=pattern_image("shippo", "shippo", "B23A2E", "E58A62"), img_scale=3.5)
    ink = plain("ink", "3A2420", 0.5)
    blush = plain("blush", "E59C86", 0.8)
    # 3 頭身、背 1.25 m（笠の先まで 1.45 m）。頭は 0.4 m
    hc = V(0, 0.0, 1.02)
    # 頭はうしろもてっぺんもある丸ごとの形。顔の前は平らに
    head_pts = [hc + V(0, 0.05, -0.16), hc + V(0, -0.02, 0.17), hc + V(0, 0.135, 0.0)] + \
        ellipse_pts(hc + V(0, 0.02, -0.1), 0.095, 0.1, 0, 7) + ellipse_pts(hc + V(0, 0.0, -0.02), 0.13, 0.13, 0, 9, 0.2) + \
        ellipse_pts(hc + V(0, -0.01, 0.07), 0.13, 0.13, 0, 9) + ellipse_pts(hc + V(0, -0.02, 0.14), 0.09, 0.09, 0, 7) + \
        [hc + V(sx * 0.07, 0.13, z) for sx in (1, -1) for z in (0.03, -0.05)]
    head = hull("head", head_pts, face, 1)
    # 髪の帽子: 黒い紙で頭のてっぺんとうしろを覆う。前髪は眉の高さで切りそろえる
    cap = ellipse_pts(hc + V(0, -0.005, 0.045), 0.145, 0.15, 0, 12) + ellipse_pts(hc + V(0, -0.02, 0.15), 0.115, 0.115, 0, 9) + \
        [hc + V(0, -0.02, 0.19)] + [p for p in ellipse_pts(hc + V(0, -0.02, -0.07), 0.145, 0.14, 0, 12) if p.y < hc.y - 0.02]
    hull("hair_cap", cap, hair, 13)
    # 閉じた目: 下へふくらむ細い弧（曲線に太さ）
    for s in (1, -1):
        cu = bpy.data.curves.new("eye", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = 0.0045
        sp = cu.splines.new("POLY")
        pts = []
        for k in range(7):
            t = -1 + 2 * k / 6
            pts.append(hc + V(s * 0.05 + t * 0.03, 0.134 - 0.01 * t * t, 0.0 - 0.012 * (1 - t * t)))
        sp.points.add(len(pts) - 1)
        for p, q in zip(sp.points, pts):
            p.co = (*q, 1)
        e = link(bpy.data.objects.new("eye", cu))
        e.data.materials.append(ink)
        bpy.ops.mesh.primitive_circle_add(vertices=10, radius=0.022, fill_type="NGON", location=hc + V(s * 0.075, 0.122, -0.04))
        b = bpy.context.object
        b.rotation_euler = (math.pi / 2, 0, s * 0.35)
        b.data.materials.append(blush)
    # 髪: 黒い紙の板。うしろは腰まで、両脇は顔を縁取って胸まで。前髪は笠の下に隠れる
    back = [V(-0.17, -0.06, 1.15), V(0.17, -0.06, 1.15), V(0.2, -0.1, 0.62), V(0.0, -0.13, 0.58), V(-0.2, -0.1, 0.62)]
    hb = mesh("hair_back", back + [V(0, -0.14, 0.95)], [(0, 1, 5), (1, 2, 5), (2, 3, 5), (3, 4, 5), (4, 0, 5)], [hair, hair], seed=2)
    thicken(hb, 0.012)
    for s in (1, -1):
        side = [V(s * 0.12, 0.06, 1.13), V(s * 0.17, -0.02, 1.12), V(s * 0.19, 0.0, 0.8), V(s * 0.14, 0.08, 0.78)]
        hs = mesh("hair_side", side + [V(s * 0.155, 0.02, 0.97)], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], [hair, hair], seed=3)
        thicken(hs, 0.012)
    # 笠: 浅い円錐を、山と谷を交互に折った放射の面で
    n = 24
    rim_z = hc.z + 0.05           # 笠の縁は目の少し上
    tip = V(0, 0.0, rim_z + 0.3)
    rim = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = 0.43 if i % 2 == 0 else 0.4
        rim.append(V(math.cos(a) * r, math.sin(a) * r, rim_z + (0.0 if i % 2 == 0 else 0.012)))
    k = mesh("kasa", [tip] + rim, [(0, 1 + (i + 1) % n, 1 + i) for i in range(n)], [yellow, yellow], seed=4)
    thicken(k, 0.008)
    # 頭当ての輪: 笠の内側から下りて、髪の上に乗る
    ring_r = 0.105
    z_top = tip.z - 0.3 * ring_r / 0.43 - 0.006
    z_bot = hc.z + 0.16
    rv, rf = [], []
    for i in range(12):
        a = 2 * math.pi * i / 12
        rv += [V(math.cos(a) * ring_r, math.sin(a) * ring_r - 0.01, z_bot), V(math.cos(a) * ring_r, math.sin(a) * ring_r - 0.01, z_top)]
    for i in range(12):
        j = (i + 1) % 12
        rf.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
    ring = mesh("kasa_ring", rv, rf, [plain("ring", "4A3A2E", 0.9)], seed=14)
    thicken(ring, 0.01, rim_white=False)
    # 着物: すそへ広がる芯（青緑の青海波）、前の身頃を左が上に斜めに重ね、襟は白と青の二重
    body = ellipse_pts(V(0, 0, 0.84), 0.13, 0.09, 0, 6) + ellipse_pts(V(0, 0, 0.05), 0.27, 0.2, 0, 8, 0.2)
    hull("kimono", body, teal, 5)
    for s, mat, z0 in ((1, white, 0.0), (1, blue, 0.012)):
        pass
    # 前の身頃（左上）: 右肩から左のすそへ斜めに折った一枚
    for s, mat, dy in ((-1, blue, 0.0), (1, green, 0.012)):
        pts = [V(s * 0.03, 0.095, 0.86), V(-s * 0.14, 0.06, 0.84), V(-s * 0.3, 0.17, 0.05), V(s * 0.06, 0.25 + dy, 0.05), V(s * 0.0, 0.16 + dy, 0.5)]
        pn = mesh("panel", pts, [(0, 1, 4), (1, 2, 4), (2, 3, 4)], [mat, white], seed=6 + s)
        thicken(pn, 0.006)
    # 襟（白と青）
    for s in (1, -1):
        col = mesh("collar", [V(0, 0.1, 0.88), V(s * 0.06, 0.09, 0.88), V(-s * 0.02, 0.15, 0.62), V(-s * 0.05, 0.15, 0.62)], [(0, 1, 2, 3)], [white, white], seed=8)
        thicken(col, 0.004)
    # 帯（赤）
    obi = ellipse_pts(V(0, 0.01, 0.66), 0.155, 0.13, 0, 8) + ellipse_pts(V(0, 0.01, 0.56), 0.165, 0.14, 0, 8)
    hull("obi", obi, red, 9)
    # 袖: 大きな四角い板を胸の前で合わせ、手は隠す。ひじで折れる
    for s, mat in ((1, green, ), (-1, blue)):
        sh = V(0.13 * s, 0.0, 0.84)
        sl = [sh, sh + V(0.13 * s, 0.05, -0.12), sh + V(0.11 * s, 0.12, -0.42), V(0.02 * s, 0.24, 0.48), V(0.0 * s, 0.17, 0.62), sh + V(0.0, 0.08, -0.06)]
        sv = mesh("sleeve", sl, [(0, 1, 5), (1, 2, 5), (2, 3, 5), (3, 4, 5)], [mat, white], seed=10 + s)
        thicken(sv, 0.008)
    # 足もと: 小さな黒い草履の先だけ
    for s in (1, -1):
        hull("geta", ellipse_pts(V(0.06 * s, 0.1, 0.0), 0.04, 0.06, 0, 6) + ellipse_pts(V(0.06 * s, 0.1, 0.04), 0.03, 0.05, 0, 6), hair, 12)


# ================================================================ ③ 新聞紙と麻布の人形
def build_news():
    img = bpy.data.images.load(os.path.join(HERE, "textures", "newsprint.png"))
    news = newsprint_paste("p_news", img)
    green = burlap("burlap_green", "66773F", 520.0)
    brown = burlap("burlap_brown", "5A4634", 600.0)
    strap = plain("strap", "8A4E2E", 0.7)
    button = plain("button", "0B0B0C", 0.18, coat=1.0)
    thread = plain("thread", "C9B48A", 0.9)
    shine = plain("eye_shine", "FFFFFF", 0.3)
    dark = plain("sleeve_in", "2A2016", 0.95)
    # 2.5 頭身、背 1.0 m。頭は少し前後につぶれた張り子の丸。頭巾に包まれ、新聞紙は顔の窓にだけ見える
    hc = V(0, 0.0, 0.73)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=0.175, location=hc)
    head = bpy.context.object
    head.name = "head"
    head.scale = (1.0, 0.9, 0.95)
    finish(head, news, smooth=True, seed=1)
    face_y = 0.175 * 0.9
    # 目: つやのある黒いボタン。顔の幅の 1/5 ほど、少し離して、顔のまん中より少し下。
    # 光の点を描き込む（ゲームの光でも、いつも目が濡れて見えるように）
    for s in (1, -1):
        p = hc + V(s * 0.07, face_y - 0.014, -0.028)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.034, location=p)
        e = bpy.context.object
        e.name = "eye"
        e.scale = (1, 0.5, 1)
        d = (p - hc).normalized()
        e.rotation_euler = Vector((0, 1, 0)).rotation_difference(d).to_euler()
        finish(e, button, smooth=True)
        for off, r in ((V(-0.011, 0.0, 0.012), 0.0085), (V(0.008, 0.0, -0.009), 0.004)):
            bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=r, location=p + d * 0.016 + off)
            h = bpy.context.object
            h.name = "eyeshine"
            h.scale = (1, 0.4, 1)
            finish(h, shine, smooth=True)
    # 頭巾: 麻布。頭をふっくら丸く包む厚い頭巾で、ふちは前へ張り出し、顔は奥まった丸い窓からのぞく。
    # とんがりは、うしろの上から出て、うしろへ折れて垂れる
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=1.0)
    hd = bpy.context.object
    hd.name = "hood"
    tipdir = V(0, -0.55, 0.84).normalized()
    R = 0.212
    bm = bmesh.new()
    bm.from_mesh(hd.data)
    for v in bm.verts:
        c = v.co.copy()
        if c.y > 0.35:
            c.y += (c.y - 0.35) * 0.55   # ふちを前へ
        a_ = c.normalized().dot(tipdir)
        if a_ > 0.8:
            t = (a_ - 0.8) / 0.2
            c += tipdir * 1.0 * t * t
            c.y -= 0.6 * t ** 3          # うしろへ折れて垂れる
            c.z -= 0.35 * t ** 3
        v.co = V(c.x * R, c.y * R * 0.95, c.z * R)
    kill = [f for f in bm.faces if (f.calc_center_median().y > 0.1 and f.calc_center_median().x ** 2 + ((f.calc_center_median().z + 0.01) / 1.05) ** 2 < 0.122 ** 2)
            or f.calc_center_median().z < -0.165]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(hd.data)
    bm.free()
    hd.location = hc + V(0, -0.004, 0.018)
    finish(hd, green, smooth=True, seed=2)
    m = hd.modifiers.new("sol", "SOLIDIFY")
    m.thickness = 0.03
    m.offset = 1.0
    m2 = hd.modifiers.new("sub", "SUBSURF")
    m2.levels = 1
    m2.render_levels = 2
    # 上着: 麻布の短いケープ（肩から腰まで）
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.245, radius2=0.1, depth=0.25, location=(0, 0, 0.46))
    cape = bpy.context.object
    cape.name = "cape"
    finish(cape, green, smooth=True, seed=3)
    bm = bmesh.new()
    bm.from_mesh(cape.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.z) > 0.9], context="FACES")
    for v in bm.verts:
        v.co.x += RND.uniform(-0.008, 0.008)
        v.co.y += RND.uniform(-0.008, 0.008)
    bm.to_mesh(cape.data)
    bm.free()
    m = cape.modifiers.new("sol", "SOLIDIFY")
    m.thickness = 0.016
    m2 = cape.modifiers.new("sub", "SUBSURF")
    m2.levels = 1
    m2.render_levels = 2
    # 体とスカート: 新聞紙の張り子。すそへ広がり、ひだが寄る
    bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=0.24, radius2=0.125, depth=0.37, end_fill_type="NOTHING", location=(0, 0, 0.275))
    body = bpy.context.object
    body.name = "body"
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.1], cuts=4)
    for v in bm.verts:
        r = math.hypot(v.co.x, v.co.y)
        if r < 1e-4:
            continue
        th = math.atan2(v.co.y, v.co.x)
        k = (0.185 - v.co.z) / 0.37   # すそほど深いひだ
        f = 1.0 + 0.075 * k * math.sin(11 * th + 0.4 * math.sin(3 * th))
        v.co.x *= f
        v.co.y *= f
    bm.to_mesh(body.data)
    bm.free()
    finish(body, news, smooth=True, seed=4)
    m = body.modifiers.new("sol", "SOLIDIFY")
    m.thickness = 0.008
    m2 = body.modifiers.new("sub", "SUBSURF")
    m2.levels = 1
    m2.render_levels = 1
    for s in (1, -1):
        # 袖: 肩から垂れて、先が少し広がり、手を隠す。袖口の奥は暗い
        tube("sleeve", [V(0.15 * s, 0, 0.55), V(0.215 * s, 0.03, 0.41), V(0.235 * s, 0.065, 0.245)], [0.058, 0.064, 0.078], 14, green, flat=False)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=8, radius=0.05, location=(0.236 * s, 0.066, 0.24))
        inner = bpy.context.object
        inner.name = "sleeve_in"
        inner.scale = (1, 1, 0.35)
        finish(inner, dark, smooth=True)
        # 脚: 麻布を巻いた短い脚と、丸い足
        tube("leg", [V(0.08 * s, 0, 0.12), V(0.085 * s, 0.01, 0.03)], [0.045, 0.048], 12, brown, flat=False)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.055, location=(0.085 * s, 0.03, 0.025))
        f = bpy.context.object
        f.scale = (1, 1.35, 0.6)
        finish(f, brown, smooth=True)
    # 背中の小さなリュック（麻布の袋に革のふた）と、そこにつながる革の肩紐
    def cape_r(z):
        return 0.245 + (0.1 - 0.245) * (z - 0.335) / 0.25

    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -cape_r(0.45) - 0.028, 0.45))
    pack = bpy.context.object
    pack.name = "pack"
    pack.scale = (0.2, 0.085, 0.17)
    bev = pack.modifiers.new("bev", "BEVEL")
    bev.width = 0.02
    bev.segments = 3
    sub = pack.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 2
    finish(pack, brown, smooth=True, seed=5)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -cape_r(0.45) - 0.072, 0.5))
    flap = bpy.context.object
    flap.name = "pack_flap"
    flap.scale = (0.19, 0.012, 0.085)
    flap.rotation_euler = (math.radians(-8), 0, 0)
    bev = flap.modifiers.new("bev", "BEVEL")
    bev.width = 0.004
    finish(flap, strap, smooth=True, seed=6)

    def band(name, path, width=0.034, thick=0.006, per=8):
        """上着の表面に沿う平たい帯。path は (角度°, 高さ, 浮かせる量)。角度は +X から反時計回り（+Y が前）"""
        def at(th, z, off):
            r = cape_r(z) + off
            a = math.radians(th)
            return V(math.cos(a) * r, math.sin(a) * r, z), V(math.cos(a), math.sin(a), 0.35).normalized()
        pts = []
        for i in range(len(path) - 1):
            for k in range(per):
                u = k / per
                q = [path[max(0, i - 1)], path[i], path[i + 1], path[min(len(path) - 1, i + 2)]]
                # 角度・高さ・浮きを Catmull-Rom でなめらかに
                vals = [0.5 * ((2 * q[1][j]) + (-q[0][j] + q[2][j]) * u + (2 * q[0][j] - 5 * q[1][j] + 4 * q[2][j] - q[3][j]) * u * u
                              + (-q[0][j] + 3 * q[1][j] - 3 * q[2][j] + q[3][j]) * u ** 3) for j in range(3)]
                pts.append(at(*vals))
        pts.append(at(*path[-1]))
        verts, faces = [], []
        for i, (p_, n_) in enumerate(pts):
            nxt = pts[min(i + 1, len(pts) - 1)][0]
            prv = pts[max(i - 1, 0)][0]
            tdir = (nxt - prv).normalized()
            w = tdir.cross(n_).normalized() * width * 0.5
            for side in (w, -w):
                verts.append(p_ + side)
                verts.append(p_ + side + n_ * thick)
        for i in range(len(pts) - 1):
            a0 = i * 4
            b0 = a0 + 4
            faces += [(a0 + 1, a0 + 3, b0 + 3, b0 + 1), (a0, b0, b0 + 2, a0 + 2), (a0, a0 + 1, b0 + 1, b0), (a0 + 2, b0 + 2, b0 + 3, a0 + 3)]
        ob = mesh(name, verts, faces, strap, smooth=True, seed=7)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(ob.data)
        bm.free()
        for pl in ob.data.polygons:
            pl.use_smooth = True
        return ob

    for s in (1, -1):
        # 右（s=1）: リュックの上 → 肩を越えて（頭巾の下）→ 胸の前を下りる → 脇の下（袖の内側）→ リュックの下
        path = [(-78, 0.55, 0.05), (-35, 0.585, 0.012), (15, 0.575, 0.012), (58, 0.5, 0.012), (52, 0.42, 0.012),
                (20, 0.37, 0.006), (-35, 0.37, 0.01), (-72, 0.4, 0.05)]
        if s < 0:
            path = [(180 - th, z, off) for th, z, off in path]
        band("strap", path)
    # 毛羽: 麻布から短い繊維がはみ出す
    for ob in (hd, cape):
        ps_mod = ob.modifiers.new("fuzz", "PARTICLE_SYSTEM")
        ps = ob.particle_systems[-1].settings
        ps.type = "HAIR"
        ps.count = 2500
        ps.hair_length = 0.012
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


# ================================================================ 描く
if A.doll == "origami":
    build_origami()
elif A.doll == "kasa":
    build_kasa()
else:
    build_news()

if A.export:
    sys.path.insert(0, HERE)
    import rig_export
    rig_export.export(A.doll, A.export)
    sys.exit(0)

# 背景: 温かい灰色の布を曲げた撮影台（参照の写真の空気）
bpy.ops.mesh.primitive_plane_add(size=14, location=(0, -1.0, 0))
bg = bpy.context.object
bm = bmesh.new()
bm.from_mesh(bg.data)
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=20, use_grid_fill=True)
for v in bm.verts:
    yy = v.co.y
    if yy < -1.0:
        v.co.z = (abs(yy) - 1.0) ** 2 * 0.8
bm.to_mesh(bg.data)
bm.free()
for p in bg.data.polygons:
    p.use_smooth = True
bg.data.materials.append(plain("backdrop", "CDBBA2" if A.doll != "news" else "6E6A58", 0.95))

w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = lin("D8CCBA")
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22
sc.world = w


def area(name, loc, size, energy, color="FFF1DE"):
    L = bpy.data.lights.new(name, "AREA")
    L.size = size
    L.energy = energy
    L.color = lin(color)[:3]
    o = link(bpy.data.objects.new(name, L))
    o.location = loc
    d = V(0, 0, 0.7) - V(*loc)
    o.rotation_euler = V(0, 0, -1).rotation_difference(d).to_euler()
    return o


# 横からのやわらかい主光、反対から弱い補光、うしろ上から縁の光
area("key", (-1.7, 1.3, 1.8), 1.4, 210)
area("fill", (1.8, 1.7, 0.9), 2.5, 28, "E8EEF8")
area("rim", (0.9, -1.5, 2.1), 0.8, 130)

# Eevee（Cycles の GPU は画面なしで装置を探すところで止まるので使わない）
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
if hasattr(sc.eevee, "ray_tracing_options"):
    sc.eevee.ray_tracing_options.resolution_scale = "1"
rx, ry = (int(v) for v in A.size.split("x"))
sc.render.resolution_x, sc.render.resolution_y = rx, ry
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast"
sc.view_settings.exposure = -0.45

if A.blend:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))

VIEWS = {"front": 0, "quarter": 32, "side": 85, "back": 180, "left": -32, "backq": 145, "low": 20}
cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
cam.data.lens = 80
sc.camera = cam
top = {"origami": 1.45, "kasa": 1.47, "news": 1.02}[A.doll]
tgt = V(0, 0, top * 0.52)
for v in A.views.split(","):
    a = math.radians(VIEWS.get(v, 0))
    dist = top * 3.3
    lift = -top * 0.32 if v == "low" else top * 0.18
    cam.location = tgt + V(math.sin(a) * dist, math.cos(a) * dist, lift)
    bg.rotation_euler = (0, 0, -a)   # 背景の撮影台はいつもカメラの向かい側に
    d = tgt - cam.location
    cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, math.atan2(d.y, d.x) - math.pi / 2)
    sc.render.filepath = os.path.abspath("%s-%s.png" % (A.prefix, v))
    bpy.ops.render.render(write_still=True)
    print("wrote", sc.render.filepath)
