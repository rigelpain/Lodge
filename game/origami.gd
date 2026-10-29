extends Node3D
## ソリを折り紙のように畳む・広げる動き（12 コマ／秒に刻む。人形と同じ）。craft.gd の出来事 fold・unfold で置く。
## 畳む（30 コマ）:
##    0〜4  ソリがぺたんとつぶれて、ソリの大きさの 1 枚の布になる
##    5〜10 前の半分が持ち上がって、後ろの半分の上へ折り重なる（山折り 1）
##   11〜16 もう一度、前の半分を後ろへ（2）
##   17〜22 左の半分を右へ（3）。小さな包みになる
##   23〜29 包みがぴょんと跳ねて、畳んだ人の手へ飛んで消える（持ち物に入る）
## 広げる（30 コマ）はその逆: 手から包みが落ちる → 3 → 2 → 1 と開く → 布がふくらんでソリになる（そこで本物のソリが現れる）。
## 布は 1 枚あたり厚み LAYER。折るたびに重なりが倍になる。

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Props := preload("res://props.gd")
const Sled := preload("res://sled.gd")
const Fabrics := preload("res://fabrics.gd")

const FRAMES := 30
const LAYER := 0.014         # 布 1 枚の厚み (m)
const STEP := 6              # 1 回折るコマ数
const LIFT := 0.03           # 床から浮かせる高さ（ロッジの床板は当たりの床より 2 cm 高い）

var kind := "mid"
var fabric := "red"
var unfolding := false       # false: 畳む、true: 広げる
var who: Node3D              # 包みが飛んでいく・落ちてくる人
var start := 0               # 始まりのコマ（Doll.frame_index()）
var _w := 1.5
var _l := 2.8
var _frame := -1
var _look: Node3D            # ソリの形（つぶれる・ふくらむ）
var _sheet: Node3D           # 布（コマごとに組み直す）
var _mat_a: StandardMaterial3D
var _mat_b: StandardMaterial3D
var _crease: StandardMaterial3D
var _from := Vector3.ZERO    # 包みが飛ぶ・落ちる始まり（広げる）


func _ready() -> void:
	var k: Dictionary = Sled.KINDS.get(kind, Sled.KINDS["mid"])
	_w = k.box.x
	_l = k.box.z
	var col := Fabrics.color(fabric)
	if kind == "sack" and fabric == "":
		col = preload("res://sled.gd").KINDS["sack"].color
	_mat_a = Look.felt(col, 2.0)
	_mat_b = Look.felt(col.darkened(0.12), 2.0)
	_crease = Look.felt(col.darkened(0.4) if col.get_luminance() > 0.35 else col.lightened(0.45), 4.0)
	var glb := "res://props/sled_%s.glb" % kind
	if ResourceLoader.exists(glb):
		_look = Props.make(glb)
		Fabrics.tint(_look, kind, fabric)
		add_child(_look)
	_sheet = Node3D.new()
	add_child(_sheet)
	if start == 0:
		start = Doll.frame_index()
	if unfolding and who:
		_from = to_local(who.global_position + Vector3.UP * 1.1)
	elif unfolding:
		_from = Vector3(0, 4.0, 0)   # 持ち主がいない（ミシンからロッジの前へ届く）: 空から落ちてくる
	_pose(0)


func _process(_dt: float) -> void:
	var k := Doll.frame_index() - start
	if k == _frame:
		return
	_frame = k
	if k >= FRAMES:
		queue_free()
		return
	_pose(maxi(k, 0))


