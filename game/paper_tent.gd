extends Node3D
## 紙細工屋さんのテント（2026-11-04 代表「紙細工士さんはエレガントなテントで営業させよう。プレイキャラが近くにいないときはテントの入口を閉めてる感じで」）。
## 案の絵は design/paper-lady-tent/00-proposals.jpg（代表が E を選んだ）。婦人の裾を大きくした形で、屋根と飾りは墨、壁と幕は中の灯りで薄く光る和紙。
## ふだんは前の幕が閉じていて、婦人と品物は見えない。閉じた幕の上の真ん中は、婦人の胸の V のように裏の朱がのぞく。
## 人（婦人の _people。自分と、つないでいるほかの人）が近づくと左右へ引き分けて開き、離れると閉まる。どの画面でも、それぞれ人の位置から決める（通信では送らない）。
## 開け閉めは番台のカーテン（bandai_curtain.gd）と同じく人形の 12 コマ／秒で刻む。竿の所が先に動き、裾は遅れてついてきて、少し行き過ぎて戻る。
## 開いてから婦人がおじぎをする（paper_lady.gd は bow_ready を見る）。
## 形は person/ideas/kamizaiku/tent_ideas.py: paper_tent.glb が幕を除くテント、paper_tent_curtain.glb が幕の絵（平らな板 2 枚）。幕の形はここで作る。
## 座標は床の楕円の真ん中が原点、+Z が前。原点の所は paper_lady.gd の TENT_AT

const Doll := preload("res://doll.gd")
const Props := preload("res://props.gd")
const BandaiCurtain := preload("res://bandai_curtain.gd")

const BODY_GLB := "res://props/paper_lady/paper_tent.glb"
const CURTAIN_GLB := "res://props/paper_lady/paper_tent_curtain.glb"
const RX := 1.68             # 床の楕円の半径 (m)。tent_ideas.py の RX・RY・E・RAIL と同じ
const RY := 1.15
const E := 50.0              # 入口の開きの半分の角度（前から左右へ）
const RAIL := 2.5            # 幕の上の縁
const COLS := 28
const ROWS := 9
const FOLDS := 7             # 片側の幕のひだの数
const V_CUT := 0.62          # 閉じた幕の上の真ん中の V の深さ (m)
const TIE_Y := 1.05          # 開いた幕を留める高さ
const OPEN_FRAMES := 9       # 開くのにかかるコマ（12 コマ／秒で 0.75 秒）
const CLOSE_FRAMES := 14     # 閉じるのにかかるコマ
const SENSE_IN := 4.6        # テントの真ん中からこの距離に人が入ると開く (m)。婦人が気づく距離（paper_lady.gd の NOTICE_R）より広い
const SENSE_OUT := 5.2       # この距離より離れると閉じる
const SENSE_Y := 2.0         # 高さの差がこれより大きい人は数えない（2 階の人）
const BOW_OPEN := 0.7        # 幕がここまで開いたら、婦人がおじぎをしてよい
const GLOW := 0.45           # 和紙が中の灯りで光る強さ
const WALL_SEGS := 14        # 壁の当たりの箱の数

var lady: Node3D             # paper_lady.gd（人の並び _people・画面 ui を見る）
var force := -1.0            # 0〜1 で開き具合を決めて止める（撮る用）。負なら人で開け閉め
var open := 0.0              # 竿の所の開き具合（コマで進む）
var _hem := 0.0              # 裾の開き具合（竿に遅れてついてくる）
var _hem_v := 0.0
var _want := false
var _frame := -1
var _shown := Vector2(-1, -1)
var _outer: Array[MeshInstance3D] = []
var _lining: Array[MeshInstance3D] = []
var _cords: Array[Node3D] = []


func _ready() -> void:
	var body := Props.make(BODY_GLB)
	body.rotation.y = PI   # glb の正面（Blender の +Y＝Godot の -Z）を、この節の正面 +Z へ
	add_child(body)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, _lit(m.get_active_material(i)))
	var sheets := Props.make(CURTAIN_GLB)
	var mat_outer := _lit((sheets.find_child("curtain_outer*", true, false) as MeshInstance3D).get_active_material(0))
	var mat_lining := _lit((sheets.find_child("curtain_lining*", true, false) as MeshInstance3D).get_active_material(0))
	sheets.free()
	for s in [1.0, -1.0]:
		_outer.append(_sheet(mat_outer))
		_lining.append(_sheet(mat_lining))
		# 開いた幕を束ねる朱の紐: 留める高さで、幕の束のまわりを一周する
		var inner := _point(s, 1.0, _tie_f(), 0.0, 1.0)
		var outer := _point(s, 0.0, _tie_f(), 0.0, 1.0)
		var mid := (inner + outer) / 2.0
		var along := (inner - outer) / 2.0
		var out := Vector3(mid.x, 0.0, mid.z).normalized() * 0.1
		var pts := []
		for k in 13:
			var a := TAU * k / 12.0
			pts.append(mid + along * 1.15 * cos(a) + out * sin(a))
		var cord := Node3D.new()
		add_child(cord)
		BandaiCurtain._tube(cord, pts, [0.012], mat_lining, 6)
		cord.visible = false
		_cords.append(cord)
	_make_walls()
	_show(0.0, 0.0)


## 幕を留める高さの、布の高さ f
func _tie_f() -> float:
	return (RAIL + 0.03 - TIE_Y) / (RAIL + 0.01)


