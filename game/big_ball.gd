extends RigidBody3D

const Snowball := preload("res://snowball.gd")
const Look := preload("res://look.gd")
const Props := preload("res://props.gd")
const Gloves := preload("res://gloves.gd")
const BallStitches := preload("res://ball_stitches.gd")
## 転がす大玉（2026-11-07 代表「ctrl+F でつくれる雪玉を転がしておおきな雪玉にしていける機能が欲しい。移動距離に従って大きくなり、
## 大きくなるに従って成長率も上がっていく」「坂上から転がしたら重力に従って（雪玉の大きさ＝重さも物理演算して）転がり、
## ぶつかったり跳ねたりしたときのある程度の衝撃で崩壊」「転がる雪玉に轢かれたキャラクターは雪玉に取り込まれる」）。
## 決まりと値の意味は design/controls-and-physics.md の「転がす大玉」。
##
## しゃがんで F を押し続けると、丸めた雪玉を雪の上に置く（emotes.gd の roll_seed）。体を当てて歩くと押せる（player.gd の _push_ball）。
## 雪の上を転がった道のりで大きくなり、大きいほど育ちも速い（半径の伸び = 道のり × (GROW_A + GROW_B × 半径)）。
## 重さは体積に比べる（DENSITY）。坂では重さで転がり、雪の転がり抵抗と、雪を押しのける抵抗（速さの 2 乗）で釣り合う。
## 耐久（2026-11-08 代表「耐久値を設定して、たえられる衝撃の量を持たせてほしい。ソリでぶつかっても耐久値が減ってほしいし、雪玉をぶつけても減ってほしい」）:
## 耐えられる量は大きいほど、固めた手袋がよいほど多い（max_wear）。ぶつかる・落ちる（1 コマの速さの変わり）、ソリ（重さ × 近づく速さ）、
## 投げた雪玉、雪の塊で減り（hurt）、尽きると崩れる。減ると当たった所がへこみ、そこの縫い目がはじけ飛び、雪のかけらが散る（show_hurt）。
## 崩れると、雪のかたまりが四方へ飛び散って転がり、雪に沈む（crumble）。育つと、減った分も、へこみも少し埋まる。
## 速く転がる大玉に当たった人は取り込まれる（rolled.gd）。中の人が Space を連打すると崩れ、崩れると中の人は放り出される。
##
## ソリと同じく、物理はホストの画面が正（net.gd の "bigball"。つなぐ側は届いた姿へ寄せる）。
## 生まれる・取り込む・暴れる・崩れるは、出来事（emotes.gd）でホストから全員に配る。

# ---- 大きさ
const SEED_R := 0.16         # 置いたばかりの玉の半径 (m)。手で丸めた雪玉（doll.gd の BALL_R 0.075）を、雪の上で一回り転がした大きさ
const MAX_R := 2.4           # これより大きくならない (m)。人の背丈の 3 倍ほど
const GROW_A := 0.006        # 1 m 転がると半径がこれだけ伸びる（小さいとき）。2026-11-08 代表「雪玉の成長率が高いかも。」で 0.012 から半分に
const GROW_B := 0.025        # …大きいほど、半径 1 m あたりこれだけ足す（0.05 から半分に）。毛糸の手袋で 0.16 → 0.5 m に約 25 m、→ 1 m に約 45 m、
                             # → 2.4 m に約 75 m（丘の頂上から斜面を下りきってふもとの溝を越えるくらい）。手袋の grow（gloves.gd）で割った道のりになる
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
# ---- 耐久（減る量の単位は「点」。どれも代表が遊んで決める前の仮の値）
const WEAR_BASE := 6.0       # 耐えられる量 = (WEAR_BASE + WEAR_PER_R × 半径) × 手袋の hard（gloves.gd）。毛糸で半径 0.16 m は 7、0.8 m は 11、2.4 m は 20
const WEAR_PER_R := 6.0
const DENT_DV := 2.5         # 1 コマの速さの変わり（重力の分を除く）がこれより小さければ減らない (m/s)。押す・起伏を転がる・人に当たるくらいでは減らない
const DENT_K := 3.5          # それを超えた 1 m/s ごとに減る量。毛糸の半径 0.8 m の玉は、木・ロッジに 7 m/s で 1 回、5 m/s なら 2 回で崩れる。2 m の高さから落ちると崩れる
const SLED_FREE := 60.0      # ソリがぶつかった勢い（乗る人も入れたソリの重さ × 近づく速さ, kg·m/s）がこれより小さければ減らない
const SLED_K := 40.0         # それを超えた SLED_K kg·m/s ごとに 1 減る。中のソリに 1 人乗って 6 m/s で 14（毛糸の半径 1 m の玉は 1 回で崩れる）
const SNOW_HIT := 0.8        # 投げた雪玉 1 個で減る量。毛糸の半径 0.5 m の玉は 12 個、1 m は 15 個で崩れる
const LUMP_FREE := 1.5       # 雪の塊（sled_crash.gd）に入る速さがこれより遅ければ減らない (m/s)
const LUMP_K := 4.0          # それを超えた 1 m/s ごとに減る量
const DENT_MAX := 10         # 覚えておくへこみの数（超えたら、近いへこみに足す）
# ---- 崩れる
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
var pack := "":              # この玉を固めた手袋の段（押した人の手袋のうち、いちばんよいもの。gloves.gd）。育つ速さと丈夫さが上がる。
	set(v):                  # ホストが決め、つなぐ側には大玉の姿と一緒に届く（net.gd の "bigball"）。縫い目の形と糸の色も段で決まる（ball_stitches.gd）
		if v == pack:
			return
		pack = v
		if _seam:
			refresh_stitch()
