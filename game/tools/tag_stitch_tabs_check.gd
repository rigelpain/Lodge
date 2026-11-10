extends SceneTree
## 持ち物の画面（I）の、名札の柄のタブとステッチのタブを分けた確かめ（2026-11-10 代表「インベントリでタグの柄設定用のタブとステッチ選択のタブは分けてほしい」）。
##   Godot --path game --resolution 1280x720 -s res://tools/tag_stitch_tabs_check.gd -- --dir=/path --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   --before を付けると、分ける前の画面の絵だけ撮る（数字は見ない）
## 絵: gear.png（装備。左に名札の札とステッチの札）、tag_<n>.png（名札の柄のページ）、stitch_trail.png・stitch_ball.png（ステッチのページ）
## 数字: 名札の札を押すと名札の柄のページだけ（ページの札 4 枚）、ステッチの札を押すと滑りあとと雪玉の柄だけ（ページの札 2 枚）、
##       もう一度押すと装備に戻る、Esc でも戻る、ページの札で滑りあと ⇄ 雪玉

const Tags := preload("res://sled_tags.gd")

var args := {}
var main: Node3D
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _process(_dt: float) -> bool:   # 窓から目が離れると設定の画面が開くので、閉じる
	if main and main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _dir() -> String:
	return String(args.get("dir", "/tmp/tag_stitch_tabs"))


func _ok(cond: bool, what: String) -> void:
	print(("OK " if cond else "NG ") + what)
	if not cond:
		fails += 1


func _shot(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dir().path_join(name))
	print("撮った: ", name)


func _click(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	main.craft_ui._input(e)


## 右に出ているページの札の、ページの番号
func _pages(ui) -> Array:
	var out: Array = []
	for o in ui._opt_rects:
		if o[1] == "_page":
			out.append(o[2])
	return out


func _run() -> void:
	await create_timer(2.5).timeout
	var ui = main.craft_ui
	if ui == null:   # 読み込めなかった
		print("NG 画面を読み込めない")
		quit(1)
		return
	ui.open_gear()
	await _shot("gear.png")
	if args.has("before"):   # 分ける前: 名札の札を押して、6 枚のページの札を順に
		ui.tag_open = true
		for k in Tags.PAGES.size() + 2:
			ui.tag_page = k
			await _shot("before_page%d.png" % (k + 1))
		quit(0)
		return
	var n := Tags.PAGES.size()
	_ok(ui._stitch_card_rect.size.x > 0.0 and not ui._stitch_card_rect.intersects(ui._tag_card_rect), "左に名札の札と、別のステッチの札がある")
	_click(ui._tag_card_rect.get_center())
	await create_timer(0.3).timeout
	_ok(ui.tag_open and ui.tag_page < n and _pages(ui) == range(n), "名札の札: 名札の柄のページの札 %d 枚だけ（%s）" % [n, _pages(ui)])
	for k in n:
		ui.tag_page = k
		await _shot("tag_%d.png" % (k + 1))
	_click(ui._stitch_card_rect.get_center())
	await create_timer(0.3).timeout
	_ok(ui.tag_open and ui.tag_page == n and _pages(ui) == [n, ui.ball_page()], "ステッチの札: 滑りあとと雪玉の柄のページの札 2 枚だけ（%s）" % [_pages(ui)])
	var trail := 0
	for o in ui._opt_rects:
		if o[1] == "_stitch":
			trail += 1
	_ok(trail > 0, "ステッチの札: 滑りあとの柄が並ぶ（%d）" % trail)
	await _shot("stitch_trail.png")
	for o in ui._opt_rects:
		if o[1] == "_page" and o[2] == ui.ball_page():
			_click((o[0] as Rect2).get_center())
			break
	await create_timer(0.3).timeout
	_ok(ui.tag_page == ui.ball_page(), "ステッチの中のページの札で、雪玉の柄へ")
	await _shot("stitch_ball.png")
	_click(ui._tag_card_rect.get_center())
	await create_timer(0.3).timeout
	_ok(ui.tag_open and ui.tag_page == n - 1, "名札の札へ戻ると、前に開いていた名札の柄のページ（%d）" % ui.tag_page)
	_click(ui._stitch_card_rect.get_center())
	await create_timer(0.3).timeout
	_ok(ui.tag_page == ui.ball_page(), "ステッチの札へ戻ると、前に開いていた雪玉の柄のページ")
	_click(ui._stitch_card_rect.get_center())
	await create_timer(0.3).timeout
	_ok(ui.gear_open and not ui.tag_open and not ui._scope_rects.is_empty(), "開いているステッチの札をもう一度押すと装備に戻る")
	_click(ui._stitch_card_rect.get_center())
	await create_timer(0.2).timeout
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	ui._input(esc)
	_ok(ui.gear_open and not ui.tag_open, "Esc でステッチから装備に戻る（画面は開いたまま）")
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)
