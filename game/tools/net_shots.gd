extends SceneTree
## 通信の確かめ: 同じ Mac で 2 つ起動し、1 つをホスト、1 つをつなぐ側にして、二人で同じソリをつかんで押し、乗るまでを撮る。
##   Godot --path game --resolution 960x540 --position 0,40 -s res://tools/net_shots.gd -- --host --tag=host --dir=/path/shots
##   Godot --path game --resolution 960x540 --position 980,40 -s res://tools/net_shots.gd -- --join=127.0.0.1 --tag=join --dir=/path/shots
## --lag=ミリ秒 で届くものを遅らせる（net.gd）。三人称で、ソリの後ろから撮る。
## 流れ: つながるのを待つ → ソリの後ろの左右に分かれてつかむ（ホストは左、つなぐ側は右）→ W で 6 秒押す → 乗る → 下って滑る。
## 1 秒ごとに、ソリの位置と相手の体の位置を log_<tag>.txt に書く（2 つの画面でソリの位置がそろっているかを比べる）

var args := {}
var main: Node3D
var p: CharacterBody3D
var lines: Array[String] = []
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/net_shots")


func _tag() -> String:
	return args.get("tag", "host" if args.has("host") else "join")


func _say(s: String) -> void:
	var line := "[%s %.1f] %s" % [_tag(), (Time.get_ticks_msec() - _t0) / 1000.0, s]
	print(line)
	lines.append(line)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _key(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)


func _shot(name: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_dir(), _tag(), name])
	_say("撮った " + name)


func _log() -> void:
	var s: RigidBody3D = main.sled
	var r := ""
	for pid in main.net.remotes:
		var rp: Node3D = main.net.remotes[pid]
		r += " 相手%d=(%.2f, %.2f, %.2f) 姿=%d" % [pid, rp.global_position.x, rp.global_position.y, rp.global_position.z, rp.mode]
	_say("ソリ=(%.2f, %.2f, %.2f) 速さ=%.2f 押す人=%d つかむ人=%d 乗る人=%d 自分=%d%s 往復=%dms" % [s.global_position.x, s.global_position.y,
		s.global_position.z, s.linear_velocity.length(), s.pushers, s.holders.size(), s.riders.size(), p.mode, r, main.hud._net_ms()])


func _run() -> void:
	await _wait(0.5)
	p = main.player
	p.set_third(true)
	p.cam_dist = 4.5
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	_say("相手が見えた" if not main.net.remotes.is_empty() else "相手が来なかった")
	await _wait(2.0)
	_log()
	await _shot("1_meet")
	# ソリの後ろに回ってつかむ（ホストは左、つなぐ側は右）
	var s: RigidBody3D = main.sled
	var x := -0.55 if args.has("host") else 0.55
	p.global_position = s.to_global(Vector3(x, 0, s.HALF.y + 0.7)) + Vector3.UP * 0.2
	var fwd: Vector3 = -s.global_basis.z
	p.rotation.y = atan2(-fwd.x, -fwd.z)
	await _wait(0.3)
	p.grab()
	_say("つかんだ: 姿=%d" % p.mode)
	await _wait(1.0)
	_key(KEY_W, true)
	for i in 6:
		await _wait(1.0)
		_log()
		if i == 2:
			await _shot("2_push")
	_key(KEY_W, false)
	await _shot("3_pushed")
	await _wait(1.0)
	p.get_on()
	_say("乗った: 姿=%d 席=%s" % [p.mode, p.seat])
	# ソリを坂の下へ向けて滑らせるのは、ホストの画面のソリが決める。乗ったまま、下るのを待つ
	for i in 5:
		await _wait(1.0)
		_log()
		if i == 1:
			await _shot("4_ride")
	await _shot("5_ride_end")
	var f := FileAccess.open("%s/log_%s.txt" % [_dir(), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	await _wait(2.0)
	quit()
