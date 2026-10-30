extends SceneTree
## 乗り物・山・標高の倍率（snow_buttons.gd の RIDE_RATE・CREW_BONUS・MAP_RATE・ALT_RATE）で、一人あたりの取り分を測る（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/pay_rate_check.gd -- --sled=KIND --map=hill|mountain --no-player --bots=0 --no-sound
##   --case=ride（既定） 頂上から 2 m/s で押し出して滑る。乗る人は、米袋 1（漕がない・1 秒に 10 回漕ぐ）、小 1・2、中 1・3、大 1・8。
##                      はじめから乗っていた一人の取り分（倍率と人数のおまけを掛けたあと。端数こみ）を出す
##                      --from=mid で大きな山の中腹（の上の端）から。--buttons で、滑る前に斜面のボタンをその山の数（MAP_MAX）まで置き、
##                      拾った値打ち（倍率を掛けたあとの、一人の分）も出す。--reps=N で N 回ずつ滑って平均する
##   --case=climb       丘の溝の底（頂上から 58 m）から、--pushers 人が後ろから押して頂上まで登る時間（大きな山は mountain_check.gd の climb）
##   --case=spots       置き場所を 2000 か所選んで（_pick_spot）、1 個の値打ちの見込み（段の出やすさ × 場所の倍率）を、山と高さの帯ごとに出す
##   --case=walk        歩いて裁ちばさみで取って回る（--secs 秒）。ボタンは自然に降らせ、いちばん近い休んでいるボタンへ走って（3.4 m/s。
##                      坂で遅くならない、上の見積もり）、着いたら 1.25 秒止まって切る。値打ちは ×1.0 のまま（倍率なし）。--band=top|low で大きな山の中腹より上・下だけを回る
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
var _slope := 0.0     # 拾った斜面のボタンの値打ち（一人の分）
var _snips := 0
var _slope_exp := 0.0 # 拾った斜面のボタンの、値打ちの見込み（段の出やすさで均した。螺鈿のくじ運をならす）
var _sums := {}       # 何回ずつ滑ったぶんの合計


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
				_paid = ev
			elif ev.kind == "share" and not _run.is_empty() and not _run.has("climb"):
				_slope += float(ev.get("value", 0.0))
				_slope_exp += ev_at(ev.at) * float(main.snow_buttons.RIDE_RATE.get(sled.kind, 1.0))
				_snips += 1)
		var reps := int(args.get("reps", "1"))
		if args.get("case", "ride") == "climb":
			_queue.append({"climb": int(args.get("pushers", "1"))})
		elif args.get("case", "ride") == "spots":
			_spots()
			quit()
			return true
		elif args.get("case", "ride") == "walk":
			_queue.append({"walk": float(args.get("secs", "300"))})
		elif sled.kind == "sack":
			for i in reps:
				_queue.append({"n": 1, "mash": 0})
			for i in reps:
				_queue.append({"n": 1, "mash": 10})
		else:
			for i in reps:
				_queue.append({"n": 1, "mash": 0})
			for i in reps:
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
	elif _run.has("walk"):
		_walk(dt)
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
	var sb = main.snow_buttons
	if q.has("walk"):
		sb.auto = true
		for m in sb._burst:   # 始まりにまとめて降る分は数えない（降り続けるときの 1 分あたり）
			sb._burst[m] = 0
		var p0 := Vector3(Mountain.COURSE_X, 0, Mountain.section("中腹")[1]) if _mountain() else Vector3(0, 0, 20.0)
		_run = q.merged({"t": 0.0, "p": p0, "goal": -1, "wait": 0.0, "got": 0.0, "exp": 0.0, "n": 0})
		return
	var at := Vector3(0, 0, 3.0)
	var fwd := Vector3(0, 0, 1)
	if _mountain():
		at = Vector3(Mountain.COURSE_X, 0, Mountain.section("中腹" if args.get("from", "top") == "mid" else "頂上")[1 if args.get("from", "top") != "mid" else 0] + (1.0 if args.get("from", "top") != "mid" else -1.0))
		fwd = Vector3(0, 0, -1)
	sb.clear()
	if args.has("buttons"):
		var m := "mountain" if _mountain() else "hill"
		for i in 200:
			if sb._live(m) >= int(sb.MAP_MAX[m]):
				break
			var bp: Vector3 = sb._pick_spot(m)
			if bp != Vector3.INF:
				sb.drop_at(bp, -1, true)
	_slope = 0.0
	_slope_exp = 0.0
	_snips = 0
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
		var key := "%d_%d" % [r.n, r.mash]
		var sm: Dictionary = _sums.get(key, {"k": 0, "dist": 0.0, "t": 0.0, "acc": 0.0, "slope": 0.0, "slope_exp": 0.0, "snips": 0, "wood": 0, "brass": 0, "best": 0.0})
		sm.k += 1
		sm.dist += float(p.get("dist", 0.0))
		sm.t += r.t
		sm.acc += float(p.get("acc", 0.0))
		sm.slope += _slope
		sm.slope_exp += _slope_exp
		sm.snips += _snips
		sm.wood += int(p.get("wood", 0))
		sm.brass += int(p.get("brass", 0))
		sm.best += r.best
		_sums[key] = sm
		if int(sm.k) == int(args.get("reps", "1")):
			var k := float(sm.k)
			_rows.append("| %s%s | %s | %d | %s | %.0f m | %.0f 秒 | %.1f m/s | 木 %.1f・真鍮 %.1f | ×%.2f | %.1f | %.1f 個 → %.1f（見込み %.1f） |" % [
					args.get("map", "hill"), "（中腹から）" if args.get("from", "") == "mid" else "", sled.kind, r.n,
					("1 秒に %d 回" % r.mash) if r.mash > 0 else "—", sm.dist / k, sm.t / k, sm.best / k, sm.wood / k, sm.brass / k,
					mult, sm.acc / k, sm.snips / k, sm.slope / k, sm.slope_exp / k])
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


