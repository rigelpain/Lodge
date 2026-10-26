"""ロッジの図面（平面 2 枚・立面 2 枚・断面 1 枚）を SVG で書き出す。寸法は dims.py から。

    python3 lodge/drawings.py      # lodge/drawings/*.svg と sheet.svg

光は南西から（左上 45 度の慣用で、出の深さだけ右下へ影を落とす）。
"""
import math
import os
import random

from dims import *  # noqa: F403

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "drawings")
S = 34.0  # 1 m = 34 px

INK = "#272638"
PAPER = "#f4f0e7"
FAINT = "#8d8a99"
SHADE = "#2f4590"      # 影は藍（不透明度で薄める）
TINT = dict(
    stone="#d3d0cb", wood1="#c8a682", wood2="#d8bf9c", felt="#3e4f8a", snow="#ffffff",
    glass="#bfcbe0", glass_warm="#f1c98a", deck="#d2b48c", tatami="#d9d3a4", hearth="#bdb8b0",
    cushion="#a7563f", quilt="#c98a4b", metal="#8e8a86",
)
FONT = "Hiragino Mincho ProN, Yu Mincho, serif"


class Svg:
    def __init__(self, w, h, ox, oy, mapper):
        self.w, self.h, self.ox, self.oy = w, h, ox, oy
        self.map = mapper  # (u, v) -> world を画面の (x, y) に
        self.items = []

    def P(self, u, v):
        x, y = self.map(u, v)
        return self.ox + x * S, self.oy - y * S

    def _pts(self, pts):
        return " ".join(f"{x:.1f},{y:.1f}" for x, y in (self.P(u, v) for u, v in pts))

    def poly(self, pts, fill="none", stroke=INK, sw=0.8, op=1.0, dash=None, close=True):
        tag = "polygon" if close else "polyline"
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.items.append(f'<{tag} points="{self._pts(pts)}" fill="{fill}" fill-opacity="{op}" '
                          f'stroke="{stroke}" stroke-width="{sw}"{d}/>')

    def rect(self, u0, v0, u1, v1, **kw):
        self.poly([(u0, v0), (u1, v0), (u1, v1), (u0, v1)], **kw)

    def line(self, u0, v0, u1, v1, sw=0.6, stroke=INK, dash=None):
        (x0, y0), (x1, y1) = self.P(u0, v0), self.P(u1, v1)
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.items.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" '
                          f'stroke="{stroke}" stroke-width="{sw}"{d}/>')

    def path(self, d, fill="none", stroke=INK, sw=0.8, op=1.0):
        self.items.append(f'<path d="{d}" fill="{fill}" fill-opacity="{op}" stroke="{stroke}" stroke-width="{sw}"/>')

    def shade(self, pts, op=0.20):
        self.poly(pts, fill=SHADE, stroke="none", sw=0, op=op)

    def text(self, x, y, s, size=13, anchor="start", fill=INK, ls=0.12):
        self.items.append(f'<text x="{x:.1f}" y="{y:.1f}" font-family="{FONT}" font-size="{size}" '
                          f'letter-spacing="{ls}em" text-anchor="{anchor}" fill="{fill}">{s}</text>')

    def arc(self, cu, cv, r, a0, a1, sw=0.5):
        x0, y0 = self.P(cu + r * math.cos(a0), cv + r * math.sin(a0))
        x1, y1 = self.P(cu + r * math.cos(a1), cv + r * math.sin(a1))
        sweep = 0 if a1 > a0 else 1
        self.items.append(f'<path d="M{x0:.1f},{y0:.1f} A{r*S:.1f},{r*S:.1f} 0 0 {sweep} {x1:.1f},{y1:.1f}" '
                          f'fill="none" stroke="{INK}" stroke-width="{sw}"/>')

    def body(self):
        return "\n".join(self.items)

    def save(self, name, title):
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
               f'viewBox="0 0 {self.w} {self.h}"><rect width="100%" height="100%" fill="{PAPER}"/>'
               f'{self.body()}</svg>')
        with open(os.path.join(OUT, name), "w") as f:
            f.write(svg)
        return svg


def scale_bar(s, x, y):
    """1 間ごとの目盛り（0〜5 間）"""
    for i in range(5):
        fill = INK if i % 2 == 0 else PAPER
        s.items.append(f'<rect x="{x + i*K*S:.1f}" y="{y:.1f}" width="{K*S:.1f}" height="5" fill="{fill}" stroke="{INK}" stroke-width="0.6"/>')
    s.text(x, y + 20, "0", 11)
    s.text(x + 5 * K * S, y + 20, "5 間（9.09 m）", 11, anchor="middle")


def bay_x(start, bay):
    return start + (bay + 0.5) * K


# ---------------------------------------------------------------- 平面
def plan_walls(s, axis, fixed, a0, a1, openings, t=WALL_T, door_swing=None):
    """axis='x' なら y=fixed の壁を x=a0..a1 に。開口を抜いて塗り、窓は細線 2 本"""
    cuts = []
    for bay, kind in openings:
        k = KINDS[kind]
        c = bay_x(a0, bay) if bay == int(bay) else a0 + (bay + 0.5) * K
        cuts.append((c - k["w"] / 2, c + k["w"] / 2, kind))
    cuts.sort()
    segs, cur = [], a0
    for c0, c1, _ in cuts:
        segs.append((cur, c0))
        cur = c1
    segs.append((cur, a1))

    def R(u0, u1, v0, v1, **kw):
        if axis == "x":
            s.rect(u0, v0, u1, v1, **kw)
        else:
            s.rect(v0, u0, v1, u1, **kw)

    def L(u0, v0, u1, v1, **kw):
        if axis == "x":
            s.line(u0, v0, u1, v1, **kw)
        else:
            s.line(v0, u0, v1, u1, **kw)

    for u0, u1 in segs:
        if u1 > u0:
            R(u0, u1, fixed - t / 2, fixed + t / 2, fill=INK, stroke=INK, sw=0.6)
    for c0, c1, kind in cuts:
        if kind in ("win1", "win2", "wins"):
            L(c0, fixed - 0.02, c1, fixed - 0.02, sw=0.5)
            L(c0, fixed + 0.02, c1, fixed + 0.02, sw=0.5)
            L(c0, fixed - t / 2, c1, fixed - t / 2, sw=0.4)
            L(c0, fixed + t / 2, c1, fixed + t / 2, sw=0.4)
        elif kind == "slide2":
            m = (c0 + c1) / 2
            L(c0, fixed - 0.03, m + 0.05, fixed - 0.03, sw=0.9)
            L(m - 0.05, fixed + 0.03, c1, fixed + 0.03, sw=0.9)
        elif kind == "shed_door":
            L(c0, fixed + t / 2 + 0.05, c1 + 0.4, fixed + t / 2 + 0.05, sw=0.9)


def posts_on(s, axis, fixed, a0, n, skip=()):
    for i in range(n + 1):
        if i in skip:
            continue
        u = a0 + i * K
        if axis == "x":
            s.rect(u - POST / 2, fixed - POST / 2, u + POST / 2, fixed + POST / 2, fill=INK, sw=0.4)
        else:
            s.rect(fixed - POST / 2, u - POST / 2, fixed + POST / 2, u + POST / 2, fill=INK, sw=0.4)


def stones_plan(s, x0, y0, x1, y1, seed=1):
    rnd = random.Random(seed)
    s.rect(x0, y0, x1, y1, fill=TINT["stone"], sw=0.9)
    y = y0
    while y < y1 - 0.05:
        h = min(rnd.uniform(0.22, 0.32), y1 - y)
        x = x0
        while x < x1 - 0.05:
            w = min(rnd.uniform(0.25, 0.45), x1 - x)
            s.rect(x + 0.02, y + 0.02, x + w - 0.02, y + h - 0.02, fill="none", sw=0.3)
            x += w
        y += h


