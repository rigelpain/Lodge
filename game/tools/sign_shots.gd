extends SceneTree
## 外の道しるべ（案内板）と、そのまわりの当たり判定を撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/sign_shots.gd -- --bots=0 --lodge-bots=0 --no-sound --no-pip --dir=/path/shots
## 道しるべごとに、正面・横・真上・まわりの地図を撮る。玄関前の広場の南の縁の段（前の道しるべの立っていた所と両の角）も撮る。当たり判定は色の線で重ねる（赤: 箱・筒などの形、橙: ロッジの床と段の面の縁、
## 青: 道しるべの柱の当たり）。道しるべの矢印が向く先は黄の線（板の矢印の向き、長さ 4 m）、行き先は緑の線。
## --tag=before_ のように付けると、名前の頭に付ける。<dir>/<名前>.png に書く

const SIGNS := ["sign_lodge", "sign_slope"]

var args := {}
var main: Node3D
var cam: Camera3D
var lines_mi: MeshInstance3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/sign_shots")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open:
		main.settings.set_open(false)
		if main.player:
			main.player.menu_open = false
	return false


func _signs() -> Array:
	var out := []
	for n in main.find_children("*", "Node3D", true, false):
		var f := String((n as Node).scene_file_path)
		for key in SIGNS:
			if f.ends_with(key + ".glb"):
				out.append([key, n])
	return out


## 色の線を足す（ImmediateMesh。見た目の上に重ねて、隠れても見える）
func _lines(segs: Array, color: Color, im: ImmediateMesh) -> void:
	if segs.is_empty():
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.no_depth_test = true
	m.render_priority = 10
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	for s in segs:
		im.surface_add_vertex(s[0])
		im.surface_add_vertex(s[1])
	im.surface_end()


func _box_segs(xf: Transform3D, size: Vector3) -> Array:
	var h := size / 2.0
	var c := []
	for i in 8:
		c.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	var out := []
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		out.append([c[e[0]], c[e[1]]])
	return out


func _cyl_segs(xf: Transform3D, r: float, h: float) -> Array:
	var out := []
	var n := 16
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		for y in [-h / 2.0, h / 2.0]:
			out.append([xf * Vector3(cos(a0) * r, y, sin(a0) * r), xf * Vector3(cos(a1) * r, y, sin(a1) * r)])
		if k % 4 == 0:
			out.append([xf * Vector3(cos(a0) * r, -h / 2.0, sin(a0) * r), xf * Vector3(cos(a0) * r, h / 2.0, sin(a0) * r)])
	return out


## 近く（中心から r の中）の当たり判定の形を線にする
func _overlay(center: Vector3, r: float) -> void:
	if lines_mi:
		lines_mi.queue_free()
	var im := ImmediateMesh.new()
	lines_mi = MeshInstance3D.new()
	lines_mi.mesh = im
	lines_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(lines_mi)
	var prim := []
	var pole := []
	var tri := []
	for cs in main.find_children("*", "CollisionShape3D", true, false):
		var c := cs as CollisionShape3D
		if c.disabled or c.shape == null:
			continue
		var xf := c.global_transform
		var near := xf.origin.distance_to(center) < r + 3.0
		var into: Array = pole if c.has_meta("sign_pole") else prim
		if c.shape is BoxShape3D and near:
			into.append_array(_box_segs(xf, (c.shape as BoxShape3D).size))
		elif c.shape is CylinderShape3D and near:
			into.append_array(_cyl_segs(xf, c.shape.radius, c.shape.height))
		elif c.shape is ConcavePolygonShape3D:
			var f: PackedVector3Array = (c.shape as ConcavePolygonShape3D).get_faces()
			for i in range(0, f.size(), 3):
				var a := xf * f[i]
				var b := xf * f[i + 1]
				var d := xf * f[i + 2]
				if Vector2(a.x - center.x, a.z - center.z).length() > r and Vector2(b.x - center.x, b.z - center.z).length() > r:
					continue
				tri.append_array([[a, b], [b, d], [d, a]])
	_lines(tri, Color(1.0, 0.55, 0.1), im)
	_lines(prim, Color(1.0, 0.1, 0.1), im)
	_lines(pole, Color(0.1, 0.5, 1.0), im)


