extends Node3D
## 山師の柵と遊び場のミニオン（2026-11-02 代表「山師のミニオンが全然動かない。」）。mountain_man.gd が、あなたが近づいたら置く。
## 1 匹ずつ、柵の中でその子らしく過ごす: 歩き回る・座ってまわりを見る・寝床のかごで丸まって寝る・餌の器と水桶で食べる・
## 毛糸玉のそばで遊ぶ（跳ねたり、まわりをぐるぐる回ったり）・切り株の上に乗る（カエル）。
## 歩き方・跳ね方・転がり方と、座る・寝る姿の刻み方は、連れのミニオンと同じ（companions.gd の pose_parts。gait は pals.gd の PET）。
## 居場所（位置と向き）は毎フレームなめらか。姿勢は人形と同じ 12 コマ／秒の時計で刻む。
## 柵・トンネル・切り株・水桶にめり込まないよう、行き先は柵の内側の、物の円の外から選び、まっすぐ行けるときだけ行く。
## 座標は、ヤク・出店・柵の glb を組んだ寸法の、山師の座標（前は -Z、左手は -X）。scale_xz で山師の節の座標へ直す（mountain_man.gd の SET_SCALE と左右）

const Doll := preload("res://doll.gd")
const Pals := preload("res://pals.gd")
const Companions := preload("res://companions.gd")
const Ghost := preload("res://ghost.gd")

## 柵の内側（ここから外へは出ない。柵の柱から 0.3 m あける）: x の範囲、z の範囲
const AREA := Rect2(-7.0, -0.2, 3.4, 2.6)
## 柵の中の物（行き先にも、通り道にもしない円）: [x, z, 半径]
const BLOCK := [[-4.1, -0.05, 0.55], [-6.6, 2.1, 0.32], [-6.05, 2.1, 0.32], [-3.75, 2.35, 0.42]]   # トンネル・切り株 2 つと坂・水桶
## 過ごす所: 名前 → [[x, z, 高さ, 向き（そこで向く向き。INF ならまわりを見る）], …]
const SPOTS := {
	"bed": [[-6.7, 0.15, 0.34, INF], [-6.2, -0.05, 0.32, INF]],                    # 薪かごの寝床（中の薪の上に丸まる）
	"food": [[-4.4, 1.95, 0.0, 0.0], [-4.18, 1.95, 0.0, 0.0], [-3.96, 1.95, 0.0, 0.0]],   # 餌の器の前（器を向く。+Z が奥）
	"water": [[-3.75, 1.95, 0.0, 0.0], [-3.45, 1.95, 0.0, 0.0]],                   # 水桶の前
	"toy": [[-4.9, 1.0, 0.0, INF], [-4.6, 0.7, 0.0, INF], [-5.6, 0.3, 0.0, INF]],  # 毛糸玉
	"perch": [[-6.8, 2.1, 0.25, INF], [-6.5, 2.1, 0.39, INF], [-6.25, 2.1, 0.18, INF]],   # 切り株の上（カエルだけ）
}
## その子らしさ: 名前 → {何をどれだけ選ぶか（重み）, 歩く速さ (m/s), 一つのことを続ける秒 [短い, 長い]}
const NATURE := {
	"kit": {"wander": 3, "sit": 2, "bed": 3, "food": 1, "toy": 2, "speed": 0.9, "stay": [3.0, 9.0]},
	"chiyo_fox": {"wander": 2, "sit": 2, "bed": 4, "food": 1, "toy": 1, "speed": 0.8, "stay": [4.0, 12.0]},
	"frog": {"wander": 3, "sit": 2, "water": 3, "perch": 3, "speed": 0.7, "stay": [3.0, 8.0]},
	"rabbit": {"wander": 4, "sit": 2, "food": 2, "toy": 1, "speed": 1.1, "stay": [2.0, 6.0]},
	"yarn": {"wander": 3, "toy": 5, "sit": 1, "speed": 1.2, "stay": [2.0, 5.0]},
	"pony": {"wander": 3, "sit": 2, "food": 3, "water": 2, "speed": 0.7, "stay": [4.0, 10.0]},
	"peacock": {"wander": 4, "sit": 2, "food": 1, "speed": 0.6, "stay": [3.0, 8.0]},
}
const SLEEP_IN := 1.5        # 寝床に着いてから寝るまで (s)

var main: Node               # main.gd（見る人を探す）
var scale_xz := Vector3.ONE  # 組んだ寸法 → 山師の節の座標（x は左右を映すとき負）
var _pets: Array = []        # {key, pet, pos, yaw, vel, phase, pose, act, goal, goal_h, face, until, spot, …}
var _frame := -1
var _rng := RandomNumberGenerator.new()
var _taken := {}             # 使っている過ごす所（"bed:0" → ミニオンの番号）


