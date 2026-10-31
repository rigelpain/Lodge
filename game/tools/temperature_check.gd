extends SceneTree
## 気温と白い息の見え方・体のふるえ・暖かさの落ち着きを、場所と時刻ごとに出す（確かめ用）。
##   Godot --headless --path game -s res://tools/temperature_check.gd
## 場所: ふもと（はじまりの所）・丘の頂上・風除室・ロッジの中（食堂のまんなか）・暖炉のそば。時刻: 14 時・18 時・22 時・4 時

const Audio := preload("res://audio.gd")
const Temperature := preload("res://temperature.gd")

var main: Node3D


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await physics_frame
	var temp := root.get_node("Temperature")
	var dc := root.get_node("DayCycle")
	var lodge: Node3D = main.get_node("Lodge")
	var start: Vector3 = main.START + Vector3(0, main.height(main.START.x, main.START.z) + 1.2, 0)
	var spots := [
		["ふもと", start],
		["頂上", Vector3(0, main.height(0, 0) + 1.2, 0)],
		["風除室", lodge.to_global(Audio.VEST + Vector3(0, 1.2, 0))],
		["ロッジの中", lodge.to_global(Vector3(0, 1.2, 4.0))],
		["暖炉のそば", lodge.to_global(Temperature.FIRE_FALLBACK + Vector3(1.2, 0.2, 1.2))],
	]
	var head := "場所          "
	for h in [14.0, 18.0, 22.0, 4.0]:
		head += "  %2d 時（°C / 息 / ふるえ / 落ち着き）" % int(h)
	print(head)
	for sp in spots:
		var line := "%-8s %5.1f m" % [sp[0], (sp[1] as Vector3).y]
		for h in [14.0, 18.0, 22.0, 4.0]:
			dc.hour = h
			var t: float = temp.at(sp[1])
			line += "   %6.1f / %4.2f / %4.2f / %4.2f" % [t, Temperature.breath_of(t), Temperature.shiver_of(t), Temperature.calm_of(t)]
		print(line)
	quit()
