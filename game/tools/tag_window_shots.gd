extends SceneTree
## 左下の札（hud.gd の _draw_tag）が、柄の違う自分の名札でも読めるかを撮る（一人称）。
##   Godot --path game --resolution 1600x900 --fixed-fps 30 -s res://tools/tag_window_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 名札ごとに: 押して登る（ソリの後ろでつかみ W）、乗って滑る。最初の名札では、背景を変えて（雪・空・ロッジ）も撮る。
## 撮った絵の左下（札）を切り抜いて並べると、直す前と後を比べられる

const Sheet := preload("res://tools/tag_sheet.gd")

## 撮る名札: [名前, 部品の辞書（書いていない部品は DEFAULT）]
const CASES := [
	["gingham", {"shape": 1, "material": 2, "paper": 6, "pattern": 3, "accent": 11, "stitch": 0, "edge": 6, "string": 6}],   # 代表が見せた黄と茶の格子
	["seigaiha", -2],
	["sumi_oval", -8],
	["asanoha", -10],
	["yagasuri", -9],
	["patchwork", -7],
	["leather", -4],
	["leaf", -3],
	["plain", {"shape": 0, "material": 0, "paper": 0, "pattern": 0, "stitch": 0, "edge": 0, "string": 1, "deco": 0}],
]

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
	return args.get("dir", "/tmp/tag_window")


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


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	if main.hud:
		main.hud.debug_on = false
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


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


func _run() -> void:
	await _wait(2.5)
	p = main.player
	p.set_third(false)
	var c: Node = main.craft
	var who: int = p.id
	var Tags := preload("res://sled_tags.gd")
	for part in Tags.PARTS:
		for i in range(Tags.STARTER[part], Tags.part_count(part)):
			c.send({"kind": "tag_unlock", "who": who, "part": part, "index": i})
	var sled: RigidBody3D = main.sled
	for k in CASES.size():
		var name: String = CASES[k][0]
		var d: Dictionary = Sheet.combo(-int(CASES[k][1]) - 1) if CASES[k][1] is int else (CASES[k][1] as Dictionary)
		c.send({"kind": "tag_design", "who": who, "design": d})
		# 押して登る
		_place_sled(40.0, 0.0)
		await _wait(0.3)
		p.global_position = sled.to_global(Vector3(0, 0, 2.2)) + Vector3.UP * 0.2
		_face(sled.global_position, -0.15)
		p.grab()
		_hold(KEY_W, true)
		await _wait(1.4)
		await _shot("%02d_%s_push" % [k + 1, name])
		_hold(KEY_W, false)
		p.let_go()
		# 乗って滑る
		_place_sled(9.0, PI)
		await _wait(0.2)
		p.global_position = sled.global_position + sled.global_basis.x * 1.2 + Vector3.UP * 0.3
		p.get_on()
		p.rotation.y = sled.global_rotation.y
		p.set("_pitch", -0.2)
		sled.linear_velocity = -sled.global_basis.z * 4.0
		await _wait(1.0)
		await _shot("%02d_%s_ride" % [k + 1, name])
		p.get_off()
		await _wait(0.3)
		if k == 0:   # 背景を変える: 足もとの雪、空、ロッジ
			_place_sled(40.0, 0.0)
			await _wait(0.3)
			p.global_position = sled.to_global(Vector3(2.0, 0, 1.5)) + Vector3.UP * 0.2
			_face(sled.global_position, -0.9)
			await _wait(0.6)
			await _shot("%02d_%s_bg_snow" % [k + 1, name])
			p.set("_pitch", 0.55)
			await _wait(0.4)
			await _shot("%02d_%s_bg_sky" % [k + 1, name])
			var lodge := Vector3(0, 0, 80.0)
			if main.has_node("Audio"):
				lodge = main.get_node("Audio").spawn_point("inside")
			_place_sled(58.0, 0.0)
			await _wait(0.3)
			p.global_position = sled.to_global(Vector3(-1.5, 0, -1.5)) + Vector3.UP * 0.2
			_face(lodge + Vector3.UP * 1.0, -0.05)
			await _wait(0.6)
			await _shot("%02d_%s_bg_lodge" % [k + 1, name])
		_say("%d %s: %s" % [k + 1, name, c.tag_designs[who]])
	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
