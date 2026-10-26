extends CharacterBody3D
## あなた。一人称で、見えるのはフェルトの手袋をした両手だけ。
## ソリに向かって W で押す（ふさぐのも、逆から押すのも同じ仕組みでできる）。

const SPEED := 4.0
const JUMP := 4.5
const GRAVITY := 9.8
const REACH := 1.4

var sled: RigidBody3D
var cam: Camera3D
var hands: Array[Node3D] = []
var seat := Vector3.INF
var pushing := false
var _col: CollisionShape3D
var _t := 0.0


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
		if e.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif e.physical_keycode == KEY_E:
			if seat == Vector3.INF:
				get_on()
			else:
				get_off()


func get_on() -> void:
	if global_position.distance_to(sled.global_position) > 2.8:
		return
	seat = sled.mount(self)
	if seat != Vector3.INF:
		_col.disabled = true


func get_off() -> void:
	if seat == Vector3.INF:
		return
	sled.dismount(self)
	seat = Vector3.INF
	_col.disabled = false
	global_position = sled.global_position + sled.global_basis.x * 1.4 + Vector3.UP * 0.5
	velocity = Vector3.ZERO


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _physics_process(dt: float) -> void:
	_t += dt
	pushing = false

	if seat != Vector3.INF:
		global_position = sled.to_global(seat)
		sled.lean(_key(KEY_D) - _key(KEY_A), Input.is_physical_key_pressed(KEY_W))
		_pose_hands(dt, true)
		return

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

	# 前に手を伸ばして、ソリに届けば押す
	if input.y < 0:
		var fwd := -global_basis.z
		var from := global_position + Vector3(0, 0.45, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * REACH)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit and hit.collider == sled:
			sled.push(fwd, hit.position)
			pushing = true
	_pose_hands(dt, false)


func _pose_hands(dt: float, riding: bool) -> void:
	for h in hands:
		var s: int = h.get_meta("side")
		var target: Vector3
		if pushing:
			# 押すときは両手を前に、歩みに合わせて少し揺れる
			target = Vector3(0.18 * s, -0.24 + sin(_t * 9.0 + s) * 0.02, -0.55)
		elif riding:
			target = Vector3(0.28 * s, -0.32, -0.35)
		else:
			target = Vector3(0.3 * s, -0.3 + sin(_t * 6.0 + s) * 0.01 * velocity.length(), -0.45)
		h.position = h.position.lerp(target, clamp(dt * 12.0, 0.0, 1.0))
