extends SceneTree
## ランタンの形違い（lantern.gd の LOOK）と、番台の横のランタン掛け（lantern_rack.gd・lantern_ui.gd）を確かめて撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/lantern_variety_shots.gd -- --part=line --no-sound --no-pip --dir=/path/shots
##   --part=line   夜の雪の上に 10 体の人形を並べ、帯にそれぞれの形を灯して提げる（L1〜L10）
##   --part=rack   番台の横のランタン掛けを、夕方のロッジで一人称・三人称・引きで撮る（--spawn=lanterns を付ける）
##   --part=ui     掛けの前で F の画面を開き、買う・足りない・提げ替える・外すを流して、財布と帯の形を log.txt に書く。装備の画面も撮る
##   --part=bots   仲間に --bot-lanterns の形を提げて、夜の外で撮る（ほかの人の画面にも、その人のランタンが見えるか）
## 自分の保存（user://my_tag.cfg）は、始めに写しを取り、終わりに戻す

var args := {}
var main: Node3D
var p: CharacterBody3D
var dc: Node
var lines: Array[String] = []
var _saved := ""

const TAG_FILE := "user://my_tag.cfg"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if FileAccess.file_exists(TAG_FILE):
		_saved = FileAccess.get_file_as_string(TAG_FILE)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 昼夜の時計（daycycle.gd）が、今の場面から太陽を探す
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/lantern-variety")


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
	_say("撮った " + name)


func _key(k: Key) -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = d
		Input.parse_input_event(e)
		await process_frame


func _put(at: Vector3, look: Vector3, pitch := -0.15) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))
	p.set("_pitch", pitch)


func _hour(h: float) -> void:
	dc.hour = h
	dc.day_seconds = 1.0e9   # 撮るあいだは時刻を止める
	await _wait(1.2)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, main.height(x, z) + 0.15, z)


## 別のカメラで撮る（look_from から at を見る）
func _cam_shot(name: String, from: Vector3, at: Vector3, fov := 45.0) -> void:
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.look_at_from_position(from, at, Vector3.UP)
	cam.fov = fov
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)
	cam.current = true
	await _wait(0.4)
	await _shot(name)
	cam.queue_free()
	p.cam.current = true


