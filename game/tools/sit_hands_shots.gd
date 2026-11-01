extends SceneTree
## ロッジの席に座った人形の手（膝の上）が、体（胸・腹・腰・裾・太もも）に埋もれていないかを撮って数える（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/sit_hands_shots.gd -- [--kinds=all|kasa,news] [--out=DIR]
## 人形を箱の椅子に座らせ、1 体ずつ前・横・斜め上から近くで撮って 1 枚に並べる（--out の sit_hands.png）。
## 埋もれは、人形の形を骨で曲げた頂点（CPU で計算）で数える: 手の頂点のうち、体の頂点がつくる箱（骨ごと）の中に入ったもの

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

const SEAT_H := 0.45
const ARM := ["upper_arm", "forearm", "hand"]

var args := {}
var t := 0.0
var cam: Camera3D
var dolls: Array = []
var _out := ""
var _step := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = args.get("out", "/tmp")
	root.scaling_3d_scale = 1.0
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	var kinds: Array = Doll.KINDS if args.get("kinds", "all") == "all" else Array(String(args.kinds).split(","))
	for k in kinds.size():
		var x := k * 3.0   # 斜めに離して並べ、前と横の近写しに隣が映らない
		var stool := CSGBox3D.new()
		stool.size = Vector3(0.45, SEAT_H, 0.45)
		stool.position = Vector3(x, SEAT_H * 0.5, -x)
		world.add_child(stool)
		var host := Node3D.new()
		host.position = Vector3(x, SEAT_H, -x)
		world.add_child(host)
		var d := Doll.new()
		d.kind = kinds[k]
		host.add_child(d)
		d.facing = Vector3(0, 0, 1)   # こちら（+Z）を向く
		d.act = Doll.Act.SIT
		d.sit_stage = 2
		d.seat_drop = SEAT_H
		dolls.append(d)


## 人形ごとに 前・横・斜め上 の 3 枚を撮り、人形を縦、向きを横に並べた 1 枚にする
const VIEWS := [Vector3(0, 0.15, 1.0), Vector3(1.0, 0.1, 0.0), Vector3(0.55, 0.9, 0.75)]
const CELL := Vector2i(400, 400)
var _sheet: Image


var _wait := 0


func _process(dt: float) -> bool:
	t += dt
	for d in dolls:
		d.set("_next_breath", 100000)   # 白い息で手が隠れないように
	if t < 1.5:
		return false
	if _step == 0 and _sheet == null:
		_report()
		_sheet = Image.create(CELL.x * VIEWS.size(), CELL.y * dolls.size(), false, Image.FORMAT_RGBA8)
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
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((_step % VIEWS.size()) * CELL.x, (_step / VIEWS.size()) * CELL.y))
	_step += 1
	if _step >= dolls.size() * VIEWS.size():
		var path := "%s/sit_hands.png" % _out
		_sheet.save_png(path)
		print("撮った: ", path)
		return true
	_aim_cam()
	return false


func _aim_cam() -> void:
	var d = dolls[_step / VIEWS.size()]
	var h: float = d.height()
	var at: Vector3 = d.get_parent().global_position + Vector3(0, h * 0.2, 0)
	var v: Vector3 = VIEWS[_step % VIEWS.size()]
	cam.look_at_from_position(at + v.normalized() * (0.3 + h * 1.1), at)


## 人形ごとに、手と前腕の頂点が体の骨の形に入った数と深さを書き出す
func _report() -> void:
	for d in dolls:
		var groups := _skinned(d)
		var body: Array = []   # 骨ごとの [箱]
		for b in groups:
			if _is_arm(b) or groups[b].size() < 8:
				continue
			body.append([b, _bounds(groups[b])])
		var line := ""
		for side in ["L", "R"]:
			var n := 0
			var hit := {}
			for part in ["forearm", "hand"]:
				var key: String = part + "." + side
				if not groups.has(key):
					continue
				for v in groups[key]:
					for bb in body:
						if (bb[1] as AABB).has_point(v):
							n += 1
							hit[bb[0]] = int(hit.get(bb[0], 0)) + 1
							break
			line += "  %s: 体に入った頂点 %d %s" % [side, n, hit]
		print(d.kind, line)


func _is_arm(b: String) -> bool:
	for a in ARM:
		if b.begins_with(a):
			return true
	return b.begins_with("finger") or b.begins_with("thumb")


func _bounds(vs: PackedVector3Array) -> AABB:
	var box := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		box = box.expand(v)
	return box


## 人形の形の頂点を、いまの骨の姿勢で曲げ、いちばん重い骨の名前ごとに世界の座標で返す
func _skinned(doll) -> Dictionary:
	var out := {}
	var skel: Skeleton3D = doll.skel
	for m in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.skin == null:
			continue
		var skin := mi.skin
		var bind_xf := []
		var names := []
		for b in skin.get_bind_count():
			var bi := skin.get_bind_bone(b)
			if bi < 0:
				bi = skel.find_bone(skin.get_bind_name(b))
			bind_xf.append(skel.get_bone_global_pose(bi) * skin.get_bind_pose(b))
			names.append(skel.get_bone_name(bi))
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null:
				continue
			var per: int = bones.size() / vs.size()
			for vi in vs.size():
				var acc := Vector3.ZERO
				var wsum := 0.0
				var top := -1.0
				var top_b := 0
				for j in per:
					var w: float = weights[vi * per + j]
					if w <= 0.0:
						continue
					acc += (bind_xf[bones[vi * per + j]] as Transform3D) * vs[vi] * w
					wsum += w
					if w > top:
						top = w
						top_b = bones[vi * per + j]
				if wsum > 0.0:
					var nm: String = names[top_b]
					if not out.has(nm):
						out[nm] = PackedVector3Array()
					out[nm].append(skel.global_transform * (acc / wsum))
	return out
