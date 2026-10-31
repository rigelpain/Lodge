extends SceneTree
## 3 体の人形を並べて撮る（骨と姿勢の確かめ用）。
##   Godot --path game -s res://tools/doll_shots.gd -- --out=/path/to.png [--at=秒] [--pose=idle|walk|wave|call|breath]
## 並べる人形を替える: --kinds=robo,musha,ningyo,golem（doll.gd の KINDS のどれでも。--kinds=all で 7 体）
## 息の見本: --pose=breath --close（顔の近くから）[--dark（うしろに暗い壁。ロッジの壁や木の前の見え方）] [--caller=0〜2]
## kasa は立ってこちらを見る、origami は手を振る、news は横へ歩く（--pose で全員を同じにもできる）
## 指さしの見本: --pose=point（① が赤い玉を指し、② と ③ がそこを見る）

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

var args := {}
var t := 0.0
var walkers: Array[Node3D] = []
var cam: Camera3D
var _breathers: Array = []
var _called := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Look.sky(world)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.4
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -40, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = Look.snow()
	world.add_child(ground)

	cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.2, 4.6), Vector3(0, 0.8, 0))
	cam.fov = 40
	if args.has("close"):
		# 寒い外で、真ん中の人形の顔と息を近くから
		cam.look_at_from_position(Vector3(-0.55, 1.5, 1.55), Vector3(-1.05, 1.22, 0.0))
		cam.fov = 45
	cam.current = true

	if args.has("dark"):
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(6, 4, 0.1)
		wall.mesh = bm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.15, 0.18, 0.25)
		wall.material_override = wm
		wall.position = Vector3(-1.0, 1, -1.4)
		world.add_child(wall)
	# 指さしの見本: 右前の地面に赤い玉を置き、① がそれを指し、② と ③ はそこへ顔を向ける
	var target := Vector3(2.2, 0.15, 1.6)
	if args.get("pose", "") == "point":
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.3
		ball.mesh = sm
		ball.material_override = Look.felt(Color(0.85, 0.25, 0.22), 3.0)
		ball.position = target
		world.add_child(ball)
		cam.look_at_from_position(Vector3(-2.6, 2.0, 4.2), Vector3(0.6, 0.6, 0.6))
	var kinds: Array = ["kasa", "origami", "news"]
	if args.has("kinds"):
		kinds = Doll.KINDS if args.kinds == "all" else Array(String(args.kinds).split(","))
	var n := kinds.size()
	var gap := 1.3 if n <= 3 else 1.15
	if n > 3:   # 並びが広いので引く
		cam.look_at_from_position(Vector3(0, 1.3, 1.6 + gap * n), Vector3(0, 0.75, 0))
	for k in n:
		var host := Node3D.new()
		host.position = Vector3((k - (n - 1) * 0.5) * gap, 0, 0)
		world.add_child(host)
		var d := Doll.new()
		d.kind = kinds[k]
		host.add_child(d)
		var to_cam := cam.position - host.position
		to_cam.y = 0
		d.facing = to_cam.rotated(Vector3.UP, 0.3)
		d.gaze = cam.position
		var pose: String = args.get("pose", ["idle", "wave", "walk"][k % 3])
		match pose:
			"wave":
				d.waving = true
			"walk":
				d.facing = Vector3(1, 0, 0.4)
				d.gaze = Vector3.INF
				walkers.append(host)
			"call":
				d.call_deferred("call_out")
			"point":
				d.facing = Vector3(0.3, 0, 1)
				if k == 0:
					d.point = target
				else:
					d.gaze = target
			"breath":
				d.facing = Vector3(1, 0, 0.5)
				d.gaze = d.global_position + Vector3(3, 1.3, 1.2)
				_breathers.append(d)


func _physics_process(dt: float) -> bool:
	for h in walkers:
		h.position.x += dt * 1.6
		if h.position.x > 2.0:
			h.position.x = 0.4
	return false


func _process(dt: float) -> bool:
	t += dt
	# 息の見本: 真ん中は声を出して大きな息、両脇はふだんの小さな息
	if not _called and t > float(args.get("puff-at", "0.5")):
		_called = true
		for k in _breathers.size():
			var d = _breathers[k]
			if k == int(args.get("caller", "0")):
				d.call_out()
			else:
				d._next_breath = d._frame
	if t > float(args.get("at", "1.3")):
		var img := root.get_texture().get_image()
		img.save_png(args.get("out", "/tmp/dolls.png"))
		print("保存: ", args.get("out", ""))
		quit()
	return false
