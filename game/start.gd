extends CanvasLayer

const Icons := preload("res://hud_icons.gd")
const Net := preload("res://net.gd")
## スタート画面。起動の引数がなければ、雪山の上に紙の札を 3 枚吊るして選んでもらう（文字は使わず、絵と数字だけ）。
##   一人: あなたと仲間（CPU）で遊ぶ。この画面を閉じて、そのまま始める
##   ホスト: あなたの所に友達が来る。あなたの番号（Tailscale の 100.x。なければ家の中の番号）を見せ、写せるようにする
##   つなぐ: 友達の番号を打って、その人の所へ行く
## ホスト・つなぐは、世界を作り直して始める（net.gd の boot に入れて、場面を読み直す。仲間を置かずに始めるため）。
## つながらなかった・ホストが帰ったときは、この画面に戻り、つなぐの札に×を縫って見せる

const NET_CFG := "user://net.cfg"   # 前に打った番号
const CARD := Vector2(320, 360)     # 札の大きさ（1080 の高さで）
const GAP := 44.0
const SPIN := 0.035                 # 後ろの雪山を回る速さ (rad/s)

static var done := false            # 一度選んだら、読み直しても出さない
static var force := false           # 設定の「スタート画面へ」から戻った
static var fail := ""               # "join" つながらなかった / "gone" ホストが帰った

var main: Node3D
var _view: Control
var _ip: LineEdit
var _cam: Camera3D
var _t := 0.0
var _hover := ""
var _cards := {}                    # 名前 → 札の Rect2
var _copy_rect := Rect2()
var _go_rect := Rect2()
var _copied := 0.0                  # 写した印を出す残り (s)
var _addr := ""
var _busy := ""                     # 押した札（読み直すまで・つながるまで砂時計）
var waiting := false                # つなぎに行ったところ。つながったら閉じる（つながらなければ net.gd が × にして戻す）


## 出すか: 引数なしで起動したとき（--start で確かめ用に出せる）
static func wanted(args: Dictionary) -> bool:
	return force or (not done and (args.is_empty() or args.has("start")))


func _ready() -> void:
	layer = 8
	_addr = my_address()
	_view = View.new()
	_view.start = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	_ip = LineEdit.new()
	_ip.placeholder_text = "100.0.0.0"
	_ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip.max_length = 40
	_ip.flat = true
	_ip.add_theme_color_override("font_color", Icons.THREAD)
	_ip.add_theme_color_override("font_placeholder_color", Color(Icons.THREAD, 0.3))
	_ip.add_theme_color_override("caret_color", Icons.RED)
	_ip.text = _last_ip()
	_ip.text_submitted.connect(func(_s: String): _join())
	_ip.text_changed.connect(func(_s: String): fail = "")
	add_child(_ip)
	# 後ろの雪山: ゆっくり回るカメラ
	_cam = Camera3D.new()
	_cam.fov = 55
	_cam.cull_mask &= ~(1 << 8)   # 右上の 360° 小窓用の太陽の写し（main.gd の PIP_SUN_LAYER）は映さない
	main.add_child(_cam)
	_cam.make_current()
	_place_cam()
	_hold(true)
	if waiting:
		_busy = "join"
		multiplayer.connected_to_server.connect(_solo)
	get_viewport().size_changed.connect(_layout)
	_layout()


## 遊ぶ人の体と画面の表示を止めて隠す（on）か、戻す
func _hold(on: bool) -> void:
	var p: Node = main.player
	if p:
		p.set_physics_process(not on)
		p.set_process_unhandled_input(not on)
		if not on:
			p.cam.make_current()
	for n in [main.hud, main.craft_ui, main.self_cam, main.get("_pip_layer"), _dial()]:
		if n:
			n.visible = not on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func _dial() -> Control:
	var dc := get_node_or_null("/root/DayCycle")
	return dc.get("_dial") if dc and is_instance_valid(dc.get("_dial")) else null


func _place_cam() -> void:
	var a := 2.2 + _t * SPIN
	var c := Vector3(-8, 6, 40)
	_cam.position = c + Vector3(sin(a), 0, cos(a)) * 34.0 + Vector3(0, 9, 0)
	_cam.look_at(c + Vector3(0, 3, 0))


func _process(dt: float) -> void:
	_t += dt
	if _dial():   # 日時計はあとから置かれる
		_dial().visible = false
	_copied = maxf(0.0, _copied - dt)
	Icons.wind_t += dt
	_place_cam()
	_view.queue_redraw()
	_test_pick()


## 確かめ用: --start-pick=solo|host|join:番号 で、4 秒後にその札を本物のクリックで押す
var _picked := false

