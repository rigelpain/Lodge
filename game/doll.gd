extends Node3D

const Look := preload("res://look.gd")
const FpHands := preload("res://fp_hands.gd")
const Palm := preload("res://palm.gd")
## 人形（person/build_dolls.py で作り、骨を入れて焼いた glb）を骨で動かす。
## 3 体: kasa 笠と千代紙の人形 / origami 多面体の折り紙の人 / news 新聞紙と麻布の人形。骨の名前は 3 体で同じ。
## 居場所（位置と向き）は毎フレームなめらか。姿勢（骨の向き）は 12 コマ／秒で刻み、コマの間は止める。
## 全員が同じ時計（物理のコマ数）でコマを変え、そのたびに骨をわずかに揺らす（クレイアニメの揺れ）。
## ソリや紐をつかむ手は、つかんだ物に対しての姿勢をコマで決め、毎フレーム腕を伸ばし直す（ソリが動いても手が離れない）。
## 見た目だけ。持ち主（player.gd・bot.gd）が毎フレーム act などを入れる。通信には乗せない。
## 身ぶり（emotes.gd の出来事）は play() で受け、出来事のコマから数えたコマ数で姿勢を決める（全員の画面で同じコマに同じ形）。

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
## 頭のいちばん上（glb の座標、人形の大きさのまま）。雪玉の当たりの背丈と、ハイタッチの手の高さに
const TOP := {"kasa": 1.372, "origami": 1.49, "news": 0.955}
const BALL_R := 0.075        # 雪玉の半径 (m)
## 米袋の動きのコマ数（12 コマ／秒）。乗る・降りるは押した瞬間に済んでいて、見た目だけがこのコマで追いつく
## （乗り込みの途中でも滑り出せる。足で蹴ると、残りを飛ばしてすぐ座る）
##   out: 0 右手を帯へ / 1 引き抜いて胸の前で両手に / 2 ばさっと前へ広げて落とす / 3 しゃがむ / 4 腰を下ろす（ぽふっ） / 5〜 座って紐を握る
##   in:  0〜1 腰を上げてかがむ / 2〜6 くるくる丸める / 7 跳ねた包みを受ける / 8 帯へ / 9 しまった
const SACK_OUT := 7
const SACK_IN := 10
## 帯の米袋の所（glb の座標、人形の大きさのまま）。右の腰の少し後ろ
const BELT := {"kasa": Vector3(0.2, 0.6, 0.05), "origami": Vector3(0.21, 0.8, 0.06), "news": Vector3(0.24, 0.34, 0.06)}

enum Act { WALK, PUSH, ROPE, RIDE }

var kind := "kasa"
var layers := 1

# 持ち主が毎フレーム入れる
var act := Act.WALK
var facing := Vector3.ZERO   # 体の向き（世界、水平）。ZERO なら持ち主の前
var gaze := Vector3.INF      # 見ている所（世界）
var effort := false
var dragged := false
var _kick_frame := -100      # 足で雪を蹴ったコマ（米袋。kick が入れる）
var _kick_leg := "R"         # ソリに引きずられている（足を前へ突っ張り、体はソリへ引かれて前に傾く）
var sack_anim := ""          # 米袋の動き（sack_start が入れる）: "out" 帯から取り出して広げ、座る / "in" 立って丸め、帯に戻す
var _sack_frame := -100      # その動きが始まったコマ
var belt_sack := false       # 帯に丸めた米袋を下げている（持ち主が毎フレーム入れる）
var belt_color := Color("B8402E")
var _roll: Node3D            # 丸めた米袋（帯か右手）
var _roll_hip: Node3D
var _roll_hand: Node3D
var airborne := false
var waving := false
var point := Vector3.INF     # 腕を伸ばして指す所（世界）。gaze が決まっていなければ、そこを見る
var sled: Node3D = null
var grip := Vector3.INF      # つかんでいる立ち位置（ソリの座標）
var rope_hand := Vector3.INF # 紐を持つ右手の所（世界）
var lean := Vector2.ZERO     # 乗っているときの体重移動（x 右、y 前）
var holding_ball := false    # 右手に雪玉を持っている
var emote := {}              # いまの身ぶり（emotes.gd の出来事）。終わると空になる
var crouch := false          # しゃがんでいる（持ち主が毎フレーム入れる）
var hand_shapes := ["", ""]  # 掲げている手の高さ [右手, 左手]（"high" 高い手のひら、"low" 低い手のひら、"" は下ろす）
var point_sides := []        # 指さす手（1 右、-1 左。両方なら両腕）。空なら、指す所に近い側

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
var _long: CPUParticles3D    # 深呼吸の長い息
var _ball: Node3D            # 右手の雪玉
var _shapes := {}            # 手の形のアップリケ: 形 → {1: 右手, -1: 左手}
var _palm_goal := {}         # 側 → [形, 手形の置き所（人形の座標）]。コマで決め、腕はその手首へ伸ばす
var _hands_frame := 0        # 手の形を変えたコマ（ぽんと出る大きさに）
var _em_head := Vector2.ZERO # 身ぶりが頭に足す向き（x 左右、y 上下）
var _em_roll := 0.0          # 身ぶりが頭に足す傾き（首をかしげる。正で右へ）


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
	_make_long_breath()
	_make_ball()
	_make_roll()
	_shapes = Palm.make_set(Color(FpHands.STYLE.get(kind, FpHands.STYLE["kasa"]).hand), layers)
	for sh in _shapes:
		for n in _shapes[sh].values():
			add_child(n)
	_make_foot_shadow()
	_measure_body(inst)
	_next_breath = randi_range(4, 30)


# ---------------------------------------------------------------- 体の形（雪玉の当たり）

const BODY_BANDS := 12       # 体を高さで切る数
static var _body_cache := {} # 人形の種類 → [各段の太さ (m), 頭のてっぺん (m), 頭の骨の高さ (m)]


