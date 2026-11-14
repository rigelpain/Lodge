extends SceneTree
## 旭ヶ丘の主コースを一人称で下り、速いときの画面の端のぼかし（ride_blur.gd）・風の上の段（ride_wind.gd の rush）・
## 宙の浮きと着地の沈み（player.gd の _ride_air、sled.gd の air_t・land_n）を撮って、数を出す。
##   Godot --path game --resolution 1280x720 -s res://tools/ride_feel_shots.gd -- --world=asahigaoka --no-sound --dir=/path/shots [--novsync] [--secs=22]
## 撮る物: 18 m/s・24 m/s を超えたとき（blur_18・blur_24）、0.4 秒より長く浮いたとき（air）、そのあと着いて沈みきったとき（land）。
## HUD と右上の映像は出したまま撮る（ぼけないことを見る）。
## 重さ: 15 m/s より速いあいだ、ぼかしを 1 秒ごとに入れる・切るを繰り返し、それぞれの 1 コマの時間の平均を出す（同じ起動の中で比べる。--novsync で）。
var main: Node3D
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)   # 窓が隠れると描画が止まる
	if args.has("novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _save(name: String, info: String) -> void:
	var dir: String = args.get("dir", "/tmp/ride_feel")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("撮った: %s  %s" % [name, info])


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
	p.set_third(args.has("third"))
	p.ride_shake_enabled = true
	p.ride_float_amount = 1.0
	var blur = main.ride_blur
	var wind = main.ride_wind
	if blur:
		blur.strength = 1.0
	if wind:
		wind.strength = 1.0
		wind.calm = false
	print("乗る: mode ", p.mode, " RIDE ", p.Mode.RIDE)
	var taken := {}
	var t := 0.0
	var top := 0.0
	var lands: int = sled.land_n
	var land_wait := -1
	var eye_lo := 0.0
	var eye_hi := 0.0
	var air_sum := 0.0
	var cost := {true: [0.0, 0], false: [0.0, 0]}   # ぼかしを入れた・切ったコマの、時間の合計と数
	var phase_t := 0.0
	var phase_on := true
	var secs := float(args.get("secs", "22"))
	var last := Time.get_ticks_usec()
	while t < secs and not sled.crashed and p.mode == p.Mode.RIDE:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000000.0
		last = now
		t += dt
		var v := sled.linear_velocity.length()
		top = maxf(top, v)
		if v > 1.0 and not args.has("back"):   # 進む向きを見る（--back で後ろを見たまま）
			var go := sled.linear_velocity / v
			p.rotation.y = atan2(-go.x, -go.z)
			p._pitch = float(args.get("pitch", "-0.25"))
		var eye: float = p.get("_air_shown")
		eye_lo = minf(eye_lo, eye)
		eye_hi = maxf(eye_hi, eye)
		if sled.air_t > 0.0:
			air_sum += dt
		var info := "速さ %.1f m/s  視野角 %.0f°  風 %.2f＋上の段 %.2f  ぼかし %.2f  宙 %.2f 秒  目の浮き沈み %+.3f m" % [
				v, p.cam.fov, wind.level if wind else -1.0, wind.rush if wind else -1.0, blur.level if blur else -1.0, sled.air_t, eye]
		for want in [18, 24]:
			if v >= want and not taken.has(want) and (blur == null or blur.level > 0.9 * wind.rush_of(float(want))):
				taken[want] = true
				_save("blur_%d" % want, info)
		if not taken.has("air") and sled.air_t > 0.4 and v > 12.0:
			taken["air"] = true
			_save("air", info)
		if sled.land_n != lands:
			lands = sled.land_n
			print("  着地: 雪面へ %.1f m/s  速さ %.1f m/s" % [sled.land_v, v])
			if taken.has("air") and not taken.has("land"):
				land_wait = 4   # 沈みきるころ
		if land_wait >= 0:
			land_wait -= 1
			if land_wait < 0:
				taken["land"] = true
				_save("land", info)
		# 重さ: 速いあいだ、ぼかしを 1 秒ごとに入れる・切る（撮るのがすんでから）
		if blur and args.has("cost") and v > 15.0 and taken.has(18):
			phase_t += dt
			if phase_t > 1.0:
				phase_t = 0.0
				phase_on = not phase_on
			blur.strength = 1.0 if phase_on else 0.0
			blur.level = wind.rush_of(v) * blur.strength
			if phase_t > 0.2:
				cost[phase_on][0] += dt
				cost[phase_on][1] += 1
	print("いちばん速いとき %.1f m/s・%.1f 秒のうち宙に %.1f 秒・着地 %d 回・目の浮き沈み %+.3f 〜 %+.3f m" % [top, t, air_sum, sled.land_n, eye_lo, eye_hi])
	if cost[true][1] > 0 and cost[false][1] > 0:
		print("1 コマの時間: ぼかしあり %.2f ms（%d コマ）・なし %.2f ms（%d コマ）" % [
				1000.0 * cost[true][0] / cost[true][1], cost[true][1], 1000.0 * cost[false][0] / cost[false][1], cost[false][1]])
	quit()
