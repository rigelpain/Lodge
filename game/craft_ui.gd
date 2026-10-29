extends CanvasLayer
## 工房の画面: 持ち物の列と、売り子の売り台。文字は使わない（絵は craft_icons.gd と hud_icons.gd）。
##   持ち物の列（画面の下のまんなか）: 左端が素手（手袋）、続けて持っている物。手に持っている物は少し持ち上がり、赤い糸で囲む。
##     右端に財布（木のボタンを数だけ積む）。ホイールで手に持つ物を替える（player.gd）。持ち物がなく売り台も閉じていれば出さない
##   売り台（おじさんに F）: 上の段に型紙 4 枚、下の段に布 6 色。どれも絵と、値段のボタンの数。
##     品物を押して選び、右の買うボタン（ボタン → 手袋）で買う。足りない品物は薄く、買えないときは買うボタンが震える。
##     閉じるのは右上の × の縫い目か、F か Esc
## 出来事は craft.gd へ送る（いまはすぐ配られる。通信ではホストが確かめる）。

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Craft := preload("res://craft.gd")
const Fabrics := preload("res://fabrics.gd")

var main: Node3D
var craft: Node
var player: Node3D
var shop_open := false
var _view: View
var _sel := -1               # 売り台で選んでいる品物（_goods の番号）
var _hover := -1
var _hover_btn := ""         # "buy" "close"
var _shake := 0.0
var _pop := {}               # 持ち物の番号 → 跳ねの残り
var _coin_pop := 0.0
var _bar_a := 0.0
var _goods: Array = []       # 売る品物の並び
var _rects: Array = []       # 品物の札の場所（画面の px）
var _buy_rect := Rect2()
var _close_rect := Rect2()


func _ready() -> void:
	layer = 4
	for k in Craft.PATTERNS:
		_goods.append({"kind": "pattern", "sled": k})
	for f in Fabrics.ORDER:
		_goods.append({"kind": "fabric", "fabric": f})
	_view = View.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	if craft:
		craft.happened.connect(_on_craft)


func ui() -> float:
	return clampf(_view.size.y / 1080.0, 0.6, 2.0)


func _who() -> int:
	return int(player.get("id")) if player else -1


func open_shop() -> void:
	if shop_open or player == null:
		return
	shop_open = true
	_sel = -1
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)
	var sk = main.get("shopkeeper")
	if sk:
		sk.shop_open = true
		sk.greet()


func close_shop() -> void:
	if not shop_open:
		return
	shop_open = false
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)
	var sk = main.get("shopkeeper")
	if sk:
		sk.shop_open = false


## 選んでいる品物を買う
func buy() -> bool:
	if _sel < 0:
		_shake = 1.0
		return false
	var ok: bool = craft.send({"kind": "buy", "who": _who(), "item": _goods[_sel].duplicate()})
	if not ok:
		_shake = 1.0
	return ok


func _on_craft(ev: Dictionary) -> void:
	if ev.get("who", -1) != _who():
		return
	match ev.kind:
		"buy", "fold":
			_pop[int(ev.slot)] = 1.0
			_coin_pop = 1.0 if ev.kind == "buy" else _coin_pop
			if ev.kind == "buy":
				var sk = main.get("shopkeeper")
				if sk:
					sk.sold()


func _input(e: InputEvent) -> void:
	if not shop_open:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_F]:
		close_shop()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = _hit(e.position)
		_hover_btn = "buy" if _buy_rect.has_point(e.position) else ("close" if _close_rect.has_point(e.position) else "")
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close_shop()
		elif _buy_rect.has_point(e.position):
			buy()
		else:
			var i := _hit(e.position)
			if i >= 0:
				_sel = i


func _hit(p: Vector2) -> int:
	for i in _rects.size():
		if (_rects[i] as Rect2).has_point(p):
			return i
	return -1


## 確かめ用: 品物を選ぶ（tools/shop_shots.gd）
func select(i: int) -> void:
	_sel = i


func _process(dt: float) -> void:
	if craft == null or player == null:
		return
	var show: bool = shop_open or not craft.bag(_who()).is_empty()
	_bar_a = move_toward(_bar_a, 1.0 if show else 0.0, dt * 4.0)
	_shake = maxf(0.0, _shake - dt * 2.5)
	_coin_pop = maxf(0.0, _coin_pop - dt * 2.5)
	for k in _pop.keys():
		_pop[k] = maxf(0.0, _pop[k] - dt * 2.5)
	_view.queue_redraw()


