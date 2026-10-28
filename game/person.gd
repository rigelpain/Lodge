extends Node3D

const Look := preload("res://look.gd")
## 人の形と動き。肌は紙、服はフェルト・毛糸・木綿。
## 形は spec（頭身・頭の形・目口鼻耳・関節の数・服）で組む。案を見比べるため、つまみを多めに持つ。
## 居場所（位置と向き）は毎フレームなめらか。姿勢（手足・体の揺れ・目・口・手袋の形）は 12 コマ／秒で刻み、コマの間は止める。
## 全員が同じ時計（物理のコマ数）でコマを変え、そのたびに形をわずかに崩す（クレイアニメの揺れ）。
## ソリや紐をつかむ手は、つかんだ物に対しての姿勢をコマで更新する（ソリが動いても手が離れて見えない）。
## 見た目だけ。持ち主（player.gd・bot.gd）が毎フレーム act などを入れる。通信には乗せない。

const FPS := 12
const HEIGHT := 1.6          # 帽子を除いた背の高さ (m)
const CADENCE := 2.0         # 歩く周期の上限（1 秒に何周）。12 コマで 6 コマ／周より速くしない
const BOIL_ROT := 0.03       # コマごとの形の崩れ（回転 rad）
const BOIL_SCALE := 0.03     # 同じく（大きさの割合）
const INK := Color(0.16, 0.12, 0.10)

enum Act { WALK, PUSH, ROPE, RIDE }

const DEFAULT := {
	"heads": 3.0,            # 頭身
	"head": "balloon",       # balloon 紙風船 / gem 折り紙の玉 / egg 卵 / flat 切り紙
	"depth": 1.0,            # 体の厚み（切り紙は薄く）
	"eyes": "move",          # none / ink 墨の点 / move 黒目が動く / slit 細い線 / arc 閉じた目
	"eye_size": 1.0,
	"mouth": "open",         # none / line / open 声で開く
	"nose": false,           # 折り目の鼻
	"ears": false,           # 紙の耳
	"cheeks": false,
	"arm_joints": 2,         # 1 肩だけ / 2 肘 / 3 肘と手首
	"leg_joints": 2,         # 1 股だけ / 2 膝
	"hand": "mitten",        # mitten 親指つき / ball 丸い手袋
	"fabric": "felt",        # felt / knit / cloth
	"coat": "long",          # long 長いコート / short 短い上着とズボン / poncho / yakko 奴さん / kimono 千代紙の着物
	"hat": "cone",           # none / cone / beanie / earflap 耳当て / hood フード / bear 耳つき / kabuto 兜 / kasa 菅笠 / kakumaki 角巻
	"scarf": false,
	"color": Color(0.85, 0.33, 0.31),
	"hair": "none",          # none / bob 黒い紙のおかっぱ
	"neck": 1.0,             # 首の長さの倍率
	"pattern": "seigaiha",   # 着物の芯の柄: seigaiha / kikko / ichimatsu / mizutama / koshi
	"inner": Color(0.95, 0.91, 0.82),   # 着物の芯の地の色
	"origami": false,        # 折り紙の形: 面に谷折り・山折りを入れ、手足は折った紙の棒
	"wear": 0.0,             # 使い込み 0〜1: 紙の体に折りじわと水のシミが増える
	"layers": 1,
}

var spec := {}

# 持ち主が毎フレーム入れる
var act := Act.WALK
var facing := Vector3.ZERO   # 体の向き（世界、水平）。ZERO なら持ち主の前
var gaze := Vector3.INF      # 見ている所（世界）。INF なら体の前
var effort := false          # 押している・引いている
var airborne := false
var waving := false          # 右手を上げて振る
var point := Vector3.INF     # 右手で指す所（世界）
var sled: Node3D = null
var grip := Vector3.INF      # つかんでいる立ち位置（ソリの座標）
var rope_hand := Vector3.INF # 紐を持つ右手の所（世界）
var lean := Vector2.ZERO     # 乗っているときの体重移動（x 右、y 前）
var demo_speed := -1.0       # 見比べ用: 速さと歩みの位相を決めうちにする
var demo_phase := 0.0

# 寸法
var hh := 0.5                # 頭の高さ
var leg := 0.6
var thigh := 0.3
var shin := 0.3
var torso := 0.5
var upper := 0.25
var fore := 0.25
var shoulder_w := 0.2
var hip_w := 0.1
var neck_h := 0.03

var _pelvis: Node3D
var _spine: Node3D
var _neck: Node3D
var _hip: Array[Node3D] = []
var _knee: Array[Node3D] = []
var _shoulder: Array[Node3D] = []
var _elbow: Array[Node3D] = []
var _wrist: Array[Node3D] = []
var _mitt: Array[MeshInstance3D] = []
var _eyes: Array[Node3D] = []
var _pupils: Array[MeshInstance3D] = []
var _lids: Array[MeshInstance3D] = []   # まばたきでつぶる目（墨の点）
var _foot: Array[Node3D] = []
var _sleeves: Array[Node3D] = []
var _limbs: Array = []             # 手足ひとつずつ [MeshInstance3D, 太さの元, 太さの先, 腕か]。肩（股）から手首（足首）まで一本の筒   # 袂。腕の途中から、いつも下へ垂れる
var _next_blink := 0
var _mouth: MeshInstance3D
var _tails: Array[Node3D] = []
var _parts: Array[MeshInstance3D] = []
var _rest: Array[Transform3D] = []
var _shape := {}             # 部品 → コマごとの形（手袋を握る、口を開く）
var _hold: Array = [null, null]   # 手ごとに [基準のノード, その座標での手の所] か null
var _breath: CPUParticles3D
var _mats := {}

var _frame := -1
var _yaw := 0.0
var _last := Vector3.INF
var _speed := 0.0
var _phase := 0.0
var _voice := 0              # 声を出している残りのコマ
var _next_breath := 0        # 次に息を吐くコマ
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var s := DEFAULT.duplicate()
	s.merge(spec, true)
	spec = s
	top_level = true
	_measure()
	_build()
	_next_breath = randi_range(4, 30)


## 全員が同じ時計で刻むコマの番号
static func frame_index() -> int:
	return Engine.get_physics_frames() * FPS / Engine.physics_ticks_per_second


## 声を出す（言葉にならない声）。口が開き、大きな白い息が出る
func call_out() -> void:
	_voice = 7


# ---------------------------------------------------------------- 形

func _measure() -> void:
	var heads: float = spec.heads
	hh = HEIGHT / heads
	var body := HEIGHT - hh
	neck_h = (0.02 + body * 0.02) * float(spec.neck)
	leg = (body - neck_h) * (0.47 + 0.04 * (heads - 2.5) / 2.5)
	torso = body - leg - neck_h
	var foot := 0.07
	if spec.leg_joints >= 2:
		thigh = (leg - foot) * 0.5
		shin = leg - foot - thigh
	else:
		thigh = leg - foot
		shin = 0.0
	var arm := torso * (0.9 + 0.12 * (heads - 2.5))
	upper = arm * 0.5 if spec.arm_joints >= 2 else arm
	fore = arm - upper if spec.arm_joints >= 2 else 0.0
	shoulder_w = 0.07 + torso * 0.3
	hip_w = 0.04 + torso * 0.14


