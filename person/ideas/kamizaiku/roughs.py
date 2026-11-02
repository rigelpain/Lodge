"""紙細工屋さん（腰に提げる紙の提灯と、頭・肩に載せる紙の小物を売る人）のラフ。
代表の Pinterest のボード「&wind：Lodge キャラ」のうち、まだほかのキャラに使っていない人の作品の意匠を取り、Lodge の素材で描く。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/kamizaiku/roughs.py -- --size 3000x1250
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/kamizaiku/roughs.py -- --lineup --size 3400x1100

5 案を、それぞれの売り場と一緒に雪の上に並べる（カメラは +Y から。絵の左から A〜E）:
  A  笠の紙衣の行商   ボードの「笠をかぶった折り紙の男（クラフト紙の着物）」から。背負子に提灯と小物を吊るす
  B  灯る裾の人       ボードの「灯る紙の裾の踊り手」から。裾そのものが提灯（木の骨と和紙）。竿に吊るす
  C  絵付けの円錐の人 ボードの「絵付けした紙の円錐の人たち」から。紙の屋根の屋台
  D  黒い折り紙の婦人 ボードの「黒い折り紙の上衣と花柄の裾の婦人」から。ひな壇の棚
  E  星のマントの子   ボードの「新聞紙の王子（星のマント、もんだ紙の髪）」から。開いた紙の行李を台に
--lineup  5 案（売り場なし）を、人形 3 体・おじいさん・山男・雪だるまと同じ大きさで並べる

部品と紙の素材は person/ideas/characters/roughs.py の「形の道具」までを読んで使う（ファイルは書き換えない）。
顔は折り紙の多面体に黒い糸の閉じた目か、参考どおり目なし（光る目・頬・口は描かない）。前は +Y。
寸法はラフの大きさ（背 1.3 m ほど）で組み、ゲームでは山男・おじいさんと同じく 1.3 倍にする。
"""
import argparse
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
IDEAS = os.path.dirname(HERE)
ROOT = os.path.normpath(os.path.join(IDEAS, "..", ".."))
SRC = os.path.join(IDEAS, "characters", "roughs.py")
OUT = os.path.join(HERE, "renders")

ap = argparse.ArgumentParser()
ap.add_argument("--size", default="3000x1250")
ap.add_argument("--samples", type=int, default=48)
ap.add_argument("--turn", type=float, default=0.0)
ap.add_argument("--views", default="front,quarter")
ap.add_argument("--lineup", action="store_true")
ap.add_argument("--close", action="store_true", help="婦人の頭の寄り")
ap.add_argument("--counter", action="store_true", help="婦人のカウンターの案")
ap.add_argument("--tiers", action="store_true", help="大きな段のスタンドの売り場")
ap.add_argument("--export", default="", help="ゲーム用の glb をこのフォルダーに書き出す（例: game/props/paper_lady）")
ap.add_argument("--what", default="lady", choices=("lady", "stand"), help="--export で書き出す物（1 回に 1 つ）")
ap.add_argument("--only", default="", help="A〜E のうち描く案（確かめ用）")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

GAME_SCALE = 1.3


def borrow(path, cut, extra=None):
    """ほかのラフの台本から、組み立てより前（素材と形の道具）だけを読む"""
    src = open(path, encoding="utf-8").read()
    ns = {"__file__": path, "__name__": "borrowed"}
    argv = sys.argv
    sys.argv = ["blender"]
    try:
        exec(compile(src[:src.index(cut)], path, "exec"), ns)
    finally:
        sys.argv = argv
    return ns


_ns = borrow(SRC, "def build_robo")
C, V, part, blob, ball, rope, ribbon, hit, facet_ball, sheet_cone, paper, register_paper, Mat, fiber_bump, np_image, lin = (
    _ns[k] for k in ("C", "V", "part", "blob", "ball", "rope", "ribbon", "hit", "facet_ball", "sheet_cone", "paper",
                     "register_paper", "Mat", "fiber_bump", "np_image", "lin"))


# ================================================================ 紙の柄（コードで描く）
def _rgb(h):
    return np.array(lin(h)[:3])


def swirl_image(px=512, seed=5):
    """絵付けの紙: 大きく波打つ色の帯に、墨の渦と葉"""
    rnd = np.random.default_rng(seed)
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    band = (x * 1.4 + y * 0.6 + 0.12 * np.sin(y * 2 * np.pi * 2) + 0.08 * np.sin(x * 2 * np.pi * 3)) % 1
    pal = [_rgb(h) for h in ("D9762B", "2E6B6E", "D9A83A", "B8442E", "EFE3C8")]
    idx = np.minimum((band * 5).astype(int), 4)
    img = np.zeros((px, px, 3))
    for k, c in enumerate(pal):
        img[idx == k] = c
    ink = _rgb("2A2624")
    cream = _rgb("EFE3C8")
    for _ in range(9):
        cx, cy, R = rnd.uniform(0, 1), rnd.uniform(0, 1), rnd.uniform(0.06, 0.12)
        dx = ((x - cx + 0.5) % 1) - 0.5
        dy = ((y - cy + 0.5) % 1) - 0.5
        r = np.hypot(dx, dy)
        th = np.arctan2(dy, dx) / (2 * np.pi)
        sp = ((th + r / R * 3.0) % 1 < 0.22) & (r < R)
        img[r < R * 1.05] = cream
        img[sp] = ink
    return np_image("swirl", img)


def flower_image(px=1024, seed=11):
    """参考の婦人の上がけの柄: 墨のクレープ地に、金の小花の房（輪の小花と細い枝）と、朱の大きな牡丹（重ねた花びらの輪郭）"""
    rnd = np.random.default_rng(seed)
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    img = np.zeros((px, px, 3)) + _rgb("3A3A40")
    gold, red, red_dk = _rgb("A68B5B"), _rgb("C25A4C"), _rgb("9C4038")

    def d(cx, cy):
        return ((x - cx + 0.5) % 1) - 0.5, ((y - cy + 0.5) % 1) - 0.5
    for _ in range(9):   # 朱の牡丹
        cx, cy, R = rnd.uniform(0, 1), rnd.uniform(0, 1), rnd.uniform(0.05, 0.09)
        dx, dy = d(cx, cy)
        r = np.hypot(dx, dy)
        th = np.arctan2(dy, dx)
        edge = R * (0.86 + 0.14 * np.abs(np.cos(3.5 * th)))
        img[r < edge] = red
        for k in (0.75, 0.5, 0.28):   # 花びらの重なりの線
            ring = np.abs(r - edge * k * (0.92 + 0.08 * np.cos(5 * th + k * 9))) < 0.0035
            img[ring & (r < edge)] = red_dk
    for _ in range(16):   # 金の小花の房
        cx, cy, R = rnd.uniform(0, 1), rnd.uniform(0, 1), rnd.uniform(0.05, 0.09)
        for _ in range(int(R * 420)):
            a, rr = rnd.uniform(0, 2 * np.pi), R * np.sqrt(rnd.uniform(0, 1))
            dx, dy = d(cx + np.cos(a) * rr, cy + np.sin(a) * rr)
            r = np.hypot(dx, dy)
            f = rnd.uniform(0.005, 0.01)
            img[(np.abs(r - f) < 0.0022)] = gold
        for _ in range(3):   # 細い枝
            a = rnd.uniform(0, 2 * np.pi)
            dx, dy = d(cx, cy)
            t = dx * np.cos(a) + dy * np.sin(a)
            n = -dx * np.sin(a) + dy * np.cos(a)
            img[(np.abs(n - 0.04 * t * t / R) < 0.0018) & (t > 0) & (t < R * 1.5)] = gold
    return np_image("flowers", img)


def star_image(px=512, seed=3):
    """紺の紙に小さな星"""
    rnd = np.random.default_rng(seed)
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / px
    img = np.zeros((px, px, 3)) + _rgb("22305E")
    for _ in range(60):
        cx, cy, R = rnd.uniform(0, 1), rnd.uniform(0, 1), rnd.uniform(0.008, 0.022)
        dx = ((x - cx + 0.5) % 1) - 0.5
        dy = ((y - cy + 0.5) % 1) - 0.5
        r = np.hypot(dx, dy)
        th = np.arctan2(dy, dx) + rnd.uniform(0, 1)
        img[r < R * (0.45 + 0.55 * np.abs(np.cos(2.5 * th)) ** 3)] = _rgb("EDE0B8")
    return np_image("stars", img)


def print_paper(name, image, scale, back="F1E6D2", fiber=0.18):
    """柄を刷った紙: 表は柄、裏は白。繊維の凹凸"""
    M = Mat(name)
    tex = M.n("ShaderNodeTexImage", projection="BOX", projection_blend=0.3)
    tex.image = image
    co = M.obj_coords(scale)
    M.l(co, 0, tex, "Vector")
    bf = M.n("ShaderNodeNewGeometry")
    M.l(M.mix((bf, "Backfacing"), (tex, "Color"), lin(back)), 2, M.b, "Base Color")
    M.l(fiber_bump(M, M.obj_coords(1.0), fiber), 0, M.b, "Normal")
    M.b.inputs["Roughness"].default_value = 0.84
    M.b.inputs["Specular IOR Level"].default_value = 0.25
    return M.m


def glow_paper(name, color, strength=2.4):
    """中に灯の入った和紙: 繊維が透けて、紙の色に光る"""
    m = paper(name, color, back=color, fiber=0.5, crinkle=0.08, sss=0.2)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Emission Color"].default_value = lin(color)
    b.inputs["Emission Strength"].default_value = strength
    return m


