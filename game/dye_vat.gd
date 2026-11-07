extends Node3D
## 1 階の人台（wardrobe.gd の子）の桶の中の染め液と、縁に掛けた染めたフェルト。桶そのものと櫂は人台の glb。
## 桶を見下ろして F を押すと、服を染める画面（dye_ui.gd）が開く（2026-11-01 代表「服の色変え」「染色桶をつくって、色に払うんじゃなくて染色代として払う」）。
## だれかが染めると（craft.gd の出来事 dye）、染め液と縁のフェルトが、その人の染めた色にじわっと変わる。人台の裾と長い布の色は変わらない。
## この節の +Z が桶の正面

## 人が近づくと、沈めてあった染め布がざばっと持ち上がり、しずくを落としながら前の縁を越えて外へ垂れる。離れると縁から引かれて液へ沈む
## （2026-11-07 代表「染台もなにかモーションを付けてほしい」）。動きは人形と同じ 12 コマ／秒のコマ _stage ひとつで形が決まる。垂れきったら止まる。

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")
const Sense := preload("res://stall_sense.gd")

const R := 1.8               # 桶の口の半径 (m)。design/dye-wardrobe/ideas.py の tub と同じ
const H := 0.74              # 桶の高さ
const LIQUID_Y := 0.62       # 染め液の面の高さ
const START := Color(0.17, 0.21, 0.38)   # はじめの染め液（藍）
const SOAK := 1.2            # 染め液の色が変わりきるまでの秒

const SENSE_R := 6.0         # 桶の真ん中からこの距離に人が来ると、布が上がる (m)。F が届く距離（wardrobe.gd の REACH）より広い
const CLOTH_W := 1.05        # 布の幅 (m)。桶の丸みに沿わせる
const ROWS := 18             # 布の長さの刻み
const COLS := 24             # 布の幅の刻み（偶数。裾をぎざぎざに切る）
## 布の断面のコマ。桶の真ん中から前への距離 r と高さ y の点（液の中の端 → 裾）。コマの間は人形と同じく止める。
## 0 は液の下に沈んだ形、最後が縁を越えて垂れた形
const POSES := [
	[Vector2(1.42, 0.56), Vector2(1.5, 0.56), Vector2(1.56, 0.56), Vector2(1.62, 0.56), Vector2(1.68, 0.56), Vector2(1.72, 0.56)],
	[Vector2(1.42, 0.56), Vector2(1.5, 0.6), Vector2(1.56, 0.72), Vector2(1.62, 0.72), Vector2(1.68, 0.6), Vector2(1.72, 0.56)],
	[Vector2(1.42, 0.56), Vector2(1.48, 0.72), Vector2(1.54, 1.0), Vector2(1.62, 1.02), Vector2(1.68, 0.76), Vector2(1.7, 0.58)],
	[Vector2(1.44, 0.56), Vector2(1.47, 0.9), Vector2(1.53, 1.3), Vector2(1.63, 1.36), Vector2(1.7, 1.02), Vector2(1.72, 0.66)],
	[Vector2(1.46, 0.56), Vector2(1.47, 1.02), Vector2(1.54, 1.5), Vector2(1.67, 1.56), Vector2(1.76, 1.24), Vector2(1.78, 0.86)],
	[Vector2(1.48, 0.56), Vector2(1.5, 1.04), Vector2(1.6, 1.46), Vector2(1.76, 1.46), Vector2(1.87, 1.16), Vector2(1.94, 0.82)],
	[Vector2(1.5, 0.56), Vector2(1.54, 0.96), Vector2(1.66, 1.22), Vector2(1.83, 1.2), Vector2(1.97, 0.94), Vector2(2.12, 0.72)],
	[Vector2(1.52, 0.56), Vector2(1.58, 0.82), Vector2(1.72, 0.96), Vector2(1.88, 0.92), Vector2(2.03, 0.68), Vector2(2.2, 0.48)],
	[Vector2(1.53, 0.56), Vector2(1.64, 0.72), Vector2(1.8, 0.82), Vector2(1.93, 0.68), Vector2(2.0, 0.42), Vector2(2.06, 0.16)],
	[Vector2(1.54, 0.56), Vector2(1.66, 0.7), Vector2(1.82, 0.81), Vector2(1.915, 0.64), Vector2(1.925, 0.36), Vector2(1.92, 0.08)],
	[Vector2(1.54, 0.56), Vector2(1.66, 0.7), Vector2(1.82, 0.81), Vector2(1.925, 0.66), Vector2(1.95, 0.38), Vector2(1.98, 0.1)],
	[Vector2(1.54, 0.56), Vector2(1.66, 0.7), Vector2(1.82, 0.81), Vector2(1.92, 0.65), Vector2(1.935, 0.37), Vector2(1.94, 0.09)],
]
## コマごとの、布の持ち上がりの丸み: 真ん中が上がり、両の耳は液の近くに残る（0 で布の幅じゅう同じ高さ）
const DOME := [0.0, 0.8, 0.8, 0.75, 0.7, 0.65, 0.5, 0.35, 0.08, 0.0, 0.0, 0.0]
## 布が上がるあいだに落ちるしずく: [落ち始めのコマ, 落ちるコマ数, 桶の前からの角, 落ちる所の r, 落ち始めの高さ]。落ちた所に輪が広がる
const DROPS := [[3, 2, -0.2, 1.56, 1.2], [4, 2, 0.17, 1.6, 1.42], [5, 2, -0.05, 1.62, 1.4], [5, 1, 0.26, 1.6, 1.1]]
const RING_FRAMES := 4       # 輪が広がるコマ数（最後の輪も、垂れきるコマより前に消える）
const SPLASH_STAGE := 8      # 布が桶の外を打つコマ

