extends SceneTree
## 滑りあとが消えていく様子（ほつれる・雪に埋もれる）と、ソリのメインカラーの確かめ用。
##   Godot --path game --resolution 1280x720 -s res://tools/trail_fade_shot.gd -- --bots=0 --no-sound --sled=mid [--riders=3] [--sled-color=2F5DA8] --out=/path/fade [--at=0,30,60] [--slide=5]
## --stitch=・--trail-fade=・--sled-color= は main.gd と同じ。頂上の少し下にソリを置き、あなたを乗せて W（前傾）で slide 秒滑らせて止める。--riders=N なら、あなたのほかに
## 見えない人を N-1 人乗せたことにする（重さだけ）。止めたあと、滑りあとの時計を --at の秒（止めてからの秒）へ進めて、
## <out>_<秒>_far.png（跡全体とソリ）と <out>_<秒>_near.png（跡の 1 m ほど）を書く。
## 時計ごとに、まだ見えている目の割合と、消えかけの目の割合を出す。
##   --fill  止めたあと、残せる目（TRAIL_N × 縫い目の per）をすべて見えている目で埋め、跡全体を見たまま、跡なしとくらべた三角の数とコマの時間を出す（重さの確かめ）
##   --table だけなら、絵を撮らずに、大きさと乗る人の数ごとの「消えるまでの時間のまんなか」の表を出して終わる

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var phase := 0
var _ft := PackedFloat32Array()
var _ft_base := PackedFloat32Array()
var _prims := Vector2i()
var _shot_t := 0.0
var _stop_time := 0.0          # 止めたときの滑りあとの時計
var _ats: Array[float] = []
var _at_i := 0
var _near := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("table"):
		_print_table()
		quit()
		return
	for s in str(args.get("at", "0")).split(","):
		_ats.append(float(s))
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 50
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)


func _print_table() -> void:
	var Sled: GDScript = load("res://sled.gd")
	print("消えるまでの時間のまんなか (s)。目ごとに ±%d%%（吹きだまり）±%d%%（目ひとつずつ）ずれる" % [Sled.TRAIL_PATCH * 100, Sled.TRAIL_SCATTER * 100])
	for kind in ["sack", "small", "mid", "large"]:
		var row := "%-6s" % kind
		var seats: int = Sled.KINDS[kind].seats.size()
		for n in seats + 1:
			var m: float = maxf(Sled.KINDS[kind].mass + n * Sled.RIDER_MASS, 1.0)
			var life: float = clampf(Sled.TRAIL_LIFE * pow(m / Sled.TRAIL_LIFE_MASS, Sled.TRAIL_LIFE_POW), Sled.TRAIL_LIFE_RANGE.x, Sled.TRAIL_LIFE_RANGE.y)
			row += "  %d人 %4.0f kg → %3.0f s" % [n, m, life]
		print(row)


## 止めてからの時計 at 秒で、まだ見えている目（消えきっていない）と、消えかけの目の割合
func _count(sled: RigidBody3D) -> String:
	var n := 0
	var alive := 0
	var burying := 0
	for i in sled._trail_used:
		var c: Color = sled._trails[i / sled._trail_chunk].multimesh.get_instance_custom_data(i % sled._trail_chunk)
		if c.a < -0.5:
			continue
		n += 1
		var b: float = (sled._trail_now - c.a) / maxf(c.b, 0.01)
		if b < 1.0:
			alive += 1
			if b > 0.0:
				burying += 1
	return "目 %d のうち 見えている %d%%（うち消えかけ %d%%）" % [n, 100 * alive / maxi(n, 1), 100 * burying / maxi(n, 1)]


func _stats(ft: PackedFloat32Array) -> String:
	ft.sort()
	var sum := 0.0
	for f in ft:
		sum += f
	return "%d コマ 平均 %.1f ms（%.0f fps）中央 %.1f ms 最長 %.1f ms" % [ft.size(), 1000.0 * sum / ft.size(), ft.size() / sum, 1000.0 * ft[ft.size() / 2], 1000.0 * ft[-1]]


## 残せる目をすべて、いまの跡を横に並べ写した見えている目で埋める（重さの確かめ用）
func _fill(sled: RigidBody3D) -> void:
	var n: int = sled._trail_used
	var side: Vector3 = sled.global_basis.x
	var ch: int = sled._trail_chunk
	for i in range(n, sled._trail_n):
		var src := i % n
		var smm: MultiMesh = sled._trails[src / ch].multimesh
		var tr := smm.get_instance_transform(src % ch)
		var row := i / n
		tr.origin += side * (row * 1.2 * (1 if row % 2 == 0 else -1))
		tr.origin.y = main.height(tr.origin.x, tr.origin.z) + 0.012
		var chunk: MultiMeshInstance3D = sled._trails[i / ch]
		chunk.multimesh.visible_instance_count = chunk.multimesh.instance_count
		chunk.multimesh.set_instance_transform(i % ch, tr)
		chunk.multimesh.set_instance_custom_data(i % ch, smm.get_instance_custom_data(src % ch))
		chunk.visible = true
		sled._chunk_end[i / ch] = 1e9   # 埋めた塊を、sled が描くのをやめないように
	sled._trail_used = sled._trail_n