def roles():
    register_paper()
    C.HEX.update({"wood_dark": "5A3F2C"})
    C._MAT.update({
        "kraft_dark": paper("kraft_dark", "7A5636", back="A88A66", fiber=0.22, crinkle=0.3),
        "kraft_crumple": paper("kraft_crumple", "C49C6C", back="DCC4A0", fiber=0.25, crinkle=0.6),
        "washi_white": paper("washi_white", "EEE8DC", back="F6F2EA", fiber=0.55, crinkle=0.12, sss=0.18),
        "washi_ochre": paper("washi_ochre", "C99A4A", back="E8D8B0", fiber=0.5, crinkle=0.25, sss=0.12),
        "washi_rust": paper("washi_rust", "A8553A", back="E2C8B0", fiber=0.5, crinkle=0.25, sss=0.12),
        "washi_teal": paper("washi_teal", "2E6B6E", back="D0DAD4", fiber=0.45, crinkle=0.1, sss=0.08),
        "washi_blue": paper("washi_blue", "6E9CC8", back="E8EEF2", fiber=0.4, crinkle=0.05, sss=0.1),
        "washi_pink": paper("washi_pink", "E6B4B0", back="F4E8E4", fiber=0.4, crinkle=0.05, sss=0.1),
        "washi_red": paper("washi_red", "C0443A", back="F0D8CC", fiber=0.4, crinkle=0.05, sss=0.1),
        "sumi_red": paper("sumi_red", "24211F", back="A8382E", fiber=0.3, crinkle=0.05),   # 表は墨、裏は朱の紙
        "sumi": paper("sumi", "24211F", back="3A3532", fiber=0.3, crinkle=0.08),
        "hair_black": paper("hair_black", "1E1B1A", back="2E2A28", rough=0.6, fiber=0.2),
        "crepe": paper("crepe", "3A3A40", back="4A4A50", rough=0.75, fiber=0.6, crinkle=0.04),   # 婦人の墨のクレープ紙
        "crepe_lt": paper("crepe_lt", "46464D", back="55555C", rough=0.75, fiber=0.6, crinkle=0.04),
        "hair_char": paper("hair_char", "3A393E", back="4A484C", rough=0.7, fiber=0.6, crinkle=0.05),   # 炭の灰のクレープ紙
        "swirl": print_paper("swirl", swirl_image(), 2.2),
        "flowers": print_paper("flowers", flower_image(), 1.3, back="4A4A50", fiber=0.5),
        "stars": print_paper("stars", star_image(), 1.8, back="D8D0BC"),
        "glow_amber": glow_paper("glow_amber", "F0B65A", 2.6),
        "glow_orange": glow_paper("glow_orange", "E0622A", 2.2),
        "glow_red": glow_paper("glow_red", "D9533A", 2.0),
        "glow_cream": glow_paper("glow_cream", "F4E2B8", 2.4),
    })


def thread_eyes(head, hc, dx=0.03, dz=0.0, w=0.012):
    """黒い糸の閉じた目（下に弧を描く 3 点の糸）"""
    for s in (1, -1):
        p, n = hit(head, hc + V(s * dx, 0.6, dz), V(0, -1, 0))
        rope("eye", "thread_ink", [p + V(-w, 0, 0.002) + n * 0.002, p + V(0, 0, -0.004) + n * 0.003, p + V(w, 0, 0.002) + n * 0.002], r=0.003, sides=6)


# ================================================================ 売り物: 紙の提灯・折り紙の小鳥・どんぐり
def chochin(at, r=0.07, h=0.15, glow="glow_amber", cap="wood_dark", string=0.06, sides=10):
    """腰に提げる紙の提灯: 胴（光る和紙）を細い骨の輪で区切り、上下に木の口輪。at は提げ紐の上の端"""
    top = at - V(0, 0, string)
    rope("chochin_string", "hemp", [at, top], r=0.0025, sides=5)
    z0, z1 = top.z - h, top.z
    prof = []
    for k in range(9):
        t = k / 8
        prof.append((r * (0.55 + 0.45 * math.sin(math.pi * t)), z0 + h * t))
    m = C.M("chochin", glow, "doll")
    rings = C.lathe(m, prof, segs=sides, closed=True)
    _ = rings
    o = m.done(smooth=False)
    o.location = (top.x, top.y, 0)
    for k in range(1, 8, 2):   # 骨の輪
        rr, zz = prof[k]
        rope("chochin_rib", "wood_dark", [V(top.x + math.cos(a) * rr * 1.02, top.y + math.sin(a) * rr * 1.02, zz)
                                         for a in [2 * math.pi * i / sides for i in range(sides + 1)]], r=0.0022, sides=4)
    for zz, rr in ((z1, r * 0.6), (z0, r * 0.6)):
        part("chochin_cap", cap, lambda m, zz=zz, rr=rr: C.tube(m, [V(top.x, top.y, zz - 0.01), V(top.x, top.y, zz + 0.01)], rr, sides=sides), smooth=False)
    return o


def ori_bird(at, s=1.0, role="washi_blue", wing="washi_pink", yaw=0.0):
    """折り紙の小鳥（ボードの小鳥と同じ: 面の少ない体、立てた三角の翼、尾）。at は足もと"""
    ca, sa = math.cos(yaw), math.sin(yaw)

    def R(v):
        return at + V(v.x * ca - v.y * sa, v.x * sa + v.y * ca, v.z) * s
    part("bird", role, lambda m: facet_ball(m, R(V(0, 0, 0.035)), (0.035 * s, 0.05 * s, 0.032 * s), 6, 4, 0.002, 7), smooth=False)
    part("bird_head", role, lambda m: facet_ball(m, R(V(0, 0.045, 0.062)), (0.022 * s, 0.022 * s, 0.022 * s), 5, 4, 0.0, 8), smooth=False)

    def tri(m, pts):
        vs = [m.bm.verts.new(R(p)) for p in pts]
        m.bm.faces.new(vs)
    part("bird_beak", "washi_ochre", lambda m: tri(m, [V(-0.006, 0.062, 0.066), V(0.006, 0.062, 0.066), V(0, 0.08, 0.06)]), smooth=False)
    part("bird_tail", role, lambda m: tri(m, [V(-0.012, -0.04, 0.04), V(0.012, -0.04, 0.04), V(0, -0.085, 0.075)]), smooth=False, solid=0.002)
    for k in (1, -1):
        part("bird_wing", wing, lambda m, k=k: tri(m, [V(0.02 * k, 0.025, 0.05), V(0.02 * k, -0.025, 0.045), V(0.055 * k, -0.035, 0.1)]), smooth=False, solid=0.002)


def acorn(at, s=1.0):
    """紙のどんぐり（ボードのペーパークラフトと同じ: 面の少ない生成りの実と、焦げ茶の帽子と軸）。at は底"""
    part("acorn", "washi_white", lambda m: facet_ball(m, at + V(0, 0, 0.04 * s), (0.032 * s, 0.032 * s, 0.042 * s), 8, 5, 0.0, 3), smooth=False)
    part("acorn_cap", "kraft_dark", lambda m: facet_ball(m, at + V(0, 0, 0.068 * s), (0.036 * s, 0.036 * s, 0.022 * s), 8, 4, 0.0, 4), smooth=False)
    rope("acorn_stem", "kraft_dark", [at + V(0, 0, 0.085 * s), at + V(0.004, 0, 0.1 * s)], r=0.005 * s, sides=5)


def hang(at, L, fn, *a, **kw):
    """糸で吊るす（小鳥・どんぐり）"""
    rope("hang", "thread_cream", [at, at - V(0, 0, L)], r=0.0016, sides=4)
    fn(at - V(0, 0, L + 0.1 * kw.get("s", 1.0)), *a, **kw)


GLOWS = ["glow_amber", "glow_red", "glow_cream", "glow_orange"]


# ================================================================ A 笠の紙衣の行商
def build_a(stall=True):
    """参考: 笠をかぶった折り紙の男（クラフト紙を折った着物、しわの残る紙、大きな笠で顔が陰になる）。
    取る: 放射に山と谷を折ったクラフト紙の大きな笠、面の少ない着物と幅広の袖、生成りの衿、帯。紙のしわ。
    売り場（吊るし・行商）: 木の背負子を背負い、横へ張り出した竿から提灯を、てっぺんの段に小鳥とどんぐりを載せる
    取らない: 刀"""
    for s in (1, -1):
        part("geta", "wood_dark", lambda m, s=s: facet_ball(m, V(0.09 * s, 0.04, 0.04), (0.06, 0.1, 0.04), 6, 4, 0.004, 1 + s), smooth=False)

    def coat(m):
        sheet_cone(m, [(0.16, 1.0), (0.2, 0.82), (0.25, 0.5), (0.3, 0.1)], n=10, sy=0.78)
    part("kimono", "kraft_crumple", coat, smooth=False, solid=0.008)
    part("kimono_top", "kraft_crumple", lambda m: facet_ball(m, V(0, 0, 0.99), (0.17, 0.13, 0.05), 10, 4, 0.0, 2), smooth=False)
    for k, (a, b) in enumerate(((V(0.1, 0.11, 0.99), V(-0.07, 0.21, 0.62)), (V(-0.1, 0.11, 0.99), V(-0.02, 0.17, 0.84)))):
        m_c = C.M("collar", "washi", "doll")
        ribbon(m_c, [a, (a + b) / 2 + V(0, 0.02, 0), b], 0.055, [V(1, 0, 0.35 if k == 0 else -0.35)] * 3)
        m_c.done(smooth=False).modifiers.new("sol", "SOLIDIFY").thickness = 0.005
    rope("obi", "washi_rust", [V(math.cos(a) * 0.235, math.sin(a) * 0.185, 0.6) for a in [2 * math.pi * k / 12 for k in range(13)]], r=0.035, sides=4)
    for s in (1, -1):   # 幅広の袖: 肩から下がる大きな紙の板
        m_s = C.M("sleeve", "kraft_crumple", "doll")
        ribbon(m_s, [V(0.17 * s, 0.0, 0.97), V(0.27 * s, 0.03, 0.8), V(0.29 * s, 0.06, 0.58)], 0.2, [V(0, 1, 0)] * 3, cols=2)
        m_s.done(smooth=False).modifiers.new("sol", "SOLIDIFY").thickness = 0.006
        rope("arm", "kraft_crumple", [V(0.15 * s, 0.0, 0.96), V(0.24 * s, 0.05, 0.8), V(0.22 * s, 0.11, 0.69)], r=0.055, sides=5)
        part("hand", "ori_face", lambda m, s=s: facet_ball(m, V(0.22 * s, 0.13, 0.66), (0.035, 0.035, 0.04), 6, 4, 0.003, 5 + s), smooth=False)
    hc = V(0, 0.03, 1.1)
    head = part("face", "ori_face", lambda m: facet_ball(m, hc, (0.08, 0.075, 0.09), 8, 6, 0.004, 9), smooth=False)
    thread_eyes(head, hc, 0.028, -0.01, 0.011)

    def kasa(m):   # 16 枚の山谷折り: 山の稜線と谷を交互に、高さを変える
        n = 16
        apex = m.bm.verts.new((0, 0, 1.36))
        rim = []
        for i in range(n):
            a = 2 * math.pi * i / n
            rr = 0.38 if i % 2 == 0 else 0.36
            zz = 1.135 if i % 2 == 0 else 1.15
            rim.append(m.bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, zz)))
        for i in range(n):
            m.bm.faces.new((apex, rim[i], rim[(i + 1) % n]))
    part("kasa", "kraft", kasa, smooth=False, solid=0.006)
    rope("kasa_tie", "hemp", [hc + V(0.07, 0.0, 0.07), hc + V(0.05, 0.05, -0.06), hc + V(0, 0.07, -0.1), hc + V(-0.05, 0.05, -0.06), hc + V(-0.07, 0, 0.07)], r=0.004)
    if not stall:
        return 1.36
    # 背負子: 2 本の柱と横木。いちばん上の横木は左右へ長く張り出して、提灯を提げる
    y = -0.27
    for s in (1, -1):
        rope("frame", "wood_dark", [V(0.15 * s, y, 0.3), V(0.15 * s, y - 0.02, 1.62)], r=0.016, sides=6)
        rope("strap", "hemp", [V(0.12 * s, -0.12, 1.0), V(0.13 * s, 0.1, 0.96), V(0.14 * s, 0.14, 0.72), V(0.15 * s, -0.2, 0.5)], r=0.009)
    for z in (0.45, 0.9):
        rope("frame_bar", "wood_dark", [V(-0.17, y, z), V(0.17, y, z)], r=0.012, sides=6)
    rope("frame_arm", "wood_dark", [V(-0.62, y - 0.02, 1.5), V(0.62, y - 0.02, 1.5)], r=0.013, sides=6)
    part("frame_shelf", "wood", lambda m: C.tube(m, [V(-0.17, y - 0.02, 1.6), V(0.17, y - 0.02, 1.6)], 0.06, sides=8, ry=0.008, sq=8.0), smooth=False)
    for k, x in enumerate((-0.58, -0.4, -0.23, 0.23, 0.4, 0.58)):
        chochin(V(x, y - 0.02, 1.5), r=0.055 + 0.01 * (k % 2), h=0.12 + 0.02 * (k % 3), glow=GLOWS[k % 4], string=0.04 + 0.05 * (k % 2))
    ori_bird(V(-0.08, y - 0.02, 1.61), 0.9, "washi_blue", "washi_pink", yaw=0.4)
    acorn(V(0.1, y - 0.02, 1.61), 0.9)
    hang(V(0.12, y - 0.03, 0.9), 0.05, acorn, s=0.8)
    hang(V(-0.1, y - 0.03, 0.9), 0.04, ori_bird, 0.8, "washi_red", "washi_white", yaw=0.0)
    return 1.36


