extends SceneTree
## ロッジの 1 階の、ミシン（と売り子）からご飯の機械までのあいだを撮り、歩いて通れるか確かめる（確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/lodge_open_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 場所はロッジの座標（lodge/dims.py の x, y。Godot ではロッジの (x, 0, -y)）で持つ。
## 1. 一人称: ミシンの前・ご飯の機械の前・そのあいだ から、それぞれ相手の方を見る
## 2. 上から: 天井を消して、ミシンからご飯の機械までを真上から（正射影）
## 3. 歩く: ミシンの前からご飯の機械の前まで、本物の W キーで歩かせ、着いたか・どこで止まったかを出す（行きと帰り）

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D
var lines: Array[String] = []

const MACHINE := Vector2(-15.4, -3.4)  # ミシンの前（南西の隅。正面は東）
const KITCHEN := Vector2(2.0, 7.4)     # ご飯の機械（炉の右の厨房）の前
const BETWEEN := Vector2(-6.7, 2.0)    # そのあいだ


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/lodge_open")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:   # 窓から目が離れると設定が開くことがある
		main.settings.set_open(false)
		p.menu_open = false
	return false


## ロッジの座標 → 世界（床の高さ）
func _w(q: Vector2) -> Vector3:
	var g := lodge.to_global(Vector3(q.x, 0, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 2.5, g + Vector3.DOWN * 3.0)
	r.exclude = [p.get_rid()] if p else []
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else g


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _look_from(at: Vector2, to: Vector2, name: String) -> void:
	var a := _w(at)
	var b := _w(to)
	p.global_position = a + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(b.x - a.x), -(b.z - a.z))
	p.set("_pitch", -0.12)
	await create_timer(0.6).timeout
	await _shot(name)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


## from から to へ、向きを合わせながら W で歩く。着いたら true
func _walk(from: Vector2, to: Vector2, name: String) -> bool:
	p.global_position = _w(from) + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	var goal := _w(to)
	await _key(KEY_W, true)
	var t := 0.0
	var stuck := 0.0
	var last := p.global_position
	var ok := false
	while t < 20.0:
		var d := goal - p.global_position
		d.y = 0
		if d.length() < 0.6:
			ok = true
			break
		p.rotation.y = atan2(-d.x, -d.z)
		await physics_frame
		t += 1.0 / 30.0
		stuck = stuck + 1.0 / 30.0 if p.global_position.distance_to(last) < 0.004 else 0.0
		last = p.global_position
		if stuck > 1.5:
			break
	await _key(KEY_W, false)
	var lp := lodge.to_local(p.global_position)
	_say("%s: %s（%.1f 秒、止まった所 ロッジの座標 x=%.1f y=%.1f）" % [name, "着いた" if ok else "止まった", t, lp.x, -lp.z])
	return ok


func _run() -> void:
	await create_timer(2.5).timeout
	p = main.player
	p.set_third(false)
	lodge = main.get_node("Lodge")
	await _look_from(MACHINE + Vector2(1.2, -2.0), KITCHEN, "01_from_machine")
	await _look_from(KITCHEN + Vector2(-1.0, -2.0), MACHINE, "02_from_kitchen")
	await _look_from(BETWEEN + Vector2(0, -3.0), BETWEEN + Vector2(0, 3.0), "03_between")
	# 上から: 天井と 2 階を隠して、真上から
	var hidden := []
	for n in lodge.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name).to_lower()
		if nm.contains("roof") or nm.contains("ceiling") or nm.contains("2f") or nm.contains("floor2") or nm.contains("upper"):
			hidden.append(n)
	for n in hidden:
		n.visible = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 14.0
	root.add_child(cam)
	var c := _w((MACHINE + KITCHEN) / 2.0 + Vector2(0, 1.5))
	cam.global_position = c + Vector3.UP * 3.4
	cam.look_at(c, -lodge.global_basis.z)
	cam.near = 0.05
	cam.far = 10.0
	cam.current = true
	await create_timer(0.4).timeout
	await _shot("04_top")
	cam.current = false
	p.cam.make_current()
	for n in hidden:
		n.visible = true
	# 歩く
	await _walk(MACHINE + Vector2(1.0, -1.0), KITCHEN + Vector2(0, -1.0), "ミシンの前 → ご飯の機械の前")
	await _walk(KITCHEN + Vector2(0, -1.0), MACHINE + Vector2(1.0, -1.0), "ご飯の機械の前 → ミシンの前")
	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()
