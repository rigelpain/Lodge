extends SceneTree
## ロッジの 1 階の南西（ミシンのまわり）を撮る（確かめ用。山男の置き場所を決めるため）。
##   Godot --path game --resolution 1280x720 -s res://tools/lodge_corner_shots.gd -- --dir=/path/shots [--marks=x,y,deg,色;...] [--top=x,y,幅]
## 撮るもの:
##   top.png       真上から（カメラを 1 階の天井の下に置く。--top-h で床からの高さ）。--marks の印（ロッジの座標 (x, y) に円と向きの棒）も描く
##   door.png      玄関（風除室の内の自動ドア）を入った人の目線で、ミシンの方
##   machine.png   ミシンの前（客の側）から、奥（北）の方
## ログに、ミシン・おじいさん・番台・ランタン掛け・灯りの所（ロッジの座標）を出す

var args := {}
var main: Node3D
var lodge: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/lodge_corner")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	if main and main.craft_ui and main.craft_ui.gear_open:
		main.craft_ui.close_gear()
	return false


## ロッジの座標 (x, y)（lodge/dims.py。y が北）を世界へ
func _w(x: float, y: float, h := 0.0) -> Vector3:
	return lodge.to_global(Vector3(x, main.LODGE_FLOOR + h, -y))


## 世界をロッジの座標 (x, y) へ
func _l(p: Vector3) -> Vector2:
	var q := lodge.to_local(p)
	return Vector2(q.x, -q.z)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _marks() -> void:
	if not args.has("marks"):
		return
	for m in String(args["marks"]).split(";"):
		var f := m.split(",")
		var at := _w(float(f[0]), float(f[1]), 0.02)
		var col := Color(f[3]) if f.size() > 3 else Color.RED
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.45
		cm.bottom_radius = 0.45
		cm.height = 0.04
		disc.mesh = cm
		disc.material_override = mat
		main.add_child(disc)
		disc.global_position = at
		var deg := float(f[2])   # 正面の向き（0 = 南、90 = 東。SLOTS と同じ）
		var d := Vector2(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.05, 1.0)
		bar.mesh = bm
		bar.material_override = mat
		main.add_child(bar)
		bar.global_position = _w(float(f[0]) + d.x * 0.7, float(f[1]) + d.y * 0.7, 0.03)
		bar.look_at(_w(float(f[0]) + d.x * 2.0, float(f[1]) + d.y * 2.0, 0.03))


func _run() -> void:
	await _wait(2.0)
	lodge = main.get_node("Lodge")
	main.player.doll.visible = false
	for n in [["ミシン", main.sewing.machine if main.sewing else null], ["おじいさん", main.shopkeeper], ["ランタン掛け", main.lantern_rack],
			["番台", lodge.get_node_or_null("Bandai_counter_patch")], ["山男", main.get("mountain_man")]]:
		if n[1]:
			print("%s %s" % [n[0], _l((n[1] as Node3D).global_position)])
	for l in main.find_children("*", "Light3D", true, false):
		var p := _l((l as Node3D).global_position)
		if p.x < -8.0 and p.y < 8.0 and p.y > -14.0 and (l as Node3D).global_position.y < lodge.global_position.y + 6.0:
			print("灯り %s %s %s" % [l.name, p, (l as Node3D).get_parent().name])
	_marks()
	# 真上から: カメラを 1 階の天井の下に置く（天井と 2 階はカメラの後ろになって写らない）
	var hidden: Array = []
	var top: PackedFloat64Array = String(args.get("top", "-15,-3,16")).split_floats(",")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = top[2]
	main.add_child(cam)
	var c := _w(top[0], top[1])
	cam.near = 0.05
	cam.far = 10.0
	cam.look_at_from_position(c + Vector3.UP * float(args.get("top-h", "2.55")), c, -lodge.global_basis.z)   # 絵の上が北
	cam.make_current()
	main.hud.visible = false if main.hud is CanvasItem else main.hud.visible
	for n in main.get_children():
		if n is CanvasLayer:
			n.visible = false
	await _wait(0.8)
	await _shot("top")
	for gi in hidden:
		gi.visible = true
	# 玄関を入った人の目線（風除室の内の自動ドアの少し内、目の高さ）
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.far = 400.0   # 真上の絵では天井の下に置くため短くしていた
	cam.fov = 65
	var door: PackedFloat64Array = String(args.get("door", "-13.4,-11.4")).split_floats(",")
	var look: PackedFloat64Array = String(args.get("door-look", "-18.5,0.5")).split_floats(",")
	cam.look_at_from_position(_w(door[0], door[1], 1.6), _w(look[0], look[1], 1.0))
	await _wait(0.6)
	await _shot("door")
	var mm = main.get("mountain_man")
	if mm:   # 玄関から山男が見えるか（目から胸へ光線を飛ばし、先に当たる物を出す）
		var eye := _w(door[0], door[1], 1.6)
		var q := PhysicsRayQueryParameters3D.create(eye, (mm as Node3D).global_position + Vector3.UP * 1.2)
		var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
		print("玄関から山男へ: ", "見える" if hit.is_empty() or (hit.collider as Node).is_ancestor_of(mm) or mm.is_ancestor_of(hit.collider) else "%s に当たる（ロッジの座標 %s）" % [hit.collider.name, _l(hit.position)])
	var mfrom: PackedFloat64Array = String(args.get("from", "-14.5,-4.5")).split_floats(",")
	var mlook: PackedFloat64Array = String(args.get("from-look", "-19.5,2.0")).split_floats(",")
	cam.look_at_from_position(_w(mfrom[0], mfrom[1], 1.6), _w(mlook[0], mlook[1], 1.0))
	await _wait(0.6)
	await _shot("machine")
	quit(0)
