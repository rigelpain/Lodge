extends SceneTree
## ソリの見本帳（sled_book.gd・sled_book_ui.gd・craft.gd の sled_dye）の確かめ（絵と数字）。
## 一人で（絵がいるので画面あり。--dir がなければ絵は撮らない。--headless でも数字は見られる）:
##   Godot --path game --resolution 1920x1080 -s res://tools/sled_book_check.gd -- --bots=0 --lodge-bots=0 --no-sound --no-pip --no-buttons --dir=/path
## 2 つ起動して（ホストを先に。あとから入る人に、染めた色が届くことも見る）:
##   Godot --headless --path game -s res://tools/sled_book_check.gd -- --host --port=24791 --bots=0 --lodge-bots=0 --no-sound --no-pip --no-buttons
##   Godot --headless --path game -s res://tools/sled_book_check.gd -- --join=127.0.0.1 --port=24791 --bots=0 --lodge-bots=0 --no-sound --no-pip --no-buttons

const Fabrics := preload("res://fabrics.gd")
const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

const TEAL := "#2F7F8F"
const PLUM := "#7A4A6E"

var args := {}
var main: Node3D
var p: CharacterBody3D
var craft: Node
var ui: CanvasLayer
var fails := 0
var _saved := PackedByteArray()   # 始めの保存ファイル（終わったら元に戻す）


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_saved = FileAccess.get_file_as_bytes("user://my_tag.cfg")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	if not args.has("dir"):
		return
	DirAccess.make_dir_recursive_absolute(args.dir)
	await _wait(0.3)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.dir).path_join(name + ".png"))
	print("絵: ", name)


func _lodge(x: float, y: float, h := 0.0) -> Vector3:
	return main.get_node("Lodge").to_global(Vector3(x, h, -y))


func _near(a: Color, hex: String) -> bool:
	return a.is_equal_approx(Color.html(hex))


func _place(kind: String, fabric: String, at: Vector3) -> int:
	return craft._place(kind, fabric, at, 0.0, 0, Vector3.UP, craft.tag_designs.get(p.id, {}), false, p.id)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, main.height(x, z) + 0.3, z)


func _run() -> void:
	await _wait(3.0)
	p = main.player
	craft = main.craft
	ui = main.sled_book_ui
	if args.has("host") or args.has("join"):
		await _net_flow()
	else:
		await _solo()
	print("確かめ: %s（× %d）" % ["よし" if fails == 0 else "だめ", fails])
	if not _saved.is_empty():
		var f := FileAccess.open("user://my_tag.cfg", FileAccess.WRITE)
		f.store_buffer(_saved)
		f.close()
	quit(0 if fails == 0 else 1)


