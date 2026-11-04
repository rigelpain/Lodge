extends SceneTree
## 入口の横の大きな鏡（mirror.gd）を確かめる。保存（user://my_tag.cfg）は写しを取って戻す。
##   Godot --path game --resolution 1600x900 -s res://tools/mirror_shots.gd -- --part=look --spawn=mirror --no-sound --no-pip --dir=/path/shots
##   --part=look   鏡の前で、ふだん・案内・F で映る・もう一度 F で消える・離れると消える。引きと一人称の絵。log に結果
##   --part=dolls  人形 7 体の全身が絵に収まるか（絵の縁に人形の色が触れていないか）。小物とミニオン付き、手を上げた姿も
##   --part=color  染めた色・頭と肩の小物・ミニオン・身ぶり（高い手のひらで左右が鏡のとおりか）
##   --part=fps    映っていないとき・映っているときの fps（各 --sec=8 秒）
##   --part=pass   入口と人台の前を、人の太さで通れるか（当たりの形で測る）
##   --part=net    通信: 同じ Mac で 2 つ起動する（--host と --join=127.0.0.1。--port= をそろえる。どちらも --spawn=mirror）。
##                 つなぐ側だけ F で映し、ホストの画面の鏡が映っていないこと、つなぐ側の鏡の絵にホストが入っていないことを撮る

const Doll := preload("res://doll.gd")
const Pals := preload("res://pals.gd")
const TAG_FILE := "user://my_tag.cfg"

var args := {}
var main: Node3D
var p: CharacterBody3D
var m: Node3D
var lines: Array[String] = []
var _saved := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if FileAccess.file_exists(TAG_FILE):
		_saved = FileAccess.get_file_as_string(TAG_FILE)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/mirror")


func _tag() -> String:
	return "host" if args.has("host") else ("join" if args.has("join") else "")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	_say("撮った " + name)


## 別のカメラで撮る（from から at を見る。ロッジの座標）
func _cam_shot(name: String, from: Vector3, at: Vector3, fov := 50.0, tp := true) -> void:
	var lodge: Node3D = main.get_node("Lodge")
	var cam := Camera3D.new()
	cam.fov = fov
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4) | (1 << 7) if tp else cam.cull_mask
	main.add_child(cam)
	cam.look_at_from_position(lodge.to_global(from), lodge.to_global(at))
	cam.make_current()
	await _wait(0.5)
	await _shot(name)
	cam.queue_free()
	p.cam.make_current()


func _key(k: Key) -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = d
		Input.parse_input_event(e)
		await process_frame


## 鏡のロッジの座標で立ち、鏡の真ん中（高さ h）を向く
func _stand(x: float, dist: float, h := 1.7) -> void:
	var at: Vector3 = m.to_global(Vector3(x, 0.1, dist))
	p.global_position = at
	p.velocity = Vector3.ZERO
	var to: Vector3 = m.to_global(Vector3(0, h, 0.1))
	var eye := at + Vector3.UP * 1.4   # 目の高さの目安（カメラはまだ前の所にある）
	var d := to - at
	p.rotation.y = atan2(-d.x, -d.z)
	p._pitch = atan2(to.y - eye.y, Vector2(d.x, d.z).length())


## 鏡の絵の縁に人形の色があるか。[上, 下, 左, 右] の割合（色のある所の範囲）と、縁に触れた辺
func _coverage() -> Dictionary:
	await process_frame
	await process_frame
	var img: Image = m._vp.get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return {"img": img, "top": float(y0) / h, "bottom": float(y1) / h, "left": float(x0) / w, "right": float(x1) / w,
		"touch": y0 < 4 or y1 > h - 5 or x0 < 4 or x1 > w - 5, "tall": float(y1 - y0) / h}


func _wear(key: String) -> void:
	main.craft.send({"kind": "pal_own", "who": p.id, "key": key})
	main.craft.send({"kind": "pal_wear", "who": p.id, "slot": Pals.slot_of(key), "key": key})


func _run() -> void:
	await _wait(4.0)
	p = main.player
	m = main.mirror
	var dc := root.get_node_or_null("/root/DayCycle")
	if dc and not args.has("host") and not args.has("join"):
		dc.hour = float(args.get("hour", "13"))
		dc.day_seconds = 1.0e9
	match args.get("part", "look"):
		"look": await _look()
		"dolls": await _dolls()
		"color": await _color()
		"fps": await _fps()
		"pass": await _pass()
		"net": await _net()
	_end()


