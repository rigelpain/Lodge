extends SceneTree
## 右上の 360° 魚眼の小窓を、ロッジの中・入る途中・外で撮る（確かめ用）。場所ごとの fps と、小窓を切り抜いた絵を残す。
##   Godot --path game --resolution 1280x720 -s res://tools/fisheye_lodge_shots.gd -- --bots=1 --no-sound --dir=/path/shots
## --layers を付けると、ロッジの見た目の物の名前と描画の層を出す。--no-fps で fps を測らない。--only=名前 で 1 か所だけ撮る。
## --no-inside: ロッジの中身を映さない（直す前の見え方）。fps はロッジの箱の中で、中身の「あり・なし」を同じ場所で交互に測る

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D
var lines: Array[String] = []

# [名前, 立つ所 (glb の座標 x, 高さ, z。南 = +z が正面), 見る向きの先（同じ座標）]。魚眼は後ろ向きなので、見る先の反対が映る
const VIEWS := [
	["1f_dining", Vector3(6.0, 0.5, -4.0), Vector3(14.0, 1.5, -10.0)],
	["1f_dining_south", Vector3(2.0, 0.5, 6.0), Vector3(2.0, 1.5, 12.0)],
	["2f_zashiki", Vector3(0.0, 6.2, -6.0), Vector3(10.0, 7.5, -8.0)],
	["enter_vestibule", Vector3(-13.4, 0.5, 15.2), Vector3(-13.4, 1.5, 21.0)],
	["enter_inner", Vector3(-13.4, 0.5, 10.5), Vector3(-13.4, 1.5, 15.0)],
	["outside_door", Vector3(-13.4, -1.0, 22.0), Vector3(-13.4, 1.5, 30.0)],
	["outside_far", Vector3(-4.0, -1.0, 42.0), Vector3(-4.0, 1.5, 60.0)],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/fisheye_lodge")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _stand(v: Array) -> void:
	var at := lodge.to_global(v[1])
	if v[1].y < 0.0:   # 外は雪面の高さに立つ
		at.y = main.height(at.x, at.z) + 0.2
	var to := lodge.to_global(v[2])
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
	p.set("_pitch", 0.0)


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	p.set_third(false)
	lodge = main.get_node("Lodge")
	main.hud.idle_limit = 0.0   # 何もしないと小窓が画面の外へ引っこむので、止める
	if args.has("layers"):
		_dump_layers()
	for v in VIEWS:
		if args.has("only") and args["only"] != v[0]:
			continue
		_stand(v)
		await create_timer(0.6).timeout
		_stand(v)
		await create_timer(0.6).timeout
		_stand(v)
		if not args.has("no-fps"):
			await _measure(v[0])
		if args.has("no-inside"):
			_set_inside(false)
		else:
			_set_inside(main._pip_inside)
		await create_timer(0.8).timeout   # 6 面が描き直されるのを待つ
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(_dir().path_join(v[0] + "_screen.png"))
		var fr: Rect2 = main.pip_frame.get_global_rect()
		img.get_region(Rect2i(fr)).save_png(_dir().path_join(v[0] + ".png"))
	var f := FileAccess.open(_dir().path_join("fps.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()


func _set_inside(on: bool) -> void:
	for cam in main.pip_cams:
		cam.cull_mask = (cam.cull_mask | main.PIP_INSIDE_LAYER) if on else (cam.cull_mask & ~main.PIP_INSIDE_LAYER)


## 平均 fps を測る。ほかの重い仕事で揺れるので、箱の中では中身の「あり・なし」を交互に 3 回ずつ測る
func _measure(name: String) -> void:
	if not main._pip_inside:
		var a: Array = await _fps()
		_say("%s（箱の外）: 平均 %.1f fps、いちばん重いコマ %.1f ms" % [name, a[0], a[1]])
		return
	var on := []
	var off := []
	var worst_on := 0.0
	var worst_off := 0.0
	for i in 3:
		_set_inside(false)
		var a: Array = await _fps()
		off.append(a[0])
		worst_off = maxf(worst_off, a[1])
		_set_inside(true)
		var b: Array = await _fps()
		on.append(b[0])
		worst_on = maxf(worst_on, b[1])
	_say("%s: 中身なし 平均 %.1f fps（重いコマ %.1f ms）%s → あり 平均 %.1f fps（重いコマ %.1f ms）%s" % [name, _mean(off), worst_off, str(off), _mean(on), worst_on, str(on)])


func _mean(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / a.size()


## [平均 fps, いちばん重いコマ (ms)]。替えたあと 6 面が描き直されるまで（0.6 秒）は数えない
func _fps() -> Array:
	await create_timer(0.6).timeout
	var n := 0
	var t := 0.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	while t < 2.5:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1e6
		last = now
		t += dt
		n += 1
		worst = maxf(worst, dt)
	return [snappedf(n / t, 0.1), worst * 1000.0]


## ロッジの見た目の物の名前と層、物の数と面の数
func _dump_layers() -> void:
	var counts := {}
	for n in lodge.find_children("*", "VisualInstance3D", true, false):
		var m: VisualInstance3D = n
		if m is Light3D:
			continue
		var key := "層 %d" % m.layers
		counts[key] = counts.get(key, 0) + 1
		if m.get_parent() == lodge or m.get_parent().get_parent() == lodge:
			var size: Vector3 = m.get_aabb().size
			var tris := 0
			if m is MeshInstance3D and m.mesh:
				tris = m.mesh.get_faces().size() / 3
			_say("%s  層 %d  大きさ %s  三角形 %d" % [m.name, m.layers, size, tris])
	_say("まとめ: %s" % str(counts))
