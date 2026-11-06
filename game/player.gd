extends CharacterBody3D

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")
const FpHands := preload("res://fp_hands.gd")
const Emotes := preload("res://emotes.gd")
const EmoteRing := preload("res://emote_ring.gd")
const Palm := preload("res://palm.gd")
const SackLook := preload("res://sack_look.gd")
const Seats := preload("res://seats.gd")
const FoodMenu := preload("res://food.gd")
const HoldTag := preload("res://hold_tag.gd")
const TableEat := preload("res://table_eat.gd")
const PropsLib := preload("res://props.gd")
const Campfire := preload("res://campfire.gd")
## あなた。一人称で、見えるのは自分の人形と同じ柄の袖口と、紙の手だけ。
## ソリのまわりのどこからでも F でつかめる。
## つかんだまま WASD で、見ている向きを基準にソリへ力をかける（W 前へ押す、S 手前へ引く、A/D 左右へ）。
## どう動くかはソリの滑り木と重力が決める。離すのは F だけ。Shift でダッシュ。
## 前に回って F を押すと紐を持ち、歩いて引ける。
## 身ぶり: Tab を押しているあいだ輪が出て、マウスの向きで選び、離すと出す。輪と同じ 6 つを 1〜6 キーでも:
## 1 高い手のひら、2 低い手のひら、3 指さし、4 ウン、5 ンーン、6 首をかしげてウン？、7 おーーーい（遠くへ呼ぶ）。手のひらは下ろすまで掲げたまま、
## 腕は見ている向きへ。手は Q で片手⇄両手、X で右⇄左。滑りながら高い両手のひらにすると、ひとりでに「ワ〜」。B を押しているあいだ、白い息を長く吐く（押した瞬間に短く吸う）。
## 左 Ctrl を押しているあいだしゃがむ。しゃがんで F で、雪玉を丸める（一人称は雪面を見て。三人称は足もとの少し先の雪面で）。
## 左クリック: 雪玉を持っていれば押してためて（振りかぶり）、離して投げる（長く押すほど遠くへ）。両手のひらなら拍手。
## 持ち物（craft.gd）: ホイールか、トラックパッドの二本指スクロールか、Z（Shift+Z で逆）で手に持つ物を替える
## （素手 → 持ち物 → …。持ち物がないときと Alt を押しているときは、ホイールは視野角。視野角はトラックパッドならピンチ）。
## 売り子のおじさんの前で F で売り台を開く。ミシンの前で F か T でミシンの画面を開き、持ち物から型紙と布を選んで縫う。
## 米袋は装備（craft.gd の sacks）: N で、いま選んでいる米袋を足もとにぽんと出して、すぐ乗る（坂ならそのまま滑り出す）。
## もう一度 N で降りて、くるっと丸めて帯に戻す。離れた所に出したままなら、N で足もとへ呼び戻す。
## 出すときは、帯の丸めた袋を引き抜いて前へ広げ、しゃがんで腰を下ろし、前の紐を握る（人形のコマ。doll.gd の sack_start）。
## 乗るのは押した瞬間なので、坂ならその途中から滑り出し、Space で蹴ればすぐ座った姿になって漕げる。
## 走りながら（歩きながら）出すと、前へ飛び乗る勢いで滑り出す（SACK_CARRY）。平らな所でも少し滑ってから止まる。
## 乗っているあいだの Space は足で蹴る。たたくたびに一回だけ（押しっぱなしでは蹴らない。2026-10-30 代表「スペース連打じゃないとだめ。ダサくて必死にこぐのがいい」）。
## どの米袋を装備するかは、I で開く装備の画面（craft_ui.gd）で選ぶ。
## ランタンも装備（craft.gd の lanterns）: 帯の左に提げ、R で点ける・消す（2026-10-29 代表。ソリをふもとへ戻すのは Backspace に移した）。
## 左クリックの順: 雪玉を持っていれば投げる → 高い両手のひらなら拍手。
## ロッジの席（椅子・丸椅子・暖炉のまわりのソファ・揺り椅子・ビーズクッション・こたつの座布団。seats.gd）: 空いた席のそばで、席の方を向いて F で座る。
## 椅子の後ろへ歩み寄って向きを変え、腰を下ろす（12 コマ）。目線は座った人形の目の高さへ。もう一度 F か、移動キーで立つ。
## 座っているあいだも、身ぶり・声・手に持った物は使える。
## 厨房の乾燥機（cook_station.gd）: 手にペレットを持たずに前で F で中へとび込み、胴の中で丸まって回って乾く（Mode.DRUM）。
## 乾ききったら、ひとりでに戸からとび出す。もう一度 F でも出る。一人称は胴の真ん中から丸い戸の窓ごしに外を見る。

const SPEED := 2.0           # 雪の中をじりじり歩く速さ
const DASH := 3.4            # Shift で走る速さ
const SPEED_TAUT := 1.5      # 紐が張っているときの歩く速さ
const SPEED_CROUCH := 0.8    # しゃがんで歩く速さ
const CROUCH_EYE := 0.5      # しゃがむと目がこれだけ下がる (m)
# ジャンプは雪の上でのその場跳びくらい: 高さ約 42 cm、宙にいるのは約 0.43 秒（2026-11-02 代表「ジャンプがふわっとしててリアルじゃない。
# もっと飛び上がりと着地までの時間は短いほうが良い」。前は 4.5 m/s・9.8 で、高さ 1.07 m・0.95 秒）。
# 下りは上がりより重力を強くして、てっぺんでふわっと浮かない。段から落ちるときも FALL_GRAVITY（仲間の bot.gd も同じ）
const JUMP := 3.5            # 踏み切りの上向きの速さ (m/s)
const GRAVITY := 14.6        # 上がるあいだの重力 (m/s²)
const FALL_GRAVITY := 24.0   # 下りるあいだの重力 (m/s²)
const LAND_DIP := 0.012      # 着いたとき、一人称の目が沈む深さ（下向きの速さ 1 m/s あたり, m。ふつうのジャンプで約 5 cm）
const LAND_DIP_MAX := 0.08
const LAND_DIP_T := 0.22     # 沈んで戻るまで (s)
const STEP_UP := 0.45        # ジャンプしなくても乗り上げる段差の高さ (m)。デッキの縁・石の基壇（雪から 0.45 m）も歩いて上がれる（2026-11-03 代表「飛ばずに乗り越えられてほしい」）
const GRAB_REACH := 2.2      # F でつかめる、立つ位置までの距離 (m)
const FALL_NET := 2.0        # 安全網: 雪面よりこれだけ下へ落ちたら、雪の上へ戻す (m)
const DRUM_DROP := 0.18       # 乾燥機の中で丸まるとき、腰から足までの高さ (m。小さいほど膝を抱える)
const SPIN_SWAY := 0.39       # 乾燥機の中の一人称の揺れの速さ（コマあたり。胴の 1 回りに 1 往復ほど）
const LET_GO_SPEED := 5.0    # 紐を持っていて、ソリがこれより速く滑ると手が離れる (m/s)。縁をつかんでいるときはソリが決める（sled.gd の引きずり）

enum Mode { WALK, GRIP, RIDE, ROPE, SIT, DRUM }

var sled: RigidBody3D
var cam: Camera3D
var hands: Array[Node3D] = []
var doll: Doll               # 自分の体（笠と千代紙の人形）。一人称には映さず、右上の映像と三人称と影に出る
var mode := Mode.WALK
var ride_lean := Vector3.ZERO  # 乗っているときの体重移動（x 左右 -1〜1、y 前傾、z 後傾）。一緒に乗った仲間が合わせる
var seat := Vector3.INF
var handle := Vector3.INF    # つかんでいる所（ソリの座標）
var push_dir := Vector3.ZERO # 押す向き（ソリの座標）
var pushing := false
var pulling := false
var push_world := Vector3.ZERO  # このコマ押した向き（世界、水平）。通信でほかの画面のあなたの体が同じ向きに押す（net.gd）
var prompt := ""             # 画面に出す一言（main.gd が読む）
const MIRROR_GAZE_Y := 0.2    # 大きな鏡に映っているあいだの、上下の見る向きの効き
var base_fov := 75.0         # 一人称の視野角（設定からだけ変える）
var third := false           # C で三人称
var fp_locked := false       # 雪合戦で戦っているあいだ、一人称に固定する（lock_first）
var _third_want := false     # 遊ぶ人の選んだ視点（固定が解けたら、これに戻す）
var cam_dist := 3.4          # 三人称: 頭の後ろからカメラまでの距離 (m)。ピンチ・設定
var cam_frame := -0.2        # 三人称: 人形の目の高さの線が、画面のどの高さに来るか（まんなかが 0、上の縁が 1、下の縁が -1）。
                             # 負で人形が画面の下のほうに来て、上が広く見える。カメラの見下ろす角度はマウスの上下のまま
                             # （2026-10-30 代表「キャラを中心とした角度ではなく、キャラの水平ラインの画面での高さの調整がしたい」）。
                             # 設定からだけ変える
const CAM_DIST := Vector2(1.4, 9.0)     # 人形の真後ろ近く 〜 ソリ全体が見える遠さ
const CAM_FRAME := Vector2(-0.75, 0.5)  # 画面の下のほう 〜 少し上
const CAM_RISE := 0.4                   # カメラは頭より少し上から見る (m)。見下ろす角度はマウスの上下で変わる
var _gaze_from := Vector3.INF           # 三人称で、人形の見る先を測る所（頭）。一人称ではカメラ
var _cam_save_t := -1.0      # ホイールで変えた視野角・カメラを、少し止まってから設定に保存する
var _cam_free := 0.0         # 三人称のカメラが、当たりで縮められずにいられる距離（いまの値）
var bob_enabled := true      # 設定: 押す・引くときの視点の揺れ
var fov_kick_enabled := true # 設定: 押すときに画角が少し広がる
# 滑るときに画角が広がる（2026-10-29 代表「スピードに従って視野角を広げてほしい」）。
# 乗って滑っているあいだ、速さに合わせて視野角（base_fov）に足す。止まっていれば足さない。
# 滑るときの風（ride_wind.gd）と同じ速さで広がりはじめ、毛糸が流れきる速さ（SPEED_FULL）までに大半が広がる。
# 中・大のソリでまっすぐ下ると 8〜10 m/s。残りは米袋の連打（16 m/s 近く）のような速さのためにとっておく
const RIDE_FOV_MAX := 14.0                  # 足す視野角の上限 (°)
const RIDE_FOV_SPEED := Vector3(2.0, 9.0, 16.0)  # 広がりはじめる速さ、大半（RIDE_FOV_MAIN）が広がる速さ、上限に届く速さ (m/s)
const RIDE_FOV_MAIN := 0.7
const FOV_CAP := 120.0                      # 足したあとの視野角の上限 (°)。広く設定している人でも魚眼にしない
const RIDE_FOV_RISE := 1.6                  # 追いつく速さ（1/秒）。速くなるときはゆっくり広がり、
const RIDE_FOV_FALL := 2.4                  # 遅くなるときは少し早めに戻る（止まったあと広いままにしない）
const RIDE_CAM_PUSH := 0.5                  # 三人称: 上限のとき、カメラを後ろへ引く距離 (m)
var ride_fov_enabled := true  # 設定: 滑るときに画角が広がる
var ride_fov_amount := 1.0    # 設定: その強さ（0〜1。上限に掛ける）
var ride_rush := 0.0          # いまの盛り上がり（0〜1。速さをなめらかにしたもの。HUD などが同じ拍子で読める）
var ride_fov := 0.0           # いま足している視野角 (°)
var mouse_sens := 1.0        # 設定: マウスの感度
var menu_open := false       # 設定画面が開いている間は、クリックでマウスをつかまない
var _pitch := 0.0
const LOOK_DOWN := -0.3   # これより下を見ていれば、見下ろしている（約 17°）
var _col: CollisionShape3D
var _t := 0.0
var _snap := 0.0             # 吸い付きの途中（0→1）
var _hand_frame := -1        # 一人称の手を最後に置き直したコマ
var point_at := Vector3.INF  # 指している所（世界）。指していなければ INF。指しているあいだは、いつも見ている先を追う
var pointing := false        # 指さしを入れているか（右クリック・輪・2 キーで入れたり切ったり）
var _point_sent := Vector3.ZERO   # 最後に配り役へ送った向き（間引くため）
var _point_send_t := 0.0
const POINT_FOLLOW := 10.0   # 指す先が、見ている先へ追いつく速さ（1/s）
const POINT_FP_SIZE := 1.6  # 一人称の指さしの手形の大きさ（奥へ伸ばすと縮んで見えるので、ほかの手形より大きく）
const POINT_FP_OUT := 0.04  # 一人称の指さしの手形の手首を、袖口から前へ出す (m)
var point_level := true      # 一人称の指さしの手形を、画面の中で床に平行に置く（--point-tilt で前の、腕に沿った斜めの向き）
var point_lift := 20.0     # 一人称の指さしの手形（床に平行）を、目のほうへ起こす角度（度）。90 で甲がまっすぐこちら。--point-lift=度
const POINT_SEND_DEG := 4.0  # 向きがこれだけ変わったら送る（度）
const POINT_SEND_GAP := 0.17 # 送るのは多くても 1 秒に 6 回
var hub: Emotes              # 身ぶりの配り役（main.gd が置く。いなければ身ぶりは出せない）
var id := -1                 # 配り役からもらった番号
var busy_until := -1         # このコマまでは、その場で（裁ちばさみで雪のボタンの糸を切っている。snow_buttons.gd）
var _fp_rig: Node3D          # 机の皿と、一人称の手の道具を描く役（table_eat.gd の Rig）
var _te_done := {}           # 机での食べ方: このひと口で済ませた音と数（コマ → true）
var _eating := false         # 左ボタンを押しているあいだ、手の料理を 1 口ずつ食べ続ける
var _bit_frame := -1         # ひと口を数えた身ぶりの始まりのコマ（同じひと口を 2 度数えない）
var holding_ball := false   # 右手に雪玉を持っている（雪玉が 1 つ以上あって、持ち物を手に持っていないとき。毎フレーム決める）
var ring: EmoteRing
var _em := {}                # いまの自分の身ぶり（出来事）
var _winding := false
var _wind_wait := false      # 雪合戦の対決で、投げたばかりのうちに左クリックを押した。押したままなら、投げられるようになったら振りかぶる
var _catching := -1          # 雪合戦の対決で、取りにいった雪玉の番号（duel.gd の reach_for）
var _wind_t := 0.0
var _ball_fp: MeshInstance3D # 一人称の右手の雪玉
var _stock_fp: Node3D        # 一人称の、左の袖口に縫い付けた雪玉のストック
var _shapes_fp := {}         # 一人称の手の形のアップリケ: 形 → {1: 右手, -1: 左手}
var hands_name := ""         # いま掲げている手（Palm.HANDS の名前。"high_R" など。"" は下ろしている）
var hand := "R"              # 身ぶりに使う手（"R" "L" "both"）。Q で片手⇄両手、X で右⇄左
var _one_hand := "R"         # 片手のときの手（両手にしても覚えておく）
var _auto_wa := false        # 滑りながら高い両手のひらで、もう「ワ〜」と言った
var crouching := false       # 左 Ctrl を押しているあいだしゃがむ
var _exhaling := false      # B を押しているあいだ、息を吐いている
var _exhale_t := 0.0
var _cam_roll := 0.0         # 首をかしげると視点も少し傾く
var _cam_em := Vector3.ZERO  # 身ぶりで視点に足す（x 上下の向き、y 左右の向き、z 高さ）。なめらかに追う
var _land_t := 1.0           # 着いてからの時間 (s)。LAND_DIP_T までのあいだ一人称の目が沈む
var _land_amp := 0.0         # そのときの沈む深さ (m)
var _dip_shown := 0.0        # いまカメラに入れている着地の沈み (m)
var _fall_v := 0.0           # 宙にいるあいだの下向きの速さ（着いたときの手応えの強さ）
var _drag_k := 0.0           # 引きずられている度合い（0→1 になめらかに）。視点が前へ傾き、低く揺れる
var craft: Node              # 工房の配り役（main.gd の Craft）。財布と持ち物
var shopping := false        # 売り台が開いている（craft_ui.gd）。歩かない
var _held_fp: Node3D         # 一人称の右手に持った物の形
var _hold_tag: Node3D        # 手の材料に吊る紙の札（hold_tag.gd。本人の画面だけ）
var _held_key := ""
const TABLE_EYE := 0.42       # 机のある席で、目が机の面より少なくともこれだけ上 (m)
const HELD_TILT := 0.12      # 畳んだソリの包みの名札の面を、まっすぐより少し上へ傾ける (rad)
const HELD_TURN := 0.0     # 少し内へ回す (rad)
const HELD_SCALE := 1.25     # 一人称で持つ包みの大きさ
## 一人称の左の袖に縫い付けたストックの、袖の上の始めと終わり（手の所から肩のほうへ, m）
const STOCK_Z := Vector2(0.05, 0.23)
const STOCK_HAND := Vector3(-0.2, -0.04, -0.5)   # ストックを見せる左手の所（腕は画面の下の肩から伸びるので、袖が目のほうへ寝る）
var last_sled: RigidBody3D   # 最後に触った（つかむ・紐・乗る・広げる）ソリ。左下の札はこのソリのタグ（hud.gd）
var _pan_acc := Vector2.ZERO # 二本指スクロールのひと撫でのたまった量（横も。縦が勝ったときだけ持ち替える）
var _pan_done := false       # このひと撫ででもう持ち替えた（指を離したあとの慣性でも、続けて替えない）
var _pan_ms := 0             # 最後に動いたパンが来た時刻 (ms)
var _pan_frame := 0          # …そのフレーム
const PAN_STEP := 1.0        # 縦にこれだけたまったら 1 つ持ち替える（Godot は Mac のスクロール量の 0.03 倍で渡す。約 33 pt）
const PAN_GAP := 120         # パンがこれだけ (ms) 途切れたら、次のひと撫で
var last_item := {}          # 最後に触ったソリを畳んで持っていれば、その持ち物（last_sled は null）
const SLED_SWITCH := 0.8     # 近いソリへ持ち替える差 (m)。行ったり来たりしないよう
var seats: Seats             # ロッジの席の配り役（main.gd が置く。なければ座れない）
var seat_i := -1             # 座っている席の番号（seats.gd）
var _drum: Node              # 入っている乾燥機（cook_station.gd。Mode.DRUM のとき）
var _sit_frame := -1         # 座る出来事のコマ
var _stand_frame := -1       # 立つ出来事のコマ（座っているあいだは -1）
var _sit_from := Vector3.ZERO   # 座ると決めたときの足もと（席の立つ所へ歩み寄る）
var _sit_stage := 0          # 0 立つ、1 中腰、2 座る（Seats.place）
var _sit_keys_free := false  # 座ってから、移動キーをいったん離した（押しっぱなしのまま来て、すぐ立たないように）


