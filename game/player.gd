extends CharacterBody3D

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")
const FpHands := preload("res://fp_hands.gd")
const Emotes := preload("res://emotes.gd")
const EmoteRing := preload("res://emote_ring.gd")
const Palm := preload("res://palm.gd")
const SackLook := preload("res://sack_look.gd")
## あなた。一人称で、見えるのは自分の人形と同じ柄の袖口と、紙の手だけ。
## ソリのまわりのどこからでも F でつかめる。
## つかんだまま WASD で、見ている向きを基準にソリへ力をかける（W 前へ押す、S 手前へ引く、A/D 左右へ）。
## どう動くかはソリの滑り木と重力が決める。離すのは F だけ。Shift でダッシュ。
## 前に回って F を押すと紐を持ち、歩いて引ける。
## 身ぶり: Tab を押しているあいだ輪が出て、マウスの向きで選び、離すと出す。輪と同じ 6 つを 1〜6 キーでも:
## 1 高い手のひら、2 低い手のひら、3 指さし、4 ウン、5 ンーン、6 首をかしげてウン？、7 おーーーい（遠くへ呼ぶ）。手のひらは下ろすまで掲げたまま、
## 腕は見ている向きへ。手は Q で片手⇄両手、X で右⇄左。滑りながら高い両手のひらにすると、ひとりでに「ワ〜」。B を押しているあいだ、白い息を長く吐く（押した瞬間に短く吸う）。
## 左 Ctrl を押しているあいだしゃがむ。しゃがんで F で、雪玉を丸める（一人称は雪面を見て。三人称は足もとの少し先の雪面で）。
## 左クリック: 雪玉を持っていれば押してためて（振りかぶり）、離して投げる（長く押すほど遠くへ）。両手のひらなら拍手。
## 持ち物（craft.gd）: ホイールか、トラックパッドの二本指スクロールか、Z（Shift+Z で逆）で手に持つ物を替える
## （素手 → 持ち物 → …。持ち物がないときと Alt を押しているときは、ホイールは視野角。視野角はトラックパッドならピンチ）。
## 売り子のおじさんの前で F で売り台を開く。ミシンの前で F か T でミシンの画面を開き、持ち物から型紙と布を選んで縫う。
## 米袋は装備（craft.gd の sacks）: N で、いま選んでいる米袋を足もとにぽんと出して、すぐ乗る（坂ならそのまま滑り出す）。
## もう一度 N で降りて、くるっと丸めて帯に戻す。離れた所に出したままなら、N で足もとへ呼び戻す。
## 出すときは、帯の丸めた袋を引き抜いて前へ広げ、しゃがんで腰を下ろし、前の紐を握る（人形のコマ。doll.gd の sack_start）。
## 乗るのは押した瞬間なので、坂ならその途中から滑り出し、Space で蹴ればすぐ座った姿になって漕げる。
## 走りながら（歩きながら）出すと、前へ飛び乗る勢いで滑り出す（SACK_CARRY）。平らな所でも少し滑ってから止まる。
## 乗っているあいだの Space は足で蹴る。たたくたびに一回だけ（押しっぱなしでは蹴らない。2026-10-30 代表「スペース連打じゃないとだめ。ダサくて必死にこぐのがいい」）。
## どの米袋を装備するかは、I で開く装備の画面（craft_ui.gd）で選ぶ。
## ランタンも装備（craft.gd の lanterns）: 帯の左に提げ、R で点ける・消す（2026-10-29 代表。ソリをふもとへ戻すのは Backspace に移した）。
## 左クリックの順: 雪玉を持っていれば投げる → 高い両手のひらなら拍手。

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
var ride_lean := Vector3.ZERO  # 乗っているときの体重移動（x 左右 -1〜1、y 前傾、z 後傾）。一緒に乗った仲間が合わせる
var seat := Vector3.INF
var handle := Vector3.INF    # つかんでいる所（ソリの座標）
var push_dir := Vector3.ZERO # 押す向き（ソリの座標）
var pushing := false
var pulling := false
var prompt := ""             # 画面に出す一言（main.gd が読む）
var base_fov := 75.0         # ホイールで変える視野角
var third := false           # C で三人称
var cam_dist := 3.4          # 三人称: 頭の後ろからカメラまでの距離 (m)。Alt＋ホイール・ピンチ・二本指の縦・設定
var cam_height := 0.6        # 三人称: 頭より上のカメラの高さ (m)。Alt＋Shift＋ホイール・二本指の横・設定
const CAM_DIST := Vector2(1.4, 9.0)     # 人形の真後ろ近く 〜 ソリ全体が見える遠さ
const CAM_HEIGHT := Vector2(-0.3, 3.0)  # 肩ごし 〜 見下ろす
var _cam_save_t := -1.0      # ホイールで変えた視野角・カメラを、少し止まってから設定に保存する
var _cam_free := 0.0         # 三人称のカメラが、当たりで縮められずにいられる距離（いまの値）
var bob_enabled := true      # 設定: 押す・引くときの視点の揺れ
var fov_kick_enabled := true # 設定: 押すときに画角が少し広がる
# 滑るときに画角が広がる（2026-10-29 代表「スピードに従って視野角を広げてほしい」）。
# 乗って滑っているあいだ、速さに合わせて視野角（base_fov）に足す。止まっていれば足さない。
# 滑るときの風（ride_wind.gd）と同じ速さで広がりはじめ、毛糸が流れきる速さ（SPEED_FULL）までに大半が広がる。
# 中・大のソリでまっすぐ下ると 8〜10 m/s。残りは米袋の連打（16 m/s 近く）のような速さのためにとっておく
const RIDE_FOV_MAX := 14.0                  # 足す視野角の上限 (°)
const RIDE_FOV_SPEED := Vector3(2.0, 9.0, 16.0)  # 広がりはじめる速さ、大半（RIDE_FOV_MAIN）が広がる速さ、上限に届く速さ (m/s)
const RIDE_FOV_MAIN := 0.7
const FOV_CAP := 120.0                      # 足したあとの視野角の上限 (°)。広く設定している人でも魚眼にしない
const RIDE_FOV_RISE := 1.6                  # 追いつく速さ（1/秒）。速くなるときはゆっくり広がり、
const RIDE_FOV_FALL := 2.4                  # 遅くなるときは少し早めに戻る（止まったあと広いままにしない）
const RIDE_CAM_PUSH := 0.5                  # 三人称: 上限のとき、カメラを後ろへ引く距離 (m)
var ride_fov_enabled := true  # 設定: 滑るときに画角が広がる
var ride_fov_amount := 1.0    # 設定: その強さ（0〜1。上限に掛ける）
var ride_rush := 0.0          # いまの盛り上がり（0〜1。速さをなめらかにしたもの。HUD などが同じ拍子で読める）
var ride_fov := 0.0           # いま足している視野角 (°)
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
const HELD_TILT := 0.12      # 畳んだソリの包みの名札の面を、まっすぐより少し上へ傾ける (rad)
const HELD_TURN := 0.0     # 少し内へ回す (rad)
const HELD_SCALE := 1.25     # 一人称で持つ包みの大きさ
var last_sled: RigidBody3D   # 最後に触った（つかむ・紐・乗る・広げる）ソリ。左下の札はこのソリのタグ（hud.gd）
var _pan_acc := 0.0          # 二本指スクロールのたまった量
const PAN_STEP := 1.5        # これだけたまったら 1 つ持ち替える
var last_item := {}          # 最後に触ったソリを畳んで持っていれば、その持ち物（last_sled は null）
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

	# 米袋に座ったときに一人称で見える両脚（層 3）。米袋に合わせて置く
	_fp_legs = FpHands.make_legs(doll.kind, 1 << 2)
	_fp_legs.top_level = true
	_fp_legs.visible = false
	add_child(_fp_legs)

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
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		ring = EmoteRing.new()
		layer.add_child(ring)
	craft = get_parent().get_node_or_null("Craft")
	if craft and id >= 0:
		craft.join(id)
		craft.happened.connect(_on_craft)
		_load_tag()
	last_sled = sled

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 一人称の視野角を変える（ホイール・ピンチ・二本指）。少し止まってから設定に保存する
func _zoom_fov(d: float) -> void:
	base_fov = clampf(base_fov + d, 50.0, 110.0)
	_cam_save_t = 0.6