var broken := false
var born := 0.0              # 生まれてから (s)
var wear := 0.0              # 減った量（点。ホスト）。尽きる（max_wear に届く）と崩れる
var wear_k := 0.0            # 減った割合 0〜1（どの画面でも。出来事 ball_hurt で届く。見た目に使う）

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
var _body: MeshInstance3D    # 玉の面（へこむと、へこんだ形の ArrayMesh に替わる）
var _seam: MultiMeshInstance3D   # 縫い目の目（ball_stitches.gd。玉 1 つで 1 回描く）。へこんだ所の目ははじけ飛ぶ
var _seam_key := ""         # 縫っている "柄:段"
var _seam_segs: Array = []  # 縫い目の目（半径 1 の玉の上）[入る針穴, 出る針穴, 弧の向き]
var _seam_off := PackedByteArray()   # はじけた目は 1
var _dents := []             # へこみ [玉の座標の向き, 深さ（半径に対する割合）, 広がりの cos]
var _dent_r := 0.0           # へこみを作ったときの半径（育つと埋まる）
var _sled_v := {}            # 近くのソリ → [2 コマ前, 前のコマ] の速さ（触れはじめの知らせが届くときは、もう跳ね返ったあとの速さなので。ホスト）
var _v_old := Vector3.INF    # 玉の 2 コマ前の速さ
var _pend := 0.0             # このコマに減る量（いちばん強い当たりだけ数える。ソリの当たりと、その速さの変わりを重ねない）
var _pend_at := Vector3.ZERO
var _pend_why := ""


func _ready() -> void:
	add_to_group("big_balls")
	continuous_cd = true
	can_sleep = false
	contact_monitor = true      # ソリが当たったのを知る（_on_body）
	max_contacts_reported = 4
	body_entered.connect(_on_body)
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
	_body = body
	_mat = Look.snow()   # 地面と同じ羊毛の雪（フェルトの縁の光りは雪の明るさで白く飛び、玉が平たい円に見えた）。編み目で転がるのが見える
	_mat.albedo_color = COLOR_NEW   # 雪面より少しだけ沈めて、地面から浮き立たせる
	body.material_override = _mat
	_look.add_child(body)
	_make_seam()
	_set_r(r)
	born = 0.0


const COLOR_NEW := Color(0.93, 0.94, 0.97)
const COLOR_WORN := Color(0.80, 0.83, 0.90)   # 減りきる手前の色（押し固められて、少し灰がかった雪）


## 転がっているのが読めるように、玉を縫い目で縫う（2026-11-09 代表「作られた手袋のグレードによって雪玉のステッチの模様変えてほしい」）。
## 縫い合わせの形と糸の色は固めた手袋の段（pack）、柄は置いた人が持ち物で選んだ柄（craft.gd の ball_stitch）か、段の標準。形は ball_stitches.gd
func _make_seam() -> void:
	_seam = MultiMeshInstance3D.new()
	_seam.name = "Seam"
	_seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_seam.custom_aabb = AABB(Vector3(-1.3, -1.3, -1.3), Vector3(2.6, 2.6, 2.6))   # 目の範囲をエンジンに数えさせない（原点まで広がることがある）
	_look.add_child(_seam)
	refresh_stitch()


