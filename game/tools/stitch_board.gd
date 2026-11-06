extends SceneTree
## 滑りあとの柄の見本を、本物の雪の上に引いて撮る（案を代表に見せる用）。
##   Godot --path game --resolution 960x540 -s res://tools/stitch_board.gd -- --bots=0 --no-sound --out=/path/board [--color=2F5DA8] [--only=cross,fly]
## 柄ごとにソリの縫う処理（sled.gd の _trail_step）へ、ゆるく曲がる道すじを 8 m 渡して縫わせ、
## 立った人の目の高さから <out>_<番号>_<柄>.png を書く。絵の左上に番号と名前を入れる

const Stitches := preload("res://stitches.gd")
const LEN := 8.0

var args := {}
var main: Node3D
var cam: Camera3D
var label: Label
var names: Array = []
var n := -1
var wait := 0
var t := 0.0
var row := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	names = Stitches.LIST.keys()
	if args.has("only"):
		names = Array(String(args.only).split(","))
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 55
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	var cl := CanvasLayer.new()
	cl.layer = 50
	root.add_child(cl)
	label = Label.new()
	label.position = Vector2(14, 8)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
	label.add_theme_color_override("font_outline_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 10)
	cl.add_child(label)


## 柄 name を、丘の東の斜面の 1 本の列に縫う
func _lay(name: String, index: int) -> Dictionary:
	var Sled := preload("res://sled.gd")
	var s: RigidBody3D = Sled.new()
	s.kind = "mid"
	s.stitch_override = name
	if args.has("color"):
		s.main_color = Color.from_string(args.color, Color(0, 0, 0, 0))
	s.snow_lift = main.snow_lift
	s.snow_plane = main.snow_plane
	s.freeze = true
	var base := Vector3(14.0, 0, -66.0 + index * 5.0)
	s.position = base + Vector3.UP * 500.0   # 本体は見えない所へ。跡は top_level なので雪の上
	main.add_child(s)
	s._body.visible = false
	s.rope.visible = false
	s.set_physics_process(false)   # 時計を止める（撮るあいだに消えない）
	for k in 2:
		var sx: float = -s.RUNNER_X if k == 0 else s.RUNNER_X
		var d := 0.0
		while d < LEN:
			var bend := sin(d * 0.5) * 0.35
			var at := base + Vector3(d, 0, sx + bend)
			at.y = main.height(at.x, at.z)
			var dir := Vector3(1.0, 0.0, cos(d * 0.5) * 0.175).normalized()
			s._trail_step(k, at, dir)
			d += s.TRAIL_STEP
	return {"sled": s, "base": base}


## 案の絵には手元の HUD を入れない
func _hide_hud(n0: Node) -> void:
	for c in n0.get_children():
		if c is CanvasLayer and c != label.get_parent():
			c.visible = false
		_hide_hud(c)


func _physics_process(dt: float) -> bool:
	t += dt
	if t < 1.5 or wait > 0:
		return false
	n += 1
	if n >= names.size():
		quit()
		return true
	var name: String = names[n]
	row = _lay(name, n)
	var b: Vector3 = row.base
	# 右の滑り木の跡を、立った人の目の高さの少し斜め上から見る
	var track := b + Vector3(1.6, 0, 0.6)
	var eye := b + Vector3(-0.5, 0, 0.6)
	eye.y = main.height(eye.x, eye.z) + 1.55
	track.y = main.height(track.x, track.z)
	cam.global_position = eye
	cam.look_at(track, Vector3.UP)
	cam.current = true
	label.text = "%d  %s" % [n + 1, Stitches.ja(name)]
	wait = 8
	return false


func _process(_dt: float) -> bool:
	_hide_hud(root)
	if wait > 0:
		wait -= 1
		if wait == 0:
			root.get_texture().get_image().save_png("%s_%02d_%s.png" % [args.get("out", "/tmp/board"), n + 1, names[n]])
			(row.sled as Node).queue_free()
	return false
