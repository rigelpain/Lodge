extends SceneTree
## 雪合戦の対決の確かめ（一人の画面、数字だけ出す）。あなたと対決の仲間（--duel-bot）と、対決していない仲間がもう 1 人。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/duel_check.gd -- --no-sound --duel-bot --bots=2 --lodge-bots=0
## 握手 → 掛金 20 → 仲間が受けて始まる → 雪玉が 3 つになるか・財布から預かったか →
## 対決していない仲間の雪玉が当たらないか → 相手の雪玉を取れるか → 続けて 2 つ当てても 1 つか → 3 発当てて勝つか → 握手で払われるか。
## --timeout: 当てずに 60 秒待って、引き分けで掛金が戻るか。--wall: 円の外へ歩いても出られないか

const Snowball := preload("res://snowball.gd")

var args := {}
var main: Node3D
var _t0 := 0
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%.1f] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, s])


func _ok(cond: bool, what: String) -> void:
	_say(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _place(p: Node3D, at: Vector3, look: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.15
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))


func _bots() -> Array:
	return main.get_children().filter(func(c): return c.get_script() == main.Bot and not c.lounge)


## a が b の胸へ投げる（当たる速さで）
func _throw(a: Node3D, b: Node3D) -> void:
	var origin := a.global_position + Vector3.UP * 1.4 + (b.global_position - a.global_position).normalized() * 0.5
	var target := b.global_position + Vector3.UP * 1.0
	var flat := target - origin
	flat.y = 0
	var t := flat.length() / 12.0
	var vel := flat.normalized() * 12.0 + Vector3.UP * ((target.y - origin.y + 4.9 * t * t) / t)
	main.emotes.send({"kind": "throw", "who": a.id, "origin": origin, "velocity": vel})


