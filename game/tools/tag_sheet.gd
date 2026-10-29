extends SceneTree
## 名札（sled_tags.gd）の一覧の絵（確かめ用）。
##   Godot --path game --resolution 1600x1000 -s res://tools/tag_sheet.gd -- --mode=parts --out=/path/parts.png
##   --mode=parts  部品ごとの見本。左が最初から使える部品、木のボタンの印の後ろが、あとで手に入る部品
##   --mode=combos 組み合わせの例 12 枚。大きく描いた名札の下に、小さく描いた同じ名札（米袋の札・見本の大きさ）
##   --mode=combo --i=3  組み合わせの例 1 枚を大きく（--out に保存）
##   --mode=lodge  ロッジの名札 13 枚と、畳んだソリの名札（広げた姿が回る窓）

const SledTags := preload("res://sled_tags.gd")
var args := {}
var t := 0.0

## 組み合わせの例（部品の名前で書く。描くときに番号へ）
const COMBOS := [
	{"shape": "stamp", "material": "paper", "paper": 0, "pattern": "none", "accent": 1, "stitch": "perf", "edge": 1, "string": 0,
		"deco": "none", "motif": "bird", "print": "ink", "layout": "overlap"},
	{"shape": "ticket", "material": "washi", "paper": 5, "pattern": "seigaiha", "accent": 4, "stitch": "running", "edge": 0, "string": 1,
		"deco": "tassel", "motif": "plum", "print": "applique", "layout": "corner"},
	{"shape": "leaf", "material": "felt", "paper": 7, "pattern": "none", "accent": 6, "stitch": "blanket", "edge": 2, "string": 6,
		"deco": "feather", "motif": "acorn", "print": "applique", "layout": "pair"},
	{"shape": "frame", "material": "leather", "paper": 11, "pattern": "none", "accent": 13, "stitch": "double", "edge": 8, "string": 10,
		"deco": "button", "motif": "mountain", "print": "cutout", "layout": "center"},
	{"shape": "hex", "material": "wood", "paper": 13, "pattern": "none", "accent": 11, "stitch": "none", "edge": 10, "string": 1,
		"deco": "bell", "motif": "pine", "print": "ink", "layout": "row"},
	{"shape": "round", "material": "cloth", "paper": 9, "pattern": "check", "accent": 0, "stitch": "zigzag", "edge": 2, "string": 2,
		"deco": "ribbon", "motif": "heart", "print": "applique", "layout": "center"},
	{"shape": "cloud", "material": "cloth", "paper": 14, "pattern": "patchwork", "accent": 6, "stitch": "cross", "edge": 1, "string": 3,
		"deco": "pompom", "motif": "star", "print": "embroidery", "layout": "scatter"},
	{"shape": "oval", "material": "felt", "paper": 12, "pattern": "none", "accent": 4, "stitch": "running", "edge": 9, "string": 9,
		"deco": "beads", "motif": "moon", "print": "window", "layout": "center"},
	{"shape": "flag", "material": "paper", "paper": 8, "pattern": "yagasuri", "accent": 0, "stitch": "none", "edge": 2, "string": 8,
		"deco": "clip", "motif": "snow", "print": "ink", "layout": "corner"},
	{"shape": "torn", "material": "washi", "paper": 0, "pattern": "asanoha", "accent": 15, "stitch": "none", "edge": 1, "string": 1,
		"deco": "none", "motif": "rabbit", "print": "ink", "layout": "pair"},
	{"shape": "scallop", "material": "paper", "paper": 10, "pattern": "kikko", "accent": 4, "stitch": "lace", "edge": 7, "string": 5,
		"deco": "feather", "motif": "snow", "print": "embroidery", "layout": "corner"},
	{"shape": "pinked", "material": "felt", "paper": 0, "pattern": "ichimatsu", "accent": 7, "stitch": "running", "edge": 6, "string": 4,
		"deco": "button", "motif": "mitten", "print": "applique", "layout": "corner"},
]


## 名前で書いた組み合わせを、部品の番号の辞書に
static func combo(i: int) -> Dictionary:
	var c: Dictionary = COMBOS[posmod(i, COMBOS.size())]
	var d := {}
	for part in SledTags.PARTS:
		var v = c.get(part, SledTags.DEFAULT[part])
		d[part] = SledTags.options(part).find(v) if v is String else int(v)
	return d


## 組み合わせの、あとで手に入る部品の数
static func later_count(d: Dictionary) -> int:
	var n := 0
	for part in d:
		if not SledTags.is_starter(part, int(d[part])):
			n += 1
	return n


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var bg := ColorRect.new()
	bg.color = Color(0.90, 0.92, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var sheet := Sheet.new()
	sheet.mode = args.get("mode", "parts")
	sheet.pick = int(args.get("i", "0"))
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)


func _process(dt: float) -> bool:
	t += dt
	if t > 1.5:
		root.get_texture().get_image().save_png(args.get("out", "/tmp/tags.png"))
		return true
	(root.get_child(1) as Control).queue_redraw()
	return false


