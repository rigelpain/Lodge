extends SceneTree
## 7 体の人形を横一列に並べ、背丈と目の高さを比べる絵を撮る（正射影なので、絵の上の高さがそのまま比べられる）。
##   Godot --path game --resolution 1800x500 -s res://tools/height_lineup.gd -- --out=/path/to.png
## 0.5 m おきの目盛りの線（濃い線は 1 m）、人形ごとに目の所に赤い玉（一人称のカメラの高さ）を置く。
## --scale=golem:1.45 で大きさの案を見る（doll.gd は変えずに）。背丈（TOP × SCALE）・形から測った頭のてっぺん・目の高さを、標準出力に表で出す

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

var args := {}
var t := 0.0
var cam: Camera3D
var dolls: Array = []
var _printed := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -25, 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Look.snow()
	world.add_child(ground)

	var kinds: Array = Doll.KINDS
	var scales := {}
	for kv in String(args.get("scale", "")).split(",", false):
		scales[kv.get_slice(":", 0)] = float(kv.get_slice(":", 1))
	var n := kinds.size()
	var gap := 1.25
	var span := gap * n
	# 目盛り: 人形のうしろの壁に、0.5 m おきの横線
	for i in range(1, 5):
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(span + 0.6, 0.012 if i % 2 else 0.022, 0.01)
		line.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.25, 0.3, 0.4) if i % 2 == 0 else Color(0.45, 0.5, 0.6)
		line.material_override = m
		line.position = Vector3(0, i * 0.5, -0.9)
		world.add_child(line)
	for k in n:
		var host := Node3D.new()
		host.position = Vector3((k - (n - 1) * 0.5) * gap, 0, 0)
		world.add_child(host)
		var d := Doll.new()
		d.kind = kinds[k]
		host.add_child(d)
		if scales.has(d.kind):   # 大きさの案を見る: --scale=golem:1.45,origami:1.0（doll.gd の SCALE の代わり。絵と目の玉だけ）
			d._scale = scales[d.kind]
			d._body.scale = Vector3.ONE * d._scale
		d.facing = Vector3(0, 0, 1)
		d.gaze = Vector3.INF
		dolls.append(d)
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		eye.mesh = sm
		var em := StandardMaterial3D.new()
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		em.albedo_color = Color(0.9, 0.1, 0.1)
		em.no_depth_test = true
		eye.material_override = em
		host.add_child(eye)
		eye.set_meta("doll", d)

	cam = Camera3D.new()
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = span + 0.4
	cam.position = Vector3(0, 1.15, 12)
	cam.current = true


func _process(dt: float) -> bool:
	t += dt
	for d in dolls:
		for c in d.get_parent().get_children():
			if c.has_meta("doll"):
				var e: Vector3 = d.eye_point(false)
				c.position = Vector3(0, e.y, 0.6)
	if not _printed and t > 0.5:
		_printed = true
		print("| キャラ | SCALE | 背丈 (TOP×SCALE, m) | 形のてっぺん (m) | 目の高さ (m) |")
		for d in dolls:
			var c: Array = Doll._body_cache.get(d.kind, [[], 0.0, 0.0])
			print("| %s | %.2f | %.2f | %.2f | %.2f |" % [d.kind, d._scale, Doll.TOP[d.kind] * d._scale, float(c[1]), d.eye_point(false).y])
	if t > float(args.get("at", "1.0")):
		var img := root.get_texture().get_image()
		img.save_png(args.get("out", "/tmp/height_lineup.png"))
		quit()
	return false
