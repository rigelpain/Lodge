extends Node3D

const Doll := preload("res://doll.gd")
const Snowball := preload("res://snowball.gd")
const Icons := preload("res://hud_icons.gd")
## 雪合戦の対決（2026-11-02 代表）。雪玉を 1 つ以上持った 2 人が握手すると、掛金を決めて、1 対 1 の雪合戦をする。
## 流れ: 握手 → bet（掛金を決める画面。片方が額を出し、もう片方が受ける。duel_hud.gd）→ fight（60 秒。先に 3 発当てた方の勝ち）
##   → over（勝ち負けが決まった。2 人がまた握手するか、30 秒たつと、勝った人に掛金のすべてが入る）→ 消える。
## 始めるとき、それまで何個持っていても、雪玉は 3 つになる。対決中も雪玉は作れる（2026-11-02 代表）。
## フィールドは握手した所を中心に半径 5 m の円。雪に赤い毛糸の並み縫いと待ち針で描く（どの画面でも、配られた対決から作る）。
## 対決中の 2 人と、それ以外の人の雪玉は、互いに当たらない（can_hit。snowball.gd が見る）。ソリは当たる（轢かれると、のけぞる）。
## 相手の雪玉が手の届く所（CATCH_REACH）に来たとき、照準（画面のまんなか）を合わせて F で取れる（player.gd → try_catch。
## 2026-11-02 代表「キャッチはFキーにしましょう」）。
## 当てられた人は、のけぞっているあいだ（GUARD）相手の雪玉が当たらない（すり抜ける）。のけぞりで動けないうちに続けて当てられないように
## （2026-11-02 代表「硬直でチェーンするのは望ましくないですね」）。
## 判定（握手・当たり・キャッチ・掛金・払い）はホストがする。つなぐ側は send で頼み、ホストが配った対決（state）で合わせる。
## 掛金はボタン（craft.gd の stake で 2 人の財布から預かり、earn で勝った人へ。引き分けはそれぞれに戻す）。
##
## 決め方（2026-11-02 に仮で作り、2026-11-03 代表「このままでよい」）:
##   掛金は片方が額を出し、もう片方が受けると決まる（額を変えた人は受けたことになり、相手の「受ける」は外れる）。上限は 2 人の財布の少ない方。
##   60 秒たったら、当てた数の多い方の勝ち。同じなら引き分けで、掛金はそれぞれに戻す。
##   円の縁は見えない壁（出られない）。取った雪玉は手持ちに足す（上限は emotes.gd の BALL_MAX）。
##   ソリに轢かれても当たりの数には入れない（のけぞるだけ）。片方がいなくなったら（通信が切れた）、残った方の勝ち。
##   ロッジの床の上では始めない。

signal happened(ev: Dictionary)

const RADIUS := 5.0          # フィールドの半径 (m)
const FIGHT_T := 60.0        # 制限時間 (s)
const LIVES := 3             # これだけ当てられたら負け
const START_BALLS := 3       # 始めるときの雪玉
const PAY_T := 30.0          # 勝ち負けが決まってから、握手しなくても払うまで (s)
const BET_T := 60.0          # 掛金がこの秒のうちに決まらなければやめる
const CATCH_REACH := 0.8     # 手の届く所（肩の高さの、体の少し前から, m。_chest）
const CATCH_SLACK := 0.9     # ホストが確かめるときのゆとり (m)。つなぐ側の画面の雪玉は、ホストのより少し遅れている
const CATCH_AIM := 0.08      # 照準（画面のまんなか）と雪玉のずれの上限（画面の高さに対して）
const WALL := 0.3            # 見えない壁: 縁からこれだけ内側で止まる (m)
const RUN_OVER_SPEED := 3.0  # これより速いソリに触れると轢かれる (m/s)
const RUN_OVER_WAIT := 1.5   # 一度轢かれてから、次に轢かれるまで (s)
const GUARD := 1.5           # 当てられてから、相手の雪玉が当たらない長さ (s)。のけぞり（16 コマ）より少し長く
const GRACE := 0.1           # 相手の雪玉が当たってから、取りにいった知らせを待つ (s)。つなぐ人には、行き来の遅れを足す
const PINS := 12             # 待ち針の数
const DASHES := 60           # 毛糸の並み縫いの目の数

