extends RigidBody3D

const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const Fabrics := preload("res://fabrics.gd")
const Snowball := preload("res://snowball.gd")
const Stitches := preload("res://stitches.gd")
const Flung := preload("res://flung.gd")
const TreeHits := preload("res://tree_hits.gd")
const Doll := preload("res://doll.gd")
## 大きなソリ。誰が押しても push() を呼ぶだけ（あなたも仲間も、のちの通信の相手も同じ）。
## 押す人が少ないとじりじり、多いと目に見えて速く登る。乗る人がいると減速をゆるめて一気に滑る。
## 誰も触れていない空のソリは、坂をゆっくりずり落ちる。速く下っているソリをつかむと引きずられ、
## 止める人の力の合計が「ソリと乗っている人の重さ × 坂」に勝てば止まる（引きずりの計算はソリがまとめてする。通信ではホスト）。

const PUSH_FORCE := 300.0   # 1人が押す力 (N)。1人でも最も急な所をじりじり登れる
const CLIMB_DAMP := 3.5     # 登るときの雪の抵抗（押すのをやめるとすぐ止まる。大きいほどじりじり）
const STAND := 0.6                 # つかむ人が立つ、縁からの距離
var ROPE_LEN := 3.0           # 引き紐の長さ（KINDS の rope_len。米袋は短い）
const ROPE_FORCE := PUSH_FORCE      # 紐が張ったときの引く力 (N)。2026-11-06 代表「紐でも本体を押してる時と同じ強さにして欲しい」。押す力と同じ（速いと弱まるのも PUSH_FADE で同じ）
const ROPE_TAKEUP := 0.15          # 紐が張りはじめてから、この長さ (m) 伸びると力が全部かかる（ぴんと張る瞬間にがくんとしない）
const ROPE_LEAD := 0.5             # 紐が張っている人は、ソリの速さよりこれだけ速く歩ける (m/s)。軽いソリを押すときの速さまで引ける
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
			"drag": 10.0, "push": 0.72, "sink": 0.0, "plane": 1.0, "turn": 1.0, "stand_slip": 0.03, "stand_speed": 3.0, "kick": 1.0,
			"seats": [Vector3(0, 0.15, 0.1)],
			"whole": true,                   # メインカラーは袋全体（地のクラフト紙ごと）。印刷は読める色に（props.gd の recolor）
			"rope_spare": 0.1, "rope_len": 1.2},   # 紐は前の左右の耳を結ぶ短いたわみと、まんなかから短い引っ張り紐
	"small": {"mass": 15.0, "box": Vector3(0.75, 0.45, 1.6), "runner_x": 0.28, "runner_z": 0.6, "color": Color("D2553A"), "stitch": "running",
			"drag": 0.6, "push": 3.2, "sink": 0.0, "plane": 1.0, "turn": 1.0, "stand_slip": 0.1, "stand_speed": 1.5, "kick": 0.0,
			"seats": [Vector3(0, 0.06, -0.3), Vector3(0, 0.06, 0.4)]},
	"mid": {"mass": 60.0, "box": Vector3(1.5, 0.45, 2.8), "runner_x": 0.6, "runner_z": 1.1, "color": Color("D2553A"), "stitch": "chain",
			"drag": 3.2, "push": 2.25, "sink": 0.02, "plane": 3.0, "turn": 1.0, "stand_slip": 0.3, "stand_speed": 0.6, "kick": 0.0,
			"seats": [Vector3(0, 0.45, -0.75), Vector3(0, 0.45, 0.15), Vector3(0, 0.45, 1.0)]},
	"large": {"mass": 220.0, "box": Vector3(2.2, 0.45, 4.8), "runner_x": 0.95, "runner_z": 1.9, "color": Color("D2553A"), "stitch": "saddle",
			"drag": 4.8, "push": 3.15, "sink": 0.06, "plane": 5.0, "turn": 1.0, "stand_slip": 0.6, "stand_speed": 0.5, "kick": 0.0,
			"seats": [Vector3(-0.5, 0.55, -1.65), Vector3(0.5, 0.55, -1.65), Vector3(-0.5, 0.55, -0.55), Vector3(0.5, 0.55, -0.55),
					Vector3(-0.5, 0.55, 0.55), Vector3(0.5, 0.55, 0.55), Vector3(-0.5, 0.55, 1.65), Vector3(0.5, 0.55, 1.65)]},
}

# ---- ずり落ちと引きずり（調整する値。意味と、変えるとどうなるかは design/controls-and-physics.md）
const SLIDE_GRIP := 0.15       # 空のソリの雪の摩擦（重さに対する割合）。坂の傾き（tan）がこれより緩い所で止まる。0.15 ≈ 8.5°
const SLIDE_DRAG := 72.0       # 空のソリがずり落ちるときの雪の抵抗 (N per m/s)。大きいほどゆっくり。重さによらないので、
                               # 重いソリほど速くずり落ちる（2026-10-29 に、重さに比べた 1.2 から、中で同じになる 72 N に）
# 動いている空のソリの雪の抵抗は、平らな所ほど弱い（2026-11-06 代表「下は雪なのでもっとしっかり滑って欲しい」）。
# 坂の傾き（tan）が SLIDE_GRIP 以上なら上の 2 つのまま（ずり落ちる速さは前と同じで、歩いて追いつける）。平らに近づくほど下の 2 つへ寄る
const GLIDE_GRIP := 0.05       # 平らな所を滑っている空のソリの摩擦（重さに対する割合）
const GLIDE_DRAG := 18.0       # 平らな所を滑っている空のソリの抵抗 (N per m/s)
const GLIDE_FRICTION := 0.02   # ソリの底の摩擦（物理の材質）。乗っていても空でも、どの速さでも効く減速（重力 × これ）。これがいちばん低い速さの滑りを決める
const EDGE_DRIFT := 30.0        # 地面の端の吹きだまりの幅 (m)。ここに入ると、端へ向かう速さだけが弱まる（遠景の雪山の手前で止まる）
const EDGE_STOP := 3.0          # 端からこの距離までに止まる (m)
# 上り斜面の減速（2026-11-07 代表「上り斜面への減速率が低いかも」）。乗って滑っているソリが雪面の上りへ向かうあいだだけ、坂の重力をこの割合だけ足す。下りと平らな所では 0。
# 地形の傾きで見るので、ジャンプ台の坂（当たりは地形の上に別にある）には効かない。押して登るときは _ride_forces を通らないので効かない
const UPHILL_K := 0.7
const UNPLANE_SPEED := 0.5     # これより遅くなると、また雪に沈む（KINDS の sink。止まりきらずにいつまでも這わないように）
const RIDER_MASS := 45.0       # 乗っている人一人の重さ (kg)。止めるときにだけ効く（登りの重さは RIDER_PUSH_MASS）
## 押す・紐で引くときの、乗っている人一人の重さ (kg)（2026-11-08 代表「乗ってる分ソリが重くなって押すのが大変になるようにしてほしい」。push_share）。
## 軽いソリほど効く（小 15 kg に 1 人で、押して登る速さが ×0.25）。重すぎたらここを下げる
const RIDER_PUSH_MASS := 45.0
const STOP_FORCE := 300.0      # つかんでいる人一人が止める力 (N)。押す力と同じ
const DRAG_SPEED := 2.5        # これより速く下っているソリをつかむと、引きずられる (m/s)
const DRAG_STOP_SPEED := 0.8   # 引きずられて、ここまで遅くなったら踏みとどまる（静止摩擦で留まる）
const DRAG_MAX_DIST := 15.0    # 止められないまま、この距離を引きずられると手が離れる (m)
const DRAG_SLIP_SPEED := 8.0   # これより速いと手がもたない（つかんでもすぐ離れる）(m/s)

const BODY_MIN_MASS := 15.0    # 物理の体の重さの下限 (kg)。米袋（重さ 1 kg）でも揺れずに滑るため。止める計算は表の重さを使う
const MID_MASS := 60.0         # 滑り木の抵抗・体重移動・雪かきの力はこの重さで決めた値。重さに比べて同じ効きにする
const PUSH_FADE := Vector2(3.0, 4.0)   # 押されるソリがこの速さ (m/s) を超えると、押す力が弱まって消える（人は走るより速く押せない）
const COL_MIN_H := 0.3         # 当たりの箱の厚さの下限 (m)。これより薄いと、強い着地で地面をすり抜ける（米袋）
const FALL_NET := 2.0          # 安全網: 雪面よりこれだけ下へ沈んだら、その場の雪の上へ戻す (m)

signal slipped(who: Node3D)    # 引きずられて手が離れた

