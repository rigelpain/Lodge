extends SceneTree
## 通信の確かめ（手形を出すあいだ元の手を隠す）: 同じ Mac で 2 つ起動し、1 つをホスト、1 つをつなぐ側にする。
##   Godot --path game --resolution 640x360 --position 0,40 -s res://tools/hand_hide_net_check.gd -- --host --dir=/path/out
##   Godot --path game --resolution 640x360 --position 660,40 -s res://tools/hand_hide_net_check.gd -- --join=127.0.0.1 --dir=/path/out
## 二人は離れて背を向けて立つ（手が合わない）。ホストは高い右手、つなぐ側は低い両手を掲げ、しばらくして下ろす。
## 両方の画面で、自分の人形とほかの人の人形の、手形が見えるか・元の手の骨の大きさが変わったコマを log_<tag>.txt に書く。
## どちらの画面でも、手形が出たコマに手が隠れ、手形が消えたコマに手が戻っていれば よい（ずれていれば「ずれ」と書く）

const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var lines: Array[String] = []
var _last := {}   # 人形の名前 → [右の手形, 左の手形, 右手が隠れている, 左手が隠れている]
var _bad := 0
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_t0 = Time.get_ticks_msec()
	physics_frame.connect(_watch)
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/hand_hide_net_check")


func _tag() -> String:
	return "host" if args.has("host") else "join"


func _say(s: String) -> void:
	var line := "[%s %.1f] %s" % [_tag(), (Time.get_ticks_msec() - _t0) / 1000.0, s]
	print(line)
	lines.append(line)


func _wait(t: float) -> void:
	await create_timer(t).timeout


## 人形ごとに、手形が見えるか・元の手が隠れているかが変わったら書く。左右それぞれ、両方がそろっていなければ「ずれ」
func _watch() -> void:
	if p == null:
		return
	var dolls := {"自分": p.doll}
	for id in main.net.remotes:
		dolls["人%d" % id] = main.net.remotes[id].doll
	for name in dolls:
		var d: Doll = dolls[name]
		var now := []
		for side in [1, -1]:
			var shown := false
			for sh in d._shapes:
				shown = shown or (d._shapes[sh][side] as Node3D).visible
			now.append(shown)
		for bone in ["hand.R", "hand.L"]:
			now.append(d.skel.get_bone_pose_scale(d.skel.find_bone(bone)).x < 0.5)
		if now != _last.get(name, []):
			_last[name] = now
			var ok: bool = now[0] == now[2] and now[1] == now[3]
			if not ok:
				_bad += 1
			_say("コマ %d %s: 手形 右=%s 左=%s / 元の手を隠す 右=%s 左=%s%s" % [Doll.frame_index(), name, now[0], now[1], now[2], now[3], "" if ok else "  ずれ"])


func _run() -> void:
	await _wait(0.5)
	p = main.player
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	await _wait(2.5 if not args.has("host") else 6.0)   # つなぐ側が読み込み終わるまで、ホストは長めに待つ
	_say("自分=%d ほかの人=%s" % [p.id, str(main.net.remotes.keys())])
	# 離れて背を向ける（ホストは西、つなぐ側は東。4 m）
	var at: Vector3 = main.START + Vector3(4, 0, 4)
	var x := -2.0 if args.has("host") else 2.0
	p.global_position = Vector3(at.x + x, main.height(at.x + x, at.z) + 0.1, at.z)
	p.rotation.y = PI / 2 if args.has("host") else -PI / 2
	await _wait(2.0)
	if args.has("host"):
		p._set_hand("R")
		p.set_height("high")
	else:
		await _wait(0.5)
		p._set_hand("both")
		p.set_height("low")
	await _wait(2.5)
	p.set_height("")
	await _wait(4.0)
	_say("ずれ=%d" % _bad)
	var f := FileAccess.open("%s/log_%s.txt" % [_dir(), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
