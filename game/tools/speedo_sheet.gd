extends SceneTree
## 速さの表示（speedo.gd のボビン）を、速さを変えて並べて PNG に書き出す（見比べ用。数字は出さない）。
##   Godot --path game --resolution 1500x620 -s res://tools/speedo_sheet.gd -- --out=絶対パス.png

const Speedo := preload("res://speedo.gd")
const Icons := preload("res://hud_icons.gd")

var args := {}
var _t := 0


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.86, 0.90, 0.96))
		var speeds := [2.5, 5.0, 8.5, 10.8, 14.0, 10.8]
		for j in speeds.size():
			var box := Rect2(20 + (j % 3) * 490, 30 + (j / 3) * 300, 460, 168)
			draw_rect(box, Color(1, 1, 1, 0.35))
			var s: float = speeds[j]
			var pop := 0.6 if j == 5 else 0.0   # 右下: 今日いちばんを超えた瞬間（跳ねて、糸が広がり、結び目）
			Speedo.draw(self, box, s, Speedo.level_of(s), 2.0 + s * 0.9, 30.0 + s * 3.0, Icons.RED, 9.0, pop,
				[30.0 + s * 3.0 - 4.0, 30.0 + s * 3.0 - 11.0] if j >= 4 else [], 1.0)


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
