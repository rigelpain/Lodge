extends SceneTree
## 速さの表示（speedo.gd のボビン）を、速さを変えて並べて PNG に書き出す（見比べ用。数字は出さない）。
##   Godot --path game --resolution 1000x480 -s res://tools/speedo_sheet.gd -- --out=絶対パス.png

const Speedo := preload("res://speedo.gd")
const Icons := preload("res://hud_icons.gd")

var args := {}
var _t := 0


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.86, 0.90, 0.96))
		var speeds := [2.5, 5.0, 8.5, 10.8, 14.0, 10.8]
		for j in speeds.size():
			var box := Rect2(30 + j * 160, 20, 110, 440)
			draw_rect(box.grow(10), Color(1, 1, 1, 0.35))
			var s: float = speeds[j]
			var k := Speedo.level_of(s)
			var pop := 0.6 if j == 5 else 0.0   # 右端: 今日いちばんを超えた瞬間（跳ねて、糸が広がり、結び目）
			var g := Speedo.layout(box, pop)
			var dist := 30.0 + s * 3.0
			Speedo.draw_stitches(self, g, k, 2.0 + s * 0.9, dist, Icons.RED, [dist - 3.0, dist - 9.0] if j >= 4 else [], 1.0)
			Speedo.draw_spool(self, g, k, 2.0 + s * 0.9, Icons.RED, 9.0, pop, 1.0)


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
