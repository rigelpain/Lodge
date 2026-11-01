extends Node

const RemotePerson := preload("res://remote_person.gd")
## 通信（オンラインで一緒に遊ぶ）。Godot の高レベルの multiplayer（ENet）で、一人がホストになり、ほかの人がつなぐ。
## 起動の引数: --host でホスト、--join=IP でつなぐ（--port= で番号を替えられる。既定 PORT）。どちらもなければ一人で遊ぶ。
##
## 人: それぞれの画面が自分の体を動かし、姿（位置・向き・人形の姿勢・ソリとのかかわり）を 1 秒に SEND_HZ 回みんなへ送る。
##   受けた画面は、その人の体（remote_person.gd）に写す。
## ソリ: ホストの物理が正。ホストがソリの姿と速さを 1 秒に SLED_HZ 回送り、つなぐ側のソリはそれへなめらかに寄せる
##   （sled.gd の net_follow）。押す・紐で引く・体重移動は、ホストの画面のその人の体がホストのソリにかける。
## --lag=ミリ秒 で、届いたものをわざと遅らせる（同じ Mac で 2 つ動かして遅れを確かめる用。片道の遅れ）

const PORT := 24680
const MAX_PEERS := 7          # ホストのほかにつなげる人数（人形が 7 体なので、合わせて 8 人まで）
const SEND_HZ := 20.0         # 自分の姿を送る回数（1 秒に）
const SLED_HZ := 30.0         # ホストがソリの姿を送る回数（1 秒に）。止まっているソリは STILL_HZ
const STILL_HZ := 2.0

static var boot := {}         # スタート画面で選んだ始め方（{"host": "1"} か {"join": 番号}）。読み直した main.gd が引数に足す

var main: Node3D
var online := false
var remotes := {}             # 通信の番号 → その人の体（remote_person.gd）
var lag := 0.0                # 届いたものを遅らせる (s)
var _send_t := 0.0
var _port := PORT
var _sled_t := {}             # ソリ → 送るまでの残り (s)


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
	if n.is_in_group("sleds"):
		follow(n)


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
	var r := RemotePerson.new()
	r.name = "Remote%d" % pid
	r.peer = pid
	r.net = self
	r.position = main.START
	main.add_child(r)
	remotes[pid] = r
	print("来た: 番号 ", pid)


func _on_gone(pid: int) -> void:
	var r = remotes.get(pid)
	remotes.erase(pid)
	if r and is_instance_valid(r):
		r._leave()
		r.queue_free()
	print("帰った: 番号 ", pid)


func _on_connected() -> void:
	print("つながった: 番号 ", multiplayer.get_unique_id())


func _on_failed() -> void:
	print("つながらなかった")
	_back_to_start("join")


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
	if _send_t <= 0.0 and main.player:
		_send_t = 1.0 / SEND_HZ
		_state.rpc(_my_state())
	if is_host():
		for s in get_tree().get_nodes_in_group("sleds"):
			var t: float = _sled_t.get(s, 0.0) - dt
			if t <= 0.0:
				var rb := s as RigidBody3D
				var still := rb.linear_velocity.length() < 0.05 and rb.angular_velocity.length() < 0.05
				t = 1.0 / (STILL_HZ if still else SLED_HZ)
				_sled.rpc(main.get_path_to(rb), rb.global_transform, rb.linear_velocity, rb.angular_velocity)
			_sled_t[s] = t


## 自分の姿（remote_person.gd の put が読む）。人形の姿勢は、自分の人形にいま入っている値をそのまま
func _my_state() -> Dictionary:
	var p: CharacterBody3D = main.player
	var d = p.doll
	var s := {"p": p.global_position, "y": p.rotation.y, "m": int(p.mode), "d": d.kind,
		"e": d.effort, "dr": d.dragged, "air": d.airborne, "f": d.facing, "g": d.gaze, "ln": d.lean,
		"c": d.crouch, "pt": d.point, "ps": d.point_sides, "ss": d.sit_stage, "sd": d.seat_drop}
	if p.sled and is_instance_valid(p.sled):
		s["sl"] = main.get_path_to(p.sled)
	# 体の調子: 紙の湿り気（damp.gd、整数）と食べたぬくもり（warmth.gd）。ホストの画面で押す力に効き、ほかの画面で人形の見た目に出る
	if main.damp:
		s["dv"] = int(roundf(main.damp.value(p.id)))
	if main.warmth:
		s["wf"] = snappedf(float(main.warmth.food.get(p.id, 0.0)), 0.01)
	match int(p.mode):
		1:   # つかんでいる
			s["h"] = p.handle
			s["pd"] = p.push_world if p.pushing else Vector3.ZERO
		2:   # 乗っている
			s["st"] = p.seat
			s["l"] = p.ride_lean
		3:   # 紐
			s["rh"] = p.rope_hand()
	return s


## ほかの人の姿が届いた
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _state(s: Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if lag > 0.0:
		await get_tree().create_timer(lag, true, true).timeout
	if not remotes.has(pid):
		_on_peer(pid)
	remotes[pid].put(s)


## ホストのソリの姿が届いた
@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _sled(path: NodePath, at: Transform3D, lv: Vector3, av: Vector3) -> void:
	if lag > 0.0:
		await get_tree().create_timer(lag, true, true).timeout
	var s := sled_at(path)
	if s and "net_follow" in s:
		s.net_put(at, lv, av)


## その人の画面に、ソリから手を離す・降りることを伝える（ホストの画面でソリが決めたとき）
func tell(pid: int, what: String) -> void:
	if is_host():
		_told.rpc_id(pid, what)


@rpc("authority", "call_remote", "reliable")
func _told(what: String) -> void:
	if lag > 0.0:
		await get_tree().create_timer(lag, true, true).timeout
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
		_ask_reset.rpc_id(1)
	else:
		main.reset_sled()


@rpc("any_peer", "call_remote", "reliable")
func _ask_reset() -> void:
	if is_host():
		main.reset_sled()
