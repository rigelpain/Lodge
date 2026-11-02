extends SceneTree
## 通信の確かめ: ペグ（peg.gd・sled.gd の peg_to）で斜面に留めたソリが、どの画面でも同じ所に止まって見えるか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/peg_net_check.gd -- --host --port=24741 --bots=0 --lodge-bots=0 --no-sound --no-buttons
##   Godot --headless --fixed-fps 60 --path game -s res://tools/peg_net_check.gd -- --join=127.0.0.1 --port=24741 --bots=0 --lodge-bots=0 --no-sound --no-buttons
## つながってから:
##   A  ホストがソリを坂の途中（頂上から 18 m）に置く。つなぐ側がペグを買い、ソリの前に立って刺す（出来事はホストへ）
##   B  両方の画面で 4 秒、ソリの位置とペグの位置を出す（どちらも止まっていて、同じ所のはず）
##   C  ホストがペグを抜く。両方の画面でペグが消え、ソリがずり落ちていく
## --late を両方に付けると: ホストが先に一人でペグを刺しておき、あとからつないだ人の画面にもペグと結んだ紐が出るか

var args := {}
var main: Node3D
var p: CharacterBody3D
var sled: RigidBody3D
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


func _where() -> String:
	var pg := "なし"
	if sled.peg:
		pg = "(%.2f, %.2f, %.2f) 色 %s" % [sled.peg.global_position.x, sled.peg.global_position.y, sled.peg.global_position.z, sled.peg.color.to_html(false)]
	return "ソリ (%.2f, %.2f, %.2f) 速さ %.2f ペグ %s" % [sled.global_position.x, sled.global_position.y, sled.global_position.z, sled.linear_velocity.length(), pg]


func _run() -> void:
	await _wait(0.5)
	if args.has("late"):
		await _late()
		return
	var t := 0.0
	while main.net.remotes.is_empty() and t < 20.0:
		await _wait(0.5)
		t += 0.5
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	_t0 = Time.get_ticks_msec()
	p = main.player
	sled = main.sled
	var host := args.has("host")
	var r := 18.0
	await _wait(1.0)
	# A
	if host:
		sled.reset_to(Vector3(0, main.height(0, r) + 0.3, r))
		sled.parked = true   # 刺すまでは置いたまま（parked: 誰かが触るまでずり落ちない）
		p.global_position = Vector3(4, main.height(4, r - 6) + 0.1, r - 6)
		_say("ソリを置いた: %s" % _where())
	await _wait(2.0)
	if not host:
		_say("買う: %s" % main.craft.send({"kind": "buy", "who": p.id, "item": {"kind": "peg", "n": 3}}))
		await _wait(0.6)
		_say("手に %s" % p.held())
		var a: Vector3 = sled.rope_root()
		p.global_position = Vector3(a.x, main.height(a.x, a.z - 1.0) + 0.05, a.z - 1.0)
		p.rotation.y = PI
		await _wait(0.3)
		_say("刺す所: %s" % str(p.peg_target()))
		_say("刺す: %s" % p.plant_peg())
	await _wait(1.5)
	# B
	for i in 5:
		_say(_where())
		if host and i == 1:
			sled.push(Vector3(0, 0, 1), sled.global_position)   # ホストの画面で押されても（ふもとへ）、紐の届く所までしか行かない
		await _wait(1.0)
	if not host:
		_say("手に %s（1 本減って 2 本のはず）" % p.held())
	# C
	if host:
		p.global_position = sled.peg.global_position + Vector3(0.8, 0.05, 0) if sled.peg else p.global_position
		await _wait(0.3)
		_say("抜く: %s" % p.pull_peg(sled))
	else:
		await _wait(0.3)
	await _wait(1.0)
	for i in 3:
		_say(_where())
		await _wait(1.0)
	await _wait(1.0)
	quit()


func _late() -> void:
	p = main.player
	sled = main.sled
	if args.has("host"):
		await _wait(1.5)
		sled.reset_to(Vector3(0, main.height(0, 18.0) + 0.3, 18.0))
		main.craft.send({"kind": "buy", "who": p.id, "item": {"kind": "peg", "n": 3}})
		var a: Vector3 = sled.rope_root()
		p.global_position = Vector3(a.x, main.height(a.x, a.z - 1.0) + 0.05, a.z - 1.0)
		p.rotation.y = PI
		await _wait(0.2)
		_say("一人で刺す: %s" % p.plant_peg())
		while main.net.remotes.is_empty():
			await _wait(0.5)
		await _wait(3.0)
		_say(_where())
	else:
		while not main.net.joined():
			await _wait(0.5)
		await _wait(3.0)
		var tied: bool = sled.peg != null and sled.rope.end_point().distance_to(sled.peg.tie_point()) < 0.05
		_say("あとから来た: %s 紐の先がペグに %s" % [_where(), tied])
	await _wait(1.0)
	quit()