## 歩いて裁ちばさみで取って回る: いちばん近い休んでいるボタンへ走り、着いたら止まって切る（はさみの出し入れの間。snow_buttons.gd の SHEAR_END）
func _walk(dt: float) -> void:
	var r := _run
	var sb = main.snow_buttons
	r.t += dt
	if r.t > float(r.walk):
		_rows.append("| %s%s | 歩き | %.0f 秒 | %d 個 | %.1f（見込み %.1f） | %.1f / 分（見込み %.1f / 分） |" % [args.get("map", "hill"),
				{"top": "（中腹より上）", "low": "（中腹より下）"}.get(args.get("band", ""), ""), r.t, r.n, r.got, r.exp,
				r.got / r.t * 60.0, r.exp / r.t * 60.0])
		_run = {}
		return
	if r.wait > 0.0:
		r.wait -= dt
		if r.wait <= 0.0:
			var b = sb.buttons.get(int(r.goal))
			if b != null and b.state == "rest":
				r.got += float(sb.TIERS[b.tier].value)   # 歩きは ×1.0 のまま
				r.exp += ev_at(b.at) / sb.place_rate(b.at)
				r.n += 1
				b.root.queue_free()
				sb.buttons.erase(int(r.goal))
			r.goal = -1
		return
	var b = sb.buttons.get(int(r.goal))
	if b == null or b.state != "rest":
		r.goal = -1
		var bd := INF
		var mid_z: float = Mountain.section("中腹")[1]
		for c in sb.buttons.values():
			if c.state != "rest" or sb.map_of(c.at) != ("mountain" if _mountain() else "hill"):
				continue
			if args.get("band", "") == "top" and c.at.z < mid_z or args.get("band", "") == "low" and c.at.z >= mid_z:
				continue
			var d := Vector2(c.at.x - r.p.x, c.at.z - r.p.z).length()
			if d < bd:
				bd = d
				r.goal = c.id
		return
	var to := Vector2(b.at.x - r.p.x, b.at.z - r.p.z)
	if to.length() <= sb.SHEAR_REACH * 0.8:
		r.wait = sb.SHEAR_END / 12.0
		return
	var step := to.normalized() * minf(to.length(), 3.4 * dt)
	r.p += Vector3(step.x, 0, step.y)


func _spots() -> void:
	var sb = main.snow_buttons
	for m in ["hill", "mountain"]:
		var bands := {}
		for i in 2000:
			var p: Vector3 = sb._pick_spot(m)
			if p == Vector3.INF:
				continue
			var at: Vector3 = sb._on_snow(p)
			var rare: float = sb.rare_at(at)
			var ev := 0.0
			var up := 0.0
			for k in range(1, sb.TIERS.size()):
				ev += float(sb.TIERS[k].chance) * rare * float(sb.TIERS[k].value)
				up += float(sb.TIERS[k].chance) * rare
			ev += (1.0 - up) * 1.0
			var band := int(at.y / 15.0) * 15
			var bd: Dictionary = bands.get(band, {"n": 0, "ev": 0.0, "rate": 0.0, "evr": 0.0, "up": 0.0})
			bd.n += 1
			bd.ev += ev
			bd.rate += sb.place_rate(at)
			bd.evr += ev * sb.place_rate(at)
			bd.up += up
			bands[band] = bd
		var keys := bands.keys()
		keys.sort()
		var all := {"n": 0, "evr": 0.0}
		for k in keys:
			var bd: Dictionary = bands[k]
			var n := float(bd.n)
			all.n += bd.n
			all.evr += bd.evr
			_rows.append("| %s | %d〜%d m | %.0f%% | 上の素材 %.1f%% | 段の見込み %.2f | 場所 ×%.2f | 1 個 %.2f |" % [m, k, k + 15, n / 20.0, bd.up / n * 100.0,
					bd.ev / n, bd.rate / n, bd.evr / n])
		_rows.append("| %s | 全体 | | | | | 1 個 %.2f |" % [m, all.evr / float(all.n)])
	print("\n".join(_rows))


## 置き場所 at（雪の上）に降るボタン 1 個の、値打ちの見込み（段の出やすさ × 段の値打ち × 場所の倍率）
func ev_at(at: Vector3) -> float:
	var sb = main.snow_buttons
	var rare: float = sb.rare_at(at)
	var ev := 0.0
	var up := 0.0
	for k in range(1, sb.TIERS.size()):
		ev += float(sb.TIERS[k].chance) * rare * float(sb.TIERS[k].value)
		up += float(sb.TIERS[k].chance) * rare
	return (ev + 1.0 - up) * sb.place_rate(at)
