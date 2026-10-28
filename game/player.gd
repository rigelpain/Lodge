extends CharacterBody3D

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")
const FpHands := preload("res://fp_hands.gd")
## あなた。一人称で、見えるのは自分の人形と同じ柄の袖口と、紙の手だけ。
## ソリのまわりのどこからでも F でつかめる。
## つかんだまま WASD で、見ている向きを基準にソリへ力をかける（W 前へ押す、S 手前へ引く、A/D 左右へ）。
## どう動くかはソリの滑り木と重力が決める。離すのは F だけ。Shift でダッシュ。
## 前に回って F を押すと紐を持ち、歩いて引ける。

const SPEED := 2.0           # 雪の中をじりじり歩く速さ
const DASH := 3.4            # Shift で走る速さ
const SPEED_TAUT := 1.5      # 紐が張っているときの歩く速さ
const JUMP := 4.5
const GRAVITY := 9.8
const STEP_UP := 0.40        # ジャンプしなくても乗り上げる段差の高さ (m)
const GRAB_REACH := 2.2      # F でつかめる、立つ位置までの距離 (m)
const LET_GO_SPEED := 5.0    # ソリがこれより速く滑ると手が離れる (m/s)
const ROPE_SEGS := 14

enum Mode { WALK, GRIP, RIDE, ROPE }

var sled: RigidBody3D
var cam: Camera3D
var hands: Array[Node3D] = []
var doll: Doll               # 自分の体（笠と千代紙の人形）。一人称には映さず、右上の映像と三人称と影に出る
var mode := Mode.WALK
var seat := Vector3.INF
var handle := Vector3.INF    # つかんでいる所（ソリの座標）
var push_dir := Vector3.ZERO # 押す向き（ソリの座標）
var pushing := false
var pulling := false
var prompt := ""             # 画面に出す一言（main.gd が読む）
var base_fov := 75.0         # ホイールで変える視野角
var third := false           # C で三人称
var bob_enabled := true      # 設定: 押す・引くときの視点の揺れ
var fov_kick_enabled := true # 設定: 押すときに画角が少し広がる
var mouse_sens := 1.0        # 設定: マウスの感度
var menu_open := false       # 設定画面が開いている間は、クリックでマウスをつかまない
var _pitch := 0.0
var _col: CollisionShape3D
var _t := 0.0
var _snap := 0.0             # 吸い付きの途中（0→1）
var _rope: Array[MeshInstance3D] = []
var _hand_frame := -1        # 一人称の手を最後に置き直したコマ
var point_at := Vector3.INF  # 右腕で指している所（世界）。仲間はここを見る
var _point_on: Node3D = null # 指した物（ソリや人）。動いても指し続ける
var _point_local := Vector3.ZERO


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
	cam.cull_mask = (1 << 0) | (1 << 2)   # 世界と手。自分の体（層 2）は映さない
	add_child(cam)
	cam.make_current()

	# 自分の体。一人称の画面には映さず、右上のライブ映像と影にだけ出る（層 2）
	doll = Doll.new()
	doll.kind = "kasa"
	doll.layers = 1 << 1
	add_child(doll)

	# 一人称の手: 自分の人形と同じ柄の袖口から、紙の手がのぞく（層 3。一人称の画面にだけ映す）
	for s in [-1, 1]:
		var h := FpHands.make(doll.kind, s, 1 << 2)
		cam.add_child(h)
		h.set_meta("side", s)
		hands.append(h)

	# 紐: 短い円柱をつないで描く（持っていないときはソリの前に垂れている）
	var rope_mat := Look.felt(Color(0.82, 0.72, 0.5), 8.0)
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


## 三人称では自分の体を映し、一人称の手は映さない
func set_third(on: bool) -> void:
	third = on
	cam.cull_mask = (1 << 0) | (1 << 1) if third else (1 << 0) | (1 << 2)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * 0.003 * mouse_sens)
		_pitch = clamp(_pitch - e.relative.y * 0.003 * mouse_sens, -1.4, 1.3)
	elif e is InputEventMagnifyGesture:
		# トラックパッドのピンチ: 広げると寄る（視野角が狭まる）
		base_fov = clamp(base_fov / e.factor, 50.0, 110.0)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			base_fov = clamp(base_fov - 3.0, 50.0, 110.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			base_fov = clamp(base_fov + 3.0, 50.0, 110.0)
		elif e.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			toggle_point()
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_C:
				set_third(not third)
				get_parent().settings.sync("third", third)
			KEY_F:
				match mode:
					Mode.GRIP, Mode.ROPE:
						let_go()
					Mode.WALK:
						if _rope_end_near():
							grab_rope()
						else:
							grab()
			KEY_G:
				doll.call_out()   # 言葉にならない声（仮のキー）
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
			sled.lean(_key(KEY_D) - _key(KEY_A), Input.is_physical_key_pressed(KEY_W), Input.is_physical_key_pressed(KEY_S))
			prompt = "W 前傾　S 後傾で止まる　A/D 体重をかけて曲がる　E 降りる"
		Mode.GRIP:
			_grip(dt)
		Mode.ROPE:
			_walk(dt, true)
		Mode.WALK:
			_walk(dt, false)
	_update_point()
	_pose_hands(dt)
	_pose_doll()
	_draw_rope()


## 人形に、いまの動きを伝える（姿勢は人形が 12 コマで刻む）。Q を押しているあいだ手を振る（仮のキー）
func _pose_doll() -> void:
	doll.act = [Doll.Act.WALK, Doll.Act.PUSH, Doll.Act.RIDE, Doll.Act.ROPE][mode]
	doll.sled = sled
	doll.grip = handle if mode == Mode.GRIP else Vector3.INF
	doll.effort = pushing or pulling
	doll.airborne = mode == Mode.WALK and not is_on_floor()
	doll.facing = (sled.global_basis * push_dir) if mode == Mode.GRIP else Vector3.ZERO
	doll.gaze = cam.global_position - cam.global_basis.z * 6.0
	doll.rope_hand = _hand_world() if mode == Mode.ROPE else Vector3.INF
	doll.lean = Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_W) - _key(KEY_S)) if mode == Mode.RIDE else Vector2.ZERO
	doll.waving = Input.is_physical_key_pressed(KEY_Q) and not menu_open
	doll.point = point_at