func _ready() -> void:
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	_col.shape = cap
	_col.position.y = 0.85
	add_child(_col)
	floor_snap_length = 0.4   # 斜面でも床に吸い付く
	floor_max_angle = deg_to_rad(50)

	cam = Camera3D.new()
	cam.position.y = 1.55
	cam.fov = 75
	cam.near = 0.05
	cam.cull_mask = (1 << 0) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 7)   # 世界と手と飾りと風と太陽（main.gd の SUN_LAYER）。自分の体（層 2）は映さない
	add_child(cam)
	cam.make_current()

	var a = get_parent().get("args")
	_make_body(String(a.get("doll", "kasa")) if a is Dictionary else "kasa")   # --doll=<人形> で始めの人形

	hub = get_parent().get_node_or_null("Emotes")
	if hub:
		id = hub.join(self)
		hub.happened.connect(_on_emote)
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		ring = EmoteRing.new()
		layer.add_child(ring)
	craft = get_parent().get_node_or_null("Craft")
	if craft and id >= 0:
		craft.join(id)
		craft.happened.connect(_on_craft)
		# 保存した人形を送ったら、いまの人形は送らない（通信では、送った出来事がホストから戻るまで doll_of が空のため）
		if not _load_tag() and craft.doll_of(id) == "":
			craft.send({"kind": "doll", "who": id, "doll": doll.kind})   # いまの人形をみんなに知らせる
	last_sled = sled
	seats = get_parent().get_node_or_null("Seats")
	if seats:
		seats.happened.connect(_on_seat)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 自分の体（人形）と、一人称の手・袖・脚を作る。人形を替えるときは、前のを捨てて作り直す（set_doll）
func _make_body(kind: String) -> void:
	# 自分の体。一人称の画面には映さず、右上のライブ映像と影にだけ出る（層 2）
	doll = Doll.new()
	doll.kind = kind if kind in Doll.KINDS else "kasa"
	doll.layers = 1 << 1
	var dyed: Array = craft.outfit_of(id, doll.kind) if craft else []   # 染め桶で染めた服の色
	doll.outfit = dyed
	add_child(doll)

	# 米袋に座ったときに一人称で見える両脚（層 3）。米袋に合わせて置く
	_fp_legs = FpHands.make_legs(doll.kind, 1 << 2, dyed)
	_fp_legs.top_level = true
	_fp_legs.visible = false
	add_child(_fp_legs)

	# 一人称の手: 自分の人形と同じ柄の袖口から、紙の手がのぞく（層 3。一人称の画面にだけ映す）
	for s in [-1, 1]:
		var h := FpHands.make(doll.kind, s, 1 << 2, dyed)
		cam.add_child(h)
		h.set_meta("side", s)
		hands.append(h)
		if s > 0:
			_ball_fp = MeshInstance3D.new()
			_ball_fp.mesh = Doll.ball_mesh()
			_ball_fp.material_override = Doll.ball_material()
			_ball_fp.layers = 1 << 2
			_ball_fp.position = Vector3(0, 0.03, -0.1)
			_ball_fp.visible = false
			h.add_child(_ball_fp)
		else:
			# 残りの雪玉は、投げない左手の袖口に縫い付けたストックに通っている（人形の左の袖と同じ。右下の HUD とも同じ形）。
			# 2026-10-31 代表「投げる方の手にくっついてしまっているから、左手にストックはくっつけてほしい」
			# →「左手の袖に縫い付けるような感じでキャラにもストックさせましょう」「一人称でそのストック雪玉見える角度にしてほしい」
			var dz := STOCK_Z.y - STOCK_Z.x
			var dr := FpHands.sleeve_r(STOCK_Z.y, doll.kind) - FpHands.sleeve_r(STOCK_Z.x, doll.kind)
			_stock_fp = Doll.stock_strip(sqrt(dz * dz + dr * dr), 1 << 2)
			_stock_fp.visible = false
			h.add_child(_stock_fp)

	_shapes_fp = Palm.make_set(Color(FpHands.STYLE.get(doll.kind, FpHands.STYLE["kasa"]).hand), 1 << 2)
	for sh in _shapes_fp:
		for n in _shapes_fp[sh].values():
			cam.add_child(n)


## 人形を替える（衣装掛けで選んだ出来事が配られてから）。体・一人称の袖と手・米袋の脚・手のアップリケを作り直す。
## 持っている物・雪玉・名札・ランタンは人ではなく工房と配り役が持っているので、そのまま新しい体に付く
func set_doll(kind: String, again := false) -> void:
	if doll and doll.kind == kind and not again or not kind in Doll.KINDS:
		return
	var at := doll.global_transform if doll else global_transform
	for n in [doll, _fp_legs] + hands:
		if n:
			n.queue_free()
	hands.clear()
	for sh in _shapes_fp:
		for n in _shapes_fp[sh].values():
			n.queue_free()
	_shapes_fp = {}
	_held_fp = null   # 一人称の手に持った物は手と一緒に消えた。次のコマで新しい手に持ち直す
	_held_key = "-"
	_make_body(kind)
	doll.global_transform = at


## トラックパッドのピンチ（2026-10-30 代表「ピンチイン・アウトはカメラ距離の調整」）。指を閉じると引き、開くと寄る。
## 三人称ではカメラの距離。一人称で指を閉じ続けると三人称へ、三人称でいちばん近くまで寄ってさらに開き続けると一人称へ戻る
## （同じ動きで、一人称と三人称を行き来できる）
const PINCH_SWITCH := 0.35   # 切り替えに要る、たまった開き閉じ（ln の和）
var _pinch_acc := 0.0

func _pinch(factor: float) -> void:
	if fp_locked:
		return
	var f := log(maxf(factor, 0.01))   # 開くと正、閉じると負
	if third:
		if f > 0.0 and cam_dist <= CAM_DIST.x + 0.01:
			_pinch_acc += f
			if _pinch_acc >= PINCH_SWITCH:
				_pinch_acc = 0.0
				_switch_view(false)
			return
		_pinch_acc = 0.0
		_zoom_cam(cam_dist / factor - cam_dist, 0.0)
	else:
		_pinch_acc = _pinch_acc - f if f < 0.0 else 0.0
		if _pinch_acc >= PINCH_SWITCH:
			_pinch_acc = 0.0
			cam_dist = CAM_DIST.x
			_cam_save_t = 0.6
			_switch_view(true)


func _switch_view(on: bool) -> void:
	set_third(on)
	var st = get_parent().get("settings")
	if st:
		st.sync("third", on)


## 三人称のカメラの距離と、人形の画面の高さを変える（距離はピンチで。画面の高さは設定から）。少し止まってから設定に保存する
func _zoom_cam(d_dist: float, d_frame: float) -> void:
	cam_dist = clampf(cam_dist + d_dist, CAM_DIST.x, CAM_DIST.y)
	cam_frame = clampf(cam_frame + d_frame, CAM_FRAME.x, CAM_FRAME.y)
	_cam_save_t = 0.6


func _save_cam(dt: float) -> void:
	if _cam_save_t < 0.0:
		return
	_cam_save_t -= dt
	if _cam_save_t < 0.0:
		var st = get_parent().get("settings")
		if st:
			st.sync("cam_dist", cam_dist)
			st.sync("cam_frame", cam_frame)


## 三人称では自分の体を映し、一人称の手は映さない。滑るときの風（層 5）はどちらでも映す
func set_third(on: bool) -> void:
	_third_want = on
	_apply_third()


## 雪合戦で戦っているあいだ、一人称に固定する。解けたら、遊ぶ人の選んでいた視点へ（設定は書き換えない）
func lock_first(on: bool) -> void:
	if on and not fp_locked:
		_third_want = third
	fp_locked = on
	_apply_third()


func _apply_third() -> void:
	third = _third_want and not fp_locked
	cam.cull_mask = ((1 << 0) | (1 << 1) | (1 << 3) if third else (1 << 0) | (1 << 2) | (1 << 3)) | (1 << 4) | (1 << 7)   # 層 8 は太陽


func _unhandled_input(e: InputEvent) -> void:
	if ring and ring.visible and e is InputEventMouseMotion:
		ring.move(e.relative)   # 輪を出しているあいだは見回さない
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * 0.003 * mouse_sens)
		_pitch = clamp(_pitch - e.relative.y * 0.003 * mouse_sens, -1.4, 1.3)
	elif e is InputEventPanGesture:
		# トラックパッドの二本指スクロール（Mac ではホイールでなくこれで届く）: 持ち物の持ち替えだけ。持ち物がなければ何もしない
		# （2026-10-30 代表「二本指スクロールはインベントリ選択にしたい。視野角とカメラ高さは設定からのみ変更」）
		_pan_hand(e.delta)
	elif e is InputEventMagnifyGesture and not menu_open:
		_pinch(e.factor)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			var step := -1 if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1
			# Shift＋ホイールは、Mac では横のホイールとして届くことがある
			var sideways: bool = e.shift_pressed or e.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
			if not sideways and _can_cycle():
				cycle_hand(step)   # ホイールは持ち物の持ち替えだけ。持ち物がなければ何もしない
		elif e.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			toggle_point()
		elif e.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_left_click()
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _eating:
		_eating = false   # 食べているひと口は最後まで
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _wind_wait:
		_wind_wait = false
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _winding:
		throw_ball()
	elif e is InputEventKey and not e.pressed and e.physical_keycode == KEY_B:
		_stop_exhale()
	elif e is InputEventKey and not e.pressed and e.physical_keycode == KEY_TAB and ring and ring.visible:
		var k := ring.close()
		if k != EmoteRing.NONE:
			_choose(k)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_C:
				if not fp_locked:
					set_third(not third)
					get_parent().settings.sync("third", third)
			KEY_F:
				var duel := get_parent().get_node_or_null("Duel")
				var aimed: int = duel.try_catch(self) if duel and mode == Mode.WALK else -1
				if aimed >= 0:
					_catching = aimed   # 雪合戦の対決: 照準に合った相手の雪玉を取りにいく（2026-11-02 代表「キャッチはFキーにしましょう」）
					return
				if rooted():
					return
				if mode == Mode.SIT:
					stand_up()
					return
				if mode == Mode.DRUM:
					_drum.leave(id)   # 乾燥機から出る
					return
				var pg := peg_near()
				if pg:
					pull_peg(pg)   # ソリを留めているペグを抜く（乗ったままでも、乗っているソリのペグに届けば）
					return
				if crouching and mode == Mode.WALK and _snow_ahead():
					emote("make_ball")   # しゃがんで雪面に手を伸ばす: 雪玉を丸める
					return
				if mode == Mode.WALK and machine_near() and (not shop_near() or _facing(get_parent().sewing.machine.global_position) > _facing(get_parent().shopkeeper.global_position)):
					get_parent().craft_ui.open_machine()   # ミシンの画面（おじさんも近ければ、向いている方）
					return
				if mode == Mode.WALK and shop_near():
					get_parent().craft_ui.open_shop()   # 売り子のおじさんに話しかける
					return
				var rt := rack_target()
				if not rt.is_empty():   # ソリの立てかけ台: 自分のソリを戻す・持ち出す
					craft.send({"kind": rt[1], "who": id, "id": craft.sled_id(rt[0])})
					return
				if mode == Mode.WALK and mountain_near():
					get_parent().mountain_ui.open()   # 玄関の外の山男: 山の道具（焚き火セット・ペグ）を買う
					return
				if mode == Mode.WALK and _mirror_f():
					return   # 入口の横の大きな鏡: 自分の人形を映す・消す
				if mode == Mode.WALK and dye_near():
					get_parent().dye_ui.open()   # 人台の桶を見下ろす: 服を染める
					return
				if mode == Mode.WALK and paper_shop_near():
					get_parent().paper_shop_ui.open()   # テントの紙細工屋さん: 提灯と頭・肩の小物を買って付け替える
					return
				var dr := dryer_near()
				if mode == Mode.WALK and dr and dr.ride(self):   # 厨房の乾燥機: 手にペレットを持っていなければ、中に入って乾く
					return
				var st := station_near()
				if mode == Mode.WALK and st and st.use(self):   # 厨房の装置: 手のペレットを入れて調理する（仕上がりを受け取る）
					return
				if mode == Mode.WALK and food_near():
					get_parent().food_ui.open()   # 雪だるまの番台: ペレットを雪玉で買う
					return
				if mode == Mode.WALK and wardrobe_near():
					get_parent().wardrobe_ui.open()   # 人台の人形の高さを見る: 人形を選び直す
					return
				var sb = get_parent().get("snow_buttons")
				if mode == Mode.WALK and sb and sb.reachable(self) != null and sb.request_cut(id):
					busy_until = Doll.frame_index() + 1 + sb.SHEAR_END   # 雪のボタンの糸を、裁ちばさみでちょきん
					var hud = get_parent().get("hud")
					if hud:
						hud.learn("shears")
					return
				if mode == Mode.WALK and lay_fire():   # 手の焚き火セットを、前の雪の上に組んで火をつける
					return
				if mode == Mode.WALK and put_out_fire():   # 自分の焚き火に雪をかけて消す
					return
				if mode == Mode.WALK and sit_down():
					return
				match mode:
					Mode.GRIP, Mode.ROPE:
						let_go()
					Mode.WALK:
						if _rope_end_near():
							grab_rope()
						else:
							grab()
					Mode.RIDE:
						catch_from_sack()   # 米袋で追いついたソリをつかむ
			KEY_SPACE:
				if mode == Mode.RIDE and sled.kick(self):
					_kicked()   # 乗っているあいだの Space は足で漕ぐ（ジャンプしない）
				elif space_hands_up():
					toggle_hands_up()   # 漕げないソリで滑っているあいだの Space は万歳（A・D で曲がりながら押せる）
			KEY_TAB:
				if ring and not menu_open:
					ring.open(hand, _height(), point_at != Vector3.INF)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				# 輪と同じ 6 つ: 1 高い手のひら、2 低い手のひら、3 指さし、4 ウン、5 ンーン、6 首をかしげてウン？
				if e.physical_keycode == KEY_1 and gliding():
					toggle_hands_up()   # 滑っているあいだの 1 は、片手・両手の切り替えによらず両手で万歳（Space と同じ）
				else:
					_choose(["high", "low", "point", "un", "nn", "huh", "oi"][e.physical_keycode - KEY_1])
			KEY_Q:
				# 片手 ⇄ 両手
				_set_hand("both" if hand != "both" else _one_hand)
			KEY_X:
				# 片手の右 ⇄ 左
				_one_hand = "L" if _one_hand == "R" else "R"
				_set_hand(_one_hand)
			KEY_B:
				if not _exhaling and available().get("breath", false):
					_exhaling = true
					_exhale_t = 0.0
					emote("breath")
			KEY_N:
				if craft and not menu_open and not rooted() and mode != Mode.SIT and mode != Mode.DRUM:
					toggle_sack()
			KEY_R:
				if craft and not menu_open:
					toggle_lamp()
			KEY_I:
				if craft and not menu_open and get_parent().get("craft_ui"):
					get_parent().craft_ui.open_gear()   # 装備の画面
			KEY_Z:
				# 手に持つ物を替える（Shift で逆回り）。ホイールやトラックパッドが使えないとき
				if craft and craft.has_hand_items(id) and not menu_open:
					cycle_hand(-1 if e.shift_pressed else 1)
			KEY_E:
				if mode == Mode.RIDE:
					get_off()
				elif mode != Mode.SIT and mode != Mode.DRUM:
					get_on()


## そばの、座れる空いた席の番号（見ている向きにあるもの）。なければ -1
func seat_near() -> int:
	if seats == null or mode != Mode.WALK or shopping:
		return -1
	return seats.near(global_position, -cam.global_basis.z)


## そばの空いた席に座る（出来事を出す。座るのは配られてから）
func sit_down() -> bool:
	var i := seat_near()
	return i >= 0 and seats.send({"kind": "sit", "who": id, "seat": i})


## 席から立つ（立つ途中なら何もしない）
func stand_up() -> void:
	if seat_i >= 0 and _stand_frame < 0:
		seats.send({"kind": "stand", "who": id, "seat": seat_i})


