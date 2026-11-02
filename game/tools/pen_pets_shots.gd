extends SceneTree
## 山師の柵と遊び場のミニオンの動きを撮る（確かめ用）。
##   Godot --path game --resolution 960x540 -s res://tools/pen_pets_shots.gd -- --spawn=mountain --dir=/path/shots [--secs=8] [--check=60] [--near]
## 撮るもの: frame_000.png〜（12 コマ／秒で secs 秒。gif と、コマを並べた絵は ffmpeg で作る）
## --check の秒だけ回して、ミニオンごとに、歩く・座る・寝るの割合、柵の外や物の円の中に入ったコマの数をログに出す

const PenPets := preload("res://pen_pets.gd")

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/pen_pets")


func _process(_dt: float) -> bool:
	if main and main.craft_ui and main.craft_ui.gear_open:
		main.craft_ui.close_gear()
	return false


func _run() -> void:
	await create_timer(2.0).timeout
	var mm: Node3D = main.mountain_man
	var pp: Node3D = mm.get_node_or_null("PenPets")
	while pp == null:
		await create_timer(0.3).timeout
		pp = mm.get_node_or_null("PenPets")
	for n in main.get_children():
		if n is CanvasLayer:
			n.visible = false
	var cam := Camera3D.new()
	cam.cull_mask &= ~(1 << 2)
	cam.fov = 50
	main.add_child(cam)
	var c: Vector3 = Vector3(-5.3, 0.3, 1.1) * pp.scale_xz
	var near := args.has("near")   # 近くから（柵の前の、客の目の高さ）
	cam.look_at_from_position(mm.to_global(c + (Vector3(0.6, 1.3, -2.9) if near else Vector3(0.8, 2.6, -4.4))), mm.to_global(c))
	cam.make_current()
	main.player.global_position = mm.to_global(Vector3(-2.0, 0.1, -3.5))
	var secs := float(args.get("secs", "8"))
	var n := int(secs * 12.0)
	var last := -1
	var k := 0
	while k < n:
		await process_frame
		var fi := preload("res://doll.gd").frame_index()
		if fi != last:
			last = fi
			root.get_texture().get_image().save_png(_dir().path_join("frame_%03d.png" % k))
			k += 1
	# 長く回して、ふるまいと、めり込みを数える
	var check := float(args.get("check", "0"))
	if check > 0.0:
		var stats := {}
		var t := 0.0
		while t < check:
			await create_timer(0.25).timeout
			t += 0.25
			for m in pp._pets:
				var s: Dictionary = stats.get(m.key, {"walk": 0, "sit": 0, "sleep": 0, "out": 0, "acts": {}})
				s[m.pose] += 1
				s.acts[m.act] = int(s.acts.get(m.act, 0)) + 1
				var p := Vector2(m.pos.x, m.pos.z)
				if not PenPets.AREA.grow(0.05).has_point(p):
					s.out += 1
				elif not (m.act in ["bed", "perch"]) and not pp._free(p, -0.05):
					s.out += 1
				stats[m.key] = s
		for key in stats:
			print("%s  歩く %d 座る %d 寝る %d  はみ出し %d  していたこと %s" % [key, stats[key].walk, stats[key].sit, stats[key].sleep, stats[key].out, stats[key].acts])
	quit(0)
