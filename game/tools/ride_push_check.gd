extends SceneTree
## 乗っている人がいるソリを押す・紐で引くときの確かめ（数字だけ出す）。大きさは main.gd と同じ --sled= で選ぶ。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/ride_push_check.gd -- --sled=mid --no-player --bots=0 --no-sound --no-lodge --roam-bots=0 --lodge-bots=0
## 1. 重さ: ふもと（頂上から 36 m）から頂上の 4 m 手前まで、乗っている人の数を変えて、1 人・2 人で押す、1 人で紐で引く。
##    登る時間と平均の速さ（push_check と同じ線）。乗っている人が増えるほど遅くなるか
## 2. 稼ぎ: 乗っている人（番号つき）を、押してもらう・紐で引いてもらうあいだ、乗っている人に入るボタン（share・ride_pay_one）を数える。
##    頂上から下りへ押し続ける（押し出しのあとも押す）と、ふもとの平らな所を押す・紐で引く（道の上に斜面のボタンを 3 つ置く）。
##    最後に、頂上で押し出して手を離し、ふつうに滑ったときの分も出す（押してもらっていないときは前のまま入るか）
##   --part=weight|earn で片方だけ

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const FROM := 36.0
const TO := 4.0
const LIMIT := 150.0
const RIDER_ID := 7

var args := {}
var main: Node3D
var sled: RigidBody3D
var sb: Node3D
var _dummy: GDScript
var _rows: Array[String] = []
var _got := 0          # 乗っている人（RIDER_ID）に入った数
var _helper_got := 0   # 押した・引いた人に入った数


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


func _person(id := -1) -> Node3D:
	var d := Node3D.new()
	d.set_script(_dummy)
	d.sled = sled
	d.id = id
	main.add_child(d)
	return d


func _run() -> void:
	await create_timer(0.5).timeout
	sled = main.sled
	sb = main.snow_buttons
	if sb:
		sb.auto = false
		sb.clear()
		sb.happened.connect(_on_button)
	var part := String(args.get("part", ""))
	if part != "earn":
		await _weight()
	if part != "weight" and sb:
		await _earn()
	print("\n".join(_rows))
	quit()


# ================================================================ 1. 重さ

func _weight() -> void:
	var seats: int = sled.SEATS.size()
	var counts := [0, 1]
	if seats >= 2:
		counts.append(2)
	if seats > 2:
		counts.append(seats)
	_rows.append("### 重さ（%s。ふもとから頂上の %d m 手前まで %d m）" % [sled.kind, int(TO), int(FROM - TO)])
	_rows.append("| ソリ | 乗る人 | 押し方 | 登る時間 (s) | 平均の速さ (m/s) | 乗っていない時に比べた速さ |")
	_rows.append("|---|---|---|---|---|---|")
	for how in ["押す 1 人", "押す 2 人", "紐 1 人"]:
		var base := 0.0
		for n in counts:
			var r := await _climb(n, how)
			if n == 0:
				base = r.v
			_rows.append("| %s | %d | %s | %s | %.2f | %s |" % [sled.kind, n, how, r.time, r.v, "—" if n == 0 else "×%.2f" % (r.v / maxf(base, 0.001))])


