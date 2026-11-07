"""人（プレイヤーと仲間）を Blender で組む。外の素材は使わず、すべてコードで作る。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P person/build_person.py -- \
        --views front,quarter,side,back --prefix person/renders/01

紙の体は折り紙の多面体: 骨組みの線に太さを付けて一枚の形にし、三角の面に崩して平らに塗る。
服はフェルト: やわらかく厚みのある面に、縁をクリームの糸でかがる。
骨は一本の armature。体と上着は骨に沿って曲がり（重みは骨までの距離で決める）、頭・手袋・長靴は骨に固定する。
向き: 前は +Y（Blender）。glTF では -Z（Godot の前）になる。
"""
import argparse
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ap = argparse.ArgumentParser()
ap.add_argument("--views", default="front,quarter,side,back")
ap.add_argument("--pose", default="rest", help="rest / wave / push / walk")
ap.add_argument("--prefix", default="/tmp/person")
ap.add_argument("--size", default="700x1000")
ap.add_argument("--coat", default="B45A4A", help="上着の色（sRGB の 16 進）")
ap.add_argument("--export", default="", help="この場所に person.glb を書き出す（描画しない）")
ap.add_argument("--blend", default="")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
random.seed(7)

# ---------------------------------------------------------------- 寸法（m）。3.5 頭身、背 1.6 m
H = 1.60
HEAD = H / 3.5
J = {   # 関節。x は右、y は前、z は上
    "pelvis": (0, 0, 0.60), "chest": (0, -0.01, 0.90), "neck": (0, 0, 1.10), "head": (0, 0.0, 1.14),
    "top": (0, 0.0, 1.14 + HEAD),
    "shoulder.R": (0.17, 0, 1.03), "elbow.R": (0.23, 0.0, 0.81), "wrist.R": (0.26, 0.02, 0.62), "hand.R": (0.27, 0.03, 0.53),
    "hip.R": (0.085, 0, 0.56), "knee.R": (0.09, 0.015, 0.31), "ankle.R": (0.09, 0, 0.075), "toe.R": (0.09, 0.11, 0.03),
}
for k in list(J):
    if k.endswith(".R"):
        x, y, z = J[k]
        J[k[:-2] + ".L"] = (-x, y, z)
J = {k: Vector(v) for k, v in J.items()}

# 骨: 名前 → (頭, 尾, 親)
BONES = {
    "hips": ("pelvis", "chest", None),
    "chest": ("chest", "neck", "hips"),
    "neck": ("neck", "head", "chest"),
    "head": ("head", "top", "neck"),
}
for s in ("L", "R"):
    BONES["upper_arm." + s] = ("shoulder." + s, "elbow." + s, "chest")
    BONES["forearm." + s] = ("elbow." + s, "wrist." + s, "upper_arm." + s)
    BONES["hand." + s] = ("wrist." + s, "hand." + s, "forearm." + s)
    BONES["thigh." + s] = ("hip." + s, "knee." + s, "hips")
    BONES["shin." + s] = ("knee." + s, "ankle." + s, "thigh." + s)
    BONES["foot." + s] = ("ankle." + s, "toe." + s, "shin." + s)


def lin(h):
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


