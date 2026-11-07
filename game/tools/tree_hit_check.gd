extends SceneTree
## 木の当たりの確かめ（数字）。丘・大きな山・大山の木へ、人が歩いて、ソリ（または米袋）が滑ってぶつかり、止まるか抜けるかを出す。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/tree_hit_check.gd -- --bots=0 --lodge-bots=0 --no-pip --no-sound [--sled=sack]
## 山ごとに、木の種類ごとのいちばんなだらかな所の 1 本を使う。「幹から」は幹の軸から当たる物の真ん中までの水平の距離 (m)。
## 滑る道の木: 頂上のまわりから雪面の下りをたどる線のそばに、幹がいくつ立つか。「置き場所の印」: 別の起動でも同じなら、全員の画面で同じ所に当たる。
## --crash を足すと、木にぶつかって放り投げられるのを確かめる（--bots=2 で仲間も一緒に乗る。遅い・かすめるは飛ばない。起き上がったあと W で歩けるか）。
## 窓を出して --crash --strip=/path/dir を足すと、一人称で放り投げられる様子を 0.15 秒おきに撮る。--film も足すと、ソリの斜め後ろの上から 1/30 秒おきに撮る（動画用）。
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


var _crash_bad := 0
var _given := []


func _judge(ok: bool, line: String) -> void:
	print(("○ " if ok else "× ") + line)
	if not ok:
		_crash_bad += 1


## 木の手前にソリを置いて全員を乗せ、speed m/s で向かわせる。off は幹から横へずらす長さ (m)。全員の飛び方を見て返す
func _crash_run(t: Node3D, speed: float, off: float, secs: float, take_strip := false) -> Dictionary:
	var s: RigidBody3D = main.sled
	var o := Vector2(t.global_position.x, t.global_position.z)
	var g := _slope(o)
	var dir := -g.normalized() if g.length() > 0.01 else Vector2(1, 0)
	var side := Vector2(-dir.y, dir.x)
	var a: Vector2 = o - dir * (float(s.HALF.y) + 4.0) + side * off
	var folks: Array = [p] + get_nodes_in_group("bots").filter(func(b): return not b.lounge)
	for w in folks:
		if w.fling.active():
			await create_timer(4.0).timeout
	s.let_everyone_go()
	s.reset_to(Vector3(a.x, main.height(a.x, a.y) + 0.3, a.y))
	s.global_basis = Basis(Vector3.UP, atan2(-dir.x, -dir.y))
	for i in 10:
		await physics_frame
	var res := {}
	for w in folks:
		w.global_position = s.global_position + s.global_basis.x * 1.2
		if w == p:
			p.sled = s
			p.get_on()
		else:
			w.sled = s
			w.seat = s.mount(w)
			if w.seat != Vector3.INF:
				w._col.disabled = true
				w.state = w.State.RIDE
				w._ride_goal = o + dir * 200.0
				w._ride_t = 0.0
				w._still = 0.0
				w._goal_best = INF
				w._goal_t = 0.0
		res[w] = {"from": w.global_position, "apex": -INF, "far": 0.0, "dir": Vector3.ZERO, "seen": [], "rose": -1.0}
	s.parked = false
	s.linear_velocity = Vector3(dir.x, 0, dir.y) * speed
	var t0 := 0.0
	var snap := 0.0
	var i := 0
	while t0 < secs:
		await physics_frame
		t0 += 1.0 / Engine.physics_ticks_per_second
		for w in folks:
			var r: Dictionary = res[w]
			var st: int = w.doll.flung
			if r.seen.is_empty() or r.seen[-1] != st:
				r.seen.append(st)
				if st == 1:
					r.from = w.global_position
					r.t = t0
				if st == 0 and r.seen.size() > 1:
					r.rose = t0
			if st != 0:
				r.apex = maxf(r.apex, w.global_position.y - main.height(w.global_position.x, w.global_position.z))
				var d: Vector3 = w.global_position - r.from
				d.y = 0.0
				r.far = maxf(r.far, d.length())
				if d.length() > 2.0 and r.dir == Vector3.ZERO:
					r.dir = d.normalized()
		if take_strip and args.has("strip") and (res[p].seen.has(1) or args.has("film")) and t0 >= snap:
			snap = t0 + (1.0 / 30.0 if args.has("film") else 0.15)
			if args.has("film"):
				var fwd3 := Vector3(dir.x, 0, dir.y)
				var sd: Vector3 = Vector3(-dir.y, 0, dir.x)
				_side_cam(t.global_position - fwd3 * 11.0 + sd * 3.0 + Vector3.UP * 5.0, t.global_position + fwd3 * 8.0 + Vector3.UP * 1.0)
			await _strip_save(i)
			i += 1
	return {"res": res, "sled": s.global_position, "dir": dir, "riders": s.riders.size(), "sled_v": s.linear_velocity.length(), "o": o, "folks": folks}


