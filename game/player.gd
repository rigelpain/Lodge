extends CharacterBody3D
## あなた。一人称で、見えるのはフェルトの手袋をした両手だけ。
## ソリのまわりのどこからでも F でつかめる。
## つかんだまま WASD で、見ている向きを基準にソリへ力をかける（W 前へ押す、S 手前へ引く、A/D 左右へ）。
## どう動くかはソリの滑り木と重力が決める。離すのは F だけ。Shift でダッシュ。
## 前に回って F を押すと紐を持ち、歩いて引ける。

const SPEED := 4.0
const DASH := 7.0            # Shift で走る速さ
const SPEED_TAUT := 2.6      # 紐が張っているときの歩く速さ
const JUMP := 4.5
const GRAVITY := 9.8
const GRAB_REACH := 2.2      # F でつかめる、立つ位置までの距離 (m)
const LET_GO_SPEED := 5.0    # ソリがこれより速く滑ると手が離れる (m/s)
const ROPE_SEGS := 14

enum Mode { WALK, GRIP, RIDE, ROPE }

var sled: RigidBody3D
var cam: Camera3D
var hands: Array[Node3D] = []
var mode := Mode.WALK
var seat := Vector3.INF
var handle := Vector3.INF    # つかんでいる所（ソリの座標）
var push_dir := Vector3.ZERO # 押す向き（ソリの座標）
var pushing := false
var pulling := false
var prompt := ""             # 画面に出す一言（main.gd が読む）
var base_fov := 75.0         # ホイールで変える視野角
var _col: CollisionShape3D
var _t := 0.0
var _snap := 0.0             # 吸い付きの途中（0→1）
var _rope: Array[MeshInstance3D] = []


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

	# 紐: 短い円柱をつないで描く（持っていないときはソリの前に垂れている）
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.82, 0.72, 0.5)
	rope_mat.roughness = 1.0
	for i in ROPE_SEGS:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.022
		cm.bottom_radius = 0.022
		cm.height = 1.0
		cm.radial_segments = 6
		seg.mesh = cm
		seg.material_override = rope_mat
		seg.top_level = true
		add_child(seg)
		_rope.append(seg)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * 0.003)
		cam.rotation.x = clamp(cam.rotation.x - e.relative.y * 0.003, -1.4, 1.3)
	elif e is InputEventMagnifyGesture:
		# トラックパッドのピンチ: 広げると寄る（視野角が狭まる）
		base_fov = clamp(base_fov / e.factor, 50.0, 110.0)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			base_fov = clamp(base_fov - 3.0, 50.0, 110.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			base_fov = clamp(base_fov + 3.0, 50.0, 110.0)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				match mode:
					Mode.GRIP, Mode.ROPE:
						let_go()
					Mode.WALK:
						if _rope_end_near():
							grab_rope()
						else:
							grab()
			KEY_E:
				if mode == Mode.RIDE:
					get_off()
				else:
					get_on()


## 紐の先（ソリの前）に近いか
func _rope_end_near() -> bool:
	var p: Vector3 = sled.to_local(global_position)
	return p.z < -sled.HALF.y - 0.3 and abs(p.x) < 1.3 and p.length() < sled.HALF.y + GRAB_REACH


func grab() -> void:
	var gp: Array = sled.grip_point_near(global_position)
	var stand: Vector3 = gp[0]
	if global_position.distance_to(sled.to_global(stand)) > GRAB_REACH:
		return
	if not sled.take_handle(self, stand):
		return
	handle = stand
	push_dir = gp[1]
	mode = Mode.GRIP
	_col.disabled = true
	_snap = 0.0
	# 体を押す向きに向ける（視線はそのあと自由）
	var fwd: Vector3 = sled.global_basis * push_dir
	rotation.y = atan2(-fwd.x, -fwd.z)


func grab_rope() -> void:
	if not sled.take_rope(self):
		return
	mode = Mode.ROPE


func let_go() -> void:
	match mode:
		Mode.GRIP:
			sled.release_handle(self)
			handle = Vector3.INF
			_col.disabled = false
		Mode.ROPE:
			sled.release_rope(self)
		_:
			return
	mode = Mode.WALK
	velocity = Vector3.ZERO


func get_on() -> void:
	if global_position.distance_to(sled.global_position) > 2.8:
		return
	var s: Vector3 = sled.mount(self)
	if s == Vector3.INF:
		return
	if mode == Mode.GRIP or mode == Mode.ROPE:
		let_go()
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
	pulling = false
	prompt = ""

	match mode:
		Mode.RIDE:
			global_position = sled.to_global(seat)
			sled.lean(_key(KEY_D) - _key(KEY_A), Input.is_physical_key_pressed(KEY_W))
			prompt = "W 前へ　A/D 曲がる　E 降りる"
		Mode.GRIP:
			_grip(dt)
		Mode.ROPE:
			_walk(dt, true)
		Mode.WALK:
			_walk(dt, false)
	_pose_hands(dt)
	_draw_rope()


func _walk(dt: float, with_rope: bool) -> void:
	var input := Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_S) - _key(KEY_W))
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := DASH if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED
	if with_rope:
		# 紐が張っていれば、手の位置から引く。引いている間は歩みが重くなる
		var over: float = sled.pull_rope(_hand_world())
		if over > 0.0:
			pulling = true
			speed = SPEED_TAUT
		# 紐より遠くへは行けない
		var anchor: Vector3 = sled.to_global(sled.ROPE_ANCHOR)
		var d := global_position - anchor
		d.y = 0
		if d.length() > sled.ROPE_LEN + 0.3:
			global_position = anchor + d.normalized() * (sled.ROPE_LEN + 0.3) + Vector3(0, global_position.y - anchor.y, 0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()

	if with_rope:
		if sled.linear_velocity.length() > LET_GO_SPEED:
			let_go()
			return
		prompt = "紐を引いている　F 手を離す" if pulling else "紐を持っている　歩くと引ける　F 手を離す"
		return

	if _rope_end_near():
		prompt = "F で紐を持つ"
		return
	var gp: Array = sled.grip_point_near(global_position)
	var stand_w: Vector3 = sled.to_global(gp[0])
	if global_position.distance_to(stand_w) > GRAB_REACH:
		return
	var fwd: Vector3 = sled.global_basis * gp[1]
	fwd.y = 0
	if fwd.normalized().dot(-global_basis.z) > 0.6:
		prompt = "F でソリをつかむ"


func _grip(dt: float) -> void:
	# 手が縁に吸い付き、体はソリについて行く
	_snap = min(1.0, _snap + dt * 5.0)
	var target: Vector3 = sled.to_global(handle)
	global_position = global_position.lerp(target, _snap) if _snap < 1.0 else target
	velocity = Vector3.ZERO

	# 視点基準の WASD を、つかんでいる所にかける力の向きにする
	var input := Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_S) - _key(KEY_W))
	var fwd: Vector3 = -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	if input.length() > 0.0:
		var dir := (global_basis * Vector3(input.x, 0, input.y))
		dir.y = 0
		sled.push(dir.normalized(), target + Vector3.UP * 0.5)
		pushing = true

	# 速く滑り出したら手が離れる
	if sled.linear_velocity.length() > LET_GO_SPEED:
		let_go()
		global_position -= fwd * 0.6
		return

	prompt = "力をかけている　F 手を離す　E 乗る" if pushing else "WASD 見ている向きを基準に力をかける　F 手を離す　E 乗る"


