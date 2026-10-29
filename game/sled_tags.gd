extends RefCounted
## 名札（タグ）。文字は使わない。ロッジの名札（DESIGNS の番号）と、一人一つの自分の名札（部品の組み合わせ）がある。
##   自分の名札の部品（PARTS）: 形 × 素材（紙・フェルト・布・和紙・革・木）× 地の色 × 模様（縞・水玉・格子・帯・市松・青海波・
##       麻の葉・矢絣・七宝・亀甲・継ぎはぎ）× 模様の色 × 縁の作り（並縫い・ジグザグ・クロス・ブランケット・レース・ミシン目・二本）×
##       縁の糸 × 吊るす糸 × 飾り（ボタン・リボン・鈴・房・ぼんぼん・ビーズ・木のクリップ・羽根）× 判子 ×
##       判子の作り（判子・フェルトのアップリケ・刺繍・切り抜き・透けるフィルムの窓）× 押し方（隅・まんなか・対角・三つ並べ・ずらし重ね・散らし）
##   部品ごとに、前から STARTER の数までは最初から使える。後ろは「あとで手に入る」部品で、手に入れた人だけが使える
##   （craft.gd の tag_owned。手に入れる仕組みはまだなく、値の目安だけ COST に置く）
##   広げたソリ: 手すりの前の結び目から、小さなタグを糸で吊るす（hang）
##   畳んだソリ: 包みにも同じタグを付け、タグの窓に広げた姿をくるくる回して見せる（turntable。12 コマで回る）
##   画面の左下の札（hud.gd）: 自分の名札の上に針山の方位磁針
## 柄の番号はソリの tag（sled.gd）。最初のソリは 0（ロッジの名札）、縫ったソリ・米袋は持ち主の名札。

const Icons := preload("res://hud_icons.gd")
const Doll := preload("res://doll.gd")

const DESIGNS := [
	{"shape": "cut", "paper": Color(0.96, 0.93, 0.86), "edge": Color(0.20, 0.25, 0.42), "string": Color(0.80, 0.24, 0.20), "motif": "none", "ink": Color(0.80, 0.24, 0.20)},
	{"shape": "round", "paper": Color(0.86, 0.72, 0.52), "edge": Color(0.45, 0.30, 0.18), "string": Color(0.95, 0.92, 0.84), "motif": "snow", "ink": Color(0.97, 0.97, 1.0)},
	{"shape": "pinked", "paper": Color(0.80, 0.88, 0.95), "edge": Color(0.24, 0.32, 0.55), "string": Color(0.88, 0.66, 0.20), "motif": "star", "ink": Color(0.88, 0.66, 0.20)},
	{"shape": "ticket", "paper": Color(0.97, 0.88, 0.80), "edge": Color(0.72, 0.30, 0.24), "string": Color(0.30, 0.42, 0.32), "motif": "pine", "ink": Color(0.25, 0.45, 0.30)},
	{"shape": "flag", "paper": Color(0.30, 0.38, 0.62), "edge": Color(0.95, 0.92, 0.84), "string": Color(0.95, 0.92, 0.84), "motif": "dots", "ink": Color(0.95, 0.92, 0.84)},
	{"shape": "scallop", "paper": Color(0.95, 0.80, 0.82), "edge": Color(0.62, 0.28, 0.38), "string": Color(0.62, 0.28, 0.38), "motif": "heart", "ink": Color(0.80, 0.24, 0.30)},
	{"shape": "hex", "paper": Color(0.88, 0.84, 0.50), "edge": Color(0.40, 0.32, 0.16), "string": Color(0.20, 0.25, 0.42), "motif": "mitten", "ink": Color(0.72, 0.30, 0.24)},
	{"shape": "round", "paper": Color(0.36, 0.42, 0.33), "edge": Color(0.95, 0.92, 0.84), "string": Color(0.86, 0.74, 0.48), "motif": "stripe", "ink": Color(0.86, 0.74, 0.48)},
	{"shape": "pinked", "paper": Color(0.96, 0.93, 0.86), "edge": Color(0.36, 0.42, 0.33), "string": Color(0.36, 0.42, 0.33), "motif": "pine", "ink": Color(0.36, 0.42, 0.33)},
	{"shape": "ticket", "paper": Color(0.47, 0.30, 0.45), "edge": Color(0.95, 0.85, 0.60), "string": Color(0.95, 0.85, 0.60), "motif": "snow", "ink": Color(0.95, 0.92, 0.84)},
	{"shape": "flag", "paper": Color(0.80, 0.24, 0.20), "edge": Color(0.98, 0.96, 0.92), "string": Color(0.20, 0.25, 0.42), "motif": "star", "ink": Color(0.98, 0.96, 0.92)},
	{"shape": "scallop", "paper": Color(0.80, 0.90, 0.86), "edge": Color(0.25, 0.45, 0.42), "string": Color(0.80, 0.24, 0.20), "motif": "dots", "ink": Color(0.25, 0.45, 0.42)},
	{"shape": "cut", "paper": Color(0.55, 0.38, 0.22), "edge": Color(0.95, 0.92, 0.84), "string": Color(0.95, 0.92, 0.84), "motif": "mitten", "ink": Color(0.95, 0.92, 0.84)},
]
## ロッジの名札（DESIGNS）の、書いていない部品
const LODGE := {"material": "paper", "pattern": "none", "stitch": "running", "deco": "none", "print": "ink", "layout": "corner"}

const TEX_SIZE := Vector2i(192, 128)   # 吊るすタグの絵
const TURN_SIZE := Vector2i(160, 160)  # 回る図
const TURN_STEP := 2                   # 何コマごとに回すか（12 コマ／秒の 2 コマ = 6 回／秒）
const TURN_DEG := 15.0                 # 1 回に回す角度

static var _holder: Node
static var _tags := {}                 # 柄の番号 → ViewportTexture
static var _turns := {}                # "kind|fabric" → Turntable
static var _geo := {}                  # 形・模様・素材・縁・大きさ → 切り抜いた模様・素材の筋・縁の目（毎回の計算を省く）
static var _mstyle := "ink"            # 判子の描き方（motif の中で使う）: ink（平らな判子）/ fill（フェルト）/ embroidery（刺繍）/ cutout（切り抜き）


## 自分の名札の部品（装備の画面で組み合わせる）。名札の柄は、DESIGNS の番号（int。0 はロッジの名札）か、
## 部品の番号の辞書 {shape, material, paper, ...}（自分の名札。書いていない部品は DEFAULT）。-1 は名札なし
const SHAPES := ["cut", "round", "pinked", "ticket", "flag", "scallop", "hex",
	"oval", "stamp", "torn", "cloud", "frame", "leaf"]
const MATERIALS := ["paper", "felt", "cloth", "washi", "leather", "wood"]
const PAPERS := [Color(0.96, 0.93, 0.86), Color(0.86, 0.72, 0.52), Color(0.80, 0.88, 0.95), Color(0.97, 0.88, 0.80),
	Color(0.30, 0.38, 0.62), Color(0.95, 0.80, 0.82), Color(0.88, 0.84, 0.50), Color(0.36, 0.42, 0.33), Color(0.47, 0.30, 0.45),
	Color(0.80, 0.24, 0.20), Color(0.80, 0.90, 0.86), Color(0.55, 0.38, 0.22),
	Color(0.18, 0.18, 0.22), Color(0.80, 0.64, 0.32), Color(0.58, 0.74, 0.86), Color(0.92, 0.58, 0.34)]   # 墨・金茶・空・柿
const THREADS := [Color(0.20, 0.25, 0.42), Color(0.80, 0.24, 0.20), Color(0.95, 0.92, 0.84), Color(0.88, 0.66, 0.20),
	Color(0.25, 0.45, 0.30), Color(0.62, 0.28, 0.38), Color(0.45, 0.30, 0.18), Color(0.25, 0.45, 0.42),
	Color(0.86, 0.72, 0.32), Color(0.80, 0.82, 0.86), Color(0.14, 0.13, 0.16)]   # 金糸・銀糸・黒
const PATTERNS := ["none", "stripe", "dots", "check", "band",
	"ichimatsu", "seigaiha", "asanoha", "yagasuri", "shippo", "kikko", "patchwork"]
const STITCHES := ["running", "none", "zigzag", "cross", "blanket", "lace", "perf", "double"]
const DECOS := ["none", "button", "ribbon", "bell", "tassel", "pompom", "beads", "clip", "feather"]
const MOTIFS := ["none", "snow", "star", "pine", "heart", "dots", "stripe", "mitten",
	"moon", "mountain", "plum", "bird", "acorn", "rabbit"]
const PRINTS := ["ink", "applique", "embroidery", "cutout", "window"]
const LAYOUTS := ["corner", "center", "pair", "row", "overlap", "scatter"]
const PARTS := ["shape", "material", "paper", "pattern", "accent", "stitch", "edge", "string", "deco", "motif", "print", "layout", "cushion"]
## 装備の画面のページ: 形と素材 / 模様 / 縁と糸 / 飾りと判子
const PAGES := [["shape", "material", "paper"], ["pattern", "accent"], ["stitch", "edge", "string"], ["deco", "motif", "print", "layout", "cushion"]]
## 部品ごとの、最初から使える数（前から順に）。それより後ろは、あとで手に入る
const STARTER := {"shape": 7, "material": 3, "paper": 12, "pattern": 5, "accent": 12, "stitch": 4, "edge": 8, "string": 8,
	"deco": 3, "motif": 8, "print": 2, "layout": 4, "cushion": 7}
## あとで手に入る部品の値の目安（木のボタンの数）。報酬や店で配るときに使う
const COST := {"shape": 4, "material": 6, "paper": 2, "pattern": 5, "accent": 2, "stitch": 4, "edge": 3, "string": 2,
	"deco": 5, "motif": 3, "print": 6, "layout": 3, "cushion": 2}
const DEFAULT := {"shape": 0, "material": 0, "paper": 0, "pattern": 0, "accent": 4, "stitch": 0, "edge": 0, "string": 1,
	"deco": 0, "motif": 0, "print": 0, "layout": 0, "cushion": 1}
## 方位磁針のピンクッション（hud.gd の _draw_pillow・pin_cushion_3d.gd）の色。0 は名札の地の色（少し淡く）、ほかは淡い色
const CUSHIONS := [Color(0, 0, 0, 0), Color(0.96, 0.78, 0.82), Color(0.80, 0.89, 0.97), Color(0.97, 0.93, 0.82),
	Color(0.80, 0.93, 0.85), Color(0.88, 0.82, 0.95), Color(0.98, 0.94, 0.70)]


static func count() -> int:
	return DESIGNS.size()


## 部品の選べる物
static func options(part: String) -> Array:
	match part:
		"shape": return SHAPES
		"material": return MATERIALS
		"paper", "accent": return PAPERS
		"pattern": return PATTERNS
		"stitch": return STITCHES
		"deco": return DECOS
		"motif": return MOTIFS
		"print": return PRINTS
		"layout": return LAYOUTS
		"cushion": return CUSHIONS
	return THREADS


