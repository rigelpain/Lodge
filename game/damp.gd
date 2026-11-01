extends Node

const Doll := preload("res://doll.gd")
const Emotes := preload("res://emotes.gd")
const Temp := preload("res://temperature.gd")
const Audio := preload("res://audio.gd")
const Food := preload("res://food.gd")
## 紙の人形の「水」と「熱」の配り役。人ごとに 2 本の値を持つ（2026-11-01 代表「水ゲージと熱ゲージは別にしようか。
## 水が高まるとデバフがついて、熱が高まるとバフが付く感じ。それは相殺するから±でどっちになってるかがバフ・デバフアイコンとして
## 出てきてほしい。水 MAX と熱 MAX だと熱のほうが強い」）。表は design/damp.md。
##   水 water  0 乾いている 〜 100 びしょびしょ。外の雪で増え（雪玉・引きずられる・雪煙・転ぶで大きく）、ロッジの中で減る。
##             暖炉や乾燥機のそばでは速く減る
##   熱 heat   0 凍える（氷）〜 50 ふつう 〜 100 ほかほか（炎）。外の寒さで 50 より下がり（夜・高い所ほど、濡れているほど速く）、
##             ロッジの中で 50 に戻り、暖炉・乾燥機・温かいご飯で 50 より上がる
## 効き目は 2 本を差し引いた 1 つの点（score）で決める: 熱の側 1.5 ×（熱 − 50）/ 50 から、水の側 水 / 100 を引く。
## 熱の側は 50 より上だけが効く（凍えても、それだけではデバフにしない。2026-11-01 代表「ゼロ扱い」）。
## 熱の重みが大きいので、水も熱も MAX なら +0.5 でバフ寄り。点を 4 つの段に分け、段ごとに歩く速さ・押す力・姿勢のコマの間隔を変え、
## 押す力と速さのバッジ（上がる・下がる）を出す（STAGES）。
## 熱が低いほど、外でふるえる（doll.gd の warm。前の「ぬくもり」warmth.gd と湯たんぽの絵は、熱のゲージにまとめた。2026-11-01 代表）。
## 見た目は段でなく値のまま（doll.gd の damp に毎フレーム入れる。水で濡れの色・シミ・垂れ・うなだれ、熱でパリッとした張り）。
## ご飯を食べると、熱がじんわり上がる（eat。料理ごとの量は food.gd の HEAT。温かい物はふつうの少し上まで、
## 熱い汁物だけはいちばん上まで。food.gd の heat_cap）。上がるのを待っているあいだは、熱のゲージにしつけ糸（行き先）を縫い、
## ご飯のバッジを出す。
##
## 通信（net.gd）: 人の値は、その人の画面が決める（自分の場所・動き・食べたことを知っているのはその画面なので）。
## 値は姿といっしょに送り（net.gd の _my_state の "dw"・"dh"）、ほかの画面ではその人の体（remote_person.gd）が apply_net で入れる。
## その人の体は damp_from_net を持ち、ここでは値を動かさない。ソリはホストの物理が動かすので、ホストの画面の
## その人の体が、届いた値の押す力で押す。ホストは自分と仲間の値も sent で配る（main.gd）

signal sent(ev: Dictionary)     # 値が動いた出来事 {kind: "damp", who, w, h}（値は整数）

## 段: [点の下限, 名前, 歩く速さ, 押す力, 姿勢のコマの間隔（12 fps のコマいくつに 1 回）, バッジの向き（-1 下がる・1 上がる）, 矢印の数]
const STAGES := [
	[-INF, "よれよれ", 0.80, 0.70, 1.5, -1, 2],
	[-0.75, "しんなり", 0.90, 0.85, 1.2, -1, 1],
	[-0.35, "ふつう", 1.0, 1.0, 1.0, 0, 0],
	[0.35, "パリッと", 1.15, 1.25, 1.0, 1, 1],
]
const HEAT_W := 1.5             # 熱の側の重み（水の側は 1）。水も熱も MAX なら熱が勝つ
const HEAT_MID := 50.0          # 熱のふつう（ロッジの中）
const START_WATER := 0.0
const START_HEAT := 50.0
const SHIVER_CUT := 0.85        # 熱が高いと、外のふるえをいちばんこれだけ弱める
const SHIVER_HEAT := Vector2(42.0, 65.0)   # 熱がこのあいだで、ふるえを弱めはじめ、いちばん弱める（ふもとの昼の行き先 41 ではふつうにふるえる）

