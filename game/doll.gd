extends Node3D

## 人形（person/build_dolls.py で作り、骨を入れて焼いた glb）を骨で動かす。
## 3 体: kasa 笠と千代紙の人形 / origami 多面体の折り紙の人 / news 新聞紙と麻布の人形。骨の名前は 3 体で同じ。
## 居場所（位置と向き）は毎フレームなめらか。姿勢（骨の向き）は 12 コマ／秒で刻み、コマの間は止める。
## 全員が同じ時計（物理のコマ数）でコマを変え、そのたびに骨をわずかに揺らす（クレイアニメの揺れ）。
## ソリや紐をつかむ手は、つかんだ物に対しての姿勢をコマで決め、毎フレーム腕を伸ばし直す（ソリが動いても手が離れない）。
## 見た目だけ。持ち主（player.gd・bot.gd）が毎フレーム act などを入れる。通信には乗せない。

const FPS := 12
const CADENCE := 2.0          # 歩く周期の上限（1 秒に何周）
const BOIL := 0.018           # コマごとの骨の揺れ（rad）
const SCENES := {
	"kasa": preload("res://person/kasa.glb"),
	"origami": preload("res://person/origami.glb"),
	"news": preload("res://person/news.glb"),
}
## ゲームでの大きさ。news がいちばん小さく、目の高さが origami のお尻あたり
const SCALE := {"kasa": 1.15, "origami": 1.1, "news": 1.05}
## 足もとの影の半径（人形の大きさのまま）
const FOOT_SHADOW := {"kasa": 0.46, "origami": 0.44, "news": 0.38}
## 目の所（glb の座標、人形の大きさのまま。立ったとき）。乗っているときの一人称のカメラを合わせる
const EYE := {"kasa": Vector3(0, 1.01, -0.1), "origami": Vector3(0, 1.235, -0.1), "news": Vector3(0, 0.745, -0.12)}
## 座ったとき、腰の骨の付け根を座面からどれだけ上に置くか（骨の座標の空間）
const SIT_HIPS := 0.07
## 口の位置（頭の骨の付け根から、人形の大きさのまま）。白い息が出る
const MOUTH := {"kasa": Vector3(0, 0.08, -0.24), "origami": Vector3(0, 0.07, -0.27), "news": Vector3(0, 0.13, -0.3)}

enum Act { WALK, PUSH, ROPE, RIDE }

var kind := "kasa"
var layers := 1

# 持ち主が毎フレーム入れる
var act := Act.WALK
var facing := Vector3.ZERO   # 体の向き（世界、水平）。ZERO なら持ち主の前
var gaze := Vector3.INF      # 見ている所（世界）
var effort := false
var airborne := false
var waving := false
var point := Vector3.INF     # 腕を伸ばして指す所（世界）。gaze が決まっていなければ、そこを見る
var sled: Node3D = null
var grip := Vector3.INF      # つかんでいる立ち位置（ソリの座標）
var rope_hand := Vector3.INF # 紐を持つ右手の所（世界）
var lean := Vector2.ZERO     # 乗っているときの体重移動（x 右、y 前）

var skel: Skeleton3D
var _b := {}                 # 骨の名前 → 番号
var _order: Array[int] = []  # 親が先
var _rest_rot := {}          # 番号 → 付け根の回転（親の座標）
var _rest_pos := {}
var _rot := {}               # 番号 → いまの回転（親の座標）
var _g := {}                 # 番号 → いまの向きと位置（骨の座標の空間）
var _hold: Array = [null, null]   # 手ごとに [基準のノード, その座標での手の所] か null
var _arm_base := {}          # コマで決めた腕の回転（毎フレームここから伸ばし直す）
var _breath: CPUParticles3D
var _breaths: Array[CPUParticles3D] = []   # 息の出口は 2 つ。交互に使い、まだ流れている息を消さない
var _next_out := 0
var _frame := -1
var _yaw := 0.0
var _last := Vector3.INF
var _speed := 0.0
var _phase := 0.0
var _voice := 0
var _next_breath := 0
var _rng := RandomNumberGenerator.new()
var _scale := 1.0


