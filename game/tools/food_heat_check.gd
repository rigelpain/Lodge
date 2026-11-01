extends SceneTree
## ご飯で熱（damp.gd）が上がる様子を確かめる（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/food_heat_check.gd -- --no-sound
## あなたを外（ふもと）に置き、水と熱を入れてから料理を 3 口（1 秒おき）食べ、2 秒ごとに水・熱・これから上がる量・点・段・バッジを出す。
## 料理の種類（汁物・飲み物・揚げ物・焼き物・おにぎり）と、汁物のほかは 60 で止まり、汁物は 100 まで上がること

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
	return "| %.0f 秒 | %.1f | %.1f | %.1f | %.2f | %s | %s |" % [t, dm.water_of(p.id), dm.heat_of(p.id), dm.coming(p.id), dm.score(p.id),
		dm.STAGES[dm.stage_of(dm.score(p.id))][1], bs if bs != "" else "なし"]


func _try(dish: String, w: float, h: float, secs: float) -> void:
	main.damp.put(p.id, w, h)
	main.damp.pending.erase(p.id)
	print("\n%s（熱 %s 上げる）: 水 %.0f 熱 %.0f から" % [dish, main.damp.Food.heat(dish), w, h])
	print("| 時 | 水 | 熱 | これから | 点 | 段 | バッジ |\n|---|---|---|---|---|---|---|")
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
	await _try("ramen", 60.0, 40.0, 17.0)
	await _try("cocoa", 60.0, 40.0, 11.0)
	await _try("korokke", 60.0, 40.0, 9.0)
	await _try("yakiimo", 60.0, 40.0, 7.0)
	await _try("onigiri", 60.0, 40.0, 5.0)
	await _try("cocoa", 0.0, 50.0, 7.0)   # 60 で止まる（まだバフにならない）
	await _try("ramen", 0.0, 50.0, 17.0)  # 汁物はバフへ
	await _try("ramen", 0.0, 90.0, 7.0)   # 100 まで
	quit()
