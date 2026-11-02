extends Node3D
## 山の道具（焚き火セット・ペグ）を売る山男（2026-11-01 代表「そういう道具類を売ってくれる山男？山師？みたいなキャラが欲しい」）。
## 姿はラフの C「狼の毛皮の山男」（person/ideas/yamaotoko。代表が 3 案から選んだ。ボードの白い和紙の狼と、折り紙の着物の人から）:
## 藍の和紙を折った長い上着、クリームの紙の衿を左前に重ね、赤い毛糸の帯。白い和紙の狼の頭を頭巾にかぶり、毛皮を背中へ垂らし、
## 前足の毛皮を肩から胸へ。顔は折り紙の多面体に、黒い糸の閉じた目。
## 形は人形と同じ作り（2026-11-02 代表「山師がアートコンセプトに沿ってない気がする。キャラの要素は良いんだけど」）:
## person/ideas/yamaotoko/roughs.py --export で、紙と糸の素材で組み、骨を入れ、色と凹凸とくぼみの陰を焼いた game/person/yamaotoko.glb。
## 上着は青海波を刷った藍の和紙（裏と縁は白）、裾・衿・頭巾の縁に生成りの糸のなみ縫い、帯は前で結んで垂らす。足もとに青いやわらかい影
## 置き場所はロッジの 1 階の、大きなミシンの奥（main.gd の MOUNTAIN_MAN）。
## 横（rack_side の側）に木の棚を置き、山の道具を並べる。まだ売っていない品目（mountain_goods.gd の on が false）は、白い紙に包んで麻ひもで縛ってある。
## 動きは人形と同じ 12 コマ／秒に刻む（コマの間は止める）:
##   待つ   息をするように体がわずかにふくらむ。ときどき見回す
##   気づく 人が近づくと顔を向け、左手を挙げて小さく振る。近くに何人かいれば、いちばん近い人を見る（オンラインのほかの人も）
##   売る   売り場（mountain_ui.gd）が開くと、棚の側の手で棚を示す。だれかが買うと（ほかの人の買い物でも）その人を向いてうなずき、手を差し出す
## F で話しかける（player.gd の mountain_near）。

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Goods := preload("res://mountain_goods.gd")

const MODEL := "res://person/yamaotoko.glb"
const SCALE := 1.3           # ラフ（1.33 m）から、ゲームの人と並ぶ大きさへ（おじいさんと同じくらい）
const FOOT_SHADOW := 0.42    # 足もとの影の半径（ラフの大きさのまま。人形の FOOT_SHADOW と同じ考え）
const NOTICE_R := 4.0        # この距離に人が来ると気づく (m)
const TALK_R := 2.4          # F で話しかけられる距離 (m)
const RACK_AT := Vector3(1.15, 0, 0.1)   # 棚の位置（山男の座標。+X が右手の側。rack_side で左右を替える）

const WHITE := Color("EEE8DC")
const CREAM := Color("EBD9BC")
const YARN_RED := Color("B8402E")

var main: Node               # main.gd（人と craft を探す）
var craft: Node
var shop_open := false       # 売り場が開いている（mountain_ui.gd が入れる）
var rack_side := 1.0         # 棚を置く側（1 右手、-1 左手。main.gd が入れる）
var _model: Node3D           # yamaotoko.glb
var _skel: Skeleton3D
var _frame := -1
var _k := 0
var _noticed := false
var _wave_from := -100
var _show_from := -100       # 棚を示し始めたコマ
var _nod_from := -100
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
	_model = (load(MODEL) as PackedScene).instantiate()
	_model.name = "Doll"
	_model.scale = Vector3.ONE * SCALE
	add_child(_model)
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_make_foot_shadow()
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


func _paper(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := Look.paper(c)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[c] = m
	return _mats[c]


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


## 骨を、骨の座標の空間（前は -Z、右は +X）の回転 e（オイラー角）で、付け根を軸に回す。親の骨は休みの姿のままとする
func _pose(bone: String, e: Vector3) -> void:
	var i := _skel.find_bone(bone)
	if i < 0:
		return
	var gr := _skel.get_bone_global_rest(i).basis.orthonormalized()
	var lr := _skel.get_bone_rest(i).basis.orthonormalized()
	_skel.set_bone_pose_rotation(i, (lr * (gr.inverse() * Basis.from_euler(e) * gr)).get_rotation_quaternion())


## 足もとに、やわらかい丸い影（人形と同じ: 雪の影と同じ青み。doll.gd の _make_foot_shadow）
func _make_foot_shadow() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.85, 1.0])
	g.colors = PackedColorArray([Color(0.08, 0.1, 0.2, 0.85), Color(0.08, 0.1, 0.2, 0.75), Color(0.08, 0.1, 0.2, 0.3), Color(0.08, 0.1, 0.2, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var d := Decal.new()
	var r := FOOT_SHADOW * SCALE
	d.size = Vector3(r * 2.0, 0.36, r * 2.0)
	d.texture_albedo = tex
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.position = Vector3(0, 0.02, 0)
	add_child(d)


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
	_pose("head", Vector3(-_head_pitch - nod, _head_yaw, 0.03 * sin(_k * 0.19)))
	# 息: 2 秒で一回、体がわずかにふくらむ（4 コマずつの段で）
	var br := 0.5 + 0.5 * sin(TAU * float(_k / 4 * 4) / 24.0)
	_model.scale = Vector3(1.0 + 0.008 * br, 1.0 + 0.012 * br, 1.0 + 0.008 * br) * SCALE
	# 左腕: 振る。右腕: 棚を示す・買った人へ差し出す
	var w := _k - _wave_from
	if w >= 0 and w < 20:
		var up: float = [0.6, 1.4, 2.0, 2.2][mini(w, 3)] if w < 16 else [1.4, 0.7, 0.3, 0.0][w - 16]
		var sway := 0.0 if w < 4 or w >= 16 else (0.3 if (w / 2) % 2 == 0 else -0.15)
		_pose("upper_arm.L", Vector3(-0.2, 0, -up - sway))
	else:
		_pose("upper_arm.L", Vector3(0, 0, -0.03 * sin(_k * 0.3)))
	var p := _k - _show_from
	if p >= 0 and p < 24:   # 棚の側の腕を、棚へ振って示す（右手の側は +X）
		var out: float = [0.4, 0.9, 1.2, 1.3][mini(p, 3)] if p < 20 else [0.9, 0.5, 0.2, 0.0][p - 20]
		_pose("upper_arm.R" if rack_side > 0.0 else "upper_arm.L", Vector3(-0.6 * out, 0.9 * out * rack_side, 0))
		if rack_side < 0.0:
			_pose("upper_arm.R", Vector3(0, 0, 0.03 * sin(_k * 0.27)))
	elif n >= 0 and n < 10:   # 買った人へ差し出す
		var o: float = [0.3, 0.7, 0.9, 0.9, 0.9, 0.8, 0.6, 0.4, 0.2, 0.0][n]
		_pose("upper_arm.R", Vector3(-o, 0, 0))
	else:
		_pose("upper_arm.R", Vector3(0, 0, 0.03 * sin(_k * 0.27)))


## 売り場が開いた: 棚を示す
func greet() -> void:
	_show_from = _k + 1


## 売れた: 買った人を向いてうなずき、手を差し出す
func sold(buyer: Node3D) -> void:
	_nod_from = _k + 3
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