## 焼いた紙の素材を、両面に、中の灯りで薄く光るように（地の色に掛けるので墨は暗いまま）。真鍮はそのまま
func _lit(src: Material) -> Material:
	if not src is BaseMaterial3D or (src as BaseMaterial3D).albedo_texture == null:
		return src
	var d := src.duplicate() as BaseMaterial3D
	d.cull_mode = BaseMaterial3D.CULL_DISABLED
	d.emission_enabled = true
	d.emission = Color(1.0, 0.8, 0.55)
	d.emission_texture = d.albedo_texture
	d.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	d.emission_energy_multiplier = GLOW
	return d


func _sheet(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	add_child(mi)
	return mi


## 壁の当たり: 入口を除く楕円に沿って、薄い箱を並べる。幕には当たりがない（人が近づけば開いている）
func _make_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "TentWalls"
	add_child(body)
	var a0 := 90.0 + E
	var a1 := 450.0 - E
	for i in WALL_SEGS:
		var p0 := _pl(lerpf(a0, a1, float(i) / WALL_SEGS), 1.03, 0.0)
		var p1 := _pl(lerpf(a0, a1, float(i + 1) / WALL_SEGS), 1.03, 0.0)
		var d := p1 - p0
		var box := BoxShape3D.new()
		box.size = Vector3(d.length() + 0.04, 2.7, 0.12)
		var col := CollisionShape3D.new()
		col.shape = box
		col.position = (p0 + p1) / 2.0 + Vector3.UP * 1.35
		col.rotation.y = -atan2(d.z, d.x)
		body.add_child(col)


## 幕がおじぎの見える所まで開いたか（paper_lady.gd が見る）
func bow_ready() -> bool:
	return open >= BOW_OPEN


# ---- 動き（12 コマ／秒）----------------------------------------------------------------

func _process(_dt: float) -> void:
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	var steps := clampi(fi - _frame, 1, 3) if _frame >= 0 else 1
	_frame = fi
	for i in steps:
		_step()
	_show(open, _hem)


func _step() -> void:
	if force >= 0.0:
		open = force
		_hem = force
		_hem_v = 0.0
		return
	_want = _someone_near()
	var goal := 1.0 if _want else 0.0
	open = move_toward(open, goal, 1.0 / (OPEN_FRAMES if goal > open else CLOSE_FRAMES))
	# 裾はばねで竿を追う（遅れて、少し行き過ぎて戻る）
	_hem_v = _hem_v * 0.6 + (open - _hem) * 0.28
	_hem += _hem_v
	if absf(_hem - open) < 0.002 and absf(_hem_v) < 0.002:
		_hem = open
		_hem_v = 0.0


## 開けておく人がいるか。開いているあいだは少し遠くまで数える（境目で開け閉めをくり返さない）。売る画面が開いているあいだも開けておく
func _someone_near() -> bool:
	if lady == null:
		return false
	var ui = lady.get("ui")
	if ui and ui.get("is_open"):
		return true
	var r := SENSE_OUT if _want else SENSE_IN
	for who in lady._people():
		if not is_instance_valid(who):
			continue
		var l := to_local((who as Node3D).global_position)
		if absf(l.y) < SENSE_Y and Vector2(l.x, l.z).length() < r:
			return true
	return false


## 竿の所の開き具合 et、裾の開き具合 eb で幕を形にする（変わらなければ作り直さない）
func _show(et: float, eb: float) -> void:
	var k := Vector2(et, eb)
	if k.is_equal_approx(_shown):
		return
	_shown = k
	var a := _ease(et)
	var b := _ease(eb)
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		_outer[i].mesh = _mesh(s, a, b, true)
		_lining[i].mesh = _mesh(s, a, b, false)
		_cords[i].visible = et >= 0.9 and absf(eb - et) < 0.1


static func _ease(e: float) -> float:
	var c := clampf(e, -0.2, 1.2)
	return c * c * (3.0 - 2.0 * c) if c >= 0.0 and c <= 1.0 else c


func _pl(th: float, k: float, y: float) -> Vector3:
	var a := deg_to_rad(th)
	return Vector3(cos(a) * RX * k, y, sin(a) * RY * k)


## 幕の点: 側 s（1 が -X の側）、布の位置 u（0 柱の側、1 真ん中の側）、高さ f（0 上、1 裾）、内への寄り inset、開き具合 e。
## folded が偽なら、ひだの内側を通る（裏の朱の紙。ひだを合わせると、寄せたときに表へ突き抜ける）
func _point(s: float, u: float, f: float, inset: float, e: float, folded := true) -> Vector3:
	var y := RAIL + 0.03 - f * (RAIL + 0.01)
	var tie := exp(-pow((y - TIE_Y) / 0.5, 2.0)) * e   # 留める高さの所は余計に寄る
	var span := lerpf(E + 0.8, 13.0 * (1.0 - 0.55 * tie), e)
	var th := 90.0 + s * (E - u * span)
	var amp := 0.012 + 0.05 * e
	var k := 1.03 - inset + s * 0.002 + (amp * sin(u * FOLDS * TAU) * (0.6 + 0.4 * f) if folded else -amp)
	return _pl(th, k, y)


## 片側の幕の形。outer は外の和紙（上の真ん中を V に切る）、そうでなければ裏の朱の紙（切らない。V の所に見える）
func _mesh(s: float, et: float, eb: float, outer: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in ROWS + 1:
		for c in COLS + 1:
			var u := float(c) / COLS
			var f := float(r) / ROWS
			var inset := 0.0
			if outer:
				var cut := V_CUT * smoothstep(0.62, 1.0, u) / (RAIL + 0.01)
				f = cut + (1.0 - cut) * f
			else:
				inset = 0.014
			st.set_uv(Vector2(u, f))
			st.add_vertex(_point(s, u, f, inset, lerpf(et, eb, pow(f, 1.4)), outer))
	BandaiCurtain._grid_index(st, ROWS, COLS)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()
