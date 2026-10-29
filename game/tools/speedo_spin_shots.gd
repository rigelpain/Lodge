extends SceneTree
## 速さの表示の糸巻き（ボビン）が、糸を送り出す向きに回っているかを、続けて撮った絵で確かめる。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/speedo_spin_shots.gd -- --bots=0 --no-pip --no-sound --dir=/path/shots [--flat-hud]
## あなたが中のソリに乗って頂上から滑り、3 m/s を超えたところから、3 コマ（1/10 秒。30° ほど回る）ごとに 8 枚、ボビンのまわりを切り抜いて（2 倍に）
## 横に並べる（<dir>/spin_<3d|flat>.png）。糸はボビンの左下から下へ出るので、左側が下へ動けば（反時計回り）糸を送り出す向き。

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/spin"))
	_run.call_deferred()


func _run() -> void:
	for i in 20:
		await process_frame
	var p = main.player
	if main.snow_buttons:
		main.snow_buttons.auto = false
	var sled: RigidBody3D = main.sled
	var at := Vector3(0, main.height(0, 3.0) + 0.6, 3.0)
	sled.reset_to(at)
	sled.global_transform = Transform3D(Basis(Vector3.UP, PI), at)
	p.global_position = at + Vector3(1.2, 0.3, 0)
	p.get_on()
	p.rotation.y = PI
	sled.linear_velocity = Vector3(0, 0, 2.0)
	while sled.linear_velocity.length() < 3.0:
		await process_frame
		if main.settings and main.settings.is_open:
			main.settings.set_open(false)
			p.menu_open = false
	var hud = main.hud
	var crops: Array[Image] = []
	for i in 8:
		for j in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var g: Dictionary = preload("res://speedo.gd").layout(hud.speedo_box_now(), hud._spd_pop)
		var c: Vector2 = g.c
		var r: float = g.r
		var rect := Rect2i(int(c.x - r * 1.8), int(c.y - r * 2.2), int(r * 3.6), int(g.y0 - c.y + r * 3.4))
		var cr := img.get_region(rect)
		cr.resize(cr.get_width() * 2, cr.get_height() * 2, Image.INTERPOLATE_LANCZOS)
		crops.append(cr)
		print("コマ %d: 速さ %.1f m/s  回した角 %.2f rad" % [i, sled.linear_velocity.length(), hud._spd_spin])
	var w := crops[0].get_width()
	var h := crops[0].get_height()
	var out := Image.create(crops.size() * (w + 4) + 4, h + 8, false, Image.FORMAT_RGB8)
	out.fill(Color(0.15, 0.15, 0.18))
	for i in crops.size():
		var im := crops[i]
		im.convert(Image.FORMAT_RGB8)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(4 + i * (w + 4), 4))
	var path := "%s/spin_%s.png" % [args.get("dir", "/tmp/spin"), "flat" if args.has("flat-hud") else "3d"]
	out.save_png(path)
	print("並べた 1 枚: ", path)
	quit()
