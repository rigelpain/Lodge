extends RigidBody3D

const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const Snowball := preload("res://snowball.gd")
## 大きなソリ。誰が押しても push() を呼ぶだけ（あなたも仲間も、のちの通信の相手も同じ）。
## 押す人が少ないとじりじり、多いと目に見えて速く登る。乗る人がいると減速をゆるめて一気に滑る。
## 誰も触れていない空のソリは、坂をゆっくりずり落ちる。速く下っているソリをつかむと引きずられ、
## 止める人の力の合計が「ソリと乗っている人の重さ × 坂」に勝てば止まる（引きずりの計算はソリがまとめてする。通信ではホスト）。

const PUSH_FORCE := 300.0   # 1人が押す力 (N)。1人でも最も急な所をじりじり登れる
const CLIMB_DAMP := 3.5     # 登るときの雪の抵抗（押すのをやめるとすぐ止まる。大きいほどじりじり）
const RIDE_DAMP := 0.12     # 乗って滑るときの減速
const STAND := 0.6                 # つかむ人が立つ、縁からの距離
const ROPE_LEN := 3.0
const ROPE_K := 260.0              # 紐が張ったときの引く力 (N/m)
const SLIP_RESIST := 18.0          # 滑り木の横滑りのしにくさ（前後 2 点それぞれ）
const RUNNER_DRAG := 3.0           # 滑り木 1 本の前後方向の抵抗 (N per m/s)

## 大きさ。大きいほど重く、席が多い（2026-10-29 代表: 小はホームセンターのプラスチックの 1〜2 人用、大はサンタの 8 人乗り）。
## 米袋は 1 人用で 1 kg（2026-10-29 代表「米袋1kgにしよう」）。小の席は成形ソリの座る面の高さ（glb に合わせた）。
## 当たりの箱・滑り木・席はこの表が正。glb（props/build_sled.py）はこの寸法に合わせて作る
const KINDS := {
	"sack": {"mass": 1.0, "box": Vector3(0.6, 0.15, 1.1), "runner_x": 0.2, "runner_z": 0.4,
			"seats": [Vector3(0, 0.15, 0.1)]},
	"small": {"mass": 15.0, "box": Vector3(0.75, 0.45, 1.6), "runner_x": 0.28, "runner_z": 0.6,
			"seats": [Vector3(0, 0.06, -0.3), Vector3(0, 0.06, 0.4)]},
	"mid": {"mass": 60.0, "box": Vector3(1.5, 0.45, 2.8), "runner_x": 0.6, "runner_z": 1.1,
			"seats": [Vector3(0, 0.45, -0.75), Vector3(0, 0.45, 0.15), Vector3(0, 0.45, 1.0)]},
	"large": {"mass": 220.0, "box": Vector3(2.2, 0.45, 4.8), "runner_x": 0.95, "runner_z": 1.9,
			"seats": [Vector3(-0.5, 0.55, -1.65), Vector3(0.5, 0.55, -1.65), Vector3(-0.5, 0.55, -0.55), Vector3(0.5, 0.55, -0.55),
					Vector3(-0.5, 0.55, 0.55), Vector3(0.5, 0.55, 0.55), Vector3(-0.5, 0.55, 1.65), Vector3(0.5, 0.55, 1.65)]},
}

# ---- ずり落ちと引きずり（調整する値。意味と、変えるとどうなるかは design/controls-and-physics.md）
const SLIDE_GRIP := 0.15       # 空のソリの雪の摩擦（重さに対する割合）。坂の傾き（tan）がこれより緩い所で止まる。0.15 ≈ 8.5°
const SLIDE_DAMP := 1.2        # 空のソリがずり落ちるときの雪の抵抗。大きいほどゆっくり（乗ると RIDE_DAMP）
const RIDER_MASS := 45.0       # 乗っている人一人の重さ (kg)。止めるときにだけ効く（登りは速くも遅くもしない）
const STOP_FORCE := 300.0      # つかんでいる人一人が止める力 (N)。押す力と同じ
const DRAG_SPEED := 2.5        # これより速く下っているソリをつかむと、引きずられる (m/s)
const DRAG_STOP_SPEED := 0.8   # 引きずられて、ここまで遅くなったら踏みとどまる（静止摩擦で留まる）
const DRAG_MAX_DIST := 15.0    # 止められないまま、この距離を引きずられると手が離れる (m)
const DRAG_SLIP_SPEED := 8.0   # これより速いと手がもたない（つかんでもすぐ離れる）(m/s)

