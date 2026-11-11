extends SceneTree
## 天下森のリフトに、遊ぶ人とそのソリを乗せて頂上まで上げる確かめ。乗る所へ人とソリを置いて F と同じ lift_try を呼び、
## 10 秒ごとに人の高さ・椅子との距離・ソリの所を出す。降りたら、降りた所と置かれたソリの所を出し、乗る所・途中・降りた所を撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/lift_ride_check.gd -- --world=tenkamori --no-snow --no-sound --dir=<フォルダ>

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	if not args.has("dir"):
		return
	if main.settings and main.settings.is_open:   # 窓が手前でなくなると設定の画面が開くので閉じる
		main.settings.set_open(false)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(String(args["dir"]).path_join(name + ".png"))


func _run() -> void:
	for i in 30:
		await physics_frame
	if main.start:
		main.start._solo()
	var p: CharacterBody3D = main.player
	var lift = main.get_node("Tenkamori/Lift")
	var b: Vector3 = lift.board_point(0)
	p.global_position = b + Vector3(0, 0.3, 0) - lift.chair_dir(lift.next_chair()) * 0.5
	var sled: RigidBody3D = main.sled
	sled.reset_to(b - lift.chair_dir(0) * 4.0 + Vector3(0, 0.6, 0))
	for i in 20:
		await physics_frame
	print("乗る所まで %.1f m・ソリまで %.1f m" % [lift.board_dist(p.global_position), sled.global_position.distance_to(p.global_position)])
	var ok: bool = p.lift_try()
	await _shot("ride_board")
	print("乗れた: %s（椅子 %d、乗る所まであと %.1f m）" % [ok, p.lift_chair, lift.to_board(p.lift_chair)])
	if not ok:
		quit()
		return
	var t := 0.0
	var next := 0.0
	var shot_mid := false
	var y0 := p.global_position.y
	var worst := 0.0
	while t < 600.0 and p.lift_chair >= 0:
		await physics_frame
		t += 1.0 / 60.0
		if not p._lift_wait:
			worst = maxf(worst, p.global_position.distance_to(lift.seat_point(p.lift_chair, p.lift_side)))
		if t >= next:
			print("%4.0f 秒: 高さ +%.0f m・座面とのずれ %.2f m・地面から %.1f m・ソリ 椅子の下 %s" % [t, p.global_position.y - y0,
					p.global_position.distance_to(lift.seat_point(p.lift_chair, p.lift_side)), p.global_position.y - main.height(p.global_position.x, p.global_position.z),
					str(sled.freeze)])
			next += 60.0
		if args.has("jump") and t > 40.0:   # 途中で F（飛び降りる）
			var h0: float = p.global_position.y - main.height(p.global_position.x, p.global_position.z)
			p.lift_jump()
			print("飛び降りた: %.0f 秒・地面から %.1f m" % [t, h0])
			for i in 300:
				await physics_frame
			print("5 秒後: 人は地面から %.2f m（%s）・ソリは地面から %.2f m・止めてある %s・人から %.1f m" % [
					p.global_position.y - main.height(p.global_position.x, p.global_position.z), "立っている" if p.is_on_floor() else "宙",
					sled.global_position.y - main.height(sled.global_position.x, sled.global_position.z), str(sled.freeze), sled.global_position.distance_to(p.global_position)])
			await _shot("jump_land")
			quit()
			return
		if not shot_mid and t > 40.0:
			shot_mid = true
			p.set_third(false)
			p._pitch = -0.25
			await _shot("ride_mid_first")
			p.set_third(true)
			await _shot("ride_mid")
			if args.has("short"):
				quit()
				return
	print("降りた: %.0f 秒・所 (%.0f, %.0f)・地面から %.2f m・ソリの所 (%.0f, %.0f) 凍ったまま %s・座面とのずれの最大 %.2f m" % [t, p.global_position.x, p.global_position.z,
			p.global_position.y - main.height(p.global_position.x, p.global_position.z), sled.global_position.x, sled.global_position.z, str(sled.freeze), worst])
	for i in 120:
		await physics_frame
	print("2 秒後: 人は地面から %.2f m（%s）・ソリは人から %.1f m" % [p.global_position.y - main.height(p.global_position.x, p.global_position.z),
			"立っている" if p.is_on_floor() else "宙", sled.global_position.distance_to(p.global_position)])
	await _shot("ride_top")
	quit()
