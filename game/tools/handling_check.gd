extends SceneTree
## 乗って滑るときの手ざわりの確かめ用（数字だけ出す）。大きさは main.gd と同じ --sled= で選ぶ。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/handling_check.gd -- --case=<名前> --sled=mid --no-player --bots=0 --no-sound --no-lodge
##
##   --case=run    頂上（2 m。--from=頂上からの距離 で坂の途中からも）から、乗る人 1・2・3・8 人（席があるだけ）で滑り降りる。1.5 m/s までは全員前傾で雪をかき、
##                 あとは何もしない。滑り出してから 5 m/s までの時間、最高速度、止まった所
##   --case=turn   丘から離れた平らな所で、速さを 5 m/s に保ったまま（確かめのため、毎コマ前向きの速さを 5 にそろえる）、
##                 乗る人が体重移動を 1 秒。曲がる角速度と半径。体重移動は 全員 D・一人だけ D・そろわない（D と A が交互）
##   --case=budge  丘から離れた平らな所の、止まったソリを一人で押す（大きさごとの「止まっているときの動かしやすさ」）。
##                 後ろの角を横へ押して向きが 90° 変わるまでの時間と、長い辺のまんなかを横へ押して 1 m ずれるまでの時間
##   --case=follow （--no-player なしで --bots=2 --sled=large など）あなたと仲間が乗り、5 m/s で あなただけ D を 1 秒。
##                 仲間が合わせる（--bot-lean=follow）か、合わせない（--bot-lean=off）かで角速度を比べる

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const SPEED := 5.0

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


func _clear(rs: Array) -> void:
	for d in rs:
		sled.dismount(d)
		d.queue_free()


func _counts() -> Array:
	return [1, 2, 3, 8].filter(func(n): return n <= sled.SEATS.size())


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null:
		return false
	sled = main.sled
	match args.get("case", "run"):
		"run":
			_run_case(dt)
		"turn":
			_turn_case(dt)
		"follow":
			_follow_case(dt)
		"budge":
			_budge_case(dt)
	if t > float(args.get("secs", "900")):
		print("時間切れ")
		quit()
	return false


# ---------------------------------------------------------------- 滑り降りる

func _run_case(dt: float) -> void:
	if not _started:
		if t < 0.5:
			return
		_started = true
		for n in _counts():
			_queue.append(n)
		_rows.append("| ソリ | 乗る人 | 3 m/s まで | 5 m/s まで | 自分の最高速度の 9 割まで | 最高速度 | 止まった所（頂上から） |")
		_rows.append("|---|---|---|---|---|---|---|")
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return
		var n: int = _queue.pop_front()
		var from := float(args.get("from", "2"))
		sled.reset_to(Vector3(0, main.height(0, from) + 0.3, from))
		sled.rotation.y = PI
		sled.parked = false
		_run = {"n": n, "rs": _riders(n), "t": 0.0, "t3": -1.0, "t5": -1.0, "max": 0.0, "still": 0.0, "go": false, "vs": []}
		return
	var r := _run
	var v := sled.linear_velocity.length()
	r.t += dt
	if not r.go:
		for d in r.rs:
			sled.lean(0.0, true)
		r.go = r.t > 0.3 and v >= 1.5   # 置き直した直後のコマは速さが残っていることがあるので、少し待ってから見る
	r.max = maxf(r.max, v)
	if r.t3 < 0.0 and v >= 3.0:
		r.t3 = r.t
	if r.t5 < 0.0 and v >= 5.0:
		r.t5 = r.t
	r.vs.append(v)
	r.still = r.still + dt if v < 0.2 and r.t > 2.0 else 0.0
	var p := sled.global_position
	var top := Vector2(p.x, p.z).length()
	if r.still > 1.0 or r.t > 60.0:
		# 自分の最高速度の 9 割に届くまで
		var t90 := -1.0
		for i in r.vs.size():
			if r.vs[i] >= 0.9 * r.max:
				t90 = i * dt
				break
		_rows.append("| %s | %d | %s | %s | %.1f 秒 | %.1f m/s | %.0f m |" % [sled.kind, r.n, ("%.1f 秒" % r.t3) if r.t3 >= 0.0 else "届かない",
				("%.1f 秒" % r.t5) if r.t5 >= 0.0 else "届かない", t90, r.max, top])
		_clear(r.rs)
		_run = {}


# ---------------------------------------------------------------- 曲がる

## 体重移動の組み合わせ: 一人ひとりの A/D（1 が D）
func _pattern(name: String, n: int) -> Array:
	var out := []
	for i in n:
		match name:
			"all":
				out.append(1.0)
			"one":
				out.append(1.0 if i == 0 else 0.0)
			"mixed":
				out.append(1.0 if i % 2 == 0 else -1.0)
	return out


func _hold_speed() -> void:
	var f := -sled.global_basis.z
	f.y = 0
	f = f.normalized()
	sled.linear_velocity = f * SPEED + Vector3(0, sled.linear_velocity.y, 0)


