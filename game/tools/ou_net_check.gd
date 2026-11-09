extends SceneTree
## 通信の確かめ（おーいで手を振る・おうで片手を上げる）: 同じ Mac で 2 つ起動し、1 つをホスト、1 つをつなぐ側にする。
##   Godot --path game --resolution 640x360 --position 0,40 -s res://tools/ou_net_check.gd -- --host --port=24761 --bots=0 --lodge-bots=0 --roam-bots=0 --no-pip --no-buttons --no-lodge --dir=/path/out
##   （ホストが「ホストになった」と出してから）同じ引数で --host を --join=127.0.0.1 に替えて、--position 660,40
## 二人は 4 m 離れて向き合う。つなぐ側が「おう」、ホストが「おう」、つなぐ側が「おーい」、ホストが「おーい」の順に出す。
## 両方の画面で、自分の人形とほかの人の人形が身ぶりを始めたコマと、手の高さ（頭から。上がった手は +）、
## 鳴った声（自分の声は耳元、ほかの人の声はその場所から）を log_<tag>.txt に書き、ほかの人の身ぶりを自分の目で撮る。
## よい: どちらの画面でも、4 つの身ぶりが同じコマで始まり、おうは片手、おーいは振る手が頭より上にあり、声が 4 つ鳴る

const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var lines: Array[String] = []
var _seen := {}   # 人形の名前 → いま見ている身ぶりの始まりのコマ
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
	return args.get("dir", "/tmp/ou_net_check")


func _tag() -> String:
	return "host" if args.has("host") else "join"


func _say(s: String) -> void:
	var line := "[%s %.1f] %s" % [_tag(), (Time.get_ticks_msec() - _t0) / 1000.0, s]
	print(line)
	lines.append(line)


func _wait(t: float) -> void:
	await create_timer(t).timeout


## 手の高さ（頭の骨から。m）
func _hands(d: Doll) -> String:
	var head := (d.skel.global_transform * d.skel.get_bone_global_pose(d.skel.find_bone("head"))).origin.y
	var r := (d.skel.global_transform * d.skel.get_bone_global_pose(d.skel.find_bone("hand.R"))).origin.y - head
	var l := (d.skel.global_transform * d.skel.get_bone_global_pose(d.skel.find_bone("hand.L"))).origin.y - head
	return "右 %+.2f 左 %+.2f" % [r, l]


func _watch() -> void:
	if p == null:
		return
	var dolls := {"自分": p.doll}
	for id in main.net.remotes:
		dolls["人%d" % id] = main.net.remotes[id].doll
	for name in dolls:
		var d: Doll = dolls[name]
		var em := d.emote_now()
		if not em[0] in ["ou", "oi"]:
			continue
		var start: int = Doll.frame_index() - int(em[1])
		if _seen.get(name, -1) != start:
			_seen[name] = start
			_say("%s が %s を始めた（コマ %d）" % [name, em[0], start])
		var at := 4 if em[0] == "ou" else 8
		if int(em[1]) == at and _seen.get(name + "_at", -1) != start:
			_seen[name + "_at"] = start
			_say("  %s の %s の %d コマ目: 手の高さ %s" % [name, em[0], at, _hands(d)])
			if name != "自分":
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png("%s/%s_seen_by_%s.png" % [_dir(), em[0], _tag()])


func _run() -> void:
	await _wait(0.5)
	p = main.player
	var audio := main.get_node_or_null("Audio")
	if audio:
		audio.log_on = true
	var t := 0.0
	while main.net.remotes.is_empty() and t < 120.0:
		await _wait(0.5)
		t += 0.5
	await _wait(2.5 if not args.has("host") else 6.0)   # つなぐ側が読み込み終わるまで、ホストは長めに待つ
	_say("自分=%d ほかの人=%s" % [p.id, str(main.net.remotes.keys())])
	# 向き合う（ホストは西、つなぐ側は東。4 m）
	var at: Vector3 = main.START + Vector3(4, 0, 4)
	var x := -2.0 if args.has("host") else 2.0
	p.global_position = Vector3(at.x + x, main.height(at.x + x, at.z) + 0.1, at.z)
	p.rotation.y = -PI / 2 if args.has("host") else PI / 2
	p._pitch = 0.05
	await _wait(3.0)
	# 順番: つなぐ側のおう → ホストのおう → つなぐ側のおーい → ホストのおーい
	for step in [["join", "ou"], ["host", "ou"], ["join", "oi"], ["host", "oi"]]:
		if step[0] == _tag():
			p.emote(step[1])
		await _wait(3.0)
	await _wait(1.0)
	if audio:
		for n in audio.played:
			if String(n.name).begins_with("voice_o"):
				_say("声 %s 耳元=%s 距離 %.1f m" % [n.name, n.near, n.dist])
	var f := FileAccess.open("%s/log_%s.txt" % [_dir(), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
