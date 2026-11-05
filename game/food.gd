extends RefCounted
## 雪だるまの食べ物屋の品書き（2026-11-01 代表と決めた。design/snowman-food/README.md）。
## 雪だるまはペレット（料理のもとの手芸の粒）を雪玉で売り、プレイヤーが厨房の装置で料理に仕上げる。
## 持ち物の形は {kind: "food", dish: <料理>, step: <済んだ調理の数>}。step が道の長さに届くと、できあがった料理

## 調理の装置（main.gd の KITCHEN の名前）: press プレス機・iron アイロン台・dryer 乾燥機・drink 衣類スチーマー
## [料理, 料理の glb, 調理の道（装置の順）, 値段（雪玉）]
const MENU := {
	"onigiri": ["onigiri_salmon", ["press"], 1],
	"taiyaki": ["taiyaki", ["press", "dryer"], 2],
	"nikuman": ["nikuman", ["press", "dryer"], 2],
	"korokke": ["korokke", ["press", "dryer"], 2],
	"hashbrown": ["hashbrown", ["press", "dryer"], 2],
	"fries": ["fries", ["press", "dryer"], 2],
	"hotsand": ["hotsand", ["iron"], 2],
	"yakiimo": ["yakiimo", ["iron"], 2],
	"hotcake": ["hotcake", ["iron"], 2],
	"sanma": ["sanma", ["iron"], 2],
	"kaki": ["kaki", ["iron"], 2],
	"yakisoba": ["yakisoba", ["dryer", "iron"], 2],
	"ramen": ["ramen_shoyu", ["dryer"], 3],
	"udon": ["udon", ["dryer"], 2],
	"soba": ["soba", ["dryer"], 2],
	"cocoa": ["mug_cocoa", ["drink"], 1],
	"oshiruko": ["oshiruko", ["drink"], 1],
	"corn": ["mug_corn", ["drink"], 1],
	"clam": ["clam_chowder", ["drink"], 1],
	"greentea": ["yunomi_navy", ["drink"], 1],
	"milk": ["mug_milk", ["drink"], 1],
	"milktea": ["mug_milktea", ["drink"], 1],
}
## 売り場の画面の並び（品書きの順）
const ORDER := ["onigiri", "taiyaki", "nikuman", "korokke", "hashbrown", "fries", "hotsand", "yakiimo", "hotcake", "sanma", "kaki",
		"yakisoba", "ramen", "udon", "soba", "cocoa", "oshiruko", "corn", "clam", "greentea", "milk", "milktea"]
