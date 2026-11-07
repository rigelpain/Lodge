extends Node3D

## 連れ: 持ち主（player.gd か bot.gd）の頭と肩に載せる小物と、うしろをついて歩くミニオン（品書きは pals.gd、形は game/pals/ の glb）。
## 何を付けるかは craft.gd の pals_wear（出来事 pal_buy・pal_wear）。通信ではほかの人の画面でも同じ物が付く。
##
## 頭・肩の小物: 人形の骨（頭は head、肩は chest）に付け、人形ごとの載せる所（pals.gd の HEAD・SHOULDER）に置く。
##   大きさはどの人形でも同じ（人形の倍率を打ち消す）。生き物は、持ち主が指している所（doll.point）を、指していなければ
##   持ち主の見ている先を向き、ときどき首をかしげ、羽をつくろう。ハチドリは肩の上に浮いて羽ばたく。物（どんぐり・かぼちゃ・紅葉）は
##   持ち主の動きに少し遅れて揺れる。層は人形と同じ（一人称には映さず、右上の 360° の映像・三人称・HUD の自分の顔に出る）
##
## ミニオン: 姿は 3 つ（walk 歩く・sit 座って待つ・sleep 丸まって寝る）を置き換える（コマ撮りの置き換え人形）。
##   持ち主の右の少しうしろをついて歩き、止まると座り（SIT_T）、しばらくすると寝る（SLEEP_T）。座っているあいだは、指している所か
##   持ち主の顔を見上げる。持ち主がソリに乗ると、ソリの横を走ってついて滑る（速いと遅れ、離れすぎると追いつく。代表 2026-11-01）。
##   ロッジの中では暖炉の前（暖炉の前のラグの、暖炉の側。hearth_nook.gd の pet_spot）へ行って寝て待ち、持ち主が外へ出ると起きて、うしろから駆けてくる（代表 2026-11-01）。
##   大きな鏡（mirror.gd）に映しているあいだは、ロッジの中でも持ち主の足もとへ駆けてきて、鏡の方を向いて座る（この画面だけ。通信では送らない。代表 2026-11-04）。
##   層は誰の画面にも映し、右下の自分の小窓（self_cam.gd の層 6）にも映す。自分のミニオンは鏡（mirror.gd の層 11）にも映す
##
## 居場所（ミニオンの位置と向き）は毎フレームなめらか。姿勢（首・羽・脚・しっぽ・跳ねる）は人形と同じ 12 コマ／秒の時計で刻む。

const Doll := preload("res://doll.gd")
const Pals := preload("res://pals.gd")
const Audio := preload("res://audio.gd")
const Mirror := preload("res://mirror.gd")

const HEEL := Vector3(0.75, 0.0, 0.25)   # ミニオンの立ち位置（持ち主の座標。右の少しうしろ）
const HEAD_YAW := 1.2        # ミニオンの首が回る限り（これより横は体ごと向く）
const SIT_T := 0.45          # 止まってから座るまで (s)
const SLEEP_T := 25.0        # 座ってから寝るまで (s)
const HEARTH_SLEEP_T := 2.0  # 暖炉の前に着いてから寝るまで (s)
const RUN_MAX := 15.0        # ソリについて走る速さの上限 (m/s)。これより速いソリには遅れる
const RIDE_SIDE := 1.7       # ソリの横の、走る所（ソリの中心から右へ, m）
const CATCH_UP := 32.0       # これより離れたら、追いつく（持ち主のうしろへ跳ぶ）
const HOVER := 0.07          # ハチドリが肩の上に浮く高さ (m)

var host: Node3D             # 持ち主（player.gd か bot.gd。doll と id を持つ）
var craft: Node
var mirror: Node3D           # 映している鏡（mirror.gd が入れる）。映していなければ null

