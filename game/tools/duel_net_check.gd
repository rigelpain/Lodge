extends SceneTree
## 通信の確かめ: 雪合戦の対決が、ホストとつなぐ側の画面で同じになるか（数字だけ出す）。ホストを先に起動する。
## 段取りは実時間で進めるので、--fixed-fps は付けない（ゲームの時間が先へ進んで、インターバルや制限時間が合わなくなる）。
##   Godot --headless --path game -s res://tools/duel_net_check.gd -- --host --port=24731 --no-sound --bots=0 --lodge-bots=0
##   Godot --headless --path game -s res://tools/duel_net_check.gd -- --join=127.0.0.1 --port=24731 --no-sound --bots=0 --lodge-bots=0
## 窓を出して --dir=/path/shots を足すと、勝敗・握手の案内・払ったあとをそれぞれの画面で撮る（--headless を外す）。
## 握手 → つなぐ側が掛金 20 を出し、ホストが受ける → 戦い: つなぐ側が 1 発（続けて投げても 2 発目は出ない）、ホストが 2 発当てる → ホストの雪玉をつなぐ側が取る →
## （両方の画面に紙吹雪）→ ホストが 3 発目 → 2 人で握手して払う。1 秒ごとに両方の画面の対決（段・当てた数・残りの秒・雪玉・財布）を出す

const Snowball := preload("res://snowball.gd")
const Duel := preload("res://duel.gd")
const AT := Vector3(14, 0, 16)

var args := {}
var main: Node3D
var _t0 := 0
var _fight_t := -1.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _host() -> bool:
	return args.has("host")


func _say(s: String) -> void:
	print("[%s %.1f] %s" % ["host" if _host() else "join", (Time.get_ticks_msec() - _t0) / 1000.0, s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _place(p: Node3D, at: Vector3, look: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.15
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))


func _throw(a: Node3D, b: Node3D) -> void:
	var origin := a.global_position + Vector3.UP * 1.4 + (b.global_position - a.global_position).normalized() * 0.5
	var target := b.global_position + Vector3.UP * 1.0
	var flat := target - origin
	flat.y = 0
	var t := flat.length() / 12.0
	var vel := flat.normalized() * 12.0 + Vector3.UP * ((target.y - origin.y + 4.9 * t * t) / t)
	main.emotes.send({"kind": "throw", "who": a.id, "origin": origin, "velocity": vel})


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.dir).path_join("%s_%s.png" % ["host" if _host() else "join", name]))


func _line(tag: String) -> void:
	var p = main.player
	var d: Dictionary = main.duel.of(p.id)
	var them: int = main.net.remotes.keys()[0] if not main.net.remotes.is_empty() else -1
	var host_id := 1
	var join_id: int = p.id if not _host() else them
	if d.is_empty():
		_say("%s 対決なし 雪玉 ホスト %d つなぐ %d 財布 ホスト %d つなぐ %d" % [tag, main.emotes.balls_of(host_id), main.emotes.balls_of(join_id),
			main.craft.wallet(host_id), main.craft.wallet(join_id)])
		return
	var ha: int = int(d.hits_a) if int(d.a) == host_id else int(d.hits_b)
	var hj: int = int(d.hits_b) if int(d.a) == host_id else int(d.hits_a)
	_say("%s 段 %s 当てた ホスト %d つなぐ %d 残りの秒 %d 掛金 %d 勝ち %d 雪玉 ホスト %d つなぐ %d 財布 ホスト %d つなぐ %d 円 %s 投げの間の残りのコマ ホスト %d つなぐ %d" % [tag, d.phase, ha, hj,
		int(Duel.left_s(d)), int(d.stake), int(d.winner), main.emotes.balls_of(host_id), main.emotes.balls_of(join_id),
		main.craft.wallet(host_id), main.craft.wallet(join_id), main.duel._rings.size(), main.duel.throw_wait(host_id), main.duel.throw_wait(join_id)])


func _since() -> float:
	return (Time.get_ticks_msec() - _fight_t) / 1000.0


func _until(t: float) -> void:
	while _since() < t:
		await physics_frame


