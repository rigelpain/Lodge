extends CharacterBody3D

const Doll := preload("res://doll.gd")
## 押すのを手伝う仲間（通信を入れるまでの代わり）。
## ソリの下り側に回って頂上へ押す → 頂上であなたが乗ったら一緒に乗る → 下で降りてまた押す。

enum State { PUSH, WAIT, RIDE }

const SPEED := 2.4
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
	if post != null:
		_stand_at_post(dt)
		return
	var s := sled.global_position
	var to_top := Vector2(s.x, s.z).length()

	if state == State.RIDE:
		global_position = sled.to_global(seat)
		_pose_doll()
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
			if push_dir.length() > 0.05:
				sled.push(push_dir.normalized(), global_position + fwd * 0.6 + Vector3.UP * 0.4)
			debug = "err=%.0f° steer=%.2f ahead=%.2f 手=%s" % [rad_to_deg(err), steer, ahead, str(sled.to_local(global_position + fwd * 0.6 + Vector3.UP * 0.4).snapped(Vector3(0.1, 0.1, 0.1)))]
			var face := s - global_position
			face.y = 0
			if face.length() > 0.1:
				look_at(global_position + face, Vector3.UP)
			if sled.linear_velocity.length() > 5.0:
				let_go()
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
			if (post - global_position).length() < 0.8:
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
	doll.grip = handle
	doll.effort = handle != Vector3.INF and sled.pushers > 0
	doll.airborne = not is_on_floor() and state != State.RIDE and handle == Vector3.INF
	# 顔の向き: あなたが指さしたら、指された所を一緒に見る。押していないときは、近くのあなたの顔を見る
	doll.gaze = Vector3.INF
	if player:
		var pt: Vector3 = player.point_at
		if pt != Vector3.INF:
			doll.gaze = pt
		elif handle == Vector3.INF and global_position.distance_to(player.global_position) < 8.0:
			doll.gaze = player.global_position + Vector3.UP * 1.25
