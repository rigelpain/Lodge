extends SceneTree
## 食べる動き（emotes.gd の eat・doll.gd）を、7 体の人形それぞれ正面から撮る。ぬくもり（warmth.gd）と湿り気（damp.gd）の数も出す（確かめ用）。
## 湿り気は食べる前に 20（びしょびしょ）にしておき、ひと口ごとに戻るのを見る
##   Godot --path game --resolution 1280x720 -s res://tools/eat_shots.gd -- --bots=0 --no-pip --dir=/path/shots [--fp]
## 撮るもの: <人形>_k00（持つ）・k03（口へ運ぶ）・k07（噛む）・k13（下ろす）、最後のひと口のあと
## --fp で、kasa の一人称（口もとへ運ぶ）も撮る

const Doll := preload("res://doll.gd")
const Food := preload("res://food.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/eat_shots")


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	print("保存: ", name)


func _give(dish: String) -> void:
	var c: Node = main.craft
	var it := Food.item(dish)
	it["step"] = Food.route(dish).size()
	c.bags[p.id].append(it)
	c.hands[p.id] = c.bags[p.id].size() - 1


func _wait_k(k: int) -> void:
	while p._em.is_empty() or p._em.kind != "eat" or p._em_k() < k:
		await process_frame


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	var hub = main.emotes
	hub.balls[p.id] = 0
	# ロッジの中（暖かいので白い息で顔が隠れない）。--outside で雪の上（ふるえと、食べ終えたあとの白い息）
	if args.has("outside"):
		p.global_position = Vector3(0, main.height(0.0, 30.0) + 0.2, 30.0)
	else:
		var sh = main.snowman_shop
		p.global_position = sh.counter.global_position - sh.counter.global_basis.z * 3.5 + Vector3.UP * 0.1
	p.rotation.y = 0.0
	await create_timer(0.5).timeout
	var cam := Camera3D.new()
	root.add_child(cam)
	for kind in (["kasa"] if args.has("fp") else Doll.KINDS):
		main.craft.send({"kind": "doll", "who": p.id, "doll": kind})
		await create_timer(0.6).timeout
		if args.has("fp"):
			p.set_third(false)
		else:
			p.set_third(true)
			var sk: Skeleton3D = p.doll.skel
			var hb := sk.find_bone("head")
			var head: Vector3 = sk.global_transform * sk.get_bone_global_pose(hb).origin if hb >= 0 else p.global_position + Vector3.UP * 1.3
			var size := maxf(0.6, head.y - p.global_position.y)   # 体の大きさ（足もとから頭まで）
			cam.look_at_from_position(head - p.global_basis.z * size * 1.5 + Vector3.UP * size * 0.1 + p.global_basis.x * size * 0.35,
					head - Vector3.UP * size * 0.2)
			cam.fov = 45.0
			cam.current = true
		for c in root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = args.has("fp")
		var dish := "taiyaki" if kind != "musha" else "cocoa"
		main.damp.put(p.id, 20.0)
		main.damp.pending.erase(p.id)
		_give(dish)
		await create_timer(0.4).timeout
		await _shot("%s_k00" % kind)
		p._eating = true
		p._bite()
		for k in [3, 7, 13]:
			await _wait_k(k)
			await _shot("%s_k%02d" % [kind, k])
		while not p.held().is_empty():
			await process_frame
		p._eating = false
		await create_timer(0.3).timeout
		await _shot("%s_done" % kind)
		var w = main.warmth
		print("%s: 食べたぬくもり %.2f 暖炉 %.2f 押す力 x%.2f ふるえを弱める %.2f" % [kind, w.food.get(p.id, 0.0), w.fire.get(p.id, 0.0),
				p.push_boost, p.doll.warm_food])
		print("%s: 湿り気 %.0f（20 から）これから戻る %.0f" % [kind, main.damp.value(p.id), main.damp.coming(p.id)])
	# ぬくもりの減り方（食べ物は長く、暖炉はすぐ冷める）
	var w = main.warmth
	print("外で 60 秒後の食べたぬくもり（見込み） %.2f → %.2f" % [w.food.get(p.id, 0.0), maxf(0.0, w.food.get(p.id, 0.0) - w.FOOD_FADE * 60.0)])
	quit()
