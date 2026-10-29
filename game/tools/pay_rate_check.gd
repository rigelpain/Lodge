extends SceneTree
## 乗り物ごとの倍率と人数のおまけ（snow_buttons.gd の RIDE_RATE・CREW_BONUS）で、滑った分の一人あたりの取り分を測る（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/pay_rate_check.gd -- --sled=KIND --map=hill|mountain --no-player --bots=0 --no-sound
##   --case=ride（既定） 頂上から 2 m/s で押し出して滑る。乗る人は、米袋 1（漕がない・1 秒に 10 回漕ぐ）、小 1・2、中 1・3、大 1・8。
##                      はじめから乗っていた一人の取り分（倍率と人数のおまけを掛けたあと。端数こみ）を出す
##   --case=climb       丘の溝の底（頂上から 58 m）から、--pushers 人が後ろから押して頂上まで登る時間（大きな山は mountain_check.gd の climb）
## 漕ぐのは、丘は高さ 1 m より下、大きな山は受け皿の 30 m 手前でやめる（平らな所でも漕げるので、やめないと止まらない）。

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const Mountain := preload("res://mountain.gd")

var args := {}
var main: Node3D
var sled: RigidBody3D
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _rows: Array[String] = []
var _paid := {}
var t := 0.0
var _started := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()


func _mountain() -> bool:
	return args.get("map", "hill") == "mountain"


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null:
		return false
	sled = main.sled
	if t < 0.5:
		return false
	var sb = main.snow_buttons
	if not _started:
		_started = true
		sb.auto = false
		sb.clear()
		sb.happened.connect(func(ev: Dictionary) -> void:
			if ev.kind == "ride_pay":
				_paid = ev)
		if args.get("case", "ride") == "climb":
			_queue.append({"climb": int(args.get("pushers", "1"))})
		elif sled.kind == "sack":
			_queue.append({"n": 1, "mash": 0})
			_queue.append({"n": 1, "mash": 10})
		else:
			_queue.append({"n": 1, "mash": 0})
			_queue.append({"n": sled.SEATS.size(), "mash": 0})
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return true
		_start(_queue.pop_front())
		return false
	if _run.has("climb"):
		_climb(dt)
	else:
		_ride(dt)
	return false


func _start(q: Dictionary) -> void:
	if q.has("climb"):
		var z := 58.0
		sled.reset_to(Vector3(0, main.height(0, z) + 0.3, z))
		sled.rotation.y = 0.0   # 前を頂上（-z）へ
		sled.parked = false
		_run = q.merged({"t": 0.0})
		return
	var at := Vector3(0, 0, 3.0)
	var fwd := Vector3(0, 0, 1)
	if _mountain():
		at = Vector3(Mountain.COURSE_X, 0, Mountain.section("頂上")[1] + 1.0)
		fwd = Vector3(0, 0, -1)
	sled.reset_to(Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z))
	sled.rotation.y = atan2(-fwd.x, -fwd.z)
	sled.parked = false
	sled.linear_velocity = fwd * 2.0
	var rs := []
	for i in int(q.n):
		var d := Node3D.new()
		d.set_script(_dummy)
		d.sled = sled
		main.add_child(d)
		sled.mount(d)
		rs.append(d)
	_paid = {}
	_run = q.merged({"rs": rs, "t": 0.0, "next": 0.0, "best": 0.0, "fwd": fwd})


func _ride(dt: float) -> void:
	var r := _run
	r.t += dt
	r.best = maxf(r.best, sled.linear_velocity.length())
	var mash_on: bool = sled.global_position.z > Mountain.BOTTOM_Z + 30.0 if _mountain() else sled.global_position.y > 1.0
	if r.mash > 0 and mash_on:
		r.next -= dt
		if r.next <= 0.0:
			r.next = 1.0 / float(r.mash)
			sled.kick(r.rs[0])
	if not _paid.is_empty() or r.t > 200.0:
		var p := _paid
		var mult: float = main.snow_buttons.RIDE_RATE.get(sled.kind, 1.0) * (1.0 + main.snow_buttons.CREW_BONUS * (int(r.n) - 1))
		_rows.append("| %s | %s | %d | %s | %.0f m | %.1f m/s | 木 %d・真鍮 %d | ×%.2f | %.1f |" % [args.get("map", "hill"), sled.kind, r.n,
				("1 秒に %d 回" % r.mash) if r.mash > 0 else "—", float(p.get("dist", 0.0)), r.best, int(p.get("wood", 0)), int(p.get("brass", 0)),
				mult, float(p.get("acc", 0.0))])
		for d in r.rs:
			sled.dismount(d)
			d.queue_free()
		_run = {}


func _climb(dt: float) -> void:
	var r := _run
	r.t += dt
	var p := sled.global_position
	var dir := Vector3(-p.x, 0, -p.z).normalized()   # 頂上へ
	for i in int(r.climb):
		var side := -1.0 if i % 2 == 0 else 1.0
		sled.push(dir, sled.to_global(Vector3(side * sled.HALF.x * 0.8, 0.2, sled.HALF.y)))
	if Vector2(p.x, p.z).length() < 4.0 or r.t > 600.0:
		_rows.append("| 丘 | %s | %d 人 | %s |" % [sled.kind, r.climb, ("%.0f 秒" % r.t) if r.t <= 600.0 else "時間切れ"])
		_run = {}
