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
## お金の 4 段（TIERS）: 木 1・真鍮 10・白蝶貝 100・螺鈿 1000。降るのはほとんど木、たまに真鍮、まれに白蝶貝、ごくまれに螺鈿。
##   色・光り方・穴の数・大きさ・音で見分ける。光るボタンは、遠くからも分かるよう、上で星がきらっとまたたく（画面での大きさが一定）。
## 歩いて裁ちばさみで取る: 歩いて近づき F（player.gd）で、はさみを出してちょきんと切る（12 fps）。そのあいだは動けず、
##   取ったボタンは切った人だけに入る。ソリで通るほうが、たくさん・速く取れる。
## 滑った距離と速さでも: 一回の滑り（乗って滑り出してから止まるまで）の長さで木のボタン、いちばん速い所（RIDE_BRASS）を
##   超えるたびに真鍮のボタンが一つ。どちらも、もらえた瞬間に速さの表示（speedo.gd）の糸の上へぽんと縫い込まれ、
##   止まると糸が巻き取られて、糸の上のボタンが財布へ飛ぶ（hud.gd・craft_ui.gd）。
## 取得音: 財布に入る瞬間に、素材ごとの音（木「コッ」・真鍮「チン」・白蝶貝「シャラン」・螺鈿）を耳元で鳴らす（craft_ui.gd が
##   audio.gd の coin を呼ぶ）。ソリで取っても、はさみで取っても、滑った分でも同じ。その場では、糸が切れる「ぷつん」と「ぽん」だけ
##   分け方は雪のボタンと同じ。
##
## 出来事（craft.gd・emotes.gd と同じ形。中身は数・文字・Vector3 だけ）。ホストが決めて配る:
##   drop   {id, tier, at, up, yaw, color, end}      ボタンが降る（tier は TIERS の番号）（frame から降り始める。end は埋もれきるコマ）
##   snip   {id, sled, by, at}                       ソリ（名前）が、ボタン id の糸を切った（by は、はさみで切った人の番号。ソリなら -1）
##   share  {id, gives: {番号: 数}, parts: {番号: 端数}, at}  切ったボタンを分ける。数はそのあと craft の earn で財布へ
##   shear  {id, who}                                歩いてきた人が裁ちばさみを出した（frame + SHEAR_CUT コマで snip。snip の by に人の番号）
##   ride_mark {sled, look, speed}                   滑っているソリに、ボタンが一つ縫い込まれた（look: "wood" は RIDE_M_PER_WOOD 滑るごと、
##                                                   "brass" はいちばん速い所 speed を超えたとき）
##   ride_pay  {sled, dist, wood, brass, sewn, gives: {番号: 数}}  一回の滑りが終わった。滑った長さ（m）と、木と真鍮の数。
##                                                   sewn は縫い込んだ順のボタンの並び（"wood"・"brass"）
## いまは一人の画面の中だけ: send() がすぐ _apply() して配る。通信を入れたら、当たりの判定（_physics_process）と
## 置き場所選び・分け方はホストだけがして、ほかの人は出来事を受けて見た目を動かす（風の揺れは各自の画面だけ）。

signal happened(ev: Dictionary)

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Props := preload("res://props.gd")
const Rope := preload("res://sled_rope.gd")

