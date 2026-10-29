extends CanvasLayer
## 工房の画面: 持ち物の列と、売り子の売り台。文字は使わない（絵は craft_icons.gd と hud_icons.gd）。
##   持ち物の列（画面の下のまんなか）: 左端が素手（手袋）、続けて持っている物。手に持っている物は少し持ち上がり、赤い糸で囲む。
##     右端に財布（木のボタンを数だけ積む）。ホイールで手に持つ物を替える（player.gd）。持ち物がなく売り台も閉じていれば出さない
##   売り台（おじさんに F）: 上の段に型紙 4 枚、下の段に布 6 色。どれも絵と、値段のボタンの数。
##     品物を押して選び、右の買うボタン（ボタン → 手袋）で買う。足りない品物は薄く、買えないときは買うボタンが震える。
##     閉じるのは右上の × の縫い目か、F か Esc
##   ミシンの画面（ミシンの前で F か T）: 上に型紙の枠と布の枠、その右にできるソリ（広げた姿がくるくる回る）と縫うボタン。
##     下に自分の持ち物が並び、押すと型紙は型紙の枠、布は布の枠に入る（枠を押すと外す）。開いたときは、手に持っている物か
##     最初の型紙・布が入っている。足りない枠は破線の空き枠で、おじさん（売り台の絵）を指す矢印が出る。
##     縫うボタンで、型紙と布をいっしょに使って 7 つの場面が始まる（片方だけ使われることはない）
##   装備の画面（I）: 左に、いま装備している米袋（広げた姿がくるくる回る）を帯に下げて見せる。右の上の段に、持っている米袋
##     （標準のクラフト紙と、縫った色違い）が並び、装備しているものに赤い糸の印。押すと装備が入れ替わる（N でそれが出る）。
##     まんなかの段は自分の名札: 左に大きく、右に部品（形・紙の色・縁の糸・吊るす糸・判子）の見本の列。押すと名札が替わり、
##     自分のソリ・米袋の名札も替わる（保存して、次に起動しても同じ）。
##     右の下の段に、持ち物（型紙・布）。装備の種類は craft.gd の GEARS（米袋とランタン。服は段を足す）。閉じるのは ×、I、Esc
##     左の下は持っているランタン（木の手提げ・提灯）。押すと帯の左に提げ替え、提げているのをもう一度押すと外す（R で点ける・消す）
## 出来事は craft.gd へ送る（いまはすぐ配られる。通信ではホストが確かめる）。

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Craft := preload("res://craft.gd")
const Fabrics := preload("res://fabrics.gd")

var main: Node3D
var craft: Node
var player: Node3D
var shop_open := false
var machine_open := false
var gear_open := false
var _gear_rects: Array = []  # 装備の画面の、持っている米袋の札
var _lamp_rects: Array = []  # 装備の画面の、持っているランタンの札
var _lamp_hover := -1
var _opt_rects: Array = []   # 装備の画面の、名札の部品の見本 [Rect2, 部品, 番号]（部品 "_page" はページの札、"_dice" はおまかせ）
var tag_page := 0            # 装備の画面で開いている、名札の部品のページ（sled_tags.gd の PAGES）
var _opt_hover := -1         # 指している見本（_opt_rects の番号）
var _pick := {"pattern": -1, "fabric": -1}   # ミシンの画面で枠に入れた持ち物の番号
var _bag_rects: Array = []   # ミシンの画面の持ち物の札
var _slot_rects := {}        # "pattern" / "fabric" → 枠
var _sew_rect := Rect2()
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
	return Icons.ui_scale(_view.size.y)   # 画面の高さ × 設定の「HUD の大きさ」


func _who() -> int:
	return int(player.get("id")) if player else -1


func _open_panel() -> void:
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)


func _close_panel() -> void:
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)


func open_shop() -> void:
	if shop_open or machine_open or gear_open or player == null:
		return
	shop_open = true
	_sel = -1
	_open_panel()
	var sk = main.get("shopkeeper")
	if sk:
		sk.shop_open = true
		sk.greet()


func close_shop() -> void:
	if not shop_open:
		return
	shop_open = false
	_close_panel()
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


