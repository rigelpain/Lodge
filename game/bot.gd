extends CharacterBody3D

const Doll := preload("res://doll.gd")
const Flung := preload("res://flung.gd")
const Rolled := preload("res://rolled.gd")
const Emotes := preload("res://emotes.gd")
const Palm := preload("res://palm.gd")
const Seats := preload("res://seats.gd")
const Areas := preload("res://areas.gd")
const Mountain := preload("res://mountain.gd")
const Grand := preload("res://grand_mountain.gd")
const SackLook := preload("res://sack_look.gd")
const Ghost := preload("res://ghost.gd")
## 押すのを手伝う仲間（CPU）。動かすのは一人で遊ぶ画面かホストの画面だけ。つなぐ側へは姿が配られる（net.gd の "cpu"）。
## 説明の「あなた」は、遊んでいる人（通信では、つないでいる人もみんな。_humans）。
## ソリの下り側に回って頂上へ押す → 頂上であなたが乗ったら一緒に乗る → 下で降りてまた押す。
## 身ぶりへの返し（確かめ用の簡単なもの）: あなたが近くで手のひらを掲げると、ソリを離して前まで来て、
## 同じ高さで掲げる（高ければハイタッチ、低ければ握手）。片手か両手かもまねる。
## 一緒に乗っているとき、あなたが高い両手のひらにしたら一緒に上げる（万歳）。声には同じ声、「ウン？」には「ウン」、拍手には拍手。
## 「おーーーい」と呼ぶと、遠くからでもそちらを見て、「おーい」と返すか手を振る（ソリをつかんでいれば声で返す）。
## 雪玉が当たると、のけぞって笑う。つかんでいたら手を離し、少しして（REGRAB_WAIT）つかみ直しに行く。
## 一緒に乗っているときは、あなたの体重移動（A/D・前傾・後傾）に LEAN_DELAY 遅れて合わせる（lean_mode = "follow"）。
## 体重移動は乗っている一人ひとりの力が足し合わさるので、仲間が合わせると大きいソリもぐっと曲がる。"off" なら何もしない。
## 速く下るソリをつかむと引きずられ、引きずられている間は押さずに踏ん張る（止める力は sled.gd がまとめてかける）。
## lounge の仲間は、ソリを押さずにロッジでくつろぐ: 空いた席（seats.gd）に座り、しばらくすると立って別の空いた席へ歩いて座り直す。
## あなたが席に座ると、そのそばの空いた席へ寄ってくる（同じ机を囲む）。座る・立つは、あなたと同じ出来事（seats.gd の sit・stand）
## 雪合戦: 雪玉を持ったあなたに低い手のひらを差し出されると、しゃがんで雪玉を作ってから握手しに来る（握手で対決が始まる。duel.gd）。
## 掛金を受け、円の中を回りながら振りかぶって投げ、ときどきよけて、ときどき取る。なくなれば作る。ロッジでくつろぐ仲間はしない
## 財布はいつも金色の真鍮のボタン 5 枚以上（DUEL_BUTTONS）。掛金で減っても、次の握手で戻るので、賭けられなくならない
## 山めぐり（roam。2026-11-06 代表「CPUは頂上に行って滑り降りて、また別の山に行って、とうろうろしてほしい。5人くらいいたら良いな」）:
## 自分で山（丘・大きな山・大山）を選ぶ → 帯に米袋を提げて尾根を歩いて登る → 頂上で米袋を広げて滑り降りる → 帯に戻して次の山へ。
## ほかの仲間の少ない山を選ぶので、ばらける。人のいる山に誰も向かっていなければ、そこを選ぶ（対決の相手が見つからなくならないように）。
## 歩いているあいだに、そばの人がソリを押す・乗ると、手伝いに来て一緒に押して乗る（先の PUSH・WAIT・RIDE。手伝うのは 2 人まで）。
## 人の FAR より遠くでは、当たりを見ずに地面の高さをなぞって間引いて歩く（重くしない）
## 物をよける: 少し先に物があるか、点へ近づけないでいるときだけ、まわりの当たりを格子に調べて回り込む（_steer_to。ソリ・木・ロッジ）。
## 着いていない点は飛ばさない（頂上でない所で米袋を広げない）。閉じた所に入り込んだら、当たりを消して外へ歩く（_ghost）
## 仲間どうし（2026-11-06 代表「CPU同士での雪合戦やCPU同士の協力してのソリ運びなどです」「ソリを買ったり」）:
##   雪合戦: 近くの仲間と、雪玉を作って握手して対決する（人との対決と同じ出来事。掛金も賭ける）。
##   ソリ運び: 次の山を選ぶときに、ソリがあれば近くの仲間を誘う。みんなでつかむまで待ち、尾根を押して登り、頂上で向きを変えて一緒に乗って滑る。
##   使うソリは、自分のソリか、ロッジのソリ（人が近くにいなくて、誰も触っていないときだけ。丘の中だけで使う）。
##   ソリを買う: 滑って拾ったボタンがたまったら、売り子のおじさんから小の型紙と布を買い、ミシンで縫う（人と同じ buy・sew の出来事。自分のソリを持つのは CPU_SLEDS まで）

enum State { PUSH, WAIT, RIDE }

const SPEED := 2.4
const REGRAB_WAIT := 1.5     # 雪玉が当たって手を離してから、つかみ直すまで (s)
const LEAN_DELAY := 0.3      # 一緒に乗っているとき、あなたの体重移動に合わせるまでの遅れ (s)
const GRAVITY := 24.0         # 落ちるときの重力（player.gd の FALL_GRAVITY と同じ。仲間は跳ばないので、下りだけ）
const ROAM_SPEED := 3.0      # 山をめぐって歩く速さ (m/s)
const FAR := 90.0            # どの人からもこれより遠ければ、間引いて動く (m)
const FAR_STEP := 0.2        # 間引いて動くときの間 (s)
const HELP_NEAR := 30.0      # そばの人がソリを押す・乗ると手伝いに行く距離 (m)
const HELP_KEEP := 6.0       # 人がソリから離れて、手伝いをやめるまで (s)
const HELP_MAX := 2          # 手伝う仲間の数の上限
const OFFER_FAR := 40.0      # 雪玉を持って低い手のひらで見ている人に、歩いて応じる距離 (m)
const RIDE_BRAKE_NEAR := 40.0   # 滑る行き先からこの距離の内で「着いた」ら、後傾で止まる (m)
const RIDE_MAX := 240.0      # 1 回の滑りの長さの上限 (s)。どこかに引っかかっても次へ進む
const DUEL_NEAR := 40.0      # 仲間どうしで雪合戦に誘う距離 (m)。歩いて来て、向かい合って握手する
const DUEL_ODDS := 0.5       # 近くに仲間がいたときに誘う割合（DUEL_LOOK ごと）
const DUEL_LOOK := Vector2(3.0, 6.0)     # 誘うか見直す間 (s)
const DUEL_COOL := Vector2(60.0, 150.0)  # 雪合戦を誘ってから、次に誘うまで (s)
const TEAM_ODDS := 0.5       # 次の山を選ぶときに、ソリがあれば仲間と運ぶ割合
const TEAM_COOL := Vector2(60.0, 150.0)  # 運び終えてから、次に運ぶまで (s)。いつも同じ組にならず、ばらける
const TEAM_NEAR := 150.0     # 運ぶソリと、誘う仲間までの距離の上限 (m)
const TEAM_MAX := 3          # 一緒に運ぶ人数の上限
const LODGE_SLED_CLEAR := 40.0   # ロッジのソリは、人がこれより近くにいれば使わない (m)
const TEAM_WAIT := 20.0      # みんながつかむのを待つ長さ (s)
const TEAM_STALL := 30.0     # 押しても次の点へ近づけなければ、そこから滑る (s)
const TEAM_TURN := 8.0       # 頂上で滑る向きへ回す長さの上限 (s)
const TEAM_LOST := 30.0      # ソリへ歩いても近づけないでいるのがこれだけ続いたら、抜ける (s)
const TEAM_NEAR_WAIT := 4.0  # ソリのそばで、持ち場へ寄れないでいるのがこれだけ続いたら、回り込む道を探す (s)
const TEAM_REACH := 2.0      # 持ち場へ寄れないときは、ここまで近ければつかむ (m)
const TEAM_TWIST := 2.0      # 組でソリの向きを回す力（重さあたり）
const NAV_AFTER := 1.0       # 行き先へ近づけないでいるのがこれだけ続いたら、回り込む道を探す (s)
const NAV_SIZES := [12, 40]  # 道を探す範囲（自分のまわりの半分の幅。m）。狭い範囲で近づけなければ広げる。ソリは狭いほう、ロッジは広いほう
const NAV_CELL := 0.5        # 道を探す格子の幅 (m)。体の幅（0.7 m）より細かくして、薄い壁を挟んだ 2 ますがつながって見えないように
const NAV_BUDGET := 400      # 1 コマに調べるます数の目安（広い範囲でも、1 コマを重くしない）
const NAV_ARM := 0.4         # ますの中心から十字に伸ばす光線の長さ (m)。体の半径より少し長く
const NAV_STEP_T := 2.0      # 道の次の点へ着けなければ、探し直す (s)
const NAV_RETRY := 3.0       # 道が見つからなかったとき、探し直すまで (s)
const NAV_GAIN := 3.0        # 行き先へこれだけ近づけない道は、道と見なさない (m)
const WP_NEAR := 5.0         # 物が置いてあって点へ寄れないとき、ここまで近ければ着いたことにする (m)
const WP_NEAR_T := 6.0       # そのそばで待つ長さ (s)
const WP_GIVE_UP := 45.0     # 点へ近づけないでいるのがこれだけ続いたら、閉じた所に入り込んだと見て、当たりを消して抜ける (s)
const NAV_AHEAD := 0.7       # まっすぐ歩くとき、地面の高さで先を調べる距離 (m)。ロッジの床の段へ上がらず、手前で回り込む
const SHED_EXIT := Vector2(8.0, 103.0)   # 下屋のミシンで縫ったソリの出口。北は暖簾の壁なので、東へ出てから進む
const LODGE_BOX := AABB(Vector3(-62, 0, 78), Vector3(66, 1, 40))   # ロッジを包む箱（x, z）。ソリを運ぶ道がここを横切ると、壁に突き当たって止まる
const LODGE_PASS := [SHED_EXIT, Vector2(-66, 100)]                # 東と西の脇の点
const SLED_KIND := "small"   # 買うソリ（小。2 人乗り）
const CPU_SLEDS := 2         # 自分のソリを持つ仲間の数の上限（雪山がソリだらけにならないように）
## 山ごとの滑り方: top 頂上、launch 米袋を広げる所、foot 滑って行く先、spread 滑る先の左右の広がり (m)。丘はどの向きにも滑れる（launch は向きごとに決める）
const ROAM_AREAS := {
	"hill": {"top": Vector2.ZERO},
	"slope": {"top": Vector2(Mountain.SX, Mountain.SZ), "launch": Mountain.START, "foot": Vector2(Mountain.FACE_X, Mountain.BOTTOM_Z), "side": Vector2(1, 0), "spread": 20.0, "ridge": Mountain.RIDGE},
	"peak": {"top": Vector2(Grand.SX, Grand.SZ), "launch": Grand.START, "foot": Vector2(Grand.BOTTOM_X, Grand.FACE_Z), "side": Vector2(0, 1), "spread": 40.0, "ridge": Grand.RIDGE},
}

