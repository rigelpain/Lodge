extends Node

const Doll := preload("res://doll.gd")
const Emotes := preload("res://emotes.gd")
const Temp := preload("res://temperature.gd")
const Audio := preload("res://audio.gd")
## 紙の人形の水のゲージの配り役。人ごとに 1 つの値を持つ: 100 びしょびしょ 〜 0 乾いている 〜 −40 パリパリ。
## 2026-11-01 代表「水だけでいいや。暖炉か焚き火で水分ゲージを減らして 0 にして、さらに火にあたっていくとパリッとしてバフになる」。
##   0 より上: 水。外の雪で増え（雪玉・引きずられる・雪煙・転ぶで大きく）、ロッジの中で 0 まで乾く
##   0 より下: 乾きすぎてパリッとした紙。火（暖炉・焚き火）のそばだけで 0 より下へ行き、外では 3 分ほどで 0 に戻る。
##             厨房の乾燥機の中で回っていると、6 秒ほどでいちばんパリッと（−40）まで行く（2026-11-01 代表「一瞬で MAX までいくみたいな。いいじゃん」、
##             そのあと「キャラの乾燥時間を倍にしてほしい」で 2 秒から 4 秒に、2026-11-04 代表の指示で 6 秒に）。
##             乾燥機には手にペレットを持たずに F で入る（2026-11-01 代表。前に立つだけでは乾かない。cook_station.gd）
## 値を 4 つの段に分け、段ごとに歩く速さ・押す力・姿勢のコマの間隔を変え、押す力と速さのバッジ（上がる・下がる）を出す（STAGES）。
## 見た目は段でなく値のまま（doll.gd の damp に毎フレーム入れる。濡れの色・シミ・垂れ・うなだれ、パリッとした張り）。
## ご飯は効かない（雰囲気づくりの道具。2026-11-01 代表「食べ物でのバフはやめよう」）。表は design/damp.md。
## 火は、ロッジの暖炉と、仲間分け "fires" に入った Node3D（焚き火などを置いたら add_to_group("fires")）。
##
## 通信（net.gd）: 人の値は、その人の画面が決める（自分の場所・動きを知っているのはその画面なので）。
## 値は姿といっしょに送り（net.gd の _my_state の "dw"）、ほかの画面ではその人の体（remote_person.gd）が apply_net で入れる。
## その人の体は damp_from_net を持ち、ここでは値を動かさない。ソリはホストの物理が動かすので、ホストの画面の
## その人の体が、届いた値の押す力で押す。ホストは自分と仲間の値も sent で配る（main.gd）

signal sent(ev: Dictionary)     # 値が動いた出来事 {kind: "damp", who, w}（値は整数）

## 段: [値の上限（これ以下）, 名前, 歩く速さ, 押す力, 姿勢のコマの間隔（12 fps のコマいくつに 1 回）, バッジの向き（-1 下がる・1 上がる）, 矢印の数]
const STAGES := [
	[-10.0, "パリッと", 1.15, 1.25, 1.0, 1, 1],
	[35.0, "ふつう", 1.0, 1.0, 1.0, 0, 0],
	[75.0, "しんなり", 0.90, 0.85, 1.2, -1, 1],
	[INF, "よれよれ", 0.80, 0.70, 1.5, -1, 2],
]
const HI := 100.0              # びしょびしょ
const CRISP := -40.0           # いちばんパリパリ
const START := 0.0

# 水が増える（1 秒あたり、または 1 回あたり）
const AIR_FLOOR := 35.0        # 外にいるだけで、ここまではじわじわ湿る（舞う雪と湿った空気。ふつうの上の端）
const AIR_WET := 0.07          # その速さ（0 から 35 まで 8 分ほど）
const MOVE_WET := 0.08         # 雪の上を歩く（雪を蹴る）
const WORK_WET := 0.17         # ソリを押す・紐を引く（雪に膝をつき、体を雪に寄せる）
const DRAG_WET := 2.0          # ソリに引きずられる（雪の上を滑らされる）
const SPRAY_WET := 0.033       # 乗って滑ると、雪煙をかぶる（速さ 1 m/s あたり）
const SACK_SPRAY := 2.0        # 米袋は雪の上にじかに座るので、雪煙をたくさんかぶる（倍）
const HIT_WET := 8.0           # 雪玉が当たる（1 回）
const BALL_WET := 3.0          # 雪玉を丸める（素手で雪をつかむ。1 回）
const FALL_WET := 7.0          # 高い所から落ちて雪に突っ込む（転ぶ。1 回）
const FALL_SPEED := 9.4        # 着いたときの下向きの速さがこれより速いと、転ぶ (m/s。下りの重力 24 で約 1.8 m 落ちた速さ。ふつうのジャンプは 4.5)
const CRISP_FADE := 0.22       # 火から離れると（ロッジの中でも外でも）、パリッとがこの速さで抜けて 0 に戻る（−40 から 0 まで 3 分）

