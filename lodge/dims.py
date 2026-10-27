"""ロッジの寸法。Blender の台本（massing は build_lodge.py の段階 1）が同じ数を使う。

元は代表の図面（drawings/daihyo.svg、1 間 = 54px）。そこから読み取った数に、
直した 3 点（煙突を高く、南の軒を深く、外階段を短く）を入れてある。
2026-10-27、代表の指示で間取りを 2 倍、高さを 1.5 倍にした（実寸ではゲームの丘とソリの中で小さく見えた）。
戸・窓台・手すり・階段の 1 段・椅子・畳など人が触れる物は、人の大きさのまま。

単位は m。1 間 K = 1.818 m（6 尺）は人の大きさの単位（畳・戸・階段の幅）。
間取りの格子 G = 2 間。代表の図面の 1 間を、この G に読み替える。
座標: x = 東、y = 北、z = 上。丘（ゲレンデ）は南（-y）にあり、正面は南。
原点は 1 階の外形の中心の真下、雪の地面の高さ。
"""

K = 1.818            # 1 間（人の大きさの単位）
PLAN = 2.0           # 間取りの倍率
TALL = 1.5           # 高さの倍率（2 倍にすると 2 階建てが丘と同じ高さになる）
G = K * PLAN         # 間取りの格子 3.636 m

# ---- 1 階（食堂）12 x 7 格子（43.6 x 25.5 m）----
X0, X1 = -6 * G, 6 * G            # -21.8 .. 21.8
Y0, Y1 = -3.5 * G, 3.5 * G        # -12.7 .. 12.7（Y0 が南＝丘の側）


def gx(n):
    """西の壁から n 格子（代表の平面の ③ 通りが 0）"""
    return X0 + n * G


def gy(n):
    """北の壁から n 格子（代表の平面の わ 通りが 0）"""
    return Y1 - n * G


PLINTH = 0.45                     # 石の基壇＝1 階の床（デッキと同じ。ソリを降りて上がれる高さ）
FL1 = PLINTH
CEIL1 = FL1 + 3.5 * TALL          # 1 階のガラスの上端＝天井 5.7
FLOOR2_T = 0.40                   # 2 階の床の厚み（縁の帯になる）
FL2 = CEIL1 + FLOOR2_T            # 2 階の床＝テラスの床 6.1

# 丸太（巻いたフェルトのロールに見立てる）。壁の厚み＝丸太の径。大きな壁なので丸太も太く
LOG_D = 0.36
LOG_H = 0.35                      # 1 段の高さ（丸太が少し重なる）
LOG_OUT = 0.40                    # 角で交差して突き出す長さ
POST = 0.36                       # ガラスの壁の柱

# ---- 2 階（休憩の座敷）12 間 x 5 間。南を 2 間さげ、さげた分がテラス ----
X2_0, X2_1 = X0, X1
Y2_0, Y2_1 = gy(5), Y1            # -2.727 .. 6.363
H2_S, H2_N = 4.30 * TALL, 2.45 * TALL   # 2 階の壁の高さ 6.45 / 3.68。南（丘の側）が高い片流れ
EAVE_S = FL2 + H2_S               # 8.55
EAVE_N = FL2 + H2_N               # 6.70
ROOF_PITCH = (EAVE_S - EAVE_N) / (Y2_1 - Y2_0)   # 約 1.5 寸。雪は北の裏へ落ちる
EAVE_OUT_S = 2.00                 # 南の軒（直した点）。垂木の先を見せて 2 階の壁に影の帯
EAVE_OUT_N = 1.00
VERGE_OUT = 1.60                  # 東西のけらば
ROOF_T = 0.40                     # 屋根（藍のフェルトの板）
SNOW_T = 0.35                     # 屋根の雪（毛糸の編み地）
RAFTER = dict(w=0.18, h=0.32, step=G / 3)


def roof_z(y):
    """屋根の下端（壁の上端の線）の高さ。y の位置で"""
    return EAVE_N + (Y2_1 - y) * ROOF_PITCH


# ---- テラス（1 階の屋上の南 2 間）----
RAIL_H = 1.10
BALUSTER = 0.15

# ---- 風除室（玄関）----
# 風除室（代表の記憶から）: 外は 1 階の屋根まである木のアーチの両開き戸で、ふだんは外へ開け放す。
# 中は広く、自販機 2 台と靴の雪を落とすマット。両脇は雪がたまらない金網。内の戸は自動ドア
VEST = dict(x1=gx(3.5) - 0.30, w=8.0, d=5.0, h=CEIL1, t=0.20, roof_out=0.50)
VEST["x0"] = VEST["x1"] - VEST["w"]
VEST["cx"] = (VEST["x0"] + VEST["x1"]) / 2
ARCH = dict(r=1.80, spring=FL1 + 3.15)    # アーチ戸: 幅 3.6 m、頂が床から 4.95 m（1 階の屋根の下）
DOOR_IN = dict(x0=VEST["cx"] - 1.5, x1=VEST["cx"] + 1.5, h=2.70)   # 1 階の壁の内の自動ドア（引き分け）
VENDING = dict(w=1.0, d=0.75, h=1.83, gap=0.08)   # 自販機 2 台。内の戸の西、1 階の壁を背に