## 立った人形の形から、高さごとの太さ（体の軸からの横の広がり）を測る。笠のつば・着物の裾・頭巾の形がそのまま入る。
## 袖や髪の先の細いはみ出しは除く（各段で 9 割の点が入る太さ）。人形の種類ごとに一度だけ測る
func _measure_body(inst: Node3D) -> void:
	if _body_cache.has(kind):
		return
	var pts := PackedVector3Array()
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var to_doll := global_transform.affine_inverse() * mi.global_transform
		for si in mi.mesh.get_surface_count():
			# 頂点だけでは、着物の裾のような大きな平たい面の途中が抜ける。面の上に 5 cm ほどおきに点を打つ
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			for t in range(0, idx.size() - 2, 3):
				var a := to_doll * vs[idx[t]]
				var b := to_doll * vs[idx[t + 1]]
				var c := to_doll * vs[idx[t + 2]]
				var n := clampi(ceili(maxf(maxf(a.distance_to(b), b.distance_to(c)), c.distance_to(a)) / 0.05), 1, 24)
				for i in n + 1:
					for j in n + 1 - i:
						pts.append(a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n))
	var top := 0.0
	for v in pts:
		top = maxf(top, v.y)
	var bands := []
	for i in BODY_BANDS:
		bands.append([])
	for v in pts:
		var bi := clampi(int(v.y / top * BODY_BANDS), 0, BODY_BANDS - 1)
		bands[bi].append(Vector2(v.x, v.z).length())
	var radii := PackedFloat32Array()
	for b in bands:
		b.sort()
		radii.append(b[int(b.size() * 0.9)] if not b.is_empty() else 0.0)
	var head_y := (global_transform.affine_inverse() * (skel.global_transform * skel.get_bone_global_rest(_id("head")).origin)).y
	_body_cache[kind] = [radii, top, head_y]


## 点 p（世界）が、いまの体の形の中（r だけふくらませて）に入るか。しゃがむ・座ると、頭の骨の下がった分だけ縮める
func body_hit(p: Vector3, r: float) -> bool:
	var c: Array = _body_cache.get(kind, [])
	if c.is_empty():
		return false
	var radii: PackedFloat32Array = c[0]
	var top: float = c[1]
	var head_now := (skel.global_transform * _head_of(_id("head"))).y - global_position.y
	var squash := clampf(head_now / maxf(c[2], 0.01), 0.3, 1.2)
	var dy := (p.y - global_position.y) / squash
	if dy < -r or dy > top + r:
		return false
	var bi := clampi(int(dy / top * BODY_BANDS), 0, BODY_BANDS - 1)
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < radii[bi] + r


static func frame_index() -> int:
	return Engine.get_physics_frames() * FPS / Engine.physics_ticks_per_second


## 声を出す（言葉にならない声）。少し見上げて、大きな白い息が出る（持ち主のいない見本用。ゲームでは「ワ〜」の身ぶり）
func call_out() -> void:
	play({"kind": "wa", "frame": frame_index() + 1})


## 身ぶりを始める。出来事のコマ（ev.frame）から数えて姿勢を決める。手の形は、身ぶりとは別に下ろすまで続く
func play(ev: Dictionary) -> void:
	if ev.kind == "hands":
		var h: Array = Palm.HANDS.get(ev.hands, ["", ""])
		hand_shapes = [h[0], h[1]]
		_hands_frame = int(ev.frame)
		return
	if ev.kind == "breath_end":
		if emote.get("kind", "") == "breath":
			emote["until"] = int(ev.frame)   # 吐くのをやめる（少しで胸が戻る）
		return
	emote = ev


## 頭のてっぺんの高さ (m)
func height() -> float:
	return TOP.get(kind, 1.3) * _scale


## 乗ったまま足で雪を蹴る（side 1 右足、-1 左足）。次のコマから 3 コマ
func kick(side: int) -> void:
	_kick_frame = frame_index() + 1
	_kick_leg = "R" if side > 0 else "L"
	if sack_anim == "out":
		_sack_frame = mini(_sack_frame, frame_index() + 1 - 5)   # 乗り込みの途中で蹴ったら、すぐ座った姿に


## 米袋の動きを始める（what: "out" 取り出して乗る / "in" 立って丸めてしまう）。次のコマから
func sack_start(what: String) -> void:
	sack_anim = what
	_sack_frame = frame_index() + 1


## 米袋の動きの、始まってからのコマ数。その動きでなければ（終わっていれば）-1
func sack_k(what: String) -> int:
	if sack_anim != what:
		return -1
	var k := frame_index() - _sack_frame
	if k >= (SACK_OUT if what == "out" else SACK_IN):
		sack_anim = ""
		return -1
	return maxi(k, 0)


## 乗っていて、もう腰を下ろしているか（取り出して広げているあいだは立っている）。一人称の目の高さに使う
func sack_seated() -> bool:
	var k := sack_k("out")
	return act == Act.RIDE and (k < 0 or k >= 3)