func _run() -> void:
	await _wait(1.0)
	var p = main.player
	var hub = main.emotes
	var duel = main.duel
	var craft = main.craft
	var bots := _bots()
	var foe = bots[0]
	var other = bots[1]
	foe.process_mode = Node.PROCESS_MODE_DISABLED   # 握手の所まで寄せるあいだ、止めておく
	other.process_mode = Node.PROCESS_MODE_DISABLED
	var at := Vector3(14, 0, 16)
	_place(p, at, at + Vector3(0, 0, 1))
	_place(foe, at + Vector3(0, 0, 0.8), at)
	_place(other, at + Vector3(7, 0, 0), at)
	hub._set_balls(other.id, 5)
	await _wait(0.3)
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	var wallet0: int = craft.wallet(p.id)
	var fwallet0: int = craft.wallet(foe.id)
	# 握手（低い手のひら同士）
	hub.send({"kind": "hands", "who": p.id, "hands": "low_R"})
	hub.send({"kind": "hands", "who": foe.id, "hands": "low_R"})
	await _wait(1.0)
	var d: Dictionary = duel.of(p.id)
	_ok(not d.is_empty() and d.phase == "bet", "握手で掛金の画面へ: %s" % [d.get("phase", "なし")])
	_ok(main.duel_hud.bet_open and p.menu_open, "掛金の画面が開いた")
	main.duel_hud.nudge(10, 1)
	main.duel_hud.nudge(10, 1)
	await _wait(0.2)
	d = duel.of(p.id)
	_ok(int(d.stake) == 20 and (d.ok_a if int(d.a) == p.id else d.ok_b), "掛金 20 を出した（出した人は受けた）: %d" % int(d.stake))
	await _wait(foe.BET_WAIT + 1.0)
	d = duel.of(p.id)
	_ok(d.phase == "fight", "仲間が受けて始まった: %s" % d.phase)
	_ok(not main.duel_hud.bet_open and not p.menu_open, "掛金の画面が閉じた")
	_ok(hub.balls_of(p.id) == 3 and hub.balls_of(foe.id) == 3, "雪玉は 3 つ: あなた %d 仲間 %d" % [hub.balls_of(p.id), hub.balls_of(foe.id)])
	_ok(craft.wallet(p.id) == wallet0 - 20 and craft.wallet(foe.id) == fwallet0 - 20, "財布から 20 ずつ預けた: %d → %d" % [wallet0, craft.wallet(p.id)])
	_ok(duel._rings.has(int(d.id)), "雪の上に円の印が出た")
	if args.has("wall"):
		foe.process_mode = Node.PROCESS_MODE_DISABLED
		for i in 120:
			p.global_position += Vector3(0.1, 0, 0)
			await physics_frame
		var off := Vector2(p.global_position.x - d.at.x, p.global_position.z - d.at.z).length()
		_ok(off <= duel.RADIUS, "円の外へ出られない: まんなかから %.2f m" % off)
		quit(fails)
		return
	if args.has("timeout"):
		foe.process_mode = Node.PROCESS_MODE_DISABLED
		while duel.of(p.id).get("phase", "") == "fight":
			await _wait(1.0)
		d = duel.of(p.id)
		_ok(d.phase == "over" and int(d.winner) == -1, "60 秒で同じ数: 引き分け %s" % [d.winner])
		while not duel.of(p.id).is_empty():
			await _wait(1.0)
		_ok(craft.wallet(p.id) == wallet0 and craft.wallet(foe.id) == fwallet0, "30 秒で掛金が戻った: %d" % craft.wallet(p.id))
		quit(fails)
		return
	# 対決していない仲間の雪玉は当たらない
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	var hits := []
	hub.happened.connect(func(ev): if ev.kind == "hit": hits.append([ev.who, ev.get("by", -1)]))
	_throw(other, p)
	await _wait(1.5)
	_ok(hits.is_empty(), "対決していない人の雪玉は当たらない: %s" % [hits])
	# 相手の雪玉を取る: 仲間がこちらへ投げ、手の届く所に来たら取る
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	foe._duel_t = 99.0
	_place(foe, at + Vector3(0, 0, 4), at)
	await _wait(0.2)
	_throw(foe, p)
	var caught := false
	var before: int = hub.balls_of(p.id)
	for i in 120:
		await physics_frame
		for b in hub.get_children():
			if b is Snowball and b.thrower == foe.id and b.global_position.distance_to(duel._chest(p)) < duel.CATCH_REACH:
				duel.send({"kind": "catch", "who": p.id, "ball": b.ball_id})
				caught = true
				break
		if caught:
			break
	await _wait(0.5)
	d = duel.of(p.id)
	_ok(caught and hub.balls_of(p.id) == before + 1 and Duel_lives(d, p.id) == 3, "相手の雪玉を取った: 雪玉 %d → %d、残り %d" % [before, hub.balls_of(p.id), Duel_lives(d, p.id)])
	# 3 発当てる（仲間は止めておく）
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	foe.doll.process_mode = Node.PROCESS_MODE_ALWAYS
	_place(p, at + Vector3(0, 0, -2), foe.global_position)
	_throw(p, foe)   # 続けて 2 つ: のけぞっているあいだの 2 つ目は数えない（すり抜ける）
	await _wait(0.25)
	_throw(p, foe)
	await _wait(1.0)
	d = duel.of(p.id)
	var mine: int = int(d.hits_a if int(d.a) == p.id else d.hits_b)
	_ok(mine == 1 and duel.guarded(foe.id), "続けて当てても 1 つ（のけぞりで続けて当てられない）: %d" % mine)
	for i in 2:
		await _wait(1.0)
		_throw(p, foe)
		await _wait(0.8)
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	d = duel.of(p.id)
	_ok(d.phase == "over" and int(d.winner) == p.id, "3 発当てて勝った: %s 勝ち %s 当てた %d" % [d.phase, d.winner, int(d.hits_a if int(d.a) == p.id else d.hits_b)])
	# 握手で払う（仲間が握手しに来る）
	var w1: int = craft.wallet(p.id)
	await _wait(0.5)
	hub.send({"kind": "hands", "who": p.id, "hands": "low_R"})
	for i in 20:
		await _wait(0.5)
		if duel.of(p.id).is_empty():
			break
	_ok(duel.of(p.id).is_empty() and craft.wallet(p.id) == w1 + 40, "握手で掛金のすべて（40）が入った: %d → %d" % [w1, craft.wallet(p.id)])
	_say("おわり: ×の数 %d" % fails)
	quit(fails)


func Duel_lives(d: Dictionary, who: int) -> int:
	return preload("res://duel.gd").lives_of(d, who) if not d.is_empty() else -1
