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
var handle := Vector3.INF   # つかんでいる所（ソリの座標）
var _mitts: Array[MeshInstance3D] = []
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
	# 手袋。つかむとソリの縁に伸びる
	for sx in [-1, 1]:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		m.mesh = sm
		m.material_override = felt
		m.position = Vector3(0.45 * sx, 0.8, 0)
		m.set_meta("side", sx)
		add_child(m)
		_mitts.append(m)


func _part(mesh: Mesh, pos: Vector3, scl: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.scale = scl
	m.material_override = mat
	add_child(m)


func let_go() -> void:
	if handle == Vector3.INF:
		return
	sled.release_handle(self)
	handle = Vector3.INF
	_col.disabled = false
	velocity = Vector3.ZERO


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
			let_go()
			state = State.WAIT
			_wait = 0.0
		elif handle != Vector3.INF:
			# つかんでいる: 体はソリについて行き、縁に手をかけて頂上へ押す
			global_position = sled.to_global(handle)
			# 片側だけを押すとソリの向きがずれるので、ずれを打ち消す向きに少し斜めに押す
			var fwd: Vector3 = -sled.global_basis.z
			fwd.y = 0
			var err := atan2(fwd.cross(up).y, fwd.dot(up))
			var push_dir: Vector3 = up + sled.global_basis.x * clamp(err * 3.0, -1.0, 1.0) * 1.2
			sled.push(push_dir.normalized(), global_position + up * 0.6 + Vector3.UP * 0.4)
			var face := s - global_position
			face.y = 0
			if face.length() > 0.1:
				look_at(global_position + face, Vector3.UP)
			if sled.linear_velocity.length() > 5.0:
				let_go()
			_pose_mitts(dt)
			return
		else:
			# ソリの横の縁（後ろ寄り）の持ち場へ回り込み、着いたらつかむ。後ろの真ん中はあなたの分
			var post := s - up * 0.9 + up.cross(Vector3.UP) * 1.5 * side
			var to := post - global_position
			to.y = 0
			dir = to.normalized() if to.length() > 0.2 else up
			if to.length() < 0.8:
				var gp: Array = sled.grip_point_near(global_position)
				var stand: Vector3 = gp[0]
				if sled.take_handle(self, stand):
					handle = stand
					_col.disabled = true
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
	_pose_mitts(dt)


func _pose_mitts(dt: float) -> void:
	for m in _mitts:
		var sx: int = m.get_meta("side")
		var target := Vector3(0.28 * sx, 0.95, -0.5) if handle != Vector3.INF else Vector3(0.45 * sx, 0.8, 0)
		m.position = m.position.lerp(target, min(1.0, dt * 10.0))
