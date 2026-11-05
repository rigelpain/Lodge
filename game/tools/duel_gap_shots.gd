extends SceneTree
## 雪合戦の対決の、投げの間の糸の輪（duel_hud.gd の _draw_gap）を撮る。窓を出す:
##   Godot --fixed-fps 60 --path game --resolution 1280x720 -s res://tools/duel_gap_shots.gd -- --no-sound --bots=1 --lodge-bots=0 --no-pip --hud-idle=0 --dir=/path/shots
## 01 投げた直後 / 02 間のなかば / 03 もうすぐ明ける / 04 明けた瞬間 / 05 消えたあと（右手に雪玉）/
## 06 雪玉がないままの間 / 07 相手の雪玉を取れるときの間（キャッチの照準と重ならないか）

const AT := Vector3(14, 0, 16)

var args := {}
var main: Node3D
var p: Node3D
var foe: Node3D
var hub: Node
var duel: Node
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.get("dir", "/tmp/duel_gap")).path_join(name + ".png"))
	print("撮った %s: 残り %d コマ、投げられる %s" % [name, duel.throw_wait(p.id), duel.can_throw(p.id)])


func _ok(cond: bool, what: String) -> void:
	print(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _place(n: Node3D, at: Vector3, look: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.15
	n.global_position = at
	n.velocity = Vector3.ZERO
	n.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))


func _throw() -> void:
	var to: Vector3 = (foe.global_position - p.global_position).normalized()
	hub.send({"kind": "throw", "who": p.id, "origin": p.global_position + Vector3.UP * 1.4 + to * 0.5, "velocity": to * 3.0 + Vector3.UP * 5.0})


func _until_wait(frames: int) -> void:
	while duel.throw_wait(p.id) > frames:
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(String(args.get("dir", "/tmp/duel_gap")))
	await _wait(1.0)
	p = main.player
	hub = main.emotes
	duel = main.duel
	foe = main.get_children().filter(func(c): return c.get_script() == main.Bot and not c.lounge)[0]
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	p.set_third(false)
	_place(p, AT, AT + Vector3(0, 0, 1))
	_place(foe, AT + Vector3(0, 0, 0.8), AT)
	hub._set_balls(p.id, 3)
	hub._set_balls(foe.id, 3)
	_ok(duel.throw_wait(p.id) == 0, "戦いの前は間がない")
	_throw()
	_ok(duel.throw_wait(p.id) == 0, "ふだんの雪合戦で投げても間がない")
	await _wait(0.2)
	duel._shook(p.id, foe.id)
	duel._apply({"kind": "ok", "who": p.id})
	duel._apply({"kind": "ok", "who": foe.id})
	await _wait(0.5)
	_place(foe, AT + Vector3(0, 0, 5.0), AT)
	p.rotation.y = PI
	p.set("_pitch", -0.05)
	await _wait(0.3)
	_ok(not duel.fighting(p.id).is_empty(), "戦いが始まった")
	_throw()
	await _wait(0.1)
	_ok(duel.throw_wait(p.id) > 0 and not duel.can_throw(p.id), "投げると間に入る")
	await _shot("01_just_thrown")
	await _until_wait(duel.GAP_FRAMES / 2)
	await _shot("02_half")
	await _until_wait(4)
	await _shot("03_soon")
	await _until_wait(0)
	await _shot("04_clear")
	_ok(duel.can_throw(p.id), "残り 0 で投げられる")
	await _wait(0.8)
	await _shot("05_after")
	# 最後の雪玉を投げた
	hub._set_balls(p.id, 1)
	_throw()
	await _wait(0.8)
	_ok(hub.balls_of(p.id) == 0, "雪玉がなくなった")
	await _shot("06_no_ball")
	await _until_wait(0)
	await _wait(0.1)
	await _shot("06b_no_ball_clear")
	# キャッチの照準と一緒に
	hub._set_balls(p.id, 3)
	_throw()
	await _wait(0.3)
	var cam: Camera3D = p.cam
	hub._spawn_ball({"who": foe.id, "origin": cam.global_position - cam.global_basis.z * 0.5, "velocity": Vector3.ZERO, "ball": 9999})
	hub.ball(9999).freeze = true
	await _wait(0.2)
	await _shot("07_with_catch")
	quit(fails)