var _shot := false

func _test_pick() -> void:
	# 確かめ用: --start-shot=フォルダ で、3 秒後にこの画面を撮る（選ぶ前 pick・つながるのを待つ wait・× の fail）
	if main.args.has("start-shot") and not _shot and _t > 3.0:
		_shot = true
		var kind := "wait" if waiting else ("fail" if fail != "" else "pick")
		get_viewport().get_texture().get_image().save_png("%s/start_%s.png" % [main.args["start-shot"], kind])
	var want := String(main.args.get("start-pick", ""))
	if want == "" or _picked or _t < 4.0 or waiting or done:
		return
	_picked = true
	var at: Vector2 = (_cards.get(want.get_slice(":", 0), Rect2()) as Rect2).get_center()
	if want.begins_with("join:"):
		_ip.text = want.substr(5)
		at = _go_rect.get_center()
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)


func _layout() -> void:
	var vs := _view.get_viewport_rect().size
	var u := Icons.ui_scale(vs.y)
	var size := CARD * u
	var gap := GAP * u
	var w := size.x * 3 + gap * 2
	if w > vs.x - 32.0:   # 狭い画面: 札を縮める
		var k := (vs.x - 32.0) / w
		size *= k
		gap *= k
		u *= k
		w = vs.x - 32.0
	var top := vs.y * 0.5 - size.y * 0.42
	var x := (vs.x - w) / 2.0
	for name in ["solo", "host", "join"]:
		_cards[name] = Rect2(Vector2(x, top), size)
		x += size.x + gap
	var jr: Rect2 = _cards.join
	var field := Rect2(jr.position + Vector2(jr.size.x * 0.07, jr.size.y * 0.72), Vector2(jr.size.x * 0.68, jr.size.y * 0.13))
	_ip.position = field.position
	_ip.size = field.size
	_ip.add_theme_font_size_override("font_size", int(23 * u))
	_go_rect = Rect2(Vector2(field.end.x + jr.size.x * 0.04, field.position.y), Vector2(field.size.y, field.size.y))
	var hr: Rect2 = _cards.host
	_copy_rect = Rect2(Vector2(hr.end.x - hr.size.x * 0.24, hr.position.y + hr.size.y * 0.72), Vector2(field.size.y, field.size.y))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_hover = _hit(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		match _hit(e.position):
			"solo":
				_solo()
			"host":
				_host()
			"copy":
				DisplayServer.clipboard_set(_addr)
				_copied = 1.2
			"go", "join":
				if _ip.text.strip_edges() == "":
					_ip.grab_focus()
				else:
					_join()
		get_viewport().set_input_as_handled()


func _hit(p: Vector2) -> String:
	if _busy != "":
		return ""
	if _copy_rect.has_point(p) and _addr != "":
		return "copy"
	if _go_rect.has_point(p):
		return "go"
	for name in _cards:
		if (_cards[name] as Rect2).has_point(p):
			return name
	return ""


func _solo() -> void:
	if not is_inside_tree():
		return
	done = true
	force = false
	fail = ""
	_hold(false)
	_cam.queue_free()
	queue_free()


func _host() -> void:
	_go({"host": "1"})


func _join() -> void:
	var ip := _ip.text.strip_edges()
	var cf := ConfigFile.new()
	cf.set_value("net", "last", ip)
	cf.save(NET_CFG)
	var a := {"join": ip}
	var parts := ip.rsplit(":", true, 1)   # 「番号:ポート」でも打てる
	if parts.size() == 2 and parts[1].is_valid_int():
		a = {"join": parts[0], "port": parts[1]}
	_go(a)


## 世界を作り直して、ホスト・つなぐで始める
func _go(a: Dictionary) -> void:
	_busy = "host" if a.has("host") else "join"
	done = true
	force = false
	fail = ""
	Net.boot = a
	await get_tree().process_frame   # 砂時計を描いてから
	await get_tree().process_frame
	get_tree().reload_current_scene()


func _last_ip() -> String:
	var cf := ConfigFile.new()
	return String(cf.get_value("net", "last", "")) if cf.load(NET_CFG) == OK else ""


## 友達に教える番号: Tailscale（100.64.0.0/10）があればそれ、なければ家の中の番号
static func my_address() -> String:
	var best := ""
	var rank := 9
	for a in IP.get_local_addresses():
		if a.count(".") != 3:
			continue
		var p := a.split(".")
		var r := 9
		if p[0] == "100" and int(p[1]) >= 64 and int(p[1]) < 128:
			r = 0
		elif p[0] == "192" and p[1] == "168" or p[0] == "10" or p[0] == "172" and int(p[1]) >= 16 and int(p[1]) < 32:
			r = 1
		if r < rank:
			rank = r
			best = a
	return best


# ---- 描く ----------------------------------------------------------------------------

class View extends Control:
	var start

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		start._paint(self)


func _at(c: Vector2, size: float) -> void:
	Icons._o = c
	Icons._s = size / 64.0


func _paint(ci: Control) -> void:
	var vs := ci.size
	var u := (_cards.solo as Rect2).size.y / CARD.y
	# 下のほうを少し暗く（札が雪に溶けないように）
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(Icons.SHADOW, 0.12))
	for name in ["solo", "host", "join"]:
		var r: Rect2 = _cards[name]
		var lift := -8.0 * u if _hover == name or _busy == name else 0.0
		var sway := Icons.wind_angle(r.position.x * 0.01, 0.0, 0.15) * 0.4
		var pin := Vector2(r.get_center().x, r.position.y - 30.0 * u)
		# 吊るす糸
		Icons.screen()
		Icons.thread(ci, PackedVector2Array([pin, r.position + Vector2(r.size.x * 0.5, lift + 2)]), Icons.THREAD, 1.6 * u)
		ci.draw_circle(pin, 4.0 * u, Icons.RED)
		ci.draw_set_transform(pin, sway, Vector2.ONE)
		var rr := Rect2(r.position - pin + Vector2(0, lift), r.size)
		Icons.paper_tag(ci, rr, 26.0 * u, u)
		var c := rr.position + Vector2(rr.size.x * 0.5, rr.size.y * (0.5 if name == "solo" else 0.38))
		var big := rr.size.x * 0.74
		match name:
			"solo":
				_solo_pic(ci, c, big)
			"host":
				_host_pic(ci, c, big)
				if fail == "host":
					_cross(ci, c, big)
				_addr_pic(ci, rr, u)
			"join":
				_join_pic(ci, c, big)
				_field_pic(ci, rr, u)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 入力の欄は、札と一緒に揺れない本物の欄（いま揺れている札の上に重ねる）
	var jr: Rect2 = _cards.join
	var jl := -8.0 * u if _hover == "join" or _busy == "join" else 0.0
	_ip.position.y = jr.position.y + jr.size.y * 0.72 + jl