# ---------------------------------------------------------------- 素材（描画の見本用。ゲームでは名前で look.gd に差し替える）
def material(name, hexcol, kind):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    t = m.node_tree
    b = t.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(hexcol)
    if kind == "paper":
        b.inputs["Roughness"].default_value = 0.75
        if "Subsurface Weight" in b.inputs:
            b.inputs["Subsurface Weight"].default_value = 0.12
            b.inputs["Subsurface Radius"].default_value = (0.02, 0.018, 0.012)
        # 紙の地: 細かい繊維の凹凸
        no = t.nodes.new("ShaderNodeTexNoise")
        no.inputs["Scale"].default_value = 320.0
        no.inputs["Detail"].default_value = 8.0
        bp = t.nodes.new("ShaderNodeBump")
        bp.inputs["Strength"].default_value = 0.08
        t.links.new(no.outputs["Fac"], bp.inputs["Height"])
        t.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    elif kind == "felt":
        b.inputs["Roughness"].default_value = 1.0
        if "Sheen Weight" in b.inputs:
            b.inputs["Sheen Weight"].default_value = 0.8
            b.inputs["Sheen Roughness"].default_value = 0.35
        b.inputs["Specular IOR Level"].default_value = 0.1
        vo = t.nodes.new("ShaderNodeTexVoronoi")
        vo.inputs["Scale"].default_value = 260.0
        no = t.nodes.new("ShaderNodeTexNoise")
        no.inputs["Scale"].default_value = 600.0
        no.inputs["Detail"].default_value = 6.0
        mx = t.nodes.new("ShaderNodeMath")
        mx.operation = "ADD"
        t.links.new(vo.outputs["Distance"], mx.inputs[0])
        t.links.new(no.outputs["Fac"], mx.inputs[1])
        bp = t.nodes.new("ShaderNodeBump")
        bp.inputs["Strength"].default_value = 0.4
        bp.inputs["Distance"].default_value = 0.002
        t.links.new(mx.outputs[0], bp.inputs["Height"])
        t.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    else:
        b.inputs["Roughness"].default_value = 0.6
    return m


MAT = {
    "paper": material("paper", "F2EADB", "paper"),
    "coat": material("felt_coat", A.coat, "felt"),
    "mitt": material("felt_mitt", A.coat, "felt"),
    "boots": material("felt_boots", "5C4636", "felt"),
    "thread": material("thread", "F1E7CF", "felt"),
    "button": material("button", "3A2C22", "plain"),
    "ink": material("ink", "241C18", "plain"),
}


# ---------------------------------------------------------------- 形の小道具
def link(ob):
    sc.collection.objects.link(ob)
    return ob


def bake(ob):
    """モディファイアを形に焼き込む"""
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    old = ob.data
    ob.data = me
    bpy.data.meshes.remove(old)
    return ob


