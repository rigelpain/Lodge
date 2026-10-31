extends CanvasLayer
## 設定画面。Esc で開き、マウスで触る。値は user://settings.cfg に保存して次回も効く。
## 項目を足すときは ITEMS に 1 行足し、main.gd の _apply_setting で受ける。
## メニューの大きさ（menu_scale）はこの画面そのものを拡げ、画面に入らなければ中をスクロールする。
## HUD の大きさ（hud_scale）は hud_icons.gd の倍率に入れ、HUD の表示（札・ワッペン・持ち物の列・身ぶりの輪・日時計）にかかる。

const Icons := preload("res://hud_icons.gd")

signal changed(key: String, value)

const PATH := "user://settings.cfg"
const VERSION := 3   # 既定値を変えたら上げる。古い保存は、その項目だけ既定に戻す
# [鍵, 見出し, 種類, 既定, 範囲や段]
const ITEMS := [
	["bob", "視点の揺れ（押す・引くとき）", "bool", true, null],
	["fov_kick", "押すときに画角が少し広がる", "bool", true, null],
	["ride_fov", "滑るときに画角が広がる", "bool", true, null],
	["ride_fov_amt", "滑るときの画角の広がり", "float", 1.0, [0.0, 1.0, 0.05]],
	["pip", "右上の 360° 映像", "bool", true, null],
	["selfcam", "右下の自分の姿（前から）", "bool", true, null],
	["snow", "舞う雪", "bool", true, null],
	["wind", "風の流れ（滑るとき）", "float", 1.0, [0.0, 1.0, 0.05]],
	["third", "三人称", "bool", false, null],
	["fov", "視野角（一人称）", "float", 75.0, [50.0, 110.0, 1.0]],
	["cam_dist", "三人称: カメラの距離", "float", 3.4, [1.4, 9.0, 0.1]],
	["cam_frame", "三人称: 人形の画面の高さ", "float", -0.2, [-0.75, 0.5, 0.05]],
	["sens", "マウスの感度", "float", 1.0, [0.3, 2.5, 0.05]],
	["scale", "3D の描画の解像度（軽さ）", "float", 0.67, [0.4, 1.0, 0.01]],
	["ssao", "くぼみの影（SSAO）", "bool", true, null],
	["shadows", "影", "bool", true, null],
	["vol_music", "音量: 音楽", "float", 0.05, [0.0, 1.0, 0.01]],
	["vol_sfx", "音量: 効果音", "float", 0.05, [0.0, 1.0, 0.01]],
	["vol_voice", "音量: ボイス", "float", 0.05, [0.0, 1.0, 0.01]],
	["hints", "操作の手引き（近づいたときのアイコン）", "bool", true, null],
	["speedo", "滑る速さの表示（糸巻き）", "bool", true, null],
	["hud_wind", "HUD が風で揺れる（滑るとき）", "bool", true, null],
	["hud_debug", "確かめ用の数字（fps・通信）", "bool", false, null],
	["menu_scale", "メニューの大きさ", "float", 1.0, [0.7, 1.6, 0.05]],
	["hud_scale", "HUD の大きさ", "float", 1.0, [0.7, 1.6, 0.05]],
]

var values := {}
var is_open := false
var _panel: PanelContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _controls := {}
var _dragging := ""          # いま動かしているスライダー（メニューの大きさは離してから当てる）