const GLB_DIR := "res://props/snow_button/"
const R := 0.25                # 木のボタンの半径 (m。glb)
const THICK := 0.058           # 木のボタンの厚み (m)
## お金のボタンの 4 段（2026-10-30 代表）。財布（craft.gd）の中は「木の何個分」で持ち、見せるときに段ごとに分ける（craft.gd の split）。
## value 値打ち、glb 形、r 半径、thick 厚み、chance 斜面に降るボタンのうちの割合、spark 遠くからも分かるまたたきの色（なしは光らない）
const TIERS := [
	{"value": 1, "look": "wood", "glb": "snow_button", "r": 0.25, "thick": 0.058, "chance": 0.9, "spark": null},
	{"value": 10, "look": "brass", "glb": "snow_button_brass", "r": 0.21, "thick": 0.047, "chance": 0.085, "spark": Color(1.0, 0.82, 0.42)},
	{"value": 100, "look": "pearl", "glb": "snow_button_pearl", "r": 0.19, "thick": 0.026, "chance": 0.013, "spark": Color(0.94, 0.97, 1.0)},
	{"value": 1000, "look": "raden", "glb": "snow_button_raden", "r": 0.23, "thick": 0.056, "chance": 0.002, "spark": Color(0.7, 1.0, 0.95)},
]
const SPARK_EVERY := Vector2(1.0, 2.6)   # またたきの間 (s)。値打ちが高いほど短い
const SPARK_PX := 0.0016                 # またたきの星の、画面での大きさ（Sprite3D の fixed_size）

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
## 胴の下でも切れるソリ（2026-10-30 代表「当たりを広げる」「中も同様が良い」）。中と大は滑り木のあいだが広く（1.2 m・1.9 m）、
## 曲がりも遅いので、滑り木だけでは拾いにくかった（design/snow-buttons）。胴の下（左右の滑り木のあいだ）を通っても切れる
const BELLY := ["mid", "large"]
# ---- 歩いて裁ちばさみで取る
const SHEAR_REACH := 1.8       # ボタンまでこれより近く、向いていれば取れる (m)
const SHEAR_CUT := 8           # はさみを出してから、糸が切れるまで（コマ）。2 回目のちょきんは 10 コマ目
const SHEAR_END := 15          # はさみをしまい終わるまで（コマ）。このあいだは動けない
# ---- 滑った距離と速さ（一回の滑りごと）。斜面のボタンを拾うほうが多くもらえるくらいに
const RIDE_M_PER_WOOD := 12.0  # これだけ滑るごとに木のボタン 1 つ (m)
const RIDE_MAX_WOOD := 18      # 一回の滑りの木のボタンの上限
const RIDE_BRASS := [10.0, 13.0]     # この速さ (m/s) を超えるたびに真鍮のボタン 1 つ（一回の滑りで一度ずつ）
const RIDE_STOP_T := 1.0       # 0.5 m/s より遅いのがこれだけ続いたら、滑り終わり (s)
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
var stats := {"snip": 0, "value": 0}   # 確かめ用の数（切った数と、その値打ちの合計）
var _shears: Array = []         # 動いている裁ちばさみ {node, a, b, btn, who, f0}
var _cuts: Array = []           # ホスト: はさみで切る予定 {id, who, at}
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
	var tier := 0               # TIERS の番号
	var thick := THICK
	var spark: Sprite3D         # 光るボタンのまたたき
	var next_spark := 0.0
	var spark0 := -99
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
			if b == null or not b.state in ["rest", "shear"]:
				return
			var to: Node3D = _person(int(ev.get("by", -1))) if int(ev.get("by", -1)) >= 0 else null
			if to == null and world:
				to = world.get_node_or_null(String(ev.sled))
			_pop(b, int(ev.frame), to)
		"shear":
			var b: Btn = buttons.get(int(ev.id))
			var who := _person(int(ev.who))
			if b == null or who == null:
				return
			b.state = "shear"
			_start_shears(b, who, int(ev.frame))
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
	_do_cuts()


func _live() -> int:
	var n := 0
	for b in buttons.values():
		if b.state != "gone" and b.state != "pop":
			n += 1
	return n


## ボタンを降らせる（ホスト）。p は雪の上の点（xz だけ使う。高さと向きはここで決める）。番号を返す
## instant: 確かめ用。降ってくる動きを飛ばして、もう縫い付いた所から始める
func drop_at(p: Vector3, color_i := -1, instant := false, tier := -1) -> int:
	var id := _next_id
	_next_id += 1
	var f0 := Doll.frame_index() + 1
	if instant:
		f0 -= FALL_FRAMES + SEW_FRAMES + 1
	var at := _on_snow(p)
	var life := LIFE * maxf(0.2, 1.0 + LIFE_PATCH * clampf(_life_noise.get_noise_2d(at.x, at.z) * 1.6, -1.0, 1.0)
			+ LIFE_SCATTER * _rng.randf_range(-1.0, 1.0))
	var c: String = COLORS[_rng.randi() % COLORS.size() if color_i < 0 else color_i]
	if tier < 0:
		tier = pick_tier(_rng.randf())
	send({"kind": "drop", "id": id, "tier": tier, "at": at, "up": _normal(at), "yaw": _rng.randf() * TAU, "color": c,
			"end": f0 + FALL_FRAMES + SEW_FRAMES + int(life * Doll.FPS), "frame": f0})
	return id


