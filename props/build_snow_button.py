"""お金のボタン 4 段と、ボタンの糸を切る裁ちばさみを Blender で組む（game/snow_buttons.gd・design/snow-buttons/README.md）。
斜面の雪に糸で「×」にゆるく縫い付けてあり、ソリの滑り木が上を通るか、歩いて裁ちばさみで糸を切ると取れる。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snow_button.py -- --views line,close,shears --prefix props/renders/50-snow-button

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snow_button.py -- --look flat --export game/props/snow_button

2026-10-30 代表「斜面の雪に、大きな木のボタンが糸で×にゆるく縫い付けてある」「お金のボタンを 4 段にする」から。
文字を使わず、色・光り方・穴の数・大きさで見分ける（値打ちが上がるほど小さく薄くなり、光る。螺鈿だけは別格に黒く大きめ）:
  snow_button         1     木。直径 0.5 m、厚い。縁が少し盛り上がり、まんなかは浅い皿。穴 2 つ。つやなし
  snow_button_brass   10    真鍮。直径 0.42 m。ふちに刻み（ぎざぎざ）、まんなかが少しくぼむ。穴 4 つ。きらっと光る
  snow_button_pearl   100   白蝶貝。直径 0.38 m、薄い。白く、見る向きで虹色に光る。穴 4 つ
  snow_button_raden   1000  螺鈿。直径 0.46 m。漆黒の丸い盛り上がりに、貝の小片が花の形にはめ込まれ、虹色にきらめく。
                            穴 4 つを真鍮の輪で縁取る
光る素材（brass・pearl・lacquer・shell・steel）は焼かずに役割の名前で書き出し、Godot の look.gd（shine）が光らせる。
原点は底のまんなか（雪の高さ）。目印: hole_0〜（穴の口。穴 4 つは 0 と 2、1 と 3 が向かい合い、× はこの組で渡す。穴 2 つは 0 と 1）。
× の糸と、ほどけた糸の端はゲームで描く（風にそよぎ、切れるので）。

  shears_a・shears_b  裁ちばさみの片刃ずつ（開け閉めするので 2 つ）。原点はかしめ（要）。刃は前（+Y）、黒い持ち手は後ろ。
                      a は右の刃と上の持ち手（かしめの真鍮のねじ付き）、b は左の刃と下の持ち手。長さ 0.46 m
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）"))])
K.setup(A, fiber=2.0, scale=1.0, tris=900)


def holes(P, d, r, z, n=4, rim="wood_light"):
    """穴: 暗い穴の底と、口のまわりの縁。穴の口の目印を置く。n = 2 なら左右に 2 つ"""
    for k in range(n):
        a = math.pi / 4 + math.pi / 2 * k if n == 4 else math.pi * k
        x, y = d * math.cos(a), d * math.sin(a)
        K.disc(P, "felt_charcoal", (x, y, z - 0.002), r, 0.006, segs=14)
        K.ring(P, rim, (x, y, z), r + 0.002, 0.004, n=16)
        P.mark("hole_%d" % k, (x, y, z + 0.004))


def height_on(prof, r):
    """断面（半径, 高さ）の上の面の、半径 r での高さ"""
    top = [p for p in prof if p[1] > 0.0]
    for (r0, z0), (r1, z1) in zip(top, top[1:]):
        if r0 <= r <= r1:
            return z0 + (z1 - z0) * (r - r0) / max(r1 - r0, 1e-6)
    return top[-1][1]


def snow_button(name):
    """1: 木。穴 2 つ"""
    P = K.Parts(name, kind="snow_button", value=1)
    R = 0.25
    prof = [(0.0, 0.036), (0.06, 0.037), (0.11, 0.041), (0.16, 0.050), (0.19, 0.057), (0.215, 0.058),
            (0.236, 0.053), (R, 0.040), (R, 0.018), (0.243, 0.006), (0.225, 0.0), (0.0, 0.0)]
    K.lathe(P, "button", prof, segs=40)
    K.ring(P, "wood_dark", (0, 0, 0.0475), 0.152, 0.0035, n=48)   # 皿と縁の境の、彫った溝
    holes(P, 0.055, 0.026, 0.038, n=2)
    P.finish()


def snow_button_brass(name):
    """10: 真鍮。ふちに刻み、穴 4 つ"""
    P = K.Parts(name, kind="snow_button", value=10)
    R = 0.21
    prof = [(0.0, 0.030), (0.08, 0.031), (0.13, 0.036), (0.16, 0.044), (0.185, 0.047), (0.2, 0.044),
            (R, 0.034), (R, 0.012), (0.203, 0.003), (0.19, 0.0), (0.0, 0.0)]
    K.lathe(P, "brass", prof, segs=48)
    for k in range(60):   # ふちの刻み: 小さな山を一周
        a = 2 * math.pi * k / 60
        K.box(P, "brass", (R * math.cos(a), R * math.sin(a), 0.023), (0.012, 0.007, 0.02), rot=(a, "Z"))
    K.ring(P, "brass", (0, 0, 0.040), 0.125, 0.004, n=48)
    holes(P, 0.05, 0.017, 0.032, rim="brass")
    P.finish()


def snow_button_pearl(name):
    """100: 白蝶貝。薄く、穴 4 つ"""
    P = K.Parts(name, kind="snow_button", value=100)
    R = 0.19
    prof = [(0.0, 0.018), (0.08, 0.019), (0.13, 0.022), (0.165, 0.026), (0.182, 0.025), (R, 0.018),
            (R, 0.008), (0.184, 0.002), (0.17, 0.0), (0.0, 0.0)]
    K.lathe(P, "pearl", prof, segs=48)
    K.ring(P, "pearl", (0, 0, 0.0235), 0.15, 0.0025, n=48)
    holes(P, 0.042, 0.014, 0.019, rim="pearl")
    P.finish()


def snow_button_raden(name):
    """1000: 螺鈿。漆黒の盛り上がりに、貝の小片を花の形に。穴 4 つを真鍮の輪で"""
    P = K.Parts(name, kind="snow_button", value=1000)
    R = 0.23
    prof = [(0.0, 0.05), (0.06, 0.051), (0.12, 0.054), (0.17, 0.056), (0.2, 0.052), (0.222, 0.044),
            (R, 0.032), (R, 0.012), (0.222, 0.003), (0.205, 0.0), (0.0, 0.0)]
    K.lathe(P, "lacquer", prof, segs=48)
    rnd = random.Random(7)

    def chip(r, a, size, rot):
        """貝の小片: いびつな多角形を、盛り上がりの面に薄く載せる"""
        x, y = r * math.cos(a), r * math.sin(a)
        z = height_on(prof, r)
        poly = []
        m = rnd.choice([4, 5, 6])
        for j in range(m):
            t = 2 * math.pi * j / m + rnd.uniform(-0.3, 0.3)
            rr = size * rnd.uniform(0.6, 1.0)
            poly.append((x + rr * math.cos(t + rot), y + rr * math.sin(t + rot)))
        K.extrude(P, "shell", poly, z - 0.002, z + 0.0035)   # 漆の面（多角形で少しへこむ）より上に出す

    for k in range(6):   # 花びら 6 枚: 小片を 4 つずつ放射に
        a = 2 * math.pi * k / 6
        for j, r in enumerate((0.095, 0.125, 0.152, 0.176)):
            chip(r, a + rnd.uniform(-0.05, 0.05), 0.017 + 0.005 * (j % 2), rnd.uniform(0, 3))
        chip(0.15, a + math.pi / 6, 0.009, rnd.uniform(0, 3))   # 花びらのあいだの小さな粒
    for k in range(18):   # ふちの一周の細かな粒
        a = 2 * math.pi * k / 18 + 0.1
        chip(0.205, a, 0.006, rnd.uniform(0, 3))
    holes(P, 0.045, 0.014, 0.052, rim="brass")
    P.finish()


def shears(name, side):
    """裁ちばさみの片刃。side = 1 は右の刃（上の持ち手）、-1 は左の刃（下の持ち手）。かしめが原点、刃は +Y"""
    P = K.Parts(name, kind="shears")
    z = 0.006 * side   # 2 枚の刃を少し重ねる
    L, W = 0.27, 0.032
    blade = [(0.0, -0.01), (side * W * 0.6, 0.03), (side * W * 0.45, L * 0.7), (side * 0.004, L), (-side * 0.006, L * 0.96),
             (-side * 0.008, 0.02)]
    if side < 0:
        blade.reverse()   # 面の向きをそろえる
    K.extrude(P, "steel", blade, z - 0.003, z + 0.003)
    # 持ち手: かしめの後ろへ曲がって伸び、輪になる（黒い漆）
    neck = [(0.0, 0.0, z), (side * 0.012, -0.04, z), (side * 0.03, -0.09, z + 0.004 * side)]
    K.tube(P, "lacquer", neck, 0.009, sides=8)
    cx, cy = side * 0.045, -0.135
    loop = []
    for k in range(25):
        a = 2 * math.pi * k / 24
        loop.append((cx + 0.032 * math.cos(a) * (1.25 if side > 0 else 1.0), cy + 0.045 * math.sin(a), z + 0.004 * side))
    K.tube(P, "lacquer", loop, 0.008, sides=8, caps=False)
    if side > 0:
        K.disc(P, "brass", (0, 0, z + 0.005), 0.009, 0.004, segs=12)   # かしめのねじ
    P.mark("tip", (0, L, z))
    P.finish()


snow_button("snow_button")
snow_button_brass("snow_button_brass")
snow_button_pearl("snow_button_pearl")
snow_button_raden("snow_button_raden")
shears("shears_a", 1)
shears("shears_b", -1)

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    for i, n in enumerate(["snow_button", "snow_button_brass", "snow_button_pearl", "snow_button_raden"]):
        R[n].location = (-0.75 + i * 0.5, 0.0, 0.0)
    for n in ("shears_a", "shears_b"):
        R[n].location = (0.15, -0.55, 0.01)
    R["shears_a"].rotation_euler = (0, 0, -0.25)
    R["shears_b"].rotation_euler = (0, 0, 0.25)
    K.room(floor_size=4.0, wall_y=1.2)
    K.interior_light(0.9)
    cams = {
        "line": ((0.2, -1.6, 1.05), (0.0, 0.0, 0.0), 45),
        "close": ((0.55, -0.55, 0.45), (0.25, 0.0, 0.03), 55),
        "shears": ((0.15, -1.05, 0.7), (0.15, -0.55, 0.0), 45),
    }
    K.render_views(A, cams)
