extends SceneTree
## 帯のランタン（lantern.gd・craft.gd の lanterns と lamp）を確かめて撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/lantern_shots.gd -- --bots=2 --no-sound --no-pip --dir=/path/shots
## 夕方・夜・ロッジの中で、一人称・三人称・右下の小窓。点ける・消す・歩く・押す・乗る・米袋。キーは本物の入力のイベントで流す。
## 最後に、ランタンの数で fps を比べる（--perf）。数は log.txt に書く

var args := {}
var main: Node3D
var p: CharacterBody3D
var dc: Node
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 昼夜の時計（daycycle.gd）が、今の場面から太陽を探す
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/lantern")


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


func _key(k: Key, down := true, up := true) -> void:
	for d in ([true, false] if down and up else [down]):
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = d
		Input.parse_input_event(e)
		await process_frame


func _put(at: Vector3, look: Vector3, pitch := -0.15) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))
	p.set("_pitch", pitch)


func _third(on: bool) -> void:
	p.set_third(on)


func _hour(h: float) -> void:
	dc.hour = h
	dc.day_seconds = 1.0e9   # 撮るあいだは時刻を止める
	await _wait(1.2)   # 空の色は 0.5 秒ごと


## 外の平らな所（ふもと寄り）
func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, main.height(x, z) + 0.15, z)


