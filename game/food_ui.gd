extends CanvasLayer
## 雪だるまの食べ物屋の売り場（番台で F）。文字は使わない（2026-11-01 代表と決めた。design/snowman-food/）。
## おじいさんの売り台（craft_ui.gd）と同じ作り: 緑のフェルトの板、クリーム色のカード、赤い丸の買うボタン、右上の × の縫い目。
##   左: ペレットのカード 22 枚（品書きの順。8 列 3 段）。カードの下に、値段の雪玉の数（綿の雪玉）
##   右の上: 選んだ品の、できあがった料理の絵と、調理の道（使う装置の絵を、使う順に矢印でつなぐ）
##   右のまんなか: 持っている雪玉（袖のストックと同じ綿の雪玉）。足りないぶんは赤い糸の空き
##   右の下: 買うボタン（雪玉 → 矢印 → 手袋）。買えないときは震える
## 閉じるのは ×、F、Esc。払いは雪玉（craft.gd の food_buy が emotes.gd の spend を呼ぶ）

const Icons := preload("res://hud_icons.gd")
const Craft := preload("res://craft.gd")
const Food := preload("res://food.gd")
const CraftIcons := preload("res://craft_icons.gd")

const COLS := 8

var main: Node
var craft: Node
var player: Node
var shop: Node               # 雪だるま（snowman_shop.gd）
var is_open := false
var _sel := -1
var _hover := -1
var _hover_btn := ""
var _rects: Array = []
var _buy_rect := Rect2()
var _close_rect := Rect2()
var _shake := 0.0
var _pop := 0.0              # 買えたときの、カードと雪玉のぽん
var _tex := {}
var _view: Control


func _ready() -> void:
	layer = 4
	_view = View.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)


func _who() -> int:
	return int(player.get("id")) if player else -1


func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


func balls() -> int:
	var hub = main.get("emotes") if main else null
	return hub.balls_of(_who()) if hub else 0


func open() -> void:
	if is_open or player == null or player.menu_open:
		return
	is_open = true
	_sel = -1
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)
	if shop:
		shop.greet()
	var hud = main.get("hud") if main else null
	if hud:
		hud.learn("food")


func close() -> void:
	if not is_open:
		return
	is_open = false
	_view.queue_redraw()   # 閉じた姿を描き直す（開いているあいだしか毎コマ描かないので）
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)


## 確かめ用: 品書きの i 番目を選ぶ
func select(i: int) -> void:
	_sel = clampi(i, -1, Food.ORDER.size() - 1)
	_view.queue_redraw()


## i 番目の札のようす（craft_icons.gd の card_state。どの店も同じ見え方。2026-11-10 代表）。払いは雪玉
func card_state(i: int) -> String:
	if i < 0 or i >= Food.ORDER.size():
		return ""
	var dish: String = Food.ORDER[i]
	return CraftIcons.card_state(preload("res://shop_locks.gd").locked("food:" + dish), false, Food.price(dish) <= balls(), craft.free_slot(_who()) >= 0)


## 選んでいるペレットを買う
func buy() -> bool:
	if _sel < 0:
		_shake = 1.0
		return false
	var dish: String = Food.ORDER[_sel]
	var ok: bool = craft.send({"kind": "food_buy", "who": _who(), "item": Food.item(dish)})
	if ok:
		_pop = 1.0
		if shop:
			shop.sold(dish, player)
	else:
		_shake = 1.0
	return ok


func _process(dt: float) -> void:
	_shake = maxf(0.0, _shake - dt * 2.5)
	_pop = maxf(0.0, _pop - dt * 2.5)
	if is_open:
		_view.queue_redraw()


func _hit(p: Vector2) -> int:
	for i in _rects.size():
		if (_rects[i] as Rect2).has_point(p):
			return i
	return -1


