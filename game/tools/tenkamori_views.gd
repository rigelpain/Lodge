extends SceneTree
## 天下森のワールド（tenkamori.gd）を、決まった何か所から撮る。景色（谷の向かいの山）が見えるかを確かめる用。
##   Godot --path game --resolution 1280x720 -s res://tools/tenkamori_views.gd -- --world=tenkamori --no-player --no-snow --dir=/path/shots
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
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/tenka_views"))
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
	for i in 10:
		await process_frame
	var cur := root.get_camera_3d()
	if cur != cam:
		print("  別のカメラが映している: %s %s" % [cur.get_path() if cur else "なし", cur.global_position.round() if cur else Vector3.ZERO])
	var path: String = args.get("dir", "/tmp/tenka_views").path_join("%s.png" % name)
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
	var down := Vector3(413, 0, -669).normalized()   # コースを下る向き（北北東）
	# 麓: リフトの乗り場から、ゲレンデを見上げる
	await _look("base_up", _eye(30, -10, 1.7), Vector3(-260, _y(-260, 420) + 10, 420))
	# 中ほど: コースを下る向き（谷の向かいの山）
	var mid := Vector3(-200, 0, 330)
	await _look("mid_down", _eye(mid.x, mid.z), _eye(mid.x, mid.z) + down * 800.0 + Vector3(0, -60, 0))
	# 頂上: 下る向きと、左右
	var top := Vector3(-405, 0, 655)
	var e := _eye(top.x, top.z)
	await _look("top_down", e, e + down * 1000.0 + Vector3(0, -90, 0))
	await _look("top_left", e, e + down.rotated(Vector3.UP, 0.8) * 1000.0 + Vector3(0, -80, 0))
	await _look("top_right", e, e + down.rotated(Vector3.UP, -0.8) * 1000.0 + Vector3(0, -80, 0))
	await _look("top_back", e, e - down * 1000.0)
	# 上から見た全体
	await _look("air", Vector3(500, 700, -500), Vector3(-200, 50, 350), 50.0)
	# ヒュッテ（PV と同じ向きから）: 正面の斜め・入口・玄関ホール・食堂
	var hu: Node3D = main.get_node_or_null("Tenkamori/Hutte")
	if hu:
		await _look("hutte_far", hu.to_global(Vector3(-14, 9, 40)), hu.to_global(Vector3(3, 3.5, 0)), 55.0)   # ゲレンデの上から（計画書の外観の写真の向き）
		await _look("hutte_near", hu.to_global(Vector3(1.5, 1.6, 19)), hu.to_global(Vector3(0, 4.8, 8)), 70.0)   # ゲレンデの側の入口
		await _look("hutte_park", hu.to_global(Vector3(14, 1.6, -30)), hu.to_global(Vector3(2, 4, 0)), 62.0)    # 駐車場の側（ストリートビューの向き）
		await _look("hutte_se", hu.to_global(Vector3(38, 1.6, 6)), hu.to_global(Vector3(8, 4, 0)), 62.0)        # 南東の妻
		await _look("hutte_roof", hu.to_global(Vector3(-16, 18, 24)), hu.to_global(Vector3(3, 5, 0)), 55.0)          # 屋根の取り合いを上から
		await _look("hutte_dining_back", hu.to_global(Vector3(14.0, 1.8, 1.0)), hu.to_global(Vector3(0, 4.0, 0)), 75.0)   # 休憩室からホールの向き
		await _look("hutte_hall", hu.to_global(Vector3(0, 2.3, -3.5)), hu.to_global(Vector3(0, 4.5, 8)), 75.0)
		await _look("hutte_dining", hu.to_global(Vector3(15.5, 2.2, -3.2)), hu.to_global(Vector3(4, 1.3, 2.5)), 75.0)
	# ヒュッテのまわりの道と駐車場
	await _look("road_air", Vector3(150, 110, -110), Vector3(45, 0, 5), 50.0)
	await _look("road_walk", _eye(88, -70, 1.7), _eye(93, 20, 2.0), 65.0)
	await _look("parking", _eye(30, -40, 1.7), _eye(48, 18, 3.0), 65.0)
	# リフトの乗り場（PV と同じ向き: 乗り場の脇から斜面を見上げる）
	await _look("lift_base", _eye(-14, -14, 1.7), _eye(-120, 180, 30.0), 65.0)
	await _look("lift_station", _eye(-22, -2, 2.0), Vector3(0, _y(0, 0) + 4.0, 0), 60.0)
	await _look("lift_mid", _eye(-180, 300, 1.7), _eye(-330, 540, 20.0), 65.0)
	await _ride()
	await _perf()
	quit()


