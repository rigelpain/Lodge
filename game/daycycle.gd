extends Node
## 一日の巡り（自動読み込み）。20 分で一日が経つ。
## 場面の太陽（DirectionalLight3D）と WorldEnvironment を見つけて、時刻に合わせて太陽の高さと向き・光の色、
## 空と霧の色、環境光を変える。夜は同じ灯りを月にして、青く淡く照らす（空の円は月の色になる）。
## 画面の右下に日時計を出す。数字は出さず、扇形の目盛りの上を、昼は太陽、夜は月が東から西へ渡る。
## 確かめ用: --time=時（例 --time=17.5 で 17:30 から）、--day=秒（一日の長さ）

const DAY_SECONDS := 1200.0       # 20 分で一日
const START_HOUR := 10.0          # 始まりは朝の 10 時
const SUN_MAX := 42.0             # 正午の太陽の高さ（度）
const SKY_EVERY := 0.5            # 空と霧の色を変える間隔（秒）。空の映り込みの計算を毎フレームしないように

var hour := START_HOUR            # いまの時刻（0〜24）
var day_seconds := DAY_SECONDS
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _sky_t := 0.0
var _dial: Control
var _sky_top := DAY_TOP          # 日時計の扇の地の色（いまの空の上の色）

# 空の色: 昼・夕・夜（上・地平・地面・雲）
const DAY_TOP := Color(0.50, 0.66, 0.88)
const DAY_HOR := Color(0.87, 0.91, 0.95)
const DAY_GND := Color(0.80, 0.85, 0.90)
const DAY_CLOUD := Color(0.99, 0.98, 0.96)
const DUSK_TOP := Color(0.36, 0.40, 0.64)
const DUSK_HOR := Color(0.98, 0.66, 0.46)
const DUSK_GND := Color(0.62, 0.52, 0.56)
const DUSK_CLOUD := Color(0.98, 0.74, 0.62)
const NIGHT_TOP := Color(0.04, 0.06, 0.14)
const NIGHT_HOR := Color(0.11, 0.13, 0.23)
const NIGHT_GND := Color(0.09, 0.11, 0.17)
const NIGHT_CLOUD := Color(0.22, 0.24, 0.32)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			hour = fposmod(float(a.get_slice("=", 1)), 24.0)
		elif a.begins_with("--day="):
			day_seconds = maxf(1.0, float(a.get_slice("=", 1)))


func _process(dt: float) -> void:
	if _sun == null or not is_instance_valid(_sun):
		if not _find():
			return
		_make_dial()
		_apply(true)
	hour = fposmod(hour + dt * 24.0 / day_seconds, 24.0)
	_sky_t += dt
	_apply(_sky_t >= SKY_EVERY)
	if _dial:
		_dial.queue_redraw()


## 時刻を "10:24" の形で
func clock() -> String:
	return "%d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


## 右下の日時計
func _make_dial() -> void:
	if _dial and is_instance_valid(_dial):
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	_dial = Dial.new()
	_dial.cycle = self
	_dial.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dial.offset_left = -(Dial.R * 2 + 16 + 12)
	_dial.offset_right = -16
	_dial.offset_top = -(Dial.R + 16 + 14)
	_dial.offset_bottom = -12
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_dial)
	get_tree().current_scene.add_child(layer)


