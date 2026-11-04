extends CanvasLayer
## 服を染める画面（1 階の人台の桶を見下ろして F）。文字は使わない（2026-11-01 代表「服の色変えもできるようにしたい」）。
##   左: 紙の札の中で、いま着ている人形が 12 コマでゆっくり回る。選んでいる色がその場で服に染まる（見本。まだ払っていない）。
##   右上: 染める部位の見本 4 枚（主の色・2 番目・3 番目・4 番目。outfit.gd の PARTS）。押した部位を染める。見本の右下の折り返しが、もとの色。
##       選んでいる部位（見本に乗っている間はその部位）は、札の中の人形の上で輪郭を縁取り、少し光らせて点滅させる。ほかの部位はもとの色のまま
##       （どこを染めるかを、文字でなく人形の上で指す。2026-11-04 代表「他の部位の色を褪せさせるんじゃなくて、輪郭を表示して少し光で点滅させる」）
##   右: 色の輪（まわりで色合い、外ほど鮮やか）と、明るさの帯。色は自由に選べる（2026-11-01 代表「自由に選ぶ」）。
##   見本の下の小さな丸い布は、その部位の「脱色」（もとの色に戻す）。もとの色の布に戻る矢印。染めてある部位だけ押せる
##       （2026-11-03 代表「デフォルトカラーに戻す脱色を各部位でできるようにしてほしい」）。脱色はただ（代表「脱色はただに」）
##   右下: 染める札（桶の絵と、染め代のボタン）。色ではなく 1 回ごとに染め代を払う。染め代は、別の色に染める部位の数で上がる（craft.gd の
##       DYE_PRICES。脱色だけなら値段なし。桶の下に、変える部位の新しい色の小さな布が並ぶ）。何も変えていなければ押せない。足りなければ値段が赤い。
##       染めると、みんなの画面でその人の人形が染まる（craft.gd の出来事 dye）
##   閉じるのは右上の × の縫い目か、F か Esc。Tab で部位を替え、←→ で色合い、↑↓ で明るさ、Backspace で脱色、Enter で染める

const Doll := preload("res://doll.gd")
const Outfit := preload("res://outfit.gd")
const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")

const SHOT := Vector2i(300, 420)   # 札の中の絵の大きさ (px)
const RINGS := 6             # 色の輪の、外へ向かう段の数
const SEGS := 48             # 色の輪の、まわりの分け数
const V_MIN := 0.12          # 明るさの帯のいちばん暗い所
const BLINK := 1.3           # 輪郭の内側の微光が 1 回点滅する秒。動きはなめらか（art-concept: 12 コマは人の姿勢だけ）
const RING_CORE := 2.6       # 輪郭の芯（生成りの糸）の太さ (u)
const RING_EDGE := 1.5       # 芯の外側の、墨の縁の太さ (u)
const GLOW_R := 26.0         # 微光が輪郭から内側へ届く幅 (u)

var main: Node3D
var craft: Node
var player: Node3D
var is_open := false
var _view: Control
var _kind := "kasa"
var _pick: Array = []        # 部位ごとの、選んでいる色（Color か null = もとの色）
var _cloth := 0              # 染める部位の番号
var _on := 0                 # 輪郭と光を出している部位
var _blink := 0.0            # 点滅の時計（秒。0 が光のいちばん強い所）
var _hsv := Vector3(0, 0.5, 0.5)   # いまの布の色（色合い・鮮やかさ・明るさ）
var _drag := ""              # "wheel" か "value" を引いている
var _shot: SubViewport
var _spin: Node3D
var _mat: ShaderMaterial
var _part_shot: SubViewport  # 部位の型紙を撮る（見本と同じ形・同じカメラ。outfit.gd の part_material）
var _part_spin: Node3D
var _part_mat: ShaderMaterial
var _shape_shader: Shader
var _shape_shots: Array[SubViewport] = []   # 型紙の、糸のように細かい所をひとかたまりにする 2 段（広げて、削り戻す）。輪郭は後の絵の外まわり
var _ring: Ring              # 見本の絵に輪郭と光を重ねて描く
var _frame := -1
var _pop := 0.0              # 染めたときに札が跳ねる
var _hover := ""
# 描いたときに決まる所（画面の px）
var _wheel_c := Vector2.ZERO
var _wheel_r := 1.0
var _value_rect := Rect2()
var _swatches: Array[Rect2] = []
var _bleaches: Array[Rect2] = []   # 見本の下の、部位ごとの脱色の布
var _dye_rect := Rect2()
var _close_rect := Rect2()
var _shot_rect := Rect2()


