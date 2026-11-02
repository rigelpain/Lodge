extends SceneTree
## 山師が育てているミニオンの柵と、ミニオンを買う流れを撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/mountain_pets_shots.gd -- --spawn=mountain --dir=/path/shots
## 撮るもの:
##   pen.png         客の側から、山師と道具の棚とミニオンの柵
##   tools.png       山師に F で開いた売り場（左に「道具」「連れ」の札）
##   pets.png        「連れ」の札で開いたミニオンの画面（連れの段だけ。左の上に山の道具へ戻る札）
##   pets_bought.png カエルを買った（すぐ連れる。札に赤い結び目）
##   walk.png        画面を閉じて、カエルが足もとに来た
##   stall.png       2 階の売り台の画面（頭・肩の段だけ）
## ログに、買えたか・連れているか・持ち物の保存の形（craft.gd の pal_owned・pal_worn）を出す

var args := {}
var main: Node3D


## あなたの保存（player.gd の TAG_FILE。ミニオンを買うと書かれる）を、終わりに元へ戻す（確かめで代表の保存を変えない）
const TAG_FILE := "user://my_tag.cfg"
var _saved_tag := ""


func _restore_tag() -> void:
	if _saved_tag != "":
		var f := FileAccess.open(TAG_FILE, FileAccess.WRITE)
		if f:
			f.store_string(_saved_tag)


func _initialize() -> void:
	if FileAccess.file_exists(TAG_FILE):   # 始めの保存を預かる（ホストもつなぐ側も同じファイル）
		_saved_tag = FileAccess.get_file_as_string(TAG_FILE)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/mountain_pets")


func _process(_dt: float) -> bool:
	if main and main.craft_ui and main.craft_ui.gear_open:   # 撮っているあいだに窓へ入ったキー（I）で開いた装備の画面は閉じる
		main.craft_ui.close_gear()
	return false


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	print("保存: ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	await _wait(2.0)
	var mm: Node3D = main.mountain_man
	var p: Node3D = main.player
	var who: int = p.id
	var cam := Camera3D.new()
	cam.cull_mask &= ~(1 << 2)
	cam.fov = 55
	main.add_child(cam)
	var c := mm.to_global(Vector3(-1.4 * mm.rack_side * -1.0, 0.6, 0.0))
	cam.look_at_from_position(c + (mm.to_global(Vector3(0.4, 1.0, -3.4)) - mm.global_position), c)
	cam.make_current()
	p.doll.visible = false
	await _wait(1.5)
	await _shot("pen")
	cam.queue_free()
	p.doll.visible = true
	p.cam.make_current()
	var at := mm.to_global(Vector3(0, 0.1, -1.9))
	p.global_position = at
	p.rotation.y = atan2(-(mm.global_position.x - at.x), -(mm.global_position.z - at.z))
	await _wait(1.0)
	main.mountain_ui.open()
	await _wait(0.8)
	await _shot("tools")
	main.mountain_ui.open_pets()
	await _wait(1.0)
	await _shot("pets")
	main.craft.send({"kind": "earn", "who": who, "n": 40, "at": p.global_position})   # カエル（40）が買えるように
	await _wait(1.2)
	var ui = main.minion_ui
	var i: int = ui.keys().find("frog")
	print("連れの段だけ: ", ui.tabs)
	print("カエルを買う: ", ui.choose(i), "  持っている ", main.craft.pal_owned(who, "frog"), "  連れている ", main.craft.pal_worn(who, "pet"),
			"  財布 ", main.craft.wallet(who))
	await _wait(0.6)
	await _shot("pets_bought")
	ui.close()
	await _wait(2.0)
	await _shot("walk")
	var shop = main.get("paper_shop_ui")   # 2 階の小物の店は紙細工屋さん（#125）
	if shop:
		shop.open()
		await _wait(1.0)
		await _shot("stall")
		shop.close()
	_restore_tag()
	quit(0)
