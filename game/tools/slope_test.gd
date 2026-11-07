extends SceneTree
## 斜面を横切って登るときの、視点（カメラ）の震えを数字で測る（画面なしで動く）。
##   Godot --headless --path game -s res://tools/slope_test.gd -- [--angle=度] [--grip]
## あなたを丘の中腹に立たせ、頂上の向きから angle 度ずらした向きへ W で歩かせる（既定 60 度＝ほぼ横切る）。
## --grip: ソリを斜面に横向きに置き、下側の横からつかんで、斜面の上へ横向きに押す。
## 毎物理フレームのカメラの位置と向きから、なめらかな動きを引いた残り（震え）と、1 フレームで 2 cm 以上の高さの跳びを数える。

var args := {}
var main: Node3D
var t := 0.0
var started := false
var ys: Array[float] = []
var ps: Array[Vector3] = []
var fs: Array[Vector3] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _physics_process(dt: float) -> bool:
	t += dt
	var p = main.player
	if p == null:
		return false
	if not started and t > 0.5:
		started = true
		var pos := Vector3(float(args.get("x", "16")), 0.0, float(args.get("z", "6")))
		pos.y = main.height(pos.x, pos.z) + 0.3
		p.global_position = pos
		var up_hill := Vector3(-pos.x, 0, -pos.z).normalized()
		var dir := up_hill.rotated(Vector3.UP, deg_to_rad(float(args.get("angle", "60"))))
		p.rotation.y = atan2(-dir.x, -dir.z)
		if args.has("grip"):
			# ソリの長い向きを斜面の横に。あなたはその下側の横に立ち、上へ押す
			var sled: RigidBody3D = main.sled
			var along := up_hill.cross(Vector3.UP).normalized()
			var spos := pos + up_hill * 1.6
			spos.y = main.height(spos.x, spos.z) + 0.4
			sled.global_transform = Transform3D(Basis.looking_at(along, Vector3.UP), spos)
			sled.linear_velocity = Vector3.ZERO
			sled.angular_velocity = Vector3.ZERO
			p.global_position = spos - up_hill * 1.35 + Vector3.UP * 0.2
			p.rotation.y = atan2(-up_hill.x, -up_hill.z)
			p.grab()
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
	if started and t > 1.0:
		ys.append(p.cam.global_position.y)
		ps.append(p.cam.global_position)
		fs.append(-p.cam.global_basis.z)
	if t > 4.0:
		var jumps := 0
		var acc := 0.0
		for i in range(2, ys.size()):
			var d2 := ys[i] - 2.0 * ys[i - 1] + ys[i - 2]
			acc += absf(d2)
			if absf(ys[i] - ys[i - 1]) > 0.02:
				jumps += 1
		var pacc := 0.0
		var facc := 0.0
		for i in range(2, ps.size()):
			pacc += (ps[i] - 2.0 * ps[i - 1] + ps[i - 2]).length()
			facc += (fs[i] - 2.0 * fs[i - 1] + fs[i - 2]).length()
		var nn := maxf(1.0, ys.size() - 2)
		print("フレーム=%d 高さの震え=%.4f m 位置の震え=%.4f m 向きの震え=%.4f 跳び=%d 登った高さ=%.2f m あなた=%d" % [ys.size(), acc / nn, pacc / nn, facc / nn, jumps, ys[-1] - ys[0], p.mode])
		quit()
	return false
