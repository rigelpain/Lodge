extends SceneTree
## 仲間（CPU）のロッジへの寄り道の絵（bot_visit.gd）。山をめぐる仲間のうち 13 人をロッジの前に置いて寄り道を始めさせ、
## 暖炉のまわり（濡れて帰ってきて乾かす）・入口の人台と鏡・内階段・2 階のこたつを、少しずつ時間をおいて撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/cpu_visit_shots.gd -- --no-sound --roam-bots=20 --cpu-visit=0 --dir=/path/shots
## 0〜3 番: 水をいっぱいにして乾かしに、4〜7 番: 2 階のこたつ、8・9 番: 1 階の席、10 番: ランタン、11 番: 人台、12 番: 山の道具の棚

const PLANS := [["dry"], ["dry"], ["dry"], ["dry"], ["kotatsu"], ["kotatsu"], ["kotatsu"], ["kotatsu"], ["rest"], ["rest"], ["lantern"], ["wardrobe"], ["mountain"]]
## 撮る所（ロッジの座標）: [名前, カメラ, 見る先]
const VIEWS := [
	["hearth", Vector3(-3.0, 2.6, -1.0), Vector3(-10.4, 0.6, -8.5)],
	["entrance", Vector3(-9.0, 2.4, 3.0), Vector3(-16.5, 0.8, 9.0)],
	["stairs", Vector3(13.0, 3.2, -1.0), Vector3(19.0, 2.6, -9.0)],
	["kotatsu", Vector3(16.5, 8.4, 3.0), Vector3(2.0, 6.3, -3.5)],
]

var args := {}
var main: Node3D
var cam: Camera3D
var bots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg(dir.path_join(name), 0.9)
	print("撮った: ", dir.path_join(name))


func _views(tag: String) -> void:
	var lodge: Node3D = main.get_node("Lodge")
	for v in VIEWS:
		cam.global_position = lodge.to_global(v[1])
		cam.look_at(lodge.to_global(v[2]))
		await create_timer(0.4).timeout
		await _shot("%s_%s.jpg" % [tag, v[0]])
	var rows := []
	for b in bots:
		var vt: Dictionary = b.visit.task
		rows.append("#%d %s%s 水%.0f 移%d" % [b.id, "中%d階 " % b.visit.level if b.visit.inside else "外 ", String(vt.get("what", "-")) + ("(座る)" if b.seat_i >= 0 else ""),
				main.get_node("Damp").water_of(b.id), b.visit.warps])
	print(tag, ": ", " | ".join(rows))


func _run() -> void:
	await create_timer(1.5).timeout
	var p = main.player
	var lodge: Node3D = main.get_node("Lodge")
	p.global_position = lodge.to_global(Vector3(-20.0, 0.6, -11.5))   # 厨房の西の隅（通り道をふさがない）
	p.reset_physics_interpolation()
	bots = main.get_children().filter(func(c): return c.is_in_group("bots") and c.get("roam")).slice(0, PLANS.size())
	for i in bots.size():
		var b = bots[i]
		var o: Vector3 = b.visit._out_point() + Vector3((i % 5) * 1.2 - 2.4, 0, (i / 5) * 1.5)
		b.global_position = Vector3(o.x, main.height(o.x, o.z) + 0.1, o.z)
		b.reset_physics_interpolation()
		var wet: bool = PLANS[i][0] == "dry"
		if wet:
			main.get_node("Damp").put(b.id, 100.0)
		b.visit.reason = "wet" if wet else "rest"
		b._area = "lodge"
		b._route = []
		b.visit.enter()
		var plan: Array = []
		for k in PLANS[i]:
			plan.append({"kind": "seat", "what": "dry", "floor": 1} if k == "dry" else b.visit._task_of(k))
		b.visit.plan = plan
	cam = Camera3D.new()
	cam.fov = 62.0
	main.add_child(cam)
	cam.make_current()
	for tag in ["a", "b", "c"]:
		await create_timer(float(args.get("wait", "25"))).timeout
		await _views(tag)
	quit()