func _solo() -> void:
	var me: int = p.id
	craft.wallets[me] = 1000
	var dc := root.get_node_or_null("DayCycle")
	if dc:
		dc.hour = 11.0
		dc.day_seconds = 1.0e9
	# 見本帳の前で本物の F キー
	var book: Node3D = main.sled_book
	p.global_position = book.to_global(Vector3(0, 0.2, 2.6))
	var to := book.global_position
	p.rotation.y = atan2(-(to.x - p.global_position.x), -(to.z - p.global_position.z))
	p._pitch = 0.0
	await _wait(1.5)
	_ok(p.book_near(), "見本帳の前で book_near")
	await _shot("01_book_front")
	var snow_id := _place("mid", "navy", _ground(14.0, -30.0))
	var s: RigidBody3D = craft.sleds[snow_id]
	await _wait(1.2)
	s.parked = true
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.3)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_F
	up.keycode = KEY_F
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(0.2)
	if not ui.is_open and DisplayServer.get_name() == "headless":
		ui.open()
	_ok(ui.is_open, "F で画面が開く")
	ui.select({"id": snow_id})
	_ok(s.linear_velocity.length() < 1.0, "雪の上のソリは止まっている")
	await _shot("02_screen_open")

	# ---- 雪の上のソリ: 布の色 + 買う柄
	ui._press("swatch5", Vector2.ZERO)
	ui._press("stitch%d" % (Stitch_list().find("fly")), Vector2.ZERO)
	await _shot("03_swatch_and_buy_stitch")
	var before: int = craft.wallets[me]
	var want: int = craft.sled_dye_price("mid") + preload("res://stitches.gd").price("fly")
	_ok(ui.price_now() == want, "払う分 = 染め代 + 柄の値段 (%d)" % want)
	_ok(ui.apply(), "決める")
	await _wait(0.1)
	_ok(craft.wallets[me] == before - want, "ボタンがその分減る (%d → %d)" % [before, craft.wallets[me]])
	_ok(s.fabric == TEAL and s.base_fabric == "navy", "ソリが染まり、元の布を覚えている (%s / %s)" % [s.fabric, s.base_fabric])
	_ok(_near(s.color(), TEAL), "ソリのメインカラー = 選んだ色（滑りあとの糸も s.color()）")
	_ok(s.stitch_kind() == "fly", "柄が替わった")
	_ok("fly" in craft.stitch_owned[me], "柄を買った")
	# ---- 色の輪: 自由な色（本物の押し方）
	ui._press("wheel", ui._wheel_c + Vector2(ui._wheel_r * 0.6, -ui._wheel_r * 0.3))
	ui._drag = ""
	ui._press("value", (ui._rects["value"] as Rect2).get_center())
	ui._drag = ""
	var free_col: Color = ui.picked_color()
	_ok(ui._color_changed(), "色の輪で自由な色を選べる")
	await _shot("04_free_color_wheel")
	before = craft.wallets[me]
	_ok(ui.apply(), "自由な色で染める")
	await _wait(0.1)
	_ok(s.color().is_equal_approx(Color.html(s.fabric)) and Fabrics.is_dyed(s.fabric), "自由な色が付いた (%s)" % s.fabric)
	_ok(s.base_fabric == "navy", "染め直しても元の布は navy のまま")
	_ok(craft.wallets[me] == before - craft.sled_dye_price("mid"), "染め代だけ減る")
	# ---- 足りないとき
	var keep: int = craft.wallets[me]
	craft.wallets[me] = 5
	ui._press("swatch1", Vector2.ZERO)
	_ok(not ui.can_apply(), "足りないと決められない")
	await _shot("05_cannot_pay")
	_ok(not ui.apply(), "決めても通らない")
	_ok(not craft.send({"kind": "sled_dye", "who": me, "id": snow_id, "color": PLUM}), "足りないとホストが断る")
	_ok(craft.wallets[me] == 5, "ボタンは減らない")
	# 買えない柄は選べない
	var dear: int = Stitch_list().find("garden")
	var st_before: String = ui._stitch
	ui._press("stitch%d" % dear, Vector2.ZERO)
	_ok(ui._stitch == st_before, "買えない柄は選べない")
	craft.wallets[me] = keep
	# ---- 元の色に戻す（ただ）
	before = craft.wallets[me]
	_ok(ui.bleach(), "元の色に戻す")
	await _wait(0.1)
	_ok(s.fabric == "navy" and s.base_fabric == "" and _near(s.color(), "34477E"), "元の布に戻った")
	_ok(craft.wallets[me] == before, "戻すのはただ")
	_ok(not ui.bleach(), "染めていなければ戻せない")
	# ---- 乗っている・動いているソリ
	var d := GDScript.new()
	d.source_code = DUMMY_SRC
	d.reload()
	var rider := Node3D.new()
	rider.set_script(d)
	rider.sled = s
	main.add_child(rider)
	s.mount(rider)
	_ok(craft.sled_busy(s), "乗っていると使用中")
	_ok(not craft.send({"kind": "sled_dye", "who": me, "id": snow_id, "color": TEAL}), "乗っているソリは染めない")
	ui.select({"sack": 0})
	await _shot("06_busy_target")
	ui.select({"id": snow_id})
	s.dismount(rider)
	rider.queue_free()
	s.linear_velocity = Vector3(4, 0, 0)
	await physics_frame
	_ok(craft.sled_busy(s), "動いていると使用中")
	_ok(not craft.send({"kind": "sled_dye", "who": me, "id": snow_id, "color": TEAL}), "動いているソリは染めない")
	_ok(s.fabric == "navy", "色は変わらない")
	s.linear_velocity = Vector3.ZERO
	await _wait(0.2)
	# ---- 持ち主でないソリ
	var other: int = craft._place("mid", "red", _ground(20.0, -30.0), 0.0, 0, Vector3.UP, 0, false, -1)
	_ok(not craft.send({"kind": "sled_dye", "who": me, "id": other, "color": TEAL}), "持ち主でないソリは染めない")
	# ---- 畳む・広げるで色が残る
	# 畳めるのは米袋の形だけ（craft.gd の foldable）。縫った米袋で、染めて畳む
	var fold_id := _place("sack", "navy", _ground(14.0, -24.0))
	await _wait(1.0)
	craft.sleds[fold_id].linear_velocity = Vector3.ZERO
	_ok(craft.send({"kind": "sled_dye", "who": me, "id": fold_id, "color": TEAL}), "雪の上の米袋を染める")
	var f := {"kind": "fold", "who": me, "id": fold_id}
	_ok(craft.send(f), "畳む")
	var slot: int = f.slot
	var it: Dictionary = craft.bag(me)[slot]
	_ok(it.fabric == TEAL and it.base == "navy", "畳んだ包みに色と元の布")
	# 畳んだ中のソリ（持ち物の包み。stitch_shop_check.gd と同じ入れ方）を、畳んだまま染める
	slot = craft._put(me, {"kind": "folded", "sled": "mid", "fabric": "navy", "tag": craft.tag_designs.get(me, {})})
	it = craft.bag(me)[slot]
	# 畳んだまま染める
	_ok(craft.send({"kind": "sled_dye", "who": me, "slot": slot, "color": PLUM}), "畳んだソリを染める")
	it = craft.bag(me)[slot]
	_ok(it.fabric == PLUM and it.base == "navy", "包みの色が替わり、元の布はそのまま")
	await _wait(2.0)
	if ui.is_open:
		ui.select({"slot": slot})
		await _shot("07_folded_target")
	var u := {"kind": "unfold", "who": me, "slot": slot, "item": it.duplicate(), "at": _ground(14.0, -20.0), "yaw": 0.0}
	_ok(craft.send(u), "広げる")
	var s2: RigidBody3D = craft.sleds[u.id]
	await _wait(0.2)
	_ok(s2.fabric == PLUM and s2.base_fabric == "navy" and _near(s2.color(), PLUM), "広げても色と元の布が残る")
	# ---- 立てかけ台
	ui.close()
	var r_id := _place("large", "mustard", _ground(30.0, -30.0))
	var r_s: RigidBody3D = craft.sleds[r_id]
	await _wait(0.5)
	p.global_position = _lodge(-27.5, 3.0, 0.1)
	await _wait(0.2)
	_ok(craft.send({"kind": "rack_in", "who": me, "id": r_id}), "台に戻す")
	await _wait(1.8)
	before = craft.wallets[me]
	_ok(not craft.sled_busy(r_s), "台のソリは使用中でない")
	_ok(craft.send({"kind": "sled_dye", "who": me, "id": r_id, "color": TEAL}), "台のまま染める")
	_ok(craft.wallets[me] == before - craft.sled_dye_price("large"), "大の染め代")
	_ok(_near(r_s.color(), TEAL), "台のソリに色")
	if args.has("dir"):
		var cam := Camera3D.new()
		cam.fov = 55.0
		cam.cull_mask = (1 << 0) | (1 << 3)   # 世界と小物（台は小物の層）
		root.add_child(cam)
		cam.current = true
		cam.look_at_from_position(_lodge(-33.5, 1.5, 2.2), _lodge(-24.0, 3.5, 1.7))
		await _shot("08_rack_dyed")
		cam.queue_free()
	var o := {"kind": "rack_out", "who": me, "id": r_id}
	_ok(craft.send(o), "台から持ち出す")
	await _wait(1.5)
	_ok(r_s.fabric == TEAL and r_s.base_fabric == "mustard", "持ち出しても色が残る")
	# ---- 米袋と保存
	_ok(craft.send({"kind": "sled_dye", "who": me, "sack": 0, "color": PLUM}), "米袋を染める")
	_ok(craft.sacks[me][0].fabric == PLUM, "米袋の持ち物に色")
	p.save_tag()
	var cf := ConfigFile.new()
	cf.load("user://my_tag.cfg")
	_ok(String(cf.get_value("stitch", "sack_color", "")) == PLUM, "標準の米袋の色が保存される")
	_ok(not craft.send({"kind": "sled_dye_own", "who": me, "id": r_id, "color": PLUM}), "ただで染める出来事は米袋だけ")
	# ---- 閉じる（Esc と ×）
	ui.open()
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	ui._input(esc)
	_ok(not ui.is_open, "Esc で閉じる")
	ui.open()
	await process_frame
	await process_frame
	ui._press("close", Vector2.ZERO)
	_ok(not ui.is_open, "× で閉じる")
	# ---- 滑りあとの糸が色に合う（一人の絵）
	if args.has("dir"):
		await _trail_shot(s2)