func _input(e: InputEvent) -> void:
	if not is_open:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_F]:
		close()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = _hit(e.position)
		_hover_btn = "buy" if _buy_rect.has_point(e.position) else ("close" if _close_rect.has_point(e.position) else "")
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close()
		elif _buy_rect.has_point(e.position):
			buy()
		else:
			var i := _hit(e.position)
			if i >= 0 and CraftIcons.pickable(card_state(i)):   # 雪玉が足りない・ロック・いっぱいの札は選べない
				_sel = i


class View extends Control:
	var ui: Node

	func _draw() -> void:
		if ui.is_open:
			_draw_shop(Icons.ui_scale(size.y))

	## 綿の雪玉（craft_ui.gd の袖のストックと同じ考え: ちぎった綿を丸めた角のある毛玉に、下の雪の影の青）
	func _cotton(c: Vector2, r: float, seed: int, a := 1.0) -> void:
		var pts := PackedVector2Array()
		for k in 13:
			var t := TAU * k / 13.0 + seed * 0.7
			var w := 1.0 + 0.06 * sin(seed * 12.9898 + k * 78.233) + 0.03 * cos(seed * 4.1 + k * 2.3)
			pts.append(c + Vector2(cos(t), sin(t)) * r * w)
		var sh := PackedVector2Array()
		for q in pts:
			sh.append(q + Vector2(1.2, 2.2) * r / 12.0)
		draw_colored_polygon(sh, Color(Icons.SHADOW, 0.35 * a))
		var uv := PackedVector2Array()
		for q in pts:
			uv.append((q - c) / (r * 1.6) + Vector2(seed * 0.37, seed * 0.21))
		draw_colored_polygon(pts, Color(0.98, 0.98, 0.96, a), uv, Icons.felt())
		draw_arc(c + Vector2(0, r * 0.15), r * 0.8, 0.3, PI - 0.3, 10, Color(0.72, 0.80, 0.92, 0.45 * a), r * 0.25, true)

	## 雪玉 n 個を c を中心に横に並べる（have より多いぶんは赤い糸の空きの輪）
	func _balls(c: Vector2, n: int, r: float, have := 99, a := 1.0) -> void:
		var step := r * 2.3
		var x0 := c.x - step * (n - 1) / 2.0
		for i in n:
			var p := Vector2(x0 + step * i, c.y)
			if i < have:
				_cotton(p, r, i + 3, a)
			else:
				Icons.screen()
				Icons.dashes(self, Icons.circ(p, r, 14), Icons.RED, 2.0, r * 0.45, r * 0.3, a, true)

	func _pic(t: Texture2D, c: Vector2, s: float, a := 1.0) -> void:
		if t == null:
			return
		draw_texture_rect(t, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, a))

	func _draw_shop(u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var have: int = ui.balls()
		var full: bool = craft.free_slot(who) < 0
		var w := 1040.0 * u
		var h := 600.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.44 - h / 2.0, w, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), Color(0.36, 0.42, 0.33), 0.98, false)
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		# 左: ペレットのカード
		var area_w := w * 0.7
		var gap := 10.0 * u
		var cw := (area_w - 40.0 * u) / COLS - gap
		var ch := 166.0 * u
		var rects: Array = []
		for i in Food.ORDER.size():
			var dish: String = Food.ORDER[i]
			var price := Food.price(dish)
			var st: String = ui.card_state(i)
			var card := Rect2(r.position.x + 30.0 * u + (i % COLS) * (cw + gap), r.position.y + 34.0 * u + (i / COLS) * (ch + 22.0 * u), cw, ch)
			var sel: bool = ui._sel == i
			if sel or ui._hover == i and CraftIcons.pickable(st):
				card.position.y -= (8.0 if sel else 4.0) * u
			rects.append(card)
			if st == "locked":   # まだ売っていない: 麻ひもの包み
				CraftIcons.wrap_card(self, card, u)
				continue
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 12.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			var pop := 1.0 + 0.15 * sin(ui._pop * PI) if sel else 1.0
			_pic(ui.tex(Food.pellet_icon(dish)), card.position + Vector2(cw / 2.0, ch * 0.4), cw * 1.45 * pop)
			_balls(card.position + Vector2(cw / 2.0, ch * 0.84), price, 8.0 * u, 99)
			if st == "money":   # 雪玉が足りない: グレー
				CraftIcons.shade_card(self, Icons.rr(card.position.x, card.position.y, cw, ch, 12.0 * u))
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		ui._rects = rects
		# 右の上: できあがる料理と、調理の道
		var rx := r.position.x + area_w + 14.0 * u
		var rw := w - area_w - 44.0 * u
		var top := r.position.y + 34.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(rx, top, rw, 250.0 * u, 14.0 * u), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
		if ui._sel >= 0:
			var dish: String = Food.ORDER[ui._sel]
			_pic(ui.tex(Food.dish_icon(dish)), Vector2(rx + rw / 2.0, top + 92.0 * u), 170.0 * u)
			var rt := Food.route(dish)
			var ds := 64.0 * u
			var step := ds + 30.0 * u
			var x0 := rx + rw / 2.0 - step * (rt.size() - 1) / 2.0
			for k in rt.size():
				var c := Vector2(x0 + step * k, top + 206.0 * u)
				_pic(ui.tex("res://props/kitchen/icons/%s.png" % rt[k]), c, ds)
				if k > 0:
					Icons.screen()
					Icons.arrow(self, c + Vector2(-step + ds * 0.5, 0), c + Vector2(-ds * 0.5, 0), Icons.THREAD, 1.0, 2.6 * u)
		# 右のまんなか: 持っている雪玉と、要る雪玉
		var by := top + 280.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(rx, by, rw, 84.0 * u, 14.0 * u), Color(0.20, 0.25, 0.46), 0.95, true, Color(0.70, 0.57, 0.38))
		var need: int = Food.price(Food.ORDER[ui._sel]) if ui._sel >= 0 else 0
		var shown := maxi(have, need)
		_balls(Vector2(rx + rw / 2.0, by + 42.0 * u), mini(shown, 5), 13.0 * u * (1.0 + 0.12 * sin(ui._pop * PI)), have)
		# 右の下: 買うボタン（雪玉 → 矢印 → 手袋）
		var shake: float = sin(ui._shake * 40.0) * 10.0 * u * ui._shake
		var bs := 136.0 * u
		var bc := Vector2(rx + rw / 2.0 + shake, r.position.y + 480.0 * u)
		ui._buy_rect = Rect2(bc - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
		var ready: bool = ui._sel >= 0 and need <= have and not full
		var big := 1.06 if ui._hover_btn == "buy" else 1.0
		Icons.screen()
		Icons.patch(self, Icons.circ(bc, bs * 0.5 * big, 28), Icons.RED if ready else Icons.RED.lerp(Icons.PAPER_EDGE, 0.6), 1.0, true, Icons.CAP)
		_cotton(bc + Vector2(-26.0, -2.0) * bs / 64.0 * big, 10.0 * bs / 64.0, 7)
		Icons._o = bc
		Icons._s = bs / 64.0 * big
		Icons.arrow(self, Vector2(-11, -2), Vector2(1, -2), Icons.CAP, 1.0, 2.2)
		Icons.mitten(self, Vector2(15, 0), 0.4, Icons.CAP, 1.0, true, 0.9)
		if full:   # 持ち物がいっぱい: 売り場の全体をグレーにして、巾着から物があふれる印（閉じる × だけは上に）
			CraftIcons.bag_full(self, r, u)
		# 右上: 閉じる（× の縫い目）
		var xs := 46.0 * u
		var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
		ui._close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
		Icons.screen()
		Icons.patch(self, Icons.circ(xc, xs * 0.5 * (1.08 if ui._hover_btn == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
		Icons._o = xc
		Icons._s = xs / 64.0
		Icons.thread(self, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)
