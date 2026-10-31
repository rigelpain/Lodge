"""見本の人形に骨を入れ、色と凹凸を画像に焼いて、ゲーム用の glb に書き出す。build_dolls.py の --export から呼ぶ。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/build_dolls.py -- --doll kasa --export game/person

1. 曲線は面にし、モディファイアを形に焼き込む（毛羽の毛は落とす。ゲームでは別に描く）
2. 部品ごとに骨への重みを付ける: 腕・袖・脚は骨に沿って曲がる。胴の服は胴と腰だけ。頭まわりは頭に固定
3. 全部を 1 つの形にまとめ、UV を開き、Cycles（CPU）で色（光なし）と法線を 1 枚ずつ焼く。くぼみの陰（AO）も焼いて色に掛ける
4. 素材を焼いた画像の 1 つにして、骨ごと glb に書き出す
骨の名前は 7 体で同じ（ゲームの doll.gd が同じ名前で動かす）。
4 回目のキャラ案の 4 体（robo・musha・ningyo・golem）は person/ideas/characters/roughs.py の --export から呼ぶ。
部品の名前がちがうので、重みの付け方は RULES に人形ごとに書く。
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

AO_STRENGTH = 0.55   # くぼみの陰の濃さ（0 で陰なし）

# 関節（Blender の座標。前は +Y）。.R が右（+X）
JOINTS = {
    "origami": {"pelvis": (0, 0, 0.78), "chest": (0, 0, 0.92), "neck": (0, 0, 1.06), "head": (0, 0, 1.12), "top": (0, 0, 1.44),
                "shoulder": (0.17, 0, 0.96), "elbow": (0.22, 0.07, 0.74), "wrist": (0.12, 0.2, 0.68), "hand": (0.1, 0.25, 0.68),
                "hip": (0.08, 0, 0.75), "knee": (0.08, 0.01, 0.4), "ankle": (0.08, 0.0, 0.06), "toe": (0.08, 0.16, 0.01)},
    "kasa": {"pelvis": (0, 0, 0.55), "chest": (0, 0, 0.72), "neck": (0, 0, 0.86), "head": (0, 0, 0.9), "top": (0, 0, 1.2),
             "shoulder": (0.13, 0, 0.84), "elbow": (0.24, 0.06, 0.7), "wrist": (0.05, 0.22, 0.55), "hand": (0.02, 0.25, 0.5),
             "hip": (0.07, 0, 0.5), "knee": (0.07, 0.03, 0.27), "ankle": (0.06, 0.08, 0.04), "toe": (0.06, 0.16, 0.01)},
    "news": {"pelvis": (0, 0, 0.3), "chest": (0, 0, 0.46), "neck": (0, 0, 0.56), "head": (0, 0, 0.6), "top": (0, 0, 1.0),
             "shoulder": (0.15, 0, 0.56), "elbow": (0.22, 0.03, 0.42), "wrist": (0.25, 0.07, 0.29), "hand": (0.255, 0.075, 0.2),
             "hip": (0.08, 0, 0.14), "knee": (0.083, 0.005, 0.085), "ankle": (0.085, 0.01, 0.035), "toe": (0.085, 0.1, 0.02)},
    # 紙のロボット: 箱の頭は 0.565〜0.775。蛇腹の腕の先に大きなこぶし、短く太い脚
    "robo": {"pelvis": (0, 0, 0.26), "chest": (0, 0, 0.42), "neck": (0, 0, 0.53), "head": (0, 0, 0.575), "top": (0, 0, 0.92),
             "shoulder": (0.19, 0, 0.49), "elbow": (0.215, 0.02, 0.39), "wrist": (0.228, 0.035, 0.3), "hand": (0.232, 0.047, 0.2),
             "hip": (0.088, 0, 0.23), "knee": (0.088, 0, 0.155), "ankle": (0.088, 0, 0.07), "toe": (0.088, 0.11, 0.03)},
    # 折り紙の武者: 2.5 頭身。顔は 0.435〜0.685、三日月の先が 0.9。脚は袴の下で短い
    "musha": {"pelvis": (0, 0, 0.28), "chest": (0, 0, 0.39), "neck": (0, 0, 0.44), "head": (0, 0, 0.46), "top": (0, 0, 0.9),
              "shoulder": (0.13, 0, 0.44), "elbow": (0.19, 0.045, 0.33), "wrist": (0.172, 0.11, 0.265), "hand": (0.172, 0.125, 0.21),
              "hip": (0.066, 0, 0.2), "knee": (0.066, 0.004, 0.13), "ankle": (0.066, 0.008, 0.05), "toe": (0.066, 0.09, 0.02)},
    # 絹の人形: 脚は裙の中で見えない。靴の先だけ前に出る
    "ningyo": {"pelvis": (0, 0, 0.4), "chest": (0, 0, 0.55), "neck": (0, 0, 0.63), "head": (0, 0, 0.65), "top": (0, 0, 0.95),
               "shoulder": (0.11, 0, 0.6), "elbow": (0.2, 0.035, 0.47), "wrist": (0.19, 0.115, 0.4), "hand": (0.185, 0.15, 0.37),
               "hip": (0.06, 0.02, 0.36), "knee": (0.06, 0.08, 0.2), "ankle": (0.06, 0.16, 0.035), "toe": (0.06, 0.235, 0.02)},
    # 継ぎはぎの巨人: 頭は肩のあいだに低く小さく。腕は太く長い
    "golem": {"pelvis": (0, 0.01, 0.45), "chest": (0, 0.04, 0.75), "neck": (0, 0.1, 1.04), "head": (0, 0.12, 1.06), "top": (0, 0.12, 1.25),
              "shoulder": (0.42, 0.04, 0.94), "elbow": (0.47, 0.1, 0.69), "wrist": (0.45, 0.19, 0.46), "hand": (0.45, 0.22, 0.33),
              "hip": (0.17, 0, 0.36), "knee": (0.17, 0, 0.24), "ankle": (0.17, 0.02, 0.11), "toe": (0.17, 0.2, 0.04)},
}

# 4 回目のキャラ案の部品の名前 → 重みの付け方。上から順に、名前の頭が合ったものを使う。
# ("side", 骨) は左右の骨のうち形の真ん中に近い側に固定。合うものがなければ ("near",)
RULES = {
    "robo": [
        (("head", "eyehole", "eye_frame", "box_flap", "antenna"), ("rigid", "head")),
        (("neck",), ("rigid", "neck")),
        (("torso", "chest_"), ("rigid", "chest")),
        (("pelvis", "waist_rope", "rope_"), ("rigid", "hips")),
        (("shoulder", "split_pin"), ("side", "upper_arm")),
        (("arm",), ("arm",)),
        (("wrist_twine",), ("side", "forearm")),
        (("fist", "thumb", "finger_line"), ("side", "hand")),
        (("leg", "knee_twine"), ("leg",)),
        (("foot",), ("side", "foot")),
    ],
    "musha": [
        (("head", "eye", "kabuto", "suji", "hoshi", "rim_st", "tehen", "visor", "shikoro", "fukigaeshi", "fk_", "maedate", "shinobi"), ("rigid", "head")),
        (("do_", "munaita"), ("bend", ["chest", "hips"])),
        (("watagami", "sode"), ("side", "upper_arm")),
        (("kote",), ("arm",)),
        (("tekkou",), ("side", "forearm")),
        (("fist",), ("side", "hand")),
        (("kusazuri", "obi", "hakama"), ("rigid", "hips")),
        (("suneate", "sune_"), ("side", "shin")),
        (("tabi", "waraji"), ("side", "foot")),
    ],
    "ningyo": [
        (("head", "eye", "hair", "bun", "buyao", "pearl", "silk_flower"), ("rigid", "head")),
        (("ru", "eri", "bow_knot", "bow_loop", "pibo"), ("rigid", "chest")),
        (("qun", "bow_tail"), ("bend", ["chest", "hips"])),
        (("jade", "jinbu"), ("rigid", "hips")),
        (("xiu",), ("arm",)),
        (("hand",), ("side", "hand")),
        (("shoe",), ("side", "foot")),
    ],
    "golem": [
        (("head", "eye", "snow_head"), ("rigid", "head")),
        (("scarf",), ("rigid", "neck")),
        (("pelvis", "waist_rope", "rope_"), ("rigid", "hips")),
        (("torso", "body_patch"), ("bend", ["chest", "hips"])),
        (("shoulder", "snow_sh", "arm_seam"), ("side", "upper_arm")),
        (("wrist_seam",), ("side", "forearm")),
        (("arm",), ("arm",)),
        (("fist", "thumb"), ("side", "hand")),
        (("hip_seam",), ("side", "thigh")),
        (("leg",), ("leg",)),
        (("foot",), ("side", "foot")),
    ],
}


def joints(doll):
    j = {}
    for k, v in JOINTS[doll].items():
        if k in ("pelvis", "chest", "neck", "head", "top"):
            j[k] = Vector(v)
        else:
            j[k + ".R"] = Vector(v)
            j[k + ".L"] = Vector((-v[0], v[1], v[2]))
    return j


def bones():
    b = {"hips": ("pelvis", "chest", None), "chest": ("chest", "neck", "hips"), "neck": ("neck", "head", "chest"),
         "head": ("head", "top", "neck")}
    for s in ("L", "R"):
        b["upper_arm." + s] = ("shoulder." + s, "elbow." + s, "chest")
        b["forearm." + s] = ("elbow." + s, "wrist." + s, "upper_arm." + s)
        b["hand." + s] = ("wrist." + s, "hand." + s, "forearm." + s)
        b["thigh." + s] = ("hip." + s, "knee." + s, "hips")
        b["shin." + s] = ("knee." + s, "ankle." + s, "thigh." + s)
        b["foot." + s] = ("ankle." + s, "toe." + s, "shin." + s)
    return b


# 部品の名前 → 重みの付け方。("bend", 骨の候補) は近い 2 本を混ぜて曲がる、("rigid", 骨) は 1 本に固定、
# ("near",) は形の真ん中にいちばん近い骨に固定
def rule(name):
    n = name.lower()
    head_parts = ("head", "eye", "hair", "hood", "bangs", "lock", "kasa", "ring", "blush", "circle")
    if any(n.startswith(h) for h in head_parts):
        return ("rigid", "head")
    if n.startswith(("arm.", "sleeve")):
        return ("arm",)
    if n.startswith("leg"):
        return ("leg",)
    if n.startswith(("skirt", "kimono", "panel", "apron", "body", "obi", "collar")):
        return ("bend", ["hips", "chest"])
    if n.startswith(("blouse", "cape", "wrap", "torus", "strap")):
        return ("rigid", "chest")
    if n.startswith("neck"):
        return ("rigid", "neck")
    return ("near",)


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def realize(ob):
    """曲線は面に、モディファイアは形に焼き込み、毛羽の毛は外す"""
    for m in list(ob.modifiers):
        if m.type == "PARTICLE_SYSTEM":
            ob.modifiers.remove(m)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    new = bpy.data.objects.new(ob.name, me)
    new.matrix_world = ob.matrix_world.copy()
    bpy.context.scene.collection.objects.link(new)
    bpy.data.objects.remove(ob)
    # 位置・回転・大きさを形に焼く
    new.data.transform(new.matrix_world)
    new.matrix_world.identity()
    return new


def doll_rule(doll, name):
    n = name.lower()
    for heads, r in RULES.get(doll, []):
        if n.startswith(heads):
            return r
    return ("near",) if doll in RULES else rule(name)


def weigh(ob, J, B, doll=""):
    for name in B:
        ob.vertex_groups.new(name=name)
    r = doll_rule(doll, ob.name)
    if r[0] == "side":
        c = sum((v.co for v in ob.data.vertices), Vector()) / max(1, len(ob.data.vertices))
        r = ("rigid", r[1] + (".R" if c.x > 0 else ".L"))
    if r[0] == "near":
        c = sum((v.co for v in ob.data.vertices), Vector()) / max(1, len(ob.data.vertices))
        best = min(B, key=lambda n: seg_dist(c, J[B[n][0]], J[B[n][1]]))
        r = ("rigid", best)
    if r[0] in ("arm", "leg"):
        c = sum((v.co for v in ob.data.vertices), Vector()) / max(1, len(ob.data.vertices))
        s = "R" if c.x > 0 else "L"
        cand = ["upper_arm." + s, "forearm." + s, "hand." + s] if r[0] == "arm" else ["thigh." + s, "shin." + s, "foot." + s]
        r = ("bend", cand)
    if r[0] == "rigid":
        ob.vertex_groups[r[1]].add([v.index for v in ob.data.vertices], 1.0, "REPLACE")
        return
    for v in ob.data.vertices:
        ds = sorted((seg_dist(v.co, J[B[n][0]], J[B[n][1]]), n) for n in r[1])
        near = ds[:2]
        ws = [1.0 / max(d, 0.01) ** 4 for d, _ in near]
        tot = sum(ws)
        for (d, n), w in zip(near, ws):
            ob.vertex_groups[n].add([v.index], w / tot, "REPLACE")


def bake_textures(ob, name, px):
    """色（光なし）と法線を画像に焼く。Cycles を CPU で"""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 4
    sc.render.bake.margin = 6
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    out = {}
    for kind in ("color", "normal"):
        img = bpy.data.images.new("%s_%s" % (name, kind), px, px, alpha=False)
        if kind == "normal":
            img.colorspace_settings.name = "Non-Color"
        for m in ob.data.materials:
            m.use_nodes = True
            t = m.node_tree
            for n in [n for n in t.nodes if n.name == "bake_target"]:
                t.nodes.remove(n)
            n = t.nodes.new("ShaderNodeTexImage")
            n.name = "bake_target"
            n.image = img
            t.nodes.active = n
        if kind == "color":
            sc.render.bake.use_pass_direct = False
            sc.render.bake.use_pass_indirect = False
            sc.render.bake.use_pass_color = True
            bpy.ops.object.bake(type="DIFFUSE")
        else:
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
        img.pack()
        out[kind] = img
    # くぼみの陰（頭巾の内側、袖や裾の下、首まわり）を色に掛ける。どんな光の下でも立体として読める
    ao = bpy.data.images.new("%s_ao" % name, px, px, alpha=False)
    ao.colorspace_settings.name = "Non-Color"
    for m in ob.data.materials:
        n = m.node_tree.nodes["bake_target"]
        n.image = ao
        m.node_tree.nodes.active = n
    sc.cycles.samples = 32
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = 0.12   # 陰が届く距離（m）。人形の大きさに合わせて短く
    bpy.ops.object.bake(type="AO")
    import numpy as np
    col = np.empty(px * px * 4, np.float32)
    out["color"].pixels.foreach_get(col)
    a = np.empty(px * px * 4, np.float32)
    ao.pixels.foreach_get(a)
    shade = 1.0 - AO_STRENGTH * (1.0 - a.reshape(-1, 4)[:, 0])
    col = col.reshape(-1, 4)
    col[:, :3] *= shade[:, None]
    out["color"].pixels.foreach_set(col.ravel())
    out["color"].pack()
    return out


def export(doll, folder, px=2048):
    J = joints(doll)
    B = bones()
    sc = bpy.context.scene
    # 撮影用のものを外す
    for ob in list(sc.objects):
        if ob.type in ("LIGHT", "CAMERA") or ob.name.startswith("Plane"):
            bpy.data.objects.remove(ob)
    parts = []
    for ob in list(sc.objects):
        if ob.type in ("MESH", "CURVE", "META"):
            parts.append(realize(ob))
    parts = [ob for ob in parts if len(ob.data.vertices) > 0]   # 融け合った綿の雪（メタボール）は 1 つにまとまり、残りは空になる
    for ob in parts:
        weigh(ob, J, B, doll)
    # 1 つにまとめる
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    doll_ob = bpy.context.view_layer.objects.active
    doll_ob.name = doll
    imgs = bake_textures(doll_ob, doll, px)
    # 素材を焼いた画像の 1 つに
    m = bpy.data.materials.new(doll + "_baked")
    m.use_nodes = True
    t = m.node_tree
    b = t.nodes["Principled BSDF"]
    tc = t.nodes.new("ShaderNodeTexImage")
    tc.image = imgs["color"]
    t.links.new(tc.outputs["Color"], b.inputs["Base Color"])
    tn = t.nodes.new("ShaderNodeTexImage")
    tn.image = imgs["normal"]
    nm = t.nodes.new("ShaderNodeNormalMap")
    t.links.new(tn.outputs["Color"], nm.inputs["Color"])
    t.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.9
    b.inputs["Specular IOR Level"].default_value = 0.2
    doll_ob.data.materials.clear()
    doll_ob.data.materials.append(m)
    for p in doll_ob.data.polygons:
        p.material_index = 0
    # 骨
    arm = bpy.data.armatures.new(doll + "_rig")
    rig = bpy.data.objects.new(doll + "_rig", arm)
    sc.collection.objects.link(rig)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, tl, p) in B.items():
        e = arm.edit_bones.new(name)
        e.head = J[h]
        e.tail = J[tl]
        e.roll = 0.0
    for name, (h, tl, p) in B.items():
        if p:
            arm.edit_bones[name].parent = arm.edit_bones[p]
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = doll_ob.modifiers.new("rig", "ARMATURE")
    mod.object = rig
    doll_ob.parent = rig
    # 書き出し
    os.makedirs(folder, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    doll_ob.select_set(True)
    bpy.context.view_layer.objects.active = rig
    path = os.path.abspath(os.path.join(folder, doll + ".glb"))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=False, export_apply=False)
    print("wrote", path)
