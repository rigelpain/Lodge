extends Node
## HUD の手芸の物を、厚みのある立体の板にして描く（2026-10-29 代表「タグ、刺繍、糸巻き、どれも平面で背景と区別がつかないのが嫌です。
## 少しでも立体のプレートにして、影とか付けて、マテリアル感がないと安っぽくてかなわないや」）。
## しくみ（読みやすさと軽さのため、板の体と印刷を分けて描く）:
##   板    小さな 3D の場面（own_world の SubViewport、画面の半分の解像度）に、角の丸い板を物ごとに置く。縁の丸み・厚み・裏。
##         奥行きを右下へずらして写す（斜めの写し方）ので、どの板も右下に厚みが見える。光は左上の手前から一つ
##   影    板の形を平たくつぶして奥へ 3 枚、右下へずらして薄く重ねる（影の地図を使わない）
##   印刷  これまでの平らな絵（名札・札・ワッペン・持ち物の列）は、画面の解像度のまま板の表に重ねる（字や印がぼけない）。
##         印刷には紙・フェルトの凹凸を、左上からの光で陰影にしてかける（PRINT_SHADER）
##   形    糸巻き（ボビン）・刺繍枠は Blender の glb（props/build_hud.py）
##   風    滑るときの揺れ（hud_icons.gd の wind）は、板を支点のまわりに傾け（印刷も同じだけ）、板は少しあおる
## 重さ: 3D の場面は半分の解像度で、止まっているときは 2 コマに 1 回描く。M2 で、平らな絵とほぼ同じ fps（design/hud.md）

const Icons := preload("res://hud_icons.gd")
const Props := preload("res://props.gd")
const PX := 100.0                       # 3D の 1 単位 = 画面の 100 px
const SHEAR := Vector2(0.5, 0.6)        # 奥へ 1 進むと、画面で右へ 0.5・下へ 0.6 ずれる（板の厚みが右下に見える）
const DEPTH := 0.45                     # 板の表から、影を落とす面までの奥行き（単位）
const SHADOW_OFF := [Vector2(0.06, -0.09), Vector2(0.10, -0.15), Vector2(0.14, -0.20)]   # 落ち影の重ね（右下へ、だんだん広く）
const KINDS := {                        # 素材: [凹凸の画像, 凹凸の細かさ（px）, 縁の色, 表の色]
	"paper": ["res://props/textures/paper_normal.png", 160.0, Color(0.84, 0.78, 0.66), Color(0.95, 0.92, 0.85)],
	"felt": ["res://props/textures/felt_normal.png", 110.0, Color(0.86, 0.82, 0.74), Color(0.97, 0.95, 0.90)],
}

const PRINT_SHADER := """
shader_type canvas_item;
// 板に重ねた印刷に、紙・フェルトの凹凸の陰影と、左上からの光のむらをかける
uniform sampler2D bumps : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float tile = 160.0;              // 凹凸 1 枚の大きさ (px)
uniform vec2 light = vec2(-0.55, -0.7);  // 光の来る向き（画面、左上）
uniform float strength = 0.55;
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);   // 板の場所 (px)。左上ほど明るく
varying vec2 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 n = texture(bumps, lp / tile).rgb * 2.0 - 1.0;
	vec3 L = normalize(vec3(light, 0.9));
	float d = dot(normalize(vec3(n.xy * 1.6, 1.0)), L) / L.z;   // 平らなら 1
	float shade = mix(1.0, d, strength);
	vec2 f = clamp((lp - rect.xy) / rect.zw, 0.0, 1.0);
	shade *= 1.04 - 0.08 * (f.x * 0.4 + f.y * 0.6);              // 左上が少し明るい
	COLOR.rgb *= shade;
}
"""

var hud: CanvasLayer
var out: TextureRect
var prints: Control            # 印刷の入れ物（板の 3D の絵の上、ほかの HUD の下）
var vp: SubViewport
var cam: Camera3D
var scale_k := 0.5
var moving := false            # 風で揺れている・ボビンが回っている（毎コマ描く）。止まっているときは 2 コマに 1 回
var _plates := {}              # id → {node, mesh, painter, size, thick, radius, shadows, used}
var _models := {}              # id → {node, shadows, used}
var _side_mats := {}
var _print_mats := {}
var _shadow_mat: StandardMaterial3D
var _tick := 0