func _arrows(sign: Node3D, target: Vector3) -> void:
	var im := lines_mi.mesh as ImmediateMesh
	var base := sign.global_position + Vector3.UP * 1.25
	var arrow := sign.global_basis.x
	arrow.y = 0
	_lines([[base, base + arrow.normalized() * 4.0]], Color(1.0, 0.9, 0.1), im)
	var to := target - sign.global_position
	to.y = 0
	_lines([[base + Vector3.UP * 0.1, base + Vector3.UP * 0.1 + to.normalized() * 4.0]], Color(0.1, 0.9, 0.3), im)


func _shoot(name: String, from: Vector3, at: Vector3, ortho := 0.0) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho > 0.0 else Camera3D.PROJECTION_PERSPECTIVE
	if ortho > 0.0:
		cam.size = ortho
	cam.global_position = from
	var up := Vector3.UP if absf((at - from).normalized().y) < 0.95 else Vector3.FORWARD
	cam.look_at(at, up)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	print("撮った: ", name)


func _run() -> void:
	await create_timer(3.0).timeout
	var p: CharacterBody3D = main.player
	if p:
		p.global_position = Vector3(0, 60, -300)   # あなたは遠くへどけておく
		p.set_physics_process(false)
	main.sled.reset_to(Vector3(30, 40, -30))
	for c in main.find_children("*", "CanvasLayer", true, false):   # 画面の表示は隠す
		(c as CanvasLayer).visible = false
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 400.0
	main.add_child(cam)
	cam.make_current()
	var ent: Vector2 = main.lodge_to_world(Vector2(main.PATH_X, 17.0))
	var targets := {"sign_lodge": Vector3(ent.x, 0, ent.y), "sign_slope": Vector3.ZERO}
	for e in _signs():
		var key: String = e[0]
		var s: Node3D = e[1]
		var o := s.global_position
		_overlay(o, 3.0)
		_arrows(s, targets[key])
		var front := -s.global_basis.z   # 板の表（アップリケの側）の向き
		front.y = 0
		front = front.normalized()
		var side := s.global_basis.x
		side.y = 0
		side = side.normalized()
		var tag: String = args.get("tag", "")
		await _shoot("%s%s_front" % [tag, key], o + front * 3.6 + Vector3.UP * 1.6, o + Vector3.UP * 1.0)
		await _shoot("%s%s_side" % [tag, key], o + side * 3.6 + Vector3.UP * 1.4 + front * 0.6, o + Vector3.UP * 0.7)
		await _shoot("%s%s_top" % [tag, key], o + Vector3.UP * 30.0, o, 9.0)
		await _shoot("%s%s_map" % [tag, key], o + Vector3.UP * 120.0, o, 90.0)
	# 玄関前の広場の南の縁の段（ロッジの座標）: 前の道しるべの立っていた所と、東の角
	var lodge: Node3D = main.get_node_or_null("Lodge")
	if lodge:
		for v in [["plaza_edge", Vector3(-10.4, 0.2, 24.4), Vector3(-6.0, 1.6, 29.5)],
				["plaza_corner_east", Vector3(-8.1, 0.1, 24.4), Vector3(-4.6, 1.3, 27.6)],
				["plaza_corner_west", Vector3(-21.9, 0.1, 24.4), Vector3(-25.4, 1.3, 27.6)]]:
			var at: Vector3 = lodge.to_global(v[1])
			_overlay(at, 2.6)
			await _shoot("%s%s" % [args.get("tag", ""), v[0]], lodge.to_global(v[2]), at)
	quit()
