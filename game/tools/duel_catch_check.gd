extends SceneTree
## 雪合戦のキャッチの猶予を測る（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/duel_catch_check.gd -- --no-sound --bots=1 --lodge-bots=0
## 相手の胸を見て立っているとき、飛んでくる雪玉に F が効くのは何秒か。投げる速さと距離ごとに、それから仲間の投げ方（ずれあり）で。
## 距離と照準の組み合わせの表は --grid で（CATCH_READY・CATCH_AIM を決めるときに）。
## そのあと、F で取る・近すぎて間に合わない・投げたあとのインターバル・よけてから雪玉を作る間を、遊ぶ人の操作で確かめる。

const Duel := preload("res://duel.gd")
const AT := Vector3(14, 0, 16)
const SPREAD_SHOTS := 30

var args := {}
var main: Node3D
var p: Node3D
var foe: Node3D
var hub: Node
var duel: Node
var fails := 0
var _last_ball := -1
var _hits := 0
var _track := []             # いまの雪玉の、コマごとの [胸からの距離, 照準のずれ]
var _grid := {}              # "距離,照準" → 当たった玉の、F が効いたコマの並び（--grid）
const GRID_READY := [0.8, 1.6, 2.0, 2.4, 2.8]
const GRID_AIM := [0.08, 0.12, 0.16, 0.20, 0.25]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _say(s: String) -> void:
	print(s)


func _ok(cond: bool, what: String) -> void:
	_say(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _place(n: Node3D, at: Vector3, look: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.15
	n.global_position = at
	n.velocity = Vector3.ZERO
	n.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))


## 相手の胸を見る（人がふつうにする見方）
func _look_at_foe() -> void:
	var to: Vector3 = foe.global_position + Vector3.UP * foe.doll.height() * 0.78 - p.cam.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	p.set("_pitch", atan2(to.y, Vector2(to.x, to.z).length()))


func _reset() -> void:
	var d: Dictionary = duel.of(p.id)
	d.hits_a = 0
	d.hits_b = 0
	d.until = Duel.Doll.frame_index() + 60 * Duel.Doll.FPS
	duel._guard.clear()
	duel._gap_until.clear()
	hub._set_balls(foe.id, 5)
	hub._set_balls(p.id, 3)


## 仲間の位置から p の胸へ、ずれなしで投げる
func _throw_straight(speed: float) -> void:
	var origin: Vector3 = foe.global_position + Vector3.UP * foe.doll.height() * 0.85 + (p.global_position - foe.global_position).normalized() * 0.45
	var target: Vector3 = p.global_position + Vector3.UP * p.doll.height() * 0.6
	var flat := target - origin
	flat.y = 0
	var t := flat.length() / speed
	var vy := (target.y - origin.y + 4.9 * t * t) / t
	hub.send({"kind": "throw", "who": foe.id, "origin": origin, "velocity": flat.normalized() * speed + Vector3.UP * vy})


## いま投げた雪玉がなくなるまで、F が効くコマを数える。[効いたコマ, 飛んだコマ, 当たった, 手の届く所にいたコマ, そのあいだの照準のずれの最小（画面の高さに対して）]
## follow: 雪玉を目で追う（画面のまんなかに置き続ける）
func _watch_ball(follow := false) -> Array:
	var frames := 0
	var flown := 0
	var near := 0
	var off := INF
	var hits0 := _hits
	_track = []
	var reach: float = duel.CATCH_READY
	var mid: Vector2 = p.cam.get_viewport().get_visible_rect().size / 2.0
	while hub.ball(_last_ball) != null and flown < 240:
		await physics_frame
		flown += 1
		var b: Node3D = hub.ball(_last_ball)
		if b == null:
			break
		if follow:
			var to: Vector3 = b.global_position - p.cam.global_position
			p.rotation.y = atan2(-to.x, -to.z)
			p.set("_pitch", atan2(to.y, Vector2(to.x, to.z).length()))
		if not p.cam.is_position_behind(b.global_position):
			_track.append([b.global_position.distance_to(duel._chest(p)), p.cam.unproject_position(b.global_position).distance_to(mid) / (mid.y * 2.0)])
		if b.global_position.distance_to(duel._chest(p)) <= reach:
			near += 1
			if not p.cam.is_position_behind(b.global_position):
				off = minf(off, p.cam.unproject_position(b.global_position).distance_to(mid) / (mid.y * 2.0))
		var c = duel.catchable(p, p.cam, foe.id)
		if c != null and c.ball_id == _last_ball:
			frames += 1
	await _wait(0.3)   # 当てるのを少し待つ（park_hit）
	return [frames, flown, _hits > hits0, near, off]


