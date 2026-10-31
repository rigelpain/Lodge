extends Node3D

const Doll := preload("res://doll.gd")
const Snowball := preload("res://snowball.gd")
const Palm := preload("res://palm.gd")
## 身ぶりと声（エモート）の配り役。身ぶりは「誰が・何を・いつ（姿勢の時計のコマ）」の短い出来事にする。
## 出来事は辞書 {kind, who, frame, ...}。中身は数・文字・Vector3 だけにして、そのまま通信に乗せられるようにする。
## who は人の番号（join で配る）。人の節点そのものは出来事に入れない。
##
## 手（Tab の輪で選ぶ）は、挨拶のボタンではなく、手の材料。高い手のひらか低い手のひらを、片手（右か左）か両手で掲げる。
## 掲げた手は下ろすまでそのまま、腕は見ている向きへ上がる。意味は遊ぶ人が作る（高い片手で遠くの人に場所を示す、
## 高い両手で万歳、低い手で「おさえて」「ストップ」）。ここで決めるのは手と手が出会ったときだけ:
## 高い手のひら同士が届く所で向き合えばハイタッチ、低い手のひら同士なら握手。片手と両手でも合う。
## 高い手のひらで片方だけが向かって寄れば、空振り。
##
## いまは一人の画面の中だけ: send() がすぐ frame を付けて _apply() し、みんな（持ち主・音・ほかの人）に配る。
## 通信を入れたら: send() はホストへ送るだけにし、ホストが frame を付けて全員に配る。
## ハイタッチ・握手の組み合わせ・空振り・雪玉の当たりはホストだけが決め、結果を出来事として配る。
## 持っている雪玉の数（balls）もホストが持つ（あとで雪玉をお金のように使うので、持ち主の画面では決めない）。
##
## 姿勢は人形が 12 コマで刻む（doll.gd の play）。出来事は次のコマから始まり、全員の画面で同じコマに動く。

signal happened(ev: Dictionary)

## 身ぶりの長さ（コマ。12 コマで 1 秒）。root その間は歩けない（その場でする身ぶり）
const KINDS := {
	"hands": {"frames": 0, "root": false},        # 手を掲げる・下ろす（ev.hands。下ろすまで続く）
	"high_five": {"frames": 12, "root": true},    # 高い手のひら同士が合った（ev.grips）
	"shake": {"frames": 24, "root": true},        # 低い手のひら同士で握手（ev.grips）
	"whiff": {"frames": 12, "root": true},        # 空振り
	"clap": {"frames": 16, "root": false},        # 高い両手のひらで拍手（フェルトの手袋で、ぽふぽふ）
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
	"oi": {"frames": 18, "root": false},          # 声「おーーーい」遠くの人を呼ぶ（空いた手を口に当てる）
}
const VOICES := ["wa", "un", "nn", "huh", "oi"]
const HANDS := Palm.HANDS
const TOUCH_REACH := 1.3     # 手と手が届く、体どうしの距離 (m)。人形の腕は短いが、手の形が大きい
const SHAKE_REACH := 1.0     # 握手は手のひらをくっつけるので、もう少し近づいてから（腕の短い人形でも届く所）
const WHIFF_REACH := 1.0     # 片方だけが向かってこの中まで寄ると、空振り
const FIVE_HIT := 3          # high_five の何コマ目に手が合うか（その前の 3 コマが、引くため）
const MAKE_READY := 16       # 雪玉ができて手に持つコマ（make_ball の中で）
const EXHALE_MAX := 5.0      # 息が続く長さ (s)
const BALL_MAX := 5          # 持てる雪玉の数（右手に 1 つ、残りは帯の袋）

var balls := {}              # 番号 → 持っている雪玉の数
var _making := {}            # 番号 → 丸めている雪玉ができるコマ（MAKE_READY。それまでにのけぞると、できない）

