extends SceneTree
## おじいさんの番台（ロッジの目印 Bandai_counter_patch）のカーテンを撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/bandai_curtain_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 番台の正面（客の側）の遠く・近く・斜めから、目の高さで撮る。名前は <dir>/<見る所>_<開き具合>.png。
##   ... -- --open=0,0.5,1 --views=far,near,oblique,oblique_l,side [--top]
## --open: カーテンの開き具合を決めて止めて撮る。--top: 真上から（平行投影）も撮る。
##   Godot --path game --resolution 960x540 --fixed-fps 30 -s res://tools/bandai_curtain_shots.gd -- --bots=1 --no-sound --no-pip --dir=/path/walk --walk
## --walk: あなたが番台の前 6.5 m から話しかけられる所まで歩いて来て、F で売り台を開け閉めし、また離れる。
## 12 コマ／秒のコマごとに斜め前から（--cam=front で正面の少し横から寄って）撮り（walk_000.png …）、開き具合と話しかけられるかを書き出す。
## 終わりに仲間（bot.gd）を一人だけ番台の前に置いて、仲間でも開くかを見る。

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/bandai_curtain")


func _shot(cam: Camera3D, name: String, from: Vector3, to: Vector3) -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	cam.look_at_from_position(from, to)
	cam.reset_physics_interpolation()
	await process_frame
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _run() -> void:
	await create_timer(3.0).timeout
	var bandai := main.find_child("Bandai_counter_patch", true, false) as Node3D
	var sk: Node3D = main.shopkeeper
	var b := bandai.global_transform
	var front := -b.basis.z.normalized()   # 客の側（模型の正面は -Z）
	var right := b.basis.x.normalized()
	var c := b.origin
	print("番台 ", c, " 客の側 ", front, " おじいさん ", sk.global_position)
	var space := main.get_world_3d().direct_space_state
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.0, c + Vector3.UP * 8.0))
	print("天井まで ", (up.position.y - c.y) if up else -1.0)
	for s in [-1.0, 1.0]:
		var side := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.2, c + Vector3.UP * 1.2 + right * s * 8.0))
		print("横 %+d の壁まで " % s, c.distance_to(side.position) if side else -1.0)
	for h in [0.5, 1.2, 2.0]:
		var back := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * h, c + Vector3.UP * h - front * 6.0))
		print("後ろ（高さ %.1f）の当たりまで " % h, c.distance_to(back.position) - h if back else -1.0)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.cull_mask &= ~(1 << 2)   # 一人称の手と足（あなたのカメラだけに見せる層）は写さない
	root.add_child(cam)
	cam.current = true
	await create_timer(0.5).timeout
	var eye := Vector3.UP * 1.6
	if args.has("top"):
		var sew: Node3D = main.sewing
		if sew:   # ミシンの前の立つ所が、カーテンの囲い（番台の座標で x ±1.05、z -0.58〜1.15）の外か
			print("ミシンの立つ所（番台の座標）: ", bandai.to_local(sew.machine.to_global(sew._mark["stand"])))
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 10.0
		await _shot(cam, "top", c + Vector3.UP * 4.9 + front * 0.001, c)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var curtain := bandai.get_node_or_null("Curtain")
	if args.has("walk"):
		await _walk(cam, curtain, c, front, right)
		quit()
		return
	var views: PackedStringArray = String(args.get("views", "far,near,oblique")).split(",")
	for o in String(args.get("open", "0")).split(","):
		if curtain:
			curtain.force = float(o)
		await create_timer(0.25).timeout
		var tag := "_%s" % o if curtain else ""
		for v in views:
			match v:
				"far":
					await _shot(cam, "far" + tag, c + front * 6.0 + eye, c + Vector3.UP * 1.6)
				"near":
					await _shot(cam, "near" + tag, c + front * 2.6 + eye, c + Vector3.UP * 1.4)
				"oblique":
					await _shot(cam, "oblique" + tag, c + front * 4.0 + right * 3.0 + eye, c + Vector3.UP * 1.5)
				"oblique_l":
					await _shot(cam, "oblique_l" + tag, c + front * 4.0 - right * 3.0 + eye, c + Vector3.UP * 1.5)
				"side":
					await _shot(cam, "side" + tag, c + front * 0.5 - right * 4.5 + eye, c + Vector3.UP * 1.3)
	quit()


