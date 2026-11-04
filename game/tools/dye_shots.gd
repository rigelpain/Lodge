extends SceneTree
## 2 階の染め桶と、服を染める画面を撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/dye_shots.gd -- --spawn=dye --doll=kasa --dir=/path/shots [--kinds=robo,golem]
## 撮るもの:
##   vat.png          染め桶の前（F の案内）
##   vat_near.png     染め桶を近くから（衣装掛けのとなり）
##   menu.png         F で開いた、服を染める画面（もとの色）
##   menu_part<n>.png 部位 n（1〜4）を選んで、その部位に色を入れたところ（人形のその部位に輪郭が出て、その内側が微光で点滅する。染め代が部位の数で上がる）
##   menu_pick.png    4 部位とも色を選んだところ（見本の人形が染まる。染め代の札が押せる）
##   menu_bleach.png  染めたあと、2 番目と 4 番目の部位の下の丸い布を押して脱色したところ（見本の人形のその部位がもとの色に）
##   bleached_menu.png 脱色したあと（脱色はただ）
##   dyed_tp.png      染めたあと、三人称（うしろから、少し横に回って）。桶の液も同じ色に
##   dyed_fp.png      同じく一人称（袖と手も染まる）
##   dyed_vat.png     染めたあとの染め桶（液と縁の布が、染めた色に）
##   <人形>_tp.png   7 体それぞれ、染めた人形の三人称
##   wardrobe_menu.png  衣装掛けの画面（染めた人形は札の中でも染めた色）
##   friend<n>.png    仲間（bot.gd）の人形を染めた（通信で、ほかの人の画面にも染めた色が見える代わり）
## 染めるのは craft.gd の出来事 dye を直接送る（保存はしない）
## --grid を付けると、上の代わりに、7 体 × 4 部位の札の中だけを撮る（部位のハイライトの確かめ）:
##   <人形>_<部位 0〜3>_<base か dyed>_<front か back>.png   もとの色か染めた色で、前か後ろから。光のいちばん強い所で
##   <人形>_<部位 0〜3>_<base か dyed>_<front か back>_off.png   同じ所を、光のいちばん弱い所で

const Doll := preload("res://doll.gd")
const Bot := preload("res://bot.gd")
const Icons := preload("res://hud_icons.gd")

## 人形ごとに染める色（部位ごと 4 つ。outfit.gd の PARTS の順）
const DYES := {
	"kasa": ["c9603c", "6a4c93", "efe6d2", "2f6b4a"], "origami": ["3f6b4a", "d8a43e", "c97a8a", "34477e"],
	"news": ["7a4a6e", "d8a43e", "34477e", "e0e0d0"], "robo": ["d8a43e", "6f8fb8", "c9603c", "3f6b4a"],
	"musha": ["7a2e2a", "2f2f2f", "d8a43e", "d4b54a"], "ningyo": ["34477e", "f0d8e0", "c9603c", "3f6b4a"],
	"golem": ["c9603c", "3f6b4a", "d8a43e", "6a4c93"],
}

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/dye_shots")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


## 自由なカメラで撮って、あなたのカメラに戻す
func _look_shot(name: String, from: Vector3, to: Vector3) -> void:
	var cam := Camera3D.new()
	cam.fov = 50
	main.add_child(cam)
	cam.look_at_from_position(from, to)
	cam.make_current()
	main.player.doll.visible = false   # あなたの人形が前をふさがないように
	await _wait(0.5)
	await _shot(name)
	cam.queue_free()
	main.player.doll.visible = true
	main.player.cam.make_current()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _dye(who: int, kind: String, cols: Array) -> bool:
	return main.craft.send({"kind": "dye", "who": who, "doll": kind, "colors": cols})


## 札の中だけを切り抜いて保存する（dye_ui.gd の _draw_on の札の場所）
func _card_shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var vs := Vector2(img.get_size())
	var u := Icons.ui_scale(vs.y)
	var bw := minf(960.0 * u, vs.x - 60.0 * u)
	var bh := minf(600.0 * u, vs.y - 60.0 * u)
	var ch := bh - 70.0 * u
	var at := (vs - Vector2(bw, bh)) / 2.0 + Vector2(36.0 * u, 36.0 * u)
	var size := Vector2(ch * main.dye_ui.SHOT.x / main.dye_ui.SHOT.y, ch)
	img.get_region(Rect2i(at, size)).save_png(_dir().path_join(name + ".png"))


func _grid() -> void:
	var p: CharacterBody3D = main.player
	var ui = main.dye_ui
	main.craft.wallets[p.id] = 500
	var kinds: Array = Doll.KINDS if not args.has("kinds") else Array(String(args.kinds).split(","))
	for k in kinds:
		main.craft.send({"kind": "doll", "who": p.id, "doll": k})
		await _wait(0.5)
		ui.open()
		await _wait(0.5)
		for tint in ["base", "dyed"]:
			for i in 4:
				ui._pick[i] = Color(DYES[k][i]) if tint == "dyed" else null
			ui._show_pick()
			for side in ["front", "back"]:
				ui._spin.rotation.y = 0.5 if side == "front" else 0.5 + PI
				for i in 4:
					ui._cloth = i
					ui._blink = 0.0
					await _card_shot("%s_%d_%s_%s" % [k, i, tint, side])
					ui._blink = ui.BLINK / 2.0
					await _card_shot("%s_%d_%s_%s_off" % [k, i, tint, side])
		ui.close()
		print("撮った: ", k)
	quit()


