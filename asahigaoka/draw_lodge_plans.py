"""旭ヶ丘の休憩所「雪ん子館」の図面（平面・西の立面・南の立面）を、lodge_dims.py の寸法から描き、手本のコマを並べる（2026-11-11）。

  python3.11 -I draw_lodge_plans.py <動画のコマのフォルダ> <書き出す png>
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lodge_dims as D

FRAMES, OUT = sys.argv[1], sys.argv[2]
FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc"
BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"
S = 30.0   # 1 m を何 px に
f_s, f_m, f_b = ImageFont.truetype(FONT, 19), ImageFont.truetype(FONT, 23), ImageFont.truetype(BOLD, 30)
INK = (40, 40, 45)
C = D.COL


def roof_h(u):
    if u <= D.RIDGE_U:
        return D.EAVE_N_H + (D.RIDGE_H - D.EAVE_N_H) * u / D.RIDGE_U
    return D.EAVE_S_H + (D.RIDGE_H - D.EAVE_S_H) * (D.ROOF_U - u) / (D.ROOF_U - D.RIDGE_U)


def dim(d, a, b, text, off=(0, -26)):
    d.line([a, b], fill=(200, 60, 60), width=2)
    for p in (a, b):
        d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=(200, 60, 60))
    m = ((a[0] + b[0]) / 2 + off[0], (a[1] + b[1]) / 2 + off[1])
    d.text((m[0] - d.textlength(text, font=f_s) / 2, m[1]), text, fill=(200, 60, 60), font=f_s)


def west(d, ox, oy):
    """西の立面（ゲレンデの側から。左が北）。ox, oy = 屋根の北の端の地面"""
    P = lambda u, h: (ox + u * S, oy - h * S)
    d.line([P(-2, 0), P(D.ROOF_U + 2, 0)], fill=INK, width=3)
    # 低い灰の棟・大きな部屋
    d.rectangle([P(D.LOW_U[0], D.LOW_H), P(D.LOW_U[1], 0)], fill=C["panel"], outline=INK)
    for u in (8.0, 10.6):
        d.rectangle([P(u, 2.0), P(u + 1.2, 1.2)], fill=C["glass"], outline=INK)
    hall = [P(D.HALL_U[0], 0), P(D.HALL_U[0], roof_h(D.HALL_U[0]) - D.ROOF_T), P(D.RIDGE_U, D.RIDGE_H - D.ROOF_T),
            P(D.HALL_U[1], roof_h(D.HALL_U[1]) - D.ROOF_T), P(D.HALL_U[1], 0)]
    d.polygon(hall, fill=C["wood"], outline=INK)
    d.rectangle([P(D.HALL_U[0], D.PANEL_H), P(D.TALL_U[0], 0)], fill=C["panel"], outline=INK)
    u = D.HALL_U[0]
    while u < D.TALL_U[0]:   # 縦張りの板の目地
        d.line([P(u, D.PANEL_H), P(u, roof_h(u) - D.ROOF_T)], fill=(150, 95, 45), width=1)
        u += 0.45
    d.rectangle([P(D.TALL_U[0], 6.0), P(D.TALL_U[1], 1.0)], fill=C["glass"], outline=INK)
    for k in range(1, 4):
        uu = D.TALL_U[0] + (D.TALL_U[1] - D.TALL_U[0]) * k / 4
        d.line([P(uu, 6.0), P(uu, 1.0)], fill=INK)
    d.line([P(D.TALL_U[0], 3.4), P(D.TALL_U[1], 3.4)], fill=INK)
    d.rectangle([P(D.BAND_U[0], 2.2), P(D.BAND_U[1], 1.0)], fill=C["glass"], outline=INK)
    for k in range(1, 5):
        uu = D.BAND_U[0] + (D.BAND_U[1] - D.BAND_U[0]) * k / 5
        d.line([P(uu, 2.2), P(uu, 1.0)], fill=INK)
    d.rectangle([P(D.DOOR_U[0], 2.2), P(D.DOOR_U[1], 0.15)], fill=C["glass"], outline=INK)
    d.line([P(sum(D.DOOR_U) / 2, 2.2), P(sum(D.DOOR_U) / 2, 0.15)], fill=INK)
    d.rectangle([P(D.TICKET_U[0], 1.9), P(D.TICKET_U[1], 1.1)], fill=C["glass"], outline=INK)
    # デッキと手すり
    d.rectangle([P(D.DECK[0], D.DECK[2]), P(D.DECK[1], 0)], fill=C["deck"], outline=INK)
    d.line([P(D.DECK[0], D.DECK[2] + 1.0), P(D.DECK[1], D.DECK[2] + 1.0)], fill=C["steel"], width=3)
    u = D.DECK[0]
    while u <= D.DECK[1]:
        d.line([P(u, D.DECK[2] + 1.0), P(u, D.DECK[2])], fill=C["steel"], width=2)
        u += 1.7
    # 柱
    for u in D.COLS_W_U:
        d.line([P(u, 0), P(u, roof_h(u) - D.ROOF_T)], fill=C["steel"], width=5)
    # 庇
    a, b = P(D.CANOPY[0], D.CANOPY[3]), P(D.CANOPY[1], D.CANOPY[3] - 0.45)
    d.rounded_rectangle([a, b], radius=7, fill=C["canopy"], outline=INK)
    for u in (D.CANOPY[0] + 0.25, D.CANOPY[1] - 0.75):
        d.rectangle([P(u, D.CANOPY[3] - 0.45), P(u + 0.5, 0)], fill=C["canopy"], outline=INK)
    # 屋根（縁は白い板）
    r = [P(0, D.EAVE_N_H), P(D.RIDGE_U, D.RIDGE_H), P(D.ROOF_U, D.EAVE_S_H), P(D.ROOF_U, D.EAVE_S_H - D.ROOF_T),
         P(D.RIDGE_U, D.RIDGE_H - D.ROOF_T), P(0, D.EAVE_N_H - D.ROOF_T)]
    d.polygon(r, fill=C["fascia"], outline=INK)
    d.text(P(0, D.RIDGE_H + 2.3), "西の立面（ゲレンデの側から。左が北）", fill=INK, font=f_b)
    dim(d, P(0, -1.0), P(D.ROOF_U, -1.0), "屋根 %.0f m" % D.ROOF_U, (0, 6))
    dim(d, P(0, -2.2), P(D.RIDGE_U, -2.2), "棟まで %.0f m" % D.RIDGE_U, (0, 6))
    dim(d, P(D.RIDGE_U + 0.6, 0), P(D.RIDGE_U + 0.6, D.RIDGE_H), "棟 %.1f m" % D.RIDGE_H, (52, -10))
    dim(d, P(-1.0, 0), P(-1.0, D.EAVE_N_H), "%.1f" % D.EAVE_N_H, (-30, -10))
    dim(d, P(D.ROOF_U + 1.0, 0), P(D.ROOF_U + 1.0, D.EAVE_S_H), "%.1f" % D.EAVE_S_H, (30, -10))
    for u, h, t in ((3.2, 1.2, "吹きさらし\n（柱と屋根だけ）"), (8.0, 3.5, "低い灰の棟"), (21.0, 5.2, "縦張りの木"), (19.5, 1.4, "灰のパネル"),
                    (13.6, 3.3, "白い庇・入口"), (28.4, 6.3, "背の高いガラス"), (23.0, 0.0, "木のデッキと手すり")):
        d.text(P(u, h), t, fill=INK, font=f_s, stroke_width=3, stroke_fill=(255, 255, 255))


def south(d, ox, oy):
    """南の立面（駐車場の側から。左が西 = ゲレンデ）"""
    P = lambda v, h: (ox + v * S, oy - h * S)
    d.line([P(-2, 0), P(D.ROOF_V + 2, 0)], fill=INK, width=3)
    # 奥の屋根の面（棟まで上がっていく）
    d.polygon([P(0, D.EAVE_S_H), P(D.ROOF_V, D.EAVE_S_H), P(D.ROOF_V, D.RIDGE_H), P(0, D.RIDGE_H)], fill=C["roof"], outline=INK)
    d.rectangle([P(D.OVER_W, D.EAVE_S_H - D.ROOF_T), P(D.ROOF_V - D.OVER_E, 0)], fill=C["panel"], outline=INK)
    w0, w1 = D.OVER_W + 0.3, D.ROOF_V - D.OVER_E - 0.3
    d.rectangle([P(w0, D.DECK[2] + D.SOUTH_WIN[1]), P(w1, D.DECK[2] + D.SOUTH_WIN[0])], fill=C["glass"], outline=INK)
    n = 10
    for k in range(1, n):
        v = w0 + (w1 - w0) * k / n
        d.line([P(v, D.DECK[2] + D.SOUTH_WIN[1]), P(v, D.DECK[2] + D.SOUTH_WIN[0])], fill=INK)
    d.rectangle([P(0.3, D.DECK[2]), P(D.ROOF_V - D.OVER_E, 0)], fill=C["deck"], outline=INK)
    d.line([P(0.3, D.DECK[2] + 1.0), P(D.ROOF_V - D.OVER_E, D.DECK[2] + 1.0)], fill=C["steel"], width=3)
    for v in (0.4, 4.0, 7.6, 11.2, D.ROOF_V - D.OVER_E):
        d.line([P(v, 0), P(v, D.EAVE_S_H - D.ROOF_T)], fill=C["steel"], width=5)
    d.rectangle([P(0, D.EAVE_S_H), P(D.ROOF_V, D.EAVE_S_H - D.ROOF_T)], fill=C["fascia"], outline=INK)
    a, b = P(D.ROOF_V - D.OVER_E, D.CANOPY_E[3]), P(D.ROOF_V - D.OVER_E + D.CANOPY_E[2], D.CANOPY_E[3] - 0.45)
    d.rounded_rectangle([a, b], radius=7, fill=C["canopy"], outline=INK)
    d.rectangle([P(D.ROOF_V - D.OVER_E + D.CANOPY_E[2] - 0.5, D.CANOPY_E[3] - 0.45), P(D.ROOF_V - D.OVER_E + D.CANOPY_E[2], 0)], fill=C["canopy"], outline=INK)
    d.text(P(0, D.RIDGE_H + 2.3), "南の立面（左が西 = ゲレンデ）", fill=INK, font=f_b)
    dim(d, P(0, -1.0), P(D.ROOF_V, -1.0), "屋根 %.1f m" % D.ROOF_V, (0, 6))
    d.text(P(3.2, 5.4), "屋根は北の棟へ上がる", fill=(255, 255, 255), font=f_s)
    d.text(P(4.0, 2.0), "壁いっぱいの窓", fill=INK, font=f_s, stroke_width=3, stroke_fill=(255, 255, 255))
    d.text(P(D.ROOF_V - 0.5, 3.1), "駐車場の側の庇\n（場所は推しはかり）", fill=INK, font=f_s, stroke_width=3, stroke_fill=(255, 255, 255))


def plan(d, ox, oy):
    """平面（上が北）。ox, oy = 屋根の北西の角"""
    P = lambda u, v: (ox + v * S, oy + u * S)
    d.rectangle([P(0, 0), P(D.ROOF_U, D.ROOF_V)], outline=(120, 120, 130), width=2)
    wv0, wv1 = D.OVER_W, D.ROOF_V - D.OVER_E
    d.rectangle([P(D.LOW_U[0], wv0), P(D.LOW_U[1], wv1)], fill=(215, 215, 212), outline=INK, width=3)
    d.rectangle([P(D.HALL_U[0], wv0), P(D.HALL_U[1], wv1)], fill=(240, 226, 205), outline=INK, width=3)
    d.rectangle([P(D.DECK[0], 0.3), P(D.DECK[1], wv0)], fill=C["deck"], outline=INK)
    d.rectangle([P(D.HALL_U[1], 0.3), P(D.DECK[1], wv1)], fill=C["deck"], outline=INK)
    d.line([P(D.RIDGE_U, 0), P(D.RIDGE_U, D.ROOF_V)], fill=(200, 60, 60), width=3)
    d.rounded_rectangle([P(D.CANOPY[0], wv0 - D.CANOPY[2]), P(D.CANOPY[1], wv0)], radius=7, fill=C["canopy"], outline=INK)
    d.rounded_rectangle([P(D.CANOPY_E[0], wv1), P(D.CANOPY_E[1], wv1 + D.CANOPY_E[2])], radius=7, fill=C["canopy"], outline=INK)
    for a, b, col in ((D.DOOR_U, wv0, C["glass"]), (D.BAND_U, wv0, C["glass"]), (D.TALL_U, wv0, C["glass"])):
        d.line([P(a[0], b), P(a[1], b)], fill=(60, 140, 190), width=7)
    d.line([P(D.HALL_U[1], wv0 + 0.3), P(D.HALL_U[1], wv1 - 0.3)], fill=(60, 140, 190), width=7)
    d.line([P(D.HALL_U[0] + 3, wv1), P(D.HALL_U[1] - 1, wv1)], fill=(60, 140, 190), width=7)
    for u in D.COLS_W_U:
        a, b = P(u, 0.35)
        d.ellipse([a - 5, b - 5, a + 5, b + 5], fill=C["steel"])
    for u, v in ((17.5, 6.0), (17.5, 10.0), (23.0, 6.0), (23.0, 10.0), (28.0, 6.0), (28.0, 10.0)):   # 中の黒い鉄の丸柱
        a, b = P(u, v)
        d.ellipse([a - 6, b - 6, a + 6, b + 6], fill=(30, 30, 30))
    d.text((ox, oy - 96), "平面（上が北。左がゲレンデ、右が道、下が駐車場）", fill=INK, font=f_b)
    d.text((ox, oy - 54), "外の線 = 屋根の縁、赤い線 = 棟、水色 = ガラス、黒丸 = 中の鉄の柱（場所は推しはかり）", fill=(90, 90, 90), font=f_s)
    for u, v, t in ((2.0, 4.0, "吹きさらし"), (9.0, 4.0, "低い灰の棟\n（便所・倉庫と見る）"), (20.5, 4.2, "休憩所\n（一部屋・床は灰の\nコンクリート・壁と\n天井は木）"),
                    (18.6, -3.4, "入口と\n券売所"), (25.0, 0.4, "デッキ"), (32.4, 5.0, "デッキ"), (28.0, D.ROOF_V + 0.2, "駐車場の\n側の入口")):
        d.text(P(u, v), t, fill=INK, font=f_s, stroke_width=3, stroke_fill=(255, 255, 255))
    dim(d, P(D.ROOF_U + 1.2, 0), P(D.ROOF_U + 1.2, D.ROOF_V), "%.1f m" % D.ROOF_V, (0, 6))
    dim(d, P(0, -1.4), P(D.ROOF_U, -1.4), "%.0f m" % D.ROOF_U, (-44, -10))


def main():
    W, H = 3300, 1840
    im = Image.new("RGB", (W, H), (250, 249, 246))
    d = ImageDraw.Draw(im)
    d.text((40, 24), "旭ヶ丘スキー場 休憩所「雪ん子館」の図面（2026-11-11。寸法はどれも動画と空中写真から読んだ「約」）", fill=INK, font=f_b)
    plan(d, 150, 200)
    west(d, 820, 560)
    south(d, 820, 1180)
    frames = [("tokyu-133-A-lodge-front-closeup-canopy.jpg", "正面（西）: 白い庇・木の壁・背の高いガラス"),
              ("rdj-190-A-lodge-front-gable-yotei.jpg", "ゲレンデから: 左（北）は吹きさらしと低い棟"),
              ("tokyu-60-A-lodge-side-roof-eaves.jpg", "北西の角から: 北の軒は低い"),
              ("intro-5-A-lodge-wide-from-slope-snowroof.jpg", "南から: 壁いっぱいの窓とデッキ"),
              ("intro-85-A-lodge-slopeside-roof-wood-sign.jpg", "北寄りから: 軒先の柱と木の梁"),
              ("intro-120-B-interior-columns-wood-wall.jpg", "中: 黒い鉄の柱・木の壁")]
    FW, FH = 620, 349
    for k, (f, cap) in enumerate(frames):
        p = os.path.join(FRAMES, f)
        fx, fy = 1960 + (k % 2) * (FW + 20), 110 + (k // 2) * (FH + 44)
        if os.path.exists(p):
            fr = Image.open(p).convert("RGB")
            fr.thumbnail((FW, FH))
            im.paste(fr, (fx, fy))
        d.text((fx, fy + FH + 6), cap, fill=INK, font=f_m)
    notes = ["読めたこと・決めたこと",
             "・平屋。東西に走る棟から、北へ短く急に、南へ長くゆるく下る大きな屋根。縁は白い板",
             "・屋根の面は雪で見えない（夏の写真から濃い灰と見る）",
             "・ゲレンデの側（西）が正面。軒が深く、軒先に灰の細い鉄の柱が並び、柱の上に木の梁が出る",
             "・西の壁は下 3 m が灰の横長パネル、上が縦張りの木（橙がかった茶）。南の端は背の高いガラス",
             "・入口は白い角丸の庇の下。左に券売所の小窓。入口から南へ、低い木のデッキと金属の手すり",
             "・北の 6.5 m は壁が無く、柱と屋根だけ。その南に低い灰の棟（上は屋根まで空いて向こうが見える）",
             "分からないこと（推しはかりで描いた）",
             "・棟の場所（コマでは北から 3〜4 割、空中写真の色の境は 5 割）。14 m（4 割）にした",
             "・駐車場の側（東）の壁と入口。正面から撮ったコマが無い",
             "・中の柱の場所と、厨房・カウンターの場所"]
    y = 1360
    for t in notes:
        d.text((1960, y), t, fill=INK if t.startswith("・") else (200, 60, 60), font=f_m if t.startswith("・") else f_b)
        y += 40 if t.startswith("・") else 50
    im.save(OUT)
    print(OUT, im.size)


if __name__ == "__main__":
    main()
