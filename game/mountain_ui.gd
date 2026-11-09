extends CanvasLayer
## 山男の売り場（山男に F）。文字は使わない。おじいさんの売り台（craft_ui.gd）・雪だるまの店（food_ui.gd）と同じ作り:
## フェルトの板（山男の上着の藍）、クリーム色のカード、赤い丸の買うボタン、右上の × の縫い目。
##   左: 棚の品物のカード（mountain_goods.gd の SHELF の順。焚き火セット・ペグ・双眼鏡・雪玉ころがしの手袋）。カードの下に値段のボタン。
##       手袋は装備なので持ち物がいっぱいでも買え、持っている段は値段の代わりに針の印（もう買えない）
##       まだ売っていない品目は、薄い絵を麻ひもで十字に縛ったカード（選べない。値段も出さない）
##   右の上: 財布のボタン。品物を選ぶと、その値段を上に赤い糸（足りないとき）で
##   右の下: 買うボタン（ボタン → 矢印 → 手袋）。買えないときは震える
##   左の端: 段の札 3 枚。上が「道具」（この画面）、まんなかが「連れ」（山師が育てているミニオン。押すと、ミニオンの画面
##       main.gd の minion_ui＝pals_ui.gd の連れの段だけ を開く。2026-11-02 代表「ミニオンは山師が育てているのを買う感じにしてほしい」）、
##       下が「雪玉の柄」（大玉の縫い目の柄。ball_stitches.gd。2026-11-09 代表「雪玉のステッチも売って欲しい」）。手袋と同じ山師の棚で売る。
##       柄の棚は、縫い目を縫った玉の絵のカードが安い順に並び、糸はいまはめている手袋の色（はめていなければ毛糸）。持ち物の場所は使わず、
##       人ごとに一度買えばよい。買った柄は値段の代わりに針の印。選ぶのは持ち物の画面（craft_ui.gd）
## 閉じるのは ×、F、Esc。買うのは craft.gd の buy（ほかの人の画面にも配られ、山男がその人を向いてうなずく）

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Goods := preload("res://mountain_goods.gd")
const Gloves := preload("res://gloves.gd")
const BallStitches := preload("res://ball_stitches.gd")

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
var _tab_rects: Array = []   # 左の段の札（0 道具、1 連れ、2 雪玉の柄）
var page := 0                # 開いている棚（0 道具、2 雪玉の柄。連れは別の画面）
var _ball_goods: Array = BallStitches.for_sale()   # 売っている大玉の柄の名前
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
	page = 0
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
	if page == 2:
		_sel = i if i >= 0 and i < _ball_goods.size() else -1
	else:
		_sel = i if i >= 0 and i < Goods.SHELF.size() and Goods.sold(Goods.SHELF[i].item.kind) else -1
	_view.queue_redraw()


## 棚を替える（0 道具、2 雪玉の柄）
func set_page(k: int) -> void:
	page = k
	_sel = -1
	_hover = -1
	_view.queue_redraw()


## 選んでいる品物の値段（選んでいなければ 0）
func sel_price() -> int:
	if _sel < 0:
		return 0
	return BallStitches.price(_ball_goods[_sel]) if page == 2 else Goods.price(Goods.SHELF[_sel].item.kind)


## 選んでいる品物を、いま買えるか
func sel_ready() -> bool:
	if _sel < 0 or sel_price() > craft.wallet(_who()):
		return false
	if page == 2:
		return not _ball_goods[_sel] in craft.ball_owned.get(_who(), [])
	var k := String(Goods.SHELF[_sel].item.kind)
	return craft.gloves_index(_who(), k) < 0 if Gloves.is_gloves(k) else craft.free_slot(_who()) >= 0


## 「連れ」の札: この画面を閉じて、山師が育てているミニオンの画面（main.gd の minion_ui）を開く
func open_pets() -> void:
	var mui = main.get("minion_ui") if main else null
	if mui == null:
		return
	close()
	mui.open("pet")
	if shop:
		shop.shop_open = true
		shop.greet()


