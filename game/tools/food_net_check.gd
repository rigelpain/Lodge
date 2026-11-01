extends SceneTree
## 通信の確かめ: 体の調子（水と熱）が、つなぐ側からホストへ届き、押す力に効くか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/food_net_check.gd -- --host --port=24711 --no-sound
##   Godot --headless --fixed-fps 60 --path game -s res://tools/food_net_check.gd -- --join=127.0.0.1 --port=24711 --no-sound
## つなぐ側: 水 60・熱 40（濡れて冷えた）にし、ラーメンを 3 口食べる。
## ホスト: 1 秒ごとに、つなぐ側の人の体（remote_person.gd）の水・熱・押す力の倍率・人形の見た目・ふるえを出す

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
	var p = main.player
	if args.has("join"):
		main.damp.put(p.id, 60.0, 40.0)
		await _wait(2.0)
		for i in 3:
			main.damp.eat(p.id, "ramen")
			await _wait(1.0)
		for i in 18:
			_say("自分の水 %.0f 熱 %.0f これから %.0f" % [main.damp.water_of(p.id), main.damp.heat_of(p.id), main.damp.coming(p.id)])
			await _wait(1.0)
	else:
		for i in 24:
			for pid in main.net.remotes:
				var rp = main.net.remotes[pid]
				_say("相手の水 %.0f 熱 %.0f 押す力 ×%.2f 人形の見た目 %.2f ふるえを弱める %.2f" % [main.damp.water_of(rp.id), main.damp.heat_of(rp.id),
						rp.damp_k(), rp.doll.damp, rp.doll.warm])
			await _wait(1.0)
	quit()
