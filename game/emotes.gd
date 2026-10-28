extends Node3D

const Doll := preload("res://doll.gd")
const Snowball := preload("res://snowball.gd")
const Palm := preload("res://palm.gd")
## 身ぶりと声（エモート）の配り役。身ぶりは「誰が・何を・いつ（姿勢の時計のコマ）」の短い出来事にする。
## 出来事は辞書 {kind, who, frame, ...}。中身は数・文字・Vector3 だけにして、そのまま通信に乗せられるようにする。
## who は人の番号（join で配る）。人の節点そのものは出来事に入れない。
##
## いまは一人の画面の中だけ: send() がすぐ frame を付けて _apply() し、みんな（持ち主・音・ほかの人）に配る。
## 通信を入れたら: send() はホストへ送るだけにし、ホストが frame を付けて全員に配る。
## ハイタッチの組み合わせ・雪玉の当たり・空振りの判定はホストの _apply() の中でだけ決め、結果を出来事として配る。
##
## 姿勢は人形が 12 コマで刻む（doll.gd の play）。出来事は次のコマから始まり、全員の画面で同じコマに動く。

signal happened(ev: Dictionary)

## 身ぶりの長さ（コマ。12 コマで 1 秒）と、出せるとき。walk 歩いているとき、ride 乗っているとき、
## root その間は歩けない（その場でする身ぶり）
const KINDS := {
	"hand_up": {"frames": 72, "walk": true, "ride": false, "root": false},   # 手のひらを掲げて待つ（近づけば合う）
	"high_five": {"frames": 12, "walk": true, "ride": false, "root": true},  # 合った
	"whiff": {"frames": 12, "walk": true, "ride": false, "root": true},      # 空振り
	"breath": {"frames": 54, "walk": true, "ride": true, "root": true},      # 深呼吸
	"make_ball": {"frames": 22, "walk": true, "ride": false, "root": true},  # しゃがんで雪玉を作る
	"windup": {"frames": 0, "walk": true, "ride": true, "root": false},      # 雪玉を振りかぶる（離すまで）
	"throw": {"frames": 7, "walk": true, "ride": true, "root": false},
	"hit": {"frames": 16, "walk": true, "ride": true, "root": false},        # 雪玉が当たってのけぞる
	"banzai": {"frames": 34, "walk": false, "ride": true, "root": false},    # 滑りながら万歳
	"clap": {"frames": 16, "walk": true, "ride": true, "root": false},       # 拍手（フェルトの手袋で、ぽふぽふ）
	"bow": {"frames": 20, "walk": true, "ride": false, "root": true},        # おじぎ
	"wa": {"frames": 14, "walk": true, "ride": true, "root": false},         # 声「ワ〜」うれしい
	"un": {"frames": 7, "walk": true, "ride": true, "root": false},          # 声「ウン」うなずく
	"nn": {"frames": 14, "walk": true, "ride": true, "root": false},         # 声「ンーン」いやいや
}
const VOICES := ["wa", "un", "nn"]
const FIVE_REACH := 1.3      # ハイタッチの手が届く、体どうしの距離 (m)。人形の腕は短いが、手のひらが大きい
const FIVE_NEAR := 3.5       # 手を上げたとき、この中で待っている人と組む候補にする
const FIVE_HIT := 3           # high_five の何コマ目に手が合うか（その前の 3 コマが、引くため）
const MAKE_READY := 16       # 雪玉ができて手に持つコマ（make_ball の中で）

var people := {}             # 番号 → 人（player.gd・bot.gd）
var _next_id := 1
var _waiting := {}           # 手を上げて待っている人の番号 → 待ちが切れるコマ


## 人を登録して番号をもらう
func join(who: Node3D) -> int:
	var id := _next_id
	_next_id += 1
	people[id] = who
	return id


func who_of(id: int) -> Node3D:
	var n: Node3D = people.get(id)
	return n if is_instance_valid(n) else null


## 出来事を出す。持ち主が呼ぶ（いまはすぐ配る。通信ではホストへ）
func send(ev: Dictionary) -> void:
	ev["frame"] = Doll.frame_index() + 1
	_apply(ev)


## ホストの判定。ハイタッチの組み合わせはここで決めてから配る
func _apply(ev: Dictionary) -> void:
	var kind: String = ev.kind
	if kind == "hand_up":
		var a := who_of(ev.who)
		var b_id := _waiting_near(ev.who)
		if b_id > 0 and a and _can_five(a, who_of(b_id)):
			_five(ev.who, b_id, ev.frame)
			return
		# 待つ。手のひらを掲げたまま近づけば、そこで合う（_physics_process）。合わないまま切れたら空振り
		_waiting[ev.who] = ev.frame + KINDS.hand_up.frames
	elif kind != "hand_up" and _waiting.has(ev.get("who", -1)):
		_waiting.erase(ev.who)   # ほかの身ぶりをしたら、待つのをやめる
	_emit(ev)
	if kind == "throw":
		_spawn_ball(ev)


