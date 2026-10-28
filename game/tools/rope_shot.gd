extends SceneTree
## ソリの引き紐を、4 つの場面で撮る（紐の見た目の確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/rope_shot.gd -- --bots=0 --no-sound --no-snow --out=/path/rope
## <out>_flat.png   平らな所に置いたソリ。紐は持たれずに垂れている
## <out>_close.png  同じ所を、右の手すりの結び先の近く（70 cm）から。結び目と撚りの筋の確かめ
## <out>_slope.png  坂の途中で、頂上へ向けたソリ（前が上がる）
## <out>_tilt.png   横に 20° 傾けたソリ
## <out>_pull.png   あなたが紐を持って、斜め前へ引いている（三人称の後ろ上から）
## <out>_pull_fp.png  同じ場面で、引いたあと立ち止まり、ソリの方を振り返った一人称の画面
## --only=flat などで 1 枚だけ撮る。

const SCENES := ["flat", "close", "slope", "tilt", "pull", "pull_fp"]

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var _i := 0
var _start := 0.0
var _set := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 45
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)   # 世界と人の体と飾り。一人称の手（層 3）は映さない
	root.add_child(cam)
	if args.has("only"):
		_i = SCENES.find(args["only"])


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


## ソリを at に、yaw（前 -z の向き）と roll（前を軸に右へ傾ける）で置いて止める
func _place(sled: RigidBody3D, at: Vector3, yaw: float, roll: float, pitch_to_ground := true) -> void:
	sled.reset_to(at)
	var b := Basis(Vector3.UP, yaw)
	if pitch_to_ground:
		# 地面の傾きに合わせる（前後 1.2 m の高さの差）
		var f: Vector3 = -b.z
		var h0: float = main.height(at.x - f.x * 1.2, at.z - f.z * 1.2)
		var h1: float = main.height(at.x + f.x * 1.2, at.z + f.z * 1.2)
		b = b.rotated(b.x, atan2(h1 - h0, 2.4))
	b = b.rotated(-b.z, roll)
	sled.global_transform = Transform3D(b, at)
	sled.freeze = true


func _process(dt: float) -> bool:
	t += dt
	var sled: RigidBody3D = main.sled
	var p = main.player
	if sled == null or p == null or t < 0.8:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if main._pip_layer:
		main._pip_layer.visible = false
	var scene: String = SCENES[_i]
	if not _set:
		_set = true
		_start = t
		sled.freeze = false
		p.let_go()
		_key(KEY_W, false)
		match scene:
			"flat", "close":
				var at := Vector3(0, 0, 46)
				at.y = main.height(at.x, at.z) + 0.05
				_place(sled, at, 0.3, 0.0)
				p.global_position = at + Vector3(8, 0, 8)
			"slope":
				# 丘の南の斜面で、頂上（-z）へ向ける
				var at := Vector3(0, 0, 16)
				at.y = main.height(at.x, at.z) + 0.05
				_place(sled, at, 0.0, 0.0)
				p.global_position = at + Vector3(8, 0, 8)
			"tilt":
				var at := Vector3(0, 0, 46)
				at.y = main.height(at.x, at.z) + 0.3
				_place(sled, at, 0.3, deg_to_rad(20))
				p.global_position = at + Vector3(8, 0, 8)
			"pull", "pull_fp":
				# 平らな所で、ソリの前 3 m・右へ 1.2 m に立ち、斜め前へ歩いて引く
				var at := Vector3(0, 0, 48)
				at.y = main.height(at.x, at.z) + 0.05
				_place(sled, at, 0.0, 0.0)
				sled.freeze = false
				var stand := at + Vector3(1.2, 0, -2.6)
				stand.y = main.height(stand.x, stand.z) + 0.2
				p.global_position = stand
				p.rotation.y = atan2(-0.45, 1.0)   # 右斜め前（-z と +x のあいだ）を向く
				p._pitch = 0.0
				p.grab_rope()
				_key(KEY_W, true)
	# カメラ
	var fwd: Vector3 = -sled.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var c: Vector3 = sled.global_position
	match scene:
		"pull":
			var mid: Vector3 = (c + p.global_position) * 0.5
			cam.global_position = mid - right * 4.2 - fwd * 1.5 + Vector3.UP * 2.6
			cam.look_at(mid + Vector3.UP * 0.2, Vector3.UP)
		"pull_fp":
			# 2 秒引いたら立ち止まり、ソリの方を振り返る。あなたのカメラで撮る（一人称の手が映る）
			if t - _start > 2.0:
				_key(KEY_W, false)
				var to: Vector3 = c - p.global_position
				p.rotation.y = atan2(-to.x, -to.z)
				p._pitch = -0.38
			p.cam.current = true
			cam.current = false
		"close":
			# 右の手すりの前の端（紐の結び先）を、前の斜め上から
			var mid: Vector3 = sled.to_global(Vector3(0.72, 0.42, -1.3))
			cam.global_position = mid + right * 0.35 + fwd * 0.6 + Vector3.UP * 0.25
			cam.look_at(mid, Vector3.UP)
		_:
			# 前の斜め上から、手すりと紐が見えるように
			var eye: Vector3 = c + fwd * 3.6 - right * 2.4 + Vector3.UP * 1.9
			eye.y = maxf(eye.y, main.height(eye.x, eye.z) + 1.6)   # 坂では上側の雪に埋まらないように
			cam.global_position = eye
			cam.look_at(c + fwd * 1.6 + Vector3.UP * 0.1, Vector3.UP)
	if scene != "pull_fp":
		cam.current = true
	var wait := 3.0 if scene.begins_with("pull") else 1.0
	if t - _start > wait:
		var out: String = args.get("out", "/tmp/rope")
		var name := "%s_%s.png" % [out, scene]
		root.get_texture().get_image().save_png(name)
		print("保存: ", name)
		if args.has("dump"):
			var inv: Transform3D = sled.global_transform.affine_inverse()
			for q in [0, 3, 6, 9, 12, 16, 20, 26]:
				var w: Vector3 = sled.rope._pos[q]
				print("  点%d ソリから %s 雪からの高さ %.2f" % [q, (inv * w).snapped(Vector3.ONE * 0.01), w.y - main.height(w.x, w.z)])
		_set = false
		_i += 1
		if _i >= SCENES.size() or args.has("only"):
			quit()
	return false
