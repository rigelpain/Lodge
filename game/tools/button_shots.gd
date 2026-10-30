extends SceneTree
## 雪に縫い留められたボタン（snow_buttons.gd）を撮る（見た目の確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/button_shots.gd -- \
##       --no-player --bots=0 --no-sound --no-pip --dir=/path/shots --case=<名前>（mountain は大きな山のコース）
## 場面（--case）:
##   field  ゲームと同じ選び方（_pick_spot）でばらばらに 12 個降らせ、縫い付いたあと、上から斜めに見た全体と、
##          遠く（ふもとの登り口）から見上げた 2 枚
##   close  ボタン 1 つを近くから。風を強くして、ほどけた糸の端がそよぐ様子を 6 コマ（コマ撮りの 1 コマおき）の 1 枚に
##   roll   強い風で、ころころ 2 回転がって糸に引かれて戻る様子を、コマ撮りの 1 コマごとに並べた 1 枚
##   fall   空からひらひら降ってきて、雪に着き、糸がするっと縫い付く様子を、2 コマおきに並べた 1 枚
##   snip   中のソリ（乗る人 1 人）がばらばらのボタンの上を滑り、滑り木で糸が切れてボタンがぽんと跳ね、ソリへ飛んでいくまでを、1 コマごとに並べた 1 枚
##   hud    （--no-player なしで）財布にボタンが入る（木 1・真鍮 10・白蝶貝 100・螺鈿 1000 を順に）。
##   tiers  お金の 4 段（木・真鍮・白蝶貝・螺鈿）を横に並べ、近くからと、遠く（ふもとの登り口）から。遠くは光るまたたきの確かめ
##   shears （--no-player なしで）歩いて近づいたときの案内（F と裁ちばさみのワッペン）と、裁ちばさみで切る動き（1 コマごと）
##   ride   （--no-player なしで）頂上から乗って滑り、止まったときに速さの表示の糸が巻き取られ、ボタンが財布へ飛ぶまで。
##          途中で真鍮の縫い込み（ride_mark）を 1 つ、確かめのために出す画面の下で財布がぽんと増えるまでを並べた 1 枚
## 並べた 1 枚は <dir>/<case>_sheet.png、1 枚ずつは <dir>/<case>_<名前>.png。

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sb: Node3D
var cam: Camera3D
var _frames: Array[Image] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/button_shots")


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame


## コマ撮りのコマ（12 fps）が n 進むまで待つ
func _wait_steps(n: int) -> void:
	var target := _frame() + n
	while _frame() < target:
		await process_frame
	await process_frame   # 描き直されたあとのコマを撮る


func _frame() -> int:
	return preload("res://doll.gd").frame_index()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _save(img: Image, name: String) -> void:
	var path := "%s/%s_%s.png" % [_dir(), args.get("case", "field"), name]
	img.save_png(path)
	print("撮影: ", path)


## 並べた 1 枚（cols 列）。1 枚ずつは幅 w に縮める
func _sheet(imgs: Array[Image], cols: int, w := 480) -> void:
	if imgs.is_empty():
		return
	var h := int(w * imgs[0].get_height() / float(imgs[0].get_width()))
	var rows := ceili(imgs.size() / float(cols))
	var out := Image.create(cols * w + (cols + 1) * 4, rows * h + (rows + 1) * 4, false, Image.FORMAT_RGB8)
	out.fill(Color(0.15, 0.15, 0.18))
	for i in imgs.size():
		var im := imgs[i].duplicate() as Image
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(4 + (i % cols) * (w + 4), 4 + (i / cols) * (h + 4)))
	var path := "%s/%s_sheet.png" % [_dir(), args.get("case", "field")]
	out.save_png(path)
	print("並べた 1 枚: ", path)


func _look(from: Vector3, to: Vector3, fov := 60.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		main.add_child(cam)
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to)
	cam.current = true


func _snow(x: float, z: float) -> Vector3:
	return Vector3(x, main.height(x, z) + main.snow_lift(x, z), z)


func _run() -> void:
	await _wait_frames(20)
	sb = main.snow_buttons
	sb.auto = false
	if main.hud:
		main.hud.visible = false
	match args.get("case", "field"):
		"field":
			await _case_field()
		"mountain":
			await _case_mountain()
		"close":
			await _case_close()
		"roll":
			await _case_roll()
		"fall":
			await _case_fall()
		"snip":
			await _case_snip()
		"hud":
			await _case_hud()
		"tiers":
			await _case_tiers()
		"shears":
			await _case_shears()
		"ride":
			await _case_ride()
	quit()


