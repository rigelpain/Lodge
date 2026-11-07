extends Node3D
## テラスの双眼鏡台（2026-11-07 代表「テラスに固定の双眼鏡台」「双眼鏡台は木のボタン1枚か雪玉で起動してほしい」）。
## 形は design/binoculars の B（糸巻きを 2 本並べた筒）。足と支柱・左右に回る受け・上下に振る頭の 3 つに分けてある。
## この節の座標: -Z が景色の側、+Z が人の側。原点は足の板の真ん中の床。置き場は main.gd の BINOCULARS（lodge/dims.py の BINOCULAR_STANDS）。
## 動かすのは craft.gd の scope_on・scope_off（みんなの画面で who が同じになる）。のぞく人の動きは player.gd の peek。
## 頭は、のぞいている人の見ている所（doll.gaze）へ向く。どの画面でも同じ形で動く（のぞく人の画面だけ頭を隠す）
## だれものぞいていないときは、深くうつむいて休んでいる。人が近づくと顔を上げて、のぞく側をその人へ向け、止まる。離れるとまたうつむく
## （2026-11-07 代表「お金を払う施設はすべて近づくと動きのあるインタラクションをすることで注意を引いてほしい」。人形と同じ 12 コマ／秒）

const Props := preload("res://props.gd")
const Doll := preload("res://doll.gd")
const Sense := preload("res://stall_sense.gd")

const HEAD_Y := 1.20              # 頭の振る軸の高さ（design/binoculars/ideas.py の HEAD_Z）。人形の目の高さに寄せてある
const EYE_Y := 1.43               # のぞく人の視点の高さ。手すり（1.10 m）の上から見渡す。頭は隠すので形とは合わせなくてよい
const POCKET := Vector3(0, 0.82, 0.155)   # 料金の袋の口（支柱の人の側）
const USE_Z := Vector2(0.15, 1.7) # F が届く、人の側の奥行き (m)
const USE_X := 1.1                # F が届く横の幅 (m)
const USE_FACE := 0.2             # 台の方を向いている（見ている向きと台への向きの合い具合）
const STAND_R := 0.52             # のぞく人の立つ所の、支柱からの距離 (m)。体の当たり 0.35 ＋ 支柱の当たり 0.14 より少し外
const YAW_MAX := 1.35             # 見回せる幅（景色の向きから左右へ。rad）。人が手すりの側へ回らない
const PITCH := Vector2(-0.45, 0.55)   # 見下ろす・見上げる幅 (rad)
const SENSE_R := 4.0              # この距離に人が来ると顔を上げる (m)。F が届く奥行き（USE_Z）より広い
const REST_PITCH := -0.42         # だれもいないときのうつむき
const AWAKE_PITCH := 0.04         # 人が来たときの顔の上げ
const WAKE_K := 0.24              # 顔を上げるばね（コマごと。少し行き過ぎて戻る）
const WAKE_D := 0.62
const WAKE_KICK := 0.16           # 顔を上げる出だしの勢い（ぴょこんと上がる）
const REST_K := 0.07              # うつむくときはゆっくり、跳ねない
const REST_D := 0.6

var index := 0                    # 台の番号（main.gd の binocular_stands の順。通信の出来事で使う）
var who := -1                     # のぞいている人の番号（-1 はだれもいない）
var craft: Node                   # 工房の配り役（だれがのぞいているかを読む。main.gd が入れる）
var main: Node                    # main.gd が入れる
var _yaw: Node3D
var _pitch: Node3D
var _yaw_goal := 0.0
var _pitch_goal := REST_PITCH
var _yaw_v := 0.0
var _pitch_v := 0.0
var _awake := false
var _moving := false
var _check := 0.0
var _frame := -1


func _ready() -> void:
	var base := Props.make("res://props/binocular_stand/binocular_stand.glb")
	base.rotation.y = PI      # 模型の景色の側は +Z
	add_child(base)
	_yaw = Node3D.new()
	add_child(_yaw)
	var yk := Props.make("res://props/binocular_stand/binocular_yoke.glb")
	yk.rotation.y = PI
	_yaw.add_child(yk)
	_pitch = Node3D.new()
	_pitch.position.y = HEAD_Y
	_pitch.rotation.x = REST_PITCH
	_yaw.add_child(_pitch)
	var head := Props.make("res://props/binocular_stand/binocular_head.glb")
	head.rotation.y = PI
	_pitch.add_child(head)
	var body := StaticBody3D.new()   # 支柱だけ。足の板はつまずかない
	body.name = "StandBody"
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.14
	cyl.height = 1.35
	col.shape = cyl
	col.position.y = 0.675
	body.add_child(col)
	add_child(body)


