extends SceneTree
## 通信の確かめ: ソリに轢かれて吹き飛ぶ姿が、ホストとつなぐ側で同じように見えるか（数字だけ出す）。
##   Godot --headless --path game -s res://tools/run_over_net_check.gd -- --host --port=24755 --bots=1 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-lodge
##   Godot --headless --path game -s res://tools/run_over_net_check.gd -- --join=127.0.0.1 --port=24755 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-lodge
## 2 つの画面の時間を合わせるので、--fixed-fps は付けない（付けると実時間より速く進む）。--lag=ミリ秒 を両方に付けると、遅れがあるとき
##   A  ホストのソリ（ホストが動かす）が、つなぐ人に当たる。つなぐ人の画面で飛び、ホストの画面のその人の人形も同じ段を通るか。ホストのソリが反動で遅くなるか
##   B  ホストの人に当たる。つなぐ側の画面のその人の人形が同じ段を通るか
##   C  ホストの仲間に当たる。つなぐ側の画面の仲間の人形が同じ段を通るか

const LAB_Y := 300.0
const PERIOD := 12.0   # 1 つの場面の長さ (s)

var args := {}
var main: Node3D
var sled: RigidBody3D
var p: CharacterBody3D
var host := false
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	host = args.has("host")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s] %s" % ["host" if host else "join", s])


func _check(ok: bool, s: String) -> void:
	_say(("○ " if ok else "× ") + s)
	if not ok:
		fails += 1


func _make_lab() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0, LAB_Y - 1.0, 0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 2, 600)
	col.shape = box
	body.add_child(col)
	main.add_child(body)


func _run() -> void:
	await create_timer(0.5).timeout
	sled = main.sled
	p = main.player
	_make_lab()
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await create_timer(0.25).timeout
		t += 0.25
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	# 場面は、時計（同じ Mac で動かす）の PERIOD 秒ごとに始める。両方の画面で同じ場面が同じ時刻に始まる。
	# 両方がつながってから余裕を見て、次の区切りの場面 A から順に
	await create_timer(PERIOD).timeout
	var now := Time.get_unix_time_from_system()
	var cycle := int(now / (PERIOD * 3.0)) + 1
	await create_timer(cycle * PERIOD * 3.0 - now).timeout
	for i in 3:
		await _scene(["A", "B", "C"][i])
		var left := cycle * PERIOD * 3.0 + (i + 1) * PERIOD - Time.get_unix_time_from_system()
		await create_timer(maxf(left, 0.1)).timeout
	_say("だめだった数: %d" % fails)
	await create_timer(3.0).timeout
	quit(1 if fails > 0 else 0)


## 見張る人の、飛ぶ段の移り変わりを数える
func _watch(who: Node3D, secs: float, speed_keep := 0.0) -> Dictionary:
	var seen: Array[int] = []
	var apex := -99.0
	var low := 99.0
	var far := 0.0
	var from := who.global_position
	var t := 0.0
	var v_before := 0.0
	var v_after := -1.0
	var t_hit := -1.0
	while t < secs:
		await physics_frame
		t += 1.0 / 60.0
		var st: int = int(who.doll.flung)
		if seen.is_empty() or seen[-1] != st:
			seen.append(st)
		if st == 0 and seen.size() == 1 and speed_keep > 0.0 and host:
			sled.linear_velocity = Vector3(0, sled.linear_velocity.y, speed_keep)
			if who.is_in_group("bots"):
				who.global_position = Vector3(0, LAB_Y + 0.05, 2.0)   # 当たるまで仲間を立たせておく（ソリの持ち場へ歩き出す）
		if st == 0 and seen.size() == 1:
			v_before = sled.linear_velocity.length()
		elif t_hit < 0.0:
			t_hit = t
		if t_hit >= 0.0 and t < t_hit + 0.3:
			v_after = sled.linear_velocity.length() if v_after < 0.0 else minf(v_after, sled.linear_velocity.length())   # 出来事は姿と別の流れで届く
		apex = maxf(apex, who.global_position.y - LAB_Y)
		low = minf(low, who.global_position.y - LAB_Y)
		far = maxf(far, Vector2(who.global_position.x - from.x, who.global_position.z - from.z).length())
	return {"seen": seen, "apex": apex, "low": low, "far": far, "v_before": v_before, "v_after": v_after, "end": who.global_position}


func _scene(scene: String) -> void:
	var target: Node3D
	var peer_id: int = main.net.remotes.keys()[0]
	match scene:
		"A":
			target = p if not host else main.net.remotes[peer_id]
		"B":
			target = p if host else main.net.remotes[peer_id]
		"C":
			if host:
				target = get_nodes_in_group_any("bots")[0] if not get_nodes_in_group_any("bots").is_empty() else null
			else:
				var tt := 0.0
				while main.net.cpus.is_empty() and tt < 4.0:
					await create_timer(0.25).timeout
					tt += 0.25
				target = main.net.cpus.values()[0] if not main.net.cpus.is_empty() else null
	if target == null:
		_check(false, "場面 %s: 相手の体がない" % scene)
		return
	var mine: bool = (scene == "A" and not host) or (scene == "B" and host) or (scene == "C" and host)
	if host:
		sled.reset_to(Vector3(0, LAB_Y + 0.05, -14))
		sled.parked = false
		sled.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), Vector3(0, LAB_Y + 0.05, -14))
		sled.linear_velocity = Vector3.ZERO
	if mine and target is CharacterBody3D:
		(target as CharacterBody3D).global_position = Vector3(0, LAB_Y + 0.05, 2.0)
		(target as CharacterBody3D).velocity = Vector3.ZERO
	if scene != "A" or not host:
		p.global_position = p.global_position if target == p else Vector3(20, LAB_Y + 0.05, 0)
	await create_timer(1.0).timeout
	if mine and target is CharacterBody3D:
		(target as CharacterBody3D).global_position = Vector3(0, LAB_Y + 0.05, 2.0)
		if target.get("_regrab") != null:
			target.set("_regrab", 99.0)   # 仲間がソリをつかみに行かないように
	if host:
		sled.linear_velocity = Vector3(0, 0, 9.0)
	var r: Dictionary = await _watch(target, 6.5, 9.0)
	_say("場面 %s: 段 %s 高さ %.2f 距離 %.1f 低い所 %.2f おわり %s ソリ %.1f → %.1f m/s" % [scene, str(r.seen), r.apex, r.far, r.low, str(r.end.snapped(Vector3.ONE * 0.1)), r.v_before, r.v_after])
	_check(r.seen == [0, 1, 2, 3, 0], "場面 %s: 飛ぶ → 倒れる → 起き上がる → ふだん の順に見える" % scene)
	_check(r.low > -0.3, "場面 %s: 雪面の下へ抜けて見えない" % scene)
	if host:
		_check(r.v_after >= 0.0 and r.v_after < r.v_before - 0.3, "場面 %s: ホストのソリが反動で遅くなる" % scene)


func get_nodes_in_group_any(g: String) -> Array:
	return root.get_tree().get_nodes_in_group(g)
