extends SceneTree
## 案の絵（2026-11-10。代表が案 A に決め、craft_icons.gd の foot・over として作った）: 解放の品の札を、よくあるゲームの店の見せ方にする（2026-11-10 代表
## 「いやーーなんかアンロックUIが直感的に理解しづらいな。一般的なゲームのやりかたにしてほしい」）。
## 品物の絵は包みで隠さず見せる。字は使わず、数は値段のボタンの数。
## 上から 3 段: 今（#235 の包み）・案 A（値札とチェック）・案 B（暗くして角の印）。
## どの段も左から 5 枚: 買える・お金が足りない・持っている・身につけている・まだ解放できない（ロック）。
##   Godot --path game --resolution 1400x900 -s res://tools/unlock_card_mock.gd -- --out=/path/look.png

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Goods := preload("res://mountain_goods.gd")

const FELT := Color(0.22, 0.28, 0.48)       # 山師の板の藍
const CHECK := Color(0.30, 0.55, 0.34)      # 持っている印の緑のフェルト
const BRASS := Color(0.80, 0.62, 0.26)      # 南京錠の真鍮
const ITEMS := [   # [品物, ようす]
	[{"kind": "gloves_felt"}, "can"],
	[{"kind": "binoculars_night"}, "money"],
	[{"kind": "gloves"}, "owned"],
	[{"kind": "binoculars"}, "worn"],
	[{"kind": "binoculars_far"}, "locked"],
]