## k コマ目の形
func _pose(k: int) -> void:
	for c in _sheet.get_children():
		c.queue_free()
	_sheet.position = Vector3(0, LIFT, 0)
	_sheet.scale = Vector3.ONE
	_sheet.visible = true
	if _look:
		_look.visible = false
	var t := k if not unfolding else FRAMES - 1 - k   # 広げるは畳むの逆回し
	if t < 5:
		# つぶれる（広げるでは、ふくらんで少し行き過ぎて戻る）
		var sq: float
		if unfolding:
			sq = [1.0, 1.12, 0.7, 0.3, 0.08][t]
		else:
			sq = [1.0, 0.75, 0.45, 0.2, 0.08][t]
		if _look:
			_look.visible = true
			_look.scale = Vector3(1.0 + (1.0 - sq) * 0.06, sq, 1.0 + (1.0 - sq) * 0.06)
		_sheet.visible = t >= 3
		if t >= 3:
			_flat(0)
		return
	if t < 5 + STEP:
		_fold_step(0, _ease(float(t - 5 + 1) / STEP))
	elif t < 5 + STEP * 2:
		_fold_step(1, _ease(float(t - 5 - STEP + 1) / STEP))
	elif t < 5 + STEP * 3:
		_fold_step(2, _ease(float(t - 5 - STEP * 2 + 1) / STEP))
	else:
		# 包み: 跳ねて手へ飛ぶ（広げるでは、手から落ちてきて着く）
		_flat(3)
		var u := float(t - (5 + STEP * 3)) / float(FRAMES - 1 - (5 + STEP * 3))   # 0（床）〜1（手）
		var c := _rect(3).get_center()
		var to := _from if unfolding else (to_local(who.global_position + Vector3.UP * 1.1) if is_instance_valid(who) else Vector3(c.x, 1.0, c.y))
		var floor_p := Vector3(c.x, 0, c.y)
		var p := floor_p.lerp(to, u * u) + Vector3.UP * sin(u * PI) * 0.5
		var s := lerpf(1.0, 0.25, u * u)
		_sheet.scale = Vector3.ONE * s
		_sheet.position = p - floor_p * s + Vector3(0, LIFT, 0)


static func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## 折った回数 n のときの布の広がり（x の範囲を x、z の範囲を y に入れた Rect2）と、重なりの数
func _rect(n: int) -> Rect2:
	match n:
		0: return Rect2(-_w / 2, -_l / 2, _w, _l)
		1: return Rect2(-_w / 2, 0, _w, _l / 2)
		2: return Rect2(-_w / 2, _l / 4, _w, _l / 4)
	return Rect2(0, _l / 4, _w / 2, _l / 4)


## n 回折ったあとの、平らに重なった布
func _flat(n: int) -> void:
	var r := _rect(n)
	var layers := 1 << n
	_panel(_sheet, r, 0.0, layers, _mat_b if n > 0 else _mat_a)
	_creases(r, layers)


## i 回目を折っている途中（a は 0〜1 の折れ具合）
func _fold_step(i: int, a: float) -> void:
	var rest := _rect(i + 1)
	var layers := 1 << i
	var th := LAYER * layers
	_panel(_sheet, rest, 0.0, layers, _mat_b)
	var pivot := Node3D.new()
	_sheet.add_child(pivot)
	var flap: Rect2
	if i < 2:
		# 前（-z）の半分を、蝶番（z = rest の手前の縁）のまわりに持ち上げて後ろへ
		var hz := rest.position.y
		pivot.position = Vector3(0, th, hz)
		flap = Rect2(rest.position.x, -rest.size.y, rest.size.x, rest.size.y)
		pivot.rotation.x = PI * a
	else:
		# 左（-x）の半分を、蝶番（x = 0）のまわりに右へ
		pivot.position = Vector3(0, th, 0)
		flap = Rect2(-rest.size.x, rest.position.y, rest.size.x, rest.size.y)
		pivot.rotation.z = -PI * a
	var box := _panel(pivot, flap, -th, layers, _mat_a)
	_creases(rest, layers)


## 布の板: rect（x と z の範囲）、下の面の高さ y0、重なりの数
func _panel(parent: Node3D, r: Rect2, y0: float, layers: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var th := LAYER * layers
	bm.size = Vector3(r.size.x, th, r.size.y)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(r.get_center().x, y0 + th / 2.0, r.get_center().y)
	parent.add_child(mi)
	return mi


## 折り目の縫い目: 布の縁に沿って、細い破線を 1 周
func _creases(r: Rect2, layers: int) -> void:
	var y := LAYER * layers + 0.002
	var inset := 0.05
	var a := Vector2(r.position.x + inset, r.position.y + inset)
	var b := Vector2(r.end.x - inset, r.end.y - inset)
	var pts := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
	for i in 4:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % 4]
		var n := maxi(2, int(p0.distance_to(p1) / 0.12))
		for j in n:
			if j % 2 == 1:
				continue
			var q0 := p0.lerp(p1, float(j) / n)
			var q1 := p0.lerp(p1, float(j + 1) / n)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(maxf(absf(q1.x - q0.x), 0.012), 0.004, maxf(absf(q1.y - q0.y), 0.012))
			mi.mesh = bm
			mi.material_override = _crease
			mi.position = Vector3((q0.x + q1.x) / 2.0, y, (q0.y + q1.y) / 2.0)
			_sheet.add_child(mi)
