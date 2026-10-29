extends Node
## 一日の巡り（自動読み込み）。20 分で一日が経つ。
## 場面の太陽（DirectionalLight3D）と WorldEnvironment を見つけて、時刻に合わせて太陽の高さと向き・光の色、
## 空と霧の色、環境光を変える。夜は同じ灯りを月にして、青く淡く照らす（空の円は月の色になる）。
## 画面の右下に日時計を出す。数字は出さず、細い線の扇形の目盛りの上を、昼は太陽、夜は月が東から西へ渡る。
## 確かめ用: --time=時（例 --time=17.5 で 17:30 から）、--day=秒（一日の長さ）

const DAY_SECONDS := 1200.0       # 20 分で一日
const START_HOUR := 10.0          # 始まりは朝の 10 時
const SUN_MAX := 34.0             # 正午の太陽の高さ（度）。低めにして、一日じゅう影が長く落ちる
const SUN_ENERGY := 3.2           # 昼の陽の強さ。main.gd の ACES の白の上限（6）と合わせる
const DAY_SUN := Color(1.0, 0.86, 0.70)    # 昼の陽の色（暖かめ）
const AMB_DAY := 0.5              # 昼の環境光（空の青）。低いほど日なたと日かげの差がはっきりする
const AMB_NIGHT := 0.3
const SKY_EVERY := 0.5            # 空と霧の色を変える間隔（秒）。空の映り込みの計算を毎フレームしないように

var hour := START_HOUR            # いまの時刻（0〜24）
var day_seconds := DAY_SECONDS
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _sky_t := 0.0
var _dial: Control
var dial_right := 16.0            # 画面の右の端から日時計までの間（px）。右下の自分の小窓（self_cam.gd）があれば、その左に寄せる
var _ink_t := 0.0
var _ink_target := 1.0

# 空の色: 昼・夕・夜（上・地平・地面・雲）
const DAY_TOP := Color(0.30, 0.52, 0.88)    # 澄んだ濃い青。影の側にこの青が映る
const DAY_HOR := Color(0.74, 0.84, 0.95)
const DAY_GND := Color(0.70, 0.78, 0.88)
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
		_dial.offset_right = -dial_right
		_dial.offset_left = -(Dial.R * 2 + 10 + dial_right)
		_dial.pivot_offset = _dial.size   # 右下の角を動かさずに、HUD とそろえた大きさにする
		_dial.scale = Vector2.ONE * preload("res://hud_icons.gd").ui_scale(_dial.get_viewport_rect().size.y)
		_update_ink(dt)
		_dial.ink = move_toward(_dial.ink, _ink_target, dt * 2.0)
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
	_dial.offset_left = -(Dial.R * 2 + 10 + dial_right)
	_dial.offset_right = -dial_right
	_dial.offset_top = -(Dial.R + 16 + 14)
	_dial.offset_bottom = -12
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_dial)
	get_tree().current_scene.add_child(layer)


## 扇形の日時計: 左が東（6 時・18 時の地平）、上が南中（正午・真夜中）、右が西。
## 昼の 12 時間は太陽が、夜の 12 時間は月が、同じ扇を左から右へ渡る。目盛りは 3 時間ごと。
## 塗りはなく、細い線だけ。線の色は後ろの明るさを見て白と黒のあいだで変える（ink: 1 白、0 黒）
class Dial extends Control:
	const R := 40.0
	const W := 1.2
	var cycle: Node
	var ink := 1.0

	func _draw() -> void:
		var col := Color(ink, ink, ink, 0.85)
		var c := Vector2(size.x / 2.0, size.y - 6.0)       # 扇の要（地平の真ん中）
		var h: float = cycle.hour
		var day := h >= 6.0 and h < 18.0
		var f := (h - 6.0) / 12.0 if day else fposmod(h - 18.0, 24.0) / 12.0
		draw_arc(c, R, PI, TAU, 48, col, W, true)
		draw_line(c - Vector2(R + 5, 0), c + Vector2(R + 5, 0), col, W, true)   # 地平
		for k in 5:                                           # 目盛り（3 時間ごと）
			var a := PI * (1.0 - k / 4.0)
			var d := Vector2(cos(a), -sin(a))
			draw_line(c + d * (R - 5.0), c + d * R, col, W, true)
		var ang := PI * (1.0 - f)
		var p := c + Vector2(cos(ang), -sin(ang)) * (R - 14.0)
		if day:
			draw_arc(p, 5.0, 0.0, TAU, 24, col, W, true)     # 太陽: 円と 8 本の光
			for i in 8:
				var d := Vector2(cos(TAU * i / 8.0), sin(TAU * i / 8.0))
				draw_line(p + d * 7.5, p + d * 10.0, col, W, true)
		else:
			var pts := PackedVector2Array()                   # 月: 三日月の輪郭
			for i in 17:
				var t := -PI / 2.0 + PI * i / 16.0
				pts.append(p + Vector2(cos(t), sin(t)) * 7.0)
			for i in 17:
				var t := PI / 2.0 - PI * i / 16.0
				pts.append(p + Vector2(cos(t) * 2.8, sin(t) * 7.0))
			pts.append(pts[0])
			draw_polyline(pts, col, W, true)


## 日時計の線を、昼は黒、夜は白に寄せる。
## 以前は画面を読み戻して後ろの明るさを測っていたが、全画素だと 1 回 100 ms 級の停止になり
## ゲーム全体がガクついたので、時刻から決める（日時計の後ろはほぼ雪か空で、明るさは昼夜で決まる）
func _update_ink(dt: float) -> void:
	_ink_t += dt
	if _ink_t < 0.5:
		return
	_ink_t = 0.0
	var daylight: float = clampf((sin((hour - 6.0) / 12.0 * PI) + 0.15) / 1.15, 0.0, 1.0)   # 6 時〜18 時が昼
	_ink_target = 0.0 if daylight > 0.55 else (1.0 if daylight < 0.35 else _ink_target)   # 境目で行き来しないよう、間を空ける


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
		_sun.light_color = DAY_SUN.lerp(Color(1.0, 0.56, 0.30), warm)
		_sun.light_energy = SUN_ENERGY * smoothstep(-1.0, 14.0, el)
	else:           # 月: 太陽の反対の空から、青く淡く
		_sun.rotation_degrees = Vector3(-maxf(-el, 1.0), yaw + 180.0, 0)
		_sun.light_color = Color(0.62, 0.72, 1.0)
		_sun.light_energy = 0.45 * smoothstep(1.0, 12.0, -el)
	_env.ambient_light_energy = lerpf(AMB_NIGHT, AMB_DAY, day)
	if not sky_too:
		return
	_sky_t = 0.0
	var top := NIGHT_TOP.lerp(DAY_TOP, day).lerp(DUSK_TOP, dusk * 0.5)
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
	_env.fog_light_color = Color(0.74, 0.82, 0.95).lerp(hor, (1.0 - day) * 0.8 + dusk * 0.15)   # 霧は夜と夕に地平の色へ寄せる
