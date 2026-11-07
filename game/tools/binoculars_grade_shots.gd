extends SceneTree
## 手の双眼鏡の段を確かめる: 夜と吹雪で、基本と夜目（暗視）の絵、遠見の倍率、段の値段と持ち物、暗視をやめると元へ戻ること、FPS。吹雪はまだゲームにないので、ここで雪と霧を濃くして作る。
##   Godot --path game --resolution 1280x720 -s res://tools/binoculars_grade_shots.gd -- --bots=0 --no-sound --no-pip --no-buttons --doll=kasa --dir=/path

const B := preload("res://binoculars.gd")

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
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/binoculars_grades")


func _check(what: String, ok: bool) -> void:
	print("OK  " if ok else "だめ ", what)
	if not ok:
		fails += 1


func _save(name: String) -> void:
	await create_timer(0.5).timeout
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)


func _click() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	await create_timer(0.1).timeout
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await create_timer(0.2).timeout


func _hold(kind: String) -> void:
	var b: Array = main.craft.bag(p.id)
	for i in b.size():
		if b[i].get("kind", "") == kind:
			main.craft.send({"kind": "hand", "who": p.id, "slot": i})
			break
	await create_timer(0.2).timeout


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	var craft = main.craft
	var st: Node3D = main.binocular_stands[0]
	var lodge: Node3D = main.get_node("Lodge")
	var env: Environment
	for n in main.get_children():
		if n is WorldEnvironment:
			env = n.environment
	var day = root.get_node("DayCycle")
	day.day_seconds = 1000000.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p.set_third(false)
	# ---- 買う: 段ごとの値段。前の段は持ち物に残る
	craft.wallets[p.id] = 1600
	for kind in B.GRADES:
		var before: int = craft.wallet(p.id)
		craft.send({"kind": "buy", "who": p.id, "item": {"kind": kind}})
		_check("%s は %d 個で買えて手に持つ" % [kind, B.GRADES[kind].price], craft.wallet(p.id) == before - int(B.GRADES[kind].price) and p.held().get("kind", "") == kind)
	var kinds := {}
	for it in craft.bag(p.id):
		kinds[it.get("kind", "")] = true
	_check("買っても前の段は持ち物に残る", kinds.has("binoculars") and kinds.has("binoculars_far") and kinds.has("binoculars_night"))
	await _save("00_held_night")
	await _hold("binoculars_far")
	await _save("00_held_far")
	main.mountain_ui.open()
	await _save("01_shelf")
	main.mountain_ui.close()
	await create_timer(0.3).timeout
	# ---- 見る所: テラスの柵の手前から丘
	p.global_position = st.to_global(Vector3(-2.0, 0.1, 0.45))
	await create_timer(0.5).timeout
	var aim: Vector3 = lodge.to_global(Vector3(-10.0, 0, 95.0))
	aim.y = main.height(aim.x, aim.z) + 3.0
	var dir: Vector3 = (aim - p.cam.global_position).normalized()
	p.rotation.y = atan2(-dir.x, -dir.z)
	p._pitch = asin(dir.y)
	var base_fog: float = env.fog_density
	var base_exp: float = env.tonemap_exposure
	var amount: int = main.snowfall.amount
	# ---- 遠見は基本より寄れる
	await _hold("binoculars")
	await _click()
	await create_timer(0.8).timeout
	await _save("02_day_basic")
	await _click()
	await _hold("binoculars_far")
	await _click()
	await create_timer(0.8).timeout
	await _save("03_day_far")
	_check("遠見は始めから基本より寄っている", p._peek_fov_now() < B.fov("binoculars"))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	for i in 30:
		Input.parse_input_event(ev)
	await create_timer(0.8).timeout
	_check("遠見の最も寄った倍率は基本より強い", is_equal_approx(p._peek_fov_now(), 6.5))
	await _save("04_day_far_most")
	await _click()
	# ---- 夜
	day.hour = 23.0
	await create_timer(1.5).timeout
	await _hold("binoculars")
	await _click()
	await create_timer(0.8).timeout
	await _save("10_night_basic")
	await _click()
	await _hold("binoculars_night")
	await _click()
	await create_timer(0.8).timeout
	_check("夜目は霧を薄くして舞う雪を隠し、夜は明るくする", env.fog_density < base_fog and not main.snowfall.visible and env.tonemap_exposure > base_exp * 3.0)
	await _save("11_night_sight")
	await create_timer(2.0).timeout
	print("FPS 夜目でのぞいている: ", Engine.get_frames_per_second())
	await _click()
	_check("やめると霧・雪・露出が元へ戻る", is_equal_approx(env.fog_density, base_fog) and main.snowfall.visible and is_equal_approx(env.tonemap_exposure, base_exp))
	await create_timer(2.5).timeout
	print("FPS のぞかずに同じ向き: ", Engine.get_frames_per_second())
	# ---- 吹雪（昼。ゲームにはまだない。ここで作る）
	day.hour = 13.0
	await create_timer(1.0).timeout
	main.snowfall.amount = amount * 8
	env.fog_density = 0.05
	await create_timer(2.5).timeout
	var storm_fog: float = env.fog_density
	await _hold("binoculars")
	await _click()
	await create_timer(0.8).timeout
	await _save("20_storm_basic")
	await _click()
	await _hold("binoculars_night")
	await _click()
	await create_timer(0.8).timeout
	await _save("21_storm_sight")
	await _click()
	_check("吹雪でも、やめると霧と雪が戻る", is_equal_approx(env.fog_density, storm_fog) and main.snowfall.visible)
	# 夜の吹雪
	day.hour = 23.0
	await create_timer(1.5).timeout
	await _hold("binoculars")
	await _click()
	await create_timer(0.8).timeout
	await _save("30_night_storm_basic")
	await _click()
	await _hold("binoculars_night")
	await _click()
	await create_timer(0.8).timeout
	await _save("31_night_storm_sight")
	await _click()
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)
