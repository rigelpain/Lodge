extends SceneTree
## ソリの名札（sled_tags.gd）の柄を並べて 1 枚の絵にする（確かめ用）。下の段は畳んだソリの名札（広げた姿が回る窓）。
##   Godot --path game --resolution 1400x900 -s res://tools/tag_sheet.gd -- --out=/path/tags.png

const SledTags := preload("res://sled_tags.gd")
var args := {}
var t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var bg := ColorRect.new()
	bg.color = Color(0.90, 0.92, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var sheet := Sheet.new()
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
	func _draw() -> void:
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
