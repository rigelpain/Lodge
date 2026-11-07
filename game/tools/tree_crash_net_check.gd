extends SceneTree
## 通信の確かめ: 木にぶつかったソリから放り投げられるのが、ホストとつなぐ側で同じに見えるか（数字だけ出す）。
##   Godot --headless --path game -s res://tools/tree_crash_net_check.gd -- --host --port=24756 --bots=1 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons
##   Godot --headless --path game -s res://tools/tree_crash_net_check.gd -- --join=127.0.0.1 --port=24756 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons
## ホストの人・つなぐ人・仲間の 3 人が丘の木の手前で同じソリに乗り、ホストのソリが 12 m/s で幹へ向かう。
## 見ること: 3 人分の出来事が両方の画面に同じ値で届く。自分の画面の体が配られた向きへ飛ぶ。つなぐ側の仲間とホストの人、ホストのつなぐ人の人形も飛ぶ段を通る。
## 終わりに、3 人の位置を両方の画面で並べて出す（2 つの画面の時計は合わないので、起き上がったあとの止まった位置で比べる）。

var args := {}
var main: Node3D
var host := false
var fails := 0
var _got := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	host = args.has("host")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s] %s" % ["host" if host else "join", s])


func _check(ok: bool, s: String) -> void:
	_say(("○ " if ok else "× ") + s)
	if not ok:
		fails += 1


func _tree() -> Node3D:
	var best: Node3D
	var low := INF
	for n in main.get_children():
		if String(n.scene_file_path).get_file().begins_with("tree_"):
			var g := Vector2(main.height(n.position.x + 1.0, n.position.z) - main.height(n.position.x - 1.0, n.position.z), main.height(n.position.x, n.position.z + 1.0) - main.height(n.position.x, n.position.z - 1.0))
			if g.length() < low and n.scale.x > 1.0:
				low = g.length()
				best = n
	return best


func _run() -> void:
	await create_timer(0.5).timeout
	var p: CharacterBody3D = main.player
	var s: RigidBody3D = main.sled
	var t0 := 0.0
	while main.net.remotes.is_empty() and t0 < 30.0:
		await create_timer(0.25).timeout
		t0 += 0.25
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	main.emotes.happened.connect(func(ev):
		if ev.kind == "flung" and ev.get("thrown", false):
			_got.append(ev))
	# 同じ Mac の時計で、次の 10 秒の区切りの 10 秒後に始める
	var now := Time.get_unix_time_from_system()
	await create_timer(ceilf(now / 10.0) * 10.0 + 10.0 - now).timeout
	var t := _tree()
	var o := Vector2(t.position.x, t.position.z)
	var dir := Vector2(1, 0)
	var a: Vector2 = o - dir * (float(s.HALF.y) + 6.0)
	if host:
		s.let_everyone_go()
		s.reset_to(Vector3(a.x, main.height(a.x, a.y) + 0.3, a.y))
		s.global_basis = Basis(Vector3.UP, atan2(-dir.x, -dir.y))
		s.parked = false
	await create_timer(1.5).timeout   # つなぐ側のソリが着くまで
	p.global_position = s.global_position + s.global_basis.x * 1.2
	p.sled = s
	p.get_on()
	_check(p.mode == p.Mode.RIDE, "自分がソリに乗った")
	var bot: Node = null
	if host:
		bot = get_nodes_in_group("bots")[0]
		bot.global_position = s.global_position - s.global_basis.x * 1.2
		bot.sled = s
		bot.seat = s.mount(bot)
		bot._col.disabled = true
		bot.state = bot.State.RIDE
		bot._ride_goal = o + dir * 200.0
		bot._ride_t = 0.0
		bot._still = 0.0
		bot._goal_best = INF
		bot._goal_t = 0.0
	await create_timer(1.0).timeout
	if host:
		_check(s.riders.size() == 3, "ホストのソリに 3 人（%d）" % s.riders.size())
		s.linear_velocity = Vector3(dir.x, 0, dir.y) * 12.0
	var others: Array = main.net.remotes.values() + main.net.cpus.values()
	var seen := {}
	var from := p.global_position
	var far_at := Vector3.ZERO
	var t1 := 0.0
	while t1 < 8.0:
		await physics_frame
		t1 += 1.0 / 60.0
		for w in [p] + others + ([bot] if bot else []):
			var st: int = w.doll.flung
			var l: Array = seen.get_or_add(w, [])
			if l.is_empty() or l[-1] != st:
				l.append(st)
	_check(_got.size() == 3, "出来事 3 人分が届いた（%d）" % _got.size())
	var lines := []
	var ids := []
	for ev in _got:
		ids.append(int(ev.who))
		lines.append("who=%d dir=(%.3f, %.3f) out=%.2f up=%.2f" % [ev.who, ev.dir.x, ev.dir.z, ev.out, ev.up])
	lines.sort()
	_say("配られた値: " + " / ".join(lines))
	for w in seen:
		var name: String = "自分" if w == p else ("仲間" if w == bot else "ほかの人 %d" % w.peer)
		_check(seen[w].has(1) and seen[w].has(2), "%s の人形が飛んで倒れる段を通った: %s" % [name, str(seen[w])])
	if p.id in ids:
		var mine: Dictionary = _got[ids.find(p.id)]
		var moved := p.global_position - from
		moved.y = 0.0
		var apart := rad_to_deg(moved.normalized().angle_to(mine.dir))
		_check(apart < 25.0, "自分の体は配られた向きへ飛んだ（ずれ %.0f°、%.1f m）" % [apart, moved.length()])
	await create_timer(1.0).timeout
	var at := ["自分 %d (%.1f, %.1f)" % [p.id, p.global_position.x, p.global_position.z]]
	for w in others:
		at.append("%d (%.1f, %.1f)" % [w.peer, w.global_position.x, w.global_position.z])
	if bot:
		at.append("仲間 %d (%.1f, %.1f)" % [bot.id, bot.global_position.x, bot.global_position.z])
	_say("止まった位置: " + "、".join(at))
	_say("だめだった数: %d" % fails)
	await create_timer(2.0).timeout
	quit(1 if fails > 0 else 0)
