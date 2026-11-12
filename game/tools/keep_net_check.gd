extends SceneTree
## 財布のボタンと持ち物の保存を、通信で確かめる。同じ Mac で 2 つ起動し、つなぐ側の保存（--tag-file）の財布と持ち物が、
## ホストの画面でもその人の物になるか、10 秒後に両方の画面の数を出す（帳面はそれぞれ別）。
##   Godot --headless --path game -s res://tools/keep_net_check.gd -- --host --tag-file=user://keep_host.cfg --no-sound --no-player-save
##   Godot --headless --path game -s res://tools/keep_net_check.gd -- --join=127.0.0.1 --tag-file=user://keep_join.cfg --no-sound

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	args["bots"] = "0"
	args["lodge-bots"] = "0"
	args["roam-bots"] = "0"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 600:
		await physics_frame
	var craft = main.craft
	var tag := "ホスト" if args.has("host") else "つなぐ側"
	for who in craft.wallets:
		var items := []
		for it in craft.bags.get(who, []):
			if not (it as Dictionary).is_empty():
				items.append(String(it.get("kind", "?")))
		print("[%s の画面] 人 %d: ボタン %d・持ち物 %s・戻した印 %s%s" % [tag, who, craft.wallet(who), str(items), str(craft.restored.has(who)), "（自分）" if main.player and who == main.player.id else ""])
	quit()
