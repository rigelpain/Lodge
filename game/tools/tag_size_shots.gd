extends SceneTree
## 左下の名札の札の大きさを確かめる（2026-11-01 代表「タグ表示でかすぎるかも、もっと小さくできる？」）。
## 人型・名前・王冠が小さくしてもつぶれないかを見るため、3 人で押す所と、2 人で乗る所を撮る。
##   Godot --path game --resolution 1600x900 --fixed-fps 30 -s res://tools/tag_size_shots.gd -- --bots=2 --no-sound --no-pip --dir=/path/shots
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
	return args.get("dir", "/tmp/tag_size")


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
	c.send({"kind": "profile", "who": who, "name": "ハル", "color": 0})
	var mine := {"shape": 1, "material": 2, "paper": 6, "pattern": 3, "accent": 11, "stitch": 0, "edge": 6, "string": 6, "motif": 3}
	c.sleds[900] = sled
	sled.owner_id = who
	sled.retag(mine)

	# 押して登る（仲間も押す。三人称）
	_place_sled(40.0, 0.0)
	await _wait(0.3)
	p.set_third(true)
	p.global_position = sled.to_global(Vector3(0, 0, sled.HALF.y + 0.6)) + Vector3.UP * 0.2
	_face(sled.global_position, -0.15)
	p.grab()
	await _keep(KEY_W, 4.6)
	await _shot("push")
	_hold(KEY_W, false)
	p.let_go()

	# 乗って滑る（仲間も一人乗る。一人称）
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
	await _shot("ride")

	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