func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	if key.ends_with("_ds"):
		# 両面を見せる紙や布の一枚もの
		var d: BaseMaterial3D = _mat(key.trim_suffix("_ds")).duplicate()
		d.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = d
		return d
	var c: Color = spec.color
	var m: Material
	match key:
		"coat":
			m = _fabric(c)
		"trousers":
			m = _fabric(Color(0.26, 0.27, 0.31))
		"boots":
			m = Look.felt(Color(0.36, 0.27, 0.22), 3.0)
		"cream":
			m = Look.felt(Color(0.95, 0.92, 0.84), 3.0)
		"scarf":
			m = Look.knit(Color(0.93, 0.86, 0.66), 12.0)
		"mitt":
			m = Look.felt(c.darkened(0.08), 4.0)
		"paper":
			m = Look.paper()
		"white":
			m = Look.paper(Color(0.99, 0.98, 0.95))
		"cheek":
			m = Look.felt(Color(0.94, 0.62, 0.58), 4.0)
		"pattern":
			var inner: Color = spec.inner
			m = Look.wagara(spec.pattern, inner, c.darkened(0.15) if inner.get_luminance() > 0.5 else inner.lightened(0.55), 5.0)
		"obi":
			m = Look.felt(Color(0.84, 0.67, 0.3), 3.0)
		"hair":
			m = Look.paper(Color(0.15, 0.14, 0.15))
		"kasa":
			m = Look.cloth(Color(0.88, 0.82, 0.7), 8.0)
		"shawl":
			m = Look.wagara("koshi", c.lightened(0.35), c.darkened(0.25), 3.0)
		"ink":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = INK
			sm.roughness = 0.9
			m = sm
	if m is BaseMaterial3D:
		(m as BaseMaterial3D).vertex_color_use_as_albedo = true   # 折った面ごとの明るさの違い
	_mats[key] = m
	return m


func _fabric(c: Color) -> Material:
	match spec.fabric:
		"knit":
			return Look.knit(c)
		"cloth":
			return Look.cloth(c)
	return Look.felt(c, 2.0)


