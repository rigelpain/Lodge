extends SceneTree
## マップを真上か斜め上から撮る（配置を決める用）。
##   Godot --path game --resolution 1400x1400 -s res://tools/map_shot.gd -- --no-player --no-snow --out=/path/to.png
##     [--span=280]           真上: 写す幅 (m)。正射影で、画像の中心が (0, 0)、上が北（-Z）
##     [--view=x,y,z,tx,ty,tz] 斜め: カメラの位置と見る先（透視）
##     [--post-r=96]          スピーカーの柱をこの半径に立て直して写す（試し。audio.gd は変えない）
##     [--fog]                霧を残す（既定は真上では消す）

var args := {}
var main: Node3D
var t := 0.0
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	t += dt
	if main.hud:
		main.hud.visible = false
	if main.settings:
		main.settings.set_open(false)
	if not _done and t > 0.3:
		_done = true
		_setup()
	if t > 2.5:
		if args.has("dump"):
			_dump(args["dump"])
		var img := root.get_texture().get_image()
		img.save_png(args["out"])
		print("保存: ", args["out"])
		return true
	return false


func _setup() -> void:
	if args.has("post-r"):
		var r := float(args["post-r"])
		var off := deg_to_rad(float(args.get("post-off", "0")))
		for post in main.find_children("SpeakerPost*", "Node3D", true, false):
			var d := Vector2(post.position.x, post.position.z).normalized().rotated(off) * r
			post.position = Vector3(d.x, main.height(d.x, d.y), d.y)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.far = 1000
	if args.has("view"):
		var v: PackedFloat64Array = args["view"].split_floats(",")
		cam.position = Vector3(v[0], v[1], v[2])
		cam.look_at(Vector3(v[3], v[4], v[5]))
		cam.fov = float(args.get("fov", "60"))
	else:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = float(args.get("span", "280"))
		cam.position = Vector3(0, 300, 0)
		cam.rotation = Vector3(-PI / 2, 0, 0)
		if not args.has("fog"):
			main.env.fog_enabled = false
	if main.sun_light:
		main.sun_light.directional_shadow_max_distance = 200
	cam.make_current()


## --dump=PATH: 置いてある物（glb の名前と x, z, 大きさ）を JSON に書く。図を描く用
func _dump(path: String) -> void:
	var items := []
	for n in main.get_children():
		if n is Node3D and n.scene_file_path != "":
			items.append({"file": n.scene_file_path.get_file(), "x": n.position.x, "z": n.position.z,
					"s": n.scale.x, "yaw": n.rotation.y})
		elif n is MeshInstance3D and n.mesh is SphereMesh:   # 遠景のフェルトの山
			items.append({"file": "far", "x": n.position.x, "z": n.position.z, "sx": n.scale.x, "sy": n.scale.y,
					"sz": n.scale.z, "yaw": n.rotation.y})
	for post in main.find_children("SpeakerPost*", "Node3D", true, false):
		items.append({"file": "speaker", "x": post.position.x, "z": post.position.z, "s": 1.0, "yaw": 0.0})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"hill_h": main.HILL_H, "hill_r": main.HILL_R, "size": main.SIZE,
			"start": [main.START.x, main.START.z], "lodge": [main.LODGE_POS.x, main.LODGE_POS.y],
			"lodge_yaw": main.LODGE_YAW, "items": items}))
