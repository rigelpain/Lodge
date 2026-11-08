extends SceneTree
## ソリの底が雪に埋もれて見えるかを撮る（確かめ用）。同じ所・同じカメラで、平らな所と斜面、止まっている所と滑っている所を、横の低い所から。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/sled_sink_shots.gd -- --sled=small --bots=0 --roam-bots=0 --lodge-bots=0 --no-sound --no-pip --no-selfcam --day=100000 --time=14 --dir=/path/shots
## --sled= のソリにあなたが乗る（米袋は N で出して乗る）。--tag= を名前の頭に付ける（直す前・後の見比べ用）

const FLAT := Vector3(-30, 0, 30)    # 丘のふもとの西の平らな所（ロッジの外）
const SLOPE := Vector3(0, 0, 20)

var args := {}
var main: Node3D
var p: CharacterBody3D
var cam: Camera3D
var follow: RigidBody3D
var kind := "sack"


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
	return args.get("dir", "/tmp/sled_sink")


func _wait(t: float) -> void:
	await create_timer(t).timeout


## ソリの横（右）の低い所から、ソリの底の高さを見る
func _shot(name: String, side := 1.0) -> void:
	if main.hud:
		main.hud.visible = false
	var right: Vector3 = follow.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var fwd: Vector3 = -follow.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var c: Vector3 = follow.global_position
	var at := c + right * side * 2.6 + fwd * 0.6
	at.y = main.height(at.x, at.z) + 0.45
	cam.global_position = at
	cam.look_at(c + Vector3.UP * 0.1)
	cam.reset_physics_interpolation()
	cam.make_current()
	await process_frame
	await process_frame
	await process_frame
	var tag: String = args.get("tag", "")
	root.get_texture().get_image().save_png(_dir().path_join("%s%s_%s.png" % [tag + "_" if tag != "" else "", kind, name]))
	print("撮った: ", kind, "_", name, "  速さ %.1f m/s" % follow.linear_velocity.length())


func _place(at: Vector3, yaw: float) -> void:
	follow.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, main.height(at.x, at.z) + 0.25, at.z))
	follow.linear_velocity = Vector3.ZERO
	follow.angular_velocity = Vector3.ZERO
	follow.reset_physics_interpolation()


func _run() -> void:
	await _wait(2.5)
	p = main.player
	if main.settings:
		main.settings.set_open(false)
	cam = Camera3D.new()
	cam.fov = 45
	root.add_child(cam)
	kind = args.get("sled", "sack")
	if args.has("empty"):
		await _empty()
		quit()
		return
	await _ride(FLAT)
	follow = p.sled
	# 平らな所で止まっている（ペグのように留めるため、少しのあいだ固める）
	_place(FLAT, PI)
	await _wait(1.5)
	await _shot("flat_still")
	# 斜面で止まっている（頂上向き。乗っていると滑り出すので、置いたら固める）
	_place(SLOPE, 0.0)
	await _wait(0.4)
	follow.freeze = true
	await _wait(0.3)
	await _shot("slope_still")
	follow.freeze = false
	# 斜面を滑っている（ふもとへ）
	_place(Vector3(0, 0, 8), PI)
	follow.linear_velocity = Vector3(0, 0, 4.0)
	await _wait(1.6)
	await _shot("slope_slide")
	quit()


func _ride(at: Vector3) -> void:
	p.global_position = Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z)
	p.velocity = Vector3.ZERO
	p.set_third(true)
	await _wait(0.4)
	if kind == "sack":
		p.toggle_sack()
		await _wait(1.6)
		return
	var s: RigidBody3D = main.sled
	s.global_position = p.global_position + Vector3.UP * 0.2
	s.linear_velocity = Vector3.ZERO
	s.reset_physics_interpolation()
	await _wait(0.4)
	p.sled = s
	p.get_on()
	await _wait(0.6)


## 乗っていないソリ（押して・紐で運ぶとき）を、外から（横の低い所）と、荷台の中を上からのぞいて撮る
func _empty() -> void:
	follow = main.sled
	p.global_position = Vector3(20, main.height(20, 60) + 0.3, 60)   # あなたは離れた所に
	for c in [["flat", FLAT, PI], ["slope", SLOPE, 0.0], ["slope_side", SLOPE, PI / 2]]:
		_place(c[1], c[2])
		await _wait(1.2)
		follow.freeze = true
		await _wait(0.2)
		await _shot("empty_%s_out" % c[0])
		await _look_in("empty_%s_in" % c[0])
		follow.freeze = false


## 荷台の中を、後ろ斜め上からのぞく
func _look_in(name: String) -> void:
	if main.hud:
		main.hud.visible = false
	var c: Vector3 = follow.global_position
	var back: Vector3 = follow.global_basis.z
	cam.global_position = c + back * 1.1 + follow.global_basis.y * 1.3
	cam.look_at(c + follow.global_basis.y * 0.05 - back * 0.1, follow.global_basis.y)
	cam.reset_physics_interpolation()
	cam.make_current()
	await process_frame
	await process_frame
	await process_frame
	var tag: String = args.get("tag", "")
	root.get_texture().get_image().save_png(_dir().path_join("%s%s_%s.png" % [tag + "_" if tag != "" else "", kind, name]))
	print("撮った: ", kind, "_", name)