def grid(s, xs, ys, x_lab_y, y_lab_x):
    for i, x in enumerate(xs):
        s.line(x, ys[0] - 0.9, x, ys[-1] + 0.9, sw=0.3, stroke=FAINT, dash="8 2 2 2")
        px, py = s.P(x, x_lab_y)
        s.items.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="8" fill="{PAPER}" stroke="{FAINT}" stroke-width="0.6"/>')
        s.text(px, py + 4, str(i + 1), 10, anchor="middle", fill=FAINT, ls=0)
    names = "いろはにほへとち"
    for i, y in enumerate(ys):
        s.line(xs[0] - 0.9, y, xs[-1] + 0.9, y, sw=0.3, stroke=FAINT, dash="8 2 2 2")
        px, py = s.P(y_lab_x, y)
        s.items.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="8" fill="{PAPER}" stroke="{FAINT}" stroke-width="0.6"/>')
        s.text(px, py + 4, names[i], 10, anchor="middle", fill=FAINT, ls=0)


def plan_1f():
    W, H = 1200, 760
    s = Svg(W, H, 420, 330, lambda x, y: (x, y))
    xs = [X0 + i * K for i in range(11)] + [WX0 + i * K for i in range(1, 4)]
    ys = [Y0 + i * K for i in range(7)]
    grid(s, xs, ys, Y1 + 1.6, X0 - 2.2)

    # 丘のふもと（等高線）
    for j, (yy, amp) in enumerate([(-9.5, 0.4), (-12.0, 0.7), (-15.0, 1.0)]):
        pts = [(x, yy - amp * math.cos((x - 2) / 9.0)) for x in [X0 - 2 + i * 0.5 for i in range(60)]]
        s.poly(pts, close=False, sw=0.45, stroke=FAINT, dash="3 3" if j else None)

    # 基壇（石）とテラスの張り出し（上にある物は破線）
    stones_plan(s, X0 - 0.1, Y0 - 0.1, PORCH_X0, Y0 + 0.1, 3)
    stones_plan(s, PORCH_X1, Y0 - 0.1, X1 + 0.1, Y0 + 0.1, 4)
    s.rect(X0 - 0.1, Y0 - 0.1, X1 + 0.1, Y1 + 0.1, sw=0.5)
    s.rect(X0, Y0 - CANTI, X1, Y0, sw=0.6, dash="6 3")
    s.rect(PORCH_X0, BAY_Y, PORCH_X1, Y0 - CANTI, sw=0.6, dash="6 3")
    for px in (PORCH_X0, PORCH_X1):
        s.rect(px - BAY_PIER["w"] / 2, BAY_Y + 0.12 - BAY_PIER["w"] / 2, px + BAY_PIER["w"] / 2, BAY_Y + 0.12 + BAY_PIER["w"] / 2,
               fill=TINT["stone"], sw=0.6)
        s.rect(px - BAY_POST / 2, BAY_Y + 0.12 - BAY_POST / 2, px + BAY_POST / 2, BAY_Y + 0.12 + BAY_POST / 2, fill=INK)
    # 内側の床（板）
    for i in range(int((Y1 - Y0) / 0.6)):
        yy = Y0 + 0.3 + i * 0.6
        s.line(X0 + 0.2, yy, X1 - 0.2, yy, sw=0.2, stroke=FAINT)

    # 玄関の引っ込みと段
    s.rect(PORCH_X0, Y0, PORCH_X1, Y0 + PORCH_DEPTH, fill=PAPER, stroke="none")
    for i in range(PORCH_STEPS):
        yy = Y0 + i * 0.3
        s.line(PORCH_X0 + 0.1, yy, PORCH_X1 - 0.1, yy, sw=0.6)
    s.line(PORCH_X0 + 0.1, Y0 + 0.9, PORCH_X1 - 0.1, Y0 + 0.9, sw=0.6)
    plan_walls(s, "y", PORCH_X0, Y0, Y0 + PORCH_DEPTH, [])
    plan_walls(s, "y", PORCH_X1, Y0, Y0 + PORCH_DEPTH, [])
    # 両開きの戸
    dc = (PORCH_X0 + PORCH_X1) / 2
    yd = Y0 + PORCH_DEPTH
    s.rect(PORCH_X0, yd - WALL_T / 2, dc - 0.9, yd + WALL_T / 2, fill=INK)
    s.rect(dc + 0.9, yd - WALL_T / 2, PORCH_X1, yd + WALL_T / 2, fill=INK)
    for sgn in (-1, 1):
        hx = dc + sgn * 0.9
        s.line(hx, yd, hx, yd + 0.9, sw=0.6)
        s.arc(hx, yd, 0.9, math.pi / 2, math.pi if sgn > 0 else 0, sw=0.35)

    # 外壁
    plan_walls(s, "x", Y0, X0, PORCH_X0, [o for o in OPENINGS["1F_S"] if o[0] < 5])
    plan_walls(s, "x", Y0, PORCH_X1, X1, [(b - 7, k) for b, k in OPENINGS["1F_S"] if b >= 7])
    plan_walls(s, "y", X0, Y0, Y1, OPENINGS["1F_W"])
    plan_walls(s, "x", Y1, X0, X1, OPENINGS["1F_N"])
    # 東の壁: 2〜3 間目は下屋への広い口
    plan_walls(s, "y", X1, Y0, Y0 + 2 * K, [(0, "win1")])
    plan_walls(s, "y", X1, Y0 + 4 * K, Y1, [(1, "win1")])
    posts_on(s, "x", Y0, X0, 10, skip=(6,))
    posts_on(s, "x", Y1, X0, 10)
    posts_on(s, "y", X0, Y0, 6)
    posts_on(s, "y", X1, Y0, 6)
    for x in INNER_POSTS_X:
        for y in INNER_POSTS_Y:
            s.rect(x - 0.12, y - 0.12, x + 0.12, y + 0.12, fill=INK)

    # 下屋
    s.rect(WX0, WY0 - 0.06, WX1 + 0.06, WY1 + 0.06, sw=0.4)
    plan_walls(s, "x", WY0, WX0, WX1, OPENINGS["W_S"])
    plan_walls(s, "y", WX1, WY0, WY1, OPENINGS["W_E"])
    plan_walls(s, "x", WY1, WX0, WX1, [])
    # ソリ（並べて置く）とスキーの架台
    for i in range(4):
        x = WX0 + 0.5 + i * 0.95
        s.rect(x, WY0 + 0.5, x + 0.62, WY0 + 1.9, fill=TINT["cushion"], op=0.5, sw=0.6)
        s.line(x + 0.12, WY0 + 0.5, x + 0.12, WY0 + 1.9, sw=0.3)
        s.line(x + 0.5, WY0 + 0.5, x + 0.5, WY0 + 1.9, sw=0.3)
    s.rect(WX0 + 0.3, WY1 - 0.55, WX1 - 0.4, WY1 - 0.25, fill=TINT["wood1"], sw=0.6)
    for i in range(16):
        x = WX0 + 0.45 + i * 0.29
        s.line(x, WY1 - 0.62, x, WY1 - 0.18, sw=0.9)
    s.rect(WX1 - 0.55, WY0 + 2.3, WX1 - 0.25, WY1 - 0.8, fill=TINT["wood1"], sw=0.6)

    # 煙突（外に立つ石の塔）とストーブ
    stones_plan(s, X0 - CH_D0, CH_Y - CH_W0 / 2, X0 + 0.1, CH_Y + CH_W0 / 2, 7)
    s.rect(X0 - CH_D0 + 0.3, CH_Y - 0.3, X0 - 0.2, CH_Y + 0.3, fill=INK)
    st = STOVE
    s.rect(X0 + 0.15, st["y"] - 1.0, X0 + 2.15, st["y"] + 1.0, fill=TINT["hearth"], sw=0.6)
    s.rect(st["x"] - st["w"] / 2, st["y"] - st["d"] / 2, st["x"] + st["w"] / 2, st["y"] + st["d"] / 2, fill=INK)
    # ストーブを囲む長椅子（東に開いたコの字）
    s.rect(X0 + 0.4, st["y"] - 1.75, X0 + 2.6, st["y"] - 1.35, fill=TINT["wood2"], sw=0.6)
    s.rect(X0 + 0.4, st["y"] + 1.35, X0 + 2.6, st["y"] + 1.75, fill=TINT["wood2"], sw=0.6)
    s.rect(X0 + 2.95, st["y"] - 0.9, X0 + 3.35, st["y"] + 0.9, fill=TINT["wood2"], sw=0.6)
    # 物干し（上着と手袋を乾かす）
    s.line(X0 + 0.45, st["y"] - 2.25, X0 + 3.1, st["y"] - 2.25, sw=0.7, dash="2 1.5")

    # 窓際の席（各窓に 1 卓、窓に直交）
    for bay in (1, 2, 3, 4, 7, 8):
        cx = bay_x(X0, bay)
        s.rect(cx - 0.4, Y0 + 0.35, cx + 0.4, Y0 + 1.95, fill=TINT["wood2"], sw=0.7)
        for sgn in (-1, 1):
            s.rect(cx + sgn * 0.52 - 0.15, Y0 + 0.4, cx + sgn * 0.52 + 0.15, Y0 + 1.9, sw=0.5)
    # 中央の長卓
    s.rect(X0 + 3 * K + 0.3, -0.45, X0 + 5 * K - 0.3, 0.45, fill=TINT["wood2"], sw=0.7)
    for sgn in (-1, 1):
        s.rect(X0 + 3 * K + 0.35, sgn * 0.75 - 0.15, X0 + 5 * K - 0.35, sgn * 0.75 + 0.15, sw=0.5)

    # 厨房のカウンターと裏の棚、布を熱で扱う道具の形の調理機
    c = COUNTER
    s.rect(c["x0"], c["y"] - c["d"] / 2, c["x1"], c["y"] + c["d"] / 2, fill=TINT["wood1"], sw=0.9)
    s.rect(c["x0"], Y1 - 0.5, c["x1"], Y1 - 0.1, fill=TINT["wood1"], sw=0.6)
    for i, w in enumerate((1.2, 0.8, 1.0)):
        x = c["x0"] + 0.4 + i * 1.75
        s.rect(x, c["y"] + 0.55, x + w, c["y"] + 1.05, fill=TINT["metal"], op=0.5, sw=0.6)
    for i in range(5):
        x = c["x0"] + 0.4 + i * 1.05
        s.items.append('<circle cx="{:.1f}" cy="{:.1f}" r="5" fill="none" stroke="{}" stroke-width="0.5"/>'.format(
            *s.P(x, c["y"] - 0.62), INK))

    # 階段（北の壁に沿って西へ上る）
    sd = STAIR
    for i in range(sd["risers"]):
        x = sd["x_bottom"] - i * sd["tread"]
        s.line(x, sd["y0"], x, sd["y1"], sw=0.5 if i < 10 else 0.3, dash=None if i < 10 else "2 2")
    s.line(sd["x_top"], sd["y0"], sd["x_bottom"], sd["y0"], sw=0.8)
    xm = sd["x_bottom"] - 10 * sd["tread"]
    s.line(xm - 0.15, sd["y0"] - 0.05, xm + 0.15, sd["y1"] + 0.05, sw=0.8)
    ym = (sd["y0"] + sd["y1"]) / 2
    s.poly([(sd["x_bottom"] - 0.2, ym), (xm + 0.25, ym)], close=False, sw=0.6)
    s.poly([(xm + 0.45, ym + 0.12), (xm + 0.25, ym), (xm + 0.45, ym - 0.12)], close=False, sw=0.6)

    # 荷物棚と着替えの腰掛け
    s.rect(X2_1 + 0.15, Y1 - 0.5, X1 - 0.15, Y1 - 0.1, fill=TINT["wood1"], sw=0.6)
    for i in range(9):
        x = X2_1 + 0.15 + i * (X1 - X2_1 - 0.3) / 8
        s.line(x, Y1 - 0.5, x, Y1 - 0.1, sw=0.4)
    s.rect(X2_1 + 0.6, Y1 - 1.45, X1 - 0.6, Y1 - 1.1, fill=TINT["wood2"], sw=0.5)
    # 貸し出しのカウンターと上着の掛け棒
    s.rect(6.25, Y0 + 0.9, 6.8, -0.9, fill=TINT["wood1"], sw=0.9)
    for j in range(2):
        xx = 7.6 + j * 0.8
        s.line(xx, Y0 + 0.6, xx, -1.2, sw=0.8)
        for i in range(10):
            yy = Y0 + 0.75 + i * 0.36
            s.rect(xx - 0.25, yy - 0.06, xx + 0.25, yy + 0.06, fill=TINT["cushion"], op=0.55, sw=0.3)

    # 外のスキー立て
    s.rect(5.7, Y0 - 1.9, 8.7, Y0 - 1.7, fill=TINT["wood1"], sw=0.6)
    for i in range(11):
        s.line(5.85 + i * 0.27, Y0 - 2.0, 5.85 + i * 0.27, Y0 - 1.6, sw=0.9)

    # 方位と縮尺
    nx, ny = s.P(WX1 + 1.2, Y1 + 0.4)
    s.items.append(f'<path d="M{nx},{ny-22} L{nx+7},{ny+6} L{nx},{ny} L{nx-7},{ny+6} Z" fill="{INK}"/>')
    s.text(nx, ny - 28, "北", 11, anchor="middle")
    s.text(40, 40, "1 階　平面", 16, ls=0.3)
    scale_bar(s, 40, 700)
    return s


