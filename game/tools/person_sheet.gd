extends SceneTree
## 人の形の案を並べて撮る（見比べ用）。
##   Godot --path game -s res://tools/person_sheet.gd -- --set=1 --out=/path/to.png [--near]
## --set で並べる組を選ぶ。--near で顔に寄る。

const Look := preload("res://look.gd")
const Person := preload("res://person.gd")

const RED := Color(0.85, 0.33, 0.31)
const INDIGO := Color(0.18, 0.44, 0.56)
const YAMABUKI := Color(0.85, 0.63, 0.19)

## [記号, 名前, spec, 動き]。動き: idle / wave / walk / call
const SETS := {
	"1": [
		["A", "ミニ紙風船", {"heads": 2.5, "head": "balloon", "eyes": "move", "mouth": "open", "cheeks": true, "coat": "long", "hat": "cone", "color": RED}, "wave"],
		["B", "ぬいぐるみ", {"heads": 2.5, "head": "balloon", "eyes": "ink", "mouth": "none", "arm_joints": 1, "leg_joints": 1, "hand": "ball", "fabric": "knit", "coat": "short", "hat": "earflap", "scarf": true, "color": INDIGO}, "idle"],
		["C", "折り紙の玉", {"heads": 3.5, "head": "gem", "eyes": "move", "mouth": "line", "nose": true, "ears": true, "arm_joints": 3, "fabric": "cloth", "coat": "short", "hat": "beanie", "color": YAMABUKI}, "walk"],
		["D", "切り紙", {"heads": 4.5, "head": "flat", "depth": 0.35, "eyes": "slit", "mouth": "none", "coat": "poncho", "hat": "cone", "color": RED}, "wave"],
		["E", "顔なし", {"heads": 3.0, "head": "egg", "eyes": "none", "mouth": "none", "fabric": "cloth", "coat": "poncho", "hat": "hood", "scarf": true, "color": INDIGO}, "idle"],
		["F", "卵", {"heads": 4.0, "head": "egg", "eyes": "move", "mouth": "open", "nose": true, "ears": true, "fabric": "knit", "coat": "long", "hat": "earflap", "color": YAMABUKI}, "call"],
	],
	"2": [
		["G", "紙風船フード", {"heads": 3.0, "head": "balloon", "eyes": "move", "eye_size": 1.4, "mouth": "open", "coat": "poncho", "hat": "hood", "color": RED}, "call"],
		["H", "ミニ玉", {"heads": 2.5, "head": "gem", "eyes": "ink", "mouth": "open", "hand": "ball", "coat": "short", "hat": "beanie", "scarf": true, "color": INDIGO}, "wave"],
		["I", "耳つき帽", {"heads": 3.0, "head": "balloon", "eyes": "move", "mouth": "open", "cheeks": true, "fabric": "knit", "coat": "long", "hat": "bear", "color": YAMABUKI}, "idle"],
		["J", "すらり", {"heads": 5.0, "head": "egg", "eyes": "ink", "mouth": "line", "nose": true, "arm_joints": 3, "fabric": "cloth", "coat": "long", "hat": "beanie", "scarf": true, "color": RED}, "walk"],
		["K", "卵ミニ", {"heads": 2.5, "head": "egg", "eyes": "move", "eye_size": 1.3, "mouth": "open", "cheeks": true, "coat": "long", "hat": "earflap", "color": INDIGO}, "idle"],
		["L", "切り紙ずんぐり", {"heads": 3.0, "head": "flat", "depth": 0.35, "eyes": "ink", "mouth": "open", "cheeks": true, "fabric": "cloth", "coat": "short", "hat": "bear", "color": YAMABUKI}, "wave"],
	],
	# 共在感覚の調べを踏まえて絞った候補。目は墨の点でまばたき、口なし、肩・肘・手首・膝・足首、親指つきミトン
	"3": [
		["M", "紙風船ミニ", {"heads": 2.5, "head": "balloon", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "long", "hat": "cone", "color": RED}, "wave"],
		["N", "紙風船", {"heads": 3.0, "head": "balloon", "eyes": "ink", "mouth": "none", "arm_joints": 3, "fabric": "knit", "coat": "short", "hat": "earflap", "scarf": true, "color": INDIGO}, "point"],
		["O", "卵フード", {"heads": 3.0, "head": "egg", "eyes": "ink", "mouth": "none", "arm_joints": 3, "fabric": "cloth", "coat": "poncho", "hat": "hood", "color": YAMABUKI}, "call"],
		["P", "折り紙の玉", {"heads": 3.0, "head": "gem", "eyes": "ink", "mouth": "none", "arm_joints": 3, "coat": "long", "hat": "beanie", "scarf": true, "color": RED}, "walk"],
		["Q", "卵耳つき帽", {"heads": 2.5, "head": "egg", "eyes": "ink", "mouth": "none", "arm_joints": 3, "fabric": "knit", "coat": "long", "hat": "bear", "color": INDIGO}, "look"],
	],
	# 折り紙の形。面に折り目、手足は折った紙の棒。' は使い込んだもの（折りじわと水のシミ）
	"4": [
		["R", "紙風船と兜", {"origami": true, "heads": 2.5, "head": "balloon", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "long", "hat": "kabuto", "color": RED}, "wave"],
		["R'", "使い込み", {"origami": true, "wear": 1.0, "heads": 2.5, "head": "balloon", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "long", "hat": "kabuto", "color": RED}, "idle"],
		["S", "奴さん", {"origami": true, "heads": 3.0, "head": "gem", "eyes": "ink", "mouth": "none", "arm_joints": 3, "coat": "yakko", "hat": "cone", "color": INDIGO}, "point"],
		["T", "折り紙の玉", {"origami": true, "heads": 3.0, "head": "gem", "eyes": "ink", "mouth": "none", "arm_joints": 3, "fabric": "cloth", "coat": "short", "hat": "beanie", "scarf": true, "color": YAMABUKI}, "walk"],
		["U", "紙風船と耳当て", {"origami": true, "heads": 3.0, "head": "balloon", "eyes": "ink", "mouth": "none", "arm_joints": 3, "coat": "poncho", "hat": "earflap", "color": INDIGO}, "call"],
		["U'", "使い込み", {"origami": true, "wear": 1.0, "heads": 3.0, "head": "balloon", "eyes": "ink", "mouth": "none", "arm_joints": 3, "coat": "poncho", "hat": "earflap", "color": INDIGO}, "look"],
	],
	# 代表の参考（千代紙の折り紙人形・笠の人・Pinterest のボード）から
	"5": [
		["V", "千代紙人形", {"origami": true, "heads": 4.5, "head": "plate", "hair": "bob", "eyes": "arc", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "kimono", "pattern": "seigaiha", "inner": Color(0.93, 0.89, 0.8), "hat": "none", "color": RED}, "wave"],
		["W", "笠の人", {"origami": true, "heads": 5.5, "neck": 2.6, "head": "egg", "eyes": "none", "mouth": "none", "arm_joints": 3, "coat": "kimono", "pattern": "kikko", "inner": Color(0.62, 0.2, 0.18), "hat": "kasa", "color": Color(0.93, 0.9, 0.83)}, "wave"],
		["X", "笠の子", {"origami": true, "heads": 3.0, "head": "egg", "eyes": "ink", "mouth": "none", "arm_joints": 3, "coat": "kimono", "pattern": "mizutama", "inner": Color(0.85, 0.33, 0.31), "hat": "kasa", "color": YAMABUKI}, "call"],
		["Y", "角巻", {"origami": true, "heads": 4.0, "head": "plate", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "kimono", "pattern": "ichimatsu", "inner": Color(0.85, 0.63, 0.19), "hat": "kakumaki", "color": INDIGO}, "look"],
		["Z", "おかっぱ無地", {"origami": true, "heads": 5.0, "neck": 2.0, "head": "plate", "hair": "bob", "eyes": "none", "mouth": "none", "arm_joints": 3, "coat": "kimono", "pattern": "koshi", "inner": Color(0.62, 0.2, 0.18), "hat": "none", "color": Color(0.2, 0.2, 0.24)}, "walk"],
	],
	# Y（角巻）を元に。手足は肩から手首まで一本の筒
	"6": [
		["Y1", "角巻", {"origami": true, "head": "plate", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "kimono", "heads": 4.0, "pattern": "ichimatsu", "inner": Color(0.85, 0.63, 0.19), "hat": "kakumaki", "color": INDIGO}, "idle"],
		["Y2", "角巻ミニ", {"origami": true, "head": "plate", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "kimono", "heads": 3.0, "pattern": "seigaiha", "inner": Color(0.93, 0.89, 0.8), "hat": "kakumaki", "color": RED}, "wave"],
		["Y3", "笠", {"origami": true, "head": "plate", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "kimono", "heads": 4.0, "hair": "bob", "pattern": "mizutama", "inner": Color(0.85, 0.33, 0.31), "hat": "kasa", "color": YAMABUKI}, "call"],
		["Y4", "兜", {"origami": true, "head": "plate", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "kimono", "heads": 3.0, "pattern": "kikko", "inner": Color(0.85, 0.63, 0.19), "hat": "kabuto", "color": INDIGO}, "point"],
		["Y5", "角巻・歩く", {"origami": true, "head": "plate", "eyes": "ink", "mouth": "none", "cheeks": true, "arm_joints": 3, "coat": "kimono", "heads": 4.0, "pattern": "koshi", "inner": Color(0.93, 0.89, 0.8), "hat": "kakumaki", "color": YAMABUKI}, "walk"],
	],
}

