extends Node3D

const Look := preload("res://look.gd")
const FpHands := preload("res://fp_hands.gd")
const Palm := preload("res://palm.gd")
const Lantern := preload("res://lantern.gd")
const Outfit := preload("res://outfit.gd")
## 人形（person/build_dolls.py と person/ideas/characters/roughs.py で作り、骨を入れて焼いた glb）を骨で動かす。
## 7 体: kasa 笠と千代紙の人形 / origami 多面体の折り紙の人 / news 新聞紙と麻布の人形 /
## robo 紙のロボット / musha 折り紙の武者 / ningyo 絹の人形 / golem 継ぎはぎの巨人。骨の名前は 7 体で同じ。
## kind は作る前に入れる。作ったあとに替えるときは、持ち主が人形を作り直す（player.gd の set_doll）。
## 居場所（位置と向き）は毎フレームなめらか。姿勢（骨の向き）は 12 コマ／秒で刻み、コマの間は止める。
## 全員が同じ時計（物理のコマ数）でコマを変え、そのたびに骨をわずかに揺らす（クレイアニメの揺れ）。
## ソリや紐をつかむ手は、つかんだ物に対しての姿勢をコマで決め、毎フレーム腕を伸ばし直す（ソリが動いても手が離れない）。
## 見た目だけ。持ち主（player.gd・bot.gd）が毎フレーム act などを入れる。通信には乗せない。
## 身ぶり（emotes.gd の出来事）は play() で受け、出来事のコマから数えたコマ数で姿勢を決める（全員の画面で同じコマに同じ形）。

const FPS := 12
const CADENCE := 2.0          # 歩く周期の上限（1 秒に何周）
const BOIL := 0.018           # コマごとの骨の揺れ（rad）
## 選べる人形の並び（衣装掛けの札の順）
const KINDS := ["kasa", "origami", "news", "robo", "musha", "ningyo", "golem"]
## glb は使う人形のぶんだけ読む（7 体を全部先に読むと起動が重い）
const SCENES := {
	"kasa": "res://person/kasa.glb", "origami": "res://person/origami.glb", "news": "res://person/news.glb",
	"robo": "res://person/robo.glb", "musha": "res://person/musha.glb", "ningyo": "res://person/ningyo.glb", "golem": "res://person/golem.glb",
}
## ゲームでの大きさ。news がいちばん小さく、目の高さが origami のお尻あたり。golem がいちばん大きい
const SCALE := {"kasa": 1.15, "origami": 1.1, "news": 1.05, "robo": 1.15, "musha": 1.1, "ningyo": 1.1, "golem": 1.35}
## 足もとの影の半径（人形の大きさのまま）
const FOOT_SHADOW := {"kasa": 0.46, "origami": 0.44, "news": 0.38, "robo": 0.36, "musha": 0.32, "ningyo": 0.36, "golem": 0.62}
## 目の所（glb の座標、人形の大きさのまま。立ったとき）。乗っているときの一人称のカメラを合わせる
const EYE := {"kasa": Vector3(0, 1.01, -0.1), "origami": Vector3(0, 1.235, -0.1), "news": Vector3(0, 0.745, -0.12),
	"robo": Vector3(0, 0.67, -0.12), "musha": Vector3(0, 0.53, -0.1), "ningyo": Vector3(0, 0.715, -0.11), "golem": Vector3(0, 1.135, -0.18)}
## 座ったとき、腰の骨の付け根を座面からどれだけ上に置くか（骨の座標の空間）
const SIT_HIPS := 0.07
## 座布団に座ったとき、お尻を座面に沈める深さ（人形の大きさのまま）
const SOFT_SINK := 0.02
## ロッジの席に座ったときの裾の縦の長さ（つぶれて座面に広がる）
const CHAIR_SQUASH := 0.12
## 座布団の席（2 階のこたつ）で、めくって膝に掛けるこたつ布団（kotatsu_futon.gd）の形を測る所: 座布団の前の縁から、
## こたつの天板の縁まで (m)。座布団は穴の縁に 0.03 かかり、天板の縁は穴の縁から 0.42 − 0.078 内
## （lodge/dims.py の PIT_OUT、props/build_room.py の天板）
const LAP_REACH := 0.31
## 天板の縁の高さ（座面から m）。天板の下の面（畳から 0.363、座布団の上の面は 0.118）
const LAP_TOP := 0.245
## ロッジの席に座ったときの太ももの角度のいちばん小さい所（rad。下へ垂れた形から前へ。π/2 で水平）。
## ふだんは膝の芯が座面から脚の太さぶん上に来る角度で、腰の付け根が低い人形でも、これより下へは垂らさない
const SIT_THIGH_MIN := 1.20
## 口の位置（頭の骨の付け根から、人形の大きさのまま）。白い息が出る
const MOUTH := {"kasa": Vector3(0, 0.08, -0.24), "origami": Vector3(0, 0.07, -0.27), "news": Vector3(0, 0.13, -0.3),
	"robo": Vector3(0, 0.05, -0.15), "musha": Vector3(0, 0.04, -0.12), "ningyo": Vector3(0, 0.04, -0.14), "golem": Vector3(0, 0.04, -0.1)}
## 頭のいちばん上（glb の座標、人形の大きさのまま）。雪玉の当たりの背丈と、ハイタッチの手の高さに
const TOP := {"kasa": 1.372, "origami": 1.49, "news": 0.955, "robo": 0.92, "musha": 0.9, "ningyo": 0.95, "golem": 1.25}
const BALL_R := 0.075        # 雪玉の半径 (m)
const BALL_BACK := 4         # 投げてから、次の雪玉が左の袖から右手に出るコマ
## 声: [性別, 高さ, 声色]。sound/gen/voice.py が読んで、人形ごとの声（sound/wav/voice_*_<人形>.wav）を作る。
## 高さが 0 なら、性別と身長（TOP × SCALE）で決める（女性で背が低いほど高く、男性で背が高いほど低い）。
## 0 でなければ、その高さ（あなたの声を 1.0 とした倍率）。声色は "" ふつう・"robot" ロボット・"sharp" 鋭い・"round" 丸い・"beast" 獣のカタコト。
## まだゲームにいない人形も先に書いておく（代表の言葉、2026-10-31）。人形を足したら voice.py を走らせる
const VOICE := {
	"kasa": ["女", 0.0, ""],
	"origami": ["女", 0.0, ""],
	"news": ["男", 0.0, ""],
	"robo": ["", 0.9, "robot"],      # 段ボールのロボット: 真ん中くらいの、ロボロボした声
	"musha": ["", 0.75, "sharp"],    # 折り紙の武者: 低め、シャープな声色
	"ningyo": ["", 1.15, "round"],   # 絹の人形: 高め、丸い声色
	"golem": ["", 0.55, "beast"],    # 継ぎはぎの巨人: いちばん低い、獣っぽいカタコトの声色
}
## 雪玉のストック: 左の袖（前腕）の外側に縫い付けた、藍のフェルトの細い帯。赤い糸に、持っている数だけ綿の雪玉が通る（右下の HUD と同じ形）。
## 人形ごとに [前腕のどこからどこまで（肘 0〜手首 1）, 腕の芯から外へ (m)]
const SLEEVE_STOCK := {"kasa": [0.15, 0.95, 0.05], "origami": [0.15, 0.95, 0.05], "news": [0.15, 0.95, 0.05],
	"robo": [0.15, 0.95, 0.06], "musha": [0.15, 0.9, 0.06], "ningyo": [0.1, 0.8, 0.09], "golem": [0.15, 0.85, 0.15]}
const STOCK_NAVY := Color(0.16, 0.21, 0.38)   # 藍のフェルト（白い雪玉が映える）
const STOCK_RED := Color(0.82, 0.27, 0.22)    # 縫う糸（あなたの赤）
## 米袋の動きのコマ数（12 コマ／秒）。乗る・降りるは押した瞬間に済んでいて、見た目だけがこのコマで追いつく
## （乗り込みの途中でも滑り出せる。足で蹴ると、残りを飛ばしてすぐ座る）
##   out: 0 右手を帯へ / 1 引き抜いて胸の前で両手に / 2 ばさっと前へ広げて落とす / 3 しゃがむ / 4 腰を下ろす（ぽふっ） / 5〜 座って紐を握る
##   in:  0〜1 腰を上げてかがむ / 2〜6 くるくる丸める / 7 跳ねた包みを受ける / 8 帯へ / 9 しまった
const SACK_OUT := 7
const SACK_IN := 10
## 帯の米袋の所（glb の座標、人形の大きさのまま）。右の腰の少し後ろ
const BELT := {"kasa": Vector3(0.2, 0.6, 0.05), "origami": Vector3(0.21, 0.8, 0.06), "news": Vector3(0.24, 0.34, 0.06),
	"robo": Vector3(0.19, 0.27, 0.05), "musha": Vector3(0.17, 0.28, 0.05), "ningyo": Vector3(0.19, 0.42, 0.05), "golem": Vector3(0.36, 0.45, 0.08)}

enum Act { WALK, PUSH, ROPE, RIDE, SIT }

var kind := "kasa"
var layers := 1
var outfit: Array = []       # 服の布ごとの色（outfit.gd の CLOTH の順。Color か null でもとのまま）。作る前に入れる。あとから替えるときは dress()

# 持ち主が毎フレーム入れる
var act := Act.WALK
var facing := Vector3.ZERO   # 体の向き（世界、水平）。ZERO なら持ち主の前
var gaze := Vector3.INF      # 見ている所（世界）
var effort := false
var dragged := false
var _kick_frame := -100      # 足で雪を蹴ったコマ（米袋。kick が入れる）
var _kick_leg := "R"         # ソリに引きずられている（足を前へ突っ張り、体はソリへ引かれて前に傾く）
var sack_anim := ""          # 米袋の動き（sack_start が入れる）: "out" 帯から取り出して広げ、座る / "in" 立って丸め、帯に戻す
var _sack_frame := -100      # その動きが始まったコマ
var belt_sack := false       # 帯に丸めた米袋を下げている（持ち主が毎フレーム入れる）
var belt_color := Color("B8402E")
var lantern := ""            # 帯の左に提げたランタンの形（lantern.gd の LOOKS。"" は提げていない。持ち主が毎フレーム入れる）
var lantern_lit := false     # ランタンが点いている（持ち主が毎フレーム入れる）
var _lantern: Node3D         # lantern.gd
var _lantern_v := Vector3.ZERO   # 前のコマの速さ（世界）。ランタンが振られる向きに
var _vel := Vector3.ZERO
var _roll: Node3D            # 丸めた米袋（帯か右手）
var _roll_hip: Node3D
var _roll_hand: Node3D
var airborne := false
var _air_n := 0               # 宙にいるコマの数
var _land := 0                # 着地の膝の曲げの残りコマ（2 → 1 → 0）
var waving := false
var point := Vector3.INF     # 腕を伸ばして指す所（世界）。gaze が決まっていなければ、そこを見る
var sled: Node3D = null
var sit_stage := 0           # ロッジの席（seats.gd）: 0 立つ、1 中腰、2 座る（持ち主が毎フレーム入れる。act が SIT のとき）
var seat_drop := 0.45        # 座面から足を下ろす床までの高さ (m)（持ち主が入れる）
var seat_edge := 0.2         # 腰を下ろした所から、座面の前の縁までの奥行き (m)（持ち主が入れる）。膝がこれより前なら浮いている
var seat_soft := false       # 座面が座布団（やわらかい）。お尻を座面まで沈める（持ち主が入れる）
var spin_axis := Vector3.ZERO   # 乾燥機の胴といっしょに回る軸（世界。ZERO なら回らない。持ち主が毎フレーム入れる。cook_station.gd）
var spin := 0.0              # その軸まわりに回った角 (rad)
var spin_at := Vector3.ZERO  # 回る中心（世界。胴の真ん中）
## 席といっしょに体ごと傾く（揺り椅子が前後に揺れる、ビーズクッションでうしろへもたれる。hearth_nook.gd）。
## 姿勢はそのまま（乾燥機の胴と違い、手足はぶらぶらしない）。持ち主が毎フレーム入れる。ZERO なら傾かない
var rock_axis := Vector3.ZERO
var rock := 0.0              # その軸まわりに傾いた角 (rad)
var rock_at := Vector3.ZERO  # 傾く中心（世界。揺り椅子の弓の円の中心、ビーズクッションは腰）
## ビーズクッション: 座っているあいだ、体の向きが見ている向き（facing）についてくる（2026-11-03 代表「全方位に向かって座れるから」）。
## 向きは人形と同じ 12 コマ／秒で、1 コマに TURN_STEP まで回る（沈んだまま、もぞもぞ向きを変える）。もたれ（rock）の軸も体の向きから決める。
## 持ち主が毎フレーム入れる（つないだ人へは net.gd の "rt"）
var rock_turns := false
const TURN_STEP := 0.45      # 座ったまま向きを変えるとき、1 コマに回る角 (rad)
var drum_fit := 1.0          # 乾燥機の胴の中で、人形を小さくする倍（胴に収まらない大きな人形。dryer_flop.gd。持ち主が毎フレーム入れる）
var flop := {}               # 胴の中で、手足と頭が戸の向きのまわりにぶらぶら振れる角 (rad。dryer_flop.gd の arm.L・leg.R・head など)
var _foot_shade: Decal       # 足もとの影（胴の中では隠す）
var grip := Vector3.INF      # つかんでいる立ち位置（ソリの座標）
var rope_hand := Vector3.INF # 紐を持つ右手の所（世界）
var lean := Vector2.ZERO     # 乗っているときの体重移動（x 右、y 前）
var holding_ball := false    # 右手に雪玉を持っている
var sleeve_balls := 0        # 左の袖に縫い付けた雪玉の数（持ち主が毎フレーム入れる）
var emote := {}              # いまの身ぶり（emotes.gd の出来事）。終わると空になる
var crouch := false          # しゃがんでいる（持ち主が毎フレーム入れる）
var hand_shapes := ["", ""]  # 掲げている手の高さ [右手, 左手]（"high" 高い手のひら、"low" 低い手のひら、"" は下ろす）
var point_sides := []        # 指さす手（1 右、-1 左。両方なら両腕）。空なら、指す所に近い側

var skel: Skeleton3D
var _b := {}                 # 骨の名前 → 番号
var _order: Array[int] = []  # 親が先
var _rest_rot := {}          # 番号 → 付け根の回転（親の座標）
var _rest_pos := {}
var _rot := {}               # 番号 → いまの回転（親の座標）
var _g := {}                 # 番号 → いまの向きと位置（骨の座標の空間）
var _hold: Array = [null, null]   # 手ごとに [基準のノード, その座標での手の所] か null
var _arm_base := {}          # コマで決めた腕の回転（毎フレームここから伸ばし直す）
var _streams := {}           # 息の煙の出口: "small" ふだん、"big" 声、"long" B の長い息・おーい
var _blow := {"small": 0.0, "big": 0.0}   # 吐き続ける残り (s)。0 になったら出すのをやめる（出た煙は流れ続ける）
var _scale_base := {}        # 出口ごとの、粒の大きさ [最小, 最大]（寒さを掛ける前）
var _breath_mat: ShaderMaterial
var _cold := -1.0            # 白い息の見え方（0 暖かくて見えない 〜 1 ふつう 〜 1.6 とても寒い）。口もとの気温から、数秒でなじむ
var _cold_want := 1.0
var _cold_t := 0.0
var _shiver := 0.0           # 寒さのふるえ（0 〜 1）。口もとの気温から、数秒でなじむ
var _shiver_want := 0.0
var _calm := 0.0             # 暖かさの落ち着き（0 〜 1）。揺れがゆっくりになる
var _calm_want := 0.0
var damp := 0.0              # 湿り気の見た目（damp.gd の look_of。-1 びしょびしょ 〜 0 ふつう 〜 1 パリパリ）。damp.gd が毎フレーム入れる
var pose_step := 1.0         # 姿勢を決めるコマの間隔（12 fps のコマいくつに 1 回。湿ると 1.2・1.5）。damp.gd が毎フレーム入れる
var _damp_mats: Array[ShaderMaterial] = []   # 紙の湿り気の材質（paper_damp.gdshader）
var _damp_shown := INF       # 見た目の湿り気（値をなめらかに追う。姿勢もこれで決める）
var _damp_put := INF         # 材質に入れた湿り気
var _pose_due := -1.0        # 次に姿勢を決めるコマ。湿っていると間隔が空く（damp.gd の段）
var _boil_k := 0.0           # クレイアニメの揺れの進み（整数ごとに新しい形。寒い所では毎コマ 1 進む）
var _idle_t := 0.0           # 立ち止まりの揺れの時計（暖かいとゆっくり進む）
var _next_out := 0
var _frame := -1
var _yaw := 0.0
var _turn_frame := -1
var _last := Vector3.INF
var _speed := 0.0
var _phase := 0.0
var _voice := 0
var _next_breath := 0
var _rng := RandomNumberGenerator.new()
var _scale := 1.0
var _long: CPUParticles3D    # B の長い息・おーい（_streams["long"]）
var _ball: Node3D            # 右手の雪玉
var _stock: Node3D          # 左の袖の雪玉のストック（雪玉がなければ隠す）
var _shapes := {}            # 手の形のアップリケ: 形 → {1: 右手, -1: 左手}
var _palm_goal := {}         # 側 → [形, 手形の置き所（人形の座標）]。コマで決め、腕はその手首へ伸ばす
var _hands_frame := 0        # 手の形を変えたコマ（ぽんと出る大きさに）
const HAND_TUCK := 0.01      # 手形を出している手の、元の手の骨の大きさ（手首へ縮めて隠す）
var _em_head := Vector2.ZERO # 身ぶりが頭に足す向き（x 左右、y 上下）
var _em_roll := 0.0          # 身ぶりが頭に足す傾き（首をかしげる。正で右へ）


