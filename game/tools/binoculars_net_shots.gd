extends SceneTree
## 通信の確かめ: つなぐ側の人が双眼鏡をのぞいている姿を、ホストの画面で撮る（台と手の双眼鏡を 1 回ずつ）。ホストを先に起動する。
##   Godot --path game --resolution 1000x640 -s res://tools/binoculars_net_shots.gd -- --host --port=24781 --no-sound --no-pip --no-buttons --bots=0 --dir=/path/shots
##   Godot --path game --resolution 1000x640 -s res://tools/binoculars_net_shots.gd -- --join=127.0.0.1 --port=24781 --no-sound --no-pip --no-buttons --bots=0 --dir=/path/shots

var args := {}
var main: Node3D
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	(_host if args.has("host") else _join).call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/binoculars_net")


func _check(what: String, ok: bool) -> void:
	print("OK  " if ok else "だめ ", what)
	if not ok:
		fails += 1


func _wait(cond: Callable, limit := 40.0) -> bool:
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
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _remote() -> Node3D:
	var net = main.net
	for r in net.remotes.values():
		return r
	return null


func _host() -> void:
	var st: Node3D = main.binocular_stands[0]
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.cull_mask = (1 << 0) | (1 << 3) | (1 << 7)
	root.add_child(cam)
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var ok: bool = await _wait(func() -> bool: return int(st.who) >= 0)
	_check("ホストの画面でも台はふさがる", ok)
	await create_timer(2.0).timeout
	cam.current = true
	cam.look_at_from_position(st.to_global(Vector3(-1.9, 0.95, 1.5)), st.to_global(Vector3(0, 0.85, 0.2)))
	var r := _remote()
	_check("相手の人形は台をのぞく姿", r != null and r.doll.peek == "stand")
	print("相手の人形 ", r.doll.kind, " の目の高さ ", r.doll.eye_point(false).y, "（台の頭 ", st.HEAD_Y, "）")
	for k in ["kasa", "origami", "news", "robo", "musha", "ningyo", "golem"]:
		print("  EYE ", k, " ", r.doll.EYE[k].y)
	await _save("host_sees_stand")
	main.craft.send({"kind": "earn", "who": r.id, "n": 40, "at": r.global_position})   # 手の双眼鏡を買う分
	# 別の台は同時に使える。同じ台は使えない
	var me: CharacterBody3D = main.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	me.global_position = st.to_global(Vector3(0, 0.1, 1.3))
	me.rotation.y = st.global_rotation.y
	await create_timer(0.5).timeout
	_check("相手がのぞいている台は、F の相手にならない", me.binocular_near() == null)
	var st2: Node3D = main.binocular_stands[1]
	me.global_position = st2.to_global(Vector3(0, 0.1, 1.3))
	me.rotation.y = st2.global_rotation.y
	await create_timer(0.5).timeout
	await _key(KEY_F)
	await create_timer(0.3).timeout
	_check("別の台は別の人が同時に使える", me.peek == "stand" and int(st2.who) == me.id and int(st.who) == r.id)
	await _key(KEY_F)
	_check("別の台をやめても、相手の台はふさがったまま", me.peek == "" and int(st2.who) < 0 and int(st.who) == r.id)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ok = await _wait(func() -> bool: return r != null and r.doll.peek == "binoculars")
	_check("相手の人形は手の双眼鏡を目に当てる", ok)
	await create_timer(3.0).timeout   # 相手が指を離したあとも続いている
	_check("相手が指を離したあとも、目に当てたまま", r.doll.peek == "binoculars")
	var eye_h: float = r.doll.eye_point(false).y
	cam.look_at_from_position(r.global_position + r.global_basis * Vector3(0.55, eye_h - 0.12, -1.15), r.global_position + Vector3.UP * (eye_h - 0.05))
	await _save("host_sees_hand")
	ok = await _wait(func() -> bool: return r.doll.peek == "" and int(st.who) < 0)
	_check("やめると戻り、台は空く", ok)
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await create_timer(0.3).timeout


func _join() -> void:
	await create_timer(1.0).timeout
	await _wait(func() -> bool: return main.net.online and not main.net.remotes.is_empty())
	await create_timer(3.0).timeout
	var p: CharacterBody3D = main.player
	var st: Node3D = main.binocular_stands[0]
	var craft = main.craft
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p.global_position = st.to_global(Vector3(0, 0.1, 1.2))
	p.rotation.y = st.global_rotation.y
	await create_timer(0.8).timeout
	await _key(KEY_F)
	var ok: bool = await _wait(func() -> bool: return p.peek == "stand", 5.0)
	_check("つなぐ側で F を押すと、ホストが確かめて開く", ok)
	await create_timer(6.0).timeout
	p.rotation.y = st.global_rotation.y + 0.5
	await _save("join_peek_stand")
	await _key(KEY_F)
	_check("F でやめる", p.peek == "")
	await create_timer(1.5).timeout   # ホストの撮影とボタンの配りを待つ
	var money_before: int = craft.wallet(p.id)
	craft.send({"kind": "buy", "who": p.id, "item": preload("res://binoculars.gd").ITEM.duplicate()})
	ok = await _wait(func() -> bool: return p.held().get("kind", "") == "binoculars", 5.0)
	_check("つなぐ側で山男の棚の品を買って手に持つ", ok and p.held().get("kind", "") == "binoculars")
	p.global_position = st.to_global(Vector3(-3.0, 0.1, 2.5))   # 台から離れた所で
	p.rotation.y = st.global_rotation.y
	await create_timer(0.8).timeout
	await _click()
	await create_timer(6.0).timeout
	_check("つなぐ側で 1 回押して離しても、のぞいたまま", p.peek == "hand")
	await _click()
	_check("もう 1 回押すとやめる", p.peek == "")
	await create_timer(3.0).timeout
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)


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
