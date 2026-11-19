extends SceneTree
## 重いときに 3D を自動で粗くする仕組み（main.gd の _auto_scale）の確かめ。遊ぶときと同じ 60 の頭打ち・縦同期なしで、
## 同じ場所・同じ向きに立ったまま、自動を 切る → 入れる → 切る と替えて、2 秒ごとの fps と 3D の大きさを出す（画面ありで起動する）。
##   Godot --path game --maximized -s res://tools/auto_scale_check.gd -- --auto-scale [--per=30] [--spot=x,y,z] [--yaw=向き]
## 最後に「よし／だめ」: 入れているあいだに fps が上がり、3D の大きさが下がり、切ると元の大きさに戻ること

var args := {}
var main: Node3D
var _t := 0.0
var _seg := -1
var _segs := [false, true, false]
var _seg_t := 0.0
var _log_t := 0.0
var _frames := 0
var _sum := 0.0
var _seg_frames := 0
var _seg_sum := 0.0
var _seg_fps: Array = []
var _scales: Array = []
var _spot := Vector3.ZERO
var _yaw := 0.0
var _ng := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(dt: float) -> bool:
	Engine.max_fps = main.GAME_FPS
	if main.get("settings") and main.settings:
		main.settings.set_open(false)
	_t += dt
	var p = main.get("player")
	if p == null:
		return false
	if _t < 4.0:
		return false
	if _seg < 0:
		_spot = main.sled.global_position + Vector3(1.5, 1.0, 0.0)
		if args.has("spot"):
			var v := String(args["spot"]).split(",")
			_spot = Vector3(float(v[0]), float(v[1]), float(v[2]))
		_yaw = float(args.get("yaw", str(PI)))
		_next()
	p.global_position = _spot
	p.rotation.y = _yaw
	p.velocity = Vector3.ZERO
	_seg_t += dt
	_log_t += dt
	if _seg_t > 6.0:   # 切り替えのすぐあとは除く（上げ下げが落ち着くまで）
		_frames += 1
		_sum += dt
		_seg_frames += 1
		_seg_sum += dt
	if _log_t >= 2.0:
		_log_t = 0.0
		var vp := root.get_viewport()
		print("%s  t=%4.0f  %5.1f fps  3D %.2f（自動 %.2f）" % ["入" if _segs[_seg] else "切", _seg_t, _frames / maxf(_sum, 0.001), vp.scaling_3d_scale, main.dyn_scale])
		_frames = 0
		_sum = 0.0
	if _seg_t > float(args.get("per", "30")):
		_seg_fps.append(_seg_frames / maxf(_seg_sum, 0.001))
		_scales.append(root.get_viewport().scaling_3d_scale)
		_next()
	return false


func _next() -> void:
	_seg += 1
	if _seg >= _segs.size():
		_finish()
		return
	main.auto_scale = _segs[_seg]
	_seg_t = 0.0
	_seg_frames = 0
	_seg_sum = 0.0
	print("--- 自動を%s" % ("入れる" if _segs[_seg] else "切る"))


func _check(ok: bool, what: String) -> void:
	print(("よし: " if ok else "だめ: ") + what)
	if not ok:
		_ng += 1


func _finish() -> void:
	print("切: %.1f fps 3D %.2f / 入: %.1f fps 3D %.2f / 切: %.1f fps 3D %.2f" % [_seg_fps[0], _scales[0], _seg_fps[1], _scales[1], _seg_fps[2], _scales[2]])
	if _seg_fps[0] < 55.0:   # 重くないときは下げないのが正しい（下げる理由がない）
		_check(_seg_fps[1] > _seg_fps[0] * 1.15, "入れると fps が上がる（%.1f → %.1f）" % [_seg_fps[0], _seg_fps[1]])
		_check(_scales[1] < _scales[0], "入れると 3D が粗くなる（%.2f → %.2f）" % [_scales[0], _scales[1]])
	else:
		_check(_scales[1] >= _scales[0] * 0.9, "重くないときは、ほとんど下げない（%.2f → %.2f）" % [_scales[0], _scales[1]])
	_check(is_equal_approx(_scales[2], _scales[0]), "切ると元の大きさに戻る（%.2f）" % _scales[2])
	print("だめ %d 個" % _ng)
	quit()
