extends Node3D
## 布の見本帳（2026-11-06 代表「見本帖＋自由な色にしてほしい」）。立てかけ台の北の端の横、下屋の屋根の下に立つ（main.gd の SLED_BOOK_AT）。
## ぎざぎざに切ったフェルトの布を真鍮の輪で綴じた形（design/sled-custom/build_book.py）。
## ふだんは布を重ねて輪から垂らしている。人が前に来ると、外の布から順に扇に開き、離れると閉じる（2026-11-07 代表「見本帳は近づくと展開される方が良いかも」）。
## 動きは人形と同じ 12 コマ／秒。布 1 枚ごとのばねで、勢いのぶんだけ先が遅れて手前へめくれる。開ききったら止まり、形も更新しない。
## 布は 1 枚の形を 12 枚に増やして色を付ける（MultiMesh。色の違う 12 枚でも描くのは布と札の 2 回）。
## 前で F を押すと、自分のソリの色と滑りあとの縫い目を替える画面が開く（sled_book_ui.gd）。
## この節の +Z が見本帳の正面。

const Props := preload("res://props.gd")
const Doll := preload("res://doll.gd")
const Sense := preload("res://stall_sense.gd")
const SledBookUi := preload("res://sled_book_ui.gd")

const REACH := 3.4           # F が届く距離 (m)
const FACE := 0.5            # 見本帳の方を向いている（見ている向きと見本帳への向きの合い具合）
const SENSE_R := 5.5         # この距離に人が来ると開く (m)。F が届く距離より広い
const PIN := Vector3(0, 2.72, 0)   # 綴じの輪の高さ（build_book.py の PIN_Z）
const LEAF_Z := 0.03         # いちばん奥の布の、綴じの面からの出（build_book.py）
const LEAF_DZ := 0.012       # 布どうしの間
const SPREAD := 68.0         # 開いたときの両端の角 (度)
const FOLDED := 6.0          # 閉じたときの両端の角 (度)。重ねた布の色が少しのぞく
const OPEN_K := 0.2          # 開くばね（コマごと）
const OPEN_D := 0.64
const SHUT_K := 0.1          # 閉じるときはゆっくり、跳ねない
const SHUT_D := 0.62
const LAG := 0.55            # 速さのぶん、布の先が遅れる（ずらす割合）
const FLAP := 1.0            # 速さのぶん、布の先が手前へめくれる
const FLAP_MAX := 0.5
const STILL := 0.002         # これより小さな動きになったら止める (rad)

var main: Node               # main.gd が入れる
var _felt: MultiMesh
var _trim: Array[MultiMesh] = []
var _a := PackedFloat32Array()      # 布ごとの角
var _v := PackedFloat32Array()      # 布ごとの速さ
var _wait := PackedInt32Array()     # 布ごとの、動き出すまでのコマ
var _want := false
var _moving := true
var _frame := -1
var _check := 0.0


func _ready() -> void:
	add_child(Props.make("res://props/sled_book/sled_book.glb"))
	var n: int = SledBookUi.SWATCHES.size()
	_a.resize(n)
	_v.resize(n)
	_wait.resize(n)
	var c := (n - 1) * 0.5
	for i in n:
		_a[i] = deg_to_rad(FOLDED) * (float(i) - c) / c
	var leaf := _fan("res://props/sled_book/sled_book_leaf.glb", true)
	_felt = leaf[0]
	for m in _fan("res://props/sled_book/sled_book_leaf_trim.glb", false):
		_trim.append(m)
	_show()
	_moving = false
	var body := StaticBody3D.new()
	body.name = "BookBody"
	# 足もとの板と針山、扇のまんなか（脚と布の下の端は通れるように、当たりは板と脚の分だけ）
	for b in [[Vector3(1.5, 0.35, 0.95), Vector3(0, 0.175, -0.1)], [Vector3(0.9, 2.7, 0.3), Vector3(0, 1.45, -0.1)]]:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b[0]
		col.shape = box
		col.position = b[1]
		body.add_child(col)
	add_child(body)


## glb の形を、布の枚数ぶん増やして置く。tint なら布ごとに SWATCHES の色を付ける
func _fan(path: String, tint: bool) -> Array:
	var src := Props.make(path)
	var out := []
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = tint
		mm.mesh = m.mesh
		mm.instance_count = _a.size()
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		var mat := m.get_surface_override_material(0)
		if tint:
			mat = (mat as BaseMaterial3D).duplicate()   # 焼いた素材は小物どうしで共有なので、写しに
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			for i in _a.size():
				mm.set_instance_color(i, Color(String(SledBookUi.SWATCHES[i])))
		node.material_override = mat
		add_child(node)
		out.append(mm)
	src.free()
	return out


func _process(dt: float) -> void:
	_check -= dt
	if _check <= 0.0:
		_check = Sense.CHECK
		var want := Sense.nearest(main, self, SENSE_R, -0.4) != null
		if want != _want:
			_set_want(want)
	if not _moving:
		return
	var f := Doll.frame_index()
	if f == _frame:
		return
	var steps := clampi(f - _frame, 1, 3) if _frame >= 0 else 1
	_frame = f
	for s in steps:
		_step()
	_show()


func _set_want(want: bool) -> void:
	_want = want
	_moving = true
	_frame = -1
	var n := _a.size()
	var c := (n - 1) * 0.5
	for i in n:   # 外の布から順に動き出す。閉じるときは少し間を詰めて
		_wait[i] = int((c - absf(float(i) - c)) * (1.0 if want else 0.5))
	var audio = main.get_node_or_null("Audio") if main else null
	if audio:
		audio.kitchen(self, "stall_flap", -11.0 if want else -16.0)


func _step() -> void:
	var n := _a.size()
	var c := (n - 1) * 0.5
	var k := OPEN_K if _want else SHUT_K
	var d := OPEN_D if _want else SHUT_D
	var goal := deg_to_rad(SPREAD if _want else FOLDED)
	var still := true
	for i in n:
		if _wait[i] > 0:
			_wait[i] -= 1
			still = false
			continue
		var g := goal * (float(i) - c) / c
		_v[i] = _v[i] * d + (g - _a[i]) * k
		_a[i] += _v[i]
		if absf(_v[i]) < STILL and absf(g - _a[i]) < STILL:
			_a[i] = g
			_v[i] = 0.0
		else:
			still = false
	if still:
		_moving = false


func _show() -> void:
	for i in _a.size():
		var v := _v[i]
		var bend := Basis(Vector3.RIGHT, -minf(absf(v) * FLAP, FLAP_MAX))
		var lag := Basis(Vector3.RIGHT, Vector3(v * LAG, 1.0, 0.0), Vector3.BACK)
		var t := Transform3D(Basis(Vector3.BACK, _a[i]) * lag * bend, PIN + Vector3.BACK * (LEAF_Z + LEAF_DZ * (_a.size() - 1 - i)))   # 閉じたときの前は 0 番の赤
		_felt.set_instance_transform(i, t)
		for m in _trim:
			m.set_instance_transform(i, t)


func can_use(p: Node3D) -> bool:
	var d := global_position - p.global_position
	if absf(d.y) > 1.5:
		return false
	d.y = 0
	return to_local(p.global_position).z > 0.0 and d.length() <= REACH and (-p.global_basis.z).dot(d.normalized()) > FACE   # 前からだけ（裏は西のガラスの戸の側）


func hint_at(_p: Node3D) -> Vector3:
	return global_position + Vector3.UP * 3.1
