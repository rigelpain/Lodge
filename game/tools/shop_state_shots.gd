extends SceneTree
## 店の札の見え方（craft_icons.gd の card_state・foot・over。2026-11-10 代表「一般的なゲームのやりかたにしてほしい」「Aかなー」）の絵と数字。
##   Godot --path game --resolution 1280x720 -s res://tools/shop_state_shots.gd -- --dir=/path/out --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
## ロックは確かめのあいだだけ、各店の 1 品ずつに付ける（shop_locks.gd の extra。ゲームの中のロックの品は空のまま）。
##   <店>_states.jpg  買える（値段のボタン）・足りない（グレー）・持っている（緑のチェック）・身につけている（赤い糸の縁とチェック）・ロック（南京錠）が並ぶ画面
##   <店>_full.jpg    持ち物がいっぱい（画面全体がグレーで、巾着からあふれる印）
## 数字: 足りない・ロックの札は選べない、持っている・身につけている札は選べる、いっぱいの店では買えない、ロックの品はホストが断る

const ShopLocks := preload("res://shop_locks.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Food := preload("res://food.gd")
const Pals := preload("res://pals.gd")
const BS := preload("res://ball_stitches.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var c: Node
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
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _ok(cond: bool, what: String) -> void:
	print(("OK " if cond else "NG ") + what)
	if not cond:
		fails += 1


func _shot(name: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp/shop_states"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg(dir.path_join(name), 0.9)
	print("撮った: ", dir.path_join(name))


func _fill_bag(full: bool) -> void:
	var b: Array = c.bags[p.id]
	for i in b.size():
		b[i] = {"kind": "fabric", "fabric": "red"} if full else {}
	c.hands[p.id] = -1


func _run() -> void:
	await create_timer(2.0).timeout
	p = main.player
	c = main.craft
	var who: int = p.id
	var pet_lock: String = Pals.keys_of("pet")[Pals.keys_of("pet").size() - 1]
	var lantern_lock: String = preload("res://lantern.gd").LOOKS[preload("res://lantern.gd").LOOKS.size() - 1]
	var dish_lock: String = Food.ORDER[Food.ORDER.size() - 1]
	ShopLocks.extra = ["mountain:binoculars_night", "pattern:large", "stitch:garden", "ball:crystal", "pal:" + pet_lock, "pal:paper_crane",
			"lantern:" + lantern_lock, "food:" + dish_lock]
	_ok(ShopLocks.LOCKED.is_empty(), "ゲームの中でロックしている品はない（確かめのあいだだけ付ける）")
	_fill_bag(false)
	c.gloves[who] = [{"grade": "gloves"}]   # 毛糸の手袋を持っている
	c.gloves_sel[who] = 0
	c.wallets[who] = 120
	# ---- 山師の道具
	var mu = main.mountain_ui
	mu.open()
	var night := 4
	_ok(mu.state(night) == "locked", "夜の双眼鏡（ロック）は南京錠: %s" % mu.state(night))
	_ok(mu.state(6) == "money" and mu.state(5) == "worn" and mu.state(0) == "can", "フェルトの手袋は足りない・毛糸ははめている・焚き火は買える: %s %s %s" % [mu.state(6), mu.state(5), mu.state(0)])
	c.gloves[who] = [{"grade": "gloves"}, {"grade": "gloves_leather"}]   # 革も持っているが、はめているのは毛糸
	_ok(mu.state(7) == "owned" and CraftIcons.pickable("owned") and CraftIcons.pickable("worn"), "革の手袋は持っている（チェック）。持っている・身につけている札は選べる: %s" % mu.state(7))
	await _shot("yama_states.jpg")
	mu.set_page(4)   # 手袋の棚（2026-11-10 代表「山師は双眼鏡と手袋はそれぞれ別タブ作ったほうが良いかも」）
	await _shot("yama_gloves_states.jpg")
	_ok(mu._rects[6] != Rect2() and mu._rects[0] == Rect2(), "手袋の棚: 手袋だけが並ぶ（焚き火の札は押せない）")
	mu.set_page(3)
	await _shot("yama_scope_states.jpg")
	_ok(mu._rects[2] != Rect2() and mu._rects[6] == Rect2(), "双眼鏡の棚: 双眼鏡だけが並ぶ")
	mu.set_page(0)
	await _shot("yama_tools_states.jpg")
	_ok(mu._rects[0] != Rect2() and mu._rects[2] == Rect2() and mu._rects[6] == Rect2(), "道具の棚: 焚き火セットとペグだけ")
	mu.select(6)
	_ok(mu._sel != 6, "足りない札は選べない")
	mu.select(night)
	_ok(mu._sel != night, "ロック（南京錠）の札は選べない")
	_ok(not c.send({"kind": "buy", "who": who, "item": {"kind": "binoculars_night"}}), "ロックの品はホストが断る")
	c.gloves[who] = [{"grade": "gloves"}]
	mu.close()
	_fill_bag(true)
	c.wallets[who] = 2000
	mu.open()
	await _shot("yama_full.jpg")
	_ok(mu.state(0) == "full" and mu.state(6) == "can", "いっぱい: 焚き火は買えない（%s）、手袋は場所を使わないので買える（%s）" % [mu.state(0), mu.state(6)])
	mu.set_page(4)
	await _shot("yama_gloves_full.jpg")
	_ok(not mu.bag_full(), "いっぱいでも、手袋の棚は持ち物の枠を出さない（場所を使わない）")
	mu.set_page(2)
	c.wallets[who] = 120
	c.ball_owned[who] = ["back"]
	await _shot("ball_states.jpg")
	mu.close()
	# ---- ソリ屋
	var cu = main.craft_ui
	_fill_bag(false)
	c.wallets[who] = 120
	cu.open_shop()
	await _shot("sori_states.jpg")
	_ok(cu.shop_state(3) == "locked" and cu.shop_state(0) == "can", "ソリ屋: 大の型紙はロック・米袋の型紙は買える: %s %s" % [cu.shop_state(3), cu.shop_state(0)])
	cu.close_shop()
	await create_timer(0.3).timeout
	_fill_bag(true)
	cu.open_shop()
	await _shot("sori_full.jpg")
	_ok(cu.shop_state(0) == "full" and not cu.sel_ready(), "ソリ屋: いっぱいなら買えない")
	cu.close_shop()
	await create_timer(0.3).timeout
	# ---- 見本帳
	_fill_bag(false)
	c.wallets[who] = 100
	main.sled_book_ui.open()
	await _shot("book_states.jpg")
	_ok(main.sled_book_ui.stitch_state("garden") == "locked" and main.sled_book_ui.stitch_state("feather") == "money", "見本帳: 花の蔓はロック・フェザーは足りない")
	main.sled_book_ui.pick_stitch("feather")
	_ok(main.sled_book_ui._stitch != "feather", "見本帳: 足りない柄は選べない")
	main.sled_book_ui.close()
	await create_timer(0.3).timeout
	# ---- 紙細工屋さん・山師の連れ
	c.wallets[who] = 150
	main.paper_shop_ui.open("head")
	await _shot("paper_states.jpg")
	main.paper_shop_ui.set_tab(0)   # 提灯の形（値段・チェック・提げている形の赤い糸の縁）
	await _shot("paper_lantern_states.jpg")
	main.paper_shop_ui.close()
	await create_timer(0.3).timeout
	# 山師のミニオンの棚（2026-11-10 代表「山師のミニオン購入だけUIの形変わるの嫌過ぎる」）: ほかの棚と同じ形で、山師の画面の中
	var mu2 = main.mountain_ui
	mu2.open()
	mu2.set_page(1)
	await _shot("pet_states.jpg")
	var last: int = Pals.keys_of("pet").size() - 1
	_ok(mu2.state(last) == "locked", "ミニオン: ロックのミニオンは南京錠（%s）" % mu2.state(last))
	mu2.select(last)
	_ok(mu2._sel != last, "ミニオン: ロックの札は選べない")
	_ok(not main.minion_ui.is_open and mu2._rects.size() == Pals.keys_of("pet").size(), "ミニオン: 別の画面は開かず、山師の画面の札で並ぶ")
	var ys: Array = []
	for pg in [0, 1, 3, 4, 2]:
		ys.append((mu2._tab_rects[pg] as Rect2).position.y)
	_ok(ys[0] < ys[1] and ys[1] < ys[2] and ys[2] < ys[3] and ys[3] < ys[4], "段の札は上から 消耗品・ミニオン・双眼鏡・手袋・雪玉の柄（%s）" % [ys])
	mu2.close()
	await create_timer(0.3).timeout
	# ---- 雪だるまの店
	main.emotes.balls[who] = 2
	main.food_ui.open()
	await _shot("food_states.jpg")
	main.food_ui.close()
	await create_timer(0.3).timeout
	_fill_bag(true)
	main.food_ui.open()
	await _shot("food_full.jpg")
	_ok(main.food_ui.card_state(0) == "full", "雪だるまの店: いっぱいなら買えない")
	main.food_ui.close()
	_fill_bag(false)
	ShopLocks.extra = []
	print("だめだった数: %d" % fails)
	quit(1 if fails > 0 else 0)
