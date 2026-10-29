extends Node3D

## 連れの動物: 頭に止まる千代紙の小鳥と、うしろをついて歩く折り紙の子狐（案。person/ideas/costume/）。
## 形は person/ideas/costume/costume_rough.py で作った glb（--look export）。色は look.gd の紙と和柄に置き換える。
## どちらも、持ち主が指している所（doll.point）を見る。指していなければ、小鳥は持ち主の見ている先を、子狐は持ち主の顔を見る。
## 居場所（子狐の位置と体の向き）は毎フレームなめらか。姿勢（頭・しっぽ・跳ねる・小鳥の向き）は人形と同じ 12 コマ／秒の時計で刻む。
## 見た目だけ。通信には乗せない。

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")
const BIRD := preload("res://companions/bird.glb")
const KIT := preload("res://companions/kit.glb")

## 人形ごとの、頭のいちばん上（glb の座標、人形の大きさのまま）。小鳥が止まる所。
## kasa は笠の先、origami は頭巾の上、news は頭巾の前寄りの上
const PERCH := {"kasa": Vector3(0, 1.372, 0.0), "origami": Vector3(0, 1.49, 0.0), "news": Vector3(0, 0.955, -0.04)}
## 子狐の立ち位置（持ち主の座標。右の少しうしろ）
const HEEL := Vector3(0.75, 0.0, 0.2)
const KIT_SCALE := 1.4       # glb の大きさ（座って 0.4 m）からの倍率
const HEAD_YAW := 1.2        # 子狐の首が回る限り（これより横は体ごと向く）
## ソリでの子狐の座る所（持ち主の席から、ソリの座標）。膝の少し前の座面で、一人称の目の前をふさがないよう右へ寄る
const LAP := Vector3(0.2, -0.02, -0.34)

var host: Node3D             # 持ち主（player.gd か bot.gd。doll を持つ）
var bird_on := true
var kit_on := true

var _doll: Doll
var _bird: Node3D
var _bird_head: Node3D
var _bird_yaw := 0.0         # 小鳥の向き（世界、コマで決める）
var _perch := Vector3.ZERO   # 止まる所（頭の骨の座標）
var _bird_hop := 0
var _kit: Node3D
var _kit_head: Node3D
var _kit_tail: Node3D
var _kit_yaw := 0.0
var _kit_vel := Vector3.ZERO
var _kit_phase := 0.0
var _kit_hop := 0.0
var _kit_on_sled := Vector3.INF   # 乗っているあいだの子狐の所（ソリの座標）。ソリと一緒に動き、傾く
var _kit_ride_yaw := 0.0          # 乗っているあいだの、ソリに対しての向き
var _was_pointing := false
var _frame := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_doll = host.get("doll")
	if bird_on:
		_make_bird()
	if kit_on:
		_make_kit()


static func _paint(root: Node) -> void:
	var mats := {
		"chiyo": Look.wagara("seigaiha", Color("B8473A"), Color("E8A07A"), 26.0),
		"white": Look.paper(Color("F4F0E8")),
		"beak": Look.paper(Color("D9A42C")),
		"ink": Look.paper(Color("1E1A18")),
		"orange": Look.paper(Color("D27330")),
		"cream": Look.paper(Color("F2EBDD")),
		"dark": Look.paper(Color("4A3326")),
	}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var key := src.resource_name if src else ""
			for k in mats:
				if key.begins_with(k):
					m.set_surface_override_material(i, mats[k])


static func _layers(root: Node, layers: int) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = layers


# ---------------------------------------------------------------- 小鳥

func _make_bird() -> void:
	var skel := _doll.skel
	var hi := skel.find_bone("head")
	if hi < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	_bird = BIRD.instantiate()
	_paint(_bird)
	_layers(_bird, _doll.layers)   # あなたの体と同じ層（一人称には映さず、右上の映像と三人称に出る）
	att.add_child(_bird)
	# 止まる所（glb の座標）を、付け根の姿勢の頭の骨から見た所に直す（頭と一緒に動く）。
	# glb の根と骨の空間のあいだに変換が入っていてもよいように、世界の座標を通して直す
	var inst := _doll.get_child(0) as Node3D
	var perch_world := inst.global_transform * (PERCH.get(_doll.kind, PERCH["kasa"]) as Vector3)
	var bone_world := skel.global_transform * skel.get_bone_global_rest(hi)
	_perch = bone_world.affine_inverse() * perch_world
	_bird.position = _perch
	_bird_head = _bird.find_child("head", true, false)
	_bird_yaw = _doll.global_rotation.y