## いまの身ぶりの種類と、始まってからのコマ数。身ぶりがなければ ["", -1]
func emote_now() -> Array:
	if emote.is_empty():
		return ["", -1]
	return [emote.kind, frame_index() - int(emote.frame)]


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
func _reach(side: String, target: Vector3, to_wrist := false) -> void:
	var up := _id("upper_arm." + side)
	var fo := _id("forearm." + side)
	if up < 0 or fo < 0:
		return
	var s := _head_of(up)
	var a := _len(up)
	# 手首（前腕の先）を合わせるか、手のなかほどを合わせるか
	var b := _len(fo) + (0.0 if to_wrist else _len(_id("hand." + side)) * 0.5)
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
	_place_shapes()


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
	if dragged and act == Act.PUSH:
		amp = 0.0   # 引きずられているときは歩かない（足は雪をすべる）
	var ph := _phase
	var bend := 0.0
	var X := Vector3.RIGHT
	var Z := Vector3.BACK

	match act:
		Act.RIDE:
			var sk := sack_k("out")
			if sk >= 0 and sk < 3:
				bend = _sack_draw(sk)   # 米袋をまだ取り出して広げている（立ったまま）
			else:
				# ソリに座る。腰を落とし、脚は前へ。両手はソリの縁（米袋は前の紐）
				# 裾は縦につぶして座面に広げ、脚は前へ投げ出す（足先は座面の高さ）
				# 裾は腰の骨の付け根へ向かってつぶれるので、その付け根を座面のすぐ上に。
				# 脚の付け根が腰の骨よりずっと低い人形（③）は、脚が座布団に埋もれてケープに隠れる
				var sack: bool = sled != null and sled.get("kind") == "sack"
				var half := sk == 3   # しゃがんで、腰を下ろす途中
				_hips_drop = _sit_drop() * (0.55 if half else 1.0)
				_squash = 0.55 if half else 0.12
				_update_all()
				for s in ["L", "R"]:
					var kk := _frame - _kick_frame
					if kk >= 0 and kk < 3 and s == _kick_leg:
						# 足で雪を蹴る（米袋）: 横から下へ伸ばし（0）、後ろへ蹴り（1）、引き戻す（2）
						_turn_axis("thigh." + s, X, [0.7, 0.2, 0.9][kk])
						_turn_axis("shin." + s, X, [-0.5, -0.1, -0.6][kk])
						_turn_axis("thigh." + s, Z, (0.25 if s == "R" else -0.25) * [1.0, 1.0, 0.5][kk])
						continue
					if half:
						_turn_axis("thigh." + s, X, 1.05)
						_turn_axis("shin." + s, X, -1.55)
					elif sack:
						# 米袋は低いので、膝を少し立てて足先を袋の前の縁へ（脚が見えて、座っているとわかる）
						_turn_axis("thigh." + s, X, 2.0)
						_turn_axis("shin." + s, X, -1.2)
					else:
						_turn_axis("thigh." + s, X, 1.5)
						_turn_axis("shin." + s, X, -0.25)
				bend = -lean.y * 0.3 - (0.3 if sack and not half else 0.0)   # 米袋では少し後ろへもたれる
				_turn_axis("chest", Z, -lean.x * 0.3)
				if sled and sack:
					# 米袋: 前の紐を両手で握り、少し引き寄せる
					var me: Vector3 = sled.to_local(global_position)
					_hold[0] = [sled, Vector3(-0.13, me.y + 0.16, me.z - 0.36)]
					_hold[1] = [sled, Vector3(0.13, me.y + 0.16, me.z - 0.36)]
				elif sled:
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
				if dragged:
					# 引きずられている: 体勢が崩れている。体ごとソリへ前のめりに引かれ、片足を前へ突っ張ってかかとですべり、
					# もう片足は後ろに残って膝が折れる。左右によろけ、左手はソリを離して宙をかく（右手だけでしがみつく）。
					# ときどき膝ががくっと抜けて沈む。揺れはコマ（12 fps）で刻むので、人によってずらす（_rng の種）
					var f := _frame + int(_scale * 97.0)
					var sway := sin(f * 0.55) * 0.22 + (0.06 if f % 2 == 0 else -0.06)   # よろけ（ゆっくり）＋ 雪のでこぼこ（コマごと）
					var buckle := 1.0 if f % 14 < 3 else 0.0                           # 膝が抜ける 3 コマ
					_turn_axis("hips", X, -0.55 - 0.12 * buckle)
					_turn_axis("hips", Z, sway * 0.6)
					_turn_axis("thigh.L", X, 0.75 + 0.1 * sin(f * 1.3))
					_turn_axis("shin.L", X, -0.05)
					_turn_axis("thigh.R", X, -0.35 + 0.5 * buckle)
					_turn_axis("shin.R", X, -0.9 - 0.4 * buckle)
					_turn_axis("chest", Z, -sway)
					_turn_axis("chest", Vector3.UP, 0.25 * sin(f * 0.4))
					_hips_drop = 0.06 + 0.1 * buckle
					_update_all()
					# 左手はソリを離し、肩の上から外へ、大きな輪を描いて宙をかく
					var h := height()
					var swing := f * 0.9
					_hold[0] = [self, Vector3(-0.42 - 0.12 * cos(swing), h * 0.78 + 0.22 * sin(swing), -0.05 + 0.2 * cos(swing * 0.5))]
					bend = 0.75 + 0.15 * buckle
			elif act == Act.ROPE:
				if rope_hand != Vector3.INF:
					_hold[1] = [self, to_local(rope_hand)]
				if effort:
					bend += 0.3

	var si := sack_k("in")
	if si >= 0 and act != Act.RIDE:
		bend = _sack_stow(si)

	var em := _emote_k()
	if crouch and act != Act.RIDE and em[0] != "make_ball":
		bend += _crouch_legs(1.0) * 0.6
	if em[1] >= 0:
		bend += _emote_body(em[0], em[1])
	if em[0] != "breath" and em[0] != "oi":
		_long.emitting = false
	_turn_axis("chest", X, -bend)

	if point != Vector3.INF:
		# 指さし: 選んだ手の腕をまっすぐ伸ばして指す（両手なら両腕で「あっち！」）。手の先には指さしの手形。
		# 選んでいなければ、指す所に近い側。ソリをつかんでいても、その手は離して指す。胸も少しそちらへ回す
		var lp := global_basis.inverse() * (point - global_position)
		var sides: Array = point_sides if not point_sides.is_empty() else [1 if lp.x >= 0.0 else -1]
		var turned := false
		for sd in sides:
			var side := "R" if sd > 0 else "L"
			var ui := _id("upper_arm." + side)
			var sh := skel.global_transform * _head_of(ui)
			var dir := (point - sh).normalized()
			if not turned:
				var local_dir := global_basis.inverse() * dir
				_turn_axis("chest", Vector3.UP, clampf(atan2(-local_dir.x, -local_dir.z), -0.8, 0.8) * 0.3 / sides.size())
				turned = true
			sh = skel.global_transform * _head_of(ui)
			dir = (point - sh).normalized()
			var reach := (_len(ui) + _len(_id("forearm." + side)) + _len(_id("hand." + side)) * 0.5) * _scale * 0.98
			_hold[1 if side == "R" else 0] = [self, to_local(sh + dir * reach)]

	if em[1] >= 0:
		_emote_arms(em[0], em[1])
	_plan_palms(em[0], em[1])
	if em[1] < 0 and waving and _hold[1] == null and hand_shapes[0] == "":
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
		yaw = clampf(yaw + _em_head.x, -1.4, 1.4)
		pitch = clampf(pitch + _em_head.y, -1.2, 0.95)
		_turn_axis("chest", Vector3.UP, clampf(yaw_all, -1.6, 1.6) * 0.15)
		_turn_axis("neck", Vector3.UP, yaw * 0.4)
		_turn_axis("head", Vector3.UP, yaw * 0.6)
		# うなずく向きは、首を回したあとの頭の横の軸で（横を向いたまま上下を見ても頭が傾かない）
		var right: Vector3 = (_g[hi] as Transform3D).basis.x.normalized()
		_turn(hi, Quaternion(right, pitch))
		if absf(_em_roll) > 1e-4:
			# 首をかしげる: 顔の向きの軸のまわりに傾ける
			var face: Vector3 = (_g[hi] as Transform3D).basis.z.normalized()
			_turn(hi, Quaternion(face, -_em_roll))

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

	if em[1] >= 0:
		_emote_breath(em[0], em[1])
	# 雪玉は、作っている途中は大きくなりながら、できたら右手に
	var ball_k: float = 0.0
	if em[0] == "make_ball" and em[1] >= 4:
		ball_k = clampf((em[1] - 4) / 12.0, 0.0, 1.0) * 0.6 + 0.4
	elif holding_ball:
		ball_k = 1.0
	_ball.visible = ball_k > 0.0
	_ball.scale = Vector3.ONE * maxf(ball_k, 0.01)
	_place_roll()

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
		if h == null or not is_instance_valid(h[0]):   # 握っていたソリが消えた（米袋を帯に戻した）ら、次のコマまで握らない
			continue
		var space: Node3D = h[0]
		_reach("L" if k == 0 else "R", _to_skel(space.to_global(h[1])), h.size() > 2 and h[2])


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
	d.layers = layers   # 自分の影は、自分の体と同じ層（一人称では、しゃがんで足もとを見ても映らない）
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
	_breath.layers = 1 | layers   # 息は誰の画面にも映す（自分の息は、自分の体の層にも入れて右下の小窓に映す）
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