func _on_seat(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	match ev.kind:
		"sit":
			if mode == Mode.GRIP or mode == Mode.ROPE:
				let_go()
			seat_i = int(ev.seat)
			_sit_frame = int(ev.frame)
			_stand_frame = -1
			_sit_from = global_position
			_sit_stage = 0
			_sit_keys_free = false
			mode = Mode.SIT
			_col.disabled = true
			velocity = Vector3.ZERO
		"stand":
			_stand_frame = int(ev.frame)


## 座る・座っている・立つ（居場所は人形と同じコマで刻む）。立ちきったら歩ける
func _sit_step(dt: float) -> void:
	var st := seats.seat(seat_i)
	var f := Doll.frame_index()
	var pl: Array = Seats.place(st, _sit_from, f, _sit_frame, _stand_frame)
	_sit_stage = pl[1]
	velocity = Vector3.ZERO
	if pl[2]:
		mode = Mode.WALK
		seat_i = -1
		_sit_stage = 0
		_col.disabled = false
		global_position = pl[0] + Vector3.UP * 0.05
		return
	global_position = pl[0]
	if _stand_frame < 0 and f - _sit_frame < Seats.SIT_IN:
		var face: Vector3 = st.face
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-dt * 10.0))   # 腰を下ろしながら、目も席の向きへ
	var moving := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_A) \
			or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_D)
	if not moving:
		_sit_keys_free = true
	elif _sit_keys_free and _sit_stage == 2 and not menu_open and not shopping:
		stand_up()   # 移動キーでも立つ


## 乾燥機に入る出来事が配られた（cook_station.gd の begin_ride）
func enter_drum(st: Node) -> void:
	if mode == Mode.GRIP or mode == Mode.ROPE:
		let_go()
	_drum = st
	mode = Mode.DRUM
	_col.disabled = true
	velocity = Vector3.ZERO
	crouching = false
	# 一人称は外（丸い戸の窓）を、三人称は乾燥機の方を向く（カメラが戸の前から中の人形を見る）
	var f: Vector3 = st.front() * (-1.0 if third else 1.0)
	rotation.y = atan2(-f.x, -f.z)
	var hud = get_parent().get("hud")
	if hud:
		hud.learn("dryer")


## 乾燥機の中（居場所は人形と同じコマで刻む）。乾ききったら出る。出きったら歩ける
func _drum_step(_dt: float) -> void:
	velocity = Vector3.ZERO
	var pl: Dictionary = _drum.ride_pose(Doll.frame_index())
	if pl.done or _drum.rider != id:
		mode = Mode.WALK
		_col.disabled = false
		_cam_roll = 0.0
		global_position = _drum.stand_point() + Vector3.UP * 0.05
		_drum = null
		return
	global_position = pl.pos
	var dm = get_parent().get("damp")
	if dm and _drum.should_leave(dm.water_of(id), dm.CRISP):
		_drum.leave(id)   # 乾ききった: ひとりでに出る


## そばの、入れる乾燥機（前にいて、乾燥機の方を向いていて、手にペレットを持っていない）。なければ null
func dryer_near() -> Node:
	if mode != Mode.WALK or shopping:
		return null
	for st in get_parent().get("stations") if get_parent().get("stations") != null else []:
		if st.can_ride(self) and _facing(st.get_parent().global_position) > 0.2:
			return st
	return null


## 雪の上の紐の先に近いか
func _rope_end_near() -> bool:
	var d: Vector3 = sled.rope.end_point() - global_position
	d.y = 0
	return d.length() < 1.6


func grab() -> void:
	set_hands("")   # ソリをつかむ手は、形を下ろす
	var gp: Array = sled.grip_point_near(global_position)
	var stand: Vector3 = gp[0]
	if global_position.distance_to(sled.to_global(stand)) > GRAB_REACH:
		return
	if not sled.take_handle(self, stand):
		return
	handle = stand
	push_dir = gp[1]
	mode = Mode.GRIP
	_touched(sled)
	_col.disabled = true
	_snap = 0.0
	# 体を押す向きに向ける（視線はそのあと自由）
	var fwd: Vector3 = sled.global_basis * push_dir
	rotation.y = atan2(-fwd.x, -fwd.z)


func grab_rope() -> void:
	set_hands("")
	if not sled.take_rope(self):
		return
	mode = Mode.ROPE
	_touched(sled)


func let_go() -> void:
	match mode:
		Mode.GRIP:
			sled.release_handle(self)
			handle = Vector3.INF
			_col.disabled = false
			# 手が離れた: ソリに当たらないよう、つかんでいた縁から少し外へ
			var out: Vector3 = -(sled.global_basis * push_dir)
			out.y = 0
			if out.length() > 0.1:
				global_position += out.normalized() * 0.4
		Mode.ROPE:
			sled.release_rope(self)
		_:
			return
	mode = Mode.WALK
	velocity = Vector3.ZERO


func get_on() -> void:
	if global_position.distance_to(sled.global_position) > 2.8:
		return
	var s: Vector3 = sled.mount(self)
	if s == Vector3.INF:
		return
	if mode == Mode.GRIP or mode == Mode.ROPE:
		let_go()
	seat = s
	mode = Mode.RIDE
	_touched(sled)
	_col.disabled = true


func get_off() -> void:
	if mode != Mode.RIDE:
		return
	sled.dismount(self)
	var was := seat
	seat = Vector3.INF
	mode = Mode.WALK
	_col.disabled = false
	if sled.kind == "sack":
		# 米袋: その場で立ち上がり、袋のすぐ後ろに立つ（足もとで丸めて帯に戻せるように）。袋の形はふだんへ
		SackLook.set_stage(sled, was, 0)
		global_position = sled.global_position + sled.global_basis.z * 0.6 + Vector3.UP * 0.2
		velocity = Vector3.ZERO
		_keep_above_ground(0.0)
		return
	global_position = sled.global_position + sled.global_basis.x * 1.4 + Vector3.UP * 0.5
	velocity = Vector3.ZERO
	# 急な坂では、ソリの横 1.4 m の所が雪面より下になる（坂の上側へ降りたとき）。地面の下に置くと、そのまま落ち続ける
	_keep_above_ground(0.0)


## 安全網: 雪面より below (m) 下にいたら、その場の雪の上へ戻す（地面の当たりは厚みのない面なので、下へ出ると戻れない）
func _keep_above_ground(below: float) -> void:
	var w := get_parent()
	if w == null or not w.has_method("height"):
		return
	var g: float = w.height(global_position.x, global_position.z)
	if global_position.y >= g - below:
		return
	if below > 0.0:
		print("人が地面の下へ落ちたので、雪の上へ戻した: (%.1f, %.1f)" % [global_position.x, global_position.z])
	global_position.y = g + 0.1
	velocity = Vector3.ZERO
	reset_physics_interpolation()


# ---------------------------------------------------------------- 米袋で足で漕ぐ・追いついて止める

const CATCH_REACH := 2.4     # 米袋に乗ったまま F でつかめる、ほかのソリのつかみ所までの距離 (m)
var _kick_side := 1


## 蹴れた: 足を交互に出し（人形のコマ）、足もとに雪の粉、蹴る音
func _kicked() -> void:
	_kick_side = -_kick_side
	doll.kick(_kick_side)
	var foot: Vector3 = sled.to_global(seat + Vector3(0.15 * _kick_side, -seat.y, 0.2))
	preload("res://snowball.gd").splat_at(get_parent(), foot + Vector3.UP * 0.05, Vector3.UP, true)
	var au := get_parent().get_node_or_null("Audio")
	if au and au.has_method("kick"):
		au.kick(self)


## 米袋に乗ったまま F: そばに別のソリがあれば、米袋から降りてそのソリにしがみつく。
## 速く下っていれば、そのまま「引きずられて止める」に入る。米袋は自動で帯に戻す（craft.gd の sack_in。装備なので
## 空の米袋を坂に残さない。2026-10-29 店のセッションと決めた）
func catch_from_sack() -> bool:
	var sack := sled
	if sack == null or sack.kind != "sack":
		return false
	var best: RigidBody3D = null
	var best_d := CATCH_REACH
	for s in get_tree().get_nodes_in_group("sleds"):
		var rb := s as RigidBody3D
		if rb == null or rb == sack or not rb.visible:
			continue
		var gp: Array = rb.grip_point_near(global_position)
		var d := global_position.distance_to(rb.to_global(gp[0]))
		if d < best_d:
			best = rb
			best_d = d
	if best == null:
		return false
	var at := global_position
	get_off()
	global_position = at
	sled = best
	grab()
	if craft:
		craft.send({"kind": "sack_in", "who": id})   # 降りたあとなので、乗っている人はいない
	return mode == Mode.GRIP


## 紙の体の湿り気（damp.gd）の倍率: push なら押す力、そうでなければ歩く速さ
func damp_k(push: bool) -> float:
	var dm := get_parent().get_node_or_null("Damp")
	if dm == null or id < 0:
		return 1.0
	return dm.push_k(id) if push else dm.speed_k(id)


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _physics_process(dt: float) -> void:
	_eat_step()
	_t += dt
	pushing = false
	pulling = false
	prompt = ""

	if mode == Mode.WALK:
		_pick_sled()
	match mode:
		Mode.RIDE:
			global_position = sled.to_global(seat)
			ride_lean = Vector3(_key(KEY_D) - _key(KEY_A), _key(KEY_W), _key(KEY_S))
			sled.lean(ride_lean.x, ride_lean.y > 0.0, ride_lean.z > 0.0)
			prompt = "W 前傾　S 後傾で止まる　A/D 体重をかけて曲がる　E 降りる"
		Mode.GRIP:
			_grip(dt)
		Mode.ROPE:
			_walk(dt, true)
			_keep_above_ground(FALL_NET)
		Mode.WALK:
			_walk(dt, false)
			_keep_above_ground(FALL_NET)
		Mode.SIT:
			_sit_step(dt)
		Mode.DRUM:
			_drum_step(dt)
	_keep_in_duel()
	_update_point(dt)
	_update_emote(dt)
	_sack_events()
	_tag_hold_step(dt)
	_pose_hands(dt)
	_pose_doll()


## 人形に、いまの動きを伝える（姿勢は人形が 12 コマで刻む）。Q を押しているあいだ手を振る（仮のキー）
func _pose_doll() -> void:
	doll.act = [Doll.Act.WALK, Doll.Act.PUSH, Doll.Act.RIDE, Doll.Act.ROPE, Doll.Act.SIT, Doll.Act.SIT][mode]
	doll.spin_axis = Vector3.ZERO
	doll.drum_fit = 1.0
	doll.sled = sled
	doll.grip = handle if mode == Mode.GRIP else Vector3.INF
	doll.effort = pushing or pulling
	doll.dragged = mode == Mode.GRIP and sled.is_dragged(self)
	doll.airborne = mode == Mode.WALK and not is_on_floor()
	doll.facing = (sled.global_basis * push_dir) if mode == Mode.GRIP else Vector3.ZERO
	doll.rock_axis = Vector3.ZERO
	doll.rock_turns = false
	if mode == Mode.SIT:
		var st := seats.seat(seat_i)
		doll.facing = st.face
		if st.kind == "beanbag" and _sit_stage == 2 and _stand_frame < 0:
			# ビーズクッション: 座りきったら、体の向きが見ている向き（左右）についてくる（人形が 12 コマで回る。doll.gd の rock_turns）
			var view := -global_basis.z
			view.y = 0
			doll.facing = view.normalized()
			doll.rock_turns = true
		doll.sit_stage = _sit_stage
		doll.seat_drop = st.pos.y - st.floor
		doll.seat_edge = st.edge
		if st.has("rock_axis"):   # 揺り椅子・ビーズクッション: 体ごと傾く（seats.gd の rock_of）
			doll.rock_axis = st.rock_axis
			doll.rock_at = st.rock_at
			doll.rock_roll = float(st.get("rock_roll", 0.0))
			doll.rock = Seats.rock_of(st, Doll.frame_index(), _sit_frame, _stand_frame)
	doll.seat_soft = mode == Mode.SIT and seats.seat(seat_i).kind == "zabuton"
	doll.eat_table = table_ctx()
	if mode == Mode.DRUM:
		var pl: Dictionary = _drum.ride_pose(Doll.frame_index())
		doll.facing = pl.face
		doll.sit_stage = pl.stage
		doll.seat_drop = DRUM_DROP
		doll.drum_fit = pl.get("fit", 1.0)   # 胴に収まらない大きな人形は縮める
		if pl.stage == 2:   # 胴の中: 体ごと回され、手足と頭はぶらぶら（dryer_flop.gd）
			doll.spin_axis = _drum.front()
			doll.spin = pl.spin
			doll.spin_at = _drum.drum_center()
			doll.flop = pl.get("flop", {})
	# 人形の顔は、カメラの見ている向きの 6 m 先を見る。測る所は、一人称ではカメラ（目）、三人称では頭。
	# 三人称でカメラから測ると、カメラが 6 m 後ろなら見る先が頭そのものに、9 m なら頭の 3 m 後ろになり、首がねじれていた
	var from := _gaze_from if third and _gaze_from != Vector3.INF else cam.global_position
	doll.gaze = from - cam.global_basis.z * 6.0
	var mir = get_parent().get("mirror")
	if mir != null and mir.shown:
		# 大きな鏡を見上げても、鏡の中の顔が上を向きすぎないように（高い所の顔を見ると、自分の顔がのけぞって見えなくなる）。自分の画面だけ
		doll.gaze.y = from.y + (doll.gaze.y - from.y) * MIRROR_GAZE_Y
	doll.rope_hand = _hand_world() if mode == Mode.ROPE else Vector3.INF
	doll.lean = Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_W) - _key(KEY_S)) if mode == Mode.RIDE else Vector2.ZERO
	doll.point_sides = Palm.sides_of(hand)
	holding_ball = ball_count() > 0 and held().is_empty() and hub.can_throw(id)   # 雪合戦の対決で投げたばかりなら、次の雪玉はまだ袖に
	doll.holding_ball = holding_ball
	doll.sleeve_balls = ball_count() - (1 if holding_ball else 0)
	doll.crouch = crouching
	doll.point = point_at
	if craft:
		# 帯の丸めた米袋（出していなければ下げている）
		var spec: Dictionary = craft.sack(id)
		doll.belt_sack = not spec.is_empty() and craft.sack_sled(id) == null
		if not spec.is_empty():
			doll.belt_color = preload("res://fabrics.gd").color(spec.fabric) if spec.fabric != "" else preload("res://sled.gd").KINDS["sack"].color
		# 帯の左のランタン
		doll.lantern = craft.lantern(id).get("look", "")
		doll.lantern_lit = craft.lamp_on(id)


## 右クリックで指さしを入れたり切ったりする。入れているあいだ、腕はいま見ている先（画面のまんなかが当たる所）を追う。
## 見回すと指す先も一緒に動く（2026-10-31 代表「指差し時に向きを固定していますが、視点に追従するほうがわかりやすいので、向き固定はやめましょう」）。
## 前の作り（指した所に残す・動く物に吸い付く）はやめた。もう一度押すと腕を下ろす
func toggle_point() -> void:
	if pointing:
		_stop_point()
		return
	set_height("")   # 指さす手は、手のひらを下ろす
	pointing = true
	point_at = _view_point()
	_send_point(true)


func _stop_point() -> void:
	pointing = false
	point_at = Vector3.INF
	if hub:
		hub.send({"kind": "point", "who": id, "dir": Vector3.ZERO, "dist": 0.0})
		_point_sent = Vector3.ZERO


## いま見ている先: 画面のまんなかから 60 m 先までで、最初に当たる所（なければ 60 m 先）
func _view_point() -> Vector3:
	var from := cam.global_position
	var to := from - cam.global_basis.z * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else to


## 指しているあいだ、指す先を見ている先へなめらかに追わせる。向き（頭から）を回し、長さは近づける
## （当たる所が手前の物と遠くの雪のあいだで跳んでも、腕が飛ばないように）。腕の形は人形が 12 コマで刻む
func _update_point(dt: float = 0.0) -> void:
	if not pointing:
		return
	var head := global_position + Vector3.UP * 1.55
	var want := _view_point() - head
	var cur := point_at - head if point_at != Vector3.INF else want
	var k := 1.0 - exp(-dt * POINT_FOLLOW)
	var dir := cur.normalized().slerp(want.normalized(), k) if cur.length() > 0.01 and want.length() > 0.01 else want.normalized()
	var dist := lerpf(cur.length(), want.length(), k)
	point_at = head + dir * dist
	_send_point(false)


## 指さしの向きを配り役へ送る。向きが POINT_SEND_DEG 以上変わったときだけ、多くても 1 秒に 6 回（通信の量を抑える）
func _send_point(force: bool) -> void:
	if hub == null or point_at == Vector3.INF:
		return
	var rel := point_at - (global_position + Vector3.UP * 1.55)
	var dir := rel.normalized()
	var now := Time.get_ticks_msec() / 1000.0
	var turned := _point_sent == Vector3.ZERO or rad_to_deg(dir.angle_to(_point_sent)) >= POINT_SEND_DEG
	if force or (turned and now - _point_send_t >= POINT_SEND_GAP):
		hub.send({"kind": "point", "who": id, "dir": dir, "dist": snappedf(rel.length(), 0.1)})
		_point_sent = dir
		_point_send_t = now


## 小さな段差（STEP_UP まで）は、歩くだけで乗り上げる。
## 前がふさがっていて、持ち上げると前へ進め、その先に平らな床があるときだけ体を持ち上げる（壁やソリには上らない）。
## 前をふさいでいるのが歩ける斜面なら段差ではない（斜面を段差と見て持ち上げては落ちると、視点が震える）。
## 歩ける斜面かどうかは、move_and_slide が床とみなす傾き（floor_max_angle）と同じで見る。違うと、その間の傾きの縁
## （雪から 12〜14 cm 出た段の縁に体の丸い底が当たるとき）で、段とも斜面ともみなされず、そこで止まってしまう。
## 前が上りの雪の坂なら、坂に沿って進めた先も見る（雪の坂の途中から段が出ていると、真横へ動かすと坂に当たって段に気づかない）。
## 2026-11-03 代表「看板の当たり判定大きく感じる、変につまずく」: ロッジの前の広場の縁の段（道しるべの立っていた所）で止まっていた
func _step_up(dir: Vector3) -> void:
	if dir.length() < 0.1:
		return
	var ahead := dir * 0.3
	var block := KinematicCollision3D.new()
	if not test_move(global_transform, ahead, block):
		return
	var walkable := cos(floor_max_angle)
	if block.get_normal().y >= walkable:
		ahead = ahead.slide(block.get_normal())
		if not test_move(global_transform, ahead, block) or block.get_normal().y >= walkable:
			return
	var up := Vector3(0, STEP_UP, 0)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, ahead):
		return
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(ahead), -up, col):
		return
	if col.get_normal().y < 0.7 or col.get_collider() is RigidBody3D:
		return
	var rise := STEP_UP + ahead.y - col.get_travel().length()
	if rise > 0.02:
		global_position.y += rise + 0.01
		# 体は一気に上がっても、視点はすっと追いつく（カメラを同じ高さに残し、_place_camera が戻す）
		cam.position.y -= rise + 0.01