## 段を選ぶ: x は 0〜1 の乱数。ほとんど木、たまに真鍮、まれに白蝶貝、ごくまれに螺鈿
static func pick_tier(x: float) -> int:
	for i in range(TIERS.size() - 1, 0, -1):
		var above := 0.0
		for j in range(i, TIERS.size()):
			above += float(TIERS[j].chance)
		if x > 1.0 - above:
			return i
	return 0


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
	# 一回の滑り: 乗っている人がいて、押されて登っているのでなく、1.5 m/s より速くなったら始まり、
	# 0.5 m/s より遅いのが RIDE_STOP_T 続くか、誰も乗らなくなったら終わり
	for s in get_tree().get_nodes_in_group("sleds"):
		var sled := s as RigidBody3D
		var v := sled.linear_velocity.length()
		var riding: bool = not sled.riders.is_empty() and not (sled.pushers > 0 and sled.linear_velocity.y > 0.05)
		var run: Dictionary = _runs.get(sled, {})
		if run.is_empty():
			if riding and v > 1.5:
				run = {"top": sled.global_position.y, "cells": {}, "dist": 0.0, "best": 0.0, "marks": [], "riders": {}, "slow": 0.0,
						"wood": 0, "sewn": []}
				_runs[sled] = run
			continue
		if riding:
			var hv := Vector2(sled.linear_velocity.x, sled.linear_velocity.z).length()
			run.dist += hv * dt
			run.best = maxf(run.best, v)
			for r in sled.riders:
				var rid = r.get("id")
				run.riders[rid if rid != null else -1] = true
			if v > 2.0:
				run.cells[_cell(sled.global_position)] = true
			for m in RIDE_BRASS:
				if v >= m and not m in run.marks:
					run.marks.append(m)
					run.sewn.append("brass")
					send({"kind": "ride_mark", "sled": String(sled.name), "look": "brass", "speed": m})
			while run.wood < mini(floori(run.dist / RIDE_M_PER_WOOD), RIDE_MAX_WOOD):   # RIDE_M_PER_WOOD 滑るごとに木を一つ
				run.wood += 1
				run.sewn.append("wood")
				send({"kind": "ride_mark", "sled": String(sled.name), "look": "wood", "speed": v})
		run.slow = run.slow + dt if (v < 0.5 or not riding) else 0.0
		if run.slow >= RIDE_STOP_T:
			var drop := (float(run.top) - sled.global_position.y) / maxf(1.0, world.height(0.0, 0.0))
			if drop > 0.05:
				for c in run.cells:
					_traffic[c] = _traffic.get(c, 0.0) + drop
			_runs.erase(sled)
			_ride_pay(sled, run)
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
		var belly: bool = sled.kind in BELLY
		for b in buttons.values():
			if b.state != "rest" or b.at.distance_squared_to(c) > 64.0:
				continue
			if _under_runner(b, segs) or (belly and _under_belly(sled, b)):
				_snip(sled, b)


## 胴の下（左右の滑り木のあいだ、滑り木の前後の長さ）をボタンが通るか
func _under_belly(sled: RigidBody3D, b: Btn) -> bool:
	var lp := sled.to_local(b.at)
	return absf(lp.y) < 0.8 and absf(lp.x) < sled.RUNNER_X and absf(lp.z) < sled.RUNNER_Z + 0.1 + b.r


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
	send({"kind": "snip", "id": b.id, "sled": String(sled.name), "by": -1, "at": b.at})
	stats.snip += 1
	stats.value += int(TIERS[b.tier].value)
	_share(sled, b.id, int(TIERS[b.tier].value), b.at)


## 切ったボタンを分ける: 乗っていた全員に n、押して手伝ったけれど乗らなかった人に n × HELPER_SHARE（端数はためる）
func _share(sled: RigidBody3D, id_: int, n: int, at: Vector3) -> void:
	var gives := _gives(sled, sled.riders.map(func(r): return r.get("id")), n)
	send({"kind": "share", "id": id_, "gives": gives.gives, "parts": gives.parts, "at": at})
	_pay(gives.gives, at)


