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

ほかの 3 つは形を変える（2026-10-29 代表「小がホームセンターに売ってるプラスチックの1~2人用、大がサンタさんが
乗ってるような8人乗りくらいのやつ」「1人用の重さ0の米袋もほしい」→ 米袋は 1 kg に）。寸法は sled.gd の KINDS:
  sack  米袋。クラフト紙の袋に、わらを少し詰めて尻に敷く。口と底はミシンで縫い閉じ、前の両耳に紐を結ぶ
  small プラスチックの成形ソリを、型に入れて固めた厚いフェルトで。縁はクリームのバイアステープでくるみ、
        前の反りの穴に紐を通す。横には握りの穴。下に滑り木の筋
  large サンタのそり。赤いフェルトの胴に金の毛糸の縁と渦、緑のフェルトの長椅子が 4 列（2 人ずつ）。
        滑り木は前で大きく渦を巻き、その前の端に紐を結ぶ
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
    ("--kind", dict(default="mid", choices=("sack", "small", "mid", "large", "all"))),
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
# 席（seats）は Blender の座標 (x, -z, y)。Godot の sled.gd の SEATS を写したもの（small と sack は座る面の高さ。下の注）
KINDS = {
    "sack": dict(W=0.6, L=1.1, mass=1.0, runners=(-0.2, 0.2), trail="running", tris=1500,
                 seats=[(0, -0.1, 0.15)]),
    # small の席の高さ: sled.gd は 0.35 だが、成形ソリの底は雪から 3 cm。座る面に合わせ 0.06 にした（共有メモで物理側に相談）
    "small": dict(W=0.75, L=1.6, mass=15.0, runners=(-0.28, 0.28), trail="running", tris=2500,
                  seats=[(0, 0.3, 0.06), (0, -0.4, 0.06)]),
    "mid": dict(W=1.5, L=2.8, cols=1, rows=3, runners=(-0.6, 0.6), R=0.27, mass=60.0,
                felt="felt_red", trail="chain",
                seats=[(0, 0.75, 0.45), (0, -0.15, 0.45), (0, -1.0, 0.45)]),   # sled.gd の SEATS
    "large": dict(W=2.2, L=4.8, mass=220.0, runners=(-0.95, 0.95), trail="saddle", tris=4500,
                  seats=[(x, y, 0.55) for y in (1.65, 0.55, -0.55, -1.65) for x in (-0.5, 0.5)]),
}
C.HEX.update({"felt_holly": "3F6B4A", "paper_red": "B8402E", "paper_green": "5E8A4E", "paper_gold": "D9A53C",
              "paper_tape": "EFE6D2"})
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


# ---------------------------------------------------------------- 小・大・米袋の共通
def new_root(kind):
    K = KINDS[kind]
    root = bpy.data.objects.new("sled_" + kind, None)
    C.coll("prop").objects.link(root)
    root["seats"] = len(K["seats"])
    root["mass"] = K["mass"]
    root["box"] = [K["W"], 0.15 if kind == "sack" else 0.45, K["L"]]   # Godot の当たり判定の箱（幅・高さ・長さ）
    return root, K


def mark(name, loc, root, parts, axis=None):
    """目印の空の節点。axis を決めると、その向きを節点の上（Blender の Z ＝ Godot の Y）にする。
    sled_rope.gd は rope_tie_* の上の向きを、紐を巻く軸として読む"""
    e = bpy.data.objects.new(name, None)
    e.location = loc
    if axis is not None:
        e.rotation_mode = "QUATERNION"
        e.rotation_quaternion = Vector(axis).normalized().to_track_quat("Z", "Y")
    e.parent = root
    C.coll("prop").objects.link(e)
    parts.append(e)
    return e


def seat_marks(K, root, parts):
    for i, s in enumerate(K["seats"]):
        mark("seat_%d" % i, s, root, parts)


def cut_with(o, shapes):
    """穴をあける: shapes は (中心, 軸, 軸に沿った長さ, 横の半径 r1, r2, r1 の向き) の楕円の柱。
    厚みを付けたあとに引く。切る形は書き出さない（根元の子にしない）"""
    m = bmesh.new()
    for c, ax, ln, r1, r2, side in shapes:
        ax = Vector(ax).normalized()
        s = Vector(side) - ax * ax.dot(Vector(side))
        s.normalize()
        u = ax.cross(s)
        mtx = Matrix((s * r1, u * r2, ax * ln)).transposed().to_4x4()
        mtx.translation = Vector(c)
        bmesh.ops.create_cone(m, cap_ends=True, segments=20, radius1=1.0, radius2=1.0, depth=1.0, matrix=mtx)
    me = bpy.data.meshes.new(o.name + "_cut")
    m.to_mesh(me)
    m.free()
    cutter = bpy.data.objects.new(o.name + "_cut", me)
    C.coll("cut").objects.link(cutter)
    cutter.hide_render = True
    b = o.modifiers.new("holes", "BOOLEAN")
    b.operation, b.solver, b.object = "DIFFERENCE", "EXACT", cutter
    return cutter