func _ready() -> void:
	top_level = true
	add_to_group("dolls")   # 暖炉のまわりの家具が、座っている人形を探す（hearth_nook.gd）
	_scale = SCALE[kind]
	var inst: Node3D = (load(SCENES[kind]) as PackedScene).instantiate()
	inst.scale = Vector3.ONE * _scale
	add_child(inst)
	skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	_add_skirt(inst)
	_make_damp(inst)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).layers = layers
	_body = inst
	add_to_group("dolls")
	if not outfit.is_empty():
		dress(outfit)
	for i in skel.get_bone_count():
		_b[skel.get_bone_name(i)] = i
		var r := skel.get_bone_rest(i)
		_rest_rot[i] = r.basis.get_rotation_quaternion()
		_rest_pos[i] = r.origin
		_rot[i] = _rest_rot[i]
	var depth := func(i: int) -> int:
		var d := 0
		var p := skel.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = skel.get_bone_parent(p)
		return d
	for i in skel.get_bone_count():
		_order.append(i)
	_order.sort_custom(func(a, b): return depth.call(a) < depth.call(b))
	_make_breath()
	_make_ball()
	_make_stock()
	_make_roll()
	_lantern = Lantern.new(self)
	add_child(_lantern)
	_lantern.setup(skel, skel.get_bone_global_rest(_id("hips")), kind, _scale)
	_shapes = Palm.make_set(Color(FpHands.STYLE.get(kind, FpHands.STYLE["kasa"]).hand), layers)
	for sh in _shapes:
		for n in _shapes[sh].values():
			add_child(n)
	_make_foot_shadow()
	_measure_body(inst)
	_next_breath = randi_range(4, 30)


# ---------------------------------------------------------------- 体の形（雪玉の当たり）

const BODY_BANDS := 12       # 体を高さで切る数
static var _body_cache := {} # 人形の種類 → [各段の太さ (m), 頭のてっぺん (m), 頭の骨の高さ (m)]


## 立った人形の形から、高さごとの太さ（体の軸からの横の広がり）を測る。笠のつば・着物の裾・頭巾の形がそのまま入る。
## 袖や髪の先の細いはみ出しは除く（各段で 9 割の点が入る太さ）。人形の種類ごとに一度だけ測る
func _measure_body(inst: Node3D) -> void:
	if _body_cache.has(kind):
		return
	var pts := PackedVector3Array()
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var to_doll := global_transform.affine_inverse() * mi.global_transform
		for si in mi.mesh.get_surface_count():
			# 頂点だけでは、着物の裾のような大きな平たい面の途中が抜ける。面の上に 5 cm ほどおきに点を打つ
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			for t in range(0, idx.size() - 2, 3):
				var a := to_doll * vs[idx[t]]
				var b := to_doll * vs[idx[t + 1]]
				var c := to_doll * vs[idx[t + 2]]
				var n := clampi(ceili(maxf(maxf(a.distance_to(b), b.distance_to(c)), c.distance_to(a)) / 0.05), 1, 24)
				for i in n + 1:
					for j in n + 1 - i:
						pts.append(a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n))
	var top := 0.0
	for v in pts:
		top = maxf(top, v.y)
	var bands := []
	for i in BODY_BANDS:
		bands.append([])
	for v in pts:
		var bi := clampi(int(v.y / top * BODY_BANDS), 0, BODY_BANDS - 1)
		bands[bi].append(Vector2(v.x, v.z).length())
	var radii := PackedFloat32Array()
	for b in bands:
		b.sort()
		radii.append(b[int(b.size() * 0.9)] if not b.is_empty() else 0.0)
	var head_y := (global_transform.affine_inverse() * (skel.global_transform * skel.get_bone_global_rest(_id("head")).origin)).y
	_body_cache[kind] = [radii, top, head_y]


## 点 p（世界）が、いまの体の形の中（r だけふくらませて）に入るか。しゃがむ・座ると、頭の骨の下がった分だけ縮める
func body_hit(p: Vector3, r: float) -> bool:
	var c: Array = _body_cache.get(kind, [])
	if c.is_empty():
		return false
	var radii: PackedFloat32Array = c[0]
	var top: float = c[1]
	var head_now := (skel.global_transform * _head_of(_id("head"))).y - global_position.y
	var squash := clampf(head_now / maxf(c[2], 0.01), 0.3, 1.2)
	var dy := (p.y - global_position.y) / squash
	if dy < -r or dy > top + r:
		return false
	var bi := clampi(int(dy / top * BODY_BANDS), 0, BODY_BANDS - 1)
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < radii[bi] + r


static func frame_index() -> int:
	return Engine.get_physics_frames() * FPS / Engine.physics_ticks_per_second


## 声を出す（言葉にならない声）。少し見上げて、大きな白い息が出る（持ち主のいない見本用。ゲームでは「ワ〜」の身ぶり）
func call_out() -> void:
	play({"kind": "wa", "frame": frame_index() + 1})


## 身ぶりを始める。出来事のコマ（ev.frame）から数えて姿勢を決める。手の形は、身ぶりとは別に下ろすまで続く
func play(ev: Dictionary) -> void:
	if ev.kind == "hands":
		var h: Array = Palm.HANDS.get(ev.hands, ["", ""])
		hand_shapes = [h[0], h[1]]
		_hands_frame = int(ev.frame)
		return
	if ev.kind == "breath_end":
		if emote.get("kind", "") == "breath":
			emote["until"] = int(ev.frame)   # 吐くのをやめる（少しで胸が戻る）
		return
	emote = ev


## 乾燥機の胴の中の大きさ（m、人形の座標。dryer_flop.gd が胴の壁に当てる）: 胴の中の姿勢（_drum_sprawl）で
## x はいちばん低い骨（足）、y は頭のてっぺん、z は頭の高さでの体の軸からの広さ（笠のつば・頭巾。_measure_body の上 3 割の段の太さ）。
## 腕や裾の広さは入れない（腕は胴の中でぶらぶら振れる）。
## 人形の種類と大きさだけで決まる（どの画面でも同じ）
func drum_extent() -> Vector3:
	var c: Array = _body_cache.get(kind, [])
	var hold := _hold
	_reset()
	_drum_sprawl()
	var lo := INF
	var head := 0.0
	var to_doll := _body.transform * (_body.global_transform.affine_inverse() * skel.global_transform)   # 骨の座標 → 人形の座標
	for i in _order:
		var y := (to_doll * (_g[i] as Transform3D).origin).y
		lo = minf(lo, y)
		if i == _id("head"):
			head = y
	var r := 0.2
	var top := head + 0.25 * _scale
	if not c.is_empty():
		r = 0.0
		var radii: PackedFloat32Array = c[0]
		for bi in range(int(radii.size() * 0.7), radii.size()):
			r = maxf(r, radii[bi])
		top = head + (float(c[1]) - float(c[2]))   # 頭の骨から頭のてっぺん（笠）まで
	_reset()
	_hold = hold
	return Vector3(lo, top, r)


## 頭のてっぺんの高さ (m)
func height() -> float:
	return TOP.get(kind, 1.3) * _scale


## 乗ったまま足で雪を蹴る（side 1 右足、-1 左足）。次のコマから 3 コマ
func kick(side: int) -> void:
	_kick_frame = frame_index() + 1
	_kick_leg = "R" if side > 0 else "L"
	if sack_anim == "out":
		_sack_frame = mini(_sack_frame, frame_index() + 1 - 5)   # 乗り込みの途中で蹴ったら、すぐ座った姿に


## 米袋の動きを始める（what: "out" 取り出して乗る / "in" 立って丸めてしまう）。次のコマから
func sack_start(what: String) -> void:
	sack_anim = what
	_sack_frame = frame_index() + 1


## 米袋の動きの、始まってからのコマ数。その動きでなければ（終わっていれば）-1
func sack_k(what: String) -> int:
	if sack_anim != what:
		return -1
	var k := frame_index() - _sack_frame
	if k >= (SACK_OUT if what == "out" else SACK_IN):
		sack_anim = ""
		return -1
	return maxi(k, 0)


## 乗っていて、もう腰を下ろしているか（取り出して広げているあいだは立っている）。一人称の目の高さに使う
func sack_seated() -> bool:
	var k := sack_k("out")
	return act == Act.RIDE and (k < 0 or k >= 3)


## いまの身ぶりの種類と、始まってからのコマ数。身ぶりがなければ ["", -1]
func emote_now() -> Array:
	if emote.is_empty():
		return ["", -1]
	return [emote.kind, frame_index() - int(emote.frame)]


# ---------------------------------------------------------------- 骨の小道具（骨の座標の空間で考える）

func _id(name: String) -> int:
	return _b.get(name, -1)


## 付け根の姿勢に戻し、親から順に向きと位置を計算する
func _reset() -> void:
	for i in _order:
		_rot[i] = _rest_rot[i]
	_hips_drop = 0.0
	_squash = 1.0
	_leg_lift = 0.0
	_update_all()


var _hips_drop := 0.0
var _squash := 1.0           # 腰より下の裾の縦の長さ（座ると、つぶれて座面に広がる）
var _leg_lift := 0.0         # 太ももの付け根を上へずらす量（骨の座標の空間）。座布団で、お尻を座面に着けると付け根が沈む人形
var _lift_at := {}           # 骨の番号 → 付け根をずらした分（親の骨の座標。_apply が使う）
## 座布団の席（こたつ）で、めくったこたつ布団が通る線（世界の座標。お腹の前から天板の縁まで、脚の上を脚の太さぶん離して）。
## 座っていなければ空。こたつの布団（kotatsu_futon.gd）が読んで、この人形の側の布団をめくって膝に掛ける
var lap_line := PackedVector3Array()


func _update_all() -> void:
	for i in _order:
		_update(i)


func _update(i: int) -> void:
	var p := skel.get_bone_parent(i)
	var pos: Vector3 = _rest_pos[i] + (Vector3(0, -_hips_drop, 0) if p < 0 else Vector3.ZERO)
	_lift_at.erase(i)
	if _leg_lift > 0.0 and p >= 0 and (i == _id("thigh.L") or i == _id("thigh.R")):
		_lift_at[i] = (_g[p] as Transform3D).basis.inverse() * Vector3(0, _leg_lift, 0)
		pos += _lift_at[i]
	var local := Transform3D(Basis(_rot[i]), pos)
	_g[i] = (_g[p] * local) if p >= 0 else local


## 骨を、骨の座標の空間の回転 q で回す（子は一緒に回る。子の向きは _update_all で計算し直す）
func _turn(i: int, q: Quaternion) -> void:
	if i < 0:
		return
	var p := skel.get_bone_parent(i)
	var pb: Basis = (_g[p] as Transform3D).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var lb := Basis(_rot[i])
	_rot[i] = (pb.inverse() * Basis(q) * pb * lb).get_rotation_quaternion()
	_update_subtree(i)


func _update_subtree(i: int) -> void:
	_update(i)
	for c in skel.get_bone_children(i):
		_update_subtree(c)


func _turn_axis(name: String, axis: Vector3, angle: float) -> void:
	if absf(angle) > 1e-5:
		_turn(_id(name), Quaternion(axis.normalized(), angle))


## 骨の向き（付け根から先へ）を dir に向ける
func _aim(i: int, dir: Vector3) -> void:
	if i < 0 or dir.length() < 1e-5:
		return
	var y: Vector3 = (_g[i] as Transform3D).basis.y.normalized()
	var d := dir.normalized()
	if y.dot(d) > 0.9999:
		return
	_turn(i, Quaternion(y, d))


func _head_of(i: int) -> Vector3:
	return (_g[i] as Transform3D).origin


func _len(i: int) -> float:
	var c := skel.get_bone_children(i)
	if c.is_empty():
		return 0.08
	return (_rest_pos[c[0]] as Vector3).length()


## 二関節の腕で、手が target（骨の座標の空間）に来るように曲げる
func _reach(side: String, target: Vector3, to_wrist := false) -> void:
	var j := _arm_joints(side, target, to_wrist)
	if j.is_empty():
		return
	_aim(_id("upper_arm." + side), j[1] - j[0])
	var fo := _id("forearm." + side)
	_aim(fo, j[2] - _head_of(fo))


## _reach で曲げたときの [肩, 肘, 手]（骨の座標の空間）。腕の骨がなければ空
func _arm_joints(side: String, target: Vector3, to_wrist := false) -> Array:
	var up := _id("upper_arm." + side)
	var fo := _id("forearm." + side)
	if up < 0 or fo < 0:
		return []
	var s := _head_of(up)
	var a := _len(up)
	# 手首（前腕の先）を合わせるか、手のなかほどを合わせるか
	var b := _len(fo) + (0.0 if to_wrist else _len(_id("hand." + side)) * 0.5)
	var to := target - s
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.001)
	var dir := to.normalized()
	var sx := 1.0 if side == "R" else -1.0
	var pole := Vector3(sx * 0.7, -0.5, 0.6).normalized()
	pole = (pole - dir * pole.dot(dir)).normalized()
	var ang := acos(clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0))
	var elbow := s + (dir * cos(ang) + pole * sin(ang)) * a
	return [s, elbow, s + dir * d]


func _apply() -> void:
	for i in _order:
		skel.set_bone_pose_rotation(i, _rot[i])
		skel.set_bone_pose_position(i, _rest_pos[i] + (Vector3(0, -_hips_drop, 0) if skel.get_bone_parent(i) < 0 else Vector3.ZERO)
			+ _lift_at.get(i, Vector3.ZERO))
	var sk := _id("skirt")
	if sk >= 0:
		skel.set_bone_pose_scale(sk, Vector3(1, _squash, 1))
		# 体ごとうしろへもたれる席（ビーズクッション）: 裾だけはもたれを打ち消して水平に（広がった裾のうしろが床を抜けない。座面に広がる）
		var q := Quaternion.IDENTITY
		if act == Act.SIT and rock_axis != Vector3.ZERO and absf(rock) > 0.1:
			var hb := skel.get_bone_global_pose(skel.get_bone_parent(sk)).basis.orthonormalized()
			q = Quaternion(hb.inverse() * Basis(Vector3.RIGHT, -rock) * hb)
		skel.set_bone_pose_rotation(sk, q)
	# 手形のワッペンを出している手は、元の手を隠す（2026-11-02 代表「エモートで手のワッペン出すとき、元のキャラの手は一時的に
	# 消してほしい。どっちもあると意味わからない」）。手の骨を手首へ縮める。手に付けた物（雪玉・小窓の持ち物）も一緒に隠れる。
	# 手形の置き所と同じく姿勢のコマで決まるので、手形が出るコマに消え、手形が消えるコマに戻る（どの画面でも同じコマ）
	for side in [1, -1]:
		var hd := _id("hand.R" if side > 0 else "hand.L")
		if hd >= 0:
			skel.set_bone_pose_scale(hd, Vector3.ONE * (HAND_TUCK if _palm_goal.has(side) else 1.0))


## 座るときに腰を落とす量（骨の座標の空間）。腰の骨の付け根を座面から SIT_HIPS の所へ
func _sit_drop() -> float:
	return skel.get_bone_global_rest(_id("hips")).origin.y - SIT_HIPS


