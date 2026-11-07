extends RigidBody3D

const Snowball := preload("res://snowball.gd")
const Look := preload("res://look.gd")
const Props := preload("res://props.gd")
const Gloves := preload("res://gloves.gd")
## 転がす大玉（2026-11-07 代表「ctrl+F でつくれる雪玉を転がしておおきな雪玉にしていける機能が欲しい。移動距離に従って大きくなり、
## 大きくなるに従って成長率も上がっていく」「坂上から転がしたら重力に従って（雪玉の大きさ＝重さも物理演算して）転がり、
## ぶつかったり跳ねたりしたときのある程度の衝撃で崩壊」「転がる雪玉に轢かれたキャラクターは雪玉に取り込まれる」）。
## 決まりと値の意味は design/controls-and-physics.md の「転がす大玉」。
##
## しゃがんで F を押し続けると、丸めた雪玉を雪の上に置く（emotes.gd の roll_seed）。体を当てて歩くと押せる（player.gd の _push_ball）。
## 雪の上を転がった道のりで大きくなり、大きいほど育ちも速い（半径の伸び = 道のり × (GROW_A + GROW_B × 半径)）。
## 重さは体積に比べる（DENSITY）。坂では重さで転がり、雪の転がり抵抗と、雪を押しのける抵抗（速さの 2 乗）で釣り合う。
## 強くぶつかる・跳ねて落ちる（1 コマの速さの変わりが BREAK_DV より大きい）と崩れる。
## 速く転がる大玉に当たった人は取り込まれる（rolled.gd）。中の人が Space を連打すると崩れ、崩れると中の人は放り出される。
##
## ソリと同じく、物理はホストの画面が正（net.gd の "bigball"。つなぐ側は届いた姿へ寄せる）。
## 生まれる・取り込む・暴れる・崩れるは、出来事（emotes.gd）でホストから全員に配る。

# ---- 大きさ
const SEED_R := 0.16         # 置いたばかりの玉の半径 (m)。手で丸めた雪玉（doll.gd の BALL_R 0.075）を、雪の上で一回り転がした大きさ
const MAX_R := 2.4           # これより大きくならない (m)。人の背丈の 3 倍ほど
const GROW_A := 0.012        # 1 m 転がると半径がこれだけ伸びる（小さいとき）
const GROW_B := 0.05         # …大きいほど、半径 1 m あたりこれだけ足す。0.16 → 1 m に約 22 m、→ 2.4 m に約 38 m
const DENSITY := 200.0       # 重さ (kg/m³)。半径 0.5 m で 105 kg、1 m で 840 kg、2 m で 6700 kg
const MIN_MASS := 3.0        # 物理の重さの下限 (kg)
# ---- 転がり
const ROLL_RES := 0.04       # 雪の転がり抵抗（重さに対する割合）。一人の押す力で、平らな所を半径およそ 0.9 m まで押せる（0.8 m でじりじり、1 m は動かない）
const PLOW := 20.0           # 雪を押しのける抵抗 (N per (m/s)² per m²)。坂の下りの速さの上限を決める（丘・大山の頂上から放すと 8〜9 m/s まで）
const SETTLE := 1.2          # 誰も押していない遅い玉（PUSH_SPEED より遅い）が、緩い所（坂の傾きが SETTLE_TAN より緩い）で雪に沈んで止まる減速 (m/s²)。
                             # 押すのをやめると 2 m/s から 1.5 秒ほどで止まる。坂から勢いよく来た玉は、平らな所でも惰性で転がる
const SETTLE_TAN := 0.18     # この坂（約 10°）より急なら沈まずに転がり続ける
const HOLD_TAN := 0.12       # 止まっていて、誰も押していなければ、これより緩い坂（約 7°）では転がり出さない
const HOLD_SPEED := 0.25     # これより遅ければ「止まっている」(m/s)
const PUSH_FORCE := 300.0    # 一人が押す力 (N)。ソリと同じ（sled.gd の PUSH_FORCE）
const PUSH_SPEED := 2.6      # 押して出せる速さ (m/s)。ここに近づくほど押す力が弱まる（歩く 2 m/s・走る 3.4 m/s のあいだ）
# ---- 崩れる
const BREAK_DV := 6.0        # 1 コマの速さの変わり（重力の分を除く）がこれより大きいと崩れる (m/s)。木・ロッジに 6 m/s で当たる、2 m ほどの高さから落ちる
const BREAK_LUMP := 3.5      # 雪の塊（sled_crash.gd）にこれより速く入ると崩れる (m/s)
const KICK_BASE := 5         # 中から崩すのに要る Space の回数 = KICK_BASE + KICK_PER_R × 半径（中の人みんなの合計）
const KICK_PER_R := 4.0
const KICK_FADE := 2.5       # 暴れるのをやめると、ひびがこの秒数で 1 回分ずつ戻る
# ---- 取り込む（rolled.gd が読む）
const CATCH_R := 0.55        # これより小さい玉は人を取り込まない (m)
const CATCH_SPEED := 3.0     # これより遅い玉は人を取り込まない (m/s)。押して出せる速さより上
const BODY_MASS := 45.0      # 中の人一人の重さ (kg。flung.gd と同じ)
# ---- いくつまで
const MAX_BALLS := 8         # 世界に置ける大玉の数。超えたら古いものから崩れる（ホスト）

