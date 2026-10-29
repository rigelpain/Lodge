extends SceneTree
## 走りながら米袋を出したときの勢いと、乗ったまま Space で漕ぐ効きの確かめ用（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sack_carry_check.gd -- --bots=0 [--places=flat,slope]
##         [--gaits=stand,walk,run] [--spaces=none,mash,hold] [--kick-secs=4] [--rate=8]
## あなたを平らな所（丘から 85 m 離れた所）か、坂（頂上のすぐ下）に立たせ、走る（Shift+W）・歩く（W）・止まったまま で
## 1.2 秒進んでから N で米袋を出して乗る。乗ったら W を離す（前傾しない）。--keep-w なら W は押したまま（前傾して、遅くなると雪をかく）。
## Space は none 押さない / mash 1 秒に --rate 回たたく / hold 押しっぱなし、を乗ってから --kick-secs 秒のあいだ。
## 止まる（0.15 m/s より遅いのが 0.4 秒）か、20 秒たつか、地面の端の手前まで来たら、滑った道のりと最高速度を出す。
## --control: 漕ぎ終えた速さから、D で 1 秒体重をかけて曲がった角度と、そのあと S で後ろに体重をかけて 3 m/s まで落とせる道のり

const RUNUP := 1.2          # N を押すまでに進む時間 (s)
const PLACES := {
	# 平ら: 丘の中心から 85 m の所から、丘と反対の斜め向きへ（下りの傾き 0.008 以下）
	"flat": {"at": Vector2(60, -60), "dir": Vector2(1, -1)},
	# 坂: 頂上から +x へ 12 m 下った所（下りの傾き 0.31）から、さらに下る（x = 25 m あたりがいちばん急で 0.44）
	"slope": {"at": Vector2(12, 0), "dir": Vector2(1, 0)},
}

var args := {}
var main: Node3D
var t := 0.0
var _keys := {}
var _queue: Array = []
var _run := {}
var _rows: Array[String] = []
var _wait := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for place in args.get("places", "flat,slope").split(","):
		for gait in args.get("gaits", "stand,walk,run").split(","):
			for space in args.get("spaces", "none,mash,hold").split(","):
				_queue.append([place, gait, space])
	_rows.append("| 場所 | 乗りかた | Space | 乗った瞬間 | 最高速度 | 1.5 m/s に落ちるまで | 滑った道のり | 止まるまで |")
	_rows.append("|---|---|---|---|---|---|---|---|")


func _key(k: Key, on: bool, again := false) -> void:
	if _keys.get(k, false) == on and not again:
		return
	_keys[k] = on
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)


func _tap(k: Key) -> void:
	_key(k, true, true)
	_key(k, false, true)


