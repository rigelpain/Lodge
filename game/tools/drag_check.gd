extends SceneTree
## ずり落ちと引きずりの確かめ用（数字だけ出す）。大きさは main.gd と同じ --sled= で選ぶ。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/drag_check.gd -- --case=<名前> --sled=mid --no-player --bots=0 --no-sound
##
##   --case=slide     誰も触れていない空のソリと、一人乗ったソリを、坂の途中（--from=頂上からの距離、既定 8 と 35）から放す。
##                    速さの最高と平均、止まった所を出す
##   --case=drag      頂上の近くから滑り出したソリ（乗る人 0〜3。空のソリは --from-empty=8 から放す）を、
##                    頂上から --at=15 m の所で、止める人 1〜3 人がつかむ。止まるまでの距離と時間、止まらなければ手が離れた距離
##   --case=snowball  （--no-player なしで --bots=1）あなたと仲間がソリをつかみ、互いに雪玉を当てる。手が離れるか、ソリがずり落ちるか
##   --case=shot      （画面あり、--bots=N が乗る）一人称で引きずられている場面を撮る。--out=絵.png（main.gd の --shot とは別）

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
var slipped := false
func let_go() -> void:
	slipped = true
	sled.release_handle(self)
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sled: RigidBody3D
var t := 0.0
var _dummy: GDScript
var _queue: Array = []        # 残りの試し: [乗る人, 止める人]
var _run := {}                # いまの試し
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


func _make_dummy() -> Node3D:
	var d := Node3D.new()
	d.set_script(_dummy)
	d.sled = sled
	main.add_child(d)
	return d


## 頂上から +Z（ふもと）へ r m の雪面。ソリの前（-Z）がふもとを向くよう回転 PI で置く
func _place(r: float) -> void:
	for who in sled.holders.keys():
		sled.release_handle(who)
	sled.reset_to(Vector3(0, main.height(0, r) + 0.3, r))
	sled.rotation.y = PI
	sled.parked = false


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null:
		return false
	sled = main.sled
	match args.get("case", "slide"):
		"slide":
			_slide(dt)
		"drag":
			_drag(dt)
		"snowball":
			_snowball(dt)
		"shot":
			_shot(dt)
	if t > float(args.get("secs", "900")):
		print("時間切れ")
		quit()
	return false


# ---------------------------------------------------------------- ずり落ち

func _slide(dt: float) -> void:
	if not _started:
		if t < 0.5:
			return
		_started = true
		for from in args.get("from", "8,35").split(","):
			for riders in [0, 1]:
				_queue.append([float(from), riders])
		_rows.append("| 放す所（頂上から） | 乗る人 | 最高の速さ | 最初の 10 秒の平均 | 止まった所（頂上から） | 止まるまで |")
		_rows.append("|---|---|---|---|---|---|")
	if _run.is_empty():
		if _queue.is_empty():
			_finish()
			return
		var q: Array = _queue.pop_front()
		_place(q[0])
		var rs: Array = []
		for i in q[1]:
			var d := _make_dummy()
			sled.mount(d)
			rs.append(d)
		_run = {"from": q[0], "riders": q[1], "t": 0.0, "max": 0.0, "sum": 0.0, "n": 0, "still": 0.0, "rs": rs}
		return
	var r := _run
	r.t += dt
	var v := sled.linear_velocity.length()
	r.max = maxf(r.max, v)
	if r.t <= 10.0:
		r.sum += v
		r.n += 1
	r.still = r.still + dt if v < 0.05 and r.t > 1.0 else 0.0
	var p := sled.global_position
	var top := Vector2(p.x, p.z).length()
	if r.still > 1.0 or r.t > 60.0 or top > 110.0:
		var where := "%.0f m" % top if r.still > 1.0 else "止まらない（%.0f 秒で %.0f m まで）" % [r.t, top]
		_rows.append("| %.0f m | %d | %.1f m/s | %.1f m/s | %s | %s |" % [r.from, r.riders, r.max, r.sum / maxi(r.n, 1), where,
				("%.0f 秒" % (r.t - 1.0)) if r.still > 1.0 else "—"])
		for d in r.rs:
			sled.dismount(d)
			d.queue_free()
		_run = {}


