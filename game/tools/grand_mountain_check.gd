extends SceneTree
## 大山（grand_mountain.gd）の確かめ用（数字だけ出す）。
##   Godot --headless --path game -s res://tools/grand_mountain_check.gd -- --case=shape [--out=heights.json]   形の数字（軽い）
##   ゲームを動かす確かめは、後ろに --fixed-fps 60 ... を付ける:
##   Godot --headless --fixed-fps 60 --path game -s res://tools/grand_mountain_check.gd -- --case=<名前> --sled=KIND --no-player --bots=0 --no-sound
##     --case=run     頂上の西の端から西へ滑る。滑り出しだけ前傾。帯ごとの最高速度、段へ入る速さ・出る速さ、止まった所、ジャンプ
##     --case=bench   段の奥の手前の斜面（--from=x）から、段へ滑り込む。段で止まるか。止まったら前傾して動き出し、段の縁を越えて麓まで下りるか
##     --case=rest    段のまんなかに置く: 誰も乗らず放す、乗って何もしない。ずり落ちないか
##     --case=climb   南の尾根の下の端から --pushers 人で押して、段と頂上まで。時間（--no-player のまま。押す力は人と同じ sled.push）
##     --case=kick    ジャンプ台ごとに、踏み切りの 14 m 手前から --speeds（既定 8,12 m/s）で入る。飛んだ時間と長さ
##     --case=rail    手すりの手前から 6 m/s で入る
##     --case=seam    地面の継ぎ目（x = 128）をまたいで、東と西へ --pushers 人で押す。いちばん遅くなった速さ
##     --case=buttons 30 秒待って、大山に降ったボタンの数と場所の倍率
##   歩きは --case=walk（--no-player を付けない）: あなたが尾根の下の端から背に沿って W で歩き、段と頂上に着くまで

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const DT := 1.0 / 60.0
const World := preload("res://main.gd")
const Grand := preload("res://grand_mountain.gd")

var args := {}
var main: Node3D
var sled: RigidBody3D
var t := 0.0
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _started := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.get("case", "shape") == "shape":
		_shape()
		quit()
		return
	var t0 := Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	print("場面を作る時間: %d ms" % (Time.get_ticks_msec() - t0))
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()


func _place(at: Vector3, fwd: Vector3) -> void:
	sled.reset_to(Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z))
	sled.rotation.y = atan2(-fwd.x, -fwd.z)
	sled.parked = false


func _riders(n: int) -> Array:
	var rs := []
	for i in n:
		var d := Node3D.new()
		d.set_script(_dummy)
		d.sled = sled
		main.add_child(d)
		sled.mount(d)
		rs.append(d)
	return rs


func _off(rs: Array) -> void:
	for d in rs:
		sled.dismount(d)
		d.queue_free()


func _clear() -> float:
	var p := sled.global_position
	return p.y - main.height(p.x, p.z) - sled.KINDS[sled.kind].box.y * 0.5


func _mmss(s: float) -> String:
	if s < 0.0:
		return "時間切れ"
	return "%d 分 %02d 秒" % [int(s) / 60, int(s) % 60]


