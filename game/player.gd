extends CharacterBody3D

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")
const FpHands := preload("res://fp_hands.gd")
const Emotes := preload("res://emotes.gd")
const EmoteRing := preload("res://emote_ring.gd")
const Palm := preload("res://palm.gd")
## あなた。一人称で、見えるのは自分の人形と同じ柄の袖口と、紙の手だけ。
## ソリのまわりのどこからでも F でつかめる。
## つかんだまま WASD で、見ている向きを基準にソリへ力をかける（W 前へ押す、S 手前へ引く、A/D 左右へ）。
## どう動くかはソリの滑り木と重力が決める。離すのは F だけ。Shift でダッシュ。
## 前に回って F を押すと紐を持ち、歩いて引ける。
## 身ぶり: Tab を押しているあいだ輪が出て、マウスの向きで選び、離すと出す。輪と同じ 6 つを 1〜6 キーでも:
## 1 高い手のひら、2 低い手のひら、3 指さし、4 ウン、5 ンーン、6 首をかしげてウン？。手のひらは下ろすまで掲げたまま、
## 腕は見ている向きへ。手は Q で片手⇄両手、X で右⇄左。滑りながら高い両手のひらにすると、ひとりでに「ワ〜」。B を押しているあいだ、白い息を長く吐く（押した瞬間に短く吸う）。
## 左 Ctrl を押しているあいだしゃがむ。しゃがんで雪面を見て F で、雪玉を丸める。
## 左クリック: 雪玉を持っていれば押してためて（振りかぶり）、離して投げる（長く押すほど遠くへ）。両手のひらなら拍手。
## 持ち物（craft.gd）: ホイールで手に持つ物を替える（素手 → 持ち物 → …。持ち物がないときと Alt を押しているときは、ホイールは視野角）。
## 売り子のおじさんの前で F で売り台を開く。型紙か布を手に持ってミシンの前で T でセットする（両方そろうと縫い始める）。
## 縫ったソリのそばで G で畳んで持ち物に入れ、畳んだソリを手に持って左クリックで、前の床に広げて置く。
## 左クリックの順: 雪玉を持っていれば投げる → 畳んだソリを持っていれば広げる → 高い両手のひらなら拍手。

const SPEED := 2.0           # 雪の中をじりじり歩く速さ
const DASH := 3.4            # Shift で走る速さ
const SPEED_TAUT := 1.5      # 紐が張っているときの歩く速さ
const SPEED_CROUCH := 0.8    # しゃがんで歩く速さ
const CROUCH_EYE := 0.5      # しゃがむと目がこれだけ下がる (m)
const JUMP := 4.5
const GRAVITY := 9.8
const STEP_UP := 0.40        # ジャンプしなくても乗り上げる段差の高さ (m)
const GRAB_REACH := 2.2      # F でつかめる、立つ位置までの距離 (m)
const LET_GO_SPEED := 5.0    # 紐を持っていて、ソリがこれより速く滑ると手が離れる (m/s)。縁をつかんでいるときはソリが決める（sled.gd の引きずり）

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
var _hand_frame := -1        # 一人称の手を最後に置き直したコマ
var point_at := Vector3.INF  # 指している所（世界）。仲間はここを見る
var _point_on: Node3D = null # 指した物（ソリや人）。動いても指し続ける
var _point_local := Vector3.ZERO
var hub: Emotes              # 身ぶりの配り役（main.gd が置く。いなければ身ぶりは出せない）
var id := -1                 # 配り役からもらった番号
var voice_pitch := 1.0       # 声の高さ（人ごとに少し変える）
var voice_size := 1          # 声の大きさ（sound/wav/voice_*_01 ふつう・02 高い・03 低い）
var holding_ball := false
var ring: EmoteRing
var _em := {}                # いまの自分の身ぶり（出来事）
var _winding := false
var _wind_t := 0.0
var _ball_fp: MeshInstance3D # 一人称の右手の雪玉
var _shapes_fp := {}         # 一人称の手の形のアップリケ: 形 → {1: 右手, -1: 左手}
var hands_name := ""         # いま掲げている手（Palm.HANDS の名前。"high_R" など。"" は下ろしている）
var hand := "R"              # 身ぶりに使う手（"R" "L" "both"）。Q で片手⇄両手、X で右⇄左
var _one_hand := "R"         # 片手のときの手（両手にしても覚えておく）
var _auto_wa := false        # 滑りながら高い両手のひらで、もう「ワ〜」と言った
var crouching := false       # 左 Ctrl を押しているあいだしゃがむ
var _exhaling := false      # B を押しているあいだ、息を吐いている
var _exhale_t := 0.0
var _cam_roll := 0.0         # 首をかしげると視点も少し傾く
var _cam_em := Vector3.ZERO  # 身ぶりで視点に足す（x 上下の向き、y 左右の向き、z 高さ）。なめらかに追う
var _drag_k := 0.0           # 引きずられている度合い（0→1 になめらかに）。視点が前へ傾き、低く揺れる
var craft: Node              # 工房の配り役（main.gd の Craft）。財布と持ち物
var shopping := false        # 売り台が開いている（craft_ui.gd）。歩かない
var _held_fp: Node3D         # 一人称の右手に持った物の形
var _held_key := ""
var _unfold_up := Vector3.UP # 広げる所の床の傾き（unfold_spot が決める）
const FOLD_REACH := 2.6      # G で畳めるソリまでの距離（ソリの縁から, m）
const SLED_SWITCH := 0.8     # 近いソリへ持ち替える差 (m)。行ったり来たりしないよう


