"""画面の表示（HUD）の、立体の小物を Blender で組む。Godot では hud_plates.gd が小さな 3D の場面で描いて、画面に重ねる。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_hud.py -- --views all --prefix props/renders/30-hud

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_hud.py -- --look flat --export game/props/hud

2026-10-29 代表「タグ、刺繍、糸巻き、どれも平面で背景と区別がつかないのが嫌です。少しでも立体のプレートにして、影とか付けて、
マテリアル感がないと安っぽくてかなわないや。Blender で軽く作ってほしい」から。
大きさが場面で変わる板（名札・札・ワッペン・持ち物の列）は Godot で角の丸い板を組み、ここでは形の決まった物だけを作る:
  hud_bobbin   木の糸巻き（ボビン）。正面（-Y、Godot では +Z）に三つ穴の端の板、奥に巻いた糸。半径 0.5
  hud_hoop     刺繍枠。内と外の 2 本の木の輪と、上の真鍮色のねじ。内の半径 1.0
  hud_eyelet   札の穴のはとめ（真鍮色）。外の半径 0.1
軸はどれも Blender の Y（Godot の Z、画面の奥行き）。
"""
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）"))])
K.setup(A, fiber=3.0, scale=1.0, tris=4000)
C.HEX.update({"felt_brass": "C9A24A", "thread_bobbin": "D2553A"})


def bobbin(name):
    """木の糸巻き: 前と後ろの端の板（縁を丸めた円板）、真ん中の軸に巻いた赤い糸。前の板に三つ穴と、軸の穴"""
    P = K.Parts(name, kind="hud")
    R = 0.5
    for y in (-0.16, 0.16):
        K.disc(P, "wood_light", (0, y, 0), R, 0.07, axis="Y", segs=48)
    K.lathe(P, "thread_bobbin", [(0.12, -0.13), (0.40, -0.13), (0.42, -0.08), (0.42, 0.08), (0.40, 0.13), (0.12, 0.13)],
            (0, 0, 0), segs=48, closed=True, rot=(math.pi / 2, "X"))
    for k in range(9):   # 巻いた糸の筋
        y = -0.12 + 0.03 * k
        K.ring(P, "thread_bobbin", (0, y, 0), 0.42, 0.012, axis="Y", n=48)
    for i in range(3):   # 前の板の三つ穴（濃い木の円板を少し沈めて、穴に見せる）
        a = math.pi / 2 + 2 * math.pi * i / 3
        K.disc(P, "wood_dark", (math.cos(a) * 0.17, -0.2, math.sin(a) * 0.17), 0.055, 0.012, axis="Y", segs=16)
    K.disc(P, "wood_dark", (0, -0.2, 0), 0.04, 0.012, axis="Y", segs=16)
    K.stitch_ring(P, "thread", (0, -0.198, 0), 0.40, r=0.006, axis="Y", dash=0.05)
    P.finish()


def hoop(name):
    """刺繍枠: 内の輪と、少し大きい外の輪。上に真鍮色のねじの留め金"""
    P = K.Parts(name, kind="hud")
    R = 1.0
    for (rr, w, y) in ((R + 0.03, 0.045, 0.0), (R + 0.10, 0.05, 0.02)):
        prof = [(rr - w, -0.06 + y), (rr + w, -0.06 + y), (rr + w + 0.01, 0.0 + y), (rr + w, 0.06 + y),
                (rr - w, 0.06 + y), (rr - w - 0.01, 0.0 + y)]
        K.lathe(P, "wood_light", prof + prof[:1], (0, 0, 0), segs=72, closed=False, rot=(math.pi / 2, "X"))   # 輪（断面を閉じる）
    top = R + 0.18
    K.box(P, "wood_light", (0, 0.02, top), (0.16, 0.12, 0.10))
    K.dowel(P, "felt_brass", (-0.16, 0.02, top + 0.02), (0.16, 0.02, top + 0.02), 0.022, sides=12)
    K.disc(P, "felt_brass", (0.18, 0.02, top + 0.02), 0.045, 0.05, axis="X", segs=16)
    P.finish()


def eyelet(name):
    """はとめ: 真鍮色の輪"""
    P = K.Parts(name, kind="hud")
    prof = [(0.055, -0.02), (0.1, -0.02), (0.105, 0.0), (0.1, 0.02), (0.055, 0.02), (0.05, 0.0)]
    K.lathe(P, "felt_brass", prof + prof[:1], (0, 0, 0), segs=24, closed=False, rot=(math.pi / 2, "X"))
    P.finish()


bobbin("hud_bobbin")
hoop("hud_hoop")
eyelet("hud_eyelet")

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    R["hud_bobbin"].location = (-1.6, 0, 1.2)
    R["hud_hoop"].location = (0.8, 0, 1.4)
    R["hud_eyelet"].location = (2.6, 0, 1.2)
    K.room(floor_size=8.0, wall_y=0.6)
    K.interior_light(1.0)
    K.render_views(A, {"all": ((0.4, -6.5, 1.6), (0.4, 0.0, 1.3), 40)})