var sled: RigidBody3D
var fling: Flung             # ソリに轢かれて吹き飛ぶ（flung.gd）
var rolled: Rolled           # 転がる大玉に取り込まれる（rolled.gd）
var player: Node3D          # この画面で遊ぶ人。いないとき（確かめ用）は仲間だけで滑る
var side := 1
var state := State.PUSH
var seat := Vector3.INF
var handle := Vector3.INF   # つかんでいる所（ソリの座標）
var doll: Doll               # 見た目の人形（右側の仲間は折り紙、左側は新聞紙。doll_kind で替えられる）
var doll_kind := ""          # 始めの人形（doll.gd の KINDS。"" なら右は折り紙、左は新聞紙。main.gd が入れる）
var debug := ""
var roam := false            # 山をめぐる（main.gd が入れる）
var far := false             # どの人からも遠い（間引いて動く。通信で送る回数も減らす）
var _area := ""              # 向かっている山（ROAM_AREAS の名前）
var _last_area := ""         # さっき滑った山
var _route: Array = []       # これから歩く所 [Vector2]
var _ride_goal := Vector2.ZERO   # 滑って行く先
var _ride_t := 0.0           # 滑っている秒
var _kick_t := 0.0           # 次に足で漕ぐまで (s)
var _goal_best := INF        # 滑る行き先に、いちばん近づいた距離
var _goal_t := 0.0           # そこから近づけないでいる秒
var _roam_rest := 0.0        # 次の山へ歩き出すまで (s)
var _far_t := 0.0            # 遠いかを見直すまで (s)
var _far_acc := 0.0          # 間引いて動く時間のたまり (s)
var _wp_best := INF          # いまの行き先に、いちばん近づいた距離
var _wp_t := 0.0             # そこから近づけないでいる秒
var give_ups := 0            # 当たりを消して抜けた回数（確かめ用）
var _ghost := false          # 閉じた所に入り込んだ: 当たりを消して、遠いときと同じ歩き方で外へ出る
var _nav: Array = []         # 回り込む道 [Vector2]
var _nav_t := 0.0            # 道の次の点へ向かっている秒
var _nav_job := {}           # 調べている途中の範囲 {grid, row, size, to, lift}
var _nav_wait := 0.0         # 次に道を探すまで (s)
var _nav_q: PhysicsShapeQueryParameters3D
var _nav_ray: PhysicsRayQueryParameters3D
var _help_t := 0.0           # 手伝いの残り (s)
var _duel_cool := 20.0       # 雪合戦を誘うまで (s)
var _team_cool := 0.0        # 次に運ぶまで (s)
var _team := {}              # 一緒に運ぶ組（みんなで同じ辞書を持つ）{sled, route, goal, area, members, go, turned, ...}。組がなければ空
var _lost_t := 0.0           # ソリまで歩いている秒
var own_sled: RigidBody3D    # 自分のソリ（買って縫った）
var _errand := ""            # ソリを買う用事: "shop" 店へ行く、"sew" ミシンへ行く、"sewing" 縫い上がるのを待つ
var _errand_t := 0.0         # 用事を待っている残り (s)
var post: Node3D = null      # 持ち場（ミシンの足踏みなど）。あればソリを押さず、そこに立って post_look を向く
var post_look := Vector3.INF
var _col: CollisionShape3D
var _still := 0.0
var _wait := 0.0
var hub: Emotes
var id := -1
var stays_dry := true         # 一人プレイの仲間（CPU）は場所や動きでは湿らない。雪玉・吹き飛びで濡れた分はひとりでに乾く（damp.gd の CPU_DRY。乾かしに行かないので。2026-11-01 代表「一人プレイの時の CPU は濡れないように」）
var _replies: Array = []     # [残り秒, 身ぶり]
var _five_with := -1         # ハイタッチをしにいく相手の番号
var _five_until := 0         # このコマまでに届かなければやめる
var _five_sent := false      # もう手を上げた（あとは合うまで、相手の前へ寄り続ける）
var _em := {}
var _regrab := 0.0           # これが 0 になるまでつかまない
var push_world := Vector3.ZERO   # このコマ押した向き（通信で配る。net.gd）
var _caller: Node3D          # おーいと呼んだ人（_look_t のあいだ、そちらを見る）
var lean_mode := "follow"    # 一緒に乗っているときの体重移動: "follow" あなたに合わせる、"off" しない（main.gd の --bot-lean=）
var _lean_q: Array = []      # [時刻, あなたの体重移動]（遅れて合わせるため）
var _lean_now := Vector3.ZERO
var _clock := 0.0
var craft: Node              # 工房の配り役（craft.gd）。仲間も帯にランタンを提げ、暗くなると点ける
var _lamp_t := 0.0           # ランタンを点けるか見直すまで (s)
var lounge := false          # ロッジでくつろぐ仲間（ソリは押さない）
var seats: Node              # ロッジの席の配り役（seats.gd）
var seat_i := -1             # 座っている席の番号
var _sit_frame := -1
var _stand_frame := -1
var _sit_from := Vector3.ZERO
var _sit_stage := 0
var _goal := -1              # 歩いて向かっている席
var _left := -1              # さっき立った席（すぐには戻らない）
var _rest := 0.0             # 座っている残り (s)。立っているときは、次の席を選ぶまで
var _stuck := 0.0            # 歩いても進まない時間 (s)
var _near_was := false       # あなたが近くの席に座っていた
const REST := Vector2(25.0, 60.0)   # 一つの席に座っている長さ (s)
const NEAR_SEAT := 4.0       # あなたの席からこの中の席なら「そば」(m)
const HEARTH_SEATS := ["sofa", "rocker", "beanbag"]   # 暖炉のまわりの席（hearth_nook.gd）
const HEARTH_LIKE := 0.7     # 次の席を選ぶとき、暖炉のまわりから選ぶ割合


func _ready() -> void:
	add_to_group("bots")
	fling = Flung.new(self)
	rolled = Rolled.new(self)
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	_col.shape = cap
	_col.position.y = 0.85
	add_child(_col)

	doll = Doll.new()
	doll.kind = doll_kind if doll_kind in Doll.KINDS else ("origami" if side > 0 else "news")
	add_child(doll)

	hub = get_parent().get_node_or_null("Emotes")
	if hub:
		id = hub.join(self)
		hub.happened.connect(_on_emote)
	craft = get_parent().get_node_or_null("Craft")
	if craft and id >= 0:
		craft.join(id)
		_fill_wallet()
		craft.happened.connect(_on_craft)
		craft.send({"kind": "doll", "who": id, "doll": doll.kind})   # いまの人形をみんなに知らせる
	seats = get_parent().get_node_or_null("Seats")
	if seats:
		seats.happened.connect(_on_seat)