func _look() -> void:
	_stand(0.0, 3.4)
	await _wait(1.5)
	_say("向いている: 案内 %s 映っている %s" % [p.mirror_near(), m.shown])
	await _shot("01_fp_off")
	await _cam_shot("02_room_off", Vector3(-11.0, 2.6, 5.5), Vector3(-16.6, 2.4, 12.3))
	await _key(KEY_F)
	await _wait(1.2)
	_say("F: 映っている %s" % m.shown)
	await _shot("03_fp_on")
	await _cam_shot("04_room_on", Vector3(-11.0, 2.6, 5.5), Vector3(-16.6, 2.4, 12.3))
	await _cam_shot("05_side_on", Vector3(-13.0, 1.7, 7.0), Vector3(-16.9, 2.2, 12.3))
	await _key(KEY_F)
	await _wait(0.8)
	_say("もう一度 F: 映っている %s（描く %d）" % [m.shown, m._vp.render_target_update_mode])
	await _shot("06_fp_off_again")
	# 映したまま人台の桶を見下ろして F: 染める画面が開き、鏡は映ったまま
	await _key(KEY_F)
	await _wait(0.5)
	var w: Node3D = main.wardrobe
	var at: Vector3 = w.to_global(Vector3(0, 0.1, 2.6))
	p.global_position = at
	var d: Vector3 = w.global_position - at
	p.rotation.y = atan2(-d.x, -d.z)
	p._pitch = -0.6
	await _wait(0.5)
	await _key(KEY_F)
	await _wait(0.5)
	_say("映したまま桶を見下ろして F: 染める画面 %s 映っている %s" % [main.dye_ui.is_open, m.shown])
	await _key(KEY_ESCAPE)
	await _wait(0.5)
	_say("Esc: 染める画面 %s menu_open %s shopping %s 設定 %s" % [main.dye_ui.is_open, p.menu_open, p.shopping, main.settings.is_open])
	_stand(0.0, 3.2)
	await _wait(0.3)
	_say("鏡へ戻った: 向いている %s 映っている %s 目の高さ %.2f" % [m.can_use(p), m.shown, p.cam.global_position.y - p.global_position.y])
	await _key(KEY_F)
	await _wait(0.6)
	_say("もう一度 F: 映っている %s menu_open %s 向いている %s" % [m.shown, p.menu_open, m.can_use(p)])
	# 離れると消える
	await _key(KEY_F)
	await _wait(0.5)
	_say("F: 映っている %s" % m.shown)
	_stand(0.0, 8.5)
	await _wait(0.8)
	_say("8.5 m 離れた: 映っている %s" % m.shown)
	# 鏡を向いていないと映らない
	_stand(0.0, 3.0)
	p.rotation.y += PI
	await _wait(0.3)
	await _key(KEY_F)
	await _wait(0.3)
	_say("背を向けて F: 映っている %s 案内 %s" % [m.shown, p.mirror_near()])
	# 映ったまま入口から外へ
	_stand(0.0, 3.0)
	await _wait(0.3)
	await _key(KEY_F)
	await _wait(0.5)
	_say("F: 映っている %s" % m.shown)
	p.global_position = main.get_node("Lodge").to_global(Vector3(-13.4, 0.55, 13.5))
	await _wait(0.5)
	_say("入口の外: 映っている %s" % m.shown)


func _dolls() -> void:
	_stand(0.0, 3.0)
	await _wait(1.0)
	await _key(KEY_F)
	await _wait(0.6)
	var kinds: Array = Doll.KINDS
	_wear("moon_rabbit")
	_wear("phoenix")
	_wear("pony")
	for k in kinds:
		main.craft.send({"kind": "doll", "who": p.id, "doll": k})
		await _wait(1.8)
		var c: Dictionary = await _coverage()
		_say("%s 立ち: 高さ %.0f%% 上 %.2f 下 %.2f 左 %.2f 右 %.2f 縁に触れる %s" % [k, c.tall * 100.0, c.top, c.bottom, c.left, c.right, c.touch])
		(c.img as Image).save_png(_dir().path_join("doll_%s.png" % k))
		p._choose("high")
		p._set_hand("both")
		await _wait(1.0)
		c = await _coverage()
		_say("%s 両手を上げる: 高さ %.0f%% 上 %.2f 下 %.2f 左 %.2f 右 %.2f 縁に触れる %s" % [k, c.tall * 100.0, c.top, c.bottom, c.left, c.right, c.touch])
		(c.img as Image).save_png(_dir().path_join("doll_%s_up.png" % k))
		p._choose("high")
		await _wait(0.3)


