extends SceneTree
## ソリに轢かれて吹き飛ぶ（flung.gd）の確かめ（数字だけ出す）。大きさは main.gd と同じ --sled= で選ぶ。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/run_over_check.gd -- --case=<名前> --sled=mid --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons
##
##   --case=speed  平らな板の上で、乗る人と速さを変えて立っている人に当てる。飛んだか、高さ、距離、起き上がるまで、ソリの速さの前後
##   --case=rules  飛ばないはずの場面と、飛ぶはずの場面: 遅いソリ、乗っている本人、つかんでいる本人、横をかすめる、跳んで越える、押して登る、紐、別のソリ
##   --case=slope  本物の丘を滑り下りたソリに当たる。雪面の下へ抜けないか、起き上がったあと W で歩けるか
##   --case=edge   地面の端の近くで端へ向けて飛ばす。地面の外へ出ないか
##   --case=bot    （--bots=1）仲間に当てる。つかんでいる仲間は飛ばない。立っている仲間は飛んで、起き上がったらまた動く

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
var seat := Vector3.INF
func get_off() -> void:
	sled.dismount(self)
func let_go() -> void:
	sled.release_handle(self)
"""
const LAB_Y := 300.0
const Sled := preload("res://sled.gd")

var args := {}
var main: Node3D
var sled: RigidBody3D
var p: CharacterBody3D
var _dummy: GDScript
var _dummies: Array[Node3D] = []
var fails := 0


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
	p = main.player
	_make_lab()
	match args.get("case", "speed"):
		"speed":
			await _speed_case()
		"rules":
			await _rules_case()
		"slope":
			await _slope_case()
		"edge":
			await _edge_case()
		"bot":
			await _bot_case()
	print("だめだった数: ", fails)
	quit(1 if fails > 0 else 0)


func _make_lab() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0, LAB_Y - 1.0, 0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000, 2, 6000)
	col.shape = box
	body.add_child(col)
	main.add_child(body)


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _say(ok: bool, what: String) -> void:
	print(("○ " if ok else "× ") + what)
	if not ok:
		fails += 1


func _riders(n: int) -> void:
	for d in _dummies:
		sled.dismount(d)
		d.queue_free()
	_dummies.clear()
	for i in n:
		var d: Node3D = _dummy.new()
		d.sled = sled
		main.add_child(d)
		d.seat = sled.mount(d)
		_dummies.append(d)


## 平らな板の上で、z = -10 の所のソリを +z へ v で走らせる（ソリの前は -z なので、後ろ向きにならないよう向きを合わせる）
func _launch(s: RigidBody3D, v: Vector3, at := Vector3(0, LAB_Y + 0.05, -10)) -> void:
	s.parked = false
	s.angular_velocity = Vector3.ZERO
	s.global_transform = Transform3D(Basis.looking_at(v.normalized() if v.length() > 0.01 else Vector3.FORWARD, Vector3.UP), at)
	s.linear_velocity = v
	s.reset_physics_interpolation()


func _stand(who: CharacterBody3D, at: Vector3) -> void:
	who.global_position = at
	who.velocity = Vector3.ZERO
	who.reset_physics_interpolation()


## ソリを走らせて、人に当てる。当たるまで速さを保つ。{flung, apex, dist, down_t, back_t, sled_before, sled_after, min_gap}
func _shot_at(who: CharacterBody3D, v: float, ground_y: float) -> Dictionary:
	var fl = who.get("fling")
	_launch(sled, Vector3(0, 0, v))
	_stand(who, Vector3(0, LAB_Y + 0.05, 4.0))
	var out := {"flung": false, "apex": 0.0, "dist": 0.0, "down_t": 0.0, "back_t": 0.0, "sled_before": v, "sled_after": 0.0, "min_gap": 99.0}
	var start: Vector3 = who.global_position
	var t := 0.0
	var hit_t := -1.0
	var limit := 25.0 / v + 10.0
	while t < limit:
		await physics_frame
		t += 1.0 / 60.0
		if hit_t < 0.0:
			if fl.active():
				hit_t = t
				out.flung = true
				out.sled_before = v
				await physics_frame
				t += 1.0 / 60.0
				out.sled_after = sled.linear_velocity.length()
			elif sled.global_position.z > 12.0 or (sled.linear_velocity.length() < 0.5 and t > 0.5):
				out.sled_after = sled.linear_velocity.length()
				return out
			elif sled.global_position.z < who.global_position.z - sled.HALF.y - 0.5:
				sled.linear_velocity = Vector3(0, sled.linear_velocity.y, v)   # 届くまで速さを保つ（板の摩擦は本物の雪より強い）
		else:
			out.apex = maxf(out.apex, who.global_position.y - ground_y)
			out.min_gap = minf(out.min_gap, who.global_position.y - ground_y)
			if fl.stage >= 2 and out.down_t == 0.0:
				out.down_t = t - hit_t
			if not fl.active():
				out.back_t = t - hit_t
				out.dist = Vector2(who.global_position.x - start.x, who.global_position.z - start.z).length()
				return out
	return out


func _speed_case() -> void:
	var counts := {"sack": [1], "small": [0, 1, 2], "mid": [0, 1, 3], "large": [0, 1, 8]}
	print("ソリ\t乗る人\t速さ\t飛ぶ\t高さ\t距離\t倒れるまで\t動けるまで\tソリの速さ（あと）")
	for n in counts[sled.kind]:
		_riders(n)
		for v in [3.0, 4.0, 4.6, 6.0, 8.0, 11.0, 14.0]:
			var r: Dictionary = await _shot_at(p, v, LAB_Y)
			print("%s\t%d\t%.1f\t%s\t%.2f\t%.1f\t%.2f\t%.2f\t%.1f" % [sled.kind, n, v, "飛ぶ" if r.flung else "—", r.apex, r.dist, r.down_t, r.back_t, r.sled_after])
			await _ticks(40)


func _rules_case() -> void:
	# 遅いソリ
	_riders(1)
	var r: Dictionary = await _shot_at(p, 3.0, LAB_Y)
	_say(not r.flung, "遅いソリ（3 m/s）では飛ばない")
	r = await _shot_at(p, 4.0, LAB_Y)
	_say(not r.flung, "押して出せる速さ（4 m/s）では飛ばない")
	r = await _shot_at(p, 8.0, LAB_Y)
	_say(r.flung, "速いソリ（8 m/s）では飛ぶ: 高さ %.2f m、距離 %.1f m、動けるまで %.2f 秒" % [r.apex, r.dist, r.back_t])
	await _ticks(40)

	# 乗っている本人
	_riders(0)
	_launch(sled, Vector3.ZERO)
	await _ticks(2)
	_stand(p, sled.global_position + Vector3(1.0, 0.2, 0))
	p.get_on()
	await _ticks(2)
	_launch(sled, Vector3(0, 0, 10))
	await _ticks(30)
	_say(p.mode == p.Mode.RIDE and not p.fling.active(), "乗っている本人は飛ばない")
	p.get_off()
	await _ticks(40)

	# つかんでいる本人（ソリの前の縁で 7 m/s。引きずられるだけ）
	_launch(sled, Vector3.ZERO)
	sled.linear_velocity = Vector3.ZERO
	await _ticks(2)
	var front: Vector3 = sled.to_global(Vector3(0, 0, -(sled.HALF.y + sled.STAND)))
	_stand(p, front)
	await _ticks(2)
	p.sled = sled
	p.rotation.y = PI
	p.grab()
	var gripped: bool = p.mode == p.Mode.GRIP
	sled.linear_velocity = -sled.global_basis.z * 7.0
	var flew := false
	for i in 12:
		await physics_frame
		flew = flew or p.fling.active()
	_say(gripped and not flew, "つかんでいる本人は、そのソリには飛ばされない（つかめた %s）" % gripped)
	if p.mode == p.Mode.GRIP:
		p.let_go()
	sled.linear_velocity = Vector3.ZERO
	await _ticks(90)

	# 横をかすめる
	_launch(sled, Vector3(0, 0, 8))
	_stand(p, Vector3(sled.HALF.x + 0.42, LAB_Y + 0.05, 2.0))
	flew = false
	for i in 150:
		await physics_frame
		flew = flew or p.fling.active()
		if sled.global_position.z < 0.0:
			sled.linear_velocity.z = 8.0
	_say(not flew, "横をかすめるだけなら飛ばない")
	await _ticks(10)

	# 跳んで越える（米袋のように低いソリの上を、足が高い所にある）
	_launch(sled, Vector3(0, 0, 8))
	_stand(p, Vector3(0, LAB_Y + 2.2, 4.0))
	flew = false
	for i in 20:
		await physics_frame
		flew = flew or (p.fling.active() and p.global_position.y > LAB_Y + 1.0 and sled.global_position.z > 1.0)
		p.global_position.y = LAB_Y + 2.2
		p.velocity = Vector3.ZERO
	_say(not flew, "足がソリより高ければ飛ばない")
	await _ticks(60)
	sled.linear_velocity = Vector3.ZERO

	# 紐を持っている人は、速いソリに追いつかれたら手を離して飛ぶ
	_launch(sled, Vector3.ZERO)
	await _ticks(2)
	var anchor: Vector3 = sled.to_global(sled.ROPE_ANCHOR)
	_stand(p, anchor)
	p.sled = sled
	p.grab_rope()
	var roped: bool = p.mode == p.Mode.ROPE
	sled.linear_velocity = -sled.global_basis.z * 4.8
	await _ticks(1)
	p.global_position = sled.to_global(Vector3(0, 0, -sled.HALF.y - 0.3))
	for i in 12:
		await physics_frame
		if p.fling.active():
			break
	_say(roped and p.fling.active() and p.mode == p.Mode.WALK, "紐を持っている人は手を離して飛ぶ（持てた %s）" % roped)
	sled.linear_velocity = Vector3.ZERO
	await _ticks(300)

	# 別のソリをつかんでいる人は、手を離して飛ぶ
	var other: RigidBody3D = Sled.new()
	other.kind = "mid"
	other.name = "OtherSled"
	main.add_child(other)
	await _ticks(2)
	_launch(other, Vector3.ZERO, Vector3(0, LAB_Y + 0.05, 8.0))
	other.global_transform = Transform3D(Basis(), Vector3(1.65, LAB_Y + 0.05, 4.0))   # つかむ人の立つ所（x = 0.3）がソリの通り道に入る
	other.linear_velocity = Vector3.ZERO
	await _ticks(2)
	_launch(sled, Vector3(0, 0, 9))
	_stand(p, other.to_global(Vector3(-(other.HALF.x + other.STAND), 0, 0)))
	await _ticks(1)
	p.sled = other
	p.grab()
	p.global_position = other.to_global(Vector3(-(other.HALF.x + other.STAND), 0, 0))
	roped = p.mode == p.Mode.GRIP
	flew = false
	for i in 200:
		await physics_frame
		flew = flew or p.fling.active()
		if flew:
			break
		sled.linear_velocity.z = 9.0
	_say(roped and flew and not other.holders.has(p), "別のソリをつかんでいる人は、手を離して飛ぶ（つかめた %s 飛んだ %s 人 %s ソリ %s %s）" % [roped, flew, p.global_position, sled.global_position, sled.linear_velocity])
	if p.mode == p.Mode.GRIP:
		p.let_go()
	p.sled = sled
	other.queue_free()
	sled.linear_velocity = Vector3.ZERO
	await _ticks(330)
	_say(not p.fling.active(), "最後は動ける")
	await _push_up_case()


## 押して坂を登るソリの前に立っていても飛ばない（力は sled.push をそのまま呼ぶ）。登りでは、速くても（6 m/s）飛ばない
func _push_up_case() -> void:
	_riders(0)
	var z := 30.0
	sled.reset_to(Vector3(0, main.height(0, z) + 0.3, z))
	sled.parked = false
	sled.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), sled.global_position)
	var flew := false
	var top := 0.0
	var pusher: Node3D = _dummy.new()
	main.add_child(pusher)
	for i in 240:
		var at: Vector3 = sled.global_position + Vector3(0, 0, -(sled.HALF.y + 0.6))
		if i % 60 == 0:
			_stand(p, Vector3(at.x, main.height(at.x, at.z) + 0.05, at.z))
		for k in 3:
			sled.push(Vector3(0, 0, -1), sled.global_position + Vector3(0.5 * (k - 1), 0.4, sled.HALF.y), pusher)
		if i == 120:
			sled.linear_velocity = Vector3(0, 2.4, -5.5)   # 登りで速くても
		await physics_frame
		top = maxf(top, sled.linear_velocity.length())
		flew = flew or p.fling.active()
	_say(not flew, "押して登っているソリでは飛ばない（いちばん速くて %.1f m/s）" % top)
	pusher.queue_free()


func _slope_case() -> void:
	# 頂上の近くから滑り、丘の途中で立っている人に当てる
	var r := 8.0
	_riders(2)
	sled.reset_to(Vector3(0, main.height(0, r) + 0.3, r))
	_riders(2)
	sled.parked = false
	var stand_z := 30.0
	_stand(p, Vector3(0, main.height(0, stand_z) + 0.05, stand_z))
	sled.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), sled.global_position)
	var low := 99.0
	var hit := false
	var vmax := 0.0
	var t := 0.0
	var start := Vector3.ZERO
	while t < 25.0:
		await physics_frame
		t += 1.0 / 60.0
		sled.lean(0.0, true)
		if not hit:
			vmax = maxf(vmax, sled.linear_velocity.length())
			if sled.global_position.x * sled.global_position.x > 9.0:   # 向きがそれたら、人を前へ置き直す
				var at: Vector3 = sled.global_position + sled.linear_velocity.normalized() * 4.0
				_stand(p, Vector3(at.x, main.height(at.x, at.z) + 0.05, at.z))
			if p.fling.active():
				hit = true
				start = p.global_position
				print("速さ %.1f m/s で当たった (%.1f, %.1f)" % [sled.linear_velocity.length(), start.x, start.z])
		else:
			low = minf(low, p.global_position.y - main.height(p.global_position.x, p.global_position.z))
			if not p.fling.active():
				break
	_say(hit, "丘を滑ってきたソリに当たった（最高 %.1f m/s）" % vmax)
	_say(low > -0.5, "雪面の下へ抜けない（いちばん低い所 %.2f m）" % low)
	_say(not p.fling.active() and t < 25.0, "起き上がった（%.1f m 先まで飛んだ）" % start.distance_to(p.global_position))
	await _ticks(20)
	# 起き上がったら W で歩ける
	var before := p.global_position
	_press(KEY_W, true)
	await _ticks(60)
	_press(KEY_W, false)
	var walked := Vector2(p.global_position.x - before.x, p.global_position.z - before.z).length()
	_say(walked > 0.8, "起き上がったあと W で歩ける（1 秒で %.1f m）" % walked)


func _press(k: Key, on: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = on
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _edge_case() -> void:
	# 丘の西の端（見た目の地面の端から 8 m）で、端へ向けて飛ばす
	var x: float = -main.SIZE * 0.5 + 8.0
	var z := 40.0
	var g: float = main.height(x, z)
	_riders(1)
	sled.global_transform = Transform3D(Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP), Vector3(x + 5.0, g + 0.3, z))
	sled.linear_velocity = Vector3(-14, 0, 0)
	sled.parked = false
	_stand(p, Vector3(x, g + 0.05, z))
	var least := 99.0
	var flew := false
	for i in 300:
		await physics_frame
		flew = flew or p.fling.active()
		least = minf(least, main.edge_gap(p.global_position.x, p.global_position.z))
	_say(flew, "端の近くでも飛ぶ")
	_say(least > 0.0, "地面の外へ出ない（端までいちばん近くて %.1f m）" % least)


func _bot_case() -> void:
	var bots := get_nodes_in_group_of("bots")
	if bots.is_empty():
		_say(false, "仲間がいない（--bots=1）")
		return
	var b: CharacterBody3D = bots[0]
	_riders(1)
	await _ticks(2)
	var moved_after := false
	var r: Dictionary = await _shot_at(b, 8.0, LAB_Y)
	_say(r.flung, "立っている仲間は飛ぶ: 高さ %.2f m、距離 %.1f m、動けるまで %.2f 秒" % [r.apex, r.dist, r.back_t])
	_say(not b.fling.active(), "仲間が起き上がった")
	sled.linear_velocity = Vector3.ZERO
	var at: Vector3 = b.global_position
	await _ticks(180)
	moved_after = b.global_position.distance_to(at) > 0.5 or b.handle != Vector3.INF
	_say(moved_after, "起き上がったあと、また動く（%.1f m 動いた、つかんだ %s）" % [b.global_position.distance_to(at), b.handle != Vector3.INF])


func get_nodes_in_group_of(g: String) -> Array:
	return root.get_tree().get_nodes_in_group(g)
