extends CanvasLayer
## 山男の売り場（山男に F）。文字は使わない。おじいさんの売り台（craft_ui.gd）・雪だるまの店（food_ui.gd）と同じ作り:
## フェルトの板（山男の上着の藍）、クリーム色のカード、赤い丸の買うボタン、右上の × の縫い目。
##   左: 棚の品物のカード（mountain_goods.gd の SHELF の順。焚き火セット・ペグ）。カードの下に値段のボタン。
##       まだ売っていない品目は、薄い絵を麻ひもで十字に縛ったカード（選べない。値段も出さない）
##   右の上: 財布のボタン。品物を選ぶと、その値段を上に赤い糸（足りないとき）で
##   右の下: 買うボタン（ボタン → 矢印 → 手袋）。買えないときは震える
## 閉じるのは ×、F、Esc。買うのは craft.gd の buy（ほかの人の画面にも配られ、山男がその人を向いてうなずく）

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Goods := preload("res://mountain_goods.gd")

const FELT := Color(0.22, 0.28, 0.48)   # 山男の上着の藍

var main: Node
var craft: Node
var player: Node
var shop: Node               # 山男（mountain_man.gd）
var is_open := false
var _sel := -1
var _hover := -1
var _hover_btn := ""
var _rects: Array = []
var _buy_rect := Rect2()
var _close_rect := Rect2()
var _shake := 0.0
var _pop := 0.0              # 買えたときの、カードと財布のぽん
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
		shop.shop_open = true
		shop.greet()
	var hud = main.get("hud") if main else null
	if hud:
		hud.learn("mountain")


func close() -> void:
	if not is_open:
		return
	is_open = false
	_view.queue_redraw()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)
	if shop:
		shop.shop_open = false


## 確かめ用: 棚の i 番目を選ぶ（売っていない品目は選べない）
func select(i: int) -> void:
	_sel = i if i >= 0 and i < Goods.SHELF.size() and Goods.sold(Goods.SHELF[i].item.kind) else -1
	_view.queue_redraw()


## 選んでいる品物を買う
func buy() -> bool:
	if _sel < 0:
		_shake = 1.0
		return false
	var ok: bool = craft.send({"kind": "buy", "who": _who(), "item": (Goods.SHELF[_sel].item as Dictionary).duplicate()})
	if ok:
		_pop = 1.0
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
			if i >= 0:
				select(i)


class View extends Control:
	var ui: Node

	func _draw() -> void:
		if ui.is_open:
			_draw_shop(Icons.ui_scale(size.y))

	func _draw_shop(u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var coins: int = craft.wallet(who)
		var full: bool = craft.free_slot(who) < 0
		var w := 1040.0 * u
		var h := 600.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.44 - h / 2.0, w, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), FELT, 0.98, false)
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		# 左: 棚の品物のカード（大きく、横に並べる。4 つまでは 1 段）
		var area_w := w * 0.7
		var n: int = Goods.SHELF.size()
		var per := mini(maxi(n, 2), 4)
		var gap := 22.0 * u
		var cw := (area_w - 40.0 * u - gap * (per - 1)) / per
		var ch := minf(cw * 1.3, (h - 80.0 * u) / ceilf(float(n) / per) - gap)
		var rects: Array = []
		for i in n:
			var e: Dictionary = Goods.SHELF[i]
			var on := Goods.sold(e.item.kind)
			var cost: int = Goods.price(e.item.kind)
			var can := on and cost <= coins and not full
			var card := Rect2(r.position.x + 30.0 * u + (i % per) * (cw + gap), r.position.y + 50.0 * u + (i / per) * (ch + gap), cw, ch)
			var sel: bool = ui._sel == i
			if on and (sel or ui._hover == i):
				card.position.y -= (8.0 if sel else 4.0) * u
			rects.append(card)
			Icons.screen()
			var a := 1.0 if can else (0.5 if on else 0.3)
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 14.0 * u), Icons.CAP, 1.0 if on else 0.6, on, Icons.PAPER_EDGE)
			var pop := 1.0 + 0.15 * sin(ui._pop * PI) if sel else 1.0
			CraftIcons.item(self, e.item, card.position + Vector2(cw / 2.0, ch * 0.4), minf(cw, ch * 0.7) * 0.8 * pop, a)
			Icons.screen()
			if on:
				CraftIcons.price(self, card.position + Vector2(cw / 2.0, ch * 0.85), cost, 13.0 * u, a)
			else:   # まだ売っていない: 麻ひもで十字に縛った包み
				var hemp := Color(0.78, 0.66, 0.46)
				var c := card.get_center() + Vector2(0, -ch * 0.06)
				Icons.thread(self, PackedVector2Array([Vector2(card.position.x + 6 * u, c.y), Vector2(card.end.x - 6 * u, c.y)]), hemp, 5.0 * u, 0.95)
				Icons.thread(self, PackedVector2Array([Vector2(c.x, card.position.y + 6 * u), Vector2(c.x, card.end.y - 6 * u)]), hemp, 5.0 * u, 0.95)
				for s in [-1.0, 1.0]:   # 蝶結び
					Icons.patch(self, Icons.ell(c + Vector2(s * 13.0 * u, -4.0 * u), 12.0 * u, 7.0 * u, 14), hemp, 1.0, false)
				Icons.patch(self, Icons.circ(c, 5.0 * u, 10), hemp.darkened(0.15), 1.0, false)
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 16.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		ui._rects = rects
		# 右の上: 財布（持っているボタン）と、選んだ品物の値段
		var rx := r.position.x + area_w + 14.0 * u
		var rw := w - area_w - 44.0 * u
		var top := r.position.y + 50.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(rx, top, rw, 250.0 * u, 14.0 * u), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
		if ui._sel >= 0:
			var need: int = Goods.price(Goods.SHELF[ui._sel].item.kind)
			CraftIcons.price(self, Vector2(rx + rw / 2.0, top + 50.0 * u), need, 13.0 * u, 1.0, Icons.RED if need > coins else CraftIcons.COIN)
			Icons.screen()
			Icons.arrow(self, Vector2(rx + rw / 2.0, top + 150.0 * u), Vector2(rx + rw / 2.0, top + 105.0 * u), Icons.THREAD, 0.8, 2.6 * u)
		CraftIcons.price(self, Vector2(rx + rw / 2.0, top + 200.0 * u), coins, 13.0 * u * (1.0 + 0.2 * sin(ui._pop * PI)), 1.0)
		# 右の下: 買うボタン（ボタン → 矢印 → 手袋）
		var shake: float = sin(ui._shake * 40.0) * 10.0 * u * ui._shake
		var bs := 150.0 * u
		var bc := Vector2(rx + rw / 2.0 + shake, r.position.y + 440.0 * u)
		ui._buy_rect = Rect2(bc - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
		var ready: bool = ui._sel >= 0 and Goods.price(Goods.SHELF[ui._sel].item.kind) <= coins and not full
		var big := 1.06 if ui._hover_btn == "buy" else 1.0
		Icons.screen()
		Icons.patch(self, Icons.circ(bc, bs * 0.5 * big, 28), Icons.RED if ready else Icons.RED.lerp(Icons.PAPER_EDGE, 0.6), 1.0, true, Icons.CAP)
		Icons._o = bc
		Icons._s = bs / 64.0 * big
		CraftIcons.coin(self, Vector2(-12, -2), 9.0, 1.0)
		Icons.arrow(self, Vector2(-1, -2), Vector2(9, -2), Icons.CAP, 1.0, 2.2)
		Icons.mitten(self, Vector2(17, 0), 0.4, Icons.CAP, 1.0, true, 0.9)
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
