extends SceneTree
## 名札の形（sled_tags.gd の outline）が、いろいろな大きさで正しい多角形（三角形に分けられる）になるかを確かめる。
##   Godot --headless --path game -s res://tools/tag_outline_check.gd
## 形 7 種と、いままでの 13 枚の柄を、装備の画面の見本（28 × 18）から左下の札（262 × 146）まで、HUD の大きさ 0.5〜2.0 倍で。
## 崩れた形と大きさを出し、崩れが 0 なら 0 で終わる

const SledTags := preload("res://sled_tags.gd")


func _initialize() -> void:
	var sizes := [Vector2(28, 18), Vector2(40, 26), Vector2(62, 28), Vector2(120, 28), Vector2(240, 136), Vector2(262, 146), Vector2(172, 108)]
	var scales := [0.4, 0.5, 0.6, 0.67, 0.75, 0.9, 1.0, 1.25, 1.5, 2.0]
	var shapes: Array = SledTags.SHAPES.duplicate()
	var bad := 0
	var total := 0
	for shape in shapes:
		for sz in sizes:
			for k in scales:
				var r := Rect2(Vector2(10.3, 7.7), sz * k)
				var pts := SledTags.outline(r, shape)
				total += 1
				if Geometry2D.triangulate_polygon(pts).is_empty():
					bad += 1
					print("崩れ: %s 大きさ %s（%d 点）" % [shape, str(sz * k), pts.size()])
	print("形 %d 種 × 大きさ %d 通り: 崩れ %d / %d" % [shapes.size(), sizes.size() * scales.size(), bad, total])
	quit(1 if bad > 0 else 0)
