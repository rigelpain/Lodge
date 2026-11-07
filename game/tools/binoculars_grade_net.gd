extends SceneTree
## 通信の確かめ: つなぐ側が夜目でのぞいても、ホストの画面の明るさ・霧・舞う雪は変わらない。ホストの人形が、つなぐ側の暗視で見えるか。
##   Godot --path game --resolution 1000x640 -s res://tools/binoculars_grade_net.gd -- --host --port=24787 --time=23 --day=1000000 --no-sound --no-pip --no-buttons --bots=0 --doll=kasa --dir=/path
##   Godot --path game --resolution 1000x640 -s res://tools/binoculars_grade_net.gd -- --join=127.0.0.1 --port=24787 --time=23 --day=1000000 --no-sound --no-pip --no-buttons --bots=0 --doll=origami --dir=/path

var args := {}
var main: Node3D
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(_dir())
	(_host if args.has("host") else _join).call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/binoculars_grade_net")


func _check(what: String, ok: bool) -> void:
	print("OK  " if ok else "だめ ", what)
	if not ok:
		fails += 1


func _wait(cond: Callable, limit := 50.0) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return false


func _save(name: String) -> void:
	await create_timer(0.4).timeout
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _env() -> Environment:
	for n in main.get_children():
		if n is WorldEnvironment:
			return n.environment
	return null


func _spot() -> Vector3:
	var at: Vector3 = main.get_node("Lodge").to_global(Vector3(-13.0, 0, 72.0))   # 丘の上。テラスの手すりの上から見通せる
	at.y = main.height(at.x, at.z) + 0.2
	return at


func _host() -> void:
	var env := _env()
	var me: CharacterBody3D = main.player
	me.global_position = _spot()
	await _wait(func() -> bool: return not main.net.remotes.is_empty())
	var r: Node3D = main.net.remotes.values()[0]
	me.global_position = _spot()
	await create_timer(2.0).timeout
	main.craft.send({"kind": "earn", "who": r.id, "n": 1000, "at": r.global_position})   # 夜目を買う分（ホストだけが配れる）
	var fog: float = env.fog_density
	var ex: float = env.tonemap_exposure
	var snow: bool = main.snowfall.visible
	await _save("host_before")
	var ok: bool = await _wait(func() -> bool:
		me.velocity = Vector3.ZERO
		return r.doll.peek == "binoculars_night")
	_check("相手の人形は夜目の双眼鏡を目に当てる", ok)
	await create_timer(1.5).timeout
	_check("相手がのぞいている間、ホストの霧・露出・舞う雪は変わらない", is_equal_approx(env.fog_density, fog) and is_equal_approx(env.tonemap_exposure, ex) and main.snowfall.visible == snow)
	await _save("host_during")
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.cull_mask = (1 << 0) | (1 << 3) | (1 << 7)
	root.add_child(cam)
	cam.current = true
	var h: float = r.doll.eye_point(false).y
	cam.look_at_from_position(r.global_position + r.global_basis * Vector3(0.5, h - 0.1, -1.1), r.global_position + Vector3.UP * (h - 0.05))
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	await _save("host_sees_doll")
	me.cam.make_current()
	await _wait(func() -> bool: return r.doll.peek == "", 20.0)
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)


func _join() -> void:
	await _wait(func() -> bool: return main.net.online and not main.net.remotes.is_empty())
	await create_timer(3.0).timeout
	var p: CharacterBody3D = main.player
	var craft = main.craft
	var st: Node3D = main.binocular_stands[0]
	await _wait(func() -> bool: return craft.wallet(p.id) >= 400, 10.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p.set_third(false)
	p.global_position = st.to_global(Vector3(-2.0, 0.1, 0.45))
	await create_timer(1.0).timeout
	await _ensure_item(craft, p)
	_check("つなぐ側で夜目を買う", p.held().get("kind", "") == "binoculars_night")
	# 相手の人形の方を向く（まず、のぞかずに 1 枚）
	var who: Node3D = main.net.remotes.values()[0]
	print("相手の所: ", who.global_position, " 自分: ", p.global_position)
	var dir: Vector3 = (who.global_position + Vector3.UP * 0.9 - p.cam.global_position).normalized()
	p.rotation.y = atan2(-dir.x, -dir.z)
	p._pitch = asin(dir.y)
	await create_timer(1.0).timeout
	p.cam.fov = 75.0
	await _save("join_before")
	await _click()
	await create_timer(1.0).timeout
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	for i in 6:
		Input.parse_input_event(ev)
	await create_timer(3.0).timeout
	_check("つなぐ側でのぞいている", p.peek == "hand")
	await _save("join_sight")
	await create_timer(4.0).timeout
	await _click()
	await create_timer(1.5).timeout
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)


func _ensure_item(craft: Node, p: Node) -> void:
	craft.send({"kind": "buy", "who": p.id, "item": {"kind": "binoculars_night"}})
	await _wait(func() -> bool: return p.held().get("kind", "") == "binoculars_night", 6.0)


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