## 部品ごとの選べる数
static func part_count(part: String) -> int:
	return options(part).size()

## 方位磁針のピンクッションの色（自分の名札の cushion の部品）
static func cushion_color(d) -> Color:
	var i: int = int(d.get("cushion", DEFAULT.cushion)) if d is Dictionary else DEFAULT.cushion
	i = posmod(i, CUSHIONS.size())
	if i == 0:
		return design(d).paper.lerp(Color(1, 1, 1), 0.3)
	return CUSHIONS[i]


## 最初から使える部品か（でなければ、あとで手に入る部品）
static func is_starter(part: String, i: int) -> bool:
	return i >= 0 and i < int(STARTER.get(part, 0))


## 部品の値の目安（最初から使える物は 0）
static func cost(part: String, i: int) -> int:
	return 0 if is_starter(part, i) else int(COST.get(part, 0))


## 名札の柄を、描くための辞書 {shape, material, paper, pattern, accent, stitch, edge, string, deco, motif, print, layout, ink} にする
static func design(d) -> Dictionary:
	if d is Dictionary:
		var o := {}
		for part in PARTS:
			var opts := options(part)
			o[part] = opts[posmod(int(d.get(part, DEFAULT[part])), opts.size())]
		var paper: Color = o.paper
		var edge: Color = o.edge
		var ink := edge
		if absf(edge.get_luminance() - paper.get_luminance()) < 0.25:   # 判子は紙の上で読める色に
			ink = Color(0.98, 0.96, 0.92) if paper.get_luminance() < 0.5 else Color(0.20, 0.25, 0.42)
		o["ink"] = ink
		return o
	var base: Dictionary = DESIGNS[posmod(int(d), DESIGNS.size())]
	var lodge := LODGE.duplicate()
	lodge.merge(base, true)
	lodge["accent"] = base.paper
	return lodge


## 名札があるか（-1 は名札なし）
static func has_tag(d) -> bool:
	return d is Dictionary or int(d) >= 0


## 人の番号から決める、はじめの自分の名札（最初から使える部品だけ。装備の画面で変えられる）
static func default_design(who: int) -> Dictionary:
	var paper := posmod(who * 5 + 1, 12)
	return {"shape": posmod(who, 7), "material": posmod(who, 3), "paper": paper, "pattern": posmod(who * 2 + 1, 5),
		"accent": posmod(paper + 4 + posmod(who, 7), 12), "stitch": posmod(who * 3, 4), "edge": posmod(who * 3, 8),
		"string": posmod(who * 3 + 1, 8), "deco": posmod(who + 1, 3), "motif": posmod(who * 2 + 1, 8), "print": posmod(who, 2),
		"layout": posmod(who * 3 + 1, 4), "cushion": DEFAULT.cushion}


static func _key(d) -> String:
	return str(d) if d is Dictionary else str(posmod(int(d), DESIGNS.size()))


# ---- 形 ------------------------------------------------------------------------------