## 三人称のカメラの距離と高さを変える（ホイール・ピンチ・二本指）。少し止まってから設定に保存する
func _zoom_cam(d_dist: float, d_height: float) -> void:
	cam_dist = clampf(cam_dist + d_dist, CAM_DIST.x, CAM_DIST.y)
	cam_height = clampf(cam_height + d_height, CAM_HEIGHT.x, CAM_HEIGHT.y)
	_cam_save_t = 0.6


func _save_cam(dt: float) -> void:
	if _cam_save_t < 0.0:
		return
	_cam_save_t -= dt
	if _cam_save_t < 0.0:
		var st = get_parent().get("settings")
		if st:
			st.sync("fov", base_fov)
			st.sync("cam_dist", cam_dist)
			st.sync("cam_height", cam_height)


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
	elif e is InputEventPanGesture:
		# トラックパッドの二本指スクロール（Mac ではホイールでなくこれで届く）: ホイールと同じ決まり。
		# 持ち物があれば持ち替え。Alt を押しているか持ち物がなければ、一人称は視野角、三人称は縦で距離・横で高さ
		if menu_open:
			pass
		elif craft and not craft.bag(id).is_empty() and not e.alt_pressed:
			_pan_acc += e.delta.y
			if absf(_pan_acc) >= PAN_STEP:
				cycle_hand(1 if _pan_acc > 0.0 else -1)
				_pan_acc = 0.0
		elif third:
			_zoom_cam(e.delta.y * 0.25, -e.delta.x * 0.1)
		else:
			_zoom_fov(e.delta.y * 2.0)
	elif e is InputEventMagnifyGesture:
		# トラックパッドのピンチ: 広げると寄る（一人称は視野角が狭まり、三人称はカメラが近づく）
		if third:
			_zoom_cam(cam_dist / e.factor - cam_dist, 0.0)
		else:
			_zoom_fov(base_fov / e.factor - base_fov)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			var step := -1 if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1
			# Shift＋ホイールは、Mac では横のホイールとして届くことがある
			var sideways: bool = e.shift_pressed or e.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
			if menu_open:
				pass
			elif craft and not craft.bag(id).is_empty() and not e.alt_pressed:
				cycle_hand(step)   # 持ち物があれば、ホイールは手に持つ物
			elif third:
				if sideways:
					_zoom_cam(0.0, -0.2 * step)
				else:
					_zoom_cam(0.4 * step, 0.0)
			else:
				_zoom_fov(3.0 * step)
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
				if mode == Mode.WALK and machine_near() and (not shop_near() or _facing(get_parent().sewing.machine.global_position) > _facing(get_parent().shopkeeper.global_position)):
					get_parent().craft_ui.open_machine()   # ミシンの画面（おじさんも近ければ、向いている方）
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
					Mode.RIDE:
						catch_from_sack()   # 米袋で追いついたソリをつかむ
			KEY_SPACE:
				if mode == Mode.RIDE and sled.kick(self):
					_kicked()   # 乗っているあいだの Space は足で漕ぐ（ジャンプしない）
			KEY_TAB:
				if ring and not menu_open:
					ring.open(hand, _height(), point_at != Vector3.INF)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				# 輪と同じ 6 つ: 1 高い手のひら、2 低い手のひら、3 指さし、4 ウン、5 ンーン、6 首をかしげてウン？
				_choose(["high", "low", "point", "un", "nn", "huh", "oi"][e.physical_keycode - KEY_1])
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
			KEY_N:
				if craft and not menu_open and not rooted():
					toggle_sack()
			KEY_R:
				if craft and not menu_open:
					toggle_lamp()
			KEY_I:
				if craft and not menu_open and get_parent().get("craft_ui"):
					get_parent().craft_ui.open_gear()   # 装備の画面
			KEY_Z:
				# 手に持つ物を替える（Shift で逆回り）。ホイールやトラックパッドが使えないとき
				if craft and not craft.bag(id).is_empty() and not menu_open:
					cycle_hand(-1 if e.shift_pressed else 1)
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
	_touched(sled)
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
	_touched(sled)


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
	_touched(sled)
	_col.disabled = true