def strip(m, pts, widths, height_at, lift=0.0015, thick=0.0012):
    """面に貼った平たい帯（印刷・アップリケ）。pts は平面の (x, y)、widths は点ごとの幅。
    height_at(x, y) が下の面の高さ。薄い厚みのある閉じた形にする（面の向きが裏返らないように）"""
    pts = [Vector((p[0], p[1], 0)) for p in pts]
    ws = widths if isinstance(widths, (list, tuple)) else [widths] * len(pts)
    top, bot = [], []
    for i, p in enumerate(pts):
        a, b = pts[max(0, i - 1)], pts[min(len(pts) - 1, i + 1)]
        t = (b - a).normalized()
        sd = Vector((-t.y, t.x, 0)) * max(ws[i], 0.002) / 2
        row_t, row_b = [], []
        for q in (p - sd, p + sd):
            z = height_at(q.x, q.y) + lift
            row_t.append(m.bm.verts.new((q.x, q.y, z)))
            row_b.append(m.bm.verts.new((q.x, q.y, z - thick)))
        top.append(row_t)
        bot.append(row_b)
    for i in range(len(pts) - 1):
        m.bm.faces.new((top[i][0], top[i][1], top[i + 1][1], top[i + 1][0]))
        m.bm.faces.new((bot[i][0], bot[i + 1][0], bot[i + 1][1], bot[i][1]))
        m.bm.faces.new((bot[i][0], top[i][0], top[i + 1][0], bot[i + 1][0]))
        m.bm.faces.new((top[i][1], bot[i][1], bot[i + 1][1], top[i + 1][1]))
    m.bm.faces.new((bot[0][0], bot[0][1], top[0][1], top[0][0]))
    m.bm.faces.new((top[-1][0], top[-1][1], bot[-1][1], bot[-1][0]))


def taper(n, w, head=0.3, tail=0.5, w0=0.35):
    """筆の線の幅: 入りで太り、終わりで細る"""
    out = []
    for i in range(n):
        t = i / (n - 1)
        k = min(1.0, w0 + (1 - w0) * t / head) if t < head else 1.0 - (1.0 - 0.15) * max(0.0, (t - (1 - tail)) / tail)
        out.append(w * k)
    return out


def line_pts(a, b, n=8):
    return [Vector(a).lerp(Vector(b), i / (n - 1)) for i in range(n)]


def super_ring(a, b, n=5.0, count=96):
    """超楕円の周を等間隔に count 点と、外向きの法線。C.ellipse_ring と同じ形だが、極座標
    r(φ) = (|cos φ / a|^n + |sin φ / b|^n)^(-1/n) で密に取り、長さで補って間引く（細長い形でも点が重ならない）"""
    dense = []
    for i in range(4000):
        f = 2 * math.pi * i / 4000
        c, sn = math.cos(f), math.sin(f)
        r = (abs(c / a) ** n + abs(sn / b) ** n) ** (-1 / n)
        dense.append(Vector((r * c, r * sn, 0)))
    cum = [0.0]
    for i in range(1, len(dense) + 1):
        cum.append(cum[-1] + (dense[i % len(dense)] - dense[i - 1]).length)
    pts, nrm, j = [], [], 0
    for k in range(count):
        target = cum[-1] * k / count
        while cum[j + 1] < target:
            j += 1
        p, q = dense[j], dense[(j + 1) % len(dense)]
        pts.append(p.lerp(q, (target - cum[j]) / max(1e-9, cum[j + 1] - cum[j])))
        t = (q - p).normalized()
        nrm.append(Vector((t.y, -t.x, 0)))
    return pts, nrm