const BODY_MIN_MASS := 15.0    # 物理の体の重さの下限 (kg)。米袋（重さ 1 kg）でも揺れずに滑るため。止める計算は表の重さを使う
const MID_MASS := 60.0         # 滑り木の抵抗・体重移動・雪かきの力はこの重さで決めた値。重さに比べて同じ効きにする
const PUSH_FADE := Vector2(3.0, 4.0)   # 押されるソリがこの速さ (m/s) を超えると、押す力が弱まって消える（人は走るより速く押せない）

signal slipped(who: Node3D)    # 引きずられて手が離れた

var kind := "mid"              # 置く前に決める（main.gd の --sled=sack|small|mid|large）
var kind_mass := 60.0          # 表の重さ（米袋は 1 kg）。乗っている人の重さと合わせて止める計算に使う
var _k := 1.0                  # 体の重さ / MID_MASS
var SEATS: Array = KINDS.mid.seats
var HALF := Vector2(0.75, 1.4)     # 台の半分の幅と長さ
var ROPE_ANCHOR := Vector3(0, 0.3, -1.45)
var RUNNER_Z := 1.1                # 滑り木の前後の接地点（中心からの距離）
var RUNNER_X := 0.6                # 左右の滑り木の位置
var parked := true             # ふもとに止めてある（最初と R で戻したとき）。誰かが触るまでずり落ちない
var dragged := {}              # 引きずられている人 → 引きずられた距離 (m)
var _pushed_by := {}           # このコマ押した人（引きずりの判定用。押している人は引きずられない）
var _pushed_now := {}
const LEAN_DIG := 17.5             # 体重をかけた側の滑り木が食い込んで増える抵抗（2026-10-28 に 14 から上げた）
const SCOOP_FORCE := 120.0         # 乗ったまま前傾して手で雪をかく力 (N)。坂を登る向きには効かない
const BRAKE_DRAG := 14.0           # 後ろに体重をかけたときの制動（両側）
const HOLD_FRICTION := 0.45        # 遅いときに働く静止摩擦（重さに対する割合）。丘のどこでも留まり、1人が押せば動き出す

var pushers := 0            # 前のコマで押していた人数（表示用）
var riders: Array[Node3D] = []
var holders := {}           # つかんでいる人 → つかんだ所（ソリの座標）
var rope_holder: Node3D = null
var rope: Node3D            # 引き紐（見た目と、拾える先の位置）
var _push_count := 0
var _steer := 0.0           # 乗っている人の左右の体重移動の合計（このコマ）
var _lean_fwd := false
var _lean_back := false
var hold_debug := ""

# 足元の影と、滑り木の跡（ステッチ）
const TRAIL_N := 800          # 残す針目の数（2 本 × 400 = 約 120 m）
const TRAIL_STEP := 0.3       # 針目の間隔 (m)
const TRAIL_ZIG := 0.045      # ジグザグの振れ幅（縫い目の中心から針穴まで, m）
const TRAIL_JITTER := 0.012   # 針穴の位置のばらつき (m)。手で縫ったような揺れ
var _blob: MeshInstance3D
var _trail: MultiMeshInstance3D
var _trail_i := 0
var _trail_dist := 0.0
var _trail_last := Vector3.INF
var _trail_flip := false
var _trail_holes := [Vector3.INF, Vector3.INF]   # 左右それぞれ、前の針穴
var _trail_rng := RandomNumberGenerator.new()
var snow_lift := Callable()   # (x, z) → 見た目の雪面が当たり判定からずれる量。main が渡す


