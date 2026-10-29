extends SceneTree
## 画面の表示（hud.gd）を、場面ごとに一人称で撮る（確かめ用）。
##   Godot --path game --resolution 1600x900 -s res://tools/hud_shots.gd -- --scene=base --out=/path/to.png [--at=秒]
## 場面:
##   base    ふもと。ソリの後ろに立つ（つかむの案内）
##   side    ソリの横に立つ（つかむ・乗るの案内）
##   push    仲間と一緒に押して登っている（札の人の形と糸の矢印、押すの案内）
##   top     頂上で乗っている、止まっている（前に乗り出す・降りるの案内）
##   ride    乗って滑り降りている（体重をかける・止まるの案内）
##   people  ソリから離れて、仲間のそばにいる（身ぶりの案内）
##   lodge   ロッジの中（札は消える）
##   menu    Esc を押したとき（操作の札）
## main.gd の引数（--bots など）もそのまま効く。

var args := {}
var main: Node3D
var t := 0.0
var _set := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


## ソリを丘の上の、頂上から r m の所に置く。yaw はソリの向き（0 で頂上を向く、PI で下りを向く）
func _place_sled(r: float, yaw: float) -> void:
	var sled: RigidBody3D = main.sled
	var p := Vector3(0, 0, r)
	p.y = main.height(p.x, p.z) + 0.35
	sled.reset_to(p)
	sled.rotation.y = yaw


func _face(p: Node3D, at: Vector3, pitch := -0.15) -> void:
	var d := at - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p._pitch = pitch


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	var sled: RigidBody3D = main.sled
	if p == null or sled == null:
		return false
	var scene: String = args.get("scene", "base")
	if not _set and t > 0.6:
		_set = true
		p.set_third(false)
		match scene:
			"base":
				_face(p, sled.global_position, -0.2)
			"side":
				p.global_position = sled.to_global(Vector3(2.1, 0, 0.3)) + Vector3.UP * 0.2
				_face(p, sled.global_position, -0.3)
			"push":
				p.global_position = sled.to_global(Vector3(0, 0, 2.2)) + Vector3.UP * 0.2
				_face(p, sled.global_position, -0.15)
				p.grab()
				_key(KEY_W, true)
			"top":
				_place_sled(2.5, PI)
				p.global_position = sled.global_position + sled.global_basis.x * 1.2 + Vector3.UP * 0.3
				p.get_on()
				p.rotation.y = sled.global_rotation.y
				p._pitch = -0.15
			"ride":
				_place_sled(9.0, PI)
				p.global_position = sled.global_position + sled.global_basis.x * 1.2 + Vector3.UP * 0.3
				p.get_on()
				p.rotation.y = sled.global_rotation.y
				p._pitch = -0.2
				sled.linear_velocity = -sled.global_basis.z * 4.0
			"people":
				p.global_position = sled.to_global(Vector3(5.0, 0, 3.5)) + Vector3.UP * 0.3
			"lodge":
				if main.has_node("Audio"):
					p.global_position = main.get_node("Audio").spawn_point("inside")
				p._pitch = -0.05
			"menu":
				main.settings.set_open(true)
				p.menu_open = true
	if _set and t < 1.5:   # 360° 映像は、保存してある設定に関わらず出す（設定は書き換えない）
		main.pip_hidden = false
		if main._pip_layer: main._pip_layer.visible = true
	if _set and (scene == "base" or scene == "side"):   # 仲間がソリを動かしても、ソリとの位置を保つ
		var off := Vector3(0, 0, 2.6) if scene == "base" else Vector3(2.1, 0, 0.3)
		var want := sled.to_global(off)
		want.y = main.height(want.x, want.z) + 0.1
		p.global_position = want
		_face(p, sled.global_position, -0.3)
	if _set and scene == "people":
		var bots := main.get_children().filter(func(c): return c != p and c is CharacterBody3D and c.get("doll") != null)
		if bots.size() > 0:
			_face(p, bots[0].global_position + Vector3.UP * 1.2, -0.05)
	if _set and scene == "ride":
		p.rotation.y = sled.global_rotation.y
	if t > float(args.get("at", "4")):
		var out: String = args.get("out", "/tmp/hud.png")
		root.get_texture().get_image().save_png(out)
		print("保存: ", out, "  案内: ", main.hud.uses, "  押している人: ", sled.pushers)
		return true
	return false
