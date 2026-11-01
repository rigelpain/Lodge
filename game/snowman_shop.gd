extends Node
## ご飯係の雪だるま（props/build_snowman.py の節点 base → chest → head・arm_l・arm_r を回す）。冷蔵庫の中から、番台ごしに
## ペレットを雪玉で売る（売り場の画面は food_ui.gd。2026-11-01 代表: 調理はプレイヤーがする。雪だるまは売って渡すだけ）。
## 動きは人形と同じ 12 コマ／秒に刻む（コマの間は止める）:
##   待つ   胴がゆっくり左右に揺れる。人が番台に来ると頭をその人へ向ける
##   あいさつ 売り場が開くと、胴を前へ倒しておじぎ
##   売る   右手のベルを振って「ちりりん」。冷蔵庫の中からペレットがぴょんと番台のお皿へ跳ね、お皿から買った人の手へ飛ぶ
## main.gd が雪だるま（man）と番台（counter）を入れる。番台で F（player.gd の food_near）

const Doll := preload("res://doll.gd")
const Props := preload("res://props.gd")
const Food := preload("res://food.gd")

const TALK_R := 2.3          # 番台からこの距離で話しかけられる (m)
const NOTICE_R := 4.0        # この距離に人が来ると頭を向ける

var main: Node
var man: Node3D              # 雪だるま（snowman.glb）
var counter: Node3D          # 番台の根元（main.gd の Bandai_counter_indigo）
var dish_at := Vector3.ZERO  # 番台のお皿（番台の座標）
var _chest: Node3D
var _head: Node3D
var _arm_r: Node3D
var _rest := {}              # 節点 → 初めの回転
var _frame := -1
var _k := 0
var _bow_from := -100
var _ring_from := -100
var _flights: Array = []     # [{node, from, mid, to, start, len, then}]
var _head_yaw := 0.0


func _ready() -> void:
	if man:
		_chest = man.find_child("chest", true, false) as Node3D
		_head = man.find_child("head", true, false) as Node3D
		_arm_r = man.find_child("arm_r", true, false) as Node3D
		for n in [_chest, _head, _arm_r]:
			if n:
				_rest[n] = n.rotation


## 人 who が番台で話しかけられる所にいるか（番台の客の側。冷蔵庫の側からは話しかけない）
func can_talk(who: Node3D) -> bool:
	if counter == null or who == null:
		return false
	var p := counter.to_local(who.global_position)
	return Vector2(p.x, p.z).length() < TALK_R and (man == null or
			who.global_position.distance_to(man.global_position) > counter.global_position.distance_to(man.global_position))


func greet() -> void:
	_bow_from = _k + 1


## 売れた: ベルを振り、ペレットを冷蔵庫からお皿へ、お皿から買った人の手へ跳ばす（見た目だけ。持ち物にはもう入っている）
func sold(dish: String, buyer: Node3D) -> void:
	_ring_from = _k + 1
	_bow_from = _k + 10
	var audio = main.get_node_or_null("Audio") if main else null
	if audio and man:
		audio.kitchen(man, "cook_bell", -12.0, 2)
	if man == null or counter == null:
		return
	var pel := Props.make(Food.pellet_glb(dish))
	pel.scale = Vector3.ONE * 1.6
	main.add_child(pel)
	var start := man.global_position + Vector3.UP * 1.2
	var mid := counter.to_global(dish_at) + Vector3.UP * 0.06
	pel.global_position = start
	_flights.append({"node": pel, "from": start, "to": mid, "start": _k + 3, "len": 6, "h": 0.5, "buyer": buyer, "leg": 0})


func _process(_dt: float) -> void:
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	_frame = fi
	_k += 1
	_step()


func _step() -> void:
	if man == null:
		return
	# 待つ: 胴がゆっくり左右に（4 コマごとに動かす）
	var sway := sin(float(_k / 4 * 4) / 12.0 * 0.9) * 0.035
	var bow := 0.0
	var n := _k - _bow_from
	if n >= 0 and n < 9:
		bow = [-0.08, -0.2, -0.3, -0.34, -0.34, -0.26, -0.15, -0.06, 0.0][n]
	if _chest:
		_chest.rotation = _rest[_chest] + Vector3(bow, 0, sway)
	# ベル: 右手を 2 度振る
	var ring := 0.0
	n = _k - _ring_from
	if n >= 0 and n < 10:
		ring = [0.3, 0.6, 0.2, -0.3, 0.5, 0.7, 0.2, -0.2, 0.1, 0.0][n]
	if _arm_r:
		_arm_r.rotation = _rest[_arm_r] + Vector3(0, 0, ring)
	# 近くの人へ頭を向ける（3 コマで寄せる）
	var target := 0.0
	var who: Node3D = main.get("player") if main else null
	if who and _head and who.global_position.distance_to(man.global_position) < NOTICE_R:
		var d: Vector3 = (_head.get_parent() as Node3D).global_transform.affine_inverse() * who.global_position
		target = clampf(atan2(d.x, d.z), -0.6, 0.6)
	if _k % 3 == 0:
		_head_yaw = lerpf(_head_yaw, target, 0.5)
	if _head:
		_head.rotation = _rest[_head] + Vector3(0, _head_yaw, 0)
	# 跳ねるペレット
	for f in _flights.duplicate():
		var t := float(_k - int(f.start)) / float(f.len)
		var node: Node3D = f.node
		if not is_instance_valid(node):
			_flights.erase(f)
			continue
		if t < 0.0:
			continue
		var to: Vector3 = f.to
		if f.leg == 1 and is_instance_valid(f.buyer):   # 2 本目は、買った人の手（胸の前）へ
			to = (f.buyer as Node3D).global_position + Vector3.UP * 1.1 - (f.buyer as Node3D).global_basis.z * 0.3
		var tt := minf(t, 1.0)
		node.global_position = (f.from as Vector3).lerp(to, tt) + Vector3.UP * float(f.h) * 4.0 * tt * (1.0 - tt)
		node.rotation.y += 0.6
		if t >= 1.0:
			var audio = main.get_node_or_null("Audio")
			if audio:   # 消えるペレットに付けると音が切れるので、雪だるまか買った人に付ける
				audio.kitchen(man if f.leg == 0 or not is_instance_valid(f.buyer) else f.buyer, "cook_pellet", -10.0, 3)
			if f.leg == 0:
				f.leg = 1
				f.from = to
				f.start = _k + 2
				f.h = 0.35
			else:
				_flights.erase(f)
				node.queue_free()
