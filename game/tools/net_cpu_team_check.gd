extends SceneTree
## 通信の確かめ: 仲間どうしの雪合戦・協力してのソリ運び・ソリを買うのが、ホストとつなぐ側の両方の画面で同じに見えるか。ホストを先に、6 秒ほどあとにつなぐ側を起動する。
## 実時間で動かすので --fixed-fps は付けない。段取りはホストの道具が仲間に頼む（山めぐりで起きるのを待つと長いので）。
##   Godot --path game --resolution 960x540 --position 0,40 -s res://tools/net_cpu_team_check.gd -- --host --port=24761 --no-sound --hud-idle=0 --dir=/path/shots
##   Godot --path game --resolution 960x540 --position 980,40 -s res://tools/net_cpu_team_check.gd -- --join=127.0.0.1 --port=24761 --no-sound --hud-idle=0 --dir=/path/shots
## ○× は 1 行ずつ。「所」の行を壁の時計で比べて、両方の画面のずれを見る。絵は <tag>_*.png

const AT := Vector3(30, 0, 22)   # 雪合戦の所
const CAST := [2, 3, 4]          # 使う仲間の番号（ゆき・こはる・わた）

var args := {}
var main: Node3D
var p: CharacterBody3D
var hub: Node
var duel: Node
var craft: Node
var fails := 0
var _seen := {"star": 0, "paper": 0, "windup": 0, "throw": 0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	if args.has("dir"):
		DirAccess.make_dir_recursive_absolute(String(args.dir))
	_run.call_deferred()


func _host() -> bool:
	return args.has("host")


func _tag() -> String:
	return "host" if _host() else "join"


func _say(s: String) -> void:
	print("[%s %.3f] %s" % [_tag(), fmod(Time.get_unix_time_from_system(), 1000.0), s])


func _ok(cond: bool, what: String) -> void:
	_say(("○ " if cond else "× ") + what)
	if not cond:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _until(cond: Callable, limit: float) -> bool:
	var left := limit
	while not cond.call() and left > 0.0:
		await create_timer(0.05).timeout
		left -= 0.05
	return cond.call()


func _shot(nm: String) -> void:
	if not args.has("dir"):
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(String(args.dir).path_join("%s_%s.png" % [_tag(), nm]))
	_say("撮った: " + nm)


func _stand(at: Vector3) -> void:
	at.y = main.height(at.x, at.z) + 0.2
	p.global_position = at
	p.velocity = Vector3.ZERO


func _face(at: Vector3) -> void:
	var to := at - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	var up: Vector3 = at + Vector3.UP * 0.8 - p.cam.global_position
	p.set("_pitch", atan2(up.y, Vector2(up.x, up.z).length()))


func _cpu(id: int) -> Node3D:
	return hub.who_of(id)


## 両方の画面で、同じ形で所を出す（あとで時計で比べる）
func _where(s: RigidBody3D = null) -> void:
	var line := "所"
	for id in CAST:
		var b := _cpu(id)
		var m: int = b.net_mode() if _host() else b.mode
		line += " %d:(%.2f,%.2f,%.2f)段%d" % [id, b.global_position.x, b.global_position.y, b.global_position.z, m]
	if s and is_instance_valid(s):
		line += " ソリ:(%.2f,%.2f,%.2f)" % [s.global_position.x, s.global_position.y, s.global_position.z]
	_say(line)


func _run() -> void:
	p = main.player
	hub = main.emotes
	duel = main.duel
	craft = main.craft
	p.set_third(false)
	var joined: bool = await _until(func(): return not main.net.remotes.is_empty() and (_host() or main.net.cpus.size() >= 5), 30.0)
	_ok(joined, "つないだ（仲間が見える）")
	if not joined:
		quit(1)
		return
	hub.happened.connect(_note)
	await _wait(2.0)
	await _duel_part()
	await _team_part()
	await _buy_part()
	_say("おわり: ×の数 %d" % fails)
	await _wait(1.0)
	quit(fails)


func _note(ev: Dictionary) -> void:
	match String(ev.kind):
		"hit":
			if ev.get("star", false) and int(ev.who) in CAST:
				_seen.star += 1
				if _seen.star == 1:
					_say("仲間に当たった（星）")
					_shot("1_cpu_hit")
		"catch":
			if int(ev.who) in CAST:
				_seen.paper += 1
				if _seen.paper == 1:
					_say("仲間が取った（紙吹雪）")
					_shot("1_cpu_catch")
		"windup":
			_seen.windup += 1
		"throw":
			_seen.throw += 1


# ---------------------------------------------------------------- 雪合戦

func _duel_part() -> void:
	_stand(AT + (Vector3(9, 0, 0) if _host() else Vector3(-9, 0, 0)))
	_face(AT)
	if _host():
		var a = _cpu(2)
		var b = _cpu(3)
		await _until(func(): return a.state != a.State.RIDE and b.state != b.State.RIDE, 60.0)
		for c in [a, b]:
			c.global_position = AT + Vector3(0, main.height(AT.x, AT.z) + 0.3, 0) + (Vector3(-2, 0, 0) if c == a else Vector3(2, 0, 0))
			c.far = false
		a._ask_duel(3)
		b._ask_duel(2)
	var fought: bool = await _until(func(): return duel.of(2).get("phase", "") == "fight", 45.0)
	_ok(fought, "ゆきとこはるの対決が始まった（この画面にも届いた）")
	if not fought:
		return
	var d: Dictionary = duel.of(2)
	_say("掛金 %d 雪玉 %d %d 財布 %d %d 円 %d" % [int(d.stake), hub.balls_of(2), hub.balls_of(3), craft.wallet(2), craft.wallet(3), duel._rings.size()])
	_ok(int(duel.opponent(d, 2)) == 3 and int(d.stake) > 0, "相手はこはる、掛金 %d" % int(d.stake))
	_ok(duel._rings.size() == 1, "雪の上に円が出た")
	await _wait(2.5)
	await _shot("1_cpu_duel")
	var t := 0.0
	while duel.of(2).get("phase", "") == "fight" and t < 70.0:
		_where()
		await _wait(1.0)
		t += 1.0
	d = duel.of(2)
	_say("決まった: 段 %s 当てた %d・%d 勝ち %d 見たもの %s" % [d.get("phase", ""), int(d.get("hits_a", 0)), int(d.get("hits_b", 0)), int(d.get("winner", -1)), str(_seen)])
	_ok(_seen.windup >= 1 and _seen.throw >= 1, "振りかぶって投げた: %d %d" % [_seen.windup, _seen.throw])
	var paid: bool = await _until(func(): return duel.of(2).is_empty(), 45.0)
	_ok(paid, "握手で払って、対決が終わった")
	await _wait(0.5)
	_say("財布 %d %d" % [craft.wallet(2), craft.wallet(3)])


# ---------------------------------------------------------------- 協力してソリを運ぶ

func _team_part() -> void:
	var s: RigidBody3D = main.sled
	_stand(s.global_position + (Vector3(6, 0, -2) if _host() else Vector3(-6, 0, -2)))
	_face(s.global_position)
	if _host():
		var a = _cpu(2)
		var b = _cpu(3)
		await _until(func(): return a.state != a.State.RIDE and b.state != b.State.RIDE and a._five_with < 0 and b._five_with < 0 and not a._in_duel() and not b._in_duel(), 60.0)
		_stand(s.global_position + Vector3(6, 0, -2))
		for c in [a, b]:
			c.global_position = s.global_position + (Vector3(-3, 0.3, 3) if c == a else Vector3(3, 0.3, 3))
			c.far = false
		a.make_team(s, [b], "hill")
	var both: bool = await _until(func():
		_stand(s.global_position + (Vector3(6, 0, -2) if _host() else Vector3(-6, 0, -2)))
		_face(s.global_position)
		var h: Dictionary = s.holders
		return h.has(_cpu(2)) and h.has(_cpu(3)), 40.0)
	_ok(both, "2 人がソリをつかんだ（この画面でも）")
	await _wait(2.5)
	_stand(s.global_position + (Vector3(5, 0, -3) if _host() else Vector3(-5, 0, -3)))
	_face(s.global_position)
	await _shot("2_team_push")
	var rode: bool = await _until(func():
		_where(s)
		return s.riders.has(_cpu(2)) and s.riders.has(_cpu(3)), 90.0)
	_ok(rode, "頂上で 2 人が同じソリに乗った（この画面でも）")
	await _wait(1.0)
	_stand(s.global_position + (Vector3(5, 0, 0) if _host() else Vector3(-5, 0, 0)))
	_face(s.global_position)
	await _shot("3_team_ride")
	var t := 0.0
	while s.riders.has(_cpu(2)) and t < 60.0:
		_where(s)
		await _wait(0.5)
		t += 0.5
	_ok(not s.riders.has(_cpu(2)), "滑り終えて降りた")
	_where(s)


# ---------------------------------------------------------------- ソリを買う

func _buy_part() -> void:
	var n0: int = craft.sleds.size()
	var machine: Node3D = main.sewing.machine
	var mark: Vector3 = machine.to_global(main.sewing.get("_mark")["stand"])
	p.global_position = mark + (Vector3(3, 0.2, 0) if _host() else Vector3(-3, 0.2, 0))
	p.velocity = Vector3.ZERO
	_face(mark)
	if _host():
		var c = _cpu(4)
		await _until(func(): return c.state != c.State.RIDE and c._team.is_empty() and c._five_with < 0 and not c._in_duel(), 90.0)
		craft.wallets[4] = maxi(craft.wallet(4), 200)
		c._area = ""
		c._route = []
		c._roam_rest = 0.0
		c._team_cool = 999.0
		c.global_position = main.shopkeeper.to_global(Vector3(0, 0.3, -2.4))
		c.far = false
		_ok(c._try_errand(), "わたが買いに行く")
	var sewn: bool = await _until(func(): return craft.sleds.size() > n0, 70.0)
	_ok(sewn, "わたの縫ったソリが、この画面にも出た")
	if not sewn:
		return
	await _wait(1.0)
	var keys: Array = craft.sleds.keys()
	var s: RigidBody3D = craft.sleds[keys[-1]]
	_ok(int(s.owner_id) == 4 and s.kind == "small", "持ち主はわた: %d 大きさ %s 所 (%.2f, %.2f, %.2f) 名前 %s" % [int(s.owner_id), s.kind, s.global_position.x, s.global_position.y, s.global_position.z, s.name])
	if not _host():
		_ok(s.net_follow, "つなぐ側のソリは、ホストの姿を写す")
	_stand(s.global_position + (Vector3(4, 0, 3) if _host() else Vector3(5, 0, -3)))
	_face(s.global_position)
	await _wait(0.3)
	await _shot("4_sewn")
	_say("財布 わた %d" % craft.wallet(4))