func get_off() -> void:
	if mode != Mode.RIDE:
		return
	sled.dismount(self)
	var was := seat
	seat = Vector3.INF
	mode = Mode.WALK
	_col.disabled = false
	if sled.kind == "sack":
		# 米袋: その場で立ち上がり、袋のすぐ後ろに立つ（足もとで丸めて帯に戻せるように）。袋の形はふだんへ
		SackLook.set_stage(sled, was, 0)
		global_position = sled.global_position + sled.global_basis.z * 0.6 + Vector3.UP * 0.2
		velocity = Vector3.ZERO
		return
	global_position = sled.global_position + sled.global_basis.x * 1.4 + Vector3.UP * 0.5
	velocity = Vector3.ZERO


# ---------------------------------------------------------------- 米袋で足で漕ぐ・追いついて止める

const CATCH_REACH := 2.4     # 米袋に乗ったまま F でつかめる、ほかのソリのつかみ所までの距離 (m)
var _kick_side := 1


## 蹴れた: 足を交互に出し（人形のコマ）、足もとに雪の粉、蹴る音
func _kicked() -> void:
	_kick_side = -_kick_side
	doll.kick(_kick_side)
	var foot: Vector3 = sled.to_global(seat + Vector3(0.15 * _kick_side, -seat.y, 0.2))
	preload("res://snowball.gd").splat_at(get_parent(), foot + Vector3.UP * 0.05, Vector3.UP, true)
	var au := get_parent().get_node_or_null("Audio")
	if au and au.has_method("kick"):
		au.kick(self)


