extends Node3D

const Look := preload("res://look.gd")
## 原型の場面: こんもりした丘、ソリ、あなた（手だけ見える一人称）、押すのを手伝う仲間。
## 確かめ用の起動引数（-- のあとに付ける）:
##   --bots=N      仲間の数（既定 1）
##   --no-player   あなたを出さず、仲間だけで押す（速さを比べる用）
##   --shot=PATH   数秒後に画面を PNG で保存して終わる
##   --log         ソリの高さを1秒ごとに出す
##   --no-wind     滑るときの風のエフェクトを出さない（重さを比べる用）
##   --cam=x,y,z,tx,ty,tz  --no-player のときのカメラの位置と見る先（ロッジを撮る用）

const HILL_H := 18.0      # 丘の高さ (m)
const HILL_R := 25.0      # 丘の広がり (m)
const SIZE := 256         # 地面の一辺 (m)。Jolt の地形は 2 のべき乗 + 1 点で作る
const START := Vector3(0, 0, 38)

## ロッジ（lodge/ の Blender の台本で作った glb）。スタートの先、少し西の麓に置き、
## 正面（ガラスの食堂とテラス、glb の +Z）を頂上へ向ける。足もとの地面はならす
const LODGE_POS := Vector2(-27, 76)          # (x, z)
const LODGE_YAW := 2.8004                    # atan2(27, -76): 正面を頂上の向きへ
const LODGE_PAD := Rect2(-32, -16, 57, 37)   # ならす範囲（ロッジの座標の x, z）。下屋から外階段の踊り場まで
const LODGE_BLEND := 10.0                    # ならした所から丘へ戻るまでの幅 (m)

const Sled := preload("res://sled.gd")
const Props := preload("res://props.gd")
const Player := preload("res://player.gd")
const Bot := preload("res://bot.gd")
const Settings := preload("res://settings.gd")
const Audio := preload("res://audio.gd")
const RideWind := preload("res://ride_wind.gd")
const Emotes := preload("res://emotes.gd")

var sled: RigidBody3D
var player: CharacterBody3D
var emotes: Emotes          # 身ぶりと声の配り役（人より先に置く。人が登録する）
var hud: Label
var args := {}
var elapsed := 0.0
var log_t := 0.0
var _duty := 0
var _frames := 0
var _sim_sent := false
var _ft_max := 0.0
var _ft_sum := 0.0
var _ft_n := 0
var pip_label: Label


static func hill(x: float, z: float) -> float:
	return HILL_H * exp(-(x * x + z * z) / (2.0 * HILL_R * HILL_R))


## ロッジの足もとで 0、離れると 1
static func lodge_weight(x: float, z: float) -> float:
	var d := Vector2(x, z) - LODGE_POS
	var c := cos(LODGE_YAW)
	var s := sin(LODGE_YAW)
	var l := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	var q := Vector2(maxf(LODGE_PAD.position.x - l.x, l.x - LODGE_PAD.end.x),
			maxf(LODGE_PAD.position.y - l.y, l.y - LODGE_PAD.end.y))
	return smoothstep(0.0, LODGE_BLEND, Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length())


static func height(x: float, z: float) -> float:
	return lerpf(hill(LODGE_POS.x, LODGE_POS.y), hill(x, z), lodge_weight(x, z))


static var _drift: FastNoiseLite

## 見た目の雪面だけにある吹きだまりのうねり（当たり判定にはない）。地面の 1 m 刻みの点の値
static func drift(x: float, z: float) -> float:
	if _drift == null:
		_drift = FastNoiseLite.new()
		_drift.seed = 5
		_drift.frequency = 0.06
		_drift.fractal_octaves = 3
	return _drift.get_noise_2d(x, z) * 0.35 * lodge_weight(x, z)