func _ready() -> void:
	top_level = true
	_scale = SCALE[kind]
	var inst: Node3D = SCENES[kind].instantiate()
	inst.scale = Vector3.ONE * _scale
	add_child(inst)
	skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	_add_skirt(inst)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).layers = layers
	for i in skel.get_bone_count():
		_b[skel.get_bone_name(i)] = i
		var r := skel.get_bone_rest(i)
		_rest_rot[i] = r.basis.get_rotation_quaternion()
		_rest_pos[i] = r.origin
		_rot[i] = _rest_rot[i]
	var depth := func(i: int) -> int:
		var d := 0
		var p := skel.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = skel.get_bone_parent(p)
		return d
	for i in skel.get_bone_count():
		_order.append(i)
	_order.sort_custom(func(a, b): return depth.call(a) < depth.call(b))
	_make_breath()
	_make_foot_shadow()
	_next_breath = randi_range(4, 30)


static func frame_index() -> int:
	return Engine.get_physics_frames() * FPS / Engine.physics_ticks_per_second


## 声を出す（言葉にならない声）。少し見上げて、大きな白い息が出る
func call_out() -> void:
	_voice = 7


# ---------------------------------------------------------------- 骨の小道具（骨の座標の空間で考える）

func _id(name: String) -> int:
	return _b.get(name, -1)


## 付け根の姿勢に戻し、親から順に向きと位置を計算する
func _reset() -> void:
	for i in _order:
		_rot[i] = _rest_rot[i]
	_hips_drop = 0.0
	_squash = 1.0
	_update_all()


var _hips_drop := 0.0
var _squash := 1.0           # 腰より下の裾の縦の長さ（座ると、つぶれて座面に広がる）


func _update_all() -> void:
	for i in _order:
		_update(i)


func _update(i: int) -> void:
	var p := skel.get_bone_parent(i)
	var local := Transform3D(Basis(_rot[i]), _rest_pos[i] + (Vector3(0, -_hips_drop, 0) if p < 0 else Vector3.ZERO))
	_g[i] = (_g[p] * local) if p >= 0 else local


## 骨を、骨の座標の空間の回転 q で回す（子は一緒に回る。子の向きは _update_all で計算し直す）
func _turn(i: int, q: Quaternion) -> void:
	if i < 0:
		return
	var p := skel.get_bone_parent(i)
	var pb: Basis = (_g[p] as Transform3D).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var lb := Basis(_rot[i])
	_rot[i] = (pb.inverse() * Basis(q) * pb * lb).get_rotation_quaternion()
	_update_subtree(i)


func _update_subtree(i: int) -> void:
	_update(i)
	for c in skel.get_bone_children(i):
		_update_subtree(c)


func _turn_axis(name: String, axis: Vector3, angle: float) -> void:
	if absf(angle) > 1e-5:
		_turn(_id(name), Quaternion(axis.normalized(), angle))


## 骨の向き（付け根から先へ）を dir に向ける
func _aim(i: int, dir: Vector3) -> void:
	if i < 0 or dir.length() < 1e-5:
		return
	var y: Vector3 = (_g[i] as Transform3D).basis.y.normalized()
	var d := dir.normalized()
	if y.dot(d) > 0.9999:
		return
	_turn(i, Quaternion(y, d))


func _head_of(i: int) -> Vector3:
	return (_g[i] as Transform3D).origin


func _len(i: int) -> float:
	var c := skel.get_bone_children(i)
	if c.is_empty():
		return 0.08
	return (_rest_pos[c[0]] as Vector3).length()


## 二関節の腕で、手が target（骨の座標の空間）に来るように曲げる
func _reach(side: String, target: Vector3) -> void:
	var up := _id("upper_arm." + side)
	var fo := _id("forearm." + side)
	if up < 0 or fo < 0:
		return
	var s := _head_of(up)
	var a := _len(up)
	var b := _len(fo) + _len(_id("hand." + side)) * 0.5
	var to := target - s
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.001)
	var dir := to.normalized()
	var sx := 1.0 if side == "R" else -1.0
	var pole := Vector3(sx * 0.7, -0.5, 0.6).normalized()
	pole = (pole - dir * pole.dot(dir)).normalized()
	var ang := acos(clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0))
	var elbow := s + (dir * cos(ang) + pole * sin(ang)) * a
	_aim(up, elbow - s)
	_aim(fo, (s + dir * d) - _head_of(fo))


