extends CharacterBody3D

const Doll := preload("res://doll.gd")
## 通信でつないでいるほかの人の体（net.gd が置く）。動きはその人の画面が決め、ここは届いた姿を写す。
## ソリには、あなたや仲間と同じ口（take_handle・push・mount・lean・pull_rope）でかかわる。
## 力をかけるのはどの画面でも同じに呼ぶが、効くのはホストの画面だけ（つなぐ側のソリは、ホストのソリの姿を写しているので）。
## 体の当たりは持たない（届いた位置へ置き直すので、ソリや人を押してしまわないように）

enum Mode { WALK, GRIP, RIDE, ROPE, SIT }   # player.gd の Mode と同じ並び
const STALE := 0.5           # これより長く届かなければ、押す・引く・体重移動をやめる (s)
const PULL := 12.0           # 届いた位置へ寄る速さ（1/s）
const SNAP := 4.0            # これより離れていたら、寄らずに置き直す (m)

var peer := 0                # この人の通信の番号
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
var _s := {}                 # 最後に届いた姿
var _age := 99.0             # 最後に届いてから (s)
var _at := Vector3.INF       # 届いた位置
var _vel := Vector3.ZERO     # 届いた位置から測った速さ（次が届くまで、この速さで先へ進める）
var _yaw := 0.0


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
	_yaw = float(s.get("y", 0.0))
	_age = 0.0
	if _s.is_empty():
		global_position = p
		rotation.y = _yaw
	var kind := String(s.get("d", doll.kind))
	if kind != doll.kind and kind in Doll.KINDS:
		_set_doll(kind)
	var sl: RigidBody3D = net.sled_at(s.get("sl", NodePath())) if net else null
	var m := int(s.get("m", Mode.WALK))
	var h: Vector3 = s.get("h", Vector3.INF)
	if sl != sled or m != mode or (m == Mode.GRIP and h != handle):
		_leave()
		sled = sl
		_enter(m, h, s.get("st", Vector3.INF))
	if mode == Mode.RIDE:
		seat = s.get("st", seat)
		_yield_seat()
	_s = s


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
				sled.push(dir, global_position + Vector3.UP * 0.5, self, _push_k())
				pushing = true
		_:
			var want := _at + _vel * minf(_age, STALE)
			if global_position.distance_to(want) > SNAP:
				global_position = want
			else:
				global_position = global_position.lerp(want, 1.0 - exp(-PULL * dt))
			if mode == Mode.ROPE and fresh:
				pulling = sled.pull_rope(rope_hand(), _push_k()) > 0.0
	rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-PULL * dt))
	_pose_doll()


## 湿り気で変わる押す力（damp.gd。値はホストが決めているので、ホストの画面でそのまま効く）
func _push_k() -> float:
	var dm := get_parent().get_node_or_null("Damp")
	return dm.push_k(id) if dm and id >= 0 else 1.0


## 人形に、その人の画面の人形と同じ姿勢を伝える（姿勢は人形が 12 コマで刻む）
func _pose_doll() -> void:
	doll.act = [Doll.Act.WALK, Doll.Act.PUSH, Doll.Act.RIDE, Doll.Act.ROPE, Doll.Act.SIT][mode]
	doll.sled = sled
	doll.grip = handle if mode == Mode.GRIP else Vector3.INF
	doll.effort = bool(_s.get("e", false))
	doll.dragged = bool(_s.get("dr", false))
	doll.airborne = bool(_s.get("air", false))
	doll.facing = _s.get("f", Vector3.ZERO)
	doll.gaze = _s.get("g", Vector3.INF)
	doll.rope_hand = rope_hand() if mode == Mode.ROPE else Vector3.INF
	doll.lean = _s.get("ln", Vector2.ZERO)
	doll.crouch = bool(_s.get("c", false))
	doll.point = _s.get("pt", Vector3.INF)
	doll.point_sides = _s.get("ps", [])
	doll.sit_stage = int(_s.get("ss", 0))
	doll.seat_drop = float(_s.get("sd", 0.45))
	# 雪玉・帯の米袋・ランタンは、配り役（ホストが決めて配った値）から。player.gd の _pose_doll と同じ
	if hub:
		var n: int = hub.balls_of(id)
		doll.holding_ball = n > 0 and (craft == null or craft.held(id).is_empty())
		doll.sleeve_balls = n - (1 if doll.holding_ball else 0)
	if craft:
		var spec: Dictionary = craft.sack(id)
		doll.belt_sack = not spec.is_empty() and craft.sack_sled(id) == null
		if not spec.is_empty():
			doll.belt_color = preload("res://fabrics.gd").color(spec.fabric) if spec.fabric != "" else preload("res://sled.gd").KINDS["sack"].color
		doll.lantern = craft.lantern(id).get("look", "")
		doll.lantern_lit = craft.lamp_on(id)
