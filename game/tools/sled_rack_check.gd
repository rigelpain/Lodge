extends SceneTree
## ソリ屋を外の下屋へ移したこと（ミシンと屋根の間・歩いて買える・縫ったソリが外へ出られる・通り道）と、
## ソリの立てかけ台（戻す・持ち出す・断る）を確かめる（2026-11-04）。
##   Godot --path game --headless --fixed-fps 30 -s res://tools/sled_rack_check.gd -- --bots=1 --no-pip

const LEAN_X_OUT := -30.18
const LEAN_Z_WALL := 4.725
const LEAN_Z_OUT := 3.6
const LEAN_X_WALL := -21.816

var main: Node3D
var fails := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(sec: float) -> void:
	var until := Engine.get_physics_frames() + int(sec * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < until:
		await physics_frame


func _say(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "  NG  ") + what)
	if not ok:
		fails += 1


func _lodge(x: float, y: float, h := 0.0) -> Vector3:
	return main.get_node("Lodge").to_global(Vector3(x, h, -y))


## 人を、ロッジの座標 (x, y) の雪の上に立たせて、ロッジの座標で (lx, ly) の方を向かせる
func _put(who: Node3D, x: float, y: float, lx: float, ly: float) -> void:
	var p := _lodge(x, y)
	p.y = main.height(p.x, p.z) + 0.1
	who.global_position = p
	var t := _lodge(lx, ly)
	who.global_rotation.y = atan2(-(t.x - p.x), -(t.z - p.z))


func _clear_path(a: Vector3, b: Vector3, size: Vector3, skip: Array) -> float:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size
	q.shape = box
	var flat := (b - a)
	q.transform = Transform3D(Basis(Vector3.UP, atan2(-flat.x, -flat.z)), a)
	q.motion = flat
	q.exclude = skip
	return main.get_world_3d().direct_space_state.cast_motion(q)[0]


