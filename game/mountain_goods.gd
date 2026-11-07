extends RefCounted
## 山男の棚（山の道具の品書き。2026-11-01 代表「そういう道具類を売ってくれる山男？山師？みたいなキャラが欲しい」）。
## 売り場は mountain_ui.gd、売り子は mountain_man.gd。買うのは craft.gd の buy（ほかの店と同じ出来事。お金はボタン）。
##
## 差しこみ口: 品目ごとに 1 行。item は持ち物に入る形（craft.gd の bags にそのまま入る）、price は木のボタンの何個分、
## on は売るかどうか。on が false の品目は、棚に薄い絵だけ並び（まだ入荷していない札）、買えない（ホストも断る）。
##   焚き火セット  品目・名前・値段・絵は campfire.gd（組む・燃える・乾かすも）
##   ペグ          品目（3 本の束）・名前・値段・絵は peg.gd（刺してソリを留めるのも）
##   双眼鏡        品目・名前・値段・絵は binoculars.gd（のぞくのは player.gd の peek）
##   手袋          雪玉ころがしの手袋 3 段（毛糸・フェルト・革）。名前・値段・性能・絵は gloves.gd。持ち物の場所は使わず、装備に入る（craft.gd の buy）
## 品目を足すときも、ここに 1 行足し、絵を draw に足す（持ち物の列の絵も craft_icons.gd の item がここを呼ぶ）。

const Icons := preload("res://hud_icons.gd")
const Campfire := preload("res://campfire.gd")
const Peg := preload("res://peg.gd")
const Binoculars := preload("res://binoculars.gd")
const Gloves := preload("res://gloves.gd")

const SHELF := [
	{"item": Campfire.ITEM, "price": Campfire.PRICE, "on": true},
	{"item": {"kind": Peg.KIND, "n": Peg.PACK}, "price": Peg.PRICE, "on": true},   # Peg.item() と同じ 1 束
	{"item": Binoculars.ITEM, "price": Binoculars.PRICE, "on": true},
	{"item": {"kind": "binoculars_far"}, "price": 500, "on": true},     # 値段は binoculars.gd の GRADES と同じ
	{"item": {"kind": "binoculars_night"}, "price": 1000, "on": true},
	{"item": {"kind": "gloves"}, "price": Gloves.GRADES["gloves"].price, "on": true},
	{"item": {"kind": "gloves_felt"}, "price": Gloves.GRADES["gloves_felt"].price, "on": true},
	{"item": {"kind": "gloves_leather"}, "price": Gloves.GRADES["gloves_leather"].price, "on": true},
]

## 確かめ用: true なら on でない品目も売る（--shelf-all。main.gd が入れる）
static var all_on := false


static func has(kind: String) -> bool:
	return entry(kind) != {}


static func entry(kind: String) -> Dictionary:
	for e in SHELF:
		if e.item.kind == kind:
			return e
	return {}


static func price(kind: String) -> int:
	return int(entry(kind).get("price", 99))


## 売っているか（棚にあって on）
static func sold(kind: String) -> bool:
	var e := entry(kind)
	return e != {} and (bool(e.on) or all_on)


## 持ち物の名前（日本語。持ち物の列の上に出す）
static func item_name(it: Dictionary) -> String:
	match it.get("kind", ""):
		"campfire":
			return Campfire.NAME
		"peg":
			return Peg.item_name(it)
		"binoculars", "binoculars_far", "binoculars_night":
			return Binoculars.item_name(it)
		"gloves", "gloves_felt", "gloves_leather":
			return Gloves.item_name(String(it.kind))
	return ""


## 品物の絵（64 × 64 の箱。中心が原点、y は下向き。Icons._o と _s は呼ぶ側が決める）
static func draw(ci: CanvasItem, it: Dictionary, a := 1.0) -> void:
	match it.get("kind", ""):
		"campfire":
			Campfire.icon(ci, Vector2.ZERO, 1.0, a)
		"peg":
			Peg.icon(ci, it, a)
		"binoculars", "binoculars_far", "binoculars_night":
			Binoculars.icon(ci, a, String(it.kind))
		"gloves", "gloves_felt", "gloves_leather":
			Gloves.icon(ci, String(it.kind), a)
