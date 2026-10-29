extends SceneTree
## 左下の方位磁針（ピンクッションと待ち針）を、ソリが 0・1・3 台、前・横・後ろにあるときで撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/pillow_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots [--compass=pillow]
## <dir>/<n>_<名前>.png を書き、左下の札だけを切り出した見比べは呼ぶ側で作る。最後にクッションの色を替えて撮る（保存はしない）

var args := {}
var main: Node3D
var p: CharacterBody3D
var n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/pillow")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	await process_frame
	await process_frame
	n += 1
	root.get_texture().get_image().save_png(_dir().path_join("%02d_%s.png" % [n, name]))
	print("撮った: %02d_%s" % [n, name])


func _at(x: float, z: float, lift := 0.15) -> Vector3:
	return Vector3(x, main.height(x, z) + lift, z)


## 立つ所から、yaw の向きを見る（0 は -z）
func _look(yaw: float) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	p.rotation.y = yaw
	p.set("_pitch", -0.1)
	await _wait(0.35)


func _run() -> void:
	await _wait(2.5)
	p = main.player
	p.set_third(false)
	var c: Node = main.craft
	var who: int = p.id
	var stand := _at(0.0, 36.0)
	p.global_position = stand
	await _look(0.0)
	await _shot("0dai")
	# 1 台: 立つ所の真北（-z）20 m
	c.send({"kind": "sewn", "who": who, "sled": "small", "fabric": "navy", "at": _at(0.0, 16.0), "yaw": 0.0})
	await _wait(0.6)
	p.global_position = stand
	for v in [[0.0, "1dai_mae"], [PI * 0.5, "1dai_yoko"], [PI, "1dai_ushiro"]]:
		await _look(v[0])
		await _shot(v[1])
	# 3 台: 北西・東・南西
	c.send({"kind": "sewn", "who": who, "sled": "mid", "fabric": "mustard", "at": _at(18.0, 30.0), "yaw": 0.0})
	c.send({"kind": "sewn", "who": who, "sled": "mid", "fabric": "plum", "at": _at(-12.0, 50.0), "yaw": 0.0})
	await _wait(0.6)
	p.global_position = stand
	for v in [[0.0, "3dai_mae"], [PI * 0.5, "3dai_yoko"], [PI, "3dai_ushiro"]]:
		await _look(v[0])
		await _shot(v[1])
	# 上下: 頂上から見下ろす（ソリは下）と、ふもとから見上げる（1 台目は上）
	p.global_position = _at(0.0, 2.0)
	await _look(PI)
	await _shot("shita")
	p.global_position = _at(0.0, 44.0)
	await _look(0.0)
	await _shot("ue")
	# 米袋に乗る
	p.global_position = stand
	var e := InputEventKey.new()
	e.physical_keycode = KEY_N
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(0.6)
	await _shot("noru")
	e = InputEventKey.new()
	e.physical_keycode = KEY_N
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(0.5)
	p.global_position = stand
	await _look(0.0)
	# クッションの色を替える（0 は名札の地の色）
	for i in [0, 2, 4]:
		main.craft_ui.set_tag_part("cushion", i, false)
		await _wait(0.2)
		await _shot("iro%d" % i)
	# 名札の中身: 最初のソリを押す・乗って滑る・離れる
	main.craft_ui.set_tag_part("cushion", 1, false)
	var big: RigidBody3D = main.sled
	p.sled = big
	p.global_position = big.to_global(Vector3(0, 0.2, big.HALF.y + big.STAND))
	p.rotation.y = big.rotation.y
	p.grab()
	await _key_hold(KEY_W, 2.5)
	await _shot("osu")
	p.let_go()
	big.reset_to(_at(0.0, 10.0, 0.6))
	big.rotation.y = PI   # ふもと（+z）へ向ける
	await _wait(0.3)
	p.global_position = big.global_position + Vector3(1.5, 0.2, 0)
	p.sled = big
	p.get_on()
	big.parked = false
	big.apply_central_impulse(Vector3(0, 0, 4.0) * big.mass)
	await _wait(2.0)
	await _shot("noru_suberu")
	p.get_off()
	await _wait(0.3)
	p.global_position = _at(-30.0, 60.0)
	await _look(0.0)
	await _wait(1.5)
	await _shot("hanareru")
	quit()


func _key_hold(k: Key, t: float) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(t)
	var r := InputEventKey.new()
	r.physical_keycode = k
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame
