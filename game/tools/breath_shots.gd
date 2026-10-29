extends SceneTree
## 白い息を撮る（確かめ用）。ふだんの息・声の息・B の長い息を、吐きはじめから何度か撮る。
##   Godot --path game --resolution 960x540 -s res://tools/breath_shots.gd -- --dir=/path [--view=fp|tp|side] [--tag=before]
##        [--only=normal,voice,long] [--time=10] [--place=foot|summit|inside|fire]
## --place: 立つ場所（ふもと・丘の頂上・ロッジの中・暖炉のそば）。--time=23 で夜
## --move=out|in: ロッジの中から外へ（out）、外から中へ（in）出ながら B で長く吐き、息が気温になじむ様子を撮る
## fp 一人称（右下の小窓も写る）、tp 三人称（C）、side 顔の横から（煙の形がいちばん分かる）。
## あなたは横を向いて立ち、仲間が 2 m 先でこちらを向く。名前は 息_視点_タグ_秒.png（秒は吐きはじめから）
## --fps: 撮らずに、仲間 2 人とあなたが 10 秒息を吐き続けるあいだの fps の平均と最低を出す

const Doll := preload("res://doll.gd")
const Audio := preload("res://audio.gd")
const Temperature := preload("res://temperature.gd")
const MOVE_WHEN := [0.6, 1.2, 2.0, 3.0, 4.2]   # 出入りしてから撮る秒
const WHEN := [0.4, 0.9, 1.6]   # 吐きはじめから撮る秒

var args := {}
var main: Node3D
var cam: Camera3D
var p: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 40
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _key(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)


func _bots() -> Array:
	return main.get_children().filter(func(c): return c != p and c.get("doll") != null and c.has_method("get_off"))