## 人形を替える出来事（通信では、ほかの人が衣装掛けで選んだ人形がここに届く）。人形を作り直す。
## 服を染めた出来事（dye・outfit）では、いまの人形ならその色に染め直す（作り直さない）
func _on_craft(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	if ev.kind == "sewn":
		own_sled = craft.sleds.get(int(ev.get("id", -1)))
		return
	if ev.kind in ["dye", "outfit"] and String(ev.doll) == doll.kind:
		doll.dress(craft.outfit_of(id, doll.kind))
		return
	if ev.kind != "doll" or doll.kind == ev.doll:
		return
	var at := doll.global_transform
	doll.queue_free()
	doll = Doll.new()
	doll.kind = String(ev.doll)
	doll.outfit = craft.outfit_of(id, doll.kind)
	add_child(doll)
	doll.global_transform = at


## 暗くなったらランタンを点け、明るくなったら消す（あなたと同じ lamp の出来事。見直すたびに少しずつ間をずらす）
func _mind_lamp(dt: float) -> void:
	_lamp_t -= dt
	if craft == null or id < 0 or _lamp_t > 0.0:
		return
	_lamp_t = randf_range(1.5, 4.0)
	var dc := get_node_or_null("/root/DayCycle")
	if dc == null or not dc.has_method("daylight"):
		return
	var light: float = dc.daylight()
	var on: bool = craft.lamp_on(id)
	if (light < 0.4 and not on) or (light > 0.6 and on):
		craft.send({"kind": "lamp", "who": id, "on": not on})


func let_go() -> void:
	if handle == Vector3.INF:
		return
	sled.release_handle(self)
	handle = Vector3.INF
	_col.disabled = false
	velocity = Vector3.ZERO


func get_off() -> void:
	if seat == Vector3.INF:
		return
	sled.dismount(self)
	seat = Vector3.INF
	_col.disabled = false
	global_position = sled.global_position - sled.global_basis.x * 1.4 * side + Vector3.UP * 0.5
	velocity = Vector3.ZERO
	state = State.PUSH


## ソリに轢かれて吹き飛ぶ（flung.gd）。吹き飛んでいるあいだは、ほかのことをしない。起き上がれば、いまの役目に戻る
func _run_over_step(dt: float) -> bool:
	if rolled.active():
		# 大玉の中: ひとりでに暴れて崩す（rolled.gd）。崩れたら放り出されて、吹き飛んだのと同じに
		rolled.step(dt)
		if rolled.active():
			rolled.bot_struggle(dt)
		_pose_doll()
		fling.pose()
		rolled.pose()
		return true
	if not fling.active():
		if lounge or seat_i >= 0 or state == State.RIDE:
			return false
		var rh := rolled.find_hit()   # 速く転がる大玉に当たると、取り込まれる
		if not rh.is_empty():
			if handle != Vector3.INF:
				let_go()
				_regrab = REGRAB_WAIT
			rolled.start(rh)
			_pose_doll()
			fling.pose()
			rolled.pose()
			return true
		var hit := fling.find_hit(sled if handle != Vector3.INF else null)   # つかんでいるソリには飛ばされない（引きずられる）
		if hit.is_empty():
			return false
		if handle != Vector3.INF:
			let_go()
			_regrab = REGRAB_WAIT
		fling.start(hit)
	fling.step(dt)
	_pose_doll()
	fling.pose()
	return true


## 入っていた大玉が崩れた（emotes.gd が出来事 ball_break で呼ぶ）: 放り出されて飛ぶ
func ball_out() -> void:
	rolled.out()


## 乗っているソリが木にぶつかって、放り投げられる（ホストが配った向きと強さで。flung.gd・emotes.gd）。起き上がれば、次の山へ
func thrown(ev: Dictionary) -> void:
	if state != State.RIDE or seat == Vector3.INF or fling.active():
		return
	if roam:
		_roam_get_off(false)
	else:
		sled.dismount(self)
		seat = Vector3.INF
		_col.disabled = false
		velocity = Vector3.ZERO
		state = State.PUSH
	global_position += Vector3.UP * 0.15
	reset_physics_interpolation()
	fling.throw(ev)


func _uphill(p: Vector3) -> Vector3:
	if not _team.is_empty():   # 組: 次の点へ。頂上に着いたら、滑る向きへ
		var w: Vector2 = _team.route[0] if not _team.route.is_empty() else _team.goal
		var d := Vector3(w.x - p.x, 0, w.y - p.z)
		return d.normalized() if d.length() > 0.1 else Vector3.FORWARD
	var top := _top_of(p)
	var u := Vector3(top.x - p.x, 0, top.y - p.z)
	return u.normalized() if u.length() > 0.1 else Vector3.FORWARD


## その所の山の頂上 (x, z)。どの山の範囲でもなければ丘（ふもとのくぼみの外も、丘へ押す）
func _top_of(p: Vector3) -> Vector2:
	var a := Areas.of(Vector2(p.x, p.z))
	return ROAM_AREAS[a].top if ROAM_AREAS.has(a) else Vector2.ZERO


## 紙の体の湿り気（damp.gd）の倍率: push なら押す力、そうでなければ歩く速さ（player.gd と同じ）
func damp_k(push: bool) -> float:
	var dm := get_parent().get_node_or_null("Damp")
	if dm == null or id < 0:
		return 1.0
	return dm.push_k(id) if push else dm.speed_k(id)


func _physics_process(dt: float) -> void:
	push_world = Vector3.ZERO
	if roam:
		_keep_sled()
		_team_cool = maxf(0.0, _team_cool - dt)
	_update_replies(dt)
	_mind_lamp(dt)
	_regrab = maxf(0.0, _regrab - dt)
	if _run_over_step(dt):
		return
	if lounge:
		_lounge(dt)
		return
	if post != null:
		_stand_at_post(dt)
		return
	if _duel_step(dt):
		return
	var s := sled.global_position
	var to_top := Vector2(s.x, s.z).distance_to(_top_of(s))
	_watch_offer()
	if state != State.RIDE and (_five_with > 0 or _rooted()):
		_go_five(dt)
		return
	var teamed := roam and not _team.is_empty()
	if roam and not _helping(dt) and _team.is_empty():
		if state == State.RIDE:
			_roam_ride(dt)
		else:
			_roam_walk(dt)
		return
	if not _team.is_empty() and _team_step(dt):
		return
	if teamed:
		to_top = 100.0   # 組のときは、頂上に着いたかを _team_step が見る

	if state == State.RIDE:
		global_position = sled.to_global(seat)
		_pose_doll()
		# あなたがいないときは、仲間が体重をかけて滑り出す
		if player == null and to_top < 8.0:
			sled.lean(0.0, true)
		_follow_lean(dt)
		_still = _still + dt if sled.linear_velocity.length() < 0.4 else 0.0
		if _still > 1.5 and to_top > 14.0:
			_still = 0.0
			get_off()
		return

	var up := _uphill(s)
	var dir := Vector3.ZERO
	if state == State.PUSH:
		if to_top < 4.0:
			let_go()
			state = State.WAIT
			_wait = 0.0
		elif handle != Vector3.INF:
			# つかんでいる: 体はソリについて行き、縁に手をかけて頂上へ押す
			global_position = sled.to_global(handle)
			# ソリの軸に沿って押しながら、向きを頂上へ向け直す。
			# 大きくずれているときは進める力をかけず、まず向きを直す（縁を横に押して回す）
			var fwd: Vector3 = -sled.global_basis.z
			fwd.y = 0
			fwd = fwd.normalized()
			var err := atan2(fwd.cross(up).y, fwd.dot(up))
			# ソリの軸に沿って押し、縁を横に押して向きを頂上へ向け直す。
			# 60° 以上ずれているときは進めず、その場で向きを直す（止まったソリは静止摩擦で留まる）。
			# 回りすぎないよう、いま回っている速さの分は弱める
			var steer: float = clamp(err * 2.5 - sled.angular_velocity.y * 0.5, -1.0, 1.0)
			var ahead: float = max(0.0, cos(err)) if abs(err) < deg_to_rad(60.0) else 0.0
			var push_dir: Vector3 = fwd * ahead + sled.global_basis.x * steer * 1.2
			if not _team.is_empty():   # 組: 小さなソリは縁を横に押すと横へ流れて回らないので、体で向きを回す
				# 頂上で滑る向きへ回しているあいだは、前へ押さない（行き先は下りなので、押すと回し終える前に頂上から滑り落ちる）
				push_dir = fwd * ahead if not _team.route.is_empty() else Vector3.ZERO
				if _team.go and absf(err) > 0.2:
					sled.apply_torque(Vector3.UP * clampf(err, -1.0, 1.0) * sled.mass * TEAM_TWIST)
			var waiting: bool = not _team.is_empty() and not _team.go   # みんながつかむまで押さない
			if push_dir.length() > 0.05 and not sled.is_dragged(self) and not waiting:
				push_world = push_dir.normalized()
				sled.push(push_world, global_position + fwd * 0.6 + Vector3.UP * 0.4, self, damp_k(true))
			debug = "err=%.0f° steer=%.2f ahead=%.2f 手=%s" % [rad_to_deg(err), steer, ahead, str(sled.to_local(global_position + fwd * 0.6 + Vector3.UP * 0.4).snapped(Vector3(0.1, 0.1, 0.1)))]
			var face := s - global_position
			face.y = 0
			if face.length() > 0.1:
				look_at(global_position + face, Vector3.UP)
			_pose_doll()
			return
		else:
			# 持ち場はソリの横の縁の後ろの角。いま自分がいる側を選び、他の仲間が持っていれば反対側。
			# 後ろの真ん中はあなたの分
			var lp0: Vector3 = sled.to_local(global_position)
			var want: float = signf(lp0.x) if abs(lp0.x) > 0.05 else float(side)
			if _post_taken(want):
				want = -want
			var stand_l := Vector3((sled.HALF.x + sled.STAND) * want, 0, sled.HALF.y)   # 後ろの角のつかみ所
			var post: Vector3 = sled.to_global(stand_l)
			var to := post - global_position
			to.y = 0
			# ソリに突き当たらない経路: 反対側の持ち場へは、自分側の後ろの角 → 後ろの通路 → 持ち場、と回る
			var lp: Vector3 = sled.to_local(global_position)
			var lpost: Vector3 = sled.to_local(post)
			var hx: float = sled.HALF.x
			var hz: float = sled.HALF.y
			var sx := signf(lp.x) if abs(lp.x) > 0.05 else float(side)
			var lane := hz + 0.9
			var outside := hx + 0.7
			var target_l: Vector3
			if lp.z >= lane:
				target_l = Vector3(lpost.x, 0, hz + 1.1) if abs(lp.x - lpost.x) > 0.3 else lpost
			elif signf(lp.x) == signf(lpost.x) and abs(lp.x) >= outside:
				target_l = lpost
			elif abs(lp.x) < outside:
				target_l = Vector3(sx * (hx + 1.1), 0, lp.z)       # まず横へ出る
			else:
				target_l = Vector3(sx * (hx + 1.1), 0, hz + 1.1)   # 自分側の後ろの角へ
			to = sled.to_global(target_l) - global_position
			to.y = 0
			dir = _round_player(to.normalized()) if to.length() > 0.2 else up
			debug = "持ち場まで%.2f" % (post - global_position).length()
			var reach := 1.4 if _player_within(1.0) else 0.8   # あなたが持ち場のそばに立っていて寄れなければ、少し遠くからつかむ
			if not _team.is_empty():
				dir = _team_walk(dir, post, dt)
				if _lost_t > TEAM_NEAR_WAIT:
					reach = TEAM_REACH
			if (post - global_position).length() < reach and _regrab <= 0.0:
				if sled.take_handle(self, stand_l):
					handle = stand_l
					_col.disabled = true
	elif state == State.WAIT:
		_wait += dt
		var rider_ok: bool = _humans().is_empty() or _humans().any(func(h): return h.get("seat") != null and h.seat != Vector3.INF)
		if rider_ok and _wait > 1.0 and global_position.distance_to(s) < 3.5:
			seat = sled.mount(self)
			if seat != Vector3.INF:
				_col.disabled = true
				state = State.RIDE
				return
		var to := s - global_position
		to.y = 0
		if to.length() > 2.0:
			dir = to.normalized()
		if to_top > 6.0:
			state = State.PUSH   # 頂上からずり落ちたら押し直す

	velocity.x = dir.x * SPEED * damp_k(false)
	velocity.z = dir.z * SPEED * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if dir.length() > 0.1:
		look_at(global_position + dir, Vector3.UP)
	_pose_doll()


## 通り道にあなたが立っていれば、ソリから離れる側へ回る（握手のあとは、あなたの正面にいるので、ソリがあなたの向こうだと突き当たって止まる）
func _round_player(dir: Vector3) -> Vector3:
	if not _player_within(1.3):
		_rounding = false
		return dir
	var gap := Emotes._flat(player.global_position - global_position)
	if dir.dot(gap.normalized()) <= 0.5:
		return dir
	if not _rounding:   # 回る向きは、回り終えるまで変えない（左右に振れて進めなくなる）
		_rounding = true
		var away := Emotes._flat(global_position - sled.global_position)
		_turn_sign = 1.0 if dir.rotated(Vector3.UP, 1.2).dot(away) > dir.rotated(Vector3.UP, -1.2).dot(away) else -1.0
	return dir.rotated(Vector3.UP, 1.2 * _turn_sign)


var _rounding := false       # あなたのまわりを回っている途中


## 遊んでいる人: この画面の人と、通信でつないでいる人。仲間は入らない
func _humans() -> Array:
	var out := [player] if player and not Ghost.gone(player) else []   # 観戦モードの霊体（ghost.gd）は、いない人と同じ
	var net := get_parent().get_node_or_null("Net")
	if net:
		for r in net.remotes.values():
			if not Ghost.gone(r):
				out.append(r)
	return out


## いちばん近くの、遊んでいる人（いなければ null）
func _nearest_human() -> Node3D:
	var best: Node3D = null
	var near := INF
	for h in _humans():
		var d: float = global_position.distance_squared_to(h.global_position)
		if d < near:
			near = d
			best = h
	return best


## 通信で配る姿の段（remote_person.gd の Mode の並び）
func net_mode() -> int:
	if seat_i >= 0:
		return 4
	if state == State.RIDE:
		return 2
	return 1 if handle != Vector3.INF else 0


func _player_within(m: float) -> bool:
	return player != null and not Ghost.gone(player) and Emotes._flat(player.global_position - global_position).length() < m


## 一緒に乗っているあなたの体重移動に、少し遅れて合わせる
func _follow_lean(dt: float) -> void:
	_clock += dt
	var with_me = null
	for h in _humans():
		if h.get("mode") == h.Mode.RIDE and h.sled == sled:
			with_me = h
			break
	if lean_mode != "follow" or with_me == null:
		_lean_q.clear()
		_lean_now = Vector3.ZERO
		return
	_lean_q.append([_clock, with_me.ride_lean])
	while not _lean_q.is_empty() and _clock - _lean_q[0][0] >= LEAN_DELAY:
		_lean_now = _lean_q.pop_front()[1]
	if _lean_now != Vector3.ZERO:
		sled.lean(_lean_now.x, _lean_now.y > 0.0, _lean_now.z > 0.0)


## 持ち場へ歩いて行って立ち、見る先を向く（ミシンの足踏み。sewing_machine.gd が呼ぶ）
func _stand_at_post(dt: float) -> void:
	var to := post.global_position - global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.15 else Vector3.ZERO
	velocity.x = dir.x * SPEED * damp_k(false)
	velocity.z = dir.z * SPEED * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	var face := dir
	if dir == Vector3.ZERO and post_look != Vector3.INF:
		face = post_look - global_position
		face.y = 0
	if face.length() > 0.1:
		look_at(global_position + face, Vector3.UP)
	doll.act = Doll.Act.WALK
	doll.sled = sled
	doll.grip = Vector3.INF
	doll.effort = false
	doll.airborne = false
	doll.gaze = post_look


## その側の後ろの持ち場を、他の仲間がすでにつかんでいるか
func _post_taken(side_sign: float) -> bool:
	for who in sled.holders:
		if who == self:
			continue
		var h: Vector3 = sled.holders[who]
		if h.z > 0.5 and signf(h.x) == side_sign and abs(h.x) > 0.9:
			return true
	return false


## 人形に、いまの動きを伝える（姿勢は人形が 12 コマで刻む）
func _pose_doll() -> void:
	if state == State.RIDE:
		doll.act = Doll.Act.RIDE
	elif handle != Vector3.INF:
		doll.act = Doll.Act.PUSH
	else:
		doll.act = Doll.Act.WALK
	doll.sled = sled
	if hub:
		doll.holding_ball = hub.balls_of(id) > 0 and hub.can_throw(id)   # 持っている雪玉（右手に 1 つ、残りは袖。player.gd と同じ）
		doll.sleeve_balls = hub.balls_of(id) - (1 if doll.holding_ball else 0)
	doll.lean = Vector2(_lean_now.x, _lean_now.y - _lean_now.z) if state == State.RIDE else Vector2.ZERO
	if craft:
		doll.lantern = craft.lantern(id).get("look", "")
		doll.lantern_lit = craft.lamp_on(id)
		var spec: Dictionary = craft.sack(id)   # 帯の丸めた米袋（player.gd と同じ）
		doll.belt_sack = not spec.is_empty() and craft.sack_sled(id) == null
		if not spec.is_empty():
			doll.belt_color = preload("res://fabrics.gd").color(spec.fabric) if spec.fabric != "" else preload("res://sled.gd").KINDS["sack"].color
	doll.grip = handle
	doll.effort = handle != Vector3.INF and sled.pushers > 0
	doll.dragged = handle != Vector3.INF and sled.is_dragged(self)
	doll.airborne = not is_on_floor() and state != State.RIDE and handle == Vector3.INF
	# 顔の向き: あなたが指さしたら、指された所を一緒に見る。押していないときは、近くのあなたの顔を見る
	doll.gaze = Vector3.INF
	doll.waving = _wave_t > 0.0
	var person = _nearest_human()
	if _look_t > 0.0 and is_instance_valid(_caller):
		doll.gaze = _caller.global_position + Vector3.UP * 1.25   # 呼ばれた人のほうを見る
	elif person:
		var hub = get_parent().get_node_or_null("Emotes")   # あなたが指している所（配られた向きから。通信でも同じ）
		var pt: Vector3 = hub.point_of(int(person.get("id"))) if hub and person.get("id") != null else person.point_at
		if pt != Vector3.INF:
			doll.gaze = pt
		elif handle == Vector3.INF and global_position.distance_to(person.global_position) < 8.0:
			doll.gaze = person.global_position + Vector3.UP * 1.25


# ---------------------------------------------------------------- 身ぶりへの返し

var _shape := ""             # 仲間がいま掲げている手（Palm.HANDS の名前）
var _five_shape := ""        # 合わせにいく手（"high_R" "low_both" など）
var _lower_t := 0.0          # 返しで掲げた形を下ろすまで (s)
var _look_t := 0.0           # 呼ばれて、あなたのほうを見ているあいだ (s)
var _wave_t := 0.0           # 呼ばれて、手を振っているあいだ (s)


func _on_emote(ev: Dictionary) -> void:
	var who: int = ev.get("who", -1)
	if who == id:
		if ev.kind in Emotes.BALL_EVENTS:
			return
		if ev.kind == "hands":
			_shape = ev.hands
			doll.play(ev)
			return
		_em = ev
		doll.play(ev)
		if ev.kind in ["high_five", "shake", "whiff"]:
			_five_with = -1   # 合った・空振りした。持ち場へ戻る
		if ev.kind == "hit" and handle != Vector3.INF:
			let_go()   # びっくりして手を離す
			_regrab = REGRAB_WAIT
		if ev.kind == "hit" or ev.kind == "flung":
			_wind = -1.0   # 振りかぶっていても、のけぞって投げられない
		if ev.kind == "hit" and randf() < 0.6:
			_reply(randf_range(0.7, 1.0), {"kind": "wa"})   # 当たっても楽しい
		return
	if ev.kind == "throw":
		_saw_throw(ev)
	# 返すのは、あなた（人）の身ぶりにだけ（仲間どうしで返し合い続けないように）
	var them = hub.who_of(who)
	if them == null or not them in _humans():
		return
	var near := global_position.distance_to(them.global_position)
	match ev.kind:
		"wa", "un", "nn":
			if near < 15.0 and not ev.get("auto", false):
				_reply(randf_range(0.35, 0.8), {"kind": ev.kind})
		"huh":
			if near < 15.0:
				_reply(randf_range(0.4, 0.8), {"kind": "un"})   # たずねられたら、ウンとうなずく
		"oi":
			# 呼ばれたら、そちらを見て、おーいと返すか、手を振る（遠くても届く）
			if near < 100.0:
				_look_t = 3.0
				_caller = them
				if randf() < 0.5 or handle != Vector3.INF:
					_reply(randf_range(0.7, 1.1), {"kind": "oi"})
				else:
					_wave_t = 2.5
		"clap":
			if near < 10.0:
				_reply(randf_range(0.15, 0.3), {"kind": "hands", "hands": "high_both"})
				_reply(randf_range(0.4, 0.6), {"kind": "clap"})
				_lower_t = 2.2
		"hands":
			var h: String = ev.hands
			if h == "":
				if _five_with == who:
					_five_with = -1
				return
			var parts := h.split("_")
			var both := parts[1] == "both"
			if h == "high_both" and state == State.RIDE and them.get("mode") == them.Mode.RIDE:
				_reply(randf_range(0.1, 0.25), {"kind": "hands", "hands": "high_both"})   # 一緒に乗っていれば、一緒に万歳
				_reply(randf_range(0.35, 0.5), {"kind": "wa"})
				_lower_t = 3.0
			elif near < 7.0 and state != State.RIDE and not lounge and _offered_to_me(parts[0], who):
				# 手のひらを差し出された: 前まで行って、同じ高さで掲げる（片手か両手かもまねる。片手なら右手）
				_five_with = who
				_five_shape = Palm.hands_name(parts[0], "both" if both else "R")
				_five_until = Doll.frame_index() + 12 * 8
				_five_sent = false
				_five_ball = _wants_ball(parts[0], who)


func _reply(after: float, ev: Dictionary) -> void:
	_replies.append([after, ev])


func _update_replies(dt: float) -> void:
	for r in _replies.duplicate():
		r[0] -= dt
		if r[0] <= 0.0:
			_replies.erase(r)
			var ev: Dictionary = r[1].duplicate()
			ev["who"] = id
			hub.send(ev)
	_look_t = maxf(0.0, _look_t - dt)
	_wave_t = maxf(0.0, _wave_t - dt)
	if _lower_t > 0.0:
		_lower_t -= dt
		if _lower_t <= 0.0 and _shape != "" and _five_with < 0:
			hub.send({"kind": "hands", "who": id, "hands": ""})


func _rooted() -> bool:
	if _em.is_empty():
		return false
	var spec: Dictionary = Emotes.KINDS.get(_em.kind, {})
	return spec.get("root", false) and Doll.frame_index() - int(_em.frame) < spec.frames


## 手のひら（グー）を掲げた相手の前まで歩き、向き合って同じ形を掲げる（届けば配り役が合わせる）
func _go_five(dt: float) -> void:
	var dir := Vector3.ZERO
	var them := hub.who_of(_five_with)
	if _five_with > 0 and (them == null or Doll.frame_index() > _five_until):
		_five_with = -1
		if _shape != "":
			hub.send({"kind": "hands", "who": id, "hands": ""})
	elif _five_with > 0:
		let_go()
		var fwd: Vector3 = Emotes._forward(them)
		# 握手は手のひらをくっつけるので、ハイタッチより近くまで行く
		var spot: Vector3 = them.global_position + fwd * (0.7 if _five_shape.begins_with("low") else 0.95)
		var to := spot - global_position
		to.y = 0
		var face: Vector3 = them.global_position - global_position
		face.y = 0
		if _five_ball and hub.balls_of(id) < 1 and not _rooted():
			hub.send({"kind": "make_ball", "who": id})   # 対決に応じる: まず雪玉を丸める
		_five_ball = _five_ball and (hub.balls_of(id) < 1 or _rooted())
		if to.length() > 0.15 and not _five_ball:
			dir = to.normalized()
		if face.length() > 0.1:
			look_at(global_position + face, Vector3.UP)
		if not _five_ball and not _five_sent and to.length() < 0.6 and Emotes._forward(self).dot(face.normalized()) > 0.6:
			hub.send({"kind": "hands", "who": id, "hands": _five_shape})
			_five_sent = true
	velocity.x = dir.x * SPEED * damp_k(false)
	velocity.z = dir.z * SPEED * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	_pose_doll()


# ---------------------------------------------------------------- 雪合戦の対決（duel.gd）

const DUEL_BUTTONS := 50     # 財布にいつも持っている分（木の何個分。金色の真鍮のボタン 5 枚）。2026-11-05 代表「CPUは金5枚持っていてほしいです」
const BET_WAIT := 4.0        # 掛金がこれだけ変わらなければ受ける (s)。あなたが額を選び終えるのを待つ
const START_WAIT := 1.5      # 戦いが始まってから、最初に投げるまで (s)
const THROW_EVERY := Vector2(0.0, 1.2)   # 投げられるようになってから（duel.gd の THROW_GAP）、次に振りかぶるまで (s)
const WINDUP_T := 0.4        # 投げる前に振りかぶる長さ (s)。あなたが見てからよけられるように
const THROW_SPREAD := 2.4    # 投げる速さのずれ (m/s)。大きいほど外れる
const CATCH_ODDS := 0.2      # あなたの雪玉を取りにいく割合
const DODGE_ODDS := 0.35     # あなたの雪玉をよける割合（残りは、そのまま受ける）
const DODGE_T := 0.5         # 横へよける長さ (s)
const REACT_T := Vector2(0.1, 0.25)   # 投げられてから動き出すまで (s)

var _duel_t := 0.0           # 次に投げる・受けるまで (s)
var _duel_stake := -1        # 見ていた掛金（変わったら、少し待ってから受ける）
var _orbit := 0.0            # 円のまんなかのまわりを回る角
var _orbit_dir := 1.0
var _wind := -1.0            # 振りかぶっている残り (s)。負なら振りかぶっていない
var _catching := -1          # 取りにいく雪玉の番号
var _dodge := Vector3.ZERO   # よける向き
var _dodge_wait := 0.0       # よけ始めるまで (s)
var _dodge_t := 0.0          # よける残り (s)
var _five_ball := false      # 握手しに行く前に、雪玉を作る（対決に応じる）


## 雪玉を持って低い手のひらを差し出すのは、対決の申し込み: 見ている相手にだけ応じる（仲間が何人いても、見て選べる）
func _offered_to_me(height: String, who: int) -> bool:
	if height != "low" or hub.balls_of(who) < 1:
		return true
	var them: Node3D = hub.who_of(who)
	return Emotes._flat(-them.global_basis.z).normalized().dot(Emotes._flat(global_position - them.global_position).normalized()) > 0.8


## 雪玉を持って低い手のひらを掲げたまま、こちらを見ている人（あとから近づいた・あとから向いた）にも応じる
func _watch_offer() -> void:
	var duel := get_parent().get_node_or_null("Duel")
	if _five_with > 0 or state == State.RIDE or duel == null or not duel.of(id).is_empty():
		return
	for them in _humans():
		var who := int(them.get("id"))
		var h: String = hub.hands.get(who, "")
		if who < 0 or not h.begins_with("low") or hub.balls_of(who) < 1:
			continue
		var d: float = global_position.distance_to(them.global_position)
		if d < OFFER_FAR and _offered_to_me("low", who):
			_five_with = who
			_five_shape = Palm.hands_name("low", "both" if h.ends_with("both") else "R")
			_five_until = Doll.frame_index() + 12 * maxi(8, int(d / SPEED) + 4)
			_five_sent = false
			_five_ball = _wants_ball("low", who)
			return


## 低い手のひらを差し出した人が雪玉を持っていて、自分は持っていない: 握手で対決が始まるように作る（ロッジの床では始まらないので作らない）
func _wants_ball(height: String, who: int) -> bool:
	var duel := get_parent().get_node_or_null("Duel")
	var w := get_parent()
	return height == "low" and duel != null and duel.of(id).is_empty() and hub.balls_of(who) > 0 and hub.balls_of(id) < 1 \
		and w.lodge_weight(global_position.x, global_position.z) >= 1.0


## 対決の相手が投げた: 取りにいくか、よけるか、そのまま受けるかを 1 球に 1 度決める
func _saw_throw(ev: Dictionary) -> void:
	var duel := get_parent().get_node_or_null("Duel")
	if duel == null:
		return
	var d: Dictionary = duel.fighting(id)
	if d.is_empty() or duel.opponent(d, id) != int(ev.who):
		return
	var roll := randf()
	if roll < CATCH_ODDS:
		_catching = int(ev.get("ball", -1))
	elif roll < CATCH_ODDS + DODGE_ODDS:
		var v: Vector3 = ev.velocity
		v.y = 0
		_dodge = v.cross(Vector3.UP).normalized()
		var at: Vector3 = d.at
		if _dodge.dot(at - global_position) < 0.0:
			_dodge = -_dodge   # 円のまんなかの側へ（縁に追いつめられない）
		_dodge_wait = randf_range(REACT_T.x, REACT_T.y)
		_dodge_t = DODGE_T


## 取りにいく雪玉が手の届く所に来たら取る（取れたかはホストが決める）
func _try_catch(duel: Node) -> void:
	if _catching < 0:
		return
	if not duel.reach_for(self, _catching):
		_catching = -1


## 財布が DUEL_BUTTONS より少なければ、そこまで足す（多いぶんは持ったまま）。はじめと、握手で掛金の画面に入るとき
func _fill_wallet() -> void:
	var lack: int = DUEL_BUTTONS - craft.wallet(id)
	if lack > 0:
		craft.send({"kind": "earn", "who": id, "n": lack})


## 対決にかかわっているあいだの動き。動かしたら true（ふだんの動きはしない）
func _duel_step(dt: float) -> bool:
	var duel := get_parent().get_node_or_null("Duel")
	if duel == null:
		return false
	var d: Dictionary = duel.of(id)
	if d.is_empty():
		_duel_stake = -1
		return false
	var them: Node3D = hub.who_of(duel.opponent(d, id))
	far = false
	_duel_t -= dt
	match String(d.phase):
		"bet":
			if _duel_stake < 0:   # 掛金の画面に入ったところ（前の対決で減った分は、ここで戻る）
				_fill_wallet()
				if _vs_bot(them) and id == int(d.a):   # 仲間どうし: 誘った側が額を出す
					duel.send({"kind": "bet", "who": id, "n": randi_range(1, 3) * 5})
			if int(d.stake) != _duel_stake:
				_duel_stake = int(d.stake)
				_duel_t = BET_WAIT
			var ok: bool = d.ok_a if id == int(d.a) else d.ok_b
			if not ok and _duel_t <= 0.0:
				_duel_t = BET_WAIT
				duel.send({"kind": "ok", "who": id})
			_duel_move(Vector3.ZERO, them, dt)
			return true
		"fight":
			if _duel_stake >= 0:   # 始まったところ
				_duel_stake = -1
				_duel_t = START_WAIT
				if _vs_bot(them):   # 仲間どうし: 円の向かい合う所を、同じ向きに回る
					_orbit = float(d.id) * 1.7 + (PI if id == int(d.b) else 0.0)
					_orbit_dir = 1.0 if int(d.id) % 2 == 0 else -1.0
				_wind = -1.0
				_catching = -1
				_dodge_t = 0.0
			let_go()
			_duel_fight(d, them, dt, duel)
			return true
		"over":
			if _wind >= 0.0 and them:   # 振りかぶっていた分は投げてしまう（腕が上がったままにならない。もう数えない）
				_wind = -1.0
				_duel_throw(them)
			# 払いの握手をしにいく（相手の前で低い手のひら）
			if them and _five_with < 0 and _shape == "":
				_five_with = duel.opponent(d, id)
				_five_shape = "low_R"
				_five_ball = false
				_five_until = Doll.frame_index() + 12 * 25
				_five_sent = false
	return false


func _duel_fight(d: Dictionary, them: Node3D, dt: float, duel: Node) -> void:
	if them == null:
		_duel_move(Vector3.ZERO, null, dt)
		return
	var at: Vector3 = d.at
	if randf() < dt * 0.25 and not _vs_bot(them):
		_orbit_dir = -_orbit_dir   # ときどき向きを変える
	_orbit += dt * 0.32 * _orbit_dir
	var goal := at + Vector3(cos(_orbit), 0, sin(_orbit)) * 3.2
	var to := goal - global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.3 else Vector3.ZERO
	_try_catch(duel)
	_dodge_wait -= dt
	if _dodge_t > 0.0 and _dodge_wait <= 0.0:
		_dodge_t -= dt
		dir = _dodge
	if _rooted():
		dir = Vector3.ZERO
	elif hub.balls_of(id) <= 0:
		hub.send({"kind": "make_ball", "who": id})   # なくなったら、しゃがんで作る
		dir = Vector3.ZERO
		_wind = -1.0
	elif _wind >= 0.0:
		_wind -= dt
		if _wind < 0.0:
			_duel_throw(them)
			_duel_t = duel.THROW_GAP + randf_range(THROW_EVERY.x, THROW_EVERY.y)
	elif _duel_t <= 0.0 and duel.can_throw(id):
		_duel_t = randf_range(THROW_EVERY.x, THROW_EVERY.y) + 1.0   # のけぞって投げられなかったら、また少し待つ
		_wind = WINDUP_T
		hub.send({"kind": "windup", "who": id})
	_duel_move(dir, them, dt)
	duel.keep_in(self, id)


## 相手の胸へ、山なりに投げる（少しずらす。立っている相手に半分ほど当たる。動いている先は読まないので、歩いていればよけられる）
func _duel_throw(them: Node3D) -> void:
	var fwd := Emotes._forward(self)
	var origin := global_position + Vector3.UP * doll.height() * 0.85 + fwd * 0.4
	var h: float = them.doll.height() if them.get("doll") else 1.6
	var target: Vector3 = them.global_position + Vector3.UP * h * 0.6
	var flat: Vector3 = target - origin
	flat.y = 0
	var vh := 10.0
	var t := maxf(flat.length() / vh, 0.1)
	var vy: float = (target.y - origin.y + 0.5 * 9.8 * t * t) / t
	var vel: Vector3 = flat.normalized() * vh + Vector3.UP * vy
	vel += Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * THROW_SPREAD
	hub.send({"kind": "throw", "who": id, "origin": origin, "velocity": vel})


func _duel_move(dir: Vector3, them: Node3D, dt: float) -> void:
	if them:
		var face: Vector3 = them.global_position - global_position
		face.y = 0
		if face.length() > 0.1:
			look_at(global_position + face, Vector3.UP)
	velocity.x = dir.x * SPEED * damp_k(false)
	velocity.z = dir.z * SPEED * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	_pose_doll()


# ---------------------------------------------------------------- 山めぐり

## はじめの山（main.gd。ばらけた所から始める）
func roam_from(area: String) -> void:
	_area = area
	_route = _route_of(area)


## 山へ行く道: 尾根を麓から頂上へ（from にいちばん近い点から）→ 頂上 → 滑り出す所
func _route_of(area: String, from_at := Vector3.INF) -> Array:
	var a: Dictionary = ROAM_AREAS[area]
	var from3: Vector3 = global_position if from_at == Vector3.INF else from_at
	var at := Vector2(from3.x, from3.z)
	var out: Array = []
	if a.has("ridge"):
		var pts: Array = a.ridge.duplicate()
		pts.reverse()
		var near := INF
		var from := 0
		for i in pts.size():
			var d: float = at.distance_to(pts[i])
			if d < near:
				near = d
				from = i
		out = pts.slice(from)
		out.append(a.top)
		var side: Vector2 = a.side * randf_range(-1.0, 1.0)
		out.append(a.launch + side * 3.0)
		_ride_goal = a.foot + side * float(a.spread)
	else:
		out.append(a.top)
		var dir := Vector2.from_angle(randf() * TAU)   # 丘はどの向きにも滑れる
		out.append(a.top + dir * 6.0)
		_ride_goal = a.top + dir * 58.0
	return out


## 次の山: 人のいる山に向かっている仲間がいなければ、そこへ（遊ぶ人が対決を申し込む相手が見つからなくならないように）。
## それ以外は、さっきと別の、向かっている仲間が少ない山
func _pick_area() -> String:
	if get_parent().get("args") and get_parent().args.has("roam-all-hill"):
		return "hill"
	var count := {}
	for k in ROAM_AREAS:
		count[k] = 0
	for b in get_tree().get_nodes_in_group("bots"):
		if b != self and count.has(b._area):
			count[b._area] += 1
	for h in _humans():
		var a := Areas.of(Vector2(h.global_position.x, h.global_position.z))
		a = a if ROAM_AREAS.has(a) else "hill"
		if count[a] == 0:
			return a
	var best: Array = []
	var low := 999
	for k in ROAM_AREAS:
		if k == _last_area:
			continue
		if count[k] < low:
			low = count[k]
			best = []
		if count[k] == low:
			best.append(k)
	return best[randi() % best.size()]


## 次の山へ歩く。頂上の先（広げる所）まで来たら、米袋を広げて乗る
func _roam_walk(dt: float) -> void:
	if _area == "":
		_roam_rest -= dt
		if _roam_rest > 0.0:
			_settle_walk(Vector3.ZERO, dt)
			return
		if _try_errand() or _try_team():
			return
		_area = _pick_area()
		_route = _route_of(_area)
		_wp_best = INF
		_wp_t = 0.0
	if _route.is_empty():
		if _errand != "":
			_errand_step(dt)
			_settle_walk(Vector3.ZERO, dt)
			return
		_roam_launch()
		_settle_walk(Vector3.ZERO, dt)
		return
	_maybe_duel(dt)
	var at := Vector2(global_position.x, global_position.z)
	var w: Vector2 = _route[0]
	var gap := at.distance_to(w)
	_wp_t += dt
	if gap < _wp_best - 0.5:
		_wp_best = gap
		_wp_t = 0.0
	if gap < 1.5 or (gap < WP_NEAR and _wp_t > WP_NEAR_T):   # 着いた（物が置いてあって寄れなければ、そばまでで）
		_next_point()
		return
	if _wp_t > WP_GIVE_UP and not _ghost:   # 回り込んでも着けない（点は飛ばさない。頂上でない所で広げないように）
		give_ups += 1
		_ghost = true
		_col.disabled = true
		_nav_clear()
	_far_t -= dt
	if _far_t <= 0.0:
		_far_t = randf_range(0.4, 0.6)
		var h := _nearest_human()
		far = h == null or global_position.distance_to(h.global_position) > FAR
	var dir := Vector3(w.x - at.x, 0, w.y - at.y).normalized()
	if far or _ghost:
		_far_acc += dt
		if _far_acc < FAR_STEP:
			return
		var move := minf(ROAM_SPEED * _far_acc, gap)
		_far_acc = 0.0
		global_position += dir * move
		global_position.y = get_parent().height(global_position.x, global_position.z) + 0.02
		velocity = Vector3.ZERO
		look_at(global_position + dir, Vector3.UP)
		_pose_doll()
		if _ghost and not _ground_blocked(global_position, false):
			_ghost = false
			_col.disabled = false
			_wp_best = INF
			_wp_t = 0.0
		return
	_settle_walk(_steer_to(w, dt), dt)


func _next_point() -> void:
	_route.pop_front()
	_wp_best = INF
	_wp_t = 0.0
	_nav_clear()


func _nav_clear() -> void:
	_nav = []
	_nav_job = {}
	_nav_wait = 0.0


## ここに地面の高さで立つと、何かに当たるか（床の段も当たる。people なら人と仲間も見る）
func _ground_blocked(at: Vector3, people := true) -> bool:
	_nav_ready()
	var p := Vector3(at.x, get_parent().height(at.x, at.z) + 0.05 + (_col.shape as CapsuleShape3D).height * 0.5, at.z)
	_nav_q.transform = Transform3D(Basis.IDENTITY, p)
	return _nav_blocked(get_world_3d().direct_space_state, p, people)


## w へ歩く向き。ふだんはまっすぐ。近づけないでいる（_wp_t）あいだだけ、まわりの当たりを調べて回り込む道をたどる（ソリ・ロッジ・木・立っている人）。
## 探している数コマは、その場で待つ（Vector3.ZERO）
func _steer_to(w: Vector2, dt: float) -> Vector3:
	var at := Vector2(global_position.x, global_position.z)
	_nav_wait -= dt
	while not _nav.is_empty():
		var to: Vector2 = _nav[0] - at
		if to.length() > 0.4:
			_nav_t += dt
			if _nav_t <= NAV_STEP_T:
				return Vector3(to.x, 0, to.y).normalized()
			_nav = []   # 何かにふさがれた: 探し直す
			break
		_nav.pop_front()
		_nav_t = 0.0
	if _nav_job.is_empty():
		var dir := Vector3(w.x - at.x, 0, w.y - at.y).normalized()
		if _nav_wait > 0.0:
			return dir
		# 床の上にいないときは、少し先も見る（ぶつかってからでは、ロッジの出入り口から上がってしまう）
		var on_ground: bool = global_position.y - get_parent().height(global_position.x, global_position.z) < 0.25
		if _wp_t <= NAV_AFTER and not (on_ground and _ground_blocked(global_position + dir * NAV_AHEAD, false)):
			return dir
		_nav_begin(w, 0)
	_nav_scan()
	return Vector3.ZERO


## 自分のまわりの格子を用意する（NAV_CELL おき。ますの番号は、座標を NAV_CELL で割った数。当たりは 1 コマに少しずつ調べる）
func _nav_begin(w: Vector2, size: int) -> void:
	var half := int(NAV_SIZES[size] / NAV_CELL)
	var g := AStarGrid2D.new()
	g.region = Rect2i(_nav_cell_of(Vector2(global_position.x, global_position.z)) - Vector2i(half, half), Vector2i(half, half) * 2 + Vector2i.ONE)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES   # 角を斜めに抜けない
	g.update()
	# 床の上（ロッジの縁の段）に乗っていれば、その高さで調べる。床の段を壁と見ないように
	var ground: float = get_parent().height(global_position.x, global_position.z)
	_nav_job = {"grid": g, "row": g.region.position.y, "size": size, "to": w, "lift": maxf(0.05, global_position.y - ground)}


func _nav_cell_of(at: Vector2) -> Vector2i:
	return Vector2i((at / NAV_CELL).round())


func _nav_ready() -> void:
	if _nav_q == null:
		_nav_q = PhysicsShapeQueryParameters3D.new()
		_nav_q.shape = _col.shape
		_nav_q.exclude = [get_rid()]
		_nav_ray = PhysicsRayQueryParameters3D.new()
		_nav_ray.exclude = [get_rid()]


func _nav_scan() -> void:
	var g: AStarGrid2D = _nav_job.grid
	_nav_ready()
	var space := get_world_3d().direct_space_state
	var r := g.region
	var half_h: float = (_col.shape as CapsuleShape3D).height * 0.5
	for _i in maxi(1, NAV_BUDGET / r.size.x):
		var row: int = _nav_job.row
		if row >= r.end.y:
			_nav_solve()
			return
		for col in range(r.position.x, r.end.x):
			var x := col * NAV_CELL
			var z := row * NAV_CELL
			var y: float = get_parent().height(x, z) + _nav_job.lift + half_h
			_nav_q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y, z))
			g.set_point_solid(Vector2i(col, row), _nav_blocked(space, Vector3(x, y, z), true))
		_nav_job.row = row + 1