## 型の形を平らな面（折り紙の角）にして、大きさと向きを焼き込む。puff で箱を紙風船のようにふくらませる
static func bake(src: PrimitiveMesh, xf := Transform3D.IDENTITY, puff := 0.0) -> ArrayMesh:
	var arr := src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var n := idx.size() if idx.size() > 0 else verts.size()
	for k in n:
		var v: Vector3 = verts[idx[k]] if idx.size() > 0 else verts[k]
		if puff > 0.0:
			var mx := maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
			v = v.lerp(v.normalized() * mx * 1.25, puff)
		v = xf * v
		st.set_uv(Vector2(v.x + v.z, v.y))
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func cyl(r_top: float, r_bot: float, h: float, sides := 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = sides
	c.rings = 0
	return c


static func ball(sides := 8, rings := 4) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = sides
	s.rings = rings
	return s


## 三角形の並びから、折った紙の形を作る。tris は [a, b, c, 外向き] の並び。
## 面ごとに明るさを少し変え（光の当たり方の違いで折り目が見える）、wear で折りじわと水のシミを足す
static func fold(tris: Array, xf := Transform3D.IDENTITY, tint := 0.05, wear := 0.0, seed := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var list := tris
	if wear > 0.0:
		# 一度細かく割って、折りじわのぶん頂点を内外へずらす（同じ所は同じだけずらす）
		var fine := []
		for t in tris:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c: Vector3 = t[2]
			var ab := (a + b) * 0.5
			var bc := (b + c) * 0.5
			var ca := (c + a) * 0.5
			fine.append_array([[a, ab, ca, t[3]], [ab, b, bc, t[3]], [ca, bc, c, t[3]], [ab, bc, ca, t[3]]])
		list = []
		var size := 0.0
		for t in fine:
			size = maxf(size, (t[0] as Vector3).distance_to(t[1]))
		for t in fine:
			var q := []
			for k in 3:
				var v: Vector3 = t[k]
				var h := _hash01(v.snapped(Vector3.ONE * 0.0005), seed)
				q.append(v + (t[3] as Vector3).normalized() * (h - 0.5) * size * 0.9 * wear)
			q.append(t[3])
			list.append(q)
	for k in list.size():
		var t: Array = list[k]
		var a: Vector3 = xf * (t[0] as Vector3)
		var b: Vector3 = xf * (t[1] as Vector3)
		var c: Vector3 = xf * (t[2] as Vector3)
		var out: Vector3 = xf.basis * (t[3] as Vector3)
		var n := (b - a).cross(c - a)
		if n.length() < 1e-9:
			continue
		if n.dot(out) < 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		n = n.normalized()
		var mid := (a + b + c) / 3.0
		var shade := 1.0 + tint * (_hash01(mid.snapped(Vector3.ONE * 0.001), seed + 7) * 2.0 - 1.0)
		var col := Color(shade, shade, shade)
		if wear > 0.0 and _hash01(mid.snapped(Vector3.ONE * 0.035), seed + 13) < wear * 0.3:
			col = Color(shade * 0.8, shade * 0.82, shade * 0.88)   # 水のシミ: 乾いたあとの少し灰色がかった跡
		# Godot の表は時計回り
		for v in [a, c, b]:
			st.set_normal(n)
			st.set_color(col)
			st.set_uv(Vector2(v.x + v.z, v.y))
			st.add_vertex(v)
	return st.commit()


static func _hash01(v: Vector3, seed: int) -> float:
	return float(hash([v, seed]) % 100003) / 100003.0


## 箱を折った形。各面の真ん中を bulge だけ外（負なら内）へ出し、対角に折り目が入る（紙風船）
static func fold_box(size: Vector3, bulge := 0.08) -> Array:
	var tris := []
	for ax in 3:
		for sg in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sg
			var u := Vector3.ZERO
			u[(ax + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(ax + 2) % 3] = 1.0
			var cs := []
			for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				cs.append((n * 0.5 + u * p.x * 0.5 + v * p.y * 0.5) * size)
			var c := n * (0.5 + bulge) * size
			for i in 4:
				tris.append([c, cs[i], cs[(i + 1) % 4], n])
	return tris


## 角錐台を折った形。crease で各面の真ん中に谷折りを入れる。rot で角の向きを回す
static func fold_frustum(r_top: float, r_bot: float, h: float, sides := 4, crease := 0.0, rot := 0.0, caps := true) -> Array:
	var tris := []
	for i in sides:
		var a0 := rot + TAU * i / sides
		var a1 := rot + TAU * (i + 1) / sides
		var am := (a0 + a1) * 0.5
		var out := Vector3(cos(am), 0, sin(am))
		var t0 := Vector3(cos(a0) * r_top, h * 0.5, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, h * 0.5, sin(a1) * r_top)
		var b0 := Vector3(cos(a0) * r_bot, -h * 0.5, sin(a0) * r_bot)
		var b1 := Vector3(cos(a1) * r_bot, -h * 0.5, sin(a1) * r_bot)
		if crease != 0.0:
			var tm := (t0 + t1) * 0.5 - out * crease * r_top
			var bm := (b0 + b1) * 0.5 - out * crease * r_bot
			tris.append_array([[t0, tm, bm, out], [t0, bm, b0, out], [tm, t1, b1, out], [tm, b1, bm, out]])
		else:
			tris.append_array([[t0, t1, b1, out], [t0, b1, b0, out]])
		if caps and r_top > 0.001:
			tris.append([Vector3(0, h * 0.5, 0), t0, t1, Vector3.UP])
		if caps and r_bot > 0.001:
			tris.append([Vector3(0, -h * 0.5, 0), b0, b1, Vector3.DOWN])
	return tris


## 双角錐（上下にとがった折り紙の玉）。前に面が来るよう回す
static func bipyramid(sides := 6, mid := 0.0) -> Array:
	var tris := []
	var top := Vector3(0, 0.5, 0)
	var bot := Vector3(0, -0.5, 0)
	for i in sides:
		var a0 := PI / 2 + PI / sides + TAU * i / sides
		var a1 := a0 + TAU / sides
		var p0 := Vector3(cos(a0) * 0.5, mid, sin(a0) * 0.5)
		var p1 := Vector3(cos(a1) * 0.5, mid, sin(a1) * 0.5)
		var am := (a0 + a1) * 0.5
		var out := Vector3(cos(am), 0, sin(am))
		tris.append([top, p0, p1, out + Vector3.UP * 0.5])
		tris.append([bot, p0, p1, out + Vector3.DOWN * 0.5])
	return tris


func _origami() -> bool:
	return spec.origami


func _wear_for(mat_key: String) -> float:
	return float(spec.wear) if mat_key == "paper" else 0.0


## 角錐台（袖・脚・胴・帽子）。折り紙なら折った面、そうでなければ平らな面の円柱
func _frustum(r_top: float, r_bot: float, h: float, sides: int, xf: Transform3D, mat_key: String, crease := 0.0, rot := 0.0) -> ArrayMesh:
	if _origami():
		var k := 1.0 / cos(PI / sides)   # 面までの距離を円柱とそろえる
		return fold(fold_frustum(r_top * k, r_bot * k, h, sides, crease, rot), xf, 0.06, _wear_for(mat_key), _parts.size())
	return bake(cyl(r_top, r_bot, h, sides), xf)


## 箱の小物（手袋・靴・飾り）。xf の大きさは単位の箱に対して
func _block(xf: Transform3D, mat_key: String, puff := 0.45) -> ArrayMesh:
	if _origami():
		return fold(fold_box(Vector3.ONE, 0.06), xf, 0.06, _wear_for(mat_key), _parts.size())
	return bake(BoxMesh.new(), xf, puff)


func _add_limb(parent: Node3D, mat_key: String, r0: float, r1: float, is_arm: bool) -> void:
	var m := MeshInstance3D.new()
	m.material_override = _mat(mat_key)
	m.layers = spec.layers
	parent.add_child(m)
	_limbs.append([m, r0, r1, is_arm, _wear_for(mat_key)])


## 手足を、いまの関節の位置で一本の筒に作り直す（コマごとの置き換え）。関節は折り目になる
func _rebuild_limbs() -> void:
	var ai := 0
	var li := 0
	for limb in _limbs:
		var pts: Array[Vector3] = []
		if limb[3]:
			var sh := _shoulder[ai]
			var el := sh.transform * _elbow[ai].transform
			var wr := el * _wrist[ai].position
			var inward := Vector3(-sh.position.x * 0.45, 0.01, 0)
			pts = [sh.position + inward, sh.position, el.origin, wr + (wr - el.origin).normalized() * 0.02]
			ai += 1
		else:
			var hp := _hip[li]
			var kn := hp.transform * _knee[li].transform
			var an := kn * _foot[li].position
			pts = [hp.position + Vector3(0, 0.06, 0), hp.position, kn.origin, an + Vector3(0, 0.01, 0)]
			li += 1
		(limb[0] as MeshInstance3D).mesh = _tube(pts, limb[1], limb[2], 4 if _origami() else 6, limb[4])


## 折れ線に沿った角筒。継ぎ目の断面は二つの向きのあいだに置き、少し太らせてつなぐ
func _tube(pts: Array[Vector3], r0: float, r1: float, sides: int, wear: float) -> ArrayMesh:
	var n := pts.size()
	var total := 0.0
	for k in n - 1:
		total += pts[k].distance_to(pts[k + 1])
	var rings := []
	var u := Vector3.ZERO
	var run := 0.0
	for k in n:
		var t_in := (pts[k] - pts[k - 1]).normalized() if k > 0 else (pts[1] - pts[0]).normalized()
		var t_out := (pts[k + 1] - pts[k]).normalized() if k < n - 1 else t_in
		var t := (t_in + t_out).normalized() if (t_in + t_out).length() > 0.01 else t_out
		if k > 0:
			run += pts[k].distance_to(pts[k - 1])
		var miter := 1.0 / maxf(t_in.dot(t), 0.6)
		if u == Vector3.ZERO:
			u = t.cross(Vector3.FORWARD if absf(t.z) < 0.9 else Vector3.RIGHT).normalized()
		u = (u - t * u.dot(t)).normalized()
		var v := t.cross(u)
		var r := lerpf(r0, r1, run / maxf(total, 0.001)) * miter
		var ring := []
		for a in sides:
			var ang := TAU * (a + 0.5) / sides
			ring.append(pts[k] + (u * cos(ang) + v * sin(ang)) * r)
		rings.append(ring)
	var tris := []
	for k in n - 1:
		for a in sides:
			var b := (a + 1) % sides
			var p00: Vector3 = rings[k][a]
			var p01: Vector3 = rings[k][b]
			var p10: Vector3 = rings[k + 1][a]
			var p11: Vector3 = rings[k + 1][b]
			var c := (pts[k] + pts[k + 1]) * 0.5
			var out := (p00 + p01 + p10 + p11) * 0.25 - c
			tris.append([p00, p01, p11, out])
			tris.append([p00, p11, p10, out])
	var end: Array = rings[n - 1]
	var tip := pts[n - 1]
	for a in sides:
		tris.append([tip, end[a], end[(a + 1) % sides], tip - pts[n - 2]])
	return fold(tris, Transform3D.IDENTITY, 0.05, wear, 9)


## 一枚の布や紙（四隅の順に）。対角で少し折れる。両面を見せる材質で使う
func _sheet(parent: Node3D, corners: Array, mat_key: String) -> MeshInstance3D:
	var p0: Vector3 = corners[0]
	var p1: Vector3 = corners[1]
	var p2: Vector3 = corners[2]
	var n := (p1 - p0).cross(p2 - p0)
	var tris := [[p0, p1, p2, n], [p0, p2, corners[3], n]]
	return _part(parent, fold(tris, Transform3D.IDENTITY, 0.05), mat_key)


func _part(parent: Node3D, mesh: Mesh, mat_key: String, pos := Vector3.ZERO, basis := Basis.IDENTITY) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = _mat(mat_key)
	m.transform = Transform3D(basis, pos)
	m.layers = spec.layers
	parent.add_child(m)
	_parts.append(m)
	_rest.append(m.transform)
	return m


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build() -> void:
	var dz: float = spec.depth
	var w := hh * 0.92
	var coat: String = spec.coat
	_pelvis = _node(self, Vector3(0, leg, 0))
	_spine = _node(_pelvis, Vector3(0, 0.0, 0))

	# 胴（上着）
	var r_sh := shoulder_w * 0.95
	match coat:
		"long":
			var hem := leg * 0.5
			var h := torso + hem
			_part(_spine, _frustum(r_sh * 0.85, r_sh * 1.45, h, 4 if _origami() else 8, Transform3D(Basis.from_scale(Vector3(1, 1, 0.8 * dz)), Vector3(0, torso - h * 0.5, 0)), "coat", 0.14, PI / 4), "coat")
		"short":
			var h := torso + 0.08
			_part(_spine, _frustum(r_sh * 0.9, r_sh * 1.15, h, 4 if _origami() else 8, Transform3D(Basis.from_scale(Vector3(1, 1, 0.8 * dz)), Vector3(0, torso - h * 0.5, 0)), "coat", 0.14, PI / 4), "coat")
		"poncho":
			_part(_spine, _frustum(r_sh * 0.7, r_sh * 0.95, torso, 6, Transform3D(Basis.from_scale(Vector3(1, 1, 0.75 * dz)), Vector3(0, torso * 0.5, 0)), "trousers"), "trousers")
			var h := torso * 0.95
			_part(_spine, _frustum(r_sh * 0.5, r_sh * 1.75, h, 4 if _origami() else 8, Transform3D(Basis.from_scale(Vector3(1, 1, 0.85 * dz)), Vector3(0, torso + 0.02 - h * 0.5, 0)), "coat", 0.1, 0.0), "coat")
		"kimono":
			# 千代紙の着物: 柄の芯の上にフェルトの羽織を重ねる。襟は斜めに折って V に重ね、金の帯を締める。
			# 腰から下は、折りひだの入った大きな円錐が地面まで広がる（紙を何枚も重ねて折った裾）
			var rt := r_sh * 0.9
			var zf := 0.8 * dz
			_part(_spine, _frustum(rt * 0.95, rt * 0.85, torso, 6, Transform3D(Basis.from_scale(Vector3(1, 1, zf)), Vector3(0, torso * 0.5, 0)), "pattern", 0.08, PI / 6), "pattern")
			var sk := leg - 0.06
			_part(_pelvis, _frustum(rt * 0.85, rt * 1.75, sk, 8, Transform3D(Basis.from_scale(Vector3(1, 1, 0.85 * dz)), Vector3(0, -sk * 0.5 + 0.02, 0)), "pattern", 0.2, PI / 8), "pattern")
			# 裾の上に重なる羽織の一枚: 前は開いて柄がのぞく
			var ok := sk * 0.8
			_part(_pelvis, _frustum(rt * 0.95, rt * 1.95, ok, 8, Transform3D(Basis.from_scale(Vector3(1, 1, 0.9 * dz)), Vector3(0, -ok * 0.5 + 0.03, 0.02)), "coat", 0.24, PI / 8), "coat")
			_part(_spine, _frustum(rt * 1.0, rt * 0.97, torso * 0.24, 6, Transform3D(Basis.from_scale(Vector3(1, 1, zf * 1.02)), Vector3(0, torso * 0.2, 0)), "obi", 0.0, PI / 6), "obi")
			var fz := -rt * zf          # 胴の前の面
			for k in 2:
				var sd := -1.0 if k == 0 else 1.0   # 左（-x）の身頃を上に重ねる
				var lift := -0.01 if sd < 0 else -0.004
				var a := Vector3(sd * hh * 0.09, torso + 0.02, fz * 0.55 + lift)
				var b := Vector3(sd * rt * 1.06, torso - 0.01, fz * 0.15 + lift)
				var c2 := Vector3(sd * rt * 1.04, torso * 0.32, fz * 1.02 + lift)
				var d := Vector3(sd * rt * 0.05, torso * 0.33, fz * 1.05 + lift)
				_sheet(_spine, [a, b, c2, d], "coat_ds")
				# 重ね衿: 襟の内側にのぞくクリームの帯
				var cv := Vector3(-sd * 0.028, 0.0, -0.003)
				_sheet(_spine, [a + cv, a, d, d + cv], "cream_ds")
			_sheet(_spine, [Vector3(-rt * 1.06, torso, rt * zf * 0.4), Vector3(rt * 1.06, torso, rt * zf * 0.4), Vector3(rt * 1.0, torso * 0.3, rt * zf * 1.05), Vector3(-rt * 1.0, torso * 0.3, rt * zf * 1.05)], "coat_ds")
		"yakko":
			# 奴さん: 肩の張った上着（上が広い）と、すそが広がる袴
			_part(_spine, _frustum(r_sh * 1.25, r_sh * 0.8, torso, 4, Transform3D(Basis.from_scale(Vector3(1, 1, 0.7 * dz)), Vector3(0, torso * 0.5, 0)), "coat", 0.16, PI / 4), "coat")
			var hk := leg * 0.85
			_part(_pelvis, _frustum(r_sh * 0.8, r_sh * 1.5, hk, 4, Transform3D(Basis.from_scale(Vector3(1, 1, 0.75 * dz)), Vector3(0, -hk * 0.5 + 0.02, 0)), "trousers", 0.2, PI / 4), "trousers")
	# 首（紙）
	_part(_spine, _frustum(hh * 0.12, hh * 0.14, neck_h + 0.04, 6, Transform3D(Basis.IDENTITY, Vector3(0, torso + neck_h * 0.5, 0)), "paper"), "paper")

	# 脚。長いコートの下は紙の脚、短い上着はズボン。足もとはフェルトの長靴
	var leg_mat := "paper" if coat != "short" else "trousers"
	if coat == "yakko" or coat == "kimono":
		leg_mat = "paper"
	var r_leg := 0.035 + torso * 0.07
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var hip := _node(_pelvis, Vector3(s * hip_w, 0, 0))
		var knee := _node(hip, Vector3(0, -thigh, 0))
		_add_limb(_pelvis, leg_mat, r_leg, r_leg * 0.8, false)
		var foot := _node(knee, Vector3(0, -shin, 0))
		var bx := Vector3(r_leg * 2.3, 0.09, r_leg * 2.0 + 0.1)
		_part(foot, _block(Transform3D(Basis.from_scale(bx), Vector3(0, -0.045, -0.03)), "boots", 0.35), "boots")
		_hip.append(hip)
		_knee.append(knee)
		_foot.append(foot)

	# 腕（袖）と手袋
	var r_arm := 0.03 + torso * 0.06
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var sh := _node(_spine, Vector3(s * shoulder_w, torso - r_arm * 0.8, 0))
		if coat == "kimono":
			# 袂: 腕から下がる大きな一枚。少しだけ外へ開く。腕を上げても重さで下へ垂れる
			var a := upper * 1.1
			var ox := s * r_arm * 0.6
			var sl := _node(_spine, sh.position)
			_sleeves.append(sl)
			_sheet(sl, [Vector3(ox, 0.02, -a * 0.28), Vector3(ox + s * a * 0.12, -a * 1.05, -a * 0.3), Vector3(ox + s * a * 0.16, -a * 1.15, a * 0.32), Vector3(ox, -0.02, a * 0.3)], "coat_ds")
		if coat == "yakko":
			# 奴さんの四角い袖: 平たい板が肩から下がる
			var sw := r_arm * 3.2
			_part(sh, _block(Transform3D(Basis.from_scale(Vector3(0.05, upper * 1.05, sw)), Vector3(s * 0.01, -upper * 0.5, 0)), "coat"), "coat")
		var el := _node(sh, Vector3(0, -upper, 0))
		_add_limb(_spine, "coat", r_arm, r_arm * 0.85, true)
		var wr := _node(el, Vector3(0, -fore, 0))
		var mr := r_arm * 1.25 + 0.02
		var mitt: MeshInstance3D
		if spec.hand == "ball":
			mitt = _part(wr, bake(ball(7, 4), Transform3D(Basis.from_scale(Vector3(mr * 2.0, mr * 2.2, mr * 2.0 * maxf(dz, 0.6))), Vector3(0, -mr, 0))), "mitt")
		else:
			mitt = _part(wr, _block(Transform3D(Basis.from_scale(Vector3(mr * 1.5, mr * 2.4, mr * 1.9 * maxf(dz, 0.6))), Vector3(0, -mr * 1.2, 0)), "mitt"), "mitt")
			# 親指は体の前の側
			var th := MeshInstance3D.new()
			th.mesh = _block(Transform3D(Basis(Vector3.RIGHT, 0.5).scaled(Vector3(mr * 0.7, mr * 1.1, mr * 0.7)), Vector3(-s * mr * 0.25, -mr * 0.7, -mr * 0.85)), "mitt")
			th.material_override = _mat("mitt")
			th.layers = spec.layers
			mitt.add_child(th)
		_shoulder.append(sh)
		_elbow.append(el)
		_wrist.append(wr)
		_mitt.append(mitt)

	# 頭
	_neck = _node(_spine, Vector3(0, torso + neck_h, 0))
	var head_mesh: ArrayMesh
	var wear: float = spec.wear
	match spec.head if not _origami() else "o_" + str(spec.head):
		"o_balloon":
			# 紙風船: 面の真ん中がふくらみ、対角に折り目
			head_mesh = fold(fold_box(Vector3.ONE, 0.12), Transform3D(Basis.from_scale(Vector3(w, hh, w * dz) * 0.86), Vector3(0, hh * 0.5, 0)), 0.07, wear, 1)
		"o_egg", "egg":
			head_mesh = bake(ball(10, 6), Transform3D(Basis.from_scale(Vector3(w * 0.86, hh, w * 0.84 * dz)), Vector3(0, hh * 0.5, 0)))
		"o_plate", "plate":
			# 紙の顔: 平たい楕円の板（人形の顔）
			head_mesh = fold(fold_frustum(0.5 / cos(PI / 10), 0.5 / cos(PI / 10), 1.0, 10, 0.0, 0.0), Transform3D(Basis(Vector3.RIGHT, PI / 2).scaled(Vector3(w * 0.8, hh, w * 0.56)), Vector3(0, hh * 0.5, 0)), 0.04, wear, 4)
		"o_gem":
			# 折り紙の玉: 上下にとがった六角の双角錐
			head_mesh = fold(bipyramid(6, -0.04), Transform3D(Basis.from_scale(Vector3(w * 1.05, hh, w * 0.95 * dz)), Vector3(0, hh * 0.5, 0)), 0.07, wear, 2)
		"o_flat":
			head_mesh = fold(fold_frustum(0.5 / cos(PI / 8), 0.5 / cos(PI / 8), 1.0, 8, 0.0, PI / 8), Transform3D(Basis(Vector3.RIGHT, PI / 2).scaled(Vector3(w, hh, maxf(dz, 0.3) * w)), Vector3(0, hh * 0.5, 0)), 0.07, wear, 3)
		"balloon":
			var bm := BoxMesh.new()
			bm.subdivide_width = 2
			bm.subdivide_height = 2
			bm.subdivide_depth = 2
			head_mesh = bake(bm, Transform3D(Basis.from_scale(Vector3(w, hh, w * dz) / 1.12), Vector3(0, hh * 0.5, 0)), 0.55)
		"gem":
			head_mesh = bake(ball(7, 4), Transform3D(Basis.from_scale(Vector3(w, hh, w * dz)), Vector3(0, hh * 0.5, 0)))
		"flat":
			head_mesh = bake(cyl(0.5, 0.5, 1.0, 8), Transform3D(Basis(Vector3.RIGHT, PI / 2).scaled(Vector3(w, hh, maxf(dz, 0.3) * w)), Vector3(0, hh * 0.5, 0)))
	_part(_neck, head_mesh, "paper")
	var faces := head_mesh.get_faces()

	# 顔。頭の表面に貼る
	var es: float = hh * 0.11 * float(spec.eye_size)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var at := Vector3(s * w * 0.2, hh * 0.53, 0)
		match spec.eyes:
			"ink":
				_lids.append(_stick(faces, at, Vector3.FORWARD, bake(cyl(0.5, 0.5, 1.0, 8), Transform3D(Basis.from_scale(Vector3(es * 0.8, 0.006, es * 1.1)))), "ink"))
			"arc":
				# 閉じた目: 下へ弧を描く細い墨の線
				var arc := []
				var r := es * 0.75
				for q in 6:
					var a0 := PI + 0.35 + (PI - 0.7) * q / 6.0
					var a1 := PI + 0.35 + (PI - 0.7) * (q + 1) / 6.0
					var o0 := Vector3(cos(a0) * r, 0, -sin(a0) * r - r * 0.5)
					var o1 := Vector3(cos(a1) * r, 0, -sin(a1) * r - r * 0.5)
					var i0 := o0 * 0.8 + Vector3(0, 0, -r * 0.1)
					var i1 := o1 * 0.8 + Vector3(0, 0, -r * 0.1)
					arc.append([o0, o1, i1, Vector3.UP])
					arc.append([o0, i1, i0, Vector3.UP])
				_stick(faces, at, Vector3.FORWARD, fold(arc, Transform3D.IDENTITY, 0.0), "ink")
			"slit":
				_stick(faces, at, Vector3.FORWARD, bake(BoxMesh.new(), Transform3D(Basis.from_scale(Vector3(es * 1.4, 0.006, es * 0.25)))), "ink")
			"move":
				var eye := _stick(faces, at, Vector3.FORWARD, bake(cyl(0.5, 0.5, 1.0, 10), Transform3D(Basis.from_scale(Vector3(es * 1.5, 0.006, es * 1.8)))), "white")
				var pu := MeshInstance3D.new()
				pu.mesh = bake(cyl(0.5, 0.5, 1.0, 8), Transform3D(Basis.from_scale(Vector3(es * 0.8, 0.006, es * 1.0))))
				pu.material_override = _mat("ink")
				pu.layers = spec.layers
				pu.position = Vector3(0, 0.005, 0)
				eye.add_child(pu)
				_eyes.append(eye)
				_pupils.append(pu)
		if spec.cheeks:
			_stick(faces, Vector3(s * w * 0.32, hh * 0.36, 0), Vector3.FORWARD, bake(cyl(0.5, 0.5, 1.0, 8), Transform3D(Basis.from_scale(Vector3(es * 1.3, 0.004, es * 0.9)))), "cheek")
		if spec.ears and spec.hat != "earflap":
			var ear := _stick(faces, Vector3(0, hh * 0.48, 0), Vector3(s, 0, 0), bake(cyl(0.5, 0.5, 1.0, 6), Transform3D(Basis.from_scale(Vector3(hh * 0.16, 0.012, hh * 0.24)), Vector3(0, 0.01, 0))), "paper")
			ear.position += Vector3(s * 0.01, 0, 0)
	match spec.mouth:
		"line":
			_stick(faces, Vector3(0, hh * 0.3, 0), Vector3.FORWARD, bake(BoxMesh.new(), Transform3D(Basis.from_scale(Vector3(hh * 0.12, 0.006, hh * 0.018)))), "ink")
		"open":
			_mouth = _stick(faces, Vector3(0, hh * 0.3, 0), Vector3.FORWARD, bake(cyl(0.5, 0.5, 1.0, 8), Transform3D(Basis.from_scale(Vector3(hh * 0.11, 0.006, hh * 0.09)))), "ink")
	if spec.nose:
		_stick(faces, Vector3(0, hh * 0.42, 0), Vector3.FORWARD, bake(PrismMesh.new(), Transform3D(Basis.from_scale(Vector3(hh * 0.07, hh * 0.08, hh * 0.05)), Vector3(0, hh * 0.03, 0))), "paper")

	# 髪: 黒い紙のおかっぱ。前髪と両脇で顔を縁取る
	if spec.hair == "bob":
		var hd := w * 0.56 if spec.head == "plate" else w * dz
		_part(_neck, _block(Transform3D(Basis.from_scale(Vector3(w * 1.0, hh * 0.92, hd * 1.0)), Vector3(0, hh * 0.6, hd * 0.32)), "hair"), "hair")
		_part(_neck, _block(Transform3D(Basis.from_scale(Vector3(w * 0.96, hh * 0.3, 0.03)), Vector3(0, hh * 0.9, -hd * 0.52)), "hair"), "hair")
		for sd in [-1.0, 1.0]:
			_part(_neck, _block(Transform3D(Basis.from_scale(Vector3(w * 0.16, hh * 0.78, hd * 0.75)), Vector3(sd * w * 0.47, hh * 0.52, -hd * 0.05)), "hair"), "hair")

	# 帽子・フード
	var top := hh
	match spec.hat:
		"cone":
			var ch := hh * 0.75
			_part(_neck, _frustum(0.0, w * 0.52, ch, 4 if _origami() else 8, Transform3D(Basis.from_scale(Vector3(1, 1, dz)), Vector3(0, top * 0.86 + ch * 0.5, 0)), "coat", 0.0, PI / 4), "coat")
			_part(_neck, _frustum(w * 0.55, w * 0.57, hh * 0.1, 8, Transform3D(Basis.from_scale(Vector3(1, 1, dz)), Vector3(0, top * 0.86, 0)), "cream"), "cream")
			_part(_neck, _block(Transform3D(Basis.from_scale(Vector3.ONE * hh * 0.17), Vector3(0, top * 0.86 + ch, 0)), "cream", 0.6), "cream")
		"kabuto":
			# 兜: 折り紙の兜の形をフェルトで。四角錐の鉢に、前へ反った二枚の角と、ひたいの折り返し
			var kh := hh * 0.5
			_part(_neck, _frustum(w * 0.12, w * 0.6, kh, 4, Transform3D(Basis.from_scale(Vector3(1, 1, dz)), Vector3(0, top * 0.82 + kh * 0.5, 0)), "coat", 0.0, PI / 4), "coat")
			for s in [-1.0, 1.0]:
				var horn := Basis(Vector3.FORWARD, -s * 0.5) * Basis(Vector3.RIGHT, -0.35)
				_part(_neck, _block(Transform3D(horn.scaled(Vector3(hh * 0.28, hh * 0.42, 0.025)), Vector3(s * w * 0.4, top * 0.95 + kh * 0.25, -w * 0.42 * dz)), "coat"), "coat")
			_part(_neck, _block(Transform3D(Basis(Vector3.RIGHT, 0.4).scaled(Vector3(w * 0.9, hh * 0.14, 0.025)), Vector3(0, top * 0.84, -w * 0.5 * dz)), "cream"), "cream")
		"beanie", "earflap", "bear":
			var bh := hh * 0.36
			_part(_neck, _frustum(w * 0.36, w * 0.56, bh, 6 if _origami() else 8, Transform3D(Basis.from_scale(Vector3(1, 1, dz)), Vector3(0, top * 0.8 + bh * 0.5, 0)), "coat", 0.1, PI / 6), "coat")
			_part(_neck, _frustum(w * 0.58, w * 0.6, hh * 0.13, 8, Transform3D(Basis.from_scale(Vector3(1, 1, dz)), Vector3(0, top * 0.8, 0)), "cream"), "cream" if spec.hat != "bear" else "coat")
			if spec.hat == "earflap":
				for s in [-1.0, 1.0]:
					_part(_neck, bake(BoxMesh.new(), Transform3D(Basis.from_scale(Vector3(0.03, hh * 0.38, hh * 0.3)), Vector3(s * w * 0.56, top * 0.62, 0)), 0.3), "coat")
			elif spec.hat == "bear":
				for s in [-1.0, 1.0]:
					_part(_neck, bake(cyl(0.5, 0.5, 1.0, 8), Transform3D(Basis(Vector3.RIGHT, PI / 2).scaled(Vector3(hh * 0.22, 0.05 * maxf(dz, 0.6), hh * 0.22)), Vector3(s * w * 0.36, top * 0.8 + bh + hh * 0.04, 0))), "coat")
			else:
				_part(_neck, _block(Transform3D(Basis.from_scale(Vector3.ONE * hh * 0.14), Vector3(0, top * 0.8 + bh + hh * 0.04, 0)), "cream", 0.6), "cream")
		"kasa":
			# 菅笠: 浅く広い円錐。放射状に折り目が入り、つばの向きで見ている先がわかる
			var kh := hh * 0.42
			_part(_neck, _frustum(0.0, w * 1.25, kh, 16, Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, top * 0.78 + kh * 0.5, -w * 0.06)), "kasa", 0.1, 0.0), "kasa_ds")
		"kakumaki":
			# 角巻: 四角い布を三角に折って頭からかぶる、雪国の防寒具。とがった角が背中へ垂れる
			var crown := Vector3(0, hh * 1.14, -w * 0.05)
			var lf := Vector3(-w * 0.72, hh * 0.55, -w * 0.42)
			var rf := Vector3(w * 0.72, hh * 0.55, -w * 0.42)
			var ls := Vector3(-w * 1.2, -hh * 0.45, -w * 0.15)
			var rs := Vector3(w * 1.2, -hh * 0.45, -w * 0.15)
			var back := Vector3(0, -hh * 0.75, w * 0.9)
			var tris := []
			for t in [[crown, lf, rf], [crown, lf, ls], [crown, ls, back], [crown, rf, rs], [crown, rs, back]]:
				var mid: Vector3 = (t[0] + t[1] + t[2]) / 3.0
				tris.append([t[0], t[1], t[2], mid - Vector3(0, hh * 0.4, 0)])
			_part(_neck, fold(tris, Transform3D.IDENTITY, 0.06), "shawl_ds")
		"hood":
			_part(_neck, bake(ball(8, 5), Transform3D(Basis.from_scale(Vector3(w * 1.2, hh * 1.18, w * 1.12 * dz)), Vector3(0, hh * 0.54, w * 0.3 * dz))), "coat")

	# マフラー: 首に巻き、端は背中へ垂れる。走るとなびく
	if spec.scarf:
		_part(_spine, bake(cyl(r_sh * 0.62, r_sh * 0.68, hh * 0.16, 8), Transform3D(Basis.from_scale(Vector3(1, 1, 0.85 * dz)), Vector3(0, torso + neck_h * 0.2, 0))), "scarf")
		for s in [-1.0, 1.0]:
			var tail := _node(_spine, Vector3(s * r_sh * 0.25, torso, r_sh * 0.55 * dz))
			_part(tail, bake(BoxMesh.new(), Transform3D(Basis.from_scale(Vector3(hh * 0.13, torso * 0.55, 0.025)), Vector3(0, -torso * 0.27, 0))), "scarf")
			_tails.append(tail)

	# 白い息。羊毛のような小さな玉が口からふわっと出て、ほどけて消える（世界の座標で流れる）
	_breath = CPUParticles3D.new()
	_breath.emitting = false
	_breath.one_shot = true
	_breath.amount = 10
	_breath.lifetime = 1.6
	_breath.explosiveness = 0.75
	_breath.direction = Vector3(0, 0.15, -1)
	_breath.spread = 14.0
	_breath.initial_velocity_min = 0.35
	_breath.initial_velocity_max = 0.6
	_breath.gravity = Vector3(0, 0.12, 0)
	_breath.damping_min = 0.4
	_breath.damping_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.4))
	_breath.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.97, 0.98, 1.0, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	_breath.color_ramp = ramp
	var puff := bake(ball(6, 3), Transform3D(Basis.from_scale(Vector3.ONE * 0.1)))
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.98, 0.98, 1.0)
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 1.0
	pm.rim_enabled = true
	pm.rim = 0.6
	puff.surface_set_material(0, pm)
	_breath.mesh = puff
	_breath.layers = 1   # 息は誰の画面にも映す（自分の息も一人称で見える）
	_breath.position = Vector3(0, hh * 0.3, -w * 0.5 * dz - 0.09)
	_neck.add_child(_breath)