func _physics_process(dt: float) -> bool:
	t += dt
	if main == null or args.get("case") == "walk":
		return _walk_step(dt) if main != null else false
	if main.sled == null:
		return false
	if not _started:
		if t < 0.5:
			return false
		_started = true
		sled = main.sled
		match args.get("case"):
			"run", "bench":
				var cases := {"small": [1, 2], "mid": [1, 3], "large": [1, 8], "sack": [1]}
				_queue = cases[sled.kind].duplicate()
			"rest":
				_queue = [0, 1]
			"climb":
				for n in args.get("pushers", "2,4").split(","):
					_queue.append(int(n))
			"kick":
				for i in Grand.KICKERS.size():
					for v in args.get("speeds", "8,12").split(","):
						_queue.append([i, float(v)])
			"rail":
				_queue = [6.0, 4.0]
			"seam":
				_queue = [1.0, -1.0]
			"buttons":
				_queue = [0]
		return false
	if _run.is_empty():
		if _queue.is_empty():
			quit()
			return true
		var c = _queue.pop_front()
		match args.get("case"):
			"run":
				_place(Vector3(Grand.START.x, 0, Grand.START.y), Vector3(-1, 0, 0))
				_run = {"kind": "run", "rs": _riders(c), "t": 0.0, "go": false, "max": 0.0, "secs": {}, "in": -1.0, "out": -1.0, "low": 99.0, "still": 0.0,
						"air": [], "air_from": -1.0, "air_t": 0.0, "side": 0.0}
			"bench":
				var from := float(args.get("from", "575"))
				_place(Vector3(from, 0, Grand.SZ), Vector3(-1, 0, 0))
				_run = {"kind": "bench", "rs": _riders(c), "t": 0.0, "go": false, "stop_x": -1.0, "stop_t": -1.0, "still": 0.0, "max": 0.0, "go2": -1.0, "low_v": 99.0}
			"rest":
				var at := Vector3(Grand.REST.x, 0, Grand.REST.y)
				_place(at, Vector3(-1, 0, 0))
				_run = {"kind": "rest", "rs": _riders(c), "t": 0.0, "at": at}
			"climb":
				var foot: Vector2 = Grand.RIDGE[Grand.RIDGE.size() - 1] + Vector2(16, 0)
				var up: Vector2 = Grand.ridge_guide(foot)
				_place(Vector3(foot.x, 0, foot.y), Vector3(up.x, 0, up.y))
				_run = {"kind": "climb", "climb": c, "t": 0.0, "bench": -1.0, "top": -1.0, "log": 0.0, "stuck": 0.0, "stops": 0}
			"kick":
				var k: Dictionary = Grand.kicker(c[0])
				var f: Vector2 = k.f
				var at2: Vector2 = (k.lip as Vector2) - f * (Grand.KICK_L + 14.0)
				_place(Vector3(at2.x, 0, at2.y), Vector3(f.x, 0, f.y))
				sled.linear_velocity = Vector3(f.x, 0, f.y) * c[1]
				_run = {"kind": "kick", "c": c, "t": 0.0, "rs": _riders(1), "lip": k.lip, "f": f, "air": 0.0, "from": null, "len": 0.0, "best": 0.0, "bestlen": 0.0, "under": 0.0}
			"rail":
				var d3 := (Grand.RAIL_BOTTOM - Grand.RAIL_TOP).normalized()
				var at3: Vector2 = Grand.RAIL_TOP - d3 * 3.0
				_place(Vector3(at3.x, 0, at3.y), Vector3(d3.x, 0, d3.y))
				sled.linear_velocity = Vector3(d3.x, 0, d3.y) * c
				_run = {"kind": "rail", "t": 0.0, "rs": _riders(1), "on": 0.0, "from": null, "len": 0.0}
			"seam":
				_place(Vector3(128.0 - c * 14.0, 0, 30.0), Vector3(c, 0, 0))
				_run = {"kind": "seam", "dir": c, "t": 0.0, "low": 99.0, "started": false, "x0": 128.0 - c * 14.0}
			"buttons":
				_run = {"kind": "buttons", "t": 0.0}
		return false
	var r := _run
	r.t += dt
	match r.kind:
		"run":
			_run_step(r)
		"bench":
			_bench_step(r)
		"rest":
			_rest_step(r)
		"climb":
			_climb_step(r, dt)
		"kick":
			_kick_step(r)
		"rail":
			_rail_step(r)
		"seam":
			_seam_step(r)
		"buttons":
			_buttons_step(r)
	return false


func _kick_step(r: Dictionary) -> void:
	var p := sled.global_position
	var along: float = (Vector2(p.x, p.z) - r.lip).dot(r.f)
	r.under = minf(r.under, _clear())
	if along > 0.5 and _clear() > 0.3:
		if r.from == null:
			r.from = along
			r.air = 0.0
		r.air += 1.0 / 60.0
		r.len = along - r.from
	elif r.from != null:
		if r.air > r.best:
			r.best = r.air
			r.bestlen = r.len
		r.from = null
	if along > 40.0 or r.t > 15.0 or (r.t > 3.0 and sled.linear_velocity.length() < 0.2):
		print("%s K%d %.0f m/s: 宙 %.2f 秒・%.1f m、雪より下へ %.2f m、%s" % [sled.kind, r.c[0] + 1, r.c[1], r.best, r.bestlen, r.under, "縁の先へ" if along > 0.0 else "縁の手前で止まった"])
		_off(r.rs)
		_run = {}


