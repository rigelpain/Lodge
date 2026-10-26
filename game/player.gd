extends CharacterBody3D
## あなた。一人称で、見えるのはフェルトの手袋をした両手だけ。
## ソリの後ろの取っ手を F でつかむ（近くで W を押し続けても吸い付く）。
## つかんだまま W で押し、A/D で向きを変え、S を引き続けるか F で手を離す。
## ふさぐのも、逆から押すのも、取っ手でなく横や前からつかめば同じ仕組みでできる。

const SPEED := 4.0
const JUMP := 4.5
const GRAVITY := 9.8
const GRAB_REACH := 2.2      # F でつかめる距離 (m)
const SNAP_REACH := 1.1      # W で歩いて近づくと吸い付く距離 (m)
const LET_GO_SPEED := 5.0    # ソリがこれより速く滑ると手が離れる (m/s)

enum Mode { WALK, GRIP, RIDE }

var sled: RigidBody3D
var cam: Camera3D
var hands: Array[Node3D] = []
var mode := Mode.WALK
var seat := Vector3.INF
var handle := Vector3.INF    # つかんでいる取っ手（ソリの座標）
var pushing := false
var prompt := ""             # 画面に出す一言（main.gd が読む）
var _col: CollisionShape3D
var _t := 0.0
var _pull := 0.0             # S を引き続けた時間
var _snap := 0.0             # 吸い付きの途中（0→1）


func _ready() -> void:
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	_col.shape = cap
	_col.position.y = 0.85
	add_child(_col)

	cam = Camera3D.new()
	cam.position.y = 1.55
	cam.fov = 75
	cam.near = 0.05
	add_child(cam)
	cam.make_current()

	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.85, 0.33, 0.31)
	felt.roughness = 1.0
	for s in [-1, 1]:
		var h := Node3D.new()
		cam.add_child(h)
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		m.mesh = sm
		m.scale = Vector3(1.0, 0.8, 1.4)
		m.material_override = felt
		h.add_child(m)
		var thumb := MeshInstance3D.new()
		var tm := SphereMesh.new()
		tm.radius = 0.03
		tm.height = 0.06
		thumb.mesh = tm
		thumb.material_override = felt
		thumb.position = Vector3(-0.06 * s, 0.03, -0.02)
		h.add_child(thumb)
		h.set_meta("side", s)
		hands.append(h)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * 0.003)
		cam.rotation.x = clamp(cam.rotation.x - e.relative.y * 0.003, -1.4, 1.3)
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				if mode == Mode.GRIP:
					let_go()
				elif mode == Mode.WALK:
					grab()
			KEY_E:
				if mode == Mode.RIDE:
					get_off()
				else:
					get_on()


## いちばん近い取っ手。届かなければ INF
func _nearest_handle(reach: float) -> Vector3:
	var best := Vector3.INF
	var best_d := reach
	for h in sled.HANDLES:
		var d := global_position.distance_to(sled.to_global(h))
		if d < best_d:
			best_d = d
			best = h
	return best


func grab() -> void:
	var h := _nearest_handle(GRAB_REACH)
	if h == Vector3.INF or not sled.take_handle(self, h):
		return
	handle = h
	mode = Mode.GRIP
	_col.disabled = true
	_snap = 0.0
	_pull = 0.0
	# 体をソリの進む向きに向ける（視線はそのあと自由）
	var fwd := -sled.global_basis.z
	rotation.y = atan2(-fwd.x, -fwd.z)


func let_go() -> void:
	if mode != Mode.GRIP:
		return
	sled.release_handle(self)
	handle = Vector3.INF
	mode = Mode.WALK
	_col.disabled = false
	velocity = Vector3.ZERO


func get_on() -> void:
	if global_position.distance_to(sled.global_position) > 2.8:
		return
	var s: Vector3 = sled.mount(self)
	if s == Vector3.INF:
		return
	if mode == Mode.GRIP:
		sled.release_handle(self)
		handle = Vector3.INF
	seat = s
	mode = Mode.RIDE
	_col.disabled = true


func get_off() -> void:
	if mode != Mode.RIDE:
		return
	sled.dismount(self)
	seat = Vector3.INF
	mode = Mode.WALK
	_col.disabled = false
	global_position = sled.global_position + sled.global_basis.x * 1.4 + Vector3.UP * 0.5
	velocity = Vector3.ZERO


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _physics_process(dt: float) -> void:
	_t += dt
	pushing = false
	prompt = ""

	match mode:
		Mode.RIDE:
			global_position = sled.to_global(seat)
			sled.lean(_key(KEY_D) - _key(KEY_A), Input.is_physical_key_pressed(KEY_W))
			prompt = "W 前へ　A/D 曲がる　E 降りる"
		Mode.GRIP:
			_grip(dt)
		Mode.WALK:
			_walk(dt)
	_pose_hands(dt)


func _walk(dt: float) -> void:
	var input := Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_S) - _key(KEY_W))
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()

	var h := _nearest_handle(GRAB_REACH)
	if h == Vector3.INF:
		return
	var hp := sled.to_global(h)
	var to := hp - global_position
	to.y = 0
	var facing := to.normalized().dot(-global_basis.z) > 0.6
	# 前へ歩いて取っ手に触れたら吸い付く
	if input.y < 0 and facing and to.length() < SNAP_REACH:
		grab()
		return
	if facing:
		prompt = "F でソリをつかむ"


func _grip(dt: float) -> void:
	# 手が取っ手に吸い付き、体はソリについて行く
	_snap = min(1.0, _snap + dt * 5.0)
	var target := sled.to_global(handle)
	global_position = global_position.lerp(target, _snap) if _snap < 1.0 else target
	velocity = Vector3.ZERO

	var fwd := -sled.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	if Input.is_physical_key_pressed(KEY_W):
		sled.push(fwd, sled.to_global(handle) + fwd * 0.6 + Vector3.UP * 0.5)
		pushing = true
	var steer := _key(KEY_D) - _key(KEY_A)
	if steer != 0.0:
		sled.steer_from_handle(steer)

	# 後ろへ引き続けると手を離す
	_pull = _pull + dt if Input.is_physical_key_pressed(KEY_S) else 0.0
	if _pull > 0.35 or sled.linear_velocity.length() > LET_GO_SPEED:
		let_go()
		global_position -= fwd * 0.6
		return

	prompt = "押している　A/D 向き　S 手を離す　E 乗る" if pushing else "W 押す　A/D 向き　S 手を離す　E 乗る"


func _pose_hands(dt: float) -> void:
	var bob := sin(_t * 9.0)
	# 押すと視点がわずかに揺れ、画角が少し広がる
	cam.position.y = lerp(cam.position.y, 1.55 + (bob * 0.02 if pushing else 0.0), min(1.0, dt * 10.0))
	cam.fov = lerp(cam.fov, 79.0 if pushing else 75.0, min(1.0, dt * 4.0))
	for h in hands:
		var s: int = h.get_meta("side")
		var target: Vector3
		if mode == Mode.GRIP:
			# 取っ手を握る。押すと腕が少し伸びる
			var reach := -0.5 - (0.06 if pushing else 0.0)
			target = Vector3(0.17 * s, -0.22 + (bob * 0.015 if pushing else 0.0), reach)
		elif mode == Mode.RIDE:
			target = Vector3(0.28 * s, -0.32, -0.35)
		else:
			target = Vector3(0.3 * s, -0.3 + sin(_t * 6.0 + s) * 0.01 * velocity.length(), -0.45)
		h.position = h.position.lerp(target, clamp(dt * 12.0, 0.0, 1.0))
