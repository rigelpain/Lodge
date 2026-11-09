"""旧・夏虫沢ヒュッテの図面（平面図・屋根伏図・4 面の立面図・入口の妻）を描く。寸法は dims.py。

  python draw_plans.py <書き出す png>
"""
import math, sys, os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Rectangle, Circle
plt.rcParams["font.family"] = "Hiragino Sans"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dims import *

WALL = "#5a4636"; ROOF = "#9aa0a6"; BLUE = "#5b7fb0"; DECK = "#b88a5a"; GLASS = "#bcd3e6"; LOG = "#7a5232"; SOFFIT = "#6e5038"
t = lambda d: math.tan(math.radians(d))
r_rest = ridge(FL + REST_EAVE, 4.5, REST_PITCH)
r_wing = ridge(FL + WING_EAVE, (WING["v"][1] - WING["v"][0]) / 2, WING_PITCH)
r_a = FL + A_EAVE + A_HALF * t(A_PITCH)


def rect(ax, u, y, **k):
    ax.add_patch(Rectangle((u[0], y[0]), u[1] - u[0], y[1] - y[0], **k))


def poly(ax, pts, **k):
    ax.add_patch(Polygon(pts, closed=True, **k))


def label(ax, x, y, s, size=9, **k):
    ax.text(x, y, s, ha="center", va="center", fontsize=size, **k)


fig = plt.figure(figsize=(22, 17), dpi=100)
fig.suptitle("旧・夏虫沢ヒュッテ（平成7年・木造平屋）図面案　― 寸法は横手市の整備計画書の平面図（休憩スペース 14,000 × 9,000）から。高さは写真からの見積もり", fontsize=14, x=0.02, ha="left")

# ---------------- 平面図 ----------------
ax = fig.add_axes([0.03, 0.50, 0.55, 0.44]); ax.set_aspect("equal"); ax.set_title("平面図（上が駐車場の側、下がゲレンデの側）", loc="left", fontsize=12)
ax.set_xlim(-13, 24); ax.set_ylim(12, -12)
for d in (DECK_S, DECK_N):
    rect(ax, d["u"], d["v"], fc=DECK, alpha=0.35, ec=DECK)
for s in (STEPS_S, STEPS_N):
    rect(ax, s["u"], s["v"], fc="#ddd", ec="#888")
    for k in range(6):
        vv = s["v"][0] + (s["v"][1] - s["v"][0]) * k / 5
        ax.plot(s["u"], [vv, vv], color="#888", lw=0.6)
rooms = [(WING, "北西の棟\n便所・救護室・事務室\n湯沸室・倉庫・スノーモービル置場"), (HALL, "ホール\n（上部吹抜）"), (VEST_S, "風除室"), (VEST_N, "風除室"),
         (REST, "休憩スペース\n14,000 × 9,000（126㎡）"), (KITCHEN, "厨房\n（平成13年増築\n39㎡）")]
for r, nm in rooms:
    rect(ax, r["u"], r["v"], fc="white", ec=WALL, lw=2.2)
    label(ax, sum(r["u"]) / 2, sum(r["v"]) / 2, nm, 8.5)
# 屋根の外形（破線）
roofs = [((REST["u"][0], KITCHEN["u"][0] + OV_GABLE), (-4.5 - OV_SIDE, 4.5 + OV_SIDE), ROOF), ((-A_HALF - OV_SIDE, A_HALF + OV_SIDE), A_V, "#555"),
         ((WING["u"][0] - OV_GABLE, WING["u"][1]), (WING["v"][0] - OV_SIDE, WING["v"][1] + OV_SIDE), BLUE)]
for u, v, c in roofs:
    rect(ax, u, v, fill=False, ec=c, ls="--", lw=1.2)
# 入口の丸太の柱
for vv in (GABLE_FACE_V + 0.6, -GABLE_FACE_V - 0.6):
    ax.add_patch(Circle((0, vv), GABLE_POST_R * 2, fc=LOG, ec="k"))