func _ready() -> void:
	if not KINDS.has(kind):
		kind = "mid"
	var k: Dictionary = KINDS[kind]
	kind_mass = k.mass
	mass = maxf(k.mass, BODY_MIN_MASS)
	_k = mass / MID_MASS
	SEATS = k.seats
	HALF = Vector2(k.box.x, k.box.z) * 0.5
	ROPE_ANCHOR = Vector3(0, 0.3, -HALF.y - 0.05)
	RUNNER_X = k.runner_x
	RUNNER_Z = k.runner_z
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)
	angular_damp = 6.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.04
	physics_material_override = pm

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = k.box
	col.shape = box
	col.position.y = k.box.y * 0.49
	add_child(col)

	# 見た目: フェルトの座布団を曲げ木の滑り木に載せたソリ（props/build_sled.py の glb）。寸法はこの物理に合わせてある。
	# glb がまだない大きさは、当たりの箱と同じ大きさの仮の箱
	var glb := "res://props/sled_%s.glb" % kind
	if ResourceLoader.exists(glb):
		add_child(Props.make(glb))
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = k.box
		mi.mesh = bm
		mi.position.y = k.box.y * 0.5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.86, 0.80, 0.66) if kind == "sack" else Color(0.75, 0.25, 0.22)
		mi.material_override = m
		add_child(mi)
	# 引き紐: 手すりの両端を結ぶたわんだ紐と、そのまんなかから出る引っ張り紐（sled_rope.gd）
	rope = preload("res://sled_rope.gd").new()
	rope.sled = self
	add_child(rope)

	_make_shadow_and_trail()

## dir は押す向き（水平）、at は手が触れた所（世界座標）、who は押した人（引きずられている人は押せない）
func push(dir: Vector3, at: Vector3, who: Node3D = null) -> void:
	dir.y = 0
	if dir.length() < 0.01 or dragged.has(who):
		return
	parked = false
	if who:
		_pushed_now[who] = true
	var f: Vector3 = dir.normalized() * PUSH_FORCE * min(1.0, dir.length())
	f *= 1.0 - smoothstep(PUSH_FADE.x, PUSH_FADE.y, linear_velocity.dot(dir.normalized()))
	# 力は手が触れている所にそのままかける。どう動くかは滑り木と重力が決める
	var p := to_local(at)
	p.x = clamp(p.x, -HALF.x, HALF.x)
	p.z = clamp(p.z, -HALF.y, HALF.y)
	p.y = 0.2
	apply_force(f, global_basis * p)
	_push_count += 1


## 立っている所（世界座標）から、ソリの縁のいちばん近いつかみ所と、押す向きを返す
## [立つ位置（ソリの座標）, 押す向き（ソリの座標）]
func grip_point_near(world_pos: Vector3) -> Array:
	var p := to_local(world_pos)
	var ex := HALF.x + STAND
	var ez := HALF.y + STAND
	if abs(p.x) / ex > abs(p.z) / ez:
		var sx := signf(p.x) if p.x != 0.0 else 1.0
		return [Vector3(sx * ex, 0, clamp(p.z, -HALF.y, HALF.y)), Vector3(-sx, 0, 0)]
	var sz := signf(p.z) if p.z != 0.0 else 1.0
	return [Vector3(clamp(p.x, -HALF.x, HALF.x), 0, sz * ez), Vector3(0, 0, -sz)]


func take_handle(who: Node3D, h: Vector3) -> bool:
	for other in holders:
		if other != who and holders[other].distance_to(h) < 0.7:
			return false
	holders[who] = h
	parked = false
	# 速く下っているソリをつかむと、引きずられる。速すぎると手がもたない
	if _downhill_fast(DRAG_SPEED):
		dragged[who] = 0.0
	return true


func release_handle(who: Node3D) -> void:
	holders.erase(who)
	dragged.erase(who)


## 引きずられているか（つかんでいる人の見た目と音が読む）
func is_dragged(who: Node3D) -> bool:
	return dragged.has(who)


## 乗っている人も入れた重さ (kg)。米袋に誰も乗っていなければ 1 kg
func load_mass() -> float:
	return maxf(kind_mass + riders.size() * RIDER_MASS, 1.0)


## ソリがこれより速く下っているか（押されて登っているときは数えない）
func _downhill_fast(v: float) -> bool:
	return linear_velocity.length() > v and (_pushed_by.is_empty() or linear_velocity.y < -0.1)


func take_rope(who: Node3D) -> bool:
	if rope_holder != null and rope_holder != who:
		return false
	rope_holder = who
	parked = false
	return true


func release_rope(who: Node3D) -> void:
	if rope_holder == who:
		rope_holder = null


## 紐を持つ人の手の位置から、張っていれば引く。張った分の長さを返す（たるみなら負）
func pull_rope(hand: Vector3) -> float:
	var anchor := to_global(ROPE_ANCHOR)
	var d := hand - anchor
	var over := d.length() - ROPE_LEN
	if over > 0.0:
		var dir := d
		dir.y = 0
		apply_force(dir.normalized() * min(over * ROPE_K, 600.0), anchor - global_position)
		_push_count += 1
	return over