# ================================================================ B 灯る裾の人
def build_b(stall=True):
    """参考: 灯る紙の裾の踊り手（墨色のとんがり笠、墨の上衣に角ばった袖、裾は内から灯る朱と橙の紙のひだ）。
    取る: 墨の笠、表が墨で裏が朱の紙の袖（角が立つ）、裾を提灯の骨（木の細い輪）と和紙にして中から灯す。
    売り場（吊るし）: 木の柱 2 本に竿を渡し、色違いの提灯を提げ、竿に小鳥とどんぐり
    取らない: 踊りの姿勢（立って売る）、長い黒髪のなびき"""
    def skirt(m):
        sheet_cone(m, [(0.11, 0.76), (0.2, 0.62), (0.29, 0.42), (0.34, 0.22), (0.35, 0.06)], n=14, sy=0.9)
    part("skirt", "glow_orange", skirt, smooth=False, solid=0.004)
    for zz, rr in ((0.62, 0.2), (0.52, 0.25), (0.42, 0.29), (0.32, 0.32), (0.22, 0.34), (0.06, 0.35)):
        rope("skirt_rib", "wood_dark", [V(math.cos(a) * (rr + 0.004), math.sin(a) * (rr + 0.004) * 0.9, zz)
                                        for a in [2 * math.pi * i / 14 for i in range(15)]], r=0.0045, sides=4)
    m_p = C.M("front_panel", "sumi", "doll")   # 前の墨の板（参考の黒い差し）
    ribbon(m_p, [V(0, 0.112, 0.76), V(0, 0.19, 0.62), V(0, 0.272, 0.42), V(0, 0.316, 0.22), V(0, 0.325, 0.06)], 0.09, [V(1, 0, 0)] * 5)
    m_p.done(smooth=False).modifiers.new("sol", "SOLIDIFY").thickness = 0.004
    part("bodice", "sumi", lambda m: facet_ball(m, V(0, 0, 0.88), (0.12, 0.09, 0.15), 7, 5, 0.003, 21), smooth=False)
    part("waist", "sumi_red", lambda m: C.tube(m, [V(0, 0, 0.74), V(0, 0, 0.79)], 0.115, sides=10, ry=0.105), smooth=False)
    for s in (1, -1):   # 角ばった袖: 肩から外へ張り、先が三角に垂れる
        m_s = C.M("sleeve", "sumi_red", "doll")
        ribbon(m_s, [V(0.1 * s, 0.0, 0.98), V(0.2 * s, 0.03, 0.88), V(0.26 * s, 0.05, 0.66)], 0.17, [V(1, 0.15 * s, -0.25 * s)] * 3, cols=2, notch=0.06)
        m_s.done(smooth=False).modifiers.new("sol", "SOLIDIFY").thickness = 0.005
        part("hand", "ori_face", lambda m, s=s: facet_ball(m, V(0.13 * s, 0.13, 0.78), (0.032, 0.032, 0.038), 6, 4, 0.003, 22 + s), smooth=False)
        rope("arm", "sumi", [V(0.12 * s, 0.02, 0.96), V(0.17 * s, 0.07, 0.86), V(0.13 * s, 0.12, 0.8)], r=0.03, sides=5)
    chochin(V(0.13, 0.15, 0.76), r=0.05, h=0.1, glow="glow_red", string=0.03)   # 両手で提げた小さな提灯
    rope("neck", "ori_face", [V(0, 0, 1.0), V(0, 0.01, 1.06)], r=0.028, sides=6)
    hc = V(0, 0.02, 1.12)
    head = part("face", "ori_face", lambda m: facet_ball(m, hc, (0.075, 0.07, 0.085), 8, 6, 0.004, 24), smooth=False)
    thread_eyes(head, hc, 0.026, -0.015, 0.01)
    part("hair", "hair_black", lambda m: facet_ball(m, hc + V(0, -0.025, -0.01), (0.088, 0.075, 0.1), 7, 5, 0.004, 25), smooth=False)

    def hat(m):
        sheet_cone(m, [(0.0, 1.34), (0.16, 1.23), (0.33, 1.14)], n=12, sy=1.0)
    part("hat", "sumi", hat, smooth=False, solid=0.006)
    if not stall:
        return 1.34
    # 竿の吊るし: 柱 2 本（人のうしろ左）、竿、提灯 5 つ、竿の上に小鳥
    x0, x1, y = 0.95, 0.25, -0.45
    for x in (x0, x1):
        rope("pole", "wood_dark", [V(x, y, 0.0), V(x, y, 1.75)], r=0.02, sides=6)
        part("pole_foot", "wood_dark", lambda m, x=x: facet_ball(m, V(x, y, 0.03), (0.07, 0.07, 0.04), 6, 3, 0.0, 26), smooth=False)
    rope("bar", "wood_dark", [V(x0 + 0.06, y, 1.7), V(x1 - 0.06, y, 1.7)], r=0.014, sides=6)
    for k in range(5):
        x = x0 - 0.06 - (x0 - x1 - 0.12) * k / 4
        chochin(V(x, y, 1.69), r=0.05 + 0.012 * ((k + 1) % 3), h=0.11 + 0.03 * (k % 2), glow=GLOWS[k % 4], string=0.1 + 0.12 * (k % 2))
    ori_bird(V(0.62, y, 1.712), 0.9, "washi_white", "washi_blue", yaw=0.5)
    hang(V(0.52, y, 1.69), 0.42, acorn, s=0.9)
    return 1.34


# ================================================================ C 絵付けの円錐の人
def build_c(stall=True):
    """参考: 絵付けした紙の円錐の人たち（細長い円錐の衣に、大きな渦と葉の絵、小さな頭と細い首、髪はまとめて後ろへ）。
    取る: 高い円錐の衣（絵付けの紙）、細い首、小さな頭と黄土の紙の髪の結い、墨の細い腕。
    売り場（屋台）: 木の柱 4 本に紙の屋根、軒に提灯、台に小鳥とどんぐり
    取らない: 細すぎる人の体つき（立てるように円錐を太めに）"""
    def cone(m):
        sheet_cone(m, [(0.05, 1.0), (0.12, 0.8), (0.22, 0.45), (0.3, 0.05)], n=16, sy=0.9)
    part("cone", "swirl", cone, smooth=False, solid=0.005)
    part("cone_top", "swirl", lambda m: facet_ball(m, V(0, 0, 1.0), (0.055, 0.05, 0.02), 8, 3, 0.0, 31), smooth=False)
    rope("neck", "ori_face", [V(0, 0, 1.0), V(0, 0.005, 1.1)], r=0.022, sides=6)
    hc = V(0, 0.01, 1.16)
    head = part("face", "ori_face", lambda m: facet_ball(m, hc, (0.06, 0.058, 0.075), 8, 6, 0.003, 32), smooth=False)
    thread_eyes(head, hc, 0.022, -0.01, 0.009)
    part("hair", "washi_ochre", lambda m: facet_ball(m, hc + V(0, -0.02, 0.025), (0.068, 0.065, 0.065), 7, 5, 0.003, 33), smooth=False)
    part("bun", "washi_ochre", lambda m: facet_ball(m, hc + V(0, -0.08, 0.04), (0.04, 0.04, 0.045), 6, 4, 0.003, 34), smooth=False)
    for s in (1, -1):
        rope("arm", "sumi", [V(0.05 * s, 0.0, 0.97), V(0.1 * s, 0.06, 0.8), V(0.06 * s, 0.16, 0.66)], r=0.012, sides=5)
        part("hand", "ori_face", lambda m, s=s: facet_ball(m, V(0.05 * s, 0.17, 0.64), (0.022, 0.022, 0.028), 6, 4, 0.002, 35 + s), smooth=False)
    if not stall:
        return 1.24
    # 屋台: 人のうしろ。台の高さ 0.8、紙の切妻屋根
    cx, cy, w, d = 0.0, -0.6, 1.3, 0.5
    for sx in (1, -1):
        for sy in (1, -1):
            rope("post", "wood_dark", [V(cx + sx * w / 2, cy + sy * d / 2, 0), V(cx + sx * w / 2, cy + sy * d / 2, 1.62)], r=0.018, sides=6)
    part("counter", "wood", lambda m: C.tube(m, [V(cx - w / 2 - 0.05, cy, 0.8), V(cx + w / 2 + 0.05, cy, 0.8)], 0.3, sides=8, ry=0.02, sq=8.0), smooth=False)
    part("counter_cloth", "felt_obi", lambda m: C.tube(m, [V(cx - w / 2, cy + 0.3, 0.6), V(cx + w / 2, cy + 0.3, 0.6)], 0.006, sides=8, ry=0.19, sq=8.0), smooth=False)

    def roof(m):
        L, R = cx - w / 2 - 0.12, cx + w / 2 + 0.12
        ridge = 1.88
        for sy in (1, -1):
            vs = [m.bm.verts.new(p) for p in (V(L, cy, ridge), V(R, cy, ridge), V(R, cy + sy * (d / 2 + 0.2), 1.58), V(L, cy + sy * (d / 2 + 0.2), 1.58))]
            m.bm.faces.new(vs)
    part("roof", "swirl", roof, smooth=False, solid=0.006)
    for k in range(5):
        x = cx - w / 2 + 0.05 + (w - 0.1) * k / 4
        chochin(V(x, cy + d / 2 + 0.2, 1.58), r=0.05 + 0.01 * (k % 2), h=0.12, glow=GLOWS[k % 4], string=0.05 + 0.06 * (k % 2))
    for k, x in enumerate((-0.5, -0.3, -0.1)):
        ori_bird(V(x, cy + 0.05 * (k % 2), 0.82), 1.0, ("washi_blue", "washi_red", "washi_white")[k], ("washi_pink", "washi_ochre", "washi_blue")[k], yaw=0.3 * (k - 1))
    for k, x in enumerate((0.15, 0.3, 0.45)):
        acorn(V(x, cy + 0.04 * (k % 2), 0.82), 1.0)
    return 1.24


