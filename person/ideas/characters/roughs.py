"""新しい人形のラフ（3 回目）。代表の Pinterest のボード「&wind：Lodge キャラ」の意匠を取り、Lodge の素材で描き直す。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/characters/roughs.py -- --doll robo --views quarter,front,backq
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/characters/roughs.py -- --lineup --size 2800x1100

--doll
  robo     紙のロボット: 角の立った段ボールの箱の体。ふたの開いた箱の頭に四角い窓の目、短い首。大きな肩、四角い蛇腹の腕、大きなこぶし、低い腰と大きな足。腰に麻縄
  musha    折り紙の武者（縫い目）: 折り紙の顔と手。紺のフェルトの兜と鎧を、赤い糸の縅・十字縫い・なみ縫いで固める。三日月、忍緒、大袖、草摺、脛当て
  ningyo   絹の人形: 和紙の顔に刺繍の閉じた目。紺の毛糸のお団子に絹の花と、左右の歩揺。月白の襦、胸高の茜の裙、絹のリボン、透ける披帛
  golem    継ぎはぎの巨人: 頭の小さなゴーレムのような大男。継ぎはぎの布をふくらませた体に、十字縫いで手足を縫いつける。頭とこぶしはもんだ紙。肩と頭に綿の雪
--export DIR  骨を入れて質感を焼き、ゲーム用の glb を DIR に書き出す（例: game/person）
--lineup   いまの 3 体（person/build_dolls.py を読むだけで組む）と 4 体を雪の上に並べる

素材と縫い目は、ソリと同じもの（props/common.py → lodge/materials.py）を読むだけで使う。紙は person/build_dolls.py から写した。
顔は参考のとおり、縫い目・閉じた目・穴・眼鏡で表す（光る目や頬は描かない。口は描かない）。骨はまだ入れない。
肩と腰には、胴と腕・胴と脚のつながりがわかる部品を置く（肩当て、肩上と大袖、腰の箱、草摺、縫いつけた輪）。
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
from mathutils import Matrix, Vector, noise

sys.dont_write_bytecode = True
ap = argparse.ArgumentParser()
ap.add_argument("--doll", default="robo", choices=("robo", "musha", "ningyo", "golem"))
ap.add_argument("--views", default="quarter,front,backq")
ap.add_argument("--lineup", action="store_true")
ap.add_argument("--turn", type=float, default=0.0)
ap.add_argument("--size", default="900x1100")
ap.add_argument("--samples", type=int, default=64)
ap.add_argument("--blend", default="")
ap.add_argument("--export", default="", help="骨を入れて焼き、ゲーム用の glb をこのフォルダーに書き出す（person/rig_export.py）")
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


def np_image(name, img):
    """numpy の (高さ, 幅, 3) の色（線形）を Blender の画像に。行 0 が上"""
    h, w = img.shape[:2]
    rgba = np.concatenate([img, np.ones((h, w, 1))], axis=2)[::-1]
    im = bpy.data.images.new(name, w, h)
    if "Linear Rec.709" in [c.name for c in im.colorspace_settings.bl_rna.properties["name"].enum_items]:
        im.colorspace_settings.name = "Linear Rec.709"
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.pack()
    return im


def two_tone(name, mask, base, ink):
    b = np.array(lin(base)[:3])
    k = np.array(lin(ink)[:3])
    return np_image(name, b[None, None] * (1 - mask[..., None]) + k[None, None] * mask[..., None])


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
    return two_tone("seigaiha", m, base, ink)


def check_image(base, ink, px=256, n=6):
    """ギンガムの格子: 縦と横の帯が重なる所は濃く"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    a = ((x * n) % 1 < 0.5).astype(np.float32)
    b = ((y * n) % 1 < 0.5).astype(np.float32)
    return two_tone("check", 0.45 * a + 0.45 * b, base, ink)


def stripe_image(base, ink, px=256, n=5):
    """縦じまの綿（太い線と細い線）"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    f = (x * n) % 1
    return two_tone("stripe", ((f < 0.16) | ((f > 0.42) & (f < 0.47))).astype(np.float32), base, ink)


def embroidery_images(name, ground, thread, heart, px=512, n=4):
    """絹の刺繍: 5 弁の梅の花を互い違いに並べる。色の画像と、糸の盛り上がり（繻子縫いの筋）の画像"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    petal = np.zeros((px, px), np.float32)
    core = np.zeros((px, px), np.float32)
    ang = np.zeros((px, px), np.float32)
    r = 0.5 / n * 0.78
    for j in range(n + 1):
        for i in range(n + 1):
            cx, cy = (i + (0.5 if j % 2 else 0.0)) / n, (j + 0.5) / n
            dx = ((x - cx + 0.5) % 1) - 0.5
            dy = ((y - cy + 0.5) % 1) - 0.5
            rot = (i * 1.3 + j * 0.7)
            for k in range(5):
                a = rot + 2 * math.pi * k / 5
                d = np.hypot(dx - math.cos(a) * r * 0.52, dy - math.sin(a) * r * 0.52)
                hit = d < r * 0.42
                petal = np.maximum(petal, hit.astype(np.float32))
                ang = np.where(hit, np.arctan2(dy, dx), ang)
            core = np.maximum(core, (np.hypot(dx, dy) < r * 0.2).astype(np.float32))
    g, t, c = (np.array(lin(h)[:3]) for h in (ground, thread, heart))
    col = g[None, None] * (1 - petal[..., None]) + t[None, None] * petal[..., None]
    col = col * (1 - core[..., None]) + c[None, None] * core[..., None]
    satin = 0.75 + 0.25 * np.sin(ang * 14.0)   # 花びらの中の糸の筋（中心から放射）
    h = np.maximum(petal * satin, core)
    return np_image(name, col), np_image(name + "_h", np.repeat(h[..., None], 3, axis=2))


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


def bsdf_set(b, **kw):
    for k, v in kw.items():
        k = k.replace("_", " ")
        if k in b.inputs:
            b.inputs[k].default_value = v


def painted(name, paint, base="B78C5C", chip=0.6):
    """段ボールに塗った絵の具: ところどころはげて、下の紙が見える"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    no = M.n("ShaderNodeTexNoise", Scale=7.0, Detail=9.0, Roughness=0.72)
    M.l(co, 0, no, "Vector")
    mr = M.n("ShaderNodeMapRange")
    M.l(no, "Fac", mr, 0)
    mr.inputs["From Min"].default_value = chip
    mr.inputs["From Max"].default_value = chip + 0.025
    mr.inputs["To Min"].default_value = 1.0
    mr.inputs["To Max"].default_value = 0.0
    M.l(M.mix((mr, 0), lin(base), lin(paint)), 2, M.b, "Base Color")
    rg = M.n("ShaderNodeMapRange")
    M.l(mr, 0, rg, 0)
    rg.inputs["To Min"].default_value = 0.88
    rg.inputs["To Max"].default_value = 0.6
    M.l(rg, 0, M.b, "Roughness")
    bp = fiber_bump(M, co, 0.18)
    b2 = M.n("ShaderNodeBump", Strength=0.35, Distance=0.002)
    M.l(mr, 0, b2, "Height")
    M.l(bp, 0, b2, "Normal")
    M.l(b2, 0, M.b, "Normal")
    M.b.inputs["Specular IOR Level"].default_value = 0.3
    return M.m


def silk(name, color, emb=None, scale=7.0, alpha=1.0, shot=None):
    """絹: 控えめでやわらかい光。
    ・糸が光を中で散らすので、光の点は白くならず糸の色をおびる（Specular Tint を糸の色に、強さは控えめ）
    ・光は広くやわらかく（粗さ 0.5 前後）、浅い角度で布の縁がふわっと明るく、色が少しずれる（玉虫の shot 色へ）
    ・Eevee では Principled の異方性が効かないので、細かな平織りの凹凸と、糸の節（スラブ）のむらで光をばらす
    emb=(色の画像, 高さの画像) で刺繍"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    shot = shot or color or "F0E6D2"
    # 色: 糸の節のむら（横に長いむら）と、浅い角度での色のずれ
    sl_map = M.n("ShaderNodeMapping")
    sl_map.inputs["Scale"].default_value = (60.0, 60.0, 4.0)
    M.l(co, 0, sl_map, "Vector")
    slub = M.n("ShaderNodeTexNoise", Scale=1.0, Detail=3.0, Roughness=0.5)
    M.l(sl_map, 0, slub, "Vector")
    if emb:
        mp = M.obj_coords(scale)
        tc = M.n("ShaderNodeTexImage", projection="BOX", projection_blend=0.25)
        tc.image = emb[0]
        M.l(mp, 0, tc, "Vector")
        base = (tc, "Color")
    else:
        base = lin(color)
    sm = M.n("ShaderNodeMapRange")
    M.l(slub, "Fac", sm, 0)
    sm.inputs["To Min"].default_value = 0.94
    sm.inputs["To Max"].default_value = 1.05
    vary = M.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    vary.inputs[0].default_value = 1.0
    if emb:
        M.l(base[0], base[1], vary, 6)
    else:
        vary.inputs[6].default_value = base
    cc = M.n("ShaderNodeCombineColor")
    for k in range(3):
        M.l(sm, 0, cc, k)
    M.l(cc, 0, vary, 7)
    lw = M.n("ShaderNodeLayerWeight", Blend=0.35)
    gr = M.n("ShaderNodeMapRange")
    M.l(lw, "Facing", gr, 0)
    gr.inputs["From Min"].default_value = 0.35
    gr.inputs["To Max"].default_value = 0.4
    col = M.mix((gr, 0), (vary, 2), lin(shot))
    M.l(col, 2, M.b, "Base Color")
    # 光の色は糸の色（白っぽくしない）
    tint = M.mix(0.35, (vary, 2), (1.0, 1.0, 1.0, 1.0))
    M.l(tint, 2, M.b, "Specular Tint")
    # 凹凸: 平織り（縦と横の糸）と、糸の節
    wx = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X", Scale=1800.0)
    wz = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Z", Scale=1800.0)
    M.l(co, 0, wx, "Vector")
    M.l(co, 0, wz, "Vector")
    wv = M.n("ShaderNodeMath", operation="MULTIPLY")
    M.l(wx, "Fac", wv, 0)
    M.l(wz, "Fac", wv, 1)
    bp = M.n("ShaderNodeBump", Strength=0.12, Distance=0.0008)
    M.l(wv, 0, bp, "Height")
    b1 = M.n("ShaderNodeBump", Strength=0.08, Distance=0.002)
    M.l(slub, "Fac", b1, "Height")
    M.l(bp, 0, b1, "Normal")
    bp = b1
    if emb:
        th = M.n("ShaderNodeTexImage", projection="BOX", projection_blend=0.25)
        th.image = emb[1]
        M.l(mp, 0, th, "Vector")
        b2 = M.n("ShaderNodeBump", Strength=0.5, Distance=0.0025)
        M.l(th, "Color", b2, "Height")
        M.l(bp, 0, b2, "Normal")
        bp = b2
    M.l(bp, 0, M.b, "Normal")
    # 粗さ: 0.46〜0.58 のむら（光の帯が切れ切れに）
    rr = M.n("ShaderNodeMapRange")
    M.l(slub, "Fac", rr, 0)
    rr.inputs["To Min"].default_value = 0.46
    rr.inputs["To Max"].default_value = 0.58
    M.l(rr, 0, M.b, "Roughness")
    bsdf_set(M.b, Specular_IOR_Level=0.32, Sheen_Weight=0.45, Sheen_Roughness=0.45, Alpha=alpha)
    M.b.inputs["Sheen Tint"].default_value = lin(shot)
    M.b.inputs["Subsurface Weight"].default_value = 0.06
    if alpha < 1.0:
        for attr, v in (("surface_render_method", "BLENDED"), ("use_backface_culling", False)):
            if hasattr(M.m, attr):
                setattr(M.m, attr, v)
    return M.m


