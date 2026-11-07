extends SceneTree
## ロッジ前の地図の看板の灯りを、昼・夕方・夜で撮る（map_light.gd）。実時間で動かすので --fixed-fps は付けない。
##   Godot --path game --resolution 1280x720 -s res://tools/map_light_shots.gd -- --no-sound --hud-idle=0 --day=100000 --dir=/path/shots
## --fps: 撮らずに、夜の看板の前で灯りの有無を交互にして fps を出す（別の Godot が動いていないときに）

var args := {}
var main: Node3D
var p: CharacterBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(String(args.dir))
	_run.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t).timeout


## 撮るあいだに窓がキーの入力を受けても（I の装備の画面、歩く）、絵に出ないように、撮る直前に閉じて立ち直す
func _shot(nm: String, board: Node3D, off: float, back: float) -> void:
	main.craft_ui.close_gear()
	_stand(board, off, back)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.dir).path_join(nm + ".png"))
	print("撮った: ", nm)


## 看板の前に立って見る。off は正面からの横のずれ、back は看板からの距離 (m)
func _stand(board: Node3D, off: float, back: float) -> void:
	var at: Vector3 = board.global_transform * Vector3(off, 0, back)
	p.set_third(false)
	p.global_position = Vector3(at.x, main.height(at.x, at.z) + 0.2, at.z)
	var look: Vector3 = board.global_transform * Vector3(0, 3.8, 0)
	var d := look - (p.global_position + Vector3.UP * 1.5)
	p.rotation.y = atan2(-d.x, -d.z)
	p.set("_pitch", atan2(d.y, Vector2(d.x, d.z).length()))


func _run() -> void:
	await _wait(1.0)
	p = main.player
	var lamps: Node3D = null
	while lamps == null:   # 地図の絵を焼き終えると置かれる
		await process_frame
		lamps = main.find_child("MapLight", true, false)
	var board := lamps.get_parent() as Node3D
	var cycle := root.get_node("DayCycle")
	if args.has("fps"):
		await _fps(lamps, board, cycle)
		quit()
		return
	for h in [12.0, 17.0, 18.5, 22.0]:
		cycle.hour = h
		_stand(board, 0.0, 9.0)
		await _wait(1.2)
		await _shot("front_%04d" % int(h * 100.0), board, 0.0, 9.0)
		if h == 12.0:
			await _shot("close_1200", board, -2.2, 3.5)
	await _shot("side_2200", board, -7.0, 9.0)
	await _shot("far_2200", board, 0.0, 18.0)
	await _shot("close_2200", board, -2.2, 3.5)
	# 灯りを消した夜（比べる絵）
	lamps.set_process(false)
	for l in lamps.find_children("*", "SpotLight3D", true, false):
		l.visible = false
	await _wait(0.3)
	await _shot("front_2200_off", board, 0.0, 9.0)
	quit()


func _fps(lamps: Node3D, board: Node3D, cycle: Node) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	cycle.hour = 22.0
	lamps.set_process(false)
	_stand(board, 0.0, 9.0)
	var lights := lamps.find_children("*", "SpotLight3D", true, false)
	for l in lights:
		l.light_energy = 1.7
	for i in 8:
		var on := i % 2 == 0
		for l in lights:
			l.visible = on
		await _wait(1.5)
		main.craft_ui.close_gear()
		_stand(board, 0.0, 9.0)
		Engine.max_fps = 0   # 窓が前にないと main.gd が頭打ちを入れるので、測る直前に外す
		var n0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_usec()
		await _wait(4.0)
		print("%s: %.1f fps" % ["灯りあり" if on else "灯りなし", (Engine.get_frames_drawn() - n0) * 1e6 / (Time.get_ticks_usec() - t0)])
