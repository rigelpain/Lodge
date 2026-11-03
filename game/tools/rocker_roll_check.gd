extends SceneTree
## 揺り椅子の揺れを真横から撮り、弓が床から浮いたり床にめり込んだりしないか、人形が椅子といっしょに動くかを数える（確かめ用）。
##   Godot --path game --resolution 1000x1000 -s res://tools/rocker_roll_check.gd -- [--kind=kasa] [--out=DIR]
## 絵 rocker_roll.png: 上の段が前（弓の円の中心まわりに回すだけ）、下の段が後（弓が床を転がる）。左から、いちばん前・まんなか・いちばんうしろ。
##   赤い線が床、黄色の点が弓の床に触れている所（いちばん低い頂点）、水色の縦の線が揺れていないときの触れる所
## 数えるのは（下の段の形で、揺れの片側から片側まで 41 の角）:
##   弓のいちばん低い頂点と床の差（浮き・めり込み）、触れる所の前後のずれ、椅子に対しての人形のずれ（いっしょに動くか）、目の所の動き（一人称の視点）

const Doll := preload("res://doll.gd")
const Nook := preload("res://hearth_nook.gd")
const CELL := 600
const SWEEP := 41

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var nook: Node3D
var st: Dictionary
var chair: Node3D
var base: Transform3D
var host: Node3D
var doll
var _step := -1
var _wait := 0
var _sheet: Image
var _rest_rel: Transform3D
var _rest_contact := Vector3.ZERO
var _rows := []               # 数えた結果: [角, 床との差, 触れる所の前後, 人形のずれ, 目の所]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0
	root.add_child(cam)
	host = Node3D.new()
	root.add_child(host)
	doll = Doll.new()
	doll.kind = args.get("kind", "kasa")
	host.add_child(doll)
	doll.act = Doll.Act.SIT
	doll.sit_stage = 2


func _out() -> String:
	return args.get("out", "/tmp")


## 段: 0〜5 は絵（上の段 0〜2 が前、下の段 3〜5 が後）、6〜 は数える（後の形で SWEEP の角）
func _angle(i: int) -> float:
	var amp: float = st.rock_amp
	if i < 6:
		return [-amp, 0.0, amp][i % 3]
	return lerpf(-amp, amp, float(i - 6) / float(SWEEP - 1))


func _process(_dt: float) -> bool:
	t += _dt
	doll.set("_next_breath", 100000)
	var seats = main.get("seats")
	if seats == null or seats.seats.is_empty() or t < 2.0:
		return false
	if _step < 0:
		_setup(seats)
		_step = 0
		_pose()
		return false
	_wait += 1
	if _wait < 6:   # 人形と椅子が同じ角になるまで（椅子は 12 コマ／秒で動く）
		return false
	_wait = 0
	if _step < 6:
		_shoot()
	else:
		_measure()
	_step += 1
	if _step >= 6 + SWEEP:
		_report()
		return true
	_pose()
	return false


func _setup(seats) -> void:
	if main.settings:
		main.settings.set_open(false)
	for c in root.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	for c in main.get_children():
		if c.get("doll") != null:
			c.visible = false
			c.global_position += Vector3(0, -50, 0)   # あなたと仲間は居場所の外へ
	nook = main.find_child("HearthNook", true, false)
	for i in seats.seats.size():
		if seats.seats[i].kind == "rocker":
			st = seats.seat(i)
			break
	for r in nook._rockers:   # 席の目印にいちばん近い揺り椅子
		if (r[2] as Node3D).global_position.distance_to(st.pos) < 0.05:
			chair = r[0]
			base = r[1]
	chair.transform = base
	_rest_contact = _lowest()
	host.global_position = st.pos
	doll.facing = st.face
	doll.set("_yaw", atan2(-st.face.x, -st.face.z))
	doll.seat_drop = st.pos.y - st.floor
	doll.seat_edge = st.edge
	doll.rock_axis = st.rock_axis
	doll.rock_at = st.rock_at
	var side: Vector3 = st.rock_axis
	var c: Vector3 = chair.global_position + Vector3.UP * 0.85
	cam.look_at_from_position(c + side * 4.0, c)
	cam.near = 4.0 - 0.6   # 椅子のまわりだけ（手前と奥の家具・壁は切る）
	cam.far = 4.0 + 0.6
	cam.current = true
	_sheet = Image.create(CELL * 3, CELL * 2, false, Image.FORMAT_RGBA8)


func _old() -> bool:
	return _step >= 0 and _step < 3


