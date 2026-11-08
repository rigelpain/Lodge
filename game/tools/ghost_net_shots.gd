extends SceneTree
## 観戦モード（ghost.gd）の通信の確かめ: 同じ Mac で 2 つ起動し、1 つをホスト、1 つをつなぐ側にする（ホストを先に）。
##   Godot --path game --resolution 960x540 --position 0,40 -s res://tools/ghost_net_shots.gd -- --host --port=24790 --dir=/path/shots --no-sound
##   Godot --path game --resolution 960x540 --position 980,40 -s res://tools/ghost_net_shots.gd -- --join=127.0.0.1 --port=24790 --dir=/path/shots --no-sound
## 二人は 5 m 離れて向かい合う。前半はつなぐ側が、後半はホストが抜ける: 体 → 見えない霊体（抜けた所の 1 m 上へ）→ 見える霊体 → 体。
## 見ている側の画面を段ごとに撮り（<見ている側>_<段>.png）、相手の体の人形が見えるか・名簿にいるか・仲間から見えるかを log に書く。
## 見える霊体の段では、見ている側の姿の案（ghost.gd の LOOKS）を a・b・c と替えて撮る

const PERIOD := 4.0
const Ghost := preload("res://ghost.gd")

var args := {}
var main: Node3D
var host := false
var lines: Array[String] = []
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	host = args.has("host")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/ghost_net_shots")


func _tag() -> String:
	return "host" if host else "join"


func _say(s: String) -> void:
	var l := "[%s] %s" % [_tag(), s]
	print(l)
	lines.append(l)


func _check(ok: bool, s: String) -> void:
	_say(("○ " if ok else "× ") + s)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	for i in 6:   # 色を替えた直後は新しい材料の支度で写りが遅れるので、数コマ待つ
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_dir(), _tag(), name])


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame


func _spot(of_host: bool) -> Vector3:
	var at := Vector3(main.START.x + 4.0, 0, main.START.z - (0.0 if of_host else 5.0))
	at.y = main.height(at.x, at.z) + 0.1
	return at


func _run() -> void:
	await create_timer(0.5).timeout
	var t := 0.0
	while main.net.remotes.is_empty() and t < 40.0:
		await create_timer(0.25).timeout
		t += 0.25
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	# 始まりの時刻: つながった時刻（2 つでほぼ同じ）の 12 秒後を 10 秒に丸める。区切りの直前に
	# つながると片方だけ次の区切りになり、段が 1 つずれるので、近い方へ丸めてずれにくくする
	var start := roundf((Time.get_unix_time_from_system() + 12.0) / 10.0) * 10.0
	var p: CharacterBody3D = main.player
	var me := _spot(host)
	p.global_position = me
	p.velocity = Vector3.ZERO
	_face()
	main.settings.set_open(false)
	p.menu_open = false
	var step := 0
	for ghost_is_host in [false, true]:
		for stage in ["1_body", "2_hidden", "3_seen", "4_back"]:
			await create_timer(start + step * PERIOD - Time.get_unix_time_from_system()).timeout
			step += 1
			await _stage(ghost_is_host, stage)
	await create_timer(1.0).timeout
	_say("食い違い %d" % fails)
	var f := FileAccess.open("%s/log_%s.txt" % [_dir(), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(1 if fails > 0 else 0)


## 相手の立つ所へ向く
func _face() -> void:
	var p: CharacterBody3D = main.player
	var d := _spot(not host) - _spot(host)
	p.rotation.y = atan2(-d.x, -d.z)
	p._pitch = -0.05


## 段: 抜ける人は操作し、見ている人は撮って、相手の体を調べる
func _stage(ghost_is_host: bool, stage: String) -> void:
	var mine := ghost_is_host == host
	var g: Node = main.ghost
	var who := "ホスト" if ghost_is_host else "つなぐ側"
	if mine:
		match stage:
			"2_hidden":
				g.enter()
				await process_frame
				g.cam.global_position = main.player.global_position + Vector3.UP * (Ghost.EYE + 1.0)   # 抜けた所の 1 m 上に浮かぶ
			"3_seen":
				g.set_seen(true)
			"4_back":
				g.leave()
		await create_timer(1.6).timeout
		if stage == "2_hidden":
			await _shot("%s_ghost_%s" % [stage, "host" if ghost_is_host else "join"])   # 霊体の画面（案内のワッペン）
		return
	await create_timer(1.6).timeout   # 届くまで
	_face()   # 窓の上をマウスが通ると向きが変わるので、撮る前に相手へ向き直す
	var r: Node3D = main.net.remotes.values()[0]
	var pid := int(r.peer)
	var people_has: bool = main.emotes.people.get(pid) == r
	var in_humans := true
	var bots := get_nodes_in_group("bots")
	if host and not bots.is_empty():
		in_humans = bots[0]._humans().has(r)
	var pals_shown := false   # その人の連れ（companions.gd。付けていれば）
	for c in main.get_children():
		if c.get("host") == r:
			pals_shown = c.visible
	_say("%s %s: 霊体=%d 人形が見える=%s 名簿=%s 仲間から=%s 位置=%s" % [who, stage, r.ghost, r.doll.is_visible_in_tree(), people_has, in_humans if host else "-", r.global_position.snapped(Vector3.ONE * 0.01)])
	match stage:
		"1_body", "4_back":
			_check(r.ghost == 0 and r.doll.is_visible_in_tree() and people_has, "%s %s: 体が見えて名簿にいる" % [who, stage])
			if host:
				_check(in_humans, "%s %s: 仲間から見える" % [who, stage])
			await _shot("%s_by_%s" % [stage, "host" if ghost_is_host else "join"])
		"2_hidden":
			_check(r.ghost == 1 and not r.doll.is_visible_in_tree() and not people_has and not pals_shown, "%s 見えない霊体: 人形・連れが出ず、名簿にいない" % who)
			if host:
				_check(not in_humans, "%s 見えない霊体: 仲間から見えない" % who)
			await _shot("%s_by_%s" % [stage, "host" if ghost_is_host else "join"])
		"3_seen":
			_check(r.ghost == 2 and r.doll.is_visible_in_tree() and not people_has, "%s 見える霊体: 人形が出て、名簿にはいない" % who)
			var at: Vector3 = _spot(ghost_is_host) + Vector3.UP * 1.0
			_check(r.global_position.distance_to(at) < 0.3, "%s 見える霊体: 抜けた所の 1 m 上に浮かぶ（ずれ %.2f m）" % [who, r.global_position.distance_to(at)])
			for look in ["a", "b", "c"]:
				Ghost.look = look
				Ghost.paint(r.doll, true)
				await _shot("%s_%s_by_%s" % [stage, look, "host" if ghost_is_host else "join"])
			Ghost.look = "b"
