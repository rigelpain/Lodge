extends Node

const Doll := preload("res://doll.gd")
const Emotes := preload("res://emotes.gd")
const Temp := preload("res://temperature.gd")
const Audio := preload("res://audio.gd")
const Food := preload("res://food.gd")
## 紙の人形の湿り気（「よれ」のゲージ）の配り役。人ごとに 1 本の値を持つ: 0 びしょびしょ（下端・水）〜 200 パリパリ（上端・炎）。
## 境目は 150: 150 〜 200 は暖炉で乾かしたブーストタイム、150 より下は水の側。ふつうの幅を長く取り、湿っても
## すぐには弱らない（水の猶予）。2026-11-01 代表「境目は 150 くらいにして、150〜200 がブーストタイムだと思ってもらえる感じに」。
## 外の雪で湿り（雪玉・引きずられる・雪煙・転ぶで大きく）、ロッジの中で乾き、暖炉や乾燥機のそばでブーストまで上がる。
## 値は 4 つの段に分け、段ごとに歩く速さ・押す力・姿勢のコマの間隔を変える（下の STAGES。表は design/damp.md）。
## 見た目は段でなく値のまま（doll.gd の damp に毎フレーム入れる。濡れの色・シミ・垂れ・うなだれ、パリッとした張り）。
## HUD のバッジ（押す力・速さの上がり下がり）は badges.gd に入れる（ご飯の効き目など、ほかの仕組みも同じ所に入れる）。
## ご飯を食べると、湿り気がじんわり戻る（eat。料理ごとの量は food.gd の DRY。ふつうの上の端 150 まで、
## 熱い汁物だけはブーストまで。food.gd の dry_cap）。2026-11-01 代表「ごはんで湿り気ゲージをかいふくできるようにしてほしい」。
## 戻るのを待っているあいだは、ゲージにしつけ糸（行き先）を縫い、ご飯のバッジを出す。
##
## 通信（net.gd）: 人の値は、その人の画面が決める（自分の場所・動き・食べたことを知っているのはその画面なので）。
## 値は姿といっしょに送り（net.gd の _my_state の "dv"）、ほかの画面ではその人の体（remote_person.gd）が apply_net で入れる。
## その人の体は damp_from_net を持ち、ここでは値を動かさない。ソリはホストの物理が動かすので、ホストの画面の
## その人の体が、届いた値の押す力で押す。

signal sent(ev: Dictionary)     # 値が動いた出来事 {kind: "damp", who, v}（値は整数）。通信は net.gd が姿といっしょに送るので、いまは聞く人がいない

## 段: [値の下限, 名前, 歩く速さ, 押す力, 姿勢のコマの間隔（12 fps のコマいくつに 1 回）, バッジの向き（-1 下がる・1 上がる）, 矢印の数]
const STAGES := [
	[0.0, "びしょびしょ", 0.80, 0.70, 1.5, -1, 2],
	[40.0, "しっとり", 0.90, 0.85, 1.2, -1, 1],
	[90.0, "ふつう", 1.0, 1.0, 1.0, 0, 0],
	[150.0, "ブースト", 1.15, 1.25, 1.0, 1, 1],
]
const LO := 0.0
const HI := 200.0
const MID := 100.0               # ゲージのまんなか。見た目の湿りはここから下で出る
const BOOST := 150.0             # 境目。ここから上がブーストタイム
const START := 120.0             # 始めの値（ふつう）