## 乾燥機で揚げる料理（ほかは茹でる）。音とコマの見せ方が変わる
const FRIED := ["taiyaki", "nikuman", "korokke", "hashbrown", "fries"]
const DRINKS := ["cocoa", "oshiruko", "corn", "clam", "greentea", "milk", "milktea"]
const NOODLES := ["ramen", "udon", "soba", "yakisoba"]
const CRISP := ["taiyaki", "korokke", "hashbrown", "fries", "hotsand"]   # 皮がぱりっとした物（さくっ）
const BITES := 3             # 3 口で食べ終わる
## 手に持つ向き（度。形の正面が自分へ向き、食べ口が見えるように）と、手からのずれ・大きさ。ないものは正面を自分へ向けるだけ
const HOLD := {
	"onigiri": {"rot": Vector3(-8, 180, 0), "pos": Vector3(-0.05, -0.05, 0.0), "scale": 3.0},
	"nikuman": {"rot": Vector3(-20, 180, 0), "pos": Vector3(-0.05, -0.05, 0.0), "scale": 2.4},
	"taiyaki": {"rot": Vector3(68, 0, 18), "yaw": 180.0, "pos": Vector3(-0.07, 0.02, 0.0), "scale": 2.6},
	"korokke": {"rot": Vector3(-10, 180, 0), "pos": Vector3(-0.05, -0.06, 0.0), "scale": 2.5},
	"hashbrown": {"rot": Vector3(-10, 180, 0), "pos": Vector3(-0.05, -0.05, 0.0), "scale": 2.5},
	"fries": {"rot": Vector3(-14, 180, 0), "pos": Vector3(-0.05, -0.08, 0.0), "scale": 2.0},
	"hotsand": {"rot": Vector3(-10, 180, 0), "pos": Vector3(-0.05, -0.06, 0.0), "scale": 2.6},
	"yakiimo": {"rot": Vector3(-14, 180, -22), "pos": Vector3(-0.04, -0.08, 0.0), "scale": 2.0},
	"ramen": {"rot": Vector3(-38, 180, 0), "pos": Vector3(-0.1, 0.0, 0.0), "scale": 1.5},
	"udon": {"rot": Vector3(-38, 180, 0), "pos": Vector3(-0.1, 0.0, 0.0), "scale": 1.5},
	"soba": {"rot": Vector3(-38, 180, 0), "pos": Vector3(-0.1, 0.0, 0.0), "scale": 1.5},
	"yakisoba": {"rot": Vector3(-38, 180, 0), "pos": Vector3(-0.1, 0.0, 0.0), "scale": 1.5},
	"hotcake": {"rot": Vector3(-38, 180, 0), "pos": Vector3(-0.09, -0.02, 0.0), "scale": 1.6},
	"sanma": {"rot": Vector3(-42, 180, 0), "pos": Vector3(-0.1, 0.02, 0.0), "scale": 1.4},
	"kaki": {"rot": Vector3(-38, 180, 0), "pos": Vector3(-0.09, 0.0, 0.0), "scale": 1.35},
	"oshiruko": {"rot": Vector3(40, 0, 0), "pos": Vector3(-0.07, -0.05, 0.0), "scale": 1.7},
	"clam": {"rot": Vector3(40, 0, 0), "pos": Vector3(-0.08, -0.05, 0.0), "scale": 1.6},
}
const HOLD_DRINK := {"rot": Vector3(32, 0, -6), "pos": Vector3(-0.09, -0.06, 0.0), "scale": 2.1}   # 飲み物は取っ手を右（手の側）へ、中が見えるように傾ける
const HOLD_DEFAULT := {"rot": Vector3(-10, 180, 0), "pos": Vector3(-0.05, -0.05, 0.0), "scale": 2.2}


## 料理の glb。bites（食べた口数）を渡すと、食べている途中の形（<名前>_b1・_b2。かじった跡と中身が見える）があればそれを返す
static func dish_glb(dish: String, bites := 0) -> String:
	return "res://props/food/%s.glb" % _model(dish, bites)


static func _model(dish: String, bites: int) -> String:
	var base: String = MENU[dish][0]
	var b := clampi(bites, 0, BITES - 1)
	if b > 0 and ResourceLoader.exists("res://props/food/%s_b%d.glb" % [base, b]):
		return "%s_b%d" % [base, b]
	return base


static func pellet_glb(dish: String) -> String:
	return "res://props/pellets/pellet_%s.glb" % dish


static func dish_icon(dish: String, bites := 0) -> String:
	return "res://props/food/icons/%s.png" % _model(dish, bites)


static func pellet_icon(dish: String) -> String:
	return "res://props/pellets/icons/pellet_%s.png" % dish


static func route(dish: String) -> Array:
	return MENU[dish][1]


static func price(dish: String) -> int:
	return MENU[dish][2]


## 持ち物 it が、次に入れる装置（できあがっていれば ""）
static func next_station(it: Dictionary) -> String:
	if it.get("kind") != "food" or not MENU.has(it.get("dish", "")):
		return ""
	var r := route(it.dish)
	var s: int = it.get("step", 0)
	return r[s] if s < r.size() else ""


static func done(it: Dictionary) -> bool:
	return it.get("kind") == "food" and MENU.has(it.get("dish", "")) and int(it.get("step", 0)) >= route(it.dish).size()


static func item(dish: String) -> Dictionary:
	return {"kind": "food", "dish": dish, "step": 0}


## ひと口の音（sound/gen/eat.py）: [名前, 数]
static func bite_sound(dish: String) -> Array:
	if dish in DRINKS:
		return ["eat_sip", 2]
	if dish in NOODLES:
		return ["eat_slurp", 2]
	if dish in CRISP:
		return ["eat_crunch", 4]
	return ["eat_chew", 4]
