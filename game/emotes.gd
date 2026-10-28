extends Node3D

const Doll := preload("res://doll.gd")
const Snowball := preload("res://snowball.gd")
const Palm := preload("res://palm.gd")
## 身ぶりと声（エモート）の配り役。身ぶりは「誰が・何を・いつ（姿勢の時計のコマ）」の短い出来事にする。
## 出来事は辞書 {kind, who, frame, ...}。中身は数・文字・Vector3 だけにして、そのまま通信に乗せられるようにする。
## who は人の番号（join で配る）。人の節点そのものは出来事に入れない。
##
## 手の形（Tab の輪で選ぶ）は、挨拶のボタンではなく、手の材料。選んだ形は下ろすまで掲げたまま、腕は見ている向きへ上がる。
## 意味は遊ぶ人が作る（両手のひらは、前を見れば「来るな」、見上げれば万歳）。ここで決めるのは手と手が出会ったときだけ:
## 手のひら同士が届く所で向き合えばハイタッチ、グー同士ならグータッチ。片方だけが向かって寄れば、空振り。
##
## いまは一人の画面の中だけ: send() がすぐ frame を付けて _apply() し、みんな（持ち主・音・ほかの人）に配る。
## 通信を入れたら: send() はホストへ送るだけにし、ホストが frame を付けて全員に配る。
## ハイタッチ・グータッチの組み合わせ・空振り・雪玉の当たりはホストだけが決め、結果を出来事として配る。
##
## 姿勢は人形が 12 コマで刻む（doll.gd の play）。出来事は次のコマから始まり、全員の画面で同じコマに動く。

signal happened(ev: Dictionary)

## 身ぶりの長さ（コマ。12 コマで 1 秒）。root その間は歩けない（その場でする身ぶり）
const KINDS := {
	"hands": {"frames": 0, "root": false},        # 手の形を変える（ev.hands。下ろすまで続く）
	"high_five": {"frames": 12, "root": true},    # 手のひら同士が合った
	"fist_bump": {"frames": 12, "root": true},    # グー同士が合った
	"whiff": {"frames": 12, "root": true},        # 空振り
	"clap": {"frames": 16, "root": false},        # 両手のひらで拍手（フェルトの手袋で、ぽふぽふ）
	"breath": {"frames": 0, "root": false},       # 白い息を長く吐く（B を押しているあいだ。breath_end で止まる）
	"breath_end": {"frames": 0, "root": false},
	"make_ball": {"frames": 22, "root": true},    # しゃがんで雪玉を作る
	"windup": {"frames": 0, "root": false},       # 雪玉を振りかぶる（離すまで）
	"throw": {"frames": 7, "root": false},
	"hit": {"frames": 16, "root": false},         # 雪玉が当たってのけぞる
	"wa": {"frames": 14, "root": false},          # 声「ワ〜」うれしい
	"un": {"frames": 7, "root": false},           # 声「ウン」うなずく
	"nn": {"frames": 14, "root": false},          # 声「ンーン」いやいや
	"huh": {"frames": 16, "root": false},         # 声「ウン？」首をかしげる
}
const VOICES := ["wa", "un", "nn", "huh"]
const HANDS := Palm.HANDS
const TOUCH_REACH := 1.3     # 手と手が届く、体どうしの距離 (m)。人形の腕は短いが、手の形が大きい
const WHIFF_REACH := 1.0     # 片方だけが向かってこの中まで寄ると、空振り
const FIVE_HIT := 3          # high_five・fist_bump の何コマ目に手が合うか（その前の 3 コマが、引くため）
const MAKE_READY := 16       # 雪玉ができて手に持つコマ（make_ball の中で）
const EXHALE_MAX := 5.0      # 息が続く長さ (s)

var people := {}             # 番号 → 人（player.gd・bot.gd）
var hands := {}              # 番号 → いま掲げている手の形（HANDS の名前）
var _next_id := 1


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


## ホストの判定
func _apply(ev: Dictionary) -> void:
	if ev.kind == "hands":
		if ev.hands == "":
			hands.erase(ev.who)
		else:
			hands[ev.who] = ev.hands
	_emit(ev)
	if ev.kind == "throw":
		_spawn_ball(ev)


func _emit(ev: Dictionary) -> void:
	if ev.kind == "splat":
		_show_splat(ev)
	elif ev.kind in ["high_five", "fist_bump"] and ev.who < ev.with:
		_burst_at(ev.point, int(ev.frame) + FIVE_HIT)
	happened.emit(ev)


## 右手の形（"palm" "fist" など。下ろしていれば ""）
func right_hand(id: int) -> String:
	return HANDS.get(hands.get(id, ""), ["", ""])[0]


## 手の形を掲げた人どうしが出会ったら、合わせる（手のひらとグーだけ）。合ったら二人とも手を下ろす
func _physics_process(_dt: float) -> void:
	var now := Doll.frame_index()
	var ids := hands.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a_id: int = ids[i]
			var b_id: int = ids[j]
			var a := who_of(a_id)
			var b := who_of(b_id)
			if a == null or b == null or not hands.has(a_id) or not hands.has(b_id):
				continue
			var shape := right_hand(a_id)
			if not shape in ["palm", "fist"] or right_hand(b_id) != shape:
				continue
			var ab := _flat(b.global_position - a.global_position)
			var d := ab.length()
			if d > TOUCH_REACH or d < 0.01:
				continue
			ab /= d
			var a_faces := _forward(a).dot(ab) > 0.35
			var b_faces := _forward(b).dot(-ab) > 0.35
			if a_faces and b_faces:
				_touch(a_id, b_id, "high_five" if shape == "palm" else "fist_bump", now + 1)
			elif d < WHIFF_REACH and (a_faces or b_faces):
				# 片方だけが向かって寄った: 向かった人が空振りして、手を下ろす
				var who: int = a_id if a_faces else b_id
				_lower(who, now + 1)
				_emit({"kind": "whiff", "who": who, "frame": now + 1, "shape": shape})
	for id in hands.keys():
		if who_of(id) == null:
			hands.erase(id)


## 二人の手が、あいだの顔の高さで合う。合ったコマに紙吹雪。二人とも手を下ろす（同じ形を掲げ直せば、またできる）
func _touch(a_id: int, b_id: int, kind: String, frame: int) -> void:
	var contact := (_hand_spot(who_of(a_id)) + _hand_spot(who_of(b_id))) * 0.5
	_lower(a_id, frame)
	_lower(b_id, frame)
	_emit({"kind": kind, "who": a_id, "with": b_id, "frame": frame, "point": contact})
	_emit({"kind": kind, "who": b_id, "with": a_id, "frame": frame, "point": contact})


func _lower(id: int, frame: int) -> void:
	hands.erase(id)
	_emit({"kind": "hands", "who": id, "hands": "", "frame": frame, "auto": true})


## 手が合うコマに、紙吹雪と紙の星と綿の粉（どの画面でも、出来事から作る）
func _burst_at(point: Vector3, frame: int) -> void:
	var tps := Engine.physics_ticks_per_second
	var wait := float(frame * tps / Doll.FPS - Engine.get_physics_frames()) / tps
	if wait > 0.0:
		await get_tree().create_timer(wait, true, true).timeout
	Palm.burst(self, point)
	Snowball.splat_at(self, point, Vector3.UP, true)


## 掲げた右手のあたり（世界）。顔の横の前
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