# ---------------------------------------------------------------- 小: 成形ソリ
def build_small(ox=0.0, export=False):
    """ホームセンターのプラスチックのソリ（1〜2 人、縦に並ぶ）を、型に入れて固めた厚いフェルトで作る。
    平たい盆の形に低い縁、前は上へ反って穴に紐を通す。横に握りの穴、縁はバイアステープでくるむ。
    形は「盆」を平らに作ってから前を曲げる: 中心から縁へ輪を重ね、縁の近くで立ち上げて壁にする"""
    root, K = new_root("small")
    parts = []
    A_, B_ = 0.355, 0.875           # 平らに広げたときの半分の幅と長さ（縁の外）
    YC = 0.1                        # 広げたときの中心（前へずらす。前は反って縮む）
    YB, RB = 0.42, 0.32             # ここより前を、この半径で上へ曲げる
    Z0 = 0.03                       # 底の面の高さ（下の滑り木の筋が雪に着く）
    WD, RC = 0.07, 0.035            # 壁の付け根の内側への入り、底の角の丸み
    HS, HF = 0.135, 0.02            # 壁の高さ（横と後ろ / 前の端）

    def bend(p):
        p = Vector(p)
        if p.y > YB:
            th = (p.y - YB) / RB
            d = p.z
            p = Vector((p.x, YB + (RB - d) * math.sin(th), RB - (RB - d) * math.cos(th)))
        return p + Vector((0, 0, Z0))

    def wall_h(ey):   # 縁の点の前後の位置で、壁の高さ
        t = max(0.0, min(1.0, ((ey - YC) / B_ - 0.55) / 0.4))
        return HS + (HF - HS) * t * t * (3 - 2 * t)

    def prof(u, h):   # 壁の断面: 内への入り と 高さ（u: 0 = 壁の付け根、1 = 縁）
        rc = min(RC, h * 0.7)
        if u < 0.4:
            a = u / 0.4 * math.pi / 2
            return WD - rc * math.sin(a), rc * (1 - math.cos(a))
        v = (u - 0.4) / 0.6
        return (WD - rc) * (1 - v), rc + (h - rc) * v

    n_ring = 64 if export else 112
    edge, enrm = super_ring(A_, B_, n=5.0, count=n_ring)
    edge = [p + Vector((0, YC, 0)) for p in edge]
    FLOOR_R, WALL_R = 7, 10
    shell = C.M("shell", "felt_red")
    bm = shell.bm
    center = bm.verts.new(bend((0, YC, 0)))
    rings = []
    for k in range(1, FLOOR_R + WALL_R + 1):
        ring = []
        for p, n in zip(edge, enrm):
            h = wall_h(p.y)
            if k <= FLOOR_R:
                q = p - n * WD
                c = Vector((0, YC, 0))
                q = c + (q - c) * (k / FLOOR_R)
                z = 0.0
            else:
                ins, z = prof((k - FLOOR_R) / WALL_R, h)
                q = p - n * ins
            ring.append(bm.verts.new(bend((q.x, q.y, z))))
        rings.append(ring)
    N = len(edge)
    for j in range(N):
        bm.faces.new((center, rings[0][j], rings[0][(j + 1) % N]))
    for k in range(len(rings) - 1):
        for j in range(N):
            j2 = (j + 1) % N
            bm.faces.new((rings[k][j], rings[k + 1][j], rings[k + 1][j2], rings[k][j2]))
    shell_o = shell.done(parent=root)
    so = shell_o.modifiers.new("thick", "SOLIDIFY")
    so.thickness, so.offset = 0.014, 0.0

    # 穴: 前の反りに紐を通す 2 つ、横に握りを 2 つずつ（座る人ごと）
    def surf(x, y, d=0.0):
        """平らに広げた (x, y) の、底の面から d 上の点と、そこの面の上の向き"""
        p = bend((x, y, d))
        th = max(0.0, (y - YB) / RB)
        return p, Vector((0, -math.sin(th), math.cos(th)))

    y_tip = YC + B_
    y_hole = y_tip - WD - 0.075
    holes = []
    ties = []
    for sx in (-1, 1):
        p, nrm = surf(sx * 0.17, y_hole)
        holes.append((p, nrm, 0.12, 0.05, 0.02, (1, 0, 0)))
        ties.append(surf(sx * 0.17, y_hole + 0.042)[0])
    for sy in (0.42, -0.28):                   # 握り: 座る所の少し前の、横の壁
        for sx in (-1, 1):
            p = bend((sx * (A_ - 0.012), sy, HS * 0.62))
            holes.append((p, (1, 0, 0), 0.07, 0.055, 0.016, (0, 1, 0)))
    cut_with(shell_o, holes)
    parts.append(shell_o)

    # 縁: クリームのバイアステープでくるみ、内側を赤い糸で押さえる。穴のまわりはボタンホールかがり
    tape = C.M("binding", "felt_cream")
    rim = []
    for p, n in zip(edge, enrm):
        rim.append(bend((p.x, p.y, wall_h(p.y) + 0.004)))
    C.tube(tape, rim + rim[:2], 0.014, sides=10, caps=False)
    parts.append(tape.done(parent=root))
    thread = C.M("stitches", "thread_red")
    line = []
    for p, n in zip(edge, enrm):
        h = wall_h(p.y)
        q = p - n * 0.011
        line.append(bend((q.x, q.y, h - 0.028)))
    C.running_stitch(thread, line + line[:1], [Vector((0, 0, 1))], dash=0.026, gap=0.014, r=0.0042)
    # 座る所: 底に楕円のなみ縫い（ここに座る、のしるし）
    for s in K["seats"]:
        ov, _n = super_ring(0.19, 0.24, n=3.0, count=60)
        pts = [bend((p.x, p.y + s[1], 0.0085)) for p in ov]
        C.running_stitch(thread, pts + pts[:1], [Vector((0, 0, 1))], dash=0.03, gap=0.016, r=0.0042)
    for c, ax, ln, r1, r2, side in holes:     # 穴のまわりのかがり（楕円の輪）
        ax = Vector(ax).normalized()
        s = Vector(side) - ax * ax.dot(Vector(side))
        s.normalize()
        u = ax.cross(s)
        for face in (1, -1):
            ring = [Vector(c) + ax * face * 0.0085 + s * (r1 + 0.006) * math.cos(a) + u * (r2 + 0.006) * math.sin(a)
                    for a in [2 * math.pi * i / 28 for i in range(29)]]
            C.tube(thread, ring, 0.0045, sides=4)
    parts.append(thread.done(parent=root))

    # 下の滑り木の筋: 底に縫い付けた細長いフェルトの帯（押し出した筋の代わり）
    ridge = C.M("ridges", "felt_red_dark")
    for x in K["runners"]:
        pts = [bend((x, y, -0.016)) for y in [-0.66 + (y_tip - 0.2 + 0.66) * i / 30 for i in range(31)]]
        C.tube(ridge, pts, 0.03, sides=10, side=(1, 0, 0), ry=0.012, sq=3.0)
    parts.append(ridge.done(parent=root))

    seat_marks(K, root, parts)
    for t, nm in zip(ties, ("rope_tie_l", "rope_tie_r")):   # 前の穴と縁のあいだ。紐は穴を通って縁を巻く（軸は左右）
        mark(nm, t, root, parts, axis=(1, 0, 0))
    root.location.x = ox
    return root, parts, K, K["runners"], -K["L"] / 2