func _ready() -> void:
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	_col.shape = cap
	_col.position.y = 0.85
	add_child(_col)
	floor_snap_length = 0.4   # 斜面でも床に吸い付く
	floor_max_angle = deg_to_rad(50)

	cam = Camera3D.new()
	cam.position.y = 1.55
	cam.fov = 75
	cam.near = 0.05
	cam.cull_mask = (1 << 0) | (1 << 2) | (1 << 3) | (1 << 4)   # 世界と手と飾りと風。自分の体（層 2）は映さない
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
		if s > 0:
			_ball_fp = MeshInstance3D.new()
			_ball_fp.mesh = Doll.ball_mesh()
			_ball_fp.material_override = Doll.ball_material()
			_ball_fp.layers = 1 << 2
			_ball_fp.position = Vector3(0, 0.03, -0.1)
			_ball_fp.visible = false
			h.add_child(_ball_fp)

	_shapes_fp = Palm.make_set(Color(FpHands.STYLE.get(doll.kind, FpHands.STYLE["kasa"]).hand), 1 << 2)
	for sh in _shapes_fp:
		for n in _shapes_fp[sh].values():
			cam.add_child(n)

	hub = get_parent().get_node_or_null("Emotes")
	if hub:
		id = hub.join(self)
		hub.happened.connect(_on_emote)
	craft = get_parent().get_node_or_null("Craft")
	if craft and id >= 0:
		craft.join(id)
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		ring = EmoteRing.new()
		layer.add_child(ring)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 三人称では自分の体を映し、一人称の手は映さない。滑るときの風（層 5）はどちらでも映す
func set_third(on: bool) -> void:
	third = on
	cam.cull_mask = ((1 << 0) | (1 << 1) | (1 << 3) if third else (1 << 0) | (1 << 2) | (1 << 3)) | (1 << 4)


func _unhandled_input(e: InputEvent) -> void:
	if ring and ring.visible and e is InputEventMouseMotion:
		ring.move(e.relative)   # 輪を出しているあいだは見回さない
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * 0.003 * mouse_sens)
		_pitch = clamp(_pitch - e.relative.y * 0.003 * mouse_sens, -1.4, 1.3)
	elif e is InputEventMagnifyGesture:
		# トラックパッドのピンチ: 広げると寄る（視野角が狭まる）
		base_fov = clamp(base_fov / e.factor, 50.0, 110.0)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := -1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if menu_open:
				pass
			elif craft and not craft.bag(id).is_empty() and not e.alt_pressed:
				cycle_hand(step)   # 持ち物があれば、ホイールは手に持つ物
			else:
				base_fov = clamp(base_fov + 3.0 * step, 50.0, 110.0)
		elif e.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			toggle_point()
		elif e.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_left_click()
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _winding:
		throw_ball()
	elif e is InputEventKey and not e.pressed and e.physical_keycode == KEY_B:
		_stop_exhale()
	elif e is InputEventKey and not e.pressed and e.physical_keycode == KEY_TAB and ring and ring.visible:
		var k := ring.close()
		if k != EmoteRing.NONE:
			_choose(k)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_C:
				set_third(not third)
				get_parent().settings.sync("third", third)
			KEY_F:
				if rooted():
					return
				if crouching and mode == Mode.WALK and _snow_ahead():
					emote("make_ball")   # しゃがんで雪面に手を伸ばす: 雪玉を丸める
					return
				if mode == Mode.WALK and shop_near():
					get_parent().craft_ui.open_shop()   # 売り子のおじさんに話しかける
					return
				match mode:
					Mode.GRIP, Mode.ROPE:
						let_go()
					Mode.WALK:
						if _rope_end_near():
							grab_rope()
						else:
							grab()
			KEY_TAB:
				if ring and not menu_open:
					ring.open(hand, _height(), point_at != Vector3.INF)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				# 輪と同じ 6 つ: 1 高い手のひら、2 低い手のひら、3 指さし、4 ウン、5 ンーン、6 首をかしげてウン？
				_choose(["high", "low", "point", "un", "nn", "huh"][e.physical_keycode - KEY_1])
			KEY_Q:
				# 片手 ⇄ 両手
				_set_hand("both" if hand != "both" else _one_hand)
			KEY_X:
				# 片手の右 ⇄ 左
				_one_hand = "L" if _one_hand == "R" else "R"
				_set_hand(_one_hand)
			KEY_B:
				if not _exhaling and available().get("breath", false):
					_exhaling = true
					_exhale_t = 0.0
					emote("breath")
			KEY_G:
				if mode == Mode.WALK and not rooted():
					fold_near()
			KEY_E:
				if mode == Mode.RIDE:
					get_off()
				else:
					get_on()


## 雪の上の紐の先に近いか
func _rope_end_near() -> bool:
	var d: Vector3 = sled.rope.end_point() - global_position
	d.y = 0
	return d.length() < 1.6


