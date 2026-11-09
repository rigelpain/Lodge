extends SceneTree
## 大玉の縫い目の柄（ball_stitches.gd・big_ball.gd）の確かめ。数字だけ出す。
## 1 台:
##   Godot --headless --path game -s res://tools/ball_stitch_check.gd -- --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons
##   柄と段ごとの目の数・手袋の段で縫い合わせと柄が替わる・山師の棚で買う（ボタンが減る、二度買えない、足りないと買えない）・
##   持ち物の画面で選ぶ（買っていない柄は選べない）・選ぶと置いてある自分の玉が縫い直される・へこむと目がはじける・保存と読み込み
##   （本物の user://my_tag.cfg に書くので、始めに読んで、終わりに戻す）
## 2 台（ホストを先に）:
##   Godot --headless --path game -s res://tools/ball_stitch_check.gd -- --host --port=24791 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   Godot --headless --path game -s res://tools/ball_stitch_check.gd -- --join=127.0.0.1 --port=24791 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   ホストの人の玉（革・菊かがり）と、つなぐ側の人の玉（フェルト・つなぐ側が買って選んだジグザグ）が、両方の画面で同じ柄・同じ段になる

const BS := preload("res://ball_stitches.gd")
const SPOT := Vector3(4.0, 0.0, 60.0)

var args := {}
var main: Node3D
var p: CharacterBody3D
var fails := 0
var _next := 700


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


func _ok(c: bool, what: String) -> void:
	print(("OK " if c else "NG ") + what)
	if not c:
		fails += 1


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		if t > limit:
			return false
		await physics_frame
		t += 1.0 / 60.0
	return true


func _ball(maker: int, grade: String, id := -1) -> RigidBody3D:
	_next += 1
	var x := SPOT.x + (_next % 8) * 4.0
	var b: RigidBody3D = main.emotes._spawn_big({"ball": id if id >= 0 else _next, "point": Vector3(x, main.height(x, SPOT.z), SPOT.z), "r": 0.8, "who": maker})
	b.freeze = true
	b.pack = grade
	return b


func _run() -> void:
	await create_timer(1.0).timeout
	p = main.player
	if args.has("host"):
		await _host_run()
	elif args.has("join"):
		await _join_run()
	else:
		await _solo()
	print("だめだった数: %d" % fails)
	await create_timer(0.5).timeout
	quit(1 if fails > 0 else 0)