# 乾く
const DRY_ROOM := 0.55         # ロッジの中で 0 まで乾く速さ（100 から 0 まで 3 分）
const DRY_FIRE := 4.7          # 火のすぐそばで足す速さ（すぐそばなら 100 から −40 まで 27 秒ほど）
const FIRE_R := 5.0            # 焚き火の暖かさが届く (m。temperature.gd の FIRE_R と同じ)
const HEARTH_R := 9.0          # 暖炉の暖かさが届く (m。temperature.gd の HEARTH_R と同じ。暖炉のまわりの席まで)
const CRISP_FROM := 0.15       # 暖かさ（0 〜 1。火からの近さ）がこれを超えると、0 より下（パリッと）へ行く
const CRISP_FULL := 0.6        # ここで −40 まで行く（火から 2 m）
const DRYER_DRY := 140.0 / 6.0 # 乾燥機の中で乾く速さ（1 秒に。100 から −40 まで 6 秒。回る長さ cook_station.gd の RIDE_MIN・RIDE_MAX と合わせる）

const SEND_STEP := 2.0         # 値がこれだけ変わるか、段が変わったら配る
const SEND_GAP := 0.25         # 配るのは多くても 1 秒に 4 回

var hub: Emotes                # 身ぶりの配り役（人の番号と、雪玉が当たった出来事）
var badges: Node               # badges.gd（あれば押す力・速さのバッジを入れる）
var authority := true          # 値を決める。false なら受けるだけ（確かめの道具が値を止めるとき）
var water := {}                # 番号 → 値（−40 〜 100）
var _fall := {}                # 番号 → 前のフレームの下向きの速さ（空中にいるあいだ）
var _sent := {}                # 番号 → [最後に配った値, 時刻]


func _ready() -> void:
	if hub:
		hub.happened.connect(_on_emote)


## 段の番号（STAGES の添え字。0 パリッと 〜 1 ふつう 〜 3 よれよれ）
static func stage_of(w: float) -> int:
	for i in STAGES.size():
		if w <= STAGES[i][0]:
			return i
	return STAGES.size() - 1


static func speed_of(w: float) -> float:
	return STAGES[stage_of(w)][2]


static func push_of(w: float) -> float:
	return STAGES[stage_of(w)][3]


static func pose_step_of(w: float) -> float:
	return STAGES[stage_of(w)][4]


## 人形の見た目（-1 びしょびしょ 〜 0 ふつう 〜 1 パリパリ）。0 より上は水のまま、0 より下はパリッとした張り
static func look_of(w: float) -> float:
	return -w / HI if w > 0.0 else clampf(w / CRISP, 0.0, 1.0)


func water_of(id: int) -> float:
	return water.get(id, START)


## 歩く速さ・押す力に掛ける倍率（持ち主が引く）
func speed_k(id: int) -> float:
	return speed_of(water_of(id))


func push_k(id: int) -> float:
	return push_of(water_of(id))


## 水を足す（正で濡れる、負で乾く）。値を決める画面だけ（通信の相手の値は、その人の画面が決める）。
## 濡れると、パリッとはすぐ消える（0 から足す）
func add_water(id: int, amount: float) -> void:
	if authority and not _from_net(id):
		water[id] = clampf((maxf(water_of(id), 0.0) if amount > 0.0 else water_of(id)) + amount, CRISP, HI)


func _from_net(id: int) -> bool:
	var who = hub.people.get(id) if hub else null
	return who != null and is_instance_valid(who) and who.get("damp_from_net") == true


## 確かめ用: 値をそのまま入れる
func put(id: int, w: float) -> void:
	water[id] = clampf(w, CRISP, HI)
	_publish(id, true)


## 通信で受けた出来事（{kind: "damp", who, w}）
func apply_net(ev: Dictionary) -> void:
	if ev.get("kind", "") == "damp":
		water[int(ev.who)] = clampf(float(ev.get("w", 0.0)), CRISP, HI)


## 入ってきた人に渡す、みんなの値（net.gd）
func snapshot() -> Dictionary:
	return water.duplicate()


func load_snapshot(s: Dictionary) -> void:
	water.merge(s, true)


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
		# 一人プレイの仲間（bot.gd）は湿らない。通信の相手（remote_person.gd）の値は、その人の画面から届く
		if authority and not who.get("stays_dry") and not who.get("damp_from_net"):
			water[id] = clampf(water_of(id) + _rate(id, who, dt), CRISP, HI)
		var d: Doll = who.get("doll")
		if d and is_instance_valid(d):
			d.damp = look_of(water_of(id))
			d.pose_step = pose_step_of(water_of(id))
		_publish(id, false)


