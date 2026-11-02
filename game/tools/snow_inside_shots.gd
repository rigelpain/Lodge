extends SceneTree
## ロッジの中に舞う雪（main.gd の _make_snowfall）が降りこまないかを撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/snow_inside_shots.gd -- --bots=1 --no-sound --hud-idle=0 --dir=/path/shots [--only=名前,名前] [--snow-amount=5000] [--no-shelter] [--settle=10] [--flake=0.15] [--no-turbulence]
## 場所はロッジの座標（lodge/dims.py の x, y, 高さ）。置いたら雪を降らせ直し、粒が目の高さまで落ちてくるのを待って（--settle 秒。既定 10）撮る。
## 雪の粒は小さくまばらなので、--snow-amount で粒の数を増やすと、どこに降っているかが絵で見やすい（確かめ用。ゲームの既定は 500）。
## --no-turbulence で乱流を切った降り方にする。--flake で粒の半径を大きくする（既定 0.045 m）。--no-shelter で雪よけの箱（main.gd の _shelter_snow）を外し、直す前の降り方と比べる。場所ごとに、最後の 2 秒の平均 fps も出す

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D
var lines: Array[String] = []

# [名前, 立つ所 (x, y), 床を探す高さ, 見る所 (x, y, 高さ)]
const VIEWS := [
	["1f_dining", Vector2(8.0, -2.0), 3.0, Vector3(-6.0, 4.0, 2.2)],
	["1f_window", Vector2(4.0, -6.0), 3.0, Vector3(4.0, -30.0, 2.0)],
	["1f_kitchen", Vector2(4.0, 6.0), 3.0, Vector3(4.0, 12.0, 2.0)],
	["1f_mountain_man", Vector2(-12.0, -2.0), 3.0, Vector3(-18.3, 0.9, 2.0)],
	["2f_room", Vector2(14.0, 6.0), 9.0, Vector3(-10.0, 2.0, 7.6)],
	["2f_window", Vector2(0.0, 2.0), 9.0, Vector3(0.0, -30.0, 7.0)],
	["vest_in", Vector2(-13.4, -14.0), 3.0, Vector3(-13.4, -30.0, 2.0)],
	["vest_door_out", Vector2(-13.4, -22.0), 3.0, Vector3(-13.4, -12.0, 2.0)],
	["terrace", Vector2(-4.0, -10.5), 9.0, Vector3(-4.0, -30.0, 6.0)],
	["outside_front", Vector2(-4.0, -40.0), 3.0, Vector3(-4.0, 0.0, 5.0)],
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
	return args.get("dir", "/tmp/snow_inside")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _w(q: Vector2, top: float) -> Vector3:
	var g := lodge.to_global(Vector3(q.x, 0, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g + Vector3.UP * top, g + Vector3.DOWN * 30.0)
	r.exclude = [p.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else g


func _aim(at: Vector3, to: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
	var eye := at + Vector3.UP * 1.55
	p.set("_pitch", atan2(to.y - eye.y, Vector2(to.x - eye.x, to.z - eye.z).length()))


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	p.set_third(false)
	lodge = main.get_node("Lodge")
	if main.snowfall and args.has("snow-amount"):
		main.snowfall.amount = int(args["snow-amount"])
	if main.snowfall and args.has("flake"):   # 粒を大きくして見やすく（確かめ用）
		var m := main.snowfall.draw_pass_1.duplicate() as SphereMesh
		m.radius = float(args["flake"])
		m.height = m.radius * 2.0
		main.snowfall.draw_pass_1 = m
	if main.snowfall and args.has("no-turbulence"):   # 乱流を切った降り方（粒がまっすぐ目の高さまで落ちてくる）でも確かめる
		var pm := main.snowfall.process_material as ParticleProcessMaterial
		pm.turbulence_enabled = false
		pm.spread = 40.0
	if args.has("no-shelter"):
		(main.snowfall.process_material as ParticleProcessMaterial).collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
		for c in lodge.get_children():
			if c is GPUParticlesCollisionBox3D:
				c.queue_free()
	var only: Array = args["only"].split(",") if args.has("only") else []
	for v in VIEWS:
		if not only.is_empty() and not only.has(v[0]):
			continue
		var at := _w(v[1], v[2]) + Vector3.UP * 0.05
		var to := lodge.to_global(Vector3(v[3].x, v[3].z, -v[3].y))
		_aim(at, to)
		await create_timer(0.5).timeout
		_aim(at, to)   # 着地や仲間に押されてずれた分を戻す
		if main.snowfall:
			main.snowfall.restart()   # 雪は世界に残るので、ここで降らせ直す
		await create_timer(float(args.get("settle", "10"))).timeout   # preprocess の 10 秒では、上で生まれた粒がまだ目の高さまで落ちきらない
		_aim(at, to)
		var n := 0
		var t := 0.0
		var last := Time.get_ticks_usec()
		while t < 2.0:
			await process_frame
			var now := Time.get_ticks_usec()
			t += (now - last) / 1e6
			last = now
			n += 1
		_say("%s: 平均 %.0f fps" % [v[0], n / t])
		await process_frame
		root.get_texture().get_image().save_png(_dir().path_join(v[0] + ".png"))
	var f := FileAccess.open(_dir().path_join("fps.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