func _solo() -> void:
	var c = main.craft
	var who: int = p.id
	# 買う・選ぶと保存が走るので、遊ぶ人の保存ファイルを始めに控えておき、終わりに戻す
	var path := "user://my_tag.cfg"
	var had := FileAccess.file_exists(path)
	var keep := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	_ok(c.ball_owned[who].is_empty(), "始めは大玉の柄を持っていない（%s）" % str(c.ball_owned[who]))
	# ---- 形
	var t0 := Time.get_ticks_msec()
	var most := 0
	var empty := []
	for grade in BS.STANDARD:
		var counts := []
		for nm in BS.LIST:
			var n: int = BS.segments(nm, grade).size()
			counts.append("%s %d" % [nm, n])
			most = maxi(most, n)
			if n == 0:
				empty.append(nm + ":" + grade)
		print("%s（面 %d）: %s" % [grade, BS.faces(grade).size(), ", ".join(counts)])
	print("柄の形を全部作るのに %d ms" % (Time.get_ticks_msec() - t0))
	_ok(empty.is_empty(), "どの柄・どの段にも目がある %s" % str(empty))
	_ok(most <= 400, "1 つの玉の目は多くて %d（400 まで）" % most)
	for grade in BS.STANDARD:
		_ok(BS.faces(grade).size() == BS.MAX_FACES, "%s: 手まりの柄を刺す面が %d か所" % [grade, BS.faces(grade).size()])
	# 段ごとに縫い合わせの形がちがう（標準の柄の目の数と、縫い合わせの数）
	_ok(BS.seams("gloves").size() == 2 and BS.seams("gloves_felt").size() == 3 and BS.seams("gloves_leather").size() == 1, "縫い合わせ: 毛糸 2 本・フェルト 3 本・革 1 本")
	# ---- 手袋の段で替わる
	var bw := _ball(who, "gloves")
	var bf := _ball(who, "gloves_felt")
	var bl := _ball(who, "gloves_leather")
	await process_frame
	_ok(bw._seam_key == "yarn:gloves" and bf._seam_key == "felt:gloves_felt" and bl._seam_key == "leather:gloves_leather",
			"段ごとの標準の柄: %s / %s / %s" % [bw._seam_key, bf._seam_key, bl._seam_key])
	_ok(bw._seam.multimesh.instance_count == BS.segments("yarn", "gloves").size(), "玉の目の数が柄の目の数と同じ（%d）" % bw._seam.multimesh.instance_count)
	bw.pack = "gloves_leather"
	_ok(bw._seam_key == "leather:gloves_leather", "よい手袋で押されて段が上がると、縫い直される（%s）" % bw._seam_key)
	bw.pack = "gloves"
	# ---- 買う（山師の棚）
	c.wallets[who] = 100
	var mui = main.mountain_ui
	mui.open()
	mui.set_page(2)
	_ok(mui._ball_goods.size() == BS.for_sale().size() and mui._ball_goods.size() >= 16, "山師の棚の雪玉の柄: %d 種" % mui._ball_goods.size())
	_ok(not c.ball_can_use(who, "cross"), "買う前のクロスは選べない")
	_ok(not main.craft_ui.set_ball_stitch("cross"), "買う前のクロスを持ち物の画面で押しても替わらない")
	mui.select(mui._ball_goods.find("cross"))
	_ok(mui.buy(), "クロス（60）を買える")
	_ok(c.wallet(who) == 40 and "cross" in c.ball_owned[who], "ボタンが 60 減り（%d）、持っている柄に入る" % c.wallet(who))
	_ok(not mui.buy(), "同じ柄は二度買えない")
	mui.select(mui._ball_goods.find("kiku"))
	_ok(not mui.buy() and c.wallet(who) == 40, "ボタンが足りないと買えない（菊かがり 250）")
	mui.set_page(0)
	mui.close()
	# ---- 選ぶ（持ち物の画面）
	var ui = main.craft_ui
	ui.open_gear()
	ui.tag_page = ui.ball_page()
	await process_frame
	_ok(ui.set_ball_stitch("cross"), "持ち物の画面でクロスを選べる")
	_ok(bw._seam_key == "cross:gloves" and bf._seam_key == "cross:gloves_felt", "置いてある自分の玉が縫い直される（糸と縫い合わせは段のまま）: %s / %s" % [bw._seam_key, bf._seam_key])
	var other := _ball(who + 50, "gloves")
	await process_frame
	_ok(other._seam_key == "yarn:gloves", "ほかの人の玉は替わらない（%s）" % other._seam_key)
	var nb := _ball(who, "gloves_leather")
	await process_frame
	_ok(nb._seam_key == "cross:gloves_leather", "これから置く玉も選んだ柄（%s）" % nb._seam_key)
	_ok(ui.set_ball_stitch("") and bw._seam_key == "yarn:gloves", "手袋の柄に戻せる（%s）" % bw._seam_key)
	ui.set_ball_stitch("cross")
	await process_frame
	ui.close_gear()
	# ---- へこむと目がはじける
	var before: int = bw._seam_off.count(1)
	bw.show_hurt({"dir": Vector3(0, 0, 1), "amt": 0.5, "k": 0.3})
	var popped: int = bw._seam_off.count(1)
	_ok(popped > before, "へこんだ所の目がはじける（%d → %d）" % [before, popped])
	if DisplayServer.get_name() != "headless":   # 画面のない起動では、目ごとの値を読み返せない
		var cd: Color = bw._seam.multimesh.get_instance_custom_data(bw._seam_off.find(1))
		_ok(cd.a < 0.0, "はじけた目は描かれない")
	ui.set_ball_stitch("")
	ui.set_ball_stitch("cross")
	_ok(bw._seam_off.count(1) >= popped - 2 and bw._seam_off.count(1) > 0, "縫い直しても、へこんだ所の目ははじけたまま（%d）" % bw._seam_off.count(1))
	# ---- 保存と読み込み（本物の保存ファイル。始めの中身に戻す）
	p.save_tag()
	var cf := ConfigFile.new()
	cf.load(path)
	_ok(Array(cf.get_value("ball", "owned", [])) == ["cross"] and String(cf.get_value("ball", "stitch", "")) == "cross", "保存: 買った柄 %s・選んだ柄 %s" % [str(cf.get_value("ball", "owned", [])), cf.get_value("ball", "stitch", "")])
	c.ball_owned[who] = []
	c.ball_stitch[who] = ""
	p._load_tag()
	_ok(c.ball_owned[who] == ["cross"] and c.ball_stitch_of(who) == "cross", "読み込むと、買った柄と選んだ柄が戻る")
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(keep)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("保存ファイルを戻した（%s）" % ("元の中身" if had else "消した"))


