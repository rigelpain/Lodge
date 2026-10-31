extends SceneTree
## ご飯係の雪だるまと冷蔵庫の glb を、ゲームと同じ素材の差し替え（props.gd）で撮る。人形 3 体と並べた絵も。
##   Godot --path game -s res://tools/snowman_shots.gd -- --out=/path/to.png [--view=front|quarter|side|dolls|bow]
## bow: 雪だるまの節点を回して、おじぎ（chest）・首かしげ（head）・ベルを振る（arm_l）の見本（動かせるかの確かめ）

const Look := preload("res://look.gd")
const Props := preload("res://props.gd")
const Doll := preload("res://doll.gd")

var args := {}
var frame := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Look.sky(world)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	world.add_child(sun)
	var lamp := OmniLight3D.new()   # ロッジの中の電球色の灯り
	lamp.position = Vector3(1.5, 2.6, -2.0)
	lamp.light_color = Color(1.0, 0.76, 0.52)
	lamp.light_energy = 0.9
	lamp.omni_range = 8.0
	world.add_child(lamp)
	# 床（木の色）と奥の壁
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.62, 0.42, 0.28)
	floor_mat.roughness = 0.8
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	fl.mesh = pm
	fl.material_override = floor_mat
	world.add_child(fl)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 5, 0.1)
	wall.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.86, 0.78, 0.66)
	wall.material_override = wm
	wall.position = Vector3(0, 2.5, 0.65)
	world.add_child(wall)

	# 冷蔵庫（前は -Z）と、中の印 snowman_spot に雪だるま
	var fridge: Node3D = Props.make("res://props/snowman_fridge.glb")
	world.add_child(fridge)
	var spot: Node3D = fridge.find_child("snowman_spot", true, false)
	var snowman: Node3D = Props.make("res://props/snowman.glb")
	world.add_child(snowman)
	var at := spot.transform   # 木をたどって冷蔵庫の座標に（まだ木に入る前なので global は使わない）
	var n := spot.get_parent()
	while n != world:
		at = (n as Node3D).transform * at
		n = n.get_parent()
	snowman.position = at.origin
	var view: String = args.get("view", "front")
	if view == "bow":
		var chest: Node3D = snowman.find_child("chest", true, false)
		var head: Node3D = snowman.find_child("head", true, false)
		var arm_l: Node3D = snowman.find_child("arm_l", true, false)
		chest.rotation.x = -0.35
		head.rotation.z = 0.2
		arm_l.rotation.z = -0.6
		snowman.position = Vector3(1.9, 0, -1.0)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40
	match view:
		"quarter":
			cam.look_at_from_position(Vector3(2.7, 1.65, -3.7), Vector3(-0.1, 0.95, -0.1))
		"side":
			cam.look_at_from_position(Vector3(4.4, 1.15, -0.9), Vector3(0.0, 0.95, -0.1))
		"bow":
			cam.look_at_from_position(Vector3(3.9, 1.3, -3.6), Vector3(1.6, 0.75, -0.8))
		"dolls":
			cam.look_at_from_position(Vector3(1.9, 1.4, -6.0), Vector3(1.9, 0.9, 0.0))
			var kinds := ["kasa", "origami", "news"]
			for k in 3:
				var host := Node3D.new()
				host.position = Vector3(1.3 + k * 0.85, 0, -0.6)
				world.add_child(host)
				var d := Doll.new()
				d.kind = kinds[k]
				host.add_child(d)
				var to_cam := cam.position - host.position
				to_cam.y = 0
				d.facing = to_cam.rotated(Vector3.UP, -0.35)
				d.gaze = snowman.position + Vector3(0, 1.1, 0)
		_:
			cam.look_at_from_position(Vector3(0.0, 1.3, -4.8), Vector3(0.0, 1.0, 0.0))
	cam.current = true


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 40:
		root.get_texture().get_image().save_png(args.get("out", "/tmp/snowman.png"))
		print("保存: ", args.get("out", ""))
		return true
	return false
