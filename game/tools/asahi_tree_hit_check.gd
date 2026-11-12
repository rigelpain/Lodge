extends SceneTree
## 旭ヶ丘の林の木に、ソリが当たるかを確かめる（数字だけ）。木の数と幹の当たりの数を出し、開けた所から林へ、いくつかの向きで
## 1 人乗りのソリを決まった速さでまっすぐ送り込んで、木に当たって打ち上がるまでに林の中を何 m 進んだかを出す。
##   Godot --headless --path game -s res://tools/asahi_tree_hit_check.gd -- --world=asahigaoka --no-player --no-sound

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var t0 := Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	print("世界を作るのにかかった時間: %d ms" % (Time.get_ticks_msec() - t0))
	_run.call_deferred()


func _run() -> void:
	for i in 30:
		await physics_frame
	var site: Node3D = main.get_node("Site")
	var trees := 0
	for w in site.find_children("Woods_*", "MultiMeshInstance3D", true, false):
		if String(w.name).ends_with("_felt") or "prop_" in String(w.name):
			pass
		trees += (w as MultiMeshInstance3D).multimesh.instance_count
	var bodies := root.get_tree().get_nodes_in_group("tree_hits")
	var nshape := 0
	for b in bodies:
		nshape += (b as StaticBody3D).get_shape_owners().size()
	print("木の形（部品ごとに数えた延べ）: %d  幹の当たり: %d（体 %d）" % [trees, nshape, bodies.size()])
	# 所ごとに、半径 15 m の中の木の本数と幹の当たりの数を比べる（林の島のまんなか・島の縁・北東の林の中・そりコースの南の林の縁）
	var where := {"林の島のまんなか": Vector2(-170, -75), "林の島の縁": Vector2(-140, -100), "北東の林の中": Vector2(-60, -190), "そりコースの南の縁": Vector2(-70, 100), "西の林の奥": Vector2(-360, -80)}
	var seen := {}
	for w in site.find_children("Woods_*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (w as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var o := mm.get_instance_transform(i).origin
			seen[Vector2i(roundi(o.x * 2.0), roundi(o.z * 2.0))] = Vector2(o.x, o.z)   # 部品ごとの重なりを 1 本に（0.5 m の升）
	var trunks: Array[Vector2] = []
	for b in bodies:
		for own in (b as StaticBody3D).get_shape_owners():
			var o: Vector3 = (b as StaticBody3D).shape_owner_get_transform(own).origin
			trunks.append(Vector2(o.x, o.z))
	print("木（おおよその本数）: %d  幹の当たり: %d" % [seen.size(), trunks.size()])
	for name in where:
		var c: Vector2 = where[name]
		var nt := 0
		for q in seen.values():
			if (q as Vector2).distance_to(c) < 15.0:
				nt += 1
		var nh := 0
		for q in trunks:
			if q.distance_to(c) < 15.0:
				nh += 1
		print("  %s (%.0f, %.0f): 木 %d 本・当たり %d" % [name, c.x, c.y, nt, nh])
	# 物理の 1 コマの重さ（ソリを置いただけで 300 コマ）
	var t0 := Time.get_ticks_usec()
	for i in 300:
		await physics_frame
	print("300 コマ: %.1f ms/コマ（待ち時間こみ。比べる用）  物理 %.2f ms" % [(Time.get_ticks_usec() - t0) / 300000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	# 林へ送り込む: [始める所, 向き]。主コースの縁から林の島へ、北東の林へ、そりコースの南の林へ、林の島の奥へ
	var runs := [[Vector2(-150, -95), Vector2(-0.62, 0.78)], [Vector2(-120, -135), Vector2(0.62, -0.78)], [Vector2(-70, 80), Vector2(0, 1)],
			[Vector2(-250, -60), Vector2(1, 0)], [Vector2(-60, -30), Vector2(-1, 0.2)], [Vector2(-180, -150), Vector2(-0.3, 1)]]
	var hit_n := 0
	for r in runs:
		if await _send(r[0], (r[1] as Vector2).normalized(), float(args.get("speed", "12"))):
			hit_n += 1
	print("当たった: %d / %d" % [hit_n, runs.size()])
	quit()


func _send(from: Vector2, dir: Vector2, speed: float) -> bool:
	var sled: RigidBody3D = main.sled
	const SRC := """extends Node3D
var sled: Node3D
var side := 1
var id := 0
func get_off() -> void:
	sled.dismount(self)
"""
	var gs := GDScript.new()
	gs.source_code = SRC
	gs.reload()
	sled.crashed = false
	sled.set("_crash_cool", 0.0)
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.6, from.y))
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	var d := Node3D.new()
	d.set_script(gs)
	d.sled = sled
	main.add_child(d)
	sled.mount(d)
	var w := 0.0
	var gone := 0.0
	var in_woods := 0.0
	var forest := FileAccess.get_file_as_bytes("res://asahigaoka/forest.bin")
	var crashed := false
	while w < 12.0:
		# 決まった速さでまっすぐ（坂や抵抗によらず、林の中をどこまで抜けるかを見る）
		var v := sled.linear_velocity
		sled.linear_velocity = Vector3(dir.x * speed, v.y, dir.y * speed)
		await physics_frame
		w += 1.0 / 60.0
		var p := sled.global_position
		var c: int = clampi(int((p.z + 650.0) / 4.0), 0, 255) * 256 + clampi(int((p.x + 600.0) / 4.0), 0, 255)
		gone += speed / 60.0
		if forest[c] > 128:
			in_woods += speed / 60.0
		if sled.crashed or sled.riders.is_empty():
			crashed = true
			break
	var p2 := sled.global_position
	print("  (%.0f, %.0f) から (%.1f, %.1f) の向き・%.0f m/s: %s  林の中を %.0f m 進んだ（全部で %.0f m、(%.0f, %.0f) まで）" % [
			from.x, from.y, dir.x, dir.y, speed, "木に当たって放り出された" if crashed else "当たらずに抜けた", in_woods, gone, p2.x, p2.z])
	if d.is_inside_tree() and sled.riders.has(d):
		sled.dismount(d)
	d.queue_free()
	for i in 240:   # 打ち上がって落ち着くまで待つ
		await physics_frame
	return crashed
