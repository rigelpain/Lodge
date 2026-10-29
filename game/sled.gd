extends RigidBody3D

const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const Fabrics := preload("res://fabrics.gd")
const Snowball := preload("res://snowball.gd")
## 大きなソリ。誰が押しても push() を呼ぶだけ（あなたも仲間も、のちの通信の相手も同じ）。
## 押す人が少ないとじりじり、多いと目に見えて速く登る。乗る人がいると減速をゆるめて一気に滑る。
## 誰も触れていない空のソリは、坂をゆっくりずり落ちる。速く下っているソリをつかむと引きずられ、
## 止める人の力の合計が「ソリと乗っている人の重さ × 坂」に勝てば止まる（引きずりの計算はソリがまとめてする。通信ではホスト）。

const PUSH_FORCE := 300.0   # 1人が押す力 (N)。1人でも最も急な所をじりじり登れる
const CLIMB_DAMP := 3.5     # 登るときの雪の抵抗（押すのをやめるとすぐ止まる。大きいほどじりじり）
const STAND := 0.6                 # つかむ人が立つ、縁からの距離
var ROPE_LEN := 3.0           # 引き紐の長さ（KINDS の rope_len。米袋は短い）
const ROPE_K := 260.0              # 紐が張ったときの引く力 (N/m)
const SLIP_RESIST := 18.0          # 滑り木の横滑りのしにくさ（前後 2 点それぞれ）
const RUNNER_DRAG := 3.0           # 滑り木 1 本の前後方向の抵抗 (N per m/s)

## 大きさ。大きいほど重く、席が多い（2026-10-29 代表: 小はホームセンターのプラスチックの 1〜2 人用、大はサンタの 8 人乗り）。
## 米袋は 1 人用で 1 kg（2026-10-29 代表「米袋1kgにしよう」）。小の席は成形ソリの座る面の高さ（glb に合わせた）。
## 当たりの箱・滑り木・席はこの表が正。glb（props/build_sled.py）はこの寸法に合わせて作る。
## color はメインカラーの既定（glb に焼いてある主なフェルトの色。米袋は印刷の赤）。main_color で上書きできる。
## stitch は滑りあとの縫い目（STITCHES）。重いソリほど太く丈夫な縫い目（2026-10-27 代表が選んだ。props/stitches.md）。stitch_override で差し替えられる
## 乗って滑るときの手ざわり（2026-10-29 代表「小さければ小さいほど操舵性と加速がよく、最高速度が遅い。重ければ重いほど
## 操舵性と加速が悪く、最高速度が速い。乗っている人が同じ操作をすると操舵力は強くなる」）。値の意味は design/controls-and-physics.md
##   drag  底や滑り木が雪をこする抵抗 (N per m/s)。遅いときから効く
##   push  雪を押しのける・風を受ける抵抗 (N per (m/s)²)。速くなるほど急に増える。重さ（ソリ＋乗る人）に比べて小さいほど最高速度が速い
##   sink  滑り出しで雪に沈む抵抗（重さに対する割合）。plane (m/s) まで速くなると浮いて消える。滑り木のソリだけ。大きいほど出足が重い
##   turn  乗っている人一人の体重移動の効きの倍率。曲がりにくさは、ソリの長さと重さ（回りにくさ）から物理で出る
## 止まっているときの動かしやすさ（2026-10-29 代表「ソリの静止状態での移動自由度も、小さければ小さいほど高くしてほしい」）
##   stand_slip   止まっているときの横すべりのしにくさ（SLIP_RESIST に掛ける割合）。小さいほど、その場で回しやすく横にずらしやすい
##   stand_speed  この速さ (m/s) までは「止まっている」として stand_slip を使う。米袋は底が平らなので、ゆっくりなら横へも引きずれる
##   kick  乗って滑っているあいだ、Space で足で雪を蹴って進める効き（米袋だけ。KICK_DV に掛ける）
const KINDS := {
	"sack": {"mass": 1.0, "box": Vector3(0.6, 0.15, 1.1), "runner_x": 0.2, "runner_z": 0.4, "color": Color("B8402E"), "stitch": "running",
			"drag": 25.0, "push": 0.8, "sink": 0.0, "plane": 1.0, "turn": 1.0, "stand_slip": 0.03, "stand_speed": 3.0, "kick": 1.0,
			"seats": [Vector3(0, 0.15, 0.1)],
			"whole": true,                   # メインカラーは袋全体（地のクラフト紙ごと）。印刷は読める色に（props.gd の recolor）
			"rope_spare": 0.1, "rope_len": 1.2},   # 紐は前の左右の耳を結ぶ短いたわみと、まんなかから短い引っ張り紐
	"small": {"mass": 15.0, "box": Vector3(0.75, 0.45, 1.6), "runner_x": 0.28, "runner_z": 0.6, "color": Color("D2553A"), "stitch": "running",
			"drag": 1.5, "push": 3.6, "sink": 0.0, "plane": 1.0, "turn": 1.0, "stand_slip": 0.1, "stand_speed": 1.5, "kick": 0.0,
			"seats": [Vector3(0, 0.06, -0.3), Vector3(0, 0.06, 0.4)]},
	"mid": {"mass": 60.0, "box": Vector3(1.5, 0.45, 2.8), "runner_x": 0.6, "runner_z": 1.1, "color": Color("D2553A"), "stitch": "chain",
			"drag": 8.0, "push": 2.5, "sink": 0.02, "plane": 3.0, "turn": 1.0, "stand_slip": 0.3, "stand_speed": 0.6, "kick": 0.0,
			"seats": [Vector3(0, 0.45, -0.75), Vector3(0, 0.45, 0.15), Vector3(0, 0.45, 1.0)]},
	"large": {"mass": 220.0, "box": Vector3(2.2, 0.45, 4.8), "runner_x": 0.95, "runner_z": 1.9, "color": Color("D2553A"), "stitch": "saddle",
			"drag": 12.0, "push": 3.5, "sink": 0.06, "plane": 5.0, "turn": 1.0, "stand_slip": 0.6, "stand_speed": 0.5, "kick": 0.0,
			"seats": [Vector3(-0.5, 0.55, -1.65), Vector3(0.5, 0.55, -1.65), Vector3(-0.5, 0.55, -0.55), Vector3(0.5, 0.55, -0.55),
					Vector3(-0.5, 0.55, 0.55), Vector3(0.5, 0.55, 0.55), Vector3(-0.5, 0.55, 1.65), Vector3(0.5, 0.55, 1.65)]},
}

