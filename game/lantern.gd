extends Node3D
## 帯に提げたランタン（装備。craft.gd の lanterns）。人形（doll.gd）が 1 つ持ち、人形の lantern（形の名前）と lantern_lit を読む。
## 形は props/build_lantern.py の glb（提げる所が原点、体は下）。左の腰に提げる（右の腰は米袋、右手は紐と雪玉）。
## 揺れは人形と同じ 12 コマの時計で刻む: 歩くと前後に少し振れ、止まると垂れて戻る。居場所だけは毎フレーム帯を追う。
## 灯りは 1 つの OmniLight3D。揺れのコマで跳ばないよう、灯りはランタンの芯をなめらかに追う。
## 揺らぎは小さくゆっくり（±3% ほど、数秒の周期）。画面全体の明るさがちらつかないように、点け消しもふわっと変える。
## 影は落とさない: 腰の灯りは体の影で半分欠け、何人も持つと影の描画が重い。遠いランタンの灯りは消す（光る紙は見える）。
## 見た目だけ。通信には乗せない（誰が点けたかは craft.gd の lamp の出来事）。

const Props := preload("res://props.gd")
const MODELS := {"box": "res://props/lantern/lantern_box.glb", "paper": "res://props/lantern/lantern_paper.glb"}
const LOOKS := ["box", "paper"]          # 装備の画面の並び（0 番が標準）
const COLOR := Color(1.0, 0.68, 0.40)    # ロッジの灯り（props.gd）と同じ、電球色より少し赤み
const ENERGY := 2.2
const RANGE := 7.0
const ATTEN := 1.2
const FADE := 0.35                       # 点け消しにかかる秒
const FAR := 40.0                        # この距離から先は灯りを薄くして消す
## 帯の左の腰の少し後ろ（glb の座標、人形の大きさのまま）。doll.gd の BELT（右）を左右に返す。後ろから（三人称で）見えるように外へ出す
const BELT := {"kasa": Vector3(-0.25, 0.6, 0.07), "origami": Vector3(-0.26, 0.8, 0.07), "news": Vector3(-0.27, 0.34, 0.07),
	"robo": Vector3(-0.21, 0.27, 0.07), "musha": Vector3(-0.19, 0.28, 0.07), "ningyo": Vector3(-0.21, 0.42, 0.07), "golem": Vector3(-0.38, 0.45, 0.1)}
## 人形の大きさに対するランタンの大きさ（小さい人形の足もとに着かないように）
const SIZE := {"kasa": 0.95, "origami": 1.0, "news": 0.72, "robo": 0.75, "musha": 0.72, "ningyo": 0.75, "golem": 1.0}

var doll: Node3D
var _anchor: Node3D            # 帯の所（腰の骨に付ける）
var _body: Node3D              # 形（glb）
var _look := ""
var _papers: Array[MeshInstance3D] = []
var _paper_on: Material
var _light: OmniLight3D
var _core := Vector3(0, -0.21, 0)   # 灯りの芯（形の座標）
var _swing := Vector2.ZERO     # x 前後、z 左右（rad）。コマで決める
var _vel := Vector2.ZERO
var _level := 0.0              # 0 消えている … 1 点いている
var _seed := randf() * 100.0
var _t := 0.0
var _lit_paper := true

static var _paper_off: Material


func _init(d: Node3D) -> void:
	doll = d


func setup(skel: Skeleton3D, hips_rest: Transform3D, kind: String, scale_k: float) -> void:
	var at := BoneAttachment3D.new()
	at.bone_name = "hips"
	skel.add_child(at)
	_anchor = Node3D.new()
	_anchor.position = hips_rest.affine_inverse() * (BELT.get(kind, BELT["kasa"]) as Vector3)
	at.add_child(_anchor)
	top_level = true
	scale = Vector3.ONE * scale_k * SIZE.get(kind, 1.0)
	_light = OmniLight3D.new()
	_light.top_level = true
	_light.light_color = COLOR
	_light.omni_range = RANGE
	_light.omni_attenuation = ATTEN
	_light.shadow_enabled = false
	_light.light_specular = 0.2
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = FAR
	_light.distance_fade_length = 10.0
	_light.visible = false
	add_child(_light)