var _doll: Doll
var _who := -1
var _perch := {}             # slot → {key, node, att, local, corr, parts, move, rest, yaw, …}
var _pet := {}               # {key, node, poses, parts, rest, gait, …}。付けていなければ空
var _frame := -1
var _rng := RandomNumberGenerator.new()
var _was_pointing := false
var _hop := 0                # 指さしが入ったとき、頭・肩の生き物がぴょんと跳ねる残りのコマ
var _last_pos := Vector3.ZERO   # 持ち主の前のコマの所（世界）。物の揺れに
var _sway := Vector2.ZERO    # 物の揺れ（x 前後、y 左右, rad）
var _sway_v := Vector3.ZERO  # 持ち主の速さ（世界。前のコマ）

# ミニオンの居場所
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _yaw := 0.0
var _phase := 0.0            # 歩く・跳ねる・転がるの進み
var _still := 0.0            # 止まっている秒
var _pose := "sit"
var _want_pose := "sit"
var _in_lodge := false       # 持ち主がロッジの中にいる（前のフレーム）
var _hearth := Vector3.INF   # 暖炉の前の寝る所（世界）
var _lodge: Node3D
var _riding := false


func _ready() -> void:
	name = "Pals%d" % int(host.get("id"))
	_who = int(host.get("id"))
	if craft == null:
		craft = host.get_parent().get_node_or_null("Craft")
	if craft:
		craft.happened.connect(_on_craft)
	_lodge = host.get_parent().get_node_or_null("Lodge")
	_doll = host.get("doll")
	_rng.seed = hash(_who)
	_refresh()


func _worn(slot: String) -> String:
	if craft == null:
		return Pals.START_WEAR[slot]
	return craft.pal_worn(_who, slot)


## 付けている物を craft から読み直す（替わった所だけ作り直す）
func _refresh() -> void:
	for slot in ["head", "shoulder"]:
		var k := _worn(slot)
		if String(_perch.get(slot, {}).get("key", "")) != k:
			_make_perch(slot, k)
	var pk := _worn("pet")
	if String(_pet.get("key", "")) != pk:
		_make_pet(pk)


func _on_craft(ev: Dictionary) -> void:
	if int(ev.get("who", -1)) == _who and String(ev.kind) in ["pal_buy", "pal_wear", "pal_own"]:
		_refresh()


# ---------------------------------------------------------------- 頭・肩の小物

func _make_perch(slot: String, key: String) -> void:
	var old: Dictionary = _perch.get(slot, {})
	if old.has("att") and is_instance_valid(old.att):
		(old.att as Node).queue_free()
	_perch.erase(slot)
	if key == "" or _doll == null or not is_instance_valid(_doll) or not Pals.PERCH.has(key):
		return
	var skel := _doll.skel
	var bone := "head" if slot == "head" else String(Pals.SHOULDER_BONE.get(_doll.kind, "chest"))
	var bi := skel.find_bone(bone)
	if bi < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skel.add_child(att)
	var node: Node3D = Pals.scene(key).instantiate()
	Pals.paint(node, _doll.layers)   # あなたの体と同じ層（一人称には映さない）
	att.add_child(node)
	node.top_level = true
	# 載せる所（glb の座標）を、付け根の姿勢の骨から見た所に直す（骨と一緒に動く）。向きも、付け根の姿勢でまっすぐ立つように直す
	var inst := _doll.get_child(0) as Node3D
	var pts: Dictionary = Pals.HEAD if slot == "head" else Pals.SHOULDER
	var at_world := inst.global_transform * (pts.get(_doll.kind, pts["kasa"]) as Vector3)
	var bone_world := skel.global_transform * skel.get_bone_global_rest(bi)
	var parts := {}
	var rest := {}
	for c in node.get_children():
		if c is Node3D:
			parts[Pals.part_name(c)] = c
			rest[Pals.part_name(c)] = (c as Node3D).transform
	_perch[slot] = {
		"key": key, "node": node, "att": att,
		"local": bone_world.affine_inverse() * at_world,
		"corr": bone_world.basis.orthonormalized().inverse() * inst.global_basis.orthonormalized(),
		"parts": parts, "rest": rest, "move": String(Pals.PERCH[key].move),
		"yaw": 0.0, "preen": -100, "flap": 0.0,
	}
	_place_perch(_perch[slot])