def skin(name, pts, edges, radii, subdiv=1, smooth=False):
    """骨組みの線（pts と edges）に太さ（radii: (x, y)）を付けた一枚の形"""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in pts], edges, [])
    ob = link(bpy.data.objects.new(name, me))
    mod = ob.modifiers.new("skin", "SKIN")
    mod.branch_smoothing = 0.6
    mod.use_smooth_shade = smooth
    layer = me.skin_vertices[0].data
    for i, r in enumerate(radii):
        layer[i].radius = r
    layer[0].use_root = True
    if subdiv:
        s = ob.modifiers.new("sub", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv
    return bake(ob)


def facet(ob, ratio, seed=0):
    """折り紙の多面体にする: 三角の面に崩し（向きを少しずつ散らす）、平らに塗る"""
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bake(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    rnd = random.Random(seed)
    for v in bm.verts:
        v.co += v.normal * rnd.uniform(-0.004, 0.004)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def soften(ob, levels=1):
    for p in ob.data.polygons:
        p.use_smooth = True
    if levels:
        s = ob.modifiers.new("sub", "SUBSURF")
        s.levels = levels
        bake(ob)
        for p in ob.data.polygons:
            p.use_smooth = True
    return ob


def thicken(ob, t):
    mod = ob.modifiers.new("sol", "SOLIDIFY")
    mod.thickness = t
    mod.offset = -1.0
    mod.use_even_offset = True
    return bake(ob)


def set_mat(ob, key):
    ob.data.materials.clear()
    ob.data.materials.append(MAT[key])
    return ob


def drop_faces(ob, test):
    """test(中心, 法線) が真の面を消す（裾や袖口を開ける）。開いた縁の頂点を返す"""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    kill = [f for f in bm.faces if test(f.calc_center_median(), f.normal)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    edge = [v.co.copy() for v in bm.verts if v.is_boundary]
    bm.to_mesh(ob.data)
    bm.free()
    return edge


# ---------------------------------------------------------------- 紙の体
def build_body():
    names = ["pelvis", "chest", "neck", "shoulder.R", "elbow.R", "wrist.R", "hand.R", "shoulder.L", "elbow.L", "wrist.L",
             "hand.L", "hip.R", "knee.R", "ankle.R", "toe.R", "hip.L", "knee.L", "ankle.L", "toe.L"]
    idx = {n: i for i, n in enumerate(names)}
    pts = [J[n] for n in names]
    pts[idx["neck"]] = J["neck"] + Vector((0, 0, 0.05))
    for s in ("R", "L"):   # 手先とつま先は手袋と長靴の中に収める
        pts[idx["hand." + s]] = J["wrist." + s] + (J["hand." + s] - J["wrist." + s]) * 0.5
        pts[idx["toe." + s]] = J["ankle." + s] + (J["toe." + s] - J["ankle." + s]) * 0.5
    e = [("pelvis", "chest"), ("chest", "neck")]
    for s in ("R", "L"):
        e += [("chest", "shoulder." + s), ("shoulder." + s, "elbow." + s), ("elbow." + s, "wrist." + s), ("wrist." + s, "hand." + s),
              ("pelvis", "hip." + s), ("hip." + s, "knee." + s), ("knee." + s, "ankle." + s), ("ankle." + s, "toe." + s)]
    R = {"pelvis": (0.13, 0.10), "chest": (0.14, 0.10), "neck": (0.045, 0.045)}
    for s in ("R", "L"):
        R.update({"shoulder." + s: (0.04, 0.04), "elbow." + s: (0.035, 0.035), "wrist." + s: (0.028, 0.026), "hand." + s: (0.02, 0.015),
                  "hip." + s: (0.06, 0.06), "knee." + s: (0.045, 0.045), "ankle." + s: (0.032, 0.032), "toe." + s: (0.02, 0.018)})
    ob = skin("body", pts, [(idx[a], idx[b]) for a, b in e], [R[n] for n in names], subdiv=1)
    facet(ob, 0.45, 1)
    return set_mat(ob, "paper")


# 頭: 卵形の多面体に、鼻すじの山折りと、ほお・あごの面を折る
def build_head():
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0)
    ob = bpy.context.object
    ob.name = "head"
    w, d, h = HEAD * 0.42, HEAD * 0.40, HEAD * 0.47
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for v in bm.verts:
        x, y, z = v.co
        # あごへ細く、頭のてっぺんは丸く広い
        k = 1.0 - 0.18 * max(0.0, -z) ** 1.5
        x *= k
        y *= k
        # 顔は前で平らに
        if y > 0.55:
            y = 0.55 + (y - 0.55) * 0.35
        # 鼻すじ: 前の真ん中を山に折る
        if y > 0.3 and -0.45 < z < 0.25:
            ridge = max(0.0, 1.0 - abs(x) / 0.18)
            y += 0.16 * ridge * (1.0 - abs(z + 0.1) / 0.35)
        v.co = Vector((x * w, y * d, z * h))
    bm.to_mesh(ob.data)
    bm.free()
    ob.location = J["head"] + Vector((0, 0.01, h * 0.98))
    facet(ob, 0.55, 2)
    return set_mat(ob, "paper")


def surface_point(ob, origin, direction):
    """ob の表面で、origin から direction に進んで当たる所と法線（世界座標）"""
    inv = ob.matrix_world.inverted()
    ok, loc, nrm, _ = ob.ray_cast(inv @ origin, (inv.to_3x3() @ direction).normalized())
    if not ok:
        return origin, direction
    return ob.matrix_world @ loc, (ob.matrix_world.to_3x3() @ nrm).normalized()


def build_eyes(head):
    """目: 黒い糸でかがった小さな結び目（フレンチノット）。ほんの少し眉の下に"""
    out = []
    c = head.location
    for s in (1, -1):
        p, n = surface_point(head, c + Vector((s * HEAD * 0.13, 0, HEAD * 0.03)), Vector((0, 1, 0)))
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=HEAD * 0.032, location=p + n * 0.002)
        e = bpy.context.object
        e.name = "eye." + ("R" if s > 0 else "L")
        e.scale = (1.0, 0.55, 1.15)
        bake(e)
        soften(e, 0)
        out.append(set_mat(e, "ink"))
    return out


# ---------------------------------------------------------------- フェルトの服
def stitch_along(edge_pts, center, name, every=0.028, size=0.022, up=True):
    """縁をかがり縫い（ブランケットステッチ）: 縁から布の上へ短い糸の目が並ぶ"""
    if not edge_pts:
        return None
    # 縁の点を中心のまわりの角度で並べ、一定の間かくで糸を置く
    pts = sorted(edge_pts, key=lambda p: math.atan2(p.y - center.y, p.x - center.x))
    bm = bmesh.new()
    acc = 0.0
    prev = pts[0]
    for p in pts[1:] + pts[:1]:
        acc += (p - prev).length
        prev = p
        if acc < every:
            continue
        acc = 0.0
        out = Vector((p.x - center.x, p.y - center.y, 0)).normalized()
        a = p + out * 0.006
        b = a + Vector((0, 0, size if up else -size)) + out * 0.004
        mat = Matrix.Translation((a + b) / 2) @ (Vector((0, 0, 1)).rotation_difference(b - a)).to_matrix().to_4x4()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.0032, radius2=0.0032, depth=(b - a).length, matrix=mat)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    for p in ob.data.polygons:
        p.use_smooth = True
    return set_mat(ob, "thread")