var args := {}
var people: Array = []
var t := 0.0
var cam: Camera3D


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
	env.ssao_intensity = 2.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -40, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.45
	sun.light_angular_distance = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = Look.snow()
	world.add_child(ground)

	var near := args.has("near")
	var list: Array = SETS[args.get("set", "1")]
	var n := list.size()
	var gap := 1.4 if n > 5 else 1.65
	cam = Camera3D.new()
	world.add_child(cam)
	if near:
		var cx := float(args.get("cx", "0"))   # 寄る所の横の位置
		cam.look_at_from_position(Vector3(cx, 1.45, 4.6 if not args.has("cx") else 2.6), Vector3(cx, 1.1, 0))
		cam.fov = 38
	else:
		cam.look_at_from_position(Vector3(0, 1.1, 8.2), Vector3(0, 0.88, 0))
		cam.fov = 36
	cam.current = true

	for k in n:
		var item: Array = list[k]
		var host := Node3D.new()
		host.position = Vector3((k - (n - 1) * 0.5) * gap, 0, 0)
		world.add_child(host)
		var p := Person.new()
		p.spec = item[2]
		host.add_child(p)
		var to_cam := cam.position - host.position
		to_cam.y = 0
		p.facing = to_cam.rotated(Vector3.UP, 0.35 if k % 2 == 0 else -0.35)
		p.gaze = cam.position
		match item[3]:
			"wave":
				p.waving = true
			"walk":
				p.demo_speed = 3.0
				p.demo_phase = 1.3
				p.facing = Vector3(1 if k % 2 == 0 else -1, 0, 0.6)
				p.gaze = Vector3.INF
			"call":
				p.call_deferred("call_out")
			"point":
				p.point = host.position + Vector3(-4, 2.2, 3)
				p.gaze = p.point
			"look":
				p.gaze = host.position + Vector3(-1.4, 1.2, 0)
		var label := Label3D.new()
		label.text = "%s  %s" % [item[0], item[1]]
		label.font_size = 44
		label.pixel_size = 0.0042
		label.outline_size = 10
		label.modulate = Color(0.2, 0.2, 0.25)
		label.outline_modulate = Color(1, 1, 1)
		label.position = Vector3(0, 0.08, 0.75)
		label.rotation.x = -0.35
		host.add_child(label)
		people.append(p)


func _process(dt: float) -> bool:
	t += dt
	if t > 1.0 and t - dt <= 1.0:
		for p in people:
			if p._voice == 0:
				p._next_breath = p._frame + randi_range(0, 3)
	if t > float(args.get("at", "1.45")):
		var img := root.get_texture().get_image()
		img.save_png(args.get("out", "/tmp/person_sheet.png"))
		print("保存: ", args.get("out", ""))
		quit()
	return false
