extends SceneTree
## 山師（mountain_man.gd）のそばにミニオンを見せる置き方の案を撮る（確かめ用。代表に選んでもらうため）。
##   Godot --path game --resolution 1280x720 -s res://tools/minion_layout_shots.gd -- --layout=A --dir=/path/shots
## 案（山師の座標。前は -Z、右手は +X＝南、左手の -X＝北に道具の棚）:
##   A  足もとで遊ぶ: 山師の前と足もとに編んだ敷物を敷き、ミニオンが座ったり寝たりしている
##   B  寝床の台: 山師の右手（南）に低い木の台。座布団の寝床でミニオンが寝て、前の床に紙コップの餌の器
##   C  柵の囲い: 道具の棚の先（北）に、毛糸を巻いた木の柵で囲った寝床。敷物、薪かごの巣、餌の器
## 撮るもの: <案>_eye.png（客の側の目の高さ）、<案>_high.png（客の側の斜め上から）

const Pals := preload("res://pals.gd")
const Props := preload("res://props.gd")
const Look := preload("res://look.gd")

var args := {}
var main: Node3D
var mm: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/minion_layout")


func _process(_dt: float) -> bool:
	if main and main.craft_ui and main.craft_ui.gear_open:
		main.craft_ui.close_gear()
	return false


## ミニオンを 1 匹置く（pose は sit / sleep / walk）
func _pet(key: String, at: Vector3, yaw: float, pose := "sit", sc := 1.0) -> void:
	var n: Node3D = Pals.scene(key).instantiate()
	Pals.paint(n)
	for c in n.get_children():
		(c as Node3D).visible = Pals.part_name(c) == pose
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3.ONE * sc
	mm.add_child(n)


func _prop(path: String, at: Vector3, yaw := 0.0, sc := 0.5) -> Node3D:
	var n := Props.make(path)
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3.ONE * sc
	mm.add_child(n)
	return n


func _box(size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	mm.add_child(mi)


func _layout(k: String) -> void:
	var wood := Look.wood(Color(0.50, 0.33, 0.20))
	var dark := Look.wood(Color(0.36, 0.24, 0.15))
	match k:
		"A":
			_prop("res://props/room/rug_braided_warm.glb", Vector3(0.35, 0.01, -0.65), 0.3)
			_pet("kit", Vector3(0.7, 0, -0.55), PI + 0.5)
			_pet("frog", Vector3(-0.45, 0, -0.75), PI - 0.3)
			_pet("yarn", Vector3(0.95, 0, -1.0), PI + 0.8)
			_pet("rabbit", Vector3(0.25, 0, -1.05), PI)
			_pet("chiyo_fox", Vector3(0.75, 0, 0.35), PI + 1.2, "sleep")
			_pet("peacock", Vector3(-0.55, 0, 0.45), PI - 0.6)
		"B":
			var c := Vector3(1.45, 0, 0.15)
			_box(Vector3(0.55, 0.05, 1.5), c + Vector3(0, 0.36, 0), wood)
			for sz in [-1.0, 1.0]:
				for sx in [-1.0, 1.0]:
					_box(Vector3(0.05, 0.34, 0.05), c + Vector3(sx * 0.22, 0.17, sz * 0.68), dark)
			for i in 3:
				var zp := c + Vector3(0, 0.39, -0.48 + i * 0.48)
				_prop("res://props/room/zabuton_%s.glb" % ["red", "moss", "mustard"][i], zp, 0.0, 0.42)
			_pet("kit", c + Vector3(0, 0.45, -0.48), PI + 0.4, "sleep")
			_pet("rabbit", c + Vector3(0, 0.45, 0.0), PI, "sit")
			_pet("frog", c + Vector3(0, 0.45, 0.48), PI - 0.4, "sleep")
			for i in 3:
				_prop("res://props/cup.glb", c + Vector3(-0.42, 0.0, -0.45 + i * 0.45), 0.0, 0.6)
			_pet("yarn", c + Vector3(-0.5, 0, 0.9), PI + 0.6)
		"C":
			var c := Vector3(-2.75, 0, 0.0)
			var w := 1.6
			var d := 1.5
			_prop("res://props/room/rug_braided_cool.glb", c + Vector3(0, 0.01, 0), 0.0, 0.5)
			var yarn := Look.felt(Color(0.80, 0.24, 0.20), 4.0)
			for i in 6:   # 柵の柱（角と、前後のまんなか）
				var p: Vector3 = [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d), Vector3(0, 0, -d), Vector3(0, 0, d)][i] * 0.5
				_box(Vector3(0.06, 0.55, 0.06), c + p + Vector3(0, 0.275, 0), dark)
				_box(Vector3(0.075, 0.05, 0.075), c + p + Vector3(0, 0.42, 0), yarn)
			for y in [0.22, 0.46]:   # 横木 2 段（前は入口をあける）
				_box(Vector3(w, 0.035, 0.035), c + Vector3(0, y, d * 0.5), wood)
				_box(Vector3(0.035, 0.035, d), c + Vector3(-w * 0.5, y, 0), wood)
				_box(Vector3(0.035, 0.035, d), c + Vector3(w * 0.5, y, 0), wood)
				_box(Vector3(w * 0.32, 0.035, 0.035), c + Vector3(-w * 0.34, y, -d * 0.5), wood)
				_box(Vector3(w * 0.32, 0.035, 0.035), c + Vector3(w * 0.34, y, -d * 0.5), wood)
			_prop("res://props/hearth/log_basket.glb", c + Vector3(-0.35, 0, 0.35), 0.4, 0.5)
			_pet("kit", c + Vector3(-0.35, 0.18, 0.35), PI, "sleep")
			_pet("rabbit", c + Vector3(0.35, 0, -0.15), PI + 0.5)
			_pet("frog", c + Vector3(-0.3, 0, -0.35), PI - 0.2)
			_pet("yarn", c + Vector3(0.45, 0, 0.4), PI + 1.0)
			for i in 2:
				_prop("res://props/cup.glb", c + Vector3(0.05 + i * 0.25, 0, 0.1), 0.0, 0.6)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	print("保存: ", name)


func _run() -> void:
	await create_timer(2.0).timeout
	mm = main.mountain_man
	main.player.global_position = mm.to_global(Vector3(0, 0.1, -9.0))
	var k: String = args.get("layout", "A")
	_layout(k)
	for n in main.get_children():
		if n is CanvasLayer:
			n.visible = false
	var cam := Camera3D.new()
	cam.cull_mask &= ~(1 << 2)
	cam.fov = 55
	main.add_child(cam)
	var look := {"A": Vector3(0.1, 0.6, -0.4), "B": Vector3(0.7, 0.6, 0.0), "C": Vector3(-1.5, 0.6, 0.0)}[k] as Vector3
	cam.look_at_from_position(mm.to_global(look + Vector3(0.5, 0.7, -2.4)), mm.to_global(look))
	cam.make_current()
	await create_timer(1.0).timeout
	await _shot(k + "_eye")
	# 斜め上から（並びがわかるように）
	cam.look_at_from_position(mm.to_global(look + Vector3(0.2, 2.3, -2.0)), mm.to_global(look + Vector3(0, -0.3, 0)))
	await create_timer(0.6).timeout
	await _shot(k + "_high")
	quit(0)
