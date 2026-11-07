extends RefCounted
## ソリに轢かれて吹き飛ぶ（2026-11-07 代表「ソリで轢かれたときキャラクターが吹き飛んでほしい」）。
## 遊ぶ人（player.gd）と仲間（bot.gd）が 1 つずつ持つ。決まりと値の意味は design/controls-and-physics.md の「ソリに轢かれて吹き飛ぶ」。
##
## 体を動かす画面が決める（人の動きと同じ。人はその人の画面、仲間はホストの画面）。ほかの画面には、ふだんの姿（位置と人形の姿勢）で届く。
## 当たる直前に見つけて、そのソリとの当たりを切るので、ソリは体に止められずに走り抜ける（CharacterBody3D は押されないので、切らないと壁になる）。
## 吹き飛ばした分だけソリが遅くなるのは、出来事 "flung" でホストのソリだけに効かせる（slow_sled）。

enum { NONE, FLY, DOWN, RISE }   # 人形の flung と同じ番号

# ---- 吹き飛ぶ条件
const MIN_SPEED := 4.5      # これより遅いソリは吹き飛ばさない (m/s)。押して出せる速さ（sled.gd の PUSH_FADE で 4 m/s まで）より上
const MIN_CLOSING := 3.0    # ソリが体へ向かって迫る速さの下限 (m/s)。一緒に走っている・横をかすめるだけなら飛ばない
const MIN_OUT := 3.0        # 飛び出す速さがこれより遅ければ飛ばない (m/s)。空の米袋のような軽いソリは当たっても人を飛ばせない
# ---- 飛ぶ強さ
const BODY_MASS := 45.0     # 人の重さ (kg。sled.gd の RIDER_MASS と同じ)
const BOUNCINESS := 0.6     # 跳ね返りの強さ。飛び出す速さ = 迫る速さ × (1 + これ) × ソリの重さ / (ソリの重さ + 人の重さ)
const MAX_OUT := 14.0       # 飛び出す速さの上限 (m/s)
const UP_K := 0.75          # 飛び出す速さのこれだけ上向きにも飛ぶ
const UP_RANGE := Vector2(3.0, 8.0)   # 上向きの速さの下限と上限 (m/s)
const SIDE_K := 0.3         # 当たった側へそれる割合。ソリの通り道から外れて、すぐまた下敷きにならないように
const SLED_LOSS := 0.25     # 人を飛ばした反動のうち、ソリの速さに効かせる割合（紙の体は見かけより軽い）。1 で本当の反動
# ---- 飛んでいるあいだ
const G_UP := 14.6          # 上がるあいだの重力 (m/s²。player.gd の GRAVITY と同じ)
const G_DOWN := 16.0        # 下りるあいだの重力 (m/s²)。歩くときの 24 より軽い（紙の体が、ふわっと落ちる）
const TURNS_PER_S := 1.1    # 宙で回る速さの目安（1 秒に何回転）
const HOP_MIN_FALL := 3.0   # これより速く落ちて着くと、一度だけ跳ねる (m/s)
const HOP_UP := 0.4         # 跳ねるときに残る、落ちる速さの割合
const HOP_ON := 0.7         # 跳ねるときに残る、水平の速さの割合
const HOP_SPIN := 0.35      # 跳ねているあいだに回る量（12 fps の 1 コマに rad）
# ---- 倒れて、起き上がる
const SKID := 12.0          # 倒れて雪をすべるときの減速 (m/s²)
const LIE_TIME := Vector2(0.55, 1.0)   # 倒れている長さ (s)。弱く飛んだとき 〜 強く飛んだとき。すべり終えてから数える
const RISE_TIME := 0.5      # 起き上がる長さ (s)。人形の 6 コマ
const MAX_TIME := 6.0       # 何かに引っかかっても、ここまでで必ず起き上がる (s)
const COOL_TIME := 0.3      # 起き上がったあと、次に飛ばされるまで空ける (s)
const FALL_NET := 2.0       # 雪面よりこれだけ下へ沈んだら、雪の上へ戻す (m)
const EDGE_STOP := 3.0      # 見た目の地面の端からこの距離より外へは飛ばない (m)
const EDGE_EASE := 2.5      # 端へ向かう速さの上限 = 端までの残り × これ (1/s)
# ---- 体の当たり（player.gd・bot.gd の _ready のカプセルと同じ）
const RADIUS := 0.35
const TALL := 1.7