# 参考の婦人（着物とドレスを混ぜた紙の人形）。寸法は参考の写真から測った（背 1.3 m に直した高さ z と、横の半分の幅）。
# 頭は小さく（髪まで入れて背の 6 分の 1）、肩は袖山が立ち、胸から細い腰へ締まり、腰から下は大きく広がる。
# 衿まわりと色は着物（朱の内衿の打ち合わせ、墨の広い衿）、袖口と裾の形と量はドレス（ベルの袖口、二段の上がけと前の尖った垂れ）
LADY_SY = 0.8   # 前後のつぶれ
# おかっぱ: (高さ, 横の半分の幅, 前のあきの半分の角度°)。いちばん広いのはあごの少し上、そこから首へすっと締まる
BOB_ROWS = [
    (1.300, 0.015, 0.0), (1.292, 0.06, 0.0), (1.272, 0.094, 0.0), (1.244, 0.116, 4.0), (1.214, 0.128, 16.0),
    (1.184, 0.135, 22.0), (1.154, 0.138, 25.0), (1.126, 0.134, 27.0), (1.102, 0.118, 32.0), (1.086, 0.094, 40.0),
    (1.076, 0.066, 55.0), (1.071, 0.04, 75.0),
]


def bob_hair(n=64):
    """クレープ紙のおかっぱ: まんなかで分け、分け目から外へ流れるひだ（列ごとに少し出し入れした面）"""
    def b(m):
        rows = []
        for z, r, w in BOB_ROWS:
            a0, a1 = math.radians(90 + w), math.radians(90 - w + 360)
            row = []
            for i in range(n + 1):
                a = a0 + (a1 - a0) * i / n
                pl = 1.0 + (0.022 if i % 2 else -0.006) * min(1.0, r / 0.1)
                row.append(m.bm.verts.new(V(math.cos(a) * r * pl, -0.012 + math.sin(a) * r * 0.82 * pl, z)))
            rows.append(row)
        for k in range(len(rows) - 1):
            for i in range(n):
                m.bm.faces.new((rows[k][i], rows[k + 1][i], rows[k + 1][i + 1], rows[k][i + 1]))
    part("bob", "hair_char", b, smooth=False, solid=0.004)


def shield_face():
    """顔: まんなかを山に折った盾の形。目なし、あごが尖る"""
    def b(m):
        top, ridge, chin = V(0, 0.028, 1.228), V(0, 0.08, 1.15), V(0, 0.05, 1.079)
        for s in (1, -1):
            up, lo = V(0.067 * s, 0.03, 1.19), V(0.062 * s, 0.03, 1.12)
            vs = [m.bm.verts.new(p) for p in (top, ridge, up, lo, chin)]
            for f in ((0, 1, 2), (1, 3, 2), (1, 4, 3)):
                m.bm.faces.new([vs[i] for i in (f if s > 0 else tuple(reversed(f)))])
    part("face", "washi", b, smooth=False, solid=0.004)
    part("head", "washi", lambda m: facet_ball(m, V(0, -0.012, 1.16), (0.06, 0.05, 0.07), 8, 6, 0.0, 45), smooth=False)


def ring_shell(name, role, prof, n, sy=LADY_SY, pleat=0.0, lon=None, solid=0.004, gaps=None):
    """輪郭（半径, 高さ）を上から下へ回した紙の殻。pleat で縦のひだ（列ごとに出し入れ）。
    gaps は列ごとの前のあきの半分の角度（度）。上衣の前を V にあける"""
    def b(m):
        rows = []
        for k, (r, z) in enumerate(prof):
            g = gaps[k] if gaps else 0.0
            a0, a1 = (90.0 + g, 450.0 - g) if lon is None else lon
            row = []
            for i in range(n + 1):
                a = math.radians(a0 + (a1 - a0) * i / n)
                pl = 1.0 + (pleat if i % 2 else -pleat * 0.3)
                row.append(m.bm.verts.new(V(math.cos(a) * r * pl, math.sin(a) * r * sy * pl, z)))
            rows.append(row)
        for k in range(len(rows) - 1):
            for i in range(n):
                m.bm.faces.new((rows[k][i], rows[k + 1][i], rows[k + 1][i + 1], rows[k][i + 1]))
    return part(name, role, b, smooth=False, solid=solid)


BODICE = [(0.026, 1.06), (0.06, 1.036), (0.116, 1.012), (0.082, 0.96), (0.078, 0.91), (0.062, 0.86), (0.052, 0.81), (0.056, 0.77)]
BODICE_GAP = [70.0, 46.0, 30.0, 16.0, 1.0, 0.0, 0.0, 0.0]   # 上衣の前の V のあき（度）。中に朱の着物が見える


def bodice_r(z, prof=BODICE):
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        if z1 <= z <= z0:
            return r0 + (r1 - r0) * (z0 - z) / (z0 - z1)
    return prof[-1][0] if z < prof[-1][1] else prof[0][0]


def gap_x(z):
    """上衣の V のふちの横の位置"""
    for (g0, (_, z0)), (g1, (_, z1)) in zip(zip(BODICE_GAP, BODICE), zip(BODICE_GAP[1:], BODICE[1:])):
        if z1 <= z <= z0:
            g = g0 + (g1 - g0) * (z0 - z) / (z0 - z1)
            return bodice_r(z) * math.sin(math.radians(g))
    return 0.0


def on_bodice(x, z, lift=0.004):
    """上衣の表の点（前の面）。BODICE の輪郭を高さで補い、楕円の前の面へ"""
    r = bodice_r(z)
    return V(x, LADY_SY * math.sqrt(max(r * r - x * x, 0.0)) + lift, z)


def surface_panel(name, role, inner, outer, lift):
    """上衣に貼る紙の帯: inner と outer の (x, z) の列を表の面に落として四角でつなぐ"""
    def b(m):
        a = [m.bm.verts.new(on_bodice(x, z, lift)) for x, z in inner]
        c = [m.bm.verts.new(on_bodice(x, z, lift)) for x, z in outer]
        for i in range(len(a) - 1):
            m.bm.faces.new((a[i], a[i + 1], c[i + 1], c[i]))
    part(name, role, b, smooth=False, solid=0.003)


def flap(name, role, rel, span, top, corner, tip, crease=0.02, sy=LADY_SY):
    """上がけの垂れ（折り紙の尖ったひだ）。rel は前から測った真ん中の向き（度）、span は上の縁の半分の開き（度）。
    top=(半径, 高さ)、corner=(半径, 高さ) は左右の角、tip=(半径, 高さ) は下の尖り。真ん中に山折りの稜線"""
    def P(a_deg, r, z, out=0.0):
        a = math.radians(90 + a_deg)
        return V(math.cos(a) * (r + out), math.sin(a) * (r + out) * sy, z)

    def b(m):
        rt, zt = top
        rc, zc = corner
        rp, zp = tip
        s2 = span * 1.25
        rows = [
            [P(rel - span, rt, zt), P(rel, rt, zt, crease * 0.3), P(rel + span, rt, zt)],
            [P(rel - span * 1.12, (rt + rc) / 2, (zt + zc) / 2), P(rel, (rt + rc) / 2 + 0.01, (zt + zc) / 2 - 0.02, crease * 0.7),
             P(rel + span * 1.12, (rt + rc) / 2, (zt + zc) / 2)],
            [P(rel - s2, rc, zc), P(rel, (rc + rp) / 2, (zc + zp) / 2, crease), P(rel + s2, rc, zc)],
        ]
        vs = [[m.bm.verts.new(p) for p in row] for row in rows]
        t = m.bm.verts.new(P(rel, rp, zp, crease * 0.6))
        for k in range(2):
            for i in range(2):
                m.bm.faces.new((vs[k][i], vs[k + 1][i], vs[k + 1][i + 1], vs[k][i + 1]))
        m.bm.faces.new((vs[2][0], t, vs[2][1]))
        m.bm.faces.new((vs[2][1], t, vs[2][2]))
    return part(name, role, b, smooth=False, solid=0.004)


LADY_WAIST, LADY_NECK = 0.79, 1.06   # 腰と首の付け根の高さ（参考の寸法）
LADY_TORSO, LADY_HEAD = 0.8, 0.8
SKIRT_PARTS = ("underskirt", "front_panel", "flap_low", "flap_up")
HEAD_PARTS = ("face", "head", "bob")


SEAT_K = 0.6   # 座ったときの裾の高さの割合（腰が座面の高さまで下がり、裾は床へ広がる）


def sit_down(objs, top):
    """座る: 裾を縦に縮めて床に広げ、腰から上はそのまま下げる"""
    drop = LADY_WAIST * (1 - SEAT_K)
    for ob in objs:
        if ob.type != "MESH":
            continue
        skirt = ob.name.split(".")[0] in SKIRT_PARTS
        for v in ob.data.vertices:
            p = v.co
            v.co = V(p.x * (1.08 if skirt else 1.0), p.y * (1.08 if skirt else 1.0) + (0.04 if skirt else 0.0),
                     p.z * SEAT_K if skirt else p.z - drop)
    return top - drop


def shrink_upper(objs):
    """腰から上を縦に縮め、頭を小さくする。いちばん上の高さを返す"""
    def torso(z):
        return LADY_WAIST + (z - LADY_WAIST) * LADY_TORSO
    neck = torso(LADY_NECK)
    top = 0.0
    for ob in objs:
        base = ob.name.split(".")[0]
        if ob.type != "MESH" or base in SKIRT_PARTS:
            continue
        for v in ob.data.vertices:
            p = v.co
            if base in HEAD_PARTS:
                v.co = V(p.x * LADY_HEAD, p.y * LADY_HEAD, neck + (p.z - LADY_NECK) * LADY_HEAD)
            else:
                v.co = V(p.x, p.y, torso(p.z))
            top = max(top, v.co.z)
    return top


