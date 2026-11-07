extends SceneTree
## 通信の確かめ: 転がす大玉（big_ball.gd・rolled.gd）。数字だけ出す。キーは本物の入力のイベントで押す。ホストを先に起動する。
##   Godot --headless --path game -s res://tools/big_ball_net_check.gd -- --host --port=24781 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   Godot --headless --path game -s res://tools/big_ball_net_check.gd -- --join=127.0.0.1 --port=24781 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
## 2 つの画面の時間を合わせるので --fixed-fps は付けない。両方の画面に同じ平らな雪の板を置き、その上で確かめる。
## 流れ: つなぐ側の人がしゃがんで F を押し続けて種を置く → 両方の画面に同じ番号の大玉 → つなぐ側の人が W で押す → ホストの大玉が動いて育ち、
## つなぐ側も同じ所・同じ大きさに → ホストが大きくして、つなぐ側の人へ速く転がす → つなぐ側の画面で取り込まれ、ホストの大玉が中の人を知り、
## ホストの画面の人形も玉の面に → つなぐ側の人が Space を連打 → ホストの大玉が崩れ、両方の画面から消え、つなぐ側の人は放り出される

const BigBall := preload("res://big_ball.gd")
const LAB_Y := 300.0
const SPOT := Vector3(0.0, LAB_Y, 20.0)   # 両方の画面に置く、平らな雪の板の上（坂で玉が逃げない）

var args := {}
var main: Node3D
var p: CharacterBody3D
var fails := 0
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _host() -> bool:
	return args.has("host")


func _say(t: String) -> void:
	print("[%s %.1f] %s" % ["host" if _host() else "join", (Time.get_ticks_msec() - _t0) / 1000.0, t])


func _ok(c: bool, what: String) -> void:
	_say(("○ " if c else "× ") + what)
	if not c:
		fails += 1


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		if t > limit:
			return false
		await physics_frame
		t += 1.0 / 60.0
	return true


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


## 平らな雪の板（高さの地図の当たり）
func _make_lab() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0, LAB_Y, 0)
	var col := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	var n := 161
	hm.map_width = n
	hm.map_depth = n
	var d := PackedFloat32Array()
	d.resize(n * n)
	d.fill(0.0)
	hm.map_data = d
	col.shape = hm
	body.add_child(col)
	main.add_child(body)


func _ball() -> RigidBody3D:
	for b in root.get_tree().get_nodes_in_group("big_balls"):
		if not b.broken:
			return b
	return null


func _run() -> void:
	await create_timer(0.5).timeout
	p = main.player
	_make_lab()
	if _host():
		await _host_run()
	else:
		await _join_run()
	_say("だめだった数: %d" % fails)
	await create_timer(1.0).timeout
	quit(1 if fails > 0 else 0)


func _host_run() -> void:
	p.global_position = SPOT + Vector3(-12, 0.1, 0)
	_ok(await _until(func(): return not main.net.remotes.is_empty(), 20.0), "つなぐ側が来た")
	var pid: int = main.net.remotes.keys()[0]
	var them: Node3D = main.net.remotes[pid]
	_ok(await _until(func(): return _ball() != null, 20.0), "つなぐ側が置いた種が、ホストにも生まれる")
	var b := _ball()
	if b == null:
		return
	_say("ホストの大玉 %d: 半径 %.2f" % [b.ball_id, b.r])
	var at0 := b.global_position
	var hands := 0
	for i in 60 * 5:
		await physics_frame
		if not is_instance_valid(b):
			break
		if them.doll.ball_at != Vector3.INF:
			hands += 1
		if args.has("trace") and i % 15 == 0:
			_say("  玉 (%.1f, %.1f) 速さ %.2f 半径 %.2f　人 (%.1f, %.1f) bp %s" % [b.global_position.x, b.global_position.z, b.linear_velocity.length(), b.r, them.global_position.x, them.global_position.z, str(them._s.get("bp", "-"))])
	if not is_instance_valid(b):
		_ok(false, "押しているあいだに崩れた")
		return
	var moved := Vector2(b.global_position.x - at0.x, b.global_position.z - at0.z).length()
	_ok(moved > 1.0, "つなぐ側の人が押すと、ホストの大玉が動く（%.1f m、半径 %.2f m）" % [moved, b.r])
	_ok(hands > 60, "ホストの画面で、押している人の両手が玉に（%.1f 秒）" % (hands / 60.0))
	_ok(them.doll.gloves == "gloves_felt", "ホストの画面で、つなぐ側の人の人形が手袋をはめている（%s）" % them.doll.gloves)
	await create_timer(3.0).timeout
	# 大きくして、つなぐ側の人へ速く転がす
	var who: Vector3 = them.global_position
	b._set_r(1.1)
	b.global_position = Vector3(who.x, LAB_Y + 1.1, who.z - 6.0)
	b.linear_velocity = Vector3(0, 0, 8.0)
	b.angular_velocity = Vector3(8.0 / 1.1, 0, 0)
	b._v_prev = Vector3.INF   # 急に速くしたのを、ぶつかったと見ない
	_say("ホストが大玉を半径 1.1 m にして、つなぐ側の人へ 8 m/s で転がす")
	var bid: int = b.ball_id
	_ok(await _until(func(): return is_instance_valid(b) and b.inside.has(pid), 6.0), "ホストの大玉が、取り込まれた人を知る")
	await create_timer(0.3).timeout
	_ok(them.doll.rolled, "ホストの画面で、取り込まれた人の人形が玉の面に")
	_ok(await _until(func(): return main.emotes.big_ball(bid) == null, 20.0), "つなぐ側の人が暴れて、ホストの大玉が崩れる")
	await create_timer(0.5).timeout
	_ok(not them.doll.rolled, "ホストの画面で、出てきた人の人形が玉から離れる")
	await create_timer(4.0).timeout


