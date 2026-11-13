extends SceneTree
## HUD の入れ物ごとに、乗って滑っているあいだ何回描き直されたかを数える（2026-11-14。HUD の描き直しが 1 コマの 2〜4 割を使っていた）。
##   Godot --path game --resolution 1280x720 -s res://tools/hud_redraw_count.gd -- --roam-bots=0 --no-sound --no-pip --no-save [--keys] [--secs=6]
## 丘の上からソリに乗って滑り出し、--secs 秒（既定 6）のあいだ、描き直しの知らせ（CanvasItem の draw）を入れ物ごとに数えて出す。
## --keys: W を押し続ける（何もしないと HUD が画面の外へ引っこむので、遊んでいるときと同じにするには付ける）
## 見方: コマ数に近い回数の入れ物は、毎コマ描き直している。名札の地（hud:tag）・持ち物の列（craft:bar）・装備の札（craft:gear）・
## 雪玉の帯（craft:balls）は、中身が変わらなければ 1 秒に 1〜2 回（追いつきの描き直し）だけのはず。
## Control の傾き・縮み・支点（rotation・scale・pivot_offset）を変えると、そのたびに中身が描き直されるので注意（hud_plates.gd の holder）

var args := {}
var main: Node3D
var t := 0.0
var step := 0
var frames := 0
var redraws := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	AudioServer.set_bus_mute(0, true)


func _hook(v: CanvasItem, name: String) -> void:
	if v.has_meta("redraw_counted"):
		return
	v.set_meta("redraw_counted", true)
	v.draw.connect(func(): redraws[name] = int(redraws.get(name, 0)) + 1)


## HUD の入れ物（View の part を持つ Control と、自分の小窓の枠）に、数える知らせをつなぐ。滑り出してから作られる入れ物もあるので毎コマ見る
func _hook_all() -> void:
	for c in main.craft_ui.get_children():
		if c is Control and c.get("part") != null:
			_hook(c, "craft:" + String(c.part))
	for c in main.hud.find_children("*", "Control", true, false):
		if c.get("part") != null:
			_hook(c, "hud:" + String(c.part))
	var sc = main.get("self_cam")
	if sc and sc.get("_frame"):
		_hook(sc._frame, "self_cam:frame")


func _process(dt: float) -> bool:
	t += dt
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		main.player.menu_open = false
	var p = main.player
	var sled = main.sled
	match step:
		0:
			if t > 5.0:
				var out := Vector3(0, 0, 1)
				sled.global_position = Vector3(0, main.height(0, 6) + 0.6, 6)
				sled.global_rotation.y = atan2(-out.x, -out.z)
				p.global_position = sled.global_position + Vector3.UP * 0.5
				p.get_on()
				sled.linear_velocity = out * 9.0
				step = 1
				t = 0.0
		1:
			_hook_all()
			if args.has("keys"):
				var ev := InputEventKey.new()
				ev.physical_keycode = KEY_W
				ev.pressed = true
				Input.parse_input_event(ev)
			frames += 1
			if t > float(args.get("secs", "6")):
				var keys := redraws.keys()
				keys.sort()
				print("コマ数 %d。描き直した回数:" % frames)
				for k in keys:
					print("  %-18s %d" % [k, redraws[k]])
				quit()
	return false
