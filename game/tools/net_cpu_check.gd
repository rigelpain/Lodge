extends SceneTree
## 通信の確かめ: 仲間（CPU）が、ホストとつなぐ側の両方の画面で同じに見えるか。ホストを先に、6 秒ほどあとにつなぐ側を起動する（あとから来た人にも見えるか）。
## 実時間で動かすので --fixed-fps は付けない。ロッジの席の札も見るので、ロッジの仲間も置く（--cpus は全部の数）。
##   Godot --path game --resolution 960x540 --position 0,40 -s res://tools/net_cpu_check.gd -- --host --port=24760 --no-sound --hud-idle=0 --bots=0 --roam-bots=5 --lodge-bots=2 --cpus=7 --dir=/path/shots
##   Godot --path game --resolution 960x540 --position 980,40 -s res://tools/net_cpu_check.gd -- --join=127.0.0.1 --port=24760 --no-sound --hud-idle=0 --cpus=7 --dir=/path/shots
## 1 人目が帰ったあとに、もう 1 つ（--second を足す）つなぐ: 人が抜けても仲間が残るか、あとから来た人に見えるか、席の札が合うか、ホストが帰ったら消えるか。
##   Godot --headless --path game -s res://tools/net_cpu_check.gd -- --join=127.0.0.1 --port=24760 --no-sound --cpus=7 --second
## 流れ: 仲間の表を出す → ゆきが丘を米袋で滑るのを両方から撮る（0.25 秒ごとに所を記録）→ つなぐ側がソリをつかむと手伝いに来る → 一緒に乗る
##   → つなぐ側がゆきと対決（握手・掛金 10・人が取る・ゆきが取る・人に当たる・ゆきに当たる・投げの間）→ 握手で払う → つなぐ側が帰る。
## 絵は <tag>_*.png。○× は 1 行ずつ。両方のログの時刻（壁の時計）で、ゆきの位置を比べる

