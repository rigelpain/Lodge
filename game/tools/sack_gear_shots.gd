extends SceneTree
## 装備の米袋（craft.gd の sacks、player.gd の toggle_sack）を確かめて撮る（一人称）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/sack_gear_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 1. 坂の途中で N: 足もとに米袋が出て、すぐ乗り、滑り出す
## 2. 乗ったまま N: 降りて、丸めて帯に戻る
## 3. I で装備の画面を開き、色違いの米袋を選んで閉じ、N でその米袋が出る（縫った米袋を足しておく）
## 4. 出したまま降りて遠くへ歩く: 30 m・4 秒で、ひとりでに帯に戻る
## 5. 大きいソリをつかんだまま N: 手を離して、米袋に乗る
## キーは本物の入力のイベントで流す

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
	return args.get("dir", "/tmp/sack")


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


func _key(k: Key, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		e.shift_pressed = shift
		Input.parse_input_event(e)
		await process_frame


func _put(at: Vector3, look: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))
	p.set("_pitch", -0.2)


func _run() -> void:
	await _wait(2.5)
	p = main.player
	var c: Node = main.craft
	var who: int = p.id
	_say("最初の装備の米袋 %s 持ち物 %s" % [c.sacks[who], c.bag(who)])
	# 1. 坂の途中（中腹、ふもとを向いて）で N
	var at := Vector3(3.0, 0, 16.0)
	at.y = main.height(at.x, at.z) + 0.2
	_put(at, Vector3(3.0, 0, 60.0))
	await _wait(1.0)
	await _shot("01_before")
	await _key(KEY_N)
	await _wait(0.15)
	await _shot("02_pop")
	_say("N: 乗った %s" % (p.mode == p.Mode.RIDE and p.sled == c.sack_sled(who)))
	await _wait(1.5)
	var gs: RigidBody3D = c.sack_sled(who)
	_say("1.5 秒後の速さ %.1f m/s" % (gs.linear_velocity.length() if gs else -1.0))
	await _shot("03_sliding")
	await _wait(1.5)
	await _shot("04_sliding2")
	# 2. 乗ったまま N
	await _key(KEY_N)
	await _wait(0.4)
	_say("乗ったまま N: 帯に戻った %s 歩く %s" % [c.sack_sled(who) == null, p.mode == p.Mode.WALK])
	await _shot("05_stowed")
	# 3. 縫った米袋を足して、装備の画面（I）で選ぶ → 閉じる → N
	c.sacks[who].append({"fabric": "mustard", "tag": 6})
	c.sacks[who].append({"fabric": "navy", "tag": 3})
	c.bags[who] = [{"kind": "pattern", "sled": "small"}, {"kind": "fabric", "fabric": "plum"}]
	await _key(KEY_I)
	await _wait(0.4)
	_say("I: 装備の画面 %s" % main.craft_ui.gear_open)
	await _shot("06_gear_open")
	_say("からしの米袋を選ぶ: %s 装備 %d / %d" % [main.craft_ui.equip(1), c.sack_sel[who], c.sacks[who].size()])
	await _wait(0.3)
	await _shot("06b_gear_picked")
	await _key(KEY_I)
	await _wait(0.3)
	_say("I でもう一度: 閉じた %s" % (not main.craft_ui.gear_open))
	await _shot("06c_gear_closed")
	await _key(KEY_N)
	await _wait(0.6)
	gs = c.sack_sled(who)
	_say("N で装備の米袋が出た: %s（布 %s）" % [gs != null, gs.fabric if gs else ""])
	await _shot("07_mustard")
	# 4. 降りて遠くへ
	p.get_off()
	p.global_position = gs.global_position + Vector3(40, 0, 0)
	p.global_position.y = main.height(p.global_position.x, p.global_position.z) + 0.3
	await _wait(5.0)
	_say("40 m 離れて 5 秒: ひとりでに帯に戻った %s" % (c.sack_sled(who) == null))
	# 5. 大きいソリをつかんだまま N
	var big: RigidBody3D = main.sled
	p.global_position = big.to_global(Vector3(0, 0.2, big.HALF.y + big.STAND))
	p.rotation.y = big.rotation.y
	p.sled = big
	p.grab()
	await _wait(0.3)
	_say("大きいソリをつかんでいる %s" % (p.mode == p.Mode.GRIP))
	await _key(KEY_N)
	await _wait(0.3)
	_say("つかんだまま N: 手を離して米袋に乗った %s" % (p.mode == p.Mode.RIDE and p.sled == c.sack_sled(who)))
	await _shot("08_from_big")
	_say("持ち物 %s（米袋は入らない）" % [c.bag(who)])
	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
