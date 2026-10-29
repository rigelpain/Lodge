extends Node3D
## 雪に縫い留められたボタン（2026-10-30 代表）。斜面の雪に、大きな木のボタンが糸で「×」にゆるく縫い付けてある。
## ソリの滑り木（米袋も）が上を通ると糸がぷつんと切れ、ボタンがぽんと跳ね上がって取れる（お金。craft.gd の財布）。
##
## 並べ方: 列は作らず、一つずつばらばらに置く（2026-10-30 代表「ボタンは列を作らずばらばらがいい」）。
##   ソリは体重移動でゆっくりしか曲がらないので、いくつも拾うには、押し出す向きで狙い、乗っている人が息を合わせて体重をかける。
## 分け方: 取ったボタンは、そのソリに乗っていた全員に 1 つずつ入る（分け合って減らない）。そのソリを押したり紐で引いたり
##   して手伝ったけれど乗らなかった人にも、少し（HELPER_SHARE。端数はためて、1 つになったら入る）。奪い合いにはしない。
## 新しいボタン: 空からひらひら降ってきて、落ちた所に糸がするっと縫い付く（12 fps のコマ撮り）。置き場所はランダムだが、
##   高い所から長く滑るほど通れる所に出やすい（_pick_spot）。時間がたつと雪に埋もれて消える。滑りあと（sled.gd）と同じく、
##   吹きだまりのまとまりと一つずつのばらつきで、まばらに消える。
## 風: ゆるく留まっているので、風でふわっとめくれ上がったり、ころころ転がったりして、糸に引かれて戻る（見た目だけ）。
##
## 出来事（craft.gd・emotes.gd と同じ形。中身は数・文字・Vector3 だけ）。ホストが決めて配る:
##   drop   {id, at, up, yaw, color, end}            ボタンが降る（frame から降り始める。end は埋もれきるコマ）
##   snip   {id, sled, at}                           ソリ（名前）が、ボタン id の糸を切った
##   share  {id, gives: {番号: 数}, parts: {番号: 端数}, at}  切ったボタンを分ける。数はそのあと craft の earn で財布へ
## いまは一人の画面の中だけ: send() がすぐ _apply() して配る。通信を入れたら、当たりの判定（_physics_process）と
## 置き場所選び・分け方はホストだけがして、ほかの人は出来事を受けて見た目を動かす（風の揺れは各自の画面だけ）。

signal happened(ev: Dictionary)

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Props := preload("res://props.gd")
const Rope := preload("res://sled_rope.gd")

const BUTTON_GLB := "res://props/snow_button/snow_button.glb"
const R := 0.25                # ボタンの半径 (m。glb)
const THICK := 0.058           # ボタンの厚み (m)

# ---- 出し方（調整する値）
const MAX_BUTTONS := 14              # 斜面に同時に出ているボタンの数
const FIRST_DROP := 1.5              # 始まってから最初のボタンが降るまで (s)
const FIRST_BURST := 6               # 始まってすぐ、続けて降らせる数
const DROP_EVERY := Vector2(3.0, 7.0)   # 足りないとき、次のボタンが降るまで (s)
const AWAY := 3.0                    # ほかのボタンから、これより離して置く (m)
const SPOT_R := Vector2(7.0, 45.0)   # 置く、頂上からの距離 (m)
const COLORS := ["B8402E", "34477E", "D9A53C", "5E8A4E", "C2577E", "2F7F86"]   # 糸の色（赤・藍・からし・緑・桃・青緑）。一つずつ選ぶ
# 高い所から長く滑るほど通れる所に出やすく（_pick_spot）。
# 初めは決めた形（頂上からふもと（+z。登り道の側）へ下る道を中心に、頂上に近いほど多い）、
# 滑った跡（TRAFFIC）がたまると、実際に長く滑った所へ寄っていく
const MAIN_DIR := PI / 2             # よく滑る向き（xz の角度。+z）
const MAIN_SPREAD := 0.6             # その向きの広がり (rad)
const OFF_PATH := 0.15               # 道から外れた向きの重み（道の重みに対して）
const TRAFFIC_CELL := 4.0            # 滑った跡を数えるます目 (m)
const TRAFFIC_GAIN := 3.0            # 滑った跡の重み（決めた形の重みに足す）
const TRAFFIC_HALF := 600.0          # 滑った跡が半分に薄れるまで (s)

# ---- 取る
const HIT := 0.12              # 滑り木がボタンの縁からこれだけ外を通っても切れる (m)
const MIN_SPEED := 2.0         # これより遅いソリでは切れない (m/s)
const VALUE := 1               # 乗っていた一人ひとりに入るボタンの数
const HELPER_SHARE := 1.0 / 3.0   # 押して手伝ったけれど乗らなかった人に届く割合
const HELP_WINDOW := 120.0     # 滑る前のこの秒のうちに押した人を、手伝った人にする（ソリの時計 sled._trail_now）

