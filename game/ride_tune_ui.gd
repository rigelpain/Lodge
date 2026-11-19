extends Control
## 乗り心地の調整の画面（テストプレイ用。値と JSON の出し入れは ride_tune.gd）。
## 設定の画面（settings.gd）で「確かめ用の数字」を入れると出る「乗り心地の調整」ボタンから開く。Esc で設定ごと閉じる。
## 字を使う（2026-11-19 代表に確かめた。設定の画面と同じ扱いで、遊ぶ人には見せない）。
## 画面の右に縦長に置き、左にゲームが見えるようにする。既定から変えた値は数字を黄色に

const Tune := preload("res://ride_tune.gd")

signal back   # 「設定へ戻る」を押した

const W := 560.0
const CHANGED := Color(1.0, 0.85, 0.35)

var ui_scale := 1.0
var _panel: PanelContainer
var _scroll: ScrollContainer
var _status: Label
var _rows := []   # [項目, スライダー, 数字]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.86)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "乗り心地の調整（テストプレイ用）"
	title.add_theme_font_size_override("font_size", 20)
	outer.add_child(title)
	var note := Label.new()
	note.text = "変えた値はこの起動のあいだだけ効きます。つないで遊ぶときは、ソリの動きと飛び方はホストの値、画面の揺れは各自の値。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = W
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	outer.add_child(note)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	outer.add_child(bar)
	_button(bar, "JSON をコピー", _copy)
	_button(bar, "貼り付けて読む", _paste)
	_button(bar, "既定に戻す", _reset)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	_button(bar, "設定へ戻る", func(): back.emit())
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", CHANGED)
	outer.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size.x = W
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	for it in Tune.ITEMS:
		if it[0] == "#":
			var h := Label.new()
			h.text = it[1]
			h.add_theme_font_size_override("font_size", 16)
			h.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
			if box.get_child_count() > 0:
				box.add_child(HSeparator.new())
			box.add_child(h)
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lb := Label.new()
		lb.text = it[3]
		lb.tooltip_text = Tune.id(it)
		lb.mouse_filter = Control.MOUSE_FILTER_PASS
		lb.add_theme_font_size_override("font_size", 14)
		lb.custom_minimum_size.x = 290
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lb)
		var sl := HSlider.new()
		sl.min_value = it[4]
		sl.max_value = it[5]
		sl.step = it[6]
		sl.allow_greater = true   # 貼った値が範囲の外でも、そのまま持つ
		sl.allow_lesser = true
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sl)
		var num := Label.new()
		num.custom_minimum_size.x = 64
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.add_theme_font_size_override("font_size", 14)
		row.add_child(num)
		sl.value_changed.connect(func(v: float):
			Tune.set_value(it, v)
			_show(it, num))
		box.add_child(row)
		_rows.append([it, sl, num])
	refresh()
	get_viewport().size_changed.connect(layout)


func _button(bar: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	bar.add_child(b)


## いまの値を、すべてのスライダーと数字に写す
func refresh() -> void:
	for r in _rows:
		r[1].set_value_no_signal(Tune.value(r[0]))
		_show(r[0], r[2])


func _show(it: Array, num: Label) -> void:
	var v := Tune.value(it)
	var digits := 3 if float(it[6]) < 0.01 else (2 if float(it[6]) < 0.1 else 1)
	num.text = String.num(v, digits)
	var changed := not is_equal_approx(v, Tune.default_value(it))
	num.add_theme_color_override("font_color", CHANGED if changed else Color.WHITE)
	num.tooltip_text = "既定 %s" % String.num(Tune.default_value(it), digits) if changed else ""
	num.mouse_filter = Control.MOUSE_FILTER_PASS


func _copy() -> void:
	DisplayServer.clipboard_set(Tune.to_json())
	var n := 0
	for r in _rows:
		if not is_equal_approx(Tune.value(r[0]), Tune.default_value(r[0])):
			n += 1
	_status.text = "クリップボードにコピーしました（既定から変えた値 %d 個）" % n


func _paste() -> void:
	var n := Tune.from_json(DisplayServer.clipboard_get())
	if n < 0:
		_status.text = "クリップボードの中身を JSON として読めませんでした"
		return
	refresh()
	_status.text = "%d 個の値を読み込みました" % n


func _reset() -> void:
	Tune.reset()
	refresh()
	_status.text = "すべて既定に戻しました"


## 画面の右に、上から下まで。メニューの大きさ（ui_scale）で拡げる
func layout() -> void:
	if _panel == null or not is_inside_tree():
		return
	var view := get_viewport().get_visible_rect().size
	var k := ui_scale
	var h := (view.y - 32.0) / k
	_panel.reset_size()
	_panel.size = Vector2(W + 36.0 + 14.0, h)
	_panel.scale = Vector2(k, k)
	_panel.position = Vector2(maxf(8.0, view.x - _panel.size.x * k - 16.0), 16.0)


func panel_rect() -> Rect2:
	return Rect2(_panel.position, _panel.size * _panel.scale)
