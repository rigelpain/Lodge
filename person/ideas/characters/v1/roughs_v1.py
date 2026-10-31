"""新しい人形の案のラフを Blender で描く。外の素材は使わず、形も柄もコードで作る。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/characters/roughs.py -- --doll fusen --views quarter,front
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/characters/roughs.py -- --lineup

--doll
  fusen    紙風船の頭の子: 色の帯の紙風船の頭（前だけ生成りの顔の帯）、毛糸のセーター、フェルトのミトン
  musha    フェルトの兜の小さな武者: クラフト紙を折った体、紺のフェルトの兜と金の鍬形、毛糸で綴じた鎧
  sashiko  刺し子の半纏の子: ちぎり絵の肌、藍の刺し子の半纏、毛糸の耳当て帽とマフラー、縞のもんぺ
  hako     箱の頭の子: 方眼紙を組んだ箱の頭と角の手足、切り紙の前髪、パッチワークのコート
--lineup   いまの 3 体（person/build_dolls.py を読むだけで組む）と 4 体を並べて描く

ラフなので、骨は入れない。形の作り方・紙の素材・光は person/build_dolls.py を写して使う（あちらは import すると組み立てが走るため）。
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
from mathutils import Vector

ap = argparse.ArgumentParser()
ap.add_argument("--doll", default="fusen", choices=("fusen", "musha", "sashiko", "hako"))
ap.add_argument("--views", default="quarter,front")
ap.add_argument("--lineup", action="store_true")
ap.add_argument("--turn", type=float, default=0.0, help="並べるとき、全員をこの角度だけ右へ向ける（遠くから向きが読めるかを見る）")
ap.add_argument("--size", default="800x1000")
ap.add_argument("--samples", type=int, default=64)
ap.add_argument("--out", default="")
ap.add_argument("--blend", default="")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

HERE = os.path.dirname(os.path.abspath(__file__))
PERSON = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = A.out or os.path.join(HERE, "renders")
RND = random.Random(17)


def scene():
    return bpy.context.scene


def lin1(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin(h):
    return (*(lin1(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)), 1.0)


def srgb(h):
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


# ================================================================ 柄の画像（numpy）
def np_image(name, rgb):
    """rgb は sRGB の 0〜1（px, px, 3）。直線の値にして詰める"""
    px = rgb.shape[0]
    rgb = np.clip(rgb, 0, 1)
    li = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    rgba = np.concatenate([li, np.ones((px, px, 1), np.float32)], axis=2)[::-1]
    im = bpy.data.images.new(name, px, px)
    names = [c.name for c in im.colorspace_settings.bl_rna.properties["name"].enum_items]
    if "Linear Rec.709" in names:
        im.colorspace_settings.name = "Linear Rec.709"
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.pack()
    return im


def grain(px, seed, amp):
    return (np.random.default_rng(seed).random((px, px)).astype(np.float32) - 0.5) * amp


def knit_height(px=256, cols=8, rows=10):
    """メリヤス編みの V の高さ（0〜1）。1 目に 2 本の脚が斜めに立つ"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    u = (x * cols) % 1
    v = (y * rows) % 1
    h = np.zeros((px, px), np.float32)
    for s in (-1, 1):
        cx, cy = 0.5 + s * 0.2, 0.5
        dx, dy = s * 0.45, 1.0
        nn = math.hypot(dx, dy)
        dx, dy = dx / nn, dy / nn
        a = (u - cx) * dx + (v - cy) * dy
        b = -(u - cx) * dy + (v - cy) * dx
        h = np.maximum(h, np.sqrt(np.clip(1 - (a / 0.6) ** 2 - (b / 0.23) ** 2, 0, 1)))
    h = h * 0.85 + 0.15 + grain(px, 3, 0.18)
    return np.clip(h, 0, 1)


def sashiko_image(px=512):
    """藍の木綿に白い刺し子（十字刺し）。地の藍は染めむら"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    base = srgb("24365C")[None, None] * (1 + grain(px, 5, 0.12)[..., None])
    rng = np.random.default_rng(6)
    mott = np.kron(rng.random((8, 8)), np.ones((px // 8, px // 8))).astype(np.float32)
    base *= (0.9 + 0.2 * mott)[..., None]
    n = 14   # 格子の数
    m = np.zeros((px, px), np.float32)
    for a, b in ((x, y), (y, x)):
        on_line = np.abs(((a * n) % 1) - 0.5) < 0.06
        dash = ((b * n * 2 + 0.2) % 1) < 0.4      # 1 マスに 2 針、交点で十字
        m = np.maximum(m, (on_line & dash).astype(np.float32))
    thread = srgb("EEE6D4")
    img = base * (1 - m[..., None]) + thread[None, None] * m[..., None]
    return np_image("sashiko", img), m


def patchwork_image(px=512):
    """木綿の端切れを 4×4 で継ぐ。無地・水玉・縞・ギンガム。継ぎ目は白い糸の並縫い"""
    pal = ["D6A23E", "3F7F7A", "B4513C", "2F4366", "E3D6BC", "8FA07A", "C9735A", "5E6E8C"]
    kinds = ["plain", "dots", "stripes", "gingham"]
    rng = np.random.default_rng(9)
    img = np.zeros((px, px, 3), np.float32)
    q = px // 4
    for j in range(4):
        for i in range(4):
            col = srgb(pal[rng.integers(len(pal))])
            kind = kinds[rng.integers(len(kinds))]
            y, x = np.mgrid[0:q, 0:q].astype(np.float32) / q
            tile = np.ones((q, q, 3), np.float32) * col
            lite = np.clip(col * 0.35 + 0.65, 0, 1)
            if kind == "dots":
                d = np.hypot((x * 5) % 1 - 0.5, (y * 5) % 1 - 0.5) < 0.18
                tile[d] = lite
            elif kind == "stripes":
                tile[((x + y * 0.0) * 7) % 1 < 0.35] = lite
            elif kind == "gingham":
                a = ((x * 6) % 1 < 0.5).astype(np.float32)
                b = ((y * 6) % 1 < 0.5).astype(np.float32)
                tile = tile * (1 - 0.25 * (a + b))[..., None] + lite * (0.25 * (a + b))[..., None]
            img[j * q:(j + 1) * q, i * q:(i + 1) * q] = tile
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    seam = np.minimum(np.abs(((x * 4) % 1) - 0.0), np.abs(((x * 4) % 1) - 1.0))
    seam = np.minimum(seam, np.minimum(np.abs((y * 4) % 1), np.abs(1 - (y * 4) % 1)))
    img *= (0.7 + 0.3 * np.clip(seam / 0.012, 0, 1))[..., None]     # 継ぎ目の影
    # 並縫い: 継ぎ目から少し内側に、白い糸の点線
    m = np.zeros((px, px), np.float32)
    for a, b in ((x, y), (y, x)):
        f = (a * 4) % 1
        near = (np.abs(f - 0.04) < 0.008) | (np.abs(f - 0.96) < 0.008)
        dash = ((b * 4 * 10) % 1) < 0.55
        m = np.maximum(m, (near & dash).astype(np.float32))
    img = img * (1 - m[..., None]) + srgb("F1EADB")[None, None] * m[..., None]
    img *= (1 + grain(px, 10, 0.1))[..., None]
    return np_image("patchwork", img), m


def grid_paper_image(px=512, cells=20):
    """方眼紙: 生成りの地に青緑の細い線、5 マスごとに太い線"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    base = srgb("EFE8D4")[None, None] * (1 + grain(px, 12, 0.05)[..., None])
    m = np.zeros((px, px), np.float32)
    for a in (x, y):
        f = (a * cells) % 1
        d = np.minimum(f, 1 - f) * px / cells
        thin = np.clip(1.2 - d, 0, 1) * 0.55
        g = (a * cells / 5) % 1
        d5 = np.minimum(g, 1 - g) * px / cells * 5
        thick = np.clip(2.0 - d5, 0, 1)
        m = np.maximum(m, np.maximum(thin, thick))
    ink = srgb("6FA3B3")
    return np_image("gridpaper", base * (1 - m[..., None]) + ink[None, None] * m[..., None])