func grab() -> void:
	set_hands("")   # ソリをつかむ手は、形を下ろす
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
	set_hands("")
	if not sled.take_rope(self):
		return
	mode = Mode.ROPE


func let_go() -> void:
	match mode:
		Mode.GRIP:
			sled.release_handle(self)
			handle = Vector3.INF
			_col.disabled = false
			# 手が離れた: ソリに当たらないよう、つかんでいた縁から少し外へ
			var out: Vector3 = -(sled.global_basis * push_dir)
			out.y = 0
			if out.length() > 0.1:
				global_position += out.normalized() * 0.4
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

	if mode == Mode.WALK:
		_pick_sled()
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
	_update_emote(dt)
	_pose_hands(dt)
	_pose_doll()


## 人形に、いまの動きを伝える（姿勢は人形が 12 コマで刻む）。Q を押しているあいだ手を振る（仮のキー）
func _pose_doll() -> void:
	doll.act = [Doll.Act.WALK, Doll.Act.PUSH, Doll.Act.RIDE, Doll.Act.ROPE][mode]
	doll.sled = sled
	doll.grip = handle if mode == Mode.GRIP else Vector3.INF
	doll.effort = pushing or pulling
	doll.dragged = mode == Mode.GRIP and sled.is_dragged(self)
	doll.airborne = mode == Mode.WALK and not is_on_floor()
	doll.facing = (sled.global_basis * push_dir) if mode == Mode.GRIP else Vector3.ZERO
	doll.gaze = cam.global_position - cam.global_basis.z * 6.0
	doll.rope_hand = _hand_world() if mode == Mode.ROPE else Vector3.INF
	doll.lean = Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_W) - _key(KEY_S)) if mode == Mode.RIDE else Vector2.ZERO
	doll.point_sides = Palm.sides_of(hand)
	doll.holding_ball = holding_ball
	doll.crouch = crouching
	doll.point = point_at


## 右クリックで指さしを入れたり切ったりする。入れると、いま向いている先（画面のまんなかが当たる所）を指し、
## その所を指し続ける。指したまま見回せば、顔の向きと違う所を指していられる。もう一度押すと腕を下ろす
func toggle_point() -> void:
	if point_at != Vector3.INF:
		point_at = Vector3.INF
		_point_on = null
		return
	set_height("")   # 指さす手は、手のひらを下ろす
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
	if rooted() or shopping:
		input = Vector2.ZERO   # 雪玉を丸める・ハイタッチ・買い物のあいだは、その場で
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := DASH if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED
	if crouching:
		speed = SPEED_CROUCH
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
			velocity.y = 0.0   # 床の上で縦の速さを残すと、床に食い込んでは押し戻されて細かく揺れる
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
	var dragged: bool = sled.is_dragged(self)
	if input.length() > 0.0 and not dragged:
		var dir := (global_basis * Vector3(input.x, 0, input.y))
		dir.y = 0
		sled.push(dir.normalized(), target + Vector3.UP * 0.5, self)
		pushing = true

	if dragged:
		prompt = "引きずられている　踏ん張って止める　F 手を離す"
		return
	prompt = "力をかけている　F 手を離す　E 乗る" if pushing else "WASD 見ている向きを基準に力をかける　F 手を離す　E 乗る"


## 紐を持つ手の位置（世界座標）。一人称では画面の右手、三人称では体の右前
func _hand_world() -> Vector3:
	if third:
		return to_global(Vector3(0.25, 1.0, -0.45))
	return cam.to_global(Vector3(0.2, -0.3, -0.4))


## 紐の先を付ける所（sled_rope.gd が読む）
func rope_hand() -> Vector3:
	return _hand_world()


