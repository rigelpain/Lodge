extends SceneTree
## ロッジの席に 7 体の人形を 1 体ずつ座らせ、真横から撮って 1 枚に並べる（確かめ用）。人形を縦、席の種類を横に並べる。
##   Godot --path game --resolution 1000x1000 -s res://tools/sit_side_shots.gd -- [--kinds=all|kasa,news] [--seats=chair,stool,bench,zabuton] [--out=DIR]
##     [--quarter（真横でなく、斜め前の上から撮る）] [--bones（座布団の席で、骨ごとのいちばん低い所も書く）]
##     [--hard（座布団も椅子と同じ座り方。くらべる用）] [--cell=800（1 枚の大きさ）]
## 席は種類ごとに、カメラを置く横が空いている席（並びの端。なければ並びのまんなか）。人形のまわりの奥行きだけを映す（手前と奥は切る）。
## 脚（太もも・すね・足）の頂点のうち、座面の真下（座面の幅と奥行きの中で、座面より低く床より高い所＝椅子の中）に入った数を書き出す。
## 座布団の席では、こたつ（天板と垂れた布団の外形の箱）の中へ入った体の頂点も数える

const Doll := preload("res://doll.gd")
var CELL := Vector2i(400, 400)   # 1 枚の大きさ（--cell=800 で大きく）
## 2 階のこたつの外形（lodge/dims.py の KOTATSU_W・KOTATSU_D、KOTATSU_FLARE、KOTATSU_TOP、PIT_DEPTH）
const KOTATSU := Vector2(2.1816, 1.2726)
const KOTATSU_FLARE := 0.10
const KOTATSU_TOP := 0.44
const KOTATSU_PIT_D := 0.40

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var _out := ""
var _dolls: Array = []
var _hosts: Array = []
var _seat_kinds: Array = []
var _seat_of := {}           # 席の種類 → 席の番号
var _side_of := {}           # 席の種類 → カメラを置く横（世界、水平）
var _step := -1
var _wait := 0
var _sheet: Image


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = args.get("out", "/tmp")
	if args.has("cell"):
		CELL = Vector2i(int(args.cell), int(args.cell))
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 40
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)
	root.add_child(cam)
	var kinds: Array = Doll.KINDS if args.get("kinds", "all") == "all" else Array(String(args.kinds).split(","))
	_seat_kinds = Array(String(args.get("seats", "chair,stool,bench,zabuton")).split(","))
	for k in kinds:
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


func _process(dt: float) -> bool:
	t += dt
	for d in _dolls:
		d.set("_next_breath", 100000)   # 白い息で脚が隠れないように
	var seats = main.get("seats")
	if seats == null or seats.seats.is_empty() or t < 1.0:
		return false
	if _step < 0:
		if main.settings:
			main.settings.set_open(false)
		for c in root.find_children("*", "CanvasLayer", true, false):
			c.visible = false
		# ゲームの人（あなた・仲間）は隠す
		for c in main.get_children():
			if c.get("doll") != null:
				c.visible = false
		for sk in _seat_kinds:
			_pick(seats, sk)
		_sheet = Image.create(CELL.x * _seat_kinds.size(), CELL.y * _dolls.size(), false, Image.FORMAT_RGBA8)
		_step = 0
		_place(seats)
		return false
	_wait += 1
	if _wait < 8:   # 座らせた姿と据えたカメラの絵が出るまで待つ
		return false
	_wait = 0
	_count(seats)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var sz := img.get_size()
	var sq := mini(sz.x, sz.y)
	img = img.get_region(Rect2i((sz.x - sq) / 2, (sz.y - sq) / 2, sq, sq))
	img.resize(CELL.x, CELL.y)
	var col := _step % _seat_kinds.size()
	var row := _step / _seat_kinds.size()
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
	_step += 1
	if _step >= _dolls.size() * _seat_kinds.size():
		var path := "%s/sit_side.png" % _out
		_sheet.save_png(path)
		print("撮った: ", path)
		return true
	_place(seats)
	return false


