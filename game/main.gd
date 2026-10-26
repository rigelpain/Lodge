extends Node3D
## 原型の場面: こんもりした丘、ソリ、あなた（手だけ見える一人称）、押すのを手伝う仲間。
## 確かめ用の起動引数（-- のあとに付ける）:
##   --bots=N      仲間の数（既定 1）
##   --no-player   あなたを出さず、仲間だけで押す（速さを比べる用）
##   --shot=PATH   数秒後に画面を PNG で保存して終わる
##   --log         ソリの高さを1秒ごとに出す

const HILL_H := 18.0      # 丘の高さ (m)
const HILL_R := 25.0      # 丘の広がり (m)
const SIZE := 256         # 地面の一辺 (m)。Jolt の地形は 2 のべき乗 + 1 点で作る
const START := Vector3(0, 0, 38)

const Sled := preload("res://sled.gd")
const Player := preload("res://player.gd")
const Bot := preload("res://bot.gd")

var sled: RigidBody3D
var player: CharacterBody3D
var hud: Label
var args := {}
var elapsed := 0.0
var log_t := 0.0
var _duty := 0
var _frames := 0
var _sim_sent := false
var pip_label: Label


static func height(x: float, z: float) -> float:
	return HILL_H * exp(-(x * x + z * z) / (2.0 * HILL_R * HILL_R))


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"

	_make_world()
	_make_ground()

	sled = Sled.new()
	sled.position = START + Vector3(0, height(START.x, START.z - 3) + 0.6, -3)
	add_child(sled)
	if args.has("sled-yaw"):   # 確かめ用: 最初からソリを横や逆に向けておく
		sled.rotation.y = deg_to_rad(float(args["sled-yaw"]))

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

	if player == null:
		var cam := Camera3D.new()
		add_child(cam)
		cam.position = Vector3(-30, 26, 40)
		cam.look_at(Vector3(0, 8, 10))

	if player:
		_make_pip()

	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)


## 右上のライブ映像: 自分の頭の上に載せた 360° カメラの映像。
## 6 方向を同時に撮り、シェーダで 1 枚の全天球（正距円筒）に合成する。V でリトルプラネット
const FACE_PX := 320
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
var pip_frame: PanelContainer
var pip_mat: ShaderMaterial
var pip_mode := 0


func _make_pip() -> void:
	var textures: Array[Texture2D] = []
	for f in FACES:
		var vp := SubViewport.new()
		vp.size = Vector2i(FACE_PX, FACE_PX)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 90.0
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.near = 0.08
		cam.cull_mask = (1 << 0) | (1 << 1)   # 世界と、あなたの体。手は映さない
		vp.add_child(cam)
		cam.current = true
		pip_cams.append(cam)
		textures.append(vp.get_texture())
	_place_pip_cams()

	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
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


func _process(_dt: float) -> void:
	if pip_cams.is_empty():
		return
	_place_pip_cams()
	var t := int(elapsed)
	pip_label.text = "    360 LIVE  %02d:%02d%s" % [t / 60, t % 60, "  後ろ" if pip_mode == 0 else ""]


func _make_world() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.72, 0.86)
	sky_mat.sky_horizon_color = Color(0.86, 0.9, 0.93)
	sky_mat.ground_horizon_color = Color(0.86, 0.9, 0.93)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.9, 0.93)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80
	add_child(sun)


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

	# 見た目（2m 刻み）
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2
	for j in range(0, SIZE, step):
		for i in range(0, SIZE, step):
			var x0 := i - half
			var z0 := j - half
			var q := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0, 0, z0 + step), Vector3(x0 + step, 0, z0 + step)]
			for k in 4:
				q[k].y = height(q[k].x, q[k].z)
			for v in [q[0], q[1], q[2], q[2], q[1], q[3]]:
				st.add_vertex(v)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.96, 0.97)
	mat.roughness = 1.0
	mesh.material_override = mat
	add_child(mesh)

	# 木（ソリの通り道は空ける）
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tree_mat := StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.31, 0.54, 0.35)
	for k in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(32, 90)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.z > 20 and abs(p.x) < 14:
			continue
		var h := rng.randf_range(4, 8)
		var cone := CylinderMesh.new()
		cone.top_radius = 0
		cone.bottom_radius = h * 0.32
		cone.height = h
		cone.radial_segments = 7
		var t := MeshInstance3D.new()
		t.mesh = cone
		t.material_override = tree_mat
		t.position = p + Vector3(0, height(p.x, p.z) + h / 2.0, 0)
		add_child(t)


func _physics_process(dt: float) -> void:
	elapsed += dt
	var s := sled.global_position
	var top := Vector2(s.x, s.z).length()
	var lines := [
		"押している人: %d　ソリの高さ: %.1f m（頂上 %.0f m）　速さ: %.1f m/s" % [sled.pushers, s.y, HILL_H, sled.linear_velocity.length()],
	]
	if player:
		lines.append(player.prompt if player.prompt != "" else "WASD 歩く　Shift 走る　マウス 見回す　ホイール／ピンチ 視野角　V 360映像の見せ方　C 一人称／三人称　Space ジャンプ　ソリのそばで F つかむ（前では紐を持つ）　E 乗る　R ソリをふもとへ　Esc マウスを離す")
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
			player.cam.cull_mask = (1 << 0) | (1 << 1)
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
		if log_t >= 1.0:
			log_t = 0.0
			var bots := get_children().filter(func(c): return c.get_script() == Bot)
			var bd: float = bots[0].global_position.distance_to(s) if bots.size() > 0 else 0.0
			var me := ("　あなた=%s 向き=%.0f°" % [["歩く", "つかむ", "乗る", "紐"][player.mode], rad_to_deg(player.rotation.y)]) if player else ""
			me += "　ソリ向き=%.0f° 速さ=%.2f 保持=%s" % [rad_to_deg(sled.rotation.y), sled.linear_velocity.length(), sled.hold_debug]
			me += "　つかんでいる人=%d 回転=%.2f 横滑り=%.2f" % [sled.holders.size(), sled.angular_velocity.y, sled.linear_velocity.dot(sled.global_basis.x)]
			if bots.size() > 0:
				me += "　仲間=%s" % bots[0].debug
			print("t=%.0f 高さ=%.2f 頂上まで=%.1f 押していた割合=%.0f%% 乗る人=%d 仲間との距離=%.1f%s" % [elapsed, s.y, top, 100.0 * _duty / _frames, sled.riders.size(), bd, me])
			_duty = 0
			_frames = 0

	if args.has("shot") and elapsed > float(args.get("shot-at", "4")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		print("保存: ", args["shot"])
		get_tree().quit()
	if args.has("quit-at") and elapsed > float(args["quit-at"]):
		get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_R:
			sled.reset_to(START + Vector3(0, height(START.x, START.z - 3) + 0.6, -3))
		elif e.physical_keycode == KEY_V and pip_mat:
			pip_mode = (pip_mode + 1) % 3
			pip_mat.set_shader_parameter("mode", pip_mode)
			_layout_pip()