ax.annotate("", xy=(REST["u"][0], 11), xytext=(REST["u"][1], 11), arrowprops=dict(arrowstyle="<->"))
label(ax, sum(REST["u"]) / 2, 11.6, "14,750（壁の外）")
ax.annotate("", xy=(WING["u"][0], -11), xytext=(KITCHEN["u"][1], -11), arrowprops=dict(arrowstyle="<->"))
label(ax, (WING["u"][0] + KITCHEN["u"][1]) / 2, -11.6, "全長 約 32,000（屋根の出を入れて約 34,000。航空写真と合う）")
label(ax, -12.3, 0, "← リフト・北西", 9, rotation=90)
label(ax, 23.3, 0, "南東 →", 9, rotation=90)
ax.text(-12.8, 11.7, "破線 = 屋根の外形（灰 = 休憩室の切妻、黒 = ホールの A 字の屋根、青 = 北西の棟）", fontsize=8.5)
ax.set_xticks([]); ax.set_yticks([])

# ---------------- 入口の妻 ----------------
ax = fig.add_axes([0.62, 0.50, 0.36, 0.44]); ax.set_aspect("equal"); ax.set_title("入口の妻（ゲレンデの側も駐車場の側も同じ）", loc="left", fontsize=12)
ax.set_xlim(-7.5, 7.5); ax.set_ylim(-0.5, r_a + 1)
eh = FL + A_EAVE - 1.5 * 0  # 軒
base = A_HALF + OV_SIDE
ey = FL + A_EAVE - OV_SIDE * t(A_PITCH)
poly(ax, [(-base, ey), (0, r_a + 0.25), (base, ey), (base - 0.5, ey), (0, r_a - 0.4), (-base + 0.5, ey)], fc=ROOF, ec="k")
poly(ax, [(-A_HALF + 0.4, FL + A_EAVE + 0.3), (0, r_a - 0.6), (A_HALF - 0.4, FL + A_EAVE + 0.3)], fc=SOFFIT, ec="k", lw=0.8)  # 妻の板（奥）
rect(ax, (-2.25, 2.25), (FL, FL + GABLE_BEAM_Y), fc=WALL, ec="k")     # 風除室の前の壁
rect(ax, (0.3, 2.1), (FL + 0.05, FL + 2.6), fc=GLASS, ec="k")          # ガラスの戸
for k in range(1, 4):
    ax.plot([0.3 + 0.45 * k] * 2, [FL + 0.05, FL + 2.6], color="k", lw=0.8)
rect(ax, (-1.9, -0.6), (FL + 0.05, FL + 2.3), fc="#eee", ec="k")        # 白い戸
rect(ax, (-A_HALF + 0.2, A_HALF - 0.2), (FL + GABLE_BEAM_Y - 0.15, FL + GABLE_BEAM_Y + 0.15), fc=LOG, ec="k")   # 横の丸太の梁
rect(ax, (0.4, 2.6), (FL + GABLE_BEAM_Y + 0.15, FL + GABLE_BEAM_Y + 0.55), fc="#e9dcc0", ec="k")                # 看板
label(ax, 1.5, FL + GABLE_BEAM_Y + 0.35, "夏虫沢ヒュッテ", 8)
label(ax, 0, FL + 5.2, "天下森スキー場（板の文字）", 8, color="white")
rect(ax, (-GABLE_POST_R, GABLE_POST_R), (0.0, r_a - 0.5), fc=LOG, ec="k")  # 丸太の柱 1 本
rect(ax, (-6.5, 6.5), (0, FL), fc=DECK, ec="k", alpha=0.6)
rect(ax, (-1.5, 1.5), (0, FL), fc="#ddd", ec="k")
for k in range(1, 5):
    ax.plot([-1.5, 1.5], [FL * k / 5] * 2, color="k", lw=0.6)
ax.annotate("まんなかの丸太の柱 1 本（デッキから頂まで）", xy=(0.1, 7.5), xytext=(2.2, 9.5), fontsize=9, arrowprops=dict(arrowstyle="->"))
ax.annotate("横の丸太の梁 1 本（床から 3.2 m）", xy=(-4, FL + GABLE_BEAM_Y), xytext=(-7.2, FL + 5.0), fontsize=9, arrowprops=dict(arrowstyle="->"))
ax.annotate("A 字の屋根（46°）。軒は隣の屋根の軒と同じ高さ", xy=(-4.6, ey + 0.6), xytext=(-7.3, 1.0), fontsize=9, arrowprops=dict(arrowstyle="->"))
ax.set_xticks([]); ax.set_yticks(range(0, int(r_a) + 2, 2)); ax.set_ylabel("高さ (m)")

