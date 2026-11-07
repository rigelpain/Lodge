extends SceneTree
## ソリが雪の塊や木にぶつかる確かめ（数字だけ出す）。大きさは main.gd と同じ --sled= で選ぶ。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/crash_check.gd -- --sled=mid --no-sound --roam-bots=0 --lodge-bots=0
## 乗るのは本物のあなた（1 席目）と、形の人（席が余れば --full で満席に）。
##   丘の頂上からロッジの入口へ滑る / 丘の木へ 10 m/s で当てる / 木へ 3 m/s で当てる（飛ばない） / 雪の塊へ押して当てる（飛ばない）
## 当たった速さ、ソリと人の高さ、着いたときの向き、着いてから滑った距離、止まった所、起き直るかを出す。

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
var id := -1
var seat := Vector3.ZERO
func get_off() -> void:
	sled.dismount(self)
"""

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
	await create_timer(1.0).timeout
	sled = main.sled
	_rows.append("| 場面 | ソリ | 飛んだか | 当たった速さ | ソリの高さ | 人の高さ | 人の飛んだ距離 | 着いたときの上向き | 着いてから滑った | 止まった所 | ロッジの当たりまで | 止まるまで | 起き直った |")
	_rows.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	var door: Vector2 = main.lodge_to_world(Vector2(main.PATH_X, 17.0))
	for at in [Vector2(0.0, 0.0), Vector2(-10.0, 0.0), Vector2(14.0, 0.0)]:
		var aim: Vector2 = main.lodge_to_world(Vector2(main.PATH_X + at.x, 17.0))
		await _ride_at("丘 → ロッジ（%+d m）" % int(at.x), aim.normalized() * 2.0, aim, 0.0)
	var p := _hill_tree()
	if p != Vector3.INF:
		var from := Vector2(p.x, p.z) - Vector2(p.x, p.z).normalized() * 9.0
		await _ride_at("木へ 10 m/s", from, Vector2(p.x, p.z), 10.0)
		await _ride_at("木へ 3 m/s", Vector2(p.x, p.z) - Vector2(p.x, p.z).normalized() * 6.0, Vector2(p.x, p.z), 3.0)
	await _pushed_through()
	print("\n".join(_rows))
	quit()


func _hill_tree() -> Vector3:
	for b in get_nodes_in_group("tree_hits"):
		for own in b.get_shape_owners():
			var p: Vector3 = b.global_transform * b.shape_owner_get_transform(own).origin
			if Vector2(p.x, p.z).length() > 34.0 and Vector2(p.x, p.z).length() < 46.0:
				return p
	return Vector3.INF


func _ride_at(label: String, from: Vector2, to: Vector2, v0: float) -> void:
	var pl: CharacterBody3D = main.player
	sled.crashed = false
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	var dir := (to - from).normalized()
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	await create_timer(0.8).timeout
	pl.global_position = sled.global_position + Vector3.UP
	pl.get_on()
	var rs := []
	if args.has("full"):
		for i in sled.SEATS.size() - 1:
			var d := Node3D.new()
			d.set_script(_dummy)
			d.sled = sled
			main.add_child(d)
			d.seat = sled.mount(d)
			rs.append(d)
	if v0 > 0.0:
		sled.linear_velocity = Vector3(dir.x, 0, dir.y) * v0
	var t := 0.0
	var hit_v := 0.0
	var top_s := 0.0
	var top_p := 0.0
	var flew := 0.0
	var hit_at := Vector3.ZERO
	var land_up := INF
	var land_at := Vector3.ZERO
	var near := INF
	var hit := false
	var was := sled.linear_velocity
	var stop_t := -1.0
	while t < 90.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var at: Vector3 = sled.global_position
		var g: float = main.height(at.x, at.z)
		if not hit:
			if not sled.crashed:
				was = sled.linear_velocity
				var f: Vector3 = -sled.global_basis.z
				f.y = 0
				var want := Vector3(to.x - at.x, 0, to.y - at.y).normalized()
				var err := atan2(f.normalized().cross(want).y, f.normalized().dot(want))
				sled.lean(clampf(-err * 0.5, -1.0, 1.0), sled.linear_velocity.length() < 1.5)
				if t > 12.0 and sled.linear_velocity.length() < 0.2:
					break
			else:
				hit = true
				hit_v = Vector2(was.x, was.z).length()
				hit_at = at
		if hit:
			top_s = maxf(top_s, at.y - g)
			if land_up == INF and t > 0.3 and at.y - g < 1.0 and sled.linear_velocity.y <= 0.0:
				land_up = sled.global_basis.y.y
				land_at = at
			var pp: Vector3 = pl.global_position
			top_p = maxf(top_p, pp.y - main.height(pp.x, pp.z))
			if pl.fling.active():
				flew = maxf(flew, Vector2(pp.x - hit_at.x, pp.z - hit_at.z).length())
			if not sled.crashed:
				stop_t = t
				break
	await create_timer(2.5).timeout   # 起き直るのを待つ
	var q: Vector3 = sled.global_position
	# ロッジの当たりまで: ロッジの座標で、ならした範囲の正面の縁からの距離
	var l: Vector2 = q.x * Vector2.ONE * 0.0
	var d: Vector2 = Vector2(q.x, q.z) - main.LODGE_POS
	var c := cos(main.LODGE_YAW)
	var s := sin(main.LODGE_YAW)
	l = Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	_rows.append("| %s | %s | %s | %.1f | %.1f m | %.1f m | %.1f m | %s | %s | (%.0f, %.0f) | 正面から %.0f m | %s | %s |" % [label, sled.kind, "はい" if hit else "いいえ", hit_v, top_s, top_p, flew,
		"%.2f" % land_up if land_up != INF else "—", "%.0f m" % (q - land_at).length() if land_up != INF else "—", q.x, q.z, l.y - 21.0, "%.0f s" % stop_t if stop_t >= 0.0 else "—", "はい (%.2f)" % sled.global_basis.y.y if sled.global_basis.y.y > 0.9 else "いいえ (%.2f)" % sled.global_basis.y.y])
	if pl.mode == pl.Mode.RIDE:
		pl.get_off()
	while pl.fling.active():
		await physics_frame
	for r in rs:
		if sled.riders.has(r):
			sled.dismount(r)
		r.queue_free()


## 押しているソリは雪の塊を通り抜ける（飛ばない）
func _pushed_through() -> void:
	var lump: Node3D = get_nodes_in_group("crash_lumps")[4]
	var p := lump.global_position
	var dir := (Vector2(main.LODGE_POS.x, main.LODGE_POS.y) - Vector2(p.x, p.z)).normalized()
	var from := Vector2(p.x, p.z) - dir * 5.0
	sled.crashed = false
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	await create_timer(0.8).timeout
	var d := Node3D.new()
	d.set_script(_dummy)
	main.add_child(d)
	var t := 0.0
	var w := Vector3(dir.x, 0, dir.y)
	var top := 0.0
	while t < 20.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		sled.push(w, sled.to_global(Vector3(0, 0.2, sled.HALF.y)), d, 1.0)
		top = maxf(top, sled.linear_velocity.length())
		if sled.global_position.distance_to(p) < 0.5 or (sled.global_position - p).dot(w) > 4.0:
			break
	_rows.append("| 雪の塊へ押す | %s | %s | %.1f | | | | | | | | | |" % [sled.kind, "はい" if sled.crashed else "いいえ", top])
	sled.release_handle(d)
	d.queue_free()