func _walk(dt: float, with_rope: bool) -> void:
	var input := Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_S) - _key(KEY_W))
	if rooted() or shopping:
		input = Vector2.ZERO   # 雪玉を丸める・ハイタッチ・買い物のあいだは、その場で
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := DASH if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED
	if crouching:
		speed = SPEED_CROUCH
	if with_rope:
		# 紐が張っていれば、手の位置から引く。引いている間は歩みが重くなる
		var over: float = sled.pull_rope(_hand_world(), damp_k(true))
		if over > 0.0:
			pulling = true
			speed = SPEED_TAUT
		# 紐より遠くへは行けない
		var anchor: Vector3 = sled.to_global(sled.ROPE_ANCHOR)
		var d := global_position - anchor
		d.y = 0
		if d.length() > sled.ROPE_LEN + 0.3:
			global_position = anchor + d.normalized() * (sled.ROPE_LEN + 0.3) + Vector3(0, global_position.y - anchor.y, 0)
	speed *= damp_k(false)   # 紙の体が湿ると遅く、パリッとすると速く（damp.gd）
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP
		else:
			velocity.y = 0.0   # 床の上で縦の速さを残すと、床に食い込んでは押し戻されて細かく揺れる
			_step_up(dir)
	else:
		velocity.y -= (GRAVITY if velocity.y > 0.0 else FALL_GRAVITY) * dt
	var was_air := not is_on_floor()
	move_and_slide()
	if was_air and is_on_floor() and _fall_v > 1.5:
		# 着いた: 下向きの速さに応じて、一人称の目が少し沈んで戻る（膝で受け止める。人形の膝は doll.gd、音は audio.gd）
		_land_t = 0.0
		_land_amp = minf(_fall_v * LAND_DIP, LAND_DIP_MAX)
	_fall_v = maxf(-velocity.y, 0.0) if not is_on_floor() else 0.0

	if with_rope:
		if sled.linear_velocity.length() > LET_GO_SPEED:
			let_go()
			return
		prompt = "紐を引いている　F 手を離す" if pulling else "紐を持っている　歩くと引ける　F 手を離す"
		return

	if _rope_end_near():
		prompt = "F で紐を持つ"
		return
	var gp: Array = sled.grip_point_near(global_position)
	var stand_w: Vector3 = sled.to_global(gp[0])
	if global_position.distance_to(stand_w) > GRAB_REACH:
		return
	var fwd: Vector3 = sled.global_basis * gp[1]
	fwd.y = 0
	if fwd.normalized().dot(-global_basis.z) > 0.6:
		prompt = "F でソリをつかむ"


func _grip(dt: float) -> void:
	# 手が縁に吸い付き、体はソリについて行く
	_snap = min(1.0, _snap + dt * 5.0)
	var target: Vector3 = sled.to_global(handle)
	global_position = global_position.lerp(target, _snap) if _snap < 1.0 else target
	velocity = Vector3.ZERO

	# 視点基準の WASD を、つかんでいる所にかける力の向きにする
	var input := Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_S) - _key(KEY_W))
	var dragged: bool = sled.is_dragged(self)
	if input.length() > 0.0 and not dragged:
		var dir := (global_basis * Vector3(input.x, 0, input.y))
		dir.y = 0
		push_world = dir.normalized()
		sled.push(push_world, target + Vector3.UP * 0.5, self, damp_k(true))
		pushing = true

	if dragged:
		prompt = "引きずられている　踏ん張って止める　F 手を離す"
		return
	prompt = "力をかけている　F 手を離す　E 乗る" if pushing else "WASD 見ている向きを基準に力をかける　F 手を離す　E 乗る"


## 紐を持つ手の位置（世界座標）。一人称では画面の右手、三人称では体の右前
func _hand_world() -> Vector3:
	if third:
		return to_global(Vector3(0.25, 1.0, -0.45))
	return cam.to_global(Vector3(0.2, -0.3, -0.4))


## 紐の先を付ける所（sled_rope.gd が読む）
func rope_hand() -> Vector3:
	return _hand_world()


## 着地の沈み (m): 0.05 秒で沈みきり、残りでなめらかに戻る。視点の揺れを切ると弱く
func _land_dip(dt: float) -> float:
	if _land_t >= LAND_DIP_T:
		return 0.0
	_land_t += dt
	var k := clampf(_land_t / LAND_DIP_T, 0.0, 1.0)
	var down := 0.05 / LAND_DIP_T
	var w := k / down if k < down else 0.5 + 0.5 * cos(PI * (k - down) / (1.0 - down))
	return _land_amp * w * (1.0 if bob_enabled else 0.3)


func _place_camera(dt: float, bob: float, working: bool) -> void:
	var eye_y := 1.55 + (bob * 0.02 if working else 0.0)
	_drag_k = move_toward(_drag_k, 1.0 if mode == Mode.GRIP and sled.is_dragged(self) else 0.0, dt * 4.0)
	# 引きずられているときの体勢の崩れ（人形と同じコマで刻む）: 雪のでこぼこ（コマごと）、左右のよろけ（ゆっくり）、
	# ときどき膝ががくっと抜けて沈む。視点の揺れを切ると弱く
	var jolt := 0.0
	var reel := 0.0
	var dip := 0.0
	if _drag_k > 0.0:
		var f := Doll.frame_index()
		var calm := 1.0 if bob_enabled else 0.3
		jolt = (0.015 if f % 2 == 0 else -0.015) * _drag_k * calm
		reel = sin(f * 0.55) * 0.09 * _drag_k * calm
		dip = (0.1 if f % 14 < 3 else 0.0) * _drag_k * calm
	if not third:
		var eye := Vector3(0, eye_y - 0.3 * _drag_k - dip + jolt, -0.35 * _drag_k)
		if mode == Mode.RIDE and doll.sack_seated():
			# 乗っているときは、座った人形の目の所（席や人形が変わっても合う）。ソリが傾けば一緒に傾く。
			# 乗り降りは同じ lerp で、すっと立ち上がる・腰を下ろす。米袋は、袋を広げ終えて腰を下ろしてから下がる
			var e := doll.eye_point(true)
			if sled.kind == "sack":
				e += SACK_EYE   # 米袋では少し後ろへもたれる（膝と紐を握った手と袋の前の縁が、画面の下に見える）
			eye = to_local(Transform3D(sled.global_basis.orthonormalized(), global_position) * e)
		elif mode == Mode.DRUM and _drum.drying(id):
			# 乾燥機の中: 胴の真ん中から（人形といっしょには回らない。胴の回りに合わせて少し揺れる）
			eye = to_local(_drum.drum_center() + Vector3.UP * 0.1)
			_cam_roll = 0.08 * sin(Doll.frame_index() * SPIN_SWAY)
		elif mode == Mode.SIT and _sit_stage > 0:
			# ロッジの席: 座った人形の目の所（中腰のあいだは半ば）。揺り椅子・ビーズクッションでは、傾いて動いた人形の目の所（視点は傾けない）
			var e := doll.eye_point(true) if _sit_stage == 2 else doll.eye_point(false).lerp(doll.eye_point(true), 0.55)
			eye = to_local(doll.global_transform * e)
			var st := seats.seat(seat_i)
			if _sit_stage == 2 and st.has("table"):   # 机より目が下だと、天板の裏しか見えない（掘りごたつの座布団）。机の面の少し上へ
				eye.y = maxf(eye.y, to_local(Vector3(0, float(st.table.y) + TABLE_EYE, 0)).y)
		eye.y += _cam_em.z
		# 着地の沈みは目の高さの追いかけ（lerp）の外で足す（なまらず、すとんと沈んですっと戻る）
		cam.position.y += _dip_shown
		cam.position = cam.position.lerp(eye, min(1.0, dt * 10.0))
		_dip_shown = _land_dip(dt)
		cam.position.y -= _dip_shown
		cam.rotation = Vector3(clampf(_pitch + _cam_em.x - 0.18 * _drag_k - dip * 1.5, -1.5, 1.4), _cam_em.y + reel * 0.5, _cam_roll + reel + jolt * 2.0)
		return
	# 三人称: 頭の少し上を中心に、後ろからカメラの距離と高さで見る。マウスの上下で回り込む。
	# 頭からカメラへ玉を滑らせて、壁・天井・地面・ソリに当たる手前で止める（埋まらない）。
	# 当たって縮むときはすぐ、離れて戻るときはゆっくり（壁の向こうが一瞬見えないように）
	# カメラは頭のまわりをマウスの上下で回り、頭を見る向き（basis）を決める。そのあと、人形の目の高さの線が画面の cam_frame の
	# 高さに来るよう、カメラを自分の上下の向きに平行にずらす（見下ろす角度は変えない。Camera3D の v_offset と同じ）
	_dip_shown = 0.0   # 着地の沈みは一人称だけ（三人称は人形の膝で見せる）
	var pivot := Vector3(0, 1.6, 0)
	if mode == Mode.DRUM:
		pivot = to_local(_drum.drum_center())   # 乾燥機の中: 胴の真ん中を見る（カメラは戸の前へ出る）
	elif mode == Mode.SIT and _sit_stage > 0:
		pivot.y -= (doll.eye_point(false).y - doll.eye_point(true).y) * (1.0 if _sit_stage == 2 else 0.55)   # 座った目の高さに合わせて下げる
	var offset := Vector3(0, CAM_RISE, cam_dist + RIDE_CAM_PUSH * ride_fov / RIDE_FOV_MAX).rotated(Vector3.RIGHT, clamp(_pitch, -0.6, 1.0))
	var pivot_w := to_global(pivot)
	_gaze_from = pivot_w
	var orbit_w := to_global(pivot + offset)
	var look := Basis.looking_at(pivot_w - orbit_w, Vector3.UP)
	var reach := (pivot_w - orbit_w).dot(-look.z)
	var shift := cam_frame * reach * tan(deg_to_rad(cam.fov) / 2.0)
	var want_w := orbit_w - look.y * shift
	var floor_y: float = get_parent().height(want_w.x, want_w.z) + 0.4
	if want_w.y < floor_y:
		want_w.y = floor_y
	var ray := want_w - pivot_w
	var free := _cam_clear(pivot_w, ray)
	_cam_free = free if free < _cam_free else move_toward(_cam_free, free, dt * 4.0)
	var at := pivot_w + ray.normalized() * minf(_cam_free, ray.length())
	cam.global_position = at if cam.global_position.distance_to(at) > 2.0 or free < _cam_free + 0.01 \
		else cam.global_position.lerp(at, min(1.0, dt * 10.0))
	# 地面や当たりで動かした所から、もう一度頭へ向け直す（ずらした分は除いて向ける。ずらしは縮めた割合だけ残す）
	var k := minf(_cam_free, ray.length()) / maxf(ray.length(), 0.001)
	var aim_from := cam.global_position + look.y * shift * k
	if aim_from.distance_to(pivot_w) > 0.05:
		cam.global_basis = Basis.looking_at(pivot_w - aim_from, Vector3.UP)


## 乗って滑っている速さから、視野角に足す分を決める。速さは雪のでこぼこで細かく揺れるので、ならしてから使う。
## 一人称も三人称も同じだけ足す（三人称はそのうえでカメラを少し後ろへ引く）
func _update_ride_fov(dt: float) -> void:
	var want := 0.0
	if mode == Mode.RIDE:
		var v := sled.linear_velocity.length()
		want = RIDE_FOV_MAIN * smoothstep(RIDE_FOV_SPEED.x, RIDE_FOV_SPEED.y, v) \
				+ (1.0 - RIDE_FOV_MAIN) * smoothstep(RIDE_FOV_SPEED.y, RIDE_FOV_SPEED.z, v)
	ride_rush = lerpf(ride_rush, want, 1.0 - exp(-dt * (RIDE_FOV_RISE if want > ride_rush else RIDE_FOV_FALL)))
	ride_fov = RIDE_FOV_MAX * ride_rush * ride_fov_amount if ride_fov_enabled else 0.0


