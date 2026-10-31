"""手で並べ替える平面図（editor.html）を書き出す。

  python3 design/lodge-layout/editor.py

建物（壁・ガラス・窓・風除室・内階段・丸柱）は動かない下絵。家具と施設は動かせる品物。
品物の初めの並びは plan.py の「今」と「案」。寸法と座標は lodge/ と同じ（x = 東、y = 北、m）。
editor.html はブラウザで開くだけで動く（外の通信なし）。並べた結果は「書き出し」の JSON か、
ページの window.getLayout() で読める。
"""
import json
import os

from plan import HERE, now_layout, new_layout, SLOT_K
from dims import *  # noqa: F403

R = LOG_D / 2


def static():
    """動かない下絵: [種類, ...]（m）"""
    s = []
    for n in range(13):
        s.append(["grid", gx(n), Y0 - 6.5, gx(n), Y1 + 2.0])
    for n in range(8):
        s.append(["grid", X0 - 9.0, gy(n), X1 + 2.0, gy(n)])
    s.append(["rect", LEAN["x_out"], LEAN["y0"], X0, LEAN["y1"], "lean"])
    s.append(["label", (LEAN["x_out"] + X0) / 2 + 0.6, 0.0, "貸出（屋根のみ）", 0.55])
    s.append(["rect", DECK["x0"], DECK["y0"], DECK["x1"], DECK["y1"], "deck"])
    s.append(["label", (VEST["x1"] + DECK["x1"]) / 2, (DECK["y0"] + DECK["y1"]) / 2, "デッキ", 0.55])
    s.append(["rect", PLAZA["x0"], PLAZA["y0"], PLAZA["x1"], PLAZA["y1"], "deck"])
    s.append(["rect", X0, Y0, X1, Y1, "floor"])
    V = VEST
    s.append(["rect", V["x0"], Y0 - V["d"], V["x1"], Y0, "floor"])
    s.append(["wall", V["cx"] - ARCH["r"], Y0 - V["d"], V["x0"], Y0 - V["d"]])
    s.append(["wall", V["x0"], Y0 - V["d"], V["x0"], Y0])
    s.append(["wall", V["cx"] + ARCH["r"], Y0 - V["d"], V["x1"], Y0 - V["d"]])
    s.append(["wall", V["x1"], Y0 - V["d"], V["x1"], Y0])
    for kk in range(2):
        x0 = V["x0"] + V["t"] + 0.10 + kk * (VENDING["w"] + VENDING["gap"])
        s.append(["rect", x0, Y0 - 0.05 - VENDING["d"], x0 + VENDING["w"], Y0 - 0.05, "vend"])
    s.append(["label", V["cx"] + 0.6, Y0 - 3.0, "風除室（自販機 2 台）", 0.55])
    s.append(["label", V["cx"], Y0 - V["d"] - 1.0, "入口 ▲", 0.75])
    s.append(["wall", X0, Y1, X1, Y1])
    s.append(["wall", X1, Y1, X1, Y0])
    s.append(["wall", X0, Y0, GLASS_S_X0, Y0])
    s.append(["glass", GLASS_S_X0, Y0, X1, Y0])
    s.append(["glass", X0, Y0, X0, Y1])
    s.append(["autodoor", DOOR_IN["x0"], Y0, DOOR_IN["x1"], Y0])
    for u in GLASS_S_POSTS:
        s.append(["post", u, Y0])
    for u in GLASS_W_POSTS:
        s.append(["post", X0, u])
    for c, kind in OPENINGS["1F_N"]:
        if kind == "win":
            s.append(["win", c - WIN["w"] / 2, Y1, c + WIN["w"] / 2, Y1])
    for c, kind in OPENINGS["1F_E"]:
        s.append(["win", X1, c - WIN["w"] / 2, X1, c + WIN["w"] / 2])
    wy = sorted(GLASS_W_POSTS)
    s.append(["opening", X0, wy[GLASS_W_DOOR_BAY] + 0.2, X0, wy[GLASS_W_DOOR_BAY + 1] - 0.2])
    s.append(["label", X0 - 1.3, (wy[GLASS_W_DOOR_BAY] + wy[GLASS_W_DOOR_BAY + 1]) / 2, "戸", 0.5])
    I = INSTAIR
    s.append(["stair", I["x0"], I["y_bottom"], I["x1"], I["y_top"], I["xm"], I["tread"], I["n1"], I["y_land"]])
    s.append(["label", (I["x0"] + I["x1"]) / 2, I["y_bottom"] - 0.8, "内階段（2 階へ）", 0.5])
    for x, y in COLS:
        s.append(["col", x, y, COL_D / 2])
    s.append(["label", X1 + 1.6, Y1 + 1.6, "北 ▲", 0.7])
    return s


