"""天下森のゲレンデの見取り図（2026-11-09）。航空写真にコース・リフト・ヒュッテと、動画で見たものの印を重ね、右に動画のコマを並べる。

  python draw_slope_map.py <空中写真のタイルのフォルダ> <動画のコマのフォルダ> <書き出す png>

動画のコマ（3×3 に並べた 800×450 の絵）は ~/research/natsumushi-hutte/sources/video/。印の場所は動画の流れから見積もった（「約」）。
"""
import json, math, os, sys, textwrap, urllib.request
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle
from PIL import Image
import numpy as np
plt.rcParams["font.family"] = "Hiragino Sans"

TILES, FRAMES, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
HERE = os.path.dirname(os.path.abspath(__file__))
M = json.load(open(os.path.join(HERE, "..", "game", "tenkamori", "map.json")))
LAT0, LON0 = 39.1623465, 140.6208507
MY = 111132.954 - 559.822 * math.cos(2 * math.radians(LAT0)); MX = 111412.84 * math.cos(math.radians(LAT0))
X0, X1, Z0, Z1 = -560, 160, -120, 760   # 遊びの座標（x 東、z 南）


def aerial():
    z = 18; n = 2 ** z
    def px(lat, lon):
        return (lon + 180) / 360 * n * 256, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n * 256
    x0, y0 = px(LAT0 - Z0 / MY, LON0 + X0 / MX)
    x1, y1 = px(LAT0 - Z1 / MY, LON0 + X1 / MX)
    tx0, ty0, tx1, ty1 = int(x0 // 256), int(y0 // 256), int(x1 // 256), int(y1 // 256)
    W = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            p = f"{TILES}/sp_{z}_{tx}_{ty}.jpg"
            if not os.path.exists(p):
                req = urllib.request.Request(f"https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{tx}/{ty}.jpg", headers={"User-Agent": "lodge-terrain-check"})
                try:
                    open(p, "wb").write(urllib.request.urlopen(req, timeout=30).read())
                except Exception:
                    continue
            W.paste(Image.open(p), ((tx - tx0) * 256, (ty - ty0) * 256))
    return W.crop((int(x0 - tx0 * 256), int(y0 - ty0 * 256), int(x1 - tx0 * 256), int(y1 - ty0 * 256)))


def along(line, f):
    P = np.array(line, float)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    cum = np.r_[0, np.cumsum(seg)]
    s = f * cum[-1]
    k = min(np.searchsorted(cum, s) - 1, len(seg) - 1)
    k = max(k, 0)
    t = (s - cum[k]) / max(seg[k], 1e-6)
    return P[k] + (P[k + 1] - P[k]) * t


def tile(path, k):
    """3×3 に並べた 800×450 の絵から k 番目のコマ"""
    im = Image.open(path).convert("RGB")
    w, h = im.size[0] / 3, im.size[1] / 3
    return im.crop((int((k % 3) * w), int((k // 3) * h), int((k % 3 + 1) * w), int((k // 3 + 1) * h)))


pist = {(p["name"], p["level"]): p["line"] for p in M["pistes"]}
lift = [l for l in M["lifts"] if l["kind"] == "chair_lift"][0]["line"]
rope = [l for l in M["lifts"] if l["kind"] == "rope_tow"][0]["line"]
main_c = pist[("天下森コース", "easy")]
rinkan = [p["line"] for p in M["pistes"] if p["name"] == "夏虫沢林間コース"]
rinkan_full = rinkan[0] + rinkan[1][1:] if len(rinkan) > 1 else rinkan[0]
adv = pist.get(("", "advanced"))

V = FRAMES
# 印: [番号, 場所（遊びの座標）, 見出し, 説明, (コマの絵, 番号)]
marks = [
    [1, along(lift, 0.02), "乗り場", "ペアリフトの乗り場。ヒュッテと駐車場のすぐ脇", (f"{V}/v1-lift-195-371.png", 0)],
    [2, along(lift, 0.45), "リフトから谷の向かいの山", "乗っているあいだ、谷の向かいの雪をかぶった山なみがずっと見える。柱は灰の鉄の筒に梯子", (f"{V}/v1-lift-195-371.png", 4)],
    [3, along(lift, 0.97), "降り場", "頂上の降り場。柱に案内の札", (f"{V}/v1-lift-195-371.png", 7)],
    [4, along(rinkan_full, 0.12), "夏虫沢林間コース 上", "幅 8〜10 m の林の中の道。谷の側に雪の壁（高さ 1 m ほど）、両側に杉", (f"{V}/v1-natsumushi-375-535.png", 1)],
    [5, along(rinkan_full, 0.35), "林間コースの曲がり", "雪の壁に沿って大きく曲がる。外の側が盛り上がる", (f"{V}/v1-natsumushi-375-535.png", 3)],
    [6, along(rinkan_full, 0.6), "視界が開ける", "林が切れて、谷の向かいの雪の山が正面に見える", (f"{V}/v1-natsumushi-375-535.png", 4)],
    [7, along(rinkan_full, 0.85), "ゲレンデへの合流", "林間コースがゲレンデへ出る所。縁にオレンジの安全ネット", (f"{V}/v1-natsumushi-375-535.png", 6)],
    [8, along(main_c, 0.3), "天下森ゲレンデの肩", "広い一枚の斜面。肩から急に落ちる所がある。圧雪の筋", (f"{V}/v1-tengamori-555-755.png", 2)],
    [9, along(main_c, 0.55), "リフト沿い", "左にリフトの柱とナイターの照明の柱。柱のまわりに赤いネット", (f"{V}/v1-tengamori-555-755.png", 4)],
    [10, along(main_c, 0.8), "下の斜面", "ゆるくなり、下にヒュッテとリフト乗り場が見える。縁に雪をかぶった小さな小屋（看板）", (f"{V}/v1-tengamori-555-755.png", 5)],
    [11, along(main_c, 0.95), "ふもと", "人が集まる平らな所。ヒュッテの前へ", (f"{V}/v1-tengamori-555-755.png", 8)],
]

fig = plt.figure(figsize=(26, 17), dpi=100)
fig.suptitle("天下森スキー場 ゲレンデの見取り図（案）　― 航空写真（国土地理院）に、OSM のコース・リフトと、代表がくれた動画で見たものの印。印の場所は動画の流れからの見積もり", fontsize=15, x=0.01, ha="left")
ax = fig.add_axes([0.01, 0.02, 0.44, 0.93])
img = aerial()
ax.imshow(img, extent=[X0, X1, Z1, Z0])
ax.set_xlim(X0, X1); ax.set_ylim(Z1, Z0); ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
def line(l, **k):
    P = np.array(l); ax.plot(P[:, 0], P[:, 1], **k)
line(main_c, color="#3fbf4f", lw=4, label="天下森コース（ゲレンデ）")
for r in rinkan:
    line(r, color="#3f7fff", lw=4)
ax.plot([], [], color="#3f7fff", lw=4, label="夏虫沢林間コース")
if adv:
    line(adv, color="#ff4040", lw=4, label="上級の区間")
line(lift, color="black", lw=2, ls="--", label="ペアリフト")
for k, p in enumerate(lift[1:-1]):
    ax.add_patch(Circle(p, 5, color="white", ec="black", zorder=5))
    ax.text(p[0] + 9, p[1], str(k + 1), fontsize=8, color="white", zorder=6, va="center")
line(rope, color="orange", lw=2, label="ロープトウ")
if M.get("hutte"):
    line(M["hutte"], color="#ffdd55", lw=2)
for poly in M.get("parking", []):
    line(poly, color="#cccccc", lw=1.5)
ax.text(70, 30, "ヒュッテ", color="#ffdd55", fontsize=11, fontweight="bold")
ax.text(40, -60, "駐車場", color="white", fontsize=10)
for n, p, title, _, _ in marks:
    ax.add_patch(Circle(p, 13, color="#d62828", ec="white", lw=2, zorder=8))
    ax.text(p[0], p[1], str(n), color="white", fontsize=11, fontweight="bold", ha="center", va="center", zorder=9)
ax.legend(loc="lower left", fontsize=10)
ax.text(X0 + 10, Z0 + 20, "↑ 北（谷の向かいの山はこの上の方）", color="white", fontsize=10)
ax.plot([X1 - 120, X1 - 20], [Z1 - 20, Z1 - 20], color="white", lw=4); ax.text(X1 - 70, Z1 - 32, "100 m", color="white", ha="center", fontsize=10)
# 右: コマ
cols = 3
for i, (n, p, title, desc, (path, k)) in enumerate(marks):
    r, c = divmod(i, cols)
    bx = 0.47 + c * 0.177
    by = 0.76 - r * 0.24
    a = fig.add_axes([bx, by, 0.17, 0.17 * 0.5625 * 26 / 17])
    a.imshow(tile(path, k)); a.set_xticks([]); a.set_yticks([])
    a.set_title(f"{n}. {title}", loc="left", fontsize=11, color="#d62828", fontweight="bold")
    fig.text(bx, by - 0.008, "\n".join(textwrap.wrap(desc, 26)), fontsize=9.5, va="top", linespacing=1.4)
fig.text(0.47 + 2 * 0.177, 0.17, "\n".join(textwrap.wrap("動画: 「天下森スキー場◆ヒュッテをリニューアルします！」（えすぺゆき）と「天下森スキー場に行って来ました」。コマは見て形を汲み取るだけで、ゲームには入れない。", 26) + [""] + textwrap.wrap("リフトの柱の番号は下から数えた仮の番号（2 本目の動画に「10」の札が映っている）。", 26)), fontsize=9.5, va="top", linespacing=1.4)
fig.savefig(OUT, dpi=100)
print("saved", OUT)
