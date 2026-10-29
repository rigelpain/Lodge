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


static func color(fabric: String) -> Color:
	return COLORS.get(fabric, COLORS["red"])


## ソリの形だけ（本物のソリでない、見せる・畳む動きの形）を布の色にする。sled.gd の _make_body と同じ差し替え
static func tint(root: Node, kind: String, fabric: String) -> void:
	if fabric == "":
		return
	var k: Dictionary = preload("res://sled.gd").KINDS.get(kind, {})
	var key: Color = k.get("color", COLORS["red"])
	if not color(fabric).is_equal_approx(key):
		Props.recolor(root, key, color(fabric), k.get("whole", false))
