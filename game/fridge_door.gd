extends Node3D
## 雪だるまの冷蔵庫の扉と、畳める番台（2026-11-02 代表「扉は近づいたら開いてほしい」「普段0、開いたときに番台が組み立てられる感じ」）。
## ふだんは扉がぴったり閉じ（0°）、番台は冷蔵庫の前の床に畳んである。人（CharacterBody3D。自分・ボット・オンラインのほかの人の
## だれでも）が冷蔵庫の口の前 NEAR_R m に入ると、扉が 220° まで開き、開ききってから番台が組み立つ（前の板が起き、横の板が
## ぱた・ぱたと出て、天板がのり、冷蔵庫からレジ・お皿・雪玉が跳んで来る）。だれもいなくなると逆の順に畳んでから扉が閉じる。
## 近くの人はロッジの自動ドア（lodge/lodge.gd）と同じく Area3D で見る。どの画面でも、その画面の人の並びで同じように動く。
## 動きは人形と同じ 12 fps のコマ（Doll.frame_index）で刻む。番台は組み立ちのコマの番号 _stage ひとつで形が決まるので、
## 途中で人が来たり去ったりしても、その所から逆へ戻れる。
## 扉が閉じるあいだ、雪だるまは両手を上げて少し奥へ下がり（snowman_shop.gd の tuck）、口からこぼれる冷気の綿（glb の節点 chill）は
## しぼんで隠れる。扉が開くと逆に。番台が組み立ちきるまでは雪だるまに話しかけられない（snowman_shop.gd の open）。
## 扉の節点 door・chill は props/build_snowman.py、番台は同じ台本の snowman_counter（節点 front・side_l・side_r・top）。
## 冷蔵庫（SNOWMAN_SCALE 倍）の子に置くので、ここの長さは倍率 1 の冷蔵庫の座標

const Doll := preload("res://doll.gd")

const OPEN := 220.0      # 開いたとき（build_snowman.py の DOOR_OPEN）。前の面より後ろへ回り込み、左の側面に沿う
const NEAR_R := 4.0      # 冷蔵庫の口の前のこの距離（m、ロッジの長さ）に人が入ると開く
const OPEN_K := 32.0     # 開くときのばね（コマごと）。少し行き過ぎて 220° に戻る
const OPEN_D := 0.55
const SHUT_K := 18.0     # 閉じるときは、開くよりゆっくり
const SHUT_D := 0.6
const UNTUCK_AT := 0.35  # 扉がこの開き（0〜1）を越えたら、雪だるまが手を下ろして前へ出る
const CHILL_AT := 0.4    # 扉がこの開きを越えたら、冷気の綿がもくもく出てくる

## 番台の組み立ちのコマ（_stage 0 = 畳んだ、STAGES = 組み立った）。[コマ, 角度] の並びを、コマのあいだは直線でつなぐ。
## front は x の回り（−90° で客の側へ倒れて床に寝る）、side_l・side_r は y の回り（±90° で前の板の内に重なる）、
## top は x の回り（90° で横の板の後ろに垂れる）
const STAGES := 24
const KEYS := {
	"front": [[0, -90.0], [1, -84.0], [2, -70.0], [3, -48.0], [4, -22.0], [5, 4.0], [6, 0.0]],
	"side_l": [[6, 90.0], [7, 55.0], [8, 10.0], [9, -4.0], [10, 0.0]],
	"side_r": [[8, -90.0], [9, -55.0], [10, -10.0], [11, 4.0], [12, 0.0]],
	"top": [[12, 90.0], [13, 70.0], [14, 35.0], [15, -6.0], [16, 0.0]],
}
## 番台にのる物が冷蔵庫から跳んで来るコマ: [節点の名前, 跳び始めのコマ, 跳ぶコマ数, 高さ (m)]
const HOPS := [["Register", 16, 4, 0.5], ["Dish", 18, 4, 0.45], ["Heap", 21, 3, 0.35]]
## コマを進めた（戻した）とき鳴らす音: コマ → [音, 大きさ]。番台は sound/gen/fridge.py、跳ぶ物は cook.py の「ぽこ」
const STAGE_SOUNDS := {6: ["stall_flap", -8.0], 10: ["stall_tap", -10.0], 12: ["stall_tap", -10.0], 16: ["stall_flap", -9.0],
		20: ["cook_pellet_01", -10.0], 22: ["cook_pellet_02", -10.0], 24: ["cook_pellet_03", -10.0]}

var main: Node
var door: Node3D
var chill: Node3D
var _area: Area3D
var _p := 0.0            # 扉の開き（0 = 閉じた、1 = OPEN）
var _v := 0.0
var _goal := 0.0
var _tuck := 1.0         # 雪だるまの身構え（1 = 手を上げて奥へ）
var _chill := 0.0
var _stage := 0
var _frame := -1
var _counter: Node3D     # 番台の根元（main.gd の Bandai_counter_indigo）
var _parts := {}         # 名前 → 番台の節点（front・side_l・side_r・top）
var _items := {}         # 名前 → [節点, 組み立った所（番台の座標）]
var _col: CollisionShape3D


