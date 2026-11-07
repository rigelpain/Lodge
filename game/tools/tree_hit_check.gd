extends SceneTree
## 木の当たりの確かめ（数字）。丘・大きな山・大山の木へ、人が歩いて、ソリ（または米袋）が滑ってぶつかり、止まるか抜けるかを出す。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/tree_hit_check.gd -- --bots=0 --lodge-bots=0 --no-pip --no-sound [--sled=sack]
## 山ごとに、木の種類ごとのいちばんなだらかな所の 1 本を使う。「幹から」は幹の軸から当たる物の真ん中までの水平の距離 (m)。
## 滑る道の木: 頂上のまわりから雪面の下りをたどる線のそばに、幹がいくつ立つか。「置き場所の印」: 別の起動でも同じなら、全員の画面で同じ所に当たる。
## 窓を出して --shots=/path/dir を足すと、丘の高い木で絵を撮る。--cost=/path/cost.txt を足すと、大山のいちばん木の多い所で、当たりあり・なしを交互に 1 コマの時間を測る。

const KINDS := ["tree_tall", "tree_zigzag", "tree_round", "tree_little"]
const LINE_TREE := 2.0       # 下りの線からこの距離の内にある幹を「道に立っている」と数える (m)

var args := {}
var main: Node3D
var p: CharacterBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


## 木の節点の、地面の傾き（高さの差 / m）
func _slope(at: Vector2) -> Vector2:
	return Vector2(main.height(at.x + 1.0, at.y) - main.height(at.x - 1.0, at.y), main.height(at.x, at.y + 1.0) - main.height(at.x, at.y - 1.0)) * 0.5


func _trees(parent: Node) -> Array:
	var out := []
	for n in parent.get_children():
		if String(n.scene_file_path).get_file().begins_with("tree_"):
			out.append(n)
	return out


func _kind_of(t: Node) -> String:
	return String(t.scene_file_path).get_file().get_basename()


## 種類ごとに、いちばんなだらかで、ほかの幹から離れた 1 本
func _picks(trees: Array) -> Array:
	var best := {}
	for t in trees:
		var at := Vector2(t.position.x, t.position.z)
		var near := false
		for o in trees:
			if o != t and at.distance_to(Vector2(o.position.x, o.position.z)) < 8.0:
				near = true
				break
		if near:
			continue
		var k := _kind_of(t)
		var s := _slope(at).length()
		if not best.has(k) or s < best[k][0]:
			best[k] = [s, t]
	var out := []
	for k in KINDS:
		if best.has(k):
			out.append(best[k][1])
	return out


## 人: 幹の 4 m 手前から W で幹の真ん中へ歩く
func _walk(t: Node3D) -> String:
	var o := Vector2(t.global_position.x, t.global_position.z)
	var g := _slope(o)
	var dir := g.normalized() if g.length() > 0.01 else Vector2(1, 0)   # 坂を上りながら
	var a := o - dir * 4.0
	var start := Vector3(a.x, main.height(a.x, a.y) + 0.3, a.y)
	p.global_position = start
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-dir.x, -dir.y)
	for i in 20:
		await physics_frame
		p.global_position.x = start.x
		p.global_position.z = start.z
	await _key(KEY_W, true)
	var least := INF
	var passed := false
	var rise := 0.0
	var t0 := 0.0
	while t0 < 5.0:
		await physics_frame
		t0 += 1.0 / Engine.physics_ticks_per_second
		var at := Vector2(p.global_position.x, p.global_position.z)
		least = minf(least, at.distance_to(o))
		rise = maxf(rise, p.global_position.y - main.height(at.x, at.y))
		if (at - o).dot(dir) > 0.5:
			passed = true
			break
	await _key(KEY_W, false)
	return "人 %s（幹から %.2f m。足もとの雪からの浮き %.2f m）" % ["抜けた" if passed else "止まった", least, rise]


