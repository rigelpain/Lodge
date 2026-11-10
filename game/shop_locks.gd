extends RefCounted
## 店の品物のロック（まだ売っていない品。2026-11-10 代表「まだ売っていないを作るのもいいですね。一部LOCKしておくのもいい。じゃあLOCKしてるのを麻紐のつつみにして」）。
## LOCKED に品の名前（"店:品"）を書くと、その品はどの店でも麻ひもの包みの札になり（craft_icons.gd の wrap_card）、選べず、買えない（craft.gd でホストも断る）。
## どの品をロックするか、何で解けるかは代表が決める。まだ決めていないので空（design/shop-buy-look/README.md に案の一覧）。
## 山師の棚の on が false の品目（mountain_goods.gd）も、同じロックとして扱う。
##
## 品の名前（key_of と、各店の画面が使う）:
##   型紙 "pattern:<sled>"・布 "fabric:<fabric>"（ソリ屋）、山師の道具 "mountain:<kind>"、滑りあとの柄 "stitch:<name>"（見本帳）、
##   雪玉の柄 "ball:<name>"（山師）、頭・肩の小物とミニオン "pal:<key>"（紙細工屋さん・山師の連れ）、提灯 "lantern:<look>"（紙細工屋さん）、
##   食べ物 "food:<dish>"（雪だるまの店）

const MountainGoods := preload("res://mountain_goods.gd")

const LOCKED: Array[String] = []

## 確かめ用（起動の引数 --lock=名前,名前。main.gd が入れる）
static var extra: Array = []


static func locked(key: String) -> bool:
	if key in LOCKED or key in extra:
		return true
	if key.begins_with("mountain:"):
		var kind := key.trim_prefix("mountain:")
		return MountainGoods.has(kind) and not MountainGoods.sold(kind)
	return false


## 買う出来事（craft.gd）の品の名前（買う出来事でなければ ""）
static func key_of(ev: Dictionary) -> String:
	var it: Dictionary = ev.get("item", {}) if ev.get("item") is Dictionary else {}
	match String(ev.get("kind", "")):
		"buy":
			return item_key(it)
		"stitch_buy":
			return "stitch:" + String(ev.get("stitch", ""))
		"ball_stitch_buy":
			return "ball:" + String(ev.get("stitch", ""))
		"pal_buy":
			return "pal:" + String(ev.get("key", ""))
		"lantern_buy":
			return "lantern:" + String(ev.get("look", ""))
		"food_buy":
			return "food:" + String(it.get("dish", ""))
	return ""


## 持ち物の品（craft.gd の buy の item）の名前
static func item_key(it: Dictionary) -> String:
	match String(it.get("kind", "")):
		"pattern":
			return "pattern:" + String(it.get("sled", ""))
		"fabric":
			return "fabric:" + String(it.get("fabric", ""))
	return "mountain:" + String(it.get("kind", ""))