func _run() -> void:
	await _wait(2.5)
	p = main.player
	dc = root.get_node("DayCycle")
	var c: Node = main.craft
	var who: int = p.id
	_say("提げているランタン %s 点いている %s" % [c.lantern(who), c.lamp_on(who)])
	var start: Vector3 = p.global_position
	var sled: RigidBody3D = main.sled
	var bots: Array = []
	for n in main.get_children():
		if n is CharacterBody3D and n != p:
			bots.append(n)

	# 1. 夕方（17:40）: 点ける前と、R で点けたあと。三人称と一人称
	await _hour(17.7)
	var at := _ground(start.x + 4.0, start.z + 6.0)
	_put(at, at + Vector3(0, 0, 10))
	_third(true)
	await _wait(0.5)
	await _shot("01_dusk_off_3rd")
	await _key(KEY_R)
	await _wait(0.6)
	_say("R: 点いた %s" % c.lamp_on(who))
	await _shot("02_dusk_on_3rd")
	_third(false)
	p.set("_pitch", -0.7)
	await _wait(0.3)
	await _shot("03_dusk_on_1st_down")
	p.set("_pitch", -0.2)
	await _wait(0.2)
	await _shot("04_dusk_on_1st")

	await _close("03b_dusk_close")
	# 2. 夜（21:00）: 一人称・三人称。消す・点ける
	await _hour(21.0)
	await _shot("05_night_on_1st")
	await _key(KEY_R)
	await _wait(0.6)
	_say("R: 消えた %s" % (not c.lamp_on(who)))
	await _shot("06_night_off_1st")
	await _key(KEY_R)
	await _wait(0.6)
	_third(true)
	await _wait(0.3)
	await _shot("07_night_on_3rd")
	await _close("07b_night_close")
	await _close("07c_night_close_front", true)
	_say("仲間のランタン: %s" % [bots.map(func(b): return [c.lantern(b.id).get("look", ""), c.lamp_on(b.id)])])

	# 3. 夜に歩く（W を押したまま）: 揺れのコマを 3 枚
	_put(_ground(start.x + 4.0, start.z + 6.0), _ground(start.x + 4.0, start.z + 30.0))
	await _key(KEY_W, true, false)
	for i in 3:
		await _wait(0.45 if i == 0 else 0.17)
		await _shot("08_walk_%d" % i)
	await _key(KEY_W, false, true)

	# 4. 夜にソリを押す（つかむ）・乗る
	p.global_position = sled.to_global(Vector3(0, 0.2, sled.HALF.y + sled.STAND))
	p.rotation.y = sled.rotation.y
	p.sled = sled
	p.grab()
	await _wait(0.6)
	_say("押す: つかんでいる %s" % (p.mode == p.Mode.GRIP))
	await _shot("09_push_3rd")
	_third(false)
	await _wait(0.2)
	await _shot("10_push_1st")
	p.let_go()
	await _wait(0.2)
	p.get_on()
	await _wait(0.8)
	_say("乗る: %s" % (p.mode == p.Mode.RIDE))
	_third(true)
	await _wait(0.3)
	await _shot("11_ride_3rd")
	p.get_off()
	await _wait(0.5)

	# 5. 夜に米袋（坂の途中で N）
	var hill := Vector3(3.0, 0, 16.0)
	hill.y = main.height(hill.x, hill.z) + 0.2
	_put(hill, Vector3(3.0, 0, 60.0))
	await _wait(0.6)
	await _key(KEY_N)
	await _wait(1.4)
	_say("米袋: 乗っている %s" % (p.mode == p.Mode.RIDE and p.sled == c.sack_sled(who)))
	await _shot("12_sack_3rd")
	_third(false)
	await _wait(0.2)
	await _shot("13_sack_1st")
	await _key(KEY_N)
	await _wait(0.6)

	# 6. ロッジの中（夜）: 売り子のおじさんの前。点いている・消えている
	var sk: Node3D = main.shopkeeper
	if sk:
		var ia := sk.to_global(Vector3(0, 0.1, -2.4))
		_put(ia, sk.global_position, -0.25)
		await _wait(0.8)
		await _shot("14_lodge_on_1st")
		_third(true)
		await _wait(0.3)
		await _shot("15_lodge_on_3rd")
		await _key(KEY_R)
		await _wait(0.6)
		await _shot("16_lodge_off_3rd")
		await _key(KEY_R)
		await _wait(0.4)

	# 7. 装備の画面（I）: ランタンを外す・付け替える
	_third(false)
	_put(_ground(start.x + 4.0, start.z + 6.0), _ground(start.x + 4.0, start.z + 30.0))
	await _wait(0.4)
	await _shot("17_hud")
	await _key(KEY_I)
	await _wait(0.4)
	await _shot("18_gear_screen")
	_say("提灯に替える: %s" % main.craft_ui.equip(1, "lantern"))
	await _wait(0.3)
	await _shot("19_gear_paper")
	await _key(KEY_I)
	await _wait(0.3)
	_third(true)
	await _wait(0.4)
	await _shot("20_paper_3rd")
	_say("外す: %s 点いている %s" % [main.craft_ui.equip(-1, "lantern"), c.lamp_on(who)])
	await _wait(0.3)
	await _shot("21_none_3rd")
	_say("外したまま R: 断られる %s" % (not p.toggle_lamp()))
	main.craft_ui.equip(0, "lantern")

	# 8. 重さ: ランタンの数で fps を比べる（夜、外。仲間のほかに、灯りだけの人形を増やす）
	if args.has("perf"):
		_third(false)
		_put(_ground(start.x, start.z + 4.0), _ground(start.x, start.z + 20.0), -0.2)
		for b in bots:
			c.send({"kind": "lamp", "who": b.id, "on": false})
		c.send({"kind": "lamp", "who": who, "on": false})
		await _wait(1.0)
		_say("fps ランタンなし %.1f" % await _fps())
		c.send({"kind": "lamp", "who": who, "on": true})
		for b in bots:
			c.send({"kind": "lamp", "who": b.id, "on": true})
		await _wait(1.0)
		_say("fps 点いたランタン %d 個 %.1f" % [1 + bots.size(), await _fps()])
		var Doll := preload("res://doll.gd")
		var extra: Array = []
		for i in 6:   # 人形だけを並べて、ランタンを点ける（8 人で遊ぶときの数）
			var host := Node3D.new()
			main.add_child(host)
			host.global_position = _ground(start.x - 5.0 + 2.0 * i, start.z + 9.0)
			var d := Doll.new()
			d.kind = ["kasa", "origami", "news"][i % 3]
			d.lantern = "box" if i % 2 == 0 else "paper"
			d.lantern_lit = false
			host.add_child(d)
			extra.append(d)
		await _wait(1.5)
		_say("fps 人形を 6 体足す（ランタンは消えている）%.1f" % await _fps())
		for d in extra:
			d.lantern_lit = true
		await _wait(1.0)
		await _shot("22_eight_lanterns")
		_say("fps 点いたランタン %d 個 %.1f" % [1 + bots.size() + extra.size(), await _fps()])
		# 同じ時間の中で、全部消す・全部点けるを交互に 4 回ずつ（ほかの重い処理の揺れを打ち消す）
		var sums := {false: 0.0, true: 0.0}
		for k in 8:
			var on := k % 2 == 1
			for b in bots:
				c.send({"kind": "lamp", "who": b.id, "on": on})
			c.send({"kind": "lamp", "who": who, "on": on})
			for d in extra:
				d.lantern_lit = on
			await _wait(0.6)
			var n := 0
			var t0 := Time.get_ticks_usec()
			while Time.get_ticks_usec() - t0 < 2000000:
				await process_frame
				n += 1
			sums[on] += n / ((Time.get_ticks_usec() - t0) / 1.0e6)
		_say("交互 4 回の平均: 消す fps %.1f / 点ける（9 個）fps %.1f" % [sums[false] / 4, sums[true] / 4])

	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()


## 腰のランタンを近くから撮る（横から。front なら前の斜めから）
func _close(name: String, front := false) -> void:
	var cam := Camera3D.new()
	main.add_child(cam)
	var b := p.global_basis
	var hip: Vector3 = p.global_position + Vector3.UP * 0.6
	var off := (-b.x * 1.3 + b.z * 0.9) if not front else (-b.x * 1.0 - b.z * 1.2)
	cam.look_at_from_position(hip + off + Vector3.UP * 0.35, hip, Vector3.UP)
	cam.fov = 45.0
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)
	cam.current = true
	await _wait(0.3)
	await _shot(name)
	cam.queue_free()
	p.cam.current = true


## 3 秒の平均の fps
func _fps() -> float:
	var n := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 3000000:
		await process_frame
		n += 1
	return n / ((Time.get_ticks_usec() - t0) / 1.0e6)
