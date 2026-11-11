extends Node

const Gloves := preload("res://gloves.gd")
const RemotePerson := preload("res://remote_person.gd")
const Doll := preload("res://doll.gd")
const Pipe := preload("res://net_pipe.gd")
## 通信（オンラインで一緒に遊ぶ）。Godot の高レベルの multiplayer（ENet）で、一人がホストになり、ほかの人がつなぐ。
## 起動の引数: --host でホスト、--join=IP でつなぐ（--port= で番号を替えられる。既定 PORT）。どちらもなければ一人で遊ぶ。
##
## 人: それぞれの画面が自分の体を動かし、姿（位置・向き・人形の姿勢・ソリとのかかわり）を 1 秒に SEND_HZ 回みんなへ送る。
##   受けた画面は、その人の体（remote_person.gd）に写す。
## ソリ: ホストの物理が正。ホストがソリの姿と速さを 1 秒に SLED_HZ 回送り、つなぐ側のソリはそれへなめらかに寄せる
##   （sled.gd の net_follow）。押す・紐で引く・体重移動は、ホストの画面のその人の体がホストのソリにかける。
## 仲間（CPU）: ホストの画面の bot.gd だけが動かす。姿は人と同じ形で 1 秒に SEND_HZ 回みんなへ送り、つなぐ側は届いたら体（remote_person.gd）を置く。
##   身ぶり・対決・持ち物は、人と同じ出来事でホストから配られる。人が抜けても残る。ホストが抜けたら、人と同じくいなくなる。
## --lag=ミリ秒 で、届いたものをわざと遅らせる（同じ Mac で 2 つ動かして遅れを確かめる用。片道の遅れ）

const PORT := 24680
const MAX_PEERS := 7          # ホストのほかにつなげる人数（人形が 7 体なので、合わせて 8 人まで）
const SEND_HZ := 20.0         # 自分の姿を送る回数（1 秒に）
const SLED_HZ := 30.0         # ホストがソリの姿を送る回数（1 秒に）。止まっているソリは STILL_HZ
const STILL_HZ := 2.0
const FAR_EVERY := 4          # どの人からも遠い仲間の姿を、SEND_HZ の何回に 1 回送るか

static var boot := {}         # スタート画面で選んだ始め方（{"host": "1"} か {"join": 番号}）。読み直した main.gd が引数に足す

var main: Node3D
var online := false
var remotes := {}             # 通信の番号 → その人の体（remote_person.gd）
var cpus := {}                # つなぐ側: 仲間の人の番号 → その体（remote_person.gd）。来ている人の数には入れない
var lag := 0.0                # 届いたものを遅らせる (s)
var _send_t := 0.0
var _cpu_tick := 0
var _port := PORT
var _sled_t := {}             # ソリ → 送るまでの残り (s)


var _fast: Node              # 人の姿（届かなくてよい。流れ 1）
var _sleds: Node             # ソリの姿（届かなくてよい。流れ 2）
var _sure: Node              # 出来事（確かに届く。流れ 0）


func _ready() -> void:
	_fast = _pipe("Fast", MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 1)
	_sleds = _pipe("Sleds", MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 2)
	_sure = _pipe("Sure", MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)


