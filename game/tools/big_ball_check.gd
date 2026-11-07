extends SceneTree
## 転がす大玉（big_ball.gd・rolled.gd）の確かめ（数字だけ出す）。キーは本物の入力のイベントで流す。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/big_ball_check.gd -- --case=<名前> --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##
##   --case=seed   ふもとの雪の上で、手袋なしでしゃがんで F を押し続けても大玉は置けず、ふつうに雪玉ができる。手袋（gloves.gd）をはめると、
##                 押し続けて大玉の種が置かれ、手の雪玉は増えない。短く押せば、雪玉ができて大玉は増えない。手袋は山師の棚で買うと装備に入ってはまる
##   --case=grade  手袋の 3 段（gloves.gd）で、一人で押して 4 秒後の速さ（半径ごと）、固めた玉の育ち（道のり 20 m の半径）、崩れる強さ
##   --case=grow   平らな雪の板の上で、玉を一定の速さで転がす。道のりと半径の表（大きいほど育ちが速いか）
##   --case=push   平らな雪の板の上で、半径ごとに一人で W を押し続ける。4 秒後の速さ、両手が玉に伸びているか、体が玉から離れないか
##   --case=slope  本物の丘の上から放す。速さ・半径・崩れたか（--at=mountain で大山の頂上から）
##   --case=bump   板の上の壁にぶつける・高い所から落とす。強いと崩れ、弱いと崩れない
##   --case=catch  速い大玉を、立っているあなたに当てる。取り込まれ、Space の連打で崩れて放り出され、着いたら歩ける。遅い玉は取り込まない
##   --case=bot    （--bots=1）仲間に当てる。取り込まれた仲間は、ひとりでに暴れて出てくる

const LAB_Y := 300.0
const BigBall := preload("res://big_ball.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var fails := 0
var _next := 1000


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


## 窓から目が離れると設定が開くことがある（開いているとキーが効かない）。毎コマ閉じる
func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _run() -> void:
	await create_timer(0.5).timeout
	p = main.player
	_make_lab()
	match args.get("case", "grow"):
		"seed":
			await _seed_case()
		"grow":
			await _grow_case()
		"push":
			await _push_case()
		"grade":
			await _grade_case()
		"slope":
			await _slope_case()
		"bump":
			await _bump_case()
		"catch":
			await _catch_case()
		"bot":
			await _bot_case()
	print("だめだった数: ", fails)
	quit(1 if fails > 0 else 0)


## 平らな雪の板（高さの地図の当たり。雪の上として育つ）
func _make_lab() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0, LAB_Y, 0)
	var col := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	var n := 241
	hm.map_width = n
	hm.map_depth = n
	var d := PackedFloat32Array()
	d.resize(n * n)
	d.fill(0.0)
	hm.map_data = d
	col.shape = hm
	body.add_child(col)
	main.add_child(body)


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _say(ok: bool, what: String) -> void:
	print(("○ " if ok else "× ") + what)
	if not ok:
		fails += 1


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


## 雪玉ころがしの手袋をはめる・外す（持っていなければ、赤い布の手袋を持たせる）
func _wear(on: bool) -> void:
	if on and main.craft.gear_list(p.id, "gloves").is_empty():
		main.craft.send({"kind": "gloves_own", "who": p.id, "grade": "gloves"})
	main.craft.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": 0 if on else -1})


func _ball(at: Vector3, r: float) -> RigidBody3D:
	_next += 1
	var b: RigidBody3D = main.emotes._spawn_big({"ball": _next, "point": at, "r": r, "who": -1})
	b.reset_physics_interpolation()
	return b


func _clear_balls() -> void:
	for b in get_nodes_in_group_of("big_balls"):
		main.emotes.big_balls.erase(b.ball_id)
		b.queue_free()
	await _ticks(2)


func _stand(who: CharacterBody3D, at: Vector3, yaw := 0.0) -> void:
	who.global_position = at
	who.velocity = Vector3.ZERO
	who.rotation.y = yaw
	who.reset_physics_interpolation()


func get_nodes_in_group_of(g: String) -> Array:
	return root.get_tree().get_nodes_in_group(g)


# ---------------------------------------------------------------- 種を置く