# ---------------------------------------------------------------- 引きずって止める

func _drag(dt: float) -> void:
	if not _started:
		if t < 0.5:
			return
		_started = true
		var seats: int = sled.SEATS.size()
		for riders in range(0, 4):
			for stoppers in range(1, 4):
				_queue.append([riders, stoppers, riders > seats])
		_rows.append("| ソリ | 乗る人 | 止める人 | つかんだ時の速さ | 結果 | 引きずられた距離 | 時間 |")
		_rows.append("|---|---|---|---|---|---|---|")
	if _run.is_empty():
		if _queue.is_empty():
			_finish()
			return
		var q: Array = _queue.pop_front()
		if q[2]:
			_rows.append("| %s | %d | %d | — | 乗れない（席 %d） | — | — |" % [sled.kind, q[0], q[1], sled.SEATS.size()])
			return
		var start: float = 2.0 if q[0] > 0 else float(args.get("from-empty", "8"))
		_place(start)
		var rs: Array = []
		for i in q[0]:
			var d := _make_dummy()
			sled.mount(d)
			rs.append(d)
		_run = {"riders": q[0], "stoppers": q[1], "phase": 0, "t": 0.0, "rs": rs, "ss": [], "still": 0.0, "v0": 0.0,
				"dist": 0.0, "last": sled.global_position}
		return
	var r := _run
	var v := sled.linear_velocity.length()
	var p := sled.global_position
	var top := Vector2(p.x, p.z).length()
	if r.phase == 0:
		# 滑り出す: 乗っていれば前傾して雪をかく（仲間と同じ）
		if r.riders > 0:
			sled.lean(0.0, true)
		r.t += dt
		if top >= float(args.get("at", "15")):
			r.phase = 1
			r.t = 0.0
			r.v0 = v
			r.last = p
			# 止める人: 後ろの両角と、後ろのまんなか
			var hx: float = sled.HALF.x + sled.STAND
			var hz: float = sled.HALF.y
			var spots := [Vector3(hx, 0, hz * 0.6), Vector3(-hx, 0, hz * 0.6), Vector3(0, 0, hz + sled.STAND)]
			for i in r.stoppers:
				var d := _make_dummy()
				sled.take_handle(d, spots[i])
				d.global_position = sled.to_global(spots[i])
				r.ss.append(d)
		elif r.t > 40.0:
			_rows.append("| %s | %d | %d | — | 滑り出さない | — | — |" % [sled.kind, r.riders, r.stoppers])
			_end_run()
		return
	r.t += dt
	r.dist += p.distance_to(r.last)
	r.last = p
	for d in r.ss:
		if not d.slipped:
			d.global_position = sled.to_global(sled.holders[d])
	var holding: int = r.ss.filter(func(d): return not d.slipped).size()
	r.still = r.still + dt if v < 0.1 else 0.0
	if r.still > 0.5 and holding > 0:
		_rows.append("| %s | %d | %d | %.1f m/s | 止まる | %.1f m | %.1f 秒 |" % [sled.kind, r.riders, r.stoppers, r.v0, r.dist, r.t - 0.5])
		_end_run()
	elif holding == 0:
		_rows.append("| %s | %d | %d | %.1f m/s | 止まらない（手が離れる） | %.1f m | %.1f 秒 |" % [sled.kind, r.riders, r.stoppers, r.v0, r.dist, r.t])
		_end_run()
	elif r.t > 30.0:
		_rows.append("| %s | %d | %d | %.1f m/s | 止まらない（30 秒たっても） | %.1f m | — |" % [sled.kind, r.riders, r.stoppers, r.v0, r.dist])
		_end_run()