## ロッジの席に座るときに腰を落とす量。脚の付け根が腰よりずっと低い人形は、脚の付け根が座面の上（脚の太さぶん上）に
## 残る所まで（脚が座面に沈まない）。ソリでは脚が座布団に埋もれてケープに隠れるのでよいが、椅子では脚が座面を突き抜ける
func _chair_drop() -> float:
	var drop := _sit_drop()
	var th := _id("thigh.L")
	if th >= 0:
		drop = minf(drop, skel.get_bone_global_rest(th).origin.y - _seat_shape()[3])
	if seat_soft:
		# 座布団: 脚の付け根で止めると、脚の短い人形はお尻が浮く。お尻（腰・胸・裾のいちばん下）が座面に SOFT_SINK 沈むまで
		# 下ろす。脚の付け根がそれで座面に沈むなら、_sit_chair が付け根を体の中へ持ち上げる（_leg_lift）
		# 裾は座るとつぶれる（CHAIR_SQUASH）ので、つぶれた裾の下の端で測る
		var bottom: float = _seat_shape()[4]
		var sk := _id("skirt")
		if sk >= 0 and _seat_shape()[5] < INF:
			var root := skel.get_bone_global_rest(sk).origin.y
			bottom = minf(bottom, root + (_seat_shape()[5] - root) * CHAIR_SQUASH)
		drop = maxf(drop, bottom + SOFT_SINK)
	return drop


## ロッジの席に座る（seats.gd）。腰の骨の付け根を座面のすぐ上へ下ろし、裾は座面に広げ、太ももは座面に沿って前へ。
## 膝が座面の上にあれば（脚が短い、座面が深い）、すねも前へ投げ出して座面の上に置く（すねが座面にめりこまない）。
## 膝が座面の前の縁より前で浮いていれば、膝を曲げてすねを垂らす。垂らしたすねは座面の縁に当たらない所まで前へ出し、
## 足が床に届くなら、すねを前へ振り出して足の裏を床に置く（床を突き抜けない）。
## 太ももを座面に沿わせて上げないので、膝が机の天板の裏に当たらない。両手は膝の上（体に埋もれるなら体の外、_sit_hand）。
## 返り値は胸を前へ曲げる量
func _sit_chair() -> float:
	var X := Vector3.RIGHT
	_hips_drop = _chair_drop()
	_squash = CHAIR_SQUASH
	var lr: float = _seat_shape()[3]     # 脚の太さ
	var th0 := _id("thigh.L")
	if seat_soft and th0 >= 0:
		# 座布団: 脚の付け根が座面に沈むなら、付け根を体の中へ上げ、脚が座布団に半分沈む高さに（脚は前へ投げ出す）
		_leg_lift = maxf(0.0, lr * 0.5 - (skel.get_bone_global_rest(th0).origin.y - _hips_drop))
	_update_all()
	var floor_y := -seat_drop / _scale   # 骨の座標の空間。座面が 0、前が -Z
	var edge := seat_edge / _scale
	for s in ["L", "R"]:
		var th := _id("thigh." + s)
		var sh := _id("shin." + s)
		var ft := _id("foot." + s)
		if th < 0 or sh < 0 or ft < 0:
			continue
		# 太もも: 膝の芯が座面から脚の太さぶん上に来るまで前へ倒す（水平より上げない）
		var hip := _head_of(th)
		var bend := clampf(acos(clampf((hip.y - lr) / _len(th), -1.0, 1.0)), SIT_THIGH_MIN, PI * 0.5)
		_turn_axis("thigh." + s, X, bend)
		_update_all()
		var knee := _head_of(sh)
		var shin := _len(sh)
		var sole := skel.get_bone_global_rest(ft).origin.y   # 足首から足の裏まで（立った形の足首の高さ）
		# すねの角度（真下から前へ。0 で垂らす、π/2 で前へ投げ出す）: 座面の縁の高さで、すねの芯が縁より脚の太さぶん前に出る角度
		var fwd := 0.0
		var ahead := edge + lr - (-knee.z)   # 膝から、すねが越えるべき縁の先まで
		if ahead > 0.0:
			fwd = atan2(ahead, knee.y - lr) if knee.y > lr else PI * 0.5
		fwd = clampf(fwd, 0.0, PI * 0.5)
		if knee.y - shin * cos(fwd) - sole < floor_y:
			# 足が床に届く: すねを前へ振り出して、足の裏を床に
			fwd = maxf(fwd, acos(clampf((knee.y - sole - floor_y) / shin, -1.0, 1.0)))
		_turn_axis("shin." + s, X, -(bend - fwd))
	_update_all()
	for s in ["L", "R"]:
		var th := _id("thigh." + s)
		var sh := _id("shin." + s)
		if th < 0 or sh < 0:
			continue
		var p := _sit_hand(s, _head_of(th), _head_of(sh))
		if p != Vector3.INF:
			_hold[0 if s == "L" else 1] = [self, to_local(skel.global_transform * p)]
	if seat_soft:
		_lap_futon(lr)
	return 0.08


## 座布団の席（こたつ）: めくったこたつ布団が通る線（lap_line）を測る。お腹（脚を除いた体）の前の面から、脚の上（脚の太さぶん
## 離して）を通り、こたつの天板の縁まで。両手は布団の上の、膝のあたり
func _lap_futon(lr: float) -> void:
	var pts := PackedVector3Array()   # 脚の芯の上の点
	var hip_z := 0.0
	for s in ["L", "R"]:
		var th := _id("thigh." + s)
		var sh := _id("shin." + s)
		var ft := _id("foot." + s)
		if th < 0 or sh < 0 or ft < 0:
			continue
		var a := _head_of(th)
		var k := _head_of(sh)
		var f := _head_of(ft)
		var toe := f + (_g[ft] as Transform3D).basis.y.normalized() * _len(ft)
		for i in 5:
			pts.append(a.lerp(k, i / 4.0))
			pts.append(k.lerp(f, i / 4.0))
			pts.append(f.lerp(toe, i / 4.0))
		hip_z += a.z * 0.5
	var clear := lr + 0.012 / _scale
	var knee_y := 0.0
	for s2 in ["L", "R"]:
		knee_y += _head_of(_id("shin." + s2)).y * 0.5 if _id("shin." + s2) >= 0 else 0.0
	# お腹の前の面を、膝の高さで探す（脚は除く）
	var z0 := _out_of_body(Vector3(0, knee_y + clear, hip_z), 0.015 / _scale, [Vector3.FORWARD], true).z
	var far_z := -(seat_edge + LAP_REACH) / _scale
	if far_z >= z0:
		return
	var n := 8
	var step := (z0 - far_z) / (n - 1)
	var lap_h := knee_y + clear
	for i in n:
		var z := lerpf(z0, far_z, float(i) / (n - 1))
		var y := knee_y + clear
		for p in pts:
			if absf(p.z - z) < step:
				y = maxf(y, p.y + clear)
		lap_h = maxf(lap_h, y) if i < n / 2 else lap_h
		lap_line.append(skel.global_transform * Vector3(0, y, z))
	lap_line.append(skel.global_transform * Vector3(0, LAP_TOP / _scale, far_z))
	# 両手は布団の上、膝のあたりに（布団は膝の上で lap_h の高さ。厚みのぶん上）
	var hr: float = _seat_shape()[2]
	for k in 2:
		var sh := _id("shin." + ("L" if k == 0 else "R"))
		if sh < 0:
			continue
		var kn := _head_of(sh)
		var hand := Vector3(kn.x * 0.8, lap_h + 0.035 / _scale + hr, minf(kn.z, z0 - 0.03 / _scale))
		_hold[k] = [self, to_local(skel.global_transform * hand)]


## 座ったときの手の所（骨の座標の空間）。膝の上に置き、体（胸・腰・裾・脚）に埋もれるなら、上・前・外のいちばん近い向きへ体の外に出す。
## 膝まで届かなければ（脚が短くお腹の丸い人形）、膝の方へ伸ばした先を体の前へ出す。それでも届かないか、座面の縁より前に出る
## （腕を前へ伸ばして袖が机に当たる）か、前腕が体を通るなら、
## 立ったときのまま腕を垂らす（INF を返す）。垂らした手が体に入るなら、その手を体の外へ出し、それもだめなら体の横に下ろして
## 座面の脇へ（届かなければ、腕を伸ばした先）
func _sit_hand(side: String, hip: Vector3, knee: Vector3) -> Vector3:
	var sx := 1.0 if side == "R" else -1.0
	var r: float = _seat_shape()[2]        # 手を体から離す
	var ra: float = _seat_shape()[1] * 0.3  # 前腕の芯を体から離す
	var up := _id("upper_arm." + side)
	var s := _head_of(up)
	var reach := (_len(up) + _len(_id("forearm." + side)) + _len(_id("hand." + side)) * 0.5) * 0.97
	var want := hip.lerp(knee, 0.75) + Vector3(0, 0.06, 0)
	if want.distance_to(s) < reach and not _in_seat_body(want, r):
		return want
	var p := _out_of_body(want, r, [Vector3.UP, Vector3.FORWARD, Vector3(sx, 0, 0)])
	if p.distance_to(s) >= reach:
		# 膝まで届かない: 膝の方へ伸ばせるだけ伸ばし、体の前（お腹や太ももの上）へ出す
		for i in 3:
			p = _out_of_body(s + (p - s).normalized() * minf(p.distance_to(s), reach), r, [Vector3.FORWARD, Vector3(sx, 0, 0), Vector3.UP])
	if p.distance_to(s) < reach * 1.02 and -p.z <= seat_edge / _scale and _forearm_clear(side, p, ra):
		return p
	# 立ったときの腕の垂らし方のままで手が体の外なら、そのまま（人形の形は、立って腕を垂らしたときに体に当たらないように作ってある）。
	# 座ってつぶれた裾に手が入るなら、裾の上へ出す
	var hd := _id("hand." + side)
	if hd >= 0:
		var g: Transform3D = _g[hd]
		var h := g.origin + g.basis.y.normalized() * _len(hd) * 0.5
		if not _in_seat_body(h, ra):
			return Vector3.INF
		h = _out_of_body(h, r, [Vector3.UP, Vector3.FORWARD, Vector3(sx, 0, 0)])
		if h.distance_to(s) < reach and _forearm_clear(side, h, ra):
			return h
	var q := Vector3(s.x, r, hip.lerp(knee, 0.25).z)
	for i in 3:
		q = _out_of_body(q, r, [Vector3(sx, 0, 0)])
		if q.distance_to(s) <= reach:
			break
		q = s + (q - s).normalized() * reach
	return q


## 前腕から手（target）までが、体の中を通らないか
func _forearm_clear(side: String, target: Vector3, r: float) -> bool:
	var j := _arm_joints(side, target)
	if j.is_empty():
		return true
	for i in range(1, 5):
		if _in_seat_body((j[1] as Vector3).lerp(j[2], i / 4.0), r):
			return false
	return true


## 点 p を、向き dirs のうち体の外にいちばん近く出られる向きへ、体の外（r だけ離して）まで動かす
func _out_of_body(p: Vector3, r: float, dirs: Array, no_legs := false) -> Vector3:
	if not _in_seat_body(p, r, no_legs):
		return p
	var step := 0.01
	for k in 80:
		for d in dirs:
			var q: Vector3 = p + d * step * (k + 1)
			if not _in_seat_body(q, r, no_legs):
				return q
	return p


# ---------------------------------------------------------------- 体の形（座った手）

const SEAT_BODY := ["hips", "chest", "skirt", "thigh.L", "thigh.R", "shin.L", "shin.R"]
const SEAT_SLICES := 10
const SEAT_CELL := 0.025       # 輪切りの升の大きさ（人形の大きさのまま）
const SEAT_PAD := 7            # 形のまわりに足す升（手の太さぶん離して調べられる）
static var _seat_cache := {}   # 人形の種類 → [{骨の番号: [下の端, 段の高さ, 升の x と z の始まり, 升の数 x, z, 段ごとの升（体までの升の数）]}, 前腕の太さ, 手の太さ, 脚の太さ, 腰・胸のいちばん下, 裾のいちばん下]


## 体（胸・腰・裾・脚）の形を、骨ごとにその骨の座標で、骨に沿って輪切りにした段の升目で覚える。
## 前腕の太さは、前腕の点の骨からの離れの真ん中。手の太さは、右手の点の真ん中からの離れの真ん中。
## 脚の太さは、太もも・すねの点の骨からの離れの真ん中（座ったすねを座面の縁から離す）。人形の種類ごとに一度だけ測る
func _seat_shape() -> Array:
	if _seat_cache.has(kind):
		return _seat_cache[kind]
	var pts := {}
	var arm := []
	var hand := PackedVector3Array()
	var leg := []
	var bottom := INF        # 腰・胸のいちばん下（立った形の人形の座標）
	var skirt_bottom := INF  # 裾のいちばん下（同じ）
	for m in _body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.skin == null:
			continue
		var bone_of := []
		for b in mi.skin.get_bind_count():
			var bi := mi.skin.get_bind_bone(b)
			bone_of.append(bi if bi >= 0 else skel.find_bone(mi.skin.get_bind_name(b)))
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null:
				continue
			var per: int = bones.size() / vs.size()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			for t in range(0, idx.size() - 2, 3):
				# 面の最初の頂点のいちばん重い骨のものとし、面の上に 3 cm ほどおきに点を打つ（大きな平たい面の途中が抜けない）
				var top := 0
				for j in per:
					if weights[idx[t] * per + j] > weights[idx[t] * per + top]:
						top = j
				var bind: int = bones[idx[t] * per + top]
				var bn := skel.get_bone_name(bone_of[bind])
				var is_arm := bn.begins_with("forearm")
				var is_hand := bn == "hand.R"
				var is_leg := bn.begins_with("thigh") or bn.begins_with("shin")
				if not is_arm and not is_hand and not (bn in SEAT_BODY):
					continue
				var to_bone := mi.skin.get_bind_pose(bind)
				if not is_arm and not is_hand and not is_leg:
					var y := (skel.get_bone_global_rest(bone_of[bind]) * (to_bone * vs[idx[t]])).y
					if bn == "skirt":
						skirt_bottom = minf(skirt_bottom, y)
					else:
						bottom = minf(bottom, y)
				var a := to_bone * vs[idx[t]]
				var b := to_bone * vs[idx[t + 1]]
				var c := to_bone * vs[idx[t + 2]]
				var n := clampi(ceili(maxf(maxf(a.distance_to(b), b.distance_to(c)), c.distance_to(a)) / 0.03), 1, 24)
				for i in n + 1:
					for j in n + 1 - i:
						var v := a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n)
						if is_arm:
							arm.append(Vector2(v.x, v.z).length())
						elif is_hand:
							hand.append(v)
						else:
							if is_leg:
								leg.append(Vector2(v.x, v.z).length())
							if not pts.has(bone_of[bind]):
								pts[bone_of[bind]] = PackedVector3Array()
							pts[bone_of[bind]].append(v)
	var shape := {}
	for bi in pts:
		var vs: PackedVector3Array = pts[bi]
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for v in vs:
			lo = lo.min(v)
			hi = hi.max(v)
		var dy := maxf(hi.y - lo.y, 0.01) / SEAT_SLICES
		var ox := lo.x - SEAT_PAD * SEAT_CELL
		var oz := lo.z - SEAT_PAD * SEAT_CELL
		var nx := int((hi.x - lo.x) / SEAT_CELL) + 1 + SEAT_PAD * 2
		var nz := int((hi.z - lo.z) / SEAT_CELL) + 1 + SEAT_PAD * 2
		var occ := []
		for i in SEAT_SLICES:
			var g := PackedByteArray()
			g.resize(nx * nz)
			occ.append(g)
		for v in vs:
			var k := clampi(int((v.y - lo.y) / dy), 0, SEAT_SLICES - 1)
			occ[k][int((v.z - oz) / SEAT_CELL) * nx + int((v.x - ox) / SEAT_CELL)] = 1
		var slices := []
		for g in occ:
			slices.append(_seat_slice(g, nx, nz))
		shape[bi] = [lo.y, dy, ox, oz, nx, nz, slices]
	arm.sort()
	var mid := Vector3.ZERO
	for v in hand:
		mid += v / hand.size()
	var hr := []
	for v in hand:
		hr.append(v.distance_to(mid))
	hr.sort()
	leg.sort()
	_seat_cache[kind] = [shape, arm[arm.size() / 2] if not arm.is_empty() else 0.03, hr[hr.size() / 2] if not hr.is_empty() else 0.03,
		leg[leg.size() / 2] if not leg.is_empty() else 0.04, bottom if bottom < INF else 0.0, skirt_bottom]
	return _seat_cache[kind]