var hub: Node3D              # emotes.gd
var ball_id := -1            # 大玉の番号（ホストが付ける。どの画面でも同じ玉を指せる）
var maker := -1              # 置いた人の番号
var r := SEED_R              # いまの半径 (m)
var inside := {}             # 中の人の番号 → [取り込まれた所の向き（玉の座標）, 頭の向き（玉の座標）]。出来事 ball_in で全員の画面に
var kicks := 0.0             # 中から暴れた回数（ホスト）
var pack := ""               # この玉を固めた手袋の段（押した人の手袋のうち、いちばんよいもの。gloves.gd）。育つ速さと丈夫さが上がる（ホスト）
var broken := false
var born := 0.0              # 生まれてから (s)

# ---- 通信: つなぐ側の大玉は、ホストの大玉の姿を写す（sled.gd の net_follow と同じ作り）
var net_follow := false:
	set(v):
		net_follow = v
		custom_integrator = v
const NET_PULL := 0.2
const NET_SNAP := 4.0
const NET_AHEAD := 0.3
var _net_at := Transform3D()
var _net_v := Vector3.ZERO
var _net_w := Vector3.ZERO
var _net_age := -1.0

var _shape: SphereShape3D
var _look: Node3D            # 見た目（半径 1 の玉を r 倍に）
var _mat: StandardMaterial3D
var _mat_r := -1.0           # 材質の模様の大きさを合わせた半径
var _v_prev := Vector3.INF
var _push_t := 99.0          # 最後に押されてから (s)
var _wob := 0.0              # 暴れて揺れている強さ（0〜）
var _wob_t := 0.0


func _ready() -> void:
	add_to_group("big_balls")
	continuous_cd = true
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	angular_damp = 0.3
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.05
	physics_material_override = pm
	var col := CollisionShape3D.new()
	_shape = SphereShape3D.new()
	_shape.radius = r
	col.shape = _shape
	add_child(col)
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 28
	sm.rings = 14
	var body := MeshInstance3D.new()
	body.mesh = sm
	_mat = Look.snow()   # 地面と同じ羊毛の雪（フェルトの縁の光りは雪の明るさで白く飛び、玉が平たい円に見えた）。編み目で転がるのが見える
	_mat.albedo_color = Color(0.93, 0.94, 0.97)   # 雪面より少しだけ沈めて、地面から浮き立たせる
	body.material_override = _mat
	_look.add_child(body)
	_add_seam()
	_set_r(r)
	born = 0.0


## 転がっているのが読めるように、玉を一周する縫い目（ソリの滑りあとと同じ、なみ縫い）
func _add_seam() -> void:
	var thread := Look.felt(Color("6F86A3"), 2.0)
	thread.rim = 0.0
	var dash := BoxMesh.new()
	dash.size = Vector3(0.14, 0.05, 0.05)
	var n := 28
	for i in n:
		if i % 2 == 1:
			continue
		var a := TAU * i / n
		var m := MeshInstance3D.new()
		m.mesh = dash
		m.material_override = thread
		m.position = Vector3(cos(a), 0.0, sin(a)) * 1.005
		m.rotation = Vector3(0.0, -a - PI * 0.5, 0.0)
		_look.add_child(m)
	# もう一本、斜めに（どちらへ転がっても回るのが見える）
	for i in n:
		if i % 2 == 0:
			continue
		var a := TAU * i / n
		var m := MeshInstance3D.new()
		m.mesh = dash
		m.material_override = thread
		var p := Vector3(cos(a), sin(a), 0.0) * 1.005
		m.position = Basis(Vector3.UP, 1.1) * p
		m.basis = Basis(Vector3.UP, 1.1) * Basis(Vector3.BACK, a + PI * 0.5)
		_look.add_child(m)


