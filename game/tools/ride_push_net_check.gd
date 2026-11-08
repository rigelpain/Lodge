extends SceneTree
## 通信の確かめ: 乗っている人がいるソリを押すと重く、押してもらっているあいだは乗っている人に稼ぎが入らないか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/ride_push_net_check.gd -- --host --port=24761 --sled=small --no-sound --no-lodge --bots=0 --roam-bots=0 --lodge-bots=0
##   Godot --headless --fixed-fps 60 --path game -s res://tools/ride_push_net_check.gd -- --join=127.0.0.1 --port=24761 --sled=small --no-sound --no-lodge --bots=0 --roam-bots=0 --lodge-bots=0
## 押すのはホストの人（後ろの縁をつかんで W。つなぐ側の画面にも、押している姿が届く）。乗るのはつなぐ側の人（ホストの画面では Remote として乗る）。
##   A  誰も乗せずに、平らな所を 10 秒押す
##   B  つなぐ側の人が乗って、同じ所から 10 秒押す（道の上に斜面のボタンを 3 つ置く。どちらの画面にも置く）
##   C  丘の頂上から下りへ押し出して手を離し、止まるまで滑る（つなぐ側の人が乗ったまま）
## 二つの画面は、時計でなく、相手の様子（ソリの置き場・乗っている人）を見て進む。
## どちらの画面でも、ソリが動いた距離と、つなぐ側の人の財布（ホストの画面では Remote の番号の財布）の増えた数を出す。--trace で途中の様子

const FLAT := Vector3(-10, 0, 85)   # ride_push_check の平らな所（+z へ何もない）
const TOP := Vector3(0, 0, 3)

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


func _host() -> bool:
	return args.has("host")


func _say(s: String) -> void:
	print("[%s] %s" % ["ホスト" if _host() else "つなぐ側", s])


func _trace(s: String) -> void:
	if args.has("trace"):
		_say("  %s（乗っている %d、所 %s、速さ %.2f、押 %d）" % [s, sled.riders.size(), str(sled.global_position.snapped(Vector3(0.1, 0.1, 0.1))),
				sled.linear_velocity.length(), sled.pushers])


func _wait(t: float) -> void:
	await create_timer(t).timeout


## cond が true になるまで待つ（limit 秒まで）。なったら true
func _until(cond: Callable, limit := 40.0) -> bool:
	var t := 0.0
	while not cond.call():
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if t > limit:
			return false
	return true


func _key(k: Key, on: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)


## つなぐ側の人の財布（ホストの画面では、その人の Remote の番号で）
func _wallet() -> int:
	if not _host():
		return main.craft.wallet(main.player.id)
	for r in main.net.remotes.values():
		return main.craft.wallet(r.id)
	return -1


func _near(at: Vector3, r := 1.5) -> bool:
	return Vector2(sled.global_position.x - at.x, sled.global_position.z - at.z).length() < r


func _dist(from: Vector3) -> float:
	return Vector2(sled.global_position.x - from.x, sled.global_position.z - from.z).length()


## ホスト: ソリを at に前を +z へ向けて置き、ホストの人が後ろの縁をつかむ
func _place(at: Vector3) -> void:
	var p: Node3D = main.player
	p.let_go()
	sled.reset_to(Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z))
	sled.rotation.y = PI   # 前を +z へ
	sled.parked = false
	await physics_frame
	var b: Vector3 = sled.global_position - Vector3(0, 0, sled.HALF.y + sled.STAND)
	p.global_position = Vector3(b.x, main.height(b.x, b.z) + 0.1, b.z)
	p.rotation.y = PI   # +z を向く
	p.velocity = Vector3.ZERO
	await physics_frame
	p.grab()


## ホスト: W で secs 秒押す（stop_v を渡すと、その速さを超えたらやめる）
func _push_for(secs: float, stop_v := INF) -> void:
	_key(KEY_W, true)
	_trace("押しはじめ")
	var t := 0.0
	while t < secs and sled.linear_velocity.length() < stop_v:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_key(KEY_W, false)
	_trace("押しおわり")
	main.player.let_go()


## つなぐ側: ソリが at に置かれて止まるのを待って乗る
func _get_on_at(at: Vector3) -> void:
	await _until(func(): return _near(at) and sled.linear_velocity.length() < 0.1, 60.0)
	await _wait(1.0)
	var p: Node3D = main.player
	for i in 10:
		p.global_position = sled.global_position + sled.global_basis.x * (sled.HALF.x + 0.6) + Vector3.UP * 0.3
		p.velocity = Vector3.ZERO
		await physics_frame
		p.get_on()
		await _wait(0.5)
		if p.seat != Vector3.INF:
			break
	_trace("乗った" if p.seat != Vector3.INF else "乗れなかった")


