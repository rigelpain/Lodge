extends SceneTree
## ソリの glb（米袋・小・中・大）を、ゲームと同じ素材の差し替え（props.gd）で並べて撮る。紐の結び先の印に赤い玉。
##   Godot --path game -s res://tools/sled_models_shot.gd -- --out=/path/to.png [--view=line|front]

const Look := preload("res://look.gd")
const Props := preload("res://props.gd")

var args := {}
var frame := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Look.sky(world)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -40, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = Look.snow()
	world.add_child(ground)
	var xs := {"sack": -3.4, "small": -2.3, "mid": 0.0, "large": 3.1}
	for k in xs:
		var p: Node3D = Props.make("res://props/sled_%s.glb" % k)
		p.position.x = xs[k]
		world.add_child(p)
		for tie in p.find_children("rope_tie_*", "Node3D", true, false):
			var dot := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.03
			sm.height = 0.06
			dot.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1, 0, 0)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dot.material_override = m
			tie.add_child(dot)
	var cam := Camera3D.new()
	world.add_child(cam)
	if args.get("view", "line") == "front":
		cam.look_at_from_position(Vector3(-1.0, 2.6, -7.0), Vector3(0.0, 0.3, 0.0))
	else:
		cam.look_at_from_position(Vector3(-4.6, 3.6, -6.2), Vector3(0.2, 0.2, 0.3))
	cam.fov = 45


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 30:
		root.get_texture().get_image().save_png(args.get("out", "/tmp/sleds.png"))
		return true
	return false
