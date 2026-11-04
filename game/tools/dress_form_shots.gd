extends SceneTree
## 1 階の人台と紙細工屋さんのテントの並びを確かめて撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/dress_form_shots.gd -- --spawn=wardrobe --bots=0 --no-sound --no-pip --dir=/path/shots
## 数字: 視線の高さで F の行き先が分かれるか（人形の高さ → 着替える、見下ろす → 染める）。勝手口から南と、人台のまわりの通り道に当たりがないか。
## 絵: hint_wardrobe・hint_dye（案内）、door（入口のマットから）、hall（食堂から）、near（人台の前。染めたあとの桶）、back（山師の前から南）

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/dress-form"))
	_run.call_deferred()


func _save(name: String) -> void:
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png(String(args.get("dir", "/tmp/dress-form")).path_join(name + ".png"))
	print("撮った ", name)


## ロッジの座標 (x, y) と高さ h を、世界の座標に
func _at(x: float, h: float, y: float) -> Vector3:
	return main.wardrobe.get_parent().to_global(Vector3(x, h, -y))


## ロッジの座標 (x, y) の線を、人の太さ（半径 0.35 m、床から 0.5〜1.7 m）で通れるか
func _clear(a: Vector2, b: Vector2) -> bool:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.exclude = [main.player.get_rid()]
	var n := int(a.distance_to(b) / 0.2) + 1
	for i in n + 1:
		var c := a.lerp(b, float(i) / n)
		q.transform = Transform3D(Basis(), _at(c.x, 0.45 + 1.1, c.y))
		if not space.intersect_shape(q, 1).is_empty():
			print("  当たる所 (%.1f, %.1f)" % [c.x, c.y])
			return false
	return true


func _run() -> void:
	await create_timer(6.0).timeout
	var p: CharacterBody3D = main.player
	# --no-shop: ソリ屋が外へ移る前に、その跡に置いた形で確かめる（ミシンと売り子をのける）
	for n in [] if not args.has("no-shop") else [main.sewing.machine if main.sewing else null, main.shopkeeper, main.find_child("counter_patch", true, false), main.find_child("Curtain", true, false)]:
		if n:
			(n as Node).queue_free()
	await create_timer(0.3).timeout
	var dc := root.get_node_or_null("DayCycle")
	if dc:
		dc.hour = 13.0
		dc.day_seconds = 1.0e9
	p._pitch = 0.0
	await create_timer(0.3).timeout
	print("人台の座標で立つ所 ", main.wardrobe.to_local(p.global_position), " 向きの合い ", (-p.global_basis.z).dot((main.wardrobe.global_position - p.global_position).normalized()))
	print("人形の高さを見る: 着替える ", p.wardrobe_near(), " 染める ", p.dye_near())
	await _save("hint_wardrobe")
	p._pitch = -0.6
	await create_timer(0.3).timeout
	print("見下ろす: 着替える ", p.wardrobe_near(), " 染める ", p.dye_near())
	await _save("hint_dye")
	p.global_position = main.wardrobe.to_global(Vector3(0, 0.1, -2.6))
	await create_timer(0.3).timeout
	p._pitch = 0.0
	p.look_at(main.wardrobe.global_position * Vector3(1, 0, 1) + Vector3.UP * p.global_position.y)
	await create_timer(0.2).timeout
	print("長い布の側で人形の高さを見る: 着替える ", p.wardrobe_near())
	print("真ん中を通す（当たるはず）: ", _clear(Vector2(-19.0, -8.6), Vector2(-19.0, -10.6)))
	print("入口のマットから北へ (-13.4, -11) → (-13.4, 3): ", _clear(Vector2(-13.4, -11.0), Vector2(-13.4, 3.0)))
	print("人台の前 南北 (-16.4, -11.8) → (-16.4, -3): ", _clear(Vector2(-16.4, -11.8), Vector2(-16.4, -3.0)))
	print("テントと人台のあいだ 東西 (-16.4, -7.2) → (-20.6, -7.2): ", _clear(Vector2(-16.4, -7.2), Vector2(-20.6, -7.2)))
	print("テントと山師のあいだ 東西 (-16.4, -2.9) → (-20.6, -2.9): ", _clear(Vector2(-16.4, -2.9), Vector2(-20.6, -2.9)))
	main.dye_vat._on_craft({"kind": "dye", "colors": ["c9603c"]})   # 染めると、桶の液と縁の布の色が変わる
	await create_timer(1.6).timeout
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)
	cam.near = 0.05
	cam.fov = 60.0
	cam.make_current()
	for v in [["door", _at(-13.4, 2.2, -10.5), _at(-19.0, 1.9, -7.0)], ["hall", _at(-9.0, 2.4, -3.0), _at(-19.0, 2.0, -7.0)],
			["near", _at(-15.8, 1.8, -9.2), _at(-19.0, 2.5, -9.6)], ["back", _at(-20.8, 2.2, -1.5), _at(-19.0, 1.6, -9.0)]]:
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		await _save(v[0])
	quit()
