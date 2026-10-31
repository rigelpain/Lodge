"""頭・肩に載せる小物（perch）と、連れて歩くミニオン（pet）を Blender で組む。

    # 並べて 1 枚に描く（代表に見せるラフ）
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/pets/build_pets.py -- --sheet perch --out person/pets/renders/01-perch.png
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/pets/build_pets.py -- --sheet pet --out person/pets/renders/02-pet.png
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/pets/build_pets.py -- --sheet dolls --out person/pets/renders/03-dolls.png

    # ゲームへ書き出す（game/pals/ に perch_*.glb・pet_*.glb と素材の表 mats.json）
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/pets/build_pets.py -- --export game/pals

形はどれも、代表の参考ボード（&wind：Lodge キャラ）の折り紙・ペーパークラフト・フェルトの作品から取った。
ボードにないもの（毛糸玉）は、Lodge の手芸の素材から作った。
小物の原点は、頭や肩に載る底のまんなか。ミニオンの原点は足もとのまんなか。
ミニオンは 3 つの姿（walk 立って歩く・sit 座って待つ・sleep 丸まって寝る）を、それぞれ別の形として組む（コマ撮りの置き換え人形）。
動かす部品（head・tail・leg_*・wing_*）は分けて、節点の原点を回す支点にする。
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

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
bpy.ops.wm.read_factory_settings(use_empty=True)
import lib as L  # noqa: E402
from lib import V, hull, mesh, thicken, tube, paper, felt, plain, glow, ellipse_pts, link, finish, soften  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--sheet", default="perch")
ap.add_argument("--out", default="")
ap.add_argument("--export", default="", help="glb を書き出すフォルダ（game/pals）")
ap.add_argument("--samples", type=int, default=48)
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
sc = bpy.context.scene
L.sc = sc


# ================================================================ 柄
def pattern(name, kind, base, ink, ink2=None, px=512):
    """千代紙の柄（lib.pattern_image のほかに、桜・筆の墨・孔雀の羽）"""
    if kind in ("seigaiha", "shippo"):
        return L.pattern_image(name, kind, base, ink, px)
    rnd = np.random.default_rng(abs(hash(name)) % 9999)
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    b = np.array(L.lin(base)[:3])
    k = np.array(L.lin(ink)[:3])
    k2 = np.array(L.lin(ink2 or ink)[:3])
    img = np.ones((px, px, 3)) * b
    if kind == "sakura":   # 散らした五弁の花と、小さな葉
        for i in range(26):
            cx, cy = rnd.random(2)
            r = 0.035 + rnd.random() * 0.03
            dx = ((x - cx + 0.5) % 1) - 0.5
            dy = ((y - cy + 0.5) % 1) - 0.5
            a = np.arctan2(dy, dx)
            d = np.hypot(dx, dy)
            petal = d < r * (0.62 + 0.38 * np.abs(np.cos(2.5 * a + i)))
            img = np.where(petal[..., None], k if i % 3 else k2, img)
            img = np.where((d < r * 0.2)[..., None], np.array(L.lin("E8C25A")[:3]), img)
    elif kind == "sumi":   # 月の紙: 文字に見えない、墨の短い筆の線
        for i in range(70):
            cx, cy = rnd.random(2)
            ang = rnd.random() * math.pi
            ln = 0.015 + rnd.random() * 0.03
            dx = ((x - cx + 0.5) % 1) - 0.5
            dy = ((y - cy + 0.5) % 1) - 0.5
            u = dx * math.cos(ang) + dy * math.sin(ang)
            v = -dx * math.sin(ang) + dy * math.cos(ang)
            stroke = (np.abs(u) < ln) & (np.abs(v) < 0.0035 + 0.002 * (1 - np.abs(u) / ln))
            img = np.where(stroke[..., None], k, img)
    rgba = np.concatenate([img, np.ones((px, px, 1))], axis=2)[::-1]
    im = bpy.data.images.new(name, px, px)
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.pack()
    return im


def yarn(name, color):
    """毛糸: 巻いた糸の筋（lib.yarn_ball の光を弱め、ガラスのように見えないように）"""
    m = L.yarn_ball(name, color)
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Sheen Weight"].default_value = 0.25
    b.inputs["Specular IOR Level"].default_value = 0.05
    return m


## 素材の表: 名前 → [種類, 色, 柄 [柄の名前, 墨の色, 2 つめの墨の色] か None]。
## 種類は paper 紙 / felt フェルト / yarn 毛糸 / plain つやのある小物（目・真鍮・木の玉）。
## 書き出しでは名前と色だけの素材にし、この表を game/pals/mats.json に書く（Godot の pals.gd が look.gd の素材に置き換える）
MATS = {
    "chiyo_red": ["paper", "B8473A", ["seigaiha", "E8A07A", None]],
    "chiyo_orange": ["paper", "D9772E", ["shippo", "F2C27A", None]],
    "chiyo_sakura": ["paper", "B8352B", ["sakura", "F1D9C9", "5D7A4A"]],
    "moon": ["paper", "E2C27A", ["sumi", "3A2B22", None]],
    "white": ["paper", "F4F0E8", None],
    "cream": ["paper", "F2EBDD", None],
    "ink": ["plain", "1E1A18", None],
    "beak": ["paper", "D9A42C", None],
    "sky": ["paper", "86C3DE", None],
    "teal": ["paper", "2FA4A8", None],
    "pink": ["paper", "F2B7BE", None],
    "fox": ["paper", "D27330", None],
    "fox_dark": ["paper", "4A3326", None],
    "squirrel": ["paper", "9A6A43", None],
    "chame": ["paper", "4E9A3A", None],
    "chame_lite": ["paper", "9CCB5A", None],
    "phoenix_r": ["paper", "C8322A", None],
    "phoenix_o": ["paper", "E8822E", None],
    "phoenix_y": ["paper", "F0C23E", None],
    "acorn_cap": ["paper", "7A4A2A", None],
    "acorn_nut": ["paper", "D8B48A", None],
    "pumpkin": ["paper", "E58A2E", None],
    "stem": ["paper", "6E5A2E", None],
    "maple_r": ["felt", "C8452A", None],
    "maple_o": ["felt", "E07B2E", None],
    "maple_y": ["felt", "E8B03A", None],
    "frog": ["paper", "5FA03C", None],
    "frog_lite": ["paper", "B5D66A", None],
    "peacock": ["paper", "2C5F8A", None],
    "peacock_g": ["paper", "2E7A6A", None],
    "peacock_eye_o": ["paper", "E8A63A", None],
    "peacock_eye_b": ["paper", "1E3A6A", None],
    "pony": ["felt", "3E7F86", None],
    "pony_dark": ["felt", "2C5A60", None],
    "pony_saddle": ["felt", "C9A86A", None],
    "brass": ["plain", "C79A42", None],
    "wood_btn": ["plain", "8A5A34", None],
    "yarn_mane": ["yarn", "E8DCC2", None],
    "yarn_red": ["yarn", "B8352B", None],
    "thread_cream": ["plain", "EFE6D2", None],
    "thread_red": ["plain", "B8352B", None],
}
EXPORT = bool(getattr(A, "export", ""))
_M = {}


def M(key):
    """素材を名前で引く（一度だけ作る）。書き出しでは名前と色だけ"""
    if key in _M:
        return _M[key]
    kind, hexcol, pat = MATS[key]
    if EXPORT:
        m = plain(key, hexcol, 0.9)
    elif pat:
        m = paper(key, image=pattern("p_" + key, pat[0], hexcol, pat[1], pat[2]), img_scale=6.0 if pat[0] == "seigaiha" else (5.0 if pat[0] == "shippo" else 3.0), tint=0.08)
    elif kind == "paper":
        m = paper(key, hexcol, tint=0.1)
    elif kind == "felt":
        m = felt(key, hexcol)
    elif kind == "yarn":
        m = yarn(key, hexcol)
    else:
        m = plain(key, hexcol, 0.35 if key == "brass" else (0.55 if key == "ink" else 0.7))
    m.name = key
    _M[key] = m
    return m


# ================================================================ 形の小道具
def bake(o):
    """物体の置き方（位置・回転・大きさ）を形の頂点に焼き、置き方を元に戻す（あとで moved で動かせるように）"""
    o.data.transform(o.matrix_basis)
    o.matrix_basis = Matrix.Identity(4)
    return o


def sphere(name, loc, r, mat, scale=(1, 1, 1), seg=24):
    return bake(L.sphere(name, loc, r, mat, scale, seg))


def cyl(name, loc, r, depth, mat, rot=(0, 0, 0), verts=14, smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    return bake(finish(o, mat, smooth=smooth))


def tri(name, a, b, c, mat, th=0.003, seed=0):
    """紙 1 枚の三角（表は mat、裏は白）"""
    return thicken(mesh(name, [a, b, c], [(0, 1, 2)], [mat, M("white")], seed=seed), th)


def quad(name, a, b, c, d, mat, th=0.003, seed=0):
    return thicken(mesh(name, [a, b, c, d], [(0, 1, 2, 3)], [mat, M("white")], seed=seed), th)


def eye_dot(name, at, r=0.006):
    return sphere(name, at, r, M("ink"), seg=10)


def eye_shut(name, at, w=0.016, side=1.0):
    """閉じた目: 細い墨の弧（寝ているとき）"""
    pts = [at + V(side * w * (i / 4 - 0.5), 0.0, -0.004 * math.sin(math.pi * i / 4)) for i in range(5)]
    return tube(name, pts, [0.0022] * 5, 5, M("ink"), flat=False)


class Item:
    """品物ひとつ。部品の名前 → [物体]、支点 → 位置（品物の座標）"""

    def __init__(self, key):
        self.key = key
        self.parts = {}
        self.pivots = {}

    def add(self, part, objs, pivot=None):
        self.parts.setdefault(part, []).extend(objs if isinstance(objs, list) else [objs])
        if pivot is not None:
            self.pivots[part] = V(*pivot)

    def all(self):
        return [o for v in self.parts.values() for o in v]

    def place(self, at, yaw=0.0, scale=1.0):
        e = link(bpy.data.objects.new(self.key, None))
        for o in self.all():
            o.parent = e
        e.location = at
        e.rotation_euler = (0, 0, math.radians(yaw))
        e.scale = (scale,) * 3
        return e


def collect(fn):
    """fn() の中で作った物体を拾う"""
    before = set(bpy.data.objects.keys())
    fn()
    return [bpy.data.objects[k] for k in bpy.data.objects.keys() if k not in before and bpy.data.objects[k].type == "MESH"]


def moved(objs, mtx):
    """作った物体を、まとめて動かす（形の頂点に焼く）"""
    for o in objs:
        o.data.transform(mtx)
    return objs


# ================================================================ A. 頭・肩の小物
def p_chiyo_bird(pose="sit"):
    """A1 千代紙の小鳥（今の小鳥）。ボードの千代紙の狐と鶴の紙、青い小鳥の形"""
    it = Item("chiyo_bird")
    c, w = M("chiyo_red"), M("white")
    it.add("body", hull("cb_body", [V(0, 0.05, 0.035), V(0, -0.05, 0.03), V(0.026, 0.0, 0.025), V(-0.026, 0.0, 0.025), V(0, 0.0, 0.0), V(0, 0.01, 0.055)], c, 1))
    for s in (1, -1):
        it.add("body", tri("cb_wing", V(s * 0.024, 0.025, 0.04), V(s * 0.03, -0.05, 0.035), V(s * 0.05, -0.065, 0.07), c, seed=4))
    it.add("body", tri("cb_tail", V(0.012, -0.045, 0.032), V(-0.012, -0.045, 0.032), V(0, -0.11, 0.075), c, seed=5))
    it.add("head", [hull("cb_head", [V(0, 0.045, 0.05), V(0.017, 0.058, 0.062), V(-0.017, 0.058, 0.062), V(0, 0.068, 0.085), V(0, 0.062, 0.045)], c, 2),
                    hull("cb_beak", [V(0.006, 0.072, 0.065), V(-0.006, 0.072, 0.065), V(0, 0.07, 0.072), V(0, 0.1, 0.062)], M("beak"), 3),
                    eye_dot("cb_eye_l", V(0.016, 0.066, 0.068), 0.004), eye_dot("cb_eye_r", V(-0.016, 0.066, 0.068), 0.004)], (0, 0.045, 0.05))
    return it


def p_blue_bird():
    """A2 青い折り紙の小鳥（ボード: 水色の体、桃色の胸、青緑の羽を立てた、ずんぐりした小鳥）。肩に"""
    it = Item("blue_bird")
    s_, p, t = M("sky"), M("pink"), M("teal")
    it.add("body", hull("bb_body", ellipse_pts(V(0, -0.01, 0.0), 0.04, 0.055, 0, 6) + ellipse_pts(V(0, 0.0, 0.05), 0.05, 0.065, 0, 7, 0.3) +
                         [V(0, 0.07, 0.07), V(0, -0.07, 0.06), V(0, 0.01, 0.1)], s_, 11))
    it.add("body", hull("bb_belly", [V(0.035, 0.045, 0.01), V(-0.035, 0.045, 0.01), V(0, 0.07, 0.04), V(0.03, 0.06, 0.07), V(-0.03, 0.06, 0.07), V(0, 0.03, 0.0)], p, 12))
    for s in (1, -1):
        it.add("wing_" + ("l" if s > 0 else "r"), [tri("bb_wing_a", V(s * 0.03, 0.01, 0.075), V(s * 0.035, -0.06, 0.08), V(s * 0.06, -0.075, 0.16), t, seed=13),
                                                   tri("bb_wing_b", V(s * 0.03, 0.01, 0.075), V(s * 0.06, -0.075, 0.16), V(s * 0.07, -0.01, 0.13), p, seed=14)], (s * 0.03, -0.02, 0.08))
    it.add("body", tri("bb_tail", V(0.02, -0.055, 0.05), V(-0.02, -0.055, 0.05), V(0, -0.12, 0.09), t, seed=15))
    it.add("head", [hull("bb_head", [V(0.035, 0.05, 0.08), V(-0.035, 0.05, 0.08), V(0, 0.09, 0.09), V(0, 0.06, 0.135), V(0, 0.02, 0.11), V(0.03, 0.07, 0.11), V(-0.03, 0.07, 0.11)], s_, 16),
                    hull("bb_face", [V(0.028, 0.075, 0.08), V(-0.028, 0.075, 0.08), V(0, 0.095, 0.085), V(0, 0.085, 0.115)], p, 17),
                    hull("bb_beak", [V(0.008, 0.094, 0.095), V(-0.008, 0.094, 0.095), V(0, 0.093, 0.105), V(0, 0.115, 0.093)], M("white"), 18),
                    eye_dot("bb_eye_l", V(0.024, 0.085, 0.103), 0.0045), eye_dot("bb_eye_r", V(-0.024, 0.085, 0.103), 0.0045)], (0, 0.04, 0.08))
    return it


def p_crane():
    """A3 千代紙の折り鶴（ボード: 橙の千代紙の鶴）。頭に"""
    it = Item("crane")
    c, w = M("chiyo_orange"), M("white")
    it.add("body", hull("cr_body", [V(0, 0.04, 0.02), V(0, -0.04, 0.02), V(0.024, 0, 0.015), V(-0.024, 0, 0.015), V(0, 0, 0.0), V(0, 0, 0.045)], c, 1))
    it.add("body", tri("cr_tail", V(0.004, -0.028, 0.02), V(-0.004, -0.028, 0.02), V(0, -0.115, 0.11), c, 0.004, 2))
    it.add("head", [tri("cr_neck", V(0.004, 0.028, 0.02), V(-0.004, 0.028, 0.02), V(0, 0.11, 0.12), c, 0.004, 3),
                    tri("cr_head", V(0.003, 0.105, 0.115), V(-0.003, 0.105, 0.115), V(0, 0.145, 0.095), c, 0.004, 4)], (0, 0.028, 0.02))
    for s in (1, -1):
        it.add("wing_" + ("l" if s > 0 else "r"), tri("cr_wing", V(s * 0.004, 0.035, 0.04), V(s * 0.004, -0.035, 0.04), V(s * 0.14, -0.02, 0.11), c, 0.003, 5), (s * 0.004, 0, 0.04))
    return it


def p_hummingbird():
    """A4 白い折り紙のハチドリ（ボード: 白い紙の、羽を上げて飛ぶ鳥）。肩の上に浮いて羽ばたく"""
    it = Item("hummingbird")
    w = M("white")
    it.add("body", hull("hb_body", [V(0, 0.05, 0.06), V(0, -0.05, 0.05), V(0.016, 0.0, 0.055), V(-0.016, 0.0, 0.055), V(0, 0.0, 0.035), V(0, 0.01, 0.075)], w, 1))
    it.add("body", tri("hb_tail", V(0.008, -0.045, 0.055), V(-0.008, -0.045, 0.055), V(0, -0.12, 0.03), w, 0.003, 2))
    it.add("head", [hull("hb_head", [V(0, 0.045, 0.06), V(0.012, 0.06, 0.07), V(-0.012, 0.06, 0.07), V(0, 0.075, 0.085), V(0, 0.07, 0.055)], w, 3),
                    tube("hb_beak", [V(0, 0.075, 0.07), V(0, 0.14, 0.068)], [0.003, 0.0012], 5, M("ink"), flat=False),
                    eye_dot("hb_eye_l", V(0.011, 0.07, 0.074), 0.003), eye_dot("hb_eye_r", V(-0.011, 0.07, 0.074), 0.003)], (0, 0.045, 0.06))
    for s in (1, -1):
        it.add("wing_" + ("l" if s > 0 else "r"), [tri("hb_wing", V(s * 0.01, 0.025, 0.07), V(s * 0.01, -0.02, 0.07), V(s * 0.09, -0.03, 0.17), w, 0.002, 4),
                                                   tri("hb_wing2", V(s * 0.01, -0.02, 0.07), V(s * 0.09, -0.03, 0.17), V(s * 0.05, -0.06, 0.12), w, 0.002, 5)], (s * 0.01, 0, 0.07))
    if not EXPORT:
        it.add("body", tube("hb_stalk", [V(0, 0, 0.0), V(0, 0, 0.04)], [0.0015, 0.0015], 4, M("thread_cream"), flat=False))   # 肩から浮かせる目安（ラフだけ。ゲームでは浮かせて羽ばたく）
    return it


def p_squirrel():
    """A5 モモンガ（ボード: 茶と白の折り紙の、膜を広げたモモンガ）。頭に腹ばいで広がる"""
    it = Item("squirrel")
    b, c = M("squirrel"), M("cream")
    sail = [V(0.075, 0.06, 0.02), V(0.085, -0.06, 0.02), V(-0.085, -0.06, 0.02), V(-0.075, 0.06, 0.02)]
    it.add("body", quad("ms_sail", *sail, c, 0.003, 1))
    it.add("body", hull("ms_back", [V(0.03, 0.05, 0.022), V(-0.03, 0.05, 0.022), V(0.035, -0.05, 0.022), V(-0.035, -0.05, 0.022), V(0, 0.0, 0.05), V(0, 0.05, 0.035), V(0, -0.05, 0.035)], b, 2))
    for s in (1, -1):
        it.add("body", tri("ms_paw_f", V(s * 0.075, 0.06, 0.021), V(s * 0.095, 0.08, 0.018), V(s * 0.06, 0.07, 0.021), b, 0.003, 3))
        it.add("body", tri("ms_paw_b", V(s * 0.085, -0.06, 0.021), V(s * 0.1, -0.08, 0.018), V(s * 0.07, -0.07, 0.021), b, 0.003, 4))
    it.add("tail", hull("ms_tail", [V(0.012, -0.05, 0.025), V(-0.012, -0.05, 0.025), V(0.02, -0.13, 0.04), V(-0.02, -0.13, 0.04), V(0, -0.16, 0.06), V(0, -0.09, 0.05)], b, 5), (0, -0.05, 0.03))
    it.add("head", [hull("ms_head", [V(0.035, 0.05, 0.03), V(-0.035, 0.05, 0.03), V(0, 0.1, 0.035), V(0, 0.065, 0.075), V(0.025, 0.08, 0.05), V(-0.025, 0.08, 0.05)], b, 6),
                    hull("ms_face", [V(0.02, 0.085, 0.032), V(-0.02, 0.085, 0.032), V(0, 0.103, 0.036), V(0, 0.09, 0.055)], c, 7),
                    eye_dot("ms_eye_l", V(0.02, 0.087, 0.055), 0.0045), eye_dot("ms_eye_r", V(-0.02, 0.087, 0.055), 0.0045),
                    tri("ms_ear_l", V(0.02, 0.06, 0.06), V(0.04, 0.055, 0.055), V(0.04, 0.05, 0.085), b, 0.003, 8),
                    tri("ms_ear_r", V(-0.02, 0.06, 0.06), V(-0.04, 0.055, 0.055), V(-0.04, 0.05, 0.085), b, 0.003, 9)], (0, 0.05, 0.035))
    return it


def p_moon_rabbit():
    """A6 月と兎（ボード: 墨の筆の線を書いた三日月の紙に、白い折り紙の兎が座る）。頭に。文字は書かない"""
    it = Item("moon_rabbit")
    m = M("moon")
    pts_o, pts_i = [], []
    for i in range(15):
        a = math.radians(195 + 150 * i / 14)   # 揺りかごの形の三日月（角が上へ）
        pts_o.append(V(0, 0.13 * math.cos(a), 0.13 + 0.13 * math.sin(a)))
        pts_i.append(V(0, 0.105 * math.cos(a), 0.165 + 0.115 * math.sin(a)))
    verts, faces = [], []
    for k in range(15):
        for p in (pts_o[k], pts_i[k]):
            verts.append(p)
    for k in range(14):
        faces.append((2 * k, 2 * k + 2, 2 * k + 3, 2 * k + 1))
    moon = thicken(mesh("mr_moon", verts, faces, [m, m], seed=1), 0.012, rim_white=False)
    it.add("body", moon)
    moved([moon], Matrix.Translation(V(0, 0, -0.005)))
    rb = collect(lambda: _rabbit_sit("mr", 0.42))
    moved(rb, Matrix.Translation(V(0, 0.0, 0.045)))
    it.add("head", rb, (0, 0.02, 0.01))
    return it


def p_chameleon():
    """A7 緑のカメレオン（ボード: 蛇腹に折った緑の紙、渦に巻いたしっぽ）。肩にしがみつく"""
    it = Item("chameleon")
    g, gl = M("chame"), M("chame_lite")
    # 蛇腹の胴: 山と谷を交互に、色を交互に
    n = 9
    for i in range(n):
        y0 = 0.055 - i * 0.013
        y1 = y0 - 0.017
        r0 = 0.03 + 0.008 * math.sin(math.pi * i / (n - 1))
        r1 = 0.03 + 0.008 * math.sin(math.pi * (i + 1) / (n - 1))
        it.add("body", hull("ch_seg", ellipse_pts(V(0, y0, 0.03), r0, 0.004, 0, 6) + ellipse_pts(V(0, y1, 0.031 + (0.004 if i % 2 else 0)), r1, 0.004, 0, 6) + [V(0, (y0 + y1) / 2, 0.0)] +
                            [V(0, (y0 + y1) / 2, 0.03 + r0 + (0.005 if i % 2 else 0))], g if i % 2 else gl, 10 + i))
    # 渦のしっぽ
    pts = []
    for i in range(22):
        t = i / 21
        a = t * math.pi * 2.6
        r = 0.035 * (1 - t * 0.75)
        pts.append(V(0, -0.06 - 0.03 * t - r * math.sin(a) * 0.2, 0.03 - r + r * math.cos(a) - 0.0 * t))
    pts = [V(0, -0.06 - 0.02 * math.sin(i / 21 * math.pi * 2.6) * (1 - i / 21), 0.035 - 0.035 * (1 - i / 21) * (1 - math.cos(i / 21 * math.pi * 2.6)) - 0.004 * i / 21) for i in range(22)]
    it.add("tail", tube("ch_tail", pts, [0.012 * (1 - 0.8 * i / 21) for i in range(22)], 6, g, seed=30), (0, -0.06, 0.03))
    for s in (1, -1):
        for y in (0.035, -0.04):
            it.add("body", tube("ch_leg", [V(s * 0.02, y, 0.03), V(s * 0.04, y + 0.005, 0.012), V(s * 0.045, y + 0.01, 0.0)], [0.006, 0.005, 0.004], 5, g, seed=31))
    it.add("head", [hull("ch_head", [V(0.022, 0.05, 0.03), V(-0.022, 0.05, 0.03), V(0, 0.105, 0.03), V(0, 0.05, 0.075), V(0, 0.07, 0.06), V(0.015, 0.09, 0.025), V(-0.015, 0.09, 0.025)], gl, 32),
                    sphere("ch_eye_l", V(0.022, 0.075, 0.045), 0.011, M("white"), seg=12), sphere("ch_eye_r", V(-0.022, 0.075, 0.045), 0.011, M("white"), seg=12),
                    eye_dot("ch_pupil_l", V(0.031, 0.078, 0.046), 0.004), eye_dot("ch_pupil_r", V(-0.031, 0.078, 0.046), 0.004)], (0, 0.05, 0.035))
    return it


def p_phoenix():
    """A8 鳳凰（ボード: 赤と橙と黄の紙を重ねた、羽を広げた鳥）。肩に。羽としっぽが長い、いちばんの品"""
    it = Item("phoenix")
    r, o, y = M("phoenix_r"), M("phoenix_o"), M("phoenix_y")
    it.add("body", hull("ph_body", [V(0, 0.05, 0.04), V(0, -0.05, 0.035), V(0.025, 0.0, 0.03), V(-0.025, 0.0, 0.03), V(0, 0.0, 0.0), V(0, 0.02, 0.07)], r, 1))
    for i, (m, ln, sp) in enumerate(((y, 0.2, 0.025), (o, 0.24, 0.0), (r, 0.2, -0.025))):
        it.add("tail", tri("ph_tail", V(0.006, -0.04, 0.035), V(-0.006, -0.04, 0.035), V(sp, -0.04 - ln, 0.015 - 0.04 * abs(sp) / 0.025), m, 0.003, 2 + i), (0, -0.04, 0.035))
    for s in (1, -1):
        side = "l" if s > 0 else "r"
        for i, (m, tip) in enumerate(((y, V(s * 0.16, -0.05, 0.2)), (o, V(s * 0.13, -0.09, 0.15)), (r, V(s * 0.09, -0.1, 0.1)))):
            it.add("wing_" + side, tri("ph_wing", V(s * 0.02, 0.03, 0.05), V(s * 0.02, -0.03, 0.05), tip, m, 0.003, 6 + i), (s * 0.02, 0, 0.05))
    it.add("head", [hull("ph_head", [V(0, 0.045, 0.06), V(0.016, 0.06, 0.075), V(-0.016, 0.06, 0.075), V(0, 0.07, 0.1), V(0, 0.06, 0.055)], r, 10),
                    hull("ph_beak", [V(0.006, 0.072, 0.08), V(-0.006, 0.072, 0.08), V(0, 0.07, 0.088), V(0, 0.1, 0.075)], y, 11),
                    tri("ph_crest", V(0.003, 0.06, 0.095), V(-0.003, 0.06, 0.095), V(0, 0.03, 0.15), o, 0.003, 12),
                    eye_dot("ph_eye_l", V(0.015, 0.068, 0.085), 0.0035), eye_dot("ph_eye_r", V(-0.015, 0.068, 0.085), 0.0035)], (0, 0.045, 0.06))
    return it


def _lathe_faceted(name, prof, segs, mat, seed=0, center=V(0, 0, 0)):
    """ペーパークラフトの、角のある回転体（展開図から組んだ形）"""
    verts, faces = [], []
    for j, (r, z) in enumerate(prof):
        for i in range(segs):
            a = 2 * math.pi * i / segs
            verts.append(center + V(r * math.cos(a), r * math.sin(a), z))
    for j in range(len(prof) - 1):
        for i in range(segs):
            k = (i + 1) % segs
            faces.append((j * segs + i, j * segs + k, (j + 1) * segs + k, (j + 1) * segs + i))
    ob = mesh(name, verts, faces, mat, seed=seed)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.contextual_create(bm, geom=[e for e in bm.edges if e.is_boundary])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    L.add_tint(ob.data, seed)
    return ob


def p_acorn():
    """A9 紙のどんぐり（ボード: ペーパークラフトのどんぐり。こげ茶のかさ、明るい実）。頭に"""
    it = Item("acorn")
    it.add("body", _lathe_faceted("ac_nut", [(0.0, 0.0), (0.03, 0.012), (0.05, 0.045), (0.055, 0.085), (0.05, 0.1)], 7, M("acorn_nut"), 1))
    it.add("body", _lathe_faceted("ac_cap", [(0.052, 0.085), (0.064, 0.1), (0.06, 0.125), (0.035, 0.145), (0.0, 0.15)], 7, M("acorn_cap"), 2))
    it.add("body", tube("ac_stem", [V(0, 0, 0.145), V(0.004, 0, 0.165), V(0.012, 0, 0.175)], [0.007, 0.006, 0.005], 5, M("acorn_cap"), seed=3))
    return it


def p_pumpkin():
    """A10 紙のかぼちゃ（ボード: ペーパークラフトのかぼちゃ）。頭に"""
    it = Item("pumpkin")
    segs = 16
    prof = [(0.0, 0.0), (0.045, 0.006), (0.075, 0.03), (0.082, 0.06), (0.07, 0.09), (0.035, 0.105), (0.0, 0.1)]
    ob = _lathe_faceted("pk_body", prof, segs, M("pumpkin"), 1)
    for v in ob.data.vertices:   # 筋: ひとつおきに内へ
        a = math.atan2(v.co.y, v.co.x)
        k = round(a / (2 * math.pi / segs))
        if k % 2:
            v.co.x *= 0.9
            v.co.y *= 0.9
    it.add("body", ob)
    it.add("body", tube("pk_stem", [V(0, 0, 0.095), V(0.003, 0.002, 0.125), V(0.015, 0.006, 0.14)], [0.01, 0.008, 0.007], 5, M("stem"), seed=2))
    return it


def p_maple():
    """A11 紅葉の葉 3 枚（ボード: 頭から生えた赤・橙・黄の紅葉）。頭に冠のように立てる"""
    it = Item("maple")
    for i, (m, a) in enumerate(((M("maple_r"), 0.0), (M("maple_o"), 0.75), (M("maple_y"), -0.75))):
        pts = []
        n = 70
        for k in range(n):   # 5 つに裂けた葉: 裂けめの深い星形に、細かい鋸の歯
            th = 2 * math.pi * k / n
            lobe = abs(math.cos(2.5 * (th - math.pi / 2))) ** 3
            saw = 0.08 * (k % 2)
            rr = 0.068 * (0.32 + 0.68 * lobe + saw * lobe)
            if math.sin(th) < -0.6:   # 柄の側は短く
                rr *= 0.55
            pts.append(V(math.cos(th) * rr, 0, math.sin(th) * rr))
        ob = thicken(mesh("mp_leaf", [V(0, 0, 0)] + pts, [(0, k + 1, (k + 1) % n + 1) for k in range(n)], [m, m], seed=4 + i), 0.004, rim_white=False)
        ob.data.transform(Matrix.Translation(V(0.045 * math.sin(a), -0.025 * abs(math.sin(a)) - 0.01 * i, 0.075 - 0.012 * abs(math.sin(a)))) @
                          Matrix.Rotation(a * 0.6, 4, "Y") @ Matrix.Rotation(-a * 0.5, 4, "Z") @ Matrix.Rotation(-0.15, 4, "X"))
        it.add("body", ob)
        it.add("body", tube("mp_stem", [V(0.04 * math.sin(a), -0.01 * abs(math.sin(a)), 0.0), V(0.045 * math.sin(a), -0.02, 0.04)], [0.004, 0.003], 4, M("stem"), seed=9))
    return it


PERCH = [  # [作る関数, 名前, 載せる所, 値段（木のボタンの何個分。0 ははじめから）, ボードの絵]
    (p_chiyo_bird, "千代紙の小鳥", "頭", 0, "千代紙の鶴と狐"),
    (p_blue_bird, "青い折り紙の小鳥", "肩", 30, "青い小鳥"),
    (p_acorn, "紙のどんぐり", "頭", 40, "どんぐり"),
    (p_crane, "千代紙の折り鶴", "頭", 60, "千代紙の鶴"),
    (p_pumpkin, "紙のかぼちゃ", "頭", 80, "かぼちゃ"),
    (p_maple, "紅葉の葉", "頭", 100, "紅葉の頭"),
    (p_hummingbird, "白いハチドリ", "肩", 150, "白い鳥"),
    (p_squirrel, "モモンガ", "頭", 200, "モモンガ"),
    (p_chameleon, "カメレオン", "肩", 300, "カメレオン"),
    (p_moon_rabbit, "月と兎", "頭", 500, "月の兎"),
    (p_phoenix, "鳳凰", "肩", 1000, "鳳凰"),
]


# ================================================================ B. ミニオン
def _fox_head(prefix, mat, belly, dark, sleep=False):
    """多面体の折り紙の狐の頭（今の子狐の頭）。支点（首）が原点"""
    o = V(0, -0.04, -0.22)
    s = 1.2
    def P(*a):
        return (V(*a) + o) * s
    objs = [hull(prefix + "_head", [P(0.052, 0.04, 0.27), P(-0.052, 0.04, 0.27), P(0.04, 0.015, 0.315), P(-0.04, 0.015, 0.315), P(0, 0.0, 0.305),
                                     P(0, 0.06, 0.225), P(0, 0.165, 0.255), P(0.022, 0.12, 0.25), P(-0.022, 0.12, 0.25), P(0, 0.1, 0.29)], mat, 13),
            hull(prefix + "_cheek", [P(0.045, 0.06, 0.245), P(-0.045, 0.06, 0.245), P(0, 0.07, 0.228), P(0, 0.165, 0.253), P(0.02, 0.12, 0.243), P(-0.02, 0.12, 0.243)], belly, 14),
            hull(prefix + "_nose", [P(0, 0.17, 0.258), P(0.01, 0.155, 0.262), P(-0.01, 0.155, 0.262), P(0, 0.157, 0.25), P(0, 0.155, 0.272)], dark, 15)]
    for sd in (1, -1):
        objs.append(hull(prefix + "_ear", [P(sd * 0.018, 0.03, 0.305), P(sd * 0.058, 0.035, 0.29), P(sd * 0.04, 0.0, 0.3), P(sd * 0.052, 0.025, 0.385)], mat, 16))
        if sleep:
            objs.append(eye_shut(prefix + "_eye", P(sd * 0.037, 0.095, 0.285), 0.02, sd))
        else:
            objs.append(hull(prefix + "_eye", [P(sd * 0.03, 0.098, 0.283), P(sd * 0.045, 0.085, 0.29), P(sd * 0.038, 0.094, 0.278), P(sd * 0.033, 0.09, 0.29)], dark, 17))
    return objs


def _fox_tail(prefix, mat, belly, curl=0.0):
    """狐のしっぽ: 付け根が原点で、うしろ（-Y）へ。curl で体の横へ巻く"""
    pts = [V(0, 0, 0), V(0.04, -0.08, -0.04), V(0.06, -0.17, -0.06), V(0.05, -0.24, -0.04)]
    objs = [hull(prefix + "_tail", [V(0, 0, 0.01), V(0.015, 0.0, -0.02), V(-0.015, 0, -0.02), V(0.07, -0.1, -0.01), V(0.02, -0.12, -0.07), V(0.09, -0.15, -0.06),
                                     V(0.05, -0.2, 0.0)], mat, 19),
            hull(prefix + "_tip", [V(0.05, -0.2, 0.0), V(0.09, -0.16, -0.06), V(0.06, -0.27, -0.05), V(0.07, -0.25, -0.02), V(0.08, -0.2, -0.07)], belly, 20)]
    if curl:
        moved(objs, Matrix.Rotation(curl, 4, "Z"))
    return objs


def m_fox(pose, mat_key="fox", key="kit"):
    """B1 折り紙の子狐（ボード: 橙の多面体の折り紙の狐、星の王子さまの狐）／ B2 千代紙の狐（ボード: 千代紙の狐）"""
    it = Item(key + "_" + pose)
    m, b, d = M(mat_key), M("cream"), M("fox_dark")
    pf = key
    if pose == "sit":
        it.add("body", hull(pf + "_body", ellipse_pts(V(0, -0.036, 0.0), 0.096, 0.12, 0, 7) + ellipse_pts(V(0, -0.048, 0.096), 0.1, 0.108, 0, 7) +
                            ellipse_pts(V(0, 0.048, 0.24), 0.054, 0.048, 0, 6), m, 11))
        it.add("body", hull(pf + "_chest", [V(0, 0.096, 0.036), V(0.042, 0.078, 0.108), V(-0.042, 0.078, 0.108), V(0.036, 0.072, 0.24), V(-0.036, 0.072, 0.24), V(0, 0.105, 0.168)], b, 12))
        for sd in (1, -1):
            it.add("leg_f" + ("l" if sd > 0 else "r"), tube(pf + "_leg", [V(sd * 0.036, 0.072, 0.18), V(sd * 0.036, 0.09, 0.0)], [0.017, 0.014], 5, d, seed=18), (sd * 0.036, 0.072, 0.18))
        it.add("head", _fox_head(pf, m, b, d), (0, 0.048, 0.264))
        moved(it.parts["head"], Matrix.Translation(V(0, 0.048, 0.264)))
        it.add("tail", moved(_fox_tail(pf, m, b, curl=-0.3), Matrix.Translation(V(0.04, -0.13, 0.06)) @ Matrix.Rotation(math.radians(-60), 4, "Z") @ Matrix.Rotation(-0.6, 4, "X")), (0.04, -0.13, 0.06))
    elif pose == "walk":
        hy = 0.17   # 胴の高さ
        it.add("body", hull(pf + "_body", ellipse_pts(V(0, -0.12, hy), 0.07, 0.001, 0, 7) + [V(0, -0.15, hy)] + ellipse_pts(V(0, 0.0, hy + 0.01), 0.085, 0.001, 0, 7) +
                            ellipse_pts(V(0, 0.1, hy + 0.03), 0.07, 0.001, 0, 7), m, 11))
        it.add("body", hull(pf + "_chest", [V(0.04, 0.1, hy - 0.04), V(-0.04, 0.1, hy - 0.04), V(0, 0.15, hy + 0.02), V(0, 0.05, hy - 0.06), V(0.03, 0.13, hy + 0.04), V(-0.03, 0.13, hy + 0.04)], b, 12))
        for sd in (1, -1):
            nm = "l" if sd > 0 else "r"
            it.add("leg_f" + nm, tube(pf + "_leg", [V(sd * 0.04, 0.09, hy - 0.02), V(sd * 0.042, 0.095, 0.08), V(sd * 0.042, 0.1, 0.0)], [0.02, 0.016, 0.013], 5, m if sd else d, seed=18), (sd * 0.04, 0.09, hy - 0.02))
            it.add("leg_b" + nm, tube(pf + "_legb", [V(sd * 0.045, -0.1, hy - 0.01), V(sd * 0.05, -0.13, 0.08), V(sd * 0.045, -0.11, 0.0)], [0.026, 0.017, 0.013], 5, m, seed=19), (sd * 0.045, -0.1, hy - 0.01))
        it.add("head", moved(_fox_head(pf, m, b, d), Matrix.Translation(V(0, 0.13, hy + 0.06)) @ Matrix.Rotation(-0.25, 4, "X")), (0, 0.13, hy + 0.06))
        it.add("tail", moved(_fox_tail(pf, m, b), Matrix.Translation(V(0, -0.14, hy + 0.01)) @ Matrix.Rotation(0.5, 4, "X")), (0, -0.14, hy + 0.01))
    else:   # sleep: 丸まって、しっぽを鼻先へ巻く
        it.add("body", hull(pf + "_body", ellipse_pts(V(0, 0, 0.0), 0.13, 0.14, 0, 8) + ellipse_pts(V(0.0, -0.01, 0.1), 0.1, 0.11, 0, 7, 0.3) + [V(0, -0.02, 0.135)], m, 11))
        it.add("head", moved(_fox_head(pf, m, b, d, sleep=True), Matrix.Translation(V(-0.06, 0.1, 0.05)) @ Matrix.Rotation(math.radians(-60), 4, "Z") @ Matrix.Rotation(0.25, 4, "X") @ Matrix.Rotation(0.5, 4, "Y")), (-0.06, 0.1, 0.05))
        it.add("tail", moved(_fox_tail(pf, m, b), Matrix.Translation(V(0.1, -0.08, 0.04)) @ Matrix.Rotation(math.radians(130), 4, "Z") @ Matrix.Rotation(0.75, 4, "X") @ Matrix.Rotation(0.3, 4, "Y")), (0.1, -0.08, 0.04))
    return it


def _rabbit_sit(pf, s=1.0, sleep=False):
    """白い折り紙の兎の、座った形（月と兎の兎にも）。s は大きさ"""
    w, pk = M("white"), M("pink")
    def P(*a):
        return V(*a) * s
    hull(pf + "_body", [P(c.x, c.y, c.z) for c in ellipse_pts(V(0, -0.02, 0.0), 0.09, 0.11, 0, 7) + ellipse_pts(V(0, -0.03, 0.1), 0.085, 0.09, 0, 7) + [V(0, 0.0, 0.17)]], w, 21)
    hull(pf + "_head", [P(0.06, 0.03, 0.17), P(-0.06, 0.03, 0.17), P(0, 0.11, 0.2), P(0, 0.03, 0.27), P(0.045, 0.08, 0.24), P(-0.045, 0.08, 0.24), P(0, -0.02, 0.22)], w, 22)
    hull(pf + "_nose", [P(0.008, 0.11, 0.205), P(-0.008, 0.11, 0.205), P(0, 0.115, 0.2), P(0, 0.11, 0.212)], pk, 23)
    for sd in (1, -1):
        if sleep:
            eye_shut(pf + "_eye", P(sd * 0.038, 0.085, 0.225), 0.018 * s, sd)
            tri(pf + "_ear", P(sd * 0.015, 0.0, 0.25), P(sd * 0.045, 0.0, 0.24), P(sd * 0.06, -0.18, 0.2), w, 0.003, 24)
        else:
            sphere(pf + "_eye", P(sd * 0.038, 0.088, 0.225), 0.0065 * s, M("ink"), seg=10)
            tri(pf + "_ear", P(sd * 0.015, 0.0, 0.25), P(sd * 0.045, 0.0, 0.24), P(sd * 0.04, -0.04, 0.42), w, 0.003, 24)
            tri(pf + "_earin", P(sd * 0.022, 0.003, 0.26), P(sd * 0.04, 0.003, 0.255), P(sd * 0.037, -0.03, 0.39), pk, 0.003, 25)
    hull(pf + "_tail", [P(0.02, -0.12, 0.03), P(-0.02, -0.12, 0.03), P(0, -0.15, 0.05), P(0, -0.12, 0.07)], w, 26)


def m_rabbit(pose):
    """B3 白い折り紙の兎（ボード: 月の上の白い兎）。跳ねて歩く"""
    it = Item("rabbit_" + pose)
    w, pk = M("white"), M("pink")
    if pose == "sit":
        objs = collect(lambda: _rabbit_sit("rb", 1.0))
        it.add("body", [o for o in objs if "_head" not in o.name and "_eye" not in o.name and "_ear" not in o.name and "_nose" not in o.name])
        it.add("head", [o for o in objs if o not in it.parts["body"]], (0, 0.02, 0.17))
    elif pose == "walk":   # 跳ねる途中: 体を伸ばし、うしろ足を蹴る
        objs = collect(lambda: _rabbit_sit("rb", 1.0))
        moved(objs, Matrix.Translation(V(0, 0, 0.05)) @ Matrix.Rotation(-0.5, 4, "X"))
        it.add("body", [o for o in objs if "_head" not in o.name and "_eye" not in o.name and "_ear" not in o.name and "_nose" not in o.name])
        it.add("head", [o for o in objs if o not in it.parts["body"]], (0, 0.08, 0.2))
        for sd in (1, -1):
            nm = "l" if sd > 0 else "r"
            it.add("leg_b" + nm, tube("rb_legb", [V(sd * 0.05, -0.08, 0.06), V(sd * 0.05, -0.17, 0.02)], [0.02, 0.012], 5, w, seed=27), (sd * 0.05, -0.08, 0.06))
            it.add("leg_f" + nm, tube("rb_legf", [V(sd * 0.03, 0.1, 0.1), V(sd * 0.03, 0.15, 0.03)], [0.013, 0.01], 5, w, seed=28), (sd * 0.03, 0.1, 0.1))
    else:
        objs = collect(lambda: _rabbit_sit("rb", 1.0, sleep=True))
        moved(objs, Matrix.Scale(1.0, 4) @ Matrix.Translation(V(0, 0, 0)))
        for o in objs:   # 平たくつぶして伏せる
            o.data.transform(Matrix.Diagonal((1.1, 1.15, 0.62, 1.0)))
        it.add("body", [o for o in objs if "_head" not in o.name and "_eye" not in o.name and "_ear" not in o.name and "_nose" not in o.name])
        it.add("head", [o for o in objs if o not in it.parts["body"]], (0, 0.02, 0.1))
    return it


def m_frog(pose):
    """B4 跳ねる折り紙のカエル（ボード: 動く折り紙の、跳ねるカエル）"""
    it = Item("frog_" + pose)
    g, gl = M("frog"), M("frog_lite")
    lift = {"walk": 0.07, "sit": 0.0, "sleep": -0.02}[pose]
    pitch = {"walk": -0.35, "sit": -0.25, "sleep": 0.0}[pose]
    mt = Matrix.Translation(V(0, 0, lift)) @ Matrix.Rotation(pitch, 4, "X")
    body = [hull("fr_body", [V(0.08, -0.08, 0.02), V(-0.08, -0.08, 0.02), V(0.07, 0.06, 0.02), V(-0.07, 0.06, 0.02), V(0, 0.11, 0.03), V(0, -0.1, 0.03),
                              V(0.05, -0.02, 0.09), V(-0.05, -0.02, 0.09), V(0, 0.04, 0.1)], g, 31),
            hull("fr_belly", [V(0.06, -0.06, 0.018), V(-0.06, -0.06, 0.018), V(0.05, 0.05, 0.018), V(-0.05, 0.05, 0.018), V(0, 0.09, 0.024), V(0, 0, 0.0)], gl, 32)]
    it.add("body", moved(body, mt))
    eyes = []
    for sd in (1, -1):
        eyes.append(hull("fr_eyebump", [V(sd * 0.025, 0.06, 0.09), V(sd * 0.055, 0.06, 0.09), V(sd * 0.04, 0.045, 0.085), V(sd * 0.04, 0.075, 0.085), V(sd * 0.04, 0.06, 0.12)], g, 33))
        eyes.append(eye_shut("fr_eye", V(sd * 0.04, 0.07, 0.112), 0.02, sd) if pose == "sleep" else eye_dot("fr_eye", V(sd * 0.04, 0.072, 0.112), 0.007))
    it.add("head", moved(eyes, mt), (0, 0.06 * math.cos(pitch), 0.09 + lift))
    for sd in (1, -1):
        nm = "l" if sd > 0 else "r"
        if pose == "walk":   # うしろ足を伸ばして蹴る
            bl = [V(sd * 0.07, -0.07, 0.07), V(sd * 0.1, -0.15, 0.03), V(sd * 0.11, -0.22, 0.0)]
        else:                # たたんだうしろ足（Z の折り目）
            bl = [V(sd * 0.07, -0.06, 0.03), V(sd * 0.12, -0.02, 0.03), V(sd * 0.11, -0.09, 0.0)]
        it.add("leg_b" + nm, tube("fr_legb", bl, [0.02, 0.016, 0.012], 4, g, seed=34), tuple(bl[0]))
        fl = [V(sd * 0.05, 0.06, 0.05 + lift), V(sd * 0.07, 0.09, 0.0)] if pose != "sleep" else [V(sd * 0.05, 0.06, 0.02), V(sd * 0.08, 0.1, 0.0)]
        it.add("leg_f" + nm, tube("fr_legf", fl, [0.012, 0.01], 4, g, seed=35), tuple(fl[0]))
    return it


def m_pony(pose):
    """B5 フェルトのポニー（ボード: 青緑のフェルトに、ボタンと渦巻きの刺繍、波の縁の鞍、木の脚の馬）"""
    it = Item("pony_" + pose)
    f, fd, sd_, br = M("pony"), M("pony_dark"), M("pony_saddle"), M("brass")
    hy = {"walk": 0.3, "sit": 0.2, "sleep": 0.13}[pose]
    def body_parts():
        b = sphere("po_body", V(0, 0, 0), 0.1, f, scale=(0.85, 1.55, 0.85), seg=20)
        objs = [b]
        # 鞍: 波の縁の布を背中に
        sad = sphere("po_saddle", V(0, -0.01, 0.0), 0.1, sd_, scale=(0.92, 0.95, 0.92), seg=20)
        for v in sad.data.vertices:   # 背中だけを覆い、縁は波に切る（下は胴の中に押し込む）
            cut = 0.035 + 0.012 * math.sin(math.atan2(v.co.y, v.co.x) * 8)
            if v.co.z < cut:
                v.co.z = cut - 0.02
                v.co.x *= 0.8
                v.co.y *= 0.8
        objs.append(sad)
        # ボタン（真鍮と木）と渦巻きの刺繍
        for i, (x, y, z) in enumerate(((0.083, 0.06, 0.02), (-0.083, 0.06, 0.02), (0.085, -0.08, -0.01), (-0.085, -0.08, -0.01), (0.07, 0.0, -0.04))):
            objs.append(cyl("po_button", (x, y, z), 0.016, 0.008, br if i % 2 == 0 else M("wood_btn"), (0, math.pi / 2, 0)))
        for sx in (1, -1):
            pts = [V(sx * 0.086, -0.02 + 0.03 * (1 - i / 16) * math.cos(i * 0.9), 0.0 + 0.03 * (1 - i / 16) * math.sin(i * 0.9)) for i in range(17)]
            objs.append(tube("po_swirl", pts, [0.003] * 17, 4, M("thread_cream"), flat=False))
        return objs
    it.add("body", moved(body_parts(), Matrix.Translation(V(0, 0, hy)) @ Matrix.Rotation(-0.5 if pose == "sit" else 0.0, 4, "X")))
    # 首と頭
    def head():
        h = [sphere("po_head", V(0, 0.05, 0.02), 0.05, f, scale=(0.8, 1.45, 0.85), seg=16),
             sphere("po_muzzle", V(0, 0.11, 0.0), 0.035, fd, scale=(0.9, 1.0, 0.8), seg=12),
             tube("po_neck", [V(0, -0.06, -0.09), V(0, 0.0, 0.0)], [0.05, 0.042], 10, f, flat=False)]
        for sd in (1, -1):
            h.append(hull("po_ear", [V(sd * 0.025, 0.02, 0.05), V(sd * 0.04, 0.03, 0.05), V(sd * 0.03, 0.0, 0.05), V(sd * 0.035, 0.015, 0.095)], fd, 40))
            if pose == "sleep":
                h.append(eye_shut("po_eye", V(sd * 0.04, 0.07, 0.035), 0.018, sd))
            else:
                h.append(cyl("po_eye", (sd * 0.041, 0.07, 0.035), 0.009, 0.006, M("ink"), (0, math.pi / 2, 0), 12))
        # 毛糸のたてがみ
        for i in range(7):
            t = i / 6
            p0 = V(0, -0.08 + 0.1 * t, -0.07 + 0.11 * t + 0.03)
            h.append(tube("po_mane", [p0, p0 + V(0.0, -0.03, 0.03)], [0.012, 0.008], 5, M("yarn_mane"), flat=False))
        return h
    hp = {"walk": V(0, 0.17, hy + 0.12), "sit": V(0, 0.11, hy + 0.19), "sleep": V(0.0, 0.2, 0.06)}[pose]
    hr = {"walk": 0.0, "sit": -0.1, "sleep": 0.6}[pose]
    it.add("head", moved(head(), Matrix.Translation(hp) @ Matrix.Rotation(hr, 4, "X") @ Matrix.Rotation(-0.5 if pose == "sleep" else 0.0, 4, "Z")), tuple(hp))
    # 脚: 木の丸棒（ボードの馬の細い木の脚）
    for sd in (1, -1):
        nm = "l" if sd > 0 else "r"
        for fb, y in (("f", 0.09), ("b", -0.1)):
            if pose == "walk":
                pts = [V(sd * 0.05, y, hy - 0.03), V(sd * 0.05, y, 0.0)]
            elif pose == "sit":   # 前脚は立て、うしろ脚は腰の下から前へたたむ
                pts = [V(sd * 0.05, 0.1, hy + 0.08), V(sd * 0.05, 0.12, 0.0)] if fb == "f" else [V(sd * 0.08, -0.07, 0.1), V(sd * 0.085, 0.03, 0.02)]
            else:
                pts = [V(sd * 0.06, y, 0.07), V(sd * 0.07, y + 0.12, 0.015)]
            it.add("leg_" + fb + nm, tube("po_leg", pts, [0.014, 0.012], 8, M("wood_btn"), flat=False), tuple(pts[0]))
    tp = {"walk": V(0, -0.15, hy + 0.04), "sit": V(0, -0.15, 0.15), "sleep": V(0.04, -0.14, 0.08)}[pose]
    it.add("tail", [tube("po_tail", [tp, tp + V(0.0, -0.04, -0.07 + 0.01 * i), tp + V(0.01 * i, -0.05, -0.15)], [0.012, 0.01, 0.007], 5, M("yarn_mane"), flat=False) for i in (-1, 0, 1)], tuple(tp))
    return it


def m_peacock(pose):
    """B6 孔雀（ボード: 藍と青緑の紙の孔雀、目玉の柄の羽を広げる）。座ると羽を広げ、歩くと羽をたたんで引きずる"""
    it = Item("peacock_" + pose)
    b, g, eo, eb = M("peacock"), M("peacock_g"), M("peacock_eye_o"), M("peacock_eye_b")
    lift = 0.0 if pose == "sleep" else 0.12
    it.add("body", hull("pc_body", ellipse_pts(V(0, -0.02, lift), 0.06, 0.09, 0, 7) + ellipse_pts(V(0, 0.0, lift + 0.08), 0.055, 0.075, 0, 7, 0.3) + [V(0, 0.07, lift + 0.12)], b, 41))
    # 首と頭
    if pose == "sleep":
        hp, hr = V(0.05, 0.02, lift + 0.12), (0.9, -1.8)
    else:
        hp, hr = V(0, 0.06, lift + 0.12), (0.0, 0.0)
    h = [tube("pc_neck", [V(0, 0, 0), V(0, 0.02, 0.08), V(0, 0.035, 0.13)], [0.026, 0.02, 0.016], 6, b, seed=42),
         hull("pc_head", [V(0.02, 0.02, 0.13), V(-0.02, 0.02, 0.13), V(0, 0.07, 0.13), V(0, 0.03, 0.16), V(0, 0.01, 0.115)], b, 43),
         hull("pc_beak", [V(0.005, 0.06, 0.13), V(-0.005, 0.06, 0.13), V(0, 0.09, 0.125), V(0, 0.06, 0.137)], M("cream"), 44)]
    for i in range(3):   # 冠の羽
        h.append(tube("pc_crest", [V(0, 0.03, 0.155), V((i - 1) * 0.012, 0.02, 0.19)], [0.002, 0.002], 4, b, flat=False))
        h.append(sphere("pc_crest_tip", V((i - 1) * 0.012, 0.02, 0.192), 0.005, g, seg=8))
    for sd in (1, -1):
        h.append(eye_shut("pc_eye", V(sd * 0.018, 0.045, 0.14), 0.012, sd) if pose == "sleep" else eye_dot("pc_eye", V(sd * 0.018, 0.045, 0.14), 0.004))
    it.add("head", moved(h, Matrix.Translation(hp) @ Matrix.Rotation(hr[1], 4, "Z") @ Matrix.Rotation(hr[0], 4, "X")), tuple(hp))
    # 羽（しっぽ）: 座ると扇に広げる。目玉の柄の札を並べる
    tail = []
    fan = pose == "sit"
    n = 11 if fan else 7
    for i in range(n):
        if fan:
            a = math.radians(-80 + 160 * i / (n - 1))
            d = V(math.sin(a), -0.35, math.cos(a)).normalized()
            ln = 0.34
        else:
            a = (i - (n - 1) / 2) * 0.06
            d = V(math.sin(a), -1.0, 0.12 if pose == "walk" else 0.0).normalized()
            ln = 0.36
        base = V(0, -0.07, lift + 0.06)
        side = d.cross(V(0, 1, 0) if fan else V(0, 0, 1)).normalized()
        tip = base + d * ln
        tail.append(quad("pc_feather", base + side * 0.008, base - side * 0.008, tip - side * 0.035, tip + side * 0.035, g if i % 2 else b, 0.003, 50 + i))
        nrm = side.cross(d).normalized()
        for k, (m, r) in enumerate(((eo, 0.026), (eb, 0.014))):
            tail.append(cyl("pc_eye", tuple(tip - d * 0.03 + nrm * (0.003 + 0.002 * k)), r, 0.004, m, tuple(V(0, 0, 1).rotation_difference(nrm).to_euler()), 12, False))
    it.add("tail", tail, (0, -0.07, lift + 0.06))
    for sd in (1, -1):
        nm = "l" if sd > 0 else "r"
        if pose != "sleep":
            it.add("leg_" + nm, tube("pc_leg", [V(sd * 0.025, 0.0, lift + 0.02), V(sd * 0.03, 0.01, 0.0)], [0.007, 0.006], 5, M("acorn_cap"), flat=False), (sd * 0.025, 0, lift + 0.02))
    return it


def m_yarn(pose):
    """B7 毛糸玉（ボードにはない。Lodge の手芸の素材から）。転がってついてきて、ほどけた糸を引く。寝ると糸の端を丸めて止まる"""
    it = Item("yarn_" + pose)
    r = 0.11
    ball = sphere("yb_ball", V(0, 0, r), r, M("yarn_red"), seg=24)
    it.add("body", ball, (0, 0, r))
    if pose == "walk":
        pts = [V(0.0, -r * 0.6, 0.02 + r * 0.2)] + [V(0.03 * math.sin(i * 1.3), -r - 0.06 * i, 0.006) for i in range(1, 7)]
    elif pose == "sit":
        pts = [V(r * 0.9, 0.0, r)] + [V(r + 0.02 + 0.015 * i, 0.03 * math.sin(i), max(0.006, r - 0.03 * i)) for i in range(1, 5)]
    else:
        pts = [V(r * 0.9, 0.0, r * 0.5)] + [V(r + 0.06 * math.cos(i * 0.9) * (1 - i / 9), 0.06 * math.sin(i * 0.9) * (1 - i / 9), 0.006) for i in range(1, 9)]
    it.add("tail", tube("yb_thread", pts, [0.006] * len(pts), 5, M("yarn_red"), flat=False), tuple(pts[0]))
    # 刺した編み針 2 本（顔の代わりの目印）。転がるときは針を抜いて、雪に刺さらないように
    for sd in ((1, -1) if pose != "walk" else ()):
        it.add("body", tube("yb_needle", [V(sd * 0.03, 0.02, r * 1.6), V(sd * 0.06, 0.05, r * 2.35)], [0.005, 0.004], 6, M("wood_btn"), flat=False))
        it.add("body", sphere("yb_knob", V(sd * 0.06, 0.05, r * 2.37), 0.009, M("brass"), seg=10))
    return it


PET = [  # [作る関数, 名前, 値段, ボードの絵]
    (lambda p: m_fox(p, "fox", "kit"), "折り紙の子狐", 0, "橙の折り紙の狐"),
    (m_frog, "跳ねるカエル", 40, "動く折り紙のカエル"),
    (m_rabbit, "白い兎", 80, "月の兎"),
    (m_yarn, "毛糸玉", 120, "（ボードにはない）"),
    (lambda p: m_fox(p, "chiyo_sakura", "chiyo_fox"), "千代紙の狐", 300, "千代紙の狐"),
    (m_pony, "フェルトのポニー", 800, "フェルトの馬"),
    (m_peacock, "孔雀", 1500, "孔雀"),
]


# ================================================================ 撮る
def font():
    base = os.path.dirname(bpy.app.binary_path) + "/../Resources"
    for ver in os.listdir(base):
        p = os.path.join(base, ver, "datafiles", "fonts", "Noto Sans CJK Regular.woff2")
        if os.path.exists(p):
            return bpy.data.fonts.load(p)
    return None


FONT = font()


def label(text, at, size, color="2B211C"):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = text
    cu.align_x = "CENTER"
    cu.size = size
    if FONT:
        cu.font = FONT
    o = link(bpy.data.objects.new("label", cu))
    o.data.materials.append(glow("ink_" + color, color, 1.0))
    o.location = at
    o.rotation_euler = (math.radians(90), 0, 0)
    return o


def stage(w, h):
    """白い雪の撮影台（曲げた布）と、やわらかい光"""
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
    bg = bpy.context.object
    bg.scale = (w * 3, 1, 1)
    bm = bmesh.new()
    bm.from_mesh(bg.data)
    bm.free()
    verts, faces = [], []
    nx, ny = 4, 30
    for j in range(ny + 1):
        t = j / ny
        y = -1.0 + t * (h + 3.0)
        z = 0.0 if y < h * 0.6 else (y - h * 0.6) ** 2 * 0.6
        for i in range(nx + 1):
            verts.append(V(-w * 1.5 + 3 * w * i / nx, y, z))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    bpy.data.objects.remove(bg)
    st = mesh("stage", verts, faces, plain("snowcloth", "B9AE9C", 0.95), smooth=True)
    wd = bpy.data.worlds.new("w")
    wd.use_nodes = True
    wd.node_tree.nodes["Background"].inputs["Color"].default_value = L.lin("DDE2E6")
    wd.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25
    sc.world = wd

    def area(name, loc, size, energy, color="FFF1DE", tgt=V(0, 0, 0)):
        lt = bpy.data.lights.new(name, "AREA")
        lt.size = size
        lt.energy = energy
        lt.color = L.lin(color)[:3]
        o = link(bpy.data.objects.new(name, lt))
        o.location = loc
        o.rotation_euler = V(0, 0, -1).rotation_difference(tgt - V(*loc)).to_euler()
    area("key", (-w * 0.8, -1.4, 2.4), 2.5, 260 * w, tgt=V(0, h * 0.4, 0))
    area("fill", (w * 0.9, -1.4, 1.0), 4.0, 50 * w, "E8EEF8", V(0, h * 0.4, 0))
    area("rim", (0, h + 1.5, 2.0), 3.0, 120 * w, tgt=V(0, h * 0.4, 0))


def render(path, cam_at, tgt, lens, size, ortho=0.0):
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
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = -0.4
    cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    cam.data.lens = lens
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    sc.camera = cam
    cam.location = cam_at
    d = tgt - cam.location
    cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, math.atan2(d.y, d.x) - math.pi / 2)
    sc.render.filepath = os.path.abspath(path)
    os.makedirs(os.path.dirname(sc.render.filepath), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("wrote", sc.render.filepath)


def price_text(n):
    return "はじめから" if n == 0 else "ボタン %d" % n


PERCH_SCALE = 1.5   # 人形に載せて見える大きさ（ラフの 03 で決めた）


def join_part(name, objs, pivot, scale):
    """部品の物体を 1 つの形にまとめる。厚み（sol）は bmesh で付け、面の明るさの違い（tint）を頂点の色 Col にする。
    pivot が節点の原点（回す支点）になる"""
    bm = bmesh.new()
    mats = []
    for o in objs:
        part = bmesh.new()
        part.from_mesh(o.data)
        tl = part.faces.layers.float.get("tint")
        cl = part.loops.layers.float_color.new("Col")
        for f in part.faces:
            t = f[tl] if tl else 0.5
            v = 0.9 + 0.1 * t
            for lp in f.loops:
                lp[cl] = (v, v, v, 1.0)
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
    if "Col" in me.color_attributes:
        me.color_attributes.active_color = me.color_attributes["Col"]
    ob = link(bpy.data.objects.new(name, me))
    ob.location = pivot * scale
    return ob


def export_glb(path, roots):
    bpy.ops.object.select_all(action="DESELECT")
    for r in roots:
        r.select_set(True)
        for c in r.children_recursive:
            c.select_set(True)
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False)
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color="ACTIVE")
    except TypeError:
        bpy.ops.export_scene.gltf(**kw, export_colors=True)
    print("wrote", path)


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def item_nodes(it, scale, parent=None):
    """品物の部品を、部品ごとの節点にまとめる"""
    bpy.context.view_layer.update()   # 焼いた置き方（bake）を matrix_world に反映してから
    nodes = []
    for part, objs in it.parts.items():
        piv = it.pivots.get(part, V(0, 0, 0))
        ob = join_part(part, objs, piv, scale)
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        if parent is not None:
            ob.parent = parent
        nodes.append(ob)
    return nodes


def perch_key(fn):
    return fn.__name__[2:]


PET_KEYS = ["kit", "frog", "rabbit", "yarn", "chiyo_fox", "pony", "peacock"]


if A.export:
    import json
    out = os.path.abspath(A.export)
    os.makedirs(out, exist_ok=True)
    for fn, name, where, price, ref in PERCH:
        clear_scene()
        it = fn()
        nodes = item_nodes(it, PERCH_SCALE)
        export_glb(os.path.join(out, "perch_%s.glb" % perch_key(fn)), nodes)
    for (fn, name, price, ref), key in zip(PET, PET_KEYS):
        clear_scene()
        roots = []
        for pose in ("walk", "sit", "sleep"):
            e = link(bpy.data.objects.new(pose, None))
            item_nodes(fn(pose), 1.0, e)
            roots.append(e)
        export_glb(os.path.join(out, "pet_%s.glb" % key), roots)
    with open(os.path.join(out, "mats.json"), "w") as f:
        json.dump(MATS, f, ensure_ascii=False, indent=1)
    sys.exit(0)

if A.sheet == "perch":
    cols = 4
    dx, dy = 0.52, 0.66
    for i, (fn, name, where, price, ref) in enumerate(PERCH):
        c, r = i % cols, i // cols
        x = (c - (cols - 1) / 2) * dx
        y = (2 - r) * dy
        it = fn()
        it.place(V(x, y, 0.0), yaw=-28, scale=1.6)
        # 頭・肩を思わせる、低い紙の台
        label("A%d %s" % (i + 1, name), V(x, y - 0.2, 0.002), 0.065)
        label("%s ・ %s" % (where, price_text(price)), V(x, y - 0.27, 0.002), 0.055, "5A4A3A")
        for o in bpy.data.objects:
            if o.name.startswith("label") and o.location.z < 0.01:
                o.rotation_euler = (0, 0, 0)
    stage(1.4, 2.6)
    render(A.out, V(0, -2.4, 3.2), V(0, 0.62, 0.0), 40, (1800, 1500), ortho=2.3)
elif A.sheet == "pet":
    poses = ("walk", "sit", "sleep")
    dx, dy = 0.62, 0.7
    for i, (fn, name, price, ref) in enumerate(PET):
        col = i % 2
        row = i // 2
        for k, p in enumerate(poses):
            x = (col - 0.5) * 1.9 + (k - 1) * 0.55
            y = (3 - row) * 0.95
            it = fn(p)
            it.place(V(x, y, 0.0), yaw=-35)
            label(("歩く", "座る", "寝る")[k], V(x, y - 0.26, 0.002), 0.07, "5A4A3A")
        label("B%d %s ・ %s" % (i + 1, name, price_text(price)), V((col - 0.5) * 1.9, y - 0.4, 0.002), 0.1)
        for o in bpy.data.objects:
            if o.name.startswith("label"):
                o.rotation_euler = (0, 0, 0)
    stage(2.4, 6.0)
    render(A.out, V(0, -3.0, 4.5), V(0, 1.45, 0.0), 40, (1800, 2000), ortho=4.1)
elif A.sheet == "dolls":
    # 7 体の人形（ゲームの glb）に、頭と肩の小物を載せ、足もとにミニオンを座らせる。載せる所は人形ごとに決める
    DOLLS = ["kasa", "origami", "news", "robo", "musha", "ningyo", "golem"]
    SCALE = {"kasa": 1.15, "origami": 1.1, "news": 1.05, "robo": 1.15, "musha": 1.1, "ningyo": 1.1, "golem": 1.35}
    HEAD = {"kasa": (0, 1.372, 0.0), "origami": (0, 1.49, 0.0), "news": (0, 0.955, -0.04), "robo": (0, 0.79, 0.03),
            "musha": (0, 0.745, 0.02), "ningyo": (0, 0.89, 0.02), "golem": (0, 1.235, -0.12)}   # companions.gd の PERCH（glb の座標）
    WEAR = {"kasa": (p_crane, p_blue_bird, 0), "origami": (p_acorn, p_chameleon, 4), "news": (p_chiyo_bird, p_hummingbird, 2),
            "robo": (p_pumpkin, p_phoenix, 1), "musha": (p_maple, p_blue_bird, 3), "ningyo": (p_moon_rabbit, p_hummingbird, 5),
            "golem": (p_squirrel, p_phoenix, 6)}
    dg = bpy.context.evaluated_depsgraph_get()
    for i, k in enumerate(DOLLS):
        x = (i - 3) * 1.05
        before = set(bpy.data.objects.keys())
        bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "..", "..", "game", "person", k + ".glb"))
        new = [bpy.data.objects[n] for n in bpy.data.objects.keys() if n not in before]
        root = [o for o in new if o.parent is None]
        s = SCALE[k]
        for o in root:
            o.location = (x, 0, 0)
            o.scale = (s, s, s)
        bpy.context.view_layer.update()
        hx, hy, hz = HEAD[k]
        head_at = V(x, -hz * s, hy * s)   # glb (y 上・-z 前) → Blender (z 上・+y 前)
        arm = next(o for o in new if o.type == "ARMATURE")
        ua = arm.matrix_world @ arm.data.bones["upper_arm.R"].head_local
        neck = arm.matrix_world @ arm.data.bones["neck"].head_local
        # 肩: 腕の付け根の少し内側を、首の高さから下へ探る（髪や笠のつばの下の、肩の面）
        dg = bpy.context.evaluated_depsgraph_get()
        ox = x + (ua.x - x) * 0.85
        hit, loc, nrm, idx, ob, mx = sc.ray_cast(dg, V(ox, ua.y, neck.z + 0.02), V(0, 0, -1))
        sh_at = loc if hit else V(ox, ua.y, ua.z)
        print("PERCH", k, "head", tuple(round(c, 3) for c in head_at - V(x, 0, 0)), "shoulder", tuple(round(c, 3) for c in sh_at - V(x, 0, 0)))
        hfn, sfn, pet = WEAR[k]
        hfn().place(head_at, yaw=0, scale=1.5)
        sfn().place(sh_at, yaw=0, scale=1.5)
        PET[pet][0]("sit").place(V(x + 0.4, 0.15, 0), yaw=10, scale=1.0)
        label(k, V(x, 0.55, 0.002), 0.08, "5A4A3A")
    for o in bpy.data.objects:
        if o.name.startswith("label"):
            o.rotation_euler = (0, 0, math.pi)
    before = set(bpy.data.objects.keys())
    stage(5.0, 4.0)
    for n in set(bpy.data.objects.keys()) - before:   # 人形は +Y を向くので、撮影台と光を前後に返し、光は人形へ向け直す
        o = bpy.data.objects[n]
        o.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ o.matrix_world
        if o.type == "LIGHT":
            o.rotation_euler = V(0, 0, -1).rotation_difference(V(0, 0, 0.7) - o.location).to_euler()
    floor = mesh("floor", [V(-20, -3, 0), V(20, -3, 0), V(20, 20, 0), V(-20, 20, 0)], [(0, 1, 2, 3)], plain("snowcloth", "B9AE9C", 0.95))
    floor.location.z = -0.001
    sun = link(bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(8)
    sun.data.color = L.lin("FFF1DE")[:3]
    sun.rotation_euler = V(0, 0, -1).rotation_difference(V(0.5, -1.0, -0.9)).to_euler()
    render(A.out, V(-1.4, 7.0, 2.4), V(0, 0, 0.75), 50, (2400, 1150), ortho=7.8)