func _end_run() -> void:
	for d in _run.ss + _run.rs:
		if sled.holders.has(d):
			sled.release_handle(d)
		sled.dismount(d)
		d.queue_free()
	_run = {}


# ---------------------------------------------------------------- 雪玉

func _throw_at(from: Node3D, to: Node3D) -> void:
	var o: Vector3 = from.global_position + Vector3.UP * 1.3
	var aim: Vector3 = to.global_position + Vector3.UP * 0.9
	var d := aim - o
	var flat := Vector2(d.x, d.z).length()
	var tt := flat / 10.0
	var vel := Vector3(d.x, 0, d.z).normalized() * 10.0 + Vector3.UP * (d.y / tt + 0.5 * 9.8 * tt)
	main.emotes.send({"kind": "throw", "who": from.id, "origin": o, "velocity": vel})


func _snowball(dt: float) -> void:
	var p = main.player
	var bots := main.get_children().filter(func(c): return c.get_script() == main.Bot)
	if p == null or bots.is_empty():
		print("--bots=1 で、--no-player なしで使う")
		quit()
		return
	var b = bots[0]
	if _run.is_empty() and t > 1.0:
		# ソリは前を頂上へ向けて置き、あなたは前の縁（坂の上側）でつかむ。仲間は自分で後ろの角をつかみに行く。
		# 手が離れたあと、あなたの体がずり落ちるソリの邪魔をしないように、坂の上側に立つ
		sled.reset_to(Vector3(0, main.height(0, 20) + 0.3, 20))
		p.global_position = sled.to_global(Vector3(0.5, 0, -sled.HALF.y - sled.STAND)) + Vector3.UP * 0.2
		p.rotation.y = PI
		p.grab()
		_run = {"phase": 0, "t": 0.0, "z0": 0.0}
		print("あなた=%s 仲間がつかむまで待つ" % ["歩く", "つかむ", "乗る", "紐"][p.mode])
		return
	if _run.is_empty():
		return
	var r := _run
	r.t += dt
	match r.phase:
		0:
			if b.handle != Vector3.INF and r.t > 2.0:
				print("仲間もつかんだ。ソリは留まっている: 速さ %.2f m/s、つかんでいる人 %d" % [sled.linear_velocity.length(), sled.holders.size()])
				# 仲間をソリから離して、あなたへ雪玉を投げさせる（まず仲間を待たせる: 手を離したらすぐつかみ直さない）
				b.let_go()
				b._regrab = 99.0
				b.global_position = sled.to_global(Vector3(4.5, 0, 0)) + Vector3.UP * 0.3
				r.phase = 1
				r.t = 0.0
		1:
			if r.t > 0.5 and not r.has("thrown"):
				r.thrown = true
				_throw_at(b, p)
			if r.t > 0.5 and p.mode != p.Mode.GRIP:
				print("雪玉が当たって、あなたの手が離れた（%.2f 秒後）。ソリの速さ %.2f m/s" % [r.t - 0.5, sled.linear_velocity.length()])
				r.phase = 2
				r.t = 0.0
				r.z0 = sled.global_position.z
			elif r.t > 4.0:
				print("あなた: 4 秒たっても手が離れない（当たらなかった？） mode=%d" % p.mode)
				quit()
		2:
			if r.t >= 3.0 and not r.has("slid"):
				r.slid = true
				print("手が離れて 3 秒: ソリは %.2f m ずり落ちた（速さ %.2f m/s）。F でつかみ直す" % [sled.global_position.z - r.z0, sled.linear_velocity.length()])
				p.global_position = sled.to_global(Vector3(0.5, 0, -sled.HALF.y - sled.STAND)) + Vector3.UP * 0.2
				p.grab()
			if r.has("slid") and r.t >= 5.0:
				print("つかみ直して 2 秒: 速さ %.2f m/s（つかんでいる=%s）" % [sled.linear_velocity.length(), str(p.mode == p.Mode.GRIP)])
				# こんどは仲間がつかんで、あなたが当てる
				b._regrab = 0.0
				r.phase = 3
				r.t = 0.0
		3:
			if b.handle != Vector3.INF and not r.has("thrown2") and r.t > 1.0:
				r.thrown2 = true
				p.let_go()
				var bh: Vector3 = sled.holders[b]
				p.global_position = sled.to_global(Vector3(signf(bh.x) * 5.0, 0, bh.z)) + Vector3.UP * 0.3
				r.t2 = r.t
				_throw_at(p, b)
			if r.has("thrown2") and b.handle == Vector3.INF and not r.has("bot_off"):
				r.bot_off = r.t
				print("雪玉が当たって、仲間の手が離れた（%.2f 秒後）。%.1f 秒たつとつかみ直しに行く" % [r.t - r.t2, b.REGRAB_WAIT])
			if r.has("bot_off") and b.handle != Vector3.INF:
				print("仲間がつかみ直した（手が離れて %.1f 秒後）。速さ %.2f m/s" % [r.t - r.bot_off, sled.linear_velocity.length()])
				quit()
			elif r.t > 12.0:
				print("仲間: 手が離れない handle=%s" % str(b.handle))
				quit()