## 米袋に乗ったまま F: そばに別のソリがあれば、米袋から降りてそのソリにしがみつく。
## 速く下っていれば、そのまま「引きずられて止める」に入る。米袋は自動で帯に戻す（craft.gd の sack_in。装備なので
## 空の米袋を坂に残さない。2026-10-29 店のセッションと決めた）
func catch_from_sack() -> bool:
	var sack := sled
	if sack == null or sack.kind != "sack":
		return false
	var best: RigidBody3D = null
	var best_d := CATCH_REACH
	for s in get_tree().get_nodes_in_group("sleds"):
		var rb := s as RigidBody3D
		if rb == null or rb == sack or not rb.visible:
			continue
		var gp: Array = rb.grip_point_near(global_position)
		var d := global_position.distance_to(rb.to_global(gp[0]))
		if d < best_d:
			best = rb
			best_d = d
	if best == null:
		return false
	var at := global_position
	get_off()
	global_position = at
	sled = best
	grab()
	if craft:
		craft.send({"kind": "sack_in", "who": id})   # 降りたあとなので、乗っている人はいない
	return mode == Mode.GRIP


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
			ride_lean = Vector3(_key(KEY_D) - _key(KEY_A), _key(KEY_W), _key(KEY_S))
			sled.lean(ride_lean.x, ride_lean.y > 0.0, ride_lean.z > 0.0)
			prompt = "W 前傾　S 後傾で止まる　A/D 体重をかけて曲がる　E 降りる"
		Mode.GRIP:
			_grip(dt)
		Mode.ROPE:
			_walk(dt, true)
		Mode.WALK:
			_walk(dt, false)
	_update_point()
	_update_emote(dt)
	_sack_events(dt)
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
	if craft:
		# 帯の丸めた米袋（出していなければ下げている）
		var spec: Dictionary = craft.sack(id)
		doll.belt_sack = not spec.is_empty() and craft.sack_sled(id) == null
		if not spec.is_empty():
			doll.belt_color = preload("res://fabrics.gd").color(spec.fabric) if spec.fabric != "" else preload("res://sled.gd").KINDS["sack"].color
		# 帯の左のランタン
		doll.lantern = craft.lantern(id).get("look", "")
		doll.lantern_lit = craft.lamp_on(id)


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
	# 引きずられているときの体勢の崩れ（人形と同じコマで刻む）: 雪のでこぼこ（コマごと）、左右のよろけ（ゆっくり）、
	# ときどき膝ががくっと抜けて沈む。視点の揺れを切ると弱く
	var jolt := 0.0
	var reel := 0.0
	var dip := 0.0
	if _drag_k > 0.0:
		var f := Doll.frame_index()
		var calm := 1.0 if bob_enabled else 0.3
		jolt = (0.015 if f % 2 == 0 else -0.015) * _drag_k * calm
		reel = sin(f * 0.55) * 0.09 * _drag_k * calm
		dip = (0.1 if f % 14 < 3 else 0.0) * _drag_k * calm
	if not third:
		var eye := Vector3(0, eye_y - 0.3 * _drag_k - dip + jolt, -0.35 * _drag_k)
		if mode == Mode.RIDE and doll.sack_seated():
			# 乗っているときは、座った人形の目の所（席や人形が変わっても合う）。ソリが傾けば一緒に傾く。
			# 乗り降りは同じ lerp で、すっと立ち上がる・腰を下ろす。米袋は、袋を広げ終えて腰を下ろしてから下がる
			var e := doll.eye_point(true)
			if sled.kind == "sack":
				e += SACK_EYE   # 米袋では少し後ろへもたれる（膝と紐を握った手と袋の前の縁が、画面の下に見える）
			eye = to_local(Transform3D(sled.global_basis.orthonormalized(), global_position) * e)
		eye.y += _cam_em.z
		cam.position = cam.position.lerp(eye, min(1.0, dt * 10.0))
		cam.rotation = Vector3(clampf(_pitch + _cam_em.x - 0.18 * _drag_k - dip * 1.5, -1.5, 1.4), _cam_em.y + reel * 0.5, _cam_roll + reel + jolt * 2.0)
		return
	# 三人称: 頭の少し上を中心に、後ろからカメラの距離と高さで見る。マウスの上下で回り込む。
	# 頭からカメラへ玉を滑らせて、壁・天井・地面・ソリに当たる手前で止める（埋まらない）。
	# 当たって縮むときはすぐ、離れて戻るときはゆっくり（壁の向こうが一瞬見えないように）
	var pivot := Vector3(0, 1.6, 0)
	var offset := Vector3(0, cam_height, cam_dist + RIDE_CAM_PUSH * ride_fov / RIDE_FOV_MAX).rotated(Vector3.RIGHT, clamp(_pitch, -0.6, 1.0))
	var pivot_w := to_global(pivot)
	var want_w := to_global(pivot + offset)
	var floor_y: float = get_parent().height(want_w.x, want_w.z) + 0.4
	if want_w.y < floor_y:
		want_w.y = floor_y
	var ray := want_w - pivot_w
	var free := _cam_clear(pivot_w, ray)
	_cam_free = free if free < _cam_free else move_toward(_cam_free, free, dt * 4.0)
	var at := pivot_w + ray.normalized() * minf(_cam_free, ray.length())
	cam.global_position = at if cam.global_position.distance_to(at) > 2.0 or free < _cam_free + 0.01 \
		else cam.global_position.lerp(at, min(1.0, dt * 10.0))
	if cam.global_position.distance_to(pivot_w) > 0.05:
		cam.look_at(pivot_w, Vector3.UP)


