"""ロッジの寸法。図面（drawings.py）と Blender の台本（build_lodge.py）が同じ数を使う。

単位は m。1 間 K = 1.818 m（6 尺）を柱の間隔にする。
座標: x = 東、y = 北、z = 上。丘は南（-y）にあり、正面（丘に面した側）は南。
原点は 1 階の床面の中心の真下、雪の地面の高さ。
"""

K = 1.818            # 1 間

# ---- 1 階（土間の大広間）10 間 x 6 間 ----
X0, X1 = -5 * K, 5 * K          # -9.09 .. 9.09
Y0, Y1 = -3 * K, 3 * K          # -5.454 .. 5.454（Y0 が南＝丘の側）
PLINTH = 0.80                   # 石の基壇の高さ＝1 階の床
H1 = 2 * K                      # 1 階の階高 3.636
FL2 = PLINTH + H1               # 2 階の床 4.436
FLOOR2_T = 0.45                 # 2 階の床の構造の厚み（下は 1 階の天井）
WALL_T = 0.20                   # 外壁の厚み
POST = 0.16                     # 柱の太さ

# ---- 2 階（掘りごたつの座敷）8 間 x 4 間。西にそろえ、南を 2 間さげる ----
X2_0, X2_1 = X0, X0 + 8 * K     # -9.09 .. 5.454
Y2_0, Y2_1 = Y0 + 2 * K, Y1     # -1.818 .. 5.454
H2 = 2.20                       # 2 階の壁の高さ（床から桁まで）。上は屋根の中
EAVE_Z = FL2 + H2               # 6.636 桁の上端
# 屋根は腰折れ（北海道の牧舎の形）。下の急な流れは雪が載らず藍のフェルトが見え、
# 上のゆるい流れに雪が積もる。軒先は 4 寸 5 分にはね出して影の帯を落とす。
LOW_RUN, LOW_RISE = 0.72, 1.25  # 下の流れ（60 度）
KNEE_Z = EAVE_Z + LOW_RISE      # 7.886 折れ点
UPPER_PITCH = 0.5               # 上の流れ 5 寸
RIDGE_Y = (Y2_0 + Y2_1) / 2     # 棟の位置 1.818
RIDGE_Z = KNEE_Z + ((Y2_1 - Y2_0) / 2 - LOW_RUN) * UPPER_PITCH   # 9.052
EAVE_OUT = 0.75                 # 軒の出（1 階の階高の 21%）
KICK = 0.45                     # 軒先のはね出しの勾配
EAVE_EDGE_Z = EAVE_Z - EAVE_OUT * KICK   # 6.299
VERGE_OUT = 0.50                # けらばの出
ROOF_T = 0.22                   # 屋根（藍のフェルトの板）の厚み
SNOW_T = 0.34                   # 屋根の雪（毛糸の編み地）の厚み
# 屋根の下端の線（南の軒先 → 棟 → 北の軒先）。y-z の折れ線
ROOF_LINE = [(Y2_0 - EAVE_OUT, EAVE_EDGE_Z), (Y2_0, EAVE_Z), (Y2_0 + LOW_RUN, KNEE_Z), (RIDGE_Y, RIDGE_Z),
             (Y2_1 - LOW_RUN, KNEE_Z), (Y2_1, EAVE_Z), (Y2_1 + EAVE_OUT, EAVE_EDGE_Z)]


def offset_line(pts, d):
    """折れ線を外（上）側へ d だけ平行にずらす（角は留め）"""
    import math
    out = []
    n = len(pts)
    def nrm(a, b):
        dy, dz = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dy, dz)
        return (-dz / L, dy / L)
    for i in range(n):
        if i == 0:
            ny, nz = nrm(pts[0], pts[1])
        elif i == n - 1:
            ny, nz = nrm(pts[-2], pts[-1])
        else:
            a, b = nrm(pts[i - 1], pts[i]), nrm(pts[i], pts[i + 1])
            ny, nz = a[0] + b[0], a[1] + b[1]
            L = (ny * a[0] + nz * a[1])
            ny, nz = ny / L, nz / L
        out.append((pts[i][0] + ny * d, pts[i][1] + nz * d))
    return out


def roof_z(y):
    """屋根の下端の線の高さ（y の位置で）"""
    for (y0, z0), (y1, z1) in zip(ROOF_LINE, ROOF_LINE[1:]):
        if y0 <= y <= y1:
            return z0 + (z1 - z0) * (y - y0) / (y1 - y0)
    return None


# ---- テラス（1 階の屋上。南の帯 10 x 2 間 + 東の帯 2 x 4 間）----
CANTI = 0.90                    # 南へ片持ちで張り出す（半間）。持ち送りで支える
DECK_T = 0.10
DECK_Z = FL2 - 0.12             # テラスの床（座敷より 1 段低く、水を切る）
FASCIA_H = 0.42                 # テラスの縁の梁（鼻隠し）の高さ
RAIL_H = 1.10                   # 手すり（1 階の階高の 0.30。建築基準法の 1.1 m）
BALUSTER = 0.152                # 縦材の間隔（1 間の 1/12）

# ---- 下屋（東の貸し出し・ソリ置き）3 間 x 4 間 片流れ ----
WX0, WX1 = X1, X1 + 3 * K       # 9.09 .. 14.544
WY0, WY1 = -2 * K, 2 * K        # -3.636 .. 3.636（南を 1 間さげる）
W_FL = 0.15                     # 下屋の床（ソリを引き込めるよう地面に近い）
W_HIGH = 3.60                   # 母屋の壁に当たる側の桁の高さ（テラスの縁の梁の下に収める）
W_PITCH = 0.25                  # 2 寸 5 分勾配で東へ下がる
W_EAVE_OUT = 0.6
W_LOW = W_HIGH - (WX1 - WX0) * W_PITCH   # 2.24

