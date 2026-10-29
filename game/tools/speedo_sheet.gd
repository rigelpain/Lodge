extends SceneTree
## 速さの表示の案（speedo.gd の bobbin・tape・gauge）を、遅い・速い・とても速いで並べて PNG に書き出す（見比べ用）。
##   Godot --path game --resolution 1500x700 -s res://tools/speedo_sheet.gd -- --out=../design/hud/speedo-ideas.png

const Speedo := preload("res://speedo.gd")

var args := {}
var _t := 0


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.86, 0.90, 0.96))
		var styles := ["bobbin", "tape", "gauge"]
		var speeds := [3.0, 8.5, 13.0]
		for i in styles.size():
			for j in speeds.size():
				var box := Rect2(20 + j * 490, 30 + i * 220, 460, 190)
				draw_rect(box, Color(1, 1, 1, 0.35))
				Speedo.draw(self, styles[i], box, speeds[j], Speedo.level_of(speeds[j]), 7.0 + speeds[j] * 2.0, 9.0, 0.0, 1.0)


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
		root.get_texture().get_image().save_png(args.get("out", "/tmp/speedo.png"))
		return true
	return false