## 乗って滑っている速さから、視野角に足す分を決める。速さは雪のでこぼこで細かく揺れるので、ならしてから使う。
## 一人称も三人称も同じだけ足す（三人称はそのうえでカメラを少し後ろへ引く）
func _update_ride_fov(dt: float) -> void:
	var want := 0.0
	if mode == Mode.RIDE:
		var v := sled.linear_velocity.length()
		want = RIDE_FOV_MAIN * smoothstep(RIDE_FOV_SPEED.x, RIDE_FOV_SPEED.y, v) \
				+ (1.0 - RIDE_FOV_MAIN) * smoothstep(RIDE_FOV_SPEED.y, RIDE_FOV_SPEED.z, v)
	ride_rush = lerpf(ride_rush, want, 1.0 - exp(-dt * (RIDE_FOV_RISE if want > ride_rush else RIDE_FOV_FALL)))
	ride_fov = RIDE_FOV_MAX * ride_rush * ride_fov_amount if ride_fov_enabled else 0.0


## 頭（from）からカメラの向き（ray）へ玉を滑らせ、何にも当たらずに行ける距離を返す。
## 自分と、乗っている・つかんでいるソリの縁の内側は、人形の体と同じくよける（ソリは当たりに入れる。中に潜らない）
func _cam_clear(from: Vector3, ray: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.22
	q.shape = ball
	q.transform = Transform3D(Basis(), from)
	q.motion = ray
	q.exclude = [get_rid()]
	if space.get_rest_info(q).size() > 0:   # 頭がもう何かに触れている（座ったソリなど）: ソリは外して測り直す
		q.exclude = [get_rid(), sled.get_rid()]
	var r := space.cast_motion(q)
	return maxf(0.3, ray.length() * r[0] - 0.05)


func _pose_hands(dt: float) -> void:
	var working := pushing or pulling
	var bob := sin(_t * 9.0) if bob_enabled else 0.0
	# 押す・引くと視点がわずかに揺れ、画角が少し広がる
	_update_ride_fov(dt)
	_place_camera(dt, bob, working)
	_save_cam(dt)
	var fov := base_fov + (4.0 if working and fov_kick_enabled else 0.0)
	cam.fov = lerp(cam.fov, maxf(fov, minf(fov + ride_fov, FOV_CAP)), min(1.0, dt * 4.0))
	var fi := Doll.frame_index()
	for h in hands:
		var s: int = h.get_meta("side")
		var target: Vector3
		match mode:
			Mode.GRIP:
				# 縁を握る。押すと腕が少し伸びる。引きずられていると、腕がソリへ引っぱられて伸びきる
				var reach := -0.5 - (0.06 if pushing else 0.0) - 0.12 * _drag_k
				target = Vector3(0.17 * s, -0.22 + (bob * 0.015 if pushing else 0.0) - 0.05 * _drag_k, reach)
				if s < 0 and _drag_k > 0.5:
					# 引きずられている: 左手はソリを離して宙をかく（画面の左上へ大きく輪を描いて出入りする）
					var sw := fi * 0.9
					target = Vector3(-0.42 - 0.1 * cos(sw), 0.05 + 0.18 * sin(sw), -0.5 + 0.08 * cos(sw * 0.5))
			Mode.ROPE:
				# 右手で紐を握り、左手は振る
				if s > 0:
					target = Vector3(0.2, -0.3 - (0.05 if pulling else 0.0), -0.4)
				else:
					target = Vector3(-0.3, -0.3 + sin(_t * 6.0) * 0.01 * velocity.length(), -0.45)
			Mode.RIDE:
				if sled.kind == "sack":
					var k := doll.sack_k("out")
					if k >= 0 and k < 3:
						# 取り出して広げる: 右手を帯へ（画面の下の外）→ 胸の前で両手に → 前へ振り下ろす
						target = [Vector3(0.3 * s, -0.7, 0.05), Vector3(0.1 * s, -0.3, -0.3), Vector3(0.15 * s, -0.42, -0.52)][k]
					else:
						target = cam.to_local(sled.to_global(seat + Vector3(0.2 * s, 0.1, -0.5)))   # 袋の前の左右の耳で紐を握る（まん中の膝が見えるように）
				else:
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
			var on_sled: bool = (mode == Mode.GRIP or (mode == Mode.RIDE and sled.kind == "sack" and doll.sack_seated())) and not pointing and em_hand == Vector3.INF
			h.set_meta("hold", sled.to_local(cam.to_global(target)) if on_sled else target)
			h.set_meta("on_sled", on_sled)
		var hold: Vector3 = h.get_meta("hold", target)
		h.position = cam.to_local(sled.to_global(hold)) if h.get_meta("on_sled", false) else hold
		# 腕は画面の下の肩から手へ伸びる。袖をその向きに
		var arm := h.position - Vector3(0.2 * s, -0.42, 0.12)
		h.basis = Basis.looking_at(arm, Vector3.UP)
	_hand_frame = fi
	_pose_fp_legs(fi)
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
	_face_held_fp()
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
		"wa": true, "un": true, "nn": true, "huh": true, "oi": true,
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
		"oi":
			return Vector3(-0.05 if k < 2 else (0.1 if k < 15 else 0.03), 0, 0)   # 顔を上げて呼ぶ
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
		"oi":
			# 空いた手（手のひらも指さしもしていない手。右から）を口の横へ。画面の下の端に、手袋の先がのぞく
			if k >= 1 and k < 16:
				var free := 0
				for sd in [1, -1]:
					if free == 0 and doll.hand_shapes[0 if sd > 0 else 1] == "" and not (point_at != Vector3.INF and sd in Palm.sides_of(hand)):
						free = sd
				if s == free:
					return Vector3(0.1 * s, -0.2, -0.22)
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
	var to := from - cam.global_basis.z * 2.2
	if third:
		# 三人称ではカメラが人形の後ろ上にあり、カメラからの線は雪に届かない。人形の胸から、足もとの少し先の雪面へ
		var fwd := -global_basis.z
		fwd.y = 0
		from = global_position + Vector3.UP * 0.9
		to = global_position + fwd.normalized() * 0.7 + Vector3.DOWN * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, to)
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