def odoshi_image(px=512, rows=8, cols=12):
    """鎧の板を毛糸で綴じる（威）: 紺のフェルトの板の段に、縦に赤と白の毛糸"""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    r = (y * rows) % 1
    row = np.floor(y * rows).astype(int)
    plate = srgb("27325A")[None, None] * (0.78 + 0.32 * np.clip(r / 0.25, 0, 1))[..., None]
    plate *= np.where(r > 0.9, 0.55, 1.0)[..., None]                     # 段の下の影
    c = (x * cols) % 1
    lace = (np.abs(c - 0.5) < 0.17) & (r > 0.12) & (r < 0.86)
    red, white = srgb("C2412F"), srgb("EEE6D6")
    lc = np.where((row % 4 == 1)[..., None], white[None, None], red[None, None])
    twist = 0.85 + 0.15 * np.sin((y * rows * 10 + x * cols * 3) * 6.28)[..., None]   # 撚り
    img = np.where(lace[..., None], lc * twist, plate)
    img *= (1 + grain(px, 14, 0.12))[..., None]
    h = np.where(lace, 1.0, 0.35 * np.clip(r / 0.25, 0, 1))
    return np_image("odoshi", img), h


def height_image(name, h):
    return np_image(name, np.repeat(h[..., None], 3, axis=2))


