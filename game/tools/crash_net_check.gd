extends SceneTree
## 通信の確かめ: つなぐ側の人が乗ったソリが雪の塊に当たると、ホストの画面でも、つなぐ側の画面でも、ソリが打ち上がり、人が飛ぶか（数字だけ出す）。
##   Godot --headless --path game -s res://tools/crash_net_check.gd -- --host --port=24733 --sled=mid --no-sound --roam-bots=0 --lodge-bots=0
##   Godot --headless --path game -s res://tools/crash_net_check.gd -- --join=127.0.0.1 --port=24733 --sled=mid --no-sound --roam-bots=0 --lodge-bots=0

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s] %s" % ["ホスト" if args.has("host") else "つなぐ側", s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _run() -> void:
	await _wait(1.0)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	_say("相手が見えた" if not main.net.remotes.is_empty() else "相手が来なかった")
	await _wait(2.0)
	var sled: RigidBody3D = main.sled
	var p: Node3D = main.player
	var lump: Node3D = get_nodes_in_group("crash_lumps")[6]
	var at := lump.global_position
	var dir := (Vector2(main.LODGE_POS.x, main.LODGE_POS.y) - Vector2(at.x, at.z)).normalized()
	var from := Vector2(at.x, at.z) - dir * 12.0
	if args.has("host"):
		sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
		sled.rotation.y = atan2(-dir.x, -dir.y)
		sled.parked = false
	await _wait(2.0)
	if args.has("join"):
		p.global_position = sled.global_position + Vector3.UP
		p.get_on()
		_say("乗った: %s" % str(p.mode == p.Mode.RIDE))
	if args.has("host"):
		t = 0.0
		while sled.riders.is_empty() and t < 20.0:   # つなぐ側の人が乗ったのが届くまで
			await _wait(0.2)
			t += 0.2
		await _wait(0.5)
		_say("乗っている人 %d" % sled.riders.size())
		sled.linear_velocity = Vector3(dir.x, 0, dir.y) * 8.0
	var top := 0.0
	var seen := false
	var flew := false
	var man := 0.0
	var other: Node3D = null
	for r in main.net.remotes.values():
		other = r
	t = 0.0
	while t < 22.0:
		await physics_frame
		t += get_root().get_physics_process_delta_time()
		var q: Vector3 = sled.global_position
		top = maxf(top, q.y - main.height(q.x, q.z))
		seen = seen or sled.crashed
		if args.has("join"):
			flew = flew or p.fling.active()
			man = maxf(man, p.global_position.y - main.height(p.global_position.x, p.global_position.z))
		elif other:
			man = maxf(man, other.global_position.y - main.height(other.global_position.x, other.global_position.z))
			flew = flew or int(other.doll.flung) != 0
	var q: Vector3 = sled.global_position
	_say("打ち上がったのを見た %s、ソリの高さ %.1f m、人の高さ %.1f m、人が飛んだ %s、残って乗っている人 %d、ソリの所 (%.2f, %.2f)" % [str(seen), top, man, str(flew), sled.riders.size(), q.x, q.z])
	await _wait(1.0)
	quit()
