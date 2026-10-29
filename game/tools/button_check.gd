extends SceneTree
## 雪に縫い留められたボタン（snow_buttons.gd）を、ソリの大きさごとに一回の滑りでいくつ拾えるか測る（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/button_check.gd -- --sled=mid --no-player --bots=0 --no-sound --no-lodge
## ボタンは、頂上の下から +z（ふもと）へ下る幅 12 m・長さ 36 m（z = 9〜45）の帯に、ばらばらに 14 個（間は 3 m 以上）。
## 置き方は 3 通り（種 1・2・3。どのソリも同じ置き方で比べる）。ソリは頂上の少し下（z = 5）から +z へ向け、3 m/s で押し出し、
## 乗る人を席の数だけ乗せて滑り降りる。
## 体重のかけ方:
##   全員   乗っている全員が、前にあるボタンのうち、いちばん少し曲がれば届くものへ向けて、同じ向きに体重をかける
##          （滑り木の間が広いソリは、近い方の滑り木がボタンの上を通るように狙う）
##   一人   一人だけが体重をかけ、ほかの人は何もしない
##   なし   誰も体重をかけない（まっすぐ滑るだけ）
## 出すのは、拾えた数 / 14（置き方 1 / 2 / 3）と、その平均。--trace で 0.5 秒ごとの位置

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const N := 14
const BAND := Vector4(-6.0, 6.0, 9.0, 45.0)   # x の左右、z の始まりと終わり
const SEEDS := [1, 2, 3]
const LOOK := 14.0                              # 狙うのは、この距離 (m) より近いボタン

var args := {}
var main: Node3D
var sled: RigidBody3D
var sb: Node3D
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _results := {}
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


## 置き方 seed_ のボタンの場所（間は 3 m 以上）
func _field(seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var pts := []
	while pts.size() < N:
		var p := Vector3(rng.randf_range(BAND.x, BAND.y), 0, rng.randf_range(BAND.z, BAND.w))
		var ok := true
		for q in pts:
			if (q as Vector3).distance_to(p) < 3.0:
				ok = false
		if ok:
			pts.append(p)
	return pts


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
		var modes := ["全員", "なし"] if sled.SEATS.size() == 1 else ["全員", "一人", "なし"]
		if args.has("only"):
			modes = [args["only"]]
		for mode in modes:
			for sd in SEEDS:
				_queue.append([mode, sd])
	if _run.is_empty():
		if _queue.is_empty():
			_report()
			quit()
			return true
		_start(_queue.pop_front())
		return false
	_step(dt)
	return false


func _start(q: Array) -> void:
	sb.clear()
	for p in _field(q[1]):
		sb.drop_at(p, -1, true)
	sled.reset_to(Vector3(0, main.height(0, 5.0) + 0.3, 5.0))
	sled.rotation.y = PI
	sled.parked = false
	sled.linear_velocity = Vector3(0, 0, 3.0)
	var rs := []
	for i in sled.SEATS.size():
		var d := Node3D.new()
		d.set_script(_dummy)
		d.sled = sled
		main.add_child(d)
		sled.mount(d)
		rs.append(d)
	_run = {"q": q, "rs": rs, "t": 0.0, "still": 0.0, "snip0": sb.stats.snip}


func _step(dt: float) -> void:
	var r := _run
	r.t += dt
	var v := sled.linear_velocity.length()
	var steer := _policy()
	var n_rs: int = r.rs.size()
	for i in n_rs:
		var s := 0.0
		match r.q[0]:
			"全員": s = steer
			"一人": s = steer if i == 0 else 0.0
		sled.lean(s, false)
	if args.has("trace") and Engine.get_physics_frames() % 30 == 0:
		var p := sled.global_position
		print("%s 種%d t=%.1f pos=(%.1f, %.1f) v=%.1f steer=%.2f 拾った=%d" % [r.q[0], r.q[1], r.t, p.x, p.z, v, steer, sb.stats.snip - r.snip0])
	r.still = r.still + dt if v < 0.3 and r.t > 2.0 else 0.0
	if r.still > 1.0 or r.t > 40.0 or sled.global_position.z > BAND.w + 8.0:
		_results["%s|%d" % [r.q[0], r.q[1]]] = sb.stats.snip - r.snip0
		for d in r.rs:
			sled.dismount(d)
			d.queue_free()
		_run = {}


## 前にあるボタンのうち、いちばん少し曲がれば届くものへ向ける体重移動 -1〜1。
## 滑り木の間が広いソリは、近い方の滑り木がボタンの上を通るように狙う
func _policy() -> float:
	var best := INF
	var steer := 0.0
	var gap: bool = sled.RUNNER_X > sb.R + sb.HIT * 0.5 and not sled.kind in sb.BELLY   # 胴の下でも切れるソリは、まんなかで狙う
	for b in sb.buttons.values():
		if b.state != "rest":
			continue
		var lt := sled.to_local(b.at)
		if lt.z > -1.0 or -lt.z > LOOK:
			continue
		var x := lt.x
		if gap:
			x -= signf(x) * sled.RUNNER_X if absf(x) > 0.05 else sled.RUNNER_X
		var ang := atan2(x, -lt.z)
		if absf(ang) < best:
			best = absf(ang)
			steer = clampf(ang * 5.0, -1.0, 1.0)
	return steer


func _report() -> void:
	var rows := ["| ソリ | 乗る人 | 体重のかけ方 | 置き方 1 | 置き方 2 | 置き方 3 | 平均 |", "|---|---|---|---|---|---|---|"]
	for mode in ["全員", "一人", "なし"]:
		if not _results.has("%s|%d" % [mode, SEEDS[0]]):
			continue
		var cells := []
		var sum := 0
		for sd in SEEDS:
			var n: int = _results.get("%s|%d" % [mode, sd], 0)
			cells.append(str(n))
			sum += n
		rows.append("| %s | %d | %s | %s | %.1f |" % [sled.kind, sled.SEATS.size(), mode, " | ".join(cells), float(sum) / SEEDS.size()])
	print("\n".join(rows))
	print("（14 個中の拾えた数）")