# ---- 消える（滑りあとと同じ考え方。sled.gd の TRAIL_*）
const LIFE := 200.0            # 埋もれきるまでの時間のまんなか (s)
const LIFE_PATCH := 0.4        # 吹きだまりのまとまりで、残る時間がずれる割合（±）
const LIFE_PATCH_SIZE := 6.0   # 吹きだまりのまとまりの大きさ (m)
const LIFE_SCATTER := 0.35     # 一つずつのばらつき（±）
const BURY_PART := 0.25        # 残る時間のうち、埋もれていく時間の割合
const BURY_MIN := 6.0          # 埋もれていく時間の下限 (s)

# ---- 動き（コマ。12 コマで 1 秒）
const FALL_FRAMES := 34        # 空から降ってくる
const FALL_H := 13.0           # 降り始める高さ (m)
const SEW_FRAMES := 10         # 落ちた所に糸が縫い付く
const POP_UP := 7              # 跳ね上がる
const POP_FLY := 7             # ソリへ飛んでいく
const ROLL_FRAMES := [0, 18, 37, 49, 63, 82, 108, 135, 158, 172, 180]   # 転がるとき、1 回分（180°）のめくれ角の並び（度）

const TAIL_LEN := [0.46, 0.34]   # ほどけた糸の端の長さ (m)
const TAIL_SEG := 7
const THREAD_R := 0.011          # 糸の太さ（半径 m）。遠くでは太く描く（THREAD_FAR）
const THREAD_FAR := 0.0004       # 1 m 離れるごとに足す太さ（遠くからもそよぐ糸が見えるように）
const THREAD_SIDES := 5
const DRAW_NEAR := 45.0          # これより遠いボタンの糸は、描き直さない

var world: Node3D               # main.gd
var auto := true                # 自分で降らせる（確かめの台本は false にして drop_at で置く）
var gust_override := -1.0       # 確かめ用: 0〜1 なら、風の強さをこれに固定する
var buttons := {}               # 番号 → Btn
var crumbs := {}                # 人の番号 → ためている端数（手伝った人の分）
var stats := {"snip": 0}        # 確かめ用の数
var _next_id := 1
var _drop_t := FIRST_DROP
var _burst := FIRST_BURST
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()   # 風
var _life_noise := FastNoiseLite.new()
var _traffic := {}              # ます目 → 重み
var _runs := {}                 # ソリ → {top: 滑り始めの高さ, cells: {ます目: true}}
var _clock := 0.0
var _confetti_mat: StandardMaterial3D
var _thread_mats := {}
var _cam_pos := Vector3.ZERO
var _last_frame := -1


class Btn:
	var id: int
	var r := R
	var at: Vector3             # 雪の上の置き場（世界）
	var up: Vector3
	var yaw := 0.0
	var root: Node3D            # at に置いた、雪面の向きの台（ボタンの座標の原点）
	var body: Node3D            # glb
	var holes: Array = []       # 穴の口（ボタンの座標で、休んでいるとき）
	var anchors: Array = []     # 糸が雪に潜る所（台の座標）
	var knot: Vector3           # ほどけた糸の端の根元（台の座標）
	var tail_dir: Array = []    # 端の休む向き
	var thread: MeshInstance3D
	var mesh: ImmediateMesh
	var lid: MeshInstance3D     # かぶさる雪
	var start := 0              # 降り始めるコマ
	var land := 0               # 雪に着くコマ
	var end_f := 0              # 埋もれきるコマ
	var bury_f := 1             # 埋もれていくコマ数
	var state := "fall"         # fall・sew・rest・pop・gone
	var roll0 := -1             # 転がり始めたコマ
	var rolls := 1
	var next_roll := 0.0        # 次に転がれるまでの秒
	var psi := 0.0              # めくれ角（度。風の揺れと転がり）
	var pop0 := -1
	var target: Node3D          # 跳ねたあと飛んでいく先（ソリ）
	var pop_from := Vector3.ZERO
	var drawn := -99
	var sd := 0                 # 見た目のばらつきの種
	var roll_w := Vector3.RIGHT  # 転がる向き（台の座標）
	var cut_bits := false       # 切れた糸の残り（跳ねたあと、しばらく雪に残る）


func _ready() -> void:
	name = "SnowButtons"
	_rng.randomize()
	_noise.seed = 21
	_noise.frequency = 0.04
	_life_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_life_noise.frequency = 1.0 / LIFE_PATCH_SIZE
	_life_noise.seed = _rng.randi()


## 出来事を出す。ホストが呼ぶ（いまはすぐ配る）
func send(ev: Dictionary) -> void:
	if not ev.has("frame"):
		ev["frame"] = Doll.frame_index() + 1
	_apply(ev)


func _apply(ev: Dictionary) -> void:
	match ev.kind:
		"drop":
			buttons[int(ev.id)] = _make_button(ev)
		"snip":
			var b: Btn = buttons.get(int(ev.id))
			if b == null or b.state != "rest":
				return
			var sled := world.get_node_or_null(String(ev.sled)) if world else null
			_pop(b, int(ev.frame), sled)
		"share":
			pass   # 財布へは craft.gd の earn。ここは見た目だけ（いまはなし。HUD は earn を聞く）
	happened.emit(ev)


# ================================================================ ホスト: 出す

