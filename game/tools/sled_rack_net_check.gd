extends SceneTree
## 通信の確かめ: ほかの人や CPU が触っている自分のソリを、持ち主が立てかけ台へ呼び戻す（数字だけ出す。F と W は本物のキーの出来事で押す）。
## ホストを先に起動する。--owner= は持ち主の画面（host か join）。もう一方の画面の人が触る。CPU が触る回は、ホストの画面の仲間が触る。
## --lag=ミリ秒 で遅らせると、呼ばれる前に送られた姿が台のあとに届く（remote_person.gd の put が受け流す）。
##   Godot --headless --path game -s res://tools/sled_rack_net_check.gd -- --host --port=24771 --no-sound --no-buttons --roam-bots=1 --owner=host
##   Godot --headless --path game -s res://tools/sled_rack_net_check.gd -- --join=127.0.0.1 --port=24771 --no-sound --no-buttons --roam-bots=1 --owner=host
## 1 回の流れ: ホストがソリを山へ置く → 触る側が触る → 持ち主が台の前で F → 両方の画面で、ソリが台に立てかかり、触っていた人の状態が消えたのを見る → 持ち主が F で持ち出す

const RemotePerson := preload("res://remote_person.gd")
const CASES := ["grip", "push", "rope", "ride", "cpu_grip", "cpu_ride"]
const FAR_FROM_RACK := 8.0     # 触っていた人は台のそばへ飛ばない（山から呼ぶので、ここより遠い）

var args := {}
var main: Node3D
var p: CharacterBody3D
var craft: Node
var rack: Node3D
var s: RigidBody3D
var id := -1
var far := Vector3.ZERO
var fails := 0
var _t0 := 0
var _last := Vector3.ZERO      # 台へ呼ばれる前の、ソリの最後の所


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _physics_process(_dt: float) -> bool:
	if is_instance_valid(s) and not s.racked:
		_last = s.global_position
	return false


func _host() -> bool:
	return args.has("host")


func _owner() -> bool:
	return _host() == (String(args.get("owner", "join")) == "host")


func _say(t: String) -> void:
	print("[%s %.1f] %s" % ["host" if _host() else "join", (Time.get_ticks_msec() - _t0) / 1000.0, t])


func _ok(c: bool, what: String) -> void:
	_say(("○ " if c else "× ") + what)
	if not c:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		if t > limit:
			return false
		await physics_frame
		t += 1.0 / 60.0
	return true


## 本物のキーの出来事
func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _press_f() -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_F
	e.pressed = true
	p._unhandled_input(e)


## ホストの画面の仲間
func _bot() -> CharacterBody3D:
	var l := get_nodes_in_group("bots")
	return l[0] if not l.is_empty() else null


## この画面の、ほかの人の体（触っている人を見る）
func _other() -> Node3D:
	return main.net.remotes.values()[0] if not main.net.remotes.is_empty() else null


## この画面の、仲間の体（ホストは bot.gd、つなぐ側は remote_person.gd）
func _cpu_body() -> Node3D:
	if _host():
		return _bot()
	return main.net.cpus.values()[0] if not main.net.cpus.is_empty() else null


func _touching() -> bool:
	return not s.riders.is_empty() or not s.holders.is_empty() or s.rope_holder != null


func _run() -> void:
	await _wait(0.5)
	if not await _until(func(): return not main.net.remotes.is_empty(), 60.0):
		_say("相手が来なかった")
		quit(1)
		return
	_t0 = Time.get_ticks_msec()
	p = main.player
	craft = main.craft
	rack = main.sled_rack
	var lodge: Node3D = main.get_node("Lodge")
	far = lodge.to_global(Vector3(-18.0, 0, 40.0))
	far.y = main.height(far.x, far.z) + 0.3
	await _wait(1.0)
	if _host():
		var who: int = p.id if _owner() else main.net.remotes.keys()[0]
		craft.send({"kind": "sewn", "who": who, "sled": "mid", "fabric": "red", "at": far, "yaw": 0.0})
	await _until(func(): return not craft.sleds.is_empty(), 10.0)
	id = craft.sleds.keys()[0]
	s = craft.sleds[id]
	_say("ソリ %d 持ち主 %d（自分 %d）" % [id, s.owner_id, p.id])
	for c in CASES:
		await _round(c)
	_say("NG の数: %d" % fails)
	await _wait(1.0)
	quit(1 if fails > 0 else 0)


