extends SceneTree
## 2 階の紙細工屋さん（paper_lady.gd・paper_shop_ui.gd）を確かめて撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/paper_shop_shots.gd -- --part=look --spawn=paper_shop --no-sound --no-pip --dir=/path/shots
##   --part=look   婦人とスタンドを、一人称・三人称・引き・スタンドの寄りで撮る（昼と夕方）。婦人が顔を向けるのも撮る
##   --part=ui     前で F の画面を開き、提灯・頭・肩の 3 段を撮る。買う・足りない・付け替える・外すを流して、財布と身につけた物を log.txt に書く。
##                 婦人がうなずくのも撮る
##   --part=net    通信: 同じ Mac で 2 つ起動する（--host と --join=127.0.0.1。--port= をそろえる。どちらも --spawn=paper_shop）。
##                 つなぐ側が画面で糸巻きの提灯とどんぐりを買い、互いの画面で相手の人の帯と頭の物を書いて撮る
## 自分の保存（user://my_tag.cfg）は、始めに写しを取り、終わりに戻す

const Lantern := preload("res://lantern.gd")
const Pals := preload("res://pals.gd")
const TAG_FILE := "user://my_tag.cfg"

var args := {}
var main: Node3D
var p: CharacterBody3D
var dc: Node
var lines: Array[String] = []
var _saved := ""


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
	return args.get("dir", "/tmp/paper-shop")


func _tag() -> String:
	return "host" if args.has("host") else ("join" if args.has("join") else "")


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


func _hour(h: float) -> void:
	dc.hour = h
	dc.day_seconds = 1.0e9   # 撮るあいだは時刻を止める
	await _wait(1.2)


## 別のカメラで撮る（from から at を見る）
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


func _worn(who: int) -> String:
	var c: Node = main.craft
	return "提灯 %s 頭 %s 肩 %s" % [c.lantern(who).get("look", ""), c.pal_worn(who, "head"), c.pal_worn(who, "shoulder")]


