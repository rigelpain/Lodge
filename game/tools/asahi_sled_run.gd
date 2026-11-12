extends SceneTree
## 旭ヶ丘で、ソリに 1 人乗せて放し、速さを測る（数字だけ。画面は使わない）。そりコースの上からと、主コースの上から。
##   Godot --headless --path game -s res://tools/asahi_sled_run.gd -- --world=asahigaoka --no-player --no-sound [--sled=small|mid|large|sack] [--glide=1 --pull=0]
## --glide・--pull は確かめ用（sled.gd の glide・pull を上書きして、直す前の値と比べる）

const Sled := preload("res://sled.gd")

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 30:
		await physics_frame
	if args.has("glide"):
		Sled.glide = float(args["glide"])
	if args.has("pull"):
		Sled.pull = float(args["pull"])
	print("ソリ %s  glide %.2f  pull %.2f" % [main.sled.kind, Sled.glide, Sled.pull])
	# そりコース: 南の斜面の上（-120, 70）から、麓（0, 35）の向きへ。主コース: 降り場の下（リフトの線の北東 30 m）から乗り場の向きへ
	if args.has("things"):   # 確かめ用: そりコースのあたりの当たり（柱・ネット・札）の所を出す
		for cs in main.get_node("Site/Slope/SlopeColliders").get_children():
			var q: Vector3 = (cs as Node3D).global_position
			if q.x > -160 and q.x < 40 and q.z > 20 and q.z < 110:
				print("  当たり (%.0f, %.0f) %s" % [q.x, q.z, (cs as CollisionShape3D).shape.get_class()])
	await _ride("そりコース", Vector2(-120, 76), Vector2(0, 42))
	await _ride("主コース", Vector2(-200, -190), Vector2(18, -18))
	quit()


func _ride(name: String, from: Vector2, to: Vector2) -> void:
	var sled: RigidBody3D = main.sled
	const SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
	var gs := GDScript.new()
	gs.source_code = SRC
	gs.reload()
	var dir := (to - from).normalized()
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.6, from.y))
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	var d := Node3D.new()
	d.set_script(gs)
	d.sled = sled
	main.add_child(d)
	sled.mount(d)
	sled.linear_velocity = Vector3(dir.x, 0, dir.y) * 1.5   # 走って乗った勢い
	var w := 0.0
	var top := 0.0
	var t5 := -1.0
	var t10 := -1.0
	var t20 := -1.0
	var still := 0.0
	var y0 := sled.global_position.y
	while w < 90.0:
		await physics_frame
		w += 1.0 / 60.0
		var v := sled.linear_velocity.length()
		top = maxf(top, v)
		if t5 < 0.0 and v >= 5.0: t5 = w
		if t10 < 0.0 and v >= 10.0: t10 = w
		if t20 < 0.0 and v >= 20.0: t20 = w
		still = still + 1.0 / 60.0 if v < 0.3 else 0.0
		if still > 2.0 or sled.crashed:
			break
	var p := sled.global_position
	print("%s: いちばん速いとき %.1f m/s（時速 %.0f km）  5 m/s まで %s 秒・10 m/s まで %s 秒・20 m/s まで %s 秒  %.0f 秒で (%.0f, %.0f) に%s  下った高さ %.0f m" % [
			name, top, top * 3.6, _s(t5), _s(t10), _s(t20), w, p.x, p.z, "打ち上がった" if sled.crashed else "止まった", y0 - p.y])
	if d.is_inside_tree():
		sled.dismount(d)
	d.queue_free()
	sled.crashed = false
	for i in 10:
		await physics_frame


func _s(t: float) -> String:
	return "%.1f" % t if t >= 0.0 else "—"
