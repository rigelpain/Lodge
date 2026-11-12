extends Node
## ホストの操作（設定の画面の中。ホストのときだけ出る）。2026-11-12 代表「ホストが参加メンバーの位置を変えたり所持金を変えたり
## ワールドを切り替えたり、ゲーム中にできるようにしてほしい」
##   ワールド: 選んで「移る」。つないでいる人もいっしょに移る（net.gd の host_world）。工房の持ち物・財布は始め直し
##   全員: 自分のそばへ呼ぶ・はじめの所へ
##   人ごと: 財布のボタンの数（打つか矢印で。net.gd の host_purse → craft.gd の purse）、呼ぶ・その人のそばへ行く・はじめの所へ
## 設定の画面なので字で書く（字を使わないのは遊ぶ画面。設定の画面だけは字）。
## main.gd が置き、settings.gd の host_slot の中に行を作る。画面が開いているあいだ、来ている人が変われば作り直し、財布の数を合わせる

const WORLD_NAMES := {"plain": "今までの世界（ロッジ）", "tenkamori": "天下森", "asahigaoka": "旭ヶ丘（倶知安）"}
const NEAR_R := 1.8           # 呼んだ人を並べる、自分からの距離 (m)
const NEAR_ARC := 120.0       # 呼んだ人を並べる、自分の前の弧の広さ (度)
const BESIDE := 1.5           # その人のそばへ行くとき、その人から離れて立つ距離 (m)
const FONT := 15

var main: Node3D
var net: Node
var settings: CanvasLayer

var _t := 0.0
var _shown := ""              # いま行を作ってある顔ぶれ（番号を並べた文字）。変わったら作り直す
var _purses := {}             # 人の番号 → 財布の SpinBox
var _world_pick: OptionButton


func _process(dt: float) -> void:
	if settings == null or not settings.is_open:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.5
	var host: bool = net != null and net.is_host()
	var ids := ""
	if host:
		for m in net.members():
			ids += "%d," % m[0]
	if ids != _shown or (not host and settings.host_slot.get_child_count() > 0):
		_build(host)
		_shown = ids
	_sync_purses()


## 行を作り直す（ホストでなければ空に）
func _build(host: bool) -> void:
	for c in settings.host_slot.get_children():
		c.queue_free()
	_purses.clear()
	_world_pick = null
	if host:
		var box: VBoxContainer = settings.host_slot
		var title := Label.new()
		title.text = "ホストの操作"
		title.add_theme_font_size_override("font_size", 17)
		box.add_child(title)
		box.add_child(_world_row())
		box.add_child(_all_row())
		var head := _label("名前 ／ ボタン ／ 場所", 13)
		head.modulate.a = 0.6
		box.add_child(head)
		var members: Array = net.members()
		for m in members:
			box.add_child(_member_row(int(m[0]), m[1]))
		box.add_child(HSeparator.new())   # ここから下は、ふだんの設定
	settings.relayout()


func _world_row() -> HBoxContainer:
	var row := _row()
	var lb := _label("ワールド")
	lb.custom_minimum_size.x = 80
	row.add_child(lb)
	_world_pick = OptionButton.new()
	_world_pick.add_theme_font_size_override("font_size", FONT)
	_world_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for w in main.WORLDS:
		_world_pick.add_item(WORLD_NAMES.get(w, w))
		if w == main.stage:
			_world_pick.select(_world_pick.item_count - 1)
	row.add_child(_world_pick)
	row.add_child(_button("移る", func():
		var w: String = main.WORLDS[_world_pick.selected]
		if w != main.stage:
			net.host_world(w)))
	return row


func _all_row() -> HBoxContainer:
	var row := _row()
	var lb := _label("全員")
	lb.custom_minimum_size.x = 80
	row.add_child(lb)
	row.add_child(_button("自分のそばへ呼ぶ", _call_all))
	row.add_child(_button("はじめの所へ", _start_all))
	return row


