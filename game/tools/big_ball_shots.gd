extends SceneTree
## 転がす大玉（big_ball.gd・rolled.gd）の絵。ふもとの雪の上で、玉を止めて撮る。
##   Godot --path game --resolution 960x540 --fixed-fps 60 -s res://tools/big_ball_shots.gd -- --dir=/path/out --bots=1 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   push.jpg   三人称: 一人で玉を押している（両手が玉の面に）
##   small.jpg  三人称: 小さな玉をしゃがんで押している
##   caught.jpg 横から: 仲間が大きな玉に取り込まれている（玉の面に背中から半分埋まる）
##   inside.jpg あなたが取り込まれたときの、大玉の三人称の視点

const SPOT := Vector3(4.0, 0.0, 60.0)

var args := {}
var main: Node3D
var p: CharacterBody3D
var _next := 500


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


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


func _ground(x: float, z: float) -> float:
	return main.height(x, z)


func _ball(at: Vector2, r: float) -> RigidBody3D:
	_next += 1
	var b: RigidBody3D = main.emotes._spawn_big({"ball": _next, "point": Vector3(at.x, _ground(at.x, at.y), at.y), "r": r, "who": -1})
	b.freeze = true
	return b


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg(dir.path_join(name), 0.9)
	print("撮った: ", dir.path_join(name))


func _clear() -> void:
	for b in root.get_tree().get_nodes_in_group("big_balls"):
		main.emotes.big_balls.erase(b.ball_id)
		b.queue_free()
	await create_timer(0.1).timeout


func _run() -> void:
	await create_timer(1.0).timeout
	p = main.player
	main.craft.send({"kind": "gloves_own", "who": p.id, "grade": "gloves"})   # 雪玉ころがしの手袋をはめる
	main.craft.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": 0})
	p.set_third(true)
	p.cam_dist = 4.2
	# 押す: 玉の +z 側に立ち、-z（玉）を向いて W
	for c in [["push.jpg", 0.75], ["small.jpg", 0.3]]:
		await _clear()
		var r: float = c[1]
		var b := _ball(Vector2(SPOT.x, SPOT.z), r)
		p.global_position = Vector3(SPOT.x + 0.3, _ground(SPOT.x, SPOT.z + r + 0.6) + 0.1, SPOT.z + r + 0.6)
		p.rotation.y = 0.35
		p.set("_pitch", -0.25)
		p.reset_physics_interpolation()
		await create_timer(0.4).timeout
		await _key(KEY_W, true)
		await create_timer(1.2).timeout
		await _shot(c[0])
		await _key(KEY_W, false)
	# 取り込まれた仲間を横から
	await _clear()
	var bots := root.get_tree().get_nodes_in_group("bots")
	var b := _ball(Vector2(SPOT.x, SPOT.z), 1.5)
	b.rotation = Vector3(0.4, 0.3, 0.0)
	if not bots.is_empty():
		var bt: CharacterBody3D = bots[0]
		bt.global_position = b.global_position + Vector3(0, 0, 2.0)
		bt.rolled.start({"ball": b, "dir": (b.global_basis.inverse() * Vector3(0.3, 0.55, 1.0).normalized()), "up": b.global_basis.inverse() * Vector3.UP})
	p.set_third(false)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 45
	cam.global_position = b.global_position + Vector3(5.5, 1.2, 6.5)
	cam.look_at(b.global_position + Vector3(0, 0.2, 0))
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4) | (1 << 7)
	cam.make_current()
	await create_timer(0.6).timeout
	if not bots.is_empty():
		print("仲間: 体 %s 取り込まれ %s 人形 %s 玉 %s" % [bots[0].global_position, bots[0].rolled.active(), bots[0].doll.global_position, b.global_position])
	await _shot("caught.jpg")
	cam.queue_free()
	# あなたが取り込まれたときの視点
	await _clear()
	for bt in bots:   # 放り出された仲間は、絵の外へ
		bt.global_position = SPOT + Vector3(40, _ground(SPOT.x + 40, SPOT.z), 0)
		bt.reset_physics_interpolation()
	var b2 := _ball(Vector2(SPOT.x, SPOT.z), 1.3)
	p.cam.make_current()
	p.global_position = b2.global_position + Vector3(0, 0, 2.0)
	p.rotation.y = 0.6
	p.set("_pitch", -0.2)
	p.cam_dist = 3.4
	p.rolled.start({"ball": b2, "dir": b2.global_basis.inverse() * Vector3(0.2, 0.5, 1.0).normalized(), "up": b2.global_basis.inverse() * Vector3.UP})
	p._apply_third()
	await create_timer(0.8).timeout
	print("あなた %s 体 %s / 仲間たち %s" % [p.doll.kind, p.global_position, root.get_tree().get_nodes_in_group("bots").map(func(x): return [x.doll.kind, x.global_position, x.rolled.active(), x.doll.rolled])])
	print("あなたの人形 %s（玉の面 %s）、仲間 %s（取り込まれ %s）" % [p.doll.global_position, p.doll.rolled, bots[0].doll.global_position if not bots.is_empty() else Vector3.ZERO, bots[0].rolled.active() if not bots.is_empty() else false])
	await _shot("inside.jpg")
	await _glove_shots()
	quit(0)


