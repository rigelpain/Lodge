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
##   sew    {pattern, fabric, pattern_slot, fabric_slot}  ミシンの画面で選んだ型紙と布を 1 つずつ使って縫い始める（両方いっしょに使う。ミシンが読む）
##   sewn   {sled, fabric, at, yaw, id}  ミシンが縫い上げた。広げた実寸のソリが at に出る
##   fold   {id, item}         置いてあるソリを畳んで、持ち物に入れる（畳む動きは origami.gd）。item に名札の柄 tag も入る
##   unfold {slot, item, at, yaw, up, id}  畳んだソリを手から前の床に広げて置く（up は床の傾き）
##   sack_out  {at, yaw, up, v}  装備の米袋（いま選んでいるもの）を足もとに出す（2026-10-29 代表: 米袋は装備。持ち物の列は使わない）。
##                             v は出した人の勢い（初めの速さ。走りながら出すと滑り出す）
##   sack_in   {}              出している米袋を、くるっと丸めて帯に戻す
##   tag_design {design}       自分の名札のデザインを決める（装備の画面）。持ち主の印として、その人のソリ・米袋の名札が替わる
##   equip     {gear, index}   装備の画面（craft_ui.gd）で、その種類（gear）の持っている物から装備する物を替える
## 装備は種類ごとに「持っている物の配列」と「装備している番号」を持つ（GEARS）。いまは米袋だけ。服や名札の柄を足すときは、
## GEARS に種類を足し、_gear_lists に持ち物の配列の入れ物を足す
## 米袋は全員が最初から 1 つ（標準）持つ。米袋の型紙と布で縫った米袋は、持ち物でなく装備の枠に入り、選ばれる

signal happened(ev: Dictionary)

const Doll := preload("res://doll.gd")
const Sled := preload("res://sled.gd")
const Fabrics := preload("res://fabrics.gd")

## お金はまだ決めていない（design/facilities.md）。仮にボタンをお金にし、最初に START_BUTTONS 個持たせる
const START_BUTTONS := 12
const PATTERN_PRICE := {"sack": 1, "small": 2, "mid": 3, "large": 5}   # 型紙の値段（ボタンの数）
const FABRIC_PRICE := 1
const PATTERNS := ["sack", "small", "mid", "large"]
## ロッジの中から外へ運び出せないソリ（tools/carry_out_check.gd で確かめた。大は西の通路の家具と壁に当たる）。
## 縫うと、ロッジの前（main.gd の delivery_spot）に、空から包みが落ちて折り紙のように開いて出てくる
const OUT_FRONT := ["large"]
const SLOTS := 8               # 持ち物に入る数
const FOLD_FRAMES := 30        # 畳む動きの長さ（コマ。12 コマで 1 秒）
const UNFOLD_FRAMES := 30      # 広げる動きの長さ

var world: Node                # main.gd（ソリを置く所）
var wallets := {}              # 人の番号 → ボタンの数
var bags := {}                 # 人の番号 → 持ち物（item の配列）
var hands := {}                # 人の番号 → 手に持つ持ち物の番号（-1 は素手）
var sleds := {}                # ソリの番号 → 縫った・広げたソリ（畳めるソリ）
var _next_sled := 1
const GEARS := ["sack"]        # 装備の種類（装備の画面の並び）
var tag_designs := {}          # 人の番号 → 自分の名札（sled_tags.gd の部品の辞書）。通信では「誰が」の印として配る
var tag_owned := {}            # 人の番号 → 手に入れた「あとで手に入る」名札の部品 {部品: [番号, ...]}（最初から使える部品は書かない）
var sacks := {}                # 人の番号 → 持っている米袋の配列 [{fabric, tag}]（0 番は標準）
var sack_sel := {}             # 人の番号 → 装備している米袋の番号（N でこれが出る）
var sack_out := {}             # 人の番号 → いま出している米袋（ソリ）
var _sack_far := {}            # 人の番号 → 持ち主が離れていた秒
const SACK_FAR := 30.0         # 誰も乗っていない米袋から持ち主がこれより離れて…
const SACK_FAR_T := 4.0        # …この秒たつと、ひとりでに帯に戻る


