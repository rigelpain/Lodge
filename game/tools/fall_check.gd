extends SceneTree
## 大きな山の段差から飛んで着地したとき、ソリが地面をすり抜けないかの確かめ（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/fall_check.gd -- --sled=KIND --no-player --bots=0 --no-sound
##
## 山の何か所か（ジャンプ台の着地・コースの脇の土手の外・山の脇の急な所・頂上の裏）の雪面のすぐ上に、
## いろいろな速さ（前へ・下へ）と傾き（水平・前のめり・横倒し）でソリを置き、3 秒のあいだ雪面より下へ沈まないかを見る。
## 沈んだ = ソリのまんなかが雪面より 1 m 以上下にいたことがある。
##   --net-check   落ちたあと、安全網で雪の上へ戻ったか（戻った数）も出す
##   --only=所,前,下,傾き   その 1 回だけ（例 --only=頂上の裏,25,30,水平）。1 コマずつの様子も出す
##   --trace=所,前,下,傾き  全部回しつつ、その 1 回の 1 コマずつの様子を出す（--trace-t=秒 まで。既定 0.4）
##   --case=jump   ジャンプ台（中腹の肩の先）の踏み切りの坂の 6 m 手前から、1 人乗せて 6・9・12 m/s で踏み切りへ入れ、宙にいた時間と飛んだ長さを出す
##                 （当たりを変えたときに、飛び方が変わっていないかを見る用）

const Mountain := preload("res://mountain.gd")

var args := {}
var main: Node3D
var sled: RigidBody3D
var t := 0.0
var _queue: Array = []
var _cur := {}
var _rows: Array[String] = []
var _fell := 0
var _back := 0
var _total := 0
var _worst := 0.0
var _started := false
var _dummy: GDScript
const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


## 着地させる所: [名前, x, z]
func _spots() -> Array:
	var k := Mountain.kicker(1)
	var land: Vector2 = (k.lip as Vector2) + (k.f as Vector2) * 8.0
	return [
		["ジャンプ台の着地", land.x, land.y],
		["東の尾根の東の急な所", 52.0, 400.0],
		["山の脇の急な所", Mountain.SX - 70.0, 420.0],
		["頂上の裏", Mountain.SX, Mountain.top_z + 40.0],
	]


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null:
		return false
	if not _started:
		if t < 0.5:
			return false
		_started = true
		sled = main.sled
		if args.get("case", "") == "jump":
			_dummy = GDScript.new()
			_dummy.source_code = DUMMY_SRC
			_dummy.reload()
			for v in [6.0, 9.0, 12.0]:
				_queue.append({"jump": v})
			return false
		for s in _spots():
			for fwd in [12.0, 25.0]:
				for down in [6.0, 12.0, 20.0, 30.0]:
					for tilt in ["水平", "前のめり", "横倒し"]:
						if args.has("only") and args["only"] != "%s,%d,%d,%s" % [s[0], fwd, down, tilt]:
							continue
						_queue.append({"spot": s, "fwd": fwd, "down": down, "tilt": tilt, "name": "%s,%d,%d,%s" % [s[0], fwd, down, tilt]})
		_total = _queue.size()
		return false
	if _cur.is_empty():
		if _queue.is_empty():
			print("%s: %d 回のうち、すり抜けた %d 回%s。雪面からいちばん下へ沈んだ %.2f m" % [sled.kind, _total, _fell,
					("（安全網で雪の上へ戻った %d 回）" % _back) if args.has("net-check") else "", _worst])
			for r in _rows:
				print("  " + r)
			quit()
			return true
		_cur = _queue.pop_front()
		if _cur.has("jump"):
			_jump_start(_cur)
			return false
		_cur.t = 0.0
		_cur.low = 1e9
		_cur.fell = false
		var s: Array = _cur.spot
		var x: float = s[1]
		var z: float = s[2]
		var g: float = main.height(x, z)
		var b := Basis(Vector3.UP, 0.0)   # 前（-z）を向く
		match _cur.tilt:
			"前のめり":
				b = Basis(Vector3.RIGHT, deg_to_rad(-30.0)) * b
			"横倒し":
				b = Basis(Vector3.BACK, deg_to_rad(45.0)) * b
		# 箱のどの角も、その真下の雪面から 0.4 m 上にあるように置く（坂に箱が刺さった姿から始めない）
		var box: Vector3 = sled.KINDS[sled.kind].box
		var lift := -1e9
		for cx in [-0.5, 0.5]:
			for cy in [0.0, 1.0]:
				for cz in [-0.5, 0.5]:
					var o := b * Vector3(box.x * cx, box.y * cy, box.z * cz)
					lift = maxf(lift, main.height(x + o.x, z + o.z) - g - o.y + 0.4)
		sled.reset_to(Vector3(x, g + 0.8, z))
		sled.global_transform = Transform3D(b, Vector3(x, g + lift, z))
		sled.parked = false
		sled.linear_velocity = Vector3(0, -float(_cur.down), -float(_cur.fwd))
		sled.angular_velocity = Vector3.ZERO
		return false
	var c := _cur
	if c.has("jump"):
		_jump_step(c, dt)
		return false
	c.t += dt
	var p := sled.global_position
	var d: float = p.y - main.height(p.x, p.z)
	c.low = minf(c.low, d)
	if (args.has("only") or args.get("trace", "") == c.name) and c.t < float(args.get("trace-t", "0.4")):   # 1 コマずつの様子
		print("t=%.3f 雪から %.2f 速さ %s 回り %s 上 %s" % [c.t, d, str(sled.linear_velocity.snapped(Vector3.ONE * 0.1)),
				str(sled.angular_velocity.snapped(Vector3.ONE * 0.1)), str(sled.global_basis.y.snapped(Vector3.ONE * 0.01))])
	if d < -1.0:
		c.fell = true
	if c.t >= 3.0:
		var s: Array = c.spot
		_worst = minf(_worst, c.low)
		if c.fell:
			_fell += 1
			var back := d > -0.5
			if back:
				_back += 1
			_rows.append("すり抜けた: %s 前へ %.0f m/s・下へ %.0f m/s・%s（いちばん沈んだ %.1f m、3 秒後 %.1f m%s）" % [s[0], c.fwd, c.down, c.tilt, c.low, d,
					"、雪の上へ戻った" if back else ""])
		_cur = {}
	return false


