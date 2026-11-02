"""山の道具の売り子（山男・山師）のラフ。代表の Pinterest のボード「&wind：Lodge キャラ」の意匠を取り、Lodge の素材で描く。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/yamaotoko/roughs.py -- --size 2400x1100

3 案を雪の上に並べる（カメラは +Y から。絵の左から A・B・C）:
  A  蓑の山師     ボードの「紙の葉を重ねた剣士」から: 体を、ちぎった紙の葉を何段も重ねた蓑で包む。折った紙の頭巾、長い木の杖
  B  熊の山男     ボードの「クラフト紙の熊」「クラフト紙の兎」から: 大きな多面体のクラフト紙の体。熊の頭を折った頭巾の下から顔
  C  狼の毛皮の山男 ボードの「白い和紙の狼」「折り紙の着物の人」から: 藍の和紙を折った長い上着に、白い和紙の狼の毛皮をかぶる

部品と紙の素材は person/ideas/characters/roughs.py の「形の道具」までを読んで使う（ファイルは書き換えない）。
顔は折り紙の多面体に、黒い糸の閉じた目（光る目・頬・口は描かない）。前は +Y。
"""
import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "characters", "roughs.py"))
OUT = os.path.join(HERE, "renders")

ap = argparse.ArgumentParser()
ap.add_argument("--size", default="2400x1100")
ap.add_argument("--samples", type=int, default=64)
ap.add_argument("--turn", type=float, default=0.0)
ap.add_argument("--views", default="front,quarter,backq")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

# 人形のラフの台本から、組み立ての前（素材と形の道具）だけを借りる
_src = open(SRC, encoding="utf-8").read()
_cut = _src.index("def build_robo")
_argv = sys.argv
_ns = {"__file__": SRC, "__name__": "roughs_borrowed"}
sys.argv = ["blender"]
try:
    exec(compile(_src[:_cut], SRC, "exec"), _ns)
finally:
    sys.argv = _argv
C, V, part, blob, ball, stitch, rope, ribbon, hit, facet_ball, sheet_cone, paper, register_paper = (
    _ns[k] for k in ("C", "V", "part", "blob", "ball", "stitch", "rope", "ribbon", "hit", "facet_ball", "sheet_cone", "paper", "register_paper"))


def paper_roles():
    register_paper()
    C._MAT.update({
        "kraft_dark": paper("kraft_dark", "7A5636", back="A88A66", fiber=0.22, crinkle=0.3),
        "washi_sage": paper("washi_sage", "8C9A6A", back="D8D8C0", fiber=0.5, crinkle=0.25, sss=0.12),
        "washi_moss": paper("washi_moss", "5E7448", back="C8CCB0", fiber=0.5, crinkle=0.25, sss=0.12),
        "washi_ochre": paper("washi_ochre", "C99A4A", back="E8D8B0", fiber=0.5, crinkle=0.25, sss=0.12),
        "washi_rust": paper("washi_rust", "A8553A", back="E2C8B0", fiber=0.5, crinkle=0.25, sss=0.12),
        "washi_indigo": paper("washi_indigo", "34477E", back="C8CEDC", fiber=0.45, crinkle=0.1, sss=0.08),
        "washi_white": paper("washi_white", "EEE8DC", back="F6F2EA", fiber=0.55, crinkle=0.12, sss=0.18),
        "washi_grey": paper("washi_grey", "B8B2A6", back="E6E2DA", fiber=0.55, crinkle=0.12, sss=0.12),
    })


def thread_eyes(head, hc, dx=0.032, dz=0.0, w=0.014):
    """黒い糸の閉じた目（下に弧を描く 3 点の糸）"""
    for s in (1, -1):
        p, n = hit(head, hc + V(s * dx, 0.6, dz), V(0, -1, 0))
        rope("eye", "thread_ink", [p + V(-w, 0, 0.002) + n * 0.002, p + V(0, 0, -0.004) + n * 0.003, p + V(w, 0, 0.002) + n * 0.002], r=0.0032, sides=6)


def leaf_layer(role, leaves):
    """紙の葉: 上の 2 点で体に留め、下へとがる菱形。leaves は (上の中心, 外向き, 幅, 長さ, ねじれ)"""
    def b(m):
        for top, out, w, L, tw in leaves:
            out = Vector(out).normalized()
            side = V(-out.y, out.x, 0).normalized()
            down = V(0, 0, -1) + out * 0.35
            down.normalize()
            side = side + down * tw
            side.normalize()
            a = top - side * w * 0.5
            c = top + side * w * 0.5
            mid = top + down * L * 0.45 + out * 0.012
            tip = top + down * L + out * 0.03
            vs = [m.bm.verts.new(p) for p in (a, mid - side * w * 0.55, tip, mid + side * w * 0.55, c)]
            m.bm.faces.new((vs[0], vs[1], vs[2]))
            m.bm.faces.new((vs[0], vs[2], vs[4]))
            m.bm.faces.new((vs[4], vs[2], vs[3]))
    return part("leaves", role, b, smooth=False, solid=0.004)


