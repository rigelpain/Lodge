extends SceneTree
## 手の材料に吊る紙の札（hold_tag.gd）の確かめ。本番の流れで撮る（文字の札は出ないように消す）。
##   Godot --path game --resolution 1920x1080 -s res://tools/hold_tag_shots.gd -- --bots=0 --lodge-bots=0 --no-pip --no-sound --no-snow --dir=/path/shots
## 01 買った直後（たい焼き: プレス機・次に乾燥機）  02 プレス機のあと（乾燥機・次にたい焼き）  03 できあがり（札なし）
## 04 持ち替え: 空の手（札なし）  05 焼きそばの材料（乾燥機・次にアイロン台）  06 ココアの材料（スチーマー・次にココア）
## 02b 装置の前  07 三人称  08 厨房を見上げる（板がない）  09 視野角 100°
## 見回しの振れ（hold_tag.gd の swing_now）も数字で出す。シート: <dir>/hold_tag_sheet.png

const Food := preload("res://food.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var _shots: Array[Image] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/hold_tag")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.craft_ui.gear_open:   # 撮っているあいだに窓へキーが入って装備の画面が開いたとき
		main.craft_ui.close_gear()
		await _wait(0.2)
	main.craft_ui.set("_name_t", 0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_dir().path_join(name + ".png"))
	img.convert(Image.FORMAT_RGB8)
	img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	_shots.append(img)
	var t: Node3D = p._hold_tag
	print("%s: 手に %s 札 %s" % [name, p.held(), t != null and t.visible])


func _station(kind: String) -> Node:
	for st in main.stations:
		if st.kind == kind:
			return st
	return null


func _buy(dish: String) -> void:
	main.emotes.balls[p.id] = 5
	main.food_ui.open()
	main.food_ui.select(Food.ORDER.find(dish))
	main.food_ui.buy()
	main.food_ui.close()
	main.emotes.balls[p.id] = 0   # 袖の雪玉は写さない
	await _wait(0.5)


## 厨房を食堂の側から見る
func _view() -> void:
	var slot: Node3D = main.kitchen["press"].get_parent()
	var mid: Vector3 = (main.kitchen["press"].global_position + main.kitchen["drink"].global_position) * 0.5
	var at: Vector3 = mid + slot.global_basis.z * 8.5
	at.y = p.global_position.y
	p.global_position = at
	var d: Vector3 = mid + Vector3.UP * 1.4 - at
	p.rotation.y = atan2(-d.x, -d.z)
	p.set("_pitch", -0.08)
	p.velocity = Vector3.ZERO


func _cook(kind: String) -> void:
	var st := _station(kind)
	var dev: Node3D = st.get_parent()
	var slot: Node3D = dev.get_parent()
	p.global_position = dev.global_position + slot.global_basis.z * 2.2 + Vector3.UP * 0.1
	await _wait(0.4)
	st.use(p)
	await _wait(0.3)
	while st.busy():
		await process_frame
	await _wait(0.8)


func _run() -> void:
	await _wait(4.0)
	p = main.player
	p.set_third(false)
	main.settings.sync("hud_debug", false)
	main.hud.idle_limit = 0.0   # 無操作で HUD を引っこめない（重なりを見る）
	await _buy("taiyaki")
	_view()
	await _wait(0.8)
	await _shot("01_bought")
	# 見回したときの札の振れと、手の材料の動く幅
	var swing_max := 0.0
	var yaw0: float = p.rotation.y
	var t0 := Time.get_ticks_msec()
	var t := 0.0
	while t < 2.0:   # いちばん速い所で 1 秒に 3 rad（速めの見回し）
		await process_frame
		t = (Time.get_ticks_msec() - t0) / 1000.0
		p.rotation.y = yaw0 + sin(t * TAU) * 0.5
		swing_max = maxf(swing_max, absf(p._hold_tag.swing_now()))
	p.rotation.y = yaw0
	print("見回し: 札の振れ %.1f° （札の下の端で %.0f px）" % [rad_to_deg(swing_max), sin(swing_max) * 0.3 * 1080.0])
	await _wait(1.5)
	await _cook("press")
	_view()
	await _wait(0.6)
	await _shot("02_after_press")
	# 装置の前（F の案内と重ならないか）
	var dry: Node3D = main.kitchen["dryer"]
	p.global_position = dry.global_position + (dry.get_parent() as Node3D).global_basis.z * 2.6 + Vector3.UP * 0.1
	var dd: Vector3 = dry.global_position + Vector3.UP * 1.2 - p.global_position
	p.rotation.y = atan2(-dd.x, -dd.z)
	p.set("_pitch", -0.1)
	await _wait(0.6)
	await _shot("02b_near_dryer")
	await _cook("dryer")
	_view()
	await _wait(0.6)
	await _shot("03_done")
	var i: int = main.craft.hands.get(p.id, -1)
	main.craft.send({"kind": "hand", "who": p.id, "slot": -1})
	await _wait(0.4)
	await _shot("04_empty_hand")
	main.craft.bags[p.id][i] = {}
	await _wait(0.2)
	await _buy("yakisoba")
	_view()
	await _wait(0.5)
	await _shot("05_yakisoba")
	main.craft.bags[p.id][main.craft.hands.get(p.id, 0)] = {}
	await _wait(0.2)
	await _buy("cocoa")
	_view()
	await _wait(0.5)
	await _shot("06_cocoa")
	p.set_third(true)
	await _wait(0.8)
	await _shot("07_third")
	p.set_third(false)
	var board: Node = main.find_child("MenuBoard", true, false)
	print("板のノード: ", board)
	p.set("_pitch", 0.35)
	await _wait(0.5)
	await _shot("08_no_board")
	p.base_fov = 100.0   # 視野角を変えても札の大きさと位置は同じ
	_view()
	await _wait(1.5)
	await _shot("09_fov100")
	var sheet := Image.create(640 * 3, 360 * 3, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.95, 0.92, 0.85))
	for k in _shots.size():
		sheet.blit_rect(_shots[k], Rect2i(0, 0, 640, 360), Vector2i(640 * (k % 3), 360 * (k / 3)))
	sheet.save_png(_dir().path_join("hold_tag_sheet.png"))
	quit()