# ---------------------------------------------------------------- 身ぶり（emotes.gd）
# どれも「ため → 解放」。ためは短く小さく、解放で大きく。形はコマごとに決め、コマの間は止める。
# 向きは骨の座標の空間で、右手側（R）で書く。左手は x を裏返す

## emotes.gd の KINDS と同じ長さ（コマ）。0 は終わりを持ち主が決める
const EMOTE_FRAMES := {
	"high_five": 12, "shake": 24, "whiff": 12, "breath": 0, "make_ball": 22, "windup": 0, "throw": 7,
	"hit": 16, "clap": 16, "wa": 14, "un": 7, "nn": 14, "huh": 16, "oi": 18,
}
## 腕を使う身ぶり。このあいだは手の形を出さない
const ARM_EMOTES := ["high_five", "shake", "whiff", "clap", "make_ball", "windup", "throw", "hit"]


## いまの身ぶりと、始まってからのコマ数（このコマ）。終わっていたら消す
func _emote_k() -> Array:
	_em_head = Vector2.ZERO
	_em_roll = 0.0
	if emote.is_empty():
		return ["", -1]
	var k := _frame - int(emote.frame)
	var n: int = EMOTE_FRAMES.get(emote.kind, 12)
	if emote.has("until") and _frame >= int(emote.until) + 8:
		n = maxi(1, k)
	if n > 0 and k >= n:
		emote = {}
		return ["", -1]
	if k < 0:
		return ["", -1]
	return [emote.kind, k]


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## しゃがむ（s 0 立つ〜1 しゃがみきる）。腰を落とし、膝を曲げる。返り値は胸を前へ曲げる量
func _crouch_legs(s: float) -> float:
	var X := Vector3.RIGHT
	var leg := absf(_head_of(_id("thigh.R")).y - _head_of(_id("foot.R")).y) if _id("foot.R") >= 0 else 0.5
	_hips_drop = leg * 0.42 * s
	_update_all()
	for side in ["L", "R"]:
		_turn_axis("thigh." + side, X, 1.25 * s)
		_turn_axis("shin." + side, X, -1.7 * s)
	return 0.5 * s


const INHALE := 5            # 吐く前に短く吸うコマ


## 吐く息の胸のふくらみ（0 ふだん〜1 吸いきった）。押した瞬間に短く吸い、押しているあいだゆっくり吐き、離すと戻る。
## ended は離したか、until_k は離したコマ（始まりから）
static func exhale_curve(k: int, ended: bool, until_k: int) -> float:
	if k < INHALE:
		return _ease(k / float(INHALE - 1))
	var b := 1.0 - 0.6 * clampf((k - INHALE) / 60.0, 0.0, 1.0)
	if ended and k >= until_k:
		b *= 1.0 - _ease((k - until_k) / 6.0)
	return b


func _exhale_now(k: int) -> float:
	return exhale_curve(k, emote.has("until"), int(emote.get("until", 0)) - int(emote.get("frame", 0)))


