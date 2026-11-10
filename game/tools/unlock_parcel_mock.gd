extends SceneTree
## 案の絵（まだ作っていない）: 解放の品（一度買えばずっと持つ品）を、店で小包の見え方にする（2026-11-10 代表
## 「UNLOCK系のやつが小包になってなくない？小包の上に金額を乗せてほしい。お金が足りなくて変えないときはグレーの小包で、買えるときは色のある小包にするのは？」）。
## 店の画面と同じ部品（hud_icons.gd・craft_icons.gd）で、上から 4 段: 今・案 1・案 2・案 3。
## どの段も左から 4 枚: 買える（色のある小包）・お金が足りない（グレーの小包）・買ったあと（開いた包みと中身、針の印）・まだ売っていない（ロック）。
##   案 1: 小包のひもに、中身の小さな絵の荷札。ロックはクラフト紙の包みに赤い封蝋（値段なし）
##   案 2: 小包の前に薄紙の丸い窓があり、中身が透ける。ロックは板を打ちつけた木箱（値段なし）
##   案 3: 手がかりなし（色と値段だけ）。ロックはクラフト紙の包みに雪が積もる（値段なし）
##   Godot --path game --resolution 1600x1000 -s res://tools/unlock_parcel_mock.gd -- --out=/path/look.png

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Goods := preload("res://mountain_goods.gd")

const FELT := Color(0.22, 0.28, 0.48)       # 山師の板の藍
const WRAP_RED := Color(0.78, 0.30, 0.24)   # 色のある小包の包み紙（朱）
const GRAY_PAPER := Color(0.66, 0.66, 0.68)
const GRAY_TWINE := Color(0.82, 0.82, 0.84)
const WAX := Color(0.66, 0.12, 0.12)
const ITEMS := [   # [品物, ようす]
	[{"kind": "gloves_felt"}, "can"],
	[{"kind": "binoculars_night"}, "money"],
	[{"kind": "gloves"}, "owned"],
	[{"kind": "binoculars_far"}, "locked"],
]

