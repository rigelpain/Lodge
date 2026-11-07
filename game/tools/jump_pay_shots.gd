extends SceneTree
## ジャンプ台から飛んで、ボタンが糸に縫い込まれ、止まって財布へ入るまでを、一人称で撮って確かめる（snow_buttons.gd の ride_jump）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/jump_pay_shots.gd -- --bots=0 --no-pip --no-sound --sled=mid --dir=/path/shots
## 大きな山の 2 つ目の台の 14 m 手前から、あなたが乗って入る。飛ぶ前・宙・着地のあとを並べる（<dir>/jump_<ソリ>.png）。
## 終わりに、宙の時間、もらえる分、自分の分（ride_pay_one）を出す。

const Mountain := preload("res://mountain.gd")

var args := {}
var main: Node3D
var _shots: Array[Image] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/jump"))
	_run.call_deferred()


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(640, 360)
	_shots.append(img)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	for i in 20:
		await process_frame
	var p = main.player
	var sb = main.snow_buttons
	var sled: RigidBody3D = main.sled
	sb.auto = false
	sb.clear()
	var k := Mountain.kicker(1)
	var f: Vector2 = k.f
	var a: Vector2 = (k.lip as Vector2) - f * (Mountain.KICK_L + 14.0)
	var y: float = main.height(a.x, a.y)
	sled.reset_to(Vector3(a.x, y + 0.3, a.y))
	sled.global_transform = Transform3D(Basis.looking_at(Vector3(f.x, 0, f.y), Vector3.UP), sled.global_position)
	p.global_position = sled.global_position + Vector3(1.2, 0.3, 0)
	p.get_on()
	p.rotation.y = 0.0
	p._pitch = -0.1
	sled.parked = false
	var ahead := a + f
	sled.linear_velocity = Vector3(f.x, main.height(ahead.x, ahead.y) - y, f.y).normalized() * 14.0
	var jump := []
	var paid := []
	var money0: int = main.craft.wallets.get(p.id, 0)
	sb.happened.connect(func(ev: Dictionary) -> void:
		if ev.kind == "ride_jump":
			jump.append(ev)
		elif ev.kind == "ride_pay_one" and int(ev.who) == int(p.id):
			paid.append(ev))
	await _wait(0.7)
	_shot()
	while jump.is_empty():
		await process_frame
	for d in [0.0, 0.2, 0.4, 0.6, 1.0]:
		_shot()
		await _wait(0.2 if d < 0.6 else 0.4)
	p.get_off()   # 途中で降りても、縫い込む前の分までもらえる
	var t := 0.0
	while paid.is_empty() and t < 5.0:
		await _wait(0.5)
		t += 0.5
	await _wait(2.0)
	_shot()
	await _wait(0.5)
	var w := 640 * 3
	var sheet := Image.create(w, 360 * 2, false, _shots[0].get_format())
	for i in mini(_shots.size(), 6):
		sheet.blit_rect(_shots[i], Rect2i(0, 0, 640, 360), Vector2i(640 * (i % 3), 360 * (i / 3)))
	sheet.save_png("%s/jump_%s.png" % [args.get("dir", "/tmp/jump"), sled.kind])
	var money1: int = main.craft.wallets.get(p.id, 0)
	print("宙 %.2f 秒、もらえる分 %.1f、自分の分 %d、財布 %d → %d" % [jump[0].air, jump[0].value, int(paid[0].n) if not paid.is_empty() else -1, money0, money1])
	quit()
