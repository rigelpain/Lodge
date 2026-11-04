extends SceneTree
## 乗っているソリのまわりの地面の見え方を撮る（確かめ用）。ロッジの中と雪の上、止まっている所と滑っている所を、後ろからと一人称で。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/sack_ground_shots.gd -- --bots=0 --no-sound --no-pip --no-selfcam --day=100000 --time=14 --dir=/path/shots [--sled=mid] [--probe]
## --sled= なしは米袋（N で出して乗る）。--sled=small|mid|large は、そのソリに乗る。--time= で昼と夜を切り替える
## --probe: ロッジの中で止めたまま、足もとの影の板・人形の丸い影を順に隠して撮り、光っているのがどれかを確かめる

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
	current_scene = main   # 昼夜の時計（daycycle.gd）が、今の場面から太陽を探す
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/sack_ground")


func _wait(t: float) -> void:
	await create_timer(t).timeout


## ソリの後ろ斜め上から（view "back"）、または一人称の目で（view "fp"）
func _shot(name: String, view := "back") -> void:
	if main.hud:
		main.hud.visible = false
	if view == "fp":
		p.set_third(false)
		p.set("_pitch", -0.7)
		p.cam.make_current()
	else:
		var back: Vector3 = follow.global_basis.z
		back.y = 0.0
		back = back.normalized()
		cam.global_position = follow.global_position + back * 3.2 + back.cross(Vector3.UP) * 1.1 + Vector3.UP * 1.9
		cam.look_at(follow.global_position + Vector3.UP * 0.2)
		cam.reset_physics_interpolation()
		p.set_third(true)
		cam.make_current()
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join("%s_%s.png" % [kind, name]))
	print("撮った: ", kind, "_", name, "  速さ %.1f m/s" % follow.linear_velocity.length())


## ソリを止めて、at に yaw の向きで置く
func _place(at: Vector3, yaw: float) -> void:
	follow.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	follow.linear_velocity = Vector3.ZERO
	follow.angular_velocity = Vector3.ZERO
	follow.reset_physics_interpolation()


func _run() -> void:
	await _wait(2.5)
	p = main.player
	if main.settings:
		main.settings.set_open(false)
	cam = Camera3D.new()
	cam.fov = 50
	cam.cull_mask = 0xFFFFF
	root.add_child(cam)
	kind = args.get("sled", "sack")
	var lodge: Node3D = main.get_node("Lodge")
	var inside: Vector3 = lodge.to_global(Vector3(5.0, main.LODGE_FLOOR + 0.25, 5.0))
	await _ride(inside)
	follow = p.sled
	var yaw := PI / 2.0   # 東の壁へ向けて（窓のある南が横に来る）
	# ロッジの中: 止まっている
	follow.freeze = true
	_place(inside, yaw)
	await _wait(1.0)
	await _shot("lodge_still")
	await _shot("lodge_still_fp", "fp")
	if args.has("probe"):
		var blob: Node3D = follow.get("_blob")
		blob.visible = false
		await _shot("probe_no_blob")
		blob.visible = true
		var shade: Node3D = p.doll.get("_foot_shade")
		shade.visible = false
		await _shot("probe_no_foot_shade")
		shade.visible = true
		quit()
		return
	follow.freeze = false
	# ロッジの中: 滑っている
	_place(inside + Vector3.UP * 0.1, yaw)
	follow.linear_velocity = -Basis(Vector3.UP, yaw).z * 7.0
	await _wait(0.5)
	await _shot("lodge_slide")
	_place(inside + Vector3.UP * 0.1, yaw)
	follow.linear_velocity = -Basis(Vector3.UP, yaw).z * 7.0
	await _wait(0.5)
	await _shot("lodge_slide_fp", "fp")
	# 雪の上: 平らな所で止まっている
	var snow: Vector3 = lodge.to_global(Vector3(-6.0, 0, 30.0))
	snow.y = main.height(snow.x, snow.z) + 0.2
	follow.freeze = true
	_place(snow, 0.0)
	await _wait(0.6)
	await _shot("snow_still")
	follow.freeze = false
	# 雪の上: 坂を滑っている
	var hill := Vector3(0, 0, float(args.get("z", "16")))
	hill.y = main.height(hill.x, hill.z) + 0.3
	var down := Vector3(hill.x, 0, hill.z).normalized()
	_place(hill, atan2(down.x, down.z) + PI)
	follow.linear_velocity = down * 6.0
	await _wait(0.8)
	await _shot("snow_slide")
	quit()


func _ride(at: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.set_third(true)
	await _wait(0.4)
	if kind == "sack":
		p.toggle_sack()
		await _wait(1.6)
		return
	var s: RigidBody3D = main.sled
	s.global_position = at + Vector3.UP * 0.2
	s.linear_velocity = Vector3.ZERO
	s.reset_physics_interpolation()
	await _wait(0.4)
	p.sled = s
	p.get_on()
	await _wait(0.6)
