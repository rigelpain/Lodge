extends SceneTree
## 仲間が大勢そばにいるときの重さを、項目ごとに分けて測る。縦同期と 60 の頭打ちを外し、ふつうと「その項目を消した」を交互に測って、
## 1 コマの時間（ms）の中央値の差を出す（仲間が動くぶんと熱のぶんを、交互にして打ち消す）。
##   Godot --path game --resolution 1280x720 -s res://tools/crowd_cost.gd -- --roam-bots=30 --roam-all-hill --no-sound --time=21 [--per=3] [--rounds=3] [--warm=15] [--freeze] [--at=x,z,向き] [--steps=N]
## --freeze: 測る前に仲間を止める（描く重さだけを比べる）。--still: 仲間の考えと歩みだけ止める（人形は動く）。--trace: 段ごとの様子。--only=番号,…: 項目を選ぶ。
## Mac が熱いと全体が何倍も遅くなるので、冷えてから続けて回さずに測る
## 仲間のソリ・頭の小物の項目は、止めているあいだにソリが流れたりペットが置いていかれたりして、戻したあとの動きが乱れる。
## その後ろの項目は時間とともに重くなることがあるので、--only で 1 つずつ測る

var args := {}
var main: Node3D
var t := 0.0
var _phase := "wait"
var _steps: Array = []
var _si := 0
var _round := 0
var _off := false
var _samples := []
var _last_us := 0
var _res := {}   # 項目 → [ふつうの ms の配列, 消した ms の配列]
var _gpu := {}   # 項目 → [ふつうの GPU ms の配列, 消した GPU ms の配列]
var _phase_us := 0
## GPU の使用率（ioreg）を別の糸で 0.3 秒ごとに読む。窓のある Mac は画面の書き換え（120 Hz）に合わせてコマが頭打ちになり、
## 1 コマの時間では差が出ないので、「1 コマの時間 × 使用率」を GPU が働いた時間とみる
var _util_thread: Thread
var _util_lock := Mutex.new()
var _util: Array = []   # [ticks_usec, 使用率%]
var _util_stop := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	AudioServer.set_bus_mute(0, true)
	if args.has("steps"):   # 1 コマに進める物理の歩みの上限（遊ぶときは main.gd の GAME_STEPS）
		Engine.max_physics_steps_per_frame = int(args["steps"])
	_util_thread = Thread.new()
	_util_thread.start(_util_loop)
	_steps = [
		["ランタンの灯り", func(on): _lights(on)],
		["人形の影", func(on): _doll_shadows(on)],
		["360°の小窓", func(on): _setting("pip", on)],
		["右下の自分の小窓", func(on): _setting("selfcam", on)],
		["影ぜんぶ", func(on): _setting("shadows", on)],
		["息の煙", func(on): _kind(on, "CPUParticles3D")],
		["ランタンの形", func(on): _lantern_body(on)],
		["人形の形を粗く（lod_bias 0.3）", func(on): _lod(on)],
		["60 m より遠い人形", func(on): _bots(on, 60.0)],
		["人形ぜんぶ", func(on): _bots(on)],
		["仲間の考えと歩み（bot.gd）", func(on): _brains(on)],
		["人形の姿勢づくり（doll.gd）", func(on): _poses(on)],
		["仲間のソリ（sled.gd）", func(on): _script_nodes(on, "res://sled.gd", true)],
		["頭の小物・ペット（companions.gd）", func(on): _script_nodes(on, "res://companions.gd", false)],
		["遠くの人の間引き（doll.gd の thin_far。消した側が前の作り）", func(on): preload("res://doll.gd").thin_far = on],
	]
	if args.has("only"):   # --only=0,9,10 のように、測る項目の番号を選ぶ
		var keep := []
		for i in String(args["only"]).split(","):
			keep.append(_steps[int(i)])
		_steps = keep