def plan_2f():
    W, H = 1200, 760
    s = Svg(W, H, 420, 330, lambda x, y: (x, y))
    xs = [X0 + i * K for i in range(11)] + [WX0 + i * K for i in range(1, 4)]
    ys = [Y0 + i * K for i in range(7)]
    grid(s, xs, ys, Y1 + 1.6, X0 - 2.2)

    # 下屋の屋根（見下ろし）
    s.rect(WX0, WY0 - 0.3, WX1 + W_EAVE_OUT, WY1 + 0.3, fill=TINT["snow"], sw=0.6)
    for i in range(1, 8):
        y = WY0 - 0.3 + i * (WY1 - WY0 + 0.6) / 8
        s.line(WX0 + 0.1, y, WX1 + W_EAVE_OUT - 0.1, y, sw=0.2, stroke=FAINT)
    my = 0.0
    s.poly([(WX0 + 0.6, my), (WX1 - 0.2, my)], close=False, sw=0.6)
    s.poly([(WX1 - 0.45, my + 0.15), (WX1 - 0.2, my), (WX1 - 0.45, my - 0.15)], close=False, sw=0.6)

    # テラス（南の帯 + 東の帯）。床板は南北に
    deck = [(X0, Y0 - CANTI), (PORCH_X0, Y0 - CANTI), (PORCH_X0, BAY_Y), (PORCH_X1, BAY_Y), (PORCH_X1, Y0 - CANTI),
            (X1, Y0 - CANTI), (X1, Y1), (X2_1, Y1), (X2_1, Y2_0), (X0, Y2_0)]
    s.poly(deck, fill=TINT["deck"], op=0.45, sw=0.9)
    x = X0 + 0.15
    while x < X1:
        ytop = Y2_0 if x < X2_1 else Y1
        y0d = BAY_Y if PORCH_X0 < x < PORCH_X1 else Y0 - CANTI
        s.line(x, y0d + 0.05, x, ytop - 0.05, sw=0.2, stroke=FAINT)
        x += 0.3
    # 手すり（上桟の線を二重に）
    rail = [(X0 + 0.05, Y2_0), (X0 + 0.05, Y0 - CANTI + 0.05), (PORCH_X0, Y0 - CANTI + 0.05), (PORCH_X0, BAY_Y + 0.05),
            (PORCH_X1, BAY_Y + 0.05), (PORCH_X1, Y0 - CANTI + 0.05), (X1 - 0.05, Y0 - CANTI + 0.05),
            (X1 - 0.05, Y1 - 0.05), (X2_1, Y1 - 0.05)]
    s.poly(rail, close=False, sw=1.6)
    for i in range(11):
        xx = X0 + i * K
        s.rect(xx - 0.06, Y0 - CANTI - 0.01, xx + 0.06, Y0 - CANTI + 0.11, fill=INK)
    # テラスの腰掛け
    s.rect(X0 + 3 * K + 0.2, Y2_0 - 0.55, X0 + 5 * K - 0.2, Y2_0 - 0.15, fill=TINT["wood2"], sw=0.6)

    # 座敷の畳（1 間 x 半間）。北の 1 間は板の間
    tz0, tz1 = Y2_0, Y1 - K
    for i in range(8):
        for j in range(3):
            x0, y0 = X2_0 + i * K, tz0 + j * K
            s.rect(x0, y0, x0 + K, y0 + K, fill=TINT["tatami"], op=0.6, sw=0.4)
            if (i + j) % 2:
                s.line(x0 + K / 2, y0, x0 + K / 2, y0 + K, sw=0.4)
            else:
                s.line(x0, y0 + K / 2, x0 + K, y0 + K / 2, sw=0.4)
    s.line(X2_0, tz1, X2_1, tz1, sw=1.0)
    for i in range(int((X2_1 - X2_0) / 0.3)):
        xx = X2_0 + 0.15 + i * 0.3
        s.line(xx, tz1 + 0.05, xx, Y1 - 0.1, sw=0.2, stroke=FAINT)

    # 掘りごたつ 3 卓（掘り込みは破線）と座布団
    kt = KOTATSU
    for kx in KOTATSU_X:
        s.rect(kx - kt["w"] / 2 - 0.25, KOTATSU_Y - kt["d"] / 2 - 0.25, kx + kt["w"] / 2 + 0.25, KOTATSU_Y + kt["d"] / 2 + 0.25,
               fill=TINT["quilt"], op=0.35, sw=0.4)
        s.rect(kx - kt["w"] / 2, KOTATSU_Y - kt["d"] / 2, kx + kt["w"] / 2, KOTATSU_Y + kt["d"] / 2, fill=TINT["wood2"], sw=0.9)
        s.rect(kx - kt["pit_w"] / 2 - 0.05, KOTATSU_Y - kt["pit_d"] / 2 - 0.4, kx + kt["pit_w"] / 2 + 0.05,
               KOTATSU_Y + kt["pit_d"] / 2 + 0.4, sw=0.5, dash="3 2")
        for dx in (-0.48, 0.48):
            for sgn in (-1, 1):
                cy = KOTATSU_Y + sgn * (kt["d"] / 2 + 0.55)
                s.rect(kx + dx - 0.27, cy - 0.3, kx + dx + 0.27, cy + 0.3, fill=TINT["cushion"], op=0.7, sw=0.5)
        for sgn in (-1, 1):
            cx = kx + sgn * (kt["w"] / 2 + 0.55)
            s.rect(cx - 0.3, KOTATSU_Y - 0.27, cx + 0.3, KOTATSU_Y + 0.27, fill=TINT["cushion"], op=0.7, sw=0.5)
        # 紙の灯り（吊り）
        s.items.append('<circle cx="{:.1f}" cy="{:.1f}" r="7" fill="none" stroke="{}" stroke-width="0.5" stroke-dasharray="2 2"/>'.format(
            *s.P(kx, KOTATSU_Y), INK))

    # 階段の吹き抜けと手すり、下足箱
    sd = STAIR
    s.rect(sd["x_top"], sd["y0"], X2_1 - WALL_T / 2, sd["y1"], fill=PAPER, sw=0.4)
    for i in range(10, sd["risers"]):
        x = sd["x_bottom"] - i * sd["tread"]
        s.line(x, sd["y0"], x, sd["y1"], sw=0.5)
    s.line(sd["x_top"], sd["y0"] - 0.05, X2_1 - 0.1, sd["y0"] - 0.05, sw=1.6)
    s.rect(-3.0, Y1 - 0.5, -0.6, Y1 - 0.12, fill=TINT["wood1"], sw=0.6)

    # 2 階の外壁と柱
    plan_walls(s, "x", Y2_0, X2_0, X2_1, OPENINGS["2F_S"])
    plan_walls(s, "y", X2_0, Y2_0, Y2_1, OPENINGS["2F_W"])
    plan_walls(s, "x", Y2_1, X2_0, X2_1, OPENINGS["2F_N"])
    plan_walls(s, "y", X2_1, Y2_0, Y2_1, OPENINGS["2F_E"])
    posts_on(s, "x", Y2_0, X2_0, 8)
    posts_on(s, "x", Y2_1, X2_0, 8)
    posts_on(s, "y", X2_0, Y2_0, 4)
    posts_on(s, "y", X2_1, Y2_0, 4)
    for x in INNER_POSTS_X[:3]:
        s.rect(x - 0.12, RIDGE_Y - 0.12, x + 0.12, RIDGE_Y + 0.12, fill=INK)

    # 煙突（肩より上）
    stones_plan(s, X0 - CH_D1, CH_Y - CH_W1 / 2, X0 + 0.1, CH_Y + CH_W1 / 2, 9)
    s.rect(X0 - CH_D1 + 0.22, CH_Y - 0.25, X0 - 0.15, CH_Y + 0.25, fill=INK)

    # 屋根の外形（上にある物は破線）と棟
    s.rect(X2_0 - VERGE_OUT, Y2_0 - EAVE_OUT, X2_1 + VERGE_OUT, Y2_1 + EAVE_OUT, sw=0.7, dash="7 3")
    s.line(X2_0 - VERGE_OUT, RIDGE_Y, X2_1 + VERGE_OUT, RIDGE_Y, sw=0.5, dash="10 3 2 3")

    nx, ny = s.P(WX1 + 1.2, Y1 + 0.4)
    s.items.append(f'<path d="M{nx},{ny-22} L{nx+7},{ny+6} L{nx},{ny} L{nx-7},{ny+6} Z" fill="{INK}"/>')
    s.text(nx, ny - 28, "北", 11, anchor="middle")
    s.text(40, 40, "2 階　平面", 16, ls=0.3)
    scale_bar(s, 40, 700)
    return s