# ================================================================ 素材（person/build_dolls.py から写し、足した）
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

    def box_image(self, image, scale, blend=0.3):
        tex = self.n("ShaderNodeTexImage", projection="BOX", projection_blend=blend, interpolation="Linear")
        tex.image = image
        self.l(self.obj_coords(scale), 0, tex, "Vector")
        return tex


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
    front = (M.box_image(image, img_scale, 0.25), "Color") if image is not None else lin(color)
    bf = M.n("ShaderNodeNewGeometry")
    side = M.mix((bf, "Backfacing"), front, lin(back))
    at = M.n("ShaderNodeAttribute", attribute_name="tint", attribute_type="GEOMETRY")
    sh = M.n("ShaderNodeMapRange", data_type="FLOAT")
    M.l(at, "Fac", sh, "Value")
    sh.inputs["To Min"].default_value = 1 - tint
    sh.inputs["To Max"].default_value = 1 + tint
    cm = M.n("ShaderNodeCombineColor")
    for k in range(3):
        M.l(sh, 0, cm, k)
    mul = M.mix(1.0, (side, 2), (cm, 0), "MULTIPLY")
    M.l(mul, 2, M.b, "Base Color")
    M.l(fiber_bump(M, co, fiber), 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = rough
    M.b.inputs["Subsurface Weight"].default_value = 0.08
    M.b.inputs["Subsurface Radius"].default_value = (0.01, 0.008, 0.006)
    M.b.inputs["Specular IOR Level"].default_value = 0.25
    return M.m


def plain(name, color, rough=0.6, coat=0.0):
    M = Mat(name)
    M.b.inputs["Base Color"].default_value = lin(color)
    M.b.inputs["Roughness"].default_value = rough
    if coat:
        M.b.inputs["Coat Weight"].default_value = coat
        M.b.inputs["Coat Roughness"].default_value = 0.08
    return M.m


def felt(name, color, fuzz=0.45):
    """フェルト: 細かく絡んだ毛の凹凸、ところどころの色むら、毛羽の光（シーン）"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    fine = M.n("ShaderNodeTexNoise", Scale=260.0, Detail=12.0, Roughness=0.75)
    M.l(co, 0, fine, "Vector")
    big = M.n("ShaderNodeTexNoise", Scale=18.0, Detail=4.0)
    M.l(co, 0, big, "Vector")
    base = lin(color)
    dark = tuple(c * 0.86 for c in base[:3]) + (1,)
    lite = tuple(min(1, c * 1.1) for c in base[:3]) + (1,)
    M.l(M.mix((big, "Fac"), dark, lite), 2, M.b, "Base Color")
    bp = M.n("ShaderNodeBump", Strength=fuzz, Distance=0.003)
    M.l(fine, "Fac", bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 1.0
    M.b.inputs["Sheen Weight"].default_value = 0.7
    M.b.inputs["Sheen Roughness"].default_value = 0.4
    M.b.inputs["Specular IOR Level"].default_value = 0.15
    return M.m


KNIT_H = None


def knit(name, color, stitch=0.016, band=None):
    """毛糸のメリヤス編み。stitch は 1 目の幅（m）。band=(色, 下, 上) で物の z の帯だけ色を変える（編み込みの帯）"""
    global KNIT_H
    if KNIT_H is None:
        KNIT_H = height_image("knit_h", knit_height())
    M = Mat(name)
    tex = M.box_image(KNIT_H, 1 / (stitch * 8), 0.35)
    col = lin(color)
    if band:
        tc = M.n("ShaderNodeTexCoord")
        sep = M.n("ShaderNodeSeparateXYZ")
        M.l(tc, "Object", sep, 0)
        lo = M.n("ShaderNodeMath", operation="GREATER_THAN")
        M.l(sep, "Z", lo, 0)
        lo.inputs[1].default_value = band[1]
        hi = M.n("ShaderNodeMath", operation="LESS_THAN")
        M.l(sep, "Z", hi, 0)
        hi.inputs[1].default_value = band[2]
        both = M.n("ShaderNodeMath", operation="MULTIPLY")
        M.l(lo, 0, both, 0)
        M.l(hi, 0, both, 1)
        colsrc = (M.mix((both, 0), col, lin(band[0])), 2)
    else:
        colsrc = col
    shade = M.n("ShaderNodeMapRange")
    M.l(tex, "Color", shade, 0)
    shade.inputs["To Min"].default_value = 0.5
    shade.inputs["To Max"].default_value = 1.08
    cm = M.n("ShaderNodeCombineColor")
    for k in range(3):
        M.l(shade, 0, cm, k)
    M.l(M.mix(1.0, colsrc, (cm, 0), "MULTIPLY"), 2, M.b, "Base Color")
    fz = M.n("ShaderNodeTexNoise", Scale=700.0, Detail=6.0)
    M.l(M.obj_coords(1.0), 0, fz, "Vector")
    h = M.n("ShaderNodeMath", operation="MULTIPLY_ADD")
    M.l(fz, "Fac", h, 0)
    h.inputs[1].default_value = 0.15
    M.l(tex, "Color", h, 2)
    bp = M.n("ShaderNodeBump", Strength=0.8, Distance=0.004)
    M.l(h, 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 1.0
    M.b.inputs["Sheen Weight"].default_value = 0.9
    M.b.inputs["Sheen Roughness"].default_value = 0.45
    M.b.inputs["Specular IOR Level"].default_value = 0.1
    return M.m


def cloth_image(name, image, height, scale, bump=0.45, sheen=0.3):
    """木綿などの布: 柄の画像と、糸の盛り上がり（height）"""
    M = Mat(name)
    tex = M.box_image(image, scale)
    M.l(tex, "Color", M.b, "Base Color")
    ht = M.box_image(height_image(name + "_h", height), scale)
    wv = M.n("ShaderNodeTexNoise", Scale=900.0, Detail=4.0)
    M.l(M.obj_coords(1.0), 0, wv, "Vector")
    h = M.n("ShaderNodeMath", operation="MULTIPLY_ADD")
    M.l(wv, "Fac", h, 0)
    h.inputs[1].default_value = 0.35
    M.l(ht, "Color", h, 2)
    bp = M.n("ShaderNodeBump", Strength=bump, Distance=0.002)
    M.l(h, 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 0.95
    M.b.inputs["Sheen Weight"].default_value = sheen
    M.b.inputs["Specular IOR Level"].default_value = 0.15
    return M.m


def stripe_cotton(name, c1, c2, period=0.05):
    """縞の木綿（もんぺ）: 縦の縞と細かな織り目"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    wv = M.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X", Scale=1 / period, Distortion=0.6, Detail=1.0)
    M.l(co, 0, wv, "Vector")
    st = M.n("ShaderNodeMath", operation="GREATER_THAN")
    M.l(wv, "Fac", st, 0)
    st.inputs[1].default_value = 0.62
    M.l(M.mix((st, 0), lin(c1), lin(c2)), 2, M.b, "Base Color")
    ck = M.n("ShaderNodeTexChecker", Scale=420.0)
    M.l(co, 0, ck, "Vector")
    bp = M.n("ShaderNodeBump", Strength=0.25, Distance=0.002)
    M.l(ck, "Fac", bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 0.95
    M.b.inputs["Sheen Weight"].default_value = 0.3
    return M.m


def chigiri(name, tones=("EFC6A2", "E6B48C", "F4D2B4"), edge="F8F0E4", scale=12.0):
    """ちぎり絵: 手でちぎった色紙を重ねて貼る。片ごとに色が少し違い、ちぎった縁は白い繊維が毛羽立つ"""
    M = Mat(name)
    co = M.obj_coords(1.0)
    warp = M.n("ShaderNodeTexNoise", Scale=9.0, Detail=5.0)
    M.l(co, 0, warp, "Vector")
    wsub = M.n("ShaderNodeVectorMath", operation="SUBTRACT")
    M.l(warp, "Color", wsub, 0)
    wsub.inputs[1].default_value = (0.5, 0.5, 0.5)
    wsc = M.n("ShaderNodeVectorMath", operation="SCALE")
    M.l(wsub, 0, wsc, 0)
    wsc.inputs["Scale"].default_value = 0.05
    wco = M.n("ShaderNodeVectorMath", operation="ADD")
    M.l(co, 0, wco, 0)
    M.l(wsc, 0, wco, 1)
    vo = M.n("ShaderNodeTexVoronoi", Scale=scale, Randomness=1.0)
    M.l(wco, 0, vo, "Vector")
    sep = M.n("ShaderNodeSeparateColor")
    M.l(vo, "Color", sep, 0)
    c1 = M.mix((sep, 0), lin(tones[0]), lin(tones[1]))
    g = M.n("ShaderNodeMapRange")
    M.l(sep, 1, g, 0)
    g.inputs["From Min"].default_value = 0.65
    g.inputs["From Max"].default_value = 0.7
    c2 = M.mix((g, 0), (c1, 2), lin(tones[2]))
    ed = M.n("ShaderNodeTexVoronoi", Scale=scale, Randomness=1.0)
    ed.feature = "DISTANCE_TO_EDGE"
    M.l(wco, 0, ed, "Vector")
    fn = M.n("ShaderNodeTexNoise", Scale=420.0, Detail=8.0)
    M.l(co, 0, fn, "Vector")
    dd = M.n("ShaderNodeMath", operation="MULTIPLY_ADD")
    M.l(fn, "Fac", dd, 0)
    dd.inputs[1].default_value = 0.05
    M.l(ed, "Distance", dd, 2)
    rim = M.n("ShaderNodeMapRange")
    M.l(dd, 0, rim, 0)
    rim.inputs["From Min"].default_value = 0.03
    rim.inputs["From Max"].default_value = 0.045
    rim.inputs["To Min"].default_value = 1.0
    rim.inputs["To Max"].default_value = 0.0
    M.l(M.mix((rim, 0), (c2, 2), lin(edge)), 2, M.b, "Base Color")
    h = M.n("ShaderNodeMath", operation="MULTIPLY_ADD")
    M.l(rim, 0, h, 0)
    h.inputs[1].default_value = 0.5
    M.l(fn, "Fac", h, 2)
    bp = M.n("ShaderNodeBump", Strength=0.3, Distance=0.002)
    M.l(h, 0, bp, "Height")
    M.l(bp, 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 0.9
    M.b.inputs["Subsurface Weight"].default_value = 0.06
    M.b.inputs["Subsurface Radius"].default_value = (0.01, 0.008, 0.006)
    M.b.inputs["Specular IOR Level"].default_value = 0.2
    return M.m


# ================================================================ 形の小道具（person/build_dolls.py から写した）
def link(ob):
    scene().collection.objects.link(ob)
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


def thicken(ob, t, rim_white=True, offset=0.0):
    mod = ob.modifiers.new("sol", "SOLIDIFY")
    mod.thickness = t
    mod.offset = offset
    mod.use_even_offset = True
    if rim_white and len(ob.data.materials) >= 2:
        mod.material_offset_rim = 1
    return ob


def recalc(ob, smooth):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = smooth
    return ob


def tube(name, pts, radii, sides, mat, seed=0, flat=True, twist=0.0):
    """折れ線に沿った筒（腕・脚）。関節は折り目"""
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
        rings.append([pts[k] + (u * math.cos(2 * math.pi * (a + 0.5) / sides + twist) + v * math.sin(2 * math.pi * (a + 0.5) / sides + twist)) * r
                      for a in range(sides)])
    verts = [p for ring in rings for p in ring]
    faces = []
    for k in range(n - 1):
        for a in range(sides):
            b = (a + 1) % sides
            faces.append((k * sides + a, k * sides + b, (k + 1) * sides + b, (k + 1) * sides + a))
    faces.append(tuple(range(sides))[::-1])
    faces.append(tuple((n - 1) * sides + a for a in range(sides)))
    ob = mesh(name, verts, faces, mat, not flat, seed)
    recalc(ob, not flat)
    if flat:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(ob.data)
        bm.free()
        add_tint(ob.data, seed)
    return ob


def lathe(name, prof, mat, n=32, sy=1.0, smooth=True, cap=True, seed=0, lon=None, wob=0.0):
    """（半径, 高さ）を上から下へ並べた輪郭を回す。lon=(始め°, 終わり°) で一部だけ（鎧の段・草摺）"""
    rnd = random.Random(seed)
    full = lon is None
    a0, a1 = (0.0, 360.0) if full else lon
    m = n if full else n + 1
    verts = []
    for r, z in prof:
        for i in range(m):
            a = math.radians(a0 + (a1 - a0) * i / n)
            rr = r * (1 + rnd.uniform(-wob, wob))
            verts.append(Vector((math.cos(a) * rr, math.sin(a) * rr * sy, z)))
    faces = []
    for k in range(len(prof) - 1):
        for i in range(n):
            j = (i + 1) % m
            faces.append((k * m + i, (k + 1) * m + i, (k + 1) * m + j, k * m + j))
    if full and cap:
        faces.append(tuple(range(n))[::-1])
        faces.append(tuple((len(prof) - 1) * m + i for i in range(n)))
    ob = mesh(name, verts, faces, mat, smooth, seed)
    if full and cap:
        recalc(ob, smooth)
    return ob


def ellipsoid(name, loc, size, mat, seed=0, seg=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=1.0, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = size
    return finish(ob, mat, smooth=True, seed=seed)


def V(*a):
    return Vector(a)


def surface_hit(ob, origin, direction):
    """ob の表面で、origin から direction に進んで当たる所と外向きの法線（世界座標）"""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    obe = ob.evaluated_get(dg)
    inv = ob.matrix_world.inverted()
    ok, loc, nrm, _ = obe.ray_cast(inv @ origin, (inv.to_3x3() @ direction).normalized(), depsgraph=dg)
    if not ok:
        return origin, -direction
    n = (ob.matrix_world.to_3x3() @ nrm).normalized()
    return ob.matrix_world @ loc, (n if n.dot(direction) < 0 else -n)


def ellipse_pts(c, rx, ry, z, n, rot=0.0):
    return [c + V(math.cos(rot + 2 * math.pi * i / n) * rx, math.sin(rot + 2 * math.pi * i / n) * ry, z) for i in range(n)]


def decal(name, ob, at, rx, ry, mat, lift=0.003, k=14, shape=None, tilt=0.0):
    """ob の正面の表面に、平たい形を貼る（目・頬・光の点）。at は貼りたい所の前方の点"""
    p, n = surface_hit(ob, at + V(0, 0.4, 0), V(0, -1, 0))
    u = n.cross(V(0, 0, 1)).normalized()
    w_ = u.cross(n).normalized()
    pts = []
    for i in range(k):
        a = 2 * math.pi * i / k
        x, y = math.cos(a) * rx, math.sin(a) * ry
        if shape == "halfmoon" and y > 0:
            y *= 0.25
        xr = x * math.cos(tilt) - y * math.sin(tilt)
        yr = x * math.sin(tilt) + y * math.cos(tilt)
        pts.append(p + n * lift + u * xr + w_ * yr)
    return mesh(name, pts[::-1], [tuple(range(k))], mat, seed=30)   # 表（法線）が外を向く順に


def eyes(ob, hc, dx, dz, rx, ry, ink, shine, cheek=None, cheek_dx=0.0, cheek_dz=0.0, cheek_r=0.0, shine_dir=-1):
    """目と光の点（と頬）。口は描かない"""
    for s in (1, -1):
        decal("eye", ob, hc + V(s * dx, 0, dz), rx, ry, ink)
        decal("eyeshine", ob, hc + V(s * dx + shine_dir * rx * 0.35, 0, dz + ry * 0.4), rx * 0.32, rx * 0.32, shine, lift=0.0045, k=10)
        if cheek is not None:
            decal("cheek", ob, hc + V(s * cheek_dx, 0, cheek_dz), cheek_r, cheek_r * 0.75, cheek, lift=0.002)


def fuzz(ob, count=2500, length=0.01):
    """毛羽: 短い繊維がはみ出す（③ の麻布と同じ作り）"""
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


# ================================================================ A 紙風船の頭の子
def build_fusen():
    """3 頭身、背 1.08 m。頭は紙風船: 色の帯を縦に貼り合わせた球。顔の帯だけ生成りで幅広く、前がひと目でわかる"""
    hc = V(0, 0, 0.875)
    R = 0.19
    cream = paper("f_face", "F2E3C6", tint=0.03, fiber=0.3)
    cols = {k: paper("f_" + k, c, tint=0.04, fiber=0.3, rough=0.9) for k, c in
            (("red", "CC4A3C"), ("yel", "E2B13C"), ("blu", "3F67A8"), ("grn", "4E8C5A"))}
    order = [("red", 10, 50), ("yel", -30, 10), ("blu", -70, -30), ("grn", -110, -70),
             ("blu", -150, -110), ("yel", 170, 210), ("red", 130, 170)]

    def gore(lon):
        lon %= 360
        if 50 <= lon < 130:
            return 0, (lon - 50) / 80
        for i, (_, a, c) in enumerate(order):
            a2, c2 = a % 360, c % 360
            if (a2 <= lon < c2) if a2 < c2 else (lon >= a2 or lon < c2):
                return i + 1, ((lon - a2) % 360) / 40
        return 1, 0.5

    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=36, radius=1.0, location=hc)
    head = bpy.context.object
    head.name = "head"
    bm = bmesh.new()
    bm.from_mesh(head.data)
    rnd = random.Random(3)
    for v in bm.verts:
        c = v.co
        lon = math.degrees(math.atan2(c.y, c.x))
        lat = math.asin(max(-1, min(1, c.z)))
        _, f = gore(lon)
        bulge = math.sin(math.pi * f) ** 0.6
        crease = 0.006 * math.sin(c.x * 23 + c.z * 11) * math.sin(c.y * 19 - c.z * 7) + 0.004 * math.sin(c.x * 41 - c.y * 37 + c.z * 29)
        r = R * (0.955 + 0.045 * bulge * math.cos(lat) ** 0.5 + crease + rnd.uniform(-0.002, 0.002))
        v.co = V(c.x * r, c.y * r, c.z * r * 0.95)
    bm.to_mesh(head.data)
    bm.free()
    finish(head, [cream] + [cols[k] for k, _, _ in order], smooth=True, seed=1)
    for p in head.data.polygons:
        c = p.center
        p.material_index = gore(math.degrees(math.atan2(c.y, c.x)))[0]
    # 継ぎ目: 帯と帯を貼り合わせた細い白いのりしろ
    glue = paper("f_glue", "F4EEDF", tint=0.0)
    for b in (50, 130, 170, 210, 250, 290, 330, 10):
        cu = bpy.data.curves.new("seam", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = 0.0022
        sp = cu.splines.new("POLY")
        pts = []
        for k in range(25):
            lat = math.radians(-70 + 150 * k / 24)
            a = math.radians(b)
            r = R * (0.958 + 0.004)
            pts.append(hc + V(math.cos(a) * math.cos(lat) * r, math.sin(a) * math.cos(lat) * r, math.sin(lat) * r * 0.95))
        sp.points.add(len(pts) - 1)
        for p_, q in zip(sp.points, pts):
            p_.co = (*q, 1)
        link(bpy.data.objects.new("seam", cu)).data.materials.append(glue)
    # 吹き口: てっぺんの丸い紙と穴
    lathe("fusen_cap", [(0.0, hc.z + R * 0.95 + 0.006), (0.034, hc.z + R * 0.95 + 0.004), (0.036, hc.z + R * 0.95 - 0.006)], cream, n=16, cap=False)
    ellipsoid("fusen_hole", hc + V(0, 0, R * 0.95 + 0.0065), (0.009, 0.009, 0.002), plain("hole", "2A2220", 0.9))
    ink = paper("f_ink", "231B19", back="231B19", tint=0.02, rough=0.6)
    shine = paper("f_shine", "FBF6EC", tint=0.0)
    blush = paper("f_blush", "E8907C", tint=0.0, fiber=0.2)
    eyes(head, hc, 0.052, -0.012, 0.021, 0.029, ink, shine, blush, 0.092, -0.058, 0.022)
    # セーター: 毛糸。とっくり襟、ゆったりした胴、すそのゴム編み
    plum = knit("k_plum", "8E4A6C", 0.017, band=("D9C7A4", 0.555, 0.595))
    sw = lathe("sweater", [(0.06, 0.745), (0.1, 0.745), (0.118, 0.72), (0.112, 0.69), (0.15, 0.66), (0.185, 0.615),
                           (0.2, 0.52), (0.21, 0.4), (0.214, 0.3), (0.205, 0.245), (0.175, 0.225)], plum, n=40, sy=0.86)
    sw.location.z = 0.0
    # 脚: 灰の毛糸のタイツと、フェルトの長靴
    grey = knit("k_grey", "4A4549", 0.012)
    boot = felt("ft_boot", "6B4A35")
    for s in (1, -1):
        tube("leg", [V(0.075 * s, 0, 0.25), V(0.08 * s, 0.005, 0.08)], [0.048, 0.044], 14, grey, flat=False)
        lathe("boot", [(0.05, 0.13), (0.055, 0.06), (0.06, 0.02), (0.05, 0.0)], boot, n=20).location = V(0.08 * s, 0.02, 0)
        ellipsoid("toe", V(0.08 * s, 0.06, 0.03), (0.05, 0.06, 0.035), boot)
    # 腕: セーターの袖。手はからし色のフェルトのミトン
    mitt = felt("ft_mitt", "D39B32")
    for s in (1, -1):
        sh, el, wr = V(0.165 * s, 0, 0.63), V(0.235 * s, 0.025, 0.5), V(0.25 * s, 0.075, 0.38)
        tube("sleeve", [sh - V(0.04 * s, 0, 0), sh, el, wr], [0.055, 0.058, 0.054, 0.05], 16, plum, flat=False)
        ellipsoid("mitten", wr + V(0.004 * s, 0.012, -0.058), (0.045, 0.038, 0.06), mitt, seed=5)
        ellipsoid("thumb", wr + V(-0.03 * s, 0.03, -0.045), (0.017, 0.017, 0.028), mitt, seed=6)
    return 1.09


# ================================================================ B フェルトの兜の小さな武者
def build_musha():
    """2.5 頭身、背 0.82 m（鍬形の先で 0.98 m）。クラフト紙を折った体に、紺のフェルトの兜、毛糸で綴じた鎧"""
    hc = V(0, 0, 0.6)
    kraft = paper("m_kraft", "BC9064", back="D9BE98", tint=0.07, fiber=0.22)
    navy = felt("ft_navy", "283456")
    gold = felt("ft_gold", "D8A23A")
    red = felt("ft_red", "BE3B2E")
    dark = felt("ft_dark", "3A2C26")
    oimg, oh = odoshi_image()
    odo = cloth_image("odoshi", oimg, oh, 3.6, bump=0.6, sheen=0.5)
    # 頭: 折ったクラフト紙の多面体。顔は前が平ら
    head_pts = [hc + V(0, 0.03, -0.14), hc + V(0, -0.01, 0.15), hc + V(0, 0.125, -0.01)] + \
        ellipse_pts(hc + V(0, 0.01, -0.09), 0.1, 0.095, 0, 7) + ellipse_pts(hc + V(0, 0, -0.01), 0.14, 0.125, 0, 9, 0.2) + \
        ellipse_pts(hc + V(0, -0.01, 0.07), 0.13, 0.12, 0, 9) + [hc + V(sx * 0.07, 0.12, z) for sx in (1, -1) for z in (0.03, -0.06)]
    head = hull("head", head_pts, kraft, 1)
    ink = felt("ft_eye", "17110F", 0.2)
    shine = plain("m_shine", "FBF6EC", 0.5)
    eyes(head, hc, 0.052, -0.03, 0.026, 0.026, ink, shine, red, 0.088, -0.075, 0.018)
    # 兜の鉢: 紺のフェルト。筋を 16 本立てる
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=24, radius=1.0, location=hc + V(0, -0.01, 0.025))
    bowl = bpy.context.object
    bowl.name = "kabuto"
    bm = bmesh.new()
    bm.from_mesh(bowl.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < -0.02], context="FACES")
    for v in bm.verts:
        c = v.co
        lon = math.atan2(c.y, c.x)
        r = 0.168 * (1 + 0.035 * abs(math.cos(8 * lon)) ** 4 * min(1, 1 - c.z))
        v.co = V(c.x * r, c.y * r, c.z * r * 1.05)
    bm.to_mesh(bowl.data)
    bm.free()
    finish(bowl, navy, smooth=True, seed=2)
    thicken(bowl, 0.012, rim_white=False, offset=1.0)
    ellipsoid("tehen", hc + V(0, -0.01, 0.2), (0.022, 0.022, 0.014), gold)
    # 眉庇: 前に出たつば
    visor = lathe("visor", [(0.168, hc.z + 0.03), (0.215, hc.z + 0.005)], navy, n=12, lon=(25, 155), smooth=True)
    thicken(visor, 0.01, rim_white=False)
    # 吹返し: 兜の両脇で外へ折り返した耳
    for s in (1, -1):
        fk = mesh("fukigaeshi", [hc + V(s * 0.16, 0.08, 0.035), hc + V(s * 0.16, -0.02, 0.035), hc + V(s * 0.215, -0.01, -0.04), hc + V(s * 0.215, 0.1, -0.03)],
                  [(0, 1, 2, 3)], [navy], seed=7)
        thicken(fk, 0.012, rim_white=False)
    # 鍬形: 金のフェルトの三日月を 2 本。顔の向きを遠くから示す
    for s in (1, -1):
        outer, inner = [], []
        for i in range(10):
            t = i / 9
            a = math.radians(80 * t)
            outer.append(hc + V(s * (0.03 + 0.15 * math.sin(a) + 0.02 * t), 0.19 + 0.03 * t, 0.06 + 0.24 * t - 0.02 * math.cos(a)))
            w = 0.035 * (1 - t) ** 0.7 + 0.004
            inner.append(outer[-1] + V(-s * w, 0, -w * 0.4))
        verts = outer + inner
        faces = [(i, i + 1, 11 + i, 10 + i) for i in range(9)]
        kw = mesh("kuwagata", verts, faces, [gold], seed=8)
        thicken(kw, 0.012, rim_white=False)
    ellipsoid("maedate", hc + V(0, 0.19, 0.06), (0.032, 0.008, 0.032), red)
    # 錣: うしろと横を守る 3 段（毛糸で綴じた板）
    for k in range(3):
        zt = hc.z + 0.03 - k * 0.042
        rt = 0.165 + k * 0.022
        sk = lathe("shikoro", [(rt, zt), (rt + 0.03, zt - 0.05)], odo, n=24, lon=(150, 390), smooth=True)
        thicken(sk, 0.008, rim_white=False)
    # 胴と草摺（毛糸で綴じた鎧）
    lathe("do", [(0.07, 0.48), (0.12, 0.475), (0.14, 0.44), (0.145, 0.38), (0.135, 0.33), (0.12, 0.32)], odo, n=32, sy=0.85)
    lathe("hips", [(0.12, 0.33), (0.12, 0.2)], kraft, n=10, sy=0.85, smooth=False)
    for i in range(4):
        a = 90 + i * 90
        kz = lathe("kusazuri", [(0.13, 0.34), (0.2, 0.16)], odo, n=8, sy=0.88, lon=(a - 40, a + 40))
        thicken(kz, 0.01, rim_white=False)
    # 脚と足: クラフト紙の角の脚、こげ茶のフェルトの足袋
    for s in (1, -1):
        tube("leg", [V(0.06 * s, 0, 0.2), V(0.065 * s, 0.01, 0.06)], [0.04, 0.036], 6, kraft, seed=9)
        ellipsoid("foot", V(0.066 * s, 0.03, 0.03), (0.045, 0.065, 0.032), dark)
    # 腕: クラフト紙。前腕は紺の籠手、肩には大袖（毛糸で綴じた板）
    for s in (1, -1):
        sh, el, wr = V(0.14 * s, 0, 0.45), V(0.19 * s, 0.03, 0.36), V(0.17 * s, 0.1, 0.28)
        tube("arm", [sh - V(0.03 * s, 0, 0), sh, el], [0.04, 0.04, 0.036], 6, kraft, seed=10)
        tube("kote", [el, wr], [0.045, 0.042], 12, navy, flat=False)
        hull("hand", [wr + V(x, y, z) for x in (-0.022, 0.022) for y in (-0.01, 0.03) for z in (-0.045, -0.005)], kraft, 11)
        so = mesh("osode", [V(0.15 * s, 0.07, 0.49), V(0.15 * s, -0.07, 0.49), V(0.2 * s, -0.08, 0.35), V(0.2 * s, 0.08, 0.35)], [(0, 1, 2, 3)], [odo], seed=12)
        thicken(so, 0.01, rim_white=False)
    return 0.98


# ================================================================ C 刺し子の半纏の子
def build_sashiko():
    """3.5 頭身、背 1.3 m。ちぎり絵の肌、藍の刺し子の半纏、毛糸の耳当て帽とマフラー、縞のもんぺ"""
    hc = V(0, 0, 1.07)
    skin = chigiri("c_skin")
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.165, location=hc)
    head = bpy.context.object
    head.name = "head"
    head.scale = (1.0, 0.95, 1.05)
    finish(head, skin, smooth=True, seed=1)
    ink = paper("c_ink", "1E1816", back="1E1816", tint=0.02, rough=0.6)
    shine = paper("c_shine", "FBF6EC", tint=0.0)
    blush = chigiri("c_blush", ("E28D7A", "D97A6A", "EA9C88"), scale=60.0)
    eyes(head, hc, 0.058, -0.03, 0.019, 0.026, ink, shine, blush, 0.098, -0.075, 0.026)
    # 耳当て帽: 錆色の毛糸に生成りの編み込みの帯、てっぺんにぼんぼり
    rust = knit("k_rust", "B04E2C", 0.014, band=("E7DCC4", 0.05, 0.09))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1.0, location=hc + V(0, -0.012, 0.0))
    cap = bpy.context.object
    cap.name = "cap"
    bm = bmesh.new()
    bm.from_mesh(cap.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < (0.12 if f.calc_center_median().y > 0.3 else -0.05)], context="FACES")
    for v in bm.verts:
        v.co = V(v.co.x * 0.185, v.co.y * 0.18, v.co.z * 0.2)
    bm.to_mesh(cap.data)
    bm.free()
    finish(cap, rust, smooth=True, seed=2)
    thicken(cap, 0.02, rim_white=False, offset=1.0)
    cream = knit("k_cream", "E7DCC4", 0.012)
    rust2 = knit("k_rust2", "B04E2C", 0.014)
    for s in (1, -1):
        ellipsoid("earflap", hc + V(s * 0.178, -0.012, -0.07), (0.03, 0.075, 0.085), rust2, seed=3)
        tube("tie", [hc + V(s * 0.18, -0.01, -0.15), hc + V(s * 0.175, 0.0, -0.3)], [0.008, 0.007], 8, cream, flat=False)
    pom = ellipsoid("pompom", hc + V(0, -0.01, 0.225), (0.055, 0.055, 0.05), felt("yarnball", "E7DCC4", 1.2), seed=4)
    fuzz(pom, 2500, 0.012)
    # マフラー: 生成りの毛糸。首にひと巻きして、前に端を垂らす
    bpy.ops.mesh.primitive_torus_add(major_radius=0.095, minor_radius=0.045, location=(0, 0.005, 0.9))
    sc_ = bpy.context.object
    sc_.name = "scarf"
    sc_.scale = (1.0, 0.9, 0.8)
    finish(sc_, cream, smooth=True, seed=5)
    tube("scarf_end", [V(0.06, 0.09, 0.88), V(0.085, 0.165, 0.76), V(0.09, 0.185, 0.64)], [0.04, 0.038, 0.036], 12, cream, flat=False)
    # 半纏: 藍の木綿に白い刺し子。四角い身頃、黒い掛け衿
    simg, sm = sashiko_image()
    ai = cloth_image("sashiko", simg, sm, 3.0, bump=0.6)
    lathe("hanten", [(0.07, 0.915), (0.13, 0.905), (0.2, 0.86), (0.215, 0.76), (0.225, 0.6), (0.235, 0.47), (0.232, 0.45)], ai, n=40, sy=0.8)
    collar = plain("collar", "1B1A1E", 0.9)
    hanten = bpy.data.objects["hanten"]
    for s in (1, -1):
        pts = []
        for i in range(8):
            t = i / 7
            z = 0.9 - 0.44 * t
            xo = s * (0.025 + 0.03 * t)
            p, n = surface_hit(hanten, V(xo, 0.5, z), V(0, -1, 0))
            pts.append((p + n * 0.004, n))
        verts, faces = [], []
        for i, (p, n) in enumerate(pts):
            side = n.cross(V(0, 0, 1)).normalized() * 0.024
            verts += [p - side, p + side]
        faces = [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(7)]
        cb = mesh("eri", verts, faces, [collar], seed=6)
        thicken(cb, 0.008, rim_white=False)
    # 腕: 角ばった広い袖はひじまで。前腕は錆色の毛糸の腕カバー、手はちぎり絵
    for s in (1, -1):
        sh, el, wr = V(0.19 * s, 0, 0.84), V(0.28 * s, 0.03, 0.68), V(0.265 * s, 0.1, 0.55)
        tube("sleeve", [sh - V(0.05 * s, 0, 0), sh, el], [0.075, 0.08, 0.088], 6, ai, seed=7)
        tube("armwarmer", [el, wr], [0.045, 0.04], 14, rust2, flat=False)
        ellipsoid("hand", wr + V(0, 0.015, -0.045), (0.036, 0.03, 0.048), skin, seed=8)
        ellipsoid("thumb", wr + V(-0.026 * s, 0.03, -0.03), (0.013, 0.013, 0.024), skin, seed=9)
    # もんぺ: 縞の木綿。足首ですぼめる。足もとは墨色のフェルトの長靴
    mon = stripe_cotton("monpe", "6B4B3A", "8C6E55", 0.045)
    boot = felt("ft_boot2", "3A3533")
    lathe("hip", [(0.17, 0.5), (0.18, 0.42), (0.12, 0.36)], mon, n=24, sy=0.8)
    for s in (1, -1):
        tube("pants", [V(0.085 * s, 0, 0.46), V(0.095 * s, 0.01, 0.24), V(0.095 * s, 0.02, 0.14)], [0.09, 0.08, 0.055], 16, mon, flat=False)
        lathe("boot", [(0.055, 0.15), (0.058, 0.04), (0.055, 0.0)], boot, n=18).location = V(0.095 * s, 0.025, 0)
        ellipsoid("toe", V(0.095 * s, 0.07, 0.03), (0.05, 0.065, 0.035), boot)
    return 1.32


