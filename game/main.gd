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

	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)


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
		lines.append(player.prompt if player.prompt != "" else "WASD 歩く　Shift 走る　マウス 見回す　ホイール／ピンチ 視野角　Space ジャンプ　ソリのそばで F つかむ（前では紐を持つ）　E 乗る　R ソリをふもとへ　Esc マウスを離す")
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
		if args["sim"] == "1":
			player.grab()
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
	if args.has("log"):
		_duty += 1 if sled.pushers > 0 else 0
		_frames += 1
		log_t += dt
		if log_t >= 1.0:
			log_t = 0.0
			var bots := get_children().filter(func(c): return c.get_script() == Bot)
			var bd: float = bots[0].global_position.distance_to(s) if bots.size() > 0 else 0.0
			var me := ("　あなた=%s 向き=%.0f° ソリ向き=%.0f°" % [["歩く", "つかむ", "乗る", "紐"][player.mode], rad_to_deg(player.rotation.y), rad_to_deg(sled.rotation.y)]) if player else ""
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
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_R:
		sled.reset_to(START + Vector3(0, height(START.x, START.z - 3) + 0.6, -3))