# ---- 窓のモジュール: 1.5 間 x 1.95、窓台は床から 0.9。十字の桟で 4 枚 ----
WIN = dict(w=1.5 * K, h=1.95, sill=0.90, frame=0.08)
DOOR2 = dict(w=1.80, h=2.40)      # 2 階からテラスへの両開き

# 1 階の南: 西 3.5 格子は丸太の壁（風除室）、東 8.5 格子はガラス。柱は 0.85 格子（3.1 m）ごと
GLASS_S_X0 = gx(3.5)
GLASS_S_POSTS = [gx(3.5 + 0.85 * i) for i in range(11)]
# 1 階の西: 全面ガラス（貸出の下屋に開く）。柱は 0.7 格子（2.5 m）ごと、北の端の間は戸
GLASS_W_POSTS = [gy(0.7 * i) for i in range(11)]
GLASS_W_DOOR_BAY = len(GLASS_W_POSTS) - 2   # 南から数えて最後の間（北の端）
TRANSOM = FL1 + 2.30 * TALL       # ガラスの欄間の横桟

# 壁ごとの開口（中心の位置, 種類）。位置は壁に沿った世界座標。窓は 1.5 格子ごと（窓の間は窓幅と同じ）
OPENINGS = {
    "1F_N": [(gx(4.6), "win"), (gx(10.5), "win"), (gx(2.78), "door1")],
    "1F_E": [(gy(3.9), "win"), (gy(5.5), "win")],
    "2F_S": [(gx(1.0), "win"), (gx(2.5), "door2"), (gx(4.5), "win"), (gx(6.0), "win"), (gx(7.5), "win"),
             (gx(9.0), "win"), (gx(10.5), "win")],
    "2F_N": [(gx(1.5), "win"), (gx(3.5), "win"), (gx(5.5), "win"), (gx(7.0), "win"), (gx(10.4), "win")],
    "2F_W": [(gy(1.5), "win"), (gy(3.5), "win")],
    "2F_E": [(gy(3.9), "win")],
}
DOOR1 = dict(w=1.20, h=2.40)      # 厨房の勝手口

# ---- 煙突（北の壁にまたがる石の塔）----
CH = dict(x0=gx(8.3), x1=gx(9.7), y0=Y1 - 1.60, y1=Y1 + 1.50,          # 1 階: 炉（幅 5.1 m の大きな炉）
          ux0=gx(8.55), ux1=gx(9.45), uy0=Y1 - 0.80, uy1=Y1 + 1.40,   # 2 階より上
          top=EAVE_S + ROOF_T + SNOW_T + 1.80,   # 直した点: 南の屋根の上端より 1.8 m 上に出す
          cap_out=0.20, cap_t=0.24, fire_w=1.8, fire_h=1.4)
VENTS = [gx(6.25)]                # 厨房の排気の筒（屋根の上）

# ---- 西の下屋（屋根だけの貸出）----
LEAN = dict(x_out=gx(-2.3), x_post=gx(-2.0), y0=gy(7.05), y1=gy(-0.05),
            z_wall=3.15 * TALL, z_out=2.40 * TALL, posts=[gy(0.875 * i) for i in range(9)])

# ---- デッキ（地面から 0.45）----
DECK = dict(x0=gx(-1.5), x1=gx(6.0), y0=Y0 - 1.5 * K, y1=Y0, z=FL1, t=0.12)

# ---- 外階段（デッキからテラスへ折り返す）----
# 直した点: 代表の図面は踊り場が丘へ大きく出ていた。蹴上げをふつうにして縮め、デッキの先から少しだけ出る。
# 西の端なので、正面に滑り込むソリの道をふさがない。幅は人の大きさ（1 間）
ESTAIR = dict(x_lo=(X0 - K, X0), x_up=(X0, X0 + K), y_start=Y0 - 0.30,
              risers=2 * round((FL2 - FL1) / 0.175 / 2), tread=0.27, landing=1.40, width=K)