## 半径を変える（当たり・重さ・見た目）
func _set_r(nr: float) -> void:
	r = nr
	_shape.radius = r
	_look.scale = Vector3.ONE * r
	mass = maxf(DENSITY * 4.0 / 3.0 * PI * r * r * r, MIN_MASS) + BODY_MASS * inside.size()
	if absf(r - _mat_r) > _mat_r * 0.08:
		_mat_r = r
		_mat.uv1_scale = Vector3.ONE * 1.2 * r   # 編み目の細かさを、どの大きさでも同じに（玉の座標で 1 m に 1.2 回。雪面の 0.8 より少し細かく）


func _physics_process(dt: float) -> void:
	born += dt
	_wobble_step(dt)
	if broken or net_follow:
		return
	var w := get_parent()
	var p := global_position
	if p.y < w.height(p.x, p.z) - 6.0 or w.edge_gap(p.x, p.z) < 1.5:
		break_now("edge")
		return
	# 当たった・落ちた強さ: このコマの速さの変わりから、重力の分を除く
	var v := linear_velocity
	if _v_prev != Vector3.INF and born > 0.1:
		var dv := v - _v_prev - get_gravity() * dt
		if dv.length() > BREAK_DV * Gloves.stat(pack, "hard"):
			break_now("bump")
			return
	_v_prev = v
	_push_t += dt
	var hit := _ground_hit(p)
	if hit.is_empty():
		return   # 宙にいる
	var n: Vector3 = hit.normal
	var vt := v - n * v.dot(n)
	var sp := vt.length()
	var slope := Vector2(n.x, n.z).length() / maxf(n.y, 0.01)
	if _push_t > 0.2 and sp < HOLD_SPEED and slope < HOLD_TAN:
		# 止まっている: 緩い坂では、雪に沈んで動かない
		linear_velocity = n * v.dot(n)
		angular_velocity *= 0.5
		return
	if sp > 0.02:
		var res := ROLL_RES * 9.8 * n.y
		if _push_t > 0.2 and slope < SETTLE_TAN and sp < PUSH_SPEED:
			res += SETTLE * 1.4   # 転がる玉は回りの分だけ減速しにくいので、1.4 倍の力で SETTLE の減速に
		apply_central_force(-vt / sp * minf(res * mass, mass * sp / dt * 0.5))
		apply_central_force(-vt * sp * PLOW * r * r)
	# 雪の上を転がった道のりで大きくなる（デッキや石の上では大きくならない）。大きくなった分だけ、中心を上げる（雪に食い込まない）
	if sp > 0.05 and r < MAX_R and _is_snow(hit.collider):
		var nr := minf(r + sp * dt * (GROW_A + GROW_B * r) * Gloves.stat(pack, "grow"), MAX_R)
		var dr := nr - r
		_set_r(nr)
		global_position += n * dr


## 玉の真下の地面（触れていれば {position, normal, collider}。宙にいれば空）
func _ground_hit(p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * (r + 0.2))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.3:
		return {}
	return hit


static var _snow_of := {}    # 当たりの体 → 雪面か（高さの地図の当たりを持つ）

static func _is_snow(c: Object) -> bool:
	if c == null:
		return false
	var k := c.get_instance_id()
	if not _snow_of.has(k):
		var yes := false
		for ch in (c as Node).get_children():
			if ch is CollisionShape3D and (ch as CollisionShape3D).shape is HeightMapShape3D:
				yes = true
		_snow_of[k] = yes
	return _snow_of[k]


## 人が押す（player.gd・remote_person.gd。ホストの画面でだけ効く）。dir は水平の向き（長さが押す強さの割合）。
## grade は押す人の手袋の段（gloves.gd）: 押す力が段の倍率だけ強く、玉はいちばんよい手袋で固められる
func push(dir: Vector3, k := 1.0, grade := "") -> void:
	if broken or net_follow:
		return
	_push_t = 0.0
	if Gloves.rank(grade) > Gloves.rank(pack):
		pack = grade
	k *= Gloves.stat(grade, "push")
	var d := Vector3(dir.x, 0.0, dir.z)
	var along := linear_velocity.dot(d.normalized()) if d.length() > 0.01 else 0.0
	var fade := clampf(1.0 - along / PUSH_SPEED, 0.0, 1.0)
	apply_central_force(d * PUSH_FORCE * k * fade)