## 生き物が見る所: 指していればそこ、でなければ持ち主の見ている先（なければ前）
func _perch_target(p: Dictionary) -> Vector3:
	if _doll.point != Vector3.INF:
		return _doll.point
	if _doll.gaze != Vector3.INF:
		return _doll.gaze
	return (p.node as Node3D).global_position - _doll.global_basis.z * 5.0


func _base(p: Dictionary) -> Transform3D:
	var att: Node3D = p.att
	var b: Basis = att.global_basis.orthonormalized() * (p.corr as Basis)
	return Transform3D(b, att.global_transform * (p.local as Vector3))


## 毎フレーム: 骨の動きについていく（向きは 12 コマで決めた値）
func _place_perch(p: Dictionary) -> void:
	var t := _base(p)
	var up := 0.0
	if p.move == "hover":
		up = HOVER + 0.012 * sin(_frame * 0.7)
	elif _hop in [3, 2] and p.move != "thing":
		up = 0.03
	var b := t.basis * Basis(Vector3.UP, float(p.yaw))
	if p.move == "thing":
		b = b * Basis(Vector3.RIGHT, _sway.x) * Basis(Vector3.BACK, _sway.y)
	(p.node as Node3D).global_transform = Transform3D(b, t.origin + t.basis.y * up)


## 12 コマ: 首・羽・しっぽ
func _pose_perch(p: Dictionary) -> void:
	var parts: Dictionary = p.parts
	var t := _base(p)
	var d := t.basis.inverse() * (_perch_target(p) - t.origin)
	var want := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var mv: String = p.move
	match mv:
		"thing":
			return
		"chameleon":   # ゆっくり見回す
			p.yaw = lerp_angle(float(p.yaw), clampf(want, -1.2, 1.2), 0.12)
		"rabbit":
			p.yaw = lerp_angle(float(p.yaw), clampf(want, -1.6, 1.6), 0.5)
		_:
			p.yaw = clampf(want, -2.4, 2.4)
	var head: Node3D = parts.get("head")
	var tilt := 0.0
	if _doll.point == Vector3.INF and _frame % 17 < 3:
		tilt = 0.35 * (1.0 if (_frame / 17) % 2 == 0 else -1.0)   # ときどき首をかしげる
	# 羽をつくろう（鳥。指していないとき、ときどき 8 コマ）
	if mv in ["bird", "crane"] and _doll.point == Vector3.INF and _frame - int(p.preen) > 70 and _rng.randf() < 0.03:
		p.preen = _frame
	var preen := _frame - int(p.preen) < 8
	if head:
		var hr := Vector3(clampf(pitch, -0.8, 0.9) if mv != "rabbit" else 0.0, 0.0, tilt)
		if preen:
			var side := 1.0 if (int(p.preen) / 7) % 2 == 0 else -1.0
			hr = Vector3(-0.5, side * (1.3 + 0.15 * (_frame % 2)), 0.2 * side)
		if mv == "rabbit":
			hr = Vector3(0, 0, tilt * 0.5)
		head.rotation = hr
	# 羽: 指さしが入った・持ち主が跳んだ・速いときに広げてばたつく。ハチドリはいつも羽ばたく。鶴はゆっくり上下
	var flap := 0.0
	if mv == "hover":
		flap = 0.9 if _frame % 2 == 0 else -0.5
	elif mv == "crane":
		flap = 0.18 * sin(_frame * 0.35)
	elif _hop > 0 or _doll.airborne or _sway_v.length() > 6.0:
		flap = 0.8 if _frame % 2 == 0 else 0.3
	elif preen:
		flap = 0.25
	for side in [["wing_l", 1.0], ["wing_r", -1.0]]:
		var w: Node3D = parts.get(side[0])
		if w:
			w.rotation = Vector3(0, 0, flap * float(side[1]))
	var tail: Node3D = parts.get("tail")
	if tail:
		match mv:
			"squirrel":
				tail.rotation = Vector3(0.15 * sin(_frame * 0.4), 0.45 * sin(_frame * 0.27), 0)
			"chameleon":
				tail.rotation = Vector3(0.35 * (0.5 + 0.5 * sin(_frame * 0.08)), 0, 0)
			_:
				tail.rotation = Vector3(0.1 * sin(_frame * 0.5), 0, 0)