## 見た目の雪面が当たり判定の地面からずれている量。1 m 刻みの点のあいだは直線でつなぐ（滑りあとを雪面に載せる用）
static func snow_lift(x: float, z: float) -> float:
	var x0 := floorf(x)
	var z0 := floorf(z)
	var fx := x - x0
	var fz := z - z0
	return lerpf(lerpf(drift(x0, z0), drift(x0 + 1, z0), fx), lerpf(drift(x0, z0 + 1), drift(x0 + 1, z0 + 1), fx), fz)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"

	_make_world()
	_make_ground()
	if not args.has("no-lodge"):
		_make_lodge()
		_furnish_lodge()

	sled = Sled.new()
	sled.position = START + Vector3(0, height(START.x, START.z - 3) + 0.6, -3)
	sled.snow_lift = snow_lift
	add_child(sled)
	if args.has("sled-yaw"):   # 確かめ用: 最初からソリを横や逆に向けておく
		sled.rotation.y = deg_to_rad(float(args["sled-yaw"]))

	emotes = Emotes.new()
	emotes.name = "Emotes"
	add_child(emotes)

	if not args.has("no-player"):
		player = Player.new()
		player.sled = sled
		player.position = START + Vector3(0, height(START.x, START.z) + 0.2, 0)
		add_child(player)
		player.look_at(sled.position, Vector3.UP)
		player.rotation.x = 0

	for i in int(args.get("bots", "1")):
		var b := Bot.new()
		b.sled = sled
		b.player = player
		b.side = 1 if i % 2 == 0 else -1
		b.position = START + Vector3(2.0 * b.side, height(START.x + 2.0 * b.side, START.z) + 0.2, 1)
		add_child(b)

	# 音（game/audio.gd）。--spawn=lodge でロッジの前から、--spawn=inside で食堂の中から始める（音の確かめ用）
	if not args.has("no-sound"):   # --no-sound は確かめ用: 音を入れない
		var audio := Audio.new()
		audio.name = "Audio"
		audio.setup(self, sled, player, get_children().filter(func(c): return c.get_script() == Bot), get_node_or_null("Lodge"))
		add_child(audio)
		_dress_speakers()
		_make_volume_buses()
		if args.has("buses"):   # 確かめ用: バスのつながりを出す
			for i in AudioServer.bus_count:
				print("bus %d %s -> %s" % [i, AudioServer.get_bus_name(i), AudioServer.get_bus_send(i)])
	if player and args.has("spawn") and has_node("Audio"):
		player.global_position = get_node("Audio").spawn_point(args["spawn"])

	if player == null:
		var cam := Camera3D.new()
		add_child(cam)
		cam.position = Vector3(-30, 26, 40)
		cam.look_at(Vector3(0, 8, 10))
		if args.has("cam"):
			var v: PackedFloat64Array = args["cam"].split_floats(",")
			cam.position = Vector3(v[0], v[1], v[2])
			cam.look_at(Vector3(v[3], v[4], v[5]))

	if player and not args.has("no-pip"):
		_make_pip()
	if not args.has("no-snow"):
		_make_snowfall(player if player else self)
	if player and not args.has("no-wind"):   # 滑るときの風（あなたの画面だけ）
		ride_wind = RideWind.new()
		ride_wind.setup(player, sled)
		add_child(ride_wind)

	# 設定画面（Esc）。保存してある値を起動時に当てる
	settings = Settings.new()
	add_child(settings)
	settings.changed.connect(_apply_setting)
	for key in settings.values:
		_apply_setting(key, settings.values[key])
	if args.has("settings"):   # 確かめ用: 設定画面を開いた状態で始める
		settings.set_open(true)
		if player: player.menu_open = true

	call_deferred("_split_pip_layers")   # 全部が置かれたあとで

	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)


