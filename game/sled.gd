extends RigidBody3D
## 大きなソリ。誰が押しても push() を呼ぶだけ（あなたも仲間も、のちの通信の相手も同じ）。
## 押す人が少ないとじりじり、多いと目に見えて速く登る。乗る人がいると減速をゆるめて一気に滑る。

const PUSH_FORCE := 340.0   # 1人が押す力 (N)。1人でも最も急な所をじりじり登れる
const CLIMB_DAMP := 1.6     # 登るときの減速（押すのをやめるとすぐ止まる）
const RIDE_DAMP := 0.12     # 乗って滑るときの減速
const SEATS := [Vector3(0, 0.45, -0.75), Vector3(0, 0.45, 0.15), Vector3(0, 0.45, 1.0)]

var pushers := 0            # 前のコマで押していた人数（表示用）
var riders: Array[Node3D] = []
var _push_count := 0


func _ready() -> void:
	mass = 60.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)
	angular_damp = 3.0
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
	var f := dir.normalized() * PUSH_FORCE
	# 手の位置で押すとソリが回って横に逃げ、1人では登れなくなるので、力は台の中心にかける
	apply_force(f, global_basis * Vector3(0, 0.2, 0))
	_push_count += 1


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
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(), pos)


func _physics_process(_dt: float) -> void:
	pushers = _push_count
	_push_count = 0
	linear_damp = RIDE_DAMP if riders.size() > 0 else CLIMB_DAMP
	# 起き上がり: 大きく傾いたら少しずつ戻す
	var up := global_basis.y
	if up.y < 0.5:
		apply_torque(up.cross(Vector3.UP) * 400.0)
