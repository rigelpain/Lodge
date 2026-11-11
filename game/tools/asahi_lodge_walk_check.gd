extends SceneTree
## 旭ヶ丘の休憩所「雪ん子館」（asahi_lodge.gd）に、人の大きさの筒がつかえずに入れるかを確かめる（hutte_walk_check.gd と同じやり方）。
##   Godot --headless --path game -s res://tools/asahi_lodge_walk_check.gd -- --world=asahigaoka --no-player --no-sound

func _initialize() -> void:
	var main: Node3D = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await physics_frame
	var hu: Node3D = main.get_node("Site/Lodge")
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var routes := {
		"ゲレンデの側の入口から": [Vector3(-6, 0, 15.8), Vector3(-3, 0, 15.8), Vector3(-1.5, 0, 15.8), Vector3(0.6, 0, 15.8), Vector3(1.8, 0, 15.8), Vector3(2.6, 0, 15.8), Vector3(3.6, 0, 15.8), Vector3(6, 0, 18), Vector3(8.2, 0, 24), Vector3(8.2, 0, 30)],
		"駐車場の側の入口から": [Vector3(19, 0, 29.2), Vector3(17, 0, 29.2), Vector3(15.2, 0, 29.2), Vector3(13.9, 0, 29.2), Vector3(12.8, 0, 29.2), Vector3(10, 0, 27)],
		"デッキを南へ": [Vector3(1.5, 0, 17.5), Vector3(1.5, 0, 24), Vector3(1.5, 0, 32.8), Vector3(8, 0, 32.9)],
	}
	var bad := 0
	for name in routes:
		var line := ""
		for lp in routes[name]:
			var w: Vector3 = hu.to_global(lp)
			var q := PhysicsRayQueryParameters3D.create(Vector3(w.x, hu.global_position.y + 2.3, w.z), w + Vector3(0, -6, 0))   # 戸の上の壁より下から
			var r: Dictionary = space.intersect_ray(q)
			var foot: float = r.get("position", w).y
			var sp := PhysicsShapeQueryParameters3D.new()
			sp.shape = cap
			sp.transform = Transform3D(Basis.IDENTITY, Vector3(w.x, foot + 0.15 + 0.85, w.z))
			var hits: Array = space.intersect_shape(sp, 8)
			var on: String = (r.get("collider") as Node).name if r.has("collider") else "?"
			line += "\n  (%.1f, %.1f) 足もと %.2f m（%s）" % [lp.x, lp.z, foot - hu.global_position.y, on]
			if not hits.is_empty():
				line += "  ← つかえる: %d か所" % hits.size()
				bad += 1
		print(name, line)
	print("つかえた点: %d" % bad)
	quit()
