extends SceneTree
## ビーズクッションに座ったまま、体の向きを 8 方向（45° ごと）へ回して、めり込みを数えて撮る（確かめ用）。
##   Godot --path game --resolution 1000x1000 -s res://tools/beanbag_turn_check.gd -- [--kinds=all|kasa,news] [--bags=0,1,2,3] [--out=DIR]
## 人形は seats.gd の席に、プレイヤーと同じ形（向きについてくる rock_turns・もたれ rock_lean）で座らせる。数えるのは:
##   袋: 脚（太もも・すね・足）の頂点のうち、袋の面より 3 cm より深く入ったもの（腰のくぼみは沈むので体は数えない）
##   床: 床より 1 cm より下へ出た頂点（ラグの毛足は柔らかいので、床の板で数える）
##   家具: ほかの家具（暖炉・ソファ・揺り椅子・ほかの袋・薪のかご）の当たりの箱に入った頂点
## 絵は 1 つ目の袋で、人形を縦、向きを横に並べる（どの向きも同じ所から斜め上に見下ろす）

const Doll := preload("res://doll.gd")
const CELL := Vector2i(240, 240)
const DIRS := 8

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var _kinds: Array = []
var _bags: Array = []        # 席の番号
var _hosts: Array = []
var _dolls: Array = []
var _step := -1
var _wait := 0
var _sheet: Image
var _worst := {}
var _below_bones := {}       # 床の下へ出た頂点の骨の名前


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	_kinds = Doll.KINDS if args.get("kinds", "all") == "all" else Array(String(args.kinds).split(","))
	for k in _kinds:
		var host := Node3D.new()
		root.add_child(host)
		host.visible = false
		var d := Doll.new()
		d.kind = k
		host.add_child(d)
		d.act = Doll.Act.SIT
		d.sit_stage = 2
		_hosts.append(host)
		_dolls.append(d)


func _out() -> String:
	return args.get("out", "/tmp")


func _process(dt: float) -> bool:
	t += dt
	for d in _dolls:
		d.set("_next_breath", 100000)
	var seats = main.get("seats")
	if seats == null or seats.seats.is_empty() or t < 2.0:
		return false
	if _step < 0:
		if main.settings:
			main.settings.set_open(false)
		for c in root.find_children("*", "CanvasLayer", true, false):
			c.visible = false
		for c in main.get_children():
			if c.get("doll") != null:
				c.visible = false
				c.global_position += Vector3(0, -50, 0)   # あなたと仲間は居場所の外へ
		var want: Array = Array(String(args.get("bags", "0,1,2,3")).split(",")).map(func(x): return int(x))
		var n := 0
		for i in seats.seats.size():
			if seats.seats[i].kind == "beanbag":
				if n in want:
					_bags.append(i)
				n += 1
		_sheet = Image.create(CELL.x * DIRS, CELL.y * _dolls.size(), false, Image.FORMAT_RGBA8)
		_step = 0
		_place(seats)
		return false
	_wait += 1
	if _wait < 10:   # 回しきって、座った姿のコマが出るまで
		return false
	_wait = 0
	_count(seats)
	var per := DIRS * _dolls.size()
	if _step < per:   # 1 つ目の袋だけ撮る
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var sz := img.get_size()
		var sq := mini(sz.x, sz.y)
		img = img.get_region(Rect2i((sz.x - sq) / 2, (sz.y - sq) / 2, sq, sq))
		img.resize(CELL.x, CELL.y)
		_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((_step % DIRS) * CELL.x, (_step / DIRS) * CELL.y))
	_step += 1
	if _step >= per * _bags.size():
		var path := "%s/beanbag_turn.png" % _out()
		_sheet.save_png(path)
		print("撮った: ", path)
		print("床の下へ出た頂点の骨: ", _below_bones.keys())
		for k in _worst:
			print("いちばん悪い %s: %s" % [k, _worst[k]])
		return true
	_place(seats)
	return false


## いまの段: 袋 _step / (8 × 人形の数)、人形 (_step / 8) % 人形の数、向き _step % 8
func _parts() -> Array:
	var per := DIRS * _dolls.size()
	return [_bags[_step / per], (_step % per) / DIRS, _step % DIRS]