func _rail_step(r: Dictionary) -> void:
	var p := sled.global_position
	var from := p + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.5)
	q.exclude = [sled.get_rid()]
	var hit := sled.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and (hit.collider as Node).name == "MountainRail":
		if r.from == null:
			r.from = p.x
		r.len = absf(p.x - r.from)
	if r.t > 8.0:
		print("%s: 手すりに乗っていた長さ %.1f m（全長 %.1f m）" % [sled.kind, r.len, Grand.RAIL_TOP.distance_to(Grand.RAIL_BOTTOM)])
		_off(r.rs)
		_run = {}


func _seam_step(r: Dictionary) -> void:
	var p := sled.global_position
	var dir := Vector3(r.dir, 0, 0)
	for i in int(args.get("pushers", "2")):
		var side := -1.0 if i % 2 == 0 else 1.0
		sled.push(dir, sled.to_global(Vector3(side * sled.HALF.x * 0.8, 0.2, sled.HALF.y)))
	var v := sled.linear_velocity.length()
	if r.t > 3.0 and absf(p.x - 128.0) < 6.0:
		r.low = minf(r.low, v)
	if (p.x - r.x0) * r.dir > 28.0 or r.t > 60.0:
		print("%s %s へ押す: 継ぎ目の前後 ±6 m でいちばん遅く %.2f m/s、%.0f 秒で %.0f m" % [sled.kind, "東" if r.dir > 0 else "西", r.low, r.t, absf(p.x - r.x0)])
		_run = {}


func _buttons_step(r: Dictionary) -> void:
	if r.t < 30.0:
		return
	var sb = main.get("snow_buttons")
	var n := 0
	var low := INF
	var high := -INF
	for b in sb.buttons.values():
		if sb.map_of(b.at) == "grand" and b.state != "gone":
			n += 1
			low = minf(low, b.at.y)
			high = maxf(high, b.at.y)
			var gap: float = b.at.y - main.height(b.at.x, b.at.z)
			if absf(gap) > 1.0 and b.state == "stuck":
				print("雪から離れたボタン: ", b.at, " ", gap)
	print("大山のボタン %d 個（高さ %.0f〜%.0f）。場所の倍率: 麓 ×%.2f、段 ×%.2f、頂上 ×%.2f（大きな山の頂上 ×%.2f）" % [n, low, high, sb.place_rate(Vector3(180, 3, 30)), sb.place_rate(Vector3(505, 98, 30)), sb.place_rate(Vector3(704, 144, 32)), sb.place_rate(Vector3(-5, 73, 492))])
	_run = {}
	_queue = []


func _run_step(r: Dictionary) -> void:
	var v := sled.linear_velocity.length()
	if not r.go:
		for d in r.rs:
			sled.lean(0.0, true)
		r.go = r.t > 0.3 and v >= 1.5
	var p := sled.global_position
	if r.t > 0.5:
		r.max = maxf(r.max, v)
	var zn: String = Grand.zone(p.x)
	r.secs[zn] = maxf(r.secs.get(zn, 0.0), v)
	r.side = maxf(r.side, absf(p.z - Grand.FACE_Z))
	if zn == "段":
		if r.in < 0.0:
			r.in = v
		r.out = v
		r.low = minf(r.low, v)
	if _clear() > 0.35:
		if r.air_from < 0.0:
			r.air_from = p.x
			r.air_t = 0.0
		r.air_t += DT
	elif r.air_from >= 0.0:
		if r.air_t > 0.15:
			r.air.append("x=%.0f→%.0f（%.2f 秒）" % [r.air_from, p.x, r.air_t])
		r.air_from = -1.0
	r.still = r.still + DT if v < 0.2 and r.t > 3.0 else 0.0
	if r.still > 1.5 and zn in ["頂上", "上の斜面", "段"] and not r.has("rest_gave_up"):
		# 段（や上）で止まったら、一息ついて前傾で動き出す
		if not r.has("stop"):
			r.stop = "x=%.0f（%s）に %.0f 秒で止まった" % [p.x, zn, r.t]
		r.go = false
		r.still = 0.0
		r.hold = true
		r.t0_go = r.t
		r.tries = r.get("tries", 0) + 1
		if r.tries > 3:
			r.rest_gave_up = true
		return
	if r.get("hold", false):   # W を押したまま、段の縁を越えるまで
		for d in r.rs:
			sled.lean(0.0, true)
		if p.x < Grand.ZONES[2][1]:
			r.hold = false
			r.stop += "、W を押したまま縁を越えるまで %.0f 秒" % (r.t - r.t0_go)
	if r.still > 1.5 or r.t > 300.0:
		var secs := []
		for s in Grand.ZONES + [["窪地"]]:
			if r.secs.has(s[0]):
				secs.append("%s %.1f" % [s[0], r.secs[s[0]]])
		print("%s %d 人: %.0f 秒、最高 %.1f m/s（%s）、段へ入る %.1f → いちばん遅く %.1f → 出る %.1f m/s、ジャンプ %s、%s、止まった所 x=%.0f z=%.0f y=%.1f、斜面のまんなかから横へ %.0f m%s" % [sled.kind, r.rs.size(), r.t, r.max, "・".join(secs),
				r.in, r.low, r.out, "、".join(r.air) if not r.air.is_empty() else "なし", r.get("stop", "途中で止まらず"), p.x, p.z, p.y, r.side, "" if r.still > 1.5 else "（止まらない）"])
		_off(r.rs)
		_run = {}