## あなたを、番台の前 from_d m から to_d m まで secs 秒で歩かせ、コマごとに撮る
func _walk(cam: Camera3D, curtain: Node3D, c: Vector3, front: Vector3, right: Vector3) -> void:
	var p: CharacterBody3D = main.player
	var sk: Node3D = main.shopkeeper
	var ui: CanvasLayer = main.craft_ui
	var lane := Vector3.ZERO   # あなたの歩く線（番台の真ん中から横へ）
	if args.get("cam", "") == "front":   # 正面の少し横から寄って（あなたは反対の横を歩く）
		cam.look_at_from_position(c + front * 3.3 + right * 0.9 + Vector3.UP * 1.75, c + front * 0.3 + Vector3.UP * 1.05)
		lane = -right * 0.55
	else:
		cam.look_at_from_position(c + front * 4.6 + right * 1.7 + Vector3.UP * 1.9, c + front * 0.2 + Vector3.UP * 1.15)
	cam.reset_physics_interpolation()
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var k := 0
	var plan := [[6.5, 6.5, 0.8], [6.5, 1.1, 3.4], [1.1, 1.1, 0.8], ["F", 0, 0], [1.1, 1.1, 1.5], ["close", 0, 0],
			[1.1, 1.1, 0.4], [1.1, 6.5, 3.4], [6.5, 6.5, 2.2]]
	var talk_shut := 0   # 話しかけられるのに、カーテンがまだ半分も開いていないコマ
	for step in plan:
		if step[0] is String:
			if step[0] == "F":
				print("話しかけられる: %s 開き具合 %.2f" % [p.shop_near(), curtain.open])
				ui.open_shop()
				print("売り台が開いた: %s おじいさんの shop_open %s" % [ui.get("shop_open") if ui.get("shop_open") != null else "?", sk.shop_open])
			else:
				ui.close_shop()
			continue
		var dur: float = step[2]
		var last := -1
		var el := 0.0
		while true:
			var t := minf(el / dur, 1.0)
			var d := lerpf(step[0], step[1], t)
			var at := c + front * d + lane + Vector3.UP * 0.05
			p.global_position = at
			p.velocity = Vector3.ZERO
			p.rotation.y = atan2(front.x, front.z)   # 番台の方を向く
			await process_frame
			el += 1.0 / 30.0   # --fixed-fps 30 で回す（撮るのが遅くても、ゲームの時間で歩く）
			var fi := preload("res://doll.gd").frame_index()
			if fi != last:
				last = fi
				for n in root.find_children("*", "CanvasLayer", true, false):
					(n as CanvasLayer).visible = false
				root.get_texture().get_image().save_png(_dir().path_join("walk_%03d.png" % k))
				if sk.can_talk(p) and curtain.open < 0.5:
					talk_shut += 1
				print("コマ %03d 前から %.2f m 開き %.2f 裾 %.2f 話せる %s" % [k, d, curtain.open, curtain._hem, sk.can_talk(p)])
				k += 1
			if t >= 1.0:
				break
	print("話しかけられるのにカーテンが半分も開いていないコマ: %d" % talk_shut)
	print("離れたあとの開き具合: %.2f" % curtain.open)
	# 仲間だけを番台の前に置く（あなたは遠く）
	var bot: CharacterBody3D = null
	for n in main.get_children():
		if n is CharacterBody3D and n != p and n.get_script() == preload("res://bot.gd"):
			bot = n
			break
	if bot:
		bot.set_physics_process(false)
		for i in 48:
			bot.global_position = c + front * 2.0 + Vector3.UP * 0.05
			await process_frame
		print("仲間が前に来た: 開き具合 %.2f" % curtain.open)
		for i in 60:
			bot.global_position = c + front * 20.0
			await process_frame
		print("仲間が離れた: 開き具合 %.2f" % curtain.open)
	else:
		print("仲間がいない（--bots=1 で）")
