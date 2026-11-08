extends SceneTree
## 通信の確かめ: 転がす大玉の耐久（big_ball.gd の hurt・show_hurt・crumble）。数字だけ出す。ホストを先に起動する。
##   Godot --headless --path game -s res://tools/big_ball_wear_net_check.gd -- --host --port=24782 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   Godot --headless --path game -s res://tools/big_ball_wear_net_check.gd -- --join=127.0.0.1 --port=24782 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
## 流れ: ホストが高台の平らな所に半径 1 m の大玉を置く → 雪玉を 3 個当てる → ソリを 6 m/s でぶつける → 崩れるまで雪玉を当てる。
## 両方の画面で、減った割合（wear_k）・へこみの数・はじけた縫い目の数が変わるたびに出し、崩れたら両方の画面から玉が消えて、雪のかたまりが飛ぶか見る。

const BigBall := preload("res://big_ball.gd")
const SPOT := Vector2(40.0, 100.0)   # くぼみの外の高台（平ら）

var args := {}
var main: Node3D
var p: CharacterBody3D
var fails := 0
var _t0 := 0
var _seen := ""


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


func _ball() -> RigidBody3D:
	for b in root.get_tree().get_nodes_in_group("big_balls"):
		if not b.broken:
			return b
	return null


## 玉の減りの見た目（変わったときだけ出す）
func _watch(b) -> void:
	if b == null or not is_instance_valid(b):
		return
	var torn := 0
	for st in b._stitches:
		if not (st[0] as Node3D).visible:
			torn += 1
	var s := "減った割合 %.3f　へこみ %d　はじけた縫い目 %d" % [b.wear_k, b._dents.size(), torn]
	if s != _seen:
		_seen = s
		_say("  " + s)


func _flyers() -> int:
	var n := 0
	for c in main.get_children():
		if c is BigBall.Flyer:
			n += 1
	return n


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


func _wait_watch(b, t: float) -> void:
	var n := int(t * 60.0)
	for i in n:
		await physics_frame
		_watch(b)


func _snow_at(b: RigidBody3D, k: int) -> void:
	var at: Vector3 = b.global_position + Vector3(0.0, 0.2, 4.0)
	main.emotes._spawn_ball({"who": p.id, "ball": 7000 + k, "origin": at, "velocity": (b.global_position - at).normalized() * 12.0})


func _host_run() -> void:
	var g: float = main.height(SPOT.x, SPOT.y)
	p.global_position = Vector3(SPOT.x - 6.0, g + 0.5, SPOT.y + 12.0)
	_ok(await _until(func(): return not main.net.remotes.is_empty(), 20.0), "つなぐ側が来た")
	await create_timer(2.0).timeout
	main.emotes.balls[p.id] = 1
	main.emotes.send({"kind": "roll_seed", "who": p.id, "point": Vector3(SPOT.x, g, SPOT.y), "r": 1.0})
	var b := _ball()
	_ok(b != null, "大玉を置いた")
	if b == null:
		return
	_say("耐えられる量 %.1f" % b.max_wear())
	await _wait_watch(b, 2.0)
	_say("雪玉を 3 個")
	for k in 3:
		_snow_at(b, k)
		await _wait_watch(b, 0.5)
	await _wait_watch(b, 1.0)
	_ok(absf(b.wear - 3.0 * BigBall.SNOW_HIT) < 0.01, "雪玉 3 個で %.1f 減った（%.1f）" % [3.0 * BigBall.SNOW_HIT, b.wear])
	_say("ソリを 6 m/s で")
	var sled: RigidBody3D = main.sled
	var from := Vector2(b.global_position.x - (b.r + sled.HALF.y + 1.0), b.global_position.z)
	sled.crashed = false
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	sled.rotation.y = atan2(-1.0, 0.0)
	sled.parked = false
	await _wait_watch(b, 0.4)
	var w0: float = b.wear
	sled.linear_velocity = Vector3(6.0, 0, 0)
	await _wait_watch(b, 2.0)
	_ok(b.wear - w0 > 1.0, "ソリで %.1f 減った" % (b.wear - w0))
	sled.reset_to(Vector3(0, main.height(0, 38) + 0.3, 38))
	_say("崩れるまで雪玉を")
	var n := 0
	while n < 30 and is_instance_valid(b) and not b.broken:
		n += 1
		_snow_at(b, 10 + n)
		await _wait_watch(b, 0.45)
	_ok(not is_instance_valid(b) or b.broken, "雪玉 %d 個めで崩れた" % n)
	await create_timer(0.3).timeout
	_ok(_flyers() > 5, "雪のかたまりが飛び散る（%d）" % _flyers())
	await create_timer(4.0).timeout


func _join_run() -> void:
	_ok(await _until(func(): return main.net.joined(), 20.0), "ホストにつながった")
	_ok(await _until(func(): return _ball() != null, 30.0), "ホストが置いた大玉が、つなぐ側にも生まれる")
	var b := _ball()
	if b == null:
		return
	_ok(b.net_follow, "つなぐ側の大玉は、ホストの姿を写す")
	var t := 0.0
	while is_instance_valid(b) and not b.broken and t < 40.0:
		await physics_frame
		t += 1.0 / 60.0
		_watch(b)
	_ok(not is_instance_valid(b) or b.broken, "ホストで崩れると、つなぐ側の大玉も崩れる")
	await create_timer(0.3).timeout
	_ok(_flyers() > 5, "つなぐ側でも雪のかたまりが飛び散る（%d）" % _flyers())
	_ok(_ball() == null, "つなぐ側の大玉は消える")
	await create_timer(3.0).timeout
