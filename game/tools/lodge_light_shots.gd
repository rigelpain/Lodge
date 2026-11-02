extends SceneTree
## ロッジの中の明るさを見て回る絵と fps（確かめ用。火の灯りの道具 lodge_lights.gd の前と後を比べる）。
##   Godot --path game --resolution 1280x720 -s res://tools/lodge_light_shots.gd -- --dir=/path/shots [--hours=13,22] [--tag=before] [--views=v01,v14]
##   --no-fire-lights  火の灯りの道具を置かない（置く前の絵）
##   --old-hearth      暖炉の火を前のまま（光る板と丸太。hearth_fire.gd を置かない）
##   --fps             撮らずに、いくつかの見渡しで灯りを消した・点けたを交互にして fps の平均を出す（--fps-views=v05_kitchen_w,… --rounds=2）
## 1 枚ごとに、明るさの平均と、暗い画素（明るさ 0.06 未満）の割合を出す。
## 見渡しの場所はロッジの座標（lodge/dims.py の x 東, y 北, 高さ。Godot ではロッジの (x, 高さ, -y)）

## [名前, 目の所 (x, y, 高さ), 見る所 (x, y, 高さ)]。1 階の床は 0.45、2 階の床は 6.1
const VIEWS := [
	["v01_entrance", Vector3(-13.4, -11.5, 2.05), Vector3(-10.4, 10.0, 1.4)],    # 入口から正面の炉
	["v02_sw_corner", Vector3(-20.5, -11.8, 2.2), Vector3(-10.0, 0.0, 1.0)],     # 南西の隅（貸出の棚・ミシン）
	["v03_nw_corner", Vector3(-20.5, 11.5, 2.2), Vector3(-5.0, -5.0, 1.0)],      # 北西の隅
	["v04_hearth", Vector3(-10.4, 3.0, 2.05), Vector3(-10.4, 12.0, 1.5)],        # 炉のまわり
	["v05_kitchen_w", Vector3(-3.0, 5.5, 2.05), Vector3(10.0, 11.0, 1.5)],       # 厨房を西から
	["v06_kitchen_e", Vector3(12.5, 7.5, 2.05), Vector3(-2.0, 11.0, 1.5)],       # 厨房を東から
	["v07_ne_stairs", Vector3(13.0, 4.0, 2.05), Vector3(21.0, 11.0, 2.0)],       # 北東の隅（内階段）
	["v08_east", Vector3(5.0, -5.0, 2.05), Vector3(21.5, -5.0, 1.0)],            # 東の壁へ
	["v09_hall", Vector3(20.0, -11.0, 4.6), Vector3(-6.0, 4.0, 0.5)],            # 南東の隅から 1 階ぜんぶ
	["v10_window_bar", Vector3(-6.0, -10.0, 2.05), Vector3(20.0, -12.0, 1.0)],   # 窓向きのカウンター
	["v11_vestibule", Vector3(-13.4, -16.8, 2.05), Vector3(-13.4, -12.0, 1.5)],  # 風除室（内の自動ドアを見る）
	["v12_vestibule_back", Vector3(-13.4, -11.0, 2.05), Vector3(-13.4, -17.5, 1.0)],   # 風除室を中から
	["v13_ceiling", Vector3(-4.0, -5.0, 2.05), Vector3(-4.0, 6.0, 5.6)],          # 1 階の天井
	["v14_2f_west", Vector3(-20.5, 2.0, 7.7), Vector3(5.0, 2.0, 6.5)],           # 2 階を西の端から
	["v15_2f_east", Vector3(20.0, 0.0, 7.7), Vector3(-5.0, 2.5, 6.5)],           # 2 階を東の端から
	["v16_2f_kotatsu", Vector3(-11.0, -1.8, 7.9), Vector3(5.0, 4.0, 6.4)],       # 座敷（こたつ）
	["v17_2f_wardrobe", Vector3(15.0, 2.2, 7.7), Vector3(21.5, 2.2, 7.0)],       # 衣装掛けと染め桶
	["v18_2f_north", Vector3(0.0, -2.0, 7.7), Vector3(0.0, 6.3, 7.0)],           # 2 階の北の壁
	["v19_2f_bench", Vector3(-6.0, 4.0, 7.7), Vector3(-19.0, -2.0, 6.6)],        # 2 階の西の長椅子と卓
	# 道具の寄り（--views=c で寄りだけ）
	["c1_torch", Vector3(20.2, -3.6, 2.6), Vector3(21.5, -4.4, 3.0)],
	["c2_gas", Vector3(-11.0, -14.5, 2.6), Vector3(-9.7, -15.2, 2.85)],
	["c3_candle", Vector3(3.55, -3.9, 1.65), Vector3(3.55, -2.8, 1.3)],
	["c4_stove", Vector3(10.2, 10.9, 2.0), Vector3(10.2, 12.0, 1.4)],
	["c5_stand", Vector3(-18.9, 8.6, 2.1), Vector3(-20.7, 9.6, 1.6)],
	["c6_kitchen_gas", Vector3(3.5, 7.0, 3.0), Vector3(1.7, 12.4, 4.1)],
	["c7_wheel", Vector3(-12.5, -9.5, 2.0), Vector3(-15.0, -6.5, 4.0)],
	["c8_hearth", Vector3(-9.6, 8.4, 1.35), Vector3(-10.4, 11.6, 0.9)],          # 暖炉の火（hearth_fire.gd。--old-hearth で前の火）
	# 真上からの間取り（--views=p。この高さより上を切って、正射影で見下ろす）
	["p1_plan_1f_w", Vector3(-11.0, -6.0, 4.5), Vector3.ZERO],
	["p2_plan_1f_e", Vector3(11.0, -6.0, 4.5), Vector3.ZERO],
	["p3_plan_1f_nw", Vector3(-11.0, 6.5, 5.3), Vector3.ZERO],
	["p4_plan_1f_ne", Vector3(11.0, 6.5, 5.3), Vector3.ZERO],
	["p5_plan_2f_w", Vector3(-11.0, 1.8, 8.3), Vector3.ZERO],
	["p6_plan_2f_e", Vector3(11.0, 1.8, 8.3), Vector3.ZERO],
]
const FPS_VIEWS := ["v01_entrance", "v05_kitchen_w", "v09_hall", "v14_2f_west", "v15_2f_east"]

