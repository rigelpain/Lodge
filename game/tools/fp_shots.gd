extends SceneTree
## 一人称の画面を撮る（一人称の腕の確かめ用）。
##   Godot --path game --resolution 960x540 -s res://tools/fp_shots.gd -- --out=/path/to.png [--mode=idle|grip|point] [--at=秒]
## idle: 立って前を見る / grip: ソリのうしろからつかむ / point: 右前の雪を指す

var args := {}
var main: Node3D
var t := 0.0
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	if p == null or main.sled == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if not _done and t > 0.6:
		_done = true
		var sled: Node3D = main.sled
		var back: Vector3 = sled.global_basis.z
		match args.get("mode", "idle"):
			"grip":
				p.global_position = sled.global_position + back * 2.0 + Vector3.UP * 0.3
				p.rotation.y = atan2(back.x, back.z)
				p._pitch = -0.35
				p.grab()
			"point":
				p.global_position = sled.global_position + back * 4.0 + Vector3.UP * 0.3
				p.rotation.y = atan2(back.x, back.z) - 0.5
				p._pitch = -0.3
				p.toggle_point()
				p.rotate_y(0.5)
			_:
				p.global_position = sled.global_position + back * 4.0 + Vector3.UP * 0.3
				p.rotation.y = atan2(back.x, back.z)
				p._pitch = -0.15
	if t > float(args.get("at", "1.6")):
		root.get_texture().get_image().save_png(args.get("out", "/tmp/fp.png"))
		print("保存: ", args.get("out", ""), " mode=", p.mode)
		quit()
	return false
