"""新しい人形のラフ（2 回目）。代表の Pinterest のボード「&wind：Lodge キャラ」の意匠を取り、Lodge の素材で描き直す。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/characters/roughs.py -- --doll shinbun --views quarter,front,backq
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/characters/roughs.py -- --lineup --size 2800x1100

--doll
  shinbun  新聞紙の箱頭の子: 新聞紙を折った箱の頭に丸い穴の目、ちぎった新聞の髪。青緑のフェルトの上着はすそが波形、麻ひもの帯
  musha    フェルトの小さな武者: しわの寄ったクラフト紙の顔に糸の目。紺のフェルトの兜に錫色の三日月、吹返しに木のボタン。赤い毛糸の帯
  ningyo   布の人形: 和紙の顔に刺繍の閉じた目。紺の毛糸を巻いたお団子に、フェルトの玉。生成りの木綿に藍の青海波の着物、赤い帯と房
  tabi     旅のおじいさん: 先が巻いた紺のフェルトのとんがり帽、針金の丸眼鏡、綿のひげ。継ぎ当てのフェルトの長いコートと杖
--lineup   いまの 3 体（person/build_dolls.py を読むだけで組む）と 4 体を雪の上に並べる

素材と縫い目は、ソリと同じもの（props/common.py → lodge/materials.py）を読むだけで使う。紙は person/build_dolls.py から写した。
顔は参考のとおり、縫い目・閉じた目・穴・眼鏡で表す（光る目や頬は描かない。口は描かない）。骨はまだ入れない。
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

sys.dont_write_bytecode = True
ap = argparse.ArgumentParser()
ap.add_argument("--doll", default="shinbun", choices=("shinbun", "musha", "ningyo", "tabi"))
ap.add_argument("--views", default="quarter,front,backq")
ap.add_argument("--lineup", action="store_true")
ap.add_argument("--turn", type=float, default=0.0)
ap.add_argument("--size", default="900x1100")
ap.add_argument("--samples", type=int, default=64)
ap.add_argument("--blend", default="")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

HERE = os.path.dirname(os.path.abspath(__file__))
PERSON = os.path.normpath(os.path.join(HERE, "..", ".."))
ROOT = os.path.dirname(PERSON)
OUT = os.path.join(HERE, "renders")
sys.path.insert(0, os.path.join(ROOT, "props"))
import common as C  # noqa: E402  ソリと同じ素材・縫い目・雪・光
LM = C.LM

C.HEX.update({
    "felt_teal": "3E7C84", "felt_teal_dk": "2C5A61", "felt_indigo": "2B3760", "felt_indigo2": "3C4E7C", "felt_rust": "B0553A",
    "felt_denim": "58718F", "felt_grey": "8C877F", "felt_plum": "4E3550", "felt_boot": "4A3A2E", "felt_ink": "1C1A1C",
    "felt_obi": "B23A2E", "felt_cream2": "EDE3CF", "felt_mustard": "C99634", "yarn_indigo": "1E2340", "yarn_cream": "EFE6D2",
    "thread_ink": "1A1716", "thread_cream": "EFE6D2", "wire": "4A3C30",
})


def lin(h):
    return LM.lin(h)


# ================================================================ 紙（person/build_dolls.py から写した）
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

    def mix(self, fac, a, b, blend="MIX"):
        mx = self.n("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        if isinstance(fac, (int, float)):
            mx.inputs[0].default_value = fac
        else:
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


def paper(name, color, back="F6F2EA", rough=0.82, fiber=0.14, crinkle=0.0, sss=0.08):
    """紙: 表は色、裏は白。繊維の凹凸、わずかな透け。crinkle でもんだ紙のしわ"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    bf = M.n("ShaderNodeNewGeometry")
    M.l(M.mix((bf, "Backfacing"), lin(color), lin(back)), 2, M.b, "Base Color")
    bp = fiber_bump(M, co, fiber)
    if crinkle:
        vo = M.n("ShaderNodeTexVoronoi", Scale=14.0, Randomness=1.0)
        vo.feature = "F2"
        M.l(co, 0, vo, "Vector")
        b2 = M.n("ShaderNodeBump", Strength=crinkle, Distance=0.01)
        M.l(vo, "Distance", b2, "Height")
        M.l(bp, 0, b2, "Normal")
        bp = b2
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = rough
    M.b.inputs["Subsurface Weight"].default_value = sss
    M.b.inputs["Subsurface Radius"].default_value = (0.01, 0.008, 0.006)
    M.b.inputs["Specular IOR Level"].default_value = 0.25
    return M.m


