extends SceneTree
## ホストの操作の確かめ（host_panel.gd・net.gd の host_purse・host_warp・host_world）: 同じ Mac で 2 つ起動し、1 つをホスト、1 つをつなぐ側にする。
##   Godot --path game --resolution 960x600 --position 0,40 -s res://tools/host_panel_net_check.gd -- --host --port=24771 --roam-bots=0 --no-pip --dir=/path/out
##   （ホストが「ホストになった」と出してから）同じ引数で --host を --join=127.0.0.1 に替えて、--position 980,40
## ホスト: つなぐ人が来たら、設定の画面を開いてホストの操作を撮る → その人の財布を 1234 に → その人を自分のそばへ呼ぶ
##   → 自分をはじめの所へ → ワールドを天下森へ。作り直したあと、つなぐ人がまた来るのを待つ
## よい: つなぐ側の財布が 1234、つなぐ側の体がホストの前 1.8 m、ワールドを替えたあと両方とも tenkamori で、またつながっている

var args := {}
var main: Node3D
var lines: Array[String] = []
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # ワールドを替えると場面を読み直すので
	DirAccess.make_dir_recursive_absolute(_dir())
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/host_panel_net_check")


func _tag() -> String:
	return "host" if args.has("host") else "join"


func _say(s: String) -> void:
	var line := "[%s %.1f] %s" % [_tag(), (Time.get_ticks_msec() - _t0) / 1000.0, s]
	print(line)
	lines.append(line)
	var f := FileAccess.open(_dir() + "/log_%s.txt" % _tag(), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(nm: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir() + "/%s.png" % nm)


## 読み直したあとの main（current_scene）
func _main() -> Node3D:
	return current_scene as Node3D


func _run() -> void:
	if args.has("host"):
		await _host()
	else:
		await _join()
	quit()


func _host() -> void:
	var m := _main()
	if args.has("solo-shot"):   # 一人のホストで、設定の画面のホストの操作だけ撮る
		await _wait(3.0)
		m.settings.set_open(true)
		await _wait(1.5)
		await _shot("host_panel_solo")
		return
	var t := 0.0
	while m.net.remotes.is_empty() and t < 150.0:
		await _wait(0.5)
		t += 0.5
	if m.net.remotes.is_empty():
		_say("つなぐ人が来ない")
		return
	var who: int = m.net.remotes.keys()[0]
	await _wait(2.0)
	_say("来た: %d 財布 %d" % [who, m.craft.wallet(who)])
	m.settings.set_open(true)
	await _wait(1.0)
	_say("ホストの操作の行: %d" % m.settings.host_slot.get_child_count())
	await _shot("host_panel")
	m.net.host_purse(who, 1234)
	_say("財布を 1234 に → ホストの数 %d" % m.craft.wallet(who))
	await _wait(1.0)
	m.get_node("HostPanel")._call(who)
	await _wait(1.5)
	var r: Node3D = m.net.remotes[who]
	var me: Node3D = m.player
	_say("呼んだ: つなぐ人まで %.2f m（水平）" % Vector2(r.global_position.x - me.global_position.x, r.global_position.z - me.global_position.z).length())
	await _shot("host_called")
	m.get_node("HostPanel")._start(int(me.id))
	await _wait(0.5)
	_say("自分をはじめの所へ: %s（はじめの所 %s）" % [me.global_position, m.start_pos()])
	m.settings.set_open(false)
	await _wait(1.0)
	_say("ワールドを天下森へ")
	m.net.host_world("tenkamori")
	await _wait(2.0)
	t = 0.0
	while t < 60.0:
		m = _main()
		if m and m.is_inside_tree() and m.get("net") and not m.net.remotes.is_empty():
			break
		await _wait(0.5)
		t += 0.5
	m = _main()
	_say("作り直したあと: ワールド %s ホスト %s 来ている人 %d" % [m.stage, m.net.is_host(), m.net.remotes.size()])
	await _wait(3.0)
	await _shot("host_after_world")


func _join() -> void:
	var m := _main()
	var last_w := -1
	var t := 0.0
	var moved := false
	while t < 240.0:
		m = _main()
		if m and m.is_inside_tree() and m.get("player") and m.get("craft"):
			if m.stage == "tenkamori":
				moved = true
				if m.net.joined():
					break
			elif m.player.id >= 0:
				var w: int = m.craft.wallet(m.player.id)
				if w != last_w:
					_say("自分の財布: %d" % w)
					last_w = w
		await _wait(0.25)
		t += 0.25
	m = _main()
	_say("終わり: ワールド %s 移った %s つながっている %s ほかの人 %d" % [m.stage, moved, m.net.joined(), m.net.remotes.size()])
	await _wait(3.0)
	await _shot("join_after_world")