var people := {}             # 番号 → 人（player.gd・bot.gd）
var aims := {}               # 番号 → 指している向き {dir: 頭から見た向き（世界）, dist: その先までの長さ}。指していなければ無い
var hands := {}              # 番号 → いま掲げている手（HANDS の名前。"high_R" など）
var _next_id := 1


## 人を登録して番号をもらう
func join(who: Node3D) -> int:
	var id := _next_id
	_next_id += 1
	people[id] = who
	return id


## その人がいま指している所（世界）。頭から、配られた向きと長さの先。指していなければ INF
func point_of(id: int) -> Vector3:
	var a: Dictionary = aims.get(id, {})
	var who: Node3D = people.get(id)
	if a.is_empty() or who == null or not is_instance_valid(who):
		return Vector3.INF
	return who.global_position + Vector3.UP * 1.55 + (a.dir as Vector3) * float(a.dist)


## 持っている雪玉の数
func balls_of(id: int) -> int:
	return balls.get(id, 0)


func who_of(id: int) -> Node3D:
	var n: Node3D = people.get(id)
	return n if is_instance_valid(n) else null


## 出来事を出す。持ち主が呼ぶ（いまはすぐ配る。通信ではホストへ）
func send(ev: Dictionary) -> void:
	ev["frame"] = Doll.frame_index() + 1
	_apply(ev)


## ホストの判定
func _apply(ev: Dictionary) -> void:
	match ev.kind:
		"make_ball":
			if balls_of(ev.who) >= BALL_MAX:
				return   # もう持てない
			_making[ev.who] = int(ev.frame) + MAKE_READY
		"throw":
			if balls_of(ev.who) <= 0:
				return   # 投げる雪玉がない
			balls[ev.who] = balls_of(ev.who) - 1
	if ev.kind == "point":   # 指さしの向き（持ち主の画面で、向きが変わったときだけ間引いて送られる）
		if ev.get("dir", Vector3.ZERO) == Vector3.ZERO:
			aims.erase(ev.who)
		else:
			aims[ev.who] = {"dir": ev.dir, "dist": ev.dist}
	if ev.kind == "hands":
		if ev.hands == "":
			hands.erase(ev.who)
		else:
			hands[ev.who] = ev.hands
	_emit(ev)
	if ev.kind == "throw":
		_spawn_ball(ev)


func _emit(ev: Dictionary) -> void:
	if ev.kind == "hit":
		_making.erase(ev.who)   # びっくりして、丸めていた雪玉は崩れる
	if ev.kind == "splat":
		_show_splat(ev)
	elif ev.kind == "high_five" and ev.who < ev.with:
		# 紙吹雪は一度だけ（両手どうしでも）。合う所のまんなかに
		var at := Vector3.ZERO
		for g in ev.grips:
			at += g[1] as Vector3
		_burst_at(at / ev.grips.size(), int(ev.frame) + FIVE_HIT)
	happened.emit(ev)


## 掲げている手のうち、その高さの側（1 右、-1 左）
func _sides(id: int, height: String) -> Array:
	var h: Array = HANDS.get(hands.get(id, ""), ["", ""])
	var out := []
	if h[0] == height:
		out.append(1)
	if h[1] == height:
		out.append(-1)
	return out


