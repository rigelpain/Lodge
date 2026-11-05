extends SceneTree
## 机のある席での食べ方を撮る（確かめ用。design/food-look/table-eat.md）。席の一覧も出す。
##   Godot --path game --resolution 1280x720 -s res://tools/food_table_shots.gd -- --bots=0 --no-pip --dir=/path/shots --dishes=ramen,nikuman [--ext] [--kind=chair] [--stand]
## 既定は一人称。--ext でそばのカメラから人形を見る（ほかの人の画面と同じ人形の動き）。名前は <料理>_<コマ>.png
## --stand で、立って食べると前の 3 口の身ぶり（eat）のままかを確かめて出す

const Food := preload("res://food.gd")
const TableEat := preload("res://table_eat.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/food_table")


func _shot(name: String) -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	p.set_third(false)
	var seats = p.seats
	var count := {}
	for i in seats.seats.size():
		var s: Dictionary = seats.seats[i]
		var key := "%s %s" % [s.kind, "机あり" if s.has("table") else "机なし"]
		count[key] = count.get(key, 0) + 1
		if args.has("list"):
			print(i, " ", s.kind, " 腰 ", s.pos.snappedf(0.01), " 机 ", s.get("table", "なし"))
	print("席: ", count)
	var dishes: Array = String(args.get("dishes", "ramen")).split(",")
	var craft = main.craft
	if args.has("stand"):
		p.global_position = main.snowman_shop.counter.global_position + main.snowman_shop.counter.global_basis.z * -2.2 + Vector3.UP * 0.1
		await create_timer(0.5).timeout
		craft._put(p.id, {"kind": "food", "dish": "nikuman", "step": Food.route("nikuman").size(), "bites": 0})
		await create_timer(0.3).timeout
		p.eat_held()
		await create_timer(0.3).timeout
		print("立って食べる: 身ぶり ", p.get("_em").get("kind", ""), " 机の状況 ", p.table_ctx())
		await create_timer(5.0).timeout
		print("3 口のあと: 手 ", p.held())
		quit()
		return
	var seat_i := -1
	var want: String = args.get("kind", "chair")
	for i in seats.seats.size():
		if seats.seats[i].kind == want and seats.seats[i].has("table"):
			seat_i = i
			break
	if seat_i < 0:
		print("席がない: ", want)
		quit()
		return
	var st: Dictionary = seats.seats[seat_i]
	p.global_position = st.stand
	await create_timer(0.3).timeout
	print("座る ", seats.send({"kind": "sit", "who": p.id, "seat": seat_i}))
	await create_timer(1.2).timeout
	p.rotation.y = atan2(-st.face.x, -st.face.z)
	p.set("_pitch", -0.35)
	print("目 ", p.cam.global_position, " 腰 ", st.pos, " 机 ", st.table, " 人形 ", p.doll.kind)
	var cam2: Camera3D = null
	if args.has("ext"):
		var right: Vector3 = st.face.cross(Vector3.UP).normalized()
		cam2 = Camera3D.new()
		cam2.fov = 42.0
		cam2.cull_mask = 1 | (1 << 1) | (1 << 3) | (1 << 7)
		root.add_child(cam2)
		cam2.look_at_from_position(st.pos + right * -1.05 + st.face * 0.95 + Vector3.UP * 0.75, st.pos + st.face * 0.28 + Vector3.UP * 0.32)
		cam2.current = true
	for dish in dishes:
		var slot: int = craft.hands.get(p.id, -1)
		if slot >= 0:
			craft._clear(p.id, slot)
		var i: int = craft._put(p.id, {"kind": "food", "dish": dish, "step": Food.route(dish).size(), "bites": 0})
		craft.hands[p.id] = i
		await create_timer(0.4).timeout
		await _shot("%s_rest" % dish)
		print(dish, " 机の状況 ", p.table_ctx().get("dish", "なし"))
		var style: String = TableEat.style_of(dish)
		var want_bites := 2 if style == "slurp" else 1
		p.eat_held()
		p.set("_eating", style == "slurp")
		var spec: Dictionary = TableEat.STYLES[style]
		var total: int = spec.len * want_bites
		var at := 0
		var n := 0
		var t0 := -1
		var last_frame := -1
		for frame in 2000:
			await process_frame
			var em: Dictionary = p.get("_em")
			if em.get("kind", "") != "eat_t":
				continue
			if t0 < 0:
				t0 = int(em.frame)
			var f: int = preload("res://doll.gd").frame_index() - t0
			if f >= total:
				break
			if f >= at and f != last_frame:
				last_frame = f
				await _shot("%s_%02d" % [dish, n])
				n += 1
				at += maxi(1, total / 8)
		p.set("_eating", false)
		await create_timer(0.3).timeout
		print(dish, " ", style, " 撮った ", n, " 手 ", p.held().get("bites", "空"))
		await create_timer(max(0.3, spec.len / 12.0 - 0.3)).timeout
	if cam2:
		cam2.queue_free()
	quit()