## 二人のハイタッチ。手は、あいだの顔の高さで合う。合ったコマに紙吹雪
func _five(a_id: int, b_id: int, frame: int) -> void:
	_waiting.erase(a_id)
	_waiting.erase(b_id)
	var contact := (_hand_spot(who_of(a_id)) + _hand_spot(who_of(b_id))) * 0.5
	_emit({"kind": "high_five", "who": a_id, "with": b_id, "frame": frame, "point": contact})
	_emit({"kind": "high_five", "who": b_id, "with": a_id, "frame": frame, "point": contact})


func _emit(ev: Dictionary) -> void:
	if ev.kind == "splat":
		_show_splat(ev)
	elif ev.kind == "high_five" and ev.who < ev.with:
		_burst_at(ev.point, int(ev.frame) + FIVE_HIT)
	happened.emit(ev)


## 手が合うコマに、紙吹雪と紙の星と綿の粉（どの画面でも、出来事から作る）
func _burst_at(point: Vector3, frame: int) -> void:
	var tps := Engine.physics_ticks_per_second
	var wait := float(frame * tps / Doll.FPS - Engine.get_physics_frames()) / tps
	if wait > 0.0:
		await get_tree().create_timer(wait, true, true).timeout
	Palm.burst(self, point)
	Snowball.splat_at(self, point, Vector3.UP, true)


## 手のひらを掲げた二人が届く所で向き合ったら、合わせる。待ちが切れた人は、上げた手を下ろしながら空振りする
func _physics_process(_dt: float) -> void:
	var now := Doll.frame_index()
	var ids := _waiting.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := who_of(ids[i])
			var b := who_of(ids[j])
			if a and b and _waiting.has(ids[i]) and _waiting.has(ids[j]) and _can_five(a, b):
				_five(ids[i], ids[j], now + 1)
	for id in _waiting.keys():
		if now >= _waiting[id] or who_of(id) == null:
			_waiting.erase(id)
			if who_of(id):
				_emit({"kind": "whiff", "who": id, "frame": now + 1})


## 手を上げて待っている人のうち、近い人
func _waiting_near(id: int) -> int:
	var a := who_of(id)
	if a == null:
		return -1
	var best := -1
	var best_d := FIVE_NEAR
	for other in _waiting:
		if other == id or who_of(other) == null:
			continue
		var d := _flat(who_of(other).global_position - a.global_position).length()
		if d < best_d:
			best_d = d
			best = other
	return best


## 届いて、二人とも相手のほうを向いているか（横を向いた相手とは合わない）
func _can_five(a: Node3D, b: Node3D) -> bool:
	var ab := _flat(b.global_position - a.global_position)
	if ab.length() > FIVE_REACH:
		return false
	ab = ab.normalized()
	return _forward(a).dot(ab) > 0.35 and _forward(b).dot(-ab) > 0.35


## 上げた右手のあたり（世界）。顔の横の前。笠の人形は真上へ上げると手がつばに隠れる
func _hand_spot(who: Node3D) -> Vector3:
	var doll: Doll = who.doll
	return who.global_position + Vector3.UP * doll.height() * 0.78 + _forward(who) * 0.35


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


## 人の前（世界、水平）。体の向き（人形の向き）で見る
static func _forward(who: Node3D) -> Vector3:
	var doll: Doll = who.doll
	return _flat(-doll.global_basis.z).normalized()


# ---------------------------------------------------------------- 雪玉

## 投げた雪玉を物として飛ばす。当たり（人・ソリ・地面）は雪玉が見つけ、ここへ知らせる
func _spawn_ball(ev: Dictionary) -> void:
	var ball := Snowball.new()
	ball.hub = self
	ball.thrower = ev.who
	add_child(ball)
	ball.global_position = ev.origin
	ball.linear_velocity = ev.velocity


## 雪玉が人に当たった（雪玉が呼ぶ）。のけぞりは出来事として配る
func ball_hit_person(ball: Node3D, id: int, point: Vector3, dir: Vector3) -> void:
	_emit({"kind": "hit", "who": id, "by": ball.thrower, "frame": Doll.frame_index() + 1, "point": point, "dir": dir})
	_emit({"kind": "splat", "frame": Doll.frame_index(), "point": point, "normal": -dir, "on_person": id})


## 雪玉が物（ソリ・地面・ロッジ）に当たって崩れた。残る雪を付ける物は、通信に乗るよう節点の道すじで渡す
func ball_splat(point: Vector3, normal: Vector3, body: Node) -> void:
	var on := ""
	if body is Node3D and get_parent().is_ancestor_of(body):
		on = str(get_parent().get_path_to(body))
	_emit({"kind": "splat", "frame": Doll.frame_index(), "point": point, "normal": normal, "on": on})


## 崩れた雪の見た目（どの画面でも、出来事から作る）
func _show_splat(ev: Dictionary) -> void:
	var on: Node3D = self
	if ev.has("on_person") and who_of(ev.on_person):
		on = who_of(ev.on_person).doll
	elif ev.get("on", "") != "":
		var n := get_parent().get_node_or_null(NodePath(ev.on))
		if n is Node3D:
			on = n
	Snowball.splat_at(on, ev.point, ev.normal)