# ================================================================ A 蓑の山師
def build_mino():
    """参考: 紙の葉を重ねた剣士（ちぎった緑・茶・黄土の紙片が何段も重なり、体の線が見えない。とがった頭巾、長い棒）。
    取る: 体を包む紙の葉の段（肩から膝下まで 11 段、色は 4 つ）。折った紙のとんがり頭巾。長い木の杖（右手）。小さな多面体の顔。
    取らない: 刀、舞う紙片。顔の上半分を隠すほどの髪"""
    rnd = random.Random(3)
    for s in (1, -1):
        part("boot", "kraft_dark", lambda m, s=s: facet_ball(m, V(0.09 * s, 0.03, 0.06), (0.07, 0.1, 0.06), 6, 4, 0.006, 4 + s), smooth=False)
        part("shin", "washi_grey", lambda m, s=s: facet_ball(m, V(0.09 * s, 0.0, 0.2), (0.06, 0.06, 0.13), 6, 4, 0.004, 7 + s), smooth=False)
    core = part("core", "kraft", lambda m: blob(m, V(0, 0, 0.62), (0.2, 0.17, 0.4), 2.4, 2.2, 6))
    roles = ["washi_sage", "kraft", "washi_moss", "washi_ochre"]
    by_role = {r: [] for r in roles}
    rows = 11
    for j in range(rows):
        t = j / (rows - 1)
        z = 1.0 - t * 0.72
        r = 0.15 + 0.2 * t ** 0.8
        n = int(10 + 9 * t)
        off = rnd.uniform(0, 1)
        for i in range(n):
            a = 2 * math.pi * (i + off + 0.5 * (j % 2)) / n
            o = V(math.cos(a), math.sin(a) * 0.86, 0)
            role = roles[(i * 3 + j) % 4] if rnd.random() > 0.15 else roles[rnd.randrange(4)]
            by_role[role].append((V(o.x * r, o.y * r, z), o, 2 * math.pi * r / n * 1.5, 0.12 + 0.05 * t, rnd.uniform(-0.25, 0.25)))
    for role, lv in by_role.items():
        leaf_layer(role, lv)
    # 頭と頭巾: 小さな多面体の顔を、折った紙のとんがり頭巾が包む（前があいている。先は後ろへ折れる）
    hc = V(0, 0.03, 1.1)
    head = part("head", "ori_face", lambda m: facet_ball(m, hc, (0.085, 0.08, 0.095), 8, 6, 0.004, 11), smooth=False)
    thread_eyes(head, hc, 0.03, 0.005, 0.012)

    def hood(m):
        prof = [(0.0, 1.42), (0.06, 1.3), (0.115, 1.19), (0.13, 1.08), (0.15, 1.0)]
        rows_ = sheet_cone(m, prof, n=12, lon=(125.0, 415.0))
        for k, row in enumerate(rows_):   # 先を後ろ（-Y）へ倒す
            for v in row:
                v.co.y -= 0.16 * max(0.0, v.co.z - 1.15) / 0.27
    part("hood", "washi_ochre", hood, smooth=False, solid=0.006)
    # 杖: 右手に長い木の杖（上に麻ひもの巻きと、紙の葉の飾り）
    hand = V(0.27, 0.12, 0.74)
    rope("staff", "wood_dark", [V(0.29, 0.14, 0.0), hand, V(0.26, 0.11, 1.42)], r=0.016)
    for k in range(4):
        rope("staff_bind", "hemp", [V(0.26 + 0.02 * math.cos(a), 0.11 + 0.02 * math.sin(a), 1.2 + k * 0.016 + a * 0.0025)
                                     for a in [x * 0.6 for x in range(12)]], r=0.006)
    part("hand", "ori_face", lambda m: facet_ball(m, hand, (0.04, 0.04, 0.05), 6, 4, 0.003, 13), smooth=False)
    rope("sleeve", "washi_moss", [V(0.15, 0.02, 0.96), V(0.26, 0.08, 0.86), hand + V(0, 0, 0.04)], r=0.045, sides=7)
    return 1.42


