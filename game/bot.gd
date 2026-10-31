extends CharacterBody3D

const Doll := preload("res://doll.gd")
const Emotes := preload("res://emotes.gd")
const Palm := preload("res://palm.gd")
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

enum State { PUSH, WAIT, RIDE }

const SPEED := 2.4
const REGRAB_WAIT := 1.5     # 雪玉が当たって手を離してから、つかみ直すまで (s)
const LEAN_DELAY := 0.3      # 一緒に乗っているとき、あなたの体重移動に合わせるまでの遅れ (s)
const GRAVITY := 9.8

var sled: RigidBody3D
var player: Node3D          # いないとき（確かめ用）は仲間だけで滑る
var side := 1
var state := State.PUSH
var seat := Vector3.INF
var handle := Vector3.INF   # つかんでいる所（ソリの座標）
var doll: Doll               # 見た目の人形（右側の仲間は折り紙、左側は新聞紙）
var debug := ""
var post: Node3D = null      # 持ち場（ミシンの足踏みなど）。あればソリを押さず、そこに立って post_look を向く
var post_look := Vector3.INF
var _col: CollisionShape3D
var _still := 0.0
var _wait := 0.0
var hub: Emotes
var id := -1
var voice_pitch := 1.0
var voice_size := 1
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


func _ready() -> void:
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	_col.shape = cap
	_col.position.y = 0.85
	add_child(_col)

	doll = Doll.new()
	doll.kind = "origami" if side > 0 else "news"
	add_child(doll)
	# 声: 背の高い折り紙は低い声（03）、いちばん小さい新聞紙は高い声（02）。そこから少しだけずらす
	voice_size = 3 if side > 0 else 2
	voice_pitch = 0.97 if side > 0 else 1.04

	hub = get_parent().get_node_or_null("Emotes")
	if hub:
		id = hub.join(self)
		hub.happened.connect(_on_emote)
	craft = get_parent().get_node_or_null("Craft")
	if craft and id >= 0:
		craft.join(id)


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


func _physics_process(dt: float) -> void:
	_update_replies(dt)
	_mind_lamp(dt)
	_regrab = maxf(0.0, _regrab - dt)
	if post != null:
		_stand_at_post(dt)
		return
	var s := sled.global_position
	var to_top := Vector2(s.x, s.z).length()
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
				sled.push(push_dir.normalized(), global_position + fwd * 0.6 + Vector3.UP * 0.4, self)
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
			dir = to.normalized() if to.length() > 0.2 else up
			debug = "持ち場まで%.2f" % (post - global_position).length()
			if (post - global_position).length() < 0.8 and _regrab <= 0.0:
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

	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if dir.length() > 0.1:
		look_at(global_position + dir, Vector3.UP)
	_pose_doll()


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
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
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
		if ev.kind == "hit" and randf() < 0.6:
			_reply(randf_range(0.7, 1.0), {"kind": "wa"})   # 当たっても楽しい
		return
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
			elif near < 7.0 and state != State.RIDE:
				# 手のひらを差し出された: 前まで行って、同じ高さで掲げる（片手か両手かもまねる。片手なら右手）
				_five_with = who
				_five_shape = Palm.hands_name(parts[0], "both" if both else "R")
				_five_until = Doll.frame_index() + 12 * 8
				_five_sent = false


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
		if to.length() > 0.15:
			dir = to.normalized()
		if face.length() > 0.1:
			look_at(global_position + face, Vector3.UP)
		if not _five_sent and to.length() < 0.6 and Emotes._forward(self).dot(face.normalized()) > 0.6:
			hub.send({"kind": "hands", "who": id, "hands": _five_shape})
			_five_sent = true
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	_pose_doll()