func _bench_step(r: Dictionary) -> void:
	var v := sled.linear_velocity.length()
	var p := sled.global_position
	r.max = maxf(r.max, v)
	if not r.go:
		r.go = r.t > 0.5 and v >= 1.5
		for d in r.rs:
			sled.lean(0.0, true)
		return
	if r.stop_t < 0.0:
		r.low_v = minf(r.low_v, v) if p.x < 545.0 else r.low_v
		r.still = r.still + 1.0 / 60.0 if v < 0.15 else 0.0
		if r.still > 1.5:
			r.stop_t = r.t
			r.stop_x = p.x
			print("%s %d 人: x=%.0f から滑り込む。最高 %.1f m/s。止まった所 x=%.0f（%s、高さ %.1f）%.0f 秒" % [sled.kind, r.rs.size(), float(args.get("from", "575")), r.max, p.x, Grand.zone(p.x), p.y - 3.0, r.t])
		elif p.x < 440.0 or r.t > 120.0:
			print("%s %d 人: 段で止まらず、x=%.0f を %.1f m/s（段でいちばん遅く %.1f m/s）" % [sled.kind, r.rs.size(), p.x, v, r.low_v])
			_off(r.rs)
			_run = {}
		return
	# 止まったら、1 秒休んで前傾して動き出す。動き出してから縁の先まで
	if r.t < r.stop_t + 1.0:
		return
	for d in r.rs:
		sled.lean(0.0, true)
	if r.go2 < 0.0 and v > 1.0:
		r.go2 = r.t
	if p.x < 440.0 or r.t > r.stop_t + 90.0:
		print("  前傾で動き出す: 1 m/s まで %.1f 秒、x=440 まで %.0f 秒（x=%.0f、%.1f m/s）" % [r.go2 - r.stop_t - 1.0, r.t - r.stop_t - 1.0, p.x, v])
		_off(r.rs)
		_run = {}


func _rest_step(r: Dictionary) -> void:
	if r.t > 20.0:
		var p := sled.global_position
		print("%s 乗る人 %d: 段のまんなかに置いて 20 秒で動いた距離 %.2f m、速さ %.2f m/s" % [sled.kind, r.rs.size(), Vector2(p.x - r.at.x, p.z - r.at.z).length(), sled.linear_velocity.length()])
		_off(r.rs)
		_run = {}


func _climb_step(r: Dictionary, dt: float) -> void:
	var n: int = r.climb
	var p := sled.global_position
	var g: Vector2 = Grand.ridge_guide(Vector2(p.x, p.z))
	var dir := Vector3(g.x, 0, g.y)
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := sled.to_global(Vector3(side * sled.HALF.x * 0.8, 0.2, sled.HALF.y))
		sled.push(dir, at)
	if r.bench < 0.0 and p.y - 3.0 >= Grand.BENCH_Y.y:
		r.bench = r.t
		print("  %d 人: 段に着いた %s（x=%.0f z=%.0f）" % [n, _mmss(r.t), p.x, p.z])
	if r.top < 0.0 and p.y - 3.0 >= 138.0:
		r.top = r.t
	r.stuck = r.stuck + dt if sled.linear_velocity.length() < 0.1 else 0.0
	r.log += dt
	if r.log >= 60.0:
		r.log = 0.0
		print("  %d 人: %.0f 秒 x=%.0f z=%.0f 高さ %.1f m 速さ %.2f m/s 背から %.1f m" % [n, r.t, p.x, p.z, p.y - 3.0, sled.linear_velocity.length(), Grand.Mountain._seg(Vector2(p.x, p.z), Grand._pts).x])
	if r.top >= 0.0 or r.t > float(args.get("limit", "1500")) or r.stuck > 20.0:
		print("%s を %d 人で押す: 段まで %s、頂上まで %s%s" % [sled.kind, n, _mmss(r.bench), _mmss(r.top), "（動かなくなった x=%.0f z=%.0f）" % [p.x, p.z] if r.stuck > 20.0 else ""])
		_run = {}