func setup(h: CanvasLayer) -> void:
	hud = h
	out = TextureRect.new()
	out.set_anchors_preset(Control.PRESET_FULL_RECT)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_SCALE
	hud.add_child(out)
	hud.move_child(out, 0)
	prints = Control.new()
	prints.set_anchors_preset(Control.PRESET_FULL_RECT)
	prints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(prints)
	hud.move_child(prints, 1)
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()   # 左上の手前から
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(-3.0, 4.0, 6.0), Vector3.ZERO)
	sun.light_energy = 0.85
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(0, 0, 10)
	cam.near = 0.1
	cam.far = 30.0
	vp.add_child(cam)
	cam.current = true
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(0.10, 0.08, 0.16, 0.16)
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_mat.no_depth_test = false   # 奥の面にあるので、手前の物には重ならない
	_shadow_mat.render_priority = -10
	out.texture = vp.get_texture()


## 毎コマの初め: 画面の大きさに合わせる
func begin() -> void:
	var vs := _vs()
	var want := Vector2i(maxi(1, int(vs.x * scale_k)), maxi(1, int(vs.y * scale_k)))
	if vp.size != want:
		vp.size = want
	cam.size = vs.y / PX
	for v in _plates.values():
		v.used = false
	for v in _models.values():
		v.used = false


## 毎コマの終わり: このコマに使わなかった物は隠し、3D の場面を描く。動いていなければ 2 コマに 1 回
func end() -> void:
	for v in _plates.values():
		v.node.visible = v.used
		v.painter.visible = v.used
		for sh in v.shadows:
			sh.visible = v.used
	for v in _models.values():
		v.node.visible = v.used
		for sh in v.shadows:
			sh.visible = v.used
	_tick += 1
	if moving or _tick % 2 == 0:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _vs() -> Vector2:
	return hud.get_viewport().get_visible_rect().size


func to_w(p: Vector2) -> Vector3:
	var vs := _vs()
	return Vector3((p.x - vs.x / 2.0) / PX, -(p.y - vs.y / 2.0) / PX, 0.0)


## 奥行きを右下へずらす写し方（板の厚みが見える）
static func shear() -> Basis:
	return Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(-SHEAR.x, SHEAR.y, 1))


## 支点のまわりの風の揺れ: 画面の中の傾き（印刷と同じ）と、板だけ少しあおる傾き
func _wind_xform(pivot: Vector2, wind: Array) -> Transform3D:
	if wind.is_empty() or Icons.wind <= 0.001:
		return Transform3D(Basis(), to_w(pivot))
	var seed: float = wind[0]
	var ang := Icons.wind_angle(seed, wind[1], wind[2])
	var off := Icons.wind_offset(seed, wind[3])
	var t := Icons._wt()
	var rx := Icons.wind * 0.12 * sin(t * 6.0 + seed)
	var ry := Icons.wind * 0.10 * Icons._jolt(seed + 4.0)
	return Transform3D(Basis(Vector3.BACK, -ang) * Basis.from_euler(Vector3(rx, ry, 0.0)), to_w(pivot + off))


