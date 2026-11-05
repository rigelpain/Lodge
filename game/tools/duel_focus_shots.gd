extends SceneTree
## 雪合戦のあいだ、ふだんの HUD をよけて一人称に固定する（main.gd の set_duel_focus）のを撮って確かめる。対決の仲間（--duel-bot）が相手。
##   Godot --path game --resolution 1280x720 -s res://tools/duel_focus_shots.gd -- --duel-bot --bots=1 --lodge-bots=0 --no-sound --hud-idle=0 --dir=/path/shots
## 1 回目: 三人称で小窓と刺繍枠を出して始める。戦いでよける・C とピンチで視点が変わらない → 勝ち負けで元どおり。
## 2 回目: 小窓と刺繍枠を自分で閉じて始める。終わっても閉じたまま。
## 01 始める前 / 02 戦い（一人称）/ 03 勝ち負けのあと / 04 払ったあと / 05 閉じたまま始めた戦い / 06 閉じたまま終わったあと

var args := {}
var main: Node3D
var p: Node3D
var foe: Node3D
var bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 日時計（daycycle.gd）は current_scene に置く
	_run.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var dir: String = args.get("dir", "/tmp/duel_focus")
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("撮った: ", name)


func _see(what: String, got: Variant, want: Variant) -> void:
	if got != want:
		bad += 1
	print("%s %s: %s（のぞみ %s）" % ["ok" if got == want else "NG", what, got, want])


func _dial_shown() -> bool:
	var dial = root.get_node("DayCycle").get("_dial")
	return dial != null and dial.visible


func _place(n: Node3D, at: Vector3, look: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.15
	n.global_position = at
	n.velocity = Vector3.ZERO
	n.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))


## 握手して掛金なしで受け、戦いが始まるまで
func _begin(at: Vector3) -> void:
	var hub = main.emotes
	var duel = main.duel
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	foe.doll.process_mode = Node.PROCESS_MODE_ALWAYS
	_place(p, at, at + Vector3(0, 0, 1))
	_place(foe, at + Vector3(0, 0, 0.8), at)
	await _wait(0.3)
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	hub.send({"kind": "hands", "who": p.id, "hands": "low_R"})
	hub.send({"kind": "hands", "who": foe.id, "hands": "low_R"})
	await _wait(1.2)
	main.duel_hud.accept()
	while duel.of(p.id).get("phase", "") != "fight":
		await _wait(0.2)
	foe._duel_t = 99.0
	await _wait(0.4)
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	_place(foe, at + Vector3(0, 0, 3.0), at)
	_place(p, at + Vector3(0, 0, -1.5), at + Vector3(0, 0, 3.0))
	p.set("_pitch", -0.05)
	await _wait(0.4)


## 仲間に 3 発当てたことにして、勝ち負けを決める
func _end() -> void:
	var d: Dictionary = main.duel.of(p.id)
	for i in 3:
		main.duel._guard.erase(foe.id)
		main.duel._struck(p.id, foe.id)
	_see("勝ち負けが決まった", main.duel.of(p.id).get("phase", ""), "over")
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	await _wait(0.5)


func _pay() -> void:
	main.duel._pay(main.duel.of(p.id))
	await _wait(0.5)


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	p._unhandled_input(e)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/duel_focus"))
	await _wait(2.0)
	p = main.player
	foe = main.get_children().filter(func(c): return c.get_script() == main.Bot and c.duelist)[0]
	# ---- 1 回目: 三人称、小窓と刺繍枠を出している
	p.set_third(true)
	main.hud.hints_on = true
	await _wait(0.3)
	await _shot("01_before")
	await _begin(Vector3(14, 0, 16))
	_see("戦い: よけている", main.duel_focus, true)
	_see("戦い: 一人称", p.third, false)
	_see("戦い: 小窓を消す", main._pip_layer.visible, false)
	_see("戦い: 刺繍枠を消す", main.self_cam.hidden, true)
	_see("戦い: 日時計を消す", _dial_shown(), false)
	_key(KEY_C)
	_see("戦い: C で変わらない", p.third, false)
	p._pinch(0.01)
	p._pinch(0.01)
	_see("戦い: ピンチで変わらない", p.third, false)
	_see("戦い: 設定は三人称のまま", main.settings.values.get("third", false) == true or p._third_want, true)
	await _shot("02_fight")
	await _end()
	_see("勝ち負けのあと: 戻す", main.duel_focus, false)
	_see("勝ち負けのあと: 三人称へ戻る", p.third, true)
	_see("勝ち負けのあと: 小窓が戻る", main._pip_layer.visible, true)
	_see("勝ち負けのあと: 刺繍枠が戻る", main.self_cam.hidden, false)
	_see("勝ち負けのあと: 日時計が戻る", _dial_shown(), true)
	await _shot("03_over")
	await _pay()
	await _shot("04_after")
	# ---- 2 回目: 一人称、小窓と刺繍枠を閉じて始める
	p.set_third(false)
	main.pip_hidden = true
	main._sync_pip_shown()
	main.self_cam.set_shown(false)
	await _begin(Vector3(24, 0, 16))
	_see("閉じて始めた戦い: よけている", main.duel_focus, true)
	await _shot("05_fight_closed")
	await _end()
	await _pay()
	_see("閉じて終わった: 一人称のまま", p.third, false)
	_see("閉じて終わった: 小窓は閉じたまま", main._pip_layer.visible, false)
	_see("閉じて終わった: 刺繍枠は閉じたまま", main.self_cam.hidden, true)
	_see("閉じて終わった: 日時計は戻る", _dial_shown(), true)
	await _shot("06_after_closed")
	print("NG の数: ", bad)
	quit()