# ---------------------------------------------------------------- ミニオン

func _make_pet(key: String) -> void:
	if _pet.has("node") and is_instance_valid(_pet.node):
		(_pet.node as Node).queue_free()
	_pet = {}
	if key == "" or not Pals.PET.has(key):
		return
	var node: Node3D = Pals.scene(key).instantiate()
	var own := _doll != null and is_instance_valid(_doll) and _doll.layers != 1   # 自分のミニオン（人形が自分の体の層にいる）だけ、鏡に映す
	Pals.paint(node, 1 | (1 << 5) | (Mirror.LAYER if own else 0))   # 誰の画面にも映し、右下の自分の小窓（self_cam.gd の層 6）にも映す
	add_child(node)
	node.top_level = true
	var poses := {}
	var parts := {}
	var rest := {}
	for c in node.get_children():
		var pose := Pals.part_name(c)
		if not pose in ["walk", "sit", "sleep"]:
			continue
		poses[pose] = c
		parts[pose] = {}
		rest[pose] = {}
		for pc in c.get_children():
			parts[pose][Pals.part_name(pc)] = pc
			rest[pose][Pals.part_name(pc)] = (pc as Node3D).transform
	_pet = {"key": key, "node": node, "poses": poses, "parts": parts, "rest": rest, "spec": Pals.PET[key]}
	if _doll and is_instance_valid(_doll):
		_pos = _heel()
		_yaw = _doll.global_rotation.y
	_vel = Vector3.ZERO
	_still = SIT_T
	_pose = "sit"
	_want_pose = "sit"
	_show_pose()
	node.global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)


func _show_pose() -> void:
	for k in _pet.poses:
		(_pet.poses[k] as Node3D).visible = k == _pose