# 水が増える（1 秒あたり、または 1 回あたり）
const AIR_FLOOR := 35.0        # 外にいるだけで、ここまではじわじわ湿る（舞う雪と湿った空気）
const AIR_WET := 0.07          # その速さ（0 から 35 まで 8 分ほど）
const MOVE_WET := 0.08         # 雪の上を歩く（雪を蹴る）
const WORK_WET := 0.17         # ソリを押す・紐を引く（雪に膝をつき、体を雪に寄せる）
const DRAG_WET := 2.0          # ソリに引きずられる（雪の上を滑らされる）
const SPRAY_WET := 0.033       # 乗って滑ると、雪煙をかぶる（速さ 1 m/s あたり）
const SACK_SPRAY := 2.0        # 米袋は雪の上にじかに座るので、雪煙をたくさんかぶる（倍）
const HIT_WET := 8.0           # 雪玉が当たる（1 回）
const BALL_WET := 3.0          # 雪玉を丸める（素手で雪をつかむ。1 回）
const FALL_WET := 7.0          # 高い所から落ちて雪に突っ込む（転ぶ。1 回）
const FALL_SPEED := 6.0        # 着いたときの下向きの速さがこれより速いと、転ぶ (m/s。ふつうのジャンプは 4.5)

# 水が減る
const DRY_ROOM := 0.55         # ロッジの中で乾く速さ（100 から 0 まで 3 分）
const DRY_FIRE := 4.7          # 暖炉のすぐそばで足す速さ（すぐそばなら 100 から 0 まで 20 秒ほど）
const DRY_HOT := 0.006         # 外でも、熱が 50 より上なら少しずつ乾く（熱 100 で 0.3 / 秒）

# 熱
const COLD_C := 1.5            # 外の熱の行き先: 50 ＋ 1.5 ×（気温 − 4 °C）。ふもとの昼 −2 °C で 41、明け方 −11 °C で 27、頂上の夜で 21
const COLD_LO := 15.0          # 外の熱の行き先の下限
const HOT_FADE := 0.28         # 外では、50 より上の熱がこの速さで抜ける（100 から 50 まで 3 分ほど）
const COOL := 0.05             # 外で、50 から行き先まで下がる速さ（50 から 41 まで 3 分）。行き先より低ければ同じ速さで戻る
const WET_CHILL := 1.0         # 濡れていると外で早く冷える: 下がる速さ ×（1 ＋ 1.0 × 水 / 100）
const ROOM_WARM := 0.5         # ロッジの中で、50 まで戻る速さ
const FIRE_HEAT := 3.0         # 暖炉のすぐそばで、熱が上がる速さ（すぐそばなら 50 から 100 まで 17 秒ほど）
const BOOST_FROM := 0.15       # 暖かさ（0 〜 1。暖炉からの近さ）がこれを超えると、熱が 50 より上へ上がる
const BOOST_FULL := 0.6        # ここで 100 まで上がる（暖炉から 2 m）
const DRYER_AT := Vector3(5.5, 0.0, -0.2)   # 乾燥機の真ん中（厨房の目印 slot_food_kitchen の座標。props/sets/kitchen.tscn の当たりの箱 box_2）
const DRYER_R := 2.6           # 乾燥機の真ん中から、これより近い（前に立つ）と暖炉と同じように乾く (m、水平。乾燥機は 2.7 m 角)
const DRYER_HEAT := 0.8        # 乾燥機の前の暖かさ（暖炉のすぐそばを 1 として）