## 財布へ（craft.gd の earn）。from: "spool" なら、画面では速さの表示の糸の上から飛ぶ。
## pieces は飛ぶボタンの並び（滑った分は縫い込んだ順）。全部（full）をもらった人にだけ付ける（手伝った人の分は段ごとに分けて飛ぶ）
func _pay(gives: Dictionary, at: Vector3, from := "", pieces := [], full := -1) -> void:
	var craft: Node = world.get("craft") if world else null
	if craft:
		for who in gives:
			var ev := {"kind": "earn", "who": who, "n": gives[who], "at": at, "from": from}
			if not pieces.is_empty() and int(gives[who]) == full:
				ev["pieces"] = pieces.duplicate()
			craft.send(ev)


## 分け方: 乗っていた人（番号の配列）に n ずつ、押して手伝ったけれど乗らなかった人に n × HELPER_SHARE（端数はためる）
func _gives(sled: RigidBody3D, rider_ids: Array, n: int) -> Dictionary:
	var gives := {}
	var parts := {}
	var riders := []
	for id in rider_ids:
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
	return {"gives": gives, "parts": parts}


# ================================================================ ホスト: 歩いて裁ちばさみで取る

## 人の番号から、その人（emotes.gd の登録）
func _person(id: int) -> Node3D:
	var hub: Node = world.get_node_or_null("Emotes") if world else null
	return hub.who_of(id) if hub and id >= 0 else null


## 人 p が歩いてはさみで取れるボタン（いちばん近いもの。なければ null）: 近く、向いていて、休んでいる
func reachable(p: Node3D) -> Btn:
	var best: Btn = null
	var bd := SHEAR_REACH
	var fwd := -p.global_basis.z
	fwd.y = 0
	for b in buttons.values():
		if b.state != "rest":
			continue
		var d: Vector3 = b.at - p.global_position
		if absf(d.y) > 1.3:
			continue
		d.y = 0
		var l := d.length()
		if l < bd and (l < 0.5 or fwd.normalized().dot(d / l) > 0.3):
			bd = l
			best = b
	return best


## 歩いてきた人 who（番号）が F を押した（player.gd）。取れるボタンがあれば、はさみを出す。断られたら false
func request_cut(who: int) -> bool:
	var p := _person(who)
	var b := reachable(p) if p else null
	if b == null:
		return false
	var f := Doll.frame_index() + 1
	send({"kind": "shear", "id": b.id, "who": who, "frame": f})
	_cuts.append({"id": b.id, "who": who, "at": f + SHEAR_CUT})
	return true


## はさみで切る予定のコマが来たら、糸を切って、切った人だけに分ける
func _do_cuts() -> void:
	var f := Doll.frame_index()
	for c in _cuts.duplicate():
		if f < int(c.at):
			continue
		_cuts.erase(c)
		var b: Btn = buttons.get(int(c.id))
		if b == null or b.state != "shear":
			continue
		var v := int(TIERS[b.tier].value)
		send({"kind": "snip", "id": b.id, "sled": "", "by": int(c.who), "at": b.at, "frame": f})
		stats.snip += 1
		stats.value += v
		send({"kind": "share", "id": b.id, "gives": {int(c.who): v}, "parts": {}, "at": b.at})
		_pay({int(c.who): v}, b.at)


# ================================================================ ホスト: 滑った距離と速さ