func _physics_process(dt: float) -> void:
	_clock += dt
	if world == null:
		return
	_track_runs(dt)
	if auto:
		_drop_t -= dt
		if _drop_t <= 0.0:
			_drop_t = 0.4 if _burst > 0 else _rng.randf_range(DROP_EVERY.x, DROP_EVERY.y)
			_burst -= 1
			if _live() < MAX_BUTTONS:
				var p := _pick_spot()
				if p != Vector3.INF:
					drop_at(p)
	_check_hits()


func _live() -> int:
	var n := 0
	for b in buttons.values():
		if b.state != "gone" and b.state != "pop":
			n += 1
	return n


## ボタンを降らせる（ホスト）。p は雪の上の点（xz だけ使う。高さと向きはここで決める）。番号を返す
## instant: 確かめ用。降ってくる動きを飛ばして、もう縫い付いた所から始める
func drop_at(p: Vector3, color_i := -1, instant := false) -> int:
	var id := _next_id
	_next_id += 1
	var f0 := Doll.frame_index() + 1
	if instant:
		f0 -= FALL_FRAMES + SEW_FRAMES + 1
	var at := _on_snow(p)
	var life := LIFE * maxf(0.2, 1.0 + LIFE_PATCH * clampf(_life_noise.get_noise_2d(at.x, at.z) * 1.6, -1.0, 1.0)
			+ LIFE_SCATTER * _rng.randf_range(-1.0, 1.0))
	var c: String = COLORS[_rng.randi() % COLORS.size() if color_i < 0 else color_i]
	send({"kind": "drop", "id": id, "at": at, "up": _normal(at), "yaw": _rng.randf() * TAU, "color": c,
			"end": f0 + FALL_FRAMES + SEW_FRAMES + int(life * Doll.FPS), "frame": f0})
	return id


## 雪の上の高さ（見た目の雪面）
func _on_snow(p: Vector3) -> Vector3:
	var y: float = world.height(p.x, p.z) + world.snow_lift(p.x, p.z)
	return Vector3(p.x, y, p.z)


func _normal(p: Vector3) -> Vector3:
	var e := 0.4
	var hx: float = world.height(p.x + e, p.z) - world.height(p.x - e, p.z)
	var hz: float = world.height(p.x, p.z + e) - world.height(p.x, p.z - e)
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()


## 置いてよい所か: ロッジの近くでない、斜面の上、ほかのボタンから離れている、木や小物に重ならない
func _free_spot(p: Vector3) -> bool:
	var r := Vector2(p.x, p.z).length()
	if r < 4.0 or r > 60.0 or world.lodge_weight(p.x, p.z) < 1.0:
		return false
	for b in buttons.values():
		if b.state != "gone" and Vector2(b.at.x - p.x, b.at.z - p.z).length() < AWAY:
			return false
	if not is_inside_tree():
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.4
	q.shape = sph
	q.transform = Transform3D(Basis(), _on_snow(p) + Vector3.UP * 1.6)
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 4):
		var c: Object = hit.collider
		if c is StaticBody3D and (c as Node).get_child_count() > 0 and (c as Node).get_child(0) is CollisionShape3D \
				and ((c as Node).get_child(0) as CollisionShape3D).shape is HeightMapShape3D:
			continue
		if c is RigidBody3D or c is CharacterBody3D:
			continue
		return false
	return true


## 置き場所を選ぶ: 候補をいくつか取り、重み（spot_weight）で引く
func _pick_spot() -> Vector3:
	var cands := []
	var total := 0.0
	for i in 40:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(SPOT_R.x, SPOT_R.y)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var w := spot_weight(p)
		if w <= 0.0 or not _free_spot(p):
			continue
		cands.append([p, w])
		total += w
	if cands.is_empty():
		return Vector3.INF
	var pick := _rng.randf() * total
	for c in cands:
		pick -= c[1]
		if pick <= 0.0:
			return c[0]
	return cands[cands.size() - 1][0]


## 置き場所の重み。高い所から長く滑るほど通れる所ほど大きい。
## 決めた形: 頂上からふもと（+z）へ下る道の向きほど、頂上に近いほど（そこより下へ滑る人みんなが通る）大きい。
## ただし頂上のすぐ下は遅いので、少し下りてから。滑った跡がたまったら、その重みを足す
func spot_weight(p: Vector3) -> float:
	var r := Vector2(p.x, p.z).length()
	var a := atan2(p.z, p.x)
	var off := absf(wrapf(a - MAIN_DIR, -PI, PI))
	var dir_w := OFF_PATH + (1.0 - OFF_PATH) * exp(-pow(off / MAIN_SPREAD, 2.0))
	var reach := smoothstep(5.0, 10.0, r) * exp(-(r - 10.0) / 22.0)
	return dir_w * reach + TRAFFIC_GAIN * _traffic.get(_cell(p), 0.0)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TRAFFIC_CELL), floori(p.z / TRAFFIC_CELL))


