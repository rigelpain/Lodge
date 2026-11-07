extends SceneTree
## 白い息を撮る（確かめ用）。ふだんの息・声の息・B の長い息を、吐きはじめから何度か撮る。
##   Godot --path game --resolution 960x540 -s res://tools/breath_shots.gd -- --dir=/path [--view=fp|tp|side] [--tag=before]
##        [--only=normal,voice,long] [--time=10] [--place=foot|summit|inside|fire] [--when=0.4,0.9,1.6]
## --place: 立つ場所（ふもと・丘の頂上・ロッジの中・暖炉のそば）。--time=23 で夜
## --move=out|in: ロッジの中から外へ（out）、外から中へ（in）出ながら B で長く吐き、息が気温になじむ様子を撮る
## fp 一人称（右下の小窓も写る）、tp 三人称（C）、side 顔の横から（煙の形がいちばん分かる）。
## あなたは横を向いて立ち、仲間が 2 m 先でこちらを向く。名前は 息_視点_タグ_秒.png（秒は吐きはじめから）
## --fps: 撮らずに、仲間 2 人とあなたが B で 10 秒息を吐き続けるあいだの fps の平均と最低を出す
## --only=b: あなただけ B で吐く（仲間は吐かない）。--only=b_bot: 仲間が B で吐くのを、あなたの目で見る（配り役を通す。相手の画面と同じ道）
## --view=other: 離れた所から（息の全体を入れる。ほかの人の目）
## --measure[=秒]: 撮らずに、B を押している秒（ふつう 3 秒）とそのあとの、粒の届いた高さ・前への伸び・消えるまでの時間と、
##   絵で見える高さ（--view=other）や画面をふさぐ割合（--view=fp）を出す。絵は同じ瞬間に息だけ消した絵と比べる

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
	if args.get("only", "") in ["b", "b_bot"] or args.has("measure"):
		for c in root.find_children("*", "CanvasLayer", true, false):
			c.visible = false   # B の息の絵と測りには、画面の飾りも入れない（画面の割合が正しく出るよう）
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
	if args.has("measure"):
		await _measure()
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
		var when: Array = Array(args["when"].split(",")).map(func(x): return float(x)) if args.has("when") else WHEN
		for w in when:
			while (Time.get_ticks_msec() - t0) / 1000.0 < w:
				await process_frame
			if main.settings:
				main.settings.set_open(false)   # 窓が隠れると設定の画面が開くことがある。写さない
			_camera(view)
			RenderingServer.force_draw()
			var path := dir.path_join("%s_%s_%s_%.1f.png" % [kind, view, args.get("tag", "now"), w])
			root.get_texture().get_image().save_png(path)
			var tn := root.get_node_or_null("Temperature")
			print("保存: ", path.get_file(), "  身ぶり=", p.doll.emote_now(), " B の息=", p.doll._streams.get("exhale", p.doll._long).emitting, " 気温=%.1f 見え方=%.2f" % [tn.at(p.doll._long.global_position) if tn else 0.0, p.doll.get("_cold") if p.doll.get("_cold") != null else -1.0], " 口=", p.doll._long.global_position.snapped(Vector3(0.1, 0.1, 0.1)))
		_key(KEY_B, false)
		await _frames(200)   # 息が消えるまで
	quit()


## あなたは横（+x）を向いて立ち、仲間は 2 m 先（あなたの前）でこちらを向く。ロッジの中なら、その場で
func _stage(place := "") -> void:
	if place == "":
		place = args.get("place", "foot")
	p.global_position = _place_pos(place)
	p.rotation.y = _yaw(place)
	p._pitch = float(args.get("pitch", -0.05))   # --pitch=0.6 で見上げる
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
		"b":
			_key(KEY_B, true)   # あなただけ
		"b_bot":
			for b in _bots():
				main.emotes.send({"kind": "breath", "who": b.id})   # 仲間が B で吐く（配り役を通す）
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
		"other":
			# 離れた所から: 息の出口の真横 7 m。口より 1.4 m 上を画面のまんなかに（fov 40 で上下 2.5 m ほど入る）
			var out: Node3D = p.doll._streams["small"]
			var mouth: Vector3 = out.global_position
			var fwd: Vector3 = out.global_basis * Vector3(0, 0, -1)
			fwd.y = 0
			fwd = fwd.normalized()
			var side := fwd.cross(Vector3.UP)
			cam.look_at_from_position(mouth + side * 7.0 + fwd * 0.6 + Vector3.UP * 0.2, mouth + fwd * 0.6 + Vector3.UP * 1.4)
			cam.current = true
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


## 3 人が B で 10 秒、吐き続けるあいだの fps（--disable-vsync で測る）
func _fps() -> void:
	await _stage()
	p.set_third(false)
	p.cam.current = true
	_key(KEY_B, true)
	for b in _bots():
		main.emotes.send({"kind": "breath", "who": b.id})   # 仲間も B で吐く（離さないので吐き続ける）
	await _frames(240)   # 煙が出そろうのを待つ
	var samples := []
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < 10000:
		Engine.max_fps = 0   # main.gd が窓の出入りで戻すので、毎コマ
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


