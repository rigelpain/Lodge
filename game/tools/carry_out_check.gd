extends SceneTree
## ミシンで縫ったソリを、ロッジの中から外へ運び出せるかを確かめる（確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 60 -s res://tools/carry_out_check.gd -- --no-player --bots=0 --no-sound --no-pip --dir=/path/shots
## 1. 箱を通す: ソリの大きさの箱を、ミシンの前（ソリが出てくる所）→ 食堂の西の通路 → 内の自動ドア → 風除室 → アーチ戸 →
##    玄関前の広場 → 外の雪、の道に沿って、向きを道に合わせながら 0.2 m ずつ動かし、壁や家具に当たる所を探す（床と階段は数えない）
## 2. 押して運ぶ（--push=small など）: 本物のソリを出し、後ろから人が押すのと同じ力（sled.push）で道の点へ向けて押す。
##    自動ドアは人にしか開かないので、ソリの後ろを当たりのない人がついて歩く。外の雪まで着いたか、どこで止まったかを出す
## 道の点はロッジの座標（Blender の lodge/dims.py の x, y。正面は -y）で持つ

const Sled := preload("res://sled.gd")

# 道（ロッジの座標 x, y）。ミシンの前から南へ、内の戸の前で東へ寄り、まっすぐ外へ
const PATH := [Vector2(-19.1, 6.0), Vector2(-18.6, 0.0), Vector2(-15.0, -8.5), Vector2(-13.4, -11.0), Vector2(-13.4, -15.0),
	Vector2(-13.4, -19.0), Vector2(-13.4, -24.5), Vector2(-13.4, -30.0)]
const ALT_PATHS := [
	[Vector2(-19.1, 6.0), Vector2(-17.5, 2.0), Vector2(-15.0, -8.5), Vector2(-13.4, -11.0), Vector2(-13.4, -19.0), Vector2(-13.4, -30.0)],
	[Vector2(-19.1, 6.0), Vector2(-19.1, 3.0), Vector2(-16.5, -2.0), Vector2(-13.4, -10.0), Vector2(-13.4, -19.0), Vector2(-13.4, -30.0)],
	[Vector2(-18.0, 6.0), Vector2(-16.8, 0.0), Vector2(-14.5, -8.5), Vector2(-13.4, -11.0), Vector2(-13.4, -19.0), Vector2(-13.4, -30.0)],
]
const OUTSIDE_Y := -24.5     # これより南（ロッジの座標）なら外の雪

var args := {}
var main: Node3D
var lodge: Node3D
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _say(s: String) -> void:
	print(s)
	lines.append(s)


## ロッジの座標 (x, y) → 世界（高さは床を探す）
func _w(p: Vector2, lift := 0.0) -> Vector3:
	var g := lodge.to_global(Vector3(p.x, 0, -p.y))
	var q := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 3.0, g + Vector3.DOWN * 4.0)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position if hit else g) + Vector3.UP * lift


func _passable(n: Object) -> bool:
	if not (n is Node):
		return true
	var nm := (n as Node).name.to_lower()
	if nm.contains("floor") or nm.contains("stairs"):
		return true
	for c in (n as Node).get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is HeightMapShape3D:
			return true
	return n is RigidBody3D or n is CharacterBody3D


func _sweep(kind: String, path: Array = PATH) -> String:
	var k: Dictionary = Sled.KINDS[kind]
	var box: Vector3 = k.box
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.x, 0.5, box.z) * Vector3(0.98, 1, 0.98)
	var sp := root.get_world_3d().direct_space_state
	for i in path.size() - 1:
		var a := _w(path[i])
		var b := _w(path[i + 1])
		var n := maxi(1, int(a.distance_to(b) / 0.2))
		for j in n + 1:
			var t := float(j) / n
			var p := a.lerp(b, t)
			var dir := (b - a)
			dir.y = 0
			dir = dir.normalized()
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), p + Vector3.UP * 0.55)   # 床から 0.3 上（段差・床板は数えない）
			for r in sp.intersect_shape(q, 8):
				if not _passable(r.collider):
					var lp := lodge.to_local(p)
					return "当たる: %s（ロッジの座標 x=%.1f y=%.1f、道の %d 区間目）" % [(r.collider as Node).name, lp.x, -lp.z, i + 1]
	return "通る"