## 置いた人が選んでいる柄（買った柄。選んでいなければ ""）
func chosen_stitch() -> String:
	var cr = hub.get_parent().get("craft") if hub and hub.get_parent() else null
	if cr == null or not cr.has_method("ball_stitch_of"):
		return ""
	return cr.ball_stitch_of(maker)


## 縫っている柄の名前（ball_stitches.gd）
func stitch_name() -> String:
	return BallStitches.pattern_of(chosen_stitch(), pack)


## 柄か段が替わったら縫い直す（どの画面でも。craft.gd の ball_stitch_set と、pack が替わったとき）。へこんだ所の目は、はじけたまま
func refresh_stitch() -> void:
	var nm := stitch_name()
	var key := nm + ":" + pack
	if key == _seam_key or _seam == null:
		return
	_seam_key = key
	_seam_segs = BallStitches.segments(nm, pack)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BallStitches.mesh(nm, pack)
	mm.instance_count = _seam_segs.size()
	_seam_off = PackedByteArray()
	_seam_off.resize(_seam_segs.size())
	for i in _seam_segs.size():
		mm.set_instance_transform(i, BallStitches.xform(_seam_segs[i]))
		mm.set_instance_custom_data(i, BallStitches.custom(_seam_segs[i], i))
	_seam.multimesh = mm
	for d in _dents:
		_pop_seam(d[0], d[2], null)


## 向き dir（玉の座標）のまわり（cos が ca より近い）の目をはじく。w があれば、そのうち何本かを飛ばす
func _pop_seam(dir: Vector3, ca: float, w: Node3D, most := 12) -> void:
	var mm := _seam.multimesh if _seam else null
	if mm == null:
		return
	var flown := 0
	for i in _seam_segs.size():
		if _seam_off[i] == 1:
			continue
		var seg: Array = _seam_segs[i]
		if ((seg[0] as Vector3) + (seg[1] as Vector3)).normalized().dot(dir) > ca - 0.04:
			_seam_off[i] = 1
			mm.set_instance_custom_data(i, BallStitches.custom(seg, i, true))
			if w and flown < most:
				flown += 1
				_fly_seg(w, i)


## 半径を変える（当たり・重さ・見た目）
func _set_r(nr: float) -> void:
	r = nr
	_shape.radius = r
	_look.scale = Vector3.ONE * r
	mass = maxf(DENSITY * 4.0 / 3.0 * PI * r * r * r, MIN_MASS) + BODY_MASS * inside.size()
	if absf(r - _mat_r) > _mat_r * 0.08:
		_mat_r = r
		_mat.uv1_scale = Vector3.ONE * 1.2 * r   # 編み目の細かさを、どの大きさでも同じに（玉の座標で 1 m に 1.2 回。雪面の 0.8 より少し細かく）
	# 育つと、へこみが埋まり、減った割合も下がる（耐えられる量が増える）。どの画面でも同じに
	if not _dents.is_empty() and r > _dent_r * 1.05:
		var f := _dent_r / r
		for d in _dents:
			d[1] *= f * f
		_dents = _dents.filter(func(d): return d[1] > 0.01)
		wear_k *= (WEAR_BASE + WEAR_PER_R * _dent_r) / (WEAR_BASE + WEAR_PER_R * r)
		_dent_r = r
		_reshape()


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
		var dl := dv.length()
		if dl > DENT_DV:
			_queue_hurt((dl - DENT_DV) * DENT_K, p - dv / dl * r, "bump")   # 速さの変わりの逆の向き（当たった物の側）がへこむ
	if _pend > 0.0:
		hurt(_pend, _pend_at, _pend_why)
		_pend = 0.0
		if broken:
			return
	_v_old = _v_prev
	_v_prev = v
	_note_sleds(p)
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
	if net_follow or broken:
		return
	var v := linear_velocity
	if v.length() > LUMP_FREE:
		_queue_hurt((v.length() - LUMP_FREE) * LUMP_K, global_position + v.normalized() * r, "lump")