## 滑った跡を数える: 乗って下っているソリが通ったます目を覚えておき、滑り終わったら、その滑りで下った高さ（頂上の高さで割る）を
## 重みとして足す。長く・高くから滑った道ほど重い。古い跡は薄れていく
func _track_runs(dt: float) -> void:
	var fade := pow(0.5, dt / TRAFFIC_HALF)
	if Engine.get_physics_frames() % 60 == 0:
		for c in _traffic.keys():
			_traffic[c] *= pow(fade, 60.0)
			if _traffic[c] < 0.002:
				_traffic.erase(c)
	for s in get_tree().get_nodes_in_group("sleds"):
		var sled := s as RigidBody3D
		var riding: bool = not sled.riders.is_empty() and sled.linear_velocity.length() > 2.0 and sled.linear_velocity.y < 0.3
		var run: Dictionary = _runs.get(sled, {})
		if riding:
			if run.is_empty():
				run = {"top": sled.global_position.y, "cells": {}}
				_runs[sled] = run
			run.cells[_cell(sled.global_position)] = true
		elif not run.is_empty() and sled.linear_velocity.length() < 0.5:
			var drop := (float(run.top) - sled.global_position.y) / maxf(1.0, world.height(0.0, 0.0))
			if drop > 0.05:
				for c in run.cells:
					_traffic[c] = _traffic.get(c, 0.0) + drop
			_runs.erase(sled)
	for s in _runs.keys():
		if not is_instance_valid(s):
			_runs.erase(s)


# ================================================================ ホスト: 取る

## 乗っている人のいる、動いているソリの滑り木が、休んでいるボタンの上を通ったら糸を切る
func _check_hits() -> void:
	for s in get_tree().get_nodes_in_group("sleds"):
		var sled := s as RigidBody3D
		if sled.riders.is_empty() or sled.linear_velocity.length() < MIN_SPEED:
			continue
		var c := sled.global_position
		var segs := runner_segments(sled)
		for b in buttons.values():
			if b.state != "rest" or b.at.distance_squared_to(c) > 64.0:
				continue
			if _under_runner(b, segs):
				_snip(sled, b)


## 滑り木（左右の 2 本）の、雪に触れる線（世界）
static func runner_segments(sled: RigidBody3D) -> Array:
	var out := []
	for sx in [-sled.RUNNER_X, sled.RUNNER_X]:
		out.append([sled.to_global(Vector3(sx, 0, -sled.RUNNER_Z - 0.1)), sled.to_global(Vector3(sx, 0, sled.RUNNER_Z + 0.1))])
	return out


func _under_runner(b: Btn, segs: Array) -> bool:
	for sg in segs:
		var a: Vector3 = sg[0]
		var e: Vector3 = sg[1]
		if absf((a.y + e.y) * 0.5 - b.at.y) > 0.8:
			continue
		var p := Geometry3D.get_closest_point_to_segment(Vector3(b.at.x, 0, b.at.z), Vector3(a.x, 0, a.z), Vector3(e.x, 0, e.z))
		if Vector2(p.x - b.at.x, p.z - b.at.z).length() < b.r + HIT:
			return true
	return false


func _snip(sled: RigidBody3D, b: Btn) -> void:
	send({"kind": "snip", "id": b.id, "sled": String(sled.name), "at": b.at})
	stats.snip += 1
	_share(sled, b.id, VALUE, b.at)


## 切ったボタンを分ける: 乗っていた全員に n、押して手伝ったけれど乗らなかった人に n × HELPER_SHARE（端数はためる）
func _share(sled: RigidBody3D, id_: int, n: int, at: Vector3) -> void:
	var gives := {}
	var parts := {}
	var riders := []
	for r in sled.riders:
		var id = r.get("id")
		if id != null and int(id) >= 0:
			riders.append(int(id))
			gives[int(id)] = n
	var helped: Dictionary = sled.get("helped") if sled.get("helped") != null else {}
	for h in helped:
		if not is_instance_valid(h) or sled._trail_now - float(helped[h]) > HELP_WINDOW:
			continue
		var id = h.get("id")
		if id == null or int(id) < 0 or int(id) in riders:
			continue
		var c: float = crumbs.get(int(id), 0.0) + n * HELPER_SHARE
		var whole := floori(c + 0.0001)
		crumbs[int(id)] = c - whole
		parts[int(id)] = crumbs[int(id)]
		if whole > 0:
			gives[int(id)] = whole
	send({"kind": "share", "id": id_, "gives": gives, "parts": parts, "at": at})
	var craft: Node = world.get("craft") if world else null
	if craft:
		for who in gives:
			craft.send({"kind": "earn", "who": who, "n": gives[who], "at": at})


# ================================================================ 見た目

