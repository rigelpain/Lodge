extends SceneTree
## 旭ヶ丘で、遊ぶ人をソリに乗せて主コースを下らせ、一人称と三人称のカメラの揺れの大きさを測る（player.gd の _rattle）。
##   Godot --path game --resolution 960x540 -s res://tools/asahi_ride_shake.gd -- --world=asahigaoka --no-sound
var main: Node3D
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()
func _run() -> void:
	for i in 30:
		await physics_frame
	if main.start:
		main.start._solo()
	var p = main.player
	var sled: RigidBody3D = main.sled
	var at := Vector2(-200, -190)
	var dir := (Vector2(18, -18) - at).normalized()
	sled.reset_to(Vector3(at.x, main.height(at.x, at.y) + 0.6, at.y))
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	for i in 10:
		await physics_frame
	p.global_position = sled.global_position + Vector3(1.5, 0.5, 0)
	for i in 5:
		await physics_frame
	p.get_on()
	var ok = true
	for i in 120:
		await physics_frame
	print("乗る: ", ok, " mode ", p.mode, " RIDE ", p.Mode.RIDE)
	# 速いときの風と視野角: --dir=<フォルダ> で、一人称で 12・18・24 m/s を超えたときに撮る（ride_wind.gd・player.gd の ride_fov）
	if main.args.has("dir"):
		p.set_third(false)
		for want in [12.0, 18.0, 24.0]:
			var w := 0.0
			while sled.linear_velocity.length() < want and w < 40.0:
				await process_frame
				w += 1.0 / 60.0
			for i in 3:
				await process_frame
			var f: String = String(main.args["dir"]).path_join("wind_%d.png" % int(want))
			root.get_texture().get_image().save_png(f)
			print("撮った: %s  速さ %.1f m/s  視野角 %.0f°  風の強さ %.2f" % [f.get_file(), sled.linear_velocity.length(), p.cam.fov, main.ride_wind.level if main.get("ride_wind") else -1.0])
	for third in [false, true]:
		p.set_third(third)
		var big_rot := 0.0
		var big_y := 0.0
		var prev: Transform3D = p.cam.global_transform
		for i in 240:
			await process_frame
			var t: Transform3D = p.cam.global_transform
			big_rot = maxf(big_rot, rad_to_deg(prev.basis.get_rotation_quaternion().angle_to(t.basis.get_rotation_quaternion())))
			big_y = maxf(big_y, absf(p.get("_rattle_y")))
			prev = t
		print("%s: 1 コマでいちばん大きく向きが変わった %.1f°・目の上下のずれ いちばん %.2f m・速さ %.1f m/s" % ["三人称" if third else "一人称", big_rot, big_y, sled.linear_velocity.length()])
	quit()
