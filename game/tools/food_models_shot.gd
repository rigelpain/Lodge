extends SceneTree
## 雪だるまの店の料理とペレットを、ゲームの素材（props.gd）で並べて撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/food_models_shot.gd -- --out=/path/x.png [--only=taiyaki] [--pellets]

const Props := preload("res://props.gd")
const Food := preload("res://food.gd")

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.42, 0.33)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.85, 0.8)
	env.environment.ambient_light_energy = 0.6
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	stage.add_child(sun)
	var keys: Array = Food.ORDER if not args.has("only") else String(args.only).split(",")
	var cols := 6
	for i in keys.size():
		var path: String = Food.pellet_glb(keys[i]) if args.has("pellets") else Food.dish_glb(keys[i])
		var n := Props.make(path)
		n.position = Vector3((i % cols) * 0.3, 0, (i / cols) * 0.3)
		stage.add_child(n)
	var cam := Camera3D.new()
	var w := mini(keys.size(), cols) * 0.3
	var rows := (keys.size() + cols - 1) / cols
	stage.add_child(cam)
	cam.look_at_from_position(Vector3(w / 2 - 0.15, 0.5 + 0.12 * rows, rows * 0.3 + 0.25), Vector3(w / 2 - 0.15, 0, rows * 0.15 - 0.05))
	cam.fov = 40 if keys.size() > 1 else 18
	cam.current = true
	for k in 6:
		await process_frame
	root.get_texture().get_image().save_png(args.get("out", "/tmp/food_models.png"))
	print("保存: ", args.get("out", "/tmp/food_models.png"))
	quit()