# ================================================================ D 黒い折り紙の婦人
def build_d(stall=True, seated=False):
    """参考: 着物とドレスを混ぜた黒い紙の婦人（クレープ紙のおかっぱは顎で広がり首へ締まる、目のない白い盾の顔、
    朱の内衿の打ち合わせと墨の広い衿、袖山の立った細い袖とベルの袖口、手を前で重ねる、細く締まった腰と帯留め、
    墨地に金と朱の花の上がけを二段に垂らし、前は無地の尖った垂れ、裾は床で大きく広がる）。
    取る: 上のすべて。量の配り: 頭は小さく、肩幅は腰の 2.4 倍、裾は腰の 7 倍
    売り場（棚）: うしろに木のひな壇の棚（赤いフェルト敷き）。上の段に提灯、下の段に小鳥とどんぐり
    取らない: なし（参考の形を写す）
    頭身（2026-11-02 代表「頭のサイズ縮小と、胴と腕を短く」）: 参考の寸法で組んでから、腰から上を縦に LADY_TORSO 倍、
    頭（顔・髪）を首の付け根を中心に LADY_HEAD 倍にする（shrink_upper）。裾はそのまま"""
    before = set(bpy.data.objects)
    # 裾: いちばん下の無地のクレープ紙（縦のひだ）。腰から床へ広がる
    ring_shell("underskirt", "crepe", [(0.05, 0.79), (0.1, 0.7), (0.2, 0.5), (0.3, 0.26), (0.36, 0.08), (0.375, 0.0)], 56, pleat=0.008)
    # 前の無地の尖った垂れ（着物の前の打ち合わせ）
    def front(m):
        pts = [(0.0, 0.78, 0.012), (0.045, 0.6, 0.06), (0.075, 0.38, 0.085), (0.0, 0.115, 0.0)]
        rows = []
        for hw, z, _ in pts:
            r = 0.05 + (0.36 - 0.05) * (0.79 - z) / 0.79
            y = r * LADY_SY + 0.015
            rows.append((hw, z, y))
        vs = []
        for hw, z, y in rows:
            vs.append([m.bm.verts.new(V(-hw, y - 0.01, z)), m.bm.verts.new(V(0, y + 0.012, z)), m.bm.verts.new(V(hw, y - 0.01, z))])
        for k in range(len(vs) - 1):
            for i in range(2):
                m.bm.faces.new((vs[k][i], vs[k + 1][i], vs[k + 1][i + 1], vs[k][i + 1]))
    part("front_panel", "crepe", front, smooth=False, solid=0.004)
    # 上がけ: 中の段（大きな垂れ、尖りは膝の下）と上の段（腰から、尖りは腿）。前はあけて無地の垂れを見せる
    for s in (1, -1):
        for k, rel in enumerate((48, 108, 168)):
            flap("flap_low", "flowers", s * rel, 30, (0.17, 0.6), (0.33, 0.3), (0.39, 0.12), crease=0.03)
        for k, rel in enumerate((56, 114, 170)):
            flap("flap_up", "flowers", s * rel, 26, (0.055, 0.78), (0.29, 0.56), (0.33, 0.44), crease=0.025)
    # 上衣: 胸から細い腰へ締まり、前は尖って腰の下まで
    ring_shell("bodice", "crepe", BODICE, 14, solid=0.0, gaps=BODICE_GAP)
    # 中に着る朱の着物: 上衣の少し内側に、首まで立つ衿
    ring_shell("kimono_in", "washi_red", [(0.024, 1.092), (0.029, 1.062)] + [(r * 0.955, z) for r, z in BODICE[1:6]], 14, solid=0.0)
    part("bodice_point", "crepe", lambda m: [m.bm.faces.new([m.bm.verts.new(p) for p in (V(-0.05, 0.04, 0.78), V(0, 0.016, 0.72), V(0.05, 0.04, 0.78))])], smooth=False, solid=0.004)
    # 衿: 朱の内衿を左前に打ち合わせ、墨の広い衿を胸の V へ
    for s in (1, -1):
        if s > 0:   # 朱の内衿の打ち合わせ（左前）: 首の横から胸の V の底へ斜めに重なる折り目
            rope("inner_fold", "washi_rust", [on_bodice(x, z, -0.0012) for x, z in ((0.027, 1.07), (0.016, 1.02), (0.004, 0.97), (-0.004, 0.93))],
                 r=0.0022, sides=5)
        # 墨の広い衿: V のふちから外へ折り返す
        zs = (1.044, 1.012, 0.96, 0.912)
        wide = (0.022, 0.042, 0.036, 0.012)
        surface_panel("lapel", "crepe_lt", [((gap_x(z) + 0.002) * s, z) for z in zs],
                      [((gap_x(z) + 0.002 + w) * s, z) for z, w in zip(zs, wide)], 0.006)
        m_s = C.M("stand_collar", "crepe_lt", "doll")   # 首のうしろに立つ衿
        ribbon(m_s, [V(0.03 * s, -0.01, 1.05), V(0.036 * s, -0.012, 1.11)], 0.045, [V(0.3 * s, 1, 0)] * 2)
        m_s.done(smooth=False).modifiers.new("sol", "SOLIDIFY").thickness = 0.004
    rope("neck", "crepe", [V(0, -0.005, 1.04), V(0, -0.005, 1.085)], r=0.021, sides=6)
    # 帯留め: 腰の前の小さな金具
    rope("brooch", "brass", [V(0, 0.047, 0.845), V(0, 0.05, 0.775)], r=0.008, sides=6)
    part("brooch_knot", "brass", lambda m: facet_ball(m, V(0, 0.054, 0.81), (0.014, 0.008, 0.012), 6, 4, 0.0, 47), smooth=False)
    # 袖: 立った袖山、細い腕、ベルの袖口。手は腰の前で重ねる
    hands = V(0, 0.165, 0.685)
    for s in (1, -1):
        part("puff", "crepe", lambda m, s=s: facet_ball(m, V(0.128 * s, 0.0, 1.035), (0.042, 0.04, 0.056), 5, 4, 0.0, 48 + s), smooth=False)
        sh, el, wr = V(0.128 * s, 0.0, 1.01), V(0.168 * s, 0.01, 0.845), V(0.07 * s, 0.13, 0.72)
        part("arm", "crepe", lambda m, sh=sh, el=el, wr=wr: C.tube(m, [sh, el, wr], [0.028, 0.024, 0.022], sides=7), smooth=False)
        d = (wr - el).normalized()
        part("cuff", "crepe", lambda m, wr=wr, d=d: C.tube(m, [wr - d * 0.03, wr + d * 0.01, wr + d * 0.045, wr + d * 0.07],
                                                             [0.024, 0.04, 0.06, 0.072], sides=9, caps=False), smooth=False, solid=0.004)
    part("hands", "washi", lambda m: facet_ball(m, hands, (0.045, 0.03, 0.028), 6, 4, 0.0, 46), smooth=False)
    shield_face()
    bob_hair()
    top = shrink_upper(set(bpy.data.objects) - before)
    if seated:
        top = sit_down(set(bpy.data.objects) - before, top)
    if not stall:
        return top
    # ひな壇の棚: 3 段。赤いフェルト
    cy = -0.65
    for k in range(3):
        z = 0.32 + 0.3 * k
        yy = cy + 0.22 - 0.2 * k
        part("step", "wood", lambda m, z=z, yy=yy: C.tube(m, [V(-0.62, yy, z / 2), V(0.62, yy, z / 2)], 0.11, sides=8, ry=z / 2, sq=8.0), smooth=False)
        part("step_felt", "felt_obi", lambda m, z=z, yy=yy: C.tube(m, [V(-0.63, yy + 0.02, z + 0.005), V(0.63, yy + 0.02, z + 0.005)], 0.12, sides=8, ry=0.008, sq=8.0), smooth=False)
    for k in range(4):   # 上の段から立てた細い竿に提灯
        x = -0.45 + 0.3 * k
        rope("rack", "wood_dark", [V(x, cy - 0.18, 0.92), V(x, cy - 0.18, 1.45), V(x, cy - 0.02, 1.45)], r=0.008, sides=5)
        chochin(V(x, cy - 0.02, 1.45), r=0.055, h=0.12, glow=GLOWS[k], string=0.05)
    for k, x in enumerate((-0.45, -0.15, 0.15, 0.45)):
        ori_bird(V(x, cy + 0.04, 0.63), 1.0, ("washi_blue", "washi_white", "washi_red", "washi_teal")[k], ("washi_pink", "washi_blue", "washi_ochre", "washi_white")[k], yaw=0.2 * k)
    for k, x in enumerate((-0.4, -0.2, 0.0, 0.2, 0.4)):
        acorn(V(x, cy + 0.24, 0.33), 1.0)
    return top


