extends SceneTree
## ロッジの正面の雪の塊の当たり具合（数字だけ出す）。塊の当たりの形（円柱・寝かせた丸棒）を上から見て、まっすぐな道すじが触れるかを数える。
##   Godot --headless --path game -s res://tools/lump_cover.gd -- --no-sound --no-lodge --roam-bots=0 --lodge-bots=0 --bots=0 --no-player
## 道すじ: 丘の頂上から帯を横切る放射状の線（ロッジの幅を少し超える範囲を 0.1 m おき）と、ロッジへまっすぐ向かう平行な線（ロッジの幅を 0.1 m おき）。
## 幅: 米袋（半分 0.3 m）と中のソリ（半分 0.75 m）。触れない道すじの割合、いちばん広い抜け道、1 本の道すじが触れる塊の数

var main: Node3D


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shapes() -> Array:   # [a, b, r]（世界の xz。円は a == b）
	var out := []
	for area in get_nodes_in_group("crash_lumps"):
		for col in area.get_children():
			if not col is CollisionShape3D:
				continue
			var t: Transform3D = (col as Node3D).global_transform
			var c := Vector2(t.origin.x, t.origin.z)
			if col.shape is CylinderShape3D:
				out.append([c, c, (col.shape as CylinderShape3D).radius, area])
			elif col.shape is CapsuleShape3D:
				var cap: CapsuleShape3D = col.shape
				var ax := Vector2(t.basis.y.x, t.basis.y.z).normalized()
				var half := cap.height * 0.5 - cap.radius
				out.append([c - ax * half, c + ax * half, cap.radius, area])
	return out


## 点 o から向き d へ伸びる線と、丸棒 s（a〜b、半径 r）の距離が w + r 以下か
func _touch(o: Vector2, d: Vector2, s: Array, w: float) -> bool:
	var n := Vector2(-d.y, d.x)
	var d0: float = (s[0] - o).dot(n)
	var d1: float = (s[1] - o).dot(n)
	if (s[0] - o).dot(d) < 0.0 and (s[1] - o).dot(d) < 0.0:
		return false
	if d0 * d1 <= 0.0:
		return true
	return minf(absf(d0), absf(d1)) <= float(s[2]) + w


func _lanes(label: String, lines: Array, shapes: Array, step: float) -> void:
	for w in [0.3, 0.75]:
		var open := 0
		var gap := 0.0
		var run := 0.0
		var hits := 0
		var most := 0
		for ln in lines:
			var areas := {}
			for s in shapes:
				if _touch(ln[0], ln[1], s, w):
					areas[s[3]] = true
			var n := areas.size()
			hits += n
			most = maxi(most, n)
			if n == 0:
				open += 1
				run += step
				gap = maxf(gap, run)
			else:
				run = 0.0
		print("| %s | %s | %d 本 | %.1f %% | %.1f m | %.1f | %d |" % [label, "米袋" if w < 0.5 else "中", lines.size(), 100.0 * open / lines.size(), gap, float(hits) / lines.size(), most])


func _run() -> void:
	await create_timer(1.0).timeout
	var shapes := _shapes()
	var areas := get_nodes_in_group("crash_lumps")
	var kinds := {}
	for a in areas:
		var k: String = a.get_meta("kind", "heap")
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("塊 %d（形 %s）、当たりの部品 %d" % [areas.size(), str(kinds), shapes.size()])
	print("| 道すじ | 幅 | 数 | 触れない割合 | いちばん広い抜け道 | 1 本が触れる塊（平均） | 最多 |")
	print("|---|---|---|---|---|---|---|")
	var radial := []
	var a0: Vector2 = main.lodge_to_world(Vector2(-40.0, 35.0))
	var a1: Vector2 = main.lodge_to_world(Vector2(34.0, 35.0))
	var t0 := a0.angle()
	var dt := wrapf(a1.angle() - t0, -PI, PI)
	var steps := int(absf(dt) * a0.length() / 0.1)
	for i in steps + 1:
		radial.append([Vector2.ZERO, Vector2.from_angle(t0 + dt * i / steps)])
	_lanes("丘の頂上から", radial, shapes, 0.1)
	var straight := []
	var x := -36.0
	while x <= 30.0:
		var o: Vector2 = main.lodge_to_world(Vector2(x, 70.0))
		var e: Vector2 = main.lodge_to_world(Vector2(x, 20.0))
		straight.append([o, (e - o).normalized()])
		x += 0.1
	_lanes("ロッジへまっすぐ", straight, shapes, 0.1)
	quit()