## いまの段の角に、人形と椅子を傾ける。前の形は、椅子を弓の円の中心まわりに回すだけ（hearth_nook.gd の動きを止めて、ここで置く）
func _pose() -> void:
	var a := _angle(_step)
	doll.rock = a
	doll.rock_roll = 0.0 if _old() else float(st.rock_roll)
	nook.set_process(not _old())
	for r in nook._rockers:   # 前の形から戻すとき、角が同じでも置き直す
		r[3] = INF
	if _old():
		var r := Basis(Vector3.RIGHT, a)
		chair.transform = base * Transform3D(r, Nook.ROCK_PIVOT - r * Nook.ROCK_PIVOT)


## 椅子のいちばん低い頂点（世界）
func _lowest() -> Vector3:
	var low := Vector3(0, INF, 0)
	for m in chair.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := mi.global_transform
		for si in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var w := xf * v
				if w.y < low.y:
					low = w
	return low


func _shoot() -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var sz := img.get_size()
	# 床の線（赤）、揺れていないときの触れる所（水色の縦の線）、いまの触れる所（黄色の点）
	var fy := int(cam.unproject_position(Vector3(chair.global_position.x, st.floor, chair.global_position.z)).y)
	img.fill_rect(Rect2i(0, fy, sz.x, 2), Color(0.9, 0.1, 0.1))
	var low := _lowest()
	var lp := cam.unproject_position(low)
	var rp := cam.unproject_position(_rest_contact)
	img.fill_rect(Rect2i(int(rp.x) - 1, fy - 40, 2, 80), Color(0.2, 0.8, 1.0))
	img.fill_rect(Rect2i(int(lp.x) - 6, int(lp.y) - 6, 12, 12), Color(1.0, 0.85, 0.1))
	var sq := mini(sz.x, sz.y)
	img = img.get_region(Rect2i((sz.x - sq) / 2, (sz.y - sq) / 2, sq, sq))
	img.resize(CELL, CELL)
	_sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i((_step % 3) * CELL, (_step / 3) * CELL))
	print("%s %+.3f rad: 弓のいちばん低い所と床の差 %+.4f m" % ["前" if _old() else "後", doll.rock, _lowest().y - st.floor])


func _measure() -> void:
	var rel: Transform3D = chair.global_transform.affine_inverse() * doll.global_transform
	var low := _lowest()
	var fw: Vector3 = st.face
	var eye: Vector3 = doll.global_transform * doll.eye_point(true)
	var c: Vector3 = chair.global_transform * Nook.ROCK_PIVOT   # 弓の円の中心（椅子といっしょに動く点）
	_rows.append([doll.rock, low.y - st.floor, (low - _rest_contact).dot(fw), rel, eye, c])


func _report() -> void:
	var path := "%s/rocker_roll.png" % _out()
	_sheet.save_png(path)
	print("撮った: ", path)
	var mid: Array = _rows[SWEEP / 2]
	var gap_min := INF
	var gap_max := -INF
	var drift := 0.0
	var turn := 0.0
	var eye_min := Vector3.INF
	var eye_max := -Vector3.INF
	for r in _rows:
		gap_min = minf(gap_min, r[1])
		gap_max = maxf(gap_max, r[1])
		var rel: Transform3D = r[3]
		drift = maxf(drift, rel.origin.distance_to((mid[3] as Transform3D).origin))
		turn = maxf(turn, rel.basis.get_rotation_quaternion().angle_to((mid[3] as Transform3D).basis.get_rotation_quaternion()))
		eye_min = eye_min.min(r[4])
		eye_max = eye_max.max(r[4])
	print("弓のいちばん低い所と床の差: %+.4f 〜 %+.4f m（正は浮き、負はめり込み）" % [gap_min, gap_max])
	print("触れる所の前後（揺れていないときから。前が正）: いちばん前へ揺れたとき %+.3f m、まんなか %+.3f m、いちばんうしろ %+.3f m" % [_rows[0][2], mid[2], _rows[-1][2]])
	var c0: Vector3 = mid[5]
	print("弓の円の中心の床からの高さ: いちばん前 %.4f m、まんなか %.4f m、いちばんうしろ %.4f m（変わらなければ、弓は床に触れたまま転がる）" % [_rows[0][5].y - st.floor, c0.y - st.floor, _rows[-1][5].y - st.floor])
	print("弓の床に触れる所（中心の真下）の前後: いちばん前 %+.3f m、いちばんうしろ %+.3f m（転がるなら 半径 × 角 = %+.3f / %+.3f m）" % [
		(_rows[0][5] - c0).dot(st.face), (_rows[-1][5] - c0).dot(st.face), float(st.rock_roll) * -_rows[0][0], float(st.rock_roll) * -_rows[-1][0]])
	print("椅子に対しての人形のずれ: 所 %.4f m、向き %.3f°" % [drift, rad_to_deg(turn)])
	print("目の所の動き（%s）: 前後 %.3f m、上下 %.3f m" % [doll.kind, absf((_rows[-1][4] - _rows[0][4]).dot(st.face)), eye_max.y - eye_min.y])
