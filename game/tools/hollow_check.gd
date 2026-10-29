extends SceneTree
## ふもとのくぼみでソリが止まるかの確かめ用（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/hollow_check.gd -- --sled=KIND --no-player --bots=0 --no-sound [--dirs=90,110]
## 頂上から、--sled の大きさで（小は 1・2 人、中は 1・3 人、大は 1・8 人、米袋は蹴らないと 1 秒に 10 回蹴り続ける）、--dirs の向き（度。
## 90 が真南＝スタートの側、110 がロッジの向き）へ滑り降りる。滑り出しは全員前傾で雪をかき、あとは何もしない（米袋は蹴り続ける）。
## 止まった所（頂上からの距離）、いちばん遠くまで行った所、ロッジのならした範囲にいちばん近づいた距離、最高速度を出す。

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sled: RigidBody3D
var t := 0.0
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _rows: Array[String] = []
var _started := false
var _stops := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()


## ロッジのならした範囲（LODGE_PAD）の外側までの距離 (m)。中なら 0
func _pad_gap(p: Vector3) -> float:
	var d: Vector2 = Vector2(p.x, p.z) - main.LODGE_POS
	var c: float = cos(main.LODGE_YAW)
	var s: float = sin(main.LODGE_YAW)
	var l := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	var pad: Rect2 = main.LODGE_PAD
	var q := Vector2(maxf(pad.position.x - l.x, l.x - pad.end.x), maxf(pad.position.y - l.y, l.y - pad.end.y))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null:
		return false
	if not _started:
		if t < 0.5:
			return false
		_started = true
		sled = main.sled
		if args.get("case", "") == "pull":
			_queue.append("pull")
			return false
		var cases := {"small": [[1, 0], [2, 0]], "mid": [[1, 0], [3, 0]], "large": [[1, 0], [8, 0]], "sack": [[1, 0], [1, 10]]}
		for dir in args.get("dirs", "90,110").split(","):
			for c in cases[sled.kind]:
				_queue.append([sled.kind, c[0], c[1], float(dir)])
		_rows.append("| 向き | ソリ | 乗る人 | 最高速度 | いちばん遠く | 止まった所 | ロッジのならした範囲まで（いちばん近づいたとき） |")
		_rows.append("|---|---|---|---|---|---|---|")
		return false
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			if args.has("stops"):   # 止まった所を JSON に足す（図に描く用）
				var old := []
				if FileAccess.file_exists(args["stops"]):
					old = JSON.parse_string(FileAccess.get_file_as_string(args["stops"]))
				var f := FileAccess.open(args["stops"], FileAccess.WRITE)
				f.store_string(JSON.stringify(old + _stops))
			quit()
			return true
		if _queue[0] is String:
			_queue.pop_front()
			_start_pull()
			return false
		var c: Array = _queue.pop_front()
		var a := deg_to_rad(c[3])
		var f := Vector3(cos(a), 0, sin(a))
		var from := 6.0 if c[0] == "large" else 2.0   # 大はまんなかの平らな所では動き出さないので、少し下から
		var at := f * from
		sled.reset_to(Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z))
		sled.rotation.y = atan2(-f.x, -f.z)
		sled.parked = false
		var rs := []
		for i in c[1]:
			var d := Node3D.new()
			d.set_script(_dummy)
			d.sled = sled
			main.add_child(d)
			sled.mount(d)
			rs.append(d)
		_run = {"c": c, "rs": rs, "t": 0.0, "go": false, "max": 0.0, "far": 0.0, "gap": 1e9, "still": 0.0, "next": 0.0}
		return false
	var r := _run
	r.t += dt
	if r.has("pull"):
		_pull(r, dt)
		return false
	var v := sled.linear_velocity.length()
	if not r.go:
		for d in r.rs:
			sled.lean(0.0, true)
		r.go = r.t > 0.3 and v >= 1.5
	elif r.c[2] > 0:
		r.next -= dt
		if r.next <= 0.0:
			r.next += 1.0 / r.c[2]
			sled.kick(r.rs[0])
	var p := sled.global_position
	var dist := Vector2(p.x, p.z).length()
	if r.t > 0.5:
		r.max = maxf(r.max, v)
	r.far = maxf(r.far, dist)
	r.gap = minf(r.gap, _pad_gap(p))
	r.still = r.still + dt if v < 0.2 and r.t > 2.0 else 0.0
	if r.still > 1.0 or r.t > 120.0:
		_rows.append("| %.0f° | %s | %d%s | %.1f m/s | %.0f m | %.0f m%s | %.0f m |" % [r.c[3], r.c[0], r.c[1],
				("（1 秒に %d 回蹴る）" % r.c[2]) if r.c[2] > 0 else "", r.max, r.far, dist,
				"" if r.still > 1.0 else "（120 秒で止まらない）", r.gap])
		_stops.append({"x": p.x, "z": p.z, "kind": r.c[0], "n": r.c[1], "kick": r.c[2], "dir": r.c[3], "far": r.far, "gap": r.gap})
		for d in r.rs:
			sled.dismount(d)
			d.queue_free()
		_run = {}
	return false


# ---------------------------------------------------------------- 引いて運ぶ
## --case=pull（--no-player なしで --bots=0）: くぼみの底に止めたソリの紐を持ち、ロッジの玄関前（ソリを出す所）へ W で歩き続ける。
## 着くまでの時間と、坂の途中で止まらないかを出す

func _start_pull() -> void:
	var p = main.player
	var to: Vector3 = main.delivery_spot(sled.kind).origin
	var dir := Vector2(to.x, to.z).normalized()
	var at: Vector2 = dir * (main.BOWL_R + 1.0)
	var fwd := Vector3(to.x - at.x, 0, to.z - at.y).normalized()
	sled.reset_to(Vector3(at.x, main.height(at.x, at.y) + 0.3, at.y))
	sled.rotation.y = atan2(-fwd.x, -fwd.z)
	p.global_position = sled.to_global(Vector3(0, 0, -sled.HALF.y - 1.6)) + Vector3.UP * 0.3
	p.rotation.y = atan2(-fwd.x, -fwd.z)
	p.grab_rope()
	_key(KEY_W, true)
	_run = {"pull": true, "to": to, "t": 0.0, "log": 0.0}


func _pull(r: Dictionary, dt: float) -> void:
	var p = main.player
	var to: Vector3 = r.to
	var aim: Vector3 = to + (to - Vector3(0, to.y, 0)).normalized() * 10.0   # 引く人は玄関前の先まで歩く
	var d := Vector2(aim.x - p.global_position.x, aim.z - p.global_position.z)
	p.rotation.y = atan2(-d.x, -d.y)
	var s := sled.global_position
	var left := Vector2(to.x - s.x, to.z - s.z).length()
	r.log += dt
	if r.log >= 2.0:
		r.log = 0.0
		print("t=%.0f ソリの高さ %.1f m　玄関前まで %.1f m　速さ %.1f m/s　紐=%s" % [r.t, s.y, left, sled.linear_velocity.length(), p.mode == p.Mode.ROPE])
	if left < 4.0 or r.t > 90.0:
		_key(KEY_W, false)
		print("%s: %s に %.0f 秒（底から玄関前まで）" % [sled.kind, "着いた" if left < 4.0 else "90 秒で着かない", r.t])
		quit()


func _key(k: Key, on: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)