var world: Node3D            # main.gd
var hub: Node                # emotes.gd
var craft: Node              # craft.gd
var duels := {}              # 番号 → 対決 {id, a, b, at, stake, phase, hits_a, hits_b, ok_a, ok_b, winner, until}
var _next := 1
var _rings := {}             # 番号 → フィールドの印（毛糸と待ち針）
var _run_over := {}          # 人の番号 → 次に轢かれるまでの残り (s)
var _guard := {}             # 人の番号 → このコマまで当たらない（当てられた。どの画面でも、配られた struck から）
var _parked := {}            # 雪玉の番号 → 当てるのを待っている当たり {who, by, point, dir, t}


func _ready() -> void:
	if hub:
		hub.happened.connect(_on_emote)
	multiplayer.peer_connected.connect(_on_peer)


# ---------------------------------------------------------------- 調べる（どの画面でも）

## その人がかかわっている対決（どの段でも）。なければ {}
func of(who: int) -> Dictionary:
	for d in duels.values():
		if int(d.a) == who or int(d.b) == who:
			return d
	return {}


## その人が戦っている対決（fight の段）。なければ {}
func fighting(who: int) -> Dictionary:
	var d := of(who)
	return d if not d.is_empty() and d.phase == "fight" else {}


static func opponent(d: Dictionary, who: int) -> int:
	return int(d.b) if int(d.a) == who else int(d.a)


## その人の残り（相手に当てられた数を引く）
static func lives_of(d: Dictionary, who: int) -> int:
	return LIVES - int(d.hits_b if int(d.a) == who else d.hits_a)


## 段の残りの秒（fight は制限時間、over は払うまで、bet はやめるまで）
static func left_s(d: Dictionary) -> float:
	return maxf(0.0, float(int(d.until) - Doll.frame_index()) / Doll.FPS)


## 掛けられる上限（2 人の財布の少ない方）
func max_stake(d: Dictionary) -> int:
	return mini(craft.wallet(int(d.a)), craft.wallet(int(d.b))) if craft else 0


## 雪玉が当たるか: 戦っている 2 人はその 2 人の間だけ、それ以外の人はそれ以外の人の間だけ
func can_hit(thrower: int, target: int) -> bool:
	var dt := fighting(thrower)
	var dv := fighting(target)
	if dt.is_empty() and dv.is_empty():
		return true
	return not dt.is_empty() and dt == dv and not guarded(target)


## 当てられたばかりで、相手の雪玉が当たらないあいだか
func guarded(who: int) -> bool:
	return int(_guard.get(who, -1)) > Doll.frame_index()


func _net() -> Node:
	return world.get_node_or_null("Net") if world else null


func _client() -> bool:
	var net := _net()
	return net != null and net.online and not net.is_host()


## 手が届く所を測るもと: 肩の高さで、体の少し前（手を出す所。一人称の目は体のまんなかより前にあるので、目の前の玉も届く）
func _chest(who: Node3D) -> Vector3:
	var h: float = who.doll.height() if who.get("doll") else 1.6
	var fwd: Vector3 = hub._forward(who) if who.get("doll") else Vector3.ZERO
	return who.global_position + Vector3.UP * h * 0.78 + fwd * 0.3


# ---------------------------------------------------------------- 頼む（持ち主の画面）
# bet {n}: 掛金を n にする / ok: 受ける / cancel: やめる / catch {ball}: 相手の雪玉を取る

func send(ev: Dictionary) -> void:
	ev["frame"] = Doll.frame_index() + 1
	if _client():
		_net().up("duel", ev)
		return
	_apply(ev)


## F（player.gd）。手の届く所の相手の雪玉に照準が合っていれば、取りにいく（取れたかはホストが決める）。
## 取りにいったら true（振りかぶらない）
func try_catch(p: Node3D) -> bool:
	var me: int = int(p.get("id"))
	var d := fighting(me)
	var cam: Camera3D = p.get("cam")
	if d.is_empty() or cam == null:
		return false
	var b := catchable(p, cam, opponent(d, me))
	if b == null:
		return false
	send({"kind": "catch", "who": me, "ball": b.ball_id})
	return true