func mount(who: Node3D) -> Vector3:
	if riders.size() >= SEATS.size() or who in riders:
		return Vector3.INF
	riders.append(who)
	parked = false
	return SEATS[riders.size() - 1]


func dismount(who: Node3D) -> void:
	riders.erase(who)


## 乗っている人の体重移動。steer は -1（左）〜1（右）、forward は前傾、back は後傾。
## 力を直接かけるのではなく、滑り木の食い込み（抵抗）が変わることで曲がる・止まる
func lean(steer: float, forward: bool, back: bool = false) -> void:
	_steer += steer
	_lean_fwd = _lean_fwd or forward
	_lean_back = _lean_back or back


func reset_to(pos: Vector3) -> void:
	for r in riders.duplicate():
		if r.has_method("get_off"):
			r.get_off()
	for who in holders.keys():
		if who.has_method("let_go"):
			who.let_go()
	if rope_holder and rope_holder.has_method("let_go"):
		rope_holder.let_go()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(), pos)
	parked = true


## 足元の影（やわらかい楕円）と、滑り木の跡のステッチ（毛糸の雪に残る針目）
func _make_shadow_and_trail() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var dx := (x - 63.5) / 63.5
			var dy := (y - 63.5) / 63.5
			var r := sqrt(dx * dx + dy * dy)
			var a: float = (1.0 - smoothstep(0.3, 1.0, r)) * 0.42
			img.set_pixel(x, y, Color(0.20, 0.26, 0.46, a))
	var tex := ImageTexture.create_from_image(img)
	_blob = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 3.4)
	q.orientation = PlaneMesh.FACE_Y
	_blob.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.render_priority = -1
	_blob.material_override = m
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.top_level = true
	add_child(_blob)

	_trail = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Look.stitch_mesh(Color(0.66, 0.75, 0.93))   # 雪より濃い毛糸の青
	mm.instance_count = TRAIL_N
	for i in TRAIL_N:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -100, 0)))
		mm.set_instance_custom_data(i, Color(0.3, 0, 1, 0))
	_trail.multimesh = mm
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.top_level = true
	add_child(_trail)