# ---- ずり落ちと引きずり（調整する値。意味と、変えるとどうなるかは design/controls-and-physics.md）
const SLIDE_GRIP := 0.15       # 空のソリの雪の摩擦（重さに対する割合）。坂の傾き（tan）がこれより緩い所で止まる。0.15 ≈ 8.5°
const SLIDE_DRAG := 72.0       # 空のソリがずり落ちるときの雪の抵抗 (N per m/s)。大きいほどゆっくり。重さによらないので、
                               # 重いソリほど速くずり落ちる（2026-10-29 に、重さに比べた 1.2 から、中で同じになる 72 N に）
const RIDER_MASS := 45.0       # 乗っている人一人の重さ (kg)。止めるときにだけ効く（登りは速くも遅くもしない）
const STOP_FORCE := 300.0      # つかんでいる人一人が止める力 (N)。押す力と同じ
const DRAG_SPEED := 2.5        # これより速く下っているソリをつかむと、引きずられる (m/s)
const DRAG_STOP_SPEED := 0.8   # 引きずられて、ここまで遅くなったら踏みとどまる（静止摩擦で留まる）
const DRAG_MAX_DIST := 15.0    # 止められないまま、この距離を引きずられると手が離れる (m)
const DRAG_SLIP_SPEED := 8.0   # これより速いと手がもたない（つかんでもすぐ離れる）(m/s)

const BODY_MIN_MASS := 15.0    # 物理の体の重さの下限 (kg)。米袋（重さ 1 kg）でも揺れずに滑るため。止める計算は表の重さを使う
const MID_MASS := 60.0         # 滑り木の抵抗・体重移動・雪かきの力はこの重さで決めた値。重さに比べて同じ効きにする
const PUSH_FADE := Vector2(3.0, 4.0)   # 押されるソリがこの速さ (m/s) を超えると、押す力が弱まって消える（人は走るより速く押せない）

signal slipped(who: Node3D)    # 引きずられて手が離れた

var kind := "mid"              # 置く前に決める（main.gd の --sled=sack|small|mid|large）
## メインカラー（ソリの主なフェルトと、滑りあとの糸の色）。透明（a = 0）なら KINDS の既定。
## 置く前に入れるか、置いたあとは set_main_color で（のちのカスタマイズの画面・通信はここを呼ぶ）。main.gd の --sled-color=
var main_color := Color(0, 0, 0, 0)
var _body: Node3D              # 見た目（glb か仮の箱）
## 滑りあとの縫い目の差し替え（STITCHES の名前）。空なら KINDS の既定。置く前に入れる（main.gd の --stitch=）
var stitch_override := ""
## 布の色（fabrics.gd の名前）。ミシンで縫ったソリに付く。入れるとメインカラー（main_color・set_main_color）になる
var fabric := "":
	set(v):
		fabric = v
		if v == "":
			return
		if is_node_ready():
			set_main_color(Fabrics.color(v))
		else:
			main_color = Fabrics.color(v)
var crafted := false           # ミシンで縫った・広げたソリ（畳んで持てる。craft.gd）
var tag: Variant = 0           # 名札の柄（sled_tags.gd）。持ち主の名札（辞書）か、ロッジの名札（0）。-1 は名札なし。手すりの前の結び目から小さく吊るす
var owner_id := -1             # 持ち主の人の番号（縫った人・米袋の人）。-1 は持ち主なし
var kind_mass := 60.0          # 表の重さ（米袋は 1 kg）。乗っている人の重さと合わせて止める計算に使う
var _k := 1.0                  # 体の重さ / MID_MASS
var SEATS: Array = KINDS.mid.seats
var HALF := Vector2(0.75, 1.4)     # 台の半分の幅と長さ
var ROPE_ANCHOR := Vector3(0, 0.3, -1.45)
var RUNNER_Z := 1.1                # 滑り木の前後の接地点（中心からの距離）
var RUNNER_X := 0.6                # 左右の滑り木の位置
var parked := true             # ふもとに止めてある（最初と R で戻したとき）。誰かが触るまでずり落ちない
var dragged := {}              # 引きずられている人 → 引きずられた距離 (m)
var _pushed_by := {}           # このコマ押した人（引きずりの判定用。押している人は引きずられない）
var _pushed_now := {}
# ---- 乗って滑るときの、乗っている一人ひとりの力（調整する値。乗る人の数だけ足し合わさる）
# 乗って下っているあいだは、乗っている人の重さ（RIDER_MASS）もソリと一緒に動く重さに入る。
# 人の力は「ソリ＋乗る人」の重さで分け合うので、重いソリほど一人の力では動きにくく、そろえると効く
const LEAN_DIG := 30.0             # 一人が体重をかけた側の滑り木が食い込んで増える抵抗 (N per m/s)。逆向きの人とは打ち消し合う
                                   # （2026-10-29 に、乗る人の重さを入れたので 17.5 から合わせ直した。中＋一人の曲がり方は前と同じ）
const SCOOP_FORCE := 210.0         # 一人が乗ったまま前傾して手で雪をかく力 (N)。坂を登る向きには効かない
const BRAKE_DRAG := 24.0           # 一人が後ろに体重をかけたときの制動（両側, N per m/s）
const FWD_LEAN_EASE := 0.6         # 前傾した人の割合 × これだけ、雪をこする抵抗が減る（全員前傾で 0.4 倍）
# ---- 足で漕ぐ（米袋。2026-10-29 代表「スペース連打で滑走中のみ加速」「友達と連打勝負できるように」）
# 一回蹴るごとに前へ KICK_DV だけ速くなるが、速いほど蹴りが効かなくなり、KICK_TOP に近づくと 0 になる。
# 漕がずに滑るだけなら大きいソリより遅いが、速く連打するほど伸び、大きいソリより速くなれる（連打の速さがそのまま速さの差）。
# 下り坂で全部効き、平らな所では KICK_FLAT だけ、登りでは効かない（登りを楽にしない）
const KICK_DV := 1.5               # 一回蹴って速くなる量 (m/s。止まりかけのとき)
const KICK_TOP := 16.0             # 蹴って届く速さの上限 (m/s)。ここに近づくほど蹴りが効かない
const KICK_FLAT := 0.3             # 平らな所での蹴りの効き（下り坂で 1）
const KICK_FULL_SLOPE := 0.15      # この下り（傾きの sin）より急なら、蹴りが全部効く
const KICK_MIN_SPEED := 0.5        # これより遅いと蹴れない（滑っているあいだだけ。滑り出しは W で雪をかく）
signal kicked(who: Node3D)
const CLIMB_LEAN_DIG := 17.5       # 押されて登っているときの体重移動・後傾（前の作りのまま。登りの手ざわりを変えない）
const CLIMB_BRAKE_DRAG := 14.0
const HOLD_FRICTION := 0.45        # 遅いときに働く静止摩擦（重さに対する割合）。丘のどこでも留まり、1人が押せば動き出す

