extends SceneTree
## 服の色違いの人形を横に並べて撮る（outfit.gd の確かめ・代表に見せる絵）。
##   Godot --path game -s res://tools/outfit_shots.gd -- --out=/path/to.png --set=kasa:-,kasa:D2553A,kasa:D8A43E/EFE6D2
## --set は「人形:布ごとの色」をカンマで並べる。布ごとの色は / で区切り、- はもとの色のまま（outfit.gd の CLOTH の順）
## --rows=2 で何段に並べるか。--close で近くから

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

var args := {}
var t := 0.0
var cam: Camera3D


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
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.4
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -20, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	ground.material_override = Look.snow()
	world.add_child(ground)

	var items: Array = String(args.get("set", "kasa:-")).split(",")
	var rows := int(args.get("rows", "1"))
	var per := ceili(float(items.size()) / rows)
	var gap := float(args.get("gap", "1.0"))
	var depth := float(args.get("depth", "1.7"))
	for i in items.size():
		var kv: PackedStringArray = String(items[i]).split(":")
		var r := i / per
		var c := i % per
		var host := Node3D.new()
		host.position = Vector3((c - (per - 1) * 0.5) * gap, 0, (r - (rows - 1) * 0.5) * depth)
		world.add_child(host)
		var d := Doll.new()
		d.kind = kv[0]
		var cols := []
		if kv.size() > 1:
			for h in kv[1].split("/"):
				cols.append(null if h == "-" else Color(h))
		d.outfit = cols
		host.add_child(d)
		d.facing = Vector3(0.25, 0, 1)
		d.gaze = host.position + Vector3(0, 1.2, 6)
	cam = Camera3D.new()
	world.add_child(cam)
	# 横の並びがちょうど収まる距離（縦の画角と画面の縦横比から、横の画角を出す）
	cam.fov = 30
	var vs := root.get_visible_rect().size
	var half_w := (per - 1) * gap * 0.5 + 0.7
	var dist := half_w / (tan(deg_to_rad(cam.fov * 0.5)) * vs.x / vs.y) + (rows - 1) * depth * 0.5
	dist = float(args.get("dist", str(dist)))
	cam.look_at_from_position(Vector3(0, float(args.get("cam-y", str(0.7 + rows * 0.5))), dist), Vector3(0, 0.55 - (rows - 1) * 0.2, 0))
	cam.current = true


func _process(dt: float) -> bool:
	t += dt
	for p in root.find_children("*", "CPUParticles3D", true, false):   # 白い息は色を見るじゃまなので出さない
		(p as CPUParticles3D).visible = false
	if t > float(args.get("at", "3.0")):
		var img := root.get_texture().get_image()
		img.save_png(args.get("out", "/tmp/outfit.png"))
		print("保存: ", args.get("out", ""))
		quit()
	return false
