extends SceneTree
## ロッジ 1 階の暖炉とまわりの居場所を撮る（確かめ用。作り直しの前と後を比べる）。
##   Godot --path game --resolution 1280x720 -s res://tools/hearth_shots.gd -- --dir=/path/shots [--hours=13,22] [--views=h1,h2] [--tag=before]
##   --sit=kasa,origami,…  人形を新しい席に座らせて撮る（--sit=all で 7 体）。席は近い順に 1 体ずつ
## 見渡しの場所はロッジの座標（lodge/dims.py の x 東, y 北, 高さ。Godot ではロッジの (x, 高さ, -y)）。1 階の床は 0.45

## [名前, 目の所 (x, y, 高さ), 見る所 (x, y, 高さ)]
const FL1 := 0.45
const VIEWS := [
	["h1_entrance", Vector3(-13.4, -11.5, 2.05), Vector3(-10.4, 10.0, 1.6)],   # 入口から正面の炉
	["h2_plan", Vector3(-10.4, 4.5, 4.4), Vector3.ZERO],                       # 真上から（この高さより上を切る）
	["h3_seated", Vector3(-10.4, 5.4, 1.25), Vector3(-10.4, 12.0, 1.4)],       # 暖炉の前に座った目線
	["h4_side", Vector3(-3.0, 2.0, 2.4), Vector3(-12.5, 8.5, 0.8)],            # 南東から居場所ぜんぶ
	["h5_close", Vector3(-9.2, 7.6, 1.5), Vector3(-10.4, 11.4, 1.1)],          # 火の寄り
]

const Doll := preload("res://doll.gd")
const Seats := preload("res://seats.gd")

var args := {}
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # daycycle.gd は current_scene の太陽を探す
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/hearth_shots")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	for l in main.find_children("*", "CanvasLayer", true, false):   # HUD・小窓を出さない
		(l as CanvasLayer).visible = false
	return false


func _look(v: Array) -> void:
	var lodge := main.get_node("Lodge") as Node3D
	var eye: Vector3 = v[1]
	var at: Vector3 = v[2]
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.near = 0.05
	cam.far = 400.0
	if String(v[0]).ends_with("plan"):   # 間取り: 高さ 40 m から細い画角で見下ろし、eye.z より上を near で切る
		cam.fov = 2.0 * rad_to_deg(atan(8.0 / (40.0 - FL1)))
		cam.near = 40.0 - eye.z
		cam.far = 60.0
		cam.global_transform = lodge.global_transform * Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(eye.x, 40.0, -eye.y))
		return
	cam.fov = 70.0
	cam.global_position = lodge.to_global(Vector3(eye.x, eye.z, -eye.y))
	cam.look_at(lodge.to_global(Vector3(at.x, at.z, -at.y)))


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _run() -> void:
	await create_timer(4.0).timeout
	cam = Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	if main.player:   # 自分の体が写らないよう、居場所の外へ
		main.player.global_position = (main.get_node("Lodge") as Node3D).to_global(Vector3(18.0, 0.5, 8.0))
	_look(VIEWS[0])   # 始めは素材の下ごしらえで数秒黒く写るので、先に見せて待つ
	await create_timer(float(args.get("warm", "6"))).timeout
	if args.has("sit"):
		await _sit_dolls()
	if args.has("fps"):
		await _fps()
		quit()
		return
	var only: PackedStringArray = String(args.get("views", "")).split(",", false)
	var tag := String(args.get("tag", ""))
	var cycle := root.get_node_or_null("DayCycle")
	for hr in String(args.get("hours", "13,22")).split(",", false):
		if cycle:
			cycle.hour = float(hr)
			cycle.day_seconds = 100000.0   # 撮るあいだに時刻が進まないように
		await create_timer(0.8).timeout
		var when := "day" if float(hr) >= 6.0 and float(hr) < 18.0 else "night"
		for v in VIEWS:
			if not only.is_empty() and not only.has(String(v[0]).get_slice("_", 0)):
				continue
			_look(v)
			await create_timer(0.4).timeout
			await _shot("%s%s_%s" % [tag + "_" if tag != "" else "", v[0], when])
	quit()


## 人形を、暖炉のまわりの席（ソファ・揺り椅子・ビーズクッション）に 1 体ずつ座らせる（確かめ用の人形をその場で作る）。
## 種類が偏らないよう、揺り椅子・ビーズクッション・ソファの順に配る
func _sit_dolls() -> void:
	var names: PackedStringArray = String(args.get("sit")).split(",", false)
	if names.size() == 1 and names[0] == "all":
		names = PackedStringArray(["kasa", "origami", "news", "robo", "musha", "ningyo", "golem"])
	var seats = main.seats
	if seats == null:
		return
	var by_kind := {"rocker": [], "beanbag": [], "sofa": []}
	for i in seats.seats.size():
		var k: String = seats.seats[i].kind
		if by_kind.has(k):
			by_kind[k].append(i)
	var order := []
	for r in 8:
		for k in ["rocker", "beanbag", "sofa"]:
			var j: int = r if k != "sofa" else r * 2 + 1   # ソファは 1 つおきに（並んだ姿が見えるように）
			if j < by_kind[k].size():
				order.append(by_kind[k][j])
	for i in mini(names.size(), order.size()):
		var st: Dictionary = seats.seat(order[i])
		var host := Node3D.new()
		root.add_child(host)
		host.global_position = st.pos
		var d: Node3D = Doll.new()
		d.kind = names[i]
		host.add_child(d)
		d.act = Doll.Act.SIT
		d.sit_stage = 2
		d.facing = st.face
		d.set("_yaw", atan2(-st.face.x, -st.face.z))
		d.seat_drop = st.pos.y - st.floor
		d.seat_edge = st.edge
		if st.has("rock_axis"):
			d.rock_axis = st.rock_axis
			d.rock_at = st.rock_at
			d.rock = float(st.get("rock_lean", 0.0))
			_rocking.append([d, st])
	await create_timer(1.5).timeout


var _rocking := []


func _physics_process(_dt: float) -> bool:
	for r in _rocking:   # 揺り椅子: 座りきってからのつもりで揺らす
		r[0].rock = Seats.rock_of(r[1], Doll.frame_index(), -100, -1)
	return false


## 居場所を見渡す所で、暖炉と家具（HearthNook）を見せた・隠したを交互にして、fps の平均を出す（--fps）
func _fps() -> void:
	var nook := main.find_child("HearthNook", true, false) as Node3D
	var sums := {true: 0.0, false: 0.0}
	for v in [VIEWS[0], VIEWS[3]]:
		_look(v)
		for r in 2:
			for on in [true, false]:
				nook.visible = on
				await create_timer(1.0).timeout
				var f0 := Engine.get_frames_drawn()
				var t0 := Time.get_ticks_msec()
				await create_timer(3.0).timeout
				var fps := float(Engine.get_frames_drawn() - f0) / ((Time.get_ticks_msec() - t0) / 1000.0)
				sums[on] += fps / 4.0
				print("%s %s: %.1f fps" % [v[0], "あり" if on else "なし", fps])
	print("平均: あり %.1f fps、なし %.1f fps" % [sums[true], sums[false]])