# ---------------------------------------------------------------- 大: サンタのそり
def build_large(ox=0.0, export=False):
    """サンタのそり。赤いフェルトの胴（前は高く反り返る板、後ろは背の高い背板、横は中ほどが低い）を、
    前で大きく渦を巻く曲げ木の滑り木に載せる。縁は金茶の毛糸の撚りひも、横に渦の飾り。
    中は緑のフェルトの長椅子が 4 列（2 人ずつ）。前の両角に鈴"""
    root, K = new_root("large")
    parts = []
    RX = 0.95                       # 滑り木の x
    RR = 0.032                      # 滑り木の太さ（半径）。紐の巻きはこの外
    Y_CURL, R = 1.7, 0.5            # 前の反りの始まりと半径
    Z_FLOOR = 0.27                  # 床の上
    XW = 0.98                       # 横板の x

    # 滑り木: 後ろは少し反り、前で上へ大きく渦を巻く
    bent = C.M("runners", "wood_bent")
    for x in (-RX, RX):
        pts = [Vector((x, -2.24, RR + 0.07)), Vector((x, -2.17, RR + 0.02)), Vector((x, -2.08, RR))]
        for i in range(1, 13):
            pts.append(Vector((x, -2.08 + (Y_CURL + 2.08) * i / 12, RR)))
        for i in range(1, 37):     # 下から前へ、上へ、後ろへ回って内へ巻き込む
            a = math.radians(-90 + i * 8.0)
            rr = R * (1 - 0.55 * max(0.0, i * 8.0 - 180) / 108)
            pts.append(Vector((x, Y_CURL + rr * math.cos(a), RR + R + rr * math.sin(a))))
        C.tube(bent, pts, RR, sides=14, sq=2.6)
    parts.append(bent.done(parent=root))

    # 支え: 滑り木から胴の下へ、少し内へ寄る丸棒。床の下の桁
    wood = C.M("struts", "wood")
    for x in (-RX, RX):
        for y in (-1.95, -1.1, -0.3, 0.5, 1.3):
            C.tube(wood, [Vector((x, y, RR * 1.5)), Vector((x * 0.97, y + 0.04, Z_FLOOR - 0.05))], 0.026, sides=8)
        C.tube(wood, [Vector((x * 0.97, -2.1, Z_FLOOR - 0.055)), Vector((x * 0.97, 1.86, Z_FLOOR - 0.055))], 0.03, sides=8)
    parts.append(wood.done(parent=root))

    # 床: 縦の板
    board = C.M("floor", "wood_dark")
    n_b = 9
    for i in range(n_b):
        x = -XW + 0.04 + (2 * XW - 0.08) * (i + 0.5) / n_b
        bmesh.ops.create_cube(board.bm, size=1.0, matrix=Matrix.Translation((x, -0.12, Z_FLOOR - 0.017))
                              @ Matrix.Diagonal(((2 * XW - 0.08) / n_b - 0.012, 3.98, 0.034, 1)))
    parts.append(board.done(smooth=False, bevel=0.006, seg=2, parent=root))

    felt = C.M("body", "felt_red")
    gold = C.M("trim", "yarn_yellow")

    # 前の板: 床の前から立ち上がり、前へ反り返って少し巻く
    dash = [Vector((0, 1.86, Z_FLOOR - 0.01)), Vector((0, 1.93, 0.45)), Vector((0, 2.0, 0.66)), Vector((0, 2.07, 0.86)),
            Vector((0, 2.15, 1.0)), Vector((0, 2.25, 1.08)), Vector((0, 2.33, 1.08)), Vector((0, 2.36, 1.02)),
            Vector((0, 2.33, 0.97))]
    C.tube(felt, dash, XW - 0.06, sides=24, side=(1, 0, 0), ry=0.035, sq=8.0)
    # 後ろの背板: 背が高く、上で後ろへ巻く
    back = [Vector((0, -2.1, Z_FLOOR - 0.01)), Vector((0, -2.14, 0.6)), Vector((0, -2.16, 0.92)), Vector((0, -2.2, 1.12)),
            Vector((0, -2.27, 1.24)), Vector((0, -2.34, 1.26)), Vector((0, -2.37, 1.2)), Vector((0, -2.34, 1.14))]
    C.tube(felt, back, XW - 0.03, sides=24, side=(1, 0, 0), ry=0.04, sq=8.0)

    # 横の板: 下はまっすぐ、上は後ろで高く、中ほどで低く、前の板へ上がる
    def side_top(y):
        if y < -1.2:
            t = (y + 2.15) / 0.95
            return 1.1 + (0.8 - 1.1) * (t * t * (3 - 2 * t))
        if y > 1.2:
            t = (y - 1.2) / 0.8
            return 0.8 + (1.0 - 0.8) * (t * t * (3 - 2 * t))
        return 0.8
    ys = [-2.13 + (2.0 + 2.13) * i / 40 for i in range(41)]
    for sx in (-1, 1):
        xo = sx * XW
        # 板: y ごとに下と上の 2 点を、内と外の 2 枚に。四角の面だけで組む（上の縁がへこむ形なので）
        cols = [[felt.bm.verts.new((xo + dx, y, z)) for dx, z in ((-0.026, Z_FLOOR - 0.03), (-0.026, side_top(y)),
                                                                (0.026, side_top(y)), (0.026, Z_FLOOR - 0.03))] for y in ys]
        for c0, c1 in zip(cols, cols[1:]):
            for k in range(4):
                felt.bm.faces.new((c0[k], c1[k], c1[(k + 1) % 4], c0[(k + 1) % 4]))
        felt.bm.faces.new(cols[0])
        felt.bm.faces.new(list(reversed(cols[-1])))
        # 縁の金の撚りひも（上の縁）
        C.tube(gold, [Vector((xo, y, side_top(y) + 0.008)) for y in ys], 0.019, sides=8)
        # 渦の飾り: 外の面に金の撚りひもで渦を 2 つ、そのあいだを波でつなぐ
        xf = xo + sx * 0.034
        for cy, cz, turn in ((-1.35, 0.54, 1), (1.2, 0.54, -1)):
            sp = []
            for i in range(60):
                t = i / 59
                a = turn * t * 2 * math.pi * 2.1
                r = 0.025 + 0.14 * t
                sp.append(Vector((xf, cy + r * math.cos(a), cz + r * math.sin(a))))
            C.tube(gold, sp, 0.012, sides=6)
        wave = [Vector((xf, y, 0.54 + 0.06 * math.sin((y + 1.35) / 2.55 * 2 * math.pi * 1.5))) for y in
                [-1.15 + 2.15 * i / 50 for i in range(51)]]
        C.tube(gold, wave, 0.01, sides=6)
        # 下の縁にも細い撚りひも
        C.tube(gold, [Vector((xo + sx * 0.03, y, Z_FLOOR - 0.01)) for y in ys], 0.011, sides=6)
    # 前の板と背板の縁
    for path, half, off in ((dash, XW - 0.06, 0.036), (back, XW - 0.03, 0.041)):
        for sx in (-1, 1):
            C.tube(gold, [p + Vector((sx * half, 0, 0)) for p in path], 0.016, sides=8)
        tip = path[-3]
        C.tube(gold, [Vector((-half, tip.y, tip.z)), Vector((half, tip.y, tip.z))], 0.018, sides=8)
    # 前の板の外: 大きな渦を 1 つずつ左右に
    for sx in (-1, 1):
        sp = []
        for i in range(60):
            t = i / 59
            a = -sx * t * 2 * math.pi * 2.0
            r = 0.02 + 0.14 * t
            q = Vector((sx * 0.42 + r * math.cos(a), 0, r * math.sin(a)))
            # 前の板の面（y は板の高さで決まる）にそわせる
            zq = 0.72 + q.z
            yq = 1.93 + (zq - 0.45) / (0.86 - 0.45) * (2.07 - 1.93) + 0.045
            sp.append(Vector((q.x, yq, zq)))
        C.tube(gold, sp, 0.012, sides=6)
    parts.append(felt.done(bevel=0.012, seg=2, parent=root))

    # 長椅子: 4 列。木の台に、人ごとに緑のフェルトの座布団、後ろに背もたれ
    seat_felt = C.M("cushions", "felt_holly")
    thread = C.M("stitches", "thread")
    button = C.M("buttons", "button")
    bench = C.M("benches", "wood")

    def cushion(center, half, rot_x=0.0, tuft=True):
        mtx = Matrix.Translation(center) @ Matrix.Rotation(rot_x, 4, "X")
        a, b, c = half
        dent = (0.03, min(a, b) * 0.35) if tuft else None
        bf, bt, bb = len(seat_felt.bm.verts), len(thread.bm.verts), len(button.bm.verts)
        C.superellipsoid(seat_felt, (0, 0, 0), half, n_xy=5.0, n_z=2.4, cuts=6 if export else 9, dent=dent)
        pts, nrm = C.ellipse_ring(a, b, n=5.0, count=max(24, int(2 * (a + b) * 2 / 0.05)), z=0.0, inset=0.004)
        C.seam_whip(seat_felt, thread, pts, nrm, every=2 if export else 1)
        if tuft:
            top = c - dent[0] + 0.004
            bmesh.ops.create_cone(button.bm, cap_ends=True, segments=14, radius1=0.032, radius2=0.028, depth=0.012,
                                  matrix=Matrix.Translation((0, 0, top + 0.006)))
        C.place(seat_felt, bf, mtx)
        C.place(thread, bt, mtx)
        C.place(button, bb, mtx)

    for y in (1.65, 0.55, -0.55, -1.65):
        bmesh.ops.create_cube(bench.bm, size=1.0, matrix=Matrix.Translation((0, y + 0.02, (Z_FLOOR + 0.41) / 2))
                              @ Matrix.Diagonal((2 * XW - 0.1, 0.5, 0.41 - Z_FLOOR, 1)))
        bmesh.ops.create_cube(bench.bm, size=1.0, matrix=Matrix.Translation((0, y - 0.36, 0.64))
                              @ Matrix.Rotation(math.radians(-10), 4, "X") @ Matrix.Diagonal((2 * XW - 0.1, 0.035, 0.66, 1)))
        for x in (-0.47, 0.47):
            cushion((x, y + 0.02, 0.475), (0.44, 0.24, 0.062))
        cushion((0, y - 0.31, 0.77), (2 * XW / 2 - 0.08, 0.17, 0.055), rot_x=math.radians(100), tuft=False)
    parts.append(seat_felt.done(parent=root))
    parts.append(button.done(parent=root))
    parts.append(bench.done(smooth=False, bevel=0.01, seg=2, parent=root))
    parts.append(thread.done(parent=root))

    # 鈴: 前の板の上の両角から、金の撚りひもで吊るしたフェルトの鈴
    bell = C.M("bells", "felt_gold")
    for sx in (-1, 1):
        top = Vector((sx * (XW - 0.1), 2.3, 1.06))
        c = top + Vector((0, 0.06, -0.16))
        C.tube(gold, [top, top + Vector((0, 0.04, -0.07)), c + Vector((0, 0, 0.05))], 0.007, sides=5)
        C.superellipsoid(bell, c, (0.05, 0.05, 0.048), n_xy=2.0, n_z=2.0, cuts=4)
        C.tube(bell, [c + Vector((-0.03, -0.05, -0.008)), c + Vector((0.03, -0.05, -0.008))], 0.006, sides=4)
    parts.append(bell.done(parent=root))
    parts.append(gold.done(parent=root))

    seat_marks(K, root, parts)
    for sx, nm in ((-1, "rope_tie_l"), (1, "rope_tie_r")):   # 滑り木の渦のいちばん前（ここは縦に立つ。軸は上）
        mark(nm, (sx * RX, Y_CURL + R, RR + R), root, parts, axis=(0, 0, 1))
    root.location.x = ox
    return root, parts, K, K["runners"], -2.1