## 投げた雪玉が当たった（ホスト。emotes.gd の ball_splat）
func snow_hit(point: Vector3) -> void:
	hurt(SNOW_HIT, point, "snow")


## 耐えられる量（点）。大きいほど、固めた手袋がよいほど多い
func max_wear() -> float:
	return (WEAR_BASE + WEAR_PER_R * r) * Gloves.stat(pack, "hard")


## このコマに減る量を覚える（いちばん強いものだけ。_physics_process で減らす）
func _queue_hurt(amt: float, at: Vector3, why: String) -> void:
	if amt > _pend:
		_pend = amt
		_pend_at = at
		_pend_why = why


## 減らす（ホスト）。at は当たった所（世界）。尽きたら崩す。減った所と割合は出来事 ball_hurt で全員へ
func hurt(amt: float, at: Vector3, why: String) -> void:
	if broken or net_follow or hub == null or amt <= 0.0:
		return
	wear += amt
	var mw := max_wear()
	if wear >= mw:
		break_now(why)
		return
	var dir := global_basis.inverse() * (at - global_position)
	if dir.length() < 0.001:
		dir = Vector3.UP
	hub.send({"kind": "ball_hurt", "who": -1, "ball": ball_id, "dir": dir.normalized(), "amt": amt / mw,
			"k": wear / mw, "why": why})


## 近くのソリの速さを覚える（ホスト。触れはじめの知らせ（_on_body）は 1 コマ遅れて届くことがあり、そのときはもう跳ね返ったあとの速さなので、
## 2 コマ前まで覚えておく）
func _note_sleds(p: Vector3) -> void:
	var near := (r + 8.0) * (r + 8.0)
	for s in get_tree().get_nodes_in_group("sleds"):
		if s is RigidBody3D and (s as Node3D).global_position.distance_squared_to(p) < near:
			var v := (s as RigidBody3D).linear_velocity
			_sled_v[s] = [_sled_v[s][1] if _sled_v.has(s) else v, v]
		else:
			_sled_v.erase(s)


## 何かに触れはじめた（ホスト）。ソリなら、重さ（乗る人も）× 近づく速さで減る
func _on_body(body: Node) -> void:
	if broken or net_follow or not body.is_in_group("sleds"):
		return
	var s := body as RigidBody3D
	var d := global_position - s.global_position
	d.y *= 0.5   # ソリは玉の下の方に当たる。上下の差で近づく速さを小さく見積もらないように
	d = d.normalized()
	# 近づく速さ: 2 コマ前と前のコマのうち、大きいほう（当たる前の速さ）
	var vss: Array = _sled_v.get(s, [s.linear_velocity, s.linear_velocity])
	var vbs := [_v_old, _v_prev]
	var closing := 0.0
	for i in 2:
		var vb: Vector3 = vbs[i] if vbs[i] != Vector3.INF else linear_velocity
		closing = maxf(closing, ((vss[i] as Vector3) - vb).dot(d))
	if closing <= 0.0:
		return
	var m: float = s.load_mass() if s.has_method("load_mass") else s.mass
	var amt := (m * closing - SLED_FREE) / SLED_K
	if amt > 0.0:
		_queue_hurt(amt, global_position - d * r, "sled")


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