def build_coat():
    """とんがり頭巾つきのフェルトの上着。すそは膝の上まで広がる。袖は手首まで"""
    pts = [J["chest"], J["pelvis"] + Vector((0, 0, 0.05)), Vector((0, 0.01, 0.36)), J["neck"] + Vector((0, 0, -0.01))]
    rad = [(0.165, 0.13), (0.19, 0.15), (0.29, 0.24), (0.08, 0.075)]
    e = [(0, 1), (1, 2), (0, 3)]
    for s in ("R", "L"):
        i = len(pts)
        pts += [J["shoulder." + s] + Vector((0, 0, -0.005)), J["elbow." + s], J["wrist." + s] + (J["wrist." + s] - J["elbow." + s]).normalized() * 0.02]
        rad += [(0.075, 0.075), (0.066, 0.066), (0.064, 0.064)]
        e += [(0, i), (i, i + 1), (i + 1, i + 2)]
    ob = skin("coat", pts, e, rad, subdiv=2, smooth=True)
    hem_z = 0.36
    hem = drop_faces(ob, lambda c, n: (c.z < hem_z + 0.02 and n.z < -0.6) or (c.z > J["neck"].z - 0.03 and n.z > 0.6))
    cuff = []
    for s in ("R", "L"):
        w, el = J["wrist." + s], J["elbow." + s]
        ax = (w - el).normalized()
        cuff += drop_faces(ob, lambda c, n, w=w, ax=ax: (c - w).dot(ax) > -0.01 and n.dot(ax) > 0.6)
    thicken(ob, 0.008)
    soften(ob, 0)
    set_mat(ob, "coat")
    out = [ob]
    out.append(stitch_along([p for p in hem if p.z < hem_z + 0.05], Vector((0, 0.01, hem_z)), "stitch_hem"))
    for s in ("R", "L"):
        w = J["wrist." + s]
        ring = [p for p in cuff if (p - w).length < 0.12]
        if ring:
            out.append(cuff_stitch(ring, w, J["elbow." + s], "stitch_cuff." + s))
    # 前の合わせに木のボタンを 2 つ
    for i, z in enumerate((0.86, 0.70)):
        p, n = surface_point(ob, Vector((0, 1.0, z)), Vector((0, -1, 0)))
        n = -n if n.y < 0 else n
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.022, depth=0.008, location=p + n * 0.004)
        b = bpy.context.object
        b.name = "button.%d" % i
        b.rotation_euler = Vector((0, 0, 1)).rotation_difference(n).to_euler()
        bake(b)
        out.append(set_mat(b, "button"))
    return out


