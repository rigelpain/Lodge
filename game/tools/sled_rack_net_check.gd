extends SceneTree
## 通信の確かめ: つなぐ側の人が自分のソリを立てかけ台へ戻し、持ち出す（数字だけ出す。F は本物のキーの出来事で押す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_rack_net_check.gd -- --host --port=24751 --bots=0 --lodge-bots=0 --no-sound --no-buttons
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_rack_net_check.gd -- --join=127.0.0.1 --port=24751 --bots=0 --lodge-bots=0 --no-sound --no-buttons
## A ホストがつなぐ側の人のソリを山に出す。B ホストの人がつかんでいる間は、つなぐ側の F は断られる。
## C 手を離すと戻せる（両方の画面で台に立てかかる）。D つなぐ側の F で持ち出す（両方の画面で雪の上）

var args := {}
var main: Node3D
var p: CharacterBody3D
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s %.1f] %s" % ["host" if args.has("host") else "join", (Time.get_ticks_msec() - _t0) / 1000.0, s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _press_f() -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_F
	e.pressed = true
	p._unhandled_input(e)


func _where(s: RigidBody3D) -> String:
	return "立てかけ %s 止め %s 台の記録 %s 位置 (%.2f, %.2f, %.2f) 上向き %.2f 見える %s" % [s.racked, s.freeze, main.craft.racked.keys(), s.global_position.x, s.global_position.y, s.global_position.z, s.global_basis.y.y, s.visible]


func _run() -> void:
	await _wait(0.5)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	_t0 = Time.get_ticks_msec()
	p = main.player
	var craft = main.craft
	var host := args.has("host")
	await _wait(1.0)
	var lodge: Node3D = main.get_node("Lodge")
	var far: Vector3 = lodge.to_global(Vector3(-18.0, 0, 40.0))
	far.y = main.height(far.x, far.z) + 0.3
	if host:
		var who: int = main.net.remotes.keys()[0]
		craft.send({"kind": "sewn", "who": who, "sled": "mid", "fabric": "red", "at": far, "yaw": 0.0})
	await _wait(1.0)
	var id: int = craft.sleds.keys()[0]
	var s: RigidBody3D = craft.sleds[id]
	_say("A ソリ %d 持ち主 %d（自分 %d）: %s" % [id, s.owner_id, p.id, _where(s)])
	var rack: Node3D = main.sled_rack
	var front: Vector3 = rack.to_global(Vector3(-3.0, 0.1, 2.9))
	if host:
		s.take_handle(p, Vector3(0, 0, 1.0))   # B: ホストの人がつかむ
		_say("B つかんだ")
	else:
		p.global_position = front
		p.global_rotation.y = rack.global_rotation.y   # 台の方（-Z）を向く
	await _wait(1.0)
	if not host:
		_say("B F の案内 %s 呼べない %s" % [p.rack_target(), p.rack_refused()])
		_press_f()   # 画面にはまだ届いていない手の分もあるので、ホストが断る
		craft.send({"kind": "rack_in", "who": p.id, "id": id})
	await _wait(1.5)
	_say("B つかんでいる間: %s" % _where(s))
	await _wait(1.5)   # 2 つの画面の時計のずれを見込んで、長めにつかんでおく
	if host:
		s.release_handle(p)
		_say("C 離した")
	await _wait(2.5)
	if not host:
		_say("C F の案内 %s" % str(p.rack_target()))
		_press_f()
	await _wait(2.5)
	_say("C 戻した後: %s" % _where(s))
	if not host:
		p.global_rotation.y = atan2(-(s.global_position.x - p.global_position.x), -(s.global_position.z - p.global_position.z))
		await _wait(0.2)
		_say("D F の案内 %s" % str(p.rack_target()))
		_press_f()
	await _wait(2.0)
	_say("D 持ち出した後: %s" % _where(s))
	await _wait(1.0)
	_say("D もう少しあと: %s" % _where(s))
	quit()
