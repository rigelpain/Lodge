extends SceneTree
## 画面の表示の絵（hud_icons.gd）を一覧にして PNG に書き出す（確かめ用）。
##   Godot --path game --resolution 1200x900 -s res://tools/hud_sheet.gd -- --out=../design/hud/icons.png

const Icons := preload("res://hud_icons.gd")

var args := {}
var _t := 0


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.80, 0.86, 0.94))
		var cell := 120.0
		var cols := int(size.x / cell)
		var names: Array = Icons.NAMES + ["person", "person_sit"]
		for i in names.size():
			var c := Vector2((i % cols) * cell + cell / 2.0, (i / cols) * cell + cell / 2.0 - 6.0)
			Icons.icon(self, names[i], c, 84.0)
			draw_string(ThemeDB.fallback_font, c + Vector2(-50, 52), names[i], HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Color(0.2, 0.25, 0.4, 0.7))
		var y := (names.size() / cols + 1) * cell + 20.0
		var x := 40.0
		for k in ["F", "E", "W", "A", "S", "D", "R", "Q", "G", "T", "B", "1", "Tab", "Esc", "Shift", "Space"]:
			var w := Icons.keycap(self, k, Vector2(x + 30, y), 44.0)
			x += w + 14.0
		y += 70.0
		x = 30.0
		for b in [[["F"], "grab"], [["E"], "ride"], [["W"], "push"], [["A", "D"], "lean_r"], [["mouse_r"], "point"], [["T"], "needle"]]:
			var w := Icons.badge_w(b[0], 64.0)
			Icons.badge(self, b[0], b[1], Vector2(x + w / 2.0, y + 20), 64.0)
			x += w + 16.0
		Icons.tag(self, Rect2(40, y + 70, 230, 120))


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var s := Sheet.new()
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(s)


func _process(_dt: float) -> bool:
	_t += 1
	if _t == 4:
		var img := root.get_texture().get_image()
		img.save_png(args.get("out", "/tmp/hud_icons.png"))
		print("保存: ", args.get("out", "/tmp/hud_icons.png"))
		return true
	return false
