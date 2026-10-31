extends RefCounted
## 手の形のアップリケ。紙を切った手の形（手のひら・指さし）に墨色の縁を付けた、平たい板。
## 遠くからでも形が読めるよう、ほんとうの手より大きく作る。人形の手（doll.gd）と、一人称の手（player.gd）に付ける。
## ハイタッチが合ったときに飛び散る、千代紙の紙吹雪と紙の星もここで作る。

const Look := preload("res://look.gd")

const EDGE := Color(0.22, 0.16, 0.13)
const BIG := 1.7            # 人形の手の形は、ほんとうの手より大きく（遠くからでも読める）
const WRIST := Vector3(0, -0.075, 0)   # 手形の手首の真ん中（手形の座標）。腕の先をここに合わせる
const POINT_ROOT := Vector3(0.026, -0.005, 0)   # 指さしの手形の、人さし指の付け根（右手の座標。左手は x を返す）
const SHAPES := ["palm", "point"]
## 掲げた手の状態（高さ_手）→ [右手, 左手] の高さ。"" は下ろしている。
## 高い手のひら: 遠くの人に場所を示す・万歳・ハイタッチ。低い手のひら: おさえて・ストップ・握手
const HANDS := {
	"high_R": ["high", ""], "high_L": ["", "high"], "high_both": ["high", "high"],
	"low_R": ["low", ""], "low_L": ["", "low"], "low_both": ["low", "low"], "": ["", ""],
}


## 高さ（"high" "low" ""）と手（"R" "L" "both"）から、状態の名前
static func hands_name(height: String, hand: String) -> String:
	return "" if height == "" else "%s_%s" % [height, hand]


## 手（"R" "L" "both"）→ 使う側（1 右、-1 左）
static func sides_of(hand: String) -> Array:
	return [1, -1] if hand == "both" else ([-1] if hand == "L" else [1])


## 紙吹雪の色: 人の上着の差し色（赤・藍・山吹）と、生成り
const CONFETTI := [Color(0.82, 0.25, 0.2), Color(0.22, 0.32, 0.6), Color(0.93, 0.72, 0.2), Color(0.97, 0.94, 0.86), Color(0.36, 0.6, 0.5)]

static var _meshes := {}     # "形_側" → [板, 縁]


## 手の形の輪郭（m、指は +y、手のひらは +z を向く）。side 1 右手、-1 左手。
## 手のひら（甲でなく）を前（相手）へ向けたとき、うしろ（自分）から見て親指が内側に来る向き
static func outline(shape: String, side := 1) -> PackedVector2Array:
	var poly := _left(shape)
	if side < 0:
		return poly
	var right := PackedVector2Array()   # 右手: 左右を返す（向きをそろえるため点の順も逆に）
	for i in range(poly.size() - 1, -1, -1):
		right.append(Vector2(-poly[i].x, poly[i].y))
	return right


## 左手の形（親指は -x）
static func _left(shape: String) -> PackedVector2Array:
	var poly: PackedVector2Array
	if shape == "point":
		# 指さし: 握ったこぶしから人さし指がまっすぐ（+y）。ほかの指は折って節だけ、親指は横に沿う
		poly = _round_rect(Vector2(0.006, -0.04), Vector2(0.095, 0.09), 0.032)
		poly = _merge(poly, _capsule(Vector2(-POINT_ROOT.x, POINT_ROOT.y), Vector2(-POINT_ROOT.x, 0.105), 0.0135))
		for c in [[0.0, 0.012], [0.022, 0.007], [0.042, -0.002]]:
			poly = _merge(poly, _dot(Vector2(c[0], c[1]), 0.0145))
		poly = _merge(poly, _capsule(Vector2(-0.046, -0.045), Vector2(-0.044, -0.008), 0.014))
		return poly
	# 手のひら: 指 4 本（中指がいちばん長い）と、斜めに開いた親指
	poly = _round_rect(Vector2(0, -0.035), Vector2(0.105, 0.1), 0.035)
	for f in [[-0.039, 0.068], [-0.013, 0.083], [0.013, 0.078], [0.038, 0.062]]:
		poly = _merge(poly, _capsule(Vector2(f[0], 0.0), Vector2(f[0] * 1.15, f[1]), 0.0125))
	poly = _merge(poly, _capsule(Vector2(-0.04, -0.05), Vector2(-0.088, 0.0), 0.014))
	return poly