# ---------------------------------------------------------------- 立面の部品
def stones_elev(s, u0, u1, z0, z1, seed=2, rows=3):
    """フェルトの小石を積んだ基壇。段ごとに長さがばらつき、角は丸い"""
    rnd = random.Random(seed)
    s.rect(u0, z0, u1, z1, fill=TINT["stone"], sw=1.0)
    h = (z1 - z0) / rows
    for r in range(rows):
        u = u0 + (rnd.uniform(0, 0.3) if r % 2 else 0)
        if r % 2:
            s.line(u0, z0 + r * h, u0, z0 + (r + 1) * h, sw=0)
        while u < u1 - 0.05:
            w = min(rnd.uniform(0.35, 0.7), u1 - u)
            za, zb = z0 + r * h + 0.025, z0 + (r + 1) * h - 0.025
            (xa, ya), (xb, yb) = s.P(u + 0.025, zb), s.P(u + w - 0.025, za)
            lo = rnd.uniform(0.92, 1.06)
            s.items.append(f'<rect x="{min(xa,xb):.1f}" y="{min(ya,yb):.1f}" width="{abs(xb-xa):.1f}" height="{abs(yb-ya):.1f}" '
                           f'rx="{h*S*0.38:.1f}" fill="#ffffff" fill-opacity="{0.25*(lo-0.9)*4:.2f}" stroke="{INK}" stroke-width="0.35"/>')
            u += w
    return s


def boards_h(s, u0, u1, z0, z1, gap=0.21):
    s.rect(u0, z0, u1, z1, fill=TINT["wood1"], sw=0.8)
    z = z0 + gap
    while z < z1 - 0.02:
        s.line(u0, z, u1, z, sw=0.25)
        z += gap


def boards_v(s, u0, u1, z0, z1, gap=0.30):
    s.rect(u0, z0, u1, z1, fill=TINT["wood2"], sw=0.8)
    u = u0 + gap
    while u < u1 - 0.02:
        s.line(u, z0, u, z1, sw=0.25)
        u += gap