func _make_button(ev: Dictionary) -> Btn:
	var b := Btn.new()
	b.id = int(ev.id)
	b.at = ev.at
	b.up = ev.up
	b.yaw = float(ev.yaw)
	b.start = int(ev.frame)
	b.land = b.start + FALL_FRAMES
	b.end_f = int(ev.end)
	b.bury_f = int(maxf(BURY_MIN, (b.end_f - b.land) / float(Doll.FPS) * BURY_PART) * Doll.FPS)
	b.sd = absi(hash(b.id * 7919 + 13))
	b.next_roll = 3.0 + float(b.sd % 700) / 100.0
	b.root = Node3D.new()
	b.root.name = "Button%d" % b.id
	var bs := Basis(Quaternion(Vector3.UP, b.up.normalized())) * Basis(Vector3.UP, b.yaw)
	b.root.transform = Transform3D(bs, b.at)
	add_child(b.root)
	b.body = Props.make(BUTTON_GLB)
	b.root.add_child(b.body)
	for k in 4:
		var h := b.body.find_child("hole_%d" % k, true, false) as Node3D
		b.holes.append(h.position if h else Vector3(cos(PI / 4 + PI / 2 * k), 0.7, sin(PI / 4 + PI / 2 * k)) * b.r * 0.3)
	for k in 4:
		var hp: Vector3 = b.holes[k]
		b.anchors.append(Vector3(hp.x * 1.25, -0.01, hp.z * 1.25))
	var ka := float(b.sd % 628) / 100.0
	b.knot = Vector3(cos(ka), 0, sin(ka)) * b.r * 0.92
	for k in 2:
		var ta := ka + (0.5 if k == 0 else -0.6)
		b.tail_dir.append(Vector3(cos(ta), 0, sin(ta)))
	b.mesh = ImmediateMesh.new()
	b.thread = MeshInstance3D.new()
	b.thread.mesh = b.mesh
	b.thread.material_override = _thread_mat(Color(ev.color))
	b.thread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.root.add_child(b.thread)
	b.lid = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = b.r * 1.25
	lm.height = b.r * 0.7
	lm.radial_segments = 16
	lm.rings = 6
	b.lid.mesh = lm
	b.lid.material_override = _lid_mat()
	b.lid.visible = false
	b.root.add_child(b.lid)
	b.root.visible = false
	return b


func _thread_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html(false)
	if not _thread_mats.has(key):
		var m: StandardMaterial3D = Rope.material().duplicate()
		m.albedo_color = c * 1.15
		m.rim = 0.35
		_thread_mats[key] = m
	return _thread_mats[key]


static var _lid: StandardMaterial3D

static func _lid_mat() -> StandardMaterial3D:
	if _lid == null:
		_lid = Look.snow()
	return _lid


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		_cam_pos = cam.global_position
	var f := Doll.frame_index()
	var t := f / float(Doll.FPS)   # 風もコマ撮り: 12 コマの時刻で読む
	var stepped := f != _last_frame
	_last_frame = f
	if not stepped:
		return
	for id in buttons.keys():
		var b: Btn = buttons[id]
		_update_button(b, f, t)
		if b.state == "gone":
			if is_instance_valid(b.root):
				b.root.queue_free()
			buttons.erase(id)


## 風の向き（水平）と、その場の強さ 0〜1（ときどき強い突風）
func wind(p: Vector3, t: float) -> Array:
	var a := 0.7 + 0.9 * _noise.get_noise_1d(t * 0.6)
	var g := clampf(0.5 + 0.9 * _noise.get_noise_3d(p.x * 1.5, p.z * 1.5, t * 6.0), 0.0, 1.0)
	if gust_override >= 0.0:
		g = gust_override
	return [Vector3(cos(a), 0, sin(a)), g]


func _update_button(b: Btn, f: int, t: float) -> void:
	if b.state == "gone":
		return
	if f < b.start:
		return
	b.root.visible = true
	match b.state:
		"fall":
			if f >= b.land:
				b.state = "sew"
				_audio("land", b.at, f)
				_audio("sew", b.at, f + 2)
				_puff(b.at, b.up, 0.4)
			else:
				_pose_fall(b, f)
				_draw_thread(b, f, t)
				return
		"sew":
			if f >= b.land + SEW_FRAMES:
				b.state = "rest"
		"pop":
			_pose_pop(b, f)
			_draw_thread(b, f, t)
			return
	if b.state in ["sew", "rest"]:
		# 埋もれる
		if f >= b.end_f:
			b.state = "gone"
			b.root.visible = false
			return
		var bury := clampf(float(f - (b.end_f - b.bury_f)) / b.bury_f, 0.0, 1.0)
		_pose_rest(b, f, t, bury)
		_draw_thread(b, f, t, bury)


## 降ってくる: 木の葉のように左右へ揺れ、揺れに合わせて傾きながら、ゆっくり落ちる
func _pose_fall(b: Btn, f: int) -> void:
	var k := float(f - b.start) / FALL_FRAMES                  # 0 → 1
	var h := FALL_H * (1.0 - k) * (1.0 - 0.35 * k)                 # 終わりほどゆっくり
	var ph := float(f - b.start) / 12.0 * TAU / 1.3 + float(b.sd % 100) / 16.0
	var sway := sin(ph) * 1.1 * (1.0 - k * 0.8)
	var side := Vector3(cos(b.sd % 7), 0, sin(b.sd % 7))
	var tilt := cos(ph) * 0.6 * (1.0 - k * 0.7)
	var spin := k * 2.5
	var bs := Basis(side.cross(Vector3.UP).normalized(), tilt) * Basis(Vector3.UP, spin)
	b.body.transform = Transform3D(bs, Vector3(0, h, 0) + side * sway + Vector3(0.6, 0, 0.4) * (1.0 - k) * 2.0)
	b.lid.visible = false