func _util_loop() -> void:
	var re := RegEx.create_from_string("Device Utilization %\"=(\\d+)")
	while not _util_stop:
		var o := []
		OS.execute("ioreg", ["-r", "-d", "1", "-c", "IOAccelerator"], o)
		var m := re.search(String(o[0]) if o.size() > 0 else "")
		if m:
			_util_lock.lock()
			_util.append([Time.get_ticks_usec(), float(m.get_string(1))])
			_util_lock.unlock()
		OS.delay_msec(300)


func _util_since(us: int) -> float:
	_util_lock.lock()
	var sum := 0.0
	var n := 0
	for u in _util:
		if u[0] >= us:
			sum += u[1]
			n += 1
	_util_lock.unlock()
	return sum / n if n > 0 else -1.0


func _bot_list() -> Array:
	return main.get_children().filter(func(c): return c.is_in_group("bots"))


## 仲間の居場所の内わけ（カメラから 60 m の内・外、画面に入っているか）
func _census() -> String:
	var cam := root.get_camera_3d()
	var near_in := 0
	var far_in := 0
	var out := 0
	for b in _bot_list():
		var p: Vector3 = b.global_position + Vector3.UP
		if not cam.is_position_in_frustum(p):
			out += 1
		elif cam.global_position.distance_to(p) <= 60.0:
			near_in += 1
		else:
			far_in += 1
	return "画面の中で 60 m の内 %d 人・外 %d 人、画面の外 %d 人。描く数 %d" % [near_in, far_in, out, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]


## 消すときは、消す距離を 0 にする（いまの寄り具合を覚えさせて、lantern.gd の _fit_fade に戻させない）。
## 戻すときは、次のコマで _fit_fade に合わせ直させる
func _lights(on: bool) -> void:
	var cam := root.get_camera_3d()
	for b in _bot_list():
		var lt = b.doll._lantern
		lt._fade_k = -1.0 if on else clampf(cam.fov / 75.0, 0.02, 1.0)
		if not on:
			lt._light.distance_fade_begin = 0.0
			lt._light.distance_fade_length = 0.01


func _doll_shadows(on: bool) -> void:
	for b in _bot_list():
		for g in b.find_children("*", "GeometryInstance3D", true, false):
			if on:
				if g.has_meta("cc_shadow"):
					g.cast_shadow = g.get_meta("cc_shadow")
			else:
				g.set_meta("cc_shadow", g.cast_shadow)
				g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _kind(on: bool, cls: String) -> void:
	for b in _bot_list():
		for g in b.find_children("*", cls, true, false):
			g.visible = on


func _lantern_body(on: bool) -> void:
	for b in _bot_list():
		for c in b.doll._lantern.get_children():
			if c is Node3D and not (c is Light3D):
				c.visible = on


func _lod(on: bool) -> void:
	for b in _bot_list():
		for g in b.find_children("*", "GeometryInstance3D", true, false):
			g.lod_bias = 1.0 if on else 0.3


## far が 0 より大きければ、カメラからそれより遠い人形だけ
func _bots(on: bool, far := 0.0) -> void:
	var cam := root.get_camera_3d()
	for b in _bot_list():
		if far > 0.0 and on == false and cam.global_position.distance_to(b.global_position) <= far:
			continue
		(b as Node3D).visible = on


## script の付いた物の物理を止める。bots_only なら、あなたのソリ（main.sled）は止めない
func _script_nodes(on: bool, script: String, skip_mine: bool) -> void:
	for n in main.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc and sc.resource_path == script and not (skip_mine and n == main.sled):
			n.set_physics_process(on)


func _brains(on: bool) -> void:
	for b in _bot_list():
		b.set_physics_process(on)


func _poses(on: bool) -> void:
	for b in _bot_list():
		b.doll.set_physics_process(on)
		b.doll.set_process(on)


func _setting(key: String, on: bool) -> void:
	main.settings.values[key] = on
	main._apply_setting(key, on)