# ---------------- 立面図 4 面 ----------------
def elev_long(ax, from_slope):
    s = 1 if from_slope else -1
    ax.set_aspect("equal"); ax.set_xlim(-14, 24) if from_slope else ax.set_xlim(24, -14); ax.set_ylim(-0.5, r_a + 1)
    # 遠い順: 休憩室の屋根・北西の棟の屋根 → 壁 → A 字 → デッキ
    pr = REST_PITCH
    eyr = FL + REST_EAVE - OV_SIDE * t(pr)
    poly(ax, [(REST["u"][0], eyr), (KITCHEN["u"][0] + OV_GABLE, eyr), (KITCHEN["u"][0] + OV_GABLE, r_rest), (REST["u"][0], r_rest)], fc=ROOF, ec="k")
    rect(ax, REST["u"], (FL, FL + REST_EAVE - 0.3), fc=WALL, ec="k")
    for k in range(5):   # 大きな窓（ゲレンデの側）・小さな窓（駐車場の側）
        u0 = REST["u"][0] + 1.0 + k * 2.75
        rect(ax, (u0, u0 + 2.2), (FL + (0.7 if from_slope else 1.2), FL + 2.6), fc=GLASS, ec="k")
    ew = FL + WING_EAVE - OV_SIDE * t(WING_PITCH)
    poly(ax, [(WING["u"][0] - OV_GABLE, ew), (WING["u"][1], ew), (WING["u"][1], r_wing), (WING["u"][0] - OV_GABLE, r_wing)], fc=BLUE, ec="k")
    rect(ax, WING["u"], (FL, FL + WING_EAVE - 0.3), fc=WALL, ec="k")
    rect(ax, (WING["u"][0] + 2, WING["u"][0] + 3.6), (FL + 1.0, FL + 2.0), fc=GLASS, ec="k")
    rect(ax, KITCHEN["u"], (FL, FL + KITCHEN_EAVE), fc=WALL, ec="k")
    poly(ax, [(KITCHEN["u"][0], FL + KITCHEN_EAVE + 0.9), (KITCHEN["u"][1] + 0.6, FL + KITCHEN_EAVE - 0.1), (KITCHEN["u"][1] + 0.6, FL + KITCHEN_EAVE + 0.15), (KITCHEN["u"][0], FL + KITCHEN_EAVE + 1.15)], fc=ROOF, ec="k")
    # A 字（妻が手前を向く）
    base = A_HALF + OV_SIDE
    ey = FL + A_EAVE - OV_SIDE * t(A_PITCH)
    poly(ax, [(-base, ey), (0, r_a + 0.25), (base, ey)], fc=ROOF, ec="k")
    poly(ax, [(-A_HALF + 0.5, ey + 0.6), (0, r_a - 0.6), (A_HALF - 0.5, ey + 0.6)], fc=SOFFIT, ec="k", lw=0.6)
    rect(ax, (-2.25, 2.25), (FL, FL + GABLE_BEAM_Y), fc=WALL, ec="k")
    rect(ax, (0.3, 2.1) if from_slope else (-2.1, -0.3), (FL + 0.05, FL + 2.6), fc=GLASS, ec="k")
    rect(ax, (-A_HALF + 0.2, A_HALF - 0.2), (FL + GABLE_BEAM_Y - 0.15, FL + GABLE_BEAM_Y + 0.15), fc=LOG, ec="k")
    rect(ax, (-GABLE_POST_R, GABLE_POST_R), (0, r_a - 0.5), fc=LOG, ec="k")
    # デッキと段
    d = DECK_S if from_slope else DECK_N
    rect(ax, d["u"], (FL - 0.12, FL), fc=DECK, ec="k")
    uu = d["u"][0] + 0.3
    while uu < d["u"][1]:
        rect(ax, (uu - 0.06, uu + 0.06), (0, FL), fc=DECK, ec="k", lw=0.5)
        uu += 2.75
    rect(ax, (-1.5, 1.5), (0, FL), fc="#ddd", ec="k")
    ax.axhline(0, color="k", lw=1)
    ax.set_yticks(range(0, int(r_a) + 2, 2)); ax.set_xticks([])


ax = fig.add_axes([0.03, 0.27, 0.55, 0.2]); ax.set_title("ゲレンデの側の立面（左が北西＝リフトの側）", loc="left", fontsize=12); elev_long(ax, True)
ax = fig.add_axes([0.03, 0.03, 0.55, 0.2]); ax.set_title("駐車場の側の立面（左が南東）", loc="left", fontsize=12); elev_long(ax, False)


