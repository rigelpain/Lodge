extends CanvasLayer
## 山男の売り場（山男に F）。文字は使わない。おじいさんの売り台（craft_ui.gd）・雪だるまの店（food_ui.gd）と同じ作り:
## フェルトの板（山男の上着の藍）、クリーム色のカード、赤い丸の買うボタン、右上の × の縫い目。
##   左: 棚の品物のカード。左の端の段の札で棚を替える。上から（2026-11-10 代表「上から、消耗品、ミニオン、双眼鏡、手袋、雪玉ステッチにしてほしいタブは」）:
##       消耗品（焚き火セット・ペグ。mountain_goods.gd の SHELF）・ミニオン（山師が育てている連れ。pals.gd の pet）・双眼鏡・手袋（雪玉ころがしの手袋）・
##       雪玉の柄（大玉の縫い目の柄。ball_stitches.gd）。札の印は品物の絵。どの棚も同じ形（1 段 4 枚の札、右に財布と買うボタン）
##       （代表「山師のミニオン購入だけUIの形変わるの嫌過ぎる」）。ミニオンの札の中では、座ったミニオンがくるくる回る（絵と買う・連れる出来事は
##       main.gd の minion_ui＝pals_ui.gd の連れの段のものを使う。その画面そのものは開かない）。持っているミニオンの札を押すと連れ替え
##       （連れているのを押すと外す）、持っていないミニオンは選んで買うボタンで買うと、すぐ連れる。カードの下に値段のボタン。
##       札の見え方はどの店も同じ（craft_icons.gd の foot・over。2026-11-10 代表「一般的なゲームのやりかたにしてほしい」）: 品物の絵の下に値段のボタン、
##       ボタンが足りなければ札がグレーで選べない、持っている手袋と双眼鏡は値段の代わりに緑のチェック、はめている・下げているものは赤い糸の縁、
##       まだ売っていない品（ロック。shop_locks.gd）は札がくすんで南京錠（選べない）、
##       持ち物がいっぱいなら、場所の要る札は買えない見え方（くすみと埋まった枠の印）で、板の下に手持ちとかばんの枠を全部並べる
##       （2026-11-10 代表「インベントリパンパンのときは…インベントリスロットを表示したほうが良い」）。手袋と双眼鏡は装備なので、いっぱいでも買える
##   右の上: 財布のボタン。品物を選ぶと、その値段を上に赤い糸（足りないとき）で
##   右の下: 買うボタン（ボタン → 矢印 → 手袋）。買えないときは震える
##   雪玉の柄の棚は、縫い目を縫った玉の絵のカードが安い順に並び、糸はいまはめている手袋の色（はめていなければ毛糸）。持ち物の場所は使わず、
##       人ごとに一度買えばよい。買った柄は値段の代わりに緑のチェック、使っている柄は赤い糸の縁。選ぶのは持ち物の画面（craft_ui.gd）
## 閉じるのは ×、F、Esc。買うのは craft.gd の buy（ほかの人の画面にも配られ、山男がその人を向いてうなずく）

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Goods := preload("res://mountain_goods.gd")
const Gloves := preload("res://gloves.gd")
const Binoculars := preload("res://binoculars.gd")
const BallStitches := preload("res://ball_stitches.gd")
const ShopLocks := preload("res://shop_locks.gd")
const Pals := preload("res://pals.gd")
const Doll := preload("res://doll.gd")

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
var _tab_rects: Array = []   # 左の段の札（棚の番号ごと。0 消耗品、1 ミニオン、2 雪玉の柄、3 双眼鏡、4 手袋）
var page := 0                # 開いている棚（0 消耗品、1 ミニオン、2 雪玉の柄、3 双眼鏡、4 手袋）
const TAB_ORDER := [0, 1, 3, 4, 2]   # 段の札の並び（上から 消耗品・ミニオン・双眼鏡・手袋・雪玉の柄）。中身は棚の番号
var _frame := -1             # ミニオンの絵を回すコマ
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
	_pets_off()
	_view.queue_redraw()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)
	if shop:
		shop.shop_open = false


## 確かめ用: 棚の i 番目を選ぶ（売っていない品目は選べない）
func select(i: int) -> void:
	if not CraftIcons.pickable(state(i)):
		return   # お金が足りない・ロック・いっぱいの札は選べない（押しても何も起きない）
	_sel = i
	if page == 1 and state(i) in ["owned", "worn"]:   # 持っているミニオン: 押すと連れ替え（連れているのを押すと外す）
		if _pets().choose(i):
			_pop = 1.0
	_view.queue_redraw()