func _run() -> void:
	await _wait(2.5)
	p = main.player
	dc = root.get_node("DayCycle")
	var c: Node = main.craft
	var who: int = p.id
	var Lantern := preload("res://lantern.gd")
	match args.get("part", "line"):
		"line":
			await _hour(21.0)
			var start: Vector3 = p.global_position
			var Doll := preload("res://doll.gd")
			var kinds := ["kasa", "origami", "news", "robo", "musha", "ningyo", "kasa", "origami", "news", "ningyo"]
			var base := _ground(start.x, start.z + 8.0)
			for i in Lantern.LOOKS.size():
				var host := Node3D.new()
				main.add_child(host)
				host.global_position = _ground(base.x - 6.75 + 1.5 * i, base.z)
				host.rotation.y = PI * 0.5   # 右（+X）を向いて、左の腰（ランタン）がこちらへ
				var d := Doll.new()
				d.kind = kinds[i]
				d.lantern = Lantern.LOOKS[i]
				d.lantern_lit = true
				host.add_child(d)
			_put(_ground(base.x, base.z - 9.0), base, -0.1)
			p.global_position.y += 50.0   # あなたは写らないところへ
			await _wait(2.0)
			await _cam_shot("01_line", base + Vector3(0, 1.6, 7.0), base + Vector3(0, 0.5, 0), 62.0)
			await _cam_shot("02_line_left", base + Vector3(-3.75, 1.0, 2.8), base + Vector3(-3.75, 0.45, 0), 58.0)
			await _cam_shot("03_line_right", base + Vector3(3.75, 1.0, 2.8), base + Vector3(3.75, 0.45, 0), 58.0)
		"rack":
			var rk: Node3D = main.lantern_rack
			if rk == null:
				_say("ランタン掛けがない")
			else:
				await _hour(18.2)
				await _wait(1.0)
				await _shot("04_rack_fp")
				p.set_third(true)
				await _wait(0.6)
				await _shot("05_rack_3rd")
				p.set_third(false)
				var sk: Node3D = main.shopkeeper
				var mid: Vector3 = (rk.global_position + sk.global_position) * 0.5
				await _cam_shot("06_rack_bandai", rk.to_global(Vector3(0.6, 1.7, 4.6)), mid + Vector3.UP * 1.0, 60.0)
				await _cam_shot("07_rack_close", rk.to_global(Vector3(0.0, 1.55, 1.9)), rk.to_global(Vector3(0, 1.5, 0)), 50.0)
		"ui":
			c.wallets[who] = 400
			_say("始め: 財布 %d 提げている %s 持っている %s" % [c.wallet(who), c.lantern(who), c.lanterns[who]])
			await _wait(1.0)
			await _key(KEY_F)
			await _wait(1.2)
			_say("画面が開いた %s" % main.lantern_ui.is_open)
			await _shot("08_ui_open")
			var ui = main.lantern_ui
			_say("糸巻きを買う %s → 財布 %d 提げている %s" % [ui.choose(2), c.wallet(who), c.lantern(who)])
			_say("毛糸の編み帽子を買う %s → 財布 %d" % [ui.choose(3), c.wallet(who)])
			_say("螺鈿を買う（足りない）%s → 財布 %d" % [ui.choose(9), c.wallet(who)])
			await _wait(0.1)
			await _shot("09_ui_short")
			await _wait(0.6)
			_say("刺繍枠を買う %s → 財布 %d 提げている %s" % [ui.choose(4), c.wallet(who), c.lantern(who)])
			_say("糸巻きに提げ替える %s → 提げている %s" % [ui.choose(2), c.lantern(who)])
			await _wait(0.6)
			await _shot("10_ui_bought")
			_say("糸巻きをもう一度押して外す %s → 提げている %s" % [ui.choose(2), c.lantern(who)])
			_say("刺繍枠を提げる %s → 提げている %s" % [ui.choose(4), c.lantern(who)])
			await _key(KEY_ESCAPE)
			await _wait(0.5)
			_say("画面を閉じた %s" % (not main.lantern_ui.is_open))
			var cf := ConfigFile.new()
			cf.load(TAG_FILE)
			_say("保存: 持っている %s 提げている %s" % [cf.get_value("lantern", "owned", []), cf.get_value("lantern", "wear", "?")])
			c.send({"kind": "lamp", "who": who, "on": true})
			main.craft_ui.open_gear()
			await _wait(1.0)
			await _shot("11_gear")
			if main.craft_ui.has_method("close"):
				main.craft_ui.close()
		"bots":
			await _hour(21.0)
			var bots: Array = []
			for n in main.get_children():
				if n is CharacterBody3D and n != p and n.get("lounge") == false:
					bots.append(n)
			await _wait(1.5)
			for b in bots:
				c.send({"kind": "lamp", "who": b.id, "on": true})
				_say("仲間 %d の帯: %s 点いている %s" % [b.id, c.lantern(b.id), c.lamp_on(b.id)])
			await _wait(1.0)
			if not bots.is_empty():
				var b0: Node3D = bots[0]
				var mid: Vector3 = b0.global_position
				if bots.size() > 1:
					mid = (b0.global_position + (bots[1] as Node3D).global_position) * 0.5
				await _cam_shot("12_bots", mid + Vector3(0, 1.4, -4.0), mid + Vector3.UP * 0.5, 55.0)
	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	if _saved != "":
		var w := FileAccess.open(TAG_FILE, FileAccess.WRITE)
		w.store_string(_saved)
	elif FileAccess.file_exists(TAG_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TAG_FILE))
	quit()