## 人を登録する（財布と持ち物を作る）
func join(who: int) -> void:
	if wallets.has(who):
		return
	wallets[who] = START_BUTTONS
	bags[who] = []
	hands[who] = -1
	tag_designs[who] = preload("res://sled_tags.gd").default_design(who)
	tag_owned[who] = {}
	sacks[who] = [{"fabric": "", "tag": 0}]   # 標準の米袋（名札は持ち主の名札）
	sack_sel[who] = 0


## 名札の部品 part の i 番を使えるか（最初から使える部品か、手に入れた部品）
func tag_can_use(who: int, part: String, i: int) -> bool:
	if preload("res://sled_tags.gd").is_starter(part, i):
		return true
	return i in tag_owned.get(who, {}).get(part, [])


## 種類 gear の、持っている物の配列と、装備している番号
func gear_list(who: int, gear: String) -> Array:
	match gear:
		"sack": return sacks.get(who, [])
	return []


func gear_index(who: int, gear: String) -> int:
	match gear:
		"sack": return int(sack_sel.get(who, 0))
	return -1


## いま呼び出す米袋 {fabric, tag}
func sack(who: int) -> Dictionary:
	var list: Array = sacks.get(who, [])
	return list[clampi(sack_sel.get(who, 0), 0, list.size() - 1)] if not list.is_empty() else {}


## 出している米袋（なければ null）
func sack_sled(who: int) -> RigidBody3D:
	var s = sack_out.get(who)
	return s if s != null and is_instance_valid(s) and not s.is_queued_for_deletion() else null


func bag(who: int) -> Array:
	return bags.get(who, [])


func wallet(who: int) -> int:
	return wallets.get(who, 0)


## 手に持っている物（素手なら {}）
func held(who: int) -> Dictionary:
	var i: int = hands.get(who, -1)
	var b := bag(who)
	return b[i] if i >= 0 and i < b.size() else {}


