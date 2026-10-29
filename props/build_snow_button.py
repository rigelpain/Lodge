"""雪に縫い留められたボタン（game/snow_buttons.gd）を Blender で組む。斜面の雪に糸で「×」にゆるく縫い付けてあり、
ソリの滑り木が上を通ると糸が切れて取れる（お金）。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snow_button.py -- --views quarter,top,close --prefix props/renders/50-snow-button

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snow_button.py -- --look flat --export game/props/snow_button

2026-10-30 代表「斜面の雪に、大きな木のボタンが糸で×にゆるく縫い付けてある」から。
  snow_button      直径 0.5 m の丸い木のボタン。縁が少し盛り上がり、まんなかは浅い皿。穴は 4 つ
× の糸と、ほどけた糸の端はゲームで描く（風にそよぎ、切れるので）。
原点は底のまんなか（雪の高さ）。目印: hole_0〜3（穴の口。0 と 2、1 と 3 が向かい合い、× はこの組で渡す）。
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）"))])
K.setup(A, fiber=2.0, scale=1.0, tris=900)


def holes(P, d, r, z):
    """4 つの穴: 暗い穴の底と、口のまわりの少し明るい木の縁。穴の口の目印を置く"""
    for k in range(4):
        a = math.pi / 4 + math.pi / 2 * k
        x, y = d * math.cos(a), d * math.sin(a)
        K.disc(P, "felt_charcoal", (x, y, z - 0.002), r, 0.006, segs=14)
        K.ring(P, "wood_light", (x, y, z), r + 0.002, 0.004, n=16)
        P.mark("hole_%d" % k, (x, y, z + 0.004))


def snow_button(name):
    P = K.Parts(name, kind="snow_button")
    R = 0.25
    # 断面（半径, 高さ）: まんなかの浅い皿 → 盛り上がった縁 → 丸い外の縁 → 底
    prof = [(0.0, 0.036), (0.06, 0.037), (0.11, 0.041), (0.16, 0.050), (0.19, 0.057), (0.215, 0.058),
            (0.236, 0.053), (R, 0.040), (R, 0.018), (0.243, 0.006), (0.225, 0.0), (0.0, 0.0)]
    K.lathe(P, "button", prof, segs=40)
    K.ring(P, "wood_dark", (0, 0, 0.0475), 0.152, 0.0035, n=48)   # 皿と縁の境の、彫った溝
    holes(P, 0.068, 0.024, 0.038)
    P.finish()


snow_button("snow_button")

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    R["snow_button"].location = (0.0, 0.0, 0.0)
    K.room(floor_size=4.0, wall_y=1.2)
    K.interior_light(0.9)
    cams = {
        "quarter": ((0.55, -0.85, 0.6), (0.0, 0.0, 0.03), 50),
        "top": ((0.0, 0.0, 1.4), (0.0, 0.0, 0.0), 40),
        "close": ((0.2, -0.65, 0.45), (0.0, 0.1, 0.03), 60),
    }
    K.render_views(A, cams)