func _ready() -> void:
	door = get_parent().find_child("door", true, false) as Node3D
	chill = get_parent().find_child("chill", true, false) as Node3D
	var spot := get_parent().find_child("chill_spot", true, false) as Node3D   # 口の縁の下
	_area = Area3D.new()
	_area.name = "FridgeDoorSensor"
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	var s := (get_parent() as Node3D).scale.x
	sh.radius = NEAR_R / s
	sh.height = 3.0 / s
	cs.shape = sh
	_area.add_child(cs)
	_area.position = (spot.position if spot else Vector3.ZERO) + Vector3(0, sh.height / 2.0, 0)
	add_child(_area)
	_apply()


func _process(_dt: float) -> void:
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	_frame = fi
	_step()


## 番台の節点を探す（番台は main.gd の _put_bandai が雪だるまの後に置くので、初めのコマで）
func _find_counter() -> void:
	var shop = main.get("snowman_shop") if main else null
	_counter = shop.counter if shop else null
	if _counter == null:
		return
	for n in ["front", "side_l", "side_r", "top"]:
		_parts[n] = _counter.find_child(n, true, false)
	for h in HOPS:
		var node := _counter.get_node_or_null(String(h[0])) as Node3D
		if node:
			_items[h[0]] = [node, node.position]
	_col = _counter.find_child("CounterShape", true, false) as CollisionShape3D


## 1 コマ進める
func _step() -> void:
	if _counter == null:
		_find_counter()
	var someone := false
	for b in _area.get_overlapping_bodies():
		if b is CharacterBody3D:
			someone = true
			break
	var goal := 0.0
	if someone:
		goal = 1.0
		if _p > 0.95 and _stage < STAGES:   # 扉が開ききってから組み立つ
			_stage += 1
			_stage_sound(_stage)
	elif _stage > 0:                         # 畳みきるまで扉は開けておく
		_stage_sound(_stage)
		_stage -= 1
		goal = 1.0
	if goal > _goal and _p < 0.5:
		_sound("fridge_open", -9.0)
	_goal = goal
	var dt := 1.0 / 12.0
	var opening := _goal > 0.5
	_v += (_goal - _p) * (OPEN_K if opening else SHUT_K) * dt
	_v *= OPEN_D if opening else SHUT_D
	_p += _v * dt
	if _p < 0.0:   # 閉まる: 小さく跳ね返る
		_p = 0.0
		if _v < -0.6:
			_sound("fridge_close", -8.0)
		_v = -_v * 0.25
	# 雪だるまは、閉じ始めたらすぐ手を上げて下がり、開いてくる扉が UNTUCK_AT を越えたら手を下ろす（3 コマで）
	_tuck = move_toward(_tuck, 1.0 if (_goal < 0.5 or _p < UNTUCK_AT) else 0.0, 1.0 / 3.0)
	_chill = move_toward(_chill, 1.0 if _p > CHILL_AT else 0.0, 0.25)
	_apply()


func _apply() -> void:
	if door:
		door.rotation.y = deg_to_rad(-OPEN * _p)
	if chill:
		chill.visible = _chill > 0.0
		var c := _chill * _chill * (3.0 - 2.0 * _chill)
		chill.scale = Vector3.ONE * maxf(0.05, c)
	var shop = main.get("snowman_shop") if main else null
	if shop:
		shop.tuck = _tuck
		shop.open = _stage >= STAGES
	for n in _parts:
		var node := _parts[n] as Node3D
		if node == null:
			continue
		var a := deg_to_rad(_key(KEYS[n], _stage))
		if n in ["side_l", "side_r"]:
			node.rotation = Vector3(0, a, 0)
		else:
			node.rotation = Vector3(a, 0, 0)
	for h in HOPS:
		if not _items.has(h[0]):
			continue
		var node: Node3D = _items[h[0]][0]
		var to: Vector3 = _items[h[0]][1]
		var t := clampf(float(_stage - int(h[1])) / float(h[2]), 0.0, 1.0)
		node.visible = t > 0.0
		if t > 0.0 and t < 1.0:   # 冷蔵庫の口から、番台の上の所へ弧を描いて
			var from := _counter.to_local(get_parent().to_global(Vector3(0, 1.0, -0.2)))
			node.position = from.lerp(to, t) + Vector3.UP * float(h[3]) * 4.0 * t * (1.0 - t)
		elif t >= 1.0:
			node.position = to
	if _col:
		_col.disabled = _stage < STAGES


## コマの並び keys の、コマ s での角度
static func _key(keys: Array, s: int) -> float:
	if s <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if s <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			return lerpf(a[1], b[1], float(s - a[0]) / float(b[0] - a[0]))
	return keys[-1][1]


func _stage_sound(s: int) -> void:
	if STAGE_SOUNDS.has(s):
		var snd: Array = STAGE_SOUNDS[s]
		var audio = main.get_node_or_null("Audio") if main else null
		if audio and _counter:
			audio.kitchen(_counter, snd[0], snd[1])


func _sound(name_: String, db: float) -> void:
	var audio = main.get_node_or_null("Audio") if main else null
	if audio and door:
		audio.kitchen(door, name_, db)
