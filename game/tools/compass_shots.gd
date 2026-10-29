extends SceneTree
## 自分の名札と、左下の球の方位磁針を確かめて撮る（一人称）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/compass_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots [--compass=knots]
## 0. まだ自分のソリが無いときは、左下は名札だけ
## 1. 自分の名札で 3 台縫ったことにして、丘のあちこちに置く（縫った人の名札が付く）
## 2. 歩き回り・向きを変えながら撮る: 針がそれぞれのソリを指し、距離が変わる
## 3. 米袋を N で出して乗る: 乗っている米袋の針は真下
## 4. 装備の画面（I）で名札の部品を替える → 自分のソリの名札も替わる

var args := {}
var main: Node3D
var p: CharacterBody3D
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/compass")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _key(k: Key) -> void:
	if main.settings and main.settings.is_open:   # 窓から目が離れると設定が開き、キーが効かなくなる
		main.settings.set_open(false)
		p.menu_open = false
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame


func _at(x: float, z: float, lift := 0.15) -> Vector3:
	return Vector3(x, main.height(x, z) + lift, z)


func _run() -> void:
	await _wait(2.5)
	p = main.player
	p.set_third(false)
	var c: Node = main.craft
	var who: int = p.id
	_say("自分の名札 %s" % [c.tag_designs[who]])
	# 0. まだ自分のソリが無い: 左下は名札だけ（方位磁針は出ない）
	p.global_position = _at(0.0, 40.0)
	p.rotation.y = 0.0
	await _wait(0.4)
	await _shot("00_no_sleds")
	# 1. 3 台縫ったことにして置く
	var spots := [[_at(14.0, 34.0), "small", "navy"], [_at(-16.0, 26.0), "mid", "mustard"], [_at(4.0, 8.0), "mid", "plum"]]
	for sp in spots:
		c.send({"kind": "sewn", "who": who, "sled": sp[1], "fabric": sp[2], "at": sp[0], "yaw": 0.3})
	await _wait(0.8)
	var mine := []
	for s in get_nodes_in_group("sleds"):
		if int(s.get("owner_id")) == who:
			mine.append(s)
	_say("自分の名札の付いたソリ: %d 台（名札 %s）" % [mine.size(), mine[0].tag if mine.size() > 0 else "-"])
	# 2. 歩き回る
	var walk := [[_at(0.0, 40.0), 0.0], [_at(0.0, 40.0), PI * 0.5], [_at(0.0, 40.0), PI], [_at(10.0, 28.0), 0.4], [_at(-8.0, 18.0), -0.8], [_at(2.0, 12.0), 2.6]]
	for i in walk.size():
		p.global_position = walk[i][0]
		p.velocity = Vector3.ZERO
		p.rotation.y = walk[i][1]
		p.set("_pitch", -0.1)
		await _wait(0.5)
		var ds := []
		for s in mine:
			ds.append("%.0f" % p.global_position.distance_to(s.global_position))
		_say("立ち位置 %d: 向き %.0f° 距離 %s m" % [i + 1, rad_to_deg(walk[i][1]), ", ".join(ds)])
		await _shot("%02d_walk" % (i + 1))
	# 3. 米袋に乗る
	p.global_position = _at(6.0, 20.0, 0.2)
	p.rotation.y = PI
	await _wait(0.4)
	await _key(KEY_N)
	await _wait(0.8)
	_say("米袋に乗った %s" % (p.mode == p.Mode.RIDE))
	await _shot("07_ride_sack")
	await _key(KEY_N)
	await _wait(0.4)
	# 4. 装備の画面で名札を替える
	p.global_position = mine[0].global_position + Vector3(1.6, 0.2, 1.2)
	p.rotation.y = atan2(-(mine[0].global_position.x - p.global_position.x), -(mine[0].global_position.z - p.global_position.z))
	await _key(KEY_I)
	await _wait(0.4)
	await _shot("08_gear_tag")
	var ui = main.craft_ui
	ui.set_tag_part("shape", 4, false)   # 確かめでは保存しない
	ui.set_tag_part("paper", 9, false)
	ui.set_tag_part("edge", 2, false)
	ui.set_tag_part("motif", 2, false)
	await _wait(0.4)
	_say("名札を替えた %s" % [c.tag_designs[who]])
	await _shot("09_gear_tag_changed")
	await _key(KEY_I)
	await _wait(0.4)
	p.set("_pitch", -0.35)
	await _shot("10_compass_new_tag")
	_say("ソリの名札も替わった %s" % (mine[0].tag == c.tag_designs[who]))
	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
