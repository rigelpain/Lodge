extends SceneTree
## 手の双眼鏡の解放と、持ち物の画面（I）の B の並べ方（2026-11-10 代表「手袋も双眼鏡もUNLOCK形式にしましょう」「Bがいいレイアウトは」）の確かめ。数字と絵。
##   Godot --path game --resolution 1600x900 -s res://tools/inventory_unlock_check.gd -- --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-save --dir=/path
## 数字: 双眼鏡は持ち物の場所を使わない・同じ段は 2 度買えない・持ち物がいっぱいでも買える・首の枠で手に持ってのぞける・外せる・
##       保存から戻せる（scope_own・equip の grade）・前の版の持ち物の双眼鏡は移る・山師の札は「持っている」・装備の画面の段と名札の画面
## 絵: gear_few.png（少し持っている）、gear_many.png（米袋 14・ランタン 10。めくる札）、gear_tag.png（名札と柄の画面）、bar_neck.png（手持ちの列の首の枠）、
##     yama_owned.png（山師の棚で、持っている双眼鏡が針の印）

const Craft := preload("res://craft.gd")

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
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _ok(cond: bool, what: String) -> void:
	print(("OK " if cond else "NG ") + what)
	if not cond:
		fails += 1


func _shot(name: String) -> void:
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp/inventory_unlock"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(name))
	print("撮った: ", dir.path_join(name))