func _run() -> void:
	await _frames(30)
	p = main.player
	if main.settings:
		main.settings.set_open(false)
	if main.get("hud") != null:
		main.hud.visible = false   # 画面の案内は写さない（右下の小窓は写す）
	for b in _bots():
		b.set_physics_process(false)
	if args.has("fps"):
		await _fps()
		quit()
		return
	if args.has("move"):
		await _move()
		quit()
		return
	var view: String = args.get("view", "fp")
	var dir: String = args.get("dir", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var only: Array = args["only"].split(",") if args.has("only") else ["normal", "voice", "long"]
	for kind in only:
		await _stage()
		var t0 := Time.get_ticks_msec()
		_camera(view)
		await process_frame
		await process_frame
		_start(kind)
		for w in WHEN:
			while (Time.get_ticks_msec() - t0) / 1000.0 < w:
				await process_frame
			if main.settings:
				main.settings.set_open(false)   # 窓が隠れると設定の画面が開くことがある。写さない
			_camera(view)
			RenderingServer.force_draw()
			var path := dir.path_join("%s_%s_%s_%.1f.png" % [kind, view, args.get("tag", "now"), w])
			root.get_texture().get_image().save_png(path)
			var tn := root.get_node_or_null("Temperature")
			print("保存: ", path.get_file(), "  身ぶり=", p.doll.emote_now(), " 長い息=", p.doll._long.emitting, " 気温=%.1f 見え方=%.2f" % [tn.at(p.doll._long.global_position) if tn else 0.0, p.doll.get("_cold") if p.doll.get("_cold") != null else -1.0], " 口=", p.doll._long.global_position.snapped(Vector3(0.1, 0.1, 0.1)))
		_key(KEY_B, false)
		await _frames(200)   # 息が消えるまで
	quit()


## あなたは横（+x）を向いて立ち、仲間は 2 m 先（あなたの前）でこちらを向く。ロッジの中なら、その場で
func _stage(place := "") -> void:
	if place == "":
		place = args.get("place", "foot")
	p.global_position = _place_pos(place)
	p.rotation.y = _yaw(place)
	p._pitch = -0.05
	p.velocity = Vector3.ZERO
	var fwd: Vector3 = -p.global_basis.z
	var bots := _bots()
	for i in bots.size():
		var b: Node3D = bots[i]
		var bp: Vector3 = p.global_position + fwd * 2.2 + p.global_basis.x * (0.9 * (i * 2 - 1))
		if place == "foot" or place == "summit" or place == "door":
			bp.y = main.height(bp.x, bp.z)
		b.global_position = bp
		b.look_at(Vector3(p.global_position.x, bp.y, p.global_position.z), Vector3.UP)
		b.doll.act = Doll.Act.WALK
		b.doll.gaze = p.global_position + Vector3.UP * 1.2
	# ふだんの息が勝手に出ないよう、しばらく先へ
	for d in [p.doll] + bots.map(func(b): return b.doll):
		d._next_breath = d._frame + 600
	await _frames(60)
	# 寒さがその場になじむまで待つ（なじむのに数秒かかる作り）
	for i in 900:
		if absf(p.doll._cold - p.doll._cold_want) < 0.01:
			break
		await physics_frame


## 向き。ふもとと戸口では、カメラが丘と反対（空のほう）を向くように: 白い息は雪を背にするとほとんど見えない
func _yaw(place: String) -> float:
	if place == "foot" or place == "door":
		var d := Vector2(p.global_position.x - 1.5, p.global_position.z).normalized()   # 丘の頂上（1.5, 0）から
		return atan2(d.y, -d.x)
	return -PI / 2.0


## 立つ場所（世界）。ロッジの中は床の上
func _place_pos(place: String) -> Vector3:
	var lodge: Node3D = main.get_node_or_null("Lodge")
	match place:
		"summit":
			return Vector3(1.5, main.height(1.5, 0.0) + 0.05, 0.0)
		"inside":
			return lodge.to_global(Vector3(0.0, 0.05, 4.0))
		"fire":
			return lodge.to_global(Temperature.FIRE_FALLBACK + Vector3(1.6, -0.95, 1.6))
		"door":
			var d: Vector3 = lodge.to_global(Audio.VEST + Vector3(0, 0, 7.0))
			return Vector3(d.x, main.height(d.x, d.z) + 0.05, d.z)
	var base := Vector3(6.0, 0, 30.0)
	return Vector3(base.x, main.height(base.x, base.z) + 0.05, base.z)


## ロッジの出入り: 片方で寒さがなじむまで待ち、B で吐きはじめてから、もう片方へ移る。移ってから何度か撮る
func _move() -> void:
	var out: bool = args["move"] == "out"
	var dir: String = args.get("dir", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	await _stage("inside" if out else "door")
	if main.settings:
		main.settings.set_open(false)
	p.menu_open = false
	_key(KEY_B, true)
	await _frames(12)
	var to := _place_pos("door" if out else "inside")
	p.global_position = to
	p.rotation.y = _yaw("door" if out else "inside")
	var t0 := Time.get_ticks_msec()
	await _frames(8)   # 体と頭（姿勢は 12 fps）が移ってから、カメラを先に替えておく（最初の一枚が、移る前の向きで写らないよう）
	_camera(args.get("view", "side"))
	for w in MOVE_WHEN:
		while (Time.get_ticks_msec() - t0) / 1000.0 < w:
			await process_frame
		if main.settings:
			main.settings.set_open(false)
		if p.doll.emote.is_empty() and w < 4.0:
			_key(KEY_B, false)   # 息が 5 秒で切れたら、吐き直す
			await process_frame
			_key(KEY_B, true)
		_camera(args.get("view", "side"))
		RenderingServer.force_draw()
		var path := dir.path_join("move_%s_%s_%.1f.png" % [args["move"], args.get("view", "side"), w])
		root.get_texture().get_image().save_png(path)
		print("保存: ", path, "  気温=%.1f 見え方の目標=%.2f いま=%.2f" % [root.get_node("Temperature").at(p.doll._long.global_position), p.doll._cold_want, p.doll._cold])
	_key(KEY_B, false)


func _start(kind: String) -> void:
	# 窓が隠れると設定の画面が開き、そのあいだは身ぶりが出せない。閉じてから吐く
	if main.settings:
		main.settings.set_open(false)
	p.menu_open = false
	var dolls := [p.doll] + _bots().map(func(b): return b.doll)
	match kind:
		"normal":
			for d in dolls:
				d._next_breath = d._frame   # 次のコマで、ふだんの息
		"voice":
			for who in [p] + _bots():
				main.emotes.send({"kind": "un", "who": who.id})
		"long":
			_key(KEY_B, true)   # あなたは B で長く吐く（押したまま）
			for b in _bots():
				main.emotes.send({"kind": "oi", "who": b.id})   # 仲間はおーいの長い息


func _camera(view: String) -> void:
	match view:
		"fp", "tp":
			p.set_third(view == "tp")
			p._place_camera(1.0, 0.0, false)
			p.cam.current = true
		_:
			# 顔の横から: 息が流れていく向き（あなたの前）と直角に
			# 息の出口の真横から、口の高さで（上からだと笠に隠れる）。出口の向きは、出口の節点（頭の骨に付いている）から
			var out: Node3D = p.doll._streams["small"] if p.doll.get("_streams") else p.doll._breaths[0]
			var mouth: Vector3 = out.global_position
			var fwd: Vector3 = out.global_basis * Vector3(0, 0, -1)
			fwd.y = 0
			fwd = fwd.normalized()
			var side := fwd.cross(Vector3.UP)
			cam.look_at_from_position(mouth + side * 3.0 + fwd * 0.9 - Vector3.UP * 0.05, mouth + fwd * 0.9)
			cam.current = true


## 3 人が 10 秒、吐き続けるあいだの fps
func _fps() -> void:
	await _stage()
	p.set_third(false)
	p.cam.current = true
	_key(KEY_B, true)
	var samples := []
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < 10000:
		for b in _bots():
			if b.doll.emote.is_empty():
				main.emotes.send({"kind": "oi", "who": b.id})
		if p.doll.emote.is_empty():
			_key(KEY_B, false)
			await process_frame
			_key(KEY_B, true)
		await process_frame
		samples.append(Engine.get_frames_per_second())
	_key(KEY_B, false)
	samples = samples.slice(60)
	var s := 0.0
	for x in samples:
		s += x
	print("fps 平均=%.1f 最低=%d（%d コマ）" % [s / samples.size(), samples.min(), samples.size()])
