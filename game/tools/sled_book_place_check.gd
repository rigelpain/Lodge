extends SceneTree
## 布の見本帳の置き場の確かめ（立てかけ台の横。main.gd の SLED_BOOK_AT）。数字と絵。
##   Godot --headless --path game -s res://tools/sled_book_place_check.gd -- --bots=0 --lodge-bots=0 --no-sound --no-pip --no-buttons
##   Godot --path game --resolution 1280x720 -s res://tools/sled_book_place_check.gd -- --bots=0 --lodge-bots=0 --no-sound --no-pip --no-buttons --time=12 --third --shot=/path/day.png [--px= --py= --tx= --ty=]
## 見るもの: 屋根の下に収まる、台と重ならない、持ち出したソリの置き場が変わらない、戸から西と南へ歩ける、台と見本帳の F が取り合わない

const ROOF_Y := 12.91

var args := {}
var main: Node3D
var bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	create_timer(60.0).timeout.connect(quit)
	_run.call_deferred()


func _ok(c: bool, s: String) -> void:
	print(("○ " if c else "× ") + s)
	if not c:
		bad += 1


func _box(n: Node3D, lodge: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mm := m as MeshInstance3D
		var ab: AABB = (lodge.global_transform.affine_inverse() * mm.global_transform) * mm.get_aabb()
		bb = ab if first else bb.merge(ab)
		first = false
	return bb


func _run() -> void:
	for i in 30:
		await process_frame
	await physics_frame
	await physics_frame
	var lodge: Node3D = main.get_node("Lodge")
	var rack: Node3D = main.sled_rack
	var book: Node3D = main.sled_book
	var p: Node3D = main.player
	if args.has("shot"):
		await _shoot(lodge)
		quit()
		return
	var bb := _box(book, lodge)
	var rb := _box(rack, lodge)
	print("見本帳 x %.2f..%.2f y %.2f..%.2f 高さ %.2f / 台 x %.2f..%.2f y %.2f..%.2f" % [bb.position.x, bb.end.x, -bb.end.z, -bb.position.z, bb.end.y, rb.position.x, rb.end.x, -rb.end.z, -rb.position.z])
	_ok(-bb.position.z <= ROOF_Y, "屋根の下に収まる（北の端 %.2f、屋根 %.2f）" % [-bb.position.z, ROOF_Y])
	_ok(-bb.end.z >= -rb.position.z, "台と重ならない（すき間 %.2f m）" % (-bb.end.z + rb.position.z))
	for u in [-4.8, -2.4, 0.0, 2.4, 4.8]:
		var xf: Transform3D = rack.out_at("large", u, main)
		_ok(xf.origin != Vector3.INF, "大を持ち出して置ける（台の %+.1f m）" % u)
		var lo: Vector3 = lodge.to_local(xf.origin)
		_ok(absf(lo.x + 27.5) < 0.01, "  置く所は x -27.5 のまま（y %.1f）" % -lo.z)
	_ok(is_equal_approx(rack.fit("large", [[3.6, 2.4], [1.2, 2.4], [-1.2, 2.4]]), -3.6) and is_nan(rack.fit("large", [[3.6, 2.4], [1.2, 2.4], [-1.2, 2.4], [-3.6, 2.4]])), "大は 4 台まで")
	# 歩ける所: 人の当たりの形を 0.25 m 刻みで置いて、戸の前から広がる
	var shape: Shape3D = null
	for c in p.find_children("*", "CollisionShape3D", false, false):
		shape = c.shape
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var free := func(cell: Vector2i) -> bool:
		var w: Vector3 = lodge.to_global(Vector3(cell.x * 0.25, 0, -cell.y * 0.25))
		w.y = main.height(w.x, w.z) + 1.0
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(), w)
		q.exclude = [p.get_rid()]
		for r in space.intersect_shape(q, 4):
			if r.collider is StaticBody3D:
				return false
		return true
	var start := Vector2i(int(-23.0 / 0.25), int(11.45 / 0.25))   # 西のガラスの戸の前
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if seen.has(n) or n.x * 0.25 < -33.0 or n.x * 0.25 > -22.2 or n.y * 0.25 < 2.0 or n.y * 0.25 > 16.0:
				continue
			if free.call(n):
				seen[n] = true
				todo.append(n)
	for goal in [[Vector2(-29.0, 11.5), "戸から西へ"], [Vector2(-27.5, 3.0), "戸から台の前へ（南）"], [Vector2(-27.5, 9.7), "戸から見本帳の前へ"]]:
		var g := Vector2i(int(goal[0].x / 0.25), int(goal[0].y / 0.25))
		_ok(seen.has(g), goal[1] + "歩ける")
	# 見本帳の脇のすき間（南と北）
	for side in [[Vector2(-25.1, 11.2), "見本帳の北"]]:
		var g := Vector2i(int(side[0].x / 0.25), int(side[0].y / 0.25))
		_ok(seen.has(g), side[1] + "を人が通れる")
	# F の取り合い: 人を置いて見本帳へ向ける
	var both := 0
	var book_only := 0
	var at_lodge := func(x: float, y: float, to: Vector3) -> void:
		var w: Vector3 = lodge.to_global(Vector3(x, 0, -y))
		w.y = main.height(w.x, w.z) + 0.1
		p.global_position = w
		var d := to - w
		p.rotation.y = atan2(-d.x, -d.z)
	for ix in range(-30, -24):
		for iy in range(24, 52):
			at_lodge.call(float(ix), iy * 0.25, book.global_position)
			var bn: bool = p.book_near()
			if bn and rack.can_use(p):
				both += 1
			if bn:
				book_only += 1
	_ok(both == 0, "見本帳と台の F が同時に出る所はない（%d 所）" % both)
	_ok(book_only > 0, "見本帳の F が出る所がある（%d 所）" % book_only)
	at_lodge.call(-27.5, 9.7, book.global_position)
	_ok(p.book_near(), "見本帳の真ん前で F が出る")
	_ok(not rack.can_use(p), "  そこに台の F は届かない")
	at_lodge.call(-27.5, 3.0, rack.global_position)
	_ok(not p.book_near(), "台の前では見本帳の F は出ない")
	_ok(rack.can_use(p), "  台の F は出る")
	at_lodge.call(-27.5, 7.5, book.global_position)
	_ok(not p.book_near() and rack.can_use(p), "台の端の前で見本帳の方を見ても、台を優先する")
	at_lodge.call(-23.0, 9.7, book.global_position)
	_ok(not p.book_near(), "見本帳の裏（戸の側）からは F が出ない")
	print("だめだった数: %d" % bad)
	quit()


## 遊ぶ人の画面のまま撮る。--px・--py は人の立つ所（ロッジの座標）、--tx・--ty は向く先
func _shoot(lodge: Node3D) -> void:
	var p: Node3D = main.player
	var w: Vector3 = lodge.to_global(Vector3(float(args.get("px", "-31.0")), 0, -float(args.get("py", "6.0"))))
	w.y = main.height(w.x, w.z) + 0.1
	p.global_position = w
	var to: Vector3 = lodge.to_global(Vector3(float(args.get("tx", "-24.5")), 0, -float(args.get("ty", "5.0"))))
	var d := to - w
	p.rotation.y = atan2(-d.x, -d.z)
	for i in 50:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args.shot)
