extends SceneTree
## 寒さのふるえと、暖かいロッジでのゆっくりした揺れを撮る（確かめ用）。
##   Godot --path game --resolution 960x540 -s res://tools/cold_shots.gd -- --dir=/path [--place=foot,door,inside] [--time=14]
##   7 体を並べて: Godot --path game --resolution 1280x540 -s res://tools/cold_shots.gd -- --lineup --no-pip --dir=/path [--place=foot,inside]
## 場所ごとに、仲間（2.2 m 先でこちらを向いて立つ）を正面から 12 コマ（1 秒）続けて撮り、一人称（fp）と三人称（tp）も 1 枚ずつ撮る。
## 名前は 場所_seq_00.png 〜 場所_seq_11.png、場所_fp.png、場所_tp.png。
## 揺れの大きさ（胸と手の、コマごとの動き）と、気温・ふるえ・落ち着きを出す。
## --move: ロッジの中から戸口の外へ出て、ふるえ・落ち着き・白い息がなじむ様子を 0.5 秒おきに出す（撮らない）

const Doll := preload("res://doll.gd")
const Audio := preload("res://audio.gd")
const SEQ := 12

var args := {}
var main: Node3D
var cam: Camera3D
var p: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 38
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
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
	if main.get("hud") != null:
		main.hud.visible = false
	for b in _bots():
		b.set_physics_process(false)
	if args.has("time"):
		root.get_node("DayCycle").hour = float(args["time"])
	if args.has("move"):
		await _move()
		quit()
		return
	if args.has("lineup"):
		await _lineup()
		quit()
		return
	var dir: String = args.get("dir", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var places: Array = args.get("place", "foot,door,inside").split(",")
	for place in places:
		await _stage(place)
		var b: Node3D = _bots()[0]
		# 仲間を正面やや横から
		var bf: Vector3 = -b.global_basis.z
		var side: Vector3 = bf.cross(Vector3.UP)
		var h: float = b.doll.height()
		cam.look_at_from_position(b.global_position + bf * 2.4 + side * 0.7 + Vector3.UP * h * 0.75, b.global_position + Vector3.UP * h * 0.5)
		cam.current = true
		var moves := []
		var last := []
		for k in SEQ:
			await _next_frame()
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(dir.path_join("%s_seq_%02d.png" % [place, k]))
			var now := _marks(b.doll)
			if not last.is_empty():
				var m := 0.0
				for i in now.size():
					m += (now[i] as Vector3).distance_to(last[i])
				moves.append(m / now.size() * 1000.0)
			last = now
		var avg := 0.0
		for m in moves:
			avg += m
		var tn := root.get_node("Temperature")
		print("%s: 気温=%.1f °C ふるえ=%.2f 落ち着き=%.2f 白い息=%.2f  胸と手のコマごとの動き 平均=%.1f mm 最大=%.1f mm" % [
			place, tn.at(b.doll._long.global_position), b.doll._shiver, b.doll._calm, b.doll._cold, avg / moves.size(), moves.max()])
		for view in ["fp", "tp"]:
			p.set_third(view == "tp")
			p._place_camera(1.0, 0.0, false)
			p.cam.current = true
			await _frames(20)
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(dir.path_join("%s_%s.png" % [place, view]))
	quit()


## 次のコマ（12 fps）まで待つ
func _next_frame() -> void:
	var f := Doll.frame_index()
	while Doll.frame_index() == f:
		await physics_frame


## 胸・頭・両手の所（世界）
func _marks(d: Node3D) -> Array:
	var out := []
	for n in ["chest", "head", "hand.L", "hand.R"]:
		var i: int = d._id(n)
		if i >= 0:
			out.append(d.skel.global_transform * (d._g[i] as Transform3D).origin)
	return out


## あなたは立ち、仲間 2 人は 2.2 m 先でこちらを向く。寒さがその場になじむまで待つ
func _stage(place: String) -> void:
	p.global_position = _place_pos(place)
	p.rotation.y = _yaw(place)
	p._pitch = -0.05
	p.velocity = Vector3.ZERO
	var fwd: Vector3 = -p.global_basis.z
	var bots := _bots()
	for i in bots.size():
		var b: Node3D = bots[i]
		var bp: Vector3 = p.global_position + fwd * 2.2 + p.global_basis.x * (0.9 * (i * 2 - 1))
		if place != "inside":
			bp.y = main.height(bp.x, bp.z)
		b.global_position = bp
		b.look_at(Vector3(p.global_position.x, bp.y, p.global_position.z), Vector3.UP)
		b.doll.act = Doll.Act.WALK
		b.doll.gaze = p.global_position + Vector3.UP * 1.2
	await _frames(60)
	for i in 1200:
		var ok := true
		for d in [p.doll] + bots.map(func(b): return b.doll):
			if absf(d._shiver - d._shiver_want) > 0.01 or absf(d._calm - d._calm_want) > 0.01 or absf(d._cold - d._cold_want) > 0.01:
				ok = false
		if ok:
			break
		await physics_frame


## 向き。外では丘と反対（空のほう）を向く（白い息が雪を背にすると見えないので）
func _yaw(place: String) -> float:
	if place == "foot" or place == "door":
		var d := Vector2(p.global_position.x - 1.5, p.global_position.z).normalized()
		return atan2(d.y, -d.x)
	return -PI / 2.0


func _place_pos(place: String) -> Vector3:
	var lodge: Node3D = main.get_node_or_null("Lodge")
	match place:
		"inside":
			return lodge.to_global(Vector3(0.0, 0.05, 4.0))
		"door":
			var d: Vector3 = lodge.to_global(Audio.VEST + Vector3(0, 0, 7.0))
			return Vector3(d.x, main.height(d.x, d.z) + 0.05, d.z)
	var base := Vector3(6.0, 0, 30.0)
	return Vector3(base.x, main.height(base.x, base.z) + 0.05, base.z)


## 7 体の人形（doll.gd の KINDS）を横一列に並べ、正面から撮る。場所ごとに、続けて 6 コマと、大きく息を吐かせて 0.6 秒後の 1 枚。
## 人形ごとの揺れの大きさと、ふるえ・落ち着き・白い息を出す。名前は lineup_場所.png、lineup_場所_seq_00.png 〜
func _lineup() -> void:
	var dir: String = args.get("dir", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var lodge: Node3D = main.get_node("Lodge")
	# あなたと仲間は写らない所へ（右上の小窓は --no-pip で消す）
	for n in [p] + _bots():
		n.global_position = Vector3(60, main.height(60, 60) + 0.1, 60)
	var places: Array = args.get("place", "foot,inside").split(",")
	for place in places:
		var hosts := []
		var center: Vector3
		var face: Vector3   # 人形が向く向き（カメラのほう）
		if place == "inside":
			center = lodge.to_global(Vector3(0.0, 0.05, 6.0))   # 柱より手前
			face = lodge.global_basis.z
		else:
			center = _place_pos(place)
			face = Vector3(center.x - 1.5, 0, center.z).normalized()   # 丘と反対（空のほう）を背に
			face = -face
		var side := face.cross(Vector3.UP).normalized()
		for i in Doll.KINDS.size():
			var h := Node3D.new()
			root.add_child(h)
			var at := center + side * (i - 3) * 1.05
			if place != "inside":
				at.y = main.height(at.x, at.z) + 0.02
			else:
				var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at - Vector3.UP * 3.0))
				if hit:
					at.y = hit.position.y + 0.02   # 床の上
			h.global_position = at
			h.look_at(at + face, Vector3.UP)
			var d := Doll.new()
			d.kind = Doll.KINDS[i]
			h.add_child(d)
			hosts.append(h)
		var floor_y: float = (hosts[3] as Node3D).global_position.y
		center.y = floor_y
		cam.look_at_from_position(center + face * (6.6 if place == "inside" else 7.0) + Vector3.UP * 1.1, center + Vector3.UP * 0.7)
		cam.current = true
		await _frames(150)   # 気温がなじむ（はじめはその場の値から）、glb を読む
		var last := {}
		var moves := {}
		for k in 6:
			await _next_frame()
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(dir.path_join("lineup_%s_seq_%02d.png" % [place, k]))
			for h in hosts:
				var d: Node3D = h.get_child(0)
				var now := _marks(d)
				if last.has(d):
					var m := 0.0
					for i in now.size():
						m += (now[i] as Vector3).distance_to(last[d][i])
					moves[d] = moves.get(d, 0.0) + m / now.size() * 1000.0 / 5.0
				last[d] = now
		for h in hosts:
			(h.get_child(0) as Node3D)._puff(1.7, 1.3)   # 声の息の大きさで（身ぶりはさせない: 腕が上がるとふるえの形が見えない）
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 600:
			await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(dir.path_join("lineup_%s.png" % place))
		var tn := root.get_node("Temperature")
		for h in hosts:
			var d: Node3D = h.get_child(0)
			print("%s %-8s 気温=%5.1f ふるえ=%.2f 落ち着き=%.2f 白い息=%.2f 吐いている=%s コマごとの動き=%.1f mm" % [
				place, d.kind, tn.at(d._long.global_position), d._shiver, d._calm, d._cold,
				d._streams["big"].emitting, moves.get(d, 0.0)])
		for h in hosts:
			h.queue_free()
		await _frames(5)


## ロッジの中から戸口の外へ出て、なじむ様子を出す
func _move() -> void:
	await _stage("inside")
	var d: Node3D = p.doll
	print("中: ふるえ=%.2f 落ち着き=%.2f 白い息=%.2f" % [d._shiver, d._calm, d._cold])
	p.global_position = _place_pos("door")
	var t0 := Time.get_ticks_msec()
	for k in 13:
		while (Time.get_ticks_msec() - t0) / 1000.0 < k * 0.5:
			await physics_frame
		print("出て %.1f 秒: ふるえ=%.2f 落ち着き=%.2f 白い息=%.2f" % [k * 0.5, d._shiver, d._calm, d._cold])