# ================================================================ B 熊の山男
def build_bear():
    """参考: クラフト紙の熊（大きな平らな面、太い四肢、丸い耳）、クラフト紙の兎（同じ紙の色と稜線）。
    取る: 体も腕も脚も、面の少ない多面体のクラフト紙。熊の頭を折った頭巾（丸い耳）の口元から、人の顔がのぞく。胸に白い紙の面。
    取らない: 四つ足の姿勢（人として立つ）、熊の鼻と目（頭巾の熊の顔は描かない）"""
    for s in (1, -1):
        part("leg", "kraft_dark", lambda m, s=s: facet_ball(m, V(0.15 * s, 0.0, 0.16), (0.12, 0.13, 0.17), 7, 5, 0.01, 2 + s), smooth=False)
        part("foot", "kraft_dark", lambda m, s=s: facet_ball(m, V(0.15 * s, 0.05, 0.04), (0.11, 0.15, 0.05), 6, 4, 0.006, 5 + s), smooth=False)
    part("torso", "kraft", lambda m: facet_ball(m, V(0, 0, 0.64), (0.34, 0.27, 0.36), 9, 6, 0.012, 1), smooth=False)
    part("chest", "washi_white", lambda m: facet_ball(m, V(0, 0.13, 0.7), (0.2, 0.16, 0.24), 7, 5, 0.008, 9), smooth=False)
    for s in (1, -1):
        part("arm", "kraft", lambda m, s=s: facet_ball(m, V(0.38 * s, 0.02, 0.78), (0.11, 0.11, 0.18), 7, 5, 0.008, 20 + s), smooth=False)
        part("forearm", "kraft", lambda m, s=s: facet_ball(m, V(0.41 * s, 0.07, 0.53), (0.1, 0.1, 0.15), 7, 5, 0.008, 22 + s), smooth=False)
        part("paw", "kraft_dark", lambda m, s=s: facet_ball(m, V(0.41 * s, 0.11, 0.37), (0.085, 0.085, 0.075), 6, 4, 0.005, 24 + s), smooth=False)
    rope("belt", "hemp", [V(math.cos(a) * 0.32, math.sin(a) * 0.255, 0.5) for a in [2 * math.pi * k / 30 for k in range(31)]], r=0.016)
    # 頭巾: 熊の頭を折った大きな多面体。口元が大きくあき、そこから顔
    hood = part("hood", "kraft", lambda m: facet_ball(m, V(0, -0.02, 1.13), (0.2, 0.2, 0.18), 8, 6, 0.01, 30), smooth=False)
    for s in (1, -1):
        part("ear", "kraft", lambda m, s=s: facet_ball(m, V(0.15 * s, -0.04, 1.29), (0.065, 0.035, 0.06), 6, 4, 0.004, 31 + s), smooth=False)
        part("ear_in", "washi_white", lambda m, s=s: facet_ball(m, V(0.15 * s, -0.008, 1.285), (0.04, 0.012, 0.038), 5, 4, 0.002, 33 + s), smooth=False)
    hc = V(0, 0.15, 1.07)
    head = part("face", "ori_face", lambda m: facet_ball(m, hc, (0.11, 0.07, 0.1), 8, 6, 0.004, 35), smooth=False)
    thread_eyes(head, hc, 0.038, 0.01, 0.014)
    _ = hood
    return 1.33


