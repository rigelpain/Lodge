extends SceneTree
## ある場所から見た景色で、何をどれだけ描いているかを数える。main の子（地面・山・木・ロッジ…）を 1 つずつ隠して、
## 描く数・面の数がどれだけ減るかを出す（数は熱でぶれない）。1 コマの時間も添える（こちらは熱でぶれる）。
##   Godot --path game --maximized -s res://tools/view_cost.gd -- --roam-bots=0 --no-sound --time=21 --at=-5,462,0 [--deep=名前,名前] [--pip] [--base-only]
## --at=x,z,向き(度): あなたを立たせる所（向き 0 は北 = -z）。--deep: その子の中を、さらに子ごとに数える
## 遠くまで見える所（大きな山の上）が重い（2026-11-09 測定: 仲間 0 人でも 1 コマ 24〜27 ms、GPU 100%）

var args := {}
var main: Node3D
var _items: Array = []   # [名前, Node3D]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	AudioServer.set_bus_mute(0, true)
	_run.call_deferred()


func _process(_dt: float) -> bool:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _geo_count(n: Node) -> int:
	return n.find_children("*", "GeometryInstance3D", true, false).size() + (1 if n is GeometryInstance3D else 0)


## 数コマ待って、描く数・面の数・1 コマの時間（中央値）
func _measure(frames := 30) -> Array:
	for i in 4:
		await process_frame
	var ms := []
	var last := Time.get_ticks_usec()
	var d := 0
	var p := 0
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
		d += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		p += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	ms.sort()
	return [d / frames, p / frames, ms[ms.size() / 2]]


func _run() -> void:
	await create_timer(6.0).timeout
	var p: CharacterBody3D = main.player
	var v := String(args.get("at", "-5,462,0")).split(",")
	var x := float(v[0])
	var z := float(v[1])
	p.global_position = Vector3(x, preload("res://main.gd").ground(x, z) + 0.2, z)
	p.velocity = Vector3.ZERO
	p.rotation.y = deg_to_rad(float(v[2]) if v.size() > 2 else 0.0)
	if not args.has("pip"):   # 360° の小窓と自分の小窓は、コマごとに違う向きを描くので数がぶれる。本体の景色だけを数える（--pip で残す）
		for key in ["pip", "selfcam"]:
			main.settings.values[key] = false
			main._apply_setting(key, false)
	await create_timer(3.0).timeout
	for c in main.get_children():
		if c is Node3D and _geo_count(c) > 0 and c != p:
			_items.append([String(c.name), c])
	var deep := String(args.get("deep", "")).split(",", false)
	for name in deep:
		var c := main.get_node_or_null(name)
		if c:
			for g in c.get_children():
				if g is Node3D and _geo_count(g) > 0:
					_items.append([name + "/" + String(g.name), g])
	var base: Array = await _measure()
	print("場所 %s 窓 %s  ぜんぶ: 描く数 %d 面 %d  %.1f ms" % [str(p.global_position.snapped(Vector3.ONE)), str(root.size), base[0], base[1], base[2]])
	if args.has("census"):   # 画面に入っている形を、main の子の種類（名前の数字を除く）ごとに数える。ぶれない
		_census(p)
	if args.has("base-only") or args.has("census"):   # ぜんぶの数だけ
		quit()
		return
	var res := []
	for it in _items:
		var n: Node3D = it[1]
		if not n.visible:
			continue
		var on: Array = await _measure(10)   # 隠す直前に測り直す（ぶれを打ち消す）
		n.visible = false
		var r: Array = await _measure(10)
		n.visible = true
		res.append([it[0], on[0] - r[0], on[1] - r[1], on[2] - r[2], _geo_count(n)])
	res.sort_custom(func(a, b): return a[2] > b[2])
	print("隠した物 / 減った描く数 / 減った面 / 減った ms / 形の数")
	for r in res:
		if r[1] > 5 or r[2] > 20000:
			print("%-40s %6d %9d %6.1f %6d" % r)
	quit()


## 画面に入っていて、見える距離の内の形の数・面の組の数（描く数の目安。影の分は入れない）・三角の数（LOD の前）を、種類ごとに
func _census(p: Node3D) -> void:
	var cam := root.get_camera_3d()
	var planes := cam.get_frustum()
	var re := RegEx.create_from_string("[0-9@]+")
	var rows := {}
	for c in main.get_children():
		if not (c is Node3D) or not c.is_visible_in_tree():
			continue
		var key := re.sub(String(c.name), "", true)
		if key == "":
			key = "(名前なし)" + (c.get_script().resource_path.get_file() if c.get_script() else c.get_class())
		for g in c.find_children("*", "GeometryInstance3D", true, false) + ([c] if c is GeometryInstance3D else []):
			var gi := g as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			var ab: AABB = gi.global_transform * gi.get_aabb()
			var inside := true
			for pl in planes:
				var far_pt := ab.get_support(pl.normal)
				if pl.is_point_over(ab.get_support(-pl.normal)) and pl.is_point_over(far_pt):
					inside = false
					break
			if not inside:
				continue
			var d := cam.global_position.distance_to(ab.get_center())
			if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + gi.visibility_range_end_margin:
				continue
			var surf := 1
			var tri := 0
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
				var m: Mesh = (gi as MeshInstance3D).mesh
				surf = m.get_surface_count()
				for si in surf:
					var arr := m.surface_get_arrays(si)
					var idx = arr[Mesh.ARRAY_INDEX]
					tri += (idx.size() if idx else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var r: Array = rows.get(key, [0, 0, 0])
			rows[key] = [r[0] + 1, r[1] + surf, r[2] + tri]
	var keys := rows.keys()
	keys.sort_custom(func(a, b): return rows[a][1] > rows[b][1])
	print("種類 / 画面の中の形 / 面の組 / 三角（LOD の前）")
	for k in keys.slice(0, 25):
		print("%-34s %6d %6d %9d" % [k, rows[k][0], rows[k][1], rows[k][2]])