## いまの段の人形を、いまの段の席に座らせ、真横にカメラを据える
func _place(seats) -> void:
	var di := _step / _seat_kinds.size()
	var sk: String = _seat_kinds[_step % _seat_kinds.size()]
	for k in _hosts.size():
		_hosts[k].visible = k == di
	if not _seat_of.has(sk):
		return
	var st: Dictionary = seats.seat(_seat_of[sk])
	var d = _dolls[di]
	_hosts[di].global_position = st.pos
	d.facing = st.face
	d.set("_yaw", atan2(-st.face.x, -st.face.z))   # 向きを回しきってから撮る
	d.seat_drop = st.pos.y - st.floor
	if "seat_edge" in d:
		d.seat_edge = st.get("edge", 0.2)
	if "seat_soft" in d:
		d.seat_soft = st.kind == "zabuton" and not args.has("hard")
	var side: Vector3 = _side_of[sk]
	var h: float = d.height()
	var c: Vector3 = st.pos + Vector3.UP * (h * 0.3 - 0.2) + st.face * (0.1 + h * 0.1)
	var dist := 1.0 + h * 1.4
	cam.near = dist - 0.45   # 人形のまわりだけを映す（手前の隣の椅子・机・壁は切る）
	cam.far = dist + 1.0
	cam.look_at_from_position(c + side * dist, c)
	if args.has("quarter"):   # 斜め前の上から（膝に掛けた布団を見る）。手前は切らない
		cam.near = 0.05
		cam.far = 60.0
		cam.look_at_from_position(c + (side * 0.8 + st.face * 0.35 + Vector3.UP * 0.55).normalized() * dist * 0.85, c + st.face * 0.15 - Vector3.UP * 0.05)
	cam.current = true


## 種類 sk の席から、横（左右どちらか）に 1.3 m 以内でほかの席がない席を選ぶ。なければ並びのまんなか
func _pick(seats, sk: String) -> void:
	var list := []
	for i in seats.seats.size():
		if seats.seats[i].kind == sk:
			list.append(i)
	if list.is_empty():
		return
	if args.has("n"):
		var st: Dictionary = seats.seat(list[clampi(int(args.n), 0, list.size() - 1)])
		_seat_of[sk] = list[clampi(int(args.n), 0, list.size() - 1)]
		_side_of[sk] = st.face.cross(Vector3.UP)
		return
	for i in list:
		var st: Dictionary = seats.seat(i)
		for sd in [1.0, -1.0]:
			var side: Vector3 = st.face.cross(Vector3.UP) * sd
			var open := true
			for o in seats.seats:
				var to: Vector3 = o.pos - st.pos
				if o != st and absf(to.y) < 0.6 and to.dot(side) > 0.1 and to.length() < 1.3:
					open = false
					break
			if open:
				_seat_of[sk] = i
				_side_of[sk] = side
				_side_of[sk + "_open"] = true
				return
	_seat_of[sk] = list[list.size() / 2]
	_side_of[sk] = seats.seat(_seat_of[sk]).face.cross(Vector3.UP)