func _ground_hit(from: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _update_shadow_and_trail() -> void:
	if _blob == null:
		return
	var hit := _ground_hit(global_position + Vector3.UP * 0.5)
	if hit:
		var n: Vector3 = hit.normal
		var fwd: Vector3 = -global_basis.z
		fwd = (fwd - n * fwd.dot(n)).normalized()
		_blob.global_transform = Transform3D(Basis(n.cross(-fwd).normalized(), n, -fwd), hit.position + n * 0.03)
	# ステッチ: 動いている間、0.3 m ごとに左右の滑り木の後ろ端に針穴をあけ、前の針穴から糸を渡す。
	# 針穴は縫い目の中心から左右交互にずらすので、太い糸のジグザグ縫いになる
	var v := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if v.length() < 0.25:
		_trail_last = Vector3.INF
		_trail_holes = [Vector3.INF, Vector3.INF]
		return
	if _trail_last == Vector3.INF:
		_trail_last = global_position
	_trail_dist += global_position.distance_to(_trail_last)
	_trail_last = global_position
	var dir := v.normalized()
	while _trail_dist >= TRAIL_STEP:
		_trail_dist -= TRAIL_STEP
		_trail_flip = not _trail_flip
		for k in 2:
			var sx := -RUNNER_X if k == 0 else RUNNER_X
			var h := _ground_hit(to_global(Vector3(sx, 0.3, RUNNER_Z)) + Vector3.UP * 0.5)
			if not h:
				_trail_holes[k] = Vector3.INF
				continue
			var nn: Vector3 = h.normal
			var d := (dir - nn * dir.dot(nn)).normalized()
			var side := d.cross(nn)
			var hole: Vector3 = h.position + side * ((TRAIL_ZIG if _trail_flip else -TRAIL_ZIG) + _trail_rng.randf_range(-TRAIL_JITTER, TRAIL_JITTER)) \
					+ d * _trail_rng.randf_range(-TRAIL_JITTER, TRAIL_JITTER)
			if snow_lift.is_valid():
				hole.y += snow_lift.call(hole.x, hole.z)
			var prev: Vector3 = _trail_holes[k]
			_trail_holes[k] = hole
			if prev == Vector3.INF:
				continue
			var span := hole - prev
			var len := span.length()
			if len < 0.1 or len > 0.6:
				continue
			# 前の針穴（原点）から -z の向きへ len だけ伸びる目
			var z := -span / len
			var y := (nn - z * nn.dot(z)).normalized()
			var b := Basis(y.cross(z), y, z)
			_trail.multimesh.set_instance_transform(_trail_i, Transform3D(b, prev + nn * 0.012))
			_trail.multimesh.set_instance_custom_data(_trail_i, Color(len, _trail_rng.randf(), _trail_rng.randf_range(0.9, 1.06), 0))
			_trail_i = (_trail_i + 1) % TRAIL_N


func _ground_normal() -> Vector3:
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.normal if hit else Vector3.UP


## 止める力を出している人の数: つかんでいて、このコマ押していない人（押されて登っているときは数えない）
func _brakers() -> int:
	if pushers > 0 and linear_velocity.y > -0.1:
		return 0
	var n := 0
	for who in holders:
		if not _pushed_by.has(who):
			n += 1
	return n


## 引きずられている人の出入り。速く下っている間につかんでいる人は引きずられ、遅くなれば踏みとどまる。
## 止められないまま DRAG_MAX_DIST 引きずられるか、DRAG_SLIP_SPEED より速くなると手が離れる
func _update_drag(dt: float) -> void:
	var v := linear_velocity.length()
	for who in holders.keys():
		if dragged.has(who):
			if v < DRAG_STOP_SPEED:
				dragged.erase(who)
				continue
			dragged[who] += v * dt
			if dragged[who] > DRAG_MAX_DIST or v > DRAG_SLIP_SPEED:
				release_handle(who)
				if who.has_method("let_go"):
					who.let_go()
				slipped.emit(who)
		elif not _pushed_by.has(who) and _downhill_fast(DRAG_SPEED):
			dragged[who] = 0.0
	_update_drag_puffs()
	_update_heel_stitches()


var _puffs := {}   # 引きずられている人 → 足もとの雪の粉

# 引きずられ跡: かかと 2 本の線に、ぐし縫いのギャザー（Look.gather_stitch_mesh）。短いなみ縫いの目と、まわりに寄ったひだ
const DRAG_TRAIL_N := 400       # 残す目の数（全員ぶん）
const DRAG_STITCH := 0.12       # 針穴の間隔 (m)。なみ縫いなので、目と目のあいだも同じだけ空く
const HEEL_X := 0.11            # かかとの、体のまんなかからの横の距離 (m)
var _drag_trail: MultiMeshInstance3D
var _drag_i := 0
var _heels := {}                # 引きずられている人 → {last, dist, on, holes: [左, 右]}


## かかとが雪をすべった所に、ぐし縫いの目を置く。速いほど雪が強く寄る（ひだが濃い）
func _update_heel_stitches() -> void:
	for who in _heels.keys():
		if not dragged.has(who) or not is_instance_valid(who):
			_heels.erase(who)
	if dragged.is_empty():
		return
	if _drag_trail == null:
		_drag_trail = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Look.gather_stitch_mesh(Color(0.70, 0.34, 0.30))   # かかとの赤茶の毛糸。滑りあとの青と見分ける
		mm.instance_count = DRAG_TRAIL_N
		for i in DRAG_TRAIL_N:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -100, 0)))
		_drag_trail.multimesh = mm
		_drag_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drag_trail.top_level = true
		add_child(_drag_trail)
	var v := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if v.length() < 0.2:
		return
	var dir := v.normalized()
	var side := dir.cross(Vector3.UP)
	for who in dragged:
		if not is_instance_valid(who):
			continue
		var feet: Vector3 = (who as Node3D).global_position
		var h: Dictionary = _heels.get(who, {})
		if h.is_empty():
			h = {"last": feet, "dist": 0.0, "on": true, "holes": [Vector3.INF, Vector3.INF]}
			_heels[who] = h
		h.dist += feet.distance_to(h.last)
		h.last = feet
		while h.dist >= DRAG_STITCH:
			h.dist -= DRAG_STITCH
			for k in 2:
				var at: Vector3 = feet + side * (HEEL_X if k == 0 else -HEEL_X) + side * _trail_rng.randf_range(-0.025, 0.025)
				var hit := _ground_hit(at + Vector3.UP * 0.6)
				if not hit:
					h.holes[k] = Vector3.INF
					continue
				var nn: Vector3 = hit.normal
				var hole: Vector3 = hit.position
				if snow_lift.is_valid():
					hole.y += snow_lift.call(hole.x, hole.z)
				var prev: Vector3 = h.holes[k]
				h.holes[k] = hole
				if prev == Vector3.INF or not h.on:
					continue
				var span := hole - prev
				var len := span.length()
				if len < 0.04 or len > 0.4:
					continue
				var z := -span / len
				var y := (nn - z * nn.dot(z)).normalized()
				_drag_trail.multimesh.set_instance_transform(_drag_i, Transform3D(Basis(y.cross(z), y, z), prev + nn * 0.01))
				_drag_trail.multimesh.set_instance_custom_data(_drag_i, Color(len, _trail_rng.randf(), _trail_rng.randf_range(0.9, 1.06),
						clampf(v.length() / 6.0, 0.45, 1.0)))
				_drag_i = (_drag_i + 1) % DRAG_TRAIL_N
			h.on = not h.on   # なみ縫い: 目、あき、目、…


