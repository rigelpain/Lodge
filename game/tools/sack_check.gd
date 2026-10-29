extends SceneTree
## 米袋の足漕ぎと、逃げていくソリに追いついて止める確かめ用（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sack_check.gd -- --case=<名前> [main.gd の引数]
##
##   --case=mash   （--sled=sack --no-player --bots=0）頂上（2 m）から乗って、1 秒に --rates=0,4,6,8,10 回蹴り続ける。
##                 最高速度と、ふもと（頂上から 55 m）までの時間。--sled=mid・large で同じ道を蹴らずに滑った値も出せる
##   --case=chase  （--bots=0、--sled=逃げるソリ）頂上から 15 m で止まっていたソリが、手を離れて滑り出す。
##                 --delay 秒あとに、あなたが追いかける: --by=foot は走って（Shift+W）、--by=sack は米袋に乗って 1 秒に --rate 回蹴る。
##                 つかめる所まで来たら F。追いつくまでの時間と、そこまでにソリが滑った距離、止まったか
##   --case=shot   （画面あり、--bots=0）米袋に乗って 1 秒に 8 回蹴りながら滑るのを、横から撮る。--out=絵.png、--shot-after=秒

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const Sled := preload("res://sled.gd")
const FOOT := 55.0          # ふもと（頂上からの距離, m）

var args := {}
var main: Node3D
var sled: RigidBody3D
var t := 0.0
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _rows: Array[String] = []
var _started := false
var _keys := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()


func _key(k: Key, on: bool) -> void:
	if _keys.get(k, false) == on and k != KEY_SPACE and k != KEY_F:
		return
	_keys[k] = on
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)


func _tap(k: Key) -> void:
	_key(k, true)
	_key(k, false)


func _top(n: Node3D) -> float:
	return Vector2(n.global_position.x, n.global_position.z).length()


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null:
		return false
	sled = main.sled
	match args.get("case", "mash"):
		"mash":
			_mash(dt)
		"chase":
			_chase(dt)
		"shot":
			_shot(dt)
	if t > float(args.get("secs", "900")):
		print("時間切れ")
		quit()
	return false


# ---------------------------------------------------------------- 連打

func _mash(dt: float) -> void:
	if not _started:
		if t < 0.5:
			return
		_started = true
		for r in args.get("rates", "0,4,6,8,10").split(","):
			_queue.append(float(r))
		_rows.append("| ソリ | 1 秒に蹴る回数 | 最高速度 | ふもと（55 m）まで |")
		_rows.append("|---|---|---|---|")
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return
		var rate: float = _queue.pop_front()
		sled.reset_to(Vector3(0, main.height(0, 2) + 0.3, 2))
		sled.rotation.y = PI
		sled.parked = false
		var d := Node3D.new()
		d.set_script(_dummy)
		d.sled = sled
		main.add_child(d)
		sled.mount(d)
		_run = {"rate": rate, "rider": d, "t": 0.0, "go": false, "next": 0.0, "max": 0.0, "foot": -1.0, "kicks": 0}
		return
	var r := _run
	r.t += dt
	var v := sled.linear_velocity.length()
	if not r.go:
		sled.lean(0.0, true)   # 滑り出しは雪をかく
		r.go = r.t > 0.3 and v >= 1.5
	elif r.rate > 0.0:
		r.next -= dt
		if r.next <= 0.0:
			r.next += 1.0 / r.rate
			if sled.kick(r.rider):
				r.kicks += 1
	r.max = maxf(r.max, v)
	if r.foot < 0.0 and _top(sled) >= FOOT:
		r.foot = r.t
	if r.foot >= 0.0 or r.t > 60.0:
		_rows.append("| %s | %s | %.1f m/s | %s |" % [sled.kind, ("%d 回" % r.rate) if r.rate > 0.0 else "蹴らない",
				r.max, ("%.1f 秒" % r.foot) if r.foot >= 0.0 else "60 秒で届かない"])
		sled.dismount(r.rider)
		r.rider.queue_free()
		_run = {}


# ---------------------------------------------------------------- 追いかける