## 山めぐりの仲間（--roam-bots=1）: 米袋で滑って木にぶつかり、飛んで、袋を帯に戻し、次の山へ歩き出すか
func _crash_roam() -> void:
	var b: Node = get_nodes_in_group("bots").filter(func(x): return x.roam)[0]
	var t: Node3D = _picks(_trees(main))[0]
	var o := Vector2(t.global_position.x, t.global_position.z)
	var a := o - Vector2(1, 0) * 8.0
	p.global_position = Vector3(o.x, main.height(o.x, o.y + 12.0) + 0.3, o.y + 12.0)
	b.global_position = Vector3(a.x, main.height(a.x, a.y) + 0.2, a.y)
	b.velocity = Vector3.ZERO
	b._ride_goal = o + Vector2(1, 0) * 60.0
	b.look_at(b.global_position + Vector3(1, 0, 0), Vector3.UP)
	b._roam_launch()
	var gs: RigidBody3D = b.sled
	_judge(gs.kind == "sack" and b.state == b.State.RIDE, "仲間が米袋に乗った（%s）" % gs.kind)
	gs.linear_velocity = Vector3(12.0, 0, 0)
	var seen := []
	var t0 := 0.0
	while t0 < 12.0:
		await physics_frame
		t0 += 1.0 / Engine.physics_ticks_per_second
		var st: int = b.doll.flung
		if seen.is_empty() or seen[-1] != st:
			seen.append(st)
		if seen.size() > 2 and st == 0:
			break
	_judge(seen.has(1) and seen[-1] == 0, "仲間が飛んで起き上がった: 段 %s、%.1f 秒" % [str(seen), t0])
	_judge(b.state != b.State.RIDE and b.seat == Vector3.INF and b.sled == main.sled, "席を離れ、ふだんのソリに戻った")
	await create_timer(1.0).timeout
	_judge(not is_instance_valid(gs) or not gs.visible or not gs.riders.has(b), "米袋に残っていない（米袋は帯へ戻す）")
	var from: Vector3 = b.global_position
	await create_timer(6.0).timeout
	_judge(b.global_position.distance_to(from) > 3.0, "そのあと歩き出した（%.1f m。行き先 %s）" % [b.global_position.distance_to(from), b._area])


func _strip_save(i: int) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(String(args.strip).path_join("%03d.png" % i))


func _crash() -> void:
	if args.has("strip"):
		DirAccess.make_dir_recursive_absolute(args.strip)
		p.set_third(false)
		for n in main.find_children("*", "CanvasLayer", true, false):
			if args.has("film"):
				n.visible = false
	var trees: Array = _picks(_trees(main.get_node("GrandMountain")))
	var hill: Array = _picks(_trees(main))
	var t: Node3D = hill[0]
	main.emotes.happened.connect(func(ev):
		if ev.kind == "flung" and ev.get("thrown", false):
			_given.append(ev))
	# 速いとき: 乗っている全員が別々の向きへ
	for speed in [8.0, 14.0, 20.0]:
		var r := await _crash_run(t, speed, 0.0, 6.0, speed == 14.0)
		var given := _given.duplicate()
		_given.clear()
		for w in r.folks:
			var x: Dictionary = r.res[w]
			var deg := rad_to_deg(Vector3(r.dir.x, 0, r.dir.y).signed_angle_to(x.dir, Vector3.UP)) if x.dir != Vector3.ZERO else 999.0
			_judge(x.seen.has(1) and x.rose > 0.0, "%s %.0f m/s %s: 段 %s、雪からいちばん %.1f m、飛んだ距離 %.1f m、飛んだ向き %+.0f°、起き上がるまで %.1f 秒" % [
					main.sled.kind, speed, "あなた" if w == p else "仲間 %d" % w.id, str(x.seen), x.apex, x.far, deg, x.rose - x.get("t", 0.0)])
		_judge(given.size() == r.folks.size(), "  配られた向き %d 人分: %s" % [given.size(), ", ".join(given.map(func(e):
				return "%+.0f° 速さ %.1f 上 %.1f" % [rad_to_deg(Vector3(r.dir.x, 0, r.dir.y).signed_angle_to(e.dir, Vector3.UP)), e.out, e.up]))])
		for i in given.size():
			for j in range(i + 1, given.size()):
				var apart := rad_to_deg((given[i].dir as Vector3).angle_to(given[j].dir))
				_judge(apart > 15.0, "  配られた向きが %.0f° 離れている" % apart)
		_judge(r.riders == 0, "  ソリに残った人 %d、ソリは幹のそば（%.1f m）で速さ %.1f m/s" % [r.riders, Vector2(r.sled.x, r.sled.z).distance_to(r.o), r.sled_v])
	# 起き上がったあと歩ける
	await create_timer(1.0).timeout
	var from: Vector3 = p.global_position
	await _key(KEY_W, true)
	await create_timer(1.0).timeout
	await _key(KEY_W, false)
	_judge(p.global_position.distance_to(from) > 1.0, "起き上がったあと W で %.1f m 歩けた" % p.global_position.distance_to(from))
	# 遅い: 飛ばず、乗ったまま止まる
	var slow := await _crash_run(t, 4.0, 0.0, 3.0)
	_judge(not slow.res[p].seen.has(1) and p.mode == p.Mode.RIDE, "4 m/s は飛ばない（乗ったまま）: 段 %s" % str(slow.res[p].seen))
	p.get_off()
	# 横をかすめる: ソリの幅の端で幹の端をこする（迫る速さが境目より遅い）
	var rad: float = preload("res://tree_hits.gd")._sizes[t.scene_file_path].x * t.scale.x
	_given.clear()
	var graze := await _crash_run(t, 12.0, float(main.sled.HALF.x) + rad - 0.02, 1.0)
	_judge(not graze.res[p].seen.has(1), "12 m/s で幹の端をかすめても飛ばない: 段 %s%s" % [str(graze.res[p].seen),
			"、飛んだ所は幹から %.1f m" % Vector2(_given[0].point.x, _given[0].point.z).distance_to(graze.o) if not _given.is_empty() else ""])
	p.get_off()
	# 大山の木でも
	var far := await _crash_run(trees[3], 12.0, 0.0, 5.0)
	_judge(far.res[p].seen.has(1), "大山の小さい木でも飛ぶ: 段 %s、飛んだ距離 %.1f m" % [str(far.res[p].seen), far.res[p].far])


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
	if args.has("crash-roam"):
		await _crash_roam()
		quit(1 if _crash_bad > 0 else 0)
		return
	if args.has("crash"):
		await _crash()
		quit(1 if _crash_bad > 0 else 0)
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