# ---- 雪の塊や木にぶつかって打ち上がる（塊は sled_crash.gd。値の意味は design/controls-and-physics.md）
const CRASH_SOFT_SPEED := 3.0  # 雪の塊に、これより速く当たると打ち上がる (m/s)。押している・紐で引いている・つかんでいるソリは飛ばない
const CRASH_UP := Vector2(5.0, 13.0)   # 上へ飛ぶ速さ (m/s)。当たった速さが CRASH_UP_AT.x のとき 〜 CRASH_UP_AT.y のとき
const CRASH_UP_AT := Vector2(3.0, 12.0)
const CRASH_KEEP := 0.35       # 雪の塊: 当たった速さのうち、そのまま前へ残る割合。大きいと塊を越えてロッジの前の広場まで飛ぶ
const CRASH_BOUNCE := 0.3      # 木: 跳ね返る速さの割合
const CRASH_SPIN := Vector2(4.0, 9.0)  # 宙で回る速さの下限と上限 (rad/s)
const CRASH_SPIN_DAMP := 0.2   # 宙で回る勢いの弱まり（ふだんの angular_damp は 6）
const CRASH_LAND_DAMP := 2.5   # 着いたあと、回る勢いの弱まり
const CRASH_MAX := 40.0        # 打ち上がってからこの長さで、ふつうのソリに戻る (s)
const CRASH_REST := 1.0        # これだけ止まっていると、ふつうのソリに戻る (s)
## ワールドごとの滑りの速さ（main.gd がワールドを決めたときに入れる。tenkamori.gd の SITES の glide・pull）。乗って滑っているあいだだけ効く。
## 2026-11-12 代表「このコース（旭ヶ丘）はソリの加速と最大速度を上げたい。希望者はここで死にかけるくらい早いソリ滑りをしていた」
##   glide  雪の抵抗（drag・push・沈み）に掛ける割合。小さいほど最高速度が速い（最高速度はおよそ 1/√glide 倍）
##   pull   坂を下る向きに足す、重力の割合。大きいほど加速がよい（凍った斜面のすべりのよさ）
## どちらも掛け算と足し算が 1 つずつ増えるだけで、描く物も当たりの計算も増えない
## 2026-11-14 代表「旭ヶ丘での滑ってる時の一人称視点のガクガクやスピードなど、旭ヶ丘でのみ実装していたものを共通のものにしたい」で、
## どのワールドも FEEL の値にした（前は旭ヶ丘だけで、ほかは glide 1・pull 0・bumps 0・rattle 0）。値は旭ヶ丘で決めたまま
const FEEL := {"glide": 0.25, "pull": 0.4, "bumps": 1.0, "rattle": 0.75}   # rattle 0.75: 代表が「いい感じ」と言ったときの揺れ
static var glide := 0.25
static var pull := 0.4
## ワールドごとの揺れ（2026-11-12 代表「ソリってもっと揺れるよね？それが怖かった記憶がある。画面のガクガクもそうだし、ちょっとした隆起で跳ねる」）
##   bumps   雪面の小さな隆起で跳ねる強さ（0 で無し）。乗って BUMP_MIN より速く滑っているとき、雪面を BUMP_CELL (m) の升に分け、
##           升ごとに決まった割合（BUMP_CHANCE）で隆起がある。隆起に乗り上げると、速さに比べた勢いで雪面から跳ね、前後に少しつんのめる。
##           隆起の所は場所で決まるので、同じ所を通れば同じ所で跳ねる。升をまたぐときに数を 1 つ作るだけで、当たりの形も描く物も増えない
##   rattle  乗っている人の画面のガクガクの強さ（player.gd が読む。0 で無し）
static var bumps := 1.0
static var rattle := 0.75
const HALF_H_ON_SNOW := 0.9    # ソリのまんなかが雪面からこれより上なら、宙にいる (m)
## 跳ねは「ジャンプ」でなく、ごつんと突き上げられる小刻みな衝撃（2026-11-12 代表「はねるのがジャンプみたいになってる」）:
## 高さは数 cm で、すぐ雪面に戻る。そのかわり細かい間隔で何度も来て、前後・左右にがくっと揺さぶる
const BUMP_CELL := 2.5
const BUMP_CHANCE := 0.45     # 升に隆起がある割合（2026-11-12 代表「少しの隆起でももう少し跳ねて良い」）
const BUMP_MIN := 3.5          # これより遅いと跳ねない (m/s)
const BUMP_UP := 0.05          # 突き上げる速さ = 滑る速さ × これ（BUMP_UP_MAX まで）× (0.5〜1.5) × bumps
const BUMP_UP_MAX := 0.8       # 突き上げる速さの上限 (m/s。高さ 3 cm ほど、宙に 0.16 秒ほど)
const BUMP_PITCH := 1.1        # つんのめる・のけぞる回る速さ (rad/s) の上限
const BUMP_ROLL := 0.6         # 左右にがくっと傾く回る速さ (rad/s) の上限
var _bump_cell := Vector2i(1 << 30, 0)
var bump_n := 0                # 跳ねた回数（確かめ用・画面のガクガクのきっかけ）
## 宙と着地（2026-11-14 代表「ジャンプ台や起伏でのちょっとした落下のときに体が浮く用な浮遊感とかバウンドする感じとかが欲しい」）。
## 地面のほうが下がって浮いたら、ふつうの重力のまま飛ぶ（前は、雪面から 0.6 m 浮くと重力を 0.8 倍足して引き戻していた。BUMP_SNAP）。
## 小さな隆起の「ごつん」（bumps）は数 cm のままで、宙には数えない。
## 着いたら、雪面へ向かっていた速さの LAND_BOUNCE 倍で 1 回はね返る（雪が受け止めるので小さく。2 回めはほとんど浮かない）。
## air_t・land_n・land_v は、乗っている人の目の浮き沈み（player.gd の _ride_air）・滑る音（audio.gd）・雪しぶき（ride_wind.gd）が読む。
## 下への線 1 本（_ground_normal と同じもの）で見るので、当たりの計算も描く物も増えない。
## 旭ヶ丘を速く下ると、起伏に付いていけず 1〜2 秒に 1 回は 0.3〜1 秒ほど浮く（引き戻していた前も、小刻みな浮きは同じだけあった）。
## だから、見せ方の側は「長く浮いたとき」だけ大きく変える（player.gd の AIR_LIFT_T・RATTLE_AIR_T、audio.gd）
const AIR_GAP := 0.22          # ソリの底が、下の当たり（雪面・ジャンプ台）からこれより離れたら宙 (m)
const AIR_MIN_T := 0.12        # これより長く宙にいたあと着いたら、着地とする (s)
const LAND_MIN_V := 1.0        # 雪面へ向かう速さがこれより速いと、着地の手応えがある (m/s)
const LAND_BOUNCE := 0.22      # はね返る速さ = 雪面へ向かっていた速さ × これ（LAND_BOUNCE_MAX まで）
const LAND_BOUNCE_MAX := 1.5   # はね返る速さの上限 (m/s。高さ 11 cm ほど、宙に 0.3 秒ほど)
var air_t := 0.0               # 乗って滑っていて、宙にいる時間 (s)。雪の上では 0
var land_n := 0                # 着地した回数
var land_v := 0.0              # 最後の着地の、雪面へ向かっていた速さ (m/s)
var _air_vn := 0.0             # 宙にいるあいだの、雪面へ向かう速さ
var _touch_t := 0.0            # 雪面のすぐ上まで来てからの時間（当たりが受け止めるのを待つ）
var _ground_gap := INF         # ソリの底から、下の当たりまでの高さ (m)。_ground_normal が入れる（届かなければ INF）
var crashed := false           # 打ち上がってから止まるまで。乗れない。滑り木は効かず、どの向きでも坂に沿って滑る
var _crash_t := 0.0
var _crash_still := 0.0
var _right_t := 0.0
const TIP_UP := 0.5             # ソリの上向きの y がこれより小さい（60° より傾いた）と、縦や横倒し。乗れない・つかめない
const TIP_WAIT := 0.5           # 縦や横倒しのまま、これだけ続いたら跳ねて起き直る (s)
var _tip_t := 0.0

# ---- ペグで斜面に留める（2026-11-01 代表「斜面にそりを留める消耗品があると休憩したり焚き火ができる」。形と動きは peg.gd）
# 引き紐の先をペグに結ぶ。留めているあいだは、乗っていても、どんな坂でも止まっている（休める・そばで焚き火ができる）。
# 押すと紐のたるみの分だけは動くが、紐が張るとそれ以上は行かない。乗ったまま雪をかいても、蹴っても進まない。
# 紐は持てない（ペグに結んである）。滑るには、誰かがペグを抜く（F。乗ったままでも届けば抜ける）。抜いたペグは使い切り。
# 通信ではホストのソリの力で止まり、つなぐ側はホストの姿を写す（ペグの見た目と紐の結び先は craft の出来事で全員に）
const PEG_HOLD := 1.2          # 留めているときの静止摩擦の上限（重さに対する割合）。1 を超えれば、どの坂でも留まる
const PEG_K := 5000.0          # 紐が張ったときに引き戻す力 (N/m。中より重いソリは重さに比べて強く。大に 8 人で押しても伸びは 0.2 m ほど)
const PEG_DAMP := 6.0          # 張った紐の向きに動く速さを弱める力（重さ × これ, N per m/s）
const PEG_PULL_MAX := 30000.0  # 引き戻す力の上限 (N)
var peg: Node3D = null         # 刺さっているペグ（peg.gd。ソリの子で、世界に留まる）。なければ null
var racked := false            # 立てかけ台（sled_rack.gd）に立てかけてある。動かず、つかめず、乗れない。出来事は craft.gd の rack_in・rack_out

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
var base_fabric := ""          # 見本帳で染めたソリ（fabric が "#RRGGBB"）の、元の布の名前。脱色で戻す（sled_book_ui.gd・craft.gd の sled_dye）
var crafted := false           # ミシンで縫った・広げたソリ（畳んで持てる。craft.gd）
var tag: Variant = 0           # 名札の柄（sled_tags.gd）。ソリごとの名札（辞書）か、ロッジの名札（0）。-1 は名札なし。手すりの前の結び目から小さく吊るす。
                               # 米袋には付けない（2026-10-31 代表「タグは米袋には要らない」）
var owner_id := -1             # 持ち主（名札を持っている人）の番号。縫った人・名札を付けた人・米袋の人。-1 は持ち主なし（ロッジのソリ・名札を外したソリ）
var kind_mass := 60.0          # 表の重さ（米袋は 1 kg）。乗っている人の重さと合わせて止める計算に使う
var _k := 1.0                  # 体の重さ / MID_MASS
var SEATS: Array = KINDS.mid.seats
var HALF := Vector2(0.75, 1.4)     # 台の半分の幅と長さ
var ROPE_ANCHOR := Vector3(0, 0.3, -1.45)
var RUNNER_Z := 1.1                # 滑り木の前後の接地点（中心からの距離）
var RUNNER_X := 0.6                # 左右の滑り木の位置
var _planed := false           # 乗って滑っていて、雪から浮いている（_ride_forces）
var parked := true             # ふもとに止めてある（最初と R で戻したとき）。誰かが触るまでずり落ちない
var dragged := {}              # 引きずられている人 → 引きずられた距離 (m)
var _pushed_by := {}           # このコマ押した人（引きずりの判定用。押している人は引きずられない）
var _pushed_now := {}
var helped := {}               # 押した・紐で引いた人 → その時刻（_trail_now）。雪のボタンを、乗らずに手伝った人にも分ける（snow_buttons.gd）
# ---- 通信: つなぐ側のソリは、ホストのソリの姿を写す（net.gd）。自分の画面では力で動かさず、届いた姿と速さから
# いまの姿を先読みして、そこへなめらかに寄せる。速さは届いた値をそのまま持つ（音・視野角・引きずりが読む）
var net_follow := false:
	set(v):
		net_follow = v
		custom_integrator = v   # かけた力・重力では動かない（_integrate_forces で姿を決める）
const NET_PULL := 0.2          # 1 コマで、先読みした姿へ寄る割合
const NET_SNAP := 4.0          # これより離れていたら置き直す (m)
const NET_AHEAD := 0.3         # 届かないあいだ、先読みするのはここまで (s)
var _net_at := Transform3D()
var _net_v := Vector3.ZERO
var _net_w := Vector3.ZERO
var _net_age := -1.0           # 届いてから (s)。まだ届いていなければ負
# ---- 乗って滑るときの、乗っている一人ひとりの力（調整する値。乗る人の数だけ足し合わさる）
# 乗って下っているあいだは、乗っている人の重さ（RIDER_MASS）もソリと一緒に動く重さに入る。
# 人の力は「ソリ＋乗る人」の重さで分け合うので、重いソリほど一人の力では動きにくく、そろえると効く
const LEAN_DIG := 30.0             # 一人が体重をかけた側の滑り木が食い込んで増える抵抗 (N per m/s)。逆向きの人とは打ち消し合う
                                   # （2026-10-29 に、乗る人の重さを入れたので 17.5 から合わせ直した。中＋一人の曲がり方は前と同じ）