def cuff_stitch(ring, w, el, name):
    ax = (w - el).normalized()
    bm = bmesh.new()
    c = sum(ring, Vector()) / len(ring)
    u = ax.orthogonal().normalized()
    v = ax.cross(u)
    ring = sorted(ring, key=lambda p: math.atan2((p - c).dot(v), (p - c).dot(u)))
    for k in range(0, len(ring), max(1, len(ring) // 14)):
        p = ring[k]
        out = (p - c - ax * (p - c).dot(ax)).normalized()
        a = p + out * 0.004 - ax * 0.002
        b = a - ax * 0.018
        mat = Matrix.Translation((a + b) / 2) @ (Vector((0, 0, 1)).rotation_difference(b - a)).to_matrix().to_4x4()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.003, radius2=0.003, depth=(b - a).length, matrix=mat)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    return set_mat(ob, "thread")


def build_hood(head):
    """とんがり頭巾: 頭をうしろから包み、先は上うしろへ折れて垂れる。顔のまわりは開く"""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=14, radius=1.0)
    ob = bpy.context.object
    ob.name = "hood"
    c = head.location
    r = HEAD * 0.6
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for v in bm.verts:
        x, y, z = v.co
        # とんがり: 上ほど細く高く、先はうしろへ
        if z > 0.2:
            t = (z - 0.2) / 0.8
            x *= 1.0 - 0.75 * t
            y = y * (1.0 - 0.75 * t) - 0.35 * t * t
            z = z + 0.9 * t * t
        v.co = Vector((x * r, y * r * 0.95 - r * 0.12, z * r))
    kill = [f for f in bm.faces if (f.calc_center_median().y > r * 0.32 and -r * 0.75 < f.calc_center_median().z < r * 0.62)
            or f.calc_center_median().z < -r * 0.62]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    edge = [v.co.copy() for v in bm.verts if v.is_boundary and v.co.y > 0]
    bm.to_mesh(ob.data)
    bm.free()
    ob.location = c + Vector((0, -0.005, HEAD * 0.02))
    soften(ob, 1)
    thicken(ob, 0.009)
    set_mat(ob, "coat")
    # 顔のまわりの縁をかがる
    face = [ob.matrix_world @ p for p in edge]
    st = None
    if face:
        bm = bmesh.new()
        cc = sum(face, Vector()) / len(face)
        face = sorted(face, key=lambda p: math.atan2(p.z - cc.z, p.x - cc.x))
        for k in range(0, len(face), 2):
            p = face[k]
            inward = (cc - p)
            inward.y = 0
            inward.normalize()
            a = p + Vector((0, 0.006, 0))
            b = a - inward * 0.02
            mat = Matrix.Translation((a + b) / 2) @ (Vector((0, 0, 1)).rotation_difference(b - a)).to_matrix().to_4x4()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.003, radius2=0.003, depth=(b - a).length, matrix=mat)
        me = bpy.data.meshes.new("stitch_hood")
        bm.to_mesh(me)
        bm.free()
        st = set_mat(link(bpy.data.objects.new("stitch_hood", me)), "thread")
    # 先に毛糸の玉（ぽんぽん）の代わりにフェルトの小さな玉
    tip = max((ob.matrix_world @ v.co for v in ob.data.vertices), key=lambda p: p.z - p.y * 0.5)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.03, location=tip)
    pom = set_mat(bpy.context.object, "thread")
    pom.name = "pompom"
    soften(pom, 0)
    return [o for o in (ob, st, pom) if o]


