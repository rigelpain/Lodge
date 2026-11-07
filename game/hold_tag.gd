extends Node3D
## 手の材料に吊る紙の札（2026-11-06 代表「食べ物と調理施設の対応を施設の上のボードでなくもとを手に持ったときに表示」。案は design/hold-station-hint）。
## 札には次の装置を大きく、その下に、その次の装置（なければできあがる料理）を小さく描く。文字なし。1 工程済むと絵が替わる。
## player.gd が、材料を持っているあいだ毎コマ step を呼ぶ。本人の画面だけ（カメラの子で、層 5。小窓・鏡には映らない）。通信には載せない。
## 札はカメラに留める: 手と一緒に動かすと読みにくい（代表の気にした弱点）。手が動いても札は同じ所にあり、麻ひもだけが手の材料へ伸びる。
##   振れは、見回した・踏み出したときに少しだけ（振り子。SWING_MAX まで）。大きさと位置は画面の高さに対する割合で、視野角が変わっても同じ。
## 三人称では手の物が画面に出ないので、麻ひもなしで札だけ同じ所に出す（板がなくなったので、三人称でも行き先が分かるように）。

const Food := preload("res://food.gd")
const Icons := preload("res://hud_icons.gd")

const LAYER := 1 << 4        # 本人のカメラにだけ映る層（ride_wind.gd と同じ。一人称も三人称も映す）
const DEPTH := 0.4           # カメラからの距離 (m)。深さの判定はしないので、絵の大きさは変わらない
## 大きさと位置（画面の高さを 1 とした割合）。1080p で札 216 × 324 px、次の装置の絵は 180 px ほど。下の端は持ち物の列のすぐ上
const SIZE := Vector2(0.20, 0.30)
const HOLE := Vector2(0.17, 0.09)   # はとめ（振り子の支点）の位置。画面のまんなかから右へ・下へ
const HOLE_FROM_TOP := 0.024 # 札の上の端から、はとめまで
const PX := Vector2i(300, 450)   # 絵の細かさ
const REST_TILT := -0.05     # ふだんの傾き (rad)。手で吊った札らしく、まっすぐにしない
# ---- 振れ（振り子）
const SWING_K := 45.0        # 戻る強さ（1 秒に 1 回ほど揺れる）
const SWING_DAMP := 5.0      # 止まる強さ（2〜3 回揺れて止まる）
const SWING_TURN := 1.0      # 見回す速さ (rad/s) が振れに効く割合
const SWING_MOVE := 0.15     # 横への加速 (m/s²) が振れに効く割合
const SWING_MAX := 0.1       # 振れの上限 (rad。6° ほど)
const POP_T := 0.28          # 絵が替わったときに、ぽんとふくらむ時間 (s)
const POP := 0.1             # そのふくらみ

var _vp: SubViewport
var _card: Card
var _pivot: Node3D
var _cord: MeshInstance3D
var _key := ""
var _swing := 0.0
var _swing_v := 0.0
var _yaw := INF
var _pos := Vector3.INF
var _side_v := 0.0
var _pop := 0.0