## 減った（どの画面でも。emotes.gd が出来事 ball_hurt で呼ぶ）: 当たった所がへこみ、そこの縫い目がはじけ飛び、雪のかけらが散って、玉が揺れる。
## 減るほど、玉の色が少し灰がかる（押し固められた雪）
func show_hurt(ev: Dictionary) -> void:
	var dir: Vector3 = (ev.get("dir", Vector3.UP) as Vector3).normalized()
	var amt: float = clampf(float(ev.get("amt", 0.1)), 0.0, 1.0)
	wear_k = clampf(float(ev.get("k", wear_k)), 0.0, 1.0)
	_mat.albedo_color = COLOR_NEW.lerp(COLOR_WORN, wear_k)
	# へこみ: 減った割合が大きいほど深く広い。近くにへこみがあれば、そこが深くなる
	var depth := clampf(0.025 + amt * 0.3, 0.025, 0.16)
	var ca := cos(clampf(0.28 + amt * 0.8, 0.28, 0.62))
	var near := -1
	for i in _dents.size():
		if (_dents[i][0] as Vector3).dot(dir) > ca:
			near = i
	if near >= 0:
		_dents[near][1] = minf(_dents[near][1] + depth * 0.6, 0.22)
		_dents[near][2] = minf(_dents[near][2], ca)
	else:
		if _dents.size() >= DENT_MAX:
			_dents.pop_front()
		_dents.append([dir, depth, ca])
	_dent_r = r
	_reshape()
	# へこんだ所の縫い目の目が、はじけ飛ぶ
	var w := get_parent() as Node3D
	_pop_seam(dir, ca, w)
	# 雪のかけらと綿の粉
	var at := global_position + global_basis * dir * r
	var out := (global_basis * dir).normalized()
	Snowball.splat_at(w, at, out, true, 0.8 + amt * 3.0 + r * 0.4)
	for i in clampi(int(amt * 10.0), 1, 4):
		var sz := clampf(r * randf_range(0.08, 0.16) * (0.6 + amt * 2.0), 0.04, 0.35)
		var v := (out + Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.9), randf_range(-0.6, 0.6))).normalized() * randf_range(1.5, 3.0)
		_fly_chunk(w, at + out * sz, v + linear_velocity * 0.6, sz)
	_wob = maxf(_wob, 0.03 + 0.12 * clampf(amt * 2.5, 0.0, 1.0))
	_wob_t = 0.0


## 玉の面を、へこみの形に作り直す（半径 1 の玉の頂点を、へこみの向きへ沈める。法線も、へこみの斜面に合わせて傾ける）
func _reshape() -> void:
	if _dents.is_empty():
		_body.mesh = _sphere_mesh()
		return
	var a: Array = _sphere_arrays()
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	nv.resize(vs.size())
	nn.resize(vs.size())
	for i in vs.size():
		var v := vs[i].normalized()
		var h := 1.0
		var g := Vector3.ZERO
		for d in _dents:
			var dir: Vector3 = d[0]
			var c := v.dot(dir)
			var ca: float = d[2]
			if c <= ca:
				continue
			var t := (c - ca) / (1.0 - ca)
			h -= float(d[1]) * t * t * (3.0 - 2.0 * t)
			g += (dir - v * c) * float(d[1]) * 6.0 * t * (1.0 - t) / (1.0 - ca)
		h = maxf(h, 0.7)
		nv[i] = v * h
		nn[i] = (v * h + g).normalized()
	var out := a.duplicate()
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	_body.mesh = am


static var _sphere: SphereMesh
static var _sphere_a := []

static func _sphere_mesh() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 28
		_sphere.rings = 14
	return _sphere


static func _sphere_arrays() -> Array:
	if _sphere_a.is_empty():
		_sphere_a = _sphere_mesh().get_mesh_arrays()
	return _sphere_a


## 縫い目の目を一つ、玉から飛ばす（i は _seam_segs の番号。糸の色のフェルトの細い棒）
func _fly_seg(w: Node3D, i: int) -> void:
	var seg: Array = _seam_segs[i]
	var t := BallStitches.xform(seg)
	var len := (seg[1] as Vector3).distance_to(seg[0])
	var th := float(BallStitches.LIST.get(_seam_key.get_slice(":", 0), {}).get("radius", 0.03)) * 1.4
	len *= 0.55   # ちぎれた糸のきれはし
	var f := Flyer.new()
	f.mesh = BallStitches.dash_mesh()
	f.material_override = BallStitches.dash_mat(pack)
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(f)
	f.global_transform = _look.global_transform * Transform3D(Basis(t.basis.x * th, t.basis.y * th, t.basis.z * len), t.origin - t.basis.z * len * 0.5)
	var out := (f.global_position - global_position).normalized()
	f.vel = out * randf_range(1.5, 3.0) + Vector3.UP * randf_range(1.0, 2.5) + linear_velocity * 0.5
	f.spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	f.size = 0.03 * r
	f.skip = get_rid()


static var _chunk_mesh: SphereMesh
static var _chunk_mats := {}

