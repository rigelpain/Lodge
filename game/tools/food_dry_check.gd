extends SceneTree
## ご飯で湿り気（damp.gd）が戻る様子を確かめる（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/food_dry_check.gd -- --no-sound
## あなたを外（ふもと）に置き、値を入れてから料理を 3 口（1 秒おき）食べ、2 秒ごとに値・これから戻る量・段・バッジを出す。
## 料理の種類（汁物・飲み物・揚げ物・焼き物・おにぎり）と、汁物のほかはふつうの上の端（150）で止まり、汁物はブーストまで戻ること

var main: Node3D
var p: Node3D


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(sec: float) -> void:
	for i in int(sec * Engine.physics_ticks_per_second):
		await physics_frame


func _row(t: float) -> String:
	var dm = main.damp
	var bs := ""
	for b in main.badges.of(p.id):
		bs += "%s%s " % [b.icon, "↑" if b.dir > 0 else "↓".repeat(b.level)]
	return "| %.0f 秒 | %.1f | %.1f | %s | %s |" % [t, dm.value(p.id), dm.coming(p.id), dm.STAGES[dm.stage_of(dm.value(p.id))][1], bs if bs != "" else "なし"]


func _try(dish: String, start: float, secs: float) -> void:
	main.damp.put(p.id, start)
	main.damp.pending.erase(p.id)
	print("\n%s（%s 戻す）: 始め %.0f" % [dish, main.damp.Food.dry(dish), start])
	print("| 時 | 値 | これから | 段 | バッジ |\n|---|---|---|---|---|")
	var t := 0.0
	for i in 3:
		main.damp.eat(p.id, dish)
		await _wait(1.0)
		t += 1.0
	print(_row(t))
	while t < secs:
		await _wait(2.0)
		t += 2.0
		print(_row(t))


func _run() -> void:
	await _wait(0.5)
	p = main.player
	if main.settings:
		main.settings.set_open(false)
	p.global_position = Vector3(6.0, main.height(6.0, 30.0) + 0.1, 30.0)
	p.velocity = Vector3.ZERO
	await _wait(0.5)
	await _try("ramen", 20.0, 17.0)
	await _try("cocoa", 20.0, 13.0)
	await _try("korokke", 20.0, 9.0)
	await _try("yakiimo", 20.0, 9.0)
	await _try("onigiri", 20.0, 7.0)
	await _try("cocoa", 120.0, 9.0)   # 150 で止まる
	await _try("ramen", 120.0, 17.0)  # 汁物はブーストへ
	await _try("ramen", 170.0, 9.0)   # ブーストの中でも 200 まで
	await _try("cocoa", 170.0, 3.0)   # 汁物でなければ、ブーストの中では戻らない
	quit()