## 照準に合っている、手の届く相手の雪玉（なければ null）
func catchable(p: Node3D, cam: Camera3D, opp: int) -> Snowball:
	var vs := cam.get_viewport().get_visible_rect().size
	var mid := vs / 2.0
	var chest := _chest(p)
	var best: Snowball = null
	var near := INF
	for c in hub.get_children():
		if not (c is Snowball) or c.thrower != opp or c._done:
			continue
		var dist: float = c.global_position.distance_to(chest)
		if dist > CATCH_REACH or cam.is_position_behind(c.global_position):
			continue
		if cam.unproject_position(c.global_position).distance_to(mid) > CATCH_AIM * vs.y:
			continue
		if dist < near:
			near = dist
			best = c
	return best


## 戦っている人を円の中に留める（見えない壁）。持ち主の画面が、動かしたあとに呼ぶ（player.gd・bot.gd）
func keep_in(body: Node3D, who: int) -> bool:
	var d := fighting(who)
	if d.is_empty():
		return false
	var at: Vector3 = d.at
	var off := Vector2(body.global_position.x - at.x, body.global_position.z - at.z)
	var lim := RADIUS - WALL
	if off.length() <= lim:
		return false
	off = off.normalized() * lim
	body.global_position.x = at.x + off.x
	body.global_position.z = at.z + off.y
	return true


# ---------------------------------------------------------------- ホストの判定

func _apply(ev: Dictionary) -> void:
	var who: int = int(ev.get("who", -1))
	var d := of(who)
	if d.is_empty():
		return
	match ev.kind:
		"bet":
			if d.phase != "bet":
				return
			d.stake = clampi(int(ev.n), 0, max_stake(d))
			d.ok_a = who == int(d.a)   # 額を出した人は受けたことに。相手はもう一度「受ける」
			d.ok_b = who == int(d.b)
			_state(d, "bet")
		"ok":
			if d.phase != "bet":
				return
			d["ok_a" if who == int(d.a) else "ok_b"] = true
			if d.ok_a and d.ok_b:
				_start(d)
			else:
				_state(d, "bet")
		"cancel":
			if d.phase == "bet":
				_drop(d, "cancel")
		"catch":
			if d.phase == "fight":
				_catch(d, who, int(ev.get("ball", -1)))


func _on_emote(ev: Dictionary) -> void:
	if _client():
		return
	match ev.kind:
		"shake":
			if int(ev.who) < int(ev.with):   # 2 人に配られるので、片方で
				_shook(int(ev.who), int(ev.with))
		"hit":
			if ev.has("by"):
				_struck(int(ev.by), int(ev.who))


## 握手した。対決の前なら掛金の画面へ、勝ち負けが決まったあとなら払う
func _shook(a: int, b: int) -> void:
	var d := of(a)
	if not d.is_empty():
		if d.phase == "over" and opponent(d, a) == b:
			_pay(d)
		return
	if not of(b).is_empty() or hub.balls_of(a) < 1 or hub.balls_of(b) < 1:
		return
	var pa: Node3D = hub.who_of(a)
	var pb: Node3D = hub.who_of(b)
	if pa == null or pb == null:
		return
	var at := (pa.global_position + pb.global_position) * 0.5
	if world.has_method("lodge_weight") and world.lodge_weight(at.x, at.z) < 1.0:
		return   # ロッジの床の上では始めない
	if world.has_method("height"):
		at.y = world.height(at.x, at.z)
	d = {"id": _next, "a": a, "b": b, "at": at, "stake": 0, "phase": "bet", "hits_a": 0, "hits_b": 0,
		"ok_a": false, "ok_b": false, "winner": -1, "until": Doll.frame_index() + int(BET_T * Doll.FPS)}
	_next += 1
	duels[int(d.id)] = d
	_state(d, "bet")


## 2 人とも受けた: 掛金を預かって、始める
func _start(d: Dictionary) -> void:
	var n := int(d.stake)
	if n > 0:
		if craft.wallet(int(d.a)) < n or craft.wallet(int(d.b)) < n:
			d.ok_a = false
			d.ok_b = false
			d.stake = mini(n, max_stake(d))
			_state(d, "bet")
			return
		craft.send({"kind": "stake", "who": int(d.a), "n": n})
		craft.send({"kind": "stake", "who": int(d.b), "n": n})
	hub._set_balls(int(d.a), START_BALLS)
	hub._set_balls(int(d.b), START_BALLS)
	d.phase = "fight"
	d.until = Doll.frame_index() + int(FIGHT_T * Doll.FPS)
	_state(d, "start")
	for w in [d.a, d.b]:
		hub.send({"kind": "un", "who": int(w)})   # よし、とうなずく