## タグの輪郭（rect の中。左に穴のある向き）。どの大きさでも自分と交わらない多角形（tools/tag_outline_check.gd で確かめる）
static func outline(r: Rect2, shape: String) -> PackedVector2Array:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var c := minf(h * 0.28, 26.0)
	match shape:
		"round":
			return Icons.rr(x, y, w, h, h * 0.22)
		"pinked":   # ぎざぎざの縁。辺ごとの歯の数は偶数にして、角はとがったまま、角の点は 1 度だけ（重ねると塗れない）
			var p := PackedVector2Array()
			var z := minf(4.0, minf(w, h) * 0.12)   # 歯の深さ（小さい名札では浅く）
			var n := maxi(2, int(w / 9.0))
			n += n % 2
			var m := maxi(2, int(h / 9.0))
			m += m % 2
			for i in n:
				p.append(Vector2(x + w * i / n, y + (0.0 if i % 2 == 0 else z)))
			for i in m:
				p.append(Vector2(x + w - (0.0 if i % 2 == 0 else z), y + h * i / m))
			for i in n:
				p.append(Vector2(x + w - w * i / n, y + h - (0.0 if i % 2 == 0 else z)))
			for i in m:
				p.append(Vector2(x + (0.0 if i % 2 == 0 else z), y + h - h * i / m))
			return _clean(p)
		"ticket":   # 両端に半円の切り欠き
			var p := PackedVector2Array([Vector2(x, y), Vector2(x + w, y)])
			for i in 9:
				var a := -PI / 2 + PI * i / 8.0
				p.append(Vector2(x + w, y + h / 2) + Vector2(-cos(a), sin(a)) * h * 0.16)
			p.append(Vector2(x + w, y + h))
			p.append(Vector2(x, y + h))
			for i in 9:
				var a := PI / 2 - PI * i / 8.0
				p.append(Vector2(x, y + h / 2) + Vector2(cos(a), sin(a)) * h * 0.16)
			return p
		"flag":     # 燕尾の旗
			return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w - h * 0.3, y + h / 2), Vector2(x + w, y + h), Vector2(x, y + h)])
		"scallop":  # 波の縁。波の高さと間は大きさに合わせる（小さい名札で、つぶれて 1〜2 点にならないよう）
			var p := PackedVector2Array()
			var ins := minf(6.0, minf(w, h) * 0.16)
			var inner := Rect2(x + ins, y + ins, w - ins * 2.0, h - ins * 2.0)
			var per := Icons.rr(inner.position.x, inner.position.y, inner.size.x, inner.size.y, inner.size.y * 0.3)
			var tot := _perimeter(per)
			var n := maxi(12, int(tot / maxf(3.0, ins * 1.17)))
			n += n % 2
			var ctr := inner.get_center()
			for i in n:
				var q := _along(per, tot * i / n)
				var out := (q - ctr).normalized()
				p.append(q + out * (ins if i % 2 == 0 else ins * 0.33))
			return _clean(p)
		"hex":
			return PackedVector2Array([Vector2(x + c, y), Vector2(x + w - c * 0.6, y), Vector2(x + w, y + h / 2), Vector2(x + w - c * 0.6, y + h),
					Vector2(x + c, y + h), Vector2(x, y + h / 2)])
		"oval":     # 楕円の刺繍ワッペン
			return Icons.ell(Vector2(x + w / 2.0, y + h / 2.0), w / 2.0, h / 2.0, 40)
		"stamp", "torn":   # 切手（縁にミシン目の半円の歯）/ ちぎった和紙（縁が細かく不揃い）。どちらも内側へだけ削る
			var p := PackedVector2Array()
			var b := minf(3.2, minf(w, h) * 0.07)
			var j := minf(3.0, minf(w, h) * 0.05)
			var st := maxf(2.0, minf(6.0, h * 0.06))
			var cs := [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
			for k in 4:
				var a0: Vector2 = cs[k]
				var a1: Vector2 = cs[(k + 1) % 4]
				var ln := a0.distance_to(a1)
				var dir := (a1 - a0) / ln
				var inward := Vector2(-dir.y, dir.x)
				p.append(a0)
				if shape == "stamp":
					var n := maxi(2, int(ln / (b * 3.4)))
					for i in n:
						var mc := a0 + dir * ln * (i + 0.5) / n
						for s in 7:
							var t := PI * s / 6.0
							p.append(mc - dir * cos(t) * b + inward * sin(t) * b)
				else:
					var n := maxi(2, int(ln / st))
					for i in range(1, n):
						var off := j * (0.5 + 0.5 * sin(i * 2.7 + k * 1.3) * cos(i * 1.1))
						p.append(a0 + dir * ln * i / n + inward * off)
			return _clean(p)
		"cloud":    # 雲: 丸いふくらみが並ぶ
			var p := PackedVector2Array()
			var bh := minf(h * 0.12, 9.0)
			var inner := Rect2(x + bh, y + bh, w - bh * 2.0, h - bh * 2.0)
			var per := Icons.rr(inner.position.x, inner.position.y, inner.size.x, inner.size.y, inner.size.y * 0.45)
			var tot := _perimeter(per)
			var n := maxi(8, int(tot / maxf(4.0, bh * 2.6)))
			var ctr := inner.get_center()
			for i in n:
				var q0 := _along(per, tot * i / n)
				var q1 := _along(per, tot * (i + 1) / n)
				var dir := (q1 - q0).normalized()
				var out := Vector2(dir.y, -dir.x)
				if out.dot((q0 + q1) / 2.0 - ctr) < 0.0:
					out = -out
				for s in 6:
					var t := s / 6.0
					p.append(q0.lerp(q1, t) + out * sin(t * PI) * bh)
			return _clean(p)
		"frame":    # 額: 四隅を内側へ丸く切る
			var q := minf(h * 0.2, 20.0)
			var p := PackedVector2Array()
			var corners := [[Vector2(x + w, y), PI], [Vector2(x + w, y + h), -PI / 2], [Vector2(x, y + h), 0.0], [Vector2(x, y), PI / 2]]
			for k in 4:
				var cc: Vector2 = corners[k][0]
				var a0: float = corners[k][1]
				for s in 6:
					var a := a0 - PI / 2 * s / 5.0
					p.append(cc + Vector2(cos(a), sin(a)) * q)
			return _clean(p)
		"leaf":     # 葉: 両端が細る（穴は茎の側に寄せる）
			var p := PackedVector2Array()
			var cy := y + h / 2.0
			for i in 17:
				var t := i / 16.0
				p.append(Vector2(x + w * t, cy - h / 2.0 * pow(sin(PI * t), 0.55)))
			for i in range(15, 0, -1):
				var t := i / 16.0
				p.append(Vector2(x + w * t, cy + h / 2.0 * pow(sin(PI * t), 0.55)))
			return _clean(p)
	return PackedVector2Array([Vector2(x + c, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x + c, y + h), Vector2(x, y + h - c), Vector2(x, y + c)])


## 穴の中心（形ごとに、紙の内に収まる所）
static func hole(r: Rect2, shape: String) -> Vector2:
	var c := minf(r.size.y * 0.28, 26.0)
	var hx := c * 0.62
	match shape:
		"ticket": hx += 4.0 + r.size.y * 0.18
		"oval", "cloud": hx += r.size.y * 0.14
		"leaf": hx = r.size.x * 0.17
		"stamp", "torn", "frame": hx += r.size.y * 0.05
	return r.position + Vector2(hx, r.size.y / 2.0)


## 続けて重なった点（と、終わりと始まりが同じ点）を除く。重なった点のある多角形は三角形に分けられず、塗れない
static func _clean(p: PackedVector2Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for q in p:
		if o.is_empty() or o[o.size() - 1].distance_to(q) > 0.05:
			o.append(q)
	while o.size() > 3 and o[o.size() - 1].distance_to(o[0]) <= 0.05:
		o.remove_at(o.size() - 1)
	return o


static func _perimeter(pts: PackedVector2Array) -> float:
	var tot := 0.0
	for i in pts.size():
		tot += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return tot


static func _along(pts: PackedVector2Array, d: float) -> Vector2:
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var l := a.distance_to(b)
		if d <= l:
			return a.lerp(b, d / maxf(l, 0.001))
		d -= l
	return pts[0]


# ---- 模様・素材・縁（大きさごとに 1 度だけ計算して、名札の左上を原点に持つ） ----------------------------

## 形・模様・素材・縁の作りと大きさから、描く物をまとめる: {pts, fill: [[多角形, 色の役]], lines: [[線の対, 色の役, 太さ]], under, stitch...}
static func _geometry(sz: Vector2, d: Dictionary) -> Dictionary:
	var key := "%s|%s|%s|%s|%d|%d" % [d.shape, d.pattern, d.material, d.stitch, roundi(sz.x * 2.0), roundi(sz.y * 2.0)]
	if _geo.has(key):
		return _geo[key]
	if _geo.size() > 400:
		_geo.clear()
	var R := Rect2(Vector2.ZERO, sz)
	var pts := outline(R, d.shape)
	var g := {"pts": pts, "fill": _pattern_fill(R, pts, d.pattern), "lines": _pattern_lines(R, pts, d.pattern)}
	g.lines.append_array(_material_lines(R, pts, d.material))
	g.merge(_stitch_geo(R, pts, d.stitch, hole(R, d.shape)))
	_geo[key] = g
	return g


static func _box(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


## poly を名札の形で切り抜いて、塗れる物だけ足す
static func _clip_fill(out: Array, poly: PackedVector2Array, pts: PackedVector2Array, role: String) -> void:
	for q in Geometry2D.intersect_polygons(poly, pts):
		if q.size() >= 3 and not Geometry2D.triangulate_polygon(q).is_empty():
			out.append([q, role])


## 線の対（2 点ずつ）を名札の形で切り抜く
static func _clip_segs(segs: PackedVector2Array, pts: PackedVector2Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for i in range(0, segs.size() - 1, 2):
		for pl in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([segs[i], segs[i + 1]]), pts):
			for k in pl.size() - 1:
				o.append(pl[k])
				o.append(pl[k + 1])
	return o


## 閉じた線を、線の対にして足す
static func _ring(segs: PackedVector2Array, poly: PackedVector2Array) -> void:
	for i in poly.size():
		segs.append(poly[i])
		segs.append(poly[(i + 1) % poly.size()])


## 面の模様（色の役: a 模様の色、a2 半分透かした模様の色、a3 明るい模様の色、mix 地と模様の間、p 地の色）
static func _pattern_fill(R: Rect2, pts: PackedVector2Array, pattern: String) -> Array:
	var w := R.size.x
	var h := R.size.y
	var u := maxf(h * 0.15, 5.0)
	var o := []
	match pattern:
		"stripe":   # 縞（縦）
			var x := u * 0.4
			while x < w:
				_clip_fill(o, _box(x, -1.0, u * 0.55, h + 2.0), pts, "a")
				x += u * 1.5
		"dots":     # 水玉
			var row := 0
			var y := u * 0.5
			while y < h + u:
				var x := u * (0.5 if row % 2 == 0 else 1.25)
				while x < w + u:
					_clip_fill(o, Icons.circ(Vector2(x, y), u * 0.3, 12), pts, "a")
					x += u * 1.5
				y += u * 1.3
				row += 1
		"check":    # 格子（ギンガム）: 縦と横の帯を半分透かして重ねる
			var x := u * 0.3
			while x < w:
				_clip_fill(o, _box(x, -1.0, u * 0.7, h + 2.0), pts, "a2")
				x += u * 1.4
			var y := u * 0.3
			while y < h:
				_clip_fill(o, _box(-1.0, y, w + 2.0, u * 0.7), pts, "a2")
				y += u * 1.4
		"band":     # 帯: まんなかを横切る太い帯と、両側の細い線
			var t := maxf(1.0, h * 0.03)
			_clip_fill(o, _box(-1.0, h * 0.38, w + 2.0, h * 0.24), pts, "a")
			_clip_fill(o, _box(-1.0, h * 0.38 - t * 2.6, w + 2.0, t), pts, "a")
			_clip_fill(o, _box(-1.0, h * 0.62 + t * 1.6, w + 2.0, t), pts, "a")
		"ichimatsu":   # 市松
			var s := u * 1.1
			for j in int(h / s) + 1:
				for i in int(w / s) + 1:
					if (i + j) % 2 == 0:
						_clip_fill(o, _box(i * s, j * s, s, s), pts, "a")
		"seigaiha":    # 青海波: 同じ心の半円の重なり。上の段から描き、下の段が下半分を隠す
			var s := u * 1.05
			var j := 0
			var y := -s
			while y < h + s:
				var x := -s + (s if j % 2 == 1 else 0.0)
				while x < w + s:
					var rings := [[1.0, "a"], [0.72, "p"], [0.44, "a"], [0.2, "p"]]
					for rg in rings:
						_clip_fill(o, Icons.circ(Vector2(x, y), s * rg[0], 20), pts, rg[1])
					x += s * 2.0
				y += s * 0.5
				j += 1
		"yagasuri":    # 矢絣: 列ごとに向きを変えた矢羽
			var cw := u * 1.3
			var ch := u * 1.8
			var i := 0
			var x := 0.0
			while x < w:
				if i % 2 == 0:
					var y := -ch
					while y < h + ch:
						_clip_fill(o, PackedVector2Array([Vector2(x, y), Vector2(x + cw / 2.0, y + cw * 0.45), Vector2(x + cw, y),
								Vector2(x + cw, y + ch * 0.5), Vector2(x + cw / 2.0, y + ch * 0.5 + cw * 0.45), Vector2(x, y + ch * 0.5)]), pts, "a")
						y += ch
				else:
					var y := -ch * 0.5
					while y < h + ch:
						_clip_fill(o, PackedVector2Array([Vector2(x, y + cw * 0.45), Vector2(x + cw / 2.0, y), Vector2(x + cw, y + cw * 0.45),
								Vector2(x + cw, y + ch * 0.5 + cw * 0.45), Vector2(x + cw / 2.0, y + ch * 0.5), Vector2(x, y + ch * 0.5 + cw * 0.45)]), pts, "a3")
						y += ch
				x += cw
				i += 1
		"patchwork":   # 継ぎはぎ: 斜めの縫い目で 4 枚の布に分ける
			var x1t := w * 0.40
			var x1b := w * 0.48
			var x2t := w * 0.74
			var x2b := w * 0.68
			_clip_fill(o, PackedVector2Array([Vector2(x1t, -1), Vector2(x2t, -1), Vector2(lerpf(x2t, x2b, 0.48), h * 0.48), Vector2(lerpf(x1t, x1b, 0.52), h * 0.52)]), pts, "a")
			_clip_fill(o, PackedVector2Array([Vector2(lerpf(x1t, x1b, 0.52), h * 0.52), Vector2(lerpf(x2t, x2b, 0.48), h * 0.48), Vector2(x2b, h + 1), Vector2(x1b, h + 1)]), pts, "mix")
			_clip_fill(o, PackedVector2Array([Vector2(x2t, -1), Vector2(w + 1, -1), Vector2(w + 1, h + 1), Vector2(x2b, h + 1)]), pts, "a3")
	return o


## 線の模様（麻の葉・七宝・亀甲）と、継ぎはぎの縫い目
static func _pattern_lines(R: Rect2, pts: PackedVector2Array, pattern: String) -> Array:
	var w := R.size.x
	var h := R.size.y
	var u := maxf(h * 0.22, 6.0)
	var lw := maxf(0.8, h * 0.012)
	var segs := PackedVector2Array()
	match pattern:
		"asanoha":    # 麻の葉: 三角の格子に、三角の真ん中から頂点への線
			var s := u * 1.3
			var th := s * sqrt(3.0) / 2.0
			for j in range(-1, int(h / th) + 2):
				var off0 := s * 0.5 * posmod(j, 2)
				var off1 := s * 0.5 * posmod(j + 1, 2)
				for i in range(-1, int(w / s) + 2):
					var a0 := Vector2(i * s + off0, j * th)
					var a1 := Vector2((i + 1) * s + off0, j * th)
					var b0 := Vector2(i * s + off1, (j + 1) * th)
					var b1 := Vector2((i + 1) * s + off1, (j + 1) * th)
					var tris := [[a0, a1, b0], [b0, b1, a1]] if off0 == 0.0 else [[a0, a1, b1], [b0, b1, a0]]
					for tri in tris:
						var cc: Vector2 = (tri[0] + tri[1] + tri[2]) / 3.0
						for v in tri:
							segs.append(cc)
							segs.append(v)
						_ring(segs, PackedVector2Array(tri))
		"shippo":     # 七宝: 円を四分の一ずつずらして重ねる
			var s := u * 1.25
			for j in range(-1, int(h / s) + 2):
				for i in range(-1, int(w / s) + 2):
					_ring(segs, Icons.circ(Vector2(i * s, j * s), s / sqrt(2.0), 20))
		"kikko":      # 亀甲: 六角の格子を二重に
			var hr := u * 0.8
			var dy := sqrt(3.0) * hr
			for i in range(-1, int(w / (hr * 1.5)) + 2):
				for j in range(-1, int(h / dy) + 2):
					var cc := Vector2(i * hr * 1.5, j * dy + (dy / 2.0 if posmod(i, 2) == 1 else 0.0))
					_ring(segs, Icons.circ(cc, hr, 6))
					_ring(segs, Icons.circ(cc, hr * 0.68, 6))
		"patchwork":  # 縫い目（縁の糸の色の並縫い）
			var x1t := w * 0.40
			var x1b := w * 0.48
			var x2t := w * 0.74
			var x2b := w * 0.68
			var seam := PackedVector2Array([Vector2(x1t, -1), Vector2(x1b, h + 1), Vector2(x2t, -1), Vector2(x2b, h + 1),
					Vector2(lerpf(x1t, x1b, 0.52), h * 0.52), Vector2(lerpf(x2t, x2b, 0.48), h * 0.48)])
			return [[_clip_segs(seam, pts), "seam", maxf(1.0, h * 0.012)]]
	if segs.is_empty():
		return []
	return [[_clip_segs(segs, pts), "a", lw]]


## 素材の筋（布の織り目・和紙の繊維・木目・革の毛穴）。小さい名札ではうるさいので描かない
static func _material_lines(R: Rect2, pts: PackedVector2Array, material: String) -> Array:
	var w := R.size.x
	var h := R.size.y
	if h < 36.0:
		return []
	var segs := PackedVector2Array()
	match material:
		"cloth":
			var sp := maxf(2.4, h * 0.035)
			var x := sp * 0.5
			while x < w:
				segs.append_array([Vector2(x, 0), Vector2(x, h)])
				x += sp
			var y := sp * 0.5
			while y < h:
				segs.append_array([Vector2(0, y), Vector2(w, y)])
				y += sp
			return [[_clip_segs(segs, pts), "dark", maxf(0.5, sp * 0.22)]]
		"washi":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var light := PackedVector2Array()
			var n := clampi(int(w * h / 300.0), 12, 60)
			for i in n:
				var p0 := Vector2(rng.randf() * w, rng.randf() * h)
				var a := rng.randf() * TAU
				var l := h * rng.randf_range(0.06, 0.18)
				var p1 := p0 + Vector2.from_angle(a) * l
				var p2 := p1 + Vector2.from_angle(a + rng.randf_range(-0.8, 0.8)) * l * 0.7
				if i % 3 != 0:
					light.append_array([p0, p1, p1, p2])
				else:
					segs.append_array([p0, p1, p1, p2])
			return [[_clip_segs(light, pts), "light", maxf(0.7, h * 0.008)], [_clip_segs(segs, pts), "dark", maxf(0.6, h * 0.006)]]
		"wood":
			var n := 7
			for k in n:
				var y0 := h * (k + 0.5) / n
				var prev := Vector2(-1, y0)
				for i in range(1, 25):
					var x := w * i / 24.0
					var bend := exp(-pow((x - w * 0.68) / (w * 0.12), 2.0)) * h * 0.08 * (1.0 if y0 < h * 0.38 else -1.0)
					var q := Vector2(x, y0 + sin(x / w * TAU * 1.2 + k * 0.9) * h * 0.025 + bend)
					segs.append_array([prev, q])
					prev = q
			_ring(segs, Icons.ell(Vector2(w * 0.68, h * 0.38), h * 0.07, h * 0.035, 12))
			return [[_clip_segs(segs, pts), "grain", maxf(0.8, h * 0.012)]]
		"leather":
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			for i in clampi(int(w * h / 120.0), 20, 160):
				var q := Vector2(rng.randf() * w, rng.randf() * h)
				segs.append_array([q, q + Vector2(0.7, 0.4)])
			return [[_clip_segs(segs, pts), "dark", maxf(0.9, h * 0.01)]]
	return []


## 縁の作り（縁の糸の色）: {under: [[多角形, 色の役]], dash: [[閉じた線, 目, 間, 太さ]], seg: 線の対, seg_w, dots: 点, dot_r}
static func _stitch_geo(R: Rect2, pts: PackedVector2Array, stitch: String, hp: Vector2) -> Dictionary:
	var h := R.size.y
	var e := minf(5.0, h * 0.05)
	var g := {"under": [], "dash": [], "seg_w": maxf(0.8, h * 0.008), "dot_r": maxf(0.8, h * 0.011)}
	var seg := PackedVector2Array()
	var dots := PackedVector2Array()
	var inset := _inset(pts, e)
	var run := [inset, maxf(5.0, h * 0.035), maxf(3.5, h * 0.025), maxf(1.2, h * 0.009)]
	match stitch:
		"running":
			g.dash.append(run)
		"double":
			g.dash.append(run)
			var in2 := _inset(pts, e * 2.3)
			if in2.size() >= 3:
				g.dash.append([in2, run[1] * 0.8, run[2], run[3] * 0.8])
		"zigzag":   # ミシンのジグザグ
			var s := _resample(inset, maxf(2.6, h * 0.028))
			var amp := maxf(1.0, h * 0.014)
			var prev := Vector2.ZERO
			for i in s.size() + 1:
				var q := s[i % s.size()]
				var tg := (s[(i + 1) % s.size()] - s[(i - 1 + s.size()) % s.size()]).normalized()
				var zz := q + Vector2(-tg.y, tg.x) * amp * (1.0 if i % 2 == 0 else -1.0)
				if i > 0:
					seg.append_array([prev, zz])
				prev = zz
		"cross":    # クロスステッチ
			var s := _resample(inset, maxf(4.0, h * 0.05))
			var k := maxf(1.3, h * 0.016)
			for q in s:
				seg.append_array([q + Vector2(-k, -k), q + Vector2(k, k), q + Vector2(-k, k), q + Vector2(k, -k)])
			g.seg_w = maxf(0.9, h * 0.009)
		"blanket":  # ブランケットステッチ: 縁を回る糸と、縁から内へまっすぐ入る目
			var s := _resample(pts, maxf(3.5, h * 0.045))
			var depth := maxf(2.2, h * 0.055)
			for i in s.size():
				var q := s[i]
				var nx := s[(i + 1) % s.size()]
				var tg := (nx - s[(i - 1 + s.size()) % s.size()]).normalized()
				var nrm := Vector2(-tg.y, tg.x)
				if not Geometry2D.is_point_in_polygon(q + nrm * 0.8, pts):
					nrm = -nrm
				seg.append_array([q, nx, q, q + nrm * depth])
			g.seg_w = maxf(0.9, h * 0.009)
		"lace":     # レースの縁: 外へ丸い山が並び、山ごとに小さな穴
			var lr := maxf(2.4, h * 0.042)
			var s := _resample(pts, lr * 1.5)
			var ctr := R.get_center()
			for i in s.size():
				var q := s[i]
				var tg := (s[(i + 1) % s.size()] - s[(i - 1 + s.size()) % s.size()]).normalized()
				var out := Vector2(tg.y, -tg.x)
				if out.dot(q - ctr) < 0.0:
					out = -out
				g.under.append([Icons.circ(q + out * lr * 0.25, lr, 10), "lace"])
				g.under.append([Icons.circ(q + out * lr * 0.55, lr * 0.28, 6), "lacehole"])
			var in1 := _inset(pts, maxf(1.5, e * 0.5))
			if in1.size() >= 3:
				g.dash.append([in1, run[1] * 0.7, run[2] * 0.7, run[3]])
		"perf":     # ミシン目の切り取り線（穴の側を切り取れる）と、並縫い
			g.dash.append(run)
			var c := minf(h * 0.28, 26.0)
			var tx := hp.x + c * 0.75
			var line := _clip_segs(PackedVector2Array([Vector2(tx, -1), Vector2(tx, h + 1)]), pts)
			var sp := maxf(3.0, h * 0.04)
			for i in range(0, line.size() - 1, 2):
				var a := line[i]
				var b := line[i + 1]
				var n := int(a.distance_to(b) / sp)
				for k in range(1, n):
					dots.append(a.lerp(b, float(k) / n))
	g["seg"] = seg
	g["dots"] = dots
	return g


static func _inset(pts: PackedVector2Array, e: float) -> PackedVector2Array:
	var best := PackedVector2Array()
	for q in Geometry2D.offset_polygon(pts, -e):
		if q.size() > best.size():
			best = q
	return best if best.size() >= 3 else pts


static func _resample(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var tot := _perimeter(poly)
	var n := maxi(8, int(tot / step))
	var o := PackedVector2Array()
	for i in n:
		o.append(_along(poly, tot * i / n))
	return o


## 素材ごとの面の色
static func _base_col(d: Dictionary) -> Color:
	var paper: Color = d.paper
	match d.material:
		"leather": return paper.darkened(0.08)
	return paper


## 色の役を色に
static func _role(d: Dictionary, role: String) -> Color:
	var paper := _base_col(d)
	var acc: Color = d.accent
	match role:
		"a": return acc
		"a2": return Color(acc, 0.5)
		"a3": return acc.lerp(Color(1, 1, 1), 0.3)
		"mix": return paper.lerp(acc, 0.5)
		"p": return paper
		"dark": return Color(paper.darkened(0.18), 0.45)
		"light": return Color(paper.lightened(0.45), 0.6)
		"grain": return Color(paper.darkened(0.3), 0.55)
		"seam": return d.edge
		"lace": return Color(0.98, 0.97, 0.93)
		"lacehole": return Color(0.78, 0.74, 0.66)
	return acc


# ---- 描く ------------------------------------------------------------------------------

## タグを描く（画面の px の rect）。穴と糸の輪も。stamp で判子を押す
## window で、名札の中に無地の窓（window_rect）を敷き、その窓の rect（画面の px）を返す。窓のないときは r を返す
static func draw_tag(ci: CanvasItem, r: Rect2, idx, a := 1.0, stamp := true, window := false) -> Rect2:
	var d := design(idx)
	_face(ci, r.position, r.size, d, a)
	var R := Rect2(Vector2.ZERO, r.size)
	var hp := hole(R, d.shape)
	var h := r.size.y
	var wr := r
	if window:
		if d.deco in ["tassel", "feather"]:   # 面に垂れる飾りは、窓の下に差し込む（窓の中の絵を隠さない）
			Icons.screen()
			ci.draw_set_transform(r.position)
			_deco(ci, d, R, hp, a)
		wr = window_rect(r, d.shape)
		_draw_window(ci, r.position, Rect2(wr.position - r.position, wr.size), d, h, a)
	if stamp and d.motif != "none" and not window:
		_stamps(ci, r.position, R, d, hp, a)
	Icons.screen()
	ci.draw_set_transform(r.position)
	var c := minf(h * 0.28, 26.0)
	var hr := maxf(h * 0.038, 3.0)
	if d.deco == "button":
		_deco(ci, d, R, hp, a)
	ci.draw_circle(hp, hr * 1.5, Color(Icons.PAPER_EDGE, a))
	ci.draw_circle(hp, hr, Color(0.35, 0.30, 0.28, 0.85 * a))
	var loop := PackedVector2Array()
	for i in 16:
		var t := i / 15.0
		loop.append(hp + Vector2(-t * c * 0.85, sin(t * PI) * -c * 0.38 - t * c * 0.23))
	Icons.thread(ci, loop, d.string, maxf(1.6, h * 0.012), a)
	if d.deco != "button" and not (window and d.deco in ["tassel", "feather"]):
		_deco(ci, d, R, hp, a, loop)
	Icons.screen()
	ci.draw_set_transform(Vector2.ZERO)
	return wr


## 窓の地の色（名札の地・柄・素材に関わらず、いつも同じ明るさ。丘の雪・印・人の形が読める）
const WINDOW := Color(0.97, 0.96, 0.93)


## 名札の中の、情報を描く無地の窓（r の中、画面の px）。穴と糸の輪より右の、形の縁の内に収まる角の丸い四角。
## 楕円・葉・雲・旗の切れ込み・切符の切り欠きなどで縁からはみ出す辺だけを縮める。形と大きさごとに覚えておく
static func window_rect(r: Rect2, shape: String) -> Rect2:
	var key := "win|%s|%d|%d" % [shape, roundi(r.size.x * 2.0), roundi(r.size.y * 2.0)]
	if not _geo.has(key):
		var R := Rect2(Vector2.ZERO, r.size)
		var h := R.size.y
		var c := minf(h * 0.28, 26.0)
		var m := maxf(2.5, h * 0.075)
		var x0 := hole(R, shape).x + c * 0.62 + maxf(2.0, h * 0.02)
		var win := Rect2(x0, m, R.size.x - m - x0, h - m * 2.0)
		var inner := _inset(outline(R, shape), maxf(2.0, h * 0.04))
		for it in 160:
			var out := 0.0
			var push := {"l": false, "r": false, "t": false, "b": false}
			for q in Geometry2D.clip_polygons(_window_poly(win), inner):
				var ar := absf(_area(q))
				if ar < win.get_area() * 0.0005:
					continue
				out += ar
				var dv := (_centroid(q) - win.get_center()) / (win.size / 2.0)
				var hx := absf(dv.x) > 0.55
				var vy := absf(dv.y) > 0.55
				if not hx and not vy:
					hx = absf(dv.x) >= absf(dv.y)
					vy = not hx
				if hx:
					push["r" if dv.x > 0.0 else "l"] = true
				if vy:
					push["b" if dv.y > 0.0 else "t"] = true
			if out <= 0.0:
				break
			var sx := win.size.x * 0.015
			var sy := win.size.y * 0.015
			if push.l:
				win.position.x += sx
				win.size.x -= sx
			if push.r:
				win.size.x -= sx
			if push.t:
				win.position.y += sy
				win.size.y -= sy
			if push.b:
				win.size.y -= sy
		_geo[key] = win
	var w: Rect2 = _geo[key]
	return Rect2(r.position + w.position, w.size)


static func _window_poly(win: Rect2) -> PackedVector2Array:
	return Icons.rr(win.position.x, win.position.y, win.size.x, win.size.y, minf(win.size.x, win.size.y) * 0.12)


static func _area(q: PackedVector2Array) -> float:
	var s := 0.0
	for i in q.size():
		s += q[i].cross(q[(i + 1) % q.size()])
	return s / 2.0


static func _centroid(q: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in q:
		c += p
	return c / maxf(q.size(), 1)


## 窓を、名札の素材に合わせた手芸の形で描く（wr は名札の左上からの rect）: 紙・和紙・木は貼った紙のラベル（角を紙テープで留める）、
## フェルト・布は白い布の当て布（並縫いで縫い付け）、革は縫い付けた窓（二本の並縫い）。地の色はいつも WINDOW
static func _draw_window(ci: CanvasItem, org: Vector2, wr: Rect2, d: Dictionary, h: float, a: float) -> void:
	Icons.screen()
	ci.draw_set_transform(org)
	var pts := _window_poly(wr)
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(0.7, 1.2) * maxf(1.0, h / 120.0))
	ci.draw_colored_polygon(sh, Color(Icons.SHADOW, 0.32 * a))
	ci.draw_colored_polygon(pts, Color(WINDOW, a))
	var rim := pts.duplicate()
	rim.append(pts[0])
	ci.draw_polyline(rim, Color(WINDOW.darkened(0.3), 0.7 * a), maxf(1.0, h * 0.008), true)
	var th := _readable(d.edge, WINDOW)
	var run := [maxf(4.0, h * 0.03), maxf(2.8, h * 0.022), maxf(1.0, h * 0.009)]
	match d.material:
		"felt", "cloth":
			Icons.dashes(ci, _inset(pts, maxf(2.0, h * 0.022)), Color(th, 0.8), run[2], run[0], run[1], a, true)
		"leather":
			Icons.dashes(ci, _inset(pts, maxf(2.0, h * 0.02)), Color(th, 0.8), run[2], run[0], run[1], a, true)
			Icons.dashes(ci, _inset(pts, maxf(3.6, h * 0.045)), Color(th, 0.6), run[2] * 0.8, run[0] * 0.8, run[1], a, true)
		_:   # 紙テープを左上と右下の角に斜めに
			var tw := maxf(8.0, h * 0.2)
			var tt := maxf(3.0, h * 0.07)
			for k in 2:
				var at := wr.position + Vector2(tw * 0.2, tt * 0.6) if k == 0 else wr.end - Vector2(tw * 0.2, tt * 0.6)
				var tape := Icons.xf(PackedVector2Array([Vector2(-tw / 2.0, -tt / 2.0), Vector2(tw / 2.0, -tt / 2.0), Vector2(tw / 2.0, tt / 2.0), Vector2(-tw / 2.0, tt / 2.0)]), -0.6, at)
				ci.draw_colored_polygon(tape, Color(0.93, 0.86, 0.68, 0.8 * a))


## 名札の面: 下敷き（レース・和紙の毛羽）、素材の面、模様、素材の筋、縁。大きさ sz の名札を、org を左上に zoom 倍で描く。
## 描いたあと、描く原点は org のまま
static func _face(ci: CanvasItem, org: Vector2, sz: Vector2, d: Dictionary, a := 1.0, zoom := 1.0) -> void:
	var g := _geometry(sz, d)
	var pts: PackedVector2Array = g.pts
	var h := sz.y
	var base := _base_col(d)
	Icons.screen()
	ci.draw_set_transform(org, 0.0, Vector2.ONE * zoom)
	for u in g.under:
		ci.draw_colored_polygon(u[0], Color(_role(d, u[1]), a))
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(0.9, 1.4))
	ci.draw_colored_polygon(sh, Color(Icons.SHADOW, 0.26 * a))
	if d.material == "washi":   # 和紙の毛羽立った縁
		var soft := Geometry2D.offset_polygon(pts, maxf(0.8, h * 0.012), Geometry2D.JOIN_ROUND)
		if soft.size() > 0:
			ci.draw_colored_polygon(soft[0], Color(base.lightened(0.35), 0.55 * a))
	if d.material in ["felt", "cloth"]:
		var uv := PackedVector2Array()
		for p in pts:
			uv.append(p / 22.0)
		ci.draw_colored_polygon(pts, Color(base, a), uv, Icons.felt())
	else:
		ci.draw_colored_polygon(pts, Color(base, a))
	for f in g.fill:
		var col := _role(d, f[1])
		ci.draw_colored_polygon(f[0], Color(col, col.a * a))
	for l in g.lines:
		if l[0].size() < 2:
			continue
		var col := _role(d, l[1])
		if l[1] == "seam":
			for i in range(0, l[0].size() - 1, 2):
				Icons.dashes(ci, PackedVector2Array([l[0][i], l[0][i + 1]]), col, l[2], maxf(3.0, h * 0.03), maxf(2.0, h * 0.02), a)
		else:
			ci.draw_multiline(l[0], Color(col, col.a * a), l[2], true)
	var rim := pts.duplicate()
	rim.append(pts[0])
	match d.material:
		"felt":
			ci.draw_polyline(rim, Color(base.lightened(0.25), 0.45 * a), maxf(1.3, h * 0.016), true)
		"cloth":
			ci.draw_polyline(rim, Color(base.lightened(0.2), 0.4 * a), 1.0, true)
		"leather":   # 磨いた縁（コバ）
			ci.draw_polyline(rim, Color(base.darkened(0.35), 0.6 * a), maxf(1.5, h * 0.03), true)
		"wood":
			ci.draw_polyline(rim, Color(base.darkened(0.3), 0.7 * a), maxf(1.0, h * 0.014), true)
		"paper":
			ci.draw_polyline(rim, Color(base.darkened(0.12), 0.5 * a), 1.0, true)
	# 縁の作り
	var edge: Color = d.edge
	for ds in g.dash:
		Icons.dashes(ci, ds[0], Color(edge, 0.7), ds[3], ds[1], ds[2], a, true)
	if g.seg.size() >= 2:
		ci.draw_multiline(g.seg, Color(edge, 0.85 * a), g.seg_w, true)
	for q in g.dots:
		ci.draw_circle(q, g.dot_r, Color(Icons.SHADOW, 0.5 * a))


## 判子を押し方の位置に押す
static func _stamps(ci: CanvasItem, org: Vector2, R: Rect2, d: Dictionary, hp: Vector2, a: float) -> void:
	var h := R.size.y
	var s := minf(h * 0.30, 40.0)
	var lx := hp.x + minf(h * 0.28, 26.0) * 0.7
	var spots := _fit_spots(d, R, lx, s)
	for sp in spots:
		_stamp(ci, org + sp[0], sp[1], sp[2], d, a * sp[3])
	_mstyle = "ink"
	Icons.screen()
	ci.draw_set_transform(org)


## 押し方の位置を、名札の形の内へ寄せる（楕円・葉・雲・旗の切れ込みで、判子がはみ出さないよう）。形と大きさごとに覚えておく
static func _fit_spots(d: Dictionary, R: Rect2, lx: float, s: float) -> Array:
	var key := "spots|%s|%s|%d|%d" % [d.layout, d.shape, roundi(R.size.x * 2.0), roundi(R.size.y * 2.0)]
	if _geo.has(key):
		return _geo[key]
	var pts: PackedVector2Array = _geometry(R.size, d).pts
	var ctr := Vector2((lx + R.size.x) / 2.0, R.size.y / 2.0)
	var o := []
	for sp in _spots(d.layout, R, lx, s):
		var p: Vector2 = sp[0]
		var m: float = sp[1] * 0.42
		for k in 16:
			if Geometry2D.is_point_in_polygon(p, pts) and _edge_dist(p, pts) >= m:
				break
			p = p.lerp(ctr, 0.15)
		o.append([p, sp[1], sp[2], sp[3]])
	_geo[key] = o
	return o


static func _edge_dist(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])))
	return best