def window_elev(s, cu, z0, k, kind, sun_left=True, warm=False):
    w, h, d = k["w"], k["h"], k["depth"]
    u0, u1, z1 = cu - w / 2, cu + w / 2, z0 + h
    s.rect(u0 - 0.06, z0 - 0.06, u1 + 0.06, z1 + 0.06, fill=TINT["wood1"], sw=0.7)   # 枠
    s.rect(u0, z0, u1, z1, fill=TINT["glass_warm" if warm else "glass"], sw=0.6)
    if kind in ("win1", "win2", "wins"):
        s.line(cu, z0, cu, z1, sw=0.45)
        for f in (1 / 3, 2 / 3) if kind != "wins" else (0.5,):
            s.line(u0, z0 + h * f, u1, z0 + h * f, sw=0.45)
    elif kind == "slide2":
        s.line(cu, z0, cu, z1, sw=0.8)
        for uu in (u0 + w / 4, cu + w / 4):
            pass
        s.line(u0, z0 + 0.9, u1, z0 + 0.9, sw=0.45)
    elif kind == "shed_door":
        for f in (0.25, 0.5, 0.75):
            s.line(u0 + w * f, z0, u0 + w * f, z1, sw=0.4)
    # 見込みの影（光は左上から: 左の縦枠と上枠が奥へ影を落とす）
    s.shade([(u0, z1), (u1, z1), (u1 - 0, z1 - d), (u0 + d, z1 - d), (u0 + d, z0), (u0, z0)], op=0.32)
    if kind not in ("slide2", "shed_door"):
        # 窓台: 明るい上端と、その下の影
        s.rect(u0 - 0.12, z0 - 0.09, u1 + 0.12, z0 - 0.02, fill=PAPER, sw=0.6)
        s.shade([(u0 - 0.12, z0 - 0.09), (u1 + 0.12, z0 - 0.09), (u1 + 0.2, z0 - 0.17), (u0 - 0.04, z0 - 0.17)], op=0.28)


def railing_elev(s, u0, u1, z0, posts, step=BALUSTER, sw_post=None):
    zt = z0 + RAIL_H
    u = u0 + step / 2
    while u < u1:
        s.line(u, z0 + 0.1, u, zt - 0.06, sw=0.5)
        u += step
    s.rect(u0, z0 + 0.06, u1, z0 + 0.12, fill=TINT["wood1"], sw=0.5)
    s.rect(u0 - 0.05, zt - 0.07, u1 + 0.05, zt + 0.02, fill=TINT["wood1"], sw=0.8)
    for p in posts:
        s.rect(p - 0.06, z0, p + 0.06, zt, fill=TINT["wood1"], sw=0.7)


def snow_band(s, pts_top, thick, sw=1.0):
    """毛糸の雪の帯: 上の線を厚みぶん下に下ろし、縁を丸める"""
    poly = pts_top + [(u, z - thick) for u, z in reversed(pts_top)]
    s.poly(poly, fill=TINT["snow"], sw=sw)


# ---------------------------------------------------------------- 屋根の帯（腰折れ）
def roof_lines():
    rl = ROOF_LINE
    ro = offset_line(rl, ROOF_T)
    return rl, ro


def chimney_elev(s, c0, c1, c0u, c1u, seed, z_hide=None):
    """c0..c1 が下（肩まで）、c0u..c1u が上の幅。z_hide=(u0, u1, za, zb) はその範囲を描かない（屋根の陰）"""
    stones_elev(s, c0, c1, 0, CH_SHOULDER, seed=seed, rows=13)
    s.poly([(c0, CH_SHOULDER), (c0u, CH_SHOULDER + 0.35), (c1u, CH_SHOULDER + 0.35), (c1, CH_SHOULDER)],
           fill=TINT["stone"], sw=0.9)
    stones_elev(s, c0u, c1u, CH_SHOULDER + 0.35, CH_TOP, seed=seed + 1, rows=17)
    chimney_cap(s, c0u, c1u)


def chimney_cap(s, c0u, c1u):
    s.rect(c0u + 0.12, CH_TOP, c1u - 0.12, CH_TOP + 0.16, fill=INK)
    s.rect(c0u - CH_CAP_OUT, CH_TOP + 0.16, c1u + CH_CAP_OUT, CH_TOP + 0.3, fill=TINT["felt"], sw=0.9)
    s.path("M{},{} Q{},{} {},{}".format(*s.P(c0u - CH_CAP_OUT, CH_TOP + 0.3), *s.P((c0u + c1u) / 2, CH_TOP + 0.55),
                                        *s.P(c1u + CH_CAP_OUT, CH_TOP + 0.3)), fill=TINT["snow"], sw=0.9)


def snow_hem(s, u0, u1, z0, z1, hem=0.05, wave=0.22):
    """編み地の雪の毛布: 上は平ら、下の縁（裾）はゆるく波打つ"""
    n = max(2, int((u1 - u0) / wave))
    d = "M{},{} ".format(*s.P(u0, z1)) + "L{},{} ".format(*s.P(u1, z1))
    d += "Q{},{} {},{} ".format(*s.P(u1 + 0.06, (z0 + z1) / 2), *s.P(u1 - 0.02, z0))
    for i in range(n, 0, -1):
        ua, ub = u0 + (u1 - u0) * i / n, u0 + (u1 - u0) * (i - 1) / n
        d += "Q{},{} {},{} ".format(*s.P((ua + ub) / 2, z0 - hem), *s.P(ub, z0))
    d += "Q{},{} {},{} Z".format(*s.P(u0 - 0.06, (z0 + z1) / 2), *s.P(u0, z1))
    s.path(d, fill=TINT["snow"], sw=1.0)