def newsprint_paste(name, image):
    """新聞紙を貼った張り子（person/build_dolls.py の ③ と同じ作り）"""
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
    sp = M.n("ShaderNodeTexNoise", Scale=900.0, Detail=2.0)
    M.l(co, 0, sp, "Vector")
    spr = M.n("ShaderNodeMapRange")
    M.l(sp, "Fac", spr, 0)
    spr.inputs["From Min"].default_value = 0.62
    spr.inputs["From Max"].default_value = 0.72
    spr.inputs["To Min"].default_value = 1.0
    spr.inputs["To Max"].default_value = 0.82
    ed = M.n("ShaderNodeTexVoronoi", Scale=6.0, Randomness=0.9)
    ed.feature = "DISTANCE_TO_EDGE"
    M.l(co, 0, ed, "Vector")
    rmp = M.n("ShaderNodeMapRange")
    M.l(ed, "Distance", rmp, 0)
    rmp.inputs["From Max"].default_value = 0.06
    rmp.inputs["To Min"].default_value = 0.72
    mul = M.n("ShaderNodeMath", operation="MULTIPLY")
    M.l(spr, 0, mul, 0)
    M.l(rmp, 0, mul, 1)
    cm = M.n("ShaderNodeCombineColor")
    for k in range(3):
        M.l(mul, 0, cm, k)
    M.l(M.mix(1.0, (tex, "Color"), (cm, 0), "MULTIPLY"), 2, M.b, "Base Color")
    bp = M.n("ShaderNodeBump", Strength=0.5, Distance=0.004)
    wr = M.n("ShaderNodeTexVoronoi", Scale=26.0, Randomness=1.0)
    wr.feature = "F2"
    M.l(co, 0, wr, "Vector")
    hh = M.n("ShaderNodeMath", operation="ADD")
    M.l(wr, "Distance", hh, 0)
    M.l(rmp, 0, hh, 1)
    M.l(hh, 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 0.95
    M.b.inputs["Specular IOR Level"].default_value = 0.08
    M.b.inputs["Subsurface Weight"].default_value = 0.05
    return M.m


def seigaiha_image(base, ink, px=512):
    """青海波（person/build_dolls.py の柄と同じ描き方）"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    r = 1 / 6
    best = np.full((px, px), -1.0)
    dist = np.zeros((px, px))
    for j in range(-1, 14):
        for i in range(-1, 5):
            cx = i * 2 * r + (r if j % 2 else 0)
            cy = j * r * 0.5
            d = np.hypot(((x - cx + 0.5) % 1) - 0.5, y - cy)
            hit = (d < r) & (j >= best)
            best = np.where(hit, j, best)
            dist = np.where(hit, d, dist)
    m = ((((dist / r) * 4) % 1 < 0.2) & (best >= 0)).astype(np.float32)
    b = np.array(lin(base)[:3])
    k = np.array(lin(ink)[:3])
    img = b[None, None] * (1 - m[..., None]) + k[None, None] * m[..., None]
    rgba = np.concatenate([img, np.ones((px, px, 1))], axis=2)[::-1]
    im = bpy.data.images.new("seigaiha", px, px)
    if "Linear Rec.709" in [c.name for c in im.colorspace_settings.bl_rna.properties["name"].enum_items]:
        im.colorspace_settings.name = "Linear Rec.709"
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.pack()
    return im


def printed_cotton(name, image, scale):
    """柄を染めた木綿: 柄の画像、細かな織り目、やわらかい光"""
    M = Mat(name)
    tex = M.n("ShaderNodeTexImage", projection="BOX", projection_blend=0.3)
    tex.image = image
    M.l(M.obj_coords(scale), 0, tex, "Vector")
    M.l(tex, "Color", M.b, "Base Color")
    ck = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X", Scale=900.0)
    M.l(M.obj_coords(1.0), 0, ck, "Vector")
    no = M.n("ShaderNodeTexNoise", Scale=300.0, Detail=6.0)
    M.l(M.obj_coords(1.0), 0, no, "Vector")
    h = M.n("ShaderNodeMath", operation="MULTIPLY_ADD")
    M.l(ck, "Fac", h, 0)
    h.inputs[1].default_value = 0.4
    M.l(no, "Fac", h, 2)
    bp = M.n("ShaderNodeBump", Strength=0.25, Distance=0.002)
    M.l(h, 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 0.92
    M.b.inputs["Sheen Weight"].default_value = 0.5
    M.b.inputs["Specular IOR Level"].default_value = 0.15
    return M.m


def plain(name, color, rough=0.6, metal=0.0):
    M = Mat(name)
    M.b.inputs["Base Color"].default_value = lin(color)
    M.b.inputs["Roughness"].default_value = rough
    M.b.inputs["Metallic"].default_value = metal
    return M.m


def register_paper():
    """紙の素材を props/common.py の役割の表に足す（C.M(…, role) で使えるように）"""
    img = bpy.data.images.load(os.path.join(PERSON, "textures", "newsprint.png"))
    C._MAT.update({
        "news": newsprint_paste("news", img),
        "kraft": paper("kraft", "B98C5E", back="D8C09A", fiber=0.2, crinkle=0.35),
        "washi": paper("washi", "EBD9BC", back="F1E6D2", fiber=0.55, crinkle=0.2, sss=0.15),
        "paper_face": paper("paper_face", "D6B68C", back="E6D3B3", fiber=0.3, crinkle=0.45),
        "hole": plain("hole", "120E0C", 1.0),
        "wire": plain("wire", "3B3028", 0.35, metal=0.8),
        "print": printed_cotton("print", seigaiha_image("EFE6D2", "2E4372"), 4.0),
    })


# ================================================================ 形の道具
def V(*a):
    return Vector(a)


def part(name, role, build, smooth=True, subsurf=0, solid=0.0, fuzz=0.0, fuzz_hex=None):
    """C.M に build(m) で形を作り、厚み（フェルトの板）と毛羽を足す"""
    m = C.M(name, role, "doll")
    build(m)
    o = m.done(smooth=smooth, subsurf=subsurf)
    if solid:
        s = o.modifiers.new("sol", "SOLIDIFY")
        s.thickness = solid
        s.offset = 0.0
        s.use_even_offset = True
        o.modifiers.move(len(o.modifiers) - 1, 0)
    if fuzz:
        C.fuzz(o, fuzz * 0.55, 3, fuzz_hex or C.HEX.get(role), 0.6)
    return o


def sheet_cone(m, prof, n=40, sy=1.0, wave=None, lon=None):
    """（半径, 高さ）を上から下へ並べた輪郭を回した布の板（ふたをしない）。
    wave=(山の数, 深さ) で一番下の縁を波形（スカラップ）に。lon=(始め°, 終わり°) で前をあける"""
    a0, a1 = (0.0, 360.0) if lon is None else lon
    full = lon is None
    cnt = n if full else n + 1
    rows = []
    for k, (r, z) in enumerate(prof):
        row = []
        for i in range(cnt):
            a = math.radians(a0 + (a1 - a0) * i / n)
            zz = z
            if wave and k == len(prof) - 1:
                f = (i * wave[0] / n) % 1
                zz = z - wave[1] * math.sqrt(max(0.0, 1 - (2 * f - 1) ** 2))
            row.append(m.bm.verts.new((math.cos(a) * r, math.sin(a) * r * sy, zz)))
        rows.append(row)
    for k in range(len(rows) - 1):
        for i in range(n):
            j = (i + 1) % cnt
            m.bm.faces.new((rows[k][i], rows[k + 1][i], rows[k + 1][j], rows[k][j]))
    return rows


def lathe_at(m, prof, at, segs=20):
    n0 = len(m.bm.verts)
    C.lathe(m, prof, segs=segs)
    C.place(m, n0, Matrix.Translation(at))


def blob(m, center, half, n_xy=2.4, n_z=2.4, cuts=6, dent=None):
    return C.superellipsoid(m, center, half, n_xy, n_z, cuts, dent=dent)


def ball(m, center, r, sx=1.0, sy=1.0, sz=1.0, seg=16):
    n0 = len(m.bm.verts)
    bmesh.ops.create_uvsphere(m.bm, u_segments=seg, v_segments=seg // 2, radius=1.0)
    for v in C.new_verts(m, n0):
        v.co = Vector(center) + Vector((v.co.x * r * sx, v.co.y * r * sy, v.co.z * r * sz))


def stitch(name, pts, nrm, role="thread_cream", dash=0.018, gap=0.012, r=0.0028):
    m = C.M(name, role, "doll")
    C.running_stitch(m, pts, nrm, dash=dash, gap=gap, r=r)
    return m.done(smooth=False)


def rope(name, role, pts, r=0.008, sides=8):
    m = C.M(name, role, "doll")
    C.tube(m, pts, r, sides=sides)
    return m.done(subsurf=1)


def helix(c, r, z0, z1, turns, n_per=24, sy=1.0):
    pts = []
    N = int(turns * n_per)
    for i in range(N + 1):
        t = i / N
        a = 2 * math.pi * turns * t
        pts.append(Vector(c) + V(math.cos(a) * r, math.sin(a) * r * sy, z0 + (z1 - z0) * t))
    return pts


def button(name, center, normal, r=0.016, role="button"):
    """木のボタン: 平たい円板に 2 つ穴"""
    m = C.M(name, role, "doll")
    n0 = len(m.bm.verts)
    C.lathe(m, [(r, 0.004), (r * 1.05, 0.0), (r, -0.004)], segs=20)
    rot = Vector((0, 0, 1)).rotation_difference(Vector(normal)).to_matrix().to_4x4()
    C.place(m, n0, Matrix.Translation(center) @ rot)
    o = m.done(smooth=True)
    hm = C.M(name + "_holes", "hole", "doll")
    for s in (-1, 1):
        n1 = len(hm.bm.verts)
        C.lathe(hm, [(r * 0.16, 0.0045), (r * 0.16, 0.0)], segs=8)
        C.place(hm, n1, Matrix.Translation(center) @ rot @ Matrix.Translation((s * r * 0.33, 0, 0)))
    hm.done(smooth=False)
    return o


def hit(ob, origin, direction):
    """ob の表面で、origin から direction に進んで当たる所と外向きの法線"""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    oe = ob.evaluated_get(dg)
    inv = ob.matrix_world.inverted()
    ok, loc, nrm, _ = oe.ray_cast(inv @ origin, (inv.to_3x3() @ direction).normalized(), depsgraph=dg)
    if not ok:
        return Vector(origin), -Vector(direction)
    n = (ob.matrix_world.to_3x3() @ nrm).normalized()
    return ob.matrix_world @ loc, (n if n.dot(direction) < 0 else -n)


def on_surface(ob, pts2, axis_origin, toward=V(0, -1, 0), lift=0.003):
    """前から（toward の向きに）面へ落とした点の列と法線"""
    out, nrm = [], []
    for p in pts2:
        q, n = hit(ob, Vector(p) - toward * 0.6, toward)
        out.append(q + n * lift)
        nrm.append(n)
    return out, nrm


def patch(name, role, ob, center, w, h, rot=0.0, thread="thread_cream"):
    """継ぎ当て: 面に沿う小さなフェルトの四角と、まわりのなみ縫い"""
    pts = []
    for i in range(9):
        for j in range(9):
            u, v = (i / 8 - 0.5) * w, (j / 8 - 0.5) * h
            pts.append((center + V(u * math.cos(rot) - v * math.sin(rot) * 0, 0, v + u * math.sin(rot))))
    q, nn = on_surface(ob, pts, center, lift=0.004)

    def b(m):
        vs = [m.bm.verts.new(p) for p in q]
        for i in range(8):
            for j in range(8):
                m.bm.faces.new((vs[i * 9 + j], vs[(i + 1) * 9 + j], vs[(i + 1) * 9 + j + 1], vs[i * 9 + j + 1]))
    o = part(name, role, b, solid=0.005)
    edge = [q[i * 9] for i in range(9)] + [q[72 + j] for j in range(1, 9)] + [q[i * 9 + 8] for i in range(7, -1, -1)] + [q[j] for j in range(7, 0, -1)]
    en = [nn[0]] * len(edge)
    inset = [p + n * 0.004 for p, n in zip(edge, en)]
    stitch(name + "_st", inset, en, thread, dash=0.012, gap=0.009, r=0.0022)
    return o


# ================================================================ A 新聞紙の箱頭の子
def build_shinbun():
    """参考: 新聞紙の箱の頭の騎士（丸い穴の目、ちぎった紙の髪）、フェルトの馬（波形のすそ、銅のボタン）、新聞紙の体。
    取らない: 剣と盾、細すぎる手足。背 1.12 m（髪の先まで）、4 頭身"""
    hc = V(0, 0, 0.885)
    head = part("head", "news", lambda m: blob(m, hc, (0.105, 0.09, 0.125), 8.0, 8.0, 6), subsurf=1)
    # 目: 切り抜いた丸い穴（奥は暗い）と、切り口の紙の縁
    for s in (1, -1):
        p, n = hit(head, hc + V(s * 0.048, 0.5, -0.012), V(0, -1, 0))
        part("eyehole", "hole", lambda m: ball(m, p - n * 0.004, 0.027, 1.0, 0.25, 1.0, 20))
        rope("eyerim", "news", [p + V(math.cos(a) * 0.028, 0, math.sin(a) * 0.028) + n * 0.001 for a in
                                [2 * math.pi * k / 24 for k in range(25)]], r=0.0028, sides=6)
    # 髪: ちぎった新聞紙の細い帯を、てっぺんから後ろへなびかせる
    rnd = random.Random(4)
    for k in range(9):
        x = -0.07 + 0.0175 * k + rnd.uniform(-0.006, 0.006)
        L = rnd.uniform(0.11, 0.17)
        w = rnd.uniform(0.022, 0.032)

        def strip(m, x=x, L=L, w=w):
            rows = []
            for i in range(7):
                t = i / 6
                ang = math.radians(15 + 70 * t * t + rnd.uniform(-6, 6))
                base = hc + V(x, 0.04 - 0.07 * t * 0, 0.125)
                c = base + V(0, -math.sin(ang) * L * t * 0.9, math.cos(ang) * L * t)
                ww = w * (1 - 0.6 * t)
                rows.append([m.bm.verts.new(c + V(-ww / 2, 0, 0)), m.bm.verts.new(c + V(ww / 2, 0, 0))])
            for i in range(6):
                m.bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
        part("tuft", "news", strip, solid=0.002)
    # 首: 新聞紙の芯に麻ひもを巻く
    part("neck", "news", lambda m: C.lathe(m, [(0.036, 0.785), (0.034, 0.72)], segs=16))
    rope("neck_twine", "hemp", helix(V(0, 0, 0), 0.036, 0.725, 0.765, 4), r=0.005, sides=6)
    # 上着: 青緑のフェルト。肩から腰の下まで、すそは波形。前に木のボタン、すそになみ縫い
    coat = part("coat", "felt_teal", lambda m: sheet_cone(m, [(0.045, 0.74), (0.1, 0.725), (0.135, 0.68), (0.15, 0.6), (0.165, 0.5), (0.185, 0.41)],
                                                           n=48, sy=0.82, wave=(10, 0.03)), solid=0.009, fuzz=0.004)
    hem = [V(math.cos(a) * 0.183, math.sin(a) * 0.183 * 0.82 + 0.004, 0.418) for a in [2 * math.pi * k / 80 for k in range(81)]]
    stitch("hem_st", hem, [V(math.cos(2 * math.pi * k / 80), math.sin(2 * math.pi * k / 80), 0) for k in range(81)], "thread_cream")
    for z in (0.68, 0.6, 0.52):
        p, n = hit(coat, V(0, 0.5, z), V(0, -1, 0))
        button("btn", p + n * 0.006, n, 0.014)
    # 帯: 麻ひもを 2 巻きして前で結ぶ
    rope("belt", "hemp", helix(V(0, 0.0, 0), 0.158, 0.535, 0.55, 2, sy=0.84), r=0.007)
    part("knot", "hemp", lambda m: ball(m, V(0.02, 0.145, 0.54), 0.016, 1.2, 0.8, 1.0))
    for s, L in ((1, 0.1), (-1, 0.08)):
        rope("belt_end", "hemp", [V(0.02, 0.15, 0.535), V(0.02 + s * 0.02, 0.16, 0.5), V(0.02 + s * 0.03, 0.162, 0.535 - L)], r=0.006)
    # 腕: 新聞紙を巻いた細い腕、ひじと手首に麻ひも。肩にフェルトの短い袖。手はさび色のフェルトの手袋
    for s in (1, -1):
        sh, el, wr = V(0.13 * s, 0, 0.7), V(0.2 * s, 0.03, 0.56), V(0.19 * s, 0.09, 0.44)
        arm = C.M("arm", "news", "doll")
        C.tube(arm, [sh - V(0.03 * s, 0, 0), sh, el, wr], [0.038, 0.037, 0.034, 0.032], sides=10)
        arm.done(subsurf=1)
        part("sleeve", "felt_teal", lambda m: C.tube(m, [sh - V(0.04 * s, 0, 0.0), sh + (el - sh) * 0.35], [0.05, 0.048], sides=14, caps=False), solid=0.007, fuzz=0.003)
        rope("elbow_twine", "hemp", [el + (Matrix.Rotation(2 * math.pi * k / 16, 3, (wr - sh).normalized()) @ V(0.031, 0, 0)) for k in range(17)], r=0.0045, sides=6)
        part("mitten", "felt_rust", lambda m: blob(m, wr + V(0.0, 0.015, -0.05), (0.03, 0.026, 0.045), 2.2, 2.2), fuzz=0.003)
        part("thumb", "felt_rust", lambda m: blob(m, wr + V(-0.026 * s, 0.03, -0.035), (0.012, 0.012, 0.022), 2.2, 2.2))
    # 脚: 新聞紙の脚と、こげ茶のフェルトの長靴
    for s in (1, -1):
        leg = C.M("leg", "news", "doll")
        C.tube(leg, [V(0.062 * s, 0, 0.44), V(0.066 * s, 0.005, 0.1)], [0.04, 0.038], sides=10)
        leg.done(subsurf=1)
        part("boot", "felt_boot", lambda m: lathe_at(m, [(0.046, 0.15), (0.05, 0.06), (0.052, 0.02), (0.046, 0.0)], V(0.066 * s, 0.01, 0)), fuzz=0.003)
        part("boot_toe", "felt_boot", lambda m: blob(m, V(0.066 * s, 0.05, 0.03), (0.045, 0.05, 0.032), 2.4, 2.4))
        rope("boot_cuff", "hemp", [V(0.066 * s + math.cos(a) * 0.05, 0.01 + math.sin(a) * 0.05, 0.135) for a in [2 * math.pi * k / 24 for k in range(25)]], r=0.005, sides=6)
    return 1.12


# ================================================================ B フェルトの小さな武者
def build_musha():
    """参考: 苔の上の小さな武者 2 体（糸の目の麻布の顔、紺の布の鎧、大きなボタンの吹返し、三日月の前立、赤い紐の結び目）。
    取らない: 刀、苔。背 0.82 m（三日月の先まで 0.96 m）、2.5 頭身"""
    hc = V(0, 0, 0.56)
    head = part("head", "kraft", lambda m: blob(m, hc, (0.12, 0.112, 0.125), 2.3, 2.3, 6), subsurf=1)
    # 目: 黒い糸で 2 針ずつ、横に縫った細い目
    for s in (1, -1):
        p, n = hit(head, hc + V(s * 0.045, 0.5, -0.03), V(0, -1, 0))
        rope("eye", "thread_ink", [p + V(-0.017, 0, 0.002) + n * 0.002, p + n * 0.003, p + V(0.017, 0, 0.002) + n * 0.002], r=0.0042, sides=6)
    # 兜: 紺のフェルトの鉢。縦になみ縫いの筋 8 本
    bowl = part("kabuto", "felt_indigo", lambda m: sheet_cone(m, [(0.0, 0.745), (0.06, 0.74), (0.11, 0.715), (0.14, 0.675), (0.152, 0.625), (0.155, 0.6)], n=40),
                solid=0.012, fuzz=0.004)
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        prof = [(0.06, 0.741), (0.11, 0.716), (0.14, 0.676), (0.152, 0.626), (0.155, 0.605)]
        pts = [V(math.cos(a) * (r + 0.008), math.sin(a) * (r + 0.008), z + 0.004) for r, z in prof]
        stitch("suji", pts, [V(math.cos(a), math.sin(a), 0.4).normalized()] * len(pts), "thread_cream", dash=0.014, gap=0.01)
    part("tehen", "button", lambda m: C.lathe(m, [(0.0, 0.762), (0.022, 0.756), (0.024, 0.744)], segs=16))
    # 眉庇（前のつば）と、錣（うしろの 2 段）
    part("visor", "felt_indigo", lambda m: sheet_cone(m, [(0.152, 0.612), (0.205, 0.585)], n=16, lon=(20, 160)), solid=0.01, fuzz=0.003)
    for k in range(2):
        z = 0.605 - k * 0.05
        part("shikoro", "felt_indigo2" if k else "felt_indigo",
             lambda m, z=z, k=k: sheet_cone(m, [(0.155 + k * 0.02, z), (0.2 + k * 0.025, z - 0.065)], n=24, lon=(150, 390)), solid=0.01, fuzz=0.003)
    # 吹返し: 両脇で外へ折り返した耳に、大きな木のボタン
    for s in (1, -1):
        c = V(s * 0.17, 0.06, 0.6)
        part("fukigaeshi", "felt_indigo", lambda m, c=c: blob(m, c, (0.018, 0.05, 0.045), 4.0, 3.0), fuzz=0.003)
        button("fk_btn", c + V(s * 0.022, 0, 0), V(s, 0, 0), 0.026)
    # 前立: 錫色のフェルトの三日月を、木の台に立てる
    def crescent(m):
        outer = [V(math.cos(a) * 0.085, 0, math.sin(a) * 0.085) for a in [math.radians(200 + 140 * t / 20) for t in range(21)]]
        inner = [V(math.cos(a) * 0.072, 0, math.sin(a) * 0.072 + 0.028) for a in [math.radians(200 + 140 * t / 20) for t in range(21)]]
        rows = [[m.bm.verts.new(V(0, 0.17, 0.79) + p) for p in row] for row in (outer, inner)]
        for i in range(20):
            m.bm.faces.new((rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]))
    part("maedate", "felt_tin", crescent, solid=0.012, fuzz=0.002)
    button("maedate_base", V(0, 0.165, 0.705), V(0, 1, 0.2), 0.02)
    # 胴: 紺のフェルトを綿でふくらませ、横になみ縫い（板の段）
    do = part("do", "felt_indigo2", lambda m: blob(m, V(0, 0, 0.36), (0.135, 0.115, 0.11), 3.0, 2.6, 8), fuzz=0.004)
    for z in (0.4, 0.36, 0.32):
        ring = [V(math.cos(a) * 0.14, math.sin(a) * 0.12, z) for a in [2 * math.pi * k / 60 for k in range(61)]]
        q, nn = on_surface(do, [V(0, 0, z)] * 0, V(0, 0, z))
        pts = []
        for p in ring:
            d = (p - V(0, 0, z)).normalized()
            qq, n_ = hit(do, V(0, 0, z) + d * 0.4, -d)
            pts.append(qq + n_ * 0.002)
        stitch("do_st", pts, [V(0, 0, 1)] * len(pts), "thread_cream", dash=0.016, gap=0.01)
    # 大袖: 肩にふくらんだ板、上に木のボタン
    for s in (1, -1):
        c = V(s * 0.16, 0, 0.4)
        part("sode", "felt_indigo", lambda m, c=c: blob(m, c, (0.03, 0.075, 0.06), 4.0, 3.0), fuzz=0.004)
        button("sode_btn", c + V(s * 0.005, 0, 0.064), V(0, 0, 1), 0.017)
    # 帯: 赤い毛糸の太い紐を巻き、前で結んで房を垂らす
    rope("obi", "yarn_red", helix(V(0, 0, 0), 0.142, 0.265, 0.285, 2, sy=0.86), r=0.011)
    part("obi_knot", "yarn_red", lambda m: ball(m, V(0.03, 0.125, 0.275), 0.022, 1.2, 0.8, 1.0))
    for s in (1, -1):
        rope("obi_end", "yarn_red", [V(0.03, 0.13, 0.27), V(0.03 + s * 0.03, 0.14, 0.23), V(0.03 + s * 0.035, 0.142, 0.17)], r=0.009)
    # 袴: ひだのある紺の木綿（フェルト）
    def hakama(m):
        rows = []
        for k, (r, z) in enumerate([(0.13, 0.28), (0.15, 0.2), (0.17, 0.12)]):
            row = []
            for i in range(48):
                a = 2 * math.pi * i / 48
                rr = r * (1 + (0.06 * (k / 2)) * (1 if i % 2 else -1))
                row.append(m.bm.verts.new((math.cos(a) * rr, math.sin(a) * rr * 0.86, z)))
            rows.append(row)
        for k in range(2):
            for i in range(48):
                j = (i + 1) % 48
                m.bm.faces.new((rows[k][i], rows[k + 1][i], rows[k + 1][j], rows[k][j]))
    part("hakama", "felt_indigo", hakama, smooth=False, solid=0.008, fuzz=0.003)
    # 腕: 紺の籠手とこげ茶の手袋。脚: 短い紺の脚に、麻ひもの草鞋
    for s in (1, -1):
        sh, el, wr = V(0.13 * s, 0, 0.42), V(0.19 * s, 0.03, 0.33), V(0.17 * s, 0.09, 0.25)
        part("kote", "felt_indigo2", lambda m: C.tube(m, [sh - V(0.03 * s, 0, 0), sh, el, wr], [0.04, 0.04, 0.038, 0.035], sides=12), subsurf=1, fuzz=0.003)
        part("mitten", "felt_boot", lambda m: blob(m, wr + V(0, 0.012, -0.04), (0.03, 0.026, 0.038), 2.2, 2.2), fuzz=0.003)
        part("leg", "felt_indigo2", lambda m: C.tube(m, [V(0.06 * s, 0, 0.14), V(0.062 * s, 0.01, 0.045)], [0.038, 0.035], sides=12), subsurf=1)
        part("tabi", "felt_cream2", lambda m: blob(m, V(0.063 * s, 0.025, 0.035), (0.04, 0.058, 0.03), 2.4, 2.4), fuzz=0.003)
        coil = [V(0.063 * s + math.cos(a) * (0.012 + 0.03 * a / 18.8) * 0.8, 0.025 + math.sin(a) * (0.012 + 0.03 * a / 18.8) * 1.2, 0.004) for a in [k * 0.3 for k in range(63)]]
        rope("waraji", "hemp", coil, r=0.0045, sides=6)
    return 0.96


# ================================================================ C 布の人形
def build_ningyo():
    """参考: 布の人形（白い顔に閉じた目、紺の糸のお団子に布の玉、波の柄の着物、赤い帯と房）と ElenaS の笠の人形。
    取らない: 口紅、袖で手を隠すこと（手は出す）。背 1.12 m、3 頭身"""
    hc = V(0, 0, 0.745)
    head = part("head", "washi", lambda m: ball(m, hc, 0.135, 1.0, 0.95, 1.05, 32))
    # 閉じた目: 黒い糸の刺繍で、下へふくらむ弧
    for s in (1, -1):
        pts2 = [hc + V(s * 0.048 + t * 0.026, 0, -0.03 - 0.009 * (1 - t * t)) for t in [-1 + 2 * k / 8 for k in range(9)]]
        q, _ = on_surface(head, pts2, hc, lift=0.0015)
        rope("eye", "thread_ink", q, r=0.0032, sides=6)
    # 髪: 紺の毛糸を頭に巻きつける（てっぺんとうしろ）。前髪は眉の上で切りそろえる
    def wound_cap(m):
        pts = []
        turns = 26
        for i in range(turns * 40 + 1):
            t = i / (turns * 40)
            lat = math.radians(84 - 124 * t)   # うしろは襟足まで
            a = 2 * math.pi * turns * t
            # 顔の前（下のほう）はあける: 前を向く所は、眉より下に行かない
            r = 0.142
            p = V(math.cos(a) * math.cos(lat) * r, math.sin(a) * math.cos(lat) * r * 0.95, math.sin(lat) * r * 1.05)
            if p.y > 0.05 and p.z < 0.035:
                p = V(p.x, p.y, 0.035 + (p.z - 0.035) * 0.0)   # 前は眉の高さで止める（前髪の線）
            pts.append(hc + p)
        C.tube(m, pts, 0.0068, sides=6, caps=True)
    hair = part("hair", "yarn_indigo", wound_cap, smooth=True)
    hair.data.materials[0].node_tree.nodes["Principled BSDF"].inputs["Sheen Weight"].default_value = 0.12   # 毛糸の黒髪が灰色に光らないように
    # お団子 2 つ: 毛糸を巻いた玉に、フェルトの玉を飾る
    for s in (1, -1):
        c = hc + V(s * 0.105, -0.03, 0.115)
        def bun(m, c=c):
            pts = []
            for i in range(14 * 30 + 1):
                t = i / (14 * 30)
                lat = math.radians(85 - 170 * t)
                a = 2 * math.pi * 14 * t
                pts.append(c + V(math.cos(a) * math.cos(lat), math.sin(a) * math.cos(lat), math.sin(lat)) * 0.06)
            C.tube(m, pts, 0.0065, sides=6)
        part("bun", "yarn_indigo", bun)
        for k, (role, off, r) in enumerate((("felt_cream2", V(s * 0.03, 0.04, 0.035), 0.02), ("felt_obi", V(s * 0.045, 0.01, 0.05), 0.016),
                                            ("felt_cream2", V(s * 0.05, -0.03, 0.04), 0.018))):
            part("deco", role, lambda m, c=c, off=off, r=r: ball(m, c + off, r), fuzz=0.003)
    # 飾り紐: 左のお団子から赤い糸で、フェルトの玉を 2 つ垂らす
    c = hc + V(0.13, 0.0, 0.08)
    rope("kanzashi", "thread_red", [c, c + V(0.03, 0.01, -0.12), c + V(0.032, 0.01, -0.2)], r=0.0025, sides=5)
    for z, r in ((-0.12, 0.024), (-0.2, 0.021)):
        part("temari", "felt_cream2", lambda m, z=z, r=r: ball(m, c + V(0.031, 0.01, z - r), r), fuzz=0.003)
        rope("temari_band", "thread_red", [c + V(0.031, 0.01, z - r) + V(math.cos(a) * r * 1.02, math.sin(a) * r * 1.02, 0) for a in [2 * math.pi * k / 20 for k in range(21)]], r=0.003, sides=5)
    # 着物: 生成りの木綿に藍の青海波。身頃の重なりと、藍の襟
    body = part("kimono", "print", lambda m: sheet_cone(m, [(0.06, 0.62), (0.12, 0.605), (0.15, 0.56), (0.165, 0.45), (0.2, 0.25), (0.245, 0.025)], n=48, sy=0.84), solid=0.008)
    part("kimono_cap", "print", lambda m: C.lathe(m, [(0.06, 0.621), (0.0, 0.621)], segs=24))
    for s in (1, -1):
        pts = [V(s * (0.012 + 0.07 * t), 0.105 + 0.08 * t * t, 0.615 - 0.45 * t) for t in [k / 10 for k in range(11)]]
        q, nn = on_surface(body, pts, V(0, 0, 0.5), lift=0.006)
        def collar(m, q=q, nn=nn):
            rows = []
            for p, n in zip(q, nn):
                side = n.cross(V(0, 0, 1)).normalized() * 0.022
                rows.append([m.bm.verts.new(p - side), m.bm.verts.new(p + side)])
            for i in range(len(rows) - 1):
                m.bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
        part("eri", "felt_indigo", collar, solid=0.006)
    # 帯: 赤いフェルトの太い帯と、毛糸の帯締め、前に房
    part("obi", "felt_obi", lambda m: sheet_cone(m, [(0.16, 0.5), (0.165, 0.41)], n=40, sy=0.86), solid=0.014, fuzz=0.003)
    rope("obijime", "yarn_cream", [V(math.cos(a) * 0.177, math.sin(a) * 0.177 * 0.86, 0.455) for a in [2 * math.pi * k / 48 for k in range(49)]], r=0.006)
    rope("tassel_cord", "thread_red", [V(0.04, 0.155, 0.455), V(0.05, 0.163, 0.4), V(0.052, 0.165, 0.35)], r=0.003, sides=5)
    part("tassel", "felt_obi", lambda m: lathe_at(m, [(0.012, 0.36), (0.02, 0.3), (0.022, 0.27)], V(0.052, 0.165, 0), 12), fuzz=0.004)
    # 袖: 大きな四角い袂。手（和紙）は袖口から出す
    for s in (1, -1):
        sh, el, wr = V(0.14 * s, 0, 0.585), V(0.215 * s, 0.04, 0.46), V(0.185 * s, 0.12, 0.395)
        def sleeve(m, sh=sh, el=el, wr=wr):
            top = [sh, el + V(0.02 * s, 0, 0.02), wr + V(0.02 * s, 0.01, 0.0)]
            bot = [p + V(0.012 * s, -0.01, -0.15) for p in top[1:]]
            vs = [m.bm.verts.new(p) for p in top + bot]
            m.bm.faces.new((vs[0], vs[1], vs[3]))
            m.bm.faces.new((vs[1], vs[2], vs[4], vs[3]))
        part("tamoto", "print", sleeve, solid=0.008)
        part("arm", "print", lambda m, sh=sh, el=el, wr=wr: C.tube(m, [sh - V(0.03 * s, 0, 0), sh, el, wr], [0.045, 0.045, 0.043, 0.04], sides=14), subsurf=1)
        part("cuff", "felt_indigo", lambda m, wr=wr, el=el: C.tube(m, [wr + (el - wr) * 0.12, wr], 0.043, sides=14, caps=False), solid=0.005)
        part("hand", "washi", lambda m, wr=wr: blob(m, wr + V(0, 0.02, -0.035), (0.026, 0.022, 0.034), 2.2, 2.2))
    for s in (1, -1):
        part("zori", "felt_ink", lambda m: blob(m, V(0.06 * s, 0.14, 0.015), (0.035, 0.05, 0.015), 2.6, 2.6))
    return 0.95


# ================================================================ D 旅のおじいさん
def build_tabi():
    """参考: フェルトの魔法使いの人形（先の巻いたとんがり帽、丸眼鏡、羊毛のひげ、継ぎ当ての長いコート、杖）と紙の王子（紺の布のマント）。
    取らない: 本、蝋燭。背 1.25 m（帽子の先まで）、腰を少し曲げる"""
    hc = V(0, 0.02, 0.8)
    head = part("head", "paper_face", lambda m: blob(m, hc, (0.1, 0.1, 0.12), 2.2, 2.2, 6), subsurf=1)
    # 鼻: 紙を巻いた長めの円錐。顔の向きを示す
    part("nose", "paper_face", lambda m: C.tube(m, [hc + V(0, 0.085, -0.005), hc + V(0, 0.15, -0.025)], [0.022, 0.006], sides=10))
    # 丸眼鏡: 細い針金の輪 2 つと橋
    for s in (1, -1):
        c = hc + V(s * 0.045, 0.105, 0.012)
        rope("glass", "wire", [c + V(math.cos(a) * 0.032, 0.0, math.sin(a) * 0.03) for a in [2 * math.pi * k / 28 for k in range(29)]], r=0.0028, sides=6)
        rope("temple", "wire", [c + V(s * 0.032, 0, 0), c + V(s * 0.06, -0.06, 0.005), c + V(s * 0.06, -0.13, 0.0)], r=0.0024, sides=5)
    rope("bridge", "wire", [hc + V(-0.013, 0.108, 0.016), hc + V(0, 0.112, 0.022), hc + V(0.013, 0.108, 0.016)], r=0.0025, sides=5)
    # ひげと眉: 綿のかたまり
    C.metablob("beard", "cotton", [(hc + V(0, 0.08, -0.07), 0.07, (1.0, 0.6, 1.0)), (hc + V(0, 0.07, -0.16), 0.06, (0.8, 0.55, 1.2)),
                                   (hc + V(0.05, 0.06, -0.06), 0.05), (hc + V(-0.05, 0.06, -0.06), 0.05), (hc + V(0, 0.06, -0.24), 0.035)], 0.012,
               group="doll", lumps=0.12)
    for s in (1, -1):
        C.metablob("brow", "cotton", [(hc + V(s * 0.045, 0.1, 0.06), 0.026, (1.4, 0.6, 0.6))], 0.006, group="doll", lumps=0.1)
    # 帽子: 紺のフェルトのとんがり。先は後ろへ巻く。つばは広め、継ぎ当て 2 枚
    path = [hc + V(0, -0.005, 0.08)]
    for k in range(1, 15):
        t = k / 14
        path.append(hc + V(0, -0.005 - 0.03 * t - 0.09 * max(0, t - 0.6) ** 1.5 * 6, 0.08 + 0.36 * t - 0.25 * max(0, t - 0.75) ** 2 * 8))
    curl_c = path[-1] + V(0, -0.035, -0.01)
    for k in range(1, 9):
        a = math.pi * 0.5 + 1.6 * math.pi * k / 8
        path.append(curl_c + V(0, math.cos(a) * 0.035 * (1 - k / 12), math.sin(a) * 0.035 * (1 - k / 12)))
    radii = [0.118 * (1 - i / len(path)) ** 1.15 + 0.004 for i in range(len(path))]
    hat = part("hat", "felt_indigo2", lambda m: C.tube(m, path, radii, sides=24), subsurf=1, fuzz=0.004)
    part("brim", "felt_indigo2", lambda m: sheet_cone(m, [(0.11, hc.z + 0.085), (0.2, hc.z + 0.065)], n=48, sy=0.95), solid=0.01, fuzz=0.004)
    patch("hat_patch", "felt_denim", hat, hc + V(0.03, 0.0, 0.2), 0.055, 0.05)
    patch("hat_patch2", "felt_grey", hat, hc + V(-0.025, 0.0, 0.32), 0.04, 0.04, thread="thread_ink")
    # コート: 長い紺のフェルト。継ぎ当て、立てた襟、木のボタン
    coat = part("coat", "felt_indigo", lambda m: sheet_cone(m, [(0.05, 0.69), (0.11, 0.675), (0.145, 0.62), (0.16, 0.5), (0.19, 0.3), (0.22, 0.09)], n=48, sy=0.85),
                solid=0.012, fuzz=0.004)
    part("coat_cap", "felt_indigo", lambda m: C.lathe(m, [(0.05, 0.692), (0.0, 0.692)], segs=24))
    part("collar", "felt_indigo2", lambda m: sheet_cone(m, [(0.06, 0.72), (0.075, 0.665)], n=32, sy=0.9, lon=(110, 430)), solid=0.01, fuzz=0.003)
    for (role, c, w, h, th) in (("felt_denim", V(0.08, 0, 0.42), 0.09, 0.1, "thread_cream"), ("felt_grey", V(-0.1, 0, 0.25), 0.08, 0.07, "thread_ink"),
                                ("felt_cream2", V(-0.04, 0, 0.55), 0.05, 0.05, "thread_ink"), ("felt_plum", V(0.12, 0, 0.18), 0.06, 0.08, "thread_cream")):
        patch("coat_patch", role, coat, c, w, h, thread=th)
    for z in (0.6, 0.5, 0.4):
        p, n = hit(coat, V(0.0, 0.5, z), V(0, -1, 0))
        button("btn", p + n * 0.007, n, 0.014)
    # 腕: コートの袖と折り返し、紙の手。右手で杖を持つ
    for s in (1, -1):
        sh = V(0.13 * s, 0, 0.66)
        el = V(0.2 * s, 0.03, 0.52)
        wr = V(0.2 * s, 0.11, 0.44) if s > 0 else V(0.17 * s, 0.08, 0.42)
        part("sleeve", "felt_indigo", lambda m, sh=sh, el=el, wr=wr: C.tube(m, [sh - V(0.04 * s, 0, 0), sh, el, wr], [0.052, 0.052, 0.05, 0.048], sides=16), subsurf=1, fuzz=0.004)
        part("cuff", "felt_indigo2", lambda m, wr=wr, el=el: C.tube(m, [wr + (el - wr) * 0.15, wr + (wr - el).normalized() * 0.01], 0.056, sides=16, caps=False), solid=0.008)
        part("hand", "paper_face", lambda m, wr=wr: blob(m, wr + V(0, 0.015, -0.04), (0.028, 0.024, 0.036), 2.2, 2.2))
    # 杖: 木の棒に麻ひもを巻き、てっぺんにフェルトの玉
    top = V(0.24, 0.13, 0.78)
    part("staff", "wood", lambda m: C.tube(m, [V(0.24, 0.16, 0.0), V(0.235, 0.14, 0.4), top], [0.012, 0.012, 0.014], sides=10), subsurf=1)
    rope("staff_twine", "hemp", helix(V(0.236, 0.135, 0), 0.016, 0.42, 0.48, 6), r=0.004, sides=6)
    part("staff_ball", "felt_plum", lambda m: ball(m, top + V(0, 0, 0.03), 0.032), fuzz=0.004)
    for s in (1, -1):
        part("boot", "felt_boot", lambda m: blob(m, V(0.07 * s, 0.07, 0.04), (0.045, 0.07, 0.04), 2.4, 2.6), fuzz=0.003)
    return 1.25


BUILDERS = {"shinbun": build_shinbun, "musha": build_musha, "ningyo": build_ningyo, "tabi": build_tabi}


# ================================================================ 場面（ソリと同じ雪と光）
def stage(size):
    C.ground(60.0)
    C.light(elev=24.0, az=-140.0)   # 太陽はカメラの左前から、午後の低い光
    sun = bpy.data.objects["sun"]
    sun.data.color = (1.0, 0.8, 0.6)
    C.setup_render(size)
    sc = bpy.context.scene
    sc.eevee.taa_render_samples = A.samples
    sc.view_settings.exposure = -0.75


VIEWS = {"front": 0, "quarter": 32, "side": 85, "back": 180, "backq": 145}


def shoot(name, top):
    tgt = V(0, 0, top * 0.48)
    for v in A.views.split(","):
        a = math.radians(VIEWS.get(v, 0))
        dist = top * 3.4
        C.render(tgt + V(math.sin(a) * dist, math.cos(a) * dist, top * 0.12), tgt, 80, os.path.join(OUT, "%s-%s.png" % (name, v)), dof=2.0)


def build_old_three():
    """person/build_dolls.py を読むだけで、組み立ての関数を借りる（描く所より前だけを実行する）"""
    path = os.path.join(PERSON, "build_dolls.py")
    src = open(path, encoding="utf-8").read()
    cut = src.index("# ================================================================ 描く")
    ns = {"__file__": path, "__name__": "build_dolls_borrowed"}
    argv = sys.argv
    sys.argv = ["blender"]
    try:
        exec(compile(src[:cut], path, "exec"), ns)
    finally:
        sys.argv = argv
    return ns


def group(name, fn):
    before = set(bpy.data.objects)
    fn()
    emp = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(emp)
    for ob in set(bpy.data.objects) - before:
        if ob is not emp and ob.parent is None:
            ob.parent = emp
    return emp


def lineup():
    ns = build_old_three()   # ここで場面が空にされる
    register_paper()
    row = [("kasa", ns["build_kasa"]), ("origami", ns["build_origami"]), ("news", ns["build_news"])]
    row += [(k, BUILDERS[k]) for k in ("shinbun", "musha", "ningyo", "tabi")]
    xs = [2.85, 1.9, 0.98, 0.05, -0.85, -1.8, -2.8]   # カメラは +Y から見るので、+X が絵の左
    for (name, fn), x in zip(row, xs):
        emp = group(name, fn)
        emp.location = V(x, 0, 0)
        emp.rotation_euler = (0, 0, math.radians(A.turn))
    stage(A.size)
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    tgt = V(0.0, 0, 0.62)
    a = math.radians(10)
    C.render(tgt + V(math.sin(a) * 15.5, math.cos(a) * 15.5, 1.3), tgt, 80,
             os.path.join(OUT, "00-lineup%s.png" % ("" if not A.turn else "-turn%d" % A.turn)))


if A.lineup:
    lineup()
else:
    C.reset()
    register_paper()
    top = BUILDERS[A.doll]()
    stage(A.size)
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    shoot(A.doll, top)
