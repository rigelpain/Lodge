extends Node3D
## 山の道具（焚き火セット・ペグ）を売る山男（2026-11-01 代表「そういう道具類を売ってくれる山男？山師？みたいなキャラが欲しい」）。
## 姿はラフの C「狼の毛皮の山男」（person/ideas/yamaotoko。代表が 3 案から選んだ。ボードの白い和紙の狼と、折り紙の着物の人から）:
## 藍の和紙を折った長い上着、クリームの紙の衿を左前に重ね、赤い毛糸の帯。白い和紙の狼の頭を頭巾にかぶり、毛皮を背中へ垂らし、
## 前足の毛皮を肩から胸へ。顔は折り紙の多面体に、黒い糸の閉じた目。どれも面の少ない折り紙の多面体（平らな面のまま描く）。
## 置き場所はロッジの 1 階の、大きなミシンの奥（main.gd の MOUNTAIN_MAN）。
## 横（rack_side の側）に木の棚を置き、山の道具を並べる。まだ売っていない品目（mountain_goods.gd の on が false）は、白い紙に包んで麻ひもで縛ってある。
## 動きは人形と同じ 12 コマ／秒に刻む（コマの間は止める）:
##   待つ   息をするように体がわずかにふくらむ。ときどき見回し、狼の耳がぴくりと動く
##   気づく 人が近づくと顔を向け、左手を挙げて小さく振る。近くに何人かいれば、いちばん近い人を見る（オンラインのほかの人も）
##   売る   売り場（mountain_ui.gd）が開くと、棚の側の手で棚を示す。だれかが買うと（ほかの人の買い物でも）その人を向いてうなずき、狼の耳が立つ
## F で話しかける（player.gd の mountain_near）。

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Goods := preload("res://mountain_goods.gd")

const SCALE := 1.3           # ラフ（1.33 m）から、ゲームの人と並ぶ大きさへ（おじいさんと同じくらい）
const NOTICE_R := 4.0        # この距離に人が来ると気づく (m)
const TALK_R := 2.4          # F で話しかけられる距離 (m)
const RACK_AT := Vector3(1.15, 0, 0.1)   # 棚の位置（山男の座標。+X が右手の側。rack_side で左右を替える）

const INDIGO := Color("34477E")
const WHITE := Color("EEE8DC")
const GREY := Color("B8B2A6")
const CREAM := Color("EBD9BC")
const FACE := Color("E8CFA6")
const BOOT := Color("7A5636")
const YARN_RED := Color("B8402E")
const INK := Color("1A1716")

var main: Node               # main.gd（人と craft を探す）
var craft: Node
var shop_open := false       # 売り場が開いている（mountain_ui.gd が入れる）
var rack_side := 1.0         # 棚を置く側（1 右手、-1 左手。main.gd が入れる）
var _body: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _ears: Array[Node3D] = []
var _frame := -1
var _k := 0
var _noticed := false
var _wave_from := -100
var _show_from := -100       # 棚を示し始めたコマ
var _nod_from := -100
var _perk_from := -100       # 耳が立つ
var _twitch_next := 30
var _look_next := 24
var _look_yaw := 0.0
var _head_yaw := 0.0
var _head_pitch := 0.0
var _buyer: Node3D           # いま見ている買った人（少しのあいだ）
var _buyer_until := -1
var _rng := RandomNumberGenerator.new()
var _mats := {}


func _ready() -> void:
	_rng.seed = 33
	var root := Node3D.new()
	root.name = "Doll"
	root.scale = Vector3.ONE * SCALE
	add_child(root)
	_build(root)
	var col := StaticBody3D.new()   # ぶつかる体（上着の裾くらいの筒）
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.3 * SCALE
	cy.height = 1.3 * SCALE
	cs.shape = cy
	cs.position.y = 0.65 * SCALE
	col.add_child(cs)
	add_child(col)
	_make_rack()
	if craft:
		craft.happened.connect(_on_craft)