func _run() -> void:
	await _wait(0.5)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 20.0:
		await _wait(0.5)
		t += 0.5
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	await _wait(1.5)
	var p = main.player
	var hub = main.emotes
	var duel = main.duel
	var them_id: int = main.net.remotes.keys()[0]
	if _host():
		_place(p, AT, AT + Vector3(0, 0, 1))
		hub._set_balls(1, 1)
		hub._set_balls(them_id, 1)
	else:
		_place(p, AT + Vector3(0, 0, 0.8), AT)
	await _wait(1.5)
	hub.send({"kind": "hands", "who": p.id, "hands": "low_R"})
	while duel.of(p.id).get("phase", "") != "bet":
		await physics_frame
	_line("握手した")
	if not _host():
		await _wait(0.5)
		main.duel_hud.nudge(10, 1)
		await _wait(0.3)
		main.duel_hud.nudge(10, 1)
	else:
		while int(duel.of(p.id).get("stake", 0)) != 20:
			await physics_frame
		await _wait(0.5)
		main.duel_hud.accept()
	while duel.of(p.id).get("phase", "") != "fight":
		await physics_frame
	_fight_t = Time.get_ticks_msec()
	_line("始まった")
	_log_loop()
	hub.happened.connect(func(ev):
		if ev.kind == "catch":
			await _wait(0.15)
			var n: int = hub.get_children().filter(func(c): return c is CPUParticles3D and c.amount == 20).size()
			_say("%s 取った: この画面の紙吹雪 %d" % ["○" if n == 1 else "×", n])
		elif ev.kind == "hit":
			var n: int = hub.get_children().filter(func(c): return c is MeshInstance3D and c.material_override is StandardMaterial3D and c.material_override.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED).size()
			_say("%s 当たった: この画面の星 %d" % ["○" if n == 1 else "×", n]))
	if _host():
		_place(p, AT + Vector3(0, 0, -2), AT + Vector3(0, 0, 3))
	else:
		_place(p, AT + Vector3(0, 0, 3), AT + Vector3(0, 0, -2))
	var them: Node3D = main.net.remotes[them_id]
	if _host():
		for at in [3.0, 5.5, 8.0, 11.0]:
			if at > 9.0:   # 雪玉がなくなったので、作る（対決中も作れる）
				await _until(8.6)
				hub.send({"kind": "make_ball", "who": p.id})
			await _until(at)
			_throw(p, them)
			_say("投げた（%.1f 秒）雪玉 %d" % [at, hub.balls_of(p.id)])
	else:
		await _until(1.0)
		_throw(p, them)
		_say("投げた（1.0 秒）")
		await _until(1.5)
		_throw(p, them)   # 投げたばかり: ホストが受けない（雪玉は減らない）
		await _wait(0.3)
		_say("%s 続けて投げても出ない: 雪玉 %d（のぞみ 2）" % ["○" if hub.balls_of(p.id) == 2 else "×", hub.balls_of(p.id)])
		await _until(7.5)
		var done := false
		while _since() < 10.5 and not done:
			for b in hub.get_children():
				if b is Snowball and b.thrower == them_id and not b._done and b.global_position.distance_to(duel._chest(p)) < duel.CATCH_REACH:
					duel.send({"kind": "catch", "who": p.id, "ball": b.ball_id})
					_say("取りにいった: 雪玉 %d（胸から %.2f m）" % [b.ball_id, b.global_position.distance_to(duel._chest(p))])
					done = true
					break
			await physics_frame
	await _until(13.0)
	_line("決まった")
	if args.has("dir"):   # 窓を出して撮る: 勝敗の大きな表示と握手の案内（duel_hud.gd の _draw_end）を、それぞれの画面で
		await _shot("result")
		await _wait(3.0)
		await _shot("guide")
	# 払いの握手
	if _host():
		_place(p, AT, AT + Vector3(0, 0, 1))
	else:
		_place(p, AT + Vector3(0, 0, 0.8), AT)
	await _wait(1.0)
	hub.send({"kind": "hands", "who": p.id, "hands": "low_R"})
	var w := 0.0
	while not duel.of(p.id).is_empty() and w < 10.0:
		await _wait(0.5)
		w += 0.5
	await _wait(1.0)
	_line("払った")
	if args.has("dir"):
		await _shot("paid")
	await _wait(2.0)
	quit()


func _log_loop() -> void:
	while true:
		await _wait(1.0)
		if main.duel.of(main.player.id).is_empty():
			return
		_line("%.0f 秒" % _since())
