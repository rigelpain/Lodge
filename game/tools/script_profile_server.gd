extends SceneTree
## ゲームの GDScript のどの関数が時間を使っているかを、エディタなしで測る（Godot のリモートデバッガの口を使う）。
##   1) Godot --headless --path game -s res://tools/script_profile_server.gd -- --out=/path/prof.txt --from=30 --secs=40
##   2) Godot --path game --remote-debug tcp://127.0.0.1:6007 -s res://tools/fps_soak.gd -- ...
## 起動から --from 秒たったところから --secs 秒のあいだ、関数ごとの 1 コマあたりの時間（自分だけ）を足して、多い順に書き出す。
## そのあとに、関数ごとの「1 コマでいちばん長くかかったとき」を長い順に書く（ときどきの引っかかりの元を探す用）。
## 計測をつなぐと読み込みが何倍も遅くなる。--from は読み込みが終わったあとにする（測り始めるまでは遅くならない。ゲームが先に終わるとコマ数 0 になる）。
## --trace: 知らせの種類ごとに、出した糸の番号を数える（何も届かないときの確かめ用）

const PORT := 6007

var args := {}
var srv := TCPServer.new()
var peer: StreamPeerTCP
var stream := PacketPeerStream.new()
var tid := 0
var armed := false
var names := {}
var self_ms := {}
var total_ms := {}
var calls := {}
var frames := 0
var frame_ms := 0.0
var script_ms := 0.0
var t0 := 0
var kinds := {}
var worst_ms := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	srv.listen(PORT, "127.0.0.1")
	stream.input_buffer_max_size = 16 * 1024 * 1024
	stream.output_buffer_max_size = 1024 * 1024
	print("待ち受け ", PORT)


func _send(cmd: String, data: Array) -> void:
	stream.put_var([cmd, tid, data])


func _process(_dt: float) -> bool:
	if peer == null:
		if srv.is_connection_available():
			peer = srv.take_connection()
			stream.stream_peer = peer
			t0 = Time.get_ticks_msec()
			print("つながった")
		return false
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_write()
		quit()
		return true
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	while stream.get_available_packet_count() > 0:
		var m = stream.get_var()
		if not (m is Array) or (m as Array).size() < 3:
			continue
		var cmd: String = m[0]
		if tid == 0:
			tid = m[1]   # 最初の知らせ（set_pid）を出した糸 = ゲームのメインの糸。あとの知らせ（output など）は別の糸からも来るので、上書きしない
			             # （上書きすると、測り始めの合図を別の糸あてに送ってしまい、何も届かないことがあった。2026-11-14）
		kinds[cmd] = int(kinds.get(cmd, 0)) + 1
		if args.has("trace"):   # 確かめ用: 知らせの種類ごとに、出した糸の番号を数える
			var tk := "%s@%d" % [cmd, int(m[1])]
			kinds[tk] = int(kinds.get(tk, 0)) + 1
		if cmd == "servers:function_signature":
			var sig: Array = m[2]
			names[int(sig[1])] = String(sig[0])
		elif cmd == "servers:profile_frame":
			if secs >= float(args.get("from", "30")):
				_frame(m[2])
	if not armed and tid != 0 and secs >= float(args.get("from", "30")) - 2.0:
		armed = true
		_send("set_skip_breakpoints", [true, true])
		_send("profiler:servers", [true, [8192]])
		print("測り始め 糸 %d 秒 %.1f" % [tid, secs])
	if armed and secs >= float(args.get("from", "30")) + float(args.get("secs", "40")):
		_write()
		quit()
		return true
	return false


func _frame(a: Array) -> void:
	var i := 0
	var fn: int = a[i]
	i += 1
	var ft: float = a[i]
	i += 1
	i += 3   # process, physics, physics_frame
	var st: float = a[i]
	i += 1
	frames += 1
	frame_ms += ft * 1000.0
	script_ms += st * 1000.0
	var ns: int = a[i]
	i += 1
	for _k in ns:
		i += 1   # 名前
		var nf: int = a[i]
		i += 1
		i += nf   # 名前と時間の組の数 × 2 で入っている
	var nscr: int = a[i]   # 関数の数 × 5 で入っている
	i += 1
	for _k in nscr / 5:
		var id: int = a[i]
		var c: int = a[i + 1]
		var slf: float = a[i + 2]
		var tot: float = a[i + 3]
		i += 5
		self_ms[id] = float(self_ms.get(id, 0.0)) + slf * 1000.0
		if tot * 1000.0 > float(worst_ms.get(id, 0.0)):   # 1 コマでいちばん長くかかったとき（引っかかりの元を探す）
			worst_ms[id] = tot * 1000.0
		total_ms[id] = float(total_ms.get(id, 0.0)) + tot * 1000.0
		calls[id] = int(calls.get(id, 0)) + c
	if fn < 0:
		return


func _write() -> void:
	var ids: Array = self_ms.keys()
	ids.sort_custom(func(x, y): return self_ms[x] > self_ms[y])
	var out := FileAccess.open(args.get("out", "/tmp/prof.txt"), FileAccess.WRITE)
	var n := maxi(frames, 1)
	out.store_line("コマ数 %d 1 コマの時間 %.2f ms スクリプトの時間 %.2f ms  種類 %s" % [frames, frame_ms / n, script_ms / n, str(kinds)])
	out.store_line("自分ms/コマ  合計ms/コマ  呼ぶ回数/コマ  関数")
	for id in ids.slice(0, 400):
		out.store_line("%8.3f %8.3f %9.1f  %s" % [self_ms[id] / n, total_ms[id] / n, float(calls[id]) / n, names.get(id, str(id))])
	out.store_line("")
	out.store_line("1 コマでいちばん長くかかったとき（合計 ms。引っかかりの元）")
	var wids: Array = worst_ms.keys()
	wids.sort_custom(func(x, y): return worst_ms[x] > worst_ms[y])
	for id in wids.slice(0, 60):
		out.store_line("%8.2f  %s" % [worst_ms[id], names.get(id, str(id))])
	out.close()
	print("書いた")