## 頭の表面の、at から向き dir に進んで当たる所に部品を貼る（部品の y を面の外向きにそろえる）
func _stick(faces: PackedVector3Array, at: Vector3, dir: Vector3, mesh: Mesh, mat_key: String) -> MeshInstance3D:
	var from := at - dir * 0.0
	var hit := at + dir * hh * 0.5
	var nrm := dir
	var best := INF
	for k in range(0, faces.size(), 3):
		var a := faces[k]
		var b := faces[k + 1]
		var c := faces[k + 2]
		var p = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
		if p != null:
			var d: float = (p - from).length()
			if d < best:
				best = d
				hit = p
				var n := (b - a).cross(c - a).normalized()
				nrm = n if n.dot(dir) > 0.0 else -n
	var y := nrm
	var x := y.cross(Vector3.UP)
	if x.length() < 0.1:
		x = Vector3.RIGHT
	x = x.normalized()
	if x.dot(Vector3.RIGHT) < 0.0 and absf(dir.x) < 0.5:
		x = -x
	var z := x.cross(y).normalized()
	return _part(_neck, mesh, mat_key, hit + nrm * (0.003 + 0.012 * float(spec.wear)), Basis(x, y, z))


# ---------------------------------------------------------------- 動き

func _physics_process(dt: float) -> void:
	var host := get_parent() as Node3D
	var pos := host.global_position
	var b: Basis
	if act == Act.RIDE and sled:
		b = sled.global_basis.orthonormalized()
		_yaw = b.get_euler().y
	else:
		var f := facing if facing != Vector3.ZERO else -host.global_basis.z
		f.y = 0
		if f.length() > 0.01:
			_yaw = lerp_angle(_yaw, atan2(-f.x, -f.z), 1.0 - exp(-dt * 14.0))
		b = Basis(Vector3.UP, _yaw)
	global_transform = Transform3D(b, pos)

	# 歩みは進んだ道のりで刻む（足と地面のずれを小さく）
	if _last == Vector3.INF:
		_last = pos
	var d := pos - _last
	d.y = 0
	_last = pos
	var v := d.length() / dt
	if v > 25.0:
		v = 0.0
		d = Vector3.ZERO
	if demo_speed >= 0.0:
		_speed = demo_speed
		_phase = demo_phase
	else:
		_speed = lerpf(_speed, v, 1.0 - exp(-dt * 8.0))
		_phase += TAU * d.length() / maxf(_speed / CADENCE, 0.5)

	var f_i := frame_index()
	if f_i != _frame:
		_frame = f_i
		_pose()
		_boil()
	_hold_hands()


