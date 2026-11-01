extends SceneTree
## 通信の確かめ: つなぐ側が焚き火セットを買って組むと、ホストの画面にも焚き火が出て、そばにいる人がみな乾くか。消すのも届くか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/campfire_net_check.gd -- --host --port=24721 --no-sound --bots=0 --lodge-bots=0
##   Godot --headless --fixed-fps 60 --path game -s res://tools/campfire_net_check.gd -- --join=127.0.0.1 --port=24721 --no-sound --bots=0 --lodge-bots=0
## つなぐ側: 買う → 外の雪の上で組む → 焚き火から 1.4 m で、自分の水（100 から）を 1 秒ごと → F の代わりに put_out_fire。
## --late: ホストが先に組んで 20 秒燃やしておき、あとからつないだ人の画面に、燃えた秒のぶん進んだ焚き火が出るか（snapshot）。
## ホスト: 焚き火が届いたら、自分の体を焚き火の反対側 1.4 m に置き、自分の水（100 から）と焚き火の様子を 1 秒ごと

var args := {}
var main: Node3D
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s %.1f] %s" % ["host" if args.has("host") else "join", (Time.get_ticks_msec() - _t0) / 1000.0, s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _fire() -> Node3D:
	for f in main.craft.fires.values():
		if is_instance_valid(f):
			return f
	return null


func _place(p: Node3D, at: Vector3, look: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.15
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))


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
	var p = main.player
	var c = main.craft
	if args.has("join"):
		await _wait(2.0)
		var before: int = c.wallet(p.id)
		c.send({"kind": "buy", "who": p.id, "item": {"kind": "campfire"}})
		await _wait(1.0)
		_say("買った: 手に %s、ボタン %d → %d" % [c.held(p.id).get("kind", ""), before, c.wallet(p.id)])
		var at: Vector3 = p.global_position + Vector3(6, 0, 8)
		_place(p, at, at + Vector3(0, 0, 10))
		await _wait(0.5)
		_say("組める所: %s" % [p.fire_spot()])
		_say("組む: %s" % p.lay_fire())
		await _wait(1.5)
		var f := _fire()
		_say("自分の画面の焚き火: %s 強さ %.2f" % [f != null, f.level() if f else -1.0])
		if f:
			_place(p, f.global_position + Vector3(0, 0, -1.4), f.global_position)
			main.damp.put(p.id, 100.0)
			var ws := []
			for i in 10:
				ws.append(int(main.damp.water_of(p.id)))
				await _wait(1.0)
			_say("自分の水（焚き火から 1.4 m、1 秒ごと）: %s" % [ws])
			_say("消す: %s" % p.put_out_fire())
			await _wait(1.5)
			_say("消えた: %s" % [not is_instance_valid(f) or not f.lit()])
		await _wait(3.0)
	else:
		var seen := false
		var ws := []
		for i in 30:
			var f := _fire()
			if f and not seen:
				seen = true
				_say("相手の焚き火が届いた: 番号 %d 組んだ人 %d 所 %s" % [f.fire_id, f.owner_id, f.global_position])
				_place(p, f.global_position + Vector3(0, 0, 1.4), f.global_position)
				main.damp.put(p.id, 100.0)
			if f:
				ws.append(int(main.damp.water_of(p.id)))
				_say("焚き火: 燃えている %s 強さ %.2f 仲間分け fires %s 自分の水 %d" % [f.lit(), f.level(), f.is_in_group("fires"), int(main.damp.water_of(p.id))])
			elif seen:
				_say("焚き火は片づいた")
				break
			await _wait(1.0)
		_say("ホストの水（焚き火から 1.4 m、1 秒ごと）: %s" % [ws])
	quit()


func _late() -> void:
	var p = main.player
	var c = main.craft
	if args.has("host"):
		await _wait(2.0)
		c.send({"kind": "buy", "who": p.id, "item": {"kind": "campfire"}})
		var at: Vector3 = p.global_position + Vector3(6, 0, 8)
		_place(p, at, at + Vector3(0, 0, 10))
		await _wait(0.3)
		_say("組む: %s" % p.lay_fire())
		var t := 0.0
		while t < 90.0:
			var f := _fire()
			_say("ホストの焚き火: 燃えた秒 %.1f 燃えている %s 相手 %d 人" % [f.age if f else -1.0, f.lit() if f else false, main.net.remotes.size()])
			await _wait(2.0)
			t += 2.0
	else:
		var t := 0.0
		while main.net.remotes.is_empty() and t < 20.0:
			await _wait(0.5)
			t += 0.5
		await _wait(1.0)
		var f := _fire()
		_say("あとから来た画面の焚き火: %s 燃えた秒 %.1f 燃えている %s 仲間分け fires %s" % [f != null, f.age if f else -1.0, f.lit() if f else false, f.is_in_group("fires") if f else false])
	quit()