var body: CharacterBody3D
var stage := NONE
var dir := Vector3.ZERO      # 飛ぶ向き（水平）
var spin := 0.0              # 人形が 1 コマに回る量 (rad)
var hops := 0                # 跳ねた回数（人形が雪の粉を出す）
var ground_n := Vector3.UP   # 倒れている所の雪の向き
var _v := Vector3.ZERO
var _t := 0.0                # 吹き飛んでから (s)
var _air_t := 0.0            # 宙にいる (s)
var _lie := 0.0              # 倒れている長さの残り (s)
var _rise := 0.0             # 起き上がる長さの残り (s)
var _cool := 0.0
var _passing: Array = []     # 当たりを切っているソリ


func _init(b: CharacterBody3D) -> void:
	body = b


func active() -> bool:
	return stage != NONE


## いま体に当たろうとしているソリを探す。当たるなら {sled, closing, out, dir, point} を返す。skip はつかんでいるソリ（引きずりの決まりに任せる）
func find_hit(skip: Node = null) -> Dictionary:
	var dt := body.get_physics_process_delta_time()
	_cool = maxf(0.0, _cool - dt)
	if not _passing.is_empty():
		_end_passing()
	if active() or _cool > 0.0:
		return {}
	for s in body.get_tree().get_nodes_in_group("sleds"):
		if s != skip:
			var h := _hit_of(s, dt)
			if not h.is_empty():
				return h
	return {}


func _hit_of(s: RigidBody3D, dt: float) -> Dictionary:
	var v := s.linear_velocity
	if v.length() < MIN_SPEED or s.racked or s.freeze or not s.visible:
		return {}
	if s.pushers > 0 and v.y > 0.05:
		return {}   # 押して坂を登っているソリ
	var at := body.global_position
	var far: float = Vector2(s.HALF.x, s.HALF.y).length() + RADIUS + 1.0 + v.length() * dt * 2.0
	if Vector2(at.x - s.global_position.x, at.z - s.global_position.z).length_squared() > far * far:
		return {}
	var c: Vector3 = s.to_local(at + Vector3.UP * TALL * 0.5)
	# 高さ: 跳んで越えている・ソリが頭の上を飛んでいるときは当たらない
	var top: float = maxf(s.KINDS[s.kind].box.y, s.COL_MIN_H) + 0.1
	if c.y - TALL * 0.5 > top or c.y + TALL * 0.5 < -0.1:
		return {}
	# このコマから 2 コマ先までに、箱が体に触れるか（速いソリも、触れて止められる前に見つける。横を通り過ぎるだけのものは当てない）
	var flat_v := Vector3(v.x, 0.0, v.z)
	var flat_me := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var rel: Vector3 = s.global_basis.inverse() * (flat_me - flat_v)
	var near := Vector3.INF
	var off := Vector3.ZERO
	for i in 3:
		var q := c + rel * dt * i
		var n_at := Vector3(clampf(q.x, -s.HALF.x, s.HALF.x), 0.0, clampf(q.z, -s.HALF.y, s.HALF.y))
		var d := Vector3(q.x - n_at.x, 0.0, q.z - n_at.z)
		if d.length() <= RADIUS + 0.02:
			near = n_at
			off = d
			break
	if near == Vector3.INF:
		return {}
	var near_w: Vector3 = s.to_global(near)
	var n: Vector3 = s.global_basis * off
	n.y = 0.0
	n = n.normalized() if n.length() > 0.01 else flat_v.normalized()
	var v_at := flat_v + s.angular_velocity.cross(near_w - s.global_position)
	v_at.y = 0.0
	var closing := (v_at - flat_me).dot(n)
	if closing < MIN_CLOSING:
		return {}
	var m: float = s.load_mass()
	var out := minf(closing * (1.0 + BOUNCINESS) * m / (m + BODY_MASS), MAX_OUT)
	if out < MIN_OUT:
		return {}
	# 向き: ソリの進む向きと、当たった面の向きのあいだ。まんなかに当たっても少し横へそれる
	var side_sign := signf(c.x) if absf(c.x) > 0.02 else (1.0 if randf() < 0.5 else -1.0)
	var side: Vector3 = s.global_basis.x * side_sign
	side.y = 0.0
	var to := flat_v.normalized() * 0.6 + n * 0.4 + side.normalized() * SIDE_K
	return {"sled": s, "closing": closing, "out": out, "dir": to.normalized(), "point": near_w + Vector3.UP * 0.7}