## ラフ（Blender）の座標 (x 右, y 前, z 上) を、この節の座標（前は -Z）へ
static func g(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


func _paper(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := Look.paper(c)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[c] = m
	return _mats[c]


# ---- 組む ------------------------------------------------------------------------------

func _build(root: Node3D) -> void:
	for s in [1, -1]:   # クラフト紙の長靴
		_facet(root, g(0.1 * s, 0.03, 0.06), Vector3(0.08, 0.06, 0.11), 6, 4, 0.006, 40 + s, _paper(BOOT))
	_body = Node3D.new()
	_body.name = "Body"
	root.add_child(_body)
	# 上着: 藍の和紙を折った裾広がり（面 10 枚）と、肩の面
	_cone(_body, [Vector2(0.17, 0.98), Vector2(0.22, 0.8), Vector2(0.27, 0.5), Vector2(0.33, 0.14)], 10, 0.8, 0.0, 360.0, _paper(INDIGO))
	_facet(_body, g(0, 0, 0.97), Vector3(0.18, 0.05, 0.15), 10, 4, 0.0, 41, _paper(INDIGO))
	# 衿: クリームの紙の帯を左前で斜めに重ねる
	_ribbon(_body, [g(0.1, 0.13, 0.97), g(0.0, 0.19, 0.8), g(-0.07, 0.215, 0.6)], 0.06, Vector3.ZERO, _paper(CREAM))
	_ribbon(_body, [g(-0.1, 0.13, 0.97), g(-0.03, 0.18, 0.86)], 0.055, Vector3.ZERO, _paper(CREAM))
	# 赤い毛糸の帯
	var belt: Array = []
	for k in 31:
		var a := TAU * k / 30.0
		belt.append(g(cos(a) * 0.245, sin(a) * 0.2, 0.6))
	_tube(_body, belt, 0.014, 6, Look.felt(YARN_RED, 4.0))
	# 狼の毛皮: 背中へ垂れる白い和紙と、肩から胸へ垂れる前足
	_cone(_body, [Vector2(0.12, 1.12), Vector2(0.2, 0.95), Vector2(0.27, 0.72), Vector2(0.3, 0.55)], 6, 0.85, 215.0, 325.0, _paper(WHITE))
	for s in [1, -1]:
		_ribbon(_body, [g(0.15 * s, 0.02, 1.0), g(0.13 * s, 0.13, 0.9), g(0.1 * s, 0.17, 0.78)], 0.06, Vector3.RIGHT, _paper(WHITE), 0.025)
	# 腕: 肩を軸に回す。藍の袖と、折り紙の手
	_arm_r = _arm(1)
	_arm_l = _arm(-1)
	# 頭: 首の所を軸に回す。折り紙の顔に糸の閉じた目、上に狼の頭巾（鼻すじ・鼻・とがった耳）
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = g(0, 0.02, 1.0)
	_body.add_child(_head)
	var o := _head.position
	var hc := g(0, 0.04, 1.07) - o
	_facet(_head, hc, Vector3(0.085, 0.095, 0.08), 8, 6, 0.004, 44, _paper(FACE))
	for s in [1, -1]:   # 閉じた目: 下に弧を描く黒い糸
		var c := hc + g(0.03 * s, 0.075, -0.005)
		_tube(_head, [c + g(-0.012, 0, 0.002), c + g(0, 0.003, -0.004), c + g(0.012, 0, 0.002)], 0.0032, 5, Look.felt(INK, 6.0))
	_facet(_head, g(0, -0.01, 1.17) - o, Vector3(0.13, 0.09, 0.14), 7, 5, 0.006, 45, _paper(WHITE))
	_facet(_head, g(0, 0.15, 1.17) - o, Vector3(0.05, 0.045, 0.1), 6, 4, 0.003, 46, _paper(WHITE))
	_facet(_head, g(0, 0.245, 1.18) - o, Vector3(0.02, 0.016, 0.018), 5, 4, 0.0, 47, _paper(GREY))
	for s in [1, -1]:
		var ear := Node3D.new()
		ear.name = "Ear"
		ear.position = g(0.08 * s, -0.03, 1.22) - o
		_head.add_child(ear)
		var tip := g(0.01 * s, -0.015, 0.11)
		_flat(ear, PackedVector3Array([g(-0.04, 0, 0), g(0.04, 0, 0), tip, g(0.04, 0, 0), g(0, -0.035, 0), tip, g(0, -0.035, 0), g(-0.04, 0, 0), tip]),
				Vector3(0, 0.03, 0.01), _paper(WHITE))
		_ears.append(ear)


## 腕（s = 1 右、-1 左）。肩を軸に回す: 袖の折った筒と、折り紙の手
func _arm(s: int) -> Node3D:
	var arm := Node3D.new()
	arm.name = "ArmR" if s > 0 else "ArmL"
	arm.position = g(0.17 * s, 0.0, 0.94)
	_body.add_child(arm)
	var o := arm.position
	_tube(arm, [g(0.17 * s, 0.0, 0.94) - o, g(0.27 * s, 0.05, 0.75) - o, g(0.25 * s, 0.13, 0.6) - o], 0.06, 6, _paper(INDIGO), true)
	_facet(arm, g(0.24 * s, 0.17, 0.56) - o, Vector3(0.04, 0.05, 0.04), 6, 4, 0.003, 42 + s, _paper(FACE))
	return arm


## 平らな面の三角の列（3 点ずつ）。面は inside から外を向ける（片面の素材でも光が正しく当たるように）
func _flat(parent: Node3D, tris: PackedVector3Array, inside: Variant, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n := (b - a).cross(c - a)
		if n.length() < 1e-9:
			continue
		n = n.normalized()
		var mid := (a + b + c) / 3.0
		var into: Vector3 = Vector3(0, mid.y, 0) if inside == null else inside
		if n.dot(mid - into) < 0.0:
			n = -n
			var t := b
			b = c
			c = t
		st.set_normal(n)
		for p in [a, c, b]:   # Godot は時計回りが表
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## 折り紙の多面体: 分割の少ない球を、少しゆがめて平らな面のまま（ラフの facet_ball と同じ）。half は (x, y, z) の半径（この節の座標）
func _facet(parent: Node3D, center: Vector3, half: Vector3, u: int, v: int, jit: float, seed: int, mat: Material) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rows: Array = []
	for j in v + 1:
		var lat := -PI / 2.0 + PI * j / v
		var row: Array = []
		for i in u:
			var a := TAU * i / u
			var p := Vector3(cos(lat) * cos(a), sin(lat), cos(lat) * sin(a))
			var q := center + p * half + Vector3(rng.randf_range(-jit, jit), rng.randf_range(-jit, jit), rng.randf_range(-jit, jit))
			if j == 0 or j == v:
				q = center + p * half
			row.append(q)
		rows.append(row)
	var tris := PackedVector3Array()
	for j in v:
		for i in u:
			var a: Vector3 = rows[j][i]
			var b: Vector3 = rows[j][(i + 1) % u]
			var c: Vector3 = rows[j + 1][(i + 1) % u]
			var d: Vector3 = rows[j + 1][i]
			if j > 0:
				tris.append_array([a, b, c])
			if j < v - 1:
				tris.append_array([a, c, d])
	return _flat(parent, tris, center, mat)


## 折った紙の裾広がり: (半径, 高さ) を上から下へ並べた輪郭を回した板。lon は回す範囲（ラフの角度。90° が前、270° が背中）
func _cone(parent: Node3D, prof: Array, n: int, sy: float, lon0: float, lon1: float, mat: Material) -> void:
	var full := lon1 - lon0 >= 360.0
	var cnt := n if full else n + 1
	var rows: Array = []
	for p in prof:
		var row: Array = []
		for i in cnt:
			var a := deg_to_rad(lon0 + (lon1 - lon0) * i / n)
			row.append(g(cos(a) * p.x, sin(a) * p.x * sy, p.y))
		rows.append(row)
	var tris := PackedVector3Array()
	for k in rows.size() - 1:
		for i in n:
			var j := (i + 1) % cnt
			tris.append_array([rows[k][i], rows[k + 1][i], rows[k + 1][j], rows[k][i], rows[k + 1][j], rows[k][j]])
	_flat(parent, tris, null, mat)


## 平たい紙の帯（衿・前足の毛皮）。wd は幅の向き（ZERO なら、体の軸から外へ向く面に沿わせる）。notch で端を燕尾に切る
func _ribbon(parent: Node3D, pts: Array, w: float, wd: Vector3, mat: Material, notch := 0.0) -> void:
	var rows: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var wi := wd
		if wi == Vector3.ZERO:
			wi = t.cross(Vector3(p.x, 0, p.z).normalized()).normalized()
		var row: Array = []
		for c in 3:
			var f := c / 2.0 - 0.5
			var q := p + wi * (f * w)
			if notch > 0.0 and i == pts.size() - 1:
				q -= t * notch * (1.0 - 2.0 * absf(f))
			row.append(q)
		rows.append(row)
	var tris := PackedVector3Array()
	for i in rows.size() - 1:
		for c in 2:
			tris.append_array([rows[i][c], rows[i][c + 1], rows[i + 1][c + 1], rows[i][c], rows[i + 1][c + 1], rows[i + 1][c]])
	_flat(parent, tris, null, mat)


## 管: 点の列に沿う。flat なら面の少ない折った筒（袖）、でなければ丸い糸
func _tube(parent: Node3D, pts: Array, r: float, sides: int, mat: Material, flat := false) -> void:
	var rings: Array = []
	var n := pts.size()
	for i in n:
		var t: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.1:
			side = t.cross(Vector3.FORWARD)
		side = side.normalized()
		var up := side.cross(t)
		var ring: Array = []
		for j in sides:
			var a := TAU * j / sides
			ring.append((pts[i] as Vector3) + (side * cos(a) + up * sin(a)) * r)
		rings.append(ring)
	if flat:
		var tris := PackedVector3Array()
		for i in n - 1:
			var cen: Vector3 = ((pts[i] as Vector3) + (pts[i + 1] as Vector3)) / 2.0
			for j in sides:
				var k := (j + 1) % sides
				tris.append_array([rings[i][j], rings[i + 1][j], rings[i + 1][k], rings[i][j], rings[i + 1][k], rings[i][k]])
		var mi := _flat(parent, tris, null, mat)
		_flat_reorient(mi, pts)
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		for j in sides:
			var k := (j + 1) % sides
			for p in [rings[i][j], rings[i + 1][k], rings[i + 1][j], rings[i][j], rings[i][k], rings[i + 1][k]]:
				var q: Vector3 = p
				var c: Vector3 = pts[i] if q in rings[i] else pts[i + 1]
				st.set_normal((q - c).normalized())
				st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)


## 折った筒の面の向きを、筒の芯から外へ直す（_flat は縦の軸から外へ向けるので、横に寝た袖では向きが乱れる）
func _flat_reorient(mi: MeshInstance3D, pts: Array) -> void:
	var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in range(0, vs.size(), 3):
		var mid := (vs[i] + vs[i + 1] + vs[i + 2]) / 3.0
		var best := Vector3.ZERO
		var bd := INF
		for k in pts.size() - 1:
			var q := Geometry3D.get_closest_point_to_segment(mid, pts[k], pts[k + 1])
			if q.distance_to(mid) < bd:
				bd = q.distance_to(mid)
				best = q
		if ns[i].dot(mid - best) < 0.0:
			for k in 3:
				ns[i + k] = -ns[i + k]
			var t := vs[i + 1]
			vs[i + 1] = vs[i + 2]
			vs[i + 2] = t
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m


# ---- 棚 --------------------------------------------------------------------------------

## 木の棚: 柱 2 本と板 2 段、上に白い和紙の毛皮を掛ける。品目ごとに、売っていれば道具を並べ、まだなら紙に包んで麻ひもで縛った包み
func _make_rack() -> void:
	var rack := Node3D.new()
	rack.name = "Rack"
	rack.position = Vector3(RACK_AT.x * rack_side, RACK_AT.y, RACK_AT.z)
	rack.rotation.y = -0.35 * rack_side   # 少し客の方へ向ける
	add_child(rack)
	var wood := Look.wood(Color(0.50, 0.33, 0.20))
	var dark := Look.wood(Color(0.36, 0.24, 0.15))
	const W := 1.2
	const D := 0.45
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(rack, Vector3(0.06, 1.5, 0.06), Vector3(sx * (W / 2.0 - 0.03), 0.75, sz * (D / 2.0 - 0.03)), dark)
	var shelves := [0.42, 0.9]
	for y in shelves:
		_box(rack, Vector3(W, 0.04, D), Vector3(0, y, 0), wood)
	_box(rack, Vector3(W + 0.1, 0.05, D + 0.1), Vector3(0, 1.52, 0), wood)
	var pelt := _paper(WHITE)   # 屋根の上の毛皮（多面体の和紙）
	_facet(rack, Vector3(0, 1.56, 0), Vector3(W * 0.55, 0.05, D * 0.7), 8, 3, 0.01, 60, pelt)
	for i in Goods.SHELF.size():
		var e: Dictionary = Goods.SHELF[i]
		var y: float = shelves[i % 2] + 0.02
		var at := Vector3(0.0, y, -0.02)
		if e.on or Goods.all_on:
			match e.item.kind:
				"campfire": _show_campfire(rack, at)
				"peg": _show_pegs(rack, at)
		else:
			_wrapped(rack, at, i)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(W, 1.6, D)
	cs.shape = box
	cs.position.y = 0.8
	body.add_child(cs)
	rack.add_child(body)


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


## 焚き火セットの見本: 毛糸を巻いた薪の束と、フェルトの石 3 つ
func _show_campfire(parent: Node3D, at: Vector3) -> void:
	var wood := Look.wood(Color(0.55, 0.38, 0.22))
	var yarns := [YARN_RED, Color(0.88, 0.66, 0.20), Color(0.24, 0.32, 0.55)]
	for k in 3:
		for j in 2:
			var stick := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.045
			cm.height = 0.42
			stick.mesh = cm
			stick.material_override = wood
			stick.rotation.z = PI / 2.0
			stick.position = at + Vector3(-0.2, 0.05 + j * 0.08, -0.09 + k * 0.09 - j * 0.045)
			parent.add_child(stick)
	for s in [-1.0, 1.0]:   # 束ねた毛糸
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.15
		tm.outer_radius = 0.17
		ring.mesh = tm
		ring.material_override = Look.felt(yarns[0 if s < 0 else 1], 4.0)
		ring.rotation.z = PI / 2.0
		ring.scale = Vector3(1.0, 1.0, 0.7)
		ring.position = at + Vector3(-0.2 + s * 0.11, 0.09, -0.02)
		parent.add_child(ring)
	var stones := [Color(0.55, 0.53, 0.52), Color(0.46, 0.40, 0.36), Color(0.42, 0.45, 0.50)]
	for k in 3:
		_facet(parent, at + Vector3(0.12 + k * 0.1, 0.04, 0.04 * (k % 2)), Vector3(0.05, 0.035, 0.045), 6, 4, 0.004, 70 + k, Look.felt(stones[k], 3.0))


## ペグの見本: 木の杭を 5 本、毛糸で束ねて立てかける
func _show_pegs(parent: Node3D, at: Vector3) -> void:
	var wood := Look.wood(Color(0.62, 0.45, 0.28))
	for k in 5:
		var peg := Node3D.new()
		peg.position = at + Vector3(0.12 + k * 0.045, 0.0, 0.05)
		peg.rotation.z = -0.25
		parent.add_child(peg)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.004
		cm.height = 0.36
		cm.radial_segments = 6
		mi.mesh = cm
		mi.material_override = wood
		mi.position.y = 0.18
		peg.add_child(mi)
		var loop := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.022
		tm.outer_radius = 0.03
		loop.mesh = tm
		loop.material_override = Look.felt([YARN_RED, Color(0.24, 0.32, 0.55)][k % 2], 4.0)
		loop.position.y = 0.33
		loop.rotation.x = PI / 2.0
		peg.add_child(loop)


## まだ売っていない品目: 白い紙に包んで、麻ひもで十字に縛った包み
func _wrapped(parent: Node3D, at: Vector3, i: int) -> void:
	var c := at + Vector3(0.0, 0.13, 0.0)
	_facet(parent, c, Vector3(0.3, 0.13, 0.15), 6, 3, 0.012, 80 + i, _paper(CREAM))
	var hemp := Look.felt(Color(0.78, 0.66, 0.46), 6.0)
	for k in 2:   # 腰を回る輪と、上から下へ回る輪（前から見て十字。包みに沿う楕円。輪は寝かせて作り、縦の輪は立てる）
		var pivot := Node3D.new()
		pivot.position = c
		pivot.rotation = Vector3.ZERO if k == 0 else Vector3(0, 0, PI / 2.0)
		parent.add_child(pivot)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.97
		tm.outer_radius = 1.03
		ring.mesh = tm
		ring.material_override = hemp
		ring.scale = Vector3(0.305, 0.08, 0.155) if k == 0 else Vector3(0.135, 0.08, 0.155)
		pivot.add_child(ring)


# ---- 動き（12 コマ／秒）----------------------------------------------------------------

## いちばん近い人（あなたとオンラインのほかの人。いなければ null）
func _nearest() -> Node3D:
	var best: Node3D = null
	var bd := NOTICE_R
	var people: Array = []
	if main and main.get("player"):
		people.append(main.player)
	var net = main.get_node_or_null("Net") if main else null
	if net and net.get("remotes") != null:
		people.append_array(net.remotes.values())
	for p in people:
		if p is Node3D and is_instance_valid(p):
			var d: float = (p as Node3D).global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = p
	return best


func _process(_dt: float) -> void:
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	_frame = fi
	_k += 1
	var you := _buyer if _buyer and is_instance_valid(_buyer) and _k < _buyer_until else _nearest()
	var near := you != null
	if near and not _noticed:
		_wave_from = _k
	_noticed = near
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
	_head.rotation = Vector3(-_head_pitch - nod, _head_yaw, 0.03 * sin(_k * 0.19))
	# 耳: ときどきぴくり。売れたら立つ（後ろへ倒れた耳が前へ）
	if _k >= _twitch_next:
		_twitch_next = _k + _rng.randi_range(40, 100)
	var tw := _twitch_next - _k
	var perk := _k - _perk_from
	for i in _ears.size():
		var ear: Node3D = _ears[i]
		var x := 0.0
		if perk >= 0 and perk < 10:
			x = [0.25, 0.4, 0.4, 0.35, 0.3, 0.25, 0.2, 0.12, 0.05, 0.0][perk]
		elif tw <= 2 and i == (_twitch_next / 7) % 2:
			x = -0.3
		ear.rotation = Vector3(x, 0, 0)
	# 息: 2 秒で一回、体がわずかにふくらむ（4 コマずつの段で）
	var br := 0.5 + 0.5 * sin(TAU * float(_k / 4 * 4) / 24.0)
	_body.scale = Vector3(1.0 + 0.008 * br, 1.0 + 0.012 * br, 1.0 + 0.008 * br)
	# 左腕: 振る。右腕: 棚を示す・買った人へ差し出す
	var w := _k - _wave_from
	if w >= 0 and w < 20:
		var up: float = [0.6, 1.4, 2.0, 2.2][mini(w, 3)] if w < 16 else [1.4, 0.7, 0.3, 0.0][w - 16]
		var sway := 0.0 if w < 4 or w >= 16 else (0.3 if (w / 2) % 2 == 0 else -0.15)
		_arm_l.rotation = Vector3(-0.2, 0, -up - sway)
	else:
		_arm_l.rotation = Vector3(0, 0, -0.03 * sin(_k * 0.3))
	var p := _k - _show_from
	if p >= 0 and p < 24:   # 棚の側の腕を、棚へ振って示す（右手の側は +X）
		var out: float = [0.4, 0.9, 1.2, 1.3][mini(p, 3)] if p < 20 else [0.9, 0.5, 0.2, 0.0][p - 20]
		(_arm_r if rack_side > 0.0 else _arm_l).rotation = Vector3(-0.6 * out, 0.9 * out * rack_side, 0)
		if rack_side < 0.0:
			_arm_r.rotation = Vector3(0, 0, 0.03 * sin(_k * 0.27))
	elif n >= 0 and n < 10:   # 買った人へ差し出す
		var o: float = [0.3, 0.7, 0.9, 0.9, 0.9, 0.8, 0.6, 0.4, 0.2, 0.0][n]
		_arm_r.rotation = Vector3(-o, 0, 0)
	else:
		_arm_r.rotation = Vector3(0, 0, 0.03 * sin(_k * 0.27))


## 売り場が開いた: 棚を示す
func greet() -> void:
	_show_from = _k + 1


## 売れた: 買った人を向いてうなずき、耳が立つ
func sold(buyer: Node3D) -> void:
	_nod_from = _k + 3
	_perk_from = _k + 1
	if buyer:
		_buyer = buyer
		_buyer_until = _k + 30


## だれかが山男の棚の品物を買った（通信では全員の画面に届く）
func _on_craft(ev: Dictionary) -> void:
	if ev.get("kind", "") != "buy" or not Goods.has(ev.get("item", {}).get("kind", "")):
		return
	sold(_person(int(ev.get("who", -1))))


## 人の番号から、その人の体（あなたか、オンラインのほかの人）
func _person(who: int) -> Node3D:
	if main and main.get("player") and int(main.player.get("id")) == who:
		return main.player
	var net = main.get_node_or_null("Net") if main else null
	if net and net.get("remotes") != null:
		for r in net.remotes.values():
			if is_instance_valid(r) and int(r.get("id")) == who:
				return r
	return null


## 話しかけられる所にいるか
func can_talk(who: Node3D) -> bool:
	var d := to_local(who.global_position)
	return Vector2(d.x, d.z).length() < TALK_R and absf(d.y) < 1.6