## 扇形の日時計: 左が東（6 時・18 時の地平）、上が南中（正午・真夜中）、右が西。
## 昼の 12 時間は太陽が、夜の 12 時間は月が、同じ扇を左から右へ渡る。目盛りは 3 時間ごと
class Dial extends Control:
	const R := 42.0
	var cycle: Node

	func _draw() -> void:
		var c := Vector2(size.x / 2.0, size.y - 6.0)       # 扇の要（地平の真ん中）
		var h: float = cycle.hour
		var day := h >= 6.0 and h < 18.0
		var f := (h - 6.0) / 12.0 if day else fposmod(h - 18.0, 24.0) / 12.0
		# 扇の地: いまの空の色を淡く
		var fan := PackedVector2Array([c])
		for i in 33:
			var a := PI * (1.0 - i / 32.0)
			fan.append(c + Vector2(cos(a), -sin(a)) * R)
		var bg: Color = cycle._sky_top
		bg.a = 0.55
		draw_colored_polygon(fan, bg)
		for pass_ in 2:   # 下に薄い影の線を敷いてから白い線（白い雪の上でも読めるように）
			var col := Color(0.15, 0.18, 0.25, 0.35) if pass_ == 0 else Color(1, 1, 1, 0.9)
			var w := 4.5 if pass_ == 0 else 2.0
			draw_arc(c, R, PI, TAU, 40, col, w, true)
			draw_line(c - Vector2(R + 6, 0), c + Vector2(R + 6, 0), col, w, true)   # 地平
			for k in 5:                                       # 目盛り（3 時間ごと）
				var a := PI * (1.0 - k / 4.0)
				var d := Vector2(cos(a), -sin(a))
				draw_line(c + d * (R - 7.0), c + d * R, col, w, true)
		var ang := PI * (1.0 - f)
		var p := c + Vector2(cos(ang), -sin(ang)) * (R - 15.0)
		if day:
			_sun(p)
		else:
			_moon(p)

	func _sun(p: Vector2) -> void:
		for i in 8:                                           # 光の筋
			var a := TAU * i / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_line(p + d * 8.5, p + d * 12.0, Color(1.0, 0.80, 0.30), 2.0, true)
		draw_circle(p, 7.0, Color(1.0, 0.82, 0.35))
		draw_circle(p, 7.0, Color(0.85, 0.55, 0.15, 0.9), false, 1.5, true)

	func _moon(p: Vector2) -> void:
		var pts := PackedVector2Array()                       # 三日月: 外の円の右半分と、内の楕円の弧
		for i in 17:
			var t := -PI / 2.0 + PI * i / 16.0
			pts.append(p + Vector2(cos(t), sin(t)) * 8.0)
		for i in 17:
			var t := PI / 2.0 - PI * i / 16.0
			pts.append(p + Vector2(cos(t) * 3.2, sin(t) * 8.0))
		draw_colored_polygon(pts, Color(0.97, 0.95, 0.82))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.75, 0.72, 0.55, 0.9), 1.2, true)


func _find() -> bool:
	var root := get_tree().current_scene
	if root == null:
		return false
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		_sun = n
		break
	for n in root.find_children("*", "WorldEnvironment", true, false):
		_env = (n as WorldEnvironment).environment
		break
	if _sun == null or _env == null:
		_sun = null
		return false
	if _env.sky and _env.sky.sky_material is ShaderMaterial:
		_sky_mat = _env.sky.sky_material
	return true


func _apply(sky_too: bool) -> void:
	var el := SUN_MAX * sin((hour - 6.0) / 12.0 * PI)    # 太陽の高さ（度）。6 時に昇り 18 時に沈む
	var yaw := -40.0 + (14.0 - hour) * 15.0              # 東から南を通って西へ。14 時がこれまでの午後の光の向き
	var day := smoothstep(-4.0, 12.0, el)                # 昼の度合い
	var dusk := exp(-pow(el / 8.0, 2.0))                 # 地平の近く（朝焼け・夕焼け）
	if el > -1.0:   # 太陽
		_sun.rotation_degrees = Vector3(-maxf(el, 1.0), yaw, 0)
		var warm := 1.0 - smoothstep(0.0, 25.0, el)
		_sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.60, 0.36), warm)
		_sun.light_energy = 1.45 * smoothstep(-1.0, 14.0, el)
	else:           # 月: 太陽の反対の空から、青く淡く
		_sun.rotation_degrees = Vector3(-maxf(-el, 1.0), yaw + 180.0, 0)
		_sun.light_color = Color(0.62, 0.72, 1.0)
		_sun.light_energy = 0.22 * smoothstep(1.0, 12.0, -el)
	_env.ambient_light_energy = lerpf(0.40, 0.75, day)
	if not sky_too:
		return
	_sky_t = 0.0
	var top := NIGHT_TOP.lerp(DAY_TOP, day).lerp(DUSK_TOP, dusk * 0.5)
	_sky_top = top
	var hor := NIGHT_HOR.lerp(DAY_HOR, day).lerp(DUSK_HOR, dusk * 0.7)
	var gnd := NIGHT_GND.lerp(DAY_GND, day).lerp(DUSK_GND, dusk * 0.5)
	var cloud := NIGHT_CLOUD.lerp(DAY_CLOUD, day).lerp(DUSK_CLOUD, dusk * 0.6)
	var disc := Color(1.0, 0.86, 0.60) if el > -1.0 else Color(0.92, 0.94, 1.0)   # フェルトの太陽／月
	if _sky_mat:
		_sky_mat.set_shader_parameter("top_color", top)
		_sky_mat.set_shader_parameter("horizon_color", hor)
		_sky_mat.set_shader_parameter("ground_color", gnd)
		_sky_mat.set_shader_parameter("cloud_color", cloud)
		_sky_mat.set_shader_parameter("sun_color", disc)
	_env.fog_light_color = Color(0.86, 0.90, 0.94).lerp(hor, (1.0 - day) * 0.8 + dusk * 0.15)   # 霧は夜と夕に地平の色へ寄せる