# ご飯で上がる
const FOOD_HEAT := 2.5         # 上がる速さ（1 秒に。熱い汁物 1 杯 35 で 14 秒ほど）

const SEND_STEP := 2.0         # 値がこれだけ変わるか、段が変わったら配る
const SEND_GAP := 0.25         # 配るのは多くても 1 秒に 4 回

var hub: Emotes                # 身ぶりの配り役（人の番号と、雪玉が当たった出来事）
var badges: Node               # badges.gd（あれば押す力・速さのバッジを入れる）
var authority := true          # 値を決める。false なら受けるだけ（確かめの道具が値を止めるとき）
var water := {}                # 番号 → 水（0 〜 100）
var heat := {}                 # 番号 → 熱（0 〜 100）
var pending := {}              # 番号 → ご飯でこれから上がる熱
var _pending_cap := {}         # 番号 → それがどこまで上がるか（food.gd の heat_cap。重ねて食べたら高いほう）
var _fall := {}                # 番号 → 前のフレームの下向きの速さ（空中にいるあいだ）
var _sent := {}                # 番号 → [最後に配った水, 熱, 時刻]
var _dryer: Node3D
var _looked := -100000


func _ready() -> void:
	if hub:
		hub.happened.connect(_on_emote)


## 水と熱を差し引いた点（-1 〜 +1.5。0 がふつう）。熱は 50 より上だけ
static func score_of(w: float, h: float) -> float:
	return HEAT_W * maxf(0.0, h - HEAT_MID) / HEAT_MID - w / 100.0


## 段の番号（STAGES の添え字。0 よれよれ 〜 2 ふつう 〜 3 パリッと）
static func stage_of(s: float) -> int:
	var st := 0
	for i in STAGES.size():
		if s >= STAGES[i][0]:
			st = i
	return st


static func speed_of(s: float) -> float:
	return STAGES[stage_of(s)][2]


static func push_of(s: float) -> float:
	return STAGES[stage_of(s)][3]


static func pose_step_of(s: float) -> float:
	return STAGES[stage_of(s)][4]


## 人形の見た目（-1 びしょびしょ 〜 0 ふつう 〜 1 パリパリ）。湿りは水のまま。張りは熱が 60 から出はじめ 100 でいっぱい。
## 濡れているほど、張りは出にくい
static func look_of(w: float, h: float) -> float:
	var wet := clampf(w / 100.0, 0.0, 1.0)
	var crisp := clampf((h - 60.0) / 40.0, 0.0, 1.0)
	return -wet + crisp * (1.0 - wet)


func water_of(id: int) -> float:
	return water.get(id, START_WATER)


func heat_of(id: int) -> float:
	return heat.get(id, START_HEAT)


func score(id: int) -> float:
	return score_of(water_of(id), heat_of(id))


## 歩く速さ・押す力に掛ける倍率（持ち主が引く）
func speed_k(id: int) -> float:
	return speed_of(score(id))


func push_k(id: int) -> float:
	return push_of(score(id))


## 水を足す（正で濡れる、負で乾く）。値を決める画面だけ（通信の相手の値は、その人の画面が決める）
func add_water(id: int, amount: float) -> void:
	if authority and not _from_net(id):
		water[id] = clampf(water_of(id) + amount, 0.0, 100.0)


## 熱を足す（正で温まる、負で冷える）
func add_heat(id: int, amount: float) -> void:
	if authority and not _from_net(id):
		heat[id] = clampf(heat_of(id) + amount, 0.0, 100.0)


## ひと口食べた（player.gd が craft.gd の bite のあとに呼ぶ）。料理の HEAT の 1/BITES を、これから上がる熱に足す。
## 上がるのは料理の heat_cap まで（もうそこより上なら上げない）
func eat(id: int, dish: String) -> void:
	if not authority or _from_net(id):
		return
	var cap := Food.heat_cap(dish)
	if coming(id) > 0.0:
		cap = maxf(cap, _pending_cap.get(id, cap))
	_pending_cap[id] = cap
	pending[id] = minf(coming(id) + Food.heat(dish) / Food.BITES, maxf(0.0, cap - heat_of(id)))