## ミシンの画面を開く。手に持っている物か、最初の型紙・布を枠に入れておく
func open_machine() -> void:
	if shop_open or machine_open or gear_open or player == null:
		return
	machine_open = true
	_pick = {"pattern": -1, "fabric": -1}
	var bag: Array = craft.bag(_who())
	var held: int = craft.hands.get(_who(), -1)
	for kind in ["pattern", "fabric"]:
		if held >= 0 and held < bag.size() and bag[held].kind == kind:
			_pick[kind] = held
			continue
		for i in bag.size():
			if bag[i].kind == kind:
				_pick[kind] = i
				break
	_open_panel()


func close_machine() -> void:
	if not machine_open:
		return
	machine_open = false
	_close_panel()


## 持ち物の i 番を枠に入れる（同じ物なら外す）
func pick(i: int) -> void:
	var bag: Array = craft.bag(_who())
	if i < 0 or i >= bag.size() or not bag[i].kind in ["pattern", "fabric"]:
		_shake = 1.0
		return
	var kind: String = bag[i].kind
	_pick[kind] = -1 if _pick[kind] == i else i


## 縫う: 枠の型紙と布をいっしょに使って、ミシンを動かす。そろっていなければ縫うボタンが震える
func sew() -> bool:
	var bag: Array = craft.bag(_who())
	var ps: int = _pick.pattern
	var fs: int = _pick.fabric
	if ps < 0 or fs < 0 or ps >= bag.size() or fs >= bag.size():
		_shake = 1.0
		return false
	var ok: bool = craft.send({"kind": "sew", "who": _who(), "pattern": bag[ps].duplicate(), "fabric": bag[fs].duplicate(),
			"pattern_slot": ps, "fabric_slot": fs})
	if ok:
		close_machine()
	else:
		_shake = 1.0
	return ok


## 装備の画面を開く
func open_gear() -> void:
	if shop_open or machine_open or gear_open or player == null:
		return
	gear_open = true
	_open_panel()


func close_gear() -> void:
	if not gear_open:
		return
	gear_open = false
	_close_panel()


## 種類 gear の持っている物の i 番を装備する（確かめ用の入口も兼ねる）。ランタンは -1 で外す
func equip(i: int, gear := "sack") -> bool:
	return craft.send({"kind": "equip", "who": _who(), "gear": gear, "index": i})


## 自分の名札の部品を替える（確かめ用の入口も兼ねる）。保存もする。まだ手に入れていない部品は選べない
func set_tag_part(part: String, i: int, save := true) -> bool:
	if not craft.tag_can_use(_who(), part, i):
		_shake = 0.4
		return false
	var d: Dictionary = craft.tag_designs.get(_who(), {}).duplicate()
	d[part] = i
	return _send_tag(d, save)


## おまかせ: 使える部品から選び直す。地と模様の色は、見分けられるほど離す
func shuffle_tag(save := true) -> bool:
	var Tags := preload("res://sled_tags.gd")
	var d := {}
	for part in Tags.PARTS:
		var ok := []
		for i in Tags.part_count(part):
			if craft.tag_can_use(_who(), part, i):
				ok.append(i)
		d[part] = ok.pick_random()
	var paper: Color = Tags.PAPERS[d.paper]
	var far := []
	for i in Tags.part_count("accent"):
		if craft.tag_can_use(_who(), "accent", i) and absf(Tags.PAPERS[i].get_luminance() - paper.get_luminance()) > 0.15:
			far.append(i)
	if not far.is_empty():
		d["accent"] = far.pick_random()
	return _send_tag(d, save)


func _send_tag(d: Dictionary, save: bool) -> bool:
	var ok: bool = craft.send({"kind": "tag_design", "who": _who(), "design": d})
	if ok and save and player.has_method("save_tag"):
		player.save_tag()
	return ok