func _apply() -> void:
	for i in _order:
		skel.set_bone_pose_rotation(i, _rot[i])
		skel.set_bone_pose_position(i, _rest_pos[i] + (Vector3(0, -_hips_drop, 0) if skel.get_bone_parent(i) < 0 else Vector3.ZERO))
	var sk := _id("skirt")
	if sk >= 0:
		skel.set_bone_pose_scale(sk, Vector3(1, _squash, 1))


## 座るときに腰を落とす量（骨の座標の空間）
func _sit_drop() -> float:
	return skel.get_bone_global_rest(_id("hips")).origin.y - SIT_HIPS


## 目の所（人形の座標、m）。座っているときは腰を落とした分だけ低い（姿勢のコマや揺れには付き合わない）
func eye_point(sitting: bool) -> Vector3:
	var e: Vector3 = EYE.get(kind, EYE["kasa"])
	if sitting:
		e.y -= _sit_drop()
	return e * _scale


# ---------------------------------------------------------------- 裾

static var _skirt_cache := {}


## 腰の骨に「裾」の骨を子として足し、腰より下の、腰の骨で動く所（着物・ローブ・ケープの裾）をそちらへ移す。
## ふだんは腰と同じに動き、座ったときだけ縦につぶす（裾が座面を突き抜けない）。
## 裾の骨は子を持たないので、縦だけつぶしても脚や胸はゆがまない
func _add_skirt(inst: Node3D) -> void:
	var hips := skel.find_bone("hips")
	if hips < 0:
		return
	var sk := skel.add_bone("skirt")
	skel.set_bone_parent(sk, hips)
	skel.set_bone_rest(sk, Transform3D.IDENTITY)
	skel.reset_bone_pose(sk)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.skin == null:
			continue
		if not _skirt_cache.has(kind):
			_skirt_cache[kind] = _skirt_mesh(mi)
		var c: Array = _skirt_cache[kind]
		if c.is_empty():
			continue
		mi.mesh = c[0]
		mi.skin = c[1]


func _skirt_mesh(mi: MeshInstance3D) -> Array:
	var skin := mi.skin.duplicate() as Skin
	var hb := -1
	for i in skin.get_bind_count():
		var n := skin.get_bind_name(i)
		if n == "hips" or (n == "" and skin.get_bind_bone(i) == skel.find_bone("hips")):
			hb = i
	if hb < 0:
		return []
	var nb := skin.get_bind_count()
	if skin.get_bind_name(hb) != "":
		skin.add_named_bind("skirt", skin.get_bind_pose(hb))
	else:
		skin.add_bind(skel.find_bone("skirt"), skin.get_bind_pose(hb))
	var to_hips := skin.get_bind_pose(hb)
	var src := mi.mesh
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var per := bones.size() / verts.size()
		for v in verts.size():
			if (to_hips * verts[v]).y < 0.0:
				for k in per:
					if bones[v * per + k] == hb:
						bones[v * per + k] = nb
		a[Mesh.ARRAY_BONES] = bones
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		out.surface_set_material(si, src.surface_get_material(si))
	return [out, skin]


# ---------------------------------------------------------------- 動き

func _physics_process(dt: float) -> void:
	var host := get_parent() as Node3D
	var pos := host.global_position
	var b: Basis
	if act == Act.RIDE and sled:
		b = sled.global_basis.orthonormalized()
		_yaw = b.get_euler().y
	else:
		var f := facing if facing != Vector3.ZERO else -host.global_basis.z
		f.y = 0
		if f.length() > 0.01:
			_yaw = lerp_angle(_yaw, atan2(-f.x, -f.z), 1.0 - exp(-dt * 14.0))
		b = Basis(Vector3.UP, _yaw)
	global_transform = Transform3D(b, pos)

	# 歩みは進んだ道のりで刻む（足と地面のずれを小さく）
	if _last == Vector3.INF:
		_last = pos
	var d := pos - _last
	d.y = 0
	_last = pos
	var v := d.length() / dt
	if v > 25.0:
		v = 0.0
		d = Vector3.ZERO
	_speed = lerpf(_speed, v, 1.0 - exp(-dt * 8.0))
	_phase += TAU * d.length() / maxf(_speed / CADENCE, 0.5) / _scale

	var fi := frame_index()
	if fi != _frame:
		_frame = fi
		_pose()
	_hold_hands()
	_apply()