## 雪のかたまりを一つ飛ばす（いびつな毛糸の雪の玉）。sz は半径 (m)
func _fly_chunk(w: Node3D, at: Vector3, v: Vector3, sz: float) -> void:
	if _chunk_mesh == null:
		_chunk_mesh = SphereMesh.new()
		_chunk_mesh.radius = 1.0
		_chunk_mesh.height = 2.0
		_chunk_mesh.radial_segments = 9
		_chunk_mesh.rings = 5
	var key := snappedf(sz, 0.05)
	if not _chunk_mats.has(key):
		var m := Look.snow()
		m.albedo_color = COLOR_NEW
		m.uv1_scale = Vector3.ONE * 1.2 * maxf(key, 0.05)   # 編み目の細かさを玉と同じに
		_chunk_mats[key] = m
	var f := Flyer.new()
	f.mesh = _chunk_mesh
	f.material_override = _chunk_mats[key]
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sz > 0.15 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(f)
	f.global_position = at
	f.basis = Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0.0)).scaled(
			Vector3(randf_range(0.75, 1.15), randf_range(0.6, 0.95), randf_range(0.8, 1.2)) * sz)
	f.vel = v
	f.spin = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	f.size = sz
	f.skip = get_rid()


## 崩れる（どの画面でも。emotes.gd が出来事 ball_break で呼ぶ）: 雪のかたまりが四方へ飛び散って転がり、綿の雪の粉が舞い、
## 縫い目の目がはじけ、崩れた雪の山がしばらく残る
func crumble(ev: Dictionary) -> void:
	broken = true
	var w := get_parent() as Node3D
	var c := global_position
	var rr: float = float(ev.get("r", r))
	var carry: Vector3 = (ev.get("dir", Vector3.ZERO) as Vector3) * 0.5
	var n := clampi(int(4 + rr * 4.0), 4, 14)
	for i in n:
		var d := Vector3(randf_range(-1, 1), randf_range(0.0, 1.0), randf_range(-1, 1)).normalized()
		Snowball.splat_at(w, c + d * rr * 0.8, d, true, 1.5 + rr * 2.0)
	# 雪のかたまり: 大きいのが少し、小さいのがたくさん
	var nc := clampi(int(7 + rr * 5.0), 7, 18)
	for i in nc:
		var d := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized()
		var sz := rr * (randf_range(0.26, 0.4) if i < 3 else randf_range(0.1, 0.22))
		sz = clampf(sz, 0.05, 0.9)
		var sp := randf_range(1.5, 3.5) * (0.7 + 0.25 * sqrt(rr))
		var v := d * sp + Vector3.UP * randf_range(1.0, 3.0) * (0.6 + 0.4 * sqrt(rr)) + carry
		_fly_chunk(w, c + d * rr * 0.55, v, sz)
	var torn := 0
	for k in mini(_seam_segs.size(), 40):
		var i := randi() % _seam_segs.size()
		if _seam_off[i] == 0 and torn < 10:
			_seam_off[i] = 1
			torn += 1
			_fly_seg(w, i)
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


## 飛び散る雪のかたまり・縫い目の目（見た目だけ。当たりは持たない。どの画面でも、それぞれに飛ぶ）。
## 進んだ線分で地面・物に当たると跳ね、止まると転がって、しばらくで雪に沈んで消える
class Flyer extends MeshInstance3D:
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var size := 0.1            # 地面からの浮き (m)
	var skip := RID()          # 当たりを見ない体（崩れた玉）
	var life := 0.0
	var rest := -1.0           # 止まってから (s)。止まるまでは負

	func _physics_process(dt: float) -> void:
		life += dt
		if life > 14.0:
			queue_free()
			return
		if rest >= 0.0:
			rest += dt
			if rest > 5.0:
				# 雪に沈む
				global_position.y -= dt * maxf(size, 0.03) * 0.5
				if rest > 8.0:
					queue_free()
			return
		vel.y -= 9.8 * dt
		var a := global_position
		var b := a + vel * dt
		var q := PhysicsRayQueryParameters3D.create(a, b + vel.normalized() * size)
		if skip.is_valid():
			q.exclude = [skip]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			global_position = b
			if spin != Vector3.ZERO:
				basis = Basis(spin.normalized(), spin.length() * dt) * basis
			if global_position.y < -100.0:
				queue_free()
			return
		var nrm: Vector3 = hit.normal
		global_position = (hit.position as Vector3) + nrm * size * 0.7
		var vn := vel.dot(nrm)
		if absf(vn) > 1.5:
			vel = (vel - nrm * vn) * 0.55 - nrm * vn * 0.25   # 跳ねる（雪なので、ほとんど跳ねない）
			spin *= 0.6
		else:
			rest = 0.0                                          # 止まる


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
