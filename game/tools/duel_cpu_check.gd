extends SceneTree
## コンピューターの仲間と雪合戦を 2 戦する確かめ（ふつうに起動したときと同じ引数で。--duel-bot は付けない）。
##   数字だけ: Godot --headless --fixed-fps 60 --path game -s res://tools/duel_cpu_check.gd -- --no-sound
##   仲間が 2 人のとき（見ている相手だけが応じるか）は --bots=2 を足す
##   絵も撮る: Godot --fixed-fps 60 --path game --resolution 1280x720 -s res://tools/duel_cpu_check.gd -- --no-sound --hud-idle=0 --dir=/path/shots
## 遊ぶ人と同じ道を通す: しゃがんで雪玉を作る → 低い手のひら → 仲間が雪玉を作って握手しに来る → 掛金の画面 → 戦い。
## 1 戦目は立っているだけで負ける（仲間の雪玉で 3 つ減る）。2 戦目からは横へ歩きながら仲間をねらって投げて勝つ（負けたらもう 1 戦、5 戦まで）。
## どちらも握手で払い、元の遊びに戻るまで見る。

const Snowball := preload("res://snowball.gd")
const Duel := preload("res://duel.gd")

var args := {}
var main: Node3D
var p: Node3D
var hub: Node
var duel: Node
var craft: Node
var foe: Node3D
var fails := 0
var _seen := {"throw": 0, "windup": 0, "catch": 0, "hit_me": 0, "hit_foe": 0, "make": 0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 日時計（daycycle.gd）は current_scene に置く
	_run.call_deferred()


## ゲームの中の秒（--fixed-fps では時計より速く進む）
func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


func _say(s: String) -> void:
	print("[%.1f] %s" % [_now(), s])


func _ok(cond: bool, what: String) -> void:
	_say(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if not args.has("dir"):
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.dir).path_join(name + ".png"))
	_say("撮った: " + name)


## cond が true になるまで待つ（長くても limit 秒）。なったら true
func _until(cond: Callable, limit: float) -> bool:
	var left := limit
	while not cond.call() and left > 0.0:
		await create_timer(0.05).timeout
		left -= 0.05
	return cond.call()


func _face(at: Vector3) -> void:
	var to := at - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	var up: Vector3 = at + Vector3.UP * 1.0 - p.cam.global_position   # 坂でも相手の胸を見る
	p.set("_pitch", atan2(up.y, Vector2(up.x, up.z).length()))


## 遊ぶ人と同じ: Ctrl でしゃがんで F で雪玉を作る（player.gd）
func _make_ball() -> void:
	var n: int = hub.balls_of(p.id)
	var pitch: float = p.get("_pitch")
	p.set("_pitch", -1.35)   # 足もとの雪を見る
	_key(KEY_CTRL, true)
	for i in 4:
		await physics_frame
	_key(KEY_F, true)
	_key(KEY_F, false)
	await _until(func(): return hub.balls_of(p.id) > n and not p.rooted(), 4.0)
	_key(KEY_CTRL, false)
	p.set("_pitch", pitch)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## 低い手のひらを出して、仲間が来て握手するまで。掛金の画面が開いたら true
func _offer() -> bool:
	_face(foe.global_position)
	p.set_height("low")
	return await _until(func(): return duel.of(p.id).get("phase", "") == "bet", 15.0)


## 仲間の前で投げる（長く振りかぶって、体のまんなかをねらう。遊ぶ人と同じ wind_up・throw_ball）
func _throw_at_foe() -> void:
	_face(foe.global_position)
	p.wind_up()
	await _wait(0.5)
	for k in [KEY_A, KEY_D]:   # 投げる前に足を止める
		_key(k, false)
	await _wait(0.3)
	_face(foe.global_position)
	var to: Vector3 = foe.global_position + Vector3.UP * 1.0 - p.cam.global_position
	p.set("_pitch", atan2(to.y, Vector2(to.x, to.z).length()) - 0.14)
	await physics_frame
	p.throw_ball()