# ---------------------------------------------------------------- 米袋
def build_sack(ox=0.0, export=False):
    """子どもが尻に敷いて滑る米袋。クラフト紙の袋にわらを少し詰め、口（前）と底（後ろ）はミシンで縫い閉じる
    （本物の米袋も、口を紙テープの上から糸で縫う）。前の両耳に穴をあけて紐を結ぶ。
    表に赤い丸に「米」、両脇に稲穂の印刷。座る所は少しへこみ、紙の折りじわ"""
    root, K = new_root("sack")
    parts = []
    A_, B_ = 0.26, 0.49             # 半分の幅と長さ
    T0 = 0.13                       # まんなかの厚み
    BAND = 0.075                    # 縫い閉じた端の平らな帯
    SEAT = Vector((0, K["seats"][0][1]))
    rnd = __import__("random").Random(4)
    creases = []
    for i in range(7):              # 折りじわ: 袋をたたんだ跡の線（山と谷）
        ang = rnd.uniform(0, math.pi)
        creases.append((Vector((math.cos(ang), math.sin(ang))), rnd.uniform(-0.35, 0.35), rnd.choice((-1, 1)) * rnd.uniform(0.002, 0.004)))
    creases.append((Vector((1, 0)), 0.0, -0.004))    # まんなかの縦の折り目

    def ends(y):
        """前後の端で平らにつぶれる割合（1 = ふくらむ、端の帯で ≈0.09）"""
        d = B_ - abs(y)
        t = max(0.0, min(1.0, (d - BAND) / 0.12))
        e = 0.09 + 0.91 * t * t * (3 - 2 * t)
        return e * max(0.0, 1 - (abs(y) / B_) ** 40) ** 0.5

    def thick(x, y):
        xs = max(0.0, 1 - abs(x / A_) ** 3) ** 0.5
        dent = 1 - 0.13 * math.exp(-((x / 0.16) ** 2 + ((y - SEAT.y) / 0.2) ** 2))
        return T0 * ends(y), T0 * ends(y) * xs * dent

    def bottom(x, y):
        full, t = thick(x, y)
        return 0.004 + 0.3 * (full - t)

    def top(x, y):
        full, t = thick(x, y)
        z = bottom(x, y) + t
        k = min(1.0, t / 0.03)       # しわは厚みのある所だけ
        for d, off, amp in creases:
            dist = Vector((x, y)).dot(Vector((d.y, -d.x))) - off
            z += amp * math.exp(-(dist / 0.014) ** 2) * k
        band = max(0.0, 1 - (B_ - abs(y)) / (BAND + 0.04))   # 縫い閉じた所のひだ
        z += 0.004 * band * math.sin(x * 70) * min(1.0, abs(x) / 0.05 + 0.3)
        return z

    nx, ny = (18, 36) if export else (30, 60)
    paper = C.M("sack", "paper_kraft")
    grid_t, grid_b = [], []
    for j in range(ny + 1):
        y = -B_ + 2 * B_ * j / ny
        rt, rb = [], []
        for i in range(nx + 1):
            u = -1 + 2 * i / nx
            x = A_ * math.copysign(abs(u) ** 0.8, u)      # 縁の近くを細かく
            rt.append(paper.bm.verts.new((x, y, top(x, y))))
            rb.append(paper.bm.verts.new((x, y, bottom(x, y))))
        grid_t.append(rt)
        grid_b.append(rb)
    for j in range(ny):
        for i in range(nx):
            paper.bm.faces.new((grid_t[j][i], grid_t[j][i + 1], grid_t[j + 1][i + 1], grid_t[j + 1][i]))
            paper.bm.faces.new((grid_b[j][i], grid_b[j + 1][i], grid_b[j + 1][i + 1], grid_b[j][i + 1]))
    edge = [grid_t[j][0] for j in range(ny + 1)] + [grid_t[j][nx] for j in range(ny + 1)] + grid_t[0] + grid_t[ny]
    edge_b = [grid_b[j][0] for j in range(ny + 1)] + [grid_b[j][nx] for j in range(ny + 1)] + grid_b[0] + grid_b[ny]
    for a, b in zip(edge, edge_b):   # 周りでは上と下が重なる（厚み 0）。つなぐ
        b.co = a.co.copy()
    bmesh.ops.remove_doubles(paper.bm, verts=list(set(edge + edge_b)), dist=1e-4)
    parts.append(paper.done(parent=root))

    # 印刷: 赤い丸に「米」の筆の字、両脇に稲穂、前に赤い 2 本の帯
    red = C.M("print_red", "paper_red")
    green = C.M("print_green", "paper_green")
    grain = C.M("print_gold", "paper_gold")
    cx, cy, s = 0.0, 0.2, 0.066
    ring = [(cx + 1.42 * s * math.cos(a), cy + 1.42 * s * math.sin(a)) for a in [2 * math.pi * i / 48 for i in range(49)]]
    strip(red, ring, 0.011, top)
    for a, b in (((-0.85, 0.02), (0.85, 0.05)), ((0.0, 0.95), (0.02, -0.98)), ((-0.6, 0.68), (-0.36, 0.34)),
                 ((0.6, 0.7), (0.36, 0.36)), ((-0.1, -0.08), (-0.74, -0.78)), ((0.1, -0.08), (0.78, -0.72))):
        pts = [(cx + p.x * s, cy + p.y * s) for p in line_pts(a, b, 9)]
        strip(red, pts, taper(9, 0.24 * s), top)
    for sx in (-1, 1):               # 稲穂: 丸のまわりに弧を描く茎、外向きの籾、下に葉
        stem = []
        for i in range(14):
            a = math.radians(250 - 120 * i / 13)
            stem.append((cx + sx * 0.14 * -math.cos(a), cy + 0.14 * math.sin(a) + 0.006))
        stem = [(sx * abs(p[0]), p[1]) for p in stem]
        strip(green, stem, taper(14, 0.0055, head=0.1, tail=0.3), top)
        for i in range(4, 14):
            p = Vector(stem[i])
            q = Vector(stem[min(13, i + 1)]) - Vector(stem[i - 1])
            q.normalize()
            out = Vector((q.y, -q.x)) * (sx if i % 2 else -sx)
            g0 = p + out * 0.004
            g1 = p + out * 0.02 + q * 0.014
            strip(grain, line_pts(g0, g1, 5), taper(5, 0.0085, head=0.5, tail=0.5, w0=0.4), top)
        lf = [(sx * (0.05 + 0.09 * t), cy - 0.115 + 0.035 * t - 0.035 * t * t) for t in [i / 9 for i in range(10)]]
        strip(green, lf, taper(10, 0.014, head=0.3, tail=0.6), top)
    for yy in (0.36, 0.385):
        strip(red, [(x, yy) for x in [-A_ + 0.03 + (2 * A_ - 0.06) * i / 24 for i in range(25)]], 0.009, top)
    parts.append(red.done(parent=root))
    parts.append(green.done(parent=root))
    parts.append(grain.done(parent=root))

    # 口と底: 紙テープを折りかぶせ、赤い糸のくさり縫い。前の両耳に穴と紐の巻き場所
    tape = C.M("tape", "paper_tape")
    thread = C.M("seam", "thread_red")
    for sy in (1, -1):
        yy = sy * (B_ - 0.04)
        strip(tape, [(x, yy) for x in [-A_ + 0.004 + (2 * A_ - 0.008) * i / 30 for i in range(31)]], 0.038, top,
              lift=0.0035, thick=0.003)
        pts = [Vector((x, yy, top(x, yy) + 0.006)) for x in [-A_ + 0.01 + (2 * A_ - 0.02) * i / 60 for i in range(61)]]
        chain_stitch(thread, pts, size=0.024, width=0.012, r=0.0026)
    for sx in (-1, 1):               # 耳の穴: 紐を通すためにあけた穴のかがり
        c = Vector((sx * (A_ - 0.068), B_ - 0.045, 0))
        ringp = [Vector((c.x + 0.011 * math.cos(a), c.y + 0.011 * math.sin(a), top(c.x, c.y) + 0.004))
                 for a in [2 * math.pi * i / 16 for i in range(17)]]
        C.tube(thread, ringp, 0.003, sides=4)
    parts.append(tape.done(parent=root))
    parts.append(thread.done(parent=root))

    seat_marks(K, root, parts)
    for sx, nm in ((-1, "rope_tie_l"), (1, "rope_tie_r")):   # 前の耳の角。紐は穴を通って耳の縁を巻く（軸は前後）
        x = sx * (A_ - 0.03)
        mark(nm, (x, B_ - 0.045, top(x, B_ - 0.045)), root, parts, axis=(0, 1, 0))
    root.location.x = ox
    return root, parts, K, K["runners"], -B_