def elev_end(ax, se):
    ax.set_aspect("equal"); ax.set_xlim(11, -11) if se else ax.set_xlim(-11, 11); ax.set_ylim(-0.5, r_a + 1)
    # 奥: A 字の屋根の面（横から見ると台形）
    ey = FL + A_EAVE - OV_SIDE * t(A_PITCH)
    rect(ax, A_V, (ey, r_a), fc=ROOF, ec="k")
    if se:
        half = 4.5 + OV_SIDE
        eyr = FL + REST_EAVE - OV_SIDE * t(REST_PITCH)
        poly(ax, [(-half, eyr), (0, r_rest + 0.2), (half, eyr)], fc=ROOF, ec="k")
        poly(ax, [(-4.5, FL + REST_EAVE), (0, r_rest - 0.3), (4.5, FL + REST_EAVE)], fc=WALL, ec="k")
        for k in range(12):
            yy = FL + REST_EAVE + k * 0.3
            ax.plot([-4.5 + (yy - FL - REST_EAVE) / t(REST_PITCH), 4.5 - (yy - FL - REST_EAVE) / t(REST_PITCH)], [yy, yy], color="#3d2f24", lw=0.4)
        rect(ax, (-4.5, 4.5), (FL, FL + REST_EAVE), fc=WALL, ec="k")
        rect(ax, (-4.5, 4.5), (FL, FL + KITCHEN_EAVE + 0.15), fc="#6b5443", ec="k")   # 厨房の差し掛け（手前）
        rect(ax, (-4.8, 4.8), (FL + KITCHEN_EAVE, FL + KITCHEN_EAVE + 0.2), fc=ROOF, ec="k")
        rect(ax, (1.5, 3.5), (FL + 1.0, FL + 2.0), fc=GLASS, ec="k")
        rect(ax, (-4.3, -2.6), (FL, FL + 2.1), fc="#4a3a2d", ec="k")
        rect(ax, (-6.4, -4.5), (0, FL), fc=DECK, ec="k")
    else:
        half = (WING["v"][1] - WING["v"][0]) / 2 + OV_SIDE
        vc = sum(WING["v"]) / 2
        ew = FL + WING_EAVE - OV_SIDE * t(WING_PITCH)
        poly(ax, [(vc - half, ew), (vc, r_wing + 0.2), (vc + half, ew)], fc=BLUE, ec="k")
        poly(ax, [(WING["v"][0], FL + WING_EAVE), (vc, r_wing - 0.3), (WING["v"][1], FL + WING_EAVE)], fc=WALL, ec="k")
        rect(ax, WING["v"], (FL, FL + WING_EAVE), fc=WALL, ec="k")
        rect(ax, (-2, 0), (FL + 1.0, FL + 2.0), fc=GLASS, ec="k")
        rect(ax, (1.5, 3.2), (FL, FL + 2.1), fc="#4a3a2d", ec="k")
        poly(ax, [(0.8, FL + 2.6), (4.5 + 1.6, FL + 2.0), (4.5 + 1.6, FL + 2.2), (0.8, FL + 2.8)], fc=ROOF, ec="k")   # 横の小さな差し掛け（入口と段）
        rect(ax, (4.5, 6.4), (0, FL), fc=DECK, ec="k")
    ax.axhline(0, color="k", lw=1); ax.set_xticks([]); ax.set_yticks(range(0, int(r_a) + 2, 2))


ax = fig.add_axes([0.62, 0.27, 0.36, 0.2]); ax.set_title("南東の妻（休憩室と厨房の差し掛け。左がゲレンデの側）", loc="left", fontsize=12); elev_end(ax, True)
ax = fig.add_axes([0.62, 0.03, 0.36, 0.2]); ax.set_title("北西の妻（青い屋根の棟。右がゲレンデの側）", loc="left", fontsize=12); elev_end(ax, False)
fig.text(0.62, 0.005, "高さ: 床 %.2f m・休憩室の棟 %.1f m・A 字の頂 %.1f m・北西の棟の棟 %.1f m（地面から。見積もり）" % (FL, r_rest, r_a, r_wing), fontsize=10)
fig.savefig(sys.argv[1], dpi=100)
print("saved", sys.argv[1])
