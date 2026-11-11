extends SceneTree
## 旭ヶ丘のワールド（tenkamori.gd の site = asahigaoka）を、決まった何か所から撮る。景色（南南東の羊蹄山・倶知安の町）が見えるかを確かめる用。
## 所はリフトの線（map.json）から決める: 乗り場・線の中ほど・降り場と、上から見下ろした全体。
##   Godot --path game --resolution 1280x720 -s res://tools/asahi_views.gd -- --world=asahigaoka --no-player --no-snow --no-sound --dir=/path/shots
## --only=名前,名前 で一部だけ。撮るたびに 1 コマの重さ（描く物・三角）も出す

var args := {}
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	# macOS はほかの窓の後ろに隠れた窓を描かない（撮る絵が最初の 1 コマのまま止まる）。撮るあいだだけ、いちばん手前に出しておく
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	var t0 := Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	print("世界を作るのにかかった時間: %d ms" % (Time.get_ticks_msec() - t0))
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/asahi_views"))
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main.hud:
		main.hud.visible = false
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	return false


func _y(x: float, z: float) -> float:
	return main.height(x, z)


func _eye(x: float, z: float, h := 1.6) -> Vector3:
	return Vector3(x, _y(x, z) + h, z)


func _look(name: String, from: Vector3, to: Vector3, fov := 60.0) -> void:
	if args.has("only") and not (name in args["only"].split(",")):
		return
	cam.fov = fov
	cam.position = from
	cam.look_at(to)
	print("%s: カメラ %s → %s（そこの地面 %.1f）" % [name, from.round(), to.round(), _y(from.x, from.z)])
	# 窓が隠れている・別のデスクトップにあると macOS は描かない（絵が前のコマのまま止まる）。本当に描けたコマを数えて待つ（60 秒まで）
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() < f0 + 10 and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	if Engine.get_frames_drawn() < f0 + 10:
		print("  描けなかった（窓が隠れている）: %s" % name)
		return
	var cur := root.get_camera_3d()
	if cur != cam:
		print("  別のカメラが映している: %s %s" % [cur.get_path() if cur else "なし", cur.global_position.round() if cur else Vector3.ZERO])
	var path: String = args.get("dir", "/tmp/asahi_views").path_join("%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("保存: %s  描いた物 %d  描いた三角 %d" % [path,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _run() -> void:
	for i in 4:
		await process_frame
	cam = Camera3D.new()
	cam.far = 30000.0
	main.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	var m: Dictionary = preload("res://tenkamori.gd").map()
	var line: Array = m.lifts[0].line
	var bot := Vector3(line[0][0], 0, line[0][1])
	var top := Vector3(line[line.size() - 1][0], 0, line[line.size() - 1][1])
	var up := (top - bot).normalized()
	var side := Vector3(-up.z, 0, up.x)   # 広いゲレンデの側（リフトの線の北東。南西は林の島）
	var yotei := Vector3(6100, 1898.0 - 193.0, 8400)   # 羊蹄山の頂（遊びの座標）
	# 麓: 乗り場の脇から、ゲレンデを見上げる
	await _look("base_up", _eye(bot.x - up.x * 25 + side.x * 20, bot.z - up.z * 25 + side.z * 20, 1.7), Vector3(top.x, _y(top.x, top.z) + 5, top.z))
	# 始める所から乗り場の向き
	var st: Array = m.get("start", [20, 20])
	await _look("start", _eye(st[0], st[1]), _eye(0, 0, 1.0))
	# 中ほど・頂上: 下る向き（羊蹄山）
	for name in ["mid", "top"]:
		var p := bot.lerp(top, 0.5 if name == "mid" else 0.82) + side * (35.0 if name == "mid" else 14.0)
		var e := _eye(p.x, p.z)
		await _look(name + "_yotei", e, yotei + Vector3(0, -700, 0), 55.0)
		await _look(name + "_down", e, e + (bot - top).normalized() * 600.0 + Vector3(0, -80, 0))
	var e2 := _eye(top.x + side.x * 14.0 - up.x * 60.0, top.z + side.z * 14.0 - up.z * 60.0)
	await _look("top_town", e2, e2 + Vector3(1, 0, 0.15) * 1500.0 + Vector3(0, -150, 0))
	await _look("top_annupuri", _eye(top.x + side.x * 14.0 - up.x * 60.0, top.z + side.z * 14.0 - up.z * 60.0, 12.0), Vector3(-7900, 900, 5500), 40.0)
	# 羊蹄山を寄せて（形の確かめ）
	await _look("yotei_zoom", _eye(top.x + side.x * 14.0 - up.x * 60.0, top.z + side.z * 14.0 - up.z * 60.0, 3.0), yotei + Vector3(0, -500, 0), 18.0)
	# V 字の坂: ロッジの前から西を見る（右が主コース、左が初級コースとそりコース、あいだに林の島）
	await _look("v_lodge", _eye(96.0, 28.0, 2.4), _eye(-110.0, -15.0, 22.0), 80.0)
	await _look("v_plaza", _eye(62.0, 36.0, 1.7), _eye(-120.0, -20.0, 25.0), 85.0)
	# 初級コースを下から見上げる（intro-35）と、そりコースの入口
	await _look("beginner_up", _eye(40.0, 44.0, 1.7), _eye(-130.0, 52.0, 30.0), 70.0)
	await _look("sled_course", _eye(40.0, 74.0, 1.7), _eye(-60.0, 80.0, 12.0), 65.0)
	await _look("v_above", Vector3(150.0, _y(60.0, 30.0) + 110.0, 90.0), _eye(-90.0, 0.0, 10.0), 55.0)
	# 木: リフトの中ほどから南西の林の島を、近くと寄りで
	var tp := bot.lerp(top, 0.45) - side * 4.0
	await _look("trees_edge", _eye(tp.x + side.x * 14.0, tp.z + side.z * 14.0, 1.7), _eye(tp.x - side.x * 30.0, tp.z - side.z * 30.0, 6.0), 65.0)
	await _look("trees_close", _eye(tp.x - side.x * 2.0, tp.z - side.z * 2.0, 1.7), _eye(tp.x - side.x * 20.0 + up.x * 6.0, tp.z - side.z * 20.0 + up.z * 6.0, 5.0), 60.0)
	# 上から全体
	var c := bot.lerp(top, 0.5)
	await _look("above", Vector3(c.x + 250, _y(c.x, c.z) + 380, c.z + 380), Vector3(c.x, _y(c.x, c.z), c.z), 55.0)
	# ゲレンデの小物（asahi_slope.gd）
	var tw := Vector3(-222, 0, -215)
	var dn := -up
	await _look("slope_tower_low", _eye(tw.x + dn.x * 45 - side.x * 10, tw.z + dn.z * 45 - side.z * 10, 1.7), Vector3(tw.x, _y(tw.x, tw.z) + 9, tw.z), 55.0)
	await _look("slope_tower_top", Vector3(tw.x + up.x * 14 + side.x * 8, _y(tw.x, tw.z) + 24, tw.z + up.z * 14 + side.z * 8), Vector3(tw.x + dn.x * 10, _y(tw.x, tw.z) + 4, tw.z + dn.z * 10), 60.0)
	var lp := bot.lerp(top, 0.52) + side * 16.0
	await _look("slope_lights", _eye(lp.x + dn.x * 30 + side.x * 8, lp.z + dn.z * 30 + side.z * 8, 1.7), Vector3(lp.x, _y(lp.x, lp.z) + 8, lp.z), 60.0)
	var np := bot.lerp(top, 0.3) + side * 9.0
	await _look("slope_nets", _eye(np.x + side.x * 12 + dn.x * 15, np.z + side.z * 12 + dn.z * 15, 1.7), Vector3(np.x - up.x * 5, _y(np.x, np.z) + 1.0, np.z - up.z * 5), 60.0)
	await _look("slope_top_nets", Vector3(top.x + side.x * 40 + dn.x * 25, _y(top.x, top.z) + 14, top.z + side.z * 40 + dn.z * 25), Vector3(top.x + side.x * 5, _y(top.x, top.z), top.z + side.z * 5), 60.0)
	await _look("slope_divider", Vector3(50, _y(50, 5) + 4, 5), Vector3(60, _y(60, -22) + 0.5, -22), 55.0)
	await _look("slope_ramp_judge", Vector3(-134 + dn.x * 22 + side.x * 14, _y(-134, -186) + 14, -186 + dn.z * 22 + side.z * 14), Vector3(-134, _y(-134, -186) + 1, -186), 55.0)
	await _look("slope_judge", Vector3(-38 + dn.x * 14 + side.x * 5, _y(-38, -96) + 6, -96 + dn.z * 14 + side.z * 5), Vector3(-38, _y(-38, -96) + 3, -96), 60.0)
	await _look("slope_stone", Vector3(78, _y(78, 14) + 3, 14), Vector3(88, _y(88, 20) + 0.6, 20), 55.0)
	quit()