## 通信の口（net_pipe.gd）を置く。口は 1 つのノードに 1 つだけ（番号がずれないように）
func _pipe(n: String, mode: MultiplayerPeer.TransferMode, channel: int) -> Node:
	var p := Pipe.new()
	p.name = n
	p.net = self
	p.rpc_config("_in", {"rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "transfer_mode": mode, "call_local": false, "channel": channel})
	add_child(p)
	return p


## 届いた。中身は [何か, …]。ホストからしか来ないはずのものは、ホスト（1）から来たときだけ受ける
func receive(pid: int, m: Array) -> void:
	if m.is_empty():
		return
	if lag > 0.0:
		await get_tree().create_timer(lag, true, true).timeout
	if _moving:   # ホストのワールドへ移るところ: 読み直すまで何も受けない
		return
	var from_host := pid == 1
	match String(m[0]):
		"world":
			if from_host:
				_world(String(m[1]))
		"state":
			_state(pid, m[1])
		"sled":
			if from_host:
				_sled(m[1], m[2], m[3], m[4])
		"bigball":
			if from_host:
				_bigball(int(m[1]), m[2], m[3], m[4], float(m[5]), int(m[6]) if m.size() > 6 else 0, int(m[7]) if m.size() > 7 else -1)
		"cpu":
			if from_host:
				_cpu(int(m[1]), m[2])
		"cpu_gone":
			if from_host:
				_cpu_gone(int(m[1]))
		"up":
			_up(pid, m[1], m[2], m[3])
		"down":
			if from_host:
				_down(m[1], m[2], m[3])
		"balls":
			if from_host:
				main.emotes.balls[int(m[1])] = int(m[2])
		"snap":
			if from_host:
				main.craft.load_snapshot(m[1])
				main.emotes.load_snapshot(m[2])
				if main.get("damp"):
					main.damp.load_snapshot(m[3])
				if main.get("seats"):
					main.seats.load_snapshot(m[4])
		"told":
			if from_host:
				_told(m[1])
		"reset":
			if is_host():
				main.reset_sled()


## 起動の引数から、ホストになるか、つなぐ。どちらでもなければ false（一人で遊ぶ）
func start(args: Dictionary) -> bool:
	if not (args.has("host") or args.has("join")):
		return false
	lag = float(args.get("lag", "0")) / 1000.0
	var port := int(args.get("port", str(PORT)))
	_port = port
	var peer := ENetMultiplayerPeer.new()
	var err: Error
	if args.has("host"):
		err = peer.create_server(port, MAX_PEERS)
	else:
		err = peer.create_client(String(args["join"]), port)
	if err != OK:
		push_error("通信を始められない: %s" % error_string(err))
		_back_to_start("host" if args.has("host") else "join")
		return false
	if not args.has("host"):
		peer.get_peer(1).set_timeout(0, 4000, 8000)   # つながらないときは 8 秒ほどであきらめる（ENet の既定は 30 秒ほど）
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer)
	multiplayer.peer_disconnected.connect(_on_gone)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_host_gone)
	online = true
	print("ホストになった: ポート %d" % port if is_host() else "つなぎにいく: %s:%d" % [args["join"], port])
	for s in get_tree().get_nodes_in_group("sleds"):
		follow(s)
	get_tree().node_added.connect(_on_node_added)
	return true


## つなぐ側で、ホストとつながっている
func joined() -> bool:
	return online and not is_host() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return online and multiplayer.is_server()


## つなぐ側: ソリをホストの姿に寄せる（自分では物理で動かさない）
func follow(s: Node) -> void:
	if online and not is_host() and s is RigidBody3D and "net_follow" in s:
		s.net_follow = true


func _on_node_added(n: Node) -> void:
	follow(n)   # あとから出たソリ（米袋など）。グループに入るのは _ready なので、ここでは見ない


## つなぐ側の、自分が来た順の小さな番号（1〜）。始める所を横へずらすのに使う
func spawn_slot() -> int:
	return 0 if not online or is_host() else 1 + absi(multiplayer.get_unique_id()) % 6


func sled_at(path: NodePath) -> RigidBody3D:
	if path.is_empty():
		return null
	return main.get_node_or_null(path) as RigidBody3D


func _on_peer(pid: int) -> void:
	if remotes.has(pid):
		return
	remotes[pid] = _add_body(pid, "Remote%d" % pid)
	print("来た: 番号 ", pid)
	if is_host():
		_sure.rpc_id(pid, "_in", ["world", main.stage])   # つなぐ側のワールドがちがえば、ホストのワールドで作り直してつなぎ直す（_world）
		_sure.rpc_id(pid, "_in", ["snap", main.craft.snapshot(), main.emotes.snapshot(), main.damp.snapshot() if main.get("damp") else {},
			main.seats.snapshot() if main.get("seats") else {}])


