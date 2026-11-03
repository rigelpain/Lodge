extends SceneTree
## 人形の腕の縫い目（肩口・手首の十字縫いの輪、腕の継ぎ当て）を、いくつかの形で腕に寄って撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/arm_seam_shots.gd -- [--kind=golem] [--limb=arm|leg] [--out=/path/to.png]
## 形: 立つ・指さす（腕を上げる）・ハイタッチ（手のひらを高く）・座る・押す。1 つの形を、腕の外と前から 2 枚撮り、
## 形を縦、向きを横に並べた 1 枚にする。右腕を撮る（指さしとハイタッチも右手）。--limb=leg で右脚（武者の脛当ての縫い目など）

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

const POSES := ["stand", "point", "high", "sit", "push"]
const SEAT_H := 0.45
const CELL := Vector2i(420, 420)
## 押す形のソリの代わり: 縁の大きさ（HALF）と種類だけ持つ
const SLED_SRC := """extends Node3D
const HALF := Vector2(0.45, 0.9)
var kind := "wood"
"""

var args := {}
var t := 0.0
var cam: Camera3D
var dolls: Array = []
var _sheet: Image
var _step := 0
var _wait := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.8, 0.84, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.8)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	var sled_script := GDScript.new()
	sled_script.source_code = SLED_SRC
	sled_script.reload()
	for k in POSES.size():
		var pose: String = POSES[k]
		var x := k * 4.0   # 斜めに離して並べ、寄りの絵に隣が映らない
		var host := Node3D.new()
		host.position = Vector3(x, 0, -x)
		world.add_child(host)
		var d := Doll.new()
		d.kind = args.get("kind", "golem")
		d.facing = Vector3(0, 0, 1)   # こちら（+Z）を向く
		d.gaze = host.position + Vector3(0, 1.0, 3.0)
		match pose:
			"point":
				d.point = host.position + Vector3(-2.2, 2.4, 1.8)   # 右手で、右の高い所を指す
				d.point_sides = [1]
			"high":
				d.hand_shapes = ["high", ""]
			"sit":
				var stool := CSGBox3D.new()
				stool.size = Vector3(0.5, SEAT_H, 0.5)
				stool.position = Vector3(x, SEAT_H * 0.5, -x)
				world.add_child(stool)
				host.position.y = SEAT_H
				d.act = Doll.Act.SIT
				d.sit_stage = 2
				d.seat_drop = SEAT_H
			"push":
				var sled := Node3D.new()
				sled.set_script(sled_script)
				sled.position = host.position + Vector3(0, 0, 1.2)
				sled.rotation.y = PI   # ソリの後ろ（+Z の縁）がこちらの人形を向く
				world.add_child(sled)
				d.act = Doll.Act.PUSH
				d.sled = sled
				d.grip = Vector3(0, 0, 1.3)
		host.add_child(d)
		dolls.append(d)


func _process(dt: float) -> bool:
	t += dt
	for d in dolls:
		d.set("_next_breath", 100000)   # 白い息で腕が隠れないように
	if t < 1.5:
		return false
	if _sheet == null:
		_sheet = Image.create(CELL.x * 2, CELL.y * dolls.size(), false, Image.FORMAT_RGBA8)
		_aim_cam()
		return false
	_wait += 1
	if _wait < 3:   # 据えたカメラの絵が出るまで待つ
		return false
	_wait = 0
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var sz := img.get_size()
	var sq := mini(sz.x, sz.y)
	img = img.get_region(Rect2i((sz.x - sq) / 2, (sz.y - sq) / 2, sq, sq))
	img.resize(CELL.x, CELL.y)
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((_step % 2) * CELL.x, (_step / 2) * CELL.y))
	_step += 1
	if _step >= dolls.size() * 2:
		var path: String = args.get("out", "/tmp/arm_seam.png")
		_sheet.save_png(path)
		print("撮った: ", path)
		quit()
		return true
	_aim_cam()
	return false


## 右腕の肩・ひじ・手首（脚なら腿・すね・足）の真ん中を、外（1 枚目）と前（2 枚目）から
func _aim_cam() -> void:
	var d = dolls[_step / 2]
	var sk: Skeleton3D = d.skel
	var pts := []
	for b in (["thigh.R", "shin.R", "foot.R"] if args.get("limb", "arm") == "leg" else ["upper_arm.R", "forearm.R", "hand.R"]):
		pts.append(sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin)
	var at: Vector3 = (pts[0] + pts[1] + pts[2]) / 3.0
	var chest: Vector3 = d.chest_point()
	var out: Vector3 = at - chest
	out.y = 0
	out = out.normalized() if out.length() > 0.01 else Vector3.LEFT
	var fwd := Vector3(0, 0, 1)
	var v := (out * 0.85 + fwd * 0.35 + Vector3.UP * 0.15) if _step % 2 == 0 else (fwd * 0.9 + out * 0.35 + Vector3.UP * 0.1)
	var span: float = maxf((pts[0] - pts[2]).length(), 0.3)
	cam.look_at_from_position(at + v.normalized() * (0.35 + span * 2.2), at)
