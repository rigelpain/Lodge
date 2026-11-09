extends SceneTree
## 双眼鏡で寄ったとき、遠くの人のランタンの灯りが見えるかを撮って確かめる（lantern.gd の _fit_fade）。
## 夜に仲間を 1 列に遠くへ並べ、あなたはそちらを向いて手の双眼鏡でのぞく。いまの作りと、前の作り（画角によらず 40 m から消す）を撮り比べる。
##   Godot --path game --resolution 1280x720 -s res://tools/lantern_zoom_shots.gd -- --roam-bots=6 --time=21 --no-sound --no-pip --no-buttons --dir=/path/shots

const Main := preload("res://main.gd")
const FROM := Vector2(20.0, 0.0)     # あなたの立つ所 (x, z)。丘の頂のそばから、南の広場を見下ろす
const TOWARD := Vector2(0.0, 1.0)    # 見る向き（ロッジの東を通る）
const DISTS := [60.0, 90.0, 120.0, 150.0, 180.0, 210.0]   # 仲間を並べる距離 (m)

var args := {}
var main: Node3D
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/lantern_zoom_shots")


func _process(_dt: float) -> bool:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _check(what: String, ok: bool) -> void:
	print(("よい　　" if ok else "よくない") + "　" + what)
	if not ok:
		fails += 1


func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _bots() -> Array:
	return main.get_children().filter(func(c): return c.is_in_group("bots"))


## 見えている灯りの数（消す距離の内にある、点いたランタンの灯り）
func _lit_in_range(cam: Camera3D) -> int:
	var n := 0
	for b in _bots():
		var l: OmniLight3D = b.doll._lantern._light
		if l.visible and cam.global_position.distance_to(l.global_position) < l.distance_fade_begin + l.distance_fade_length:
			n += 1
	return n


func _run() -> void:
	var p: CharacterBody3D = main.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # のぞいているあいだは、つかんだままの印（player.gd の _update_peek）
	p.set_third(false)
	await create_timer(8.0).timeout   # 夜なので、仲間がランタンを点ける（bot.gd の _mind_lamp は 1.5〜4 秒ごとに見る）
	var bots := _bots()
	_check("仲間がいる", bots.size() >= DISTS.size())
	for i in DISTS.size():
		var b: Node3D = bots[i]
		b.set_physics_process(false)   # 仲間の考えを止め、並べた所に立たせる（人形とランタンは動く）
		var w: Vector2 = FROM + TOWARD * float(DISTS[i]) + Vector2(TOWARD.y, -TOWARD.x) * (float(i % 2) * 2.0 - 1.0) * 3.0
		b.global_position = Vector3(w.x, Main.ground(w.x, w.y) + 0.05, w.y)
		b.doll.lantern = "box"
		b.doll.lantern_lit = true
	for b in bots.slice(DISTS.size()):
		b.global_position = Vector3(400, Main.ground(400, 400), 400)
	p.global_position = Vector3(FROM.x, Main.ground(FROM.x, FROM.y) + 0.1, FROM.y)
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-TOWARD.x, -TOWARD.y)
	p._pitch = -0.1
	await create_timer(1.5).timeout
	await _save("00_eye")
	var cam: Camera3D = p.cam
	_check("ふつうの画角では、40 m より先の灯りは消えている", _lit_in_range(cam) == 0)
	# 手の双眼鏡（24°）でのぞく
	var craft = main.craft
	craft.wallets[p.id] = 40
	craft.send({"kind": "buy", "who": p.id, "item": preload("res://binoculars.gd").ITEM.duplicate()})
	await create_timer(0.3).timeout
	_check("双眼鏡を手に持つ", p.held().get("kind", "") == "binoculars")
	p._peek_begin("hand", null)
	await create_timer(1.5).timeout
	await _save("01_peek_now")
	var n24 := _lit_in_range(cam)
	_check("双眼鏡（24°）で 120 m までの灯りが見える（%d 個）" % n24, n24 >= 3)
	# 遠見の双眼鏡の寄りきり（6.5°）
	p._peek_fov["binoculars"] = 6.5
	await create_timer(1.5).timeout
	print("画角 %.1f°" % cam.fov)
	await _save("02_peek_far_now")
	var n6 := _lit_in_range(cam)
	_check("寄りきると 210 m の灯りも見える（%d 個）" % n6, n6 == DISTS.size())
	# 前の作り: 画角によらず 40 m から消す
	for b in bots.slice(0, DISTS.size()):
		var lt = b.doll._lantern
		lt._fade_k = cam.fov / 75.0   # _fit_fade が戻さないように
		lt._light.distance_fade_begin = lt.FAR
		lt._light.distance_fade_length = lt.FAR_LEN
	await create_timer(0.5).timeout
	await _save("03_peek_far_before")
	p.peek_stop()
	await create_timer(1.5).timeout
	var back: float = bots[0].doll._lantern.FAR / clampf(cam.fov / 75.0, 0.02, 1.0)
	_check("のぞくのをやめると、灯りの消える距離が戻る（%.0f m）" % back, bots.slice(0, DISTS.size()).all(func(b): return absf(b.doll._lantern._light.distance_fade_begin - back) < 1.0))
	print("よくない %d" % fails)
	quit()