## 押し方ごとの判子の位置: [[中心, 大きさ, 回し, 濃さ]]。lx より左は穴と糸の場所、s はふつうの判子の大きさ
static func _spots(layout: String, R: Rect2, lx: float, s: float) -> Array:
	var w := R.size.x
	var h := R.size.y
	var corner := Vector2(w, h) - Vector2(s * 0.8, s * 0.8)
	var spots := []
	match layout:
		"center":
			var sc := minf(h * 0.52, 66.0)
			spots.append([Vector2((lx + w) / 2.0, h / 2.0), sc, 0.0, 1.0])
		"pair":
			spots.append([Vector2(lx + s * 0.6, s * 0.75), s * 0.85, -0.2, 1.0])
			spots.append([corner, s * 0.85, 0.2, 1.0])
		"row":
			var sw := minf(s * 0.85, (w - lx) / 3.0 * 0.8)
			for k in 3:
				spots.append([Vector2(lx + (w - lx - s * 0.2) * (k + 0.5) / 3.0, h / 2.0), sw, 0.0, 1.0])
		"overlap":   # ずらして重ね押し（薄い順に）
			spots.append([corner - Vector2(s * 0.55, s * 0.3), s, -0.3, 0.4])
			spots.append([corner - Vector2(s * 0.27, s * 0.12), s, -0.12, 0.65])
			spots.append([corner, s, 0.06, 1.0])
		"scatter":   # 散らし
			var at := [Vector2(0.12, 0.25), Vector2(0.42, 0.18), Vector2(0.78, 0.26), Vector2(0.28, 0.72), Vector2(0.6, 0.62), Vector2(0.9, 0.78)]
			for k in at.size():
				var q: Vector2 = at[k]
				spots.append([Vector2(lerpf(lx, w - s * 0.35, q.x), lerpf(s * 0.35, h - s * 0.35, q.y)), s * 0.55, (k % 3 - 1) * 0.35, 1.0])
		_:
			spots.append([corner, s, 0.0, 1.0])
	return spots