func _climb(n_riders: int, how: String) -> Dictionary:
	sled.reset_to(Vector3(0, main.height(0, FROM) + 0.3, FROM))
	sled.rotation.y = 0.0   # 前（-Z）を頂上へ
	sled.parked = false
	# 押す人が先に後ろの縁をつかんで押しはじめ、それから乗る
	var ps := []
	var np := 2 if how == "押す 2 人" else 1
	for i in np:
		var d := _person()
		if how != "紐 1 人":
			sled.take_handle(d, Vector3((i - (np - 1) / 2.0) * 1.0, 0, sled.HALF.y + sled.STAND))
		ps.append(d)
	var rs := []
	for i in n_riders:
		rs.append(_person())
	var t := 0.0
	var still := 0.0
	var z := FROM
	while true:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		if t > 1.0 and t - dt <= 1.0:   # 押しはじめて、置き直したソリが雪に落ち着いてから乗る（落ちた勢いのまま乗ると、大は滑り出して止まらない）
			for d in rs:
				sled.mount(d)
		if how == "紐 1 人":
			# 紐の先を持つ手: 頂上へ向けて、紐がぴんと張った所（ソリについて行く）
			var a: Vector3 = sled.to_global(sled.ROPE_ANCHOR)
			sled.rope_holder = ps[0]
			sled.pull_rope(a + Vector3(0, 0, -(sled.ROPE_LEN + sled.ROPE_TAKEUP + 0.05)))
		else:
			var k: int = ps.size()
			for i in k:
				var x: float = (i - (k - 1) / 2.0) / maxf(k, 1.0) * sled.HALF.x * 1.6
				sled.push(Vector3(0, 0, -1), sled.to_global(Vector3(x, 0.2, sled.HALF.y)), ps[i])
		z = sled.global_position.z
		var v := sled.linear_velocity.length()
		if args.has("trace") and Engine.get_physics_frames() % 60 == 0:
			print("%s 乗%d t=%.0f z=%.1f 速さ=%.2f 上=%.2f 押%d 登り%s %s" % [how, n_riders, t, z, v, sled.linear_velocity.y, sled.pushers, sled._pushing_uphill(), sled.hold_debug])
		still = still + dt if v < 0.05 and t > 3.0 else 0.0
		if z <= TO or still > 3.0 or t > LIMIT:
			break
	sled.rope_holder = null
	for d in rs:
		sled.dismount(d)
		d.queue_free()
	for d in ps:
		sled.release_handle(d)
		d.queue_free()
	var climbed := FROM - z
	var time := "%.1f" % t if z <= TO else ("止まった（%.1f m 登って）" % climbed if still > 3.0 else "%d 秒で %.1f m" % [int(LIMIT), climbed])
	return {"time": time, "v": climbed / t}


# ================================================================ 2. 稼ぎ

func _on_button(ev: Dictionary) -> void:
	match ev.kind:
		"share":
			for who in ev.gives:
				if int(who) == RIDER_ID:
					_got += int(ev.gives[who])
				else:
					_helper_got += int(ev.gives[who])
		"ride_pay_one":
			if int(ev.who) == RIDER_ID:
				_got += int(ev.n)
		"ride_pay":
			for who in ev.gives:
				_helper_got += int(ev.gives[who])


func _earn() -> void:
	_rows.append("")
	_rows.append("### 稼ぎ（%s。乗っている人 1 人に入った数。木の何個分）" % sled.kind)
	_rows.append("| ソリ | 場面 | 時間 (s) | 進んだ (m) | 平均の速さ (m/s) | 切れた斜面のボタン | 乗っている人に入った | 押した・引いた人に入った |")
	_rows.append("|---|---|---|---|---|---|---|---|")
	await _earn_case("下りを押し続ける", "push_down", 14.0)
	var flat := _flat_spot()
	await _earn_case("平らな所を押す 2 人", "push_flat", 30.0, flat)
	await _earn_case("平らな所を紐で引く", "rope_flat", 30.0, flat)
	await _earn_case("押し出して手を離し、滑る", "launch", 60.0)
	_rows.append("平らな所: (%.0f, %.1f, %.0f) から +z へ。斜面のボタンは、平らな所の 2 つの場面だけ道の上に 3 つ置く" % [flat.x, flat.y, flat.z])


