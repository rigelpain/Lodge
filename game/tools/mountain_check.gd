extends SceneTree
## 大きな山（mountain.gd）の確かめ用（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/mountain_check.gd -- --case=<名前> --sled=KIND --no-player --bots=0 --no-sound
##
##   --case=run    頂上から、--sled の大きさで（小は 1・2 人、中は 1・3 人、大は 1・8 人、米袋は蹴らないと 1 秒に 10 回蹴り続ける）
##                 頂上の平らの下の端から、まっすぐ北へ滑り降りる。滑り出しは全員前傾で雪をかき、あとは何もしない（米袋は蹴り続ける）。
##                 区間ごとの最高速度、ジャンプ（踏み切った所・着いた所・宙にいた時間）、コースのまんなかからいちばん離れた横の距離、
##                 止まった所（z と、ロッジのならした範囲まで）
##   --case=rail   手すりの上の端の手前に、--speed (m/s, 既定 6) で手すりへ向けて走り込む。手すりに乗っていた長さ
##   --case=climb  登り道の下の端から、--pushers 人が後ろから押して頂上まで登る（押す力は sled.push。人の歩きは省く）。
##                 中腹と頂上に着くまでの時間

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const Mountain := preload("res://mountain.gd")

var args := {}
var main: Node3D
var sled: RigidBody3D
var t := 0.0
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _rows: Array[String] = []
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


func _pad_gap(p: Vector3) -> float:
	var d: Vector2 = Vector2(p.x, p.z) - main.LODGE_POS
	var c: float = cos(main.LODGE_YAW)
	var s: float = sin(main.LODGE_YAW)
	var l := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	var pad: Rect2 = main.LODGE_PAD
	var q := Vector2(maxf(pad.position.x - l.x, l.x - pad.end.x), maxf(pad.position.y - l.y, l.y - pad.end.y))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


func _section_at(z: float) -> String:
	for s in Mountain.SECTIONS:
		var r: Array = Mountain.section(s[0])
		if z <= r[0] and z >= r[1]:
			return s[0]
	return "受け皿" if z < Mountain.BOTTOM_Z else "裏"


## 雪面からソリの底までの高さ
func _clear() -> float:
	var p := sled.global_position
	return p.y - main.height(p.x, p.z) - sled.KINDS[sled.kind].box.y * 0.5


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


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null:
		return false
	if not _started:
		if t < 0.5:
			return false
		_started = true
		sled = main.sled
		match args.get("case", "run"):
			"run":
				var cases := {"small": [[1, 0], [2, 0]], "mid": [[1, 0], [3, 0]], "large": [[1, 0], [8, 0]], "sack": [[1, 0], [1, 10]]}
				for c in cases[sled.kind]:
					_queue.append(c)
				_rows.append("| ソリ | 乗る人 | 最高速度 | 区間ごとの最高速度 | ジャンプ（踏み切り→着地、宙の時間） | 横にいちばん外れた | 止まった所 | ロッジの範囲まで |")
				_rows.append("|---|---|---|---|---|---|---|---|")
			"rail":
				_queue.append("rail")
			"climb":
				for n in args.get("pushers", "1,2,4").split(","):
					_queue.append(int(n))
		return false
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return true
		var c = _queue.pop_front()
		match args.get("case", "run"):
			"run":
				_place(Vector3(Mountain.COURSE_X, 0, Mountain.section("頂上")[1] + 1.0), Vector3(0, 0, -1))   # 頂上の平らの下の端（押し出したところ）
				_run = {"c": c, "rs": _riders(c[0]), "t": 0.0, "go": false, "max": 0.0, "secs": {}, "air": [], "air_from": -1.0, "air_t": 0.0,
						"side": 0.0, "gap": 1e9, "still": 0.0, "next": 0.0}
			"rail":
				var s: Array = Mountain.section("なだらか 2（手すり）")
				var z0: float = s[0] + 3.0
				_place(Vector3(Mountain.RAIL_X, 0, z0), Vector3(0, 0, -1))
				sled.linear_velocity = Vector3(0, 0, -float(args.get("speed", "6")))
				_run = {"rail": true, "rs": _riders(1), "t": 0.0, "on": 0.0, "from": 1e9, "to": -1e9, "still": 0.0, "max_dx": 0.0}
			"climb":
				_place(Vector3(Mountain.PATH_X, 0, Mountain.BOTTOM_Z + 1.0), Vector3(0, 0, 1))
				_run = {"climb": c, "t": 0.0, "mid": -1.0, "top": -1.0, "log": 0.0}
		return false
	var r := _run
	r.t += dt
	if r.has("rail"):
		_rail_step(r, dt)
	elif r.has("climb"):
		_climb_step(r, dt)
	else:
		_run_step(r, dt)
	return false


