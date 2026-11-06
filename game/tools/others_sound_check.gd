extends SceneTree
## 自分の音とほかの人の音の大きさの確かめ（数字で。本物の audio.gd の音を、Master の出口で測る）。
##   Godot --path game --resolution 640x360 -s res://tools/others_sound_check.gd -- --bots=0 --no-pip --dir=/path/out [--sfx=0.22 --voice=0.22] [--crowd=30]
## 実時間で鳴らして測るので --fixed-fps は付けない。
## 1. 風・曲・炉などの場の音を止める
## 2. 自分の足音・息・身ぶり・声を耳元で鳴らす（基準）
## 3. 同じ音を、ほかの人（通信の体。net.gd が足すのと同じく add_walker で足す）の所から、距離を変えて鳴らす
## ピーク（dBFS）とエネルギー（1.6 秒の窓の和を dB にしたもの）を出す。差は「ほかの人 - 自分」。正なら自分より大きい。
## ソリのしゃー（だれも触っていない・自分が乗っている）も距離ごとに測る。
## --crowd=秒: 別の測り。場の音は止めたまま、山をめぐる仲間（--roam-bots）を歩かせて、聞こえた音の大きさと、鳴った足音の数を距離ごとに数える。
## <dir>/others_sound.txt と、鳴らした順の録音 <dir>/others_sound.wav（--crowd なら crowd.wav）に書く

const RemotePerson := preload("res://remote_person.gd")
const Doll := preload("res://doll.gd")
const DISTS := [0.5, 1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0, 40.0]
const WINDOW := 1.6   # おーいの声が鳴り切る長さ（短いと、前の音の尾が次の測りに混ざる）

var args := {}
var main: Node3D
var audio: Node
var p: CharacterBody3D
var cap: AudioEffectCapture
var r: CharacterBody3D
var w: Dictionary
var lines: Array[String] = []
var rec := PackedVector2Array()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/others_sound")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


## 場の音を止める。ここからは測る音だけが鳴る
func _silence() -> void:
	for n in audio.lodge.find_children("*", "AudioStreamPlayer3D", true, false):
		n.stop()
	for post in audio._posts:
		post.player.stop()
	audio._posts.clear()
	audio._wind_calm.stop()
	audio._wind_rush.stop()
	audio._timers.crack = 1e9
	audio._timers.lid = 1e9
	audio._timers.dish = 1e9
	audio._timers.creak = 1e9
	if main.snow_buttons:   # 雪に落ちるボタンの音が測りに混ざらないように
		main.snow_buttons.process_mode = Node.PROCESS_MODE_DISABLED


func _fresh() -> void:
	var f := cap.get_frames_available()
	if f > 0:
		rec.append_array(cap.get_buffer(f))


## 鳴らして窓のあいだ録り、[ピーク dBFS, エネルギー dB] を返す
func _measure(play: Callable) -> Array:
	_fresh()
	var from := rec.size()
	play.call()
	await _wait(WINDOW)
	_fresh()
	var peak := 0.0
	var sum := 0.0
	for i in range(from, rec.size()):
		var v: Vector2 = rec[i]
		peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
		sum += v.x * v.x + v.y * v.y
	return [linear_to_db(maxf(peak, 1e-7)), linear_to_db(sqrt(maxf(sum, 1e-14)))]


func _put_at(d: float) -> Vector3:
	var cam := root.get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	return cam.global_position + fwd.normalized() * d


## ほかの人の足音（audio.gd の _play_step。ここを呼ぶと、外なら Outdoor の側、中なら Inside の側で鳴る）
func _other_step(pos: Vector3) -> void:
	r.global_position = pos
	audio._play_step(r, w, "step_snow_01", -10.0, 1.0)


func _other_breath(pos: Vector3) -> void:
	r.global_position = pos
	audio._shot_other(w.breath, audio._wav("breath_01"), -16.0 - audio.OTHER_DROP, 1.0)


func _emote(name_: String, db: float, pos: Vector3, near: bool, bus := "", fixed := "") -> void:
	audio._emote_sound({"frame": Doll.frame_index()}, 0, name_, 3 if fixed == "" else 1, db, 1.0, pos, near, bus, fixed)