func _run() -> void:
	await _wait(1.0)
	p = main.player
	hub = main.emotes
	duel = main.duel
	foe = main.get_children().filter(func(c): return c.get_script() == main.Bot and not c.lounge)[0]
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	p.set_third(false)
	hub.happened.connect(func(ev):
		if ev.kind == "throw":
			_last_ball = int(ev.ball)
		elif ev.kind == "hit" and int(ev.who) == p.id:
			_hits += 1)
	# 戦いを始める（握手と掛金は飛ばす）
	_place(p, AT, AT + Vector3(0, 0, 1))
	_place(foe, AT + Vector3(0, 0, 0.8), AT)
	hub._set_balls(p.id, 3)
	hub._set_balls(foe.id, 3)
	duel._shook(p.id, foe.id)
	duel._apply({"kind": "ok", "who": p.id})
	duel._apply({"kind": "ok", "who": foe.id})
	await _wait(0.5)
	_ok(not duel.fighting(p.id).is_empty(), "戦いが始まった")
	_say("--- ずれなし")
	for row in [[5.0, 10.0], [5.0, 16.0], [5.0, 7.0], [3.0, 10.0], [3.0, 7.0], [2.0, 7.0]]:
		_place(foe, AT + Vector3(0, 0, -row[0] * 0.5), AT)
		_place(p, AT + Vector3(0, 0, row[0] * 0.5), AT)
		await _wait(0.4)
		_reset()
		_look_at_foe()
		await _wait(0.1)
		_throw_straight(row[1])
		var r: Array = await _watch_ball()
		await _wait(1.4)   # のけぞりで視線がぶれなくなるまで
		_reset()
		_look_at_foe()
		await _wait(0.1)
		_throw_straight(row[1])
		var f: Array = await _watch_ball(true)
		_say("%.0f m / %2.0f m/s 飛ぶ %.3f 秒 届く所 %.3f 秒 ／ 相手の胸を見たまま F が効く %.3f 秒（ずれ最小 %.3f）／ 玉を目で追って F が効く %.3f 秒" % [row[0], row[1], r[1] / 60.0, r[3] / 60.0, r[0] / 60.0, r[4], f[0] / 60.0])
		await _wait(1.4)
	_say("--- 仲間の投げ方（ずれあり）を 5 m から %d 回" % SPREAD_SHOTS)
	_place(foe, AT + Vector3(0, 0, -2.5), AT)
	_place(p, AT + Vector3(0, 0, 2.5), AT)
	var hit_n := 0
	var none := 0
	var total := 0
	var least := 9999
	for i in SPREAD_SHOTS:
		await _wait(0.2)
		_reset()
		_look_at_foe()
		await _wait(0.1)
		foe._duel_throw(p)
		var r: Array = await _watch_ball(args.has("follow"))
		if r[2] and args.has("grid"):
			_note_grid()
		if r[2]:
			hit_n += 1
			total += r[0]
			least = mini(least, r[0])
			if r[0] == 0:
				none += 1
		await _wait(1.4)
	_say("当たった %d 回 / %d 回。当たった玉で F が効いた秒: 平均 %.3f 最短 %.3f。照準に入らず取れなかった %d 回" % [hit_n, SPREAD_SHOTS, total / maxf(hit_n, 1) / 60.0, least / 60.0, none])
	if args.has("grid"):
		_say("--- 当たった玉で F が効く秒の平均（0 回の数）。横が照準 %s、縦が距離" % str(GRID_AIM))
		for rd in GRID_READY:
			var line := "%.1f m:" % rd
			for am in GRID_AIM:
				var v: Array = _grid.get("%s,%s" % [rd, am], [])
				var sum := 0
				var zero := 0
				for x in v:
					sum += x
					zero += 1 if x == 0 else 0
				line += "  %.2f(%d)" % [sum / maxf(v.size(), 1) / 60.0, zero]
			_say(line)
	await _check_catch()
	await _check_gap()
	await _check_make_after_dodge()
	_say("おわり: ×の数 %d" % fails)
	quit(fails)


## いまの雪玉で、距離と照準の組み合わせごとに F が効いたコマを数える
func _note_grid() -> void:
	for rd in GRID_READY:
		for am in GRID_AIM:
			var n := 0
			for t in _track:
				if t[0] <= rd and t[1] <= am:
					n += 1
			var k := "%s,%s" % [rd, am]
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(n)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## 投げられてから after 秒で F を押す（人の反応を 0.25 秒とする）。取れたら true
func _press_f_after(dist: float, speed: float, after: float) -> bool:
	_place(foe, AT + Vector3(0, 0, -dist * 0.5), AT)
	_place(p, AT + Vector3(0, 0, dist * 0.5), AT)
	await _wait(0.4)
	_reset()
	_look_at_foe()
	await _wait(0.1)
	var balls0: int = hub.balls_of(p.id)
	var hits0 := _hits
	_throw_straight(speed)
	await _wait(after)
	_key(KEY_F, true)
	_key(KEY_F, false)
	await _wait(1.0)
	var caught: bool = hub.balls_of(p.id) == balls0 + 1 and _hits == hits0
	_say("  %.0f m / %.0f m/s を %.2f 秒で F: %s" % [dist, speed, after, "取れた" if caught else "当たった"])
	await _wait(1.2)
	return caught