func _seed_case() -> void:
	main.emotes.balls.erase(p.id)
	var at := Vector3(4.0, 0, 44.0)
	at.y = main.height(at.x, at.z) + 0.1
	_stand(p, at)
	p.set_third(false)
	p.set("_pitch", -0.6)   # 一人称で雪面を見下ろす（まっすぐ前では雪玉を丸められない。遊ぶ人の視点の設定によらず同じに）
	await create_timer(0.6).timeout
	await _key(KEY_CTRL, true)
	await create_timer(0.4).timeout
	await _key(KEY_F, true)
	await create_timer(2.2).timeout
	await _key(KEY_F, false)
	_say(get_nodes_in_group_of("big_balls").is_empty() and p.ball_count() == 1, "手袋なしで押し続けても大玉は置けず、雪玉ができる（雪玉 %d、大玉 %d）" % [p.ball_count(), get_nodes_in_group_of("big_balls").size()])
	main.emotes.balls.erase(p.id)
	var bag_n: int = main.craft.count(p.id)
	await _buy_gloves()
	_say(p.gloves_on() and p.doll.gloves == "gloves" and main.craft.count(p.id) == bag_n, "山師の棚で毛糸の手袋を買うと、持ち物を使わずにはまる（%s）" % p.doll.gloves)
	await create_timer(0.4).timeout
	await _key(KEY_F, true)
	await create_timer(2.2).timeout
	await _key(KEY_F, false)
	var bs := get_nodes_in_group_of("big_balls")
	_say(bs.size() == 1, "押し続けると大玉の種が 1 つ置かれる（%d）" % bs.size())
	_say(p.ball_count() == 0, "手の雪玉は増えない（%d）" % p.ball_count())
	if bs.size() == 1:
		var b: RigidBody3D = bs[0]
		var flat := Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length()
		_say(flat < 1.5, "種は足もとの前に（%.2f m 先、半径 %.2f m）" % [flat, b.r])
	await create_timer(0.5).timeout
	await _key(KEY_F, true)
	await _key(KEY_F, false)
	await create_timer(2.2).timeout
	_say(get_nodes_in_group_of("big_balls").size() == 1 and p.ball_count() == 1, "短く押すと雪玉ができ、大玉は増えない（雪玉 %d、大玉 %d）" % [p.ball_count(), get_nodes_in_group_of("big_balls").size()])
	main.emotes.balls[p.id] = 5
	await create_timer(0.3).timeout
	await _key(KEY_F, true)
	await create_timer(2.2).timeout
	await _key(KEY_F, false)
	_say(get_nodes_in_group_of("big_balls").size() == 2 and p.ball_count() == 4, "5 つ持っていても押し続ければ種にでき、1 つ減る（雪玉 %d、大玉 %d）" % [p.ball_count(), get_nodes_in_group_of("big_balls").size()])
	await _key(KEY_CTRL, false)


## 山師の棚で、いちばん安い手袋（毛糸）を買う。買うとすぐはまる
func _buy_gloves(kind := "gloves") -> void:
	var c: Node = main.craft
	c.wallets[p.id] = 5000
	c.send({"kind": "buy", "who": p.id, "item": {"kind": kind}})
	await _ticks(3)   # 人形に伝わるのは次のコマ


# ---------------------------------------------------------------- 育ち

func _grow_case() -> void:
	_stand(p, Vector3(-100, LAB_Y + 0.1, -100))
	var b := _ball(Vector3(-60, LAB_Y, 0), BigBall.SEED_R)
	await _ticks(10)
	var start := b.global_position
	var marks := [0.3, 0.5, 0.75, 1.0, 1.5, 2.0, BigBall.MAX_R]
	var mi := 0
	var last_r: float = b.r
	print("道のり (m)  半径 (m)  重さ (kg)")
	for i in 60 * 60:
		b.linear_velocity = Vector3(3.0, b.linear_velocity.y, 0)
		b.angular_velocity = Vector3(0, 0, -3.0 / b.r)
		await physics_frame
		while mi < marks.size() and b.r >= marks[mi] - 0.001:
			print("%8.1f  %7.2f  %8.0f" % [b.global_position.x - start.x, b.r, b.mass])
			mi += 1
		if mi >= marks.size():
			break
		last_r = b.r
	_say(b.r >= BigBall.MAX_R - 0.01, "転がし続けると上限の %.1f m まで育つ" % BigBall.MAX_R)
	var bottom: float = b.global_position.y - b.r - LAB_Y
	_say(absf(bottom) < 0.08, "育っても雪に食い込まない・浮かない（底 %.3f m）" % bottom)
	_say(not b.broken, "育つだけでは崩れない")


# ---------------------------------------------------------------- 押す