## 右上のライブ映像: 自分の頭の上に載せた 360° カメラの映像。
## 6 方向を同時に撮り、シェーダで 1 枚の全天球（正距円筒）に合成する。V でリトルプラネット
const FACE_PX := 160
const PIP_PHONE := Vector2(216, 384)    # スマホ向けの縦長 (9:16)。超広角の魚眼で切り出す
const PIP_EQ := Vector2(420, 210)       # 全天球の窓 (2:1)
const PIP_PLANET := Vector2(260, 260)   # リトルプラネットの窓
const PIP_SIZES := [PIP_PHONE, PIP_EQ, PIP_PLANET]
# 面ごとの [前 A, 上 U, 右 R]。シェーダ側も同じ向きで読む
const FACES := [
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],   # 前
	[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],   # 後ろ
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],    # 右
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],  # 左
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],    # 上
	[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],  # 下
]
const PIP_SHADER := """
shader_type canvas_item;
uniform sampler2D f0; uniform sampler2D f1; uniform sampler2D f2;
uniform sampler2D f3; uniform sampler2D f4; uniform sampler2D f5;
uniform int mode = 0;   // 0: 縦長の超広角魚眼  1: 全天球  2: リトルプラネット
uniform float aspect = 0.5625;   // 窓の 幅/高さ
uniform float vfov = 2.97;       // 魚眼の縦の画角 (rad)。170°
uniform float tilt = 0.17;       // 魚眼の中心を下へ向ける角 (rad)
uniform int face_back = 1;       // 1: 後ろ向き（背中側を中央に）

vec4 sample_face(int i, vec2 uv) {
	if (i == 0) return texture(f0, uv);
	if (i == 1) return texture(f1, uv);
	if (i == 2) return texture(f2, uv);
	if (i == 3) return texture(f3, uv);
	if (i == 4) return texture(f4, uv);
	return texture(f5, uv);
}

// 向き d をどの面のどこで読むか（カメラの座標: 前 -z, 上 +y, 右 +x）
vec4 sample_dir(vec3 d) {
	vec3 a = abs(d);
	int i; vec3 A; vec3 U; vec3 R;
	if (a.x >= a.y && a.x >= a.z) {
		if (d.x > 0.0) { i = 2; A = vec3(1,0,0); U = vec3(0,1,0); R = vec3(0,0,1); }
		else { i = 3; A = vec3(-1,0,0); U = vec3(0,1,0); R = vec3(0,0,-1); }
	} else if (a.y >= a.z) {
		if (d.y > 0.0) { i = 4; A = vec3(0,1,0); U = vec3(0,0,1); R = vec3(1,0,0); }
		else { i = 5; A = vec3(0,-1,0); U = vec3(0,0,-1); R = vec3(1,0,0); }
	} else {
		if (d.z < 0.0) { i = 0; A = vec3(0,0,-1); U = vec3(0,1,0); R = vec3(1,0,0); }
		else { i = 1; A = vec3(0,0,1); U = vec3(0,1,0); R = vec3(-1,0,0); }
	}
	float t = dot(d, A);
	vec2 uv = vec2(0.5 + 0.5 * dot(d, R) / t, 0.5 - 0.5 * dot(d, U) / t);
	return sample_face(i, uv);
}

void fragment() {
	vec3 d;
	if (mode == 0) {
		// 等距離射影の魚眼: 中央はふつうに、端へ行くほどぎゅっと縮む
		vec2 p = (UV - 0.5) * vec2(aspect, 1.0) * 2.0;
		float r = length(p);
		float theta = r * vfov * 0.5;
		vec2 u = (r > 0.0001) ? p / r : vec2(0.0, -1.0);
		d = cos(theta) * vec3(0.0, 0.0, -1.0) + sin(theta) * (-u.y * vec3(0.0, 1.0, 0.0) + u.x * vec3(1.0, 0.0, 0.0));
		float cy = d.y * cos(tilt) + d.z * sin(tilt);
		float cz = -d.y * sin(tilt) + d.z * cos(tilt);
		d = vec3(d.x, cy, cz);
		if (face_back == 1) d = vec3(-d.x, d.y, -d.z);
		COLOR = sample_dir(d);
	} else if (mode == 1) {
		float lon = (UV.x - 0.5) * 6.2831853;
		float lat = (0.5 - UV.y) * 3.1415927;
		d = vec3(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat));
		COLOR = sample_dir(d);
	} else {
		vec2 p = (UV - 0.5) * 2.0;
		float r = length(p);
		if (r > 1.0) { COLOR = vec4(0.08, 0.1, 0.16, 1.0); }
		else {
			float theta = 2.0 * atan(r * 5.0);          // 真下 0 → 地平線 → 空
			float el = theta - 1.5707963;
			float phi = atan(p.x, -p.y);                 // 上が前
			d = vec3(sin(phi) * cos(el), sin(el), -cos(phi) * cos(el));
			COLOR = sample_dir(d);
		}
	}
}
"""

var pip_cams: Array[Camera3D] = []
var _pip_vps: Array[SubViewport] = []
var _pip_tick := 0
var pip_hidden := false
var settings: CanvasLayer
var ground_mesh: MeshInstance3D
var sun_light: DirectionalLight3D
var env: Environment
var snowfall: GPUParticles3D
var ride_wind: Node3D
var _pip_layer: CanvasLayer
var pip_frame: PanelContainer
var pip_mat: ShaderMaterial
var pip_mode := 0


## 右上の 360° 映像は場面を 6 回描くので、小物・連れの動物・スピーカーの柱・遠景は層 4 にして映さない
## （描画回数が 7 倍になるのを防ぐ）。地面・木・ロッジの建物・ソリ・人は映す。本体のカメラは層 4 も映す
const PIP_SKIP_WORDS := ["prop", "kitchen", "companion", "pet", "speaker", "mound", "furnish", "machine", "vending"]

func _split_pip_layers() -> void:
	for m in find_children("*", "VisualInstance3D", true, false):
		if m == ground_mesh or m is Camera3D or m is Light3D:
			continue
		var top: Node = m
		while top.get_parent() != null and top.get_parent() != self:
			top = top.get_parent()
		var names := [top.name.to_lower(), m.name.to_lower()]
		var p := m.get_parent()
		if p and p != self:
			names.append(p.name.to_lower())
		var skip := false
		for w in PIP_SKIP_WORDS:
			for nm in names:
				if nm.contains(w):
					skip = true
		if top.name == "Lodge" and not m.name.to_lower().contains("lodge_body") and not m.name.to_lower().contains("door"):
			skip = true   # ロッジは建物だけ映し、中の小物は映さない
		if skip:
			m.layers = 1 << 3