def build_mitts():
    out = []
    for s in ("R", "L"):
        w, h = J["wrist." + s], J["hand." + s]
        ax = (h - w).normalized()
        sx = 1 if s == "R" else -1
        palm = w + ax * 0.05
        tip = w + ax * 0.115
        thumb = palm + Vector((-sx * 0.03, 0.035, 0.0))
        ob = skin("mitt." + s, [w - ax * 0.01, palm, tip, thumb], [(0, 1), (1, 2), (1, 3)],
                  [(0.048, 0.045), (0.058, 0.04), (0.048, 0.034), (0.024, 0.022)], subdiv=2, smooth=True)
        soften(ob, 0)
        out.append(set_mat(ob, "mitt"))
    return out


def build_boots():
    out = []
    for s in ("R", "L"):
        a, t = J["ankle." + s], J["toe." + s]
        top = a + Vector((0, -0.005, 0.07))
        heel = Vector((a.x, a.y - 0.03, 0.035))
        ob = skin("boot." + s, [top, heel, Vector((a.x, a.y + 0.05, 0.035)), t + Vector((0, 0.015, 0.0))], [(0, 1), (1, 2), (2, 3)],
                  [(0.058, 0.058), (0.054, 0.05), (0.058, 0.045), (0.048, 0.034)], subdiv=2, smooth=True)
        soften(ob, 0)
        out.append(set_mat(ob, "boots"))
    return out


# ---------------------------------------------------------------- 骨と重み
def build_armature():
    arm = bpy.data.armatures.new("rig")
    ob = link(bpy.data.objects.new("rig", arm))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, p) in BONES.items():
        b = arm.edit_bones.new(name)
        b.head = J[h]
        b.tail = J[t]
        b.roll = 0.0
    for name, (h, t, p) in BONES.items():
        if p:
            arm.edit_bones[name].parent = arm.edit_bones[p]
            arm.edit_bones[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def weigh(ob, rig, allowed, rigid=None):
    """骨までの距離で重みを付ける（近い 2 本をなめらかに混ぜる）。rigid なら 1 本に固定"""
    for name in BONES:
        ob.vertex_groups.new(name=name)
    mw = ob.matrix_world
    for v in ob.data.vertices:
        if rigid:
            ob.vertex_groups[rigid].add([v.index], 1.0, "REPLACE")
            continue
        p = mw @ v.co
        ds = sorted((seg_dist(p, J[BONES[n][0]], J[BONES[n][1]]), n) for n in allowed)
        near = ds[:2]
        ws = [1.0 / max(d, 0.01) ** 4 for d, _ in near]
        tot = sum(ws)
        for (d, n), wgt in zip(near, ws):
            ob.vertex_groups[n].add([v.index], wgt / tot, "REPLACE")
    mod = ob.modifiers.new("rig", "ARMATURE")
    mod.object = rig
    ob.parent = rig


# ---------------------------------------------------------------- 姿勢（見本の絵のため）
def pose(rig, kind):
    pb = rig.pose.bones

    def rot(name, x=0.0, y=0.0, z=0.0):
        pb[name].rotation_mode = "XYZ"
        pb[name].rotation_euler = (math.radians(x), math.radians(y), math.radians(z))

    if kind == "wave":
        rot("upper_arm.R", 0, 0, 150)
        rot("forearm.R", 0, 0, -25)
        rot("head", -5, 0, 10)
    elif kind == "push":
        rot("hips", -20)
        rot("chest", -15)
        rot("head", 25)
        for s in ("L", "R"):
            rot("upper_arm." + s, -75)
            rot("forearm." + s, -20)
            rot("thigh." + s, 20 if s == "L" else -15)
            rot("shin." + s, 30 if s == "R" else 5)
    elif kind == "walk":
        rot("thigh.L", -28)
        rot("shin.L", 10)
        rot("thigh.R", 22)
        rot("shin.R", 35)
        rot("upper_arm.L", 22)
        rot("upper_arm.R", -24)
        rot("forearm.R", -20)
        rot("forearm.L", -12)
        rot("chest", 0, 8, 0)


# ---------------------------------------------------------------- 組む
rig = build_armature()
body = build_body()
head = build_head()
eyes = build_eyes(head)
coat = build_coat()
hood = build_hood(head)
mitts = build_mitts()
boots = build_boots()

limbs = [n for n in BONES if n not in ("head",)]
weigh(body, rig, [n for n in BONES if not n.startswith("hand") and n != "head"])
for o in coat:
    if o and (o.name == "coat" or o.name.startswith("stitch_hem")):
        weigh(o, rig, ["hips", "chest", "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R", "thigh.L", "thigh.R"])
    elif o and o.name.startswith("stitch_cuff"):
        weigh(o, rig, [], rigid="forearm." + o.name[-1])
    elif o:
        weigh(o, rig, [], rigid="chest")
for o in [head] + eyes + hood:
    weigh(o, rig, [], rigid="head")
for o in mitts:
    weigh(o, rig, [], rigid="hand." + o.name[-1])
for o in boots:
    weigh(o, rig, [], rigid="foot." + o.name[-1])

if A.pose != "rest":
    pose(rig, A.pose)


# ---------------------------------------------------------------- 書き出し
def export(folder):
    os.makedirs(folder, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in sc.objects:
        o.select_set(o.type in ("MESH", "ARMATURE"))
    bpy.context.view_layer.objects.active = rig
    path = os.path.abspath(os.path.join(folder, "person.glb"))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=False, export_apply=False)
    print("wrote", path)


if A.blend:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend))
if A.export:
    export(A.export)
    sys.exit(0)

