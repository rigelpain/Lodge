extends SceneTree
## 指さしの見え方を、見上げ・まっすぐ・見下ろし・横向き・三人称で撮る（人さし指が画面の奥の消失点へ向いて見えるかの確かめ用）。
##   Godot --path game --resolution 960x540 -s res://tools/point_view_shots.gd -- --out=/path/to/dir [--hand=R|L|both]
## dir に up.png・level.png・down.png・side.png・tp.png を残す。画面のまんなかに小さな点を打つ（消失点の目じるし）

const Palm := preload("res://palm.gd")

const SHOTS := [["up", 0.45, 0.0, false], ["level", 0.0, 0.0, false], ["down", -0.5, 0.0, false], ["side", -0.15, 1.2, false], ["tp", -0.15, 0.0, true]]

var args := {}
var main: Node3D
var t := 0.0
var _i := -1
var _shot_t := 0.0
var _dot: ColorRect


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	if p == null or main.sled == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if _i < 0 and t > 0.6:
		var sled: Node3D = main.sled
		var back: Vector3 = sled.global_basis.z
		p.global_position = sled.global_position + back * 4.0 + Vector3.UP * 0.3
		p.rotation.y = atan2(back.x, back.z) + 0.6
		if args.get("hand", "R") != "R":
			p.hand = args["hand"]
		p.toggle_point()
		var layer := CanvasLayer.new()
		layer.layer = 100
		_dot = ColorRect.new()
		_dot.color = Color(1, 0, 0.6)
		_dot.size = Vector2(6, 6)
		_dot.position = Vector2(root.size) / 2.0 - Vector2(3, 3)
		layer.add_child(_dot)
		root.add_child(layer)
		_next(p)
	elif _i >= 0 and t - _shot_t > 1.2:
		var dir: String = args.get("out", "/tmp")
		root.get_texture().get_image().save_png(dir.path_join(SHOTS[_i][0] + ".png"))
		print("保存: ", SHOTS[_i][0], "  指す先と見ている向きのずれ %.1f°" % rad_to_deg((p.point_at - p.cam.global_position).angle_to(-p.cam.global_basis.z)), _finger(p))
		if _i + 1 >= SHOTS.size():
			quit()
		else:
			_next(p)
	return false


func _next(p) -> void:
	_i += 1
	_shot_t = t
	var s: Array = SHOTS[_i]
	p._pitch = s[1]
	p.rotate_y(s[2])
	p.set_third(s[3])
	_dot.visible = not s[3]


## 一人称の画面で、人さし指の線（付け根→先）と、付け根から画面のまんなかへの線の角度
func _finger(p) -> String:
	var out := ""
	if SHOTS[_i][3]:
		# 三人称: 人形の右腕（肩→手首）と、肩から指す所への向きの角度
		var d = p.doll
		var sk: Skeleton3D = d.skel
		var sh: Vector3 = sk.global_transform * d._head_of(d._id("upper_arm.R"))
		var hand: Vector3 = sk.global_transform * sk.get_bone_global_pose(d._id("hand.R")).origin
		return "  人形の腕と、肩から指す所への向きのずれ %.1f°" % rad_to_deg((hand - sh).angle_to(p.point_at - sh))
	for side in [1, -1]:
		var node: Node3D = p._shapes_fp["point"][side]
		if not node.visible:
			continue
		var x: float = Palm.POINT_ROOT.x * side
		var a: Vector2 = p.cam.unproject_position(node.global_transform * Vector3(x, Palm.POINT_ROOT.y, 0))
		var b: Vector2 = p.cam.unproject_position(node.global_transform * Vector3(x, 0.105, 0))
		var c := Vector2(root.size) / 2.0
		out += "  %s手: 指の長さ %.0f px、まんなかとのずれ %.1f°" % ["右" if side > 0 else "左", (b - a).length(), rad_to_deg(absf((b - a).angle_to(c - a)))]
	return out
