extends SceneTree
## ゲームの場面（main.tscn）で、ミシンのまわり（slot_craft_rental）を撮る。雪だるまの冷蔵庫の置き場の確かめ用。
##   Godot --path game --resolution 1280x720 -s res://tools/snowman_lodge_shot.gd -- --bots=0 --no-sound --no-pip \
##       --out=/path/to.png [--view=front|top|quarter|near|kitchen]
## 目印の座標で: +Z が食堂の側（ミシンの正面）、ミシンの正面から見て右が +X

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
	await create_timer(2.5).timeout
	var slot := main.find_child("slot_craft_rental", true, false) as Node3D
	var cam := Camera3D.new()
	slot.add_child(cam)
	var at := {
		"front": [Vector3(2.4, 2.2, 10.5), Vector3(2.4, 1.5, 0.0)],
		"quarter": [Vector3(-2.0, 2.6, 8.0), Vector3(3.5, 1.4, -0.5)],
		"near": [Vector3(3.0, 1.5, 5.5), Vector3(3.7, 1.7, -1.0)],
		"kitchen": [Vector3(5.5, 2.4, 9.0), Vector3(6.5, 1.4, -0.5)],
		"top": [Vector3(1.5, 3.3, 1.6), Vector3(1.5, 0.0, 1.5)],
	}
	if args.has("probe"):   # 目印の座標で、まわりの壁までの距離と、ミシンの大きさを出す
		var space := slot.get_world_3d().direct_space_state
		for o in [Vector3(1.5, 1.0, 0.5), Vector3(1.5, 1.0, 2.0), Vector3(-1.5, 1.0, 1.5), Vector3(2.5, 1.0, -0.5)]:
			for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
				var q := PhysicsRayQueryParameters3D.create(slot.to_global(o), slot.to_global(o + d * 12.0))
				var hit := space.intersect_ray(q)
				print("probe from ", o, " dir ", d, " -> ", slot.to_local(hit.position) if hit else "none")
		for c in slot.get_children():   # 目印の下の物ごとの大きさ（ミシン・売り子）
			var box := AABB()
			var first := true
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				if not mi.is_visible_in_tree():
					continue
				var b: AABB = slot.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
				box = b if first else box.merge(b)
				first = false
			print("box (slot) ", c.name, ": ", box)
		var kitchen := main.find_child("slot_food_kitchen", true, false) as Node3D
		print("kitchen slot in craft slot: ", slot.to_local(kitchen.global_position), " yaw ", kitchen.global_rotation.y - slot.global_rotation.y)
		for mi in kitchen.find_children("*", "MeshInstance3D", true, false):   # 厨房の西の端の品物（ミシンの目印の座標で）
			var b: AABB = slot.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			if b.position.x < 6.0:
				print("kitchen (slot) ", mi.get_parent().get_parent().name, "/", mi.get_parent().name, ": ", b)
		quit()
		return
	var v: Array = at[args.get("view", "front")]
	cam.position = v[0]
	cam.fov = 60 if args.get("view", "front") != "top" else 95
	cam.near = 0.05
	cam.current = true
	cam.look_at(slot.to_global(v[1]), Vector3.UP if args.get("view", "front") != "top" else Vector3(0, 0, -1).rotated(Vector3.UP, slot.global_rotation.y))
	if main.get("player"):
		main.player.global_position = slot.to_global(Vector3(-30, 0, 30))   # あなたは画面の外へ
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png(args.get("out", "/tmp/lodge.png"))
	print("保存: ", args.get("out", ""))
	quit()
