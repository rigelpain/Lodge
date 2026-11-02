"""画面の表示（HUD）の、立体の小物を Blender で組む。Godot では hud_plates.gd が小さな 3D の場面で描いて、画面に重ねる。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_hud.py -- --views all --prefix props/renders/30-hud

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_hud.py -- --look flat --export game/props/hud

2026-10-29 代表「タグ、刺繍、糸巻き、どれも平面で背景と区別がつかないのが嫌です。少しでも立体のプレートにして、影とか付けて、
マテリアル感がないと安っぽくてかなわないや。Blender で軽く作ってほしい」から。
大きさが場面で変わる板（名札・札・ワッペン・持ち物の列）は Godot で角の丸い板を組み、ここでは形の決まった物だけを作る:
  hud_bobbin   木の糸巻き（ボビン）。正面（-Y、Godot では +Z）に三つ穴の端の板、奥に巻いた糸。半径 0.5
  hud_hoop     刺繍枠。内と外の 2 本の木の輪と、上の真鍮色のねじ。内の半径 1.0
  hoop.png     本物らしい刺繍枠を真上から撮った絵（--hoop-png。2026-10-29 代表「刺繍小窓の刺繍枠をリアルな木枠にしてほしい。
               いまなんかぼやぼやしてモチーフが伝わらない」）。見えるのは曲げ木の外枠 1 本と、てっぺんの切れ目を締める金具だけ
               （内枠は張った布の下。2026-11-02 代表「二重の木枠の内側の方は布に隠れて見えない」）。影は枠が布に落とす段差の影を
               Cycles の shadow catcher で焼き込む（代表「前後って感じでなく段差があるような感じ」）。
               3D の場面（半分の解像度）に置くとぼやけるので、絵にして画面の解像度のまま描く（hud.gd）
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

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）")),
             ("--hoop-png", dict(default="", help="刺繍枠だけを正面から撮って、背景の抜けた PNG にする（HUD の小窓の枠の絵）"))])
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


# 刺繍枠の絵の寸法（Blender の単位。窓の布の縁 = 外枠の内の半径 = 1.0）。hud.gd の _draw_hoop と self_cam.gd の MASK_SHADER の縁の沈みがこれに合わせる
HOOP_T = 0.075        # 外枠の帯の幅（正面から見た太さ）
HOOP_D = 0.07         # 外枠の高さ（布からの段差）
HOOP_GAP = 0.04       # てっぺんの切れ目の半分の幅


def hoop_band(P, role, r0, t, d, gap, segs=160):
    """曲げ木の帯の輪（正面は -Y、輪の軸は Y）。てっぺん（+Z）に切れ目。断面は前の角を丸めた長方形で、布の面 y = 0 に座る。
    UV の u は輪に沿う長さ（曲げ木の木目が輪に沿って流れる）"""
    m = P.m(role)
    prof = []
    def corner(cx, cy, rad, a0, a1, n=5):
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            prof.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    cf, cb = 0.024, 0.006   # 前（見える面）の角は大きく丸め、後ろ（布に当たる面）はほぼ角
    corner(r0 + cb, -cb, cb, math.pi, math.pi / 2, 2)                      # 内・後ろ
    corner(r0 + t - cb, -cb, cb, math.pi / 2, 0.0, 2)                      # 外・後ろ
    corner(r0 + t - cf, -d + cf, cf, 0.0, -math.pi / 2)                    # 外・前
    corner(r0 + cf, -d + cf, cf, -math.pi / 2, -math.pi)                   # 内・前
    # 断面のまわりの長さで v を決める（木目の筋が帯の面を何本か横切る）
    vs = [0.0]
    for i in range(1, len(prof) + 1):
        a, b = prof[i - 1], prof[i % len(prof)]
        vs.append(vs[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    a0, a1 = gap / r0, 2 * math.pi - gap / r0
    rings = []
    for i in range(segs + 1):
        th = a0 + (a1 - a0) * i / segs
        rings.append([m.bm.verts.new((r * math.sin(th), y, r * math.cos(th))) for (r, y) in prof])
    n = len(prof)
    for i in range(segs):
        u0 = (a0 + (a1 - a0) * i / segs) * (r0 + t / 2)
        u1 = (a0 + (a1 - a0) * (i + 1) / segs) * (r0 + t / 2)
        for j in range(n):
            j2 = (j + 1) % n
            f = m.bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
            for lp, uv in zip(f.loops, ((u0, vs[j] * 4), (u0, vs[j + 1] * 4), (u1, vs[j + 1] * 4), (u1, vs[j] * 4))):
                lp[m.uv].uv = uv
    for ring in (rings[0], rings[-1]):   # 切れ目の木口
        f = m.bm.faces.new(ring)
        for lp, (r, y) in zip(f.loops, prof):
            lp[m.uv].uv = (r * 3, y * 3)
    m.uv_set = True


def hoop_real(name):
    """本物の刺繍枠を真上から（正面は -Y）: 見えるのは外枠の曲げ木の帯 1 本だけ。内枠は張った布の下に隠れる
    （2026-11-02 代表「地を木枠で挟むので二重の木枠の内側の方は布に隠れて見えないようです」）。
    外枠はてっぺんで切れ、両端に巻いた金具の耳を、横のねじで締める（左にねじの先と六角ナット、右に丸いつまみ）"""
    P = K.Parts(name, kind="hud")
    R, T, D, G = 1.0, HOOP_T, HOOP_D, HOOP_GAP
    hoop_band(P, "wood_bent", R, T, D, G)
    y = -D / 2
    # 帯の両端に巻いた金具（帯より少し大きい箱）と、上へ立つ耳
    for sx in (-1, 1):
        K.box(P, "steel", (sx * (G + 0.022), y, R + T / 2), (0.044, D + 0.008, T + 0.008))
        K.box(P, "steel", (sx * (G + 0.005), y, R + T + 0.045), (0.01, D * 0.7, 0.1))
    # ねじ: 耳を横に貫く軸。左はねじ山の見える先と六角ナット、右は刻みのある丸いつまみ
    zc = R + T + 0.06
    K.dowel(P, "steel", (-0.19, y, zc), (0.13, y, zc), 0.014, sides=16)
    for k in range(7):   # ねじ山
        K.ring(P, "steel", (-0.185 + 0.012 * k, y, zc), 0.016, 0.004, axis="X", n=16)
    K.disc(P, "steel", (-0.085, y, zc), 0.036, 0.026, axis="X", segs=6)
    K.disc(P, "steel", (-0.058, y, zc), 0.03, 0.008, axis="X", segs=24)   # 座金
    K.disc(P, "steel", (0.09, y, zc), 0.046, 0.05, axis="X", segs=24)
    for k in range(16):
        a = 2 * math.pi * k / 16
        K.box(P, "steel", (0.09, y + 0.046 * math.cos(a), zc + 0.046 * math.sin(a)), (0.044, 0.01, 0.01))
    P.finish()
    # 曲げ木の木目は淡く（ブナは木目が細かく目立たない）、金具はニッケルめっきの明るい鈍い銀
    base = C.LM.lin(C.HEX["wood_bent"])
    wm = C.mat("wood_bent").node_tree
    mix = next(nd for nd in wm.nodes if nd.type == "MIX")
    mix.inputs[6].default_value = tuple(c * 0.8 for c in base[:3]) + (1,)
    # 色むら: 輪に沿ってゆるく明るさが揺れる（写真の枠の、ところどころの濃い所）
    uv = wm.nodes.new("ShaderNodeTexCoord")
    nz = wm.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 1.6
    nz.inputs["Detail"].default_value = 3.0
    wm.links.new(uv.outputs["UV"], nz.inputs["Vector"])
    ramp = wm.nodes.new("ShaderNodeMapRange")
    ramp.inputs["To Min"].default_value = 0.86
    ramp.inputs["To Max"].default_value = 1.04
    wm.links.new(nz.outputs["Fac"], ramp.inputs["Value"])
    mul = wm.nodes.new("ShaderNodeMix")
    mul.data_type, mul.blend_type = "RGBA", "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    bsdf = wm.nodes.get("Principled BSDF")
    wm.links.new(mix.outputs[2], mul.inputs[6])
    wm.links.new(ramp.outputs[0], mul.inputs[7])
    wm.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    st = C.mat("steel").node_tree.nodes.get("Principled BSDF")
    if st:
        st.inputs["Base Color"].default_value = C.LM.lin("CDD0D4")
        st.inputs["Roughness"].default_value = 0.38


def cloth_catcher():
    """影だけを受ける布（Cycles の shadow catcher）。窓の中の布は、内枠の上を張って帯の高さの半分ほどまで持ち上がり、
    外枠の内の縁で枠の中へ引き込まれて沈む。外枠の外は、外枠が乗っている面（y = 0）"""
    import bmesh
    import bpy
    D = HOOP_D
    prof = [(0.0, -D * 0.45), (0.9, -D * 0.45), (0.95, -D * 0.42), (0.98, -D * 0.3), (0.995, -D * 0.12), (1.0, 0.0), (1.6, 0.0)]
    bm = bmesh.new()
    segs = 128
    rings = [[bm.verts.new((r * math.sin(2 * math.pi * i / segs), y, r * math.cos(2 * math.pi * i / segs))) for i in range(segs)]
             for (r, y) in prof]
    for j in range(len(rings) - 1):
        for i in range(segs):
            i2 = (i + 1) % segs
            bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))
    me = bpy.data.meshes.new("cloth_catcher")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("cloth_catcher", me)
    bpy.context.scene.collection.objects.link(o)
    o.is_shadow_catcher = True
    return o


def render_hoop_png(path):
    """刺繍枠を真上から、平行に撮る。背景は抜き、枠が布に落とす段差の影だけを残す（Cycles の shadow catcher）。
    光は左上の手前から（HUD の光と同じ向き）。布から高く離した落ち影ではなく、外枠の外の縁に沿う細い影になる"""
    import bpy
    C.setup_render("640x640")
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.image_settings.color_mode = "RGBA"
    for o in list(bpy.data.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.4
    sun.data.angle = math.radians(14)
    sun.rotation_euler = Vector((0.35, 1.0, -0.45)).normalized().to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(sun)
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    fill.data.energy = 0.6
    fill.data.angle = math.radians(40)
    fill.rotation_euler = Vector((-0.3, 1.0, 0.3)).normalized().to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(fill)
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.9, 0.9, 0.92, 1)
        bg.inputs[1].default_value = 0.5
    cloth_catcher()
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.8
    cam.location = (0, -6, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)
    print("wrote", path)


if A.hoop_png:
    C.HEX["wood_bent"] = "DDB27A"   # ブナのような明るい曲げ木（代表の写真の刺繍枠）
    hoop_real("hud_hoop_real")
    for r, parts in K.made:
        K.seat_threads([r] + K.descendants(r))
    render_hoop_png(A.hoop_png)
    sys.exit(0)

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
