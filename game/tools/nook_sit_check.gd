extends SceneTree
## あなた（プレイヤー）が暖炉のまわりの席に座れるか（確かめ用）。種類ごとに 1 つ、立つ所へ置いて席を向き、
## F と同じ sit_down を呼ぶ。座りきったら、揺れ（人形の rock）と、ビーズクッションのつぶれを 2 秒見て、立つ
##   Godot --path game --headless -s res://tools/nook_sit_check.gd -- --spawn=inside

var main: Node3D
var t := 0.0
var _kinds := ["sofa", "rocker", "beanbag"]
var _step := -1
var _t0 := 0.0
var _rocks := []


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
		p.stand_up()
		return false
	if _step < 0 or t - _t0 > 5.0:
		_step += 1
		_rocks = []
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
	return false
