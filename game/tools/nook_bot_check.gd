extends SceneTree
## ロッジでくつろぐ仲間（--lodge-bots）が、暖炉のまわりの席（ソファ・揺り椅子・ビーズクッション）へ歩いて座れるか（確かめ用）。
##   Godot --path game --headless -s res://tools/nook_bot_check.gd -- --spawn=inside --lodge-bots=6 [--secs=90]
## 10 秒ごとに、座っている仲間の数と席の種類を書き出す

var main: Node3D
var t := 0.0
var _next := 10.0
var _seen := {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	t += dt
	if t < _next:
		return false
	_next += 10.0
	var seats = main.seats
	var kinds := {}
	for who in seats.seat_of:
		var k: String = seats.seat(seats.seat_of[who]).kind
		kinds[k] = kinds.get(k, 0) + 1
		_seen[k] = true
	print("%3.0f 秒: 座っている %d 人 %s" % [t, seats.seat_of.size(), kinds])
	if OS.get_cmdline_user_args().has("--why"):
		for c in main.get_children():
			if c.get("_goal") != null and c.get("seat_i") != null:
				var g: int = c._goal
				print("  仲間 %s: 席 %d 行き先 %d %s 離れ %.2f 詰まり %.1f" % [c.name, c.seat_i, g, seats.seat(g).kind if g >= 0 else "-",
					(seats.seat(g).stand - c.global_position).length() if g >= 0 else -1.0, c._stuck])
	var secs := 90.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.split("=")[1])
	if t > secs:
		print("座った席の種類: ", _seen.keys())
		return true
	return false
