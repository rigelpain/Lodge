extends SceneTree
## 店の売り場の絵（2026-11-10 代表「ショップのなかゴチャついてたりする？」）。直す前と後で同じ道具を使えるよう、どちらの版にもある入口だけを使う。
##   Godot --path game --resolution 1280x720 -s res://tools/shop_tidy_shots.gd -- --dir=/path/out --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   sori_0.jpg / sori_1.jpg  ソリ屋（おじいさんの売り台）の棚（型紙と布・滑りあとの柄。直したあとは型紙と布だけ）
##   book.jpg                 見本帳（ソリの色と滑りあとの柄）
##   yama_0.jpg / yama_pet.jpg / yama_2.jpg  山師の売り場（道具・連れ・雪玉の柄）
##   paper.jpg / food.jpg     紙細工屋・雪だるまの食べ物屋（ほかの店。並べて見るため）

var args := {}
var main: Node3D
var p: CharacterBody3D


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


func _shot(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp/shops"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg(dir.path_join(name), 0.9)
	print("撮った: ", dir.path_join(name))


func _run() -> void:
	await create_timer(2.0).timeout
	p = main.player
	main.craft.wallets[p.id] = 320
	# ソリ屋
	var cu = main.craft_ui
	cu.open_shop()
	await _shot("sori_0.jpg")
	if cu.get("shop_page") != null:   # 直す前の版だけ: 2 枚目の棚（滑りあとの柄）
		cu.set("shop_page", 1)
		await _shot("sori_1.jpg")
	else:
		print("ソリ屋の棚の札は 1 枚だけ（滑りあとの柄の棚はない）")
	cu.close_shop()
	await create_timer(0.3).timeout
	# 見本帳
	main.sled_book_ui.open()
	await _shot("book.jpg")
	main.sled_book_ui.close()
	await create_timer(0.3).timeout
	# 山師: 道具 → 連れ → 雪玉の柄
	var mu = main.mountain_ui
	mu.open()
	await _shot("yama_0.jpg")
	mu.open_pets()
	await _shot("yama_pet.jpg")
	main.minion_ui.close()
	await create_timer(0.3).timeout
	mu.open()
	mu.set_page(2)
	await _shot("yama_2.jpg")
	mu.close()
	await create_timer(0.3).timeout
	# ほかの店
	main.paper_shop_ui.open()
	await _shot("paper.jpg")
	main.paper_shop_ui.close()
	await create_timer(0.3).timeout
	main.food_ui.open()
	await _shot("food.jpg")
	main.food_ui.close()
	quit(0)