func _process(dt: float) -> void:
	if who >= 0:
		if craft:
			var person: Node3D = craft._person(who)
			if person and person.doll and person.doll.gaze != Vector3.INF:
				var d: Vector3 = global_basis.inverse() * (person.doll.gaze - to_global(Vector3.UP * HEAD_Y))
				_yaw_goal = clampf(atan2(-d.x, -d.z), -YAW_MAX, YAW_MAX)
				_pitch_goal = clampf(atan2(d.y, Vector2(d.x, d.z).length()), PITCH.x, PITCH.y)
		_yaw.rotation.y = lerp_angle(_yaw.rotation.y, _yaw_goal, minf(1.0, dt * 10.0))
		_pitch.rotation.x = lerp_angle(_pitch.rotation.x, _pitch_goal, minf(1.0, dt * 10.0))
		_yaw_v = 0.0
		_pitch_v = 0.0
		_moving = true   # 離れたら、そこから休みの姿へ
		_check = 0.0
		return
	_check -= dt
	if _check <= 0.0:
		_check = Sense.CHECK
		_look_for_someone()
	if not _moving:
		return
	var f := Doll.frame_index()
	if f == _frame:
		return
	_frame = f
	_step()


## 近くの人を見る: 顔を上げて、のぞく側（+Z）をその人へ。いなければ前を向いてうつむく
func _look_for_someone() -> void:
	var p := Sense.nearest(main, self, SENSE_R)
	var yaw := 0.0
	if p:
		var l := to_local(p.global_position)
		yaw = clampf(atan2(l.x, l.z), -YAW_MAX, YAW_MAX)
	if p != null and not _awake:
		var audio = main.get_node_or_null("Audio") if main else null
		if audio:
			audio.kitchen(self, "stall_tap", -14.0)
		_pitch_v = WAKE_KICK
	_awake = p != null
	var pitch := AWAKE_PITCH if _awake else REST_PITCH
	if absf(yaw - _yaw_goal) > 0.02 or pitch != _pitch_goal:
		_yaw_goal = yaw
		_pitch_goal = pitch
		_moving = true


func _step() -> void:
	var k := WAKE_K if _awake else REST_K
	var d := WAKE_D if _awake else REST_D
	_yaw_v = _yaw_v * d + wrapf(_yaw_goal - _yaw.rotation.y, -PI, PI) * k
	_pitch_v = _pitch_v * d + (_pitch_goal - _pitch.rotation.x) * k
	_yaw.rotation.y += _yaw_v
	_pitch.rotation.x += _pitch_v
	if absf(_yaw_v) < 0.002 and absf(_pitch_v) < 0.002 and absf(_yaw_goal - _yaw.rotation.y) < 0.003 and absf(_pitch_goal - _pitch.rotation.x) < 0.003:
		_yaw.rotation.y = _yaw_goal
		_pitch.rotation.x = _pitch_goal
		_yaw_v = 0.0
		_pitch_v = 0.0
		_moving = false


## F が届く所で、台の方を向いているか（だれかがのぞいていても答える。空きは who を読む）
func in_reach(p: Node3D) -> bool:
	if p == null:
		return false
	var l := to_local(p.global_position)
	if absf(l.x) > USE_X or l.z < USE_Z.x or l.z > USE_Z.y or absf(l.y) > 1.0:
		return false
	var to_me := global_position - p.global_position
	to_me.y = 0.0
	return to_me.length() < 0.01 or (-p.global_basis.z).dot(to_me.normalized()) > USE_FACE


## いま向いている向き yaw（世界の角）を、見回せる幅に収める
func clamp_yaw(yaw: float) -> float:
	var base := global_rotation.y
	return base + clampf(wrapf(yaw - base, -PI, PI), -YAW_MAX, YAW_MAX)


## のぞく人の立つ所（世界の座標）。見ている向きの反対へ STAND_R だけ下がった、床の高さ
func spot(yaw: float) -> Vector3:
	return global_position + Basis(Vector3.UP, yaw) * Vector3(0, 0, STAND_R)


## のぞく人の目（世界の座標）。のぞく人の画面では頭を隠すので、形は邪魔をしない
func eye_world() -> Vector3:
	return global_position + Vector3.UP * EYE_Y


## のぞく人の画面で、頭を隠す・戻す（カメラが頭の中に入るので）
func hide_head(on: bool) -> void:
	_pitch.visible = not on


## 料金を入れた: 木のボタンか雪玉が手もとから袋の口へ落ちる（みんなの画面で）
func drop_fee(paid: String, from: Vector3) -> void:
	var mi := MeshInstance3D.new()
	if paid == "ball":
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.10
		mi.mesh = sphere
	else:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.04
		disc.bottom_radius = 0.04
		disc.height = 0.012
		mi.mesh = disc
	var look := preload("res://look.gd")
	mi.material_override = look.felt(Color(0.97, 0.97, 1.0)) if paid == "ball" else look.felt(Color(0.62, 0.42, 0.24))
	add_child(mi)
	var goal := to_global(POCKET)
	mi.global_position = from
	var mid := from.lerp(goal, 0.5) + Vector3.UP * 0.14
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(mi):
			mi.global_position = from.lerp(mid, t).lerp(mid.lerp(goal, t), t)
	, 0.0, 1.0, 0.28)
	tw.tween_callback(mi.queue_free)
