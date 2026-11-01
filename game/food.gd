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
## 食べたときに熱（damp.gd の熱のゲージ, 0〜100。ふつうは 50）を上げる量（3 口に分けて、ひと口ごとに 1/3 ずつ。じんわり温まる）。
## 熱い汁物・麺のつゆがいちばん、温かい飲み物、揚げ物、焼き物、おにぎりの順に少ない。表は design/damp.md。
## 上がるのはふつうの少し上（60。まだバフにならない）までで、熱い汁物（SOUPS）だけはいちばん上（100）まで
## （2026-11-01 代表「ブーストまで戻せるように」。熱い汁物だけ）
const HEAT := {
	"ramen": 35.0, "udon": 35.0, "soba": 35.0, "clam": 35.0, "corn": 35.0, "oshiruko": 35.0,
	"cocoa": 25.0, "milktea": 25.0, "greentea": 25.0, "milk": 25.0,
	"taiyaki": 20.0, "nikuman": 20.0, "korokke": 20.0, "hashbrown": 20.0, "fries": 20.0,
	"hotsand": 15.0, "yakiimo": 15.0, "hotcake": 15.0, "sanma": 15.0, "kaki": 15.0, "yakisoba": 15.0,
	"onigiri": 10.0,
}
const SOUPS := ["ramen", "udon", "soba", "clam", "corn", "oshiruko"]


static func dish_glb(dish: String) -> String:
	return "res://props/food/%s.glb" % MENU[dish][0]


static func pellet_glb(dish: String) -> String:
	return "res://props/pellets/pellet_%s.glb" % dish


static func dish_icon(dish: String) -> String:
	return "res://props/food/icons/%s.png" % MENU[dish][0]


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


## 熱を上げる量（料理 1 つぶん）
static func heat(dish: String) -> float:
	return HEAT.get(dish, 0.0)


## 熱をどこまで上げるか（熱い汁物はいちばん上まで）
static func heat_cap(dish: String) -> float:
	return 100.0 if dish in SOUPS else 60.0
