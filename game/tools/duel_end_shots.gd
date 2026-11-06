extends SceneTree
## 雪合戦の終わりの、勝敗の舞台（duel_stage.gd）と握手の案内（duel_hud.gd の _draw_end）を撮る。相手はコンピューターの仲間。窓を出す:
##   Godot --path game --resolution 1280x720 -s res://tools/duel_end_shots.gd -- --no-sound --bots=1 --lodge-bots=0 --hud-idle=0 --dir=/path/shots
## 1 勝ち（3 発当てた）: 01 決まった瞬間 / 02 案内 / 2 キーを本当に押して 03 手を出した / 仲間と握手して 04 払ったあと（消える）
## 2 負け（3 発当てられた）: 05 決まった瞬間 / 06 案内 / 3 時間切れの勝ち: 07 / 4 時間切れの引き分け: 08 / 5 相手が抜けた: 09 決まった瞬間 / 10 案内

const AT := Vector3(14, 0, 16)

var args := {}
var main: Node3D
var p: Node3D
var foe: Node3D
var hub: Node
var duel: Node
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.get("dir", "/tmp/duel_end")).path_join(name + ".png"))
	print("撮った: ", name)


func _ok(cond: bool, what: String) -> void:
	print(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _place(n: Node3D, at: Vector3, look: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.15
	n.global_position = at
	n.velocity = Vector3.ZERO
	n.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))


func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)
	Input.flush_buffered_events()


## 戦いを始めて、仲間を止めて向かい合う（握手と掛金は飛ばす）
func _begin(stake := 10) -> void:
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	_place(p, AT, AT + Vector3(0, 0, 1))
	_place(foe, AT + Vector3(0, 0, 0.8), AT)
	hub._set_balls(p.id, 3)
	hub._set_balls(foe.id, 3)
	duel._shook(p.id, foe.id)
	duel.of(p.id).stake = stake
	duel._apply({"kind": "ok", "who": p.id})
	duel._apply({"kind": "ok", "who": foe.id})
	await _wait(0.3)
	_place(foe, AT + Vector3(0, 0, 3.5), AT)
	p.rotation.y = PI
	p.set("_pitch", -0.05)
	_ok(not duel.fighting(p.id).is_empty(), "戦いが始まった")


func _strike_out(by: int, who: int) -> void:
	for i in duel.LIVES:
		duel._guard.clear()
		duel._struck(by, who)


## 片づける（握手なしで払う）
func _pay_now() -> void:
	var d: Dictionary = duel.of(p.id)
	if not d.is_empty():
		duel._pay(d)
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	await _wait(0.5)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(String(args.get("dir", "/tmp/duel_end")))
	await _wait(1.0)
	p = main.player
	hub = main.emotes
	duel = main.duel
	foe = main.get_children().filter(func(c): return c.get_script() == main.Bot and not c.lounge)[0]
	p.set_third(false)
	var ui: Node = main.duel_hud
	# 勝ち
	await _begin()
	_strike_out(p.id, foe.id)
	await _wait(0.3)
	_ok(duel.of(p.id).get("phase", "") == "over" and int(duel.of(p.id).winner) == p.id, "勝ち: 決まった")
	await _shot("01_win_big")
	await _wait(0.3)
	await _shot("01b_win_big")
	await _wait(0.3)
	await _shot("01c_win_big")
	await _wait(ui.END_BIG_T + ui.END_MOVE_T)
	await _shot("02_win_guide")
	_key(KEY_2)
	await _wait(0.3)
	_ok(String(p.hands_name).begins_with("low"), "2 キーで低い手のひらが出る: %s" % p.hands_name)
	await _shot("03_win_hand_out")
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	_place(foe, AT + Vector3(0, 0, 0.9), AT)
	var w := 0.0
	while not duel.of(p.id).is_empty() and w < 15.0:
		await _wait(0.2)
		w += 0.2
	_ok(duel.of(p.id).is_empty(), "近づいて握手すると終わる（%.1f 秒）" % w)
	await _wait(0.6)
	await _shot("04_paid")
	_key(KEY_2)   # 手を下ろす
	await _wait(1.5)
	# 負け
	await _begin()
	_strike_out(foe.id, p.id)
	await _wait(0.3)
	await _shot("05_lose_big")
	await _wait(0.2)
	await _shot("05b_lose_big")
	await _wait(ui.END_BIG_T + ui.END_MOVE_T)
	await _shot("06_lose_guide")
	await _pay_now()
	await _wait(1.5)
	# 時間切れの勝ち
	await _begin()
	duel._guard.clear()
	duel._struck(p.id, foe.id)
	duel.of(p.id).until = Duel_frame()
	await _wait(0.5)
	await _shot("07_time_win")
	await _pay_now()
	await _wait(1.5)
	# 時間切れの引き分け
	await _begin()
	duel.of(p.id).until = Duel_frame()
	await _wait(0.5)
	_ok(int(duel.of(p.id).winner) == -1, "同じ数なら引き分け")
	await _shot("08_time_draw")
	await _pay_now()
	await _wait(1.5)
	# 相手が抜けた
	await _begin()
	hub.people.erase(foe.id)
	await _wait(0.5)
	_ok(int(duel.of(p.id).winner) == p.id, "抜けた人の負け")
	await _shot("09_gone_big")
	await _wait(ui.END_BIG_T + ui.END_MOVE_T)
	await _shot("10_gone_guide")
	quit(fails)


func Duel_frame() -> int:
	return duel.Doll.frame_index()