func _join_run() -> void:
	_ok(await _until(func(): return main.net.joined(), 20.0), "ホストにつながった")
	main.emotes.balls.erase(p.id)
	main.craft.send({"kind": "gloves_own", "who": p.id, "grade": "gloves_felt"})   # 雪玉ころがしの手袋をはめる（gloves.gd）
	main.craft.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": 0})
	_ok(await _until(func(): return p.gloves_on(), 5.0), "手袋をはめた")
	p.global_position = SPOT + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0   # -z を向く
	p.set_third(false)
	p.set("_pitch", -0.6)   # 一人称で雪面を見下ろす（まっすぐ前では雪玉を丸められない。遊ぶ人の視点の設定によらず同じに）
	p.reset_physics_interpolation()
	await create_timer(1.5).timeout
	await _key(KEY_CTRL, true)
	await create_timer(0.3).timeout
	await _key(KEY_F, true)
	await create_timer(2.2).timeout
	await _key(KEY_F, false)
	await _key(KEY_CTRL, false)
	_ok(await _until(func(): return _ball() != null, 5.0), "種を置くと、つなぐ側にも大玉が生まれる")
	var b := _ball()
	if b == null:
		return
	_ok(b.net_follow, "つなぐ側の大玉は、ホストの姿を写す")
	await create_timer(0.3).timeout
	var at0 := b.global_position
	await _key(KEY_W, true)
	await create_timer(3.5).timeout
	_ok(p.ball_pushed != null, "W で押している（体が玉に当たっている）")
	await _key(KEY_W, false)
	await create_timer(0.5).timeout
	var moved := Vector2(b.global_position.x - at0.x, b.global_position.z - at0.z).length()
	_ok(moved > 1.0 and b.r > BigBall.SEED_R + 0.05, "つなぐ側の大玉もホストのとおり動いて育つ（%.1f m、半径 %.2f m）" % [moved, b.r])
	_ok(await _until(func(): return p.rolled.active(), 8.0), "ホストが転がした大玉に取り込まれる（半径 %.2f m）" % (b.r if is_instance_valid(b) else 0.0))
	await create_timer(0.3).timeout
	_ok(p.third, "取り込まれると三人称")
	var n := 0
	while p.rolled.active() and n < 40:
		await _key(KEY_SPACE, true)
		await create_timer(0.06).timeout
		await _key(KEY_SPACE, false)
		await create_timer(0.06).timeout
		n += 1
	_ok(not p.rolled.active(), "Space を %d 回で、崩れて出てくる" % n)
	await create_timer(0.1).timeout
	_ok(p.fling.active(), "放り出されて飛ぶ")
	_ok(await _until(func(): return _ball() == null, 3.0), "つなぐ側の大玉も消える")
	_ok(await _until(func(): return not p.fling.active(), 6.0), "起き上がる")
