extends SceneTree
## 紐で引く力と、滑走の減速の確かめ（数字だけ出す）。大きさは main.gd と同じ --sled= で選ぶ。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/glide_check.gd -- --case=<名前> --sled=mid --no-sound --no-lodge --roam-bots=0 --lodge-bots=0
##
##   --case=pull   同じ坂（丘の x = 0、頂上から 36 m → 4 m）と平らな所で、押すのと紐で引くのを比べる。紐は本物のあなた（W を押して歩く）、
##                 押す人は sled.push を呼ぶだけの形の人。人数が増えると、紐 1 人＋押す人（紐は 1 本で 1 人しか持てない）。
##   --case=coast  平らな所（確かめ用の広い板）で、速さ v0 から手を離して止まるまでの距離と時間。乗る人 0・1 人・満席。後傾のブレーキと、体重移動の曲がり方も。
##   --case=down   本物の山を滑る。丘は頂上から、大きな山・大山は滑り出す所から麓へ体重移動で向かい、最高速度と止まった所。空のソリのずり落ちも。
##   --case=edge   飛び出しの確かめ。いちばん速い乗り方（満席で前傾しっぱなし）で、丘の頂上から 8 方向と、大きな山・大山の麓へ。地面の端までの距離（負なら地面の外）。

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const FROM := 36.0
const TO := 4.0
const LAB_Y := 300.0     # 確かめ用の平らな板の上面の高さ
const STILL := 0.1       # これより遅くなったら「止まった」(m/s)
const Mountain := preload("res://mountain.gd")
const Grand := preload("res://grand_mountain.gd")

var args := {}
var main: Node3D
var sled: RigidBody3D
var _dummy: GDScript
var _rows: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.5).timeout
	sled = main.sled
	_make_lab()
	match args.get("case", "coast"):
		"pull":
			await _pull_case()
		"coast":
			await _coast_case()
		"down":
			await _down_case()
		"edge":
			await _edge_case()
	print("\n".join(_rows))
	quit()


## 平らな広い板（地面の当たりと同じ摩擦）。山の起伏に邪魔されず、止まるまでの距離を測る
func _make_lab() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0, LAB_Y - 1.0, 0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000, 2, 6000)
	col.shape = box
	body.add_child(col)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	body.physics_material_override = pm
	main.add_child(body)


func _person() -> Node3D:
	var d := Node3D.new()
	d.set_script(_dummy)
	d.sled = sled
	main.add_child(d)
	return d


func _key(k: Key, on: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)


func _ms(v: float) -> String:
	return "%.2f" % v


# ---------------------------------------------------------------- 紐と押す

func _pull_case() -> void:
	_rows.append("| 所 | ソリ | 人数 | 方法 | 時間 (s) | 平均の速さ (m/s) | いちばん遅い速さ (m/s) | 紐の張り（平均 m）| 手が離れた |")
	_rows.append("|---|---|---|---|---|---|---|---|---|")
	var people: Array = Array(String(args.get("people", "1,2,4")).split(",")).map(func(s): return int(s))
	for n in people:
		for how in ["push", "rope"]:
			await _pull_one("hill", n, how)
	for n in people:
		for how in ["push", "rope"]:
			await _pull_one("flat", n, how)


func _pull_one(where: String, n: int, how: String) -> void:
	var pl: Node3D = main.player
	var start: Vector3
	var dist := FROM - TO
	if where == "hill":
		start = Vector3(0, main.height(0, FROM) + 0.3, FROM)
	else:
		start = Vector3(40, LAB_Y + 0.3, 0)
		dist = 30.0
	pl.let_go()
	sled.reset_to(start)
	sled.rotation.y = 0.0
	sled.parked = false
	pl.global_position = Vector3(start.x + 30.0, main.height(start.x + 30.0, start.z) + 1.0, start.z)
	await create_timer(0.5).timeout
	var pushers := []
	for i in (n if how == "push" else n - 1):
		pushers.append(_person())
	var z0: float = sled.global_position.z
	if how == "rope":
		var a: Vector3 = sled.rope_root()
		pl.global_position = a + Vector3(0, 0.5, -sled.ROPE_LEN)
		if where == "hill":
			pl.global_position.y = main.height(a.x, a.z - sled.ROPE_LEN) + 0.1
		pl.rotation.y = 0.0
		pl.velocity = Vector3.ZERO
		pl.grab_rope()
		_key(KEY_W, true)
	var t := 0.0
	var low := INF
	var over_sum := 0.0
	var over_n := 0
	var dropped := false
	var cap := 150.0
	while t < cap:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		var k: float = pl.damp_k(true)
		for i in pushers.size():
			var m: int = pushers.size()
			var x: float = (i - (m - 1) / 2.0) / maxf(m, 1.0) * sled.HALF.x * 1.6
			sled.push(Vector3(0, 0, -1), sled.to_global(Vector3(x, 0.2, sled.HALF.y)), pushers[i], k)
		var moved: float = z0 - sled.global_position.z
		if t > 3.0 and moved > 1.0 and moved < dist - 1.0:
			low = minf(low, sled.linear_velocity.length())
		if how == "rope":
			if sled.rope_holder != pl:
				dropped = true
				break
			var over: float = pl.rope_hand().distance_to(sled.rope_root()) - sled.ROPE_LEN
			over_sum += maxf(over, 0.0)
			over_n += 1
		if moved >= dist:
			break
	var moved: float = z0 - sled.global_position.z
	_key(KEY_W, false)
	pl.let_go()
	var tt := "%.1f" % t if moved >= dist else "%.1f m で打ち切り" % moved
	_rows.append("| %s | %s | %d | %s | %s | %s | %s | %s | %s |" % ["丘" if where == "hill" else "平ら", sled.kind, n,
		"押す %d" % n if how == "push" else ("紐 1 ＋ 押す %d" % (n - 1) if n > 1 else "紐 1"), tt, _ms(moved / t), _ms(low if low != INF else 0.0),
		"%.2f" % (over_sum / over_n) if over_n > 0 else "—", "はい" if dropped else ""])
	for d in pushers:
		sled.release_handle(d)
		d.queue_free()