## 雪玉ころがしの手袋（gloves.gd）の絵: 一人称の手・山師の棚・三人称の 3 段・装備の画面
##   fp.jpg  一人称で大玉を押している（手袋の手）
##   shelf.jpg  山師の棚（下の段に手袋 3 段）
##   doll_<段>.jpg  三人称で、自分の人形の手元を正面から（段ごと）
##   fp_<段>.jpg  一人称の手袋（段ごと）
##   gear.jpg  装備の画面（右上に持っている手袋）
func _glove_shots() -> void:
	p.rolled.out()
	await create_timer(3.0).timeout
	await _clear()
	p.cam.make_current()
	p.set_third(false)
	var b := _ball(Vector2(SPOT.x, SPOT.z), 0.7)
	p.global_position = Vector3(SPOT.x, _ground(SPOT.x, SPOT.z + 1.2) + 0.1, SPOT.z + 1.2)
	p.rotation.y = 0.0
	p.set("_pitch", -0.45)
	p.reset_physics_interpolation()
	await create_timer(0.5).timeout
	await _key(KEY_W, true)
	await create_timer(1.0).timeout
	await _shot("fp.jpg")
	await _key(KEY_W, false)
	await _clear()
	var c: Node = main.craft
	c.wallets[p.id] = 5000
	var mu = main.mountain_ui
	mu.open()
	mu.select(5)
	await create_timer(0.5).timeout
	await _shot("shelf.jpg")
	mu.close()
	for g in ["gloves_felt", "gloves_leather"]:
		c.send({"kind": "buy", "who": p.id, "item": {"kind": g}})
	p.set("_pitch", -0.3)
	for g in ["gloves", "gloves_felt", "gloves_leather"]:
		c.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": c.gloves_index(p.id, g)})
		await create_timer(0.4).timeout
		await _shot("fp_%s.jpg" % g)
	await create_timer(0.3).timeout
	main.craft_ui.open_gear()
	await create_timer(0.5).timeout
	await _shot("gear.jpg")
	main.craft_ui.close_gear()
	# 三人称: 自分の人形の手元を正面から、段ごとに
	p.set_third(false)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 28
	var at := Vector3(SPOT.x, 0, SPOT.z)
	at.y = _ground(at.x, at.z) + 0.05
	p.global_position = at
	p.rotation.y = PI   # カメラ（+z）を向く
	p.reset_physics_interpolation()
	cam.global_position = at + Vector3(0.5, 0.75, 2.4)
	cam.look_at(at + Vector3(0, 0.55, 0))
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4) | (1 << 7)
	cam.make_current()
	for g in ["gloves", "gloves_felt", "gloves_leather"]:
		c.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": c.gloves_index(p.id, g)})
		await create_timer(0.6).timeout
		await _shot("doll_%s.jpg" % g)
