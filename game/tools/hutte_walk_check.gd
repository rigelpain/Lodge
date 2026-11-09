extends SceneTree
## 旧ヒュッテ（hutte.gd）に、人の大きさの筒がつかえずに入れるかを確かめる。ゲレンデの側の段 → 土間 → ガラスの戸 → 風除室 → ホール → 休憩室、
## 駐車場の側も同じ。道の点ごとに、立つ高さ（光線で下の当たりを取る）に人の筒（半径 0.3、高さ 1.7）を置いて、壁や柱に重ならないかを見る。
##   Godot --headless --path game -s res://tools/hutte_walk_check.gd -- --world=tenkamori --no-player --no-sound

func _initialize() -> void:
	var main: Node3D = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await physics_frame
	var hu: Node3D = main.get_node("Tenkamori/Hutte")
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var routes := {
		"ゲレンデの側から": [Vector3(1.4, 0, 14), Vector3(1.4, 0, 11.5), Vector3(1.4, 0, 10.0), Vector3(1.2, 0, 8.5), Vector3(1.2, 0, 7.9), Vector3(1.0, 0, 6.0), Vector3(0, 0, 3), Vector3(0, 0, 0), Vector3(3.0, 0, 0), Vector3(6.0, 0, 1.3), Vector3(10.0, 0, 1.3)],
		"駐車場の側から": [Vector3(-1.4, 0, -14), Vector3(-1.4, 0, -11.5), Vector3(-1.4, 0, -10.0), Vector3(-1.2, 0, -8.5), Vector3(-1.2, 0, -7.9), Vector3(-1.0, 0, -6.0), Vector3(0, 0, -3), Vector3(0, 0, 0)],
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