## これから上がる熱（HUD のしつけ糸）
func coming(id: int) -> float:
	return float(pending.get(id, 0.0))


func _from_net(id: int) -> bool:
	var who = hub.people.get(id) if hub else null
	return who != null and is_instance_valid(who) and who.get("damp_from_net") == true


## 確かめ用: 値をそのまま入れる
func put(id: int, w: float, h: float) -> void:
	water[id] = clampf(w, 0.0, 100.0)
	heat[id] = clampf(h, 0.0, 100.0)
	_publish(id, true)


## 通信で受けた出来事（{kind: "damp", who, w, h}）
func apply_net(ev: Dictionary) -> void:
	if ev.get("kind", "") == "damp":
		var id := int(ev.who)
		water[id] = clampf(float(ev.get("w", water_of(id))), 0.0, 100.0)
		heat[id] = clampf(float(ev.get("h", heat_of(id))), 0.0, 100.0)


## 入ってきた人に渡す、みんなの値（net.gd）
func snapshot() -> Dictionary:
	return {"w": water.duplicate(), "h": heat.duplicate()}


func load_snapshot(s: Dictionary) -> void:
	water.merge(s.get("w", {}), true)
	heat.merge(s.get("h", {}), true)


func _on_emote(ev: Dictionary) -> void:
	if not authority:
		return
	match ev.kind:
		"hit":
			add_water(ev.who, HIT_WET)
		"make_ball":
			add_water(ev.who, BALL_WET)


func _physics_process(dt: float) -> void:
	if hub == null:
		return
	for id in hub.people:
		var who: Node3D = hub.people[id]
		if who == null or not is_instance_valid(who):
			continue
		# 一人プレイの仲間（bot.gd）は湿らない・冷えない。通信の相手（remote_person.gd）の値は、その人の画面から届く
		if authority and not who.get("stays_dry") and not who.get("damp_from_net"):
			_step(id, who, dt)
		var d: Doll = who.get("doll")
		if d and is_instance_valid(d):
			d.damp = look_of(water_of(id), heat_of(id))
			d.pose_step = pose_step_of(score(id))
			d.warm = SHIVER_CUT * smoothstep(SHIVER_HEAT.x, SHIVER_HEAT.y, heat_of(id))
		_publish(id, false)


## ご飯で上がる熱（1 フレーム）。行き先（heat_cap）に着いたら、残りは捨てる
func _digest(id: int, dt: float) -> float:
	var p: float = pending.get(id, 0.0)
	if p <= 0.0:
		return 0.0
	var cap: float = _pending_cap.get(id, 100.0)
	var dh := minf(minf(FOOD_HEAT * dt, p), maxf(0.0, cap - heat_of(id)))
	pending[id] = p - dh if heat_of(id) + dh < cap - 0.01 else 0.0
	return dh


