"""外の小物（ソリ・木・雪）の共通部品。Blender 5.2 を画面なしで動かす台本から読む。

素材のノードは lodge/materials.py をそのまま使い（読むだけ）、足りない麻ひも・糸・綿をここで足す。
向き: 前は +Y（Blender）。glTF では -Z（Godot の前）になる。単位は m。
"""
import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True   # lodge/ に __pycache__ を増やさない
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "lodge"))
import materials as LM  # noqa: E402

# 色（sRGB の 16 進）。ロッジの HEX にないものだけ
HEX = {
    "felt_red": "D2553A", "felt_red_dark": "9E3B2A", "felt_navy": "34477E", "felt_yellow": "D8A43E",
    "wood": "B98A58", "wood_bent": "B07E4C", "wood_dark": "7A5232", "hemp": "C9AC78", "thread": "EFE6D2", "thread_red": "B8402E", "thread_green": "5E8A4E", "thread_gold": "D9A53C",
    "button": "8F6440", "yarn_yellow": "D9A23A", "felt_horn": "D8D2C4", "felt_horn_in": "4A4640",
    "felt_navy2": "2F3B79", "felt_cream": "F1E8D6", "pole": "A87A4C",
    "felt_gold": "D2A04A", "felt_heat": "E8823A", "felt_brown": "7A4E34", "felt_beige": "D9C4A0", "felt_green": "7C9A5C",
    "yarn_red": "B8402E", "felt_flame_r": "E0482A", "felt_flame_o": "F08A2C", "felt_flame_y": "F7C84A",
    "felt_brick": "A4573C", "felt_charcoal": "3A3836", "paper_white": "F4F0E6", "paper_kraft": "C9A87A", "felt_bun": "F4EEE2",
    "felt_tin": "A8A8A4", "yarn_noodle": "EED07E", "yarn_soba": "6E5A48", "felt_broth": "C8813A", "felt_broth_miso": "D49A55",
    "felt_broth_shio": "E6D5A6", "felt_pink": "E59AA8", "felt_nori": "2C3A2E", "felt_rice": "FAF6EC",
    "felt_orange": "E58A2E", "felt_curry": "A8642A", "felt_konnyaku": "8C8780", "felt_daikon": "E3CDA0",
    "felt_tea": "8BA35A", "felt_purple": "7A3E5C", "felt_tan": "C8925A", "yarn_cream": "EFE6D2", "wood_light": "D2B07E", "knit_drum": "8E8A84", "snow": "F6F7FA", "cotton": "FBFAF6", "trunk": "6B4A30",
    "brass": "C99A3E", "pearl": "EEEAE2", "lacquer": "141012", "shell": "D8E4E6", "steel": "A9ADB2",
    "felt_stone": "726A60", "felt_stone2": "66727A", "thread_dark": "5E5850", "tree_a": "3E6B4F", "tree_b": "4F7A45", "tree_c": "2F5A55", "tree_d": "6E8A4A",
}


