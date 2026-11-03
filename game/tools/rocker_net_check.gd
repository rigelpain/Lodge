extends SceneTree
## 通信の確かめ: ホストが揺り椅子に座り、揺れる人形と椅子の所が、ホストの画面とつなぐ側の画面でそろうか。
##   Godot --path game --resolution 960x540 -s res://tools/rocker_net_check.gd -- --host --port=24692 --spawn=inside --lodge-bots=0 --tag=host --dir=/path
##   Godot --path game --resolution 960x540 -s res://tools/rocker_net_check.gd -- --join=127.0.0.1 --port=24692 --spawn=inside --lodge-bots=0 --tag=join --dir=/path
## 座りきってから 4 秒、ホストの人形（つなぐ側ではその人の人形）の傾きが変わるたびに、
##   傾き・人形の所・弓の円の中心（椅子といっしょに動く点）・椅子に対しての人形の所 を rock_<tag>.txt に書く。
## くらべるときは、同じ傾きの行どうしで所の差を見る（同じ傾きなら、どの画面でも同じ所になるはず）

const Nook := preload("res://hearth_nook.gd")

var args := {}
var main: Node3D
var lines: Array[String] = []
var _doll
var _chair: Node3D
var _last := INF
var _rec := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/rocker_net"))
	RenderingServer.frame_pre_draw.connect(_sample)
	_run.call_deferred()


func _tag() -> String:
	return args.get("tag", "host" if args.has("host") else "join")


func _wait(t: float) -> void:
	await create_timer(t).timeout


## 描く直前（そのフレームの動きがすべて済んで、画面に出る形）に書く
func _sample() -> void:
	if not _rec or not is_instance_valid(_doll) or _chair == null:
		return
	if _doll.rock == _last:
		return
	_last = _doll.rock
	var p: Vector3 = _doll.global_position
	var c: Vector3 = _chair.global_transform * Nook.ROCK_PIVOT
	var rel: Vector3 = _chair.global_transform.affine_inverse() * p
	lines.append("%.5f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f" % [_doll.rock, p.x, p.y, p.z, c.x, c.y, c.z, rel.x, rel.y, rel.z, _doll.rock_roll])


func _run() -> void:
	await _wait(1.0)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	print("[%s] %s" % [_tag(), "相手が見えた" if not main.net.remotes.is_empty() else "相手が来なかった"])
	await _wait(1.5)
	var seats = main.seats
	var si := -1
	for i in seats.seats.size():
		if seats.seats[i].kind == "rocker":
			si = i
			break
	var st: Dictionary = seats.seat(si)
	if args.has("host"):
		main.player.global_position = st.stand + Vector3.UP * 0.05
		seats.send({"kind": "sit", "who": main.player.id, "seat": si})
	var nook := main.find_child("HearthNook", true, false)
	for r in nook._rockers:
		if (r[2] as Node3D).global_position.distance_to(st.pos) < 0.05:
			_chair = r[0]
	await _wait(3.0)
	_doll = main.player.doll if args.has("host") else main.net.remotes.values()[0].doll
	_rec = true
	await _wait(4.0)
	_rec = false
	var f := FileAccess.open("%s/rock_%s.txt" % [args.get("dir", "/tmp/rocker_net"), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines))
	print("[%s] 書いた %d 行" % [_tag(), lines.size()])
	quit()
