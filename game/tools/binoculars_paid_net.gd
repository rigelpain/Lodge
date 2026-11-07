extends SceneTree
## 通信の確かめ: つなぐ側が台で払う → やめる → のぞき直しても、つなぐ側でもホストの持つ財布でも二重に減らない。同じ台を別の人（ホスト）は自分で払って使える。60 秒すぎると、また払う。約 75 秒かかる。
##   Godot --path game --resolution 1000x640 -s res://tools/binoculars_paid_net.gd -- --host --port=24797 --no-sound --no-pip --no-buttons --bots=0 --dir=/path
##   Godot --path game --resolution 1000x640 -s res://tools/binoculars_paid_net.gd -- --join=127.0.0.1 --port=24797 --no-sound --no-pip --no-buttons --bots=0 --dir=/path

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
	(_host if args.has("host") else _join).call_deferred()


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


func _before(p: CharacterBody3D, st: Node3D) -> void:
	p.global_position = st.to_global(Vector3(0, 0.1, 1.3))
	p.rotation.y = st.global_rotation.y
	p.velocity = Vector3.ZERO
	await create_timer(0.6).timeout


func _host() -> void:
	var craft = main.craft
	var st: Node3D = main.binocular_stands[0]
	var me: CharacterBody3D = main.player
	await _wait(func() -> bool: return not main.net.remotes.is_empty())
	var r: Node3D = main.net.remotes.values()[0]
	await _wait(func() -> bool: return int(st.who) == r.id)   # 相手が払った
	var w0: int = craft.wallet(r.id)
	await _wait(func() -> bool: return int(st.who) < 0)        # やめた
	# 同じ台を別の人が使う: ホストは自分で払う
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	main.emotes._set_balls(me.id, 0)
	var mine: int = craft.wallet(me.id)
	await _before(me, st)
	_check("相手の払った時間は、ほかの人には効かない", me.binocular_pay() == "button")
	await _key(KEY_F)
	_check("ホストは自分で払う", me.peek == "stand" and craft.wallet(me.id) == mine - 1)
	await create_timer(1.0).timeout
	await _key(KEY_F)
	me.global_position = st.to_global(Vector3(4, 0.1, 3.0))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(func() -> bool: return int(st.who) == r.id)    # 相手がのぞき直した
	await create_timer(0.5).timeout
	_check("相手がのぞき直しても、ホストの持つ財布は減らない", craft.wallet(r.id) == w0)
	await _wait(func() -> bool: return craft.wallet(r.id) == w0 - 1, 70.0)   # 60 秒すぎて払い直した
	_check("60 秒すぎて、相手はまた 1 枚だけ払う", craft.wallet(r.id) == w0 - 1)
	await create_timer(2.0).timeout
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)


func _join() -> void:
	await _wait(func() -> bool: return main.net.online and not main.net.remotes.is_empty())
	await create_timer(3.0).timeout
	var p: CharacterBody3D = main.player
	var craft = main.craft
	var st: Node3D = main.binocular_stands[0]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p.set_third(false)
	main.emotes.balls[p.id] = 0
	var w0: int = craft.wallet(p.id)
	await _before(p, st)
	await _key(KEY_F)
	var ok: bool = await _wait(func() -> bool: return p.peek == "stand", 5.0)
	var t0 := Time.get_ticks_msec()
	_check("つなぐ側で払ってのぞく", ok and craft.wallet(p.id) == w0 - 1)
	await create_timer(2.0).timeout
	await _key(KEY_F)
	_check("やめる", p.peek == "")
	p.global_position = st.to_global(Vector3(-4, 0.1, 3.0))
	await _wait(func() -> bool: return int(st.who) >= 0, 10.0)   # ホストが同じ台を使う
	await _wait(func() -> bool: return int(st.who) < 0, 10.0)
	await create_timer(0.5).timeout
	await _before(p, st)
	_check("つなぐ側の案内も払いなし", p.binocular_pay() == "free")
	await _key(KEY_F)
	ok = await _wait(func() -> bool: return p.peek == "stand", 5.0)
	_check("のぞき直しても、つなぐ側の財布は減らない", ok and craft.wallet(p.id) == w0 - 1)
	_check("残りはその残りから続く", p._peek_left < 58.0 and p._peek_left > 30.0)
	await create_timer(1.0).timeout
	await _key(KEY_F)
	while Time.get_ticks_msec() - t0 < 61500:
		await create_timer(0.5).timeout
	await _before(p, st)
	_check("60 秒すぎると、つなぐ側の案内は払う形", p.binocular_pay() in ["button", "ball", "none"])
	await _key(KEY_F)
	ok = await _wait(func() -> bool: return p.peek == "stand", 5.0)
	_check("また 1 枚だけ払う", ok and craft.wallet(p.id) == w0 - 2)
	await create_timer(1.0).timeout
	await _key(KEY_F)
	await create_timer(1.0).timeout
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)
