extends SceneTree
## ソリの名札（2026-10-31 の作り直し）を撮って確かめる。
##   Godot --path game --resolution 1600x900 --fixed-fps 30 -s res://tools/sled_tag_shots.gd -- --bots=2 --no-sound --no-pip --dir=/path/shots
## 撮るもの:
##   01〜04 押して登る・乗って滑る（一人称・三人称）。左下の札に、丘と、人を乗せて回るソリと、王冠を載せた持ち主
##   05 紐で引く  06 ロッジのソリ（持ち主はロッジ）
##   07〜09 名札を外す（G を長押しの途中の輪・外したあとの無地の札）、付け直す
##   10 装備の画面（名前・キャラの色・替える名札の列）  11 米袋に名札がない（三人称）
## 回る図の向きが変わるのを見るため、01 は 1 秒おきに 4 枚撮る（回る図は 12 秒で 1 周）

const Bot := preload("res://bot.gd")

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
	return args.get("dir", "/tmp/sled_tag")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _hold(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)


## キーを押したままにする（窓が前に出ていないと押した印が消えることがあるので、毎コマ押し直す）
func _keep(k: Key, t: float) -> void:
	for i in int(t * Engine.physics_ticks_per_second):
		_hold(k, true)
		await physics_frame


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	if main.hud:
		main.hud.debug_on = false
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	_say("撮った " + name)


func _face(at: Vector3, pitch := -0.15) -> void:
	var d := at - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p.set("_pitch", pitch)


## ソリを丘の、頂上から r m の所に置く（yaw 0 で頂上を向く）
func _place_sled(r: float, yaw: float) -> void:
	var sled: RigidBody3D = main.sled
	var at := Vector3(0, 0, r)
	at.y = main.height(at.x, at.z) + 0.35
	sled.reset_to(at)
	sled.rotation.y = yaw


func _bots() -> Array:
	return main.get_children().filter(func(c): return c.get_script() == Bot and not c.lounge)


## 仲間をソリに乗せる
func _mount(b: Node) -> void:
	var sled: RigidBody3D = main.sled
	b.let_go()
	b.seat = sled.mount(b)
	if b.seat != Vector3.INF:
		b._col.disabled = true
		b.state = Bot.State.RIDE


