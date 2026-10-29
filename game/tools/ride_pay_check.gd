extends SceneTree
## 滑った距離と速さでもらえるボタン（snow_buttons.gd の ride_pay）を、ソリの大きさごとに測る（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/ride_pay_check.gd -- --sled=mid --no-player --bots=0 --no-sound --no-lodge
## 頂上（3 m）から +z（ふもと）へ向けて置き、2 m/s で押し出して（頂上は平らで、大は乗ったまま雪をかいても動き出さない）、
## 乗る人を 1 人と席いっぱいで、あとは何もしない。米袋は、Space の連打（1 秒に 0・6・10 回）も比べる。
## 連打は、ふもとの平らな所（高さ 1 m より下）に着いたらやめる（平らな所でも漕げるので、やめないと地図の端まで行く）。
## 斜面のボタンは置かない。--trace で 2 秒ごとの位置
## 出すのは、滑った長さ、いちばん速い所、もらえた木と真鍮の数（乗っていた一人ひとりに入る数）。

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sled: RigidBody3D
var sb: Node3D
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _rows: Array[String] = []
var t := 0.0
var _started := false
var _paid := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null or main.snow_buttons == null:
		return false
	sled = main.sled
	sb = main.snow_buttons
	sb.auto = false
	if t < 0.5:
		return false
	if not _started:
		_started = true
		sb.clear()
		sb.happened.connect(func(ev: Dictionary) -> void:
			if ev.kind == "ride_pay":
				_paid = ev)
		var counts := [1, sled.SEATS.size()] if sled.SEATS.size() > 1 else [1]
		if args.has("riders"):
			counts = [int(args["riders"])]
		for n in counts:
			if sled.kind == "sack":
				for rate in ([int(args["rate"])] if args.has("rate") else [0, 6, 10]):
					_queue.append([n, rate])
			else:
				_queue.append([n, 0])
		_rows.append("| ソリ | 乗る人 | 連打（回/秒） | 滑った長さ | いちばん速い所 | 木 | 真鍮 | 一人に入る数 |")
		_rows.append("|---|---|---|---|---|---|---|---|")
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return true
		var q: Array = _queue.pop_front()
		sled.reset_to(Vector3(0, main.height(0, 3.0) + 0.3, 3.0))
		sled.rotation.y = PI
		sled.parked = false
		sled.linear_velocity = Vector3(0, 0, 2.0)
		var rs := []
		for i in q[0]:
			var d := Node3D.new()
			d.set_script(_dummy)
			d.sled = sled
			main.add_child(d)
			sled.mount(d)
			rs.append(d)
		_paid = {}
		_run = {"n": q[0], "rate": q[1], "rs": rs, "t": 0.0, "go": false, "next": 0.0, "best": 0.0}
		return false
	var r := _run
	r.t += dt
	var v := sled.linear_velocity.length()
	r.best = maxf(r.best, v)
	if not r.go:
		for d in r.rs:
			sled.lean(0.0, true)
		r.go = r.t > 0.3 and v >= 1.5
	elif r.rate > 0 and sled.global_position.y > 1.0:
		r.next -= dt
		if r.next <= 0.0:
			r.next = 1.0 / float(r.rate)
			sled.kick(r.rs[0])
	if args.has("trace") and Engine.get_physics_frames() % 120 == 0:
		var run: Dictionary = sb._runs.get(sled, {})
		print("t=%.0f pos=(%.1f, %.1f, %.1f) v=%.1f 滑り=%s" % [r.t, sled.global_position.x, sled.global_position.y, sled.global_position.z, v,
				("%.0f m slow=%.1f" % [run.dist, run.slow]) if not run.is_empty() else "なし"])
	if not _paid.is_empty() or r.t > 90.0:
		var p := _paid
		var wood: int = p.get("wood", 0)
		var brass: int = p.get("brass", 0)
		_rows.append("| %s | %d | %d | %.0f m | %.1f m/s | %d | %d | %d |" % [sled.kind, r.n, r.rate, float(p.get("dist", 0.0)), r.best, wood, brass, wood + 10 * brass])
		for d in r.rs:
			sled.dismount(d)
			d.queue_free()
		_run = {}
	return false
