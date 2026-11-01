"""雪だるまの店で売るペレット（料理のもとの粒）を Blender で組む。料理ごとに色と形を変えた手芸の粒（直径 4〜6 cm）。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_pellets.py -- \
        --views all,near_a,near_b --prefix props/renders/32-pellets

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_pellets.py -- \
        --look flat --export game/props/pellets

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_pellets.py -- --icons game/props/pellets/icons

品書きと見た目は design/snowman-food/（01_menu.png の丸の中）。名前は pellet_<料理>。
料理の glb は props/build_food.py（game/props/food/）。
"""
import math
import os
import random
import sys

from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--only", dict(default="", help="書き出す品物の名前（カンマで）")),
              ("--icons", dict(default="", help="この場所に、品物ごとのアイコン（背景を透かした絵）を描く"))])
K.setup(A, fiber=4.0, scale=1.5, tris=700)
EX = K.S["export"]
C.HEX.update({"felt_azuki": "6A2A34", "felt_crumb": "C98A3E", "felt_silver": "9AA6B0", "felt_shell": "8E8A84",
              "felt_potato": "E8C878"})

# 品書きの順（design/snowman-food/README.md）
ORDER = ["onigiri", "taiyaki", "nikuman", "korokke", "hashbrown", "fries", "hotsand", "yakiimo", "hotcake", "sanma", "kaki",
         "yakisoba", "ramen", "udon", "soba", "cocoa", "oshiruko", "corn", "clam", "greentea", "milk", "milktea"]


def blob(P, role, c, half, n=2.0, nz=None, cuts=None, rot=None):
    """丸みのあるフェルトの塊（K.pbox の薄い包み）"""
    K.pbox(P, role, c, half, n=n, nz=nz, c=cuts or K.cuts(8, 5), rot=rot)


def coil(P, role, R, r, turns, z0, rise, wave=0.0):
    """毛糸を渦に巻いた麺"""
    pts = []
    n = int(turns * 28)
    for i in range(n + 1):
        t = i / n
        a = t * turns * 2 * math.pi
        rr = R * (0.35 + 0.65 * t)
        pts.append((rr * math.cos(a), rr * math.sin(a), z0 + rise * t + wave * math.sin(a * 5)))
    K.tube(P, role, pts, r, sides=6)


