extends SceneTree
## 夜目の双眼鏡をのぞいているときの、自分の白い息を確かめる: いちばん寒い夜（2 時）、テラスから丘を夜目でのぞき、
## 息を吐いた瞬間から少しずつ撮る。のぞく前の一人称（息は前のとおり見える）と、のぞき終えたあとも撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/binocular_breath_shots.gd -- --bots=0 --no-sound --no-pip --no-buttons --doll=kasa --dir=/path [--tag=after] [--as-before]
## 絵は <dir>/<tag>_*.png。標準出力に、息の濃さ（doll._cold）と、息の出口が自分のカメラに映るか（層）を出す

const B := preload("res://binoculars.gd")

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
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/binocular_breath")


func _save(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join("%s_%s.png" % [args.get("tag", "before"), name]))


func _click() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	await create_timer(0.1).timeout
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await create_timer(0.2).timeout


func _seen() -> String:
	var shown := 0
	var all := 0
	for key in p.doll._streams:
		all += 1
		if (p.doll._streams[key] as VisualInstance3D).layers & p.cam.cull_mask:
			shown += 1
	return "息の出口 %d 本のうち %d 本が自分のカメラに映る" % [all, shown]


## 息を吐かせて、吐いた瞬間から 3 枚撮る
func _breath_shots(name: String) -> void:
	await create_timer(1.5).timeout
	p.doll._next_breath = p.doll._frame
	for i in 3:
		await create_timer([0.2, 0.25, 0.35][i]).timeout
		await _save("%s_%d" % [name, i + 1])
	print("%s: 息の濃さ %.2f、%s" % [name, p.doll._cold, _seen()])


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	var craft = main.craft
	var st: Node3D = main.binocular_stands[0]
	var lodge: Node3D = main.get_node("Lodge")
	var day = root.get_node("DayCycle")
	day.day_seconds = 1000000.0
	day.hour = 2.0   # いちばん寒い時刻（temperature.gd の _outdoor は 2 時がいちばん低い）
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p.set_third(false)
	craft.wallets[p.id] = 1600
	craft.send({"kind": "buy", "who": p.id, "item": {"kind": "binoculars_night"}})
	await create_timer(0.3).timeout
	# テラスの柵の手前から丘（binoculars_grade_shots.gd と同じ所）
	p.global_position = st.to_global(Vector3(-2.0, 0.1, 0.45))
	await create_timer(0.5).timeout
	var aim: Vector3 = lodge.to_global(Vector3(-10.0, 0, 95.0))
	aim.y = main.height(aim.x, aim.z) + 3.0
	var dir: Vector3 = (aim - p.cam.global_position).normalized()
	p.rotation.y = atan2(-dir.x, -dir.z)
	p._pitch = asin(dir.y)
	await _breath_shots("fp")
	await _click()   # 夜目でのぞく
	await create_timer(0.8).timeout
	print("のぞいている: ", p.peek, " 段 ", p._peek_grade)
	if args.has("as-before"):   # 直す前の見え方: 自分の息を自分の画面に映したまま（前のコードと同じ層）
		p.doll.breath_in_view(true)
	await _breath_shots("night")
	await _click()   # やめる
	await create_timer(0.5).timeout
	await _breath_shots("fp_after")
	quit()