BUILD = {"mid": build, "small": build_small, "large": build_large, "sack": build_sack}



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
if A.kind == "all":   # 4 台を並べる（描くときだけ）
    LINE = (("sack", -3.4), ("small", -2.3), ("mid", 0.0), ("large", 3.1))
else:
    LINE = ((A.kind, 0.0),)
built = [BUILD[k](k, ox, bool(A.export)) if k == "mid" else BUILD[k](ox, bool(A.export)) for k, ox in LINE]

if not A.export:
    if A.trail:
        for root, parts, K, xs, y_back in built:
            trail(K["trail"], xs, -K["L"] / 2 - 0.1, root.location.x)
    C.ground(80.0)
    C.light()
    C.setup_render(A.size)
    s = KINDS[A.kind]["L"] / 2.8 if A.kind != "all" else 1.0
    cams = {
        "quarter": ((-2.6 * s, 3.2 * s, 1.7 * s), (0, -0.1 * s, 0.25 * s), 40),
        "side": ((-4.6 * s, 0.0, 0.9 * s), (0, 0, 0.3 * s), 45),
        "back": ((2.6 * s, -3.6 * s, 1.8 * s), (0, 0.1 * s, 0.3 * s), 40),
        "low": ((-1.2 * s, 2.7 * s, 0.32 * s), (0.1 * s, 0.0, 0.3 * s), 30),
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
        KT.export_root(root, os.path.join(A.export, "%s.glb" % root.name), tris=K.get("tris", 2000))
