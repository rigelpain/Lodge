"""ロッジの素材（段階 3）。すべてノードとコードで作り、外の画像は使わない。

手芸の世界（design/art-concept.md）: 雪は毛糸の編み地、壁の丸太は巻いたフェルト、石はフェルトの小石、
屋根は藍のフェルト、木部は木目のある木、灯りは紙。役割の名前（log, roof ...）ごとに 1 つ作る。
色は sRGB の 16 進で書き、ここで線形に直す。
"""
import math

import bpy

# 色: 代表の図面の色をそのまま使う（丸太 #8B5E3C、柱 #6F4628、板 #C8A26C、屋根 #2F3B79、石 #CDC5B8）
HEX = {
    "log": "7E5535", "log_cap": "A97F4F", "post": "6F4628", "frame": "EDE1C9", "board": "C8A26C",
    "door": "6E4A30", "deck": "B99465", "rail": "A97F4F", "stone": "CDC5B8", "roof": "283268",
    "snow": "F6F7FA", "glass": "B9CBE3", "metal": "3A2A1E", "dark": "1A1410", "tatami": "D9D2A8",
    "cushion": "C98A67", "quilt": "B45A4A", "paper": "F5D6A0", "felt_red": "B45A4A",
    "felt_blue": "4C6FA8", "felt_green": "7C9A5C", "felt_yellow": "D7A24A", "tree": "3E5C48",
    "trunk": "5C3B23", "fire": "FF8A3A", "far": "A9BCD6", "floor": "9A714A", "ceiling": "C8A26C",
}


def lin(h):
    """sRGB の 16 進を線形の RGBA に"""
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


