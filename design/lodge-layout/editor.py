"""手で並べ替える平面図を、開発ダッシュボードの「間取り」のページ（docs/layout.html）に書き出す。

  python3 design/lodge-layout/editor.py

建物（壁・ガラス・窓・風除室・内階段・丸柱）は動かない下絵。家具と施設は動かせる品物。
始めの並びは 3 つ:
  ゲームの今   いまのコードから作る（lodge/dims.py、props/build_scenes.py の kitchen、game/main.gd の売り子と冷蔵庫）。
               ロッジや厨房の並びを変えたら、これを走らせ直すとダッシュボードも合う
  代表の並び   layout-daihyo.json（2026-10-31 に代表が手で並べたもの）
  前の並び     layout-pr68.json（PR #68 のころ）
寸法と座標は lodge/ と同じ（x = 東、y = 北、m）。向き rot は度で、0 が正面を南へ、上から見て反時計回り。
ページは docs/ を出すだけで動く。並べた結果は「書き出し」の JSON か、ページの window.getLayout() で読める。
決めた並びは layout-*.json に残す。
"""
import ast
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "lodge"))
from dims import *  # noqa: E402,F403

R = LOG_D / 2
X2 = 2.0   # 厨房の場面の座標は 2 倍する前の数


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


def _rot(x, y, deg):
    a = math.radians(deg)
    return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)


def _gd_vec(name):
    """game/main.gd の const NAME := Vector3(a, b, c) を (a, b, c) で"""
    src = open(os.path.join(ROOT, "game", "main.gd"), encoding="utf-8").read()
    m = re.search(r"const %s := Vector3\(([^)]*)\)" % name, src)
    return tuple(float(v) for v in m.group(1).split(","))


def _kitchen():
    """props/build_scenes.py の kitchen の並びと当たりの箱"""
    tree = ast.parse(open(os.path.join(ROOT, "props", "build_scenes.py"), encoding="utf-8").read())
    got = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) and node.targets[0].id in ("SCENES", "COLLIDE"):
            got[node.targets[0].id] = ast.literal_eval(node.value)
    return got["SCENES"]["kitchen"], got["COLLIDE"]["kitchen"]


