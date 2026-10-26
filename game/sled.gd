extends RigidBody3D
## 大きなソリ。誰が押しても push() を呼ぶだけ（あなたも仲間も、のちの通信の相手も同じ）。
## 押す人が少ないとじりじり、多いと目に見えて速く登る。乗る人がいると減速をゆるめて一気に滑る。

const PUSH_FORCE := 340.0   # 1人が押す力 (N)。1人でも最も急な所をじりじり登れる
const CLIMB_DAMP := 1.6     # 登るときの減速（押すのをやめるとすぐ止まる）
const RIDE_DAMP := 0.12     # 乗って滑るときの減速
const SEATS := [Vector3(0, 0.45, -0.75), Vector3(0, 0.45, 0.15), Vector3(0, 0.45, 1.0)]
const HALF := Vector2(0.75, 1.4)   # 台の半分の幅と長さ
const STAND := 0.6                 # つかむ人が立つ、縁からの距離
const ROPE_ANCHOR := Vector3(0, 0.3, -1.45)
const ROPE_LEN := 3.0
const ROPE_K := 260.0              # 紐が張ったときの引く力 (N/m)
const SLIP_RESIST := 18.0          # 滑り木の横滑りのしにくさ（前後 2 点それぞれ）
const RUNNER_Z := 1.1              # 滑り木の前後の接地点（中心からの距離）

var pushers := 0            # 前のコマで押していた人数（表示用）
var riders: Array[Node3D] = []
var holders := {}           # つかんでいる人 → つかんだ所（ソリの座標）
var rope_holder: Node3D = null
var _push_count := 0


func _ready() -> void:
	mass = 60.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)
	angular_damp = 6.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.04
	physics_material_override = pm

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 0.45, 2.8)
	col.shape = box
	col.position.y = 0.22
	add_child(col)

	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.88, 0.38, 0.23)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.36, 0.22)
	_box(Vector3(1.5, 0.25, 2.8), Vector3(0, 0.3, 0), red)
	_box(Vector3(1.5, 0.6, 0.18), Vector3(0, 0.6, 1.3), red)      # 背もたれ（後ろ）
	for x in [-0.6, 0.6]:
		_box(Vector3(0.12, 0.12, 3.1), Vector3(x, 0.08, -0.1), wood) # 滑り木


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = pos
	add_child(m)


## dir は押す向き（水平）、at は手が触れた所（世界座標）
func push(dir: Vector3, at: Vector3) -> void:
	dir.y = 0
	if dir.length() < 0.01:
		return
	var f: Vector3 = dir.normalized() * PUSH_FORCE * min(1.0, dir.length())
	# 力は手が触れている所にそのままかける。どう動くかは滑り木と重力が決める
	var p := to_local(at)
	p.x = clamp(p.x, -HALF.x, HALF.x)
	p.z = clamp(p.z, -HALF.y, HALF.y)
	p.y = 0.2
	apply_force(f, global_basis * p)
	_push_count += 1


## 立っている所（世界座標）から、ソリの縁のいちばん近いつかみ所と、押す向きを返す
## [立つ位置（ソリの座標）, 押す向き（ソリの座標）]
func grip_point_near(world_pos: Vector3) -> Array:
	var p := to_local(world_pos)
	var ex := HALF.x + STAND
	var ez := HALF.y + STAND
	if abs(p.x) / ex > abs(p.z) / ez:
		var sx := signf(p.x) if p.x != 0.0 else 1.0
		return [Vector3(sx * ex, 0, clamp(p.z, -HALF.y, HALF.y)), Vector3(-sx, 0, 0)]
	var sz := signf(p.z) if p.z != 0.0 else 1.0
	return [Vector3(clamp(p.x, -HALF.x, HALF.x), 0, sz * ez), Vector3(0, 0, -sz)]


func take_handle(who: Node3D, h: Vector3) -> bool:
	for other in holders:
		if other != who and holders[other].distance_to(h) < 0.7:
			return false
	holders[who] = h
	return true


func release_handle(who: Node3D) -> void:
	holders.erase(who)


func take_rope(who: Node3D) -> bool:
	if rope_holder != null and rope_holder != who:
		return false
	rope_holder = who
	return true


func release_rope(who: Node3D) -> void:
	if rope_holder == who:
		rope_holder = null


## 紐を持つ人の手の位置から、張っていれば引く。張った分の長さを返す（たるみなら負）
func pull_rope(hand: Vector3) -> float:
	var anchor := to_global(ROPE_ANCHOR)
	var d := hand - anchor
	var over := d.length() - ROPE_LEN
	if over > 0.0:
		var dir := d
		dir.y = 0
		apply_force(dir.normalized() * min(over * ROPE_K, 600.0), anchor - global_position)
		_push_count += 1
	return over




func mount(who: Node3D) -> Vector3:
	if riders.size() >= SEATS.size() or who in riders:
		return Vector3.INF
	riders.append(who)
	return SEATS[riders.size() - 1]


func dismount(who: Node3D) -> void:
	riders.erase(who)


## 乗っている人の操作。steer は -1〜1、forward は前へ体重をかける
func lean(steer: float, forward: bool) -> void:
	apply_torque(Vector3.UP * -steer * 120.0)
	if forward:
		var f := -global_basis.z
		f.y = 0
		apply_central_force(f.normalized() * 160.0)


func reset_to(pos: Vector3) -> void:
	for r in riders.duplicate():
		if r.has_method("get_off"):
			r.get_off()
	for who in holders.keys():
		if who.has_method("let_go"):
			who.let_go()
	if rope_holder and rope_holder.has_method("let_go"):
		rope_holder.let_go()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(), pos)


func _physics_process(_dt: float) -> void:
	pushers = _push_count
	_push_count = 0
	linear_damp = RIDE_DAMP if riders.size() > 0 else CLIMB_DAMP
	# 滑り木: 前後にはよく滑り、横には滑らない。前後 2 点で横滑りを止めるので、
	# 縁に偏った力をかけると、横にずれるのでなく向きが変わる
	var side := global_basis.x
	for z in [-RUNNER_Z, RUNNER_Z]:
		var r := global_basis * Vector3(0, 0, z)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var slip := side * v_point.dot(side)
		apply_force(-slip * mass * SLIP_RESIST * 0.5, r)
	# 起き上がり: 大きく傾いたら少しずつ戻す
	var up := global_basis.y
	if up.y < 0.5:
		apply_torque(up.cross(Vector3.UP) * 400.0)
