"""書き出した小物の glb を組み合わせて、ロッジの場面を作る。描いて確かめ、Godot の場面（.tscn）も書き出す。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_scenes.py -- \
        --views hearth,kotatsu,dining --prefix props/renders/15-scene

場面:
  hearth_nook  暖炉の前のくつろぎ場所: 暖炉、編んだ敷物、ひじ掛け椅子 2 脚、プフ、小卓と灯り、薪、膝掛け
  kotatsu_room 小上がりの掘りごたつ: 畳の台、こたつ、座布団 4 枚、提灯、行灯、お茶とみかん
  dining       食堂のカウンター: カウンター 2 区画、メニュー板 3 枚、レジ、お盆にラーメンとお茶、給水機、肉まんのケース
  kitchen      厨房（ロッジの slot_food_kitchen に置く）: 巨大なプレス機・乾燥機を奥に並べ（アイロン台は一旦外した）、東の端の
               作業台に卓上の道具。床に麻袋と仕分けの盆、奥の台（ロッジの物）に瓶と紙袋。前（-Y）がレジのカウンターの側。
               装置と作業台には当たり判定の箱

先に各台本で glb を game/props/ に書き出しておくこと。Godot の場面は game/props/sets/<名前>.tscn
（game/props_set.gd が素材を着せる）。座標は Blender（前 +Y）で書き、Godot（前 -Z）に直して書く。
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kit as K  # noqa: E402

A = C.parse([("--no-tscn", dict(action="store_true")),
             ("--scenes", dict(default="", help="組む場面の名前（カンマで）。空なら全部"))])
K.setup(A, fiber=2.0)
GAME = os.path.join(C.ROOT, "game")
X = 2.0   # 小物は 2 倍（食べ物は 1.5 倍）で書き出してあるので、置く位置も 2 倍に広げる

# (glb の res:// からの道, x, y, z, z 軸まわりの回転（度）, 大きさ)
SCENES = {
    "hearth_nook": [
        ("props/room/floor_planks.glb", -1, 0, 0, 0, 1), ("props/room/floor_planks.glb", 1, 0, 0, 0, 1),
        ("props/room/floor_planks.glb", -1, 2, 0, 0, 1), ("props/room/floor_planks.glb", 1, 2, 0, 0, 1),
        ("props/room/wall_boards.glb", -1, -1.05, 0, 0, 1), ("props/room/wall_boards.glb", 1, -1.05, 0, 0, 1),
        ("props/hearth/fireplace_stone.glb", 0, -0.75, 0.02, 0, 1),
        ("props/room/rug_braided_warm.glb", 0, 1.05, 0.02, 0, 1),
        ("props/furniture/armchair_rust.glb", -0.95, 1.2, 0.02, -35, 1),
        ("props/furniture/armchair_mustard.glb", 0.95, 1.2, 0.02, 35, 1),
        ("props/furniture/pouf_ivory.glb", 0.0, 1.75, 0.02, 0, 1),
        ("props/furniture/side_table.glb", -1.75, 0.6, 0.02, 0, 1),
        ("props/furniture/table_lamp.glb", -1.75, 0.6, 0.6, 0, 1),
        ("props/furniture/blanket_red.glb", 0.95, 1.25, 0.42, 30, 1),
        ("props/hearth/log_basket.glb", 1.35, -0.25, 0.02, 0, 1),
        ("props/hearth/kettle_red.glb", -0.75, -0.42, 0.1, 0, 1),
        ("props/furniture/floor_lamp.glb", 1.8, 0.3, 0.02, 0, 1),
        ("props/food/yunomi_wood.glb", -1.72, 0.48, 0.6, 0, 1),
        ("props/food/mikan.glb", -1.8, 0.68, 0.6, 0, 1),
    ],
    "kotatsu_room": [
        ("props/room/floor_planks_dark.glb", -1, 0, 0, 0, 1), ("props/room/floor_planks_dark.glb", 1, 0, 0, 0, 1),
        ("props/room/floor_planks_dark.glb", -1, 2, 0, 0, 1), ("props/room/floor_planks_dark.glb", 1, 2, 0, 0, 1),
        ("props/room/wall_quilt_warm.glb", -1, -1.05, 0, 0, 1), ("props/room/wall_quilt_warm.glb", 1, -1.05, 0, 0, 1),
        ("props/room/koagari_4.glb", 0, 0.0, 0, 90, 1),
        ("props/room/kotatsu_patch.glb", 0, 0.0, 0.4, 0, 1),
        ("props/room/zabuton_red.glb", 0, 0.72, 0.4, 0, 1), ("props/room/zabuton_indigo.glb", 0, -0.72, 0.4, 0, 1),
        ("props/room/zabuton_mustard.glb", 0.95, 0, 0.4, 0, 1), ("props/room/zabuton_moss.glb", -0.95, 0, 0.4, 0, 1),
        ("props/furniture/pendant_lantern.glb", 0, 0, 2.3, 0, 1),
        ("props/furniture/andon.glb", -1.55, -0.6, 0.4, 0, 1),
        ("props/food/yunomi_navy.glb", -0.2, -0.15, 0.82, 0, 1), ("props/food/yunomi_wood.glb", 0.15, 0.2, 0.82, 0, 1),
        ("props/food/taiyaki.glb", -0.25, 0.15, 0.82, 20, 1),
        ("props/room/futon_patch.glb", 1.7, 1.6, 0.0, 0, 1),
    ],
    "dining": [
        ("props/room/floor_planks.glb", -1, 0, 0, 0, 1), ("props/room/floor_planks.glb", 1, 0, 0, 0, 1),
        ("props/room/floor_planks.glb", -1, 2, 0, 0, 1), ("props/room/floor_planks.glb", 1, 2, 0, 0, 1),
        ("props/room/wall_logs.glb", -1, -1.05, 0, 0, 1), ("props/room/wall_logs.glb", 1, -1.05, 0, 0, 1),
        ("props/counter/counter_patch.glb", -0.9, 0, 0, 0, 1), ("props/counter/counter_patch.glb", 0.9, 0, 0, 0, 1),
        ("props/counter/menu_food.glb", -0.9, -0.85, 1.85, 0, 1), ("props/counter/menu_drink.glb", 0.1, -0.85, 1.85, 0, 1),
        ("props/counter/menu_sweet.glb", 1.1, -0.85, 1.85, 0, 1),
        ("props/counter/register.glb", -1.35, -0.05, 1.05, 15, 1), ("props/counter/bell.glb", -0.95, 0.15, 1.05, 0, 1),
        ("props/counter/tray_wood.glb", -0.3, 0.05, 1.05, 0, 1),
        ("props/food/ramen_shoyu.glb", -0.36, 0.05, 1.063, 0, 1), ("props/food/yunomi_wood.glb", -0.16, 0.1, 1.063, 0, 1),
        ("props/counter/tray_dark.glb", 0.3, 0.05, 1.05, 0, 1),
        ("props/food/curry.glb", 0.27, 0.05, 1.063, 0, 1), ("props/food/can_cocoa.glb", 0.46, 0.1, 1.063, 0, 1),
        ("props/food/bun_case.glb", 1.3, -0.05, 1.05, -10, 1),
        ("props/counter/chopstick_box.glb", 0.75, 0.2, 1.05, 0, 1),
        ("props/counter/water_server.glb", 2.3, -0.55, 0.0, -20, 1),
        ("props/counter/paper_cups.glb", 2.05, -0.3, 0.0, 0, 1),
        ("props/furniture/pendant_drum.glb", -0.9, 0.1, 2.6, 0, 1), ("props/furniture/pendant_drum.glb", 0.9, 0.1, 2.6, 0, 1),
    ],
    # 原点はロッジの slot_food_kitchen（床の上）。前のカウンターの裏は y = -1.36、奥の台（高さ 0.45）は y = 0.93..1.28、
    # 両脇の間仕切りは x = ±4.1（どれも 2 倍する前の数）。装置の前（カウンターとのあいだ）に 2 m ほどの通り道をあける
    "kitchen": [
        # 巨大な装置 3 台を奥に並べ、正面をカウンターへ。東の端の作業台に卓上の道具
        # 巨大なアイロン台（x = -2.9）は一旦外した。そこ（ミシンの右）に雪だるまの冷蔵庫を置く（main.gd の _put_snowman）。2026-10-31 代表
        # ("props/kitchen/giant_press_board.glb", -2.9, 0.3, 0, 90, 1),
        ("props/kitchen/giant_heat_press.glb", -0.95, 0.4, 0, 180, 1),
        ("props/kitchen/giant_dryer.glb", 1.0, 0.25, 0, 180, 1),
        ("props/kitchen/work_table_moss.glb", 3.0, -0.2, 0, 0, 1),
        ("props/kitchen/press_board.glb", 2.78, -0.2, 0.47, 180, 1),
        ("props/kitchen/table_dryer_red.glb", 3.22, -0.17, 0.47, 180, 1),
        ("props/food/taiyaki.glb", 3.0, -0.36, 0.47, 30, 1),
        ("props/kitchen/pellet_sack_mix.glb", -2.45, -0.3, 0, 0, 1),     # 冷蔵庫の前を空けるよう、東へ寄せた
        ("props/kitchen/pellet_sack_brown.glb", -2.25, -0.5, 0, 40, 1),
        ("props/kitchen/pellet_sack_green.glb", 2.2, 0.6, 0, 0, 1),
        ("props/kitchen/pellet_sack_mix.glb", 3.85, 0.55, 0, -30, 1),
        ("props/kitchen/pellet_tray.glb", -1.95, -0.25, 0, 0, 1),
        ("props/kitchen/pellet_jar_yellow.glb", -2.1, 1.08, 0.45, 0, 1),
        ("props/kitchen/pellet_jar_mix.glb", -1.95, 1.1, 0.45, 0, 1),
        ("props/kitchen/pellet_jar_red.glb", -1.8, 1.07, 0.45, 0, 1),
        ("props/kitchen/pellet_bag.glb", 2.6, 1.08, 0.45, 10, 1),
        ("props/kitchen/pellet_bag.glb", 2.76, 1.1, 0.45, -15, 1),
        ("props/kitchen/pellet_jar_green.glb", 3.0, 1.08, 0.45, 0, 1),
    ],
}

# 当たり判定の箱: (場面, x, y, 幅, 奥行き, 高さ)。床に置く（2 倍する前の数）
COLLIDE = {"kitchen": [(-0.95, 0.4, 0.8, 0.98, 0.5), (1.0, 0.25, 1.35, 1.35, 1.73),
                       (3.0, -0.2, 0.9, 0.45, 0.47)]}

# 描くときだけ置く物（ロッジの床と奥の台の代わり）
STAGE = {"kitchen": [("props/room/floor_planks.glb", x, y, 0, 0, 1) for x in (-3, -1, 1, 3) for y in (-0.4, 1.6)]}


def color_hex(m):
    """読み込んだ素材の色を sRGB の 16 進に"""
    try:
        c = m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value
    except (KeyError, AttributeError):
        return "CCCCCC"
    out = ""
    for v in c[:3]:
        v = max(0.0, min(1.0, v))
        s = v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
        out += "%02X" % int(round(s * 255))
    return out


def dress(objs):
    """読み込んだ glb の素材（名前と色だけ）を、描くための手芸の素材に差し替える"""
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            if slot.material is None:
                continue
            if slot.material.node_tree and any(n.type == "TEX_IMAGE" for n in slot.material.node_tree.nodes):
                continue   # 焼いた画像のある素材は、そのまま使う
            role = slot.material.name.split(".")[0]
            if role not in C.HEX and role not in C.LM.HEX:
                C.HEX[role] = color_hex(slot.material)
            slot.material = C.mat(role)


def place(path, x, y, z, rot, sc):
    x, y, z = x * X, y * X, z * X
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(GAME, path))
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None or o.parent not in new]
    for r in roots:
        r.location = (x, y, z)
        r.rotation_mode = "XYZ"
        r.rotation_euler = (0, 0, math.radians(rot))
        r.scale = (sc, sc, sc)
    dress(new)
    return new


def tscn(name, items):
    """Godot の場面: glb を並べて、props_set.gd で素材を着せる"""
    paths = sorted({p for p, *_ in items})
    ids = {p: i + 2 for i, p in enumerate(paths)}
    lines = ["[gd_scene load_steps=%d format=3]" % (len(paths) + 2), "",
             '[ext_resource type="Script" path="res://props_set.gd" id="1"]']
    for p in paths:
        lines.append('[ext_resource type="PackedScene" path="res://%s" id="%d"]' % (p, ids[p]))
    boxes = COLLIDE.get(name, [])
    if boxes:   # 当たり判定の箱の形（大きさごと）
        lines[0] = "[gd_scene load_steps=%d format=3]" % (len(paths) + 2 + len(boxes))
        lines += [""]
        for i, (x, y, w, d, h) in enumerate(boxes):
            lines += ['[sub_resource type="BoxShape3D" id="box_%d"]' % i, "size = Vector3(%.3f, %.3f, %.3f)" % (w * X, h * X, d * X), ""]
        lines.pop()
    lines += ["", '[node name="%s" type="Node3D"]' % "".join(w.capitalize() for w in name.split("_")),
              'script = ExtResource("1")']
    counts = {}
    for (p, x, y, z, rot, sc) in items:
        base = os.path.splitext(os.path.basename(p))[0]
        counts[base] = counts.get(base, 0) + 1
        nm = base if counts[base] == 1 else "%s_%d" % (base, counts[base])
        t = math.radians(rot)
        c, s = math.cos(t) * sc, math.sin(t) * sc
        x, y, z = x * X, y * X, z * X
        # Blender (x, y, z) → Godot (x, z, -y)。z 軸まわりの回転は Godot の y 軸まわりの同じ角度。
        # .tscn の Transform3D は基底の行を順に書く: [[c, 0, s], [0, 1, 0], [-s, 0, c]]
        lines += ["", '[node name="%s" parent="." instance=ExtResource("%d")]' % (nm, ids[p]),
                  "transform = Transform3D(%.4f, 0, %.4f, 0, %.4f, 0, %.4f, 0, %.4f, %.4f, %.4f, %.4f)"
                  % (c, s, sc, -s, c, x, z, -y)]
    if boxes:
        lines += ["", '[node name="Collide" type="StaticBody3D" parent="."]']
        for i, (x, y, w, d, h) in enumerate(boxes):
            lines += ["", '[node name="box_%d" type="CollisionShape3D" parent="Collide"]' % i,
                      "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4f, %.4f, %.4f)" % (x * X, h * X / 2, -y * X),
                      'shape = SubResource("box_%d")' % i]
    out = os.path.join(GAME, "props", "sets", name + ".tscn")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", out)


SET_TRIS = 20000   # 1 組の三角の目安（ゲーム開発のセッションの目安: 1 組あたり描画 10 回以下・三角 2 万以下）


def merge(name, items):
    """組の小物を、素材の組（felt・wood・光る物・ガラス・雪）ごとに 1 つの形に結合し、組ごとに 1 枚の画像へ焼き直して、
    game/props/sets/<名前>.glb に書き出す。目印（灯り・湯気・調理・座る所）は組の根元へ移す。
    調理の道具の湯気の目印は steam_cook_<番号>（Godot は調理中だけ煙を出す）"""
    before = set(bpy.data.objects)
    roots = []
    for it in items:
        new = place(*it)
        roots += [o for o in new if o.parent is None or o.parent not in new]
    objs = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new("prop_set_" + name, None)
    C.coll("prop").objects.link(root)
    bpy.context.view_layer.update()
    k = 0
    for r in roots:
        kids = K.descendants(r)
        cooking = any(o.name.startswith("cook") for o in kids)
        for e in [o for o in kids if o.type == "EMPTY" and not o.children]:
            mw = e.matrix_world.copy()
            base = e.name.split(".")[0]
            if "steam" in base and cooking:
                base = "steam_cook_%d" % k
                k += 1
            e.parent = root
            e.matrix_world = mw
            e.name = base
    meshes = [o for o in objs if o.type == "MESH"]
    groups = {}
    for o in meshes:
        groups.setdefault(o.active_material.name.split(".")[0] if o.active_material else "felt", []).append(o)
    tris = {g: sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in ms) for g, ms in groups.items()}
    total = max(1, sum(tris.values()))
    K._cycles()
    K.BAKE["max"] = 2048
    lows = []
    for g, ms in groups.items():
        low = K._join_world(ms, "prop_%s_%s" % (name, g))
        K._decimate(low, max(150, int(min(total, SET_TRIS) * tris[g] / total)))
        if g in ("glass", "snow"):
            low.data.materials.append(ms[0].active_material)
            K._flat(low, g)
        else:
            K._bake_to(low, ms, g, 0.03)
        lows.append(low)
    for o in meshes + [r for r in roots if r.name in bpy.data.objects]:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o)
    for o in [o for o in bpy.data.objects if o not in before and o.type == "EMPTY" and o is not root and o.parent is None]:
        bpy.data.objects.remove(o)
    for low in lows:
        low.parent = root
    out = os.path.join(GAME, "props", "sets", name + ".glb")
    keep = [root] + K.descendants(root)
    print("triangles", name, C.tri_count(keep), "groups", len(lows))
    C.export(keep, out, root)
    for o in keep:
        bpy.data.objects.remove(o)
    return "props/sets/%s.glb" % name


OFFSET = {"hearth_nook": (-7.0, 0.0), "kotatsu_room": (0.0, 0.0), "dining": (7.0, 0.0), "kitchen": (0.0, 8.0)}   # 2 倍する前の位置
chosen = [n for n in SCENES if not A.scenes or n in A.scenes.split(",")]
if not A.no_tscn:   # 組ごとに 1 つの glb に結合して、Godot の場面を書く
    for name in chosen:
        tscn(name, [(merge(name, SCENES[name]), 0, 0, 0, 0, 1)])
for name in chosen:   # 描く: 結合した組（ゲームと同じ物）と、ロッジの床と奥の台の代わり
    ox, oy = OFFSET[name]
    if name == "kitchen":   # ロッジの奥の台の代わり（描くときだけ）
        bk = C.M("back_counter", "wood_dark", "stage")
        bmesh.ops.create_cube(bk.bm, size=1.0, matrix=Matrix.Translation((0, (1.1 + oy) * X, 0.45)) @ Matrix.Diagonal((15.6, 0.7, 0.9, 1)))
        bk.done(smooth=False)
    for (p, x, y, z, rot, sc) in [("props/sets/%s.glb" % name, 0, 0, 0, 0, 1)] + STAGE.get(name, []):
        new = place(p, x + ox, y + oy, z, rot, sc)
        for o in new:   # 灯りの目印に、描くときだけ暖色の灯り
            if o.type == "EMPTY" and o.name.split(".")[0].startswith("light"):
                L = bpy.data.objects.new("bulb", bpy.data.lights.new("bulb", "POINT"))
                C.coll("stage").objects.link(L)
                L.location = o.matrix_world.translation
                fire = "fire" in o.name
                L.data.energy = 140 if fire else 60
                L.data.color = (1.0, 0.6, 0.3) if fire else (1.0, 0.72, 0.46)
                L.data.shadow_soft_size = 0.15

bpy.context.view_layer.update()
K.interior_light(0.45)
cams = {
    "hearth": ((-14.0, 9.2, 3.4), (-14.0, 0.4, 1.6), 30),
    "kotatsu": ((3.8, 7.2, 4.4), (0.0, 0.0, 1.2), 30),
    "dining": ((15.2, 7.2, 3.4), (14.2, -0.4, 2.6), 30),
    "kitchen": ((3.0, 9.6, 4.6), (0.0, 15.6, 0.7), 22),
    "kitchen_near": ((-3.4, 12.2, 2.3), (-4.6, 15.6, 1.0), 30),
}
C.setup_render(A.size)
bpy.context.scene.view_settings.exposure = 0.2
for v in [v for v in A.views.split(",") if v in cams]:
    loc, tgt, lens = cams[v]
    C.render(loc, tgt, lens, os.path.abspath("%s-%s.png" % (A.prefix, v)))
