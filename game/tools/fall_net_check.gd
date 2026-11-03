extends SceneTree
## 安全網の確かめ: 地面の下へ落ちたソリと人が、雪の上へ戻るか。通信でも同じか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/fall_net_check.gd -- --host --port=24712 --no-sound
##   Godot --headless --fixed-fps 60 --path game -s res://tools/fall_net_check.gd -- --join=127.0.0.1 --port=24712 --no-sound
##   Godot --headless --fixed-fps 60 --path game -s res://tools/fall_net_check.gd -- --no-sound     （ひとりで）
## ホスト（ひとりのときも）: 大きな山のジャンプ台の着地で、ソリを雪面の 5 m 下へ置いて下へ 10 m/s で落とす。自分の人も 5 m 下へ。
## つなぐ側: 自分の画面のソリ（ホストの姿を写す）と、自分の人を 5 m 下へ置いたあとの、雪面からの高さを出す

const Mountain := preload("res://mountain.gd")

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
	print("[%s %.1f] %s" % ["host" if args.has("host") else ("join" if args.has("join") else "solo"), (Time.get_ticks_msec() - _t0) / 1000.0, s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _gap(n: Node3D) -> float:
	var p := n.global_position
	return p.y - main.height(p.x, p.z)


func _run() -> void:
	await _wait(0.5)
	if args.has("host") or args.has("join"):
		var t := 0.0
		while main.net.remotes.is_empty() and t < 20.0:
			await _wait(0.5)
			t += 0.5
		if main.net.remotes.is_empty():
			_say("相手が来なかった")
			quit(1)
			return
	var k := Mountain.kicker(1)   # 中腹の肩の先のジャンプ台の着地
	var land: Vector2 = (k.lip as Vector2) + (k.f as Vector2) * 8.0
	var at := Vector3(land.x, 0, land.y)
	var sled: RigidBody3D = main.sled
	var p: CharacterBody3D = main.player
	if not args.has("join"):
		sled.reset_to(Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z))
		await _wait(0.3)
		sled.parked = false
		sled.global_position = Vector3(at.x, main.height(at.x, at.z) - 5.0, at.z)
		sled.linear_velocity = Vector3(0, -10, -8)
		_say("ソリを雪面の 5 m 下へ置いた")
	else:
		await _wait(1.0)   # ホストがソリを動かすのを待つ
	p.global_position = Vector3(at.x + 6.0, main.height(at.x + 6.0, at.z) - 5.0, at.z)
	p.velocity = Vector3(0, -10, 0)
	_say("人を雪面の 5 m 下へ置いた（ソリは %s）" % ("ホストの姿を写す" if sled.net_follow else "自分の画面の物理"))
	var low_s := 1e9
	var low_p := 1e9
	for i in 30:
		await _wait(0.1)
		low_s = minf(low_s, _gap(sled))
		low_p = minf(low_p, _gap(p))
		if i % 5 == 4:
			_say("ソリ 雪から %.2f m、人 雪から %.2f m" % [_gap(sled), _gap(p)])
	var ok := _gap(sled) > -0.5 and _gap(p) > -0.5
	_say("%s: 3 秒後 ソリ 雪から %.2f m、人 雪から %.2f m" % ["戻った" if ok else "戻らない", _gap(sled), _gap(p)])
	quit(0 if ok else 1)