## 雪玉が当たった（emotes.gd の hit。by は投げた人）
func _struck(by: int, who: int) -> void:
	var d := fighting(by)
	if d.is_empty() or opponent(d, by) != who:
		return
	if guarded(who):
		return   # のけぞっているあいだは数えない（同じコマに 2 つ当たったときなど）
	if by == int(d.a):
		d.hits_a = int(d.hits_a) + 1
	else:
		d.hits_b = int(d.hits_b) + 1
	_guard[who] = Doll.frame_index() + 1 + int(GUARD * Doll.FPS)
	if int(d.hits_a) >= LIVES or int(d.hits_b) >= LIVES:
		_finish(d, by)
	else:
		_state(d, "struck", {"struck": who})


## 相手の雪玉を取った（ホストの雪玉が、まだ飛んでいて手の届く所にあれば）
## ホストの雪玉がもう体に当たっていても、当てるのを待っているあいだ（park_hit）なら取れる
func _catch(d: Dictionary, who: int, ball_id: int) -> void:
	var me: Node3D = hub.who_of(who)
	var point := Vector3.INF
	var parked: Dictionary = _parked.get(ball_id, {})
	if not parked.is_empty() and int(parked.who) == who:
		_parked.erase(ball_id)
		point = parked.point
	else:
		var b: Snowball = hub.ball(ball_id)
		if b == null or me == null or b.thrower != opponent(d, who) or b._done:
			return
		if b.global_position.distance_to(_chest(me)) > CATCH_REACH + CATCH_SLACK:
			return
		point = b.global_position
	hub._set_balls(who, mini(hub.balls_of(who) + 1, hub.BALL_MAX))
	hub._emit({"kind": "catch", "who": who, "ball": ball_id, "frame": Doll.frame_index() + 1, "point": point})
	_state(d, "caught")


## 戦っている人に、相手の雪玉が当たった（ホストの雪玉が見つけた。emotes.gd）。すぐには当てず、取りにいった知らせを
## 少し待つ（つなぐ側の画面の雪玉は遅れて飛ぶので、手の届く所で取っても、ホストではもう当たっていることがある）。待ったら true
func park_hit(ball: Node3D, who: int, point: Vector3, dir: Vector3) -> bool:
	var d := fighting(who)
	if d.is_empty() or opponent(d, who) != int(ball.thrower) or int(ball.ball_id) < 0:
		return false
	_parked[int(ball.ball_id)] = {"who": who, "by": int(ball.thrower), "point": point, "dir": dir, "t": _grace(who)}
	return true


## 取りにいった知らせを待つ長さ: 自分の画面の人は GRACE、つなぐ人は行き来の遅れを足す
func _grace(who: int) -> float:
	var net := _net()
	var g := GRACE
	if net and net.online and net.remotes.has(who) and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var pk: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(who)
		if pk:
			g += pk.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0 * 1.2
		g += float(net.lag) * 2.0
	return clampf(g, GRACE, 0.6)


## 勝ち負けが決まった（winner が -1 なら引き分け）
func _finish(d: Dictionary, winner: int) -> void:
	d.phase = "over"
	d.winner = winner
	d.until = Doll.frame_index() + int(PAY_T * Doll.FPS)
	_state(d, "end")
	if winner >= 0:
		hub.send({"kind": "wa", "who": winner})
		if hub.who_of(opponent(d, winner)):
			hub.send({"kind": "nn", "who": opponent(d, winner)})


## 掛金を払う（勝った人へ 2 人分。引き分けはそれぞれへ）。対決は消える
func _pay(d: Dictionary) -> void:
	var n := int(d.stake)
	var at: Vector3 = d.at + Vector3.UP * 1.0
	if n > 0:
		if int(d.winner) >= 0:
			craft.send({"kind": "earn", "who": int(d.winner), "n": n * 2, "at": at})
		else:
			for w in [d.a, d.b]:
				craft.send({"kind": "earn", "who": int(w), "n": n, "at": at})
	_drop(d, "paid")


