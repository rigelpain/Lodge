extends SceneTree
## ソリに轢かれて吹き飛ぶ姿を撮る（12 コマを並べた 1 枚の絵）。画面ありで動かす。
##   Godot --path game --resolution 960x540 --fixed-fps 60 -s res://tools/run_over_shots.gd -- --view=side --out=/tmp/ro.jpg --doll=kasa --sled=mid --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-lodge
##   --view=side  横から（カメラは止めて、飛ぶ先を追う）
##   --view=tp    三人称（遊ぶ人のカメラ）
##   --view=fp    一人称（遊ぶ人のカメラ）
##   --view=lying 倒れている所を近くから 1 枚（--out にそのまま）
##   --speed=9    当たる速さ (m/s)

const COLS := 5
const ROWS := 4
const STEP := 2      # 何コマ（12 fps）ごとに撮るか

var args := {}
var main: Node3D
var sled: RigidBody3D
var p: CharacterBody3D
var _n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _run() -> void:
	await create_timer(1.0).timeout
	sled = main.sled
	p = main.player
	var view: String = args.get("view", "side")
	var speed := float(args.get("speed", "9"))
	# 平らな所（丘から離れた所）。ソリは +x へ
	var at := Vector3(float(args.get("x", "70")), 0, float(args.get("z", "30")))
	at.y = main.height(at.x, at.z)
	for c in main.get_children():
		if c is CanvasLayer:
			c.visible = false   # 札や持ち物の列は写さない
	var cam := Camera3D.new()
	cam.fov = 30
	main.add_child(cam)
	if view == "side" or view == "lying":
		cam.make_current()
		cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4) | (1 << 7)   # 三人称と同じ（一人称の手は写さない）
		p.set_third(true)
	elif view == "tp":
		p.set_third(true)
		p.rotation.y = -PI * 0.5   # 飛ぶ向きを見て
	else:
		p.set_third(false)
		p.rotation.y = PI * 0.5   # ソリを見て
	p.global_position = at + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO
	sled.parked = false
	sled.global_transform = Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(at.x - 12.0, main.height(at.x - 12.0, at.z) + 0.35, at.z))
	sled.linear_velocity = Vector3.RIGHT * speed
	sled.reset_physics_interpolation()
	if view == "side" or view == "lying":
		cam.global_position = at + Vector3(0.5, 1.3, 8.0)
		cam.look_at(at + Vector3(0.5, 1.0, 0.0))
	var shots: Array[Image] = []
	var last := -99
	var t := 0.0
	var hit := false
	var down_t := -1.0
	while t < 8.0:
		await physics_frame
		t += 1.0 / 60.0
		if not hit:
			if sled.global_position.x < at.x - sled.HALF.y - 0.6:
				sled.linear_velocity = Vector3(speed, sled.linear_velocity.y, 0)
			hit = p.fling.active()
			if not hit:
				if t > 6.0:
					print("当たらなかった")
					quit(1)
					return
				continue
		_n += 1
		if view == "side" or view == "lying":
			var close := 8.0 if view == "side" else 4.5
			var look: Vector3 = p.global_position + Vector3.UP * (1.0 if view == "side" else 0.35)
			cam.global_position = look + Vector3(0.0, 0.5 if view == "side" else 1.6, close)
			cam.look_at(look)
			cam.reset_physics_interpolation()
		if view == "lying":
			if p.fling.stage == 2 and down_t < 0.0:
				down_t = t
			if down_t > 0.0 and t > down_t + 0.34:
				await process_frame
				_save(await _grab(), args.get("out", "/tmp/ro.jpg"))
				quit()
				return
			continue
		if _n % (5 * STEP) == 1:   # 物理 60 回で 12 コマ
			shots.append(await _grab())
			if shots.size() >= COLS * ROWS or not p.fling.active():
				break
	_sheet(shots)
	quit()


func _sheet(shots: Array[Image]) -> void:
	var w: int = shots[0].get_width() / 2
	var h: int = shots[0].get_height() / 2
	var rows := ceili(float(shots.size()) / COLS)
	var out := Image.create(w * COLS, h * rows, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % COLS) * w, (i / COLS) * h))
	_save(out, args.get("out", "/tmp/ro.jpg"))


func _save(im: Image, path: String) -> void:
	im.convert(Image.FORMAT_RGB8)
	if path.ends_with(".png"):
		im.save_png(path)
	else:
		im.save_jpg(path, 0.88)
	print("撮った: ", path)
