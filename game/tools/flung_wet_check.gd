extends SceneTree
## 吹き飛ぶと濡れるかの確かめ（数字）。ソリに轢かれる・木にぶつかって放り投げられる、を、あなたと仲間で見る。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/flung_wet_check.gd -- --bots=1 --lodge-bots=0 --roam-bots=0 --no-pip --no-sound --no-buttons
## 窓を出して --shots=/path/dir を足すと、仲間の人形を吹き飛ぶ前と起き上がったあとで正面から撮る。

const Damp := preload("res://damp.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var bad := 0


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


func _judge(ok: bool, s: String) -> void:
	print(("○ " if ok else "× ") + s)
	if not ok:
		bad += 1


## 丘のなだらかな木（ほかの木から離れた、高い木）
func _tree() -> Node3D:
	var best: Node3D
	var low := INF
	for t in main.get_children():
		if not String(t.scene_file_path).get_file().begins_with("tree_") or t.scale.x < 1.0:
			continue
		var at := Vector2(t.position.x, t.position.z)
		var near := false
		for o in main.get_children():
			if o != t and String(o.scene_file_path).get_file().begins_with("tree_") and at.distance_to(Vector2(o.position.x, o.position.z)) < 14.0:
				near = true
		var g := Vector2(main.height(at.x + 1.0, at.y) - main.height(at.x - 1.0, at.y), main.height(at.x, at.y + 1.0) - main.height(at.x, at.y - 1.0)).length()
		if not near and g < low:
			low = g
			best = t
	return best


## 飛び始めてから起き上がるまでの水を見る。{before, top, after, hops}
func _watch(who: Node, secs: float, keep := Callable()) -> Dictionary:
	var id: int = who.id
	var before: float = main.damp.water_of(id)
	var at_fly := before
	var top := before
	var seen := []
	var hops := 0
	var t := 0.0
	while t < secs:
		await physics_frame
		t += 1.0 / 60.0
		var st: int = who.doll.flung
		if keep.is_valid() and st == 0 and seen.size() <= 1:
			keep.call()
		if seen.is_empty() or seen[-1] != st:
			seen.append(st)
			if st == 1:
				at_fly = main.damp.water_of(id)
		if st == 1 or st == 2:
			top = maxf(top, main.damp.water_of(id))
			hops = maxi(hops, who.fling.hops)
		if seen.size() > 2 and st == 0:
			break
	return {"before": at_fly, "top": top, "after": main.damp.water_of(id), "seen": seen, "hops": hops, "look": who.doll.damp}


## 木へ乗って向かう
func _ride_at(who: Node, t: Node3D, speed: float) -> void:
	var s: RigidBody3D = main.sled
	s.let_everyone_go()
	var o := Vector2(t.position.x, t.position.z)
	var a: Vector2 = o - Vector2(1, 0) * (float(s.HALF.y) + 4.0)
	s.reset_to(Vector3(a.x, main.height(a.x, a.y) + 0.3, a.y))
	s.global_basis = Basis(Vector3.UP, atan2(-1.0, 0.0))
	for i in 10:
		await physics_frame
	who.global_position = s.global_position + s.global_basis.x * 1.2
	if who == p:
		p.sled = s
		p.get_on()
	else:
		who.sled = s
		who.seat = s.mount(who)
		who._col.disabled = true
		who.state = who.State.RIDE
		who._ride_goal = o + Vector2(1, 0) * 200.0
		who._ride_t = 0.0
		who._still = 0.0
		who._goal_best = INF
		who._goal_t = 0.0
	s.parked = false
	s.linear_velocity = Vector3(speed, 0, 0)


## 立っている人へ、ソリを 10 m/s で走らせる
func _run_over(who: Node, at: Vector2) -> void:
	var s: RigidBody3D = main.sled
	s.let_everyone_go()
	if who != p:
		who.global_position = Vector3(at.x, main.height(at.x, at.y) + 0.1, at.y)
		who.velocity = Vector3.ZERO
	else:
		p.global_position = Vector3(at.x, main.height(at.x, at.y) + 0.1, at.y)
		p.velocity = Vector3.ZERO
	await physics_frame
	var a := at - Vector2(1, 0) * 8.0
	s.reset_to(Vector3(a.x, main.height(a.x, a.y) + 0.3, a.y))
	s.global_basis = Basis(Vector3.UP, atan2(-1.0, 0.0))
	for i in 5:
		await physics_frame
	s.parked = false
	s.linear_velocity = Vector3(10, 0, 0)


func _shot(name: String, who: Node3D) -> void:
	if not args.has("shots"):
		return
	var cam: Camera3D = main.get_node_or_null("ToolCam")
	if cam == null:
		cam = Camera3D.new()
		cam.name = "ToolCam"
		cam.cull_mask = 0xFFFFF
		main.add_child(cam)
	var t0 := 0.0
	while t0 < 1.0:   # 1 秒のあいだ、体の正面から見続ける（人の視点が戻ろうとしても）
		var at: Vector3 = who.global_position + Vector3.UP * 0.9
		var front: Vector3 = (who as Node3D).global_basis.z.normalized() if args.has("back") else -(who as Node3D).global_basis.z.normalized()
		cam.global_position = at + front * 2.4 + Vector3.UP * 0.25
		cam.look_at(at, Vector3.UP)
		cam.make_current()
		await process_frame
		t0 += 1.0 / 60.0
	root.get_viewport().get_texture().get_image().save_png(String(args.shots).path_join(name + ".png"))
	print("絵: ", name)


func _run() -> void:
	await create_timer(2.0).timeout
	p = main.player
	if args.has("shots"):
		DirAccess.make_dir_recursive_absolute(args.shots)
		p.set_third(true)
		for n in main.find_children("*", "CanvasLayer", true, false):
			n.visible = false
	var t := _tree()
	var o := Vector2(t.position.x, t.position.z)
	var field := o + Vector2(0, 14)
	var wet := Damp.FLUNG_WET
	var b: Node = get_nodes_in_group("bots")[0]
	var far := Vector2(o.x, o.y - 40.0)
	b.global_position = Vector3(far.x, main.height(far.x, far.y) + 0.1, far.y)

	# あなた: 木にぶつかる
	main.damp.put(p.id, 10.0)
	await _ride_at(p, t, 12.0)
	var r: Dictionary = await _watch(p, 9.0)
	_judge(r.seen.has(1) and absf(r.top - r.before - wet) < 3.0, "あなた 木にぶつかる: 水 %.1f → %.1f（増え %.1f。跳ねた %d）、段 %s" % [r.before, r.top, r.top - r.before, r.hops, str(r.seen)])

	# あなた: 轢かれる
	main.damp.put(p.id, 10.0)
	await _run_over(p, field)
	r = await _watch(p, 8.0, func(): main.sled.linear_velocity = Vector3(10, main.sled.linear_velocity.y, 0))
	_judge(r.seen.has(1) and absf(r.top - r.before - wet) < 3.0, "あなた 轢かれる: 水 %.1f → %.1f（増え %.1f）、段 %s" % [r.before, r.top, r.top - r.before, str(r.seen)])

	# パリッとしていても、濡れるとパリッとは消える
	main.damp.put(p.id, -30.0)
	await _run_over(p, field)
	r = await _watch(p, 8.0, func(): main.sled.linear_velocity = Vector3(10, main.sled.linear_velocity.y, 0))
	_judge(r.seen.has(1) and r.after > 15.0, "パリッと −30 から: 水 %.1f（パリッとは消える）" % r.after)

	# 飛ばなければ濡れない
	main.damp.put(p.id, 10.0)
	await _ride_at(p, t, 4.0)
	await create_timer(3.0).timeout
	_judge(p.mode == p.Mode.RIDE and main.damp.water_of(p.id) < 11.5, "4 m/s で当たって飛ばないときは濡れない: 水 %.1f" % main.damp.water_of(p.id))
	p.get_off()
	p.global_position = Vector3(far.x + 4.0, main.height(far.x + 4.0, far.y) + 0.1, far.y)

	# 仲間: 木にぶつかる
	main.damp.put(b.id, 0.0)
	await _ride_at(b, t, 12.0)
	r = await _watch(b, 9.0)
	_judge(r.seen.has(1) and r.top > wet - 3.0, "仲間 木にぶつかる: 水 %.1f → %.1f、段 %s" % [r.before, r.top, str(r.seen)])

	# 仲間: 轢かれる（当たるまで立たせておく）
	main.damp.put(b.id, 0.0)
	await _run_over(b, field)
	r = await _watch(b, 8.0, func():
		b.global_position = Vector3(field.x, main.height(field.x, field.y) + 0.05, field.y)
		main.sled.linear_velocity = Vector3(10, main.sled.linear_velocity.y, 0))
	_judge(r.seen.has(1) and r.top > wet - 3.0, "仲間 轢かれる: 水 %.1f → %.1f、段 %s" % [r.before, r.top, str(r.seen)])

	# 仲間はひとりでに乾く
	var w0: float = main.damp.water_of(b.id)
	await create_timer(10.0).timeout
	var w1: float = main.damp.water_of(b.id)
	_judge(w1 < w0 - 4.0, "仲間はひとりでに乾く: 10 秒で %.1f → %.1f" % [w0, w1])

	if args.has("shots"):
		main.damp.put(b.id, 0.0)
		await create_timer(3.0).timeout
		var hold := func(): b.global_position = Vector3(field.x, main.height(field.x, field.y) + 0.05, field.y)
		hold.call()
		await _shot("1_before", b)
		await _run_over(b, field)
		r = await _watch(b, 8.0, func():
			hold.call()
			main.sled.linear_velocity = Vector3(10, main.sled.linear_velocity.y, 0))
		print("仲間 水 %.1f → %.1f、見た目 %.2f、人形 %s" % [r.before, r.after, r.look, b.doll.kind])
		b.set_physics_process(false)   # 撮るあいだ、その場に止める
		await _shot("2_after", b)
	print("だめだった数: ", bad)
	quit(1 if bad > 0 else 0)