# ---------------------------------------------------------------- 南立面
def elev_south():
    W, H = 1160, 520
    s = Svg(W, H, 560, 440, lambda x, z: (x, z))
    fas0 = DECK_Z - FASCIA_H
    rl, ro = roof_lines()
    ru0, ru1 = X2_0 - VERGE_OUT, X2_1 + VERGE_OUT
    cx0, cx1 = X0 - CH_D0, X0

    # 煙突（奥。屋根より先に描く）
    chimney_elev(s, cx0, cx1, X0 - CH_D1, X0, 11)

    # 2 階の南の壁（縦羽目）と開口
    boards_v(s, X2_0, X2_1, FL2, EAVE_Z)
    for bay, kind in OPENINGS["2F_S"]:
        window_elev(s, bay_x(X2_0, bay), FL2 + KINDS[kind]["sill"], KINDS[kind], kind)
    for i in range(9):
        u = X2_0 + i * K
        s.rect(u - POST / 2, FL2, u + POST / 2, EAVE_Z, fill=TINT["wood1"], sw=0.6)
    # 軒の影（軒先の下端から、出の分だけ下へ）
    zs = rl[0][1] - EAVE_OUT
    s.shade([(X2_0, EAVE_Z), (X2_1, EAVE_Z), (X2_1, zs), (X2_0 + EAVE_OUT, zs), (X2_0, zs + 0.25)], op=0.26)

    # 屋根: 軒先の鼻隠し → はね出し（雪）→ 急な流れ（藍）→ ゆるい流れ（雪）
    s.rect(ru0, rl[0][1], ru1, ro[3][1], fill=TINT["felt"], sw=1.2)
    s.rect(ru0, rl[0][1], ru1, ro[0][1], fill="#2f3d6e", sw=0.9)                   # 鼻隠し（影側で暗い）
    s.line(ru0, ro[1][1], ru1, ro[1][1], sw=0.5)
    for i in range(1, 6):                                                          # 急な流れの縫い目
        z = ro[1][1] + (ro[2][1] - ro[1][1]) * i / 6
        s.line(ru0 + 0.05, z, ru1 - 0.05, z, sw=0.25, stroke="#9aa6d0")
    u = ru0 + 0.2
    while u < ru1 - 0.1:                                                           # 垂木の鼻
        s.rect(u - 0.045, rl[0][1] - 0.12, u + 0.045, rl[0][1], fill=TINT["wood1"], sw=0.4)
        u += K / 4
    snow_hem(s, ru0 + 0.25, ru1 - 0.25, ro[2][1] - 0.02, ro[3][1] + SNOW_T, hem=0.07)  # 上の流れの雪
    for i in range(1, 5):
        z = ro[2][1] + (ro[3][1] + SNOW_T - ro[2][1]) * i / 5
        s.line(ru0 + 0.4, z, ru1 - 0.4, z, sw=0.2, stroke=FAINT)
    # 煙突は棟の 1 間南に立つので、けらばより内の部分は南の流れの上 (z>8.3) だけ見える
    zc = roof_z(CH_Y) + ROOF_T + SNOW_T * 0.6
    stones_elev(s, X0 - VERGE_OUT, X0, zc, CH_TOP, seed=19, rows=5)
    stones_elev(s, X0 - CH_D1, X0 - VERGE_OUT, EAVE_EDGE_Z - 0.3, CH_TOP, seed=18, rows=10)
    chimney_cap(s, X0 - CH_D1, X0)

    # 東のテラスの奥の手すり（北の縁）
    railing_elev(s, X2_1, X1, DECK_Z, [X2_1 + K, X1])

    # テラスの縁の梁と南の手すり
    s.rect(X0 - 0.06, fas0, X1 + 0.06, DECK_Z, fill=TINT["wood1"], sw=1.2)
    s.line(X0 - 0.06, DECK_Z - 0.06, X1 + 0.06, DECK_Z - 0.06, sw=0.4)
    railing_elev(s, X0, X1, DECK_Z, [X0 + i * K for i in range(11)])

    # 1 階の南の壁（下見板）と柱、窓、玄関
    boards_h(s, X0, X1, PLINTH, fas0)
    dc = (PORCH_X0 + PORCH_X1) / 2
    s.rect(dc - 0.96, PLINTH - 0.0, dc + 0.96, PLINTH + 2.46, fill=TINT["wood1"], sw=0.7)
    s.rect(dc - 0.9, PLINTH, dc + 0.9, PLINTH + 2.2, fill="#7a5a43", sw=0.7)
    s.rect(dc - 0.9, PLINTH + 2.22, dc + 0.9, PLINTH + 2.4, fill=TINT["glass_warm"], sw=0.5)
    s.line(dc, PLINTH, dc, PLINTH + 2.2, sw=0.6)
    for sgn in (-1, 1):
        s.rect(dc + sgn * 0.45 - 0.2, PLINTH + 0.9, dc + sgn * 0.45 + 0.2, PLINTH + 1.9, fill=TINT["glass_warm"], sw=0.5)
    for i in range(PORCH_STEPS):
        s.rect(PORCH_X0, i * 0.2, PORCH_X1, (i + 1) * 0.2, fill=TINT["stone"], sw=0.6)
    for bay, kind in OPENINGS["1F_S"]:
        window_elev(s, bay_x(X0, bay), PLINTH + WIN1["sill"], WIN1, kind)
    for i in range(11):
        if i == 6:
            continue
        u = X0 + i * K
        s.rect(u - POST / 2 - 0.015, PLINTH, u + POST / 2 + 0.015, fas0, fill=TINT["wood1"], sw=0.7)
        s.poly([(u - 0.07, fas0 - 1.05), (u + 0.07, fas0 - 1.05), (u + 0.07, fas0), (u - 0.07, fas0)], fill="#9c7b5c", sw=0.7)
    # テラスの張り出しの影の帯（出 0.9 m → 下へ 0.9 m）。玄関の奥は 1 間ぶん深い影
    s.shade([(X0, fas0), (X1, fas0), (X1, fas0 - CANTI), (X0 + CANTI, fas0 - CANTI), (X0, fas0 - CANTI + 0.3)], op=0.26)
    s.shade([(PORCH_X0, fas0 - CANTI), (PORCH_X1, fas0 - CANTI), (PORCH_X1, fas0 - CANTI - PORCH_DEPTH),
             (PORCH_X0 + PORCH_DEPTH, fas0 - CANTI - PORCH_DEPTH), (PORCH_X0 + PORCH_DEPTH, 0), (PORCH_X0, 0)], op=0.34)
    s.line(PORCH_X0, 0, PORCH_X0, fas0, sw=1.3)
    s.line(PORCH_X1, 0, PORCH_X1, fas0, sw=1.3)

    stones_elev(s, X0 - 0.1, PORCH_X0, 0, PLINTH, seed=21)
    stones_elev(s, PORCH_X1, X1 + 0.1, 0, PLINTH, seed=22)
    # 張り出しの 2 本の柱（手前）と石の束
    for px in (PORCH_X0, PORCH_X1):
        stones_elev(s, px - BAY_PIER["w"] / 2, px + BAY_PIER["w"] / 2, 0, BAY_PIER["h"], seed=int(px * 7) + 3, rows=2)
        s.rect(px - BAY_POST / 2, BAY_PIER["h"], px + BAY_POST / 2, fas0, fill=TINT["wood1"], sw=1.0)

    # 下屋（1 間さがる）: 母屋の影が 1 間ぶん落ちる
    zw = lambda x: W_HIGH - (x - WX0) * W_PITCH
    s.poly([(WX0, 0), (WX0, zw(WX0)), (WX1, zw(WX1)), (WX1, 0)], fill=TINT["wood1"], sw=0.9)
    z = 0.21
    while z < W_HIGH:
        s.line(WX0, z, min(WX1, WX0 + (W_HIGH - z) / W_PITCH), z, sw=0.25)
        z += 0.21
    window_elev(s, WX0 + K, W_FL, SHED_DOOR, "shed_door")
    stones_elev(s, WX0, WX1 + 0.05, 0, W_FL + 0.1, seed=23, rows=1)
    e = WX1 + W_EAVE_OUT
    s.poly([(WX0, zw(WX0)), (e, zw(e)), (e, zw(e) + ROOF_T), (WX0, zw(WX0) + ROOF_T)], fill=TINT["felt"], sw=1.0)
    snow_band(s, [(WX0, zw(WX0) + ROOF_T + 0.3), (e - 0.25, zw(e - 0.25) + ROOF_T + 0.28)], 0.3)
    s.shade([(WX0, 0), (WX0, fas0 + 0.2), (WX0 + K, fas0 + 0.2 - K * W_PITCH), (WX0 + K, 0)], op=0.3)

    # スキー立て
    s.rect(5.7, 0, 5.8, 1.1, fill=TINT["wood1"], sw=0.6)
    s.rect(8.6, 0, 8.7, 1.1, fill=TINT["wood1"], sw=0.6)
    s.rect(5.6, 1.0, 8.8, 1.1, fill=TINT["wood1"], sw=0.6)
    for i in range(11):
        u = 5.85 + i * 0.27
        s.poly([(u, 0.05), (u + 0.06, 0.05), (u + 0.12, 1.75), (u + 0.06, 1.78)], fill=TINT["cushion"] if i % 3 else TINT["felt"], sw=0.5)

    s.path("M{},{} ".format(*s.P(-16, 0)) + " ".join("L{},{}".format(*s.P(x, 0.18 + 0.12 * math.sin(x * 0.9)))
                                                     for x in [X0 - 2.0 + i * 0.5 for i in range(int((WX1 + 3 - X0) / 0.5))])
           + " L{},{} L{},{} L{},{} Z".format(*s.P(WX1 + 4, 0), *s.P(WX1 + 4, -0.6), *s.P(-16, -0.6)), fill=TINT["snow"], sw=0)
    s.line(-16, 0, WX1 + 4, 0, sw=2.2)
    s.text(40, 40, "南　立面（丘から見る）", 16, ls=0.3)
    scale_bar(s, 40, 480)
    return s