const SCOOP_FORCE := 210.0         # 一人が乗ったまま前傾して手で雪をかく力 (N)。坂を登る向きには効かない
const BRAKE_DRAG := 40.0           # 一人が後ろに体重をかけたときの制動（両側, N per m/s）。2026-11-06 に、雪の抵抗を弱めたぶん 24 から上げた（止まれる距離は前と同じくらい）
const FWD_LEAN_EASE := 0.6         # 前傾した人の割合 × これだけ、雪をこする抵抗が減る（全員前傾で 0.4 倍）
# ---- 足で漕ぐ（米袋。2026-10-29 代表「スペース連打で滑走中のみ加速」「友達と連打勝負できるように」）
# 一回蹴るごとに前へ KICK_DV だけ速くなるが、速いほど蹴りが効かなくなり、KICK_TOP に近づくと 0 になる。
# 漕がずに滑るだけなら大きいソリより遅いが、速く連打するほど伸び、大きいソリより速くなれる（連打の速さがそのまま速さの差）。
# 下り坂で全部効き、平らな所では KICK_FLAT だけ、登りでは効かない（登りを楽にしない）
const KICK_DV := 1.5               # 一回蹴って速くなる量 (m/s。止まりかけのとき)
const KICK_TOP := 16.0             # 蹴って届く速さの上限 (m/s)。ここに近づくほど蹴りが効かない
const KICK_FLAT := 0.6             # 平らな所での蹴りの効き（下り坂で 1）。走って乗った勢いを、平らな所でも漕いで保てる
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
var _push_force := Vector3.ZERO      # 前のコマの押す・紐で引く力の合計（_pushing_uphill）
var _push_force_now := Vector3.ZERO
const UPHILL_PUSH_SLOPE := 0.05      # これより緩い坂（傾きの sin。約 3°）は、押していても登りに数えない
var _steer := 0.0           # 乗っている人の左右の体重移動の合計（このコマ。一人 -1〜1 を足し合わせる。上限なし）
var _n_fwd := 0             # このコマ前傾した人の数
var _n_back := 0            # このコマ後傾した人の数
var steer_now := 0.0        # 前のコマの体重移動の合計（確かめ用・表示用）
var hold_debug := ""

# 足元の影と、滑り木の跡（ステッチ）
const TRAIL_N := 1600         # 同時に残せる歩みの数（滑り木 2 本 × 800 歩 = 約 240 m、丘を 4 回ほど滑った長さ）。あふれたら、いちばん早く消える目から使い回す
const TRAIL_STEP := 0.3       # 縫い目の 1 歩の長さ (m)。1 歩ごとに縫い目の形を 1 つ置く
const TRAIL_JITTER := 0.012   # 針穴の位置のばらつき (m)。手で縫ったような揺れ
## 縫い目の種類（stitches.gd の表と形）。per は 1 歩に置く糸の目の数の目安、radius は糸の太さ（半径 m）
const STITCHES := Stitches.LIST
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
const TRAIL_CHUNK := 100              # 歩みをこの数ずつの塊に分けて描く（塊の目の数は × per）。画面の外の塊は描かない
const TRAIL_CHUNK_SPAN := 24.0        # 1 つの塊に入れる跡の広がり (m)。塊は続いた跡だけを持つ（離れた跡が混ざると、塊のまんなかが遠くなって丸ごと消える）
const TRAIL_SEE := 45.0               # これより遠い塊は描かない (m)。糸は細いので、その先はほとんど見えない
const TRAIL_MAKE := 130.0             # カメラからこれより遠いソリは、跡を作らない (m)。遠くのソリのぶん重くならないように（どうせ見えない）
const TRAIL_SLOW := 0.25              # これより遅い動き (m/s) は歩みに数えない。止まっても前の目から続けて縫う
const TRAIL_AIR := 0.6                # 滑り木の下がこれより空いていたら、宙を飛んでいるので縫わない (m)
const TRAIL_JUMP := 2.0               # 1 コマでこれより動いたら、置き直されたので跡を切る (m)
const TRAIL_LEN := Vector2(0.1, 0.9)  # 1 歩の長さがこの外なら縫わない (m)
var _stitch: ArrayMesh                        # 1 目の形（塊どうしで共有。色と時計はここに入れる。粗い形は Look.stitch_mesh）
var _trails: Array[MultiMeshInstance3D] = []  # 目の塊
var _chunk_i := 0                             # いま縫っている塊
var _chunk_fill := 0                          # その塊に置いた目の数
var _chunk_from := Vector3.ZERO               # その塊の最初の目の所
var _trail_now := 0.0                         # 滑りあとの時計 (s)。確かめ用に進めてよい
var _trail_end := PackedFloat32Array()        # 目ごとの、消えきる時刻
var _chunk_end := PackedFloat32Array()        # 塊ごとの、目がすべて消えきる時刻（過ぎたら塊を描かない）
var _trail_used := 0                          # 使ったことのある目の数
var _trail_noise := FastNoiseLite.new()
var _trail_dist := [0.0, 0.0]                    # 左右それぞれ、前の歩みから滑った長さ
var _trail_last := [Vector3.INF, Vector3.INF]    # 左右それぞれ、前のコマの滑り木の後ろ端
var _trail_count := [0, 0]                       # 左右それぞれ、歩みの番号（柄の左右や周期に使う）
var _trail_holes := [Vector3.INF, Vector3.INF]   # 左右それぞれ、前の歩みの縫い目の中心
var _trail_jit := [Vector3.ZERO, Vector3.ZERO]   # 左右それぞれ、前の針穴のばらつき
var _st: Dictionary = STITCHES.zigzag            # いまの縫い目（STITCHES の 1 つ）
var _stitch_name := "zigzag"
var _trail_n := TRAIL_N                          # 目の数（TRAIL_N × per）
var _trail_chunk := TRAIL_CHUNK                  # 塊の目の数
var _trail_rng := RandomNumberGenerator.new()
var snow_lift := Callable()   # (x, z) → 見た目の雪面が当たり判定からずれる量。main が渡す
# ---- 見た目を、見た目の雪面に載せる（2026-11-08 代表「二人乗りソリが雪に底が埋もれがち」「ソリのなかに雪が底から貫通するような感じ」）。
# 見た目の雪面は、当たり判定の地面に吹きだまりのうねり（main.gd の drift。道の外で最大 ±0.35 m）を足してある。ソリは当たりの上に
# 乗るので、うねりが高い所では見た目の雪が荷台の床を突き抜けていた（小は床が底から 1〜5 cm しかない）。
# 当たりと物理はそのままにして、見た目（形・紐・名札）と、乗っている人の席・つかんでいる人の手（vis_point）だけを上下させる
const VIS_LIFT_RATE := 18.0    # 見た目の雪面へ寄る速さ（1/s）。速く滑ってうねりを越えるときも、雪が床から出ないように速め
const VIS_LIFT_ON := 0.15      # 底のどこも当たりの地面からこれより離れていたら（ロッジの床・ジャンプ台・宙）、合わせない (m)
var vis_lift := 0.0            # いま見た目を上げている量 (m。ソリの上向きに。負は下げる)
## 遠いか画面の外のソリは、見た目の雪面合わせ（雪面を 15 点測る）を VIS_LIFT_FAR_EVERY 歩に 1 回にする（見た目だけなので、遠くでは分からない）。
## CPU の仲間のソリが増えると、全部のソリが毎歩測るのが重かった（2026-11-09 測定）。doll.gd の thin_far で切れる
const VIS_LIFT_FAR_EVERY := 4
var _lift_dt := 0.0
var _lift_tick := 0
var _body_y0 := 0.0
var _tag_y0 := 0.0
var snow_plane := Callable()  # (x, z) → 見た目の雪面の向きと高さ Vector4(法線 x, y, z, 高さ)。main が渡す。なければ当たり判定＋snow_lift
var _box_col: CollisionShape3D  # 当たりの箱
var _crash_q: PhysicsShapeQueryParameters3D   # ぶつかる幹を探す問い合わせ（_check_crash）
var _crash_cool := 0.0       # 放り投げたあと、次に放り投げるまで空ける (s)。つなぐ側の人の席が空くまでに、もう一度配らないように


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
	# 速く着地しても地面をすり抜けないように（2026-11-01 代表「大きな山の段差を滑り飛んだときに着地と同時にすり抜けて無限に落ちた」）。
	# 地面の当たり（HeightMapShape3D）は厚みのない面なので、1 コマで箱の半分の厚さより深く入ると、裏へ押し出されて落ちる。
	# 動いた道すじを調べて、面の手前で止める
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = GLIDE_FRICTION
	physics_material_override = pm

	# 当たりの箱。薄い米袋（0.15 m）は、強く着地して少し沈むだけで箱の半分を超え、裏へ押し出される。
	# 当たりだけ COL_MIN_H まで上へ厚くする（底の高さは見た目と同じ）
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var h := maxf(k.box.y, COL_MIN_H)
	box.size = Vector3(k.box.x, h, k.box.z)
	col.shape = box
	col.position.y = k.box.y * 0.49 + (h - k.box.y) * 0.5
	add_child(col)
	_box_col = col

	_make_body()
	# 引き紐: 手すりの両端を結ぶたわんだ紐と、そのまんなかから出る引っ張り紐（sled_rope.gd）
	rope = preload("res://sled_rope.gd").new()
	rope.sled = self
	add_child(rope)
	retag(tag)

	_make_trail()

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
	_body_y0 = _body.position.y


## ソリの座標の点 local の、見た目の位置（世界）。乗っている人の席・つかんでいる人の手・紐の結び先は、ここで見た目の雪面に合わせる
func vis_point(local: Vector3) -> Vector3:
	return to_global(local + Vector3(0, vis_lift, 0))


var _lift_xf := Transform3D(Basis(), Vector3.INF)   # 雪面を聞いたときのソリの向きと位置
var _lift_want := 0.0                                # そのときの、載せる量
var _lift_put := NAN                                 # 見た目に入れ終えた量（まだなら NAN）