## 一回の滑り（乗って滑り出してから止まるまで）の長さと速さを数え、終わったら分ける
func _ride_pay(sled: RigidBody3D, run: Dictionary) -> void:
	var dist: float = run.dist
	var wood: int = run.wood
	var brass: int = run.marks.size()
	var n := wood + 10 * brass
	if n <= 0:
		return
	var g := _gives(sled, run.riders.keys(), n)
	send({"kind": "ride_pay", "sled": String(sled.name), "dist": dist, "wood": wood, "brass": brass, "sewn": run.sewn, "gives": g.gives})
	_pay(g.gives, sled.global_position, "spool", run.sewn, n)


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
	b.tier = clampi(int(ev.get("tier", 0)), 0, TIERS.size() - 1)
	var spec: Dictionary = TIERS[b.tier]
	b.r = spec.r
	b.thick = spec.thick
	b.body = Props.make(GLB_DIR + String(spec.glb) + ".glb")
	b.root.add_child(b.body)
	var marks := []
	for k in 4:
		var h := b.body.find_child("hole_%d" % k, true, false) as Node3D
		if h:
			marks.append(h.position)
	if marks.size() == 2:
		# 穴 2 つ: 糸は 2 つの穴のあいだを 2 回渡る（少しずらした 2 本）。× の組（0 と 2、1 と 3）に合わせて並べる
		var side: Vector3 = (marks[1] - marks[0]).cross(Vector3.UP).normalized() * 0.009
		marks = [marks[0] + side, marks[0] - side, marks[1] + side, marks[1] - side]
	for k in 4:
		b.holes.append(marks[k] if k < marks.size() else Vector3(cos(PI / 4 + PI / 2 * k), 0.7, sin(PI / 4 + PI / 2 * k)) * b.r * 0.3)
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
	if spec.spark != null:
		b.spark = Sprite3D.new()
		b.spark.texture = _spark_tex()
		b.spark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.spark.fixed_size = true
		b.spark.pixel_size = SPARK_PX
		b.spark.shaded = false
		b.spark.double_sided = true
		b.spark.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		b.spark.modulate = Color(spec.spark, 0.0)
		b.spark.position = Vector3(0, b.thick + 0.06, 0)
		b.spark.render_priority = 2
		b.body.add_child(b.spark)
		b.next_spark = float(b.sd % 100) / 100.0
	b.root.visible = false
	return b


static var _spark: ImageTexture

## またたきの星: 4 本の細い光の筋と、まんなかのにじみ（白。色は modulate）
static func _spark_tex() -> ImageTexture:
	if _spark:
		return _spark
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5) / (n / 2.0)
			var core := exp(-p.length_squared() * 18.0)
			var ray := exp(-absf(p.x) * 22.0) * maxf(0.0, 1.0 - absf(p.y)) + exp(-absf(p.y) * 22.0) * maxf(0.0, 1.0 - absf(p.x))
			var diag := Vector2(p.x + p.y, p.x - p.y) * 0.7071
			ray += 0.35 * (exp(-absf(diag.x) * 30.0) * maxf(0.0, 1.0 - absf(diag.y) * 1.6) + exp(-absf(diag.y) * 30.0) * maxf(0.0, 1.0 - absf(diag.x) * 1.6))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(core + ray * 0.9, 0.0, 1.0)))
	_spark = ImageTexture.create_from_image(img)
	return _spark