func _push_case() -> void:
	p.set_third(true)
	# 手袋なしでは押せない
	var b0 := _ball(Vector3(0, LAB_Y, 0), 0.4)
	_stand(p, Vector3(0, LAB_Y + 0.05, 1.0), 0.0)
	await _ticks(20)
	await _key(KEY_W, true)
	await _ticks(120)
	await _key(KEY_W, false)
	_say(p.ball_pushed == null and Vector2(b0.global_position.x, b0.global_position.z).length() < 0.2, "手袋なしでは押せない（%.2f m 動いた）" % Vector2(b0.global_position.x, b0.global_position.z).length())
	_wear(true)
	for r in [0.2, 0.4, 0.6, 0.8, 1.0, 1.3]:
		await _clear_balls()
		_stand(p, Vector3(0, LAB_Y + 0.05, r + 0.6), 0.0)   # 玉の +z 側で、-z（玉）を向く。人を先に置く
		await _ticks(3)   # 人を置き直したコマは、物理では人が大きく動いたことになり、そこに出した玉を弾く
		var b := _ball(Vector3(0, LAB_Y, 0), r)
		await _ticks(20)
		var r0: float = b.r
		await _key(KEY_W, true)
		var hands := 0
		var far := 0.0
		var n := 240
		for i in n:
			await physics_frame
			if p.doll.ball_at != Vector3.INF:
				hands += 1
			if i > 30:
				far = maxf(far, p._ball_gap(b, p.global_position))
		await _key(KEY_W, false)
		var v := Vector2(b.linear_velocity.x, b.linear_velocity.z).length()
		print("半径 %.1f → %.2f m（%4.0f kg）: 4 秒後の速さ %.2f m/s、進んだ %.1f m、両手 %d%%、体と玉の離れの最大 %.2f m" % [r0, b.r, b.mass, v, -b.global_position.z, hands * 100 / n, far])
		if r <= 0.8:
			_say(v > 0.2, "  一人で押して動く")
		_say(hands > n * 0.8, "  押しているあいだ両手が玉に伸びている")
		_say(far < 0.4, "  体が玉から離れない（吸い付き）")
		await _ticks(90)
		var still := Vector2(b.linear_velocity.x, b.linear_velocity.z).length()
		_say(still < 0.3, "  押すのをやめると止まる（%.2f m/s）" % still)
	await _clear_balls()


# ---------------------------------------------------------------- 手袋の段

func _grade_case() -> void:
	var Gloves := preload("res://gloves.gd")
	p.set_third(true)
	for g in Gloves.ORDER:
		await _buy_gloves(g)
		main.craft.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": main.craft.gloves_index(p.id, g)})
		await _ticks(2)
		var line := "%s:" % Gloves.item_name(g)
		for r in [0.8, 1.0, 1.2, 1.4]:
			await _clear_balls()
			_stand(p, Vector3(0, LAB_Y + 0.05, r + 0.6), 0.0)   # 人を先に置く（玉を人に重ねて出すと、物理で弾き飛ぶ）
			await _ticks(3)   # 人を置き直したコマは、物理では人が大きく動いたことになり、そこに出した玉を弾く
			var b := _ball(Vector3(0, LAB_Y, 0), r)
			for i in 20:
				await physics_frame
				if args.has("trace") and g == "gloves_felt" and r == 1.0:
					print("    出した %d: 玉 %s 速さ %.2f 半径 %.2f pack %s 人 %s 玉の数 %d" % [i, b.global_position - Vector3(0, LAB_Y, 0), b.linear_velocity.length(), b.r, b.pack, p.global_position - Vector3(0, LAB_Y, 0), get_nodes_in_group_of("big_balls").size()])
			await _key(KEY_W, true)
			for i in 240:
				await physics_frame
				if args.has("trace") and (i % 20 == 0 or b.linear_velocity.length() > 4.0):
					print("    %s r%.1f t%d 玉 %s 速さ %.2f 半径 %.3f 人 %s 押す %s" % [g, r, i, b.global_position - Vector3(0, LAB_Y, 0), b.linear_velocity.length(), b.r, p.global_position - Vector3(0, LAB_Y, 0), p.ball_pushed != null])
					if b.linear_velocity.length() > 4.0:
						break
			await _key(KEY_W, false)
			line += "  半径 %.1f → %.2f m/s" % [r, Vector2(b.linear_velocity.x, b.linear_velocity.z).length()]
		print(line)
		# 固めた玉の育ち: 平らな雪の上を 3 m/s で 20 m
		await _clear_balls()
		var b2 := _ball(Vector3(-60, LAB_Y, 0), BigBall.SEED_R)
		b2.pack = g
		await _ticks(5)
		var x0: float = b2.global_position.x
		while b2.global_position.x - x0 < 20.0:
			b2.linear_velocity = Vector3(3.0, b2.linear_velocity.y, 0)
			b2.angular_velocity = Vector3(0, 0, -3.0 / b2.r)
			await physics_frame
		print("  固めた玉: 20 m 転がって半径 %.2f m、崩れる強さ %.1f m/s" % [b2.r, BigBall.BREAK_DV * Gloves.stat(g, "hard")])
	await _clear_balls()