## 印刷を重ねた板を出す。paint は印刷を描く Control を作る関数（画面と同じ座標で描く）。
## rect は板の画面の場所（px）、radius は角の丸み（px）、thick は厚み（px）、kind は素材、pivot は風の支点（画面の px）、
## wind は [seed, lean, flutter, jit]（空なら揺らさない）、a は薄さ
func plate(id: String, paint: Callable, rect: Rect2, radius: float, thick: float, kind: String, pivot: Vector2, wind: Array, a: float) -> void:
	var v: Dictionary = _plates.get(id, {})
	if v.is_empty():
		var painter: Control = paint.call()
		painter.material = _print_mat(kind)
		prints.add_child(painter)
		v = {"node": Node3D.new(), "mesh": MeshInstance3D.new(), "painter": painter, "size": Vector2.ZERO, "thick": 0.0,
			"radius": 0.0, "shadows": [], "used": false}
		vp.add_child(v.node)
		v.node.add_child(v.mesh)
		_plates[id] = v
	if absf(v.size.x - rect.size.x) > 0.5 or absf(v.size.y - rect.size.y) > 0.5 or v.thick != thick or v.radius != radius:
		v.size = rect.size
		v.thick = thick
		v.radius = radius
		v.mesh.mesh = _plate_mesh(rect.size / PX, radius / PX, thick / PX, kind)
		for sh in v.shadows:
			sh.queue_free()
		v.shadows = _make_shadows(vp, v.mesh)
	# 板: 支点で風に揺れ、板の真ん中を表の面に
	var base := _wind_xform(pivot, wind)
	var center := to_w(rect.get_center()) - to_w(pivot)
	v.node.transform = base * Transform3D(Basis(), center) * Transform3D(shear(), Vector3.ZERO)
	_place_shadows(v.shadows, base * Transform3D(Basis(), center))
	# 印刷: 板と同じだけ、画面の中で傾けてずらす
	var p: Control = v.painter
	p.size = _vs()
	p.pivot_offset = pivot
	if wind.is_empty():
		p.rotation = 0.0
		p.position = Vector2.ZERO
	else:
		p.rotation = Icons.wind_angle(wind[0], wind[1], wind[2])
		p.position = Icons.wind_offset(wind[0], wind[3])
	p.modulate.a = clampf(a, 0.0, 1.0)
	(p.material as ShaderMaterial).set_shader_parameter("rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	p.queue_redraw()
	v.used = a > 0.01
	v.node.visible = v.used
	p.visible = v.used


## glb の形（ボビン・刺繍枠）を出す。center は画面の px、size は 1 単位あたりの px、spin は奥行きの軸のまわりの回り
func model(id: String, path: String, center: Vector2, size: float, spin: float, wind: Array, a: float) -> Node3D:
	var v: Dictionary = _models.get(id, {})
	if v.is_empty():
		var n := Node3D.new()
		var body := Props.make(path)
		n.add_child(body)
		for g in body.find_children("*", "MeshInstance3D", true, false):   # 明るい木（HUD の光は弱めなので、木目の色を明るく当て直す）
			if "wood_light" in g.name:
				var wm := StandardMaterial3D.new()
				wm.albedo_color = Color(0.92, 0.74, 0.50)
				wm.roughness = 0.8
				wm.normal_enabled = true
				wm.normal_texture = load("res://props/textures/wood_normal.png")
				g.material_override = wm
		vp.add_child(n)
		v = {"node": n, "used": false, "shadows": _make_shadows(vp, n)}
		_models[id] = v
	var base := _wind_xform(center, wind)
	var s := size / PX
	var turn := Transform3D(Basis(Vector3.BACK, spin).scaled(Vector3(s, s, s)), Vector3.ZERO)
	v.node.transform = base * Transform3D(shear(), Vector3.ZERO) * turn
	_place_shadows(v.shadows, base * turn)
	v.used = a > 0.01
	v.node.visible = v.used
	return v.node


## 落ち影の部品（同じ形を 3 枚。平たくつぶして奥へ置く）
func _make_shadows(parent: Node, src: Node3D) -> Array:
	var list: Array = []
	for k in SHADOW_OFF.size():
		var n := src.duplicate()
		for g in ([n] + n.find_children("*", "GeometryInstance3D", true, false)):
			if g is GeometryInstance3D:
				g.material_override = _shadow_mat
				g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(n)
		list.append(n)
	return list


## 落ち影を置く: 物の変換を平たくつぶし、奥の面で右下へずらす。重ねるほど少し大きく
func _place_shadows(list: Array, xf: Transform3D) -> void:
	for k in list.size():
		var off: Vector2 = SHADOW_OFF[k]
		var grow := 1.0 + 0.02 * k
		var flat := Transform3D(Basis().scaled(Vector3(grow, grow, 0.001)), Vector3(off.x, off.y, -DEPTH))
		list[k].transform = Transform3D(Basis(), xf.origin) * flat * Transform3D(xf.basis, Vector3.ZERO)
		list[k].visible = true


func _print_mat(kind: String) -> ShaderMaterial:
	if not _print_mats.has(kind):
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = PRINT_SHADER
		var k: Array = KINDS.get(kind, KINDS.paper)
		m.set_shader_parameter("bumps", load(k[0]))
		m.set_shader_parameter("tile", k[1])
		_print_mats[kind] = m
	return (_print_mats[kind] as ShaderMaterial).duplicate()   # 板ごとに場所（rect）が違う


func _side_mat(kind: String, face: bool) -> StandardMaterial3D:
	var key := kind + ("_face" if face else "")
	if not _side_mats.has(key):
		var m := StandardMaterial3D.new()
		var k: Array = KINDS.get(kind, KINDS.paper)
		m.albedo_color = k[3] if face else k[2]
		m.roughness = 0.95
		m.normal_enabled = true
		m.normal_texture = load(k[0])
		m.uv1_scale = Vector3(6, 6, 1)
		_side_mats[key] = m
	return _side_mats[key]


## 角の丸い板: 表（z = 0）、縁の丸み、横の壁、裏。大きさは単位
func _plate_mesh(size: Vector2, radius: float, thick: float, kind: String) -> ArrayMesh:
	var r := clampf(radius, 0.004, minf(size.x, size.y) / 2.0)
	var bev := minf(thick * 0.45, r * 0.6 + 0.01)
	var outline := _rounded(size, r, 6)
	var inner := _rounded(size - Vector2(bev, bev) * 2.0, maxf(r - bev, 0.002), 6)
	var mesh := ArrayMesh.new()
	# 表（印刷の下地。印刷が隠すので、縁の色の一つ明るい色）
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(inner)
	for k in range(tri.size() - 1, -1, -1):   # Godot の表は時計回り
		var p := inner[tri[k]]
		st.set_uv(Vector2(p.x / size.x + 0.5, -p.y / size.y + 0.5))
		st.set_normal(Vector3.BACK)
		st.set_tangent(Plane(1, 0, 0, 1))
		st.add_vertex(Vector3(p.x, p.y, 0.0))
	st.commit(mesh)
	mesh.surface_set_material(0, _side_mat(kind, true))
	# 縁の丸み・横・裏
	var sd := SurfaceTool.new()
	sd.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [[inner, 0.0], [outline, -bev], [outline, -thick]]
	var n := outline.size()
	for j in rings.size() - 1:
		var a0: PackedVector2Array = rings[j][0]
		var a1: PackedVector2Array = rings[j + 1][0]
		var z0: float = rings[j][1]
		var z1: float = rings[j + 1][1]
		for i in n:
			var i2 := (i + 1) % n
			var q := [Vector3(a0[i].x, a0[i].y, z0), Vector3(a0[i2].x, a0[i2].y, z0), Vector3(a1[i2].x, a1[i2].y, z1), Vector3(a1[i].x, a1[i].y, z1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var pv: Vector3 = q[idx]
				sd.set_uv(Vector2(float(i) / n * 8.0, pv.z * 20.0))
				sd.add_vertex(pv)
	var back := Geometry2D.triangulate_polygon(outline)
	for k in back.size():
		var p := outline[back[k]]
		sd.set_uv(p)
		sd.add_vertex(Vector3(p.x, p.y, -thick))
	sd.generate_normals()
	sd.generate_tangents()
	sd.commit(mesh)
	mesh.surface_set_material(1, _side_mat(kind, false))
	return mesh


## 角の丸い長方形（中心が原点、反時計回り。y は上向き）
static func _rounded(size: Vector2, r: float, seg: int) -> PackedVector2Array:
	var hw := size.x / 2.0
	var hh := size.y / 2.0
	var cs := [Vector2(hw - r, -hh + r), Vector2(hw - r, hh - r), Vector2(-hw + r, hh - r), Vector2(-hw + r, -hh + r)]
	var p := PackedVector2Array()
	for k in 4:
		for i in seg + 1:
			var a := -PI / 2.0 + (k + float(i) / seg) * PI / 2.0
			p.append(cs[k] + Vector2(cos(a), sin(a)) * r)
	return p