static func _merge(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	return Geometry2D.merge_polygons(a, b)[0]


static func _dot(c: Vector2, r: float) -> PackedVector2Array:
	return _capsule(c, c + Vector2(0, 0.001), r)


static func _round_rect(c: Vector2, size: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var h := size * 0.5 - Vector2(r, r)
	for q in 4:
		var cc := c + Vector2(h.x * (1 if q in [0, 3] else -1), h.y * (1 if q < 2 else -1))
		for k in 5:
			var a := PI * 0.5 * q + PI * 0.5 * k / 4.0
			pts.append(cc + Vector2(cos(a), sin(a)) * r)
	return pts


static func _capsule(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var pts := PackedVector2Array()
	for k in 7:
		var t := PI * k / 6.0
		pts.append(b + (n * cos(t) + d * sin(t)) * r)
	for k in 7:
		var t := PI + PI * k / 6.0
		pts.append(a + (n * cos(t) + d * sin(t)) * r)
	return pts


## 平たい紙の板（表と裏と縁）
static func _slab(poly: PackedVector2Array, z0: float, z1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(poly)
	for face in [[z1, 1.0], [z0, -1.0]]:
		st.set_normal(Vector3(0, 0, face[1]))
		for i in range(0, tri.size(), 3):
			var order := [0, 1, 2] if face[1] > 0 else [0, 2, 1]
			for k in order:
				var p := poly[tri[i + k]]
				st.set_uv(p * 6.0 + Vector2(0.5, 0.5))
				st.add_vertex(Vector3(p.x, p.y, face[0]))
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := Vector3(b.y - a.y, a.x - b.x, 0).normalized()
		if Geometry2D.is_polygon_clockwise(poly):
			n = -n
		st.set_normal(n)
		for v in [Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)]:
			st.set_uv(Vector2(v.x, v.y) * 6.0)
			st.add_vertex(v)
	return st.commit()


## 手の形の節点を作る。color は手（紙）の色。layers は映す層
static func make(shape: String, side: int, color: Color, layers: int) -> Node3D:
	var key := "%s_%d" % [shape, side]
	if not _meshes.has(key):
		var poly := outline(shape, side)
		_meshes[key] = [_slab(poly, -0.003, 0.003), _slab(Geometry2D.offset_polygon(poly, 0.007)[0], -0.002, 0.002)]
	var root := Node3D.new()
	var paper := Look.paper(color)
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	var face := MeshInstance3D.new()
	face.mesh = _meshes[key][0]
	face.material_override = paper
	face.layers = layers
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(face)
	# 墨色の縁: 少し大きな板を、紙の厚みの中に挟む（表からも裏からも、縁だけが見える）
	var edge := MeshInstance3D.new()
	edge.mesh = _meshes[key][1]
	var em := StandardMaterial3D.new()
	em.albedo_color = EDGE
	em.roughness = 1.0
	em.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge.material_override = em
	edge.layers = layers
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(edge)
	root.visible = false
	return root


## 人や一人称の手に付ける、形ごと・左右ごとの板の組。shapes[形][側] で引く（側は 1 右、-1 左）
static func make_set(color: Color, layers: int) -> Dictionary:
	var out := {}
	for sh in SHAPES:
		out[sh] = {1: make(sh, 1, color, layers), -1: make(sh, -1, color, layers)}
	return out


## 握手で、重ねた手を上下に振る量 (m、世界)。握る 2 コマのあと、2 コマずつ上・まんなか・下・まんなか。二人とも同じに動く
static func shake_pump(k: int) -> float:
	if k < 2 or k >= 20:
		return 0.0
	return [0.0, 0.04, 0.0, -0.04][((k - 2) / 2) % 4]


## 握手の手形の向き: 指（+y）は相手へ、手のひら（+z）は重ねる向き。二人の手のひらがみな平行になる。
## 親指は上へ（右手の輪郭は親指が +x、左手は -x。下を向く手は面を裏返す。手形は表裏が同じなので、平行のまま）
static func shake_basis(fwd: Vector3, axis: Vector3, side: int) -> Basis:
	var y := (fwd - axis * fwd.dot(axis)).normalized()
	return thumb_up(Basis(y.cross(axis).normalized(), y, axis), side)


## 親指を上へ: 右手の輪郭は親指が +x、左手は -x。親指が下を向くなら面を裏返す（手形は表裏が同じ。指の向きは変えない）
static func thumb_up(b: Basis, side: int) -> Basis:
	if (b.x * float(side)).y < 0.0:
		return Basis(-b.x, b.y, -b.z)
	return b


## 出てくるときの大きさ（12 コマ。ぽんと出て、少し行きすぎて戻る）
static func pop(k: int) -> float:
	return [0.45, 1.25, 1.05, 1.0][clampi(k, 0, 3)]


# ---------------------------------------------------------------- 合った所で飛び散るもの

## 紙吹雪と紙の星。normal はぶつかった手の向き（横へ散る）
static func burst(parent: Node, point: Vector3) -> void:
	var c := CPUParticles3D.new()
	c.one_shot = true
	c.emitting = false
	c.local_coords = false
	c.amount = 20
	c.lifetime = 1.4
	c.explosiveness = 1.0
	c.randomness = 0.5
	c.direction = Vector3.UP
	c.spread = 100.0
	c.initial_velocity_min = 1.6
	c.initial_velocity_max = 3.4
	c.gravity = Vector3(0, -3.2, 0)
	c.damping_min = 1.2
	c.damping_max = 2.2
	c.particle_flag_rotate_y = true
	c.angle_min = 0.0
	c.angle_max = 360.0
	c.angular_velocity_min = -540.0
	c.angular_velocity_max = 540.0
	c.scale_amount_min = 0.7
	c.scale_amount_max = 1.3
	var g := Gradient.new()   # 色は 5 つのどれか（混ぜない）
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in CONFETTI.size():
		offs.append(float(i) / CONFETTI.size())
		cols.append(CONFETTI[i])
	g.offsets = offs
	g.colors = cols
	c.color_initial_ramp = g
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	c.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.062)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	q.material = m
	c.mesh = q
	parent.add_child(c)
	c.global_position = point
	c.restart()
	c.finished.connect(c.queue_free)
	_star(parent, point)


## 紙を切った星が、合った瞬間にひらいて消える（12 コマで 4 コマ）
static func _star(parent: Node, point: Vector3) -> void:
	var pts := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0 + PI / 2.0
		var r := 0.17 if k % 2 == 0 else 0.07
		pts.append(Vector2(cos(a), sin(a)) * r)
	var star := MeshInstance3D.new()
	star.mesh = _slab(pts, -0.001, 0.001)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.98, 0.86, 0.36)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	star.material_override = m
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(star)
	star.global_position = point
	var tw := star.create_tween()
	for s in [[0.5, 1.0], [1.15, 1.0], [1.45, 0.65], [1.6, 0.25]]:
		tw.tween_callback(func():
			star.scale = Vector3.ONE * s[0]
			m.albedo_color.a = s[1])
		tw.tween_interval(1.0 / 12.0)
	tw.tween_callback(star.queue_free)