## 引きずられている人の足もとから、綿の雪の粉が舞う（足が雪をすべる）。速いほど多い
func _update_drag_puffs() -> void:
	for who in _puffs.keys():
		if not is_instance_valid(who) or not dragged.has(who):
			var old: CPUParticles3D = _puffs[who]
			old.emitting = false
			_puffs.erase(who)
			old.get_tree().create_timer(1.2).timeout.connect(old.queue_free)
	var v := Vector3(linear_velocity.x, 0, linear_velocity.z)
	for who in dragged:
		if not is_instance_valid(who):
			continue
		var puff: CPUParticles3D = _puffs.get(who)
		if puff == null:
			puff = CPUParticles3D.new()
			puff.amount = 56
			puff.lifetime = 0.9
			puff.local_coords = false
			puff.direction = Vector3(0, 1, 0)
			puff.spread = 55.0
			puff.initial_velocity_min = 1.4
			puff.initial_velocity_max = 2.8
			puff.gravity = Vector3(0, -2.0, 0)
			puff.damping_min = 1.5
			puff.damping_max = 2.5
			puff.angle_max = 360.0
			puff.scale_amount_min = 0.9
			puff.scale_amount_max = 1.8
			puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			puff.emission_box_extents = Vector3(0.35, 0.02, 0.15)
			var ramp := Gradient.new()
			ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
			ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
			puff.color_ramp = ramp
			puff.mesh = Snowball._cotton_quad(0.22)
			get_parent().add_child(puff)
			puff.emitting = false
			puff.restart()
			_puffs[who] = puff
		# 足は前へ踏ん張り、ソリに引かれて雪をすべる。かかとが雪を押しのけ、粉は足のまわりから上へ舞って、後ろへ流れる
		# （ソリの下に隠れないよう、足の先までにする）
		var ahead := v.normalized() * 0.15 if v.length() > 0.1 else Vector3.ZERO
		puff.global_position = (who as Node3D).global_position + ahead + Vector3.UP * 0.05
		puff.direction = (Vector3.UP * 1.5 - v.normalized() * 0.4).normalized() if v.length() > 0.1 else Vector3.UP
		puff.speed_scale = clampf(0.6 + v.length() * 0.15, 0.6, 1.6)
		puff.emitting = true


