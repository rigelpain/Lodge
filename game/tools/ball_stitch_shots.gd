extends SceneTree
## 大玉の縫い目の柄（ball_stitches.gd・big_ball.gd）の絵。ふもとの雪の上に玉を止めて、同じ位置から撮る。
##   Godot --path game --resolution 960x540 -s res://tools/ball_stitch_shots.gd -- --dir=/path/out --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save
##   grades.jpg   毛糸・フェルト・革の手袋で固めた玉を並べて、少し離れて（一目で見分けられるか）
##   std_<段>.jpg 段ごとの標準の柄を、同じ位置から近くで
##   sheet.jpg    同じ位置から撮った近くの絵を並べた一覧（上の段が標準 3 つ、続けて売る柄を毛糸で、最後に菊かがりとクロスをフェルト・革で）
##   dent.jpg     へこんで縫い目がはじけた玉
##   shop.jpg     山師の売り場の雪玉の柄の棚（いくつか買ってある）
##   gear.jpg     持ち物の画面の雪玉の柄のページ（クロスを選んでいる）

const BS := preload("res://ball_stitches.gd")
const SPOT := Vector3(4.0, 0.0, 60.0)
const R := 0.8

var args := {}
var main: Node3D
var p: CharacterBody3D
var cam: Camera3D
var _next := 800


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _dir() -> String:
	return String(args.get("dir", "/tmp/ball_stitch"))


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	img.save_jpg(_dir().path_join(name), 0.9)
	print("撮った: ", _dir().path_join(name))


func _hud(on: bool) -> void:
	for c in main.get_children():
		if c is CanvasLayer:
			c.visible = on


## 玉を置く。手まりの柄（motif）は刺した 1 つ目の面（ball_stitches.gd の faces）を、縫い合わせに沿う柄は縫い合わせの 1 点を、向き look へ向ける
## （柄の種類と段ごとに同じ向き）
func _ball(at: Vector3, grade: String, look := Vector3.ZERO, motif := true) -> RigidBody3D:
	_next += 1
	var b: RigidBody3D = main.emotes._spawn_big({"ball": _next, "point": at, "r": R, "who": p.id})
	b.freeze = true
	b.pack = grade
	if look != Vector3.ZERO:
		var f: Vector3 = BS.faces(grade)[0][0] if motif else (BS.seams(grade)[0][0] as Vector3).lerp(BS.faces(grade)[0][0], 0.25).normalized()
		b.basis = Basis(Quaternion(f, look.normalized()))
	return b


func _clear() -> void:
	for b in root.get_tree().get_nodes_in_group("big_balls"):
		main.emotes.big_balls.erase(b.ball_id)
		b.queue_free()
	await process_frame


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, main.height(x, z), z)


func _run() -> void:
	await create_timer(1.5).timeout
	p = main.player
	var c = main.craft
	p.global_position = _ground(SPOT.x - 30.0, SPOT.z - 30.0) + Vector3.UP * 0.2   # 絵の外へ
	p.reset_physics_interpolation()
	cam = Camera3D.new()
	main.add_child(cam)
	cam.fov = 40
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4) | (1 << 7)
	cam.make_current()
	_hud(false)
	# 3 段を並べて、少し離れて
	var mid := _ground(SPOT.x, SPOT.z)
	var grades := ["gloves", "gloves_felt", "gloves_leather"]
	for i in 3:
		_ball(_ground(SPOT.x + (i - 1) * 2.1, SPOT.z), grades[i], Vector3(0.0, 0.5, 1.0), false)
	cam.global_position = mid + Vector3(0.0, 2.2, 6.2)
	cam.look_at(mid + Vector3(0, R, 0))
	await create_timer(0.6).timeout
	_save(await _grab(), "grades.jpg")
	await _clear()
	# 近くの絵: 同じ位置・同じ向きの玉を、同じカメラで
	var at := mid
	cam.global_position = at + Vector3(1.9, 1.9, 2.9)
	cam.look_at(at + Vector3(0, R, 0))
	var face := cam.global_position - (at + Vector3(0, R, 0)) + Vector3(-0.6, 0.3, 0.0)   # 面はカメラの少し左上へ（まわりの縫い合わせも見える）
	var shots := []   # [柄（"" は標準）, 段]
	for g in grades:
		shots.append(["", g])
	for nm in BS.for_sale():
		shots.append([nm, "gloves"])
	for nm in ["kiku", "cross"]:
		for g in ["gloves_felt", "gloves_leather"]:
			shots.append([nm, g])
	c.ball_owned[p.id] = BS.for_sale()
	var tiles: Array[Image] = []
	for s in shots:
		c.ball_stitch[p.id] = s[0]
		var nm: String = s[0] if s[0] != "" else BS.standard(s[1])
		var b := _ball(at, s[1], face, BS.LIST[nm].has("motif"))
		await create_timer(0.25).timeout
		var img := await _grab()
		if s[0] == "":
			_save(img, "std_%s.jpg" % s[1])
		print("  %s → %s（%d 目）" % [s, b._seam_key, b._seam.multimesh.instance_count])
		tiles.append(img)
		await _clear()
	_save(_sheet(tiles, 5), "sheet.jpg")
	# へこんで縫い目がはじけた玉
	c.ball_stitch[p.id] = "kiku"
	var bd := _ball(at, "gloves_felt", face)
	await process_frame
	var side := (cam.global_position - bd.global_position).normalized().cross(Vector3.UP).normalized()   # カメラから見て横へ向いた所をへこませる
	bd.show_hurt({"dir": (bd.global_basis.inverse() * (side + Vector3.UP * 0.3)).normalized(), "amt": 0.4, "k": 0.4})
	await create_timer(0.15).timeout
	_save(await _grab(), "dent.jpg")
	await _clear()
	# 山師の売り場と持ち物の画面
	cam.queue_free()
	p.cam.make_current()
	_hud(true)
	c.ball_owned[p.id] = ["back", "cross", "kiku"]
	c.ball_stitch[p.id] = "cross"
	c.wallets[p.id] = 320
	c.send({"kind": "gloves_own", "who": p.id, "grade": "gloves_felt"})
	c.send({"kind": "equip", "who": p.id, "gear": "gloves", "index": c.gloves_index(p.id, "gloves_felt")})
	main.mountain_ui.open()
	main.mountain_ui.set_page(2)
	main.mountain_ui.select(BS.for_sale().find("hoshi"))
	await create_timer(0.4).timeout
	_save(await _grab(), "shop.jpg")
	main.mountain_ui.close()
	await create_timer(0.3).timeout
	main.craft_ui.open_gear()
	main.craft_ui.tag_page = main.craft_ui.ball_page()
	await create_timer(0.4).timeout
	_save(await _grab(), "gear.jpg")
	main.craft_ui.close_gear()
	quit(0)


## 絵を cols 列に並べた一覧（1 枚を 4 分の 1 に縮める）
func _sheet(tiles: Array[Image], cols: int) -> Image:
	var tw := tiles[0].get_width() / 3
	var th := tiles[0].get_height() / 3
	var rows := ceili(float(tiles.size()) / cols)
	var out := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGB8)
	out.fill(Color(0.15, 0.15, 0.18))
	for i in tiles.size():
		var t := tiles[i]
		t.convert(Image.FORMAT_RGB8)
		# 玉のまわりだけ切り出す（まんなかの 4 分の 3）
		var cw := t.get_width() * 3 / 4
		var ch := t.get_height() * 3 / 4
		var cut := t.get_region(Rect2i((t.get_width() - cw) / 2, (t.get_height() - ch) / 2, cw, ch))
		cut.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(cut, Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
	return out
