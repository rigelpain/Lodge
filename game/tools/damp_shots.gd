extends SceneTree
## 紙の人形の水（damp.gd・doll.gd の damp）の見た目を撮る（確かめ用）。値は −40（パリパリ）〜 100（びしょびしょ）
##   段ごとに 7 体を並べて: Godot --path game --resolution 1600x600 -s res://tools/damp_shots.gd -- --dir=/path [--place=foot|inside] [--values=100,0,-40]
##     → lineup_場所_値.png（値ごとに 1 枚）
##   1 体を段ごとに並べて: ... -- --stages --kinds=kasa,golem --dir=/path [--values=100,60,20,-20,-40]
##     → stages_場所_人形.png（左から値の順）
## 人形の値はそのまま入れる（なじむのを待たない）。--seq でそこから 6 コマ続けて撮る（コマの間隔を見る）

const Doll := preload("res://doll.gd")
const Damp := preload("res://damp.gd")

var args := {}
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 34
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await _frames(30)
	if main.settings:
		main.settings.set_open(false)
	if main.get("hud") != null:
		main.hud.visible = false
	if main.get("damp") != null:
		main.damp.set_physics_process(false)   # 値はここで入れる
	if args.has("time"):
		root.get_node("DayCycle").hour = float(args["time"])
	for n in main.get_children():
		if n.get("doll") != null and n is CharacterBody3D:
			n.global_position = Vector3(60, main.height(60, 60) + 0.1, 60)
			n.set_physics_process(false)
	var dir: String = args.get("dir", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var place: String = args.get("place", "foot")
	var values: Array = Array(String(args.get("values", "100,0,-40")).split_floats(","))
	if args.has("stages"):
		for kind in String(args.get("kinds", "kasa")).split(","):
			await _row(place, values.map(func(_v): return kind), values, dir.path_join("stages_%s_%s.png" % [place, kind]))
	else:
		var kinds: Array = Array(String(args.get("kinds", ",".join(Doll.KINDS))).split(","))
		for v in values:
			await _row(place, kinds, kinds.map(func(_k): return v), dir.path_join("lineup_%s_%d.png" % [place, int(v)]))
	quit()


## 人形を横一列に並べて撮る（kinds[i] の人形に values[i] の水）
func _row(place: String, kinds: Array, values: Array, path: String) -> void:
	var lodge: Node3D = main.get_node("Lodge")
	var center: Vector3
	var face: Vector3
	if place == "inside":
		center = lodge.to_global(Vector3(0.0, 0.05, 6.0))
		face = lodge.global_basis.z
	else:
		center = Vector3(6.0, 0.0, 30.0)
		center.y = main.height(center.x, center.z)
		face = -Vector3(center.x - 1.5, 0, center.z).normalized()
	var side := Vector3.UP.cross(face).normalized()   # 画面の左から右へ
	var hosts := []
	var n := kinds.size()
	# 人形の幅（足もとの影から）で間を取る
	var widths: Array = kinds.map(func(k): return Doll.FOOT_SHADOW[k] * Doll.SCALE[k] * 2.3 + 0.2)
	var total: float = widths.reduce(func(a, w): return a + w, 0.0)
	var x := -total / 2.0
	for i in n:
		var h := Node3D.new()
		root.add_child(h)
		x += widths[i] / 2.0
		var at := center + side * x
		x += widths[i] / 2.0
		if place != "inside":
			at.y = main.height(at.x, at.z) + 0.02
		else:
			var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at - Vector3.UP * 3.0))
			if hit:
				at.y = hit.position.y + 0.02
		h.global_position = at
		h.look_at(at + face, Vector3.UP)
		var d := Doll.new()
		d.kind = kinds[i]
		d.damp = Damp.look_of(float(values[i]))
		d.pose_step = Damp.pose_step_of(float(values[i]))
		h.add_child(d)
		d._next_breath = 1 << 30   # 白い息で顔が隠れないように
		hosts.append(h)
	center.y = (hosts[n / 2] as Node3D).global_position.y
	var back := total * 0.62 + 1.2
	cam.look_at_from_position(center + face * back + Vector3.UP * 1.0, center + Vector3.UP * 0.68)
	cam.current = true
	await _frames(150)
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(path)
	if args.has("seq"):
		for k in 6:
			var f := Doll.frame_index()
			while Doll.frame_index() == f:
				await physics_frame
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(path.get_basename() + "_seq_%02d.png" % k)
	for i in n:
		var d: Doll = hosts[i].get_child(0)
		print("%s %-8s 水=%4d 見た目=%.2f 段=%s" % [place, d.kind, int(values[i]), d._damp_shown, Damp.STAGES[Damp.stage_of(float(values[i]))][1]])
	for h in hosts:
		h.queue_free()
	await _frames(5)