func _pose() -> void:
	var t := float(_frame) / FPS
	var hip_a := [0.0, 0.0]
	var knee_a := [0.05, 0.05]
	var swing := [0.0, 0.0]
	var elbow_a := [0.25, 0.25]
	var out := [0.14, 0.14]
	var pelvis_y := leg
	var pelvis_z := 0.0
	var bend := 0.02
	var twist := 0.0
	var roll := 0.0
	_hold = [null, null]
	var stride := maxf(_speed / CADENCE, 0.5)
	var amp := asin(clampf(stride / (4.0 * leg), 0.0, 0.77)) if _speed > 0.25 else 0.0
	var ph := _phase

	match act:
		Act.RIDE:
			# ソリに座る。脚は前へ投げ出して膝を立て、両手はソリの縁
			pelvis_y = 0.09
			for i in 2:
				hip_a[i] = 1.75 if spec.leg_joints >= 2 else 1.4
				knee_a[i] = 1.0 if spec.leg_joints >= 2 else 0.0
			bend = -lean.y * 0.35 + 0.05
			roll = -lean.x * 0.3
			if sled:
				var me: Vector3 = sled.to_local(global_position)
				for i in 2:
					var s := -1.0 if i == 0 else 1.0
					_hold[i] = [sled, Vector3(s * 0.68, 0.5, me.z - 0.1)]
		_:
			if airborne:
				for i in 2:
					hip_a[i] = 0.5 if i == 0 else 0.15
					knee_a[i] = 0.9
					swing[i] = -0.4
					out[i] = 0.6
			elif amp > 0.0:
				for i in 2:
					var p := ph + PI * i
					hip_a[i] = amp * sin(p)
					knee_a[i] = 0.08 + (0.45 + amp) * maxf(0.0, cos(p))
					swing[i] = -amp * 0.9 * sin(p)
					elbow_a[i] = 0.3 + 0.4 * minf(_speed / 6.0, 1.0)
				pelvis_y = leg * cos(amp * absf(sin(ph))) - 0.01
				bend = 0.05 + 0.025 * minf(_speed, 7.0)
				twist = 0.14 * amp * sin(ph)
			else:
				# 立ち止まり: 重心をゆっくり左右に移し、息で胸が少し上下する
				roll = 0.035 * sin(t * 1.4)
				pelvis_y = leg - 0.005 * (1.0 + sin(t * 2.2))
				hip_a = [0.03 * sin(t * 1.4), -0.03 * sin(t * 1.4)]

			if act == Act.PUSH and sled and grip != Vector3.INF:
				var pts := _grip_points()
				for i in 2:
					_hold[i] = [sled, pts[i]]
				pelvis_y = minf(pelvis_y, leg * 0.94)
				for i in 2:
					hip_a[i] = hip_a[i] * 0.7 - 0.22
					knee_a[i] += 0.2
				if effort and amp == 0.0:
					# 動かないソリを押している: 足を前後に踏ん張り、体がふるえる
					var k := 1.0 if (_frame / 6) % 2 == 0 else -1.0
					hip_a = [0.12 * k - 0.3, -0.12 * k - 0.35]
					knee_a = [0.35, 0.1]
				bend = _push_bend(pts, pelvis_y)
			elif act == Act.ROPE:
				if rope_hand != Vector3.INF:
					_hold[1] = [self, to_local(rope_hand)]
				if effort:
					bend += 0.3

	if point != Vector3.INF and _hold[1] == null:
		# 右腕を伸ばして指す（腕で指す。指は分けない）
		_hold[1] = [self, to_local(_shoulder[1].global_position + (point - _shoulder[1].global_position).normalized() * (upper + fore) * 0.97)]
	elif waving and _hold[1] == null:
		# 右手を上げて振る。4 コマで 1 往復
		var k: float = [0.55, 0.1, -0.35, 0.1][_frame % 4]
		swing[1] = 0.2
		out[1] = 2.5 if spec.arm_joints >= 2 else 2.2 + k * 0.6
		elbow_a[1] = 0.0
		_elbow[1].basis = Basis.from_euler(Vector3(0.15, 0, k * 0.9)) if spec.arm_joints >= 2 else Basis.IDENTITY

	_pelvis.position = Vector3(0, pelvis_y, pelvis_z)
	_spine.basis = Basis.from_euler(Vector3(-bend, twist, roll))
	for i in 2:
		_hip[i].basis = Basis.from_euler(Vector3(hip_a[i], 0, 0))
		_knee[i].basis = Basis.from_euler(Vector3(-knee_a[i], 0, 0)) if spec.leg_joints >= 2 else Basis.IDENTITY
		# 足首: 靴底を地面にそろえ、後ろへ残った足はつま先で蹴る
		var k_eff: float = knee_a[i] if spec.leg_joints >= 2 else 0.0
		var ankle: float = -(hip_a[i] - k_eff)
		if act != Act.RIDE and hip_a[i] < -0.15:
			ankle += (hip_a[i] + 0.15) * 0.8
		_foot[i].basis = Basis.from_euler(Vector3(ankle, 0, 0))
		var s := -1.0 if i == 0 else 1.0
		if _hold[i] == null:
			_shoulder[i].basis = Basis.from_euler(Vector3(swing[i], 0, s * out[i]))
			if not (waving and i == 1):
				_elbow[i].basis = Basis.from_euler(Vector3(elbow_a[i], 0, 0)) if spec.arm_joints >= 2 else Basis.IDENTITY
			_wrist[i].basis = Basis.from_euler(Vector3(0.15, 0, 0)) if spec.arm_joints >= 3 else Basis.IDENTITY
		_shape[_mitt[i]] = Vector3(1.05, 0.82, 1.1) if _hold[i] != null else Vector3.ONE

	_place_sleeves()
	_rebuild_limbs()

	# 頭は見ている所へ。届かない分は黒目で
	var look := gaze
	var head_w := _neck.global_position + Vector3.UP * hh * 0.5
	if look == Vector3.INF:
		look = head_w + global_basis * Vector3(0, -0.1, -1)
	var ld := global_basis.inverse() * (look - head_w).normalized()
	var yaw := clampf(atan2(-ld.x, -ld.z), -1.1, 1.1)
	var pitch := clampf(atan2(ld.y, Vector2(ld.x, ld.z).length()), -0.6, 0.5)
	if _voice > 0:
		pitch = minf(pitch + 0.3, 0.6)   # 声を出すときは少し見上げる
	_neck.basis = Basis.from_euler(Vector3(pitch + bend * 0.75, yaw - twist, -roll * 0.5))
	var hd := (_neck.global_basis.inverse() * (look - head_w)).normalized()
	for k in _pupils.size():
		var e := _eyes[k]
		var pd := e.basis.inverse() * hd   # 目の座標: x 右、z 上、y 外
		var es: float = hh * 0.11 * float(spec.eye_size)
		_pupils[k].position = Vector3(clampf(pd.x * 1.4, -1.0, 1.0) * es * 0.38, 0.005, clampf(pd.z * 1.4, -1.0, 1.0) * es * 0.45)

	# まばたき: ときどき 1 コマだけ目をつぶる
	var blink := _frame >= _next_blink
	if blink:
		_next_blink = _frame + _rng.randi_range(30, 70)
	for lid in _lids:
		_shape[lid] = Vector3(1.3, 1.0, 0.12) if blink else Vector3.ONE

	# マフラーの端は速さでなびく
	for tail in _tails:
		tail.basis = Basis.from_euler(Vector3(minf(_speed * 0.12, 1.1) + 0.05 * sin(t * 5.0 + tail.position.x * 20.0), 0, 0))

	# 声と白い息
	if _mouth:
		_shape[_mouth] = Vector3(1.0, 1.0, 1.0 if _voice > 0 else (0.35 if effort else 0.18))
	if _voice > 0:
		if _voice == 7:
			_puff(1.35, 1.0)
		_voice -= 1
	elif _frame >= _next_breath:
		_puff(1.0, 0.5)
		_next_breath = _frame + (22 if effort else 38) + _rng.randi_range(-4, 4)