func _member_row(who: int, body: Node3D) -> HBoxContainer:
	var row := _row()
	var me: bool = body == main.player
	var dot := ColorRect.new()
	dot.color = main.craft.color_of(who)
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var nm := _label(String(main.craft.names.get(who, "?")) + ("（自分）" if me else ""))
	nm.custom_minimum_size.x = 110
	nm.clip_text = true
	row.add_child(nm)
	var sp := SpinBox.new()
	sp.min_value = 0
	sp.max_value = main.craft.PURSE_MAX
	sp.step = 1
	sp.rounded = true
	sp.suffix = "枚"
	sp.custom_minimum_size.x = 110
	sp.select_all_on_focus = true
	sp.get_line_edit().add_theme_font_size_override("font_size", FONT)
	sp.set_value_no_signal(main.craft.wallet(who))
	sp.value_changed.connect(func(v: float): net.host_purse(who, roundi(v)))
	row.add_child(sp)
	_purses[who] = sp
	if not me:
		row.add_child(_button("呼ぶ", func(): _call(who)))
		row.add_child(_button("行く", func(): _go_to(body)))
	row.add_child(_button("はじめへ", func(): _start(who)))
	return row


## 財布の数を、いまの数に合わせる（打っている途中の欄はそのまま）
func _sync_purses() -> void:
	for who in _purses:
		var sp: SpinBox = _purses[who]
		if is_instance_valid(sp) and not sp.get_line_edit().has_focus():
			var n: int = main.craft.wallet(who)
			if int(sp.value) != n:
				sp.set_value_no_signal(n)


# ---- 場所 -----------------------------------------------------------------------------------

## 自分以外の来ている人の番号
func _others() -> Array:
	var out := []
	for m in net.members():
		if m[1] != main.player:
			out.append(int(m[0]))
	return out


## 自分の前の弧に、i 番目（n 人のうち）を並べる所と、自分を向く向き
func _near_me(i: int, n: int) -> Array:
	var p: Node3D = main.player
	var a := 0.0 if n <= 1 else deg_to_rad(-NEAR_ARC / 2.0 + NEAR_ARC * i / (n - 1))
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = (fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD).rotated(Vector3.UP, a)
	var at := p.global_position + fwd * NEAR_R + Vector3.UP * 0.2
	return [at, _face(at, p.global_position)]


func _face(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


func _call(who: int) -> void:
	var o := _others()
	var spot := _near_me(maxi(o.find(who), 0), o.size())
	net.host_warp(who, spot[0], spot[1])


func _call_all() -> void:
	var o := _others()
	for i in o.size():
		var spot := _near_me(i, o.size())
		net.host_warp(o[i], spot[0], spot[1])


## その人のそばへ行く（自分を、その人から自分のほうへ BESIDE 離れた所へ。その人を向いて）
func _go_to(body: Node3D) -> void:
	if not is_instance_valid(body) or main.player == null:
		return
	var them := body.global_position
	var me: Node3D = main.player
	var d := me.global_position - them
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3.BACK
	var at := them + d * BESIDE + Vector3.UP * 0.2
	net.host_warp(int(main.player.id), at, _face(at, them))


## はじめの所（main.gd が人を置くのと同じ並び。自分が真ん中、ほかは左右へ）
func _start_spot(slot: int) -> Vector3:
	var st: Vector3 = main.start_pos()
	var at: Vector3 = st if slot == 0 else st + Vector3(2.5 * ceili(slot / 2.0) * (1 if slot % 2 == 1 else -1), 0, 1.5)
	return at + Vector3(0, main.height(at.x, at.z) + 0.2, 0)


func _start(who: int) -> void:
	var slot := 0 if main.player and who == int(main.player.id) else _others().find(who) + 1
	net.host_warp(who, _start_spot(slot), NAN)


func _start_all() -> void:
	var o := _others()
	for i in o.size():
		net.host_warp(o[i], _start_spot(i + 1), NAN)


# ---- 部品 -----------------------------------------------------------------------------------

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	return row


func _label(t: String, size := FONT) -> Label:
	var lb := Label.new()
	lb.text = t
	lb.add_theme_font_size_override("font_size", size)
	return lb


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE   # 押したあとの Space・Enter でもう一度押されないように
	b.add_theme_font_size_override("font_size", FONT)
	b.pressed.connect(cb)
	return b