# ---------------------------------------------------------------- 平らな所で止まるまで

func _coast_case() -> void:
	_rows.append("| ソリ | 乗る人 | 操作 | 手を離した速さ (m/s) | 止まるまでの距離 (m) | 時間 (s) | 速さが半分になるまで (s) |")
	_rows.append("|---|---|---|---|---|---|---|")
	var full: int = sled.SEATS.size()
	for r in ([0, 1, full] if full > 1 else [0, 1]):
		for v0 in [2.0, 5.0, 10.0]:
			await _coast_one(r, v0, "そのまま")
	await _coast_one(1, 15.0, "そのまま")
	await _coast_one(1, 5.0, "後傾")
	await _coast_one(1, 10.0, "後傾")
	await _coast_one(1, 15.0, "後傾")
	await _turn_one(1, 8.0)


func _lab_ride(r: int, v0: float) -> Array:
	sled.reset_to(Vector3(400, LAB_Y + 0.3, 0))   # 地面の端の吹きだまりから遠い所
	sled.rotation.y = 0.0
	sled.parked = false
	var rs := []
	for i in r:
		var d := _person()
		sled.mount(d)
		rs.append(d)
	await create_timer(0.5).timeout
	sled.linear_velocity = Vector3(0, 0, -v0)
	sled.angular_velocity = Vector3.ZERO
	return rs


func _coast_one(r: int, v0: float, op: String) -> void:
	var rs: Array = await _lab_ride(r, v0)
	var p0: Vector3 = sled.global_position
	var t := 0.0
	var half := -1.0
	while t < 240.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if op == "後傾":
			sled.lean(0.0, false, true)
		var v: float = sled.linear_velocity.length()
		if half < 0.0 and v < v0 * 0.5:
			half = t
		if v < STILL:
			break
	var far: float = (sled.global_position - p0).length()
	_rows.append("| %s | %d | %s | %.0f | %.1f | %s | %s |" % [sled.kind, r, op, v0, far, "%.1f" % t if t < 240.0 else "240 秒でも止まらない", "%.1f" % half])
	for d in rs:
		sled.dismount(d)
		d.queue_free()


## 体重移動（D）を 2 秒。曲がった角度と、そのあいだの半径
func _turn_one(r: int, v0: float) -> void:
	var rs: Array = await _lab_ride(r, v0)
	var yaw0: float = sled.rotation.y
	var t := 0.0
	var turned := 0.0
	var last: float = yaw0
	while t < 2.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		sled.lean(1.0, false)
		turned += absf(wrapf(sled.rotation.y - last, -PI, PI))
		last = sled.rotation.y
	var v: float = sled.linear_velocity.length()
	_rows.append("| %s | %d | 体重移動 D 2 秒 | %.0f | 曲がった %.0f°（終わりの速さ %.1f m/s） | 2.0 | |" % [sled.kind, r, v0, rad_to_deg(turned), v])
	for d in rs:
		sled.dismount(d)
		d.queue_free()


# ---------------------------------------------------------------- 本物の山