## 骨の座標の空間での、世界の点
func _to_skel(world: Vector3) -> Vector3:
	return skel.global_transform.affine_inverse() * world


func _pose() -> void:
	var t := float(_frame) / FPS
	_reset()
	_hold = [null, null]
	var stride := maxf(_speed / CADENCE, 0.5) / _scale
	var leg := absf(_head_of(_id("thigh.R")).y - _head_of(_id("foot.R")).y) if _id("foot.R") >= 0 else 0.5
	var amp := asin(clampf(stride / (4.0 * maxf(leg, 0.1)), 0.0, 0.7)) if _speed > 0.25 else 0.0
	var ph := _phase
	var bend := 0.0
	var X := Vector3.RIGHT
	var Z := Vector3.BACK

	match act:
		Act.RIDE:
			# ソリに座る。腰を落とし、脚は前へ。両手はソリの縁
			# 裾は縦につぶして座面に広げ、脚は前へ投げ出す（足先は座面の高さ）
			# 裾は腰の骨の付け根へ向かってつぶれるので、その付け根を座面のすぐ上に。
			# 脚の付け根が腰の骨よりずっと低い人形（③）は、脚が座布団に埋もれてケープに隠れる
			_hips_drop = _sit_drop()
			_squash = 0.12
			_update_all()
			for s in ["L", "R"]:
				_turn_axis("thigh." + s, X, 1.5)
				_turn_axis("shin." + s, X, -0.25)
			bend = -lean.y * 0.3
			_turn_axis("chest", Z, -lean.x * 0.3)
			if sled:
				var me: Vector3 = sled.to_local(global_position)
				_hold[0] = [sled, Vector3(-0.68, 0.5, me.z - 0.1)]
				_hold[1] = [sled, Vector3(0.68, 0.5, me.z - 0.1)]
		_:
			if airborne:
				for s in ["L", "R"]:
					_turn_axis("thigh." + s, X, 0.5 if s == "L" else 0.15)
					_turn_axis("shin." + s, X, -0.9)
			elif amp > 0.0:
				for k in 2:
					var s: String = ["L", "R"][k]
					var p := ph + PI * k
					_turn_axis("thigh." + s, X, amp * sin(p))
					_turn_axis("shin." + s, X, -(0.08 + (0.45 + amp) * maxf(0.0, cos(p))))
					_turn_axis("upper_arm." + s, X, -amp * 0.8 * sin(p))
				_hips_drop = leg * (1.0 - cos(amp * absf(sin(ph)))) + 0.005
				_update_all()
				bend = 0.04 + 0.03 * minf(_speed, 6.0)
				_turn_axis("chest", Vector3.UP, 0.12 * amp * sin(ph))
			else:
				# 立ち止まり: 重心をゆっくり左右に、息で胸が少し上下
				_turn_axis("hips", Z, 0.03 * sin(t * 1.4))
				_turn_axis("chest", Z, -0.02 * sin(t * 1.4))
				bend = 0.02 * sin(t * 2.2)

			if act == Act.PUSH and sled and grip != Vector3.INF:
				var pts := _grip_points()
				_hold[0] = [sled, pts[0]]
				_hold[1] = [sled, pts[1]]
				for s in ["L", "R"]:
					_turn_axis("thigh." + s, X, -0.25)
					_turn_axis("shin." + s, X, -0.2)
				if effort and amp == 0.0:
					# 動かないソリを押している: 足を前後に踏ん張る
					var k := 1.0 if (_frame / 6) % 2 == 0 else -1.0
					_turn_axis("thigh.L", X, 0.15 * k)
					_turn_axis("thigh.R", X, -0.15 * k)
				bend = 0.45
			elif act == Act.ROPE:
				if rope_hand != Vector3.INF:
					_hold[1] = [self, to_local(rope_hand)]
				if effort:
					bend += 0.3

	_turn_axis("chest", X, -bend)

	if point != Vector3.INF:
		# 指さし: 指す所に近い側の腕をまっすぐ伸ばして指す（指は分けず、腕で指す）。
		# ソリをつかんでいても、その手は離して指す。胸も少しそちらへ回す
		var lp := global_basis.inverse() * (point - global_position)
		var side := "R" if lp.x >= 0.0 else "L"
		var ui := _id("upper_arm." + side)
		var sh := skel.global_transform * _head_of(ui)
		var dir := (point - sh).normalized()
		var local_dir := global_basis.inverse() * dir
		_turn_axis("chest", Vector3.UP, clampf(atan2(-local_dir.x, -local_dir.z), -0.8, 0.8) * 0.3)
		sh = skel.global_transform * _head_of(ui)
		var reach := (_len(ui) + _len(_id("forearm." + side)) + _len(_id("hand." + side)) * 0.5) * _scale * 0.98
		_hold[1 if side == "R" else 0] = [self, to_local(sh + dir * reach)]

	if waving and _hold[1] == null:
		# 右手を上げて振る。4 コマで 1 往復
		var k: float = [0.55, 0.1, -0.35, 0.1][_frame % 4]
		_aim(_id("upper_arm.R"), Vector3(0.7, 0.65, -0.15))
		_aim(_id("forearm.R"), Vector3(0.25 + k * 0.6, 1.0, -0.1))

	# 頭は見ている所へ
	var hi := _id("head")
	if hi >= 0:
		var hp := skel.global_transform * _head_of(hi)
		# 見ている所が決まっていなければ、指している所を見る（あなたは顔と指さしを別々に向けられる）
		var look := gaze if gaze != Vector3.INF else (point if point != Vector3.INF else hp + global_basis * Vector3(0, -0.05, -1))
		# 顔の向きは相互行為の手がかり。首と頭で大きく回し、届かない分は胸も少し回す
		var ld := (skel.global_transform.basis.inverse() * (look - hp)).normalized()
		var yaw_all := atan2(-ld.x, -ld.z)
		var yaw := clampf(yaw_all, -1.3, 1.3)
		var pitch := clampf(atan2(ld.y, Vector2(ld.x, ld.z).length()), -0.9, 0.75) + bend * 0.7
		if _voice > 0:
			pitch = minf(pitch + 0.3, 0.85)
		_turn_axis("chest", Vector3.UP, clampf(yaw_all, -1.6, 1.6) * 0.15)
		_turn_axis("neck", Vector3.UP, yaw * 0.4)
		_turn_axis("head", Vector3.UP, yaw * 0.6)
		# うなずく向きは、首を回したあとの頭の横の軸で（横を向いたまま上下を見ても頭が傾かない）
		var right: Vector3 = (_g[hi] as Transform3D).basis.x.normalized()
		_turn(hi, Quaternion(right, pitch))

	# クレイアニメの揺れ: 骨ごとに、コマごとにわずかに
	_rng.seed = hash(Vector2i(_frame, get_instance_id()))
	for i in _order:
		_turn(i, Quaternion.from_euler(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * BOIL))

	# 腕の、伸ばし直す前の回転を覚えておく
	_arm_base.clear()
	for s in ["L", "R"]:
		for n in ["upper_arm.", "forearm.", "hand."]:
			var i := _id(n + s)
			if i >= 0:
				_arm_base[i] = _rot[i]

	# 声と白い息
	if _voice > 0:
		if _voice == 7:
			_puff(1.7, 1.3)
			_next_breath = _frame + 30
		_voice -= 1
	elif _frame >= _next_breath:
		_puff(1.0, 0.5)
		_next_breath = _frame + (22 if effort else 38) + _rng.randi_range(-4, 4)