func _ready() -> void:
	layer = 5
	for it in ITEMS:
		values[it[0]] = it[3]
	_load()
	Icons.user_scale = values["hud_scale"]
	_build()
	_panel.get_parent().visible = false
	get_viewport().size_changed.connect(_layout)


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.86)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# 画面いっぱいの入れ物に置き、大きさと位置は _layout が決める（メニューの大きさで拡げ、中央へ）
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 396
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	_box = box

	var title := Label.new()
	title.text = "設定"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	for it in ITEMS:
		var key: String = it[0]
		if it[2] == "bool":
			var cb := CheckButton.new()
			cb.text = it[1]
			cb.button_pressed = values[key]
			cb.add_theme_font_size_override("font_size", 15)
			cb.toggled.connect(func(on: bool): _change(key, on))
			box.add_child(cb)
			_controls[key] = cb
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var lb := Label.new()
			lb.text = it[1]
			lb.add_theme_font_size_override("font_size", 15)
			lb.custom_minimum_size.x = 220
			row.add_child(lb)
			var sl := HSlider.new()
			sl.min_value = it[4][0]
			sl.max_value = it[4][1]
			sl.step = it[4][2]
			sl.value = values[key]
			sl.custom_minimum_size.x = 150
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(sl)
			var num := Label.new()
			num.custom_minimum_size.x = 44
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			num.add_theme_font_size_override("font_size", 15)
			num.text = _fmt(key, values[key])
			row.add_child(num)
			sl.value_changed.connect(func(v: float): num.text = _fmt(key, v); _change(key, v))
			sl.drag_started.connect(func(): _dragging = key)
			sl.drag_ended.connect(func(_c: bool): _dragging = ""; _layout())
			box.add_child(row)
			_controls[key] = sl

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	var hint := Label.new()
	hint.text = "Esc で閉じる"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	var close := Button.new()
	close.text = "閉じる"
	close.pressed.connect(func(): set_open(false))
	foot.add_child(close)
	box.add_child(foot)


func _fmt(key: String, v: float) -> String:
	match key:
		"fov": return "%d°" % v
		"cam_dist": return "%.1f m" % v
		"cam_frame": return "%+d%%" % roundi(v * 100)
		"scale", "wind", "ride_fov_amt", "vol_music", "vol_sfx", "vol_voice", "menu_scale", "hud_scale": return "%d%%" % round(v * 100)
		_: return "%.2f" % v


func _change(key: String, v) -> void:
	values[key] = v
	if key == "hud_scale":
		Icons.user_scale = v
	elif key == "menu_scale" and _dragging != key:
		_layout()   # 動かしている最中に拡げると、手の下でスライダーがずれて値が跳ねるので、離してから
	changed.emit(key, v)
	_save()


## メニューの大きさで画面を拡げ、中央に置く。画面の高さに入らなければ、中をスクロールにする
func _layout() -> void:
	if _panel == null or not is_inside_tree():
		return
	var k: float = values["menu_scale"]
	var view := get_viewport().get_visible_rect().size
	var margin := 22.0 * 2.0
	var need := _box.get_combined_minimum_size()
	var fit_h := (view.y - 32.0) / k - margin                 # 拡げたあとで画面に入る中身の高さ
	var bar := 14.0 if need.y > fit_h else 0.0                  # スクロールの棒のぶん
	_scroll.custom_minimum_size = Vector2(need.x + bar, minf(need.y, fit_h))
	_panel.reset_size()
	_panel.size = _panel.get_combined_minimum_size()
	_panel.scale = Vector2(k, k)
	_panel.position = ((view - _panel.size * k) / 2.0).max(Vector2(8, 8))


## 設定の画面が画面の上で占める所（px）。hud.gd の操作の札はこの左に置く
func panel_rect() -> Rect2:
	if _panel == null:
		return Rect2()
	return Rect2(_panel.position, _panel.size * _panel.scale)


## 外から値を変えたとき（キー操作など）に、画面の表示も合わせる
func sync(key: String, v) -> void:
	values[key] = v
	var c = _controls.get(key)
	if c is CheckButton:
		c.set_pressed_no_signal(v)
	elif c is HSlider:
		c.set_value_no_signal(v)
	if key == "hud_scale":
		Icons.user_scale = v
	elif key == "menu_scale":
		_layout()
	_save()


func set_open(on: bool) -> void:
	is_open = on
	_panel.get_parent().visible = on
	if on:
		_layout()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var saved_version: int = cf.get_value("settings", "_version", 1)
	for key in values:
		if saved_version < 3 and key.begins_with("vol_"):
			continue   # 音量の既定を 5% に変えた（版 3）。古い保存の音量は読まない
		values[key] = cf.get_value("settings", key, values[key])


func _save() -> void:
	var cf := ConfigFile.new()
	for key in values:
		cf.set_value("settings", key, values[key])
	cf.set_value("settings", "_version", VERSION)
	cf.save(PATH)