## 判子 1 つを、判子の作りで描く（c は画面の px）
static func _stamp(ci: CanvasItem, c: Vector2, s: float, rot: float, d: Dictionary, a: float) -> void:
	var name: String = d.motif
	var ink: Color = d.ink
	ci.draw_set_transform(c, rot)
	Icons.screen()
	match d.print:
		"applique":   # フェルトのアップリケ: 丸いフェルトを縫い付け、その上に判子の形のフェルト
			var bk := _backing(d)
			Icons.patch(ci, Icons.circ(Vector2.ZERO, s * 0.56, 22), bk, a, true, d.edge)
			_mstyle = "fill"
			motif(ci, name, Vector2.ZERO, s * 0.78, _readable(ink, bk), a)
		"embroidery":
			_mstyle = "embroidery"
			motif(ci, name, Vector2.ZERO, s, ink, a)
		"cutout":     # 切り抜き: 形の穴から裏の影が見える
			_mstyle = "cutout"
			motif(ci, name, Vector2.ZERO, s, Color(0.20, 0.16, 0.18), a)
		"window":     # 透けるフィルムの窓: 縁を縫った丸窓に、薄く判子と光の筋
			var wr := s * 0.55
			ci.draw_circle(Vector2.ZERO, wr + maxf(1.2, s * 0.05), Color(_base_col(d).darkened(0.4), a))
			ci.draw_circle(Vector2.ZERO, wr, Color(0.86, 0.93, 0.98, 0.55 * a))
			_mstyle = "ink"
			motif(ci, name, Vector2.ZERO, s * 0.7, ink, 0.8 * a)
			Icons.screen()
			for k in 2:
				var off := wr * (0.15 + 0.3 * k)
				var half := sqrt(maxf(wr * wr - off * off, 0.0)) * 0.8
				var dir := Vector2(1, -1).normalized()
				var nrm := Vector2(1, 1).normalized() * -off
				ci.draw_line(nrm - dir * half, nrm + dir * half, Color(1, 1, 1, 0.55 * a), maxf(1.0, s * (0.06 - 0.03 * k)), true)
			Icons.dashes(ci, Icons.circ(Vector2.ZERO, wr + maxf(1.2, s * 0.05) * 0.5, 20), d.edge, maxf(0.8, s * 0.025), maxf(2.0, s * 0.07), maxf(1.5, s * 0.05), a, true)
		_:            # 判子: 平らなインク
			_mstyle = "ink"
			motif(ci, name, Vector2.ZERO, s, ink, 0.9 * a)
	_mstyle = "ink"