func _place_camera(dt: float, bob: float, working: bool) -> void:
	var eye_y := 1.55 + (bob * 0.02 if working else 0.0)
	_drag_k = move_toward(_drag_k, 1.0 if mode == Mode.GRIP and sled.is_dragged(self) else 0.0, dt * 4.0)
	var jolt := 0.0   # 引きずられているときの雪のでこぼこ（コマごとに変わる小さな揺れ。視点の揺れを切ると弱く）
	if _drag_k > 0.0:
		jolt = (0.012 if Doll.frame_index() % 2 == 0 else -0.012) * _drag_k * (1.0 if bob_enabled else 0.3)
	if not third:
		var eye := Vector3(0, eye_y - 0.22 * _drag_k + jolt, -0.25 * _drag_k)
		if mode == Mode.RIDE:
			# 乗っているときは、座った人形の目の所（席や人形が変わっても合う）。ソリが傾けば一緒に傾く。
			# 乗り降りは同じ lerp で、すっと立ち上がる・腰を下ろす
			eye = to_local(Transform3D(sled.global_basis.orthonormalized(), global_position) * doll.eye_point(true))
		eye.y += _cam_em.z
		cam.position = cam.position.lerp(eye, min(1.0, dt * 10.0))
		cam.rotation = Vector3(clampf(_pitch + _cam_em.x - 0.12 * _drag_k, -1.5, 1.4), _cam_em.y, _cam_roll + jolt * 2.0)
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
				# 縁を握る。押すと腕が少し伸びる。引きずられていると、腕がソリへ引っぱられて伸びきる
				var reach := -0.5 - (0.06 if pushing else 0.0) - 0.12 * _drag_k
				target = Vector3(0.17 * s, -0.22 + (bob * 0.015 if pushing else 0.0) - 0.05 * _drag_k, reach)
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
		var em_hand := _emote_hand(s)
		if em_hand != Vector3.INF:
			target = em_hand
		var pointing := (s in Palm.sides_of(hand)) and point_at != Vector3.INF and em_hand == Vector3.INF
		if pointing:
			# 指さし: 選んだ手の手袋を、指している所の向きへ伸ばす（見回すと、指した向きに残る。後ろなら画面の外）
			var d := cam.global_basis.inverse() * (point_at - cam.global_position).normalized()
			target = Vector3(0.1 * s, -0.1, 0.0) + d * 0.58
		# 手も姿勢と同じ決まり: コマが変わるときだけ置き直す（一人称では揺らさない。目の前でふるえると見ていてつらい）。
		# ソリをつかんでいる間は、ソリに対しての位置で保つ（ソリが動いても手が縁から離れない）
		if fi != _hand_frame:
			var on_sled := mode == Mode.GRIP and not pointing and em_hand == Vector3.INF
			h.set_meta("hold", sled.to_local(cam.to_global(target)) if on_sled else target)
			h.set_meta("on_sled", on_sled)
		var hold: Vector3 = h.get_meta("hold", target)
		h.position = cam.to_local(sled.to_global(hold)) if h.get_meta("on_sled", false) else hold
		# 腕は画面の下の肩から手へ伸びる。袖をその向きに
		var arm := h.position - Vector3(0.2 * s, -0.42, 0.12)
		h.basis = Basis.looking_at(arm, Vector3.UP)
	_hand_frame = fi
	# 一人称の雪玉: 作っている途中は大きくなり、できたら右手に
	var em := doll.emote_now()
	var grow := 0.0
	if em[0] == "make_ball" and em[1] >= 4:
		grow = clampf((em[1] - 4) / 12.0, 0.0, 1.0) * 0.6 + 0.4
	elif holding_ball:
		grow = 1.0
	_ball_fp.visible = grow > 0.0
	_ball_fp.scale = Vector3.ONE * maxf(grow, 0.01)
	_place_held_fp(grow > 0.0)
	_place_shapes_fp(em)


## 一人称の手形: 手の先に置く。手のひらは前（相手）へ向け（自分からは手の甲が見える）、低い手のひらは下へ向ける。
## 指さしの手には指さしの手形。ハイタッチ・握手は合う手に。形は人形と同じコマで
func _place_shapes_fp(em: Array) -> void:
	var kind: String = em[0]
	var k: int = em[1]
	var want := {1: "", -1: ""}
	var mode := {1: "", -1: ""}
	for sd in [1, -1]:
		var height: String = doll.hand_shapes[0 if sd > 0 else 1]
		if height != "":
			want[sd] = "palm"
			mode[sd] = height
	if point_at != Vector3.INF:
		for sd in Palm.sides_of(hand):
			want[sd] = "point"
			mode[sd] = "point"
	var touching := k >= 0 and kind in ["high_five", "shake", "whiff"]
	if touching:
		want = {1: "", -1: ""}
		if kind == "whiff":
			if k < 3:
				want[int(_em.get("side", 1))] = "palm"
				mode[int(_em.get("side", 1))] = kind
		elif (kind == "high_five" and k < 8) or (kind == "shake" and k < 20):
			for gr in _em.get("grips", []):
				want[int(gr[0])] = "palm"
				mode[int(gr[0])] = kind
	elif (k >= 0 and kind in Doll.ARM_EMOTES) or _winding:
		want = {1: "", -1: ""}
	for sh in _shapes_fp:
		for side in [1, -1]:
			var node: Node3D = _shapes_fp[sh][side]
			var on: bool = want[side] == sh
			node.visible = on
			if not on:
				continue
			var size := Palm.pop(Doll.frame_index() - doll._hands_frame)
			var b := Basis(Vector3.UP, PI)
			var h: Node3D = hands[0] if hands[0].get_meta("side") == side else hands[1]
			match mode[side]:
				"point":
					# 人さし指を、手の伸びる向きへ（腕の先）
					var y: Vector3 = (h.basis * Vector3.FORWARD).normalized()
					var z := Vector3.UP.cross(y) * float(side)
					z = z.normalized() if z.length() > 0.05 else Vector3.BACK
					b = Palm.thumb_up(Basis(y.cross(z).normalized(), y, z), side)   # 親指は上
					size = 1.0
				"low":
					b = b * Basis(Vector3.RIGHT, -0.65)   # 下へ向けて、おさえる
				"shake":
					# 握手: 人形と同じに、重ねる所（配り役が決めた、二人で平行な少し傾いた面）へ。合わせたら二人一緒に上下に振る
					var wb := Palm.shake_basis(_em.get("fwd", -global_basis.z), _em.get("axis", global_basis.x), side)
					var at: Vector3 = h.global_position
					for gr in _em.get("grips", []):
						if int(gr[0]) == side:
							at = (gr[1] as Vector3) + Vector3.UP * Palm.shake_pump(k) if k >= 2 else (gr[1] as Vector3).lerp(h.global_position, 0.5)
					node.global_transform = Transform3D(wb.scaled(Vector3.ONE * Palm.BIG), at)
					continue
				"high_five", "whiff":
					b = b * Basis(Vector3.RIGHT, 0.5 if k < 3 else 0.0)
					size = 1.25 if k == 3 and kind == "high_five" else 1.0
			# 手形の手首の真ん中を、袖の先（手の所）に合わせる
			var bs := b.scaled(Vector3.ONE * size)
			node.transform = Transform3D(bs, h.position - bs * Palm.WRIST)


