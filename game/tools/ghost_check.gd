extends SceneTree
## 観戦モード（ghost.gd）の確かめ（数字だけ）:
##   Godot --headless --path game -s res://tools/ghost_check.gd -- --no-sound --no-pip
## 抜け（ghost.gd の enter。設定の画面の「霊体になる」と同じ）、Ctrl で雪の下へ、W でロッジの壁を抜けて中へ、戻る（leave）。戻ったら、抜けた所・向き・当たり・名簿が元どおりか。
## 抜けているあいだ、名簿（emotes.people）・仲間（bot.gd の _humans）・連れから外れているか。
## 抜けたかどうかは、通った線を光線で調べ、間に当たる物（雪面・壁）があったかで見る

var main: Node3D
var g: Node
var fails := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _args() -> Dictionary:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return a


func _check(ok: bool, s: String) -> void:
	print(("○ " if ok else "× ") + s)
	if not ok:
		fails += 1


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _tap(k: Key) -> void:
	_key(k, true)
	await process_frame
	_key(k, false)
	await process_frame


## 飛ぶ: キーを secs 秒押す。通った線に当たる物があれば、その物の名前
func _fly(k: Key, secs: float) -> Array:
	var from: Vector3 = g.cam.global_position
	_key(k, true)
	await create_timer(secs).timeout
	_key(k, false)
	await create_timer(0.4).timeout   # 止まるまで
	var to: Vector3 = g.cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
	return [from, to, hit]


func _run() -> void:
	await create_timer(1.5).timeout
	var p: CharacterBody3D = main.player
	g = main.ghost
	_check(g != null, "観戦モードの役が置かれている")
	if g == null:
		quit(1)
		return
	# ロッジの正面の外、壁から 6 m の所に立って、ロッジのまんなかを向く
	var lc := Vector3(main.LODGE_POS.x, 0, main.LODGE_POS.y)
	var face := Vector3(sin(main.LODGE_YAW), 0, cos(main.LODGE_YAW))
	var stand := lc - face * 0.0 + Vector3(0, 0, 0)
	# 壁をさがす: まんなかから外へ光線を出し、外から当たる所
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var out := lc + face * 30.0
	out.y = main.height(out.x, out.z) + 2.0
	var mid := lc
	mid.y = out.y
	var hit_wall: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(out, mid))
	_check(not hit_wall.is_empty(), "ロッジの外から壁に当たる所がある（%s）" % [hit_wall.get("collider")])
	stand = (hit_wall.get("position", out) as Vector3) + face * 6.0
	stand.y = main.height(stand.x, stand.z) + 0.2
	p.global_position = stand
	p.rotation.y = atan2(face.x, face.z)   # -Z が前: ロッジを向く
	p._pitch = 0.0
	await create_timer(1.0).timeout
	var at0 := p.global_position
	var yaw0 := p.rotation.y
	var id: int = p.id
	var bots := root.get_tree().get_nodes_in_group("bots")
	_check(main.emotes.people.get(id) == p, "抜ける前: 名簿にいる")

	g.enter()
	await process_frame
	_check(g.active and int(p.ghost) == 1, "抜けた（見えない霊体）")
	_check(not main.emotes.people.has(id), "名簿から外れた（施設・まち針・湿り気・雪玉が見ない）")
	_check(p.process_mode == Node.PROCESS_MODE_DISABLED and p._col.disabled and p.collision_layer == 0, "体は止まって、当たりがない")
	_check(not p.doll.visible, "体の人形は見えない")
	_check(get_root().get_viewport().get_camera_3d() == g.cam, "霊体のカメラに替わった")
	if not bots.is_empty():
		_check(bots[0]._humans().is_empty(), "仲間から見て、遊んでいる人がいない（%d 人の仲間）" % bots.size())

	# 1) 雪の下へ
	var r := await _fly(KEY_CTRL, 1.5)
	var end: Vector3 = r[1]
	var below: float = float(main.height(end.x, end.z)) - end.y
	_check(below > 2.0, "Ctrl で雪面の下へ抜けた（雪面より %.1f m 下、通った線に %s）" % [below, r[2].get("collider")])
	# 2) 上へ戻って、ロッジの壁を抜けて中へ
	r = await _fly(KEY_SPACE, 1.5)
	_check(r[1].y > r[0].y + 6.0, "Space で上がった（%.1f m）" % [r[1].y - r[0].y])
	g.cam.global_position = Vector3(stand.x, (hit_wall.position as Vector3).y, stand.z)
	g._pitch = 0.0
	g._yaw = atan2(face.x, face.z)
	await create_timer(0.2).timeout
	r = await _fly(KEY_W, 2.0)
	var into: bool = (r[1] as Vector3).distance_to(lc) < (hit_wall.position as Vector3).distance_to(lc) - 1.0
	_check(into and not r[2].is_empty(), "W でロッジの壁を抜けて中へ入った（壁の内へ %.1f m、通った線に %s）" % [
		(hit_wall.position as Vector3).distance_to(lc) - (r[1] as Vector3).distance_to(lc), r[2].get("collider")])
	# 3) 速さ
	var s0: float = g.speed
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await process_frame
	_check(g.speed > s0, "ホイールで速くなる（%.1f → %.1f m/s）" % [s0, g.speed])
	# 4) 見える ⇄ 見えない
	g.set_seen(true)
	_check(int(p.ghost) == 2 and g.net_state().has("p"), "見える霊体（位置を送る）")
	g.set_seen(false)
	_check(int(p.ghost) == 1 and not g.net_state().has("p"), "見えない霊体（位置を送らない）")
	_check(p.global_position.distance_to(at0) < 0.001, "抜けているあいだ、体は抜けた所から動かない")

	# 5) 戻る
	g.leave()
	await create_timer(0.5).timeout
	_check(not g.active and int(p.ghost) == 0, "体へ戻った")
	_check(p.global_position.distance_to(at0) < 0.05, "抜けた所に戻った（ずれ %.3f m）" % p.global_position.distance_to(at0))
	_check(absf(angle_difference(p.rotation.y, yaw0)) < 0.01, "抜けたときの向き")
	_check(main.emotes.people.get(id) == p, "名簿に戻った")
	_check(p.process_mode != Node.PROCESS_MODE_DISABLED and not p._col.disabled and p.collision_layer != 0 and p.doll.visible, "体が動き、当たりと人形が戻った")
	_check(get_root().get_viewport().get_camera_3d() == p.cam, "体のカメラに戻った")
	_check(p.mode == p.Mode.WALK and p.is_on_floor(), "歩いていて、雪の上に立っている")
	print("食い違い %d" % fails)
	quit(1 if fails > 0 else 0)
