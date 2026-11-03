extends SceneTree
## 大きな山（mountain.gd）の形を、決まった何か所から撮る（直す前と後を並べる用）。1 回の起動でまとめて撮る。
##   Godot --path game --resolution 1280x800 -s res://tools/mountain_views.gd -- --no-player --no-snow --dir=/path/shots [--tag=before]
## 撮るもの（<tag>_<名前>.png）:
##   top        真上から（正射影、上が北。山の全体）
##   side       東から横に（斜面の縦の起伏）
##   north      ロッジの側（北）から山を見上げる
##   mid        斜面の途中（まんなかの高さ）から下を見る
##   climb      麓から登る向き（押して登る人の目）
##   kick_<n>   ジャンプ台の寄り（Mountain.KICKERS があるとき。なければ前のジャンプ台）。kick_<n>_near は縁の近く、kick_<n>_ride は踏み切りへ向かう目

const Mountain := preload("res://mountain.gd")

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
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/mountain_views"))
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main.hud:
		main.hud.visible = false
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	return false


func _y(x: float, z: float) -> float:
	return main.height(x, z)


func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	var path: String = args.get("dir", "/tmp/mountain_views").path_join("%s_%s.png" % [args.get("tag", "now"), name])
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _look(name: String, from: Vector3, to: Vector3, fov := 55.0) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = fov
	cam.position = from
	cam.look_at(to)
	await _shot(name)


func _run() -> void:
	for i in 20:
		await process_frame
	cam = Camera3D.new()
	cam.far = 1200
	main.add_child(cam)
	cam.make_current()
	if main.sun_light:
		main.sun_light.directional_shadow_max_distance = 400
	var top := 496.0   # 直す前と同じ所から撮る（前の頂上の z）
	var mid_z := (225.0 + top) * 0.5
	# 真上
	main.env.fog_enabled = false
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 330
	cam.position = Vector3(0, 400, 420)
	cam.rotation = Vector3(-PI / 2, 0, 0)
	await _shot("top")
	# 横（東から）
	await _look("side", Vector3(260, 45, mid_z + 10), Vector3(-10, 30, mid_z + 10), 55.0)
	main.env.fog_enabled = true
	# 北から見上げる
	await _look("north", Vector3(-10, 30, 150), Vector3(-10, 40, mid_z), 60.0)
	# 斜面の途中から下を見る
	var cx := -10.0   # 直す前と同じ所から撮る（前のコースのまんなか）
	await _look("mid", Vector3(cx + 4, _y(cx + 4, mid_z + 10) + 2.0, mid_z + 10), Vector3(cx, _y(cx, mid_z - 40), mid_z - 40), 70.0)
	# 麓から登る向き（押して登る人の目）
	var bz := 245.0
	await _look("climb", Vector3(cx, _y(cx, bz) + 1.7, bz), Vector3(cx, _y(cx, bz + 40) + 1.0, bz + 40), 70.0)
	# ジャンプ台の寄り（横の斜め上から）
	var consts: Dictionary = (Mountain as GDScript).get_script_constant_map()
	if not consts.has("KICKERS"):
		var lip: float = (Mountain as GDScript).call("section", "助走")[1]
		await _look("kick_0", Vector3(cx + 18, _y(cx, lip) + 6, lip - 6), Vector3(cx, _y(cx, lip), lip + 2), 55.0)
	else:
		for i in consts["KICKERS"].size():
			var k: Dictionary = (Mountain as GDScript).call("kicker", i)
			var lip: Vector2 = k.lip
			var f: Vector2 = k.f
			var side := Vector2(-f.y, f.x)
			var at := lip + side * 13.0 + f * 7.0
			await _look("kick_%d" % i, Vector3(at.x, _y(at.x, at.y) + 4.0, at.y), Vector3(lip.x, _y(lip.x, lip.y) + 0.5, lip.y), 55.0)
			# 近くから（縁の斜め前。リボンと縫い目が見える）
			var near := lip + f * 3.5 + side * 4.5
			await _look("kick_%d_near" % i, Vector3(near.x, _y(near.x, near.y) + 2.2, near.y), Vector3(lip.x - f.x * 2.0, _y(lip.x, lip.y) + 0.6, lip.y - f.y * 2.0), 50.0)
			# 踏み切りへ向かう人の目（手前から）
			var back := lip - f * 16.0
			await _look("kick_%d_ride" % i, Vector3(back.x, _y(back.x, back.y) + 1.6, back.y), Vector3(lip.x + f.x * 20.0, _y(lip.x + f.x * 20.0, lip.y + f.y * 20.0), lip.y + f.y * 20.0), 70.0)
	quit()
