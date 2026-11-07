extends RefCounted
## 布の色（ソリのメインカラー）。売り子のおじさんが売る布と、ミシンで縫ったソリの色の表。
## 色を当てるのはソリの側（sled.gd の main_color・set_main_color と、props.gd の recolor）。ここは名前と色の表だけ。
## sled.gd の fabric に名前を入れると、そのソリのメインカラーになる。

const Props := preload("res://props.gd")

const ORDER := ["red", "navy", "mustard", "holly", "cream", "plum"]
const COLORS := {
	"red": Color("D2553A"),       # 元のソリの赤（props/common.py の felt_red）
	"navy": Color("34477E"),
	"mustard": Color("D8A43E"),
	"holly": Color("3F6B4A"),
	"cream": Color("EFE6D2"),
	"plum": Color("7A4A6E"),
}


## 見本帳（sled_book_ui.gd）で染めた色は "#RRGGBB" の名前で持つ。売っている布と同じ道（置き直し・畳んだ包み・立てかけ台・
## あとから入った人へ送る状態・札の絵）をそのまま通るように。元の布は sled.gd の base_fabric・持ち物の base に残す（脱色で戻す）
static func color(fabric: String) -> Color:
	if is_dyed(fabric):
		return Color.html(fabric)
	return COLORS.get(fabric, COLORS["red"])


static func is_dyed(fabric: String) -> bool:
	return fabric.begins_with("#") and Color.html_is_valid(fabric)


## 色 c の名前（"#RRGGBB"。透明は持たない）
static func dyed_name(c: Color) -> String:
	return "#" + Color(c, 1.0).to_html(false).to_upper()


## ソリの形だけ（本物のソリでない、見せる・畳む動きの形）を布の色にする。sled.gd の _make_body と同じ差し替え
static func tint(root: Node, kind: String, fabric: String) -> void:
	if fabric == "":
		return
	var k: Dictionary = preload("res://sled.gd").KINDS.get(kind, {})
	var key: Color = k.get("color", COLORS["red"])
	if not color(fabric).is_equal_approx(key):
		Props.recolor(root, key, color(fabric), k.get("whole", false))