## 棚の i 番目の札のようす（craft_icons.gd の card_state）
func state(i: int) -> String:
	var who := _who()
	var coins: int = craft.wallet(who)
	if page == 1:
		return _pets().card_state(i) if _pets() else ""
	if page == 2:
		if i < 0 or i >= _ball_goods.size():
			return ""
		var nm: String = _ball_goods[i]
		return CraftIcons.card_state(ShopLocks.locked("ball:" + nm), nm in craft.ball_owned.get(who, []), BallStitches.price(nm) <= coins, true, craft.ball_stitch_of(who) == nm)
	if i < 0 or i >= Goods.SHELF.size():
		return ""
	var it: Dictionary = Goods.SHELF[i].item
	var k := String(it.kind)
	var glove := Gloves.is_gloves(k)
	var scope := Binoculars.is_item(it)
	var room: bool = glove or scope or craft.free_slot(who) >= 0 or k == "peg" and craft._peg_stack(who) >= 0   # 手袋と双眼鏡は装備、ペグは持っている束に足せる
	var owned: bool = glove and craft.gloves_index(who, k) >= 0 or scope and craft.scope_index(who, k) >= 0   # 一度買えばずっと持っている
	var worn: bool = glove and craft.glove_grade(who) == k or scope and String(craft.scope(who).get("kind", "")) == k   # はめている手袋・首から下げている双眼鏡
	return CraftIcons.card_state(ShopLocks.locked(ShopLocks.item_key(it)), owned, Goods.price(k) <= coins, room, worn)


## 持ち物がいっぱいで、道具の棚のうち場所の要る品が買えない（双眼鏡・手袋・雪玉の柄の棚は場所を使わない）
func bag_full() -> bool:
	return page == 0 and craft.free_slot(_who()) < 0


## いまの棚に並ぶ品（mountain_goods.gd の SHELF の番号）: 道具は焚き火セット・ペグなど、双眼鏡の棚は双眼鏡、手袋の棚は手袋。
## 札の番号（state・select・_rects）は棚が替わっても SHELF の番号のまま
func shelf_ids(pg := -1) -> Array:
	var p := page if pg < 0 else pg
	var out: Array = []
	for i in Goods.SHELF.size():
		var it: Dictionary = Goods.SHELF[i].item
		var on: bool
		match p:
			3: on = Binoculars.is_item(it)
			4: on = Gloves.is_gloves(String(it.kind))
			_: on = not Binoculars.is_item(it) and not Gloves.is_gloves(String(it.kind))
		if on:
			out.append(i)
	return out


## 雪玉の柄の札の絵の糸の段（はめている手袋。はめていなければ毛糸）。連れの画面（pals_ui.gd）の札も同じ絵
func tab_grade() -> String:
	var g: String = craft.glove_grade(_who()) if craft else ""
	return g if g != "" else "gloves"


## 棚を替える（0 消耗品、1 ミニオン、2 雪玉の柄、3 双眼鏡、4 手袋）
func set_page(k: int) -> void:
	if k != 1:
		_pets_off()
	page = k
	_sel = -1
	_hover = -1
	if k == 1 and _pets() and _pets()._shots.is_empty():
		_pets()._make_shots()   # 札の中で回る、座ったミニオンの絵
	_view.queue_redraw()


## ミニオンの絵と買う・連れる出来事（main.gd の minion_ui＝pals_ui.gd の連れの段。その画面は開かない）
func _pets() -> Node:
	return main.get("minion_ui") if main else null


func _pets_off() -> void:
	if _pets():
		_pets()._free_shots()


## 選んでいる品物の値段（選んでいなければ 0）
func sel_price() -> int:
	if _sel < 0:
		return 0
	if page == 1:
		return Pals.price(_pets().keys()[_sel])
	return BallStitches.price(_ball_goods[_sel]) if page == 2 else Goods.price(Goods.SHELF[_sel].item.kind)


## 選んでいる品物を、いま買えるか
func sel_ready() -> bool:
	return _sel >= 0 and state(_sel) == "can"


