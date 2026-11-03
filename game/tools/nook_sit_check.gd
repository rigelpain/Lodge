extends SceneTree
## あなた（プレイヤー）が暖炉のまわりの席に座れるか（確かめ用）。種類ごとに 1 つ、立つ所へ置いて席を向き、
## F と同じ sit_down を呼ぶ。座りきったら、揺れ（人形の rock）と、ビーズクッションのつぶれを 2 秒見て、立つ。
## 揺り椅子では、一人称の視点（カメラ）がどれだけ動くかも書く（前後・上下の幅、1 フレームのいちばん大きな動き、向きが傾かないか）
##   Godot --path game --headless -s res://tools/nook_sit_check.gd -- --spawn=inside

var main: Node3D
var t := 0.0
var _kinds := ["sofa", "rocker", "beanbag"]
var _step := -1
var _t0 := 0.0
var _rocks := []
var _eyes := []
var _tilt := 0.0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	t += dt
	if t < 3.0:
		return false
	var p = main.player
	var seats = main.seats
	if _step >= 0 and t - _t0 > 4.0 and t - _t0 - dt <= 4.0:
		var st: Dictionary = seats.seat(p.seat_i) if p.seat_i >= 0 else {}
		var sq := ""
		if _kinds[_step] == "beanbag":
			var nook = main.find_child("HearthNook", true, false)
			sq = " 袋のつぶれ %.2f" % nook._beans.map(func(b): return b[3]).max()
		print("%s: 座った %s 人形の傾き %.3f 〜 %.3f rad%s" % [_kinds[_step], p.seat_i >= 0 and st.kind == _kinds[_step], _rocks.min(), _rocks.max(), sq])
		if _kinds[_step] == "rocker" and _eyes.size() > 1:
			var fw: Vector3 = st.face
			var lo := INF
			var hi := -INF
			var ylo := INF
			var yhi := -INF
			var jump := 0.0
			for i in _eyes.size():
				lo = minf(lo, _eyes[i].dot(fw))
				hi = maxf(hi, _eyes[i].dot(fw))
				ylo = minf(ylo, _eyes[i].y)
				yhi = maxf(yhi, _eyes[i].y)
				if i > 0:
					jump = maxf(jump, _eyes[i].distance_to(_eyes[i - 1]))
			print("  一人称の視点: 前後 %.3f m、上下 %.3f m、1 フレームのいちばん大きな動き %.4f m、視点の傾き（横倒し）いちばん大きい %.2f°" % [hi - lo, yhi - ylo, jump, rad_to_deg(_tilt)])
		p.stand_up()
		return false
	if _step >= 0 and t - _t0 > 4.9 and t - _t0 - dt <= 4.9:
		print("  立った: ", p.seat_i < 0, " 動き ", p.mode)
	if _step < 0 or t - _t0 > 5.0:
		_step += 1
		_rocks = []
		_eyes = []
		_tilt = 0.0
		if _step >= _kinds.size():
			return true
		for i in seats.seats.size():
			if seats.seats[i].kind == _kinds[_step] and not seats.taken.has(i):
				var st: Dictionary = seats.seats[i]
				p.global_position = st.stand + Vector3.UP * 0.05
				p.rotation.y = atan2((st.pos - st.stand).x, (st.pos - st.stand).z) + PI
				p.cam.global_rotation = Vector3(-0.3, p.rotation.y, 0)
				break
		_t0 = t
		return false
	if t - _t0 > 1.0 and p.seat_i < 0 and t - _t0 < 1.1:
		print("  sit_down: ", p.sit_down())
	if p.seat_i >= 0:
		_rocks.append(p.doll.rock)
		if _kinds[_step] == "rocker" and t - _t0 > 2.0 and t - _t0 < 3.9:   # 座りきって揺れているあいだの視点
			_eyes.append(p.cam.global_position)
			_tilt = maxf(_tilt, absf(p.cam.global_rotation.z))
		if _kinds[_step] == "beanbag" and t - _t0 > 2.5 and t - _t0 - dt <= 2.5:   # 座ったまま見回す: 体が見ている向きへついてくるか
			p.rotate_y(PI * 0.75)
		if t - _t0 > 3.9 and t - _t0 - dt <= 3.9:
			var view: Vector3 = -p.global_basis.z
			var body: Vector3 = -p.doll.global_basis.z
			view.y = 0
			body.y = 0
			print("  %s: 見ている向きと体の向きの差 %.1f°（向きについてくる %s）" % [_kinds[_step], rad_to_deg(view.normalized().angle_to(body.normalized())), p.doll.rock_turns])
	return false