# ================================================================ C 狼の毛皮の山男
def build_wolf():
    """参考: 白い和紙の狼（とがった耳と鼻すじ、長い面、繊維の見える白い紙）、折り紙の着物の人（藍とクリームの紙を斜めに重ねた長い衣、すっと立つ）。
    取る: 藍の和紙を折った長い上着（面の少ない裾広がり）、クリームの紙の衿を斜めに重ねる。白い和紙の狼の頭を頭巾にかぶり、毛皮を背中へ垂らす。
    取らない: 狼の目（毛皮には描かない）、女の人の細い体つき"""
    for s in (1, -1):
        part("boot", "kraft_dark", lambda m, s=s: facet_ball(m, V(0.1 * s, 0.03, 0.06), (0.08, 0.11, 0.06), 6, 4, 0.006, 40 + s), smooth=False)

    def coat(m):
        prof = [(0.17, 0.98), (0.22, 0.8), (0.27, 0.5), (0.33, 0.14)]
        sheet_cone(m, prof, n=10, sy=0.8)
    part("coat", "washi_indigo", coat, smooth=False, solid=0.008)
    part("coat_top", "washi_indigo", lambda m: facet_ball(m, V(0, 0, 0.97), (0.18, 0.15, 0.05), 10, 4, 0.0, 41), smooth=False)
    # 衿: クリームの紙の帯を、左前で斜めに重ねる
    m_c = C.M("collar", "washi", "doll")
    ribbon(m_c, [V(0.11, 0.12, 0.96), V(0.0, 0.19, 0.8), V(-0.08, 0.205, 0.62)], 0.06, [V(1, 0, 0.35)] * 3)
    o = m_c.done(smooth=False)
    o.modifiers.new("sol", "SOLIDIFY").thickness = 0.006
    m_c = C.M("collar2", "washi", "doll")
    ribbon(m_c, [V(-0.11, 0.12, 0.96), V(-0.035, 0.17, 0.86)], 0.055, [V(1, 0, -0.35)] * 2)
    m_c.done(smooth=False).modifiers.new("sol", "SOLIDIFY").thickness = 0.006
    rope("belt", "yarn_red", [V(math.cos(a) * 0.245, math.sin(a) * 0.2, 0.6) for a in [2 * math.pi * k / 30 for k in range(31)]], r=0.014)
    for s in (1, -1):
        rope("sleeve", "washi_indigo", [V(0.17 * s, 0.0, 0.94), V(0.27 * s, 0.05, 0.75), V(0.25 * s, 0.13, 0.6)], r=0.06, sides=6)
        part("hand", "ori_face", lambda m, s=s: facet_ball(m, V(0.24 * s, 0.17, 0.56), (0.04, 0.04, 0.05), 6, 4, 0.003, 42 + s), smooth=False)
    hc = V(0, 0.04, 1.07)
    head = part("face", "ori_face", lambda m: facet_ball(m, hc, (0.085, 0.08, 0.095), 8, 6, 0.004, 44), smooth=False)
    thread_eyes(head, hc, 0.03, -0.005, 0.012)
    # 狼の頭巾: 白い和紙の頭、前へ出た鼻すじ、とがった耳。毛皮は背中へ垂れる
    part("wolf_head", "washi_white", lambda m: facet_ball(m, V(0, -0.01, 1.17), (0.13, 0.14, 0.09), 7, 5, 0.006, 45), smooth=False)
    part("wolf_snout", "washi_white", lambda m: facet_ball(m, V(0, 0.15, 1.17), (0.05, 0.1, 0.045), 6, 4, 0.003, 46), smooth=False)
    part("wolf_nose", "washi_grey", lambda m: facet_ball(m, V(0, 0.245, 1.18), (0.02, 0.018, 0.016), 5, 4, 0.0, 47), smooth=False)
    for s in (1, -1):
        def ear(m, s=s):
            b = V(0.08 * s, -0.03, 1.22)
            vs = [m.bm.verts.new(p) for p in (b + V(-0.04, 0, 0), b + V(0.04, 0, 0), b + V(0.0, -0.035, 0), b + V(0.01 * s, -0.015, 0.11))]
            for f in ((0, 1, 3), (1, 2, 3), (2, 0, 3)):
                m.bm.faces.new([vs[i] for i in f])
        part("wolf_ear", "washi_white", ear, smooth=False)

    def pelt(m):
        prof = [(0.12, 1.12), (0.2, 0.95), (0.27, 0.72), (0.3, 0.55)]
        sheet_cone(m, prof, n=6, sy=0.85, lon=(215.0, 325.0))
    part("pelt", "washi_white", pelt, smooth=False, solid=0.008)
    for s in (1, -1):   # 前足の毛皮を肩から胸へ垂らす
        m_p = C.M("paw_pelt", "washi_white", "doll")
        ribbon(m_p, [V(0.15 * s, 0.02, 1.0), V(0.13 * s, 0.13, 0.9), V(0.1 * s, 0.17, 0.78)], 0.06, [V(1, 0, 0)] * 3, notch=0.025)
        m_p.done(smooth=False).modifiers.new("sol", "SOLIDIFY").thickness = 0.006
    return 1.33


BUILDS = [("A", build_mino), ("B", build_bear), ("C", build_wolf)]


def group(name, fn):
    before = set(bpy.data.objects)
    top = fn()
    emp = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(emp)
    for ob in set(bpy.data.objects) - before:
        if ob is not emp and ob.parent is None:
            ob.parent = emp
    return emp, top


def stage(size):
    C.ground(60.0)
    C.light(elev=24.0, az=-140.0)
    bpy.data.objects["sun"].data.color = (1.0, 0.8, 0.6)
    C.setup_render(size)
    sc = bpy.context.scene
    sc.eevee.taa_render_samples = A.samples
    sc.view_settings.exposure = -0.75


VIEWS = {"front": 0, "quarter": 32, "side": 85, "backq": 145, "back": 180}

C.reset()
paper_roles()
emps = []
for (name, fn), x in zip(BUILDS, (1.2, 0.0, -1.2)):   # カメラは +Y から見るので、+X が絵の左
    emp, _ = group(name, fn)
    emp.location = V(x, 0, 0)
    emps.append(emp)
stage(A.size)
os.makedirs(OUT, exist_ok=True)
tgt = V(0.0, 0, 0.7)
for v in A.views.split(","):
    for emp in emps:
        emp.rotation_euler = (0, 0, math.radians(VIEWS[v] + A.turn))
    a = math.radians(6)
    C.render(tgt + V(math.sin(a) * 7.6, math.cos(a) * 7.6, 0.8), tgt, 80, os.path.join(OUT, "00-three-%s.png" % v))