class View extends Control:
	var ui: Node

	func _draw() -> void:
		var u: float = ui.ui()
		if ui.shop_open:
			_draw_shop(u)
		if ui._bar_a > 0.01:
			_draw_bar(u, ui._bar_a)

	## 持ち物の列
	func _draw_bar(u: float, a: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var bag: Array = craft.bag(who)
		var held: int = craft.hands.get(who, -1)
		var cell := 66.0 * u
		var gap := 8.0 * u
		var n := bag.size() + 1
		var wallet_w := 96.0 * u
		var w := n * cell + (n - 1) * gap + 24.0 * u + wallet_w
		var x0 := size.x / 2.0 - w / 2.0
		var y := size.y - 20.0 * u - cell
		Icons.screen()
		Icons.patch(self, Icons.rr(x0 - 12.0 * u, y - 10.0 * u, w + 24.0 * u, cell + 20.0 * u, 16.0 * u), Icons.PAPER, 0.85 * a, false)
		for i in n:
			var slot := i - 1
			var r := Rect2(x0 + i * (cell + gap), y, cell, cell)
			var on := slot == held
			var pop: float = ui._pop.get(slot, 0.0)
			if on:
				r.position.y -= 8.0 * u
			Icons.screen()
			Icons.patch(self, Icons.rr(r.position.x, r.position.y, cell, cell, 10.0 * u), Icons.CAP, a, true, Icons.PAPER_EDGE)
			var c := r.get_center()
			var sz := cell * 0.82 * (1.0 + 0.3 * sin(pop * PI))
			if slot < 0:
				Icons.icon(self, "hand", c, sz * 0.8, a, Icons.RED)
			else:
				CraftIcons.item(self, bag[slot], c, sz, a)
			if on:
				Icons.screen()
				Icons.dashes(self, Icons.rr(r.position.x - 3.0 * u, r.position.y - 3.0 * u, cell + 6.0 * u, cell + 6.0 * u, 12.0 * u), Icons.RED, 2.4 * u, 6.0 * u, 3.5 * u, a, true)
				Icons.chevron(self, Vector2(c.x, r.position.y - 12.0 * u), 14.0 * u, Icons.RED, a, PI / 2, 2.6 * u)
		# 財布: ボタンを数だけ、4 個ずつの山に
		var coins: int = craft.wallet(who)
		var wx := x0 + n * (cell + gap) + 16.0 * u
		var cr := 8.0 * u * (1.0 + 0.25 * sin(ui._coin_pop * PI))
		for i in coins:
			var col := i / 4
			var row := i % 4
			var p := Vector2(wx + col * cr * 2.3 + cr, y + cell - cr - row * cr * 0.9 - 4.0 * u)
			Icons._o = p
			Icons._s = 1.0
			CraftIcons.coin(self, Vector2.ZERO, cr, a)

	## 売り台
	func _draw_shop(u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var coins: int = craft.wallet(who)
		var full: bool = craft.bag(who).size() >= Craft.SLOTS
		var w := 1040.0 * u
		var h := 600.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.44 - h / 2.0, w, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), Color(0.36, 0.42, 0.33), 0.98, false)
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		var rects: Array = []
		var area_w := w * 0.74
		for i in ui._goods.size():
			var it: Dictionary = ui._goods[i]
			var pattern: bool = it.kind == "pattern"
			var idx: int = i if pattern else i - Craft.PATTERNS.size()
			var per := Craft.PATTERNS.size() if pattern else Fabrics.ORDER.size()
			var cw := (area_w - 40.0 * u) / per - 14.0 * u
			var ch := (250.0 if pattern else 200.0) * u
			var cx := r.position.x + 30.0 * u + idx * (cw + 14.0 * u)
			var cy := r.position.y + (40.0 if pattern else 320.0) * u
			var card := Rect2(cx, cy, cw, ch)
			var price := Craft.price(it)
			var can := price <= coins and not full
			var sel: bool = ui._sel == i
			var hov: bool = ui._hover == i
			if sel or hov:
				card.position.y -= (8.0 if sel else 4.0) * u
			rects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 14.0 * u), Icons.CAP, 1.0 if can else 0.55, true, Icons.PAPER_EDGE)
			var a := 1.0 if can else 0.4
			var isz := minf(cw, ch * 0.7) * 0.92
			CraftIcons.item(self, it, card.position + Vector2(cw / 2.0, ch * 0.4), isz, a)
			CraftIcons.price(self, card.position + Vector2(cw / 2.0, ch * 0.84), price, 11.0 * u, a)
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 16.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		ui._rects = rects
		# 右: 財布と買うボタン
		var rx := r.position.x + area_w + 20.0 * u
		var rw := w - area_w - 50.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(rx, r.position.y + 40.0 * u, rw, 250.0 * u, 14.0 * u), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
		var cr := 13.0 * u * (1.0 + 0.2 * sin(ui._coin_pop * PI))
		for i in coins:
			var col := i % 5
			var row := i / 5
			Icons._o = Vector2(rx + rw / 2.0 + (col - 2) * cr * 2.3, r.position.y + 230.0 * u - row * cr * 2.2)
			Icons._s = 1.0
			CraftIcons.coin(self, Vector2.ZERO, cr, 1.0)
		if ui._sel >= 0:   # 選んだ品物の値段のぶんを、上に赤い糸で示す
			var need := Craft.price(ui._goods[ui._sel])
			var short := need > coins
			CraftIcons.price(self, Vector2(rx + rw / 2.0, r.position.y + 80.0 * u), need, 11.0 * u, 1.0, Icons.RED if short else CraftIcons.COIN)
		var shake: float = sin(ui._shake * 40.0) * 10.0 * u * ui._shake
		var bs := 150.0 * u
		var bc := Vector2(rx + rw / 2.0 + shake, r.position.y + 420.0 * u)
		ui._buy_rect = Rect2(bc - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
		var ready: bool = ui._sel >= 0 and Craft.price(ui._goods[ui._sel]) <= coins and not full
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