def register_paper():
    """紙・絹の素材を props/common.py の役割の表に足す（C.M(…, role) で使えるように）"""
    img = bpy.data.images.load(os.path.join(PERSON, "textures", "newsprint.png"))
    emb_ind = embroidery_images("emb_indigo", "2B3760", "EFE1C4", "D2A04A")
    emb_rose = embroidery_images("emb_rose", "A93F3A", "F1E3C6", "D2A04A", n=3)
    C._MAT.update({
        "news": newsprint_paste("news", img),
        "kraft": paper("kraft", "B98C5E", back="D8C09A", fiber=0.2, crinkle=0.35),
        "washi": paper("washi", "EBD9BC", back="F1E6D2", fiber=0.55, crinkle=0.2, sss=0.15),
        "paper_face": paper("paper_face", "D6B68C", back="E6D3B3", fiber=0.3, crinkle=0.45),
        "hole": plain("hole", "120E0C", 1.0),
        "wire": plain("wire", "3B3028", 0.35, metal=0.8),
        "brass": plain("brass", "B08A44", 0.35, metal=0.9),
        "print": printed_cotton("print", seigaiha_image("EFE6D2", "2E4372"), 4.0),
        "check": printed_cotton("check", check_image("E9DFC8", "3C4E7C"), 3.0),
        "stripe": printed_cotton("stripe", stripe_image("E9DFC8", "A8553A"), 3.0),
        # 紙のロボット: 段ボール、はげた絵の具、マスキングテープ
        "card": paper("card", "B78C5C", back="C9A57A", fiber=0.25, crinkle=0.12),
        "paint_teal": painted("paint_teal", "4A8A8C"),
        "paint_cream": painted("paint_cream", "E6DCC6", chip=0.63),
        "tape": paper("tape", "E2D2A8", back="E2D2A8", rough=0.6, fiber=0.08),
        # 折り紙の武者の体、紙のおじいさんの顔
        "ori_face": paper("ori_face", "E8CFA6", back="F7F2E8", rough=0.72, fiber=0.1),
        "crumple": paper("crumple", "D9BC92", back="E9D8BA", fiber=0.3, crinkle=0.25),
        # 絹の人形
        "silk_pale": silk("silk_pale", "DCE3D6", shot="ECE4D0"),
        "silk_rose": silk("silk_rose", "A93F3A", shot="C2683F"),
        "silk_cream": silk("silk_cream", "EFE1C4", shot="F5E9CF"),
        "silk_red": silk("silk_red", "B8352C", shot="CB5A3C"),
        "silk_gauze": silk("silk_gauze", "E2A39A", alpha=0.82, shot="EEC6B6"),
        "silk_emb_indigo": silk("silk_emb_indigo", None, emb_ind, scale=9.0, shot="3E4C7E"),
        "silk_emb_rose": silk("silk_emb_rose", None, emb_rose, scale=6.0, shot="C2683F"),
        "pearl": plain("pearl", "EFE8DA", 0.18),
        "jade": plain("jade", "8DB89E", 0.22),
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


def unit_sphere(m, u=16, v=8):
    """単位球の頂点と面を m に足し、頂点の列を返す（同じ bmesh に何度足しても崩れない）"""
    vs = [m.bm.verts.new((0, 0, -1))]
    for j in range(1, v):
        lat = -math.pi / 2 + math.pi * j / v
        for i in range(u):
            a = 2 * math.pi * i / u
            vs.append(m.bm.verts.new((math.cos(lat) * math.cos(a), math.cos(lat) * math.sin(a), math.sin(lat))))
    vs.append(m.bm.verts.new((0, 0, 1)))
    ring = lambda j, i: vs[1 + (j - 1) * u + (i % u)]
    for i in range(u):
        m.bm.faces.new((vs[0], ring(1, i + 1), ring(1, i)))
        m.bm.faces.new((vs[-1], ring(v - 1, i), ring(v - 1, i + 1)))
    for j in range(1, v - 1):
        for i in range(u):
            m.bm.faces.new((ring(j, i), ring(j, i + 1), ring(j + 1, i + 1), ring(j + 1, i)))
    return vs


def ball(m, center, r, sx=1.0, sy=1.0, sz=1.0, seg=16):
    for v in unit_sphere(m, seg, seg // 2):
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


def cast_many(ob, origins, dirs):
    """ob の表面で、それぞれの origin から dir に進んで当たる所と外向きの法線（場面の更新は 1 回だけ）"""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    oe = ob.evaluated_get(dg)
    mw = ob.matrix_world
    inv = mw.inverted()
    out = []
    for o, d in zip(origins, dirs):
        o, d = Vector(o), Vector(d).normalized()
        ok, loc, nrm, _ = oe.ray_cast(inv @ o, (inv.to_3x3() @ d).normalized(), depsgraph=dg)
        if not ok:
            out.append((o + d * 0.5, -d))
            continue
        n = (mw.to_3x3() @ nrm).normalized()
        out.append((mw @ loc, n if n.dot(d) < 0 else -n))
    return out


def hit(ob, origin, direction):
    return cast_many(ob, [origin], [direction])[0]


def on_surface(ob, pts2, axis_origin=None, toward=V(0, -1, 0), lift=0.003):
    """前から（toward の向きに）面へ落とした点の列と法線"""
    res = cast_many(ob, [Vector(p) - toward * 0.6 for p in pts2], [toward] * len(pts2))
    return [q + n * lift for q, n in res], [n for _, n in res]


def tangent_frame(n):
    t1 = n.cross(V(0, 0, 1))
    if t1.length < 1e-4:
        t1 = n.cross(V(1, 0, 0))
    t1.normalize()
    return t1, n.cross(t1).normalized()


def xstitch(m, p, n, size=0.007, r=0.0022):
    """十字縫い（×）を 1 つ"""
    t1, t2 = tangent_frame(n)
    for a, b in ((t1 + t2, -(t1 + t2)), (t1 - t2, -(t1 - t2))):
        C.tube(m, [p + a * size * 0.7 + n * r * 0.5, p + n * r * 1.4, p + b * size * 0.7 + n * r * 0.5], r, sides=4)


def patch_on(name, role, ob, c, inward, u, v, w, h, thread="thread_cream", style="run", lift=0.004, rot=0.0, n=8):
    """継ぎ当て: 面に沿う布の四角と、まわりの縫い目。c は面の外の中心、inward は面へ向かう向き、u・v は四角の向き。
    style は "run"（なみ縫い）、"x"（十字縫い）、None（縫わない。紙を貼る）"""
    cr, sr = math.cos(rot), math.sin(rot)
    u, v = u * cr + v * sr, v * cr - u * sr
    org = [c + u * ((i / n - 0.5) * w) + v * ((j / n - 0.5) * h) - inward * 0.4 for i in range(n + 1) for j in range(n + 1)]
    res = cast_many(ob, org, [inward] * len(org))
    q = [p + nn * lift for p, nn in res]
    ns = [nn for _, nn in res]
    N = n + 1

    def b(m):
        vs = [m.bm.verts.new(p) for p in q]
        for i in range(n):
            for j in range(n):
                m.bm.faces.new((vs[i * N + j], vs[(i + 1) * N + j], vs[(i + 1) * N + j + 1], vs[i * N + j + 1]))
    o = part(name, role, b, solid=0.004)
    if style:
        ring = [i * N for i in range(N)] + [n * N + j for j in range(1, N)] + [i * N + n for i in range(n - 1, -1, -1)] + [j for j in range(n - 1, 0, -1)]
        mid = q[(n // 2) * N + n // 2]
        pts = [q[k] + (mid - q[k]) * 0.13 + ns[k] * 0.0035 for k in ring]
        if style == "run":
            stitch(name + "_st", pts + [pts[0]], [ns[ring[0]]] * (len(pts) + 1), thread, dash=0.011, gap=0.008, r=0.0022)
        else:
            m = C.M(name + "_x", thread, "doll")
            for k in range(0, len(pts), 2):
                xstitch(m, pts[k], ns[ring[k]], 0.008, 0.0022)
            m.done(smooth=False)
    return o


def shift(m, n0, d):
    for v in C.new_verts(m, n0):
        v.co += d


def band(name, role, rt, zt, rb, zb, lon=None, sy=1.0, cx=0.0, n=40, lace="yarn_red", step=8.0, solid=0.009, lace_r=0.0038):
    """札板の段: 円錐の帯（フェルトの板）を、縦の糸で縅す（赤い毛糸の縦の縫い目が並ぶ）"""
    def b(m):
        n0 = len(m.bm.verts)
        sheet_cone(m, [(rt, zt), (rb, zb)], n=n, sy=sy, lon=lon)
        shift(m, n0, V(cx, 0, 0))
    o = part(name, role, b, solid=solid, fuzz=0.003)
    if lace:
        a0, a1 = lon if lon else (0.0, 360.0)
        m = C.M(name + "_odoshi", lace, "doll")
        k = 0
        a = a0 + step * 0.5
        while a < a1 - step * 0.3:
            ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
            pts = []
            for t in (0.12, 0.5, 0.88):
                z = zt + (zb - zt) * t
                r = rt + (rb - rt) * t + solid * 0.5 + lace_r * 0.6
                pts.append(V(cx + ca * r, sa * r * sy, z))
            C.tube(m, pts, lace_r, sides=5)
            a += step
            k += 1
        m.done(smooth=True)
    return o


def ribbon(m, pts, w, wdirs=None, cols=1, twist=None, cup=0.0, notch=0.0):
    """平たい帯（リボン・披帛・テープ）。wdirs を決めないと、体の軸から外へ向く面になる。
    cols で幅の向きにも割る（なめらかに描いても筒に見えない）。twist は点ごとのねじれ（ラジアン）、
    cup は幅の向きの反り、notch は端を燕尾（V 字）に切る深さ"""
    rows = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if wdirs:
            wd = Vector(wdirs[i]).normalized()
        else:
            out = V(p.x, p.y, 0)
            out = out.normalized() if out.length > 1e-4 else V(0, 1, 0)
            wd = t.cross(out)
            if wd.length < 1e-4:
                wd = V(0, 0, 1)
            wd.normalize()
        if twist:
            wd = Matrix.Rotation(twist[i], 3, t) @ wd
        nrm = t.cross(wd).normalized()
        row = []
        for c in range(cols + 1):
            f = c / cols - 0.5
            q = p + wd * (f * w) + nrm * (cup * (4 * f * f - 1) * w * 0.5)
            if notch and i == len(pts) - 1:
                q -= t * (notch * (1 - 2 * abs(f)))
            row.append(m.bm.verts.new(q))
        rows.append(row)
    for i in range(len(rows) - 1):
        for c in range(cols):
            m.bm.faces.new((rows[i][c], rows[i][c + 1], rows[i + 1][c + 1], rows[i + 1][c]))


def surface_strip(name, role, ob, origins, dirs, w, lift=0.003, solid=0.003):
    """面に沿って貼る細い帯（襟、テープ）。origins から dirs の向きに面へ落とす"""
    res = cast_many(ob, origins, dirs)
    q = [p + n * lift for p, n in res]
    ns = [n for _, n in res]

    def b(m):
        rows = []
        for i, (p, n) in enumerate(zip(q, ns)):
            t = (q[min(i + 1, len(q) - 1)] - q[max(i - 1, 0)]).normalized()
            sd = t.cross(n).normalized() * w * 0.5
            rows.append([m.bm.verts.new(p - sd), m.bm.verts.new(p + sd)])
        for i in range(len(rows) - 1):
            m.bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
    part(name, role, b, solid=solid)
    return q, ns


def strip_h(name, role, ob, pts, w, lift=0.003, solid=0.003):
    """体の軸（z 軸）から水平に外から面へ落とす帯"""
    org, dirs = [], []
    for p in pts:
        d = V(p.x, p.y, 0).normalized()
        org.append(V(0, 0, p.z) + d * 0.6)
        dirs.append(-d)
    return surface_strip(name, role, ob, org, dirs, w, lift, solid)


def facet_ball(m, center, half, u=9, v=7, jit=0.0, seed=0):
    """折り紙の多面体: 少ない分割の球を平らな面のまま"""
    rnd = random.Random(seed)
    for vt in unit_sphere(m, u, v):
        p = vt.co
        vt.co = Vector(center) + V(p.x * half[0], p.y * half[1], p.z * half[2]) + V(rnd.uniform(-jit, jit), rnd.uniform(-jit, jit), rnd.uniform(-jit, jit))


def crumple_ball(m, center, half, amp=0.01, freq=6.0, subdiv=3, seed=0.0):
    """もんだ紙: 球を細かく割り、ボロノイの稜線でしわを寄せる（平らな面のまま描く）"""
    n0 = len(m.bm.verts)
    bmesh.ops.create_icosphere(m.bm, subdivisions=subdiv, radius=1.0)
    for vt in C.new_verts(m, n0):
        d = vt.co.normalized()
        k = noise.noise(d * freq + V(seed, 0, 0), noise_basis="VORONOI_F2F1")
        k2 = noise.noise(d * freq * 2.3 + V(0, seed, 0))
        vt.co = Vector(center) + V(d.x * half[0], d.y * half[1], d.z * half[2]) + d * (amp * (k - 0.35) + amp * 0.35 * k2)


def flower(name, role, c, nrm, r, petals=5, heart="brass"):
    """絹の花（絨花）: 少し反った細長い花びらを 5 枚、真ん中に金の玉"""
    nrm = Vector(nrm).normalized()
    t1, t2 = tangent_frame(nrm)
    m = C.M(name, role, "doll")
    for k in range(petals):
        a = 2 * math.pi * k / petals
        dr = t1 * math.cos(a) + t2 * math.sin(a)
        sd = nrm.cross(dr)
        for vt in unit_sphere(m, 12, 8):
            lx, ly, lz = vt.co.x * r * 0.5, vt.co.y * r * 0.3, vt.co.z * r * 0.09
            lx += r * 0.52
            vt.co = Vector(c) + dr * lx + sd * ly + nrm * (lz + 0.35 * lx * lx / r)
    m.done(smooth=True)
    part(name + "_heart", heart, lambda mm: ball(mm, Vector(c) + nrm * r * 0.08, r * 0.2, seg=10))


def tassel(name, role, top, L, r0=0.008, strands=14):
    """房: 上に結び玉、下へ細い糸の束"""
    m = C.M(name, role, "doll")
    ball(m, top - V(0, 0, r0 * 0.8), r0, 1.0, 1.0, 1.1, 12)
    rnd = random.Random(len(name) + int(top.z * 1000))
    for k in range(strands):
        a = 2 * math.pi * k / strands
        o = V(math.cos(a), math.sin(a), 0)
        p0 = top + o * r0 * 0.55 - V(0, 0, r0 * 1.6)
        L2 = L * rnd.uniform(0.9, 1.05)
        C.tube(m, [p0, p0 + o * r0 * 0.35 - V(0, 0, L2 * 0.5), p0 + o * r0 * 0.6 - V(0, 0, L2)], 0.0017, sides=4)
    m.done(smooth=True)


def accordion(m, a, b, r_in, r_out, folds=8, sides=16, sq=2.0):
    """蛇腹に折った紙の筒（sq を大きくすると角の四角い蛇腹）"""
    N = folds * 2
    pts = [a.lerp(b, i / N) for i in range(N + 1)]
    rs = [r_out if i % 2 == 0 else r_in for i in range(N + 1)]
    C.tube(m, pts, rs, sides=sides, sq=sq)


# ================================================================ A 紙のロボット
def blob_t(m, center, half, n_xy=2.4, n_z=2.4, cuts=6, taper=0.0):
    """角の丸い箱。taper で下ほど太く（重心を下げる）"""
    vs = blob(m, center, half, n_xy, n_z, cuts)
    for v in vs:
        k = 1.0 + taper * (center.z - v.co.z) / half[2]
        v.co.x = center.x + (v.co.x - center.x) * k
        v.co.y = center.y + (v.co.y - center.y) * k
    return vs


def tape(name, ob, ctr, e1, e2, th0, th1, w=0.026, n=12):
    """マスキングテープ: ctr のまわりの e1-e2 面の弧に沿って、角をまたいで貼る"""
    org, dirs = [], []
    for i in range(n + 1):
        th = math.radians(th0 + (th1 - th0) * i / n)
        d = (e1 * math.cos(th) + e2 * math.sin(th)).normalized()
        org.append(ctr + d * 0.6)
        dirs.append(-d)
    surface_strip(name, "tape", ob, org, dirs, w, lift=0.0015, solid=0.0012)


def rrect_helix(c, ax, ay, z0, z1, turns, n_per=48, n=6.0):
    """角の丸い四角に沿って巻くひも（箱の腰や膝に巻く）"""
    pts = []
    N = int(turns * n_per)
    for i in range(N + 1):
        t = i / N
        a = 2 * math.pi * turns * t
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** (2 / n), ca) * ax
        y = math.copysign(abs(sa) ** (2 / n), sa) * ay
        pts.append(Vector(c) + V(x, y, z0 + (z1 - z0) * t))
    return pts


def build_robo():
    """参考: 箱の頭のロボット（四角い窓の目、大きな肩、太い腕と大きなこぶし、腰に巻いた縄、赤い布）。
    取る: 頭は大きく、重心は低く（短く太い脚と大きな足、腰の箱、下ほど太い胴）。肩当てと腰の箱で、胴と手足のつながりを見せる。
    体はどこも角の立った箱（段ボール）。首は短い蛇腹。
    取らない: 頭の葉っぱ、手のちょうちん（指さしの手をふさぐ）、赤い布の前垂れ。背 0.92 m（アンテナの玉まで）"""
    # 足と脚: 塗った段ボールの大きな足、太く短い脚、膝に麻ひも
    for s in (1, -1):
        part("foot", "paint_teal", lambda m, s=s: blob(m, V(0.088 * s, 0.022, 0.045), (0.07, 0.098, 0.045), 12.0, 10.0, 6))
        part("leg", "card", lambda m, s=s: blob(m, V(0.088 * s, 0.0, 0.155), (0.06, 0.06, 0.075), 10.0, 10.0, 6))
        rope("knee_twine", "hemp", rrect_helix(V(0.088 * s, 0, 0), 0.064, 0.064, 0.172, 0.19, 2), r=0.005, sides=6)
    # 腰: 幅の広い箱。縄を 2 巻きして脇で結び、前に赤いフェルトの前垂れ
    pelvis = part("pelvis", "card", lambda m: blob(m, V(0, 0, 0.255), (0.158, 0.108, 0.055), 12.0, 10.0, 6))
    rope("waist_rope", "hemp", rrect_helix(V(0, 0, 0), 0.172, 0.122, 0.27, 0.298, 2), r=0.012)
    part("rope_knot", "hemp", lambda m: ball(m, V(0.12, 0.13, 0.285), 0.02, 1.0, 0.8, 1.1))
    for d, L in ((V(0.02, 0.01, 0), 0.1), (V(-0.012, 0.012, 0), 0.075)):
        rope("rope_end", "hemp", [V(0.12, 0.132, 0.27), V(0.125, 0.138, 0.23) + d * 0.5, V(0.13, 0.14, 0.27 - L) + d], r=0.009)
    # 胴: 下ほど太い箱。胸に新聞紙を貼り、木のボタン 2 つ
    torso = part("torso", "paint_teal", lambda m: blob_t(m, V(0, 0, 0.41), (0.16, 0.118, 0.13), 12.0, 10.0, 8, taper=0.1))
    patch_on("chest_news", "news", torso, V(-0.055, 0.25, 0.44), V(0, -1, 0), V(1, 0, 0), V(0, 0, 1), 0.075, 0.085, style=None, rot=0.12)
    for x, z in ((0.065, 0.47), (0.065, 0.415)):
        p, n = hit(torso, V(x, 0.5, z), V(0, -1, 0))
        button("chest_btn", p + n * 0.005, n, 0.016)
    tape("torso_tape", torso, V(0.11, 0, 0.41), V(0, 1, 0), V(0, 0, 1), -10, 100)
    # 肩: 大きな肩当て。外に割りピン（真鍮）。腕は蛇腹に折った紙の筒、こぶしは大きく
    for s in (1, -1):
        sh = V(0.205 * s, 0, 0.5)
        part("shoulder", "paint_teal", lambda m, sh=sh: blob(m, sh, (0.07, 0.078, 0.058), 8.0, 8.0, 6))
        pin = sh + V(0.068 * s, 0, 0.005)
        part("split_pin", "brass", lambda m, pin=pin, s=s: (C.lathe(m, [(0.0, 0.006), (0.016, 0.004), (0.018, 0.0)], segs=16),
                                                              C.place(m, 0, Matrix.Translation(pin) @ Matrix.Rotation(math.radians(90 * s), 4, "Y"))))
        a0, a1 = V(0.205 * s, 0.005, 0.47), V(0.228 * s, 0.035, 0.305)
        part("arm", "card", lambda m, a0=a0, a1=a1: accordion(m, a0, a1, 0.043, 0.052, folds=6, sides=24, sq=8.0), smooth=False)
        rope("wrist_twine", "hemp", rrect_helix(a1 + V(0, 0, -0.004), 0.054, 0.054, 0.0, 0.016, 2), r=0.0045, sides=6)
        fc = a1 + V(0.004 * s, 0.012, -0.062)
        part("fist", "card", lambda m, fc=fc: blob(m, fc, (0.054, 0.056, 0.056), 8.0, 8.0, 6))
        part("thumb", "card", lambda m, fc=fc, s=s: blob(m, fc + V(-0.045 * s, 0.035, 0.012), (0.017, 0.02, 0.028), 6.0, 6.0))
        for k in range(3):   # 指の折り目
            z = fc.z + 0.03 - k * 0.022
            rope("finger_line", "card", [fc + V(-0.035 * s, 0.057, z - fc.z), fc + V(0.035 * s, 0.057, z - fc.z)], r=0.003, sides=5)
    # 首: 短い蛇腹
    part("neck", "card", lambda m: accordion(m, V(0, 0, 0.53), V(0, 0, 0.575), 0.04, 0.05, folds=2, sides=24, sq=8.0), smooth=False)
    # 頭: 大きな箱（クリームの絵の具）。四角い窓の目 2 つ、角をまたぐテープ、アンテナ
    hc = V(0, 0.005, 0.67)
    head = part("head", "card", lambda m: blob(m, hc, (0.152, 0.128, 0.105), 12.0, 10.0, 8))
    # 箱のふた: 上の 4 枚のふたを、少し開いたまま立てる
    for (ax, w, d, ang) in ((V(0, 1, 0), 0.29, 0.125, 28), (V(0, -1, 0), 0.29, 0.125, 18), (V(1, 0, 0), 0.24, 0.07, 40), (V(-1, 0, 0), 0.24, 0.07, 52)):
        hinge = hc + V(ax.x * 0.148, ax.y * 0.124, 0.103)
        side = V(0, 0, 1).cross(ax)
        up = (V(0, 0, 1) * math.cos(math.radians(90 - ang)) + ax * math.sin(math.radians(90 - ang))).normalized()

        def flap_b(m, hinge=hinge, side=side, up=up, w=w, d=d):
            vs = [m.bm.verts.new(hinge + side * (w * 0.5 * sx) + up * (d * t)) for t in (0.0, 1.0) for sx in (-1, 1)]
            m.bm.faces.new((vs[0], vs[1], vs[3], vs[2]))
        part("box_flap", "card", flap_b, smooth=False, solid=0.006)
    for s in (1, -1):
        p, n = hit(head, hc + V(s * 0.062, 0.5, 0.0), V(0, -1, 0))
        part("eyehole", "hole", lambda m, p=p, n=n: blob(m, p - n * 0.004, (0.026, 0.008, 0.033), 4.0, 4.0, 4))
        fr = [p + n * 0.002 + V(0.031 * math.copysign(1, math.cos(a)) * min(1, abs(math.cos(a)) * 3), 0,
                                     0.038 * math.copysign(1, math.sin(a)) * min(1, abs(math.sin(a)) * 3)) for a in [2 * math.pi * k / 32 for k in range(33)]]
        rope("eye_frame", "card", fr, r=0.004, sides=5)
    tape("head_tape", head, hc + V(-0.1, 0, 0), V(0, 1, 0), V(0, 0, 1), -20, 110)
    part("antenna", "card", lambda m: C.tube(m, [hc + V(0.065, -0.03, 0.09), hc + V(0.075, -0.035, 0.235)], [0.009, 0.007], sides=10))
    rope("antenna_twine", "hemp", helix(hc + V(0.068, -0.031, 0), 0.011, 0.11, 0.14, 4), r=0.003, sides=5)
    part("antenna_ball", "felt_obi", lambda m: ball(m, hc + V(0.076, -0.035, 0.255), 0.026), fuzz=0.003)
    return 0.92


# ================================================================ B 折り紙の武者（縫い目）
def build_musha():
    """参考: 苔の上の小さな武者 2 体（糸の目、紺の布の鎧、大きなボタンの吹返し、三日月の前立、赤い紐の結び目）と、折り紙の多面体（どんぐり）。
    取る: 顔と手は折り紙の多面体。兜と鎧は紺のフェルトの板を、赤い毛糸の縅（縦の縫い目の列）・十字縫い・なみ縫いで固める。
    兜は頭にぴったり（鉢を深く、錣を詰め、忍緒をあごの下で結ぶ）。腕と脚は太く、肩は肩上と大袖、腰は草摺。
    取らない: 刀、苔。背 0.9 m（三日月の先まで）、2.5 頭身"""
    hc = V(0, 0, 0.56)
    head = part("head", "ori_face", lambda m: facet_ball(m, hc, (0.12, 0.11, 0.125), 10, 7, 0.004, seed=3), smooth=False)
    # 目: 黒い糸で、横に縫った細い目
    for s in (1, -1):
        p, n = hit(head, hc + V(s * 0.045, 0.5, -0.03), V(0, -1, 0))
        rope("eye", "thread_ink", [p + V(-0.018, 0, 0.002) + n * 0.002, p + n * 0.004, p + V(0.018, 0, 0.002) + n * 0.002], r=0.0045, sides=6)
    # 兜の鉢: 頭にぴったり、深くかぶる。12 本の筋（フェルトの細い棒）に、星の十字縫い
    prof = [(0.0, 0.722), (0.06, 0.716), (0.1, 0.695), (0.128, 0.655), (0.138, 0.61), (0.14, 0.585)]
    part("kabuto", "felt_indigo", lambda m: sheet_cone(m, prof, n=48), solid=0.012, fuzz=0.003)
    suji = C.M("suji", "felt_indigo2", "doll")
    hoshi = C.M("hoshi", "thread_cream", "doll")
    for k in range(12):
        a = 2 * math.pi * (k + 0.5) / 12
        o = V(math.cos(a), math.sin(a), 0)
        pts = [o * (r + 0.009) + V(0, 0, z + 0.003) for r, z in prof[1:]]
        C.tube(suji, pts, 0.005, sides=6)
        for r, z in prof[2:5]:
            nn = (o * 0.9 + V(0, 0, 0.5 if z > 0.65 else 0.15)).normalized()
            xstitch(hoshi, o * (r + 0.013) + V(0, 0, z + 0.004), nn, 0.006, 0.0018)
    suji.done(subsurf=1)
    hoshi.done(smooth=False)
    rim = [V(math.cos(a) * 0.148, math.sin(a) * 0.148, 0.594) for a in [2 * math.pi * k / 80 for k in range(81)]]
    stitch("rim_st", rim, [V(0, 0, 1)] * 81, "thread_cream", dash=0.014, gap=0.008, r=0.0026)
    part("tehen", "button", lambda m: C.lathe(m, [(0.0, 0.738), (0.022, 0.733), (0.024, 0.722)], segs=16))
    # 眉庇（前のつば）
    part("visor", "felt_indigo2", lambda m: sheet_cone(m, [(0.14, 0.6), (0.192, 0.574)], n=16, lon=(25, 155)), solid=0.01, fuzz=0.003)
    vz = [V(math.cos(math.radians(a)) * 0.18, math.sin(math.radians(a)) * 0.18, 0.586) for a in range(32, 150, 4)]
    stitch("visor_st", vz, [V(0, 0, 1)] * len(vz), "thread_cream", dash=0.012, gap=0.008, r=0.0024)
    # 錣: 3 段、首まわりに詰めて、赤い縅
    for k, (r0, z0, r1, z1) in enumerate(((0.142, 0.598, 0.166, 0.552), (0.158, 0.56, 0.186, 0.512), (0.176, 0.52, 0.206, 0.474))):
        band("shikoro", "felt_indigo2" if k % 2 else "felt_indigo", r0, z0, r1, z1, lon=(140, 400), n=32, step=9.0)
    # 吹返し: 大きく前へ折り返した耳。縁に十字縫い、真ん中に大きな木のボタン
    for s in (1, -1):
        th = math.radians(40 if s > 0 else 140)
        out = V(math.cos(th), math.sin(th), 0)
        c = out * 0.178 + V(0, 0, 0.56)
        rz = Matrix.Rotation(th, 4, "Z")

        def fk(m, c=c, rz=rz):
            vs = blob(m, V(0, 0, 0), (0.013, 0.058, 0.055), 4.0, 3.0, 6)
            for v in vs:
                v.co = c + (rz @ v.co)
        part("fukigaeshi", "felt_indigo", fk, fuzz=0.003)
        xm = C.M("fk_x", "thread_cream", "doll")
        side = V(-math.sin(th), math.cos(th), 0)
        for j in range(12):
            a = 2 * math.pi * j / 12
            p = c + out * 0.015 + side * math.cos(a) * 0.045 + V(0, 0, math.sin(a) * 0.042)
            xstitch(xm, p, out, 0.006, 0.002)
        xm.done(smooth=False)
        button("fk_btn", c + out * 0.017, out, 0.026)
    # 前立: 厚い錫色の三日月（2 つの円の差）。縁を黒い糸でなみ縫い
    R, r, d = 0.1, 0.083, 0.042
    yy = (R * R - r * r + d * d) / (2 * d)
    xx = math.sqrt(R * R - yy * yy)
    ta, ti = math.atan2(yy, xx), math.atan2(yy - d, xx)
    mc = V(0, 0.132, 0.8)

    def crescent(m):
        outer = [V(math.cos(a) * R, 0, math.sin(a) * R) for a in [math.pi - ta + (2 * math.pi - (math.pi - 2 * ta)) * t / 28 for t in range(29)]]
        inner = [V(math.cos(a) * r, 0, math.sin(a) * r + d) for a in [math.pi - ti + (2 * math.pi - (math.pi - 2 * ti)) * t / 28 for t in range(29)]]
        rows = [[m.bm.verts.new(mc + p) for p in row] for row in (outer, inner)]
        for i in range(28):
            m.bm.faces.new((rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]))
    part("maedate", "felt_tin", crescent, solid=0.02, fuzz=0.002)
    arc = [mc + V(math.cos(a) * (R - 0.009), 0.013, math.sin(a) * (R - 0.009)) for a in [math.pi - ta + 0.12 + (2 * math.pi - (math.pi - 2 * ta) - 0.24) * t / 40 for t in range(41)]]
    stitch("maedate_st", arc, [V(0, 1, 0)] * len(arc), "thread_ink", dash=0.011, gap=0.008, r=0.0024)
    button("maedate_base", V(0, 0.125, 0.705), V(0, 1, 0.3), 0.022)
    # 忍緒: 赤い毛糸を両の頬からあごの下へ回し、右の頬の下で結ぶ
    rope("shinobi_l", "yarn_red", [V(-0.135, 0.05, 0.585), V(-0.118, 0.07, 0.52), V(-0.06, 0.11, 0.47), V(0.0, 0.125, 0.458), V(0.06, 0.122, 0.468)], r=0.0065)
    rope("shinobi_r", "yarn_red", [V(0.135, 0.05, 0.585), V(0.115, 0.075, 0.52), V(0.075, 0.112, 0.476)], r=0.0065)
    part("shinobi_knot", "yarn_red", lambda m: ball(m, V(0.07, 0.12, 0.47), 0.017, 1.1, 0.8, 1.0))
    for dx, L in ((0.012, 0.07), (-0.008, 0.055)):
        rope("shinobi_end", "yarn_red", [V(0.07, 0.122, 0.462), V(0.072 + dx, 0.13, 0.43), V(0.074 + dx * 1.5, 0.132, 0.462 - L)], r=0.0055)
    # 胴: 札板の 4 段を重ね、段ごとに赤い縅。胸板に十字縫い
    part("do_core", "felt_indigo2", lambda m: blob(m, V(0, 0, 0.36), (0.128, 0.108, 0.11), 3.0, 2.6, 8))
    for k in range(4):
        zt = 0.462 - k * 0.047
        rt = 0.126 + k * 0.006
        band("do_band", "felt_indigo" if k % 2 == 0 else "felt_indigo2", rt, zt, rt + 0.01, zt - 0.054, sy=0.86, n=48, step=8.0)
    part("munaita", "felt_indigo", lambda m: sheet_cone(m, [(0.1, 0.488), (0.13, 0.46)], n=40, sy=0.86), solid=0.01, fuzz=0.003)
    xm = C.M("munaita_x", "thread_cream", "doll")
    for a in range(40, 145, 13):
        aa = math.radians(a)
        o = V(math.cos(aa), math.sin(aa) * 0.86, 0)
        xstitch(xm, o * 0.124 + V(0, 0, 0.476), (o + V(0, 0, 0.9)).normalized(), 0.006, 0.0019)
    xm.done(smooth=False)
    # 肩: 肩上（肩の丸い当て）と大袖（4 段の札板を縅したもの）
    for s in (1, -1):
        part("watagami", "felt_indigo2", lambda m, s=s: blob(m, V(s * 0.13, 0, 0.47), (0.07, 0.08, 0.03), 3.0, 2.5), fuzz=0.003)
        lon = (-62, 62) if s > 0 else (118, 242)
        for k in range(4):
            zt = 0.49 - k * 0.043
            rt = 0.07 + k * 0.006
            band("sode", "felt_indigo" if k % 2 == 0 else "felt_indigo2", rt, zt, rt + 0.008, zt - 0.05, lon=lon, sy=1.3, cx=0.155 * s, n=14, step=13.0)
        part("sode_knot", "yarn_red", lambda m, s=s: ball(m, V(s * 0.215, 0, 0.495), 0.014, 1.0, 1.2, 0.8))
    # 腕: 太い籠手。前腕に斜めの刺し子、手首に縅した手甲。手は折り紙のこぶし
    for s in (1, -1):
        sh, el, wr = V(0.15 * s, 0, 0.43), V(0.19 * s, 0.045, 0.33), V(0.172 * s, 0.11, 0.265)
        part("kote", "felt_indigo2", lambda m, sh=sh, el=el, wr=wr, s=s: C.tube(m, [sh - V(0.04 * s, 0, 0), sh, el, wr], [0.052, 0.052, 0.05, 0.047], sides=14), subsurf=1, fuzz=0.003)
        ax = (wr - el).normalized()
        e1, e2 = tangent_frame(ax)
        sp = [el.lerp(wr, t) + (e1 * math.cos(t * 9.0) + e2 * math.sin(t * 9.0)) * 0.054 for t in [i / 60 for i in range(61)]]
        stitch("kote_st", sp, [ax] * len(sp), "thread_cream", dash=0.012, gap=0.008, r=0.0024)
        part("tekkou", "felt_indigo", lambda m, wr=wr, el=el: C.tube(m, [wr + (el - wr) * 0.22, wr - (el - wr) * 0.03], [0.054, 0.056], sides=16, caps=False), solid=0.008, fuzz=0.003)
        part("fist", "ori_face", lambda m, wr=wr, s=s: facet_ball(m, wr + V(0.0, 0.015, -0.045), (0.042, 0.038, 0.046), 7, 5, 0.003, seed=7 + s), smooth=False)
    # 草摺: 腰から垂れる 4 枚の札板（前・左右・うしろ）。胴と脚をつなぐ
    for c in (90, 0, 180, 270):
        for k in range(3):
            zt = 0.29 - k * 0.048
            rt = 0.148 + k * 0.012
            band("kusazuri", "felt_indigo" if k % 2 == 0 else "felt_indigo2", rt, zt, rt + 0.012, zt - 0.055, lon=(c - 38, c + 38), sy=0.86, n=16, step=9.5)
    # 帯: 赤い毛糸の太い紐を巻き、前で結んで房を垂らす
    rope("obi", "yarn_red", helix(V(0, 0, 0), 0.142, 0.272, 0.292, 2, sy=0.88), r=0.011)
    part("obi_knot", "yarn_red", lambda m: ball(m, V(0.03, 0.128, 0.282), 0.022, 1.2, 0.8, 1.0))
    for s in (1, -1):
        rope("obi_end", "yarn_red", [V(0.03, 0.135, 0.275), V(0.03 + s * 0.03, 0.16, 0.24), V(0.03 + s * 0.035, 0.168, 0.19)], r=0.009)
    # 袴と脛当て: 太く短い脚。脛当ては縦のなみ縫いと赤い紐
    part("hakama", "felt_indigo", lambda m: sheet_cone(m, [(0.13, 0.27), (0.155, 0.17), (0.17, 0.105)], n=48, sy=0.86), solid=0.008, fuzz=0.003)
    for s in (1, -1):
        lc = V(0.066 * s, 0.008, 0)
        part("suneate", "felt_indigo2", lambda m, lc=lc: C.tube(m, [lc + V(0, 0, 0.15), lc + V(0, 0.006, 0.05)], [0.052, 0.049], sides=14), subsurf=1, fuzz=0.003)
        for a in (60, 90, 120):
            aa = math.radians(a)
            o = V(math.cos(aa), math.sin(aa), 0)
            ln = [lc + o * 0.056 + V(0, 0, z) for z in (0.14, 0.11, 0.08, 0.06)]
            stitch("sune_st", ln, [o] * 4, "thread_cream", dash=0.012, gap=0.008, r=0.0024)
        rope("sune_tie", "yarn_red", [lc + V(math.cos(a) * 0.056, math.sin(a) * 0.056, 0.135) for a in [2 * math.pi * k / 24 for k in range(25)]], r=0.005, sides=6)
        part("tabi", "felt_cream2", lambda m, s=s: blob(m, V(0.066 * s, 0.032, 0.03), (0.047, 0.066, 0.03), 2.4, 2.4), fuzz=0.003)
        coil = [V(0.066 * s + math.cos(a) * (0.012 + 0.032 * a / 18.8) * 0.85, 0.032 + math.sin(a) * (0.012 + 0.032 * a / 18.8) * 1.25, 0.004) for a in [k * 0.3 for k in range(63)]]
        rope("waraji", "hemp", coil, r=0.0045, sides=6)
    return 0.9


# ================================================================ C 絹の人形
def skirt_r(z, prof):
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        if z1 <= z <= z0:
            return r0 + (r1 - r0) * (z0 - z) / (z0 - z1)
    return prof[-1][0] if z < prof[-1][1] else prof[0][0]


def pleated(m, prof, n=72, sy=0.84, pleats=26, amp=(0.0, 0.06)):
    """ひだのある裙: 上から下へ広がる円錐に、三角波のひだ（下ほど深い）"""
    rows = []
    for k, (r, z) in enumerate(prof):
        t = k / (len(prof) - 1)
        am = amp[0] + (amp[1] - amp[0]) * t
        row = []
        for i in range(n):
            a = 2 * math.pi * i / n
            f = (a * pleats / (2 * math.pi)) % 1
            tri = abs(2 * f - 1) * 2 - 1
            rr = r * (1 + am * tri)
            row.append(m.bm.verts.new((math.cos(a) * rr, math.sin(a) * rr * sy, z)))
        rows.append(row)
    for k in range(len(rows) - 1):
        for i in range(n):
            j = (i + 1) % n
            m.bm.faces.new((rows[k][i], rows[k + 1][i], rows[k + 1][j], rows[k][j]))


def sleeve_drape(m, path, steps=22, ring=40, scale=1.0, t0=0.0, folds=2.5, phase=0.0):
    """広袖: 腕の上は布が腕に掛かり、下は前と後ろの 2 枚が重さで真下へ垂れて、底で丸く合わさる（しずくの断面）。
    垂れた所には、下へ走るたるみのひだ（下ほど深い）。袖口は少し広がって開く。
    腕の道筋（肩・肘・手首）は 2 次のベジェ曲線でなめらかにつなぐ（肘で断面の向きが急に変わると布が裂ける）"""
    A, Bm, Cc = path
    B = Bm * 2 - (A + Cc) * 0.5   # t = 0.5 で肘を通る制御点

    def at(t):
        P = A * (1 - t) ** 2 + B * (2 * (1 - t) * t) + Cc * (t * t)
        D = (B - A) * (2 * (1 - t)) + (Cc - B) * (2 * t)
        return P, D.normalized()
    rows = []
    for k in range(steps + 1):
        t = t0 + (1 - t0) * k / steps
        P, D = at(t)
        e1 = D.cross(V(0, 0, 1)).normalized()
        e2 = e1.cross(D).normalized()
        if e2.z < 0:
            e2 = -e2
        down = (V(0, 0, -1) * 0.88 - e2 * 0.12).normalized()
        flare = 1 + 0.12 * max(0.0, (t - 0.82) / 0.18) ** 1.5
        ra = (0.05 + 0.028 * t) * flare
        drop = (0.025 + 0.175 * math.sin(math.pi / 2 * min(1.0, t / 0.88)) ** 1.3) * (1 - 0.18 * max(0.0, (t - 0.86) / 0.14) ** 2)
        row = []
        for i in range(ring):
            a = 2 * math.pi * i / ring
            ca, sa = math.cos(a), math.sin(a)
            if sa >= 0:
                off = e1 * ca * ra + e2 * sa * ra * 0.92
            else:
                u = -sa
                thick = ra * (1 - 0.64 * u ** 1.25)
                fold = 0.013 * u ** 1.2 * math.sin(2 * math.pi * folds * t + phase + 0.8 * ca)
                hang = u * drop * (1 + 0.07 * math.sin(2 * math.pi * (folds + 0.5) * t + phase))
                off = e1 * (ca * thick + fold) + down * hang
            row.append(m.bm.verts.new(P + off * scale))
        rows.append(row)
    for k in range(steps):
        for i in range(ring):
            j = (i + 1) % ring
            m.bm.faces.new((rows[k][i], rows[k + 1][i], rows[k + 1][j], rows[k][j]))


def build_ningyo():
    """参考: 布の人形（白い顔に閉じた目、紺の糸のお団子に玉、赤い房）。着物の組み立ては漢服の襦裙（齐胸襦裙）に直す。
    取る: 交領右衽（左の身頃が上、y の字の襟）、広袖、胸高に結ぶ裙とリボン、披帛。テーマは絹: 繻子のつや、梅の刺繍、絹の花と房、透ける紗。
    取らない: 口紅、袖で手を隠すこと（手は出す）。背 0.95 m（お団子の上まで）、3 頭身"""
    hc = V(0, 0, 0.745)
    head = part("head", "washi", lambda m: ball(m, hc, 0.135, 1.0, 0.95, 1.05, 32))
    # 閉じた目: 黒い糸の刺繍で、下へふくらむ弧
    for s in (1, -1):
        pts2 = [hc + V(s * 0.048 + t * 0.026, 0, -0.03 - 0.009 * (1 - t * t)) for t in [-1 + 2 * k / 8 for k in range(9)]]
        q, _ = on_surface(head, pts2, hc, lift=0.0015)
        rope("eye", "thread_ink", q, r=0.0032, sides=6)
    # 髪: 紺の毛糸を頭に巻きつける。前髪は眉の上で切りそろえる
    def wound_cap(m):
        pts = []
        turns = 26
        for i in range(turns * 40 + 1):
            t = i / (turns * 40)
            lat = math.radians(84 - 124 * t)
            a = 2 * math.pi * turns * t
            r = 0.142
            p = V(math.cos(a) * math.cos(lat) * r, math.sin(a) * math.cos(lat) * r * 0.95, math.sin(lat) * r * 1.05)
            if p.y > 0.05 and p.z < 0.035:
                p = V(p.x, p.y, 0.035)
            pts.append(hc + p)
        C.tube(m, pts, 0.0068, sides=6, caps=True)
    hair = part("hair", "yarn_indigo", wound_cap, smooth=True)
    hair.data.materials[0].node_tree.nodes["Principled BSDF"].inputs["Sheen Weight"].default_value = 0.12
    # お団子 2 つ（双丫髻）。それぞれに絹の花 2 輪と、真珠と房の歩揺を左右に垂らす
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
        d1 = V(s * 0.55, 0.65, 0.5).normalized()
        flower("silk_flower", "silk_rose", c + d1 * 0.064, d1, 0.044)
        d2 = V(s * 0.95, -0.15, 0.3).normalized()
        flower("silk_flower2", "silk_cream", c + d2 * 0.063, d2, 0.034)
        # 歩揺: 赤い絹糸に真珠 3 粒、下に絹の房
        top = c + V(s * 0.05, 0.02, -0.035)
        bot = V(s * 0.178, 0.02, hc.z - 0.07)
        rope("buyao_cord", "silk_red", [top, top.lerp(bot, 0.5) + V(s * 0.006, 0, 0), bot], r=0.0022, sides=5)
        for t in (0.35, 0.62, 0.88):
            part("pearl", "pearl", lambda m, p=top.lerp(bot, t): ball(m, p, 0.0105, seg=12))
        tassel("buyao_tassel", "silk_red", bot - V(0, 0, 0.004), 0.075, 0.009)
    # 裙: 茜の絹を胸の高さで結ぶ。ひだがあり、すそに梅の刺繍の帯
    sk = [(0.136, 0.565), (0.15, 0.48), (0.178, 0.32), (0.212, 0.15), (0.24, 0.02)]
    part("qun", "silk_rose", lambda m: pleated(m, sk, pleats=26, amp=(0.0, 0.055)), smooth=True, solid=0.006)
    part("qun_hem", "silk_emb_rose", lambda m: pleated(m, [(skirt_r(0.115, sk) * 1.015, 0.115), (0.244, 0.018)], pleats=26, amp=(0.045, 0.057)), smooth=True, solid=0.004)
    # 襦: 月白の絹の短い上着（裙の上に肩と胸が出る）
    ru = part("ru", "silk_pale", lambda m: sheet_cone(m, [(0.056, 0.628), (0.108, 0.612), (0.138, 0.578), (0.146, 0.53), (0.148, 0.5)], n=48, sy=0.84), solid=0.007)
    part("ru_cap", "silk_pale", lambda m: C.lathe(m, [(0.056, 0.629), (0.0, 0.629)], segs=24))
    # 交領右衽: 藍に梅を刺繍した襟。下の襟（右の身頃）を先に、上の襟（左の身頃）を重ねる
    for s, lift, nm in ((1, 0.003, "eri_under"), (-1, 0.0062, "eri_over")):
        pts = [V(s * 0.03, -0.045, 0.632), V(s * 0.053, 0.0, 0.626), V(s * 0.05, 0.045, 0.614), V(s * 0.03, 0.09, 0.596),
               V(0.0, 0.112, 0.578), V(-s * 0.035, 0.122, 0.56), V(-s * 0.07, 0.122, 0.545)]
        strip_h(nm, "silk_emb_indigo", ru, pts, 0.036, lift=lift, solid=0.004)
    part("eri_back", "silk_emb_indigo", lambda m: sheet_cone(m, [(0.058, 0.646), (0.064, 0.624)], n=16, lon=(205, 335)), solid=0.005)
    # 裙頭と胸のリボン: クリームの絹の帯、前で蝶結び、長い 2 本の垂れ
    part("qun_tou", "silk_cream", lambda m: sheet_cone(m, [(0.14, 0.578), (0.142, 0.538)], n=48, sy=0.86), solid=0.008)
    kn = V(0, 0.132, 0.556)
    # 結び目: 帯を巻いた小さな結び（平たい布を 1 周）
    m_k = C.M("bow_knot", "silk_cream", "doll")
    ribbon(m_k, [kn + V(math.cos(a) * 0.011, math.sin(a) * 0.008 + 0.002, 0) for a in [2 * math.pi * k / 16 for k in range(17)]], 0.024,
           [V(0, 0, 1)] * 17, cols=3, cup=0.1)
    o = m_k.done(smooth=True)
    o.modifiers.new("sol", "SOLIDIFY").thickness = 0.0025
    part("bow_knot_in", "silk_cream", lambda m: blob(m, kn, (0.009, 0.006, 0.011), 2.4, 2.4, 4))
    for s in (1, -1):
        # 輪: 前の布が外へ出て先で折り返し、後ろの布で戻る。布の面は前を向き、少しふくらむ
        L, d = 0.05, 0.01
        loop = [kn + V(s * L * (1 - math.cos(th)) / 2, d * math.sin(th) + 0.002, 0.012 * (1 - math.cos(th)) / 2 + 0.003 * math.sin(2 * th))
                for th in [2 * math.pi * k / 28 for k in range(29)]]
        wd = [V(-s * 0.3 * (1 - math.cos(th)) / 2, 0, 1) for th in [2 * math.pi * k / 28 for k in range(29)]]
        m_l = C.M("bow_loop", "silk_cream", "doll")
        ribbon(m_l, loop, 0.026, wd, cols=4, cup=0.18)
        o = m_l.done(smooth=True)
        o.modifiers.new("sol", "SOLIDIFY").thickness = 0.0025
        # 垂れ: 裙に沿って下り、ゆるく揺れてねじれ、端は燕尾に切る
        bot = 0.13 if s > 0 else 0.165
        tail, tw = [], []
        for k in range(16):
            z = kn.z - 0.01 - (kn.z - bot) * k / 15
            y = skirt_r(z, sk) * 0.84 * (1 + 0.055 * max(0.0, (0.565 - z) / 0.545)) + 0.01
            tail.append(V(s * (0.01 + 0.034 * k / 15) + 0.009 * math.sin(k * 0.75 + s), y, z))
            tw.append(0.4 * math.sin(k * 0.55 + (0.0 if s > 0 else 1.2)) * k / 15)
        m_t = C.M("bow_tail", "silk_cream", "doll")
        ribbon(m_t, tail, 0.03, [V(1, 0, 0)] * len(tail), cols=4, twist=tw, cup=0.1, notch=0.012)
        o = m_t.done(smooth=True)
        sol = o.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = 0.0025
        sol.offset = 0.0
    # 禁步: 真ん中に翡翠の玉と赤い絹の房
    jz = 0.36
    jy = skirt_r(jz, sk) * 0.84 * 1.02 + 0.022
    rope("jinbu_cord", "silk_red", [kn + V(0, 0.004, -0.012), V(0, skirt_r(0.46, sk) * 0.84 + 0.02, 0.46), V(0, jy, jz + 0.026)], r=0.0022, sides=5)
    part("jade", "jade", lambda m: (C.lathe(m, [(0.0, 0.006), (0.024, 0.004), (0.026, 0.0), (0.024, -0.004), (0.0, -0.006)], segs=24),
                                    C.place(m, 0, Matrix.Translation(V(0, jy, jz)) @ Matrix.Rotation(math.radians(90), 4, "X"))))
    tassel("jinbu_tassel", "silk_red", V(0, jy + 0.002, jz - 0.03), 0.09, 0.01, strands=18)
    # 広袖: 月白の絹の大きな袖。袖口に藍の刺繍の縁。手（和紙）は袖口から出す
    for s in (1, -1):
        path = [V(0.11 * s, 0, 0.6), V(0.2 * s, 0.035, 0.47), V(0.19 * s, 0.115, 0.4)]
        ph = 0.0 if s > 0 else 1.7
        part("xiu", "silk_pale", lambda m, path=path, ph=ph: sleeve_drape(m, path, phase=ph), subsurf=1, solid=0.005)
        part("xiu_edge", "silk_emb_indigo", lambda m, path=path, ph=ph: sleeve_drape(m, path, steps=3, scale=1.03, t0=0.93, phase=ph), subsurf=1, solid=0.004)
        wr = path[-1]
        D = (path[-1] - path[-2]).normalized()
        part("hand", "washi", lambda m, wr=wr, D=D: blob(m, wr + D * 0.035 + V(0, 0, 0.012), (0.026, 0.024, 0.032), 2.2, 2.2))
    # 披帛: 透ける桃色の紗。背中から両腕にかけて、前へ垂らす
    half = [V(0.0, -0.155, 0.585), V(0.1, -0.145, 0.59), V(0.17, -0.085, 0.6), V(0.215, 0.0, 0.575), V(0.245, 0.07, 0.53),
            V(0.255, 0.14, 0.45), V(0.262, 0.17, 0.35), V(0.268, 0.168, 0.25), V(0.275, 0.16, 0.15)]
    full = [V(-p.x, p.y, p.z) for p in reversed(half[1:])] + half
    m_p = C.M("pibo", "silk_gauze", "doll")
    ribbon(m_p, full, 0.06, cols=4, cup=0.12, twist=[0.25 * math.sin(i * 0.7) for i in range(len(full))])
    o = m_p.done(smooth=True)
    sol = o.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.002
    # 靴: 刺繍の絹の靴の先が、すそから出る
    for s in (1, -1):
        part("shoe", "silk_emb_indigo", lambda m, s=s: blob(m, V(0.06 * s, 0.19, 0.018), (0.03, 0.04, 0.018), 2.6, 2.6))
        part("shoe_tip", "silk_rose", lambda m, s=s: ball(m, V(0.06 * s, 0.226, 0.03), 0.012))
    return 0.95


# ================================================================ D 継ぎはぎの巨人
PATCH_FABRICS = [("felt_denim", "thread_cream"), ("felt_indigo2", "thread_cream"), ("felt_plum", "thread_cream"), ("check", "thread_red"),
                 ("felt_cream2", "thread_ink"), ("felt_mustard", "thread_ink"), ("stripe", "thread_ink"), ("felt_teal", "thread_cream"),
                 ("print", "thread_red"), ("felt_rust", "thread_cream"), ("felt_boot", "thread_cream")]


def seam_ring(name, c, axis, r, n=12, size=0.011):
    """手足を胴に縫いつけた輪: 太い十字縫いをぐるりと"""
    axis = Vector(axis).normalized()
    e1, e2 = tangent_frame(axis)
    m = C.M(name, "yarn_cream", "doll")
    for k in range(n):
        a = 2 * math.pi * k / n
        o = e1 * math.cos(a) + e2 * math.sin(a)
        xstitch(m, Vector(c) + o * r, o, size, 0.004)
    m.done(smooth=True)


def build_golem():
    """参考: フェルトの魔法使いの人形の継ぎはぎのコート、紙の王子。代表の注文で、頭の小さなゴーレムのような巨漢にした。
    取る: 体は継ぎはぎの布を綿でふくらませた大きな塊（胴・肩・腰・脚）。手足は太い十字縫いで胴に縫いつける。
    頭とこぶしはもんだ紙で、頭は肩のあいだに低く小さく、太い首巻きで据える。胸は広く（上ほど太い胴）、腰に太い麻縄。肩と頭に綿の雪。
    取らない: とんがり帽、眼鏡、ひげ、杖（おじいさんの意匠はやめた）。背 1.25 m、幅 1.1 m で 7 体でいちばん大きい"""
    rnd = random.Random(5)
    # 足と脚: 大きく低い
    for s in (1, -1):
        part("foot", "felt_boot", lambda m, s=s: blob(m, V(0.17 * s, 0.05, 0.075), (0.13, 0.17, 0.075), 3.0, 2.6, 6), fuzz=0.004)
        leg = part("leg", "felt_grey", lambda m, s=s: blob(m, V(0.17 * s, 0.0, 0.25), (0.125, 0.125, 0.13), 2.6, 2.4, 6), fuzz=0.004)
        patch_on("leg_patch", PATCH_FABRICS[(3 + s) % 11][0], leg, V(0.17 * s, 0.4, 0.25), V(0, -1, 0), V(1, 0, 0), V(0, 0, 1), 0.12, 0.1,
                 PATCH_FABRICS[(3 + s) % 11][1], style="x", rot=0.15 * s, n=6)
        seam_ring("hip_seam", V(0.17 * s, 0.0, 0.345), V(0, 0, 1), 0.118, 14)
    # 腰: 幅の広い塊と、太い麻縄
    pelvis = part("pelvis", "felt_grey", lambda m: blob(m, V(0, 0.01, 0.42), (0.31, 0.22, 0.12), 3.0, 2.6, 7), fuzz=0.004)
    # 胴: 大きな樽。少し前へかがむ
    torso = part("torso", "felt_grey", lambda m: blob_t(m, V(0, 0.04, 0.77), (0.36, 0.27, 0.33), 2.8, 2.4, 8, taper=-0.14), fuzz=0.004)
    k = 0
    for body, axis_y, rows in ((pelvis, 0.01, ((0.42, 9, 0.12),)), (torso, 0.04, ((0.55, 11, 0.13), (0.67, 11, 0.13), (0.79, 11, 0.13), (0.91, 11, 0.12), (1.01, 9, 0.1)))):
        for z, ncol, hh in rows:
            off = rnd.uniform(0, 360 / ncol)
            for j in range(ncol):
                a = math.radians(off + 360 * j / ncol)
                o = V(math.cos(a), math.sin(a), 0)
                role, th = PATCH_FABRICS[k % len(PATCH_FABRICS)]
                w = 2 * math.pi * 0.33 / ncol * rnd.uniform(0.9, 1.1)
                patch_on("body_patch", role, body, V(0, axis_y, z + rnd.uniform(-0.015, 0.015)) + o * 0.6, -o, V(-o.y, o.x, 0), V(0, 0, 1),
                         w, hh * rnd.uniform(0.9, 1.05), th, style="x" if k % 4 == 3 else "run", lift=0.003 + 0.001 * (k % 4),
                         rot=rnd.uniform(-0.12, 0.12), n=6)
                k += 1
    rope("waist_rope", "hemp", helix(V(0, 0.01, 0), 0.335, 0.47, 0.51, 2, sy=0.76), r=0.02)
    part("rope_knot", "hemp", lambda m: ball(m, V(-0.12, 0.25, 0.49), 0.034, 1.1, 0.8, 1.0))
    for dx, L in ((0.02, 0.17), (-0.025, 0.13)):
        rope("rope_end", "hemp", [V(-0.12, 0.255, 0.47), V(-0.12 + dx, 0.265, 0.4), V(-0.12 + dx * 1.6, 0.27, 0.47 - L)], r=0.015)
    # 肩: 大きく丸い塊。腕は太く、十字縫いで縫いつける
    for s in (1, -1):
        shc = V(0.37 * s, 0.03, 0.99)
        shp = part("shoulder", "felt_indigo2", lambda m, shc=shc: blob(m, shc, (0.16, 0.17, 0.13), 2.4, 2.2, 6), fuzz=0.004)
        patch_on("shoulder_patch", "check" if s > 0 else "felt_mustard", shp, shc + V(0.0, 0.0, 0.4), V(0, 0, -1), V(0, 1, 0), V(1, 0, 0), 0.13, 0.12,
                 "thread_red" if s > 0 else "thread_ink", style="run", n=6)
        sh, el, wr = V(0.44 * s, 0.04, 0.92), V(0.47 * s, 0.1, 0.69), V(0.45 * s, 0.19, 0.46)
        arm = part("arm", "felt_grey", lambda m, sh=sh, el=el, wr=wr: C.tube(m, [sh + V(-0.04 * s, 0, 0.04), sh, el, wr], [0.12, 0.12, 0.13, 0.145], sides=16), subsurf=1, fuzz=0.004)
        out = V(s, -0.1, 0).normalized()
        ax = (wr - el).normalized()
        patch_on("arm_patch", PATCH_FABRICS[(7 + s) % 11][0], arm, el.lerp(wr, 0.5) + out * 0.4, -out, ax, ax.cross(out).normalized(), 0.13, 0.12,
                 PATCH_FABRICS[(7 + s) % 11][1], style="run", n=6)
        seam_ring("arm_seam", sh + (el - sh) * 0.18, el - sh, 0.128, 14)
        seam_ring("wrist_seam", wr + (el - wr) * 0.33, wr - el, 0.142, 14)
        fc = wr + V(0, 0.025, -0.075)
        part("fist", "crumple", lambda m, fc=fc, s=s: crumple_ball(m, fc, (0.12, 0.11, 0.13), 0.012, 5.0, 3, 4.0 + s), smooth=False)
        part("thumb", "crumple", lambda m, fc=fc, s=s: crumple_ball(m, fc + V(-0.1 * s, 0.07, 0.03), (0.04, 0.045, 0.06), 0.006, 6.0, 2, 6.0 + s), smooth=False)
    # 頭: 肩のあいだに低く、小さなもんだ紙の頭。黒い糸の細い目
    hc = V(0, 0.12, 1.13)
    head = part("head", "crumple", lambda m: crumple_ball(m, hc, (0.085, 0.08, 0.09), 0.008, 5.0, 3, 9.0), smooth=False)
    # 首巻き: さび色のフェルトの太い輪で、小さな頭を肩のあいだに据える。端を前に垂らす
    ring = [V(math.cos(a) * 0.1, 0.1 + math.sin(a) * 0.09, 1.065) for a in [2 * math.pi * k / 24 for k in range(24)]]
    part("scarf", "felt_rust", lambda m: C.tube(m, ring, 0.04, sides=12, closed=True), subsurf=1, fuzz=0.004)
    m_s = C.M("scarf_end", "felt_rust", "doll")
    ribbon(m_s, [V(-0.06, 0.22, 1.05), V(-0.08, 0.3, 0.95), V(-0.085, 0.33, 0.84)], 0.07, [V(1, 0, 0)] * 3)
    o = m_s.done()
    o.modifiers.new("sol", "SOLIDIFY").thickness = 0.012
    sc = [V(-0.085 + 0.032 * u, 0.335, 0.86) for u in (-1, -0.5, 0, 0.5, 1)]
    stitch("scarf_st", sc, [V(0, 1, 0)] * 5, "thread_cream", dash=0.012, gap=0.008, r=0.0026)
    for s in (1, -1):
        p, n = hit(head, hc + V(s * 0.03, 0.5, 0.005), V(0, -1, 0))
        rope("eye", "thread_ink", [p + V(-0.012, 0, 0) + n * 0.002, p + n * 0.003, p + V(0.012, 0, 0) + n * 0.002], r=0.0035, sides=6)
    # 雪: 肩と頭に綿の雪が少しのる
    for s in (1, -1):
        C.metablob("snow_sh", "cotton", [(V(0.38 * s, 0.03, 1.105), 0.07, (1.4, 1.2, 0.45)), (V(0.31 * s, 0.07, 1.095), 0.05, (1.2, 1.0, 0.45))], 0.014,
                   group="doll", lumps=0.15)
    C.metablob("snow_head", "cotton", [(hc + V(0, -0.01, 0.085), 0.045, (1.2, 1.1, 0.5))], 0.01, group="doll", lumps=0.15)
    return 1.25


BUILDERS = {"robo": build_robo, "musha": build_musha, "ningyo": build_ningyo, "golem": build_golem}


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


VIEWS = {"front": 0, "quarter": 32, "side": 85, "back": 180, "backq": 145, "close": 25}


def shoot(name, top):
    tgt = V(0, 0, top * 0.48)
    for v in A.views.split(","):
        a = math.radians(VIEWS.get(v, 0))
        dist = top * 3.4
        t = tgt
        if v == "close":   # 胸から腰の寄り（布の光り方を見る）
            dist, t = top * 1.5, V(0, 0, top * 0.5)
        C.render(t + V(math.sin(a) * dist, math.cos(a) * dist, top * 0.12), t, 80, os.path.join(OUT, "%s-%s.png" % (name, v)), dof=2.0)


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
    row += [(k, BUILDERS[k]) for k in ("robo", "musha", "ningyo", "golem")]
    xs = [2.85, 1.9, 0.98, 0.05, -0.85, -1.8, -3.0]   # カメラは +Y から見るので、+X が絵の左
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
    if A.export:
        sys.path.insert(0, PERSON)
        import rig_export  # noqa: E402
        rig_export.export(A.doll, A.export)
        sys.exit(0)
    stage(A.size)
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    shoot(A.doll, top)