# ---------------------------------------------------------------- 身ぶり（emotes.gd）

## いまできる身ぶり。声はいつでも。吐く息・拍手はその場でする身ぶりの途中でなければ。雪玉づくりはしゃがんでいるときだけ
func available() -> Dictionary:
	var busy := rooted() or _winding
	return {
		"wa": true, "un": true, "nn": true, "huh": true,
		"breath": not busy,
		"clap": not busy and hands_name == "high_both",
		"make_ball": not busy and mode == Mode.WALK and not holding_ball and crouching,
	}


## 輪か数字キーで選んだもの: 高い・低い手のひら（同じものをもう一度選ぶと下ろす）、指さし、声
func _choose(k: String) -> void:
	match k:
		"high", "low":
			set_height("" if _height() == k else k)
		"point":
			toggle_point()
		_:
			emote(k)


## いま掲げている高さ（"high" "low" ""）
func _height() -> String:
	return hands_name.split("_")[0] if hands_name != "" else ""


## 手のひらを掲げる・下ろす（配り役へ送る）。いまの手（右・左・両手）で。指さしていれば、指さしをやめる
func set_height(height: String) -> void:
	if height != "" and point_at != Vector3.INF:
		point_at = Vector3.INF
		_point_on = null
	set_hands(Palm.hands_name(height, hand))


## 身ぶりに使う手を替える。掲げているなら、その手で掲げ直す
func _set_hand(h: String) -> void:
	hand = h
	if ring:
		ring.set_hand(h)
	if _height() != "":
		set_hands(Palm.hands_name(_height(), hand))


## 手を変える（配り役へ送る。"" は下ろす）
func set_hands(name_: String) -> void:
	if hub == null or name_ == hands_name:
		return
	hub.send({"kind": "hands", "who": id, "hands": name_})


## 左クリック: 雪玉を持っていれば振りかぶる（離すと投げる）。高い両手のひらなら拍手
func _left_click() -> void:
	if holding_ball:
		wind_up()
	elif held().get("kind") == "folded" and mode == Mode.WALK:
		unfold_ahead()
	elif hands_name == "high_both":
		emote("clap")


## 身ぶりを出す（配り役へ送る。自分の人形も、配られた出来事で動く）
func emote(kind: String) -> void:
	if hub == null or menu_open or not available().get(kind, false):
		return
	hub.send({"kind": kind, "who": id})


## その場でする身ぶりの途中か（歩けない、つかめない）
func rooted() -> bool:
	if _em.is_empty():
		return false
	var spec: Dictionary = Emotes.KINDS.get(_em.kind, {})
	return spec.get("root", false) and _em_k() < spec.frames


func _em_k() -> int:
	return Doll.frame_index() - int(_em.frame) if not _em.is_empty() else -1