func _touched(s: RigidBody3D) -> void:
	last_sled = s
	last_item = {}


## 自分の畳む・広げるで、最後に触ったソリを替える
func _on_craft(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	match ev.kind:
		"sewn":   # 自分の縫ったソリが、最後に触ったソリになる（左下の札がその場所を出す）
			var made: RigidBody3D = craft.sleds.get(int(ev.id))
			if made:
				_touched(made)
		"fold":
			last_sled = null
			last_item = ev.item
		"unfold":
			var s: RigidBody3D = craft.sleds.get(int(ev.id))
			if s:
				_touched(s)


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


## ミシンの前（立つ所のそば）で、ミシンの方を向いていて、縫い始められるか
func machine_near() -> bool:
	var sew = get_parent().get("sewing")
	return sew != null and get_parent().get("craft_ui") != null and sew._user_near() and sew.can_sew() \
			and _facing(sew.machine.global_position) > 0.2


## 見ている向きと、at の方向の合い具合（1 で真正面）
func _facing(at: Vector3) -> float:
	var d := at - global_position
	d.y = 0
	return (-global_basis.z).dot(d.normalized()) if d.length() > 0.01 else 1.0


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
	_held_fp.set_meta("folded", it.get("kind") == "folded")


## 畳んだソリの包みは、名札を貼った面を自分（カメラ）へ向けて、手の少し上・内側に持つ（毎コマ）
func _face_held_fp() -> void:
	if _held_fp == null or not _held_fp.get_meta("folded", false):
		return
	var hand: Node3D = _held_fp.get_parent()
	var at := cam.to_local(hand.global_position) + Vector3(-0.1, 0.1, -0.02)
	var b := cam.global_basis.orthonormalized() * Basis(Vector3.RIGHT, PI / 2 - HELD_TILT) * Basis(Vector3.UP, HELD_TURN)
	_held_fp.global_transform = Transform3D(b.scaled(Vector3.ONE * HELD_SCALE), cam.to_global(at))


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
		"folded":    # 折り紙の包み。上（+Y）の面に名札を貼り、窓に広げた姿がくるくる回る。名札の面を見る人へ向けるのは呼ぶ側
			bm.size = Vector3(0.13, 0.04, 0.13)
			mi.material_override = Look.felt(preload("res://fabrics.gd").color(it.get("fabric", "red")), 6.0)
			mi.rotation.y = PI / 4
			var Tags := preload("res://sled_tags.gd")
			Tags.patch_on(root, 0.02, it.get("tag", 0), 0.15, Tags.turntable(it.get("sled", "mid"), it.get("fabric", "")))
			mi.mesh = bm
			root.add_child(mi)
			return root
	mi.mesh = bm
	root.add_child(mi)
	root.rotation.x = 0.5
	return root


# ---------------------------------------------------------------- 米袋を出す・座る・しまう動き（doll.gd の sack_start）

const SACK_LOOK := -0.32     # 米袋に腰を下ろすとき、これより上を見ていれば膝のあたりまで視線を下げる (rad。袋の傾きから)
const SACK_EYE := Vector3(0, -0.03, 0.2)   # 米袋に座ったときの目の、人形の目からのずれ（後ろへもたれる）
var _sack_ev := 0            # 米袋を出す動きで、済んだ出来事（1 広げた / 2 腰を下ろした / 3 乗っている形）
var _sack_hidden: Node3D     # 広げるコマまで隠している米袋の見た目
var _sack_landed := false
var _fp_legs: Node3D         # 一人称の両脚（米袋に座っているときだけ）
var _legs_frame := -1


## 米袋を出す動きの出来事を、人形のコマに合わせて起こす: 広げる（ばさっ）→ 腰を下ろす（ぽふっ。袋がへこみ、雪の粉）
func _sack_events(dt: float) -> void:
	var k := doll.sack_k("out")
	if k < 0 or mode != Mode.RIDE or sled == null or sled.kind != "sack":
		if k >= 0:
			doll.sack_anim = ""
		if _sack_hidden and is_instance_valid(_sack_hidden):
			_sack_hidden.visible = true
		_sack_hidden = null
		return
	if k >= 2 and _sack_ev < 1:
		_sack_ev = 1
		if _sack_hidden and is_instance_valid(_sack_hidden):
			_sack_hidden.visible = true
		_sack_hidden = null
		_sack_sound("fling")
	if k == 3 and _sack_ev < 2 and not _sack_landed:
		_sack_landed = true   # 雪の上に落ちて広がる
		preload("res://snowball.gd").splat_at(get_parent(), sled.to_global(Vector3(0, 0.03, -0.2)), sled.global_basis.y, true)
	SackLook.fling(sled, k)
	if k >= 4 and _sack_ev < 2:
		_sack_ev = 2
		SackLook.set_stage(sled, seat, 1)
		_sack_sound("sit")
		for sx in [-1, 1]:
			preload("res://snowball.gd").splat_at(get_parent(), sled.to_global(Vector3(0.32 * sx, 0.03, seat.z)), sled.global_basis.y, true)
	if k >= 5 and _sack_ev < 3:
		_sack_ev = 3
		SackLook.set_stage(sled, seat, 2)
	if k >= 3 and k <= 6 and not third:
		# 腰を下ろしながら、膝のあたりへ目を落とす（下り坂では袋が前へ傾いている分も）
		var slope := asin(clampf((-sled.global_basis.z).y, -1.0, 1.0))
		_pitch = move_toward(_pitch, minf(_pitch, SACK_LOOK + minf(slope, 0.0)), dt * 3.0)


func _sack_sound(what: String) -> void:
	var au := get_parent().get_node_or_null("Audio")
	if au and au.has_method("sack"):
		au.sack(self, what)


## 一人称の両脚: 米袋に座っているあいだ、袋の上に投げ出した腿とすねと足先。蹴る足は横へ出て、後ろへ蹴り、戻る（人形と同じコマ）
func _pose_fp_legs(fi: int) -> void:
	var show: bool = mode == Mode.RIDE and sled.kind == "sack" and doll.sack_seated() and not third
	_fp_legs.visible = show
	if not show:
		return
	_fp_legs.global_transform = Transform3D(sled.global_basis.orthonormalized(), sled.to_global(seat))
	if fi == _legs_frame:
		return
	_legs_frame = fi
	var kk: int = fi - doll._kick_frame
	for side in ["L", "R"]:
		var sx := 1.0 if side == "R" else -1.0
		var hip := Vector3(0.08 * sx, 0.02, 0.0)
		var knee := Vector3(0.1 * sx, 0.15, -0.25)
		var foot := Vector3(0.1 * sx, -0.08, -0.47)
		if kk >= 0 and kk < 3 and side == doll._kick_leg:
			knee = [Vector3(0.17 * sx, 0.03, -0.22), Vector3(0.2 * sx, -0.02, -0.12), Vector3(0.13 * sx, 0.05, -0.25)][kk]
			foot = [Vector3(0.28 * sx, -0.12, -0.38), Vector3(0.32 * sx, -0.14, 0.05), Vector3(0.16 * sx, -0.1, -0.42)][kk]
		FpHands.pose_leg(_fp_legs, side, hip, knee, foot)

## 乗るのは今（summon_sack）。見た目は、帯から取り出して広げ、腰を下ろすまでをコマで追う（袋は広げるコマまで隠す）
func _start_sack_out() -> void:
	doll.sack_start("out")
	_sack_ev = 0
	_sack_landed = false
	_sack_hidden = sled.get("_body")
	if _sack_hidden:
		_sack_hidden.visible = false


# ---------------------------------------------------------------- 装備の米袋（craft.gd の sack_out・sack_in）

const SACK_NEAR := 3.5       # 出している米袋がこれより近ければ、N でしまう（遠ければ足もとへ呼び戻す）
const SACK_CARRY := 1.8      # 走りながら出すと、前へ飛び乗る勢いで、前へ進んでいた速さのこれだけ倍で滑り出す（横・後ろはそのまま）
const SACK_CARRY_MAX := 6.5  # 受けつぐ速さの上限 (m/s)

## R: 帯のランタンを点ける・消す（提げていなければ何もしない）
func toggle_lamp() -> bool:
	return craft.send({"kind": "lamp", "who": id, "on": not craft.lamp_on(id)})


## N: 米袋を出して乗る／降りてしまう／遠くの米袋を足もとへ呼び戻す
func toggle_sack() -> void:
	var gs: RigidBody3D = craft.sack_sled(id)
	if gs:
		var on_it := mode == Mode.RIDE and sled == gs
		var near := global_position.distance_to(gs.global_position) < SACK_NEAR
		if on_it or (near and gs.riders.is_empty()):
			if on_it:
				get_off()
			doll.sack_start("in")   # 立ってかがみ、くるくる丸めて帯へ
			_sack_sound("roll")
			craft.send({"kind": "sack_in", "who": id})
			return
		if not gs.riders.is_empty():
			return   # ほかの人が乗っている
		craft.send({"kind": "sack_in", "who": id})   # 遠くに置いたまま: しまって、足もとに出し直す
	if summon_sack():
		_start_sack_out()


## 足もとに米袋を出して、すぐ乗る。つかんでいる・紐を持っている・ほかのソリに乗っているなら、離れてから。
## 歩いて・走っていれば、その勢いを米袋の初めの速さにする（前へは飛び乗る分 SACK_CARRY 倍）
func summon_sack() -> bool:
	var carry := Vector3.ZERO
	if mode == Mode.WALK:
		carry = Vector3(velocity.x, 0, velocity.z)
		var fwd := -global_basis.z
		fwd.y = 0
		carry += fwd.normalized() * maxf(0.0, carry.dot(fwd.normalized())) * (SACK_CARRY - 1.0)
		carry = carry.limit_length(SACK_CARRY_MAX)
	if mode == Mode.GRIP or mode == Mode.ROPE:
		let_go()
	elif mode == Mode.RIDE:
		get_off()
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.DOWN * 2.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if hit else global_position
	var up: Vector3 = hit.normal if hit and hit.normal.y > 0.6 else Vector3.UP
	carry -= up * carry.dot(up)   # 雪面に沿わせる
	if not craft.send({"kind": "sack_out", "who": id, "at": at, "yaw": rotation.y, "up": up, "v": carry}):
		return false
	var gs: RigidBody3D = craft.sack_sled(id)
	if gs == null:
		return false
	sled = gs
	get_on()
	return mode == Mode.RIDE


# ---------------------------------------------------------------- 自分の名札（sled_tags.gd の部品。装備の画面で決める）

const TAG_FILE := "user://my_tag.cfg"

## 保存してある自分の名札を読む（なければ、人の番号から決めたはじめの名札のまま）。
## 手に入れた部品を先に戻してから、名札を付ける（前の版の保存にない部品は、はじめの名札のまま）
func _load_tag() -> void:
	var cf := ConfigFile.new()
	if cf.load(TAG_FILE) != OK:
		return
	var Tags := preload("res://sled_tags.gd")
	if cf.has_section("owned"):
		for part in cf.get_section_keys("owned"):
			for i in cf.get_value("owned", part, []):
				craft.send({"kind": "tag_unlock", "who": id, "part": part, "index": int(i)})
	var d := {}
	for part in Tags.PARTS:
		if cf.has_section_key("tag", part):
			d[part] = int(cf.get_value("tag", part))
	craft.send({"kind": "tag_design", "who": id, "design": d})


## 自分の名札を保存する（装備の画面で変えたとき。次に起動しても同じ名札）
func save_tag() -> void:
	var cf := ConfigFile.new()
	var d: Dictionary = craft.tag_designs.get(id, {})
	for part in d:
		cf.set_value("tag", part, d[part])
	var owned: Dictionary = craft.tag_owned.get(id, {})
	for part in owned:
		cf.set_value("owned", part, owned[part])
	cf.save(TAG_FILE)