def items(L):
    """動かせる品物。x, y は真ん中、rot は度（0 で正面が南＝食堂の側）"""
    out = []

    def add(id_, name, shape, x, y, w, d, kind, rot=0, **k):
        out.append(dict(id=id_, name=name, shape=shape, x=round(x, 2), y=round(y, 2), w=round(w, 2), d=round(d, 2),
                        rot=rot, kind=kind, **k))
    hw = (CH["x1"] - CH["x0"]) / 2
    cx = L["ch_cx"]
    add("hearth", "暖炉", "hearth", cx, (CH["y0"] + Y1 + 1.5) / 2, 2 * hw, Y1 + 1.5 - CH["y0"], "fire")
    add("machine", "大きなミシン", "box", *L["machine"], 4.2, 1.8, "sled")
    add("seller", "売り子", "person", *L["seller"], 0.9, 0.9, "sled")
    add("rental_shelf", "貸出の棚", "box", (RENTAL["x0"] + RENTAL["x1"]) / 2, (BACK["y0"] + BACK["y1"]) / 2,
        RENTAL["x1"] - RENTAL["x0"], BACK["y1"] - BACK["y0"], "sled")
    SR = SKI_RACK
    add("ski_rack", "スキー置場", "rack", (SR["x0"] + SR["x1"]) / 2, (SR["y0"] + SR["y1"]) / 2,
        SR["x1"] - SR["x0"], SR["y1"] - SR["y0"], "sled")
    add("fridge", "雪だるまの冷蔵庫", "fridge", *L["fridge"], 2.0, 1.6, "food")
    add("board", "巨大アイロン台", "box", *L["board"], 3.8, 1.24, "food")
    add("press", "プレス機", "box", *L["press"], 1.6, 2.0, "food")
    add("dryer", "乾燥機", "box", *L["dryer"], 2.7, 2.7, "food")
    for i, (x, y) in enumerate(L["sacks"]):
        add("sack%d" % i, "麻袋", "sack", x, y, 0.7, 0.7, "food")
    b0, b1 = L["back"]
    add("back", "厨房の奥の台", "box", (b0 + b1) / 2, (BACK["y0"] + BACK["y1"]) / 2, b1 - b0, BACK["y1"] - BACK["y0"],
        "wood")
    for i, (x, y, rot) in enumerate(L["vend_in"]):
        add("vend%d" % i, "自販機", "box", x, y, 2.1, 1.8, "food", rot=rot)
    for i, x in enumerate(L["partition"]):
        add("partition%d" % i, "間仕切り", "box", x, (KITCHEN["y_front"] + Y1) / 2, 0.12, Y1 - KITCHEN["y_front"],
            "wall")
    add("door1", "勝手口", "door", L["door1"], Y1 - 0.15, DOOR1["w"], 0.3, "door")
    for i, (x, y) in enumerate(TABLES):
        add("table%d" % i, "食卓", "table", x, y, TABLE["w"], TABLE["d"], "seat")
    WB = WINDOW_BAR
    add("window_bar", "窓向きのカウンター", "bar", (WB["x0"] + WB["x1"]) / 2, WB["y0"] + 0.5,
        WB["x1"] - WB["x0"], 1.0, "seat")
    for kind, a, b, label in L["zones"]:
        add("zone_" + kind, label, "zone", (a + b) / 2, (gy(2.45) + Y1 - R) / 2, b - a, Y1 - R - gy(2.45), kind)
    return out


def main():
    data = dict(static=static(), presets={"now": items(now_layout()), "new": items(new_layout())},
                bounds=[-31.0, -19.5, 24.5, 17.0], hearth=dict(
                    benches=[[x0 - (CH["x0"] + CH["x1"]) / 2, y0 - (CH["y0"] + Y1 + 1.5) / 2,
                              x1 - (CH["x0"] + CH["x1"]) / 2, y1 - (CH["y0"] + Y1 + 1.5) / 2]
                             for x0, y0, x1, y1 in HEARTH_BENCH],
                    fire_w=CH["fire_w"]),
                table=dict(chair=[0.5, 0.45], gap=0.35, step=1.15),
                bar=dict(step=STOOL["step"], r=STOOL["r"]))
    tpl = open(os.path.join(HERE, "editor-template.html"), encoding="utf-8").read()
    html = tpl.replace("/*DATA*/null", json.dumps(data, ensure_ascii=False))
    with open(os.path.join(HERE, "editor.html"), "w", encoding="utf-8") as f:
        f.write(html)
    print("wrote", os.path.join(HERE, "editor.html"))


if __name__ == "__main__":
    main()
