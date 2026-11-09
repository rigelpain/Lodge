extends SceneTree
## 通信の確かめ: 縦に立ったソリを、つなぐ側の人がつかんでいたら手が離れて足が雪に着くか・ソリが起き直るか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_tip_net_check.gd -- --host --port=24763 --sled=small --no-sound --no-lodge --bots=0 --roam-bots=0 --lodge-bots=0
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_tip_net_check.gd -- --join=127.0.0.1 --port=24763 --sled=small --no-sound --no-lodge --bots=0 --roam-bots=0 --lodge-bots=0
## つなぐ側の人がソリの後ろの縁をつかむ。ホストはそれを見てから、ソリを鼻先を下に縦に立てたまま 2 秒押さえる（押す人と紐の力で立ったままの形）。
## ホストのソリは TIP_WAIT で手を離させて起き直り、つなぐ側には let_go が届く。どちらの画面でも、ソリの傾きと、つかんでいた人の様子と足の浮きを出す。
## 縦のあいだに、つなぐ側の人がもう一度つかもうとしても、つかめないか（ソリの tipped）

const AT := Vector3(-10, 0, 85)   # 平らな所（ride_push_net_check と同じ）

var args := {}
var main: Node3D
var sled: RigidBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s %5.1f] %s" % ["ホスト" if args.has("host") else "つなぐ", Engine.get_physics_frames() / 60.0, s])


func _tilt() -> float:
	return rad_to_deg(acos(clampf(sled.global_basis.y.y, -1.0, 1.0)))


func _gap(who: Node3D) -> float:
	return who.global_position.y - (main.height(who.global_position.x, who.global_position.z) + main.snow_lift(who.global_position.x, who.global_position.z))


func _run() -> void:
	await create_timer(1.0).timeout
	sled = main.sled
	if args.has("host"):
		await _host()
	else:
		await _join()
	quit()


func _host() -> void:
	var g: float = main.height(AT.x, AT.z)
	sled.global_transform = Transform3D(Basis(), Vector3(AT.x, g + 0.3, AT.z))
	main.player.global_position = Vector3(AT.x + 6, g + 0.3, AT.z)
	var t := 0.0
	var who: Node3D = null
	while who == null and t < 120.0:
		await physics_frame
		t += 1.0 / 60.0
		for r in main.net.remotes.values():
			if sled.holders.has(r):
				who = r
	if who == null:
		_say("つなぐ側の人がつかまなかった")
		return
	_say("つなぐ側の人がつかんだ。ソリを縦に立てて押さえる")
	var stand := Transform3D(Basis(Vector3.RIGHT, PI / 2), sled.global_position + Vector3.UP * 0.8)   # 鼻先（-Z）を下に
	var held := 0.0
	var let := -1.0
	while held < 2.0:
		await physics_frame
		held += 1.0 / 60.0
		sled.global_transform = stand
		sled.linear_velocity = Vector3.ZERO
		sled.angular_velocity = Vector3.ZERO
		if let < 0.0 and not sled.holders.has(who):
			let = held
			break
	_say("手が離れた: %s（縦にしてから %.2f 秒）傾き %.0f° 起き直り中 %s" % [str(let >= 0.0), let, _tilt(), str(sled.tipped())])
	await create_timer(3.0).timeout
	_say("3 秒後: 傾き %.0f° つかんでいる %d 人 つなぐ側の人の足の浮き %.2f" % [_tilt(), sled.holders.size(), _gap(who)])
	await create_timer(2.0).timeout


func _join() -> void:
	var p: CharacterBody3D = main.player
	var t := 0.0
	# ホストがソリを平らな所へ置くのを待つ
	while (Vector2(sled.global_position.x, sled.global_position.z) - Vector2(AT.x, AT.z)).length() > 1.0 and t < 30.0:
		await physics_frame
		t += 1.0 / 60.0
	await create_timer(1.5).timeout
	var back: Vector3 = sled.to_global(Vector3(0, 0, sled.HALF.y + sled.STAND))
	p.global_position = Vector3(back.x, main.height(back.x, back.z) + 0.1, back.z)
	p.look_at(Vector3(sled.global_position.x, p.global_position.y, sled.global_position.z), Vector3.UP)
	await physics_frame
	p.grab()
	_say("つかんだ: %s" % str(p.mode == p.Mode.GRIP))
	var tipped_seen := false
	var tried := false
	t = 0.0
	var worst := 0.0
	while t < 15.0:
		await physics_frame
		t += 1.0 / 60.0
		if p.mode == p.Mode.GRIP:
			worst = maxf(worst, _gap(p))
		if not tipped_seen and _tilt() > 60.0:
			tipped_seen = true
			_say("ソリが縦に見えた（傾き %.0f°）。つかんでいる %s 足の浮き %.2f" % [_tilt(), str(p.mode == p.Mode.GRIP), _gap(p)])
		if tipped_seen and not tried and p.mode != p.Mode.GRIP and _tilt() > 60.0:
			tried = true
			p.grab()
			_say("縦のあいだにもう一度つかもうとした: つかめた %s" % str(p.mode == p.Mode.GRIP))
		if tipped_seen and p.mode != p.Mode.GRIP and t > 12.0:
			break
	_say("おわり: つかんでいる %s 足の浮き %.2f（つかんでいたあいだの最大 %.2f）ソリの傾き %.0f°" % [str(p.mode == p.Mode.GRIP), _gap(p), worst, _tilt()])
