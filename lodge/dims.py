"""ロッジの寸法。Blender の台本（massing は build_lodge.py の段階 1）が同じ数を使う。

元は代表の図面（drawings/daihyo.svg、1 間 = 54px）。そこから読み取った数に、
直した 3 点（煙突を高く、南の軒を深く、外階段を短く）を入れてある。

単位は m。1 間 K = 1.818 m（6 尺）。
座標: x = 東、y = 北、z = 上。丘（ゲレンデ）は南（-y）にあり、正面は南。
原点は 1 階の外形の中心の真下、雪の地面の高さ。
"""

K = 1.818            # 1 間

# ---- 1 階（食堂）12 間 x 7 間 ----
X0, X1 = -6 * K, 6 * K            # -10.908 .. 10.908
Y0, Y1 = -3.5 * K, 3.5 * K        # -6.363 .. 6.363（Y0 が南＝丘の側）


def gx(n):
    """西の壁から n 間（代表の平面の ③ 通りが 0）"""
    return X0 + n * K


def gy(n):
    """北の壁から n 間（代表の平面の わ 通りが 0）"""
    return Y1 - n * K


PLINTH = 0.45                     # 石の基壇＝1 階の床
FL1 = PLINTH
CEIL1 = 3.95                      # 1 階のガラスの上端＝天井
FL2 = 4.25                        # 2 階の床＝テラスの床
FLOOR2_T = FL2 - CEIL1            # 2 階の床の厚み（縁の帯になる）

# 丸太（巻いたフェルトのロールに見立てる）。壁の厚み＝丸太の径
LOG_D = 0.26
LOG_H = 0.25                      # 1 段の高さ（丸太が少し重なる）
LOG_OUT = 0.30                    # 角で交差して突き出す長さ
POST = 0.26                       # ガラスの壁の柱

# ---- 2 階（休憩の座敷）12 間 x 5 間。南を 2 間さげ、さげた分がテラス ----
X2_0, X2_1 = X0, X1
Y2_0, Y2_1 = gy(5), Y1            # -2.727 .. 6.363
H2_S, H2_N = 4.30, 2.45           # 2 階の壁の高さ。南（丘の側）が高い片流れ
EAVE_S = FL2 + H2_S               # 8.55
EAVE_N = FL2 + H2_N               # 6.70
ROOF_PITCH = (EAVE_S - EAVE_N) / (Y2_1 - Y2_0)   # 約 2 寸。雪は北の裏へ落ちる
EAVE_OUT_S = 1.20                 # 南の軒（直した点。代表の図面は 0.6）。垂木の先を見せて 2 階の壁に影の帯
EAVE_OUT_N = 0.60
VERGE_OUT = 1.00                  # 東西のけらば
ROOF_T = 0.30                     # 屋根（藍のフェルトの板）
SNOW_T = 0.25                     # 屋根の雪（毛糸の編み地）
RAFTER = dict(w=0.12, h=0.22, step=K / 2)


def roof_z(y):
    """屋根の下端（壁の上端の線）の高さ。y の位置で"""
    return EAVE_N + (Y2_1 - y) * ROOF_PITCH


# ---- テラス（1 階の屋上の南 2 間）----
RAIL_H = 1.10
BALUSTER = 0.15

# ---- 風除室（玄関）----
VEST = dict(x0=gx(1.75), x1=gx(3.25), d=2.0, h=2.45, roof_out=0.35)
DOOR_OUT = dict(w=1.45, h=2.10)   # 風除室の外の両開き
DOOR_IN = dict(x0=gx(2.0), x1=gx(3.0), h=2.10)   # 1 階の壁の内の戸

# ---- 窓のモジュール: 1 間 x 1.3、窓台は床から 0.9。十字の桟で 4 枚 ----
WIN = dict(w=K, h=1.30, sill=0.90, frame=0.08)
DOOR2 = dict(w=1.45, h=2.10)      # 2 階からテラスへの戸

# 1 階の南: 西 3.5 間は丸太の壁（風除室）、東 8.5 間はガラス。柱は 1.7 間ごと
GLASS_S_X0 = gx(3.5)
GLASS_S_POSTS = [gx(3.5 + 1.7 * i) for i in range(6)]
# 1 階の西: 全面ガラス（貸出の下屋に開く）。柱は 1.4 間ごと、北の端の間は戸
GLASS_W_POSTS = [gy(1.4 * i) for i in range(6)]
TRANSOM = FL1 + 2.30              # ガラスの欄間の横桟

# 壁ごとの開口（中心の位置, 種類）。位置は壁に沿った世界座標
OPENINGS = {
    "1F_N": [(gx(4.8), "win"), (gx(10.5), "win"), (gx(2.78), "door1")],
    "1F_E": [(gy(3.9), "win"), (gy(5.5), "win")],
    "2F_S": [(gx(1.0), "win"), (gx(2.5), "door2"), (gx(4.5), "win"), (gx(6.5), "win"),
             (gx(8.5), "win"), (gx(10.5), "win")],
    "2F_N": [(gx(4.8), "win"), (gx(7.0), "win"), (gx(11.0), "win")],
    "2F_W": [(gy(3.0), "win")],
    "2F_E": [(gy(3.9), "win")],
}
DOOR1 = dict(w=1.00, h=2.10)      # 厨房の勝手口