## 札の絵: 紙に藍のステッチ、はとめ。大きな丸に次の装置、糸の矢印、小さな丸にその次
class Card extends Control:
	const FELT := Color(0.25, 0.36, 0.28)
	var big: Texture2D
	var small: Texture2D

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cut := w * 0.2
		var pts := PackedVector2Array([Vector2(cut, 0), Vector2(w - cut, 0), Vector2(w, cut), Vector2(w, h), Vector2(0, h), Vector2(0, cut)])
		Icons.screen()
		Icons.patch(self, pts, Icons.PAPER, 1.0, false, Color(0, 0, 0, 0), false)
		var inset := Geometry2D.offset_polygon(pts, -9.0)
		if inset.size() > 0:
			Icons.dashes(self, inset[0], Color(Icons.THREAD, 0.6), 2.4, 9.0, 6.0, 1.0, true)
		draw_circle(Vector2(w * 0.5, HOLE_FROM_TOP / SIZE.y * h), 11.0, Icons.PAPER_EDGE)
		draw_circle(Vector2(w * 0.5, HOLE_FROM_TOP / SIZE.y * h), 6.5, Color(0.35, 0.30, 0.28))
		var d := w * 0.84
		var y := 58.0
		_disc(big, Vector2(w * 0.5, y + d * 0.5), d)
		var yy := y + d + 3.0
		Icons.chevron(self, Vector2(w * 0.5, yy + 9.0), 28.0, Icons.RED, 1.0, PI / 2.0, 5.0)
		var s := h - (yy + 22.0) - 14.0
		_disc(small, Vector2(w * 0.5, yy + 22.0 + s * 0.5), s)

	## 深緑のフェルトの丸に、木の輪。絵は透明な背景のアイコン
	func _disc(t: Texture2D, c: Vector2, d: float) -> void:
		var pts := PackedVector2Array()
		for i in 40:
			pts.append(c + Vector2.from_angle(i / 40.0 * TAU) * d * 0.5)
		Icons.screen()
		Icons.patch(self, pts, FELT, 1.0, false, Color(0, 0, 0, 0), false)
		var ring := pts.duplicate()
		ring.append(pts[0])
		draw_polyline(ring, Icons.WOOD, maxf(3.0, d * 0.035), true)
		var s := d * 0.9
		draw_texture_rect(t, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = PX
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_card = Card.new()
	_card.size = Vector2(PX)
	_vp.add_child(_card)
	add_child(_vp)
	_pivot = Node3D.new()
	add_child(_pivot)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	var q := QuadMesh.new()
	q.size = SIZE
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position.y = -(SIZE.y * 0.5 - HOLE_FROM_TOP)
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(mi)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0018
	cm.bottom_radius = 0.0018
	cm.height = 1.0
	cm.radial_segments = 6
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.72, 0.60, 0.42)
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.no_depth_test = true
	cmat.render_priority = 11   # 札の上を通って、はとめへ
	_cord = MeshInstance3D.new()
	_cord.mesh = cm
	_cord.material_override = cmat
	_cord.layers = LAYER
	_cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cord)
	visible = false


## 札に描く 2 枚: 次の装置と、その次の装置（なければできあがる料理）
static func pictures(it: Dictionary) -> Array:
	var route: Array = Food.route(it.dish)
	var s: int = it.get("step", 0)
	return ["res://props/kitchen/icons/%s.png" % route[s],
			"res://props/kitchen/icons/%s.png" % route[s + 1] if s + 1 < route.size() else Food.dish_icon(it.dish)]


## 毎コマ。it は持っている材料（空なら札を消す）。hand は麻ひもの先（世界の座標。INF なら麻ひもなし）
func step(it: Dictionary, hand: Vector3, dt: float) -> void:
	visible = not it.is_empty()
	if not visible:
		_key = ""
		_yaw = INF
		return
	var key := "%s:%d" % [it.dish, int(it.get("step", 0))]
	if key != _key:
		_pop = 0.0 if _key == "" else 1.0   # 持った直後はふくらまない。工程が進んだときだけ
		_key = key
		var pics := pictures(it)
		_card.big = load(pics[0])
		_card.small = load(pics[1])
		_card.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_swing_step(dt)
	_pop = maxf(0.0, _pop - dt / POP_T)
	var cam := get_parent() as Camera3D
	var s := 2.0 * DEPTH * tan(deg_to_rad(cam.fov) * 0.5)   # 画面の高さ（DEPTH の所で, m）
	_pivot.position = Vector3(HOLE.x * s, -HOLE.y * s, -DEPTH)
	_pivot.scale = Vector3.ONE * s * (1.0 + POP * sin(_pop * PI))
	_pivot.rotation.z = REST_TILT + _swing
	_cord.visible = hand != Vector3.INF
	if _cord.visible:
		var a := _pivot.position
		var b := to_local(hand)
		var d := b - a
		_cord.position = (a + b) * 0.5
		_cord.basis = Basis(Quaternion(Vector3.UP, d.normalized())) * Basis.from_scale(Vector3(1.0, d.length(), 1.0))


func _swing_step(dt: float) -> void:
	if dt <= 0.0:
		return
	var b := global_basis
	var yaw := atan2(-b.z.x, -b.z.z)
	var p := global_position
	if _yaw == INF or p.distance_to(_pos) > 2.0:   # 持った直後・置き直された
		_yaw = yaw
		_pos = p
		_side_v = 0.0
		_swing = 0.0
		_swing_v = 0.0
		return
	var turn := wrapf(yaw - _yaw, -PI, PI) / dt
	var side := (p - _pos).dot(b.x.normalized()) / dt
	var acc := clampf((side - _side_v) / dt, -20.0, 20.0)
	_yaw = yaw
	_pos = p
	_side_v = side
	_swing_v += (-SWING_K * _swing - SWING_DAMP * _swing_v + turn * SWING_TURN - acc * SWING_MOVE) * dt
	_swing = clampf(_swing + _swing_v * dt, -SWING_MAX, SWING_MAX)


## 確かめ用: いまの振れ (rad)
func swing_now() -> float:
	return _swing