## いまの場所と動きから、1 フレームぶん水と熱を動かす
func _step(id: int, who: Node3D, dt: float) -> void:
	var w := water_of(id)
	var h := heat_of(id)
	# 中か外かは、音の屋内の判定（audio.gd の zone_at: 0 外・1 風除室・2 中）。暖かさは気温（temperature.gd）から
	var temp := get_node_or_null("/root/Temperature")
	var at := who.global_position + Vector3.UP
	var zone := Audio.zone_at(temp._find_lodge(), at) if temp else 0
	var d: Doll = who.get("doll")
	var dw := 0.0
	var dh := 0.0
	if zone == 2:
		# ロッジの中: 水は乾き、熱は 50 に戻る。暖炉（気温の上がり分）や乾燥機のそばでは速く乾き、熱が 100 まで上がる。
		# 中では 50 より上の熱は抜けない（乾いた空気）
		var warm := clampf((temp.at(at) - Temp.INDOOR) / Temp.FIRE_WARM, 0.0, 1.0)
		var dryer := _find_dryer()
		var off := who.global_position - dryer.to_global(DRYER_AT) if dryer else Vector3.INF
		if dryer and Vector2(off.x, off.z).length() < DRYER_R:
			warm = maxf(warm, DRYER_HEAT)
		dw -= (DRY_ROOM + DRY_FIRE * warm) * dt
		var cap := lerpf(HEAT_MID, 100.0, smoothstep(BOOST_FROM, BOOST_FULL, warm))
		if h < cap:
			dh = minf((ROOM_WARM + FIRE_HEAT * warm) * dt, cap - h)
	elif zone == 0:
		# 外: 熱が抜けて寒さの行き先へ（濡れているほど速く）。じわじわ湿り、動くと雪で湿る。熱が高いと少しずつ乾く
		var chill := 1.0 + WET_CHILL * w / 100.0
		var want := maxf(COLD_LO, HEAT_MID + COLD_C * ((temp.at(at) if temp else -2.0) - 4.0))
		if h > HEAT_MID:
			dh -= HOT_FADE * chill * dt
		elif h > want:
			dh -= minf(COOL * chill * dt, h - want)
		else:
			dh += minf(COOL * dt, want - h)
		if w < AIR_FLOOR:
			dw += minf(AIR_WET * dt, AIR_FLOOR - w)
		if h > HEAT_MID:
			dw -= DRY_HOT * (h - HEAT_MID) * dt
		if d:
			if d.act == Doll.Act.RIDE and d.sled and is_instance_valid(d.sled):
				var sp: float = (d.sled as RigidBody3D).linear_velocity.length()
				dw += SPRAY_WET * sp * (SACK_SPRAY if d.sled.get("kind") == "sack" else 1.0) * dt
			elif d.dragged:
				dw += DRAG_WET * dt
			elif d.effort:
				dw += WORK_WET * dt
			elif d._speed > 0.5:
				dw += MOVE_WET * dt
	# 転ぶ: 高い所から落ちて、雪に突っ込む
	var body := who as CharacterBody3D
	if body:
		if not body.is_on_floor():
			_fall[id] = -body.velocity.y
		elif _fall.has(id):
			if _fall[id] > FALL_SPEED and zone == 0:
				dw += FALL_WET
			_fall.erase(id)
	water[id] = clampf(w + dw, 0.0, 100.0)
	heat[id] = clampf(h + dh + _digest(id, dt), 0.0, 100.0)


## 段が変わったか、値が SEND_STEP 動いたら、出来事を配る（通信の量を抑える）。バッジも入れ直す
func _publish(id: int, force: bool) -> void:
	var w := roundf(water_of(id))
	var h := roundf(heat_of(id))
	var last: Array = _sent.get(id, [INF, INF, -100.0])
	var now := Time.get_ticks_msec() / 1000.0
	var before := stage_of(score_of(last[0], last[1])) if last[0] != INF else -1
	var moved := absf(w - last[0]) >= SEND_STEP or absf(h - last[1]) >= SEND_STEP or stage_of(score(id)) != before
	if force or (moved and now - last[2] >= SEND_GAP):
		_sent[id] = [w, h, now]
		if authority and not _from_net(id):   # 通信の相手の値は、その人の画面が送っている（送り返すと、その人の値を古い値で上書きしてしまう）
			sent.emit({"kind": "damp", "who": id, "w": int(w), "h": int(h)})
	if badges:
		# 押す力と速さのバッジ（水と熱を差し引いた段の向きと矢印の数）。ふつうなら出さない
		var st: Array = STAGES[stage_of(score(id))]
		for stat in ["push", "speed"]:
			if st[5] == 0:
				badges.clear(id, "damp_" + stat)
			else:
				badges.put(id, "damp_" + stat, st[5], st[6], stat)
		# ご飯で熱が上がっているあいだは、湯気の立つ椀のバッジ（上がる）
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
