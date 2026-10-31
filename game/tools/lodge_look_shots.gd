extends SceneTree
## ロッジの壁（丸太）・床・天井の見え方を撮り、場所ごとの fps を測る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/lodge_look_shots.gd -- --bots=1 --no-sound --dir=/path/shots
## 場所はロッジの座標（lodge/dims.py の x, y, 高さ）。それぞれ 3 秒止まって、最後の 2 秒の平均 fps と、いちばん重いコマを出す
## （--fixed-fps を付けずに流す。fps はこの機械の窓の大きさのまま）

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D
var lines: Array[String] = []

# [名前, 立つ所 (x, y), 目の高さの足し, 見る所 (x, y, 高さ)]
const VIEWS := [
	["01_front", Vector2(-4.0, -40.0), 0.0, Vector3(-4.0, 0.0, 3.0)],
	["02_corner", Vector2(-30.0, -24.0), 0.0, Vector3(-21.8, -12.7, 3.0)],
	["03_dining", Vector2(8.0, -8.0), 0.0, Vector3(-4.0, 6.0, 1.6)],
	["04_machine", Vector2(-13.0, 2.0), 0.0, Vector3(-19.1, 10.5, 1.4)],
	["05_ceiling", Vector2(2.0, 0.0), 0.0, Vector3(4.0, 3.0, 6.0)],
	["06_inner_wall", Vector2(-14.0, 5.0), 0.0, Vector3(-21.8, 5.0, 1.8)],
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
	return args.get("dir", "/tmp/lodge_look")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _w(q: Vector2) -> Vector3:
	var g := lodge.to_global(Vector3(q.x, 0, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 3.0, g + Vector3.DOWN * 30.0)
	r.exclude = [p.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else g


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	p.set_third(false)
	lodge = main.get_node("Lodge")
	for v in VIEWS:
		var at := _w(v[1]) + Vector3.UP * 0.05
		var to := lodge.to_global(Vector3(v[3].x, v[3].z, -v[3].y))
		p.global_position = at
		p.velocity = Vector3.ZERO
		p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
		var eye := at + Vector3.UP * 1.55
		p.set("_pitch", atan2(to.y - eye.y, Vector2(to.x - eye.x, to.z - eye.z).length()))
		await create_timer(0.5).timeout
		p.global_position = at   # 着地や仲間に押されてずれた分を戻し、向きも合わせ直す
		p.velocity = Vector3.ZERO
		p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
		p.set("_pitch", atan2(to.y - eye.y, Vector2(to.x - eye.x, to.z - eye.z).length()))
		await create_timer(0.5).timeout
		var n := 0
		var t := 0.0
		var worst := 0.0
		var last := Time.get_ticks_usec()
		while t < 2.0:
			await process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1e6
			last = now
			t += dt
			n += 1
			worst = maxf(worst, dt)
		_say("%s: 平均 %.0f fps、いちばん重いコマ %.1f ms" % [v[0], n / t, worst * 1000.0])
		await process_frame
		root.get_texture().get_image().save_png(_dir().path_join(v[0] + ".png"))
	var f := FileAccess.open(_dir().path_join("fps.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
