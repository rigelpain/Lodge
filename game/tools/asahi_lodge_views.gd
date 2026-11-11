extends SceneTree
## 旭ヶ丘の休憩所「雪ん子館」（asahi_lodge.gd）とリフト乗り場を、手本の動画のコマと同じ向きから撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/asahi_lodge_views.gd -- --world=asahigaoka --no-player --no-snow --no-sound --dir=/path/shots
## --only=名前,名前 で一部だけ

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
	var lo: Node3D = main.get_node("Site/Lodge")
	var o := lo.global_position   # 屋根の北西の角・ならした地面
	var at := func(v: float, u: float, h: float) -> Vector3:
		return o + Vector3(v, h, u)
	# 正面（西）: tokyu-133
	await _look("lodge_west", at.call(-24, 15, 1.7), at.call(4, 19, 3.6), 60.0)
	# ゲレンデから遠く: rdj-190（右に羊蹄山）
	await _look("lodge_far", at.call(-48, 4, 1.7), at.call(6, 30, 3.0), 75.0)
	# 北西の角から: tokyu-60
	await _look("lodge_nw", at.call(-16, -10, 1.7), at.call(6, 10, 4.0), 60.0)
	# 南から: intro-5
	await _look("lodge_south", at.call(-10, 58, 1.7), at.call(6, 30, 3.5), 60.0)
	# 北寄りから軒先に沿って: intro-85
	await _look("lodge_along", at.call(-9, 6, 1.7), at.call(4, 30, 3.0), 70.0)
	# 東（駐車場・道の側）
	await _look("lodge_east", at.call(36, 30, 1.7), at.call(10, 22, 3.5), 60.0)
	# 中: 入口から南の窓へ、南から北のカウンターへ
	await _look("lodge_in_south", at.call(4.0, 15.8, 2.2), at.call(9, 31, 2.0), 80.0)
	await _look("lodge_in_north", at.call(8.0, 30.5, 2.2), at.call(8, 14, 3.0), 80.0)
	# 上から
	await _look("lodge_above", at.call(-30, 50, 32), at.call(8, 17, 2), 50.0)
	# リフト乗り場と柱: tokyu-75・dzk-340
	var m: Dictionary = preload("res://tenkamori.gd").map()
	var line: Array = m.lifts[0].line
	var bot := Vector3(line[0][0], 0, line[0][1])
	var top := Vector3(line[line.size() - 1][0], 0, line[line.size() - 1][1])
	var up := (top - bot).normalized()
	var side := Vector3(-up.z, 0, up.x)
	await _look("lift_bottom", _eye(bot.x - up.x * 9 + side.x * 9, bot.z - up.z * 9 + side.z * 9, 1.7), _eye(bot.x, bot.z, 2.5), 65.0)
	var p3 := Vector3(line[3][0], 0, line[3][1])
	await _look("lift_tower", _eye(p3.x - up.x * 14 + side.x * 7, p3.z - up.z * 14 + side.z * 7, 1.7), _eye(p3.x, p3.z, 6.0), 65.0)
	await _look("lift_top", _eye(top.x - up.x * 14 + side.x * 10, top.z - up.z * 14 + side.z * 10, 1.7), _eye(top.x, top.z, 2.5), 65.0)
	quit()
