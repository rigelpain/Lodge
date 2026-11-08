extends CharacterBody3D

const Doll := preload("res://doll.gd")
const SackLook := preload("res://sack_look.gd")
const Rolled := preload("res://rolled.gd")
const Ghost := preload("res://ghost.gd")
## 通信でつないでいるほかの人の体（net.gd が置く）。動きはその人の画面が決め、ここは届いた姿を写す。
## ソリには、あなたや仲間と同じ口（take_handle・push・mount・lean・pull_rope）でかかわる。
## 力をかけるのはどの画面でも同じに呼ぶが、効くのはホストの画面だけ（つなぐ側のソリは、ホストのソリの姿を写しているので）。
## 体の当たりは持たない（届いた位置へ置き直すので、ソリや人を押してしまわないように）
## 体の調子（紙の湿り気・食べたぬくもり）もその人の画面が決めて届く。押す・引く力にはその値を掛ける（player.gd と同じ）
## つなぐ側の画面の仲間（CPU）の体も、これ（cpu）。動かすのはホストの画面の bot.gd で、ここは届いた姿を写す。番号はホストの画面の番号

enum Mode { WALK, GRIP, RIDE, ROPE, SIT, DRUM }   # player.gd の Mode と同じ並び
const STALE := 0.5           # これより長く届かなければ、押す・引く・体重移動をやめる (s)
const PULL := 12.0           # 届いた位置へ寄る速さ（1/s）
const SNAP := 4.0            # これより離れていたら、寄らずに置き直す (m)

var peer := 0                # この人の通信の番号（仲間は、ホストの画面での人の番号）
var ride_lean := Vector3.ZERO   # 乗っているときの体重移動（一緒に乗った仲間が合わせる。bot.gd）
var net: Node                # net.gd
var doll: Doll
var sled: RigidBody3D        # いま触っているソリ（来た姿の sled から）
var mode := Mode.WALK
var handle := Vector3.INF    # つかんでいる所（ソリの座標）
var seat := Vector3.INF      # 乗っている席（ソリの座標）
var pushing := false
var pulling := false
var id := -1                 # 配り役（emotes.gd・craft.gd）からもらった番号。この画面の中だけの番号
var hub: Node
var craft: Node
var _drum: Node              # 入っている乾燥機（cook_station.gd）。入る・出るは出来事で配られるので、どの画面でも同じコマで回る
var damp_from_net := true    # 湿り気はその人の画面が決める（damp.gd はここでは動かさない。届いた "dw" を入れる）
var _s := {}                 # 最後に届いた姿
var _age := 99.0             # 最後に届いてから (s)
var _at := Vector3.INF       # 届いた位置
var _vel := Vector3.ZERO     # 届いた位置から測った速さ（次が届くまで、この速さで先へ進める）
var _yaw := 0.0
var ghost := 0               # 観戦モード（ghost.gd）: 0 体、1 見えない霊体、2 見える霊体
var _paint_frame := -1


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	doll = Doll.new()
	doll.kind = "kasa"
	add_child(doll)
	hub = get_parent().get_node_or_null("Emotes")
	if hub:
		id = hub.join(self)   # 通信の番号がそのまま人の番号（emotes.gd）
		hub.happened.connect(_on_emote)
	craft = get_parent().get_node_or_null("Craft")
	if craft and id >= 0:
		craft.join(id)


## 帰った: 配り役の名簿から外す（ほかの仕組みが、消えた体を読まないように）
func _exit_tree() -> void:
	if hub and hub.people.get(id) == self:
		hub.people.erase(id)