func _physics_process(dt: float) -> bool:
	t += dt
	var p = main.player
	if p == null or t < 1.0:
		return false
	if _wait > 0.0:
		_wait -= dt
		return false
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return false
		var c: Array = _queue.pop_front()
		var pl: Dictionary = PLACES[c[0]]
		var dir := Vector3(pl.dir.x, 0, pl.dir.y).normalized()
		var at := Vector3(pl.at.x, 0, pl.at.y) - dir * (0.0 if c[1] == "stand" else (3.4 if c[1] == "run" else 2.0) * RUNUP)
		at.y = main.height(at.x, at.z) + 0.2
		p.global_position = at
		p.velocity = Vector3.ZERO
		p.rotation.y = atan2(-dir.x, -dir.z)
		_run = {"place": c[0], "gait": c[1], "space": c[2], "t": 0.0, "phase": 0, "next": 0.0, "max": 0.0, "v0": 0.0,
				"path": 0.0, "last": Vector3.ZERO, "still": 0.0, "kicks": 0, "carry": -1.0, "moved": false}
		if c[1] != "stand":
			_key(KEY_W, true)
		if c[1] == "run":
			_key(KEY_SHIFT, true)
		return false
	var r := _run
	r.t += dt
	match r.phase:
		0:   # 助走
			if r.t >= RUNUP:
				_tap(KEY_N)
				if not args.has("keep-w"):
					_key(KEY_W, false)
				_key(KEY_SHIFT, false)
				r.phase = 1
				r.t = 0.0
		1:   # 乗って滑る
			if p.mode != p.Mode.RIDE or p.sled.kind != "sack":
				if r.t > 0.2:
					_rows.append("| %s | %s | %s | 乗れなかった | | | | |" % [r.place, r.gait, r.space])
					_end()
				return false
			var sk: RigidBody3D = p.sled
			var pos := sk.global_position
			var v := sk.linear_velocity.length()
			if r.last == Vector3.ZERO:
				r.last = pos
				r.v0 = v
			r.path += Vector2(pos.x - r.last.x, pos.z - r.last.z).length()
			r.last = pos
			r.max = maxf(r.max, v)
			r.moved = r.moved or v > 1.6
			if r.moved and r.carry < 0.0 and v < 1.5:
				r.carry = r.path   # 勢いが尽きた（雪をかく速さまで落ちた）
			var kicking: bool = r.t < float(args.get("kick-secs", "4"))
			if args.has("control") and not kicking:
				_control(r, sk, dt)
				return false
			match r.space:
				"mash":
					r.next -= dt
					if kicking and r.next <= 0.0:
						r.next += 1.0 / float(args.get("rate", "8"))
						_tap(KEY_SPACE)
				"hold":
					_key(KEY_SPACE, kicking)
			r.still = r.still + dt if v < 0.15 else 0.0
			var edge: bool = absf(pos.x) > 118.0 or absf(pos.z) > 118.0
			if r.still > 0.4 or r.t > 20.0 or edge:
				var end := "%.1f 秒" % (r.t - r.still) if r.still > 0.4 else ("端に着いた（%.1f 秒）" % r.t if edge else "20 秒で止まらない")
				var carry := ("%.1f m" % r.carry) if r.carry >= 0.0 else ("—" if not r.moved else "落ちない")
				_rows.append("| %s | %s | %s | %.1f m/s | %.1f m/s | %s | %.1f m | %s |" % [r.place, r.gait, r.space, r.v0, r.max, carry, r.path, end])
				_key(KEY_SPACE, false)
				_end()
	return false


## 漕ぎ終えたら: D で 1 秒曲がる → S で止める
func _control(r: Dictionary, sk: RigidBody3D, dt: float) -> void:
	_key(KEY_SPACE, false)
	var v := sk.linear_velocity.length()
	var fwd := -sk.global_basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	if not r.has("c_t"):
		_key(KEY_W, false)
		_key(KEY_D, true)
		r.c_t = 0.0
		r.c_v = v
		r.c_yaw = yaw
		r.c_dir = Vector2(sk.linear_velocity.x, sk.linear_velocity.z).angle()
	r.c_t += dt
	if r.c_t >= 1.0 and not r.has("c_turn"):
		_key(KEY_D, false)
		_key(KEY_S, true)
		r.c_turn = rad_to_deg(absf(angle_difference(r.c_dir, Vector2(sk.linear_velocity.x, sk.linear_velocity.z).angle())))
		r.c_v1 = v
		r.c_path = r.path
		r.c_t1 = r.c_t
	if r.has("c_turn") and (v < 3.0 or r.c_t > 15.0):
		_key(KEY_S, false)
		_rows.append("| %s | %s | %s | 漕ぎ終え %.1f m/s | D 1 秒で進む向きが %.0f° 曲がる（%.1f m/s に） | S で 3 m/s まで %.1f m・%.1f 秒 | | |" % [
				r.place, r.gait, r.space, r.c_v, r.c_turn, r.c_v1, r.path - r.c_path, r.c_t - r.c_t1])
		_end()


## 米袋をしまって、次の場面へ
func _end() -> void:
	var p = main.player
	for k in [KEY_W, KEY_SHIFT, KEY_SPACE, KEY_D, KEY_S]:
		_key(k, false)
	if p.mode == p.Mode.RIDE and p.sled.kind == "sack":
		_tap(KEY_N)
	_run = {}
	_wait = 1.5