## 体を置くと、何かに当たるか（地面は見ない）。壁のメッシュは裏から見ると当たらないので（体の中心が薄い壁の厚みの中にあると空いて見える）、十字の光線でも確かめる
func _nav_blocked(space: PhysicsDirectSpaceState3D, at: Vector3, people: bool) -> bool:
	for hit in space.intersect_shape(_nav_q, 8):
		if not _nav_is_ground(hit.collider) and (people or not hit.collider is CharacterBody3D):
			return true
	for arm in [Vector3(NAV_ARM, 0, 0), Vector3(0, 0, NAV_ARM)]:
		_nav_ray.from = at - arm
		_nav_ray.to = at + arm
		var hit := space.intersect_ray(_nav_ray)
		if hit and not _nav_is_ground(hit.collider) and (people or not hit.collider is CharacterBody3D):
			return true
	return false


func _nav_is_ground(c: Object) -> bool:
	return c is StaticBody3D and (c as Node).get_child_count() > 0 and (c as Node).get_child(0) is CollisionShape3D \
			and ((c as Node).get_child(0) as CollisionShape3D).shape is HeightMapShape3D


## 調べ終えた格子で、行き先にいちばん近づける所までの道を探す。十分に近づけなければ、範囲を広げる
func _nav_solve() -> void:
	var g: AStarGrid2D = _nav_job.grid
	var w: Vector2 = _nav_job.to
	var size: int = _nav_job.size
	var at := Vector2(global_position.x, global_position.z)
	_nav_job = {}
	var from: Variant = _nav_free_cell(g, at)
	var aim: Vector2 = at + (w - at).limit_length(float(NAV_SIZES[size]) - 1.0)
	var path: Array = Array(g.get_id_path(from, _nav_cell_of(aim), true)) if from != null else []
	if not path.is_empty():
		var end := Vector2(path[-1]) * NAV_CELL
		if end.distance_to(w) < at.distance_to(w) - NAV_GAIN or end.distance_to(w) < 1.5:
			_nav = path.map(func(c): return Vector2(c) * NAV_CELL)
			_nav_t = 0.0
			return
	if size + 1 < NAV_SIZES.size():
		_nav_begin(w, size + 1)
	else:
		_nav_wait = NAV_RETRY


