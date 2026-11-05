extends CharacterBody3D

const Doll := preload("res://doll.gd")
const Emotes := preload("res://emotes.gd")
const Palm := preload("res://palm.gd")
const Seats := preload("res://seats.gd")
## 押すのを手伝う仲間（通信を入れるまでの代わり）。
## ソリの下り側に回って頂上へ押す → 頂上であなたが乗ったら一緒に乗る → 下で降りてまた押す。
## 身ぶりへの返し（確かめ用の簡単なもの）: あなたが近くで手のひらを掲げると、ソリを離して前まで来て、
## 同じ高さで掲げる（高ければハイタッチ、低ければ握手）。片手か両手かもまねる。
## 一緒に乗っているとき、あなたが高い両手のひらにしたら一緒に上げる（万歳）。声には同じ声、「ウン？」には「ウン」、拍手には拍手。
## 「おーーーい」と呼ぶと、遠くからでもそちらを見て、「おーい」と返すか手を振る（ソリをつかんでいれば声で返す）。
## 雪玉が当たると、のけぞって笑う。つかんでいたら手を離し、少しして（REGRAB_WAIT）つかみ直しに行く。
## 一緒に乗っているときは、あなたの体重移動（A/D・前傾・後傾）に LEAN_DELAY 遅れて合わせる（lean_mode = "follow"）。
## 体重移動は乗っている一人ひとりの力が足し合わさるので、仲間が合わせると大きいソリもぐっと曲がる。"off" なら何もしない。
## 速く下るソリをつかむと引きずられ、引きずられている間は押さずに踏ん張る（止める力は sled.gd がまとめてかける）。
## lounge の仲間は、ソリを押さずにロッジでくつろぐ: 空いた席（seats.gd）に座り、しばらくすると立って別の空いた席へ歩いて座り直す。
## あなたが席に座ると、そのそばの空いた席へ寄ってくる（同じ机を囲む）。座る・立つは、あなたと同じ出来事（seats.gd の sit・stand）
## 雪合戦: 雪玉を持ったあなたに低い手のひらを差し出されると、しゃがんで雪玉を作ってから握手しに来る（握手で対決が始まる。duel.gd）。
## 掛金を受け、円の中を回りながら振りかぶって投げ、ときどきよけて、ときどき取る。なくなれば作る。ロッジでくつろぐ仲間はしない
## 財布はいつも金色の真鍮のボタン 5 枚以上（DUEL_BUTTONS）。掛金で減っても、次の握手で戻るので、賭けられなくならない

enum State { PUSH, WAIT, RIDE }

const SPEED := 2.4
const REGRAB_WAIT := 1.5     # 雪玉が当たって手を離してから、つかみ直すまで (s)
const LEAN_DELAY := 0.3      # 一緒に乗っているとき、あなたの体重移動に合わせるまでの遅れ (s)
const GRAVITY := 24.0         # 落ちるときの重力（player.gd の FALL_GRAVITY と同じ。仲間は跳ばないので、下りだけ）

var sled: RigidBody3D
var player: Node3D          # いないとき（確かめ用）は仲間だけで滑る
var side := 1
var state := State.PUSH
var seat := Vector3.INF
var handle := Vector3.INF   # つかんでいる所（ソリの座標）
var doll: Doll               # 見た目の人形（右側の仲間は折り紙、左側は新聞紙。doll_kind で替えられる）
var doll_kind := ""          # 始めの人形（doll.gd の KINDS。"" なら右は折り紙、左は新聞紙。main.gd が入れる）
var debug := ""
var post: Node3D = null      # 持ち場（ミシンの足踏みなど）。あればソリを押さず、そこに立って post_look を向く
var post_look := Vector3.INF
var _col: CollisionShape3D
var _still := 0.0
var _wait := 0.0
var hub: Emotes
var id := -1
var stays_dry := true         # 一人プレイの仲間（CPU）は湿らない（damp.gd。乾かしに行かないので。2026-11-01 代表「一人プレイの時の CPU は濡れないように」）
var _replies: Array = []     # [残り秒, 身ぶり]
var _five_with := -1         # ハイタッチをしにいく相手の番号
var _five_until := 0         # このコマまでに届かなければやめる
var _five_sent := false      # もう手を上げた（あとは合うまで、相手の前へ寄り続ける）
var _em := {}
var _regrab := 0.0           # これが 0 になるまでつかまない
var lean_mode := "follow"    # 一緒に乗っているときの体重移動: "follow" あなたに合わせる、"off" しない（main.gd の --bot-lean=）
var _lean_q: Array = []      # [時刻, あなたの体重移動]（遅れて合わせるため）
var _lean_now := Vector3.ZERO
var _clock := 0.0
var craft: Node              # 工房の配り役（craft.gd）。仲間も帯にランタンを提げ、暗くなると点ける
var _lamp_t := 0.0           # ランタンを点けるか見直すまで (s)
var lounge := false          # ロッジでくつろぐ仲間（ソリは押さない）
var seats: Node              # ロッジの席の配り役（seats.gd）
var seat_i := -1             # 座っている席の番号
var _sit_frame := -1
var _stand_frame := -1
var _sit_from := Vector3.ZERO
var _sit_stage := 0
var _goal := -1              # 歩いて向かっている席
var _left := -1              # さっき立った席（すぐには戻らない）
var _rest := 0.0             # 座っている残り (s)。立っているときは、次の席を選ぶまで
var _stuck := 0.0            # 歩いても進まない時間 (s)
var _near_was := false       # あなたが近くの席に座っていた
const REST := Vector2(25.0, 60.0)   # 一つの席に座っている長さ (s)
const NEAR_SEAT := 4.0       # あなたの席からこの中の席なら「そば」(m)
const HEARTH_SEATS := ["sofa", "rocker", "beanbag"]   # 暖炉のまわりの席（hearth_nook.gd）
const HEARTH_LIKE := 0.7     # 次の席を選ぶとき、暖炉のまわりから選ぶ割合