## 届いた姿を入れる（net.gd）。ソリとのかかわり（つかむ・紐・乗る）が変わったら、この画面のソリにも同じことをする
func put(s: Dictionary) -> void:
	var p: Vector3 = s.get("p", global_position)
	if _at != Vector3.INF and _age > 0.0:
		_vel = (p - _at) / maxf(_age, 0.02)
	_at = p
	_yaw = float(s.get("y", rotation.y))
	_age = 0.0
	var g := int(s.get("gh", 0))
	if _s.is_empty() or g != ghost:
		global_position = p   # はじめて届いた・霊体から戻った・霊体になった: 寄らずにその所へ
		rotation.y = _yaw
		_vel = Vector3.ZERO
	var kind := String(s.get("d", doll.kind))
	if kind != doll.kind and kind in Doll.KINDS:
		_set_doll(kind)
		_paint_frame = -1
	if g != ghost:
		_set_ghost(g)
	if ghost != 0:
		_s = s   # 霊体: ソリ・体の調子にはかかわらない
		return
	_put_state(s)
	var sl: RigidBody3D = net.sled_at(s.get("sl", NodePath())) if net else null
	var m := int(s.get("m", Mode.WALK))
	if sl and sl.racked and m in [Mode.GRIP, Mode.ROPE, Mode.RIDE]:
		m = Mode.WALK   # 立てかけ台へ呼ばれる前に送られた姿: 台のソリには触れないので、体を台へ飛ばさない（その人の画面にも、すぐ届く）
	var h: Vector3 = s.get("h", Vector3.INF)
	if sl != sled or m != mode or (m == Mode.GRIP and h != handle):
		_leave()
		sled = sl
		_enter(m, h, s.get("st", Vector3.INF))
	if mode == Mode.RIDE:
		seat = s.get("st", seat)
		ride_lean = s.get("l", Vector3.ZERO)
		_yield_seat()
	_s = s


## 観戦モードに入った・出た（ghost.gd）。霊体のあいだは名簿から外し（施設・まち針・湿り気・雪玉が見ない）、
## 見えないなら人形を隠し、見えるなら透けた紙にする。ソリから手を離して席を空ける
func _set_ghost(g: int) -> void:
	ghost = g
	if g != 0:
		_leave()
		if hub and hub.people.get(id) == self:
			hub.people.erase(id)
	elif hub and id >= 0 and not hub.people.has(id):
		hub.people[id] = self
	doll.visible = g != 1
	Ghost.paint(doll, g == 2)
	_paint_frame = Doll.frame_index()


## 体の調子が届いた（"dw" 水）
func _put_state(s: Dictionary) -> void:
	var main := get_parent()
	var dm = main.get("damp")
	if dm and s.has("dw") and id >= 0:
		dm.apply_net({"kind": "damp", "who": id, "w": s.dw})


## 乾燥機に入る出来事が配られた（cook_station.gd の begin_ride）
func enter_drum(st: Node) -> void:
	_drum = st


## 乾燥機の中にいる（とび込む・回る・とび出すあいだ）
func _in_drum() -> bool:
	if _drum and is_instance_valid(_drum) and _drum.rider == id and _drum.riding():
		return true
	_drum = null
	return false


## 紙の湿り気の押す力の倍率（damp.gd の段）
func damp_k() -> float:
	var dm = get_parent().get("damp")
	return dm.push_k(id) if dm and id >= 0 else 1.0


## それぞれの画面で同じ席に座ってしまったら、通信の番号の大きい人が空いた席へ移る（その人の画面で直す）
func _yield_seat() -> void:
	var me = net.main.player if net else null
	if me == null or me.mode != Mode.RIDE or me.sled != sled or me.seat != seat or peer > net.multiplayer.get_unique_id():
		return
	var at: Vector3 = sled.free_seat(me)
	if at != Vector3.INF:
		me.seat = at


func _set_doll(kind: String) -> void:
	var at := doll.global_transform
	doll.queue_free()
	doll = Doll.new()
	doll.kind = kind
	add_child(doll)
	doll.global_transform = at


## この人の身ぶり・声・雪玉の当たりを、人形に（判定はホストが済ませて配っている）
func _on_emote(ev: Dictionary) -> void:
	if ev.get("who", -1) == id:
		doll.play(ev)


func _leave() -> void:
	if sled:
		match mode:
			Mode.GRIP:
				sled.release_handle(self)
			Mode.ROPE:
				sled.release_rope(self)
			Mode.RIDE:
				sled.dismount(self)
				if sled.kind == "sack":
					SackLook.set_stage(sled, seat, 0)
	mode = Mode.WALK
	handle = Vector3.INF
	seat = Vector3.INF