## 頭（from）からカメラの向き（ray）へ玉を滑らせ、何にも当たらずに行ける距離を返す。
## 自分と、乗っている・つかんでいるソリの縁の内側は、人形の体と同じくよける（ソリは当たりに入れる。中に潜らない）
func _cam_clear(from: Vector3, ray: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.22
	q.shape = ball
	q.transform = Transform3D(Basis(), from)
	q.motion = ray
	q.exclude = [get_rid()]
	if mode == Mode.DRUM:
		q.exclude = [get_rid(), _drum.body_rid()]   # 乾燥機の中から、戸の外へ
	elif space.get_rest_info(q).size() > 0:   # 頭がもう何かに触れている（座ったソリなど）: ソリは外して測り直す
		q.exclude = [get_rid(), sled.get_rid()]
	var r := space.cast_motion(q)
	return maxf(0.3, ray.length() * r[0] - 0.05)


func _pose_hands(dt: float) -> void:
	var working := pushing or pulling
	var bob := sin(_t * 9.0) if bob_enabled else 0.0
	# 押す・引くと視点がわずかに揺れ、画角が少し広がる
	_update_ride_fov(dt)
	_place_camera(dt, bob, working)
	_save_cam(dt)
	var fov := base_fov + (4.0 if working and fov_kick_enabled else 0.0)
	cam.fov = lerp(cam.fov, maxf(fov, minf(fov + ride_fov, FOV_CAP)), min(1.0, dt * 4.0))
	var fi := Doll.frame_index()
	for h in hands:
		var s: int = h.get_meta("side")
		var target: Vector3
		match mode:
			Mode.GRIP:
				# 縁を握る。押すと腕が少し伸びる。引きずられていると、腕がソリへ引っぱられて伸びきる
				var reach := -0.5 - (0.06 if pushing else 0.0) - 0.12 * _drag_k
				target = Vector3(0.17 * s, -0.22 + (bob * 0.015 if pushing else 0.0) - 0.05 * _drag_k, reach)
				if s < 0 and _drag_k > 0.5:
					# 引きずられている: 左手はソリを離して宙をかく（画面の左上へ大きく輪を描いて出入りする）
					var sw := fi * 0.9
					target = Vector3(-0.42 - 0.1 * cos(sw), 0.05 + 0.18 * sin(sw), -0.5 + 0.08 * cos(sw * 0.5))
			Mode.ROPE:
				# 右手で紐を握り、左手は振る
				if s > 0:
					target = Vector3(0.2, -0.3 - (0.05 if pulling else 0.0), -0.4)
				else:
					target = Vector3(-0.3, -0.3 + sin(_t * 6.0) * 0.01 * velocity.length(), -0.45)
			Mode.RIDE:
				if sled.kind == "sack":
					var k := doll.sack_k("out")
					if k >= 0 and k < 3:
						# 取り出して広げる: 右手を帯へ（画面の下の外）→ 胸の前で両手に → 前へ振り下ろす
						target = [Vector3(0.3 * s, -0.7, 0.05), Vector3(0.1 * s, -0.3, -0.3), Vector3(0.15 * s, -0.42, -0.52)][k]
					else:
						target = cam.to_local(sled.to_global(seat + Vector3(0.2 * s, 0.1, -0.5)))   # 袋の前の左右の耳で紐を握る（まん中の膝が見えるように）
				else:
					target = Vector3(0.28 * s, -0.32, -0.35)
			_:
				target = Vector3(0.27 * s, -0.25 + sin(_t * 6.0 + s) * 0.01 * velocity.length(), -0.48)
				if s < 0 and doll.sleeve_balls > 0:
					# 雪玉のストックを縫い付けた左の袖は、腕時計を見るように前へ上げて、袖の上の雪玉の並びが目に入る角度に
					target = STOCK_HAND + Vector3(0, sin(_t * 6.0) * 0.006 * velocity.length(), 0)
		var em_hand := _emote_hand(s)
		if em_hand != Vector3.INF:
			target = em_hand
		var pointing := (s in Palm.sides_of(hand)) and point_at != Vector3.INF and em_hand == Vector3.INF
		if pointing:
			# 指さし: 選んだ手の手袋を、指している所の向きへ伸ばす（指す先は見ている先を追うので、ふだんは画面の右下（左手は左下））。
			# 手は袖口より手前に出ず、画面の下の隅寄りに置く。人さし指は奥へ倒すので、手が画面のまんなか寄りだと袖口に隠れる
			var d := cam.global_basis.inverse() * (point_at - cam.global_position).normalized()
			target = Vector3(0.17 * s, -0.2, 0.0) + d * 0.46
		# 手も姿勢と同じ決まり: コマが変わるときだけ置き直す（一人称では揺らさない。目の前でふるえると見ていてつらい）。
		# ソリをつかんでいる間は、ソリに対しての位置で保つ（ソリが動いても手が縁から離れない）
		if fi != _hand_frame:
			var on_sled: bool = (mode == Mode.GRIP or (mode == Mode.RIDE and sled.kind == "sack" and doll.sack_seated())) and not pointing and em_hand == Vector3.INF
			h.set_meta("hold", sled.to_local(cam.to_global(target)) if on_sled else target)
			h.set_meta("on_sled", on_sled)
		var hold: Vector3 = h.get_meta("hold", target)
		h.position = cam.to_local(sled.to_global(hold)) if h.get_meta("on_sled", false) else hold
		# 腕は画面の下の肩から手へ伸びる。袖をその向きに
		var arm := h.position - Vector3(0.2 * s, -0.42, 0.12)
		h.basis = Basis.looking_at(arm, Vector3.UP)
	_hand_frame = fi
	_pose_fp_legs(fi)
	# 一人称の雪玉: 作っている途中は大きくなり、できたら右手に
	var em := doll.emote_now()
	var grow := 0.0
	if em[0] == "make_ball" and em[1] >= 4:
		grow = clampf((em[1] - 4) / 12.0, 0.0, 1.0) * 0.6 + 0.4
	elif holding_ball and not (em[0] == "throw" and em[1] < Doll.BALL_BACK):
		grow = 1.0   # 投げたあとは、次の雪玉を左の袖から取るまで少し空く
	_ball_fp.visible = grow > 0.0
	_ball_fp.scale = Vector3.ONE * maxf(grow, 0.01)
	var stock := doll.sleeve_balls + (1 if holding_ball and grow == 0.0 else 0)   # 投げた直後は、次の玉もまだ袖に
	_stock_fp.visible = stock > 0 or holding_ball
	Doll.stock_count(_stock_fp, stock)
	_face_stock_fp()
	_place_held_fp(grow > 0.0)
	_face_held_fp()
	_fp_table_step()
	_place_shapes_fp(em)
	_update_hold_tag(dt)


## 一人称の左の袖口のストックを、袖の筒の上で目のほうへ向ける（袖のどこが見えていても、雪玉の並びが見える）
func _face_stock_fp() -> void:
	var h: Node3D = _stock_fp.get_parent()
	var to_eye := h.basis.inverse() * -h.position
	var d := Vector3(to_eye.x, to_eye.y, 0.0)
	d = d.normalized() if d.length() > 0.001 else Vector3.UP
	var p0 := d * (FpHands.sleeve_r(STOCK_Z.x, doll.kind) + 0.002) + Vector3(0, 0, STOCK_Z.x)
	var p1 := d * (FpHands.sleeve_r(STOCK_Z.y, doll.kind) + 0.002) + Vector3(0, 0, STOCK_Z.y)
	var along := (p1 - p0).normalized()
	var out := d - along * d.dot(along)
	_stock_fp.transform = Transform3D(Basis(along.cross(out.normalized()), along, out.normalized()), p0)


## 一人称の手形: 手の先に置く。手のひらは前（相手）へ向け（自分からは手の甲が見える）、低い手のひらは下へ向ける。
## 指さしの手には指さしの手形。ハイタッチ・握手は合う手に。形は人形と同じコマで
func _place_shapes_fp(em: Array) -> void:
	var kind: String = em[0]
	var k: int = em[1]
	var want := {1: "", -1: ""}
	var mode := {1: "", -1: ""}
	for sd in [1, -1]:
		var height: String = doll.hand_shapes[0 if sd > 0 else 1]
		if height != "":
			want[sd] = "palm"
			mode[sd] = height
	if point_at != Vector3.INF:
		for sd in Palm.sides_of(hand):
			want[sd] = "point"
			mode[sd] = "point"
	var touching := k >= 0 and kind in ["high_five", "shake", "whiff"]
	if touching:
		want = {1: "", -1: ""}
		if kind == "whiff":
			if k < 3:
				want[int(_em.get("side", 1))] = "palm"
				mode[int(_em.get("side", 1))] = kind
		elif (kind == "high_five" and k < 8) or (kind == "shake" and k < 20):
			for gr in _em.get("grips", []):
				want[int(gr[0])] = "palm"
				mode[int(gr[0])] = kind
	elif (k >= 0 and kind in Doll.ARM_EMOTES) or _winding:
		want = {1: "", -1: ""}
	# 手形を出している手は、袖口の紙のミトンを隠す（人形と同じ決まり。2026-11-02 代表「エモートで手のワッペン出すとき、
	# 元のキャラの手は一時的に消してほしい」。指さしでは、奥へ伸ばした手形のこぶしを手前のミトンがふさぐのでもあった）
	for hh in hands:
		var mitt: bool = want[int(hh.get_meta("side"))] == ""
		hh.get_node("Mitten").visible = mitt
		hh.get_node("MittenThumb").visible = mitt
	# 右手に持った物（雪玉・持ち物）も、手と一緒に隠す。残すと、手のない所に物だけ浮いて手形に重なる（人形も手ごと隠れる）
	if want[1] != "":
		_ball_fp.visible = false
	if _held_fp:
		_held_fp.visible = want[1] == ""
	for sh in _shapes_fp:
		for side in [1, -1]:
			var node: Node3D = _shapes_fp[sh][side]
			var on: bool = want[side] == sh
			node.visible = on
			if not on:
				continue
			var size := Palm.pop(Doll.frame_index() - doll._hands_frame)
			var b := Basis(Vector3.UP, PI)
			var h: Node3D = hands[0] if hands[0].get_meta("side") == side else hands[1]
			var wrist := h.position   # 手形の手首の真ん中を置く所
			match mode[side]:
				"point":
					# 人さし指の手形は、画面の中で床に平行に（水平に、画面のまんなかの側へ）向け、手の甲を自分へ向ける。
					# 腕の伸びる向きに合わせると、画面の中で指が斜め上を向き、どこを指しているか読みにくかった
					# （2026-10-31 代表「指差しは床に平行な方が見やすい」。腕ではなく指のワッペンのこと）。--point-tilt で前の向き
					var y: Vector3
					var z: Vector3
					if point_level:
						# 人さし指を、一人称のパースに沿わせて奥へ伸ばす: 指の向きは、カメラの座標での「人さし指の付け根 → 指している所」の
						# 3D の向きそのもの。指している所は画面のまんなかの奥なので、指は遠くへ縮み、指の線は画面のまんなかを通る
						# （2026-10-31 代表「人差し指が消失点に向かってほしい」「消失点は平面でなく立体で捉えて、3D パースに添わせてほしい」。
						# 前の、画面の中で消失点へ回してから決まった角度だけ奥へ倒す作りはやめた）。
						# 手形の面は床に平行（手のひらが下、甲が上。手は目より下なので、上から甲が見える）。浅く見えて細すぎるので、
						# point_lift 度だけ面を目のほうへ起こす。親指は内側、小指は外側（輪郭の親指は右手 +x・左手 -x。x = y × z で内側に来る）。
						# 人さし指は手首の真ん中より内側にあるので、指の付け根から向きを決める（2 回で落ち着く）
						var aim := cam.to_local(point_at)
						var down := cam.global_basis.inverse() * Vector3.DOWN
						var lift := deg_to_rad(point_lift)
						var root := h.position
						size = POINT_FP_SIZE
						for _i in 2:
							y = (aim - root).normalized() if aim.distance_to(root) > 0.05 else Vector3.FORWARD
							var flat := down - y * down.dot(y)   # 手のひらを下へ（指に直角に）
							flat = flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
							var eye := h.position.normalized()
							var face := eye - y * eye.dot(y)     # 手のひらを目から向こうへ（甲をこちらへ）
							face = face.normalized() if face.length() > 0.05 else flat
							z = (flat * cos(lift) + face * sin(lift)).normalized()
							b = Basis(y.cross(z).normalized(), y, z)
							wrist = h.position + y * POINT_FP_OUT   # 手首を袖口から少し前へ出す（こぶしが袖口に隠れないように）
							root = wrist + b * (Palm.POINT_ROOT * Vector3(side, 1, 1) - Palm.WRIST) * size
					else:
						y = (h.basis * Vector3.FORWARD).normalized()
						z = Vector3.UP.cross(y) * float(side)
						z = z.normalized() if z.length() > 0.05 else Vector3.BACK
						b = Palm.thumb_up(Basis(y.cross(z).normalized(), y, z), side)   # 親指は上
						size = 1.0
				"low":
					b = b * Basis(Vector3.RIGHT, -0.65)   # 下へ向けて、おさえる
				"shake":
					# 握手: 人形と同じに、重ねる所（配り役が決めた、二人で平行な少し傾いた面）へ。合わせたら二人一緒に上下に振る
					var wb := Palm.shake_basis(_em.get("fwd", -global_basis.z), _em.get("axis", global_basis.x), side)
					var at: Vector3 = h.global_position
					for gr in _em.get("grips", []):
						if int(gr[0]) == side:
							at = (gr[1] as Vector3) + Vector3.UP * Palm.shake_pump(k) if k >= 2 else (gr[1] as Vector3).lerp(h.global_position, 0.5)
					node.global_transform = Transform3D(wb.scaled(Vector3.ONE * Palm.BIG), at)
					continue
				"high_five", "whiff":
					b = b * Basis(Vector3.RIGHT, 0.5 if k < 3 else 0.0)
					size = 1.25 if k == 3 and kind == "high_five" else 1.0
			# 手形の手首の真ん中を、袖の先（手の所）に合わせる
			var bs := b.scaled(Vector3.ONE * size)
			node.transform = Transform3D(bs, wrist - bs * Palm.WRIST)


# ---------------------------------------------------------------- 身ぶり（emotes.gd）

## いまできる身ぶり。声はいつでも。吐く息・拍手はその場でする身ぶりの途中でなければ。雪玉づくりはしゃがんでいるときだけ
func available() -> Dictionary:
	var busy := rooted() or _winding
	return {
		"wa": true, "un": true, "nn": true, "huh": true, "oi": true,
		"breath": not busy,
		"clap": not busy and hands_name == "high_both",
		"make_ball": not busy and mode == Mode.WALK and ball_count() < Emotes.BALL_MAX and crouching,
	}


## 輪か数字キーで選んだもの: 高い・低い手のひら（同じものをもう一度選ぶと下ろす）、指さし、声
func _choose(k: String) -> void:
	match k:
		"high", "low":
			set_height("" if _height() == k else k)
		"point":
			toggle_point()
		_:
			emote(k)


## いま掲げている高さ（"high" "low" ""）
func _height() -> String:
	return hands_name.split("_")[0] if hands_name != "" else ""


## 手のひらを掲げる・下ろす（配り役へ送る）。いまの手（右・左・両手）で。指さしていれば、指さしをやめる
func set_height(height: String) -> void:
	if height != "" and pointing:
		_stop_point()
	set_hands(Palm.hands_name(height, hand))


## 身ぶりに使う手を替える。掲げているなら、その手で掲げ直す
func _set_hand(h: String) -> void:
	hand = h
	if ring:
		ring.set_hand(h)
	if _height() != "":
		set_hands(Palm.hands_name(_height(), hand))


## 乗って滑っているあいだ（止まりかけ・ペグで留めたソリは入れない。hud.gd が A・D と S の案内を出すのと同じ）
func gliding() -> bool:
	return mode == Mode.RIDE and is_instance_valid(sled) and sled.peg == null and sled.linear_velocity.length() >= 1.0


## 滑っているあいだに Space で万歳できる（米袋のように Space で漕ぐソリは、漕ぐほう）
func space_hands_up() -> bool:
	return gliding() and float(sled.KINDS[sled.kind].get("kick", 0.0)) <= 0.0


## 両手を高く上げる（万歳）・下ろす。滑っているあいだの 1 と Space
func toggle_hands_up() -> void:
	if hands_name == "high_both":
		set_hands("")
		return
	if pointing:
		_stop_point()
	set_hands("high_both")


## 手を変える（配り役へ送る。"" は下ろす）
func set_hands(name_: String) -> void:
	if hub == null or name_ == hands_name:
		return
	hub.send({"kind": "hands", "who": id, "hands": name_})


## 左クリック: 雪玉があれば振りかぶる（離すと投げる。持ち物を手に持っていれば、しまって雪玉を出す）。高い両手のひらなら拍手
func _left_click() -> void:
	if craft and FoodMenu.done(held()):   # できあがった料理を持っていれば、押しているあいだ食べる（雪玉より先）
		_eating = true
		_bite()
		return
	if craft and held().get("kind", "") == "peg":   # ペグを持っていれば、ソリの前の雪に刺して紐を結ぶ（雪玉は投げない）
		plant_peg()
		return
	if ball_count() > 0 and mode != Mode.DRUM:   # 乾燥機の中からは投げない
		if not held().is_empty() and craft:
			craft.send({"kind": "hand", "who": id, "slot": -1})
		if not hub.can_throw(id):
			_wind_wait = true
			return
		holding_ball = held().is_empty()
		wind_up()
	elif hands_name == "high_both":
		emote("clap")


# ---------------------------------------------------------------- 雪合戦の対決（duel.gd）

## 戦っているあいだは円の中（見えない壁）。ソリをつかんだり乗ったりして円の外へ出たら、手を離す・降りる
func _keep_in_duel() -> void:
	var duel := get_parent().get_node_or_null("Duel")
	if duel == null or duel.fighting(id).is_empty():
		return
	if mode == Mode.WALK:
		duel.keep_in(self, id)
		return
	var d: Dictionary = duel.fighting(id)
	var off := Vector2(global_position.x - d.at.x, global_position.z - d.at.z)
	if off.length() > duel.RADIUS:
		if mode == Mode.GRIP or mode == Mode.ROPE:
			let_go()
		elif mode == Mode.RIDE:
			get_off()


# ---------------------------------------------------------------- ペグ（peg.gd・sled.gd の peg_to）

const PEG_AHEAD := 0.7        # ペグを刺す所: 足もとから見ている向きへ (m)
const PEG_REACH := 1.5        # 歩いていて F でペグを抜ける距離（水平, m）
const PEG_RIDE_REACH := 4.2   # 乗ったまま F で、乗っているソリのペグを抜ける距離 (m)。前の席からなら届く


## 手のペグを刺せるソリと、刺す所 [ソリ, 雪の点]。刺せなければ []。
## 雪の上で（ロッジの床には刺さない）、足もとの少し前が、まだ留めていないソリの引き紐の届く所
func peg_target() -> Array:
	if craft == null or held().get("kind", "") != "peg" or not (mode == Mode.WALK or mode == Mode.ROPE) or menu_open:
		return []
	var w := get_parent()
	if not w.has_method("height"):
		return []
	var fwd := -global_basis.z
	fwd.y = 0.0
	var at := global_position + fwd.normalized() * PEG_AHEAD
	at.y = w.height(at.x, at.z) + (w.snow_lift(at.x, at.z) if w.has_method("snow_lift") else 0.0)
	if absf(at.y - global_position.y) > 0.8 or (w.has_method("lodge_weight") and w.lodge_weight(at.x, at.z) < 1.0):
		return []
	var best: RigidBody3D = null
	var near := INF
	for s in get_tree().get_nodes_in_group("sleds"):
		if not is_instance_valid(s) or not s.visible or s.freeze or s.peg != null or not s.has_method("rope_root"):
			continue
		var d: float = at.distance_to(s.rope_root())
		if d <= s.ROPE_LEN and d < near:
			best = s
			near = d
	return [best, at] if best else []


## 手のペグを刺す（出来事を出す。刺さるのは配られてから）
func plant_peg() -> bool:
	var pt := peg_target()
	if pt.is_empty():
		return false
	if mode == Mode.ROPE:
		let_go()   # 持っていた紐は、そのままペグに結ぶ
	var ok: bool = craft.send({"kind": "peg", "who": id, "slot": int(craft.hands.get(id, -1)), "sled": craft.sled_path(pt[0]), "at": pt[1]})
	var hud = get_parent().get("hud")
	if ok and hud:
		hud.learn("peg")
	return ok


## F で抜けるペグの刺さったソリ（なければ null）。歩いていればそばのペグ、乗っていれば乗っているソリのペグ
func peg_near() -> RigidBody3D:
	if craft == null or menu_open:
		return null
	if mode == Mode.RIDE:
		if sled and "peg" in sled and is_instance_valid(sled.peg) and sled.peg.global_position.distance_to(global_position) < PEG_RIDE_REACH:
			return sled
		return null
	if mode != Mode.WALK:
		return null
	var best: RigidBody3D = null
	var near := PEG_REACH
	for s in get_tree().get_nodes_in_group("sleds"):
		if not is_instance_valid(s) or not ("peg" in s) or not is_instance_valid(s.peg):
			continue
		var d := Vector2(s.peg.global_position.x - global_position.x, s.peg.global_position.z - global_position.z).length()
		if d < near:
			best = s
			near = d
	return best


func pull_peg(s: RigidBody3D) -> bool:
	var ok: bool = craft.send({"kind": "unpeg", "who": id, "sled": craft.sled_path(s)})
	var hud = get_parent().get("hud")
	if ok and hud:
		hud.learn("unpeg")
	return ok


## 手の料理を食べ始める（装備の画面の「食べる」）。食べ終わるまでひと口ずつ続ける
func eat_held() -> void:
	if craft and FoodMenu.done(held()):
		_eating = true
		_bite()


## 手の料理をひと口: 右手を口へ運んでもぐもぐ（emotes.gd の eat）。噛むコマで持ち物のひと口を数える（_eat_step）
func _bite() -> void:
	var c := table_ctx()
	if not c.is_empty():   # 机のある席: 食べ物に合った食べ方で
		_bite_table(c)
		return
	var it := held()
	if hub == null or menu_open or not FoodMenu.done(it) or (not _em.is_empty() and _em.kind == "eat" and _em_k() < 16):
		return
	hub.send({"kind": "eat", "who": id, "dish": it.dish, "last": int(it.get("bites", 0)) >= FoodMenu.BITES - 1})


## 机のある席で座りきっていて、手にできあがった料理があるときの状況（table_eat.gd の ctx）。それ以外は空
func table_ctx() -> Dictionary:
	if seats == null or mode != Mode.SIT or seat_i < 0 or _sit_stage != 2 or _stand_frame >= 0 or craft == null:
		return {}
	return TableEat.ctx(seats.seat(seat_i), held())


func _bite_table(c: Dictionary) -> void:
	if hub == null or menu_open:
		return
	var seamless := false
	if not _em.is_empty() and _em.kind == "eat_t":
		var k := _em_k()
		if k < int(_em.len) - 1:
			return
		seamless = _em.style == "slurp"   # すすり続ける: 箸を下ろさず、切れ目なく
	_te_done = {}
	hub.send(TableEat.event(id, c, not seamless))


## 机での食べ方の進み（毎フレーム）: 決まったコマで音、ひと口を数える。押し続けていれば切れ目なく次へ
func _eat_table_step() -> void:
	var k := _em_k()
	var spec: Dictionary = TableEat.STYLES.get(_em.style, {})
	var audio = get_parent().get_node_or_null("Audio")
	if audio and spec.snd.has(k) and not _te_done.has(k):
		_te_done[k] = true
		audio.eat(self, spec.snd[k][0], spec.snd[k][1], true)
	if k >= int(spec.bite) and not _te_done.has("bite") and craft:
		_te_done["bite"] = true
		var ev := {"kind": "bite", "who": id, "slot": craft.hands.get(id, -1)}
		if craft.send(ev) and ev.has("ate"):
			_eating = false
			if audio:
				audio.eat(self, "eat_ah", 2, true)
	if k >= int(_em.len) - 1 and _eating and FoodMenu.done(held()):
		_bite()


## 机のある席の、一人称の手の基準: 目の所で、席の向きに水平（カメラと違って下を向かない。下を向くと手が机に潜る）
func _fp_table_frame(c: Dictionary) -> Transform3D:
	return Transform3D(Basis.looking_at(c.face, Vector3.UP), cam.global_position)


## その基準での、一人称の手に渡す点
func _fp_table_anchors(c: Dictionary) -> Dictionary:
	var dish: Vector3 = _fp_table_frame(c).affine_inverse() * (c.at + Vector3.UP * 0.05)
	return {"mouth": Vector3(0.02, -0.07, -0.22), "near": Vector3(0.03, -0.17, -0.42), "lift": Vector3(0.05, -0.05, -0.4), "lip": Vector3(0.0, -0.26, -0.1), "rest_r": Vector3(0.24, -0.34, -0.34), "rest_l": Vector3(-0.24, -0.34, -0.34),
			"l_table": Vector3(-0.28, -0.4, -0.3), "dish": dish, "right": Vector3.RIGHT, "up": Vector3.UP, "hold_w": TableEat.HOLD_W, "tool": TableEat.TOOL_LEN}


## 机の皿と、一人称の手の道具（毎フレーム）。三人称では人形の分（doll.gd の _eat_rig_step）が見える
func _fp_table_step() -> void:
	var c := table_ctx() if not third else {}
	if c.is_empty() and _fp_rig == null:
		return
	if _fp_rig == null:
		_fp_rig = TableEat.Rig.new(1 << 2)
		add_child(_fp_rig)
	if c.is_empty():
		_fp_rig.step({}, {}, -1, {}, Basis.IDENTITY, 1.0, 1.0, Vector3.ZERO)
		return
	var em := doll.emote_now()
	var active: bool = em[0] == "eat_t" and not _em.is_empty() and _em.kind == "eat_t"
	var pw := {}
	var mouth := Vector3.ZERO
	var xf := _fp_table_frame(c)
	if active:
		var A := _fp_table_anchors(c)
		var pt: Dictionary = TableEat.pose(_em.style, em[1], _em.first, A)
		mouth = xf * (A.lip as Vector3)   # 麺が吸い込まれる先（一人称では画面の下の外）
		pw = {"r": xf * (pt.r as Vector3), "l": xf * (pt.l as Vector3), "tilt": pt.tilt, "carry": pt.carry, "item": null, "tip": null, "tip_l": null}
		if pt.item != null:
			pw.item = xf * (pt.item as Vector3)
		if pt.tip != null:
			pw.tip = xf * (pt.tip as Vector3)
		if pt.tip_l != null:
			pw.tip_l = xf * (pt.tip_l as Vector3)
	_fp_rig.step(c, _em if active else {}, em[1] if active else -1, pw, xf.basis, 0.72, 1.0, mouth)


## 食べているひと口の進み（毎フレーム）: 5 コマ目で音、10 コマ目でひと口を数える。押し続けていれば次のひと口
func _eat_step() -> void:
	if not _em.is_empty() and _em.kind == "eat_t":
		_eat_table_step()
		return
	if _em.is_empty() or _em.kind != "eat":
		if _eating:
			_bite()
		return
	var k := _em_k()
	var audio = get_parent().get_node_or_null("Audio")
	if k == 5 and _bit_frame != int(_em.frame) * 10 + 5:
		_bit_frame = int(_em.frame) * 10 + 5
		var snd: Array = FoodMenu.bite_sound(_em.dish)
		if audio:
			audio.eat(self, snd[0], snd[1], true)
	if k == 10 and _bit_frame != int(_em.frame) * 10 + 9 and craft:
		_bit_frame = int(_em.frame) * 10 + 9
		var ev := {"kind": "bite", "who": id, "slot": craft.hands.get(id, -1)}
		if craft.send(ev) and ev.has("ate"):
			_eating = false
			if audio:
				audio.eat(self, "eat_ah", 2, true)
	# 一人称: 手の料理を口もと（画面の下のまんなか）へ運び、噛むあいだ小さく揺らす。人形の腕と同じ割合で寄せる
	if _held_fp and is_instance_valid(_held_fp) and not third:
		var f: float = [0.0, 0.45, 0.85, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.7, 0.35, 0.1, 0.0][clampi(k, 0, 15)] if k >= 0 and k < 16 else 0.0
		_held_fp.position = Vector3(-0.02, 0.05, -0.08)
		var vc := _held_fp.get_viewport().get_camera_3d()   # 一人称の手は、手だけを描く視点にいる。その視点の口もと
		if f > 0.0 and vc:
			var mouth := vc.to_global(Vector3(0.02, -0.075 + (0.01 if (k / 2) % 2 == 0 else 0.0), -0.3))   # 画面の下寄りのまんなか
			_held_fp.global_position = _held_fp.global_position.lerp(mouth, f)
	if k >= 16 and _eating and FoodMenu.done(held()):
		_bite()


## 身ぶりを出す（配り役へ送る。自分の人形も、配られた出来事で動く）
func emote(kind: String) -> void:
	if hub == null or menu_open or not available().get(kind, false):
		return
	hub.send({"kind": kind, "who": id})


## その場でする身ぶりの途中か（歩けない、つかめない）
func rooted() -> bool:
	if Doll.frame_index() < busy_until:   # 裁ちばさみで糸を切っているあいだ
		return true
	if _em.is_empty():
		return false
	var spec: Dictionary = Emotes.KINDS.get(_em.kind, {})
	return spec.get("root", false) and _em_k() < spec.frames


func _em_k() -> int:
	return Doll.frame_index() - int(_em.frame) if not _em.is_empty() else -1


func _on_emote(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	if ev.kind == "hands":
		hands_name = ev.hands
		doll.play(ev)
		return
	_em = ev
	doll.play(ev)
	match ev.kind:
		"hit":
			_winding = false   # びっくりして振りかぶりが解ける（雪玉は持ったまま）
			# びっくりしてソリの縁や紐から手を離す（乗っている人は降ろさない）。止めるにはもう一度 F
			if mode == Mode.GRIP or mode == Mode.ROPE:
				let_go()


## 持っている雪玉の数（配り役が数える。左の袖のストックと右手の分を合わせて）
func ball_count() -> int:
	return hub.balls_of(id) if hub else 0


## 左クリックを押した: 振りかぶる
func wind_up() -> void:
	if not holding_ball or _winding or rooted() or hub == null:
		return
	_winding = true
	_wind_t = 0.0
	hub.send({"kind": "windup", "who": id})


## 左クリックを離した: 見ている向きへ投げる。長く振りかぶるほど速い。乗っていればソリの速さも乗る
func throw_ball() -> void:
	if not _winding:
		return
	_winding = false
	var power := clampf(_wind_t / 0.8, 0.0, 1.0)
	var speed := lerpf(7.0, 16.0, power)
	# 向きは体の向きと見上げる角度から（三人称のカメラは後ろ上から見下ろすので、カメラの向きでは足もとへ飛ぶ）
	var aim := global_basis * (Basis(Vector3.RIGHT, _pitch) * Vector3.FORWARD)
	var dir := (aim + Vector3.UP * 0.14).normalized()
	var origin: Vector3
	if third:
		origin = global_position + Vector3.UP * doll.height() * 0.85 + doll.global_basis * Vector3(0.18, 0, -0.45)
	else:
		origin = cam.to_global(Vector3(0.14, -0.06, -0.45))
	var carry: Vector3 = sled.linear_velocity if mode == Mode.RIDE else velocity
	hub.send({"kind": "throw", "who": id, "origin": origin, "velocity": dir * speed + carry})


func _update_emote(dt: float) -> void:
	if _wind_wait and hub.can_throw(id) and not rooted():
		_wind_wait = false
		holding_ball = ball_count() > 0 and held().is_empty()
		wind_up()
	if _catching >= 0 and not get_parent().duel.reach_for(self, _catching):
		_catching = -1
	if _winding:
		_wind_t += dt
	crouching = mode == Mode.WALK and Input.is_physical_key_pressed(KEY_CTRL) and not menu_open
	# 滑りながら高い両手のひらにすると、ひとりでに「ワ〜」
	var sliding := mode == Mode.RIDE and sled.linear_velocity.length() > 2.5
	if hands_name == "high_both" and sliding and not _auto_wa:
		_auto_wa = true
		if hub:
			hub.send({"kind": "wa", "who": id, "auto": true})
	elif hands_name != "high_both" or (mode == Mode.RIDE and sled.linear_velocity.length() < 1.0):
		_auto_wa = false
	if _exhaling:
		_exhale_t += dt
		if _exhale_t > Emotes.EXHALE_MAX:
			_stop_exhale()   # 息が続くのは 5 秒まで
	var want := Vector3.ZERO
	var k := _em_k()
	if not _em.is_empty():
		want = _emote_cam(_em.kind, k)
	if not bob_enabled and not (not _em.is_empty() and _em.kind == "make_ball"):
		want *= 0.3   # 視点の揺れを切っていれば控えめに（しゃがむ高さだけはそのまま）
	if crouching:
		want.z = minf(want.z, -CROUCH_EYE)   # しゃがむと目が下がる
	_cam_em = _cam_em.lerp(want, minf(1.0, dt * 12.0))
	var roll := 0.0
	if not _em.is_empty() and _em.kind == "huh" and k >= 2 and k < 14:
		roll = -0.12 * (1.0 if k < 10 else (14 - k) / 4.0) * (1.0 if bob_enabled else 0.4)
	_cam_roll = lerpf(_cam_roll, roll, minf(1.0, dt * 10.0))


## 身ぶりの一人称の視点（x 上下の向き、y 左右の向き、z 高さ）。人形の頭と同じ形を、小さく
func _emote_cam(kind: String, k: int) -> Vector3:
	var n: int = Emotes.KINDS.get(kind, {}).get("frames", 0)
	if k < 0 or (n > 0 and k >= n):
		return Vector3.ZERO
	match kind:
		"eat_t":
			return _table_eat_cam(k)
		"un":
			return Vector3([-0.06, -0.15, -0.15, -0.06, 0.0, 0.0, 0.0][k], 0, 0)
		"nn":
			return Vector3(-0.02, [0.07, 0.07, -0.07, -0.07, 0.07, 0.07, -0.06, -0.06, 0.04, 0.04, -0.02, -0.02, 0.0, 0.0][k], 0)
		"make_ball":
			var s := 1.0 if k < 16 or crouching else 1.0 - Doll._ease((k - 16) / 5.0)
			return Vector3(-0.5 * s, 0, -CROUCH_EYE * s)
		"breath":
			var b := Doll.exhale_curve(k, _em.has("until"), int(_em.get("until", 0)) - int(_em.frame))
			return Vector3(0.14 * b, 0, 0.02 * b)
		"hit":
			var f: float = [0.55, 0.6, 0.5, 0.45, 0.4, 0.35, 0.3, 0.2, 0.12, 0.08, 0.05, 0.03, 0.0, 0.0, 0.0, 0.0][k]
			var shake := (0.05 if k % 2 == 0 else -0.05) if k >= 8 and k < 14 else 0.0
			return Vector3(0.28 * f, shake, 0)
		"whiff":
			return Vector3(-0.12 if k >= 2 and k < 8 else 0.0, 0.08 if k >= 2 and k < 5 else 0.0, 0)
		"wa":
			return Vector3(-0.04 if k < 2 else 0.08, 0, 0)
		"oi":
			return Vector3(-0.05 if k < 2 else (0.1 if k < 15 else 0.03), 0, 0)   # 顔を上げて呼ぶ
	return Vector3.ZERO


## 机で食べているあいだの視点: 皿を見下ろす。持ち上げる食べ方は、持ち上げたら顔を上げる。長さは ev.len
func _table_eat_cam(k: int) -> Vector3:
	var c := table_ctx()
	if c.is_empty() or k >= int(_em.len):
		return Vector3.ZERO
	var d: Vector3 = c.at - cam.global_position
	var flat := Vector2(d.x, d.z).length()
	var lifts: bool = TableEat.STYLES[_em.style].has("hold")
	var f := 0.8 if not lifts else (0.5 if k < 3 or k >= int(_em.len) - 3 else 0.25)
	if _em.style == "slurp" and (not _em.first or k >= TableEat.SLURP_LIFT):
		f = 0.4   # すすっているあいだは顔を上げ、器から口へのびる麺が見える
	var yaw := wrapf(atan2(-d.x, -d.z) - rotation.y, -PI, PI)
	var nod: float = TableEat.pose(_em.style, k, _em.first, _fp_table_anchors(c)).nod
	return Vector3(clampf(atan2(d.y, flat) - _pitch, -1.0, 0.6) * f + nod * 0.5, yaw * f, 0.09)   # 少し身を乗り出して、皿の中を見る


## 身ぶりの一人称の手（カメラの座標）。身ぶりでなければ INF
func _emote_hand(s: int) -> Vector3:
	if _winding:
		return Vector3(0.33, 0.0, -0.36) if s > 0 else Vector3(-0.1, -0.1, -0.62)   # 右手（雪玉）を画面の右端へ引き、左手で狙う
	var em := doll.emote_now()
	var kind: String = em[0]
	var k: int = em[1]
	# 掲げた手のひら: 高い手は画面の上のほう、低い手は下のほう（腕を使う身ぶりのあいだは出さない）
	var height: String = doll.hand_shapes[0 if s > 0 else 1]
	if height != "" and not (k >= 0 and kind in Doll.ARM_EMOTES):
		return Vector3(0.2 * s, 0.04, -0.5) if height == "high" else Vector3(0.2 * s, -0.3, -0.5)
	if k < 0:
		return Vector3.INF
	var mine := []   # この身ぶりで使う手
	for gr in _em.get("grips", []):
		mine.append(int(gr[0]))
	match kind:
		"eat_t":
			var c := table_ctx()
			if not c.is_empty() and k < int(_em.len):
				var pt: Dictionary = TableEat.pose(_em.style, k, _em.first, _fp_table_anchors(c))
				return cam.to_local(_fp_table_frame(c) * ((pt.r if s > 0 else pt.l) as Vector3))
		"high_five":
			if s in mine:
				if k < 3:
					return Vector3(0.36 * s, 0.16, -0.26)   # ため: 画面の外側へ引く
				if k < 6:
					return Vector3(0.05 * s, 0.06, -0.58)   # 叩きつける: まんなかで手が合う
				return Vector3(0.15 * s, -0.3, -0.5)
		"shake":
			if s in mine:
				if k < 2:
					return Vector3(0.14 * s, -0.27, -0.45)   # 差し出す
				if k < 20:
					# 握って、上下に振る: 袖の先を、重ねる所に置いた手形の手首へ
					for gr in _em.grips:
						if int(gr[0]) == s:
							var wb := Palm.shake_basis(_em.get("fwd", -global_basis.z), _em.get("axis", global_basis.x), s).scaled(Vector3.ONE * Palm.BIG)
							return cam.to_local((gr[1] as Vector3) + Vector3.UP * Palm.shake_pump(k) + wb * Palm.WRIST)
				return Vector3(0.25 * s, -0.3, -0.45)
		"whiff":
			var ws := int(_em.get("side", 1))
			if s == ws:
				if k < 2:
					return Vector3(0.32 * s, 0.14, -0.3)
				if k < 4:
					return Vector3(-0.08 * s, -0.12, -0.6)   # 振り抜く
				return Vector3(-0.05 * s, -0.38, -0.45)
		"breath":
			var b := Doll.exhale_curve(k, _em.has("until"), int(_em.get("until", 0)) - int(_em.frame))
			return Vector3(s * (0.27 + 0.16 * b), -0.25 + 0.1 * b, -0.48)
		"make_ball":
			if k >= 4 and k < 16:
				var up := 0.035 if ((k / 2) % 2 == 0) == (s > 0) else 0.0
				return Vector3(s * 0.08, -0.2 + up, -0.4)
			if k >= 16 and s > 0:
				return Vector3(0.12, -0.2, -0.42)
		"throw":
			if s > 0:
				if k == 0:
					return Vector3(0.12, 0.0, -0.66)
				if k < 3:
					return Vector3(-0.04, -0.34, -0.56)
				if k < Doll.BALL_BACK + 1 and ball_count() > 0:
					return Vector3(-0.08, -0.17, -0.4)   # 左の袖のストックから次の 1 つを取る
			elif k >= 2 and k < Doll.BALL_BACK + 1 and ball_count() > 0:
				return STOCK_HAND + Vector3(-0.04, -0.06, 0.04)   # 左の袖は少し寄せて、右手に差し出す
		"hit":
			if k < 8:
				return Vector3(s * 0.26, 0.0, -0.4)
			if k < 14:
				return Vector3(s * 0.15, -0.18 + (0.04 if (k % 2 == 0) == (s > 0) else 0.0), -0.36)
		"clap":
			var gap: float = [0.32, 0.14, 0.03, 0.2][k % 4]
			return Vector3(s * gap * 0.5, -0.17, -0.42)
		"catch":
			# 両手をまんなかへ突き出して、ぱっと包み、胸へ引き寄せる（雪玉の対決のキャッチ）
			if k < 2:
				return Vector3(s * 0.09, 0.02, -0.62)
			if k < 6:
				return Vector3(s * 0.05, -0.1 - 0.03 * (k - 2), -0.5 + 0.03 * (k - 2))
			return Vector3(s * 0.12, -0.26, -0.4)
		"wa":
			if k < 2:
				return Vector3(s * 0.2, -0.38, -0.4)
			if k < 11:
				return Vector3(s * 0.34, 0.0, -0.45)
		"huh":
			if k >= 2 and k < 12:
				return Vector3(s * 0.3, -0.3, -0.42)   # さあ？と両手を少し外へ
		"oi":
			# 空いた手（手のひらも指さしもしていない手。右から）を口の横へ。画面の下の端に、手袋の先がのぞく
			if k >= 1 and k < 16:
				var free := 0
				for sd in [1, -1]:
					if free == 0 and doll.hand_shapes[0 if sd > 0 else 1] == "" and not (point_at != Vector3.INF and sd in Palm.sides_of(hand)):
						free = sd
				if s == free:
					return Vector3(0.1 * s, -0.2, -0.22)
		"nn":
			if s > 0 and k < 12:
				return Vector3(0.04 + (0.06 if (k / 2) % 2 == 0 else -0.06), -0.08, -0.32)   # 顔の前で手を振る
	return Vector3.INF


## B を離した（または息が切れた）: 吐くのをやめる
func _stop_exhale() -> void:
	if not _exhaling:
		return
	_exhaling = false
	if hub:
		hub.send({"kind": "breath_end", "who": id})


## 見ている先の近くに雪面があるか（しゃがんで手が届く所。地面の当たりは高さの地図）
func _snow_ahead() -> bool:
	var from := cam.global_position
	var to := from - cam.global_basis.z * 2.2
	if third:
		# 三人称ではカメラが人形の後ろ上にあり、カメラからの線は雪に届かない。人形の胸から、足もとの少し先の雪面へ
		var fwd := -global_basis.z
		fwd.y = 0
		from = global_position + Vector3.UP * 0.9
		to = global_position + fwd.normalized() * 0.7 + Vector3.DOWN * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.5:
		return false
	for c in (hit.collider as Node).get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is HeightMapShape3D:
			return true
	return false


# ---------------------------------------------------------------- 焚き火（campfire.gd）

const FIRE_AHEAD := 1.3      # 焚き火を組む所: 体の前 (m)
const FIRE_GAP := 1.6        # ほかの焚き火とのあいだ (m)
const FIRE_REACH := 2.0      # F で自分の焚き火を消せる距離 (m)

## 手の焚き火セットを組める所 {at, yaw, up}（組めなければ {}）: 外の、前の雪の上（雪の地面。ソリや家の上でなく、急すぎない）
func fire_spot() -> Dictionary:
	if craft == null or mode != Mode.WALK or held().get("kind", "") != "campfire":
		return {}
	var fwd := -global_basis.z
	fwd.y = 0.0
	var at := global_position + fwd.normalized() * FIRE_AHEAD
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 3.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.85 or not Campfire.outside(get_tree(), hit.position):
		return {}
	var snow := false
	for c in (hit.collider as Node).get_children():
		snow = snow or (c is CollisionShape3D and (c as CollisionShape3D).shape is HeightMapShape3D)
	if not snow:
		return {}
	for f in craft.fires.values():
		if is_instance_valid(f) and f.lit() and (f as Node3D).global_position.distance_to(hit.position) < FIRE_GAP:
			return {}
	return {"at": hit.position, "yaw": rotation.y, "up": hit.normal}


func lay_fire() -> bool:
	var spot := fire_spot()
	if spot.is_empty():
		return false
	var ev := {"kind": "fire_lay", "who": id, "slot": craft.hands.get(id, -1), "at": spot.at, "yaw": spot.yaw, "up": spot.up}
	if not craft.send(ev):
		return false
	busy_until = Doll.frame_index() + 1 + Campfire.LAY_FRAMES   # 組むあいだは、その場で
	var hud = get_parent().get("hud")
	if hud:
		hud.learn("campfire")
	return true


## 近くの、自分の燃えている焚き火（なければ null）
func own_fire_near() -> Node3D:
	if craft == null or mode != Mode.WALK:
		return null
	var best: Node3D = null
	for f in craft.fires.values():
		if is_instance_valid(f) and f.owner_id == id and f.lit() and f.level() > 0.0:
			var d := global_position.distance_to((f as Node3D).global_position)
			if d < FIRE_REACH and _facing((f as Node3D).global_position) > 0.3 and (best == null or d < global_position.distance_to(best.global_position)):
				best = f
	return best


func put_out_fire() -> bool:
	var f := own_fire_near()
	if f == null or held().get("kind", "") == "campfire":
		return false
	return craft.send({"kind": "fire_out", "who": id, "id": f.fire_id})


# ---------------------------------------------------------------- 持ち物と工房（craft.gd）

## 手に持っている物（素手なら {}）
func held() -> Dictionary:
	return craft.held(id) if craft else {}


func _touched(s: RigidBody3D) -> void:
	last_sled = s
	last_item = {}


## 自分の畳む・広げるで、最後に触ったソリを替える
func _on_craft(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	match ev.kind:
		"doll":   # 衣装掛けで選んだ人形に着替える
			set_doll(String(ev.doll))
		"dye", "outfit":   # 染め桶で服を染めた: 人形と一人称の袖と脚を、その色で作り直す
			if doll and String(ev.doll) == doll.kind:
				set_doll(doll.kind, true)
		"sewn":   # 自分の縫ったソリが、最後に触ったソリになる（左下の札がその場所を出す）
			if ev.get("gear", false):   # 米袋は装備の枠に入り、床にソリは出ない
				return
			var made: RigidBody3D = craft.sleds.get(int(ev.id))
			if made:
				_touched(made)
		"fold":
			last_sled = null
			last_item = ev.item
		"unfold":
			var s: RigidBody3D = craft.sleds.get(int(ev.id))
			if s:
				_touched(s)


## ホイール・二本指スクロールで持ち替えてよいか（画面を開いているあいだは、その画面がスクロールを使う。身ぶりの輪を出しているあいだも替えない）
func _can_cycle() -> bool:
	return not menu_open and not (ring and ring.visible) and craft != null and craft.has_hand_items(id)


## 二本指スクロールのひと撫でで 1 つ持ち替える。指を離したあとの慣性のパンも同じひと撫でとして、続けて替えない。
## 途切れたら（PAN_GAP）、または逆向きに撫でたら、次のひと撫で。横向きが勝っている撫で方では替えない
func _pan_hand(d: Vector2) -> void:
	if d == Vector2.ZERO:
		return   # 撫で終わりの知らせ（動いていない）。慣性が続くことがあるので、ここでは区切らない
	var now := Time.get_ticks_msec()
	var frame := Engine.get_process_frames()
	var reverse := _pan_done and absf(d.y) > absf(d.x) and signf(d.y) != signf(_pan_acc.y)
	# 重くて 1 フレームが長いときも、毎フレーム届いているあいだは同じひと撫で（パンの来ないフレームをはさんで初めて区切る）
	if (now - _pan_ms > PAN_GAP and frame - _pan_frame > 1) or reverse:
		_pan_acc = Vector2.ZERO
		_pan_done = false
	_pan_ms = now
	_pan_frame = frame
	_pan_acc += d
	if _pan_done or not _can_cycle():
		return
	if absf(_pan_acc.y) >= PAN_STEP and absf(_pan_acc.y) > absf(_pan_acc.x):
		cycle_hand(1 if _pan_acc.y > 0.0 else -1)
		_pan_done = true


## ホイール: 素手 → 手持ち 1 → 2 → … と回す（空いたマスと、かばんの物は飛ばす）
func cycle_hand(step: int) -> void:
	var order := [-1]
	var b: Array = craft.bag(id)
	for i in mini(preload("res://craft.gd").HAND_SLOTS, b.size()):
		if not b[i].is_empty():
			order.append(i)
	var cur := order.find(craft.hands.get(id, -1))
	var next: int = order[posmod(maxi(cur, 0) + step, order.size())]
	craft.send({"kind": "hand", "who": id, "slot": next})


## いちばん近いソリを、押す・乗る・畳む相手にする（歩いているときだけ。つかむ・乗るあいだは替えない）
func _pick_sled() -> void:
	var best: RigidBody3D = sled if is_instance_valid(sled) and sled.visible and not sled.is_queued_for_deletion() and not sled.racked else null
	var best_d := INF
	if best:
		best_d = global_position.distance_to(best.global_position) - SLED_SWITCH
	for s in get_tree().get_nodes_in_group("sleds"):
		var rb := s as RigidBody3D
		if rb == null or rb == best or not rb.visible or rb.is_queued_for_deletion() or rb.racked:   # 立てかけ台のソリはつかめない
			continue
		var d := global_position.distance_to(rb.global_position)
		if d < best_d:
			best = rb
			best_d = d
	if best and best != sled:
		sled = best


## 売り子のおじさんに話しかけられる所で、おじさんの方を向いているか
func shop_near() -> bool:
	var sk = get_parent().get("shopkeeper")
	if sk == null or get_parent().get("craft_ui") == null or not sk.can_talk(self):
		return false
	var d: Vector3 = sk.global_position - global_position
	d.y = 0
	return d.length() < 0.6 or (-global_basis.z).dot(d.normalized()) > 0.4


## 立てかけ台の前で F を押すと何が起きるか: [ソリ, "rack_out" か "rack_in"]。何もなければ []。
## 台の自分のソリの方を見ていれば持ち出す。でなければ、自分のソリのうち、いちばん遠いものを台へ戻す。
## だれも触っていないソリが先で、なければほかの人が触っているソリ（その人は降りる・手が離れる）。
## 戻す物がなければ、台にある自分のソリのうち、いちばん向いているものを持ち出す
const RACK_LOOK := 0.92   # 台のソリの方を見ている（見ている向きとソリの方向の合い具合）

func rack_target() -> Array:
	var r = get_parent().get("sled_rack")
	if r == null or craft == null or mode != Mode.WALK or menu_open or shopping or not r.can_use(self):
		return []
	var l: Dictionary = craft.rack_list(id)
	var best: Node3D = null
	var best_f := -2.0
	for s in l.on:
		var f := _facing((s as Node3D).global_position)
		if f > best_f:
			best = s
			best_f = f
	if best and best_f > RACK_LOOK:
		return [best, "rack_out"]
	if _sled_in_reach():
		return []   # 手の届くソリがあれば、F はつかむほう（持ち出したソリをつかもうとして、台へ戻してしまわないように）
	var far: Node3D = null
	var far_d := -1.0
	for s in l.free if not l.free.is_empty() else l.touched:
		var d: float = (s as Node3D).global_position.distance_to(global_position)
		if d > far_d:
			far = s
			far_d = d
	if far:
		return [far, "rack_in"]
	return [best, "rack_out"] if best else []


## 立てかけ台の前で、自分のソリがみなペグで留めてあって戻せず、持ち出せる物もないか（F の代わりに「いまは呼べない」の絵を出す）
func rack_refused() -> bool:
	var r = get_parent().get("sled_rack")
	if r == null or craft == null or mode != Mode.WALK or menu_open or shopping or not r.can_use(self):
		return false
	var l: Dictionary = craft.rack_list(id)
	return l.on.is_empty() and l.free.is_empty() and l.touched.is_empty() and not l.busy.is_empty() and not _sled_in_reach()


## F でつかめる（紐の先か、つかむ所に手が届く）ソリがそばにあるか
func _sled_in_reach() -> bool:
	if not is_instance_valid(sled) or sled.racked:
		return false
	return _rope_end_near() or global_position.distance_to(sled.to_global(sled.grip_point_near(global_position)[0])) <= GRAB_REACH


## 山男に話しかけられる所で、山男の方を向いているか
func mountain_near() -> bool:
	var mm = get_parent().get("mountain_man")
	if mm == null or get_parent().get("mountain_ui") == null or menu_open or not mm.can_talk(self):
		return false
	var d: Vector3 = mm.global_position - global_position
	d.y = 0
	return d.length() < 0.6 or (-global_basis.z).dot(d.normalized()) > 0.4


## 雪だるまの番台で話しかけられる所にいて、番台の方を向いているか
func food_near() -> bool:
	var sh = get_parent().get("snowman_shop")
	if sh == null or get_parent().get("food_ui") == null or menu_open or not sh.can_talk(self):
		return false
	return sh.counter == null or _facing(sh.counter.global_position) > 0.3


## 手のペレットを入れられる（または仕上がりを受け取れる）厨房の装置のうち、いちばん向いているもの（なければ null）
func station_near() -> Node:
	var best: Node = null
	var best_f := 0.2
	for st in get_parent().get("stations") if get_parent().get("stations") != null else []:
		if st.can_use(self):
			var f := _facing(st.get_parent().global_position)
			if f > best_f:
				best = st
				best_f = f
	return best


## 1 階の人台の前で、人形の高さを見ているか
func wardrobe_near() -> bool:
	var w = get_parent().get("wardrobe")
	return w != null and get_parent().get("wardrobe_ui") != null and not menu_open and w.can_use(self)


## 入口の横の大きな鏡の前で、鏡の方を向いているか（映っているあいだは案内を出さない）
func mirror_near() -> bool:
	var m = get_parent().get("mirror")
	return m != null and not m.shown and not menu_open and not shopping and mode == Mode.WALK and m.can_use(self)


## F: 映っていれば消す（ただし鏡を見ながら人台や紙細工屋さんを向いていれば、そちらを開く）。映っていなければ、鏡の方を向いているときに映す
func _mirror_f() -> bool:
	var m = get_parent().get("mirror")
	if m == null or menu_open:
		return false
	if m.shown:
		if dye_near() or paper_shop_near() or wardrobe_near():
			return false
		m.set_shown(false)
		return true
	if not m.can_use(self):
		return false
	m.set_shown(true)
	var hud = get_parent().get("hud")
	if hud:
		hud.learn("mirror")   # 映したら、F の案内はもう出さない
	return true


## テントの紙細工屋さん（paper_lady.gd）の前で、婦人かスタンドの方を向いているか
func paper_shop_near() -> bool:
	var pl = get_parent().get("paper_lady")
	return pl != null and get_parent().get("paper_shop_ui") != null and not menu_open and pl.can_use(self)
## 1 階の人台の桶を見下ろしているか
func dye_near() -> bool:
	var v = get_parent().get("dye_vat")
	return v != null and get_parent().get("dye_ui") != null and not menu_open and v.can_use(self)


## 視線が下を向いているか（人台で、桶を見ているか人形を見ているかを分ける）
func looks_down() -> bool:
	return _pitch < LOOK_DOWN


## ミシンの前（立つ所のそば）で、ミシンの方を向いていて、縫い始められるか
func machine_near() -> bool:
	var sew = get_parent().get("sewing")
	return sew != null and get_parent().get("craft_ui") != null and sew._user_near() and sew.can_sew() \
			and _facing(sew.machine.global_position) > 0.2


## 見ている向きと、at の方向の合い具合（1 で真正面）
func _facing(at: Vector3) -> float:
	var d := at - global_position
	d.y = 0
	return (-global_basis.z).dot(d.normalized()) if d.length() > 0.01 else 1.0


## 一人称の右手に、持っている物の形を持たせる（雪玉を持っているときは雪玉だけ）
func _place_held_fp(ball: bool) -> void:
	var it := held() if not ball and table_ctx().is_empty() else {}   # 机のある席では、料理は机の上（table_eat.gd）
	var key := str(it)
	if key == _held_key:
		return
	_held_key = key
	if _held_fp:
		_held_fp.queue_free()
		_held_fp = null
	if it.is_empty():
		return
	var right: Node3D = hands[0] if hands[0].get_meta("side") > 0 else hands[1]
	_held_fp = held_shape(it)
	_held_fp.position = Vector3(-0.02, 0.05, -0.08)
	_held_fp.scale = Vector3.ONE * 0.7
	for mi in _held_fp.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1 << 2
	right.add_child(_held_fp)
	_held_fp.set_meta("folded", it.get("kind") == "folded")


## 手に材料（次に入れる装置がある食べ物）を持っているあいだ、紙の札を吊る。手が隠れているとき（手形を出す・机の席）は出さない
func _update_hold_tag(dt: float) -> void:
	var it := held()
	var on: bool = _held_fp != null and _held_fp.visible and FoodMenu.next_station(it) != ""
	if on and _hold_tag == null:
		_hold_tag = HoldTag.new()
		cam.add_child(_hold_tag)
	if _hold_tag:
		_hold_tag.step(it if on else {}, _held_fp.global_position if on and not third else Vector3.INF, dt)


## 畳んだソリの包みは、名札を貼った面を自分（カメラ）へ向けて、手の少し上・内側に持つ（毎コマ）
func _face_held_fp() -> void:
	if _held_fp == null or not _held_fp.get_meta("folded", false):
		return
	var hand: Node3D = _held_fp.get_parent()
	var at := cam.to_local(hand.global_position) + Vector3(-0.1, 0.1, -0.02)
	var b := cam.global_basis.orthonormalized() * Basis(Vector3.RIGHT, PI / 2 - HELD_TILT) * Basis(Vector3.UP, HELD_TURN)
	_held_fp.global_transform = Transform3D(b.scaled(Vector3.ONE * HELD_SCALE), cam.to_global(at))


## 手に持った物の小さな形（一人称の右手と、確かめ用）
## fp: 一人称の手に持つ形（目の前で見るので大きく持つ）。人形の手に持たせるとき（小窓・鏡）は false
static func held_shape(it: Dictionary, fp := true) -> Node3D:
	if it.get("kind") == "campfire":   # 焚き火セット: 毛糸で縛った薪の束（campfire.gd）
		return Campfire.kit_shape()
	if it.get("kind") == "peg":   # ペグの束: 待ち針の形を、束の本数だけ扇に並べる（peg.gd）
		var bunch := Node3D.new()
		var n := clampi(int(it.get("n", 1)), 1, 3)
		for k in n:
			var pg := preload("res://peg.gd").make(Color(0.80, 0.24, 0.20))
			pg.scale = Vector3.ONE * 0.14
			pg.position = Vector3((k - (n - 1) * 0.5) * 0.025, -0.06, 0.0)
			pg.rotation.z = (k - (n - 1) * 0.5) * -0.22
			bunch.add_child(pg)
		bunch.rotation.x = -0.35
		return bunch
	if it.get("kind") == "food":   # 雪だるまの店のペレット（途中は押されたペレット）か、できあがった料理（food.gd）
		var done := FoodMenu.done(it)
		var bites := int(it.get("bites", 0))
		var f := PropsLib.make(FoodMenu.dish_glb(it.dish, bites) if done else FoodMenu.pellet_glb(it.dish))
		var holder := Node3D.new()
		holder.add_child(f)
		f.scale = Vector3.ONE * (0.75 if done else 1.0) * (Vector3(1.3, 0.6, 1.3) if int(it.get("step", 0)) > 0 and not done else Vector3.ONE)   # 食べても器の大きさは変えない（中身の量は途中の形が持つ）
		if done:   # 手に持つ向き: 形の正面（glb の -Z）を自分へ
			var hold: Dictionary = FoodMenu.HOLD.get(it.dish, FoodMenu.HOLD_DRINK if it.dish in FoodMenu.DRINKS else FoodMenu.HOLD_DEFAULT)
			var k: Vector3 = f.scale * (float(hold.scale) if fp else 1.0)
			f.basis = Basis.from_euler(hold.rot * PI / 180.0, EULER_ORDER_YXZ) * Basis(Vector3.UP, deg_to_rad(float(hold.get("yaw", 0.0))))
			f.scale = k
			f.position = hold.pos
			for smoke in f.find_children("Smoke", "GPUParticles3D", true, false):   # 目の前の湯気は薄く（品を隠さない）
				(smoke as GPUParticles3D).amount_ratio = 0.3
		return holder
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	match it.get("kind", ""):
		"pattern":   # クラフト紙の型紙。待ち針の赤い頭
			bm.size = Vector3(0.13, 0.003, 0.17)
			mi.material_override = Look.paper(Color(0.84, 0.72, 0.52))
			var pin := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.008
			sm.height = 0.016
			pin.mesh = sm
			pin.material_override = Look.felt(Color(0.80, 0.24, 0.20))
			pin.position = Vector3(-0.045, 0.006, -0.06)
			root.add_child(pin)
		"fabric":    # たたんだ布の束
			bm.size = Vector3(0.14, 0.035, 0.1)
			mi.material_override = Look.felt(preload("res://fabrics.gd").color(it.get("fabric", "red")), 6.0)
		"folded":    # 折り紙の包み。上（+Y）の面に名札を貼り、窓に広げた姿がくるくる回る。名札の面を見る人へ向けるのは呼ぶ側
			bm.size = Vector3(0.13, 0.04, 0.13)
			mi.material_override = Look.felt(preload("res://fabrics.gd").color(it.get("fabric", "red")), 6.0)
			mi.rotation.y = PI / 4
			var Tags := preload("res://sled_tags.gd")
			Tags.patch_on(root, 0.02, it.get("tag", 0), 0.15, Tags.turntable(it.get("sled", "mid"), it.get("fabric", "")))
			mi.mesh = bm
			root.add_child(mi)
			return root
	mi.mesh = bm
	root.add_child(mi)
	root.rotation.x = 0.5
	return root


# ---------------------------------------------------------------- 米袋を出す・座る・しまう動き（doll.gd の sack_start）

const SACK_EYE := Vector3(0, -0.03, 0.2)   # 米袋に座ったときの目の、人形の目からのずれ（後ろへもたれる）
var _sack_ev := 0            # 米袋を出す動きで、済んだ出来事（1 広げた / 2 腰を下ろした / 3 乗っている形）
var _sack_hidden: Node3D     # 広げるコマまで隠している米袋の見た目
var _sack_landed := false
var _fp_legs: Node3D         # 一人称の両脚（米袋に座っているときだけ）
var _legs_frame := -1


## 米袋を出す動きの出来事を、人形のコマに合わせて起こす: 広げる（ばさっ）→ 腰を下ろす（ぽふっ。袋がへこみ、雪の粉）
func _sack_events() -> void:
	var k := doll.sack_k("out")
	if k < 0 or mode != Mode.RIDE or sled == null or sled.kind != "sack":
		if k >= 0:
			doll.sack_anim = ""
		if _sack_hidden and is_instance_valid(_sack_hidden):
			_sack_hidden.visible = true
		_sack_hidden = null
		return
	if k >= 2 and _sack_ev < 1:
		_sack_ev = 1
		if _sack_hidden and is_instance_valid(_sack_hidden):
			_sack_hidden.visible = true
		_sack_hidden = null
		_sack_sound("fling")
	if k == 3 and _sack_ev < 2 and not _sack_landed:
		_sack_landed = true   # 雪の上に落ちて広がる
		preload("res://snowball.gd").splat_at(get_parent(), sled.to_global(Vector3(0, 0.03, -0.2)), sled.global_basis.y, true)
	SackLook.fling(sled, k)
	if k >= 4 and _sack_ev < 2:
		_sack_ev = 2
		SackLook.set_stage(sled, seat, 1)
		_sack_sound("sit")
		for sx in [-1, 1]:
			preload("res://snowball.gd").splat_at(get_parent(), sled.to_global(Vector3(0.32 * sx, 0.03, seat.z)), sled.global_basis.y, true)
	if k >= 5 and _sack_ev < 3:
		_sack_ev = 3
		SackLook.set_stage(sled, seat, 2)


func _sack_sound(what: String) -> void:
	var au := get_parent().get_node_or_null("Audio")
	if au and au.has_method("sack"):
		au.sack(self, what)


## 一人称の両脚: 米袋に座っているあいだ、袋の上に投げ出した腿とすねと足先。蹴る足は横へ出て、後ろへ蹴り、戻る（人形と同じコマ）
func _pose_fp_legs(fi: int) -> void:
	var show: bool = mode == Mode.RIDE and sled.kind == "sack" and doll.sack_seated() and not third
	_fp_legs.visible = show
	if not show:
		return
	_fp_legs.global_transform = Transform3D(sled.global_basis.orthonormalized(), sled.to_global(seat))
	if fi == _legs_frame:
		return
	_legs_frame = fi
	var kk: int = fi - doll._kick_frame
	for side in ["L", "R"]:
		var sx := 1.0 if side == "R" else -1.0
		var hip := Vector3(0.08 * sx, 0.02, 0.0)
		var knee := Vector3(0.1 * sx, 0.15, -0.25)
		var foot := Vector3(0.1 * sx, -0.08, -0.47)
		if kk >= 0 and kk < 3 and side == doll._kick_leg:
			knee = [Vector3(0.17 * sx, 0.03, -0.22), Vector3(0.2 * sx, -0.02, -0.12), Vector3(0.13 * sx, 0.05, -0.25)][kk]
			foot = [Vector3(0.28 * sx, -0.12, -0.38), Vector3(0.32 * sx, -0.14, 0.05), Vector3(0.16 * sx, -0.1, -0.42)][kk]
		FpHands.pose_leg(_fp_legs, side, hip, knee, foot)

## 乗るのは今（summon_sack）。見た目は、帯から取り出して広げ、腰を下ろすまでをコマで追う（袋は広げるコマまで隠す）
func _start_sack_out() -> void:
	doll.sack_start("out")
	_sack_ev = 0
	_sack_landed = false
	_sack_hidden = sled.get("_body")
	if _sack_hidden:
		_sack_hidden.visible = false


# ---------------------------------------------------------------- 装備の米袋（craft.gd の sack_out・sack_in）

const SACK_NEAR := 3.5       # 出している米袋がこれより近ければ、N でしまう（遠ければ足もとへ呼び戻す）
const SACK_CARRY := 1.8      # 走りながら出すと、前へ飛び乗る勢いで、前へ進んでいた速さのこれだけ倍で滑り出す（横・後ろはそのまま）
const SACK_CARRY_MAX := 6.5  # 受けつぐ速さの上限 (m/s)

## R: 帯のランタンを点ける・消す（提げていなければ何もしない）
func toggle_lamp() -> bool:
	return craft.send({"kind": "lamp", "who": id, "on": not craft.lamp_on(id)})


## N: 米袋を出して乗る／降りてしまう／遠くの米袋を足もとへ呼び戻す
func toggle_sack() -> void:
	var gs: RigidBody3D = craft.sack_sled(id)
	if gs:
		var on_it := mode == Mode.RIDE and sled == gs
		var near := global_position.distance_to(gs.global_position) < SACK_NEAR
		if on_it or (near and gs.riders.is_empty()):
			if on_it:
				get_off()
			doll.sack_start("in")   # 立ってかがみ、くるくる丸めて帯へ
			_sack_sound("roll")
			craft.send({"kind": "sack_in", "who": id})
			return
		if not gs.riders.is_empty():
			return   # ほかの人が乗っている
		craft.send({"kind": "sack_in", "who": id})   # 遠くに置いたまま: しまって、足もとに出し直す
	if summon_sack():
		_start_sack_out()


## 足もとに米袋を出して、すぐ乗る。つかんでいる・紐を持っている・ほかのソリに乗っているなら、離れてから。
## 歩いて・走っていれば、その勢いを米袋の初めの速さにする（前へは飛び乗る分 SACK_CARRY 倍）
func summon_sack() -> bool:
	var carry := Vector3.ZERO
	if mode == Mode.WALK:
		carry = Vector3(velocity.x, 0, velocity.z)
		var fwd := -global_basis.z
		fwd.y = 0
		carry += fwd.normalized() * maxf(0.0, carry.dot(fwd.normalized())) * (SACK_CARRY - 1.0)
		carry = carry.limit_length(SACK_CARRY_MAX)
	if mode == Mode.GRIP or mode == Mode.ROPE:
		let_go()
	elif mode == Mode.RIDE:
		get_off()
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.DOWN * 2.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if hit else global_position
	var up: Vector3 = hit.normal if hit and hit.normal.y > 0.6 else Vector3.UP
	carry -= up * carry.dot(up)   # 雪面に沿わせる
	if not craft.send({"kind": "sack_out", "who": id, "at": at, "yaw": rotation.y, "up": up, "v": carry}):
		return false
	var gs: RigidBody3D = craft.sack_sled(id)
	if gs == null:
		return false
	sled = gs
	get_on()
	return mode == Mode.RIDE


# ---------------------------------------------------------------- 自分の名札（sled_tags.gd の部品。装備の画面で決める）

const TAG_FILE := "user://my_tag.cfg"

## 保存してある自分の名札を読む（なければ、人の番号から決めたはじめの名札のまま）。保存した人形を送ったら true。
## 手に入れた部品を先に戻してから、名札を付ける（前の版の保存にない部品は、はじめの名札のまま）
func _load_tag() -> bool:
	var cf := ConfigFile.new()
	if cf.load(TAG_FILE) != OK:
		return false
	var Tags := preload("res://sled_tags.gd")
	if cf.has_section("owned"):
		for part in cf.get_section_keys("owned"):
			for i in cf.get_value("owned", part, []):
				craft.send({"kind": "tag_unlock", "who": id, "part": part, "index": int(i)})
	var d := {}
	for part in Tags.PARTS:
		if cf.has_section_key("tag", part):
			d[part] = int(cf.get_value("tag", part))
	craft.send({"kind": "tag_design", "who": id, "design": d})
	if cf.has_section("profile"):
		craft.send({"kind": "profile", "who": id, "name": String(cf.get_value("profile", "name", craft.name_of(id))),
			"color": int(cf.get_value("profile", "color", craft.colors.get(id, 0)))})
	if cf.has_section("lantern"):   # ランタン: 持っている形を戻してから、提げていた形を提げる（"" は外していた）
		for k in cf.get_value("lantern", "owned", []):
			craft.send({"kind": "lantern_own", "who": id, "look": String(k)})
		if cf.has_section_key("lantern", "wear"):
			var look := String(cf.get_value("lantern", "wear"))
			craft.send({"kind": "equip", "who": id, "gear": "lantern", "index": craft.lantern_index(id, look) if look != "" else -1})
	if cf.has_section("pals"):   # 頭・肩の小物とミニオン: 持っている物を戻してから付ける
		for k in cf.get_value("pals", "owned", []):
			craft.send({"kind": "pal_own", "who": id, "key": String(k)})
		for slot in ["head", "shoulder", "pet"]:
			if cf.has_section_key("pals", slot):
				craft.send({"kind": "pal_wear", "who": id, "slot": slot, "key": String(cf.get_value("pals", slot))})
	if cf.has_section("outfit"):
		for k in cf.get_section_keys("outfit"):
			craft.send({"kind": "outfit", "who": id, "doll": k, "colors": cf.get_value("outfit", k, [])})
	var a = get_parent().get("args")
	if cf.has_section_key("profile", "doll") and not (a is Dictionary and a.has("doll")):   # --doll を付けたときは、そちらが勝つ
		craft.send({"kind": "doll", "who": id, "doll": String(cf.get_value("profile", "doll"))})
		return true
	return false


# ---------------------------------------------------------------- 名札を外す・付ける（G を長押し）
# 自分のソリの名札のそばで G を長押しすると、名札を外して持ち主をやめる（名札は帯の名札入れへ）。
# 名札入れに名札があれば、持ち主のいない名札なしのソリの結び目のそばで G を長押しすると、名札を付けて持ち主になる
const TAG_REACH := 2.2         # 名札の結び目からこの距離 (m) の内なら手が届く
const TAG_HOLD := 0.75         # 長押しの長さ (s)
var tag_hold := 0.0            # 長押しの進み（0〜1。HUD が輪を描く）
var _tag_done := false         # 長押しで外した・付けた（G を離すまで、次をしない）


## いま G で外せる・付けられるソリと、どちらか [ソリ, "untag" / "tag_on"]。なければ []
func tag_target() -> Array:
	if craft == null or mode != Mode.WALK or menu_open or shopping:
		return []
	var best: Array = []
	var near := TAG_REACH
	for s in get_tree().get_nodes_in_group("sleds"):
		if not is_instance_valid(s) or not s.visible or s.kind == "sack" or craft.sled_id(s) < 0 or s.racked:
			continue
		var d: float = s.tag_point().distance_to(global_position + Vector3.UP * 0.9)
		if d >= near:
			continue
		var Tags := preload("res://sled_tags.gd")
		if int(s.owner_id) == id and Tags.has_tag(s.tag):
			best = [s, "untag"]
			near = d
		elif int(s.owner_id) < 0 and not Tags.has_tag(s.tag) and not (craft.loose_tags.get(id, []) as Array).is_empty():
			best = [s, "tag_on"]
			near = d
	return best


func _tag_hold_step(dt: float) -> void:
	var down := Input.is_physical_key_pressed(KEY_G) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not down:
		_tag_done = false
		tag_hold = 0.0
		return
	var tt := tag_target()
	if tt.is_empty() or _tag_done:
		tag_hold = 0.0
		return
	tag_hold = minf(1.0, tag_hold + dt / TAG_HOLD)
	if tag_hold >= 1.0:
		_tag_done = true
		tag_hold = 0.0
		var ev := {"kind": tt[1], "who": id, "id": craft.sled_id(tt[0])}
		if tt[1] == "tag_on":
			ev["loose"] = (craft.loose_tags[id] as Array).size() - 1   # いちばん最近外した名札
		craft.send(ev)
		var hud = get_parent().get("hud")
		if hud:
			hud.learn(tt[1])


## 自分の名札を保存する（装備の画面で変えたとき。次に起動しても同じ名札）。名前とキャラの色も同じ帳面に
func save_tag() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "name", craft.name_of(id))
	cf.set_value("profile", "color", int(craft.colors.get(id, 0)))
	cf.set_value("profile", "doll", doll.kind)
	var dyed: Dictionary = craft.outfits.get(id, {})
	for k in dyed:
		cf.set_value("outfit", k, dyed[k])
	var d: Dictionary = craft.tag_designs.get(id, {})
	for part in d:
		cf.set_value("tag", part, d[part])
	var owned: Dictionary = craft.tag_owned.get(id, {})
	for part in owned:
		cf.set_value("owned", part, owned[part])
	var looks: Array = []   # ランタン（lantern.gd）: 持っている形と、提げている形
	for l in craft.lanterns.get(id, []):
		looks.append(String(l.get("look", "")))
	cf.set_value("lantern", "owned", looks)
	cf.set_value("lantern", "wear", String(craft.lantern(id).get("look", "")))
	cf.set_value("pals", "owned", craft.pals_owned.get(id, []))   # 頭・肩の小物とミニオン（pals.gd）
	for slot in craft.pals_wear.get(id, {}):
		cf.set_value("pals", slot, craft.pals_wear[id][slot])
	cf.save(TAG_FILE)