## 休んでいる: 風でふわっとめくれ、ときどき（強い突風）ころころ転がって、糸に引かれて戻る
func _pose_rest(b: Btn, f: int, t: float, bury: float) -> void:
	var w := wind(b.at, t)
	var wd: Vector3 = b.root.global_basis.inverse() * (w[0] as Vector3)
	wd.y = 0
	wd = wd.normalized() if wd.length() > 0.01 else Vector3.RIGHT
	var g: float = w[1] * (1.0 - bury)
	b.next_roll -= 1.0 / Doll.FPS
	if b.roll0 < 0 and b.state == "rest" and g > 0.85 and b.next_roll <= 0.0 and bury <= 0.0:
		b.roll0 = f
		b.rolls = 2 if (b.sd + f) % 3 == 0 else 1
		b.next_roll = 8.0 + float((b.sd + f) % 1200) / 100.0
		b.roll_w = wd
	var psi := 0.0
	var lift := 0.0
	if b.roll0 >= 0:
		wd = b.roll_w
		psi = _roll_angle(b, f - b.roll0)
		if psi < 0.0:
			b.roll0 = -1
			psi = 0.0
	if b.roll0 < 0:
		# ふわっとめくれる: 突風で風上の縁が持ち上がる（コマごとに少し震える）
		var flut := smoothstep(0.45, 0.95, g)
		psi = flut * (15.0 + 6.0 * sin(f * 1.7 + b.sd))
		lift = flut * 0.035
	b.psi = psi
	b.body.transform = _flip(b, wd, psi, lift)
	b.body.position -= Vector3.UP * bury * THICK * 1.4
	b.lid.visible = bury > 0.0
	if bury > 0.0:
		b.lid.scale = Vector3(1.0, smoothstep(0.0, 1.0, bury) * 1.0 + 0.02, 1.0) * lerpf(0.6, 1.0, bury)
		b.lid.position = Vector3(0, -b.r * 0.35 * (1.0 - bury) - 0.02, 0)


## 確かめ用: 置いてあるボタンを全部片づける
func clear() -> void:
	for b in buttons.values():
		if is_instance_valid(b.root):
			b.root.queue_free()
	buttons.clear()


## 確かめ用: 番号 id のボタンを、いま風下（向き wd・世界）へ rolls 回転がす
func force_roll(id: int, rolls: int, wd: Vector3) -> void:
	var b: Btn = buttons[id]
	var l := b.root.global_basis.inverse() * wd
	l.y = 0
	b.roll_w = l.normalized()
	b.roll0 = Doll.frame_index() + 1
	b.rolls = rolls


## 確かめ用: 番号 id のボタン（Btn。なければ null）
func button(id: int) -> Btn:
	return buttons.get(id)


## 転がる角の並び（度）。1 回か 2 回めくれて、少し止まり（糸がぴんと張る）、引かれて戻る。終われば -1
func _roll_angle(b: Btn, k: int) -> float:
	var one: Array = ROLL_FRAMES
	var out := []
	for a in one:
		out.append(float(a))
	if b.rolls == 2:
		for a in one.slice(1):
			out.append(180.0 + float(a))
	var top: float = out[out.size() - 1]
	for i in 3:   # 張って止まる。少し戻りかけて震える
		out.append(top - (6.0 if i == 1 else 0.0))
	var back := []
	for a in one:   # 引かれて戻る（同じ並びを逆に、少し速く）
		back.append(float(a))
	back.reverse()
	for n in b.rolls:
		for i in range(0, back.size(), 2 if n == 0 else 1):
			out.append(back[i] + 180.0 * (b.rolls - 1 - n))
	out.append(0.0)
	if k < 0:
		return 0.0
	return out[k] if k < out.size() else -1.0


## めくれ角 psi（度。0〜360）のときのボタンの置き方。風下の縁を軸に、風上の縁が持ち上がってめくれる。
## 180° を超えたら、裏返ったボタンが次の縁を軸にもう一度めくれる
func _flip(b: Btn, wd: Vector3, psi: float, lift: float) -> Transform3D:
	var ax := Vector3.UP.cross(wd).normalized()
	var n := int(clampf(floorf(psi / 180.0), 0.0, 1.0))
	var p := psi - 180.0 * n
	var base := Transform3D()
	if n == 1:
		var piv0 := wd * b.r + Vector3.UP * THICK * 0.5
		base = Transform3D(Basis(ax, PI), piv0 - Basis(ax, PI) * piv0)
	var piv := wd * (b.r + 2.0 * b.r * n) + Vector3.UP * THICK * 0.5
	var rot := Basis(ax, deg_to_rad(p))
	var tr := Transform3D(rot, piv - rot * piv) * base
	tr.origin += Vector3.UP * lift
	return tr