var _walk := {}


func _walk_step(dt: float) -> bool:
	var pl = main.player
	if pl == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if _walk.is_empty():
		if t < 0.5:
			return false
		var foot: Vector2 = Grand.RIDGE[Grand.RIDGE.size() - 1] + Vector2(16, 0)
		pl.global_position = Vector3(foot.x, main.height(foot.x, foot.y) + 0.3, foot.y)
		_walk = {"t": 0.0, "bench": -1.0, "top": -1.0, "log": 0.0, "low": 99.0, "far": 0.0}
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		return false
	_walk.t += dt
	var p: Vector3 = pl.global_position
	var g: Vector2 = Grand.ridge_guide(Vector2(p.x, p.z))
	pl.rotation.y = atan2(-g.x, -g.y)
	if _walk.bench < 0.0 and p.y - 3.0 >= Grand.BENCH_Y.y:
		_walk.bench = _walk.t
	_walk.log += dt
	if _walk.log >= 30.0:
		_walk.log = 0.0
		print("  歩き %.0f 秒: x=%.0f z=%.0f 高さ %.1f m、気温 %.1f °C" % [_walk.t, p.x, p.z, p.y - 3.0, root.get_node("Temperature").at(p)])
	if p.y - 3.0 >= 138.0 or _walk.t > 900.0:
		print("歩いて登る: 段まで %s、頂上まで %s（x=%.0f z=%.0f 高さ %.1f）" % [_mmss(_walk.bench), _mmss(_walk.t if p.y - 3.0 >= 138.0 else -1.0), p.x, p.z, p.y - 3.0])
		quit()
		return true
	return false


func _slope(x: float, z: float, e := 2.0) -> float:
	var gx := (World.height(x + e, z) - World.height(x - e, z)) / (2.0 * e)
	var gz := (World.height(x, z + e) - World.height(x, z - e)) / (2.0 * e)
	return rad_to_deg(atan(Vector2(gx, gz).length()))


