extends SceneTree
## お金を払う施設の「近づくと動く」を撮る（確かめ用）。
##   Godot --path game --resolution 960x540 --fixed-fps 30 -s res://tools/stall_motion_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots --what=book
## --what: book（見本帳）・vat（染台）・stand（双眼鏡台）・man（山男）・lady（紙細工屋さん）・curtain（番台）・fridge（雪だるま）・machine（ミシン）
## あなたを施設の正面の FAR m に立たせ、NEAR m まで歩かせて、しばらく立ち、また FAR m まで戻す。カメラは --cam の所で動かさず、
## 12 コマ／秒のコマごとに撮る（<what>_000.png …）。--still=秒 なら、立ったまま 1 枚撮るだけ（近くに立ったあとの絵）。
##   --far=7 --near=2.6 --walk-s=1.5 --stay-s=3 --back=1   歩く距離と時間（--back=0 で戻らない）
##   --side=1.2 --cam-back=4.5 --cam-h=1.6 --look-h=1.2    カメラの置き場（施設の座標。--side は横へ、--cam-back は正面へ）
##   --person=1  歩くあなたの人形も写す（既定は写さない）

var args := {}
var main: Node3D
var target: Node3D
var front := Vector3.BACK    # 施設の正面（世界の向き）
var right := Vector3.RIGHT
var ground := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/stall_motion")


func _num(key: String, def: float) -> float:
	return float(args.get(key, def))


func _find() -> bool:
	match args.get("what", "book"):
		"book":
			target = main.sled_book
		"vat":
			target = main.wardrobe
		"stand":
			target = main.binocular_stands[int(_num("index", 0))]
			front = target.global_basis.z
		"man":
			target = main.mountain_man
		"lady":
			target = main.paper_lady
		"curtain":
			target = main.find_child("Bandai_counter_patch", true, false)
			front = -target.global_basis.z
		"fridge":
			target = main.find_child("Bandai_counter_indigo", true, false)
			front = -target.global_basis.z
		"machine":
			target = main.sewing.machine
	if target == null:
		return false
	if args.get("what", "book") in ["book", "vat", "lady"]:
		front = target.global_basis.z
	elif args.get("what", "book") == "man":
		front = -target.global_basis.z
	elif args.get("what", "book") == "machine":
		front = -target.global_basis.z
	front.y = 0.0
	front = front.normalized()
	right = front.cross(Vector3.UP).normalized()
	ground = target.global_position
	return true


func _run() -> void:
	await create_timer(float(args.get("wait", 4.0))).timeout
	if not _find():
		print("施設が見つからない: ", args.get("what"))
		quit(1)
		return
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var who: Node3D = main.player
	who.set_physics_process(false)
	who.set_process(false)
	var cam := Camera3D.new()
	cam.fov = _num("fov", 70.0)
	cam.cull_mask &= ~(1 << 2)   # 一人称の手と足は写さない
	root.add_child(cam)
	cam.current = true
	var c := ground + right * _num("side", 1.2) + front * _num("cam-back", 4.5) + Vector3.UP * _num("cam-h", 1.6)
	cam.look_at_from_position(c, ground + Vector3.UP * _num("look-h", 1.2) + right * _num("look-side", 0.0))
	cam.reset_physics_interpolation()
	var name_: String = args.get("what", "book")
	var far := _num("far", 7.0)
	var near := _num("near", 2.6)
	var at := func(d: float) -> void:
		who.global_position = ground + front * d + right * _num("walk-side", 0.0) + Vector3.UP * 0.1
		who.reset_physics_interpolation()
	at.call(near if args.has("still") else far)
	if not args.has("person"):
		var d = who.get("doll")
		if d:
			d.visible = false
	if args.has("still"):
		await create_timer(_num("still", 4.0)).timeout
		if args.get("what") == "machine":
			var sew: Node3D = main.sewing
			print("天板の高さ ", sew.machine.find_child("mv_table", true, false).get_child(0).get_aabb() if false else "", " 針の下 ", sew.machine.to_global(sew._mark["work"]).y - ground.y, " 立つ所 ", sew._mark["stand"], " 人形の背 ", who.doll.height() if who.get("doll") else 0.0, " ", who.doll.kind if who.get("doll") else "")
		root.get_texture().get_image().save_png(_dir().path_join(args.get("name", name_) + ".png"))
		print("保存: ", name_)
		quit()
		return
	await create_timer(_num("settle", 1.5)).timeout
	var walk := _num("walk-s", 1.5)
	var stay := _num("stay-s", 3.0)
	var back := int(_num("back", 1))
	var total := walk + stay + (walk + _num("leave-s", 3.0) if back else 0.0)
	var frames := int(total * 12.0)
	for k in frames:
		var t := float(k) / 12.0
		var d := near
		if t < walk:
			d = lerpf(far, near, t / walk)
		elif back and t > walk + stay:
			d = lerpf(near, far, minf(1.0, (t - walk - stay) / walk))
		at.call(d)
		await create_timer(1.0 / 12.0).timeout
		root.get_texture().get_image().save_png(_dir().path_join("%s_%03d.png" % [name_, k]))
	print("draw calls ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("保存: ", frames, " コマ ", _dir())
	quit()
