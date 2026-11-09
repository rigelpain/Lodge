extends SceneTree
## 大玉の縫い目の重さを測る。置ける上限（big_ball.gd の MAX_BALLS）の大玉を目の前に並べ、縦同期を切って、
## 縫い目なし・前の作り（なみ縫いの箱 28 個を別々に描く）・今回の柄（いちばん目の多い柄）を交互に測り、1 コマの時間の中央値と描く回数を出す
## （Mac の熱や窓の裏回りで全体が遅くなる回があるので、平均ではなく中央値で比べる）。
##   Godot --path game --resolution 1280x720 -s res://tools/ball_stitch_fps.gd -- --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-save [--per=3] [--rounds=3]

const BS := preload("res://ball_stitches.gd")
const BigBall := preload("res://big_ball.gd")
const SPOT := Vector3(4.0, 0.0, 60.0)

var args := {}
var main: Node3D
var balls: Array = []
var olds: Array = []   # 前の作りの箱（玉ごと）


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _process(_dt: float) -> bool:
	Engine.max_fps = 0   # 窓が裏に回ると main.gd が 15 fps に絞るので、測るあいだは外す
	if main and main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


## 前の作り: なみ縫いの箱 28 個（2 本の輪の半分ずつ）を、玉の見た目に別々に足す
func _old_seam(b: RigidBody3D) -> Array:
	var thread := preload("res://look.gd").felt(Color("6F86A3"), 2.0)
	var dash := BoxMesh.new()
	dash.size = Vector3(0.14, 0.05, 0.05)
	var out := []
	for i in 28:
		var a := TAU * i / 28
		var m := MeshInstance3D.new()
		m.mesh = dash
		m.material_override = thread
		if i % 2 == 0:
			m.position = Vector3(cos(a), 0.0, sin(a)) * 1.005
			m.rotation = Vector3(0.0, -a - PI * 0.5, 0.0)
		else:
			m.position = Basis(Vector3.UP, 1.1) * (Vector3(cos(a), sin(a), 0.0) * 1.005)
			m.basis = Basis(Vector3.UP, 1.1) * Basis(Vector3.BACK, a + PI * 0.5)
		b._look.add_child(m)
		out.append(m)
	return out


func _show(mode: String) -> void:
	for i in balls.size():
		balls[i]._seam.visible = mode == "new"
		for m in olds[i]:
			m.visible = mode == "old"


func _measure(sec: float) -> Array:
	await create_timer(0.5).timeout
	var t0 := Time.get_ticks_usec()
	var n := 0
	var draws := 0
	while Time.get_ticks_usec() - t0 < sec * 1000000.0:
		await process_frame
		n += 1
		draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	return [(Time.get_ticks_usec() - t0) / 1000.0 / n, draws]


func _run() -> void:
	await create_timer(1.5).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var p = main.player
	var c = main.craft
	var heavy := ""
	var most := 0
	for g in BS.STANDARD:
		for nm in BS.LIST:
			var k: int = BS.segments(nm, g).size()
			if k > most:
				most = k
				heavy = nm + ":" + g
	c.ball_owned[p.id] = BS.for_sale()
	c.ball_stitch[p.id] = heavy.get_slice(":", 0)
	for i in BigBall.MAX_BALLS:
		var x := SPOT.x + (i % 4 - 1.5) * 2.8
		var z := SPOT.z - (i / 4) * 3.0
		var b: RigidBody3D = main.emotes._spawn_big({"ball": 600 + i, "point": Vector3(x, main.height(x, z), z), "r": 1.2, "who": p.id})
		b.freeze = true
		b.pack = heavy.get_slice(":", 1)
		balls.append(b)
	await process_frame
	for b in balls:
		olds.append(_old_seam(b))
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 60
	cam.global_position = Vector3(SPOT.x, main.height(SPOT.x, SPOT.z + 6.0) + 2.5, SPOT.z + 6.0)
	cam.look_at(Vector3(SPOT.x, main.height(SPOT.x, SPOT.z) + 1.0, SPOT.z - 1.5))
	cam.make_current()
	var per := float(args.get("per", "1.5"))
	var sums := {"none": [], "old": [], "new": []}
	var draws := {}
	var rounds := int(args.get("rounds", "6"))
	for r in rounds:
		for mode in ["none", "old", "new"]:
			_show(mode)
			var res := await _measure(per)
			sums[mode].append(res[0])
			draws[mode] = res[1]
			print("  %d 回目 %s: %.2f ms（描く回数 %d）" % [r + 1, mode, res[0], res[1]])
	print("いちばん目の多い柄: %s（玉 1 つに %d 目）×%d 個、半径 1.2 m" % [heavy, most, balls.size()])
	for mode in ["none", "old", "new"]:
		var list: Array = sums[mode]
		list.sort()
		var med: float = list[list.size() / 2]
		print("%s: 1 コマ %.2f ms（中央値, %.0f fps）、描く回数 %d" % [{"none": "縫い目なし", "old": "前の作り（箱 28 個）", "new": "今回"}[mode],
				med, 1000.0 / med, draws[mode]])
	quit(0)
