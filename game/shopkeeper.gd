extends Node3D
## ミシンの横に立つ、型紙と布の売り子のおじさん。人形のラフの「旅のおじいさん」（person/ideas/characters の
## v2・v3。継ぎ当てだらけの紺のフェルトの長いコート、先の巻いたとんがり帽、針金の丸眼鏡、綿のひげ、杖）を、
## ゲームの中で形の部品（円錐・球・管）から組んだもの。骨と焼いた絵の glb はまだない（あとで Blender から書き出す）。
## 動きは人形と同じ 12 コマ／秒に刻む（コマの間は止める）:
##   待つ   息をするように体がわずかにふくらみ、ときどき杖で床をとんと突き、ゆっくり左右を見る
##   気づく 人が近づくと顔を向け、左手を挙げて小さく振る
##   売る   売り台（craft_ui.gd）が開いているあいだは客を見て、開いたときに頭の上の看板を左手で指す。売れたらうなずき、帽子が跳ねる
## 頭の上に、文字のない品書きの看板（型紙と布の絵と、値段のボタンの数）を吊る。
## F で話しかける（player.gd が近さを見る）。立ち位置と向きは main.gd が決める。

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const CraftIcons := preload("res://craft_icons.gd")

const SCALE := 1.4           # 組んだ寸法（ラフの 1.25 m）から、ゲームの人と並ぶ大きさへ
const NOTICE_R := 3.6        # この距離に人が来ると気づく (m)
const TALK_R := 2.2          # F で話しかけられる距離 (m)
const SIGN_SIZE := Vector2(1.5, 0.94)   # 看板の板の大きさ (m)
const SIGN_Y := 2.25         # 看板の下の縁の高さ（足もとから, m）

const INDIGO := Color(0.20, 0.25, 0.46)
const INDIGO2 := Color(0.25, 0.31, 0.55)
const PATCHES := [   # [色, 高さ y, 横 x（前から見て）, 幅, 高さ]。ラフ（v3）の継ぎ当てを写して、数を足した
	[Color(0.36, 0.48, 0.66), 0.42, 0.08, 0.09, 0.10],
	[Color(0.62, 0.62, 0.60), 0.25, -0.10, 0.08, 0.07],
	[Color(0.90, 0.85, 0.72), 0.56, -0.05, 0.05, 0.05],
	[Color(0.45, 0.28, 0.40), 0.17, 0.12, 0.06, 0.08],
	[Color(0.24, 0.52, 0.52), 0.30, 0.04, 0.07, 0.06],
	[Color(0.86, 0.64, 0.24), 0.48, -0.11, 0.05, 0.07],
	[Color(0.72, 0.30, 0.24), 0.14, -0.04, 0.07, 0.05],
	[Color(0.85, 0.80, 0.70), 0.62, 0.07, 0.04, 0.04],
]
const BACK_PATCHES := [
	[Color(0.62, 0.62, 0.60), 0.35, 0.05, 0.10, 0.09],
	[Color(0.86, 0.64, 0.24), 0.20, -0.08, 0.07, 0.07],
	[Color(0.45, 0.28, 0.40), 0.55, -0.03, 0.06, 0.05],
]
const COAT := [Vector2(0.22, 0.09), Vector2(0.19, 0.30), Vector2(0.16, 0.50), Vector2(0.145, 0.62), Vector2(0.11, 0.675), Vector2(0.05, 0.69)]
const COAT_SZ := 0.85        # コートの前後のつぶれ