## 見た目を見た目の雪面に載せる量を求めて、寄せる。底（ソリの座標の y = 0）の 3 × 5 の点で、見た目の雪面がいちばん上に出ている所に合わせる
func _update_vis_lift(dt: float) -> void:
	var want := 0.0
	var w := get_parent()
	if snow_lift.is_valid() and w and w.has_method("height") and not crashed and not racked:
		# 止まっているソリ（置いた所から動いていない）は、前に求めた値のまま。雪面の 15 点を毎回聞き直さない（2026-11-14）
		var xf := global_transform
		if xf == _lift_xf:
			want = _lift_want
		else:
			var top := -INF
			var near := INF
			for i in 3:
				for j in 5:
					var p := to_global(Vector3((i - 1) * HALF.x * 0.9, 0.0, (j - 2) * 0.5 * HALF.y * 0.9))
					var g: float = w.height(p.x, p.z)
					near = minf(near, p.y - g)
					top = maxf(top, g + float(snow_lift.call(p.x, p.z)) - p.y)
			if near < VIS_LIFT_ON:
				want = top
			_lift_xf = xf
			_lift_want = want
	if vis_lift == want and _lift_put == want:
		return   # もう載っている
	_lift_put = want if absf(vis_lift - want) < 0.001 else NAN
	vis_lift = lerpf(vis_lift, want, 1.0 - exp(-VIS_LIFT_RATE * dt))
	if absf(vis_lift - want) < 0.001:
		vis_lift = want
	if _body:
		_body.position.y = _body_y0 + vis_lift
	var tg := get_node_or_null("Tag") as Node3D
	if tg:
		tg.position.y = _tag_y0 + vis_lift


## いまの滑りあとの縫い目の名前（STITCHES）
func stitch_kind() -> String:
	if STITCHES.has(stitch_override):
		return stitch_override
	return KINDS.get(kind, KINDS.mid).stitch


## 滑りあとの縫い目を替える（置いたあとでも。"" で KINDS の既定）。もう残っている跡は前の柄のまま、消えるまで残る
func set_stitch(name: String) -> void:
	if name != "" and not STITCHES.has(name):
		return
	stitch_override = name
	if _stitch == null or stitch_kind() == _stitch_name:
		return
	_retire_trail()
	_make_trail()


## ソリが消える前に呼ぶ（畳む・米袋をしまう）。残っている跡は雪の上に残り、ふつうの跡と同じ時刻に消えていく（2026-11-07 代表）
func leave_trail() -> void:
	_retire_trail()
	_stitch = null


## 残っている跡を、ソリから切り離して消えるまで見守らせる。また滑っても、切り離した跡とはつながらない。
## 塊はなくなるので、ソリが続けて滑るなら _make_trail を呼ぶ
func _retire_trail() -> void:
	if _stitch == null:
		return
	var left := TrailLeft.new()   # 残す目がなければ、部屋へ入れずに捨てる
	left.mesh = _stitch
	left.now = _trail_now
	for c in _trails.size():
		var mi := _trails[c]
		if mi.get_parent() == null:   # まだ場面へ足していない塊（一度も縫っていない）
			mi.free()
			continue
		remove_child(mi)
		if _chunk_end[c] > _trail_now and mi.multimesh.visible_instance_count > 0:
			left.keep(mi, _chunk_end[c])
		else:
			mi.queue_free()
	_trails.clear()
	_chunk_i = 0
	_chunk_fill = 0
	_trail_used = 0
	_trail_holes = [Vector3.INF, Vector3.INF]
	_trail_dist = [0.0, 0.0]
	if left.chunks.is_empty():
		left.free()
		return
	get_parent().add_child(left)
	TrailLeft.trim()


## 持ち主のソリから離れた跡（畳んだ米袋・柄を替える前の跡）。時計を進め、消えきった塊から片づける。
## 全部で LEFT_STITCHES・LEFT_CHUNKS を超えたら、ソリの跡が満ちたときと同じく、いちばん早く消える塊を丸ごと消す
class TrailLeft extends Node:
	const LEFT_STITCHES := 9600   # 残す目の合計（TRAIL_N の 6 本ぶん。CPU 5 人とあなたの跡がいっぱいでも収まる）
	const LEFT_CHUNKS := 96       # 残す塊の合計（ふつうのソリ 1 台の塊 16 × 6 本ぶん）
	static var all: Array = []
	var mesh: ArrayMesh
	var now := 0.0
	var chunks: Array = []        # [塊, 消えきる時刻]

	func keep(mi: MultiMeshInstance3D, end: float) -> void:
		add_child(mi)
		chunks.append([mi, end])

	func _enter_tree() -> void:
		all.append(self)

	func _exit_tree() -> void:
		all.erase(self)

	func _process(dt: float) -> void:
		now += dt
		Look.stitch_set_time(mesh, now)
		for i in range(chunks.size() - 1, -1, -1):
			if float(chunks[i][1]) <= now:
				drop(i)

	func drop(i: int) -> void:
		(chunks[i][0] as Node).queue_free()
		chunks.remove_at(i)
		if chunks.is_empty():
			queue_free()

	static func totals() -> Vector2i:
		var t := Vector2i.ZERO
		for l in all:
			t.y += l.chunks.size()
			for c in l.chunks:
				t.x += (c[0] as MultiMeshInstance3D).multimesh.visible_instance_count
		return t

	## 上限を超えたぶんを、いちばん早く消える塊から消す（残り時間で比べる。跡ごとに時計が違う）
	static func trim() -> void:
		var t := totals()
		while t.x > LEFT_STITCHES or t.y > LEFT_CHUNKS:
			var best: Node = null
			var at := -1
			var soon := INF
			for l in all:
				for i in l.chunks.size():
					var rest: float = float(l.chunks[i][1]) - l.now
					if rest < soon:
						soon = rest
						best = l
						at = i
			if best == null:
				return
			t.x -= (best.chunks[at][0] as MultiMeshInstance3D).multimesh.visible_instance_count
			t.y -= 1
			best.drop(at)


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


## 見本帳で染める。hex は "#RRGGBB"、"" なら元の布の色に戻す。ソリと滑りあとの糸がすぐその色になる（もう残っている跡も）
func dye_to(hex: String) -> void:
	if hex != "":
		if not Fabrics.is_dyed(fabric):
			base_fabric = fabric
		fabric = hex
		return
	if Fabrics.is_dyed(fabric):
		var b := base_fabric
		base_fabric = ""
		fabric = b
		if b == "":
			set_main_color(Color(0, 0, 0, 0))


## dir は押す向き（水平）、at は手が触れた所（世界座標）、who は押した人（引きずられている人は押せない）。
## strength は押す人の力の倍率（紙の体の水。damp.gd の段: よれよれ 0.7 〜 パリッと 1.25）
func push(dir: Vector3, at: Vector3, who: Node3D = null, strength := 1.0) -> void:
	dir.y = 0
	if dir.length() < 0.01 or dragged.has(who):
		return
	parked = false
	if who:
		_pushed_now[who] = true
		helped[who] = _trail_now
	var f: Vector3 = dir.normalized() * PUSH_FORCE * strength * min(1.0, dir.length()) * push_share()
	f *= 1.0 - smoothstep(PUSH_FADE.x, PUSH_FADE.y, linear_velocity.dot(dir.normalized()))
	# 力は手が触れている所にそのままかける。どう動くかは滑り木と重力が決める
	var p := to_local(at)
	p.x = clamp(p.x, -HALF.x, HALF.x)
	p.z = clamp(p.z, -HALF.y, HALF.y)
	p.y = 0.2
	_apply_level(f, global_basis * p)
	_push_count += 1
	_push_force_now += f


## 縦や横倒しになっている（起き直っている途中も）
func tipped() -> bool:
	return global_basis.y.y < TIP_UP or _right_t > 0.0


## 人が押す・紐で引く力 f を、ソリの r（体の中心からの、世界の向きの位置）にかける。ただし回す力は、ソリの上向きの軸のまわり（向きを変える分）だけにする。
## 縁を押せば向きが変わるのは前のまま。前後・左右に傾ける分は捨てる（2026-11-09 代表「おかしな挙動してる」）。
## 押す手（台の上 0.2 m）と紐の結び目（前の 0.3 m）は重心（台の下）より上なので、押す・引くたびに傾ける力がかかっていた。
## 軽い小のソリ（15 kg）を紐で引きながら仲間が後ろの縁を押すと起き上がり、立つと押す所が高くなってさらに立ち、
## 鼻先を下に縦に立ったまま、仲間が宙でつかんで運んでいた（tools/sled_tip_check.gd --case=rope）
func _apply_level(f: Vector3, r: Vector3) -> void:
	apply_central_force(f)
	var up := global_basis.y
	apply_torque(up * up.dot(r.cross(f)))


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
	if racked or tipped():   # 縦や横倒しのソリはつかめない（つかむ所が宙にある。起き直ってから）
		return false
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


## 押す・紐で引く力のうち、ソリが動く分の割合（2026-11-08 代表「乗ってる分ソリが重くなって押すのが大変になるようにしてほしい」）。
## 物理の体の重さ（mass）はソリだけなので、乗っている人の重さ（RIDER_PUSH_MASS）を足した重さで力を割り戻す。
## 坂の重さ・雪の抵抗は体の重さに比べてかかるので、ソリと乗っている人をまとめて押したのと同じ速さになる。
## 乗っていなければ 1（押し心地は前のまま）。力は中に 1 人で ×0.57、2 人で ×0.4、小に 1 人で ×0.25（小は軽いので、乗った人の重さが効く）。
## 登る速さは、遅いときの静止摩擦（HOLD_FRICTION）も効くので、力ほどは落ちない（tools/ride_push_check.gd）。
## 通信では、ホストの画面のソリにかかる力だけが効く（つなぐ側の人もホストの画面の体が push・pull_rope を呼ぶので、同じに重い）
func push_share() -> float:
	return mass / maxf(mass, maxf(kind_mass, 1.0) + riders.size() * RIDER_PUSH_MASS)


## 前のコマの押す・紐で引く力の合計が、坂の上へ向いているか（坂が UPHILL_PUSH_SLOPE より緩ければ false）
func _pushing_uphill() -> bool:
	var n := _ground_normal()
	var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)   # 地面に沿った下り（長さは傾きの sin）
	if down.length() < UPHILL_PUSH_SLOPE or _push_force.length() < 1.0:
		return false
	return _push_force.normalized().dot(down.normalized()) < -0.3


## ソリがこれより速く下っているか（押されて登っているときは数えない）
func _downhill_fast(v: float) -> bool:
	return linear_velocity.length() > v and (_pushed_by.is_empty() or linear_velocity.y < -0.1)


func take_rope(who: Node3D) -> bool:
	if racked or peg or rope_holder != null and rope_holder != who:   # ペグに結んである紐は持てない
		return false
	rope_holder = who
	parked = false
	return true


func release_rope(who: Node3D) -> void:
	if rope_holder == who:
		rope_holder = null


## 紐が張っている人が歩ける速さ（walk はその人のふだんの張ったときの速さ）。ソリについて行けないと、押すより遅くしか引けない
func taut_walk_speed(walk: float) -> float:
	return maxf(walk, linear_velocity.length() + ROPE_LEAD)