func _shape() -> void:
	var t0 := Time.get_ticks_msec()
	Grand._build()
	print("焼く時間: %d ms" % (Time.get_ticks_msec() - t0))
	var top := -INF
	var at := Vector2.ZERO
	var x0 := 1e9; var x1 := -1e9; var z0 := 1e9; var z1 := -1e9
	var z := Grand.GZ0
	while z <= Grand.GZ1:
		var x := Grand.GX0
		while x <= Grand.GX1:
			var l: float = Grand.lift(x, z)
			if l > top:
				top = l
				at = Vector2(x, z)
			if l > 0.5:
				x0 = minf(x0, x); x1 = maxf(x1, x); z0 = minf(z0, z); z1 = maxf(z1, z)
			x += 2.0
		z += 2.0
	print("頂上: 高台から %.1f m（高さ y = %.1f）(%.0f, %.0f)" % [top, World.height(at.x, at.y), at.x, at.y])
	print("広がり（0.5 m より高い所）: 東西 %.0f m（x %.0f〜%.0f）、南北 %.0f m（z %.0f〜%.0f）" % [x1 - x0, x0, x1, z1 - z0, z0, z1])
	print("大きな山の倍: 高さ %.2f 倍、東西 %.2f 倍、南北 %.2f 倍（大きな山は 70.5 m・南北 386 m・東西 234 m。向きが 90° 違うので、長いほうどうし・短いほうどうしで比べる）" % [top / 70.5, (x1 - x0) / 386.0, (z1 - z0) / 234.0])
	# 真西への断面
	var rows := []
	var x := Grand.SX
	while x >= 130.0:
		rows.append("%d:%.1f(%.1f°)" % [x, World.height(x, Grand.SZ), _slope(x, Grand.SZ)])
		x -= 30.0
	print("西への断面 z=%d: %s" % [Grand.SZ, " ".join(rows)])
	# 段
	var bench_low := INF
	var bench_high := -INF
	var slope_max := 0.0
	var slope_sum := 0.0
	var n := 0
	var flat := 0
	var z2: float = Grand.SZ - 90.0
	while z2 <= Grand.SZ + 90.0:
		var x2: float = Grand.SX - 300.0
		while x2 <= Grand.SX - 100.0:
			var b3: Vector3 = Grand._body(x2, z2)
			if b3.z >= 1.0 and b3.y > Grand.BENCH_R.x + 0.03 and b3.y < Grand.BENCH_R.y - 0.03 and not Grand.on_ridge(x2, z2, 12.0):
				var h: float = World.height(x2, z2) - World.RIM_H
				bench_low = minf(bench_low, h)
				bench_high = maxf(bench_high, h)
				var s := _slope(x2, z2)
				slope_max = maxf(slope_max, s)
				slope_sum += s
				n += 1
				if s < 3.0:
					flat += 1
			x2 += 4.0
		z2 += 4.0
	print("段（%d 点。尾根の背を除く）: 高さ %.1f〜%.1f m（頂上の %.0f〜%.0f%%）、傾き 平均 %.1f°、いちばん急で %.1f°、3° より緩い所 %d%%" % [n, bench_low, bench_high, bench_low / top * 100.0, bench_high / top * 100.0, slope_sum / n, slope_max, flat * 100 / n])
	var central := []
	for o in [-40, -20, 0, 20]:
		var acc := []
		for a2 in range(180, 236, 10):
			acc.append("%.1f°" % _slope(Grand.SX - a2, Grand.SZ + o))
		central.append("z=%d: %s" % [Grand.SZ + o, " ".join(acc)])
	print("段のまんなかの傾き（頂上から西へ 180〜230 m）: ", " / ".join(central))
	# 背
	var slen: float = Grand._ridge_len
	var steep := 0.0
	var steep_at := 0.0
	var rib := 0.0
	var rib_at := 0.0
	var s := 0.0
	while s < slen - 2.0:
		var a2 := Grand._ridge_point(s)
		var b2 := Grand._ridge_point(s + 2.0)
		var d := absf(World.height(a2.x, a2.y) - World.height(b2.x, b2.y)) / a2.distance_to(b2)
		if rad_to_deg(atan(d)) > steep:
			steep = rad_to_deg(atan(d))
			steep_at = s
		var over: float = Grand._ridge_at(s) - Grand._body(a2.x, a2.y).x
		if over > rib:
			rib = over
			rib_at = s
		s += 2.0
	print("南の尾根: 長さ %.0f m、背の坂のいちばん急 %.1f°（頂上から %.0f m）、地肌よりいちばん高い所 %.1f m（頂上から %.0f m）" % [slen, steep, steep_at, rib, rib_at])
	var hist := [0, 0, 0, 0, 0, 0, 0]
	z = Grand.GZ0
	while z <= Grand.GZ1:
		x = Grand.GX0
		while x <= Grand.SX:
			if Grand.lift(x, z) > 0.5:
				hist[mini(int(_slope(x, z) / 10.0), 6)] += 1
			x += 8.0
		z += 8.0
	var tops := []
	for tx in range(684, 730, 3):
		tops.append("%d:%.2f" % [tx, World.height(tx, Grand.SZ)])
	print("頂上の近く: ", " ".join(tops))
	print("傾きの分け（0-10°, 10-20°, …）: ", hist)
	if args.has("out"):
		var d := []
		z = Grand.GZ0 
		while z <= Grand.GZ1:
			x = Grand.GX0
			while x <= Grand.GX1:
				d.append(snappedf(World.height(x, z), 0.01))
				x += 4.0
			z += 4.0
		var f := FileAccess.open(args.out, FileAccess.WRITE)
		f.store_string(JSON.stringify({"x0": Grand.GX0, "z0": Grand.GZ0, "step": 4, "nx": Grand.GNX, "nz": Grand.GNZ, "h": d}))