## 畳んで持てるのは一人用のソリだけ（2026-10-29 代表）。いまは米袋
static func foldable(kind: String) -> bool:
	return Sled.KINDS.get(kind, {}).get("seats", [0, 0]).size() <= 1


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
		"sew":
			# 型紙と布は両方そろって初めて使う（片方だけ消えることはない）
			var b: Array = bags[who]
			var ps := int(ev.pattern_slot)
			var fs := int(ev.fabric_slot)
			if ps == fs or ps < 0 or fs < 0 or ps >= b.size() or fs >= b.size() or b[ps] != ev.pattern or b[fs] != ev.fabric \
					or ev.pattern.get("kind") != "pattern" or ev.fabric.get("kind") != "fabric":
				return false
			if world and world.get("sewing") and not world.sewing.can_sew():
				return false
			b.remove_at(maxi(ps, fs))
			b.remove_at(mini(ps, fs))
			hands[who] = -1
		"sewn":
			ev["tag"] = tag_designs.get(who, 0)   # 持ち主の印: 縫った人の名札
			if ev.sled == "sack" and sacks.has(who):
				# 米袋は装備: 床には出さず、装備の枠に入れて、呼び出す米袋にする
				sacks[who].append({"fabric": ev.fabric, "tag": 0})
				sack_sel[who] = sacks[who].size() - 1
				ev["gear"] = true
			elif ev.sled in OUT_FRONT and world and world.has_method("delivery_spot"):
				# 運び出せない大きさ: ロッジの前に、空から包みが落ちて開いて出てくる
				var spot: Transform3D = world.delivery_spot(ev.sled)
				ev["at"] = spot.origin
				ev["yaw"] = spot.basis.get_euler().y
				ev["outside"] = true
				ev["id"] = _place(ev.sled, ev.fabric, ev.at, ev.yaw, UNFOLD_FRAMES, Vector3.UP, ev.tag, true, who)
				ev["item"] = {"kind": "folded", "sled": ev.sled, "fabric": ev.fabric, "tag": ev.tag}
				_origami(ev, true, Transform3D(Basis(Vector3.UP, ev.yaw), ev.at), false)
			else:
				ev["id"] = _place(ev.sled, ev.fabric, ev.at, ev.yaw, 0, Vector3.UP, ev.tag, true, who)
		"sack_out":
			var spec := sack(who)
			if spec.is_empty() or sack_sled(who) != null:
				return false
			var gid := _place("sack", spec.fabric, ev.at, ev.yaw, 0, ev.get("up", Vector3.UP), tag_designs.get(who, 0), false, who)
			var gs: RigidBody3D = sleds[gid]
			sleds.erase(gid)   # 装備の米袋は畳むソリの数に入れない
			gs.crafted = false
			gs.name = "Sack%d" % who
			gs.set_meta("gear_of", who)
			sack_out[who] = gs
			_sack_far[who] = 0.0
			gs.linear_velocity = ev.get("v", Vector3.ZERO)
			ev["id"] = gid
			_pop(gs)
		"sack_in":
			var gs := sack_sled(who)
			if gs == null:
				return false
			for r in gs.riders.duplicate():
				if r.has_method("get_off"):
					r.get_off()
			for h in gs.holders.keys():
				if h.has_method("let_go"):
					h.let_go()
			if gs.rope_holder and gs.rope_holder.has_method("let_go"):
				gs.rope_holder.let_go()
			ev["item"] = {"kind": "folded", "sled": "sack", "fabric": gs.fabric, "tag": gs.tag}
			_origami(ev, false, gs.global_transform, true, 3.0)   # くるっと丸めて、持ち主の帯へ飛ぶ（速回し。10 コマで、人形のしまう動き doll.gd の SACK_IN と同じ）
			sack_out.erase(who)
			if world:   # この米袋を相手にしていた人（と人形）は、もとのソリへ
				for c in world.get_children():
					if c is CharacterBody3D and c.get("sled") == gs:
						c.set("sled", world.get("sled"))
						if c.get("last_sled") == gs:
							c.set("last_sled", world.get("sled"))
						var d = c.get("doll")
						if d and d.get("sled") == gs:
							d.set("sled", world.get("sled"))
			gs.queue_free()
		"tag_unlock":   # あとで手に入る名札の部品を手に入れる（報酬や店から。値はここでは取らない）
			var Tags := preload("res://sled_tags.gd")
			var part := String(ev.get("part", ""))
			var i := int(ev.get("index", -1))
			if not part in Tags.PARTS or i < 0 or i >= Tags.part_count(part):
				return false
			var owned: Dictionary = tag_owned.get(who, {})
			if not owned.has(part):
				owned[part] = []
			if not i in owned[part]:
				owned[part].append(i)
			tag_owned[who] = owned
		"tag_design":
			var Tags := preload("res://sled_tags.gd")
			var old: Dictionary = tag_designs.get(who, {})
			var d: Dictionary = {}
			for part in Tags.PARTS:   # 書いていない部品は前のまま。まだ手に入れていない部品も前のまま
				var i := posmod(int(ev.design.get(part, old.get(part, Tags.DEFAULT[part]))), Tags.part_count(part))
				if not tag_can_use(who, part, i):
					i = int(old.get(part, Tags.DEFAULT[part]))
				d[part] = i
			ev["design"] = d
			tag_designs[who] = d
			for s in get_tree().get_nodes_in_group("sleds"):   # その人のソリの名札を付け替える
				if is_instance_valid(s) and int(s.get("owner_id")) == who:
					s.retag(d)
		"equip":
			var list := gear_list(who, String(ev.get("gear", "")))
			var i := int(ev.index)
			if i < 0 or i >= list.size():
				return false
			match ev.gear:
				"sack": sack_sel[who] = i
		"fold":
			var s: Node3D = sleds.get(int(ev.id))
			if s == null or not is_instance_valid(s) or not foldable(s.kind) or bags[who].size() >= SLOTS or not _free(s):
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
			ev["id"] = _place(ev.item.sled, ev.item.fabric, ev.at, ev.yaw, UNFOLD_FRAMES, up, tag_designs.get(who, 0), true, who)
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
func _origami(ev: Dictionary, unfolding: bool, at: Transform3D, from_who := true, speed := 1.0) -> void:
	var o: Node3D = load("res://origami.gd").new()
	o.kind = ev.item.sled
	o.fabric = ev.item.fabric
	o.unfolding = unfolding
	o.start = int(ev.frame)
	o.speed = speed
	var hub: Node = world.get_node_or_null("Emotes") if world else null
	o.who = hub.who_of(int(ev.who)) if hub and from_who else null   # いなければ、包みは空から落ちてくる
	o.name = "Origami"
	o.transform = Transform3D(at.basis.orthonormalized(), at.origin)   # 置く先（main）は原点にある
	(world if world else get_parent()).add_child(o)