## つかんでいる手は、つかんだ物に対してコマの姿勢を保つ（毎物理フレーム、腕を伸ばし直す）
func _hold_hands() -> void:
	if _hold[0] == null and _hold[1] == null:
		return
	for i in _arm_base:
		_rot[i] = _arm_base[i]
	_update_all()
	for k in 2:
		var h = _hold[k]
		if h == null:
			continue
		var space: Node3D = h[0]
		_reach("L" if k == 0 else "R", _to_skel(space.to_global(h[1])))


## つかんでいる立ち位置から、ソリの縁に置く両手の所（ソリの座標）
func _grip_points() -> Array:
	var hx: float = sled.HALF.x
	var hz: float = sled.HALF.y
	var g := grip
	var e := Vector3(clampf(g.x, -hx, hx), 0, clampf(g.z, -hz, hz))
	var inward := e - g
	inward.y = 0
	inward = inward.normalized() if inward.length() > 0.01 else Vector3.FORWARD
	var right := inward.cross(Vector3.UP)
	var pts := []
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var p := e + right * s * 0.2
		p.x = clampf(p.x, -hx, hx)
		p.z = clampf(p.z, -hz, hz)
		if p.z > hz - 0.25:
			p.y = 0.95
			p.z = 1.3
		else:
			p.y = 0.48
		pts.append(p)
	return pts


