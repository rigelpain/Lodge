extends SceneTree
## 通信の確かめ（目の高さ）: 同じ Mac で 2 つ起動し、ホストとつなぐ側で別の人形を着て、ソリのうしろで向かい合って立つ。
## 自分のカメラの高さ（世界）と、相手の画面に見える自分の人形の目の高さ（世界）が合うかを、log_<tag>.txt で比べる。
##   Godot --path game --resolution 960x540 --position 0,40 -s res://tools/eye_net_check.gd -- --host --doll=golem --dir=/path
##   Godot --path game --resolution 960x540 --position 980,40 -s res://tools/eye_net_check.gd -- --join=127.0.0.1 --doll=musha --dir=/path
## 撮る絵: <tag>_face.png（一人称で相手を見る）

var args := {}
var main: Node3D
var p: CharacterBody3D
var lines: Array[String] = []
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	args["bots"] = "0"
	args["lodge-bots"] = "0"
	args["roam-bots"] = "0"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/eye_net")


func _tag() -> String:
	return "host" if args.has("host") else "join"


func _say(s: String) -> void:
	var line := "[%s %.1f] %s" % [_tag(), (Time.get_ticks_msec() - _t0) / 1000.0, s]
	print(line)
	lines.append(line)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _stand() -> void:
	# ソリの 4 m うしろで、ホストは左・つなぐ側は右に 1.2 m ずつ離れて、向かい合う
	var s: Node3D = main.sled
	var back: Vector3 = s.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var side := back.cross(Vector3.UP).normalized()
	var me := -1.0 if args.has("host") else 1.0
	var at: Vector3 = s.global_position + back * 4.0 + side * 1.2 * me
	at.y = main.height(at.x, at.z) + 0.05
	p.global_position = at
	var look := -side * me
	p.rotation.y = atan2(-look.x, -look.z)
	p._pitch = 0.0
	p.velocity = Vector3.ZERO


func _run() -> void:
	await _wait(0.5)
	p = main.player
	p.set_third(false)
	if main.settings:
		main.settings.set_open(false)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	_say("相手が見えた" if not main.net.remotes.is_empty() else "相手が来なかった")
	for i in 8:
		_stand()
		await _wait(0.5)
	for i in 3:
		_stand()
		var r := ""
		for pid in main.net.remotes:
			var rp: Node3D = main.net.remotes[pid]
			var d = rp.doll
			var eye_w: Vector3 = d.global_transform * d.eye_point(false)
			r += " 相手の人形=%s 足もと=%.3f 目=%.3f 背丈=%.2f" % [d.kind, rp.global_position.y, eye_w.y, d.height()]
		_say("自分の人形=%s 足もと=%.3f カメラ=%.3f（目 %.2f m）%s" % [p.doll.kind, p.global_position.y, p.cam.global_position.y, p.eye_height(), r])
		await _wait(0.5)
	if main.hud:
		main.hud.visible = false
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_face.png" % [_dir(), _tag()])
	_say("撮った face")
	await _wait(1.5)   # 相手が撮り終えるまで残る
	var f := FileAccess.open("%s/log_%s.txt" % [_dir(), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines))
	quit()
