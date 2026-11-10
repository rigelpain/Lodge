extends SceneTree
## 提げているランタンと、紙細工屋さんの色替え（craft.gd の lantern_dye）を、起動し直しても持っているかを確かめる。
## 保存は確かめ用の帳面（--tag-file。遊ぶ人の user://my_tag.cfg は読まない・書き換えない）。数字は log.txt にも書く。
## 1 台（2 回起動する。1 回目で保存して終わり、2 回目で読んだ物を確かめる）:
##   Godot --path game --resolution 1280x720 -s res://tools/lantern_keep_check.gd -- --part=save --spawn=paper_shop --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --tag-file=user://lantern_keep_test.cfg --dir=/path/shots
##   Godot --path game --resolution 1280x720 -s res://tools/lantern_keep_check.gd -- --part=load --spawn=paper_shop --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --tag-file=user://lantern_keep_test.cfg --dir=/path/shots
##   save: 紙細工屋さんで蛍を買う → 持ち物の画面（I）の道で和紙の提灯に提げ替える → 色替えの段で青緑に染める（前と後の絵）。
##         足りない・同じ色・パレットにない色・提げていない は断る。もとの色に戻すのはただ
##   load: 起動し直して、和紙の提灯を青緑で提げていること（絵）。持っていない形・なくなった形の保存なら、はじめの標準のまま
## 2 台（ホストを先に。つなぐ側の帳面に、和紙の提灯を青緑で提げた保存を書いてから入る）:
##   Godot --headless --path game -s res://tools/lantern_keep_check.gd -- --part=net --host --port=24795 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-save --tag-file=user://lantern_keep_none.cfg
##   Godot --headless --path game -s res://tools/lantern_keep_check.gd -- --part=net --join=127.0.0.1 --port=24795 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --tag-file=user://lantern_keep_join.cfg
##   つなぐ側が、保存した形と色のランタンを持って入り、ホストの画面のその人の人形にも同じ形と色が見える

const Lantern := preload("res://lantern.gd")
const Craft := preload("res://craft.gd")
var TEAL: String = Craft.lantern_palette()[6]   # パレット（Craft.COLORS）の 7 番の青緑

var args := {}
var main: Node3D
var p: CharacterBody3D
var dc: Node
var fails := 0
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tf := String(args.get("tag-file", ""))
	if args.get("part", "") == "save" and tf != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tf))   # まっさらな帳面から
	if args.get("part", "") == "net" and args.has("join") and tf != "":
		var cf := ConfigFile.new()   # つなぐ側の保存: 蛍と和紙の提灯を持ち、和紙の提灯を青緑に染めて提げている
		cf.set_value("lantern", "owned", ["box", "paper", "hotaru"])
		cf.set_value("lantern", "wear", "hotaru")
		cf.set_value("lantern", "colors", {"hotaru": TEAL})
		cf.save(tf)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 昼夜の時計（daycycle.gd）が、今の場面から太陽を探す
	if args.has("dir"):
		DirAccess.make_dir_recursive_absolute(String(args.dir))
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _ok(c: bool, what: String) -> void:
	_say(("OK " if c else "NG ") + what)
	if not c:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		if t > limit:
			return false
		await physics_frame
		t += 1.0 / 60.0
	return true


func _shot(name: String) -> void:
	if not args.has("dir") or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.dir).path_join(name + ".png"))


func _hour(h: float) -> void:
	dc.hour = h
	dc.day_seconds = 1.0e9   # 撮るあいだは時刻を止める
	await _wait(1.2)


## 夜の外（はじめのソリの横の雪の上）で、三人称で人形の左の腰（ランタン）が見える所に立つ。前と後で同じ所・同じ向き
func _night_pose() -> void:
	var s: Vector3 = main.sled.global_position + Vector3(3.0, 0.0, 3.0)
	p.global_position = Vector3(s.x, main.height(s.x, s.z) + 0.15, s.z)
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.9
	p.set_third(true)
	p.set("_pitch", -0.3)
	await _wait(2.0)


func _saved() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(String(args.get("tag-file", "")))
	return cf


func _run() -> void:
	await _wait(2.5)
	p = main.player
	dc = root.get_node_or_null("DayCycle")
	match String(args.get("part", "")):
		"save": await _save_run()
		"load": await _load_run()
		"net":
			if args.has("host"):
				await _host_run()
			else:
				await _join_run()
	if args.has("dir"):
		var f := FileAccess.open(String(args.dir).path_join("log_%s%s.txt" % [args.get("part", ""), "_join" if args.has("join") else ""]), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(lines) + "\n")
	_say("NG の数 %d" % fails)
	quit(1 if fails > 0 else 0)