## 一人: あなたがソリを押し、仲間（CPU）が二人ついて来る
func _solo_pic(ci: Control, c: Vector2, size: float) -> void:
	_at(c, size)
	Icons.sled_side(ci, Vector2(8, 10), 1.0)
	Icons.doll(ci, Vector2(-16, 20), Icons.RED, "push", 1.0, 1.0)
	Icons.doll(ci, Vector2(-30, 26), Icons.NAVY, "walk", 0.85, 0.6)
	Icons.doll(ci, Vector2(26, 26), Icons.MUSTARD, "walk", 0.85, 0.6)


## ホスト: あなたの家の戸が開いていて、友達が歩いて来る
func _host_pic(ci: Control, c: Vector2, size: float) -> void:
	_at(c, size)
	_house(ci, Vector2(-8, 20), true)
	Icons.doll(ci, Vector2(-8, 21), Icons.RED, "stand", 1.0, 0.62)
	Icons.doll(ci, Vector2(18, 26), Icons.NAVY, "walk", 1.0, 0.6)
	Icons.doll(ci, Vector2(30, 26), Icons.MUSTARD, "walk", 1.0, 0.6)


## つなぐ: あなたが友達の家へ歩いて行く
func _join_pic(ci: Control, c: Vector2, size: float) -> void:
	_at(c, size)
	_house(ci, Vector2(12, 20), true)
	Icons.doll(ci, Vector2(-24, 26), Icons.RED, "walk", 1.0, 0.75)
	Icons.thread(ci, PackedVector2Array([Vector2(-14, 4), Vector2(-2, 4)]), Icons.RED, 2.4)
	Icons.chevron(ci, Vector2(-1, 4), 8.0, Icons.RED, 1.0, 0.0, 2.4)
	if fail in ["join", "gone"]:
		_cross(ci, c + Vector2(12, -8) * size / 64.0, size)


## つながらなかった・ホストが帰った・ホストになれなかった: 家に×を縫う
func _cross(ci: Control, c: Vector2, size: float) -> void:
	_at(c, size)
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		Icons.thread(ci, PackedVector2Array([-d * 11.0, d * 11.0]), Icons.RED, 4.0)