## 吹き飛ぶ。まず手を離してから呼ぶ（let_go は持ち主がする）
func start(hit: Dictionary) -> void:
	stage = FLY
	dir = hit.dir
	_t = 0.0
	_air_t = 0.0
	hops = 0
	ground_n = Vector3.UP
	var up := clampf(float(hit.out) * UP_K, UP_RANGE.x, UP_RANGE.y)
	_v = dir * float(hit.out) + Vector3.UP * up
	# 宙で回る量: 着くときに、足をソリのほうへ向けて仰向けになる（人形は、飛ぶ向きへ背を向けて頭から回る）
	var air := up / G_UP + sqrt(up * up / G_UP / G_DOWN)
	var turns := roundf(air * TURNS_PER_S)
	spin = (PI * 0.5 + TAU * turns) / maxf(air * 12.0, 1.0)
	for s in body.get_tree().get_nodes_in_group("sleds"):
		body.add_collision_exception_with(s)
		_passing.append(s)
	var hub = body.get("hub")
	if hub:
		var w: Node = body.get_parent()
		hub.send({"kind": "flung", "who": body.get("id"), "sled": w.get_path_to(hit.sled), "closing": hit.closing, "point": hit.point, "dir": dir})


## ホストのソリだけに効かせる（emotes.gd が出来事 "flung" で呼ぶ）。重いソリほど遅くならない
static func slow_sled(s: RigidBody3D, closing: float) -> void:
	var m: float = s.load_mass()
	var loss := SLED_LOSS * (1.0 + BOUNCINESS) * BODY_MASS / (m + BODY_MASS) * clampf(closing, 0.0, 20.0)
	var v := s.linear_velocity.length()
	if v > 0.01:
		s.linear_velocity *= maxf(0.0, 1.0 - loss / v)


## 1 コマ動かす（持ち主の _physics_process が、歩くかわりに呼ぶ）
func step(dt: float) -> void:
	_t += dt
	match stage:
		FLY:
			_fly(dt)
		DOWN:
			_ground_step(dt, SKID)
			var flat := Vector2(_v.x, _v.z).length()
			if flat < 0.3 or _t > MAX_TIME:
				_lie -= dt
				if _lie <= 0.0 or _t > MAX_TIME:
					stage = RISE
					_rise = RISE_TIME
		RISE:
			_v.x = 0.0
			_v.z = 0.0
			_ground_step(dt, 0.0)
			_rise -= dt
			if _rise <= 0.0:
				stage = NONE
				_cool = COOL_TIME
				body.velocity = Vector3.ZERO
	_keep_on_ground()


func _fly(dt: float) -> void:
	var fall := -_v.y
	_v.y -= (G_UP if _v.y > 0.0 else G_DOWN) * dt
	_stay_inside()
	body.velocity = _v
	body.move_and_slide()
	_v = body.velocity
	_air_t += dt
	if body.is_on_wall():
		_v.x *= 0.5   # 木や壁に当たって勢いが落ちる
		_v.z *= 0.5
	if _air_t < 0.1:
		return
	if body.is_on_floor():
		if fall > HOP_MIN_FALL and hops == 0:
			hops = 1
			_v.y = fall * HOP_UP
			_v.x *= HOP_ON
			_v.z *= HOP_ON
			spin = HOP_SPIN
			return
		_lay_down()
	elif _t > MAX_TIME:
		_lay_down()


func _lay_down() -> void:
	stage = DOWN
	spin = 0.0
	var k := clampf(Vector2(_v.x, _v.z).length() / MAX_OUT, 0.0, 1.0)
	_lie = lerpf(LIE_TIME.x, LIE_TIME.y, k)


