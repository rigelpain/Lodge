"""スキー場の大きな掲示板の地図（2026-11-12 代表「倶知安も天下森も地図欲しいね、デカい掲示板の」「実際のコースも書いてほしい」）。

  python3.11 -I tenkamori/draw_trail_map.py <場所>        （場所 = tenkamori | asahigaoka。作業場所の直下から）

焼いた表（game/<場所>/near.bin・forest.bin・map.json）から、紙に布と糸で作った地図を描き、game/<場所>/trail_map.png に書く。
ゲームの掲示板（game/site_map_board.gd）がこの絵を貼り、同じ向き・縮尺の値（trail_map.json）で、いまいる人のまち針を刺す。

描き方（文字は使わない。色と絵で読む）:
  - 上 = 山の上（リフトの乗り場から降り場の向き）。掲示板の前に立って山を見上げたときと同じ向き
  - 地面: 生成りの紙に、低い陽で照らした起伏の陰影を薄く。開けた雪面は白いフェルト、林は木の粒（旭ヶ丘は葉の落ちた木の茶とシラカバの白、天下森は杉の濃い緑）
  - コース: 太い色の糸のなみ縫いと、下る向きの矢じり。緑 = 初級、赤 = 中級、黒 = 上級。そりコースは桃色の布、クロスカントリーは青い点線
  - リフト: 濃い糸と柱の点、乗り場・降り場の四角。休憩所は家の絵、駐車場は灰の布、道は灰の糸
  - 目印: 旭ヶ丘のジャンプ台の櫓、羊蹄山の方角（縁に小さな山の絵）
  - いま、ここ: 掲示板の立つ所に赤いボタン
"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SITE = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
G = os.path.join(HERE, "..", "game", SITE)
M = json.load(open(os.path.join(G, "map.json")))
NEAR = {"tenkamori": (-650.0, -150.0), "asahigaoka": (-600.0, -650.0)}[SITE]
N = 513
H = np.fromfile(os.path.join(G, "near.bin"), dtype=np.float32).reshape(N, N).astype(float)
F = np.fromfile(os.path.join(G, "forest.bin"), dtype=np.uint8).reshape(256, 256).astype(float) / 255.0
C = np.fromfile(os.path.join(G, "clear.bin"), dtype=np.uint8).reshape(256, 256)
W, HH = 2400, 1600            # 絵の大きさ（掲示板 9 × 6 m）
# 掲示板の立つ所 (x, z)。表は山を見上げる人の側（下る向き）へ向く。旭ヶ丘は休憩所とリフトの乗り場のあいだ、天下森はヒュッテとリフトの乗り場のあいだ
BOARD = {"asahigaoka": [55.0, 20.0], "tenkamori": [10.0, 25.0]}[SITE]
MARGIN = 0.10                 # 縁の余白（絵の幅に対する割合）

PAPER = (241, 232, 214)
SNOW = (250, 250, 252)
THREAD = (52, 60, 98)
RED = (196, 56, 46)
GREEN = (64, 140, 76)
BLACK = (40, 38, 40)
PINK = (236, 128, 160)
BLUE = (70, 120, 200)
GREY = (150, 148, 150)
WOOD = (122, 84, 54)


def height(x, z):
    i = np.clip((np.asarray(x) - NEAR[0]) / 2.0, 0, N - 1.001)
    j = np.clip((np.asarray(z) - NEAR[1]) / 2.0, 0, N - 1.001)
    i0, j0 = i.astype(int), j.astype(int)
    a, b = i - i0, j - j0
    return H[j0, i0] * (1 - a) * (1 - b) + H[j0, i0 + 1] * a * (1 - b) + H[j0 + 1, i0] * (1 - a) * b + H[j0 + 1, i0 + 1] * a * b


def forest(x, z):
    i = np.clip(((np.asarray(x) - NEAR[0]) / 4.0).astype(int), 0, 255)
    j = np.clip(((np.asarray(z) - NEAR[1]) / 4.0).astype(int), 0, 255)
    return F[j, i] * (C[j, i] > 0)


# ---- 向きと範囲 ----------------------------------------------------------------------------
lift = np.array(M["lifts"][0]["line"], float)
UP = (lift[-1] - lift[0]) / np.linalg.norm(lift[-1] - lift[0])   # 絵の上
RIGHT = np.array([-UP[1], UP[0]])   # 絵の右 = 山を見上げたときの右手（x 東・z 南の座標で、北を向けば東が右）
pts = [p for l in M["lifts"] for p in l["line"]]
for p in M["pistes"]:
    if p.get("kind", "downhill") == "downhill" or p.get("level"):
        pts += p["line"]
pts += M.get("course2", [])
pts.append(BOARD)
for key in ("lodge", "hutte"):
    if M.get(key):
        pts += M[key]
if M.get("hutte_rect"):
    pts.append(M["hutte_rect"]["center"])
P = np.array(pts, float)
u = P @ RIGHT
v = P @ UP
cu, cv = (u.min() + u.max()) / 2, (v.min() + v.max()) / 2
span_u, span_v = u.max() - u.min(), v.max() - v.min()
SCALE = min(W * (1 - 2 * MARGIN) / span_u, HH * (1 - 2 * MARGIN) / span_v)   # 1 m の画素
ORIGIN = np.array([cu, cv])


def to_px(x, z):
    p = np.array([x, z], float)
    uu = p @ RIGHT - ORIGIN[0]
    vv = p @ UP - ORIGIN[1]
    return (W / 2 + uu * SCALE, HH / 2 - vv * SCALE)


def to_world(px, py):
    uu = (px - W / 2) / SCALE + ORIGIN[0]
    vv = -(py - HH / 2) / SCALE + ORIGIN[1]
    return RIGHT * uu + UP * vv


# ---- 地面 --------------------------------------------------------------------------------
def ground():
    ys, xs = np.mgrid[0:HH:2, 0:W:2].astype(float)
    wx = RIGHT[0] * ((xs - W / 2) / SCALE + ORIGIN[0]) + UP[0] * (-(ys - HH / 2) / SCALE + ORIGIN[1])
    wz = RIGHT[1] * ((xs - W / 2) / SCALE + ORIGIN[0]) + UP[1] * (-(ys - HH / 2) / SCALE + ORIGIN[1])
    h = height(wx, wz)
    e = 1.5
    gx = (height(wx + e, wz) - height(wx - e, wz)) / (2 * e)
    gz = (height(wx, wz + e) - height(wx, wz - e)) / (2 * e)
    # 低い陽（絵の左上から）で照らす
    sun = -RIGHT * 0.7 + UP * 0.7
    lx, lz = sun / np.linalg.norm(sun) * math.cos(math.radians(35))
    ly = math.sin(math.radians(35))
    n = np.stack([-gx, np.ones_like(gx), -gz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    light = np.clip(n[..., 0] * lx + n[..., 1] * ly + n[..., 2] * lz, 0, 1)
    shade = 0.78 + 0.32 * light
    fo = forest(wx, wz)
    base = np.array(SNOW, float) * (1 - fo[..., None] * 0.55) + np.array(PAPER, float) * fo[..., None] * 0.55
    img = np.clip(base * shade[..., None], 0, 255).astype(np.uint8)
    im = Image.fromarray(img).resize((W, HH), Image.BICUBIC)
    # 紙の繊維のむら
    rnd = np.random.default_rng(3)
    grain = (rnd.normal(0, 5, (HH // 4, W // 4))).astype(np.float32)
    g = Image.fromarray(np.clip(grain + 128, 0, 255).astype(np.uint8)).resize((W, HH), Image.BICUBIC).filter(ImageFilter.GaussianBlur(1.2))
    a = np.asarray(im).astype(float) + (np.asarray(g).astype(float) - 128)[..., None] * 0.8
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), h


def trees(d):
    """林の木の粒: 林の濃さに合わせて点を打つ（旭ヶ丘は茶の雑木とシラカバの白、天下森は杉の濃い緑の三角）"""
    rnd = np.random.default_rng(11)
    step = 9.0
    for py in np.arange(step, HH - step, step):
        for px in np.arange(step, W - step, step):
            jx, jy = px + rnd.uniform(-3, 3), py + rnd.uniform(-3, 3)
            w = to_world(jx, jy)
            if rnd.random() > forest(w[0], w[1]) * 1.05:
                continue
            r = rnd.uniform(4.0, 6.5)
            if SITE == "tenkamori":
                col = (46 + rnd.integers(0, 18), 78 + rnd.integers(0, 20), 70 + rnd.integers(0, 16))
                d.polygon([(jx, jy - r * 1.6), (jx - r, jy + r * 0.8), (jx + r, jy + r * 0.8)], fill=col)
            else:
                k = rnd.random()
                if k < 0.18:   # シラカバ: 白い幹に黒い点
                    d.ellipse([jx - r * 0.55, jy - r * 1.2, jx + r * 0.55, jy + r * 0.9], fill=(236, 232, 224), outline=(120, 110, 100))
                elif k < 0.22:   # 少しの針葉樹
                    d.polygon([(jx, jy - r * 1.6), (jx - r, jy + r * 0.8), (jx + r, jy + r * 0.8)], fill=(58, 98, 80))
                else:   # 葉の落ちた木: 茶の毛糸の玉
                    c = (120 + rnd.integers(-14, 14), 92 + rnd.integers(-12, 12), 72 + rnd.integers(-10, 10))
                    d.ellipse([jx - r, jy - r, jx + r, jy + r], fill=c)


# ---- 糸と布 ------------------------------------------------------------------------------
def stitch(d, line, col, w, dash=26, gap=14, under=None):
    """なみ縫いの糸: 太い色の破線。under があれば下に薄い影"""
    q = [to_px(*p) for p in line]
    seg = []
    for k in range(len(q) - 1):
        a, b = np.array(q[k]), np.array(q[k + 1])
        L = np.linalg.norm(b - a)
        n = max(1, int(L / (dash + gap)))
        for i in range(n):
            s0 = a + (b - a) * (i / n)
            s1 = a + (b - a) * min(1.0, (i / n) + dash / max(L, 1e-6))
            seg.append((tuple(s0), tuple(s1)))
    for s0, s1 in seg:
        if under:
            d.line([(s0[0] + 3, s0[1] + 4), (s1[0] + 3, s1[1] + 4)], fill=under, width=w)
    for s0, s1 in seg:
        d.line([s0, s1], fill=col, width=w)
        for e in (s0, s1):
            d.ellipse([e[0] - w / 2, e[1] - w / 2, e[0] + w / 2, e[1] + w / 2], fill=col)


def arrows(d, line, col, every=170, size=30):
    """下る向きの矢じり（糸で縫った V）"""
    q = [np.array(to_px(*p)) for p in line]
    acc = every * 0.6
    for k in range(len(q) - 1):
        a, b = q[k], q[k + 1]
        L = np.linalg.norm(b - a)
        if L < 1:
            continue
        t = (b - a) / L
        n_ = np.array([-t[1], t[0]])
        s = acc
        while s < L:
            c = a + t * s
            d.line([tuple(c - t * size + n_ * size * 0.7), tuple(c), tuple(c - t * size - n_ * size * 0.7)], fill=col, width=12, joint="curve")
            s += every
        acc = s - L


def patch(d, poly, fill, rim=None, w=5):
    q = [to_px(*p) for p in poly]
    d.polygon([(x + 4, y + 5) for x, y in q], fill=(0, 0, 0, 40))
    d.polygon(q, fill=fill)
    if rim:
        stitch(d, list(poly) + [poly[0]], rim, w, dash=14, gap=10)


def house(d, at, s, roof=THREAD, wall=(214, 186, 150)):
    x, y = at
    d.rectangle([x - s, y - s * 0.6, x + s, y + s * 0.9], fill=wall, outline=(90, 70, 50), width=3)
    d.polygon([(x - s * 1.35, y - s * 0.5), (x + s * 1.35, y - s * 0.5), (x, y - s * 1.6)], fill=roof)
    d.rectangle([x - s * 0.25, y + s * 0.2, x + s * 0.25, y + s * 0.9], fill=(250, 200, 110))


def tower_icon(d, at, s):
    x, y = at
    for dx in (-s * 0.5, s * 0.5):
        d.line([(x + dx, y + s), (x + dx * 0.6, y - s * 1.2)], fill=(110, 52, 40), width=6)
    for k in range(3):
        yy = y + s - k * s * 0.7
        d.line([(x - s * 0.5, yy), (x + s * 0.5, yy - s * 0.6)], fill=(110, 52, 40), width=4)
    d.rectangle([x - s * 0.55, y - s * 1.6, x + s * 0.55, y - s * 1.1], fill=(110, 52, 40))


def mountain_icon(d, at, s):
    x, y = at
    d.polygon([(x - s * 1.6, y + s * 0.6), (x, y - s), (x + s * 1.6, y + s * 0.6)], fill=(150, 170, 205))
    d.polygon([(x - s * 0.55, y - s * 0.35), (x, y - s), (x + s * 0.55, y - s * 0.35), (x + s * 0.2, y - s * 0.2), (x - s * 0.2, y - s * 0.3)], fill=(250, 250, 252))


def sled_icon(d, at, s, col=PINK):
    x, y = at
    d.rounded_rectangle([x - s, y - s * 0.35, x + s, y + s * 0.15], radius=s * 0.2, fill=col)
    d.line([(x - s * 1.1, y + s * 0.45), (x + s * 0.9, y + s * 0.45), (x + s * 1.25, y + s * 0.1)], fill=(110, 80, 60), width=6)


def main():
    im, _ = ground()
    d = ImageDraw.Draw(im, "RGBA")
    # 道と駐車場
    for r in M.get("roads", []):
        q = [to_px(*p) for p in r["line"]]
        d.line(q, fill=(176, 174, 176), width=int(max(8, {"primary": 8, "secondary": 7, "tertiary": 6}.get(r["kind"], 4.5) * SCALE)), joint="curve")
    for pk in M.get("parking", []):
        patch(d, pk, (186, 184, 188))
    trees(d)
    # コース
    if SITE == "asahigaoka":
        # クロスカントリー（OSM の nordic）: 青い点線
        for p in M["pistes"]:
            if p.get("kind") == "nordic":
                stitch(d, p["line"], BLUE, 7, dash=12, gap=14)
        # そりコース: 南の斜面（オレンジのネットの南）の桃色の布
        sled = [[22, 58], [-10, 60], [-42, 63], [-72, 67], [-110, 74], [-120, 96], [-70, 104], [-20, 100], [30, 88], [40, 70]]
        patch(d, sled, (246, 196, 210, 210), rim=PINK, w=6)
        sled_icon(d, to_px(-40, 84), 34)
        # 初級（緑）: 降り場から林の島の西を回って麓へ
        green = M["course2"] + [[-150, 50], [-90, 44], [-40, 34], [0, 20]]
        stitch(d, green, GREEN, 22, dash=34, gap=16, under=(0, 0, 0, 50))
        arrows(d, green, GREEN)
        # 中級（赤）: 主コース。リフトの北東を降り場の脇から乗り場へ
        top, bot = lift[-1], lift[0]
        ne = np.array([-UP[1], UP[0]])   # リフトの線の北東の側（主コースの側）
        if ne[0] - ne[1] < 0:
            ne = -ne
        red = [top + (bot - top) * t + ne * off for t, off in ((0.06, 18.0), (0.3, 40.0), (0.62, 45.0), (0.9, 32.0), (1.0, 20.0))]
        red = [list(p) for p in red]
        stitch(d, red, RED, 22, dash=34, gap=16, under=(0, 0, 0, 50))
        arrows(d, red, RED)
    else:
        col = {"easy": GREEN, "intermediate": RED, "advanced": BLACK}
        for p in M["pistes"]:
            line = p["line"]
            c = col.get(p.get("level", ""), RED)
            stitch(d, line, c, 22, dash=34, gap=16, under=(0, 0, 0, 50))
            arrows(d, line, c)
    # リフト: 濃い糸と柱の点、乗り場と降り場
    for l in M["lifts"]:
        q = [to_px(*p) for p in l["line"]]
        d.line(q, fill=(40, 40, 46), width=6)
        for p in q[1:-1]:
            d.ellipse([p[0] - 7, p[1] - 7, p[0] + 7, p[1] + 7], fill=(110, 52, 40) if SITE == "asahigaoka" else (120, 124, 128))
        for p in (q[0], q[-1]):
            d.rectangle([p[0] - 16, p[1] - 16, p[0] + 16, p[1] + 16], fill=(70, 60, 56), outline=(250, 250, 252), width=4)
    # 休憩所・ヒュッテ
    if M.get("lodge"):
        c = np.mean(M["lodge"], axis=0)
        house(d, to_px(*c), 36)
    if M.get("hutte_rect"):
        house(d, to_px(*M["hutte_rect"]["center"]), 40, roof=(130, 134, 140), wall=(70, 58, 52))
    if SITE == "asahigaoka":
        tower_icon(d, to_px(-222, -215), 26)
        # 羊蹄山の方角（絵の縁の内側に、小さな山）
        yotei = np.array([6100.0, 8400.0])
        c = np.array(to_px(*(lift[0] + (lift[-1] - lift[0]) * 0.5)))
        dirp = np.array(to_px(*yotei)) - c
        dirp /= np.linalg.norm(dirp)
        t = min((W / 2 - 110) / max(abs(dirp[0]), 1e-6), (HH / 2 - 110) / max(abs(dirp[1]), 1e-6))
        mountain_icon(d, tuple(np.array([W / 2, HH / 2]) + dirp * t), 50)
    # いま、ここ: 掲示板の立つ所に赤いボタン
    b = BOARD
    if b:
        x, y = to_px(b[0], b[1])
        d.ellipse([x - 26, y - 26, x + 26, y + 26], fill=(250, 250, 252))
        d.ellipse([x - 20, y - 20, x + 20, y + 20], fill=RED)
        for dx, dy in ((-6, -6), (6, -6), (-6, 6), (6, 6)):
            d.ellipse([x + dx - 3, y + dy - 3, x + dx + 3, y + dy + 3], fill=(250, 250, 252))
    # 縁: 糸のなみ縫い
    e = 30
    for a, bb in (((e, e), (W - e, e)), ((W - e, e), (W - e, HH - e)), ((W - e, HH - e), (e, HH - e)), ((e, HH - e), (e, e))):
        n = int(math.dist(a, bb) / 40)
        for i in range(n):
            s0 = np.array(a) + (np.array(bb) - np.array(a)) * i / n
            s1 = np.array(a) + (np.array(bb) - np.array(a)) * (i + 0.6) / n
            d.line([tuple(s0), tuple(s1)], fill=THREAD, width=7)
    im.save(os.path.join(G, "trail_map.png"))
    json.dump({"right": RIGHT.round(6).tolist(), "up": UP.round(6).tolist(), "origin": ORIGIN.round(3).tolist(), "scale": round(SCALE, 6),
               "size": [W, HH], "board": BOARD}, open(os.path.join(G, "trail_map.json"), "w"), indent=1)
    print(os.path.join(G, "trail_map.png"), "1 m =", round(SCALE, 3), "px")


if __name__ == "__main__":
    main()