func _run_step(r: Dictionary, dt: float) -> void:
	var v := sled.linear_velocity.length()
	if not r.go:
		for d in r.rs:
			sled.lean(0.0, true)
		r.go = r.t > 0.3 and v >= 1.5
	elif r.c[1] > 0:
		r.next -= dt
		if r.next <= 0.0:
			r.next += 1.0 / r.c[1]
			sled.kick(r.rs[0])
	var p := sled.global_position
	if args.has("trace") and p.z < float(args["trace"]) + 6.0 and p.z > float(args["trace"]) - 6.0:
		print("t=%.2f z=%.2f y=%.2f 雪から %.2f v=%.2f 乗る人 %d 傾き %s" % [r.t, p.z, p.y, _clear(), v, sled.riders.size(), str(sled.rotation_degrees.snapped(Vector3.ONE))])
	if r.t > 0.5:
		r.max = maxf(r.max, v)
	var sec := _section_at(p.z)
	r.secs[sec] = maxf(r.secs.get(sec, 0.0), v)
	r.side = maxf(r.side, absf(p.x - Mountain.COURSE_X))
	r.gap = minf(r.gap, _pad_gap(p))
	# 宙: 雪から 0.35 m より上にいるあいだ（0.15 秒より長いものだけ数える）
	if _clear() > 0.35:
		if r.air_from < 0.0:
			r.air_from = p.z
			r.air_t = 0.0
		r.air_t += dt
	elif r.air_from >= 0.0:
		if r.air_t > 0.15:
			r.air.append("%.0f→%.0f（%.1f m、%.2f 秒）" % [r.air_from, p.z, r.air_from - p.z, r.air_t])
		r.air_from = -1.0
	r.still = r.still + dt if v < 0.2 and r.t > 3.0 else 0.0
	if r.still > 1.5 or r.t > 180.0:
		var secs := []
		for s in Mountain.SECTIONS:
			if r.secs.has(s[0]):
				secs.append("%s %.0f" % [s[0], r.secs[s[0]]])
		var tilt := rad_to_deg(acos(clampf(sled.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))
		_rows.append("| %s | %d%s | %.1f m/s | %s | %s | %.1f m | z=%.0f%s%s | %.0f m |" % [sled.kind, r.rs.size(),
				("（1 秒に %d 回蹴る）" % r.c[1]) if r.c[1] > 0 else "", r.max, "・".join(secs),
				"、".join(r.air) if not r.air.is_empty() else "なし", r.side, p.z, "" if r.still > 1.5 else "（止まらない）",
				("（%.0f° 傾いて）" % tilt) if tilt > 30.0 else "", r.gap])
		for d in r.rs:
			sled.dismount(d)
			d.queue_free()
		_run = {}


func _rail_step(r: Dictionary, dt: float) -> void:
	var p := sled.global_position
	var from := p + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.5)
	q.exclude = [sled.get_rid()]
	var hit := sled.get_world_3d().direct_space_state.intersect_ray(q)
	var on: bool = not hit.is_empty() and (hit.collider as Node).name == "MountainRail"
	if on:
		r.on += dt
		r.from = minf(r.from, p.z)
		r.to = maxf(r.to, p.z)
	r.max_dx = maxf(r.max_dx, absf(p.x - Mountain.RAIL_X))
	r.still = r.still + dt if sled.linear_velocity.length() < 0.2 and r.t > 1.0 else 0.0
	if r.still > 1.0 or r.t > 30.0:
		print("%s: 手すりに乗っていた %.1f 秒、長さ %.1f m（z %.0f〜%.0f）。手すりから横にいちばん離れた %.1f m。止まった z=%.0f" % [sled.kind, r.on,
				maxf(0.0, r.to - r.from), r.from, r.to, r.max_dx, p.z])
		for d in r.rs:
			sled.dismount(d)
			d.queue_free()
		_run = {}


func _climb_step(r: Dictionary, dt: float) -> void:
	var n: int = r.climb
	var p := sled.global_position
	# 押す向き: 頂上（+z）へ、登り道のまんなかへ寄せる
	var dir := Vector3(clampf((Mountain.PATH_X - p.x) * 0.3, -0.5, 0.5), 0, 1).normalized()
	var fwd := -sled.global_basis.z
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := sled.to_global(Vector3(side * sled.HALF.x * 0.8, 0.2, sled.HALF.y))
		sled.push(dir, at)
	var mid: Array = Mountain.section("中腹")
	if r.mid < 0.0 and p.z >= mid[1]:
		r.mid = r.t
	if r.top < 0.0 and p.z >= Mountain.top_z - 10.0:
		r.top = r.t
	r.log += dt
	if r.log >= 30.0:
		r.log = 0.0
		print("  %d 人: %.0f 秒 z=%.0f 高さ %.1f m 速さ %.2f m/s" % [n, r.t, p.z, p.y, sled.linear_velocity.length()])
	if r.top >= 0.0 or r.t > float(args.get("limit", "1500")):
		print("%s を %d 人で押す: 中腹まで %s、頂上まで %s" % [sled.kind, n, _mmss(r.mid), _mmss(r.top)])
		_run = {}


func _mmss(s: float) -> String:
	if s < 0.0:
		return "時間切れ"
	return "%d 分 %02d 秒" % [int(s) / 60, int(s) % 60]