func _enter(m: int, h: Vector3, st: Vector3) -> void:
	if sled == null and m in [Mode.GRIP, Mode.ROPE, Mode.RIDE]:
		return
	match m:
		Mode.GRIP:
			sled.take_handle(self, h)   # 同じ所を先にほかの人がつかんでいても、その人の画面ではつかめているので押す
			handle = h
		Mode.ROPE:
			sled.take_rope(self)
		Mode.RIDE:
			sled.mount(self)            # 席はその人の画面で決まった所（st）に座る
			seat = st
			if sled.kind == "sack":     # 米袋は、座った所がへこむ（player.gd・bot.gd と同じ）
				SackLook.set_stage(sled, seat, 2)
	mode = m


## ソリが手を離させた（ホストの画面で、引きずられて手がもたなかった・R で戻した）。その人の画面にも伝える
func let_go() -> void:
	if mode in [Mode.GRIP, Mode.ROPE]:
		_leave()
		if net:
			net.tell(peer, "let_go")


func get_off() -> void:
	if mode == Mode.RIDE:
		_leave()
		if net:
			net.tell(peer, "get_off")


## 紐の先を付ける所（sled_rope.gd が読む）
func rope_hand() -> Vector3:
	return _s.get("rh", global_position + Vector3.UP)


func _physics_process(dt: float) -> void:
	_age += dt
	if _s.is_empty():
		return
	var fresh := _age < STALE
	pushing = false
	pulling = false
	if ghost == 1:
		return   # 見えない霊体: 体はその場で消えたまま
	if ghost == 2:   # 見える霊体: 届いた所へ浮かんで寄る（足音は audio.gd が出さない）
		var want := _at + _vel * minf(_age, STALE)
		global_position = want if global_position.distance_to(want) > SNAP * 4.0 else global_position.lerp(want, 1.0 - exp(-PULL * dt))
		rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-PULL * dt))
		_pose_doll()
		var f := Doll.frame_index()
		if f != _paint_frame:   # 人形は部品を作り直すので、コマごとに透かし直す
			_paint_frame = f
			Ghost.paint(doll, true)
		return
	if _in_drum():
		global_position = _drum.ride_pose(Doll.frame_index()).pos
		rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-PULL * dt))
		_pose_doll()
		return
	match mode:
		Mode.RIDE:
			global_position = sled.to_global(seat)
			var l: Vector3 = _s.get("l", Vector3.ZERO)
			if fresh:
				sled.lean(l.x, l.y > 0.0, l.z > 0.0)
		Mode.GRIP:
			global_position = sled.to_global(handle)
			var dir: Vector3 = _s.get("pd", Vector3.ZERO)
			if fresh and dir != Vector3.ZERO:
				sled.push(dir, global_position + Vector3.UP * 0.5, self, damp_k())
				pushing = true
		_:
			var want := _at + _vel * minf(_age, STALE)
			if global_position.distance_to(want) > SNAP:
				global_position = want
			else:
				global_position = global_position.lerp(want, 1.0 - exp(-PULL * dt))
			if mode == Mode.ROPE and fresh:
				pulling = sled.pull_rope(rope_hand(), damp_k()) > 0.0
			var b := _ball_pushed()
			if b and fresh:
				b.push(_s.bp[1], damp_k(), craft.glove_grade(id) if craft else "")   # 転がす大玉を押す（効くのはホストの画面だけ。手袋の段で押す力が違う。big_ball.gd）
	rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-PULL * dt))
	_pose_doll()


## その人が押している大玉（届いた "bp" の番号から。なければ null）
func _ball_pushed() -> RigidBody3D:
	if not _s.has("bp") or hub == null or mode != Mode.WALK:
		return null
	return hub.big_ball(int(_s.bp[0]))


