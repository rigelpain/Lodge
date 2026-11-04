extends SceneTree
## 標高の札を 1 枚に並べる（確かめ用）。本物の名札の絵の窓に、本物の部品（フェルト・糸・回るソリの図）で描く。
##   Godot --path game --resolution 1920x560 -s res://tools/elev_tag_sheet.gd -- --out=/path/sheet.png
## 上の段が 1080 の高さの画面の大きさ、下の段がスマホの縦画面の大きさ。山は、地形ができるまで仮の断面

const SledTags := preload("res://sled_tags.gd")
const Icons := preload("res://hud_icons.gd")
const Areas := preload("res://areas.gd")
const Card := preload("res://elev_card.gd")
const MainScript := preload("res://main.gd")

const TAG_K := 1.365
const COLS := [["hill", "丘", 34.0], ["slope", "大斜面", 170.0], ["peak", "山", 260.0], ["lodge", "ロッジのまわり", 30.0]]

var args := {}
var view: Control


## 倍の山の地形ができるまでの、札の絵のための仮の断面（高さ 140 m、途中に平らな段）
static func fake_peak(r: float) -> float:
	var x := absf(r)
	if r < 0.0:
		return 140.0 * pow(clampf(1.0 - x / 130.0, 0.0, 1.0), 1.1)
	var body := 140.0 * pow(clampf(1.0 - x / 560.0, 0.0, 1.0), 1.15)
	var flat := 62.0 + 0.012 * (250.0 - x)
	var w := smoothstep(205.0, 235.0, x) * (1.0 - smoothstep(270.0, 300.0, x))
	return lerpf(body, flat, w)


class View extends Control:
	var sheet
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.87, 0.85, 0.80))
		sheet.paint(self)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Areas.extra["peak"] = {"top": Vector2(0, 0), "dir": Vector2(0, 1), "rx": 150.0, "rn": 560.0, "rs": 130.0, "back": 120.0, "foot": 560.0, "tall": 1.0, "profile": fake_peak}
	view = View.new()
	view.sheet = self
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	root.add_child(view)
	_run.call_deferred()


func _run() -> void:
	for i in 60:
		await process_frame
	view.queue_redraw()
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(args.get("out", "/tmp/elev_tags.png"))
	quit()


func paint(c: Control) -> void:
	var font := Icons._bold_font()
	var big := 1.0
	var small := 0.78
	for k in COLS.size():
		var x := 24.0 + k * 476.0
		c.draw_string(font, Vector2(x + 30.0, 34.0), COLS[k][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Icons.THREAD)
		_card(c, Rect2(Vector2(x, 50.0), Vector2(262.0, 146.0) * big * TAG_K), COLS[k][0], COLS[k][2], big)
		_card(c, Rect2(Vector2(x, 280.0), Vector2(262.0, 146.0) * small * TAG_K), COLS[k][0], COLS[k][2], small)


func _card(c: Control, r: Rect2, id: String, mark: float, u0: float) -> void:
	var u := u0 * TAG_K
	var sh := PackedVector2Array()
	for q in SledTags.outline(r, SledTags.design(0).shape):
		sh.append(q + Vector2(1.2, 2.2) * u)
	c.draw_colored_polygon(sh, Color(Icons.SHADOW, 0.3))
	var win := SledTags.draw_tag(c, r, 0, 1.0, false, true)
	var fw := 210.0 * u
	var fh := 120.0 * u
	var k := minf(minf(win.size.x / fw, win.size.y / fh), 1.06)
	c.draw_set_transform(win.get_center() - Vector2(fw, fh) * k / 2.0, 0.0, Vector2(k, k))
	var mark_at := func(mc: Vector2, slope: float, ks: float) -> void:
		c.draw_circle(mc, 8.5 * u * ks, Color(1, 1, 1, 0.8))
		Icons._o = mc
		Icons._s = 0.4 * u * ks
		Icons.sled_side(c, Vector2.ZERO, 1.0, 1.0, slope, true)
		Icons.screen()
	Card.draw(c, id, u, 1.0, fw, MainScript.height, mark, mark_at)
	var tw := Rect2(Vector2(4.0, 46.0) * u, Vector2(150.0, 71.0) * u)
	Icons.screen()
	Icons.patch(c, Icons.rr(tw.position.x, tw.position.y, tw.size.x, tw.size.y, 8.0 * u), Color(0.86, 0.90, 0.97), 1.0, true, Icons.THREAD)
	var ar := float(SledTags.WIDE_SIZE.x) / SledTags.WIDE_SIZE.y
	var ih := tw.size.y - 3.0 * u
	c.draw_texture_rect(SledTags.turntable_wide("mid", "red", []), Rect2(tw.get_center() - Vector2(ih * ar, ih) / 2.0, Vector2(ih * ar, ih)), false)
	var ow := Rect2(Vector2(158.0, 46.0) * u, Vector2(fw - 160.0 * u, 71.0 * u))
	var ph := ow.size.y * 0.82
	var pw := ph * SledTags.PERSON_SIZE.x / SledTags.PERSON_SIZE.y
	c.draw_texture_rect(SledTags.person_portrait(Icons.RED), Rect2(Vector2(ow.get_center().x - pw / 2.0, ow.end.y - ph), Vector2(pw, ph)), false)
	c.draw_set_transform(Vector2.ZERO)
	Icons.screen()