## またたき（12 コマ）: いつもは小さく薄く光り、ときどき大きくきらっと（4 コマ）。螺鈿は色が虹色に移る
func _twinkle(b: Btn, f: int, bury: float) -> void:
	if b.spark == null:
		return
	b.next_spark -= 1.0 / Doll.FPS
	if b.next_spark <= 0.0:
		b.spark0 = f
		var k := 1.0 - 0.3 * (b.tier - 1)
		b.next_spark = lerpf(SPARK_EVERY.x, SPARK_EVERY.y, float((b.sd + f) % 100) / 100.0) * k
	var shape: Array = [1.0, 1.7, 1.25, 0.7]
	var j := f - b.spark0
	var big: float = shape[j] if j >= 0 and j < shape.size() else 0.0
	var col: Color = TIERS[b.tier].spark
	if b.tier == 3:
		col = Color.from_hsv(fposmod(f * 0.07 + b.sd * 0.01, 1.0), 0.45, 1.0)
	var a := (0.45 + 0.55 * minf(big, 1.0)) * (1.0 - bury)
	b.spark.modulate = Color(col, a)
	var sc := (0.55 + big * 0.9) * (1.0 - 0.5 * bury)
	b.spark.scale = Vector3.ONE * sc
	b.spark.rotation.z = big * 0.3 + (f % 4) * 0.04


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
	_update_shears(f)
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
			_twinkle(b, f, 0.0)
			return
		"shear":   # はさみが来るのを待つ（風でめくれず、じっと）
			_draw_thread(b, f, t)
			_twinkle(b, f, 0.0)
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
		_twinkle(b, f, bury)


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
	b.body.position -= Vector3.UP * bury * b.thick * 1.4
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
		var piv0 := wd * b.r + Vector3.UP * b.thick * 0.5
		base = Transform3D(Basis(ax, PI), piv0 - Basis(ax, PI) * piv0)
	var piv := wd * (b.r + 2.0 * b.r * n) + Vector3.UP * b.thick * 0.5
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
	_audio("pop", b.at, f + 1)   # 素材ごとの取得音は、財布に入る瞬間に耳元で（craft_ui.gd → audio.gd の coin）
	_confetti(b.at + b.up * 0.15, b.tier)
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
func _confetti(at: Vector3, tier := 0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 22 + 14 * tier   # 値打ちが高いほど多く
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


func _audio(what: String, at: Vector3, f: int, tier := 0) -> void:
	var a: Node = world.get_node_or_null("Audio") if world else null
	if a and a.has_method("button"):
		a.button(what, at, f, tier)


# ---------------------------------------------------------------- 裁ちばさみ

## はさみの開き（度）と、手もと（0）からボタン（1）までの位置の並び（コマごと）。8 と 10 コマ目で「ちょきん」
const SHEAR_OPEN := [0, 0, 0, 14, 28, 38, 40, 12, 0, 26, 0, 0, 0, 0, 0]
const SHEAR_GO := [0.0, 0.0, 0.0, 0.35, 0.7, 0.92, 1.0, 1.0, 1.0, 1.0, 1.0, 0.7, 0.35, 0.0, 0.0]
const SHEAR_SCALE := [0.3, 1.15, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.45]
const SHEAR_SIZE := 1.7        # はさみの大きさ（glb の 0.46 m に掛ける。人形の手に持たせて、遠くからも読めるように）


func _start_shears(b: Btn, who: Node3D, f0: int) -> void:
	var n := Node3D.new()
	n.name = "Shears"
	var ha := Props.make(GLB_DIR + "shears_a.glb")
	var hb := Props.make(GLB_DIR + "shears_b.glb")
	n.add_child(ha)
	n.add_child(hb)
	n.visible = false
	add_child(n)
	_shears.append({"node": n, "a": ha, "b": hb, "btn": b, "who": who, "f0": f0})
	_audio("swish", who.global_position + Vector3.UP, f0)
	_audio("shears", b.at, f0 + SHEAR_CUT)
	_audio("shears", b.at, f0 + SHEAR_CUT + 2)


## はさみを動かす（12 コマ）: 手から出て、ボタンの糸へ伸び、開いて、ちょきん、ちょきん。戻ってしまう
func _update_shears(f: int) -> void:
	for s in _shears.duplicate():
		var k: int = f - int(s.f0)
		var n: Node3D = s.node
		var who: Node3D = s.who
		var b: Btn = s.btn
		if k >= SHEAR_OPEN.size() or not is_instance_valid(who):
			n.queue_free()
			_shears.erase(s)
			continue
		if k < 0:
			continue
		n.visible = true
		var fwd := -who.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP)
		var hand := who.global_position + Vector3.UP * 1.0 + fwd * 0.35 + right * 0.2
		var to: Vector3 = b.at + b.up * (b.thick + 0.05) - (b.at - who.global_position).normalized() * 0.12
		to.y = maxf(to.y, b.at.y + b.thick + 0.04)
		var p := hand.lerp(to, float(SHEAR_GO[k]))
		var dir := (to - hand).normalized() if hand.distance_to(to) > 0.05 else fwd
		if float(SHEAR_GO[k]) > 0.5:
			dir = (dir * Vector3(1, 0.4, 1)).normalized()   # 糸に近づいたら、刃を寝かせてすべり込ませる
		n.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP).scaled(Vector3.ONE * float(SHEAR_SCALE[k]) * SHEAR_SIZE), p)
		var op := deg_to_rad(float(SHEAR_OPEN[k])) * 0.5
		(s.a as Node3D).rotation.y = -op
		(s.b as Node3D).rotation.y = op
