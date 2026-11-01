extends SceneTree
## 何もしないでいると HUD が画面の外へ引っこむ（hud.gd の _update_tuck）ようすを撮る（確かめ用）。
##   Godot --path game --resolution 1600x900 -s res://tools/tuck_shots.gd -- --dir=/path --hud-idle=2 --bots=0 --no-sound [--water=-30]
## 刺繍枠の右上の体の調子のバッジ（damp_hud.gd）が出るよう、あなたの水を --water（既定 −30 パリッと）に止めてから:
##   1_shown 出ている → 2_going 引っこむ途中 → 3_tucked 引っこんだ → 4_back さわって戻った

var args := {}
var main: Node3D
var p: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/tuck_shots")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path, "  引っこめ %.2f  バッジ %d 枚" % [preload("res://hud_icons.gd").tuck, main.badges.of(p.id).size()])


func _run() -> void:
	await _wait(2.0)
	p = main.player
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	main.damp.authority = false   # 値はここで止める
	main.damp.put(p.id, float(args.get("water", "-30")))
	main.hud._idle = 0.0
	await _wait(1.0)
	await _shot("1_shown")
	while main.hud._idle < main.hud.idle_limit + 0.6:
		await process_frame
	await _shot("2_going")
	await _wait(1.5)
	await _shot("3_tucked")
	main.hud._idle = 0.0   # さわった
	await _wait(0.6)
	await _shot("4_back")
	quit()