## 輪切りの 1 段の升目（形の面が通る升が 1）を、中まで埋めて、升ごとに体までの升の数（縦横斜めに数える）にする。
## 中を埋めるのは、横の並びでも縦の並びでも面にはさまれた升（離れた飾りの紐と体の間は埋めない）
func _seat_slice(occ: PackedByteArray, nx: int, nz: int) -> PackedByteArray:
	var row_lo := PackedInt32Array()
	var row_hi := PackedInt32Array()
	row_lo.resize(nz)
	row_hi.resize(nz)
	row_lo.fill(nx)
	row_hi.fill(-1)
	var col_lo := PackedInt32Array()
	var col_hi := PackedInt32Array()
	col_lo.resize(nx)
	col_hi.resize(nx)
	col_lo.fill(nz)
	col_hi.fill(-1)
	for z in nz:
		for x in nx:
			if occ[z * nx + x]:
				row_lo[z] = mini(row_lo[z], x)
				row_hi[z] = maxi(row_hi[z], x)
				col_lo[x] = mini(col_lo[x], z)
				col_hi[x] = maxi(col_hi[x], z)
	var d := PackedByteArray()
	d.resize(nx * nz)
	for z in nz:
		for x in nx:
			var inside := occ[z * nx + x] == 1 or (x >= row_lo[z] and x <= row_hi[z] and z >= col_lo[x] and z <= col_hi[x])
			d[z * nx + x] = 0 if inside else 255
	# 体までの升の数: 前から後ろ、後ろから前の 2 回なめる
	for z in nz:
		for x in nx:
			var v := d[z * nx + x]
			if x > 0:
				v = mini(v, d[z * nx + x - 1] + 1)
			if z > 0:
				v = mini(v, d[(z - 1) * nx + x] + 1)
				if x > 0:
					v = mini(v, d[(z - 1) * nx + x - 1] + 1)
				if x < nx - 1:
					v = mini(v, d[(z - 1) * nx + x + 1] + 1)
			d[z * nx + x] = v
	for z in range(nz - 1, -1, -1):
		for x in range(nx - 1, -1, -1):
			var v := d[z * nx + x]
			if x < nx - 1:
				v = mini(v, d[z * nx + x + 1] + 1)
			if z < nz - 1:
				v = mini(v, d[(z + 1) * nx + x] + 1)
				if x < nx - 1:
					v = mini(v, d[(z + 1) * nx + x + 1] + 1)
				if x > 0:
					v = mini(v, d[(z + 1) * nx + x - 1] + 1)
			d[z * nx + x] = v
	return d


## 点 p（骨の座標の空間）が、いまの姿勢の体（胸・腰・裾・脚）の中（r だけふくらませて）に入るか。裾は座ってつぶれた分も
func _in_seat_body(p: Vector3, r: float, no_legs := false) -> bool:
	var sk := _id("skirt")
	var shape: Dictionary = _seat_shape()[0]
	for bi in shape:
		if no_legs and (skel.get_bone_name(bi).begins_with("thigh") or skel.get_bone_name(bi).begins_with("shin")):
			continue
		var c: Array = shape[bi]
		var l := (_g[bi] as Transform3D).affine_inverse() * p
		var sq := maxf(_squash, 0.05) if bi == sk else 1.0
		var ly := l.y / sq
		var ry := r / sq
		var lo: float = c[0]
		var dy: float = c[1]
		if ly < lo - ry or ly > lo + dy * SEAT_SLICES + ry:
			continue
		var ox: float = c[2]
		var oz: float = c[3]
		var nx: int = c[4]
		var nz: int = c[5]
		var ix := floori((l.x - ox) / SEAT_CELL)
		var iz := floori((l.z - oz) / SEAT_CELL)
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
			continue
		var g: PackedByteArray = c[6][clampi(int((ly - lo) / dy), 0, SEAT_SLICES - 1)]
		if g[iz * nx + ix] * SEAT_CELL <= r + SEAT_CELL * 0.5:
			return true
	return false


## 乾燥機の胴の中（spin_axis がある）: 腰を半ば落とし、膝をゆるく曲げて脚を少し開き、腕は横へ垂らす。手は何もつかまない。
## 手足と頭は、このあと _flop_limbs が胴の中の物理（dryer_flop.gd）のとおりに振る。返り値は胸を前へ曲げる量
func _drum_sprawl() -> float:
	var X := Vector3.RIGHT
	var Z := Vector3.BACK
	_hips_drop = _sit_drop() * 0.5
	_squash = 0.5
	_update_all()
	for s in ["L", "R"]:
		var out := 1.0 if s == "R" else -1.0
		_turn_axis("thigh." + s, X, 0.9)
		_turn_axis("shin." + s, X, -1.2)
		_turn_axis("thigh." + s, Z, 0.3 * out)
		_turn_axis("upper_arm." + s, Z, 0.5 * out)
	_hold = [null, null]
	return 0.1


## 胴の中で、手足と頭を戸の向き（spin_axis）のまわりに flop の角だけ振る（前腕とすねは少し遅れて半ばほど）
func _flop_limbs() -> void:
	if _foot_shade:
		_foot_shade.visible = spin_axis == Vector3.ZERO
	if spin_axis == Vector3.ZERO or flop.is_empty():
		return
	var f := (skel.global_transform.basis.inverse() * spin_axis).normalized()
	for s in ["L", "R"]:
		var a: float = flop.get("arm." + s, 0.0)
		var l: float = flop.get("leg." + s, 0.0)
		_turn(_id("upper_arm." + s), Quaternion(f, a))
		_turn(_id("forearm." + s), Quaternion(f, a * 0.5))
		_turn(_id("thigh." + s), Quaternion(f, l))
		_turn(_id("shin." + s), Quaternion(f, l * 0.4))
	var h: float = flop.get("head", 0.0)
	_turn(_id("chest"), Quaternion(f, h * 0.3))
	_turn(_id("neck"), Quaternion(f, h))


## 目の所（人形の座標、m）。座っているときは腰を落とした分だけ低い（姿勢のコマや揺れには付き合わない）
func eye_point(sitting: bool) -> Vector3:
	var e: Vector3 = EYE.get(kind, EYE["kasa"])
	if sitting:
		e.y -= _chair_drop() if act == Act.SIT else _sit_drop()
	return e * _scale


## 胸の所（世界の座標）。雪のボタンが体に飛び込む先（snow_buttons.gd）。一人称で映していなくても骨は動いている
func chest_point() -> Vector3:
	var i := _id("chest")
	if skel == null or i < 0:
		return global_position + Vector3.UP * 0.9 * _scale
	return skel.global_transform * skel.get_bone_global_pose(i).origin


# ---------------------------------------------------------------- 裾

static var _skirt_cache := {}


## 腰の骨に「裾」の骨を子として足し、腰より下の、腰の骨で動く所（着物・ローブ・ケープの裾）をそちらへ移す。
## ふだんは腰と同じに動き、座ったときだけ縦につぶす（裾が座面を突き抜けない）。
## 裾の骨は子を持たないので、縦だけつぶしても脚や胸はゆがまない
func _add_skirt(inst: Node3D) -> void:
	var hips := skel.find_bone("hips")
	if hips < 0:
		return
	var sk := skel.add_bone("skirt")
	skel.set_bone_parent(sk, hips)
	skel.set_bone_rest(sk, Transform3D.IDENTITY)
	skel.reset_bone_pose(sk)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.skin == null:
			continue
		if not _skirt_cache.has(kind):
			_skirt_cache[kind] = _skirt_mesh(mi)
		var c: Array = _skirt_cache[kind]
		if c.is_empty():
			continue
		mi.mesh = c[0]
		mi.skin = c[1]


func _skirt_mesh(mi: MeshInstance3D) -> Array:
	var skin := mi.skin.duplicate() as Skin
	var hb := -1
	for i in skin.get_bind_count():
		var n := skin.get_bind_name(i)
		if n == "hips" or (n == "" and skin.get_bind_bone(i) == skel.find_bone("hips")):
			hb = i
	if hb < 0:
		return []
	var nb := skin.get_bind_count()
	if skin.get_bind_name(hb) != "":
		skin.add_named_bind("skirt", skin.get_bind_pose(hb))
	else:
		skin.add_bind(skel.find_bone("skirt"), skin.get_bind_pose(hb))
	var to_hips := skin.get_bind_pose(hb)
	var src := mi.mesh
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var per := bones.size() / verts.size()
		for v in verts.size():
			if (to_hips * verts[v]).y < 0.0:
				for k in per:
					if bones[v * per + k] == hb:
						bones[v * per + k] = nb
		a[Mesh.ARRAY_BONES] = bones
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		out.surface_set_material(si, src.surface_get_material(si))
	return [out, skin]


# ---------------------------------------------------------------- 服の色（outfit.gd）

var _body: Node3D            # glb の人形
var _src_albedo: Texture2D   # 焼いたままの色の絵
var _dress_n := 0            # 着替えの番号（待つあいだに次の着替えが来たら、前のは捨てる）


## 服の色を替える（cols は布ごとの Color か null）。塗り直した絵ができたら差し替える（1 コマ遅れる）
func dress(cols: Array) -> void:
	outfit = cols.duplicate()
	if _body == null:
		return
	if _src_albedo == null:
		_src_albedo = Outfit.albedo(_body)
	_dress_n += 1
	Outfit.dress_into(self, _body, kind, _src_albedo, outfit, _dress_n)


## 消える前に、写した材質を外す（outfit.gd の strip）
func _exit_tree() -> void:
	if _body:
		Outfit.strip(_body)


# ---------------------------------------------------------------- 動き

func _physics_process(dt: float) -> void:
	var host := get_parent() as Node3D
	var pos := host.global_position
	var b: Basis
	if act == Act.RIDE and sled:
		b = sled.global_basis.orthonormalized()
		_yaw = b.get_euler().y
	else:
		var f := facing if facing != Vector3.ZERO else -host.global_basis.z
		f.y = 0
		if f.length() > 0.01:
			if rock_turns and act == Act.SIT and sit_stage == 2:
				# 座ったまま向きを変える: コマが進んだときだけ、見ている向きへ TURN_STEP まで回る（コマのあいだは止める）
				var fk := frame_index()
				if fk != _turn_frame:
					_turn_frame = fk
					var d := wrapf(atan2(-f.x, -f.z) - _yaw, -PI, PI)
					_yaw += clampf(d, -TURN_STEP, TURN_STEP)
			else:
				_yaw = lerp_angle(_yaw, atan2(-f.x, -f.z), 1.0 - exp(-dt * 14.0))
		b = Basis(Vector3.UP, _yaw)
	if spin_axis != Vector3.ZERO:
		var r := Basis(spin_axis.normalized(), spin)
		b = r * b
		pos = spin_at + r * (pos - spin_at)
	if rock_axis != Vector3.ZERO and rock != 0.0:
		# 向きについてくる席（ビーズクッション）では、もたれの軸も体の向きから（体の右＝前 × 上）
		var ax := Basis(Vector3.UP, _yaw) * Vector3.RIGHT if rock_turns else rock_axis.normalized()
		var r := Basis(ax, rock)
		b = r * b
		pos = rock_at + r * (pos - rock_at)
	if drum_fit != 1.0:
		b = b.scaled(Vector3.ONE * drum_fit)
	global_transform = Transform3D(b, pos)

	# 歩みは進んだ道のりで刻む（足と地面のずれを小さく）
	if _last == Vector3.INF:
		_last = pos
	var d := pos - _last
	d.y = 0
	_last = pos
	var v := d.length() / dt
	if v > 25.0:
		v = 0.0
		d = Vector3.ZERO
	_speed = lerpf(_speed, v, 1.0 - exp(-dt * 8.0))
	_vel = _vel.lerp(d / dt, 1.0 - exp(-dt * 8.0))
	_phase += TAU * d.length() / maxf(_speed / CADENCE, 0.5) / _scale

	var fi := frame_index()
	if fi != _frame and fi >= _pose_due:
		# 湿っているとコマを飛ばす（12 → 10 → 8 fps）。飛ばしたぶんは次へ持ち越し、間隔をならす
		_pose_due = _pose_due + pose_step if _pose_due + pose_step > fi else fi + pose_step
		_frame = fi
		_pose()
	_show_damp(dt)
	_hold_hands()
	_apply()
	_lantern.follow(dt, _yaw)
	_blow_breath(dt)
	_place_shapes()


## 骨の座標の空間での、世界の点
func _to_skel(world: Vector3) -> Vector3:
	return skel.global_transform.affine_inverse() * world