class View:
	extends Control
	var ui

	func _draw() -> void:
		if ui.is_open:
			ui._draw_on(self)


## 札の中の見本の絵。RING_SHADER を通して、部位の輪郭と微光を重ねる（板や札の絵は View が先に描く）
class Ring:
	extends Control
	var ui

	func _draw() -> void:
		if ui.is_open and ui._shot:
			draw_texture_rect(ui._shot.get_texture(), ui._shot_rect, false)


func _ready() -> void:
	layer = 4
	_view = View.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_ring = Ring.new()
	_ring.ui = self
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = RING_SHADER
	_ring.material = sm
	_view.add_child(_ring)
	_shape_shader = Shader.new()
	_shape_shader.code = SHAPE_SHADER


func open() -> void:
	if is_open or player == null or player.menu_open or craft == null:
		return
	is_open = true
	_kind = player.doll.kind
	_pick = craft.outfit_of(int(player.get("id")), _kind)
	_pick.resize(Outfit.cloth_count(_kind))
	_cloth = 0
	_on = 0
	_blink = 0.0
	_take_hsv()
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)
	_make_shot()
	var hud = main.get("hud") if main else null
	if hud:
		hud.learn("dye")   # 開けたら、F の案内はもう出さない
	_view.queue_redraw()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_drag = ""
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)
	if _shot:
		Outfit.strip(_spin)   # 見本の材質を先に外す（outfit.gd の strip）
		_shot.queue_free()
		_shot = null
		_mat = null
		Outfit.strip(_part_spin)
		_part_shot.queue_free()
		_part_shot = null
		_part_mat = null
		for v in _shape_shots:
			v.queue_free()
		_shape_shots.clear()
	_view.queue_redraw()
	_ring.queue_redraw()


## いま選んでいる布の色を、輪と帯の所に読む（もとの色なら、もとの色の所）
func _take_hsv() -> void:
	var c: Color = _pick[_cloth] if _pick[_cloth] is Color else Outfit.base_color(_kind, _cloth)
	_hsv = Vector3(c.h, c.s, c.v)


## 輪と帯の所から、いまの布の色を決める
func _set_from_hsv() -> void:
	_pick[_cloth] = Color.from_hsv(_hsv.x, _hsv.y, _hsv.z)
	_show_pick()


func _show_pick() -> void:
	if _mat:
		Outfit.set_params(_mat, _kind, _pick)


## いまの色から変える部位（番号の並び）。空なら染められない
func _changed() -> Array:
	var now: Array = craft.dye_colors(_kind, _pick)
	var old: Array = craft.dye_colors(_kind, craft.outfit_of(int(player.get("id")), _kind))
	var out := []
	for i in now.size():
		if now[i] != old[i]:
			out.append(i)
	return out


## 染め代（別の色に染める部位の数で決まる。脱色だけなら 0）
func _price() -> int:
	return craft.dye_price(craft.dye_colors(_kind, _pick), craft.dye_colors(_kind, craft.outfit_of(int(player.get("id")), _kind)))


func _can_pay() -> bool:
	return craft.wallet(int(player.get("id"))) >= _price()


## 染める（出来事を送る。染まるのは配られてから）
func dye() -> void:
	if _changed().is_empty() or not _can_pay():
		return
	if craft.send({"kind": "dye", "who": int(player.get("id")), "doll": _kind, "colors": craft.dye_colors(_kind, _pick)}):
		_pop = 1.0
		if player.has_method("save_tag"):
			player.save_tag()   # 次に起動しても同じ色


