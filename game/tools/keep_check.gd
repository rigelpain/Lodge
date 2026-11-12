extends SceneTree
## 財布のボタンと持ち物の保存（player.gd の keep）を確かめる。1 回目でボタンを増やして食べ物を持たせ、保存を待って閉じる。
## 2 回目で起動したときに戻っているかを見る。遊ぶ人の保存は使わない（--tag-file で別の帳面）。
##   Godot --headless --path game -s res://tools/keep_check.gd -- --step=1 --tag-file=user://keep_check.cfg --no-sound
##   Godot --headless --path game -s res://tools/keep_check.gd -- --step=2 --tag-file=user://keep_check.cfg --no-sound
## --world=asahigaoka を付けると、そのワールドで（保存はワールドによらない）

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.get("step", "1") == "1":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(args["tag-file"])))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 60:
		await physics_frame
	var p = main.player
	var craft = main.craft
	var id: int = p.id
	print("起動したとき: ボタン %d・持ち物 %s・戻した印 %s" % [craft.wallet(id), _bag(craft, id), str(craft.restored.has(id))])
	if args.get("step", "1") == "1":
		craft.send({"kind": "earn", "who": id, "n": 1234})
		craft._put(id, preload("res://food.gd").item("ramen"))
		print("ふやした: ボタン %d・持ち物 %s" % [craft.wallet(id), _bag(craft, id)])
		for i in 300:   # 自動で書くまで（3 秒おき）
			await physics_frame
		var cf := ConfigFile.new()
		cf.load(String(args["tag-file"]))
		print("帳面: ボタン %s・持ち物 %d 個" % [str(cf.get_value("keep", "buttons", "なし")), (cf.get_value("keep", "bag", []) as Array).filter(func(x): return not (x as Dictionary).is_empty()).size()])
	quit()


func _bag(craft, id: int) -> String:
	var out := []
	for it in craft.bags.get(id, []):
		if not (it as Dictionary).is_empty():
			out.append(String(it.get("kind", "?")) + ":" + String(it.get("dish", it.get("sled", ""))))
	return str(out)