## ソリ: 幹の 12 m 手前から、speed m/s で幹の真ん中へ滑らせる。あなたが乗っている
func _slide(t: Node3D, speed: float) -> String:
	var s: RigidBody3D = main.sled
	var o := Vector2(t.global_position.x, t.global_position.z)
	var g := _slope(o)
	var dir := -g.normalized() if g.length() > 0.01 else Vector2(1, 0)   # 坂を下りながら
	var a := o - dir * 12.0
	s.reset_to(Vector3(a.x, main.height(a.x, a.y) + 0.3, a.y))
	s.global_basis = Basis(Vector3.UP, atan2(-dir.x, -dir.y))
	for i in 10:
		await physics_frame
	p.global_position = s.global_position + s.global_basis.x * 1.5
	p.get_on()
	s.parked = false
	s.linear_velocity = Vector3(dir.x, 0, dir.y) * speed
	var least := INF
	var passed := false
	var fast := 0.0
	var hop := 0.0
	var fell := false
	var t0 := 0.0
	var hit_v := 0.0
	var last_v := speed
	while t0 < 6.0:
		await physics_frame
		t0 += 1.0 / Engine.physics_ticks_per_second
		var at := Vector2(s.global_position.x, s.global_position.z)
		var v := Vector2(s.linear_velocity.x, s.linear_velocity.z).length()
		least = minf(least, at.distance_to(o))
		fast = maxf(fast, v)
		hop = maxf(hop, s.global_position.y - main.height(at.x, at.y))
		fell = fell or s.global_position.y < main.height(at.x, at.y) - 1.0
		if last_v - v > hit_v:
			hit_v = last_v - v
		last_v = v
		if (at - o).dot(dir) > 1.5:
			passed = true
			break
	var rode: int = s.riders.size()
	p.get_off()
	return "%s %.0f m/s %s（幹から %.2f m。1 コマの速さの落ち %.1f m/s、そのあと %.1f m/s、雪からの浮き %.2f m、乗った人 %d%s）" % [
			s.kind, speed, "抜けた" if passed else "止まった", least, hit_v, last_v, hop, rode, "、地面の下へ落ちた" if fell else ""]


## 頂上のまわりから下りをたどる線。線のそばに立つ幹の数を返す
func _lines(trees: Array, top: Vector2, spread: float, dirs: Array) -> String:
	var bad := 0
	var total := 0
	var worst := 0
	for d in dirs:
		for off in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var side: Vector2 = Vector2(-d.y, d.x) * float(off) * spread
			var at: Vector2 = top + d * 6.0 + side
			var met := {}
			for i in 900:
				var g := _slope(at)
				if g.length() < 0.02:
					break
				at -= g.normalized()
				for t in trees:
					if at.distance_to(Vector2(t.position.x, t.position.z)) < LINE_TREE:
						met[t] = true
			total += 1
			if met.size() > 0:
				bad += 1
			worst = maxi(worst, met.size())
	return "下りの線 %d 本のうち、幹のそば（%.0f m 内）を通るのは %d 本（1 本の線でいちばん %d 本）" % [total, LINE_TREE, bad, worst]


func _shape_print(trees: Array) -> String:
	var sum := 0
	for t in trees:
		var tp: Vector3 = t.position
		sum = (sum * 31 + hash(Vector3i((tp * 100.0).round()))) & 0x7fffffff
	return "木 %d 本、置き場所の印 %d" % [trees.size(), sum]


func _save(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(String(args.shots).path_join(name + ".png"))
	print("絵: ", name)


## 脇のカメラを置く。使わないときは from を Vector3.INF に
func _side_cam(from: Vector3, at: Vector3) -> void:
	var cam: Camera3D = main.get_node_or_null("ToolCam")
	if from == Vector3.INF:
		if cam:
			cam.free()
		p.cam.make_current()
		return
	if cam == null:
		cam = Camera3D.new()
		cam.name = "ToolCam"
		cam.cull_mask = 0xFFFFF
		main.add_child(cam)
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.make_current()


func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(args.shots)
	p.set_third(false)   # 設定に三人称が残っていても、一人称で撮る
	var t: Node3D = _picks(_trees(main))[int(args.get("pick", "0"))]
	var o: Vector3 = t.global_position
	var dir := Vector2(1, 0)
	var a := Vector2(o.x, o.z) - dir * 3.5
	p.global_position = Vector3(a.x, main.height(a.x, a.y) + 0.1, a.y)
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-dir.x, -dir.y)
	await create_timer(0.5).timeout
	await _save("1_walk_before")
	await _key(KEY_W, true)
	await create_timer(3.0).timeout
	await _key(KEY_W, false)
	await _save("2_walk_at_trunk_view")
	var side := Vector3(dir.y, 0, -dir.x)
	_side_cam(p.global_position + side * 6.0 + Vector3.UP * 1.5 - Vector3(dir.x, 0, dir.y) * 1.0, p.global_position + Vector3.UP * 1.0)
	await _save("3_walk_at_trunk_side")
	_side_cam(Vector3.INF, Vector3.ZERO)
	var res := await _slide(t, 12.0)
	print(res)
	var s: RigidBody3D = main.sled
	p.global_position = s.global_position + Vector3(-1.0, 0, 3.0)
	_side_cam(s.global_position + side * 6.5 + Vector3.UP * 2.0 - Vector3(dir.x, 0, dir.y) * 2.0, s.global_position + Vector3.UP * 0.7)
	await _save("4_sled_at_trunk_side")
	_side_cam(Vector3.INF, Vector3.ZERO)
	s.reset_to(Vector3(a.x, main.height(a.x, a.y) + 0.3, a.y))
	s.global_basis = Basis(Vector3.UP, atan2(-dir.x, -dir.y))
	for i in 10:
		await physics_frame
	p.global_position = s.global_position + s.global_basis.x * 1.5
	p.get_on()
	s.parked = false
	s.linear_velocity = Vector3(dir.x, 0, dir.y) * 6.0
	await create_timer(1.5).timeout
	await _save("5_ride_at_trunk_view")
	p.get_off()
	quit()


