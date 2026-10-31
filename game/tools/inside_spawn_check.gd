extends SceneTree
## --spawn=inside（食堂の中から始める）の立ち位置が、物の当たりと重ならないか確かめる。
## 雪だるまの冷蔵庫と、ミシン・冷蔵庫・アイロン台・プレス機・乾燥機のあいだを本物の W キーで歩けるかも確かめる（確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/inside_spawn_check.gd -- --spawn=inside --bots=0 --no-pip --dir=/path/shots
## （--spawn=inside は main.gd が読む。音を切ると立ち位置が効かないので --no-sound は付けない）
## 場所はロッジの座標（lodge/dims.py の x, y。Godot ではロッジの (x, 0, -y)）で出す。
## 1. 立ち位置: 中から始めたあなたの位置、カプセルと重なる当たり、まわりの物
## 2. 一人称: 立ち位置から見た絵と、冷蔵庫の前から雪だるまを見た絵
## 3. 歩く: ミシンの前 → 冷蔵庫の前 → アイロン台の前 → プレス機の前 → 乾燥機の前を、行きと帰り

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/inside_spawn")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:   # 窓から目が離れると設定が開くことがある
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _l(g: Vector3) -> Vector2:   # 世界 → ロッジの座標
	var q := lodge.to_local(g)
	return Vector2(q.x, -q.z)


func _w(q: Vector2) -> Vector3:   # ロッジの座標 → 世界（床の高さ）
	var g := lodge.to_global(Vector3(q.x, 0, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 2.5, g + Vector3.DOWN * 3.0)
	r.exclude = [p.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else g


func _box(n: Node3D) -> Rect2:   # 物の見た目の範囲（ロッジの座標、上から見た四角）
	var r := Rect2()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		for i in 8:
			var q := _l(b.get_endpoint(i))
			if first:
				r = Rect2(q, Vector2.ZERO)
				first = false
			else:
				r = r.expand(q)
	return r


func _overlaps(at: Vector3) -> Array:
	var shape: Shape3D = null
	for c in p.get_children():
		if c is CollisionShape3D:
			shape = c.shape
			at += c.position
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	q.exclude = [p.get_rid()]
	var out := []
	for h in root.get_world_3d().direct_space_state.intersect_shape(q, 16):
		out.append(String(h.collider.get_path()).replace(String(main.get_path()), ""))
	return out


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


func _walk(goal: Vector3, name: String) -> bool:   # いまの所から goal へ、向きを合わせながら W で歩く
	await _key(KEY_W, true)
	var t := 0.0
	var stuck := 0.0
	var last := p.global_position
	var ok := false
	while t < 20.0:
		var d := goal - p.global_position
		d.y = 0
		if d.length() < 0.6:
			ok = true
			break
		p.rotation.y = atan2(-d.x, -d.z)
		await physics_frame
		t += 1.0 / 30.0
		stuck = stuck + 1.0 / 30.0 if p.global_position.distance_to(last) < 0.004 else 0.0
		last = p.global_position
		if stuck > 1.5:
			break
	await _key(KEY_W, false)
	var lp := _l(p.global_position)
	_say("%s: %s（%.1f 秒、止まった所 x=%.1f y=%.1f）" % [name, "着いた" if ok else "止まった", t, lp.x, lp.y])
	return ok


func _run() -> void:
	await create_timer(2.5).timeout
	p = main.player
	lodge = main.get_node("Lodge")
	# 1. 立ち位置（audio.gd の spawn_point と同じ所）
	var spawn := lodge.to_global(Vector3(6.0, 0.5, -4.0))
	_say("中から始める所: x=%.2f y=%.2f、いまのあなた x=%.2f y=%.2f" % [_l(spawn).x, _l(spawn).y, _l(p.global_position).x, _l(p.global_position).y])
	_say("立ち位置のカプセルと重なる当たり: %s" % str(_overlaps(spawn)))
	var fridge := main.find_child("SnowmanFridge", true, false) as Node3D
	var items := {"冷蔵庫": fridge}
	for s in ["slot_vending_1", "slot_vending_2", "slot_vending_3", "slot_craft_rental"]:
		var n := lodge.find_child(s, true, false) as Node3D
		if n and n.get_child_count() > 0:
			items[s] = n.get_child(0)
	for k in items:
		var r: Rect2 = _box(items[k])
		_say("%s: x %.2f〜%.2f、y %.2f〜%.2f" % [k, r.position.x, r.end.x, r.position.y, r.end.y])
	for b in main.get_children().filter(func(c): return c is CharacterBody3D and c != p):   # 仲間（人形の bot）の位置
		_say("仲間 %s: x=%.2f y=%.2f、あなたまで %.2f m" % [b.name, _l(b.global_position).x, _l(b.global_position).y,
			Vector2(b.global_position.x - p.global_position.x, b.global_position.z - p.global_position.z).length()])
	# 保存された設定（三人称・カメラの距離）のまま、始めた所の画面
	await create_timer(1.0).timeout
	await _shot("01_spawn_inside")
	_say("1 秒後のあなた: x=%.2f y=%.2f、カメラ x=%.2f y=%.2f（三人称 %s）" % [_l(p.global_position).x, _l(p.global_position).y,
		_l(p.cam.global_position).x, _l(p.cam.global_position).y, str(p.third)])
	# 2. 歩く: ミシンの前 → 冷蔵庫の前 → アイロン台の前 → プレス機の前 → 乾燥機の前（厨房の目印の座標で、並びの前 2.6 m）、そして帰り
	p.set_third(false)
	var kitchen := lodge.find_child("slot_food_kitchen", true, false) as Node3D
	var stops := [["ミシン", -10.9], ["冷蔵庫", -7.15], ["アイロン台", -0.8], ["プレス機", 3.0], ["乾燥機", 6.25]]
	var pts := []
	for s in stops:
		var g := kitchen.to_global(Vector3(s[1], 0, 2.6))
		pts.append(_w(_l(g)))
	p.global_position = pts[0] + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	await create_timer(0.4).timeout
	var all_ok := true
	for i in range(1, pts.size()):
		all_ok = await _walk(pts[i], "%s → %s" % [stops[i - 1][0], stops[i][0]]) and all_ok
		if stops[i][0] == "冷蔵庫":   # 冷蔵庫の前から雪だるまを見る
			var to := fridge.global_position + Vector3.UP * 2.0
			p.rotation.y = atan2(-(to.x - p.global_position.x), -(to.z - p.global_position.z))
			p.set("_pitch", 0.15)
			await create_timer(0.6).timeout
			await _shot("02_fridge_front")
	for i in range(pts.size() - 2, -1, -1):
		all_ok = await _walk(pts[i], "%s → %s" % [stops[i + 1][0], stops[i][0]]) and all_ok
	_say("歩く: %s" % ("ぜんぶ着いた" if all_ok else "止まった所がある"))
	var f := FileAccess.open(_dir().path_join("report.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