func _puff(size: float, speed: float) -> void:
	_breath.scale_amount_min = size
	_breath.scale_amount_max = size * 1.2
	_breath.initial_velocity_min = 0.3 * speed + 0.15
	_breath.initial_velocity_max = 0.55 * speed + 0.2
	_breath.amount = 8 if size < 1.5 else 16
	_breath.restart()


## つかんでいる立ち位置から、ソリの縁に置く両手の所（ソリの座標）
func _grip_points() -> Array:
	var hx: float = sled.HALF.x
	var hz: float = sled.HALF.y
	var g := grip
	var e := Vector3(clampf(g.x, -hx, hx), 0, clampf(g.z, -hz, hz))
	var inward := e - g
	inward.y = 0
	inward = inward.normalized() if inward.length() > 0.01 else Vector3.FORWARD
	var right := inward.cross(Vector3.UP)
	var pts := []
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var p := e + right * s * 0.24
		p.x = clampf(p.x, -hx, hx)
		p.z = clampf(p.z, -hz, hz)
		if p.z > hz - 0.25:
			p.y = 0.95   # 背もたれの上
			p.z = 1.3
		else:
			p.y = 0.48   # 台の縁
		pts.append(p)
	return pts


## 両手が縁に届くまで前にかがむ角
func _push_bend(pts: Array, pelvis_y: float) -> float:
	var reach := (upper + fore) * 0.95 + 0.05
	var bend := 0.15
	while bend < 1.25:
		var ok := true
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var tgt := to_local(sled.to_global(pts[i]))
			var sh := Vector3(s * shoulder_w, pelvis_y + torso * cos(bend), -torso * sin(bend))
			if sh.distance_to(tgt) > reach:
				ok = false
		if ok:
			break
		bend += 0.08
	return bend


