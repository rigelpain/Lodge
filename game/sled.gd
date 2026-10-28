extends RigidBody3D

const Props := preload("res://props.gd")
## 大きなソリ。誰が押しても push() を呼ぶだけ（あなたも仲間も、のちの通信の相手も同じ）。
## 押す人が少ないとじりじり、多いと目に見えて速く登る。乗る人がいると減速をゆるめて一気に滑る。

const PUSH_FORCE := 300.0   # 1人が押す力 (N)。1人でも最も急な所をじりじり登れる
const CLIMB_DAMP := 3.5     # 登るときの雪の抵抗（押すのをやめるとすぐ止まる。大きいほどじりじり）
const RIDE_DAMP := 0.12     # 乗って滑るときの減速
const SEATS := [Vector3(0, 0.45, -0.75), Vector3(0, 0.45, 0.15), Vector3(0, 0.45, 1.0)]
const HALF := Vector2(0.75, 1.4)   # 台の半分の幅と長さ
const STAND := 0.6                 # つかむ人が立つ、縁からの距離
const ROPE_ANCHOR := Vector3(0, 0.3, -1.45)
const ROPE_LEN := 3.0
const ROPE_K := 260.0              # 紐が張ったときの引く力 (N/m)
const SLIP_RESIST := 18.0          # 滑り木の横滑りのしにくさ（前後 2 点それぞれ）
const RUNNER_Z := 1.1              # 滑り木の前後の接地点（中心からの距離）
const RUNNER_X := 0.6              # 左右の滑り木の位置
const RUNNER_DRAG := 3.0           # 滑り木 1 本の前後方向の抵抗 (N per m/s)
const LEAN_DIG := 14.0             # 体重をかけた側の滑り木が食い込んで増える抵抗
const BRAKE_DRAG := 14.0           # 後ろに体重をかけたときの制動（両側）
const HOLD_FRICTION := 0.45        # 遅いときに働く静止摩擦（重さに対する割合）。丘のどこでも留まり、1人が押せば動き出す

var pushers := 0            # 前のコマで押していた人数（表示用）
var riders: Array[Node3D] = []
var holders := {}           # つかんでいる人 → つかんだ所（ソリの座標）
var rope_holder: Node3D = null
var _push_count := 0
var _steer := 0.0           # 乗っている人の左右の体重移動の合計（このコマ）
var _lean_fwd := false
var _lean_back := false
var hold_debug := ""


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

	# 見た目: フェルトの座布団を曲げ木の滑り木に載せたソリ（props/build_sled.py の glb）。寸法はこの物理に合わせてある
	add_child(Props.make("res://props/sled_mid.glb"))


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


## 乗っている人の体重移動。steer は -1（左）〜1（右）、forward は前傾、back は後傾。
## 力を直接かけるのではなく、滑り木の食い込み（抵抗）が変わることで曲がる・止まる
func lean(steer: float, forward: bool, back: bool = false) -> void:
	_steer += steer
	_lean_fwd = _lean_fwd or forward
	_lean_back = _lean_back or back


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


func _ground_normal() -> Vector3:
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.normal if hit else Vector3.UP


func _physics_process(_dt: float) -> void:
	pushers = _push_count
	_push_count = 0
	var riding := riders.size() > 0
	linear_damp = (RIDE_DAMP * (0.4 if _lean_fwd else 1.0)) if riding else CLIMB_DAMP
	var side := global_basis.x
	var fwd := -global_basis.z
	# 滑り木: 前後にはよく滑り、横には滑らない。前後 2 点で横滑りを止めるので、
	# 縁に偏った力をかけると、横にずれるのでなく向きが変わる
	# 止まっているときは横滑りの抵抗を弱め、人が押してソリの向きを変えられるようにする
	var slip_k: float = SLIP_RESIST * (0.3 if linear_velocity.length() < 0.6 else 1.0)
	for z in [-RUNNER_Z, RUNNER_Z]:
		var r := global_basis * Vector3(0, 0, z)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var slip := side * v_point.dot(side)
		apply_force(-slip * mass * slip_k * 0.5, r)
	# 左右の滑り木の前後方向の抵抗。体重をかけた側が雪に食い込んで抵抗が増え、曲がる。
	# 後ろに体重をかけると両側が食い込んで止まる
	var steer: float = clamp(_steer, -1.0, 1.0)
	for x in [-RUNNER_X, RUNNER_X]:
		var r := global_basis * Vector3(x, 0, 0)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var v_long := v_point.dot(fwd)
		var c := RUNNER_DRAG
		if riding:
			if steer * signf(x) > 0.0:
				c += LEAN_DIG * abs(steer)
			if _lean_back:
				c += BRAKE_DRAG
		apply_force(-fwd * v_long * c, r)
	# 遅いソリは静止摩擦で坂に留まる（乗っている人がいないとき）。押せばその分だけ動く
	var speed := linear_velocity.length()
	if speed < 0.8 and not riding:
		var n := _ground_normal()
		var g := Vector3(0, -9.8, 0)
		var g_t := g - n * g.dot(n)
		var hold := -g_t * mass
		var cap: float = HOLD_FRICTION * mass * 9.8 * abs(n.y)
		if hold.length() > cap:
			hold = hold.normalized() * cap
		apply_central_force(hold)
		if _push_count == 0 and pushers == 0:
			linear_velocity *= 0.9
		hold_debug = "n.y=%.2f 力=%.0f" % [n.y, hold.length()]
	else:
		hold_debug = "なし(速さ%.2f 押%d/%d 乗%d)" % [speed, _push_count, pushers, riders.size()]
	# 頂上などで、乗ったまま前傾すると手で雪をかいて動き出す
	if riding and _lean_fwd and speed < 1.5:
		apply_central_force(Vector3(fwd.x, 0, fwd.z).normalized() * 120.0)
	_steer = 0.0
	_lean_fwd = false
	_lean_back = false
	# 起き上がり: 大きく傾いたら少しずつ戻す
	var up := global_basis.y
	if up.y < 0.5:
		apply_torque(up.cross(Vector3.UP) * 400.0)
