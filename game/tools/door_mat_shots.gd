extends SceneTree
## 出入り口のマット（lodge/dims.py の DOORMATS）を、各出入り口の内と外から人の目の高さで撮り、1 枚に並べる（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/door_mat_shots.gd -- --bots=0 --lodge-bots=0 --no-sound --no-pip --dir=/path/shots
## 1. 開き戸の板の下端と、その戸の前後のマットの上の面の高さを比べる（板がマットの上を通るか）
## 2. 各出入り口の内と外を撮る（<dir>/<名前>.png）。左が中、右が外の 1 枚 <dir>/door_mats_sheet.png
## 3. --open を付けると、戸の近くに立って開いた戸とマットも撮る（<dir>/open_<名前>.png）
## 場所はロッジの座標（dims の x, y, 高さ）

const FL1 := 0.45
const FL2 := 6.1
const CELL := Vector2i(640, 360)

# [名前, 札, 立つ所 (x, y), 立つ高さ（null なら床へ落とす）, 見る所 (x, y, 高さ)]。行ごとに [中, 外]
const ROWS := [
	[["auto_in", "正面の自動ドア・中（食堂）", Vector2(-13.39, -8.6), FL1, Vector3(-13.39, -12.4, FL1 + 0.5)],
	 ["auto_out", "正面の自動ドア・外（風除室のマット）", Vector2(-13.39, -16.9), FL1, Vector3(-13.39, -12.8, FL1 + 0.6)]],
	[["arch_in", "風除室のアーチ・中（風除室のマット）", Vector2(-13.39, -13.3), FL1, Vector3(-13.39, -17.6, FL1 + 0.6)],
	 ["arch_out", "風除室のアーチ・外（玄関前の広場）", Vector2(-13.39, -22.4), FL1, Vector3(-13.39, -18.2, FL1 + 0.6)]],
	[["back_in", "勝手口・中（厨房）", Vector2(11.9, 8.4), FL1, Vector3(11.9, 12.2, FL1 + 0.5)],
	 ["back_out", "勝手口・外（北の雪）", Vector2(11.9, 17.2), null, Vector3(11.9, 13.2, 0.5)]],
	[["west_in", "西の戸・中（食堂）", Vector2(-17.6, 11.45), FL1, Vector3(-21.5, 11.45, FL1 + 0.5)],
	 ["west_out", "西の戸・外（下屋の雪）", Vector2(-26.3, 11.45), null, Vector3(-22.2, 11.45, 0.5)]],
	[["terrace_in", "2 階のテラスへの戸・中（通り道）", Vector2(-10.7, -0.4), FL2, Vector3(-11.4, 3.3, FL2 + 0.4)],
	 ["terrace_out", "2 階のテラスへの戸・外（テラス）", Vector2(-15.2, 3.27), FL2 + 0.03, Vector3(-12.2, 3.27, FL2 + 0.5)]],
]
# 開いた戸を撮る所（--open）: [名前, 立つ所, 立つ高さ, 見る所]
const OPENS := [
	["back_in", Vector2(11.9, 10.6), FL1, Vector3(11.9, 12.4, FL1)],
	["west_in", Vector2(-19.6, 11.45), FL1, Vector3(-21.6, 11.45, FL1)],
	["terrace_out", Vector2(-13.8, 3.27), FL2 + 0.03, Vector3(-12.0, 3.27, FL2)],
]

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D
var label: Label
var bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/door_mats")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _w(q: Vector2, h: Variant) -> Vector3:
	if h != null:
		return lodge.to_global(Vector3(q.x, float(h) + 0.02, -q.y))
	var g := lodge.to_global(Vector3(q.x, 0, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 3.0, g + Vector3.DOWN * 30.0)
	r.exclude = [p.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else g


func _aim(at: Vector3, to: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
	var eye := at + Vector3.UP * 1.55
	p.set("_pitch", atan2(to.y - eye.y, Vector2(to.x - eye.x, to.z - eye.z).length()))


func _shoot(name: String, text: String, stand: Vector2, h: Variant, look: Vector3) -> Image:
	var at := _w(stand, h) + Vector3.UP * 0.05
	var to := lodge.to_global(Vector3(look.x, look.z, -look.y))
	label.text = text
	_aim(at, to)
	await create_timer(0.6).timeout
	_aim(at, to)   # 着地でずれた分を戻す
	await create_timer(1.6).timeout   # 戸が閉まりきるまで
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_dir().path_join(name + ".png"))
	print("撮った: ", name)
	return img


## 開き戸の板（Swing_* の下の物）の下端と、戸のまわり 2.5 m のマットの上の面（目印の高さ + 厚み 1.2 cm + 縁 0.2 cm）
func _clearance() -> void:
	var mats := []
	for n in lodge.find_children("doormat_*", "Node3D", true, false):
		if not n is MeshInstance3D:
			mats.append(lodge.to_local((n as Node3D).global_position))
	print("1. 開き戸の板の下端とマットの上の面")
	for pv in lodge.find_children("Swing_*", "Node3D", true, false):
		var low := INF
		for mi in (pv as Node).find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = (lodge.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
			low = minf(low, bb.position.y)
		var hinge := lodge.to_local((pv as Node3D).global_position)
		var top := -INF
		for m in mats:
			if Vector2(m.x - hinge.x, m.z - hinge.z).length() < 2.5 and absf(m.y - low) < 0.5:
				top = maxf(top, m.y + 0.014)
		var gap := low - top
		var ok := top == -INF or gap > 0.005
		if not ok:
			bad += 1
		print("  %s %s: 板の下端 %.3f、マットの上 %s、すき間 %s" % ["○" if ok else "×", pv.name, low,
				"なし" if top == -INF else "%.3f" % top, "-" if top == -INF else "%.1f cm" % (gap * 100.0)])


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	p.set_third(false)
	lodge = main.get_node("Lodge")
	main.sled.reset_to(lodge.to_global(Vector3(10.0, 0.0, 40.0)) + Vector3.UP * 3.0)
	_clearance()
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	layer.add_child(label)
	print("2. 撮る")
	var sheet := Image.create(CELL.x * 2, CELL.y * ROWS.size(), false, Image.FORMAT_RGBA8)
	for r in ROWS.size():
		for c in 2:
			var v: Array = ROWS[r][c]
			var img := await _shoot(v[0], v[1], v[2], v[3], v[4])
			img.convert(Image.FORMAT_RGBA8)
			img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, r * CELL.y))
	sheet.save_png(_dir().path_join("door_mats_sheet.png"))
	if args.has("open"):
		for v in OPENS:
			await _shoot("open_" + v[0], "開いた戸: " + String(v[0]), v[1], v[2], v[3])
	print("合わない所: %d" % bad)
	quit(1 if bad > 0 else 0)