## 腰・脚・胸のひねり。返り値は胸を前へ曲げる量に足す。頭の向きは _em_head に
func _emote_body(kind_: String, k: int) -> float:
	var X := Vector3.RIGHT
	match kind_:
		"breath":
			# 吸うと胸がそり、頭が上がる。吐くあいだ、少しずつ戻る
			var s := _exhale_now(k)
			_em_head.y = 0.38 * s
			return -0.2 * s
		"make_ball":
			# しゃがむ → 両手で雪をぽんぽん → 立つ
			var s := _ease(k / 4.0) if k < 16 else (1.0 if crouch else 1.0 - _ease((k - 16) / 5.0))
			_em_head.y = -0.35 * s
			return _crouch_legs(s)
		"shake":
			# 握手: 少し前へかがみ、相手を見る
			_em_head.y = -0.08
			return 0.12
		"high_five", "whiff":
			var swing := k >= (2 if kind_ == "whiff" else 3)
			# 胸のひねり: 振る手の側へ（両手なら、ひねらない）
			var tw := 0.0
			if kind_ == "whiff":
				tw = float(emote.get("side", 1))
			elif emote.has("grips") and emote.grips.size() == 1:
				tw = float(emote.grips[0][0])
			if k < 7 and tw != 0.0:
				_turn_axis("chest", Vector3.UP, (0.3 if swing else -0.25) * tw)
			if kind_ == "whiff" and k >= 2 and k < 8:
				# 空振り: 振った勢いで前へよろける
				_turn_axis("thigh.L", X, 0.35)
				_turn_axis("shin.L", X, -0.3)
				_em_head.y = -0.2
				return 0.32
			if kind_ == "whiff" and k >= 8:
				_em_head.x = [0.25, -0.25, 0.15, 0.0][k - 8]   # 首をかしげる
			return 0.1 if swing else -0.05
		"windup":
			_turn_axis("chest", Vector3.UP, -0.4)
			_turn_axis("thigh.R", X, -0.2)
			_turn_axis("thigh.L", X, 0.2)
			return -0.1
		"throw":
			var f: float = [1.0, 1.0, 0.8, 0.5, 0.3, 0.15, 0.0][k]
			_turn_axis("chest", Vector3.UP, 0.4 * f)
			_turn_axis("thigh.L", X, 0.3 * f)
			_turn_axis("thigh.R", X, -0.25 * f)
			return 0.3 * f
		"hit":
			# のけぞる: 当たった向きへ胸が倒れ、片足がうしろへ。そのあと首をぶるぶる振って雪を払う
			var d := Vector3.BACK
			if emote.has("dir"):
				d = skel.global_transform.basis.inverse() * (emote.dir as Vector3)
				d.y = 0
				d = d.normalized() if d.length() > 0.01 else Vector3.BACK
			var f: float = [0.55, 0.6, 0.5, 0.45, 0.4, 0.35, 0.3, 0.2, 0.12, 0.08, 0.05, 0.03, 0.0, 0.0, 0.0, 0.0][k]
			if f > 0.0:
				_turn(_id("chest"), Quaternion(Vector3.UP.cross(d).normalized(), f))
			if k < 8:
				_turn_axis("thigh.R", X, -0.35 * f / 0.6)
				_em_head.y = 0.5 * f / 0.6
			elif k < 14:
				_em_head.x = 0.4 if k % 2 == 0 else -0.4
			return 0.0
		"wa":
			if k < 2:
				_em_head.y = -0.15
				return 0.1
			_em_head.y = 0.4 * (1.0 - _ease((k - 8) / 6.0))
			return -0.12 * (1.0 - _ease((k - 8) / 6.0))
		"un":
			_em_head.y = [-0.2, -0.45, -0.45, -0.2, -0.05, 0.0, 0.0][k]
		"nn":
			_em_head.x = [0.35, 0.35, -0.35, -0.35, 0.35, 0.35, -0.3, -0.3, 0.2, 0.2, -0.1, -0.1, 0.0, 0.0][k]
			_em_head.y = -0.08
		"oi":
			# 呼ぶ: 小さく息を吸ってかがみ（ため）、胸を張って顔を上げ、遠くへ声を届ける
			if k < 2:
				_em_head.y = -0.12
				return 0.12
			_em_head.y = 0.22 if k < 15 else 0.08
			return -0.12 if k < 15 else -0.04
		"huh":
			# 首をかしげる: 小さく引いて（ため）、ことんと横へ傾けて止め、ゆっくり戻す。肩も少しすくめる
			_em_roll = [-0.08, -0.08, 0.38, 0.45, 0.45, 0.45, 0.45, 0.45, 0.45, 0.42, 0.38, 0.3, 0.2, 0.12, 0.05, 0.0][k]
			_em_head.y = 0.06 if k >= 2 else 0.0
			_turn_axis("chest", Vector3.BACK, -_em_roll * 0.15)
		"clap":
			_em_head.y = 0.05
			return 0.05
	return 0.0


## 腕の向きを決める（右手側で書いた向き。左は x を裏返す）。その手のつかみは外す
func _arm(side: String, up_dir: Vector3, fore_dir: Vector3) -> void:
	var m := Vector3(-1, 1, 1) if side == "L" else Vector3.ONE
	_hold[0 if side == "L" else 1] = null
	_aim(_id("upper_arm." + side), up_dir * m)
	_aim(_id("forearm." + side), fore_dir * m)


## 手を、骨の座標の空間の所へ伸ばす（その手のつかみは外す）
func _hand_to(side: String, target: Vector3) -> void:
	_hold[0 if side == "L" else 1] = null
	_reach(side, target)


