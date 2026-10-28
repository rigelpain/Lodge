extends CanvasLayer
## 設定画面。Esc で開き、マウスで触る。値は user://settings.cfg に保存して次回も効く。
## 項目を足すときは ITEMS に 1 行足し、main.gd の _apply_setting で受ける。

signal changed(key: String, value)

const PATH := "user://settings.cfg"
const VERSION := 3   # 既定値を変えたら上げる。古い保存は、その項目だけ既定に戻す
# [鍵, 見出し, 種類, 既定, 範囲や段]
const ITEMS := [
	["bob", "視点の揺れ（押す・引くとき）", "bool", true, null],
	["fov_kick", "押すときに画角が少し広がる", "bool", true, null],
	["pip", "右上の 360° 映像", "bool", true, null],
	["snow", "舞う雪", "bool", true, null],
	["wind", "風の流れ（滑るとき）", "float", 1.0, [0.0, 1.0, 0.05]],
	["third", "三人称", "bool", false, null],
	["fov", "視野角", "float", 75.0, [50.0, 110.0, 1.0]],
	["sens", "マウスの感度", "float", 1.0, [0.3, 2.5, 0.05]],
	["scale", "3D の描画の解像度（軽さ）", "float", 0.67, [0.4, 1.0, 0.01]],
	["ssao", "くぼみの影（SSAO）", "bool", true, null],
	["shadows", "影", "bool", true, null],
	["vol_music", "音量: 音楽", "float", 0.05, [0.0, 1.0, 0.01]],
	["vol_sfx", "音量: 効果音", "float", 0.05, [0.0, 1.0, 0.01]],
	["vol_voice", "音量: ボイス", "float", 0.05, [0.0, 1.0, 0.01]],
	["hints", "操作の手引き（近づいたときのアイコン）", "bool", true, null],
	["hud_debug", "確かめ用の数字（fps・高さ）", "bool", false, null],
]

var values := {}
var is_open := false
var _panel: PanelContainer
var _controls := {}


func _ready() -> void:
	layer = 5
	for it in ITEMS:
		values[it[0]] = it[3]
	_load()
	_build()
	_panel.get_parent().visible = false


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.86)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(440, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# 画面いっぱいの入れ物の中で中央に置く（大きさが決まってから中央に来る）
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

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
		"scale", "wind", "vol_music", "vol_sfx", "vol_voice": return "%d%%" % (v * 100)
		_: return "%.2f" % v


func _change(key: String, v) -> void:
	values[key] = v
	changed.emit(key, v)
	_save()


## 外から値を変えたとき（キー操作など）に、画面の表示も合わせる
func sync(key: String, v) -> void:
	values[key] = v
	var c = _controls.get(key)
	if c is CheckButton:
		c.set_pressed_no_signal(v)
	elif c is HSlider:
		c.set_value_no_signal(v)
	_save()


func set_open(on: bool) -> void:
	is_open = on
	_panel.get_parent().visible = on
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