# ---------------------------------------------------------------- 札の中で回る人形（見本）

func _make_shot() -> void:
	_shot = SubViewport.new()
	_shot.size = SHOT
	_shot.transparent_bg = true
	_shot.own_world_3d = true
	_shot.msaa_3d = Viewport.MSAA_4X
	_shot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_shot)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.86, 0.95)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_shot.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.3
	_shot.add_child(sun)
	_spin = Node3D.new()
	_shot.add_child(_spin)
	var inst: Node3D = (load(Doll.SCENES[_kind]) as PackedScene).instantiate()
	_spin.add_child(inst)
	_spin.rotation.y = 0.5
	_mat = Outfit.preview_material(inst)
	_show_pick()
	var h: float = Doll.TOP[_kind]
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h * 1.12
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # 札の中のカメラは動かない
	_shot.add_child(cam)
	cam.look_at_from_position(Vector3(0, h * 0.5, 6.0), Vector3(0, h * 0.5, 0))
	_make_part_shot(cam)


## 部位の型紙を撮る: 同じ人形をもう 1 体、同じカメラの位置から撮る。前にある部位の陰になる所は、輪郭も出ない
func _make_part_shot(cam: Camera3D) -> void:
	_part_shot = SubViewport.new()
	_part_shot.size = SHOT * 2   # 札いっぱいに引き伸ばしても輪郭がギザギザにならないように
	_part_shot.transparent_bg = true
	_part_shot.own_world_3d = true
	_part_shot.msaa_3d = Viewport.MSAA_4X
	_part_shot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_part_shot)
	_part_spin = Node3D.new()
	_part_shot.add_child(_part_spin)
	var inst: Node3D = (load(Doll.SCENES[_kind]) as PackedScene).instantiate()
	_part_spin.add_child(inst)
	_part_mat = Outfit.part_material(inst, _kind)
	var c := Camera3D.new()
	c.projection = cam.projection
	c.size = cam.size
	c.keep_aspect = cam.keep_aspect
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_part_shot.add_child(c)
	c.global_transform = cam.global_transform
	_ring.material.set_shader_parameter("shape_tex", _shape_pass(_shape_pass(_part_shot, true), false).get_texture())


func _process(dt: float) -> void:
	if not is_open:
		return
	_pop = maxf(0.0, _pop - dt * 2.5)
	_blink += dt
	_show_part()
	var f := Doll.frame_index()
	if f != _frame and _spin:   # 12 コマでゆっくり回す
		_frame = f
		_spin.rotation.y += 0.05
	if _part_spin:
		_part_spin.rotation.y = _spin.rotation.y
	_view.queue_redraw()
	_ring.queue_redraw()