var world: Node              # main.gd（あなたを探す）
var shop_open := false       # 売り台が開いている（craft_ui.gd が入れる）
var _body: Node3D
var _head: Node3D
var _hat: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _sign: Node3D
var _frame := -1
var _k := 0                  # コマの数
var _noticed := false
var _wave_from := -100       # 手を振り始めたコマ
var _point_from := -100      # 看板を指し始めたコマ
var _nod_from := -100        # うなずき始めたコマ
var _tap_next := 40          # 次に杖で突くコマ
var _look_next := 30
var _look_yaw := 0.0         # 待つときに見回す向き
var _head_yaw := 0.0
var _head_pitch := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 21
	var root := Node3D.new()
	root.name = "Doll"
	root.scale = Vector3.ONE * SCALE
	add_child(root)
	_build(root)
	_make_sign()
	var col := StaticBody3D.new()   # ぶつかる体（コートの裾くらいの筒）
	var cs := CollisionShape3D.new()
	var cap := CylinderShape3D.new()
	cap.radius = 0.26 * SCALE
	cap.height = 1.4 * SCALE
	cs.shape = cap
	cs.position.y = 0.7 * SCALE
	col.add_child(cs)
	add_child(col)


# ---- 組む ------------------------------------------------------------------------------

func _build(root: Node3D) -> void:
	var felt_in := Look.felt(INDIGO, 3.0)
	felt_in.cull_mode = BaseMaterial3D.CULL_DISABLED
	var felt_in2 := Look.felt(INDIGO2, 3.0)
	felt_in2.cull_mode = BaseMaterial3D.CULL_DISABLED
	var face := Look.paper(Color(0.93, 0.84, 0.70))
	var cotton := Look.felt(Color(0.97, 0.96, 0.93), 6.0)
	cotton.rim = 0.8
	var wire := Look.wood(Color(0.16, 0.14, 0.13))
	var wood := Look.wood(Color(0.55, 0.36, 0.22))
	var boot := Look.felt(Color(0.30, 0.22, 0.17), 3.0)
	var red := Look.felt(Color(0.80, 0.33, 0.20), 3.0)

	# 足: フェルトの長靴
	for s in [1, -1]:
		_ball(root, Vector3(0.07 * s, 0.04, -0.07), Vector3(0.045, 0.04, 0.07), boot)

	_body = Node3D.new()
	_body.name = "Body"
	root.add_child(_body)
	# コート: 長い紺のフェルト。裾は広く、肩へすぼむ。立てた襟
	_mesh(_body, _lathe(COAT, 40, COAT_SZ), felt_in)
	_mesh(_body, _lathe([Vector2(0.05, 0.692), Vector2(0.0, 0.692)], 20, COAT_SZ), felt_in)
	_mesh(_body, _lathe([Vector2(0.075, 0.665), Vector2(0.06, 0.725)], 28, 0.9), felt_in2)
	# 継ぎ当て（前と後ろ）と縫い目、木のボタン、赤い帯
	var dashes: Array[Transform3D] = []
	for p in PATCHES:
		_patch(_body, p, -1.0, dashes)
	for p in BACK_PATCHES:
		_patch(_body, p, 1.0, dashes)
	for y in [0.6, 0.5, 0.36]:
		var b := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.014
		cm.bottom_radius = 0.014
		cm.height = 0.008
		b.mesh = cm
		b.material_override = wood
		b.position = Vector3(0, y, -_coat_r(y) * COAT_SZ - 0.004)
		b.rotation.x = PI / 2
		_body.add_child(b)
	_mesh(_body, _lathe([Vector2(_coat_r(0.40) + 0.012, 0.40), Vector2(_coat_r(0.46) + 0.012, 0.46)], 36, COAT_SZ), red)
	for s in [0, 1]:   # 帯の垂れ（左前）
		var tail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.16 - s * 0.03, 0.01)
		tail.mesh = bm
		tail.material_override = red
		tail.position = Vector3(-0.07 - s * 0.03, 0.36 + s * 0.015, -_coat_r(0.36) * COAT_SZ - 0.02)
		tail.rotation.z = 0.12 + s * 0.15
		_body.add_child(tail)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dm := BoxMesh.new()
	dm.size = Vector3(0.012, 0.003, 0.004)
	mm.mesh = dm
	mm.instance_count = dashes.size()
	for i in dashes.size():
		mm.set_instance_transform(i, dashes[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Look.felt(Color(0.95, 0.91, 0.82), 6.0)
	_body.add_child(mmi)

	# 腕: 袖と折り返し、紙の手。右手で杖を持つ（杖は右腕と一緒に動く）
	_arm_r = _arm(1, felt_in, felt_in2, face)
	_arm_l = _arm(-1, felt_in, felt_in2, face)
	var top := Vector3(0.24, 0.78, -0.13)
	_tube(_arm_r, [Vector3(0.24, 0.0, -0.16) - _arm_r.position, Vector3(0.235, 0.4, -0.14) - _arm_r.position, top - _arm_r.position],
			[0.012, 0.012, 0.014], wood, 8)
	_ball(_arm_r, top + Vector3(0, 0.03, 0) - _arm_r.position, Vector3.ONE * 0.032, Look.felt(Color(0.45, 0.28, 0.40), 4.0))
	for k in 5:   # 麻ひもの巻き
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.012
		tm.outer_radius = 0.019
		ring.mesh = tm
		ring.material_override = Look.felt(Color(0.78, 0.66, 0.46), 6.0)
		ring.position = Vector3(0.236, 0.42 + k * 0.014, -0.135) - _arm_r.position
		_arm_r.add_child(ring)

	# 頭: 首の所を軸に回す。紙の顔、紙を巻いた鼻、針金の丸眼鏡、閉じた目、綿のひげと眉、とんがり帽
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.69, 0)
	_body.add_child(_head)
	var hc := Vector3(0, 0.80, -0.02) - _head.position
	_ball(_head, hc, Vector3(0.1, 0.12, 0.1), face)
	_tube(_head, [hc + Vector3(0, -0.005, -0.085), hc + Vector3(0, -0.025, -0.15)], [0.022, 0.006], face, 10)
	for s in [1, -1]:
		var c := hc + Vector3(0.045 * s, 0.012, -0.105)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.028
		tm.outer_radius = 0.034
		tm.rings = 20
		ring.mesh = tm
		ring.material_override = wire
		ring.position = c
		ring.rotation.x = PI / 2
		_head.add_child(ring)
		_tube(_head, [c + Vector3(0.032 * s, 0, 0), c + Vector3(0.06 * s, 0.005, 0.06), c + Vector3(0.06 * s, 0.0, 0.11)], [0.003, 0.003, 0.003], wire, 5)
		var eye := MeshInstance3D.new()   # 閉じた目（細い糸）
		var em := BoxMesh.new()
		em.size = Vector3(0.026, 0.004, 0.004)
		eye.mesh = em
		eye.material_override = wire
		eye.position = c + Vector3(0, -0.004, 0.012)
		_head.add_child(eye)
		_ball(_head, hc + Vector3(0.045 * s, 0.06, -0.1), Vector3(0.026 * 1.4, 0.026 * 0.6, 0.026 * 0.6), cotton)
	_tube(_head, [hc + Vector3(-0.013, 0.016, -0.108), hc + Vector3(0, 0.022, -0.112), hc + Vector3(0.013, 0.016, -0.108)], [0.003, 0.003, 0.003], wire, 5)
	for b in [[Vector3(0, -0.07, -0.08), 0.07, Vector3(1.0, 1.0, 0.6)], [Vector3(0, -0.16, -0.07), 0.06, Vector3(0.8, 1.2, 0.55)],
			[Vector3(0.05, -0.06, -0.06), 0.05, Vector3.ONE], [Vector3(-0.05, -0.06, -0.06), 0.05, Vector3.ONE],
			[Vector3(0, -0.24, -0.06), 0.035, Vector3.ONE]]:
		_ball(_head, hc + b[0], b[2] * b[1], cotton)
	# 帽子: 紺のフェルトのとんがり。先は後ろへ巻く。つばは広め
	_hat = Node3D.new()
	_hat.name = "Hat"
	_hat.position = hc + Vector3(0, 0.07, 0)
	_head.add_child(_hat)
	var path: Array[Vector3] = [Vector3(0, 0.01, 0.005)]
	for k in range(1, 15):
		var t := k / 14.0
		var yb := -0.005 - 0.03 * t - 0.09 * pow(maxf(0.0, t - 0.6), 1.5) * 6.0
		var zb := 0.08 + 0.36 * t - 0.25 * pow(maxf(0.0, t - 0.75), 2.0) * 8.0
		path.append(Vector3(0, zb - 0.07, -yb))
	var curl_c: Vector3 = path[-1] + Vector3(0, -0.01, 0.035)
	for k in range(1, 9):
		var a := PI * 0.5 + 1.6 * PI * k / 8.0
		path.append(curl_c + Vector3(0, sin(a) * 0.035 * (1.0 - k / 12.0), -cos(a) * 0.035 * (1.0 - k / 12.0)))
	var radii: Array[float] = []
	for i in path.size():
		radii.append(0.118 * pow(1.0 - float(i) / path.size(), 1.15) + 0.004)
	_tube(_hat, path, radii, felt_in, 20)
	_mesh(_hat, _lathe([Vector2(0.105, 0.016), Vector2(0.2, -0.004), Vector2(0.2, -0.014), Vector2(0.105, 0.006)], 40, 0.95), felt_in2)
	var hp := MeshInstance3D.new()   # 帽子の継ぎ当て
	var hb := BoxMesh.new()
	hb.size = Vector3(0.05, 0.045, 0.008)
	hp.mesh = hb
	hp.material_override = Look.felt(Color(0.36, 0.48, 0.66), 4.0)
	hp.position = Vector3(0.0, 0.12, -0.085)
	hp.rotation.x = -0.25
	_hat.add_child(hp)


## 腕（s = 1 右、-1 左）。肩を軸に回す
func _arm(s: int, felt_a: Material, felt_b: Material, face: Material) -> Node3D:
	var arm := Node3D.new()
	arm.name = "ArmR" if s > 0 else "ArmL"
	arm.position = Vector3(0.13 * s, 0.66, 0)
	_body.add_child(arm)
	var sh := Vector3.ZERO
	var el := Vector3(0.2 * s, 0.52, -0.03) - arm.position
	var wr := (Vector3(0.2, 0.44, -0.11) if s > 0 else Vector3(-0.17, 0.42, -0.08)) - arm.position
	_tube(arm, [sh - Vector3(0.04 * s, 0, 0), sh, el, wr], [0.052, 0.052, 0.05, 0.048], felt_a, 14)
	_tube(arm, [wr + (el - wr) * 0.15, wr + (wr - el).normalized() * 0.01], [0.056, 0.056], felt_b, 14)
	_ball(arm, wr + Vector3(0, -0.04, -0.015), Vector3(0.028, 0.036, 0.024), face)
	return arm


## 継ぎ当て: コートの表面に沿う薄い板と、まわりの縫い目。side は -1 前、1 後ろ
func _patch(parent: Node3D, p: Array, side: float, dashes: Array[Transform3D]) -> void:
	var y: float = p[1]
	var x: float = p[2]
	var r := _coat_r(y)
	var a := asin(clampf(x / r, -0.9, 0.9))
	var pos := Vector3(r * sin(a), y, side * r * cos(a) * COAT_SZ)
	var nrm := Vector3(sin(a), 0.12, side * cos(a) / COAT_SZ).normalized()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(p[3], p[4], 0.006)
	mi.mesh = bm
	mi.material_override = Look.felt(p[0], 4.0)
	mi.transform = Transform3D(Basis.looking_at(-nrm, Vector3.UP), pos + nrm * 0.004)   # 板の +z が外
	parent.add_child(mi)
	# 縫い目: 縁の少し内側に、短い目を並べる
	var w: float = p[3] * 0.5 - 0.008
	var h: float = p[4] * 0.5 - 0.008
	var corners := [Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)]
	for i in 4:
		var c0: Vector2 = corners[i]
		var c1: Vector2 = corners[(i + 1) % 4]
		var along := (c1 - c0).normalized()
		var n := maxi(2, int(c0.distance_to(c1) / 0.02))
		for k in n:
			var q := c0.lerp(c1, (k + 0.5) / n)
			dashes.append(mi.transform * Transform3D(Basis(Vector3.BACK, atan2(along.y, along.x)), Vector3(q.x, q.y, 0.004)))