# ---------------------------------------------------------------- 描く: 雪の地面、低めの午後の光、空
w = bpy.data.worlds.new("sky")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = lin("C9D6E8")
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
sc.world = w
bpy.ops.mesh.primitive_plane_add(size=20)
ground = bpy.context.object
ground.data.materials.append(material("snow", "F4F5F8", "felt"))
sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 3.2
sun.angle = math.radians(4)
sun.color = (1.0, 0.95, 0.87)
so = link(bpy.data.objects.new("sun", sun))
so.rotation_euler = (math.radians(52), 0, math.radians(-35))
fill = bpy.data.lights.new("fill", "AREA")
fill.energy = 60
fill.size = 3
fo = link(bpy.data.objects.new("fill", fill))
fo.location = (-2.5, 2.5, 2.0)
fo.rotation_euler = Vector((0, 0, 1)).rotation_difference(Vector((0, 0, 0.9)) - fo.location).to_euler()

for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
rx, ry = (int(v) for v in A.size.split("x"))
sc.render.resolution_x, sc.render.resolution_y = rx, ry
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast"
sc.eevee.taa_render_samples = 48
for attr, v in (("use_raytracing", True), ("use_shadows", True), ("use_gtao", True)):
    if hasattr(sc.eevee, attr):
        setattr(sc.eevee, attr, v)

VIEWS = {"front": 0, "quarter": 35, "side": 90, "back": 160, "left": -40}
cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
cam.data.lens = 85
sc.camera = cam
tgt = Vector((0, 0, 0.88))
for v in A.views.split(","):
    a = math.radians(VIEWS.get(v, 0))
    dist = 4.6
    cam.location = tgt + Vector((math.sin(a) * dist, math.cos(a) * dist, 0.35))
    d = tgt - cam.location
    cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, math.atan2(d.y, d.x) - math.pi / 2)
    sc.render.filepath = os.path.abspath("%s-%s.png" % (A.prefix, v))
    bpy.ops.render.render(write_still=True)
    print("wrote", sc.render.filepath)