## アップリケの下のフェルトの色: 地と違って見える色
static func _backing(d: Dictionary) -> Color:
	var paper: Color = d.paper
	var acc: Color = d.accent
	if absf(acc.get_luminance() - paper.get_luminance()) > 0.12:
		return acc
	return Icons.CAP if paper.get_luminance() < 0.6 else Color(0.30, 0.38, 0.62)


## bg の上で読める色（col が読めなければ、生成りか藍）
static func _readable(col: Color, bg: Color) -> Color:
	if absf(col.get_luminance() - bg.get_luminance()) >= 0.22:
		return col
	return Color(0.98, 0.96, 0.92) if bg.get_luminance() < 0.5 else Color(0.20, 0.25, 0.42)


## 飾り（名札の左上を原点に、穴 hp・糸の輪 loop のまわりに）
static func _deco(ci: CanvasItem, d: Dictionary, R: Rect2, hp: Vector2, a: float, loop := PackedVector2Array()) -> void:
	var w := R.size.x
	var h := R.size.y
	var str_col: Color = d.string
	var gold := Color(0.88, 0.72, 0.30)
	Icons.screen()
	match d.deco:
		"button":    # 木のボタンを右上に縫い付ける
			var bp := Vector2(w - h * 0.3, h * 0.27)
			var br := maxf(2.6, h * 0.09)
			ci.draw_circle(bp + Vector2(0.6, 1.0), br, Color(Icons.SHADOW, 0.3 * a))
			ci.draw_circle(bp, br, Color(Icons.WOOD, a))
			ci.draw_arc(bp, br * 0.72, 0.0, TAU, 20, Color(Icons.WOOD.darkened(0.25), a), maxf(0.7, br * 0.12), true)
			var k := br * 0.28
			for q in [Vector2(-k, -k), Vector2(k, k), Vector2(-k, k), Vector2(k, -k)]:
				ci.draw_circle(bp + q, maxf(0.5, br * 0.12), Color(0.25, 0.16, 0.10, a))
			ci.draw_line(bp + Vector2(-k, -k), bp + Vector2(k, k), Color(d.edge, a), maxf(0.8, br * 0.14), true)
			ci.draw_line(bp + Vector2(-k, k), bp + Vector2(k, -k), Color(d.edge, a), maxf(0.8, br * 0.14), true)
		"ribbon":    # 穴にリボンの蝶結び
			var k := maxf(3.0, h * 0.11)
			var dark := str_col.darkened(0.25)
			for sgn in [-1.0, 1.0]:   # 垂れ（先は燕尾）と、左右の輪
				Icons.patch(ci, PackedVector2Array([hp + Vector2(sgn * k * 0.05, 0), hp + Vector2(sgn * k * 0.3, -k * 0.05), hp + Vector2(sgn * k * 0.75, k * 1.25),
						hp + Vector2(sgn * k * 0.5, k * 1.05), hp + Vector2(sgn * k * 0.35, k * 1.4)]), dark, a, false)
				Icons.patch(ci, PackedVector2Array([hp + Vector2(sgn * k * 0.1, -k * 0.15), hp + Vector2(sgn * k * 0.95, -k * 0.7), hp + Vector2(sgn * k * 1.2, -k * 0.15),
						hp + Vector2(sgn * k * 0.95, k * 0.4), hp + Vector2(sgn * k * 0.1, k * 0.15)]), str_col, a, false)
				ci.draw_colored_polygon(PackedVector2Array([hp + Vector2(sgn * k * 0.25, -k * 0.05), hp + Vector2(sgn * k * 0.85, -k * 0.35), hp + Vector2(sgn * k * 0.85, k * 0.15)]), Color(dark, 0.8 * a))
			Icons.patch(ci, Icons.rr(hp.x - k * 0.22, hp.y - k * 0.25, k * 0.44, k * 0.5, k * 0.12), str_col.darkened(0.08), a, false)
		"bell":      # 糸の輪に小さな鈴
			if loop.size() > 8:
				var bp := loop[9] + Vector2(0, maxf(2.6, h * 0.075))
				var br := maxf(2.2, h * 0.07)
				Icons.thread(ci, PackedVector2Array([loop[9], bp]), str_col, maxf(0.8, h * 0.008), a)
				ci.draw_circle(bp + Vector2(0.5, 0.9), br, Color(Icons.SHADOW, 0.3 * a))
				ci.draw_circle(bp, br, Color(gold, a))
				ci.draw_line(bp + Vector2(-br * 0.7, br * 0.15), bp + Vector2(br * 0.7, br * 0.15), Color(gold.darkened(0.45), a), maxf(0.7, br * 0.16), true)
				ci.draw_circle(bp + Vector2(0, br * 0.5), br * 0.18, Color(gold.darkened(0.55), a))
				ci.draw_circle(bp + Vector2(-br * 0.35, -br * 0.35), br * 0.22, Color(1, 1, 0.9, 0.7 * a))
		"tassel":    # 穴から房を下げる
			var kk := maxf(2.0, h * 0.05)
			var top := hp + Vector2(0, kk * 1.2)
			var ln := h * 0.4
			for i in 9:
				var t := (i - 4) / 4.0
				ci.draw_line(top, top + Vector2(t * kk * 1.1, ln), Color(str_col.darkened(0.15 * absf(t)), a), maxf(0.8, h * 0.012), true)
			ci.draw_circle(hp + Vector2(0, kk * 0.6), kk, Color(str_col, a))
			ci.draw_line(top + Vector2(-kk * 0.9, kk * 0.5), top + Vector2(kk * 0.9, kk * 0.5), Color(gold, a), maxf(1.0, kk * 0.5), true)
		"pompom":    # 糸の輪の先に毛糸のぼんぼん
			if not loop.is_empty():
				var pp := loop[loop.size() - 1]
				var pr := maxf(2.6, h * 0.09)
				var fluff := str_col.lightened(0.2)
				ci.draw_circle(pp + Vector2(0.6, 1.0), pr, Color(Icons.SHADOW, 0.25 * a))
				Icons.patch(ci, Icons.circ(pp, pr, 16), fluff, a, false)
				for i in 16:
					var dir := Vector2.from_angle(TAU * i / 16.0 + 0.2)
					ci.draw_line(pp + dir * pr * 0.7, pp + dir * pr * 1.25, Color(fluff, 0.8 * a), maxf(0.8, pr * 0.16), true)
		"beads":     # 糸の輪にビーズ 3 つ
			if loop.size() > 12:
				var cols := [d.accent, d.edge, Icons.CAP]
				var br := maxf(1.8, h * 0.042)
				for k in 3:
					var q := loop[4 + k * 3]
					ci.draw_circle(q + Vector2(0.4, 0.7), br, Color(Icons.SHADOW, 0.3 * a))
					ci.draw_circle(q, br, Color(cols[k], a))
					ci.draw_circle(q + Vector2(-br * 0.35, -br * 0.35), br * 0.3, Color(1, 1, 1, 0.6 * a))
		"clip":      # 上の縁を木のクリップで挟む
			var cx := w * 0.58
			var cw := maxf(3.0, h * 0.12)
			var body := Icons.rr(cx - cw / 2.0, -h * 0.12, cw, h * 0.36, cw * 0.3)
			var sh := PackedVector2Array()
			for p in body:
				sh.append(p + Vector2(0.8, 1.2))
			ci.draw_colored_polygon(sh, Color(Icons.SHADOW, 0.3 * a))
			ci.draw_colored_polygon(body, Color(Icons.WOOD.lightened(0.15), a))
			ci.draw_line(Vector2(cx, -h * 0.1), Vector2(cx, h * 0.22), Color(Icons.WOOD.darkened(0.3), a), maxf(0.7, cw * 0.1), true)
			ci.draw_arc(Vector2(cx, h * 0.02), cw * 0.42, 0.0, TAU, 14, Color(0.70, 0.72, 0.76, a), maxf(0.8, cw * 0.14), true)
		"feather":   # 穴に羽根を差す
			var ln := h * 0.55
			var ang := 0.75
			var body := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				body.append(Vector2(ln * t, -sin(PI * t) * ln * 0.16))
			for i in range(11, 0, -1):
				var t := i / 12.0
				body.append(Vector2(ln * t, sin(PI * pow(t, 0.8)) * ln * 0.12))
			var col := Color(0.97, 0.95, 0.90)
			var tip: Color = d.accent
			ci.draw_colored_polygon(Icons.xf(body, ang, hp + Vector2(1.0, 1.6)), Color(Icons.SHADOW, 0.22 * a))
			ci.draw_colored_polygon(Icons.xf(body, ang, hp), Color(col, a))
			var tipb := PackedVector2Array()
			for p in body:
				if p.x > ln * 0.72:
					tipb.append(p)
			if tipb.size() >= 3:
				ci.draw_colored_polygon(Icons.xf(tipb, ang, hp), Color(tip, a))
			var spine := Icons.xf(PackedVector2Array([Vector2(-ln * 0.06, 0), Vector2(ln, 0)]), ang, hp)
			ci.draw_line(spine[0], spine[1], Color(col.darkened(0.35), a), maxf(0.7, h * 0.01), true)