func _jump_start(c: Dictionary) -> void:
	var k := Mountain.kicker(1)
	var f: Vector2 = k.f
	var st: Vector2 = (k.lip as Vector2) - f * (Mountain.KICK_L + 6.0)
	var x := st.x
	var z := st.y
	sled.reset_to(Vector3(x, main.height(x, z) + 0.3, z))
	sled.parked = false
	var d := Vector3(f.x, main.height(x + f.x, z + f.y) - main.height(x, z), f.y).normalized()
	sled.linear_velocity = d * float(c.jump)
	var r := Node3D.new()
	r.set_script(_dummy)
	r.sled = sled
	main.add_child(r)
	sled.mount(r)
	c.rider = r
	c.t = 0.0
	c.lip = k.lip
	c.f = f
	c.air = -1.0
	c.from = 0.0
	c.v_lip = -1.0


func _jump_step(c: Dictionary, dt: float) -> void:
	c.t += dt
	var p := sled.global_position
	var along: float = (Vector2(p.x, p.z) - (c.lip as Vector2)).dot(c.f)   # 縁から先へ (m)
	if c.v_lip < 0.0 and along > 0.0:
		c.v_lip = sled.linear_velocity.length()
	var clear: float = p.y - main.height(p.x, p.z)
	if c.v_lip >= 0.0 and clear > 0.35 and c.air < 0.0:
		c.air = 0.0
		c.from = along
	elif c.air >= 0.0 and not c.has("land"):
		if clear > 0.35:
			c.air += dt
		else:
			c.land = along
	if c.has("land") or c.t > 6.0:
		print("%s: 踏み切りへ %.0f m/s で入れた。踏み切りの縁で %.1f m/s、宙 %.2f 秒、飛んだ長さ %.1f m" % [sled.kind, c.jump, c.v_lip,
				maxf(c.air, 0.0), (c.get("land", along) - c.from) if c.air >= 0.0 else 0.0])
		sled.dismount(c.rider)
		c.rider.queue_free()
		_cur = {}