func _emote_arms(kind_: String, k: int) -> void:
	# 手を伸ばす所は、肩の所と腕の長さから決める（3 体で腕の長さがちがう）
	var sh := (_head_of(_id("upper_arm.L")) + _head_of(_id("upper_arm.R"))) * 0.5
	var reach := _len(_id("upper_arm.R")) + _len(_id("forearm.R"))
	var head := _head_of(_id("head")) if _id("head") >= 0 else sh + Vector3(0, 0.1, 0)
	match kind_:
		"high_five":
			for gr in emote.get("grips", [[1, Vector3.INF]]):
				var side := "R" if gr[0] > 0 else "L"
				if k < 3:
					# ため: 肘ごと大きくうしろへ引く（3 コマ）
					_arm(side, Vector3(0.7, 0.6, 0.6), Vector3(0.35, 1.0, 0.75))
				elif k < 6 and gr[1] != Vector3.INF:
					_hold[0 if side == "L" else 1] = [self, to_local(gr[1])]   # 叩きつける: 手が合う所（相手と同じ所）
				else:
					var f := clampf((k - 6) / 4.0, 0.0, 1.0)
					_arm(side, Vector3(0.4, 0.6 - 0.9 * f, -0.7), Vector3(0.25, 0.3 - 1.1 * f, -0.9))
		"shake":
			# 握手: 手を差し出し（2 コマ）、重ねる所で手のひらを合わせ、二人一緒に 3 回上下に振り、離して下ろす。
			# 重ねる所は配り役が決める（二人の手のひらがみな平行で、ぴったり重なる）
			for gr in emote.get("grips", []):
				var side := "R" if gr[0] > 0 else "L"
				var at: Vector3 = gr[1]
				if k < 2:
					_hold[0 if side == "L" else 1] = [self, to_local(global_position.lerp(at, 0.5) + Vector3.UP * (at.y - global_position.y) * 0.5)]
				elif k < 20:
					_hold[0 if side == "L" else 1] = [self, to_local(at + Vector3.UP * Palm.shake_pump(k))]
				else:
					_arm(side, Vector3(0.2, -1.0, -0.25), Vector3(0.1, -1.0, -0.35))
		"whiff":
			var side := "R" if int(emote.get("side", 1)) > 0 else "L"
			if k < 2:
				_arm(side, Vector3(0.45, 0.9, 0.45), Vector3(0.25, 1.0, 0.65))
			elif k < 4:
				_arm(side, Vector3(0.1, 0.1, -1.0), Vector3(-0.15, -0.5, -1.0))   # 何もない所を振り抜く
			else:
				_arm(side, Vector3(-0.05, -0.8, -0.5), Vector3(-0.1, -0.9, -0.4))
		"breath":
			# 吸うと両腕が横へ開いて上がり、吐くとゆっくり下りる
			var s := _exhale_now(k)
			for side in ["L", "R"]:
				_arm(side, Vector3(0.6 + 0.2 * s, -0.75 + 0.85 * s, -0.15), Vector3(0.55 + 0.25 * s, -0.6 + 0.9 * s, -0.25))
		"make_ball":
			if k >= 4 and k < 16:
				# 足もとの前で、両手で雪をぽんぽんと丸める（2 コマごとに上下を入れ替える）
				var up := 0.06 if (k / 2) % 2 == 0 else 0.0
				var base := sh + Vector3(0, -0.8, -0.5) * reach
				_hand_to("R", base + Vector3(0.07, up, 0) * reach * 2.5)
				_hand_to("L", base + Vector3(-0.07, 0.06 - up, 0) * reach * 2.5)
			elif k >= 16:
				_arm("R", Vector3(0.25, -0.6, -0.6), Vector3(0.1, 0.1, -1.0))   # できた玉を胸の前に持つ
		"windup":
			_arm("R", Vector3(0.55, 0.55, 0.75), Vector3(0.2, 1.0, 0.45))
			_arm("L", Vector3(0.2, 0.25, -1.0), Vector3(0.1, 0.3, -1.0))   # 左手で狙う先を指す
		"throw":
			if k == 0:
				_arm("R", Vector3(0.25, 0.5, -1.0), Vector3(0.1, 0.35, -1.0))
			elif k < 3:
				_arm("R", Vector3(-0.1, -0.2, -1.0), Vector3(-0.25, -0.6, -0.8))   # 振り抜く
			_arm("L", Vector3(0.3, -0.9, 0.2), Vector3(0.2, -1.0, 0.1))
		"hit":
			if k < 8:
				# 両手がぱっと上がる（痛いのではなく、びっくりして楽しい）
				_arm("R", Vector3(0.8, 0.6, 0.15), Vector3(0.6, 1.0, 0.2))
				_arm("L", Vector3(0.8, 0.5, 0.25), Vector3(0.7, 0.9, 0.1))
			elif k < 14:
				for side in ["L", "R"]:
					_arm(side, Vector3(0.55, -0.6, 0.1), Vector3(0.3, -0.4, -0.5))   # 雪を払う
		"clap":
			# 4 回。4 コマで 1 回: 開く → 寄せる → 合わせる（ぽふ）→ 少し開く
			var gap: float = [0.32, 0.14, 0.015, 0.2][k % 4]
			var at := sh + Vector3(0, -0.25, -0.75) * reach
			_hand_to("R", at + Vector3(gap * 0.5, 0, 0) * reach * 2.5)
			_hand_to("L", at + Vector3(-gap * 0.5, 0, 0) * reach * 2.5)
		"wa":
			if k < 2:
				for side in ["L", "R"]:
					_arm(side, Vector3(0.2, -1.0, -0.2), Vector3(0.0, -0.6, -0.8))
			elif k < 11:
				for side in ["L", "R"]:
					_arm(side, Vector3(0.75, 0.3, -0.35), Vector3(0.55, 0.85, -0.3))   # 両手を開いて上へ
		"oi":
			if k >= 1 and k < 16:
				# 空いた手を口の横に当てて、メガホンに（高い片手のひらで場所を示しながら呼べる）
				var free := 0
				for sd in [1, -1]:
					if free == 0 and hand_shapes[0 if sd > 0 else 1] == "" and not (point != Vector3.INF and (sd in point_sides or point_sides.is_empty())):
						free = sd
				if free != 0:
					var arm_r := _len(_id("upper_arm.R")) + _len(_id("forearm.R"))
					_hand_to("R" if free > 0 else "L", head + Vector3(0.16 * float(free), -0.06, -0.55) * arm_r)
		"huh":
			if k >= 2 and k < 12:
				# 肩をすくめて、両の前腕を少し外へ開く（さあ？の手）
				for side in ["L", "R"]:
					_arm(side, Vector3(0.45, -0.85, -0.1), Vector3(0.75, 0.15, -0.55))
		"nn":
			if k < 12:
				# 顔の前で手を横に振る（いやいや、ちがうの手）
				var x := 0.09 if (k / 2) % 2 == 0 else -0.09
				_hand_to("R", head + Vector3(x * reach * 2.5, -0.05, -0.6 * reach))


## 身ぶりの白い息。深呼吸は吐きはじめに長い息、声は声に合わせて大きな息
func _emote_breath(kind_: String, k: int) -> void:
	match kind_:
		"breath":
			# 短く吸ったあと、押しているあいだ吐き続ける（離したら止める）
			var stop: bool = emote.has("until") and _frame >= int(emote.until)
			_long.emitting = k >= INHALE and not stop
			_next_breath = _frame + 40
		"wa":
			if k == 2:
				_puff(1.8, 1.4)
				_next_breath = _frame + 30
		"un":
			if k == 0:
				_puff(1.15, 0.6)
				_next_breath = _frame + 24
		"huh":
			if k == 2:
				_puff(1.15, 0.6)
				_next_breath = _frame + 24
		"oi":
			# 声を伸ばすあいだ、大きな白い息を吐き続ける
			if k == 2:
				_puff(1.9, 1.6)
			_long.emitting = k >= 2 and k < 15
			_next_breath = _frame + 30
		"nn":
			if k == 0 or k == 6:
				_puff(1.2, 0.7)
				_next_breath = _frame + 24
		"hit":
			if k == 0:
				_puff(1.3, 0.9)


## 吐く息。ふつうの息より大きな綿を、吐いているあいだ出し続ける（真っ白で、長く残る）
func _make_long_breath() -> void:
	_long = _breaths[0].duplicate() as CPUParticles3D
	_breaths[0].get_parent().add_child(_long)
	_long.one_shot = false   # 吐いているあいだ出し続ける
	_long.emitting = false
	_long.amount = 30
	_long.lifetime = 2.8
	_long.explosiveness = 0.0
	_long.randomness = 0.5
	_long.direction = Vector3(0, 0.45, -1)
	_long.spread = 9.0
	_long.initial_velocity_min = 0.55
	_long.initial_velocity_max = 0.85
	_long.gravity = Vector3(0, 0.12, 0)
	_long.damping_min = 0.2
	_long.damping_max = 0.4
	_long.scale_amount_min = 1.5
	_long.scale_amount_max = 2.3
	var ramp := Gradient.new()   # 真っ白に出て、ゆっくり薄くなる
	ramp.offsets = PackedFloat32Array([0.0, 0.08, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)])
	_long.color_ramp = ramp
	# 長い息は真っ白に: 影の側の青を淡くした材質を、この息だけに
	var q := (_long.mesh as QuadMesh).duplicate() as QuadMesh
	var m := (q.material as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("cool", Color(0.86, 0.89, 0.95))
	m.set_shader_parameter("warm", Color(1.0, 0.99, 0.96))
	q.material = m
	_long.mesh = q


## 右手の雪玉（ふだんは隠す）
func _make_ball() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "hand.R"
	skel.add_child(att)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.05, 0) / _scale
	att.add_child(pivot)
	var m := MeshInstance3D.new()
	m.mesh = ball_mesh()
	m.material_override = ball_material()
	m.scale = Vector3.ONE / _scale
	m.layers = layers
	pivot.add_child(m)
	_ball = pivot
	_ball.visible = false