# ---------------------------------------------------------------- 西立面
def elev_west():
    W, H = 900, 520
    s = Svg(W, H, 420, 440, lambda y, z: (-y, z))   # 東を向いて見る: 右が南（丘）
    fas0 = DECK_Z - FASCIA_H
    rl, ro = roof_lines()

    # 丘（奥で南へ上る）
    hill = [(Y0 - 4 - i * 0.5, (i * 0.5) ** 1.15 * 0.3) for i in range(24)]
    s.poly([(Y0 - 4, 0)] + hill + [(hill[-1][0], 0)], fill="#ffffff", sw=0)
    s.poly(hill, close=False, sw=0.8, stroke=FAINT)

    # 2 階の妻壁（縦羽目）
    gable = [(Y2_0, FL2), (Y2_1, FL2)] + [p for p in reversed(rl[1:6])]
    s.poly(gable, fill=TINT["wood2"], sw=0.9)
    u = Y2_0 + 0.3
    while u < Y2_1:
        s.line(u, FL2, u, roof_z(u), sw=0.25)
        u += 0.3
    for bay, kind in OPENINGS["2F_W"]:
        window_elev(s, Y2_0 + (bay + 0.5) * K, FL2 + KINDS[kind]["sill"], KINDS[kind], kind)
    # けらばの影
    s.shade(rl[1:6] + [(y, z - VERGE_OUT) for y, z in reversed(rl[1:6])], op=0.22)

    # 屋根の小口（藍）、母屋の鼻、雪
    s.poly(rl + list(reversed(ro)), fill=TINT["felt"], sw=1.3)
    for yy in (Y2_0, Y2_0 + LOW_RUN, (Y2_0 + LOW_RUN + RIDGE_Y) / 2, RIDGE_Y,
               (Y2_1 - LOW_RUN + RIDGE_Y) / 2, Y2_1 - LOW_RUN, Y2_1):
        zz = roof_z(yy)
        s.rect(yy - 0.09, zz - 0.2, yy + 0.09, zz, fill=TINT["wood1"], sw=0.5)
    up = [ro[2], ro[3], ro[4]]
    snow_band(s, [(up[0][0] + 0.05, up[0][1] + SNOW_T * 0.7), (RIDGE_Y - 0.4, up[1][1] + SNOW_T - 0.16),
                  (RIDGE_Y, up[1][1] + SNOW_T + 0.04), (RIDGE_Y + 0.4, up[1][1] + SNOW_T - 0.16),
                  (up[2][0] - 0.05, up[2][1] + SNOW_T * 0.7)], SNOW_T * 0.85)
    for a, b in ((ro[0], ro[1]), (ro[6], ro[5])):
        snow_band(s, [(a[0] + (0.1 if a[0] < b[0] else -0.1), a[1] + 0.12), (b[0], b[1] + 0.18)], 0.15)

    # 1 階の西の壁（下見板）と窓、柱
    boards_h(s, Y0, Y1, PLINTH, fas0)
    for bay, kind in OPENINGS["1F_W"]:
        window_elev(s, Y0 + (bay + 0.5) * K, PLINTH + WIN1["sill"], WIN1, kind)
    for i in range(7):
        u = Y0 + i * K
        s.rect(u - POST / 2, PLINTH, u + POST / 2, fas0, fill=TINT["wood1"], sw=0.6)

    # 階の境の帯（縁の梁）とテラスの張り出し、持ち送り
    s.rect(Y0 - CANTI - 0.06, fas0, Y1 + 0.06, DECK_Z, fill=TINT["wood1"], sw=1.2)
    s.poly([(Y0, fas0 - 1.15), (Y0 - 0.1, fas0 - 1.15), (Y0 - CANTI + 0.1, fas0 - 0.02), (Y0 - CANTI + 0.3, fas0 - 0.02)],
           fill="#9c7b5c", sw=0.8)
    s.rect(Y0 - 0.2, fas0 - 1.25, Y0 + 0.02, fas0 - 1.05, fill="#9c7b5c", sw=0.6)
    # 玄関の上の張り出し（奥にある。デッキの横顔・柱・束・手すり）
    s.rect(BAY_Y, fas0, Y0 - CANTI, DECK_Z, fill=TINT["wood1"], sw=0.9)
    stones_elev(s, BAY_Y + 0.12 - BAY_PIER["w"] / 2, BAY_Y + 0.12 + BAY_PIER["w"] / 2, 0, BAY_PIER["h"], seed=5, rows=2)
    s.rect(BAY_Y + 0.12 - BAY_POST / 2, BAY_PIER["h"], BAY_Y + 0.12 + BAY_POST / 2, fas0, fill=TINT["wood1"], sw=0.9)
    railing_elev(s, BAY_Y + 0.05, Y0 - CANTI, DECK_Z, [BAY_Y + 0.05])
    railing_elev(s, Y0 - CANTI + 0.05, Y2_0, DECK_Z, [Y0 - CANTI + 0.05, Y0, Y0 + K, Y2_0])
    s.shade([(Y0, fas0), (Y1, fas0), (Y1, fas0 - 0.35), (Y0, fas0 - 0.35)], op=0.18)

    # 煙突（手前）。光は南西（右手前）から来るので、影は煙突の北（画面の左）の壁へ、出の分だけずれて落ちる
    c0, c1, c0u, c1u = CH_Y - CH_W0 / 2, CH_Y + CH_W0 / 2, CH_Y - CH_W1 / 2, CH_Y + CH_W1 / 2
    d0, d1 = CH_D0 * 0.75, CH_D1 * 0.75
    s.shade([(c1, PLINTH), (c1 + d0, PLINTH), (c1 + d0, CH_SHOULDER - d0 * 0.4), (c1u + d1, CH_SHOULDER + 0.2),
             (c1u + d1, roof_z(c1u + d1) - 0.15), (c1u, roof_z(c1u) - 0.15), (c1u, CH_SHOULDER + 0.35), (c1, CH_SHOULDER)], op=0.26)
    chimney_elev(s, c0, c1, c0u, c1u, 31)

    stones_elev(s, Y0 - 0.1, Y1 + 0.1, 0, PLINTH, seed=33)
    s.path("M{},{} ".format(*s.P(Y1 + 3, 0)) + " ".join("L{},{}".format(*s.P(y, 0.2 + 0.1 * math.sin(y * 1.1)))
                                                       for y in [Y1 + 1.5 - i * 0.5 for i in range(int((Y1 - Y0 + 3) / 0.5))])
           + " L{},{} L{},{} Z".format(*s.P(Y0 - 2, 0), *s.P(Y1 + 3, 0)), fill=TINT["snow"], sw=0)
    s.line(Y1 + 3, 0, Y0 - 4, 0, sw=2.2)
    s.text(40, 40, "西　立面（右が丘）", 16, ls=0.3)
    scale_bar(s, 40, 480)
    return s


