"""布の見本帳（2026-11-06 代表「見本帖＋自由な色にしてほしい」）。ミシンの近くに立つ、ソリの色と滑りあとを替える所。
形: ぎざぎざに切ったフェルトの布 12 枚を真鍮の輪で綴じて扇に開き、物差しの台で立てる。足もとは針山。布の下の端に紙の札を縫い付ける（字はなし）。
素材は props/common.py と kit.py の本番の物。寸法はゲームの大きさ (m)。正面は -Y（Godot の +Z）。
書き出すと 3 つの glb になる（近づくと扇が開くように、布を台から分けた。2026-11-07 代表「見本帳は近づくと展開される方が良いかも」）:
    sled_book.glb            物差しの台・輪・針山
    sled_book_leaf.glb       白い布 1 枚（上の端のまんなかが原点。game/sled_book.gd が 12 枚に増やして色を付ける）
    sled_book_leaf_trim.glb  布 1 枚ぶんの紙の札と縫い目（色を付けないので分ける）
絵を描くときは、前と同じように扇に開いた形で描く。
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/sled-custom/build_book.py -- --views hero --prefix /path/book --size 900x900
    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/sled-custom/build_book.py -- --export game/props/sled_book
game/sled_book.gd が読む。色の並びは game/sled_book_ui.gd の SWATCHES と同じ。
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(ROOT, "props"))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse()
K.setup(A, fiber=1.5, scale=1.0, tris=6000)
SWATCHES = ["D2553A", "E08A3C", "D8A43E", "8FA84A", "3F6B4A", "2F7F8F", "6F8FB8", "34477E", "7A4A6E", "C97A8A", "EFE6D2", "4A4038"]
for i, h in enumerate(SWATCHES):
    C.HEX["felt_bk%d" % i] = h
C.HEX["paper_bk"] = "F3EBDA"
C.HEX["felt_pin"] = "9E3B2A"

PIN_Z = 2.72               # 綴じの輪の高さ
W = 0.62                   # 布の幅
L = 1.75                   # 布の長さ
SPREAD = 68.0              # 扇の開き（両端の度）


def rot(x, y, deg):
    a = math.radians(deg)
    return (x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a))


def pinked(w, h, deg, z=0.035, step=0.09, pin_z=PIN_Z):
    """上の端のまんなかを原点に、下へ垂れるぎざぎざの布。deg だけ回して、高さ pin_z へ"""
    n = int(w / step)
    m = int(h / step)
    pts = []
    for i in range(n * 2):
        pts.append((-w / 2 + w * i / (n * 2.0), 0.0 if i % 2 == 0 else -z))
    for i in range(m * 2):
        pts.append((w / 2 - (0.0 if i % 2 == 0 else z), -h * i / (m * 2.0)))
    for i in range(n * 2):
        pts.append((w / 2 - w * i / (n * 2.0), -h + (0.0 if i % 2 == 0 else z)))
    for i in range(m * 2):
        pts.append((-w / 2 + (0.0 if i % 2 == 0 else z), -h + h * i / (m * 2.0)))
    out = []
    for x, y in pts:
        rx, ry = rot(x, y, deg)
        out.append((rx, ry + pin_z))
    return out


def leaf(felt_parts, trim_parts, felt_role, deg, y0, pin_z):
    """布 1 枚と、下の端の紙の札・赤い糸、綴じに近い所の縫い目"""
    K.extrude(felt_parts, felt_role, pinked(W, L, deg, pin_z=pin_z)[::-1], 0.0, 0.01, plane="XZ", offset=(0, y0, 0))
    cx, cy = rot(0.0, -L + 0.2, deg)
    a = [rot(x, y, deg) for x, y in [(-0.13, 0.08), (0.13, 0.08), (0.13, -0.08), (-0.13, -0.08)]]
    K.extrude(trim_parts, "paper_bk", [(cx + p[0], cy + p[1] + pin_z) for p in a][::-1], 0.0, 0.004, plane="XZ", offset=(0, y0 - 0.005, 0))
    K.stitch_line(trim_parts, "thread_red", [(cx + a[0][0], y0 - 0.011, cy + a[0][1] + pin_z), (cx + a[1][0], y0 - 0.011, cy + a[1][1] + pin_z)], r=0.006, dash=0.04)
    p0 = rot(-W * 0.42, -0.3, deg)
    p1 = rot(W * 0.42, -0.3, deg)
    K.stitch_line(trim_parts, "thread", [(p0[0], y0 - 0.006, p0[1] + pin_z), (p1[0], y0 - 0.006, p1[1] + pin_z)], r=0.005, dash=0.035)


P = K.Parts("sled_book")
n = len(SWATCHES)
if A.export:
    C.HEX["felt_bk_white"] = "F4F4F4"
    PL = K.Parts("sled_book_leaf", tris=320)
    PT = K.Parts("sled_book_leaf_trim", tris=300)
    leaf(PL, PT, "felt_bk_white", 0.0, 0.0, 0.0)
    PL.finish(fuzz=0.004)
    PT.finish()
else:
    for i in range(n):
        leaf(P, P, "felt_bk%d" % i, -SPREAD + 2.0 * SPREAD * i / (n - 1), -0.03 - 0.012 * i, PIN_Z)

K.ring(P, "brass", (0, -0.2, PIN_Z - 0.05), 0.13, 0.026, axis="Y")

# 物差しの台: 竹色の板 2 本の脚に、墨の目盛り。裏に 1 本の控え
for sx in (-1.0, 1.0):
    a = math.atan2(0.46, PIN_Z)
    K.box(P, "wood_light", (sx * 0.24, 0.02, PIN_Z / 2.0), (0.11, 0.035, PIN_Z / math.cos(a) + 0.1), rot=(-sx * a, "Y"))
    for k in range(9):
        z = 0.35 + k * 0.26
        x = sx * (0.46 - z * 0.46 / PIN_Z)
        K.box(P, "wood_dark", (x, -0.001, z), (0.05 if k % 3 == 0 else 0.03, 0.006, 0.012))
K.box(P, "wood_light", (0, 0.42, PIN_Z / 2.0 - 0.1), (0.11, 0.035, PIN_Z + 0.2), rot=(-0.27, "X"))
K.box(P, "wood_dark", (0, 0.0, PIN_Z - 0.03), (0.3, 0.05, 0.1))

# 足もと: 木の板に載せた大きな針山。待ち針を数本（玉は赤と藍）
K.box(P, "wood_dark", (0, 0.1, 0.04), (1.5, 0.95, 0.08))
K.pbox(P, "felt_pin", (0, 0.05, 0.2), (0.6, 0.28, 0.14), n=3.2, seam_role="thread")
for k, (x, role) in enumerate([(-0.42, "felt_navy"), (-0.2, "felt_yellow"), (0.05, "felt_navy"), (0.3, "felt_yellow"), (0.46, "felt_navy")]):
    y = 0.02 + 0.06 * (k % 2)
    K.dowel(P, "steel", (x, y, 0.28), (x, y, 0.52), 0.008, sides=8)
    K.pbox(P, role, (x, y, 0.54), (0.036, 0.036, 0.036), n=2.2, c=4)

P.finish(fuzz=0.004)

if A.export:
    K.export_all(A.export)
    sys.exit(0)
C.ground(40.0)
C.light(40.0, -30.0)
K.render_views(A, {"hero": ((-1.6, -5.2, 1.9), (0, 0, 1.75), 32)})
