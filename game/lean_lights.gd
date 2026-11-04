extends Node3D
## 外の下屋（ソリ屋と立てかけ台）の灯り（2026-11-04 代表「ソリ屋とソリ置き場暗いね！照明付けてあげよ！」）。
## 形は紙と木の提灯（props/furniture/pendant_lantern.glb。提灯・筒・円錐の絵から代表が選んだ）。下屋の屋根から提げ、大きなミシンに合わせて大きくする。
## 灯りは影を落とさない SpotLight3D を下へ向けて、ソリ屋に 1 つ、立てかけ台に 2 つ。色はロッジの灯りと同じ、電球色より少し赤み（lodge.gd）。
## 時刻は daycycle.gd の daylight() を見る: 昼は消えていて、日が傾くと点く（昼の下屋は外の光で十分に見える。絵で確かめた）。紙も灯りと一緒に光る。
## main.gd の _furnish_lodge がロッジの子として置く（置き物なので、通信の誰の画面でも同じ）。確かめ用: --no-lean-lights で置かない

const Props := preload("res://props.gd")

const COLOR := Color(1.0, 0.68, 0.40)    # 電球色より少し赤み（lodge.gd の灯りと同じ）
const KIND_DEFAULT := "lantern"
const SCALE := 1.5                       # こたつの上の倍。ミシンの背が 3.7 m あるので
## 灯りの場所（ロッジの座標 x 東, y 北）と、強さ, 届く範囲, 真下から東（物の側）への傾き（度）, 広がり（度）。
## ソリ屋は番台とミシンの前のあいだ、立てかけ台は通り道の上に 2 つ。傾きと広がりの足した分が水平を越えるほど物の上まで届くが、
## 越えすぎると屋根の上の雪まで届く（影を落とさない灯りは屋根を通り抜ける）。壁から遠いソリ屋の灯りは控えめに
const PLACES := [
	[Vector2(-27.4, -6.4), 2.4, 10.0, 35.0, 70.0],
	[Vector2(-26.4, 0.8), 2.2, 10.0, 45.0, 75.0],
	[Vector2(-26.4, 7.0), 2.2, 10.0, 45.0, 75.0],
]
const ATTEN := 0.6                       # なだらかに届かせる（lodge_lights.gd と同じ考え）
const HANG_TOP := 3.1                    # 傘の上端の高さ（雪の面から）。頭に当たらない
const DAY_ON := Vector2(0.35, 0.95)      # daylight() がこの値のあいだで、灯りが満ちる ↔ 消える。昼は消え、午後 4 時ごろから点き、夕方には満ちる
const FADE_BEGIN := 45.0                 # 灯りの光をこの距離から薄くする（丘から見ても、ロッジの目印になるように遠めに）
const FADE_LEN := 10.0
const GLOW := 0.7                       # 紙の傘の光の強さ（夜）
const GLOW_DAY := 0.3                    # 昼（消えているとき）の紙の明るさ。屋根の陰で紙が灰色に沈まないように
const UPDATE := 0.5                      # 強さを見直す間隔 (s)。時刻はゆっくり進むので毎コマは見ない
## 下屋の屋根の下面（lodge/dims.py の LEAN）: 外の端 x -30.18 で 3.6 m、壁 x -21.82 で 4.725 m
const ROOF_OUT := Vector2(-30.18, 3.6)
const ROOF_WALL := Vector2(-21.816, 4.725)

var kind := KIND_DEFAULT
var _lights: Array[SpotLight3D] = []
var _base: Array[float] = []
var _paper: Array[StandardMaterial3D] = []
var _t := UPDATE


func _ready() -> void:
	for spec in PLACES:
		var at: Vector2 = spec[0]
		var roof := lerpf(ROOF_OUT.y, ROOF_WALL.y, (at.x - ROOF_OUT.x) / (ROOF_WALL.x - ROOF_OUT.x))
		var root := Node3D.new()
		root.position = Vector3(at.x, HANG_TOP, -at.y)
		add_child(root)
		var p := Props.make("res://props/furniture/pendant_%s.glb" % kind)
		for m in p.find_children("light*", "Node3D", true, false):
			if not m is MeshInstance3D:
				m.free()
		p.scale = Vector3.ONE * SCALE
		root.add_child(p)
		for c in p.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var nm := String(mi.name)
			if "felt" in nm or "thread" in nm:   # コード（glb では 1 m ほど）を屋根まで
				mi.scale.y = (roof - HANG_TOP) / (mi.get_aabb().size.y * SCALE)
			elif "paper" in nm:
				var src := mi.get_active_material(0) as StandardMaterial3D
				if src:
					var mat := src.duplicate() as StandardMaterial3D
					mat.emission_enabled = true
					mat.emission = COLOR
					mi.set_surface_override_material(0, mat)
					_paper.append(mat)
		var l := SpotLight3D.new()   # 下へ向ける。四方へ広がる灯りだと、影がないので屋根を通り抜けて、屋根の上の雪まで照らしてしまう
		l.light_color = COLOR
		l.spot_range = spec[2]
		l.spot_attenuation = ATTEN
		l.spot_angle = spec[4]
		l.spot_angle_attenuation = 1.2
		l.rotation = Vector3(-PI / 2.0 + deg_to_rad(spec[3]), -PI / 2.0, 0.0)   # 真下から壁の側（東）へ傾ける
		l.light_specular = 0.3
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = FADE_BEGIN
		l.distance_fade_length = FADE_LEN
		l.position = Vector3(0, -0.2 * SCALE, 0)   # 提灯のまんなか
		root.add_child(l)
		_lights.append(l)
		_base.append(float(spec[1]))


func _process(dt: float) -> void:
	_t += dt
	if _t < UPDATE:
		return
	_t = 0.0
	var cycle := get_node_or_null("/root/DayCycle")
	var day: float = cycle.daylight() if cycle else 0.0
	var k := 1.0 - smoothstep(DAY_ON.x, DAY_ON.y, day)
	for i in _lights.size():
		_lights[i].light_energy = _base[i] * k
		_lights[i].visible = k > 0.01   # 昼は灯りごと消して、軽くする
	for mat in _paper:
		mat.emission_energy_multiplier = lerpf(GLOW_DAY, GLOW, k)
