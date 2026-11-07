extends SceneTree
## 米袋をしまっても・ソリを呼び戻しても、滑りあとが残る確かめ（絵と数字）。
## 一人で:
##   Godot --path game --resolution 1280x720 -s res://tools/trail_stay_check.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## CPU 5 人が米袋で滑っているあいだの、残る跡の数を見る:
##   Godot --path game --resolution 960x540 -s res://tools/trail_stay_check.gd -- --roam-bots=5 --no-sound --no-pip --watch=90
## 2 つ起動（ホストを先に。ホストの米袋の跡が、しまったあとも両方の画面に残るかを見る）:
##   Godot --path game --resolution 960x540 -s res://tools/trail_stay_check.gd -- --host --port=24793 --bots=0 --no-sound --no-pip --dir=/path/host
##   Godot --path game --resolution 960x540 -s res://tools/trail_stay_check.gd -- --join=127.0.0.1 --port=24793 --bots=0 --no-sound --no-pip --dir=/path/join

const Sled := preload("res://sled.gd")
const Left := Sled.TrailLeft

var args := {}
var main: Node3D
var p: CharacterBody3D
var craft: Node
var cam: Camera3D
var fails := 0
var _saved := PackedByteArray()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_saved = FileAccess.get_file_as_bytes("user://my_tag.cfg")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _dir() -> String:
	return String(args.get("dir", "/tmp/trail_stay"))


func _ok(c: bool, what: String) -> void:
	print(("○ " if c else "× ") + what)
	if not c:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	_hide_hud(root)
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [_dir(), name])


func _hide_hud(n0: Node) -> void:
	for c in n0.get_children():
		if c is CanvasLayer:
			c.visible = false
		_hide_hud(c)


func _ground(x: float, z: float, lift := 0.0) -> Vector3:
	return Vector3(x, main.height(x, z) + lift, z)


func _view(eye: Vector3, at: Vector3) -> void:
	cam.global_position = eye
	cam.look_at(at, Vector3.UP)
	cam.current = true


## 目が残っている数（離れた跡の全部）
func _left() -> Vector2i:
	return Left.totals()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	await _wait(1.5)
	p = main.player
	craft = main.craft
	cam = Camera3D.new()
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	if args.has("watch"):
		await _watch(float(args.watch))
	elif args.has("host") or args.has("join"):
		await _net_flow()
	else:
		await _solo()
	print("確かめ: %s（× %d）" % ["よし" if fails == 0 else "だめ", fails])
	if not _saved.is_empty():
		var f := FileAccess.open("user://my_tag.cfg", FileAccess.WRITE)
		f.store_buffer(_saved)
		f.close()
	quit(0 if fails == 0 else 1)


## ソリに今ある目の数
func _count(s: RigidBody3D) -> int:
	var n := 0
	for mi in s._trails:
		n += mi.multimesh.visible_instance_count
	return n


func _key_w(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)


## 米袋を出して +x（下り）へ向け、人が乗って W で t 秒滑る
func _ride_sack(at: Vector3, t: float) -> RigidBody3D:
	var me: int = p.id
	craft.send({"kind": "sack_out", "who": me, "at": at, "yaw": -PI / 2, "up": Vector3.UP, "v": Vector3.ZERO})
	await _wait(0.2)
	var s: RigidBody3D = craft.sack_sled(me)
	s.parked = false
	p.global_position = s.global_position + Vector3.UP * 0.5
	p.last_sled = s
	p.sled = s
	p.get_on()
	_key_w(true)
	var left := t
	while left > 0.0:
		craft._sack_far[me] = 0.0
		_view(s.global_position + Vector3(-6.0, 3.2, 0.0), s.global_position + Vector3(-2.0, 0, 0))
		await physics_frame
		left -= 1.0 / 60.0
	_key_w(false)
	return s