# ================================================================ D 箱の頭の子
def build_hako():
    """3.5 頭身、背 1.17 m。方眼紙を組んだ四角い箱の頭と、角の手足。切り紙の前髪。パッチワークのコート"""
    hc = V(0, 0, 0.995)
    S = 0.17
    grid = paper("h_grid", image=grid_paper_image(), img_scale=3.2, tint=0.06, fiber=0.1)
    # 頭: 箱。面は少しふくらみ、稜線はくっきり
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=6, use_grid_fill=True)
    for v in bm.verts:
        c = v.co
        mx = max(abs(c.x), abs(c.y), abs(c.z))
        puff = 1 + 0.025 * (1 - (sorted([abs(c.x), abs(c.y), abs(c.z)])[1]) ** 2)
        v.co = V(c.x * S * (puff if abs(c.x) == mx else 1), c.y * S * (puff if abs(c.y) == mx else 1), c.z * S * 0.92 * (puff if abs(c.z) == mx else 1))
    me = bpy.data.meshes.new("head")
    bm.to_mesh(me)
    bm.free()
    head = finish(link(bpy.data.objects.new("head", me)), grid, seed=1)
    head.location = hc
    side_tint = {0: 0.62, 1: 0.45, 2: 0.55}
    me.attributes["tint"].data.foreach_set("value", [side_tint[max(range(3), key=lambda i: abs(p.normal[i]))] + (0.08 if p.normal[max(range(3), key=lambda i: abs(p.normal[i]))] < 0 else 0) for p in me.polygons])
    # のりしろ: うしろの稜線から少しめくれる
    tab = mesh("norishiro", [hc + V(-0.15, -S - 0.002, S * 0.92), hc + V(0.15, -S - 0.002, S * 0.92), hc + V(0.13, -S - 0.03, S * 0.92 - 0.02), hc + V(-0.13, -S - 0.03, S * 0.92 - 0.02)],
               [(0, 1, 2, 3)], [grid, paper("h_back", "F6F2EA")], seed=2)
    thicken(tab, 0.003)
    ink = paper("h_ink", "1E1A1A", back="1E1A1A", tint=0.02, rough=0.55)
    shine = paper("h_shine", "FBF6EC", tint=0.0)
    blush = paper("h_blush", "E68C7C", tint=0.0, fiber=0.25)
    eyes(head, hc, 0.065, -0.035, 0.024, 0.032, ink, shine, blush, 0.112, -0.09, 0.024)
    # 前髪: こげ茶の紙を箱のてっぺんにかぶせ、前に折って、すそはぎざぎざに切る
    hair = paper("h_hair", "4A3326", back="E8DCC6", tint=0.05, rough=0.7)
    T = S * 0.92 * 1.03 + 0.004
    top = mesh("hair_top", [hc + V(-S - 0.006, -S - 0.006, T), hc + V(S + 0.006, -S - 0.006, T), hc + V(S + 0.006, S + 0.006, T), hc + V(-S - 0.006, S + 0.006, T)],
               [(0, 1, 2, 3)], [hair, hair], seed=3)
    thicken(top, 0.004)
    zig = [hc + V(-S - 0.006 + i * (2 * S + 0.012) / 12, S + 0.008, T - (0.075 if i % 2 else 0.045)) for i in range(13)]
    up = [hc + V(-S - 0.006 + i * (2 * S + 0.012) / 12, S + 0.008, T) for i in range(13)]
    fr = mesh("bangs", up + zig, [(i, 13 + i, 14 + i, i + 1) for i in range(12)], [hair, hair], seed=4)
    thicken(fr, 0.004)
    for s in (1, -1):
        sd = mesh("hair_side", [hc + V(s * (S + 0.008), S + 0.006, T), hc + V(s * (S + 0.008), -S - 0.006, T), hc + V(s * (S + 0.008), -S - 0.006, T - 0.12),
                                hc + V(s * (S + 0.008), S - 0.04, T - 0.16), hc + V(s * (S + 0.008), S + 0.006, T - 0.1)], [(0, 1, 2, 3, 4)], [hair, hair], seed=5)
        thicken(sd, 0.004)
    tube("neck", [V(0, 0, 0.84), V(0, 0, 0.8)], [0.04, 0.04], 4, grid, seed=6, twist=math.pi / 4)
    # コート: 端切れを継いだパッチワーク。ひざ上までの A ライン、からし色のフェルトのボタン
    pimg, pm = patchwork_image()
    pw = cloth_image("patch", pimg, pm, 3.6, bump=0.5)
    lathe("coat", [(0.06, 0.83), (0.11, 0.825), (0.165, 0.79), (0.19, 0.71), (0.205, 0.56), (0.23, 0.4), (0.24, 0.32)], pw, n=36, sy=0.82)
    btn = felt("ft_btn", "D6A23E")
    coat = bpy.data.objects["coat"]
    for z in (0.74, 0.62, 0.5):
        p, n = surface_hit(coat, V(0, 0.5, z), V(0, -1, 0))
        ellipsoid("button", p + n * 0.006, (0.018, 0.008, 0.018), btn)
    # 腕と脚: 方眼紙の四角い筒。袖はひじの下まで。手も小さな箱
    for s in (1, -1):
        sh, el, wr = V(0.175 * s, 0, 0.77), V(0.25 * s, 0.03, 0.61), V(0.23 * s, 0.1, 0.48)
        tube("arm", [sh - V(0.03 * s, 0, 0), sh, el, wr], [0.045, 0.045, 0.043, 0.04], 4, grid, seed=7, twist=math.pi / 4)
        tube("sleeve", [sh - V(0.04 * s, 0, 0), sh, el + (wr - el) * 0.25], [0.062, 0.064, 0.064], 14, pw, flat=False)
        d = (wr - el).normalized()
        hull("hand", [wr + d * dd + V(x, y, 0) for dd in (0.0, 0.07) for x in (-0.03, 0.03) for y in (-0.02, 0.02)], grid, 8)
        tube("leg", [V(0.08 * s, 0, 0.34), V(0.085 * s, 0.01, 0.07)], [0.045, 0.043], 4, grid, seed=9, twist=math.pi / 4)
    shoe = felt("ft_shoe", "2F6A6E")
    for s in (1, -1):
        ellipsoid("shoe", V(0.085 * s, 0.03, 0.04), (0.055, 0.08, 0.045), shoe)
    return 1.17


