extends SceneTree
## ロッジの 2 階の掘りごたつを、決まった所から昼と夜に撮り、1 コマに描く三角形の数と描く回数を出す（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/kotatsu_shots.gd -- --no-sound --dir=/path/shots [--tag=after]
##     [--sets=patch,indigo,...（8 卓の柄を差し替える）] [--pendant=drum|lantern|cone（吊り灯りの形を差し替える）] [--sit]
##     [--hours=13,22] [--views=wide,near,row,lamp] [--kinds=musha,robo,...（--sit で座らせる人形。席の順に）]
##     [--sit-seats=6,7（--sit で座らせる席。その卓の席の並びの番号: 0〜2 北の列、3 西、4 東、5〜7 南の列、どれも西から）]
## --sit: 南の列の西から 2 卓目のこたつの座布団に、7 体の人形を座らせる。
## 三角形の数は本体の画面だけ（360 の小窓は止める）。場所はロッジの座標（lodge/dims.py の x 東, y 北, 高さ。Godot ではロッジの (x, 高さ, -y)）。2 階の畳の面は 6.5

const Doll := preload("res://doll.gd")
const Props := preload("res://props.gd")
const ZT := 6.5
## 見渡し: [名前, 目の所, 見る所, fov]
const VIEWS := [
	["wide", Vector3(-2.5, 8.4, ZT + 1.05), Vector3(-10.9, -20.7, ZT + 1.2), 62.0],   # lodge/ の kotatsu のカメラと同じ所
	["near", Vector3(2.3, -2.6, ZT + 1.45), Vector3(-0.36, 1.0, ZT + 0.1), 55.0],      # 南の列の 2 卓目を南東から
	["row", Vector3(16.6, 3.0, ZT + 1.6), Vector3(-8.0, 2.6, ZT + 0.2), 60.0],        # 東の端から 2 列を見通す
	["lamp", Vector3(2.6, -1.8, ZT + 1.5), Vector3(-0.36, 1.0, ZT + 2.7), 50.0],      # 南の列の 2 卓目の吊り灯りを見上げる
	# 天板と布団の重なりを見る（南の列の 2 卓目）
	["side", Vector3(-0.36, -1.4, ZT + 0.33), Vector3(-0.36, 1.0, ZT + 0.3), 40.0],   # 南から、天板の高さで真横に
	["corner", Vector3(0.3, -0.9, ZT + 0.36), Vector3(1.0, 0.6, ZT + 0.3), 35.0],   # 南東の角を、南から天板の高さで（行灯をよける）
	["above", Vector3(1.5, -1.2, ZT + 1.6), Vector3(-0.36, 1.0, ZT + 0.3), 45.0],     # 南東の斜め上から
	["eye", Vector3(-0.36, -0.75, ZT + 0.75), Vector3(-0.36, 1.0, ZT + 0.3), 60.0],   # 南の座布団に座った目の高さ
	["lap", Vector3(-2.4, -2.3, ZT + 1.2), Vector3(-0.36, 0.0, ZT + 0.15), 38.0],     # 南の列の座布団（--sit の人形の膝）を西から
	["lap_e", Vector3(1.7, -2.3, ZT + 1.2), Vector3(-0.36, 0.0, ZT + 0.15), 38.0],    # 同じく東から
	["lap_sw", Vector3(-2.0, -1.0, ZT + 0.8), Vector3(-1.0, 0.2, ZT + 0.2), 40.0],    # 南の列の西の席の膝を、南西から近くで
	# 辺ごとの布団の並びを正面から（どの席がめくれているか）
	["hem_s", Vector3(-0.36, -2.0, ZT + 1.25), Vector3(-0.36, 0.1, ZT + 0.2), 42.0],
	["hem_n", Vector3(-0.36, 4.0, ZT + 1.25), Vector3(-0.36, 1.9, ZT + 0.2), 42.0],
	["hem_e", Vector3(3.2, 1.0, ZT + 1.25), Vector3(1.0, 1.0, ZT + 0.2), 42.0],
	["over_s", Vector3(-0.1, 1.5, ZT + 1.5), Vector3(-0.1, -0.1, ZT + 0.2), 50.0],     # 卓の上から南の列の布団を見下ろす（隣どうしのあいだ）
	# 南の列のまんなかの席の、めくれた布の左右の端を近くから
	["fold_w", Vector3(-1.5, -0.75, ZT + 0.75), Vector3(-0.5, 0.25, ZT + 0.2), 40.0],
	["fold_e", Vector3(0.8, -0.75, ZT + 0.75), Vector3(-0.2, 0.25, ZT + 0.2), 40.0],
]
const SIT_AT := Vector2(-0.363, 1.0)   # 座らせるこたつ（南の列の西から 2 卓目）のまんなか