func _ground_step(dt: float, skid: float) -> void:
	var flat := Vector2(_v.x, _v.z).move_toward(Vector2.ZERO, skid * dt)
	_v = Vector3(flat.x, 0.0 if body.is_on_floor() else _v.y - G_DOWN * dt, flat.y)
	_stay_inside()
	body.velocity = _v
	body.move_and_slide()
	_v.y = body.velocity.y
	if body.is_on_floor():
		ground_n = body.get_floor_normal()


## 見た目の地面の端へ飛び出さない（sled.gd の _edge_drift と同じ考え。端に近いほど、端へ向かう速さを弱める）
func _stay_inside() -> void:
	var w := body.get_parent()
	if w == null or not w.has_method("edge_gap"):
		return
	var p := body.global_position
	var gap: float = w.edge_gap(p.x, p.z)
	if gap >= EDGE_STOP + MAX_OUT / EDGE_EASE:
		return
	var e := 0.5
	var out := Vector3(w.edge_gap(p.x - e, p.z) - w.edge_gap(p.x + e, p.z), 0.0, w.edge_gap(p.x, p.z - e) - w.edge_gap(p.x, p.z + e))
	if out.length() < 0.01:
		return
	out = out.normalized()
	var over := _v.dot(out) - maxf(gap - EDGE_STOP, 0.0) * EDGE_EASE
	if over > 0.0:
		_v -= out * over


## 雪面の下へ抜けていたら、雪の上へ戻す
func _keep_on_ground() -> void:
	var w := body.get_parent()
	if w == null or not w.has_method("height"):
		return
	var p := body.global_position
	var g: float = w.height(p.x, p.z)
	if p.y >= g - FALL_NET:
		return
	p.y = g + 0.1
	body.global_position = p
	_v.y = 0.0
	body.reset_physics_interpolation()


## ソリとの当たりを戻す。まだ重なっているソリは、離れるまで切ったまま（戻すと体がソリの中に閉じ込められる）
func _end_passing() -> void:
	if active():
		return
	for s in _passing.duplicate():
		if not is_instance_valid(s):
			_passing.erase(s)
		elif not _overlaps(s):
			body.remove_collision_exception_with(s)
			_passing.erase(s)


func _overlaps(s: RigidBody3D) -> bool:
	var c: Vector3 = s.to_local(body.global_position + Vector3.UP * TALL * 0.5)
	var pad := RADIUS + 0.1
	return absf(c.x) < s.HALF.x + pad and absf(c.z) < s.HALF.y + pad and absf(c.y) < TALL


## 人形に、いまの様子を伝える（持ち主の _pose_doll のあとで。通信では net.gd がこの値を配る）
func pose() -> void:
	var d = body.get("doll")
	d.flung = stage
	if stage == NONE:
		return
	d.flung_dir = dir
	d.flung_spin = spin
	d.flung_n = ground_n
	d.flung_hops = hops
	d.facing = -dir   # 当たったソリのほうを向いたまま、背中から飛ぶ（着くと、足をソリのほうへ向けて仰向け）
	d.airborne = stage == FLY
	d.crouch = false


## 一人称の視点に足す Vector3(左右の傾き, 上下の向き, 目を下げる量)。人形と同じ 12 コマで刻む。calm は視点の揺れを切ったときの弱まり
func view(frame: int, calm: float) -> Vector3:
	match stage:
		FLY:
			return Vector3(sin(frame * 1.1) * 0.5 * calm, cos(frame * 0.8) * 0.3 * calm, 0.6)
		DOWN:
			return Vector3(0.2 * calm, 0.55, 1.15)
		RISE:
			var k := clampf(_rise / RISE_TIME, 0.0, 1.0)
			return Vector3(0.2 * calm * k, 0.55 * k, 1.15 * k)
	return Vector3.ZERO


## 三人称のカメラの中心を下げる量 (m)。倒れているあいだ、地面の人形を見る
func pivot_drop() -> float:
	match stage:
		DOWN:
			return 0.9
		RISE:
			return 0.9 * clampf(_rise / RISE_TIME, 0.0, 1.0)
	return 0.0