func _on_emote(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	if ev.kind == "hands":
		hands_name = ev.hands
		doll.play(ev)
		return
	_em = ev
	doll.play(ev)
	match ev.kind:
		"throw":
			holding_ball = false
		"hit":
			_winding = false   # びっくりして振りかぶりが解ける（雪玉は持ったまま）
			# びっくりしてソリの縁や紐から手を離す（乗っている人は降ろさない）。止めるにはもう一度 F
			if mode == Mode.GRIP or mode == Mode.ROPE:
				let_go()


## 左クリックを押した: 振りかぶる
func wind_up() -> void:
	if not holding_ball or _winding or rooted() or hub == null:
		return
	_winding = true
	_wind_t = 0.0
	hub.send({"kind": "windup", "who": id})


## 左クリックを離した: 見ている向きへ投げる。長く振りかぶるほど速い。乗っていればソリの速さも乗る
func throw_ball() -> void:
	if not _winding:
		return
	_winding = false
	var power := clampf(_wind_t / 0.8, 0.0, 1.0)
	var speed := lerpf(7.0, 16.0, power)
	# 向きは体の向きと見上げる角度から（三人称のカメラは後ろ上から見下ろすので、カメラの向きでは足もとへ飛ぶ）
	var aim := global_basis * (Basis(Vector3.RIGHT, _pitch) * Vector3.FORWARD)
	var dir := (aim + Vector3.UP * 0.14).normalized()
	var origin: Vector3
	if third:
		origin = global_position + Vector3.UP * doll.height() * 0.85 + doll.global_basis * Vector3(0.18, 0, -0.45)
	else:
		origin = cam.to_global(Vector3(0.14, -0.06, -0.45))
	var carry: Vector3 = sled.linear_velocity if mode == Mode.RIDE else velocity
	hub.send({"kind": "throw", "who": id, "origin": origin, "velocity": dir * speed + carry})


func _update_emote(dt: float) -> void:
	if _winding:
		_wind_t += dt
	crouching = mode == Mode.WALK and Input.is_physical_key_pressed(KEY_CTRL) and not menu_open
	# 滑りながら高い両手のひらにすると、ひとりでに「ワ〜」
	var sliding := mode == Mode.RIDE and sled.linear_velocity.length() > 2.5
	if hands_name == "high_both" and sliding and not _auto_wa:
		_auto_wa = true
		if hub:
			hub.send({"kind": "wa", "who": id, "auto": true})
	elif hands_name != "high_both" or (mode == Mode.RIDE and sled.linear_velocity.length() < 1.0):
		_auto_wa = false
	if _exhaling:
		_exhale_t += dt
		if _exhale_t > Emotes.EXHALE_MAX:
			_stop_exhale()   # 息が続くのは 5 秒まで
	var want := Vector3.ZERO
	var k := _em_k()
	if not _em.is_empty():
		if _em.kind == "make_ball" and k >= Emotes.MAKE_READY and not _em.get("got", false):
			_em["got"] = true
			holding_ball = true
		want = _emote_cam(_em.kind, k)
	if not bob_enabled and not (not _em.is_empty() and _em.kind == "make_ball"):
		want *= 0.3   # 視点の揺れを切っていれば控えめに（しゃがむ高さだけはそのまま）
	if crouching:
		want.z = minf(want.z, -CROUCH_EYE)   # しゃがむと目が下がる
	_cam_em = _cam_em.lerp(want, minf(1.0, dt * 12.0))
	var roll := 0.0
	if not _em.is_empty() and _em.kind == "huh" and k >= 2 and k < 14:
		roll = -0.12 * (1.0 if k < 10 else (14 - k) / 4.0) * (1.0 if bob_enabled else 0.4)
	_cam_roll = lerpf(_cam_roll, roll, minf(1.0, dt * 10.0))


## 身ぶりの一人称の視点（x 上下の向き、y 左右の向き、z 高さ）。人形の頭と同じ形を、小さく
func _emote_cam(kind: String, k: int) -> Vector3:
	var n: int = Emotes.KINDS.get(kind, {}).get("frames", 0)
	if k < 0 or (n > 0 and k >= n):
		return Vector3.ZERO
	match kind:
		"un":
			return Vector3([-0.06, -0.15, -0.15, -0.06, 0.0, 0.0, 0.0][k], 0, 0)
		"nn":
			return Vector3(-0.02, [0.07, 0.07, -0.07, -0.07, 0.07, 0.07, -0.06, -0.06, 0.04, 0.04, -0.02, -0.02, 0.0, 0.0][k], 0)
		"make_ball":
			var s := 1.0 if k < 16 or crouching else 1.0 - Doll._ease((k - 16) / 5.0)
			return Vector3(-0.5 * s, 0, -CROUCH_EYE * s)
		"breath":
			var b := Doll.exhale_curve(k, _em.has("until"), int(_em.get("until", 0)) - int(_em.frame))
			return Vector3(0.14 * b, 0, 0.02 * b)
		"hit":
			var f: float = [0.55, 0.6, 0.5, 0.45, 0.4, 0.35, 0.3, 0.2, 0.12, 0.08, 0.05, 0.03, 0.0, 0.0, 0.0, 0.0][k]
			var shake := (0.05 if k % 2 == 0 else -0.05) if k >= 8 and k < 14 else 0.0
			return Vector3(0.28 * f, shake, 0)
		"whiff":
			return Vector3(-0.12 if k >= 2 and k < 8 else 0.0, 0.08 if k >= 2 and k < 5 else 0.0, 0)
		"wa":
			return Vector3(-0.04 if k < 2 else 0.08, 0, 0)
	return Vector3.ZERO


## 身ぶりの一人称の手（カメラの座標）。身ぶりでなければ INF
func _emote_hand(s: int) -> Vector3:
	if _winding:
		return Vector3(0.33, 0.0, -0.36) if s > 0 else Vector3(-0.1, -0.1, -0.62)   # 右手（雪玉）を画面の右端へ引き、左手で狙う
	var em := doll.emote_now()
	var kind: String = em[0]
	var k: int = em[1]
	# 掲げた手のひら: 高い手は画面の上のほう、低い手は下のほう（腕を使う身ぶりのあいだは出さない）
	var height: String = doll.hand_shapes[0 if s > 0 else 1]
	if height != "" and not (k >= 0 and kind in Doll.ARM_EMOTES):
		return Vector3(0.2 * s, 0.04, -0.5) if height == "high" else Vector3(0.2 * s, -0.3, -0.5)
	if k < 0:
		return Vector3.INF
	var mine := []   # この身ぶりで使う手
	for gr in _em.get("grips", []):
		mine.append(int(gr[0]))
	match kind:
		"high_five":
			if s in mine:
				if k < 3:
					return Vector3(0.36 * s, 0.16, -0.26)   # ため: 画面の外側へ引く
				if k < 6:
					return Vector3(0.05 * s, 0.06, -0.58)   # 叩きつける: まんなかで手が合う
				return Vector3(0.15 * s, -0.3, -0.5)
		"shake":
			if s in mine:
				if k < 2:
					return Vector3(0.14 * s, -0.27, -0.45)   # 差し出す
				if k < 20:
					# 握って、上下に振る: 袖の先を、重ねる所に置いた手形の手首へ
					for gr in _em.grips:
						if int(gr[0]) == s:
							var wb := Palm.shake_basis(_em.get("fwd", -global_basis.z), _em.get("axis", global_basis.x), s).scaled(Vector3.ONE * Palm.BIG)
							return cam.to_local((gr[1] as Vector3) + Vector3.UP * Palm.shake_pump(k) + wb * Palm.WRIST)
				return Vector3(0.25 * s, -0.3, -0.45)
		"whiff":
			var ws := int(_em.get("side", 1))
			if s == ws:
				if k < 2:
					return Vector3(0.32 * s, 0.14, -0.3)
				if k < 4:
					return Vector3(-0.08 * s, -0.12, -0.6)   # 振り抜く
				return Vector3(-0.05 * s, -0.38, -0.45)
		"breath":
			var b := Doll.exhale_curve(k, _em.has("until"), int(_em.get("until", 0)) - int(_em.frame))
			return Vector3(s * (0.27 + 0.16 * b), -0.25 + 0.1 * b, -0.48)
		"make_ball":
			if k >= 4 and k < 16:
				var up := 0.035 if ((k / 2) % 2 == 0) == (s > 0) else 0.0
				return Vector3(s * 0.08, -0.2 + up, -0.4)
			if k >= 16 and s > 0:
				return Vector3(0.12, -0.2, -0.42)
		"throw":
			if s > 0:
				if k == 0:
					return Vector3(0.12, 0.0, -0.66)
				if k < 3:
					return Vector3(-0.04, -0.34, -0.56)
		"hit":
			if k < 8:
				return Vector3(s * 0.26, 0.0, -0.4)
			if k < 14:
				return Vector3(s * 0.15, -0.18 + (0.04 if (k % 2 == 0) == (s > 0) else 0.0), -0.36)
		"clap":
			var gap: float = [0.32, 0.14, 0.03, 0.2][k % 4]
			return Vector3(s * gap * 0.5, -0.17, -0.42)
		"wa":
			if k < 2:
				return Vector3(s * 0.2, -0.38, -0.4)
			if k < 11:
				return Vector3(s * 0.34, 0.0, -0.45)
		"huh":
			if k >= 2 and k < 12:
				return Vector3(s * 0.3, -0.3, -0.42)   # さあ？と両手を少し外へ
		"nn":
			if s > 0 and k < 12:
				return Vector3(0.04 + (0.06 if (k / 2) % 2 == 0 else -0.06), -0.08, -0.32)   # 顔の前で手を振る
	return Vector3.INF


## B を離した（または息が切れた）: 吐くのをやめる
func _stop_exhale() -> void:
	if not _exhaling:
		return
	_exhaling = false
	if hub:
		hub.send({"kind": "breath_end", "who": id})


## 見ている先の近くに雪面があるか（しゃがんで手が届く所。地面の当たりは高さの地図）
func _snow_ahead() -> bool:
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 2.2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.5:
		return false
	for c in (hit.collider as Node).get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is HeightMapShape3D:
			return true
	return false


# ---------------------------------------------------------------- 持ち物と工房（craft.gd）

## 手に持っている物（素手なら {}）
func held() -> Dictionary:
	return craft.held(id) if craft else {}


## ホイール: 素手 → 持ち物 1 → 2 → … と回す
func cycle_hand(step: int) -> void:
	var n: int = craft.bag(id).size()
	var cur: int = craft.hands.get(id, -1)
	var next := posmod(cur + 1 + step, n + 1) - 1
	craft.send({"kind": "hand", "who": id, "slot": next})


## いちばん近いソリを、押す・乗る・畳む相手にする（歩いているときだけ。つかむ・乗るあいだは替えない）
func _pick_sled() -> void:
	var best: RigidBody3D = sled if is_instance_valid(sled) and sled.visible and not sled.is_queued_for_deletion() else null
	var best_d := INF
	if best:
		best_d = global_position.distance_to(best.global_position) - SLED_SWITCH
	for s in get_tree().get_nodes_in_group("sleds"):
		var rb := s as RigidBody3D
		if rb == null or rb == best or not rb.visible or rb.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(rb.global_position)
		if d < best_d:
			best = rb
			best_d = d
	if best and best != sled:
		sled = best


## 売り子のおじさんに話しかけられる所で、おじさんの方を向いているか
func shop_near() -> bool:
	var sk = get_parent().get("shopkeeper")
	if sk == null or get_parent().get("craft_ui") == null or not sk.can_talk(self):
		return false
	var d: Vector3 = sk.global_position - global_position
	d.y = 0
	return d.length() < 0.6 or (-global_basis.z).dot(d.normalized()) > 0.4


## 畳めるソリ（縫った・広げたソリ）が手の届く所にあれば、それ
func foldable_near() -> RigidBody3D:
	if craft == null:
		return null
	var best: RigidBody3D = null
	var best_d := FOLD_REACH
	for s in get_tree().get_nodes_in_group("sleds"):
		var rb := s as RigidBody3D
		if rb == null or not rb.get("crafted") or not rb.visible or rb.is_queued_for_deletion() or craft.id_of(rb) < 0:
			continue
		var lp := rb.to_local(global_position)
		var edge := Vector2(maxf(absf(lp.x) - rb.HALF.x, 0.0), maxf(absf(lp.z) - rb.HALF.y, 0.0)).length()
		if edge < best_d and rb.riders.is_empty() and rb.holders.is_empty() and rb.rope_holder == null:
			best = rb
			best_d = edge
	return best


## G: そばの縫ったソリを畳んで持ち物に入れる
func fold_near() -> bool:
	var s := foldable_near()
	if s == null:
		return false
	return craft.send({"kind": "fold", "who": id, "id": craft.id_of(s)})


## 畳んだソリを広げて置く所: 前の床の、ソリの長さの半分 + 0.7 m 先。壁や物とぶつかるなら INF
func unfold_spot() -> Vector3:
	var it := held()
	if it.get("kind") != "folded":
		return Vector3.INF
	var k: Dictionary = preload("res://sled.gd").KINDS.get(it.sled, {})
	if k.is_empty():
		return Vector3.INF
	var box: Vector3 = k.box
	var fwd := -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var center := global_position + fwd * (box.z * 0.5 + 0.7)
	var space := get_world_3d().direct_space_state
	# 床: 前後の 2 点の高さから傾きを出し、真ん中の床に置く（坂ではソリを坂に沿わせる）
	var hits := []
	for o in [0.0, 0.45, -0.45]:
		var p: Vector3 = center + fwd * o * box.z
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 4.0)   # 坂の上の端は足もとより高い
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return Vector3.INF
		hits.append(hit)
	var up: Vector3 = hits[0].normal
	var along: Vector3 = (hits[1].position - hits[2].position).normalized()
	var side := along.cross(up).normalized()
	up = side.cross(along).normalized() if side.length() > 0.5 else up
	if up.y < 0.75:
		return Vector3.INF   # 急すぎる
	_unfold_up = up
	var at: Vector3 = hits[0].position
	# ぶつかる物がないか（床の少し上に、ソリの大きさの箱）
	var hy := maxf(box.y, 0.3)
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.x, hy, box.z) * 0.95
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.transform = Transform3D(preload("res://craft.gd")._basis(rotation.y, up), at + up * (hy * 0.5 + 0.15))
	sq.exclude = [get_rid()]
	for r in space.intersect_shape(sq, 8):
		if not _is_ground(r.collider):   # 坂の地面に少しかかるのはよい（ソリは地面に置く）
			return Vector3.INF
	return at


