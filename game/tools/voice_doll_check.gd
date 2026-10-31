extends SceneTree
## 人形ごとの声が鳴るかを確かめる（確かめ用）。あなたと仲間 2 人に声を出させ、読み込んだ wav の名前と、Voice で鳴った係の数を出す。
##   Godot --headless --path game -s res://tools/voice_doll_check.gd

var main: Node3D


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for f in 30:
		await physics_frame
	var people: Array = [main.player] + main.get_children().filter(func(c): return c != main.player and c.get("doll") != null and c.has_method("get_off"))
	var audio: Node = main.get_node("Audio")
	for who in people:
		for kind in ["wa", "un", "nn", "huh", "oi", "hit"]:
			main.emotes.send({"kind": kind, "who": who.id})
			var players := 0
			for f in 40:
				await physics_frame
				var n := 0
				for node in audio.get_children() + main.get_children():
					if (node is AudioStreamPlayer or node is AudioStreamPlayer3D) and node.playing and node.bus == "Voice":
						n += 1
				players = maxi(players, n)
			print("%s（%s）の %s: Voice で鳴る係=%d" % ["あなた" if who == main.player else "仲間", who.doll.kind, kind, players])
			for f in 20:
				await physics_frame
	var names: Array = audio._streams.keys().filter(func(k): return (k as String).begins_with("voice_"))
	names.sort()
	print("読み込んだ声: ", names)
	quit()