## 手を掲げた人どうしが出会ったら、合わせる。高い手のひら同士はハイタッチ、低い手のひら同士は握手。合ったら二人とも手を下ろす
func _physics_process(_dt: float) -> void:
	var now := Doll.frame_index()
	# 丸めていた雪玉ができた（出来事にはしない。数は持ち主が毎フレーム見る。通信では数を配る）
	for id in _making.keys():
		if now >= int(_making[id]):
			_making.erase(id)
			balls[id] = mini(balls_of(id) + 1, BALL_MAX)
	var ids := hands.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a_id: int = ids[i]
			var b_id: int = ids[j]
			var a := who_of(a_id)
			var b := who_of(b_id)
			if a == null or b == null or not hands.has(a_id) or not hands.has(b_id):
				continue
			for height in ["high", "low"]:
				if _sides(a_id, height).is_empty() or _sides(b_id, height).is_empty():
					continue
				var ab := _flat(b.global_position - a.global_position)
				var d := ab.length()
				if d > (TOUCH_REACH if height == "high" else SHAKE_REACH) or d < 0.01:
					continue
				ab /= d
				var a_faces := _forward(a).dot(ab) > 0.35
				var b_faces := _forward(b).dot(-ab) > 0.35
				if a_faces and b_faces:
					_touch(a_id, b_id, height, now + 1)
				elif height == "high" and d < WHIFF_REACH and (a_faces or b_faces):
					# 片方だけが向かって寄った: 向かった人が空振りして、手を下ろす
					var who: int = a_id if a_faces else b_id
					var side: int = _sides(who, "high")[0]
					_lower(who, now + 1)
					_emit({"kind": "whiff", "who": who, "frame": now + 1, "side": side})
				break
	for id in hands.keys():
		if who_of(id) == null:
			hands.erase(id)


## ハイタッチで、どの手とどの手が合うか: [[a の側, b の側], ...]。向かい合うと、こちらの右の前にあるのは相手の左。
## 両手と両手は両方の手で。片手と両手は、片手と、その向かいの相手の手
func _pairs(sa: Array, sb: Array) -> Array:
	if sa.size() == 2 and sb.size() == 2:
		return [[1, -1], [-1, 1]]
	if sa.size() == 1 and sb.size() == 1:
		return [[sa[0], sb[0]]]
	return [[-sb[0], sb[0]]] if sa.size() == 2 else [[sa[0], -sa[0]]]


## 二人の手が合う。ハイタッチは顔の高さで、手と手のあいだ（合ったコマに紙吹雪）。
## 握手は腰の高さで、手のひらをそろえて重ねる（_shake_grips）。二人とも手を下ろす（掲げ直せば、またできる）
func _touch(a_id: int, b_id: int, height: String, frame: int) -> void:
	var a := who_of(a_id)
	var b := who_of(b_id)
	var sa := _sides(a_id, height)
	var sb := _sides(b_id, height)
	var ea := {"kind": "high_five", "who": a_id, "with": b_id, "frame": frame}
	var eb := {"kind": "high_five", "who": b_id, "with": a_id, "frame": frame}
	if height == "high":
		var ga := []
		var gb := []
		for pr in _pairs(sa, sb):
			var p := (_hand_spot(a, pr[0], height) + _hand_spot(b, pr[1], height)) * 0.5
			ga.append([pr[0], p])
			gb.append([pr[1], p])
		ea["grips"] = ga
		eb["grips"] = gb
	else:
		var sg := _shake_grips(a, sa, b, sb)
		ea.merge({"kind": "shake", "grips": sg[0], "fwd": sg[2], "axis": sg[3]}, true)
		eb.merge({"kind": "shake", "grips": sg[1], "fwd": -sg[2], "axis": sg[3]}, true)
	_lower(a_id, frame)
	_lower(b_id, frame)
	_emit(ea)
	_emit(eb)


const SHAKE_TILT := 0.5      # 握手の手のひらを、垂直から傾ける角 (rad)。真っすぐ立てると、面が見えない
const SHAKE_GAP := 0.045     # 重ねた手のひらどうしの間 (m)。紙の厚みより少し離して、重なりが見えるように
const SHAKE_SHIFT := 0.045   # 重ねた手を、それぞれ持ち主の側へずらす (m)。互い違いが見える