## 勝ち負けのあと: 手のひらを出して、仲間と握手して払う。払われて元の遊びに戻るまで見る
func _settle(what: String, wallet_want: int, foe_want: int) -> void:
	await _wait(0.2)
	await _shot(what + "_3_おわり")
	_ok(not main.duel_focus, "%s: 勝ち負けが決まって、ふだんの HUD に戻った" % what)
	await _until(func(): return foe.get("_shape") != "", 10.0)
	_face(foe.global_position)
	await _shot(what + "_4_仲間が手を出す")
	p.set_height("low")
	var paid: bool = await _until(func(): return duel.of(p.id).is_empty(), 12.0)
	_ok(paid, "%s: 握手で対決が終わった" % what)
	_ok(craft.wallet(p.id) == wallet_want and craft.wallet(foe.id) == foe_want, "%s: 財布 あなた %d 仲間 %d（のぞみ %d・%d）" % [what, craft.wallet(p.id), craft.wallet(foe.id), wallet_want, foe_want])
	await _wait(0.1)
	_ok(not p.menu_open and not p.fp_locked and not main.duel_hud.bet_open, "%s: 操作も元どおり（画面を閉じて、視点の固定も解けた）" % what)
	await _wait(2.5)
	await _shot(what + "_5_元の遊び")
	# あなたが仲間とソリのあいだに立っていても、回って戻れるか
	var toward: Vector3 = foe.sled.global_position - foe.global_position
	toward.y = 0
	var lane: Vector3 = foe.global_position + toward.normalized() * 0.9
	lane.y = main.height(lane.x, lane.z) + 0.15
	p.global_position = lane
	p.velocity = Vector3.ZERO
	_face(foe.global_position)
	var back: bool = await _until(func(): return foe.handle != Vector3.INF or foe.state != foe.State.PUSH, 25.0)
	_ok(back, "%s: 仲間がソリに戻った（つかんだ、または頂上・乗る）: %s" % [what, foe.debug])
	if not back:
		var sl: RigidBody3D = foe.sled
		_say("戻れない: 仲間 %s 速さ %s 床 %s ／ ソリ %s 向き上 %s 速さ %.2f 回転 %s ／ あなた %s ／ 仲間の手 %s _five_with %d _regrab %.1f" % [foe.global_position, foe.velocity, foe.is_on_floor(), sl.global_position, sl.global_basis.y, sl.linear_velocity.length(), sl.rotation, p.global_position, foe.get("_shape"), foe.get("_five_with"), foe.get("_regrab")])
		_say("  ソリ座標の仲間 %s holders %s" % [sl.to_local(foe.global_position), sl.holders.size()])