func _gear_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_I]:
		close_gear()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = -1
		for i in _gear_rects.size():
			if (_gear_rects[i] as Rect2).has_point(e.position):
				_hover = i
		_lamp_hover = -1
		for i in _lamp_rects.size():
			if (_lamp_rects[i] as Rect2).has_point(e.position):
				_lamp_hover = i
		_hover_btn = "close" if _close_rect.has_point(e.position) else ""
		_opt_hover = -1
		for i in _opt_rects.size():
			if (_opt_rects[i][0] as Rect2).has_point(e.position):
				_opt_hover = i
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close_gear()
			return
		for i in _gear_rects.size():
			if (_gear_rects[i] as Rect2).has_point(e.position):
				equip(i)
				return
		for i in _lamp_rects.size():
			if (_lamp_rects[i] as Rect2).has_point(e.position):
				equip(-1 if i == craft.gear_index(_who(), "lantern") else i, "lantern")   # 提げているのを押すと外す
				return
		for o in _opt_rects:
			if (o[0] as Rect2).has_point(e.position):
				match o[1]:
					"_page":
						tag_page = o[2]
						_opt_hover = -1
					"_dice":
						shuffle_tag()
					_:
						set_tag_part(o[1], o[2])
				return


func _input(e: InputEvent) -> void:
	if gear_open:
		_gear_input(e)
		return
	if machine_open:
		_machine_input(e)
		return
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


