extends Node3D
## 厨房の装置それぞれの真上に吊る品書きの板（2026-11-02 代表「施設それぞれの上にその施設が調理工程にある食べ物一覧にするだけ」
## 「値段もいりません」「けっこう遠くて…見えない」）。板には、その装置を調理の道に通る料理の絵と名前を並べる。
## 板は藍の糸で天井から吊った木の棒に、深緑のフェルトを掛けた形。食堂から見上げて読めるよう、前へ少し傾ける。
## 絵は売り場の画面（food_ui.gd）と同じ描き方（フェルトの継ぎ当て・なみ縫い・刺繍の字）で、起動のときに 1 度だけ描いて画像にする。
## 厨房の目印 slot_food_kitchen の子に置く（座標は main.gd の KITCHEN と同じ。+Z が食堂の側）。
## ロッジに前からある無地の板 3 枚（lodge/build_lodge.py の menu_board。内装の形の felt_green の面）は隠す

const Food := preload("res://food.gd")
const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")

## 板の大きさ（m）。装置の間（いちばん狭いのは乾燥機とスチーマーの 2.8 m）に収まる幅
const SIZE := Vector2(2.4, 1.35)
## 板の上の端の高さ（床から）と、前後の位置（装置の正面の側）。下の端は乾燥機の天板（3.46 m）より上
const TOP := 4.95
const FRONT_Z := 1.0
const TILT := 12.0           # 前へ傾ける（度）
const CEIL := 5.25           # 1 階の天井（lodge/dims.py の CEIL1 5.7 - FL1 0.45）
const PX := 600.0            # 絵の細かさ（1 m あたりの px）
const U := 4.0               # 絵の単位（1 単位 = U px）。縫い目の太さをこの倍率で太らせる
const FELT := Color(0.25, 0.36, 0.28)       # 深緑のフェルト
const WOOD := Color(0.50, 0.34, 0.20)

var stations: Array = []     # main.gd の KITCHEN
var lodge: Node3D
var _tex: Dictionary = {}


func _ready() -> void:
	_hide_old()
	_build.call_deferred()


## その装置を調理の道に通る料理（品書きの順）
static func dishes_at(kind: String) -> Array:
	return Food.ORDER.filter(func(d): return kind in Food.route(d))


## ロッジの無地の板（内装の形の felt_green の面）を描かない
func _hide_old() -> void:
	var mi := lodge.find_child("lodge_props_interior", true, false) as MeshInstance3D if lodge else null
	if mi == null:
		return
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m and m.resource_name == "felt_green":
			var sh := Shader.new()
			sh.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { discard; }\n"
			var hide := ShaderMaterial.new()
			hide.shader = sh
			mi.set_surface_override_material(s, hide)


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	return m


## 描き直す（確かめの道具から）
func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	await _build()


func _build() -> void:
	for st in stations:
		var kind: String = st[0]
		var img := await render(kind)
		if img == null:
			continue
		img.generate_mipmaps()
		# 吊る点（棒の高さ。傾けない）→ 板（棒を軸に前へ傾ける）
		var hang := Node3D.new()
		hang.name = "Menu_" + kind
		hang.position = Vector3((st[2] as Vector3).x, TOP + 0.03, FRONT_Z)
		add_child(hang)
		var board := Node3D.new()
		board.rotation.x = deg_to_rad(TILT)
		hang.add_child(board)
		var face_mat := StandardMaterial3D.new()
		face_mat.albedo_texture = ImageTexture.create_from_image(img)
		face_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		face_mat.roughness = 1.0
		var q := QuadMesh.new()
		q.size = SIZE
		_part(board, q, face_mat, Vector3(0, -0.03 - SIZE.y / 2.0, 0.008))
		var back := BoxMesh.new()   # 裏と縁のフェルト
		back.size = Vector3(SIZE.x + 0.04, SIZE.y + 0.04, 0.014)
		_part(board, back, _mat(FELT.darkened(0.15)), Vector3(0, -0.03 - SIZE.y / 2.0, 0))
		var rod := CylinderMesh.new()   # 掛ける木の棒
		rod.top_radius = 0.025
		rod.bottom_radius = 0.025
		rod.height = SIZE.x + 0.24
		var r := _part(hang, rod, _mat(WOOD), Vector3.ZERO)
		r.rotation.z = PI / 2.0
		for sx in [-1.0, 1.0]:   # 天井へ上がる藍の糸
			var cord := CylinderMesh.new()
			cord.top_radius = 0.007
			cord.bottom_radius = 0.007
			cord.height = CEIL - hang.position.y
			_part(hang, cord, _mat(Icons.THREAD), Vector3(sx * (SIZE.x / 2.0 - 0.05), cord.height / 2.0, 0))


func _part(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


## 装置 kind の板の絵を描いて画像にする（確かめの道具からも呼ぶ）
func render(kind: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(SIZE.x * PX), int(SIZE.y * PX))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var v := View.new()
	v.board = self
	v.dishes = dishes_at(kind)
	v.size = Vector2(vp.size)
	vp.add_child(v)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	return img


func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


class View extends Control:
	var board: Node
	var dishes: Array = []

	func _draw() -> void:
		Icons._o = Vector2.ZERO
		Icons._s = U
		var w := size.x / U
		var h := size.y / U
		draw_rect(Rect2(Vector2.ZERO, size), FELT.darkened(0.2))
		Icons.patch(self, Icons.rr(0, 0, w, h, 4.0), FELT, 1.0, false, Color(0, 0, 0, 0), false)
		Icons.dashes(self, Icons.rr(5, 5, w - 10, h - 10, 6.0), Icons.CAP, 0.9, 4.0, 2.6, 0.85, true)
		# 2 段に並べる（下の段が短いときは中ほどへ寄せる）
		var cols := ceili(dishes.size() / 2.0)
		var area := Rect2(10, 9, w - 20, h - 18)
		var cw := area.size.x / cols
		var ch := area.size.y / 2.0
		var isz := minf(cw * 0.86, ch * 0.7)
		var font := Icons._bold_font()
		for k in dishes.size():
			var row := k / cols
			var n_row := cols if row == 0 else dishes.size() - cols
			var x0 := area.position.x + (area.size.x - cw * n_row) / 2.0
			var c := Vector2(x0 + cw * (k % cols + 0.5), area.position.y + ch * row + isz / 2.0 + 3.0)
			Icons.patch(self, Icons.circ(c + Vector2(0, isz * 0.03), isz * 0.48, 30), Icons.PAPER, 1.0, true, Icons.PAPER_EDGE)
			var t: Texture2D = board.tex(Food.dish_icon(dishes[k]))
			if t:
				draw_texture_rect(t, Rect2((c - Vector2(isz, isz) / 2.0) * U, Vector2(isz, isz) * U), false)
			# 名前の刺繍（長い名前は升に収まるまで小さく）
			var text: String = CraftIcons.DISH_NAMES.get(dishes[k], "")
			var fs := 12.0 * U
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
			if tw > cw * 0.94 * U:
				fs *= cw * 0.94 * U / tw
				tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
			Icons.stitched_text(self, text, Vector2(c.x * U - tw / 2.0, (c.y + isz * 0.5 + 9.0) * U), fs, Icons.CAP)