func _face(st: Dictionary, dir: int) -> Vector3:
	return (st.face as Vector3).rotated(Vector3.UP, TAU * dir / DIRS)


func _place(seats) -> void:
	var p := _parts()
	var st: Dictionary = seats.seat(p[0])
	for k in _hosts.size():
		_hosts[k].visible = k == p[1]
	var d = _dolls[p[1]]
	_hosts[p[1]].global_position = st.pos
	var f := _face(st, p[2])
	d.facing = f
	d.set("_yaw", atan2(-f.x, -f.z))
	d.seat_drop = st.pos.y - st.floor
	d.seat_edge = st.edge
	d.rock_turns = true
	d.rock_axis = st.rock_axis
	d.rock_at = st.rock_at
	d.rock = float(st.get("rock_lean", 0.0))
	# 同じ所から斜め上に見下ろす（袋の暖炉と反対の側、右うしろ）
	var back: Vector3 = -st.face
	var c: Vector3 = st.pos + Vector3.UP * 0.25
	cam.look_at_from_position(c + (back * 1.6 + back.cross(Vector3.UP) * 1.1 + Vector3.UP * 1.5), c)
	cam.current = true


func _count(seats) -> void:
	var p := _parts()
	var st: Dictionary = seats.seat(p[0])
	var d = _dolls[p[1]]
	var nook := main.find_child("HearthNook", true, false)
	var bag: Node3D = null
	for b in nook._beans:
		if bag == null or (b[0] as Node3D).global_position.distance_to(st.pos) < bag.global_position.distance_to(st.pos):
			bag = b[0]
	var groups := _skinned(d)
	var in_bag := 0
	var bag_deep := 0.0
	var below := 0
	var below_deep := 0.0
	var in_furn := 0
	var furn_deep := 0.0
	var boxes := []   # [世界→箱の座標, 半分の大きさ]
	for sb in nook.find_children("*", "StaticBody3D", true, false):
		if bag.is_ancestor_of(sb):
			continue
		for cs in (sb as Node).get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
				boxes.append([(cs as CollisionShape3D).global_transform.affine_inverse(), ((cs as CollisionShape3D).shape as BoxShape3D).size * 0.5])
	var tops := {}
	for b in groups:
		var leg: bool = b.begins_with("thigh") or b.begins_with("shin") or b.begins_with("foot")
		for v: Vector3 in groups[b]:
			if v.y < st.floor - 0.01:
				below += 1
				below_deep = maxf(below_deep, st.floor - v.y)
				_below_bones[b] = true
			for bx in boxes:
				var l: Vector3 = bx[0] * v
				var h: Vector3 = bx[1]
				var dd := minf(h.x - absf(l.x), minf(h.y - absf(l.y), h.z - absf(l.z)))
				if dd > 0.0:
					in_furn += 1
					furn_deep = maxf(furn_deep, dd)
			if leg:
				var key := Vector2i(roundi(v.x * 50.0), roundi(v.z * 50.0))   # 2 cm の升目ごとに袋の面の高さを測る
				if not tops.has(key):
					tops[key] = nook._top_at(bag, bag.to_local(Vector3(v.x, 0, v.z)), -INF)
				var top: float = tops[key]
				if top > -INF:
					var top_w := bag.to_global(Vector3(0, top, 0)).y
					if v.y < top_w - 0.03:
						in_bag += 1
						bag_deep = maxf(bag_deep, top_w - v.y)
	var line := "袋 %d %s %3d°: 袋へ入った脚の頂点 %d（%.3f m）、床の下 %d（%.3f m）、ほかの家具 %d（%.3f m）" % [p[0], d.kind, 360 * p[2] / DIRS, in_bag, bag_deep, below, below_deep, in_furn, furn_deep]
	print(line)
	for k in ["袋", "床", "家具"]:
		var v: float = {"袋": bag_deep, "床": below_deep, "家具": furn_deep}[k]
		if not _worst.has(k) or v > float(_worst[k].get_slice(" ", 0)):
			_worst[k] = "%s %s" % [str(v), line]


## 人形の形の頂点を、いまの骨の姿勢で曲げ、いちばん重い骨の名前ごとに世界の座標で返す（sit_side_shots.gd と同じ）
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