func _make_pip() -> void:
	var textures: Array[Texture2D] = []
	for f in FACES:
		var vp := SubViewport.new()
		vp.size = Vector2i(FACE_PX, FACE_PX)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS   # 毎フレーム小さく描く方が、コマの重さがそろう
		add_child(vp)
		_pip_vps.append(vp)
		var cam := Camera3D.new()
		cam.fov = 90.0
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.near = 0.08
		cam.cull_mask = (1 << 0) | (1 << 1)   # 地面・ソリ・人・あなたの体。手（層 3）と飾り（層 4）は映さない
		cam.far = 120.0
		vp.add_child(cam)
		cam.current = true
		pip_cams.append(cam)
		textures.append(vp.get_texture())
	_place_pip_cams()

	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_pip_layer = layer
	pip_frame = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.22)
	sb.border_color = Color(1, 1, 1, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(5)
	sb.shadow_size = 14
	sb.shadow_color = Color(0.1, 0.15, 0.3, 0.2)
	pip_frame.add_theme_stylebox_override("panel", sb)
	layer.add_child(pip_frame)
	var view := ColorRect.new()
	var sh := Shader.new()
	sh.code = PIP_SHADER
	pip_mat = ShaderMaterial.new()
	pip_mat.shader = sh
	for i in 6:
		pip_mat.set_shader_parameter("f%d" % i, textures[i])
	pip_mat.set_shader_parameter("mode", pip_mode)
	view.material = pip_mat
	pip_frame.add_child(view)
	pip_label = Label.new()
	pip_label.add_theme_font_size_override("font_size", 13)
	pip_label.add_theme_color_override("font_color", Color.WHITE)
	pip_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	pip_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(pip_label)
	var dot := ColorRect.new()
	dot.name = "Dot"
	dot.color = Color(0.95, 0.2, 0.15)
	layer.add_child(dot)
	_layout_pip()


func _layout_pip() -> void:
	var size: Vector2 = PIP_SIZES[pip_mode]
	if pip_mat:
		pip_mat.set_shader_parameter("aspect", size.x / size.y)
	pip_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pip_frame.offset_left = -(size.x + 16)
	pip_frame.offset_right = -16
	pip_frame.offset_top = 16
	pip_frame.offset_bottom = 16 + size.y
	pip_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pip_label.offset_left = pip_frame.offset_left + 16
	pip_label.offset_right = pip_frame.offset_right - 8
	pip_label.offset_top = 28
	pip_label.offset_bottom = 48
	var dot: ColorRect = pip_label.get_parent().get_node("Dot")
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = pip_frame.offset_left + 18
	dot.offset_right = dot.offset_left + 8
	dot.offset_top = 34
	dot.offset_bottom = 42


## 6 台のカメラを、頭のてっぺんに、体の向きに合わせて置く（水平は固定）
func _place_pip_cams() -> void:
	var head: Vector3 = player.global_position + Vector3.UP * 2.35   # 帽子の先の少し上
	var yaw := Basis(Vector3.UP, player.rotation.y)
	for i in FACES.size():
		var f: Array = FACES[i]
		var A: Vector3 = f[0]
		var U: Vector3 = f[1]
		var R: Vector3 = f[2]
		pip_cams[i].global_transform = Transform3D(yaw * Basis(R, U, -A), head)


var _cloud_t := 0.0

func _process(_dt: float) -> void:
	_cloud_t += _dt
	if _cloud_t >= 0.5:   # 雲は 0.5 秒ごとに焼き直す
		_cloud_t = 0.0
		Look.tick_clouds(elapsed)
	_ft_max = maxf(_ft_max, _dt)
	_ft_sum += _dt
	_ft_n += 1
	if pip_cams.is_empty():
		return
	_place_pip_cams()
	for vp in _pip_vps:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if pip_hidden else SubViewport.UPDATE_ALWAYS
	var t := int(elapsed)
	pip_label.text = "    360 LIVE  %02d:%02d%s" % [t / 60, t % 60, "  後ろ" if pip_mode == 0 else ""]


func _make_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Look.sky(self)
	if args.has("plain-sky"):   # 確かめ用: 雲の計算をしない空
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = Color(0.50, 0.66, 0.88)
		psm.sky_horizon_color = Color(0.87, 0.91, 0.95)
		psm.ground_horizon_color = Color(0.87, 0.91, 0.95)
		var ps := Sky.new()
		ps.sky_material = psm
		env.sky = ps
	# 光（2026-10-28 代表「のっぺりして安っぽい。素材感が掴める光に。マイクラの影 MOD っぽく」）:
	# 強い暖色の陽と、空の青を映した暗めの影で、日なたと日かげの差をはっきりさせる。
	# 白い雪が飛ばないよう白の上限を高くし（ACES）、明るい所は光がにじみ、遠くは青く霞む。
	# 環境光の強さは daycycle.gd が時刻で決め直す
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.7
	env.tonemap_white = 6.0
	env.ssao_enabled = not args.has("no-ssao")          # くぼみに影が落ちる
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.5
	env.ssao_power = 1.6
	env.ssao_detail = 0.8
	env.ssao_light_affect = 0.1                         # 日なたは陽の色のまま、かげの側で効かせる
	env.ssil_enabled = not args.has("no-ssao")          # 色の照り返し（フェルトの色が近くの雪に移る）
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.2
	env.glow_enabled = true                              # 明るい所が光ってにじむ
	env.glow_intensity = 0.35
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true                               # 遠くは空の色に青く霞む。陽の側は明るく
	env.fog_light_color = Color(0.74, 0.82, 0.95)
	env.fog_density = 0.0025
	env.fog_aerial_perspective = 0.4
	env.fog_sun_scatter = 0.08
	env.fog_sky_affect = 0.15
	env.volumetric_fog_enabled = args.has("vfog")   # 空気の厚みと光の筋（重いので確かめ用）
	env.volumetric_fog_density = 0.0015
	env.volumetric_fog_albedo = Color(0.92, 0.95, 1.0)
	env.volumetric_fog_anisotropy = 0.7
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 太陽: 低めの暖かい光。影は濃く、長く、遠くまで落とす。高さ・色・強さは daycycle.gd が時刻で決める
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -40, 0)
	sun.light_color = Color(1.0, 0.86, 0.70)
	sun.light_energy = 3.2
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110
	sun.directional_shadow_blend_splits = true
	sun_light = sun
	add_child(sun)

	# 遠景: 地平線にフェルトの山なみ。地面の端（±128 m）を隠すよう、すき間なく輪にする。
	# スピーカーの柱（audio.gd の POST_R = 95 m）より外
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var far_mat := Look.felt(Color(0.72, 0.79, 0.90), 0.3)
	for k in 20:
		var a := k * TAU / 20.0 + rng.randf_range(-0.06, 0.06)
		var r := rng.randf_range(124, 140)
		var m := MeshInstance3D.new()
		m.mesh = SphereMesh.new()
		m.material_override = far_mat
		m.position = Vector3(cos(a) * r, -3.0, sin(a) * r)
		m.scale = Vector3(rng.randf_range(40, 70), rng.randf_range(14, 26), rng.randf_range(30, 50))
		m.rotation.y = rng.randf() * TAU
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.name = "FarMound%d" % k
		add_child(m)


