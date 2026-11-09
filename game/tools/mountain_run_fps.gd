extends SceneTree
## 大きな山の頂上から 3 人乗りのソリ（mid）で 3 人で滑り、麓に着くまでと止まってからの重さを 1 秒ごとに書く
## （2026-11-09 代表「麓に着く頃にすごく FPS が低下し、お金の処理もガクガク」）。
##   Godot --path game --maximized -s res://tools/mountain_run_fps.gd -- --sled=mid --bots=2 --roam-bots=30 --no-sound --time=21 [--after=15] [--grand] [--from=12] [--push=8] [--steps=N] [--pacing]
## 頂上から --from m（既定 12）下った所から、北（ロッジの側、--grand なら大山の頂上から西）へ --push m/s（既定 8）で押し出して、あとは何もしない。止まってから --after 秒で終わる。
## 1 秒ごとに: 1 コマの時間の平均・いちばん長いコマ、ソリの速さ・場所・高さ、糸の上のボタンの数、ノードの数、描く数

const Mountain := preload("res://mountain.gd")
const Grand := preload("res://grand_mountain.gd")
const Main := preload("res://main.gd")

var args := {}
var main: Node3D
var t := 0.0
var _phase := "wait"
var _sum := 0.0
var _n := 0
var _max := 0.0
var _next := 1.0
var _stop_t := -1.0
var _rt := 0.0
var _evs := {}   # この 1 秒に craft.gd で起きた出来事の種類 → 数
var _dress_n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	AudioServer.set_bus_mute(0, true)
	if args.has("steps"):   # 1 コマに進める物理の歩みの上限（Godot の既定は 8）
		Engine.max_physics_steps_per_frame = int(args["steps"])
	_hook.call_deferred()


func _hook() -> void:
	var craft = main.get_node_or_null("Craft")
	if craft:
		craft.happened.connect(func(ev: Dictionary): _evs[String(ev.get("kind", "?"))] = int(_evs.get(String(ev.get("kind", "?")), 0)) + 1)


func _process(dt: float) -> bool:
	if not args.has("pacing"):
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	t += dt
	match _phase:
		"wait":
			if t > 4.0:
				_start()
		"run":
			_rt += dt
			_sum += dt
			_n += 1
			_max = maxf(_max, dt)
			if _rt >= _next:
				_next += 1.0
				_line()
				_sum = 0.0
				_n = 0
				_max = 0.0
			var sled: RigidBody3D = main.sled
			if _stop_t < 0.0 and _rt > 5.0 and sled.linear_velocity.length() < 0.3:
				_stop_t = _rt
				print("止まった %.0f 秒" % _rt)
			if _stop_t >= 0.0 and _rt > _stop_t + float(args.get("after", "15")):
				quit()
	return false


func _start() -> void:
	if args.has("pacing"):   # 遊ぶときと同じコマの出し方（main.gd の use_game_pacing: 60 FPS の頭打ち・物理の歩みの上限）
		main.use_game_pacing()
	print("物理の歩みの上限 %d" % Engine.max_physics_steps_per_frame)
	var p: CharacterBody3D = main.player
	var sled: RigidBody3D = main.sled
	var top := Vector2(Grand.SX, Grand.SZ) if args.has("grand") else Vector2(Mountain.SX, Mountain.SZ)
	var down := Vector3(-1, 0, 0) if args.has("grand") else Vector3(0, 0, -1)   # 大山は西へ、大きな山は北へ
	var start := top + Vector2(down.x, down.z) * float(args.get("from", "12"))   # 頂上は平らで中のソリが動き出さないので、少し下から
	var at := Vector3(start.x, Main.ground(start.x, start.y) + 0.6, start.y)
	sled.reset_to(at)
	sled.global_transform = Transform3D(Basis.looking_at(down, Vector3.UP), at)   # ソリの前（-Z）を麓へ
	p.global_position = at + sled.global_basis.x * 1.2 + Vector3.UP * 0.3
	p.get_on()
	var riders := 1 if p.mode == p.Mode.RIDE else 0
	for b in main.get_children().filter(func(c): return c.is_in_group("bots") and not c.get("roam")):
		b.global_position = at + Vector3.UP * 0.5
		var s: Vector3 = sled.mount(b)
		if s != Vector3.INF:
			b.seat = s
			b._col.disabled = true
			b.state = b.State.RIDE
			riders += 1
	sled.linear_velocity = down * float(args.get("push", "8"))   # 中のソリは 3 m/s より遅いと粉雪に沈んで止まる（plane）
	print("乗った人 %d 人 ソリ %s 頂上 %s" % [riders, sled.kind, str(at)])
	print("秒,ms平均,ms最大,速さ,x,z,高さ,糸のボタン,ノード,描く数,物理ms,処理ms,  出来事の多い順")
	_phase = "run"


func _line() -> void:
	var sled: RigidBody3D = main.sled
	var hud = main.get("hud")
	var sewn: int = hud._spd_sewn.size() if hud else -1
	if int(_rt) % 5 == 0:
		print("  " + _census())
	var top := _evs.keys()
	top.sort_custom(func(a, b): return _evs[a] > _evs[b])
	var ev_s := " ".join(top.slice(0, 5).map(func(k): return "%s=%d" % [k, _evs[k]]))
	_evs.clear()
	print("%d,%.2f,%.1f,%.1f,%.0f,%.0f,%.1f,%d,%d,%d,%.2f,%.2f" % [int(_rt), _sum / maxi(_n, 1) * 1000.0, _max * 1000.0, sled.linear_velocity.length(),
			sled.global_position.x, sled.global_position.z, sled.global_position.y, sewn, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0] + ",  " + ev_s)


## 仲間の居場所の内わけ: カメラから 30 m・130 m の内、画面に入っているか、乗っているか
func _census() -> String:
	var cam := root.get_camera_3d()
	var c := {"30m内": 0, "130m内": 0, "遠い": 0, "画面の外": 0, "乗っている": 0}
	for b in main.get_children().filter(func(x): return x.is_in_group("bots")):
		var p: Vector3 = b.global_position + Vector3.UP
		var d := cam.global_position.distance_to(p)
		if not cam.is_position_in_frustum(p):
			c["画面の外"] += 1
		elif d <= 30.0:
			c["30m内"] += 1
		elif d <= 130.0:
			c["130m内"] += 1
		else:
			c["遠い"] += 1
		if b.get("state") == b.State.RIDE:
			c["乗っている"] += 1
	return str(c)