var _moving := false

## つなぐ側: ホストのワールドを聞いた。ちがうワールドなら、ホストのワールドで世界を作り直して、同じ番号へつなぎ直す
func _world(w: String) -> void:
	if w == main.stage or not w in main.WORLDS:
		return
	print("ホストのワールドへ移る: ", w)
	_moving = true
	boot["world"] = w
	if not boot.has("join"):   # 引数でつないだとき: 引数を写す（読み直すと引数は残るが、ワールドは boot から足す）
		boot["join"] = String(main.args.get("join", ""))
		if main.args.has("port"):
			boot["port"] = main.args["port"]
	var st = load("res://start.gd")
	st.done = true
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().reload_current_scene.call_deferred()


## ほかの人（仲間）の体を置く
func _add_body(id: int, nm: String) -> RemotePerson:
	var r := RemotePerson.new()
	r.name = nm
	r.peer = id
	r.net = self
	r.position = main.start_pos()
	main.add_child(r)
	var au := main.get_node_or_null("Audio")
	if au and au.has_method("add_walker"):   # 足音も、自分や仲間と同じ決まりで（audio.gd）
		au.add_walker(r, true)
	return r


func _on_gone(pid: int) -> void:
	var r = remotes.get(pid)
	remotes.erase(pid)
	if r and is_instance_valid(r):
		r._leave()
		r.queue_free()
	if main.get("seats"):
		main.seats.forget(pid)
	if is_host():
		for st in main.binocular_stands:
			if int(st.who) == pid:
				main.craft.send({"kind": "scope_off", "who": pid, "stand": st.index})   # 双眼鏡台をのぞいたまま帰った人の分を空ける
	print("帰った: 番号 ", pid)


func _on_connected() -> void:
	print("つながった: 番号 ", multiplayer.get_unique_id())
	for p in _pending:
		p[1]["frame"] = Doll.frame_index() + 1
		_sure.rpc_id(1, "_in", ["up", p[0], p[1], Doll.frame_index()])
	_pending.clear()


func _on_failed() -> void:
	print("つながらなかった")
	if not _back_to_start("join"):
		online = false   # 引数で始めたときは、一人で続ける


## スタート画面から始めた通信が切れたら、スタート画面へ戻る（つなぐの札に×）。引数で始めたときは、一人で続ける
func _back_to_start(why: String) -> bool:
	if boot.is_empty():
		return false
	var st = load("res://start.gd")
	st.fail = why
	leave()
	return true


## 通信をやめて、スタート画面へ戻る（設定の「スタート画面へ」）
func leave() -> void:
	var st = load("res://start.gd")
	st.force = true
	boot = {}
	online = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().reload_current_scene.call_deferred()


func _exit_tree() -> void:
	for sig in [multiplayer.peer_connected, multiplayer.peer_disconnected, multiplayer.connected_to_server,
			multiplayer.connection_failed, multiplayer.server_disconnected]:
		for c in sig.get_connections():
			if c.callable.get_object() == self:
				sig.disconnect(c.callable)


func _on_host_gone() -> void:
	print("ホストが帰った")
	if _back_to_start("gone"):
		return
	for pid in remotes.keys():
		_on_gone(pid)
	for id in cpus:   # 仲間を動かしていたのはホストの画面
		var r = cpus[id]
		r._leave()
		r.queue_free()   # 頭・肩の小物とミニオンも、持ち主が消えると消える（companions.gd）
		if main.get("seats"):
			main.seats.forget(id)
	cpus.clear()
	for s in get_tree().get_nodes_in_group("sleds"):
		if "net_follow" in s:
			s.net_follow = false   # ここからは自分の画面の物理で
	online = false


var _note_t := 0.0