func _run() -> void:
	for i in 30:
		await process_frame
	var p = main.player
	var craft = main.craft
	var rack = main.sled_rack
	if p == null or craft == null or main.sewing == null or rack == null:
		print("あなた・工房・ミシン・台のどれかがない")
		quit(1)
		return
	var machine: Node3D = main.sewing.machine
	# ---- ミシンと屋根
	print("ミシンと屋根:")
	var lodge: Node3D = main.get_node("Lodge")
	var inv := lodge.global_transform.affine_inverse()
	var worst := INF
	for mi in machine.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bb: AABB = m.global_transform * m.get_aabb()
		for k in 8:
			var c: Vector3 = inv * bb.get_endpoint(k)
			var roof := LEAN_Z_OUT + (c.x - LEAN_X_OUT) * (LEAN_Z_WALL - LEAN_Z_OUT) / (LEAN_X_WALL - LEAN_X_OUT)
			worst = minf(worst, roof - c.y)
	_say(worst > 0.2, "ミシンの上と屋根のすき間 %.2f m（外の桁の下より内）" % worst)
	var gd: float = main.height(machine.global_position.x, machine.global_position.z)
	_say(absf(gd - machine.global_position.y) < 0.05, "ミシンの足もとと雪の面の差 %.3f m" % (gd - machine.global_position.y))
	var rk: float = main.height(rack.global_position.x, rack.global_position.z)
	_say(absf(rk - rack.global_position.y) < 0.05, "台の足もとと雪の面の差 %.3f m" % (rk - rack.global_position.y))
	# ---- 大を立てかけた鼻と屋根
	var at_large: Transform3D = rack.lean_at("large", 0.0)
	var nose: Vector3 = inv * (at_large * Vector3(0, 0.45, -2.45))
	var roof_n := LEAN_Z_OUT + (nose.x - LEAN_X_OUT) * (LEAN_Z_WALL - LEAN_Z_OUT) / (LEAN_X_WALL - LEAN_X_OUT)
	_say(roof_n - nose.y > 0.1 and nose.x < LEAN_X_WALL, "大の鼻: x %.2f 高さ %.2f、屋根 %.2f（壁は x %.2f）" % [nose.x, nose.y, roof_n, LEAN_X_WALL])
	# ---- 歩いて買う
	print("ソリ屋で買う・縫う:")
	await _wait(0.5)
	var counter: Node3D = lodge.get_node_or_null("Bandai_counter_patch")
	var cl := lodge.to_local(counter.global_position)
	_put(p, cl.x - 1.2, -cl.z, cl.x, -cl.z)
	await _wait(0.3)
	_say(main.shopkeeper.can_talk(p) and p.shop_near(), "番台の前で F で話しかけられる（距離 %.2f m）" % p.global_position.distance_to(main.shopkeeper.global_position))
	craft.wallets[p.id] = 5000
	_say(craft.send({"kind": "buy", "who": p.id, "item": {"kind": "pattern", "sled": "mid"}}), "中の型紙を買う")
	_say(craft.send({"kind": "buy", "who": p.id, "item": {"kind": "fabric", "fabric": "red"}}), "布を買う")
	var stand: Vector3 = machine.to_global(main.sewing._mark["stand"])
	var sl := lodge.to_local(stand)
	var mp := lodge.to_local(machine.global_position)
	_put(p, sl.x, -sl.z, mp.x, -mp.z)
	await _wait(0.3)
	_say(p.machine_near(), "ミシンの前で F で画面を開ける")
	var bag: Array = craft.bags[p.id]
	var ps := -1
	var fs := -1
	for i in bag.size():
		if bag[i].get("kind") == "pattern":
			ps = i
		elif bag[i].get("kind") == "fabric":
			fs = i
	_say(craft.send({"kind": "sew", "who": p.id, "pattern": bag[ps].duplicate(), "fabric": bag[fs].duplicate(), "pattern_slot": ps, "fabric_slot": fs}), "縫い始める")
	var n0: int = craft.sleds.size()
	var t0 := Time.get_ticks_msec()
	while craft.sleds.size() == n0 and Time.get_ticks_msec() - t0 < 5000:
		await _wait(0.5)
	if craft.sleds.size() == n0:
		print("  （足踏みなしでは縫い上がらないので、sewn を直接出す）")
		var fwd: Vector3 = -machine.global_basis.z
		craft.send({"kind": "sewn", "who": p.id, "sled": "mid", "fabric": "red", "at": machine.to_global(Vector3(main.sewing._mark["stand"].x, 0, main.sewing._mark["out"].z - 2.8 * 0.5 + 0.6)), "yaw": atan2(-fwd.x, -fwd.z)})
	await _wait(0.5)
	var id: int = craft.sleds.keys()[craft.sleds.size() - 1]
	var s: RigidBody3D = craft.sleds[id]
	_say(int(s.owner_id) == p.id, "縫ったソリの持ち主があなた")
	var sll := lodge.to_local(s.global_position)
	print("  ソリの出た所: x %.2f y %.2f、向きの前 (%.2f, %.2f)" % [sll.x, -sll.z, s.global_basis.z.x, s.global_basis.z.z])
	# 出た所から西（柱のあいだ）へ、ソリの箱がまっすぐ抜けられるか
	var k: Dictionary = s.KINDS.mid
	var box_at: Vector3 = s.global_position + Vector3.UP * (k.box.y * 0.5 + 0.2)
	var west: Vector3 = _lodge(-36.0, -sll.z, box_at.y) - box_at
	west.y = 0.0
	var frac := _clear_path(box_at, box_at + west, Vector3(k.box.x, k.box.y, k.box.z), [s.get_rid(), p.get_rid()])
	_say(frac >= 0.999, "縫ったソリが柱のあいだを西の雪へ抜けられる（%.0f %%）" % (frac * 100.0))
	# ---- 通り道
	print("下屋の通り道:")
	var man := Vector3(0.8, 1.2, 0.8)
	for w in [["南の口 → 北（ソリ屋の前）", Vector2(-27.8, -14.0), Vector2(-27.8, 9.0)],
			["台の前 → 西のガラスの戸", Vector2(-27.0, 11.4), Vector2(-23.0, 11.4)],
			["南の口 → 番台の前", Vector2(-27.6, -13.5), Vector2(-27.3, -8.0)]]:
		var a := _lodge(w[1].x, w[1].y, 0.8)
		var b := _lodge(w[2].x, w[2].y, 0.8)
		var f := _clear_path(a, b, man, [p.get_rid(), s.get_rid()])
		_say(f >= 0.999, "%s（%.0f %%）" % [w[0], f * 100.0])
	# ---- 台
	print("立てかけ台:")
	var bot: Node3D = null
	for c in main.get_children():
		if c is CharacterBody3D and c != p:
			bot = c
	# 山へ置いてくる
	var far := _lodge(-18.0, -40.0)
	far.y = main.height(far.x, far.z) + 0.3
	s.reset_to(far)
	await _wait(0.2)
	_put(p, -27.5, 2.0, -24.6, 2.0)
	await _wait(0.2)
	var rt: Array = p.rack_target()
	_say(rt.size() == 2 and rt[0] == s and rt[1] == "rack_in", "台の前で F: 山のソリを戻す案内")
	# 触っていると断る
	s.riders.append(bot)
	_say(not craft.send({"kind": "rack_in", "who": p.id, "id": id}), "乗っている人がいると断る")
	_say(p.rack_refused(), "そのときは『いま呼べない』の絵")
	s.riders.erase(bot)
	s.holders[bot] = Vector3.ZERO
	_say(not craft.send({"kind": "rack_in", "who": p.id, "id": id}), "つかんでいる人がいると断る")
	s.holders.erase(bot)
	s.rope_holder = bot
	_say(not craft.send({"kind": "rack_in", "who": p.id, "id": id}), "紐を持っている人がいると断る")
	s.rope_holder = null
	s.peg = Node3D.new()
	s.add_child(s.peg)
	_say(not craft.send({"kind": "rack_in", "who": p.id, "id": id}), "ペグで留めていると断る")
	s.peg.free()
	s.peg = null
	_say(s.global_position.distance_to(far) < 2.0, "断られたソリは山のまま（動かない）")
	if bot:
		_say(not craft.send({"kind": "rack_in", "who": int(bot.get("id")), "id": id}), "持ち主でない人は戻せない")
	var ow: int = s.owner_id
	s.owner_id = -1
	_say(not craft.send({"kind": "rack_in", "who": p.id, "id": id}), "名札のない（持ち主のいない）ソリは対象外")
	s.owner_id = ow
	_put(p, -40.0, 2.0, -24.6, 2.0)
	await _wait(0.1)
	_say(not craft.send({"kind": "rack_in", "who": p.id, "id": id}), "台から遠いと断る")
	_put(p, -27.5, 2.0, -24.6, 2.0)
	await _wait(0.1)
	# 戻す
	_say(craft.send({"kind": "rack_in", "who": p.id, "id": id}), "だれも触っていなければ戻せる")
	_say(s.racked and s.freeze and craft.racked.has(id), "台に立てかかり、止まっている")
	var ang: float = rad_to_deg(acos(s.global_basis.y.dot(Vector3.UP)))
	_say(absf(ang - 60.0) < 35.0, "傾き %.0f°（上向きとの角度。立てかけて 30° 前後）" % ang)
	_say(s.take_handle(p, Vector3.ZERO) == false and s.take_rope(p) == false and s.mount(p) == Vector3.INF, "台のソリはつかめない・紐を持てない・乗れない")
	_say(not craft.send({"kind": "rack_in", "who": p.id, "id": id}), "台のソリをもう一度戻すのは断る")
	await _wait(1.8)
	_say(s.visible, "包みが飛んだあと、台に見える")
	# 別のソリも詰まる（置き場が重ならない）
	var u0: float = craft.racked[id]
	var taken: Array = craft._rack_taken()
	var u1: float = rack.fit("large", taken)
	_say(absf(u1 - u0) >= (1.7 + 2.4) / 2.0 - 0.01, "次の大の置き場は重ならない（%.2f と %.2f）" % [u0, u1])
	var full := []
	for i in 5:
		full.append([rack.fit("large", full), 2.4])
	_say(is_nan(rack.fit("large", full)), "大 5 台でいっぱい（6 台目は断る）")
	# 通信: あとから来た人の画面に、台のソリがそのまま出る（ホストの様子を読み直す）
	var snap: Dictionary = craft.snapshot()
	craft.load_snapshot(snap)
	await _wait(0.2)
	s = craft.sleds[id]
	_say(s.racked and craft.racked.has(id), "あとから来た人（様子の読み直し）にも台に見える")
	# つなぐ側がなぞる（ホストの決めた置き場どおりに持ち出す）
	_put(p, -27.5, 2.0, -24.6, 2.0)
	p.global_rotation.y = atan2(-(s.global_position.x - p.global_position.x), -(s.global_position.z - p.global_position.z))
	await _wait(0.1)
	rt = p.rack_target()
	_say(rt.size() == 2 and rt[1] == "rack_out", "台のソリの方を見て F: 持ち出す案内")
	_say(craft.send({"kind": "rack_out", "who": p.id, "id": id}), "持ち出せる")
	await _wait(1.2)
	_say(not s.racked and not s.freeze and not craft.racked.has(id), "雪の上に降りて、また動く")
	var ll := lodge.to_local(s.global_position)
	print("  置かれた所: x %.2f y %.2f 高さ %.2f" % [ll.x, -ll.z, ll.y])
	# 持ち出したソリのそばで F: 台へ戻さず、つかむ
	var by: Vector3 = s.global_position + s.global_basis.x * (s.HALF.x + 0.4)
	by.y = p.global_position.y
	p.global_position = by
	p.global_rotation.y = atan2(-rack.global_basis.z.x, -rack.global_basis.z.z) + PI
	await _wait(0.5)
	print("  そばに立った所: 台から %s、つかむソリ %s" % [rack.to_local(p.global_position), p.sled == s])
	_say(rack.can_use(p) and p.rack_target().is_empty(), "持ち出したソリのそばで台を向いても、F はつかむほう")
	_say(s.take_handle(p, Vector3(0, 0, 1)), "またつかめる")
	s.release_handle(p)
	_say(s.global_position.distance_to(_lodge(-27.5, 2.0)) < 6.0, "台の前にある")
	print("NG の数: %d" % fails)
	quit(1 if fails > 0 else 0)