## 歩き始めるます: 自分のいる所にいちばん近い空いたますのうち、薄い壁の向こうでない所（壁に体を寄せていると、自分のますがふさがって見える）。なければ null
func _nav_free_cell(g: AStarGrid2D, at: Vector2) -> Variant:
	var c := _nav_cell_of(at)
	var near: Array = []
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var p := c + Vector2i(dx, dz)
			if g.is_in_boundsv(p) and not g.is_point_solid(p):
				near.append(p)
	near.sort_custom(func(a, b): return (Vector2(a) * NAV_CELL).distance_squared_to(at) < (Vector2(b) * NAV_CELL).distance_squared_to(at))
	var from := global_transform
	from.origin.y += 0.2   # 坂の雪面を壁と見ないように
	for p in near:
		var to: Vector2 = Vector2(p) * NAV_CELL - at
		if to.length() < 0.05 or not test_move(from, Vector3(to.x, 0, to.y)):
			return p
	return null


func _settle_walk(dir: Vector3, dt: float) -> void:
	velocity.x = dir.x * ROAM_SPEED
	velocity.z = dir.z * ROAM_SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if dir.length() > 0.1:
		look_at(global_position + dir, Vector3.UP)
	_pose_doll()


## 足もとに米袋を広げて乗る（あなたの N と同じ出来事。player.gd の summon_sack）。滑る向きへ少し勢いをつけて
func _roam_launch() -> void:
	far = false
	var at2 := Vector2(global_position.x, global_position.z)
	var to := (_ride_goal - at2).normalized()
	var fwd := Vector3(to.x, 0, to.y)
	look_at(global_position + fwd, Vector3.UP)
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.DOWN * 2.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if hit else global_position
	var up: Vector3 = hit.normal if hit and hit.normal.y > 0.6 else Vector3.UP
	var carry := fwd * 2.5
	carry -= up * carry.dot(up)
	if not craft.send({"kind": "sack_out", "who": id, "at": at, "yaw": rotation.y, "up": up, "v": carry}):
		_roam_done()
		return
	var gs: RigidBody3D = craft.sack_sled(id)
	if gs == null:
		_roam_done()
		return
	sled = gs
	seat = gs.mount(self)
	if seat == Vector3.INF:
		_roam_done()
		return
	_col.disabled = true
	state = State.RIDE
	handle = Vector3.INF
	SackLook.set_stage(gs, seat, 2)
	_ride_t = 0.0
	_still = 0.0
	_kick_t = 0.0
	_goal_best = INF
	_goal_t = 0.0


