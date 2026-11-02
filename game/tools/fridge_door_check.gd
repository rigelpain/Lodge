extends SceneTree
## 雪だるまの冷蔵庫の扉の開き具合の確かめ。扉（節点 door）を角度ごとに回し、扉の形の点が
## ほかの当たり（壁・装置）に入らないかを数え、厨房の通り道からの目線と真上から撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/fridge_door_check.gd -- --dir=/path/shots --angles=100,180,220
## 角度は閉じた所からの開き（度）。--keep を付けると、glb のままの角度で撮る（角度の名前は now）。
## どちらも扉の動き（fridge_door.gd）を止めて、決めた角度で撮る。
##   ... -- --bots=0 --no-pip --dir=/path/walk --walk [--before]
## --walk: 自分の人形が通り道の遠くから冷蔵庫の前まで歩いて来て、少し待って戻る。12 fps のコマごとに斜め後ろから撮り
## （walk_000.png …）、扉の点が人形に入ったコマを数える。--before で扉を動かさず、前の 100° のままで撮る。--close で寄って撮る

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/fridge_door_check")


func _shot(name: String) -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


## 扉の形の点（世界の座標）。頂点を間引いて使う
func _door_points(door: Node3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for mi in door.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var xf := (mi as MeshInstance3D).global_transform
		for s in m.get_surface_count():
			var v: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for i in range(0, v.size(), 7):
				pts.append(xf * v[i])
	return pts


func _owner_name(n: Node) -> String:
	var path := []
	while n and n != main:
		path.push_front(String(n.name))
		n = n.get_parent()
	return "/".join(path.slice(maxi(0, path.size() - 4)))


func _check(door: Node3D, fridge: Node3D, label: String) -> void:
	var space := main.get_world_3d().direct_space_state
	var pts := _door_points(door)
	var hits := {}
	var q := PhysicsPointQueryParameters3D.new()
	q.collide_with_areas = false
	for p in pts:
		q.position = p
		for r in space.intersect_point(q, 8):
			var key := _owner_name(r.collider)
			hits[key] = hits.get(key, 0) + 1
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in pts:
		var l := fridge.to_local(p)
		lo = lo.min(l)
		hi = hi.max(l)
	print("[%s] 扉の点 %d、冷蔵庫の座標での広がり（倍率 1）: %s 〜 %s" % [label, pts.size(), lo, hi])
	if hits.is_empty():
		print("[%s] 当たりに入る点なし" % label)
	for k in hits:
		print("[%s] 当たりに入る点 %d: %s" % [label, hits[k], k])


func _run() -> void:
	await create_timer(4.0).timeout
	var fridge := main.find_child("SnowmanFridge", true, false) as Node3D
	var door := fridge.find_child("door", true, false) as Node3D
	var mover := fridge.find_child("FridgeDoor", true, false)
	if args.has("walk"):
		await _walk(fridge, door, mover)
		quit()
		return
	if mover:
		mover.set_process(false)
	var base_y := door.rotation.y
	print("扉の rotation.y（glb のまま）: ", rad_to_deg(base_y))
	var cam := Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	await create_timer(0.5).timeout   # 初めの 1 枚が、切り替わる前の画で撮れないように
	# 目線は冷蔵庫の向きで決める（glb の前は -Z、前から見て左＝蝶番の側は +X）
	var f := fridge.global_transform
	var front := -(f.basis.z.normalized())
	var left := f.basis.x.normalized()
	var c := f.origin
	var looks := [
		# 真上から（平行投影。2 階の床の下から、幅 9 m を写す）
		["top", c + front * 1.5 + left * 1.5 + Vector3(0, 5.4, 0), c + front * 1.5 + left * 1.5],
		# 厨房の通り道（冷蔵庫の前 3.2 m、少し右（東）寄り）から、目の高さで
		["aisle", c + front * 3.2 - left * 1.0 + Vector3(0, 1.6, 0), c + front * 0.3 + left * 0.5 + Vector3(0, 1.5, 0)],
		# 通り道を蝶番の側に寄って
		["aisle_left", c + front * 3.0 + left * 1.6 + Vector3(0, 1.6, 0), c + left * 0.6 + Vector3(0, 1.4, 0)],
	]
	var angles: Array = []
	if args.has("keep"):
		angles.append("now")
	else:
		for s in String(args.get("angles", "100,180,220")).split(","):
			angles.append(float(s))
	for a in angles:
		var label := "now" if a is String else "%d" % int(a)
		if not a is String:
			door.rotation.y = deg_to_rad(-float(a))
		await process_frame
		_check(door, fridge, label)
		for l in looks:
			cam.global_position = l[1]
			if l[0] == "top":
				cam.projection = Camera3D.PROJECTION_ORTHOGONAL
				cam.size = 9.0
				cam.look_at(l[2], front)
			else:
				cam.projection = Camera3D.PROJECTION_PERSPECTIVE
				cam.look_at(l[2])
			cam.current = true
			cam.reset_physics_interpolation()   # 動きの補間で、前の目線から滑ってこないように
			await create_timer(0.3).timeout
			await _shot("%s_%s" % [l[0], label])
	quit()


## 人形が歩いて来て、扉が開き、戻ると閉じる流れをコマごとに撮る
func _walk(fridge: Node3D, door: Node3D, mover: Node) -> void:
	var f := fridge.global_transform
	var front := -(f.basis.z.normalized())
	var left := f.basis.x.normalized()
	var c := f.origin
	if args.has("before") and mover:
		mover.set_process(false)
		door.rotation.y = deg_to_rad(-100.0)
	var p: CharacterBody3D = main.get("player")
	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.global_position = c + front * 7.0 - left * 2.8 + Vector3(0, 3.0, 0)
	cam.look_at(c + front * 1.6 + left * 0.5 + Vector3(0, 1.3, 0))
	var far := c + front * 8.0 - left * 0.8
	var near := c + front * 3.3 - left * 0.4
	if args.has("close"):   # 冷蔵庫と番台に寄って撮る。人形は蝶番の側から来て、番台の前をふさがない（扉の回る所より外）
		cam.global_position = c + front * 5.2 - left * 1.4 + Vector3(0, 2.1, 0)
		cam.look_at(c + front * 1.2 + left * 0.3 + Vector3(0, 1.1, 0))
		far = c + front * 7.5 + left * 4.0
		near = c + front * 3.2 + left * 1.6
	cam.current = true
	cam.reset_physics_interpolation()
	var plan := []   # コマごとの立つ所: 歩いて来て、扉が開いて番台が組み立つあいだ待ち、戻って、畳んで閉じるまで待つ
	for i in 30:
		plan.append(far.lerp(near, float(i) / 29.0))
	for i in 50:
		plan.append(near)
	for i in 30:
		plan.append(near.lerp(far, float(i) / 29.0))
	for i in 50:
		plan.append(far)
	var hits := 0
	var was_talk := false
	var space := main.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	for i in plan.size():
		var at: Vector3 = plan[i]
		p.global_position = Vector3(at.x, p.global_position.y, at.z)
		p.velocity = Vector3.ZERO
		var d := c - at
		p.rotation.y = atan2(-d.x, -d.z)
		p.reset_physics_interpolation()
		await create_timer(1.0 / 12.0).timeout
		for pt in _door_points(door):
			q.position = pt
			for r in space.intersect_point(q, 4):
				if r.collider == p:
					hits += 1
		var shop = main.get("snowman_shop")
		var talk: bool = shop != null and shop.can_talk(p)
		if talk != was_talk:   # 話しかけられるようになった（なくなった）コマ
			print("コマ %d: 話しかけ %s（番台 open=%s）" % [i, talk, shop.open])
			was_talk = talk
		await _shot("walk_%03d" % i)
	print("扉の点が人形に入った数: ", hits)