## 右クリックで指さしを入れたり切ったりする。入れると、いま向いている先（画面のまんなかが当たる所）を指し、
## その所を指し続ける。指したまま見回せば、顔の向きと違う所を指していられる。もう一度押すと腕を下ろす
func toggle_point() -> void:
	if point_at != Vector3.INF:
		point_at = Vector3.INF
		_point_on = null
		return
	var from := cam.global_position
	var to := from - cam.global_basis.z * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	point_at = hit.position if hit else to
	_point_on = null
	# 動く物（ソリや人）を指したら、その物に対しての所を覚えて、動いても指し続ける
	if hit and (hit.collider is RigidBody3D or hit.collider is CharacterBody3D):
		_point_on = hit.collider
		_point_local = _point_on.to_local(point_at)


## 指した物が動いたら、指す所もついていく。物が消えたら腕を下ろす
func _update_point() -> void:
	if _point_on == null:
		return
	if not is_instance_valid(_point_on):
		point_at = Vector3.INF
		_point_on = null
		return
	point_at = _point_on.to_global(_point_local)


## 小さな段差（STEP_UP まで）は、歩くだけで乗り上げる。
## 前がふさがっていて、持ち上げると前へ進め、その先に平らな床があるときだけ体を持ち上げる（壁やソリには上らない）。
## 前をふさいでいるのが歩ける斜面なら段差ではない（斜面を段差と見て持ち上げては落ちると、視点が震える）
func _step_up(dir: Vector3) -> void:
	if dir.length() < 0.1:
		return
	var ahead := dir * 0.3
	var block := KinematicCollision3D.new()
	if not test_move(global_transform, ahead, block):
		return
	if block.get_normal().y > 0.6:
		return
	var up := Vector3(0, STEP_UP, 0)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, ahead):
		return
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(ahead), -up, col):
		return
	if col.get_normal().y < 0.7 or col.get_collider() is RigidBody3D:
		return
	var rise := STEP_UP - col.get_travel().length()
	if rise > 0.02:
		global_position.y += rise + 0.01
		# 体は一気に上がっても、視点はすっと追いつく（カメラを同じ高さに残し、_place_camera が戻す）
		cam.position.y -= rise + 0.01


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
			_step_up(dir)
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


func _place_camera(dt: float, bob: float, working: bool) -> void:
	var eye_y := 1.55 + (bob * 0.02 if working else 0.0)
	if not third:
		cam.position = cam.position.lerp(Vector3(0, eye_y, 0), min(1.0, dt * 10.0))
		cam.rotation = Vector3(_pitch, 0, 0)
		return
	# 三人称: 頭の少し上を中心に、後ろ上から見下ろす。地面に潜らない
	var pivot := Vector3(0, 1.6, 0)
	var offset := Vector3(0, 0.6, 3.4).rotated(Vector3.RIGHT, clamp(_pitch, -0.6, 1.0))
	var want := pivot + offset
	var want_w := to_global(want)
	var floor_y: float = get_parent().height(want_w.x, want_w.z) + 0.4
	if want_w.y < floor_y:
		want.y += floor_y - want_w.y
	cam.position = cam.position.lerp(want, min(1.0, dt * 8.0))
	cam.look_at(to_global(pivot), Vector3.UP)


func _pose_hands(dt: float) -> void:
	var working := pushing or pulling
	var bob := sin(_t * 9.0) if bob_enabled else 0.0
	# 押す・引くと視点がわずかに揺れ、画角が少し広がる
	_place_camera(dt, bob, working)
	cam.fov = lerp(cam.fov, base_fov + (4.0 if working and fov_kick_enabled else 0.0), min(1.0, dt * 4.0))
	var fi := Doll.frame_index()
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
				target = Vector3(0.27 * s, -0.25 + sin(_t * 6.0 + s) * 0.01 * velocity.length(), -0.48)
		var pointing := s > 0 and point_at != Vector3.INF
		if pointing:
			# 指さし: 右の手袋を、指している所の向きへ伸ばす（見回すと、指した向きに残る。後ろなら画面の外）
			var d := cam.global_basis.inverse() * (point_at - cam.global_position).normalized()
			target = Vector3(0.1, -0.1, 0.0) + d * 0.58
		# 手も姿勢と同じ決まり: コマが変わるときだけ置き直す（一人称では揺らさない。目の前でふるえると見ていてつらい）。
		# ソリをつかんでいる間は、ソリに対しての位置で保つ（ソリが動いても手が縁から離れない）
		if fi != _hand_frame:
			var on_sled := mode == Mode.GRIP and not pointing
			h.set_meta("hold", sled.to_local(cam.to_global(target)) if on_sled else target)
			h.set_meta("on_sled", on_sled)
		var hold: Vector3 = h.get_meta("hold", target)
		h.position = cam.to_local(sled.to_global(hold)) if h.get_meta("on_sled", false) else hold
		# 腕は画面の下の肩から手へ伸びる。袖をその向きに
		var arm := h.position - Vector3(0.2 * s, -0.42, 0.12)
		h.basis = Basis.looking_at(arm, Vector3.UP)
	_hand_frame = fi


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
