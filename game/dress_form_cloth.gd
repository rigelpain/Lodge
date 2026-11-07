extends Node3D
## 人台のまわりの長い布（wardrobe.gd の子）。ふだんは桶の液に沈んでいて、人が近づくと 1 枚ずつ液から昇り、人台に巻きつくように渦を描いて
## 天井の輪まで上がり、ほどけて後ろへ垂れる。離れると逆にたどって液へ沈む
## （2026-11-07 代表「いまトルソー周りの布が染台から昇って来てもいいのに」）。
## コマ _stage ひとつで形が決まる（12 コマ／秒）。5 枚をまとめて 1 つの形にするので、描くのは布と糸の 2 回。
## 形の計算は重いので、起動したときに裏のスレッドで全コマぶん済ませ、動かすときは組み立てるだけにする。
## 昇りきったら止まり、形も更新しない。沈んでいるあいだは隠す。形の元は design/dye-wardrobe/ideas.py の long_cloth（E）。
## この節の座標は人台の節と同じ: +Z が正面。角 th は正面から測り、位置は (r sin th, y, r cos th)

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

const R_TOP := 1.62          # 天井の輪の半径
const R_MID := 1.72          # 人形の高さでの半径（回る人形に当たらないよう、少しふくらむ）
const Y_TOP := 4.96          # 天井の輪の高さ
const Y_LIQ := 0.58          # 液の面の少し下
## 5 枚の布: [角の始まり（度）, 色]。後ろの半分あまり。前はあける
const STRIPS := [[60.0, "A8532E"], [108.0, "C99A3A"], [156.0, "9E3B3A"], [204.0, "6E7F4A"], [252.0, "A8532E"]]
const SPAN := 40.0           # 1 枚の幅（度）
const ROWS := 24
const COLS := 12             # 偶数。布の先をぎざぎざに切る
const RISE := 22             # 1 枚が昇るコマ数
const DELAY := 3             # 次の布が出るまでのコマ
const SETTLE := 8            # 昇りきってから止まるまでのコマ
const DEEP := 0.74           # 焼いた布と同じ色の深さに見えるよう、色を沈める
const SPIRAL := 2.6          # 昇る途中の、先の巻きつき（rad）
const STAGES := RISE + DELAY * 4 + SETTLE

var _mat: StandardMaterial3D
var _thread: StandardMaterial3D
var _mi: MeshInstance3D
var _arrays: Array = []      # コマ → [布の配列, 糸の配列]（裏のスレッドが作る）
var _meshes := {}
var _task := -1
var _stage := 0
var _frame := -1


func _ready() -> void:
	_mat = Look.felt(Color.WHITE, 1.5)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_thread = Look.felt(Color("EFE6D2"), 4.0)
	_thread.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi = MeshInstance3D.new()
	_mi.visible = false
	add_child(_mi)
	_task = WorkerThreadPool.add_task(_build_all)


func _exit_tree() -> void:
	_wait_built()


func _wait_built() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## 裏のスレッド: 全コマの形を計算する
func _build_all() -> void:
	var out := []
	for s in STAGES + 1:
		out.append(_shape(s))
	_arrays = out


func _process(_dt: float) -> void:
	var goal := STAGES if get_parent().near else 0
	if _stage == goal:
		return
	var f := Doll.frame_index()
	if f == _frame:
		return
	_frame = f
	_stage += signi(goal - _stage)
	_mi.visible = _stage > 0
	if _stage > 0:
		_mi.mesh = _mesh(_stage)


## 布 k の、コマ s での昇り具合（0 = 液の中、1 = 天井）。出だしは速く、上で少しゆるむ
static func _rise(k: int, s: int) -> float:
	var p := clampf(float(s - k * DELAY) / RISE, 0.0, 1.0)
	return 1.0 - (1.0 - p) * (1.0 - p)


## 布 k の先の巻きつき。昇るほどほどけ、昇りきった所で少し行き過ぎて戻る
static func _twist(k: int, s: int) -> float:
	var over := s - k * DELAY - RISE
	if over >= 0:
		var left := maxi(STAGES - k * DELAY - RISE, 1)
		var e := 1.0 - float(over) / left
		return -0.16 * e * cos(float(over) * 1.1) if e > 0.0 else 0.0
	var p := clampf(float(s - k * DELAY) / RISE, 0.0, 1.0)
	return SPIRAL * pow(1.0 - p, 0.8) * sin(minf(p * 8.0, 1.0) * PI * 0.5)


