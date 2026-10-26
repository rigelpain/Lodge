extends CharacterBody3D
## 押すのを手伝う仲間（通信を入れるまでの代わり）。
## ソリの下り側に回って頂上へ押す → 頂上であなたが乗ったら一緒に乗る → 下で降りてまた押す。

enum State { PUSH, WAIT, RIDE }

const SPEED := 4.0
const GRAVITY := 9.8

var sled: RigidBody3D
var player: Node3D          # いないとき（確かめ用）は仲間だけで滑る
var side := 1
var state := State.PUSH
var seat := Vector3.INF
var _col: CollisionShape3D
var _still := 0.0
var _wait := 0.0


func _ready() -> void:
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	_col.shape = cap
	_col.position.y = 0.85
	add_child(_col)

	# 紙の体にフェルトの上着と帽子
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.18, 0.44, 0.56) if side > 0 else Color(0.85, 0.63, 0.19)
	felt.roughness = 1.0
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.95, 0.93, 0.88)
	_part(CapsuleMesh.new(), Vector3(0, 0.85, 0), Vector3(0.75, 0.9, 0.75), felt)
	_part(SphereMesh.new(), Vector3(0, 1.62, 0), Vector3(0.5, 0.5, 0.5), paper)
	var hat := CylinderMesh.new()
	hat.top_radius = 0
	hat.bottom_radius = 0.24
	hat.height = 0.4
	_part(hat, Vector3(0, 1.95, 0), Vector3.ONE, felt)


func _part(mesh: Mesh, pos: Vector3, scl: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.scale = scl
	m.material_override = mat
	add_child(m)


func get_off() -> void:
	if seat == Vector3.INF:
		return
	sled.dismount(self)
	seat = Vector3.INF
	_col.disabled = false
	global_position = sled.global_position - sled.global_basis.x * 1.4 * side + Vector3.UP * 0.5
	velocity = Vector3.ZERO
	state = State.PUSH


func _uphill(p: Vector3) -> Vector3:
	var u := Vector3(-p.x, 0, -p.z)
	return u.normalized() if u.length() > 0.1 else Vector3.FORWARD


func _physics_process(dt: float) -> void:
	var s := sled.global_position
	var to_top := Vector2(s.x, s.z).length()

	if state == State.RIDE:
		global_position = sled.to_global(seat)
		# あなたがいないときは、仲間が体重をかけて滑り出す
		if player == null and to_top < 8.0:
			sled.lean(0.0, true)
		_still = _still + dt if sled.linear_velocity.length() < 0.4 else 0.0
		if _still > 1.5 and to_top > 14.0:
			_still = 0.0
			get_off()
		return

	var up := _uphill(s)
	var dir := Vector3.ZERO
	if state == State.PUSH:
		if to_top < 4.0:
			state = State.WAIT
			_wait = 0.0
		else:
			# ソリの下り側の、自分の持ち場へ回り込み、そこに着いたら押しながら一緒に登る
			var post := s - up * 1.6 + up.cross(Vector3.UP) * 0.45 * side
			var to := post - global_position
			to.y = 0
			dir = to.normalized() if to.length() > 0.2 else up
			if to.length() < 1.0:
				sled.push(up, global_position + up * 0.6 + Vector3.UP * 0.4)
	elif state == State.WAIT:
		_wait += dt
		var rider_ok: bool = player == null or (player.get("seat") != null and player.seat != Vector3.INF)
		if rider_ok and _wait > 1.0 and global_position.distance_to(s) < 3.5:
			seat = sled.mount(self)
			if seat != Vector3.INF:
				_col.disabled = true
				state = State.RIDE
				return
		var to := s - global_position
		to.y = 0
		if to.length() > 2.0:
			dir = to.normalized()
		if to_top > 6.0:
			state = State.PUSH   # 頂上からずり落ちたら押し直す

	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if dir.length() > 0.1:
		look_at(global_position + dir, Vector3.UP)