func _run() -> void:
	await _wait(2.5)
	p = main.player
	var c: Node = main.craft
	var who: int = p.id
	var sled: RigidBody3D = main.sled
	# 自分の名前と色。仲間の名前と色ははじめのまま
	c.send({"kind": "profile", "who": who, "name": "ハル", "color": 0})
	# ロッジのソリを、自分が持ち主のソリにする（名札の柄はソリごと）
	var mine := {"shape": 1, "material": 2, "paper": 6, "pattern": 3, "accent": 11, "stitch": 0, "edge": 6, "string": 6, "motif": 3}
	c.sleds[900] = sled
	sled.owner_id = who
	sled.retag(mine)
	for b in _bots():
		_say("仲間 %d: %s %s" % [b.id, c.name_of(b.id), c.color_of(b.id)])

	# 01・02 押して登る（仲間も押す）
	_place_sled(40.0, 0.0)
	await _wait(0.3)
	p.set_third(false)
	p.global_position = sled.to_global(Vector3(0, 0, sled.HALF.y + 0.6)) + Vector3.UP * 0.2
	_face(sled.global_position, -0.15)
	p.grab()
	await _keep(KEY_W, 4.0)
	_say("押している: pushing %s 押した人 %s" % [p.pushing, sled._pushed_by.has(p)])
	for k in 4:   # 回る図がゆっくり回る（1 秒に 30°）
		await _shot("01_push_fp_%d" % k)
		await _keep(KEY_W, 1.0)
	p.set_third(true)
	await _keep(KEY_W, 0.6)
	await _shot("02_push_3p")
	_hold(KEY_W, false)
	p.let_go()

	# 03・04 乗って滑る（仲間も一人乗る）
	_place_sled(9.0, PI)
	await _wait(0.3)
	for b in _bots():
		b.let_go()
	var bots := _bots()
	if bots.size() > 0:
		_mount(bots[0])
	p.global_position = sled.global_position + sled.global_basis.x * 1.2 + Vector3.UP * 0.3
	p.get_on()
	p.rotation.y = sled.global_rotation.y
	p.set("_pitch", -0.2)
	p.set_third(false)
	sled.linear_velocity = -sled.global_basis.z * 4.0
	await _wait(1.0)
	await _shot("03_ride_fp")
	p.set_third(true)
	await _wait(0.5)
	await _shot("04_ride_3p")
	p.get_off()
	for b in _bots():
		b.get_off()
	await _wait(0.4)

	# 05 紐で引く
	_place_sled(30.0, 0.0)
	await _wait(0.3)
	p.set_third(true)
	p.global_position = sled.rope.end_point() + Vector3.UP * 0.2
	_face(sled.global_position + (-sled.global_basis.z) * 10.0, -0.1)
	p.grab_rope()
	await _keep(KEY_W, 1.2)
	await _shot("05_rope_3p")
	_hold(KEY_W, false)
	p.let_go()

	# 06 ロッジのソリ（持ち主はロッジ。ロッジの名札）
	sled.owner_id = -1
	sled.retag(0)
	_place_sled(40.0, 0.0)
	await _wait(0.3)
	p.set_third(false)
	p.global_position = sled.to_global(Vector3(0, 0, sled.HALF.y + 0.6)) + Vector3.UP * 0.2
	_face(sled.global_position, -0.15)
	p.grab()
	await _wait(1.0)
	await _shot("06_lodge_sled")
	p.let_go()

	# 07〜09 名札を外す・付け直す（自分のソリで）
	sled.owner_id = who
	sled.retag(mine)
	await _wait(0.2)
	p.set_third(true)
	p.global_position = sled.tag_point() + sled.global_basis.x * 1.2 - Vector3.UP * 0.6
	_face(sled.tag_point(), -0.2)
	p.last_sled = sled
	await _wait(0.6)
	_hold(KEY_G, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _wait(0.4)
	_say("長押しの途中 %.2f 先 %s" % [p.tag_hold, p.tag_target()])
	await _shot("07_untag_hold")
	await _wait(0.8)
	_hold(KEY_G, false)
	await _wait(0.2)
	await _shot("07b_untag_flying")
	await _wait(0.8)
	_say("外したあと: 持ち主 %d 名札 %s 名札入れ %d" % [sled.owner_id, sled.tag, c.loose_tags[who].size()])
	await _shot("08_untagged")
	p.global_position = sled.tag_point() + sled.global_basis.x * 1.2 - Vector3.UP * 0.6
	_face(sled.tag_point(), -0.2)
	await _wait(0.3)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hold(KEY_G, true)
	await _wait(0.4)
	_say("付ける途中 %.2f 先 %s 姿 %d 名札まで %.2f マウス %d" % [p.tag_hold, p.tag_target(), p.mode, sled.tag_point().distance_to(p.global_position + Vector3.UP * 0.9), Input.mouse_mode])
	await _wait(0.8)
	_hold(KEY_G, false)
	await _wait(1.0)
	_say("付けたあと: 持ち主 %d 名札入れ %d" % [sled.owner_id, c.loose_tags[who].size()])
	await _shot("09_tag_on")
	# 名札入れに一枚残して、装備の画面で見せる
	await _wait(0.6)
	_hold(KEY_G, true)
	await _wait(1.2)
	_hold(KEY_G, false)
	await _wait(0.6)
	c.bags[who].append({"kind": "folded", "sled": "small", "fabric": "navy", "tag": c.tag_designs[who]})

	# 10 装備の画面
	main.craft_ui.open_gear()
	main.craft_ui.tag_edit = {"loose": 0}
	await _wait(0.6)
	await _shot("10_gear")
	main.craft_ui.close_gear()
	await _wait(0.3)

	# 11 米袋に名札がない
	p.set_third(true)
	p.global_position = Vector3(6, 0, 30)
	p.global_position.y = main.height(6, 30) + 0.3
	_face(Vector3(6, main.height(6, 26), 26), -0.35)
	await _wait(0.4)
	p.toggle_sack()
	await _wait(1.2)
	var gs = c.sack_sled(who)
	if p.mode == p.Mode.RIDE:
		p.get_off()
	if gs:
		gs.linear_velocity = Vector3.ZERO
		gs.freeze = true
		p.set_third(false)
		p.global_position = gs.global_position + Vector3(1.4, 0.3, 1.4)
		_face(gs.global_position, -0.75)
	await _wait(0.5)
	_say("米袋: %s 名札 %s 吊るした名札 %s" % [gs, gs.tag if gs else null, gs.get_node_or_null("Tag") if gs else null])
	await _shot("11_sack_3p")

	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
