extends SceneTree
## 通信の確かめ: ホストがロッジの椅子に座り、つなぐ側の画面のホストの人形が、ホストの画面と同じ座り方（席の奥行き・脚の向き）になるか。
##   Godot --path game --resolution 960x540 -s res://tools/sit_net_check.gd -- --host --port=24690 --spawn=inside --tag=host --dir=/path/shots
##   Godot --path game --resolution 960x540 -s res://tools/sit_net_check.gd -- --join=127.0.0.1 --port=24690 --spawn=inside --tag=join --dir=/path/shots
## 両方の画面で、ホストの人形の seat_edge・座る段・太もも・すね・足の向き（人形の座標）を log_<tag>.txt に書く。つなぐ側は横から撮る

const LEGS := ["thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"]

var args := {}
var main: Node3D
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/sit_net")


func _tag() -> String:
	return args.get("tag", "host" if args.has("host") else "join")


func _say(s: String) -> void:
	print("[%s] %s" % [_tag(), s])
	lines.append(s)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _run() -> void:
	await _wait(1.0)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	_say("相手が見えた" if not main.net.remotes.is_empty() else "相手が来なかった")
	await _wait(1.5)
	var p = main.player
	if args.has("host"):
		var seats = main.seats
		var list := []
		for i in seats.seats.size():
			if seats.seats[i].kind == args.get("seat", "chair"):
				list.append(i)
		var si: int = list[list.size() / 2]
		var st: Dictionary = seats.seat(si)
		p.global_position = st.stand + Vector3.UP * 0.05
		seats.send({"kind": "sit", "who": p.id, "seat": si})
		_say("座る席 %d（奥行き %.3f m）" % [si, st.edge])
	await _wait(3.0)
	# ホストの人形: ホストの画面では自分、つなぐ側では Remote1
	var doll = p.doll if args.has("host") else main.net.remotes[1].doll
	_say("人形 %s 動き %d 段 %d 座面の高さ %.3f 奥行き %.3f 居場所 %s" % [doll.kind, doll.act, doll.sit_stage, doll.seat_drop, doll.seat_edge, doll.global_position.snapped(Vector3.ONE * 0.01)])
	for b in LEGS:
		var i: int = doll.skel.find_bone(b)
		var y: Vector3 = doll.skel.get_bone_global_pose(i).basis.y.normalized()
		_say("%s の向き (%.2f, %.2f, %.2f)" % [b, y.x, y.y, y.z])
	if not args.has("host"):
		var cam := Camera3D.new()
		root.add_child(cam)
		var side: Vector3 = doll.global_basis.x
		var c: Vector3 = doll.global_position + Vector3.UP * 0.3
		cam.look_at_from_position(c + side * 2.2 + Vector3.UP * 0.3, c)
		cam.near = 1.6
		cam.current = true
		for c2 in root.find_children("*", "CanvasLayer", true, false):
			c2.visible = false
		await _wait(0.5)
		root.get_viewport().get_texture().get_image().save_png("%s/join_side.png" % _dir())
		_say("撮った join_side.png")
	var f := FileAccess.open("%s/log_%s.txt" % [_dir(), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	await _wait(1.0)
	quit()
