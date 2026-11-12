extends SceneTree
## 雪面の起伏を見る絵（今までの世界と天下森。main.gd の relief・tenkamori/add_snow_relief.py）。陽の低い時刻で撮ると影で見える。
##   Godot --path game --resolution 1280x720 -s res://tools/relief_shots.gd -- --world=plain|tenkamori --no-player --no-snow --no-sound --time=15.8 --dir=<フォルダ>

const SHOTS := {
	"plain": [["hill", Vector3(-30, 0, 70), Vector3(0, 0, 0)], ["mountain", Vector3(-10, 0, 240), Vector3(-10, 0, 420)],
			["mountain_down", Vector3(-20, 0, 420), Vector3(-10, 0, 260)]],
	"tenkamori": [["base_up", Vector3(-60, 0, 90), Vector3(-260, 0, 420)], ["mid_down", Vector3(-230, 0, 380), Vector3(-80, 0, 130)],
			["top_down", Vector3(-380, 0, 620), Vector3(-200, 0, 340)]],
}

var args := {}
var main: Node3D


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
	return false


func _run() -> void:
	for i in 30:
		await process_frame
	if main.start:
		main.start._solo()
	var cam := Camera3D.new()
	cam.far = 30000.0
	cam.fov = 60.0
	main.add_child(cam)
	cam.make_current()
	for s in SHOTS[String(args.get("world", "plain"))]:
		var a: Vector3 = s[1]
		var b: Vector3 = s[2]
		cam.position = Vector3(a.x, main.height(a.x, a.z) + 1.6, a.z)
		cam.look_at(Vector3(b.x, main.height(b.x, b.z) + 1.0, b.z))
		var f0 := Engine.get_frames_drawn()
		while Engine.get_frames_drawn() < f0 + 12:
			await process_frame
		var path: String = String(args.get("dir", "/tmp")).path_join("%s.png" % s[0])
		root.get_texture().get_image().save_png(path)
		print("保存: ", path)
	quit()