func _chase(dt: float) -> void:
	var p = main.player
	if p == null:
		print("--no-player なしで使う")
		quit()
		return
	if _run.is_empty():
		if t < 1.0:
			return
		# 逃げるソリを頂上から 15 m に置いて放す（みんなで押していたソリから、手が離れた）
		sled.reset_to(Vector3(0, main.height(0, 15) + 0.3, 15))
		sled.rotation.y = PI
		sled.parked = false
		p.global_position = Vector3(0, main.height(0, 11) + 0.2, 11)
		p.rotation.y = PI   # ふもとを向く
		_run = {"t": 0.0, "phase": 0, "by": args.get("by", "sack"), "rate": float(args.get("rate", "8")), "next": 0.0,
				"z0": sled.global_position.z, "sack": null, "catch_t": -1.0, "catch_d": 0.0, "still": 0.0, "vmax": 0.0}
		return
	var r := _run
	r.t += dt
	var v := sled.linear_velocity.length()
	r.vmax = maxf(r.vmax, v)
	match r.phase:
		0:   # 手を離れて滑っていく。delay 秒たったら追いかけ始める
			if r.t >= float(args.get("delay", "1.0")):
				r.phase = 1
				if r.by == "sack":
					# 米袋を足もとに出して乗る（装備の呼び出しは店のセッションの N。ここでは同じことを直接する）
					var sk: RigidBody3D = Sled.new()
					sk.kind = "sack"
					sk.snow_lift = main.snow_lift
					main.add_child(sk)
					sk.global_transform = Transform3D(Basis(Vector3.UP, PI), p.global_position + Vector3.UP * 0.2)
					sk.parked = false
					r.sack = sk
					p.sled = sk
					p.get_on()
					_key(KEY_W, true)
				else:
					p.rotation.y = PI
					_key(KEY_SHIFT, true)
					_key(KEY_W, true)
		1:   # 追いかける
			if r.by == "sack":
				var sk: RigidBody3D = r.sack
				if sk.linear_velocity.length() > 1.5:
					_key(KEY_W, false)
				r.next -= dt
				if r.rate > 0.0 and r.next <= 0.0:
					r.next += 1.0 / r.rate
					_tap(KEY_SPACE)
			else:
				# 走って追う: ソリのほうを向く
				var to: Vector3 = sled.global_position - p.global_position
				p.rotation.y = atan2(-to.x, -to.z)
			var gp: Array = sled.grip_point_near(p.global_position)
			if p.global_position.distance_to(sled.to_global(gp[0])) < (p.CATCH_REACH if r.by == "sack" else p.GRAB_REACH) - 0.2:
				_key(KEY_W, false)
				_key(KEY_SHIFT, false)
				p.sled = sled if r.by != "sack" else p.sled
				_tap(KEY_F)
				r.phase = 2
				r.catch_t = r.t
				r.catch_d = sled.global_position.z - r.z0
			elif r.t > 40.0:
				print("結果: %s を %s（%s）で追って、40 秒で追いつけない。ソリは %.0f m 滑った（最高 %.1f m/s）" % [sled.kind, r.by,
						("1 秒に %d 回" % r.rate) if r.by == "sack" else "走る", sled.global_position.z - r.z0, r.vmax])
				quit()
		2:   # つかんだ: 止まるか
			r.still = r.still + dt if v < 0.1 else 0.0
			var holding: bool = p.mode == p.Mode.GRIP and p.sled == sled
			if r.still > 0.5 and holding:
				_report(r, "止まった（つかんでから %.1f m・%.1f 秒）" % [sled.global_position.z - r.z0 - r.catch_d, r.t - r.catch_t - 0.5])
			elif not holding and r.t - r.catch_t > 0.2:
				_report(r, "止められない（%s。つかんでから %.1f m で手が離れた）" % ["つかめなかった" if r.t - r.catch_t < 0.4 else "引きずられた",
						sled.global_position.z - r.z0 - r.catch_d])
			elif r.t - r.catch_t > 30.0:
				_report(r, "30 秒たっても止まらない")


func _report(r: Dictionary, outcome: String) -> void:
	print("結果: %s（空、頂上から 15 m で手を離れる）を %.1f 秒遅れて %s で追う → %.1f 秒・ソリが %.1f m 滑った所で追いつく（ソリの最高 %.1f m/s）。%s" % [
			sled.kind, float(args.get("delay", "1.0")), ("米袋・1 秒に %d 回蹴る" % r.rate) if r.by == "sack" else "走って",
			r.catch_t, r.catch_d, r.vmax, outcome])
	quit()


# ---------------------------------------------------------------- 横から撮る

func _shot(dt: float) -> void:
	var p = main.player
	if _run.is_empty():
		if t < 1.0:
			return
		var sk: RigidBody3D = Sled.new()
		sk.kind = "sack"
		sk.snow_lift = main.snow_lift
		main.add_child(sk)
		sk.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, main.height(0, 12) + 0.3, 12))
		sk.parked = false
		sk.linear_velocity = Vector3(0, 0, 3)
		p.global_position = sk.global_position
		p.sled = sk
		p.get_on()
		var c := Camera3D.new()
		c.fov = 50
		c.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4)
		main.add_child(c)
		c.make_current()
		_run = {"t": 0.0, "next": 0.0, "sack": sk, "cam": c}
		return
	var r := _run
	r.t += dt
	r.next -= dt
	if r.next <= 0.0:
		r.next += 1.0 / 8.0
		_tap(KEY_SPACE)
	var sk: RigidBody3D = r.sack
	var at: Vector3 = sk.global_position + Vector3.UP * 0.5
	r.cam.global_position = at + sk.global_basis.x * 2.6 + Vector3.UP * 0.5
	r.cam.look_at(at, Vector3.UP)
	if r.t > float(args.get("shot-after", "2.0")):
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(args.get("out", "/tmp/kick.png"))
		print("保存: ", args.get("out", "/tmp/kick.png"), " 速さ %.1f m/s" % sk.linear_velocity.length())
		quit()