func _run() -> void:
	await _wait(3.0)
	p = main.player
	dc = root.get_node("DayCycle")
	var c: Node = main.craft
	var who: int = p.id
	var lady: Node3D = main.paper_lady
	if lady == null:
		_say("紙細工屋さんがいない")
		_end()
		return
	_say("婦人 %s スタンド %s 開ける %s" % [lady.global_position, lady.stand.global_position, p.paper_shop_near()])
	match args.get("part", "look"):
		"look":
			await _hour(13.0)
			await _shot("01_fp")
			p.set_third(true)
			await _wait(0.8)
			await _shot("02_3rd")
			p.set_third(false)
			await _cam_shot("03_wide", lady.to_global(Vector3(0.7, 1.9, 5.2)), lady.to_global(Vector3(0.7, 1.1, 0)), 55.0)
			await _cam_shot("04_stand", lady.to_global(Vector3(1.35, 1.6, 2.1)), lady.to_global(Vector3(1.35, 1.25, -0.3)), 50.0)
			await _cam_shot("05_lady", lady.to_global(Vector3(0.0, 1.4, 2.3)), lady.to_global(Vector3(0.0, 1.0, 0)), 42.0)
			await _cam_shot("06_side", lady.to_global(Vector3(-2.6, 1.6, 2.2)), lady.to_global(Vector3(0.6, 1.0, -0.2)), 50.0)
			await _hour(18.3)
			await _cam_shot("07_wide_evening", lady.to_global(Vector3(0.7, 1.9, 5.2)), lady.to_global(Vector3(0.7, 1.1, 0)), 55.0)
			# 顔を向ける: あなたを婦人の右前と左前に置いて、婦人の頭を撮る
			for side in [-1.0, 1.0]:
				var at: Vector3 = lady.to_global(Vector3(side * 2.0, 0.1, 2.0))
				p.global_position = at
				p.velocity = Vector3.ZERO
				await _wait(1.0)
				await _cam_shot("08_look_%s" % ("r" if side < 0 else "l"), lady.to_global(Vector3(0.0, 1.6, 1.6)), lady.to_global(Vector3(0.0, 1.2, 0)), 40.0)
		"ui":
			await _hour(13.0)
			c.wallets[who] = 300
			_say("始め: 財布 %d %s" % [c.wallet(who), _worn(who)])
			await _key(KEY_F)
			await _wait(1.2)
			var ui = main.paper_shop_ui
			_say("画面が開いた %s 段 %s" % [ui.is_open, ui.TABS[ui.tab]])
			await _shot("10_ui_lantern")
			_say("糸巻きを買う %s → 財布 %d %s" % [ui.choose(Lantern.LOOKS.find("spool")), c.wallet(who), _worn(who)])
			_say("螺鈿を買う（足りない）%s → 財布 %d" % [ui.choose(Lantern.LOOKS.find("raden")), c.wallet(who)])
			await _wait(0.1)
			await _shot("11_ui_short")
			await _wait(0.5)
			ui.set_tab(1)
			await _wait(1.0)
			_say("段 %s: どんぐりを買う %s → 財布 %d %s" % [ui.TABS[ui.tab], ui.choose(ui.keys().find("acorn")), c.wallet(who), _worn(who)])
			await _wait(0.3)
			await _shot("12_ui_head")
			_say("どんぐりをもう一度押して外す %s → %s" % [ui.choose(ui.keys().find("acorn")), _worn(who)])
			_say("千代紙の小鳥（はじめから）をつける %s → %s" % [ui.choose(ui.keys().find("chiyo_bird")), _worn(who)])
			ui.set_tab(2)
			await _wait(1.0)
			_say("段 %s: 青い小鳥を買う %s → 財布 %d %s" % [ui.TABS[ui.tab], ui.choose(ui.keys().find("blue_bird")), c.wallet(who), _worn(who)])
			await _wait(0.3)
			await _shot("13_ui_shoulder")
			await _key(KEY_ESCAPE)
			await _wait(0.3)
			_say("画面を閉じた %s" % (not ui.is_open))
			await _cam_shot("14_nod", lady.to_global(Vector3(0.0, 1.5, 2.0)), lady.to_global(Vector3(0.0, 1.2, 0)), 40.0)
			c.send({"kind": "pal_buy", "who": who, "key": "crane"})   # 買った直後のうなずき
			await _wait(0.33)
			await _cam_shot("15_nod_mid", lady.to_global(Vector3(0.0, 1.5, 2.0)), lady.to_global(Vector3(0.0, 1.2, 0)), 40.0)
			p.set_third(true)
			await _wait(0.8)
			await _shot("16_wearing_3rd")
			p.set_third(false)
			var cf := ConfigFile.new()
			cf.load(TAG_FILE)
			_say("保存: 提灯 持っている %s 提げている %s / 小物 %s" % [cf.get_value("lantern", "owned", []), cf.get_value("lantern", "wear", "?"),
				cf.get_value("pals", "wear", cf.get_value("pals", "owned", "?"))])
		"net":
			var net: Node = main.net
			var t := 0.0
			while net.remotes.is_empty() and t < 30.0:
				await _wait(0.5)
				t += 0.5
			if net.remotes.is_empty():
				_say("相手が来なかった")
			else:
				await _hour(13.0)
				var pid: int = net.remotes.keys()[0]
				var rp: Node3D = net.remotes[pid]
				_say("%s: 自分 %d 相手 %d" % [_tag(), who, pid])
				if net.is_host():
					c.send({"kind": "earn", "who": pid, "n": 300, "at": rp.global_position})   # つなぐ側にボタンを配る
					t = 0.0
					while (c.lantern(pid).get("look", "") != "spool" or c.pal_worn(pid, "head") != "acorn") and t < 25.0:   # つなぐ側が買うのを待つ
						await _wait(0.5)
						t += 0.5
				else:
					t = 0.0
					while c.wallet(who) < 200 and t < 10.0:
						await _wait(0.5)
						t += 0.5
					_say("つなぐ側: 財布 %d" % c.wallet(who))
					await _key(KEY_F)
					await _wait(1.0)
					var ui = main.paper_shop_ui
					_say("つなぐ側: 画面 %s 糸巻きを押す %s" % [ui.is_open, ui.choose(Lantern.LOOKS.find("spool"))])
					await _wait(1.0)
					ui.set_tab(1)
					await _wait(0.5)
					_say("つなぐ側: どんぐりを押す %s" % ui.choose(ui.keys().find("acorn")))
					await _wait(1.0)
					await _key(KEY_ESCAPE)
				await _wait(2.0)
				_say("%s: 自分 %s 財布 %d" % [_tag(), _worn(who), c.wallet(who)])
				_say("%s: 相手 %s（相手の人形の帯 %s）" % [_tag(), _worn(pid), rp.doll.lantern])
				var at: Vector3 = rp.global_position
				await _cam_shot("20_net_%s" % _tag(), at + rp.global_basis.z * 2.2 + Vector3.UP * 1.3, at + Vector3.UP * 0.8, 50.0)
				await _wait(8.0 if net.is_host() else 1.0)   # ホストは、つなぐ側が撮り終えるまで残る
	_end()


func _end() -> void:
	var f := FileAccess.open(_dir().path_join("log%s.txt" % ("_" + _tag() if _tag() != "" else "")), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	if _saved != "":
		var g := FileAccess.open(TAG_FILE, FileAccess.WRITE)
		g.store_string(_saved)
	elif FileAccess.file_exists(TAG_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TAG_FILE))
	quit()
