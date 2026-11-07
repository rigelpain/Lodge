extends SceneTree
## 通信の確かめ: B の息が、吐いた人の画面と相手の画面で同じように出て、同じように止まるか（数字だけ出す）。
##   Godot --headless --path game -s res://tools/breath_net_check.gd -- --host --port=24756 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-lodge
##   Godot --headless --path game -s res://tools/breath_net_check.gd -- --join=127.0.0.1 --port=24756 --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-buttons --no-lodge
## 時計の区切りで、はじめにホストが、次につなぐ側が 2 秒吐く。どちらの画面でも、吐いた人の人形の B の息が出て、
## 離すと止まり、おーいの息は出ないか見る（粒の動きは --headless では進まないので、出方と作りの数字まで）

const PERIOD := 8.0

var args := {}
var main: Node3D
var host := false
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	host = args.has("host")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s] %s" % ["host" if host else "join", s])


func _check(ok: bool, s: String) -> void:
	_say(("○ " if ok else "× ") + s)
	if not ok:
		fails += 1


func _run() -> void:
	await create_timer(0.5).timeout
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await create_timer(0.25).timeout
		t += 0.25
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	await create_timer(PERIOD).timeout   # 両方がつながるのを待ち、次の区切りから
	var now := Time.get_unix_time_from_system()
	var start := (int(now / PERIOD) + 1) * PERIOD
	await create_timer(start - now).timeout
	await _turn(true)
	await create_timer(start + PERIOD - Time.get_unix_time_from_system()).timeout
	await _turn(false)
	_say("食い違い %d" % fails)
	quit(1 if fails > 0 else 0)


## by_host: ホストが吐く番か。自分の番なら B を押して 2 秒で離す。どちらの番でも、吐いた人の人形を見る
func _turn(by_host: bool) -> void:
	var mine := by_host == host
	var who: Node3D = main.player if mine else main.net.remotes[main.net.remotes.keys()[0]]
	var d = who.doll
	var label := ("自分" if mine else "相手") + "の人形"
	if mine:
		main.player.menu_open = false
		_key(true)
	await create_timer(1.5).timeout
	var e: CPUParticles3D = d._streams["exhale"]
	_check(e.emitting, label + ": 吐いているあいだ、B の息が出る")
	_check(not d._long.emitting, label + ": おーいの息は出ない")
	if mine:
		_key(false)
	await create_timer(1.4).timeout
	_check(not e.emitting, label + ": 離すと止まる")
	_say("%s: 粒の数=%d 寿命=%.1f 昇る力=%.2f 濃さ=%.2f" % [label, e.amount, e.lifetime, e.gravity.y, d._exhale_mat.get_shader_parameter("opacity")])


func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_B
	ev.keycode = KEY_B
	ev.pressed = down
	Input.parse_input_event(ev)