## 外の地面（高さの地図）か
static func _is_ground(n: Object) -> bool:
	if n is Node:
		for c in (n as Node).get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is HeightMapShape3D:
				return true
	return false


## 左クリック: 手に持った畳んだソリを、前の床に広げて置く
func unfold_ahead() -> bool:
	var at := unfold_spot()
	if at == Vector3.INF:
		return false
	var slot: int = craft.hands.get(id, -1)
	return craft.send({"kind": "unfold", "who": id, "slot": slot, "item": held().duplicate(), "at": at, "yaw": rotation.y,
			"up": _unfold_up})


## ミシンの前で T: 手に持った型紙か布をセットする。セットできたら true
func load_machine(machine: Node) -> bool:
	var it := held()
	if craft == null or it.is_empty() or not machine.accepts(it):
		return false
	return craft.send({"kind": "load", "who": id, "slot": craft.hands.get(id, -1), "item": it.duplicate()})


## 一人称の右手に、持っている物の形を持たせる（雪玉を持っているときは雪玉だけ）
func _place_held_fp(ball: bool) -> void:
	var it := held() if not ball else {}
	var key := str(it)
	if key == _held_key:
		return
	_held_key = key
	if _held_fp:
		_held_fp.queue_free()
		_held_fp = null
	if it.is_empty():
		return
	var right: Node3D = hands[0] if hands[0].get_meta("side") > 0 else hands[1]
	_held_fp = held_shape(it)
	_held_fp.position = Vector3(-0.02, 0.05, -0.08)
	_held_fp.scale = Vector3.ONE * 0.7
	for mi in _held_fp.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1 << 2
	right.add_child(_held_fp)


## 手に持った物の小さな形（一人称の右手と、確かめ用）
static func held_shape(it: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	match it.get("kind", ""):
		"pattern":   # クラフト紙の型紙。待ち針の赤い頭
			bm.size = Vector3(0.13, 0.003, 0.17)
			mi.material_override = Look.paper(Color(0.84, 0.72, 0.52))
			var pin := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.008
			sm.height = 0.016
			pin.mesh = sm
			pin.material_override = Look.felt(Color(0.80, 0.24, 0.20))
			pin.position = Vector3(-0.045, 0.006, -0.06)
			root.add_child(pin)
		"fabric":    # たたんだ布の束
			bm.size = Vector3(0.14, 0.035, 0.1)
			mi.material_override = Look.felt(preload("res://fabrics.gd").color(it.get("fabric", "red")), 6.0)
		"folded":    # 折り紙の包み
			bm.size = Vector3(0.11, 0.045, 0.11)
			mi.material_override = Look.felt(preload("res://fabrics.gd").color(it.get("fabric", "red")), 6.0)
			mi.rotation.y = PI / 4
	mi.mesh = bm
	root.add_child(mi)
	root.rotation.x = 0.5
	return root
