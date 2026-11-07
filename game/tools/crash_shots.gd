extends SceneTree
## ソリが雪の塊や木にぶつかる姿を撮る（コマを並べた 1 枚の絵）。画面ありで動かす。
##   Godot --path game --resolution 960x540 --fixed-fps 60 -s res://tools/crash_shots.gd -- --view=lump --out=/tmp/c.jpg --sled=mid --no-sound --roam-bots=0 --lodge-bots=0
##   --view=row   ロッジの正面の雪の塊の列（--out にそのまま）
##   --view=lump  雪の塊に当たる（横から、ソリの動きに合わせて）
##   --view=tree  木に当たる

const COLS := 5
const ROWS := 3

var args := {}
var main: Node3D
var sled: RigidBody3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _save(im: Image, path: String) -> void:
	im.convert(Image.FORMAT_RGB8)
	im.save_jpg(path, 0.88)
	print("撮った: ", path)


func _run() -> void:
	await create_timer(2.0).timeout
	sled = main.sled
	for c in main.get_children():
		if c is CanvasLayer:
			c.visible = false   # 札や持ち物の列は写さない
	cam = Camera3D.new()
	cam.fov = 50.0
	main.add_child(cam)
	var view: String = args.get("view", "lump")
	if view == "row":
		var a: Vector2 = main.lodge_to_world(Vector2(-13.0, 52.0))
		var b: Vector2 = main.lodge_to_world(Vector2(-13.0, 25.0))
		cam.global_position = Vector3(a.x, main.height(a.x, a.y) + 5.0, a.y)
		cam.look_at(Vector3(b.x, main.height(b.x, b.y) + 1.0, b.y))
		cam.make_current()
		await create_timer(0.3).timeout
		_save(await _grab(), args.get("out", "/tmp/c.jpg"))
		quit()
		return
	var target: Vector3
	if view == "tree":
		for b in get_nodes_in_group("tree_hits"):
			for own in b.get_shape_owners():
				var q: Vector3 = b.global_transform * b.shape_owner_get_transform(own).origin
				if Vector2(q.x, q.z).length() > 34.0 and Vector2(q.x, q.z).length() < 46.0 and target == Vector3.ZERO:
					target = q
	else:
		var list: Array = get_nodes_in_group("crash_lumps")
		target = list[8].global_position
	var hit_dir := Vector2(target.x, target.z).normalized()
	var from := Vector2(target.x, target.z) - hit_dir * 9.0
	var dir := hit_dir
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	await create_timer(0.6).timeout
	var pl: CharacterBody3D = main.player
	pl.global_position = sled.global_position + Vector3.UP
	pl.get_on()
	sled.linear_velocity = Vector3(dir.x, 0, dir.y) * float(args.get("speed", "11"))
	var side := Vector3(-dir.y, 0, dir.x)
	var look0 := target + Vector3.UP * 3.0 + Vector3(dir.x, 0, dir.y) * 3.0
	cam.global_position = look0 + side * 19.0 + Vector3.UP * 3.0
	cam.look_at(look0)
	cam.make_current()
	var t := 0.0
	while not sled.crashed and t < 6.0:
		await physics_frame
		t += 1.0 / 60.0
	var shots: Array[Image] = []
	var n := 0
	while shots.size() < COLS * ROWS:
		await physics_frame
		n += 1
		if n % 18 == 1:
			cam.make_current()
			shots.append(await _grab())
	var w: int = shots[0].get_width() / 2
	var h: int = shots[0].get_height() / 2
	var out := Image.create(w * COLS, h * ROWS, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % COLS) * w, (i / COLS) * h))
	_save(out, args.get("out", "/tmp/c.jpg"))
	quit()