## ミニオン key を、組んだ寸法の所 at（y は高さ）に、姿 pose で置く
func add(key: String, at: Vector3, yaw: float, pose: String) -> void:
	var node: Node3D = Pals.scene(key).instantiate()
	Pals.paint(node)
	add_child(node)
	var poses := {}
	var parts := {}
	var rest := {}
	for c in node.get_children():
		var p := Pals.part_name(c)
		if not p in ["walk", "sit", "sleep"]:
			continue
		poses[p] = c
		parts[p] = {}
		rest[p] = {}
		for pc in c.get_children():
			parts[p][Pals.part_name(pc)] = pc
			rest[p][Pals.part_name(pc)] = (pc as Node3D).transform
	var m := {"key": key, "pet": {"node": node, "poses": poses, "parts": parts, "rest": rest, "spec": Pals.PET[key]},
		"pos": at, "yaw": yaw, "vel": Vector3.ZERO, "phase": 0.0, "pose": pose, "act": "sleep" if pose == "sleep" else "sit",
		"goal": at, "goal_h": at.y, "face": yaw, "until": 0.0, "spot": "", "still": 0.0, "i": _pets.size()}
	_rng.seed = hash(key)
	m.until = _rng.randf_range(2.0, 10.0)   # はじめの過ごし方を、子ごとにずらして終える
	if pose == "sleep":   # 寝床で寝ているところから始める（いちばん近い寝床を使う）
		var beds: Array = SPOTS.bed
		var bi := 0
		for i in beds.size():
			if Vector2(beds[i][0], beds[i][1]).distance_to(Vector2(at.x, at.z)) < Vector2(beds[bi][0], beds[bi][1]).distance_to(Vector2(at.x, at.z)):
				bi = i
		m.act = "bed"
		m.spot = "bed:%d" % bi
		m.goal_h = at.y
		m.still = SLEEP_IN + 1.0
		m.until = _rng.randf_range(8.0, 20.0)
		_taken[m.spot] = m.i
	_pets.append(m)
	_show(m)
	_place(m)


func _show(m: Dictionary) -> void:
	for k in m.pet.poses:
		(m.pet.poses[k] as Node3D).visible = k == m.pose


func _place(m: Dictionary) -> void:
	(m.pet.node as Node3D).transform = Transform3D(Basis(Vector3.UP, _yaw_out(m.yaw)), (m.pos as Vector3) * scale_xz)


## 組んだ寸法の向きを、左右を映したときの向きへ
func _yaw_out(yaw: float) -> float:
	return -yaw if scale_xz.x < 0.0 else yaw


## 点 p（組んだ寸法の x, z）が、柵の内側で、物の円の外か
func _free(p: Vector2, pad := 0.0) -> bool:
	if not AREA.grow(-pad).has_point(p):
		return false
	for b in BLOCK:
		if p.distance_to(Vector2(b[0], b[1])) < float(b[2]) + pad:
			return false
	return true


## a から b へ、物の円を通らずにまっすぐ行けるか
func _clear_path(a: Vector2, b: Vector2) -> bool:
	for k in 9:
		var p := a.lerp(b, k / 8.0)
		if p.distance_to(a) < 0.45:   # 切り株の上・かごの中から降りる所は見ない
			continue
		if not _free(p, 0.05):
			return false
	return true


## 次にすることを、その子らしさの重みで選ぶ
func _next(m: Dictionary) -> void:
	var nat: Dictionary = NATURE.get(m.key, NATURE.kit)
	_release(m)
	var acts := []
	var total := 0.0
	for a in ["wander", "sit", "bed", "food", "water", "toy", "perch"]:
		var w := float(nat.get(a, 0))
		if w > 0.0:
			acts.append([a, w])
			total += w
	var r := _rng.randf() * total
	var act := "wander"
	for a in acts:
		r -= float(a[1])
		if r <= 0.0:
			act = a[0]
			break
	var here := Vector2(m.pos.x, m.pos.z)
	var stay: Array = nat.stay
	m.until = _rng.randf_range(stay[0], stay[1])
	m.face = INF
	m.goal_h = 0.0
	if act in SPOTS:
		var spots: Array = SPOTS[act]
		var order: Array = range(spots.size())
		order.shuffle()
		for i in order:
			var s: Array = spots[i]
			var id := "%s:%d" % [act, i]
			if _taken.has(id) or not _clear_path(here, Vector2(s[0], s[1])) and act != "bed" and act != "perch":
				continue
			_taken[id] = m.i
			m.spot = id
			m.goal = Vector3(s[0], 0.0, s[1])
			m.goal_h = float(s[2])
			m.face = float(s[3])
			m.act = act
			if act == "bed":
				m.until = _rng.randf_range(stay[1], stay[1] * 2.5)   # 寝るのは長め
			return
		act = "wander"   # 空いていない・行けない
	if act == "sit":
		m.act = "sit"
		m.goal = m.pos
		return
	for t in 12:   # 歩き回る: 柵の中の、まっすぐ行ける所
		var p := Vector2(_rng.randf_range(AREA.position.x, AREA.end.x), _rng.randf_range(AREA.position.y, AREA.end.y))
		if _free(p, 0.1) and _clear_path(here, p) and p.distance_to(here) > 0.6:
			m.goal = Vector3(p.x, 0.0, p.y)
			m.act = "wander"
			return
	m.act = "sit"
	m.goal = m.pos