## 滑る: 行き先へ体重をかけ、足で漕ぐ。行き先を過ぎるか止まったら降りる（雪をかく力で、平らな段も越えられる）
func _roam_ride(dt: float) -> void:
	global_position = sled.to_global(seat)
	_pose_doll()
	_ride_t += dt
	var at := Vector2(global_position.x, global_position.z)
	var to := _ride_goal - at
	var speed: float = sled.linear_velocity.length()
	var hv := Vector2(sled.linear_velocity.x, sled.linear_velocity.z)
	_goal_t += dt
	if to.length() < _goal_best - 3.0:   # 行き先のまわりを回って近づけないときも、着いたことにする
		_goal_best = to.length()
		_goal_t = 0.0
	var arrived: bool = to.length() < 10.0 or (speed > 1.0 and hv.dot(to) < 0.0) or _goal_t > 8.0
	if not arrived:
		var fwd := Emotes._flat(-sled.global_basis.z).normalized()
		var want := Vector3(to.x, 0, to.y).normalized()
		var err := atan2(fwd.cross(want).y, fwd.dot(want))
		sled.lean(clampf(-err * 1.5, -1.0, 1.0), true)
		_kick_t -= dt
		if _kick_t <= 0.0:
			_kick_t = randf_range(0.5, 1.2)
			if speed < 8.0 and sled.kind == "sack":
				sled.kick(self)
	elif to.length() < RIDE_BRAKE_NEAR:
		sled.lean(0.0, false, true)   # 行き先のそばでは後傾で止まる（雪はよく滑るので、そのままだと大きく過ぎる）。滑り出しで向きが逆なだけのときは止めない
	_still = _still + dt if speed < 0.4 else 0.0
	if (arrived and _still > 0.8) or _still > 4.0 or _ride_t > RIDE_MAX:
		_roam_get_off()