var pushers := 0            # 前のコマで押していた人数（表示用）
var riders: Array[Node3D] = []
var holders := {}           # つかんでいる人 → つかんだ所（ソリの座標）
var rope_holder: Node3D = null
var rope: Node3D            # 引き紐（見た目と、拾える先の位置）
var _push_count := 0
var _steer := 0.0           # 乗っている人の左右の体重移動の合計（このコマ。一人 -1〜1 を足し合わせる。上限なし）
var _n_fwd := 0             # このコマ前傾した人の数
var _n_back := 0            # このコマ後傾した人の数
var steer_now := 0.0        # 前のコマの体重移動の合計（確かめ用・表示用）
var hold_debug := ""

# 足元の影と、滑り木の跡（ステッチ）
const TRAIL_N := 1600         # 同時に残せる歩みの数（滑り木 2 本 × 800 歩 = 約 240 m、丘を 4 回ほど滑った長さ）。あふれたら、いちばん早く消える目から使い回す
const TRAIL_STEP := 0.3       # 縫い目の 1 歩の長さ (m)。1 歩ごとに縫い目の形を 1 つ置く
const TRAIL_ZIG := 0.045      # ジグザグの振れ幅（縫い目の中心から針穴まで, m）
const TRAIL_JITTER := 0.012   # 針穴の位置のばらつき (m)。手で縫ったような揺れ
## 縫い目の種類。per は 1 歩に置く糸の目の数、radius は糸の太さ（半径 m）。重いソリほど太く丈夫に
##   running なみ縫い: 中心線に沿った破線。軽い
##   zigzag  ジグザグ: 左右交互の針穴を渡る（はじめの滑りあと、PR #6）
##   chain   くさり縫い: しずく形の輪が、前の輪の中から次の輪が出るようにつながる
##   saddle  サドルステッチ: 太い糸の斜めの目が 2 列。いちばん丈夫
const STITCHES := {
	"running": {"per": 1, "radius": 0.02},
	"zigzag": {"per": 1, "radius": 0.026},
	"chain": {"per": 2, "radius": 0.021},
	"saddle": {"per": 4, "radius": 0.025},
}
const RUNNING_DASH := 0.62    # なみ縫いの 1 歩のうち、糸が表に出ている割合
const CHAIN_WIDTH := 0.052    # くさり縫いの輪の、ふくらんだ所の半分の幅 (m)
const SADDLE_ROW := 0.08      # サドルステッチの 2 列の、中心からの距離 (m)
const SADDLE_SLANT := Vector2(0.055, 0.095)   # サドルステッチの 1 目の、横と前後の半分の長さ (m)
# ---- 滑りあとが消える（調整する値。意味は design/controls-and-physics.md）
# 古い順に一列で消えるのでなく、縫い目ごとにばらばらの時刻で消えていく。
# 重いソリ（ソリの重さ ＋ 乗っている人）の跡ほど深く、長く残る。消え方は TRAIL_FADE
const TRAIL_LIFE := 50.0              # 重さ TRAIL_LIFE_MASS の跡が消えるまでの時間のまんなか (s)
const TRAIL_LIFE_MASS := 100.0        # その基準の重さ (kg)
const TRAIL_LIFE_POW := 0.6           # 重さが 2 倍で 2^0.6 ≈ 1.5 倍長く残る
const TRAIL_LIFE_RANGE := Vector2(12.0, 300.0)   # 消えるまでの時間のまんなかの下限と上限 (s)
const TRAIL_PATCH := 0.45             # 吹きだまりのまとまりで、残る時間がずれる割合（±）
const TRAIL_PATCH_SIZE := 3.0         # 吹きだまりのまとまりの大きさ (m)
const TRAIL_SCATTER := 0.4            # 縫い目ひとつずつで、残る時間がずれる割合（±）
const TRAIL_BURY := 0.3               # 消えるまでの時間のうち、消えていく（ほつれる・埋もれる）時間の割合
const TRAIL_BURY_MIN := 4.0           # 消えていく時間の下限 (s)
## 消え方。"fray" ほつれる（撚りがゆるみ、繊維がまんなかから切れていく。2026-10-29 代表）、"bury" 雪に埋もれる（白くなって沈む）
const TRAIL_FADE := "fray"
var trail_fade := TRAIL_FADE          # 置く前に変えてよい（main.gd の --trail-fade=）
const TRAIL_SCAN := 48                # 空いた目を探すとき、先へ見る数（多いほど正確、重い）
const TRAIL_CHUNK := 100              # 歩みをこの数ずつの塊に分けて描く（塊の目の数は × per）。画面の外の塊は描かない
const TRAIL_SEE := 45.0               # これより遠い塊は描かない (m)。糸は細いので、その先はほとんど見えない
var _blob: MeshInstance3D
var _stitch: ArrayMesh                        # 1 目の形（塊どうしで共有。色と時計はここに入れる。粗い形は Look.stitch_mesh）
var _trails: Array[MultiMeshInstance3D] = []  # 目の塊
var _trail_i := 0
var _trail_now := 0.0                         # 滑りあとの時計 (s)。確かめ用に進めてよい
var _trail_end := PackedFloat32Array()        # 目ごとの、消えきる時刻
var _chunk_end := PackedFloat32Array()        # 塊ごとの、目がすべて消えきる時刻（過ぎたら塊を描かない）
var _trail_used := 0                          # 使ったことのある目の数
var _trail_noise := FastNoiseLite.new()
var _trail_dist := 0.0
var _trail_last := Vector3.INF
var _trail_flip := false
var _trail_holes := [Vector3.INF, Vector3.INF]   # 左右それぞれ、前の歩みの縫い目の中心
var _trail_jit := [Vector3.ZERO, Vector3.ZERO]   # 左右それぞれ、前の針穴のばらつき
var _st: Dictionary = STITCHES.zigzag            # いまの縫い目（STITCHES の 1 つ）
var _stitch_name := "zigzag"
var _trail_n := TRAIL_N                          # 目の数（TRAIL_N × per）
var _trail_chunk := TRAIL_CHUNK                  # 塊の目の数
var _trail_rng := RandomNumberGenerator.new()
var snow_lift := Callable()   # (x, z) → 見た目の雪面が当たり判定からずれる量。main が渡す


func _ready() -> void:
	add_to_group("sleds")
	if not KINDS.has(kind):
		kind = "mid"
	var k: Dictionary = KINDS[kind]
	ROPE_LEN = k.get("rope_len", 3.0)
	kind_mass = k.mass
	mass = maxf(k.mass, BODY_MIN_MASS)
	_k = mass / MID_MASS
	SEATS = k.seats
	HALF = Vector2(k.box.x, k.box.z) * 0.5
	ROPE_ANCHOR = Vector3(0, 0.3, -HALF.y - 0.05)
	RUNNER_X = k.runner_x
	RUNNER_Z = k.runner_z
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)
	angular_damp = 6.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.04
	physics_material_override = pm

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = k.box
	col.shape = box
	col.position.y = k.box.y * 0.49
	add_child(col)

	_make_body()
	# 引き紐: 手すりの両端を結ぶたわんだ紐と、そのまんなかから出る引っ張り紐（sled_rope.gd）
	rope = preload("res://sled_rope.gd").new()
	rope.sled = self
	add_child(rope)
	retag(tag)

	_make_shadow_and_trail()

