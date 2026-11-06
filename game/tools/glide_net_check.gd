extends SceneTree
## 通信の確かめ: 紐で引く力と滑走が、ホストの画面とつなぐ側の画面で同じか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/glide_net_check.gd -- --host --port=24731 --sled=mid --no-sound --no-lodge --roam-bots=0 --lodge-bots=0
##   Godot --headless --fixed-fps 60 --path game -s res://tools/glide_net_check.gd -- --join=127.0.0.1 --port=24731 --sled=mid --no-sound --no-lodge --roam-bots=0 --lodge-bots=0
## 1. つなぐ側の人が紐を持ち、W で 12 秒歩く。ソリが動いた距離を両方の画面で出す（ひとりのときと同じ力なら、ホストのソリが同じだけ動く）
## 2. ホストがソリに一人乗せて（形の人）、平らな所で 8 m/s で放す。止まるまでの時間と止まった所を両方の画面で出す

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _tag() -> String:
	return "ホスト" if args.has("host") else "つなぐ側"


func _say(s: String) -> void:
	print("[%s] %s" % [_tag(), s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _key(k: Key, on: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)


func _run() -> void:
	await _wait(1.0)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	_say("相手が見えた" if not main.net.remotes.is_empty() else "相手が来なかった")
	await _wait(2.0)
	var sled: RigidBody3D = main.sled
	var p: Node3D = main.player
	var from: Vector3 = sled.global_position
	# 1. 紐
	if args.has("join"):
		var a: Vector3 = sled.rope_root()
		var fwd: Vector3 = -sled.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var at: Vector3 = a + fwd * sled.ROPE_LEN
		p.global_position = Vector3(at.x, main.height(at.x, at.z) + 0.1, at.z)
		p.rotation.y = atan2(-fwd.x, -fwd.z)
		p.velocity = Vector3.ZERO
		p.grab_rope()
		_key(KEY_W, true)
	await _wait(12.0)
	if args.has("join"):
		_key(KEY_W, false)
		p.let_go()
	var moved: float = sled.global_position.distance_to(from)
	_say("紐: 12 秒でソリが動いた距離 %.2f m、所 (%.2f, %.2f)" % [moved, sled.global_position.x, sled.global_position.z])
	await _wait(3.0)
	# 2. 滑走
	var rider: Node3D = null
	if args.has("host"):
		sled.reset_to(Vector3(90, main.height(90, 0) + 0.3, 0))
		sled.rotation.y = 0.0
		sled.parked = false
		var dummy := GDScript.new()
		dummy.source_code = DUMMY_SRC
		dummy.reload()
		rider = Node3D.new()
		rider.set_script(dummy)
		rider.sled = sled
		main.add_child(rider)
		sled.mount(rider)
		await _wait(1.0)
		sled.linear_velocity = Vector3(0, 0, -8)
	# どちらの画面でも、3 m/s より速くなったのを見て時計を始める
	t = 0.0
	while sled.linear_velocity.length() < 3.0 and t < 20.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	var t0 := 0.0
	var p0: Vector3 = sled.global_position
	var still := 0.0
	var top := 0.0
	while t0 < 60.0:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t0 += dt
		top = maxf(top, sled.linear_velocity.length())
		still = still + dt if sled.linear_velocity.length() < 0.1 else 0.0
		if still > 1.0:
			break
	var q: Vector3 = sled.global_position
	_say("滑走: 速さの上限 %.1f m/s、止まるまで %.1f s、距離 %.1f m、止まった所 (%.2f, %.2f)" % [top, t0 - still, q.distance_to(p0), q.x, q.z])
	await _wait(1.0)
	quit()
