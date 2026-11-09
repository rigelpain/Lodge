extends SceneTree
## ぶつかられた大玉が動く（big_ball.gd の knock・bump）の絵。高台の平らな雪の上で、同じ向きから撮る。
##   Godot --path game --resolution 960x540 --fixed-fps 60 -s res://tools/big_ball_knock_shots.gd -- --dir=/path/out --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   knock_0.jpg  ソリが来る前（半径 0.5 m の玉。足もとに目じるしの棒）
##   knock_1.jpg  中のソリが 6 m/s で当たって 2 秒（玉は目じるしから転がって離れている）
##   knock_2.jpg  手袋なしの人が走って当たる前（半径 0.3 m の玉）
##   knock_3.jpg  当たって 1.5 秒（玉は転がって離れている）

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


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


## 玉の置いた所の目じるし（細い棒）
func _mark(at: Vector3) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.03
	c.bottom_radius = 0.03
	c.height = 1.2
	m.mesh = c
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("B8402E")
	m.material_override = mat
	main.add_child(m)
	m.global_position = at + Vector3(0, 0.6, 0)


func _run() -> void:
	await create_timer(1.0).timeout
	p = main.player
	var g: float = main.height(SPOT.x, SPOT.y)
	p.global_position = Vector3(SPOT.x + 4.0, g + 0.5, SPOT.y + 16.0)
	p.reset_physics_interpolation()
	cam = Camera3D.new()
	cam.fov = 55.0
	main.add_child(cam)
	var c := Vector3(SPOT.x + 1.0, g + 0.6, SPOT.y)
	cam.global_position = c + Vector3(0.0, 2.2, 7.0)
	cam.look_at(c + Vector3(0.0, -0.3, 0.0))
	cam.make_current()
	# ソリ
	var at := Vector3(SPOT.x, g, SPOT.y)
	_mark(at)
	var b: RigidBody3D = main.emotes._spawn_big({"ball": 900, "point": at, "r": 0.5, "who": -1})
	b.reset_physics_interpolation()
	var sled: RigidBody3D = main.sled
	var from := Vector2(at.x - (0.5 + sled.HALF.y + 1.0), at.z)
	sled.crashed = false
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	sled.rotation.y = atan2(-1.0, 0.0)
	sled.parked = false
	await create_timer(1.0).timeout
	await _shot("knock_0.jpg")
	sled.linear_velocity = Vector3(6.0, 0, 0)
	await create_timer(2.0).timeout
	print("ソリ: 玉は目じるしから %.1f m" % Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length())
	await _shot("knock_1.jpg")
	main.emotes.big_balls.erase(b.ball_id)
	b.queue_free()
	sled.reset_to(Vector3(0, main.height(0, 38) + 0.3, 38))
	# 手袋なしの人が走って当たる（玉の -x 側から +x へ）
	await create_timer(0.5).timeout
	var at2 := Vector3(SPOT.x - 1.0, main.height(SPOT.x - 1.0, SPOT.y), SPOT.y)
	_mark(at2)
	var b2: RigidBody3D = main.emotes._spawn_big({"ball": 901, "point": at2, "r": 0.3, "who": -1})
	b2.reset_physics_interpolation()
	p.global_position = at2 + Vector3(-3.5, 0.1, 0.0)
	p.rotation.y = -PI * 0.5   # +x を向く
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p.set_third(true)
	main.craft.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": -1})   # 手袋を外す（はめていると、押すになる）
	await create_timer(1.0).timeout
	await _shot("knock_2.jpg")
	await _key(KEY_SHIFT, true)
	await _key(KEY_W, true)
	var t := 0.0
	while t < 1.4 and Vector2(b2.global_position.x - at2.x, b2.global_position.z - at2.z).length() < 0.05:
		await physics_frame
		t += 1.0 / 60.0
	await _key(KEY_W, false)
	await _key(KEY_SHIFT, false)
	await create_timer(1.5).timeout
	print("人: 玉は目じるしから %.1f m" % Vector2(b2.global_position.x - at2.x, b2.global_position.z - at2.z).length())
	await _shot("knock_3.jpg")
	quit()