func _save_run() -> void:
	var c: Node = main.craft
	var ui = main.paper_shop_ui
	var who: int = p.id
	_ok(c.lantern(who).get("look", "") == "box", "まっさらな帳面では、はじめの木の手提げを提げている（%s）" % c.lantern(who))
	c.wallets[who] = 600
	# 紙細工屋さんで蛍を買う（買ったらすぐ提げる。保存する）
	ui.open("lantern")
	_ok(ui.choose(Lantern.LOOKS.find("hotaru")), "蛍を買えた")
	_ok(String(_saved().get_value("lantern", "wear", "?")) == "hotaru", "買うと保存される（wear %s）" % _saved().get_value("lantern", "wear", "?"))
	ui.close()
	# 持ち物の画面（I）で和紙の提灯に提げ替える（押したときと同じ道: 数えてから equip）
	var cu = main.craft_ui
	cu._lamp_asked += 1
	_ok(cu.equip(c.lantern_index(who, "paper"), "lantern"), "持ち物の画面で和紙の提灯に提げ替えた")
	_ok(String(_saved().get_value("lantern", "wear", "?")) == "paper", "持ち物の画面で提げ替えても保存される（wear %s）" % _saved().get_value("lantern", "wear", "?"))
	_ok(cu._lamp_asked == 0, "数えた分は返ってきた")
	# 色替え
	await _hour(21.0)
	c.send({"kind": "lamp", "who": who, "on": true})
	await _night_pose()
	await _shot("01_before_3rd")
	ui.open("lantern_dye")
	await _wait(0.6)
	await _shot("02_before_shop")
	var w0: int = c.wallet(who)
	_ok(ui.choose(Craft.lantern_palette().find(TEAL)), "色替えの段で青緑を押した")
	_ok(c.lantern(who).get("color", "") == TEAL, "提げている和紙の提灯が青緑になった（%s）" % c.lantern(who))
	_ok(w0 - c.wallet(who) == Craft.LANTERN_DYE_PRICE, "染め代 %d を払った（%d → %d）" % [Craft.LANTERN_DYE_PRICE, w0, c.wallet(who)])
	_ok(not ui.dye(TEAL), "同じ色は断る")
	_ok(not c.send({"kind": "lantern_dye", "who": who, "look": "paper", "color": "123456"}), "パレットにない色は断る")
	_ok(not c.send({"kind": "lantern_dye", "who": who, "look": "pearl", "color": TEAL}), "持っていない形は断る")
	var tints = _saved().get_value("lantern", "colors", {})
	_ok(tints is Dictionary and String(tints.get("paper", "")) == TEAL, "染めた色が保存される（%s）" % str(tints))
	await _wait(0.8)
	await _shot("03_after_shop")
	ui.close()
	await _night_pose()
	await _shot("04_after_3rd")
	var d: Node3D = p.doll
	_ok(d.lantern == "paper" and d.lantern_color == TEAL, "人形の帯のランタンも青緑（%s %s）" % [d.lantern, d.lantern_color])
	var lt = d.get("_lantern")
	_ok(lt and (lt.get("_light") as OmniLight3D).light_color.is_equal_approx(Lantern.tint("paper", TEAL)), "灯りの色が染めた色（%s）" % ((lt.get("_light") as OmniLight3D).light_color if lt else null))
	# 蛍を染めてから、もとの色に戻す（ただ）
	c.send({"kind": "equip", "who": who, "gear": "lantern", "look": "hotaru"})
	_ok(c.lantern(who).get("look", "") == "hotaru" and c.lantern(who).get("color", "") == "", "蛍に替えると、蛍のもとの色（和紙の提灯の色は和紙の提灯に残る）")
	c.send({"kind": "lantern_dye", "who": who, "look": "hotaru", "color": Craft.lantern_palette()[0]})
	var w1: int = c.wallet(who)
	_ok(c.send({"kind": "lantern_dye", "who": who, "look": "hotaru", "color": ""}) and c.wallet(who) == w1, "もとの色に戻すのはただ")
	c.wallets[who] = 3
	_ok(not c.send({"kind": "lantern_dye", "who": who, "look": "hotaru", "color": TEAL}), "足りなければ断る")
	# 保存の道でもう一度提げ直して、終わりの保存を和紙の提灯（青緑）にする
	cu._lamp_asked += 1
	cu.equip(c.lantern_index(who, "paper"), "lantern")
	var cf := _saved()
	_say("保存: owned %s wear %s colors %s" % [cf.get_value("lantern", "owned", []), cf.get_value("lantern", "wear", "?"), cf.get_value("lantern", "colors", {})])


