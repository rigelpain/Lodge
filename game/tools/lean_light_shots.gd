extends SceneTree
## 外の下屋の灯りを、時刻を止めて撮る（ソリ屋の前・立てかけ台の前・西から遠く）。大・中・小を立てかけた所を見る。
##   Godot --path game --resolution 1280x720 -s res://tools/lean_light_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots --hours=12,17.8,21.5 [--no-lean-lights] [--lean-light=drum] [--tag=after]
## --fps: 夜の立てかけ台の前で 8 秒ずつ、灯りのある・ない（lean_lights を消す）の fps を数える

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 時刻（DayCycle）が場面を見つけるのに要る
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/lean_light_shots")


func _lodge(x: float, y: float, h := 0.0) -> Vector3:
	return main.get_node("Lodge").to_global(Vector3(x, h, -y))


func _shot(cam: Camera3D, name: String, from: Vector3, to: Vector3) -> void:
	cam.look_at_from_position(from, to)
	cam.reset_physics_interpolation()
	await create_timer(0.3).timeout
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _fps(sec: float) -> float:
	await create_timer(1.0).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await create_timer(sec).timeout
	return (Engine.get_frames_drawn() - f0) * 1000.0 / maxf(Time.get_ticks_msec() - t0, 1)


func _run() -> void:
	await create_timer(3.0).timeout
	var craft = main.craft
	var p = main.player
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.cull_mask &= ~(1 << 2)
	root.add_child(cam)
	cam.current = true
	var far: Vector3 = _lodge(-40.0, 2.0)
	var ids := []
	for k in ["large", "mid", "small", "mid"]:
		ids.append(craft._place(k, "red", far, 0.0, 0, Vector3.UP, craft.tag_designs[p.id], false, p.id))
		far += Vector3(0, 0, 6)
	await create_timer(0.3).timeout
	p.global_position = _lodge(-31.0, -18.0, 0.1)
	var rack = main.sled_rack
	var taken := []
	for id in ids:
		var s: Node3D = craft.sleds[id]
		var u: float = rack.fit(s.kind, taken)
		taken.append([u, rack.WIDTHS[s.kind]])
		craft.racked[id] = u
		s.rack_in(rack.lean_at(s.kind, u))
	var dc := root.get_node("DayCycle")
	dc.day_seconds = 1.0e9
	var tag: String = args.get("tag", "x")
	if args.has("fps"):
		dc.hour = 21.5
		await create_timer(1.5).timeout
		cam.look_at_from_position(_lodge(-33.0, 3.0, 2.2), _lodge(-24.0, 2.0, 1.7))
		var ll: Node = main.get_node("Lodge").get_node_or_null("LeanLights")
		var with := []
		var without := []
		for i in 3:
			ll.visible = true
			for l in ll.find_children("*", "SpotLight3D", true, false):
				(l as SpotLight3D).visible = true
			with.append(await _fps(8.0))
			ll.visible = false
			for l in ll.find_children("*", "SpotLight3D", true, false):
				(l as SpotLight3D).visible = false
			without.append(await _fps(8.0))
		print("fps 灯りあり %s なし %s" % [with, without])
		quit()
		return
	if args.has("keeper"):   # 人が近づいて番台の幕が開き、おじいさんが見える所（夜）
		dc.hour = 21.5
		var b: Node3D = main.get_node("Lodge").get_node("Bandai_counter_patch")
		p.global_position = _lodge(-27.2, -8.07, 0.1)
		await create_timer(2.0).timeout
		await _shot(cam, "%s_keeper" % tag, _lodge(-31.0, -9.5, 1.7), b.global_position + Vector3.UP * 1.2)
		quit()
		return
	for hs in String(args.get("hours", "12,17.8,21.5")).split(","):
		dc.hour = float(hs)
		await create_timer(1.5).timeout
		await _shot(cam, "%s_%s_shop" % [tag, hs], _lodge(-34.0, -6.5, 2.4), _lodge(-25.0, -6.0, 1.6))
		await _shot(cam, "%s_%s_rack" % [tag, hs], _lodge(-33.5, 3.0, 2.2), _lodge(-24.0, 3.5, 1.7))
		await _shot(cam, "%s_%s_far" % [tag, hs], _lodge(-55.0, -2.0, 4.0), _lodge(-24.0, -1.0, 2.0))
	quit()
