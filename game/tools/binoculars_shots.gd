extends SceneTree
## 双眼鏡と、テラスの双眼鏡台を撮って確かめる（のぞく前・のぞいたとき・横から。払う・閉じる・断るの数字も出す）。F と左ボタンは本物の入力の出来事で押す。
##   Godot --path game --resolution 1280x720 -s res://tools/binoculars_shots.gd -- --bots=0 --no-sound --no-pip --no-buttons --dir=/path/shots

var args := {}
var main: Node3D
var p: CharacterBody3D
var st: Node3D
var side: Camera3D
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/binoculars_shots")


func _check(what: String, ok: bool) -> void:
	print("OK  " if ok else "だめ ", what)
	if not ok:
		fails += 1


func _save(name: String) -> void:
	await create_timer(0.3).timeout
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


## 横のカメラで撮る（窓と HUD は隠す）
func _from_side(name: String, from: Vector3, to: Vector3) -> void:
	var seen := {}
	for n in root.find_children("*", "CanvasLayer", true, false):
		seen[n] = (n as CanvasLayer).visible
		(n as CanvasLayer).visible = false
	if p._peek_view:
		p._peek_view.get_child(0).visible = false   # 窓は毎コマ出し直されるので、中の 1 枚を隠す
	side.current = true
	side.look_at_from_position(from, to)
	await _save(name)
	if p._peek_view:
		p._peek_view.get_child(0).visible = true
	p.cam.make_current()
	for n in seen:
		(n as CanvasLayer).visible = seen[n]


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await create_timer(0.15).timeout