ESTAIR["rise"] = (FL2 - FL1) / ESTAIR["risers"]
ESTAIR["run"] = (ESTAIR["risers"] // 2 - 1) * ESTAIR["tread"]       # 1 本の流れ 2.7 m
ESTAIR["z_land"] = FL1 + ESTAIR["risers"] // 2 * ESTAIR["rise"]
ESTAIR["y_land"] = ESTAIR["y_start"] - ESTAIR["run"]                 # 踊り場の北の縁

# ---- 中 ----
COLS = [(gx(n), Y2_0 + 0.2) for n in (2, 4, 6, 8, 10)]   # 2 階の南の壁を受ける丸柱（屋根まで通す）
COL_D = 0.50
_ir = round((FL2 - FL1) / 0.18)    # 内階段: 蹴上げ約 0.18、踏面 0.26、幅 1.6 m の 2 本。東の隅で踊り場を挟んで折り返す
INSTAIR = dict(x1=X1 - LOG_D / 2, y_top=Y1 - LOG_D / 2, risers=_ir, n1=_ir // 2, tread=0.26, width=1.6, landing=1.6)
INSTAIR["xm"] = INSTAIR["x1"] - INSTAIR["width"]          # 1 本目（東）と 2 本目（西）の境
INSTAIR["x0"] = INSTAIR["xm"] - INSTAIR["width"]          # 2 本目の西の縁
INSTAIR["y_land"] = INSTAIR["y_top"] - INSTAIR["landing"]  # 踊り場の南の縁（北の壁際に踊り場）
INSTAIR["y_bottom"] = INSTAIR["y_land"] - (INSTAIR["n1"] - 1) * INSTAIR["tread"]   # 1 本目の上り口（南）
INSTAIR["z_land"] = FL1 + INSTAIR["n1"] * (FL2 - FL1) / _ir
INSTAIR["hole_y0"] = INSTAIR["y_land"] - (_ir - INSTAIR["n1"] - 1) * INSTAIR["tread"]   # 2 本目の上がり口＝穴の南の縁
KITCHEN = dict(x0=gx(1.46), x1=gx(6.0), y_front=gy(1.5))   # 間仕切りの位置
COUNTER = dict(x0=gx(1.6), x1=gx(5.9), y0=gy(1.5) - 0.75, y1=gy(1.5), h=1.05)   # レジ・配膳
BACK = dict(x0=gx(1.6), x1=gx(5.9), y0=Y1 - LOG_D / 2 - 0.70, y1=Y1 - LOG_D / 2, h=0.90)
RENTAL = dict(x0=gx(0.15), x1=gx(1.40), y0=gy(1.5) - 0.75, y1=gy(1.5), h=1.05)
SKI_RACK = dict(x0=X0 + LOG_D / 2 + 0.5, x1=X0 + LOG_D / 2 + 1.2, y0=gy(5.4), y1=gy(1.9), n=40)
TABLE = dict(w=2 * K, d=0.6 * K, h=0.72)
# 卓 18（6 人掛け）。3 列 x 6。2 階の南の壁の丸柱の列は、2 列目と 3 列目の間の通路に入る
TABLES = [(gx(3.8 + 1.3 * i), y) for y in (gy(3.4), gy(4.6), gy(6.0)) for i in range(6)]   # 南西の角
# 窓向きのカウンター: 正面（南）のガラス面いっぱいに一続き。一人用の高い椅子で外の丘を眺める
WINDOW_BAR = dict(x0=GLASS_S_X0 + 0.35, x1=X1 - LOG_D / 2 - 0.05, y0=Y0 + POST / 2 + 0.10,
                  d=0.50, h=1.05, t=0.06)
STOOL = dict(step=0.80, y=WINDOW_BAR["y0"] + 0.50 + 0.38, seat=0.76, r=0.21)
# 炉をコの字に囲む長椅子（奥行き 0.45）
HEARTH_BENCH = [(CH["x0"], CH["y0"] - 2.8, CH["x1"], CH["y0"] - 2.35),
                (CH["x0"] - 1.6, CH["y0"] - 2.8, CH["x0"] - 1.15, CH["y0"] - 0.6),
                (CH["x1"] + 1.15, CH["y0"] - 2.8, CH["x1"] + 1.6, CH["y0"] - 0.6)]
# 2 階
TATAMI = dict(x0=gx(3.25), x1=gx(10.75), y0=gy(4.6), y1=gy(0.6), h=0.40)   # 小上がり
KOTATSU_W, KOTATSU_D = 1.2 * K, 0.7 * K
KOTATSU = [(gx(3.9 + 1.7 * i), y) for y in (gy(3.4), gy(2.0)) for i in range(4)]   # 8 卓。南西の角
PIT_DEPTH = 0.40
BENCH2 = (gx(0.3), Y2_0 + LOG_D / 2 + 0.05, gx(2.0), Y2_0 + LOG_D / 2 + 0.50)
TABLE2 = (gx(0.4), Y2_0 + 2.0, gx(1.6), Y2_0 + 3.1)

# 機械の置き場（代表があとで置く）。床を空け、glb に空の目印を入れる
SLOTS = {
    "slot_food_kitchen": (gx(3.75), gy(0.75), FL1),
    "slot_craft_rental": (gx(0.75), gy(0.75), FL1),
    "slot_vending_1": (gx(6.55), gy(0.30), FL1),
    "slot_vending_2": (gx(7.15), gy(0.30), FL1),
    "slot_vending_3": (gx(3.7), Y0 - 0.45, FL1),
}

# ---- 地面 ----
HILL_Y = Y0 - 22.0                # ここから南へ丘が上る