# ---------------------------------------------------------------- 坂

func _slope_case() -> void:
	var at := Vector3.ZERO
	var down := Vector3.ZERO
	if args.get("at", "") == "mountain":
		var M := preload("res://mountain.gd")
		at = Vector3(M.START.x, 0, M.START.y)
		down = Vector3(0, 0, -1)
	else:
		# 丘のふもと（4, 44）から頂上の向きへ、いちばん高い所
		var best := -INF
		for z in range(44, -10, -1):
			var h: float = main.height(4.0, float(z))
			if h > best:
				best = h
				at = Vector3(4.0, 0, float(z))
		down = Vector3(0, 0, 1)
	# 坂へ下りはじめる所（傾きが 0.2 を超える所）まで下る
	for i in 80:
		var h0: float = main.height(at.x, at.z)
		var h1: float = main.height(at.x + down.x, at.z + down.z)
		if h0 - h1 > 0.2:
			break
		at += down
	at.y = main.height(at.x, at.z)
	print("置いた所 (%.0f, %.1f, %.0f)" % [at.x, at.y, at.z])
	_stand(p, at + Vector3(30, 5, 0))
	var b := _ball(at, float(args.get("r", "0.4")))
	b.apply_central_impulse(down * b.mass * 1.0)
	var t := 0.0
	var top_v := 0.0
	print("  秒   速さ   半径   高さ")
	var last_print := -1
	while t < 60.0 and is_instance_valid(b) and not b.broken:
		await physics_frame
		t += 1.0 / 60.0
		if not is_instance_valid(b) or b.broken:
			break
		top_v = maxf(top_v, b.linear_velocity.length())
		if int(t) != last_print:
			last_print = int(t)
			print("%5.0f %6.2f %6.2f %6.1f" % [t, b.linear_velocity.length(), b.r, b.global_position.y])
		if t > 3.0 and b.linear_velocity.length() < 0.05:
			break
	var gone: bool = not is_instance_valid(b) or b.broken
	print("最高速 %.1f m/s、%s（%.1f 秒）" % [top_v, "崩れた" if gone else "止まった", t])
	_say(top_v > 3.0, "坂では重さで転がり出す")


# ---------------------------------------------------------------- ぶつかる・落ちる

func _bump_case() -> void:
	_stand(p, Vector3(-100, LAB_Y + 0.1, -100))
	var wall := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 6, 20)
	col.shape = box
	wall.add_child(col)
	main.add_child(wall)
	wall.global_position = Vector3(10, LAB_Y + 3, 0)
	for v in [3.0, 5.0, 7.0, 10.0]:
		await _clear_balls()
		var b := _ball(Vector3(7.0, LAB_Y, 0), 0.8)   # 壁の面（x = 9）の 1.2 m 手前
		await _ticks(30)
		b.linear_velocity = Vector3(v, 0, 0)
		b.angular_velocity = Vector3(0, 0, -v / b.r)
		for i in 120:
			await physics_frame
			if not is_instance_valid(b) or b.broken:
				break
		var broke: bool = not is_instance_valid(b) or b.broken
		print("壁に %.0f m/s で: %s" % [v, "崩れた" if broke else "崩れない"])
		_say(broke == (v >= 7.0), "  壁に %.0f m/s は%s" % [v, "崩れる" if v >= 7.0 else "崩れない"])
	wall.queue_free()
	for h in [0.5, 1.0, 2.0, 3.0]:
		await _clear_balls()
		var b := _ball(Vector3(0, LAB_Y + h, 0), 0.8)
		b.linear_velocity = Vector3.ZERO
		for i in 120:
			await physics_frame
			if not is_instance_valid(b) or b.broken:
				break
		var broke: bool = not is_instance_valid(b) or b.broken
		print("%.1f m から落ちて: %s（着く速さ %.1f m/s）" % [h, "崩れた" if broke else "崩れない", sqrt(2.0 * 9.8 * h)])
		_say(broke == (h >= 2.0), "  %.1f m から落ちるのは%s" % [h, "崩れる" if h >= 2.0 else "崩れない"])
	await _clear_balls()


# ---------------------------------------------------------------- 取り込まれる