func _run() -> void:
	await _wait(4.0)
	if args.has("grid"):
		await _grid()
		return
	var p: CharacterBody3D = main.player
	var v: Node3D = main.dye_vat
	main.craft.wallets[p.id] = 500
	print("染め桶: ", v.global_position, " あなた: ", p.global_position, " 開ける: ", p.dye_near())
	await _wait(1.5)
	await _shot("vat")
	var front: Vector3 = v.global_basis.z
	var side: Vector3 = v.global_basis.x
	await _look_shot("vat_near", v.global_position + front * 1.7 - side * 0.9 + Vector3.UP * 1.5, v.global_position + Vector3.UP * 0.35 - side * 0.6)
	var ui = main.dye_ui
	ui.open()
	await _wait(1.0)
	await _shot("menu")
	var mine: Array = DYES[p.doll.kind]
	for i in 4:   # 部位を 1 つずつ選んで、色の輪で色を入れる
		ui._cloth = i
		var c := Color(mine[i])
		ui._hsv = Vector3(c.h, c.s, c.v)
		ui._set_from_hsv()
		await _wait(0.45)
		await _shot("menu_part%d" % (i + 1))
	await _wait(0.4)
	await _shot("menu_pick")
	var before: int = main.craft.wallet(p.id)
	print("染める: ", _dye(p.id, p.doll.kind, main.craft.dye_colors(p.doll.kind, ui._pick)), " 財布 ", before, " → ", main.craft.wallet(p.id))
	print("同じ色でもう一度（断られるはず）: ", _dye(p.id, p.doll.kind, main.craft.dye_colors(p.doll.kind, ui._pick)))
	await _wait(1.5)
	await _shot("dyed_menu")
	ui.bleach(1)   # 2 番目と 4 番目を脱色（もとの色に戻す）
	ui.bleach(3)
	await _wait(0.5)
	await _shot("menu_bleach")
	before = main.craft.wallet(p.id)
	print("脱色（2 部位。ただのはず）: ", _dye(p.id, p.doll.kind, main.craft.dye_colors(p.doll.kind, ui._pick)), " 財布 ", before, " → ", main.craft.wallet(p.id),
			" 服 ", main.craft.outfits[p.id].get(p.doll.kind))
	await _wait(1.5)
	await _shot("bleached_menu")
	for i in 4:   # 次の 7 体の撮影のために、もう一度 4 部位とも染めた色に
		ui._pick[i] = Color(DYES[p.doll.kind][i])
	_dye(p.id, p.doll.kind, main.craft.dye_colors(p.doll.kind, ui._pick))
	ui.close()
	p.set_third(true)
	p.rotation.y = v.global_rotation.y + PI * 0.8
	await _wait(1.5)
	await _shot("dyed_tp")
	p.set_third(false)
	await _wait(0.6)
	await _shot("dyed_fp")
	await _look_shot("dyed_vat", v.global_position + front * 1.5 + side * 0.4 + Vector3.UP * 1.3, v.global_position + Vector3.UP * 0.35)
	var kinds: Array = Doll.KINDS if not args.has("kinds") else Array(String(args.kinds).split(","))
	for k in kinds:
		main.craft.send({"kind": "doll", "who": p.id, "doll": k})
		await _wait(0.4)
		_dye(p.id, k, DYES[k])
		p.set_third(true)
		await _wait(1.2)
		print(k, ": 人形=", p.doll.kind, " 服=", p.doll.outfit, " 手=", p.hands.size())
		await _shot(k + "_tp")
	# 衣装掛けの画面: 染めた 7 体が、札の中でも染めた色で回る
	p.set_third(false)
	main.wardrobe_ui.open()
	await _wait(1.2)
	await _shot("wardrobe_menu")
	main.wardrobe_ui.close()
	# 仲間の人形を染める（ほかの人が染めた出来事が届いたときと同じ）
	var bots := main.get_children().filter(func(c): return c.get_script() == Bot)
	for b in bots:
		main.craft.wallets[b.id] = 500   # 4 部位ぶんの染め代
		_dye(b.id, b.doll.kind, DYES[b.doll.kind])
		print("仲間 ", b.id, ": ", b.doll.kind, " 服=", b.doll.outfit)
	await _wait(1.0)
	for i in bots.size():
		var b: Node3D = bots[i]
		var at: Vector3 = b.doll.global_position
		var ahead: Vector3 = (b.sled.global_position - at) if b.get("sled") else Vector3.FORWARD   # 押しているソリの方が前
		ahead.y = 0
		ahead = ahead.normalized()
		var across := ahead.cross(Vector3.UP)
		await _look_shot("friend%d" % i, at + ahead * 1.3 + across * 1.8 + Vector3.UP * 1.2, at + Vector3.UP * 0.6)
	p.set_third(false)
	quit()