func _drop_buttons(at: Vector3) -> void:
	var sb: Node3D = main.snow_buttons
	if sb == null:
		return
	sb.clear()
	for d in [6.0, 12.0, 18.0]:
		var q := at + Vector3(0, 0, d)
		sb.drop_at(Vector3(q.x, main.height(q.x, q.z), q.z), 0, true, 0)


func _snips() -> int:
	return main.snow_buttons.stats.snip if main.snow_buttons else 0


func _run() -> void:
	await _wait(1.0)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	_say("相手が見えた" if not main.net.remotes.is_empty() else "相手が来なかった")
	await _wait(3.0)
	sled = main.sled
	if main.snow_buttons:
		main.snow_buttons.auto = false
		main.snow_buttons.clear()
	var from: Vector3
	var w0: int
	if _host():
		# A 誰も乗せずに押す
		await _place(FLAT)
		await _wait(1.5)
		from = sled.global_position
		await _push_for(10.0)
		await _wait(2.0)
		_say("A 乗る人 %d: 10 秒押してソリが動いた距離 %.1f m" % [sled.riders.size(), _dist(from)])
		# B つなぐ側の人が乗るのを待って押す
		await _place(FLAT)
		await _until(func(): return not sled.riders.is_empty(), 60.0)
		await _wait(1.5)
		_drop_buttons(sled.global_position)
		await _wait(0.5)
		from = sled.global_position
		w0 = _wallet()
		var s0 := _snips()
		await _push_for(10.0)
		await _wait(3.0)
		_say("B 乗る人 %d: 10 秒押してソリが動いた距離 %.1f m、乗っている人の財布 +%d、切れた斜面のボタン %d" % [sled.riders.size(), _dist(from), _wallet() - w0, _snips() - s0])
		# C 頂上から押し出して手を離す（乗っている人は、置き直すと降ろされるので、乗り直すのを待つ）
		if main.snow_buttons:
			main.snow_buttons.clear()
		await _place(TOP)
		await _until(func(): return not sled.riders.is_empty(), 60.0)
		await _wait(1.5)
		from = sled.global_position
		w0 = _wallet()
		await _push_for(6.0, 2.5)
		await _until(func(): return sled.riders.is_empty(), 60.0)   # 止まって降りるまで
		await _wait(3.0)
		_say("C 押し出して手を離し、滑った: 距離 %.1f m、乗っていた人の財布 +%d" % [_dist(from), _wallet() - w0])
	else:
		# A は見ているだけ: ソリが FLAT に置かれて、動いて、止まるまで
		await _until(func(): return _near(FLAT) and sled.linear_velocity.length() < 0.1, 60.0)
		from = sled.global_position
		await _until(func(): return sled.linear_velocity.length() > 0.3, 30.0)
		await _until(func(): return sled.linear_velocity.length() < 0.05, 30.0)
		_say("A 乗る人 %d: 押してソリが動いた距離 %.1f m" % [sled.riders.size(), _dist(from)])
		# B 置き直されたら乗る
		await _get_on_at(FLAT)
		w0 = _wallet()
		_drop_buttons(sled.global_position)   # 斜面のボタンは通信に載っていないので、こちらの画面にも置く
		from = sled.global_position
		var s0 := _snips()
		await _until(func(): return sled.linear_velocity.length() > 0.3, 30.0)
		await _until(func(): return sled.linear_velocity.length() < 0.05, 30.0)
		await _wait(2.0)
		_say("B 乗る人 %d: 押してソリが動いた距離 %.1f m、乗っている人の財布 +%d、切れた斜面のボタン %d" % [sled.riders.size(), _dist(from), _wallet() - w0, _snips() - s0])
		# C 頂上に置き直されたら乗り直し、滑り終わったら降りる
		await _get_on_at(TOP)
		w0 = _wallet()
		from = sled.global_position
		await _until(func(): return _dist(from) > 10.0, 30.0)
		await _until(func(): return sled.linear_velocity.length() < 0.1, 60.0)
		await _wait(2.0)
		main.player.get_off()
		await _wait(3.0)
		_say("C 押し出して手を離し、滑った: 距離 %.1f m、乗っていた人の財布 +%d" % [_dist(from), _wallet() - w0])
	await _wait(2.0)
	quit()
