extends SceneTree
## 大山（grand_mountain.gd）を、決まった何か所から撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/grand_mountain_views.gd -- --no-player --no-snow --dir=/path/shots

const Grand := preload("res://grand_mountain.gd")

var args := {}
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/grand_views"))
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main.hud:
		main.hud.visible = false
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	return false


func _y(x: float, z: float) -> float:
	return main.height(x, z)


func _look(name: String, from: Vector3, to: Vector3, fov := 55.0) -> void:
	if args.has("only") and not (name in args["only"].split(",")):
		return
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = fov
	cam.position = from
	cam.look_at(to)
	for i in 8:
		await process_frame
	var path: String = args.get("dir", "/tmp/grand_views").path_join("%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("保存: %s  %d fps  描いた物 %d  描いた三角 %d" % [path, Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


## ソリと人の大きさが分かる絵: 段へ滑り込んで止まったソリ（滑りあと付き）を、横と後ろから
func _ride_shot() -> void:
	if args.has("only") and not ("ride_bench" in args["only"].split(",")):
		return
	var sled: RigidBody3D = main.sled
	if sled == null:
		return
	const SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
	var gs := GDScript.new()
	gs.source_code = SRC
	gs.reload()
	sled.reset_to(Vector3(585.0, _y(585.0, Grand.SZ) + 0.3, Grand.SZ))
	sled.rotation.y = PI / 2
	sled.parked = false
	for i in 3:
		var d := Node3D.new()
		d.set_script(gs)
		d.sled = sled
		main.add_child(d)
		sled.mount(d)
	var w := 0.0
	while w < 40.0:
		await physics_frame
		w += 1.0 / 60.0
		if sled.linear_velocity.length() < 1.5 and w < 3.0:
			sled.lean(0.0, true)
		if w > 8.0 and sled.linear_velocity.length() < 0.15:
			break
	var p := sled.global_position
	print("段で止まったソリ: x=%.0f z=%.0f 高さ %.1f m（%.0f 秒）" % [p.x, p.z, p.y - 3.0, w])
	await _look("ride_bench", p + Vector3(-5.0, 2.2, 11.0), p + Vector3(6.0, 2.0, 0.0), 60.0)
	await _look("ride_bench_up", p + Vector3(-12.0, 2.0, 2.0), p + Vector3(40.0, 6.0, 0.0), 60.0)


## 重さ: 大山の地面と飾りを隠したときと出したときの、描く物の数と三角の数
func _perf() -> void:
	var grand: Array[Node3D] = []
	for n in main.get_children():
		if n.name.begins_with("GrandGround") or n.name == "GrandMountain":
			grand.append(n)
	var spots := [["ロッジの前から大山", _eye(-5, 80), Vector3(Grand.SX, 70, Grand.SZ)], ["丘の頂上からロッジ", _eye(0, 0), Vector3(-35, 3, 98)],
			["大きな山の頂上から大山", _eye(-5, 480), Vector3(Grand.SX, 70, Grand.SZ)], ["段の上から頂上", _eye(490, 20), Vector3(Grand.SX, 125, Grand.SZ)],
			["頂上からロッジの向き", _eye(700, 32), Vector3(0, 0, 60)]]
	for sp in spots:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 75.0
		cam.position = sp[1]
		cam.look_at(sp[2])
		var line: String = sp[0]
		for on in [false, true]:
			for g in grand:
				g.visible = on
			for i in 20:
				await process_frame
			var t0 := Time.get_ticks_usec()
			for i in 60:
				await process_frame
			line += "  %s: 描く物 %d・三角 %d・1 コマ %.1f ms" % ["大山あり" if on else "なし", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), (Time.get_ticks_usec() - t0) / 60000.0]
		print(line)


## 立つ高さ（雪から目の高さ）
func _eye(x: float, z: float, h := 1.6) -> Vector3:
	return Vector3(x, _y(x, z) + h, z)


func _run() -> void:
	for i in 20:
		await process_frame
	cam = Camera3D.new()
	cam.far = 3000
	main.add_child(cam)
	cam.make_current()
	# 遠くから
	await _look("from_lodge", _eye(-5, 80), Vector3(Grand.SX, 70, Grand.SZ), 50.0)
	await _look("from_hill", _eye(0, 0), Vector3(Grand.SX, 70, Grand.SZ), 50.0)
	await _look("from_south", Vector3(450, 120, 780), Vector3(450, 50, 32), 60.0)
	await _look("from_mountain", _eye(-5, 480, 3.0), Vector3(Grand.SX, 70, Grand.SZ), 50.0)
	await _look("from_foot", _eye(150, 30), Vector3(Grand.SX, 90, Grand.SZ), 55.0)
	await _look("ridge_foot", _eye(165, 58), _eye(240, 90, 8.0), 60.0)
	await _look("from_north", Vector3(420, 70, -290), Vector3(540, 90, 32), 55.0)
	await _look("ridge_mid", _eye(330, 62, 2.0), _eye(420, 92, 2.0), 60.0)
	await _look("ridge_bench", _eye(470, 98, 2.0), _eye(530, 76, 2.0), 60.0)
	# 段
	await _look("bench_up", _eye(490, 20), Vector3(Grand.SX, 125, Grand.SZ), 60.0)
	await _look("bench_across", _eye(505, -40), _eye(505, 90), 70.0)
	await _look("bench_down", _eye(540, 30), _eye(250, 30, -60.0), 65.0)
	await _look("rim_down", _eye(462, 28), _eye(300, 28, -30.0), 65.0)
	await _look("slope_to_bench", _eye(610, 30), _eye(470, 30), 60.0)
	await _look("summit_west", _eye(700, 32, 2.0), Vector3(0, 0, 60), 65.0)
	await _look("summit_east", _eye(712, 32, 2.0), Vector3(1100, 0, 40), 65.0)
	await _look("summit_north", _eye(704, 26, 2.0), Vector3(650, 0, -500), 65.0)
	# 継ぎ目
	await _look("seam", _eye(140, 10, 1.2), _eye(110, 10), 60.0)
	await _look("seam_side", _eye(128, -20, 1.2), _eye(128, 40), 60.0)
	await _look("rim_below", _eye(375, 25, 2.0), Vector3(540, 100, 30), 55.0)
	for i in Grand.KICKERS.size():
		var k: Dictionary = Grand.kicker(i)
		var lip: Vector2 = k.lip
		var f: Vector2 = k.f
		var q := Vector2(-f.y, f.x)
		var a := lip - f * 12.0 + q * 5.0
		await _look("kick_%d" % (i + 1), _eye(a.x, a.y, 3.0), _eye(lip.x, lip.y, 0.5), 50.0)
	await _look("rail", _eye(Grand.RAIL_BOTTOM.x - 8.0, Grand.RAIL_BOTTOM.y + 7.0, 2.0), _eye(Grand.RAIL_BOTTOM.x + 8.0, Grand.RAIL_BOTTOM.y), 55.0)
	main.env.fog_enabled = false
	await _look("profile", Vector3(480, 90, -950), Vector3(480, 70, 32), 50.0)
	await _look("profile_oblique", Vector3(120, 170, -420), Vector3(500, 70, 32), 55.0)
	main.env.fog_enabled = true
	await _ride_shot()
	await _perf()
	# 上から
	main.env.fog_enabled = false
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1100
	cam.position = Vector3(450, 600, 200)
	cam.rotation = Vector3(-PI / 2, 0, 0)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(args.get("dir", "/tmp/grand_views").path_join("top.png"))
	quit()