func _machine_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_F, KEY_T]:
		close_machine()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = -1
		for i in _bag_rects.size():
			if (_bag_rects[i] as Rect2).has_point(e.position):
				_hover = i
		_hover_btn = "sew" if _sew_rect.has_point(e.position) else ("close" if _close_rect.has_point(e.position) else "")
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close_machine()
		elif _sew_rect.has_point(e.position):
			sew()
		else:
			for kind in _slot_rects:
				if (_slot_rects[kind] as Rect2).has_point(e.position):
					_pick[kind] = -1
					return
			for i in _bag_rects.size():
				if (_bag_rects[i] as Rect2).has_point(e.position):
					pick(i)
					return


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
	var show: bool = shop_open or machine_open or gear_open or not craft.bag(_who()).is_empty()
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
		if ui.machine_open:
			_draw_machine(u)
		if ui.gear_open:
			_draw_gear_screen(u)
		if ui._bar_a > 0.01:   # 操作のための表示なので、風では揺らさない（2026-10-29 代表）
			_draw_bar(u, ui._bar_a)
		_draw_gear(u)

	## 帯の装備の札（2026-10-29 代表「米袋は刺繍小窓の上においてほしい」）: 右下の刺繍の小窓の真上に、左から
	##   装備の画面（I・背負いかばん）、米袋（N。持っている米袋の数だけ点、選んでいるのは赤。出していれば破線の形）、
	##   ランタン（R。点いていれば光の輪。外していれば破線の形）。小窓を消していれば、画面の右下の隅に
	func _draw_gear(u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var list: Array = craft.sacks.get(who, [])
		if list.is_empty() or ui.shop_open or ui.machine_open or ui.gear_open:
			return
		var cw := 70.0 * u
		var ch := 78.0 * u
		var gap := 10.0 * u
		var total := cw * 3.0 + gap * 2.0
		var cx := size.x - 18.0 * u - total / 2.0
		var bottom := size.y - 18.0 * u
		var sc = ui.main.get("self_cam") if ui.main else null
		if sc and is_instance_valid(sc) and not sc.get("hidden") and sc.get("_frame"):
			var fr: Control = sc._frame
			cx = minf(fr.position.x + fr.size.x / 2.0, size.x - 12.0 * u - total / 2.0)
			bottom = fr.position.y - 44.0 * u   # 刺繍枠の上のねじ（小窓の縁から 1080 で 30 px ほど飛び出す。PR #48）の上
		var spec: Dictionary = craft.sack(who)
		var lamp: Dictionary = craft.lantern(who)
		var cards := [["I", "gear"], ["N", "sack"], ["R", "lamp"]]
		for i in cards.size():
			var r := Rect2(cx - total / 2.0 + i * (cw + gap), bottom - ch, cw, ch)
			Icons.screen()
			Icons.patch(self, Icons.rr(r.position.x, r.position.y, cw, ch, 12.0 * u), Icons.PAPER, 0.88, true, Icons.PAPER_EDGE)
			var ic := r.get_center() + Vector2(4.0 * u, 2.0 * u)
			CraftIcons._at(ic, 58.0 * u)
			match cards[i][1]:
				"gear":
					CraftIcons.backpack(self, Vector2.ZERO, 1.0, 1.0)
				"sack":
					CraftIcons.rice_sack(self, Vector2.ZERO, 1.0, CraftIcons.sack_body(spec), CraftIcons.sack_band(spec), 1.0, craft.sack_sled(who) != null)
					Icons.screen()
					for k in list.size():
						var dp := Vector2(ic.x - (list.size() - 1) * 4.5 * u + k * 9.0 * u, r.end.y - 7.0 * u)
						draw_circle(dp, 2.8 * u, Color(Icons.RED if k == int(craft.sack_sel.get(who, 0)) else Icons.PAPER_EDGE, 1.0))
				"lamp":
					CraftIcons.lantern(self, Vector2.ZERO, 1.0, lamp.get("look", "box"), craft.lamp_on(who), 1.0, lamp.is_empty())
			Icons.keycap(self, cards[i][0], r.position + Vector2(13.0 * u, 13.0 * u), 22.0 * u, 1.0)

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
		if not bag.is_empty():   # 持ち替えの案内: Z（と、ホイール・二本指スクロール）
			Icons.keycap(self, "Z", Vector2(x0 - 44.0 * u, y + cell * 0.32), 30.0 * u, a)
			Icons.icon(self, "mouse_wheel", Vector2(x0 - 44.0 * u, y + cell * 0.86), 34.0 * u, a)
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

	## ミシンの画面
	func _draw_machine(u: float) -> void:
		var craft: Node = ui.craft
		var bag: Array = craft.bag(ui._who())
		var w := 1040.0 * u
		var h := 600.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.44 - h / 2.0, w, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), Color(0.20, 0.25, 0.46), 0.98, false)   # ミシンの紺のフェルト
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		# 上の段: 型紙の枠 ＋ 布の枠 → できるソリ、縫うボタン
		var cw := 190.0 * u
		var ch := 230.0 * u
		var top := r.position.y + 40.0 * u
		var shop_ic := Vector2.ZERO
		var slots := {}
		for k in 2:
			var kind: String = ["pattern", "fabric"][k]
			var cr := Rect2(r.position.x + 40.0 * u + k * (cw + 70.0 * u), top, cw, ch)
			slots[kind] = cr
			var i: int = ui._pick[kind]
			Icons.screen()
			if i >= 0 and i < bag.size():
				Icons.patch(self, Icons.rr(cr.position.x, cr.position.y, cw, ch, 14.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
				CraftIcons.item(self, bag[i], cr.get_center(), cw * 0.8, 1.0)
			else:
				# 空き枠: 破線と薄い絵。持ち物に無ければ、おじさん（売り台）を指す矢印
				Icons.dashes(self, Icons.rr(cr.position.x, cr.position.y, cw, ch, 14.0 * u), Icons.CAP, 3.0 * u, 9.0 * u, 6.0 * u, 0.9, true)
				CraftIcons.item(self, {"kind": kind, "sled": "mid", "fabric": "cream"}, cr.get_center(), cw * 0.7, 0.25)
				var have := false
				for it in bag:
					have = have or it.kind == kind
				if not have:
					var ic := Vector2(cr.get_center().x, cr.end.y + 84.0 * u)
					Icons._o = Vector2.ZERO
					Icons._s = 1.0
					Icons.arrow(self, Vector2(cr.get_center().x, cr.end.y + 6.0 * u), ic - Vector2(0, 46.0 * u), Icons.MUSTARD, 1.0, 4.0 * u)
					Icons.patch(self, Icons.circ(ic, 44.0 * u, 24), Icons.PAPER, 1.0, true, Icons.PAPER_EDGE)
					Icons.icon(self, "shopkeeper", ic + Vector2(-12.0 * u, 0), 62.0 * u, 1.0)
					Icons.icon(self, "shop", ic + Vector2(20.0 * u, 8.0 * u), 40.0 * u, 1.0)
					shop_ic = ic
			if k == 0:   # ＋ の縫い目
				var pc := Vector2(cr.end.x + 35.0 * u, cr.get_center().y)
				Icons._o = pc
				Icons._s = u
				Icons.thread(self, PackedVector2Array([Vector2(-14, 0), Vector2(14, 0)]), Icons.CAP, 4.0, 1.0)
				Icons.thread(self, PackedVector2Array([Vector2(0, -14), Vector2(0, 14)]), Icons.CAP, 4.0, 1.0)
		ui._slot_rects = slots
		# できるソリ: 型紙と布がそろうと、広げた姿が布の色でくるくる回る
		var res := Rect2((slots["fabric"] as Rect2).end.x + 70.0 * u, top, 230.0 * u, ch)
		Icons.screen()
		Icons.chevron(self, Vector2(res.position.x - 36.0 * u, res.get_center().y), 26.0 * u, Icons.CAP, 1.0, 0.0, 4.0 * u)
		var ps: int = ui._pick.pattern
		var fs: int = ui._pick.fabric
		var ready := ps >= 0 and fs >= 0 and ps < bag.size() and fs < bag.size()
		if ready:
			Icons.patch(self, Icons.rr(res.position.x, res.position.y, res.size.x, res.size.y, 14.0 * u), Color(0.86, 0.90, 0.97), 1.0, true, Icons.PAPER_EDGE)
			var tw := res.size.x * 0.92
			draw_texture_rect(preload("res://sled_tags.gd").turntable(bag[ps].sled, bag[fs].fabric),
					Rect2(res.get_center() - Vector2(tw, tw) / 2.0, Vector2(tw, tw)), false)
		else:
			Icons.dashes(self, Icons.rr(res.position.x, res.position.y, res.size.x, res.size.y, 14.0 * u), Icons.CAP, 3.0 * u, 9.0 * u, 6.0 * u, 0.5, true)
		# 縫うボタン（針と赤い糸）
		var shake: float = sin(ui._shake * 40.0) * 10.0 * u * ui._shake
		var bs := 150.0 * u
		var bc := Vector2(r.end.x - 40.0 * u - bs / 2.0 + shake, res.get_center().y)
		ui._sew_rect = Rect2(bc - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
		var big := 1.06 if ui._hover_btn == "sew" else 1.0
		Icons.screen()
		Icons.patch(self, Icons.circ(bc, bs * 0.5 * big, 28), Icons.RED if ready else Icons.RED.lerp(Icons.PAPER_EDGE, 0.6), 1.0, true, Icons.CAP)
		Icons.patch(self, Icons.circ(bc, bs * 0.36 * big, 24), Icons.CAP, 1.0, false)
		Icons.icon(self, "needle", bc, bs * 0.62 * big, 1.0)
		# 下の段: 自分の持ち物
		var rects: Array = []
		var bw := 104.0 * u
		var by := r.end.y - 40.0 * u - 120.0 * u
		var x0 := r.position.x + 40.0 * u
		for i in bag.size():
			var it: Dictionary = bag[i]
			var usable: bool = it.kind in ["pattern", "fabric"]
			var picked: bool = ui._pick.get(it.kind, -1) == i
			var card := Rect2(x0 + i * (bw + 14.0 * u), by - (8.0 * u if picked else (4.0 * u if ui._hover == i else 0.0)), bw, 120.0 * u)
			rects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, bw, card.size.y, 12.0 * u), Icons.CAP, 1.0 if usable else 0.55, true, Icons.PAPER_EDGE)
			CraftIcons.item(self, it, card.get_center(), bw * 0.82, 1.0 if usable else 0.35)
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, bw + 8 * u, card.size.y + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		ui._bag_rects = rects
		# 右上: 閉じる
		var xs := 46.0 * u
		var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
		ui._close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
		Icons.screen()
		Icons.patch(self, Icons.circ(xc, xs * 0.5 * (1.08 if ui._hover_btn == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
		Icons._o = xc
		Icons._s = xs / 64.0
		Icons.thread(self, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)

	## 装備の画面
	func _draw_gear_screen(u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var w := 1040.0 * u
		var h := 690.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.44 - h / 2.0, w, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), Color(0.42, 0.30, 0.22), 0.98, false)   # 革の色のフェルト
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		var Tags := preload("res://sled_tags.gd")
		var list: Array = craft.gear_list(who, "sack")
		var on: int = craft.gear_index(who, "sack")
		# 左: 装備している米袋。帯に下げ、広げた姿がくるくる回る
		var lw := 280.0 * u
		var lr := Rect2(r.position.x + 30.0 * u, r.position.y + 40.0 * u, lw, h - 80.0 * u)
		Icons.patch(self, Icons.rr(lr.position.x, lr.position.y, lw, lr.size.y, 16.0 * u), Icons.PAPER, 0.96, true, Icons.PAPER_EDGE)
		Icons.patch(self, Icons.rr(lr.position.x + 14.0 * u, lr.position.y + 24.0 * u, lw - 28.0 * u, 16.0 * u, 6.0 * u), Icons.WOOD.darkened(0.2), 1.0, true, Icons.CAP)   # 帯
		var lamps: Array = craft.gear_list(who, "lantern")
		var lamp_on: int = craft.gear_index(who, "lantern")
		if on >= 0 and on < list.size():   # 帯の右に米袋、左にランタンを下げる（人形と同じ側）
			var spec: Dictionary = list[on]
			CraftIcons._at(Vector2(lr.position.x + lw * 0.7, lr.position.y + 82.0 * u), 64.0 * u * 1.3)
			Icons.thread(self, PackedVector2Array([Vector2(0, -36), Vector2(0, -22)]), Icons.WOOD, 2.0, 1.0)
			CraftIcons.rice_sack(self, Vector2.ZERO, 1.0, CraftIcons.sack_body(spec), CraftIcons.sack_band(spec), 1.0)
			var tw := lw * 0.6
			draw_texture_rect(Tags.turntable("sack", spec.get("fabric", "")), Rect2(Vector2(lr.position.x + lw * 0.62 - tw / 2.0, lr.position.y + 128.0 * u), Vector2(tw, tw)), false)
			Icons.keycap(self, "N", Vector2(lr.position.x + 36.0 * u, lr.position.y + 214.0 * u), 30.0 * u, 1.0)
		if lamp_on >= 0 and lamp_on < lamps.size():
			CraftIcons._at(Vector2(lr.position.x + lw * 0.28, lr.position.y + 84.0 * u), 64.0 * u * 1.3)
			Icons.thread(self, PackedVector2Array([Vector2(0, -36), Vector2(0, -28)]), Icons.WOOD, 2.0, 1.0)
			CraftIcons.lantern(self, Vector2.ZERO, 1.0, lamps[lamp_on].get("look", "box"), craft.lamp_on(who), 1.0)
		# 左の下: 持っているランタン。押すと提げ替え、提げているのをもう一度押すと外す（R で点ける・消す）
		var lrects: Array = []
		var lcw := 104.0 * u
		var lch := 128.0 * u
		var ly := lr.position.y + 330.0 * u
		Icons.screen()
		Icons.thread(self, PackedVector2Array([Vector2(lr.position.x + 18.0 * u, ly - 18.0 * u), Vector2(lr.end.x - 18.0 * u, ly - 18.0 * u)]), Icons.PAPER_EDGE, 1.5 * u, 0.8)
		for i in lamps.size():
			var card := Rect2(lr.position.x + 24.0 * u + (i % 2) * (lcw + 12.0 * u), ly + (i / 2) * (lch + 10.0 * u), lcw, lch)
			var picked := i == lamp_on
			if picked or ui._lamp_hover == i:
				card.position.y -= (8.0 if picked else 4.0) * u
			lrects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, lcw, lch, 12.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			CraftIcons._at(card.get_center(), lcw * 0.95)
			CraftIcons.lantern(self, Vector2.ZERO, 1.0, lamps[i].get("look", "box"), picked and craft.lamp_on(who), 1.0)
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, lcw + 8 * u, lch + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
				Icons.chevron(self, Vector2(card.get_center().x, card.position.y - 14.0 * u), 18.0 * u, Icons.RED, 1.0, PI / 2, 3.0 * u)
		ui._lamp_rects = lrects
		Icons.keycap(self, "R", Vector2(lr.get_center().x, lr.end.y - 30.0 * u), 30.0 * u, 1.0)
		# 右上: 持っている米袋
		var x0 := lr.end.x + 30.0 * u
		var cw := 128.0 * u
		var ch := 150.0 * u
		var rects: Array = []
		Icons.screen()
		Icons.icon(self, "sack", Vector2(x0 + 26.0 * u, r.position.y + 60.0 * u), 44.0 * u, 1.0)   # 段の印: 米袋
		for i in list.size():
			var spec: Dictionary = list[i]
			var col := i % 5
			var row := i / 5
			var card := Rect2(x0 + 56.0 * u + col * (cw + 12.0 * u), r.position.y + 40.0 * u + row * (ch + 12.0 * u), cw, ch)
			var picked := i == on
			if picked or ui._hover == i:
				card.position.y -= (8.0 if picked else 4.0) * u
			rects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 12.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			var tw := cw * 0.92
			draw_texture_rect(Tags.turntable("sack", spec.get("fabric", "")), Rect2(Vector2(card.get_center().x - tw / 2.0, card.position.y + 2.0 * u), Vector2(tw, tw)), false)
			# 名札の柄（小さく）
			Tags.draw_tag(self, Rect2(card.position.x + 12.0 * u, card.end.y - 36.0 * u, cw - 24.0 * u, 28.0 * u), craft.tag_designs.get(who, 0), 1.0, false)   # 持ち主の名札
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
				Icons.chevron(self, Vector2(card.get_center().x, card.position.y - 14.0 * u), 18.0 * u, Icons.RED, 1.0, PI / 2, 3.0 * u)
		ui._gear_rects = rects
		# まんなか: 自分の名札（左に大きく）と、部品の見本（押すと替わる）。部品は 4 ページ（形と素材・模様・縁と糸・飾りと判子）
		var mine: Dictionary = craft.tag_designs.get(who, {})
		var ty := r.position.y + 218.0 * u
		Tags.draw_tag(self, Rect2(x0 + 50.0 * u, ty + 26.0 * u, 210.0 * u, 128.0 * u), mine, 1.0, true)
		var opts: Array = []
		var ox := x0 + 286.0 * u
		var sw := 25.0 * u
		# おまかせ（さいころ）: 名札の下
		var dc := Vector2(x0 + 155.0 * u, ty + 196.0 * u)
		var ds := 40.0 * u * (1.08 if ui._opt_hover >= 0 and ui._opt_hover < ui._opt_rects.size() and ui._opt_rects[ui._opt_hover][1] == "_dice" else 1.0)
		Icons.screen()
		Icons.patch(self, Icons.rr(dc.x - ds / 2.0, dc.y - ds / 2.0, ds, ds, ds * 0.22), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
		for q in [Vector2(-1, -1), Vector2(1, 1), Vector2(0, 0), Vector2(1, -1), Vector2(-1, 1)]:
			draw_circle(dc + q * ds * 0.24, ds * 0.08, Icons.RED)
		opts.append([Rect2(dc - Vector2(ds, ds) / 2.0, Vector2(ds, ds)), "_dice", 0])
		# ページの札
		var page: int = clampi(ui.tag_page, 0, Tags.PAGES.size() - 1)
		var looks := [["shape", int(mine.get("shape", 0))], ["pattern", maxi(int(mine.get("pattern", 0)), 3) if int(mine.get("pattern", 0)) == 0 else int(mine.get("pattern", 0))],
			["stitch", 3 if int(mine.get("stitch", 0)) == 1 else int(mine.get("stitch", 0))], ["motif", 2 if int(mine.get("motif", 0)) == 0 else int(mine.get("motif", 0))]]
		for k in Tags.PAGES.size():
			var tr := Rect2(ox + k * 54.0 * u, ty - (6.0 * u if k == page else 0.0), 48.0 * u, 38.0 * u)
			Icons.screen()
			Icons.patch(self, Icons.rr(tr.position.x, tr.position.y, tr.size.x, tr.size.y, 9.0 * u), Icons.CAP if k == page else Icons.PAPER_EDGE, 1.0 if k == page else 0.75, k == page, Icons.PAPER_EDGE)
			Tags.swatch(self, looks[k][0], looks[k][1], tr.get_center(), 26.0 * u, mine, 1.0 if k == page else 0.6)
			if k == page:
				Icons.screen()
				Icons.dashes(self, Icons.rr(tr.position.x - 2.0 * u, tr.position.y - 2.0 * u, tr.size.x + 4.0 * u, tr.size.y + 4.0 * u, 10.0 * u), Icons.RED, 2.4 * u, 5.0 * u, 3.0 * u, 1.0, true)
			opts.append([tr, "_page", k])
		# 部品の見本。まだ手に入れていない部品は薄く、木のボタンの印（あとで手に入る）
		var per := maxi(1, int((r.end.x - 26.0 * u - ox) / (sw + 5.0 * u)))
		var oy := ty + 50.0 * u
		for part in Tags.PAGES[page]:
			var n := Tags.part_count(part)
			for i in n:
				var sr := Rect2(ox + (i % per) * (sw + 5.0 * u), oy + (i / per) * (sw + 9.0 * u), sw + 2.0 * u, sw + 6.0 * u)
				var c := sr.get_center()
				var can: bool = craft.tag_can_use(who, part, i)
				if ui._opt_hover == opts.size():
					Icons.screen()
					Icons.patch(self, Icons.rr(sr.position.x - 2.0 * u, sr.position.y - 1.0 * u, sr.size.x + 4.0 * u, sr.size.y + 2.0 * u, 6.0 * u), Icons.CAP, 0.7, false)
				Tags.swatch(self, part, i, c, sw, mine, 1.0 if can else 0.35)
				if not can:
					var bc := Vector2(sr.end.x - 3.0 * u, sr.end.y - 4.0 * u)
					Icons.screen()
					draw_circle(bc, 5.5 * u, Icons.WOOD)
					draw_arc(bc, 4.0 * u, 0.0, TAU, 14, Icons.WOOD.darkened(0.3), 1.0 * u, true)
					draw_circle(bc + Vector2(-1.4, 0) * u, 0.9 * u, Color(0.25, 0.16, 0.10))
					draw_circle(bc + Vector2(1.4, 0) * u, 0.9 * u, Color(0.25, 0.16, 0.10))
				if int(mine.get(part, -1)) == i:
					Icons.screen()
					Icons.dashes(self, Icons.rr(sr.position.x - 2.0 * u, sr.position.y - 1.0 * u, sr.size.x + 4.0 * u, sr.size.y + 2.0 * u, 6.0 * u), Icons.RED, 2.4 * u, 5.0 * u, 3.0 * u, 1.0, true)
				opts.append([sr, part, i])
			oy += ceili(float(n) / per) * (sw + 9.0 * u) + 8.0 * u
		ui._opt_rects = opts
		# 右下: 持ち物（見るだけ）
		var bag: Array = craft.bag(who)
		var by := r.end.y - 40.0 * u - 104.0 * u
		Icons.screen()
		Icons.icon(self, "hand", Vector2(x0 + 26.0 * u, by + 52.0 * u), 44.0 * u, 1.0)
		for i in bag.size():
			var card := Rect2(x0 + 56.0 * u + i * 96.0 * u, by, 86.0 * u, 104.0 * u)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, card.size.x, card.size.y, 10.0 * u), Icons.CAP, 0.9, true, Icons.PAPER_EDGE)
			CraftIcons.item(self, bag[i], card.get_center(), card.size.x * 0.82, 1.0)
		if bag.is_empty():
			Icons.screen()
			Icons.dashes(self, Icons.rr(x0 + 56.0 * u, by, 86.0 * u, 104.0 * u, 10.0 * u), Icons.CAP, 2.0 * u, 6.0 * u, 4.0 * u, 0.5, true)
		# 右上: 閉じる
		var xs := 46.0 * u
		var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
		ui._close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
		Icons.screen()
		Icons.patch(self, Icons.circ(xc, xs * 0.5 * (1.08 if ui._hover_btn == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
		Icons._o = xc
		Icons._s = xs / 64.0
		Icons.thread(self, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)