## コートの半径（高さ y で）
func _coat_r(y: float) -> float:
	for i in COAT.size() - 1:
		if y <= COAT[i + 1].y:
			return lerpf(COAT[i].x, COAT[i + 1].x, inverse_lerp(COAT[i].y, COAT[i + 1].y, y))
	return COAT[-1].x


func _mesh(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, at: Vector3, radii: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = mat
	mi.position = at
	mi.scale = radii
	parent.add_child(mi)
	return mi


## 回転体: 横断面 (半径, 高さ) の列を y 軸のまわりに回す。sz で前後をつぶす
static func _lathe(prof: Array, segs: int, sz := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = prof.size()
	for i in n:
		for j in segs + 1:
			var a := TAU * j / segs
			var p: Vector2 = prof[i]
			st.set_uv(Vector2(float(j) / segs, float(i) / (n - 1)))
			st.add_vertex(Vector3(cos(a) * p.x, p.y, sin(a) * p.x * sz))
	for i in n - 1:
		for j in segs:
			var k := i * (segs + 1) + j
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + segs + 1)
			st.add_index(k + 1)
			st.add_index(k + segs + 2)
			st.add_index(k + segs + 1)
	st.generate_normals()
	return st.commit()


## 管: 点の列に沿って、半径の列で太さを変える
func _tube(parent: Node3D, pts: Array, radii: Array, mat: Material, sides := 10) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for i in n:
		var t: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.1:
			side = t.cross(Vector3.FORWARD)
		side = side.normalized()
		var up := side.cross(t)
		for j in sides + 1:
			var a := TAU * j / sides
			var nrm := side * cos(a) + up * sin(a)
			st.set_normal(nrm)
			st.add_vertex((pts[i] as Vector3) + nrm * float(radii[mini(i, radii.size() - 1)]))
	for i in n - 1:
		for j in sides:
			var a := i * (sides + 1) + j
			st.add_index(a)
			st.add_index(a + sides + 1)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + sides + 1)
			st.add_index(a + sides + 2)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# ---- 看板 ------------------------------------------------------------------------------