## ロッジ（game/lodge/lodge.tscn）。main.tscn に置いてあり、エディタでも見える。
## 位置と向きはここの定数（地面をならす範囲と同じ）で決め直す
func _make_lodge() -> void:
	var lodge: Node3D = get_node_or_null("Lodge")
	if lodge == null:
		lodge = (load("res://lodge/lodge.tscn") as PackedScene).instantiate()
		add_child(lodge)
	lodge.position = Vector3(LODGE_POS.x, hill(LODGE_POS.x, LODGE_POS.y), LODGE_POS.y)
	lodge.rotation = Vector3(0, LODGE_YAW, 0)


## ロッジの機械の置き場の目印（slot_*。lodge/ の glb にある）に、props/ の機械を置く。
## どれも正面を南（ロッジの食堂の側、目印の +Z）へ向ける。目印のない古い glb なら何もしない
func _furnish_lodge() -> void:
	var lodge: Node3D = get_node_or_null("Lodge")
	if lodge == null:
		return
	var put := func(slot_name: String, path: String, offset: Vector3, yaw := PI) -> void:
		var slot := lodge.find_child(slot_name, true, false) as Node3D
		if slot == null:
			return
		var n := Props.make(path)
		n.position = offset
		n.rotation.y = yaw
		slot.add_child(n)
	# 機械は 2 倍（ミシンは貸出に収まるよう 1.5 倍）の大きさで書き出してある
	put.call("slot_vending_1", "res://props/misc/vending_red.glb", Vector3.ZERO)
	put.call("slot_vending_2", "res://props/misc/vending_blue.glb", Vector3.ZERO)
	put.call("slot_vending_3", "res://props/misc/vending_red.glb", Vector3.ZERO)
	put.call("slot_craft_rental", "res://props/craft_machine.glb", Vector3.ZERO)
	# 厨房: 巨大なアイロン台・プレス機・乾燥機と、卓上の道具（props/build_scenes.py の kitchen）
	var kitchen := lodge.find_child("slot_food_kitchen", true, false) as Node3D
	if kitchen:
		var set_node := (load("res://props/sets/kitchen.tscn") as PackedScene).instantiate()
		kitchen.add_child(set_node)
		Props.cook_cycle(set_node)   # 調理の仕組みができるまで: 装置が順に調理して煙を出す