var player: Node3D           # main.gd が入れる
var craft: Node              # main.gd が入れる（だれかが染めたら、液の色を変える）
var main: Node               # main.gd が入れる
var _liquid: StandardMaterial3D
var _cloth: StandardMaterial3D
var _from := START
var _to := START
var _t := 1.0
var _thread: StandardMaterial3D
var _cloth_mi: MeshInstance3D
var _meshes := {}            # コマ → 布の形（一度作ったら使い回す）
var _stage := 0
var _goal := 0
var _frame := -1
var _tick := 0
var _check := 0.0
var _drops: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	# 染め液: 縁の少し下に張った、色のフェルト（つるつるにしない）
	_liquid = Look.felt(START, 2.0)
	var liq := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = R * 0.98
	lc.bottom_radius = R * 0.98
	lc.radial_segments = 72
	lc.height = 0.02
	liq.mesh = lc
	liq.material_override = _liquid
	liq.position.y = LIQUID_Y
	add_child(liq)
	# 液に沈めた、染めたフェルトの布（近づくと上がる。形はコマごとに _cloth_mesh が作る）
	_cloth = Look.felt(START, 1.5)
	_cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloth.vertex_color_use_as_albedo = true
	_thread = Look.felt(Color("EFE6D2"), 4.0)
	_thread.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloth_mi = MeshInstance3D.new()
	_cloth_mi.visible = false
	add_child(_cloth_mi)
	# しずくと、液の面に広がる輪
	var bead := SphereMesh.new()
	bead.radius = 0.045
	bead.height = 0.12
	bead.radial_segments = 8
	bead.rings = 4
	_ring_mat = Look.felt(START.lightened(0.25), 2.0)
	var loop := TorusMesh.new()
	loop.inner_radius = 0.86
	loop.outer_radius = 1.0
	loop.rings = 20
	loop.ring_segments = 4
	for d in DROPS:
		var drop := MeshInstance3D.new()
		drop.mesh = bead
		drop.material_override = _cloth
		drop.visible = false
		add_child(drop)
		_drops.append(drop)
		var ring := MeshInstance3D.new()
		ring.mesh = loop
		ring.material_override = _ring_mat
		ring.visible = false
		add_child(ring)
		_rings.append(ring)
	if craft:
		craft.happened.connect(_on_craft)


## あなたが人台（親の wardrobe.gd）に手が届く所で、桶を見下ろしているか
func can_use(p: Node3D) -> bool:
	return p.looks_down() and get_parent().near_and_facing(p)


## 案内の絵を出す所: あなたの側の桶の縁の上
func hint_at(p: Node3D) -> Vector3:
	var d := p.global_position - global_position
	d.y = 0
	return global_position + d.normalized() * R + Vector3.UP * (H + 0.35)


## だれかが染めた: 染め液と縁の布を、その人の染めた色（主の色から順に、染めた最初の部位の色）へ
func _on_craft(ev: Dictionary) -> void:
	if ev.get("kind") != "dye":
		return
	for h in ev.get("colors", []):
		if String(h) != "":
			_from = _liquid.albedo_color
			_to = Color(String(h))
			_t = 0.0
			return


func _process(dt: float) -> void:
	_check -= dt
	if _check <= 0.0:
		_check = Sense.CHECK
		_goal = POSES.size() - 1 if Sense.nearest(main, self, SENSE_R, get_parent().BACK_LIMIT) else 0
	if _stage != _goal:
		var f := Doll.frame_index()
		if f != _frame:
			_frame = f
			_step()
	if _t >= 1.0:
		return
	_t = minf(1.0, _t + dt / SOAK)
	var c := _from.lerp(_to, smoothstep(0.0, 1.0, _t))
	_liquid.albedo_color = c
	_cloth.albedo_color = c
	_ring_mat.albedo_color = c.lightened(0.25)


## 12 コマ／秒のコマごと: 上がるときは 1 コマずつ、沈むときは 2 コマに 1 つずつ
func _step() -> void:
	_tick += 1
	if _goal > _stage:
		_stage += 1
		if _stage == SPLASH_STAGE:
			_sound("stall_flap", -9.0)
	elif _goal < _stage and _tick % 2 == 0:
		_stage -= 1
	_cloth_mi.visible = _stage > 0
	if _stage > 0:
		_cloth_mi.mesh = _cloth_mesh(_stage)
	for i in DROPS.size():
		_show_drop(i)