# ================================================================ E 星のマントの子
def build_e(stall=True):
    """参考: 新聞紙の王子（もんだ紙のつんつんの髪、クラフト紙の長い上着とブーツ、紺の紙に小さな星のマント）。
    取る: もんだ紙の尖った髪、クラフト紙の長い上着、紺に星のマント（片側へ流す）、焦げ茶の紙のブーツ。顔は糸の閉じた目。
    売り場（台）: 開いた紙の行李を木の台に載せ、ふたに小鳥とどんぐりを並べ、行李に挿した棒から提灯
    取らない: 星の背景、狐（ミニオンは山師の売り物）"""
    for s in (1, -1):
        part("boot", "kraft_dark", lambda m, s=s: facet_ball(m, V(0.07 * s, 0.03, 0.08), (0.05, 0.07, 0.08), 6, 4, 0.004, 51 + s), smooth=False)

    def coat(m):
        sheet_cone(m, [(0.12, 0.82), (0.15, 0.66), (0.2, 0.32), (0.22, 0.16)], n=10, sy=0.85)
    part("coat", "kraft", coat, smooth=False, solid=0.006)
    part("coat_top", "kraft", lambda m: facet_ball(m, V(0, 0, 0.81), (0.125, 0.105, 0.04), 10, 3, 0.0, 53), smooth=False)
    rope("belt", "kraft_dark", [V(math.cos(a) * 0.17, math.sin(a) * 0.145, 0.5) for a in [2 * math.pi * k / 12 for k in range(13)]], r=0.012, sides=4)

    def cape(m):
        rows = sheet_cone(m, [(0.13, 0.84), (0.21, 0.66), (0.27, 0.38), (0.31, 0.2)], n=9, sy=0.9, lon=(150.0, 395.0))
        for row in rows[1:]:   # 右へ流す
            for v in row:
                v.co.x -= 0.06 * (0.84 - v.co.z)
    part("cape", "stars", cape, smooth=False, solid=0.005)
    for s in (1, -1):
        rope("sleeve", "kraft", [V(0.12 * s, 0.0, 0.78), V(0.18 * s, 0.04, 0.62), V(0.15 * s, 0.1, 0.52)], r=0.04, sides=5)
        part("hand", "ori_face", lambda m, s=s: facet_ball(m, V(0.15 * s, 0.13, 0.49), (0.03, 0.03, 0.035), 6, 4, 0.002, 54 + s), smooth=False)
    hc = V(0, 0.02, 0.96)
    head = part("face", "ori_face", lambda m: facet_ball(m, hc, (0.09, 0.085, 0.1), 8, 6, 0.004, 56), smooth=False)
    thread_eyes(head, hc, 0.032, -0.012, 0.012)
    rnd = random.Random(57)
    for k in range(17):   # もんだ紙の尖った髪
        a = 2 * math.pi * k / 17 + rnd.uniform(-0.15, 0.15)
        el = rnd.uniform(0.15, 1.2)
        d = V(math.cos(a) * math.cos(el), math.sin(a) * math.cos(el) * 0.9 - 0.2, math.sin(el) + 0.25).normalized()
        if d.y > 0.55 and d.z < 0.6:
            continue
        base = hc + V(0, -0.005, 0.03) + d * 0.07
        part("hair", "kraft_crumple", lambda m, base=base, d=d: C.tube(m, [base, base + d * rnd.uniform(0.07, 0.11)], [0.035, 0.004], sides=4), smooth=False)
    if not stall:
        return 1.12
    # 行李の台: 木の台に、ふたの開いた紙の箱
    cx, cy = 0.62, -0.25
    part("stand", "wood", lambda m: C.tube(m, [V(cx - 0.32, cy, 0.25), V(cx + 0.32, cy, 0.25)], 0.22, sides=8, ry=0.25, sq=8.0), smooth=False)
    part("box", "kraft", lambda m: C.tube(m, [V(cx - 0.28, cy, 0.62), V(cx + 0.28, cy, 0.62)], 0.18, sides=8, ry=0.12, sq=8.0), smooth=False)
    part("box_in", "washi_rust", lambda m: C.tube(m, [V(cx - 0.26, cy + 0.0, 0.66), V(cx + 0.26, cy + 0.0, 0.66)], 0.16, sides=8, ry=0.085, sq=8.0), smooth=False)

    def lid(m):   # うしろへ開いて立てたふた
        vs = [m.bm.verts.new(p) for p in (V(cx - 0.28, cy - 0.18, 0.74), V(cx + 0.28, cy - 0.18, 0.74), V(cx + 0.28, cy - 0.26, 1.08), V(cx - 0.28, cy - 0.26, 1.08))]
        m.bm.faces.new(vs)
    part("lid", "stars", lid, smooth=False, solid=0.01)
    for k, x in enumerate((-0.18, 0.0, 0.18)):
        ori_bird(V(cx + x, cy + 0.02, 0.745), 1.0, ("washi_white", "washi_blue", "washi_red")[k], ("washi_blue", "washi_pink", "washi_white")[k], yaw=-0.3 + 0.3 * k)
    acorn(V(cx - 0.1, cy + 0.12, 0.745), 0.9)
    acorn(V(cx + 0.1, cy + 0.12, 0.745), 0.9)
    rope("stick", "wood_dark", [V(cx + 0.3, cy - 0.1, 0.5), V(cx + 0.36, cy - 0.12, 1.5), V(cx - 0.1, cy - 0.16, 1.62)], r=0.01, sides=5)
    for k, t in enumerate((0.15, 0.45, 0.75)):
        p = V(cx + 0.36, cy - 0.12, 1.5).lerp(V(cx - 0.1, cy - 0.16, 1.62), t)
        chochin(p, r=0.05, h=0.11, glow=GLOWS[k], string=0.06 + 0.06 * (k % 2))
    return 1.12


BUILDS = [("A", build_a), ("B", build_b), ("C", build_c), ("D", build_d), ("E", build_e)]


def group(name, fn, *a):
    before = set(bpy.data.objects)
    top = fn(*a)
    emp = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(emp)
    for ob in set(bpy.data.objects) - before:
        if ob is not emp and ob.parent is None:
            ob.parent = emp
    return emp, top


def import_glb(name, path, scale):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    emp = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(emp)
    for ob in set(bpy.data.objects) - before:
        if ob is not emp and ob.parent is None:
            ob.parent = emp
    emp.scale = (scale,) * 3
    return emp


def stage(size):
    C.ground(80.0)
    C.light(elev=24.0, az=-140.0)
    bpy.data.objects["sun"].data.color = (1.0, 0.8, 0.6)
    C.setup_render(size)
    sc = bpy.context.scene
    sc.eevee.taa_render_samples = A.samples
    sc.view_settings.exposure = -0.75


VIEWS = {"front": 0, "quarter": 28, "backq": 145}


def sheet():
    C.reset()
    roles()
    emps = []
    builds = [b for b in BUILDS if not A.only or b[0] in A.only]
    step = 2.3
    for k, (name, fn) in enumerate(builds):   # カメラは +Y から見るので、+X が絵の左
        emp, _ = group(name, fn)
        emp.location = V(step * ((len(builds) - 1) / 2 - k), 0, 0)
        emp.scale = (GAME_SCALE,) * 3
        emps.append(emp)
    stage(A.size)
    os.makedirs(OUT, exist_ok=True)
    tgt = V(0.0, -0.3, 1.15)
    for v in A.views.split(","):
        for emp in emps:
            emp.rotation_euler = (0, 0, math.radians(VIEWS[v] + A.turn))
        a = math.radians(4)
        dist = max(10.0, (step * len(builds) + 0.6) / 0.45)
        C.render(tgt + V(math.sin(a) * dist, math.cos(a) * dist, 1.4), tgt, 80, os.path.join(OUT, "00-five-%s.png" % v))


# ================================================================ 婦人のカウンターの案（2026-11-02 代表「洋風テーブルとティーセット置いてそこに座ってもらおうか」）
def stick(name, role, pts, r=0.01, sides=8):
    """角の立った木の棒（rope は端が丸く細るので、家具の脚や柱はこちら）"""
    return part(name, role, lambda m: C.tube(m, pts, r, sides=sides), smooth=False)


def lace_doily(c, r, z, drop=0.05, role="washi_white"):
    """紙のレースのドイリー: 丸い紙の縁を波に切り、少し垂らす"""
    def b(m):
        rows = sheet_cone(m, [(0.0, z), (r * 0.8, z), (r, z - drop)], n=36, wave=(18, 0.025))
        for row in rows:
            for v in row:
                v.co.x += c.x
                v.co.y += c.y
    part("doily", role, b, smooth=False, solid=0.002)


def tea_table(c, r=0.34, h=0.66):
    """木の丸いティーテーブル（一本脚に猫脚 3 本）と、紙のレースのドイリー"""
    part("table_top", "wood", lambda m: C.tube(m, [c + V(0, 0, h - 0.03), c + V(0, 0, h)], r, sides=24), smooth=False)
    lace_doily(c, r + 0.05, h + 0.004)
    part("table_post", "wood_dark", lambda m: C.tube(m, [c + V(0, 0, 0.12), c + V(0, 0, h - 0.03)], [0.035, 0.028], sides=8), smooth=False)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.5
        d = V(math.cos(a), math.sin(a), 0)
        stick("table_leg", "wood_dark", [c + V(0, 0, 0.16), c + d * 0.14 + V(0, 0, 0.1), c + d * 0.26 + V(0, 0, 0.02)], r=0.016, sides=6)


def teapot(at):
    """紙のティーポットとカップ: 面の少ない白い紙に藍の帯"""
    part("pot", "washi_white", lambda m: facet_ball(m, at + V(0, 0, 0.07), (0.075, 0.075, 0.065), 8, 5, 0.0, 61), smooth=False)
    part("pot_band", "washi_blue", lambda m: C.tube(m, [at + V(0, 0, 0.066), at + V(0, 0, 0.082)], 0.077, sides=8), smooth=False)
    part("pot_lid", "washi_white", lambda m: facet_ball(m, at + V(0, 0, 0.135), (0.035, 0.035, 0.02), 6, 3, 0.0, 62), smooth=False)
    part("pot_knob", "washi_blue", lambda m: facet_ball(m, at + V(0, 0, 0.158), (0.012, 0.012, 0.012), 5, 3, 0.0, 63), smooth=False)
    part("pot_spout", "washi_white", lambda m: C.tube(m, [at + V(0.06, 0, 0.06), at + V(0.12, 0, 0.12)], [0.018, 0.008], sides=6), smooth=False)
    rope("pot_handle", "washi_white", [at + V(-0.065, 0, 0.11), at + V(-0.11, 0, 0.09), at + V(-0.065, 0, 0.04)], r=0.008, sides=5)


def cup(at):
    part("saucer", "washi_white", lambda m: C.tube(m, [at, at + V(0, 0, 0.006)], 0.06, sides=12), smooth=False)
    part("cup", "washi_white", lambda m: C.lathe(m, [(0.025, 0.006 + at.z), (0.04, 0.05 + at.z)], segs=10, closed=False), smooth=False, solid=0.003)
    for o in bpy.data.objects:
        pass
    rope("cup_band", "washi_blue", [V(at.x + math.cos(a) * 0.036, at.y + math.sin(a) * 0.036, at.z + 0.04) for a in [2 * math.pi * k / 12 for k in range(13)]], r=0.003, sides=4)


def cup_at(at):
    """lathe は原点のまわりに回すので、置き場所へ動かす"""
    before = set(bpy.data.objects)
    cup(V(0, 0, at.z))
    for o in set(bpy.data.objects) - before:
        o.location.x += at.x
        o.location.y += at.y


def cake_stand(at, tiers=((0.16, 0.0), (0.12, 0.17), (0.085, 0.32))):
    """3 段のケーキスタンド（真鍮の柱に紙の皿）。皿の上に小鳥とどんぐり"""
    rope("stand_rod", "brass", [at, at + V(0, 0, tiers[-1][1] + 0.09)], r=0.006, sides=6)
    rope("stand_ring", "brass", [at + V(math.cos(a) * 0.02, math.sin(a) * 0.02, tiers[-1][1] + 0.1) for a in [2 * math.pi * k / 10 for k in range(11)]], r=0.004, sides=4)
    birds = [("washi_blue", "washi_pink"), ("washi_red", "washi_ochre"), ("washi_white", "washi_blue"), ("washi_teal", "washi_white")]
    for k, (r, z) in enumerate(tiers):
        lace_doily(at, r, at.z + z + 0.01, drop=0.012)
        n = 3 if k < 2 else 2
        for i in range(n):
            a = 2 * math.pi * i / n + k
            p = at + V(math.cos(a) * r * 0.6, math.sin(a) * r * 0.6, z + 0.012)
            if (i + k) % 2:
                acorn(p, 0.8)
            else:
                ori_bird(p, 0.8, *birds[(i + k) % 4], yaw=a + 1.6)


