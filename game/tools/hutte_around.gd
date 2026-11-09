extends SceneTree
## 旧ヒュッテ（hutte.gd）をまわりの 8 方向・真上・中の何か所から撮る。屋根の穴・壁の抜けを探す用。
##   Godot --path game --resolution 960x540 -s res://tools/hutte_around.gd -- --world=tenkamori --no-player --no-snow --no-sound --dir=<フォルダ>

var args := {}
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)   # 隠れた窓は描かれないので
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main.hud:
		main.hud.visible = false
	return false


func _shot(name: String, from: Vector3, to: Vector3, fov := 65.0) -> void:
	cam.fov = fov
	cam.position = from
	cam.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(String(args.get("dir", "/tmp")).path_join(name + ".png"))


func _run() -> void:
	cam = Camera3D.new()
	cam.far = 30000.0
	main.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	var hu: Node3D = main.get_node("Tenkamori/Hutte")
	var c := Vector3(5, 4, 0)
	for k in 8:
		var a := TAU * k / 8.0
		await _shot("around_%d" % k, hu.to_global(c + Vector3(cos(a) * 30.0, 6.0, sin(a) * 30.0)), hu.to_global(c))
	await _shot("top", hu.to_global(Vector3(5, 60, 0.1)), hu.to_global(Vector3(5, 0, 0)), 50.0)
	# 中: ホールから上・休憩室の隅・風除室・北西の棟の戸
	await _shot("in_hall_up", hu.to_global(Vector3(0, 1.8, 0)), hu.to_global(Vector3(0.5, 9, 1)), 90.0)
	await _shot("in_rest_corner", hu.to_global(Vector3(15.5, 2.0, 3.5)), hu.to_global(Vector3(3, 4.5, -3)), 90.0)
	await _shot("in_rest_to_hall", hu.to_global(Vector3(10, 1.8, 0)), hu.to_global(Vector3(-2, 4, 0)), 90.0)
	await _shot("in_vest", hu.to_global(Vector3(0, 1.8, -3)), hu.to_global(Vector3(0, 2.5, -8)), 90.0)
	await _shot("in_rest_up", hu.to_global(Vector3(6, 1.8, 0)), hu.to_global(Vector3(4, 8, 2)), 90.0)
	await _shot("in_rest_se", hu.to_global(Vector3(6, 1.7, 0)), hu.to_global(Vector3(17, 4.5, 0)), 90.0)   # 南東の妻（代表の画面と同じ向き）
	await _shot("in_hall_nw", hu.to_global(Vector3(1.5, 1.7, 0)), hu.to_global(Vector3(-3, 5.5, 0)), 90.0)
	# 入口（駐車場の側）: 閉まっている戸 → 人が近づいて開いた戸
	await _shot("door_closed", hu.to_global(Vector3(-1.2, 1.8, -16)), hu.to_global(Vector3(-0.8, 2.0, -8)), 60.0)
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	main.add_child(body)
	body.global_position = hu.to_global(Vector3(-1.2, 1.7, -9.3))
	for i in 90:
		await physics_frame
	await _shot("door_open", hu.to_global(Vector3(-1.2, 1.8, -16)), hu.to_global(Vector3(-0.8, 2.0, -8)), 60.0)
	body.global_position = hu.to_global(Vector3(-3.0, 1.7, 0.0))
	for i in 90:
		await physics_frame
	await _shot("door_wing", hu.to_global(Vector3(1.5, 1.8, 2.5)), hu.to_global(Vector3(-2.25, 1.4, 0)), 75.0)
	# ゲレンデの側の入口（代表の冬の写真と同じ向き）
	await _shot("slope_entry", hu.to_global(Vector3(1.8, 1.5, 14.5)), hu.to_global(Vector3(-0.6, 2.6, 8)), 75.0)
	# 始める所から
	var st: Vector3 = main.start_pos()
	await _shot("spawn", Vector3(st.x, main.height(st.x, st.z) + 1.6, st.z), preload("res://tenkamori.gd").start_look(), 75.0)
	quit()