## 小鳥が見る所: 指していればそこ、でなければ持ち主の見ている先（なければ前）
func _bird_target() -> Vector3:
	if _doll.point != Vector3.INF:
		return _doll.point
	if _doll.gaze != Vector3.INF:
		return _doll.gaze
	return _bird.global_position - _doll.global_basis.z * 5.0


func _pose_bird() -> void:
	var tgt := _bird_target()
	var d := tgt - _bird.global_position
	_bird_yaw = atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var tilt := 0.0
	if _doll.point == Vector3.INF and _frame % 17 < 3:
		tilt = 0.35 * (1.0 if (_frame / 17) % 2 == 0 else -1.0)   # ときどき首をかしげる
	if _bird_head:
		_bird_head.rotation = Vector3(clampf(pitch, -0.8, 0.9), 0.0, tilt)
	if _bird_hop > 0:
		_bird_hop -= 1


func _place_bird() -> void:
	var s: float = (_bird.get_parent() as Node3D).global_basis.get_scale().x
	var up := 0.035 * s if _bird_hop in [3, 2] else 0.0
	var at: Vector3 = (_bird.get_parent() as Node3D).global_transform * _perch
	_bird.global_transform = Transform3D(Basis(Vector3.UP, _bird_yaw).scaled(Vector3.ONE * s), at + Vector3.UP * up)


# ---------------------------------------------------------------- 子狐

func _make_kit() -> void:
	_kit = KIT.instantiate()
	_paint(_kit)
	add_child(_kit)
	_kit.top_level = true
	_kit.scale = Vector3.ONE * KIT_SCALE
	_layers(_kit, 1 | (1 << 5))   # 誰の画面にも映し、右下の自分の小窓（self_cam.gd の層 6）にも映す
	_kit_head = _kit.find_child("head", true, false)
	_kit_tail = _kit.find_child("tail", true, false)
	_kit.global_position = _heel()
	_kit_yaw = _doll.global_rotation.y


