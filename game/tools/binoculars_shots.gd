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


## 左ボタンを押して離す
func _click() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	await create_timer(0.1).timeout
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await create_timer(0.15).timeout


func _pan(dy: float) -> void:
	var n := 8
	for i in n:
		var e := InputEventPanGesture.new()
		e.delta = Vector2(0, dy / n)
		Input.parse_input_event(e)
		await process_frame
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


## 人の体の大きさがそこに入るか（床は除く）
func _free_at(at: Vector3, skip: Node3D) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.5
	q.shape = cap
	q.transform = Transform3D(Basis(), at + Vector3.UP * 0.95)
	q.exclude = [skip.get_rid()]
	var hits := skip.get_world_3d().direct_space_state.intersect_shape(q, 8)
	for h in hits:
		print("  当たり: ", h.collider)
	return hits.is_empty()


## 全方角の並びの絵: 上から全体（台の上に色の玉の目印）と、台ごとの近景
func _overview() -> void:
	var cols := [Color(0.85, 0.2, 0.18), Color(0.92, 0.68, 0.15), Color(0.2, 0.62, 0.62), Color(0.55, 0.3, 0.7)]
	var marks := []
	for i in main.binocular_stands.size():
		var bs: Node3D = main.binocular_stands[i]
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.75
		sm.height = 1.5
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cols[i]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		bs.add_child(mi)
		mi.position = Vector3(0, 3.2, 0)
		marks.append(mi)
	var lodge: Node3D = main.get_node("Lodge")
	await _from_side("30_overview", lodge.to_global(Vector3(-46, 40, 44)), lodge.to_global(Vector3(-1, 5, 2)))
	for i in main.binocular_stands.size():
		var bs: Node3D = main.binocular_stands[i]
		await _from_side("31_near%d" % i, bs.to_global(Vector3(1.9, 2.1, 3.6)), bs.to_global(Vector3(0, 0.9, 0)))
	for m in marks:
		m.queue_free()