BUILDERS = {"fusen": build_fusen, "musha": build_musha, "sashiko": build_sashiko, "hako": build_hako}


# ================================================================ 撮影台・光・カメラ（build_dolls.py と同じ考え）
def backdrop(size=14.0, color="CDBBA2"):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, -1.0, 0))
    bg = bpy.context.object
    bg.name = "backdrop"
    bm = bmesh.new()
    bm.from_mesh(bg.data)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=24, use_grid_fill=True)
    for v in bm.verts:
        if v.co.y < -1.0:
            v.co.z = (abs(v.co.y) - 1.0) ** 2 * 0.8
    bm.to_mesh(bg.data)
    bm.free()
    for p in bg.data.polygons:
        p.use_smooth = True
    bg.data.materials.append(plain("backdrop", color, 0.95))
    return bg


def area(name, loc, size, energy, color="FFF1DE", aim=(0, 0, 0.7)):
    L = bpy.data.lights.new(name, "AREA")
    L.size = size
    L.energy = energy
    L.color = lin(color)[:3]
    o = link(bpy.data.objects.new(name, L))
    o.location = loc
    o.rotation_euler = V(0, 0, -1).rotation_difference(V(*aim) - V(*loc)).to_euler()
    return o


def render_setup(size):
    sc = scene()
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = lin("D8CCBA")
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22
    sc.world = w
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
    rx, ry = (int(v) for v in size.split("x"))
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = -0.45


