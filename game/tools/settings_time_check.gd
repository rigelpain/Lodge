extends SceneTree
## 設定の画面の「時刻」と「時刻を止める」の確かめ（settings.gd の _build_time、daycycle.gd の set_hour・paused）。
##   Godot --path game --resolution 1280x720 -s res://tools/settings_time_check.gd -- --no-sound --bots=0 [--dir=/path/shots]
## 設定の画面を開き、時刻のスライダーを 19:00 → 1:00 → 12:00 と動かして、一日の巡りの時刻が変わるか、
## 止めると進まないか、外すとまた進むかを数で出す。--dir があれば、そのたびに画面を撮る。
var main: Node3D
var args := {}
var bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 一日の巡り（daycycle.gd）は、いまの場面の中から太陽を探す
	_run.call_deferred()


func _check(what: String, ok: bool) -> void:
	print("%s: %s" % ["よし" if ok else "だめ", what])
	if not ok:
		bad += 1


func _shot(name: String) -> void:
	if not args.has("dir"):
		return
	DirAccess.make_dir_recursive_absolute(args["dir"])
	root.get_texture().get_image().save_png(String(args["dir"]).path_join(name + ".png"))


func _wait(secs: float) -> void:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _run() -> void:
	for i in 30:
		await physics_frame
	if main.start:
		main.start._solo()
	await _wait(1.0)
	var dc := root.get_node("DayCycle")
	var st = main.settings
	var saved := FileAccess.get_file_as_bytes(st.PATH)   # 保存してある設定は、確かめのあとで元に戻す
	st.set_open(true)
	await _wait(0.4)
	var sl: HSlider = st._time_sl
	var cb: CheckButton = st._time_cb
	st._scroll.ensure_control_visible(cb)
	await _wait(0.3)
	_check("開いたとき、スライダーがいまの時刻（%s）を指している" % dc.clock(), absf(sl.value - dc.hour) <= 0.25)
	_check("時刻が流れている（%.3f。始まりは 10 時）" % dc.hour, dc.hour > 10.01)
	_shot("0_open")
	for h in [19.0, 1.0, 12.0]:
		sl.value = h
		await _wait(0.8)
		_check("スライダーを %s にすると、時刻が %s になる（数字 %s）" % [h, dc.clock(), st._time_num.text], absf(dc.hour - h) < 0.1)
		_shot("1_hour_%02d" % int(h))
	cb.button_pressed = true
	var h0: float = dc.hour
	await _wait(1.5)
	_check("止めると、1.5 秒たっても時刻が進まない（%.3f → %.3f）" % [h0, dc.hour], is_equal_approx(h0, dc.hour))
	sl.value = 17.5
	await _wait(0.8)
	_check("止めたままでも、スライダーで 17:30 にできる（%s）" % dc.clock(), is_equal_approx(dc.hour, 17.5))
	_shot("2_stopped_1730")
	cb.button_pressed = false
	await _wait(1.5)
	_check("外すと、また進む（17.500 → %.3f）" % dc.hour, dc.hour > 17.51)
	_check("保存する設定には入れていない", not st.values.has("time"))
	st.set_open(false)
	if saved.size() > 0:
		var f := FileAccess.open(st.PATH, FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	print("だめ %d 個" % bad)
	quit(1 if bad > 0 else 0)