func _color() -> void:
	_stand(0.0, 3.0)
	await _wait(1.0)
	main.craft.wallets[p.id] = 500
	var pals: Node = main.get_node("Pals%d" % p.id)
	_say("映す前: ミニオンは人形から %.1f m" % pals._pos.distance_to(p.doll.global_position))
	await _key(KEY_F)
	var t0 := Time.get_ticks_msec()
	while pals._pos.distance_to(m.pet_spot(p.doll)) > 0.4 and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_say("映してから %.1f 秒でミニオンが足もとに着く" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await _wait(1.5)
	await _shot("10_kasa_plain")
	(m._vp.get_texture().get_image() as Image).save_png(_dir().path_join("10_view.png"))
	main.craft.send({"kind": "dye", "who": p.id, "doll": p.doll.kind, "colors": ["c9603c", "d8a43e", "2f4e9a", ""]})
	await _wait(1.2)
	await _shot("11_kasa_dyed")
	_wear("crane")
	_wear("chameleon")
	_wear("chiyo_fox")
	await _wait(3.0)
	await _shot("12_worn_pet")
	_say("ミニオンの所: 人形から %.2f m" % (main.get_node("Pals%d" % p.id)._pos.distance_to(p.doll.global_position)))
	var lodge: Node3D = main.get_node("Lodge")
	var pet_w: Vector3 = main.get_node("Pals%d" % p.id)._pos
	await _cam_shot("16_main_pet", lodge.to_local(pet_w + m._to * 1.4 + Vector3.UP * 0.5), lodge.to_local(pet_w + Vector3.UP * 0.2), 40.0)
	p._set_hand("R")
	p._choose("high")
	await _wait(0.9)
	await _shot("13_right_hand_up")
	(m._vp.get_texture().get_image() as Image).save_png(_dir().path_join("13_view.png"))
	p._choose("high")
	p.emote("nn")
	await _wait(0.5)
	await _shot("14_nn")
	await _wait(1.5)
	# 見回す: 斜めからの姿が見える
	p.rotation.y += 0.6
	await _wait(1.0)
	await _shot("15_turn")
	p.rotation.y -= 0.6
	await _wait(0.3)
	await _key(KEY_F)
	await _wait(5.0)
	_say("消して 5 秒: ミニオンは人形から %.1f m（暖炉へ帰る）" % pals._pos.distance_to(p.doll.global_position))


func _fps() -> void:
	_stand(0.0, 3.2)
	await _wait(2.0)
	var sec := float(args.get("sec", "8"))
	for round_i in 2:
		_say("映っていない: %s" % await _measure(sec))
		await _key(KEY_F)
		await _wait(1.0)
		_say("映っている: %s" % await _measure(sec))
		await _key(KEY_F)
		await _wait(1.0)


func _measure(sec: float) -> String:
	var t := 0.0
	var n := 0
	var worst := 0.0
	while t < sec:
		await process_frame
		var d := root.get_process_delta_time() if false else main.get_process_delta_time()
		t += d
		n += 1
		worst = maxf(worst, d)
	return "%.1f fps（いちばん長いコマ %.1f ms）" % [n / t, worst * 1000.0]


## 人の太さ（player の当たりの形）で、通り道を少しずつ見る。当たった所を出す
func _pass() -> void:
	await _wait(1.0)
	var lodge: Node3D = main.get_node("Lodge")
	var shape: CollisionShape3D = null
	for c in p.get_children():
		if c is CollisionShape3D:
			shape = c
	var routes := {
		"鏡の枠と桶のあいだ（西へ。z 11.85）": [Vector3(-14.5, 1.4, 11.85), Vector3(-20.5, 1.4, 11.85)],
		"入口のマットから食堂へ": [Vector3(-13.4, 1.4, 13.0), Vector3(-13.4, 1.4, 5.0)],
		"入口から鏡の前を通って人台の正面へ": [Vector3(-14.9, 1.4, 11.9), Vector3(-15.2, 1.4, 7.0)],
		"鏡の東の端と戸の縁": [Vector3(-14.95, 1.4, 11.5), Vector3(-14.95, 1.4, 12.2)],
	}
	var sp := p.get_world_3d().direct_space_state
	for name in routes:
		var a: Vector3 = routes[name][0]
		var b: Vector3 = routes[name][1]
		var hits := {}
		var n := 60
		for i in n + 1:
			var at := a.lerp(b, float(i) / n)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape.shape
			q.transform = Transform3D(Basis(), lodge.to_global(at))
			q.exclude = [p.get_rid()]
			for r in sp.intersect_shape(q, 8):
				if r.collider != m.get_child(1) and not r.collider is StaticBody3D:
					continue
				hits[str(r.collider.name)] = at
		_say("%s: %s" % [name, "通れる" if hits.is_empty() else "当たる %s" % str(hits)])


func _net() -> void:
	var net: Node = main.net
	var t := 0.0
	while net.remotes.is_empty() and t < 30.0:
		await _wait(0.5)
		t += 0.5
	if net.remotes.is_empty():
		_say("相手が来なかった")
		return
	var pid: int = net.remotes.keys()[0]
	var rp: Node3D = net.remotes[pid]
	if net.is_host():
		_stand(1.0, 3.6)   # ホスト: 鏡の前で、映さずに立つ
	else:
		_stand(-0.6, 3.2)
	await _wait(2.0)
	if not net.is_host():
		await _key(KEY_F)
	await _wait(2.0)
	_say("%s: 映っている %s 相手の人形の層 %d 相手の所 %s" % [_tag(), m.shown, rp.doll.layers, rp.global_position])
	await _shot("20_net_%s" % _tag())
	if m.shown:
		(m._vp.get_texture().get_image() as Image).save_png(_dir().path_join("21_view_%s.png" % _tag()))
	await _wait(15.0 if net.is_host() else 1.0)


func _end() -> void:
	var f := FileAccess.open(_dir().path_join("log%s.txt" % ("_" + _tag() if _tag() != "" else "")), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	if _saved != "":
		var g := FileAccess.open(TAG_FILE, FileAccess.WRITE)
		g.store_string(_saved)
	elif FileAccess.file_exists(TAG_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TAG_FILE))
	quit()
