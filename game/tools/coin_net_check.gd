extends SceneTree
## 通信の確かめ: 雪のボタンを取ったとき、財布へ飛ぶボタン（craft_ui.gd）が、体に入り終えてから体から飛び出すか（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/coin_net_check.gd -- --host --port=24751 --bots=0 --lodge-bots=0 --no-sound
##   Godot --headless --fixed-fps 60 --path game -s res://tools/coin_net_check.gd -- --join=127.0.0.1 --port=24751 --bots=0 --lodge-bots=0 --no-sound
## つながってから（雪のボタンは通信に載っていないので、どちらもホストの画面のボタンを切る）:
##   A  ホストが自分の足もとのボタンを裁ちばさみで切る → ホストの画面で 3D のボタンがホストの体へ、体から財布へ（f0 あり）
##   B  ホストが、つなぐ側の人（ホストの画面の Remote）の足もとのボタンを、その人のはさみで切る → ホストの画面では 3D のボタンが
##      Remote の体へ。つなぐ側の画面にはそのボタンがないので、つなぐ側の財布へは、取った所から飛ぶ（f0 なし。二つに見えない）

const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s %.1f コマ %d] %s" % ["host" if args.has("host") else "join", (Time.get_ticks_msec() - _t0) / 1000.0, Doll.frame_index(), s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _flies() -> String:
	var out := []
	for f in main.craft_ui._flies:
		out.append("%s t=%.2f %s" % [f.look, f.t, ("f0=%d 体=%s" % [f.f0, f.body.name]) if f.has("f0") else "取った所から"])
	return "財布へ飛ぶ %d 枚 %s / 財布 %d（飛んでいる %d）" % [out.size(), out, main.craft.wallet(main.player.id), main.craft_ui._pending]


func _run() -> void:
	await _wait(0.5)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 20.0:
		await _wait(0.5)
		t += 0.5
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	_t0 = Time.get_ticks_msec()
	var sb: Node3D = main.snow_buttons
	sb.auto = false
	var host := args.has("host")
	var p: CharacterBody3D = main.player
	main.craft.happened.connect(func(ev: Dictionary) -> void:
		if ev.kind == "earn":
			_say("earn 届いた: 人 %d に %d（btn %s）" % [int(ev.who), int(ev.n), ev.get("btn", "-")]))
	await _wait(1.5)
	# A
	if host:
		var id: int = sb.drop_at(p.global_position - p.global_basis.z * 0.3, 0, true)
		await _wait(0.2)
		_say("A 自分で切る: %s" % sb.request_cut(p.id))
		await _wait(1.0)
		var b = sb.button(id)
		_say("A 3D のボタン %s → %s（体に入り終えるコマ %d）" % [b.state, b.target.name if b.target else "-", b.pop0 + sb.POP_UP + sb.POP_FLY])
	for i in 6:
		await _wait(0.3)
		_say("A " + _flies())
	# B
	if host:
		var rid: int = main.net.remotes.keys()[0]
		var r: Node3D = sb._person(rid)
		var id: int = sb.drop_at(r.global_position - r.global_basis.z * 0.3, 0, true)
		await _wait(0.2)
		_say("B つなぐ側の人 %d（%s）が切る: %s" % [rid, r.name, sb.request_cut(rid)])
		await _wait(1.0)
		var b = sb.button(id)
		_say("B 3D のボタン %s → %s" % [b.state, b.target.name if b.target else "-"])
	for i in 8:
		await _wait(0.3)
		_say("B " + _flies())
	await _wait(1.0)
	quit()
