extends SceneTree
## 通信の確かめ: ぶつかられた大玉が動く（big_ball.gd の knock・bump、emotes.gd の ball_bump）。数字だけ出す。ホストを先に起動する。
##   Godot --headless --path game -s res://tools/big_ball_knock_net_check.gd -- --host --port=24784 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   Godot --headless --path game -s res://tools/big_ball_knock_net_check.gd -- --join=127.0.0.1 --port=24784 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
## 流れ: ホストが高台の平らな所に半径 0.5 m の大玉を置く → つなぐ側の人（手袋なし）が走って当たる → ホストの玉が動き、つなぐ側の玉も同じ所へ →
## ホストがソリを 6 m/s で当てる → また両方の玉が同じ所へ。止まった所を両方の画面で出す

const SPOT := Vector2(40.0, 100.0)

var args := {}
var main: Node3D
var p: CharacterBody3D
var fails := 0
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _host() -> bool:
	return args.has("host")


func _say(t: String) -> void:
	print("[%s %.1f] %s" % ["host" if _host() else "join", (Time.get_ticks_msec() - _t0) / 1000.0, t])


func _ok(c: bool, what: String) -> void:
	_say(("○ " if c else "× ") + what)
	if not c:
		fails += 1


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		if t > limit:
			return false
		await physics_frame
		t += 1.0 / 60.0
	return true


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


func _ball() -> RigidBody3D:
	for b in root.get_tree().get_nodes_in_group("big_balls"):
		if not b.broken:
			return b
	return null


func _flat(v: Vector3) -> String:
	return "(%.2f, %.2f)" % [v.x - SPOT.x, v.z - SPOT.y]


func _run() -> void:
	await create_timer(0.5).timeout
	p = main.player
	if _host():
		await _host_run()
	else:
		await _join_run()
	_say("だめだった数: %d" % fails)
	await create_timer(1.0).timeout
	quit(1 if fails > 0 else 0)


func _host_run() -> void:
	var g: float = main.height(SPOT.x, SPOT.y)
	p.global_position = Vector3(SPOT.x + 6.0, g + 0.5, SPOT.y + 12.0)
	_ok(await _until(func(): return not main.net.remotes.is_empty(), 20.0), "つなぐ側が来た")
	await create_timer(2.0).timeout
	main.emotes.balls[p.id] = 1
	main.emotes.send({"kind": "roll_seed", "who": p.id, "point": Vector3(SPOT.x, g, SPOT.y), "r": 0.5})
	var b := _ball()
	_ok(b != null, "大玉を置いた")
	if b == null:
		return
	var at0 := b.global_position
	_ok(await _until(func(): return Vector2(b.global_position.x - at0.x, b.global_position.z - at0.z).length() > 0.2, 15.0), "つなぐ側の人が走って当たると、ホストの玉が動く")
	await create_timer(4.0).timeout
	_say("人のあと、止まった所 %s" % _flat(b.global_position))
	# ソリを 6 m/s で（-x 側から +x へ）
	var sled: RigidBody3D = main.sled
	var bp := b.global_position
	var from := Vector2(bp.x - (b.r + sled.HALF.y + 1.0), bp.z)
	sled.crashed = false
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	sled.rotation.y = atan2(-1.0, 0.0)
	sled.parked = false
	await create_timer(0.4).timeout
	var at1 := b.global_position
	sled.linear_velocity = Vector3(6.0, 0, 0)
	await create_timer(5.0).timeout
	var moved := Vector2(b.global_position.x - at1.x, b.global_position.z - at1.z).length()
	_ok(moved > 0.5, "ソリに当てられて動いた（%.1f m）" % moved)
	_say("ソリのあと、止まった所 %s" % _flat(b.global_position))
	sled.reset_to(Vector3(0, main.height(0, 38) + 0.3, 38))
	await create_timer(3.0).timeout


func _join_run() -> void:
	_ok(await _until(func(): return main.net.joined(), 20.0), "ホストにつながった")
	main.craft.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": -1})   # 手袋を外す（はめていると、押すになる）
	_ok(await _until(func(): return not p.gloves_on(), 5.0), "手袋をはめていない")
	_ok(await _until(func(): return _ball() != null, 30.0), "ホストが置いた大玉が、つなぐ側にも生まれる")
	var b := _ball()
	if b == null:
		return
	await create_timer(0.8).timeout
	var at0 := b.global_position
	p.global_position = at0 + Vector3(-(b.r + 3.2), 0.1, 0.0)
	p.velocity = Vector3.ZERO
	p.rotation.y = -PI * 0.5   # +x を向く
	p.reset_physics_interpolation()
	await create_timer(0.3).timeout
	await _key(KEY_SHIFT, true)
	await _key(KEY_W, true)
	var t := 0.0
	while t < 2.0 and Vector2(b.global_position.x - at0.x, b.global_position.z - at0.z).length() < 0.05:
		await physics_frame
		t += 1.0 / 60.0
	await _key(KEY_W, false)
	await _key(KEY_SHIFT, false)
	p.global_position = at0 + Vector3(0.0, 0.5, 8.0)   # 玉の行く手からどく
	p.reset_physics_interpolation()
	_ok(await _until(func(): return Vector2(b.global_position.x - at0.x, b.global_position.z - at0.z).length() > 0.2, 5.0), "走って当たると、つなぐ側の玉も動く（ホストの玉の姿が届く）")
	await create_timer(3.5).timeout
	_say("人のあと、止まった所 %s" % _flat(b.global_position))
	var at1 := b.global_position
	_ok(await _until(func(): return Vector2(b.global_position.x - at1.x, b.global_position.z - at1.z).length() > 0.5, 15.0), "ホストのソリに当てられて、つなぐ側の玉も動く")
	await create_timer(5.0).timeout
	_say("ソリのあと、止まった所 %s" % _flat(b.global_position))