## 誰も乗っていない・つかんでいない・紐を持っていないソリだけ畳める
func _free(s: Node3D) -> bool:
	return s.riders.is_empty() and s.holders.is_empty() and s.rope_holder == null


## 実寸のソリを置く。wait コマのあいだは止めておく（広げる動きのあいだ）
func _place(kind: String, fabric: String, at: Vector3, yaw: float, wait: int, up := Vector3.UP, tag: Variant = 0, room := true, owner_id := -1) -> int:
	var id := _next_sled
	_next_sled += 1
	var s := Sled.new()
	s.kind = kind
	s.fabric = fabric
	s.crafted = true
	s.tag = tag
	s.owner_id = owner_id
	s.name = "MadeSled%d" % id
	s.transform = Transform3D(_basis(yaw, up), at + up * 0.08)   # 床に少し浮かせて置く（めり込むと床の下へ押し出される）
	if world and world.has_method("snow_lift"):
		s.snow_lift = Callable(world, "snow_lift")
	(world if world else get_parent()).add_child(s)
	s.set_meta("craft_id", id)
	if wait > 0:
		s.hold_still(wait)
	sleds[id] = s
	if room:
		_make_room(s)
	return id


## 米袋が足もとに、ぽんと出る（見た目だけ。12 コマで 4 コマ: ふくらんで、少し行き過ぎて戻る）
func _pop(s: RigidBody3D) -> void:
	var body: Node3D = s.get("_body")
	if body == null:
		return
	for k in [0.35, 1.15, 0.95, 1.0]:
		body.scale = Vector3(k, k, k)
		await get_tree().create_timer(1.0 / 12.0).timeout
		if not is_instance_valid(body):
			return


## 誰も乗っていない米袋から持ち主が遠く離れたら、ひとりでに帯に戻す（ホストの片付け）
func _physics_process(dt: float) -> void:
	if sack_out.is_empty():
		return
	var hub: Node = world.get_node_or_null("Emotes") if world else null
	for who in sack_out.keys():
		var gs := sack_sled(who)
		var owner: Node3D = hub.who_of(who) if hub else null
		if gs == null:
			sack_out.erase(who)
			continue
		var idle: bool = gs.riders.is_empty() and gs.holders.is_empty() and gs.rope_holder == null
		var far := owner == null or owner.global_position.distance_to(gs.global_position) > SACK_FAR
		_sack_far[who] = (_sack_far.get(who, 0.0) + dt) if idle and far else 0.0
		if _sack_far[who] > SACK_FAR_T:
			send({"kind": "sack_in", "who": who, "auto": true})


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