## 紐を持つ人の手の位置から、張っていれば引く。張った分の長さを返す（たるみなら負）。strength は引く人の力の倍率（push と同じ）
func pull_rope(hand: Vector3, strength := 1.0) -> float:
	var anchor := to_global(ROPE_ANCHOR)
	var d := hand - anchor
	var over := d.length() - ROPE_LEN
	if over > 0.0:
		var dir := d
		dir.y = 0
		dir = dir.normalized()
		var f: float = ROPE_FORCE * strength * minf(over / ROPE_TAKEUP, 1.0) * push_share()
		f *= 1.0 - smoothstep(PUSH_FADE.x, PUSH_FADE.y, linear_velocity.dot(dir))   # 押すときと同じ（人は走るより速く引けない）
		_apply_level(dir * f, anchor - global_position)
		_push_count += 1
		_push_force_now += dir * f
		if rope_holder:
			helped[rope_holder] = _trail_now
	return over




func mount(who: Node3D) -> Vector3:
	if racked or crashed or tipped() or riders.size() >= SEATS.size() or who in riders:   # 打ち上がっている・ひっくり返っているソリには乗れない
		return Vector3.INF
	var at := free_seat(who)
	riders.append(who)
	parked = false
	return at


## ほかの人が座っていない、前からいちばん目の席（通信では、それぞれの画面で座った席がぶつかったときにも使う）。空きがなければ INF
func free_seat(who: Node3D) -> Vector3:
	var used := []
	for r in riders:
		if r != who:
			used.append(r.get("seat"))
	for at in SEATS:
		if not at in used:
			return at
	return Vector3.INF


func dismount(who: Node3D) -> void:
	riders.erase(who)


## 乗っている人の体重移動。乗っている一人ひとりが毎コマ呼ぶ。steer は -1（左）〜1（右）、forward は前傾、back は後傾。
## 力を直接かけるのではなく、滑り木の食い込み（抵抗）が変わることで曲がる・止まる。
## 一人ひとりの力は足し合わさる: 全員が同じ向きなら重なって大きく曲がり、逆向きの人がいると打ち消し合う
func lean(steer: float, forward: bool, back: bool = false) -> void:
	_steer += clampf(steer, -1.0, 1.0)
	_n_fwd += 1 if forward else 0
	_n_back += 1 if back else 0


## 乗っている人が進めようとする向き（地面に沿う。n は雪面の上）。雪をかく（W）のも、米袋を漕ぐ（Space）のも、この向きへ。
## 滑っていれば、いま滑っている向きへ（2026-10-30 代表「後ろ向きでも効かせる」）:
##   ソリの軸に沿って滑っている（前か後ろ。滑り木があるのでたいていそう）なら、軸の前か後ろのうち滑っている側。前向きはこれまでと同じ向き
##   軸から大きく外れて滑っている（横向き・くるくる回っている）なら、速度の水平の向き
## ほとんど動いていなければ（GO_DIR_SPEED まで）、ソリの前の向き。
## 登る向きの分を消す（雪かき）・登りでは蹴れない（漕ぎ）の決まりは、呼ぶ側がこの向きで確かめる
const GO_DIR_SPEED := 0.3
const GO_AXIS_COS := 0.8   # 滑る向きとソリの軸のなす角の cos がこれより大きければ、軸に沿って滑っているとみなす（約 37° まで）


func go_dir(n: Vector3) -> Vector3:
	var fwd := -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var hv := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var d := -global_basis.z   # ソリの前（前向きは、これまでと同じ向き）
	if hv.length() > GO_DIR_SPEED:
		var c := hv.normalized().dot(fwd)
		if absf(c) > GO_AXIS_COS:
			d *= signf(c)   # 軸に沿って、前か後ろの滑っている側
		else:
			d = hv          # 横向き・回りながら: 滑っている向き
	return (d - n * d.dot(n)).normalized()


## 乗っている人が足で雪を蹴る（Space を押すたび）。蹴れたら true
func kick(who: Node3D) -> bool:
	var K: Dictionary = KINDS[kind]
	if K.get("kick", 0.0) <= 0.0 or not riders.has(who) or linear_velocity.length() < KICK_MIN_SPEED or peg:
		return false
	var n := _ground_normal()
	var f := go_dir(n)                     # 地面に沿った、いま滑っている向き（後ろ向き・横向きでも）
	var slope := 0.0                        # 進む向きの下り（sin）。登りなら負
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


## 引き紐の付け根（世界）。ペグに結ぶ紐はここから ROPE_LEN まで届く
func rope_root() -> Vector3:
	return to_global(ROPE_ANCHOR)


## at（雪の面の点、世界）にペグを刺して、引き紐の先を結ぶ。head は玉の色。check なら、紐が届かなければ null
## （つなぐ側がなぞるときは、ソリの姿が少し遅れているので確かめない）
func peg_to(at: Vector3, head: Color, check := true) -> Node3D:
	if check and at.distance_to(rope_root()) > ROPE_LEN + 0.3:
		return null
	unpeg(false)
	if rope_holder and rope_holder.has_method("let_go"):
		rope_holder.let_go()
	var Peg := preload("res://peg.gd")
	peg = Peg.new()
	peg.name = "Peg"
	peg.color = head
	add_child(peg)
	peg.global_transform = Transform3D(Basis(), at)
	peg.drive()
	parked = false
	return peg


## ペグを抜く。show なら抜く動き（先が曲がって倒れ、消える）。ペグは使い切り
func unpeg(show := true) -> void:
	if peg == null or not is_instance_valid(peg):
		peg = null
		return
	var p := peg
	peg = null
	if show:
		p.name = "PulledPeg"
		p.pull_out()
	else:
		p.queue_free()


## ペグに結んだ紐が張ったら、付け根を引き戻す（紐の長さ ROPE_LEN まではたるみで動ける）
func _peg_pull() -> void:
	if peg == null:
		return
	var a := rope_root()
	var d: Vector3 = peg.tie_point() - a
	var over := d.length() - ROPE_LEN
	if over <= 0.0:
		return
	var dir := d.normalized()
	var r := global_basis * ROPE_ANCHOR
	var v_out := -(linear_velocity + angular_velocity.cross(r)).dot(dir)   # 紐を伸ばす向きの速さ
	var f := minf(over * PEG_K * maxf(1.0, _k) + maxf(v_out, 0.0) * mass * PEG_DAMP, PEG_PULL_MAX)
	apply_force(dir * f, r)


## ホストのソリの姿が届いた（net.gd）
func net_put(at: Transform3D, lv: Vector3, av: Vector3) -> void:
	_net_at = at
	_net_v = lv
	_net_w = av
	_net_age = 0.0


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if not net_follow or _net_age < 0.0:
		return
	_net_age += st.step
	var ahead := minf(_net_age, NET_AHEAD)
	var want := _net_at
	want.origin += _net_v * ahead
	if _net_w.length() > 0.001:
		want.basis = Basis(_net_w.normalized(), _net_w.length() * ahead) * want.basis
	var t := st.transform
	if t.origin.distance_to(want.origin) > NET_SNAP:
		t = want
	else:
		t.origin = t.origin.lerp(want.origin, NET_PULL)
		t.basis = Basis(t.basis.get_rotation_quaternion().slerp(want.basis.get_rotation_quaternion(), NET_PULL))
	st.transform = t
	st.linear_velocity = _net_v
	st.angular_velocity = _net_w


## 広げる動きのあいだ（frames コマ）、止めて見た目を隠しておく（craft.gd が折り紙の形を見せる）
func hold_still(frames: int) -> void:
	freeze = true
	visible = false
	await get_tree().create_timer(frames / 12.0).timeout
	if is_instance_valid(self):
		freeze = false
		visible = true
		parked = true


## 名札を付け直す（ソリの名札の柄を替えた・外した・付けたとき。craft.gd）。米袋には付けない
func retag(d) -> void:
	if kind == "sack":
		d = -1
	tag = d
	var old := get_node_or_null("Tag")
	if old:
		old.name = "OldTag"
		old.queue_free()
	if rope == null or not preload("res://sled_tags.gd").has_tag(d):
		return
	var tg: Node3D = preload("res://sled_tags.gd").hang(self, rope._ties[1] + Vector3(0.02, -0.02, 0), d, clampf(HALF.x * 0.32, 0.16, 0.26))
	tg.rotation.y = PI / 2   # 紙の面を外（横）へ向ける
	_tag_y0 = tg.position.y
	tg.position.y += vis_lift


## 名札を吊るす結び目（世界の座標）。名札を外す・付けるのは、ここのそばで
func tag_point() -> Vector3:
	return vis_point(rope._ties[1] + Vector3(0.02, -0.1, 0)) if rope else global_position


## 乗っている人を降ろし、つかんでいる人と紐を持っている人の手を離させる
func let_everyone_go() -> void:
	for r in riders.duplicate():
		if r.has_method("get_off"):
			r.get_off()
	for who in holders.keys():
		if who.has_method("let_go"):
			who.let_go()
	if rope_holder and rope_holder.has_method("let_go"):
		rope_holder.let_go()


## 立てかけ台の姿 at へ移す。wait 秒のあいだは隠しておき（山で畳まれた包みが飛んでくる間）、ぽんと現れる
func rack_in(at: Transform3D, wait := 0.0) -> void:
	let_everyone_go()
	unpeg(false)
	if _trail_used > 0:   # 雪の上の跡は、ソリを隠しているあいだも、台にあるあいだも残る
		_retire_trail()
		_make_trail()
	racked = true
	parked = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = at
	reset_physics_interpolation()
	if wait <= 0.0:
		return
	visible = false
	await get_tree().create_timer(wait).timeout
	if not is_instance_valid(self):
		return
	visible = true
	if _body:
		for k in [0.4, 1.08, 0.97, 1.0]:   # 12 コマ／秒で 4 コマ
			_body.scale = Vector3.ONE * k
			await get_tree().create_timer(1.0 / 12.0).timeout
			if not is_instance_valid(self):
				return


## 立てかけ台から前の雪の上へ、コマ撮りで倒して置く（12 コマ／秒で 8 コマ）。降りたら landed を呼ぶ
func rack_out(to: Transform3D, landed := Callable()) -> void:
	var a := global_transform
	var qa := a.basis.get_rotation_quaternion()
	var qb := to.basis.get_rotation_quaternion()
	const N := 8
	for i in range(1, N + 1):
		await get_tree().create_timer(1.0 / 12.0).timeout
		if not is_instance_valid(self):
			return
		var t := float(i) / N
		t = t * t * (3.0 - 2.0 * t)
		global_transform = Transform3D(Basis(qa.slerp(qb, t)), a.origin.lerp(to.origin, t) + Vector3.UP * sin(t * PI) * 0.25)
	global_transform = to
	reset_physics_interpolation()
	racked = false
	freeze = false
	parked = true
	if landed.is_valid():
		landed.call()


func reset_to(pos: Vector3) -> void:
	let_everyone_go()
	unpeg(false)   # ふもとへ戻すときは、刺さっていたペグもなくなる
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(), pos + Vector3.UP * place_lift())
	parked = true