func _ready() -> void:
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	_col.shape = cap
	_col.position.y = 0.85
	add_child(_col)

	doll = Doll.new()
	doll.kind = doll_kind if doll_kind in Doll.KINDS else ("origami" if side > 0 else "news")
	add_child(doll)

	hub = get_parent().get_node_or_null("Emotes")
	if hub:
		id = hub.join(self)
		hub.happened.connect(_on_emote)
	craft = get_parent().get_node_or_null("Craft")
	if craft and id >= 0:
		craft.join(id)
		_fill_wallet()
		craft.happened.connect(_on_craft)
		craft.send({"kind": "doll", "who": id, "doll": doll.kind})   # いまの人形をみんなに知らせる
	seats = get_parent().get_node_or_null("Seats")
	if seats:
		seats.happened.connect(_on_seat)


## 人形を替える出来事（通信では、ほかの人が衣装掛けで選んだ人形がここに届く）。人形を作り直す。
## 服を染めた出来事（dye・outfit）では、いまの人形ならその色に染め直す（作り直さない）
func _on_craft(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	if ev.kind in ["dye", "outfit"] and String(ev.doll) == doll.kind:
		doll.dress(craft.outfit_of(id, doll.kind))
		return
	if ev.kind != "doll" or doll.kind == ev.doll:
		return
	var at := doll.global_transform
	doll.queue_free()
	doll = Doll.new()
	doll.kind = String(ev.doll)
	doll.outfit = craft.outfit_of(id, doll.kind)
	add_child(doll)
	doll.global_transform = at


## 暗くなったらランタンを点け、明るくなったら消す（あなたと同じ lamp の出来事。見直すたびに少しずつ間をずらす）
func _mind_lamp(dt: float) -> void:
	_lamp_t -= dt
	if craft == null or id < 0 or _lamp_t > 0.0:
		return
	_lamp_t = randf_range(1.5, 4.0)
	var dc := get_node_or_null("/root/DayCycle")
	if dc == null or not dc.has_method("daylight"):
		return
	var light: float = dc.daylight()
	var on: bool = craft.lamp_on(id)
	if (light < 0.4 and not on) or (light > 0.6 and on):
		craft.send({"kind": "lamp", "who": id, "on": not on})


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


## 紙の体の湿り気（damp.gd）の倍率: push なら押す力、そうでなければ歩く速さ（player.gd と同じ）
func damp_k(push: bool) -> float:
	var dm := get_parent().get_node_or_null("Damp")
	if dm == null or id < 0:
		return 1.0
	return dm.push_k(id) if push else dm.speed_k(id)


func _physics_process(dt: float) -> void:
	_update_replies(dt)
	_mind_lamp(dt)
	_regrab = maxf(0.0, _regrab - dt)
	if lounge:
		_lounge(dt)
		return
	if post != null:
		_stand_at_post(dt)
		return
	if _duel_step(dt):
		return
	var s := sled.global_position
	var to_top := Vector2(s.x, s.z).length()
	_watch_offer()
	if state != State.RIDE and (_five_with > 0 or _rooted()):
		_go_five(dt)
		return

	if state == State.RIDE:
		global_position = sled.to_global(seat)
		_pose_doll()
		# あなたがいないときは、仲間が体重をかけて滑り出す
		if player == null and to_top < 8.0:
			sled.lean(0.0, true)
		_follow_lean(dt)
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
			# ソリの軸に沿って押しながら、向きを頂上へ向け直す。
			# 大きくずれているときは進める力をかけず、まず向きを直す（縁を横に押して回す）
			var fwd: Vector3 = -sled.global_basis.z
			fwd.y = 0
			fwd = fwd.normalized()
			var err := atan2(fwd.cross(up).y, fwd.dot(up))
			# ソリの軸に沿って押し、縁を横に押して向きを頂上へ向け直す。
			# 60° 以上ずれているときは進めず、その場で向きを直す（止まったソリは静止摩擦で留まる）。
			# 回りすぎないよう、いま回っている速さの分は弱める
			var steer: float = clamp(err * 2.5 - sled.angular_velocity.y * 0.5, -1.0, 1.0)
			var ahead: float = max(0.0, cos(err)) if abs(err) < deg_to_rad(60.0) else 0.0
			var push_dir: Vector3 = fwd * ahead + sled.global_basis.x * steer * 1.2
			if push_dir.length() > 0.05 and not sled.is_dragged(self):
				sled.push(push_dir.normalized(), global_position + fwd * 0.6 + Vector3.UP * 0.4, self, damp_k(true))
			debug = "err=%.0f° steer=%.2f ahead=%.2f 手=%s" % [rad_to_deg(err), steer, ahead, str(sled.to_local(global_position + fwd * 0.6 + Vector3.UP * 0.4).snapped(Vector3(0.1, 0.1, 0.1)))]
			var face := s - global_position
			face.y = 0
			if face.length() > 0.1:
				look_at(global_position + face, Vector3.UP)
			_pose_doll()
			return
		else:
			# 持ち場はソリの横の縁の後ろの角。いま自分がいる側を選び、他の仲間が持っていれば反対側。
			# 後ろの真ん中はあなたの分
			var lp0: Vector3 = sled.to_local(global_position)
			var want: float = signf(lp0.x) if abs(lp0.x) > 0.05 else float(side)
			if _post_taken(want):
				want = -want
			var stand_l := Vector3((sled.HALF.x + sled.STAND) * want, 0, 1.4)   # 後ろの角のつかみ所
			var post: Vector3 = sled.to_global(stand_l)
			var to := post - global_position
			to.y = 0
			# ソリに突き当たらない経路: 反対側の持ち場へは、自分側の後ろの角 → 後ろの通路 → 持ち場、と回る
			var lp: Vector3 = sled.to_local(global_position)
			var lpost: Vector3 = sled.to_local(post)
			var hx: float = sled.HALF.x
			var hz: float = sled.HALF.y
			var sx := signf(lp.x) if abs(lp.x) > 0.05 else float(side)
			var lane := hz + 0.9
			var outside := hx + 0.7
			var target_l: Vector3
			if lp.z >= lane:
				target_l = Vector3(lpost.x, 0, hz + 1.1) if abs(lp.x - lpost.x) > 0.3 else lpost
			elif signf(lp.x) == signf(lpost.x) and abs(lp.x) >= outside:
				target_l = lpost
			elif abs(lp.x) < outside:
				target_l = Vector3(sx * (hx + 1.1), 0, lp.z)       # まず横へ出る
			else:
				target_l = Vector3(sx * (hx + 1.1), 0, hz + 1.1)   # 自分側の後ろの角へ
			to = sled.to_global(target_l) - global_position
			to.y = 0
			dir = _round_player(to.normalized()) if to.length() > 0.2 else up
			debug = "持ち場まで%.2f" % (post - global_position).length()
			# あなたが持ち場のそばに立っていて寄れなければ、少し遠くからつかむ
			if (post - global_position).length() < (1.4 if _player_within(1.0) else 0.8) and _regrab <= 0.0:
				if sled.take_handle(self, stand_l):
					handle = stand_l
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

	velocity.x = dir.x * SPEED * damp_k(false)
	velocity.z = dir.z * SPEED * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if dir.length() > 0.1:
		look_at(global_position + dir, Vector3.UP)
	_pose_doll()


## 通り道にあなたが立っていれば、ソリから離れる側へ回る（握手のあとは、あなたの正面にいるので、ソリがあなたの向こうだと突き当たって止まる）
func _round_player(dir: Vector3) -> Vector3:
	if not _player_within(1.3):
		_rounding = false
		return dir
	var gap := Emotes._flat(player.global_position - global_position)
	if dir.dot(gap.normalized()) <= 0.5:
		return dir
	if not _rounding:   # 回る向きは、回り終えるまで変えない（左右に振れて進めなくなる）
		_rounding = true
		var away := Emotes._flat(global_position - sled.global_position)
		_turn_sign = 1.0 if dir.rotated(Vector3.UP, 1.2).dot(away) > dir.rotated(Vector3.UP, -1.2).dot(away) else -1.0
	return dir.rotated(Vector3.UP, 1.2 * _turn_sign)


var _rounding := false       # あなたのまわりを回っている途中


func _player_within(m: float) -> bool:
	return player != null and Emotes._flat(player.global_position - global_position).length() < m


## 一緒に乗っているあなたの体重移動に、少し遅れて合わせる
func _follow_lean(dt: float) -> void:
	_clock += dt
	var riding_with: bool = player != null and player.get("mode") == player.Mode.RIDE and player.sled == sled
	if lean_mode != "follow" or not riding_with:
		_lean_q.clear()
		_lean_now = Vector3.ZERO
		return
	_lean_q.append([_clock, player.ride_lean])
	while not _lean_q.is_empty() and _clock - _lean_q[0][0] >= LEAN_DELAY:
		_lean_now = _lean_q.pop_front()[1]
	if _lean_now != Vector3.ZERO:
		sled.lean(_lean_now.x, _lean_now.y > 0.0, _lean_now.z > 0.0)


## 持ち場へ歩いて行って立ち、見る先を向く（ミシンの足踏み。sewing_machine.gd が呼ぶ）
func _stand_at_post(dt: float) -> void:
	var to := post.global_position - global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.15 else Vector3.ZERO
	velocity.x = dir.x * SPEED * damp_k(false)
	velocity.z = dir.z * SPEED * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	var face := dir
	if dir == Vector3.ZERO and post_look != Vector3.INF:
		face = post_look - global_position
		face.y = 0
	if face.length() > 0.1:
		look_at(global_position + face, Vector3.UP)
	doll.act = Doll.Act.WALK
	doll.sled = sled
	doll.grip = Vector3.INF
	doll.effort = false
	doll.airborne = false
	doll.gaze = post_look


## その側の後ろの持ち場を、他の仲間がすでにつかんでいるか
func _post_taken(side_sign: float) -> bool:
	for who in sled.holders:
		if who == self:
			continue
		var h: Vector3 = sled.holders[who]
		if h.z > 0.5 and signf(h.x) == side_sign and abs(h.x) > 0.9:
			return true
	return false


## 人形に、いまの動きを伝える（姿勢は人形が 12 コマで刻む）
func _pose_doll() -> void:
	if state == State.RIDE:
		doll.act = Doll.Act.RIDE
	elif handle != Vector3.INF:
		doll.act = Doll.Act.PUSH
	else:
		doll.act = Doll.Act.WALK
	doll.sled = sled
	if hub:
		doll.holding_ball = hub.balls_of(id) > 0 and hub.can_throw(id)   # 持っている雪玉（右手に 1 つ、残りは袖。player.gd と同じ）
		doll.sleeve_balls = hub.balls_of(id) - (1 if doll.holding_ball else 0)
	doll.lean = Vector2(_lean_now.x, _lean_now.y - _lean_now.z) if state == State.RIDE else Vector2.ZERO
	if craft:
		doll.lantern = craft.lantern(id).get("look", "")
		doll.lantern_lit = craft.lamp_on(id)
	doll.grip = handle
	doll.effort = handle != Vector3.INF and sled.pushers > 0
	doll.dragged = handle != Vector3.INF and sled.is_dragged(self)
	doll.airborne = not is_on_floor() and state != State.RIDE and handle == Vector3.INF
	# 顔の向き: あなたが指さしたら、指された所を一緒に見る。押していないときは、近くのあなたの顔を見る
	doll.gaze = Vector3.INF
	doll.waving = _wave_t > 0.0
	if player and _look_t > 0.0:
		doll.gaze = player.global_position + Vector3.UP * 1.25   # 呼ばれた人のほうを見る
	elif player:
		var hub = get_parent().get_node_or_null("Emotes")   # あなたが指している所（配られた向きから。通信でも同じ）
		var pt: Vector3 = hub.point_of(int(player.get("id"))) if hub and player.get("id") != null else player.point_at
		if pt != Vector3.INF:
			doll.gaze = pt
		elif handle == Vector3.INF and global_position.distance_to(player.global_position) < 8.0:
			doll.gaze = player.global_position + Vector3.UP * 1.25


# ---------------------------------------------------------------- 身ぶりへの返し

var _shape := ""             # 仲間がいま掲げている手（Palm.HANDS の名前）
var _five_shape := ""        # 合わせにいく手（"high_R" "low_both" など）
var _lower_t := 0.0          # 返しで掲げた形を下ろすまで (s)
var _look_t := 0.0           # 呼ばれて、あなたのほうを見ているあいだ (s)
var _wave_t := 0.0           # 呼ばれて、手を振っているあいだ (s)


func _on_emote(ev: Dictionary) -> void:
	var who: int = ev.get("who", -1)
	if who == id:
		if ev.kind == "hands":
			_shape = ev.hands
			doll.play(ev)
			return
		_em = ev
		doll.play(ev)
		if ev.kind in ["high_five", "shake", "whiff"]:
			_five_with = -1   # 合った・空振りした。持ち場へ戻る
		if ev.kind == "hit" and handle != Vector3.INF:
			let_go()   # びっくりして手を離す
			_regrab = REGRAB_WAIT
		if ev.kind == "hit":
			_wind = -1.0   # 振りかぶっていても、のけぞって投げられない
		if ev.kind == "hit" and randf() < 0.6:
			_reply(randf_range(0.7, 1.0), {"kind": "wa"})   # 当たっても楽しい
		return
	if ev.kind == "throw":
		_saw_throw(ev)
	# 返すのは、あなた（人）の身ぶりにだけ（仲間どうしで返し合い続けないように）
	if player == null or hub.who_of(who) != player:
		return
	var near := global_position.distance_to(player.global_position)
	match ev.kind:
		"wa", "un", "nn":
			if near < 15.0 and not ev.get("auto", false):
				_reply(randf_range(0.35, 0.8), {"kind": ev.kind})
		"huh":
			if near < 15.0:
				_reply(randf_range(0.4, 0.8), {"kind": "un"})   # たずねられたら、ウンとうなずく
		"oi":
			# 呼ばれたら、そちらを見て、おーいと返すか、手を振る（遠くても届く）
			if near < 100.0:
				_look_t = 3.0
				if randf() < 0.5 or handle != Vector3.INF:
					_reply(randf_range(0.7, 1.1), {"kind": "oi"})
				else:
					_wave_t = 2.5
		"clap":
			if near < 10.0:
				_reply(randf_range(0.15, 0.3), {"kind": "hands", "hands": "high_both"})
				_reply(randf_range(0.4, 0.6), {"kind": "clap"})
				_lower_t = 2.2
		"hands":
			var h: String = ev.hands
			if h == "":
				if _five_with == who:
					_five_with = -1
				return
			var parts := h.split("_")
			var both := parts[1] == "both"
			if h == "high_both" and state == State.RIDE and player.get("mode") == player.Mode.RIDE:
				_reply(randf_range(0.1, 0.25), {"kind": "hands", "hands": "high_both"})   # 一緒に乗っていれば、一緒に万歳
				_reply(randf_range(0.35, 0.5), {"kind": "wa"})
				_lower_t = 3.0
			elif near < 7.0 and state != State.RIDE and not lounge and _offered_to_me(parts[0], who):
				# 手のひらを差し出された: 前まで行って、同じ高さで掲げる（片手か両手かもまねる。片手なら右手）
				_five_with = who
				_five_shape = Palm.hands_name(parts[0], "both" if both else "R")
				_five_until = Doll.frame_index() + 12 * 8
				_five_sent = false
				_five_ball = _wants_ball(parts[0], who)


func _reply(after: float, ev: Dictionary) -> void:
	_replies.append([after, ev])


func _update_replies(dt: float) -> void:
	for r in _replies.duplicate():
		r[0] -= dt
		if r[0] <= 0.0:
			_replies.erase(r)
			var ev: Dictionary = r[1].duplicate()
			ev["who"] = id
			hub.send(ev)
	_look_t = maxf(0.0, _look_t - dt)
	_wave_t = maxf(0.0, _wave_t - dt)
	if _lower_t > 0.0:
		_lower_t -= dt
		if _lower_t <= 0.0 and _shape != "" and _five_with < 0:
			hub.send({"kind": "hands", "who": id, "hands": ""})


func _rooted() -> bool:
	if _em.is_empty():
		return false
	var spec: Dictionary = Emotes.KINDS.get(_em.kind, {})
	return spec.get("root", false) and Doll.frame_index() - int(_em.frame) < spec.frames


## 手のひら（グー）を掲げた相手の前まで歩き、向き合って同じ形を掲げる（届けば配り役が合わせる）
func _go_five(dt: float) -> void:
	var dir := Vector3.ZERO
	var them := hub.who_of(_five_with)
	if _five_with > 0 and (them == null or Doll.frame_index() > _five_until):
		_five_with = -1
		if _shape != "":
			hub.send({"kind": "hands", "who": id, "hands": ""})
	elif _five_with > 0:
		let_go()
		var fwd: Vector3 = Emotes._forward(them)
		# 握手は手のひらをくっつけるので、ハイタッチより近くまで行く
		var spot: Vector3 = them.global_position + fwd * (0.7 if _five_shape.begins_with("low") else 0.95)
		var to := spot - global_position
		to.y = 0
		var face: Vector3 = them.global_position - global_position
		face.y = 0
		if _five_ball and hub.balls_of(id) < 1 and not _rooted():
			hub.send({"kind": "make_ball", "who": id})   # 対決に応じる: まず雪玉を丸める
		_five_ball = _five_ball and (hub.balls_of(id) < 1 or _rooted())
		if to.length() > 0.15 and not _five_ball:
			dir = to.normalized()
		if face.length() > 0.1:
			look_at(global_position + face, Vector3.UP)
		if not _five_ball and not _five_sent and to.length() < 0.6 and Emotes._forward(self).dot(face.normalized()) > 0.6:
			hub.send({"kind": "hands", "who": id, "hands": _five_shape})
			_five_sent = true
	velocity.x = dir.x * SPEED * damp_k(false)
	velocity.z = dir.z * SPEED * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	_pose_doll()


# ---------------------------------------------------------------- 雪合戦の対決（duel.gd）

const DUEL_BUTTONS := 50     # 財布にいつも持っている分（木の何個分。金色の真鍮のボタン 5 枚）。2026-11-05 代表「CPUは金5枚持っていてほしいです」
const BET_WAIT := 4.0        # 掛金がこれだけ変わらなければ受ける (s)。あなたが額を選び終えるのを待つ
const START_WAIT := 1.5      # 戦いが始まってから、最初に投げるまで (s)
const THROW_EVERY := Vector2(0.0, 1.2)   # 投げられるようになってから（duel.gd の THROW_GAP）、次に振りかぶるまで (s)
const WINDUP_T := 0.4        # 投げる前に振りかぶる長さ (s)。あなたが見てからよけられるように
const THROW_SPREAD := 2.4    # 投げる速さのずれ (m/s)。大きいほど外れる
const CATCH_ODDS := 0.2      # あなたの雪玉を取りにいく割合
const DODGE_ODDS := 0.35     # あなたの雪玉をよける割合（残りは、そのまま受ける）
const DODGE_T := 0.5         # 横へよける長さ (s)
const REACT_T := Vector2(0.1, 0.25)   # 投げられてから動き出すまで (s)

var _duel_t := 0.0           # 次に投げる・受けるまで (s)
var _duel_stake := -1        # 見ていた掛金（変わったら、少し待ってから受ける）
var _orbit := 0.0            # 円のまんなかのまわりを回る角
var _orbit_dir := 1.0
var _wind := -1.0            # 振りかぶっている残り (s)。負なら振りかぶっていない
var _catching := -1          # 取りにいく雪玉の番号
var _dodge := Vector3.ZERO   # よける向き
var _dodge_wait := 0.0       # よけ始めるまで (s)
var _dodge_t := 0.0          # よける残り (s)
var _five_ball := false      # 握手しに行く前に、雪玉を作る（対決に応じる）


## 雪玉を持って低い手のひらを差し出すのは、対決の申し込み: 見ている相手にだけ応じる（仲間が何人いても、見て選べる）
func _offered_to_me(height: String, who: int) -> bool:
	if height != "low" or hub.balls_of(who) < 1:
		return true
	var them: Node3D = hub.who_of(who)
	return Emotes._flat(-them.global_basis.z).normalized().dot(Emotes._flat(global_position - them.global_position).normalized()) > 0.8


## 雪玉を持って低い手のひらを掲げたまま、こちらを見ている人（あとから近づいた・あとから向いた）にも応じる
func _watch_offer() -> void:
	if _five_with > 0 or player == null or state == State.RIDE or int(player.get("id")) < 0:
		return
	var who: int = player.id
	var h: String = hub.hands.get(who, "")
	var duel := get_parent().get_node_or_null("Duel")
	if not h.begins_with("low") or hub.balls_of(who) < 1 or duel == null or not duel.of(id).is_empty():
		return
	if global_position.distance_to(player.global_position) < 7.0 and _offered_to_me("low", who):
		_five_with = who
		_five_shape = Palm.hands_name("low", "both" if h.ends_with("both") else "R")
		_five_until = Doll.frame_index() + 12 * 8
		_five_sent = false
		_five_ball = _wants_ball("low", who)


## 低い手のひらを差し出した人が雪玉を持っていて、自分は持っていない: 握手で対決が始まるように作る（ロッジの床では始まらないので作らない）
func _wants_ball(height: String, who: int) -> bool:
	var duel := get_parent().get_node_or_null("Duel")
	var w := get_parent()
	return height == "low" and duel != null and duel.of(id).is_empty() and hub.balls_of(who) > 0 and hub.balls_of(id) < 1 \
		and w.lodge_weight(global_position.x, global_position.z) >= 1.0


## 対決の相手が投げた: 取りにいくか、よけるか、そのまま受けるかを 1 球に 1 度決める
func _saw_throw(ev: Dictionary) -> void:
	var duel := get_parent().get_node_or_null("Duel")
	if duel == null:
		return
	var d: Dictionary = duel.fighting(id)
	if d.is_empty() or duel.opponent(d, id) != int(ev.who):
		return
	var roll := randf()
	if roll < CATCH_ODDS:
		_catching = int(ev.get("ball", -1))
	elif roll < CATCH_ODDS + DODGE_ODDS:
		var v: Vector3 = ev.velocity
		v.y = 0
		_dodge = v.cross(Vector3.UP).normalized()
		var at: Vector3 = d.at
		if _dodge.dot(at - global_position) < 0.0:
			_dodge = -_dodge   # 円のまんなかの側へ（縁に追いつめられない）
		_dodge_wait = randf_range(REACT_T.x, REACT_T.y)
		_dodge_t = DODGE_T


## 取りにいく雪玉が手の届く所に来たら取る（取れたかはホストが決める）
func _try_catch(duel: Node) -> void:
	if _catching < 0:
		return
	if not duel.reach_for(self, _catching):
		_catching = -1


## 財布が DUEL_BUTTONS より少なければ、そこまで足す（多いぶんは持ったまま）。はじめと、握手で掛金の画面に入るとき
func _fill_wallet() -> void:
	var lack: int = DUEL_BUTTONS - craft.wallet(id)
	if lack > 0:
		craft.send({"kind": "earn", "who": id, "n": lack})


## 対決にかかわっているあいだの動き。動かしたら true（ふだんの動きはしない）
func _duel_step(dt: float) -> bool:
	var duel := get_parent().get_node_or_null("Duel")
	if duel == null:
		return false
	var d: Dictionary = duel.of(id)
	if d.is_empty():
		_duel_stake = -1
		return false
	var them: Node3D = hub.who_of(duel.opponent(d, id))
	_duel_t -= dt
	match String(d.phase):
		"bet":
			if _duel_stake < 0:   # 掛金の画面に入ったところ（前の対決で減った分は、ここで戻る）
				_fill_wallet()
			if int(d.stake) != _duel_stake:
				_duel_stake = int(d.stake)
				_duel_t = BET_WAIT
			var ok: bool = d.ok_a if id == int(d.a) else d.ok_b
			if not ok and _duel_t <= 0.0:
				_duel_t = BET_WAIT
				duel.send({"kind": "ok", "who": id})
			_duel_move(Vector3.ZERO, them, dt)
			return true
		"fight":
			if _duel_stake >= 0:   # 始まったところ
				_duel_stake = -1
				_duel_t = START_WAIT
				_wind = -1.0
				_catching = -1
				_dodge_t = 0.0
			let_go()
			_duel_fight(d, them, dt, duel)
			return true
		"over":
			if _wind >= 0.0 and them:   # 振りかぶっていた分は投げてしまう（腕が上がったままにならない。もう数えない）
				_wind = -1.0
				_duel_throw(them)
			# 払いの握手をしにいく（相手の前で低い手のひら）
			if them and _five_with < 0 and _shape == "":
				_five_with = duel.opponent(d, id)
				_five_shape = "low_R"
				_five_ball = false
				_five_until = Doll.frame_index() + 12 * 25
				_five_sent = false
	return false


func _duel_fight(d: Dictionary, them: Node3D, dt: float, duel: Node) -> void:
	if them == null:
		_duel_move(Vector3.ZERO, null, dt)
		return
	var at: Vector3 = d.at
	if randf() < dt * 0.25:
		_orbit_dir = -_orbit_dir   # ときどき向きを変える
	_orbit += dt * 0.32 * _orbit_dir
	var goal := at + Vector3(cos(_orbit), 0, sin(_orbit)) * 3.2
	var to := goal - global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.3 else Vector3.ZERO
	_try_catch(duel)
	_dodge_wait -= dt
	if _dodge_t > 0.0 and _dodge_wait <= 0.0:
		_dodge_t -= dt
		dir = _dodge
	if _rooted():
		dir = Vector3.ZERO
	elif hub.balls_of(id) <= 0:
		hub.send({"kind": "make_ball", "who": id})   # なくなったら、しゃがんで作る
		dir = Vector3.ZERO
		_wind = -1.0
	elif _wind >= 0.0:
		_wind -= dt
		if _wind < 0.0:
			_duel_throw(them)
			_duel_t = duel.THROW_GAP + randf_range(THROW_EVERY.x, THROW_EVERY.y)
	elif _duel_t <= 0.0 and duel.can_throw(id):
		_duel_t = randf_range(THROW_EVERY.x, THROW_EVERY.y) + 1.0   # のけぞって投げられなかったら、また少し待つ
		_wind = WINDUP_T
		hub.send({"kind": "windup", "who": id})
	_duel_move(dir, them, dt)
	duel.keep_in(self, id)


## 相手の胸へ、山なりに投げる（少しずらす。立っている相手に半分ほど当たる。動いている先は読まないので、歩いていればよけられる）
func _duel_throw(them: Node3D) -> void:
	var fwd := Emotes._forward(self)
	var origin := global_position + Vector3.UP * doll.height() * 0.85 + fwd * 0.4
	var h: float = them.doll.height() if them.get("doll") else 1.6
	var target: Vector3 = them.global_position + Vector3.UP * h * 0.6
	var flat: Vector3 = target - origin
	flat.y = 0
	var vh := 10.0
	var t := maxf(flat.length() / vh, 0.1)
	var vy: float = (target.y - origin.y + 0.5 * 9.8 * t * t) / t
	var vel: Vector3 = flat.normalized() * vh + Vector3.UP * vy
	vel += Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * THROW_SPREAD
	hub.send({"kind": "throw", "who": id, "origin": origin, "velocity": vel})


func _duel_move(dir: Vector3, them: Node3D, dt: float) -> void:
	if them:
		var face: Vector3 = them.global_position - global_position
		face.y = 0
		if face.length() > 0.1:
			look_at(global_position + face, Vector3.UP)
	velocity.x = dir.x * SPEED * damp_k(false)
	velocity.z = dir.z * SPEED * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	_pose_doll()


# ---------------------------------------------------------------- ロッジでくつろぐ

func _on_seat(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	match ev.kind:
		"sit":
			seat_i = int(ev.seat)
			_sit_frame = int(ev.frame)
			_stand_frame = -1
			_sit_from = global_position
			_sit_stage = 0
			_col.disabled = true
			velocity = Vector3.ZERO
			_goal = -1
			_rest = randf_range(REST.x, REST.y)
		"stand":
			_stand_frame = int(ev.frame)
			_left = seat_i


## あなたが座っている席（座っていなければ空）
func _player_seat() -> Dictionary:
	if player == null or seats == null or int(player.get("seat_i")) < 0:
		return {}
	return seats.seat(int(player.seat_i))


func _lounge(dt: float) -> void:
	if seats == null or seats.seats.is_empty():
		_pose_lounge()
		return
	var mine: Dictionary = _player_seat()
	if seat_i >= 0:
		var st: Dictionary = seats.seat(seat_i)
		var pl: Array = Seats.place(st, _sit_from, Doll.frame_index(), _sit_frame, _stand_frame)
		_sit_stage = pl[1]
		if pl[2]:
			seat_i = -1
			_sit_stage = 0
			_col.disabled = false
			global_position = pl[0] + Vector3.UP * 0.05
			_rest = randf_range(0.5, 2.0)
		else:
			global_position = pl[0]
			# あなたが近くに座ったら、長く座っている。遠くに座ったら、少しして寄っていく
			var near: bool = not mine.is_empty() and (mine.pos as Vector3).distance_to(st.pos) < NEAR_SEAT
			if not mine.is_empty() and not near and not _near_was:
				_rest = minf(_rest, randf_range(2.0, 6.0))
			_near_was = not mine.is_empty()
			_rest -= dt
			if _rest <= 0.0 and _stand_frame < 0 and _sit_stage == 2:
				if near:
					_rest = randf_range(REST.x, REST.y)
				else:
					seats.send({"kind": "stand", "who": id, "seat": seat_i})
		_pose_lounge()
		return
	# 立っている: 次の席を選んで歩いて行く
	if _goal < 0:
		_rest -= dt
		if _rest > 0.0:
			_pose_lounge()
			return
		_goal = _pick_seat(mine)
		_near_d = INF
		_near_t = 0.0
		_via = []
		if _goal >= 0 and seats.seat(_goal).kind in HEARTH_SEATS:
			var st: Dictionary = seats.seat(_goal)
			var d: Vector3 = st.stand - global_position
			d.y = 0
			var nook = seats.lodge.find_child("HearthNook", true, false) if seats.lodge else null
			if nook and test_move(global_transform, d):   # まっすぐ行けなければ、入り口を通る
				_via = nook.route(global_position, st.stand)
		_stuck = 0.0
		if _goal < 0:
			_rest = 2.0
			_pose_lounge()
			return
		if not _started:
			# 始まり: 選んだ席のそばから、すぐ座る
			_started = true
			global_position = seats.seat(_goal).stand + Vector3.UP * 0.05
	var goal: Dictionary = seats.seat(_goal)
	if seats.taken.has(_goal):
		_goal = -1   # 先に座られた
		_pose_lounge()
		return
	var to: Vector3 = goal.stand - global_position
	to.y = 0
	if not _via.is_empty():   # 暖炉の居場所の入り口を通って回り込む途中（hearth_nook.gd の route）
		var w: Vector3 = _via[0] - global_position
		w.y = 0
		if w.length() < 0.5:
			_via.pop_front()
			_near_d = INF
		else:
			to = w
	if to.length() < 0.3 and _via.is_empty():
		if not seats.send({"kind": "sit", "who": id, "seat": _goal}):
			_goal = -1
		_pose_lounge()
		return
	var dir := _detour(to.normalized())
	var before := global_position
	velocity.x = dir.x * SPEED * 0.7 * damp_k(false)
	velocity.z = dir.z * SPEED * 0.7 * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	look_at(global_position + dir, Vector3.UP)
	# 机などに当たって進めなければ、別の席にする
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_stuck = _stuck + dt if moved < SPEED * 0.2 * dt else maxf(0.0, _stuck - dt)
	# 家具のあいだで左右に振れて近づけないときも（動いてはいる）、4 秒で 0.5 m 近づけなければ別の席にする
	_near_t += dt
	if to.length() < _near_d - 0.5:
		_near_d = to.length()
		_near_t = 0.0
	if _near_t > 4.0:
		_stuck = 2.0
	if _stuck > 1.5:
		_near_d = INF
		_near_t = 0.0
		_left = _goal
		_goal = -1
	_pose_lounge()


var _started := false
var _via := []               # 席へ行く前に通る所（世界）
var _near_d := INF           # 行き先の席の立つ所に、いちばん近づいた距離
var _near_t := 0.0           # そこから近づけないでいる秒
var _turn_sign := 1.0        # 机をよけて回り込む向き（ふさがれているあいだは同じ向きへ回り続ける）


## 行きたい向き want の前がふさがっていれば（机など）、少しずつ向きを振って通れる向きを選ぶ。
## 前に選んだ回り込みの向きを先に試すので、机の縁に沿って端まで回り込める
func _detour(want: Vector3) -> Vector3:
	if not test_move(global_transform, want * 0.35):
		return want
	for a in [0.6, 1.1, 1.6, 2.2]:
		for sg in [_turn_sign, -_turn_sign]:
			var d := want.rotated(Vector3.UP, a * sg)
			if not test_move(global_transform, d * 0.35):
				_turn_sign = sg
				return d
	return want


## 次に座る席: あなたが座っていれば、そのそばの空いた席。でなければ、近くの空いた席から気まぐれに
func _pick_seat(mine: Dictionary) -> int:
	var list: Array = []
	if not mine.is_empty():
		list = seats.free_near(mine.stand, 4, NEAR_SEAT).filter(func(i): return i != _left)
	if list.is_empty() and randf() < HEARTH_LIKE:   # 暖炉のまわりの家具（ソファ・揺り椅子・ビーズクッション）が好き
		list = seats.free_near(global_position, 8, 40.0, HEARTH_SEATS).filter(func(i): return i != _left)
	if list.is_empty():
		list = seats.free_near(global_position, 8, 14.0).filter(func(i): return i != _left and seats.seat(i).kind != "zabuton")
	return list[randi() % list.size()] if not list.is_empty() else -1


func _pose_lounge() -> void:
	_pose_doll()
	doll.airborne = false
	doll.facing = Vector3.ZERO
	doll.seat_soft = seat_i >= 0 and seats.seat(seat_i).kind == "zabuton"
	doll.rock_axis = Vector3.ZERO
	if seat_i >= 0:
		var st: Dictionary = seats.seat(seat_i)
		doll.act = Doll.Act.SIT
		doll.facing = st.face
		doll.sit_stage = _sit_stage
		doll.seat_drop = st.pos.y - st.floor
		doll.seat_edge = st.edge
		if st.has("rock_axis"):   # 揺り椅子・ビーズクッション: 体ごと傾く
			doll.rock_axis = st.rock_axis
			doll.rock_at = st.rock_at
			doll.rock_roll = float(st.get("rock_roll", 0.0))
			doll.rock = Seats.rock_of(st, Doll.frame_index(), _sit_frame, _stand_frame)