const Snowball := preload("res://snowball.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var hub: Node
var duel: Node
var craft: Node
var fails := 0
var _t0 := 0
var _seen := {"my_catch": 0, "cpu_catch": 0, "hit_me": 0, "hit_cpu": 0, "throw_cpu": 0, "windup_cpu": 0, "gap_cpu": 0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 日時計（daycycle.gd）は current_scene に置く
	if args.has("dir"):
		DirAccess.make_dir_recursive_absolute(String(args.dir))
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _host() -> bool:
	return args.has("host")


func _tag() -> String:
	return "host" if _host() else ("join2" if args.has("second") else "join")


func _say(s: String) -> void:
	print("[%s %.3f] %s" % [_tag(), fmod(Time.get_unix_time_from_system(), 1000.0), s])


func _ok(cond: bool, what: String) -> void:
	_say(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _until(cond: Callable, limit: float) -> bool:
	var left := limit
	while not cond.call() and left > 0.0:
		await create_timer(0.05).timeout
		left -= 0.05
	return cond.call()


func _shot(nm: String) -> void:
	if not args.has("dir"):
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.dir).path_join("%s_%s.png" % [_tag(), nm]))
	_say("撮った: " + nm)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _place(at: Vector3) -> void:
	at.y = main.height(at.x, at.z) + main.snow_lift(at.x, at.z) + 0.15
	p.global_position = at
	p.velocity = Vector3.ZERO


func _face(at: Vector3) -> void:
	var to := at - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	var up: Vector3 = at + Vector3.UP * 1.0 - p.cam.global_position
	p.set("_pitch", atan2(up.y, Vector2(up.x, up.z).length()))


## 仲間の体: ホストは bot.gd、つなぐ側は写し（remote_person.gd）。番号 → 体
func _cpus() -> Dictionary:
	if not _host():
		return main.net.cpus
	var out := {}
	for b in get_nodes_in_group("bots"):
		out[b.id] = b
	return out


func _table(what: String) -> void:
	var c := _cpus()
	for id in c:
		var b: Node3D = c[id]
		var m: int = b.net_mode() if _host() else b.mode
		_say("%s 番号 %d 名前 %s 人形 %s 財布 %d 雪玉 %d 段 %d 持ち場 %s 所 (%.2f, %.2f, %.2f) 姿勢の段 %d 灯 %s" % [what, id, craft.name_of(id), b.doll.kind, craft.wallet(id),
			hub.balls_of(id), m, str(b.handle), b.global_position.x, b.global_position.y, b.global_position.z, b.doll.sit_stage, craft.lamp_on(id)])
	if main.seats:
		_say("%s 席の札 %s" % [what, str(main.seats.taken)])


func _yuki() -> Node3D:
	return _cpus().get(2)


func _run() -> void:
	p = main.player
	hub = main.emotes
	duel = main.duel
	craft = main.craft
	if args.has("second"):
		await _run_second()
		return
	hub.happened.connect(_note)
	if _host():
		await _run_host()
	else:
		await _run_join()


# ---------------------------------------------------------------- ホスト

func _want() -> int:
	return int(args.get("cpus", "5"))


## ゆきが丘を滑るのを見る（どちらの画面でも）。立つ所は左右に分ける
func _watch_ride() -> void:
	var y := _yuki()
	p.set_third(false)
	_place(Vector3(5.0 if _host() else -5.0, 0, 1.0))   # 頂上のそばから。どの向きへ滑っても見える
	var began: bool = await _until(func():
		_face(y.global_position)
		return (y.state == y.State.RIDE) if _host() else y.mode == y.Mode.RIDE, 70.0)
	_ok(began, "ゆきが米袋に乗った")
	if not began:
		return
	var gs: RigidBody3D = y.sled
	_ok(gs != null and gs.kind == "sack" and gs.name == "Sack2", "ゆきのソリは米袋: %s" % str(gs.name if gs else "なし"))
	if not _host():
		_ok(gs.net_follow, "つなぐ側の米袋は、ホストの米袋の姿を写す")
	var shot := false
	var t := 0.0
	while is_instance_valid(gs) and ((y.state == y.State.RIDE) if _host() else y.mode == y.Mode.RIDE) and t < 30.0:
		_face(y.global_position)
		_say("滑り ゆき (%.2f, %.2f, %.2f) 米袋の速さ %.2f" % [y.global_position.x, y.global_position.y, y.global_position.z, gs.linear_velocity.length()])
		if not shot and t > 2.0:
			shot = true
			_place(y.global_position + Vector3(4.5 if _host() else -4.5, 0, 0))   # 滑っている横のそばから
			_face(y.global_position)
			await _shot("1_ride_sack")
		await _wait(0.25)
		t += 0.25
	_table("滑り終わり")


func _run_host() -> void:
	await _wait(1.0)
	_ok(_cpus().size() == _want(), "ホストの画面の仲間: %d 人" % _cpus().size())
	var came: bool = await _until(func(): return not main.net.remotes.is_empty(), 30.0)
	_ok(came, "人が来た")
	if not came:
		quit(1)
		return
	var them_id: int = main.net.remotes.keys()[0]
	var y := _yuki()
	await _wait(2.0)
	for i in 4:
		_table("表 %d" % i)
		await _wait(1.0)
	# 1. 丘で滑るのを見る: ゆきを丘の途中へ運ぶ（山めぐりを待つと長いので）
	if y.state != y.State.RIDE:
		y.global_position = Vector3(6, main.height(6, 14) + 0.3, 14)
		y.roam_from("hill")
	await _watch_ride()
	# 2. つないだ人がソリをつかむと、手伝いに来る
	await _until(func(): return main.net.remotes[them_id].mode == 1, 40.0)
	_say("つないだ人がソリをつかんだ")
	var yat: Vector3 = main.sled.global_position + Vector3(6, 0, 0)
	if y.state != y.State.RIDE:
		y.global_position = Vector3(yat.x, main.height(yat.x, yat.z) + 0.3, yat.z)
		y.far = false
	var helped: bool = await _until(func(): return y.handle != Vector3.INF, 20.0)
	_ok(helped, "そばのゆきが、ソリをつかんで手伝いに来た")
	await _wait(1.0)
	_place(main.sled.global_position + Vector3(5, 0, 3))
	_face(main.sled.global_position)
	await _wait(0.3)
	await _shot("2_help")
	await _wait(2.0)
	# 頂上へ運ぶ（押して登ると長いので）
	var top := Vector3(0, main.height(0, 2) + 0.4 + main.sled.place_lift(), 2)
	var rode: bool = await _until(func():
		if y.state != y.State.RIDE or main.sled.riders.size() < 2:   # 2 人が乗るまで、頂上に留めておく（つかんでいた手を離すと、丸い頂上からすぐ滑り出すので）
			main.sled.global_position = top
			main.sled.linear_velocity = Vector3.ZERO
		return y.state == y.State.RIDE and y.sled == main.sled, 25.0)
	_ok(rode, "つないだ人が乗ると、ゆきも一緒に乗った")
	_place(main.sled.global_position + Vector3(4, 0, 4))
	_face(main.sled.global_position)
	await _wait(0.4)
	await _shot("3_ride")
	_table("乗っている")
	await _until(func(): return main.net.remotes[them_id].mode == 0 and y.state != y.State.RIDE, 40.0)
	_table("降りた")
	hub._set_balls(them_id, 1)
	# 3. 対決: ホストの人は、円の外から見ている
	var seen_bet: bool = await _until(func(): return not duel.of(them_id).is_empty(), 50.0)
	_ok(seen_bet, "つないだ人と仲間の対決が始まった")
	var d: Dictionary = duel.of(them_id)
	if d.is_empty():
		quit(fails + 1)
		return
	var foe_id: int = duel.opponent(d, them_id)
	_say("相手は %d %s" % [foe_id, craft.name_of(foe_id)])
	_place(d.at + Vector3(7.5, 0, 0))
	_face(d.at)
	var f0: int = craft.wallet(them_id)
	await _until(func(): return duel.of(them_id).get("phase", "") == "fight", 12.0)
	_table("始まった")
	_host_fight(them_id, foe_id)
	await _until(func(): return duel.of(them_id).is_empty(), 110.0)
	_ok(duel.of(them_id).is_empty(), "対決が終わった")
	await _wait(0.5)
	_table("払った")
	_say("つないだ人の財布 %d → %d" % [f0, craft.wallet(them_id)])
	_say("見たもの: %s" % str(_seen))
	# 4. 人が帰っても、仲間は残る
	var left: bool = await _until(func(): return main.net.remotes.is_empty(), 25.0)
	_ok(left, "つないだ人が帰った")
	await _wait(2.0)
	_ok(_cpus().size() == _want() and is_instance_valid(y), "人が帰っても、仲間はいる: %d 人" % _cpus().size())
	var was: Vector3 = y.global_position
	await _wait(3.0)
	_say("ゆきは動いている: %.2f m" % was.distance_to(y.global_position))
	_table("帰ったあと")
	# 2 人目が来て、席の札を確かめるのを待つ
	var again: bool = await _until(func(): return not main.net.remotes.is_empty(), 40.0)
	if again:
		var them2: int = main.net.remotes.keys()[0]
		var sat: bool = await _until(func(): return main.seats.seat_of.has(them2), 25.0)
		_ok(sat, "つないだ人が座った席が、ホストの席の札に入った: %s" % str(main.seats.seat_of.get(them2, -1)))
		await _wait(3.0)
	_say("おわり: ×の数 %d" % fails)
	quit(fails)


## ホスト: 対決を見ている。仲間が「取る」場面を作る（当たる球は次の球。CATCH_ODDS を待つと長いので、1 球目だけ取りにいかせる）
func _host_fight(them_id: int, foe_id: int) -> void:
	var foe: Node3D = hub.who_of(foe_id)
	var made_catch := {"done": false}   # 無名関数の中で書き換えるので辞書に
	var cb := func(ev: Dictionary):
		if ev.kind == "throw" and int(ev.who) == them_id:
			if not made_catch.done:
				made_catch.done = true
				foe.set("_catching", int(ev.ball))
			else:
				foe.set("_catching", -1)   # 2 球目から: 受ける
				foe.set("_dodge_t", 0.0)
	hub.happened.connect(cb)
	while not duel.of(them_id).is_empty():
		var d: Dictionary = duel.of(them_id)
		if d.is_empty():
			break
		_face(d.at + Vector3.DOWN * 0.3)
		await process_frame
	hub.happened.disconnect(cb)


# ---------------------------------------------------------------- つなぐ側

func _run_join() -> void:
	await _until(func(): return main.net.joined() and main.net.cpus.size() >= _want(), 20.0)
	_ok(main.net.cpus.size() == _want(), "あとから来ても、つなぐ側の画面に仲間が見える: %d 人" % main.net.cpus.size())
	_ok(get_nodes_in_group("bots").is_empty(), "つなぐ側の画面では bot.gd を動かさない")
	_ok(not main.net.remotes.has(2) and main.net.remotes.size() == 1, "来ている人の数に仲間を入れない: %d" % main.net.remotes.size())
	await _wait(1.0)
	for i in 4:
		_table("表 %d" % i)
		await _wait(1.0)
	var y := _yuki()
	_ok(craft.name_of(2) == "ゆき", "1 人目の仲間の名前は %s" % craft.name_of(2))
	_ok(craft.wallet(2) == 50, "ゆきの財布は %d（のぞみ 50）" % craft.wallet(2))
	_ok(y.doll.kind == "origami", "ゆきの人形は %s" % y.doll.kind)
	_ok(main.has_node("Pals2"), "ゆきの頭の小物・ミニオンがある")
	var seated := 0
	for id in main.seats.taken:
		if main.net.cpus.has(main.seats.taken[id]):
			seated += 1
	_ok(seated == _want() - 5, "つなぐ側の席の札に、ロッジの仲間の席が入っている: %d" % seated)
	# 1. 丘で滑るのを見る
	await _watch_ride()
	# 2. ソリをつかむと、手伝いに来る
	var s: RigidBody3D = main.sled
	p.global_position = s.to_global(Vector3(0, 0, s.HALF.y + 0.7)) + Vector3.UP * 0.2
	p.velocity = Vector3.ZERO
	var fwd: Vector3 = -s.global_basis.z
	p.rotation.y = atan2(-fwd.x, -fwd.z)
	await _wait(0.3)
	p.grab()
	_ok(int(p.mode) == 1, "ソリをつかんだ: 段 %d" % p.mode)
	var helped: bool = await _until(func(): return y.mode == y.Mode.GRIP and s.holders.has(y), 25.0)
	_ok(helped, "つなぐ側でも、ゆきがソリをつかんでいる: 段 %d" % y.mode)
	await _wait(1.0)
	await _shot("2_help")
	# 3. 一緒に乗る: ホストが頂上へ運ぶ
	await _until(func(): return Vector2(s.global_position.x, s.global_position.z).length() < 6.0, 20.0)
	await _wait(1.0)
	p.get_on()
	if int(p.mode) != 2:
		p.global_position = s.global_position + Vector3(1.5, 0.3, 0)
		await _wait(0.2)
		p.get_on()
	_ok(int(p.mode) == 2, "乗った: 段 %d 席 %s" % [p.mode, str(p.seat)])
	await _until(func(): return y.mode == y.Mode.RIDE, 20.0)
	_ok(y.mode == y.Mode.RIDE and s.riders.has(y), "つなぐ側でも、ゆきが同じソリに乗った: 席 %s（わたしの席 %s）" % [str(y.seat), str(p.seat)])
	_ok(y.seat != p.seat, "席は別")
	_table("乗っている")
	await _wait(0.5)
	await _shot("3_ride")
	# 体重をかけて下り、止まったら降りる
	_key(KEY_W, true)
	await _wait(6.0)
	_key(KEY_W, false)
	await _until(func(): return s.linear_velocity.length() < 0.4, 20.0)
	await _wait(0.5)
	p.get_off()
	var off: bool = await _until(func(): return y.mode != y.Mode.RIDE, 25.0)
	_table("降りた")
	_ok(off, "ゆきも降りた: 段 %d" % y.mode)
	# 4. 対決: 雪玉はホストからもらう。ゆきのそばで低い手のひら
	await _until(func(): return hub.balls_of(p.id) >= 1, 15.0)
	await _duel_with(y)
	_say("見たもの: %s" % str(_seen))
	_say("帰る: ×の数 %d" % fails)
	quit(fails)


func _duel_with(y: Node3D) -> void:
	var off: Vector3 = (Vector3(y.global_position.x, 0, y.global_position.z)).normalized() * 3.0
	_place(y.global_position + off)
	await _wait(0.5)
	_face(y.global_position)
	p.set_height("low")
	var began: bool = await _until(func():
		_face(y.global_position)
		return duel.of(p.id).get("phase", "") == "bet", 25.0)
	_ok(began, "握手で掛金の画面へ")
	if not began:
		return
	var foe_id: int = duel.opponent(duel.of(p.id), p.id)
	var foe: Node3D = hub.who_of(foe_id)
	_say("相手は %d %s" % [foe_id, craft.name_of(foe_id)])
	await _wait(0.2)
	_ok(main.duel_hud.bet_open, "掛金の画面が開いた")
	main.duel_hud.nudge(10, 1)
	await _wait(0.4)
	await _shot("5_bet")
	var w0: int = craft.wallet(p.id)
	var f0: int = craft.wallet(foe_id)
	var fought: bool = await _until(func(): return not duel.fighting(p.id).is_empty(), 7.0)
	_ok(fought, "仲間が掛金 10 を受けて始まった")
	await _wait(0.1)
	_ok(craft.wallet(p.id) == w0 - 10 and craft.wallet(foe_id) == f0 - 10, "2 人の財布から 10 ずつ預けた: %d %d" % [craft.wallet(p.id), craft.wallet(foe_id)])
	_ok(hub.balls_of(p.id) == 3 and hub.balls_of(foe_id) == 3, "雪玉は 3 つずつ: %d %d" % [hub.balls_of(p.id), hub.balls_of(foe_id)])
	await _fight(foe, foe_id)
	var d: Dictionary = duel.of(p.id)
	_table("決まった")
	_ok(d.get("phase", "") == "over", "勝ち負けが決まった: 勝ち %s" % str(d.get("winner", "なし")))
	await _shot("9_over")
	# 払いの握手: 仲間が手を出しに来る
	await _until(func(): return hub.hands.has(foe_id), 12.0)
	await _wait(0.5)
	_face(foe.global_position)
	p.set_height("low")
	var paid: bool = await _until(func():
		_face(foe.global_position)
		return duel.of(p.id).is_empty(), 25.0)
	_ok(paid, "握手で払った")
	await _wait(0.5)
	var won: int = int(d.get("winner", -1))
	_ok(craft.wallet(p.id) == w0 + (10 if won == p.id else -10 if won == foe_id else 0) and craft.wallet(foe_id) == f0 + (10 if won == foe_id else -10 if won == p.id else 0),
		"財布: わたし %d 仲間 %d（握手の前は %d・%d、勝ち %d）" % [craft.wallet(p.id), craft.wallet(foe_id), w0, f0, won])
	_table("払った")


## 相手を見て立ち、ねらって投げる。1 球目は取り、2 球目は受ける。3 球目からは取りにいく（先に負けないように）
func _fight(y: Node3D, foe_id: int) -> void:
	var incoming := 0
	var seen_balls := {}
	var shot := {}
	while not duel.fighting(p.id).is_empty():
		_face(y.global_position)
		for b in hub.get_children():
			if not (b is Snowball) or b.thrower != foe_id or b._done or b.ball_id < 0:
				continue
			if not seen_balls.has(b.ball_id):
				seen_balls[b.ball_id] = true
				incoming += 1
				if not shot.has("ball"):
					shot["ball"] = true
					_shot("6_ball_coming")
			if incoming != 2 and b.global_position.distance_to(duel._chest(p)) < duel.CATCH_REACH:
				duel.send({"kind": "catch", "who": p.id, "ball": b.ball_id})
		if hub.can_throw(p.id) and not p.rooted():
			if hub.balls_of(p.id) >= 1:
				_throw_at(y)
				await _wait(0.1)
				if not shot.has("gap"):
					shot["gap"] = true
					_say("投げの間: わたしの残りのコマ %d" % duel.throw_wait(p.id))
					_ok(duel.throw_wait(p.id) > 0, "投げたあとの間が、つなぐ側の時計で動いている")
					await _shot("7_gap")
			else:
				hub.send({"kind": "make_ball", "who": p.id})
				await _wait(2.0)
		await process_frame


func _throw_at(y: Node3D) -> void:
	var fwd: Vector3 = (y.global_position - p.global_position)
	fwd.y = 0
	var origin: Vector3 = p.global_position + Vector3.UP * 1.3 + fwd.normalized() * 0.5
	var target: Vector3 = y.global_position + Vector3.UP * y.doll.height() * 0.6
	var flat: Vector3 = target - origin
	flat.y = 0
	var t: float = maxf(flat.length() / 14.0, 0.05)
	var vel: Vector3 = flat.normalized() * 14.0 + Vector3.UP * ((target.y - origin.y + 4.9 * t * t) / t)
	hub.send({"kind": "throw", "who": p.id, "origin": origin, "velocity": vel})


# ---------------------------------------------------------------- 2 人目（あとから来た人・席の札・ホストが帰る）

func _run_second() -> void:
	await _until(func(): return main.net.joined() and main.net.cpus.size() >= _want() and main.seats != null and not main.seats.seats.is_empty(), 20.0)
	_ok(main.net.cpus.size() == _want(), "人が帰ったあとに来ても、仲間が見える: %d 人" % main.net.cpus.size())
	await _wait(1.5)
	_table("つないだとき")
	var taken_by_cpu := -1
	for s in main.seats.taken:
		if main.net.cpus.has(main.seats.taken[s]):
			taken_by_cpu = int(s)
	_ok(taken_by_cpu >= 0, "席の札に仲間の席がある: %d" % taken_by_cpu)
	_ok(not main.seats.send({"kind": "sit", "who": p.id, "seat": taken_by_cpu}), "仲間が座っている席には座れない")
	_ok(not main.seats.near(main.seats.seat(taken_by_cpu).stand, main.seats.seat(taken_by_cpu).face) == taken_by_cpu, "F の案内にも、仲間の席は出ない")
	var free_seat := -1
	for i in main.seats.seats.size():
		if not main.seats.taken.has(i):
			free_seat = i
			break
	_ok(main.seats.send({"kind": "sit", "who": p.id, "seat": free_seat}), "空いた席には座れる: %d" % free_seat)
	var y := _yuki()
	var gone: bool = await _until(func(): return not main.net.online, 40.0)
	_ok(gone, "ホストが帰った")
	await _wait(0.5)
	_ok(main.net.cpus.is_empty() and not is_instance_valid(y) and not main.has_node("Pals2"), "ホストが帰ると、仲間もいなくなる（人と同じ）")
	_ok(not main.seats.seat_of.has(2) and main.seats.taken.values().all(func(w): return w == p.id), "席の札も空いた: %s" % str(main.seats.taken))
	_say("おわり: ×の数 %d" % fails)
	quit(fails)


# ---------------------------------------------------------------- 出来事

func _note(ev: Dictionary) -> void:
	var me_id: int = p.id
	var is_cpu: bool = _cpus().has(int(ev.get("who", -1)))
	match String(ev.kind):
		"windup":
			if is_cpu:
				_seen.windup_cpu += 1
				if _seen.windup_cpu == 1:
					_say("仲間が振りかぶった")
					_shot("6_windup")
		"throw":
			if is_cpu:
				_seen.throw_cpu += 1
				var gap: int = duel.throw_wait(int(ev.who))
				if gap > 0:
					_seen.gap_cpu += 1
				if _seen.throw_cpu == 1:
					_ok(gap > 0, "仲間が投げたあとの間が、この画面の時計で動いている: 残り %d コマ" % gap)
		"catch":
			var mine: bool = not is_cpu
			_seen["my_catch" if mine else "cpu_catch"] += 1
			if _seen["my_catch" if mine else "cpu_catch"] == 1:
				_after_catch(mine)
		"hit":
			if not ev.get("star", false):
				return
			var cpu: bool = is_cpu
			_seen["hit_cpu" if cpu else "hit_me"] += 1
			if _seen["hit_cpu" if cpu else "hit_me"] == 1:
				_after_hit(cpu, me_id)


func _after_catch(mine: bool) -> void:
	await _wait(0.25)
	var n: int = hub.get_children().filter(func(c): return c is CPUParticles3D and c.amount == 20).size()
	_ok(n >= 1, "%sが取った: この画面の紙吹雪 %d" % ["人" if mine else "仲間", n])
	await _shot("8_catch_%s" % ("human" if mine else "cpu"))


func _after_hit(cpu: bool, _me: int) -> void:
	await _wait(0.1)
	var n: int = hub.get_children().filter(func(c): return c is MeshInstance3D and c.material_override is StandardMaterial3D and c.material_override.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED).size()
	_ok(n >= 1, "%sに当たった: この画面の星 %d" % ["仲間" if cpu else "人", n])
	await _shot("8_hit_%s" % ("cpu" if cpu else "human"))