## 見た目: フェルトの座布団を曲げ木の滑り木に載せたソリ（props/build_sled.py の glb）。寸法はこの物理に合わせてある。
## 焼いてある主なフェルトの色（KINDS の color）を、メインカラーに差し替える（props.gd の recolor）。
## glb がまだない大きさは、当たりの箱と同じ大きさの仮の箱
func _make_body() -> void:
	var k: Dictionary = KINDS[kind]
	var glb := "res://props/sled_%s.glb" % kind
	if ResourceLoader.exists(glb):
		_body = Props.make(glb)
		if not color().is_equal_approx(k.color):
			Props.recolor(_body, k.color, color(), k.get("whole", false))
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = k.box
		mi.mesh = bm
		mi.position.y = k.box.y * 0.5
		var m := StandardMaterial3D.new()
		m.albedo_color = color()
		mi.material_override = m
		_body = mi
	add_child(_body)


## いまの滑りあとの縫い目の名前（STITCHES）
func stitch_kind() -> String:
	if STITCHES.has(stitch_override):
		return stitch_override
	return KINDS.get(kind, KINDS.mid).stitch


## いまのメインカラー
func color() -> Color:
	return main_color if main_color.a > 0.0 else KINDS.get(kind, KINDS.mid).color


## メインカラーを変える（置いたあとでも）。ソリの見た目と、滑りあとの糸（もう残っている跡も）が同じ色になる
func set_main_color(c: Color) -> void:
	main_color = c
	if _body == null:
		return
	if _body is MeshInstance3D and (_body as MeshInstance3D).material_override:   # 仮の箱
		((_body as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = color()
	else:
		Props.recolor(_body, KINDS[kind].color, color(), KINDS[kind].get("whole", false))
	if _stitch:
		Look.stitch_set_color(_stitch, color())


## dir は押す向き（水平）、at は手が触れた所（世界座標）、who は押した人（引きずられている人は押せない）
func push(dir: Vector3, at: Vector3, who: Node3D = null) -> void:
	dir.y = 0
	if dir.length() < 0.01 or dragged.has(who):
		return
	parked = false
	if who:
		_pushed_now[who] = true
	var f: Vector3 = dir.normalized() * PUSH_FORCE * min(1.0, dir.length())
	f *= 1.0 - smoothstep(PUSH_FADE.x, PUSH_FADE.y, linear_velocity.dot(dir.normalized()))
	# 力は手が触れている所にそのままかける。どう動くかは滑り木と重力が決める
	var p := to_local(at)
	p.x = clamp(p.x, -HALF.x, HALF.x)
	p.z = clamp(p.z, -HALF.y, HALF.y)
	p.y = 0.2
	apply_force(f, global_basis * p)
	_push_count += 1


## 立っている所（世界座標）から、ソリの縁のいちばん近いつかみ所と、押す向きを返す
## [立つ位置（ソリの座標）, 押す向き（ソリの座標）]
func grip_point_near(world_pos: Vector3) -> Array:
	var p := to_local(world_pos)
	var ex := HALF.x + STAND
	var ez := HALF.y + STAND
	if abs(p.x) / ex > abs(p.z) / ez:
		var sx := signf(p.x) if p.x != 0.0 else 1.0
		return [Vector3(sx * ex, 0, clamp(p.z, -HALF.y, HALF.y)), Vector3(-sx, 0, 0)]
	var sz := signf(p.z) if p.z != 0.0 else 1.0
	return [Vector3(clamp(p.x, -HALF.x, HALF.x), 0, sz * ez), Vector3(0, 0, -sz)]


func take_handle(who: Node3D, h: Vector3) -> bool:
	for other in holders:
		if other != who and holders[other].distance_to(h) < 0.7:
			return false
	holders[who] = h
	parked = false
	# 速く下っているソリをつかむと、引きずられる。速すぎると手がもたない
	if _downhill_fast(DRAG_SPEED):
		dragged[who] = 0.0
	return true


func release_handle(who: Node3D) -> void:
	holders.erase(who)
	dragged.erase(who)


## 引きずられているか（つかんでいる人の見た目と音が読む）
func is_dragged(who: Node3D) -> bool:
	return dragged.has(who)


## 乗っている人も入れた重さ (kg)。米袋に誰も乗っていなければ 1 kg
func load_mass() -> float:
	return maxf(kind_mass + riders.size() * RIDER_MASS, 1.0)


## ソリがこれより速く下っているか（押されて登っているときは数えない）
func _downhill_fast(v: float) -> bool:
	return linear_velocity.length() > v and (_pushed_by.is_empty() or linear_velocity.y < -0.1)


func take_rope(who: Node3D) -> bool:
	if rope_holder != null and rope_holder != who:
		return false
	rope_holder = who
	parked = false
	return true


func release_rope(who: Node3D) -> void:
	if rope_holder == who:
		rope_holder = null


## 紐を持つ人の手の位置から、張っていれば引く。張った分の長さを返す（たるみなら負）
func pull_rope(hand: Vector3) -> float:
	var anchor := to_global(ROPE_ANCHOR)
	var d := hand - anchor
	var over := d.length() - ROPE_LEN
	if over > 0.0:
		var dir := d
		dir.y = 0
		apply_force(dir.normalized() * min(over * ROPE_K, 600.0), anchor - global_position)
		_push_count += 1
	return over




func mount(who: Node3D) -> Vector3:
	if riders.size() >= SEATS.size() or who in riders:
		return Vector3.INF
	riders.append(who)
	parked = false
	return SEATS[riders.size() - 1]


func dismount(who: Node3D) -> void:
	riders.erase(who)


## 乗っている人の体重移動。乗っている一人ひとりが毎コマ呼ぶ。steer は -1（左）〜1（右）、forward は前傾、back は後傾。
## 力を直接かけるのではなく、滑り木の食い込み（抵抗）が変わることで曲がる・止まる。
## 一人ひとりの力は足し合わさる: 全員が同じ向きなら重なって大きく曲がり、逆向きの人がいると打ち消し合う
func lean(steer: float, forward: bool, back: bool = false) -> void:
	_steer += clampf(steer, -1.0, 1.0)
	_n_fwd += 1 if forward else 0
	_n_back += 1 if back else 0


## 乗っている人が足で雪を蹴る（Space を押すたび）。蹴れたら true
func kick(who: Node3D) -> bool:
	var K: Dictionary = KINDS[kind]
	if K.get("kick", 0.0) <= 0.0 or not riders.has(who) or linear_velocity.length() < KICK_MIN_SPEED:
		return false
	var n := _ground_normal()
	var f := -global_basis.z
	f = (f - n * f.dot(n)).normalized()   # 地面に沿った前
	var slope := 0.0                        # 前の向きの下り（sin）。登りなら負
	slope = -f.y
	if slope < -0.02:
		return false                        # 登りでは蹴っても進まない
	var eff := lerpf(KICK_FLAT, 1.0, clampf(slope / KICK_FULL_SLOPE, 0.0, 1.0))
	var v_along := maxf(0.0, linear_velocity.dot(f))
	var dv: float = KICK_DV * K.kick * eff * maxf(0.0, 1.0 - v_along / KICK_TOP)
	if dv <= 0.0:
		return false
	apply_central_impulse(f * dv * mass)    # 体の速さを dv だけ（乗っている人も一緒に動くので、体の重さで足りる）
	kicked.emit(who)
	return true


## 広げる動きのあいだ（frames コマ）、止めて見た目を隠しておく（craft.gd が折り紙の形を見せる）
func hold_still(frames: int) -> void:
	freeze = true
	visible = false
	await get_tree().create_timer(frames / 12.0).timeout
	if is_instance_valid(self):
		freeze = false
		visible = true
		parked = true


## 名札を付け直す（持ち主が自分の名札のデザインを変えたとき。craft.gd）
func retag(d) -> void:
	tag = d
	var old := get_node_or_null("Tag")
	if old:
		old.name = "OldTag"
		old.queue_free()
	if rope == null or not preload("res://sled_tags.gd").has_tag(d):
		return
	var tg: Node3D = preload("res://sled_tags.gd").hang(self, rope._ties[1] + Vector3(0.02, -0.02, 0), d, clampf(HALF.x * 0.32, 0.16, 0.26))
	tg.rotation.y = PI / 2   # 紙の面を外（横）へ向ける


func reset_to(pos: Vector3) -> void:
	for r in riders.duplicate():
		if r.has_method("get_off"):
			r.get_off()
	for who in holders.keys():
		if who.has_method("let_go"):
			who.let_go()
	if rope_holder and rope_holder.has_method("let_go"):
		rope_holder.let_go()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(), pos + Vector3.UP * place_lift())
	parked = true


## 坂に水平に置くとき、地面からこれだけ余分に浮かせる (m)。呼ぶ側は地面の 0.3 m ほど上に置くので、その分は引く。
## 長いソリ（大は 4.8 m）を坂に水平に置くと、下の端が雪に埋まり、地面を突き抜けて落ちることがあるため（丘のいちばん急な傾き 0.44 で足りる高さ）
func place_lift() -> float:
	var k: Dictionary = KINDS.get(kind, KINDS.mid)
	return maxf(0.0, k.box.z * 0.5 * 0.45 - 0.3)


## 足元の影（やわらかい楕円）と、滑り木の跡のステッチ（毛糸の雪に残る針目）
func _make_shadow_and_trail() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var dx := (x - 63.5) / 63.5
			var dy := (y - 63.5) / 63.5
			var r := sqrt(dx * dx + dy * dy)
			var a: float = (1.0 - smoothstep(0.3, 1.0, r)) * 0.42
			img.set_pixel(x, y, Color(0.20, 0.26, 0.46, a))
	var tex := ImageTexture.create_from_image(img)
	_blob = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 3.4)
	q.orientation = PlaneMesh.FACE_Y
	_blob.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.render_priority = -1
	_blob.material_override = m
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.top_level = true
	add_child(_blob)

	_stitch_name = stitch_kind()
	_st = STITCHES[_stitch_name]
	_trail_n = TRAIL_N * int(_st.per)
	_trail_chunk = TRAIL_CHUNK * int(_st.per)
	_stitch = Look.stitch_mesh(color())   # 糸はソリのメインカラー
	Look.stitch_set_shape(_stitch, _st.radius, CHAIN_WIDTH)
	Look.stitch_set_style(_stitch, 1 if trail_fade == "fray" else 0)
	for c in ceili(float(_trail_n) / _trail_chunk):
		var mi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _stitch
		mm.instance_count = mini(_trail_chunk, _trail_n - c * _trail_chunk)
		mm.visible_instance_count = 0
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = TRAIL_SEE
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_trails.append(mi)
	_trail_end.resize(_trail_n)
	_trail_end.fill(-1.0)
	_chunk_end.resize(_trails.size())
	_chunk_end.fill(-1.0)
	_trail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_trail_noise.frequency = 1.0 / TRAIL_PATCH_SIZE
	_trail_noise.seed = randi()