var args := {}


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.93, 0.92, 0.89))
		var rows := 4
		var rh := size.y / rows
		for row in rows:
			var board := Rect2(16, row * rh + 8, size.x - 32, rh - 16)
			Icons.screen()
			Icons.patch(self, Icons.rr(board.position.x, board.position.y, board.size.x, board.size.y, 18), FELT, 0.98, false)
			Icons.dashes(self, Icons.rr(board.position.x + 8, board.position.y + 8, board.size.x - 16, board.size.y - 16, 14), Icons.CAP, 2.0, 7.0, 5.0, 0.8, true)
			var mk := Vector2(board.position.x + 44, board.get_center().y)
			Icons.screen()
			if row == 0:
				Icons.icon(self, "needle", mk, 50, 0.8)
			else:
				for i in row:
					Icons.patch(self, Icons.circ(mk + Vector2(0, (i - (row - 1) * 0.5) * 22), 8, 12), Icons.RED, 1.0, false)
			var ch := board.size.y - 30
			var cw := ch * 0.82
			var step := (board.size.x - 120) / 4.0
			for i in 4:
				var card := Rect2(board.position.x + 100 + i * step + (step - cw) / 2.0, board.position.y + 15, cw, ch)
				if i == 3:   # ロックの前に、糸の区切り
					var x := board.position.x + 100 + i * step - 2
					Icons.dashes(self, PackedVector2Array([Vector2(x, board.position.y + 20), Vector2(x, board.end.y - 20)]), Icons.CAP, 2.0, 6.0, 5.0, 0.5)
				_card(row, card, ITEMS[i][0], ITEMS[i][1])

	func _card(row: int, card: Rect2, it: Dictionary, st: String) -> void:
		var cost := Goods.price(String(it.kind))
		if row == 0:
			_now(card, it, st, cost)
			return
		match st:
			"can":
				_parcel(card, it, cost, false, row)
			"money":
				_parcel(card, it, cost, true, row)
			"owned":
				_opened(card, it)
			"locked":
				match row:
					1: _lock_wax(card)
					2: _lock_crate(card)
					3: _lock_snow(card)

	## 今（#233）: ふつうの札に値段、足りなければグレー、持っていれば針、ロックは麻ひもの包み
	func _now(card: Rect2, it: Dictionary, st: String, cost: int) -> void:
		if st == "locked":
			CraftIcons.wrap_card(self, card, 1.0)
			return
		var cw := card.size.x
		var ch := card.size.y
		Icons.screen()
		Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 14.0), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
		CraftIcons.item(self, it, card.position + Vector2(cw / 2.0, ch * 0.4), minf(cw, ch * 0.7) * 0.8)
		Icons.screen()
		if st == "owned":
			Icons.icon(self, "needle", card.position + Vector2(cw / 2.0, ch * 0.85), 34.0, 1.0)
		else:
			CraftIcons.price(self, card.position + Vector2(cw / 2.0, ch * 0.85), cost, 13.0)
		if st == "money":
			CraftIcons.shade_card(self, Icons.rr(card.position.x, card.position.y, cw, ch, 14.0))

	## 小包の形（前・上・横の面）。札 card の中の箱
	func _box(card: Rect2) -> Dictionary:
		var w := card.size.x
		var h := card.size.y
		var d := w * 0.13
		var off := Vector2(d, -d * 0.75)
		var f := Rect2(card.position + Vector2(w * 0.04, h * 0.40), Vector2(w * 0.80, h * 0.56))
		var tl := f.position
		var tr := Vector2(f.end.x, f.position.y)
		var br := f.end
		return {"front": f, "off": off,
			"top": PackedVector2Array([tl, tr, tr + off, tl + off]),
			"side": PackedVector2Array([tr, tr + off, br + off, br])}

	## 買える・お金が足りない小包。上の面に値段のボタンが乗る。gray ならグレーの紙とひも（選べない）
	func _parcel(card: Rect2, it: Dictionary, cost: int, gray: bool, row: int) -> void:
		var b := _box(card)
		var f: Rect2 = b.front
		var off: Vector2 = b.off
		var paper := GRAY_PAPER if gray else WRAP_RED
		var twine := GRAY_TWINE if gray else Icons.CAP
		Icons.screen()
		var front := Icons.rr(f.position.x, f.position.y, f.size.x, f.size.y, 3.0)
		Icons.patch(self, b.side, paper.darkened(0.22), 1.0, false)
		Icons.patch(self, b.top, paper.lightened(0.14), 1.0, false)
		Icons.patch(self, front, paper, 1.0, true, paper.darkened(0.35))
		# 包み紙の水玉（色のある紙。グレーでも同じ柄が沈む）
		for k in 9:
			var p := f.position + Vector2(f.size.x * (0.16 + 0.34 * (k % 3)) + (k / 3 % 2) * f.size.x * 0.17, f.size.y * (0.16 + 0.32 * (k / 3)))
			draw_circle(p, f.size.x * 0.035, Color(paper.lightened(0.45), 0.8))
		# ひも: 前の縦と横、上の面へ続く縦、横の面へ続く横
		var cx := f.get_center().x
		var cy := f.get_center().y
		var tw := maxf(3.0, f.size.x * 0.035)
		Icons.thread(self, PackedVector2Array([Vector2(cx, f.position.y), Vector2(cx, f.end.y)]), twine, tw, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(f.position.x, cy), Vector2(f.end.x, cy)]), twine, tw, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(cx, f.position.y), Vector2(cx, f.position.y) + off]), twine, tw, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(f.end.x, cy), Vector2(f.end.x, cy) + off]), twine, tw, 1.0)
		if not gray:   # 紅白のひも: 白の上に赤の撚り
			Icons.dashes(self, PackedVector2Array([Vector2(cx, f.position.y), Vector2(cx, f.end.y)]), Icons.RED, tw * 0.6, 5.0, 5.0, 0.9)
			Icons.dashes(self, PackedVector2Array([Vector2(f.position.x, cy), Vector2(f.end.x, cy)]), Icons.RED, tw * 0.6, 5.0, 5.0, 0.9)
		# 窓（案 2）: 前の面の上半分に、薄紙の丸い窓から中身が透ける
		if row == 2:
			var wc := Vector2(f.position.x + f.size.x * 0.28, f.position.y + f.size.y * 0.30)
			var wr := f.size.x * 0.22
			Icons.screen()
			Icons.patch(self, Icons.circ(wc, wr, 24), Icons.PAPER, 1.0, false)
			CraftIcons.item(self, it, wc, wr * 1.6, 0.9)
			Icons.screen()
			draw_colored_polygon(Icons.circ(wc, wr, 24), Color(1, 1, 1, 0.28))
			Icons.dashes(self, Icons.circ(wc, wr, 24), paper.darkened(0.4), 1.6, 4.0, 3.0, 1.0, true)
		# 蝶結び（ひもの交わる所）
		_bow(Vector2(cx, cy), f.size.x * 0.11, twine, tw)
		# 荷札（案 1）: 蝶結びから下がる紙の札に、中身の小さな絵
		if row == 1:
			var tg := Rect2(Vector2(cx + f.size.x * 0.06, cy + f.size.y * 0.08), Vector2(f.size.x * 0.40, f.size.y * 0.40))
			Icons.thread(self, PackedVector2Array([Vector2(cx, cy), tg.position + Vector2(8, 8)]), twine.darkened(0.15), 1.6, 1.0)
			_tag(tg, it)
		# 値段: 上の面に乗るボタン
		var top_c := Vector2(cx, f.position.y) + off * 0.5
		var r := card.size.x * 0.075
		var n := (preload("res://craft.gd").pieces(cost) as Array).size()
		var rows := ceili(n / 3.0)
		if gray:   # 小包をまとめてグレーに沈める（選べない）
			Icons.screen()
			var sh := Color(0.50, 0.50, 0.53, 0.55)
			draw_colored_polygon(b.side, sh)
			draw_colored_polygon(b.top, sh)
			draw_colored_polygon(front, sh)
		CraftIcons.price(self, top_c - Vector2(0, r * 0.9 + (rows - 1) * r * 1.05), cost, r, 0.55 if gray else 1.0, GRAY_PAPER if gray else CraftIcons.COIN)

	func _bow(c: Vector2, b: float, col: Color, tw: float) -> void:
		Icons.screen()
		for s in [-1.0, 1.0]:
			Icons.patch(self, Icons.ell(c + Vector2(s * b * 1.1, -b * 0.35), b, b * 0.6, 14), col, 1.0, false)
			Icons.thread(self, PackedVector2Array([c, c + Vector2(s * b * 0.8, b * 1.6)]), col.darkened(0.1), tw * 0.8, 1.0)
		Icons.patch(self, Icons.circ(c, b * 0.45, 10), col.darkened(0.15), 1.0, false)

	## 荷札: 角を切った生成りの紙に、はとめと、中身の小さな絵
	func _tag(r: Rect2, it: Dictionary) -> void:
		Icons.screen()
		var cut := r.size.x * 0.22
		var pts := PackedVector2Array([Vector2(r.position.x + cut, r.position.y), Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y + cut)])
		Icons.patch(self, pts, Icons.PAPER, 1.0, true, Icons.THREAD)
		draw_circle(r.position + Vector2(cut * 0.55, cut * 0.55), 3.4, Icons.PAPER_EDGE)
		CraftIcons.item(self, it, r.get_center() + Vector2(r.size.x * 0.04, r.size.y * 0.06), r.size.x * 0.78)
		Icons.screen()

	## 買ったあと: 札の上に、開いた包み紙（4 枚の折り返し）とほどけたひも、その上に中身。下に針の印
	func _opened(card: Rect2, it: Dictionary) -> void:
		var cw := card.size.x
		var ch := card.size.y
		Icons.screen()
		Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 14.0), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
		var c := card.position + Vector2(cw / 2.0, ch * 0.42)
		var s := cw * 0.34
		for k in 4:   # 開いた包み紙: 中から 4 方へ倒れた折り返し
			var a := k * PI / 2.0 + PI / 4.0
			var tip := c + Vector2.from_angle(a) * s * 1.35
			var l := c + Vector2.from_angle(a - 0.62) * s * 0.75
			var rr := c + Vector2.from_angle(a + 0.62) * s * 0.75
			Icons.patch(self, PackedVector2Array([l, tip, rr]), WRAP_RED.lightened(0.05 * k), 1.0, false)
		Icons.patch(self, Icons.rr(c.x - s * 0.75, c.y - s * 0.75, s * 1.5, s * 1.5, 4.0), Icons.PAPER.darkened(0.04), 1.0, true, WRAP_RED.darkened(0.2))   # 包み紙の裏（生成り）
		var curl := PackedVector2Array()   # ほどけたひも
		for k in 14:
			var t := k / 13.0
			curl.append(c + Vector2(lerpf(-s * 1.2, s * 1.25, t), s * 0.95 + sin(t * TAU * 1.3) * s * 0.12))
		Icons.thread(self, curl, Icons.CAP, 3.0, 1.0)
		Icons.dashes(self, curl, Icons.RED, 1.8, 5.0, 5.0, 0.9)
		CraftIcons.item(self, it, c, minf(cw, ch * 0.7) * 0.72)
		Icons.screen()
		Icons.icon(self, "needle", card.position + Vector2(cw / 2.0, ch * 0.87), 34.0, 1.0)

	## ロック 案 1: 今の麻ひもの包み（値段なし）の結び目に、赤い封蝋（雪の結晶の型押し）
	func _lock_wax(card: Rect2) -> void:
		CraftIcons.wrap_card(self, card, 1.0)
		var c := card.get_center() + Vector2(0, -card.size.y * 0.06)
		var r := card.size.x * 0.16
		var blob := PackedVector2Array()
		for k in 22:
			var a := TAU * k / 22.0
			blob.append(c + Vector2.from_angle(a) * r * (1.0 + 0.09 * sin(a * 5.0) + 0.05 * sin(a * 3.0 + 1.0)))
		Icons.screen()
		Icons.patch(self, blob, WAX, 1.0, false)
		draw_arc(c, r * 0.68, 0, TAU, 24, WAX.darkened(0.35), 2.2, true)
		for k in 3:   # 雪の結晶の型押し
			var d := Vector2.from_angle(k * PI / 3.0) * r * 0.5
			draw_line(c - d, c + d, WAX.lightened(0.25), 2.0, true)
		draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.12, Color(1, 1, 1, 0.25))

	## ロック 案 2: 板を打ちつけた木箱（値段なし）
	func _lock_crate(card: Rect2) -> void:
		var b := _box(card)
		var f: Rect2 = b.front
		var wood := Icons.WOOD.lightened(0.18)
		Icons.screen()
		Icons.patch(self, b.side, wood.darkened(0.25), 1.0, false)
		Icons.patch(self, b.top, wood.lightened(0.1), 1.0, false)
		var n := 3
		var ph := f.size.y / n
		for k in n:   # 横の板
			Icons.patch(self, Icons.rr(f.position.x, f.position.y + k * ph + 1, f.size.x, ph - 2, 3.0), wood.darkened(0.04 * k), 1.0, true, wood.darkened(0.45))
		for s in [0, 1]:   # 斜めに打ちつけた 2 枚の板
			var a := f.position + Vector2(0, 0) if s == 0 else Vector2(f.end.x, f.position.y)
			var z := f.end if s == 0 else Vector2(f.position.x, f.end.y)
			var dir := (z - a).normalized()
			var nrm := Vector2(-dir.y, dir.x) * f.size.y * 0.075
			Icons.patch(self, PackedVector2Array([a - nrm, z - nrm, z + nrm, a + nrm]), wood.darkened(0.18), 1.0, true, wood.darkened(0.5))
			for t in [0.08, 0.5, 0.92]:   # 釘
				var p := a.lerp(z, t)
				draw_circle(p, 3.4, Color(0.30, 0.30, 0.33))
				draw_circle(p + Vector2(-0.8, -0.8), 1.4, Color(0.75, 0.75, 0.78))

	## ロック 案 3: 今の麻ひもの包み（値段なし）に雪が積もる
	func _lock_snow(card: Rect2) -> void:
		CraftIcons.wrap_card(self, card, 1.0)
		Icons.screen()
		var w := card.size.x
		var top := PackedVector2Array()   # 上の縁に積もった雪
		for k in 25:
			var t := k / 24.0
			top.append(card.position + Vector2(t * w, 6.0 - sin(t * PI) * card.size.y * 0.1 - sin(t * 17.0) * 3.0))
		top.append(card.position + Vector2(w, card.size.y * 0.1))
		top.append(card.position + Vector2(0, card.size.y * 0.1))
		Icons.patch(self, top, Icons.SNOW, 1.0, false)
		for k in 5:   # 前に貼りついた雪のかたまり
			Icons.cotton(self, card.position + Vector2(w * (0.12 + 0.19 * k), card.size.y * (0.12 + 0.04 * (k % 2))), w * 0.075, 11 + k, 1.0)
		Icons.screen()
		for k in 6:   # 舞う雪
			draw_circle(card.position + Vector2(w * (0.1 + 0.16 * k), card.size.y * (0.35 + 0.1 * (k % 3))), 3.0, Color(1, 1, 1, 0.8))


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var s := Sheet.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(s)
	_run.call_deferred()


func _run() -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := String(args.get("out", "/tmp/unlock_parcel.png"))
	root.get_texture().get_image().save_png(out)
	print("撮った: ", out)
	quit(0)