## いま撮る人形の脚の頂点のうち、座面の真下（椅子の中）に入った数
func _count(seats) -> void:
	var di := _step / _seat_kinds.size()
	var sk: String = _seat_kinds[_step % _seat_kinds.size()]
	if not _seat_of.has(sk):
		return
	var st: Dictionary = seats.seat(_seat_of[sk])
	var d = _dolls[di]
	var size: Vector2 = st.get("size", Vector2(0.4, 0.4))
	var edge: float = st.get("edge", 0.2)
	var side: Vector3 = st.face.cross(Vector3.UP)
	var n := 0
	var deep := 0.0
	var groups := _skinned(d)
	for b in groups:
		if not (b.begins_with("thigh") or b.begins_with("shin") or b.begins_with("foot")):
			continue
		for v in groups[b]:
			var rel: Vector3 = v - st.pos
			var along: float = rel.dot(st.face)
			if along < edge - size.y or along > edge or absf(rel.dot(side)) > size.x * 0.5:
				continue
			if v.y < st.pos.y - 0.015 and v.y > st.floor:
				n += 1
				deep = maxf(deep, st.pos.y - v.y)
	# 椅子の背もたれ: 座面の後ろの縁より後ろへ出た体の頂点（座面から 0.5 m の高さまで）
	var back := 0
	var back_deep := 0.0
	if sk == "chair":
		for b in groups:
			for v in groups[b]:
				var rel: Vector3 = v - st.pos
				var behind: float = (edge - size.y) - rel.dot(st.face)
				if behind > 0.01 and rel.y > 0.0 and rel.y < 0.5 and absf(rel.dot(side)) < size.x * 0.5:
					back += 1
					back_deep = maxf(back_deep, behind)
	# 座布団: こたつ（天板と、穴へ垂れた布団の外形。lodge/dims.py の KOTATSU_W・D・FLARE・TOP、穴の深さ）の中へ入った体の頂点
	var kot := ""
	if sk == "zabuton":
		var ks := _kotatsu_near(st.pos)
		if ks:
			var inside := 0
			var kdeep := 0.0
			var half := Vector3(KOTATSU.x * 0.5 + KOTATSU_FLARE, 0, KOTATSU.y * 0.5 + KOTATSU_FLARE)
			for b in groups:
				for v in groups[b]:
					var l: Vector3 = ks.global_transform.affine_inverse() * v
					var dx := half.x - absf(l.x)
					var dz := half.z - absf(l.z)
					var dy := minf(KOTATSU_TOP - l.y, l.y + KOTATSU_PIT_D)
					if dx > 0.0 and dz > 0.0 and dy > 0.0:
						inside += 1
						kdeep = maxf(kdeep, minf(minf(dx, dz), dy))
			kot = "、こたつ（布団・天板）へ入った体の頂点 %d（いちばん深く %.3f m）" % [inside, kdeep]
		# 座布団の上の、体のいちばん低い所（座面の上の面から。正なら浮いている、負なら沈んでいる）
		var low := INF
		var seat_low := INF   # 脚と腕を除いた体（お尻）
		for b in groups:
			var limb: bool = b.begins_with("thigh") or b.begins_with("shin") or b.begins_with("foot") \
				or b.begins_with("upper_arm") or b.begins_with("forearm") or b.begins_with("hand")
			for v in groups[b]:
				var rel: Vector3 = v - st.pos
				var along: float = rel.dot(st.face)
				if along > edge - size.y and along < edge and absf(rel.dot(side)) < size.x * 0.5:
					low = minf(low, rel.y)
					if not limb:
						seat_low = minf(seat_low, rel.y)
		kot += "、座布団の上の面から体のいちばん低い所 %+.3f m（お尻 %+.3f m）" % [low, seat_low]
		if args.has("bones"):
			var per := {}
			for b in groups:
				var m := INF
				for v in groups[b]:
					m = minf(m, (v - st.pos).y)
				per[b] = snappedf(m, 0.001)
			print(d.kind, " ", per)
	print("%s %s: 座面の真下に入った脚の頂点 %d（いちばん深く %.3f m）、背もたれへ出た体の頂点 %d（%.3f m）%s　座面の奥行き %.2f m（腰から縁まで %.2f m）" % [d.kind, sk, n, deep, back, back_deep, kot, size.y, edge])


## 座布団の席に近いこたつの置き場（ロッジの目印 slot_kotatsu_*）
func _kotatsu_near(p: Vector3) -> Node3D:
	var best: Node3D = null
	for n in root.find_children("slot_kotatsu_*", "Node3D", true, false):
		if best == null or (n as Node3D).global_position.distance_to(p) < best.global_position.distance_to(p):
			best = n
	return best


## 人形の形の頂点を、いまの骨の姿勢で曲げ、いちばん重い骨の名前ごとに世界の座標で返す（sit_hands_shots.gd と同じ）
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