## 設定の画面に、通信の様子を書く（ホストは友達に教える番号も）
func _update_note(dt: float) -> void:
	_note_t -= dt
	var st = main.settings
	if _note_t > 0.0 or st == null or st.net_note == null:
		return
	_note_t = 1.0
	if not online:
		st.net_note.text = ""
	elif is_host():
		st.net_note.text = "ホスト　番号 %s　ポート %d　来ている人 %d" % [load("res://start.gd").my_address(), _port, remotes.size()]
	else:
		var ok := multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		st.net_note.text = "つないでいる　ほかの人 %d" % remotes.size() if ok else "つないでいるところ"


func _physics_process(dt: float) -> void:
	_update_note(dt)
	if not online or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_send_t -= dt
	if _send_t <= 0.0:
		_send_t = 1.0 / SEND_HZ
		if main.player:
			_fast.rpc("_in", ["state", _my_state()])
		if is_host() and not remotes.is_empty():
			_cpu_tick += 1
			for b in get_tree().get_nodes_in_group("bots"):
				if not b.far or (_cpu_tick + b.id) % FAR_EVERY == 0:   # どの人からも遠い仲間は、回数を減らす
					_fast.rpc("_in", ["cpu", b.id, _bot_state(b)])
	if is_host():
		for s in get_tree().get_nodes_in_group("sleds"):
			var t: float = _sled_t.get(s, 0.0) - dt
			if t <= 0.0:
				var rb := s as RigidBody3D
				var still := rb.linear_velocity.length() < 0.05 and rb.angular_velocity.length() < 0.05
				t = 1.0 / (STILL_HZ if still else SLED_HZ)
				_sleds.rpc("_in", ["sled", main.get_path_to(rb), rb.global_transform, rb.linear_velocity, rb.angular_velocity])
			_sled_t[s] = t
		# 転がす大玉（big_ball.gd）: ソリと同じ流れで、半径と、固めた手袋の段（gloves.gd の番号）と置いた人も（縫い目の形・色と柄が決まる。ball_stitches.gd）
		for b in get_tree().get_nodes_in_group("big_balls"):
			if b.broken:
				continue
			var t: float = _sled_t.get(b, 0.0) - dt
			if t <= 0.0:
				var still: bool = b.linear_velocity.length() < 0.05 and b.angular_velocity.length() < 0.05
				t = 1.0 / (STILL_HZ if still else SLED_HZ)
				_sleds.rpc("_in", ["bigball", b.ball_id, b.global_transform, b.linear_velocity, b.angular_velocity, b.r, Gloves.rank(b.pack), b.maker])
			_sled_t[b] = t
		for k in _sled_t.keys():
			if not is_instance_valid(k):
				_sled_t.erase(k)


## 自分の姿（remote_person.gd の put が読む）。人形の姿勢は、自分の人形にいま入っている値をそのまま
func _my_state() -> Dictionary:
	var p: CharacterBody3D = main.player
	if main.get("ghost") and main.ghost.active:
		return main.ghost.net_state()   # 霊体（ghost.gd）: 見えないあいだは位置も送らない
	var s := _body_state(p, int(p.mode))
	match int(p.mode):
		1:   # つかんでいる
			s["h"] = p.handle
			s["pd"] = p.push_world if p.pushing else Vector3.ZERO
		2:   # 乗っている
			s["st"] = p.seat
			s["l"] = p.ride_lean
		3:   # 紐
			s["rh"] = p.rope_hand()
	if p.ball_pushed and is_instance_valid(p.ball_pushed):   # 転がす大玉を押している（big_ball.gd）: 玉の番号と、押す向き（長さが強さ）
		s["bp"] = [p.ball_pushed.ball_id, p.ball_push_dir]
	return s


## 仲間の姿（ホスト。人の姿と同じ形で、remote_person.gd の put が読む）
func _bot_state(b: CharacterBody3D) -> Dictionary:
	var m: int = b.net_mode()
	var s := _body_state(b, m)
	s["wv"] = b.doll.waving
	match m:
		1:   # つかんでいる
			s["h"] = b.handle
			s["pd"] = b.push_world
		2:   # 乗っている
			s["st"] = b.seat
			s["l"] = b.get("_lean_now")
	return s