func _pose() -> void:
	_idle_t += lerpf(1.0, CALM_PACE, _calm) / FPS
	_boil_k += 1.0 / lerpf(1.0, BOIL_SLOW, _calm)
	_reset()
	_hold = [null, null]
	lap_line = PackedVector3Array()
	var stride := maxf(_speed / CADENCE, 0.5) / _scale
	var leg := absf(_head_of(_id("thigh.R")).y - _head_of(_id("foot.R")).y) if _id("foot.R") >= 0 else 0.5
	var amp := asin(clampf(stride / (4.0 * maxf(leg, 0.1)), 0.0, 0.7)) if _speed > 0.25 else 0.0
	if dragged and act == Act.PUSH:
		amp = 0.0   # 引きずられているときは歩かない（足は雪をすべる）
	var ph := _phase
	var bend := 0.0
	var X := Vector3.RIGHT
	var Z := Vector3.BACK
	# 着地: 宙に 2 コマ以上いたあと床に着いたら、2 コマのあいだ膝を曲げる
	if airborne:
		_air_n += 1
		_land = 0
	else:
		_land = 2 if _air_n >= 2 else maxi(_land - 1, 0)
		_air_n = 0

	match act:
		Act.RIDE:
			var sk := sack_k("out")
			if sk >= 0 and sk < 3:
				bend = _sack_draw(sk)   # 米袋をまだ取り出して広げている（立ったまま）
			else:
				# ソリに座る。腰を落とし、脚は前へ。両手はソリの縁（米袋は前の紐）
				# 裾は縦につぶして座面に広げ、脚は前へ投げ出す（足先は座面の高さ）
				# 裾は腰の骨の付け根へ向かってつぶれるので、その付け根を座面のすぐ上に。
				# 脚の付け根が腰の骨よりずっと低い人形（③）は、脚が座布団に埋もれてケープに隠れる
				var sack: bool = sled != null and sled.get("kind") == "sack"
				var half := sk == 3   # しゃがんで、腰を下ろす途中
				_hips_drop = _sit_drop() * (0.55 if half else 1.0)
				_squash = 0.55 if half else 0.12
				_update_all()
				for s in ["L", "R"]:
					var kk := _frame - _kick_frame
					if kk >= 0 and kk < 3 and s == _kick_leg:
						# 足で雪を蹴る（米袋）: 横から下へ伸ばし（0）、後ろへ蹴り（1）、引き戻す（2）
						_turn_axis("thigh." + s, X, [0.7, 0.2, 0.9][kk])
						_turn_axis("shin." + s, X, [-0.5, -0.1, -0.6][kk])
						_turn_axis("thigh." + s, Z, (0.25 if s == "R" else -0.25) * [1.0, 1.0, 0.5][kk])
						continue
					if half:
						_turn_axis("thigh." + s, X, 1.05)
						_turn_axis("shin." + s, X, -1.55)
					elif sack:
						# 米袋は低いので、膝を少し立てて足先を袋の前の縁へ（脚が見えて、座っているとわかる）
						_turn_axis("thigh." + s, X, 2.0)
						_turn_axis("shin." + s, X, -1.2)
					else:
						_turn_axis("thigh." + s, X, 1.5)
						_turn_axis("shin." + s, X, -0.25)
				bend = -lean.y * 0.3 - (0.3 if sack and not half else 0.0)   # 米袋では少し後ろへもたれる
				_turn_axis("chest", Z, -lean.x * 0.3)
				if sled and sack:
					# 米袋: 前の紐を両手で握り、少し引き寄せる
					var me: Vector3 = sled.to_local(global_position)
					_hold[0] = [sled, Vector3(-0.13, me.y + 0.16, me.z - 0.36)]
					_hold[1] = [sled, Vector3(0.13, me.y + 0.16, me.z - 0.36)]
				elif sled:
					var me: Vector3 = sled.to_local(global_position)
					_hold[0] = [sled, Vector3(-0.68, 0.5, me.z - 0.1)]
					_hold[1] = [sled, Vector3(0.68, 0.5, me.z - 0.1)]
		Act.SIT:
			if sit_stage == 1:
				# 中腰: 腰を半分落とし、膝を曲げる（ソリに乗り込むときと同じ）
				_hips_drop = _chair_drop() * 0.55
				_squash = 0.55
				_update_all()
				for s in ["L", "R"]:
					_turn_axis("thigh." + s, X, 1.05)
					_turn_axis("shin." + s, X, -1.55)
				bend = 0.25
			elif sit_stage == 2:
				bend = _drum_sprawl() if spin_axis != Vector3.ZERO else _sit_chair()
		_:
			if airborne:
				for s in ["L", "R"]:
					_turn_axis("thigh." + s, X, 0.5 if s == "L" else 0.15)
					_turn_axis("shin." + s, X, -0.9)
			elif _land > 0:
				# 着地: 膝を曲げて受け止める（2 コマ。深く → 半ば）
				var k := 1.0 if _land == 2 else 0.5
				for s in ["L", "R"]:
					_turn_axis("thigh." + s, X, 0.75 * k)
					_turn_axis("shin." + s, X, -1.3 * k)
				_hips_drop = leg * 0.5 * ((1.0 - cos(0.75 * k)) + (1.0 - cos(0.55 * k)))
				_update_all()
				bend = 0.25 * k
			elif amp > 0.0:
				for k in 2:
					var s: String = ["L", "R"][k]
					var p := ph + PI * k
					_turn_axis("thigh." + s, X, amp * sin(p))
					_turn_axis("shin." + s, X, -(0.08 + (0.45 + amp) * maxf(0.0, cos(p))))
					_turn_axis("upper_arm." + s, X, -amp * 0.8 * sin(p))
				_hips_drop = leg * (1.0 - cos(amp * absf(sin(ph)))) + 0.005
				_update_all()
				bend = 0.04 + 0.03 * minf(_speed, 6.0)
				_turn_axis("chest", Vector3.UP, 0.12 * amp * sin(ph))
			else:
				# 立ち止まり: 重心をゆっくり左右に、息で胸が少し上下。暖かい所ではゆったりと、寒い所ではふるえる
				_turn_axis("hips", Z, 0.03 * sin(_idle_t * 1.4))
				_turn_axis("chest", Z, -0.02 * sin(_idle_t * 1.4))
				bend = (0.02 + 0.01 * _calm) * sin(_idle_t * 2.2)
				if act == Act.WALK and _shiver > 0.01:
					bend += _shiver_pose()

			if act == Act.PUSH and sled and grip != Vector3.INF:
				var pts := _grip_points()
				_hold[0] = [sled, pts[0]]
				_hold[1] = [sled, pts[1]]
				for s in ["L", "R"]:
					_turn_axis("thigh." + s, X, -0.25)
					_turn_axis("shin." + s, X, -0.2)
				if effort and amp == 0.0:
					# 動かないソリを押している: 足を前後に踏ん張る
					var k := 1.0 if (_frame / 6) % 2 == 0 else -1.0
					_turn_axis("thigh.L", X, 0.15 * k)
					_turn_axis("thigh.R", X, -0.15 * k)
				bend = 0.45
				if dragged:
					# 引きずられている: 体勢が崩れている。体ごとソリへ前のめりに引かれ、片足を前へ突っ張ってかかとですべり、
					# もう片足は後ろに残って膝が折れる。左右によろけ、左手はソリを離して宙をかく（右手だけでしがみつく）。
					# ときどき膝ががくっと抜けて沈む。揺れはコマ（12 fps）で刻むので、人によってずらす（_rng の種）
					var f := _frame + int(_scale * 97.0)
					var sway := sin(f * 0.55) * 0.22 + (0.06 if f % 2 == 0 else -0.06)   # よろけ（ゆっくり）＋ 雪のでこぼこ（コマごと）
					var buckle := 1.0 if f % 14 < 3 else 0.0                           # 膝が抜ける 3 コマ
					_turn_axis("hips", X, -0.55 - 0.12 * buckle)
					_turn_axis("hips", Z, sway * 0.6)
					_turn_axis("thigh.L", X, 0.75 + 0.1 * sin(f * 1.3))
					_turn_axis("shin.L", X, -0.05)
					_turn_axis("thigh.R", X, -0.35 + 0.5 * buckle)
					_turn_axis("shin.R", X, -0.9 - 0.4 * buckle)
					_turn_axis("chest", Z, -sway)
					_turn_axis("chest", Vector3.UP, 0.25 * sin(f * 0.4))
					_hips_drop = 0.06 + 0.1 * buckle
					_update_all()
					# 左手はソリを離し、肩の上から外へ、大きな輪を描いて宙をかく
					var h := height()
					var swing := f * 0.9
					_hold[0] = [self, Vector3(-0.42 - 0.12 * cos(swing), h * 0.78 + 0.22 * sin(swing), -0.05 + 0.2 * cos(swing * 0.5))]
					bend = 0.75 + 0.15 * buckle
			elif act == Act.ROPE:
				if rope_hand != Vector3.INF:
					_hold[1] = [self, to_local(rope_hand)]
				if effort:
					bend += 0.3

	var si := sack_k("in")
	if si >= 0 and act != Act.RIDE:
		bend = _sack_stow(si)

	var em := _emote_k()
	if crouch and act != Act.RIDE and em[0] != "make_ball":
		bend += _crouch_legs(1.0) * 0.6
	if em[1] >= 0:
		bend += _emote_body(em[0], em[1])
	if em[0] != "breath" and em[0] != "oi":
		_long.emitting = false
	_turn_axis("chest", X, -bend - _damp_bend())
	_flop_limbs()

	if point != Vector3.INF:
		# 指さし: 選んだ手の腕をまっすぐ伸ばして指す（両手なら両腕で「あっち！」）。手の先には指さしの手形。
		# 選んでいなければ、指す所に近い側。ソリをつかんでいても、その手は離して指す。胸も少しそちらへ回す
		var lp := global_basis.inverse() * (point - global_position)
		var sides: Array = point_sides if not point_sides.is_empty() else [1 if lp.x >= 0.0 else -1]
		var turned := false
		for sd in sides:
			var side := "R" if sd > 0 else "L"
			var ui := _id("upper_arm." + side)
			var sh := skel.global_transform * _head_of(ui)
			var dir := (point - sh).normalized()
			if not turned:
				var local_dir := global_basis.inverse() * dir
				_turn_axis("chest", Vector3.UP, clampf(atan2(-local_dir.x, -local_dir.z), -0.8, 0.8) * 0.3 / sides.size())
				turned = true
			sh = skel.global_transform * _head_of(ui)
			dir = (point - sh).normalized()
			var reach := (_len(ui) + _len(_id("forearm." + side)) + _len(_id("hand." + side)) * 0.5) * _scale * 0.98
			_hold[1 if side == "R" else 0] = [self, to_local(sh + dir * reach)]

	if em[1] >= 0:
		_emote_arms(em[0], em[1])
	_plan_palms(em[0], em[1])
	if em[1] < 0 and waving and _hold[1] == null and hand_shapes[0] == "":
		# 右手を上げて振る。4 コマで 1 往復
		var k: float = [0.55, 0.1, -0.35, 0.1][_frame % 4]
		_aim(_id("upper_arm.R"), Vector3(0.7, 0.65, -0.15))
		_aim(_id("forearm.R"), Vector3(0.25 + k * 0.6, 1.0, -0.1))

	# 頭は見ている所へ
	var hi := _id("head")
	if hi >= 0:
		var hp := skel.global_transform * _head_of(hi)
		# 見ている所が決まっていなければ、指している所を見る（あなたは顔と指さしを別々に向けられる）
		var look := gaze if gaze != Vector3.INF else (point if point != Vector3.INF else hp + global_basis * Vector3(0, -0.05, -1))
		if spin_axis != Vector3.ZERO:
			look = hp + spin_axis * 6.0   # 乾燥機の胴の中: 顔を丸い戸の窓へ（外から顔が見える）
		# 顔の向きは相互行為の手がかり。首と頭で大きく回し、届かない分は胸も少し回す
		var ld := (skel.global_transform.basis.inverse() * (look - hp)).normalized()
		var yaw_all := atan2(-ld.x, -ld.z)
		var yaw := clampf(yaw_all, -1.3, 1.3)
		var pitch := clampf(atan2(ld.y, Vector2(ld.x, ld.z).length()), -0.9, 0.75) + bend * 0.7
		if _voice > 0:
			pitch = minf(pitch + 0.3, 0.85)
		yaw = clampf(yaw + _em_head.x, -1.4, 1.4)
		pitch = clampf(pitch + _em_head.y, -1.2, 0.95)
		_turn_axis("chest", Vector3.UP, clampf(yaw_all, -1.6, 1.6) * 0.15)
		_turn_axis("neck", Vector3.UP, yaw * 0.4)
		_turn_axis("head", Vector3.UP, yaw * 0.6)
		# うなずく向きは、首を回したあとの頭の横の軸で（横を向いたまま上下を見ても頭が傾かない）
		var right: Vector3 = (_g[hi] as Transform3D).basis.x.normalized()
		_turn(hi, Quaternion(right, pitch))
		if absf(_em_roll) > 1e-4:
			# 首をかしげる: 顔の向きの軸のまわりに傾ける
			var face: Vector3 = (_g[hi] as Transform3D).basis.z.normalized()
			_turn(hi, Quaternion(face, -_em_roll))

	# クレイアニメの揺れ: 骨ごとにわずかに。寒い所ではコマごとに形が変わり（ふるえ。寒いほど大きく）、
	# 暖かい所では、次の形へ何十コマもかけてゆっくり移る
	var bk := floori(_boil_k)
	var bw := smoothstep(0.0, 1.0, _boil_k - bk)
	var boil := BOIL * (1.0 + BOIL_COLD * _shiver) * (1.0 - DAMP_BOIL * absf(damp))
	for i in _order:
		var a := _boil_at(bk, i)
		if bw > 0.0:
			a = a.lerp(_boil_at(bk + 1, i), bw)
		_turn(i, Quaternion.from_euler(a * boil))
	_rng.seed = hash(Vector2i(_frame, get_instance_id()))

	# 腕の、伸ばし直す前の回転を覚えておく
	_arm_base.clear()
	for s in ["L", "R"]:
		for n in ["upper_arm.", "forearm.", "hand."]:
			var i := _id(n + s)
			if i >= 0:
				_arm_base[i] = _rot[i]

	if em[1] >= 0:
		_emote_breath(em[0], em[1])
	# 雪玉は、作っている途中は大きくなりながら、できたら右手に
	var ball_k: float = 0.0
	if em[0] == "make_ball" and em[1] >= 4:
		ball_k = clampf((em[1] - 4) / 12.0, 0.0, 1.0) * 0.6 + 0.4
	elif holding_ball and not (em[0] == "throw" and em[1] < BALL_BACK):
		ball_k = 1.0   # 投げたあとは、次の雪玉を袖から取るまで少し空く
	_ball.visible = ball_k > 0.0
	_ball.scale = Vector3.ONE * maxf(ball_k, 0.01)
	_place_stock(em)
	_place_roll()
	# 帯のランタン: 歩みで前後に揺れ、速さの変わり目で振られる（人形の向きの座標で、x 右・y 前）
	var acc := (_vel - _lantern_v) * FPS
	_lantern_v = _vel
	var fwd := -global_basis.z
	_lantern.step(_speed, _phase, Vector2(acc.dot(global_basis.x), acc.dot(fwd)), act == Act.RIDE or (act == Act.SIT and sit_stage > 0))

	# 声と白い息
	if _voice > 0:
		if _voice == 7:
			_puff(1.7, 1.3)
			_next_breath = _frame + 30
		_voice -= 1
	elif _frame >= _next_breath:
		_puff(1.0, 0.5)
		_next_breath = _frame + (22 if effort else 38) + _rng.randi_range(-4, 4)


## つかんでいる手は、つかんだ物に対してコマの姿勢を保つ（毎物理フレーム、腕を伸ばし直す）
func _hold_hands() -> void:
	if _hold[0] == null and _hold[1] == null:
		return
	for i in _arm_base:
		_rot[i] = _arm_base[i]
	_update_all()
	for k in 2:
		var h = _hold[k]
		if h == null or not is_instance_valid(h[0]):   # 握っていたソリが消えた（米袋を帯に戻した）ら、次のコマまで握らない
			continue
		var space: Node3D = h[0]
		_reach("L" if k == 0 else "R", _to_skel(space.to_global(h[1])), h.size() > 2 and h[2])


## つかんでいる立ち位置から、ソリの縁に置く両手の所（ソリの座標）
func _grip_points() -> Array:
	var hx: float = sled.HALF.x
	var hz: float = sled.HALF.y
	var g := grip
	var e := Vector3(clampf(g.x, -hx, hx), 0, clampf(g.z, -hz, hz))
	var inward := e - g
	inward.y = 0
	inward = inward.normalized() if inward.length() > 0.01 else Vector3.FORWARD
	var right := inward.cross(Vector3.UP)
	var pts := []
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var p := e + right * s * 0.2
		p.x = clampf(p.x, -hx, hx)
		p.z = clampf(p.z, -hz, hz)
		if p.z > hz - 0.25:
			p.y = 0.95
			p.z = 1.3
		else:
			p.y = 0.48
		pts.append(p)
	return pts


# ---------------------------------------------------------------- 足もとの影