func _round(c: String) -> void:
	_say("---- %s" % c)
	if _host():
		await _until(func(): return not s.racked, 20.0)
		await _wait(0.3)
		s.reset_to(far)
	var by_cpu := c.begins_with("cpu_")
	var at_ease := await _until(func(): return not s.racked and s.global_position.distance_to(far) < 3.0, 20.0)
	if not at_ease:
		_ok(false, "ソリが山へ置かれなかった")
	var home: RigidBody3D = main.sled
	if by_cpu:
		if _host():
			await _cpu_touch(c)
	elif not _owner():
		await _touch(c)
	if _owner():
		await _recall(c)
	await _until(func(): return s.racked, 30.0)
	if not s.racked:
		_ok(false, "%s: 呼び戻されなかった" % c)
		return
	var who_body: Node3D = _cpu_body() if by_cpu else (p if not _owner() else _other())
	var bot := _bot()
	if by_cpu and _host():
		bot._help_t = bot.HELP_KEEP   # 人が手を離したあとと同じ残り時間に
	# 飛んだ所も見る: 呼ばれたあと 1 秒、触っていた人の体が台へ飛ばないか
	var near_rack := INF
	for i in 60:
		near_rack = minf(near_rack, who_body.global_position.distance_to(rack.global_position))
		await physics_frame
	_ok(s.racked and s.freeze and craft.racked.has(id), "%s: 台に立てかかり、止まっている" % c)
	_ok(not _touching(), "%s: ソリの手・席・紐が残っていない（乗る %d つかむ %d 紐 %s）" % [c, s.riders.size(), s.holders.size(), s.rope_holder != null])
	_ok(near_rack > FAR_FROM_RACK, "%s: 触っていた人の体は台へ飛ばない（台まで最短 %.1f m）" % [c, near_rack])
	var g: float = main.height(who_body.global_position.x, who_body.global_position.z)
	var dy: float = who_body.global_position.y - g
	_ok(absf(dy) < 1.0, "%s: 触っていた人は雪の上にいる（雪面から %.2f m）" % [c, dy])
	_ok(who_body.global_position.distance_to(_last) < 6.0, "%s: ソリがいた所のそば（%.1f m）" % [c, who_body.global_position.distance_to(_last)])
	if who_body == p:
		_ok(p.mode == p.Mode.WALK and p.handle == Vector3.INF and p.seat == Vector3.INF and not p._col.disabled, "%s: 自分は歩く状態に戻った" % c)
		var from := p.global_position
		_key(KEY_W, true)
		await _wait(0.6)
		_key(KEY_W, false)
		_ok(p.global_position.distance_to(from) > 0.5, "%s: そのまま歩ける（%.1f m）" % [c, p.global_position.distance_to(from)])
		_ok(p.is_on_floor(), "%s: 足が雪についている" % c)
	elif who_body is RemotePerson:
		_ok(who_body.mode == who_body.Mode.WALK and who_body.handle == Vector3.INF and who_body.seat == Vector3.INF, "%s: 相手の体は歩く姿に戻った" % c)
	if by_cpu and _host():
		await _cpu_after(c, bot, home)
	# 持ち主が持ち出す（次の回のため）
	if _owner():
		await _wait(2.5)
		p.global_rotation.y = atan2(-(s.global_position.x - p.global_position.x), -(s.global_position.z - p.global_position.z))
		await _wait(0.2)
		var rt: Array = p.rack_target()
		_ok(rt.size() == 2 and rt[1] == "rack_out", "%s: 持ち出す案内" % c)
		_press_f()
	await _until(func(): return not s.racked, 20.0)
	_ok(not s.racked, "%s: 持ち出せた" % c)


