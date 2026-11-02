extends Node3D
## 雪だるまの冷蔵庫の扉（props/build_snowman.py の節点 door。原点が蝶番の軸）。ふだんは番台の横まで開いていて、
## 人（CharacterBody3D。自分・ボット・オンラインのほかの人のだれでも）が冷蔵庫の前 NEAR_R m に入ると 220° まで開き、
## だれもいなくなると戻る（2026-11-02 代表「扉は近づいたら開いてほしい」）。ロッジの自動ドア（lodge/lodge.gd）と同じく、
## 近くにいる人を Area3D で見る。動きは人形と同じ 12 fps のコマ（Doll.frame_index）で刻み、ばねのように少し行き過ぎて止まる。
## 開き始めに fridge_open、戻って止まる所で fridge_close（sound/gen/fridge.py）。開いた扉に当たり判定はない。
## 冷蔵庫（SNOWMAN_SCALE 倍）の子に置くので、ここの長さは倍率 1 の冷蔵庫の座標

const Doll := preload("res://doll.gd")

## ふだんの開き（度）。扉は 45° より閉じると、内の棚が中の雪だるまの腕・前かけや、霜と冷気の綿にめり込む。
## 45°〜90° では、扉の先が冷蔵庫の前の番台（main.gd の BANDAI の counter_indigo）を通り抜けるので、番台に当たらない 105° で待つ
const REST := 105.0
const OPEN := 220.0      # 開いたとき（build_snowman.py の DOOR_OPEN）。前の面より後ろへ回り込み、左の側面に沿う
const NEAR_R := 4.0      # 冷蔵庫の口の前のこの距離（m、ロッジの長さ）に人が入ると開く
const OPEN_K := 32.0     # 開くときのばね（コマごと）。少し行き過ぎて 220° に戻る
const OPEN_D := 0.55
const SHUT_K := 18.0     # 戻るときは、開くよりゆっくり
const SHUT_D := 0.6

var main: Node
var door: Node3D
var _area: Area3D
var _p := 0.0            # 開き具合（0 = REST、1 = OPEN）
var _v := 0.0
var _goal := 0.0
var _frame := -1


func _ready() -> void:
	door = get_parent().find_child("door", true, false) as Node3D
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


## 1 コマ進める
func _step() -> void:
	var someone := false
	for b in _area.get_overlapping_bodies():
		if b is CharacterBody3D:
			someone = true
			break
	var goal := 1.0 if someone else 0.0
	if goal > _goal and _p < 0.5:
		_sound("fridge_open", -9.0)
	_goal = goal
	var dt := 1.0 / 12.0
	var opening := _goal > 0.5
	_v += (_goal - _p) * (OPEN_K if opening else SHUT_K) * dt
	_v *= OPEN_D if opening else SHUT_D
	_p += _v * dt
	if _p < 0.0:   # 戻って止まる: 小さく跳ね返る
		_p = 0.0
		if _v < -0.6:
			_sound("fridge_close", -8.0)
		_v = -_v * 0.25
	_apply()


func _apply() -> void:
	if door:
		door.rotation.y = deg_to_rad(-lerpf(REST, OPEN, _p))


func _sound(name_: String, db: float) -> void:
	var audio = main.get_node_or_null("Audio") if main else null
	if audio and door:
		audio.kitchen(door, name_, db)