## 降りる。米袋なら帯に戻す。ソリならその場に置いて、次の山へ
func _roam_get_off(place := true) -> void:
	var gs := sled
	var was := seat
	sled.dismount(self)
	seat = Vector3.INF
	state = State.PUSH
	_col.disabled = false
	var sack: bool = gs.kind == "sack"
	if place:
		var at: Vector3 = gs.global_position + (gs.global_basis.z * 0.7 if sack else gs.global_basis.x * (gs.HALF.x + 0.8) * side)
		at.y = get_parent().height(at.x, at.z) + 0.2
		global_position = at
	velocity = Vector3.ZERO
	if sack:
		SackLook.set_stage(gs, was, 0)
		craft.send({"kind": "sack_in", "who": id})   # ソリの持ち物を戻す（craft.gd が sled を元のソリへ戻す）
	sled = get_parent().get("sled")
	_roam_done()


func _roam_done() -> void:
	_last_area = _area
	_area = ""
	_route = []
	_nav_clear()
	if _ghost:
		_ghost = false
		_col.disabled = false
	_roam_rest = randf_range(1.0, 4.0)


## そばの人がソリを押す・乗っているあいだは、手伝う（true のあいだ、先の PUSH・WAIT・RIDE で動く）
func _helping(dt: float) -> bool:
	var home: RigidBody3D = get_parent().get("sled")
	if home == null or sled != home:
		return false
	var touched := false
	for h in _humans():
		if h.get("sled") == home and int(h.get("mode")) in [1, 2, 3]:
			touched = true
			break
	if touched and (_help_t > 0.0 or (global_position.distance_to(home.global_position) < HELP_NEAR and _helpers() < HELP_MAX)):
		_help_t = HELP_KEEP
		far = false
		if not _team.is_empty():   # 組で運んでいたロッジのソリを、人がつかんだ: 組をやめて、人を手伝う
			_team.members.erase(self)
			_team = {}
		return true
	if _help_t > 0.0:
		_help_t -= dt
		if _help_t > 0.0:
			return true
		# 人が離れた: 手伝いをやめて、山めぐりへ戻る（行く道は、いまの所から引き直す）
		let_go()
		if state == State.RIDE:
			get_off()
		state = State.PUSH
		if _area != "":
			_route = _route_of(_area)
	return false


func _helpers() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("bots"):
		if b != self and b._help_t > 0.0:
			n += 1
	return n


# ---------------------------------------------------------------- 仲間どうし: ソリを手放したとき

## 乗っているソリ・運んでいるソリがなくなった（片付けられた・立てかけ台へ戻された）・手放したら、もとのソリを見る
func _keep_sled() -> void:
	var home: RigidBody3D = get_parent().get("sled")
	if not is_instance_valid(sled):
		sled = home
		seat = Vector3.INF
		handle = Vector3.INF
		_col.disabled = false
		if state == State.RIDE or not _team.is_empty():
			state = State.PUSH
			_team = {}
			_roam_done()
	elif state != State.RIDE and _team.is_empty() and sled != home:
		sled = home


# ---------------------------------------------------------------- 仲間どうし: 雪合戦

## 雪合戦に誘える（山めぐりの途中で、ほかのことをしていない）
func _free_for_fun() -> bool:
	return roam and state != State.RIDE and _team.is_empty() and _errand == "" and _five_with < 0 and _help_t <= 0.0 and not _ghost


func _vs_bot(them: Node3D) -> bool:
	return them != null and them.is_in_group("bots")


## 近くの仲間を、ときどき雪合戦に誘う。2 人とも雪玉を作って、向かい合って握手する（握手で対決が始まる。duel.gd）
func _maybe_duel(dt: float) -> void:
	_duel_cool -= dt
	if _duel_cool > 0.0:
		return
	_duel_cool = randf_range(DUEL_LOOK.x, DUEL_LOOK.y)
	var duel := get_parent().get_node_or_null("Duel")
	if duel == null or not _free_for_fun() or not duel.of(id).is_empty() or get_parent().lodge_weight(global_position.x, global_position.z) < 1.0:
		return
	for b in get_tree().get_nodes_in_group("bots"):
		if b == self or not b._free_for_fun() or not duel.of(b.id).is_empty() or b._duel_cool > DUEL_LOOK.y:
			continue
		if global_position.distance_to(b.global_position) < DUEL_NEAR:
			if randf() < DUEL_ODDS:
				_ask_duel(b.id)
				b._ask_duel(id)
			return


func _ask_duel(with: int) -> void:
	_duel_cool = randf_range(DUEL_COOL.x, DUEL_COOL.y)
	far = false
	_five_with = with
	_five_shape = "low_R"
	_five_until = Doll.frame_index() + 12 * 40   # 雪玉を作って、DUEL_NEAR を歩いて来られる長さ
	_five_sent = false
	_five_ball = true


# ---------------------------------------------------------------- 仲間どうし: 協力してソリを運ぶ

## 運ぶソリ: 自分のソリか、ロッジのソリ（人が近くになく、誰も触っていないときだけ。丘の中だけで使う）
func _team_sled() -> RigidBody3D:
	if is_instance_valid(own_sled) and _sled_free(own_sled) and global_position.distance_to(own_sled.global_position) < TEAM_NEAR:
		return own_sled
	var home: RigidBody3D = get_parent().get("sled")
	if home == null or not _sled_free(home) or global_position.distance_to(home.global_position) > TEAM_NEAR:
		return null
	var a := Areas.of(Vector2(home.global_position.x, home.global_position.z))
	if a != "hill" and a != Areas.NONE:
		return null
	for h in _humans():
		if h.global_position.distance_to(home.global_position) < LODGE_SLED_CLEAR:
			return null
	return home


func _sled_free(s: RigidBody3D) -> bool:
	if not craft.rack_free(s) or s.racked:
		return false
	for b in get_tree().get_nodes_in_group("bots"):
		if not b._team.is_empty() and b._team.sled == s:
			return false
	return true


## 次の山を選ぶ前に: ソリがあれば、近くの仲間を誘って運ぶ。組ができたら true
func _try_team() -> bool:
	if _team_cool > 0.0 or randf() > TEAM_ODDS:
		return false
	var s := _team_sled()
	if s == null:
		return false
	var mates: Array = []
	for b in get_tree().get_nodes_in_group("bots"):
		if b != self and b._free_for_fun() and b._team_cool <= 0.0 and b.global_position.distance_to(s.global_position) < TEAM_NEAR and not b._in_duel():
			mates.append(b)
	mates.sort_custom(func(a, b): return a.global_position.distance_squared_to(s.global_position) < b.global_position.distance_squared_to(s.global_position))
	var room: int = mini(TEAM_MAX, s.SEATS.size()) - 1
	mates = mates.slice(0, room)
	if mates.is_empty() and s != own_sled:
		return false   # ロッジのソリは、仲間と運ぶときだけ
	make_team(s, mates, _pick_area() if s == own_sled else "hill")
	return true


## 組を作る（s をみんなで area へ運ぶ）
func make_team(s: RigidBody3D, mates: Array, area: String) -> void:
	var route := _route_of(area, s.global_position)
	var at := Vector2(s.global_position.x, s.global_position.z)
	if s.global_position.x < SHED_EXIT.x - 2.0 and s.global_position.x > -32.0 and absf(s.global_position.z - SHED_EXIT.y) < 22.0:
		route.push_front(SHED_EXIT)
	elif _crosses_lodge(at, route[0]):
		for p in LODGE_PASS:
			if not _crosses_lodge(at, p) and not _crosses_lodge(p, route[0]):
				route.push_front(p)
				break
	var t := {"sled": s, "route": route, "goal": _ride_goal, "area": area, "members": [], "go": false, "turned": false,
			"hold_t": 0.0, "stall": 0.0, "best": INF, "turn_t": 0.0}
	for b in [self] + mates:
		b._join_team(t)


func _crosses_lodge(a: Vector2, b: Vector2) -> bool:
	return LODGE_BOX.intersects_segment(Vector3(a.x, 0.5, a.y), Vector3(b.x, 0.5, b.y)) != null


func _in_duel() -> bool:
	var duel := get_parent().get_node_or_null("Duel")
	return duel != null and not duel.of(id).is_empty()


func _join_team(t: Dictionary) -> void:
	_team = t
	t.members.append(self)
	_area = t.area
	_route = []
	_errand = ""
	_ride_goal = t.goal
	sled = t.sled
	state = State.PUSH
	far = false
	_lost_t = 0.0
	_wp_best = INF
	_wp_t = 0.0
	_nav_clear()


## 組を抜ける（着けなかった・乗れなかった）
func _leave_team() -> void:
	let_go()
	_team.members.erase(self)
	_team = {}
	state = State.PUSH
	_roam_done()


## 組の 1 コマ。動かしたら true（false ならソリを押す動きへ）
func _team_step(dt: float) -> bool:
	var t := _team
	if int(t.get("tick", -1)) != Engine.get_physics_frames():   # 組の進み具合は 1 コマに 1 度（誰が見てもよい。誰かが人と握手しに行っても止まらない）
		t["tick"] = Engine.get_physics_frames()
		_team_lead(t, dt)
	if t.turned:
		_team_board(t, dt)
		return true
	_lost_t = 0.0 if handle != Vector3.INF else _lost_t + dt   # 近づいているあいだは _team_walk が 0 に戻す
	if _lost_t > TEAM_LOST:
		_leave_team()
		_settle_walk(Vector3.ZERO, dt)
		return true
	return false


## 組で、つかむ所まで歩く向き。ソリのそばは dir（ソリの縁を回る道）のまま。遠いときと、そばで寄れないでいるときは、物を回り込んで歩く
func _team_walk(dir: Vector3, post: Vector3, dt: float) -> Vector3:
	var w := Vector2(post.x, post.z)
	var gap := Vector2(global_position.x, global_position.z).distance_to(w)
	_wp_t += dt
	if gap < _wp_best - 0.5:
		_wp_best = gap
		_wp_t = 0.0
		_lost_t = 0.0
	if gap > 4.0 or _lost_t > TEAM_NEAR_WAIT:
		return _steer_to(w, dt)
	_nav_clear()
	return dir


## 組の先頭の人が、組の進み具合を見る（みんながつかんだか・次の点・頂上で向きを変える）
func _team_lead(t: Dictionary, dt: float) -> void:
	var s: RigidBody3D = t.sled
	if not t.go:
		var held := 0
		for m in t.members:
			if m.handle != Vector3.INF:
				held += 1
		var coming := false
		for m in t.members:
			coming = coming or (m.handle == Vector3.INF and m._lost_t < 3.0)
		if held > 0:   # まだ歩いて来ている仲間がいれば、長めに待つ（押し始めると追いつけない）
			t.hold_t += dt * (0.25 if coming else 1.0)
		t.go = held == t.members.size() or t.hold_t > TEAM_WAIT
		return
	var at := Vector2(s.global_position.x, s.global_position.z)
	if not t.route.is_empty():
		var w: Vector2 = t.route[0]
		var gap := at.distance_to(w)
		t.stall += dt
		if gap < t.best - 0.5:
			t.best = gap
			t.stall = 0.0
		if gap < 5.0:
			t.route.pop_front()
			t.best = INF
			t.stall = 0.0
		elif t.stall > TEAM_STALL:
			t.route.clear()   # 押しても上がらない: ここから滑る
		return
	t.turn_t += dt
	var fwd := Emotes._flat(-s.global_basis.z).normalized()
	var want := Vector3(t.goal.x - at.x, 0, t.goal.y - at.y).normalized()
	if fwd.dot(want) > 0.92 or t.turn_t > TEAM_TURN:
		t.turned = true