## 判子の絵（center、大きさ size px）。描き方は _mstyle（判子・フェルト・刺繍・切り抜き）
static func motif(ci: CanvasItem, name: String, center: Vector2, size: float, col: Color, a := 1.0) -> void:
	Icons._o = center
	Icons._s = size / 64.0
	var wood := Icons.WOOD if _mstyle in ["fill", "embroidery"] else col
	match name:
		"snow":
			for k in 3:
				var dir := Vector2.from_angle(PI / 3 * k)
				_mline(ci, PackedVector2Array([-dir * 24, dir * 24]), col, 3.0, a)
				for e in [-1.0, 1.0]:
					var tip: Vector2 = dir * 14.0 * e
					var side: Vector2 = Vector2(-dir.y, dir.x)
					_mline(ci, PackedVector2Array([tip + (side - dir * e) * 6.0, tip, tip + (-side - dir * e) * 6.0]), col, 2.2, a)
		"star":
			var p := PackedVector2Array()
			for i in 10:
				p.append(Vector2.from_angle(-PI / 2 + PI / 5 * i) * (26.0 if i % 2 == 0 else 11.0))
			_mfill(ci, p, col, a)
		"pine":
			_mfill(ci, PackedVector2Array([Vector2(0, -28), Vector2(18, 0), Vector2(8, 0), Vector2(22, 18), Vector2(-22, 18), Vector2(-8, 0), Vector2(-18, 0)]), col, a)
			_mfill(ci, Icons.rr(-4, 18, 8, 9, 2), wood, a)
		"heart":
			var p := PackedVector2Array()
			for i in 24:
				var t := TAU * i / 24.0
				p.append(Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * 1.4)
			_mfill(ci, p, col, a)
		"dots":
			for q in [Vector2(-14, -12), Vector2(10, -16), Vector2(-4, 4), Vector2(16, 10), Vector2(-16, 18)]:
				_mfill(ci, Icons.circ(q, 7.0, 12), col, a)
		"stripe":
			for i in 4:
				_mline(ci, PackedVector2Array([Vector2(-24, -18 + i * 12), Vector2(24, -24 + i * 12)]), col, 4.0, a)
		"mitten":
			_mfill(ci, Icons.xf(Icons.rr(-6, -9, 12, 17, 6), 0.2, Vector2.ZERO, 2.0), col, a)
			_mfill(ci, Icons.xf(Icons.ell(Vector2(-7.5, 1), 2.8, 5.0, 12), -0.3, Vector2.ZERO, 2.0), col, a)
			_mfill(ci, Icons.xf(Icons.rr(-6.5, 6, 13, 5, 2), 0.2, Vector2.ZERO, 2.0), col.darkened(0.3) if _mstyle == "fill" else col, a)
		"moon":     # 三日月
			var cut := Geometry2D.clip_polygons(Icons.circ(Vector2.ZERO, 24.0, 28), Icons.circ(Vector2(11, -7), 20.0, 28))
			for q in cut:
				if not Geometry2D.is_polygon_clockwise(q) or cut.size() == 1:
					_mfill(ci, q, col, a)
		"mountain":  # 雪をかぶった山
			_mfill(ci, PackedVector2Array([Vector2(2, -6), Vector2(28, 20), Vector2(-8, 20)]), col.darkened(0.15) if _mstyle == "fill" else col, a)
			_mfill(ci, PackedVector2Array([Vector2(-8, -24), Vector2(16, 20), Vector2(-30, 20)]), col, a)
			if _mstyle in ["fill", "embroidery"]:
				_mfill(ci, PackedVector2Array([Vector2(-8, -24), Vector2(-1, -11), Vector2(-6, -13), Vector2(-10, -9), Vector2(-15, -11)]), Icons.SNOW, a)
		"plum":     # 梅の花
			for k in 5:
				_mfill(ci, Icons.circ(Vector2.from_angle(-PI / 2 + TAU * k / 5.0) * 13.0, 11.0, 14), col, a)
			if _mstyle != "cutout":
				Icons._o = center
				var mid := Icons._map(Icons.circ(Vector2.ZERO, 5.0, 10))
				ci.draw_colored_polygon(mid, Color(col.lightened(0.5) if _mstyle != "ink" else col.darkened(0.3), a))
		"bird":
			_mfill(ci, Icons.ell(Vector2(-4, 4), 18.0, 12.0, 20), col, a)
			_mfill(ci, Icons.circ(Vector2(13, -7), 9.0, 14), col, a)
			_mfill(ci, PackedVector2Array([Vector2(-18, 0), Vector2(-30, -10), Vector2(-27, 6)]), col, a)
			_mfill(ci, PackedVector2Array([Vector2(21, -9), Vector2(29, -6), Vector2(21, -3)]), Icons.MUSTARD if _mstyle in ["fill", "embroidery"] else col, a)
		"acorn":
			_mfill(ci, Icons.ell(Vector2(0, 5), 13.0, 17.0, 20), col, a)
			_mfill(ci, Icons.rr(-16, -18, 32, 13, 6), wood if _mstyle != "ink" else col.darkened(0.25), a)
			_mline(ci, PackedVector2Array([Vector2(0, -18), Vector2(3, -26)]), wood, 3.0, a)
		"rabbit":
			_mfill(ci, Icons.xf(Icons.ell(Vector2.ZERO, 5.5, 14.0, 14), -0.18, Vector2(-8, -14)), col, a)
			_mfill(ci, Icons.xf(Icons.ell(Vector2.ZERO, 5.5, 14.0, 14), 0.18, Vector2(8, -14)), col, a)
			_mfill(ci, Icons.ell(Vector2(0, 8), 17.0, 15.0, 20), col, a)


## 判子の面（_mstyle の描き方で）。pts は判子の絵の座標
static func _mfill(ci: CanvasItem, pts: PackedVector2Array, col: Color, a: float) -> void:
	match _mstyle:
		"fill":
			Icons.patch(ci, pts, col, a, false)
		"embroidery":   # 輪郭を糸で縫い、中を斜めのサテンで埋める
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in pts:
				lo = lo.min(p)
				hi = hi.max(p)
			var k := lo.x - (hi.y - lo.y)
			while k < hi.x:
				for pl in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(k, hi.y), Vector2(k + (hi.y - lo.y), lo.y)]), pts):
					ci.draw_polyline(Icons._map(pl), Color(col, 0.75 * a), maxf(0.8, 1.6 * Icons._s), true)
				k += 4.0
			var ring := pts.duplicate()
			ring.append(pts[0])
			Icons.thread(ci, ring, col, 2.6, a)
		"cutout":   # 穴の奥の影と、光の当たる切り口
			var m := Icons._map(pts)
			ci.draw_colored_polygon(m, Color(col, a))
			var rim := m.duplicate()
			rim.append(m[0])
			ci.draw_polyline(rim, Color(1, 1, 1, 0.25 * a), maxf(0.8, Icons._s * 1.6), true)
		_:          # 平らなインク
			ci.draw_colored_polygon(Icons._map(pts), Color(col, a))


## 判子の線（_mstyle の描き方で）
static func _mline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, a: float) -> void:
	if _mstyle in ["fill", "embroidery"]:
		Icons.thread(ci, pts, col, w, a)
	else:
		ci.draw_polyline(Icons._map(pts), Color(col, a), maxf(1.0, w * Icons._s), true)


## 部品の見本（装備の画面・一覧の絵）。c は中心、s は大きさ（px）。base は今の名札（部品の番号の辞書）
static func swatch(ci: CanvasItem, part: String, i: int, c: Vector2, s: float, base: Dictionary, a := 1.0) -> void:
	var dd := base.duplicate()
	dd[part] = i
	var d := design(dd)
	Icons.screen()
	var sq := Rect2(c - Vector2(s, s) * 0.46, Vector2(s, s) * 0.92)
	var plain := d.duplicate()
	plain.merge({"shape": "round", "stitch": "none", "pattern": "none"}, true)
	match part:
		"shape":
			var sd := d.duplicate()
			sd.merge({"stitch": "none", "pattern": "none"}, true)
			var rr := Rect2(c - Vector2(s * 0.56, s * 0.36), Vector2(s * 1.12, s * 0.72))
			_face(ci, rr.position, rr.size, sd, a)
			ci.draw_set_transform(Vector2.ZERO)
		"material":
			_face(ci, c - Vector2(s, s) * 0.5, Vector2(s, s) * 2.0, plain, a, 0.5)   # 倍の大きさで描いて縮める（素材の筋が出るように）
			ci.draw_set_transform(Vector2.ZERO)
		"paper":
			_face(ci, sq.position, sq.size, plain, a)
			ci.draw_set_transform(Vector2.ZERO)
		"accent", "pattern":
			var pd := plain.duplicate()
			pd["pattern"] = d.pattern if d.pattern != "none" or part == "pattern" else "stripe"
			_face(ci, sq.position, sq.size, pd, a)
			ci.draw_set_transform(Vector2.ZERO)
		"stitch":
			var sd := plain.duplicate()
			sd["stitch"] = d.stitch
			_face(ci, c - Vector2(s, s) * 0.42, Vector2(s, s) * 0.84, sd, a)
			ci.draw_set_transform(Vector2.ZERO)
		"edge":
			Icons.patch(ci, Icons.rr(sq.position.x, sq.position.y, sq.size.x, sq.size.y, s * 0.12), d.paper, a, false)
			Icons.dashes(ci, Icons.rr(c.x - s * 0.36, c.y - s * 0.36, s * 0.72, s * 0.72, s * 0.08), d.edge, s * 0.08, s * 0.16, s * 0.1, a, true)
		"string":
			var loop := PackedVector2Array()
			for k in 12:
				var t := k / 11.0
				loop.append(c + Vector2(-0.44 + 0.88 * t, 0.24 - sin(t * PI) * 0.56) * s)
			Icons.thread(ci, loop, d.string, s * 0.1, a)
		"cushion":   # 方位磁針のピンクッションの色（0 は名札の地の色。破線で印）
			var cc: Color = cushion_color(dd)
			Icons.patch(ci, Icons.rr(c.x - s * 0.48, c.y - s * 0.4, s * 0.96, s * 0.8, s * 0.28), cc, a, false)
			for k in 6:
				ci.draw_circle(c + Vector2(-0.4 + 0.16 * k, 0.4) * s, s * 0.064, Color(1, 1, 1, 0.95 * a))
			ci.draw_circle(c + Vector2(0.12, -0.16) * s, s * 0.12, Color(Icons.MUSTARD, a))
			if i == 0:
				Icons.screen()
				Icons.dashes(ci, Icons.rr(c.x - s * 0.32, c.y - s * 0.28, s * 0.64, s * 0.52, s * 0.12), Icons.PAPER_EDGE, s * 0.05, s * 0.12, s * 0.08, a, true)
		"deco":   # 名札の大きさを見本の 1.6 倍として、飾りが見本の真ん中に来るよう穴の位置をずらす
			var R := Rect2(Vector2.ZERO, Vector2(s * 1.4, s * 1.6))
			var h := R.size.y
			var at := {"button": Vector2(R.size.x - h * 0.3, h * 0.27), "bell": Vector2(s * 0.2, -s * 0.05), "tassel": Vector2(0, -s * 0.3),
				"pompom": Vector2(s * 0.3, s * 0.2), "beads": Vector2(s * 0.2, s * 0.15), "clip": Vector2(R.size.x * 0.58, h * 0.06),
				"feather": Vector2(-s * 0.22, -s * 0.22)}   # 穴の、見本の真ん中からのずれ（ボタンとクリップは飾りそのものの位置）
			var hp := Vector2(s * 0.35, h / 2.0)
			var z := 1.45   # 大きく見せる
			var org: Vector2 = c - (at[d.deco] * z if d.deco in ["button", "clip"] else hp * z - at.get(d.deco, Vector2.ZERO))
			if d.deco == "none":
				Icons.dashes(ci, Icons.circ(c, s * 0.3, 14), Icons.PAPER_EDGE, s * 0.05, s * 0.12, s * 0.08, a, true)
			else:
				ci.draw_set_transform(org, 0.0, Vector2.ONE * z)
				var loop := PackedVector2Array()
				var cl := minf(h * 0.28, 26.0)
				for k in 16:
					var t := k / 15.0
					loop.append(hp + Vector2(-t * cl * 0.85, sin(t * PI) * -cl * 0.38 - t * cl * 0.23))
				if d.deco != "button" and d.deco != "clip":
					Icons.thread(ci, loop, d.string, maxf(1.2, h * 0.02), a)
					ci.draw_circle(hp, maxf(1.5, h * 0.05), Color(Icons.PAPER_EDGE, a))
				_deco(ci, d, R, hp, a, loop)
			ci.draw_set_transform(Vector2.ZERO)
		"motif":
			Icons.patch(ci, Icons.circ(c, s * 0.52, 16), d.paper, a, false)
			if d.motif == "none":
				Icons.screen()
				Icons.dashes(ci, Icons.circ(c, s * 0.32, 14), Icons.PAPER_EDGE, s * 0.056, s * 0.12, s * 0.08, a, true)
			else:
				_mstyle = "ink"
				motif(ci, d.motif, c, s * 0.88, d.ink, a)
		"print":
			Icons.patch(ci, Icons.circ(c, s * 0.52, 16), d.paper, a, false)
			var pd := d.duplicate()
			if pd.motif == "none":
				pd.motif = "star"
			_stamp(ci, c, s * 0.84, 0.0, pd, a)
			ci.draw_set_transform(Vector2.ZERO)
		"layout":
			var tr := Rect2(c - Vector2(s * 0.56, s * 0.38), Vector2(s * 1.12, s * 0.76))
			Icons.patch(ci, Icons.rr(tr.position.x, tr.position.y, tr.size.x, tr.size.y, s * 0.08), d.paper, a, false)
			var ld := d.duplicate()
			ld.merge({"motif": "dots" if d.motif == "none" else d.motif, "print": "ink"}, true)
			_stamps_dots(ci, tr, ld, a)
	Icons.screen()


