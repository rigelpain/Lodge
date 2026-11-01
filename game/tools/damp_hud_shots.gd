extends SceneTree
## 水と熱のゲージとバッジ（damp_hud.gd・badges.gd）を、ゲームの画面で撮る（確かめ用）。
##   Godot --path game --resolution 1600x900 -s res://tools/damp_hud_shots.gd -- --dir=/path [--values=80/40,10/50,60/100] [--mate=80/40] [--place=foot|fire] [--frames=12] [--coming=20]
## 値（水/熱）ごとに、一人称（水_熱_fp.png）と三人称（水_熱_tp.png）。あなたの値は固定し（なじませない）、仲間（2.2 m 先）には --mate の値を入れる。
## --place=fire はロッジの暖炉の前（暖炉を背に、こちらを向いた仲間）
## --coming はご飯でこれから上がる熱（しつけ糸とご飯のバッジを見る）

const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var p: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _bots() -> Array:
	return main.get_children().filter(func(c): return c != p and c.get("doll") != null and c.has_method("get_off"))


func _run() -> void:
	await _frames(30)
	p = main.player
	if main.settings:
		main.settings.set_open(false)
	main.hud.hints_on = false
	for b in _bots():
		b.set_physics_process(false)
	main.damp.authority = false   # 値はここで入れる
	var dir: String = args.get("dir", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var place: String = args.get("place", "foot")
	var b: Node3D = _bots()[0]
	_stage(place, b)
	var mate := String(args.get("mate", "80/40")).split_floats("/")
	for pair in String(args.get("values", "80/40,10/50,60/100")).split(","):
		var wh := pair.split_floats("/")
		var v := "%d_%d" % [int(wh[0]), int(wh[1])]
		main.damp.put(p.id, wh[0], wh[1])
		main.damp.put(b.id, mate[0], mate[1])
		main.damp.pending[p.id] = float(args.get("coming", "0"))
		for view in ["fp", "tp"]:
			p.set_third(view == "tp")
			await _frames(70)
			if main.craft_ui and main.craft_ui.gear_open:
				main.craft_ui.gear_open = false   # 撮っているあいだに窓が I の入力を受けても、持ち物の窓は閉じて撮る
				await _frames(3)
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(dir.path_join("%s_%s_%s.png" % [place, v, view]))
			# --frames=N: そこから 12 コマ／秒で N 枚（上がる矢印の伸び縮みを見る）
			for k in int(args.get("frames", "0")):
				var t0 := Time.get_ticks_msec()
				while Time.get_ticks_msec() - t0 < 83:
					await process_frame
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png(dir.path_join("%s_%s_%s_f%02d.png" % [place, v, view, k]))
		print("%s 水/熱=%s 点=%.2f 段=%s 歩く×%.2f 押す×%.2f バッジ=%s" % [place, v, main.damp.score(p.id), main.damp.STAGES[main.damp.stage_of(main.damp.score(p.id))][1],
			main.damp.speed_k(p.id), main.damp.push_k(p.id), str(main.badges.of(p.id))])
	quit()


## あなたを立たせ、仲間を 2.2 m 先でこちらへ向ける
func _stage(place: String, b: Node3D) -> void:
	var lodge: Node3D = main.get_node("Lodge")
	var at: Vector3
	var yaw: float
	if place == "fire":
		var fire := lodge.find_child("light_fire", true, false) as Node3D
		var f: Vector3 = fire.global_position if fire else lodge.to_global(Vector3(-10.4, 0, -9.0))
		var out := lodge.global_basis.z   # 炉から部屋の中へ（炉は北の壁）
		at = f + out * 4.2
		var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 4.0))
		at.y = hit.position.y + 0.05 if hit else lodge.global_position.y + 0.1
		yaw = atan2(out.x, out.z)   # 炉のほうを向く
	else:
		at = Vector3(6.0, 0, 30.0)
		at.y = main.height(at.x, at.z) + 0.05
		var d := Vector2(at.x - 1.5, at.z).normalized()
		yaw = atan2(d.y, -d.x)
	p.global_position = at
	p.rotation.y = yaw
	p._pitch = -0.12
	p.velocity = Vector3.ZERO
	var fwd: Vector3 = -p.global_basis.z
	var bp: Vector3 = at + fwd * 2.2 + p.global_basis.x * 0.5
	if place != "fire":
		bp.y = main.height(bp.x, bp.z)
	b.global_position = bp
	b.look_at(Vector3(at.x, bp.y, at.z), Vector3.UP)
	b.doll.act = Doll.Act.WALK
	b.doll.gaze = at + Vector3.UP * 1.2