## 坂に水平に置くとき、地面からこれだけ余分に浮かせる (m)。呼ぶ側は地面の 0.3 m ほど上に置くので、その分は引く。
## 長いソリ（大は 4.8 m）を坂に水平に置くと、下の端が雪に埋まり、地面を突き抜けて落ちることがあるため（丘のいちばん急な傾き 0.44 で足りる高さ）
func place_lift() -> float:
	var k: Dictionary = KINDS.get(kind, KINDS.mid)
	return maxf(0.0, k.box.z * 0.5 * 0.45 - 0.3)


## ソリが消えるとき、まだ場面へ足していない塊（子になっていないので、ひとりでには消えない）を片づける
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for mi in _trails:
			if is_instance_valid(mi) and mi.get_parent() == null:
				mi.free()


## 滑り木の跡のステッチ（毛糸の雪に残る針目）
func _make_trail() -> void:
	_stitch_name = stitch_kind()
	_st = STITCHES[_stitch_name]
	_trail_n = TRAIL_N * int(_st.per)
	_trail_chunk = TRAIL_CHUNK * int(_st.per)
	_stitch = Look.stitch_mesh(color())   # 糸はソリのメインカラー
	Look.stitch_set_shape(_stitch, _st.radius, _st.bow)
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
		mi.lod_bias = 5.0 if _st.get("arc", false) else 1.0   # 弧の目は、粗い形だと角ばる
		mi.top_level = true
		mi.visible = false
		_trails.append(mi)   # 場面へ足すのは、初めて目を縫うとき（_emit）。使わない塊まで足すと、ソリを出すたびに数 ms かかる
	_trail_end.resize(_trail_n)
	_trail_end.fill(-1.0)
	_chunk_end.resize(_trails.size())
	_chunk_end.fill(-1.0)
	_trail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_trail_noise.frequency = 1.0 / TRAIL_PATCH_SIZE
	_trail_noise.seed = randi()


## from の真下の地面。人や別のソリには縫わない（動かない物だけを地面とする）
func _ground_hit(from: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	var skip: Array[RID] = [get_rid()]
	var space := get_world_3d().direct_space_state
	for i in 4:
		q.exclude = skip
		var h := space.intersect_ray(q)
		if h.is_empty() or h.collider is StaticBody3D:
			return h
		skip.append(h.rid)
	return {}


## 当たったのが雪の地面（高さの表）か。ジャンプ台などは当たりと見た目が同じ形なので、吹きだまりを足さない
static func _is_snow(h: Dictionary) -> bool:
	var body: Node = h.collider
	return body.get_child_count() > 0 and body.get_child(0) is CollisionShape3D and (body.get_child(0) as CollisionShape3D).shape is HeightMapShape3D


## 滑りあとの目が、消えるまでの時間のまんなか (s)。重いソリ（乗っている人も入れる）ほど長い
func trail_life() -> float:
	var life := TRAIL_LIFE * pow(load_mass() / TRAIL_LIFE_MASS, TRAIL_LIFE_POW)
	return clampf(life, TRAIL_LIFE_RANGE.x, TRAIL_LIFE_RANGE.y)


## 次の目を置く番号。塊はいつも続いた跡だけを持つ。満ちたら、または離れた所へ来たら、次の塊へ移る
func _trail_slot(a: Vector3) -> int:
	var mm := _trails[_chunk_i].multimesh
	if _chunk_fill >= mm.instance_count or (_chunk_fill > 0 and a.distance_to(_chunk_from) > TRAIL_CHUNK_SPAN):
		_next_chunk()
		mm = _trails[_chunk_i].multimesh
	if _chunk_fill == 0:
		_chunk_from = a
	var slot := _chunk_i * _trail_chunk + _chunk_fill
	_chunk_fill += 1
	mm.visible_instance_count = _chunk_fill
	_trail_used = maxi(_trail_used, slot + 1)
	return slot


## 次の塊へ: 先の塊から順に見て、消えきった塊。なければいちばん早く消える塊を丸ごと使い回す（跡のいちばん古い端が消える）
func _next_chunk() -> void:
	var n := _trails.size()
	var best := (_chunk_i + 1) % n
	for j in range(1, n + 1):
		var c := (_chunk_i + j) % n
		if _chunk_end[c] <= _trail_now:
			best = c
			break
		if _chunk_end[c] < _chunk_end[best]:
			best = c
	_chunk_i = best
	_chunk_fill = 0
	_chunk_end[best] = -1.0
	var mm := _trails[best].multimesh
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB()
	for i in mm.instance_count:
		_trail_end[best * _trail_chunk + i] = -1.0


## 塊の広がりに、目 a〜b を足す。描く・描かないは、塊のこの箱で決まる（エンジンに数えさせると、箱が世界の原点まで広がることがある）
func _chunk_grow(mm: MultiMesh, a: Vector3, b: Vector3) -> void:
	var one := AABB(a, Vector3.ZERO).expand(b).grow(0.3)
	var box := mm.custom_aabb
	if box.size == Vector3.ZERO:
		mm.custom_aabb = one.grow(1.0)
	elif not box.encloses(one):
		mm.custom_aabb = box.merge(one.grow(1.0))


func _update_trail(dt: float) -> void:
	if _stitch == null:
		return
	_trail_now += dt
	Look.stitch_set_time(_stitch, _trail_now)
	for c in _trails.size():
		if _trails[c].visible and _chunk_end[c] <= _trail_now and c != _chunk_i:
			_trails[c].visible = false
	# 遠くのソリは跡を作らない（レイも目も増やさない）
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_squared_to(global_position) > TRAIL_MAKE * TRAIL_MAKE
	if crashed and global_position.y > get_parent().height(global_position.x, global_position.z) + 1.0:
		far = true   # 打ち上がって宙にいるあいだも縫わない
	# ステッチ: 左右の滑り木の後ろ端が滑った道のりを 1 歩（TRAIL_STEP）ずつに刻み、そのたびに雪面を探して、
	# 前の歩みからそこまでを、ソリの縫い目（なみ縫い・くさり縫い・サドルステッチ…）で縫う。
	# 速くてもコマの刻みに左右されず、どの目も同じ長さになる。遅いあいだは数えないだけで、また滑り出せば前の目から続く
	for k in 2:
		var w := to_global(Vector3(-RUNNER_X if k == 0 else RUNNER_X, 0.0, RUNNER_Z))
		var last: Vector3 = _trail_last[k]
		_trail_last[k] = w
		if last == Vector3.INF:
			continue
		var move := w - last
		var ln := move.length()
		if far or racked or ln > TRAIL_JUMP:   # 台にある・台から降りるあいだは縫わない
			_trail_holes[k] = Vector3.INF
			_trail_dist[k] = 0.0
			continue
		if ln < TRAIL_SLOW * dt:
			continue
		var next: float = TRAIL_STEP - _trail_dist[k]
		while next <= ln:
			_trail_step(k, last + move * (next / ln), move / ln)
			next += TRAIL_STEP
		_trail_dist[k] = ln - (next - TRAIL_STEP)


## 滑り木 k の 1 歩: at（滑り木の後ろ端）の下の雪面を探し、前の歩みからそこまでを縫う。dir は滑る向き
func _trail_step(k: int, at: Vector3, dir: Vector3) -> void:
	_trail_count[k] += 1
	var h := _ground_hit(at + Vector3.UP * 0.8)
	if h.is_empty() or at.y - float(h.position.y) > TRAIL_AIR:   # 宙を飛んでいる（着地したら、そこから縫い始める）
		_trail_holes[k] = Vector3.INF
		return
	var nn: Vector3 = h.normal
	var c: Vector3 = h.position
	var plane := Vector4.ZERO
	var on_snow := _is_snow(h)
	if on_snow and snow_plane.is_valid():   # 見た目の雪面の三角の上に載せる
		plane = snow_plane.call(c.x, c.z)
		nn = Vector3(plane.x, plane.y, plane.z)
		c.y = plane.w
	elif on_snow and snow_lift.is_valid():
		c.y += snow_lift.call(c.x, c.z)
	var d := (dir - nn * dir.dot(nn)).normalized()
	var jit: Vector3 = d.cross(nn) * _trail_rng.randf_range(-TRAIL_JITTER, TRAIL_JITTER) + d * _trail_rng.randf_range(-TRAIL_JITTER, TRAIL_JITTER)
	var prev: Vector3 = _trail_holes[k]
	var prev_jit: Vector3 = _trail_jit[k]
	if prev == Vector3.INF:
		_trail_holes[k] = c
		_trail_jit[k] = jit
		return
	var len := prev.distance_to(c)
	if len < TRAIL_LEN.x:
		return                    # ほとんど進んでいない。次の歩みで縫う
	_trail_holes[k] = c
	_trail_jit[k] = jit
	if len > TRAIL_LEN.y:
		return
	# 三角の継ぎ目で雪面が目のまんなかより高いときは、そのぶん糸を上げる（雪に潜らない）
	var crown := 0.0
	if plane != Vector4.ZERO:
		var mid := (prev + c) * 0.5
		var top: Vector4 = snow_plane.call(mid.x, mid.z)
		crown = clampf(top.w - mid.y, 0.0, 0.12)
	_sew(prev + Vector3.UP * crown, c + Vector3.UP * crown, prev_jit, jit, nn, k)


## 前の歩み p0 から p1 までを、いまの縫い目で縫う。j0・j1 は針穴のばらつき、nn は雪面の上。柄の形は stitches.gd
func _sew(p0: Vector3, p1: Vector3, j0: Vector3, j1: Vector3, nn: Vector3, k: int) -> void:
	var side := (p1 - p0).normalized().cross(nn).normalized()
	Stitches.sew(_stitch_name, func(a: Vector3, b: Vector3, bow: int) -> void: _emit(a, b, nn, bow),
			p0, p1, j0, j1, side, _trail_count[k], -1.0 if k == 0 else 1.0)


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
	var slot := _trail_slot(a)
	var ci := slot / _trail_chunk
	_trail_end[slot] = _trail_now + life
	_chunk_end[ci] = maxf(_chunk_end[ci], _trail_now + life)
	var chunk := _trails[ci]
	if chunk.get_parent() == null:
		add_child(chunk)
	var mm := chunk.multimesh
	var j := slot % _trail_chunk
	_chunk_grow(mm, a, b)
	mm.set_instance_transform(j, Transform3D(bs, a + nn * 0.012))
	# y は 位相（0〜1）＋ 弧の向き（整数）
	mm.set_instance_custom_data(j, Color(len, _trail_rng.randf() * 0.999 + bow, fade, _trail_now + life - fade))
	chunk.visible = true


func _ground_normal() -> Vector3:
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_ground_gap = global_position.y - float(hit.position.y) if hit else INF
	return hit.normal if hit else Vector3.UP


## 宙にいる時間を数え、着いたら 1 回はね返す（乗って滑っているあいだ、_ride_forces から毎コマ）。n は下の当たりの向き
func _air_step(dt: float, n: Vector3) -> void:
	var vn := -linear_velocity.dot(n)   # 雪面へ向かう速さ
	if _ground_gap > AIR_GAP:
		air_t += dt
		_air_vn = maxf(vn, 0.0)
		_touch_t = 0.0
		return
	if air_t <= 0.0:
		return
	if vn > 0.5 and _touch_t < 0.2:   # 雪面のすぐ上で、まだ落ちている。当たりが受け止めてから、はね返す（先に押し上げると、ただ弱く着くだけになる）
		_touch_t += dt
		air_t += dt
		_air_vn = maxf(_air_vn, vn)
		return
	if air_t > AIR_MIN_T and _air_vn > LAND_MIN_V:
		land_v = _air_vn
		land_n += 1
		apply_central_impulse(n * mass * minf(land_v * LAND_BOUNCE, LAND_BOUNCE_MAX))
	air_t = 0.0
	_touch_t = 0.0


## 乗って下っているときの力。ソリと乗っている人は一緒に動くので、重力は同じ加速で、ほかの力（雪の抵抗・沈み・体重移動）は
## 「体の重さ / ソリと乗る人の重さ」の割合でかける（物理の体はソリの重さだけなので、乗る人の重さぶん効きを弱める）。
## 雪をこする抵抗（drag）は重さによらないので、重いほど抵抗に負けにくく、最高速度が速い。滑り木のソリは出足で雪に沈む（sink）。
## 曲がる力は一人ひとりの体重移動の合計。ソリが長く重いほど回りにくい（回りにくさは当たりの箱から物理で出る）
func _ride_forces(dt: float, fwd: Vector3) -> void:
	var K: Dictionary = KINDS[kind]
	var share := mass / load_mass()
	var n := _ground_normal()
	_air_step(dt, n)
	var v_t := linear_velocity - n * linear_velocity.dot(n)
	var vs := v_t.length()
	if vs > 0.01:
		var ease := 1.0 - FWD_LEAN_EASE * float(mini(_n_fwd, riders.size())) / riders.size()
		# 沈むのは滑り出しと止まりぎわだけ。plane まで速くなって浮いたら、UNPLANE_SPEED に落ちるまで沈まない（減速のときに急に重くならない）
		if vs >= K.plane:
			_planed = true
		elif vs < UNPLANE_SPEED:
			_planed = false
		var sink: float = 0.0 if _planed else K.sink * load_mass() * 9.8 * absf(n.y) * (1.0 - smoothstep(0.0, K.plane, vs))
		var resist: float = ((K.drag * vs + K.push * vs * vs) * ease + sink) * glide
		apply_central_force(-v_t / vs * minf(resist * share, vs * mass / dt))
		_uphill_brake(dt, v_t)
	if pull > 0.0 and n.y < 0.9995:   # 坂を下る向き（重力の、雪面に沿った分）に足す
		apply_central_force((Vector3.DOWN - n * Vector3.DOWN.dot(n)) * 9.8 * pull * mass)
	var w := get_parent()
	# ジャンプ台の通り道では跳ねさせない（台は地形とは別の当たりで、台の上が「雪面から浮いた」に見える。main.gd の on_jump_lane）。
	# 浮いたソリを雪面へ引き戻す力は、2026-11-14 に外した（起伏を越えて落ちるとき、ふつうの重力で飛ぶ。上の「宙と着地」）
	if bumps > 0.0 and vs > BUMP_MIN and not (w and w.has_method("on_jump_lane") and w.on_jump_lane(global_position.x, global_position.z)):
		_bump(n, vs)
	for x in [-RUNNER_X, RUNNER_X]:
		var r := global_basis * Vector3(x, 0, 0)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var v_long := v_point.dot(fwd)
		var c := BRAKE_DRAG * _n_back
		if _steer * signf(x) > 0.0:
			c += LEAN_DIG * K.turn * absf(_steer)
		apply_force(-fwd * v_long * c * share, r)


## 雪面の小さな隆起で跳ねる（bumps）。升をまたいだコマだけ見る
func _bump(n: Vector3, vs: float) -> void:
	var p := global_position
	var cell := Vector2i(floori(p.x / BUMP_CELL), floori(p.z / BUMP_CELL))
	if cell == _bump_cell:
		return
	_bump_cell = cell
	var h := fposmod(sin(cell.x * 127.1 + cell.y * 311.7) * 43758.5453, 1.0)
	if h > BUMP_CHANCE:
		return
	var w := get_parent()
	if w == null or not w.has_method("height") or p.y - w.height(p.x, p.z) > HALF_H_ON_SNOW:
		return   # 宙にいるあいだは跳ねない
	var k := (0.5 + h / BUMP_CHANCE) * bumps
	apply_central_impulse(n * mass * minf(vs * BUMP_UP, BUMP_UP_MAX) * k)
	angular_velocity += global_basis.x * (fposmod(h * 7.0, 1.0) - 0.4) * BUMP_PITCH * k   # 前へつんのめる・後ろへのけぞる（回りの弱まりですぐ収まる）
	angular_velocity += global_basis.z * (fposmod(h * 13.0, 1.0) - 0.5) * 2.0 * BUMP_ROLL * k   # 左右にがくっと傾く
	bump_n += 1


## 上り斜面の減速。地形の傾きと進む向きから、登っている分だけ重力を足す（UPHILL_K）。宙にいるあいだは効かない
func _uphill_brake(dt: float, v_t: Vector3) -> void:
	var w := get_parent()
	if w == null or not w.has_method("ground_normal"):
		return
	var p := global_position
	if p.y - w.height(p.x, p.z) > 1.0:
		return
	var along := Vector3(v_t.x, 0.0, v_t.z)
	if along.length() < 0.05:
		return
	along = along.normalized()
	var tn: Vector3 = w.ground_normal(p.x, p.z)
	var rise := -(tn.x * along.x + tn.z * along.z) / maxf(tn.y, 0.01)   # 進む向きの上り（tan）
	if rise <= 0.0:
		return
	var sin_a := rise / sqrt(1.0 + rise * rise)
	var vs := v_t.length()
	apply_central_force(-v_t / vs * minf(UPHILL_K * 9.8 * sin_a * mass, vs * mass / dt))


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


## 安全網: 地面の下へ落ちていたら、その場の雪の上へ戻す（向きは保ち、水平の速さは残す）。乗っている人は席についてくる。
## 通信ではホストの画面だけが決める（つなぐ側のソリはホストの姿を写すので、戻った姿も届く）
func _catch_fall() -> void:
	var w := get_parent()
	if net_follow or freeze or w == null or not w.has_method("height"):
		return
	var p := global_position
	var g: float = w.height(p.x, p.z)
	if p.y > g - FALL_NET:
		return
	var fwd := -global_basis.z
	fwd.y = 0.0
	var yaw := atan2(-fwd.x, -fwd.z) if fwd.length() > 0.01 else rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, g + 0.3 + place_lift(), p.z))
	linear_velocity = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
	print("ソリが地面の下へ落ちたので、雪の上へ戻した: %s (%.1f, %.1f)" % [kind, p.x, p.z])