func _run() -> void:
	await create_timer(2.0).timeout
	lodge = main.get_node("Lodge")
	for kind in ["sack", "small", "mid", "large"]:
		var k: Dictionary = Sled.KINDS[kind]
		_say("%s（幅 %.2f m × 長さ %.2f m）: %s" % [kind, k.box.x, k.box.z, _sweep(kind)])
	for alt in ALT_PATHS:   # 大のソリが通る道があるか
		_say("large 別の道 %s: %s" % [str(alt.slice(1, 3)), _sweep("large", alt)])
	if args.has("push"):
		await _push(args["push"])
	if args.has("dir"):
		var f := FileAccess.open(String(args["dir"]).path_join("carry_out.txt"), FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
	quit()


## 本物のソリを出して、後ろから押して運ぶ
func _push(kind: String) -> void:
	var s := Sled.new()
	s.kind = kind
	s.crafted = true
	var a := _w(PATH[0], 0.1)
	var b := _w(PATH[1])
	var d := b - a
	s.transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), a)
	s.snow_lift = Callable(main, "snow_lift")
	main.add_child(s)
	# 自動ドアを開けるための、当たりのない人（ソリの後ろをついて歩く）
	var walker := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 1.6
	cs.shape = cap
	walker.add_child(cs)
	main.add_child(walker)
	walker.add_collision_exception_with(s)
	walker.collision_mask = 0
	var cam := Camera3D.new()
	cam.fov = 70
	main.add_child(cam)
	cam.current = true
	var target := 1
	var t := 0.0
	var stuck := 0.0
	var last := s.global_position
	var shot_i := 0
	var dir_name := String(args.get("dir", ""))
	while t < 90.0 and target < PATH.size():
		await physics_frame
		t += 1.0 / 60.0
		var goal := _w(PATH[target])
		var to := goal - s.global_position
		to.y = 0
		if to.length() < maxf(1.2, s.HALF.y * 0.6):
			target += 1
			continue
		var fwd: Vector3 = -s.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var want := to.normalized()
		# 後ろの縁を、行きたい向きへ押す（2 人分）。向きのずれが大きいと、横から押して回す
		var rear: Vector3 = s.global_position - fwd * s.HALF.y
		var side := fwd.cross(Vector3.UP) * signf(fwd.cross(want).y) * -1.0
		var turn := clampf(fwd.signed_angle_to(want, Vector3.UP), -1.0, 1.0)
		s.push(want, rear + Vector3.UP * 0.3, null)
		s.push(want, rear + Vector3.UP * 0.3, null)
		if absf(turn) > 0.15:
			s.push(side, rear + Vector3.UP * 0.3, null)
		walker.global_position = rear - fwd * 0.8
		cam.global_position = s.global_position - fwd * (s.HALF.y + 3.5) + Vector3.UP * 2.6
		cam.look_at(s.global_position + fwd * 1.5 + Vector3.UP * 0.3)
		if s.global_position.distance_to(last) < 0.01:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
		last = s.global_position
		if stuck > 6.0:
			break
		if dir_name != "" and int(t * 60.0) % 300 == 0:
			shot_i += 1
			root.get_texture().get_image().save_png(dir_name.path_join("push_%s_%02d.png" % [kind, shot_i]))
	var lp := lodge.to_local(s.global_position)
	var out := -lp.z < OUTSIDE_Y
	_say("%s を押して運ぶ: %s（%.0f 秒、ロッジの座標 x=%.1f y=%.1f%s）" % [kind, "外まで出た" if out else "止まった", t, lp.x, -lp.z,
			"" if out else "、道の %d 点目へ向かう途中" % target])
	if dir_name != "":
		root.get_texture().get_image().save_png(dir_name.path_join("push_%s_end.png" % kind))