func _run() -> void:
	if args.has("dir"):
		DirAccess.make_dir_recursive_absolute(String(args.dir))
	await _wait(1.0)
	p = main.player
	hub = main.emotes
	duel = main.duel
	craft = main.craft
	var bots: Array = main.get_children().filter(func(c): return c.get_script() == main.Bot and not c.lounge)
	_ok(bots.size() >= 1, "ふつうの起動で、ソリの仲間がいる: %d 人" % bots.size())
	foe = bots[0]
	p.set_third(false)
	hub.happened.connect(_note)
	# しばらくソリを押してもらう（ふだんの遊びの途中から）
	await _wait(3.0)
	var at: Vector3 = foe.global_position
	var near := at + Vector3(2.5, 0, 2.5)
	near.y = main.height(near.x, near.z) + 0.15
	p.global_position = near
	p.velocity = Vector3.ZERO
	_ok(hub.balls_of(foe.id) == 0, "仲間はまだ雪玉を持っていない")
	# 雪玉を持たずに手を出すと、ふつうの握手で終わる（対決にならない）
	_face(foe.global_position)
	p.set_height("low")
	var shook: bool = await _until(func(): return not hub.hands.has(p.id), 12.0)
	await _wait(0.5)
	_say("雪玉なしで握手: 手を下ろした %s、仲間の手 %s" % [shook, foe.get("_shape")])
	_ok(shook and duel.of(p.id).is_empty() and hub.balls_of(foe.id) == 0, "雪玉なしの握手は対決にならない（仲間も作らない）")
	await _wait(2.0)

	# ---- 1 戦目: 立っているだけで負ける（掛金 10）
	var stand: Vector3 = foe.global_position + Vector3(3.0, 0, 3.0)
	stand.y = main.height(stand.x, stand.z) + 0.15
	p.global_position = stand
	p.velocity = Vector3.ZERO
	await _wait(0.5)   # 足が雪に着くまで
	await _make_ball()
	_ok(hub.balls_of(p.id) >= 1, "雪玉を作った: %d" % hub.balls_of(p.id))
	# 作っているあいだにソリは先へ行くので、また仲間のそばへ（2 人なら、もう 1 人を視野の外へ）
	stand = foe.global_position + Vector3(0, 0, 3.5)
	stand.y = main.height(stand.x, stand.z) + 0.15
	p.global_position = stand
	p.velocity = Vector3.ZERO
	if bots.size() > 1:
		var off: Vector3 = foe.global_position + Vector3(4.5, 0, 0)
		off.y = main.height(off.x, off.z) + 0.15
		bots[1].let_go()
		bots[1].global_position = off
	await _wait(0.3)
	_face(foe.global_position)
	p.set_height("low")
	await _wait(1.0)
	await _shot("00_仲間が雪玉を作る")
	var made: bool = await _until(func(): return hub.balls_of(foe.id) >= 1, 5.0)
	_ok(made and _seen.make >= 1, "手のひらを出すと、仲間が雪玉を作った")
	await _wait(0.8)
	await _shot("01_仲間が握手しに来る")
	var began: bool = await _until(func(): return duel.of(p.id).get("phase", "") == "bet", 15.0)
	_ok(began, "握手で掛金の画面へ")
	if not began:
		quit(fails + 1)
		return
	await _wait(0.1)
	_ok(main.duel_hud.bet_open and p.menu_open, "掛金の画面が開いた")
	if bots.size() > 1:
		_ok(bots[1].get("_five_with") == -1, "見ていない仲間は応じない")
		bots[1].process_mode = Node.PROCESS_MODE_DISABLED   # ここから先は 1 人を相手に（見た先に立っていると、そちらが応じるので）
		bots[1].global_position += Vector3(40, 0, 0)
	# やめる → 元の遊びに戻る → もう一度申し込める
	main.duel_hud.cancel()
	await _wait(0.2)
	_ok(duel.of(p.id).is_empty() and not main.duel_hud.bet_open and not p.menu_open, "× でやめると、元の遊びに戻る")
	await _wait(1.0)
	began = await _offer()
	_ok(began, "やめたあと、もう一度握手で掛金の画面へ")
	if not began:
		quit(fails + 1)
		return
	await _wait(0.1)
	var w0: int = craft.wallet(p.id)
	var f0: int = craft.wallet(foe.id)
	main.duel_hud.nudge(10, 1)
	await _wait(0.5)
	await _shot("02_掛金")
	var fighting: bool = await _until(func(): return not duel.fighting(p.id).is_empty(), foe.BET_WAIT + 2.0)
	_ok(fighting, "仲間が掛金 10 を受けて始まった")
	_ok(craft.wallet(p.id) == w0 - 10 and craft.wallet(foe.id) == f0 - 10, "2 人の財布から 10 ずつ預けた")
	_ok(hub.balls_of(foe.id) == 3, "仲間の雪玉は 3 つ")
	await _wait(0.4)
	_ok(main.duel_focus, "ふだんの HUD をよけて一人称に")
	await _shot("03_戦いの始まり")
	# 仲間のほうを見て立っている（当たるたびにハートが減る）
	var shot_wind := false
	var shot_ball := false
	var shot_hit := false
	var lives_seen: Array = []
	var t_begin := _now()
	while duel.of(p.id).get("phase", "") == "fight":
		_face(foe.global_position)
		var d: Dictionary = duel.of(p.id)
		var lives := Duel.lives_of(d, p.id)
		if lives_seen.is_empty() or lives_seen[-1] != lives:
			lives_seen.append(lives)
		if not shot_hit and lives < Duel.LIVES:
			shot_hit = true
			await _shot("06_当たってハートが減る")
		elif not shot_wind and foe.get("_wind") >= 0.0:
			shot_wind = true
			await _shot("04_仲間が振りかぶる")
		elif not shot_ball and _ball_near():
			shot_ball = true
			await _shot("05_雪玉が飛んでくる")
		await process_frame
	var d1: Dictionary = duel.of(p.id)
	_say("1 戦目の長さ %.1f 秒、ハートの残り %s" % [_now() - t_begin, str(lives_seen)])
	_ok(_seen.windup >= 1 and _seen.throw >= 1, "仲間が振りかぶって投げてきた: 振りかぶり %d 投げ %d" % [_seen.windup, _seen.throw])
	_ok(lives_seen == [3, 2, 1, 0] or lives_seen == [3, 2, 1], "当たるたびにハートが 1 つ減った: %s" % str(lives_seen))
	_ok(d1.get("phase", "") == "over" and int(d1.winner) == foe.id, "立っているだけで負けた（勝ち %s）" % str(d1.get("winner", "なし")))
	await _settle("負け", w0 - 10, f0 + 10)

	# ---- 2 戦目から: 歩きながら投げて勝つ（掛金 5）
	var won := false
	for round_i in 5:
		await _wait(1.0)
		var spot: Vector3 = foe.global_position + Vector3(2.0, 0, 2.0)
		spot.y = main.height(spot.x, spot.z) + 0.15
		p.global_position = spot
		p.velocity = Vector3.ZERO
		await _wait(0.5)
		if hub.balls_of(p.id) < 1:
			await _make_ball()
		began = await _offer()
		_ok(began, "%d 戦目: また握手で掛金の画面へ" % (round_i + 2))
		if not began:
			quit(fails + 1)
			return
		await _wait(0.2)
		w0 = craft.wallet(p.id)
		f0 = craft.wallet(foe.id)
		main.duel_hud.nudge(5, 1)
		fighting = await _until(func(): return not duel.fighting(p.id).is_empty(), foe.BET_WAIT + 2.0)
		_ok(fighting, "%d 戦目: 掛金 5 で始まった" % (round_i + 2))
		won = await _fight_moving()
		var d2: Dictionary = duel.of(p.id)
		if won:
			await _settle("勝ち", w0 + 5, f0 - 5)
			break
		await _settle("%d戦目の負け" % (round_i + 2), w0 - (5 if int(d2.winner) == foe.id else 0), f0 + (5 if int(d2.winner) == foe.id else 0))
	_ok(won, "投げて勝てた")
	_say("見たもの: %s" % str(_seen))
	_say("おわり: ×の数 %d" % fails)
	quit(fails)


