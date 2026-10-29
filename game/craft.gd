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
##   fold   {id, item}         置いてあるソリを畳んで、持ち物に入れる（畳む動きは origami.gd）。item に名札の柄 tag も入る
##   unfold {slot, item, at, yaw, up, id}  畳んだソリを手から前の床に広げて置く（up は床の傾き）

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
			ev["tag"] = 1 + (_next_sled - 1) % (preload("res://sled_tags.gd").count() - 1)   # 名札の柄は順に（0 は最初のソリ）
			ev["id"] = _place(ev.sled, ev.fabric, ev.at, ev.yaw, 0, Vector3.UP, ev.tag)
		"fold":
			var s: Node3D = sleds.get(int(ev.id))
			if s == null or not is_instance_valid(s) or bags[who].size() >= SLOTS or not _free(s):
				return false
			ev["item"] = {"kind": "folded", "sled": s.kind, "fabric": s.fabric, "tag": s.tag}
			ev["at"] = s.global_position
			ev["yaw"] = s.rotation.y
			sleds.erase(int(ev.id))
			_origami(ev, false, s.global_transform)
			s.queue_free()
			bags[who].append(ev.item)
			hands[who] = bags[who].size() - 1
			ev["slot"] = hands[who]
		"unfold":
			if not _take(who, int(ev.slot), ev.item):
				return false
			var up: Vector3 = ev.get("up", Vector3.UP)
			ev["id"] = _place(ev.item.sled, ev.item.fabric, ev.at, ev.yaw, UNFOLD_FRAMES, up, int(ev.item.get("tag", 0)))
			_origami(ev, true, Transform3D(_basis(ev.yaw, up), ev.at))
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


## 畳む・広げる動き（origami.gd）を、ソリの所に置く
func _origami(ev: Dictionary, unfolding: bool, at: Transform3D) -> void:
	var o: Node3D = load("res://origami.gd").new()
	o.kind = ev.item.sled
	o.fabric = ev.item.fabric
	o.unfolding = unfolding
	o.start = int(ev.frame)
	var hub: Node = world.get_node_or_null("Emotes") if world else null
	o.who = hub.who_of(int(ev.who)) if hub else null
	o.name = "Origami"
	o.transform = Transform3D(at.basis.orthonormalized(), at.origin)   # 置く先（main）は原点にある
	(world if world else get_parent()).add_child(o)


## 誰も乗っていない・つかんでいない・紐を持っていないソリだけ畳める
func _free(s: Node3D) -> bool:
	return s.riders.is_empty() and s.holders.is_empty() and s.rope_holder == null


## 実寸のソリを置く。wait コマのあいだは止めておく（広げる動きのあいだ）
func _place(kind: String, fabric: String, at: Vector3, yaw: float, wait: int, up := Vector3.UP, tag := 0) -> int:
	var id := _next_sled
	_next_sled += 1
	var s := Sled.new()
	s.kind = kind
	s.fabric = fabric
	s.crafted = true
	s.tag = tag
	s.name = "MadeSled%d" % id
	s.transform = Transform3D(_basis(yaw, up), at + up * 0.08)   # 床に少し浮かせて置く（めり込むと床の下へ押し出される）
	if world and world.has_method("snow_lift"):
		s.snow_lift = Callable(world, "snow_lift")
	(world if world else get_parent()).add_child(s)
	s.set_meta("craft_id", id)
	if wait > 0:
		s.hold_still(wait)
	sleds[id] = s
	_make_room(s)
	return id


## ソリの出る所に立っている人を、ソリの横へよける（重なったまま出すと、ソリが薄い床の下へ押し出される）
func _make_room(s: RigidBody3D) -> void:
	var k: Dictionary = Sled.KINDS.get(s.kind, Sled.KINDS["mid"])
	var half := Vector2(k.box.x, k.box.z) * 0.5 + Vector2(0.45, 0.45)
	for c in s.get_parent().get_children():
		if not (c is CharacterBody3D):
			continue
		var lp := s.to_local((c as Node3D).global_position)
		if absf(lp.x) < half.x and absf(lp.z) < half.y and absf(lp.y) < 2.0:
			lp.x = half.x * (1.0 if lp.x >= 0.0 else -1.0)
			(c as Node3D).global_position = s.to_global(lp) + Vector3.UP * 0.05


## 向き yaw で、上を up（床の傾き）に合わせた向き
static func _basis(yaw: float, up: Vector3) -> Basis:
	var b := Basis(Vector3.UP, yaw)
	if up.dot(Vector3.UP) < 0.999:
		b = Basis(Quaternion(Vector3.UP, up.normalized())) * b
	return b


## ソリの番号（畳めるソリでなければ -1）
func id_of(s: Node) -> int:
	for id in sleds:
		if sleds[id] == s:
			return id
	return -1