func _release(m: Dictionary) -> void:
	if m.spot != "":
		_taken.erase(m.spot)
		m.spot = ""


## 座っているとき見る所（世界）: 近くの人、いなければ柵の毛糸玉
func _look_at(m: Dictionary) -> Vector3:
	var me: Vector3 = (m.pet.node as Node3D).global_position
	var best := Vector3.INF
	var bd := 6.0
	var people: Array = []
	if main and main.get("player"):
		people.append(main.player)
	var net = main.get_node_or_null("Net") if main else null
	if net and net.get("remotes") != null:
		people.append_array(net.remotes.values())
	people = people.filter(func(p): return not Ghost.gone(p))   # 観戦モードの霊体（ghost.gd）は見ない
	for p in people:
		if p is Node3D and is_instance_valid(p) and (p as Node3D).global_position.distance_to(me) < bd:
			bd = (p as Node3D).global_position.distance_to(me)
			best = (p as Node3D).global_position + Vector3.UP * 1.2
	if best == Vector3.INF:
		var toy: Array = SPOTS.toy[m.i % SPOTS.toy.size()]
		best = to_global(Vector3(toy[0], 0.1, toy[1]) * scale_xz)
	return best


func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	for m in _pets:
		_move(m, dt)
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	_frame = fi
	for m in _pets:
		var want: String = m.pose
		var spd: float = (m.vel as Vector3).length()
		if spd > 0.12:
			want = "walk"
		elif m.act == "bed" and m.still > SLEEP_IN:
			want = "sleep"
		elif m.still > 0.3:
			want = "sit"
		if want != m.pose:
			m.pose = want
			_show(m)
		var big := 1.0
		Companions.pose_parts(m.pet, m.pose, m.phase, fi + m.i * 7, big, _look_at(m), true)


## 居場所: 行き先へ歩き、着いたらそこで過ごし、時間が来たら次のことを選ぶ
func _move(m: Dictionary, dt: float) -> void:
	var nat: Dictionary = NATURE.get(m.key, NATURE.kit)
	var d: Vector3 = m.goal - m.pos
	d.y = 0.0
	var dist := d.length()
	var arrive := dist < 0.08
	var speed := 0.0
	if not arrive:
		speed = clampf(dist * 2.5, 0.0, float(nat.speed))
	var v: Vector3 = (d.normalized() * speed) if not arrive else Vector3.ZERO
	m.vel = (m.vel as Vector3).lerp(v, 1.0 - exp(-dt * 6.0))
	var step: Vector3 = m.vel * dt
	var np: Vector3 = m.pos + step
	if not _free(Vector2(np.x, np.z), 0.0) and _free(Vector2(m.pos.x, m.pos.z), 0.0) and m.act != "bed" and m.act != "perch":   # めり込みそうなら止まって、次を選ぶ（物の上からは降りてよい）
		m.vel = Vector3.ZERO
		m.goal = m.pos
		m.until = 0.0
	else:
		m.pos = np
	var spd: float = (m.vel as Vector3).length()
	# 高さ: 行き先の高さへ、残りの道のりに合わせて上がる（切り株の上・かごの中）
	var h: float = m.goal_h if dist < 0.35 else 0.0
	m.pos.y = lerpf(m.pos.y, h, 1.0 - exp(-dt * 10.0))
	m.phase = float(m.phase) + spd * dt / float(m.pet.spec.step) * PI
	var face: float = m.yaw
	if spd > 0.12:
		face = atan2(-m.vel.x, -m.vel.z)
		m.still = 0.0
	else:
		m.still = float(m.still) + dt
		if m.face != INF:
			face = PI + float(m.face)   # 器・水桶の方へ（正面は +Z）
		elif m.act == "toy":   # 毛糸玉のまわりをぐるぐる: ときどき少し回る
			face = m.yaw + dt * 0.8
	if m.act == "toy" and arrive and int(m.still * 2.0) % 6 == 5:   # 遊ぶ: ときどき毛糸玉の向こうへ跳ねていく
		var a := _rng.randf() * TAU
		var p := Vector2(m.goal.x + cos(a) * 0.35, m.goal.z + sin(a) * 0.35)
		if _free(p, 0.05):
			m.goal = Vector3(p.x, 0.0, p.y)
	m.yaw = lerp_angle(m.yaw, face, 1.0 - exp(-dt * 8.0))
	if arrive:
		m.until = float(m.until) - dt
		if m.until <= 0.0:
			_next(m)
	_place(m)