# ---- 煙突（北の壁にまたがる石の塔）----
CH = dict(x0=gx(8.3), x1=gx(9.7), y0=Y1 - 1.08, y1=Y1 + 1.0,          # 1 階: 炉
          ux0=gx(8.55), ux1=gx(9.45), uy0=Y1 - 0.50, uy1=Y1 + 0.95,   # 2 階より上
          top=EAVE_S + ROOF_T + SNOW_T + 1.20,   # 直した点: 南の屋根の上端より 1.2 m 上に出す（10.3）
          cap_out=0.14, cap_t=0.16)
VENTS = [gx(6.25)]                # 厨房の排気の筒（屋根の上）

# ---- 西の下屋（屋根だけの貸出）----
LEAN = dict(x_out=gx(-2.3), x_post=gx(-2.0), y0=gy(7.1), y1=gy(-0.1),
            z_wall=3.15, z_out=2.40, posts=[gy(1.75 * i) for i in range(5)])

# ---- デッキ（地面から 0.45）----
DECK = dict(x0=gx(-1.5), x1=gx(6.0), y0=Y0 - 1.5 * K, y1=Y0, z=FL1, t=0.12)

# ---- 外階段（デッキからテラスへ折り返す）----
# 直した点: 代表の図面は踊り場が 1 階の壁から 8.9 m 丘へ出ていた。蹴上げをふつうにして 4.2 m に縮め、
# デッキの先から 1.5 m だけ出る。西の端なので、正面に滑り込むソリの道をふさがない。
ESTAIR = dict(x_lo=(gx(-1), gx(0)), x_up=(gx(0), gx(1)), y_start=Y0 - 0.30,
              risers=22, tread=0.27, landing=1.20, width=K)
ESTAIR["rise"] = (FL2 - FL1) / ESTAIR["risers"]
ESTAIR["run"] = (ESTAIR["risers"] // 2 - 1) * ESTAIR["tread"]       # 1 本の流れ 2.7 m
ESTAIR["z_land"] = FL1 + ESTAIR["risers"] // 2 * ESTAIR["rise"]
ESTAIR["y_land"] = ESTAIR["y_start"] - ESTAIR["run"]                 # 踊り場の北の縁

# ---- 中 ----
COLS = [(gx(6.3), Y2_0 + 0.13), (gx(8.9), Y2_0 + 0.13)]   # 2 階の南の壁を受ける丸柱（屋根まで通す）
COL_D = 0.36
INSTAIR = dict(x0=gx(11.1), x1=X1 - LOG_D / 2, y_bottom=gy(2.8), y_top=Y1 - LOG_D / 2, risers=22)
KITCHEN = dict(x0=gx(1.46), x1=gx(6.0), y_front=gy(1.5))   # 間仕切りの位置
COUNTER = dict(x0=gx(1.6), x1=gx(5.9), y0=gy(1.65), y1=gy(1.35), h=1.05)   # レジ・配膳
BACK = dict(x0=gx(1.6), x1=gx(5.9), y0=gy(0.40), y1=Y1 - LOG_D / 2, h=0.90)
RENTAL = dict(x0=gx(0.15), x1=gx(1.40), y0=gy(1.65), y1=gy(1.35), h=1.05)
SKI_RACK = dict(x0=gx(0.35), x1=gx(1.05), y0=gy(5.4), y1=gy(1.7), n=18)
TABLES = [(x, y) for y in (gy(3.9), gy(6.1)) for x in (gx(4.0), gx(6.6), gx(9.2))]   # 南西の角
TABLE = dict(w=2 * K, d=0.6 * K, h=0.72)
HEARTH_BENCH = [(gx(8.3), gy(2.2), gx(9.7), gy(1.9)), (gx(10.3), gy(1.6), gx(10.6), gy(0.4)),
                (gx(7.5), gy(2.3), gx(7.8), gy(1.6))]
# 2 階
TATAMI = dict(x0=gx(3.25), x1=gx(10.75), y0=gy(4.6), y1=gy(0.6), h=0.40)   # 小上がり
KOTATSU = [gx(3.9), gx(6.4), gx(8.9)]    # 西の端
KOTATSU_Y = (gy(2.95), gy(2.25))
KOTATSU_W = 1.2 * K
PIT_DEPTH = 0.40
BENCH2 = (gx(0.3), gy(4.85), gx(2.0), gy(4.55))
TABLE2 = (gx(0.3), gy(3.8), gx(2.2), gy(3.1))

# 機械の置き場（代表があとで置く）。床を空け、glb に空の目印を入れる
SLOTS = {
    "slot_food_kitchen": (gx(3.75), gy(0.75), FL1),
    "slot_craft_rental": (gx(0.75), gy(0.75), FL1),
    "slot_vending_1": (gx(6.55), gy(0.30), FL1),
    "slot_vending_2": (gx(7.15), gy(0.30), FL1),
    "slot_vending_3": (gx(3.7), Y0 - 0.45, FL1),
}

# ---- 地面 ----
HILL_Y = Y0 - 14.0                # ここから南へ丘が上る
