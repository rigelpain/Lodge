"""ソリを Blender で組む。フェルトの座布団を木の滑り木に載せ、麻ひもで仕立てる。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_sled.py -- \
        --kind mid --views quarter,side,back --prefix props/renders/01-sled

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_sled.py -- \
        --kind mid --look flat --export game/props

形の決まり（design/art-concept.md）: 赤いフェルトの台、木の滑り木、背もたれは後ろ、前に麻ひもの紐。
台は座る人ごとに 1 枚の座布団で、真ん中を木のボタンで綴じる。座布団の数が乗れる人数。
縁はクリームの糸でかがり、横には腕の高さに曲げ木の手すりを渡し、座る所ごとにフェルトの握りを巻く。

寸法は game/sled.gd の物理に合わせる（mid）: 台 1.5 × 2.8 m、高さ 0.45 m、滑り木は x = ±0.6、
紐の付け根は Godot の (0, 0.3, -1.45)。前は +Y（Blender）＝ -Z（Godot）。
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as KT  # noqa: E402

A = C.parse([
    ("--kind", dict(default="mid", choices=("small", "mid", "large", "all"))),
    ("--trail", dict(action="store_true", help="後ろの雪に滑りあとを描く")),
    ("--trail-large", dict(default="", help="6 人乗りの滑りあとを差し替える（候補を見るとき）")),
    ("--swatch", dict(default="", help="縫い目の見本帳を描く。all か、柄の名前をカンマで")),
])
C.reset()
C.LOOK["v"] = A.look
if A.export:   # 焼き込み: 素材は描くときと同じに組む
    KT.baking_mode()

# 種類: 台の幅と長さ、座布団の並び（列 × 行）、滑り木の x、重さ、色、滑りあと
# 滑りあと: 重いソリほど太く丈夫な縫い目。small はなみ縫い、mid はくさり縫い、large はサドルステッチ（2026-10-27 代表が選んだ）。
# 凝った柄（花の蔓 garden など）は報酬や買い物で手に入れる差し替え。見本帳は --swatch all
KINDS = {
    "small": dict(W=0.9, L=1.5, cols=1, rows=1, runners=(-0.33, 0.33), R=0.2, mass=25.0,
                  felt="felt_red", trail="running"),
    "mid": dict(W=1.5, L=2.8, cols=1, rows=3, runners=(-0.6, 0.6), R=0.27, mass=60.0,
                felt="felt_red", trail="chain",
                seats=[(0, 0.75, 0.45), (0, -0.15, 0.45), (0, -1.0, 0.45)]),   # sled.gd の SEATS
    "large": dict(W=2.3, L=3.9, cols=2, rows=3, runners=(-0.95, 0.0, 0.95), R=0.32, mass=150.0,
                  felt="felt_red", trail="saddle"),
}
def build(kind, ox=0.0, export=False):
    """1 台を組む。ox は横にずらす量（並べて描くとき）。根元の空の節点と部品の列を返す"""
    K = KINDS[kind]
    W, L, R = K["W"], K["L"], K["R"]
    RUN_RX, RUN_RY = 0.022, 0.05        # 滑り木の断面（半分の幅と高さ）。薄い曲げ木の板
    Z_BOARD0, Z_BOARD1 = 0.16, 0.20     # 板（すのこ）の下と上
    CUSH_HZ = 0.11                      # 座布団の厚みの半分。上は 0.42
    Y_BACK = -L / 2 + 0.1               # 背もたれ
    Y_CUSH0, Y_CUSH1 = Y_BACK + 0.12, L / 2 - 0.25
    Y_CURL = L / 2 - 0.2                # 滑り木が反り上がり始める所
    FRONT = (Y_CURL + R, RUN_RY + R)    # 反りのいちばん前（横棒と紐の付け根）

    root = bpy.data.objects.new("sled_" + kind, None)
    C.coll("prop").objects.link(root)
    root["seats"] = K["cols"] * K["rows"]
    root["mass"] = K["mass"]
    root["box"] = [W, 0.45, L]   # Godot の当たり判定の箱（幅・高さ・長さ）

    parts = []


    def place(m, n0, mtx):
        for v in C.new_verts(m, n0):
            v.co = mtx @ v.co


    # ---------------------------------------------------------------- 滑り木
    def runner_path(x):
        pts = []
        y0 = -L / 2 - 0.05   # 後ろの端は少しだけ反る
        pts.append(Vector((x, y0 - 0.04, RUN_RY + 0.04)))
        pts.append(Vector((x, y0, RUN_RY + 0.008)))
        n = 10
        for i in range(1, n + 1):
            pts.append(Vector((x, y0 + (Y_CURL - y0) * i / n, RUN_RY)))
        for i in range(1, 19):   # 前で反り上がり、少しだけ巻き戻る
            a = math.radians(-90 + i * 9.0)
            rr = R * (1 - 0.25 * max(0, i - 12) / 6)
            pts.append(Vector((x, Y_CURL + rr * math.cos(a), RUN_RY + R + rr * math.sin(a))))
        return pts


    bent = C.M("runners", "wood_bent")
    for x in K["runners"]:
        C.tube(bent, runner_path(x), RUN_RX, sides=16, side=(1, 0, 0), ry=RUN_RY, sq=5.0)
    parts.append(bent.done(parent=root))
    wood = C.M("struts", "wood")
    # 横棒: 反りの前を左右につなぐ（紐の付け根）
    xs = K["runners"]
    C.tube(wood, [Vector((xs[0] - 0.05, FRONT[0] - 0.005, FRONT[1])), Vector((xs[-1] + 0.05, FRONT[0] - 0.005, FRONT[1]))],
           0.028, sides=10)
    # 束: 滑り木と板のあいだの短い丸棒
    for x in xs:
        for k in range(K["rows"] + 2):
            y = Y_BACK + (Y_CURL - 0.05 - Y_BACK) * k / (K["rows"] + 1)
            C.tube(wood, [Vector((x, y, RUN_RY * 2 - 0.01)), Vector((x, y, Z_BOARD0 + 0.01))], 0.024, sides=8)
    parts.append(wood.done(parent=root))

    # すのこの板: 横向きの細い板を並べる
    board = C.M("board", "wood_dark")
    y = Y_BACK - 0.04
    while y < Y_CURL - 0.02:
        w = 0.11
        bmesh.ops.create_cube(board.bm, size=1.0,
                              matrix=Matrix.Translation((0, y + w / 2, (Z_BOARD0 + Z_BOARD1) / 2))
                              @ Matrix.Diagonal((W - 0.02, w, Z_BOARD1 - Z_BOARD0, 1)))
        y += w + 0.025
    # 縦の桁（板を受ける）
    for x in xs:
        bmesh.ops.create_cube(board.bm, size=1.0,
                              matrix=Matrix.Translation((x, (Y_BACK + Y_CURL) / 2 - 0.02, Z_BOARD0 - 0.012))
                              @ Matrix.Diagonal((0.07, Y_CURL - Y_BACK + 0.06, 0.03, 1)))
    parts.append(board.done(smooth=False, bevel=0.008, seg=2, parent=root))

    # ---------------------------------------------------------------- 座布団と背もたれ
    felt = C.M("cushions", K["felt"])
    thread = C.M("stitches", "thread")
    button = C.M("buttons", "button")


    def cushion(center, half, rot_x=0.0, tuft=True):
        """1 枚の座布団: ふっくらした超楕円体、縫い目のかがり、真ん中の木のボタン"""
        mtx = Matrix.Translation(center) @ Matrix.Rotation(rot_x, 4, "X")
        a, b, c = half
        dent = (0.035, min(a, b) * 0.35) if tuft else None
        bf, bt, bb = len(felt.bm.verts), len(thread.bm.verts), len(button.bm.verts)
        C.superellipsoid(felt, (0, 0, 0), half, n_xy=5.0, n_z=2.4, cuts=7 if export else 10, dent=dent)
        pts, nrm = C.ellipse_ring(a, b, n=5.0, count=max(24, int(2 * (a + b) * 2 / 0.045)), z=0.0, inset=0.004)
        C.seam_whip(felt, thread, pts, nrm, every=2 if export else 1)
        if tuft:
            top = c - dent[0] + 0.004
            bmesh.ops.create_cone(button.bm, cap_ends=True, segments=16, radius1=0.036, radius2=0.032, depth=0.014,
                                  matrix=Matrix.Translation((0, 0, top + 0.007)))
            for ang in (0.0, math.pi / 2):   # 4 つ穴を糸で十字に
                d = Vector((math.cos(ang + math.pi / 4), math.sin(ang + math.pi / 4), 0)) * 0.012
                C.tube(thread, [Vector((0, 0, top + 0.012)) - d, Vector((0, 0, top + 0.016)), Vector((0, 0, top + 0.012)) + d],
                       0.0035, sides=4)
        place(felt, bf, mtx)
        place(thread, bt, mtx)
        place(button, bb, mtx)


    seat_centers = []
    rows, cols = K["rows"], K["cols"]
    row_len = (Y_CUSH1 - Y_CUSH0) / rows
    for r in range(rows):
        for c in range(cols):
            cx = -W / 2 + W / cols * (c + 0.5)
            cy = Y_CUSH1 - row_len * (r + 0.5)
            cushion((cx, cy, Z_BOARD1 + CUSH_HZ - 0.01), (W / cols / 2 - 0.02, row_len / 2 - 0.02, CUSH_HZ))
            seat_centers.append((cx, cy, 0.45))
    # 背もたれ: 寝かせた座布団を立てて、少し後ろへ倒す
    BACK_H = 0.30 if kind != "small" else 0.24
    tilt = math.radians(104)
    cushion((0, Y_BACK, Z_BOARD1 + BACK_H * math.sin(tilt) + 0.0), (W / 2 - 0.03, BACK_H, 0.075), rot_x=tilt, tuft=False)
    parts.append(felt.done(parent=root))
    parts.append(button.done(parent=root))

    # 背もたれの木の枠: 後ろの 2 本の柱と上の横木
    frame = C.M("back_frame", "wood")
    for x in (-W / 2 + 0.12, W / 2 - 0.12):
        p0 = Vector((x, Y_BACK - 0.06, Z_BOARD0))
        p1 = Vector((x, Y_BACK - 0.06 + 2 * BACK_H * math.cos(tilt), Z_BOARD1 + 2 * BACK_H * math.sin(tilt) - 0.04))
        C.tube(frame, [p0, p1], 0.022, sides=8)
    top_y = Y_BACK - 0.06 + 2 * BACK_H * math.cos(tilt)
    top_z = Z_BOARD1 + 2 * BACK_H * math.sin(tilt) - 0.02
    C.tube(frame, [Vector((-W / 2 + 0.06, top_y, top_z)), Vector((W / 2 - 0.06, top_y, top_z))], 0.026, sides=10)
    parts.append(frame.done(parent=root))

    # ---------------------------------------------------------------- 横の手すり
    # 座った人の腕の高さに、曲げ木の手すりを左右に渡す（カーブで振られてもつかまれる）。
    # 後ろは背もたれの横木の端から出て、前は渦のように巻き下りて板に留まる。
    # 座る所ごとにフェルトの握りを巻いて糸でかがり、柱との継ぎ目は麻ひもで縛る。
    hemp = C.M("hemp", "hemp")
    rail = C.M("rails", "wood_bent")
    grips = C.M("grips", "felt_red_dark")
    stand = C.M("rail_posts", "wood")
    RAIL_H = 0.72                      # 手すりの高さ（座布団の上 0.42 から 0.3 上）
    RAIL_R = 0.026
    RX = W / 2 + 0.07                  # 手すりの横の位置（台の縁の少し外）
    EDGE = W / 2 - 0.03                # 柱の根元（板の縁）
    seat_ys = sorted({round(s[1], 3) for s in (K.get("seats") or seat_centers)})
    posts = [(a + b) / 2 for a, b in zip(seat_ys, seat_ys[1:])] or [seat_ys[0] - 0.3]
    Y_TURN = Y_CUSH1 - 0.22            # ここから前へ巻き下りる
    TURN_R = 0.2
    for sx in (-1, 1):
        pts = [Vector((sx * (W / 2 - 0.06), top_y, top_z))]
        for i in range(1, 7):          # 背もたれの横木の端から、外へ開いて手すりの高さへ
            t = i / 6
            e = t * t * (3 - 2 * t)
            pts.append(Vector((sx * (W / 2 - 0.06 + (RX - W / 2 + 0.06) * e), top_y + 0.22 * t,
                               top_z + (RAIL_H - top_z) * e)))
        n = 12
        for i in range(1, n + 1):
            pts.append(Vector((sx * RX, top_y + 0.22 + (Y_TURN - top_y - 0.22) * i / n, RAIL_H)))
        for i in range(1, 10):         # 前の巻き下り
            a = math.radians(90 - 180 * i / 9)
            pts.append(Vector((sx * RX, Y_TURN + TURN_R * math.cos(a), RAIL_H - TURN_R + TURN_R * math.sin(a))))
        last = pts[-1]
        for i in range(1, 4):          # 座布団の外をまっすぐ下り、板の下で内へ曲げて留める
            t = i / 3
            pts.append(Vector((sx * RX, last.y, last.z + (Z_BOARD0 + 0.03 - last.z) * t)))
        pts.append(Vector((sx * (RX - 0.04), last.y, Z_BOARD0 - 0.005)))
        pts.append(Vector((sx * EDGE, last.y, Z_BOARD0 - 0.012)))
        C.tube(rail, pts, RAIL_R, sides=12)
        for y in posts:                # 柱: 板の縁から手すりへ、少し外へ開く
            C.tube(stand, [Vector((sx * EDGE, y, Z_BOARD0)), Vector((sx * RX, y, RAIL_H))], 0.02, sides=8)
            coil = []
            for i in range(41):        # 継ぎ目を麻ひもで 5 巻き
                t = i / 40
                a = t * 2 * math.pi * 5
                coil.append(Vector((sx * RX + (RAIL_R + 0.008) * math.cos(a), y - 0.035 + 0.07 * t,
                                    RAIL_H + (RAIL_R + 0.008) * math.sin(a))))
            C.tube(hemp, coil, 0.008, sides=6)
        for y in seat_ys:              # 握り: 座る所の少し前に、フェルトを巻いてかがる
            g = y + 0.12
            L2, GR = 0.17, RAIL_R + 0.018
            rs, gp = [], []
            for i in range(13):
                t = i / 12
                gp.append(Vector((sx * RX, g - L2 + 2 * L2 * t, RAIL_H)))
                rs.append(GR * (0.75 + 0.25 * math.sin(math.pi * t) ** 0.4))
            C.tube(grips, gp, rs, sides=12)
            wrap = []
            for i in range(97):        # 糸を斜めに巻いてかがる
                t = i / 96
                a = t * 2 * math.pi * 8
                wrap.append(Vector((sx * RX + (GR + 0.002) * math.cos(a), g - L2 * 0.85 + 2 * L2 * 0.85 * t,
                                    RAIL_H + (GR + 0.002) * math.sin(a))))
            C.tube(thread, wrap, 0.0035, sides=4)
    parts.append(rail.done(parent=root))
    parts.append(stand.done(parent=root))
    parts.append(grips.done(parent=root))
    parts.append(hemp.done(parent=root))
    # 紐は横棒の両端に結ぶ（game/sled_rope.gd が描く）。ここでは横棒に結び目を作らない
    fy, fz = FRONT[0] - 0.005, FRONT[1]
    parts.append(thread.done(parent=root))

    # 垂れた紐（描くときだけ。ゲームでは player.gd が紐を描く）
    if not export:
        drop = C.M("rope_drop", "hemp", "stage")
        pts = [Vector((0, fy + 0.045, fz - 0.02))]
        for i in range(1, 30):
            t = i / 29
            y = fy + 0.05 + 1.6 * t
            z = max(0.016, fz * (1 - t * 3.2) ** 2 if t < 0.31 else 0.016)
            pts.append(Vector((0.18 * math.sin(t * 5.0) * t, y, z)))
        C.tube(drop, pts, 0.016, sides=8)
        drop.done(parent=root)

    # ---------------------------------------------------------------- 目印（Godot の座標で読める空の節点）
    for i, s in enumerate(K.get("seats") or seat_centers):
        e = bpy.data.objects.new("seat_%d" % i, None)
        e.location = s
        e.parent = root
        C.coll("prop").objects.link(e)
        parts.append(e)
    anc = bpy.data.objects.new("rope_anchor", None)
    anc.location = (0, FRONT[0], FRONT[1])
    anc.parent = root
    C.coll("prop").objects.link(anc)
    parts.append(anc)
    for sx, nm in ((-1, "rope_tie_l"), (1, "rope_tie_r")):   # 引き紐の両端を結ぶ所: 手すりの巻き下りのいちばん前
        e = bpy.data.objects.new(nm, None)
        e.location = (sx * RX, Y_TURN + TURN_R, RAIL_H - TURN_R)
        e.parent = root
        C.coll("prop").objects.link(e)
        parts.append(e)
    root.location.x = ox
    return root, parts, K, xs, Y_BACK



# ---------------------------------------------------------------- 滑りあと（描くときだけ。案）
def trail_path(x, y0, n=140, step=0.1):
    """滑り木の後ろへのびる道筋。ソリの所ではまっすぐで、遠くでゆるく曲がる"""
    return [Vector((x + 0.5 * (1 - math.cos(i * step * 0.25)), y0 - i * step, 0.004)) for i in range(n)]


def chain_stitch(m, pts, size=0.17, width=0.075, r=0.012):
    """くさり縫い: 細長い輪を、前の輪の中から次の輪が出るようにつなぐ"""
    acc = [0.0]
    for i in range(1, len(pts)):
        acc.append(acc[-1] + (pts[i] - pts[i - 1]).length)

    def at(d):
        for i in range(1, len(pts)):
            if acc[i] >= d:
                t = (d - acc[i - 1]) / (acc[i] - acc[i - 1])
                return pts[i - 1].lerp(pts[i], t), (pts[i] - pts[i - 1]).normalized()
        return pts[-1], (pts[-1] - pts[-2]).normalized()

    d = 0.0
    while d + size < acc[-1]:
        p, t = at(d)
        side = Vector((-t.y, t.x, 0))
        ring = []
        for k in range(14):
            a = 2 * math.pi * k / 14
            along = size * 0.5 * (1 - math.cos(a))      # 涙のしずくの形: 根元はすぼまり、先がふくらむ
            across = width * 0.5 * math.sin(a) * (0.35 + 0.65 * (1 - math.cos(a)) / 2)
            ring.append(p + t * along + side * across)
        C.tube(m, ring + [ring[0]], r, sides=5, caps=False)
        d += size * 0.72


def zigzag(m, pts, amp=0.07, step=0.075, r=0.012):
    """ミシンのジグザグ縫い"""
    out, d, k = [], 0.0, 0
    acc = 0.0
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        L = (b - a).length
        t = (b - a).normalized()
        side = Vector((-t.y, t.x, 0))
        while d <= acc + L:
            p = a.lerp(b, (d - acc) / L)
            out.append(p + side * amp * (1 if k % 2 else -1))
            d += step
            k += 1
        acc += L
    C.tube(m, out, r, sides=5)


def walker(pts):
    """道筋を長さで引く: at(d) → (点, 進む向き, 横の向き)"""
    acc = [0.0]
    for i in range(1, len(pts)):
        acc.append(acc[-1] + (pts[i] - pts[i - 1]).length)

    def at(d):
        for i in range(1, len(pts)):
            if acc[i] >= d:
                t = (d - acc[i - 1]) / (acc[i] - acc[i - 1])
                f = (pts[i] - pts[i - 1]).normalized()
                return pts[i - 1].lerp(pts[i], t), f, Vector((-f.y, f.x, 0))
        f = (pts[-1] - pts[-2]).normalized()
        return pts[-1], f, Vector((-f.y, f.x, 0))
    return at, acc[-1]


def feather(m, pts, amp=0.09, step=0.12, r=0.011):
    """フェザーステッチ: 左右に枝分かれしながら進む羽根の縫い目"""
    at, total = walker(pts)
    d, k, prev = 0.0, 0, None
    while d < total - step:
        c, f, sd = at(d)
        sg = 1 if k % 2 else -1
        apex = c + sd * (amp * 0.3 * sg)
        tip = c - f * step * 0.75 + sd * (amp * sg)   # 外へ開く枝（後ろ向きに＝滑った向きに流れる）
        C.tube(m, [tip, apex], r, sides=5)
        if prev is not None:
            C.tube(m, [prev, apex.lerp(prev, 0.05)], r, sides=5)
        prev = apex
        d += step
        k += 1


def lazy_daisy(m, c, ang, length, width, r):
    """レゼーデージー: 根元から伸びる 1 枚の花びら（細長い輪）と、先を留める小さな糸"""
    f = Vector((math.cos(ang), math.sin(ang), 0))
    sd = Vector((-f.y, f.x, 0))
    ring = []
    for k in range(12):
        a = 2 * math.pi * k / 12
        along = length * 0.5 * (1 - math.cos(a))
        across = width * 0.5 * math.sin(a) * (0.3 + 0.7 * (1 - math.cos(a)) / 2)
        ring.append(c + f * along + sd * across)
    C.tube(m, ring + [ring[0]], r, sides=5, caps=False)
    tip = c + f * length
    C.tube(m, [tip - f * r * 1.5, tip + f * r * 2.5], r, sides=5)


def knot(m, c, r):
    """フレンチノット: 糸を巻いた小さな粒"""
    bmesh.ops.create_icosphere(m.bm, subdivisions=1, radius=r, matrix=Matrix.Translation(c + Vector((0, 0, r * 0.6))))


def garden(pts, ox, name, red, green, gold, period=0.9, amp=0.14, r=0.011):
    """花の蔓: 波打つ茎（ステムステッチ）に、5 枚の花びらの花と葉を交互に。花の芯はフレンチノット"""
    at, total = walker(pts)
    stem = []
    d = 0.0
    while d < total:
        c, f, sd = at(d)
        stem.append(c + sd * amp * math.sin(2 * math.pi * d / period))
        d += 0.03
    for i in range(0, len(stem) - 3, 2):   # ステムステッチ: 少しずつ重なる斜めの糸
        a, b = stem[i], stem[i + 3]
        off = (b - a).normalized().cross(Vector((0, 0, 1))) * r * 0.8
        C.tube(green, [a + off, b - off], r, sides=5)
    d = period * 0.25
    k = 0
    while d < total - 0.2:
        c, f, sd = at(d)
        sg = 1 if k % 2 == 0 else -1
        p = c + sd * amp * sg
        base_ang = math.atan2(f.y, f.x)
        fc = p + sd * sg * 0.13       # 花: 茎の山から少し外に
        for j in range(5):
            lazy_daisy(red, fc, base_ang + 2 * math.pi * j / 5 + 0.3, 0.105, 0.06, r)
        for j in range(3):
            knot(gold, fc + Vector((math.cos(j * 2.1), math.sin(j * 2.1), 0)) * 0.016, r * 1.6)
        for la in (-0.9, 0.9):        # 茎から出る葉 2 枚
            lazy_daisy(green, p - f * 0.12 * la * sg, base_ang + math.pi + la + (0 if sg > 0 else math.pi), 0.095, 0.05, r)
        d += period / 2
        k += 1


def triple_zigzag(m, pts, amp=0.075, step=0.11, r=0.014):
    """三重ジグザグ: 同じジグザグを 3 回重ねて縫う、伸びに強いミシンの縫い目。太い帯に見える"""
    for off in (-1, 0, 1):
        q = pts
        out, d, k, acc = [], 0.0, 0, 0.0
        for i in range(1, len(q)):
            a, b = q[i - 1], q[i]
            L = (b - a).length
            t = (b - a).normalized()
            sd = Vector((-t.y, t.x, 0))
            while d <= acc + L:
                p = a.lerp(b, (d - acc) / L)
                out.append(p + sd * (amp * (1 if k % 2 else -1) + off * r * 0.9) + t * off * r * 0.7)
                d += step
                k += 1
            acc += L
        C.tube(m, out, r, sides=5)


def saddle(m, pts, width=0.075, step=0.095, r=0.022, rows=2):
    """サドルステッチ: 蝋を引いた太い糸の斜めの縫い目を 2 列。革を縫う、いちばん丈夫な手縫い"""
    at, total = walker(pts)
    for row in range(rows):
        x0 = (row - (rows - 1) / 2) * width * 1.6
        d = row * step * 0.5
        while d < total - step:
            c, f, sd = at(d)
            a = c + sd * (x0 - width * 0.3) - f * step * 0.28
            b = c + sd * (x0 + width * 0.3) + f * step * 0.28
            C.tube(m, [a, (a + b) / 2 + Vector((0, 0, r * 0.4)), b], r, sides=6)
            d += step


def herringbone(m, pts, amp=0.085, step=0.2, r=0.018):
    """千鳥がけ: 上の列から下の列へ斜めに渡り、少し返して次を渡る。隣の糸と列の近くで交わって × が連なる。
    裾を留める丈夫な縫い目。斜めの糸 k は、列 (k の偶奇) の d = k·step/2 から、反対の列の d + step へ"""
    at, total = walker(pts)
    k = 0
    while k * step / 2 + step < total:
        d = k * step / 2
        sg = 1 if k % 2 else -1
        a, fa, sa = at(d)
        b, fb, sb = at(d + step)
        C.tube(m, [a + sa * amp * sg, b - sb * amp * sg], r, sides=5)
        k += 1


def trail(kind, xs, y0, ox):
    m = C.M("trail_" + kind, "thread_red", "stage")
    if kind == "garden":   # 6 人乗り: 真ん中に花の蔓、左右の滑り木はフェザーステッチ
        green = C.M("trail_green", "thread_green", "stage")
        gold = C.M("trail_gold", "thread_gold", "stage")
        for x in xs:
            pts = trail_path(x + ox, y0 - 0.25)
            if abs(x) < 0.01:
                garden(pts, ox, kind, m, green, gold)
            else:
                feather(m, pts)
        green.done()
        gold.done()
        m.done()
        return
    for x in xs:
        pts = trail_path(x + ox, y0 - 0.25)
        stitch_line(m, kind, pts)
    m.done()


def stitch_line(m, kind, pts):
    if kind == "running":
        C.running_stitch(m, pts, [Vector((0, 0, 1))], dash=0.14, gap=0.08, r=0.013)
    elif kind == "chain":
        chain_stitch(m, pts)
    elif kind == "zigzag":
        zigzag(m, pts)
    elif kind == "triple_zigzag":
        triple_zigzag(m, pts)
    elif kind == "saddle":
        saddle(m, pts)
    elif kind == "herringbone":
        herringbone(m, pts)
    elif kind == "feather":
        feather(m, pts)


# 見本帳: 縫い目の柄を 1 本ずつ縦に並べる（--swatch）
SWATCH = ["running", "chain", "zigzag", "triple_zigzag", "saddle", "herringbone", "feather", "garden"]


def swatches(kinds):
    for i, kind in enumerate(kinds):
        x = (i - (len(kinds) - 1) / 2) * 0.55
        pts = [Vector((x, 1.5 - j * 0.05, 0.004)) for j in range(70)]
        m = C.M("sw_" + kind, "thread_red", "stage")
        if kind == "garden":
            green = C.M("sw_green", "thread_green", "stage")
            gold = C.M("sw_gold", "thread_gold", "stage")
            garden(pts, 0, kind, m, green, gold, period=0.9, amp=0.1)
            green.done()
            gold.done()
        else:
            stitch_line(m, kind, pts)
        m.done()


if A.trail_large:
    KINDS["large"]["trail"] = A.trail_large
if A.swatch:   # 見本帳だけ描いて終わる
    swatches(SWATCH if A.swatch == "all" else A.swatch.split(","))
    C.ground(30.0)
    C.light(elev=40.0)
    C.setup_render(A.size)
    n = len(SWATCH if A.swatch == "all" else A.swatch.split(","))
    C.render((0.0, -0.6, 0.6 * n + 0.6), (0.0, -0.3, 0.0), 32, os.path.abspath("%s-swatch.png" % A.prefix))
    raise SystemExit
if A.kind == "all":   # 3 台を並べる（描くときだけ）
    LINE = (("small", -2.6), ("mid", 0.0), ("large", 3.1))
else:
    LINE = ((A.kind, 0.0),)
built = [build(k, ox, bool(A.export)) for k, ox in LINE]

if not A.export:
    if A.trail:
        for root, parts, K, xs, y_back in built:
            trail(K["trail"], xs, -K["L"] / 2 - 0.1, root.location.x)
    C.ground(80.0)
    C.light()
    C.setup_render(A.size)
    s = KINDS[A.kind]["L"] / 2.8 if A.kind != "all" else 1.0
    cams = {
        "quarter": ((-2.6 * s, 3.2 * s, 1.7 * s), (0, -0.1 * s, 0.25), 40),
        "side": ((-4.6 * s, 0.0, 0.9 * s), (0, 0, 0.3), 45),
        "back": ((2.6 * s, -3.6 * s, 1.8 * s), (0, 0.1, 0.3), 40),
        "low": ((-1.2 * s, 2.7 * s, 0.32), (0.1, 0.0, 0.3), 30),
        "top": ((0.01, 0.0, 6.0 * s), (0, 0, 0), 40),
        "trail": ((-3.0 * s, 4.2 * s, 2.6 * s), (0.2, -3.0 * s, 0), 32),
        "line": ((-4.2, 6.4, 3.4), (0.4, -0.6, 0.2), 32),
        "line_back": ((3.0, -9.5, 4.2), (0.6, 0.0, 0.0), 30),
        "line_trail": ((-1.0, 3.5, 4.2), (0.7, -6.0, 0.0), 26),
        "trail_top": ((0.7, -4.6, 5.2), (0.7, -5.6, 0.0), 30),
        "garden": ((3.1, -4.4, 2.6), (3.1, -5.0, 0.0), 32),
    }
    for root, parts, K, xs, y_back in built:
        print("triangles", root.name, C.tri_count(parts))
    if A.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
    for v in A.views.split(","):
        loc, tgt, lens = cams[v]
        C.render(loc, tgt, lens, os.path.abspath("%s-%s.png" % (A.prefix, v)))
else:
    for root, parts, K, xs, y_back in built:
        print("triangles", root.name, C.tri_count(parts))
        KT.export_root(root, os.path.join(A.export, "%s.glb" % root.name), tris=2000)
