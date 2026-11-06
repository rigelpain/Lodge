extends SceneTree
## ロッジ前の地図のまち針の確かめ（map_pins.gd）。実時間で動かすので --fixed-fps は付けない。
## 一人: 看板の前に立ち、頂上・ロッジへ CPU を運んで絵と合うか見たあと、--secs 秒のあいだ 2 秒ごとに撮る（<dir>/frame_NNN.png）。
##   Godot --path game --resolution 1280x720 -s res://tools/map_pins_check.gd -- --no-sound --hud-idle=0 --dir=/path/shots --secs=60
## 二つ: ホストを先に、あとからつなぐ側を起動する。来た人のまち針が増え、帰ると減るか。1 秒ごとに「番号 位置 色」を書くので、両方のログを時刻で比べる。
##   Godot --path game --resolution 960x540 --position 0,40 -s res://tools/map_pins_check.gd -- --host --port=24761 --no-sound --hud-idle=0 --dir=/path/shots
##   Godot --path game --resolution 960x540 --position 980,40 -s res://tools/map_pins_check.gd -- --join=127.0.0.1 --port=24761 --no-sound --hud-idle=0 --dir=/path/shots

const Flags := preload("res://area_flags.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var pins: Node
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	if args.has("dir"):
		DirAccess.make_dir_recursive_absolute(String(args.dir))
	_run.call_deferred()


func _tag() -> String:
	return "host" if args.has("host") else ("join" if args.has("join") else "solo")


func _say(s: String) -> void:
	print("[%s %.2f] %s" % [_tag(), fmod(Time.get_unix_time_from_system(), 1000.0), s])


func _ok(cond: bool, what: String) -> void:
	_say(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(nm: String) -> void:
	await process_frame
	await process_frame
	if args.has("dir"):
		root.get_texture().get_image().save_png(String(args.dir).path_join(nm + ".png"))


## 看板の前に立って見上げる。off は看板の正面からの横のずれ、back は看板からの距離 (m)
func _stand(off: float, back: float) -> void:
	var board: Node3D = pins.get_parent()
	var at: Vector3 = board.global_transform * Vector3(off, 0, back)
	p.set_third(false)
	p.global_position = Vector3(at.x, main.height(at.x, at.z) + 0.2, at.z)
	var look: Vector3 = board.global_transform * Vector3(0, 3.4, 0)
	var d := look - (p.global_position + Vector3.UP * 1.5)
	p.rotation.y = atan2(-d.x, -d.z)
	p.set("_pitch", atan2(d.y, Vector2(d.x, d.z).length()))


## 名簿の全員のまち針が、体の位置と色に合っているか
func _check_all(what: String) -> void:
	await _wait(0.2)
	var people: Dictionary = main.emotes.people
	var got: Array = pins.pins()
	var bad := 0
	for id in people:
		var at: Vector3 = people[id].global_position
		var want: Vector2 = Flags.on_board(Vector2(at.x, at.z))
		var col: Color = main.craft.color_of(id)
		var near := got.filter(func(g): return g.at.distance_to(want) < 0.05 and (g.color as Color).is_equal_approx(col))
		bad += 0 if not near.is_empty() else 1
	_ok(got.size() == people.size() and bad == 0, "%s: まち針 %d 本、名簿 %d 人、合わない %d" % [what, got.size(), people.size(), bad])


func _table() -> void:
	var people: Dictionary = main.emotes.people
	var ids := people.keys()
	ids.sort()
	var row := []
	for id in ids:
		var at: Vector3 = people[id].global_position
		var on: Vector2 = Flags.on_board(Vector2(at.x, at.z))
		row.append("%d:(%.3f,%.3f)#%s" % [id, on.x, on.y, main.craft.color_of(id).to_html(false)])
	_say("表 " + " ".join(row))


func _run() -> void:
	await _wait(1.0)
	p = main.player
	var t0 := Time.get_ticks_msec()
	while pins == null:   # 地図の絵を焼き終えると置かれる
		await process_frame
		pins = main.find_child("MapPins", true, false)
		if Time.get_ticks_msec() - t0 > 30000:
			_ok(false, "まち針が置かれない")
			quit(1)
			return
	if args.has("host"):
		await _run_host()
	elif args.has("join"):
		await _run_join()
	else:
		await _run_solo()
	_say("確かめ: NG %d 件" % fails)
	quit(1 if fails > 0 else 0)


func _bots() -> Array:
	return get_nodes_in_group("bots")


func _run_solo() -> void:
	_stand(0.0, 7.0)
	await _wait(0.5)
	await _check_all("起動のあと")
	# 地図の外（ずっと遠く）でも、地図の縁の内側で止まる
	var edge: Vector2 = Flags.on_board(Vector2(5000, 5000))
	_ok(absf(edge.x) < Flags.BOARD.x / 2.0 and edge.y > Flags.BOARD_Y, "地図の外は縁の内側で止まる: %s" % edge)
	await _shot("near_start")
	var t0 := Time.get_ticks_usec()
	for i in 100:
		pins._stick()
	_say("全員を刺し直す 1 回: %.1f µs（12 コマ／秒で、看板のそばだけ）" % ((Time.get_ticks_usec() - t0) / 100.0))
	_stand(-2.2, 2.6)
	await _wait(0.3)
	await _shot("close_start")
	_stand(0.0, 7.0)
	# 頂上の旗の絵とロッジに合うか: CPU を運ぶ
	var bots := _bots()
	var spots := [Vector2(0, 0), Vector2(Flags.PLACES.slope[2]), Vector2(Flags.PLACES.peak[2]), Vector2(-35, 98)]
	for i in mini(bots.size(), spots.size()):
		var s: Vector2 = spots[i]
		bots[i].global_position = Vector3(s.x, main.height(s.x, s.y) + 0.3, s.y)
	await _wait(0.3)
	await _check_all("運んだあと")
	await _shot("landmarks")
	# 遠くでは隠れる
	var at: Vector3 = p.global_position
	p.global_position = Vector3(at.x, at.y + 200.0, at.z)
	await _wait(0.3)
	_ok(not pins.visible, "遠くから見ているときは隠れる")
	p.global_position = at
	await _wait(0.3)
	_ok(pins.visible, "戻ると出る")
	_stand(0.0, 7.0)
	var secs := int(args.get("secs", "60"))
	for i in int(secs / 2.0):
		await _wait(2.0)
		_table()
		await _shot("frame_%03d" % i)
	await _check_all("動いたあと")


func _run_host() -> void:
	_stand(-1.5, 7.0)
	await _check_all("ひとりのとき")
	var n0: int = pins.pins().size()
	var t := 0.0
	while main.net.remotes.is_empty() and t < 60.0:
		await _wait(0.5)
		t += 0.5
	_ok(not main.net.remotes.is_empty(), "人が来た")
	await _wait(1.0)
	await _check_all("来たあと")
	_ok(pins.pins().size() == n0 + 1, "来た人のまち針が増えた: %d → %d" % [n0, pins.pins().size()])
	t = 0.0
	var shot := false
	while not main.net.remotes.is_empty() and t < 60.0:   # 帰るまで、1 秒ごとに表を書く
		await _wait(1.0)
		t += 1.0
		_table()
		if t >= 8.0 and not shot:
			shot = true
			await _shot("host")
	await _wait(0.5)
	_ok(pins.pins().size() == n0, "帰った人のまち針が消えた: %d 本" % pins.pins().size())
	await _shot("host_after")


func _run_join() -> void:
	_stand(1.5, 7.0)
	var t := 0.0
	while main.net.cpus.size() < int(args.get("cpus", "5")) and t < 30.0:
		await _wait(0.5)
		t += 0.5
	await _wait(1.0)
	_ok(main.net.cpus.size() == int(args.get("cpus", "5")), "CPU が来た: %d 人" % main.net.cpus.size())
	await _check_all("つないだあと")
	for i in 12:
		await _wait(1.0)
		_table()
		if i == 6:
			await _shot("join")
