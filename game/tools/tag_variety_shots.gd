extends SceneTree
## 名札の幅（sled_tags.gd の部品）を、名札が出る所で確かめて撮る。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/tag_variety_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots [--only=0,5]
## 1. はじめの名札のまま装備の画面（I）を 4 ページ: あとで手に入る部品は薄く、木のボタンの印
## 2. あとで手に入る部品を全部手に入れたことにして、組み合わせの例（tools/tag_sheet.gd の COMBOS）を順に付ける。例ごとに
##    装備の画面（持ち物の列に、自分の名札の付いた畳んだソリ）、縫ったソリに吊るした名札の寄り（左下の札も写る）、
##    米袋（N で出して乗り、前から見る）を撮る

const Sheet := preload("res://tools/tag_sheet.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var cam: Camera3D
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/tag_variety")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame


func _at(x: float, z: float, lift := 0.15) -> Vector3:
	return Vector3(x, main.height(x, z) + lift, z)


## 吊るした名札の紙（Tag の下の一番大きい板）を、表から寄って見る
func _look_tag(s: Node3D, dist := 0.62, lift := 0.12) -> bool:
	var tg := s.get_node_or_null("Tag") as Node3D
	if tg == null:
		return false
	var face: Node3D = null
	for ch in tg.get_children():
		if ch is MeshInstance3D and ch.mesh is QuadMesh:
			face = ch
			break
	var at: Vector3 = face.global_position if face else tg.global_position
	var n: Vector3 = tg.global_basis.z.normalized()
	cam.global_position = at + n * dist + Vector3(0, lift, 0)
	cam.look_at(at, Vector3.UP)
	cam.make_current()
	return true


func _run() -> void:
	await _wait(2.5)
	p = main.player
	p.set_third(false)
	cam = Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	var c: Node = main.craft
	var ui = main.craft_ui
	var who: int = p.id
	_say("はじめの名札 %s" % [c.tag_designs[who]])
	# 縫ったソリを 1 台（自分の名札が付く）
	c.send({"kind": "sewn", "who": who, "sled": "mid", "fabric": "navy", "at": _at(6.0, 30.0), "yaw": 0.3})
	await _wait(0.8)
	var mine: Node3D = null
	for s in get_nodes_in_group("sleds"):
		if int(s.get("owner_id")) == who:
			mine = s
	_say("縫ったソリ %s" % [mine])
	p.global_position = _at(0.0, 26.0, 0.2)
	p.rotation.y = PI
	c.bags[who] = [{"kind": "folded", "sled": "mid", "fabric": "navy", "tag": c.tag_designs[who]}]
	# 1. はじめの名札で、装備の画面の 4 ページ
	await _key(KEY_I)
	for k in 4:
		ui.tag_page = k
		await _wait(0.3)
		await _shot("00_locked_page%d" % (k + 1))
	_say("まだ手に入れていない部品は選べない: %s" % (not ui.set_tag_part("shape", 9, false)))
	ui.close_gear()
	# 2. あとで手に入る部品を全部手に入れる
	var Tags := preload("res://sled_tags.gd")
	for part in Tags.PARTS:
		for i in range(Tags.STARTER[part], Tags.part_count(part)):
			c.send({"kind": "tag_unlock", "who": who, "part": part, "index": i})
	_say("手に入れた部品 %s" % [c.tag_owned[who]])
	var only: Array = []
	for s in String(args.get("only", "")).split(",", false):
		only.append(int(s))
	for k in Sheet.COMBOS.size():
		if not only.is_empty() and not k in only:
			continue
		var d := Sheet.combo(k)
		c.send({"kind": "tag_design", "who": who, "design": d})
		_say("例 %d: %s 付いた %s" % [k + 1, d, c.tag_designs[who] == d])
		c.bags[who] = [{"kind": "folded", "sled": "mid", "fabric": "navy", "tag": d}, {"kind": "folded", "sled": "small", "fabric": "mustard", "tag": d}]
		p.global_position = _at(0.0, 26.0, 0.2)
		p.rotation.y = PI
		p.set("_pitch", -0.1)
		await _key(KEY_I)
		ui.tag_page = k % 4
		await _wait(0.35)
		await _shot("%02d_gear" % (k + 1))
		ui.close_gear()
		await _wait(0.4)
		if mine and _look_tag(mine):
			await _wait(0.5)   # 名札の絵（SubViewport）が描けるまで
			await _shot("%02d_sled" % (k + 1))
		p.cam.make_current()
		if k % 4 == 0:   # 米袋: N で出して乗り、降りて前から見る
			await _key(KEY_N)
			await _wait(0.8)
			var sack: Node3D = c.sack_sled(who)
			if sack:
				p.get_off()
				await _wait(0.3)
				(sack as RigidBody3D).freeze = true   # 撮る間は滑らないよう止める
				if _look_tag(sack, 0.5, 0.32):
					await _wait(0.5)
					await _shot("%02d_sack" % (k + 1))
				(sack as RigidBody3D).freeze = false
				p.cam.make_current()
				await _key(KEY_N)
				await _wait(0.5)
				if c.sack_sled(who):
					p.sled = c.sack_sled(who)
					p.call("toggle_sack")
	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