def aim_cam(cam, loc, tgt):
    cam.location = loc
    d = tgt - loc
    cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, math.atan2(d.y, d.x) - math.pi / 2)


VIEWS = {"front": 0, "quarter": 32, "side": 85, "back": 180, "left": -32, "backq": 145}


def shoot_single(name, top):
    bg = backdrop()
    area("key", (-1.7, 1.3, 1.8), 1.4, 210)
    area("fill", (1.8, 1.7, 0.9), 2.5, 28, "E8EEF8")
    area("rim", (0.9, -1.5, 2.1), 0.8, 130)
    render_setup(A.size)
    cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    cam.data.lens = 80
    scene().camera = cam
    tgt = V(0, 0, top * 0.52)
    for v in A.views.split(","):
        a = math.radians(VIEWS.get(v, 0))
        dist = top * 3.3
        aim_cam(cam, tgt + V(math.sin(a) * dist, math.cos(a) * dist, top * 0.18), tgt)
        bg.rotation_euler = (0, 0, -a)
        scene().render.filepath = os.path.join(OUT, "%s-%s.png" % (name, v))
        bpy.ops.render.render(write_still=True)
        print("wrote", scene().render.filepath)


# ================================================================ 並べる
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
    top = fn()
    emp = bpy.data.objects.new(name, None)
    link(emp)
    for ob in set(bpy.data.objects) - before:
        if ob is not emp and ob.parent is None:
            ob.parent = emp
    return emp, top


