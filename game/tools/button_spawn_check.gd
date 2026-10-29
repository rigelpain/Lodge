extends SceneTree
## 雪に縫い留められたボタン（snow_buttons.gd）が、どこに降るかを数える（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/button_spawn_check.gd -- --no-player --bots=0 --no-sound [--count=200]
## 置き場所を続けて選び（_pick_spot。置かずに数えるだけ）、頂上からの距離と向き（+z がふもと・登り道の側）を数える。
## そのあと、西（-x）へ長く滑った跡を何本か入れて、跡に寄っていくか（滑った跡の重み）も同じように数える。

var args := {}
var main: Node3D
var t := 0.0
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _physics_process(dt: float) -> bool:
	t += dt
	if t < 1.0 or _done or main.snow_buttons == null:
		return false
	_done = true
	var sb: Node3D = main.snow_buttons
	sb.auto = false
	print("決めた形だけ:")
	_count(sb)
	# 西（-x）へ、頂上から長く滑った跡を 5 本
	for k in 5:
		for x in range(-6, -48, -2):
			var c: Vector2i = sb._cell(Vector3(x, 0, k * 1.5 - 3.0))
			sb._traffic[c] = sb._traffic.get(c, 0.0) + 0.9
	print("西へ長く滑った跡を 5 本入れたあと:")
	_count(sb)
	quit()
	return true


func _count(sb: Node3D) -> void:
	var n := int(args.get("count", "200"))
	var bins := {"ふもと（+z ±45°）": 0, "西（-x ±45°）": 0, "東（+x ±45°）": 0, "裏（-z ±45°）": 0}
	var rs := {"7〜15 m": 0, "15〜25 m": 0, "25〜35 m": 0, "35 m〜": 0}
	var fail := 0
	for i in n:
		var p: Vector3 = sb._pick_spot()
		if p == Vector3.INF:
			fail += 1
			continue
		var a := rad_to_deg(atan2(p.z, p.x))
		var key := "東（+x ±45°）"
		if a > 45 and a <= 135:
			key = "ふもと（+z ±45°）"
		elif a > 135 or a <= -135:
			key = "西（-x ±45°）"
		elif a > -135 and a <= -45:
			key = "裏（-z ±45°）"
		bins[key] += 1
		var r := Vector2(p.x, p.z).length()
		rs["7〜15 m" if r < 15 else ("15〜25 m" if r < 25 else ("25〜35 m" if r < 35 else "35 m〜"))] += 1
	print("  向き: ", bins)
	print("  頂上からの距離: ", rs)
	print("  置けなかった: ", fail)