func _case_field() -> void:
	sb.gust_override = 0.6
	for i in 12:
		var p: Vector3 = sb._pick_spot()
		if p != Vector3.INF:
			sb.drop_at(p)
		await _wait_steps(2)
	await _wait_steps(34 + 12 + 6)
	_look(_snow(16, 2) + Vector3.UP * 11.0, _snow(0, 20), 58.0)
	_save(await _grab(), "above")
	_look(_snow(2, 40) + Vector3.UP * 1.6, _snow(0, 14) + Vector3.UP * 0.5, 60.0)
	_save(await _grab(), "far")


## 大きな山のコースに降ったボタン（山ごと・標高ごと。上ほど多く、上の素材が多い）: 頂上の上から下を、中腹から上を見る
func _case_mountain() -> void:
	const Mountain := preload("res://mountain.gd")
	sb.gust_override = 0.4
	for i in 200:
		if sb._live("mountain") >= int(sb.MAP_MAX["mountain"]):
			break
		var p: Vector3 = sb._pick_spot("mountain")
		if p != Vector3.INF:
			sb.drop_at(p, -1, true)
	await _wait_steps(4)
	var cx := Mountain.COURSE_X
	var tiers := [0, 0, 0, 0]
	for b in sb.buttons.values():
		tiers[b.tier] += 1
	print("大きな山のボタン: 木 %d・真鍮 %d・白蝶貝 %d・螺鈿 %d" % tiers)
	_look(_snow(cx + 3.0, Mountain.top_z - 4.0) + Vector3.UP * 3.5, _snow(cx, Mountain.top_z - 34.0), 55.0)
	_save(await _grab(), "top")
	var mid: Array = Mountain.section("中腹")
	_look(_snow(cx + 6.0, mid[1] + 4.0) + Vector3.UP * 3.0, _snow(cx, mid[0] + 40.0) + Vector3.UP * 4.0, 60.0)
	_save(await _grab(), "mid")


func _case_close() -> void:
	var id: int = sb.drop_at(Vector3(0, 0, 14.0), 0)
	sb.gust_override = 0.2
	await _wait_steps(34 + 12 + 4)
	var b = sb.button(id)
	_look(b.at + Vector3(1.1, 0.7, -0.6), b.at + Vector3(0, 0.05, 0.1), 45.0)
	await _wait_steps(1)   # 近くで糸を描き直してから
	_save(await _grab(), "calm")
	sb.gust_override = 0.75
	var imgs: Array[Image] = []
	for i in 6:
		await _wait_steps(2)
		imgs.append(await _grab())
	_save(imgs[0], "gust")
	_sheet(imgs, 3)


func _case_roll() -> void:
	var id: int = sb.drop_at(Vector3(0, 0, 14.0), 0)
	sb.gust_override = 0.3
	await _wait_steps(3 + 34 + 12 + 4)
	var b = sb.button(id)
	_look(b.at + Vector3(-2.3, 1.2, 0.9), b.at + Vector3(0.5, 0.1, 0.0), 45.0)
	sb.gust_override = 0.5
	sb.force_roll(id, 2, Vector3(1, 0, 0))
	var imgs: Array[Image] = []
	for i in 30:
		await _wait_steps(1)
		imgs.append(await _grab())
	_sheet(imgs, 6, 360)


func _case_fall() -> void:
	sb.gust_override = 0.3
	var at := _snow(0, 14)
	_look(at + Vector3(1.3, 1.0, -1.9), at + Vector3(0, 0.7, 0), 50.0)
	sb.drop_at(Vector3(0, 0, 14.0), 0)
	var imgs: Array[Image] = []
	await _wait_steps(16)   # 高い所は画面の外。降りてきてから撮る
	for i in 30:
		imgs.append(await _grab())
		await _wait_steps(1)
	_sheet(imgs, 5, 384)


func _case_snip() -> void:
	var sled: RigidBody3D = main.sled
	var dummy := GDScript.new()
	dummy.source_code = DUMMY_SRC
	dummy.reload()
	var z0 := 5.0
	sled.reset_to(Vector3(0, main.height(0, z0) + 0.3, z0))
	sled.rotation.y = PI
	sled.parked = false
	await _wait_frames(2)
	var rx: float = sled.to_global(Vector3(sled.RUNNER_X, 0, 0)).x   # 右の滑り木の通る所に、少しずつずらして置く
	var ids := []
	for k in 5:
		ids.append(sb.drop_at(Vector3(rx + [0.1, -0.2, 0.15, -0.1, 0.2][k], 0, 14.0 + k * 3.4), k))
	sb.gust_override = 0.4
	await _wait_steps(34 + 12 + 2)
	var d := Node3D.new()
	d.set_script(dummy)
	d.sled = sled
	main.add_child(d)
	sled.reset_to(Vector3(0, main.height(0, z0) + 0.3, z0))
	sled.rotation.y = PI
	sled.parked = false
	sled.mount(d)
	sled.linear_velocity = Vector3(0, 0, 6.0)
	var b = sb.button(ids[2])
	_look(b.at + Vector3(-4.5, 1.8, 1.0), b.at + Vector3(0.6, 0.6, 0.6), 50.0)
	while sled.global_position.z < b.at.z - 3.2:
		await process_frame
	var imgs: Array[Image] = []
	for i in 18:
		imgs.append(await _grab())
		await _wait_steps(1)
	_sheet(imgs, 6, 360)
	print("切った数: ", sb.stats.snip)