## 玉を -z から +z へ v で転がし、z = 4 に立つ人に当てる
func _roll_at(who: CharacterBody3D, r: float, v: float) -> RigidBody3D:
	_stand(who, Vector3(0, LAB_Y + 0.05, 4.0))
	var b := _ball(Vector3(0, LAB_Y, -8.0), r)
	await _ticks(3)
	b.linear_velocity = Vector3(0, 0, v)
	b.angular_velocity = Vector3(v / r, 0, 0)
	return b


func _catch_case() -> void:
	p.set_third(false)   # 取り込まれるのは手袋によらない
	var b := await _roll_at(p, 1.0, 2.0)
	await _ticks(200)
	_say(not p.rolled.active(), "遅い玉（2 m/s）には取り込まれない")
	await _clear_balls()
	b = await _roll_at(p, 1.0, 7.0)
	var caught := false
	for i in 120:
		await physics_frame
		if args.has("trace") and i % 6 == 0:
			print("  玉 z=%.2f y=%.2f 速さ %.2f　人 z=%.2f y=%.2f" % [b.global_position.z, b.global_position.y, b.linear_velocity.length(), p.global_position.z, p.global_position.y])
		if p.rolled.active():
			caught = true
			break
	_say(caught, "速い玉（7 m/s）に取り込まれる")
	if not caught:
		return
	await _ticks(6)
	_say(p.third, "取り込まれると三人称になる")
	_say(p.doll.rolled, "人形は玉の面に（rolled）")
	var dd: float = p.doll.global_position.distance_to(b.global_position)
	_say(dd < b.r + 1.0, "人形は玉のそばにいる（まんなかから %.2f m、半径 %.2f m）" % [dd, b.r])
	_say(b.inside.has(p.id), "玉が中の人を知っている")
	await _ticks(120)
	_say(p.rolled.active(), "放っておくと出てこない（玉が崩れるまで）")
	var need := ceili(BigBall.KICK_BASE + BigBall.KICK_PER_R * b.r)
	var presses := 0
	for i in need + 10:
		await _key(KEY_SPACE, true)
		await _ticks(4)
		await _key(KEY_SPACE, false)
		await _ticks(4)
		presses += 1
		if not p.rolled.active():
			break
	_say(not p.rolled.active(), "Space を %d 回で崩れて出てくる（要る数 %d）" % [presses, need])
	await _ticks(2)
	_say(p.fling.active(), "放り出されて飛ぶ")
	_say(not p.doll.rolled, "人形は玉から離れる")
	var t := 0
	while p.fling.active() and t < 600:
		await physics_frame
		t += 1
	_say(not p.fling.active(), "起き上がる（%.1f 秒）" % (t / 60.0))
	_say(not p.third, "視点が一人称に戻る")
	var at := p.global_position
	await _key(KEY_W, true)
	await _ticks(60)
	await _key(KEY_W, false)
	_say(p.global_position.distance_to(at) > 0.5, "歩ける（%.1f m）" % p.global_position.distance_to(at))
	# 崩れて出てくる: 玉がぶつかって崩れれば、中の人も出てくる
	await _clear_balls()
	b = await _roll_at(p, 1.0, 7.0)
	for i in 180:
		await physics_frame
		if p.rolled.active():
			break
	await _ticks(30)
	if p.rolled.active():
		b.break_now("test")
		await _ticks(3)
		_say(not p.rolled.active() and p.fling.active(), "玉が崩れると、中の人は放り出される")
	else:
		_say(false, "2 回目に取り込まれなかった")
	var t2 := 0
	while p.fling.active() and t2 < 600:
		await physics_frame
		t2 += 1
	await _clear_balls()


func _bot_case() -> void:
	var bots := get_nodes_in_group_of("bots")
	if bots.is_empty():
		_say(false, "仲間がいない（--bots=1）")
		return
	_stand(p, Vector3(-100, LAB_Y + 0.1, -100))
	var bt: CharacterBody3D = bots[0]
	bt.let_go()
	await _ticks(2)
	var b := await _roll_at(bt, 1.0, 7.0)
	var caught := false
	for i in 120:
		await physics_frame
		if bt.rolled.active():
			caught = true
			break
	_say(caught, "仲間も速い玉に取り込まれる")
	var t := 0
	while bt.rolled.active() and t < 60 * 15:
		await physics_frame
		t += 1
	_say(not bt.rolled.active(), "仲間はひとりでに暴れて出てくる（%.1f 秒）" % (t / 60.0))
	_say(bt.fling.active(), "出てくるときは放り出されて飛ぶ")
