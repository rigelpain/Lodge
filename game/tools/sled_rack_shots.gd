extends SceneTree
## 外の下屋のソリ屋と、ソリの立てかけ台を撮る（確かめ用）。大・中・小を立てかけた所と、持ち出した所。
##   Godot --path game --resolution 1280x720 -s res://tools/sled_rack_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots

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
	return args.get("dir", "/tmp/sled_rack_shots")


func _lodge(x: float, y: float, h := 0.0) -> Vector3:
	return main.get_node("Lodge").to_global(Vector3(x, h, -y))


func _shot(cam: Camera3D, name: String, from: Vector3, to: Vector3, hud := false) -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = hud
	print("カメラ: ", root.get_camera_3d().get_path() if root.get_camera_3d() else "なし")
	if cam:
		cam.look_at_from_position(from, to)
		cam.reset_physics_interpolation()
	await create_timer(0.25).timeout
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _run() -> void:
	await create_timer(3.0).timeout
	var craft = main.craft
	var p = main.player
	var rack = main.sled_rack
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.cull_mask &= ~(1 << 2)
	root.add_child(cam)
	cam.current = true
	# 大・中・小を置いて、立てかける
	var ids := []
	var far := _lodge(-40.0, 2.0)
	var fabric := {"large": "red", "mid": "indigo", "small": "mustard"}
	for k in ["large", "mid", "small", "mid"]:
		var f: String = fabric[k]
		var id: int = craft._place(k, f, far, 0.0, 0, Vector3.UP, craft.tag_designs[p.id], false, p.id)
		ids.append(id)
		far += Vector3(0, 0, 6)
	await create_timer(0.3).timeout
	p.global_position = _lodge(-27.5, 3.0, 0.1)
	await create_timer(0.1).timeout
	for id in ids:
		print("戻す ", id, " ", craft.send({"kind": "rack_in", "who": p.id, "id": id}))
	await create_timer(1.8).timeout
	await _shot(cam, "01_lean_from_south", _lodge(-28.6, -15.5, 2.0), _lodge(-25.0, 0.0, 1.6))
	await _shot(cam, "02_rack_front", _lodge(-33.5, 1.5, 2.2), _lodge(-24.0, 3.5, 1.7))
	await _shot(cam, "03_rack_low", _lodge(-28.4, -1.0, 1.5), _lodge(-23.5, 6.0, 1.7))
	await _shot(cam, "04_shop_front", _lodge(-34.0, -6.5, 2.4), _lodge(-25.0, -6.0, 1.6))
	await _shot(cam, "05_from_west_far", _lodge(-52.0, -6.0, 5.0), _lodge(-24.0, 0.0, 2.2))
	await _shot(cam, "06_inside_sw", _lodge(-8.0, -3.0, 2.2), _lodge(-21.0, -7.0, 1.4))
	# 山から呼ぶ所の案内（あなたのカメラと HUD）
	print("持ち出す ", craft.send({"kind": "rack_out", "who": p.id, "id": ids[3]}))
	await create_timer(1.2).timeout
	await _shot(cam, "07_taken_out", _lodge(-33.0, 8.5, 2.6), _lodge(-26.5, 3.5, 1.0))
	# 夜の下屋
	var dc := root.get_node_or_null("DayCycle")
	if dc:
		dc.hour = 21.5
		dc.day_seconds = 1.0e9   # 撮るあいだは時刻を止める
		await create_timer(1.5).timeout
		await _shot(cam, "09_night", _lodge(-33.5, -3.0, 2.2), _lodge(-24.0, -1.0, 1.7))
		dc.hour = 12.0
		await create_timer(1.5).timeout
	cam.queue_free()
	await process_frame
	for c in p.find_children("*", "Camera3D", true, false):
		if c.get_parent().name != "":
			(c as Camera3D).make_current()
			break
	# あなたのカメラと案内: 山のソリを戻す・台のソリを持ち出す・触られていて呼べない
	var t: Vector3 = _lodge(-24.6, 7.5)
	p.global_position = _lodge(-27.5, 7.5, 0.1)
	p.global_rotation.y = atan2(-(t.x - p.global_position.x), -(t.z - p.global_position.z))
	await create_timer(1.5).timeout
	print("案内: ", main.hud._hints.get("rack_in"), " mode ", p.mode, " menu ", p.menu_open, " shopping ", p.shopping, " 台から ", rack.to_local(p.global_position), " 向き ", (-p.global_basis.z).dot(-rack.global_basis.z), " 届く ", rack.in_reach(p))
	print("F で: ", p.rack_target())
	await _shot(null, "08_hint_in", Vector3.ZERO, Vector3.ZERO, true)
	var s3: Node3D = craft.sleds[ids[3]]
	s3.holders[p] = Vector3.ZERO
	await create_timer(0.5).timeout
	print("F で（つかまれている）: ", p.rack_target(), " 呼べない: ", p.rack_refused())
	for id in ids.slice(0, 3):
		craft.racked.erase(id)
	await create_timer(1.0).timeout
	print("台を空に見せて 呼べない: ", p.rack_refused())
	await _shot(null, "10_hint_busy", Vector3.ZERO, Vector3.ZERO, true)
	for id in ids.slice(0, 3):
		craft.racked[id] = 0.0
	s3.holders.erase(p)
	var s0: Node3D = craft.sleds[ids[0]]
	p.global_rotation.y = atan2(-(s0.global_position.x - p.global_position.x), -(s0.global_position.z - p.global_position.z))
	s3.owner_id = -1
	await create_timer(1.0).timeout
	print("F で: ", p.rack_target())
	await _shot(null, "11_hint_out", Vector3.ZERO, Vector3.ZERO, true)
	quit()