## B の息を数字で出す。粒の所は粒の表（multimesh。座標・濃さ）から、絵の違いは同じ瞬間に息を消した絵と比べて
func _measure() -> void:
	await _stage()
	if main.settings:
		main.settings.set_open(false)
	p.menu_open = false
	var view: String = args.get("view", "other")
	var hold := float(args["measure"]) if args["measure"] != "1" else 3.0
	var e: CPUParticles3D = p.doll._streams.get("exhale", p.doll._long)
	_camera(view)
	await process_frame
	await process_frame
	var mouth: Vector3 = e.global_position
	var fwd: Vector3 = e.global_basis * Vector3(0, 0, -1)
	fwd.y = 0
	fwd = fwd.normalized()
	print("B の息: 粒の数=%d 寿命=%.2f 出口の高さ=%.2f 見え方=%.2f" % [e.amount, e.lifetime, mouth.y, p.doll._cold])
	var t0 := Time.get_ticks_msec()
	_key(KEY_B, true)
	var released := false
	var next := 0.5
	var last := 0.0
	var most := {"top": 0.0, "seen": 0.0, "reach": 0.0, "size": 0.0, "n": 0}
	while true:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if not released and t >= hold:
			_key(KEY_B, false)
			released = true
		var m := _particles(e, mouth, fwd)
		if e.capture_aabb().size != Vector3.ZERO:
			last = t
		for k in most:
			most[k] = maxf(most[k], m[k])
		if t >= next:
			next += 0.5
			_camera(view)
			if main.settings:
				main.settings.set_open(false)
			var r := _with_without(e)
			print("  %.1f 秒  粒=%2d  上端=%.2f m  見える上端=%.2f m  前=%.2f m  いちばん大きい粒=%.2f m  | 絵: 変わった割合=%.0f%% まんなか=%.0f%% 濃くふさぐ=%.0f%%  絵で見える高さ=%.2f m" % [t, m.n, m.top, m.seen, m.reach, m.size, r[0] * 100.0, r[1] * 100.0, r[2] * 100.0, _row_height(int(r[3]), mouth)])
		if released and (t > last + 0.3 or t > hold + 12.0):
			break
		await process_frame
	print("いちばん: 上端=%.2f m、見える上端（濃さ 1 割以上）=%.2f m、前への伸び=%.2f m、粒の幅=%.2f m、同時の粒=%d、離してから消えるまで=%.1f 秒（押した %.1f 秒）" % [most.top, most.seen, most.reach, most.size, most.n, last - hold, hold])


## 粒の表から: 生きている粒の数、中心の上端、濃さ 1 割以上の粒の上端、前への伸び（どれも口から）、いちばん大きい粒の幅
func _particles(e: CPUParticles3D, mouth: Vector3, fwd: Vector3) -> Dictionary:
	var b := RenderingServer.multimesh_get_buffer(e.get_base())
	var out := {"n": 0, "top": 0.0, "seen": 0.0, "reach": 0.0, "size": 0.0}
	var q: Vector2 = (e.mesh as QuadMesh).size
	for i in range(0, b.size(), 20):   # 姿勢 12・色 4・カスタム 4
		var a := b[i + 15]
		var sx := Vector3(b[i], b[i + 4], b[i + 8]).length()
		if sx <= 0.0 or a <= 0.0:
			continue
		var pos: Vector3 = e.global_transform * Vector3(b[i + 3], b[i + 7], b[i + 11])   # 表の座標は出口から
		out.n += 1
		out.top = maxf(out.top, pos.y - mouth.y)
		out.reach = maxf(out.reach, (pos - mouth).dot(fwd))
		out.size = maxf(out.size, sx * q.x)
		if a >= 0.1:
			out.seen = maxf(out.seen, pos.y - mouth.y)
	return out


## 同じ瞬間の、息ありと息なしの絵の違い: [変わった割合, まんなか（縦横の中央 5 割）の割合, 濃くふさぐ割合, 変わった所のいちばん上の行]
func _with_without(e: CPUParticles3D) -> Array:
	RenderingServer.force_draw()
	var a := root.get_texture().get_image()
	e.visible = false
	RenderingServer.force_draw()
	var b := root.get_texture().get_image()
	e.visible = true
	var w := a.get_width()
	var h := a.get_height()
	var n := 0
	var hit := 0
	var cn := 0
	var chit := 0
	var thick := 0
	var top := h
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var d := absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			var center: bool = x > w / 4 and x < w * 3 / 4 and y > h / 4 and y < h * 3 / 4
			n += 1
			cn += 1 if center else 0
			if d > 0.1:
				hit += 1
				chit += 1 if center else 0
				top = mini(top, y)
			if d > 0.6:
				thick += 1
	return [float(hit) / n, float(chit) / maxi(cn, 1), float(thick) / n, top]


## 画面の行を、口を通るカメラに正対した面の上の高さ（口から）に直す
func _row_height(row: int, mouth: Vector3) -> float:
	var c := root.get_camera_3d()
	var w := root.get_texture().get_width()
	var o := c.project_ray_origin(Vector2(w * 0.5, row))
	var d := c.project_ray_normal(Vector2(w * 0.5, row))
	var n := -c.global_basis.z
	n.y = 0
	n = n.normalized()
	var k := (mouth - o).dot(n) / d.dot(n)
	return (o + d * k).y - mouth.y