## 人形に、その人の画面の人形と同じ姿勢を伝える（姿勢は人形が 12 コマで刻む）
func _pose_doll() -> void:
	doll.act = [Doll.Act.WALK, Doll.Act.PUSH, Doll.Act.RIDE, Doll.Act.ROPE, Doll.Act.SIT, Doll.Act.SIT][mode]
	doll.sled = sled
	doll.grip = handle if mode == Mode.GRIP else Vector3.INF
	doll.effort = bool(_s.get("e", false))
	doll.dragged = bool(_s.get("dr", false))
	doll.airborne = bool(_s.get("air", false))
	doll.flung = int(_s.get("fl", 0))   # ソリに轢かれて吹き飛んでいる（flung.gd）
	if doll.flung != 0:
		doll.flung_dir = _s.get("fd", Vector3.ZERO)
		doll.flung_spin = float(_s.get("fs", 0.0))
		doll.flung_n = _s.get("fn", Vector3.UP)
		doll.flung_hops = int(_s.get("fh", 0))
	doll.facing = _s.get("f", Vector3.ZERO)
	doll.gaze = _s.get("g", Vector3.INF)
	doll.rope_hand = rope_hand() if mode == Mode.ROPE else Vector3.INF
	doll.lean = _s.get("ln", Vector2.ZERO)
	doll.crouch = bool(_s.get("c", false))
	doll.point = _s.get("pt", Vector3.INF)
	doll.point_sides = _s.get("ps", [])
	doll.sit_stage = int(_s.get("ss", 0))
	doll.seat_drop = float(_s.get("sd", 0.45))
	doll.seat_edge = float(_s.get("se", 0.2))
	doll.seat_soft = bool(_s.get("so", false))
	doll.eat_table = _s.get("te", {})
	doll.peek = String(_s.get("pk", ""))   # 双眼鏡をのぞいている（両手を目へ）
	doll.rock_axis = _s.get("ra", Vector3.ZERO)   # 揺り椅子・ビーズクッションで体ごと傾く
	doll.rock = float(_s.get("rk", 0.0))
	doll.rock_at = _s.get("rp", Vector3.ZERO)
	doll.rock_roll = float(_s.get("rr", 0.0))   # 揺り椅子: 弓が床を転がる
	doll.rock_turns = bool(_s.get("rt", false))   # ビーズクッション: その人の見ている向き（f）へ、12 コマで回る
	doll.waving = bool(_s.get("wv", false))   # 呼ばれて手を振る（仲間。bot.gd）
	doll.spin_axis = Vector3.ZERO
	doll.drum_fit = 1.0
	if _drum:   # 乾燥機の中: 届いた姿でなく、この画面の乾燥機のコマで（player.gd の _pose_doll と同じ）
		var pl: Dictionary = _drum.ride_pose(Doll.frame_index())
		doll.act = Doll.Act.SIT
		doll.facing = pl.face
		doll.sit_stage = pl.stage
		doll.seat_drop = preload("res://player.gd").DRUM_DROP
		doll.drum_fit = pl.get("fit", 1.0)   # 胴に収まらない大きな人形は縮める
		if pl.stage == 2:   # 胴の中: 体ごと回され、手足と頭はぶらぶら（dryer_flop.gd）
			doll.spin_axis = _drum.front()
			doll.spin = pl.spin
			doll.spin_at = _drum.drum_center()
			doll.flop = pl.get("flop", {})
	doll.gloves = craft.glove_grade(id) if craft else ""   # 雪玉ころがしの手袋（gloves.gd。はめているかは工房の配り役が知っている）
	var bp := _ball_pushed()   # 転がす大玉を押している: 両手を玉の面に
	doll.ball_at = bp.global_position if bp else Vector3.INF
	doll.ball_r = bp.r if bp else 0.0
	var ri: Array = hub.rolled_in(id) if hub else []
	doll.rolled = not ri.is_empty()
	if doll.rolled:   # 大玉に取り込まれている: 出来事 ball_in で覚えた所に、この画面の大玉と一緒に回す（rolled.gd）
		Rolled.place(doll, ri[0], ri[1], ri[2])
	# 雪玉・帯の米袋・ランタンは、配り役（ホストが決めて配った値）から。player.gd の _pose_doll と同じ
	if hub:
		var n: int = hub.balls_of(id)
		doll.holding_ball = n > 0 and (craft == null or craft.held(id).is_empty()) and hub.can_throw(id)
		doll.sleeve_balls = n - (1 if doll.holding_ball else 0)
	if craft:
		var spec: Dictionary = craft.sack(id)
		doll.belt_sack = not spec.is_empty() and craft.sack_sled(id) == null
		if not spec.is_empty():
			doll.belt_color = preload("res://fabrics.gd").color(spec.fabric) if spec.fabric != "" else preload("res://sled.gd").KINDS["sack"].color
		doll.lantern = craft.lantern(id).get("look", "")
		doll.lantern_lit = craft.lamp_on(id)
