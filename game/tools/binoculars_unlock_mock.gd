extends SceneTree
## 案の絵（まだ作っていない）: 双眼鏡を、持ち物の枠を使わない「解放」にする（2026-11-10 代表「手袋も双眼鏡もUNLOCK形式にしましょう」）。
## 本物の画面を撮り、その上に案の部品を同じ描き方（hud_icons.gd・craft_icons.gd）で重ねる。
##   Godot --path game --resolution 1600x900 -s res://tools/binoculars_unlock_mock.gd -- --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-save --dir=/path
##   now_gear.png  今の装備の画面（双眼鏡が手持ちとかばんの枠に入っている）
##   idea_gear.png 案: 装備の画面の手袋の列の下に、双眼鏡の段の札の列（押すと選ぶ）。持ち物の枠は空く
##   idea_bar_a.png 案ア: 手持ちの列の、素手の右に首から下げた双眼鏡の枠（ホイールで持ち替え、左クリックでのぞく。今と同じ）
##   idea_bar_b.png 案イ: 手持ちの列には出さず、胸に下げてキーでのぞく

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")

var args := {}
var main: Node3D
var over: Over


class Over extends Control:
	var mode := ""
	var ui: Node

	func _draw() -> void:
		var u: float = ui.ui()
		match mode:
			"gear":
				_gear_row(u)
			"bar_a":
				_bar(u, true)
			"bar_b":
				_bar(u, false)

	## 手袋の札の列の下に、双眼鏡の段の札（手袋と同じ形）。選んでいる段は赤い破線と山形
	func _gear_row(u: float) -> void:
		var gl: Array = ui._glove_rects
		if gl.is_empty():
			return
		var gw := 92.0 * u
		var gh := 104.0 * u
		var gap := 10.0 * u
		var kinds := ["binoculars", "binoculars_far", "binoculars_night"]
		var right: float = (gl[gl.size() - 1] as Rect2).end.x
		var y: float = (gl[0] as Rect2).position.y + 8.0 * u + gh + 22.0 * u
		var x := right - kinds.size() * gw - (kinds.size() - 1) * gap
		for i in kinds.size():
			var card := Rect2(x + i * (gw + gap), y, gw, gh)
			var picked := i == 1
			if picked:
				card.position.y -= 8.0 * u
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, gw, gh, 12.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			CraftIcons.item(self, {"kind": kinds[i]}, card.get_center(), gw * 0.82, 1.0)
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, gw + 8 * u, gh + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
				Icons.chevron(self, Vector2(card.get_center().x, card.position.y - 14.0 * u), 18.0 * u, Icons.RED, 1.0, PI / 2, 3.0 * u)

	## 手持ちの列を描き直す（本物の列の上にかぶせる）。neck なら素手の右に首から下げた双眼鏡の枠、そうでなければ列の左に胸の双眼鏡とキー
	func _bar(u: float, neck: bool) -> void:
		var bag: Array = ui.craft.bag(ui._who())
		var cell := 58.0 * u
		var gap := 6.0 * u
		var n := 6 + (2 if neck else 1)
		var cells_w := n * cell + (n - 1) * gap
		var x0 := size.x / 2.0 - cells_w / 2.0
		var y := size.y - 20.0 * u - cell
		Icons.screen()
		Icons.patch(self, Icons.rr(x0 - 12.0 * u, y - 10.0 * u, cells_w + 24.0 * u, cell + 20.0 * u, 16.0 * u), Icons.PAPER, 1.0, false)
		var held := 0 if neck else -1
		for i in n:
			var r := Rect2(x0 + i * (cell + gap), y, cell, cell)
			var slot := i - (2 if neck else 1)
			if neck and i == 1:   # 首から下げた双眼鏡: 丸い枠に紐を掛ける
				var on := held == 0
				if on:
					r.position.y -= 8.0 * u
				var c := r.get_center()
				Icons.screen()
				Icons.thread(self, PackedVector2Array([c + Vector2(-cell * 0.42, -cell * 0.1), c + Vector2(-cell * 0.2, -cell * 0.62), c + Vector2(cell * 0.2, -cell * 0.62), c + Vector2(cell * 0.42, -cell * 0.1)]), Icons.WOOD, 2.6 * u, 1.0)
				Icons.patch(self, Icons.circ(c, cell * 0.5, 24), Color(0.30, 0.38, 0.30), 1.0, true, Icons.CAP)
				CraftIcons.item(self, {"kind": "binoculars_far"}, c, cell * 0.8, 1.0)
				if on:
					Icons.screen()
					Icons.dashes(self, Icons.circ(c, cell * 0.5 + 4.0 * u, 24), Icons.RED, 2.4 * u, 6.0 * u, 3.5 * u, 1.0, true)
					Icons.chevron(self, Vector2(c.x, r.position.y - 12.0 * u), 14.0 * u, Icons.RED, 1.0, PI / 2, 2.6 * u)
				continue
			if slot >= 0 and (slot >= bag.size() or bag[slot].is_empty()):
				Icons.screen()
				Icons.dashes(self, Icons.rr(r.position.x + 4.0 * u, r.position.y + 4.0 * u, cell - 8.0 * u, cell - 8.0 * u, 9.0 * u), Icons.PAPER_EDGE, 2.0 * u, 5.0 * u, 4.0 * u, 0.9, true)
				continue
			Icons.screen()
			Icons.patch(self, Icons.rr(r.position.x, r.position.y, cell, cell, 10.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			if slot < 0:
				Icons.icon(self, "hand", r.get_center(), cell * 0.66, 1.0, Icons.RED)
			else:
				CraftIcons.item(self, bag[slot], r.get_center(), cell * 0.82, 1.0)
		if not neck:   # 列の左: 紐で下げた双眼鏡と、のぞくキー
			var c := Vector2(x0 - 70.0 * u, y + cell * 0.5)
			Icons.screen()
			Icons.thread(self, PackedVector2Array([c + Vector2(-20 * u, -6 * u), c + Vector2(-8 * u, -34 * u), c + Vector2(8 * u, -34 * u), c + Vector2(20 * u, -6 * u)]), Icons.WOOD, 2.4 * u, 1.0)
			CraftIcons.item(self, {"kind": "binoculars_far"}, c, cell * 0.8, 1.0)
			Icons.keycap(self, "O", Vector2(c.x + 46.0 * u, c.y), 30.0 * u, 1.0)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _shot(name: String) -> void:
	over.queue_redraw()
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp/binoculars_unlock"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(name))
	print("撮った: ", dir.path_join(name))


func _run() -> void:
	await create_timer(2.5).timeout
	var p = main.player
	var c = main.craft
	var ui = main.craft_ui
	var who: int = p.id
	p.set("_pitch", -0.05)
	p.set_third(false)
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	over = Over.new()
	over.ui = ui
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(over)
	c.gloves[who] = [{"grade": "gloves"}, {"grade": "gloves_felt"}, {"grade": "gloves_leather"}]
	c.gloves_sel[who] = 1
	c.wallets[who] = 37
	var others := [{"kind": "pattern", "sled": "small"}, {"kind": "fabric", "fabric": "plum"}, {"kind": "campfire"}, {"kind": "food", "dish": "ramen", "step": 1}]
	# 今: 双眼鏡が持ち物の枠に入っている（手持ちに 2 つ、かばんに 1 つ）
	var b: Array = [{"kind": "binoculars_far"}, others[0], {"kind": "binoculars"}, others[1], {}, {},
			{"kind": "binoculars_night"}, others[2], {}, others[3], {}, {}]
	c.bags[who] = b
	c.hands[who] = 0
	ui.open_gear()
	await _shot("now_gear.png")
	# 案: 双眼鏡は枠から出て、手袋の下の札の列で選ぶ
	c.bags[who] = [others[0], others[1], {}, {}, {}, {}, others[2], others[3], {}, {}, {}, {}]
	c.hands[who] = -1
	over.mode = "gear"
	await _shot("idea_gear.png")
	ui.close_gear()
	over.mode = ""
	await create_timer(0.5).timeout
	c.bags[who] = [{"kind": "binoculars_far"}, others[0], {"kind": "binoculars"}, others[1], {}, {}, {}, {}, {}, {}, {}, {}]
	c.send({"kind": "hand", "who": who, "slot": 0})
	await _shot("now_bar.png")
	c.bags[who] = [others[0], others[1], {}, {}, {}, {}, others[2], others[3], {}, {}, {}, {}]
	c.hands[who] = -1
	over.mode = "bar_a"
	await _shot("idea_bar_a.png")
	over.mode = "bar_b"
	await _shot("idea_bar_b.png")
	quit()
