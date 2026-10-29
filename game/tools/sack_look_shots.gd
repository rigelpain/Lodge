extends SceneTree
## 米袋の色と紐の見え方を撮る（確かめ用）。標準（クラフト紙）と、布の色を変えた米袋 3 つ。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/sack_look_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 1. 置いたとき: 平らな所に 4 つ並べて、少し上から（一人称の目で）
## 2. 呼び出して滑るとき: 坂の中腹で、それぞれの米袋を N で呼び出して乗り、滑っているところ（右下の小窓つき）

const SPECS := [{"fabric": "", "tag": 1}, {"fabric": "navy", "tag": 3}, {"fabric": "mustard", "tag": 6}, {"fabric": "plum", "tag": 9}]

var args := {}
var main: Node3D
var p: CharacterBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/sacklook")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	print("撮った: ", name)


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame


func _run() -> void:
	await _wait(2.5)
	p = main.player
	p.set_third(false)
	var c: Node = main.craft
	var who: int = p.id
	# 1. 置いたとき: ふもとの平らな所に横に並べる
	var base: Vector3 = main.get_node("Lodge").to_global(Vector3(-6.0, 0, 30.0))   # ロッジの前の、ならした平らな所
	var placed := []
	for i in SPECS.size():
		var s: RigidBody3D = preload("res://sled.gd").new()
		s.kind = "sack"
		s.fabric = SPECS[i].fabric
		s.tag = SPECS[i].tag
		var at := base + Vector3(i * 1.0, 0, 0)
		at.y = main.height(at.x, at.z) + 0.1
		s.position = at
		s.rotation.y = PI   # 前（紐）を手前（+z）へ
		main.add_child(s)
		placed.append(s)
	var eye := base + Vector3(1.5, 0, 2.6)
	eye.y = main.height(eye.x, eye.z) + 0.1
	p.global_position = eye
	p.rotation.y = atan2(-(base.x + 1.5 - eye.x), -(base.z - eye.z))
	p.set("_pitch", -0.62)
	await _wait(1.5)
	await _shot("01_placed")
	p.global_position = eye + Vector3(-1.0, 0, -1.2)
	p.set("_pitch", -0.95)
	await _wait(0.6)
	await _shot("02_placed_near")
	var r = placed[1].rope
	print("紐: 結び先 ", r._ties, " 引っ張り紐の長さ ", placed[1].ROPE_LEN, " 先（米袋の座標） ", placed[1].to_local(r.end_point()))
	for s in placed:
		s.queue_free()
	# 2. 呼び出して滑る
	c.sacks[who] = SPECS.duplicate(true)
	for i in SPECS.size():
		c.sack_sel[who] = i
		var at := Vector3(3.0 + i * 0.5, 0, 14.0)
		at.y = main.height(at.x, at.z) + 0.2
		p.global_position = at
		p.velocity = Vector3.ZERO
		p.rotation.y = PI
		p.set("_pitch", -0.3)
		await _wait(0.6)
		await _key(KEY_N)
		await _wait(0.1)
		await _shot("%02d_pop_%s" % [3 + i * 2, SPECS[i].fabric if SPECS[i].fabric != "" else "standard"])
		p.set("_pitch", -0.85)   # 乗って滑りながら、足もとの米袋を見る
		await _wait(1.6)
		await _shot("%02d_ride_%s" % [4 + i * 2, SPECS[i].fabric if SPECS[i].fabric != "" else "standard"])
		await _key(KEY_N)
		await _wait(0.6)
	quit()
