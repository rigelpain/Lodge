extends SceneTree
## 斜面に置いた小物（木・岩・旗・網・案内板・スピーカーの柱など、glb の小物）が、見た目の雪面から浮いていないかの確かめ。
##   Godot --path game --resolution 1280x800 -s res://tools/prop_float_check.gd -- --no-player --no-snow --bots=0 [--dir=/path/shots --tag=before]
## 小物ごとに、いちばん下の部分（根もと・柱の下の端）の頂点が、その真下の見た目の雪面（吹きだまりを含む）から何 m 上にあるかを測る。
## 0.03 m より上に出ていれば「浮いている」。種類ごとの数といちばん浮いた量を出す。
## --dir を渡すと、いちばん浮いている木（丘と大きな山で 2 本ずつ）を、斜面の目線で撮る（<tag>_float_<n>.png）。
## --at=x,z,x,z… を渡すと、その木を撮る（前と後で同じ木を撮る用）

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main.hud:
		main.hud.visible = false
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	return false


func _snow(x: float, z: float) -> float:
	return main.height(x, z) + main.snow_lift(x, z)


## 小物のいちばん下の部分の頂点（世界の座標）
func _bottom(n: Node3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var xf := m.global_transform
		for s in m.mesh.get_surface_count():
			for v in m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(xf * v)
	if pts.is_empty():
		return pts
	var low := INF
	for p in pts:
		low = minf(low, p.y)
	var out := PackedVector3Array()
	for p in pts:
		if p.y < low + 0.12 * n.scale.y:
			out.append(p)
	return out


func _run() -> void:
	for i in 10:
		await process_frame
	var nodes: Array = main.get_children()
	if main.has_node("Mountain"):
		nodes += main.get_node("Mountain").get_children()
	nodes += main.find_children("SpeakerPost*", "Node3D", true, false)
	var stats := {}
	var trees := []   # [浮き, ノード, 丘か山か]
	for n in nodes:
		if not (n is Node3D) or (n.scene_file_path == "" and not n.name.begins_with("SpeakerPost")):
			continue
		var kind: String = "speaker_post" if n.name.begins_with("SpeakerPost") else n.scene_file_path.get_file().get_basename()
		var gap := -INF
		for p in _bottom(n):
			gap = maxf(gap, p.y - _snow(p.x, p.z))
		if gap == -INF:
			continue
		var s: Dictionary = stats.get(kind, {"n": 0, "float": 0, "max": -INF})
		s.n += 1
		if gap > 0.03:
			s.float += 1
		s.max = maxf(s.max, gap)
		stats[kind] = s
		if kind.begins_with("tree"):
			trees.append([gap, n, "mountain" if n.get_parent() != main else "hill"])
	print("小物の浮き（根もとの頂点が、見た目の雪面から何 m 上か。0.03 m より上が浮いている）:")
	var total := 0
	var fl := 0
	for k in stats:
		var s: Dictionary = stats[k]
		total += s.n
		fl += s.float
		print("  %-16s %3d 個のうち浮いている %3d 個、いちばん浮いた %.2f m" % [k, s.n, s.float, s.max])
	print("ぜんぶで %d 個のうち浮いている %d 個" % [total, fl])
	if not args.has("dir"):
		quit()
		return
	var pick := []
	if args.has("at"):
		var v: PackedFloat64Array = args["at"].split_floats(",")
		for i in range(0, v.size(), 2):
			var best: Node3D = null
			for t in trees:
				if best == null or Vector2(t[1].position.x - v[i], t[1].position.z - v[i + 1]).length() < Vector2(best.position.x - v[i], best.position.z - v[i + 1]).length():
					best = t[1]
			pick.append(best)
	else:
		trees.sort_custom(func(a, b): return a[0] > b[0])
		for place in ["hill", "mountain"]:
			var c := 0
			for t in trees:
				if t[2] == place and c < 2:
					pick.append(t[1])
					c += 1
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.make_current()
	cam.fov = 50.0
	for i in pick.size():
		var n: Node3D = pick[i]
		var p := Vector3.ZERO   # 根もとのまんなか（glb の形が原点からずれていても、木の立つ所）
		var bt := _bottom(n)
		for q in bt:
			p += q / bt.size()
		# 下りの向き（浮くのは下りの側）から斜めに、根もとの高さで見る
		var gx: float = main.height(p.x + 1.0, p.z) - main.height(p.x - 1.0, p.z)
		var gz: float = main.height(p.x, p.z + 1.0) - main.height(p.x, p.z - 1.0)
		var down := -Vector2(gx, gz).normalized() if Vector2(gx, gz).length() > 0.01 else Vector2(0, -1)
		var side := Vector2(-down.y, down.x)
		var r: float = 7.0 * n.scale.y
		var at := Vector2(p.x, p.z) + (down * 0.6 + side * 0.8).normalized() * r
		cam.position = Vector3(at.x, _snow(at.x, at.y) + 1.2, at.y)
		cam.look_at(Vector3(p.x, _snow(p.x, p.z) + 0.6 * n.scale.y, p.z))
		for k in 6:
			await process_frame
		var path: String = args["dir"].path_join("%s_float_%d.png" % [args.get("tag", "now"), i])
		root.get_texture().get_image().save_png(path)
		var gap := -INF
		for q in _bottom(n):
			gap = maxf(gap, q.y - _snow(q.x, q.z))
		print("保存: %s（%s、置いた所 x=%.1f z=%.1f、浮き %.2f m）" % [path, n.scene_file_path.get_file(), n.position.x, n.position.z, gap])
	quit()