## 紐を持つ手の位置（世界座標）
func _hand_world() -> Vector3:
	return cam.to_global(Vector3(0.2, -0.3, -0.4))


func _pose_hands(dt: float) -> void:
	var bob := sin(_t * 9.0)
	var working := pushing or pulling
	# 押す・引くと視点がわずかに揺れ、画角が少し広がる
	cam.position.y = lerp(cam.position.y, 1.55 + (bob * 0.02 if working else 0.0), min(1.0, dt * 10.0))
	cam.fov = lerp(cam.fov, base_fov + (4.0 if working else 0.0), min(1.0, dt * 4.0))
	for h in hands:
		var s: int = h.get_meta("side")
		var target: Vector3
		match mode:
			Mode.GRIP:
				# 縁を握る。押すと腕が少し伸びる
				var reach := -0.5 - (0.06 if pushing else 0.0)
				target = Vector3(0.17 * s, -0.22 + (bob * 0.015 if pushing else 0.0), reach)
			Mode.ROPE:
				# 右手で紐を握り、左手は振る
				if s > 0:
					target = Vector3(0.2, -0.3 - (0.05 if pulling else 0.0), -0.4)
				else:
					target = Vector3(-0.3, -0.3 + sin(_t * 6.0) * 0.01 * velocity.length(), -0.45)
			Mode.RIDE:
				target = Vector3(0.28 * s, -0.32, -0.35)
			_:
				target = Vector3(0.3 * s, -0.3 + sin(_t * 6.0 + s) * 0.01 * velocity.length(), -0.45)
		h.position = h.position.lerp(target, clamp(dt * 12.0, 0.0, 1.0))


## 紐を描く。持っていれば手まで、持っていなければソリの前に垂れる
func _draw_rope() -> void:
	var a: Vector3 = sled.to_global(sled.ROPE_ANCHOR)
	var b: Vector3
	if mode == Mode.ROPE:
		b = _hand_world()
	else:
		b = a + (-sled.global_basis.z) * 1.2
		b.y = a.y - 0.28
	var d := a.distance_to(b)
	var slack: float = max(0.0, sled.ROPE_LEN - d) if mode == Mode.ROPE else 0.4
	var sag: float = min(slack * 0.45, 1.2)
	var pts: Array[Vector3] = []
	for i in ROPE_SEGS + 1:
		var t := float(i) / ROPE_SEGS
		var p := a.lerp(b, t)
		p.y -= sag * sin(PI * t)
		pts.append(p)
	for i in ROPE_SEGS:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var seg := _rope[i]
		var mid := (p0 + p1) * 0.5
		var v := p1 - p0
		var len := v.length()
		if len < 0.001:
			seg.visible = false
			continue
		seg.visible = true
		var up := Vector3.UP if abs(v.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var basis := Basis.looking_at(v.normalized(), up)
		# CylinderMesh は y 軸が長さ。見ている向き（-z）を y に合わせる
		basis = basis * Basis(Vector3.RIGHT, -PI / 2)
		seg.global_transform = Transform3D(basis.scaled(Vector3(1, len, 1)), mid)