var args := {}
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # daycycle.gd は current_scene の太陽を探す（入れないと、ずっと昼）
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/lodge_light_shots")


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
	if String(v[0]).begins_with("p"):   # 間取り: 高さ 40 m から見下ろし、eye.z より上を near で切る
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 14.0
		cam.near = 40.0 - eye.z
		cam.far = 60.0
		cam.global_transform = lodge.global_transform * Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(eye.x, 40.0, -eye.y))
		return
	cam.global_position = lodge.to_global(Vector3(eye.x, eye.z, -eye.y))
	cam.look_at(lodge.to_global(Vector3(at.x, at.z, -at.y)))


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := _dir().path_join(name + ".png")
	img.save_png(path)
	var sum := 0.0
	var dark := 0
	var n := 0
	for y in range(0, img.get_height(), 6):
		for x in range(0, img.get_width(), 6):
			var c := img.get_pixel(x, y)
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += lum
			dark += int(lum < 0.06)
			n += 1
	print("保存: %s  明るさ=%.3f 暗い所=%.0f%%" % [path, sum / n, 100.0 * dark / n])


func _run() -> void:
	await create_timer(4.0).timeout
	cam = Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	_look(VIEWS[0])   # 始めは素材の下ごしらえ（シェーダーの組み立て）で数秒黒く写るので、先に見せて待つ
	await create_timer(float(args.get("warm", "6"))).timeout
	if args.has("fps"):
		await _fps()
		quit()
		return
	var only: PackedStringArray = String(args.get("views", "")).split(",", false)
	var tag := String(args.get("tag", ""))
	var cycle := root.get_node_or_null("DayCycle")
	for hr in String(args.get("hours", "13,22")).split(",", false):   # 昼と夜を 1 回の起動で
		if cycle:
			cycle.hour = float(hr)
			cycle.day_seconds = 100000.0   # 撮るあいだに時刻が進まないように
		await create_timer(0.8).timeout
		var when := "day" if float(hr) >= 6.0 and float(hr) < 18.0 else "night"
		for v in VIEWS:
			if not _want(String(v[0]), only):
				continue
			_look(v)
			await create_timer(0.4).timeout
			await _shot(("%s_" % tag if tag != "" else "") + String(v[0]) + "_" + when)
	quit()


## --views の選び: 何もなければ見渡し（v）だけ。v・c・p で組ごと、v01 のような番号や名前で 1 枚ずつ
func _want(name: String, only: PackedStringArray) -> bool:
	var short := name.get_slice("_", 0)
	if only.is_empty():
		return short.begins_with("v")
	return only.has(name) or only.has(short) or only.has(short.left(1))


## 見渡しごとに、火の灯りの道具を消して 3 秒・点けて 3 秒の fps と、1 コマを描くのにかかった時間（GPU・CPU の ms）の平均。
## 同じ Mac のほかの重さのむらを、交互に測って均す。窓が隠れると fps は落ちる（描く時間の ms は落ちない）ので、ms も見る
func _fps() -> void:
	var lights := main.find_child("LodgeLights", true, false) as Node3D
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var tot := {0: [[], [], []], 1: [[], [], []], 2: [[], [], []]}
	var names := ["なし", "炎だけ", "炎と灯り"]
	var views: PackedStringArray = String(args.get("fps-views", ",".join(FPS_VIEWS))).split(",")
	for round_i in int(args.get("rounds", "2")):
		for v in VIEWS:
			if not views.has(v[0]):
				continue
			_look(v)
			for on in [0, 1, 2]:   # 0 置かない / 1 炎と形だけ（灯りを消す）/ 2 ぜんぶ
				if lights:
					lights.visible = on > 0
					for l in lights.find_children("*", "OmniLight3D", true, false):
						(l as OmniLight3D).visible = on == 2
				await create_timer(1.0).timeout
				var f := 0.0
				var cpu := 0.0
				var k := 0
				var t0 := Time.get_ticks_msec()
				while Time.get_ticks_msec() - t0 < 3000:
					await process_frame
					f += Engine.get_frames_per_second()
					cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
					k += 1
				tot[on][0].append(f / k)
				tot[on][1].append(0.0)
				tot[on][2].append(cpu / k)
				print("%s %s fps=%.1f CPU=%.2fms" % [v[0], names[on], f / k, cpu / k])
	for on in [0, 1, 2]:
		var out := []
		for a in tot[on]:
			var s := 0.0
			for x in a:
				s += x
			out.append(s / maxf(1, a.size()))
		print("平均 %s fps=%.1f CPU=%.2fms" % [names[on], out[0], out[2]])
	if lights == null:
		print("（火の灯りの道具はない）")
