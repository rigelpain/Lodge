extends SceneTree
## 通信の確かめ: ホストがビーズクッションに座って見回し、体の向き（人形の _yaw）ともたれの軸が、ホストの画面とつなぐ側の画面でそろうか。
##   Godot --path game --resolution 960x540 -s res://tools/beanbag_net_check.gd -- --host --port=24691 --spawn=inside --lodge-bots=0 --tag=host --dir=/path
##   Godot --path game --resolution 960x540 -s res://tools/beanbag_net_check.gd -- --join=127.0.0.1 --port=24691 --spawn=inside --lodge-bots=0 --tag=join --dir=/path
## ホストは座りきってから、見る向きを 60° ずつ 6 回回す（3 回目から三人称）。両方の画面で、回すたびに 1.2 秒待ってから
## ホストの人形の向き・もたれの軸・もたれの角を log_<tag>.txt に書く。ホストの画面では、はじめの 1 回の回り方（コマごとの向き）も書く

var args := {}
var main: Node3D
var lines: Array[String] = []
var _trace := false
var _last_yaw := INF
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/beanbag_net")


func _tag() -> String:
	return args.get("tag", "host" if args.has("host") else "join")


func _say(s: String) -> void:
	print("[%s] %s" % [_tag(), s])
	lines.append(s)


func _wait(t: float) -> void:
	await create_timer(t).timeout


## はじめの 1 回: 人形の向きが変わったときだけ、時刻（ms）とコマと向きを書く
func _physics_process(_dt: float) -> bool:
	if _trace and main.player:
		var y: float = main.player.doll.get("_yaw")
		if y != _last_yaw:
			_say("  %4d ms コマ %d 向き %.1f°" % [Time.get_ticks_msec() - _t0, preload("res://doll.gd").frame_index(), rad_to_deg(wrapf(y, -PI, PI))])
			_last_yaw = y
	return false


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
		for i in seats.seats.size():
			if seats.seats[i].kind == "beanbag":
				var st: Dictionary = seats.seat(i)
				p.global_position = st.stand + Vector3.UP * 0.05
				seats.send({"kind": "sit", "who": p.id, "seat": i})
				_say("座る席 %d（ビーズクッション）" % i)
				break
	await _wait(3.0)
	var doll = p.doll if args.has("host") else main.net.remotes[1].doll
	var base: float = p.rotation.y
	for k in 7:
		if args.has("host") and k > 0:
			if k == 1:
				_trace = true
				_t0 = Time.get_ticks_msec()
			if k == 3:
				p.set_third(true)
			p.rotation.y = base + deg_to_rad(60.0 * k)
		await _wait(1.2)
		_trace = false
		if not is_instance_valid(doll):   # 相手が帰った
			break
		var ax: Vector3 = Basis(Vector3.UP, doll.get("_yaw")) * Vector3.RIGHT if doll.rock_turns else doll.rock_axis
		_say("%d 回目（%s）: 体の向き %.1f°、もたれの軸 (%.2f, %.2f)、もたれ %.2f rad、向きについてくる %s" % [k, "三人称" if k >= 3 else "一人称",
			rad_to_deg(wrapf(doll.get("_yaw"), -PI, PI)), ax.x, ax.z, doll.rock, doll.rock_turns])
	var f := FileAccess.open("%s/log_%s.txt" % [_dir(), _tag()], FileAccess.WRITE)
	f.store_string("\n".join(lines))
	quit()
