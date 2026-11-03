extends SceneTree
## 大きな山のジャンプ台で、ソリが飛んで着地するまでを横から撮る（確かめ用。コマの PNG を書き出す）。
##   Godot --fixed-fps 60 --path game --resolution 960x600 -s res://tools/kicker_film.gd -- --no-player --bots=0 --no-sound --dir=/path/frames
##     [--kick=1]     ジャンプ台の番号（0 から）
##     [--speed=10]   踏み切りの坂の 14 m 手前で入れる速さ (m/s)
##     [--sled=large] ソリの大きさ（main.gd が読む）
##     [--every=3]    何コマおきに撮るか
## コマは f_000.png から。ソリには見えない人を 1 人乗せる

const Mountain := preload("res://mountain.gd")
const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sled: RigidBody3D
var t := 0.0
var _go := -1.0
var _n := 0
var _frame := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/kicker_film"))


func _process(_dt: float) -> bool:
	if main.hud:
		main.hud.visible = false
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	return false


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null or t < 0.6:
		return false
	var k := Mountain.kicker(int(args.get("kick", "1")))
	var lip: Vector2 = k.lip
	var f: Vector2 = k.f
	if _go < 0.0:
		sled = main.sled
		var at := lip - f * (Mountain.KICK_L + 14.0)
		var y: float = main.height(at.x, at.y)
		var d := Vector3(f.x, main.height(at.x + f.x, at.y + f.y) - y, f.y).normalized()
		sled.reset_to(Vector3(at.x, y + 0.3, at.y))
		sled.global_transform = Transform3D(Basis.looking_at(Vector3(f.x, 0, f.y), Vector3.UP), sled.global_position)
		sled.parked = false
		sled.linear_velocity = d * float(args.get("speed", "10"))
		var dummy := GDScript.new()
		dummy.source_code = DUMMY_SRC
		dummy.reload()
		var r := Node3D.new()
		r.set_script(dummy)
		r.sled = sled
		main.add_child(r)
		sled.mount(r)
		# 横から: 縁の 12 m 先の横 16 m、少し上から
		var side := Vector2(-f.y, f.x)
		var mid := lip + f * 5.0
		var cp := mid + side * 17.0
		var cam := Camera3D.new()
		main.add_child(cam)
		cam.fov = 55.0
		cam.position = Vector3(cp.x, main.height(cp.x, cp.y) + 3.0, cp.y)
		cam.look_at(Vector3(mid.x, main.height(mid.x, mid.y) + 1.0, mid.y))
		cam.make_current()
		_go = t
		return false
	_frame += 1
	if _frame % int(args.get("every", "3")) == 0:
		var path: String = args.get("dir", "/tmp/kicker_film").path_join("f_%03d.png" % _n)
		root.get_texture().get_image().save_png(path)
		_n += 1
	var along := (Vector2(sled.global_position.x, sled.global_position.z) - lip).dot(f)
	if t - _go > 6.0 or along > 26.0:
		print("撮った %d コマ" % _n)
		quit()
		return true
	return false
