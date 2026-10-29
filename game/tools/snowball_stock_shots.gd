extends SceneTree
## 持っている雪玉の数の見え方を撮る（確かめ用）。帯の袋（ほかの人から・右下の小窓から）と、一人称の右手のそばの粒。
##   Godot --path game --resolution 960x540 -s res://tools/snowball_stock_shots.gd -- --dir=/path [--place=foot|inside]
## 撮るもの: 数 0〜5 を前から（front_N）と一人称（fp_N）。3 つ持って投げるところを前から（throw_秒）。
## --place=inside でロッジの中（5 つ持ち込んだところ）

const Temperature := preload("res://temperature.gd")
const THROW_WHEN := [0.05, 0.2, 0.4, 0.8]   # 離してから撮る秒

var args := {}
var main: Node3D
var cam: Camera3D
var p: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 38
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _click(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	Input.parse_input_event(e)


func _shut() -> void:
	if main.settings:
		main.settings.set_open(false)   # 窓が隠れると設定の画面が開くことがある
	p.menu_open = false


func _save(name: String) -> void:
	_shut()
	RenderingServer.force_draw()
	var dir: String = args.get("dir", "/tmp")
	var path := dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", name, "  雪玉=", p.ball_count(), " 手=", p.holding_ball, " 袋=", p.doll.pouch_balls)


func _run() -> void:
	await _frames(30)
	p = main.player
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp"))
	if main.get("hud") != null:
		main.hud.visible = false   # 画面の案内は写さない（右下の小窓は写す）
	for b in main.get_children():
		if b != p and b.get("doll") != null and b.has_method("get_off"):
			b.global_position += Vector3(30, 0, 30)   # 仲間は写さない
			b.set_physics_process(false)
	var place: String = args.get("place", "foot")
	_stage(place)
	await _frames(20)
	_shut()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var counts := [5] if place == "inside" else [0, 1, 2, 3, 4, 5]
	for n in counts:
		main.emotes.balls[p.id] = n
		_front()
		await _frames(8)
		_front()
		await process_frame
		_save("%s_front_%d" % [place, n])
		p.set_third(false)
		p.set("_pitch", -0.35)
		p.cam.current = true
		await _frames(8)
		_save("%s_fp_%d" % [place, n])
	if place == "inside":
		var t := root.get_node("Temperature")
		print("ロッジの中の気温: %.1f °C" % t.at(p.global_position + Vector3.UP))
		quit()
		return
	# 3 つ持って投げる（振りかぶって離す）
	main.emotes.balls[p.id] = 3
	_front()
	await _frames(8)
	_click(true)
	await _frames(30)
	_click(false)
	var t0 := Time.get_ticks_msec()
	for w in THROW_WHEN:
		while (Time.get_ticks_msec() - t0) / 1000.0 < w:
			await process_frame
		_front()
		_save("%s_throw_%.2f" % [place, w])
	quit()


func _stage(place: String) -> void:
	var at := Vector3(6.0, 0, 30.0)
	at.y = main.height(at.x, at.z) + 0.05
	if place == "inside":
		at = main.get_node("Lodge").to_global(Vector3(0.0, 0.05, 4.0))
	p.global_position = at
	p.rotation.y = PI * 0.85   # 丘を背にしない向き
	p.velocity = Vector3.ZERO


## 前から、少し左から、帯の高さを見る（袋と右手の雪玉が両方写る）
func _front() -> void:
	var d: Node3D = p.doll
	var fwd: Vector3 = -d.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var left := Vector3.UP.cross(fwd)   # 人形の左
	var h: float = d.height()
	var look := d.global_position + Vector3.UP * h * 0.5
	cam.look_at_from_position(look + fwd * 2.1 + left * 0.7 + Vector3.UP * 0.25, look)
	cam.current = true