func _heel() -> Vector3:
	var p := _doll.global_position + _doll.global_basis * HEEL
	return Vector3(p.x, _ground(p), p.z)


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 6.0)
	var ex: Array[RID] = []
	if host is CollisionObject3D:
		ex.append((host as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else p.y


## 子狐が見る所: 指していればそこ、乗っていれば行く先、でなければ持ち主の顔
func _kit_target() -> Vector3:
	if _doll.point != Vector3.INF:
		return _doll.point
	if _riding():
		return _kit.global_position - _doll.sled.global_basis.z * 5.0 + Vector3.UP * 0.4
	return _doll.global_position + Vector3.UP * 1.3


func _riding() -> bool:
	return _doll.act == Doll.Act.RIDE and _doll.sled != null


func _move_kit(dt: float) -> void:
	var pos := _kit.global_position
	if _riding():
		# ソリでは持ち主の膝の前の座面に座る。所と向きはソリの座標で持つので、ソリが滑っても跳ねても傾いても離れない。
		# 乗った直後だけ、いまの所から座る所へ跳び移る
		var sled := _doll.sled
		var sb := sled.global_basis.orthonormalized()
		if _kit_on_sled == Vector3.INF:
			_kit_on_sled = sled.to_local(pos)
			_kit_ride_yaw = wrapf(_kit_yaw - sb.get_euler().y, -PI, PI)
		var lap: Vector3 = sled.to_local(_doll.global_position) + LAP
		_kit_on_sled = _kit_on_sled.lerp(lap, 1.0 - exp(-dt * 12.0))
		_kit_ride_yaw = lerp_angle(_kit_ride_yaw, 0.0, 1.0 - exp(-dt * 10.0))
		_kit_vel = Vector3.ZERO
		_kit.global_transform = Transform3D((sb * Basis(Vector3.UP, _kit_ride_yaw)).scaled(Vector3.ONE * KIT_SCALE), sled.to_global(_kit_on_sled))
		_kit_yaw = (sb * Basis(Vector3.UP, _kit_ride_yaw)).get_euler().y
		return
	else:
		_kit_on_sled = Vector3.INF
		var want := _heel()
		var d := want - pos
		d.y = 0
		if d.length() > 15.0:
			pos = want
			d = Vector3.ZERO
		var speed := clampf((d.length() - 0.25) * 3.0, 0.0, 7.0)
		_kit_vel = _kit_vel.lerp(d.normalized() * speed if d.length() > 0.01 else Vector3.ZERO, 1.0 - exp(-dt * 6.0))
		pos += _kit_vel * dt
		pos.y = lerpf(pos.y, _ground(pos), 1.0 - exp(-dt * 20.0))
		_kit.global_position = pos
		_kit_phase += _kit_vel.length() * dt * 5.0
		var face: float
		if _kit_vel.length() > 0.4:
			face = atan2(-_kit_vel.x, -_kit_vel.z)
		else:
			# 止まっているときは見る所へ。首で届かない分だけ体ごと向く
			var t := _kit_target() - pos
			var want_yaw := atan2(-t.x, -t.z)
			var off := wrapf(want_yaw - _kit_yaw, -PI, PI)
			face = _kit_yaw + signf(off) * maxf(0.0, absf(off) - HEAD_YAW * 0.8)
		_kit_yaw = lerp_angle(_kit_yaw, face, 1.0 - exp(-dt * 8.0))
	_kit.global_basis = Basis(Vector3.UP, _kit_yaw).scaled(Vector3.ONE * KIT_SCALE)


func _pose_kit() -> void:
	var t := float(_frame) / Doll.FPS
	var running := _kit_vel.length() > 0.4
	# 跳ねて走る（コマごとに高さを決める）。体は少し前へ傾く
	_kit_hop = 0.06 * absf(sin(_kit_phase)) if running else 0.0
	if _kit_head:
		var tgt := _kit_target()
		var hp := _kit_head.global_position
		var ld := _kit.global_basis.inverse() * (tgt - hp)
		var yaw := clampf(atan2(-ld.x, -ld.z), -HEAD_YAW, HEAD_YAW)
		var pitch := clampf(atan2(ld.y, Vector2(ld.x, ld.z).length()), -0.6, 0.8)
		if running:
			yaw = 0.0
			pitch = -0.1
		_kit_head.rotation = Vector3(pitch, yaw, 0.0)
	if _kit_tail:
		var sway := 0.35 * sin(t * (9.0 if running else 2.4))
		_kit_tail.rotation = Vector3(0.0, sway, 0.0)
	var body := _kit.find_child("body", true, false) as Node3D
	if body:
		body.position.y = _kit_hop
		body.rotation.x = -0.15 if running else 0.0


# ---------------------------------------------------------------- 時計

func _physics_process(dt: float) -> void:
	if _doll == null or not is_instance_valid(_doll):
		return
	var pointing := _doll.point != Vector3.INF
	if pointing and not _was_pointing:
		_bird_hop = 4   # 指さしが入ると、小鳥がぴょんと跳ねて向き直る
	_was_pointing = pointing
	if _kit:
		_move_kit(dt)
	var fi := Doll.frame_index()
	if fi != _frame:
		_frame = fi
		_rng.seed = hash(Vector2i(_frame, get_instance_id()))
		if _bird:
			_pose_bird()
		if _kit:
			_pose_kit()
	if _bird:
		_place_bird()
	if _kit and _kit_head:
		# 頭と体は同じ揺れで上下する（跳ねる高さはコマで決めた値）
		_kit_head.position.y = _kit_head_base_y() + _kit_hop
		if _kit_tail:
			_kit_tail.position.y = _kit_tail_base_y() + _kit_hop


var _head_y := INF
var _tail_y := INF


func _kit_head_base_y() -> float:
	if _head_y == INF:
		_head_y = _kit_head.position.y
	return _head_y


func _kit_tail_base_y() -> float:
	if _tail_y == INF:
		_tail_y = _kit_tail.position.y if _kit_tail else 0.0
	return _tail_y
