"""旭ヶ丘のゲレンデの見取り図（2026-11-11）。空中写真にリフト・コース・休憩所と、動画で見たものの印を重ね、右に動画のコマを並べる。

  python3.11 -I draw_slope_map.py <空中写真のタイルのフォルダ> <動画のコマのフォルダ> <書き出す png>

動画のコマは ~/research/asahigaoka/sources/video/（目録は ~/research/asahigaoka/map.md）。
印の場所は、空中写真で見える物（リフトの柱・ジャンプ台・休憩所・駐車場）は写真から、見えない物（照明の柱・ネット・小さな台）は動画の見え方から見積もった（「約」）。
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageEnhance

TILES, FRAMES, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
HERE = os.path.dirname(os.path.abspath(__file__))
M = json.load(open(os.path.join(HERE, "..", "game", "asahigaoka", "map.json")))
LAT0, LON0 = 42.9018597, 140.7372343
MY = 111132.954 - 559.822 * math.cos(2 * math.radians(LAT0)); MX = 111412.84 * math.cos(math.radians(LAT0))
X0, X1, Z0, Z1 = -400, 200, -320, 150   # 遊びの座標（x 東、z 南）
SCALE = 3.4                               # 写真の 1 px を何倍に
FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc"
BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"

# 印: [番号, x, z, 色, 見出し, 説明]
RED, ORANGE, BLUE, GREEN, BROWN, GREY = (200, 40, 40), (235, 120, 20), (40, 90, 200), (30, 130, 70), (120, 70, 40), (70, 70, 80)
MARKS = [
    [1, 0, 0, BROWN, "リフト乗り場", "赤茶の鉄骨の台に横倒しの大きな滑車と小さな屋根。ゲレンデの側に濃い茶の板張りの小屋（運転室・横長の窓）。手前に「待機位置」の札"],
    [2, -125, -99, BROWN, "リフトの柱 7 本", "赤茶の丸い鉄の柱に灰の腕木。椅子は 2 人掛け・灰のパイプに黒い座面・安全バーなし（柱の所は OSM の点。写真の影と合う）"],
    [3, -267, -211, BROWN, "降り場", "柱 1 本と滑車、雪の台。脇に小さな木の小屋"],
    [4, -222, -215, RED, "ジャンプ台の櫓（使っていない）", "赤茶の鉄骨の櫓。降り場のすぐ東。羊蹄山と並んで見える目印（空中写真にも赤茶の骨組み）"],
    [5, -134, -186, RED, "小さな台と審判の櫓（約）", "主コースの北東の縁に、雪をかぶった小さなジャンプ台と、赤茶の小さな櫓 2 つ（下から見上げた写真）"],
    [6, -95, -60, ORANGE, "オレンジのネット", "リフトの線とコースのあいだに、柱の列に沿って。降り場の縁と、コースの上の縁にも"],
    [7, -70, -105, GREY, "ナイターの照明の柱（約）", "灰の細い鉄の柱の先に丸い投光器 4〜6 個。主コースの両脇に 4〜5 本ずつ、細いコースにも"],
    [8, -150, -150, BLUE, "主コース（最大 30 度）", "リフトの北東の側。幅 60〜90 m、まっすぐ。上から正面に羊蹄山、手前に倶知安の町"],
    [9, -262, -100, BLUE, "初級コース（最長 560 m）", "降り場から、林の島の西の切り開き（幅 26〜44 m）を下り、麓へ下りる道に出る"],
    [10, -80, 70, GREEN, "そりコース", "麓へ下りる道の南の、北向きの斜面。主コースとこの斜面が、林の島の先をはさんで V 字の谷になる（ロッジから見た形）。オレンジのネットとピンクの旗のポールで仕切る"],
    [11, 108, 26, RED, "休憩所「雪ん子館」", "平屋・片側へ長く下る大きな屋根。ゲレンデの側（西）が正面で、白い庇の入口と券売所、木のデッキ（図面は 03-lodge-plans.png）"],
    [12, 112, 90, GREY, "駐車場", "休憩所の南。東と南に、雪を厚くかぶった針葉樹の列"],
    [13, -190, -265, GREEN, "林", "斜面の両脇は葉の落ちた林（カラマツの細い幹・雑木）。コースの縁にシラカバの白い幹の壁。常緑の針葉樹は少ない"],
]
FRAME_FILES = [
    ("hsakudo", "../img/hsakudo-011-3-slope-lift-bottom-jump-tower.jpg", "下から: 上に櫓 ④、右に台 ⑤"),
    ("dzk-405", "dzk-405-E-slope-down-town-yotei.jpg", "上から: 羊蹄山と町 ⑧"),
    ("tokyu-75", "tokyu-75-C-bottom-station-hut-bullwheel.jpg", "乗り場の滑車と小屋 ①"),
    ("dzk-340", "dzk-340-D-pillar-crossarm-chair.jpg", "柱・椅子・オレンジのネット ②⑥"),
    ("dzk-380", "dzk-380-C-top-jumptower-pillar-yotei.jpg", "降り場の脇の櫓 ③④"),
    ("tokyu-118", "tokyu-118-E-aerial-course2.jpg", "細いコース ⑨"),
    ("tokyu-133", "tokyu-133-A-lodge-front-closeup-canopy.jpg", "雪ん子館の正面 ⑪"),
    ("intro-35", "intro-35-E-slope-up-from-bottom.jpg", "下の広場の仕切り ⑩"),
    ("dzk-160", "dzk-160-F-birch-wall-yotei.jpg", "シラカバの壁 ⑬"),
]


def px(x, z, n=2 ** 17):
    lat, lon = LAT0 - z / MY, LON0 + x / MX
    return (lon + 180) / 360 * n * 256, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n * 256


def aerial():
    x0, y0 = px(X0, Z0)
    x1, y1 = px(X1, Z1)
    tx0, ty0, tx1, ty1 = int(x0 // 256), int(y0 // 256), int(x1 // 256), int(y1 // 256)
    W = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            for p in (f"{TILES}/seamlessphoto_17_{tx}_{ty}.jpg", f"{HERE}/photo/17_{tx}_{ty}.jpg"):
                if os.path.exists(p):
                    W.paste(Image.open(p).convert("RGB"), ((tx - tx0) * 256, (ty - ty0) * 256))
                    break
    c = W.crop((int(x0 - tx0 * 256), int(y0 - ty0 * 256), int(x1 - tx0 * 256), int(y1 - ty0 * 256)))
    c = c.resize((int(c.width * SCALE), int(c.height * SCALE)), Image.LANCZOS)
    c = ImageEnhance.Color(c).enhance(0.55)
    return Image.blend(c, Image.new("RGB", c.size, (255, 255, 255)), 0.38), x0, y0


def main():
    base, x0, y0 = aerial()
    d = ImageDraw.Draw(base)
    f_s, f_m, f_b = ImageFont.truetype(FONT, 20), ImageFont.truetype(FONT, 24), ImageFont.truetype(BOLD, 30)

    def P(x, z):
        a, b = px(x, z)
        return ((a - x0) * SCALE, (b - y0) * SCALE)

    def line(pts, col, w, dash=0):
        q = [P(*p) for p in pts]
        if not dash:
            d.line(q, fill=col, width=w, joint="curve")
            return
        for k in range(len(q) - 1):
            (ax, ay), (bx, by) = q[k], q[k + 1]
            n = max(1, int(math.hypot(bx - ax, by - ay) / dash))
            for i in range(0, n, 2):
                d.line([(ax + (bx - ax) * i / n, ay + (by - ay) * i / n), (ax + (bx - ax) * (i + 1) / n, ay + (by - ay) * (i + 1) / n)], fill=col, width=w)

    line(M["area"], (60, 90, 200), 3, 14)
    for p in M["pistes"]:
        if p["kind"] == "downhill":
            line(p["line"], BLUE, 7)
    L = M["lifts"][0]["line"]
    line(L, BROWN, 6)
    for i, p in enumerate(L):
        a, b = P(*p)
        r = 11 if i in (0, len(L) - 1) else 7
        d.ellipse([a - r, b - r, a + r, b + r], fill=BROWN, outline=(255, 255, 255), width=2)
    # オレンジのネット: リフトの線の北東 9 m に沿って（乗り場の上から降り場の下まで）
    ux, uz = L[-1][0] - L[0][0], L[-1][1] - L[0][1]
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    sx, sz = -uz, ux
    if sx - sz < 0:
        sx, sz = -sx, -sz
    line([[L[0][0] + ux * 25 + sx * 9, L[0][1] + uz * 25 + sz * 9], [L[-1][0] - ux * 20 + sx * 9, L[-1][1] - uz * 20 + sz * 9]], ORANGE, 3, 10)
    # ナイターの照明の柱（約）: 主コースの両脇
    for t in (0.12, 0.32, 0.52, 0.72, 0.9):
        for off in (16.0, 78.0 - 22.0 * t):
            a, b = P(L[0][0] + ux * n * t + sx * off, L[0][1] + uz * n * t + sz * off)
            d.regular_polygon((a, b, 8), 4, rotation=45, fill=(250, 220, 60), outline=GREY)
    line(M["lodge"], RED, 5)
    for pk in M["parking"]:
        line(pk + [pk[0]], GREY, 2, 8)
    # 羊蹄山・町の向き
    a, b = P(120, -250)
    for ang, lab in ((144, "羊蹄山 10.4 km"), (95, "倶知安の町"), (235, "ニセコアンヌプリ 9.6 km")):
        r = math.radians(ang)
        ex, ey = a + math.sin(r) * 150, b - math.cos(r) * 150
        d.line([(a, b), (ex, ey)], fill=(20, 20, 20), width=4)
        d.ellipse([ex - 7, ey - 7, ex + 7, ey + 7], fill=(20, 20, 20))
        d.text((ex + 10 if ang < 180 else ex - 20 - d.textlength(lab, font=f_m), ey - 12), lab, fill=(20, 20, 20), font=f_m, stroke_width=3, stroke_fill=(255, 255, 255))
    # 北と縮尺
    a, b = P(-380, 120)
    d.line([(a, b), (a + 100 * SCALE / 0.875, b)], fill=(0, 0, 0), width=5)
    d.text((a, b - 34), "100 m　上が北", fill=(0, 0, 0), font=f_m, stroke_width=3, stroke_fill=(255, 255, 255))
    for num, x, z, col, _h, _t in MARKS:
        a, b = P(x, z)
        if num in (1, 3, 2):
            a, b = a - 34, b + 30
        d.ellipse([a - 22, b - 22, a + 22, b + 22], fill=col, outline=(255, 255, 255), width=3)
        s = str(num)
        d.text((a - d.textlength(s, font=f_b) / 2, b - 17), s, fill=(255, 255, 255), font=f_b)

    # 右: 説明と動画のコマ
    FW, FH = 400, 225
    side_w = FW * 3 + 80
    out = Image.new("RGB", (base.width + side_w, max(base.height, 1640)), (250, 249, 246))
    out.paste(base, (0, 0))
    d = ImageDraw.Draw(out)
    x = base.width + 30
    y = 24
    d.text((x, y), "旭ヶ丘スキー場 ゲレンデの見取り図（2026-11-11）", fill=(20, 20, 20), font=f_b)
    y += 52
    d.text((x, y), "茶の線 = ペアリフト（丸は柱）、青の線 = 細いコース、橙の破線 = ネット、黄の印 = 照明の柱（約）、赤の囲い = 休憩所", fill=(60, 60, 60), font=f_s)
    y += 40
    for num, _x, _z, col, head, text in MARKS:
        d.ellipse([x, y, x + 34, y + 34], fill=col)
        s = str(num)
        d.text((x + 17 - d.textlength(s, font=f_m) / 2, y + 4), s, fill=(255, 255, 255), font=f_m)
        d.text((x + 46, y + 2), head, fill=(20, 20, 20), font=ImageFont.truetype(BOLD, 22))
        y += 34
        row = ""
        for ch in text:
            if d.textlength(row + ch, font=f_s) > side_w - 110:
                d.text((x + 46, y), row, fill=(70, 70, 70), font=f_s)
                y += 26
                row = ""
            row += ch
        d.text((x + 46, y), row, fill=(70, 70, 70), font=f_s)
        y += 34
    y += 6
    for k, (_n, f, cap) in enumerate(FRAME_FILES):
        im = Image.open(os.path.join(FRAMES, f)).convert("RGB")
        im.thumbnail((FW, FH))
        fx, fy = x + (k % 3) * (FW + 10), y + (k // 3) * (FH + 34)
        out.paste(im, (fx, fy))
        d.text((fx, fy + FH + 4), cap, fill=(40, 40, 40), font=f_s)
    out = out.crop((0, 0, out.width, max(base.height, y + 3 * (FH + 34) + 10)))
    out.save(OUT)
    print(OUT, out.size)


if __name__ == "__main__":
    main()
