extends SceneTree
## 通信の確かめ: 滑っているソリの底が、どちらの画面で雪にめり込んで見えるか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_sink_net_check.gd -- --host --port=24771 --sled=small --no-sound --no-lodge --bots=0 --roam-bots=0 --lodge-bots=0
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_sink_net_check.gd -- --join=127.0.0.1 --port=24771 --sled=small --no-sound --no-lodge --bots=0 --roam-bots=0 --lodge-bots=0
## ホストがソリに形の人を席いっぱい乗せ、丘の頂上から +z へ 4 m/s で押し出す。どちらの画面でも、ソリが動きだしてから 12 秒、
## コマごとに見た目（glb）の頂点のいちばん深い所（見た目の雪面 main.height ＋ main.snow_lift より下）を測る。--lag=秒 でつなぐ側の届く遅れをまねる（ない時は 0）

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sled: RigidBody3D
var _verts := PackedVector3Array()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s] %s" % ["ホスト" if args.has("host") else "つなぐ側", s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _body_verts() -> PackedVector3Array:
	if _verts.is_empty():
		var inv := (sled._body as Node3D).global_transform.affine_inverse()   # 形の座標で覚える（見た目の上下 vis_lift は、測るときの形の位置で入る）
		for mi in sled._body.find_children("*", "MeshInstance3D", true, false) + ([sled._body] if sled._body is MeshInstance3D else []):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree():
				continue
			var xf := inv * m.global_transform
			for si in m.mesh.get_surface_count():
				for v in (m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					_verts.append(xf * v)
	return _verts


func _deep_now() -> float:
	var xf := (sled._body as Node3D).global_transform
	var deep := 0.0
	for v in _body_verts():
		var w := xf * v
		deep = maxf(deep, main.height(w.x, w.z) + main.snow_lift(w.x, w.z) - w.y)
	return deep


func _run() -> void:
	await _wait(1.0)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	_say("相手が見えた" if not main.net.remotes.is_empty() else "相手が来なかった")
	await _wait(2.0)
	sled = main.sled
	if args.has("host"):
		sled.reset_to(Vector3(0, main.height(0, 3.0) + 0.3, 3.0))
		sled.rotation.y = PI
		sled.parked = true
		await _wait(1.5)
		_body_verts()
		var dummy := GDScript.new()
		dummy.source_code = DUMMY_SRC
		dummy.reload()
		for i in sled.SEATS.size():
			var d := Node3D.new()
			d.set_script(dummy)
			d.sled = sled
			main.add_child(d)
			sled.mount(d)
		sled.parked = false
		sled.linear_velocity = Vector3(0, 0, 4.0)
	else:
		# 頂上に置かれて止まり、動きだすまで待つ
		await _wait(1.0)
		var q := func(): return Vector2(sled.global_position.x, sled.global_position.z - 3.0).length() < 1.5 and sled.linear_velocity.length() > 1.0
		t = 0.0
		while not q.call() and t < 30.0:
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
		_body_verts()
	t = 0.0
	var top := 0.0
	var sum := 0.0
	var frames := 0
	var over2 := 0
	var over5 := 0
	while t < 12.0:
		await process_frame   # 見た目のコマ（つなぐ側は _process で姿を寄せる）
		t += 1.0 / 60.0
		var d := _deep_now()
		top = maxf(top, d)
		sum += d
		frames += 1
		if d > 0.02:
			over2 += 1
		if d > 0.05:
			over5 += 1
	_say("%s 乗る人 %d: いちばん深い %.1f cm、コマの平均 %.1f cm、2 cm より深いコマ %d%%、5 cm より深いコマ %d%%" % [sled.kind, sled.riders.size(),
			top * 100.0, sum / frames * 100.0, over2 * 100 / frames, over5 * 100 / frames])
	await _wait(2.0)
	quit()