## 人と仲間に共通の姿: 位置・向き・人形の姿勢・触っているソリ・紙の水
func _body_state(p: CharacterBody3D, mode: int) -> Dictionary:
	var d = p.doll
	var s := {"p": p.global_position, "y": p.rotation.y, "m": mode, "d": d.kind,
		"e": d.effort, "dr": d.dragged, "air": d.airborne, "f": d.facing, "g": d.gaze, "ln": d.lean,
		"c": d.crouch, "pt": d.point, "ps": d.point_sides, "ss": d.sit_stage, "sd": d.seat_drop, "se": d.seat_edge,
		"so": d.seat_soft, "pk": d.peek}
	if p.sled and is_instance_valid(p.sled):
		s["sl"] = main.get_path_to(p.sled)
	if not d.eat_table.is_empty():   # 机のある席の料理（table_eat.gd）: 皿の所・品・食べた口数
		s["te"] = d.eat_table
	if d.rock_axis != Vector3.ZERO:   # 揺り椅子・ビーズクッションで体ごと傾く（hearth_nook.gd）
		s["ra"] = d.rock_axis
		s["rk"] = d.rock
		s["rp"] = d.rock_at
		s["rt"] = d.rock_turns
		s["rr"] = d.rock_roll
	if d.flung != 0:   # ソリに轢かれて吹き飛んでいる（flung.gd）。回る角は送らず、それぞれの人形がコマで数える
		s["fl"] = d.flung
		s["fd"] = d.flung_dir
		s["fs"] = d.flung_spin
		s["fn"] = d.flung_n
		s["fh"] = d.flung_hops
	# 体の調子: 紙の水（damp.gd、整数）。ホストの画面で押す力に効き、ほかの画面で人形の見た目に出る
	if main.damp:
		s["dw"] = int(roundf(main.damp.water_of(p.id)))
	return s


# ---- 出来事（身ぶり・クラフト）: つなぐ側 → ホスト → 全員 -------------------------------------
# 出来事のコマ（frame・until）は、送る画面の姿勢の時計で書いてある。受けた画面は、送った画面の「いま」との差で
# 自分の時計に直す（届いたらすぐ、次のコマから動く）

var _pending := []            # つながる前に出した出来事 [種類, 出来事]（つながったら送る）


## つなぐ側: 出来事をホストへ
func up(what: String, ev: Dictionary) -> void:
	if joined():
		_sure.rpc_id(1, "_in", ["up", what, ev, Doll.frame_index()])
	else:
		_pending.append([what, ev])


func _up(pid: int, what: String, ev: Dictionary, at: int) -> void:
	if not is_host():
		return
	ev = _rebase(ev, at)
	ev["who"] = pid   # 人の番号は通信の番号（ほかの人の名で出させない）
	match what:
		"emote":
			main.emotes._apply(ev)
		"craft":
			if not main.craft.wallets.has(pid):
				main.craft.join(pid)
			main.craft._apply(ev)
		"duel":
			if main.get("duel"):
				main.duel._apply(ev)
		"seat":
			if main.get("seats"):
				main.seats.from_net(ev)
				down("seat", ev)
		"lift":   # 天下森のリフト: つなぐ側のソリを椅子に吊る（tenkamori_lift.gd の carry。ソリの物理はホストが動かす）
			var lf := main.get_node_or_null("Site/Lift")
			var sl := sled_at(NodePath(String(ev.get("sled", ""))))
			if lf and sl:
				if ev.get("drop", false):
					lf.drop(sl)
				else:
					lf.carry(sl, int(ev.chair), int(ev.side))


## ホスト: 確かめた出来事を、つなぐ側の全員へ
func down(what: String, ev: Dictionary) -> void:
	if is_host() and not remotes.is_empty():
		_sure.rpc("_in", ["down", what, ev, Doll.frame_index()])


