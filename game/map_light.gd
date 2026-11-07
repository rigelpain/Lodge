extends Node3D
## ロッジ前の地図の看板の灯り（2026-11-07 代表「地図の看板にライトを当ててほしい」）。
## 額の上から木の腕を 2 本手前へ出し、下屋と同じ紙と木の提灯（lean_lights.gd）を提げて、影を落とさない SpotLight3D で看板を照らす。
## 灯りは LAYER の物（看板の面・額・まち針・提灯）だけに当てる。影がない灯りは看板を通り抜けて裏の雪まで照らしてしまうのと、広い雪に灯りを計算させないため。
## 時刻は daycycle.gd の daylight() を見る: 昼は灯りごと消え、日が傾くと点く（下屋の灯りと同じ DAY_ON）。遠くでは灯りを薄くして消す。
## area_flags.gd の _put_map が看板の子として置く（置き物なので、通信の誰の画面でも同じ）。

const Props := preload("res://props.gd")
const LeanLights := preload("res://lean_lights.gd")

const LAYER := 1 << 17               # 灯りを当てる物の印（見た目の層 18）。ほかの層はそのまま
const SCALE := 1.1                   # 提灯の大きさ（下屋は 1.5）
const SIDE := 2.2                    # 看板の真ん中から提灯までの横の距離 (m)
const REACH := 1.7                   # 看板の面から提灯までの手前への距離 (m)
const CORD := 0.3                    # 腕から提灯の上端までのコードの長さ (m)
const COLOR := Color(1.0, 0.93, 0.82)   # ロッジの灯りより白く。橙の光だと藍の布が黒く沈み、まち針の色も読めない（提灯の紙の色はロッジの灯りのまま）
const ENERGY := 1.7
const RANGE := 11.0
const ATTEN := 0.3                   # 上と下の明るさの差を小さく
const ANGLE := 78.0                  # 広がり（度）
const TILT := 52.0                   # 水平から下への傾き（度）
const FADE_BEGIN := 70.0             # 灯りをこの距離から薄くする（玄関の前からロッジの外の広場まで見える）
const FADE_LEN := 10.0
const SEE := 90.0                    # 提灯の形を描くのをやめる距離 (m)

var top := 6.5                       # 額の上の端の高さ（看板の足もとから, m）
var wood: StandardMaterial3D         # 額と同じ木の材質
var _lights: Array[SpotLight3D] = []
var _paper: Array[StandardMaterial3D] = []
var _t := LeanLights.UPDATE


func _ready() -> void:
	var arm_wood := wood.duplicate() as StandardMaterial3D   # 腕は下の面しか見えず、日陰で真っ黒になるので、木の色を少し自分で光らせる
	arm_wood.emission_enabled = true
	arm_wood.emission = wood.albedo_color
	arm_wood.emission_energy_multiplier = 0.35
	for sx in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.12, REACH + 0.1)
		arm.mesh = bm
		arm.material_override = arm_wood
		arm.position = Vector3(sx * SIDE, top - 0.06, REACH / 2.0)
		_lit(arm)
		add_child(arm)
		var root := Node3D.new()
		root.position = Vector3(sx * SIDE, top - 0.12 - CORD, REACH - 0.1)
		add_child(root)
		_lantern(root)
		var l := SpotLight3D.new()
		l.light_color = COLOR
		l.light_cull_mask = LAYER
		l.spot_range = RANGE
		l.spot_attenuation = ATTEN
		l.spot_angle = ANGLE
		l.spot_angle_attenuation = 0.5
		l.light_specular = 0.2
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = FADE_BEGIN
		l.distance_fade_length = FADE_LEN
		l.position = Vector3(0, -0.2 * SCALE, 0)   # 提灯のまんなか
		l.rotation = Vector3(deg_to_rad(-TILT), 0, 0)   # 看板（-Z）へ、斜め下に向ける
		root.add_child(l)
		_lights.append(l)


## 提灯（下屋と同じ形）。紙は灯りと一緒に光る
func _lantern(root: Node3D) -> void:
	var p := Props.make("res://props/furniture/pendant_%s.glb" % LeanLights.KIND_DEFAULT)
	for m in p.find_children("light*", "Node3D", true, false):
		if not m is MeshInstance3D:
			m.free()
	p.scale = Vector3.ONE * SCALE
	root.add_child(p)
	for c in p.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		_lit(mi)
		mi.visibility_range_end = SEE
		var nm := String(mi.name)
		if "felt" in nm or "thread" in nm:   # コードを腕まで
			mi.scale.y = CORD / (mi.get_aabb().size.y * SCALE)
		elif "paper" in nm:
			var src := mi.get_active_material(0) as StandardMaterial3D
			if src:
				var mat := src.duplicate() as StandardMaterial3D
				mat.emission_enabled = true
				mat.emission = LeanLights.COLOR
				mi.set_surface_override_material(0, mat)
				_paper.append(mat)


## 影を落とさず、看板の灯りが当たる物にする
static func _lit(g: GeometryInstance3D) -> void:
	g.layers |= LAYER
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(dt: float) -> void:
	_t += dt
	if _t < LeanLights.UPDATE:
		return
	_t = 0.0
	var cycle := get_node_or_null("/root/DayCycle")
	var day: float = cycle.daylight() if cycle else 0.0
	var k := 1.0 - smoothstep(LeanLights.DAY_ON.x, LeanLights.DAY_ON.y, day)
	for l in _lights:
		l.light_energy = ENERGY * k
		l.visible = k > 0.01   # 昼は灯りごと消して、軽くする
	for mat in _paper:
		mat.emission_energy_multiplier = lerpf(LeanLights.GLOW_DAY, LeanLights.GLOW, k)
