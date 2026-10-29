extends SceneTree
## 声が鳴るかを確かめる（確かめ用）。ゲームを立ち上げ、あなたと仲間に声を出させて、鳴らす係とバスの音の大きさを記録する。
##   Godot --path game -s res://tools/voice_check.gd [-- --vol=0.5]
## --vol を付けると、その音量（ボイス）にしてから確かめる

var main: Node3D
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await _frames(30)
	var p = main.player
	var bot = main.get_children().filter(func(c): return c != p and c.get("doll") != null and c.has_method("get_off"))[0]
	if args.has("vol"):
		main.settings.values["vol_voice"] = float(args["vol"])
		main._apply_setting("vol_voice", float(args["vol"]))
	print("設定のボイス=", main.settings.values.get("vol_voice"), "（既定 ", _default("vol_voice"), "）")
	for i in AudioServer.bus_count:
		print("バス %d %-8s → %-8s %6.1f dB%s" % [i, AudioServer.get_bus_name(i), AudioServer.get_bus_send(i), AudioServer.get_bus_volume_db(i), " 消音" if AudioServer.is_bus_mute(i) else ""])
	var vi := AudioServer.get_bus_index("Voice")
	for who in [p, bot]:
		for kind in ["un", "nn", "huh", "oi"]:
			main.emotes.send({"kind": kind, "who": who.id})
			var peak := -200.0
			var players := 0
			for f in 40:
				await physics_frame
				peak = maxf(peak, maxf(AudioServer.get_bus_peak_volume_left_db(vi, 0), AudioServer.get_bus_peak_volume_right_db(vi, 0)))
				var n := 0
				for node in main.get_node("Audio").get_children() + main.get_children():
					if (node is AudioStreamPlayer or node is AudioStreamPlayer3D) and node.playing and node.bus == "Voice":
						n += 1
				players = maxi(players, n)
			print("%s の %s: Voice で鳴る係=%d、Voice の山=%.1f dB" % ["あなた" if who == p else "仲間", kind, players, peak])
			await _frames(20)
	quit()


func _default(key: String) -> Variant:
	for row in main.settings.ITEMS:
		if row[0] == key:
			return row[3]
	return null