## 頭の上に吊る品書き: 木の枠にフェルトの板。絵は craft_icons.gd で描いて板に貼る。天井から麻ひもで吊る
func _make_sign() -> void:
	_sign = Node3D.new()
	_sign.name = "MenuSign"
	_sign.position = Vector3(0, SIGN_Y + SIGN_SIZE.y / 2.0, 0)
	add_child(_sign)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(SIGN_SIZE.x * 560), int(SIGN_SIZE.y * 560))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var board := MenuBoard.new()
	board.size = Vector2(vp.size)
	vp.add_child(board)
	add_child(vp)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = SIGN_SIZE
	face.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = vp.get_texture()
	m.roughness = 1.0
	m.normal_enabled = true
	m.normal_texture = Look.fiber_normal(true)
	m.normal_scale = 0.4
	face.material_override = m
	face.position.z = -0.026
	face.rotation.y = PI   # 板の表は前（-z）
	_sign.add_child(face)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIGN_SIZE.x + 0.08, SIGN_SIZE.y + 0.08, 0.05)
	back.mesh = bm
	back.material_override = Look.wood(Color(0.50, 0.33, 0.20))
	_sign.add_child(back)
	call_deferred("_hang_sign")


## 板の上の両端から、天井まで麻ひもを張る（天井がなければ 0.8 m 上まで）
func _hang_sign() -> void:
	var hemp := Look.felt(Color(0.78, 0.66, 0.46), 6.0)
	for s in [-1, 1]:
		var from := _sign.to_global(Vector3(s * (SIGN_SIZE.x / 2.0 - 0.08), SIGN_SIZE.y / 2.0 + 0.04, 0))
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 3.0)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var to: Vector3 = hit.position if hit else from + Vector3.UP * 0.8
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.008
		cm.height = from.distance_to(to)
		mi.mesh = cm
		mi.material_override = hemp
		add_child(mi)
		mi.global_position = (from + to) / 2.0


