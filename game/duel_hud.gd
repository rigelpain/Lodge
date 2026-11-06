extends CanvasLayer
## 雪合戦の対決の画面（duel.gd）。文字は使わず、手芸の物で見せる（2026-11-02 代表「残機３と残り時間とフィールド可視化などの専用HUD」）。
## 自分が対決にかかわっているあいだだけ出る（ほかの人の対決は、雪の上の待ち針と毛糸で見える）。
##   掛金の画面（bet）: 緑のフェルトの板。左に自分、右に相手の人形の絵（受けたら足もとに糸の ✓）。まんなかに掛金のボタン、
##     その下に木・真鍮・白蝶貝のボタンの上下の矢印（1・10・100 ずつ）。下の赤い丸（手袋の握手）で受ける。右上の × でやめる。
##     ボタンの丸のまわりの糸が、やめるまでの残り
##   戦い（fight）: 上のまんなかに刺繍枠の時計（60 目の赤い糸が 1 秒に 1 目ずつ抜ける。残り 10 秒で枠が跳ねる）。
##     左に自分の残り（フェルトのハート 3 つ。当てられると綿の雪がべちゃっと付いて、ハートの縫い目だけ残る）、右に相手の残り。
##     枠の下に、円の小さな地図（白いフェルトの丸に赤い毛糸の輪。自分は上向きの矢じり、相手は丸、飛んでいる相手の雪玉は白い点）。
##     縁に近づくと輪が太く赤く光る。近づく相手の雪玉に破線の輪。手の届く所で照準に合うと、まんなかに赤い輪と開いた手袋と F のキー。
##     当てられてのけぞっているあいだ（当たらないあいだ）は、その人の人形の絵が点滅する
##     投げたあと次を投げられるまで（duel.gd の THROW_GAP）は、藍のフェルトの丸に赤い糸の輪。糸が 1 コマに 1 目ずつ抜け、
##     抜けきると、まんなかに綿の雪玉が跳ねて消える（2026-11-05 代表「雪合戦中の投げCTって表示されてますっけ」「なかったらあったほうが嬉しい」）
##   勝ち負けのあと（over）: 枠に金の糸（払うまでの 30 秒）、まんなかに勝った人の色のロゼット。下に握手の手袋（握手で払う）と掛金の山
##     決まった瞬間、画面のまんなかに大きなワッペンで「勝ち」「負け」「引き分け」（時間切れ・相手が抜けたときは小さく添える）。END_BIG_T たつと、
##     枠の下へ小さくなって移り、下に握手の案内（2 キーで低い手のひら → 近づいて握手）。握手で払うと対決が消えるので、どちらも一緒に消える。
##     ここだけは短い字を使う（2026-11-06 代表「①勝敗結果が大きく表示されて欲しい②互いに２キーを押して近づいて握手をして終わることを促す表示が欲しい」）
## 自分が戦っているあいだ（fight）は、ふだんの HUD をよけて一人称に固定する（main.gd の set_duel_focus。2026-11-05 代表「集中して戦いたいので」）

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Doll := preload("res://doll.gd")
const Duel := preload("res://duel.gd")
const Snowball := preload("res://snowball.gd")

const STEPS := [[1, "wood"], [10, "brass"], [100, "pearl"]]
const GOLD := Color(0.86, 0.66, 0.26)
const END_BIG_T := 2.4       # 勝敗を画面のまんなかに大きく出しておく (s)
const END_MOVE_T := 0.35     # 大きなワッペンが枠の下へ移る (s)
const GAP_R := 44.0          # 投げの間の糸の輪の半径（1080p の px。雪玉のストックのすぐ上の左）

var main: Node
var duel: Node
var player: Node
var bet_open := false
var focus := false           # 自分が戦っている（ふだんの HUD をよけている）
var _view: Control
var _pop := {}               # 何 → 跳ねの残り（1→0）。"lost_me" "lost_them" "catch" "start"
var _hover := ""
var _rects := {}             # 押せる所の名前 → Rect2
var _shake := 0.0
var _end_t := 0.0            # 勝ち負けが決まってからの秒
var _gap_was := 0            # 前のコマの、次を投げられるまでの残り（明けた瞬間を見つける）