## 跳ね上がって、ソリへ飛んでいく
func _pose_pop(b: Btn, f: int) -> void:
	var k := f - b.pop0
	if k < 0:
		return
	var top := Vector3.UP * 1.5
	var spin := Basis(Vector3(1, 0, 0.4).normalized(), k * 0.9) * Basis(Vector3.UP, k * 0.5)
	if k <= POP_UP:
		var u := float(k) / POP_UP
		var y := top.y * (1.0 - pow(1.0 - u, 2.0))   # ぽんと上がって、上で止まりかける
		b.body.transform = Transform3D(spin, Vector3(0, y, 0))
		if k == 0:
			b.pop_from = b.root.to_global(Vector3(0, y, 0))
		return
	var u2 := float(k - POP_UP) / POP_FLY
	if u2 > 1.0 or b.target == null or not is_instance_valid(b.target):
		b.state = "gone"
		b.root.visible = false
		return
	var from := b.root.to_global(top)
	var to := b.target.global_position + Vector3.UP * 0.7
	var p := from.lerp(to, u2 * u2) + Vector3.UP * sin(u2 * PI) * 0.8
	var sc := lerpf(1.0, 0.35, u2 * u2)
	b.body.global_transform = Transform3D(b.root.global_basis * spin.scaled(Vector3.ONE * sc), p)


func _pop(b: Btn, f: int, sled: Node3D) -> void:
	b.state = "pop"
	b.pop0 = f
	b.target = sled
	b.roll0 = -1
	b.lid.visible = false
	b.cut_bits = true
	_audio("snap", b.at, f)
	_audio("pop", b.at, f + 1)
	_confetti(b.at + b.up * 0.15)
	# 切れた糸の残りは、しばらく雪に残って消える
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if is_instance_valid(b.thread):
			b.thread.visible = false)


# ---------------------------------------------------------------- 糸

## × の糸、雪に潜る所、ほどけた端を描き直す（12 コマごと、近いボタンだけ）
func _draw_thread(b: Btn, f: int, t: float, bury := 0.0) -> void:
	if b.drawn == f:
		return
	var d := _cam_pos.distance_to(b.at)
	if d > DRAW_NEAR and b.drawn >= 0 and b.state == "rest":
		return
	b.drawn = f
	var m := b.mesh
	m.clear_surfaces()
	var rad := THREAD_R + d * THREAD_FAR
	var paths := []
	var bt := b.body.transform
	var w := wind(b.at, t)
	var wd: Vector3 = b.root.global_basis.inverse() * (w[0] as Vector3)
	wd.y = 0
	wd = wd.normalized() if wd.length() > 0.01 else Vector3.RIGHT
	var g: float = w[1] * (1.0 - bury)
	match b.state:
		"fall":
			# 降ってくるあいだは、穴に通った短い糸の端が 2 本、後ろへたなびく
			var top0: Vector3 = bt * (b.holes[0] + Vector3.UP * 0.01)
			var top2: Vector3 = bt * (b.holes[2] + Vector3.UP * 0.01)
			paths.append(PackedVector3Array([top0, top2]))
			for k in 2:
				var s := top0 if k == 0 else top2
				var tl := PackedVector3Array([s])
				for j in 5:
					var u := (j + 1) / 5.0
					tl.append(s + Vector3.UP * u * 0.3 + bt.basis.x * sin(f * 1.3 + u * 4.0 + k) * 0.06 * u)
				paths.append(tl)
		"sew", "rest":
			var full := _sew_path(b, bt)
			if b.state == "sew":
				# 縫い付く: 糸が雪の中から穴を通って × を渡り、また潜る。コマごとに伸びていく
				var u := clampf(float(f - b.land + 1) / (SEW_FRAMES - 2), 0.0, 1.0)
				full = _cut_path(full, u)
			paths.append(full)
			if b.state == "rest" or f >= b.land + SEW_FRAMES - 3:
				for k in 2:
					paths.append(_tail(b, k, wd, g, f, bury, 1.0 if b.state == "rest" else 0.6))
		"pop":
			# 切れた糸: 雪に潜る所から、ちぎれた短い端が 4 本、上へはねて倒れる。ほどけた端はそのまま
			var k0 := f - b.pop0
			for k in 4:
				var a: Vector3 = b.anchors[k]
				var out := (a * Vector3(1, 0, 1)).normalized()
				var lay := clampf(k0 / 4.0, 0.0, 1.0)
				var tip := a + Vector3.UP * (0.16 * (1.0 - lay) + 0.01) + out * (0.06 + 0.12 * lay)
				paths.append(PackedVector3Array([a, a.lerp(tip, 0.5) + Vector3.UP * 0.03 * (1.0 - lay), tip]))
			for k in 2:
				paths.append(_tail(b, k, wd, g * 0.6, f, 0.0, 1.0))
	if paths.is_empty():
		return
	m.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in paths:
		_tube(m, p, rad)
	m.surface_end()


## 縫い目の道すじ（台の座標）: 端の根元 → 雪に潜る 0 → 穴 0 → × を渡って穴 2 → 潜る 2 → 雪の下 → 潜る 1 → 穴 1 → 穴 3 → 潜る 3
func _sew_path(b: Btn, bt: Transform3D) -> PackedVector3Array:
	var lift := Vector3.UP * 0.008
	var h := []
	for k in 4:
		h.append(bt * (b.holes[k] + lift))
	var mid0: Vector3 = (h[0] + h[2]) * 0.5 + bt.basis.y * 0.012
	var mid1: Vector3 = (h[1] + h[3]) * 0.5 + bt.basis.y * 0.022   # 上に重なる糸は少し高く
	return PackedVector3Array([b.knot, b.anchors[0], h[0], mid0, h[2], b.anchors[2], b.anchors[1], h[1], mid1, h[3], b.anchors[3]])