## 触る側の人が、本物の口で触る。ソリが呼ばれるまで放さない
func _touch(c: String) -> void:
	p.sled = s
	var gp: Array = s.grip_point_near(s.global_position + s.global_basis.z * 3.0)
	if c == "rope":
		p.global_position = s.to_global(s.ROPE_ANCHOR + Vector3(0, 0.3, -1.0))
	else:
		p.global_position = s.to_global(gp[0]) + Vector3.UP * 0.2
	await _wait(0.2)
	p.sled = s
	match c:
		"grip", "push":
			p.grab()
		"rope":
			p.grab_rope()
		"ride":
			p.get_on()
	var want: int = {"grip": p.Mode.GRIP, "push": p.Mode.GRIP, "rope": p.Mode.ROPE, "ride": p.Mode.RIDE}[c]
	_ok(p.mode == want, "%s: 触った（段 %d）" % [c, p.mode])
	if c == "push":
		p.global_rotation.y = s.global_rotation.y   # ソリの前へ押す
		_key(KEY_W, true)
		await _until(func(): return p.pushing, 3.0)
		_ok(p.pushing, "push: 押している")
		await _until(func(): return s.racked, 30.0)
		_key(KEY_W, false)


## CPU が触る: ホストの画面の仲間を、このソリの手伝いにする（山めぐりでは人のソリに触らないので、ここだけ手で向ける）
func _cpu_touch(c: String) -> void:
	var b := _bot()
	main.sled = s
	b.sled = s
	b._help_t = 1000.0
	b.far = false
	if c == "cpu_grip":
		b.state = b.State.PUSH
		b.global_position = s.to_global(Vector3((s.HALF.x + s.STAND) * 1.2, 0.2, 1.4))
		var got := await _until(func(): return b.handle != Vector3.INF, 15.0)
		_ok(got, "cpu_grip: 仲間がつかんだ")
	else:
		b.seat = s.mount(b)
		b._col.disabled = true
		b.state = b.State.RIDE
		b.global_position = s.to_global(b.seat)
		_ok(b.seat != Vector3.INF, "cpu_ride: 仲間が乗った")


## 呼ばれたあとの仲間（ホストの画面）: 状態が消えて、止まったままにならない
func _cpu_after(c: String, b: CharacterBody3D, home: RigidBody3D) -> void:
	_ok(b.handle == Vector3.INF and b.seat == Vector3.INF and b.state == b.State.PUSH and not b._col.disabled, "%s: 仲間の手と席が消え、歩く状態に" % c)
	await _until(func(): return b._help_t <= 0.0, 10.0)
	_ok(b._help_t <= 0.0, "%s: 手伝いをやめた" % c)
	var from := b.global_position
	var moved := await _until(func(): return b.global_position.distance_to(from) > 2.0, 25.0)
	_ok(moved, "%s: 仲間は山めぐりへ戻り、動いている（%.1f m）" % [c, b.global_position.distance_to(from)])
	main.sled = home if home != s else main.sled
	b.sled = main.sled


## 持ち主: 相手が触っているのが見えたら、台の前で F
func _recall(c: String) -> void:
	var seen := await _until(_touching, 40.0)
	_ok(seen, "%s: 相手が触っているのが見える（乗る %d つかむ %d 紐 %s）" % [c, s.riders.size(), s.holders.size(), s.rope_holder != null])
	await _wait(1.0)
	_ok(_touching(), "%s: まだ触っている" % c)
	p.global_position = rack.to_global(Vector3(-3.0, 0.1, 2.9))
	p.global_rotation.y = rack.global_rotation.y   # 台の方（-Z）を向く
	await _wait(0.3)
	var rt: Array = p.rack_target()
	_ok(rt.size() == 2 and rt[0] == s and rt[1] == "rack_in" and not p.rack_refused(), "%s: 戻す案内が出る（%.1f m/s で動くソリ）" % [c, s.linear_velocity.length()])
	_press_f()