# 湿る（1 秒あたり、または 1 回あたり）
const AIR_FLOOR := 70.0        # 外にいるだけで、ここまではじわじわ湿る（舞う雪と湿った空気。しっとりの段）
const AIR_DAMP := 0.10         # その速さ（150 から 90 まで 10 分）
const BOOST_FADE := 0.30       # 外では、ブーストがこの速さで抜ける（200 から 150 まで 3 分ほど）
const MOVE_DAMP := 0.12        # 雪の上を歩く（雪を蹴る）
const WORK_DAMP := 0.25        # ソリを押す・紐を引く（雪に膝をつき、体を雪に寄せる）
const DRAG_DAMP := 3.0         # ソリに引きずられる（雪の上を滑らされる）
const SPRAY_DAMP := 0.05       # 乗って滑ると、雪煙をかぶる（速さ 1 m/s あたり。10 m/s で 0.5）
const SACK_SPRAY := 2.0        # 米袋は雪の上にじかに座るので、雪煙をたくさんかぶる（倍）
const HIT_DAMP := 12.0         # 雪玉が当たる（1 回）
const BALL_DAMP := 4.0         # 雪玉を丸める（素手で雪をつかむ。1 回）
const FALL_DAMP := 10.0        # 高い所から落ちて雪に突っ込む（転ぶ。1 回）
const FALL_SPEED := 6.0        # 着いたときの下向きの速さがこれより速いと、転ぶ (m/s。ふつうのジャンプは 4.5)

# 乾く
const ROOM_CAP := 110.0        # ロッジの中（暖炉から離れた所）で乾くのは、ここまで（ふつう）
const DRY_ROOM := 0.8          # ロッジの中で乾く速さ（0 から 110 まで 2 分半）
const DRY_FIRE := 7.0          # 暖炉のすぐそばで足す速さ（すぐそばなら 0 から 200 まで 25 秒ほど。暖炉の前 1.5 m で 35 秒ほど）
const BOOST_FROM := 0.15       # 暖かさ（0 〜 1。暖炉からの近さ）がこれを超えると、ROOM_CAP より上へ上がる
const BOOST_FULL := 0.6        # ここで 200 まで上がる（暖炉から 2 m）
const DRYER_AT := Vector3(5.5, 0.0, -0.2)   # 乾燥機の真ん中（厨房の目印 slot_food_kitchen の座標。props/sets/kitchen.tscn の当たりの箱 box_2）
const DRYER_R := 2.6           # 乾燥機の真ん中から、これより近い（前に立つ）と暖炉と同じように乾く (m、水平。乾燥機は 2.7 m 角)
const DRYER_HEAT := 0.8        # 乾燥機の前の暖かさ（暖炉のすぐそばを 1 として）

# ご飯で戻す
const FOOD_DRY := 5.0          # 戻る速さ（1 秒に。熱い汁物 1 杯 75 で 15 秒ほど）

const SEND_STEP := 2.0         # 値がこれだけ変わるか、段が変わったら配る
const SEND_GAP := 0.25         # 配るのは多くても 1 秒に 4 回

var hub: Emotes                # 身ぶりの配り役（人の番号と、雪玉が当たった出来事）
var badges: Node               # badges.gd（あれば押す力・速さのバッジを入れる）
var authority := true          # 値を決める（ホスト）。false ならほかの人の画面: apply_net で受けるだけ
var values := {}               # 番号 → 値（0 〜 200）
var pending := {}              # 番号 → ご飯でこれから戻る量
var _pending_cap := {}         # 番号 → それがどこまで戻るか（food.gd の dry_cap。重ねて食べたら高いほう）
var _fall := {}                # 番号 → 前のフレームの下向きの速さ（空中にいるあいだ）
var _sent := {}                # 番号 → [最後に配った値, 時刻]
var _dryer: Node3D
var _looked := -100000


func _ready() -> void:
	if hub:
		hub.happened.connect(_on_emote)


## 段の番号（STAGES の添え字。0 びしょびしょ 〜 2 ふつう 〜 3 ブースト）
static func stage_of(v: float) -> int:
	var s := 0
	for i in STAGES.size():
		if v >= STAGES[i][0]:
			s = i
	return s


static func speed_of(v: float) -> float:
	return STAGES[stage_of(v)][2]


static func push_of(v: float) -> float:
	return STAGES[stage_of(v)][3]


static func pose_step_of(v: float) -> float:
	return STAGES[stage_of(v)][4]


