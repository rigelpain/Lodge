extends SceneTree
## 案の絵（まだ作っていない）: 持ち物の画面（I）の整理と、手袋・双眼鏡の解放（2026-11-10 代表「インベントリのなかもUI整理したいね」
## 「手袋も双眼鏡もUNLOCK形式にしましょう。インベントリ圧迫するのだるいし」）。
## now.png は本物の画面に番号を重ねた今の中身。A・B・C は同じ部品（hud_icons.gd・craft_icons.gd）で描いた並べ方の案。
##   Godot --path game --resolution 1600x900 -s res://tools/inventory_ui_mock.gd -- --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-save --dir=/path

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const PersonIcon := preload("res://person_icon.gd")
const Gloves := preload("res://gloves.gd")
const Tags := preload("res://sled_tags.gd")

const LEATHER := Color(0.42, 0.30, 0.22)
const BAGGREEN := Color(0.30, 0.38, 0.30)
const ITEMS := [{"kind": "pattern", "sled": "small"}, {"kind": "fabric", "fabric": "plum"}, {"kind": "campfire"},
		{"kind": "food", "dish": "ramen", "step": 1}, {"kind": "peg", "n": 6}]

var args := {}
var main: Node3D
var over: Over


class Over extends Control:
	var mode := ""
	var ui: Node
	var marks: Array = []   # [位置, 番号]

	func _draw() -> void:
		var u: float = ui.ui()
		match mode:
			"now":
				for m in marks:
					_num(m[0], m[1], u)
			"A":
				_plan_a(u)
			"B":
				_plan_b(u)
			"C":
				_plan_c(u)
			"B2":
				_plan_b2(u, false)
			"B2many":
				_plan_b2(u, true)
			"kome":
				_kome(size / 2.0, 360.0)

	# ---- 部品
	func _num(p: Vector2, n: int, u: float) -> void:
		Icons.screen()
		Icons.patch(self, Icons.circ(p, 17.0 * u, 20), Icons.RED, 1.0, true, Icons.CAP)
		var f := ThemeDB.fallback_font
		var s := str(n)
		var fs := int(22.0 * u)
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, p + Vector2(-w / 2.0, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Icons.CAP)

	func _board(u: float, w := 1040.0, h := 690.0) -> Rect2:
		var r := Rect2(size.x / 2.0 - w * u / 2.0, size.y * 0.44 - h * u / 2.0, w * u, h * u)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.55))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, r.size.x, r.size.y, 22.0 * u), LEATHER, 1.0, false)
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, r.size.x - 20 * u, r.size.y - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		return r

	func _paper(r: Rect2, u: float, a := 0.96) -> void:
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, r.size.x, r.size.y, 16.0 * u), Icons.PAPER, a, true, Icons.PAPER_EDGE)

	func _card(r: Rect2, u: float, picked := false) -> void:
		if picked:
			r.position.y -= 6.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, r.size.x, r.size.y, 10.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
		if picked:
			Icons.dashes(self, Icons.rr(r.position.x - 3 * u, r.position.y - 3 * u, r.size.x + 6 * u, r.size.y + 6 * u, 12.0 * u), Icons.RED, 2.6 * u, 6.0 * u, 3.5 * u, 1.0, true)
			Icons.chevron(self, Vector2(r.get_center().x, r.position.y - 11.0 * u), 14.0 * u, Icons.RED, 1.0, PI / 2, 2.6 * u)

	func _slot(r: Rect2, u: float) -> void:
		Icons.screen()
		Icons.dashes(self, Icons.rr(r.position.x + 3 * u, r.position.y + 3 * u, r.size.x - 6 * u, r.size.y - 6 * u, 9.0 * u), Icons.CAP, 2.0 * u, 5.0 * u, 4.0 * u, 0.6, true)

	## 装備の 1 種類の札（kind: sack・lantern・gloves・binoculars）。i 番目
	func _gear_icon(kind: String, i: int, c: Vector2, s: float, lit := false) -> void:
		match kind:
			"sack":
				CraftIcons._at(c, s)
				CraftIcons.rice_sack(self, Vector2.ZERO, 1.0, [CraftIcons.KRAFT, Color(0.30, 0.36, 0.55), Color(0.55, 0.28, 0.40)][i % 3], [Color("B8402E"), Color("E2B33C"), Color("EDE3CF")][i % 3], 1.0)
			"lantern":
				CraftIcons._at(c, s)
				CraftIcons.lantern(self, Vector2.ZERO, 1.0, ["box", "paper", "spool", "thimble", "knit"][i % 5], lit, 1.0)
			"gloves":
				CraftIcons.item(self, {"kind": Gloves.ORDER[i % 3]}, c, s)
			"binoculars":
				CraftIcons.item(self, {"kind": ["binoculars", "binoculars_far", "binoculars_night"][i % 3]}, c, s)

	## 装備の 1 段: 左に段の印、右へ持っている札。on 番を選んでいる
	func _gear_row(kind: String, n: int, on: int, x: float, y: float, cw: float, ch: float, u: float) -> void:
		Icons.screen()
		var mk := Vector2(x + 22.0 * u, y + ch / 2.0)
		Icons.patch(self, Icons.circ(mk, 19.0 * u, 18), Icons.PAPER, 0.9, true, Icons.PAPER_EDGE)
		_gear_icon(kind, 1 if kind == "gloves" else 0, mk, 34.0 * u)
		for i in n:
			var r := Rect2(x + 50.0 * u + i * (cw + 8.0 * u), y, cw, ch)
			_card(r, u, i == on)
			_gear_icon(kind, i, r.get_center() - (Vector2(0, 6.0 * u) if i == on else Vector2.ZERO), minf(cw, ch) * 0.86, i == on and kind == "lantern")

	## 手持ち 6 とかばん 6（cell の大きさ）
	func _hand_bag(x: float, y: float, cell: float, u: float, vertical := false) -> void:
		var gap := 7.0 * u
		var bag: Array = [ITEMS[0], ITEMS[1], {}, {}, {}, {}, ITEMS[2], ITEMS[3], ITEMS[4], {}, {}, {}]
		for k in 2:
			var bx := x + (k * (2 * cell + 3 * gap) if vertical else 0.0)
			var by := y + (0.0 if vertical else k * (cell + 14.0 * u))
			Icons.screen()
			if k == 1:
				var bw := (2 * cell + gap + 16.0 * u) if vertical else (6 * cell + 5 * gap + 16.0 * u)
				var bh := (3 * cell + 2 * gap + 16.0 * u) if vertical else (cell + 12.0 * u)
				Icons.patch(self, Icons.rr(bx - 8.0 * u, by - 6.0 * u, bw, bh, 14.0 * u), BAGGREEN, 0.95, true, Icons.CAP)
			for i in 6:
				var col := (i % 2) if vertical else i
				var row := (i / 2) if vertical else 0
				var r := Rect2(bx + col * (cell + gap), by + row * (cell + gap), cell, cell)
				var it: Dictionary = bag[k * 6 + i]
				if it.is_empty():
					_slot(r, u)
				else:
					_card(r, u)
					CraftIcons.item(self, it, r.get_center(), cell * 0.82)
		Icons.screen()
		if vertical:
			Icons.icon(self, "hand", Vector2(x + cell + gap * 0.5, y - 24.0 * u), 34.0 * u, 1.0)
		else:
			Icons.icon(self, "hand", Vector2(x - 30.0 * u, y + cell / 2.0), 34.0 * u, 1.0)

	## 人形に装備を全部下げた絵（首に双眼鏡、手に手袋、帯の左にランタン、右に米袋）
	func _doll(c: Vector2, h: float, u: float, marks_on := false) -> void:
		var col: Color = ui.craft.color_of(ui._who())
		PersonIcon.draw(self, c + Vector2(0, h * 0.5), h, col)
		Icons.screen()
		var belt := c + Vector2(0, h * 0.05)
		Icons.patch(self, Icons.rr(belt.x - h * 0.42, belt.y - 5.0 * u, h * 0.84, 10.0 * u, 4.0 * u), Icons.WOOD.darkened(0.2), 1.0, true, Icons.CAP)
		var spots := {"binoculars": c + Vector2(0, -h * 0.12), "gloves": c + Vector2(h * 0.40, h * 0.0), "lantern": belt + Vector2(-h * 0.36, h * 0.16), "sack": belt + Vector2(h * 0.20, h * 0.30)}
		Icons.thread(self, PackedVector2Array([spots.binoculars + Vector2(-h * 0.1, -h * 0.04), c + Vector2(-h * 0.06, -h * 0.3), c + Vector2(h * 0.06, -h * 0.3), spots.binoculars + Vector2(h * 0.1, -h * 0.04)]), Icons.WOOD, 2.0 * u, 1.0)
		for k in spots:
			_gear_icon(k, 1 if k in ["gloves", "binoculars"] else 0, spots[k], h * (0.26 if k == "binoculars" else (0.34 if k != "sack" else 0.4)), k == "lantern")
			if marks_on:
				Icons.screen()
				Icons.dashes(self, Icons.circ(spots[k], h * 0.21, 20), Icons.RED if k == "binoculars" else Icons.CAP, 2.0 * u, 5.0 * u, 3.5 * u, 0.9, true)

	## 名前と色（左の紙の上）
	func _name_color(r: Rect2, u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		PersonIcon.draw(self, Vector2(r.position.x + 30.0 * u, r.position.y + 50.0 * u), 36.0 * u, craft.color_of(who))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x + 52.0 * u, r.position.y + 16.0 * u, r.size.x - 66.0 * u, 34.0 * u, 8.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
		var fs := int(20.0 * u)
		draw_string(ThemeDB.fallback_font, Vector2(r.get_center().x - 20.0 * u, r.position.y + 40.0 * u), craft.name_of(who), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Icons.THREAD)
		var n: int = craft.COLORS.size()
		var cs := (r.size.x - 28.0 * u) / n
		for i in n:
			draw_circle(Vector2(r.position.x + 14.0 * u + cs * (i + 0.5), r.position.y + 70.0 * u), cs * 0.4, craft.COLORS[i])

	## しおりの札（上の縁から下がる紙。icon は画面の中身の印）
	func _tab(c: Vector2, kind: String, on: bool, u: float) -> void:
		var w := 78.0 * u
		var h := 62.0 * u
		var r := Rect2(c.x - w + (0.0 if on else 10.0 * u), c.y - h / 2.0, w, h)
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 10.0 * u), Icons.PAPER if on else Icons.PAPER.darkened(0.25), 1.0, true, Icons.PAPER_EDGE)
		var ic := r.get_center() - Vector2(0, 4.0 * u)
		match kind:
			"wear":
				PersonIcon.draw(self, ic + Vector2(0, 22.0 * u), 44.0 * u, ui.craft.color_of(ui._who()))
			"tag":
				Icons.icon(self, "tag_stack", ic, 44.0 * u, 1.0)
			"bag":
				Icons.screen()
				CraftIcons._at(ic, 44.0 * u)
				CraftIcons.backpack(self, Vector2.ZERO, 1.0)
		if on:
			Icons.screen()
			Icons.dashes(self, Icons.rr(r.position.x - 3 * u, r.position.y - 3 * u, w + 6 * u, h + 6 * u, 12.0 * u), Icons.RED, 2.6 * u, 6.0 * u, 3.5 * u, 1.0, true)

	# ---- 案 A: しおりで 3 枚に分ける（身につける・名札と柄・持ち物）。絵は「身につける」の 1 枚目
	func _plan_a(u: float) -> void:
		var r := _board(u)
		for i in 3:
			_tab(Vector2(r.position.x + 6.0 * u, r.position.y + 90.0 * u + i * 80.0 * u), ["wear", "tag", "bag"][i], i == 0, u)
		var lr := Rect2(r.position.x + 30.0 * u, r.position.y + 40.0 * u, 300.0 * u, r.size.y - 80.0 * u)
		_paper(lr, u)
		_name_color(lr, u)
		_doll(Vector2(lr.get_center().x, lr.position.y + 300.0 * u), 300.0 * u, u)
		var x := lr.end.x + 30.0 * u
		var y := r.position.y + 50.0 * u
		var rows := [["sack", 3, 0], ["lantern", 5, 0], ["gloves", 3, 1], ["binoculars", 3, 1]]
		for k in rows.size():
			_gear_row(rows[k][0], rows[k][1], rows[k][2], x, y + k * 150.0 * u, 104.0 * u, 120.0 * u, u)
		_x(r, u)

	# ---- 案 B: 1 枚のまま区切り直す。左に自分（名前・色・人形に全部下げる）、右上に装備の 4 段、右下に手持ちとかばん。名札と柄は別の画面へ（左下の札）
	func _plan_b(u: float) -> void:
		var r := _board(u)
		var lr := Rect2(r.position.x + 30.0 * u, r.position.y + 40.0 * u, 280.0 * u, r.size.y - 80.0 * u)
		_paper(lr, u)
		_name_color(lr, u)
		_doll(Vector2(lr.get_center().x, lr.position.y + 290.0 * u), 280.0 * u, u)
		var tr := Rect2(lr.position.x + lw_half(lr) - 46.0 * u, lr.end.y - 104.0 * u, 92.0 * u, 80.0 * u)
		_card(tr, u)
		Icons.screen()
		Icons.icon(self, "tag_stack", tr.get_center(), 56.0 * u, 1.0)
		var x := lr.end.x + 30.0 * u
		var y := r.position.y + 44.0 * u
		var rows := [["sack", 3, 0], ["lantern", 5, 0], ["gloves", 3, 1], ["binoculars", 3, 1]]
		for k in rows.size():
			_gear_row(rows[k][0], rows[k][1], rows[k][2], x, y + k * 98.0 * u, 76.0 * u, 84.0 * u, u)
		_hand_bag(x + 50.0 * u, r.end.y - 30.0 * u - 2 * 74.0 * u - 14.0 * u, 70.0 * u, u)
		_x(r, u)

	func lw_half(lr: Rect2) -> float:
		return lr.size.x / 2.0

	# ---- 案 C: 着せ替え。まんなかの人形の、下げている所（首・手・帯の左右）を押すと、その種類の札が下に並ぶ。左に名前と色・名札の札、右に持ち物を縦に
	func _plan_c(u: float) -> void:
		var r := _board(u)
		var lr := Rect2(r.position.x + 30.0 * u, r.position.y + 40.0 * u, 220.0 * u, r.size.y - 80.0 * u)
		_paper(lr, u)
		_name_color(lr, u)
		var tr := Rect2(lr.get_center().x - 46.0 * u, lr.position.y + 130.0 * u, 92.0 * u, 80.0 * u)
		_card(tr, u)
		Icons.screen()
		Icons.icon(self, "tag_stack", tr.get_center(), 56.0 * u, 1.0)
		var mr := Rect2(lr.end.x + 24.0 * u, r.position.y + 40.0 * u, 480.0 * u, r.size.y - 80.0 * u)
		_paper(mr, u, 0.5)
		_doll(Vector2(mr.get_center().x, mr.position.y + 230.0 * u), 330.0 * u, u, true)
		# 押した所（首の双眼鏡）の札が、人形の下に並ぶ
		var cw := 100.0 * u
		var cx := mr.get_center().x - (3 * cw + 2 * 10.0 * u) / 2.0
		var cy := mr.end.y - 150.0 * u
		Icons.screen()
		Icons.thread(self, PackedVector2Array([Vector2(mr.get_center().x, mr.position.y + 160.0 * u), Vector2(mr.get_center().x, cy - 24.0 * u)]), Icons.RED, 2.0 * u, 0.7)
		for i in 3:
			var cr := Rect2(cx + i * (cw + 10.0 * u), cy, cw, 112.0 * u)
			_card(cr, u, i == 1)
			_gear_icon("binoculars", i, cr.get_center() - (Vector2(0, 6.0 * u) if i == 1 else Vector2.ZERO), cw * 0.86)
		_hand_bag(mr.end.x + 40.0 * u, r.position.y + 100.0 * u, 70.0 * u, u, true)
		_x(r, u)

	# ---- 案 B（2026-11-10 代表「Bがいいレイアウトは」）を描き直す: 人形はやめる（「体に乗っけてるのがだいぶ意味わかんない」）。
	# 米袋の段の印は、実物の米袋に刷ってある米マークのワッペン（「実物についてる米マークワッペンにしてほしい」）。
	# 品が増えたら札を小さくし、それでも入らなければ段の右の端に次の札（めくる）を出す（「増えると収まんなくなりそう」）

	## 米マークのワッペン: 生成りのフェルトの丸に、赤い輪と米の字形、左右に緑の稲穂（sled_sack の布の刷り）
	func _kome(c: Vector2, s: float) -> void:
		Icons.screen()
		var r := s * 0.5
		Icons.patch(self, Icons.circ(c, r, 28), Color(0.86, 0.76, 0.58), 1.0, true, Color(0.62, 0.50, 0.34))
		Icons.dashes(self, Icons.circ(c, r * 0.86, 28), Color(0.55, 0.42, 0.28), maxf(1.0, s * 0.02), s * 0.05, s * 0.035, 0.9, true)
		var green := Color(0.36, 0.56, 0.30)
		var red := Color(0.76, 0.22, 0.17)
		var w := maxf(1.2, s * 0.045)
		for side in [-1.0, 1.0]:   # 稲穂: 下から外へふくらみ、上で外へ穂先が垂れる
			var arc := PackedVector2Array()
			for k in 10:
				var t := k / 9.0
				arc.append(c + Vector2(side * (r * 0.62 + sin(t * PI) * r * 0.06), lerpf(r * 0.48, -r * 0.42, t)))
			arc.append(c + Vector2(side * r * 0.40, -r * 0.62))
			Icons.thread(self, arc, green, w, 1.0)
			Icons.patch(self, Icons.ell(c + Vector2(side * r * 0.46, -r * 0.6), r * 0.14, r * 0.06, 10), green, 1.0, false)
		var ring := PackedVector2Array()
		for k in 25:
			ring.append(c + Vector2.from_angle(TAU * k / 24.0) * r * 0.42)
		Icons.thread(self, ring, red, w, 1.0)
		var q := r * 0.3   # 米の字形: 縦と横、上の 2 本の払い、下の 2 つの点
		Icons.thread(self, PackedVector2Array([c + Vector2(0, -q), c + Vector2(0, q)]), red, w * 1.1, 1.0)
		Icons.thread(self, PackedVector2Array([c + Vector2(-q, 0), c + Vector2(q, 0)]), red, w * 1.1, 1.0)
		Icons.thread(self, PackedVector2Array([c + Vector2(-q * 0.72, -q * 0.78), c + Vector2(-q * 0.36, -q * 0.34)]), red, w, 1.0)   # 上の 2 つの点（中へ向く）
		Icons.thread(self, PackedVector2Array([c + Vector2(q * 0.72, -q * 0.78), c + Vector2(q * 0.36, -q * 0.34)]), red, w, 1.0)
		Icons.thread(self, PackedVector2Array([c + Vector2(-q * 0.08, q * 0.1), c + Vector2(-q * 0.8, q * 0.82)]), red, w, 1.0)   # 下の 2 本の払い（真ん中から外へ）
		Icons.thread(self, PackedVector2Array([c + Vector2(q * 0.08, q * 0.1), c + Vector2(q * 0.8, q * 0.82)]), red, w, 1.0)

	## 段の印（左の丸）
	func _row_mark(kind: String, c: Vector2, u: float) -> void:
		if kind == "sack":
			_kome(c, 44.0 * u)
			return
		Icons.screen()
		Icons.patch(self, Icons.circ(c, 21.0 * u, 18), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
		_gear_icon(kind, 1 if kind in ["gloves", "binoculars"] else 0, c, 36.0 * u)

	## 1 段: 札はふつう 78 × 86。入らなければ 58 まで小さくし、それでも入らなければ最後の場所に「めくる」札と、ページの点
	func _fit_row(kind: String, items: Array, on: int, x: float, y: float, w: float, u: float) -> void:
		_row_mark(kind, Vector2(x + 22.0 * u, y + 43.0 * u), u)
		var ax := x + 52.0 * u
		var aw := w - 52.0 * u
		var gap := 8.0 * u
		var n := items.size()
		var cw := minf(78.0 * u, (aw - (n - 1) * gap) / n)
		var paged := cw < 58.0 * u
		var show := n
		if paged:
			cw = 58.0 * u
			show = int((aw + gap) / (cw + gap)) - 1
		var ch := 86.0 * u
		for i in show:
			var cr := Rect2(ax + i * (cw + gap), y, cw, ch)
			_card(cr, u, i == on)
			var cc := cr.get_center() - (Vector2(0, 6.0 * u) if i == on else Vector2.ZERO)
			match kind:
				"sack":
					var tw := cw * 1.02
					draw_texture_rect(Tags.turntable("sack", String(items[i])), Rect2(cc - Vector2(tw, tw) / 2.0, Vector2(tw, tw)), false)
				"lantern":
					CraftIcons._at(cc, minf(cw, ch * 0.8) * 0.95)
					CraftIcons.lantern(self, Vector2.ZERO, 1.0, String(items[i]), i == on, 1.0)
				_:
					CraftIcons.item(self, {"kind": String(items[i])}, cc, minf(cw, ch) * 0.86)
		if paged:   # めくる札: 札の束の端に、赤い山形。下にページの点
			var pr := Rect2(ax + show * (cw + gap), y, cw, ch)
			Icons.screen()
			for k in 3:
				Icons.patch(self, Icons.rr(pr.position.x + (2 - k) * 4.0 * u, pr.position.y + (2 - k) * 3.0 * u, cw * 0.7, ch - 10.0 * u, 8.0 * u), Icons.CAP.darkened(0.04 * (2 - k)), 1.0, true, Icons.PAPER_EDGE)
			Icons.chevron(self, pr.get_center() + Vector2(4.0 * u, 0), 22.0 * u, Icons.RED, 1.0, 0.0, 3.4 * u)
			var pages := ceili(float(n) / show)
			for k in pages:
				var dc := Vector2(ax + aw / 2.0 + (k - (pages - 1) / 2.0) * 14.0 * u, y + ch + 9.0 * u)
				draw_circle(dc, 3.6 * u, Icons.RED if k == 0 else Icons.PAPER_EDGE)

	func _plan_b2(u: float, many: bool) -> void:
		var r := _board(u)
		var craft: Node = ui.craft
		var who: int = ui._who()
		var lr := Rect2(r.position.x + 30.0 * u, r.position.y + 40.0 * u, 250.0 * u, r.size.y - 80.0 * u)
		_paper(lr, u)
		_name_color(lr, u)
		# 名札と柄: 自分の名札の札。押すと名札と柄の画面（今のまんなかの 6 ページ）が開く
		var tr := Rect2(lr.position.x + 20.0 * u, lr.position.y + 120.0 * u, lr.size.x - 40.0 * u, 150.0 * u)
		_card(tr, u)
		Tags.draw_tag(self, tr.grow(-16.0 * u), craft.tag_designs.get(who, {}), 1.0, true)
		Icons.screen()
		Icons.icon(self, "needle", tr.end - Vector2(22, 22) * u, 34.0 * u, 1.0)
		var sacks := ["", "navy", "plum"]
		var lamps := ["box", "paper"]
		if many:
			sacks = ["", "navy", "plum", "mustard", "holly", "red", "cream", "navy", "plum", "mustard", "holly", "red", "cream", "navy"]
			lamps = preload("res://lantern.gd").LOOKS
		var x := lr.end.x + 26.0 * u
		var w := r.end.x - 30.0 * u - x
		var y := r.position.y + 76.0 * u
		_fit_row("sack", sacks, 0, x, y, w, u)
		_fit_row("lantern", lamps, 0, x, y + 104.0 * u, w, u)
		_fit_row("gloves", ["gloves", "gloves_felt", "gloves_leather"] if many else ["gloves"], 1 if many else 0, x, y + 208.0 * u, w, u)
		_fit_row("binoculars", ["binoculars", "binoculars_far", "binoculars_night"] if many else ["binoculars_far"], 1 if many else 0, x, y + 312.0 * u, w, u)
		_hand_bag(x + 52.0 * u, r.end.y - 30.0 * u - 2 * 64.0 * u - 14.0 * u, 64.0 * u, u)
		_x(r, u)

	func _x(r: Rect2, u: float) -> void:
		var xs := 46.0 * u
		var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
		Icons.screen()
		Icons.patch(self, Icons.circ(xc, xs * 0.5, 20), Icons.PAPER, 1.0, false)
		Icons._o = xc
		Icons._s = xs / 64.0
		Icons.thread(self, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if over:
		over.queue_redraw()   # 米袋の回る絵は、描き上がるまで何コマかかかる
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _shot(name: String) -> void:
	over.queue_redraw()
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var dir := String(args.get("dir", "/tmp/inventory_ui_mock"))
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(name))
	print("撮った: ", dir.path_join(name))


func _run() -> void:
	await create_timer(2.5).timeout
	var p = main.player
	var c = main.craft
	var ui = main.craft_ui
	var who: int = p.id
	p.set("_pitch", -0.05)
	p.set_third(false)
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	over = Over.new()
	over.ui = ui
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(over)
	c.gloves[who] = [{"grade": "gloves"}, {"grade": "gloves_felt"}, {"grade": "gloves_leather"}]
	c.gloves_sel[who] = 1
	c.lanterns[who] = [{"look": "box"}, {"look": "paper"}, {"look": "spool"}, {"look": "thimble"}, {"look": "knit"}]
	c.lantern_sel[who] = 0
	c.sacks[who] = [{"fabric": ""}, {"fabric": "navy"}, {"fabric": "plum"}]
	c.wallets[who] = 37
	# 今: 双眼鏡が持ち物の枠に入っている
	c.bags[who] = [{"kind": "binoculars_far"}, ITEMS[0], {"kind": "binoculars"}, ITEMS[1], {}, {},
			{"kind": "binoculars_night"}, ITEMS[2], ITEMS[3], ITEMS[4], {}, {}]
	c.hands[who] = 0
	ui.open_gear()
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	await _shot("plain.png")
	var u: float = ui.ui()
	var w := 1040.0 * u
	var h := 690.0 * u
	var sz: Vector2 = over.size
	var r := Rect2(sz.x / 2.0 - w / 2.0, sz.y * 0.44 - h / 2.0, w, h)
	var x0 := r.position.x + 340.0 * u
	over.marks = [
		[r.position + Vector2(24, 34) * u, 1],                        # 名前と色
		[r.position + Vector2(24, 150) * u, 2],                       # 帯に下げた米袋とランタン
		[r.position + Vector2(24, 420) * u, 3],                       # 持っているランタン
		[Vector2(x0 + 10.0 * u, r.position.y + 40.0 * u), 4],        # 持っている米袋
		[(ui._glove_rects[0] as Rect2).position - Vector2(14, 14) * u if not ui._glove_rects.is_empty() else r.end - Vector2(300, 640) * u, 5],   # 手袋
		[Vector2(x0 + 10.0 * u, r.position.y + 240.0 * u), 6],       # 名札と柄
		[(ui._inv_rects[0] as Rect2).position + Vector2(4, -4) * u if not ui._inv_rects.is_empty() else r.end - Vector2(600, 180) * u, 7],   # 手持ちとかばん
	]
	if not ui._inv_rects.is_empty():   # 双眼鏡が入っている枠
		for i in [0, 2, 6]:
			over.marks.append([(ui._inv_rects[i] as Rect2).get_center() + Vector2(26, -26) * u, 8])
	over.mode = "now"
	await _shot("now.png")
	ui.close_gear()
	c.bags[who] = [ITEMS[0], ITEMS[1], {}, {}, {}, {}, ITEMS[2], ITEMS[3], ITEMS[4], {}, {}, {}]
	c.hands[who] = -1
	await create_timer(0.4).timeout
	for m in (String(args.get("only", "A,B,C")).split(",")):
		over.mode = m
		await _shot(m + ".png")
	quit()