func _solo() -> void:
	var me: int = p.id
	var a0 := _ground(6.0, 0.0, 0.6)
	var s := await _ride_sack(a0, 6.0)
	var made: int = _count(s)
	_ok(made > 20, "米袋で滑って跡が出た（%d 目）" % made)
	var stitch_was: String = s.stitch_kind()
	var end_pos := s.global_position
	await _shot("1_before_fold")
	_ok(craft.send({"kind": "sack_in", "who": me}), "米袋をしまった")
	await _wait(0.1)
	_ok(_left().x >= made, "しまっても目がそのまま残る（%d 目）" % _left().x)
	_view(end_pos + Vector3(-6.0, 3.2, 0.0), end_pos + Vector3(-2.0, 0, 0))
	await _shot("2_after_fold")
	# 同じ米袋を、前の跡の横へ出して滑り直す。前の跡は残り、線はつながらない
	var a1 := _ground(6.0, 6.0, 0.6)
	var s2 := await _ride_sack(a1, 6.0)
	_ok(_left().x >= made - 2, "滑り直しても、前の跡は消えない（%d 目）" % _left().x)
	_ok(_count(s2) > 20, "滑り直して跡が出た（%d 目）" % _count(s2))
	var first: Vector3 = s2._trails[0].multimesh.get_instance_transform(0).origin
	_ok(first.distance_to(end_pos) > 3.0, "新しい跡は前の跡の終わりとつながらない（%.1f m 離れている）" % first.distance_to(end_pos))
	_ok(s2.stitch_kind() == stitch_was, "柄は同じ")
	var mid := (end_pos + s2.global_position) * 0.5
	_view(mid + Vector3(-16.0, 15.0, 7.0), mid + Vector3(-7.0, 0, 0))
	await _shot("3_ride_again")
	# 柄を替えて滑り直しても、前の跡は滑ったときの柄のまま
	craft.send({"kind": "stitch_own", "who": me, "stitch": "cross"})
	craft.send({"kind": "sled_stitch", "who": me, "sack": 0, "stitch": "cross"})
	_ok(s2.stitch_kind() == "cross", "米袋の柄を替えた")
	var end2 := s2.global_position
	craft.send({"kind": "sack_in", "who": me})
	await _wait(0.1)
	var s3 := await _ride_sack(_ground(6.0, -6.0, 0.6), 6.0)
	mid = (end2 + s3.global_position) * 0.5
	_view(mid + Vector3(-16.0, 15.0, 7.0), mid + Vector3(-7.0, 0, 0))
	await _shot("4_two_stitches")
	_ok(_left().x >= made - 2, "柄を替えても前の跡は残る（%d 目）" % _left().x)
	craft.send({"kind": "sack_in", "who": me})
	await _wait(0.1)
	# 消える: ふつうの跡と同じ時刻で消えきり、片づく
	var n0: int = Left.all.size()
	_ok(n0 > 0, "離れた跡がある（%d 本）" % n0)
	for l in Left.all.duplicate():
		l.now += 1000.0
	await _wait(0.3)
	_ok(Left.all.is_empty() and _left() == Vector2i.ZERO, "消える時刻を過ぎたら、全部片づいた")
	# 立てかけ台へ呼び戻す: 隠しているあいだも跡は見えている
	var design: Dictionary = craft.tag_designs.get(me, {})
	var id: int = craft._place("small", "navy", _ground(30.0, 0.0, 0.5), -PI / 2, 0, Vector3.UP, design, false, me)
	var own: RigidBody3D = craft.sleds[id]
	await _wait(0.2)
	own.parked = false
	var t := 3.0
	while t > 0.0:
		own.linear_velocity = Vector3(3.0, own.linear_velocity.y, 0.0)
		await physics_frame
		t -= 1.0 / 60.0
	var used: int = _count(own)
	_ok(used > 10, "ソリで跡が出た（%d 目）" % used)
	own.rack_in(own.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)), 1.0)
	await process_frame
	_ok(not own.visible and _left().x == used, "呼び戻してソリを隠しているあいだも、跡は残る")
	_ok(Left.all[0].chunks[0][0].is_visible_in_tree(), "跡は描かれている")
	# 上限: 何度しまっても、残る目と塊は上限を超えない
	for l in Left.all.duplicate():
		l.now += 1000.0
	await _wait(0.2)
	var kept := Vector2i.ZERO
	for k in 14:
		var d: RigidBody3D = Sled.new()
		d.kind = "sack"
		d.snow_plane = main.snow_plane
		d.snow_lift = main.snow_lift
		d.position = _ground(10.0 + k * 3, -20.0, 500.0)
		d.freeze = true
		main.add_child(d)
		d.set_physics_process(false)
		for r in 2:
			var x: float = 10.0 + k * 3 + (-d.RUNNER_X if r == 0 else d.RUNNER_X)
			for i in 800:
				d._trail_step(r, _ground(x, -20.0 + i * 0.3), Vector3(0, 0, 1))
		d.leave_trail()
		d.queue_free()
		kept = _left()
		await process_frame
	_ok(kept.x <= Left.LEFT_STITCHES and kept.y <= Left.LEFT_CHUNKS, "上限を超えない（目 %d / %d、塊 %d / %d）" % [kept.x, Left.LEFT_STITCHES, kept.y, Left.LEFT_CHUNKS])
	_ok(kept.y == Left.LEFT_CHUNKS, "上限までは残す（塊 %d）" % kept.y)