## 足もとに、やわらかい丸い影を落とす（雪の上に立っている感じ。乗っているときはソリの台に落ちる）。
## 雪が明るく空の光も強いので、太陽の影だけでは足もとが浮いて見える。影は雪の影と同じ青み
func _make_foot_shadow() -> void:
	var r: float = FOOT_SHADOW[kind] * _scale
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.85, 1.0])
	g.colors = PackedColorArray([Color(0.08, 0.1, 0.2, 0.85), Color(0.08, 0.1, 0.2, 0.75), Color(0.08, 0.1, 0.2, 0.3), Color(0.08, 0.1, 0.2, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var d := Decal.new()
	d.size = Vector3(r * 2.0, 0.36, r * 2.0)   # 薄い箱: 足の甲より上には届かない
	d.texture_albedo = tex
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.position = Vector3(0, 0.02, 0)
	d.layers = layers   # 自分の影は、自分の体と同じ層（一人称では、しゃがんで足もとを見ても映らない）
	add_child(d)
	_foot_shade = d


# ---------------------------------------------------------------- 白い息

## 白い息は、口もとから一続きに流れて広がる綿の煙。小さく柔らかい粒を次々に出して重ね、出口では細く濃く、
## 離れるほど太く薄くほどける。体が動くと出た所に煙が残るので、ゆるく曲がる帯になる。粒の縁は毛羽立ち、
## ほつれた糸のような細い筋が出る（手芸の綿）。人の姿勢ではないので、12 コマにせずなめらかに流す。
## 色はほぼ真っ白で、少し透けて後ろが見える。光の当て方で灰色や青に沈まないよう、陰は薄い青白だけ（光を受けない塗り）
const BREATH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D cotton : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 warm : source_color = vec3(1.0, 0.995, 0.985);
uniform vec3 cool : source_color = vec3(0.88, 0.91, 0.96);
uniform vec3 sun_dir = vec3(-0.5, -0.6, -0.6);   // 光の進む向き（世界）
uniform float opacity = 0.78;                     // 少し透ける（後ろの景色がうっすら見える）
uniform float bright = 1.75;                      // 画面の明るさの圧縮（トーンマップ）のあとでも真っ白に見えるよう、1 より明るく
uniform float erode = 0.0;                        // 粒の寿命の後半で、薄い所から削れて消える強さ（白い息は 0.85。霧散する）

varying float spin;
varying float life;   // 粒の寿命のどこにいるか（0 生まれ 〜 1 消える）
varying vec2 sun2;
varying vec2 cell;   // 綿の形は 4 つ（2x2 に並べた画像）。粒ごとに選ぶ

void vertex() {
	// 板はいつもカメラを向き、大きさは粒ごとの大きさのまま。回すのは綿の形だけ（光の向きを画面に合わせるため）
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	spin = INSTANCE_CUSTOM.x;
	life = INSTANCE_CUSTOM.y;
	cell = vec2(float(INSTANCE_ID % 2), float((INSTANCE_ID / 2) % 2));
	vec3 s = (VIEW_MATRIX * vec4(-normalize(sun_dir), 0.0)).xyz;
	sun2 = length(s.xy) > 0.001 ? normalize(s.xy) : vec2(0.0, 1.0);
}

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(spin), sn = sin(spin);
	vec2 q = vec2(c * p.x - sn * p.y, sn * p.x + c * p.y) + 0.5;
	float inside = step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	vec4 t = texture(cotton, (clamp(q, 0.0, 1.0) + cell) * 0.5);
	t.a *= inside;
	// 霧散: 寿命の後半、薄い毛羽から先に削れ、芯もまばらな筋になって消える
	float e = erode * smoothstep(0.3, 1.0, life);
	t.a = clamp((t.a - e) / max(1.0 - e, 0.05), 0.0, 1.0);
	// 太陽の側ほど明るい。陰は薄い青白まで（灰色や青に沈ませない）
	float side = dot(normalize(p * vec2(1.0, -1.0) + 1e-4), sun2) * smoothstep(0.0, 0.35, length(p));
	float lit = clamp(0.78 + 0.25 * side - 0.18 * t.r, 0.0, 1.0);
	// 縁（薄くなりかけの所）だけ、ごく薄い青白のふち: 白い雪の前でも煙の形が分かり、毛羽の縁が見える
	float rim = smoothstep(0.06, 0.3, t.a) * (1.0 - smoothstep(0.3, 0.7, t.a));
	vec3 col = mix(mix(cool, warm, lit), cool * 0.68, rim * 0.5);
	ALBEDO = col * bright;
	ALPHA = t.a * COLOR.a * opacity;
}
"""

static var _cotton: ImageTexture


## 綿のひとかたまりの形（透明度）と厚み（赤）。外の画像は使わない。
## 本体はいくつかの丸いふくらみを重ねたでこぼこの塊、縁はくねった細かい繊維がほつれる
static func cotton_texture() -> Texture2D:
	if _cotton:
		return _cotton
	var n := 160
	var atlas := Image.create(n * 2, n * 2, false, Image.FORMAT_RGBA8)
	for k in 4:
		atlas.blit_rect(_cotton_tuft(n, k), Rect2i(0, 0, n, n), Vector2i((k % 2) * n, (k / 2) * n))
	atlas.generate_mipmaps()
	_cotton = ImageTexture.create_from_image(atlas)
	return _cotton


static func _cotton_tuft(n: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21 + seed * 17
	# 芯: 少しだけでこぼこした丸。重ねたときに一続きに見えるよう、縁へなだらかに薄くなる
	var lumps := []
	for i in rng.randi_range(3, 5):
		lumps.append([Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.15, 0.15)), rng.randf_range(0.28, 0.42)])
	var warp := FastNoiseLite.new()
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.frequency = 2.2
	warp.seed = 9 + seed
	var dens := FastNoiseLite.new()
	dens.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dens.frequency = 4.0
	dens.fractal_octaves = 3
	dens.seed = 5 + seed
	var fib := FastNoiseLite.new()
	fib.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fib.frequency = 1.0
	fib.fractal_octaves = 2
	fib.seed = 13 + seed
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var w := p + 0.12 * Vector2(warp.get_noise_2d(p.x, p.y), warp.get_noise_2d(p.x + 30.0, p.y))
			var f := 0.0
			for l in lumps:
				var d: float = (w - l[0]).length() / l[1]
				f = maxf(f, exp(-d * d * 1.0))
			var dn := 0.75 + 0.25 * dens.get_noise_2d(p.x, p.y)
			var body := f * dn
			# 毛羽とほつれた糸: 芯のまわりに、外へ向かってくねる細い筋（角度に沿って細かく、半径に沿って長く）
			var ang := atan2(w.y, w.x)
			var r := w.length()
			var strand := 0.5 + 0.5 * fib.get_noise_2d(ang * 9.0, r * 3.0 + seed * 7.0)
			var fringe := pow(strand, 6.0) * smoothstep(0.95, 0.35, r) * smoothstep(0.15, 0.45, r)
			var alpha := clampf(maxf(body, fringe * 0.55) * (1.0 - smoothstep(0.85, 1.0, p.length())), 0.0, 1.0)
			img.set_pixel(x, y, Color(body, 1, 1, alpha))
	return img


## 息の煙の出口ごとの出し方: [1 秒あたりの粒, 粒の寿命 (s), 大きさ, はじめの速さ (m/s)]
## 粒は出口で小さく（大きさの 2 割）、昇りながら寿命の終わりに 3 倍ほどまで広がる。粒どうしが重なる速さで出すので、一続きの煙になる
const STREAMS := {
	"small": [26.0, 2.1, 0.85, 0.42],   # ふだんの息: 0.6 秒ほど、細く短く
	"big": [30.0, 2.5, 1.15, 0.62],     # 声の息: 大きく勢いよく
	"long": [24.0, 2.7, 1.35, 0.55],    # B の長い息・おーい: 吐いているあいだ出し続ける
}


func _make_breath() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.36, 0.36)
	var sh := Shader.new()
	sh.code = BREATH_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("cotton", cotton_texture())
	mat.set_shader_parameter("erode", 0.85)
	var sun := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	if not sun.is_empty():
		mat.set_shader_parameter("sun_dir", -(sun[0] as Node3D).global_basis.z)
	quad.material = mat
	_breath_mat = mat   # 人形ごとの材質（濃さを寒さで変える）
	var grow := Curve.new()   # 出口で細く、昇りながら太く広がる
	grow.max_value = 4.0
	grow.add_point(Vector2(0.0, 0.2))
	grow.add_point(Vector2(0.25, 0.7))
	grow.add_point(Vector2(1.0, 2.9))
	var fade := Gradient.new()   # 出口で濃く、広がるほど薄く透けて、消える
	fade.offsets = PackedFloat32Array([0.0, 0.05, 0.25, 0.5, 0.75, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0)])
	for key in STREAMS:
		var spec: Array = STREAMS[key]
		var e := CPUParticles3D.new()
		e.emitting = false
		e.one_shot = false
		e.local_coords = false   # 出た煙はその場に残る: 体が動くと、煙がゆるく曲がった帯になる
		e.lifetime = spec[1]
		e.amount = int(ceil(spec[0] * spec[1]))
		e.explosiveness = 0.0
		e.randomness = 0.0          # 出す間隔はそろえる（ばらつかせると粒が寄り集まって、かたまりに分かれる）
		e.lifetime_randomness = 0.2
		e.direction = Vector3(0, 0.12, -1)
		e.spread = 5.0             # 出口では細く
		e.initial_velocity_min = spec[3] * 0.85
		e.initial_velocity_max = spec[3] * 1.15
		e.damping_min = 0.3        # 口から離れると前へ進む勢いが落ち、たまって広がる
		e.damping_max = 0.45
		e.gravity = Vector3(0, 0.5, 0)   # 暖かい息なので、前へ少し伸びてから上へ昇りながら広がる（吐く勢いの落ちより強く）
		e.angle_min = 0.0
		e.angle_max = 360.0
		e.angular_velocity_min = -14.0
		e.angular_velocity_max = 14.0
		_scale_base[key] = [spec[2] * 0.85, spec[2] * 1.15]
		e.scale_amount_min = spec[2] * 0.85
		e.scale_amount_max = spec[2] * 1.15
		e.scale_amount_curve = grow
		e.color_ramp = fade
		e.mesh = quad
		e.layers = 1 | layers   # 息は誰の画面にも映す（自分の息は、自分の体の層にも入れて右下の小窓に映す）
		e.position = MOUTH[kind]
		att.add_child(e)
		_streams[key] = e
	_long = _streams["long"]


## 息を吐く。size 1 がふだんの小さな息、声のときは大きく。吐く長さのあいだ口から煙を出し続ける（出た煙は流れて消える）。
## speed は吐く勢い
func _puff(size: float, speed: float) -> void:
	var key := "big" if size > 1.2 else "small"
	var e: CPUParticles3D = _streams[key]
	var spec: Array = STREAMS[key]
	var v: float = spec[3] * clampf(0.6 + 0.4 * speed, 0.6, 1.6)
	e.initial_velocity_min = v * 0.85
	e.initial_velocity_max = v * 1.15
	var k := clampf(size / 1.6, 0.8, 1.3) if key == "big" else 1.0   # 声が大きいほど、煙も太く
	_scale_base[key] = [spec[2] * 0.85 * k, spec[2] * 1.15 * k]
	# ふだん 0.6 秒、声 0.8〜0.85 秒。寒いほど長く吐く（暖かいと短い）
	_blow[key] = maxf(_blow[key], (0.35 + 0.25 * size) * (0.7 + 0.35 * maxf(_cold, 0.0)))


## 吐いている残りを減らし、残りのあいだだけ煙を出す（なめらかに。姿勢のコマとは関係なく）。
## 寒さ（口もとの気温、temperature.gd）で見え方を変える: 暖かい所では出さない。寒いほど煙が大きく、濃く、長く吐く。
## 寒さは 0.25 秒おきに引き、2 秒ほどの時定数でなじむ（ロッジを出入りしても急に切り替わらない）。
## 同じ気温から、体のふるえ（_shiver）と、暖かさの落ち着き（_calm）も決める（どちらも同じ速さでなじむ）
func _blow_breath(dt: float) -> void:
	_cold_t -= dt
	if _cold_t <= 0.0:
		_cold_t = 0.25
		var temp := get_node_or_null("/root/Temperature")
		var c: float = temp.at(_long.global_position) if temp else 0.0
		_cold_want = Temp.breath_of(c) if temp else 1.0
		_shiver_want = Temp.shiver_of(c) if temp else 0.0
		_calm_want = Temp.calm_of(c) if temp else 0.0
		if _cold < 0.0:
			_cold = _cold_want   # はじめは、その場の寒さから
			_shiver = _shiver_want
			_calm = _calm_want
	var k := 1.0 - exp(-dt / 2.0)
	_cold = lerpf(_cold, _cold_want, k)
	_shiver = lerpf(_shiver, _shiver_want, k)
	_calm = lerpf(_calm, _calm_want, k)
	var seen := _cold > 0.04
	var size := 0.7 + 0.35 * _cold
	_breath_mat.set_shader_parameter("opacity", 0.78 * clampf(_cold, 0.0, 1.25))   # 暖かくなるにつれて薄れ、消える
	for key in _streams:
		var e: CPUParticles3D = _streams[key]
		e.scale_amount_min = _scale_base[key][0] * size
		e.scale_amount_max = _scale_base[key][1] * size
		if key in _blow:
			_blow[key] = maxf(0.0, _blow[key] - dt)
			e.emitting = _blow[key] > 0.0 and seen
		elif not seen:
			e.emitting = false   # 長い息も、暖かい所では白くならない


const Temp := preload("res://temperature.gd")
const BOIL_SLOW := 30.0       # いちばん暖かい所で、揺れが次の形へ移るのにかけるコマ数（寒い・ふつうの所では毎コマ）
const BOIL_COLD := 0.8        # いちばん寒い所で、揺れがこれだけ大きくなる（割合）
const CALM_PACE := 0.4        # いちばん暖かい所での、立ち止まりの揺れ（重心と胸）の速さ（ふつうを 1 として）


## 揺れの k 番目の形の、骨 i の向き（-1 〜 1。人形ごとに違う）
func _boil_at(k: int, i: int) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector3i(k, i, get_instance_id()))
	return Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1))


## 寒さのふるえ（立ち止まっているとき）: 背を少し丸めて首をすくめ、腕を体に寄せて、肘を曲げた手を胸の前へ。
## 体はコマごとに小刻みにふるえる。強さは _shiver。背を丸める角を返す
func _shiver_pose() -> float:
	var s := _shiver
	var k: float = [1.0, -0.7, 0.5, -1.0, 0.8, -0.4][_frame % 6]
	_turn_axis("hips", Vector3.UP, 0.03 * s * k)
	_turn_axis("chest", Vector3.BACK, 0.035 * s * k)
	_turn_axis("neck", Vector3.RIGHT, -0.18 * s)
	for side in ["L", "R"]:
		var x := -1.0 if side == "L" else 1.0
		_aim_toward(_id("upper_arm." + side), Vector3(0.1 * x, -1.0, -0.35), 0.8 * s)
		_aim_toward(_id("forearm." + side), Vector3(-0.6 * x, 0.35, -1.0), 0.75 * s)
	return 0.1 * s


## 骨の向きを、いまの向きから dir のほうへ w（0 〜 1）だけ回す
func _aim_toward(i: int, dir: Vector3, w: float) -> void:
	if i < 0:
		return
	var y: Vector3 = (_g[i] as Transform3D).basis.y.normalized()
	_aim(i, y.slerp(dir.normalized(), clampf(w, 0.0, 1.0)))


# ---------------------------------------------------------------- 湿り気（damp.gd）

const DAMP_SHADER := preload("res://person/paper_damp.gdshader")
const DAMP_FOLLOW := 1.5      # 見た目の湿り気が値に追いつく速さ（1/s）。暖炉でじわっと乾き、雪玉でさっと濡れる見え方に
const DAMP_SLUMP := 0.22      # びしょびしょで、胸がこれだけ前へうなだれる (rad)
const DAMP_PROUD := 0.07      # パリパリで、胸がこれだけ起きる (rad)
const DAMP_NECK := 0.22       # びしょびしょで、首がこれだけ下がる (rad)
const DAMP_ARMS := 0.35       # びしょびしょで、腕がこれだけ下へ垂れる（下へ向ける割合）
const DAMP_BOIL := 0.4        # 湿ってもパリッとしても、クレイアニメの揺れがこれだけ小さくなる（湿ると重く、張ると締まる）


## 人形の材質（焼いた色の絵と法線の絵）を、湿り気の見える紙の材質に替える。人ごとにシミの所を変える
func _make_damp(inst: Node3D) -> void:
	var seed := float(get_instance_id() % 997) * 0.173
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = DAMP_SHADER
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("top", TOP[kind])
			sm.set_shader_parameter("seed", seed)
			mi.set_surface_override_material(s, sm)
			_damp_mats.append(sm)


## 材質に湿り気を入れる（なめらかに追う。0.004 より動いたか、追いついたときだけ入れ直す）
func _show_damp(dt: float) -> void:
	var want := clampf(damp, -1.0, 1.0)
	var now := want if _damp_shown == INF else lerpf(_damp_shown, want, 1.0 - exp(-dt * DAMP_FOLLOW))
	if absf(want - now) < 0.003:
		now = want
	_damp_shown = now
	if absf(now - _damp_put) < 0.004 and not (now == want and now != _damp_put):
		return
	_damp_put = now
	for sm in _damp_mats:
		sm.set_shader_parameter("wet", maxf(-now, 0.0))
		sm.set_shader_parameter("crisp", maxf(now, 0.0))


## 湿り気の姿勢: 湿るほど胸がうなだれ、首が下がり、腕が垂れる。パリッとすると胸が起きる。返り値は胸を前へ曲げる量
func _damp_bend() -> float:
	var w := maxf(-_damp_now(), 0.0)
	var c := maxf(_damp_now(), 0.0)
	if w > 0.01:
		_turn_axis("neck", Vector3.RIGHT, -DAMP_NECK * w)
		for side in ["L", "R"]:
			var x := -1.0 if side == "L" else 1.0
			_aim_toward(_id("upper_arm." + side), Vector3(0.12 * x, -1.0, -0.1), DAMP_ARMS * w)
			_aim_toward(_id("forearm." + side), Vector3(0.05 * x, -1.0, -0.2), DAMP_ARMS * w)
	return DAMP_SLUMP * w - DAMP_PROUD * c


func _damp_now() -> float:
	return damp if _damp_shown == INF else _damp_shown


# ---------------------------------------------------------------- 身ぶり（emotes.gd）
# どれも「ため → 解放」。ためは短く小さく、解放で大きく。形はコマごとに決め、コマの間は止める。
# 向きは骨の座標の空間で、右手側（R）で書く。左手は x を裏返す

## emotes.gd の KINDS と同じ長さ（コマ）。0 は終わりを持ち主が決める
const EMOTE_FRAMES := {
	"high_five": 12, "shake": 24, "whiff": 12, "breath": 0, "make_ball": 22, "windup": 0, "throw": 7,
	"hit": 16, "clap": 16, "wa": 14, "un": 7, "nn": 14, "huh": 16, "oi": 18, "eat": 16,
}
## 腕を使う身ぶり。このあいだは手の形を出さない
const ARM_EMOTES := ["high_five", "shake", "whiff", "clap", "make_ball", "windup", "throw", "hit", "eat"]


## いまの身ぶりと、始まってからのコマ数（このコマ）。終わっていたら消す
func _emote_k() -> Array:
	_em_head = Vector2.ZERO
	_em_roll = 0.0
	if emote.is_empty():
		return ["", -1]
	var k := _frame - int(emote.frame)
	var n: int = EMOTE_FRAMES.get(emote.kind, 12)
	if emote.has("until") and _frame >= int(emote.until) + 8:
		n = maxi(1, k)
	if n > 0 and k >= n:
		emote = {}
		return ["", -1]
	if k < 0:
		return ["", -1]
	return [emote.kind, k]


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## しゃがむ（s 0 立つ〜1 しゃがみきる）。腰を落とし、膝を曲げる。返り値は胸を前へ曲げる量
func _crouch_legs(s: float) -> float:
	var X := Vector3.RIGHT
	var leg := absf(_head_of(_id("thigh.R")).y - _head_of(_id("foot.R")).y) if _id("foot.R") >= 0 else 0.5
	_hips_drop = leg * 0.42 * s
	_update_all()
	for side in ["L", "R"]:
		_turn_axis("thigh." + side, X, 1.25 * s)
		_turn_axis("shin." + side, X, -1.7 * s)
	return 0.5 * s


const INHALE := 5            # 吐く前に短く吸うコマ


## 吐く息の胸のふくらみ（0 ふだん〜1 吸いきった）。押した瞬間に短く吸い、押しているあいだゆっくり吐き、離すと戻る。
## ended は離したか、until_k は離したコマ（始まりから）
static func exhale_curve(k: int, ended: bool, until_k: int) -> float:
	if k < INHALE:
		return _ease(k / float(INHALE - 1))
	var b := 1.0 - 0.6 * clampf((k - INHALE) / 60.0, 0.0, 1.0)
	if ended and k >= until_k:
		b *= 1.0 - _ease((k - until_k) / 6.0)
	return b


func _exhale_now(k: int) -> float:
	return exhale_curve(k, emote.has("until"), int(emote.get("until", 0)) - int(emote.get("frame", 0)))


## 腰・脚・胸のひねり。返り値は胸を前へ曲げる量に足す。頭の向きは _em_head に
func _emote_body(kind_: String, k: int) -> float:
	var X := Vector3.RIGHT
	match kind_:
		"breath":
			# 吸うと胸がそり、頭が上がる。吐くあいだ、少しずつ戻る
			var s := _exhale_now(k)
			_em_head.y = 0.38 * s
			return -0.2 * s
		"make_ball":
			# しゃがむ → 両手で雪をぽんぽん → 立つ
			var s := _ease(k / 4.0) if k < 16 else (1.0 if crouch else 1.0 - _ease((k - 16) / 5.0))
			_em_head.y = -0.35 * s
			return _crouch_legs(s)
		"shake":
			# 握手: 少し前へかがみ、相手を見る
			_em_head.y = -0.08
			return 0.12
		"high_five", "whiff":
			var swing := k >= (2 if kind_ == "whiff" else 3)
			# 胸のひねり: 振る手の側へ（両手なら、ひねらない）
			var tw := 0.0
			if kind_ == "whiff":
				tw = float(emote.get("side", 1))
			elif emote.has("grips") and emote.grips.size() == 1:
				tw = float(emote.grips[0][0])
			if k < 7 and tw != 0.0:
				_turn_axis("chest", Vector3.UP, (0.3 if swing else -0.25) * tw)
			if kind_ == "whiff" and k >= 2 and k < 8:
				# 空振り: 振った勢いで前へよろける
				_turn_axis("thigh.L", X, 0.35)
				_turn_axis("shin.L", X, -0.3)
				_em_head.y = -0.2
				return 0.32
			if kind_ == "whiff" and k >= 8:
				_em_head.x = [0.25, -0.25, 0.15, 0.0][k - 8]   # 首をかしげる
			return 0.1 if swing else -0.05
		"windup":
			_turn_axis("chest", Vector3.UP, -0.4)
			_turn_axis("thigh.R", X, -0.2)
			_turn_axis("thigh.L", X, 0.2)
			return -0.1
		"throw":
			var f: float = [1.0, 1.0, 0.8, 0.5, 0.3, 0.15, 0.0][k]
			_turn_axis("chest", Vector3.UP, 0.4 * f)
			_turn_axis("thigh.L", X, 0.3 * f)
			_turn_axis("thigh.R", X, -0.25 * f)
			return 0.3 * f
		"hit":
			# のけぞる: 当たった向きへ胸が倒れ、片足がうしろへ。そのあと首をぶるぶる振って雪を払う
			var d := Vector3.BACK
			if emote.has("dir"):
				d = skel.global_transform.basis.inverse() * (emote.dir as Vector3)
				d.y = 0
				d = d.normalized() if d.length() > 0.01 else Vector3.BACK
			var f: float = [0.55, 0.6, 0.5, 0.45, 0.4, 0.35, 0.3, 0.2, 0.12, 0.08, 0.05, 0.03, 0.0, 0.0, 0.0, 0.0][k]
			if f > 0.0:
				_turn(_id("chest"), Quaternion(Vector3.UP.cross(d).normalized(), f))
			if k < 8:
				_turn_axis("thigh.R", X, -0.35 * f / 0.6)
				_em_head.y = 0.5 * f / 0.6
			elif k < 14:
				_em_head.x = 0.4 if k % 2 == 0 else -0.4
			return 0.0
		"wa":
			if k < 2:
				_em_head.y = -0.15
				return 0.1
			_em_head.y = 0.4 * (1.0 - _ease((k - 8) / 6.0))
			return -0.12 * (1.0 - _ease((k - 8) / 6.0))
		"un":
			_em_head.y = [-0.2, -0.45, -0.45, -0.2, -0.05, 0.0, 0.0][k]
		"nn":
			_em_head.x = [0.35, 0.35, -0.35, -0.35, 0.35, 0.35, -0.3, -0.3, 0.2, 0.2, -0.1, -0.1, 0.0, 0.0][k]
			_em_head.y = -0.08
		"eat":
			# ひと口: 料理を見下ろして口へ運び（0〜4）、もぐもぐと 2 回うなずくように噛んで（5〜11）、顔を上げる
			_em_head.y = [-0.18, -0.24, -0.2, -0.12, -0.05, -0.1, 0.0, -0.1, 0.0, -0.08, 0.0, 0.02, 0.04, 0.03, 0.01, 0.0][k]
			return [0.04, 0.06, 0.05, 0.03, 0.0, 0.03, 0.0, 0.03, 0.0, 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0][k]
		"oi":
			# 呼ぶ: 小さく息を吸ってかがみ（ため）、胸を張って顔を上げ、遠くへ声を届ける
			if k < 2:
				_em_head.y = -0.12
				return 0.12
			_em_head.y = 0.22 if k < 15 else 0.08
			return -0.12 if k < 15 else -0.04
		"huh":
			# 首をかしげる: 小さく引いて（ため）、ことんと横へ傾けて止め、ゆっくり戻す。肩も少しすくめる
			_em_roll = [-0.08, -0.08, 0.38, 0.45, 0.45, 0.45, 0.45, 0.45, 0.45, 0.42, 0.38, 0.3, 0.2, 0.12, 0.05, 0.0][k]
			_em_head.y = 0.06 if k >= 2 else 0.0
			_turn_axis("chest", Vector3.BACK, -_em_roll * 0.15)
		"clap":
			_em_head.y = 0.05
			return 0.05
	return 0.0


## 腕の向きを決める（右手側で書いた向き。左は x を裏返す）。その手のつかみは外す
func _arm(side: String, up_dir: Vector3, fore_dir: Vector3) -> void:
	var m := Vector3(-1, 1, 1) if side == "L" else Vector3.ONE
	_hold[0 if side == "L" else 1] = null
	_aim(_id("upper_arm." + side), up_dir * m)
	_aim(_id("forearm." + side), fore_dir * m)


## 手を、骨の座標の空間の所へ伸ばす（その手のつかみは外す）
func _hand_to(side: String, target: Vector3) -> void:
	_hold[0 if side == "L" else 1] = null
	_reach(side, target)


func _emote_arms(kind_: String, k: int) -> void:
	# 手を伸ばす所は、肩の所と腕の長さから決める（3 体で腕の長さがちがう）
	var sh := (_head_of(_id("upper_arm.L")) + _head_of(_id("upper_arm.R"))) * 0.5
	var reach := _len(_id("upper_arm.R")) + _len(_id("forearm.R"))
	var head := _head_of(_id("head")) if _id("head") >= 0 else sh + Vector3(0, 0.1, 0)
	match kind_:
		"high_five":
			for gr in emote.get("grips", [[1, Vector3.INF]]):
				var side := "R" if gr[0] > 0 else "L"
				if k < 3:
					# ため: 肘ごと大きくうしろへ引く（3 コマ）
					_arm(side, Vector3(0.7, 0.6, 0.6), Vector3(0.35, 1.0, 0.75))
				elif k < 6 and gr[1] != Vector3.INF:
					_hold[0 if side == "L" else 1] = [self, to_local(gr[1])]   # 叩きつける: 手が合う所（相手と同じ所）
				else:
					var f := clampf((k - 6) / 4.0, 0.0, 1.0)
					_arm(side, Vector3(0.4, 0.6 - 0.9 * f, -0.7), Vector3(0.25, 0.3 - 1.1 * f, -0.9))
		"shake":
			# 握手: 手を差し出し（2 コマ）、重ねる所で手のひらを合わせ、二人一緒に 3 回上下に振り、離して下ろす。
			# 重ねる所は配り役が決める（二人の手のひらがみな平行で、ぴったり重なる）
			for gr in emote.get("grips", []):
				var side := "R" if gr[0] > 0 else "L"
				var at: Vector3 = gr[1]
				if k < 2:
					_hold[0 if side == "L" else 1] = [self, to_local(global_position.lerp(at, 0.5) + Vector3.UP * (at.y - global_position.y) * 0.5)]
				elif k < 20:
					_hold[0 if side == "L" else 1] = [self, to_local(at + Vector3.UP * Palm.shake_pump(k))]
				else:
					_arm(side, Vector3(0.2, -1.0, -0.25), Vector3(0.1, -1.0, -0.35))
		"whiff":
			var side := "R" if int(emote.get("side", 1)) > 0 else "L"
			if k < 2:
				_arm(side, Vector3(0.45, 0.9, 0.45), Vector3(0.25, 1.0, 0.65))
			elif k < 4:
				_arm(side, Vector3(0.1, 0.1, -1.0), Vector3(-0.15, -0.5, -1.0))   # 何もない所を振り抜く
			else:
				_arm(side, Vector3(-0.05, -0.8, -0.5), Vector3(-0.1, -0.9, -0.4))
		"breath":
			# 吸うと両腕が横へ開いて上がり、吐くとゆっくり下りる
			var s := _exhale_now(k)
			for side in ["L", "R"]:
				_arm(side, Vector3(0.6 + 0.2 * s, -0.75 + 0.85 * s, -0.15), Vector3(0.55 + 0.25 * s, -0.6 + 0.9 * s, -0.25))
		"make_ball":
			if k >= 4 and k < 16:
				# 足もとの前で、両手で雪をぽんぽんと丸める（2 コマごとに上下を入れ替える）
				var up := 0.06 if (k / 2) % 2 == 0 else 0.0
				var base := sh + Vector3(0, -0.8, -0.5) * reach
				_hand_to("R", base + Vector3(0.07, up, 0) * reach * 2.5)
				_hand_to("L", base + Vector3(-0.07, 0.06 - up, 0) * reach * 2.5)
			elif k >= 16:
				_arm("R", Vector3(0.25, -0.6, -0.6), Vector3(0.1, 0.1, -1.0))   # できた玉を胸の前に持つ
		"windup":
			_arm("R", Vector3(0.55, 0.55, 0.75), Vector3(0.2, 1.0, 0.45))
			_arm("L", Vector3(0.2, 0.25, -1.0), Vector3(0.1, 0.3, -1.0))   # 左手で狙う先を指す
		"throw":
			if k == 0:
				_arm("R", Vector3(0.25, 0.5, -1.0), Vector3(0.1, 0.35, -1.0))
			elif k < 3:
				_arm("R", Vector3(-0.1, -0.2, -1.0), Vector3(-0.25, -0.6, -0.8))   # 振り抜く
			_arm("L", Vector3(0.3, -0.9, 0.2), Vector3(0.2, -1.0, 0.1))
		"hit":
			if k < 8:
				# 両手がぱっと上がる（痛いのではなく、びっくりして楽しい）
				_arm("R", Vector3(0.8, 0.6, 0.15), Vector3(0.6, 1.0, 0.2))
				_arm("L", Vector3(0.8, 0.5, 0.25), Vector3(0.7, 0.9, 0.1))
			elif k < 14:
				for side in ["L", "R"]:
					_arm(side, Vector3(0.55, -0.6, 0.1), Vector3(0.3, -0.4, -0.5))   # 雪を払う
		"clap":
			# 4 回。4 コマで 1 回: 開く → 寄せる → 合わせる（ぽふ）→ 少し開く
			var gap: float = [0.32, 0.14, 0.015, 0.2][k % 4]
			var at := sh + Vector3(0, -0.25, -0.75) * reach
			_hand_to("R", at + Vector3(gap * 0.5, 0, 0) * reach * 2.5)
			_hand_to("L", at + Vector3(-gap * 0.5, 0, 0) * reach * 2.5)
		"wa":
			if k < 2:
				for side in ["L", "R"]:
					_arm(side, Vector3(0.2, -1.0, -0.2), Vector3(0.0, -0.6, -0.8))
			elif k < 11:
				for side in ["L", "R"]:
					_arm(side, Vector3(0.75, 0.3, -0.35), Vector3(0.55, 0.85, -0.3))   # 両手を開いて上へ
		"eat":
			# 右手（料理を持つ手）を口の前へ運び、噛むあいだそこに置き、下ろす。口の所は頭の骨と腕の長さから決めるので、
			# 7 体（頭の大きさ・腕の長さがちがう）のどれでも口の前に来る
			var arm_r := _len(_id("upper_arm.R")) + _len(_id("forearm.R"))
			var mouth := head + Vector3(0.03, -0.1, -0.42) * arm_r
			var low := sh + Vector3(0.18, -0.35, -0.55) * arm_r   # 胸の前（持っているときの所）
			var f: float = [0.0, 0.45, 0.85, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.7, 0.35, 0.1, 0.0][k]
			_hand_to("R", low.lerp(mouth, f))
		"oi":
			if k >= 1 and k < 16:
				# 空いた手を口の横に当てて、メガホンに（高い片手のひらで場所を示しながら呼べる）
				var free := 0
				for sd in [1, -1]:
					if free == 0 and hand_shapes[0 if sd > 0 else 1] == "" and not (point != Vector3.INF and (sd in point_sides or point_sides.is_empty())):
						free = sd
				if free != 0:
					var arm_r := _len(_id("upper_arm.R")) + _len(_id("forearm.R"))
					_hand_to("R" if free > 0 else "L", head + Vector3(0.16 * float(free), -0.06, -0.55) * arm_r)
		"huh":
			if k >= 2 and k < 12:
				# 肩をすくめて、両の前腕を少し外へ開く（さあ？の手）
				for side in ["L", "R"]:
					_arm(side, Vector3(0.45, -0.85, -0.1), Vector3(0.75, 0.15, -0.55))
		"nn":
			if k < 12:
				# 顔の前で手を横に振る（いやいや、ちがうの手）
				var x := 0.09 if (k / 2) % 2 == 0 else -0.09
				_hand_to("R", head + Vector3(x * reach * 2.5, -0.05, -0.6 * reach))


## 身ぶりの白い息。深呼吸は吐きはじめに長い息、声は声に合わせて大きな息
func _emote_breath(kind_: String, k: int) -> void:
	match kind_:
		"breath":
			# 短く吸ったあと、押しているあいだ吐き続ける（離したら止める）
			var stop: bool = emote.has("until") and _frame >= int(emote.until)
			_long.emitting = k >= INHALE and not stop
			_next_breath = _frame + 40
		"wa":
			if k == 2:
				_puff(1.8, 1.4)
				_next_breath = _frame + 30
		"un":
			if k == 0:
				_puff(1.15, 0.6)
				_next_breath = _frame + 24
		"huh":
			if k == 2:
				_puff(1.15, 0.6)
				_next_breath = _frame + 24
		"eat":
			# 最後のひと口を飲み込んだら、ほっと温かい息（寒い所では白く見える）
			if k == 13 and emote.get("last", false):
				_puff(1.5, 1.1)
				_next_breath = _frame + 30
		"oi":
			# 声を伸ばすあいだ、大きな白い息を吐き続ける
			if k == 2:
				_puff(1.9, 1.6)
			_long.emitting = k >= 2 and k < 15
			_next_breath = _frame + 30
		"nn":
			if k == 0 or k == 6:
				_puff(1.2, 0.7)
				_next_breath = _frame + 24
		"hit":
			if k == 0:
				_puff(1.3, 0.9)


## 右手の雪玉（ふだんは隠す）
func _make_ball() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "hand.R"
	skel.add_child(att)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.05, 0) / _scale
	att.add_child(pivot)
	var m := MeshInstance3D.new()
	m.mesh = ball_mesh()
	m.material_override = ball_material()
	m.scale = Vector3.ONE / _scale
	m.layers = layers
	pivot.add_child(m)
	_ball = pivot
	_ball.visible = false


## 左の袖の雪玉のストック: 前腕の外側（体の横から見える側）に、肘から手首へ帯を縫い付ける。
## 文字なしで数が分かり、玉のない縫い目で、あといくつ持てるかも分かる。ほかの人からも、右下の自分の小窓からも見える
func _make_stock() -> void:
	var fo := _id("forearm.L")
	if fo < 0:
		return
	var at := BoneAttachment3D.new()
	at.bone_name = "forearm.L"
	skel.add_child(at)
	var spec: Array = SLEEVE_STOCK.get(kind, SLEEVE_STOCK["kasa"])
	var rest := skel.get_bone_global_rest(fo)
	var along := Vector3.UP   # 骨の y が肘から手首へ
	var out := rest.basis.inverse() * Vector3.LEFT   # 人形の左（-x）を骨の座標へ。腕に沿う分を除いて、腕の外側
	out = (out - along * out.dot(along)).normalized()
	var length: float = _len(fo) * _scale * (float(spec[1]) - float(spec[0]))
	_stock = stock_strip(length, layers)
	_stock.transform = Transform3D(Basis(along.cross(out), along, out), along * _len(fo) * float(spec[0]) + out * float(spec[2]) / _scale)
	_stock.scale = Vector3.ONE / _scale
	at.add_child(_stock)
	_stock.visible = false


## 雪玉のストックをコマごとに。投げた直後は、次に手に持つ分がまだ袖にある（数が飛ばないよう）
func _place_stock(em: Array) -> void:
	if _stock == null:
		return
	var n := sleeve_balls
	if holding_ball and em[0] == "throw" and em[1] < BALL_BACK:
		n += 1
	_stock.visible = n > 0 or holding_ball
	stock_count(_stock, n)


## 袖に縫い付けた雪玉のストック（人形の袖と一人称の袖口で同じもの）。藍のフェルトの細い帯に赤い糸を縫い、玉の所は糸が雪玉の中を通る。
## 玉のない所（5 つまでの空き）は、なみ縫いの目だけ。帯は +y 向きに length (m)、表は +z。数は stock_count で
static func stock_strip(length: float, layers_: int) -> Node3D:
	var root := Node3D.new()
	var step := length / 5.0
	var r := step * 0.42
	var felt := Look.felt(STOCK_NAVY, 6.0)
	var red := Look.felt(STOCK_RED, 4.0)
	var bm := BoxMesh.new()
	bm.size = Vector3(r * 2.3, length + step * 0.25, r * 0.22)
	var band := MeshInstance3D.new()
	band.mesh = bm
	band.material_override = felt
	band.position = Vector3(0, length * 0.5, 0)
	band.layers = layers_
	root.add_child(band)
	var through := BoxMesh.new()   # 玉を通る糸（玉と玉のあいだに見える）
	through.size = Vector3(r * 0.22, step, r * 0.18)
	var stitch := BoxMesh.new()    # 空きのなみ縫いの目
	stitch.size = Vector3(r * 0.24, step * 0.5, r * 0.2)
	for i in 5:
		var y := step * (i + 0.5)
		var t := MeshInstance3D.new()
		t.name = "t%d" % i
		t.mesh = through
		t.material_override = red
		t.position = Vector3(0, y, r * 0.15)
		t.layers = layers_
		root.add_child(t)
		var st := MeshInstance3D.new()
		st.name = "s%d" % i
		st.mesh = stitch
		st.material_override = red
		st.position = Vector3(0, y, r * 0.15)
		st.layers = layers_
		root.add_child(st)
		var b := MeshInstance3D.new()
		b.name = "b%d" % i
		b.mesh = ball_mesh()
		b.material_override = ball_material()
		b.scale = Vector3.ONE * (r / BALL_R)
		b.position = Vector3(0, y, r * 0.9)
		b.layers = layers_
		root.add_child(b)
	return root


## ストックに数を入れる: n 個は玉と通る糸、残りはなみ縫いの目
static func stock_count(strip: Node3D, n: int) -> void:
	for i in 5:
		strip.get_node("b%d" % i).visible = i < n
		strip.get_node("t%d" % i).visible = i < n
		strip.get_node("s%d" % i).visible = i >= n


# ---------------------------------------------------------------- 米袋を出す・しまう

## 帯の米袋を取り出して広げる（立ったまま）。k: 0 右手を帯へ / 1 引き抜いて胸の前で両手に / 2 ばさっと前へ広げて落とす
func _sack_draw(k: int) -> float:
	var h := height()
	match k:
		0:
			_hips_drop = 0.03
			_update_all()
			_turn_axis("chest", Vector3.UP, -0.3)   # 右の腰へ体をひねる（ため）
			_hold[1] = [self, (BELT.get(kind, BELT["kasa"]) as Vector3) * _scale + Vector3(0.03, 0.04, 0.0)]
			return 0.12
		1:
			_hold[1] = [self, Vector3(0.1, h * 0.6, -0.2)]
			_hold[0] = [self, Vector3(-0.07, h * 0.58, -0.22)]
			return 0.02
		_:
			# 解放: 両腕を前へ振り下ろし、袋を雪の上へ広げる
			_hips_drop = 0.06
			_update_all()
			_hold[1] = [self, Vector3(0.15, h * 0.4, -0.45)]
			_hold[0] = [self, Vector3(-0.15, h * 0.4, -0.45)]
			return 0.45


## 立って米袋を丸め、帯に戻す。k: 0〜1 腰を上げてかがむ / 2〜6 くるくる丸める / 7 跳ねた包みを受ける / 8 帯へ / 9 しまった
func _sack_stow(k: int) -> float:
	var h := height()
	if k <= 6:
		var b := _crouch_legs(0.75)
		if k <= 1:
			_hold[1] = [self, Vector3(0.12, h * 0.14, -0.4)]
			_hold[0] = [self, Vector3(-0.12, h * 0.14, -0.4)]
		else:
			# 足もとの袋を、両手で前へ転がすように、交互に回す
			var a := k * 1.7
			_hold[1] = [self, Vector3(0.08, h * 0.12 + 0.05 * sin(a), -0.38 - 0.07 * cos(a))]
			_hold[0] = [self, Vector3(-0.08, h * 0.12 - 0.05 * sin(a), -0.38 + 0.07 * cos(a))]
		return b + 0.45   # 深く前かがみ
	if k == 7:
		_crouch_legs(0.3)
		_hold[1] = [self, Vector3(0.08, h * 0.55, -0.22)]
		_hold[0] = [self, Vector3(-0.06, h * 0.53, -0.24)]
		return 0.15
	if k == 8:
		_turn_axis("chest", Vector3.UP, -0.25)
		_hold[1] = [self, (BELT.get(kind, BELT["kasa"]) as Vector3) * _scale + Vector3(0.03, 0.04, 0.0)]
		return 0.1
	return 0.0


## 丸めた米袋: 帯（右の腰）に下げておき、取り出す・しまうときは右手に持つ
func _make_roll() -> void:
	var hips := _id("hips")
	var hand := _id("hand.R")
	if hips < 0 or hand < 0:
		return
	var at_hip := BoneAttachment3D.new()
	at_hip.bone_name = "hips"
	skel.add_child(at_hip)
	_roll_hip = Node3D.new()
	_roll_hip.transform = Transform3D(Basis(Vector3.RIGHT, 1.2).rotated(Vector3.UP, 0.3), skel.get_bone_global_rest(hips).affine_inverse() * (BELT.get(kind, BELT["kasa"]) as Vector3))
	at_hip.add_child(_roll_hip)
	var at_hand := BoneAttachment3D.new()
	at_hand.bone_name = "hand.R"
	skel.add_child(at_hand)
	_roll_hand = Node3D.new()
	_roll_hand.transform = Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(-0.04, 0.05, 0) / _scale)
	at_hand.add_child(_roll_hand)
	_roll = Node3D.new()
	_roll.scale = Vector3.ONE / _scale
	var felt := Look.felt(belt_color, 6.0)
	var cm := CylinderMesh.new()   # くるくる巻いた袋
	cm.top_radius = 0.052
	cm.bottom_radius = 0.052
	cm.height = 0.24
	cm.radial_segments = 7
	cm.rings = 1
	var body := MeshInstance3D.new()
	body.mesh = cm
	body.material_override = felt
	body.layers = layers
	_roll.add_child(body)
	for y in [-0.06, 0.06]:   # 麻ひもで 2 か所しばる
		var tm := CylinderMesh.new()
		tm.top_radius = 0.056
		tm.bottom_radius = 0.056
		tm.height = 0.016
		tm.radial_segments = 7
		var tie := MeshInstance3D.new()
		tie.mesh = tm
		tie.material_override = Look.felt(Color(0.82, 0.72, 0.5), 8.0)
		tie.position.y = y
		tie.layers = layers
		_roll.add_child(tie)
	_roll_hip.add_child(_roll)
	_roll.visible = false


## 丸めた米袋をコマごとに、帯・右手・なし（広げてある）のどこかに置く
func _place_roll() -> void:
	if _roll == null:
		return
	var ko := sack_k("out")
	var ki := sack_k("in")
	var at: Node3D = null
	if ko >= 0:
		at = _roll_hip if ko == 0 else (_roll_hand if ko == 1 else null)
	elif ki >= 0:
		at = _roll_hand if ki in [7, 8] else (_roll_hip if ki >= 9 else null)
	elif belt_sack:
		at = _roll_hip
	_roll.visible = at != null
	if at and _roll.get_parent() != at:
		_roll.reparent(at, false)
	var body := _roll.get_child(0) as MeshInstance3D
	var m := body.material_override as StandardMaterial3D
	if not m.albedo_color.is_equal_approx(belt_color):
		m.albedo_color = belt_color


static var _ball_mesh: Mesh
static var _ball_mat: Material


## 雪玉の形。ちぎった綿を丸めた、角のある毛玉（投げた雪玉・手の雪玉・一人称の雪玉で同じ）
static func ball_mesh() -> Mesh:
	if _ball_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = BALL_R
		sm.height = BALL_R * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		_ball_mesh = sm
	return _ball_mesh


static func ball_material() -> Material:
	if _ball_mat == null:
		_ball_mat = Look.felt(Color(0.97, 0.97, 0.94), 4.0)
	return _ball_mat


## 手形と腕。先に手形の置き所と向きを決め、腕の先（手首の関節）を手形の手首の真ん中へ伸ばす（腕の角度は手形の場所に合わせる）。
## 高い手のひらは見ている向きの顔より上（前を見れば遠くの人に場所を示す、見上げれば万歳）、低い手のひらはみぞおちの前で下へ向けて
## （おさえて・ストップ）。両手のときは肩幅に、片手のときは少し外へ。指さしは腕をまっすぐ指す向きへ。
## ハイタッチは合う所、握手は重ねる所（配り役が決める）に手形を置く。引く・振り下ろすコマは、腕の先に手形を付ける
func _plan_palms(kind_: String, k: int) -> void:
	_palm_goal.clear()
	var want := {}   # 側 → [形, 置き方]
	for sd in [1, -1]:
		var height: String = hand_shapes[0 if sd > 0 else 1]
		if height != "":
			want[sd] = ["palm", height]
	if point != Vector3.INF:
		var lp := global_basis.inverse() * (point - global_position)
		for sd in (point_sides if not point_sides.is_empty() else [1 if lp.x >= 0.0 else -1]):
			want[sd] = ["point", "point"]
	var grip_at := {}
	if k >= 0 and kind_ in ["high_five", "shake", "whiff"]:
		want = {}
		if kind_ == "whiff":
			if k < 3:
				want[int(emote.get("side", 1))] = ["palm", "whiff"]
		elif (kind_ == "high_five" and k < 8) or (kind_ == "shake" and k < 20):
			for gr in emote.get("grips", []):
				want[int(gr[0])] = ["palm", kind_]
				grip_at[int(gr[0])] = gr[1]
	elif k >= 0 and kind_ in ARM_EMOTES:
		return
	var head_w := skel.global_transform * _head_of(_id("head"))
	var look := -global_basis.z
	if gaze != Vector3.INF and gaze.distance_to(head_w) > 0.01:
		look = (gaze - head_w).normalized()
	var ahead := Vector3(look.x, 0, look.z)
	ahead = ahead.normalized() if ahead.length() > 0.05 else -global_basis.z
	var pop := Palm.pop(frame_index() - _hands_frame)
	for side in want:
		var shape: String = want[side][0]
		var how: String = want[side][1]
		var sname := "R" if side > 0 else "L"
		var hi := 1 if side > 0 else 0
		var sh_w := skel.global_transform * _head_of(_id("upper_arm." + sname))
		var arm := (_len(_id("upper_arm." + sname)) + _len(_id("forearm." + sname))) * _scale
		var bone_wrist := skel.global_transform * _head_of(_id("hand." + sname))   # いまの腕の先
		var size := Palm.BIG * pop
		var b := Basis.IDENTITY
		var wrist := Vector3.INF   # 腕を伸ばす先（INF なら、いまの腕の先に手形を付ける）
		var origin := Vector3.INF  # 手形の置き所（INF なら、手首から決める）
		match how:
			"high", "low":
				var dir := (look + Vector3.UP * 0.55).normalized() if how == "high" else (ahead + Vector3.DOWN * 0.75).normalized()
				wrist = sh_w + dir * arm * 0.88 + global_basis.x * float(side) * arm * 0.12
				var face := (gaze - wrist) if gaze != Vector3.INF else -global_basis.z
				var tilt := -0.65 if how == "low" else clampf(atan2(face.y, Vector2(face.x, face.z).length()) * 0.5, -0.4, 0.6)
				b = _face_basis(face, tilt)
			"point":
				var y: Vector3 = (point - sh_w).normalized()
				wrist = sh_w + y * arm * 0.98
				var z := y.cross(Vector3.UP)
				z = (z.normalized() if z.length() > 0.05 else global_basis.x) * float(side)
				b = Palm.thumb_up(Basis(y.cross(z).normalized(), y, z), side)   # 人さし指（+y）を指す向きへ、面は横から見える向き、親指は上
				size = Palm.BIG
			"high_five":
				size = Palm.BIG * (1.25 if k == 3 else 1.0)
				if k < 3 or not grip_at.has(side):
					b = _face_basis(-global_basis.z, 0.45 if k < 3 else 0.0)   # 引くと、手のひらが少し上を向く
				else:
					var g: Vector3 = grip_at[side]
					b = _face_basis(emote.get("fwd", g - sh_w), 0.0)   # 手のひらは相手の体へ（配り役が決める）
					if k < 6:
						origin = g   # 叩きつける: 手形を合う所に
			"whiff":
				b = _face_basis(-global_basis.z, 0.45 if k < 2 else 0.0)
			"shake":
				b = Palm.shake_basis(emote.get("fwd", -global_basis.z), emote.get("axis", global_basis.x), side)
				size = Palm.BIG
				var g: Vector3 = grip_at[side]
				# 差し出す（2 コマ）→ 重ねる所でぴったり合わせ、二人一緒に上下に振る
				origin = (g + Vector3.UP * Palm.shake_pump(k)) if k >= 2 else sh_w.lerp(g, 0.75)
		var bs := b.scaled(Vector3.ONE * size)
		if origin != Vector3.INF:
			wrist = origin + bs * Palm.WRIST
		if wrist != Vector3.INF:
			_hold[hi] = [self, to_local(wrist), true]   # 腕の先を手形の手首へ（毎フレーム伸ばし直す）
			origin = wrist - bs * Palm.WRIST
		else:
			origin = bone_wrist - bs * Palm.WRIST
		_palm_goal[side] = [shape, global_transform.affine_inverse() * Transform3D(bs, origin)]


## 手のひら（+z）を face の向き（水平）へ立て、tilt だけ上（正）か下（負）へ傾ける
func _face_basis(face: Vector3, tilt: float) -> Basis:
	face.y = 0
	face = face.normalized() if face.length() > 0.01 else -global_basis.z
	return Basis.looking_at(-face, Vector3.UP) * Basis(Vector3.RIGHT, -tilt)


## 手形のアップリケを、コマで決めた置き所に（人形の座標で持つので、体と一緒になめらかに動く）
func _place_shapes() -> void:
	for sh in _shapes:
		for side in [1, -1]:
			var node: Node3D = _shapes[sh][side]
			var goal: Array = _palm_goal.get(side, [])
			node.visible = not goal.is_empty() and goal[0] == sh
			if node.visible:
				node.global_transform = global_transform * (goal[1] as Transform3D)