## 舞う雪: 羊毛のふわふわが、あなたのまわりでゆっくり落ちる
func _make_snowfall(follow: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.amount = 500
	p.lifetime = 14.0
	p.preprocess = 10.0
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 50, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(32, 2, 32)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, -0.35, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	p.process_material = pm
	var flake := SphereMesh.new()
	flake.radius = 0.045
	flake.height = 0.09
	flake.radial_segments = 6
	flake.rings = 3
	p.draw_pass_1 = flake
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1, 1, 1, 0.9)
	fm.roughness = 1.0
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = fm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0, 22, 0)
	follow.add_child(p)
	snowfall = p
	p.top_level = false


func _make_ground() -> void:
	var n := SIZE + 1
	var half := SIZE / 2.0
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = height(i - half, j - half)

	# 当たり判定
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	body.physics_material_override = pm
	add_child(body)

	# 見た目: 1 m 刻み、頂点を共有してなめらかな法線に。わずかなうねりで雪の吹きだまりを出す
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 1
	var cols := SIZE / step + 1
	for j in cols:
		for i in cols:
			var x := i * step - half
			var z := j * step - half
			var y := height(x, z) + drift(x, z)
			st.set_uv(Vector2(x, z) * 0.5)
			st.add_vertex(Vector3(x, y, z))
	for j in cols - 1:
		for i in cols - 1:
			var a := j * cols + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + cols)
			st.add_index(a + cols)
			st.add_index(a + 1)
			st.add_index(a + cols + 1)
	st.generate_normals()
	st.generate_tangents()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = Look.snow()
	ground_mesh = mesh
	add_child(mesh)

	# 木（ソリの通り道は空ける）。フェルトの円錐を 2 段重ねたミニチュアの木（props/build_tree.py の glb）
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	const TREES := ["res://props/tree_tall.glb", "res://props/tree_zigzag.glb", "res://props/tree_round.glb",
		"res://props/tree_little.glb"]
	for k in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(32, 90)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.z > 20 and abs(p.x) < 14:
			continue
		if lodge_weight(p.x, p.z) < 1.0:   # ロッジに重ねない
			continue
		var h := rng.randf_range(4, 8)
		var tree := Props.make(TREES[k % TREES.size()])
		tree.scale = Vector3.ONE * h / 6.0
		tree.position = p + Vector3(0, height(p.x, p.z) - 0.05, 0)
		tree.rotation.y = rng.randf() * TAU
		add_child(tree)
	_make_slope_props()


## 斜面の小物（props/build_slope.py・build_snow.py の glb）。当たり判定はまだない（見た目だけ）
func _make_slope_props() -> void:
	# コースの旗: 登り道の両脇に、赤と藍を交互に
	var i := 0
	for z in [34.0, 27.0, 20.0, 13.0]:
		for x in [-9.0, 9.0]:
			_put_prop("res://props/flag_%s.glb" % ("red" if i % 2 == 0 else "navy"), x, z, 0.4 if x < 0 else PI - 0.4)
			i += 1
	# 案内板: スタートにロッジへの矢印、ロッジの前に丘への矢印（文字なし）
	_put_prop("res://props/sign_lodge.glb", 5.0, 41.0, PI)
	var to_lodge := Vector2(-13, 14)
	_put_prop("res://props/sign_slope.glb", -14.0, 62.0, atan2(-to_lodge.x, -to_lodge.y))
	# 毛糸の安全ネット: 登り道の右の外れに 4 区間と、終わりの杭
	for k in 5:
		var net := _put_prop("res://props/net_span.glb", 13.0, 30.0 - 2.5 * k, PI / 2)
		if k == 4:
			for n in net.find_children("*", "MeshInstance3D", true, false):
				if "_yarn" in n.name or "_knots" in n.name:
					n.visible = false
	# 岩と雪のかたまり: 丘のまわりに散らす（登り道とロッジは空ける）
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	const LUMPS := ["res://props/rock_a.glb", "res://props/rock_b.glb", "res://props/rock_c.glb",
		"res://props/snow_pile_a.glb", "res://props/snow_pile_b.glb", "res://props/snow_drift.glb"]
	for k in 24:
		var a := rng.randf() * TAU
		var r := rng.randf_range(22, 85)
		var x := cos(a) * r
		var z := sin(a) * r
		if z > 8 and abs(x) < 16:
			continue
		if lodge_weight(x, z) < 1.0:
			continue
		_put_prop(LUMPS[k % LUMPS.size()], x, z, rng.randf() * TAU)