func _load_run() -> void:
	var c: Node = main.craft
	var who: int = p.id
	_ok(c.lantern(who).get("look", "") == "paper", "起動し直しても和紙の提灯を提げている（%s）" % c.lantern(who))
	_ok(c.lantern(who).get("color", "") == TEAL, "染めた青緑のまま（%s）" % c.lantern(who).get("color", ""))
	_ok(c.lantern_index(who, "hotaru") >= 0, "買った蛍も持っている")
	await _hour(21.0)
	c.send({"kind": "lamp", "who": who, "on": true})
	await _night_pose()
	await _shot("05_reload_3rd")
	_ok(p.doll.lantern == "paper" and p.doll.lantern_color == TEAL, "人形の帯にも（%s %s）" % [p.doll.lantern, p.doll.lantern_color])
	# 持っていない形・なくなった形・パレットにない色の保存: 断られて、はじめの標準のまま（止まらない）
	var tf := String(args["tag-file"])
	var cf := ConfigFile.new()
	cf.load(tf)
	cf.set_value("lantern", "owned", ["box", "paper", "no_such_lamp"])
	cf.set_value("lantern", "wear", "no_such_lamp")
	cf.set_value("lantern", "colors", {"no_such_lamp": TEAL, "paper": "123456"})
	cf.save(tf)
	c.lanterns[who] = [{"look": "box"}, {"look": "paper"}]
	c.lantern_sel[who] = 0
	p._load_tag()
	_ok(c.lantern(who).get("look", "") == "box" and c.lantern(who).get("color", "") == "", "なくなった形の保存なら、はじめの木の手提げのまま（%s）" % c.lantern(who))
	cf.set_value("lantern", "owned", ["box", "paper"])
	cf.set_value("lantern", "wear", "hotaru")   # 持っていない形
	cf.save(tf)
	p._load_tag()
	_ok(c.lantern(who).get("look", "") == "box", "持っていない形の保存でも、はじめの木の手提げのまま（%s）" % c.lantern(who))
	cf.set_value("lantern", "wear", "")   # 外していた
	cf.save(tf)
	p._load_tag()
	_ok(c.lantern(who).is_empty(), "外していた保存なら、外したまま")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tf))   # 確かめの帳面を消す


func _host_run() -> void:
	var c: Node = main.craft
	_ok(await _until(func(): return not main.net.remotes.is_empty(), 20.0), "つなぐ側が来た")
	var pid: int = main.net.remotes.keys()[0]
	_ok(await _until(func(): return c.lantern(pid).get("look", "") == "hotaru", 15.0), "つなぐ側の人が、保存した蛍を提げて入った（ホストの画面 %s）" % c.lantern(pid))
	_ok(await _until(func(): return c.lantern(pid).get("color", "") == TEAL, 5.0), "染めた青緑も（%s）" % c.lantern(pid).get("color", ""))
	var rp: Node = main.net.remotes[pid]
	var d = rp.get("doll")
	_ok(await _until(func(): return d and d.lantern == "hotaru" and d.lantern_color == TEAL, 5.0), "ホストの画面のその人の人形の帯にも（%s %s）" % [d.lantern if d else "", d.lantern_color if d else ""])
	# ホストの人が染めると、つなぐ側にも
	c.wallets[p.id] = 100
	c.send({"kind": "equip", "who": p.id, "gear": "lantern", "look": "box"})
	c.send({"kind": "lantern_dye", "who": p.id, "look": "box", "color": Craft.lantern_palette()[2]})
	await _wait(4.0)
	# 黒に染めて点けると、つなぐ側の画面でもまわりを暗くする（lantern.gd の is_black）
	c.send({"kind": "lantern_dye", "who": p.id, "look": "box", "color": Craft.lantern_palette()[10]})
	c.send({"kind": "lamp", "who": p.id, "on": true})
	await _wait(6.0)


func _join_run() -> void:
	var c: Node = main.craft
	_ok(await _until(func(): return main.net.joined(), 20.0), "ホストにつながった")
	_ok(await _until(func(): return c.lantern(p.id).get("look", "") == "hotaru" and c.lantern(p.id).get("color", "") == TEAL, 15.0),
		"自分の画面でも、保存した蛍（青緑）を提げている（%s）" % c.lantern(p.id))
	var hid := 1
	_ok(await _until(func(): return c.lantern(hid).get("color", "") == Craft.lantern_palette()[2], 15.0), "ホストの人が染めた色が、つなぐ側にも届く（%s）" % c.lantern(hid))
	var rp: Node = main.net.remotes.get(hid)
	var d = rp.get("doll") if rp else null
	_ok(await _until(func(): return d and d.lantern_color == Craft.lantern_palette()[2], 5.0), "ホストの人の人形の帯にも")
	var lt = d.get("_lantern") if d else null
	_ok(await _until(func(): return lt and (lt.get("_light") as OmniLight3D).light_negative and (lt.get("_dark") as Node3D).visible, 15.0),
		"ホストの人が黒に染めて点けると、つなぐ側の画面でもまわりを暗くする（引く灯りと暗がりの球）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(String(args.get("tag-file", ""))))