# ---------------------------------------------------------------- 編み目の画像（雪）
def knit_image(size=256, cols=8):
    """メリヤス編みの V 字。左右に傾いた楕円の糸を 1 目ずつ描く（look.gd の knit_texture と同じ考え）"""
    if "knit" in bpy.data.images:
        return bpy.data.images["knit"]
    import random
    rnd = random.Random(3)
    px = [0.62] * (size * size)
    w = size / cols
    for j in range(cols * 2):
        for i in range(cols):
            cx, cy = i * w + w / 2, j * w / 2 + w / 4
            shade = rnd.uniform(0.80, 0.95)
            for k, ang in ((-1, 0.55), (1, -0.55)):
                ox = k * w * 0.17
                ry, rx = int(w * 0.30), int(w * 0.15)
                for yy in range(-ry, ry + 1):
                    for xx in range(-rx, rx + 1):
                        fx, fy = xx / rx, yy / ry
                        e = fx * fx + fy * fy
                        if e > 1:
                            continue
                        x = xx * math.cos(ang) - yy * math.sin(ang)
                        y = xx * math.sin(ang) + yy * math.cos(ang)
                        p = (int(cy + y) % size) * size + int(cx + ox + x) % size
                        px[p] = max(px[p], shade * (0.72 + 0.28 * (1 - e)))
    img = bpy.data.images.new("knit", size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    flat = []
    for v in px:
        flat += (v, v, v, 1.0)
    img.pixels = flat
    img.pack()
    return img


# ---------------------------------------------------------------- ノードの小道具
class N:
    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        self.t = self.m.node_tree
        self.t.nodes.clear()
        self.out = self.node("ShaderNodeOutputMaterial", (900, 0))
        self.bsdf = self.node("ShaderNodeBsdfPrincipled", (600, 0))
        self.link(self.bsdf, 0, self.out, "Surface")

    def node(self, kind, loc=(0, 0), **kw):
        n = self.t.nodes.new(kind)
        n.location = loc
        for k, v in kw.items():
            if k in n.inputs:
                n.inputs[k].default_value = v
            else:
                setattr(n, k, v)
        return n

    def link(self, a, ao, b, bi):
        self.t.links.new(a.outputs[ao], b.inputs[bi])

    def set(self, name, v):
        if name in self.bsdf.inputs:
            self.bsdf.inputs[name].default_value = v

    def coords(self, scale=(1, 1, 1), kind="Object"):
        tc = self.node("ShaderNodeTexCoord", (-900, 0))
        mp = self.node("ShaderNodeMapping", (-700, 0))
        mp.inputs["Scale"].default_value = scale
        self.link(tc, kind, mp, "Vector")
        return mp

    def mix(self, fac_src, fac_out, a, b, loc=(200, 0)):
        """色 a と b を fac で混ぜる"""
        m = self.node("ShaderNodeMix", loc)
        m.data_type = "RGBA"
        self.link(fac_src, fac_out, m, "Factor")
        m.inputs[6].default_value = a
        m.inputs[7].default_value = b
        return m


def fiber_bump(n, co, strength=0.35, scale=90.0):
    """羊毛の繊維: 細胞状のノイズと細かい毛羽を重ねた凹凸"""
    vo = n.node("ShaderNodeTexVoronoi", (-450, -300), Scale=scale)
    vo.feature = "F1"
    no = n.node("ShaderNodeTexNoise", (-450, -500), Scale=scale * 2.5, Detail=6.0, Roughness=0.7)
    n.link(co, 0, vo, "Vector")
    n.link(co, 0, no, "Vector")
    ad = n.node("ShaderNodeMath", (-250, -400), operation="MULTIPLY_ADD")
    n.link(vo, "Distance", ad, 0)
    ad.inputs[1].default_value = 0.6
    n.link(no, "Fac", ad, 2)
    bp = n.node("ShaderNodeBump", (300, -350), Strength=strength, Distance=0.003)
    n.link(ad, 0, bp, "Height")
    return bp


def felt(name, hexcol, var=0.10, sheen=0.7, strength=0.35, scale=90.0):
    """フェルト: つや消し、繊維の凹凸、毛羽が縁で光る（シーン）、大きな色むら"""
    n = N(name)
    co = n.coords()
    base = lin(hexcol)
    dark = tuple(c * (1 - var) for c in base[:3]) + (1,)
    lite = tuple(min(1, c * (1 + var)) for c in base[:3]) + (1,)
    big = n.node("ShaderNodeTexNoise", (-450, 200), Scale=1.6, Detail=3.0)
    n.link(co, 0, big, "Vector")
    col = n.mix(big, "Fac", dark, lite)
    n.link(col, 2, n.bsdf, "Base Color")
    n.link(fiber_bump(n, co, strength, scale), 0, n.bsdf, "Normal")
    n.set("Roughness", 1.0)
    n.set("Sheen Weight", sheen)
    n.set("Sheen Roughness", 0.35)
    n.set("Sheen Tint", (1, 1, 1, 1))
    n.set("Specular IOR Level", 0.15)
    return n


def log_felt():
    """丸太＝巻いたフェルトのロール。胴はフェルト、木口（UV の u > 1.5）に渦巻きの層"""
    n = felt("log", HEX["log"], var=0.12)
    uv = n.node("ShaderNodeTexCoord", (-900, 400))
    sep = n.node("ShaderNodeSeparateXYZ", (-700, 400))
    n.link(uv, "UV", sep, "Vector")
    # 木口の中心からの距離と角度
    dx = n.node("ShaderNodeMath", (-500, 500), operation="SUBTRACT")
    n.link(sep, "X", dx, 0)
    dx.inputs[1].default_value = 2.5
    dy = n.node("ShaderNodeMath", (-500, 350), operation="SUBTRACT")
    n.link(sep, "Y", dy, 0)
    dy.inputs[1].default_value = 0.5
    r = n.node("ShaderNodeVectorMath", (-300, 450), operation="LENGTH")
    cmb = n.node("ShaderNodeCombineXYZ", (-400, 450))
    n.link(dx, 0, cmb, "X")
    n.link(dy, 0, cmb, "Y")
    n.link(cmb, 0, r, 0)
    ang = n.node("ShaderNodeMath", (-300, 300), operation="ARCTAN2")
    n.link(dy, 0, ang, 0)
    n.link(dx, 0, ang, 1)
    # 渦: fract(r * 層の数 - 角度 / 2π)。層の境に暗い線
    a2 = n.node("ShaderNodeMath", (-100, 300), operation="DIVIDE")
    n.link(ang, 0, a2, 0)
    a2.inputs[1].default_value = 2 * math.pi
    rr = n.node("ShaderNodeMath", (-100, 450), operation="MULTIPLY")
    n.link(r, "Value", rr, 0)
    rr.inputs[1].default_value = 11.0
    sp = n.node("ShaderNodeMath", (80, 400), operation="SUBTRACT")
    n.link(rr, 0, sp, 0)
    n.link(a2, 0, sp, 1)
    fr = n.node("ShaderNodeMath", (240, 400), operation="FRACT")
    n.link(sp, 0, fr, 0)
    ramp = n.node("ShaderNodeValToRGB", (380, 400))
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, lin("5C3B23")
    e[1].position, e[1].color = 0.12, lin(HEX["log_cap"])
    e.new(0.85).color = lin("C49A66")
    iscap = n.node("ShaderNodeMath", (240, 600), operation="GREATER_THAN")
    n.link(sep, "X", iscap, 0)
    iscap.inputs[1].default_value = 1.5
    body = n.bsdf.inputs["Base Color"].links[0].from_node
    mx = n.node("ShaderNodeMix", (500, 250))
    mx.data_type = "RGBA"
    n.link(iscap, 0, mx, "Factor")
    n.link(body, 2, mx, 6)
    n.link(ramp, 0, mx, 7)
    n.link(mx, 2, n.bsdf, "Base Color")
    return n


def wood(name, hexcol, along="Z", scale=6.0, planks=False):
    """木目: 縞を雑音でゆがめる。along は縞の向き（Z は横向きの筋＝板、X は縦の筋＝柱）。
    planks は床板: 幅 0.15 m、長さ 1.8 m の板を千鳥に張り、継ぎ目を暗く凹ませる"""
    n = N(name)
    co = n.coords()
    wv = n.node("ShaderNodeTexWave", (-450, 150), Scale=scale, Distortion=1.6, Detail=2.0, **{"Detail Scale": 2.0})
    wv.wave_type = "BANDS"
    wv.bands_direction = along
    n.link(co, 0, wv, "Vector")
    base = lin(hexcol)
    dark = tuple(c * 0.86 for c in base[:3]) + (1,)
    col = n.mix(wv, "Fac", dark, base)
    n.link(col, 2, n.bsdf, "Base Color")
    bp = n.node("ShaderNodeBump", (300, -300), Strength=0.12, Distance=0.002)
    n.link(wv, "Fac", bp, "Height")
    if planks:
        br = n.node("ShaderNodeTexBrick", (-450, -250), Scale=1.0, **{"Mortar Size": 0.006, "Mortar Smooth": 0.3,
                    "Brick Width": 1.8, "Row Height": 0.15, "Bias": 0.0})
        br.offset = 0.5
        n.link(co, 0, br, "Vector")
        br.inputs["Color1"].default_value = (1, 1, 1, 1)
        br.inputs["Color2"].default_value = (0.86, 0.86, 0.86, 1)
        br.inputs["Mortar"].default_value = (0.0, 0.0, 0.0, 1)
        ml = n.node("ShaderNodeMix", (420, 120))
        ml.data_type = "RGBA"
        ml.blend_type = "MULTIPLY"
        ml.inputs["Factor"].default_value = 0.55
        n.link(col, 2, ml, 6)
        n.link(br, "Color", ml, 7)
        n.link(ml, 2, n.bsdf, "Base Color")
        b2 = n.node("ShaderNodeBump", (450, -300), Strength=0.5, Distance=0.004)
        n.link(br, "Fac", b2, "Height")
        n.link(bp, 0, b2, "Normal")
        bp = b2
    n.link(bp, 0, n.bsdf, "Normal")
    n.set("Roughness", 0.72)
    n.set("Specular IOR Level", 0.3)
    n.set("Sheen Weight", 0.2)
    return n


def stone():
    """フェルトの小石: 石ごとに色むら、目地は暗く凹む"""
    n = N("stone")
    co = n.coords()
    vc = n.node("ShaderNodeTexVoronoi", (-450, 200), Scale=4.0)
    ve = n.node("ShaderNodeTexVoronoi", (-450, -100), Scale=4.0)
    ve.feature = "DISTANCE_TO_EDGE"
    n.link(co, 0, vc, "Vector")
    n.link(co, 0, ve, "Vector")
    base = lin(HEX["stone"])
    ramp = n.node("ShaderNodeValToRGB", (-200, 250))
    e = ramp.color_ramp.elements
    e[0].color = tuple(c * 0.78 for c in base[:3]) + (1,)
    e[1].color = tuple(min(1, c * 1.08) for c in base[:3]) + (1,)
    sepc = n.node("ShaderNodeSeparateColor", (-300, 250))
    n.link(vc, "Color", sepc, 0)
    n.link(sepc, 0, ramp, 0)
    mr = n.node("ShaderNodeMapRange", (-200, -100), **{"From Min": 0.0, "From Max": 0.07})
    n.link(ve, "Distance", mr, 0)
    joint = n.mix(mr, 0, lin("6E665C"), (0, 0, 0, 1), loc=(150, 150))
    n.link(ramp, 0, joint, 7)
    n.link(joint, 2, n.bsdf, "Base Color")
    fb = fiber_bump(n, co, 0.25)
    bp = n.node("ShaderNodeBump", (400, -200), Strength=0.6, Distance=0.04)
    n.link(mr, 0, bp, "Height")
    n.link(fb, 0, bp, "Normal")
    n.link(bp, 0, n.bsdf, "Normal")
    n.set("Roughness", 1.0)
    n.set("Sheen Weight", 0.5)
    n.set("Sheen Tint", (1, 1, 1, 1))
    return n


def snow(scale=0.8):
    """毛糸の雪: 編み目の V を箱投影で貼り、繊維の凹凸と強い毛羽の光"""
    n = N("snow")
    co = n.coords(scale=(scale * 1.0, scale * 1.0, scale * 1.0))
    img = n.node("ShaderNodeTexImage", (-450, 150))
    img.image = knit_image()
    img.projection = "BOX"
    img.projection_blend = 0.3
    n.link(co, 0, img, "Vector")
    base = lin(HEX["snow"])
    col = n.mix(img, "Color", tuple(c * 0.70 for c in base[:3]) + (1,), base)
    n.link(col, 2, n.bsdf, "Base Color")
    fb = fiber_bump(n, co, 0.30, scale=60.0)
    drift = n.node("ShaderNodeTexNoise", (-450, -700), Scale=0.25, Detail=2.0)   # 毛布のたるみ（数 m の起伏）
    n.link(co, 0, drift, "Vector")
    bd = n.node("ShaderNodeBump", (300, -600), Strength=0.35, Distance=0.6)
    n.link(drift, "Fac", bd, "Height")
    n.link(fb, 0, bd, "Normal")
    bp = n.node("ShaderNodeBump", (450, -200), Strength=0.55, Distance=0.02)
    n.link(img, "Color", bp, "Height")
    n.link(bd, 0, bp, "Normal")
    n.link(bp, 0, n.bsdf, "Normal")
    n.set("Roughness", 1.0)
    n.set("Sheen Weight", 1.0)
    n.set("Sheen Roughness", 0.3)
    n.set("Sheen Tint", (1, 1, 1, 1))
    n.set("Subsurface Weight", 0.15)
    n.set("Subsurface Radius", (0.6, 0.7, 1.0))
    n.set("Subsurface Scale", 0.05)
    return n


def glass():
    n = N("glass")
    n.set("Base Color", lin("1F2A36"))
    n.set("Roughness", 0.04)
    n.set("Alpha", 0.32)
    n.set("Specular IOR Level", 0.8)
    try:
        n.m.surface_render_method = "BLENDED"
    except (AttributeError, TypeError):
        pass
    return n


def emissive(name, hexcol, strength):
    """紙の灯り・炉の火。光る色"""
    n = felt(name, hexcol, var=0.05, sheen=0.2, strength=0.15) if name == "paper" else N(name)
    n.set("Base Color", lin(hexcol))
    n.set("Emission Color", lin(hexcol))
    n.set("Emission Strength", strength)
    return n


def quilt():
    """こたつ布団: フェルトの端切れをはぎ合わせたパッチワーク"""
    n = felt("quilt", HEX["quilt"], var=0.05)
    co = n.t.nodes["Mapping"]
    vo = n.node("ShaderNodeTexVoronoi", (-450, 500), Scale=5.0, Randomness=0.0)   # 揃った四角の端切れ
    vo.distance = "CHEBYCHEV"
    n.link(co, 0, vo, "Vector")
    sep = n.node("ShaderNodeSeparateColor", (-250, 500))
    n.link(vo, "Color", sep, 0)
    ramp = n.node("ShaderNodeValToRGB", (-50, 500))
    ramp.color_ramp.interpolation = "CONSTANT"
    e = ramp.color_ramp.elements
    e[0].color = lin("9E5E52")      # 褪せた赤・山吹・藍・生成り
    e[1].position = 0.75
    e[1].color = lin("C2A262")
    e.new(0.25).color = lin("5F7494")
    e.new(0.5).color = lin("E2D7C2")
    n.link(sep, 0, ramp, 0)
    n.link(ramp, 0, n.bsdf, "Base Color")
    return n


def tatami():
    """畳: い草の細かい縞（短い方向に並ぶ）"""
    n = N("tatami")
    co = n.coords()
    wv = n.node("ShaderNodeTexWave", (-450, 150), Scale=140.0, Distortion=0.3)
    wv.wave_type = "BANDS"
    wv.bands_direction = "Y"
    n.link(co, 0, wv, "Vector")
    base = lin(HEX["tatami"])
    col = n.mix(wv, "Fac", tuple(c * 0.86 for c in base[:3]) + (1,), base)
    n.link(col, 2, n.bsdf, "Base Color")
    bp = n.node("ShaderNodeBump", (300, -300), Strength=0.2, Distance=0.002)
    n.link(wv, "Fac", bp, "Height")
    n.link(bp, 0, n.bsdf, "Normal")
    n.set("Roughness", 0.8)
    n.set("Specular IOR Level", 0.2)
    n.set("Sheen Weight", 0.3)
    return n


def make(role, look):
    """役割の名前から素材を作る"""
    if role == "log":
        n = log_felt()
    elif role in ("post", "door"):
        n = wood(role, HEX[role], along="X", scale=3.0)
    elif role in ("board", "rail", "frame"):
        n = wood(role, HEX[role], along="Z", scale=12.0)
    elif role in ("deck", "floor", "ceiling"):
        n = wood(role, HEX[role], along="X", scale=12.0, planks=True)
    elif role == "stone":
        n = stone()
    elif role == "snow":
        n = snow()
    elif role == "glass":
        n = glass()
    elif role == "paper":
        n = emissive("paper", HEX["paper"], 4.0 if look == "dusk" else 2.0)
    elif role == "fire":
        n = emissive("fire", HEX["fire"], 25.0)
    elif role == "quilt":
        n = quilt()
    elif role == "tatami":
        n = tatami()
    elif role == "metal":
        n = N("metal")
        n.set("Base Color", lin(HEX["metal"]))
        n.set("Metallic", 0.7)
        n.set("Roughness", 0.45)
    elif role == "dark":
        n = N("dark")
        n.set("Base Color", lin(HEX["dark"]))
        n.set("Roughness", 1.0)
    elif role == "roof":
        n = felt("roof", HEX["roof"], var=0.08, sheen=0.35)
    elif role == "far":
        n = felt("far", HEX["far"], var=0.04, sheen=0.6, strength=0.1, scale=20.0)
    else:
        n = felt(role, HEX[role])
    n.m.name = role
    return n.m


def world(look):
    """空: 地平線は白、上は青白〜薄い藍。夕方は藍が濃く、地平線が橙"""
    w = bpy.data.worlds.new("sky")
    w.use_nodes = True
    t = w.node_tree
    t.nodes.clear()
    out = t.nodes.new("ShaderNodeOutputWorld")
    bg = t.nodes.new("ShaderNodeBackground")
    tc = t.nodes.new("ShaderNodeTexCoord")
    sep = t.nodes.new("ShaderNodeSeparateXYZ")
    ramp = t.nodes.new("ShaderNodeValToRGB")
    t.links.new(tc.outputs["Generated"], sep.inputs[0])
    t.links.new(sep.outputs["Z"], ramp.inputs[0])
    t.links.new(ramp.outputs[0], bg.inputs["Color"])
    t.links.new(bg.outputs[0], out.inputs["Surface"])
    e = ramp.color_ramp.elements   # 位置は見る向きの高さ（0 = 地平線、1 = 真上）
    if look == "dusk":
        e[0].position, e[0].color = 0.0, lin("F0A878")
        e[1].position, e[1].color = 0.60, lin("1A2050")
        e.new(0.07).color = lin("A890B0")
        e.new(0.25).color = lin("3A4475")
        bg.inputs["Strength"].default_value = 0.6
    else:
        e[0].position, e[0].color = 0.0, lin("DCE4EE")
        e[1].position, e[1].color = 0.55, lin("5A82C6")
        e.new(0.12).color = lin("A9C0E2")
        bg.inputs["Strength"].default_value = 0.9
    return w