# ---------------------------------------------------------------- 米袋を出す・しまう

## 帯の米袋を取り出して広げる（立ったまま）。k: 0 右手を帯へ / 1 引き抜いて胸の前で両手に / 2 ばさっと前へ広げて落とす
func _sack_draw(k: int) -> float:
	var h := height()
	match k:
		0:
			_hips_drop = 0.03
			_update_all()
			_turn_axis("chest", Vector3.UP, -0.3)   # 右の腰へ体をひねる（ため）
			_hold[1] = [self, (BELT.get(kind, BELT["kasa"]) as Vector3) * _scale + Vector3(0.03, 0.04, 0.0)]
			return 0.12
		1:
			_hold[1] = [self, Vector3(0.1, h * 0.6, -0.2)]
			_hold[0] = [self, Vector3(-0.07, h * 0.58, -0.22)]
			return 0.02
		_:
			# 解放: 両腕を前へ振り下ろし、袋を雪の上へ広げる
			_hips_drop = 0.06
			_update_all()
			_hold[1] = [self, Vector3(0.15, h * 0.4, -0.45)]
			_hold[0] = [self, Vector3(-0.15, h * 0.4, -0.45)]
			return 0.45


## 立って米袋を丸め、帯に戻す。k: 0〜1 腰を上げてかがむ / 2〜6 くるくる丸める / 7 跳ねた包みを受ける / 8 帯へ / 9 しまった
func _sack_stow(k: int) -> float:
	var h := height()
	if k <= 6:
		var b := _crouch_legs(0.75)
		if k <= 1:
			_hold[1] = [self, Vector3(0.12, h * 0.14, -0.4)]
			_hold[0] = [self, Vector3(-0.12, h * 0.14, -0.4)]
		else:
			# 足もとの袋を、両手で前へ転がすように、交互に回す
			var a := k * 1.7
			_hold[1] = [self, Vector3(0.08, h * 0.12 + 0.05 * sin(a), -0.38 - 0.07 * cos(a))]
			_hold[0] = [self, Vector3(-0.08, h * 0.12 - 0.05 * sin(a), -0.38 + 0.07 * cos(a))]
		return b + 0.45   # 深く前かがみ
	if k == 7:
		_crouch_legs(0.3)
		_hold[1] = [self, Vector3(0.08, h * 0.55, -0.22)]
		_hold[0] = [self, Vector3(-0.06, h * 0.53, -0.24)]
		return 0.15
	if k == 8:
		_turn_axis("chest", Vector3.UP, -0.25)
		_hold[1] = [self, (BELT.get(kind, BELT["kasa"]) as Vector3) * _scale + Vector3(0.03, 0.04, 0.0)]
		return 0.1
	return 0.0


## 丸めた米袋: 帯（右の腰）に下げておき、取り出す・しまうときは右手に持つ
func _make_roll() -> void:
	var hips := _id("hips")
	var hand := _id("hand.R")
	if hips < 0 or hand < 0:
		return
	var at_hip := BoneAttachment3D.new()
	at_hip.bone_name = "hips"
	skel.add_child(at_hip)
	_roll_hip = Node3D.new()
	_roll_hip.transform = Transform3D(Basis(Vector3.RIGHT, 1.2).rotated(Vector3.UP, 0.3), skel.get_bone_global_rest(hips).affine_inverse() * (BELT.get(kind, BELT["kasa"]) as Vector3))
	at_hip.add_child(_roll_hip)
	var at_hand := BoneAttachment3D.new()
	at_hand.bone_name = "hand.R"
	skel.add_child(at_hand)
	_roll_hand = Node3D.new()
	_roll_hand.transform = Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(-0.04, 0.05, 0) / _scale)
	at_hand.add_child(_roll_hand)
	_roll = Node3D.new()
	_roll.scale = Vector3.ONE / _scale
	var felt := Look.felt(belt_color, 6.0)
	var cm := CylinderMesh.new()   # くるくる巻いた袋
	cm.top_radius = 0.052
	cm.bottom_radius = 0.052
	cm.height = 0.24
	cm.radial_segments = 7
	cm.rings = 1
	var body := MeshInstance3D.new()
	body.mesh = cm
	body.material_override = felt
	body.layers = layers
	_roll.add_child(body)
	for y in [-0.06, 0.06]:   # 麻ひもで 2 か所しばる
		var tm := CylinderMesh.new()
		tm.top_radius = 0.056
		tm.bottom_radius = 0.056
		tm.height = 0.016
		tm.radial_segments = 7
		var tie := MeshInstance3D.new()
		tie.mesh = tm
		tie.material_override = Look.felt(Color(0.82, 0.72, 0.5), 8.0)
		tie.position.y = y
		tie.layers = layers
		_roll.add_child(tie)
	_roll_hip.add_child(_roll)
	_roll.visible = false


## 丸めた米袋をコマごとに、帯・右手・なし（広げてある）のどこかに置く
func _place_roll() -> void:
	if _roll == null:
		return
	var ko := sack_k("out")
	var ki := sack_k("in")
	var at: Node3D = null
	if ko >= 0:
		at = _roll_hip if ko == 0 else (_roll_hand if ko == 1 else null)
	elif ki >= 0:
		at = _roll_hand if ki in [7, 8] else (_roll_hip if ki >= 9 else null)
	elif belt_sack:
		at = _roll_hip
	_roll.visible = at != null
	if at and _roll.get_parent() != at:
		_roll.reparent(at, false)
	var body := _roll.get_child(0) as MeshInstance3D
	var m := body.material_override as StandardMaterial3D
	if not m.albedo_color.is_equal_approx(belt_color):
		m.albedo_color = belt_color


static var _ball_mesh: Mesh
static var _ball_mat: Material


## 雪玉の形。ちぎった綿を丸めた、角のある毛玉（投げた雪玉・手の雪玉・一人称の雪玉で同じ）
static func ball_mesh() -> Mesh:
	if _ball_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = BALL_R
		sm.height = BALL_R * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		_ball_mesh = sm
	return _ball_mesh