func _put_prop(path: String, x: float, z: float, yaw: float) -> Node3D:
	var n := Props.make(path)
	n.position = Vector3(x, height(x, z) - 0.05, z)
	n.rotation.y = yaw
	add_child(n)
	return n


## 音（audio.gd）が立てた柱の仮の見た目を隠し、フェルトのスピーカーの柱に着せ替える。ラッパは丘を向く
func _dress_speakers() -> void:
	for post in find_children("SpeakerPost*", "Node3D", true, false):
		for n in post.find_children("*", "MeshInstance3D", true, false):
			n.visible = false
		var look := Props.make("res://props/speaker_pole.glb")
		look.scale = Vector3.ONE * Audio.POST_H / 5.0
		var d := -Vector2(post.position.x, post.position.z)
		look.rotation.y = atan2(-d.x, -d.y)
		post.add_child(look)


func _physics_process(dt: float) -> void:
	elapsed += dt
	var s := sled.global_position
	var top := Vector2(s.x, s.z).length()
	var lines := [
		"押している人: %d　ソリの高さ: %.1f m（頂上 %.0f m）　速さ: %.1f m/s　%d fps" % [sled.pushers, s.y, HILL_H, sled.linear_velocity.length(), Engine.get_frames_per_second()],
	]
	if player:
		if player.prompt != "":
			lines.append(player.prompt)
		else:
			lines.append("WASD 歩く　Shift 走る　Space ジャンプ　F ソリをつかむ（前では紐）　E 乗る　R ソリをふもとへ")
			lines.append("マウス 見回す　ホイール／ピンチ 視野角　C 一人称／三人称　V 360映像の見せ方　P 360映像を消す　Esc 設定")
			lines.append("Tab 手の形の輪　1 2 3 声　B 息を吐く　左Ctrl しゃがむ（雪面を見て F で雪玉）　左クリック ためて投げる／両手のひらで拍手　Q 手を振る　右クリック 指さす")
	hud.text = "\n".join(lines)

	# --sim: あなたが W を押し続けたことにする（吸い付き→押すの確かめ用）
	# --sim=rope: 先にソリの前に回って紐を持ち、それから W で歩く（引く確かめ用）
	# --sim=side: 先にソリの横に立ち、それから W で押す（横から押す確かめ用）
	if args.has("sim") and player and elapsed > 1.0 and not _sim_sent:
		_sim_sent = true
		var fwd: Vector3 = -sled.global_basis.z
		if args["sim"] == "rope":
			player.global_position = sled.to_global(Vector3(0, 0, -2.6)) + Vector3.UP * 0.2
			player.rotation.y = atan2(-fwd.x, -fwd.z)
			player.grab_rope()
		elif args["sim"] == "side":
			player.global_position = sled.to_global(Vector3(2.0, 0, 0)) + Vector3.UP * 0.2
			var inward: Vector3 = -sled.global_basis.x
			player.rotation.y = atan2(-inward.x, -inward.z)
		if args["sim"] == "left":
			player.global_position = sled.to_global(Vector3(-2.0, 0, 0)) + Vector3.UP * 0.2
			var inward: Vector3 = sled.global_basis.x
			player.rotation.y = atan2(-inward.x, -inward.z)
			player.grab()
			var eva := InputEventKey.new()
			eva.physical_keycode = KEY_A
			eva.pressed = true
			Input.parse_input_event(eva)
			return
		if args["sim"] == "turn":
			player.global_position = sled.to_global(Vector3(0, 0, 2.4)) + Vector3.UP * 0.2
			player.rotation.y = atan2(-fwd.x, -fwd.z)
			player.grab()
			var evd := InputEventKey.new()
			evd.physical_keycode = KEY_D
			evd.pressed = true
			Input.parse_input_event(evd)
			return
		if args.has("third"):
			player.third = true
			player.cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4)
		if args["sim"] == "1":
			player.grab()
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
	if args.has("sim") and player and _sim_sent and player.mode == player.Mode.GRIP and args["sim"] == "1":
		var fwd: Vector3 = -sled.global_basis.z
		player.rotation.y = atan2(-fwd.x, -fwd.z)
	if args.has("log"):
		_duty += 1 if sled.pushers > 0 else 0
		_frames += 1
		log_t += dt
		if log_t >= float(args.get("log-every", "1")):
			log_t = 0.0
			var bots := get_children().filter(func(c): return c.get_script() == Bot)
			var bd: float = bots[0].global_position.distance_to(s) if bots.size() > 0 else 0.0
			var me := ("　あなた=%s 向き=%.0f°" % [["歩く", "つかむ", "乗る", "紐"][player.mode], rad_to_deg(player.rotation.y)]) if player else ""
			me += "　ソリ向き=%.0f° 速さ=%.2f 保持=%s" % [rad_to_deg(sled.rotation.y), sled.linear_velocity.length(), sled.hold_debug]
			me += "　つかんでいる人=%d 回転=%.2f 横滑り=%.2f" % [sled.holders.size(), sled.angular_velocity.y, sled.linear_velocity.dot(sled.global_basis.x)]
			if bots.size() > 0:
				me += "　仲間=%s" % bots[0].debug
			if has_node("Audio"):
				me += "　" + get_node("Audio").debug
			print("fps=%d コマ 平均%.1fms 最長%.1fms " % [Engine.get_frames_per_second(), 1000.0 * _ft_sum / maxi(_ft_n, 1), 1000.0 * _ft_max], "t=%.0f 高さ=%.2f 頂上まで=%.1f 押していた割合=%.0f%% 乗る人=%d 仲間との距離=%.1f%s" % [elapsed, s.y, top, 100.0 * _duty / _frames, sled.riders.size(), bd, me])
			_duty = 0
			_frames = 0
			_ft_max = 0.0
			_ft_sum = 0.0
			_ft_n = 0

	if args.has("shot") and elapsed > float(args.get("shot-at", "4")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		print("保存: ", args["shot"])
		get_tree().quit()
	if args.has("quit-at") and elapsed > float(args["quit-at"]):
		get_tree().quit()


## 音量の区分のバス。音楽は Speaker → Music → Outdoor、効果音は Inside・Self → SFX → Master、
## ボイスは Voice → Master。audio.gd の環境のバス（Outdoor・Inside）はそのまま生かす。
## 送り先は自分より前のバスにしか指定できないので、挿す位置に注意する
func _make_volume_buses() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	AudioServer.add_bus(1)
	AudioServer.set_bus_name(1, "SFX")
	AudioServer.set_bus_send(1, "Master")
	AudioServer.add_bus(2)
	AudioServer.set_bus_name(2, "Voice")
	AudioServer.set_bus_send(2, "Master")
	var o := AudioServer.get_bus_index("Outdoor")
	if o >= 0:
		AudioServer.add_bus(o + 1)
		AudioServer.set_bus_name(o + 1, "Music")
		AudioServer.set_bus_send(o + 1, "Outdoor")
		var sp := AudioServer.get_bus_index("Speaker")
		if sp >= 0:
			AudioServer.set_bus_send(sp, "Music")
	else:
		AudioServer.add_bus(3)
		AudioServer.set_bus_name(3, "Music")
		AudioServer.set_bus_send(3, "Master")
	for b in ["Inside", "Self"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_send(i, "SFX")


func _set_volume(buses: Array, v: float) -> void:
	for b in buses:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			continue
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func _apply_setting(key: String, v) -> void:
	match key:
		"vol_music":
			_set_volume(["Music"], v)
		"vol_sfx":
			_set_volume(["SFX", "Wind"], v)   # 風は Outdoor の処理を通したいので、バスの音量で合わせる
		"vol_voice":
			_set_volume(["Voice"], v)
		"bob":
			if player: player.bob_enabled = v
			if ride_wind: ride_wind.calm = not v   # 揺れを切った人には、風も控えめに
		"wind":
			if ride_wind: ride_wind.strength = v
		"fov_kick":
			if player: player.fov_kick_enabled = v
		"pip":
			pip_hidden = not v
			if _pip_layer: _pip_layer.visible = v
		"snow":
			if snowfall: snowfall.emitting = v; snowfall.visible = v
		"third":
			if player: player.set_third(v)
		"fov":
			if player: player.base_fov = v
		"sens":
			if player: player.mouse_sens = v
		"scale":
			get_viewport().scaling_3d_scale = v
		"ssao":
			if env:
				env.ssao_enabled = v
				env.ssil_enabled = v   # 照り返しも同じく重いので一緒に
		"shadows":
			if sun_light: sun_light.shadow_enabled = v


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE and settings:
			settings.set_open(not settings.is_open)
			if player: player.menu_open = settings.is_open
			return
		if e.physical_keycode == KEY_R:
			sled.reset_to(START + Vector3(0, height(START.x, START.z - 3) + 0.6, -3))
		elif e.physical_keycode == KEY_P and _pip_layer:
			# 右上の 360° 映像を消す／出す（消している間は描画もしない）
			pip_hidden = not pip_hidden
			_pip_layer.visible = not pip_hidden
			settings.sync("pip", not pip_hidden)
		elif e.physical_keycode == KEY_V and pip_mat:
			pip_mode = (pip_mode + 1) % 3
			pip_mat.set_shader_parameter("mode", pip_mode)
			_layout_pip()
