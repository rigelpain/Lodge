"""北欧の新聞紙の地の画像をコードで作る（外の画像は使わない。書体は Blender に入っているもの）。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/newsprint.py -- --out person/textures/newsprint.png

Blender の文字で、北欧の言葉に見える作り語（å ä ö ø æ を混ぜる。意味のある言葉にはしない）の段組みを組み、
縦長で太い見出し、段の罫線、囲みの広告、網点の写真を並べて、真上から描いて画像にする。
紙は灰色がかった生成り、インクは濃い墨。文字は貼ったときに読める大きさにする。
"""
import argparse
import math
import os
import random
import sys

import bpy

ap = argparse.ArgumentParser()
ap.add_argument("--out", default="person/textures/newsprint.png")
ap.add_argument("--px", type=int, default=2048)
ap.add_argument("--seed", type=int, default=5)
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(A.seed)
SIZE = 1.0   # 描く紙の一辺（Blender の単位）

ON = ["sk", "bj", "fj", "kv", "st", "tr", "gr", "h", "l", "m", "n", "v", "d", "s", "r", "k", "t", "sn", "dr", "vä"]
NU = ["ö", "ä", "å", "ø", "e", "i", "a", "o", "u", "y", "æ", "ei", "ie"]
CO = ["rn", "ll", "nd", "rk", "g", "n", "t", "ks", "st", "dt", "j", "rd", "", "", "ng"]


def word(lo=1, hi=3):
    w = "".join(rnd.choice(ON) + rnd.choice(NU) + rnd.choice(CO) for _ in range(rnd.randint(lo, hi)))
    return w


def flat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    t = m.node_tree
    t.nodes.clear()
    out = t.nodes.new("ShaderNodeOutputMaterial")
    em = t.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1)
    t.links.new(em.outputs[0], out.inputs[0])
    return m


ink = flat("ink", (0.035, 0.032, 0.03))
grey = flat("grey", (0.22, 0.21, 0.2))
paper_dark = flat("tint", (0.62, 0.6, 0.55))


def text(body, x, y, size, width=None, mat=ink, bold=0.0, squeeze=1.0, align="LEFT"):
    """文字を置き、高さ（下へ何 m 使ったか）を返す。bold は字を少しずらして重ねて太くする量（字の大きさに対する割合）"""
    obs = []
    shifts = [(0.0, 0.0)] if not bold else [(dx * bold * size, dy * bold * size) for dx in (-1, 0, 1) for dy in (-0.5, 0.5)]
    for dx, dy in shifts:
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = body
        cu.size = size
        cu.space_line = 1.0
        if width:
            cu.text_boxes[0].width = width / squeeze
            cu.align_x = align
        ob = bpy.data.objects.new("t", cu)
        ob.location = (x + dx, y + dy, 0)
        ob.scale = (squeeze, 1, 1)
        ob.data.materials.append(mat)
        sc.collection.objects.link(ob)
        obs.append(ob)
    bpy.context.view_layer.update()
    return obs[0].dimensions.y


def rect(x0, y0, x1, y1, mat, z=-0.001):
    bpy.ops.mesh.primitive_plane_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, z))
    p = bpy.context.object
    p.scale = (abs(x1 - x0), abs(y1 - y0), 1)
    p.data.materials.append(mat)
    return p


def frame(x0, y0, x1, y1, t=0.0012):
    rect(x0, y0, x1, y0 + t, ink)
    rect(x0, y1 - t, x1, y1, ink)
    rect(x0, y0, x0 + t, y1, ink)
    rect(x1 - t, y0, x1, y1, ink)