func _ready() -> void:
	layer = 4
	_view = View.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	if duel:
		duel.happened.connect(_on_duel)
	var hub = main.get("emotes") if main else null
	if hub:
		hub.happened.connect(_on_emote)


func me() -> int:
	return int(player.get("id")) if player and player.get("id") != null else -1


func mine() -> Dictionary:
	return duel.of(me()) if duel else {}


func _color(who: int) -> Color:
	var craft = main.get("craft") if main else null
	return craft.color_of(who) if craft else Icons.RED


func _on_duel(ev: Dictionary) -> void:
	var d: Dictionary = ev.get("duel", {})
	if d.is_empty() or not (int(d.a) == me() or int(d.b) == me()):
		return
	match String(ev.get("cue", "")):
		"start":
			_pop["start"] = 1.0
		"struck":
			_pop["lost"] = 1.0
		"end":
			_pop["end"] = 1.0
			_end_t = 0.0
	_sync_bet()
	_view.queue_redraw()


func _on_emote(ev: Dictionary) -> void:
	if ev.kind == "catch" and int(ev.who) == me():
		_pop["catch"] = 1.0


## 掛金の画面を、対決の段に合わせて開く・閉じる
func _sync_bet() -> void:
	var d := mine()
	var want: bool = not d.is_empty() and d.phase == "bet"
	if want == bet_open or player == null:
		return
	if want and player.menu_open:
		return   # ほかの画面を開いている（閉じたら _process で開く）
	bet_open = want
	_view.mouse_filter = Control.MOUSE_FILTER_STOP if want else Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if want else Input.MOUSE_MODE_CAPTURED
	player.menu_open = want


func _process(dt: float) -> void:
	for k in _pop.keys():
		_pop[k] = maxf(0.0, _pop[k] - dt * 1.6)
	_shake = maxf(0.0, _shake - dt * 2.5)
	_end_t += dt
	var wait: int = duel.throw_wait(me()) if duel else 0
	if _gap_was > 0 and wait <= 0:
		_pop["gap"] = 1.0
	_gap_was = wait
	_sync_bet()
	_sync_focus()
	if not mine().is_empty() or bet_open:
		_view.queue_redraw()


## 戦いが始まったら、ふだんの HUD をよけて一人称に固定する。勝ち負けが決まる・相手が抜ける・通信が切れる（どれも fight の段が終わる）と戻す
func _sync_focus() -> void:
	var on: bool = duel != null and not duel.fighting(me()).is_empty()
	if on != focus:
		focus = on
		main.set_duel_focus(on)


## 掛金を足す・引く（step は 1・10・100、sign は 1 か -1）
func nudge(step: int, sign_: int) -> void:
	var d := mine()
	if d.is_empty():
		return
	var top: int = duel.max_stake(d)
	var n := clampi(int(d.stake) + step * sign_, 0, top)
	if n == int(d.stake):
		_shake = 1.0
		return
	duel.send({"kind": "bet", "who": me(), "n": n})


func accept() -> void:
	duel.send({"kind": "ok", "who": me()})


func cancel() -> void:
	duel.send({"kind": "cancel", "who": me()})


func _hit(p: Vector2) -> String:
	for k in _rects:
		if (_rects[k] as Rect2).has_point(p):
			return k
	return ""


