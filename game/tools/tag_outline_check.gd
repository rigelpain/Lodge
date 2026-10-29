extends SceneTree
## 名札の形（sled_tags.gd の outline）が、いろいろな大きさで正しい多角形（三角形に分けられ、自分と交わらない）になるかを確かめる。
##   Godot --headless --path game -s res://tools/tag_outline_check.gd
## 形のすべてを、装備の画面の見本（28 × 18）から左下の札（262 × 146）まで、HUD の大きさ 0.4〜2.0 倍で。
## あわせて、模様・素材・縁の作りを全部組み合わせて計算し、塗れない欠片が出ないかも見る。
## 崩れた形と大きさを出し、崩れが 0 なら 0 で終わる

const SledTags := preload("res://sled_tags.gd")


func _initialize() -> void:
	var sizes := [Vector2(28, 18), Vector2(40, 26), Vector2(62, 28), Vector2(80, 28), Vector2(120, 28), Vector2(168, 104),
		Vector2(210, 128), Vector2(240, 136), Vector2(262, 146), Vector2(172, 108)]
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
				var why := ""
				if pts.size() < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
					why = "三角形に分けられない"
				elif _crosses(pts):
					why = "自分と交わる"
				elif not r.grow(0.01).encloses(_bounds(pts)):
					why = "枠からはみ出す"
				if why != "":
					bad += 1
					print("崩れ: %s 大きさ %s（%d 点）: %s" % [shape, str(sz * k), pts.size(), why])
	print("形 %d 種 × 大きさ %d 通り: 崩れ %d / %d" % [shapes.size(), sizes.size() * scales.size(), bad, total])
	# 模様・素材・縁を全部の形と、小さい・大きい名札で計算する（塗れない欠片は _clip_fill が捨てる。落ちないことを見る）
	var combos := 0
	for shape in shapes:
		for sz in [Vector2(104, 28), Vector2(168, 104)]:
			for pattern in SledTags.PATTERNS:
				for material in SledTags.MATERIALS:
					for stitch in SledTags.STITCHES:
						var g: Dictionary = SledTags._geometry(sz, {"shape": shape, "pattern": pattern, "material": material, "stitch": stitch})
						combos += 1
						for f in g.fill:
							if Geometry2D.triangulate_polygon(f[0]).is_empty():
								bad += 1
								print("塗れない模様: %s %s %s" % [shape, pattern, str(sz)])
	print("模様・素材・縁の組み合わせ %d 通りを計算" % combos)
	quit(1 if bad > 0 else 0)


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## 隣り合わない辺どうしが交わるか
static func _crosses(pts: PackedVector2Array) -> bool:
	var n := pts.size()
	for i in n:
		var a0 := pts[i]
		var a1 := pts[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var b0 := pts[j]
			var b1 := pts[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
				return true
	return false
