"""ロッジ 1 階の並びの平面図（真上から。北が上）を SVG で描く。

  python3 design/lodge-layout/plan.py

今（PR #68 の厨房の並び）と、暖炉を北の壁の真ん中にした案の 2 枚を書く。
寸法は lodge/dims.py、厨房の装置は props/build_scenes.py の kitchen（2 倍する前の数）と game/main.gd の冷蔵庫・売り子の位置から。
座標は lodge/ と同じ（x = 東、y = 北、m）。
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "lodge"))
from dims import *  # noqa: E402,F403

S = 19.0                      # 1 m の px
VX0, VX1 = -31.0, 24.5        # 描く範囲
VY0, VY1 = -19.5, 17.0
W = (VX1 - VX0) * S
H = (VY1 - VY0) * S

C = dict(bg="#f3eee4", floor="#ece4d2", wall="#262b45", glass="#9fbbd9", wood="#d9b07a", wood_d="#b58a55",
         chair="#cf8a68", stone="#c9c3b8", fire="#3a3030", ink="#3b342c", faint="#c8bfae",
         sled="#5b7fb8", sled_bg="#dbe5f2", food="#d0743c", food_bg="#f6e1d0", path="#7a6f60", ask="#c8323c")


def px(x):
    return (x - VX0) * S


def py(y):
    return (VY1 - y) * S


class Svg:
    def __init__(self):
        self.o = []

    def rect(self, x0, y0, x1, y1, fill="none", stroke="none", sw=1.0, extra=""):
        xa, xb = sorted((x0, x1))
        ya, yb = sorted((y0, y1))
        self.o.append(f'<rect x="{px(xa):.1f}" y="{py(yb):.1f}" width="{(xb - xa) * S:.1f}" height="{(yb - ya) * S:.1f}" '
                      f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')

    def box(self, cx, cy, w, d, **k):
        self.rect(cx - w / 2, cy - d / 2, cx + w / 2, cy + d / 2, **k)

    def line(self, x0, y0, x1, y1, stroke, sw=1.0, extra=""):
        self.o.append(f'<line x1="{px(x0):.1f}" y1="{py(y0):.1f}" x2="{px(x1):.1f}" y2="{py(y1):.1f}" '
                      f'stroke="{stroke}" stroke-width="{sw}" {extra}/>')

    def poly(self, pts, stroke, sw=1.0, fill="none", extra=""):
        p = " ".join(f"{px(x):.1f},{py(y):.1f}" for x, y in pts)
        self.o.append(f'<polyline points="{p}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')

    def circle(self, x, y, r, fill, stroke="none", sw=1.0):
        self.o.append(f'<circle cx="{px(x):.1f}" cy="{py(y):.1f}" r="{r * S:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')

    def text(self, x, y, s, size=12, fill=None, anchor="middle", weight="normal", raw=False):
        X, Y = (x, y) if raw else (px(x), py(y))
        self.o.append(f'<text x="{X:.1f}" y="{Y:.1f}" font-size="{size}" fill="{fill or C["ink"]}" text-anchor="{anchor}" '
                      f'font-weight="{weight}" dominant-baseline="middle">{s}</text>')

    def ask(self, x, y, n):
        self.circle(x, y, 0.62, C["ask"])
        self.text(x, y, str(n), 13, "#fff", weight="bold")


# ---- 並びの中身 ------------------------------------------------------------------------

SLOT_K = (gx(3.75), gy(0.75))        # slot_food_kitchen
SLOT_M = (gx(0.75), gy(0.75))        # slot_craft_rental


def now_layout():
    kx, ky = SLOT_K

    def k(x, y):                     # 厨房の場面の座標（2 倍する前）→ ロッジ
        return kx + 2 * x, ky + 2 * y
    return dict(
        title="今（PR #68 の並び）",
        ch_cx=(CH["x0"] + CH["x1"]) / 2,
        machine=(SLOT_M[0], SLOT_M[1]),
        seller=(SLOT_M[0] + 2.0, SLOT_M[1] - 1.0),
        fridge=(kx - 7.15, ky + 1.07),
        board=k(-0.4, 0.3), press=k(1.5, 0.4), dryer=k(3.125, 0.25),
        sacks=[k(-2.45, -0.3), k(-2.25, -0.5), k(-2.35, 0.6), k(-1.95, 0.65)],
        back=(BACK["x0"], BACK["x1"]),
        menu=((COUNTER["x0"] + COUNTER["x1"]) / 2, BACK["y0"] - 4.0),
        partition=[KITCHEN["x1"]],
        vend_in=[(gx(6.55), gy(0.30) - 0.1, 0), (gx(7.15), gy(0.30) - 0.1, 0)],
        door1=gx(2.78),
        vent=gx(6.25),
        zones=[],
    )


def new_layout():
    # 暖炉を北の壁の真ん中（x = 0）へ。左（西）がソリ・装備、右（東）が食べ物
    cx = 0.0
    hw = (CH["x1"] - CH["x0"]) / 2
    bench_x1 = cx + hw + 1.6           # 長椅子の外の縁
    ky = SLOT_K[1]
    # 東の並び（暖炉の長椅子の外から、内階段の手前まで）: 冷蔵庫 → アイロン台 → 勝手口 → プレス機 → 乾燥機
    fr = bench_x1 + 0.6 + 1.0
    bd = fr + 1.0 + 0.6 + 1.9
    dr0 = bd + 1.9 + 0.15             # 勝手口（幅 1.2）の西の縁
    pr = dr0 + 1.2 + 0.15 + 0.8
    dy = pr + 0.8 + 0.6 + 1.35
    return dict(
        title="案（暖炉を真ん中に。左はソリ・装備、右は食べ物）",
        ch_cx=cx,
        machine=(-10.6, SLOT_M[1]),
        seller=(-10.6 + 2.0, SLOT_M[1] - 1.0),
        fridge=(fr, ky + 1.07),
        board=(bd, ky + 0.6), press=(pr, ky + 0.8), dryer=(dy, ky + 0.5),
        sacks=[(bd - 1.5, ky - 1.9), (bd - 0.8, ky - 2.1), (bd - 1.3, ky - 2.6), (bd - 0.6, ky - 2.8)],
        back=(bench_x1 + 0.5, INSTAIR["x0"] - 0.2),
        menu=(fr + 5.0, BACK["y0"] - 4.0),
        partition=[],
        vend_in=[(X1 - LOG_D / 2 - 0.9, 1.3, 90), (X1 - LOG_D / 2 - 0.9, 3.5, 90)],
        door1=dr0 + 0.6,
        vent=dr0 + 0.6,
        zones=[("sled", X0 + LOG_D / 2, -cx - hw - 1.6 - 0.3, "ソリ・装備"),
               ("food", bench_x1 + 0.3, X1 - LOG_D / 2, "食べ物")],
        asks=True,
    )


# ---- 描く ------------------------------------------------------------------------------

def draw(L, path):
    g = Svg()
    hw = (CH["x1"] - CH["x0"]) / 2
    cx = L["ch_cx"]
    # 間の格子（代表の図面の通り）
    for n in range(13):
        g.line(gx(n), Y0 - 6.5, gx(n), Y1 + 2.0, C["faint"], 0.5, 'stroke-dasharray="2 4"')
    for n in range(8):
        g.line(X0 - 9.0, gy(n), X1 + 2.0, gy(n), C["faint"], 0.5, 'stroke-dasharray="2 4"')
    # 外: 西の下屋（屋根だけの貸出）、デッキ、玄関前の広場
    g.rect(LEAN["x_out"], LEAN["y0"], X0, LEAN["y1"], stroke=C["path"], sw=1, extra='stroke-dasharray="5 4"')
    for i in range(14):
        y = LEAN["y0"] + 1.2 + i * 1.6
        g.rect(LEAN["x_out"] + 0.6, y, LEAN["x_out"] + 1.1, y + 1.1, fill=[C["sled"], C["food"], "#e2b84a", "#6c9a6a"][i % 4])
    g.text((LEAN["x_out"] + X0) / 2 + 0.6, 0, "貸出", 12)
    g.text((LEAN["x_out"] + X0) / 2 + 0.6, -1.0, "（屋根のみ）", 10)
    g.rect(DECK["x0"], DECK["y0"], DECK["x1"], DECK["y1"], fill="#e6d9bf", stroke=C["faint"])
    g.text((VEST["x1"] + DECK["x1"]) / 2, (DECK["y0"] + DECK["y1"]) / 2, "デッキ", 11)
    g.rect(PLAZA["x0"], PLAZA["y0"], PLAZA["x1"], PLAZA["y1"], fill="#e6d9bf", stroke=C["faint"])
    # 床と区分けの色
    g.rect(X0, Y0, X1, Y1, fill=C["floor"])
    for kind, a, b, label in L["zones"]:
        g.rect(a, gy(2.45), b, Y1 - LOG_D / 2, fill=C[kind + "_bg"], extra='opacity="0.9"')
        g.text((a + b) / 2, Y1 + 2.2, label, 17, C[kind], weight="bold")
    # 壁: 丸太（北・東・南の西）と、ガラス（南の東・西）
    wall = C["wall"]
    g.line(X0, Y1, X1, Y1, wall, 6)
    g.line(X1, Y1, X1, Y0, wall, 6)
    g.line(X0, Y0, GLASS_S_X0, Y0, wall, 6)
    g.line(GLASS_S_X0, Y0, X1, Y0, C["glass"], 5)
    g.line(X0, Y0, X0, Y1, C["glass"], 5)
    for u in GLASS_S_POSTS:
        g.box(u, Y0, POST, POST, fill=wall)
    for u in GLASS_W_POSTS:
        g.box(X0, u, POST, POST, fill=wall)
    # 窓（北・東）
    for c, kind in OPENINGS["1F_N"]:
        if kind == "win":
            g.line(c - WIN["w"] / 2, Y1, c + WIN["w"] / 2, Y1, C["glass"], 4)
    for c, kind in OPENINGS["1F_E"]:
        g.line(X1, c - WIN["w"] / 2, X1, c + WIN["w"] / 2, C["glass"], 4)
    # 戸: 勝手口（北）と西の戸（貸出へ）
    d1 = L["door1"]
    g.line(d1 - DOOR1["w"] / 2, Y1, d1 + DOOR1["w"] / 2, Y1, C["bg"], 6)
    g.poly([(d1 - DOOR1["w"] / 2, Y1), (d1 - DOOR1["w"] / 2, Y1 - DOOR1["w"])], C["ink"], 1)
    g.text(d1, Y1 + 0.8, "勝手口", 9)
    wy0, wy1 = sorted(GLASS_W_POSTS)[GLASS_W_DOOR_BAY], sorted(GLASS_W_POSTS)[GLASS_W_DOOR_BAY + 1]
    g.line(X0, wy0 + 0.2, X0, wy1 - 0.2, C["bg"], 5)
    g.text(X0 - 1.3, (wy0 + wy1) / 2, "戸", 10)
    # 風除室（入口）
    V = VEST
    g.rect(V["x0"], Y0 - V["d"], V["x1"], Y0, fill=C["floor"])
    g.poly([(V["cx"] - ARCH["r"], Y0 - V["d"]), (V["x0"], Y0 - V["d"]), (V["x0"], Y0)], wall, 6)
    g.poly([(V["cx"] + ARCH["r"], Y0 - V["d"]), (V["x1"], Y0 - V["d"]), (V["x1"], Y0)], wall, 6)
    g.line(DOOR_IN["x0"], Y0, DOOR_IN["x1"], Y0, C["glass"], 3)
    g.line(DOOR_IN["x0"], Y0, DOOR_IN["x1"], Y0, C["bg"], 6, 'stroke-dasharray="6 3" opacity="0.6"')
    for kk in range(2):
        x0 = V["x0"] + V["t"] + 0.10 + kk * (VENDING["w"] + VENDING["gap"])
        g.rect(x0, Y0 - 0.05 - VENDING["d"], x0 + VENDING["w"], Y0 - 0.05, fill=[C["food"], C["sled"]][kk])
    g.text(V["x0"] + 1.6, Y0 - 1.6, "自販機", 9)
    g.text(V["cx"] + 0.6, Y0 - 3.0, "風除室", 12)
    g.text(V["cx"], Y0 - V["d"] - 1.0, "入口 ▲", 14, weight="bold")
    # 内階段（北東の隅）
    I = INSTAIR
    g.rect(I["x0"], I["y_bottom"], I["x1"], I["y_top"], fill="#e9dcc2", stroke=C["wood_d"])
    for i in range(I["n1"]):
        y = I["y_bottom"] + i * I["tread"]
        g.line(I["xm"], y, I["x1"], y, C["wood_d"], 0.6)
    g.line(I["xm"], I["y_bottom"], I["xm"], I["y_land"], C["wood_d"], 1)
    g.poly([((I["xm"] + I["x1"]) / 2, I["y_bottom"] + 0.3), ((I["xm"] + I["x1"]) / 2, I["y_land"] - 0.2)], C["ink"], 1.2,
           extra='marker-end="url(#ar)"')
    g.text((I["x0"] + I["x1"]) / 2, I["y_bottom"] - 0.8, "内階段（2 階）", 10)
    # 丸柱
    for x, y in COLS:
        g.circle(x, y, COL_D / 2, C["fire"])
    # 窓向きのカウンターと丸椅子
    WB = WINDOW_BAR
    g.rect(WB["x0"], WB["y0"], WB["x1"], WB["y0"] + WB["d"], fill=C["wood"])
    n = int((WB["x1"] - WB["x0"]) / STOOL["step"])
    for i in range(n):
        g.circle(WB["x0"] + 0.4 + i * STOOL["step"], STOOL["y"], STOOL["r"], C["chair"])
    g.text((WB["x0"] + WB["x1"]) / 2, WB["y0"] + 2.0, "窓向きのカウンター（丘を眺める）", 10)
    # 卓と椅子
    for x, y in TABLES:
        g.box(x, y, TABLE["w"], TABLE["d"], fill=C["wood"])
        for s in (-1, 1):
            for j in (-1, 0, 1):
                g.box(x + j * 1.15, y + s * (TABLE["d"] / 2 + 0.35), 0.5, 0.45, fill=C["chair"])
    g.text(gx(7.05), gy(4.6) - 0.05, "食卓（みんなの席）", 13, weight="bold")
    # スキー置場（西のガラス際）と貸出の棚
    SR = SKI_RACK
    g.rect(SR["x0"], SR["y0"], SR["x1"], SR["y1"], fill=C["wood_d"])
    for i in range(0, SR["n"], 2):
        y = SR["y0"] + (i + 0.5) * (SR["y1"] - SR["y0"]) / SR["n"]
        g.line(SR["x0"] - 0.1, y, SR["x1"] + 0.3, y, [C["sled"], C["food"], "#e2b84a", "#6c9a6a"][(i // 2) % 4], 2)
    g.text(SR["x1"] + 1.6, (SR["y0"] + SR["y1"]) / 2, "スキー置場", 10)
    g.rect(RENTAL["x0"], BACK["y0"], RENTAL["x1"], BACK["y1"], fill=C["wood_d"])
    g.text((RENTAL["x0"] + RENTAL["x1"]) / 2, BACK["y0"] - 0.55, "貸出の棚", 9)
    # 厨房の奥の台・間仕切り・メニュー板
    g.rect(L["back"][0], BACK["y0"], L["back"][1], BACK["y1"], fill=C["wood"], stroke=C["wood_d"], sw=0.6)
    for x in L["partition"]:
        g.line(x, KITCHEN["y_front"], x, Y1, wall, 4)
        g.text(x + 0.3, KITCHEN["y_front"] - 0.6, "間仕切り", 9, anchor="start")
    # 暖炉と長椅子
    g.rect(cx - hw, CH["y0"], cx + hw, Y1 + 1.5, fill=C["stone"], stroke="#9d968a")
    g.rect(cx - CH["fire_w"] / 2, CH["y0"], cx + CH["fire_w"] / 2, CH["y0"] + 0.7, fill=C["fire"])
    g.circle(cx, CH["y0"] + 0.3, 0.32, "#e8783a")
    off = cx - (CH["x0"] + CH["x1"]) / 2
    for x0, y0, x1, y1 in HEARTH_BENCH:
        g.rect(x0 + off, y0, x1 + off, y1, fill=C["wood"], stroke=C["wood_d"], sw=0.6)
    g.text(cx, CH["y0"] - 1.4, "暖炉", 15, weight="bold")
    # 中の自販機
    for x, y, rot in L["vend_in"]:
        w, d = (2.1, 1.8) if rot == 0 else (1.8, 2.1)
        g.box(x, y, w, d, fill=C["food"], stroke=C["ink"], sw=0.6)
    vx = sum(v[0] for v in L["vend_in"]) / 2
    vy = sum(v[1] for v in L["vend_in"]) / 2
    if L["vend_in"][0][2] == 0:
        g.text(vx, vy - 1.6, "自販機 2 台", 10)
    else:
        g.text(vx - 1.6, vy, "自販機 2 台", 10, anchor="end")
    # 厨房の装置と、ご飯係の雪だるまの冷蔵庫（食べ物）
    fx, fy = L["fridge"]
    g.box(fx, fy, 2.0, 1.6, fill="#f4f6f8", stroke=C["food"], sw=2)
    g.circle(fx, fy - 0.1, 0.5, "#ffffff", C["ink"], 0.8)
    g.text(fx, fy - 1.25, "雪だるま", 10, C["food"], weight="bold")
    g.text(fx, fy - 1.95, "の冷蔵庫", 10, C["food"], weight="bold")
    for (x, y), w, d, name in ((L["board"], 3.8, 1.24, "巨大アイロン台"), (L["press"], 1.6, 2.0, "プレス機"),
                               (L["dryer"], 2.7, 2.7, "乾燥機")):
        g.box(x, y, w, d, fill=C["food"], extra='opacity="0.9"')
        g.text(x, y - d / 2 - 0.6, name, 10, C["food"], weight="bold")
    for x, y in L["sacks"]:
        g.circle(x, y, 0.35, "#c9a46a", C["wood_d"], 0.5)
    # ミシンと売り子（ソリ・装備）
    mx, my = L["machine"]
    g.box(mx, my, 4.2, 1.8, fill=C["sled"], extra='opacity="0.9"')
    g.text(mx, my, "大きなミシン", 11, "#fff", weight="bold")
    sx, sy = L["seller"]
    g.circle(sx, sy, 0.45, "#f0e6d6", C["sled"], 2)
    g.text(sx, sy - 0.95, "売り子", 10, C["sled"], weight="bold")
    g.rect(mx - 2.1, my - 0.9 - 3.6, mx + 2.1, my - 0.9 - 0.3, stroke=C["sled"], sw=1, extra='stroke-dasharray="3 3"')
    g.text(mx, my - 3.0, "縫ったソリが出る床", 9, C["sled"])
    # 通り道
    p = C["path"]
    pa = 'stroke-dasharray="7 5" marker-end="url(#ar)" opacity="0.8"'
    ex = V["cx"]
    g.poly([(ex, Y0 - V["d"] - 0.4), (ex, Y0 + 1.0), (ex, 4.5), (mx + 1.0, 5.2)], p, 2.2, extra=pa)
    g.poly([(ex, 4.5), (cx, 5.2), (I["xm"] + 0.8, 5.2), ((I["xm"] + I["x1"]) / 2, I["y_bottom"] - 0.2)], p, 2.2, extra=pa)
    g.poly([(ex, Y0 + 1.0), (gx(9.8), gy(5.25)), (X1 - 2.0, gy(5.25))], p, 1.6, extra=pa)
    g.text(cx + 6.5, 5.9, "通り道", 10, p)
    # 迷う所の印（代表に聞く）
    if L.get("asks"):
        g.ask(mx - 3.0, my + 0.4, 1)
        g.ask(fx - 1.5, fy + 0.9, 2)
        g.ask(vx - 1.6, vy - 2.0, 3)
        g.ask(mx - 6.8, my - 2.0, 4)
    # 方位と縮尺
    g.text(X1 + 2.0, Y1 + 1.8, "北 ▲", 13, weight="bold")
    g.line(X1 - 5 * K, VY0 + 1.2, X1, VY0 + 1.2, C["ink"], 3)
    g.text(X1 - 5 * K, VY0 + 2.0, "0", 10, anchor="start")
    g.text(X1, VY0 + 2.0, "5 間 (9.09 m)", 10, anchor="end")
    g.text(VX0 + 0.6, VY1 - 1.0, "1 階 平面 — " + L["title"], 18, anchor="start", weight="bold")
    if L.get("asks"):
        g.circle(VX0 + 1.2, VY0 + 1.3, 0.45, C["ask"])
        g.text(VX0 + 2.0, VY0 + 1.3, "赤い丸 = 代表に聞きたい所", 11, anchor="start")

    defs = ('<defs><marker id="ar" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">'
            f'<path d="M0,0 L10,5 L0,10 z" fill="{C["path"]}"/></marker></defs>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W:.0f} {H:.0f}" width="{W:.0f}" height="{H:.0f}" '
           f'font-family="Hiragino Mincho ProN, Yu Mincho, serif">{defs}'
           f'<rect width="100%" height="100%" fill="{C["bg"]}"/>' + "".join(g.o) + "</svg>")
    with open(path, "w") as f:
        f.write(svg)


if __name__ == "__main__":
    draw(now_layout(), os.path.join(HERE, "plan-now.svg"))
    draw(new_layout(), os.path.join(HERE, "plan-new.svg"))
    print("wrote", HERE)
