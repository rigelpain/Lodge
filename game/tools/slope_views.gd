extends SceneTree
## 天下森のゲレンデを、見取り図（design/tenkamori/slope/01-slope-map.png）の印の所から、動画と同じ向き（下る向き）で撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/slope_views.gd -- --world=tenkamori --no-player --no-snow --no-sound --dir=<フォルダ>

const Tenka := preload("res://tenkamori.gd")

var args := {}
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main.hud:
		main.hud.visible = false
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	return false


static func _v(p) -> Vector2:
	return Vector2(p[0], p[1])


static func _along(line: Array, f: float) -> Array:
	var L := 0.0
	for k in line.size() - 1:
		L += _v(line[k]).distance_to(_v(line[k + 1]))
	var s := f * L
	var acc := 0.0
	for k in line.size() - 1:
		var a := _v(line[k])
		var b := _v(line[k + 1])
		var d := a.distance_to(b)
		if acc + d >= s:
			return [a.lerp(b, (s - acc) / d), (b - a).normalized()]
		acc += d
	return [_v(line[line.size() - 1]), Vector2.RIGHT]


func _shot(name: String, from: Vector3, to: Vector3, fov := 75.0) -> void:
	cam.fov = fov
	cam.position = from
	cam.look_at(to)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(String(args.get("dir", "/tmp")).path_join(name + ".png"))


## (x, z) に立って、下る向き dir（線の向き）の先を見る
func _stand(name: String, p: Vector2, dir: Vector2, h := 1.6, ahead := 40.0, drop := 4.0) -> void:
	var y: float = main.height(p.x, p.y) + h
	var q := p + dir * ahead
	await _shot(name, Vector3(p.x, y, p.y), Vector3(q.x, main.height(q.x, q.y) + h - drop, q.y))


func _run() -> void:
	cam = Camera3D.new()
	cam.far = 30000.0
	main.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	var m: Dictionary = Tenka.map()
	var lift: Array = []
	for l in m.lifts:
		if l.kind == "chair_lift":
			lift = l.line
	var main_c: Array = []
	var rinkan: Array = []
	for p in m.pistes:
		if p.name == "天下森コース":
			main_c = p.line
		elif p.name == "夏虫沢林間コース":
			rinkan.append(p.line)
	var rk: Array = rinkan[0].duplicate()
	rk.append_array(rinkan[1].slice(1))
	var down_main := main_c.duplicate()   # 天下森コースは頂上 → ふもとの向きに並んでいる
	# 2: リフトの中ほどの座面の高さから、谷の向かい（乗り場の向き）
	var r: Array = _along(lift, 0.45)
	var lp: Vector2 = r[0]
	var lift_node = main.get_node("Tenkamori/Lift")
	var seat_y: float = main.height(lp.x, lp.y) + 6.5
	await _shot("m2_lift", Vector3(lp.x, seat_y, lp.y), Vector3(lp.x - r[1].x * 300.0, seat_y - 30.0, lp.y - r[1].y * 300.0), 80.0)
	for f in [[4, 0.12], [5, 0.35], [6, 0.6], [7, 0.85]]:
		var a: Array = _along(rk, f[1])
		await _stand("m%d_rinkan" % f[0], a[0] - a[1] * 6.0, a[1])
	for f in [[8, 0.3], [9, 0.55], [10, 0.8], [11, 0.95]]:
		var a: Array = _along(down_main, f[1])
		await _stand("m%d_main" % f[0], a[0] - a[1] * 8.0, a[1], 1.6, 60.0, 8.0)
	quit()