func _check_catch() -> void:
	_say("--- F で取る（反応 0.25 秒）")
	_ok(await _press_f_after(5.0, 10.0, 0.25), "仲間の玉（5 m）は見てから取れる")
	_ok(await _press_f_after(3.0, 7.0, 0.25), "振りかぶらない玉も 3 m なら見てから取れる")
	_ok(not await _press_f_after(2.0, 7.0, 0.25), "振りかぶらない玉は 2 m まで詰めれば、見てからでは間に合わない")
	_ok(not await _press_f_after(5.0, 7.0, 0.05), "遠すぎるうちに押しても取れない（投げてすぐ、5 m）")
	# 玉が消えるのは手の届く所まで来てから（見た目が変わらない）
	var where := [-1.0]
	var note := func(ev):
		if ev.kind == "catch":
			where[0] = (ev.point as Vector3).distance_to(duel._chest(p))
	hub.happened.connect(note)
	await _press_f_after(5.0, 10.0, 0.25)
	hub.happened.disconnect(note)
	_ok(where[0] >= 0.0 and where[0] <= duel.CATCH_REACH + 0.2, "玉は手の届く所まで飛んできてから取れる: 胸から %.2f m" % where[0])


func _check_gap() -> void:
	_say("--- 投げたあとのインターバル（%.1f 秒）" % duel.THROW_GAP)
	_place(foe, AT + Vector3(0, 0, -2.5), AT)
	_place(p, AT + Vector3(0, 0, 2.5), AT)
	await _wait(0.4)
	_reset()
	_look_at_foe()
	await _wait(0.1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	# 1 つ投げる
	p._left_click()
	await _wait(0.1)
	_ok(p.get("_winding"), "振りかぶった")
	p._unhandled_input(up)
	var t0 := Engine.get_physics_frames()
	await _wait(0.1)
	_ok(hub.balls_of(p.id) == 2, "投げた: 雪玉 %d" % hub.balls_of(p.id))
	_ok(not p.holding_ball and p.doll.sleeve_balls == 2, "次の雪玉はまだ袖に（手が空く）: 手 %s 袖 %d" % [p.holding_ball, p.doll.sleeve_balls])
	# すぐ押して離す: 投げない
	p._left_click()
	await physics_frame
	_ok(not p.get("_winding"), "投げたばかりは振りかぶれない")
	p._unhandled_input(up)
	# 押したまま: 投げられるようになったら振りかぶる
	p._left_click()
	hub.send({"kind": "throw", "who": p.id, "origin": p.global_position + Vector3.UP, "velocity": Vector3.UP})
	await _wait(0.1)
	_ok(hub.balls_of(p.id) == 2, "投げたばかりは、ホストも受けない: 雪玉 %d" % hub.balls_of(p.id))
	while not p.get("_winding") and Engine.get_physics_frames() - t0 < 300:
		await physics_frame
	var waited := (Engine.get_physics_frames() - t0) / 60.0
	_ok(p.get("_winding") and absf(waited - duel.THROW_GAP) < 0.2, "押したままなら %.2f 秒で振りかぶる" % waited)
	_ok(p.holding_ball, "雪玉が手に出た")
	p._unhandled_input(up)
	await _wait(0.1)
	_ok(hub.balls_of(p.id) == 1, "投げた: 雪玉 %d" % hub.balls_of(p.id))
	await _wait(duel.THROW_GAP + 0.2)


## 相手の玉をよけて（0.8 秒）から、しゃがんで作る: 次の玉が投げられる前に雪玉ができるか
func _check_make_after_dodge() -> void:
	_say("--- よけてから雪玉を作る")
	_reset()
	hub._set_balls(p.id, 0)
	# 外れる玉を投げる
	hub.send({"kind": "throw", "who": foe.id, "origin": foe.global_position + Vector3(4, 1.5, 0), "velocity": Vector3(0, 2, 8)})
	var t0 := Engine.get_physics_frames()
	await _wait(0.8 - 4.0 / 60.0)
	p.set("_pitch", -1.35)
	_key(KEY_CTRL, true)
	for i in 4:
		await physics_frame
	_key(KEY_F, true)
	_key(KEY_F, false)
	var made := -1.0
	var free := -1.0
	var ready := -1.0
	while Engine.get_physics_frames() - t0 < 300 and (made < 0.0 or free < 0.0 or ready < 0.0):
		await physics_frame
		var t := (Engine.get_physics_frames() - t0) / 60.0
		if made < 0.0 and hub.balls_of(p.id) > 0:
			made = t
		if made >= 0.0 and free < 0.0 and not p.rooted():
			free = t
		if ready < 0.0 and hub.can_throw(foe.id):
			ready = t
	_key(KEY_CTRL, false)
	_say("  投げられてから: 雪玉ができた %.2f 秒、立てる %.2f 秒、相手が次を投げられる %.2f 秒" % [made, free, ready])
	_ok(made >= 0.0 and made <= ready, "相手が次を投げられる前に雪玉ができた")
	_ok(free >= 0.0 and free <= ready + 0.38, "振りかぶらない次の玉が 3 m から届く（%.2f 秒）前に立てた" % (ready + 0.38))