## いまの場所と動きから、1 フレームの増減
func _rate(id: int, who: Node3D, dt: float) -> float:
	var w := water_of(id)
	# 中か外かは、音の屋内の判定（audio.gd の zone_at: 0 外・1 風除室・2 中）
	var temp := get_node_or_null("/root/Temperature")
	var at := who.global_position + Vector3.UP
	var zone := Audio.zone_at(temp._find_lodge(), at) if temp else 0
	var warm := _warm_at(who.global_position, temp)
	var d: Doll = who.get("doll")
	var dw := 0.0
	if _in_dryer(id):
		dw = -minf(DRYER_DRY * dt, w - CRISP)   # 乾燥機の中: 一瞬でいちばんパリッと
	elif warm > 0.0:
		# 火のそば（中でも外でも）: 速く乾き、近ければ 0 より下（パリッと）まで。焚き火は暖炉より速い（campfire.gd の dry_k）
		var floor_w := lerpf(0.0, CRISP, smoothstep(CRISP_FROM, CRISP_FULL, warm))
		if w > floor_w:
			dw = -minf((DRY_ROOM + DRY_FIRE * warm) * _fire_k(who.global_position) * dt, w - floor_w)
		elif w < 0.0:
			dw = minf(CRISP_FADE * dt, floor_w - w)   # 火から少し離れたら、その近さのパリッとまで戻る
	elif w < 0.0:
		dw = minf(CRISP_FADE * dt, -w)                # 火から離れると、パリッとが抜けて 0 に戻る
	elif zone == 2:
		dw = -minf(DRY_ROOM * dt, w)                  # ロッジの中: 0 まで乾く
	if zone == 0:
		# 外: じわじわ湿り、動くと雪で湿る
		if w >= 0.0 and w < AIR_FLOOR and warm <= 0.0:
			dw += minf(AIR_WET * dt, AIR_FLOOR - w)
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
				dw += FALL_WET - minf(w, 0.0)   # パリッとは消えて、そこから濡れる
			_fall.erase(id)
	return dw


## その所の火の暖かさ（0 〜 1）: 暖炉から HEARTH_R、焚き火（仲間分け "fires"）から FIRE_R の内で近いほど強い
func _warm_at(pos: Vector3, temp: Node) -> float:
	var warm := 0.0
	if temp and temp._find_lodge() and temp._fire != Vector3.INF and Audio.zone_at(temp._lodge, pos + Vector3.UP) == 2:
		warm = clampf(1.0 - pos.distance_to(temp._fire) / HEARTH_R, 0.0, 1.0)   # 暖炉はロッジの中からだけ（壁の外では効かない）
	for f in get_tree().get_nodes_in_group("fires"):
		if f is Node3D and is_instance_valid(f):
			warm = maxf(warm, clampf(1.0 - pos.distance_to((f as Node3D).global_position) / FIRE_R, 0.0, 1.0))
	return warm


## 乾く速さの倍率: 暖かさの届いている焚き火（"fires" の dry_k）のうち、いちばん速いもの。暖炉だけなら 1
func _fire_k(pos: Vector3) -> float:
	var k := 1.0
	for f in get_tree().get_nodes_in_group("fires"):
		if f is Node3D and is_instance_valid(f) and pos.distance_to((f as Node3D).global_position) < FIRE_R:
			k = maxf(k, float(f.get("dry_k") if f.get("dry_k") != null else 1.0))
	return k


## 乾燥機の中で回っているか（cook_station.gd）
func _in_dryer(id: int) -> bool:
	for st in get_tree().get_nodes_in_group("dryers"):
		if st.drying(id):
			return true
	return false


## 段が変わったか、値が SEND_STEP 動いたら、出来事を配る（通信の量を抑える）。バッジも入れ直す
func _publish(id: int, force: bool) -> void:
	var w := roundf(water_of(id))
	var last: Array = _sent.get(id, [INF, -100.0])
	var now := Time.get_ticks_msec() / 1000.0
	var moved := absf(w - last[0]) >= SEND_STEP or stage_of(w) != (stage_of(last[0]) if last[0] != INF else -1)
	if force or (moved and now - last[1] >= SEND_GAP):
		_sent[id] = [w, now]
		if authority and not _from_net(id):   # 通信の相手の値は、その人の画面が送っている（送り返すと、その人の値を古い値で上書きしてしまう）
			sent.emit({"kind": "damp", "who": id, "w": int(w)})
	if badges:
		# 押す力と速さのバッジ（段の向きと矢印の数）。ふつうなら出さない
		var st: Array = STAGES[stage_of(water_of(id))]
		for stat in ["push", "speed"]:
			if st[5] == 0:
				badges.clear(id, "damp_" + stat)
			else:
				badges.put(id, "damp_" + stat, st[5], st[6], stat)