class Sheet extends Control:
	var mode := "parts"
	var pick := 0

	func _draw() -> void:
		match mode:
			"combos": _combos()
			"combo": _one(pick)
			"lodge": _lodge()
			_: _parts()

	## 部品ごとの見本。最初から使える部品と、あとで手に入る部品の間に縦の破線、あとで手に入る部品には木のボタンの印
	func _parts() -> void:
		var Tags := preload("res://sled_tags.gd")
		var Icons := preload("res://hud_icons.gd")
		var base := {"shape": 0, "material": 0, "paper": 0, "pattern": 3, "accent": 4, "stitch": 0, "edge": 0, "string": 1, "deco": 2,
			"motif": 4, "print": 0, "layout": 0}   # 生成りの紙に藍の格子、赤い糸
		var s := 46.0
		var step := 58.0
		var y := 30.0
		draw_rect(Rect2(1000, 20, 580, 360), Color(0.98, 0.97, 0.94))
		Tags.draw_tag(self, Rect2(1060, 50, 420, 256), base, 1.0, true)
		for page in Tags.PAGES:
			for part in page:
				var n := Tags.part_count(part)
				var starter: int = Tags.STARTER[part]
				var per := 16 if size.x > 1400 else 14
				var x0 := 40.0
				var lim := 980.0 if y < 380.0 else size.x - 40.0
				per = int((lim - x0) / step)
				for i in n:
					var col := i % per
					var row := i / per
					var c := Vector2(x0 + col * step + (12.0 if i >= starter else 0.0) + s / 2.0, y + row * (s + 16.0) + s / 2.0)
					Tags.swatch(self, part, i, c, s, base, 1.0)
					if i >= starter:
						Icons.screen()
						var bc := c + Vector2(s * 0.42, s * 0.44)
						draw_circle(bc, 7.0, Icons.WOOD)
						draw_arc(bc, 5.0, 0.0, TAU, 14, Icons.WOOD.darkened(0.3), 1.2, true)
						draw_circle(bc + Vector2(-1.8, 0), 1.1, Color(0.25, 0.16, 0.10))
						draw_circle(bc + Vector2(1.8, 0), 1.1, Color(0.25, 0.16, 0.10))
					if i == starter and starter < n:
						Icons.screen()
						var lx := c.x - step / 2.0 - 6.0
						Icons.dashes(self, PackedVector2Array([Vector2(lx, c.y - s * 0.55), Vector2(lx, c.y + s * 0.55)]), Icons.RED, 2.0, 5.0, 3.0, 1.0)
				y += ceili(float(n) / per) * (s + 16.0) + 10.0
			y += 8.0

	## 組み合わせの例 12 枚（4 列 × 3 段）。それぞれ、大きい名札の下に、米袋の札の大きさ（104 × 28）と見本の大きさ（56 × 34）
	func _combos() -> void:
		var Tags := preload("res://sled_tags.gd")
		var Icons := preload("res://hud_icons.gd")
		var Sheet0 := preload("res://tools/tag_sheet.gd")
		var cw := (size.x - 60.0) / 4.0
		var ch := (size.y - 40.0) / 3.0
		for i in Sheet0.COMBOS.size():
			var d: Dictionary = Sheet0.combo(i)
			var o := Vector2(30.0 + (i % 4) * cw, 20.0 + (i / 4) * ch)
			draw_rect(Rect2(o + Vector2(4, 4), Vector2(cw - 8, ch - 8)), Color(0.98, 0.97, 0.94))
			var tw := cw - 70.0
			var th := tw * 0.6
			Tags.draw_tag(self, Rect2(o + Vector2(44, 22), Vector2(tw, th)), d, 1.0, true)
			var sy := o.y + 22.0 + th + 22.0
			Tags.draw_tag(self, Rect2(Vector2(o.x + 44, sy), Vector2(104, 28)), d, 1.0, false)
			Tags.draw_tag(self, Rect2(Vector2(o.x + 172, sy - 4), Vector2(56, 34)), d, 1.0, true)
			Icons.screen()
			for k in Sheet0.later_count(d):   # あとで手に入る部品の数だけ木のボタン
				var bc := Vector2(o.x + 252 + k * 15.0, sy + 14)
				draw_circle(bc, 6.0, Icons.WOOD)
				draw_circle(bc + Vector2(-1.6, 0), 1.0, Color(0.25, 0.16, 0.10))
				draw_circle(bc + Vector2(1.6, 0), 1.0, Color(0.25, 0.16, 0.10))

	## 組み合わせの例 1 枚: 大きな名札、吊るす絵の大きさ、左下の札の大きさ、米袋の札、包みの名札
	func _one(i: int) -> void:
		var Tags := preload("res://sled_tags.gd")
		var d: Dictionary = preload("res://tools/tag_sheet.gd").combo(i)
		Tags.draw_tag(self, Rect2(70, 40, 520, 320), d, 1.0, true)
		Tags.draw_tag(self, Rect2(680, 40, 168, 104), d, 1.0, true)
		Tags.draw_tag(self, Rect2(680, 180, 262, 146), d, 1.0, false)
		Tags.draw_tag(self, Rect2(70, 400, 104, 28), d, 1.0, false)
		Tags.draw_tag(self, Rect2(220, 390, 56, 34), d, 1.0, true)
		Tags.draw_on_packet(self, Vector2(400, 420), 120.0, d, Tags.turntable("mid", "navy"))

	func _lodge() -> void:
		var Tags := preload("res://sled_tags.gd")
		var cols := 5
		var w := 240.0
		var h := 136.0
		for i in Tags.count():
			var r := Rect2(40 + (i % cols) * (w + 30), 30 + (i / cols) * (h + 26), w, h)
			Tags.draw_tag(self, r, i, 1.0)
		var kinds := [["sack", "holly"], ["small", "mustard"], ["mid", "navy"], ["large", "plum"]]
		for k in kinds.size():
			var r := Rect2(40 + k * (w + 30), 30 + 3 * (h + 26) + 10, w, h)
			Tags.draw_tag(self, r, k + 1, 1.0, false)
			var tw := h * 0.8
			draw_texture_rect(Tags.turntable(kinds[k][0], kinds[k][1]), Rect2(r.end.x - tw - 16, r.position.y + (h - tw) / 2, tw, tw), false)