func _mouse(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	Input.parse_input_event(e)
	await create_timer(0.15).timeout


func _wheel(button: MouseButton, n: int) -> void:
	for i in n:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = true
		Input.parse_input_event(e)
		var u := e.duplicate()
		u.pressed = false
		Input.parse_input_event(u)
	await create_timer(0.2).timeout


func _stand_before() -> void:
	p.global_position = st.to_global(Vector3(0, 0.1, 1.3))
	p.rotation.y = st.global_rotation.y
	p._pitch = -0.1
	p.velocity = Vector3.ZERO
	await create_timer(0.5).timeout


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	st = main.binocular_stand
	var craft = main.craft
	var hub = main.emotes
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p.set_third(false)
	side = Camera3D.new()
	side.fov = 42.0
	side.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 7)
	root.add_child(side)
	# ---- 台: 雪玉で
	hub._set_balls(p.id, 1)
	craft.wallets[p.id] = 2
	await _stand_before()
	_check("前で払い方は雪玉", p.binocular_pay() == "ball")
	await _save("01_before_stand_hint")
	await _from_side("02_stand_from_terrace", st.to_global(Vector3(2.4, 1.3, 3.2)), st.to_global(Vector3(0, 1.0, 0)))
	await _key(KEY_F)
	_check("F でのぞく", p.peek == "stand" and int(st.who) == p.id)
	_check("雪玉が減り、ボタンは減らない", hub.balls_of(p.id) == 0 and craft.wallet(p.id) == 2)
	await create_timer(1.0).timeout
	var at0: Vector3 = p.global_position
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	Input.parse_input_event(w)
	await create_timer(0.4).timeout
	var off := w.duplicate()
	off.pressed = false
	Input.parse_input_event(off)
	_check("W で歩かない", p.global_position.distance_to(at0) < 0.05)
	await _save("03_stand_peek")
	p._pitch = 0.09   # 遠くの丘のてっぺんへ
	await create_timer(0.6).timeout
	await _save("03b_stand_far")
	await create_timer(2.0).timeout
	print("FPS のぞいている: ", Engine.get_frames_per_second())
	p.rotation.y = st.global_rotation.y + 0.55
	await create_timer(0.6).timeout
	await _save("03c_stand_far_side")
	p.rotation.y = st.global_rotation.y
	p._pitch = -0.1
	# 横から撮る
	await _from_side("04_stand_peek_side", st.to_global(Vector3(-1.7, 1.0, 1.7)), st.to_global(Vector3(0, 0.85, 0.1)))
	# 倍率: ホイールと二本指スクロールで変わり、持ち替えない。幅に収まる
	var fov0: float = p._peek_fov.stand
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 30)
	_check("ホイールで寄り、幅で止まる", is_equal_approx(p._peek_fov.stand, 5.0))
	p._pitch = 0.09
	await create_timer(1.0).timeout
	await _save("03d_stand_most")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, 30)
	_check("ホイールで引き、幅で止まる", is_equal_approx(p._peek_fov.stand, 24.0))
	await create_timer(1.0).timeout
	await _save("03e_stand_least")
	var fv: float = p._peek_fov.stand
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, -6)
	Input.parse_input_event(pan)
	await create_timer(0.2).timeout
	_check("二本指スクロールで寄る", p._peek_fov.stand < fv and p.peek == "stand")
	p._peek_fov.stand = fov0
	p._pitch = -0.1
	await create_timer(0.5).timeout
	# 見回す: 台より横へは回らない
	p.rotation.y = st.global_rotation.y + 3.0
	await create_timer(0.5).timeout
	_check("見回す幅に収まる", absf(wrapf(p.rotation.y - st.global_rotation.y, -PI, PI)) <= st.YAW_MAX + 0.01)
	p.rotation.y = st.global_rotation.y + 0.8
	await create_timer(0.8).timeout
	await _from_side("05_stand_peek_turned", st.to_global(Vector3(-2.0, 1.2, 1.2)), st.to_global(Vector3(0, 0.85, 0.1)))
	await _key(KEY_F)
	_check("F でやめる", p.peek == "" and int(st.who) < 0)
	# ---- ふつうに見た絵（比べる）
	p.rotation.y = st.global_rotation.y
	p._pitch = 0.0
	await create_timer(0.8).timeout
	await _save("06_terrace_plain")
	await _stand_before()
	p._pitch = 0.09
	p.global_position = st.to_global(Vector3(0, 0.1, st.STAND_R))
	await create_timer(0.3).timeout
	st.hide_head(true)
	await _save("06b_same_dir_no_zoom")
	await create_timer(2.0).timeout
	print("FPS 同じ向きをふつうに: ", Engine.get_frames_per_second())
	st.hide_head(false)
	# ---- 台: ボタンで。Esc でやめる
	await _stand_before()
	_check("雪玉がなければボタン", p.binocular_pay() == "button")
	await _key(KEY_F)
	_check("ボタンが 1 減る", p.peek == "stand" and craft.wallet(p.id) == 1)
	await _key(KEY_ESCAPE)
	_check("Esc でやめる。設定は開かない", p.peek == "" and not main.settings.is_open)
	# ---- 台: 時間で閉じる
	await _stand_before()
	await _key(KEY_F)
	_check("もう 1 枚で開く", p.peek == "stand" and craft.wallet(p.id) == 0)
	p._peek_left = 6.0
	await create_timer(1.0).timeout
	await _save("07_stand_little_left")
	p._peek_left = 0.3
	await create_timer(0.55).timeout
	await _save("08_stand_closing")
	await create_timer(0.5).timeout
	_check("時間で閉じて空く", p.peek == "" and int(st.who) < 0)
	# ---- 台: 払えない
	await _stand_before()
	_check("何もなければ ×", p.binocular_pay() == "none")
	await _save("09_stand_none")
	await _key(KEY_F)
	_check("払えなければのぞけない", p.peek == "")
	# ---- 手の双眼鏡
	craft.wallets[p.id] = 40
	craft.send({"kind": "buy", "who": p.id, "item": preload("res://binoculars.gd").ITEM.duplicate()})
	_check("山男の棚で買えて手に持つ", p.held().get("kind", "") == "binoculars" and craft.wallet(p.id) == 10)
	p.rotation.y = st.global_rotation.y + 0.55
	p._pitch = 0.05
	p.global_position = st.to_global(Vector3(2.4, 0.1, 0.1))
	await create_timer(0.8).timeout
	await _save("10_hand_held")
	await _mouse(true)
	_check("左ボタンでのぞく", p.peek == "hand")
	await create_timer(0.8).timeout
	await _save("11_hand_peek")
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 2)
	_check("手の双眼鏡もホイールで寄り、持ち替えない", p._peek_fov.hand < 24.0 and p.peek == "hand" and p.held().get("kind", "") == "binoculars")
	# 横から撮る
	await _mouse(false)
	_check("離すとやめる", p.peek == "")
	await create_timer(0.3).timeout
	# ---- 山男の棚
	main.mountain_ui.open()
	await _save("13_shelf")
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)
