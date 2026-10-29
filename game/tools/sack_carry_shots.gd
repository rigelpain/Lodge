extends SceneTree
## 走りながら米袋を出して、その勢いで滑るのと、乗ったまま Space で漕ぐのを撮る（一人称と三人称）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/sack_carry_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 場面ごとに、一人称（fp）と三人称（tp）で 1 回ずつ:
##   flat_run   平らな所で走って（Shift+W）N。W は押したまま。走る前・出した直後・1 秒・2.5 秒・勢いが尽きた所
##   flat_mash  平らな所で走って N、乗ってから 1 秒に 8 回 Space をたたく
##   flat_hold  平らな所で走って N、Space を押しっぱなし
##   slope_mash 坂で走って N、1 秒に 8 回 Space
## キーは本物の入力のイベントで流す。各絵の名前に、そのときの米袋の速さを書く（log.txt）

var args := {}
var main: Node3D
var p: CharacterBody3D
var lines: Array[String] = []
var _mash := false
var _mash_t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/sack_carry")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _tap(k: Key) -> void:
	_press(k, true)
	await process_frame
	_press(k, false)


func _physics_process(dt: float) -> bool:
	if _mash:
		_mash_t -= dt
		if _mash_t <= 0.0:
			_mash_t += 1.0 / 8.0
			_press(KEY_SPACE, true)
			_press(KEY_SPACE, false)
	return false


func _speed() -> float:
	return p.sled.linear_velocity.length() if p.mode == p.Mode.RIDE else Vector2(p.velocity.x, p.velocity.z).length()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var v := _speed()
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	_say("%s  %.1f m/s（%s）" % [name, v, "乗っている" if p.mode == p.Mode.RIDE else "歩いている"])


func _put(at: Vector2, dir: Vector2) -> void:
	var pos := Vector3(at.x, 0, at.y)
	pos.y = main.height(pos.x, pos.z) + 0.2
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-dir.x, -dir.y)
	p.set("_pitch", -0.12)


func _scene(name: String, at: Vector2, dir: Vector2, space: String, view: String) -> void:
	var tag := "%s_%s" % [name, view]
	p.set_third(view == "tp")
	var d := dir.normalized()
	_put(at - d * 4.0, d)
	await _wait(0.6)
	_press(KEY_SHIFT, true)
	_press(KEY_W, true)
	await _wait(0.6)
	await _shot(tag + "_0_run")
	await _wait(0.6)
	await _tap(KEY_N)
	_press(KEY_SHIFT, false)
	if space == "mash":
		_mash = true
	elif space == "hold":
		_press(KEY_SPACE, true)
	await _wait(0.25)
	await _shot(tag + "_1_out")
	await _wait(0.75)
	await _shot(tag + "_2_1s")
	await _wait(1.5)
	await _shot(tag + "_3_2.5s")
	await _wait(2.0)
	await _shot(tag + "_4_4.5s")
	_mash = false
	_press(KEY_SPACE, false)
	_press(KEY_W, false)
	await _wait(1.0)
	if p.mode == p.Mode.RIDE and p.sled.kind == "sack":
		await _tap(KEY_N)
	await _wait(1.5)


func _run() -> void:
	await _wait(2.5)
	p = main.player
	var flat := Vector2(60, -60)
	var down := Vector2(1, -1)
	for view in ["fp", "tp"]:
		await _scene("flat_run", flat, down, "none", view)
		await _scene("flat_mash", flat, down, "mash", view)
		await _scene("flat_hold", flat, down, "hold", view)
		await _scene("slope_mash", Vector2(12, 0), Vector2(1, 0), "mash", view)
	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