def make(key):
    P = K.Parts("pellet_" + key, kind="pellet", dish=key)
    rnd = random.Random(len(key))
    if key == "onigiri":      # 白い毛玉に、のりの四角
        blob(P, "felt_rice", (0, 0, 0.022), (0.022, 0.02, 0.021))
        K.box(P, "felt_nori", (0, 0.018, 0.016), (0.018, 0.006, 0.016))
    elif key == "taiyaki":    # 平たいしずくに尾びれと目
        blob(P, "felt_beige", (0, 0, 0.012), (0.026, 0.017, 0.011), nz=2.2)
        K.extrude(P, "felt_beige", [(-0.022, 0.0), (-0.038, 0.012), (-0.034, 0.0), (-0.038, -0.012)], 0.006, 0.016)
        K.disc(P, "felt_brown", (0.014, 0.0, 0.023), 0.004, 0.002, segs=10)
    elif key == "nikuman":    # 綿のふわふわ 4 つ
        for (dx, dy, dz) in ((0, 0, 0.016), (0.013, 0.006, 0.026), (-0.011, 0.008, 0.024), (0.002, -0.011, 0.03)):
            blob(P, "cotton", (dx, dy, dz), (0.015, 0.015, 0.014))
    elif key == "korokke":    # 小判形に、パン粉の粒
        blob(P, "felt_beige", (0, 0, 0.012), (0.028, 0.019, 0.012), nz=2.4)
        for k in range(10 if not EX else 5):
            a = k * 2.3
            r = 0.006 + 0.012 * ((k * 7) % 5) / 5
            K.pbox(P, "felt_crumb", (r * math.cos(a), r * math.sin(a) * 0.7, 0.024), (0.003, 0.003, 0.002), n=3.0, c=2)
    elif key == "hashbrown":  # 小さな板に、細切りの毛糸
        blob(P, "felt_cream", (0, 0, 0.008), (0.026, 0.018, 0.008), n=4.0)
        for i in range(5):
            K.tube(P, "yarn_yellow", [(-0.018 + 0.009 * i, -0.014, 0.017), (-0.016 + 0.009 * i, 0.014, 0.017)], 0.0022, sides=5)
    elif key == "fries":      # 細い棒を 5 本、赤い糸で束ねる
        for i in range(5):
            K.box(P, "felt_potato", (-0.014 + 0.007 * i, 0.002 * (i % 2), 0.006 + 0.002 * (i % 3)), (0.006, 0.05, 0.006),
                  rot=(0.12 * (i - 2), "Z"))
        K.ring(P, "thread_red", (0, 0, 0.008), 0.02, 0.0025, axis="Y", n=20)
    elif key == "hotsand":    # 食パン 2 枚にチーズ
        blob(P, "felt_tan", (0, 0, 0.006), (0.022, 0.022, 0.005), n=5.0)
        blob(P, "felt_yellow", (0, 0, 0.013), (0.024, 0.024, 0.0025), n=5.0)
        blob(P, "felt_tan", (0, 0, 0.02), (0.022, 0.022, 0.005), n=5.0)
    elif key == "yakiimo":    # 紫の小さな芋
        blob(P, "felt_purple", (0, 0, 0.014), (0.034, 0.015, 0.013))
        K.disc(P, "felt_yellow", (0.034, 0.0, 0.014), 0.008, 0.002, axis="X", segs=10)
    elif key == "hotcake":    # 2 段の生地にバター
        for z in (0.006, 0.017):
            K.lathe(P, "felt_cream", [(0.0, z - 0.005), (0.02, z - 0.005), (0.022, z), (0.02, z + 0.005), (0.0, z + 0.005)],
                    segs=K.cuts(24, 14))
        blob(P, "felt_yellow", (0, 0, 0.025), (0.006, 0.006, 0.004), n=5.0, cuts=3)
    elif key == "sanma":      # 細い銀の魚、背は濃く
        blob(P, "felt_silver", (0, 0, 0.007), (0.04, 0.008, 0.007), nz=2.0)
        blob(P, "felt_charcoal", (0, 0, 0.012), (0.037, 0.004, 0.003))
        K.extrude(P, "felt_silver", [(0.036, 0.0), (0.05, 0.009), (0.047, 0.0), (0.05, -0.009)], 0.004, 0.01)
    elif key == "kaki":       # 灰色の殻に、身
        blob(P, "felt_shell", (0, 0, 0.007), (0.028, 0.02, 0.007), n=2.0)
        blob(P, "felt_cream", (0.003, 0, 0.014), (0.016, 0.011, 0.005))
    elif key == "yakisoba":   # 縮れた麺の毛糸と、キャベツ
        for i in range(4):
            pts = [(-0.026 + 0.0035 * k, -0.012 + 0.008 * i + 0.003 * math.sin(k * 1.4 + i), 0.005 + 0.002 * (i % 2)) for k in range(16)]
            K.tube(P, "yarn_noodle", pts, 0.0028, sides=5)
        blob(P, "felt_green", (0.012, 0.016, 0.011), (0.008, 0.006, 0.002), n=3.0, cuts=3)
    elif key == "ramen":      # 黄色い毛糸の渦
        coil(P, "yarn_noodle", 0.024, 0.0045, 3.0, 0.005, 0.004)
    elif key == "udon":       # 太い白い毛糸の渦
        coil(P, "yarn_cream", 0.026, 0.0075, 2.2, 0.008, 0.004)
    elif key == "soba":       # 灰茶の細い毛糸の渦
        coil(P, "yarn_soba", 0.024, 0.0038, 3.2, 0.004, 0.004)
    elif key == "cocoa":      # 茶色の角砂糖に、綿のマシュマロ
        blob(P, "felt_brown", (0, 0, 0.016), (0.016, 0.016, 0.016), n=6.0, rot=(0.4, "Z"))
        blob(P, "cotton", (0.004, -0.004, 0.035), (0.007, 0.007, 0.006))
    elif key == "oshiruko":   # 小豆の粒と、白い小さな餅
        for k in range(7):
            a = k * 0.9
            r = 0.012 * (k % 3) / 2
            blob(P, "felt_azuki", (r * math.cos(a), r * math.sin(a), 0.008 + 0.006 * (k % 2)), (0.0075, 0.0065, 0.0065), cuts=3)
        blob(P, "felt_rice", (0.002, 0, 0.022), (0.009, 0.009, 0.006), n=4.0, cuts=3)
    elif key == "corn":       # 小さなとうもろこしの穂と、緑の皮
        blob(P, "felt_yellow", (0, 0, 0.012), (0.028, 0.012, 0.012), nz=2.0)
        for k in range(9):
            K.pbox(P, "felt_gold", (-0.022 + 0.0055 * k, -0.012, 0.012), (0.0028, 0.002, 0.0028), n=2.0, c=2)
        K.extrude(P, "felt_green", [(0.02, 0.0), (0.042, 0.012), (0.036, 0.0), (0.042, -0.012)], 0.006, 0.012)
    elif key == "clam":       # 扇の貝殻に、筋の縫い目
        K.extrude(P, "felt_cream", [(0.0, -0.004)] + [(0.026 * math.cos(a), 0.026 * math.sin(a)) for a in
                                    [math.pi * (0.1 + 0.8 * k / 12) for k in range(13)]], 0.0, 0.01)
        for k in range(5):
            a = math.pi * (0.2 + 0.6 * k / 4)
            K.stitch_line(P, "thread_dark", [(0.0, 0.0, 0.0105), (0.024 * math.cos(a), 0.024 * math.sin(a), 0.0105)], r=0.0009, dash=0.004)
        P.transform(Matrix.Translation((0, -0.012, 0)))
    elif key == "greentea":   # 緑の葉っぱに、葉脈の縫い目
        K.extrude(P, "felt_green", K.circle_poly(0.03, 24, sx=1.0, sy=0.42), 0.0, 0.006)
        K.stitch_line(P, "thread", [(-0.026, 0.0, 0.0065), (0.026, 0.0, 0.0065)], r=0.0009, dash=0.005)
        for s in (-1, 1):
            for x in (-0.01, 0.006):
                K.stitch_line(P, "thread", [(x, 0.0, 0.0065), (x + 0.008, s * 0.008, 0.0065)], r=0.0008, dash=0.004)
    elif key == "milk":       # 牛乳のしずく
        K.lathe(P, "felt_rice", [(0.0, 0.0), (0.012, 0.002), (0.02, 0.012), (0.019, 0.022), (0.012, 0.032), (0.005, 0.042), (0.0, 0.048)],
                segs=K.cuts(24, 14))
    elif key == "milktea":    # ティーバッグ: 紙の袋、糸、赤い札
        blob(P, "paper_kraft", (0, 0, 0.018), (0.02, 0.006, 0.02), n=6.0)
        K.tube(P, "thread", [(0.0, 0.0, 0.038), (0.004, 0.0, 0.05), (0.012, 0.0, 0.056)], 0.0007, sides=4)
        K.box(P, "felt_red", (0.02, 0.0, 0.056), (0.016, 0.003, 0.012))
    P.finish(fuzz=0.0008, cotton_fuzz=0.002)


only = A.only.split(",") if A.only else None
for key in ORDER:
    make(key)

if A.export:
    K.export_all(A.export, only)
elif A.icons:   # 売り場の画面のアイコン（game/props/pellets/icons/）
    K.render_icons(A.icons, ["pellet_" + k for k in ORDER if not only or "pellet_" + k in only], size=192, pad=1.3)
else:
    roots = {r.name: r for r, p in K.made}
    TZ = 0.75
    K.table(0.0, 0.0, TZ, 1.0, 0.6)
    K.grid_place([roots["pellet_" + k] for k in ORDER], 8, 0.1, 0.12, x0=-0.35, y0=0.1, z=TZ)
    K.room()
    K.interior_light()
    cams = {
        "all": ((0.0, 0.62, 1.2), (0.0, -0.05, 0.75), 34),
        "near_a": ((-0.2, 0.38, 0.95), (-0.2, 0.05, 0.76), 34),
        "near_b": ((0.2, 0.3, 0.95), (0.2, -0.08, 0.76), 34),
    }
    K.render_views(A, cams)