def chair(at, yaw=0.0):
    """洋風の椅子: 木の脚、朱のフェルトの座面と、楕円の背もたれ"""
    ca, sa = math.cos(yaw), math.sin(yaw)

    def R(v):
        return at + V(v.x * ca - v.y * sa, v.x * sa + v.y * ca, v.z)
    for sx in (1, -1):
        for sy in (1, -1):
            stick("chair_leg", "wood_dark", [R(V(0.12 * sx, 0.1 * sy - 0.06, 0.0)), R(V(0.11 * sx, 0.09 * sy - 0.06, 0.38))], r=0.014, sides=6)
    part("chair_seat", "felt_obi", lambda m: blob(m, R(V(0, -0.06, 0.39)), (0.13, 0.12, 0.025), 2.6, 2.4), smooth=False)   # 座面は裾の下にかくれる
    for sx in (1, -1):
        stick("chair_back_post", "wood_dark", [R(V(0.13 * sx, -0.2, 0.36)), R(V(0.14 * sx, -0.25, 1.0))], r=0.014, sides=6)
    part("chair_back", "felt_obi", lambda m: blob(m, R(V(0, -0.245, 0.86)), (0.13, 0.018, 0.17), 2.2, 2.2), smooth=False)
    stick("chair_crest", "wood_dark", [R(V(-0.15, -0.255, 1.0)), R(V(0, -0.262, 1.06)), R(V(0.15, -0.255, 1.0))], r=0.014, sides=6)


