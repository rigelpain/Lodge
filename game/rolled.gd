extends RefCounted
## 転がる大玉に取り込まれる（2026-11-07 代表「転がる雪玉に轢かれたキャラクターは雪玉に取り込まれる（取り込まれたキャラは雪玉の三人称視点になる）
## ようにして、崩れたときか、暴れて雪玉を崩壊させるかで脱出できてほしい」）。大玉は big_ball.gd。
## 遊ぶ人（player.gd）と仲間（bot.gd）が 1 つずつ持つ。flung.gd と同じく、体を動かす画面が決める（人はその人の画面、仲間はホストの画面）。
##
## 当たる直前に見つけて、取り込まれる。体の当たりを切り、体は玉のまんなかについて行く。人形は、当たった所の玉の面に
## 背中から半分埋まり、玉と一緒に回りながら手足をばたつかせる（ほかの画面も、出来事 ball_in で覚えた所に同じく描く）。
## Space を連打すると玉が揺れ、回数が足りると崩れる（big_ball.gd の kick）。崩れると、玉の外へ放り出される（飛んだあとは flung.gd と同じ）

const BigBall := preload("res://big_ball.gd")

const RADIUS := 0.35         # 体の当たり（player.gd・bot.gd のカプセル）
const TALL := 1.7
const MIN_CLOSING := 2.0     # 玉が体へ向かって迫る速さの下限 (m/s)。一緒に歩いて押している・横をかすめるだけなら取り込まれない
const EMBED := 0.1           # 人形の背中を、玉の面からこれだけ内へ埋める (m)
const OUT_SPEED := Vector2(2.5, 9.0)   # 放り出される水平の速さ: 2.5 + 玉の速さ × 0.5 を、この範囲に (m/s)
const OUT_UP := Vector2(4.0, 7.5)      # 上向きの速さ: 4 + 玉の半径 を、この範囲に (m/s)
const BOT_KICK := Vector2(0.18, 0.4)   # 仲間が暴れる間隔 (s)

var body: CharacterBody3D
var ball: RigidBody3D        # 入っている大玉（いなければ null。崩れて消えたあとは、出てくるまで消えた玉を指している）
var _in := false             # 取り込まれている（消えた玉は null と同じに見えることがあるので、ball とは別に持つ）
var dir := Vector3.ZERO      # 取り込まれた所の向き（玉の座標）
var up := Vector3.ZERO       # 頭の向き（玉の座標）
var _last_c := Vector3.ZERO  # 玉のまんなか（玉が先に消えても、そこから放り出す）
var _last_v := Vector3.ZERO
var _last_r := 1.0
var _bot_t := 0.0


func _init(b: CharacterBody3D) -> void:
	body = b


func active() -> bool:
	return _in


## いま体に当たろうとしている大玉を探す。当たるなら {ball, dir, up} を返す（dir・up は玉の座標）
func find_hit() -> Dictionary:
	if active():
		return {}
	var dt := body.get_physics_process_delta_time()
	var me := body.global_position
	var my_v := body.velocity
	var bid := int(body.get("id"))
	for b in body.get_tree().get_nodes_in_group("big_balls"):
		if b.broken or b.r < BigBall.CATCH_R or b.inside.has(bid):
			continue
		var v: Vector3 = b.linear_velocity
		if v.length() < BigBall.CATCH_SPEED:
			continue
		var reach: float = b.r + RADIUS + 0.05
		var rel := v - my_v
		for i in 3:
			var c: Vector3 = b.global_position + rel * dt * i
			var y := clampf(c.y, me.y + RADIUS, me.y + TALL - RADIUS)
			var axis := Vector3(me.x, y, me.z)
			var off := axis - c
			if off.length() > reach:
				continue
			var n := off.normalized() if off.length() > 0.01 else -rel.normalized()
			if rel.dot(n) < MIN_CLOSING:
				break
			var bb: Basis = b.global_basis.orthonormalized()
			var t := Vector3.UP - n * n.dot(Vector3.UP)
			t = t.normalized() if t.length() > 0.05 else rel.normalized()
			return {"ball": b, "dir": bb.inverse() * n, "up": bb.inverse() * t}
	return {}


## 取り込まれる。まず手を離してから呼ぶ（let_go は持ち主がする）
func start(hit: Dictionary) -> void:
	ball = hit.ball
	_in = true
	dir = hit.dir
	up = hit.up
	_remember()
	var col = body.get("_col")
	if col:
		col.disabled = true
	body.velocity = Vector3.ZERO
	var hub = body.get("hub")
	if hub:
		hub.send({"kind": "ball_in", "who": body.get("id"), "ball": ball.ball_id, "dir": dir, "up": up,
				"point": ball.global_position + ball.global_basis * dir * ball.r})


