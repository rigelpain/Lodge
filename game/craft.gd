extends Node
## 工房の配り役。型紙と布を買う・ミシンにセットする・縫い上がる・ソリを畳む・広げる を、
## 「誰が・何を・いつ（姿勢の時計のコマ）」の短い出来事 {kind, who, frame, ...} にして配る（emotes.gd と同じ形）。
## 中身は数・文字・Vector3 だけにして、そのまま通信に乗せられるようにする。who は人の番号（emotes.gd の join でもらう）。
##
## いまは一人の画面の中だけ: send() がすぐ frame を付けて _apply() し、みんな（持ち主・ミシン・画面）に配る。
## 通信を入れたら: send() はホストへ送るだけにし、ホストが値段・持ち物の空き・ソリの置き場を確かめてから全員に配る。
## 財布と持ち物はホストが持つ（ここの wallets と bags）。断られた出来事は配らない（send が false を返す）。
##
## 出来事:
##   buy    {item}             売り子から買う。item は {kind:"pattern", sled} か {kind:"fabric", fabric}
##   hand   {slot}             手に持つ物を替える（-1 は素手）
##   load   {slot, item}       手に持った型紙か布をミシンにセットする（ミシンが読む）
##   sewn   {sled, fabric, at, yaw, id}  ミシンが縫い上げた。広げた実寸のソリが at に出る
##   fold   {id, item}         置いてあるソリを畳んで、持ち物に入れる（畳む動きは origami.gd）
##   unfold {slot, item, at, yaw, id}    畳んだソリを手から前の床に広げて置く

signal happened(ev: Dictionary)

const Doll := preload("res://doll.gd")
const Sled := preload("res://sled.gd")
const Fabrics := preload("res://fabrics.gd")

## お金はまだ決めていない（design/facilities.md）。仮にボタンをお金にし、最初に START_BUTTONS 個持たせる
const START_BUTTONS := 12
const PATTERN_PRICE := {"sack": 1, "small": 2, "mid": 3, "large": 5}   # 型紙の値段（ボタンの数）
const FABRIC_PRICE := 1
const PATTERNS := ["sack", "small", "mid", "large"]
const SLOTS := 8               # 持ち物に入る数
const FOLD_FRAMES := 30        # 畳む動きの長さ（コマ。12 コマで 1 秒）
const UNFOLD_FRAMES := 30      # 広げる動きの長さ

var world: Node                # main.gd（ソリを置く所）
var wallets := {}              # 人の番号 → ボタンの数
var bags := {}                 # 人の番号 → 持ち物（item の配列）
var hands := {}                # 人の番号 → 手に持つ持ち物の番号（-1 は素手）
var sleds := {}                # ソリの番号 → 縫った・広げたソリ（畳めるソリ）
var _next_sled := 1


## 人を登録する（財布と持ち物を作る）
func join(who: int) -> void:
	if wallets.has(who):
		return
	wallets[who] = START_BUTTONS
	bags[who] = []
	hands[who] = -1


func bag(who: int) -> Array:
	return bags.get(who, [])


func wallet(who: int) -> int:
	return wallets.get(who, 0)


## 手に持っている物（素手なら {}）
func held(who: int) -> Dictionary:
	var i: int = hands.get(who, -1)
	var b := bag(who)
	return b[i] if i >= 0 and i < b.size() else {}


static func price(item: Dictionary) -> int:
	if item.get("kind") == "pattern":
		return PATTERN_PRICE.get(item.get("sled", ""), 99)
	if item.get("kind") == "fabric":
		return FABRIC_PRICE
	return 99


## 出来事を出す。持ち主が呼ぶ（いまはすぐ配る。通信ではホストへ）。断られたら false
func send(ev: Dictionary) -> bool:
	ev["frame"] = Doll.frame_index() + 1
	return _apply(ev)


## ホストの判定
func _apply(ev: Dictionary) -> bool:
	var who: int = ev.get("who", -1)
	if not wallets.has(who) and ev.kind != "sewn":
		return false
	match ev.kind:
		"buy":
			var item: Dictionary = ev.item
			var cost := price(item)
			if wallets[who] < cost or bags[who].size() >= SLOTS:
				return false
			wallets[who] -= cost
			bags[who].append(item)
			hands[who] = bags[who].size() - 1   # 買った物を手に持つ
			ev["slot"] = hands[who]
		"hand":
			hands[who] = clampi(int(ev.slot), -1, bags[who].size() - 1)
		"load":
			if not _take(who, int(ev.slot), ev.item):
				return false
		"sewn":
			ev["id"] = _place(ev.sled, ev.fabric, ev.at, ev.yaw, 0)
		"fold":
			var s: Node3D = sleds.get(int(ev.id))
			if s == null or not is_instance_valid(s) or bags[who].size() >= SLOTS or not _free(s):
				return false
			ev["item"] = {"kind": "folded", "sled": s.kind, "fabric": s.fabric}
			ev["at"] = s.global_position
			ev["yaw"] = s.rotation.y
			sleds.erase(int(ev.id))
			bags[who].append(ev.item)
			hands[who] = bags[who].size() - 1
			ev["slot"] = hands[who]
		"unfold":
			if not _take(who, int(ev.slot), ev.item):
				return false
			ev["id"] = _place(ev.item.sled, ev.item.fabric, ev.at, ev.yaw, UNFOLD_FRAMES)
	happened.emit(ev)
	return true


## 持ち物の slot 番目が item なら取り出す。手は素手に戻す
func _take(who: int, slot: int, item: Dictionary) -> bool:
	var b: Array = bags[who]
	if slot < 0 or slot >= b.size() or b[slot] != item:
		return false
	b.remove_at(slot)
	hands[who] = -1
	return true


## 誰も乗っていない・つかんでいない・紐を持っていないソリだけ畳める
func _free(s: Node3D) -> bool:
	return s.riders.is_empty() and s.holders.is_empty() and s.rope_holder == null


## 実寸のソリを置く。wait コマのあいだは止めておく（広げる動きのあいだ）
func _place(kind: String, fabric: String, at: Vector3, yaw: float, wait: int) -> int:
	var id := _next_sled
	_next_sled += 1
	var s := Sled.new()
	s.kind = kind
	s.fabric = fabric
	s.crafted = true
	s.name = "MadeSled%d" % id
	s.position = at
	s.rotation.y = yaw
	if world and world.has_method("snow_lift"):
		s.snow_lift = Callable(world, "snow_lift")
	(world if world else get_parent()).add_child(s)
	s.set_meta("craft_id", id)
	if wait > 0:
		s.hold_still(wait)
	sleds[id] = s
	return id


## ソリの番号（畳めるソリでなければ -1）
func id_of(s: Node) -> int:
	for id in sleds:
		if sleds[id] == s:
			return id
	return -1
