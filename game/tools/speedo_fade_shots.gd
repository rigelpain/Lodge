extends SceneTree
## 速さの表示の糸巻きが消えていくとき、どの部品も残らないかを、続けて撮った絵で確かめる。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/speedo_fade_shots.gd -- --bots=0 --hud-idle=0 --no-pip --no-sound --dir=/path/shots [--flat-hud]
## あなたが中のソリに乗って頂上から滑り、速さの表示が出きったら、ソリを止めて動かないようにする。
## 出ている（消える前）・消えている途中（濃さ 0.6 と 0.25）・消えたすぐあと・消えて 1 秒あと の 5 枚を、画面の左の帯で切り抜いて
## 横に並べる（<dir>/fade_<3d|flat>.png）。消えたあとの 2 枚に、ボビン・リボン・糸・弧・待ち針・影が何も残っていなければよい。
## 止まると無操作で HUD が引っこむので、--hud-idle=0 で引っこめないようにして撮る。各コマで、板のボビン・リボンの見え方と透け方も出す

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/fade"))
	_run.call_deferred()


func _shot(rect: Rect2i) -> Image:
	await RenderingServer.frame_post_draw
	var pl = main.hud.plates
	if pl:
		for id in ["bobbin", "ribbon"]:
			var v: Dictionary = pl._models.get(id, pl._plates.get(id, {}))
			if not v.is_empty():
				print("  %s: 見える %s  透け %.2f" % [id, v.node.visible, float(v.get("fade", 0.0))])
	var img := root.get_texture().get_image()
	var cr := img.get_region(rect)
	cr.convert(Image.FORMAT_RGB8)
	return cr


func _run() -> void:
	for i in 20:
		await process_frame
	var p = main.player
	if main.snow_buttons:
		main.snow_buttons.auto = false
	var hud = main.hud
	var sled: RigidBody3D = main.sled
	var at := Vector3(0, main.height(0, 3.0) + 0.6, 3.0)
	sled.reset_to(at)
	sled.global_transform = Transform3D(Basis(Vector3.UP, PI), at)
	p.global_position = at + Vector3(1.2, 0.3, 0)
	p.get_on()
	p.rotation.y = PI
	sled.linear_velocity = Vector3(0, 0, 2.0)
	var box: Rect2 = hud.speedo_box()
	var rect := Rect2i(int(box.position.x - 12), int(box.position.y - 40), int(box.size.x + 40), int(box.size.y + 56))
	while hud._spd_a < 1.0 or sled.linear_velocity.length() < 5.0:
		await process_frame
		if main.settings and main.settings.is_open:
			main.settings.set_open(false)
			p.menu_open = false
	var shots: Array[Image] = []
	shots.append(await _shot(rect))
	print("消える前: 濃さ %.2f  速さ %.1f m/s  風 %.2f" % [hud._spd_a, sled.linear_velocity.length(), hud._wind])
	# 止める（乗ったまま。ソリを固めて、速さ 0 のまま）
	sled.linear_velocity = Vector3.ZERO
	sled.angular_velocity = Vector3.ZERO
	sled.freeze = true
	for want in [0.6, 0.25]:
		while hud._spd_a > want:
			await process_frame
		shots.append(await _shot(rect))
		print("消える途中: 濃さ %.2f  風 %.2f" % [hud._spd_a, hud._wind])
	while hud._spd_a > 0.0:
		await process_frame
	for i in 3:
		await process_frame
	shots.append(await _shot(rect))
	print("消えたすぐあと: 濃さ %.2f  風 %.2f" % [hud._spd_a, hud._wind])
	for i in 30:
		await process_frame
	shots.append(await _shot(rect))
	print("消えて 1 秒あと: 濃さ %.2f  風 %.2f" % [hud._spd_a, hud._wind])
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var out := Image.create(shots.size() * (w + 6) + 6, h + 12, false, Image.FORMAT_RGB8)
	out.fill(Color(0.15, 0.15, 0.18))
	for i in shots.size():
		out.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(6 + i * (w + 6), 6))
	var path := "%s/fade_%s.png" % [args.get("dir", "/tmp/fade"), "flat" if args.has("flat-hud") else "3d"]
	out.save_png(path)
	print("並べた 1 枚: ", path)
	quit()