## ふもとの平らな所（+z へ。傾きがいちばん小さい 40 m の区間の始まり）
func _flat_spot() -> Vector3:
	var best := INF
	var at := Vector3.ZERO
	var space := sled.get_world_3d().direct_space_state
	for x in range(-60, 61, 10):
		for z0 in range(30, 140, 5):
			var lo := INF
			var hi := -INF
			var clear := true
			for i in 9:
				var h: float = main.height(x, z0 + i * 5.0)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				# 道の上に木や物がないか（ソリの幅で、雪の上 0.6 m を横に見る）
				for dx in [-1.2, 0.0, 1.2]:
					var q := PhysicsRayQueryParameters3D.create(Vector3(x + dx, h + 0.6, z0 + i * 5.0), Vector3(x + dx, h + 0.6, z0 + i * 5.0 + 5.0))
					q.exclude = [sled.get_rid()]
					if not space.intersect_ray(q).is_empty():
						clear = false
			if clear and hi - lo < best:
				best = hi - lo
				at = Vector3(x, main.height(x, z0), z0)
	return at


func _earn_case(label: String, how: String, secs: float, at := Vector3.INF) -> void:
	sb.clear()
	if how == "push_flat" or how == "rope_flat":
		sled.reset_to(at + Vector3(0, 0.3, 0))
		sled.rotation.y = PI   # 前（-Z）を +z へ。+z へ進む
	else:
		sled.reset_to(Vector3(0, main.height(0, 3.0) + 0.3, 3.0))
		sled.rotation.y = PI
	sled.parked = false
	sled.helped.clear()
	var rider := _person(RIDER_ID)
	sled.mount(rider)
	var ps := []
	for i in (2 if how == "push_flat" else 1):
		ps.append(_person(20 + i))
	await create_timer(0.3).timeout
	var p0: Vector3 = sled.global_position
	if how == "push_flat" or how == "rope_flat":   # 道の上に斜面のボタンを 3 つ
		for d in [6.0, 14.0, 22.0]:
			var q := p0 + Vector3(0, 0, d)
			sb.drop_at(Vector3(q.x, main.height(q.x, q.z), q.z), 0, true, 0)
	await create_timer(0.1).timeout
	_got = 0
	_helper_got = 0
	var snip0: int = sb.stats.snip
	var t := 0.0
	while t < secs:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		match how:
			"push_down", "push_flat":
				var k: int = ps.size()
				for i in k:
					var x: float = (i - (k - 1) / 2.0) / maxf(k, 1.0) * sled.HALF.x * 1.6
					sled.push(Vector3(0, 0, 1), sled.to_global(Vector3(x, 0.2, sled.HALF.y)), ps[i])
			"rope_flat":
				var a: Vector3 = sled.to_global(sled.ROPE_ANCHOR)
				sled.rope_holder = ps[0]
				sled.pull_rope(a + Vector3(0, 0, sled.ROPE_LEN + sled.ROPE_TAKEUP + 0.05))
			"launch":
				if t < 1.5:
					sled.push(Vector3(0, 0, 1), sled.to_global(Vector3(0, 0.2, sled.HALF.y)), ps[0])
				elif t > 3.0 and sled.linear_velocity.length() < 0.3:
					break
		if args.has("trace") and Engine.get_physics_frames() % 60 == 0:
			print("%s t=%.0f 所=(%.1f, %.1f, %.1f) 速さ=%.2f 押%d" % [how, t, sled.global_position.x, sled.global_position.y, sled.global_position.z, sled.linear_velocity.length(), sled.pushers])
	var dist := Vector2(sled.global_position.x - p0.x, sled.global_position.z - p0.z).length()
	sled.rope_holder = null
	# 降りる（降りたときに、乗ってから縫い込まれた分が入る）。滑りが終わるまで少し待つ
	sled.dismount(rider)
	for i in 90:
		await physics_frame
	_rows.append("| %s | %s | %.1f | %.0f | %.2f | %d | %d | %d |" % [sled.kind, label, t, dist, dist / maxf(t, 0.01), sb.stats.snip - snip0, _got, _helper_got])
	rider.queue_free()
	for d in ps:
		d.queue_free()