## しずく i: 上がるあいだだけ落ちる。落ちたら輪が広がる（沈むあいだは出さない）
func _show_drop(i: int) -> void:
	var d: Array = DROPS[i]
	var up := _goal > 0
	var k := _stage - int(d[0])
	var fell := float(k) / float(d[1])
	var at := Vector3(sin(d[2]) * d[3], 0.0, cos(d[2]) * d[3])
	_drops[i].visible = up and k >= 0 and k < int(d[1])
	if _drops[i].visible:
		at.y = lerpf(d[4], LIQUID_Y, fell * fell)
		_drops[i].position = at
	var r := k - int(d[1])
	_rings[i].visible = up and r >= 0 and r < RING_FRAMES
	if _rings[i].visible:
		at.y = LIQUID_Y + 0.012
		_rings[i].position = at
		var size := 0.05 + 0.04 * r
		_rings[i].scale = Vector3(size, 0.35 * size, size)
		if r == 0:
			_sound("cook_pellet_0%d" % (i % 3 + 1), -15.0)


func _sound(name_: String, db: float) -> void:
	var audio = main.get_node_or_null("Audio") if main else null
	if audio:
		audio.kitchen(self, name_, db)


## コマ s の布の形。断面 POSES[s] をなめらかにつないで、桶の丸みに沿って横へ広げる。裾はぎざぎざ、両の耳に生成りのなみ縫い
func _cloth_mesh(s: int) -> ArrayMesh:
	if _meshes.has(s):
		return _meshes[s]
	var pose: Array = POSES[s]
	var line: Array[Vector2] = []
	for j in ROWS + 1:
		line.append(_along(pose, float(j) / ROWS))
	var grid := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var half := CLOTH_W * 0.5 / 1.8
	for j in ROWS + 1:
		var u := float(j) / ROWS
		for i in COLS + 1:
			var w := float(i) / COLS - 0.5
			var th := w * 2.0 * half
			var p := line[j]
			# ひだ: 縦に 5 本ほど。上の端は少なく、裾へ行くほど深い。谷は暗くして、布に見せる
			var wave := 0.65 * sin(w * 19.0 + 0.8 + s * 0.35) + 0.35 * sin(w * 43.0 + 2.1 - s * 0.2)
			var fold := wave * (0.008 + 0.022 * sin(minf(u * 1.3, 1.0) * PI * 0.5))
			var y: float = LIQUID_Y + (p.y - LIQUID_Y) * (1.0 - float(DOME[s]) * 4.0 * w * w)
			if j == ROWS and i % 2 == 1:
				y += 0.035
			grid.append(Vector3(sin(th) * (p.x + fold), y, cos(th) * (p.x + fold)))
			uvs.append(Vector2(float(i) / COLS * CLOTH_W, u * 1.4))
			var shade := 0.86 + 0.2 * wave
			cols.append(Color(shade, shade, shade))
	for j in ROWS + 1:
		for i in COLS + 1:
			var a := grid[j * (COLS + 1) + mini(i + 1, COLS)] - grid[j * (COLS + 1) + maxi(i - 1, 0)]
			var b := grid[mini(j + 1, ROWS) * (COLS + 1) + i] - grid[maxi(j - 1, 0) * (COLS + 1) + i]
			nrm.append(a.cross(b).normalized())
	for j in ROWS:
		for i in COLS:
			var o := j * (COLS + 1) + i
			idx.append_array([o, o + 1, o + COLS + 1, o + 1, o + COLS + 2, o + COLS + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = grid
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _cloth)
	# 耳のなみ縫い（布の少し外に、短い板）
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	for side: int in [1, COLS - 1]:
		for j in range(1, ROWS, 2):
			var q0 := j * (COLS + 1) + side
			var q1 := (j + 1) * (COLS + 1) + side
			var n0 := nrm[q0] * 0.006
			var wide := (grid[q0 + 1] - grid[q0]).normalized() * 0.012
			var a0 := grid[q0] + n0 - wide
			var b0 := grid[q0] + n0 + wide
			var a1 := grid[q0].lerp(grid[q1], 0.7) + n0 - wide
			var b1 := grid[q0].lerp(grid[q1], 0.7) + n0 + wide
			sv.append_array([a0, b0, a1, b0, b1, a1])
			for t in 6:
				sn.append(nrm[q0])
	var st := []
	st.resize(Mesh.ARRAY_MAX)
	st[Mesh.ARRAY_VERTEX] = sv
	st[Mesh.ARRAY_NORMAL] = sn
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st)
	mesh.surface_set_material(1, _thread)
	_meshes[s] = mesh
	return mesh


## 断面の点の並びを、なめらかにたどる（Catmull-Rom。u は 0〜1）
static func _along(p: Array, u: float) -> Vector2:
	var n := p.size() - 1
	var f := u * n
	var i := mini(int(f), n - 1)
	var t := f - i
	var a: Vector2 = p[maxi(i - 1, 0)]
	var b: Vector2 = p[i]
	var c: Vector2 = p[i + 1]
	var d: Vector2 = p[mini(i + 2, n)]
	return b.cubic_interpolate(c, a, d, t)