## 形を替える（"" で外す）
func _set_look(look: String) -> void:
	_look = look
	if _body:
		_body.queue_free()
		_body = null
	_papers.clear()
	visible = look != ""
	if look == "":
		return
	_body = Props.make(MODELS.get(look, MODELS["box"]))
	add_child(_body)
	var mark := _body.find_child("light*", true, false) as Node3D
	if mark:
		_core = (global_transform.affine_inverse() * mark.global_transform).origin
		for c in mark.get_children():   # props.gd が目印にともす灯りは使わない（ここで 1 つだけ持つ）
			c.queue_free()
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.layers = doll.layers | ((1 << 2) if doll.layers == 1 << 1 else 0)   # あなたのランタンは一人称でも見える（見下ろすと腰に揺れている）
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if "paper" in m.name:   # 光る紙（灯りの芯・提灯の紙）
			_papers.append(m)
			_paper_on = m.get_surface_override_material(0)
	_lit_paper = true   # 読んだばかりの紙は光る素材
	_show_paper(_level > 0.5)


## 光る紙の素材を、点いている・消えているで替える（素材は全員で共有なので、消えた方は写しを 1 つ作って使い回す）
func _show_paper(on: bool) -> void:
	if on == _lit_paper or _paper_on == null:
		return
	_lit_paper = on
	if _paper_off == null:
		var m := _paper_on.duplicate() as StandardMaterial3D
		if m:
			m.emission_enabled = false
			m.albedo_color = m.albedo_color.darkened(0.12)
		_paper_off = m if m else _paper_on
	for p in _papers:
		p.set_surface_override_material(0, _paper_on if on else _paper_off)


## 人形が 12 コマごとに呼ぶ: 揺れを決める。speed は歩く速さ (m/s)、phase は歩みの位相、riding は乗っている
func step(speed: float, phase: float, accel: Vector2, riding: bool) -> void:
	if _look == "":
		return
	var dt := 1.0 / 12.0
	# 振り子: 歩みの上下で前後に振れ、速さの変わり目で後ろ・前へ振られる（コマで刻むので、少しかくっと動く）
	var walk := clampf(speed / 3.0, 0.0, 1.0) * (0.0 if riding else 1.0)
	var goal := Vector2(0.16 * walk * sin(phase) - clampf(accel.y * 0.05, -0.3, 0.3), 0.07 * walk * cos(phase * 0.5) - clampf(accel.x * 0.04, -0.2, 0.2))
	if riding:   # 乗っているときは、腰の横で外へ少し傾け、座面や雪にめり込まないように持ち上げる
		goal += Vector2(0.0, -0.9)
	_vel += (goal - _swing) * 55.0 * dt
	_vel *= 0.62
	_swing += _vel * dt
	_swing = _swing.clamp(Vector2(-1.2, -1.2), Vector2(1.2, 1.2))


## 人形が毎物理フレーム呼ぶ: 帯を追い、灯りの強さを変える
func follow(dt: float, yaw: float) -> void:
	var want: String = doll.get("lantern")
	if want != _look:
		_set_look(want)
	var lit: bool = doll.get("lantern_lit") and _look != ""
	_level = move_toward(_level, 1.0 if lit else 0.0, dt / FADE)
	_t += dt
	if _look == "":
		_light.visible = false
		return
	global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(_swing.x, 0.0, _swing.y)) * Basis.from_scale(scale), _anchor.global_position)
	_show_paper(_level > 0.5)
	_light.visible = _level > 0.001
	if _light.visible:
		# 揺らぎ: 遅い 2 つの波を重ねる（±3%）。芯の所へ、なめらかに寄せる
		var flick := 1.0 + 0.02 * sin(_t * 0.9 + _seed) + 0.012 * sin(_t * 2.1 + _seed * 1.7)
		_light.light_energy = ENERGY * flick * smoothstep(0.0, 1.0, _level)
		var core := global_transform * _core
		_light.global_position = core if _light.global_position == Vector3.ZERO else _light.global_position.lerp(core, 1.0 - exp(-dt * 12.0))


## 灯りの芯（世界）。消えていれば INF
func light_point() -> Vector3:
	return _light.global_position if _light and _light.visible else Vector3.INF