## 人形の見た目の湿り気（-1 びしょびしょ 〜 0 ふつう 〜 1 パリパリ）。湿りはまんなか（100）から下で濃くなり、
## 張りはふつうの上のほう（125）から出はじめ、ブーストの中で強くなる
static func look_of(v: float) -> float:
	if v < MID:
		return (v - MID) / (MID - LO)
	return clampf((v - 125.0) / (HI - 125.0), 0.0, 1.0)


func value(id: int) -> float:
	return values.get(id, START)


## 歩く速さ・押す力に掛ける倍率（持ち主が引く）
func speed_k(id: int) -> float:
	return speed_of(value(id))


func push_k(id: int) -> float:
	return push_of(value(id))


## 足す（正で乾く・パリッと、負で湿る）。値を決める画面だけ（通信の相手の値は、その人の画面が決める）
func add(id: int, amount: float) -> void:
	if not authority or _from_net(id):
		return
	values[id] = clampf(value(id) + amount, LO, HI)


## ひと口食べた（player.gd が craft.gd の bite のあとに呼ぶ）。料理の DRY の 1/BITES を、これから戻る量に足す。
## 戻るのは料理の dry_cap まで（もうそこより上なら戻さない）
func eat(id: int, dish: String) -> void:
	if not authority or _from_net(id):
		return
	var cap := Food.dry_cap(dish)
	if coming(id) > 0.0:
		cap = maxf(cap, _pending_cap.get(id, cap))
	_pending_cap[id] = cap
	pending[id] = minf(coming(id) + Food.dry(dish) / Food.BITES, maxf(0.0, cap - value(id)))


## これから戻る量（HUD のしつけ糸）
func coming(id: int) -> float:
	return float(pending.get(id, 0.0))


func _from_net(id: int) -> bool:
	var who = hub.people.get(id) if hub else null
	return who != null and is_instance_valid(who) and who.get("damp_from_net") == true


## 確かめ用: 値をそのまま入れる
func put(id: int, v: float) -> void:
	values[id] = clampf(v, LO, HI)
	_publish(id, true)


## 通信で受けた出来事（{kind: "damp", who, v}）
func apply_net(ev: Dictionary) -> void:
	if ev.get("kind", "") == "damp":
		values[int(ev.who)] = clampf(float(ev.v), LO, HI)


func _on_emote(ev: Dictionary) -> void:
	if not authority:
		return
	match ev.kind:
		"hit":
			add(ev.who, -HIT_DAMP)
		"make_ball":
			add(ev.who, -BALL_DAMP)


func _physics_process(dt: float) -> void:
	if hub == null:
		return
	for id in hub.people:
		var who: Node3D = hub.people[id]
		if who == null or not is_instance_valid(who):
			continue
		# 一人プレイの仲間（bot.gd）は湿らない。通信の相手（remote_person.gd）の値は、その人の画面から届く
		if authority and not who.get("stays_dry") and not who.get("damp_from_net"):
			values[id] = clampf(value(id) + _rate(id, who, dt) + _digest(id, dt), LO, HI)
		var d: Doll = who.get("doll")
		if d and is_instance_valid(d):
			d.damp = look_of(value(id))
			d.pose_step = pose_step_of(value(id))
		_publish(id, false)


## ご飯で戻る分（1 フレーム）。行き先（dry_cap）に着いたら、残りは捨てる
func _digest(id: int, dt: float) -> float:
	var p: float = pending.get(id, 0.0)
	if p <= 0.0:
		return 0.0
	var cap: float = _pending_cap.get(id, HI)
	var dv := minf(minf(FOOD_DRY * dt, p), maxf(0.0, cap - value(id)))
	pending[id] = p - dv if value(id) + dv < cap - 0.01 else 0.0
	return dv