func _turn_case(dt: float) -> void:
	if not _started:
		if t < 0.5:
			return
		_started = true
		for n in _counts():
			for pat in ["all", "one", "mixed"]:
				if pat != "all" and n == 1:
					continue
				_queue.append([n, pat])
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return
		var q: Array = _queue.pop_front()
		sled.reset_to(Vector3(90, main.height(90, 0) + 0.3, 0))
		sled.parked = false
		_run = {"n": q[0], "pat": q[1], "rs": _riders(q[0]), "t": 0.0, "yaw0": 0.0, "phase": 0}
		return
	var r := _run
	r.t += dt
	_hold_speed()
	if r.phase == 0 and r.t > 0.8:
		r.phase = 1
		r.t = 0.0
		r.yaw0 = sled.rotation.y
	if r.phase == 1:
		for s in _pattern(r.pat, r.n):
			sled.lean(s, false)
		if r.t >= 1.0:
			var deg: float = absf(rad_to_deg(wrapf(sled.rotation.y - r.yaw0, -PI, PI)))
			var w: float = deg / r.t
			var rad := SPEED / deg_to_rad(w) if w > 0.05 else INF
			var label: String = {"all": "全員 D", "one": "一人だけ D", "mixed": "そろわない（D・A 交互）"}[r.pat]
			_rows.append("| %s | %d | %s | %.1f °/s | %s |" % [sled.kind, r.n, label, w, ("%.0f m" % rad) if rad < 9999.0 else "曲がらない"])
			_clear(r.rs)
			_run = {}


# ---------------------------------------------------------------- 仲間が合わせる

func _follow_case(dt: float) -> void:
	var p = main.player
	var bots := main.get_children().filter(func(c): return c.get_script() == main.Bot)
	if p == null:
		print("--no-player なしで使う")
		quit()
		return
	if _run.is_empty() and t > 1.0:
		sled.reset_to(Vector3(90, main.height(90, 0) + 0.3, 0))
		sled.parked = false
		p.global_position = sled.global_position + sled.global_basis.x * 1.5
		p.get_on()
		for b in bots:
			b.seat = sled.mount(b)
			if b.seat != Vector3.INF:
				b._col.disabled = true
				b.state = b.State.RIDE
		_run = {"t": 0.0, "phase": 0, "yaw0": 0.0}
		return
	if _run.is_empty():
		return
	var r := _run
	r.t += dt
	_hold_speed()
	if r.phase == 0 and r.t > 0.8:
		r.phase = 1
		r.t = 0.0
		r.yaw0 = sled.rotation.y
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_D
		ev.pressed = true
		Input.parse_input_event(ev)
	elif r.phase == 1 and r.t >= 1.0:
		var deg: float = absf(rad_to_deg(wrapf(sled.rotation.y - r.yaw0, -PI, PI)))
		print("結果: %s に あなた＋仲間 %d 人（仲間 %s）、あなただけ D 1 秒で %.1f °/s（半径 %.0f m）" % [sled.kind, sled.riders.size() - 1,
				args.get("bot-lean", "follow"), deg, SPEED / deg_to_rad(maxf(deg, 0.01))])
		quit()


# ---------------------------------------------------------------- 止まったソリを一人で押す

func _budge_case(dt: float) -> void:
	if not _started:
		if t < 0.5:
			return
		_started = true
		_queue = ["turn", "side"]
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return
		var what: String = _queue.pop_front()
		sled.reset_to(Vector3(90, main.height(90, 0) + 0.3, 0))
		_run = {"what": what, "t": 0.0, "go": -1.0, "yaw0": 0.0, "p0": Vector3.ZERO, "who": Node3D.new()}
		return
	var r := _run
	r.t += dt
	if r.go < 0.0:
		if r.t > 1.0:   # 雪に落ち着くのを待つ
			r.go = r.t
			r.yaw0 = sled.rotation.y
			r.p0 = sled.global_position
		return
	var el: float = r.t - r.go
	var side := sled.global_basis.x
	var done := false
	if r.what == "turn":
		# 後ろの右の角を、ソリの左へ押す（向きが変わる。押す向きは毎コマ、ソリに合わせる）
		sled.push(-side, sled.to_global(Vector3(sled.HALF.x, 0.2, sled.HALF.y)), r.who)
		done = absf(wrapf(sled.rotation.y - r.yaw0, -PI, PI)) >= PI / 2
	else:
		# 長い辺のまんなかを、ソリの左へ押す（横にずれる）
		sled.push(-side, sled.to_global(Vector3(sled.HALF.x, 0.2, 0)), r.who)
		done = absf((sled.global_position - r.p0).dot(side)) >= 1.0
	if done or el > 60.0:
		var label := "90° 向きを変える（後ろの角を押す）" if r.what == "turn" else "横に 1 m ずらす（長い辺のまんなかを押す）"
		_rows.append("| %s | %s | %s |" % [sled.kind, label, ("%.1f 秒" % el) if done else "60 秒で届かない"])
		r.who.free()
		_run = {}
