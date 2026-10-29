extends SceneTree
## 雪のボタンの取得音の確かめ（音の記録と絵）。あなたが中のソリに乗って頂上から滑り、斜面のボタンを取り、止まるまで。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/button_sound_check.gd -- --bots=0 --no-pip --dir=/path/shots
## 道の上（x = 0）に、木・真鍮・木・白蝶貝・木のボタンを置く（中は胴の下でも切れる）。
## 鳴った音（ボタンの音・はさみの音）を、時刻（滑り出してからの秒）・名前・耳元か・聞く所からの距離・滑走の風の大きさで書き出す。
## 財布に入った出来事（craft の earn）の時刻も並べる。絵は、滑っている途中・止まる前・巻き取り・財布に入ったあとを
## <dir>/sound_<番号>.png と、並べた <dir>/sound_sheet.png。

var args := {}
var main: Node3D
var _imgs: Array[Image] = []
var _t0 := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/button_sound")


func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second) - _t0


func _grab() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/sound_%02d.png" % [_dir(), _imgs.size()])
	_imgs.append(img)


func _run() -> void:
	for i in 20:
		await process_frame
	var p = main.player
	var sb = main.snow_buttons
	var audio = main.get_node_or_null("Audio")
	if p == null or sb == null or audio == null:
		print("あなた・ボタン・音のどれかがない（--no-player・--no-buttons・--no-sound を付けない）")
		quit()
		return
	sb.auto = false
	sb.clear()
	var sled: RigidBody3D = main.sled
	var at := Vector3(0, main.height(0, 3.0) + 0.6, 3.0)
	sled.reset_to(at)
	sled.global_transform = Transform3D(Basis(Vector3.UP, PI), at)
	p.global_position = at + Vector3(1.2, 0.3, 0)
	p.get_on()
	p.rotation.y = PI
	p._pitch = -0.1
	var tiers := [0, 1, 0, 2, 0]
	for i in tiers.size():
		sb.drop_at(Vector3(0, 0, 12.0 + i * 6.0), 0, true, tiers[i])
	var earns: Array = []
	main.craft.happened.connect(func(ev: Dictionary) -> void:
		if ev.kind == "earn":
			earns.append("%.2f 秒  財布に入る（earn）%d（%s）" % [_now(), ev.n, ", ".join(preload("res://craft.gd").pieces(int(ev.n)))]))
	var paid := [-1.0]
	sb.happened.connect(func(ev: Dictionary) -> void:
		if ev.kind == "ride_pay":
			paid[0] = _now())
	audio.log_on = true
	_t0 = Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
	sled.linear_velocity = Vector3(0, 0, 2.0)
	var shots := {}
	while true:
		await process_frame
		if main.settings and main.settings.is_open:
			main.settings.set_open(false)
			p.menu_open = false
		var z := sled.global_position.z
		if z > 26.0 and not shots.has("mid"):
			shots["mid"] = true
			await _grab()
		if z > 40.0 and not shots.has("late"):
			shots["late"] = true
			await _grab()
		if paid[0] >= 0.0:
			var since: float = _now() - paid[0]
			for k in [0.3, 0.9, 1.6, 2.6]:
				if since > k and not shots.has(k):
					shots[k] = true
					await _grab()
			if since > 4.5:
				break
		if _now() > 60.0:
			print("時間切れ")
			break
	audio.log_on = false
	print("---- 鳴った音（ボタン・はさみ）")
	for e in audio.played:
		var n: String = e.name
		if n.begins_with("button_") or n.begins_with("shears"):
			print("%.2f 秒  %-20s %s  距離 %.1f m  滑走の風 %.0f dB" % [e.t - _t0, n, "耳元" if e.near else "その場", e.dist, e.wind])
	print("---- 財布")
	for e in earns:
		print(e)
	print("滑り終わり（ride_pay）: %.2f 秒" % paid[0])
	_sheet()
	quit()


func _sheet() -> void:
	if _imgs.is_empty():
		return
	var w := 640
	var h := 360
	var cols := 3
	var rows := ceili(_imgs.size() / float(cols))
	var out := Image.create(cols * w + (cols + 1) * 4, rows * h + (rows + 1) * 4, false, Image.FORMAT_RGB8)
	out.fill(Color(0.15, 0.15, 0.18))
	for i in _imgs.size():
		var im := _imgs[i].duplicate() as Image
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(4 + (i % cols) * (w + 4), 4 + (i / cols) * (h + 4)))
	out.save_png("%s/sound_sheet.png" % _dir())
	print("並べた 1 枚: %s/sound_sheet.png" % _dir())