class MenuBoard extends Control:
	func _draw() -> void:
		CraftIcons.menu(self, Rect2(Vector2.ZERO, size))


# ---- 動き（12 コマ／秒）----------------------------------------------------------------

func _process(_dt: float) -> void:
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	_frame = fi
	_k += 1
	var you: Node3D = world.get("player") if world else null
	var near := you != null and you.global_position.distance_to(global_position) < NOTICE_R
	if near and not _noticed:
		_wave_from = _k
	_noticed = near
	# 頭の向き: 近い人を見る。いなければ、ときどきゆっくり見回す
	var want_yaw := _look_yaw
	var want_pitch := 0.0
	if near:
		var d := to_local(you.global_position + Vector3.UP * 1.3)
		want_yaw = clampf(atan2(-d.x, -d.z), -1.1, 1.1)
		want_pitch = clampf(atan2(d.y - 1.0 * SCALE, Vector2(d.x, d.z).length()) * 0.6, -0.3, 0.3)
	elif _k >= _look_next:
		_look_next = _k + _rng.randi_range(36, 80)
		_look_yaw = _rng.randf_range(-0.6, 0.6) if _rng.randf() < 0.7 else 0.0
	_head_yaw = lerpf(_head_yaw, want_yaw, 0.35)
	_head_pitch = lerpf(_head_pitch, want_pitch, 0.35)
	var nod := 0.0
	var n := _k - _nod_from
	if n >= 0 and n < 8:
		nod = [0.1, 0.25, 0.3, 0.2, 0.08, 0.18, 0.06, 0.0][n]
	_head.rotation = Vector3(-_head_pitch - nod, _head_yaw, 0.04 * sin(_k * 0.21))
	# 帽子: 売れたら跳ねる（つぶれて戻る）
	var hop := 1.0
	if n >= 0 and n < 6:
		hop = [0.85, 1.12, 0.95, 1.04, 0.99, 1.0][n]
	_hat.scale = Vector3(1.0 / sqrt(hop), hop, 1.0 / sqrt(hop))
	# 息: 2 秒で一回、体がわずかにふくらむ（4 コマずつの段で）
	var br := 0.5 + 0.5 * sin(TAU * float(_k / 4 * 4) / 24.0)
	_body.scale = Vector3(1.0 + 0.008 * br, 1.0 + 0.012 * br, 1.0 + 0.008 * br)
	# 左腕: 振る・看板を指す・下ろす
	var w := _k - _wave_from
	var p := _k - _point_from
	if w >= 0 and w < 20:
		var up: float = [0.6, 1.4, 2.0, 2.2][mini(w, 3)] if w < 16 else [1.4, 0.7, 0.3, 0.0][w - 16]
		var sway := 0.0 if w < 4 or w >= 16 else (0.3 if (w / 2) % 2 == 0 else -0.15)
		_arm_l.rotation = Vector3(-0.2, 0, -up - sway)
	elif p >= 0 and p < 24:
		var up: float = [0.5, 1.2, 1.9, 2.4][mini(p, 3)] if p < 20 else [1.6, 0.9, 0.4, 0.0][p - 20]
		_arm_l.rotation = Vector3(-0.5 * minf(up, 1.0), 0, -up)
	else:
		_arm_l.rotation = Vector3(0, 0, 0.03 * sin(_k * 0.3))
	# 右腕と杖: ときどき床をとんと突く（持ち上げて、落とす）
	if _k >= _tap_next:
		_tap_next = _k + _rng.randi_range(50, 110)
	var t := _tap_next - _k
	var lift := 0.0
	if t > 0 and t <= 4 and not shop_open:
		lift = [0.0, 0.03, 0.05, 0.03][4 - t]
	_arm_r.position.y = 0.66 + lift


## 売り台が開いた: 看板を指す
func greet() -> void:
	_point_from = _k + 1


## 売れた: うなずいて、帽子が跳ねる
func sold() -> void:
	_nod_from = _k + 1


## 話しかけられる所にいるか
func can_talk(who: Node3D) -> bool:
	var d := to_local(who.global_position)
	return Vector2(d.x, d.z).length() < TALK_R