# ---------------------------------------------------------------- 断面 A（x = 1.5 間、東を向いて見る）
def section_a():
    W, H = 900, 560
    s = Svg(W, H, 420, 470, lambda y, z: (-y, z))
    fas0 = DECK_Z - FASCIA_H
    rl, ro = roof_lines()

    hill = [(Y0 - 4 - i * 0.5, (i * 0.5) ** 1.15 * 0.3) for i in range(24)]
    s.poly(hill, close=False, sw=0.8, stroke=FAINT)

    # 見えがかり（奥）: 中の柱、棟の束、持ち送り、梁と小屋の水平材
    for y in INNER_POSTS_Y:
        s.rect(y - 0.12, PLINTH, y + 0.12, FL2 - FLOOR2_T, fill=TINT["wood2"], sw=0.6)
    s.rect(RIDGE_Y - 0.1, FL2, RIDGE_Y + 0.1, RIDGE_Z - 0.3, fill=TINT["wood2"], sw=0.6)
    s.poly([(Y0, fas0 - 1.15), (Y0 - 0.1, fas0 - 1.15), (Y0 - CANTI + 0.1, fas0 - 0.02), (Y0 - CANTI + 0.3, fas0 - 0.02)],
           fill="#9c7b5c", sw=0.6)
    s.rect(BAY_Y, fas0, Y0 - CANTI, DECK_Z, fill="none", sw=0.5)                               # 玄関の上の張り出し
    s.rect(BAY_Y + 0.12 - BAY_POST / 2, BAY_PIER["h"], BAY_Y + 0.12 + BAY_POST / 2, fas0, fill="none", sw=0.5)
    s.rect(BAY_Y + 0.12 - BAY_PIER["w"] / 2, 0, BAY_Y + 0.12 + BAY_PIER["w"] / 2, BAY_PIER["h"], fill="none", sw=0.5)
    s.rect(Y2_0, EAVE_Z - 0.28, Y2_1, EAVE_Z, fill=TINT["wood2"], sw=0.6)                    # 桁をつなぐ梁
    s.rect(Y2_0 + LOW_RUN, KNEE_Z - 0.22, Y2_1 - LOW_RUN, KNEE_Z, fill=TINT["wood2"], sw=0.6)  # 折れ点の水平材

    stones_elev(s, Y0 - 0.1, Y1 + 0.1, 0, PLINTH - 0.15, seed=41, rows=2)
    s.rect(Y0, PLINTH - 0.15, Y1, PLINTH, fill=INK)
    for y in (Y0, Y1):
        s.rect(y - WALL_T / 2, PLINTH, y + WALL_T / 2, PLINTH + WIN1["sill"], fill=INK)
        s.rect(y - WALL_T / 2, PLINTH + WIN1["sill"] + WIN1["h"], y + WALL_T / 2, fas0, fill=INK)
        s.line(y, PLINTH + WIN1["sill"], y, PLINTH + WIN1["sill"] + WIN1["h"], sw=0.6)
        s.rect(y - 0.18, PLINTH + WIN1["sill"] - 0.05, y + 0.18, PLINTH + WIN1["sill"], fill=INK)
    s.rect(Y2_0 - 0.1, FL2 - FLOOR2_T, Y1 + 0.1, FL2, fill=INK)
    s.rect(Y0 - CANTI, DECK_Z - FASCIA_H, Y2_0, DECK_Z - FASCIA_H + 0.28, fill=INK)
    s.rect(Y0 - CANTI, DECK_Z - DECK_T, Y2_0, DECK_Z, fill=TINT["deck"], sw=0.6)
    s.rect(Y0 - CANTI - 0.06, fas0, Y0 - CANTI + 0.02, DECK_Z, fill=INK)
    s.line(Y0, FL2 - FLOOR2_T - 0.02, Y1, FL2 - FLOOR2_T - 0.02, sw=0.5)
    s.rect(Y0 - CANTI + 0.04, DECK_Z, Y0 - CANTI + 0.12, DECK_Z + RAIL_H, fill=TINT["wood1"], sw=0.6)
    s.rect(Y0 - CANTI - 0.0, DECK_Z + RAIL_H - 0.08, Y0 - CANTI + 0.16, DECK_Z + RAIL_H + 0.02, fill=INK)
    for y in (Y2_0, Y2_1):
        s.rect(y - WALL_T / 2, FL2, y + WALL_T / 2, FL2 + WIN2["sill"], fill=INK)
        s.rect(y - WALL_T / 2, FL2 + WIN2["sill"] + WIN2["h"], y + WALL_T / 2, EAVE_Z, fill=INK)
        s.line(y, FL2 + WIN2["sill"], y, FL2 + WIN2["sill"] + WIN2["h"], sw=0.6)
    # 屋根（切断、藍）と雪、棟木
    s.poly(rl + list(reversed(ro)), fill=TINT["felt"], sw=1.3)
    up = [ro[2], ro[3], ro[4]]
    snow_band(s, [(up[0][0] + 0.05, up[0][1] + SNOW_T * 0.7), (RIDGE_Y, up[1][1] + SNOW_T + 0.04),
                  (up[2][0] - 0.05, up[2][1] + SNOW_T * 0.7)], SNOW_T * 0.85)
    for a, b in ((ro[0], ro[1]), (ro[6], ro[5])):
        snow_band(s, [(a[0] + (0.1 if a[0] < b[0] else -0.1), a[1] + 0.12), (b[0], b[1] + 0.18)], 0.15)
    s.rect(RIDGE_Y - 0.15, RIDGE_Z - 0.3, RIDGE_Y + 0.15, RIDGE_Z, fill=INK)

    # 掘りごたつ（切断）: 畳、掘り込み、天板、こたつ布団、座布団、紙の灯り
    kt = KOTATSU
    s.rect(Y2_0 + 0.1, FL2, Y2_1 - K, FL2 + 0.055, fill=TINT["tatami"], sw=0.5)
    p0, p1 = KOTATSU_Y - kt["pit_d"] / 2 - 0.4, KOTATSU_Y + kt["pit_d"] / 2 + 0.4
    s.rect(p0, FL2 - kt["pit_depth"], p1, FL2 + 0.06, fill=PAPER, sw=0.8)
    s.rect(KOTATSU_Y - kt["d"] / 2 - 0.25, FL2 + kt["h"] - 0.06, KOTATSU_Y + kt["d"] / 2 + 0.25, FL2 + kt["h"] - 0.02,
           fill=TINT["quilt"], sw=0.5)
    s.rect(KOTATSU_Y - kt["d"] / 2, FL2 + kt["h"] - 0.02, KOTATSU_Y + kt["d"] / 2, FL2 + kt["h"] + 0.03, fill=INK)
    for yy in (KOTATSU_Y - kt["d"] / 2 + 0.05, KOTATSU_Y + kt["d"] / 2 - 0.08):
        s.rect(yy, FL2 - kt["pit_depth"], yy + 0.03, FL2 + kt["h"] - 0.06, fill=TINT["wood1"], sw=0.3)
    for sgn in (-1, 1):
        cy = KOTATSU_Y + sgn * (kt["d"] / 2 + 0.6)
        s.items.append('<rect x="{:.1f}" y="{:.1f}" width="{:.1f}" height="{:.1f}" rx="3" fill="{}" stroke="{}" stroke-width="0.6"/>'.format(
            s.P(cy + 0.3, 0)[0], s.P(0, FL2 + 0.17)[1], 0.6 * S, 0.11 * S, TINT["cushion"], INK))
    lz = FL2 + 1.75
    s.line(KOTATSU_Y, lz + 0.3, KOTATSU_Y, KNEE_Z - 0.22, sw=0.4)
    s.items.append('<ellipse cx="{:.1f}" cy="{:.1f}" rx="{:.1f}" ry="{:.1f}" fill="#fbf3dc" stroke="{}" stroke-width="0.6"/>'.format(
        *s.P(KOTATSU_Y, lz + 0.12), 0.28 * S, 0.2 * S, INK))

    # 1 階: 窓際の卓（切断）とカウンター（切断）、蛍光灯
    s.rect(Y0 + 0.35, PLINTH + 0.68, Y0 + 1.95, PLINTH + 0.74, fill=INK)
    for yy in (Y0 + 0.5, Y0 + 1.8):
        s.rect(yy - 0.03, PLINTH, yy + 0.03, PLINTH + 0.68, fill=TINT["wood1"], sw=0.3)
    c = COUNTER
    s.rect(c["y"] - c["d"] / 2, PLINTH, c["y"] + c["d"] / 2, PLINTH + c["h"], fill=INK)
    s.rect(Y1 - 0.5, PLINTH + 1.4, Y1 - 0.1, PLINTH + 1.44, fill=INK)
    s.rect(Y1 - 0.5, PLINTH + 1.9, Y1 - 0.1, PLINTH + 1.94, fill=INK)
    for yy in (Y0 + 1.2, -0.0, 2.6):
        s.rect(yy - 0.5, FL2 - FLOOR2_T - 0.1, yy + 0.5, FL2 - FLOOR2_T - 0.04, fill="#fffbe8", sw=0.5)

    s.line(Y1 + 3, 0, Y0 - 4, 0, sw=2.2)
    s.text(40, 40, "断面 A（西から 1.5 間、東を向いて見る。右が丘）", 16, ls=0.2)
    scale_bar(s, 40, 525)
    return s


def main():
    os.makedirs(OUT, exist_ok=True)
    parts = [("plan-1f.svg", plan_1f()), ("plan-2f.svg", plan_2f()), ("elev-south.svg", elev_south()),
             ("elev-west.svg", elev_west()), ("section-a.svg", section_a())]
    for name, s in parts:
        s.save(name, name)
    # 1 枚にまとめる: 上に南立面、中に平面 2 枚、下に西立面と断面
    lay = {"elev-south.svg": (0, 0), "plan-1f.svg": (0, 520), "plan-2f.svg": (1200, 520),
           "elev-west.svg": (1160, 0), "section-a.svg": (2060, 0)}
    sw, sh = 2960, 1280
    body = [f'<rect width="100%" height="100%" fill="{PAPER}"/>']
    for name, s in parts:
        x, y = lay[name]
        body.append(f'<svg x="{x}" y="{y}" width="{s.w}" height="{s.h}" viewBox="0 0 {s.w} {s.h}">{s.body()}</svg>')
    with open(os.path.join(OUT, "sheet.svg"), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{sw}" height="{sh}" viewBox="0 0 {sw} {sh}">{"".join(body)}</svg>')
    print("wrote", OUT)


if __name__ == "__main__":
    main()