func _ground_hit(from: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


## 滑りあとの目が、消えるまでの時間のまんなか (s)。重いソリ（乗っている人も入れる）ほど長い
func trail_life() -> float:
	var life := TRAIL_LIFE * pow(load_mass() / TRAIL_LIFE_MASS, TRAIL_LIFE_POW)
	return clampf(life, TRAIL_LIFE_RANGE.x, TRAIL_LIFE_RANGE.y)


## 次の目を置く所: 先の TRAIL_SCAN 個のうち、消えきった目があればそれ、なければいちばん早く消える目
func _trail_slot() -> int:
	var best := _trail_i
	var best_end := INF
	for j in mini(TRAIL_SCAN, _trail_n):
		var i := (_trail_i + j) % _trail_n
		if _trail_end[i] <= _trail_now:
			best = i
			break
		if _trail_end[i] < best_end:
			best_end = _trail_end[i]
			best = i
	_trail_i = (best + 1) % _trail_n
	_trail_used = maxi(_trail_used, best + 1)
	return best


func _update_shadow_and_trail(dt: float) -> void:
	if _blob == null:
		return
	_trail_now += dt
	Look.stitch_set_time(_stitch, _trail_now)
	for c in _trails.size():
		if _trails[c].visible and _chunk_end[c] <= _trail_now:
			_trails[c].visible = false
	var hit := _ground_hit(global_position + Vector3.UP * 0.5)
	if hit:
		var n: Vector3 = hit.normal
		var fwd: Vector3 = -global_basis.z
		fwd = (fwd - n * fwd.dot(n)).normalized()
		_blob.global_transform = Transform3D(Basis(n.cross(-fwd).normalized(), n, -fwd), hit.position + n * 0.03)
	# ステッチ: 動いている間、1 歩（TRAIL_STEP）ごとに左右の滑り木の後ろ端で雪面を探し、
	# 前の歩みからそこまでを、ソリの縫い目（なみ縫い・くさり縫い・サドルステッチ…）で縫う
	var v := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if v.length() < 0.25:
		_trail_last = Vector3.INF
		_trail_holes = [Vector3.INF, Vector3.INF]
		return
	if _trail_last == Vector3.INF:
		_trail_last = global_position
	_trail_dist += global_position.distance_to(_trail_last)
	_trail_last = global_position
	var dir := v.normalized()
	while _trail_dist >= TRAIL_STEP:
		_trail_dist -= TRAIL_STEP
		_trail_flip = not _trail_flip
		for k in 2:
			var sx := -RUNNER_X if k == 0 else RUNNER_X
			var h := _ground_hit(to_global(Vector3(sx, 0.3, RUNNER_Z)) + Vector3.UP * 0.5)
			if not h:
				_trail_holes[k] = Vector3.INF
				continue
			var nn: Vector3 = h.normal
			var d := (dir - nn * dir.dot(nn)).normalized()
			var c: Vector3 = h.position
			if snow_lift.is_valid():
				c.y += snow_lift.call(c.x, c.z)
			var jit: Vector3 = d.cross(nn) * _trail_rng.randf_range(-TRAIL_JITTER, TRAIL_JITTER) + d * _trail_rng.randf_range(-TRAIL_JITTER, TRAIL_JITTER)
			var prev: Vector3 = _trail_holes[k]
			var prev_jit: Vector3 = _trail_jit[k]
			_trail_holes[k] = c
			_trail_jit[k] = jit
			if prev == Vector3.INF:
				continue
			var len := prev.distance_to(c)
			if len < 0.1 or len > 0.6:
				continue
			_sew(prev, c, prev_jit, jit, nn)


## 前の歩み p0 から p1 までを、いまの縫い目で縫う。j0・j1 は針穴のばらつき、nn は雪面の上
func _sew(p0: Vector3, p1: Vector3, j0: Vector3, j1: Vector3, nn: Vector3) -> void:
	var f := (p1 - p0).normalized()        # 進む向き（雪面に沿う）
	var side := f.cross(nn).normalized()
	match _stitch_name:
		"running":   # 中心線に沿って、表に出る目と、裏に潜る隙間をくり返す
			_emit(p0 + j0, p0.lerp(p1, RUNNING_DASH) + j1 * 0.5, nn, 0)
		"chain":     # しずく形の輪: 根元から左右にふくらむ 2 本の弧。先は次の輪の根元の少し先
			var tip := p1 + f * 0.04 + j1 * 0.5
			_emit(p0 + j0 * 0.5, tip, nn, 1)
			_emit(p0 + j0 * 0.5, tip, nn, 2)
		"saddle":    # 斜めの短い目を 2 列。列どうしは半目ずらす
			for row in 2:
				var x0 := SADDLE_ROW * (1.0 if row == 0 else -1.0)
				for sub in 2:
					var cm := p0.lerp(p1, 0.25 + 0.5 * sub + (0.25 if row == 1 else 0.0) - 0.125)
					var a := cm + side * (x0 - SADDLE_SLANT.x) - f * SADDLE_SLANT.y
					var b := cm + side * (x0 + SADDLE_SLANT.x) + f * SADDLE_SLANT.y
					_emit(a + j0 * 0.3, b + j1 * 0.3, nn, 0)
		_:           # zigzag: 針穴を中心から左右交互にずらす
			var s := TRAIL_ZIG if _trail_flip else -TRAIL_ZIG
			_emit(p0 - side * s + j0, p1 + side * s + j1, nn, 0)


## 糸の目を 1 つ置く。a（入る針穴）から b（出る針穴）へ。bow は 0 でまっすぐ、1・2 で左・右にふくらむ弧（くさり縫いの輪）
func _emit(a: Vector3, b: Vector3, nn: Vector3, bow: int) -> void:
	var span := b - a
	var len := span.length()
	if len < 0.04:
		return
	# 入る針穴（原点）から -z の向きへ len だけ伸びる目
	var z := -span / len
	var y := (nn - z * nn.dot(z)).normalized()
	var bs := Basis(y.cross(z), y, z)
	# 消えるまでの時間: 重さで決まるまんなかを、吹きだまりのまとまりと、目ひとつずつでずらす
	var f := 1.0 + TRAIL_PATCH * clampf(_trail_noise.get_noise_2d(a.x, a.z) * 1.6, -1.0, 1.0) \
			+ TRAIL_SCATTER * _trail_rng.randf_range(-1.0, 1.0)
	var life := trail_life() * maxf(f, 0.15)
	var fade := maxf(life * TRAIL_BURY, TRAIL_BURY_MIN)
	var slot := _trail_slot()
	_trail_end[slot] = _trail_now + life
	var ci := slot / _trail_chunk
	_chunk_end[ci] = maxf(_chunk_end[ci], _trail_now + life)
	var chunk := _trails[ci]
	var mm := chunk.multimesh
	var j := slot % _trail_chunk
	mm.visible_instance_count = maxi(mm.visible_instance_count, j + 1)
	mm.set_instance_transform(j, Transform3D(bs, a + nn * 0.012))
	# y は 位相（0〜1）＋ 弧の向き（整数）
	mm.set_instance_custom_data(j, Color(len, _trail_rng.randf() * 0.999 + bow, fade, _trail_now + life - fade))
	chunk.visible = true


func _ground_normal() -> Vector3:
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.normal if hit else Vector3.UP


## 乗って下っているときの力。ソリと乗っている人は一緒に動くので、重力は同じ加速で、ほかの力（雪の抵抗・沈み・体重移動）は
## 「体の重さ / ソリと乗る人の重さ」の割合でかける（物理の体はソリの重さだけなので、乗る人の重さぶん効きを弱める）。
## 雪をこする抵抗（drag）は重さによらないので、重いほど抵抗に負けにくく、最高速度が速い。滑り木のソリは出足で雪に沈む（sink）。
## 曲がる力は一人ひとりの体重移動の合計。ソリが長く重いほど回りにくい（回りにくさは当たりの箱から物理で出る）
func _ride_forces(dt: float, fwd: Vector3) -> void:
	var K: Dictionary = KINDS[kind]
	var share := mass / load_mass()
	var n := _ground_normal()
	var v_t := linear_velocity - n * linear_velocity.dot(n)
	var vs := v_t.length()
	if vs > 0.01:
		var ease := 1.0 - FWD_LEAN_EASE * float(mini(_n_fwd, riders.size())) / riders.size()
		var sink: float = K.sink * load_mass() * 9.8 * absf(n.y) * (1.0 - smoothstep(0.0, K.plane, vs))
		var resist: float = (K.drag * vs + K.push * vs * vs) * ease + sink
		apply_central_force(-v_t / vs * minf(resist * share, vs * mass / dt))
	for x in [-RUNNER_X, RUNNER_X]:
		var r := global_basis * Vector3(x, 0, 0)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var v_long := v_point.dot(fwd)
		var c := BRAKE_DRAG * _n_back
		if _steer * signf(x) > 0.0:
			c += LEAN_DIG * K.turn * absf(_steer)
		apply_force(-fwd * v_long * c * share, r)


## 止める力を出している人の数: つかんでいて、このコマ押していない人（押されて登っているときは数えない）
func _brakers() -> int:
	if pushers > 0 and linear_velocity.y > -0.1:
		return 0
	var n := 0
	for who in holders:
		if not _pushed_by.has(who):
			n += 1
	return n


## 引きずられている人の出入り。速く下っている間につかんでいる人は引きずられ、遅くなれば踏みとどまる。
## 止められないまま DRAG_MAX_DIST 引きずられるか、DRAG_SLIP_SPEED より速くなると手が離れる
func _update_drag(dt: float) -> void:
	var v := linear_velocity.length()
	for who in holders.keys():
		if dragged.has(who):
			if v < DRAG_STOP_SPEED:
				dragged.erase(who)
				continue
			dragged[who] += v * dt
			if dragged[who] > DRAG_MAX_DIST or v > DRAG_SLIP_SPEED:
				release_handle(who)
				if who.has_method("let_go"):
					who.let_go()
				slipped.emit(who)
		elif not _pushed_by.has(who) and _downhill_fast(DRAG_SPEED):
			dragged[who] = 0.0
	_update_drag_puffs()
	_update_heel_stitches()


var _puffs := {}   # 引きずられている人 → 足もとの雪の粉

# 引きずられ跡: かかと 2 本の線に、ぐし縫いのギャザー（Look.gather_stitch_mesh）。短いなみ縫いの目と、まわりに寄ったひだ
const DRAG_TRAIL_N := 400       # 残す目の数（全員ぶん）
const DRAG_STITCH := 0.12       # 針穴の間隔 (m)。なみ縫いなので、目と目のあいだも同じだけ空く
const HEEL_X := 0.11            # かかとの、体のまんなかからの横の距離 (m)
var _drag_trail: MultiMeshInstance3D
var _drag_i := 0
var _heels := {}                # 引きずられている人 → {last, dist, on, holes: [左, 右]}


## かかとが雪をすべった所に、ぐし縫いの目を置く。速いほど雪が強く寄る（ひだが濃い）
func _update_heel_stitches() -> void:
	for who in _heels.keys():
		if not dragged.has(who) or not is_instance_valid(who):
			_heels.erase(who)
	if dragged.is_empty():
		return
	if _drag_trail == null:
		_drag_trail = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Look.gather_stitch_mesh(Color(0.70, 0.34, 0.30))   # かかとの赤茶の毛糸。滑りあとの青と見分ける
		mm.instance_count = DRAG_TRAIL_N
		for i in DRAG_TRAIL_N:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -100, 0)))
		_drag_trail.multimesh = mm
		_drag_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drag_trail.top_level = true
		add_child(_drag_trail)
	var v := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if v.length() < 0.2:
		return
	var dir := v.normalized()
	var side := dir.cross(Vector3.UP)
	for who in dragged:
		if not is_instance_valid(who):
			continue
		var feet: Vector3 = (who as Node3D).global_position
		var h: Dictionary = _heels.get(who, {})
		if h.is_empty():
			h = {"last": feet, "dist": 0.0, "on": true, "holes": [Vector3.INF, Vector3.INF]}
			_heels[who] = h
		h.dist += feet.distance_to(h.last)
		h.last = feet
		while h.dist >= DRAG_STITCH:
			h.dist -= DRAG_STITCH
			for k in 2:
				var at: Vector3 = feet + side * (HEEL_X if k == 0 else -HEEL_X) + side * _trail_rng.randf_range(-0.025, 0.025)
				var hit := _ground_hit(at + Vector3.UP * 0.6)
				if not hit:
					h.holes[k] = Vector3.INF
					continue
				var nn: Vector3 = hit.normal
				var hole: Vector3 = hit.position
				if snow_lift.is_valid():
					hole.y += snow_lift.call(hole.x, hole.z)
				var prev: Vector3 = h.holes[k]
				h.holes[k] = hole
				if prev == Vector3.INF or not h.on:
					continue
				var span := hole - prev
				var len := span.length()
				if len < 0.04 or len > 0.4:
					continue
				var z := -span / len
				var y := (nn - z * nn.dot(z)).normalized()
				_drag_trail.multimesh.set_instance_transform(_drag_i, Transform3D(Basis(y.cross(z), y, z), prev + nn * 0.01))
				_drag_trail.multimesh.set_instance_custom_data(_drag_i, Color(len, _trail_rng.randf(), _trail_rng.randf_range(0.9, 1.06),
						clampf(v.length() / 6.0, 0.45, 1.0)))
				_drag_i = (_drag_i + 1) % DRAG_TRAIL_N
			h.on = not h.on   # なみ縫い: 目、あき、目、…