func _down_case() -> void:
	_rows.append("| 所 | ソリ | 乗る人 | 最高速度 (m/s) | 止まった所 (x, z) | 滑った距離 (m) | 時間 (s) | 地面の下へ |")
	_rows.append("|---|---|---|---|---|---|---|---|")
	var full: int = sled.SEATS.size()
	await _down_one("丘（頂上から）", Vector2(0, 2), Vector2(0, 58), 1)
	if full > 1:
		await _down_one("丘（頂上から）", Vector2(0, 2), Vector2(0, 58), full)
	await _down_one("大きな山", Mountain.START, Vector2(Mountain.FACE_X, Mountain.BOTTOM_Z), 1)
	await _down_one("大山", Grand.START, Vector2(Grand.BOTTOM_X, Grand.FACE_Z), 1)
	await _slip_one("丘の空のソリ（頂上から 25 m に置く）", Vector2(0, 25), Vector2(0, 1))
	await _slip_one("丘の空のソリ（横 15 m、頂上から 25 m に置く）", Vector2(15, 20), Vector2(0.6, 0.8))


func _edge_case() -> void:
	_rows.append("| 所 | ソリ | 乗る人 | 最高速度 (m/s) | 止まった所 (x, z) | 滑った距離 (m) | 時間 (s) | 地面の下へ |")
	_rows.append("|---|---|---|---|---|---|---|---|")
	var full: int = sled.SEATS.size()
	var fast: bool = not args.has("plain")   # --plain で、前傾しない（1.5 m/s までの雪かきだけ）
	for k in 8:
		var d := Vector2.from_angle(TAU * k / 8.0)
		await _down_one("丘 %d°" % (45 * k), Vector2.ZERO + d * 2.0, d * 58.0, full, fast)
	await _down_one("大きな山", Mountain.START, Vector2(Mountain.FACE_X, Mountain.BOTTOM_Z), full, fast)
	await _down_one("大山", Grand.START, Vector2(Grand.BOTTOM_X, Grand.FACE_Z), full, fast)


func _down_one(label: String, from: Vector2, to: Vector2, r: int, fast := false) -> void:
	var y: float = main.height(from.x, from.y) + 0.3
	sled.reset_to(Vector3(from.x, y, from.y))
	var dir := (to - from).normalized()
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	var rs := []
	for i in r:
		var d := _person()
		sled.mount(d)
		rs.append(d)
	await create_timer(0.8).timeout
	var t := 0.0
	var top := 0.0
	var trip := 0.0
	var last: Vector3 = sled.global_position
	var still := 0.0
	var under := 0
	var heading := true
	while t < 300.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var p: Vector3 = sled.global_position
		var v: float = sled.linear_velocity.length()
		top = maxf(top, v)
		trip += (p - last).length()
		last = p
		var at := Vector2(p.x, p.z)
		if at.distance_to(to) < 12.0 or (to - at).dot(dir) < 0.0:
			heading = false   # 行き先を過ぎたら、もう操作しない（どこまで滑るかを見る）
		if not heading and fast:
			for d in rs:
				sled.lean(0.0, true)
		if heading:
			var fwd: Vector3 = -sled.global_basis.z
			fwd.y = 0
			var want := Vector3(to.x - at.x, 0, to.y - at.y).normalized()
			var err := atan2(fwd.normalized().cross(want).y, fwd.normalized().dot(want))
			for d in rs:   # 乗っている一人ひとりが毎コマ体重移動する（sled.lean）
				sled.lean(clampf(-err * 1.5, -1.0, 1.0), v < 1.5 or fast)
		if p.y < main.height(p.x, p.z) - 1.0:
			under += 1
		still = still + 1.0 / Engine.physics_ticks_per_second if v < STILL else 0.0
		if still > 1.0:
			break
	var p: Vector3 = sled.global_position
	_rows.append("| %s | %s | %d | %.1f | (%.0f, %.0f) 端まで %.0f m | %.0f | %s | %s |" % [label, sled.kind, r, top, p.x, p.z, main.edge_gap(p.x, p.z), trip, "%.0f" % t if t < 300.0 else "300 秒でも止まらない", str(under) if under > 0 else ""])
	for d in rs:
		sled.dismount(d)
		d.queue_free()


## 誰も触れていない空のソリを坂に置いて、手を離す
func _slip_one(label: String, from: Vector2, dir: Vector2) -> void:
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	var t := 0.0
	var top := 0.0
	var trip := 0.0
	var last: Vector3 = sled.global_position
	var still := 0.0
	while t < 120.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var p: Vector3 = sled.global_position
		var v: float = sled.linear_velocity.length()
		top = maxf(top, v)
		trip += (p - last).length()
		last = p
		still = still + 1.0 / Engine.physics_ticks_per_second if v < STILL else 0.0
		if still > 1.0 and t > 3.0:
			break
	var p: Vector3 = sled.global_position
	_rows.append("| %s | %s | 0 | %.1f | (%.0f, %.0f) | %.0f | %s | |" % [label, sled.kind, top, p.x, p.z, trip, "%.0f" % t if t < 120.0 else "120 秒でも止まらない"])