## 選んでいる品物を買う
func buy() -> bool:
	if _sel < 0:
		_shake = 1.0
		return false
	var ok: bool
	if page == 1:
		ok = _pets().choose(_sel)   # 買うと、すぐ連れる（保存も pals_ui.gd が）
	elif page == 2:
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
	if is_open and page == 1 and _pets():   # ミニオンの絵を 12 コマで回す。選んでいる札は速く（pals_ui.gd と同じ）
		var f := Doll.frame_index()
		if f != _frame:
			_frame = f
			var shots: Array = _pets()._shots
			for i in shots.size():
				(shots[i][1] as Node3D).rotation.y += 0.22 if i == _sel else 0.07
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
		for k in _tab_rects.size():
			if k != page and (_tab_rects[k] as Rect2).has_point(e.position):
				_hover_btn = "tab%d" % k
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		var tab := -1
		for k in _tab_rects.size():
			if (_tab_rects[k] as Rect2).has_point(e.position):
				tab = k
		if tab >= 0:
			if tab != page:
				set_page(tab)
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
		# 左の端: 段の札（上から 消耗品・ミニオン・双眼鏡・手袋・雪玉の柄）。印は品物の絵
		var ts := 84.0 * u
		var tabs: Array = []
		tabs.resize(TAB_ORDER.size())
		for slot in TAB_ORDER.size():
			var i: int = TAB_ORDER[slot]
			var tr := Rect2(r.position + Vector2(24.0 * u, 34.0 * u + slot * (ts + 12.0 * u)), Vector2(ts, ts))
			tabs[i] = tr
			var on: bool = i == ui.page
			Icons.screen()
			Icons.patch(self, Icons.rr(tr.position.x, tr.position.y, ts, ts, 12.0 * u), Icons.PAPER if on else Icons.PAPER.darkened(0.12),
					1.0 if on or ui._hover_btn == "tab%d" % i else 0.75, true, Icons.PAPER_EDGE)
			if i == 2:   # 雪玉の柄: 菊かがりの玉
				BallStitches.draw_ball(self, "kiku", _grade(), tr.grow(-ts * 0.1), 1.0 if on else 0.6)
			elif i == 3:   # 双眼鏡
				CraftIcons.item(self, {"kind": "binoculars"}, tr.get_center(), ts * 0.8, 1.0 if on else 0.6)
			elif i == 4:   # 手袋
				CraftIcons.item(self, {"kind": "gloves_felt"}, tr.get_center(), ts * 0.8, 1.0 if on else 0.6)
			elif i == 1:   # ミニオン: 足もとの子狐
				Icons.icon(self, "pal_pet", tr.get_center(), ts * 0.8, 1.0 if on else 0.6)
			else:   # 消耗品: 焚き火セット
				CraftIcons.item(self, {"kind": "campfire"}, tr.get_center(), ts * 0.78, 1.0 if on else 0.6)
			if on:
				Icons.screen()
				Icons.dashes(self, Icons.rr(tr.position.x - 5 * u, tr.position.y - 5 * u, ts + 10 * u, ts + 10 * u, 15.0 * u), Icons.RED, 3.0 * u, 8.0 * u, 5.0 * u, 1.0, true)
		ui._tab_rects = tabs
		var left := 120.0 * u
		var area_w := w * 0.7
		if ui.page == 1:
			_draw_pets(u, r, left, area_w)
		elif ui.page == 2:
			_draw_ball_shelf(u, r, left, area_w, coins)
		else:
			_draw_tools(u, r, left, area_w, coins, full)
		_draw_side(u, r, area_w, w, coins)

	## はめている手袋の段（柄の絵の糸の色。はめていなければ毛糸）
	func _grade() -> String:
		var g: String = ui.craft.glove_grade(ui._who())
		return g if g != "" else "gloves"

	## ミニオンの棚: ほかの棚と同じ形の札（1 段 4 枚）に、座ったミニオンがくるくる回る絵。下に値段かチェック、連れていれば赤い糸の縁、ロックなら南京錠
	func _draw_pets(u: float, r: Rect2, left: float, area_w: float) -> void:
		var pets: Node = ui._pets()
		var keys: Array = pets.keys() if pets else []
		var per := 4
		var gap := 22.0 * u
		var cw := (area_w - left - 20.0 * u - gap * (per - 1)) / per
		var rows := ceili(float(keys.size()) / per)
		var ch := minf(cw * 1.3, (r.size.y - 80.0 * u) / maxf(rows, 1) - gap)
		var rects: Array = []
		for i in keys.size():
			var st: String = ui.state(i)
			var card := Rect2(r.position.x + left + (i % per) * (cw + gap), r.position.y + 50.0 * u + (i / per) * (ch + gap), cw, ch)
			var sel: bool = ui._sel == i
			if sel or ui._hover == i and CraftIcons.pickable(st):
				card.position.y -= (8.0 if sel else 4.0) * u
			rects.append(card)
			var pts := Icons.rr(card.position.x, card.position.y, cw, ch, 14.0 * u)
			Icons.screen()
			Icons.patch(self, pts, Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			if i < pets._shots.size():
				var pop := 1.0 + 0.15 * sin(ui._pop * PI) if sel else 1.0
				var tex: Texture2D = (pets._shots[i][0] as SubViewport).get_texture()
				var th := ch * 0.68 * pop
				var tw := th * float(tex.get_width()) / maxf(1.0, tex.get_height())
				draw_texture_rect(tex, Rect2(card.position + Vector2((cw - tw) / 2.0, ch * 0.38 - th / 2.0), Vector2(tw, th)), false)
			CraftIcons.foot(self, st, card.position + Vector2(cw / 2.0, ch * 0.83), Pals.price(keys[i]), 11.0 * u, u)
			CraftIcons.over(self, st, card, pts, u)
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 16.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		ui._rects = rects

	## 雪玉の柄の棚: 縫い目を縫った玉の絵のカード（安い順）。買った柄はチェック、使っている柄は赤い糸の縁
	func _draw_ball_shelf(u: float, r: Rect2, left: float, area_w: float, coins: int) -> void:
		var names: Array = ui._ball_goods
		var per := 4
		var gap := 16.0 * u
		var cw := (area_w - left - 20.0 * u - gap * (per - 1)) / per
		var rows := ceili(float(names.size()) / per)
		var ch := (r.size.y - 70.0 * u) / rows - gap
		var rects: Array = []
		for i in names.size():
			var nm: String = names[i]
			var cost := BallStitches.price(nm)
			var st: String = ui.state(i)
			var card := Rect2(r.position.x + left + (i % per) * (cw + gap), r.position.y + 44.0 * u + (i / per) * (ch + gap), cw, ch)
			var sel: bool = ui._sel == i
			if sel or ui._hover == i and CraftIcons.pickable(st):
				card.position.y -= (6.0 if sel else 3.0) * u
			rects.append(card)
			# 札と柄の玉（いつも見せる）。下に値段かチェック、身につけていれば赤い糸の縁、ロックなら南京錠（craft_icons.gd の foot・over）
			var pts := Icons.rr(card.position.x, card.position.y, cw, ch, 12.0 * u)
			Icons.screen()
			Icons.patch(self, pts, Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			var pop := 1.0 + 0.15 * sin(ui._pop * PI) if sel else 1.0
			var bs := minf(cw * 0.62, ch * 0.62) * pop
			BallStitches.draw_ball(self, nm, _grade(), Rect2(card.position + Vector2(cw / 2.0 - bs / 2.0, ch * 0.36 - bs / 2.0), Vector2(bs, bs)))
			CraftIcons.foot(self, st, card.position + Vector2(cw / 2.0, ch * 0.82), cost, 8.0 * u, u)
			CraftIcons.over(self, st, card, pts, u)
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		ui._rects = rects

	## 道具の棚。持ち物がいっぱいなら、場所の要る札は札ごとに買えない見え方（くすみと埋まった枠の印）にし、板の下に持ち物の枠を全部並べる。
	## 場所の要らない品（手袋・双眼鏡・束に足せるペグ）はいつもどおり買える
	func _draw_tools(u: float, r: Rect2, left: float, area_w: float, _coins: int, full: bool) -> void:
		var h := r.size.y
		var n: int = Goods.SHELF.size()
		var ids: Array = ui.shelf_ids()   # いまの棚の品（SHELF の番号）
		var per := 4   # 札の大きさは、どの棚も同じ（1 段 4 枚）
		var gap := 22.0 * u
		var cw := (area_w - left - 20.0 * u - gap * (per - 1)) / per
		var ch := minf(cw * 1.3, (h - 80.0 * u) / ceilf(float(ids.size()) / per) - gap)
		var rects: Array = []
		rects.resize(n)
		rects.fill(Rect2())   # ほかの棚の品は押せない
		var states: Array = []
		for i in n:
			states.append(ui.state(i))
		for j in ids.size():
			var i: int = ids[j]
			var e: Dictionary = Goods.SHELF[i]
			var st: String = states[i]
			var cost: int = Goods.price(e.item.kind)
			var card := Rect2(r.position.x + left + (j % per) * (cw + gap), r.position.y + 50.0 * u + (j / per) * (ch + gap), cw, ch)
			var sel: bool = ui._sel == i
			if sel or ui._hover == i and CraftIcons.pickable(st):
				card.position.y -= (8.0 if sel else 4.0) * u
			rects[i] = card
			# 札と品物の絵（いつも見せる）。下に値段かチェック、身につけていれば赤い糸の縁、ロックなら南京錠（craft_icons.gd の foot・over）
			var pts := Icons.rr(card.position.x, card.position.y, cw, ch, 14.0 * u)
			Icons.screen()
			Icons.patch(self, pts, Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			var pop := 1.0 + 0.15 * sin(ui._pop * PI) if sel else 1.0
			CraftIcons.item(self, e.item, card.position + Vector2(cw / 2.0, ch * 0.38), minf(cw, ch * 0.66) * 0.8 * pop)
			CraftIcons.foot(self, st, card.position + Vector2(cw / 2.0, ch * 0.83), cost, 11.0 * u, u)
			CraftIcons.over(self, st, card, pts, u)
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 16.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		if full and ui.bag_full():   # 持ち物がいっぱい: 板の下に、手持ちとかばんの枠を全部並べて、埋まっているのを見せる（場所の要る札は札ごとに買えない見え方）
			CraftIcons.slot_strip(self, Vector2(r.get_center().x, r.end.y + 14.0 * u), ui.craft.bag(ui._who()), u)
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