func _case_hud() -> void:
	var p = main.player
	if p == null:
		return
	if main.hud:
		main.hud.visible = true
	await _wait_frames(30)
	var at: Vector3 = p.cam.global_position - p.cam.global_basis.z * 6.0 + Vector3.UP * -1.0
	var imgs: Array[Image] = []
	var k := 0
	for n in [1, 10, 100, 1000]:
		main.craft.send({"kind": "earn", "who": p.id, "n": n, "at": at + Vector3(k - 1.5, 0, 0)})
		k += 1
		for i in 3:
			await _wait_frames(8)
			imgs.append(await _grab())
	_sheet(imgs, 4, 480)


func _case_tiers() -> void:
	sb.gust_override = 0.3
	for t in 4:
		sb.drop_at(Vector3(-1.5 + t * 1.0, 0, 14.0), 0, false, t)
	await _wait_steps(34 + 12 + 6)
	_look(_snow(0, 14) + Vector3(0.4, 1.6, -2.4), _snow(0, 14) + Vector3(0, 0.05, 0.2), 45.0)
	await _wait_steps(1)
	_save(await _grab(), "close")
	var imgs: Array[Image] = []
	_look(_snow(2, 40) + Vector3.UP * 1.6, _snow(0, 14) + Vector3.UP * 0.5, 60.0)
	for i in 6:
		await _wait_steps(3)
		imgs.append(await _grab())
	_save(imgs[0], "far")
	_sheet(imgs, 3)


func _case_shears() -> void:
	var p = main.player
	if p == null:
		return
	var id: int = sb.drop_at(Vector3(0, 0, 14.0), 0, false, 1)
	await _wait_steps(34 + 12 + 4)
	var b = sb.button(id)
	p.global_position = b.at + Vector3(0, 0.2, -1.3)
	p.rotation.y = PI
	p._pitch = -0.6
	if main.hud:
		main.hud.visible = true
	await _wait_frames(40)
	_save(await _grab(), "hint")
	if main.hud:
		main.hud.visible = false
	_look(b.at + Vector3(-2.6, 1.3, -0.4), b.at + Vector3(0, 0.55, -0.6), 45.0)
	sb.request_cut(p.id)
	p.busy_until = preload("res://doll.gd").frame_index() + 1 + sb.SHEAR_END
	var imgs: Array[Image] = []
	for i in 24:
		await _wait_steps(1)
		imgs.append(await _grab())
	_sheet(imgs, 6, 360)


func _case_ride() -> void:
	var p = main.player
	if p == null:
		return
	if main.hud:
		main.hud.visible = true
	var sled: RigidBody3D = main.sled
	var at := Vector3(0, main.height(0, 3.0) + 0.6, 3.0)
	sled.reset_to(at)
	sled.global_transform = Transform3D(Basis(Vector3.UP, PI), at)
	p.global_position = at + Vector3(1.2, 0.3, 0)
	p.get_on()
	p.rotation.y = PI
	p._pitch = -0.1
	sled.linear_velocity = Vector3(0, 0, 2.0)
	var paid := [false]
	sb.happened.connect(func(ev: Dictionary) -> void:
		if ev.kind == "ride_pay":
			paid[0] = true)
	var marked := false
	var imgs: Array[Image] = []
	while not paid[0]:
		await process_frame
		if main.settings and main.settings.is_open:
			main.settings.set_open(false)
			p.menu_open = false
		if not marked and sled.global_position.z > 22.0:
			marked = true   # 確かめのため: いちばん速い所を超えたことにして、真鍮を縫い込む
			sb.send({"kind": "ride_mark", "sled": String(sled.name), "speed": 10.0})
			await _wait_frames(6)
			imgs.append(await _grab())
	for i in 11:
		imgs.append(await _grab())
		await _wait_frames(5)
	_sheet(imgs, 4, 480)