## 地面の端の吹きだまり: 端へ向かう速さを、EDGE_STOP の手前で止まれるだけ弱める。沿って滑る・戻るのは邪魔しない（どんなに速くても地面の外へ出ない）
func _edge_drift(dt: float) -> void:
	var w := get_parent()
	if w == null or not w.has_method("edge_gap"):
		return
	var p := global_position
	var gap: float = w.edge_gap(p.x, p.z)
	if gap >= EDGE_DRIFT:
		return
	var e := 0.5
	var out := Vector3(w.edge_gap(p.x - e, p.z) - w.edge_gap(p.x + e, p.z), 0.0, w.edge_gap(p.x, p.z - e) - w.edge_gap(p.x, p.z + e))
	if out.length() < 0.01:
		return
	out = out.normalized()
	var v_out := linear_velocity.dot(out)
	if gap < EDGE_STOP:   # ここより外へは行かない（乗ったまま雪をかいても、押しても）。少しずつ内へ戻す
		var back := EDGE_STOP - gap
		if v_out > -back:
			linear_velocity -= out * (v_out + back)
		return
	if v_out <= 0.0:
		return
	var decel := v_out * v_out / (2.0 * maxf(gap - EDGE_STOP, 0.1))
	apply_central_force(-out * minf(decel, v_out / dt) * mass)


## 雪の塊に入った（sled_crash.gd。ホストのソリだけ）。速ければ打ち上がり、乗っている人を放り投げる
func crash_lump(lump: Node3D) -> void:
	if net_follow or crashed or racked or freeze or peg or not visible or pushers > 0 or not holders.is_empty():
		return
	var flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if flat.length() < CRASH_SOFT_SPEED:
		return
	_launch(flat, flat * CRASH_KEEP, global_position + Vector3.UP * 0.7, lump)


## 打ち上がる。v はぶつかる前の速さ（水平）、keep は残る水平の速さ、point は雪の粉の所。ホストのソリが呼び、乗っている人の飛び方と雪の粉を全員へ配る
func _launch(v: Vector3, keep: Vector3, point: Vector3, lump: Node3D = null) -> void:
	crashed = true
	_crash_t = 0.0
	_crash_still = 0.0
	var hub = get_parent().get_node_or_null("Emotes")
	if hub:
		for ev in Flung.throw_events(self, v, point):
			hub.send(ev)
		var ev := {"kind": "crash", "sled": get_parent().get_path_to(self), "point": point}
		if lump:
			ev["lump"] = get_parent().get_path_to(lump)
		hub.send(ev)
	for who in holders.keys():
		if who.has_method("let_go"):
			who.let_go()
	if rope_holder and rope_holder.has_method("let_go"):
		rope_holder.let_go()
	var speed := v.length()
	linear_velocity = keep + Vector3.UP * lerpf(CRASH_UP.x, CRASH_UP.y, clampf(inverse_lerp(CRASH_UP_AT.x, CRASH_UP_AT.y, speed), 0.0, 1.0))
	var spin := clampf(speed, CRASH_SPIN.x, CRASH_SPIN.y)
	angular_velocity = global_basis.x * spin * (1.0 if randf() < 0.5 else -1.0) + global_basis.z * spin * randf_range(-0.7, 0.7)
	angular_damp = CRASH_SPIN_DAMP


## 出来事 "crash" が届いた（どの画面でも）
func crash_seen() -> void:
	crashed = true
	_crash_t = 0.0