func _process(dt: float) -> bool:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	t += dt
	var now := Time.get_ticks_usec()
	match _phase:
		"wait":
			if t > float(args.get("warm", "15")):
				if args.has("at"):   # --at=x,z,向き(度): あなたをそこに立たせる（向き 0 は北 = -z）
					var v := String(args["at"]).split(",")
					var p: CharacterBody3D = main.player
					var x := float(v[0])
					var z := float(v[1])
					p.global_position = Vector3(x, preload("res://main.gd").ground(x, z) + 0.2, z)
					p.velocity = Vector3.ZERO
					p.rotation.y = deg_to_rad(float(v[2]) if v.size() > 2 else 0.0)
					t = 0.0
					_phase = "settle"
					return false
				print("仲間 %d 人 窓 %s" % [_bot_list().size(), str(root.size)])
				print(_census())
				if args.has("freeze"):   # 仲間を止めて、描く重さだけを比べる（動くとぶれる）
					for b in _bot_list():
						b.process_mode = Node.PROCESS_MODE_DISABLED
				elif args.has("still"):   # 仲間の考えと歩みだけ止める（人形は立ったまま、姿勢のコマと息を続ける）
					for b in _bot_list():
						b.set_physics_process(false)
				_phase = "run"
				_begin()
		"settle":   # 立たせた所に慣れるまで（描く物の読み込み）
			if t > 3.0:
				args.erase("at")
				t = 999.0
				_phase = "wait"
		"run":
			if t > 0.8 and _last_us > 0:
				if _samples.is_empty():
					_phase_us = now
				_samples.append((now - _last_us) / 1000.0)
			if t > float(args.get("per", "3")):
				_end()
	_last_us = now
	return false


func _begin() -> void:
	t = 0.0
	_samples.clear()
	if _off:
		(_steps[_si][1] as Callable).call(false)


func _end() -> void:
	_samples.sort()
	var med: float = _samples[_samples.size() / 2] if _samples.size() > 0 else 0.0
	var name: String = _steps[_si][0]
	if not _res.has(name):
		_res[name] = [[], []]
	_res[name][1 if _off else 0].append(med)
	if not _gpu.has(name):
		_gpu[name] = [[], []]
	var u := _util_since(_phase_us)
	if u >= 0.0:
		_gpu[name][1 if _off else 0].append(med * u / 100.0)
	if args.has("trace"):   # 段ごとの様子（時刻・描く数・面の数・使用率）。急に重くなった段の中身を見る
		var dc := root.get_node_or_null("DayCycle")
		print("  %s %s  %.2f ms  使用率 %.0f%%  物理 %.2f ms  処理 %.2f ms  描く数 %d  面 %d  時刻 %.2f" % [name, "消" if _off else "ふ", med, u,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), dc.hour if dc else -1.0])
	if _off:
		(_steps[_si][1] as Callable).call(true)
		_off = false
		_round += 1
		if _round >= int(args.get("rounds", "3")):
			_round = 0
			_si += 1
			if _si >= _steps.size():
				_report()
				_util_stop = true
				_util_thread.wait_to_finish()
				quit()
				return
	else:
		_off = true
	_begin()


func _report() -> void:
	print("項目 / ふつう ms / 消した ms / 差 ｜ GPU ふつう ms / 消した ms / 差")
	for s in _steps:
		var r: Array = _res[s[0]]
		var a: Array = r[0].duplicate()
		var b: Array = r[1].duplicate()
		a.sort()
		b.sort()
		var ma: float = a[a.size() / 2]
		var mb: float = b[b.size() / 2]
		var ga: Array = _gpu[s[0]][0].duplicate()
		var gb: Array = _gpu[s[0]][1].duplicate()
		ga.sort()
		gb.sort()
		var gma: float = ga[ga.size() / 2] if ga.size() > 0 else -1.0
		var gmb: float = gb[gb.size() / 2] if gb.size() > 0 else -1.0
		print("%s  %.2f  %.2f  %+.2f ｜ %.2f  %.2f  %+.2f" % [s[0], ma, mb, mb - ma, gma, gmb, gmb - gma])
