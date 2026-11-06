extends SceneTree
## 滑りあとの柄を買って、ソリごとに設定して滑るまでの確かめ（絵と数字）。
## 一人で:
##   Godot --path game --resolution 1280x720 -s res://tools/stitch_shop_check.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 2 つ起動して（ホストを先に。あとから入る人に、置いてあるソリの柄が届くことも見る）:
##   Godot --path game --resolution 960x540 -s res://tools/stitch_shop_check.gd -- --host --port=24781 --bots=0 --no-sound --no-pip --dir=/path/host
##   Godot --path game --resolution 960x540 -s res://tools/stitch_shop_check.gd -- --join=127.0.0.1 --port=24781 --bots=0 --no-sound --no-pip --dir=/path/join
## 通信では、ホストがソリを置いて柄を付ける → つなぐ側に届く → つなぐ側が自分のソリの柄を替える → ホストが滑らせて、両方の画面で同じ柄の跡が出るかを見る

const Stitches := preload("res://stitches.gd")
const Tags := preload("res://sled_tags.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var craft: Node
var ui: CanvasLayer
var fails := 0
var _saved := PackedByteArray()   # 始めの保存ファイル。買った柄を試すので、終わったら元に戻す（本当の持ち物を汚さない）


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_saved = FileAccess.get_file_as_bytes("user://my_tag.cfg")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _dir() -> String:
	return String(args.get("dir", "/tmp/stitch"))


func _ok(c: bool, what: String) -> void:
	print(("○ " if c else "× ") + what)
	if not c:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [_dir(), name])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	await _wait(1.5)
	p = main.player
	craft = main.craft
	ui = main.craft_ui
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
	# 売り台: 棚を替えて、柄を選んで買う
	ui.open_shop()
	ui.shop_page = 1
	await _shot("01_shop_shelf")
	var fly: int = ui._stitch_goods.find("fly")
	var coins: int = craft.wallet(me)
	ui.select(fly)
	await _shot("02_shop_selected")
	_ok(ui.buy(), "フライを買えた")
	_ok(craft.wallet(me) == coins - Stitches.price("fly"), "財布から値段のぶん減った")
	_ok(craft.free_slot(me) >= 0 and craft.count(me) == 0, "持ち物の場所は使わない")
	_ok(not ui.buy(), "同じ柄は二度買えない")
	ui.select(ui._stitch_goods.find("cross"))
	ui.buy()
	await _shot("03_shop_bought")
	ui.close_shop()
	craft.wallets[me] = 0
	_ok(not craft.send({"kind": "stitch_buy", "who": me, "stitch": "garden"}), "ボタンが足りないと買えない")
	# 持ち物の画面: 米袋に柄を付ける
	ui.open_gear()
	ui.tag_page = Tags.PAGES.size()
	await _shot("04_gear_stitch")
	ui.stitch_edit = {"sack": 0}
	_ok(ui.set_stitch("fly"), "米袋にフライを付けた")
	_ok(craft.sack(me).get("stitch", "") == "fly", "米袋の表に入った")
	_ok(not ui.set_stitch("garden"), "買っていない柄は付けられない")
	# 自分のソリ・他の人のソリ
	var at := Vector3(14.0, 0, -30.0)
	at.y = main.height(at.x, at.z) + 0.6
	var design: Dictionary = craft.tag_designs.get(me, {})
	var mine: int = craft._place("mid", "navy", at, 0.0, 0, Vector3.UP, design, false, me)
	var other: int = craft._place("mid", "navy", at + Vector3(4, 0, 0), 0.0, 0, Vector3.UP, design, false, 99)
	await _wait(0.2)
	var s: RigidBody3D = craft.sleds[mine]
	ui.stitch_edit = {"id": mine}
	await _shot("05_gear_stitch_sled")
	_ok(ui.set_stitch("cross"), "自分のソリにクロスを付けた")
	_ok(s.stitch_kind() == "cross", "ソリの柄が替わった")
	await _shot("06_gear_stitch_set")
	_ok(not craft.send({"kind": "sled_stitch", "who": me, "id": other, "stitch": "cross"}), "他の人のソリは替えられない")
	_ok((craft.sleds[other] as Node).stitch_kind() == "chain", "他の人のソリは標準のまま")
	ui.close_gear()
	# 畳んだ包み（中のソリは畳めないので、包みを持ち物に入れて）: 柄を替えて、広げても同じ柄
	var slot: int = craft._put(me, {"kind": "folded", "sled": "mid", "fabric": "navy", "tag": design})
	_ok(craft.send({"kind": "sled_stitch", "who": me, "slot": slot, "stitch": "cross"}), "畳んだままでも替えられる")
	_ok(craft.bag(me)[slot].get("stitch", "") == "cross", "畳んだ包みに柄が入る")
	craft.sleds[mine].queue_free()
	craft.sleds.erase(mine)
	_ok(craft.send({"kind": "unfold", "who": me, "slot": slot, "item": craft.bag(me)[slot].duplicate(), "at": at, "yaw": 0.0}), "広げた")
	await _wait(3.0)
	var open_id := -1
	for id in craft.sleds:
		if id != other:
			open_id = id
	s = craft.sleds[open_id]
	_ok(s.stitch_kind() == "cross", "広げても同じ柄")
	# 替えたソリで滑る（途中で柄を替えても、前の跡は残る）
	s.linear_velocity = Vector3.ZERO
	s.parked = false
	s.rotation.y = -PI / 2
	p.global_position = s.global_position + Vector3.UP * 0.5
	p.last_sled = s
	p.sled = s
	p.get_on()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	var cam := Camera3D.new()
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	var t := 0.0
	var left := 0
	while t < 12.0:
		var fwd: Vector3 = -s.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		cam.global_position = s.global_position - fwd * 6.5 + Vector3.UP * 3.0
		cam.look_at(s.global_position - fwd * 2.0, Vector3.UP)
		cam.current = true
		await process_frame
		t += root.get_process_delta_time()
		if t > 6.0 and left == 0:
			await _shot("07_ride_cross")
			left = s._trail_used
			ui.stitch_edit = {"id": open_id}
			_ok(ui.set_stitch("fly"), "滑りながら柄を替えた")
	await _shot("08_ride_changed")
	_ok(s.stitch_kind() == "fly" and s._trail_used > 0, "替えたあとの柄で跡が出る")
	_ok(left > 0, "替える前の柄で跡が出ていた")
	# 保存: 買った柄を読み直せる
	p.save_tag()
	var cf := ConfigFile.new()
	cf.load(p.TAG_FILE)
	_ok("fly" in cf.get_value("stitch", "owned", []), "買った柄を保存した")
	craft.stitch_owned[me] = []
	var sk: Dictionary = craft.sacks[me][0]
	sk.erase("stitch")
	craft.sacks[me][0] = sk
	p._load_tag()
	_ok("fly" in craft.stitch_owned[me], "次の起動で、買った柄が戻る")
	_ok(craft.sack(me).get("stitch", "") == "fly", "次の起動で、標準の米袋の柄が戻る")