func _drop(d: Dictionary, cue: String) -> void:
	duels.erase(int(d.id))
	_emit({"kind": "gone", "id": int(d.id), "duel": d.duplicate(), "cue": cue, "frame": Doll.frame_index() + 1})


## 対決の今を全員に配る。cue は何が起きたか（bet・start・struck・caught・end）
func _state(d: Dictionary, cue: String, extra := {}) -> void:
	var ev := {"kind": "state", "duel": d.duplicate(), "until": int(d.until), "cue": cue, "frame": Doll.frame_index() + 1}
	ev.merge(extra)
	_emit(ev)


func _emit(ev: Dictionary) -> void:
	_show(ev)
	happened.emit(ev)
	var net := _net()
	if net and net.is_host():
		net.down("duel", ev)


## ホストが配った対決が届いた（つなぐ側。net.gd）。until は届いたときにこの画面の時計に直してある
func from_host(ev: Dictionary) -> void:
	match ev.kind:
		"state":
			var d: Dictionary = ev.duel
			d.until = int(ev.until)
			duels[int(d.id)] = d
			if ev.has("struck"):   # frame は届いたときにこの画面の時計に直してある
				_guard[int(ev.struck)] = int(ev.frame) + int(GUARD * Doll.FPS)
		"gone":
			duels.erase(int(ev.id))
	_show(ev)
	happened.emit(ev)


## あとから来た人へ、いまの対決を配る（ホスト）
func _on_peer(_pid: int) -> void:
	if _client() or not is_inside_tree():
		return
	for d in duels.values():
		_state(d, "")


func _physics_process(dt: float) -> void:
	if _client():
		return
	for bid in _parked.keys():   # 待っても取られなかった当たりを当てる
		var h: Dictionary = _parked[bid]
		h.t = float(h.t) - dt
		if h.t <= 0.0:
			_parked.erase(bid)
			if guarded(int(h.who)):   # 待つあいだに別の玉が当たっていた: 崩れるだけ
				hub._emit({"kind": "splat", "frame": Doll.frame_index(), "point": h.point, "normal": -(h.dir as Vector3)})
			else:
				hub.hit_person(int(h.by), int(h.who), h.point, h.dir)
	var now := Doll.frame_index()
	for id in duels.keys():
		var d: Dictionary = duels[id]
		var a: Node3D = hub.who_of(int(d.a))
		var b: Node3D = hub.who_of(int(d.b))
		match d.phase:
			"bet":
				if a == null or b == null or now >= int(d.until):
					_drop(d, "cancel")
			"fight":
				if a == null or b == null:
					_finish(d, int(d.a) if a else (int(d.b) if b else -1))   # 抜けた人の負け
				elif now >= int(d.until):
					var ha := int(d.hits_a)
					var hb := int(d.hits_b)
					_finish(d, int(d.a) if ha > hb else (int(d.b) if hb > ha else -1))
				else:
					_watch_sleds(d, dt)
			"over":
				if now >= int(d.until):
					_pay(d)


## 対決していない人のソリは、戦っている人に当たる（轢かれると、のけぞる。当たりの数には入れない）
func _watch_sleds(d: Dictionary, dt: float) -> void:
	for w in [int(d.a), int(d.b)]:
		var t: float = _run_over.get(w, 0.0) - dt
		_run_over[w] = t
		var p: Node3D = hub.who_of(w)
		if t > 0.0 or p == null:
			continue
		for s in get_tree().get_nodes_in_group("sleds"):
			var rb := s as RigidBody3D
			if rb == null or rb.linear_velocity.length() < RUN_OVER_SPEED or p.get("sled") == rb and int(p.get("mode") if p.get("mode") != null else 0) != 0:
				continue
			var half: Vector2 = rb.get("HALF") if rb.get("HALF") != null else Vector2(0.6, 1.2)
			var lp := rb.to_local(p.global_position + Vector3.UP * 0.8)
			if absf(lp.x) < half.x + 0.35 and absf(lp.z) < half.y + 0.35 and absf(lp.y) < 1.4:
				_run_over[w] = RUN_OVER_WAIT
				var dir := rb.linear_velocity.normalized()
				hub._emit({"kind": "hit", "who": w, "frame": Doll.frame_index() + 1, "point": _chest(p), "dir": dir, "sled": true})
				break


# ---------------------------------------------------------------- フィールドの印（どの画面でも）