## 握手で手のひらを重ねる所。二人の手のひらはみな平行で、同じ傾き。重ねる向き（axis）に沿って並べる:
## 片手どうしは 自分・相手、片手と両手は 相手・自分・相手（両手で包む）、両手どうしは互い違いに 自分・相手・自分・相手。
## 並びは、腕が交差しないよう、A から見た左右の順にする。返り値は [a の [側, 所]…, b の [側, 所]…, A から B への向き, 重ねる向き]
func _shake_grips(a: Node3D, sa: Array, b: Node3D, sb: Array) -> Array:
	var fwd := _flat(b.global_position - a.global_position).normalized()
	var left := Vector3.UP.cross(fwd).normalized()   # A から見た左
	var axis := (left * cos(SHAKE_TILT) + Vector3.UP * sin(SHAKE_TILT)).normalized()
	var center := Vector3.ZERO
	var hands := []   # [人 0 か 1, 側, A から見た左右（左が正）]
	for sd in sa:
		hands.append([0, sd, -float(sd)])        # A の右手は A の右
		center += _hand_spot(a, sd, "low")
	for sd in sb:
		hands.append([1, sd, float(sd)])         # 向かいの B の右手は、A から見て左
		center += _hand_spot(b, sd, "low")
	center /= hands.size()
	var order := []
	if sa.size() == 1 and sb.size() == 2:
		order = [_hand_at(hands, 1, -1.0), _hand_at(hands, 0, 0.0), _hand_at(hands, 1, 1.0)]   # B が両手で包む
	elif sa.size() == 2 and sb.size() == 1:
		order = [_hand_at(hands, 0, -1.0), _hand_at(hands, 1, 0.0), _hand_at(hands, 0, 1.0)]   # A が両手で包む
	else:
		hands.sort_custom(func(x, y): return x[2] < y[2] or (x[2] == y[2] and x[0] < y[0]))
		order = hands   # 片手どうしは 2 枚、両手どうしは A・B・A・B の互い違い
	var ga := []
	var gb := []
	for i in order.size():
		var hd: Array = order[i]
		var p := center + axis * (i - (order.size() - 1) * 0.5) * SHAKE_GAP   # A から見て右の手から順に
		p -= fwd * SHAKE_SHIFT * (1.0 if hd[0] == 0 else -1.0)
		(ga if hd[0] == 0 else gb).append([hd[1], p])
	return [ga, gb, fwd, axis]


## hands の中から、その人の手を一つ（lat が 0 なら、その人のただ一つの手。そうでなければ左右がその符号の手）
func _hand_at(hands: Array, who: int, lat: float) -> Array:
	for hd in hands:
		if hd[0] == who and (lat == 0.0 or signf(hd[2]) == signf(lat)):
			return hd
	return hands[0]


func _lower(id: int, frame: int) -> void:
	hands.erase(id)
	_emit({"kind": "hands", "who": id, "hands": "", "frame": frame, "auto": true})


## 手が合うコマに、紙吹雪と紙の星と綿の粉（どの画面でも、出来事から作る）
func _burst_at(point: Vector3, frame: int) -> void:
	var tps := Engine.physics_ticks_per_second
	var wait := float(frame * tps / Doll.FPS - Engine.get_physics_frames()) / tps
	if wait > 0.0:
		await get_tree().create_timer(wait, true, true).timeout
	var before := get_child_count()
	Palm.burst(self, point)
	Snowball.splat_at(self, point, Vector3.UP, true)
	for i in range(before, get_child_count()):   # 右下の自分の小窓（self_cam.gd の層 6）にも映す
		for g in get_child(i).find_children("*", "GeometryInstance3D", true, false) + [get_child(i)]:
			if g is GeometryInstance3D:
				(g as GeometryInstance3D).layers |= 1 << 5


## 掲げた手のあたり（世界）。高い手は顔の横の前、低い手はみぞおちの前（握手で手を合わせる高さ。一人称でも画面に入る）。side 1 右、-1 左
func _hand_spot(who: Node3D, side: int, height: String) -> Vector3:
	var doll: Doll = who.doll
	var right := _flat(doll.global_basis.x).normalized()
	var up := doll.height() * (0.78 if height == "high" else 0.56)
	return who.global_position + Vector3.UP * up + _forward(who) * 0.35 + right * side * 0.16


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