## 大山で木のいちばん多い所に立ち、当たりあり・なしを交互に per 秒ずつ測る（体を消す・戻すのを 2 組）
func _cost() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var hub: Node3D = main.get_node("GrandMountain")
	var trees := _trees(hub)
	var best: Vector2
	var most := -1
	for t in trees:
		var at := Vector2(t.position.x, t.position.z)
		var n := 0
		for o in trees:
			if at.distance_to(Vector2(o.position.x, o.position.z)) < 40.0:
				n += 1
		if n > most:
			most = n
			best = at
	p.global_position = Vector3(best.x + 2.0, main.height(best.x + 2.0, best.y) + 0.3, best.y)
	await create_timer(4.0).timeout
	var body: StaticBody3D
	for c in hub.get_children():
		if c is StaticBody3D and c.get_child_count() == 0 and c.get_script() == preload("res://tree_hits.gd"):
			body = c
	var out := FileAccess.open(args.cost, FileAccess.WRITE)
	var say := func(l: String):
		print(l)
		out.store_line(l)
	say.call("大山 (%.0f, %.0f) 半径 40 m に木 %d 本。仲間 %d 人。当たりの形 %d" % [best.x, best.y, most, get_nodes_in_group("bots").size(), body.get_shape_owners().size()])
	for pair in 4:
		for on in [true, false]:
			if on and body.get_parent() == null:
				hub.add_child(body)
			elif not on:
				hub.remove_child(body)
			await create_timer(1.0).timeout
			var frames := 0
			var phys := 0.0
			var t0 := Time.get_ticks_usec()
			while Time.get_ticks_usec() - t0 < 5000000:
				await process_frame
				frames += 1
				phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			say.call("  当たり%s: %.1f fps、1 コマ %.2f ms、物理 %.3f ms" % ["あり" if on else "なし", frames / 5.0, 5000.0 / frames, phys / frames])
	if body.get_parent() == null:
		body.free()
	quit()


func _run() -> void:
	await create_timer(2.0).timeout
	p = main.player
	main.sled.parked = false
	if args.has("shots"):
		await _shots()
		return
	if args.has("cost"):
		await _cost()
		return
	var hills := {"丘": main, "大きな山": main.get_node("Mountain"), "大山": main.get_node("GrandMountain")}
	var lines := {
		"丘": [Vector2(0, 0), 8.0, [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]],
		"大きな山": [Vector2(-14, 300), 20.0, [Vector2(0, -1)]],
		"大山": [Vector2(300, 22), 40.0, [Vector2(-1, 0)]],
	}
	for name in hills:
		var trees := _trees(hills[name])
		print("%s: %s" % [name, _shape_print(trees)])
		print("  " + _lines(trees, lines[name][0], lines[name][1], lines[name][2]))
		for t in _picks(trees):
			var head := "  %s 高さ倍率 %.2f 傾き %.2f: " % [_kind_of(t), t.scale.x, _slope(Vector2(t.position.x, t.position.z)).length()]
			print(head + await _walk(t))
			for sp in [8.0, 20.0]:
				print(head + await _slide(t, sp))
	quit()