func _down(what: String, ev: Dictionary, at: int) -> void:
	ev = _rebase(ev, at)
	match what:
		"emote":
			main.emotes.from_host(ev)
		"damp":
			main.damp.apply_net(ev)
		"duel":
			if main.get("duel"):
				main.duel.from_host(ev)
		"seat":
			if main.get("seats") and int(ev.who) != multiplayer.get_unique_id():
				main.seats.from_net(ev)
		"craft":
			main.craft.replay = true
			if not main.craft._apply(ev):
				push_warning("ホストの出来事をなぞれなかった: %s" % ev)
			main.craft.replay = false


## ホスト: 雪玉の数（出来事にはしない。配り役の数を合わせるだけ）
func down_balls(id: int, n: int) -> void:
	if is_host() and not remotes.is_empty():
		_sure.rpc("_in", ["balls", id, n])


func _rebase(ev: Dictionary, at: int) -> Dictionary:
	var d := Doll.frame_index() - at
	for k in ["frame", "until"]:
		if ev.has(k):
			ev[k] = int(ev[k]) + d
	return ev


## ほかの人の姿が届いた
func _state(pid: int, s: Dictionary) -> void:
	if not remotes.has(pid):
		_on_peer(pid)
	remotes[pid].put(s)


## 仲間の姿が届いた（はじめて届いたら、体を置く。あとから来た人にも、これで見える）。頭・肩の小物とミニオンも、ホストの画面と同じに
## ホスト: 設定で CPU の数を減らして、仲間を消した（main.gd の set_cpu_count）。つなぐ側の体も消してもらう
func cpu_gone(id: int) -> void:
	if online and is_host() and not remotes.is_empty():
		_sure.rpc("_in", ["cpu_gone", id])


## つなぐ側: 仲間が消えた。体を片付け、あとから遅れて届く姿（"cpu"）では作り直さない（仲間の番号は使い回されない）
func _cpu_gone(id: int) -> void:
	_cpus_gone[id] = true
	var r = cpus.get(id)
	cpus.erase(id)
	if r and is_instance_valid(r):
		r._leave()
		r.queue_free()   # 頭・肩の小物とミニオンも、持ち主が消えると消える（companions.gd）
	if main.get("seats"):
		main.seats.forget(id)


var _cpus_gone := {}           # つなぐ側: 消えた仲間の番号


func _cpu(id: int, s: Dictionary) -> void:
	if _cpus_gone.has(id):
		return
	if not cpus.has(id):
		cpus[id] = _add_body(id, "Cpu%d" % id)
		main._add_pals(cpus[id])
	cpus[id].put(s)


## ホストの大玉の姿が届いた。まだない玉（あとから来た人）は、ここで置く
func _bigball(id: int, at: Transform3D, lv: Vector3, av: Vector3, r: float, grade := 0, maker := -1) -> void:
	var b: RigidBody3D = main.emotes.big_balls.get(id)
	if b == null:
		b = main.emotes._spawn_big({"ball": id, "point": at.origin - Vector3.UP * r, "r": r, "who": maker})
	if is_instance_valid(b) and not b.broken:
		b.net_put(at, lv, av, r)
		if b.maker != maker:   # 置いた人の柄で縫う
			b.maker = maker
			b.refresh_stitch()
		b.pack = Gloves.ORDER[grade - 1] if grade > 0 and grade <= Gloves.ORDER.size() else ""


## ホストのソリの姿が届いた
func _sled(path: NodePath, at: Transform3D, lv: Vector3, av: Vector3) -> void:
	var s := sled_at(path)
	if s and "net_follow" in s:
		s.net_put(at, lv, av)


## その人の画面に、ソリから手を離す・降りることを伝える（ホストの画面でソリが決めたとき）
func tell(pid: int, what: String) -> void:
	if is_host():
		_sure.rpc_id(pid, "_in", ["told", what])


func _told(what: String) -> void:
	var p = main.player
	if p == null:
		return
	match what:
		"let_go":
			p.let_go()
		"get_off":
			p.get_off()


## ソリを戻す（Backspace）。つなぐ側はホストに頼む
func reset_sled() -> void:
	if online and not is_host():
		_sure.rpc_id(1, "_in", ["reset"])
	else:
		main.reset_sled()