func _net_flow() -> void:
	var host: bool = args.has("host")
	var me: int = p.id
	if host:
		var at := Vector3(14.0, 0, -30.0)
		at.y = main.height(at.x, at.z) + 0.6
		craft.wallets[me] = 1000
		craft.send({"kind": "stitch_buy", "who": me, "stitch": "fly"})
		var design: Dictionary = craft.tag_designs.get(me, {})
		var id: int = craft._place("mid", "navy", at, 0.0, 0, Vector3.UP, design, false, me)
		_ok(craft.send({"kind": "sled_stitch", "who": me, "id": id, "stitch": "fly"}), "ホストが自分のソリにフライを付けた")
		while main.net.remotes.is_empty():
			await physics_frame
		print("つなぐ側が入った")
		await _wait(5.0)   # つなぐ側が柄を確かめて、替えるのを待つ
		var them: int = main.net.remotes.keys()[0]
		_ok(craft.stitch_owned.get(them, []).has("back"), "つなぐ側が買った柄がホストに届いた")
		_ok(String(craft.sacks.get(them, [{}])[0].get("stitch", "")) == "back", "つなぐ側の米袋の柄がホストに届いた")
		var s: RigidBody3D = craft.sleds[id]
		print("ホストのソリの柄=", s.stitch_kind())
		_ok(s.stitch_kind() == "fly", "ホストの画面でフライ")
		await _slide(s)
	else:
		while craft.sleds.is_empty():
			await physics_frame
		await _wait(1.0)
		var id: int = craft.sleds.keys()[0]
		var s: RigidBody3D = craft.sleds[id]
		_ok(s.stitch_kind() == "fly", "あとから入っても、置いてあるソリの柄が届いた")
		me = p.id
		craft.send({"kind": "sled_stitch", "who": me, "id": id, "stitch": "running"})   # 他の人のソリを替えようとする（ホストが断るはず）
		craft.send({"kind": "stitch_buy", "who": me, "stitch": "back"})
		craft.send({"kind": "sled_stitch", "who": me, "sack": 0, "stitch": "back"})
		await _wait(1.0)
		_ok(craft.stitch_owned.get(me, []).has("back"), "つなぐ側が柄を買えた（ホストが確かめて返した）")
		_ok(s.stitch_kind() == "fly", "他の人のソリの柄は替わらない")
		await _slide(s)


## ソリを 8 秒滑らせ（ホストの画面が動かす）、この画面でも跡が出ているかを見る。カメラは後ろ上
func _slide(s: RigidBody3D) -> void:
	var cam := Camera3D.new()
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	var host: bool = args.has("host")
	if host:
		s.parked = false
		s.rotation.y = -PI / 2
	var t := 0.0
	while t < 9.0:
		if host and t < 7.0:
			s.linear_velocity = Vector3(7.0, s.linear_velocity.y, 0.0)
		cam.global_position = s.global_position + Vector3(-7.0, 3.5, 0.0)
		cam.look_at(s.global_position + Vector3(-2.0, 0, 0), Vector3.UP)
		cam.current = true
		await physics_frame
		t += 1.0 / 60.0
	print("柄=%s 目の数=%d" % [s.stitch_kind(), s._trail_used])
	_ok(s.stitch_kind() == "fly", "この画面でもフライ")
	_ok(s._trail_used > 20, "この画面でも跡が出た")
	await _shot("net_%s" % ("host" if host else "join"))