## 押し方の見本: 判子の位置に小さな点（4 倍の名札で位置を求めて縮める）
static func _stamps_dots(ci: CanvasItem, tr: Rect2, d: Dictionary, a: float) -> void:
	var R := Rect2(Vector2.ZERO, tr.size * 4.0)
	var h := R.size.y
	var lx := hole(R, d.shape).x + minf(h * 0.28, 26.0) * 0.7
	for sp in _spots(d.layout, R, lx, minf(h * 0.30, 40.0)):
		ci.draw_circle(tr.position + sp[0] * 0.25, maxf(1.4, sp[1] * 0.25 * 0.42), Color(d.ink, a * sp[3]))


# ---- 3D に貼る絵 ------------------------------------------------------------------------

static func _root() -> Node:
	if _holder == null or not is_instance_valid(_holder):
		_holder = Node.new()
		_holder.name = "SledTagTextures"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_holder)
	return _holder


## 吊るすタグの絵（柄ごとに 1 枚を描いて使い回す）
static func texture(idx) -> Texture2D:
	var key := _key(idx)
	if not _tags.has(key):
		var vp := SubViewport.new()
		vp.size = TEX_SIZE
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var c := TagFace.new()
		c.idx = idx
		c.size = Vector2(TEX_SIZE)
		vp.add_child(c)
		_root().add_child.call_deferred(vp)
		_tags[key] = vp.get_texture()
	return _tags[key]


## 畳んだソリの、広げた姿がくるくる回る図（大きさと布の色ごとに 1 つを使い回す）
static func turntable(kind: String, fabric: String) -> Texture2D:
	var key := kind + "|" + fabric
	if not _turns.has(key):
		var t := Turntable.new()
		t.kind = kind
		t.fabric = fabric
		_root().add_child.call_deferred(t)
		_turns[key] = t
	return (_turns[key] as Turntable).get_texture()


class TagFace extends Control:
	var idx: Variant = 0

	func _draw() -> void:
		var pad := Vector2(10, 12)
		preload("res://sled_tags.gd").draw_tag(self, Rect2(pad + Vector2(14, 0), size - pad * 2 - Vector2(14, 0)), idx, 1.0)


## 広げた姿を小さな世界に置いて、斜め上から撮る。12 コマに合わせて 15° ずつ回す（人形と同じコマ撮り）
class Turntable extends SubViewport:
	var kind := "mid"
	var fabric := ""
	var _model: Node3D
	var _frame := -1

	func _init() -> void:
		size = preload("res://sled_tags.gd").TURN_SIZE
		own_world_3d = true
		transparent_bg = true
		render_target_update_mode = SubViewport.UPDATE_ALWAYS

	func _ready() -> void:
		var Sled := preload("res://sled.gd")
		var k: Dictionary = Sled.KINDS.get(kind, Sled.KINDS["mid"])
		var glb := "res://props/sled_%s.glb" % kind
		_model = Node3D.new()
		add_child(_model)
		if ResourceLoader.exists(glb):
			var look := preload("res://props.gd").make(glb)
			preload("res://fabrics.gd").tint(look, kind, fabric)
			_model.add_child(look)
		var L: float = maxf(k.box.z, k.box.x)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = L * 1.25
		cam.position = Vector3(0, L * 0.9, L * 1.3)
		add_child(cam)
		cam.look_at(Vector3(0, k.box.y * 0.5, 0))
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -30, 0)
		sun.light_energy = 1.4
		add_child(sun)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.85, 0.88, 0.95)
		env.ambient_light_energy = 0.7
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)

	func _process(_dt: float) -> void:
		var fi := preload("res://doll.gd").frame_index() / preload("res://sled_tags.gd").TURN_STEP
		if fi == _frame or _model == null:
			return
		_frame = fi
		_model.rotation.y = deg_to_rad(preload("res://sled_tags.gd").TURN_DEG * fi)


# ---- 3D のタグ（吊るす） -------------------------------------------------------------------

## 畳んだソリの包みの面に、名札を平らに貼る（吊るすと包みに隠れるので）。parent の +Y の面に載せ、絵の下は +Z。
## 左右の端を紙テープで留め、窓に広げた姿がくるくる回る。面に埋もれないよう少し浮かせる。w は名札の幅 (m)
static func patch_on(parent: Node3D, top: float, idx, w: float, turn: Texture2D, layers := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "TagPatch"
	root.position = Vector3(0, top + 0.003, 0)
	parent.add_child(root)
	var h := w * TEX_SIZE.y / TEX_SIZE.x
	var face := _flat(root, Vector2(w, h), texture(idx), false, layers)
	face.position.y = 0.0
	if turn:   # 窓（右寄り）
		var win := _flat(root, Vector2.ONE * h * 0.74, turn, true, layers)
		win.position = Vector3(w * 0.2, 0.0015, 0.0)
	# 紙テープ: 左上と右下の角に斜めに
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.93, 0.86, 0.68, 0.85)
	tape.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tape.roughness = 0.9
	for s in [-1.0, 1.0]:
		var t := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w * 0.3, 0.001, h * 0.22)
		t.mesh = bm
		t.material_override = tape
		t.layers = layers
		t.position = Vector3(s * w * 0.46, 0.003, -s * h * 0.42)
		t.rotation.y = 0.6
		root.add_child(t)
	return root


static func _flat(parent: Node3D, sz: Vector2, tex: Texture2D, unshaded: bool, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.layers = layers
	mi.rotation.x = -PI / 2   # 面は +Y、絵の上は -Z
	parent.add_child(mi)
	return mi


## 畳んだソリの包みの絵に、名札を貼った形で描く（持ち物の列・売り台。3D の patch_on と同じ並び）。c と w は画面の px
static func draw_on_packet(ci: CanvasItem, c: Vector2, w: float, idx, turn: Texture2D, a := 1.0) -> void:
	var h := w * TEX_SIZE.y / TEX_SIZE.x * 0.82
	var r := Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h))
	draw_tag(ci, r, idx, a, false)
	var tw := h * 0.74
	ci.draw_texture_rect(turn, Rect2(Vector2(c.x + w * 0.2 - tw / 2.0, c.y - tw / 2.0), Vector2(tw, tw)), false, Color(1, 1, 1, a))
	for s in [-1.0, 1.0]:
		var tc := c + Vector2(s * w * 0.46, -s * h * 0.42)
		var tape := Icons.xf(Icons.rr(-w * 0.15, -h * 0.11, w * 0.3, h * 0.22, 1.0), -0.6, tc, 1.0)
		Icons._o = Vector2.ZERO
		Icons._s = 1.0
		ci.draw_colored_polygon(tape, Color(0.93, 0.86, 0.68, 0.85 * a))


## 小さなタグを parent の at から糸で吊るす。turn があれば、タグの窓に回る図も貼る（畳んだソリ）。layers は映す層
static func hang(parent: Node3D, at: Vector3, idx, w := 0.16, turn: Texture2D = null, layers := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Tag"
	root.position = at
	parent.add_child(root)
	var drop := w * 0.45
	var string := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.003
	cm.bottom_radius = 0.003
	cm.height = drop
	string.mesh = cm
	string.position.y = -drop / 2.0
	var sm := StandardMaterial3D.new()
	sm.albedo_color = design(idx).string
	string.material_override = sm
	string.layers = layers
	root.add_child(string)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, w * TEX_SIZE.y / TEX_SIZE.x)
	face.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(idx)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	face.material_override = m
	face.layers = layers
	# 穴（絵の左）を糸の先に合わせ、紙を縦に吊るす
	face.position = Vector3(0, -drop - q.size.x * 0.42, 0)
	face.rotation.z = -PI / 2
	root.add_child(face)
	if turn:
		var win := MeshInstance3D.new()
		var wq := QuadMesh.new()
		wq.size = Vector2.ONE * q.size.y * 0.78
		win.mesh = wq
		var wm := StandardMaterial3D.new()
		wm.albedo_texture = turn
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		win.material_override = wm
		win.layers = layers
		win.position = face.position + Vector3(0, -q.size.x * 0.08, 0.002)
		root.add_child(win)
	return root