## つかんでいる手は、つかんだ物に対してコマの姿勢を保つ（毎物理フレーム、腕を伸ばし直す）
func _hold_hands() -> void:
	for i in 2:
		var h = _hold[i]
		if h == null:
			continue
		var space: Node3D = h[0]
		var world: Vector3 = space.to_global(h[1])
		var tgt := _spine.global_transform.affine_inverse() * world
		_reach(i, tgt)
	if _hold[0] != null or _hold[1] != null:
		_place_sleeves()
		_rebuild_limbs()


## 袂を、上腕の真ん中から下へ垂らす（胴の座標で。腕の振りの向きに少しだけ傾く）
func _place_sleeves() -> void:
	for i in _sleeves.size():
		var sh := _shoulder[i]
		var mid := sh.position + sh.basis * Vector3(0, -upper * 0.45, 0)
		var arm := sh.basis * Vector3.DOWN
		_sleeves[i].position = mid
		_sleeves[i].basis = Basis.from_euler(Vector3(clampf(arm.z * -0.5, -0.4, 0.4), 0, 0))


## 二関節の腕を、手袋が target（胴の座標）に来るように曲げる
func _reach(i: int, target: Vector3) -> void:
	var s := -1.0 if i == 0 else 1.0
	var sh := _shoulder[i].position
	var to := target - sh
	var pole := Vector3(s * 0.7, -0.5, 0.6).normalized()
	if spec.arm_joints < 2:
		_shoulder[i].basis = _aim(to, pole)
		return
	var a := upper
	var b := fore + 0.04
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.001)
	var dir := to.normalized()
	pole = (pole - dir * pole.dot(dir)).normalized()
	var ang := acos(clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0))
	var elbow := sh + (dir * cos(ang) + pole * sin(ang)) * a
	var hand := sh + dir * d
	var sb := _aim(elbow - sh, pole)
	_shoulder[i].basis = sb
	_elbow[i].basis = sb.inverse() * _aim(hand - elbow, pole)


## -y を down に向けた向き（z は pole の側）
static func _aim(down: Vector3, pole: Vector3) -> Basis:
	var y := -down.normalized()
	var z := pole - y * pole.dot(y)
	if z.length() < 0.01:
		z = Vector3.BACK - y * y.z
	z = z.normalized()
	return Basis(y.cross(z), y, z)


## コマが変わるたび、部品ごとに形をわずかに崩す（クレイアニメの揺れ）
func _boil() -> void:
	_rng.seed = hash(Vector2i(_frame, get_instance_id()))
	for k in _parts.size():
		var p := _parts[k]
		var r := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * BOIL_ROT
		var sc := Vector3.ONE + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * BOIL_SCALE
		if _shape.has(p):
			sc *= _shape[p]
		p.transform = _rest[k] * Transform3D(Basis.from_euler(r).scaled(sc), Vector3.ZERO)