func _physics_process(dt: float) -> void:
	_update_shadow_and_trail()
	pushers = _push_count
	_push_count = 0
	_pushed_by = _pushed_now
	_pushed_now = {}
	var riding := riders.size() > 0
	# 押されて坂を登っている間は、乗っている人がいても登りの雪の抵抗。乗るだけで登りが速くならないように
	var pushed_up := pushers > 0 and linear_velocity.y > 0.05
	# 誰も押していない空のソリは、ずり落ちる雪の抵抗（つかまれていても同じ。止める力はつかんだ人が出す）
	if riding and not pushed_up:
		linear_damp = RIDE_DAMP * (0.4 if _lean_fwd else 1.0)
	elif pushers > 0 or parked:
		linear_damp = CLIMB_DAMP
	else:
		linear_damp = SLIDE_DAMP
	_update_drag(dt)
	var side := global_basis.x
	var fwd := -global_basis.z
	# 滑り木: 前後にはよく滑り、横には滑らない。前後 2 点で横滑りを止めるので、
	# 縁に偏った力をかけると、横にずれるのでなく向きが変わる
	# 止まっているときは横滑りの抵抗を弱め、人が押してソリの向きを変えられるようにする
	var slip_k: float = SLIP_RESIST * (0.3 if linear_velocity.length() < 0.6 else 1.0)
	for z in [-RUNNER_Z, RUNNER_Z]:
		var r := global_basis * Vector3(0, 0, z)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var slip := side * v_point.dot(side)
		apply_force(-slip * mass * slip_k * 0.5, r)
	# 左右の滑り木の前後方向の抵抗。体重をかけた側が雪に食い込んで抵抗が増え、曲がる。
	# 後ろに体重をかけると両側が食い込んで止まる
	var steer: float = clamp(_steer, -1.0, 1.0)
	for x in [-RUNNER_X, RUNNER_X]:
		var r := global_basis * Vector3(x, 0, 0)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var v_long := v_point.dot(fwd)
		var c := RUNNER_DRAG
		if riding:
			if steer * signf(x) > 0.0:
				c += LEAN_DIG * abs(steer)
			if _lean_back:
				c += BRAKE_DRAG
		apply_force(-fwd * v_long * c * _k, r)
	# 遅いソリは静止摩擦で坂に留まる。押せばその分だけ動く。
	# 乗っている人がいても押されていれば効くので、乗る＋一人が押すは、一人で押すのと同じ速さで登る。
	# 押されていなければ、留める力は「つかんでいる人の止める力」と「空のソリの雪の摩擦」まで。
	# 誰も触れていない空のソリは雪の摩擦だけなので、急な所ではずり落ち、緩い所（ふもと）で止まる
	var speed := linear_velocity.length()
	var n := _ground_normal()
	var brakers := _brakers()
	# 空のソリの雪の摩擦は、押されていないときだけ（押して登るときの雪の抵抗は CLIMB_DAMP に入っている）
	var snow: float = 0.0 if riding or pushers > 0 else SLIDE_GRIP * mass * 9.8 * abs(n.y)
	if speed < DRAG_STOP_SPEED and (pushers > 0 or parked or brakers > 0 or not riding):
		var g := Vector3(0, -9.8, 0)
		var g_t := g - n * g.dot(n)
		var hold := -g_t * mass
		var cap: float = HOLD_FRICTION * mass * 9.8 * abs(n.y)
		if pushers == 0 and not parked:
			cap = minf(cap, brakers * STOP_FORCE * mass / load_mass() + snow)
		if hold.length() > cap:
			hold = hold.normalized() * cap
		apply_central_force(hold)
		if pushers == 0 and hold.length() < cap - 1.0:
			linear_velocity *= 0.9
		hold_debug = "n.y=%.2f 力=%.0f/%.0f" % [n.y, hold.length(), cap]
	else:
		# 動いている: つかんでいる人の止める力と空のソリの雪の摩擦が、動きと逆向きにかかる。
		# 乗っている人の重さは、止める力を分け合う重さに入れる（ソリと乗っている人をまとめて止める）
		var v_t := linear_velocity - n * linear_velocity.dot(n)
		var stop := brakers * STOP_FORCE * mass / load_mass() + snow
		if v_t.length() > 0.01 and stop > 0.0:
			apply_central_force(-v_t.normalized() * minf(stop, v_t.length() * mass / dt))
		hold_debug = "なし(速さ%.2f 押%d/%d 乗%d 止%d)" % [speed, _push_count, pushers, riders.size(), brakers]
	# 頂上などで、乗ったまま前傾すると手で雪をかいて動き出す。
	# 雪をかく力は坂を登る向きには効かない（平らな所と下りでだけ進む）。乗って W で登ると、降りて押すより速くなるため
	if riding and _lean_fwd and speed < 1.5:
		var f := (fwd - n * fwd.dot(n)).normalized()            # 地面に沿った前
		var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)      # 地面に沿った下り
		if down.length() > 0.01:
			down = down.normalized()
			f -= down * minf(0.0, f.dot(down))                   # 上りの成分を消す
		apply_central_force(f * SCOOP_FORCE * _k)
	_steer = 0.0
	_lean_fwd = false
	_lean_back = false
	# 起き上がり: 大きく傾いたら少しずつ戻す
	var up := global_basis.y
	if up.y < 0.5:
		apply_torque(up.cross(Vector3.UP) * 400.0 * _k)
