extends SceneTree
## 体の調子のバッジ（badges.gd）の見本を 1 枚に描く（確かめ用）。
##   Godot --path game --resolution 1500x620 -s res://tools/badge_sheet.gd -- --out=/path/badges.png
## 押す力と速さの、下降 2 本・下降 1 本・上昇

const Badges := preload("res://badges.gd")

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var bg := ColorRect.new()
	bg.color = Color(0.90, 0.91, 0.94)
	bg.size = Vector2(1500, 620)
	root.add_child(bg)
	var c := Control.new()
	c.size = Vector2(1500, 620)
	c.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	root.add_child(c)
	c.draw.connect(func(): _draw(c))
	_shoot.call_deferred()


func _draw(ci: Control) -> void:
	var sets := [[-1, 2], [-1, 1], [1, 1]]
	var x := 110.0
	for st in sets:
		for stat in ["push", "speed"]:
			Badges.draw_badge(ci, {"key": stat, "dir": st[0], "level": st[1], "icon": stat}, Vector2(x, 105), 120.0)
			x += 150.0
		x += 70.0


func _shoot() -> void:
	for i in 10:
		await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(args.get("out", "/tmp/badges.png"))
	quit()