## 打ち上がってから止まるまでの 1 コマ。滑り木も体重移動も効かない。雪面にいれば、どの向きでも坂に沿って滑る（雪の抵抗は、平らな所を滑る空のソリと同じ）
func _crash_step(dt: float) -> void:
	_crash_t += dt
	_steer = 0.0
	_n_fwd = 0
	_n_back = 0
	_crash_still = _crash_still + dt if linear_velocity.length() < 0.3 else 0.0
	if net_follow:
		if _crash_still > CRASH_REST:
			crashed = false
		return
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	var w := get_parent()
	if _crash_t > 0.3 and global_position.y - w.height(global_position.x, global_position.z) < 1.0:
		angular_damp = CRASH_LAND_DAMP
		var n := _ground_normal()
		var v_t := linear_velocity - n * linear_velocity.dot(n)
		if v_t.length() > 0.01:
			var resist: float = GLIDE_GRIP * mass * 9.8 * absf(n.y) + GLIDE_DRAG * v_t.length()
			apply_central_force(-v_t.normalized() * minf(resist, v_t.length() * mass / dt))
	_edge_drift(dt)
	if _crash_still > CRASH_REST or _crash_t > CRASH_MAX or not holders.is_empty() or rope_holder or pushers > 0:
		_crash_end()


## ふつうのソリに戻る。ひっくり返っていれば、長いソリも回りきれるだけ高く跳ねて起き直る（乗れる・押せるように）
func _crash_end() -> void:
	crashed = false
	angular_damp = 6.0
	if global_basis.y.y >= 0.5:
		return
	_right_up()


## 跳ねて起き直る（長いソリも回りきれるだけ高く）。打ち上がったあとと、縦や横倒しのまま戻らないとき
func _right_up() -> void:
	var up := global_basis.y
	var axis := up.cross(Vector3.UP)
	axis = axis.normalized() if axis.length() > 0.05 else global_basis.z
	var t := 2.0 * sqrt(2.0 * (HALF.y + 0.3) / 9.8)
	_right_t = t
	angular_damp = 0.0
	angular_velocity = axis * acos(clampf(up.y, -1.0, 1.0)) / t
	linear_velocity = Vector3.UP * 9.8 * t * 0.5


## 乗って滑っていて、次のコマで木の幹にぶつかるなら、乗っている人を放り投げる（ソリの物理を持つホストの画面だけ。向きと強さを決めて配る。flung.gd）。
## 幹の当たりで速さが消える前に見つけるので、ぶつかる前の速さを渡せる。ソリは幹で止まり、そのままそこに残る（空のソリの決まりでずり落ちる）。
## 迫る速さが Flung.CRASH_MIN より遅い・横をかすめるだけなら、何もしない（乗ったまま、物理で止まる・それる）
func _check_crash(dt: float) -> void:
	_crash_cool = maxf(0.0, _crash_cool - dt)
	if net_follow or crashed or peg or _crash_cool > 0.0:
		return
	var v := linear_velocity
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length() < Flung.CRASH_MIN:
		return
	if _crash_q == null:
		_crash_q = PhysicsShapeQueryParameters3D.new()
		_crash_q.shape = _box_col.shape
		_crash_q.collision_mask = TreeHits.LAYER
	var at := global_transform * _box_col.transform
	at.origin += v * dt
	_crash_q.transform = at
	for r in get_world_3d().direct_space_state.intersect_shape(_crash_q, 4):
		var trunk: TreeHits = r.collider
		var c: Vector3 = to_local(trunk.trunk_at(r.shape) - v * dt)   # 次のコマの箱から見た幹
		var near := Vector3(clampf(c.x, -HALF.x, HALF.x), 0.0, clampf(c.z, -HALF.y, HALF.y))
		var off := Vector3(c.x - near.x, 0.0, c.z - near.z)
		if off.length() > trunk.radius_at(r.shape) + 0.02:
			continue   # 問い合わせの余白で引っかかっただけ。本当に触れたときの向きで見る（かすめただけを正面と間違えない）
		var n: Vector3 = global_basis * off
		n.y = 0.0
		n = n.normalized() if n.length() > 0.01 else flat.normalized()
		if flat.dot(n) < Flung.CRASH_MIN:
			continue
		_crash_cool = 1.0
		_launch(flat, (flat - n * 2.0 * flat.dot(n)) * CRASH_BOUNCE, to_global(near) + Vector3.UP * 0.7)
		return


func _physics_process(dt: float) -> void:
	_catch_fall()
	_update_trail(dt)
	_lift_dt += dt
	_lift_tick += 1
	if not Doll.thin_far or (_lift_tick + get_instance_id()) % VIS_LIFT_FAR_EVERY == 0 or Doll.view_lod(self, global_position) == 0:
		_update_vis_lift(_lift_dt)
		_lift_dt = 0.0
	if racked:
		return
	_check_crash(dt)
	pushers = _push_count
	_push_count = 0
	_push_force = _push_force_now
	_push_force_now = Vector3.ZERO
	_pushed_by = _pushed_now
	_pushed_now = {}
	if _right_t > 0.0:
		_right_t -= dt
		if _right_t <= 0.0:
			angular_damp = 6.0
			angular_velocity = Vector3.ZERO
	if crashed:
		air_t = 0.0
		_update_drag(dt)
		_crash_step(dt)
		return
	var riding := riders.size() > 0
	# 押されて坂を登っている間は、乗っている人がいても登りの雪の抵抗。乗るだけで登りが速くならないように。
	# 坂の上へ向けて押されていてまだ遅い（DRAG_STOP_SPEED より遅い）ときも同じ（2026-11-08。乗っている人の重さで押す力が弱まると、
	# 急な所で上へ動けずに滑り出しの沈み（KINDS の sink）がかかり、押してもほとんど進まなくなっていた）。
	# 平らな所や下りへ押し出すときは前のまま（乗って滑る抵抗）
	var pushed_up := pushers > 0 and (linear_velocity.y > 0.05 or (linear_velocity.length() < DRAG_STOP_SPEED and _pushing_uphill()))
	# 乗って下っている: 雪をこする抵抗・沈み・体重移動は、ソリと乗る人をまとめた重さで動かす（_ride_forces）
	var descent := riding and not pushed_up
	# 誰も押していない空のソリは、ずり落ちる雪の抵抗（つかまれていても同じ。止める力はつかんだ人が出す）
	# 乗って滑っているあいだは、物理の既定の減衰（project の default_linear_damp。遅いときから効く）も消す。雪の抵抗は _ride_forces だけ
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE if descent else RigidBody3D.DAMP_MODE_COMBINE
	if descent:
		linear_damp = 0.0
	elif pushers > 0 or parked or peg:
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
	# 縦や横倒しのあいだは、滑り木は雪に着いていないので効かせない（傾いた滑り木の横滑りを止める力が翼のように上向きにかかり、
	# 押されて傾いたソリが人ごと宙を飛んでいた）
	var on_runners := global_basis.y.y >= TIP_UP
	for z in ([-RUNNER_Z, RUNNER_Z] if on_runners else []):
		var r := global_basis * Vector3(0, 0, z)
		var v_point := linear_velocity + angular_velocity.cross(r)
		var slip := side * v_point.dot(side)
		apply_force(-slip * mass * slip_k * 0.5, r)
	# 左右の滑り木の前後方向の抵抗。体重をかけた側が雪に食い込んで抵抗が増え、曲がる。
	# 後ろに体重をかけると両側が食い込んで止まる
	if not (descent and on_runners):
		air_t = 0.0   # 宙と着地を数えるのは、乗って滑っているあいだだけ（_air_step）
	if not on_runners:
		pass
	elif descent:
		_ride_forces(dt, fwd)
	else:
		# 押して登っているとき（乗っている人がいても）は前の作りのまま。乗っている人の重さは、押す・引く力の側で効かせる（push_share）
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
	# 乗っている人がいても押されていれば効く（乗っている人の重さの分、押す力が弱まるので、一人で押すより遅く登る。push_share）。
	# 押されていなければ、留める力は「つかんでいる人の止める力」と「空のソリの雪の摩擦」まで。
	# 誰も触れていない空のソリは雪の摩擦だけなので、急な所ではずり落ち、緩い所（ふもと）で止まる
	var speed := linear_velocity.length()
	var n := _ground_normal()
	var brakers := _brakers()
	# 空のソリの雪の摩擦は、押されていないときだけ（押して登るときの雪の抵抗は CLIMB_DAMP に入っている）
	var snow: float = 0.0 if riding or pushers > 0 else SLIDE_GRIP * mass * 9.8 * abs(n.y)
	if speed < DRAG_STOP_SPEED and (pushers > 0 or parked or brakers > 0 or not riding or peg):
		var g := Vector3(0, -9.8, 0)
		var g_t := g - n * g.dot(n)
		var hold := -g_t * mass
		var cap: float = (PEG_HOLD if peg else HOLD_FRICTION) * mass * 9.8 * abs(n.y)
		if pushers == 0 and not parked and not peg:
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
		# 動いている空のソリの雪の抵抗は、平らな所ほど弱い（坂の傾き tan が SLIDE_GRIP 以上なら前のまま）
		var steep: float = smoothstep(0.0, SLIDE_GRIP, sqrt(maxf(1.0 - n.y * n.y, 0.0)) / maxf(absf(n.y), 0.01))
		var stop: float = brakers * STOP_FORCE * mass / load_mass() + snow * lerpf(GLIDE_GRIP / SLIDE_GRIP, 1.0, steep)
		if not riding and pushers == 0 and not parked and not peg:
			stop += lerpf(GLIDE_DRAG, SLIDE_DRAG, steep) * v_t.length()
		if v_t.length() > 0.01 and stop > 0.0:
			apply_central_force(-v_t.normalized() * minf(stop, v_t.length() * mass / dt))
		hold_debug = "なし(速さ%.2f 押%d/%d 乗%d 止%d)" % [speed, _push_count, pushers, riders.size(), brakers]
	# 頂上などで、乗ったまま前傾すると手で雪をかいて動き出す。
	# 雪をかく力は坂を登る向きには効かない（平らな所と下りでだけ進む）。乗って W で登ると、降りて押すより速くなるため
	_peg_pull()
	_edge_drift(dt)
	if riding and _n_fwd > 0 and speed < 1.5 and not peg:
		var f := go_dir(n)                                      # 地面に沿った、いま滑っている向き（ほとんど止まっていれば前）
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
	# それでも縦や横倒しのまま TIP_WAIT 続いたら、つかんでいる・紐を持っている・乗っている人の手を離させ、跳ねて起き直る
	# （傾いたソリの席やつかみ所に付いた人は、ソリの向きのまま宙に浮く。人が離れれば、押されて立ったままにもならない）
	_tip_t = _tip_t + dt if up.y < TIP_UP and _right_t <= 0.0 and not net_follow and not freeze else 0.0
	if _tip_t > TIP_WAIT:
		_tip_t = 0.0
		let_everyone_go()
		_right_up()