func _input(e: InputEvent) -> void:
	if not bet_open:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = _hit(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		var k := _hit(e.position)
		if k == "ok":
			accept()
		elif k == "close":
			cancel()
		elif k.begins_with("up") or k.begins_with("down"):
			nudge(STEPS[int(k.right(1))][0], 1 if k.begins_with("up") else -1)


class View extends Control:
	var ui: Node

	func _draw() -> void:
		var d: Dictionary = ui.mine()
		if d.is_empty():
			return
		var u := Icons.ui_scale(size.y)
		if d.phase == "bet":
			if ui.bet_open:
				_draw_bet(d, u)
			return
		_draw_top(d, u)
		if d.phase == "fight":
			_draw_gap(u)
			_draw_catch(d, u)
		elif d.phase == "over":
			_draw_end(d, u)

	# ---- 掛金の画面

	func _draw_bet(d: Dictionary, u: float) -> void:
		var me: int = ui.me()
		var them: int = Duel.opponent(d, me)
		var w := 760.0 * u
		var h := 460.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.46 - h / 2.0, w, h)
		var rects := {}
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), Color(0.36, 0.42, 0.33), 0.98, false)
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		# 左に自分、右に相手（クリーム色の札に人形。受けたら足もとに ✓）
		for side in [-1, 1]:
			var who: int = me if side < 0 else them
			var ok: bool = d.ok_a if who == int(d.a) else d.ok_b
			var cx: float = size.x / 2.0 + side * w * 0.36
			var card := Rect2(cx - 80 * u, r.position.y + 50 * u, 160 * u, 250 * u)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, card.size.x, card.size.y, 14 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			Icons._o = Vector2(cx, card.position.y + 190 * u)
			Icons._s = 2.6 * u
			Icons.doll(self, Vector2.ZERO, ui._color(who), "stand" if not ok else "wave")
			Icons.screen()
			if ok:
				_check(Vector2(cx, card.end.y - 28 * u), 22 * u)
			else:
				Icons.dashes(self, Icons.circ(Vector2(cx, card.end.y - 28 * u), 16 * u, 16), Icons.PAPER_EDGE, 2.0 * u, 4 * u, 3 * u, 1.0, true)
		# まんなか: 掛金（ひとり分のボタン。勝てばこの 2 倍）
		var cx := size.x / 2.0
		var pot := Vector2(cx, r.position.y + 110 * u)
		Icons.screen()
		Icons.patch(self, Icons.ell(pot, 120 * u, 62 * u, 28), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
		var n := int(d.stake)
		var shake: float = sin(ui._shake * 40.0) * 8.0 * u * ui._shake
		if n > 0:
			CraftIcons.price(self, pot + Vector2(shake, 0), n, 14 * u)
		else:
			Icons.screen()
			Icons.dashes(self, Icons.circ(pot + Vector2(shake, 0), 14 * u, 16), Icons.PAPER_EDGE, 2.0 * u, 4 * u, 3 * u, 1.0, true)
		# 上下の矢印: 木（1）・真鍮（10）・白蝶貝（100）
		for i in STEPS.size():
			var c := Vector2(cx + (i - 1) * 78 * u, r.position.y + 250 * u)
			CraftIcons._at(c, 64.0)
			CraftIcons.money(self, Vector2.ZERO, 17 * u, STEPS[i][1])
			for dir in [-1, 1]:
				var key := ("up%d" if dir < 0 else "down%d") % i
				var at := c + Vector2(0, dir * 46 * u)
				var box := Rect2(at - Vector2(28, 22) * u, Vector2(56, 44) * u)
				rects[key] = box
				var big := 1.15 if ui._hover == key else 1.0
				Icons.screen()
				Icons.patch(self, Icons.circ(at, 19 * u * big, 18), Icons.CAP, 1.0, false)
				Icons.chevron(self, at, 18 * u * big, Icons.THREAD, 1.0, -PI / 2 if dir < 0 else PI / 2, 2.6 * u)
		# 下: 受ける（赤い丸に、手袋の握手）。まわりの糸が、やめるまでの残り
		var bc := Vector2(cx, r.end.y - 72 * u)
		var bs := 104.0 * u
		var my_ok: bool = d.ok_a if me == int(d.a) else d.ok_b
		var big := 1.06 if ui._hover == "ok" and not my_ok else 1.0
		rects["ok"] = Rect2(bc - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
		Icons.screen()
		Icons.patch(self, Icons.circ(bc, bs * 0.5 * big, 28), Icons.RED if not my_ok else Icons.RED.lerp(Icons.PAPER_EDGE, 0.6), 1.0, true, Icons.CAP)
		_shake_hands(bc, bs / 64.0 * big, Icons.CAP)
		var left := clampf(Duel.left_s(d) / Duel.BET_T, 0.0, 1.0)
		draw_arc(bc, bs * 0.5 * big + 7 * u, -PI / 2, -PI / 2 + TAU * left, 40, Color(Icons.CAP, 0.85), 2.5 * u, true)
		# 右上: やめる（× の縫い目）
		var xs := 46.0 * u
		var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
		rects["close"] = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
		Icons.screen()
		Icons.patch(self, Icons.circ(xc, xs * 0.5 * (1.08 if ui._hover == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
		Icons._o = xc
		Icons._s = xs / 64.0
		Icons.thread(self, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)
		ui._rects = rects

	## 糸の ✓
	func _check(c: Vector2, s: float) -> void:
		Icons._o = c
		Icons._s = s / 20.0
		Icons.thread(self, PackedVector2Array([Vector2(-9, 0), Vector2(-3, 7), Vector2(10, -8)]), Color(0.25, 0.52, 0.34), 4.0, 1.0)

	## 握手の手袋（2 つの手袋が向かい合って重なる）。c は画面、sc は 64 の絵の 1 単位の px
	func _shake_hands(c: Vector2, sc: float, col: Color) -> void:
		Icons._o = c
		Icons._s = sc
		Icons.mitten(self, Vector2(-8, 3), PI / 2, col, 1.0, true, 1.0)              # 左から差し出した手
		Icons.mitten(self, Vector2(8, -3), -PI / 2, col.darkened(0.15), 1.0, true, 1.0)   # 右から重ねた手

	# ---- 戦いの上の帯

	func _draw_top(d: Dictionary, u: float) -> void:
		var me: int = ui.me()
		var them: int = Duel.opponent(d, me)
		var over: bool = d.phase == "over"
		var cx := size.x / 2.0
		var cy := 74.0 * u
		var rr := 46.0 * u
		var left := Duel.left_s(d)
		var hurry := not over and left < 10.0
		var beat := 1.0 + (0.08 * absf(sin(left * PI)) if hurry else 0.0) + 0.12 * sin(ui._pop.get("start", 0.0) * PI)
		# 刺繍枠の時計
		Icons.screen()
		Icons.patch(self, Icons.circ(Vector2(cx, cy), rr * 1.18 * beat, 36), Icons.WOOD, 1.0, false)
		Icons.patch(self, Icons.circ(Vector2(cx, cy), rr * 1.02 * beat, 36), Icons.PAPER, 1.0, false)
		var total := Duel.PAY_T if over else Duel.FIGHT_T
		var marks := 60
		var on := int(ceil(left / total * marks))
		for i in marks:
			var ang := -PI / 2 + TAU * i / marks
			var dirv := Vector2(cos(ang), sin(ang))
			var p0 := Vector2(cx, cy) + dirv * rr * 0.80 * beat
			var p1 := Vector2(cx, cy) + dirv * rr * 0.95 * beat
			if i < on:
				var col: Color = GOLD if over else (Icons.RED if not hurry else Icons.RED.lightened(0.15))
				draw_line(p0, p1, col, 3.0 * u, true)
			else:
				draw_circle(p1, 1.2 * u, Color(Icons.SHADOW, 0.35))   # 糸を抜いたあとの針穴
		if over:
			_rosette(Vector2(cx, cy), rr * 0.62, int(d.winner))
		else:
			# まんなかに掛金（なしなら綿の雪玉）
			if int(d.stake) > 0:
				CraftIcons.price(self, Vector2(cx, cy), int(d.stake) * 2, 7 * u)
			else:
				_cotton(Vector2(cx, cy), 12 * u, 3)
		# 左に自分、右に相手の残り
		for side in [-1, 1]:
			var who: int = me if side < 0 else them
			var lives: int = Duel.lives_of(d, who)
			var col: Color = ui._color(who)
			var x0: float = cx + side * (rr * 1.5 + 18 * u)
			Icons._o = Vector2(x0 + side * 150 * u, cy + 26 * u)
			Icons._s = 1.4 * u
			var blink: float = 0.35 if ui.duel.guarded(who) and Time.get_ticks_msec() / 120 % 2 == 0 else 1.0
			Icons.doll(self, Vector2.ZERO, col, "stand", blink)
			for i in Duel.LIVES:
				var hc := Vector2(x0 + side * (24 + i * 44) * u, cy)
				var lost := i >= lives
				var pop: float = ui._pop.get("lost", 0.0) if i == lives else 0.0
				_heart(hc, 17 * u * (1.0 + 0.4 * sin(pop * PI)), col, lost)
		# 下: 円の小さな地図
		var mc := Vector2(cx, cy + rr * 1.18 + 62 * u)
		if not over:
			_map(d, mc, 52 * u, them)
		else:
			# 握手で払う（手袋の握手）と、勝った人に行く掛金。相手が抜けたら握手はない
			var hub = ui.main.get("emotes")
			if hub == null or hub.who_of(them) != null:
				Icons.screen()
				Icons.patch(self, Icons.circ(mc, 34 * u, 24), Icons.CAP, 1.0, true)
				_shake_hands(mc, 0.95 * u, Icons.RED)
			if int(d.stake) > 0:
				CraftIcons.price(self, mc + Vector2(80 * u, 0), int(d.stake) * 2, 10 * u)

	## フェルトのハート。lost なら縫い目の輪郭だけと、べちゃっと付いた綿の雪
	func _heart(c: Vector2, r: float, col: Color, lost: bool) -> void:
		var pts := PackedVector2Array()
		for k in 28:
			var t := TAU * k / 28.0
			var x := 16.0 * pow(sin(t), 3)
			var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
			pts.append(c + Vector2(x, y) * r / 16.0)
		Icons.screen()
		if lost:
			Icons.dashes(self, pts, col.darkened(0.2), 1.6, 3.5, 2.5, 0.8, true)
			_cotton(c + Vector2(r * 0.15, -r * 0.1), r * 0.62, int(c.x) % 7)
		else:
			Icons.patch(self, pts, col, 1.0, true)
			draw_circle(c + Vector2(-r * 0.38, -r * 0.35), r * 0.16, Color(1, 1, 1, 0.35))

	## ロゼット（勝った人の色のフェルトの花びらに、リボンの 2 本の尾）。引き分けは生成り
	func _rosette(c: Vector2, r: float, winner: int) -> void:
		var col: Color = ui._color(winner) if winner >= 0 else Icons.PAPER_EDGE
		var pop: float = 1.0 + 0.25 * sin(ui._pop.get("end", 0.0) * PI)
		r *= pop
		Icons.screen()
		for side in [-1, 1]:
			Icons.patch(self, PackedVector2Array([c + Vector2(side * r * 0.25, r * 0.3), c + Vector2(side * r * 0.75, r * 1.55),
				c + Vector2(side * r * 0.45, r * 1.35), c + Vector2(side * r * 0.25, r * 1.6), c + Vector2(side * r * 0.0, r * 0.4)]), col.darkened(0.15), 1.0, false)
		var petals := PackedVector2Array()
		for k in 32:
			var t := TAU * k / 32.0
			petals.append(c + Vector2(cos(t), sin(t)) * r * (1.0 if k % 2 == 0 else 0.84))
		Icons.patch(self, petals, col, 1.0, true)
		Icons.patch(self, Icons.circ(c, r * 0.6, 24), GOLD if winner >= 0 else Icons.CAP, 1.0, true)
		if winner >= 0:
			Icons._o = c + Vector2(0, r * 0.42)
			Icons._s = r / 40.0
			Icons.doll(self, Vector2.ZERO, col, "wave")

	## 円の小さな地図。上が自分の見ている向き
	func _map(d: Dictionary, c: Vector2, r: float, them: int) -> void:
		var p: Node3D = ui.player
		var at: Vector3 = d.at
		var k := r / Duel.RADIUS
		var yaw := p.global_rotation.y
		var to_map := func(w: Vector3) -> Vector2:
			var v := Vector2(w.x - at.x, w.z - at.z).rotated(yaw)
			return c + v * k
		Icons.screen()
		Icons.patch(self, Icons.circ(c, r * 1.12, 36), Icons.SNOW, 0.95, false)
		var mine := Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length()
		var edge := clampf((mine - (Duel.RADIUS - 1.2)) / 0.9, 0.0, 1.0)   # 縁に近いほど輪が太く赤く
		Icons.dashes(self, Icons.circ(c, r, 40), Icons.RED.lightened(0.1 - 0.1 * edge), 2.0 + 2.5 * edge, 5.0, 3.0, 1.0, true)
		for i in Duel.PINS:
			var ang := TAU * i / Duel.PINS
			var q := Vector2(cos(ang), sin(ang)).rotated(yaw) * r
			draw_circle(c + q, 2.6 * Icons.ui_scale(size.y), ui._color(int(d.a) if i % 2 == 0 else int(d.b)))
		# 飛んでいる相手の雪玉
		var hub = ui.main.get("emotes")
		if hub:
			for b in hub.get_children():
				if b is Snowball and b.thrower == them and not b._done:
					draw_circle(to_map.call(b.global_position), 3.0 * Icons.ui_scale(size.y), Color(1, 1, 1))
					draw_arc(to_map.call(b.global_position), 3.0 * Icons.ui_scale(size.y), 0, TAU, 10, Color(Icons.SHADOW, 0.5), 1.0, true)
		var t: Node3D = hub.who_of(them) if hub else null
		if t:
			Icons.patch(self, Icons.circ(to_map.call(t.global_position), 6.5 * Icons.ui_scale(size.y), 14), ui._color(them), 1.0, false)
		# 自分: 上向きの矢じり
		var mc: Vector2 = to_map.call(p.global_position)
		var s := 8.0 * Icons.ui_scale(size.y)
		Icons.patch(self, PackedVector2Array([mc + Vector2(0, -s * 1.3), mc + Vector2(s, s), mc + Vector2(0, s * 0.45), mc + Vector2(-s, s)]), ui._color(ui.me()), 1.0, false)

	## 綿の雪玉（food_ui.gd と同じ考え）
	func _cotton(c: Vector2, r: float, seed: int) -> void:
		var pts := PackedVector2Array()
		for k in 13:
			var t := TAU * k / 13.0 + seed * 0.7
			var w := 1.0 + 0.08 * sin(seed * 12.9898 + k * 78.233)
			pts.append(c + Vector2(cos(t), sin(t)) * r * w)
		var uv := PackedVector2Array()
		for q in pts:
			uv.append((q - c) / (r * 1.6))
		draw_colored_polygon(pts, Color(0.98, 0.98, 0.96), uv, Icons.felt())
		draw_arc(c + Vector2(0, r * 0.15), r * 0.8, 0.3, PI - 0.3, 10, Color(0.72, 0.80, 0.92, 0.45), r * 0.25, true)

	# ---- 勝ち負けと握手の案内

	func _draw_end(d: Dictionary, u: float) -> void:
		var me: int = ui.me()
		var them: int = Duel.opponent(d, me)
		var hub = ui.main.get("emotes")
		var gone: bool = hub != null and hub.who_of(them) == null
		var t: float = ui._end_t
		var move := smoothstep(END_BIG_T, END_BIG_T + END_MOVE_T, t)
		var big_at := Vector2(size.x / 2.0, size.y * 0.40)
		var small_at := Vector2(size.x / 2.0, 272.0 * u)
		var pop := 1.0 + 0.18 * sin(clampf(t / 0.3, 0.0, 1.0) * PI)
		var sub := ""
		if gone:
			sub = "相手が抜けた"
		elif Duel.lives_of(d, me) > 0 and Duel.lives_of(d, them) > 0:
			sub = "時間切れ"
		_result(big_at.lerp(small_at, move), lerpf(1.0, 0.4, move) * pop * u, int(d.winner), me, sub)
		if t >= END_BIG_T:
			_shake_guide(Vector2(size.x / 2.0, size.y * 0.68), u, gone, clampf((t - END_BIG_T) / END_MOVE_T, 0.0, 1.0))

	## 勝敗のワッペン。勝ちは赤のフェルトに金の縫い目、負けは藍のフェルトに麻の縫い目で字は生成り。引き分けは麻色のフェルトに藍の字。s は 1080p の 1 px の大きさ
	func _result(c: Vector2, s: float, winner: int, me: int, sub: String) -> void:
		var word := "引き分け"
		var felt := Icons.PAPER_EDGE
		var thread := Doll.STOCK_NAVY.lightened(0.1)
		var edge := Icons.CAP
		if winner == me:
			word = "勝ち"
			felt = Icons.RED
			thread = Icons.CAP
			edge = GOLD
		elif winner >= 0:
			word = "負け"
			felt = Doll.STOCK_NAVY
			thread = Icons.CAP
			edge = Color(0.70, 0.57, 0.38)
		var fs := 132.0 * s
		var font := Icons._bold_font()
		var tw := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
		var w := tw + 150.0 * s
		var h := (214.0 if sub != "" else 190.0) * s
		var word_y := c.y - (24.0 * s if sub != "" else 0.0)
		Icons.screen()
		Icons.patch(self, Icons.rr(c.x - w / 2.0, c.y - h / 2.0, w, h, 26.0 * s), felt, 1.0, false)
		Icons.dashes(self, Icons.rr(c.x - w / 2.0 + 13.0 * s, c.y - h / 2.0 + 13.0 * s, w - 26.0 * s, h - 26.0 * s, 16.0 * s), edge, 3.5 * s, 13.0 * s, 8.0 * s, 1.0, true)
		Icons.stitched_text(self, word, Vector2(c.x - tw / 2.0, word_y), fs, thread)
		if sub != "":
			var sub_fs := 34.0 * s
			var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, int(sub_fs)).x
			Icons.stitched_text(self, sub, Vector2(c.x - sw / 2.0, c.y + 66.0 * s), sub_fs, thread)

	## 握手の案内: 生成りの札に、2 キー・字・手袋の握手。低い手のひらを出したら、キーが押された形になって字が短くなる。相手がいないなら握手はない
	func _shake_guide(c: Vector2, u: float, gone: bool, a: float) -> void:
		var low: bool = String(ui.player.get("hands_name")).begins_with("low")
		var text := "握手なしで終わります" if gone else ("近づいて握手" if low else "を押して、近づいて握手")
		var fs := 34.0 * u
		var key_w := 0.0 if gone else (82.0 if low else 46.0) * u
		var hands_w := 0.0 if gone else 72.0 * u
		var tw := Icons._bold_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
		var gap := 12.0 * u
		var w := key_w + tw + hands_w + (gap * 2.0 if not gone else 0.0) + 56.0 * u
		var h := 76.0 * u
		var x := c.x - w / 2.0 + 28.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(c.x - w / 2.0, c.y - h / 2.0, w, h, 16.0 * u), Icons.PAPER, a, true, Icons.PAPER_EDGE)
		if a < 1.0:
			return
		if not gone:
			Icons.keycap(self, "2", Vector2(x + 23.0 * u, c.y), 44.0 * u, 1.0, low)
			if low:
				_check(Vector2(x + 64.0 * u, c.y), 22.0 * u)
			Icons.screen()
			x += key_w + gap
		Icons.stitched_text(self, text, Vector2(x, c.y), fs, Icons.THREAD)
		if not gone:
			_shake_hands(Vector2(x + tw + gap + hands_w / 2.0, c.y), 1.0 * u, Icons.RED)
			Icons.screen()

	# ---- 投げの間

	## 次を投げられるまでの残り。藍のフェルトの丸（雪玉のストックと同じ布と麻の縁）に、時計と同じ向きで抜けていく赤い糸の輪。
	## まんなかは、待っているあいだ破線の丸（雪玉がまだ手に来ていない）。明けると糸の輪が金になって綿の雪玉が跳ね、消える。
	## 雪玉を持っていなければ、跳ねずに消える
	func _draw_gap(u: float) -> void:
		var wait: int = ui.duel.throw_wait(ui.me())
		var pop: float = ui._pop.get("gap", 0.0)
		var hub = ui.main.get("emotes")
		var has_ball: bool = hub != null and hub.balls_of(ui.me()) > 0
		if wait <= 0 and (pop <= 0.0 or not has_ball):
			return
		var r := GAP_R * u
		var c := Vector2(size.x - (18.0 + 230.0 - GAP_R) * u, size.y - (18.0 + 46.0 + 12.0 + GAP_R) * u)
		var a := 1.0
		var big := 1.0
		if wait <= 0:
			a = clampf(pop / 0.35, 0.0, 1.0)   # 跳ねたあとに薄れて消える
			big += 0.25 * sin(pop * PI)
		Icons.screen()
		Icons.patch(self, Icons.circ(c, r * big, 28), Doll.STOCK_NAVY, a, true, Color(0.70, 0.57, 0.38))
		for i in Duel.GAP_FRAMES:
			var ang := -PI / 2 + TAU * i / Duel.GAP_FRAMES
			var dirv := Vector2(cos(ang), sin(ang))
			var p1 := c + dirv * r * 0.84 * big
			if wait <= 0:
				draw_line(c + dirv * r * 0.68 * big, p1, Color(GOLD, a), 3.0 * u, true)
			elif i < wait:
				draw_line(c + dirv * r * 0.68 * big, p1, Doll.STOCK_RED, 3.0 * u, true)
			else:
				draw_circle(p1, 1.3 * u, Color(Doll.STOCK_NAVY.darkened(0.5), 0.8))   # 糸を抜いたあとの針穴
		if wait <= 0:
			Icons.cotton(self, c, r * 0.56 * big, 1, a)
		else:
			Icons.screen()
			Icons.dashes(self, Icons.circ(c, r * 0.42, 16), Icons.CAP, 2.0 * u, 4.0 * u, 3.0 * u, 0.9, true)

	# ---- キャッチの照準

	## 手の届きそうな相手の雪玉に、破線の輪。照準が合って取れるなら、まんなかに開いた手袋
	func _draw_catch(d: Dictionary, u: float) -> void:
		var p: Node3D = ui.player
		var cam: Camera3D = p.get("cam")
		var hub = ui.main.get("emotes")
		if cam == null or hub == null:
			return
		var them := Duel.opponent(d, ui.me())
		var mid := size / 2.0
		var ready: Snowball = ui.duel.catchable(p, cam, them)
		for b in hub.get_children():
			if not (b is Snowball) or b.thrower != them or b._done or cam.is_position_behind(b.global_position):
				continue
			var dist: float = b.global_position.distance_to(ui.duel._chest(p))
			if dist > 3.0:
				continue
			var sp := cam.unproject_position(b.global_position)
			var a := clampf((3.0 - dist) / 2.0, 0.2, 1.0)
			Icons.screen()
			Icons.dashes(self, Icons.circ(sp, 26 * u, 20), Icons.CAP, 2.2 * u, 5 * u, 4 * u, a, true)
		var pop: float = ui._pop.get("catch", 0.0)
		if ready or pop > 0.0:
			Icons.screen()
			draw_arc(mid, 30 * u * (1.0 + 0.3 * sin(pop * PI)), 0, TAU, 32, Color(Icons.RED, 0.9), 3.0 * u, true)
			Icons._o = mid + Vector2(-14 * u, 46 * u)
			Icons._s = 1.1 * u
			Icons.mitten(self, Vector2.ZERO, 0.0, Icons.RED, 1.0, pop <= 0.0, 1.0)
			if pop <= 0.0:
				Icons.screen()
				Icons.keycap(self, "F", mid + Vector2(16 * u, 46 * u), 26 * u)