## 出来事から、雪の上の円を出す・消す
func _show(ev: Dictionary) -> void:
	var d: Dictionary = ev.get("duel", {})
	if d.is_empty():
		return
	var id := int(d.id)
	if ev.kind == "gone" or d.phase == "bet":
		if _rings.has(id):
			var r: Node3D = _rings[id]
			_rings.erase(id)
			if is_instance_valid(r):
				var tw := r.create_tween()
				tw.tween_property(r, "scale", Vector3(1, 0.01, 1), 0.5)
				tw.tween_callback(r.queue_free)
		return
	if not _rings.has(id):
		_rings[id] = _make_ring(d, ev.get("cue", "") == "start")


## 半径 5 m の円: 赤い毛糸の並み縫いを雪に刺し、待ち針（玉は 2 人の色）を立てる。start なら、待ち針が空から刺さる
func _make_ring(d: Dictionary, drop: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Field%d" % int(d.id)
	add_child(root)
	var at: Vector3 = d.at
	root.global_position = Vector3(at.x, 0, at.z)
	var yarn := StandardMaterial3D.new()
	yarn.albedo_color = Color(0.78, 0.16, 0.14)
	yarn.albedo_texture = Icons.felt()
	yarn.uv1_scale = Vector3(3, 3, 1)
	yarn.roughness = 1.0
	var dash := CapsuleMesh.new()
	dash.radius = 0.04
	dash.height = 0.34
	dash.radial_segments = 6
	dash.rings = 2
	for i in DASHES:
		var ang := TAU * (i + 0.5) / DASHES
		var p := Vector3(cos(ang), 0, sin(ang)) * RADIUS
		var m := MeshInstance3D.new()
		m.mesh = dash
		m.material_override = yarn
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(m)
		var tangent := Vector3(-sin(ang), 0, cos(ang))
		var y := _snow_y(at.x + p.x, at.z + p.z)
		m.position = Vector3(p.x, y + 0.015, p.z)
		m.basis = _lay(tangent)   # 糸の長い向きを円に沿わせて寝かせる
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.84, 0.88)
	steel.metallic = 0.8
	steel.roughness = 0.3
	var needle := CylinderMesh.new()
	needle.top_radius = 0.012
	needle.bottom_radius = 0.004
	needle.height = 0.6
	needle.radial_segments = 6
	var head := SphereMesh.new()
	head.radius = 0.075
	head.height = 0.15
	head.radial_segments = 10
	head.rings = 6
	var cols := [_color(int(d.a)), _color(int(d.b))]
	for i in PINS:
		var ang := TAU * i / PINS
		var p := Vector3(cos(ang), 0, sin(ang)) * RADIUS
		var pin := Node3D.new()
		root.add_child(pin)
		var n := MeshInstance3D.new()
		n.mesh = needle
		n.material_override = steel
		n.position.y = 0.3
		pin.add_child(n)
		var h := MeshInstance3D.new()
		h.mesh = head
		var hm := StandardMaterial3D.new()
		hm.albedo_color = cols[i % 2]
		hm.roughness = 0.25
		hm.clearcoat_enabled = true
		h.material_override = hm
		h.position.y = 0.62
		pin.add_child(h)
		var y := _snow_y(at.x + p.x, at.z + p.z) - 0.18   # 針の先は雪に刺さる
		pin.position = Vector3(p.x, y, p.z)
		pin.rotation = Vector3(0.12 * cos(ang * 3.0), 0, 0.12 * sin(ang * 5.0))   # 少しずつ傾いて刺さる
		if drop:
			pin.position.y = y + 2.5
			var tw := pin.create_tween()
			tw.tween_interval(0.04 * i)
			tw.tween_property(pin, "position:y", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return root


## 糸の目を寝かせる向き（カプセルの長い y を円の接線へ）
static func _lay(tangent: Vector3) -> Basis:
	var x := Vector3.UP.cross(tangent).normalized()
	return Basis(x, tangent, x.cross(tangent).normalized())


func _snow_y(x: float, z: float) -> float:
	var y: float = world.height(x, z) if world and world.has_method("height") else 0.0
	if world and world.has_method("snow_lift"):
		y += world.snow_lift(x, z)
	return y


func _color(who: int) -> Color:
	return craft.color_of(who) if craft and craft.has_method("color_of") else Icons.RED
