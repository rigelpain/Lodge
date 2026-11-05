extends SceneTree
## 画面の項目ごとの重さを測る。縦同期を切り、同じ場所・同じ向きで、項目を 1 つずつ消して 1 コマの時間（ms）を比べる。
##   Godot --path game --maximized -s res://tools/fps_cost.gd -- --out=/path/cost.txt [--per=5] [--spot=x,y,z]
## いちばん描く数が多い向きを探してから測る。ふつうと交互に測って、その差を出す（熱で全体が遅くなる分を打ち消す）。
## 設定は保存しない（settings.changed を直接鳴らす）。

var args := {}
var main: Node3D
var _out: FileAccess
var _t := 0.0
var _phase := 0
var _yaw_i := 0
var _best_yaw := 0.0
var _best_draws := 0
var _steps: Array = []
var _si := 0
var _acc := 0.0
var _n := 0
var _last_us := 0
var _base_prev := -1.0
var _results := []
var _pending := {}
var _per := 5.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_per = float(args.get("per", "5"))
	_out = FileAccess.open(args.get("out", "/tmp/cost.txt"), FileAccess.WRITE)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_steps = [
		["360°の小窓", func(on): _setting("pip", on)],
		["右下の自分の小窓", func(on): _setting("selfcam", on)],
		["くぼみの影・照り返し", func(on): _setting("ssao", on)],
		["光のにじみ", func(on): _setting("glow", on)],
		["影", func(on): _setting("shadows", on)],
		["舞う雪", func(on): _setting("snow", on)],
		["HUD ぜんぶ", func(on): _layers(on)],
		["3D 解像度 0.75→0.5", func(on): main.settings.values["scale"] = 0.75 if on else 0.5; _setting("scale", 0.75 if on else 0.5)],
		["人形（ボット）", func(on): _bots(on)],
	]


func _setting(k: String, v) -> void:
	main.settings.changed.emit(k, v)


func _layers(on: bool) -> void:
	for n in main.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = on


func _bots(on: bool) -> void:
	for b in main.get_children():
		if b != main.get("player") and b.get("doll") != null:
			(b as Node3D).visible = on


func _process(dt: float) -> bool:
	Engine.max_fps = 0   # main.gd の 60 の頭打ちを外して、本当の重さを測る
	if main.get("settings") and main.settings:
		main.settings.set_open(false)
	var p = main.get("player")
	_t += dt
	match _phase:
		0:
			if _t > 3.0 and p:
				var spot: Vector3 = main.sled.global_position
				if args.has("spot"):
					var v := String(args["spot"]).split(",")
					spot = Vector3(float(v[0]), float(v[1]), float(v[2]))
				p.global_position = spot + Vector3(1.5, 1.0, 0)
				_phase = 1
				_t = 0.0
		1:
			# 向きを探す: 12 方向で描く数を見る
			if _t > 0.5:
				_t = 0.0
				var d := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				if d > _best_draws:
					_best_draws = d
					_best_yaw = p.rotation.y
				_yaw_i += 1
				p.rotation.y = TAU * _yaw_i / 12.0
				if _yaw_i >= 12:
					p.rotation.y = _best_yaw
					_line("向き %.2f 描く数 %d 窓 %s" % [_best_yaw, _best_draws, str(root.size)])
					_phase = 2
					_si = 0
					_begin(false)
		2:
			var now := Time.get_ticks_usec()
			if _t > 1.5:
				if _last_us > 0:
					_acc += (now - _last_us) / 1000.0
					_n += 1
			_last_us = now
			if _t > _per:
				_finish()
	return false


## off: false ならふつう、true なら _si の項目を消す
func _begin(off: bool) -> void:
	_pending = {"off": off}
	if off:
		(_steps[_si][1] as Callable).call(false)
	_t = 0.0
	_acc = 0.0
	_n = 0
	_last_us = 0


func _finish() -> void:
	var ms := _acc / maxi(_n, 1)
	var dr := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if _pending.off:
		(_steps[_si][1] as Callable).call(true)
		_results.append([_steps[_si][0], _base_prev, ms])
		_line("%-22s ふつう %.2f ms → 消す %.2f ms（差 %.2f ms, 描く数 %d）" % [_steps[_si][0], _base_prev, ms, _base_prev - ms, dr])
		_si += 1
		if _si >= _steps.size():
			_out.flush()
			quit()
			return
		_begin(false)
	else:
		_base_prev = ms
		_begin(true)


func _line(s: String) -> void:
	print(s)
	_out.store_line(s)
	_out.flush()
