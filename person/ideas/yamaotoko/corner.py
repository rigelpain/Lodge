"""山師のまわりの案: 後ろで伏せて休む白いヤク、品物を積んだ出店（2 案）、ミニオンの広い柵と遊び場。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/yamaotoko/corner.py -- --stall pack --views high,eye,top
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/yamaotoko/corner.py -- --part yak --export game/person
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/yamaotoko/corner.py -- --part stall --stall sled --export game/person
    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/ideas/yamaotoko/corner.py -- --part pen --export game/person
代表が選んだのは、出店が sled（ソリの屋台）。ヤクと柵はこの形のまま（2026-11-02）

代表の言葉（2026-11-02）:
  「山師の後ろにこういう白いヤク置いてほしい、なんかヤクが座って休んでるみたいな」（写真: 白く長い毛、上へ曲がる角、赤い鞍掛けと鐙）
  「棚スカスカすぎだし素っ気なさすぎ。山師が商売してんだからただの棚じゃ味気ないでしょ」
  「動物たちの柵と遊び場みたいなのも狭すぎ小さすぎ」
--stall
  pack  背負子と茣蓙: 麻の茣蓙に品物を並べ、後ろに荷を積んだ木の背負子を立てる（行商の山師）
  sled  ソリの屋台: 木のソリの台に、縞のフェルトの日よけ。段に品物、日よけの横木から提灯と縄の輪を吊る
並び（山師の座標。前は +Y＝ゲームの東、山師の左手の -X＝北、後ろの -Y＝西のガラスの壁）:
  山師 (0, 0)。ヤクは後ろ (0.3, -1.75) に、頭を右手（南）へ向けて伏せる。出店は左手 X -0.6〜-3.0。柵は X -3.3〜-7.3、Y -2.7〜0.5
素材は人形と同じ（props/common.py と人形のラフの紙）。ヤクの毛は生成りの毛糸の房、体は白いフェルト、角はフェルトの筒、鞍掛けは赤いフェルトに金の糸のなみ縫い。
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
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
GAME = os.path.join(ROOT, "game")

ap = argparse.ArgumentParser()
ap.add_argument("--stall", default="pack", choices=("pack", "sled"))
ap.add_argument("--views", default="high,eye,top")
ap.add_argument("--size", default="1600x900")
ap.add_argument("--samples", type=int, default=32)
ap.add_argument("--prefix", default="corner")
ap.add_argument("--yak-only", action="store_true")
ap.add_argument("--export", default="", help="--part の形を、色と凹凸とくぼみの陰を焼いて glb に書き出すフォルダー（例: game/person）")
ap.add_argument("--part", default="", choices=("", "yak", "stall", "pen"),
                help="書き出す 1 つ（山師の座標のまま。ゲームでは山師の節に置くだけ）: yak ヤク / stall 出店（--stall の案）/ pen 柵と遊び場（ミニオンは入れない）")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

# 山師のラフの台本（素材・形の道具・ゲーム用の山師）を、描く所の前まで借りる
_src_path = os.path.join(HERE, "roughs.py")
_src = open(_src_path, encoding="utf-8").read()
_cut = _src.index("if A.game or A.export:")
_ns = {"__file__": _src_path, "__name__": "yama_borrowed"}
_argv = sys.argv
sys.argv = ["blender"]
try:
    exec(compile(_src[:_cut], _src_path, "exec"), _ns)
finally:
    sys.argv = _argv
C, V, part, blob, ball, stitch, rope, ribbon, facet_ball, sheet_cone, paper_roles, build_yamaotoko, helix, thread_eyes = (
    _ns[k] for k in ("C", "V", "part", "blob", "ball", "stitch", "rope", "ribbon", "facet_ball", "sheet_cone", "paper_roles",
                     "build_yamaotoko", "helix", "thread_eyes"))
lathe_at = _ns["_ns"]["lathe_at"]   # 人形のラフの台本の道具（山師の台本の中の _ns）
C.HEX.update({"yak_wool": "F2EEE6", "yarn_yak": "EFE8DA", "yak_muzzle": "B8B0A6", "hoof": "3A3836", "awning_red": "B8402E",
              "awning_cream": "EFE6D2", "mat_hemp": "C9AC78"})


def group_of(fn, name):
    before = set(bpy.data.objects)
    fn()
    emp = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(emp)
    for ob in set(bpy.data.objects) - before:
        if ob is not emp and ob.parent is None:
            ob.parent = emp
    return emp


def imp(path, loc, rot=0.0, sc=1.0, keep=None):
    """game/ の glb を読んで置く（ミニオンは keep の姿だけ残す）"""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(GAME, path))
    new = set(bpy.data.objects) - before
    if keep:
        drop = []
        for ob in new:
            if ob.parent is None and ob.name.split(".")[0] in ("sit", "sleep", "walk") and ob.name.split(".")[0] != keep:
                drop += [ob] + list(ob.children_recursive)
        for c in drop:
            new.discard(c)
        for c in drop:
            bpy.data.objects.remove(c)
    emp = bpy.data.objects.new("imp", None)
    bpy.context.scene.collection.objects.link(emp)
    for ob in new:
        if ob.parent is None:
            ob.parent = emp
    emp.location = loc
    emp.rotation_euler = (0, 0, rot)
    emp.scale = (sc, sc, sc)
    return emp


def logs(c, n=3, L=0.42, r=0.045, yarn="yarn_red", axis="x"):
    """毛糸で縛った薪の束（焚き火セット）"""
    for i in range(n):
        dx = (i - (n - 1) / 2) * r * 2.05
        dz = r if i % 2 == 0 else r * 2.6
        a, b = (V(-L / 2, dx, dz), V(L / 2, dx, dz)) if axis == "x" else (V(dx, -L / 2, dz), V(dx, L / 2, dz))
        rope("log", "wood_dark" if i % 2 else "wood", [c + a, c + b], r=r, sides=10)
    for s in (-0.3, 0.3):
        o = V(s * L, 0, 0) if axis == "x" else V(0, s * L, 0)
        ring = [c + o + (V(0, math.cos(t) * r * 2.9, r * 1.7 + math.sin(t) * r * 2.1) if axis == "x" else V(math.cos(t) * r * 2.9, 0, r * 1.7 + math.sin(t) * r * 2.1))
                for t in [2 * math.pi * k / 16 for k in range(17)]]
        rope("tie", yarn, ring, r=0.009)


def pegs(c, n=7, h=0.36, tilt=0.18, rnd=None):
    """木の杭（ペグ）を何本も立てる。頭に毛糸の輪"""
    rnd = rnd or random.Random(3)
    for i in range(n):
        a = 2 * math.pi * i / n
        base = c + V(math.cos(a) * 0.05, math.sin(a) * 0.05, 0)
        top = base + V(math.cos(a) * tilt * h, math.sin(a) * tilt * h, h)
        rope("peg", "wood_light", [base, top], r=0.012, sides=6)
        ring = [top + V(math.cos(t) * 0.022, math.sin(t) * 0.022, -0.03) for t in [2 * math.pi * k / 10 for k in range(11)]]
        rope("peg_loop", ["yarn_red", "felt_navy", "yarn_yellow"][i % 3], ring, r=0.005)


def bucket(c, r=0.16, h=0.26):
    part("bucket", "wood", lambda m: lathe_at(m, [(r, h), (r * 0.9, 0.0)], c, segs=24))
    for z in (0.05, h - 0.04):
        rope("hoop", "hemp", [c + V(math.cos(t) * (r * 0.92 + 0.01 + z * 0.3), math.sin(t) * (r * 0.92 + 0.01 + z * 0.3), z)
                              for t in [2 * math.pi * k / 24 for k in range(25)]], r=0.008)


def rope_coil(c, r=0.16, turns=5, rr=0.014, flat=True):
    pts = []
    for i in range(turns * 24 + 1):
        t = 2 * math.pi * i / 24
        rad = r - 0.012 * i / 24 if flat else r
        pts.append(c + (V(math.cos(t) * rad, math.sin(t) * rad, rr) if flat else V(math.cos(t) * r, (i / 24) * rr * 2.2, math.sin(t) * r)))
    rope("rope_coil", "hemp", pts, r=rr)


def snowshoe(c, rot=0.0, lean=1.25):
    """かんじき: 曲げ木の楕円の輪に、麻ひもの格子"""
    m = C.M("kanjiki", "wood_bent", "doll")
    pts = [V(math.cos(t) * 0.14, math.sin(t) * 0.24, 0) for t in [2 * math.pi * k / 30 for k in range(31)]]
    C.tube(m, pts, 0.014, sides=6)
    o = m.done(subsurf=1)
    o.rotation_euler = (lean, 0, rot)
    o.location = c
    for k in range(-2, 3):
        st = C.M("kanjiki_lace", "hemp", "doll")
        C.tube(st, [V(-0.13, k * 0.07, 0), V(0.13, k * 0.07, 0)], 0.004, sides=4)
        s = st.done()
        s.parent = o


def stones(c, n=5, rnd=None):
    rnd = rnd or random.Random(5)
    for i in range(n):
        p = c + V(rnd.uniform(-0.12, 0.12), rnd.uniform(-0.1, 0.1), 0.03)
        part("stone", ["felt_stone", "felt_stone2", "felt_beige"][i % 3], lambda m, p=p: facet_ball(m, p, (0.05, 0.045, 0.035), 6, 4, 0.005, i), smooth=False)


# ================================================================ ヤク
def build_yak():
    """白いヤクが伏せて休む。前は +Y。体は白いフェルト、毛は生成りの毛糸の房（体の縁から床まで垂れる）、角はフェルトの筒、
    赤いフェルトの鞍掛けに金の糸のなみ縫い、麻の腹帯、針金の鐙（床に寝る）。目は閉じた糸"""
    rnd = random.Random(11)
    part("yak_body", "yak_wool", lambda m: blob(m, V(0, 0, 0.42), (0.42, 0.78, 0.33), 2.4, 2.2, 7))
    part("yak_hump", "yak_wool", lambda m: blob(m, V(0, 0.28, 0.66), (0.3, 0.38, 0.16), 2.2, 2.2, 6))
    # 毛の房: 生成りの太い毛糸。体の縁から床へ垂れ、先は少し外へ広がる（重ねて 2 列）
    for row, (n, zr, rr) in enumerate(((170, (0.46, 0.62), 0.03), (120, (0.3, 0.44), 0.032))):
        for i in range(n):
            t = 2 * math.pi * (i + 0.5 * row) / n + rnd.uniform(-0.015, 0.015)
            ex, ey = math.cos(t), math.sin(t)
            z0 = rnd.uniform(*zr)
            top = V(ex * (0.4 + 0.03 * row), ey * (0.78 + 0.03 * row), z0)
            mid = V(ex * (0.5 + 0.02 * row), ey * (0.86 + 0.02 * row), z0 * 0.5)
            end = V(ex * (0.56 + rnd.uniform(0, 0.05)), ey * (0.93 + rnd.uniform(0, 0.04)), 0.0)
            rope("yak_lock", "yarn_yak", [top + V(0, 0, 0.03), top, mid, end, end + V(0, 0, -0.03)], r=rr * rnd.uniform(0.85, 1.15), sides=7)
    for i in range(190):   # 背中とこぶを覆う房: 背骨から両脇へ寝かせる
        a = rnd.uniform(-1.3, 1.3)
        y = rnd.uniform(-0.62, 0.62)
        sgn = 1 if a >= 0 else -1
        zt = 0.72 + 0.11 * math.exp(-((y - 0.28) / 0.3) ** 2)   # こぶの高さ
        b0 = V(math.sin(a) * 0.3, y, zt + 0.05 * math.cos(a))
        b1 = V(math.sin(a) * 0.3 + sgn * 0.16, y - 0.02, zt - 0.11 + 0.03 * math.cos(a))
        rope("yak_lock_back", "yarn_yak", [b0 - V(sgn * 0.03, 0, -0.02), b0, b1, b1 + V(sgn * 0.02, 0, -0.04)], r=0.026, sides=7)
    part("yak_neck", "yak_wool", lambda m: blob(m, V(0, 0.8, 0.52), (0.26, 0.22, 0.22), 2.2, 2.2, 6))
    for i in range(40):   # 首の房
        t = rnd.uniform(-2.2, 2.2)
        b0 = V(math.sin(t) * 0.25, 0.82 + rnd.uniform(-0.08, 0.08), 0.55 + math.cos(t) * 0.18)
        rope("yak_lock_neck", "yarn_yak", [b0, b0 + V(math.sin(t) * 0.06, 0.04, -0.2), V(b0.x * 1.3, b0.y + 0.06, 0.0)], r=0.026, sides=7)
    # 折った前脚と蹄
    for s in (1, -1):
        part("yak_leg", "yak_wool", lambda m, s=s: blob(m, V(0.2 * s, 0.68, 0.09), (0.1, 0.22, 0.08), 2.2, 2.2, 5))
        part("yak_hoof", "hoof", lambda m, s=s: facet_ball(m, V(0.2 * s, 0.9, 0.05), (0.06, 0.05, 0.045), 6, 4, 0.003, 20 + s), smooth=False)
    # 頭: 少し下げ、鼻づらは灰色のフェルト、額から毛の房が垂れる
    hc = V(0, 1.02, 0.5)
    head = part("yak_head", "yak_wool", lambda m: blob(m, hc, (0.18, 0.26, 0.19), 2.2, 2.2, 6))
    part("yak_muzzle", "yak_muzzle", lambda m: blob(m, hc + V(0, 0.2, -0.09), (0.11, 0.09, 0.09), 2.2, 2.2, 5))
    part("yak_nose", "hoof", lambda m: ball(m, hc + V(0, 0.285, -0.08), 0.022, 1.6, 0.5, 0.7))
    thread_eyes(head, hc + V(0, 0, 0.02), 0.095, 0.0, 0.014)
    for i in range(16):
        x = -0.12 + 0.24 * i / 15
        b = hc + V(x, 0.12, 0.15)
        rope("yak_forelock", "yarn_yak", [b, b + V(x * 0.2, 0.08, -0.12), b + V(x * 0.3, 0.1, -0.2 - rnd.uniform(0, 0.06))], r=0.014, sides=6)
    for s in (1, -1):
        part("yak_ear", "yak_wool", lambda m, s=s: blob(m, hc + V(0.19 * s, -0.04, 0.06), (0.07, 0.03, 0.035), 2.2, 2.2, 4))
        hp = [hc + V(0.12 * s, -0.02, 0.09), hc + V(0.28 * s, 0.0, 0.08), hc + V(0.41 * s, 0.03, 0.15), hc + V(0.45 * s, 0.03, 0.27), hc + V(0.4 * s, 0.0, 0.36)]
        rope("yak_horn", "felt_horn", hp, r=[0.05, 0.044, 0.034, 0.024, 0.012], sides=10)
        rope("yak_horn_tip", "felt_horn_in", hp[-2:], r=[0.016, 0.009], sides=8)
    # しっぽ
    for i in range(6):
        b = V(rnd.uniform(-0.03, 0.03), -0.8, 0.52)
        rope("yak_tail", "yarn_yak", [b, b + V(0, -0.1, -0.2), b + V(rnd.uniform(-0.04, 0.04), -0.14, -0.5)], r=0.016, sides=6)
    # 鞍掛け: 赤いフェルトを背に掛けて両脇へ垂らす。縁に金の糸のなみ縫い
    def blanket(m):
        rows = []
        for j in range(9):
            y = -0.05 + 0.55 * j / 8
            row = []
            for i in range(21):
                th = -1.95 + 3.9 * i / 20
                row.append(m.bm.verts.new((0.52 * math.sin(th), y, 0.5 + 0.28 * math.cos(th))))
            rows.append(row)
        for j in range(8):
            for i in range(20):
                m.bm.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
    part("yak_blanket", "felt_red", blanket, smooth=True, solid=0.012)
    for s in (1, -1):
        th = 1.95 * s
        edge = [V(0.535 * math.sin(th), -0.05 + 0.55 * k / 12, 0.5 + 0.29 * math.cos(th) + 0.02) for k in range(13)]
        stitch("yak_blanket_st", edge, [V(math.sin(th), 0, 0)] * 13, "thread_gold", dash=0.02, gap=0.012, r=0.004)
    rope("yak_girth", "felt_brown", [V(0.53 * math.sin(t), 0.22, 0.5 + 0.3 * math.cos(t)) for t in [-2.0 + 4.0 * k / 20 for k in range(21)]], r=0.014)
    stir = [V(0.6 + 0.07 * math.cos(t) * 0.2, 0.22 + 0.07 * math.cos(t), 0.08 + 0.07 * math.sin(t)) for t in [2 * math.pi * k / 16 for k in range(17)]]
    rope("yak_stirrup", "wire", stir, r=0.008)
    rope("yak_stirrup_strap", "felt_brown", [V(0.54, 0.22, 0.4), V(0.6, 0.22, 0.15)], r=0.012)


# ================================================================ 出店
def stall_pack():
    """背負子と茣蓙: 麻の茣蓙（縁に赤い糸）に品物を並べ、後ろに荷を積んだ木の背負子"""
    cx = -1.8
    part("mat", "mat_hemp", lambda m: blob(m, V(cx, 0.15, 0.012), (1.25, 0.6, 0.012), 6.0, 3.0, 4))
    edge = [V(cx + 1.2 * math.cos(t), 0.15 + 0.55 * math.sin(t), 0.026) for t in [2 * math.pi * k / 60 for k in range(61)]]
    stitch("mat_st", edge, [V(0, 0, 1)] * 61, "thread_red", dash=0.03, gap=0.02, r=0.005)
    # 背負子: 2 本の柱、横木、背当ての麻ひも
    for s in (-0.42, 0.42):
        rope("frame_pole", "wood_bent", [V(cx + s, -0.42, 0), V(cx + s, -0.47, 1.65)], r=0.03)
    for z in (0.35, 0.8, 1.25, 1.6):
        rope("frame_bar", "wood_bent", [V(cx - 0.45, -0.44 - z * 0.03, z), V(cx + 0.45, -0.44 - z * 0.03, z)], r=0.022)
    # 背負子に積んだ荷: 薪の束、縄の輪、白い毛皮の巻き、ペグの束、提灯
    logs(V(cx, -0.3, 0.37), 5, L=0.8, r=0.05, yarn="yarn_red")
    logs(V(cx, -0.3, 0.82), 4, L=0.75, r=0.05, yarn="yarn_yellow")
    rope_coil(V(cx - 0.2, -0.32, 1.12), r=0.17, turns=6, rr=0.016, flat=False)
    part("pelt_roll", "yak_wool", lambda m: C.tube(m, [V(cx + 0.05, -0.32, 1.42), V(cx + 0.4, -0.32, 1.42)], 0.11, sides=14), subsurf=1)
    rope("pelt_tie", "felt_brown", [V(cx + 0.22 + 0.11 * math.cos(t) * 0, -0.32 + 0.115 * math.cos(t), 1.42 + 0.115 * math.sin(t)) for t in [2 * math.pi * k / 16 for k in range(17)]], r=0.01)
    imp("props/lantern/lantern_box.glb", V(cx + 0.45, -0.38, 1.25), 0.0, 0.55)
    imp("props/hearth/kettle_tin.glb", V(cx - 0.32, -0.3, 1.27), 0.5, 0.4)
    # 茣蓙の上: 焚き火セット 3 つ、桶に立てたペグ、かんじき、フェルトの石、縄の輪
    for i, y in enumerate(("yarn_red", "yarn_yellow", "felt_navy")):
        logs(V(cx - 0.85 + i * 0.32, 0.4, 0.025), 3, L=0.32, r=0.035, yarn=y, axis="y")
    stones(V(cx - 0.55, 0.05, 0.02))
    bucket(V(cx + 0.35, 0.3, 0.02))
    pegs(V(cx + 0.35, 0.3, 0.05), 9, 0.4)
    pegs(V(cx + 0.75, 0.42, 0.03), 5, 0.3, 0.55)
    rope_coil(V(cx + 0.85, 0.05, 0.02), r=0.15, turns=5)
    snowshoe(V(cx - 1.25, -0.25, 0.3), 0.3)
    snowshoe(V(cx - 1.05, -0.3, 0.3), -0.2)
    # 立て札: 木の板に、炎とペグのフェルトのアップリケ（文字なし）
    rope("sign_pole", "wood_dark", [V(cx + 1.15, -0.3, 0), V(cx + 1.15, -0.3, 1.25)], r=0.025)
    part("sign_board", "wood", lambda m: blob(m, V(cx + 1.15, -0.27, 1.1), (0.28, 0.02, 0.2), 6.0, 6.0, 3))
    part("sign_flame", "felt_flame_r", lambda m: blob(m, V(cx + 1.03, -0.245, 1.1), (0.07, 0.008, 0.12), 2.2, 2.2, 3))
    part("sign_flame_in", "felt_flame_y", lambda m: blob(m, V(cx + 1.03, -0.236, 1.07), (0.035, 0.008, 0.06), 2.2, 2.2, 3))
    rope("sign_peg", "wood_light", [V(cx + 1.25, -0.24, 1.0), V(cx + 1.3, -0.24, 1.22)], r=0.018)


def stall_sled():
    """ソリの屋台: 木のソリの台に段を組み、縞のフェルトの日よけ。日よけの横木から提灯と縄の輪を吊る"""
    cx = -1.8
    for s in (-0.5, 0.5):   # 滑り木（前が反る）
        pts = [V(cx - 1.2, s, 0.04), V(cx + 0.9, s, 0.04), V(cx + 1.15, s, 0.12), V(cx + 1.25, s, 0.3)]
        rope("runner", "wood_bent", pts, r=0.03)
        for x in (-0.9, 0.0, 0.8):
            rope("strut", "wood", [V(cx + x, s, 0.04), V(cx + x, s * 0.92, 0.28)], r=0.025)
    part("deck", "wood", lambda m: blob(m, V(cx - 0.15, 0.0, 0.3), (1.1, 0.58, 0.03), 6.0, 6.0, 3))
    part("deck_felt", "felt_red", lambda m: blob(m, V(cx - 0.15, 0.05, 0.335), (1.05, 0.5, 0.008), 6.0, 6.0, 3))
    part("tier", "wood", lambda m: blob(m, V(cx - 0.15, -0.28, 0.62), (1.05, 0.2, 0.025), 6.0, 6.0, 3))
    for x in (-1.15, 0.85):
        rope("tier_leg", "wood_dark", [V(cx + x, -0.28, 0.33), V(cx + x, -0.28, 0.6)], r=0.02)
        rope("awning_pole", "wood_dark", [V(cx + x, -0.5, 0.3), V(cx + x, -0.5, 1.95)], r=0.03)
        rope("awning_pole_f", "wood_dark", [V(cx + x, 0.55, 0.3), V(cx + x, 0.55, 1.75)], r=0.025)
    rope("awning_bar", "wood_dark", [V(cx - 1.2, 0.55, 1.75), V(cx + 0.9, 0.55, 1.75)], r=0.025)
    # 日よけ: 赤と生成りの縞のフェルト。前の縁は波形
    for i in range(10):
        x0 = cx - 1.2 + 2.1 * i / 10
        x1 = cx - 1.2 + 2.1 * (i + 1) / 10
        role = "awning_red" if i % 2 == 0 else "awning_cream"

        def strip(m, x0=x0, x1=x1):
            vs = [m.bm.verts.new(p) for p in (V(x0, -0.55, 1.98), V(x1, -0.55, 1.98), V(x1, 0.62, 1.74), V(x0, 0.62, 1.74))]
            m.bm.faces.new(vs)
            sc = [m.bm.verts.new(p) for p in (V(x0, 0.62, 1.74), V(x1, 0.62, 1.74), V((x0 + x1) / 2, 0.64, 1.6))]
            m.bm.faces.new(sc)
        part("awning", role, strip, smooth=False, solid=0.01)
    # 品物: 下の段に焚き火セットと石、上の段に桶のペグと縄の輪
    for i, y in enumerate(("yarn_red", "yarn_yellow", "felt_navy", "yarn_red")):
        logs(V(cx - 0.95 + i * 0.3, 0.15, 0.345), 3, L=0.3, r=0.034, yarn=y, axis="y")
    stones(V(cx + 0.35, 0.2, 0.34))
    bucket(V(cx + 0.55, -0.28, 0.645), r=0.13, h=0.22)
    pegs(V(cx + 0.55, -0.28, 0.67), 9, 0.36)
    rope_coil(V(cx - 0.75, -0.28, 0.645), r=0.15, turns=5)
    logs(V(cx - 0.25, -0.28, 0.645), 4, L=0.5, r=0.04, yarn="yarn_yellow")
    # 吊るす物: 提灯 2 つ、縄の輪、白い毛皮の巻き
    imp("props/lantern/lantern_paper.glb", V(cx - 0.9, 0.55, 1.35), 0.0, 0.55)
    imp("props/lantern/lantern_box.glb", V(cx + 0.6, 0.55, 1.35), 0.0, 0.55)
    rope_coil(V(cx - 0.2, 0.55, 1.3), r=0.14, turns=4, rr=0.012, flat=False)
    rope("hang", "hemp", [V(cx - 0.2, 0.55, 1.75), V(cx - 0.2, 0.55, 1.44)], r=0.006)
    snowshoe(V(cx + 1.25, 0.1, 0.3), 1.4, 1.35)
    snowshoe(V(cx + 1.3, -0.15, 0.3), 1.6, 1.35)


# ================================================================ ミニオンの柵と遊び場
def pen(pets=True):
    """毛糸を巻いた木の柵（4.0 × 3.2 m）。前（+Y）に入口。中に編んだ敷物 2 枚、フェルトのトンネル、丸太の切り株、
    木の坂、毛糸玉、薪かごの寝床 2 つ、水桶と餌の器。ミニオンが遊んで、寝て、食べている"""
    c = V(-5.3, -1.1, 0)
    w, d = 4.0, 3.2
    posts = []
    for i in range(6):
        x = c.x - w / 2 + w * i / 5
        posts += [V(x, c.y - d / 2, 0), V(x, c.y + d / 2, 0)]
    for j in range(1, 4):
        y = c.y - d / 2 + d * j / 4
        posts += [V(c.x - w / 2, y, 0), V(c.x + w / 2, y, 0)]
    for p in posts:
        if abs(p.y - (c.y + d / 2)) < 0.01 and abs(p.x - c.x) < 0.5:
            continue   # 入口
        rope("pen_post", "wood_dark", [p, p + V(0, 0, 0.62)], r=0.035, sides=8)
        rope("pen_cap", "yarn_red", helix(p + V(0, 0, 0.0), 0.04, 0.5, 0.58, 3), r=0.008)
    for z in (0.25, 0.5):
        for (a, b) in ((V(-w / 2, -d / 2, z), V(w / 2, -d / 2, z)), (V(-w / 2, -d / 2, z), V(-w / 2, d / 2, z)), (V(w / 2, -d / 2, z), V(w / 2, d / 2, z)),
                       (V(-w / 2, d / 2, z), V(-0.4, d / 2, z)), (V(0.4, d / 2, z), V(w / 2, d / 2, z))):
            rope("pen_rail", "wood", [c + a, c + b], r=0.022, sides=8)
    imp("props/room/rug_braided_cool.glb", c + V(-0.8, 0.3, 0.005), 0.0, 0.8)
    imp("props/room/rug_braided_warm.glb", c + V(1.0, -0.5, 0.005), 0.6, 0.7)
    # フェルトのトンネル（半分の筒に、縫い目の輪）
    def tunnel(m):
        for i in range(13):
            pass
        C.lathe(m, [(0.28, 0.0), (0.28, 0.9)], segs=24, closed=False)
    t = part("tunnel", "felt_green", tunnel, solid=0.02)
    t.rotation_euler = (math.pi / 2, 0, 0.3)
    t.location = c + V(1.2, 0.7, 0.0)
    for x, h, r in ((-1.5, 0.22, 0.14), (-1.2, 0.34, 0.12), (-0.95, 0.16, 0.15)):   # 切り株
        part("stump", "trunk", lambda m, x=x, h=h, r=r: lathe_at(m, [(r, h), (r * 1.1, 0.0)], c + V(x, -1.0, 0), segs=16))
        part("stump_top", "wood_light", lambda m, x=x, h=h, r=r: blob(m, c + V(x, -1.0, h), (r * 0.95, r * 0.95, 0.008), 2.0, 2.0, 3))
    ramp = part("ramp", "wood", lambda m: blob(m, V(0, 0, 0), (0.5, 0.18, 0.02), 6.0, 6.0, 3))   # 切り株へ渡した木の坂
    ramp.location = c + V(-0.75, -1.0, 0.15)
    ramp.rotation_euler = (0, 0.32, 0)
    for i, (x, y, col) in enumerate(((0.4, 0.1, "yarn_red"), (0.7, 0.4, "yarn_yellow"), (-0.3, 0.8, "felt_navy"))):   # 毛糸玉
        part("yarn_ball", col, lambda m, x=x, y=y: ball(m, c + V(x, y, 0.07), 0.07))
        rope("yarn_wrap", col, helix(c + V(x, y, 0.0), 0.072, 0.0, 0.14, 5), r=0.006)
    imp("props/hearth/log_basket.glb", c + V(-1.4, 0.95, 0), 0.4, 0.55)
    imp("props/hearth/log_basket.glb", c + V(-0.9, 1.15, 0), -0.3, 0.5)
    part("trough", "wood", lambda m: blob(m, c + V(1.55, -1.25, 0.1), (0.35, 0.12, 0.1), 6.0, 6.0, 3))
    part("water", "felt_navy", lambda m: blob(m, c + V(1.55, -1.25, 0.19), (0.31, 0.09, 0.01), 6.0, 6.0, 3))
    for i in range(3):
        imp("props/cup.glb", c + V(0.9 + i * 0.22, -1.2, 0), 0.0, 0.6)
    # ミニオン（ゲームでは mountain_man.gd が pals の形を置いて動かすので、書き出しには入れない）
    if not pets:
        return
    for key, at, rot, pose in (("kit", V(-1.4, 0.95, 0.16), 2.4, "sleep"), ("chiyo_fox", V(-0.9, 1.15, 0.14), 3.5, "sleep"),
                               ("frog", V(-1.2, -1.0, 0.34), 0.6, "sit"), ("rabbit", V(0.3, 0.4, 0.0), 2.6, "walk"),
                               ("yarn", V(0.7, 0.1, 0.0), 1.2, "walk"), ("pony", V(-0.4, -0.3, 0.0), 2.0, "sit"),
                               ("peacock", V(1.0, -0.9, 0.0), 2.8, "walk")):
        imp("pals/pet_%s.glb" % key, c + at, rot, 1.0, keep=pose)


YAK_AT = V(0.4, -1.8, 0)          # ヤクの所（山師の座標）
YAK_TURN = -math.pi / 2 + 0.35    # 頭を右手（+X、南）へ、少し客の方へ


def floor():
    m = C.M("floor", "wood", "doll")
    vs = [m.bm.verts.new(p) for p in (V(-9, -4.5, 0), V(4, -4.5, 0), V(4, 4, 0), V(-9, 4, 0))]
    m.bm.faces.new(vs)
    m.done()


def stage(size):
    C.light(elev=40.0, az=-120.0)
    bpy.data.objects["sun"].data.color = (1.0, 0.82, 0.62)
    C.setup_render(size)
    sc = bpy.context.scene
    sc.eevee.taa_render_samples = A.samples
    sc.view_settings.exposure = -0.6


if A.part and A.export:
    C.reset()
    paper_roles()
    if A.part == "yak":
        g = group_of(build_yak, "yak")
        g.location = YAK_AT
        g.rotation_euler = (0, 0, YAK_TURN)
        name = "yama_yak"
    elif A.part == "stall":
        group_of(stall_pack if A.stall == "pack" else stall_sled, "stall")
        name = "yama_stall"
    else:
        group_of(lambda: pen(False), "pen")
        name = "yama_pen"
    sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..")))
    import rig_export  # noqa: E402
    rig_export.export_static(name, A.export)
    sys.exit(0)

if A.yak_only:
    C.reset()
    paper_roles()
    build_yak()
    stage(A.size)
    tgt = V(0, 0.2, 0.4)
    os.makedirs(os.path.join(HERE, "renders"), exist_ok=True)
    for name, d in (("yak-quarter", V(2.4, 2.6, 1.2)), ("yak-side", V(3.4, 0.2, 0.9))):
        C.render(tgt + d, tgt, 60, os.path.join(HERE, "renders", name + ".png"))
    sys.exit(0)

C.reset()
paper_roles()
floor()
group_of(build_yamaotoko, "man")
yak = group_of(build_yak, "yak")
yak.location = YAK_AT
yak.rotation_euler = (0, 0, YAK_TURN)
group_of(stall_pack if A.stall == "pack" else stall_sled, "stall")
group_of(pen, "pen")
stage(A.size)
out = os.path.join(HERE, "renders")
os.makedirs(out, exist_ok=True)
for v in A.views.split(","):
    if v == "high":
        C.render(V(1.8, 6.2, 5.2), V(-2.6, -0.9, 0.3), 30, os.path.join(out, "%s-%s-high.png" % (A.prefix, A.stall)))
    elif v == "eye":
        C.render(V(0.6, 4.6, 1.55), V(-1.3, -0.6, 0.7), 32, os.path.join(out, "%s-%s-eye.png" % (A.prefix, A.stall)))
    elif v == "top":
        sc = bpy.context.scene
        cam = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        if cam.name not in sc.collection.objects:
            sc.collection.objects.link(cam)
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 10.5
        cam.location = V(-2.6, -0.6, 12)
        cam.rotation_euler = (0, 0, -math.pi / 2)   # 絵の上が山師の左手（北）
        sc.camera = cam
        sc.render.filepath = os.path.join(out, "%s-%s-top.png" % (A.prefix, A.stall))
        bpy.ops.render.render(write_still=True)