static func ball_material() -> Material:
	if _ball_mat == null:
		_ball_mat = Look.felt(Color(0.97, 0.97, 0.94), 4.0)
	return _ball_mat


## 手形と腕。先に手形の置き所と向きを決め、腕の先（手首の関節）を手形の手首の真ん中へ伸ばす（腕の角度は手形の場所に合わせる）。
## 高い手のひらは見ている向きの顔より上（前を見れば遠くの人に場所を示す、見上げれば万歳）、低い手のひらはみぞおちの前で下へ向けて
## （おさえて・ストップ）。両手のときは肩幅に、片手のときは少し外へ。指さしは腕をまっすぐ指す向きへ。
## ハイタッチは合う所、握手は重ねる所（配り役が決める）に手形を置く。引く・振り下ろすコマは、腕の先に手形を付ける
func _plan_palms(kind_: String, k: int) -> void:
	_palm_goal.clear()
	var want := {}   # 側 → [形, 置き方]
	for sd in [1, -1]:
		var height: String = hand_shapes[0 if sd > 0 else 1]
		if height != "":
			want[sd] = ["palm", height]
	if point != Vector3.INF:
		var lp := global_basis.inverse() * (point - global_position)
		for sd in (point_sides if not point_sides.is_empty() else [1 if lp.x >= 0.0 else -1]):
			want[sd] = ["point", "point"]
	var grip_at := {}
	if k >= 0 and kind_ in ["high_five", "shake", "whiff"]:
		want = {}
		if kind_ == "whiff":
			if k < 3:
				want[int(emote.get("side", 1))] = ["palm", "whiff"]
		elif (kind_ == "high_five" and k < 8) or (kind_ == "shake" and k < 20):
			for gr in emote.get("grips", []):
				want[int(gr[0])] = ["palm", kind_]
				grip_at[int(gr[0])] = gr[1]
	elif k >= 0 and kind_ in ARM_EMOTES:
		return
	var head_w := skel.global_transform * _head_of(_id("head"))
	var look := -global_basis.z
	if gaze != Vector3.INF and gaze.distance_to(head_w) > 0.01:
		look = (gaze - head_w).normalized()
	var ahead := Vector3(look.x, 0, look.z)
	ahead = ahead.normalized() if ahead.length() > 0.05 else -global_basis.z
	var pop := Palm.pop(frame_index() - _hands_frame)
	for side in want:
		var shape: String = want[side][0]
		var how: String = want[side][1]
		var sname := "R" if side > 0 else "L"
		var hi := 1 if side > 0 else 0
		var sh_w := skel.global_transform * _head_of(_id("upper_arm." + sname))
		var arm := (_len(_id("upper_arm." + sname)) + _len(_id("forearm." + sname))) * _scale
		var bone_wrist := skel.global_transform * _head_of(_id("hand." + sname))   # いまの腕の先
		var size := Palm.BIG * pop
		var b := Basis.IDENTITY
		var wrist := Vector3.INF   # 腕を伸ばす先（INF なら、いまの腕の先に手形を付ける）
		var origin := Vector3.INF  # 手形の置き所（INF なら、手首から決める）
		match how:
			"high", "low":
				var dir := (look + Vector3.UP * 0.55).normalized() if how == "high" else (ahead + Vector3.DOWN * 0.75).normalized()
				wrist = sh_w + dir * arm * 0.88 + global_basis.x * float(side) * arm * 0.12
				var face := (gaze - wrist) if gaze != Vector3.INF else -global_basis.z
				var tilt := -0.65 if how == "low" else clampf(atan2(face.y, Vector2(face.x, face.z).length()) * 0.5, -0.4, 0.6)
				b = _face_basis(face, tilt)
			"point":
				var y: Vector3 = (point - sh_w).normalized()
				wrist = sh_w + y * arm * 0.98
				var z := y.cross(Vector3.UP)
				z = (z.normalized() if z.length() > 0.05 else global_basis.x) * float(side)
				b = Palm.thumb_up(Basis(y.cross(z).normalized(), y, z), side)   # 人さし指（+y）を指す向きへ、面は横から見える向き、親指は上
				size = Palm.BIG
			"high_five":
				size = Palm.BIG * (1.25 if k == 3 else 1.0)
				if k < 3 or not grip_at.has(side):
					b = _face_basis(-global_basis.z, 0.45 if k < 3 else 0.0)   # 引くと、手のひらが少し上を向く
				else:
					var g: Vector3 = grip_at[side]
					b = _face_basis(g - sh_w, 0.0)
					if k < 6:
						origin = g   # 叩きつける: 手形を合う所に
			"whiff":
				b = _face_basis(-global_basis.z, 0.45 if k < 2 else 0.0)
			"shake":
				b = Palm.shake_basis(emote.get("fwd", -global_basis.z), emote.get("axis", global_basis.x), side)
				size = Palm.BIG
				var g: Vector3 = grip_at[side]
				# 差し出す（2 コマ）→ 重ねる所でぴったり合わせ、二人一緒に上下に振る
				origin = (g + Vector3.UP * Palm.shake_pump(k)) if k >= 2 else sh_w.lerp(g, 0.75)
		var bs := b.scaled(Vector3.ONE * size)
		if origin != Vector3.INF:
			wrist = origin + bs * Palm.WRIST
		if wrist != Vector3.INF:
			_hold[hi] = [self, to_local(wrist), true]   # 腕の先を手形の手首へ（毎フレーム伸ばし直す）
			origin = wrist - bs * Palm.WRIST
		else:
			origin = bone_wrist - bs * Palm.WRIST
		_palm_goal[side] = [shape, global_transform.affine_inverse() * Transform3D(bs, origin)]


## 手のひら（+z）を face の向き（水平）へ立て、tilt だけ上（正）か下（負）へ傾ける
func _face_basis(face: Vector3, tilt: float) -> Basis:
	face.y = 0
	face = face.normalized() if face.length() > 0.01 else -global_basis.z
	return Basis.looking_at(-face, Vector3.UP) * Basis(Vector3.RIGHT, -tilt)


## 手形のアップリケを、コマで決めた置き所に（人形の座標で持つので、体と一緒になめらかに動く）
func _place_shapes() -> void:
	for sh in _shapes:
		for side in [1, -1]:
			var node: Node3D = _shapes[sh][side]
			var goal: Array = _palm_goal.get(side, [])
			node.visible = not goal.is_empty() and goal[0] == sh
			if node.visible:
				node.global_transform = global_transform * (goal[1] as Transform3D)