## 引きずられている人の足もとから、綿の雪の粉が舞う（足が雪をすべる）。速いほど多い
func _update_drag_puffs() -> void:
	for who in _puffs.keys():
		if not is_instance_valid(who) or not dragged.has(who):
			var old: CPUParticles3D = _puffs[who]
			old.emitting = false
			_puffs.erase(who)
			old.get_tree().create_timer(1.2).timeout.connect(old.queue_free)
	var v := Vector3(linear_velocity.x, 0, linear_velocity.z)
	for who in dragged:
		if not is_instance_valid(who):
			continue
		var puff: CPUParticles3D = _puffs.get(who)
		if puff == null:
			puff = CPUParticles3D.new()
			puff.amount = 56
			puff.lifetime = 0.9
			puff.local_coords = false
			puff.direction = Vector3(0, 1, 0)
			puff.spread = 55.0
			puff.initial_velocity_min = 1.4
			puff.initial_velocity_max = 2.8
			puff.gravity = Vector3(0, -2.0, 0)
			puff.damping_min = 1.5
			puff.damping_max = 2.5
			puff.angle_max = 360.0
			puff.scale_amount_min = 0.9
			puff.scale_amount_max = 1.8
			puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			puff.emission_box_extents = Vector3(0.35, 0.02, 0.15)
			var ramp := Gradient.new()
			ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
			ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
			puff.color_ramp = ramp
			puff.mesh = Snowball._cotton_quad(0.22)
			get_parent().add_child(puff)
			puff.emitting = false
			puff.restart()
			_puffs[who] = puff
		# 足は前へ踏ん張り、ソリに引かれて雪をすべる。かかとが雪を押しのけ、粉は足のまわりから上へ舞って、後ろへ流れる
		# （ソリの下に隠れないよう、足の先までにする）
		var ahead := v.normalized() * 0.15 if v.length() > 0.1 else Vector3.ZERO
		puff.global_position = (who as Node3D).global_position + ahead + Vector3.UP * 0.05
		puff.direction = (Vector3.UP * 1.5 - v.normalized() * 0.4).normalized() if v.length() > 0.1 else Vector3.UP
		puff.speed_scale = clampf(0.6 + v.length() * 0.15, 0.6, 1.6)
		puff.emitting = true


