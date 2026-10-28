"""ロッジの落ち着く場所の床・壁・小上がり・掘りごたつ・座布団・布団を Blender で組む。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_room.py -- \
        --views all,koagari,futon,walls --prefix props/renders/11-room

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_room.py -- \
        --look flat --export game/props/room

ロッジの建物（lodge/）は別のセッションが作っているので、ここでは差し替えや模様替えに使える部品として作る。
床と壁は 2 m 角の板で、並べてつなぐ。小上がりは畳の台で、掘りごたつを載せられる。
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）")),
             ("--views-only", dict(default="", help="描く品物の名前（カンマで）。ほかは組まない"))])
K.setup(A, fiber=1.5, scale=2.0)
EX = K.S["export"]

C.HEX.update({"felt_indigo": "2E3F66", "felt_mustard": "C99A3A", "felt_rose": "B5636A", "felt_moss": "6E7F4A",
              "felt_charcoal": "3A3836", "felt_ivory": "EEE6D4", "felt_rust": "A8532E", "felt_sky": "8FAFC8"})


# ---------------------------------------------------------------- 床（2 m 角）
def floor_planks(name, role="wood", w=0.16):
    """板張りの床: 幅 16 cm の板を、継ぎ目を少しあけて千鳥に張る"""
    P = K.Parts(name, kind="floor", size=2.0)
    for _r in ("wood", "wood_dark"):
        P.hard[_r] = 0.006
    rnd = random.Random(len(name))
    y = -1.0
    while y < 1.0 - 0.01:
        x = -1.0
        off = rnd.uniform(0.2, 0.9)
        cuts = [-1.0, -1.0 + off, -1.0 + off + 1.0, 1.0]
        for a, b in zip(cuts[:-1], cuts[1:]):
            b = min(b, 1.0)
            if b - a > 0.05:
                K.box(P, role, ((a + b) / 2, y + w / 2, 0.01), (b - a - 0.006, w - 0.006, 0.02))
        y += w
    P.finish()


def floor_tatami(name):
    """畳 2 枚（0.9 × 1.8 を 2 枚で 1.8 角）と、まわりの板。へりは藍の布"""
    P = K.Parts(name, kind="floor", size=2.0)
    for _r in ("wood", "wood_dark"):
        P.hard[_r] = 0.006
    K.box(P, "wood", (0, 0, 0.01), (2.0, 2.0, 0.02))
    for x in (-0.45, 0.45):
        K.box(P, "tatami", (x, 0, 0.035), (0.88, 1.78, 0.03))
        for sx in (-1, 1):   # 長い辺のへり
            K.box(P, "felt_indigo", (x + sx * 0.432, 0, 0.0505), (0.03, 1.78, 0.002))
    P.finish()


def floor_rug(name, colors):
    """編んだ楕円の敷物（ブレイデッドラグ）。毛糸の三つ編みを渦に巻く。色は外へ向かって変わる"""
    P = K.Parts(name, kind="rug")
    turns = 9 if not EX else 6
    pitch = 0.07
    n = 64 if not EX else 32
    for t in range(turns):
        role = colors[t % len(colors)]
        pts = []
        for k in range(n + 1):
            a = 2 * math.pi * k / n
            r = 0.06 + pitch * (t + k / n)
            pts.append((r * 1.5 * math.cos(a), r * math.sin(a), 0.012 + 0.002 * math.sin(a * 20)))
        K.tube(P, role, pts, 0.037, sides=8, ry=0.013, caps=False)
    P.finish()


# ---------------------------------------------------------------- 壁（幅 2 m、高さ 2.6 m。前が +Y）
def wall_boards(name, role="wood"):
    """縦の羽目板。上と下に横木"""
    P = K.Parts(name, kind="wall", size=[2.0, 2.6])
    for _r in ("wood", "wood_dark"):
        P.hard[_r] = 0.006
    w = 0.14
    x = -1.0
    while x < 1.0 - 0.01:
        K.box(P, role, (x + w / 2, 0.0, 1.3), (w - 0.008, 0.03, 2.6))
        x += w
    K.box(P, "wood_dark", (0, 0.025, 0.06), (2.0, 0.03, 0.12))
    K.box(P, "wood_dark", (0, 0.025, 2.56), (2.0, 0.03, 0.08))
    P.finish()


def wall_quilt(name, palette):
    """下は腰板、上はフェルトの端切れをはぎ合わせた壁。継ぎ目をなみ縫い"""
    P = K.Parts(name, kind="wall", size=[2.0, 2.6])
    for _r in ("wood", "wood_dark"):
        P.hard[_r] = 0.006
    rnd = random.Random(len(name) * 7)
    K.box(P, "wood", (0, 0.0, 0.45), (2.0, 0.04, 0.9))
    K.box(P, "wood_dark", (0, 0.025, 0.92), (2.0, 0.05, 0.05))
    cols, rows = 5, 4
    cw, ch = 2.0 / cols, 1.65 / rows
    for i in range(cols):
        for j in range(rows):
            cx = -1.0 + cw * (i + 0.5)
            cz = 0.95 + ch * (j + 0.5)
            K.pbox(P, rnd.choice(palette), (cx, 0.0, cz), (cw / 2 - 0.004, 0.012, ch / 2 - 0.004), n=8.0, nz=8.0, c=5)
    for i in range(1, cols):
        x = -1.0 + cw * i
        K.stitch_line(P, "thread", [(x, 0.014, 0.97), (x, 0.014, 2.58)], r=0.003, dash=0.03)
    for j in range(1, rows):
        z = 0.95 + ch * j
        K.stitch_line(P, "thread", [(-0.98, 0.014, z), (0.98, 0.014, z)], r=0.003, dash=0.03)
    P.finish(fuzz=0.003)


def wall_logs(name):
    """巻いたフェルトの丸太を横に積んだ壁（ロッジの外壁と同じ考え）。木口に渦"""
    P = K.Parts(name, kind="wall", size=[2.0, 2.6])
    for _r in ("wood", "wood_dark"):
        P.hard[_r] = 0.006
    r = 0.13
    z = r
    while z < 2.6:
        K.tube(P, "felt_tan", [(-1.0, 0, z), (1.0, 0, z)], r, sides=K.cuts(20, 12))
        for x in (-1.0, 1.0):   # 木口の渦: 巻いたフェルトの層
            sp = []
            for k in range(60):
                t = k / 59 * 4
                rr = r * (0.15 + 0.8 * t / 4)
                sp.append((x + 0.002 * (1 if x > 0 else -1), rr * math.cos(t * 2 * math.pi), z + rr * math.sin(t * 2 * math.pi)))
            K.tube(P, "felt_brown", sp, 0.004, sides=4)
        z += 2 * r * 0.96
    P.finish(fuzz=0.004)


# ---------------------------------------------------------------- 座布団と布団
def floor_collider(z=0.0):
    return K.collider_box((0, 0, z - 0.05), (8.0, 8.0, 0.1))


def zabuton(name, role, tuft_role="thread_red", tassel_role="thread_red"):
    """座布団: 綿を詰めた四角い袋を、内から押して重さでつぶす（布の計算）。真ん中を綴じてくぼませる。四隅に房"""
    P = K.Parts(name, kind="cushion")
    a, h = 0.27, 0.05
    m = C.M(name + "_cushion", role)
    ret = bmesh.ops.create_cube(m.bm, size=1.0, matrix=Matrix.Translation((0, 0, h + 0.01)) @ Matrix.Diagonal((2 * a, 2 * a, 2 * h, 1)))
    es = list({e for v in ret["verts"] for e in v.link_edges})
    bmesh.ops.subdivide_edges(m.bm, edges=es, cuts=K.cuts(16, 12), use_grid_fill=True)
    o = m.done(smooth=True)
    fl = floor_collider()
    K.cloth_sim(o, [fl], frames=36, pressure=4.0, mass=0.25, stiff=12.0, bend=0.2,
                pin=lambda p: math.hypot(p.x, p.y) < 0.035, thickness=0.004, subsurf=1)
    K.drop(fl)
    o.parent = P.root
    P.parts.append(o)
    top = max((o.matrix_world @ v.co).z for v in o.data.vertices)
    K.stitch_line(P, tuft_role, [(-0.008, -0.008, h * 2 + 0.012), (0.008, 0.008, h * 2 + 0.012)], r=0.003, dash=0.02)
    K.stitch_line(P, tuft_role, [(-0.008, 0.008, h * 2 + 0.012), (0.008, -0.008, h * 2 + 0.012)], r=0.003, dash=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = Vector((sx * (a - 0.005), sy * (a - 0.005), h * 0.6))
            out = Vector((sx, sy, 0)).normalized()
            for k in range(5):   # 房: 短い糸の束
                d = out * 0.035 + Vector((0, 0, -0.02 - 0.004 * k))
                K.tube(P, tassel_role, [c, c + d + Vector((0.004 * (k - 2), 0, 0))], 0.0025, sides=4)
    P.finish(fuzz=0.002)


def futon(name, shiki, kake, makura):
    """布団一組: 敷き布団（綿を詰めて重さで沈む）、上から掛けた掛け布団（布の計算で縁が垂れる）、そば殻の枕"""
    P = K.Parts(name, kind="bedding")
    fl = floor_collider()
    sk = K.cushion(P, "shiki", shiki, (0, 0, 0.07), (1.0, 2.0, 0.1), pressure=2.5, colliders=[fl], cuts_n=14, frames=30)
    top = max((sk.matrix_world @ v.co).z for v in sk.data.vertices)
    # 枕と掛け布団は、ふくらんだ敷き布団そのものに当てる（箱に当てると敷き布団の中に沈む）
    K.cushion(P, "makura", makura, (0, 0.82, top + 0.08), (0.5, 0.26, 0.1), pressure=3.0, colliders=[sk], cuts_n=10,
              frames=25)
    # 掛け布団は枕の手前まで（枕に乗り上げると、折れた縁が固く浮く）。どこも留めずに落とし、横と足もとへ垂らす
    nu, nv = (44, 52) if not EX else (36, 42)
    cloth = K.cloth_grid(name + "_kake", kake, 1.3, 1.5, nu, nv, (0, -0.16, top + 0.05))
    K.cloth_sim(cloth, [sk, fl], frames=70, mass=0.45, stiff=10.0, bend=0.8, thickness=0.012, solidify=0.04, subsurf=1)
    cloth.parent = P.root
    P.parts.append(cloth)
    K.drop(fl)
    P.finish(fuzz=0.002)


# ---------------------------------------------------------------- 小上がりと掘りごたつ
def koagari(name, mats=2, H=0.4):
    """小上がり: 畳の台。縁は木の框（かまち）、へりは藍。前に踏み台"""
    W, D = 0.9 * mats, 1.8
    P = K.Parts(name, kind="platform", size=[W + 0.1, D + 0.1], height=H)
    for _r in ("wood", "wood_dark"):
        P.hard[_r] = 0.006
    K.box(P, "wood_dark", (0, 0, H / 2 - 0.02), (W + 0.06, D + 0.06, H - 0.04))
    for i in range(mats):
        x = -W / 2 + 0.45 + 0.9 * i
        K.box(P, "tatami", (x, 0, H - 0.02), (0.88, 1.78, 0.04))
        for sx in (-1, 1):
            K.box(P, "felt_indigo", (x + sx * 0.432, 0, H + 0.0005), (0.03, 1.78, 0.003))
    # 框: 前と横の角に太い木
    K.box(P, "wood", (0, D / 2 + 0.04, H - 0.04), (W + 0.12, 0.08, 0.08))
    for sx in (-1, 1):
        K.box(P, "wood", (sx * (W / 2 + 0.04), 0, H - 0.04), (0.08, D + 0.12, 0.08))
    # 踏み台
    K.box(P, "wood", (0, D / 2 + 0.25, 0.1), (min(W, 0.9), 0.3, 0.2))
    P.mark("top", (0, 0, H))
    P.finish()


def kotatsu(name, quilt_role, top_role="wood", pit=True):
    """こたつ: 木の卓に布団を重力で掛け（布の計算。卓の角で折れて畳に広がる）、上に厚い天板。
    pit=True は掘りごたつ（原点は畳の面。穴は下へ 0.45 m。穴の底に熱をもったフェルト）"""
    P = K.Parts(name, kind="kotatsu")
    TW, TD, TZ = 1.2, 0.8, 0.38
    for role in ("wood", "wood_dark", top_role, "felt_charcoal"):
        P.hard[role] = 0.006
    if pit:
        PW, PD, PZ = 1.0, 0.65, 0.45
        for (cx, cy, sx, sy) in ((0, PD / 2, PW, 0.03), (0, -PD / 2, PW, 0.03), (PW / 2, 0, 0.03, PD), (-PW / 2, 0, 0.03, PD)):
            K.box(P, "wood", (cx, cy, -PZ / 2), (sx, sy, PZ))
        K.box(P, "felt_charcoal", (0, 0, -PZ), (PW, PD, 0.02))
        K.pbox(P, "felt_heat", (0, 0, -PZ + 0.04), (0.18, 0.12, 0.03), n=4.0, c=5)
    # 卓: 四角い脚と、脚をつなぐ幕板
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.box(P, "wood_dark", (sx * (TW / 2 - 0.05), sy * (TD / 2 - 0.05), (TZ - 0.04) / 2), (0.06, 0.06, TZ - 0.04))
    for (cx, cy, sx, sy) in ((0, TD / 2 - 0.05, TW - 0.1, 0.03), (0, -TD / 2 + 0.05, TW - 0.1, 0.03),
                             (TW / 2 - 0.05, 0, 0.03, TD - 0.1), (-TW / 2 + 0.05, 0, 0.03, TD - 0.1)):
        K.box(P, "wood_dark", (cx, cy, TZ - 0.07), (sx, sy, 0.06))
    K.box(P, "wood_dark", (0, 0, TZ - 0.02), (TW, TD, 0.03))                              # 布団を受ける板
    # こたつ布団: 細かく割った 1 枚の布を卓の上から落とす
    col = K.collider_box((0, 0, (TZ - 0.005) / 2), (TW, TD, TZ - 0.005))
    fl = floor_collider()
    nu, nv = (70, 58) if not EX else (56, 46)
    cloth = K.cloth_grid(name + "_futon", quilt_role, 2.2, 1.8, nu, nv, (0, 0, TZ + 0.04))
    K.cloth_sim(cloth, [col, fl], frames=60, mass=0.5, stiff=12.0, bend=3.0, thickness=0.012, solidify=0.035, subsurf=1)
    K.drop(col)
    K.drop(fl)
    cloth.parent = P.root
    P.parts.append(cloth)
    # 天板: 布団の上に載る厚い板。縁を一段落とす
    tz = TZ + 0.04 + 0.035 + 0.02
    K.box(P, top_role, (0, 0, tz), (TW + 0.08, TD + 0.08, 0.04))
    K.box(P, "wood_dark", (0, 0, tz - 0.026), (TW + 0.02, TD + 0.02, 0.012))
    # 天板の上: みかんの籠
    K.lathe(P, "hemp", [(0.0, 0.0), (0.09, 0.0), (0.11, 0.05), (0.1, 0.05), (0.085, 0.006), (0.0, 0.006)],
            center=(0.25, 0.05, tz + 0.02), segs=24)
    for k, (dx, dy) in enumerate(((0.0, 0.0), (0.045, 0.02), (-0.03, 0.035), (0.01, -0.04))):
        K.pbox(P, "felt_orange", (0.25 + dx, 0.05 + dy, tz + 0.07 + (0.03 if k == 0 else 0)), (0.032, 0.032, 0.028), n=2.0, c=5)
    P.mark("top", (0, 0, tz + 0.02))
    for i, (x, y) in enumerate(((0, TD / 2 + 0.45), (0, -TD / 2 - 0.45), (TW / 2 + 0.45, 0), (-TW / 2 - 0.45, 0))):
        P.mark("seat_%d" % i, (x, y, 0))
    P.finish(fuzz=0.003)


# ---------------------------------------------------------------- 組む
floor_planks("floor_planks")
floor_planks("floor_planks_dark", "wood_dark")
floor_tatami("floor_tatami")
floor_rug("rug_braided_warm", ["felt_rust", "felt_mustard", "felt_ivory", "felt_rose"])
floor_rug("rug_braided_cool", ["felt_indigo", "felt_sky", "felt_ivory", "felt_moss"])
wall_boards("wall_boards")
wall_quilt("wall_quilt_warm", ["felt_rust", "felt_mustard", "felt_ivory", "felt_rose", "felt_tan"])
wall_quilt("wall_quilt_cool", ["felt_indigo", "felt_sky", "felt_ivory", "felt_moss", "felt_beige"])
wall_logs("wall_logs")
for nm, role in (("zabuton_red", "felt_red"), ("zabuton_indigo", "felt_indigo"), ("zabuton_mustard", "felt_mustard"),
                 ("zabuton_moss", "felt_moss")):
    zabuton(nm, role, "thread" if role != "felt_mustard" else "thread_red", "thread" if role == "felt_indigo" else "thread_red")
zabuton("zabuton_patch", "patch_cool", "thread_red", "thread_red")
futon("futon_indigo", "felt_ivory", "felt_indigo", "felt_mustard")
futon("futon_patch", "felt_ivory", "patch_warm", "felt_rust")
futon("futon_rose", "felt_beige", "felt_rose", "felt_ivory")
koagari("koagari_2")
koagari("koagari_4", mats=4)
kotatsu("kotatsu_patch", "patch_mix")
kotatsu("kotatsu_indigo", "felt_indigo")
kotatsu("kotatsu_floor", "felt_rust", pit=False)

if A.export:
    K.export_all(A.export, A.only.split(",") if A.only else None)
else:
    R = {r.name: r for r, p in K.made}
    # 部屋: 奥に壁 4 枚、床に板 3 枚、小上がりにこたつと座布団、横に布団
    for i, n in enumerate(["wall_boards", "wall_quilt_warm", "wall_logs", "wall_quilt_cool"]):
        R[n].location = (-3.0 + 2.0 * i, -2.0, 0)
    for i, n in enumerate(["floor_planks", "floor_tatami", "floor_planks_dark"]):
        R[n].location = (-2.0 + 2.0 * i, 3.6, 0)
    R["koagari_4"].location = (-2.6, 0.0, 0)
    R["kotatsu_patch"].location = (-2.6, -0.1, 0.4)
    for i, n in enumerate(["zabuton_red", "zabuton_indigo", "zabuton_mustard", "zabuton_moss"]):
        R[n].location = [(-2.6, 0.62, 0.4), (-2.6, -0.82, 0.4), (-1.65, -0.1, 0.4), (-3.55, -0.1, 0.4)][i]
    R["zabuton_patch"].location = (-0.6, 1.6, 0)
    R["koagari_2"].location = (3.4, -0.6, 0)
    R["futon_indigo"].location = (3.4, -0.6, 0.4)
    R["futon_patch"].location = (1.6, 0.4, 0)
    R["futon_rose"].location = (5.3, 0.4, 0)
    R["kotatsu_indigo"].location = (0.4, -0.4, 0.0)
    R["kotatsu_indigo"].hide_render = False
    R["kotatsu_floor"].location = (0.4, 2.0, 0)
    R["rug_braided_warm"].location = (0.4, 2.0, 0)
    R["rug_braided_cool"].location = (-2.6, 3.0, 0)
    # 床の穴の掘りごたつは、床の上だと穴が見えるので、描くときは小上がりの上だけにする
    for o in K.descendants(R["kotatsu_indigo"]):
        o.hide_render = True
    K.room(floor_size=14.0, wall_y=-2.2)
    K.interior_light(1.4)
    cams = {
        "all": ((0.6, 9.5, 4.2), (0.4, 0.0, 0.6), 26),
        "koagari": ((-0.6, 3.4, 2.0), (-2.6, -0.1, 0.5), 34),
        "futon": ((4.2, 4.2, 2.4), (3.0, 0.0, 0.3), 32),
        "walls": ((0.0, 3.0, 1.5), (0.0, -2.0, 1.3), 30),
        "rug": ((0.4, 5.0, 2.2), (0.2, 2.0, 0.1), 32),
    }
    K.render_views(A, cams)