def parse(extra=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--views", default="quarter")
    ap.add_argument("--prefix", default="/tmp/prop")
    ap.add_argument("--size", default="1200x800")
    ap.add_argument("--look", default="day", choices=("day", "flat"))
    ap.add_argument("--export", default="", help="この場所に glb を書き出す（描画しない）")
    ap.add_argument("--blend", default="")
    for a, kw in (extra or []):
        ap.add_argument(a, **kw)
    return ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def coll(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


# ---------------------------------------------------------------- 素材
LOOK = {"v": "day"}
FIBER = {"k": 1.0}   # フェルトの繊維と毛羽の細かさの倍率。手に持つ小物は細かく（4 倍など）
_MAT = {}


def hemp(name="hemp", hexcol=None, plies=2):
    """麻ひも・毛糸: 撚りの斜めの溝と、ちくちくした毛羽。UV は u が長さ（周の長さで割る）、v が周"""
    n = LM.N(name)
    tc = n.node("ShaderNodeTexCoord", (-900, 300))
    sep = n.node("ShaderNodeSeparateXYZ", (-700, 300))
    n.link(tc, "UV", sep, "Vector")
    add = n.node("ShaderNodeMath", (-500, 300), operation="ADD")
    n.link(sep, "X", add, 0)
    n.link(sep, "Y", add, 1)
    mul = n.node("ShaderNodeMath", (-350, 300), operation="MULTIPLY")
    n.link(add, 0, mul, 0)
    mul.inputs[1].default_value = 2 * math.pi * plies   # 撚りの本数
    sn = n.node("ShaderNodeMath", (-200, 300), operation="SINE")
    n.link(mul, 0, sn, 0)
    ab = n.node("ShaderNodeMath", (-50, 300), operation="ABSOLUTE")
    n.link(sn, 0, ab, 0)
    pw = n.node("ShaderNodeMath", (100, 300), operation="POWER")
    n.link(ab, 0, pw, 0)
    pw.inputs[1].default_value = 0.5
    base = LM.lin(hexcol or HEX["hemp"])
    col = n.mix(pw, 0, tuple(c * 0.55 for c in base[:3]) + (1,), base, loc=(300, 300))
    n.link(col, 2, n.bsdf, "Base Color")
    co = n.coords()
    fb = LM.fiber_bump(n, co, 0.35, scale=160.0)
    bp = n.node("ShaderNodeBump", (450, -150), Strength=0.8, Distance=0.004)
    n.link(pw, 0, bp, "Height")
    n.link(fb, 0, bp, "Normal")
    n.link(bp, 0, n.bsdf, "Normal")
    n.set("Roughness", 0.95)
    n.set("Sheen Weight", 0.6)
    n.set("Sheen Tint", (1, 1, 1, 1))
    return n


def bent_wood(name, hexcol):
    """曲げ木: 木目を管の長さの向き（UV の u）に流す。tube() の UV を使う"""
    n = LM.N(name)
    co = n.coords(scale=(1.0, 1.0, 1.0), kind="UV")
    wv = n.node("ShaderNodeTexWave", (-450, 150), Scale=3.0, Distortion=2.5, Detail=2.0, **{"Detail Scale": 1.5})
    wv.wave_type = "BANDS"
    wv.bands_direction = "Y"
    n.link(co, 0, wv, "Vector")
    base = LM.lin(hexcol)
    col = n.mix(wv, "Fac", tuple(c * 0.62 for c in base[:3]) + (1,), base)
    n.link(col, 2, n.bsdf, "Base Color")
    bp = n.node("ShaderNodeBump", (300, -300), Strength=0.15, Distance=0.002)
    n.link(wv, "Fac", bp, "Height")
    n.link(bp, 0, n.bsdf, "Normal")
    n.set("Roughness", 0.6)
    n.set("Specular IOR Level", 0.35)
    n.set("Sheen Weight", 0.15)
    return n


def cotton(name="cotton", hexcol=None):
    """綿: 白く、つやがなく、光が中まで回る。縁が強く光ってにじむ"""
    n = LM.felt(name, hexcol or HEX["cotton"], var=0.04, sheen=1.0, strength=0.6, scale=14.0)
    n.set("Sheen Roughness", 0.5)
    n.set("Subsurface Weight", 0.35)
    n.set("Subsurface Radius", (0.8, 0.85, 1.0))
    n.set("Subsurface Scale", 0.08)
    return n


_FUZZ = {}


def fuzz_mat(k, layers, hexcol, sheen=1.0):
    """毛羽の層の素材: 細かい雑音で穴をあけ、外の層ほど毛がまばら（シェルテクスチャリング）。同じものは使い回す"""
    key = (k, layers, hexcol, sheen, FIBER["k"])
    if key not in _FUZZ:
        _FUZZ[key] = _fuzz_mat(k, layers, hexcol, sheen)
    return _FUZZ[key]


def _fuzz_mat(k, layers, hexcol, sheen):
    n = LM.N("fuzz_%d" % k)
    co = n.coords(scale=(1, 1, 1))
    no = n.node("ShaderNodeTexVoronoi", (-450, 0), Scale=260.0 * FIBER["k"], Randomness=1.0)
    n.link(co, 0, no, "Vector")
    h = (k + 1) / (layers + 1)
    ramp = n.node("ShaderNodeValToRGB", (-200, 0))
    ramp.color_ramp.interpolation = "CONSTANT"
    e = ramp.color_ramp.elements
    e[0].color = (1, 1, 1, 1)
    e[1].position = 0.15 + 0.35 * (1 - h)   # 外の層ほど、毛の芯の近くだけ残す
    e[1].color = (0, 0, 0, 1)
    n.link(no, "Distance", ramp, 0)
    n.link(ramp, 0, n.bsdf, "Alpha")
    base = LM.lin(hexcol)
    n.set("Base Color", tuple(c * (0.9 + 0.1 * h) for c in base[:3]) + (1,))
    n.set("Roughness", 1.0)
    n.set("Sheen Weight", sheen)
    n.set("Subsurface Weight", 0.3)
    try:
        n.m.surface_render_method = "DITHERED"
    except (AttributeError, TypeError):
        pass
    return n.m


NOFUZZ = {"v": False}   # 書き出し（焼き込み）のときは毛羽の層を作らない


def fuzz(obj, length, layers=4, hexcol=None, sheen=1.0):
    """描くときだけ: 綿やフェルトの輪郭の毛羽。同じ形を法線の向きに少しずつ膨らませて重ねる"""
    if NOFUZZ["v"]:
        return
    for k in range(layers):
        o = obj.copy()
        o.modifiers.clear()
        for md in obj.modifiers:
            if md.type == "SUBSURF":
                s = o.modifiers.new("soft", "SUBSURF")
                s.levels = s.render_levels = md.levels
        d = o.modifiers.new("shell", "DISPLACE")
        d.strength = length * (k + 1) / layers
        d.mid_level = 0.0
        o.material_slots[0].link = "OBJECT"
        o.material_slots[0].material = fuzz_mat(k, layers, hexcol or HEX["cotton"], sheen)
        o.name = obj.name + "_fuzz%d" % k
        coll("stage").objects.link(o)


# パッチワークの端切れの色（役割 patch_* ごと）。色を変えて、柄違いの布を何枚でも作れる
PATCH = {
    "patch_warm": ["A8532E", "C99A3A", "EEE6D4", "B5636A", "2E3F66", "C8925A"],
    "patch_cool": ["2E3F66", "8FAFC8", "EEE6D4", "6E7F4A", "C99A3A", "D9C4A0"],
    "patch_mix": ["B45A4A", "C2A262", "5F7494", "E2D7C2", "6E7F4A", "B5636A", "D58A4A"],
    "patch_rose": ["B5636A", "E59AA8", "F4EEE2", "C99A3A", "8FAFC8", "A8532E"],
}


def patchwork(role, cols, size=0.11):
    """パッチワーク: 四角い端切れを縫い合わせた布。端切れごとに無地・縞・水玉・ギンガムの柄と色を変え、
    半分は対角に三角 2 枚をはぐ。縫い目は少しへこみ、端切れの縁の内側になみ縫い。端切れはふっくら。
    座標は布に貼った UV（cloth、m 単位。M.done が箱の向きで投影する。垂らす布は平らな形のときの位置）"""
    n = LM.felt(role, "FFFFFF", var=0.07, sheen=0.5, strength=0.45, scale=60.0 * FIBER["k"])
    T = n.t
    felt_col = n.bsdf.inputs["Base Color"].links[0].from_socket
    felt_nrm = n.bsdf.inputs["Normal"].links[0].from_socket

    def nd(kind, **kw):
        x = T.nodes.new(kind)
        for k, v in kw.items():
            setattr(x, k, v)
        return x

    def put(sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            T.links.new(v, sock)
        elif isinstance(v, tuple) and hasattr(v[0], "outputs"):
            T.links.new(v[0].outputs[v[1]], sock)
        else:
            sock.default_value = v

    def op(name, a, b=0.0):
        x = nd("ShaderNodeMath", operation=name)
        put(x.inputs[0], a)
        put(x.inputs[1], b)
        return (x, 0)

    def vop(name, a, b=None, scale=None):
        x = nd("ShaderNodeVectorMath", operation=name)
        put(x.inputs[0], a)
        if b is not None:
            put(x.inputs[1], b)
        if scale is not None:
            x.inputs["Scale"].default_value = scale
        return (x, 0)

    def ramp(fac, hexes):
        x = nd("ShaderNodeValToRGB")
        x.color_ramp.interpolation = "CONSTANT"
        e = x.color_ramp.elements
        e[0].color = LM.lin(hexes[0])
        e[1].position = 1.0 / len(hexes)
        e[1].color = LM.lin(hexes[1])
        for k in range(2, len(hexes)):
            e.new(k / len(hexes)).color = LM.lin(hexes[k])
        put(x.inputs[0], fac)
        return (x, 0)

    def mix(fac, a, b, blend="MIX"):
        x = nd("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        put(x.inputs[0], fac)
        put(x.inputs[6], a)
        put(x.inputs[7], b)
        return (x, 2)

    uv = nd("ShaderNodeUVMap", uv_map="cloth")
    p = vop("SCALE", (uv, 0), scale=1.0 / size)
    cell = vop("FLOOR", p)
    f = vop("FRACTION", p)
    sep = nd("ShaderNodeSeparateXYZ")
    put(sep.inputs[0], f)
    fx, fy = (sep, 0), (sep, 1)
    wn = nd("ShaderNodeTexWhiteNoise", noise_dimensions="3D")
    put(wn.inputs["Vector"], cell)
    rc = nd("ShaderNodeSeparateColor")
    put(rc.inputs[0], (wn, "Color"))
    r1, r2, r3, r4 = (wn, "Value"), (rc, 0), (rc, 1), (rc, 2)
    # 対角にはぐ端切れ: 三角の片方は別の色
    split = op("GREATER_THAN", r3, 0.62)
    side = op("MULTIPLY", split, op("GREATER_THAN", fx, fy))
    idx = op("FRACT", op("ADD", r1, op("MULTIPLY", side, 0.43)))
    base = ramp(idx, cols)
    accent = mix(0.35, ramp(op("FRACT", op("ADD", idx, 0.5)), cols), LM.lin("F4EEE2"))
    # 柄: 縞（向きは端切れごと）、水玉、ギンガム
    across = op("LESS_THAN", r4, 0.5)
    sc = op("ADD", op("MULTIPLY", fx, across), op("MULTIPLY", fy, op("SUBTRACT", 1.0, across)))
    stripes = op("LESS_THAN", op("FRACT", op("MULTIPLY", sc, 6.0)), 0.34)
    dot_d = vop("DISTANCE", vop("FRACTION", vop("SCALE", f, scale=4.0)), (0.5, 0.5, 0.0))
    dots = op("LESS_THAN", dot_d, 0.19)
    ging = op("MULTIPLY", op("ADD", op("LESS_THAN", op("FRACT", op("MULTIPLY", fx, 4.0)), 0.5),
                                 op("LESS_THAN", op("FRACT", op("MULTIPLY", fy, 4.0)), 0.5)), 0.5)
    w_st = op("SUBTRACT", op("GREATER_THAN", r2, 0.42), op("GREATER_THAN", r2, 0.6))
    w_dot = op("SUBTRACT", op("GREATER_THAN", r2, 0.6), op("GREATER_THAN", r2, 0.8))
    w_g = op("GREATER_THAN", r2, 0.8)
    pv = op("ADD", op("ADD", op("MULTIPLY", stripes, w_st), op("MULTIPLY", dots, w_dot)), op("MULTIPLY", ging, w_g))
    col = mix(op("MULTIPLY", pv, 0.85), base, accent)
    # 縫い目: 端切れの縁（と対角）までの距離
    ex = op("MINIMUM", fx, op("SUBTRACT", 1.0, fx))
    ey = op("MINIMUM", fy, op("SUBTRACT", 1.0, fy))
    dd = op("ADD", op("MULTIPLY", op("ABSOLUTE", op("SUBTRACT", fx, fy)), 0.7071), op("SUBTRACT", 1.0, split))
    e = op("MINIMUM", op("MINIMUM", ex, ey), dd)
    seam = op("LESS_THAN", e, 0.022)
    col = mix(op("MULTIPLY", seam, 0.45), col, (0.0, 0.0, 0.0, 1.0))
    # なみ縫い: 縁の内側に、縁にそって点線
    st_x = op("MULTIPLY", op("LESS_THAN", op("ABSOLUTE", op("SUBTRACT", ex, 0.075)), 0.011),
              op("LESS_THAN", op("FRACT", op("MULTIPLY", fy, 7.0)), 0.55))
    st_y = op("MULTIPLY", op("LESS_THAN", op("ABSOLUTE", op("SUBTRACT", ey, 0.075)), 0.011),
              op("LESS_THAN", op("FRACT", op("MULTIPLY", fx, 7.0)), 0.55))
    stitch = op("MAXIMUM", op("MULTIPLY", st_x, op("GREATER_THAN", ey, 0.06)), op("MULTIPLY", st_y, op("GREATER_THAN", ex, 0.06)))
    col = mix(op("MINIMUM", stitch, 1.0), col, LM.lin("F2EAD8"))
    col = mix(1.0, col, felt_col, "MULTIPLY")
    put(n.bsdf.inputs["Base Color"], col)
    # ふくらみ: 縫い目でへこみ、端切れの真ん中がふっくら。なみ縫いは糸が少し沈む
    puff = op("MINIMUM", op("MULTIPLY", e, 7.0), 1.0)
    h = op("SUBTRACT", puff, op("MULTIPLY", op("MINIMUM", stitch, 1.0), 0.25))
    bp = nd("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.7
    bp.inputs["Distance"].default_value = 0.006
    put(bp.inputs["Height"], h)
    T.links.new(felt_nrm, bp.inputs["Normal"])
    T.links.new(bp.outputs["Normal"], n.bsdf.inputs["Normal"])
    return n


SHINES = ("brass", "pearl", "lacquer", "shell", "steel")   # 焼かない光る素材（kit.group_of・game/look.gd の shine）
LODGE_ROLES = ("quilt", "floor", "paper", "glass", "fire", "tatami", "stone")   # ロッジの素材をそのまま使う


def make_mat(role):
    hexcol = HEX.get(role) or LM.HEX.get(role)
    if role in LODGE_ROLES and LOOK["v"] == "day":
        return LM.make(role, "day")
    if LOOK["v"] == "flat":   # 書き出し用: 役割の名前と色だけ。Godot で look.gd の素材に差し替える
        m = bpy.data.materials.new(role)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = LM.lin(hexcol)
        b.inputs["Roughness"].default_value = 0.9
        return m
    if role.startswith(("felt_tree", "felt_stone")):   # 木と岩は 20 cm の作品を 30 倍にした縮尺。繊維も大きく
        n = LM.felt(role, hexcol, var=0.14, sheen=0.6, strength=0.7, scale=9.0)
        for nd in n.t.nodes:
            if nd.type == "BUMP":
                nd.inputs["Distance"].default_value *= 12
    elif role == "felt_heat" or role.startswith("felt_flame"):   # 熱をもったフェルト・炎: 光る
        n = LM.felt(role, hexcol, var=0.12, sheen=0.5, strength=0.5, scale=40.0)
        n.set("Emission Color", LM.lin(hexcol))
        n.set("Emission Strength", 0.6 if role == "felt_heat" else 0.7)
    elif role.startswith("felt") or role.startswith("tree"):
        n = LM.felt(role, hexcol, var=0.12, sheen=0.55, strength=0.5, scale=60.0 * FIBER["k"])
        if FIBER["k"] != 1.0:
            for nd in n.t.nodes:
                if nd.type == "BUMP":
                    nd.inputs["Distance"].default_value /= FIBER["k"]
    elif role in ("wood", "wood_dark", "trunk", "pole", "wood_light"):
        n = LM.wood(role, hexcol, along="X" if role == "pole" else "Z", scale=7.0)   # 柱は縦の木目
        mx = n.bsdf.inputs["Base Color"].links[0].from_node   # 木目をはっきり
        mx.inputs[6].default_value = tuple(c * 0.62 for c in LM.lin(hexcol)[:3]) + (1,)
    elif role == "wood_bent":
        n = bent_wood(role, hexcol)
    elif role in SHINES:   # 光る素材（真鍮・白蝶貝・漆・貝の小片・鋼）。書き出しでは焼かず、Godot が look.gd の shine で光らせる
        n = LM.N(role)
        n.set("Base Color", LM.lin(hexcol))
        n.set("Metallic", 1.0 if role in ("brass", "steel") else 0.0)
        n.set("Roughness", {"brass": 0.25, "steel": 0.22, "lacquer": 0.08, "pearl": 0.2, "shell": 0.12}[role])
        if role in ("pearl", "shell"):   # 真珠層: 薄膜の虹色
            n.set("Thin Film Thickness", 520.0 if role == "pearl" else 650.0)
            n.set("Thin Film IOR", 1.5)
        if role == "lacquer":
            n.set("Coat Weight", 1.0)
    elif role == "button":
        n = LM.wood(role, hexcol, along="X", scale=30.0)
    elif role == "hemp":
        n = hemp()
    elif role.startswith("yarn"):   # 毛糸: 3 本撚り
        n = hemp(role, hexcol, plies=3)
    elif role.startswith("thread"):
        n = LM.felt(role, hexcol, var=0.03, sheen=0.5, strength=0.2, scale=300.0)
    elif role.startswith("paper_"):   # 光らない紙（包み紙、紙コップ、メニューの紙）
        n = LM.felt(role, hexcol, var=0.03, sheen=0.15, strength=0.12, scale=120.0)
        n.set("Roughness", 0.8)
    elif role == "snow":
        n = LM.snow()
    elif role == "cotton":
        n = cotton()
    elif role in PATCH:
        n = patchwork(role, PATCH[role])
    else:
        n = LM.felt(role, hexcol)
    n.m.name = role
    return n.m


def mat(role):
    if role not in _MAT:
        _MAT[role] = make_mat(role)
    return _MAT[role]


# ---------------------------------------------------------------- 形
class M:
    """1 つの部品 = 1 つの bmesh = 1 つの素材"""

    def __init__(self, name, role, group="prop"):
        self.name, self.role, self.group = name, role, group
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()

    def done(self, smooth=True, subsurf=0, bevel=0.0, seg=2, parent=None):
        if self.role in PATCH and not getattr(self, "uv_set", False):
            box_uv(self, getattr(self, "uv_scale", 1.0))
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        if self.role in PATCH:
            me.uv_layers[0].name = "cloth"
        o = bpy.data.objects.new(self.name, me)
        coll(self.group).objects.link(o)
        me.materials.append(mat(self.role))
        if smooth:
            me.shade_smooth()
        if bevel:
            b = o.modifiers.new("bevel", "BEVEL")
            b.width, b.segments, b.limit_method = bevel, seg, "ANGLE"
        if subsurf:
            s = o.modifiers.new("subsurf", "SUBSURF")
            s.levels = s.render_levels = subsurf
        if parent is not None:
            o.parent = parent
        return o


def box_uv(m, k=1.0):
    """面の向きで投影した UV（m 単位の k 倍。小さな品物は k を大きくして端切れを細かく）。
    パッチワークの端切れを箱や袋の面に並べる"""
    m.bm.normal_update()
    for f in m.bm.faces:
        nx, ny, nz = (abs(c) for c in f.normal)
        for lp in f.loops:
            x, y, z = lp.vert.co * k
            lp[m.uv].uv = (x, y) if nz >= max(nx, ny) else ((x, z) if ny >= nx else (y, z))


def plan_uv(m, cx=0.0, cy=0.0):
    """平らな布の UV: 上から見た位置（m 単位）。垂らしたあとも端切れが布にそってつく"""
    for f in m.bm.faces:
        for lp in f.loops:
            lp[m.uv].uv = (lp.vert.co.x - cx, lp.vert.co.y - cy)
    m.uv_set = True


def place(m, n0, mtx):
    """n0 個目より後に足した頂点を mtx で動かす"""
    for v in new_verts(m, n0):
        v.co = mtx @ v.co


def lathe(m, prof, segs=32, closed=True):
    """回転体: prof は (半径, 高さ) の列。z 軸のまわりに回す。closed なら端を軸で閉じる"""
    rings = []
    for (r, z) in prof:
        rings.append([m.bm.verts.new((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z))
                      for i in range(segs)])
    for j in range(len(rings) - 1):
        for i in range(segs):
            i2 = (i + 1) % segs
            m.bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))
    if closed:
        for ring, z in ((rings[0], prof[0][1]), (rings[-1], prof[-1][1])):
            c = m.bm.verts.new((0, 0, z))
            for i in range(segs):
                m.bm.faces.new((ring[i], ring[(i + 1) % segs], c))
    return rings


def new_verts(m, n0):
    """n0 個目より後に足した頂点（bmesh の頂点は足した順に並ぶ）"""
    m.bm.verts.ensure_lookup_table()
    return [m.bm.verts[i] for i in range(n0, len(m.bm.verts))]


def frames(pts, side=None):
    """道筋の各点の向き（接線, 横, 上）。side を決めると横の向きを固定する（板のような断面に）"""
    out = []
    n = len(pts)
    prev_s = None
    for i in range(n):
        a, b = pts[max(0, i - 1)], pts[min(n - 1, i + 1)]
        t = (Vector(b) - Vector(a)).normalized()
        if side is not None:
            s = Vector(side) - t * t.dot(Vector(side))
        elif prev_s is None:
            ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            s = t.cross(ref)
        else:
            s = prev_s - t * t.dot(prev_s)
        s.normalize()
        prev_s = s
        out.append((t, s, t.cross(s) * -1))
    return out


def tube(m, pts, r, sides=8, side=None, caps=True, closed=False, ry=None, twist=0.0, sq=2.0):
    """道筋に沿った管。r は太さ（数か、点ごとの列）。ry を決めると上下の太さを変える（楕円の断面）。
    sq を 2 より大きくすると断面が角の丸い四角に近づく（板）"""
    fr = frames(pts, side)
    rs = r if isinstance(r, (list, tuple)) else [r] * len(pts)
    rys = ry if isinstance(ry, (list, tuple)) else [ry if ry is not None else rr for rr in rs]
    rings = []
    length = 0.0
    lens = []
    for i, p in enumerate(pts):
        if i:
            length += (Vector(p) - Vector(pts[i - 1])).length
        lens.append(length)
        t, s, u = fr[i]
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides + twist * lens[i]
            ca, sa = math.cos(a), math.sin(a)
            if sq != 2.0:
                ca, sa = math.copysign(abs(ca) ** (2 / sq), ca), math.copysign(abs(sa) ** (2 / sq), sa)
            ring.append(m.bm.verts.new(Vector(p) + s * ca * rs[i] + u * sa * rys[i]))
        rings.append(ring)
    circ = 2 * math.pi * max(rs)
    segs = range(len(pts) if closed else len(pts) - 1)
    for i in segs:
        j = (i + 1) % len(pts)
        for k in range(sides):
            k2 = (k + 1) % sides
            f = m.bm.faces.new((rings[i][k], rings[i][k2], rings[j][k2], rings[j][k]))
            u0, u1 = lens[i] / circ, (lens[j] if j else length + (Vector(pts[0]) - Vector(pts[-1])).length) / circ
            for lp, (uu, vv) in zip(f.loops, ((u0, k / sides), (u0, (k + 1) / sides), (u1, (k + 1) / sides), (u1, k / sides))):
                lp[m.uv].uv = (uu, vv)
    if caps and not closed:
        m.bm.faces.new(list(reversed(rings[0])))
        m.bm.faces.new(rings[-1])
    return rings


def superellipsoid(m, center, half, n_xy=6.0, n_z=2.6, cuts=8, mat_fn=None, dent=None):
    """ふっくらした角の丸い箱（座布団やクッション）。立方体を細かく割って、超楕円体に押しつける。
    dent=(深さ, 広さ) で上の真ん中をボタンでへこませる"""
    n0 = len(m.bm.verts)
    ret = bmesh.ops.create_cube(m.bm, size=2.0)
    es = list({e for v in ret["verts"] for e in v.link_edges})
    bmesh.ops.subdivide_edges(m.bm, edges=es, cuts=cuts, use_grid_fill=True)
    allv = new_verts(m, n0)
    ax, ay, az = half
    for v in allv:
        # 向きは「箱の寸法に引き伸ばした格子の点」から取る。とても平たい形でも頂点が縁まで行き渡る
        d = Vector((v.co.x * ax, v.co.y * ay, v.co.z * az)).normalized()
        lo, hi = 0.0, 4.0 * max(half)
        for _ in range(40):   # f(t) = 1 になる t を二分法で
            t = (lo + hi) / 2
            f = (abs(t * d.x) / ax) ** n_xy + (abs(t * d.y) / ay) ** n_xy
            f = f ** (n_z / n_xy) + (abs(t * d.z) / az) ** n_z
            lo, hi = (t, hi) if f < 1 else (lo, t)
        p = d * lo
        if dent and p.z > 0:
            dd, w = dent
            p.z -= dd * math.exp(-(p.x * p.x + p.y * p.y) / (w * w)) * (p.z / az)
        v.co = Vector(center) + p
    return allv


def ellipse_ring(a, b, n=6.0, count=64, z=0.0, inset=0.0):
    """超楕円 |x/a|^n + |y/b|^n = 1 の周を、ほぼ等間隔に count 点。外向きの法線も返す"""
    dense = []
    for i in range(2000):
        th = 2 * math.pi * i / 2000
        c, s = math.cos(th), math.sin(th)
        x = (a - inset) * math.copysign(abs(c) ** (2 / n), c)
        y = (b - inset) * math.copysign(abs(s) ** (2 / n), s)
        dense.append(Vector((x, y, z)))
    cum = [0.0]
    for i in range(1, len(dense) + 1):
        cum.append(cum[-1] + (dense[i % len(dense)] - dense[i - 1]).length)
    total = cum[-1]
    pts, nrm = [], []
    j = 0
    for k in range(count):
        target = total * k / count
        while cum[j + 1] < target:
            j += 1
        p = dense[j % len(dense)]
        q = dense[(j + 1) % len(dense)]
        t = (q - p).normalized()
        pts.append(p)
        nrm.append(Vector((t.y, -t.x, 0)).normalized())
    return pts, nrm


def seam_whip(felt_m, thread_m, pts, nrm, out=0.016, th=0.007, r=0.0065, every=1):
    """2 枚のフェルトを縫い合わせた耳（縫い代）と、それを巻きかがる糸。pts は縫い目の周（閉じた輪）"""
    ring = [p + n * out * 0.5 for p, n in zip(pts, nrm)]
    tube(felt_m, ring + [ring[0]], out, sides=8, ry=th, caps=False)
    up = Vector((0, 0, 1))
    for k in range(0, len(pts), every):
        p, n = pts[k], nrm[k]
        t = (pts[(k + 1) % len(pts)] - pts[k - 1]).normalized()
        sl = t * 0.010   # かがりの糸は斜めに渡る
        e = 1.5 * out + r * 0.6
        tube(thread_m, [p + n * 0.3 * out + up * (th + r * 0.7) + sl,
                        p + n * e * 0.9 + up * (th * 0.7 + r * 0.5) + sl * 0.5,
                        p + n * (e + r * 0.3),
                        p + n * e * 0.9 - up * (th * 0.7 + r * 0.5) - sl * 0.5,
                        p + n * 0.3 * out - up * (th + r * 0.7) - sl], r, sides=4)


def running_stitch(m, pts, nrm, dash=0.03, gap=0.02, r=0.005, lift=0.0):
    """なみ縫い: 破線の糸。pts は等間隔でなくてよい"""
    seq = list(pts)
    acc, on, cur = 0.0, True, [seq[0]]
    for i in range(1, len(seq)):
        a, b = seq[i - 1], seq[i]
        L = (b - a).length
        pos = 0.0
        while pos < L:
            need = (dash if on else gap) - acc
            if pos + need <= L:
                p = a.lerp(b, (pos + need) / L)
                if on:
                    cur.append(p)
                    tube(m, [q + nrm[0] * lift for q in cur], r, sides=4)
                cur = [p]
                on = not on
                pos += need
                acc = 0.0
            else:
                if on:
                    cur.append(b)
                acc += L - pos
                pos = L


def metablob(name, role, balls, res, parent=None, group="prop", lumps=0.10):
    """綿のかたまり: 球をメタボールで溶かし合わせ、雲の雑音で少し凸凹に。
    balls は (位置, 半径) か (位置, 半径, (大きさ x, y, z), z 軸まわりの向き)"""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = mb.render_resolution = res
    mb.threshold = 0.6
    for b in balls:
        e = mb.elements.new()
        e.co, e.radius = b[0], b[1]
        if len(b) > 2:
            e.type = "ELLIPSOID"
            e.size_x, e.size_y, e.size_z = b[2]
            if len(b) > 3:
                e.rotation = (math.cos(b[3] / 2), 0, 0, math.sin(b[3] / 2))
    ob = bpy.data.objects.new(name + "_mb", mb)
    coll(group).objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    o = bpy.data.objects.new(name, me)
    coll(group).objects.link(o)
    me.materials.append(mat(role))
    me.shade_smooth()
    if lumps:
        big = max(b[1] for b in balls)
        tex = bpy.data.textures.new(name + "_tex", "CLOUDS")
        tex.noise_scale = 0.35 * big
        tex.noise_depth = 1
        d = o.modifiers.new("lumps", "DISPLACE")
        d.texture = tex
        d.texture_coords = "OBJECT"
        d.strength = lumps * big
        d.mid_level = 0.5
    o.parent = parent
    return o


# ---------------------------------------------------------------- 場面と描画
def ground(size=60.0, hill=None):
    """雪の地面（毛糸の編み地）。描くときだけ"""
    m = M("ground", "snow", "stage")
    bmesh.ops.create_grid(m.bm, x_segments=40, y_segments=40, size=size / 2)
    if hill:
        for v in m.bm.verts:
            v.co.z = hill(v.co.x, v.co.y)
    return m.done()


def light(elev=32.0, az=-35.0):
    """太陽: 高さ elev 度、向き az 度の午後の光。空は lodge と同じ"""
    sc = bpy.context.scene
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    coll("stage").objects.link(sun)
    sun.data.angle = math.radians(2)
    sun.data.energy = 4.5
    sun.data.color = (1.0, 0.86, 0.68)
    sun.rotation_euler = (math.radians(90 - elev), 0, math.radians(az))
    sc.world = LM.world("day")


def setup_render(size):
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    rx, ry = (int(v) for v in size.split("x"))
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = -0.35
    sc.eevee.taa_render_samples = 64
    for attr, v in (("use_raytracing", True), ("use_shadows", True), ("use_gtao", True)):
        if hasattr(sc.eevee, attr):
            setattr(sc.eevee, attr, v)
    if hasattr(sc.eevee, "fast_gi_method"):
        sc.eevee.use_fast_gi = True


def render(cam_loc, target, lens, path, dof=None):
    sc = bpy.context.scene
    cam = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.location = cam_loc
    d = Vector(target) - Vector(cam_loc)
    cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, math.atan2(d.y, d.x) - math.pi / 2)
    cam.data.lens = lens
    cam.data.clip_start = 0.02
    cam.data.dof.use_dof = dof is not None
    if dof:
        cam.data.dof.focus_distance = d.length
        cam.data.dof.aperture_fstop = dof
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("wrote", path)


def export(objs, path, root=None):
    """選んだ部品を 1 つの glb に。モディファイアは当てて書き出す"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root or objs[0]
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(path), export_format="GLB", use_selection=True,
                              export_apply=True, export_lights=False, export_cameras=False, export_yup=True,
                              export_extras=True, export_image_format="JPEG", export_image_quality=88)
    print("wrote", path)


def tri_count(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for o in objs:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        n += len(me.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
    return n