func _physics_process(dt: float) -> void:
	_update_shadow_and_trail(dt)
	pushers = _push_count
	_push_count = 0
	_pushed_by = _pushed_now
	_pushed_now = {}
	var riding := riders.size() > 0
	# 押されて坂を登っている間は、乗っている人がいても登りの雪の抵抗。乗るだけで登りが速くならないように
	var pushed_up := pushers > 0 and linear_velocity.y > 0.05
	# 乗って下っている: 雪をこする抵抗・沈み・体重移動は、ソリと乗る人をまとめた重さで動かす（_ride_forces）
	var descent := riding and not pushed_up
	# 誰も押していない空のソリは、ずり落ちる雪の抵抗（つかまれていても同じ。止める力はつかんだ人が出す）
	if descent:
		linear_damp = 0.0
	elif pushers > 0 or parked:
		linear_damp = CLIMB_DAMP
	else:
		linear_damp = 0.0   # 空のソリのずり落ちる抵抗は SLIDE_DRAG（下の「止める力」と一緒にかける）
	_update_drag(dt)
	var side := global_basis.x
	var fwd := -global_basis.z
	# 滑り木: 前後にはよく滑り、横には滑らない。前後 2 点で横滑りを止めるので、
	# 縁に偏った力をかけると、横にずれるのでなく向きが変わる
	# 止まっているときは横滑りの抵抗を弱め、人が押してソリの向きを変えられるようにする。
	# どれだけ弱めるかは大きさごと（小さいほどその場で回しやすく、横にずらしやすい。大は滑り木が雪に食い込む）
	var K: Dictionary = KINDS[kind]
	var slip_k: float = SLIP_RESIST * (K.stand_slip if linear_velocity.length() < K.stand_speed else 1.0)
	for z in [-RUNNER_Z, RUNNER_Z]:
		var r := global_basis * Vector3(0, 0, z)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var slip := side * v_point.dot(side)
		apply_force(-slip * mass * slip_k * 0.5, r)
	# 左右の滑り木の前後方向の抵抗。体重をかけた側が雪に食い込んで抵抗が増え、曲がる。
	# 後ろに体重をかけると両側が食い込んで止まる
	if descent:
		_ride_forces(dt, fwd)
	else:
		# 押して登っているとき（乗っている人がいても）は前の作りのまま。乗る人で登りが速くも遅くもならない
		var steer: float = clamp(_steer, -1.0, 1.0)
		for x in [-RUNNER_X, RUNNER_X]:
			var r := global_basis * Vector3(x, 0, 0)
			var v_point := linear_velocity + angular_velocity.cross(r)
			var v_long := v_point.dot(fwd)
			var c := RUNNER_DRAG
			if riding:
				if steer * signf(x) > 0.0:
					c += CLIMB_LEAN_DIG * abs(steer)
				if _n_back > 0:
					c += CLIMB_BRAKE_DRAG
			apply_force(-fwd * v_long * c * _k, r)
	# 遅いソリは静止摩擦で坂に留まる。押せばその分だけ動く。
	# 乗っている人がいても押されていれば効くので、乗る＋一人が押すは、一人で押すのと同じ速さで登る。
	# 押されていなければ、留める力は「つかんでいる人の止める力」と「空のソリの雪の摩擦」まで。
	# 誰も触れていない空のソリは雪の摩擦だけなので、急な所ではずり落ち、緩い所（ふもと）で止まる
	var speed := linear_velocity.length()
	var n := _ground_normal()
	var brakers := _brakers()
	# 空のソリの雪の摩擦は、押されていないときだけ（押して登るときの雪の抵抗は CLIMB_DAMP に入っている）
	var snow: float = 0.0 if riding or pushers > 0 else SLIDE_GRIP * mass * 9.8 * abs(n.y)
	if speed < DRAG_STOP_SPEED and (pushers > 0 or parked or brakers > 0 or not riding):
		var g := Vector3(0, -9.8, 0)
		var g_t := g - n * g.dot(n)
		var hold := -g_t * mass
		var cap: float = HOLD_FRICTION * mass * 9.8 * abs(n.y)
		if pushers == 0 and not parked:
			cap = minf(cap, brakers * STOP_FORCE * mass / load_mass() + snow)
		if hold.length() > cap:
			hold = hold.normalized() * cap
		apply_central_force(hold)
		if pushers == 0 and hold.length() < cap - 1.0:
			linear_velocity *= 0.9
		hold_debug = "n.y=%.2f 力=%.0f/%.0f" % [n.y, hold.length(), cap]
	else:
		# 動いている: つかんでいる人の止める力と空のソリの雪の摩擦が、動きと逆向きにかかる。
		# 乗っている人の重さは、止める力を分け合う重さに入れる（ソリと乗っている人をまとめて止める）
		var v_t := linear_velocity - n * linear_velocity.dot(n)
		var stop := brakers * STOP_FORCE * mass / load_mass() + snow
		if not riding and pushers == 0 and not parked:
			stop += SLIDE_DRAG * v_t.length()
		if v_t.length() > 0.01 and stop > 0.0:
			apply_central_force(-v_t.normalized() * minf(stop, v_t.length() * mass / dt))
		hold_debug = "なし(速さ%.2f 押%d/%d 乗%d 止%d)" % [speed, _push_count, pushers, riders.size(), brakers]
	# 頂上などで、乗ったまま前傾すると手で雪をかいて動き出す。
	# 雪をかく力は坂を登る向きには効かない（平らな所と下りでだけ進む）。乗って W で登ると、降りて押すより速くなるため
	if riding and _n_fwd > 0 and speed < 1.5:
		var f := (fwd - n * fwd.dot(n)).normalized()            # 地面に沿った前
		var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)      # 地面に沿った下り
		if down.length() > 0.01:
			down = down.normalized()
			f -= down * minf(0.0, f.dot(down))                   # 上りの成分を消す
		# 前傾した人の数だけ雪をかく。力はソリと乗る人をまとめた重さで分け合う（重いソリは出足が重い）
		apply_central_force(f * SCOOP_FORCE * _n_fwd * mass / load_mass())
	steer_now = _steer
	_steer = 0.0
	_n_fwd = 0
	_n_back = 0
	# 起き上がり: 大きく傾いたら少しずつ戻す
	var up := global_basis.y
	if up.y < 0.5:
		apply_torque(up.cross(Vector3.UP) * 400.0 * _k)