func _heel() -> Vector3:
	var p := _doll.global_position + _doll.global_basis * HEEL
	return Vector3(p.x, _ground(p), p.z)


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 6.0)
	var ex: Array[RID] = []
	if host is CollisionObject3D:
		ex.append((host as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else p.y


func _zone(p: Vector3) -> int:
	if _lodge == null or not is_instance_valid(_lodge):
		_lodge = host.get_parent().get_node_or_null("Lodge")
	return Audio.zone_at(_lodge, p)


## 暖炉の前の寝る所: 暖炉の前のラグの、暖炉の側（人ごとに散らす。hearth_nook.gd）。ラグがなければ炉の目印の前
func _hearth_spot() -> Vector3:
	if _hearth != Vector3.INF:
		return _hearth
	var nook = _lodge.find_child("HearthNook", true, false) if _lodge else null
	if nook:
		var p: Vector3 = nook.pet_spot(_who)
		_hearth = Vector3(p.x, _ground(p), p.z)
	elif _lodge:
		var mark := _lodge.find_child("light_fire", true, false) as Node3D
		if mark:
			var away := (_lodge.global_position - mark.global_position)
			away.y = 0
			var p := mark.global_position + away.normalized() * 1.8
			_hearth = Vector3(p.x, _ground(p), p.z)
	return _hearth


## ミニオンが見る所: 指していればそこ、鏡に映っていれば鏡、でなければ持ち主の顔
func _pet_target() -> Vector3:
	if _doll.point != Vector3.INF:
		return _doll.point
	if mirror:
		return mirror.look_point()   # 鏡を見る（鏡の絵の中で、こちらを向く）
	return _doll.global_position + Vector3.UP * 1.2


func _move_pet(dt: float) -> void:
	var spec: Dictionary = _pet.spec
	var riding := _doll.act == Doll.Act.RIDE and _doll.sled != null
	var inside := _zone(_doll.global_position) == 2
	var want: Vector3
	var cap: float = spec.speed
	var settle := false   # 着いたら座ってすぐ寝る所（暖炉の前）
	if riding:
		# ソリの横を走る: ソリの右（RIDE_SIDE）の少しうしろ。走る速さには限りがあり、速いソリには遅れる
		var sb := _doll.sled.global_basis.orthonormalized()
		var p: Vector3 = _doll.sled.global_position + sb.x * RIDE_SIDE + sb.z * 0.6
		want = Vector3(p.x, _ground(p), p.z)
		cap = maxf(cap * 1.6, RUN_MAX)
	elif mirror:
		want = mirror.pet_spot(_doll)
		want.y = _ground(want)
	elif inside:
		want = _hearth_spot()
		if want == Vector3.INF:
			want = _heel()
		settle = true
	else:
		want = _heel()
	# 持ち主が外へ出た: 暖炉の前で寝ていたミニオンは起きて、うしろから駆けてくる（壁を抜けないよう、持ち主のうしろへ出る）
	if _in_lodge and not inside and _zone(_pos) == 2:
		var back := _doll.global_position + _doll.global_basis.z * 2.5
		_pos = Vector3(back.x, _ground(back), back.z)
		_still = 0.0
	_in_lodge = inside
	var d := want - _pos
	d.y = 0
	if d.length() > CATCH_UP or d.length() > 12.0 and not riding and not settle:
		# 離れすぎた（速いソリに置いていかれた・跳んだ）: 持ち主のうしろへ跳んで、追いつく
		var back := want - (_doll.global_basis.z * -1.0) * 6.0 if not riding else want + _doll.sled.global_basis.z * 8.0
		_pos = Vector3(back.x, _ground(back), back.z)
		d = want - _pos
		d.y = 0
	var near := 0.15 if settle else 0.25
	var speed := clampf((d.length() - near) * 3.0, 0.0, cap)
	if riding and d.length() > 1.0:
		speed = cap   # ソリについて全力で走る
	_vel = _vel.lerp(d.normalized() * speed if d.length() > 0.02 else Vector3.ZERO, 1.0 - exp(-dt * (8.0 if riding else 6.0)))
	_pos += _vel * dt
	_pos.y = lerpf(_pos.y, _ground(_pos), 1.0 - exp(-dt * 20.0))
	var spd := _vel.length()
	_phase += spd * dt / float(spec.step) * PI
	var face: float
	if spd > 0.35:
		face = atan2(-_vel.x, -_vel.z)
		_still = 0.0
	else:
		_still += dt
		if mirror:   # 鏡に体ごと向く
			var t := _pet_target() - _pos
			face = atan2(-t.x, -t.z)
		elif settle and d.length() < 0.5 and _lodge:   # 暖炉に体を向けて丸まる
			var mark := _lodge.find_child("light_fire", true, false) as Node3D
			var t := (mark.global_position if mark else _pet_target()) - _pos
			face = atan2(-t.x, -t.z)
		else:
			# 止まっているときは見る所へ。首で届かない分だけ体ごと向く
			var t := _pet_target() - _pos
			var want_yaw := atan2(-t.x, -t.z)
			var off := wrapf(want_yaw - _yaw, -PI, PI)
			face = _yaw + signf(off) * maxf(0.0, absf(off) - HEAD_YAW * 0.8)
	_yaw = lerp_angle(_yaw, face, 1.0 - exp(-dt * 8.0))
	if spd > 0.35:
		_want_pose = "walk"
	elif mirror:
		_want_pose = "sit"   # 鏡の前では寝ない
	elif _still > (HEARTH_SLEEP_T if settle and d.length() < 0.5 else SLEEP_T) or _pose == "sleep" and spd < 0.35:
		_want_pose = "sleep"
	elif _still > SIT_T:
		_want_pose = "sit"
	_riding = riding
	(_pet.node as Node3D).global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)


## 12 コマ: 姿を置き換え、脚・首・しっぽを刻む
func _pose_pet() -> void:
	if _want_pose != _pose:
		_pose = _want_pose
		_show_pose()
	pose_parts(_pet, _pose, _phase, _frame, 1.4 if _riding else 1.0, _pet_target(), _doll.point == Vector3.INF)


## ミニオンの姿 pose の部品を、付け根の姿勢から 12 コマの 1 コマぶん動かす（連れのミニオンと、山師の柵のミニオン pen_pets.gd が使う）。
## pet は {node, parts, rest, spec}（_make_pet の形）。ph は歩く・跳ねる・転がるの進み、big は脚の振りの大きさ、
## look は座っているときに首で見る所（世界）、tilt は、ときどき首をかしげるか
static func pose_parts(pet: Dictionary, pose: String, ph: float, frame: int, big: float, look: Vector3, tilt: bool) -> void:
	var parts: Dictionary = pet.parts.get(pose, {})
	var rest: Dictionary = pet.rest.get(pose, {})
	var gait: String = pet.spec.gait
	for k in parts:   # 付け根の姿勢に戻してから
		(parts[k] as Node3D).transform = rest[k]
	var body: Node3D = parts.get("body")
	var head: Node3D = parts.get("head")
	var tail: Node3D = parts.get("tail")
	match pose:
		"walk":
			match gait:
				"trot":   # 対角の脚を一緒に出す。体は歩くたびに少し上下
					var s := sin(ph) * 0.55 * big
					for leg in [["leg_fl", 1.0], ["leg_br", 1.0], ["leg_fr", -1.0], ["leg_bl", -1.0]]:
						var n: Node3D = parts.get(leg[0])
						if n:
							n.rotation.x = s * float(leg[1])
					var bob := 0.018 * absf(cos(ph)) * big
					for k in ["body", "head", "tail", "leg_fl", "leg_fr", "leg_bl", "leg_br"]:
						if parts.has(k):
							(parts[k] as Node3D).position.y += bob
					if head:
						head.rotation.x = 0.06 * sin(ph * 2.0)
					if tail:
						tail.rotation.y = 0.3 * sin(ph)
				"hop":   # 跳ねる: 体ごと弧を描き、跳ぶ前にうしろ脚を伸ばす
					var u := fmod(ph / PI, 1.0)
					var hgt := 0.12 * sin(u * PI) * big
					for k in parts:
						(parts[k] as Node3D).position.y += hgt
					for leg in ["leg_bl", "leg_br"]:
						if parts.has(leg):
							(parts[leg] as Node3D).rotation.x = -0.7 * (1.0 - u) + 0.3
					for leg in ["leg_fl", "leg_fr"]:
						if parts.has(leg):
							(parts[leg] as Node3D).rotation.x = 0.5 * u
				"roll":   # 毛糸玉が転がる（半径 0.11 m）。ほどけた糸はうしろへ流れる
					if body:
						body.rotation.x = -fmod(ph * float(pet.spec.step) / PI / 0.11, TAU)
					if tail:
						tail.rotation.y = 0.25 * sin(ph * 0.5)
				"strut":   # 二本足で、首を前後に振って歩く
					var s := sin(ph) * 0.45 * big
					if parts.has("leg_l"):
						(parts["leg_l"] as Node3D).rotation.x = s
					if parts.has("leg_r"):
						(parts["leg_r"] as Node3D).rotation.x = -s
					if head:
						head.position.z += 0.03 * sin(ph * 2.0)
					if tail:
						tail.rotation.y = 0.08 * sin(ph)
		"sit":   # 見る所を首で追う。しっぽをゆっくり振り、息で体が少しふくらむ
			if head:
				var hp := head.global_position
				var ld := (pet.node as Node3D).global_basis.inverse() * (look - hp)
				head.rotation = Vector3(clampf(atan2(ld.y, Vector2(ld.x, ld.z).length()), -0.5, 0.7), clampf(atan2(-ld.x, -ld.z), -HEAD_YAW, HEAD_YAW), 0.0)
				if tilt and frame % 23 < 3:
					head.rotation.z = 0.3   # ときどき首をかしげる
			if tail:
				tail.rotation.y = 0.25 * sin(frame * 0.2)
			if body:
				body.scale = Vector3(1.0, 1.0 + 0.015 * sin(frame * 0.5), 1.0)
		"sleep":   # ゆっくり息をする。ときどきしっぽの先が動く
			if body:
				body.scale = Vector3(1.0 + 0.01 * sin(frame * 0.25), 1.0 + 0.03 * sin(frame * 0.25), 1.0)
			if tail and frame % 60 < 3:
				tail.rotation.y = 0.15


## 頭・肩の小物が占める箱（世界）。鏡が全身の収まる距離を出すのに使う
func worn_box() -> AABB:
	var box := AABB()
	for slot in _perch:
		if not is_instance_valid(_perch[slot].node):   # 着替えの途中（前の体と一緒に消えた。_physics_process で付け直す）
			continue
		for mi in (_perch[slot].node as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.is_visible_in_tree():
				var b := m.global_transform * m.get_aabb()
				box = b if not box.has_volume() else box.merge(b)
	return box


## ミニオンのいる所（世界）
func pet_at() -> Vector3:
	return _pos


## ミニオンの半径の目安 (m)。いなければ 0
func pet_radius() -> float:
	if _pet.is_empty():
		return 0.0
	if not _pet.has("radius"):
		var box := AABB()
		for mi in ((_pet.poses as Dictionary).get("sit") as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var b := (_pet.node as Node3D).global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			box = b if not box.has_volume() else box.merge(b)
		_pet["radius"] = maxf(box.size.x, box.size.z) * 0.5
	return float(_pet.radius)


# ---------------------------------------------------------------- 時計

var _lod_dt := 0.0
var _lod_frame := -1


func _physics_process(dt: float) -> void:
	if host == null or not is_instance_valid(host):
		queue_free()
		return
	var d = host.get("doll")
	if d != _doll and d != null and is_instance_valid(d):   # 衣装掛けで着替えた: 新しい体に小物を付け直す（前の小物は前の体と消えた）
		_doll = d
		_perch.clear()
		_refresh()
	if _doll == null or not is_instance_valid(_doll):
		return
	if Doll.view_lod(_doll, _doll.global_position + Vector3.UP) > 0:
		# 遠い持ち主の小物とペットは 12 コマ／秒で（地面を探すのが重いので）
		_lod_dt += dt
		var lk := Doll.frame_index()
		if lk == _lod_frame:
			return
		_lod_frame = lk
		dt = _lod_dt
	_lod_dt = 0.0
	var pointing := _doll.point != Vector3.INF
	if pointing and not _was_pointing:
		_hop = 4   # 指さしが入ると、頭・肩の生き物がぴょんと跳ねて向き直る
	_was_pointing = pointing
	if not _pet.is_empty():
		_move_pet(dt)
	var fi := Doll.frame_index()
	if fi != _frame:
		_frame = fi
		_rng.seed = hash(Vector2i(_frame, _who))
		# 物の揺れ: 持ち主の速さの変わりに少し遅れて傾き、ばねのように戻る
		var v := _doll.global_position
		var vel := (v - _last_pos) * Doll.FPS if _last_pos != Vector3.ZERO else Vector3.ZERO
		var acc := _doll.global_basis.inverse() * (vel - _sway_v) * 0.02
		_sway = (_sway * 0.55 + Vector2(clampf(acc.z, -0.25, 0.25), clampf(-acc.x, -0.25, 0.25))) + Vector2(_rng.randf_range(-0.012, 0.012), _rng.randf_range(-0.012, 0.012))
		_sway_v = vel
		_last_pos = v
		if _hop > 0:
			_hop -= 1
		for slot in _perch:
			_pose_perch(_perch[slot])
		if not _pet.is_empty():
			_pose_pet()
	for slot in _perch:
		_place_perch(_perch[slot])