def lineup():
    ns = build_old_three()   # ここで場面が空にされる
    row = [("kasa", ns["build_kasa"], 1.47), ("origami", ns["build_origami"], 1.45), ("news", ns["build_news"], 1.02)]
    row += [(k, BUILDERS[k], None) for k in ("fusen", "musha", "sashiko", "hako")]
    xs = [2.85, 1.9, 0.98, 0.0, -0.92, -1.88, -2.88]   # カメラは +Y から見るので、+X が絵の左
    for (name, fn, _), x in zip(row, xs):
        emp, _top = group(name, fn)
        emp.location = V(x, 0, 0)
        emp.rotation_euler = (0, 0, math.radians(A.turn))
    bg = backdrop(40.0)
    bg.scale = (1.0, 1.0, 1.0)
    area("key", (-5.5, 4.5, 4.8), 5.0, 1500)
    area("fill", (5.5, 5.5, 2.2), 7.0, 200, "E8EEF8")
    area("rim", (1.0, -4.0, 4.5), 6.0, 700)
    render_setup(A.size)
    cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    cam.data.lens = 80
    scene().camera = cam
    tgt = V(0.0, 0, 0.6)
    a = math.radians(12)
    dist = 15.0
    aim_cam(cam, tgt + V(math.sin(a) * dist, math.cos(a) * dist, 1.2), tgt)
    bg.rotation_euler = (0, 0, -a)
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    scene().render.filepath = os.path.join(OUT, "00-lineup%s.png" % ("" if not A.turn else "-turn%d" % A.turn))
    bpy.ops.render.render(write_still=True)
    print("wrote", scene().render.filepath)


if A.lineup:
    lineup()
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    top = BUILDERS[A.doll]()
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    shoot_single(A.doll, top)