## 頂上で向きが変わった: つかんでいた手を離して、みんなで乗る
func _team_board(t: Dictionary, dt: float) -> void:
	var s: RigidBody3D = t.sled
	let_go()
	if global_position.distance_to(s.global_position) > 4.5:
		_leave_team()
		_settle_walk(Vector3.ZERO, dt)
		return
	seat = s.mount(self)
	if seat == Vector3.INF:
		_leave_team()
		_settle_walk(Vector3.ZERO, dt)
		return
	_col.disabled = true
	state = State.RIDE
	_team_cool = randf_range(TEAM_COOL.x, TEAM_COOL.y)
	_ride_goal = t.goal
	_ride_t = 0.0
	_still = 0.0
	_goal_best = INF
	_goal_t = 0.0
	_team = {}
	global_position = s.to_global(seat)
	_pose_doll()


# ---------------------------------------------------------------- ソリを買う

## 次の山を選ぶ前に: ボタンがたまっていて自分のソリがなければ、買いに行く
func _try_errand() -> bool:
	var w := get_parent()
	if is_instance_valid(own_sled) or w.get("shopkeeper") == null or w.get("sewing") == null:
		return false
	if craft.wallet(id) < craft.PATTERN_PRICE[SLED_KIND] + craft.FABRIC_PRICE:
		return false
	var n := 0
	for b in get_tree().get_nodes_in_group("bots"):
		if b != self and (is_instance_valid(b.own_sled) or b._errand != ""):
			n += 1
	if n >= CPU_SLEDS:
		return false
	var at: Vector3 = w.shopkeeper.to_global(Vector3(0, 0, -1.9))
	_errand = "shop"
	_area = "errand"
	_route = [Vector2(at.x, at.z)]
	_wp_best = INF
	_wp_t = 0.0
	return true


## 用事の所に着いた: 店で型紙と布を買う → ミシンへ → 縫う → 縫い上がったら終わり（人と同じ出来事。ソリは縫った人のもの）
func _errand_step(dt: float) -> void:
	var w := get_parent()
	match _errand:
		"shop":
			var fabric: String = preload("res://fabrics.gd").ORDER[id % preload("res://fabrics.gd").ORDER.size()]
			if not craft.send({"kind": "buy", "who": id, "item": {"kind": "pattern", "sled": SLED_KIND}}) \
					or not craft.send({"kind": "buy", "who": id, "item": {"kind": "fabric", "fabric": fabric}}):
				_errand_end()
				return
			hub.send({"kind": "un", "who": id})
			var at: Vector3 = w.sewing.machine.to_global(w.sewing.get("_mark")["stand"])
			_errand = "sew"
			_errand_t = 30.0
			_route = [Vector2(at.x, at.z)]
			_wp_best = INF
			_wp_t = 0.0
		"sew":
			_errand_t -= dt
			if _errand_t <= 0.0:
				_errand_end()
			elif w.sewing.can_sew() and _sew():
				_errand = "sewing"
				_errand_t = 30.0
			return
		"sewing":
			_errand_t -= dt
			if is_instance_valid(own_sled) or _errand_t <= 0.0:
				_errand_end()


## 持ち物の型紙と布を 1 つずつ使って縫い始める
func _sew() -> bool:
	var bag: Array = craft.bags.get(id, [])
	var ps := -1
	var fs := -1
	for i in bag.size():
		if bag[i].get("kind") == "pattern" and ps < 0:
			ps = i
		elif bag[i].get("kind") == "fabric" and fs < 0:
			fs = i
	if ps < 0 or fs < 0:
		return false
	return craft.send({"kind": "sew", "who": id, "pattern": bag[ps].duplicate(), "fabric": bag[fs].duplicate(), "pattern_slot": ps, "fabric_slot": fs})


func _errand_end() -> void:
	_errand = ""
	_roam_done()


# ---------------------------------------------------------------- ロッジでくつろぐ

func _on_seat(ev: Dictionary) -> void:
	if ev.get("who", -1) != id:
		return
	match ev.kind:
		"sit":
			seat_i = int(ev.seat)
			_sit_frame = int(ev.frame)
			_stand_frame = -1
			_sit_from = global_position
			_sit_stage = 0
			_col.disabled = true
			velocity = Vector3.ZERO
			_goal = -1
			_rest = randf_range(REST.x, REST.y)
		"stand":
			_stand_frame = int(ev.frame)
			_left = seat_i


## 遊んでいる人が座っている席（何人か座っていれば、いちばん近くの人の席。座っていなければ空）
func _player_seat() -> Dictionary:
	if seats == null:
		return {}
	var best := {}
	var near := INF
	for h in _humans():
		var i := int(seats.seat_of.get(int(h.get("id")), -1))
		var d: float = global_position.distance_squared_to(h.global_position)
		if i >= 0 and d < near:
			near = d
			best = seats.seat(i)
	return best


func _lounge(dt: float) -> void:
	if seats == null or seats.seats.is_empty():
		_pose_lounge()
		return
	var mine: Dictionary = _player_seat()
	if seat_i >= 0:
		var st: Dictionary = seats.seat(seat_i)
		var pl: Array = Seats.place(st, _sit_from, Doll.frame_index(), _sit_frame, _stand_frame)
		_sit_stage = pl[1]
		if pl[2]:
			seat_i = -1
			_sit_stage = 0
			_col.disabled = false
			global_position = pl[0] + Vector3.UP * 0.05
			_rest = randf_range(0.5, 2.0)
		else:
			global_position = pl[0]
			# あなたが近くに座ったら、長く座っている。遠くに座ったら、少しして寄っていく
			var near: bool = not mine.is_empty() and (mine.pos as Vector3).distance_to(st.pos) < NEAR_SEAT
			if not mine.is_empty() and not near and not _near_was:
				_rest = minf(_rest, randf_range(2.0, 6.0))
			_near_was = not mine.is_empty()
			_rest -= dt
			if _rest <= 0.0 and _stand_frame < 0 and _sit_stage == 2:
				if near:
					_rest = randf_range(REST.x, REST.y)
				else:
					seats.send({"kind": "stand", "who": id, "seat": seat_i})
		_pose_lounge()
		return
	# 立っている: 次の席を選んで歩いて行く
	if _goal < 0:
		_rest -= dt
		if _rest > 0.0:
			_pose_lounge()
			return
		_goal = _pick_seat(mine)
		_near_d = INF
		_near_t = 0.0
		_via = []
		if _goal >= 0 and seats.seat(_goal).kind in HEARTH_SEATS:
			var st: Dictionary = seats.seat(_goal)
			var d: Vector3 = st.stand - global_position
			d.y = 0
			var nook = seats.lodge.find_child("HearthNook", true, false) if seats.lodge else null
			if nook and test_move(global_transform, d):   # まっすぐ行けなければ、入り口を通る
				_via = nook.route(global_position, st.stand)
		_stuck = 0.0
		if _goal < 0:
			_rest = 2.0
			_pose_lounge()
			return
		if not _started:
			# 始まり: 選んだ席のそばから、すぐ座る
			_started = true
			global_position = seats.seat(_goal).stand + Vector3.UP * 0.05
	var goal: Dictionary = seats.seat(_goal)
	if seats.taken.has(_goal):
		_goal = -1   # 先に座られた
		_pose_lounge()
		return
	var to: Vector3 = goal.stand - global_position
	to.y = 0
	if not _via.is_empty():   # 暖炉の居場所の入り口を通って回り込む途中（hearth_nook.gd の route）
		var w: Vector3 = _via[0] - global_position
		w.y = 0
		if w.length() < 0.5:
			_via.pop_front()
			_near_d = INF
		else:
			to = w
	if to.length() < 0.3 and _via.is_empty():
		if not seats.send({"kind": "sit", "who": id, "seat": _goal}):
			_goal = -1
		_pose_lounge()
		return
	var dir := _detour(to.normalized())
	var before := global_position
	velocity.x = dir.x * SPEED * 0.7 * damp_k(false)
	velocity.z = dir.z * SPEED * 0.7 * damp_k(false)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	look_at(global_position + dir, Vector3.UP)
	# 机などに当たって進めなければ、別の席にする
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_stuck = _stuck + dt if moved < SPEED * 0.2 * dt else maxf(0.0, _stuck - dt)
	# 家具のあいだで左右に振れて近づけないときも（動いてはいる）、4 秒で 0.5 m 近づけなければ別の席にする
	_near_t += dt
	if to.length() < _near_d - 0.5:
		_near_d = to.length()
		_near_t = 0.0
	if _near_t > 4.0:
		_stuck = 2.0
	if _stuck > 1.5:
		_near_d = INF
		_near_t = 0.0
		_left = _goal
		_goal = -1
	_pose_lounge()


var _started := false
var _via := []               # 席へ行く前に通る所（世界）
var _near_d := INF           # 行き先の席の立つ所に、いちばん近づいた距離
var _near_t := 0.0           # そこから近づけないでいる秒
var _turn_sign := 1.0        # 机をよけて回り込む向き（ふさがれているあいだは同じ向きへ回り続ける）


## 行きたい向き want の前がふさがっていれば（机など）、少しずつ向きを振って通れる向きを選ぶ。
## 前に選んだ回り込みの向きを先に試すので、机の縁に沿って端まで回り込める
func _detour(want: Vector3) -> Vector3:
	var at := global_transform
	if not test_move(at, want * 0.35):
		return want
	for a in [0.6, 1.1, 1.6, 2.2]:
		for sg in [_turn_sign, -_turn_sign]:
			var d := want.rotated(Vector3.UP, a * sg)
			if not test_move(at, d * 0.35):
				_turn_sign = sg
				return d
	return want


## 次に座る席: あなたが座っていれば、そのそばの空いた席。でなければ、近くの空いた席から気まぐれに
func _pick_seat(mine: Dictionary) -> int:
	var list: Array = []
	if not mine.is_empty():
		list = seats.free_near(mine.stand, 4, NEAR_SEAT).filter(func(i): return i != _left)
	if list.is_empty() and randf() < HEARTH_LIKE:   # 暖炉のまわりの家具（ソファ・揺り椅子・ビーズクッション）が好き
		list = seats.free_near(global_position, 8, 40.0, HEARTH_SEATS).filter(func(i): return i != _left)
	if list.is_empty():
		list = seats.free_near(global_position, 8, 14.0).filter(func(i): return i != _left and seats.seat(i).kind != "zabuton")
	return list[randi() % list.size()] if not list.is_empty() else -1


func _pose_lounge() -> void:
	_pose_doll()
	doll.airborne = false
	doll.facing = Vector3.ZERO
	doll.seat_soft = seat_i >= 0 and seats.seat(seat_i).kind == "zabuton"
	doll.rock_axis = Vector3.ZERO
	if seat_i >= 0:
		var st: Dictionary = seats.seat(seat_i)
		doll.act = Doll.Act.SIT
		doll.facing = st.face
		doll.sit_stage = _sit_stage
		doll.seat_drop = st.pos.y - st.floor
		doll.seat_edge = st.edge
		if st.has("rock_axis"):   # 揺り椅子・ビーズクッション: 体ごと傾く
			doll.rock_axis = st.rock_axis
			doll.rock_at = st.rock_at
			doll.rock_roll = float(st.get("rock_roll", 0.0))
			doll.rock = Seats.rock_of(st, Doll.frame_index(), _sit_frame, _stand_frame)