def game_items():
    """いまのコードの並び。x, y は真ん中"""
    out = []

    def add(id_, name, shape, x, y, w, d, kind, rot=0):
        out.append(dict(id=id_, name=name, shape=shape, x=round(x, 2), y=round(y, 2), w=round(w, 2), d=round(d, 2),
                        rot=rot, kind=kind))
    add("hearth", "暖炉", "hearth", (CH["x0"] + CH["x1"]) / 2, (CH["y0"] + Y1 + 1.5) / 2, CH["x1"] - CH["x0"],
        Y1 + 1.5 - CH["y0"], "fire")
    mx, my, _, mr = SLOTS["slot_craft_rental"]
    add("machine", "大きなミシン", "box", mx, my, 4.2, 1.8, "sled", mr)
    sx, _, sz = _gd_vec("SHOP_AT")                 # 目印の中の座標（Godot: -z が北）
    dx, dy = _rot(sx, -sz, mr)
    add("seller", "売り子", "person", mx + dx, my + dy, 0.9, 0.9, "sled")
    add("rental_shelf", "貸出の棚", "box", (RENTAL["x0"] + RENTAL["x1"]) / 2, (RENTAL["y0"] + RENTAL["y1"]) / 2,
        RENTAL["y1"] - RENTAL["y0"], RENTAL["x1"] - RENTAL["x0"], "sled", 90)
    SR = SKI_RACK
    add("ski_rack", "スキー置場", "rack", (SR["x0"] + SR["x1"]) / 2, (SR["y0"] + SR["y1"]) / 2,
        SR["x1"] - SR["x0"], SR["y1"] - SR["y0"], "sled")
    kx, ky, _, _ = SLOTS["slot_food_kitchen"]
    fx, _, fz = _gd_vec("SNOWMAN_AT")
    add("fridge", "雪だるまの冷蔵庫", "fridge", kx + fx, ky - fz, 2.0, 1.6, "food")
    scene, boxes = _kitchen()
    names = {"giant_press_board": ("board", "巨大アイロン台"), "giant_heat_press": ("press", "プレス機"),
             "giant_dryer": ("dryer", "乾燥機")}
    n_sack = 0
    for path, x, y, z, rz, _sc in scene:
        base = os.path.splitext(os.path.basename(path))[0]
        if base in names:
            box = min(boxes, key=lambda b: (b[0] - x) ** 2 + (b[1] - y) ** 2)
            add(names[base][0], names[base][1], "box", kx + X2 * x, ky + X2 * y, X2 * box[2], X2 * box[3], "food")
        elif base.startswith("pellet_sack"):
            add("sack%d" % n_sack, "麻袋", "sack", kx + X2 * x, ky + X2 * y, 0.7, 0.7, "food")
            n_sack += 1
    add("back", "厨房の奥の台", "box", (BACK["x0"] + BACK["x1"]) / 2, (BACK["y0"] + BACK["y1"]) / 2,
        BACK["x1"] - BACK["x0"], BACK["y1"] - BACK["y0"], "wood")
    for i, k in enumerate(("slot_vending_1", "slot_vending_2")):
        x, y, _, r = SLOTS[k]
        add("vend%d" % i, "自販機", "box", x, y, 2.1, 1.8, "food", r)
    for c, kind in OPENINGS["1F_N"]:
        if kind == "door1":
            add("door1", "勝手口", "door", c, Y1 - 0.15, DOOR1["w"], 0.3, "door")
    for i, (x, y) in enumerate(TABLES):   # TABLES は卓の南西の角
        add("table%d" % i, "食卓", "table", x + TABLE["w"] / 2, y + TABLE["d"] / 2, TABLE["w"], TABLE["d"], "seat")
    src = open(os.path.join(ROOT, "game", "main.gd"), encoding="utf-8").read()   # 番台（main.gd の BANDAI）
    for m in re.finditer(r'\["(counter_\w+)", "\w+", "(\w+)", Vector2\(([^)]*)\), ([-\d.]+)\]', src):
        x, y = (float(v) for v in m.group(3).split(","))
        who = "おじいさん" if m.group(2) == "buttons" else "雪だるま"
        add("counter_" + ("seller" if m.group(2) == "buttons" else "snowman"), who + "の番台\n（レジ・お皿）", "box", x, y,
            1.8, 0.68, "sled" if m.group(2) == "buttons" else "food", round(float(m.group(4))))
    WB = WINDOW_BAR
    add("window_bar", "窓向きのカウンター", "bar", (WB["x0"] + WB["x1"]) / 2, WB["y0"] + 0.5,
        WB["x1"] - WB["x0"], 1.0, "seat")
    return out


def _saved(name):
    return json.load(open(os.path.join(HERE, name), encoding="utf-8"))


def main():
    daihyo = _saved("layout-daihyo.json")
    game = game_items() + [i for i in daihyo["items"] if i["shape"] == "zone"]   # 区分けは代表の並びから
    presets = {
        "game": dict(label="ゲームの今", note="いまのコード（lodge/dims.py ほか）から作った並び", items=game),
        "bandai": dict(label="番台の案", note="おじいさんと雪だるまの前に、店番のカウンターとレジ", items=_saved("layout-bandai-an.json")["items"]),
        "daihyo": dict(label="代表の並び（10/31）", note="代表が手で並べたもの", items=daihyo["items"]),
        "pr68": dict(label="前の並び（#68）", note="暖炉が東寄り、厨房が西寄りだったころ", items=_saved("layout-pr68.json")["items"]),
    }
    data = dict(static=static(), presets=presets, start="game",
                bounds=[-31.0, -19.5, 24.5, 17.0], hearth=dict(
                    benches=[[x0 - HEARTH_CX, y0 - (CH["y0"] + Y1 + 1.5) / 2, x1 - HEARTH_CX, y1 - (CH["y0"] + Y1 + 1.5) / 2]
                             for x0, y0, x1, y1 in HEARTH_BENCH],
                    fire_w=CH["fire_w"]),
                table=dict(chair=[0.5, 0.45], gap=0.35, step=1.15),
                bar=dict(step=STOOL["step"], r=STOOL["r"]))
    tpl = open(os.path.join(HERE, "editor-template.html"), encoding="utf-8").read()
    html = tpl.replace("/*DATA*/null", json.dumps(data, ensure_ascii=False))
    out = os.path.join(HERE, "..", "..", "docs", "layout.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    print("wrote", os.path.normpath(out))


if __name__ == "__main__":
    main()