## 1 つの音について、自分の基準と、距離ごとのほかの人の値を並べる
func _table(title: String, own: Callable, other: Callable) -> void:
	var base: Array = await _measure(own)
	_say("%s  自分（耳元）: ピーク %.1f dB  エネルギー %.1f dB" % [title, base[0], base[1]])
	for d in DISTS:
		var m: Array = await _measure(other.bind(_put_at(d)))
		var tail := "" if m[1] < -100.0 else ("  差 %+.1f dB" % (m[1] - base[1]))
		_say("  %5.1f m: ピーク %6.1f dB  エネルギー %6.1f dB%s" % [d, m[0], m[1], tail])


func _set_volumes() -> void:
	for pair in [["sfx", "vol_sfx"], ["voice", "vol_voice"]]:
		if args.has(pair[0]):
			main.settings.values[pair[1]] = float(args[pair[0]])
			main._apply_setting(pair[1], float(args[pair[0]]))
	_say("設定: 効果音 %.2f  ボイス %.2f" % [main.settings.values.vol_sfx, main.settings.values.vol_voice])


func _run() -> void:
	await _wait(2.0)
	p = main.player
	audio = main.get_node("Audio")
	var fx := AudioEffectCapture.new()
	fx.buffer_length = 8.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), fx)
	cap = fx
	_set_volumes()
	_silence()
	var buses := []
	for i in AudioServer.bus_count:
		buses.append("%s→%s(%.1f dB)" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i), AudioServer.get_bus_volume_db(i)])
	_say("バス: " + "  ".join(buses))
	await _wait(0.5)
	if args.has("crowd"):
		await _crowd(float(args.crowd))
	else:
		await _tables()
	var f := FileAccess.open(_dir().path_join("others_sound.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	_write_wav(_dir().path_join("crowd.wav" if args.has("crowd") else "others_sound.wav"))
	quit()


func _tables() -> void:
	r = RemotePerson.new()
	r.name = "Heard"
	r.peer = 999
	main.add_child(r)
	r.global_position = _put_at(5.0)
	audio.add_walker(r, true)
	w = audio._walkers[r]
	audio._walkers.erase(r)   # 動きからの足音は要らない。ここで鳴らす音だけを測る
	await _wait(0.3)
	await _table("足音", func(): audio._play_step(p, audio._walkers[p], "step_snow_01", -10.0, 1.0), _other_step)
	await _table("息", func(): audio._shot2(audio._walkers[p].breath, audio._wav("breath_01"), -16.0, 1.0), _other_breath)
	await _table("拍手", func(): _emote("felt_pat", -12.0, Vector3.ZERO, true),
			func(at: Vector3): _emote("felt_pat", -12.0, at, false))
	await _table("声 ワ", func(): _emote("voice_wa", -4.0, Vector3.ZERO, true, "Voice", "kasa"),
			func(at: Vector3): _emote("voice_wa", -4.0, at, false, "Voice", "kasa"))
	await _table("声 おーい", func(): _emote("voice_oi", -1.0, Vector3.ZERO, true, "Voice", "kasa"),
			func(at: Vector3): _emote("voice_oi", -1.0, at, false, "Voice", "kasa"))
	await _table("息の身ぶり（小さい音）", func(): _emote("breath", -22.0, Vector3.ZERO, true, "Voice"),
			func(at: Vector3): _emote("breath", -22.0, at, false, "Voice"))
	await _sled_table()
	await _place_table()


## ソリのしゃー（全速の音量で回っている所）。自分が触っているときの口（基準）と、ほかの人のソリの口を距離ごとに。
## ソリ本体は動かさず、音の口だけを目印に移して測る
func _sled_table() -> void:
	audio.set_physics_process(false)   # _update_sled に音量を書きかえられないように
	var probe := Node3D.new()
	main.add_child(probe)
	var own: AudioStreamPlayer3D = audio._runner_fast
	var other: AudioStreamPlayer3D = audio._runner_other
	for q in [own, other]:
		q.reparent(probe, false)
		q.position = Vector3.ZERO
		q.volume_db = -80.0
		if not q.playing:
			q.play()
	var top: float = -6.0 - audio.OTHER_DROP
	probe.global_position = _put_at(1.0)
	await _wait(0.2)
	var base: Array = await _measure(func(): own.volume_db = -6.0)
	own.volume_db = -80.0
	_say("ソリのしゃー  自分（1 m）: ピーク %.1f dB  エネルギー %.1f dB" % [base[0], base[1]])
	for d in DISTS:
		probe.global_position = _put_at(d)
		await _wait(0.1)
		var m: Array = await _measure(func():
			other.volume_db = top
			other.max_db = top)
		other.volume_db = -80.0
		_say("  %5.1f m: ピーク %6.1f dB  エネルギー %6.1f dB  差 %+.1f dB" % [d, m[0], m[1], m[1] - base[1]])
	audio.set_physics_process(true)


## 耳元でない自分の音と場の音（設定の効果音の音量を変えて、その分だけ動くかを見る）
func _place_table() -> void:
	audio.set_physics_process(false)
	var at := _put_at(1.0)
	var mine: Array = await _measure(func(): audio._emote_sound({"frame": Doll.frame_index()}, 0, "button_snap", 3, -4.0, 1.0, at, false, "", "", true))
	_say("自分のボタン（1 m）: ピーク %.1f dB  エネルギー %.1f dB" % [mine[0], mine[1]])
	var probe := Node3D.new()
	main.add_child(probe)
	probe.global_position = at
	var ps: Array = audio.campfire(probe)
	ps[0].volume_db = -9.0
	var fire: Array = await _measure(func(): pass)
	ps[0].stop()
	_say("焚き火の床（1 m）: ピーク %.1f dB  エネルギー %.1f dB" % [fire[0], fire[1]])
	audio.set_physics_process(true)


## 仲間が動いているあいだに聞こえた音の大きさと、鳴った足音の数
func _crowd(sec: float) -> void:
	audio.log_on = true
	audio.played.clear()
	var from := rec.size()
	var t := 0.0
	while t < sec:
		await _wait(0.5)
		t += 0.5
		_fresh()
	var hist := {"0-5": 0, "5-10": 0, "10-20": 0, "20-40": 0, "40-": 0}
	var steps := 0
	for e in audio.played:
		if e.get("near", false) or not e.has("who"):
			continue
		steps += 1
		var d: float = e.dist
		hist["0-5" if d < 5.0 else "5-10" if d < 10.0 else "10-20" if d < 20.0 else "20-40" if d < 40.0 else "40-"] += 1
	var sum := 0.0
	var peak := 0.0
	var loudest := -200.0
	var block := 0.0
	var n := 0
	for i in range(from, rec.size()):
		var v: Vector2 = rec[i]
		peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
		var e2 := v.x * v.x + v.y * v.y
		sum += e2
		block += e2
		n += 1
		if n == 4800:   # 0.1 秒ごとの大きさのいちばん大きい所
			loudest = maxf(loudest, linear_to_db(sqrt(maxf(block / n, 1e-14))))
			block = 0.0
			n = 0
	var total := maxi(rec.size() - from, 1)
	_say("仲間 %d 人、%.0f 秒: 足音 %d（1 秒に %.1f）距離ごと %s" % [
			main.get_children().filter(func(c): return c.has_method("_roam_get_off")).size(), sec, steps, steps / sec, hist])
	_say("出口の大きさ: 平均 %.1f dB  0.1 秒ごとの最大 %.1f dB  ピーク %.1f dB" % [
			linear_to_db(sqrt(maxf(sum / total, 1e-14))), loudest, linear_to_db(maxf(peak, 1e-7))])


func _write_wav(path: String) -> void:
	var rate := int(AudioServer.get_mix_rate())
	var n := rec.size()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 4)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(rate)
	f.store_32(rate * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 4)
	for v in rec:
		f.store_16(int(clampf(v.x, -1.0, 1.0) * 32767.0) & 0xffff)
		f.store_16(int(clampf(v.y, -1.0, 1.0) * 32767.0) & 0xffff)
