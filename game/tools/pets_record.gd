extends SceneTree
## 連れの動物（companions.gd）の確かめ: 小鳥と子狐が、あなたが指した所を一緒に見るか。
##   Godot --path game --resolution 960x540 -s res://tools/pets_record.gd -- --no-pip --no-sound --bots=0 --dir=/path/frames
## あなたはソリから離れて立ち、決まった時刻に次のことをする。カメラは斜め前から、あなたと子狐を撮る。
##   1.5 秒  右の前の雪を指す
##   3.5 秒  指したまま、左へ見回す（顔と指さしが別の向き。小鳥と子狐は指した所を見続けるはず）
##   6.0 秒  指さしを切る（小鳥はあなたの見ている先、子狐はあなたの顔を見るはず）
##   7.5 秒  前へ 5 m 歩く（子狐がついてくるはず）
## 0.5 秒ごとに、指す所と、小鳥と子狐の頭の向きのずれ（水平の角度）を出す。コマは 15 枚／秒で dir に書く。

const Companions := preload("res://companions.gd")

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var n := 0
var _acc := 0.0
var _said := 0.0
var _step := 0
var _pets: Companions
var _walk_from := Vector3.ZERO
var _fwd := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 45
	cam.cull_mask = (1 << 0) | (1 << 1)   # 世界と、あなたの体（小鳥はあなたの体と同じ層）
	root.add_child(cam)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/pets"))


## 水平の角度のずれ（度）。from から見た to の向きと、dir の向き
static func _off(dir: Vector3, from: Vector3, to: Vector3) -> float:
	var a := Vector2(dir.x, dir.z)
	var b := Vector2(to.x - from.x, to.z - from.z)
	if a.length() < 1e-4 or b.length() < 1e-4:
		return 0.0
	return rad_to_deg(absf(a.angle_to(b)))


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	if p == null:
		return false
	cam.current = true
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if _pets == null:
		for c in main.get_children():
			if c is Companions:
				_pets = c
		# ソリから離れて、ソリに背を向けて立つ（カメラにソリが入らないように）
		var away: Vector3 = p.global_position - main.sled.global_position
		away.y = 0
		away = away.normalized()
		var at: Vector3 = p.global_position + away * 4.0
		p.global_position = Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z)
		p.rotation.y = atan2(-away.x, -away.z)
		_fwd = away
	var right := _fwd.cross(Vector3.UP)

	match _step:
		0:
			if t > 1.0:
				_step = -1
				p.rotate_y(-0.7)      # 右の前を向いて
				p._pitch = -0.62      # 前の雪を見下ろす（カメラの向きは次の物理のコマで変わるので、指すのは少しあと）
		-1:
			if t > 1.5:
				_step = 1
				p.toggle_point()      # 指す
				print("指す: ", p.point_at.snapped(Vector3.ONE * 0.1))
				# 確かめ用の目印（赤い玉）を指した所に置く
				var mark := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.12
				sm.height = 0.24
				mark.mesh = sm
				var mm := StandardMaterial3D.new()
				mm.albedo_color = Color(0.85, 0.1, 0.1)
				mark.material_override = mm
				main.add_child(mark)
				mark.global_position = p.point_at + Vector3.UP * 0.1
		1:
			if t > 3.5:
				_step = 2
				p.rotate_y(1.5)       # 指したまま左へ見回す
				p._pitch = 0.0
				print("見回す（指したまま）")
		2:
			if t > 6.0:
				_step = 3
				p.toggle_point()
				print("指さしを切る")
		3:
			if t > 7.5:
				_step = 4
				p.rotate_y(-0.8)
				_walk_from = p.global_position
				print("歩く")
		4:
			var walked: float = (p.global_position - _walk_from).length()
			if walked < 5.0:
				var f: Vector3 = -p.global_basis.z
				f.y = 0
				p.global_position += f.normalized() * 1.6 * dt
			else:
				_step = 5
				print("止まる")

	# カメラ: 歩き始めるまでは、あなたの斜め前から（顔・指す腕・小鳥・子狐・指す所が入る）。歩いたらついていく
	var base: Vector3 = p.global_position if _step >= 4 else _walk_from_or(p)
	var want: Vector3 = base + _fwd * 4.6 - right * 2.2 + Vector3.UP * 2.3
	var look: Vector3 = base + _fwd * 1.1 + right * 0.4 + Vector3.UP * 0.45
	cam.global_position = want if t < 0.1 else cam.global_position.lerp(want, minf(1.0, dt * 3.0))
	cam.look_at(look, Vector3.UP)

	if _pets and t - _said > 0.5:
		_said = t
		var line := "t=%.1f 指す=%s" % [t, "なし" if p.point_at == Vector3.INF else str(p.point_at.snapped(Vector3.ONE * 0.1))]
		var tgt: Vector3 = p.point_at if p.point_at != Vector3.INF else Vector3.INF
		if _pets._bird:
			var bt: Vector3 = tgt if tgt != Vector3.INF else p.doll.gaze
			line += "  小鳥のずれ=%.0f°" % _off(-_pets._bird.global_basis.z, _pets._bird.global_position, bt)
		if _pets._kit_head:
			var kt: Vector3 = tgt if tgt != Vector3.INF else p.doll.global_position + Vector3.UP * 1.3
			line += "  子狐の頭のずれ=%.0f°  子狐との距離=%.1fm" % [_off(-_pets._kit_head.global_basis.z, _pets._kit_head.global_position, kt),
					(_pets._kit.global_position - p.global_position).length()]
		line += "  あなたの顔と指す所のずれ=%.0f°" % (_off(-p.cam.global_basis.z, p.cam.global_position, tgt) if tgt != Vector3.INF else 0.0)
		print(line)

	_acc += dt
	if _acc >= 1.0 / 15.0 and t > 0.3:
		_acc = 0.0
		root.get_texture().get_image().save_png("%s/%05d.png" % [args.get("dir", "/tmp/pets"), n])
		n += 1
	if t > float(args.get("secs", "12")):
		print("frames: ", n)
		quit()
	return false


var _start := Vector3.INF


func _walk_from_or(p: Node3D) -> Vector3:
	if _start == Vector3.INF:
		_start = p.global_position
	return _start
