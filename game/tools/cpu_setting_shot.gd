extends SceneTree
## 設定の画面の「CPU の数」の行を撮る（確かめ用）。--join 相当の見た目は --lock で（触れない札になる）。保存は書き換えない。
##   Godot --path game --resolution 1280x720 -s res://tools/cpu_setting_shot.gd -- --no-sound --roam-bots=5 --out=/path/cpus.png [--lock]
var args := {}
var main: Node3D
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()
func _run() -> void:
	await create_timer(2.0).timeout
	var st = main.settings
	if args.has("lock"):
		st.lock("cpus", "ホストが決める")
	st.set_open(true)
	main.player.menu_open = true
	await create_timer(0.3).timeout
	var c: Control = st._controls["cpus"]
	st._scroll.ensure_control_visible(c)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(String(args.get("out", "/tmp/cpus.png")))
	quit()