func _click(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	main.craft_ui._input(e)


func _run() -> void:
	await create_timer(2.5).timeout
	var p = main.player
	var c = main.craft
	var ui = main.craft_ui
	var who: int = p.id
	p.set("_pitch", -0.05)
	p.set_third(false)
	c.wallets[who] = 5000
	var used: int = c.count(who)
	# ---- 買う
	_ok(c.send({"kind": "buy", "who": who, "item": {"kind": "binoculars_far"}}), "遠見の双眼鏡を買える")
	_ok(c.count(who) == used, "持ち物の場所は使わない（%d → %d）" % [used, c.count(who)])
	_ok(c.scope(who).get("kind", "") == "binoculars_far" and c.hands[who] == Craft.NECK, "買うと首から下げて手に持つ")
	_ok(p.held().get("kind", "") == "binoculars_far", "手に持っているのは遠見の双眼鏡")
	_ok(not c.send({"kind": "buy", "who": who, "item": {"kind": "binoculars_far"}}), "同じ段は 2 度買えない")
	for i in c.bags[who].size():   # 持ち物をいっぱいにしても、双眼鏡は買える
		if c.bags[who][i].is_empty():
			c.bags[who][i] = {"kind": "fabric", "fabric": "red"}
	_ok(c.free_slot(who) < 0 and c.send({"kind": "buy", "who": who, "item": {"kind": "binoculars_night"}}), "持ち物がいっぱいでも夜目の双眼鏡を買える")
	_ok(c.scopes[who].size() == 2 and c.scope(who).kind == "binoculars_night", "持っている双眼鏡は 2 つ、首は夜目")
	# ---- 山師の札
	main.mountain_ui.open()
	await create_timer(0.3).timeout
	var night := -1
	var plain := -1
	for i in preload("res://mountain_goods.gd").SHELF.size():
		match String(preload("res://mountain_goods.gd").SHELF[i].item.kind):
			"binoculars_night": night = i
			"binoculars": plain = i
	_ok(main.mountain_ui.state(night) == "owned", "山師の棚: 夜目は「持っている」（%s）" % main.mountain_ui.state(night))
	_ok(main.mountain_ui.state(plain) == "can", "山師の棚: いっぱいでも、ふつうの双眼鏡は買える（%s）" % main.mountain_ui.state(plain))
	await _shot("yama_owned.png")
	main.mountain_ui.close()
	await create_timer(0.3).timeout
	for i in c.bags[who].size():
		c.bags[who][i] = {}
	c.bags[who][0] = {"kind": "pattern", "sled": "small"}
	c.bags[who][1] = {"kind": "fabric", "fabric": "plum"}
	c.bags[who][6] = {"kind": "campfire"}
	# ---- 持ち替えとのぞく
	c.hands[who] = -1
	p.cycle_hand(1)
	_ok(c.hands[who] == Craft.NECK, "素手の次は首の双眼鏡（%d）" % c.hands[who])
	p.cycle_hand(1)
	_ok(c.hands[who] == 0, "その次は手持ちの 1 つ目（%d）" % c.hands[who])
	c.send({"kind": "hand", "who": who, "slot": Craft.NECK})
	await create_timer(0.8).timeout
	await _shot("bar_neck.png")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p._left_click()
	await create_timer(0.5).timeout
	_ok(p.peek == "hand", "首の双眼鏡を手に持って、左クリックでのぞく（%s）" % p.peek)
	p.peek_stop()
	await create_timer(0.5).timeout
	# ---- 外す・選び直す
	_ok(c.send({"kind": "equip", "who": who, "gear": "binoculars", "index": -1}) and c.scope(who).is_empty() and c.hands[who] == -1, "外すと首の枠が消え、素手になる")
	p.cycle_hand(1)
	_ok(c.hands[who] == 0, "外しているあいだは、素手の次は手持ちの 1 つ目")
	_ok(c.send({"kind": "equip", "who": who, "gear": "binoculars", "index": 0}) and c.scope(who).kind == "binoculars_far", "選ぶだけで遠見に替わる")
	# ---- 保存から戻す（scope_own と、段で下げる equip）。前の版の持ち物の双眼鏡は移る
	var other := 99
	c.join(other)
	c.send({"kind": "scope_own", "who": other, "grade": "binoculars_night"})
	c.send({"kind": "scope_own", "who": other, "grade": "binoculars"})
	_ok(c.send({"kind": "equip", "who": other, "gear": "binoculars", "grade": "binoculars"}) and c.scope(other).kind == "binoculars", "保存から戻す: 持っている段と、下げていた段")
	_ok(not c.send({"kind": "equip", "who": other, "gear": "binoculars", "grade": "binoculars_far"}), "持っていない段は下げられない")
	c.bags[other][2] = {"kind": "binoculars_far"}
	c.bags[other][7] = {"kind": "binoculars"}
	c.hands[other] = 2
	var moved: int = c.lift_scopes(other)
	_ok(moved == 2 and c.count(other) == 0 and c.scope_index(other, "binoculars_far") >= 0 and c.scopes[other].size() == 3, "前の版の持ち物の双眼鏡は、持っている双眼鏡へ移り、場所は空く（%d）" % moved)
	# ---- 持ち物の画面（B）
	c.sacks[who] = [{"fabric": ""}, {"fabric": "navy"}, {"fabric": "plum"}]
	c.gloves[who] = [{"grade": "gloves"}]
	c.gloves_sel[who] = 0
	c.send({"kind": "hand", "who": who, "slot": 0})
	ui.open_gear()
	await _shot("gear_few.png")
	_ok(ui._gear_rects.size() == 3 and ui._lamp_rects.size() == c.lanterns[who].size() and ui._glove_rects.size() == 1 and ui._scope_rects.size() == 2,
			"4 段: 米袋 3・ランタン %d・手袋 1・双眼鏡 2（%d %d %d %d）" % [c.lanterns[who].size(), ui._gear_rects.size(), ui._lamp_rects.size(), ui._glove_rects.size(), ui._scope_rects.size()])
	_ok(ui._inv_rects.size() == 12, "手持ちとかばんは 12 の場所")
	_click((ui._scope_rects[1] as Rect2).get_center())
	await create_timer(0.3).timeout
	_ok(c.scope(who).get("kind", "") == "binoculars_night", "双眼鏡の札を押すと首の段が替わる")
	_click((ui._scope_rects[1] as Rect2).get_center())
	await create_timer(0.3).timeout
	_ok(c.scope(who).is_empty(), "下げている札をもう一度押すと外す")
	_click((ui._scope_rects[0] as Rect2).get_center())
	_click(ui._tag_card_rect.get_center())
	await create_timer(0.3).timeout
	_ok(ui.tag_open and not ui._opt_rects.is_empty() and ui._scope_rects.is_empty() and ui._inv_rects.is_empty(), "名札の札を押すと、右が名札と柄の画面になる")
	await _shot("gear_tag.png")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	ui._input(esc)
	_ok(ui.gear_open and not ui.tag_open, "Esc で名札と柄の画面から装備に戻る（画面は開いたまま）")
	# 品が増えたとき: 米袋 14・ランタン 10・手袋 3・双眼鏡 3
	var fabs := ["", "navy", "plum", "mustard", "holly", "red", "cream"]
	c.sacks[who] = []
	for i in 14:
		c.sacks[who].append({"fabric": fabs[i % fabs.size()]})
	c.lanterns[who] = []
	for lk in preload("res://lantern.gd").LOOKS:
		c.lanterns[who].append({"look": lk})
	c.gloves[who] = [{"grade": "gloves"}, {"grade": "gloves_felt"}, {"grade": "gloves_leather"}]
	c.send({"kind": "buy", "who": who, "item": {"kind": "binoculars"}})
	ui.close_gear()
	ui.open_gear()
	await _shot("gear_many.png")
	var sack_shown: int = ui._gear_rects.filter(func(r): return (r as Rect2).size.x > 0.0).size()
	var lamp_shown: int = ui._lamp_rects.filter(func(r): return (r as Rect2).size.x > 0.0).size()
	_ok(lamp_shown == 10, "ランタン 10 は小さくして 1 段に入る（%d）" % lamp_shown)
	_ok(sack_shown < 14 and ui._page_rects.size() == 1, "米袋 14 は入りきらず、めくる札が出る（見えている %d）" % sack_shown)
	_click((ui._page_rects[0][0] as Rect2).get_center())
	await create_timer(0.3).timeout
	_ok((ui._gear_rects[0] as Rect2).size.x == 0.0 and (ui._gear_rects[sack_shown] as Rect2).size.x > 0.0, "めくる札を押すと次のページ")
	await _shot("gear_many_page2.png")
	ui.close_gear()
	print("だめだった数: %d" % fails)
	quit(1 if fails > 0 else 0)
