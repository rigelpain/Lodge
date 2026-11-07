extends SceneTree
## 間引いた人形（doll.gd の view_lod で見えない人形）にも、雪玉の当たり（body_hit）と胸の位置（chest_point）が正しく答えるかの確かめ。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/lod_hit_check.gd -- --no-sound
## あなたを遠くへ置いて仲間をみな見えなくし、仲間の 1 人の姿勢を空にする（着替えで新しい体になった直後と同じ）。
## そのまま当たりを聞いて、近くで見ているときと同じ答えになるかを比べる。SCRIPT ERROR が出ず、最後に「よい」と出れば通り。

var main: Node3D
var t := 0.0
var step := 0
var bot: Node3D
var far_hits := []
var far_chest := Vector3.ZERO


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _probe(d: Node3D) -> Array:
	# 体のまわりの点（足もとから頭の上まで、前後左右）で当たりを聞く
	var out := []
	var base: Vector3 = d.global_position
	for y in [0.2, 0.6, 1.0, 1.4, 1.8]:
		for off in [Vector3.ZERO, Vector3(0.25, 0, 0), Vector3(0, 0, 0.25), Vector3(0.5, 0, 0)]:
			out.append(d.body_hit(base + off + Vector3.UP * y, 0.08))
	return out


func _physics_process(_dt: float) -> bool:
	t += 1.0 / 60.0
	var p = main.get("player")
	if p == null:
		return false
	match step:
		0:
			if t > 3.0:
				for c in main.get_children():
					if c != p and c.get("doll") != null and c.get("roam"):
						bot = c
						break
				if bot == null:
					print("仲間が見つからない")
					quit(1)
					return true
				p.global_position = Vector3(0, main.height(0, 400) + 2.0, 400)   # 遠くへ
				step = 1
				t = 0.0
		1:
			if t > 1.0:
				var d: Node3D = bot.doll
				print("遠さの段: ", d.view_lod(d, d.global_position + Vector3.UP))
				d._g.clear()   # 着替えで新しい体になった直後と同じ（姿勢をまだ作っていない）
				d.set_physics_process(false)   # 比べるあいだ、姿勢が進まないように
				bot.set_physics_process(false)
				far_hits = _probe(d)
				far_chest = d.chest_point() - d.global_position
				# 同じ人形を、近くで見ているときと同じに姿勢を作り直して聞く
				d._pose_stale = true
				var near_hits := _probe(d)
				var near_chest: Vector3 = d.chest_point() - d.global_position
				var hits := far_hits.count(true)
				print("当たった点 遠い %d / 近い %d / 全部 %d、胸のずれ %.3f m" % [hits, near_hits.count(true), far_hits.size(), far_chest.distance_to(near_chest)])
				if far_hits == near_hits and hits > 0 and far_chest.distance_to(near_chest) < 0.01:
					print("よい")
				else:
					print("ずれている")
				quit()
				return true
	return false