func _stand_before() -> void:
	p.global_position = st.to_global(Vector3(0, 0.1, 1.3))
	p.rotation.y = st.global_rotation.y
	p._pitch = -0.1
	p.velocity = Vector3.ZERO
	await create_timer(0.5).timeout


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	st = main.binocular_stands[0]
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
	var fov0: float = p._peek_fov_now()
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 30)
	_check("ホイールで寄り、幅で止まる", is_equal_approx(p._peek_fov_now(), 5.0))
	p._pitch = 0.09
	await create_timer(1.0).timeout
	await _save("03d_stand_most")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, 30)
	_check("ホイールで引き、幅で止まる", is_equal_approx(p._peek_fov_now(), 24.0))
	await create_timer(1.0).timeout
	await _save("03e_stand_least")
	var fv: float = p._peek_fov_now()
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, -6)
	Input.parse_input_event(pan)
	await create_timer(0.2).timeout
	_check("二本指スクロールで寄る", p._peek_fov_now() < fv and p.peek == "stand")
	p._peek_fov["stand"] = 24.0
	await _pan(-430.0 * 0.03)   # Mac の量の 0.03 倍で届く
	_check("約 430 pt の撫でで台の倍率の端へ届く", p._peek_fov_now() < 5.5)
	p._peek_fov["stand"] = fov0
	p._pitch = -0.1
	await create_timer(0.5).timeout
	# 台は左ボタンやほかのキーではやめない
	await _click()
	await _key(KEY_Z)
	_check("台は左ボタンやほかのキーでやめない", p.peek == "stand")
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
	craft.scope_paid.clear()   # 払った時間を消して、払う所から確かめる（のぞき直しは binoculars_paid_check.gd）
	await _stand_before()
	_check("雪玉がなければボタン", p.binocular_pay() == "button")
	await _key(KEY_F)
	_check("ボタンが 1 減る", p.peek == "stand" and craft.wallet(p.id) == 1)
	await _key(KEY_ESCAPE)
	_check("Esc でやめる。設定は開かない", p.peek == "" and not main.settings.is_open)
	# ---- 台: 時間で閉じる
	craft.scope_paid.clear()
	await _stand_before()
	await _key(KEY_F)
	_check("もう 1 枚で開く", p.peek == "stand" and craft.wallet(p.id) == 0)
	await create_timer(1.0).timeout
	await _save("07a_stand_full")
	p._peek_left = 30.0
	await create_timer(1.0).timeout
	await _save("07b_stand_half")
	p._peek_left = 9.0
	await create_timer(0.7).timeout
	await _save("07c_stand_ten")
	p._peek_left = 4.5
	await create_timer(0.5).timeout
	await _save("07_stand_little_left")
	p._peek_left = 0.3
	await create_timer(0.55).timeout
	await _save("08_stand_closing")
	await create_timer(0.5).timeout
	_check("時間で閉じて空く", p.peek == "" and int(st.who) < 0)
	# ---- 台: 払えない
	craft.scope_paid.clear()
	await _stand_before()
	_check("何もなければ ×", p.binocular_pay() == "none")
	await _save("09_stand_none")
	await _key(KEY_F)
	_check("払えなければのぞけない", p.peek == "")
	# ---- 全方角の台: 外を向く・払える・F が取り合わない・人が立てる
	craft.wallets[p.id] = 10
	var lodge: Node3D = main.get_node("Lodge")
	var outward := [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]   # ロッジの座標（z が南）
	for i in main.binocular_stands.size():
		var bs: Node3D = main.binocular_stands[i]
		p.global_position = bs.to_global(Vector3(0, 0.1, 1.3))
		p.rotation.y = bs.global_rotation.y
		p._pitch = 0.0
		p.velocity = Vector3.ZERO
		await create_timer(0.5).timeout
		_check("台 %d の前で F の相手は台だけ（席・立てかけ台が出ない）" % i, p.binocular_near() == bs and p.seat_near() < 0 and p.rack_target().is_empty())
		_check("台 %d は床の上に立つ" % i, absf(p.global_position.y - bs.global_position.y) < 0.2)
		await _key(KEY_F)
		await create_timer(0.8).timeout
		_check("台 %d でのぞける" % i, p.peek == "stand" and int(bs.who) == p.id)
		var look: Vector3 = lodge.global_basis.inverse() * (-p.cam.global_basis.z)
		_check("台 %d は外を向く" % i, Vector3(look.x, 0, look.z).normalized().dot(outward[i]) > 0.95)
		_check("台 %d で人が立つ所に当たりがない" % i, _free_at(p.global_position, p))
		await _save("20_stand%d_view" % i)
		await _key(KEY_F)
		_check("台 %d を下りた所も空いている" % i, p.peek == "" and _free_at(p.global_position, p))
	await _overview()
	craft.wallets[p.id] = 2
	craft.scope_paid.clear()
	# ---- 手の双眼鏡
	craft.wallets[p.id] = 40
	craft.send({"kind": "buy", "who": p.id, "item": preload("res://binoculars.gd").ITEM.duplicate()})
	_check("山男の棚で買えて手に持つ", p.held().get("kind", "") == "binoculars" and craft.wallet(p.id) == 10)
	p.rotation.y = st.global_rotation.y + 0.55
	p._pitch = 0.05
	p.global_position = st.to_global(Vector3(2.4, 0.1, 0.1))
	await create_timer(0.8).timeout
	await _save("10_hand_held")
	await _click()
	await create_timer(0.8).timeout
	_check("左ボタン 1 回でのぞき、離してものぞいたまま", p.peek == "hand" and p.doll.peek == "binoculars")
	await _save("11_hand_peek")
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 2)
	_check("手の双眼鏡もホイールで寄り、持ち替えない", p._peek_fov_now() < 24.0 and p.peek == "hand" and p.held().get("kind", "") == "binoculars")
	var fh: float = p._peek_fov_now()
	await _pan(4.0)
	_check("離した状態の二本指スクロールで倍率が変わり、持ち替えない", p._peek_fov_now() > fh and p.peek == "hand")
	var fh2: float = p._peek_fov_now()
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.2
	Input.parse_input_event(pinch)
	await create_timer(0.2).timeout
	_check("離した状態のつまむ操作で倍率が変わる", p._peek_fov_now() < fh2 and p.peek == "hand")
	await _save("11b_hand_zoomed")
	await _click()
	_check("もう 1 回押すとやめる", p.peek == "")
	# 撫でている途中でやめる: 続きの慣性で持ち替えない（パンを途切れさせない）
	await _click()
	for i in 24:
		var pe := InputEventPanGesture.new()
		pe.delta = Vector2(0, 0.25)
		Input.parse_input_event(pe)
		if i == 8:
			var lc := InputEventMouseButton.new()
			lc.button_index = MOUSE_BUTTON_LEFT
			lc.pressed = true
			Input.parse_input_event(lc)
			var lu := lc.duplicate()
			lu.pressed = false
			Input.parse_input_event(lu)
		await process_frame
	_check("撫でている途中でやめても、慣性で持ち替えない", p.peek == "" and p.held().get("kind", "") == "binoculars")
	await create_timer(0.3).timeout
	# 歩く: W を押すと下ろして歩く
	await _click()
	_check("のぞき直せる", p.peek == "hand")
	var from: Vector3 = p.global_position
	var w2 := InputEventKey.new()
	w2.physical_keycode = KEY_W
	w2.pressed = true
	Input.parse_input_event(w2)
	await create_timer(0.4).timeout
	var off2 := w2.duplicate()
	off2.pressed = false
	Input.parse_input_event(off2)
	_check("W で下ろして歩く", p.peek == "" and p.global_position.distance_to(from) > 0.2)
	# F・Esc でやめる
	await _click()
	_check("F の前にのぞいている", p.peek == "hand")
	await _key(KEY_F)
	_check("F でやめる（手）", p.peek == "")
	await _click()
	_check("Esc の前にのぞいている", p.peek == "hand")
	await _key(KEY_ESCAPE)
	_check("Esc でやめる。設定は開かない（手）", p.peek == "" and not main.settings.is_open)
	# 持ち替え: Z で下ろして替わる
	await _click()
	_check("Z の前にのぞいている", p.peek == "hand")
	await _key(KEY_Z)
	_check("Z で下ろして持ち替える", p.peek == "" and p.held().get("kind", "") != "binoculars")
	await _key(KEY_Z)
	# 持ち物の画面: I で下ろして開く
	if p.held().get("kind", "") == "binoculars":
		await _click()
		_check("I の前にのぞいている", p.peek == "hand")
		await _key(KEY_I)
		_check("I で下ろして持ち物の画面を開く", p.peek == "" and p.menu_open)
		await _key(KEY_I)
		await create_timer(0.3).timeout
	else:
		_check("Z 2 回で双眼鏡に戻る", false)
	# ソリに乗る: E で下ろして乗る
	var near: Vector3 = p.global_position - p.global_basis.z * 1.6
	var sid: int = craft._place("mid", "red", near, p.rotation.y, 0, Vector3.UP, craft.tag_designs[p.id], false, p.id)
	await create_timer(0.8).timeout
	if p.held().get("kind", "") == "binoculars":
		await _click()
		_check("E の前にのぞいている", p.peek == "hand")
		await _key(KEY_E)
		await create_timer(0.5).timeout
		_check("E で下ろしてソリへ", p.peek == "" and p.mode == p.Mode.RIDE)
		await _key(KEY_E)
		await create_timer(0.3).timeout
	craft.sleds[sid].queue_free()
	craft.sleds.erase(sid)
	await create_timer(0.3).timeout
	# ---- 山男の棚
	main.mountain_ui.open()
	await _save("13_shelf")
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)
