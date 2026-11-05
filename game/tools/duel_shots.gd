extends SceneTree
## 雪合戦の対決（duel.gd・duel_hud.gd）の流れを撮る。対決の仲間（--duel-bot）が相手。
##   Godot --path game --resolution 1280x720 -s res://tools/duel_shots.gd -- --duel-bot --bots=1 --lodge-bots=0 --no-pip --no-sound --dir=/path/shots
## 01 掛金の画面 / 02 始まり（待ち針が刺さる）/ 03 戦い（一人称、1 発ずつ当てた）/ 04 キャッチの照準（F）/
## 05 勝ち（ロゼットと握手の手袋）/ 06 フィールドを上から

const Snowball := preload("res://snowball.gd")

var args := {}
var main: Node3D
var p: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/duel")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	print("撮った: ", name)


func _place(n: Node3D, at: Vector3, look: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.15
	n.global_position = at
	n.velocity = Vector3.ZERO
	n.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))


func _throw(a: Node3D, b: Node3D) -> void:
	var origin := a.global_position + Vector3.UP * 1.4 + (b.global_position - a.global_position).normalized() * 0.5
	var target := b.global_position + Vector3.UP * 1.0
	var flat := target - origin
	flat.y = 0
	var t := flat.length() / 12.0
	var vel := flat.normalized() * 12.0 + Vector3.UP * ((target.y - origin.y + 4.9 * t * t) / t)
	main.emotes.send({"kind": "throw", "who": a.id, "origin": origin, "velocity": vel})


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	await _wait(2.0)
	p = main.player
	var hub = main.emotes
	var duel = main.duel
	var foe = main.get_children().filter(func(c): return c.get_script() == main.Bot and c.duelist)[0]
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	foe.doll.process_mode = Node.PROCESS_MODE_ALWAYS   # 止めた仲間でも、人形の体の形（当たり）は今の所に
	var at := Vector3(14, 0, 16)
	_place(p, at, at + Vector3(0, 0, 1))
	_place(foe, at + Vector3(0, 0, 0.8), at)
	p.set_third(false)
	p.set("_pitch", -0.15)
	await _wait(0.3)
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	hub.send({"kind": "hands", "who": p.id, "hands": "low_R"})
	hub.send({"kind": "hands", "who": foe.id, "hands": "low_R"})
	await _wait(1.2)
	main.duel_hud.nudge(10, 1)
	main.duel_hud.nudge(10, 1)
	main.duel_hud.nudge(1, 1)
	main.duel_hud.nudge(1, 1)
	main.duel_hud.nudge(1, 1)
	await _wait(0.4)
	await _shot("01_bet")
	while duel.of(p.id).get("phase", "") != "fight":
		await _wait(0.2)
	foe._duel_t = 99.0
	p.set("_pitch", -0.35)
	await _wait(0.5)
	await _shot("02_start")
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	_place(foe, at + Vector3(0, 0, 3.0), at)
	_place(p, at + Vector3(0, 0, -1.5), at + Vector3(0, 0, 3.0))
	p.set("_pitch", -0.05)
	_throw(p, foe)
	await _wait(1.0)
	_throw(foe, p)
	await _wait(1.2)
	_throw(foe, p)   # 飛んでいる途中を撮る（地図に白い点）
	await _wait(0.12)
	await _shot("03_fight_fp")
	await _wait(1.5)
	# 照準に合った、手の届く相手の雪玉（止めて撮る）
	var cam: Camera3D = p.cam
	hub._spawn_ball({"who": foe.id, "origin": cam.global_position - cam.global_basis.z * 0.5, "velocity": Vector3.ZERO, "ball": 9999})
	var b: Snowball = hub.ball(9999)
	b.freeze = true
	await _wait(0.2)
	print("キャッチの確かめ: 雪玉 %s done %s 肩から %.2f 画面のずれ %.0f px / %.0f 届く %s" % [is_instance_valid(b), b._done if is_instance_valid(b) else "-",
		b.global_position.distance_to(duel._chest(p)) if is_instance_valid(b) else -1.0,
		cam.unproject_position(b.global_position).distance_to(cam.get_viewport().get_visible_rect().size / 2.0) if is_instance_valid(b) else -1.0,
		duel.CATCH_AIM * cam.get_viewport().get_visible_rect().size.y, duel.catchable(p, cam, foe.id) != null])
	await _shot("04_catch_aim")
	duel.send({"kind": "catch", "who": p.id, "ball": 9999})
	await _wait(0.25)
	await _shot("04b_caught")
	await _wait(1.0)
	for i in 2:
		_throw(p, foe)
		await _wait(1.3)
	await _wait(0.6)
	await _shot("05_win")
	# フィールドを上から
	var top := Camera3D.new()
	main.add_child(top)
	var d: Dictionary = duel.of(p.id)
	top.global_position = d.at + Vector3(0, 9.5, 7.5)
	top.look_at(d.at, Vector3.UP)
	top.fov = 55
	top.current = true
	foe.process_mode = Node.PROCESS_MODE_INHERIT
	await _wait(1.5)
	await _shot("06_field_top")
	quit()