## いまの場所と動きから、1 フレームの増減
func _rate(id: int, who: Node3D, dt: float) -> float:
	var v := value(id)
	# 中か外かは、音の屋内の判定（audio.gd の zone_at: 0 外・1 風除室・2 中）。暖かさは気温（temperature.gd）から
	var temp := get_node_or_null("/root/Temperature")
	var at := who.global_position + Vector3.UP
	var zone := Audio.zone_at(temp._find_lodge(), at) if temp else 0
	var d: Doll = who.get("doll")
	var dv := 0.0
	if zone == 2:
		# ロッジの中: ふつう（ROOM_CAP）まで乾く。暖炉（気温の上がり分）や乾燥機のそばでは速く乾き、ブーストまで上がる。
		# 中ではブーストは抜けない（乾いた空気）
		var heat := clampf((temp.at(at) - Temp.INDOOR) / Temp.FIRE_WARM, 0.0, 1.0)
		var dryer := _find_dryer()
		var off := who.global_position - dryer.to_global(DRYER_AT) if dryer else Vector3.INF
		if dryer and Vector2(off.x, off.z).length() < DRYER_R:
			heat = maxf(heat, DRYER_HEAT)
		var cap := lerpf(ROOM_CAP, HI, smoothstep(BOOST_FROM, BOOST_FULL, heat))
		if v < cap:
			dv = minf((DRY_ROOM + DRY_FIRE * heat) * dt, cap - v)
	elif zone == 0:
		# 外: ブーストが抜け、じわじわ湿る。動くと雪で湿る
		if v > BOOST:
			dv -= BOOST_FADE * dt
		elif v > AIR_FLOOR:
			dv -= AIR_DAMP * dt
		if d:
			if d.act == Doll.Act.RIDE and d.sled and is_instance_valid(d.sled):
				var sp: float = (d.sled as RigidBody3D).linear_velocity.length()
				dv -= SPRAY_DAMP * sp * (SACK_SPRAY if d.sled.get("kind") == "sack" else 1.0) * dt
			elif d.dragged:
				dv -= DRAG_DAMP * dt
			elif d.effort:
				dv -= WORK_DAMP * dt
			elif d._speed > 0.5:
				dv -= MOVE_DAMP * dt
	# 転ぶ: 高い所から落ちて、雪に突っ込む
	var body := who as CharacterBody3D
	if body:
		if not body.is_on_floor():
			_fall[id] = -body.velocity.y
		elif _fall.has(id):
			if _fall[id] > FALL_SPEED and zone == 0:
				dv -= FALL_DAMP
			_fall.erase(id)
	return dv


## 段が変わったか、値が SEND_STEP 動いたら、出来事を配る（通信の量を抑える）。バッジも入れ直す
func _publish(id: int, force: bool) -> void:
	var v := roundf(value(id))
	var last: Array = _sent.get(id, [INF, -100.0])
	var now := Time.get_ticks_msec() / 1000.0
	var moved := absf(v - last[0]) >= SEND_STEP or stage_of(v) != stage_of(last[0] if last[0] != INF else START)
	if force or (moved and now - last[1] >= SEND_GAP):
		_sent[id] = [v, now]
		if authority:
			sent.emit({"kind": "damp", "who": id, "v": int(v)})
	if badges:
		# 押す力と速さのバッジ（段の向きと矢印の数）。ふつうなら出さない
		var st: Array = STAGES[stage_of(value(id))]
		for stat in ["push", "speed"]:
			if st[5] == 0:
				badges.clear(id, "damp_" + stat)
			else:
				badges.put(id, "damp_" + stat, st[5], st[6], stat)
		# ご飯で戻っているあいだは、湯気の立つ椀のバッジ（上がる）
		if coming(id) > 0.5:
			badges.put(id, "food_dry", 1, 1, "bowl")
		else:
			badges.clear(id, "food_dry")


## 厨房の目印（乾燥機は DRYER_AT。なければ null。探すのは 2 秒に一度）
func _find_dryer() -> Node3D:
	if _dryer and is_instance_valid(_dryer):
		return _dryer
	var now := Time.get_ticks_msec()
	if now - _looked < 2000:
		return null
	_looked = now
	_dryer = get_tree().root.find_child("slot_food_kitchen", true, false) as Node3D
	return _dryer