var args := {}
var main: Node3D
var lodge: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # daycycle.gd は current_scene の太陽と空を探す
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/kotatsu_shots")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _run() -> void:
	await create_timer(3.0).timeout
	lodge = main.get_node("Lodge") as Node3D
	for c in root.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	for c in main.get_children():   # ゲームの人（あなた・仲間）は隠す
		if c.get("doll") != null:
			c.visible = false
	for vp in main.find_children("*", "SubViewport", true, false):   # 右上の 360 の小窓は止める（三角形の数を本体の画面だけにする）
		(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	if args.has("sets"):
		_swap_sets(String(args.sets).split(","))
	if args.has("pendant"):
		_swap_pendants(String(args.pendant))
	if args.has("sit"):
		await _sit_dolls()
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var dc := root.get_node_or_null("DayCycle")
	if dc:
		dc.day_seconds = 1000000.0
	var tag := str(args.get("tag", "shot"))
	var lines: Array[String] = []
	var views: Array = Array(String(args.get("views", "wide,near,row")).split(","))
	for h in String(args.get("hours", "13,22")).split(","):
		if dc:
			dc.hour = float(h)
			dc.set("_sky_t", 10.0)   # 空と霧の色もすぐ決め直す
		for v in VIEWS:
			if not views.has(v[0]):
				continue
			var eye: Vector3 = v[1]
			var at: Vector3 = v[2]
			cam.fov = v[3]
			cam.global_position = lodge.to_global(Vector3(eye.x, eye.z, -eye.y))
			cam.look_at(lodge.to_global(Vector3(at.x, at.z, -at.y)))
			await create_timer(0.6).timeout
			await process_frame
			await process_frame
			var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			var name := "%s_%s_%02d" % [tag, v[0], int(float(h))]
			root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
			lines.append("%s: 三角形 %d、描く回数 %d" % [name, tris, draws])
			print(lines[-1])
	lines.append("こたつの組の三角形（8 卓の合計、近くの細かさ）: %d" % _set_tris())
	print(lines[-1])
	var f := FileAccess.open(_dir().path_join(tag + "_tris.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	quit()


## 置いたこたつの組（slot_kotatsu_* の下）の三角形の数
func _set_tris() -> int:
	var n := 0
	for i in 8:
		var ks := lodge.find_child("slot_kotatsu_%d" % i, true, false)
		if ks == null:
			continue
		for m in ks.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (m as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(si)
				n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _swap_sets(pats: PackedStringArray) -> void:
	for i in pats.size():
		var ks := lodge.find_child("slot_kotatsu_%d" % i, true, false) as Node3D
		if ks == null:
			continue
		for c in ks.get_children():
			if String(c.name).begins_with("Kotatsu"):   # 行灯は残す
				c.queue_free()
		var kset := (load("res://props/sets/kotatsu_lodge_%s.tscn" % pats[i]) as PackedScene).instantiate()
		ks.add_child(kset)
		preload("res://kotatsu_futon.gd").attach(kset)


func _swap_pendants(kind: String) -> void:
	for i in 8:
		var hook := lodge.find_child("slot_pendant_%d" % i, true, false) as Node3D
		var ks := lodge.find_child("slot_kotatsu_%d" % i, true, false) as Node3D
		if hook == null or ks == null:
			continue
		for c in hook.get_children():
			c.free()
		main._hang_pendant(hook, hook.position.y - ks.position.y - main.KOTATSU_LAMP_TOP, kind)


## 7 体の人形を、1 卓のこたつの座布団に座らせる
func _sit_dolls() -> void:
	var seats = main.get("seats")
	while seats == null or seats.seats.is_empty():
		await process_frame
		seats = main.get("seats")
	var center := lodge.to_global(Vector3(SIT_AT.x, ZT, -SIT_AT.y))   # 差し替える前の glb には目印がない
	var mine := []
	for i in seats.seats.size():
		var st: Dictionary = seats.seat(i)
		if st.kind == "zabuton" and st.pos.distance_to(center) < 3.0:
			mine.append(i)
	if args.has("sit-seats"):
		mine = Array(String(args["sit-seats"]).split(",")).map(func(j): return mine[int(j)])
	var k := 0
	var kinds: Array = Array(String(args.kinds).split(",")) if args.has("kinds") else Doll.KINDS
	for i in mine:
		if k >= kinds.size():
			break
		var st: Dictionary = seats.seat(i)
		var host := Node3D.new()
		root.add_child(host)
		var d := Doll.new()
		d.kind = kinds[k]
		host.add_child(d)
		d.act = Doll.Act.SIT
		d.sit_stage = 2
		host.global_position = st.pos
		d.facing = st.face
		d.set("_yaw", atan2(-st.face.x, -st.face.z))
		d.seat_drop = st.pos.y - st.floor
		if "seat_edge" in d:
			d.seat_edge = st.get("edge", 0.2)
		if "seat_soft" in d:
			d.seat_soft = true
		d.set("_next_breath", 100000)
		k += 1
	print("座らせた人形: %d 体（席 %d 個）" % [k, mine.size()])
	await create_timer(1.0).timeout