def halftone(x, y, w, h, kind):
    """網点の写真: 山なみと木、または人の影の濃淡"""
    n = 22
    step = w / n
    for i in range(n):
        for j in range(int(h / step)):
            u, v = (i + 0.5) / n, (j + 0.5) * step / h
            if kind == 0:   # 山の稜線と、手前の針葉樹
                ridge = 0.45 + 0.18 * math.sin(u * 7.0) + 0.08 * math.sin(u * 19.0)
                d = 0.75 if v > ridge else 0.25
                if abs((u * 5) % 1 - 0.5) < 0.18 * (1 - v) and v < 0.6:
                    d = 0.9
            else:           # ぼんやりした丸い影
                d = max(0.0, 1.0 - math.hypot(u - 0.5, (v - 0.45) * 1.3) * 2.2) * 0.9 + 0.15
            r = step * 0.5 * math.sqrt(d)
            if r < step * 0.08:
                continue
            bpy.ops.mesh.primitive_circle_add(vertices=6, radius=r, fill_type="NGON",
                                              location=(x + (i + 0.5) * step, y - (j + 0.5) * step, 0))
            bpy.context.object.data.materials.append(ink)


w = bpy.data.worlds.new("paper")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.74, 0.71, 0.63, 1)
sc.world = w

# 段組み: 5 段。見出し・本文・写真・囲み広告・罫線
cols = 5
gut = 0.014
cw = (SIZE - gut * (cols + 1)) / cols
y_top = SIZE / 2 - 0.015
BODY = 0.0135
LEAD = BODY * 1.12
for c in range(cols):
    x = -SIZE / 2 + gut + c * (cw + gut)
    y = y_top
    while y > -SIZE / 2 + 0.04:
        r = rnd.random()
        if r < 0.16:
            hs = rnd.choice((0.034, 0.042, 0.05))
            h = word(1, 2).upper()
            th = text(h, x, y - hs * 0.85, hs, mat=ink, bold=0.035, squeeze=0.72, width=cw)
            y -= max(th, hs * 0.85) + hs * 0.3
            # 小見出し
            th = text(" ".join(word(1, 2) for _ in range(4)), x, y - BODY * 1.2, BODY * 1.2, cw, ink, bold=0.02)
            y -= th + BODY * 1.4
        elif r < 0.25:
            ph = rnd.uniform(0.1, 0.17)
            halftone(x, y, cw, ph, rnd.randint(0, 1))
            y -= ph + 0.006
            th = text(" ".join(word(1, 2) for _ in range(5)), x, y - BODY * 0.9, BODY * 0.85, cw, grey)
            y -= th + BODY * 1.2
        elif r < 0.31:
            # 囲み広告
            bh = rnd.uniform(0.07, 0.11)
            frame(x, y - bh, x + cw, y)
            text(word(1, 2).upper(), x + 0.008, y - 0.03, 0.026, cw - 0.016, ink, bold=0.035, squeeze=0.8, align="CENTER")
            text(" ".join(word(1, 2) for _ in range(6)), x + 0.008, y - 0.048, BODY * 0.9, cw - 0.016, ink, align="CENTER")
            text("kr %d,-" % rnd.randint(9, 299), x + 0.008, y - bh + 0.012, 0.016, cw - 0.016, ink, bold=0.03, align="CENTER")
            y -= bh + 0.012
        else:
            lines = rnd.randint(5, 11)
            body = " ".join(word() for _ in range(lines * 3))
            th = text(body, x, y - BODY, BODY, cw, ink)
            y -= th + BODY + 0.012
    if c > 0:
        rect(x - gut / 2 - 0.0005, -SIZE / 2 + 0.02, x - gut / 2 + 0.0005, SIZE / 2 - 0.02, grey)

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = SIZE
cam.location = (0, 0, 2)
sc.collection.objects.link(cam)
sc.camera = cam
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
sc.eevee.taa_render_samples = 16
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x = sc.render.resolution_y = A.px
sc.render.filepath = os.path.abspath(A.out)
os.makedirs(os.path.dirname(sc.render.filepath), exist_ok=True)
bpy.ops.render.render(write_still=True)
print("wrote", sc.render.filepath)