def lantern_tree(at, n=10):
    """洋風のポールハンガー: 木の柱に、上下 2 段に枝を出して提灯を提げる"""
    stick("tree_pole", "wood_dark", [at, at + V(0, 0, 1.85)], r=0.022, sides=8)
    for k in range(3):
        a = 2 * math.pi * k / 3
        stick("tree_foot", "wood_dark", [at + V(0, 0, 0.12), at + V(math.cos(a) * 0.24, math.sin(a) * 0.24, 0.0)], r=0.016, sides=6)
    part("tree_cap", "wood_dark", lambda m: facet_ball(m, at + V(0, 0, 1.87), (0.04, 0.04, 0.04), 6, 4, 0.0, 64), smooth=False)
    for k in range(n):
        lvl = k % 2
        a = 2 * math.pi * (k // 2) / (n // 2) + lvl * 0.6
        z = 1.78 - 0.42 * lvl
        d = V(math.cos(a), math.sin(a), 0)
        tip = at + d * 0.26 + V(0, 0, z + 0.06)
        stick("tree_arm", "wood_dark", [at + V(0, 0, z - 0.04), at + d * 0.16 + V(0, 0, z), tip], r=0.008, sides=5)
        chochin(tip - V(0, 0, 0.01), r=0.05, h=0.11, glow=GLOWS[k % 4], string=0.04 + 0.04 * lvl)


def tea_wagon(c):
    """2 段の木のティーワゴン（車輪つき）。上の段にティーセット、下の段に小物"""
    w, d = 0.38, 0.22
    for sx in (1, -1):
        for sy in (1, -1):
            stick("wagon_leg", "wood_dark", [c + V(w * sx, d * sy, 0.06), c + V(w * sx, d * sy, 0.78)], r=0.014, sides=6)
            part("wagon_wheel", "wood_dark", lambda m, sx=sx, sy=sy: C.tube(m, [c + V(w * sx - 0.012, d * sy, 0.05), c + V(w * sx + 0.012, d * sy, 0.05)], 0.05, sides=12), smooth=False)
    for z in (0.3, 0.72):
        part("wagon_tray", "wood", lambda m, z=z: C.tube(m, [c + V(-w - 0.02, 0, z), c + V(w + 0.02, 0, z)], d + 0.03, sides=8, ry=0.012, sq=8.0), smooth=False)
        lace_doily(c, 0.2, z + 0.014, drop=0.0)
    rope("wagon_handle", "brass", [c + V(w, -d, 0.78), c + V(w + 0.08, -d, 0.86), c + V(w + 0.08, d, 0.86), c + V(w, d, 0.78)], r=0.008, sides=6)


def tea_scene():
    """案 1: 婦人はティーテーブルの横の椅子に座る。テーブルにティーセットと 3 段のスタンド（小物）、横のポールハンガーに提灯"""
    emp, top = group("lady", build_d, False, True)
    emp.scale = (GAME_SCALE,) * 3
    ch, _ = group("chair", chair, V(0, 0.0, 0.0))
    ch.scale = (GAME_SCALE,) * 3
    tb, _ = group("table", lambda: (tea_table(V(0, 0, 0)), teapot(V(-0.12, 0.08, 0.664)), cup_at(V(0.15, 0.16, 0.664)),
                                    cake_stand(V(0.1, -0.1, 0.664))))
    tb.scale = (GAME_SCALE,) * 3
    tb.location = V(-0.82, 0.15, 0)
    lt, _ = group("tree", lantern_tree, V(0, 0, 0))
    lt.scale = (GAME_SCALE,) * 3
    lt.location = V(0.85, -0.35, 0)
    return [emp, ch, tb, lt]


def wagon_scene():
    """案 2: 婦人は立ったまま。横にティーワゴン（上にティーセット、下に小物）、うしろのポールハンガーに提灯"""
    emp, top = group("lady", build_d, False)
    emp.scale = (GAME_SCALE,) * 3

    def wag():
        tea_wagon(V(0, 0, 0))
        teapot(V(-0.18, 0.0, 0.734))
        cup_at(V(0.05, 0.08, 0.734))
        cup_at(V(0.2, -0.06, 0.734))
        for k, x in enumerate((-0.27, -0.1, 0.08, 0.25)):
            p = V(x, 0.02 * (k % 2), 0.314)
            if k % 2:
                acorn(p, 0.9)
            else:
                ori_bird(p, 0.9, ("washi_blue", "washi_red")[k // 2], ("washi_pink", "washi_ochre")[k // 2], yaw=0.3)
    wg, _ = group("wagon", wag)
    wg.scale = (GAME_SCALE,) * 3
    wg.location = V(-0.85, 0.1, 0)
    lt, _ = group("tree", lantern_tree, V(0, 0, 0))
    lt.scale = (GAME_SCALE,) * 3
    lt.location = V(0.8, -0.4, 0)
    return [emp, wg, lt]


TIERS = [(0.56, 0.32), (0.47, 0.66), (0.38, 0.98), (0.29, 1.28), (0.2, 1.55)]   # 大きなスタンドの皿（半径, 高さ）


def giant_stand(at, items=True):
    """アフタヌーンティーのスタンドを背丈より大きくした売り場: 真鍮の柱に 5 段の紙の皿（レースのふち）。
    皿に頭・肩の小物を並べ、下の 2 段のふちから提灯を提げる"""
    top = TIERS[-1][1] + 0.3
    stick("stand_pole", "brass", [at, at + V(0, 0, top)], r=0.022, sides=10)
    part("stand_foot", "brass", lambda m: C.tube(m, [at, at + V(0, 0, 0.05)], [0.3, 0.2], sides=16), smooth=False)
    rope("stand_ring", "brass", [at + V(math.cos(a) * 0.08, math.sin(a) * 0.08 * 0.3, top + 0.08 + math.sin(a) * 0.07)
                                 for a in [2 * math.pi * k / 16 for k in range(17)]], r=0.012, sides=6)
    part("stand_ball", "brass", lambda m: facet_ball(m, at + V(0, 0, top), (0.04, 0.04, 0.04), 8, 5, 0.0, 70), smooth=False)
    birds = [("washi_blue", "washi_pink"), ("washi_red", "washi_ochre"), ("washi_white", "washi_blue"), ("washi_teal", "washi_white")]
    lamp = 0
    for k, (r, z) in enumerate(TIERS):
        part("plate", "washi_white", lambda m, r=r, z=z: C.lathe(m, [(0.0, at.z + z), (r * 0.9, at.z + z), (r, at.z + z + 0.035)], segs=28, closed=False), smooth=False, solid=0.01)
        lace_doily(at, r * 0.82, at.z + z + 0.006, drop=0.0)
        part("plate_rim", "brass", lambda m, r=r, z=z: C.tube(m, [at + V(math.cos(a) * r, math.sin(a) * r, z + 0.035) for a in [2 * math.pi * i / 28 for i in range(29)]], 0.006, sides=5), smooth=False)
        n = max(3, int(r * 11)) if items else 0
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * (k % 2)) / n
            p = at + V(math.cos(a) * r * 0.62, math.sin(a) * r * 0.62, z + 0.008)
            if (i + k) % 3 == 1:
                acorn(p, 1.5)
            else:
                ori_bird(p, 1.5, *birds[(i + k) % 4], yaw=a + 1.6)
        if k < 2 and items:   # 下の 2 段のふちに提灯を 5 つずつ
            for i in range(5):
                a = 2 * math.pi * (i + 0.5 * k) / 5 + 0.3
                chochin(at + V(math.cos(a) * (r + 0.01), math.sin(a) * (r + 0.01), z + 0.03), r=0.055, h=0.12, glow=GLOWS[lamp % 4], string=0.05 + 0.04 * (i % 2))
                lamp += 1


LANTERN_ORDER = ["box", "paper", "spool", "knit", "hoop", "yarnball", "thimble", "hotaru", "pearl", "raden"]
PERCH_ORDER = ["chiyo_bird", "blue_bird", "acorn", "crane", "pumpkin", "maple", "hummingbird", "squirrel", "chameleon", "moon_rabbit", "phoenix"]
# 段ごとの品（下から）: 下の 2 段は提灯、上の 3 段は頭・肩の小物。同じ品は一つずつ、前の半分の弧に並べる
STOCK_TIERS = [("lantern", LANTERN_ORDER[:5]), ("lantern", LANTERN_ORDER[5:]),
               ("perch", PERCH_ORDER[:5]), ("perch", PERCH_ORDER[5:9]), ("perch", PERCH_ORDER[9:])]
PERCH_SHOW = 0.26   # 小物の見本の大きさ（いちばん長い辺, m）


def import_item(path, mats=None, glow=None):
    """ゲームの glb を読み、ひとまとめの空の親を返す。小物は mats.json の色で紙に、提灯の紙は灯す"""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = set(bpy.data.objects) - before
    emp = bpy.data.objects.new(os.path.basename(path), None)
    bpy.context.scene.collection.objects.link(emp)
    for ob in new:
        if ob.parent is None:
            ob.parent = emp
        if ob.type != "MESH":
            continue
        for slot in ob.material_slots:
            mt = slot.material
            if mt is None:
                continue
            key = mt.name.split(".")[0]
            if mats and key in mats:
                slot.material = C._MAT.setdefault("pal_" + key, paper("pal_" + key, mats[key][1], back=mats[key][1], fiber=0.3))
            elif glow and "paper" in key:
                b = mt.node_tree.nodes.get("Principled BSDF")
                if b:
                    b.inputs["Emission Color"].default_value = lin(glow)
                    b.inputs["Emission Strength"].default_value = 1.6
    return emp, new


def world_bounds(objs):
    import mathutils
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    bpy.context.view_layer.update()
    for ob in objs:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ mathutils.Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def stock_stand(loc, k=GAME_SCALE):
    """スタンドの皿に、ゲームの提灯 10 種と頭・肩の小物 11 点を一つずつ載せる（ゲームの大きさ）"""
    import json
    G = os.path.join(ROOT, "game")
    mats = json.load(open(os.path.join(G, "pals", "mats.json"), encoding="utf-8"))
    glows = {"pearl": "C8DCFF", "hotaru": "C8FF6A"}
    for (r, z), (kind, names) in zip(TIERS, STOCK_TIERS):
        n = len(names)
        for i, name in enumerate(names):
            a = math.radians(90 + (i - (n - 1) / 2) * (150.0 / max(n - 1, 1) if n > 1 else 0))
            rr = r * (0.66 if kind == "lantern" else 0.6) * k
            spot = loc + V(math.cos(a) * rr, math.sin(a) * rr, (z + 0.012) * k)
            if kind == "lantern":
                emp, objs = import_item(os.path.join(G, "props", "lantern", "lantern_%s.glb" % name), glow=glows.get(name, "F0B65A"))
            else:
                emp, objs = import_item(os.path.join(G, "pals", "perch_%s.glb" % name), mats=mats)
                lo, hi = world_bounds(objs)
                emp.scale = (PERCH_SHOW / max(hi - lo),) * 3
            emp.rotation_euler = (0, 0, a - math.pi / 2 + (math.pi / 2 if kind == "perch" else 0.0))   # 小物の glb は横向きなので前へ回す
            lo, hi = world_bounds(objs)
            c = (lo + hi) / 2
            emp.location += V(spot.x - c.x, spot.y - c.y, spot.z - lo.z)


# ================================================================ ゲームへの書き出し
def _node(name, parent, at):
    """節点（空）。at は世界の位置、親からの位置で置く（親の逆行列は使わない。書き出しでそのまま戻すため）"""
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
        e.location = at - parent.matrix_world.translation
    else:
        e.location = at
    bpy.context.view_layer.update()
    return e


def _to_game_size(objs):
    """ラフの大きさで組んだ部品を、ゲームの大きさ（GAME_SCALE 倍）に当てる"""
    from mathutils import Matrix
    for o in objs:
        if o.type == "MESH":
            o.data.transform(Matrix.Scale(GAME_SCALE, 4))
            o.location = o.location * GAME_SCALE
            for md in o.modifiers:
                if md.type == "SOLIDIFY":
                    md.thickness *= GAME_SCALE


def _export_tree(K, top, subs, path, mat_name):
    """節点ごとに軽い形へ焼いてから、木のまま 1 つの glb に（props/build_snowman.py の export_tree と同じ）。subs は親から子の順"""
    from mathutils import Matrix
    saved = [(n, n.parent, n.matrix_basis.copy()) for n in subs]
    for n in reversed(subs):
        mw = n.matrix_world.copy()
        n.parent = None
        n.matrix_world = mw
    bpy.context.view_layer.update()
    for r in [top] + subs:
        if any(o.type == "MESH" for o in bpy.data.objects if o.parent == r):
            K.prepare(r)
            for o in [o for o in bpy.data.objects if o.parent == r and o.type == "MESH"]:
                o.data.transform(o.matrix_parent_inverse)
                o.matrix_parent_inverse = Matrix.Identity(4)
    for n, par, mb in saved:
        n.parent = par
        n.matrix_parent_inverse = Matrix.Identity(4)
        n.matrix_basis = mb
    bpy.context.view_layer.update()
    objs = [top] + K.descendants(top)
    for o in objs:   # 焼いた紙の素材の名前を paper_* に（Godot の props.gd が紙の細部を重ねる。"paper" だけだと灯りとして光る）
        if o.type == "MESH":
            for m in o.data.materials:
                if m and m.name.split(".")[0] == "felt":
                    m.name = mat_name
    print("triangles", top.name, C.tri_count(objs))
    C.export(objs, path, top)


def export_game(folder, what):
    """婦人（節: 腰から上 upper・頭 head。12 コマで動かす）か、大きなスタンドを、焼いた色と凹凸つきの glb に"""
    import kit as K
    C.reset()
    C.LOOK["v"] = "day"
    C.NOFUZZ["v"] = True
    K.S["scale"] = 1.0
    roles()
    before = set(bpy.data.objects)
    if what == "lady":
        build_d(False)
        objs = list(set(bpy.data.objects) - before)
        _to_game_size(objs)
        waist = LADY_WAIST * GAME_SCALE
        neck = (LADY_WAIST + (LADY_NECK - LADY_WAIST) * LADY_TORSO) * GAME_SCALE
        root = _node("paper_lady", None, V(0, 0, 0))
        upper = _node("upper_body", root, V(0, 0, waist))
        head = _node("head_pivot", upper, V(0, 0, neck))
        root["tris"], upper["tris"], head["tris"] = 2600, 2600, 1400
        for o in objs:
            base = o.name.split(".")[0]
            par = root if base in SKIRT_PARTS else head if base in HEAD_PARTS else upper
            o.parent = par
            o.matrix_parent_inverse = par.matrix_world.inverted()
        _export_tree(K, root, [upper, head], os.path.join(folder, "paper_lady.glb"), "paper_doll")
    else:
        giant_stand(V(0, 0, 0), False)
        objs = list(set(bpy.data.objects) - before)
        _to_game_size(objs)
        root = _node("tea_stand", None, V(0, 0, 0))
        root["tris"] = 3600
        for o in objs:
            o.parent = root
        _export_tree(K, root, [], os.path.join(folder, "tea_stand.glb"), "paper_stand")


def tiers_scene():
    C.reset()
    roles()
    emp, _ = group("lady", build_d, False)
    emp.scale = (GAME_SCALE,) * 3
    emp.location = V(0.55, 0.35, 0)
    st, _ = group("stand", giant_stand, V(0, 0, 0), False)
    st.scale = (GAME_SCALE,) * 3
    st.location = V(-0.55, -0.2, 0)
    stock_stand(st.location)
    stage(A.size)
    os.makedirs(OUT, exist_ok=True)
    tgt = V(0, 0, 1.15)
    for v, deg in (("front", 0), ("quarter", 32)):
        a_ = math.radians(deg)
        C.render(tgt + V(math.sin(a_) * 9.5, math.cos(a_) * 9.5, 1.0), tgt, 80, os.path.join(OUT, "06-tiers-%s.png" % v))


def counter_ideas():
    C.reset()
    roles()
    a = tea_scene()
    b = wagon_scene()
    for e in a:
        e.location.x += 2.3
    for e in b:
        e.location.x -= 2.3
    stage(A.size)
    os.makedirs(OUT, exist_ok=True)
    tgt = V(0, 0, 1.2)
    for v, deg in (("front", 0), ("quarter", 30)):
        a_ = math.radians(deg)
        C.render(tgt + V(math.sin(a_) * 18.0, math.cos(a_) * 18.0, 1.4), tgt, 80, os.path.join(OUT, "05-counter-%s.png" % v))


def close():
    """婦人の寄り: 全身（正面・斜め・横）と頭（正面・斜め）"""
    C.reset()
    roles()
    emp, top = group("D", build_d, False)
    emp.scale = (GAME_SCALE,) * 3
    stage(A.size)
    os.makedirs(OUT, exist_ok=True)
    h = top * GAME_SCALE
    for v, deg in (("front", 0), ("quarter", 35), ("side", 80)):
        emp.rotation_euler = (0, 0, math.radians(deg))
        tgt = V(0, 0, h * 0.5)
        C.render(tgt + V(0, 5.6, 0.2), tgt, 80, os.path.join(OUT, "02-lady-%s.png" % v))
    for v, deg in (("front", 0), ("quarter", 35)):
        emp.rotation_euler = (0, 0, math.radians(deg))
        tgt = V(0, 0, 1.03 * GAME_SCALE)
        C.render(tgt + V(0, 2.0, 0.1), tgt, 80, os.path.join(OUT, "02-head-%s.png" % v))


def lineup():
    """いまのキャラ（人形 3 体・おじいさん・山男・雪だるま）と 5 案を、ゲームの大きさで並べる"""
    C.reset()
    roles()
    tabi = borrow(os.path.join(IDEAS, "characters", "v2", "roughs_v2.py"), "BUILDERS =")
    tabi["PERSON"] = os.path.join(ROOT, "person")   # v2 の台本は一つ深い所へ移ったので、紙の画像の場所を直して渡す
    tabi["register_paper"]()
    yama = borrow(os.path.join(IDEAS, "yamaotoko", "roughs.py"), "BUILDS =")
    yama["paper_roles"]()
    roles()   # 借りた台本が同じ名前の紙を置き換えたので、こちらの紙に戻す
    row = []
    G = os.path.join(ROOT, "game")
    row.append(import_glb("kasa", os.path.join(G, "person", "kasa.glb"), 1.15))
    row.append(import_glb("news", os.path.join(G, "person", "news.glb"), 1.05))
    e, _ = group("tabi", tabi["build_tabi"])
    e.scale = (1.4,) * 3
    row.append(e)
    e, _ = group("yama", yama["build_wolf"])
    e.scale = (1.3,) * 3
    row.append(e)
    row.append(import_glb("snowman", os.path.join(G, "props", "snowman.glb"), 1.0))
    for name, fn in BUILDS:
        if A.only and name not in A.only:
            continue
        e, _ = group(name, fn, False)
        e.scale = (GAME_SCALE,) * 3
        row.append(e)
    xs = []
    x = 0.0
    for k in range(len(row)):
        xs.append(x)
        x -= 0.95 if k != 4 else 1.5   # 雪だるまと 5 案のあいだを少しあける
    mid = (xs[0] + xs[-1]) / 2
    for e, x in zip(row, xs):
        e.location = V(x - mid, 0, 0)
        e.rotation_euler = (0, 0, math.radians(15 + A.turn))
    stage(A.size)
    os.makedirs(OUT, exist_ok=True)
    tgt = V(0.0, 0, 0.85)
    a = math.radians(6)
    dist = max(10.0, (xs[0] - xs[-1] + 1.6) / 0.45)
    C.render(tgt + V(math.sin(a) * dist, math.cos(a) * dist, 1.3), tgt, 80, os.path.join(OUT, "01-lineup%s.png" % (("-" + A.only) if A.only else "")))


if A.export:
    export_game(A.export, A.what)
elif A.tiers:
    tiers_scene()
elif A.counter:
    counter_ideas()
elif A.close:
    close()
elif A.lineup:
    lineup()
else:
    sheet()