func _remember() -> void:
	_last_c = ball.global_position
	_last_v = ball.linear_velocity
	_last_r = ball.r


## 1 コマ: 体は玉のまんなかについて行く（持ち主の _physics_process が、歩くかわりに呼ぶ）。玉が消えていたら放り出される
func step(_dt: float) -> void:
	if not is_instance_valid(ball) or ball.broken:
		out()
		return
	_remember()
	body.global_position = _last_c - Vector3.UP * TALL * 0.5
	body.velocity = _last_v


## Space: 中で暴れる
func kick() -> void:
	var hub = body.get("hub")
	if hub and active() and is_instance_valid(ball):
		hub.send({"kind": "ball_kick", "who": body.get("id"), "ball": ball.ball_id})


## 仲間は、ひとりでに暴れる（ホストの画面）
func bot_struggle(dt: float) -> void:
	_bot_t -= dt
	if _bot_t <= 0.0:
		_bot_t = randf_range(BOT_KICK.x, BOT_KICK.y)
		kick()


## 玉が崩れた: 玉の外へ放り出される（崩れた所から、取り込まれた面の向きへ、玉の進む向きを少し混ぜて）
func out() -> void:
	if not active():
		return
	var bb := Basis()
	if is_instance_valid(ball):
		_remember()
		bb = ball.global_basis.orthonormalized()
	ball = null
	_in = false
	var d = body.get("doll")
	if d:
		d.rolled = false
	var n := bb * dir
	var flat := Vector3(n.x, 0.0, n.z)
	if flat.length() < 0.2:
		flat = Vector3(_last_v.x, 0.0, _last_v.z)
	if flat.length() < 0.05:
		flat = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	flat = flat.normalized()
	var mv := Vector3(_last_v.x, 0.0, _last_v.z)
	var to := (flat * 0.7 + (mv.normalized() * 0.3 if mv.length() > 0.5 else Vector3.ZERO)).normalized()
	var w := body.get_parent()
	var at := _last_c + flat * _last_r * 0.6
	var g: float = w.height(at.x, at.z) if w.has_method("height") else at.y - _last_r
	at.y = maxf(_last_c.y - _last_r, g) + 0.15
	body.global_position = at
	body.reset_physics_interpolation()
	var col = body.get("_col")
	if col:
		col.disabled = false
	var fl = body.get("fling")
	if fl:
		fl.toss(to, clampf(2.5 + _last_v.length() * 0.5, OUT_SPEED.x, OUT_SPEED.y), clampf(4.0 + _last_r, OUT_UP.x, OUT_UP.y))


## 人形に、いまの様子を伝える（持ち主の _pose_doll と fling.pose のあとで）
func pose() -> void:
	var d = body.get("doll")
	d.rolled = active() and is_instance_valid(ball)
	if not d.rolled:
		return
	place(d, ball, dir, up)


## 人形を、玉の面に背中から半分埋めて置き、手足をばたつかせる（ほかの画面の remote_person.gd も使う）
static func place(d: Node3D, b: RigidBody3D, ldir: Vector3, lup: Vector3) -> void:
	d.rolled = true
	d.rolled_at = doll_xform(b, ldir, lup, d.height())
	d.flung = 1
	d.flung_spin = 0.0
	d.flung_dir = Vector3.ZERO
	d.airborne = true
	d.crouch = false


static func doll_xform(b: RigidBody3D, ldir: Vector3, lup: Vector3, h: float) -> Transform3D:
	var bb := b.global_basis.orthonormalized()
	var n := (bb * ldir).normalized()
	var t := bb * lup
	t = (t - n * n.dot(t)).normalized()
	var z := -n   # 人形の前（-Z）が玉の外を向く
	var x := t.cross(z).normalized()
	var y := z.cross(x)
	var center: Vector3 = b.global_position + n * maxf(float(b.r) - EMBED, float(b.r) * 0.5)
	return Transform3D(Basis(x, y, z), center - y * h * 0.5)


## 三人称のカメラが見る所（玉のまんなかの少し上）と、カメラの距離の下限
func cam_pivot() -> Vector3:
	return _last_c + Vector3.UP * _last_r * 0.3


func cam_min_dist() -> float:
	return _last_r * 2.2 + 2.5
