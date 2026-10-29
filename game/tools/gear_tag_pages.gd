extends SceneTree
## 装備の画面（I）の名札のページを、1 ページずつ撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/gear_tag_pages.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 名札は保存しない。ページの数は sled_tags.gd の PAGES

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/gear"))
	_run.call_deferred()


## 窓から目が離れると設定の画面が開くので、撮る前に閉じる
func _close_settings() -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false


func _run() -> void:
	await create_timer(2.5).timeout
	var ui = main.craft_ui
	_close_settings()
	ui.open_gear()
	for k in preload("res://sled_tags.gd").PAGES.size():
		ui.tag_page = k
		_close_settings()
		if not ui.gear_open:
			ui.open_gear()
		await create_timer(0.3).timeout
		await process_frame
		root.get_texture().get_image().save_png(String(args.get("dir", "/tmp/gear")).path_join("page%d.png" % (k + 1)))
		print("撮った: page%d" % (k + 1))
	ui.close_gear()
	await create_timer(1.0).timeout   # 閉じたあと、左下の名札だけ（方位磁針なし）
	_close_settings()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.get("dir", "/tmp/gear")).path_join("hud.png"))
	quit()