## 道すじの、はじめから割合 u までを返す
func _cut_path(p: PackedVector3Array, u: float) -> PackedVector3Array:
	var total := 0.0
	for i in p.size() - 1:
		total += p[i].distance_to(p[i + 1])
	var want := total * u
	var out := PackedVector3Array([p[0]])
	for i in p.size() - 1:
		var l := p[i].distance_to(p[i + 1])
		if want <= l:
			if want > 0.001:
				out.append(p[i].lerp(p[i + 1], want / l))
			break
		want -= l
		out.append(p[i + 1])
	return out


## ほどけた糸の端: 根元から休む向きへ伸び、風が強いほど風下へなびいて持ち上がり、波打つ（12 コマごとに形が変わる）
func _tail(b: Btn, k: int, wd: Vector3, g: float, f: int, bury: float, grow: float) -> PackedVector3Array:
	var tl: float = TAIL_LEN[k] * grow * (1.0 - 0.7 * bury)
	var rest: Vector3 = b.tail_dir[k]
	var dir := rest.lerp(wd, clampf(0.25 + g * 0.8, 0.0, 1.0)).normalized()
	var side := Vector3.UP.cross(dir).normalized()
	var pts := PackedVector3Array()
	var p := b.knot + Vector3.UP * 0.006
	pts.append(p)
	var ph := f * 1.9 + k * 2.1 + float(b.sd % 50)
	for j in TAIL_SEG:
		var u := (j + 1.0) / TAIL_SEG
		var wave := sin(ph - u * 7.0) * (0.03 + 0.09 * g) * u
		var rise := (0.01 + 0.13 * g * g) * u * (1.0 - bury) + 0.012 * sin(ph * 0.7 + u * 3.0) * g
		p = b.knot + dir * tl * u + side * wave + Vector3.UP * (0.008 + rise)
		pts.append(p)
	return pts


## 太さ rad の管を描く（点ごとの輪を、前の点の向きから最小の回転で運ぶ）。U は周り、V は長さ（撚りの模様の PITCH で 1）
static func _tube(m: ImmediateMesh, pts: PackedVector3Array, rad: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rings := []
	var t0 := (pts[1] - pts[0]).normalized()
	var nv := t0.cross(Vector3.UP if absf(t0.y) < 0.9 else Vector3.RIGHT).normalized()
	var s := 0.0
	var vs := []
	for i in n:
		var t: Vector3 = pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		if t.length() < 1e-5:
			t = t0
		t = t.normalized()
		nv = nv - t * nv.dot(t)
		nv = nv.normalized() if nv.length() > 1e-4 else t.cross(Vector3.UP).normalized()
		var bv := t.cross(nv)
		var ring := []
		var r := rad * (0.55 if i == 0 or i == n - 1 else 1.0)
		for k in THREAD_SIDES + 1:
			var a := TAU * k / THREAD_SIDES
			var dv := nv * cos(a) + bv * sin(a)
			ring.append([pts[i] + dv * r, dv])
		rings.append(ring)
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		vs.append(s / Rope.PITCH)
		t0 = t
	for i in n - 1:
		for k in THREAD_SIDES:
			var q := [[i, k], [i + 1, k], [i, k + 1], [i, k + 1], [i + 1, k], [i + 1, k + 1]]
			for c in q:
				var v: Array = rings[c[0]][c[1]]
				m.surface_set_normal(v[1])
				m.surface_set_uv(Vector2(float(c[1]) / THREAD_SIDES, vs[c[0]]))
				m.surface_add_vertex(v[0])


# ---------------------------------------------------------------- 粒と音

## 小さな紙吹雪: 色とりどりの紙の切れはしが、ぱっと舞って、ひらひら落ちる
func _confetti(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 22
	p.lifetime = 1.8
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 50.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0, -2.2, 0)
	p.damping_min = 1.6
	p.damping_max = 2.6
	p.angular_velocity_min = -420.0
	p.angular_velocity_max = 420.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.particle_flag_rotate_y = true
	var cr := Gradient.new()
	cr.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	cr.colors = PackedColorArray([Color("F1E8D6"), Color("D2553A"), Color("D9A53C"), Color("34477E"), Color("E59AA8"), Color("5E8A4E")])
	cr.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	p.color_initial_ramp = cr
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.045)
	if _confetti_mat == null:
		_confetti_mat = StandardMaterial3D.new()
		_confetti_mat.vertex_color_use_as_albedo = true
		_confetti_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_confetti_mat.roughness = 0.9
	q.material = _confetti_mat
	p.mesh = q
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)


## 雪の粉がぽふっと（降ってきて着いたとき）
func _puff(at: Vector3, up: Vector3, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 12
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = up
	p.spread = 80.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, -2.5, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	p.color_ramp = ramp
	p.mesh = preload("res://snowball.gd")._cotton_quad(0.16 * size / 0.4)
	add_child(p)
	p.global_position = at + up * 0.05
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _audio(what: String, at: Vector3, f: int) -> void:
	var a: Node = world.get_node_or_null("Audio") if world else null
	if a and a.has_method("button"):
		a.button(what, at, f)