func Stitch_list() -> Array:
	var St := preload("res://stitches.gd")
	return St.standard() + St.for_sale()


func _trail_shot(s: RigidBody3D) -> void:
	var cam := Camera3D.new()
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	s.parked = false
	s.set_stitch("fly")
	s.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), _ground(-30.0, 30.0))
	var t := 0.0
	while t < 5.0:
		s.linear_velocity = Vector3(6.0, s.linear_velocity.y, 0.0)
		cam.global_position = s.global_position + Vector3(-6.0, 3.0, 0.0)
		cam.look_at(s.global_position + Vector3(-2.0, 0, 0), Vector3.UP)
		cam.current = true
		await physics_frame
		t += 1.0 / 60.0
	await _shot("09_trail_thread_color")
	cam.queue_free()


func _net_flow() -> void:
	var host: bool = args.has("host")
	var me: int = p.id
	if host:
		craft.wallets[me] = 1000
		var a := _place("mid", "navy", _ground(14.0, -30.0))
		var b := _place("small", "red", _ground(18.0, -30.0))
		var r := _place("large", "mustard", _ground(30.0, -30.0))
		await _wait(1.5)
		_ok(craft.send({"kind": "sled_dye", "who": me, "id": a, "color": TEAL}), "入る前に、雪の上のソリを染める")
		_ok(craft.send({"kind": "sled_dye", "who": me, "id": b, "color": TEAL}), "入る前に、小のソリを染める")
		var slot: int = craft._put(me, {"kind": "folded", "sled": "mid", "fabric": "red", "tag": craft.tag_designs.get(me, {})})
		_ok(craft.send({"kind": "sled_dye", "who": me, "slot": slot, "color": PLUM}), "入る前に、畳んだ包みを染める")
		p.global_position = _lodge(-27.5, 3.0, 0.1)
		await _wait(0.2)
		_ok(craft.send({"kind": "sled_dye", "who": me, "id": r, "color": TEAL}), "入る前に、台のソリを染める")
		_ok(craft.send({"kind": "rack_in", "who": me, "id": r}), "台に戻す")
		print("待つ: つなぐ側")
		while main.net.remotes.is_empty():
			await physics_frame
		print("つなぐ側が入った")
		var them: int = main.net.remotes.keys()[0]
		var left := 90.0
		while left > 0.0 and String(craft.sacks.get(them, [{}])[0].get("fabric", "")) != TEAL:   # つなぐ側が届いた色を確かめて、米袋を染めるまで
			await _wait(0.25)
			left -= 0.25
		# 入ったあと: つなぐ側の目の前で染める
		_ok(craft.send({"kind": "sled_dye", "who": me, "id": a, "color": PLUM}), "入ったあとに染める")
		await _wait(3.0)
		var sp: Dictionary = craft.sacks.get(them, [{}])[0]
		_ok(String(sp.get("fabric", "")) == TEAL, "つなぐ側の米袋の色がホストに届いた")
		_ok(craft.sleds[a].fabric == PLUM, "つなぐ側が他の人のソリを替えようとしても替わらない")
		_ok(int(craft.wallets.get(them, -1)) == int(craft.START_BUTTONS) - craft.sled_dye_price("sack") if craft.get("START_BUTTONS") != null else true, "つなぐ側の染め代がホストで引かれた")
		await _wait(1.0)
	else:
		me = p.id
		while craft.sleds.size() < 3:
			await physics_frame
		await _wait(1.0)
		var a_s: Node3D = null
		var r_s: Node3D = null
		for id in craft.sleds:
			var s: Node3D = craft.sleds[id]
			if s.kind == "mid":
				a_s = s
			if s.kind == "large":
				r_s = s
		_ok(a_s != null and a_s.fabric == TEAL and a_s.base_fabric == "navy" and _near(a_s.color(), TEAL), "あとから入っても、雪の上のソリの色と元の布が届く")
		_ok(r_s != null and r_s.fabric == TEAL and r_s.base_fabric == "mustard" and r_s.racked, "あとから入っても、台のソリの色が届く")
		var host_id: int = -1
		for who in craft.bags:
			if int(who) != me:
				host_id = int(who)
		var folded := {}
		for it in craft.bags.get(host_id, []):
			if it.get("kind") == "folded":
				folded = it
		_ok(folded.get("fabric", "") == PLUM and folded.get("base", "") == "red", "あとから入っても、畳んだ包みの色が届く")
		# 他の人のソリを替えようとする（ホストが断る）
		craft.send({"kind": "sled_dye", "who": me, "id": int(a_s.get_meta("craft_id")), "color": "#112233"})
		# 自分の米袋を染める
		craft.send({"kind": "sled_dye", "who": me, "sack": 0, "color": TEAL})
		await _wait(5.0)
		_ok(a_s.fabric == PLUM and _near(a_s.color(), PLUM), "ホストが染めた色が届く（他の人の出来事は断られた）")
		_ok(String(craft.sacks[me][0].get("fabric", "")) == TEAL, "自分の米袋が染まった（ホストが確かめて返した）")
		await _wait(1.0)