func _process(dt: float) -> bool:
	t += dt
	if main == null:
		return true
	var sled: RigidBody3D = main.sled
	var p = main.player
	if sled == null or p == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if main._pip_layer:
		main._pip_layer.visible = false
	var slide := float(args.get("slide", "5"))
	if phase == 0 and t > 0.6:
		# 頂上の東 4 m に、+x（下り）を向けて置き、乗せて前傾で滑らせる
		var at := Vector3(4.0, 0, 0)
		at.y = main.height(at.x, at.z) + 0.6
		sled.reset_to(at)
		sled.rotation.y = -PI / 2   # -z が前なので、+x を向く
		p.global_position = at + Vector3.UP * 0.5
		p.get_on()
		var ghost_src := GDScript.new()   # 見えない人（重さだけ。HUD が読む side だけ持つ）
		ghost_src.source_code = "extends Node3D\nvar side := 1\n"
		ghost_src.reload()
		for i in str(args.get("riders", "1")).to_int() - 1:
			var ghost := Node3D.new()
			ghost.set_script(ghost_src)
			main.add_child(ghost)
			sled.riders.append(ghost)
		print("ソリ=%s 縫い目=%s 消え方=%s 色=%s 重さ（乗る人こみ）=%.0f kg 消えるまでのまんなか=%.0f s" % [sled.kind, sled.stitch_kind(), sled.trail_fade, sled.color().to_html(false), sled.load_mass(), sled.trail_life()])
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		phase = 1
		_shot_t = t
	elif phase == 1:
		_ft.append(dt)
		var fwd: Vector3 = -sled.global_basis.z
		cam.global_position = sled.global_position - fwd * 6.0 + Vector3.UP * 3.0
		cam.look_at(sled.global_position, Vector3.UP)
		cam.current = true
		if t - _shot_t > slide:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_W
			ev.pressed = false
			Input.parse_input_event(ev)
			sled.freeze = true
			_ft.sort()
			var sum := 0.0
			for f in _ft:
				sum += f
			print("滑った %.1f 秒: 平均 %.1f ms（%.0f fps）最長 %.1f ms" % [slide, 1000.0 * sum / _ft.size(), _ft.size() / sum, 1000.0 * _ft[-1]])
			_stop_time = sled._trail_now
			phase = 2
			_shot_t = t
			if args.has("fill"):
				_fill(sled)
				phase = 3
				_ft.clear()
	elif phase == 3:
		# 重さの確かめ: 跡の横から、埋めた目を全部見る
		var back: Vector3 = sled.global_basis.z
		back.y = 0
		var focus: Vector3 = sled.global_position + back.normalized() * 8.0
		cam.global_position = focus + back.normalized().cross(Vector3.UP) * 9.0 + Vector3.UP * 6.0
		cam.look_at(focus, Vector3.UP)
		cam.current = true
		# 跡を隠す（くらべる元）と全部見せるを 0.5 秒ごとに入れかえ、20 秒ぶん比べる（ほかのアプリの重さのゆれを両方に均す）
		var k := int((t - _shot_t) / 0.5)
		var show := k % 2 == 1
		for c in sled._trails:
			c.visible = show
		if fmod(t - _shot_t, 0.5) > 0.1 and k >= 1 and k % 2 == int(show):
			var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			if show:
				_ft.append(dt)
				_prims.y = prims
			else:
				_ft_base.append(dt)
				_prims.x = prims
		if t - _shot_t > float(args.get("fill", "20")) + 0.75:   # 跡を見せているコマで撮る
			print("跡なし: 三角 %d  %s" % [_prims.x, _stats(_ft_base)])
			print("目 %d を描いて: 三角 %d（+%d）  %s" % [sled._trail_used, _prims.y, _prims.y - _prims.x, _stats(_ft)])
			var out: String = args.get("out", "/tmp/fade")
			root.get_texture().get_image().save_png(out + "_fill.png")
			quit()
	elif phase == 2:
		sled._trail_now = _stop_time + _ats[_at_i]
		var back: Vector3 = sled.global_basis.z
		back.y = 0
		back = back.normalized()
		var side := back.cross(Vector3.UP).normalized()
		var focus: Vector3
		var eye: Vector3
		if _near:   # 跡から 1 m、目の高さ 0.8 m
			focus = sled.global_position + back * 6.0
			focus.y = main.height(focus.x, focus.z)
			eye = focus + back * 0.9 + side * 0.35
			eye.y = main.height(eye.x, eye.z) + 0.8
			cam.global_position = eye
			cam.look_at(focus - back * 0.15, Vector3.UP)
		else:       # 跡の横、少し上から、ソリと跡全体
			focus = sled.global_position + back * 8.0
			focus.y = main.height(focus.x, focus.z)
			eye = focus + side * 7.0 + back * 2.0
			eye.y = main.height(eye.x, eye.z) + 5.0
			cam.global_position = eye
			cam.look_at(focus, Vector3.UP)
		cam.current = true
		if t - _shot_t > 0.6:
			var out: String = args.get("out", "/tmp/fade")
			var name := "%s_%03d_%s.png" % [out, int(_ats[_at_i]), "near" if _near else "far"]
			root.get_texture().get_image().save_png(name)
			if not _near:
				print("止めて %3.0f 秒: %s" % [_ats[_at_i], _count(sled)])
			print("保存: ", name)
			_shot_t = t
			_near = not _near
			if not _near:
				_at_i += 1
				if _at_i >= _ats.size():
					quit()
	return false
