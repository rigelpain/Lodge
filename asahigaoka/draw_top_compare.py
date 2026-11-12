"""旭ヶ丘を真上から見た比べの絵: 左 = 国土地理院の空中写真、右 = ゲームを真上から撮った絵（game/tools/asahi_views.gd の ortho。窓 1200x700）。
どちらも上が北、x -400〜200・z -245〜105（遊びの座標。1 m = 2 px）。赤 = リフトの線、桃 = 休憩所。

  python3.11 -I asahigaoka/draw_top_compare.py <空中写真のタイルのフォルダ> <ゲームの ortho.png> <書き出す jpg>
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont

TILES, GAME, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
HERE = os.path.dirname(os.path.abspath(__file__))
M = json.load(open(os.path.join(HERE, "..", "game", "asahigaoka", "map.json")))
LAT0, LON0 = 42.9018597, 140.7372343
MY = 111132.954 - 559.822 * math.cos(2 * math.radians(LAT0)); MX = 111412.84 * math.cos(math.radians(LAT0))
XA, ZA, XB, ZB = -400, -245, 200, 105
W, H = 1200, 700


def px(x, z, n=2 ** 17):
    lat, lon = LAT0 - z / MY, LON0 + x / MX
    return (lon + 180) / 360 * n * 256, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n * 256


def aerial():
    x0, y0 = px(XA, ZA)
    x1, y1 = px(XB, ZB)
    tx0, ty0, tx1, ty1 = int(x0 // 256), int(y0 // 256), int(x1 // 256), int(y1 // 256)
    big = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            for p in (f"{TILES}/seamlessphoto_17_{tx}_{ty}.jpg", f"{HERE}/photo/17_{tx}_{ty}.jpg"):
                if os.path.exists(p):
                    big.paste(Image.open(p).convert("RGB"), ((tx - tx0) * 256, (ty - ty0) * 256))
                    break
    return big.crop((int(x0 - tx0 * 256), int(y0 - ty0 * 256), int(x1 - tx0 * 256), int(y1 - ty0 * 256))).resize((W, H), Image.LANCZOS)


def P(x, z):
    return ((x - XA) / (XB - XA) * W, (z - ZA) / (ZB - ZA) * H)


def fit_game(path):
    """ゲームの絵の赤紫の玉 3 つ（(-350,-200)・(150,-200)・(-350,60)）を探し、x -400〜200・z -245〜105 の枠に合わせて写し直す"""
    import numpy as np
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(int)
    ys, xs = np.where((a[..., 0] - a[..., 1] > 90) & (a[..., 2] - a[..., 1] > 90))
    pts = np.stack([xs, ys], 1).astype(float)
    found = []
    while len(pts) > 12 and len(found) < 3:
        sel = np.hypot(pts[:, 0] - pts[0, 0], pts[:, 1] - pts[0, 1]) < 40
        if sel.sum() > 12:
            found.append(pts[sel].mean(0))
        pts = pts[~sel]
    if len(found) != 3:
        raise SystemExit("目印の玉が 3 つ見つからない: %s" % found)
    found.sort(key=lambda p: p[0] + 3 * p[1])   # 左上、右上、左下 の順
    tl, tr, bl = found
    kx = (tr[0] - tl[0]) / 500.0   # 1 m の px
    kz = (bl[1] - tl[1]) / 260.0
    x0 = tl[0] - (-350 - XA) * kx
    y0 = tl[1] - (-200 - ZA) * kz
    print("ゲームの絵: 1 m = %.3f × %.3f px、枠の左上 = (%.1f, %.1f)" % (kx, kz, x0, y0))
    box = (x0, y0, x0 + (XB - XA) * kx, y0 + (ZB - ZA) * kz)
    return im.transform((W, H), Image.EXTENT, box, Image.BICUBIC)


a = aerial()
g = fit_game(GAME)
f = ImageFont.truetype("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", 24)
for im, cap in ((a, "空中写真（国土地理院・夏）"), (g, "ゲームを真上から")):
    d = ImageDraw.Draw(im)
    d.line([P(*p) for p in M["lifts"][0]["line"]], fill=(230, 30, 30), width=3)
    d.line([P(*q) for q in M["lodge"]], fill=(255, 0, 255), width=3)
    d.text((14, 12), cap, fill=(255, 255, 255), font=f, stroke_width=3, stroke_fill=(0, 0, 0))
out = Image.new("RGB", (W * 2 + 10, H), (255, 255, 255))
out.paste(a, (0, 0))
out.paste(g, (W + 10, 0))
out.save(OUT, quality=88)
print(OUT, out.size)