## 横へ歩きながら、仲間へ投げ続ける。雪玉がなくなれば作る。勝ったら true
func _fight_moving() -> bool:
	var tries := 0
	var hits0: int = _seen.hit_foe
	var catches0: int = _seen.catch
	var me0: int = _seen.hit_me
	var thrown0: int = _seen.throw
	var side := KEY_A
	while duel.of(p.id).get("phase", "") == "fight":
		if p.rooted():
			await process_frame
			continue
		if hub.balls_of(p.id) < 1:
			_key(side, false)
			await _make_ball()
			continue
		side = KEY_D if side == KEY_A else KEY_A
		_key(side, true)
		tries += 1
		await _throw_at_foe()
		if tries == 2:
			await _shot("07_こちらが投げる")
		await _wait(0.3)
		_key(side, false)
	_key(KEY_A, false)
	_key(KEY_D, false)
	var d: Dictionary = duel.of(p.id)
	_say("戦い: こちら 投げ %d 当て %d 取られ %d ／ 仲間 投げ %d 当て %d" % [tries, _seen.hit_foe - hits0, _seen.catch - catches0, _seen.throw - thrown0, _seen.hit_me - me0])
	return d.get("phase", "") == "over" and int(d.winner) == p.id


func _note(ev: Dictionary) -> void:
	match String(ev.kind):
		"throw":
			if int(ev.who) == foe.id:
				_seen.throw += 1
		"windup":
			if int(ev.who) == foe.id:
				_seen.windup += 1
		"make_ball":
			if int(ev.who) == foe.id:
				_seen.make += 1
		"catch":
			if int(ev.who) == foe.id:
				_seen.catch += 1
		"hit":
			if int(ev.who) == p.id:
				_seen.hit_me += 1
			elif int(ev.who) == foe.id:
				_seen.hit_foe += 1


func _ball_near() -> bool:
	for b in hub.get_children():
		if b is Snowball and b.thrower == foe.id and not b._done and b.global_position.distance_to(p.global_position) < 3.0:
			return true
	return false