## ホスト: 自分の玉（革・菊かがり）と、つなぐ側の人の玉（フェルト）を置く。つなぐ側の人がクロスを買って選ぶ
func _host_run() -> void:
	var c = main.craft
	_ok(await _until(func(): return not main.net.remotes.is_empty(), 20.0), "つなぐ側が来た")
	var pid: int = main.net.remotes.keys()[0]
	await create_timer(1.0).timeout
	c.send({"kind": "ball_stitch_own", "who": p.id, "stitch": "kiku"})
	c.send({"kind": "ball_stitch_set", "who": p.id, "stitch": "kiku"})
	var mine := _ball(p.id, "gloves_leather", 900)
	var theirs := _ball(pid, "gloves_felt", 901)
	_ok(mine._seam_key == "kiku:gloves_leather", "ホストの人の玉: %s" % mine._seam_key)
	_ok(await _until(func(): return theirs._seam_key == "zigzag:gloves_felt", 30.0), "つなぐ側の人が買って選んだ柄が、ホストの画面の玉にも（%s）" % theirs._seam_key)
	print("ホストの画面: 900 %s（%d 目）、901 %s（%d 目）" % [mine._seam_key, mine._seam.multimesh.instance_count, theirs._seam_key, theirs._seam.multimesh.instance_count])
	await create_timer(6.0).timeout


func _join_run() -> void:
	var c = main.craft
	_ok(await _until(func(): return main.net.joined(), 20.0), "ホストにつながった")
	_ok(await _until(func(): return main.emotes.big_balls.has(900) and main.emotes.big_balls.has(901), 20.0), "ホストの大玉が 2 つ届く")
	var b900 = main.emotes.big_balls.get(900)
	var b901 = main.emotes.big_balls.get(901)
	if b900 == null or b901 == null:
		return
	_ok(await _until(func(): return b900._seam_key == "kiku:gloves_leather", 10.0), "ホストの人の玉が、つなぐ側でも同じ柄と段（%s）" % b900._seam_key)
	_ok(await _until(func(): return b901._seam_key == "felt:gloves_felt", 10.0), "自分の玉は、まだフェルトの標準（%s）" % b901._seam_key)
	c.send({"kind": "ball_stitch_buy", "who": p.id, "stitch": "zigzag"})
	_ok(await _until(func(): return "zigzag" in c.ball_owned.get(p.id, []), 10.0), "ジグザグ（30。はじめのボタンで買える）を買えた（ホストが確かめて配る）")
	c.send({"kind": "ball_stitch_set", "who": p.id, "stitch": "zigzag"})
	_ok(await _until(func(): return b901._seam_key == "zigzag:gloves_felt", 10.0), "選ぶと、自分の玉が縫い直される（%s）" % b901._seam_key)
	print("つなぐ側の画面: 900 %s（%d 目）、901 %s（%d 目）" % [b900._seam_key, b900._seam.multimesh.instance_count, b901._seam_key, b901._seam.multimesh.instance_count])
	await create_timer(3.0).timeout
