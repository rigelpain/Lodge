extends SceneTree
## 通信の確かめ（身ぶりとクラフト）: 同じ Mac で 2 つ起動し、1 つをホスト、1 つをつなぐ側にする。
##   Godot --path game --resolution 960x540 --position 0,40 -s res://tools/net_emote_shots.gd -- --host --dir=/path/shots
##   Godot --path game --resolution 960x540 --position 980,40 -s res://tools/net_emote_shots.gd -- --join=127.0.0.1 --dir=/path/shots
## 流れ: 向かい合って高い手のひらを掲げる（ハイタッチはホストが決める）→ つなぐ側が雪玉を丸めてホストに投げる（当たりはホストが決める）
##   → つなぐ側が米袋の型紙を買い、ランタンを点ける・ホストが布を買う。
## 両方の画面で、届いた身ぶりの出来事と、二人の財布・持ち物・ランタン・雪玉の数を log_<tag>.txt に書く

var args := {}
var main: Node3D
var p: CharacterBody3D
var lines: Array[String] = []
var seen: Array[String] = []
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/net_emote_shots")


func _tag() -> String:
	return args.get("tag", "host" if args.has("host") else "join")


func _say(s: String) -> void:
	var line := "[%s %.1f] %s" % [_tag(), (Time.get_ticks_msec() - _t0) / 1000.0, s]
	print(line)
	lines.append(line)


func _wait(t: float) -> void:
	await create_timer(t).timeout


## 横から二人を撮る（向かい合った真ん中を、南の 3.2 m 先から）
func _shot(name: String) -> void:
	var cam := Camera3D.new()
	main.add_child(cam)
	var mid: Vector3 = main.START + Vector3(4, 0, 4)
	mid.y = main.height(mid.x, mid.z) + 1.0
	cam.position = mid + Vector3(0, 0.6, 3.2)
	cam.look_at(mid)
	cam.make_current()
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_dir(), _tag(), name])
	cam.queue_free()
	p.cam.make_current()
	_say("撮った " + name)


func _other() -> int:
	return main.net.remotes.keys()[0] if not main.net.remotes.is_empty() else -1


func _log() -> void:
	var c: Node = main.craft
	var h: Node = main.emotes
	var s := ""
	for who in [p.id, _other()]:
		s += " 人%d: 財布=%d 持ち物=%s ランタン=%s 雪玉=%d 人形=%s" % [who, c.wallet(who), c.bag(who).map(func(it): return it.get("sled", it.get("fabric", "?"))),
			c.lamp_on(who), h.balls_of(who), c.doll_of(who)]
	_say(s)


func _run() -> void:
	await _wait(0.5)
	p = main.player
	p.set_third(true)
	p.cam_dist = 3.0
	main.emotes.happened.connect(func(ev: Dictionary): seen.append("%s(%d)" % [ev.kind, int(ev.get("who", -1))]))
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	await _wait(2.5)
	_say("自分=%d 相手=%d" % [p.id, _other()])
	_log()
	# 向かい合う（ホストは西、つなぐ側は東。1 m）
	var at: Vector3 = main.START + Vector3(4, 0, 4)
	var x := -0.5 if args.has("host") else 0.5
	p.global_position = Vector3(at.x + x, main.height(at.x + x, at.z) + 0.1, at.z)
	p.rotation.y = -PI / 2 if args.has("host") else PI / 2   # 相手のほうへ（-z が前）
	p.set_third(true)
	await _wait(2.0)
	p.set_hands("high_R")
	await _wait(0.5)
	await _shot("1_five")
	await _wait(1.5)
	_say("届いた身ぶり: " + ", ".join(seen))
	seen.clear()
	# つなぐ側が雪玉を丸めて、ホストに投げる
	if not args.has("host"):
		main.emotes.send({"kind": "make_ball", "who": p.id})
	await _wait(3.0)
	_log()
	if not args.has("host"):
		var to: Vector3 = main.net.remotes[_other()].global_position + Vector3.UP * 1.0
		var from: Vector3 = p.global_position + Vector3.UP * 1.4 + (to - p.global_position).normalized() * 0.3
		main.emotes.send({"kind": "throw", "who": p.id, "origin": from, "velocity": (to - from).normalized() * 9.0})
	await _wait(0.25)
	await _shot("2_hit")
	await _wait(1.5)
	_say("届いた身ぶり: " + ", ".join(seen))
	# 買う・ランタン
	if args.has("host"):
		main.craft.send({"kind": "buy", "who": p.id, "item": {"kind": "fabric", "fabric": "navy"}})
	else:
		main.craft.send({"kind": "buy", "who": p.id, "item": {"kind": "pattern", "sled": "sack"}})
		main.craft.send({"kind": "lamp", "who": p.id, "on": true})
	await _wait(2.0)
	_log()
	await _shot("3_craft")
	if args.has("host"):   # つなぐ側の出来事が遅れて届く分を待ってから、もう一度書く
		await _wait(6.0)
		_say("届いた身ぶり: " + ", ".join(seen))
		_log()
	var f := FileAccess.open("%s/log_%s.txt" % [_dir(), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	await _wait(2.0)
	quit()