# ---- 煙突（西の妻に立つ石の塔）----
CH_Y = Y2_0 + K                 # 棟から 1 間南へずらす（妻の中心に置かない）
CH_W0, CH_D0 = 1.60, 1.10       # 下（1 階）の幅（y）と出（x）
CH_W1, CH_D1 = 1.20, 0.85       # 肩より上
CH_SHOULDER = FL2               # 肩（すぼまる高さ）
CH_TOP = RIDGE_Z + 0.95         # 棟より 0.9 m 上（雪の上に 0.4 m）
CH_CAP_OUT = 0.14               # 笠の出

# ---- 開口のモジュール ----
# 1 階の窓 0.9 x 1.8（1:2）、窓台 0.6、まぐさ 2.4。各間の中央に 1 つ
WIN1 = dict(w=0.90, h=1.80, sill=0.60, depth=0.16)
# 2 階の窓 0.86 x 1.55（1:1.8）、窓台 0.45、まぐさ 2.0（掃き出しと揃える）
WIN2 = dict(w=0.86, h=1.55, sill=0.45, depth=0.14)
# 2 階の掃き出し（テラスへ）: 1 間いっぱいのガラス戸 2 枚
SLIDE2 = dict(w=K - POST, h=2.00, sill=0.0, depth=0.12)
# 玄関: 1 間引っ込んだ壁に両開き 1.8 x 2.2 + 欄間 0.2（まぐさ 2.4 で窓と揃える）
DOOR1 = dict(w=1.80, h=2.40, sill=0.0, depth=0.20)
# 下屋のソリの戸（引き戸）と小窓
SHED_DOOR = dict(w=2.40, h=2.10, sill=0.0, depth=0.12)
WINS = dict(w=0.60, h=1.10, sill=0.70, depth=0.12)

# 玄関の引っ込み（1 階南、6・7 間目）
PORCH_X0, PORCH_X1 = X0 + 5 * K, X0 + 7 * K   # 0 .. 3.636
PORCH_DEPTH = K
PORCH_STEPS = 4                 # 基壇を 4 段で上がる（蹴上げ 0.2）
# 玄関の上だけテラスをさらに 1 間張り出し、石の束に立つ 2 本の柱で受ける（入口の印）
BAY_Y = Y0 - K                  # 張り出しの先 -7.272
BAY_POST = 0.24
BAY_PIER = dict(w=0.46, h=0.55)

# 壁ごとの開口。(間の番号, 種類)。間は壁の始点から 0, 1, 2 ...
# 1 階の南: 端の間は壁で閉じ、窓 4 つ・玄関・窓 2 つ
OPENINGS = {
    "1F_S": [(1, "win1"), (2, "win1"), (3, "win1"), (4, "win1"), (7, "win1"), (8, "win1")],
    "1F_W": [(1, "win1"), (4, "win1"), (5, "win1")],     # 煙突は 2 と 3 の境
    "1F_N": [(1, "win1"), (2, "win1"), (3, "win1"), (5, "win1"), (6, "win1"), (7, "win1")],   # 8・9 は荷物棚
    "1F_E": [(0, "win1"), (5, "win1")],                 # 1〜4 は下屋に開く
    "2F_S": [(1, "win2"), (2, "slide2"), (3, "win2"), (4, "win2"), (5, "slide2"), (6, "win2")],
    "2F_W": [(2, "win2"), (3, "win2")],                 # 煙突は 0 と 1 の境
    "2F_N": [(1, "win2"), (2, "win2"), (5, "win2"), (6, "win2")],
    "2F_E": [(1, "slide2"), (2, "win2")],
    "W_S": [(0.5, "shed_door")],                        # 0.5 = 0〜1 間目にまたがる
    "W_E": [(1, "wins"), (2, "wins")],
}
KINDS = {"win1": WIN1, "win2": WIN2, "slide2": SLIDE2, "door1": DOOR1,
         "shed_door": SHED_DOOR, "wins": WINS}

# 1 階の中の柱（2 階の南の壁と棟を受ける 2 列）
INNER_POSTS_Y = (Y2_0, RIDGE_Y)
INNER_POSTS_X = (X0 + 2 * K, X0 + 4 * K, X0 + 6 * K, X0 + 8 * K)

# ---- 中身 ----
STAIR = dict(x_bottom=X2_1, y0=Y1 - WALL_T / 2 - 1.0, y1=Y1 - WALL_T / 2,
             risers=20, rise=H1 / 20, tread=0.26)        # 北の壁に沿って西へ上る
STAIR["x_top"] = STAIR["x_bottom"] - (STAIR["risers"] - 1) * STAIR["tread"]
STOVE = dict(x=X0 + 1.25, y=CH_Y, w=0.75, d=0.55, h=0.80)  # 煙突の前
COUNTER = dict(x0=X0 + 1 * K, x1=X0 + 4 * K, y=Y1 - 1.9, d=0.60, h=1.05)
KOTATSU_X = (X0 + 1.5 * K, X0 + 4 * K, X0 + 6.5 * K)       # 掘りごたつ 3 卓
KOTATSU_Y = Y2_0 + 1 * K + 0.05
KOTATSU = dict(w=1.80, d=0.90, pit_w=1.50, pit_d=0.62, pit_depth=0.42, h=0.36)