var args := {}


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.93, 0.92, 0.89))
		var rows := 3
		var rh := size.y / rows
		for row in rows:
			var board := Rect2(16, row * rh + 8, size.x - 32, rh - 16)
			Icons.screen()
			Icons.patch(self, Icons.rr(board.position.x, board.position.y, board.size.x, board.size.y, 18), FELT, 0.98, false)
			Icons.dashes(self, Icons.rr(board.position.x + 8, board.position.y + 8, board.size.x - 16, board.size.y - 16, 14), Icons.CAP, 2.0, 7.0, 5.0, 0.8, true)
			var mk := Vector2(board.position.x + 40, board.get_center().y)
			Icons.screen()
			if row == 0:
				Icons.icon(self, "needle", mk, 50, 0.8)
			else:
				for i in row:
					Icons.patch(self, Icons.circ(mk + Vector2(0, (i - (row - 1) * 0.5) * 22), 8, 12), Icons.RED, 1.0, false)
			var ch := board.size.y - 56
			var cw := ch * 0.78
			var step := (board.size.x - 100) / 5.0
			for i in 5:
				var card := Rect2(board.position.x + 84 + i * step + (step - cw) / 2.0, board.position.y + 30, cw, ch)
				_card(row, card, ITEMS[i][0], ITEMS[i][1])

	func _card(row: int, card: Rect2, it: Dictionary, st: String) -> void:
		var cost := Goods.price(String(it.kind))
		match row:
			0: _now(card, it, st, cost)
			1: _a(card, it, st, cost)
			2: _b(card, it, st, cost)

	## 今（#235 の包み）: 部品（parcel・unwrapped・wrap_card）は案 A を作ったときに外した。そのときの絵は design/unlock-card-look/proposal_cards.jpg
	func _now(card: Rect2, _it: Dictionary, _st: String, _cost: int) -> void:
		_plain(card, Icons.CAP.darkened(0.3))

	## 案 A（値札とチェック）: 札はいつも品物の絵を見せる。値段は札の下の紙の値札にボタン。
	## 足りない: 札はそのまま、値札のボタンと縁が赤（選べない）。持っている: 値札の代わりに緑のチェックのワッペン。
	## 身につけている: チェックに加えて、札のまわりに赤い糸の太い縁。ロック: 品物は薄い影だけ、まんなかに真鍮の南京錠、値札なし
	func _a(card: Rect2, it: Dictionary, st: String, cost: int) -> void:
		_plain(card, Icons.CAP if st != "locked" else Icons.CAP.darkened(0.22))
		var foot := card.position + Vector2(card.size.x / 2.0, card.size.y * 0.84)
		match st:
			"can", "money":
				CraftIcons.item(self, it, _art(card), _art_size(card))
				_price_tag(foot, card.size.x * 0.78, cost, st == "money")
			"owned", "worn":
				CraftIcons.item(self, it, _art(card), _art_size(card))
				_check(foot, card.size.x * 0.24)
				if st == "worn":
					_frame(card)
			"locked":
				CraftIcons.item(self, it, _art(card), _art_size(card), 0.18)
				_padlock(card.get_center() + Vector2(0, -card.size.y * 0.02), card.size.x * 0.4)

	## 案 B（暗くして角の印）: 足りない: 札ごと暗いグレーにかぶせ（品物は見える）、値段のボタンだけ赤く上に残す。
	## 持っている: 値段の所は空け、札の右上の角に緑のチェック。身につけている: 角のチェックと、札の下に赤いフェルトの帯（あなたの印の結び目）。
	## ロック: 札は藍に沈み、品物は薄い影、値段の所に南京錠
	func _b(card: Rect2, it: Dictionary, st: String, cost: int) -> void:
		var foot := card.position + Vector2(card.size.x / 2.0, card.size.y * 0.85)
		match st:
			"can":
				_plain(card)
				CraftIcons.item(self, it, _art(card), _art_size(card))
				CraftIcons.price(self, foot, cost, card.size.x * 0.075)
			"money":
				_plain(card)
				CraftIcons.item(self, it, _art(card), _art_size(card))
				Icons.screen()
				draw_colored_polygon(Icons.rr(card.position.x, card.position.y, card.size.x, card.size.y, 14.0), Color(0.30, 0.30, 0.34, 0.55))
				CraftIcons.price(self, foot, cost, card.size.x * 0.075, 1.0, Icons.RED)
				Icons.screen()   # 足りない値段: 下に赤い糸の線（どのボタンでも赤が見えるように）
				Icons.thread(self, PackedVector2Array([foot + Vector2(-card.size.x * 0.3, card.size.x * 0.1), foot + Vector2(card.size.x * 0.3, card.size.x * 0.1)]), Icons.RED, 3.0, 1.0)
			"owned", "worn":
				_plain(card)
				CraftIcons.item(self, it, _art(card), _art_size(card))
				_check(card.position + Vector2(card.size.x - 6.0, 6.0), card.size.x * 0.24)
				if st == "worn":
					var band := Rect2(card.position.x - 4.0, card.end.y - card.size.y * 0.2, card.size.x + 8.0, card.size.y * 0.13)
					Icons.screen()
					Icons.patch(self, Icons.rr(band.position.x, band.position.y, band.size.x, band.size.y, 4.0), Icons.RED, 1.0, true, Icons.RED.darkened(0.4))
					_knot(band.get_center())
			"locked":
				_plain(card, Color(0.30, 0.34, 0.48))
				CraftIcons.item(self, it, _art(card), _art_size(card), 0.22)
				_padlock(foot + Vector2(0, -card.size.y * 0.02), card.size.x * 0.3)

	func _art(card: Rect2) -> Vector2:
		return card.position + Vector2(card.size.x / 2.0, card.size.y * 0.4)

	func _art_size(card: Rect2) -> float:
		return minf(card.size.x, card.size.y * 0.7) * 0.8

	func _plain(card: Rect2, col := Icons.CAP) -> void:
		Icons.screen()
		Icons.patch(self, Icons.rr(card.position.x, card.position.y, card.size.x, card.size.y, 14.0), col, 1.0, true, Icons.PAPER_EDGE)

	## 紙の値札: 横長の生成りの札の左にはとめと糸、中にボタン。short なら縁の糸とボタンが赤
	func _price_tag(c: Vector2, w: float, cost: int, short: bool) -> void:
		var r := w * 0.095
		var n := (preload("res://craft.gd").pieces(cost) as Array).size()
		var rows := ceili(n / 3.0)
		var h := rows * r * 2.1 + r * 0.9
		var rect := Rect2(c - Vector2(w / 2.0, h / 2.0), Vector2(w, h))
		var cut := minf(h * 0.4, 14.0)
		var pts := PackedVector2Array([Vector2(rect.position.x + cut, rect.position.y), Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x + cut, rect.end.y), Vector2(rect.position.x, rect.get_center().y)])
		Icons.screen()
		Icons.patch(self, pts, Icons.PAPER, 1.0, true, Icons.RED if short else Icons.THREAD)
		if short:
			draw_polyline(pts + PackedVector2Array([pts[0]]), Icons.RED, 2.4, true)
		draw_circle(Vector2(rect.position.x + cut * 0.9, rect.get_center().y), 3.0, Icons.PAPER_EDGE)
		CraftIcons.price(self, rect.get_center() + Vector2(cut * 0.5, 0), cost, r, 1.0, Icons.RED if short else CraftIcons.COIN)
		Icons.screen()

	## 持っている印: 緑のフェルトの丸に、白い糸のチェック
	func _check(c: Vector2, s: float) -> void:
		Icons.screen()
		Icons.patch(self, Icons.circ(c, s * 0.5, 22), CHECK, 1.0, true, CHECK.darkened(0.4))
		Icons.thread(self, PackedVector2Array([c + Vector2(-s * 0.24, 0), c + Vector2(-s * 0.06, s * 0.18), c + Vector2(s * 0.26, -s * 0.2)]), Icons.CAP, maxf(2.4, s * 0.1), 1.0)

	## 身につけている縁: 札のまわりに赤い糸の太い縁（二重の縫い目）
	func _frame(card: Rect2) -> void:
		Icons.screen()
		for k in 2:
			var g := 5.0 + k * 5.0
			Icons.dashes(self, Icons.rr(card.position.x - g, card.position.y - g, card.size.x + g * 2.0, card.size.y + g * 2.0, 14.0 + g), Icons.RED, 3.2, 8.0, 3.0, 1.0, true)

	## あなたの印の赤い糸の結び目（紙細工屋さん・連れと同じ）
	func _knot(c: Vector2) -> void:
		draw_circle(c, 9.0, Icons.RED)
		draw_arc(c, 9.0, 0, TAU, 18, Icons.RED.darkened(0.4), 1.6, true)
		for s in [-1.0, 1.0]:
			draw_line(c + Vector2(s * 6.0, 4.0), c + Vector2(s * 14.0, 20.0), Icons.RED, 3.0, true)

	## 南京錠: 鈍い鉄の掛け金（太い糸の弧）と、真鍮のフェルトの錠の体、鍵穴
	func _padlock(c: Vector2, s: float) -> void:
		Icons.screen()
		var arc := PackedVector2Array()
		for k in 15:
			var a := PI + PI * k / 14.0
			arc.append(c + Vector2(0, -s * 0.12) + Vector2(cos(a) * s * 0.26, sin(a) * s * 0.34))
		Icons.thread(self, arc, Color(0.55, 0.56, 0.60), s * 0.09, 1.0)
		var body := Rect2(c + Vector2(-s * 0.4, -s * 0.14), Vector2(s * 0.8, s * 0.62))
		Icons.patch(self, Icons.rr(body.position.x, body.position.y, body.size.x, body.size.y, s * 0.1), BRASS, 1.0, true, BRASS.darkened(0.45))
		var kc := body.get_center() + Vector2(0, -s * 0.05)
		draw_circle(kc, s * 0.08, Color(0.22, 0.16, 0.10))
		draw_colored_polygon(PackedVector2Array([kc + Vector2(-s * 0.04, 0), kc + Vector2(s * 0.04, 0), kc + Vector2(s * 0.06, s * 0.17), kc + Vector2(-s * 0.06, s * 0.17)]), Color(0.22, 0.16, 0.10))


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
	var out := String(args.get("out", "/tmp/unlock_card.png"))
	root.get_texture().get_image().save_png(out)
	print("撮った: ", out)
	quit(0)
