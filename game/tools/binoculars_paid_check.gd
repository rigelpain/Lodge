extends SceneTree
## 双眼鏡台の払った時間を確かめる。払う → やめる → のぞき直しても財布が減らない → 別の台は別に払う → 本当に 60 秒すぎると、また払う。時間は縮めない（約 65 秒かかる）。
##   Godot --path game --resolution 1280x720 -s res://tools/binoculars_paid_check.gd -- --bots=0 --no-sound --no-pip --no-buttons --doll=kasa --dir=/path

var args := {}
var main: Node3D
var p: CharacterBody3D
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/binoculars_paid"))
	_run.call_deferred()


func _check(what: String, ok: bool) -> void:
	print("OK  " if ok else "だめ ", what)
	if not ok:
		fails += 1


func _save(name: String) -> void:
	await create_timer(0.4).timeout
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.get("dir", "/tmp/binoculars_paid")).path_join(name + ".png"))


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await create_timer(0.3).timeout


func _before(st: Node3D) -> void:
	p.global_position = st.to_global(Vector3(0, 0.1, 1.3))
	p.rotation.y = st.global_rotation.y
	p._pitch = -0.05
	p.velocity = Vector3.ZERO
	await create_timer(0.5).timeout


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	var craft = main.craft
	var hub = main.emotes
	var a: Node3D = main.binocular_stands[0]
	var b: Node3D = main.binocular_stands[1]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p.set_third(false)
	hub._set_balls(p.id, 0)
	craft.wallets[p.id] = 5
	await _before(a)
	_check("はじめは木のボタンの案内", p.binocular_pay() == "button")
	await _save("01_before_pay")
	await _key(KEY_F)
	var t0 := Time.get_ticks_msec()
	_check("F で払ってのぞく（5 → 4）", p.peek == "stand" and craft.wallet(p.id) == 4)
	await create_timer(3.0).timeout
	await _key(KEY_F)
	_check("やめる", p.peek == "" and int(a.who) < 0)
	await _before(a)
	_check("時間内の案内は払いなし", p.binocular_pay() == "free")
	await _save("02_free_hint")
	var left0: float = craft.scope_left(p.id, a.index)
	_check("やめても時間は進んでいる（残り %.1f 秒）" % left0, left0 < 58.0 and left0 > 50.0)
	await _key(KEY_F)
	_check("のぞき直しても財布は減らない", p.peek == "stand" and craft.wallet(p.id) == 4)
	_check("残りはその残りから続く", absf(p._peek_left - craft.scope_left(p.id, a.index)) < 0.5 and p._peek_left < left0)
	await create_timer(0.8).timeout
	await _save("03_repeek")
	await _key(KEY_ESCAPE)
	await _before(a)
	await _key(KEY_F)
	_check("もう一度のぞき直しても減らない", p.peek == "stand" and craft.wallet(p.id) == 4)
	await _key(KEY_F)
	# 別の台は別に払う
	await _before(b)
	_check("別の台は払う案内", p.binocular_pay() == "button")
	await _key(KEY_F)
	_check("別の台で払う（4 → 3）", p.peek == "stand" and craft.wallet(p.id) == 3)
	await _key(KEY_F)
	await _before(a)
	_check("もとの台の時間はまだ残っている", p.binocular_pay() == "free")
	# 本当に 60 秒すぎるまで待つ（のぞいたまま閉じるのも見る）
	await _key(KEY_F)
	_check("閉じるまでのぞいておく", p.peek == "stand")
	while Time.get_ticks_msec() - t0 < 61500:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	_check("60 秒で閉じる", p.peek == "" and int(a.who) < 0)
	await _before(a)
	_check("60 秒すぎると、また払う案内", p.binocular_pay() == "button")
	await _save("04_after_time")
	await _key(KEY_F)
	_check("また払う（3 → 2）", p.peek == "stand" and craft.wallet(p.id) == 2 and p._peek_left > 58.0)
	await _key(KEY_F)
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)