## 選んでいる品物を買う
func buy() -> bool:
	if _sel < 0:
		_shake = 1.0
		return false
	var ok: bool
	if page == 2:
		ok = craft.send({"kind": "ball_stitch_buy", "who": _who(), "stitch": _ball_goods[_sel]})
	else:
		ok = craft.send({"kind": "buy", "who": _who(), "item": (Goods.SHELF[_sel].item as Dictionary).duplicate()})
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
		for k in [1, 2]:
			if _tab_rects.size() > k and (_tab_rects[k] as Rect2).has_point(e.position):
				_hover_btn = "tab%d" % k
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _tab_rects.size() > 1 and (_tab_rects[1] as Rect2).has_point(e.position):
			open_pets()
		elif _tab_rects.size() > 2 and (_tab_rects[2] as Rect2).has_point(e.position):
			set_page(2)
		elif page == 2 and (_tab_rects[0] as Rect2).has_point(e.position):
			set_page(0)
		elif _close_rect.has_point(e.position):
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

	## 雪玉ころがしの手袋を、その段でもう持っているか
	func _owned(kind: String) -> bool:
		return Gloves.is_gloves(kind) and ui.craft.gloves_index(ui._who(), kind) >= 0

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
		# 左の端: 段の札（道具＝この画面、連れ＝ミニオンの画面へ）
		var ts := 84.0 * u
		var tabs: Array = []
		for i in 3:
			var tr := Rect2(r.position + Vector2(24.0 * u, 50.0 * u + i * (ts + 16.0 * u)), Vector2(ts, ts))
			tabs.append(tr)
			var on: bool = i == ui.page
			Icons.screen()
			Icons.patch(self, Icons.rr(tr.position.x, tr.position.y, ts, ts, 12.0 * u), Icons.PAPER if on else Icons.PAPER.darkened(0.12),
					1.0 if on or ui._hover_btn == "tab%d" % i else 0.75, true, Icons.PAPER_EDGE)
			if i == 2:   # 雪玉の柄: 菊かがりの玉
				BallStitches.draw_ball(self, "kiku", _grade(), tr.grow(-ts * 0.1), 1.0 if on else 0.6)
			else:
				Icons.icon(self, "mountain" if i == 0 else "pal_pet", tr.get_center(), ts * 0.8, 1.0 if on else 0.6)
			if on:
				Icons.screen()
				Icons.dashes(self, Icons.rr(tr.position.x - 5 * u, tr.position.y - 5 * u, ts + 10 * u, ts + 10 * u, 15.0 * u), Icons.RED, 3.0 * u, 8.0 * u, 5.0 * u, 1.0, true)
		ui._tab_rects = tabs
		var left := 120.0 * u
		var area_w := w * 0.7
		if ui.page == 2:
			_draw_ball_shelf(u, r, left, area_w, coins)
		else:
			_draw_tools(u, r, left, area_w, coins, full)
		_draw_side(u, r, area_w, w, coins)

	## はめている手袋の段（柄の絵の糸の色。はめていなければ毛糸）
	func _grade() -> String:
		var g: String = ui.craft.glove_grade(ui._who())
		return g if g != "" else "gloves"

	## 雪玉の柄の棚: 縫い目を縫った玉の絵のカード（安い順）。買った柄は針の印
	func _draw_ball_shelf(u: float, r: Rect2, left: float, area_w: float, coins: int) -> void:
		var names: Array = ui._ball_goods
		var per := 4
		var gap := 16.0 * u
		var cw := (area_w - left - 20.0 * u - gap * (per - 1)) / per
		var rows := ceili(float(names.size()) / per)
		var ch := (r.size.y - 70.0 * u) / rows - gap
		var owned_list: Array = ui.craft.ball_owned.get(ui._who(), [])
		var rects: Array = []
		for i in names.size():
			var nm: String = names[i]
			var cost := BallStitches.price(nm)
			var owned := nm in owned_list
			var can := cost <= coins and not owned
			var card := Rect2(r.position.x + left + (i % per) * (cw + gap), r.position.y + 44.0 * u + (i / per) * (ch + gap), cw, ch)
			var sel: bool = ui._sel == i
			if sel or ui._hover == i:
				card.position.y -= (6.0 if sel else 3.0) * u
			rects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 12.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			var pop := 1.0 + 0.15 * sin(ui._pop * PI) if sel else 1.0
			var bs := minf(cw * 0.62, ch * 0.66) * pop
			BallStitches.draw_ball(self, nm, _grade(), Rect2(card.position + Vector2(cw / 2.0 - bs / 2.0, ch * 0.38 - bs / 2.0), Vector2(bs, bs)), 1.0 if can or owned else 0.55)
			Icons.screen()
			if owned:
				Icons.icon(self, "needle", card.position + Vector2(cw / 2.0, ch * 0.86), 26.0 * u, 1.0)
			else:
				CraftIcons.price(self, card.position + Vector2(cw / 2.0, ch * 0.86), cost, 9.0 * u, 1.0 if can else 0.55)
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		ui._rects = rects

	## 道具の棚
	func _draw_tools(u: float, r: Rect2, left: float, area_w: float, coins: int, full: bool) -> void:
		var h := r.size.y
		var n: int = Goods.SHELF.size()
		var per := mini(maxi(n, 2), 4)
		var gap := 22.0 * u
		var cw := (area_w - left - 20.0 * u - gap * (per - 1)) / per
		var ch := minf(cw * 1.3, (h - 80.0 * u) / ceilf(float(n) / per) - gap)
		var rects: Array = []
		for i in n:
			var e: Dictionary = Goods.SHELF[i]
			var on := Goods.sold(e.item.kind)
			var cost: int = Goods.price(e.item.kind)
			var owned := _owned(String(e.item.kind))
			var can := on and cost <= coins and (not full or Gloves.is_gloves(String(e.item.kind))) and not owned
			var card := Rect2(r.position.x + left + (i % per) * (cw + gap), r.position.y + 50.0 * u + (i / per) * (ch + gap), cw, ch)
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
			if owned:   # 持っている手袋: 値段の代わりに針の印
				Icons.icon(self, "needle", card.position + Vector2(cw / 2.0, ch * 0.85), 34.0 * u, 1.0)
			elif on:
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

	## 右: 財布・値段・買うボタン・閉じる
	func _draw_side(u: float, r: Rect2, area_w: float, w: float, coins: int) -> void:
		# 右の上: 財布（持っているボタン）と、選んだ品物の値段
		var rx := r.position.x + area_w + 14.0 * u
		var rw := w - area_w - 44.0 * u
		var top := r.position.y + 50.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(rx, top, rw, 250.0 * u, 14.0 * u), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
		if ui._sel >= 0:
			var need: int = ui.sel_price()
			CraftIcons.price(self, Vector2(rx + rw / 2.0, top + 50.0 * u), need, 13.0 * u, 1.0, Icons.RED if need > coins else CraftIcons.COIN)
			Icons.screen()
			Icons.arrow(self, Vector2(rx + rw / 2.0, top + 150.0 * u), Vector2(rx + rw / 2.0, top + 105.0 * u), Icons.THREAD, 0.8, 2.6 * u)
		CraftIcons.price(self, Vector2(rx + rw / 2.0, top + 200.0 * u), coins, 13.0 * u * (1.0 + 0.2 * sin(ui._pop * PI)), 1.0)
		# 右の下: 買うボタン（ボタン → 矢印 → 手袋）
		var shake: float = sin(ui._shake * 40.0) * 10.0 * u * ui._shake
		var bs := 150.0 * u
		var bc := Vector2(rx + rw / 2.0 + shake, r.position.y + 440.0 * u)
		ui._buy_rect = Rect2(bc - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
		var ready: bool = ui.sel_ready()
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