## 雪の塊（sled_crash.gd）に入った
func crash_lump(_lump: Node3D) -> void:
	if not net_follow and linear_velocity.length() > BREAK_LUMP:
		break_now("lump")


## 中の人が暴れた（ホスト。出来事 ball_kick）。回数が足りたら崩れる。崩れるまでの割合を返す
func kick() -> float:
	kicks += 1.0
	var need := KICK_BASE + KICK_PER_R * r
	if kicks >= need:
		break_now("kick")
	return clampf(kicks / need, 0.0, 1.0)


## 揺れる（どの画面でも。出来事 ball_kick で）。k は崩れるまでの割合（大きいほど大きく揺れる）
func wobble(k: float) -> void:
	_wob = 0.06 + 0.12 * k
	_wob_t = 0.0
	var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
	Snowball.splat_at(get_parent(), global_position + dir * r, dir, true, 0.6 + r * 0.5)


func _wobble_step(dt: float) -> void:
	if not broken and get_parent() and not net_follow and kicks > 0.0:
		kicks = maxf(0.0, kicks - dt / KICK_FADE)
	if _wob <= 0.0:
		_look.scale = Vector3.ONE * r
		return
	_wob_t += dt
	var s := sin(_wob_t * 40.0) * _wob
	_look.scale = Vector3(r * (1.0 + s), r * (1.0 - s), r * (1.0 + s))
	_wob = maxf(0.0, _wob - dt * 0.6)


## 崩す（ホストが決める。出来事 ball_break を全員へ。見た目は crumble で）
func break_now(why: String) -> void:
	if broken or net_follow or hub == null:
		return
	broken = true
	hub.send({"kind": "ball_break", "who": -1, "ball": ball_id, "point": global_position, "r": r,
			"dir": linear_velocity, "why": why, "inside": inside.keys()})


## 崩れる（どの画面でも。emotes.gd が出来事 ball_break で呼ぶ）: 綿の雪が四方へ散り、崩れた雪の山がしばらく残る
func crumble(ev: Dictionary) -> void:
	broken = true
	var w := get_parent() as Node3D
	var c := global_position
	var rr: float = float(ev.get("r", r))
	var n := clampi(int(4 + rr * 4.0), 4, 14)
	for i in n:
		var d := Vector3(randf_range(-1, 1), randf_range(0.0, 1.0), randf_range(-1, 1)).normalized()
		Snowball.splat_at(w, c + d * rr * 0.8, d, true, 1.5 + rr * 2.0)
	var g: float = w.height(c.x, c.z)
	Snowball.splat_at(w, Vector3(c.x, g + 0.05, c.z), Vector3.UP, false, 3.0 + rr * 4.0)
	_leave_pile(w, Vector3(c.x, g, c.z), rr)
	queue_free()


## 崩れた雪の山（雪の塊の glb）。ゆっくり雪に沈んで消える
static func _leave_pile(w: Node3D, at: Vector3, rr: float) -> void:
	var pile := Props.make("res://props/snow_pile_a.glb")
	pile.scale = Vector3.ONE * clampf(rr * 1.4, 0.3, 3.4)
	pile.rotation.y = randf() * TAU
	w.add_child(pile)
	pile.global_position = at
	var tw := pile.create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(pile, "position:y", at.y - 0.6 * pile.scale.y, 12.0)
	tw.tween_callback(pile.queue_free)


## ホストの大玉の姿が届いた（net.gd）
func net_put(at: Transform3D, lv: Vector3, av: Vector3, nr: float) -> void:
	_net_at = at
	_net_v = lv
	_net_w = av
	_net_age = 0.0
	if absf(nr - r) > 0.001:
		_set_r(nr)


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if not net_follow or _net_age < 0.0:
		return
	_net_age += st.step
	var ahead := minf(_net_age, NET_AHEAD)
	var want := _net_at
	want.origin += _net_v * ahead
	if _net_w.length() > 0.001:
		want.basis = Basis(_net_w.normalized(), _net_w.length() * ahead) * want.basis
	var t := st.transform
	if t.origin.distance_to(want.origin) > NET_SNAP:
		t = want
	else:
		t.origin = t.origin.lerp(want.origin, NET_PULL)
		t.basis = Basis(t.basis.get_rotation_quaternion().slerp(want.basis.get_rotation_quaternion(), NET_PULL))
	st.transform = t
	st.linear_velocity = _net_v
	st.angular_velocity = _net_w