# ---------------------------------------------------------------- 足もとの影

## 足もとに、やわらかい丸い影を落とす（雪の上に立っている感じ。乗っているときはソリの台に落ちる）。
## 雪が明るく空の光も強いので、太陽の影だけでは足もとが浮いて見える。影は雪の影と同じ青み
func _make_foot_shadow() -> void:
	var r: float = FOOT_SHADOW[kind] * _scale
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.85, 1.0])
	g.colors = PackedColorArray([Color(0.08, 0.1, 0.2, 0.85), Color(0.08, 0.1, 0.2, 0.75), Color(0.08, 0.1, 0.2, 0.3), Color(0.08, 0.1, 0.2, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var d := Decal.new()
	d.size = Vector3(r * 2.0, 0.36, r * 2.0)   # 薄い箱: 足の甲より上には届かない
	d.texture_albedo = tex
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.position = Vector3(0, 0.02, 0)
	add_child(d)


# ---------------------------------------------------------------- 白い息

## 白い息はちぎった綿。カメラを向く板に、コードで作った綿の形（中はふわっと濃く、縁は繊維のようにほつれる）を貼る。
## 人の姿勢ではないので、12 コマにせずなめらかに流す。太陽の側はほんのり明るい生成り、影の側は雪の影の青
const BREATH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D cotton : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 warm : source_color = vec3(0.98, 0.95, 0.89);
uniform vec3 cool : source_color = vec3(0.58, 0.66, 0.82);
uniform vec3 sun_dir = vec3(-0.5, -0.6, -0.6);   // 光の進む向き（世界）

varying float spin;
varying vec2 sun2;
varying vec2 cell;   // 綿の形は 4 つ（2x2 に並べた画像）。粒ごとに選ぶ

void vertex() {
	// 板はいつもカメラを向き、大きさは粒ごとの大きさのまま。回すのは綿の形だけ（光の向きを画面に合わせるため）
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	spin = INSTANCE_CUSTOM.x;
	cell = vec2(float(INSTANCE_ID % 2), float((INSTANCE_ID / 2) % 2));
	vec3 s = (VIEW_MATRIX * vec4(-normalize(sun_dir), 0.0)).xyz;
	sun2 = length(s.xy) > 0.001 ? normalize(s.xy) : vec2(0.0, 1.0);
}

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(spin), sn = sin(spin);
	vec2 q = vec2(c * p.x - sn * p.y, sn * p.x + c * p.y) + 0.5;
	float inside = step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	vec4 t = texture(cotton, (clamp(q, 0.0, 1.0) + cell) * 0.5);
	t.a *= inside;
	// 太陽の側（板の中で光の来る向き）ほど明るく、厚い所ほど影の青が残る
	float side = dot(normalize(p * vec2(1.0, -1.0) + 1e-4), sun2) * smoothstep(0.0, 0.35, length(p));
	float lit = clamp(0.6 + 0.45 * side - 0.4 * t.r, 0.0, 1.0);
	ALBEDO = mix(cool, warm, lit);
	ALPHA = t.a * COLOR.a;
}
"""

static var _cotton: ImageTexture


## 綿のひとかたまりの形（透明度）と厚み（赤）。外の画像は使わない。
## 本体はいくつかの丸いふくらみを重ねたでこぼこの塊、縁はくねった細かい繊維がほつれる
static func cotton_texture() -> Texture2D:
	if _cotton:
		return _cotton
	var n := 160
	var atlas := Image.create(n * 2, n * 2, false, Image.FORMAT_RGBA8)
	for k in 4:
		atlas.blit_rect(_cotton_tuft(n, k), Rect2i(0, 0, n, n), Vector2i((k % 2) * n, (k / 2) * n))
	atlas.generate_mipmaps()
	_cotton = ImageTexture.create_from_image(atlas)
	return _cotton


static func _cotton_tuft(n: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21 + seed * 17
	var blobs := []
	var count := rng.randi_range(7, 12)
	for i in count:
		var c := Vector2(rng.randf_range(-0.38, 0.38), rng.randf_range(-0.3, 0.3))
		blobs.append([c, rng.randf_range(0.1, 0.25)])
	var dens := FastNoiseLite.new()
	dens.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dens.frequency = 3.0
	dens.fractal_octaves = 4
	dens.seed = 5 + seed
	var warp := FastNoiseLite.new()
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.frequency = 2.5
	warp.seed = 9 + seed
	var fib := FastNoiseLite.new()
	fib.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fib.frequency = 1.0
	fib.fractal_octaves = 3
	fib.seed = 13 + seed
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var f := 0.0
			for bl in blobs:
				var d: float = (p - bl[0]).length() / bl[1]
				f += exp(-d * d)
			var dn := 0.5 + 0.5 * dens.get_noise_2d(p.x, p.y)
			var body := smoothstep(0.25, 1.3, f * (0.45 + 1.1 * dn)) * (0.45 + 0.55 * dn)
			# 繊維: くねらせた座標で、細かい筋（一方向に引き伸ばす）
			var q := p + 0.18 * Vector2(warp.get_noise_2d(p.x, p.y), warp.get_noise_2d(p.x + 40.0, p.y))
			var strand := 0.5 + 0.5 * fib.get_noise_2d(q.x * 6.0, q.y * 26.0)
			var fringe := smoothstep(0.02, 0.35, f) * pow(strand, 2.0)
			var alpha := clampf(maxf(body, fringe * 0.8) * (1.0 - smoothstep(0.85, 1.0, p.length())), 0.0, 1.0)
			img.set_pixel(x, y, Color(body, 1, 1, alpha))
	return img


func _make_breath() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	_breath = CPUParticles3D.new()
	_breath.emitting = false
	_breath.one_shot = true
	_breath.local_coords = false
	_breath.amount = 4
	_breath.lifetime = 2.4
	_breath.explosiveness = 0.55
	_breath.randomness = 0.6
	_breath.direction = Vector3(0, 0.2, -1)
	_breath.spread = 16.0
	_breath.gravity = Vector3(0, 0.1, 0)
	_breath.damping_min = 0.5
	_breath.damping_max = 0.9
	# 粒ごとに向き・回り方・大きさをばらつかせる
	_breath.angle_min = 0.0
	_breath.angle_max = 360.0
	_breath.angular_velocity_min = -25.0
	_breath.angular_velocity_max = 25.0
	_breath.scale_amount_min = 0.7
	_breath.scale_amount_max = 1.3
	var curve := Curve.new()   # ふくらみながらほどける
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.35, 0.75))
	curve.add_point(Vector2(1.0, 1.6))
	_breath.scale_amount_curve = curve
	var ramp := Gradient.new()   # すっと現れて、ゆっくり薄くなる
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	_breath.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	var sh := Shader.new()
	sh.code = BREATH_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("cotton", cotton_texture())
	var sun := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	if not sun.is_empty():
		mat.set_shader_parameter("sun_dir", -(sun[0] as Node3D).global_basis.z)
	quad.material = mat
	_breath.mesh = quad
	_breath.layers = 1   # 息は誰の画面にも映す
	_breath.position = MOUTH[kind]
	att.add_child(_breath)
	_breaths.append(_breath)
	var second := _breath.duplicate() as CPUParticles3D
	att.add_child(second)
	_breaths.append(second)


## size 1 がふだんの小さな息。声を出したときは大きく、数も多く、勢いよく
func _puff(size: float, speed: float) -> void:
	_breath = _breaths[_next_out]
	_next_out = (_next_out + 1) % _breaths.size()
	var big := size > 1.2
	_breath.amount = 7 if big else 4
	_breath.scale_amount_min = 0.7 * size
	_breath.scale_amount_max = 1.3 * size
	_breath.initial_velocity_min = 0.25 * speed + 0.15
	_breath.initial_velocity_max = 0.5 * speed + 0.2
	_breath.lifetime = 3.0 if big else 2.4
	_breath.restart()