## 小さな家（ロッジ）: フェルトの壁と屋根、戸口は暖かい光
func _house(ci: Control, feet: Vector2, open: bool) -> void:
	var wall := PackedVector2Array([feet + Vector2(-17, 0), feet + Vector2(17, 0), feet + Vector2(17, -20), feet + Vector2(-17, -20)])
	Icons.patch(ci, wall, Icons.WOOD.lightened(0.25), 1.0)
	var roof := PackedVector2Array([feet + Vector2(-22, -19), feet + Vector2(22, -19), feet + Vector2(0, -38)])
	Icons.patch(ci, roof, Icons.NAVY, 1.0)
	var door := Icons.rr(feet.x - 6, feet.y - 15, 12, 15, 2)
	Icons.patch(ci, door, Color(1.0, 0.78, 0.38) if open else Icons.WOOD.darkened(0.3), 1.0, false)


## ホストの札の下: あなたの番号と、写すボタン（二枚重ねの紙）
func _addr_pic(ci: Control, rr: Rect2, u: float) -> void:
	Icons.screen()
	var y := rr.position.y + rr.size.y * 0.72
	var h := rr.size.y * 0.13
	var strip := Rect2(Vector2(rr.position.x + rr.size.x * 0.08, y), Vector2(rr.size.x * 0.62, h))
	Icons.dashes(ci, Icons.rr(strip.position.x, strip.position.y, strip.size.x, strip.size.y, 6 * u), Color(Icons.THREAD, 0.5), 1.2 * u, 4 * u, 3 * u, 1.0, true)
	var txt := _addr if _addr != "" else "-"
	var fs := 24.0 * u
	var w := Icons._bold_font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	Icons.stitched_text(ci, txt, Vector2(strip.get_center().x - w / 2.0, strip.get_center().y), fs, Icons.THREAD)
	# 写す: 二枚重ねの紙。写したら緑の糸のチェック
	var cr := Rect2(_copy_rect.position - (_cards.host as Rect2).position + rr.position, _copy_rect.size)
	var s := cr.size.x
	if _busy == "host":   # ホストの世界を作っているあいだは、写すボタンの所に砂時計
		Icons.icon(ci, "hourglass", cr.get_center(), s * 1.5, 1.0)
		return
	for i in 2:
		var o := cr.position + Vector2(s * (0.18 + 0.16 * i), s * (0.14 + 0.16 * i))
		Icons.patch(ci, Icons.rr(o.x, o.y, s * 0.5, s * 0.6, 3 * u), Icons.PAPER if i == 1 else Icons.PAPER_EDGE, 1.0, true, Icons.THREAD)
	if _copied > 0.0:
		var c := cr.get_center()
		Icons.thread(ci, PackedVector2Array([c + Vector2(-s * 0.3, 0), c + Vector2(-s * 0.08, s * 0.22), c + Vector2(s * 0.34, -s * 0.28)]), Color(0.25, 0.6, 0.3), 4.0 * u)
	elif _hover == "copy":
		Icons.dashes(ci, Icons.rr(cr.position.x, cr.position.y, s, s, 6 * u), Icons.RED, 1.4 * u, 4 * u, 3 * u, 1.0, true)


## つなぐの札の下: 番号を打つ欄（破線の枠。中は本物の入力欄）と、行くボタン（フェルトの丸に糸の「＞」）
func _field_pic(ci: Control, rr: Rect2, u: float) -> void:
	Icons.screen()
	var y := rr.position.y + rr.size.y * 0.72
	var h := rr.size.y * 0.13
	var strip := Rect2(Vector2(rr.position.x + rr.size.x * 0.07, y), Vector2(rr.size.x * 0.68, h))
	ci.draw_rect(strip, Color(1, 1, 1, 0.55))
	Icons.dashes(ci, Icons.rr(strip.position.x, strip.position.y, strip.size.x, strip.size.y, 6 * u), Color(Icons.THREAD, 0.7 if _ip.has_focus() else 0.45), 1.4 * u, 4 * u, 3 * u, 1.0, true)
	var gr := Rect2(_go_rect.position - (_cards.join as Rect2).position + rr.position, _go_rect.size)
	var c := gr.get_center()
	if _busy == "join":   # つなぎに行っているあいだは、行くボタンの所に砂時計
		Icons.icon(ci, "hourglass", c, gr.size.x * 1.5, 1.0)
		return
	Icons.patch(ci, Icons.circ(c, gr.size.x * 0.48, 22), Icons.RED if _hover == "go" else Icons.RED.darkened(0.15), 1.0, true, Icons.PAPER)
	Icons.chevron(ci, c + Vector2(2 * u, 0), gr.size.x * 0.22, Icons.PAPER, 1.0, 0.0, 3.0 * u)
