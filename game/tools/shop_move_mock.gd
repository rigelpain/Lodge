extends SceneTree
## 案の絵（まだ作っていない）: 雪玉の柄（ball_stitches.gd）を、山師の売り場から布の見本帳へ移したときの見本帳の画面。
## 見本帳の本物の画面（sled_book_ui.gd）を開き、その上に、右の面のいちばん上の札 2 枚（滑りあとの柄・雪玉の柄）と、
## 雪玉の柄の札 16 枚を、ゲームの中と同じ部品（hud_icons.gd・ball_stitches.gd・craft_icons.gd）で描く。
##   Godot --path game --resolution 1280x720 -s res://tools/shop_move_mock.gd -- --dir=/path/out --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   mock_book_ball.jpg  見本帳の右の面を「雪玉の柄」の札にしたところ

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const BS := preload("res://ball_stitches.gd")
const Stitches := preload("res://stitches.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D


class Mock extends Control:
	var book: Node
	var craft: Node
	var who := -1

	func _draw() -> void:
		var board: Vector2 = book.BOARD
		var vs := size
		var k := minf(Icons.ui_scale(vs.y), minf((vs.x - 40.0) / board.x, (vs.y - 40.0) / board.y))
		var o := (vs - board * k) / 2.0
		# 右の面を、雪玉の柄の札で覆う（滑りあとの柄の札と同じ大きさ・並び）
		var rp := Rect2(o + Vector2(760, 36) * k, Vector2(704, 788) * k)
		Icons.screen()
		Icons.paper_tag(self, rp, 16.0 * k, k)
		# 右の面のいちばん上に札 2 枚: 滑りあとの柄（いまの棚）・雪玉の柄（選んでいる）
		for t in 2:
			var on := t == 1
			var tr := Rect2(o + Vector2(784 + t * 124, (50 if on else 56)) * k, Vector2(112, 70) * k)
			Icons.screen()
			Icons.patch(self, Icons.rr(tr.position.x, tr.position.y, tr.size.x, tr.size.y, 9.0 * k), Icons.CAP if on else Icons.PAPER_EDGE, 1.0, on, Icons.PAPER_EDGE)
			if t == 0:
				Stitches.draw_swatch(self, "cross", Rect2(tr.get_center() - Vector2(28, 28) * k, Vector2(56, 56) * k), Icons.RED, 0.6)
			else:
				BS.draw_ball(self, "kiku", "gloves", Rect2(tr.get_center() - Vector2(30, 30) * k, Vector2(60, 60) * k), 1.0)
				Icons.screen()
				Icons.dashes(self, Icons.rr(tr.position.x - 2 * k, tr.position.y - 2 * k, tr.size.x + 4 * k, tr.size.y + 4 * k, 10.0 * k), Icons.RED, 2.4 * k, 5.0 * k, 3.0 * k, 1.0, true)
		var names: Array = BS.for_sale()
		var coins: int = craft.wallet(who)
		var owned: Array = craft.ball_owned.get(who, [])
		for i in names.size():
			var nm: String = names[i]
			var r := Rect2(o + Vector2(778 + (i % 6) * 112.0, 140 + (i / 6) * 190.0) * k, Vector2(104, 178) * k)
			var has := nm in owned
			var price := BS.price(nm)
			var a := 1.0 if has or price <= coins else 0.35
			Icons.screen()
			Icons.patch(self, Icons.rr(r.position.x, r.position.y, r.size.x, r.size.y, 9.0 * k), Icons.CAP, 1.0 if a > 0.5 else 0.55, true, Icons.PAPER_EDGE)
			var bs := r.size.x - 10.0 * k
			BS.draw_ball(self, nm, "gloves", Rect2(r.position + Vector2(5, 14) * k, Vector2(bs, bs)), a)
			var foot := r.position + Vector2(r.size.x / 2.0, r.size.y - 22.0 * k)
			if has:
				Icons.screen()
				Icons.icon(self, "needle", foot, 30.0 * k, 1.0)
			else:
				CraftIcons.price(self, foot, price, 7.5 * k, a)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _run() -> void:
	await create_timer(2.0).timeout
	p = main.player
	main.craft.wallets[p.id] = 320
	main.craft.ball_owned[p.id] = ["back", "cross", "kiku"]
	main.sled_book_ui.open()
	var layer := CanvasLayer.new()
	layer.layer = 50
	var m := Mock.new()
	m.book = main.sled_book_ui
	m.craft = main.craft
	m.who = p.id
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(m)
	root.add_child(layer)
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp/shops"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg(dir.path_join("mock_book_ball.jpg"), 0.9)
	print("撮った: ", dir.path_join("mock_book_ball.jpg"))
	quit(0)