## CPU が米袋で滑っているあいだ、残る跡の数を 10 秒ごとに出す
func _watch(sec: float) -> void:
	var t := 0.0
	var top := Vector2i.ZERO
	var next := 0.0
	while t < sec:
		var n := _left()
		top = Vector2i(maxi(top.x, n.x), maxi(top.y, n.y))
		if t >= next:
			next += 10.0
			print("%3.0f 秒: 離れた跡 %d 本、目 %d、塊 %d、fps %d、三角 %d" % [t, Left.all.size(), n.x, n.y, Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		await physics_frame
		t += 1.0 / 60.0
	print("いちばん多いとき: 目 %d、塊 %d" % [top.x, top.y])
	_ok(top.x <= Left.LEFT_STITCHES and top.y <= Left.LEFT_CHUNKS, "上限の中")


## ホストが米袋で滑ってしまう。両方の画面で、しまったあとも跡が残るかを見る
func _net_flow() -> void:
	var host: bool = args.has("host")
	if host:
		while main.net.remotes.is_empty():
			await physics_frame
		print("つなぐ側が入った")
		await _wait(2.0)
		var s := await _ride_sack(_ground(6.0, 0.0, 0.6), 6.0)
		var end_pos := s.global_position
		print("目の数=", _count(s))
		_ok(craft.send({"kind": "sack_in", "who": p.id}), "しまった")
		await _wait(0.5)
		_ok(_left().x > 20, "ホストの画面に残っている（目 %d）" % _left().x)
		_view(end_pos + Vector3(-6.0, 3.2, 0.0), end_pos + Vector3(-2.0, 0, 0))
		await _wait(0.5)
		await _shot("net_host")
		await _wait(3.0)
	else:
		# ホストの米袋が出て、消えるのを待つ
		var who := -1
		var s: RigidBody3D = null
		var limit := 60.0
		while s == null and limit > 0.0:
			for w in craft.sack_out:
				s = craft.sack_sled(w)
				who = w
			await physics_frame
			limit -= 1.0 / 60.0
		_ok(s != null, "ホストの米袋が届いた")
		var used := 0
		var end_pos := Vector3.ZERO
		while craft.sack_sled(who) != null and limit > 0.0:
			used = _count(s)
			end_pos = s.global_position
			_view(end_pos + Vector3(-6.0, 3.2, 0.0), end_pos + Vector3(-2.0, 0, 0))
			await physics_frame
			limit -= 1.0 / 60.0
		_ok(used > 20, "この画面でも跡が出た（目 %d）" % used)
		await _wait(0.3)
		_ok(_left().x >= used - 8 and _left().x > 0, "しまったあとも、この画面に残っている（目 %d）" % _left().x)
		_view(end_pos + Vector3(-6.0, 3.2, 0.0), end_pos + Vector3(-2.0, 0, 0))
		await _wait(0.5)
		await _shot("net_join")