## 重さ: 遊ぶ人の目の高さで、景色の向き・ヒュッテ・リフトを見たときの 1 コマ (ms)
func _perf() -> void:
	if not args.has("perf"):
		return
	var down := Vector3(413, 0, -669).normalized()
	var spots := [["中ほどから谷の向かい", _eye(-200, 330), _eye(-200, 330) + down * 800.0], ["頂上から谷の向かい", _eye(-405, 655), _eye(-405, 655) + down * 1000.0],
			["乗り場からゲレンデ", _eye(-14, -14), _eye(-120, 180, 30.0)], ["ヒュッテの前", _eye(20, 70), Vector3(48, 6, 24)]]
	for sp in spots:
		cam.fov = 75.0
		cam.position = sp[1]
		cam.look_at(sp[2])
		for i in 20:
			await process_frame
		var t0 := Time.get_ticks_usec()
		for i in 60:
			await process_frame
		print("%s: 描く物 %d・三角 %d・1 コマ %.1f ms" % [sp[0], RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), (Time.get_ticks_usec() - t0) / 60000.0])


## 頂上からソリを 1 人乗りで放して、どこまで下りるか（当たり判定の地面が見た目と合っているか・途中で止まらないか）
func _ride() -> void:
	if args.has("only") and not ("ride" in args["only"].split(",")):
		return
	var sled: RigidBody3D = main.sled
	const SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
	var gs := GDScript.new()
	gs.source_code = SRC
	gs.reload()
	var at := Vector3(-400, 0, 640)
	var face := atan2(-413.0, 669.0)   # 下る向き（北北東）へ前を向ける
	if args.has("rinkan"):   # 林間コースの上から、道の向きへ
		var rk: Array = []
		for p in preload("res://tenkamori.gd").map().pistes:
			if p.name == "夏虫沢林間コース":
				rk.append_array(p.line)
		var a: Vector2 = Vector2(rk[7][0], rk[7][1])
		var b: Vector2 = Vector2(rk[9][0], rk[9][1])
		at = Vector3(a.x, 0, a.y)
		face = atan2(-(b - a).x, -(b - a).y)
	sled.reset_to(Vector3(at.x, _y(at.x, at.z) + 0.6, at.z))
	sled.rotation.y = face
	sled.parked = false
	var d := Node3D.new()
	d.set_script(gs)
	d.sled = sled
	main.add_child(d)
	sled.mount(d)
	var w := 0.0
	var next := 0.0
	var top := 0.0
	while w < 120.0:
		await physics_frame
		w += 1.0 / 60.0
		var v := sled.linear_velocity.length()
		top = maxf(top, v)
		if w >= next:
			var p := sled.global_position
			print("ソリ %3.0f 秒: x=%5.0f z=%5.0f 雪から %.2f m  速さ %.1f m/s" % [w, p.x, p.z, p.y - _y(p.x, p.z), v])
			next += 10.0
		if w > 10.0 and v < 0.2 and not args.has("rinkan") or w > 25.0 and v < 0.2:
			break
	var p := sled.global_position
	print("止まった: x=%.0f z=%.0f（%.0f 秒、いちばん速いとき %.1f m/s）" % [p.x, p.z, w, top])
	await _look("ride_end", p + Vector3(6, 3, 8), p)
