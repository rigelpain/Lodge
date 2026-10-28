extends SceneTree
## ソリの滑りあと（ステッチ）を、近くと少し遠くから撮る（跡の見た目の確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/trail_shot.gd -- --bots=0 --no-sound --time=14 --out=/path/trail [--slide=6]
## 頂上の少し下にソリを置き、あなたを乗せて W（前傾）で滑らせる。slide 秒たったらソリを止めて
## 跡を残したまま、<out>_near.png（足もと 1 m ほど）と <out>_far.png（6 m ほど）を書く。
## 滑っている間のコマの時間も出す（重さの目安）。

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var phase := 0
var _ft := PackedFloat32Array()
var _shot_t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 50
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)


func _process(dt: float) -> bool:
	t += dt
	var sled: RigidBody3D = main.sled
	var p = main.player
	if sled == null or p == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if main._pip_layer:
		main._pip_layer.visible = false
	var slide := float(args.get("slide", "6"))
	if phase == 0 and t > 0.6:
		# 頂上の東 6 m に、+x（下り）を向けて置き、乗せて前傾で滑らせる
		var at := Vector3(6.0, 0, 0)
		at.y = main.height(at.x, at.z) + 0.6
		sled.reset_to(at)
		sled.rotation.y = -PI / 2   # -z が前なので、+x を向く
		p.global_position = at + Vector3.UP * 0.5
		p.get_on()
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		phase = 1
		_shot_t = t
	elif phase == 1:
		_ft.append(dt)
		# 滑る間はソリの後ろ上から追う
		var fwd: Vector3 = -sled.global_basis.z
		cam.global_position = sled.global_position - fwd * 6.0 + Vector3.UP * 3.0
		cam.look_at(sled.global_position, Vector3.UP)
		cam.current = true
		if t - _shot_t > slide:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_W
			ev.pressed = false
			Input.parse_input_event(ev)
			sled.freeze = true
			_ft.sort()
			var sum := 0.0
			for f in _ft:
				sum += f
			print("滑った %.1f 秒: 平均 %.1f ms（%.0f fps）中央 %.1f ms 最長 %.1f ms 速さ=%.1f" % [slide, 1000.0 * sum / _ft.size(), _ft.size() / sum, 1000.0 * _ft[_ft.size() / 2], 1000.0 * _ft[-1], sled.linear_velocity.length()])
			phase = 2
			_shot_t = t
	elif phase >= 2:
		# 跡はソリの後ろに伸びている。止めたソリから数 m 戻った所を見る
		var back: Vector3 = sled.global_basis.z
		back.y = 0
		back = back.normalized()
		var side := back.cross(Vector3.UP).normalized()
		var near := phase < 4
		# 近く: 跡から 1 m、目の高さ 0.8 m。少し遠く: 立った人の目（1.7 m）で 5 m 先から
		var dist := 1.0 if near else 5.0
		var focus: Vector3 = sled.global_position + back * (7.0 if near else 6.0)
		focus.y = main.height(focus.x, focus.z)
		var eye := focus + back * dist * 0.9 + side * dist * 0.35   # 坂の上から、下のソリの方を見る
		eye.y = main.height(eye.x, eye.z) + (0.8 if near else 1.7)
		cam.global_position = eye
		cam.look_at(focus - back * (0.15 if near else 2.0), Vector3.UP)
		cam.current = true
		if t - _shot_t > 1.0:
			print("カメラ ", cam.global_position.snapped(Vector3.ONE * 0.1), " 見る先 ", focus.snapped(Vector3.ONE * 0.1), " ソリ ", sled.global_position.snapped(Vector3.ONE * 0.1), " fps=", Engine.get_frames_per_second())
			var out: String = args.get("out", "/tmp/trail")
			var name := "%s_%s.png" % [out, "near" if near else "far"]
			root.get_texture().get_image().save_png(name)
			print("保存: ", name)
			phase += 2
			_shot_t = t
			if phase >= 6:
				quit()
	return false
