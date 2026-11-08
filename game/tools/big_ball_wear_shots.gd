extends SceneTree
## 転がす大玉の耐久（big_ball.gd の show_hurt・crumble）の絵。高台の平らな雪の上に半径 1 m の玉を置き、同じ向きから撮る。
##   Godot --path game --resolution 960x540 --fixed-fps 60 -s res://tools/big_ball_wear_shots.gd -- --dir=/path/out --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   wear_0.jpg  新しい玉
##   wear_1.jpg  投げた雪玉を 4 個当てた（小さなへこみ・はじけた縫い目）
##   wear_2.jpg  そのうえ、本物のソリを 6 m/s で 1 回ぶつけた（大きなへこみ・色が少し灰がかる）
##   wear_3.jpg  さらにソリを 6 m/s で（崩れた瞬間: 雪のかたまりが飛び散る）
##   wear_4.jpg  崩れて 1.5 秒（かたまりが雪の上に転がり、崩れた雪の山）
##   wear_5.jpg  崩れて 5.5 秒

const BigBall := preload("res://big_ball.gd")
const SPOT := Vector2(40.0, 100.0)

var args := {}
var main: Node3D
var p: CharacterBody3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg(dir.path_join(name), 0.9)
	print("撮った: ", dir.path_join(name))


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _ram(b: RigidBody3D, v: float) -> void:
	var sled: RigidBody3D = main.sled
	var from := Vector2(b.global_position.x - (b.r + sled.HALF.y + 1.0), b.global_position.z)
	sled.crashed = false
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	sled.rotation.y = atan2(-1.0, 0.0)
	sled.parked = false
	await _ticks(20)
	sled.linear_velocity = Vector3(v, 0, 0)


func _run() -> void:
	await create_timer(1.0).timeout
	p = main.player
	var g: float = main.height(SPOT.x, SPOT.y)
	p.global_position = Vector3(SPOT.x + 10.0, g + 0.5, SPOT.y + 14.0)
	p.reset_physics_interpolation()
	var b: RigidBody3D = main.emotes._spawn_big({"ball": 900, "point": Vector3(SPOT.x, g, SPOT.y), "r": 1.0, "who": -1})
	b.reset_physics_interpolation()
	cam = Camera3D.new()
	cam.fov = 55.0
	main.add_child(cam)
	var c := Vector3(SPOT.x, g + 1.0, SPOT.y)
	cam.global_position = c + Vector3(-3.2, 1.0, 3.6)
	cam.look_at(c + Vector3(-0.4, -0.2, 0.0))
	cam.make_current()
	await create_timer(1.0).timeout
	await _shot("wear_0.jpg")
	# 雪玉を 4 個（カメラの側の面へ）
	for k in 4:
		var at: Vector3 = b.global_position + Vector3(-2.5 + k * 0.4, 0.3 + 0.25 * (k % 2), 3.0)
		main.emotes._spawn_ball({"who": p.id, "ball": 800 + k, "origin": at, "velocity": (b.global_position + Vector3(-0.5, 0.1 * k, 0.4) - at).normalized() * 12.0})
		await _ticks(20)
	await create_timer(1.2).timeout
	print("雪玉 4 個: 減った %.1f / %.1f" % [b.wear, b.max_wear()])
	await _shot("wear_1.jpg")
	await _ram(b, 6.0)
	await create_timer(1.5).timeout
	print("ソリ 1 回: 減った %.1f / %.1f" % [b.wear, b.max_wear()])
	main.sled.reset_to(Vector3(0, main.height(0, 38) + 0.3, 38))
	await create_timer(1.5).timeout
	await _shot("wear_2.jpg")
	await _ram(b, 6.0)
	var t := 0.0
	while is_instance_valid(b) and not b.broken and t < 3.0:
		await physics_frame
		t += 1.0 / 60.0
	print("ソリ 2 回目: %s" % ("崩れた" if not is_instance_valid(b) or b.broken else "崩れない"))
	await _ticks(8)
	await _shot("wear_3.jpg")
	main.sled.reset_to(Vector3(0, main.height(0, 38) + 0.3, 38))
	await create_timer(1.5).timeout
	await _shot("wear_4.jpg")
	await create_timer(4.0).timeout
	await _shot("wear_5.jpg")
	quit()