# ---------------------------------------------------------------- 一人称の絵

func _shot(dt: float) -> void:
	var p = main.player
	if _run.is_empty() and t > 1.0:
		_place(2.0)
		# 乗る人は仲間（--bots=N）。見える人形で座らせる
		for b in main.get_children().filter(func(c): return c.get_script() == main.Bot):
			b.seat = sled.mount(b)
			if b.seat != Vector3.INF:
				b._col.disabled = true
				b.state = b.State.RIDE
		_run = {"phase": 0, "t": 0.0}
		p.global_position = sled.to_global(Vector3(0, 0, 3.5))
		return
	if _run.is_empty():
		return
	var r := _run
	r.t += dt
	var top := Vector2(sled.global_position.x, sled.global_position.z).length()
	if r.phase == 0:
		sled.lean(0.0, true)
		# あなたはソリの後ろについて行き、頂上から 15 m でつかむ
		p.global_position = sled.to_global(Vector3(0, 0, sled.HALF.y + sled.STAND + 0.5)) + Vector3.UP * 0.1
		p.rotation.y = sled.rotation.y
		if top >= float(args.get("at", "15")):
			p.grab()
			p._snap = 1.0
			p._pitch = float(args.get("pitch", "-0.45"))   # 足もとの雪とソリが見えるよう、少し下を見る
			if args.has("side"):
				# 横から見る（人形の姿勢を見る用）。ソリの横 4 m から、つかんでいる人を見る
				var c := Camera3D.new()
				c.fov = 55
				c.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4)   # 体は映し、一人称の手は映さない
				main.add_child(c)
				c.make_current()
				r.cam = c
			r.phase = 1
			r.t = 0.0
			print("つかんだ: 速さ %.1f m/s 引きずられている=%s" % [sled.linear_velocity.length(), str(sled.is_dragged(p))])
	if r.has("cam"):
		var at: Vector3 = p.global_position + Vector3.UP * 0.8
		r.cam.global_position = at + sled.global_basis.x * 4.2 + sled.global_basis.z * 1.0 + Vector3.UP * 0.6
		r.cam.look_at(at - sled.global_basis.z * 0.8, Vector3.UP)
	if r.phase == 1 and r.t > float(args.get("shot-after", "0.8")):
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(args.get("out", "/tmp/drag.png"))
		print("保存: ", args.get("out", "/tmp/drag.png"), " 速さ %.1f m/s 引きずられている=%s" % [sled.linear_velocity.length(), str(sled.is_dragged(p))])
		quit()


func _finish() -> void:
	print("\n".join(_rows))
	quit()