## コマ s の形（組み立ては本体のスレッドで。計算は済んでいる）
func _mesh(s: int) -> ArrayMesh:
	if _meshes.has(s):
		return _meshes[s]
	_wait_built()
	var mesh := ArrayMesh.new()
	var a: Array = _arrays[s]
	if not a.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a[0])
		mesh.surface_set_material(0, _mat)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a[1])
		mesh.surface_set_material(1, _thread)
	_meshes[s] = mesh
	return mesh


## コマ s の布と糸の配列（裏のスレッドから呼ぶ。節やリソースに触らない）
static func _shape(s: int) -> Array:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var us := PackedVector2Array()
	var idx := PackedInt32Array()
	var tv := PackedVector3Array()
	var tn := PackedVector3Array()
	for k in STRIPS.size():
		var rise := _rise(k, s)
		if rise <= 0.0:
			continue
		var tw := _twist(k, s)
		var flutter := 0.05 * (1.0 - rise) + (0.012 if rise < 1.0 else 0.0)
		var th0 := deg_to_rad(float(STRIPS[k][0]))
		var span := deg_to_rad(SPAN)
		var col := Color(String(STRIPS[k][1]))
		var tip := lerpf(Y_LIQ, Y_TOP, rise)
		var o := vs.size()
		var w := COLS + 1
		for j in ROWS + 1:
			var t := float(j) / ROWS   # 0 が布の先、1 が液の中の根もと
			for i in COLS + 1:
				var u := float(i) / COLS
				var edge := 2.0 * u - 1.0
				# 先は丸く、ぎざぎざ。昇りきると、まっすぐ天井の輪に掛かる
				var y := lerpf(tip, Y_LIQ, t)
				if j == 0:
					y -= (0.0 if i % 2 == 0 else 0.05) * (1.0 - rise)
				y -= edge * edge * 0.35 * (1.0 - rise) * (1.0 - t)
				var h := clampf((y - Y_LIQ) / (Y_TOP - Y_LIQ), 0.0, 1.0)
				var fold := 0.05 * (0.3 + t) * sin(u * TAU * 2.0)
				var r := lerpf(R_MID, R_TOP, h * h * h) + fold + flutter * sin(y * 3.2 - s * 0.9 + k * 1.3)
				var th := th0 + span * u + tw * h
				vs.append(Vector3(sin(th) * r, y, cos(th) * r))
				us.append(Vector2(u * 1.1, y * 0.4))
				var shade := DEEP * (0.88 + 0.16 * sin(u * TAU * 2.0))
				cs.append(Color(col.r * shade, col.g * shade, col.b * shade))
		for j in ROWS + 1:
			for i in COLS + 1:
				var a := vs[o + j * w + mini(i + 1, COLS)] - vs[o + j * w + maxi(i - 1, 0)]
				var b := vs[o + mini(j + 1, ROWS) * w + i] - vs[o + maxi(j - 1, 0) * w + i]
				ns.append(a.cross(b).normalized())
		for j in ROWS:
			for i in COLS:
				var q := o + j * w + i
				idx.append_array([q, q + 1, q + w, q + 1, q + w + 1, q + w])
		# 両の耳のなみ縫い
		for side: int in [1, COLS - 1]:
			for j in range(0, ROWS, 2):
				var q0: int = o + j * w + side
				var q1: int = o + (j + 1) * w + side
				var n0 := ns[q0] * 0.008
				var wide := (vs[q0 + 1] - vs[q0]).normalized() * 0.014
				var a1 := vs[q0].lerp(vs[q1], 0.65)
				tv.append_array([vs[q0] + n0 - wide, vs[q0] + n0 + wide, a1 + n0 - wide, vs[q0] + n0 + wide, a1 + n0 + wide, a1 + n0 - wide])
				for x in 6:
					tn.append(ns[q0])
	if vs.is_empty():
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_TEX_UV] = us
	arr[Mesh.ARRAY_INDEX] = idx
	var st := []
	st.resize(Mesh.ARRAY_MAX)
	st[Mesh.ARRAY_VERTEX] = tv
	st[Mesh.ARRAY_NORMAL] = tn
	return [arr, st]