## 型紙を 1 段、広げるか（grow）削るかした絵を撮る
func _shape_pass(from: SubViewport, grow: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = SHOT   # 型紙の半分の大きさで見る（ちりのように細かい点は消え、見る手間も 4 分の 1）
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_shape_shots.append(vp)
	var rect := TextureRect.new()
	rect.texture = from.get_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = SHOT
	var sm := ShaderMaterial.new()
	sm.shader = _shape_shader
	sm.set_shader_parameter("grow", grow)
	sm.set_shader_parameter("px", Vector2.ONE / Vector2(SHOT))
	rect.material = sm
	vp.add_child(rect)
	return vp


## 選んでいる部位か、見本に乗っている部位に、輪郭と微光を出す。替わったら光の強い所から始める
func _show_part() -> void:
	var on := _cloth
	for pre in ["swatch", "bleach"]:
		if _hover.begins_with(pre):
			on = int(_hover.trim_prefix(pre))
	if on != _on:
		_on = on
		_blink = 0.0
	if _part_mat:
		_part_mat.set_shader_parameter("part", _on)
	_ring.material.set_shader_parameter("pulse", 0.5 + 0.5 * cos(_blink * TAU / BLINK))


# ---------------------------------------------------------------- 描く

func _draw_on(ci: Control) -> void:
	var vs := ci.size
	var u := Icons.ui_scale(vs.y)
	var bw := minf(960.0 * u, vs.x - 60.0 * u)
	var bh := minf(600.0 * u, vs.y - 60.0 * u)
	var r := Rect2((vs - Vector2(bw, bh)) / 2.0, Vector2(bw, bh))
	_board(ci, r, u)
	# 左: 見本の札
	var lift := sin(_pop * PI) * 16.0 * u
	var ch := bh - 70.0 * u
	var cw := ch * float(SHOT.x) / SHOT.y
	var card := Rect2(r.position + Vector2(36.0 * u, 36.0 * u - lift), Vector2(cw, ch))
	Icons.paper_tag(ci, card, 18.0 * u, u)
	_shot_rect = card.grow(-10.0 * u)   # 見本の絵は _ring が描く
	_ring.material.set_shader_parameter("px", Vector2.ONE / _shot_rect.size)
	_ring.material.set_shader_parameter("core", RING_CORE * maxf(u, 0.75))
	_ring.material.set_shader_parameter("edge", RING_EDGE * maxf(u, 0.75))
	_ring.material.set_shader_parameter("glow_r", GLOW_R * maxf(u, 0.75))
	# 右上: 部位の見本
	var rx := card.end.x + 48.0 * u
	var n := _pick.size()
	var sw := 74.0 * u
	var bs := 30.0 * u
	_swatches.clear()
	_bleaches.clear()
	for i in n:
		var sr := Rect2(Vector2(rx + i * (sw + 26.0 * u), r.position.y + 34.0 * u), Vector2(sw, sw))
		_swatches.append(sr)
		_swatch(ci, sr, i, u)
		var br := Rect2(Vector2(sr.get_center().x - bs / 2.0, sr.end.y + 8.0 * u), Vector2(bs, bs))
		_bleaches.append(br)
		_bleach(ci, br, i, u)
	# 右: 色の輪と明るさの帯
	_wheel_r = minf(150.0 * u, (r.end.y - (r.position.y + 150.0 * u) - 40.0 * u) / 2.0)
	_wheel_c = Vector2(rx + _wheel_r + 4.0 * u, r.position.y + 150.0 * u + _wheel_r)
	_wheel(ci, u)
	_value_rect = Rect2(Vector2(_wheel_c.x + _wheel_r + 34.0 * u, _wheel_c.y - _wheel_r), Vector2(30.0 * u, _wheel_r * 2.0))
	_value(ci, u)
	# 右下: 染める札（桶の絵と染め代）
	var dw := 150.0 * u
	var dh := 200.0 * u
	_dye_rect = Rect2(Vector2(r.end.x - dw - 40.0 * u, r.end.y - dh - 40.0 * u), Vector2(dw, dh))
	_dye_card(ci, u)
	# 右上: 閉じる（× の縫い目）
	var xs := 46.0 * u
	var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
	_close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
	Icons.screen()
	Icons.patch(ci, Icons.circ(xc, xs * 0.5 * (1.08 if _hover == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
	Icons._o = xc
	Icons._s = xs / 64.0
	Icons.thread(ci, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
	Icons.thread(ci, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)


## 部位の見本: 選んだ色のフェルト。右下の角を折り返して、裏にもとの色。染める部位は赤い糸で囲む
func _swatch(ci: CanvasItem, sr: Rect2, i: int, u: float) -> void:
	var base := Outfit.base_color(_kind, i)
	var c: Color = _pick[i] if _pick[i] is Color else base
	var fold := sr.size.x * 0.34
	Icons.screen()
	Icons.patch(ci, PackedVector2Array([sr.position, Vector2(sr.end.x, sr.position.y), Vector2(sr.end.x, sr.end.y - fold),
		Vector2(sr.end.x - fold, sr.end.y), Vector2(sr.position.x, sr.end.y)]), c, 1.0, true)
	Icons.patch(ci, PackedVector2Array([Vector2(sr.end.x, sr.end.y - fold), Vector2(sr.end.x - fold, sr.end.y - fold), Vector2(sr.end.x - fold, sr.end.y)]),
		base, 1.0, false)
	if i == _cloth or _hover == "swatch%d" % i:
		Icons.dashes(ci, Icons.rr(sr.position.x - 7.0 * u, sr.position.y - 7.0 * u, sr.size.x + 14.0 * u, sr.size.y + 14.0 * u, 8.0 * u),
			Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 1.0 if i == _cloth else 0.4, true)


## 色の輪: まわりで色合い、外ほど鮮やか（明るさは帯の値）。フェルトの毛羽を重ねる。いまの色の所に糸の輪
func _wheel(ci: CanvasItem, u: float) -> void:
	var felt := Icons.felt()
	Icons.screen()
	ci.draw_colored_polygon(Icons.circ(_wheel_c + Vector2(2, 3) * u, _wheel_r + 3.0 * u, 48), Color(Icons.SHADOW, 0.3))
	for ri in RINGS:
		var s0 := float(ri) / RINGS
		var s1 := float(ri + 1) / RINGS
		for k in SEGS:
			var a0 := TAU * k / SEGS
			var a1 := TAU * (k + 1) / SEGS
			var pts := PackedVector2Array([_polar(a0, s0), _polar(a0, s1), _polar(a1, s1), _polar(a1, s0)])
			var cols := PackedColorArray([_wheel_col(a0, s0), _wheel_col(a0, s1), _wheel_col(a1, s1), _wheel_col(a1, s0)])
			var uv := PackedVector2Array()
			for p in pts:
				uv.append(p / (40.0 * u))
			ci.draw_polygon(pts, cols, uv, felt)
	Icons.dashes(ci, Icons.circ(_wheel_c, _wheel_r - 5.0 * u, 48), Color(Icons.CAP, 0.7), 1.6 * u, 6.0 * u, 4.0 * u, 1.0, true)
	var at := _polar(_hsv.x * TAU, _hsv.y)
	ci.draw_circle(at, 11.0 * u, Color(Icons.SHADOW, 0.3))
	ci.draw_circle(at, 10.0 * u, Color.from_hsv(_hsv.x, _hsv.y, _hsv.z))
	ci.draw_arc(at, 10.0 * u, 0, TAU, 20, Icons.CAP, 3.0 * u, true)
	ci.draw_arc(at, 13.0 * u, 0, TAU, 20, Icons.THREAD, 1.6 * u, true)


func _polar(a: float, s: float) -> Vector2:
	return _wheel_c + Vector2(cos(a), -sin(a)) * s * _wheel_r


func _wheel_col(a: float, s: float) -> Color:
	return Color.from_hsv(a / TAU, s, _hsv.z)


## 明るさの帯: 上ほど明るい。いまの色合いと鮮やかさで。いまの明るさの所に赤い糸の結び目
func _value(ci: CanvasItem, u: float) -> void:
	var r := _value_rect
	Icons.screen()
	ci.draw_rect(Rect2(r.position + Vector2(2, 3) * u, r.size), Color(Icons.SHADOW, 0.3))
	var top := Color.from_hsv(_hsv.x, _hsv.y, 1.0)
	var bot := Color.from_hsv(_hsv.x, _hsv.y, V_MIN)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / (40.0 * u))
	ci.draw_polygon(pts, PackedColorArray([top, top, bot, bot]), uv, Icons.felt())
	ci.draw_rect(r, Color(Icons.THREAD, 0.6), false, 1.2 * u)
	var y := r.end.y - (_hsv.z - V_MIN) / (1.0 - V_MIN) * r.size.y
	Icons.dashes(ci, PackedVector2Array([Vector2(r.position.x - 8.0 * u, y), Vector2(r.end.x + 8.0 * u, y)]), Icons.RED, 3.0 * u, 7.0 * u, 3.0 * u, 1.0)
	ci.draw_circle(Vector2(r.end.x + 10.0 * u, y), 5.5 * u, Icons.RED)


## 部位 i の脱色（もとの色に戻す）: もとの色の小さな丸い布と、戻る矢印。染めてある（選んでいる色がある）ときだけ濃い
func _bleach(ci: CanvasItem, sr: Rect2, i: int, u: float) -> void:
	var a := 1.0 if _pick[i] is Color else 0.3
	Icons.screen()
	var grow := 1.12 if _hover == "bleach%d" % i and a > 0.5 else 1.0
	var c := sr.get_center()
	Icons.patch(ci, Icons.circ(c, sr.size.x * 0.5 * grow, 18), Outfit.base_color(_kind, i), a, true)
	Icons.arc_arrow(ci, c, sr.size.x * 0.3, PI * 0.15, PI * 1.55, Icons.CAP, a, 2.4 * u)


## 部位 i を脱色する（もとの色に戻す。染めるのは桶の札を押してから）
func bleach(i: int) -> void:
	if i < 0 or i >= _pick.size():
		return
	_cloth = i
	_pick[i] = null
	_take_hsv()
	_show_pick()


## 染める札: 紙の札に、桶の絵（布はいま選んだ色）と、変える部位の新しい色の小さな布の並び（数が多いほど染め代が上がる）と、
## 染め代のボタン。押せないときは薄く、足りないときは値段が赤い
func _dye_card(ci: CanvasItem, u: float) -> void:
	var ch := _changed()
	var ok := not ch.is_empty() and _can_pay()
	var a := 1.0 if ok else 0.45
	var r := _dye_rect
	if _hover == "dye" and ok:
		r = r.grow(4.0 * u)
	Icons.paper_tag(ci, r, 14.0 * u, u)
	var c: Color = _pick[_cloth] if _pick[_cloth] is Color else Outfit.base_color(_kind, _cloth)
	Icons.icon(ci, "dye", r.position + Vector2(r.size.x / 2.0, r.size.y * 0.27), 74.0 * u, a, c)
	Icons.screen()
	var dot := 9.0 * u
	for j in ch.size():   # 変える部位ごとに、新しい色の小さな丸い布（もとの色に戻す部位は、もとの色）
		var i: int = ch[j]
		var at := r.position + Vector2(r.size.x / 2.0 + (j - (ch.size() - 1) * 0.5) * dot * 2.6, r.size.y * 0.52)
		Icons.patch(ci, Icons.circ(at, dot, 12), _pick[i] if _pick[i] is Color else Outfit.base_color(_kind, i), a, true)
	CraftIcons.price(ci, r.position + Vector2(r.size.x / 2.0, r.size.y * 0.78), _price() if not ch.is_empty() else craft.DYE_PRICES[1], 10.0 * u, a,
		Icons.RED if not _can_pay() else CraftIcons.COIN)
	if ok:
		Icons.dashes(ci, Icons.rr(r.position.x - 6.0 * u, r.position.y - 6.0 * u, r.size.x + 12.0 * u, r.size.y + 12.0 * u, 10.0 * u),
			Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 0.8, true)


## 濃い紫のフェルトの板と、縁のなみ縫い（衣装掛けの画面と同じ形。染め物の色）
func _board(ci: CanvasItem, r: Rect2, u: float) -> void:
	Icons.screen()
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / 40.0)
	ci.draw_colored_polygon(pts, Color(0.36, 0.30, 0.40), uv, Icons.felt())
	var inset := Rect2(r.position + Vector2(14, 14) * u, r.size - Vector2(28, 28) * u)
	Icons.dashes(ci, PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]),
			Icons.CAP, 2.4 * u, 9.0 * u, 6.0 * u, 0.8, true)


# ---------------------------------------------------------------- 押す・引く

func _hit(p: Vector2) -> String:
	if _close_rect.has_point(p):
		return "close"
	if _dye_rect.has_point(p):
		return "dye"
	for i in _bleaches.size():
		if _bleaches[i].grow(4.0).has_point(p):
			return "bleach%d" % i
	for i in _swatches.size():
		if _swatches[i].has_point(p):
			return "swatch%d" % i
	if p.distance_to(_wheel_c) <= _wheel_r + 4.0:
		return "wheel"
	if _value_rect.grow(8.0).has_point(p):
		return "value"
	return ""


func _drag_to(p: Vector2) -> void:
	if _drag == "wheel":
		var d := p - _wheel_c
		_hsv.x = fposmod(atan2(-d.y, d.x) / TAU, 1.0)
		_hsv.y = clampf(d.length() / _wheel_r, 0.0, 1.0)
		_set_from_hsv()
	elif _drag == "value":
		_hsv.z = clampf(V_MIN + (_value_rect.end.y - p.y) / _value_rect.size.y * (1.0 - V_MIN), V_MIN, 1.0)
		_set_from_hsv()


func _input(e: InputEvent) -> void:
	if not is_open:
		return
	if e is InputEventKey and e.pressed:
		match e.physical_keycode:
			KEY_ESCAPE, KEY_F:
				if not e.echo:
					close()
			KEY_TAB:
				if not e.echo and _pick.size() > 1:
					_cloth = (_cloth + 1) % _pick.size()
					_take_hsv()
			KEY_A, KEY_LEFT:
				_hsv.x = fposmod(_hsv.x - 1.0 / SEGS, 1.0)
				_set_from_hsv()
			KEY_D, KEY_RIGHT:
				_hsv.x = fposmod(_hsv.x + 1.0 / SEGS, 1.0)
				_set_from_hsv()
			KEY_W, KEY_UP:
				_hsv.z = minf(1.0, _hsv.z + 0.05)
				_set_from_hsv()
			KEY_S, KEY_DOWN:
				_hsv.z = maxf(V_MIN, _hsv.z - 0.05)
				_set_from_hsv()
			KEY_BACKSPACE, KEY_DELETE:
				if not e.echo:
					bleach(_cloth)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if not e.echo:
					dye()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		if _drag != "":
			_drag_to(e.position)
		else:
			_hover = _hit(e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if not e.pressed:
			_drag = ""
			return
		var h := _hit(e.position)
		match h:
			"close":
				close()
			"dye":
				dye()
			"wheel", "value":
				_drag = h
				_drag_to(e.position)
			_:
				if h.begins_with("swatch"):
					_cloth = int(h.trim_prefix("swatch"))
					_take_hsv()
				elif h.begins_with("bleach"):
					bleach(int(h.trim_prefix("bleach")))


# ---------------------------------------------------------------- 輪郭と微光

## 部位の型紙の、細かい所をひとかたまりにする。musha の縅の糸のように、細い線が狭いすき間で並ぶ所を 1 本ずつ縁取ると針金のようになるので、
## 広げてから同じだけ削り戻して、狭いすき間だけを埋める（大きな布の縁はずれず、離れた細い部位は細いまま）
const SHAPE_SHADER := """
shader_type canvas_item;
render_mode blend_disabled;

uniform bool grow = true;
uniform vec2 px = vec2(0.003);   // SHOT の 1 px が、絵の UV でいくつか
const float R = 8.0;       // 広げる・削る幅（SHOT の px）。これの 2 倍より狭いすき間が埋まる

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float m = t.r * t.a;
	float dir = grow ? 1.0 : -1.0;   // 削るときは逆向きに見る（削り戻しても、もとの形より小さくならない）
	for (int i = 0; i < 64; i++) {   // 円の中をむらなく見る（ひまわりの種の並び）。輪だけを見ると、細い糸のまわりに小さな輪が残る
		float a = float(i) * 2.3999632;
		float r = R * sqrt((float(i) + 0.5) / 64.0);
		vec4 s = texture(TEXTURE, UV + dir * vec2(cos(a), sin(a)) * r * px);
		m = grow ? max(m, s.r * s.a) : min(m, s.r * s.a);
	}
	COLOR = vec4(vec3(m), 1.0);
}
"""

## 見本の絵に、部位の型紙から輪郭と微光を重ねる。外から順に: 墨の縁（生成りの札の上で読める）、生成りの糸の芯（濃い布の上で読める）、輪郭の内側。
## 輪郭は外側に出して点滅させず、内側だけを微光で点滅させる。微光は輪郭のすぐ内側で強く、中へ行くほど薄い（範囲じゅう同じ強さにすると、布の色が替わったように見える）。
## 暗い布は色合いのまま明るく（灯りの色を混ぜると灰色に褪せて見える）、もう明るくできない白い布は、陰を残したまま灯りの色に少し染める
const RING_SHADER := """
shader_type canvas_item;

uniform sampler2D shape_tex : filter_linear, repeat_disable;   // 細かい所をひとかたまりにした部位（輪郭の内側。微光もここに出す）
uniform vec2 px = vec2(0.003);    // 画面の 1 px が、絵の UV でいくつか
uniform float core = 2.6;         // 芯の太さ (px)
uniform float edge = 1.5;         // 墨の縁の太さ (px)
uniform float pulse = 0.0;        // 光の強さ 0〜1
uniform float glow_r = 26.0;      // 縁の光が中へ届く幅 (px)

const vec3 CORE_COL = vec3(0.98, 0.96, 0.92);
const vec3 EDGE_COL = vec3(0.10, 0.08, 0.16);
const vec3 LIGHT_COL = vec3(1.0, 0.86, 0.60);
const float GLOW_MID = 0.35;      // 範囲のまん中の光（縁を 1 として）

// 半径 r の円の中に部位があるか（0〜1）
float near(vec2 uv, float r) {
	float m = texture(shape_tex, uv).r;
	for (int i = 0; i < 16; i++) {
		float a = float(i) * 0.3926991;
		vec2 d = vec2(cos(a), sin(a)) * px * r;
		m = max(m, texture(shape_tex, uv + d).r);
		m = max(m, texture(shape_tex, uv + d * 0.5).r);
	}
	return m;
}

// 輪郭のすぐ内側で強く、中へ行くほど薄くなる光の量（0〜1）。まわりに範囲の外が多いほど、縁に近い
float veil(vec2 uv, float shape) {
	float cover = 0.0;
	for (int i = 0; i < 32; i++) {   // 円の中をむらなく見る（ひまわりの種の並び）
		float a = float(i) * 2.3999632;
		cover += texture(shape_tex, uv + vec2(cos(a), sin(a)) * px * glow_r * sqrt((float(i) + 0.5) / 32.0)).r;
	}
	float near_edge = smoothstep(0.0, 0.5, 1.0 - cover / 32.0);
	return shape * mix(GLOW_MID, 1.0, near_edge);
}

// 暗い布は色合いのまま明るく、もう明るくできない白い布は陰を残したまま灯りの色に染める
vec3 lit(vec3 c, float g) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float white = smoothstep(0.62, 0.92, l);
	vec3 up = min(c * (1.0 + 0.30 * g * (1.0 - white)), vec3(1.0));
	vec3 tone = mix(LIGHT_COL, c / max(max(c.r, max(c.g, c.b)), 0.05), 0.6);   // 足す光は布の色寄りに（紺が灰色に褪せない）
	up += (vec3(1.0) - up) * tone * 0.20 * g;
	return up * mix(vec3(1.0), LIGHT_COL, 0.45 * g * white);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float shape = smoothstep(0.35, 0.65, texture(shape_tex, UV).r);
	float a_core = smoothstep(0.35, 0.65, near(UV, core)) * (1.0 - shape);
	float a_edge = smoothstep(0.35, 0.65, near(UV, core + edge)) * (1.0 - shape);
	float g = veil(UV, shape) * pulse;
	vec3 col = mix(c.rgb, EDGE_COL, a_edge);
	col = mix(col, CORE_COL, a_core);
	// 範囲の中: 布の上は lit、布のない狭いすき間には灯りだけが薄くかかる
	float gap = 0.30 * g * (1.0 - c.a);
	col = mix(col, mix(LIGHT_COL, lit(c.rgb, g), step(0.001, c.a)), shape);
	COLOR = vec4(col, max(max(c.a, a_edge), gap));
}
"""
