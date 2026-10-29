extends Node3D
## 大きな山（2026-10-30 代表「ロッジから見て、丘と反対方向に超デカい山を作ってほしい。スキーコースみたいな感じで、
## 途中にジャンプ台、でこぼこ、手すり、なだらかな斜面と急斜面のリズム、一旦平坦になる中腹」）。
## ロッジの南に、高台から高さ約 70 m、長い一本のコースを北へ下ろす。上から下へ:
##   頂上の平ら → 急 → なだらか → 急 → 中腹の平ら → 助走 → ジャンプ台 → 着地 → こぶ → なだらか（手すり） → 急 → 流し → 受け皿と上り返し
## コースの東隣に、押して登る道（代表「押して登ります。それがこのゲームの目指すところです」）。
## 中腹では道もいったん平らになり、一息つけて、下りてくるソリが見える。
## 地面の高さは静的な関数（lift）で、main.gd の ground() が足す（当たり判定と見た目の雪面の両方に効く）。
## このノードは、コースの脇の旗・柵・手すり・木を置く

const Props := preload("res://props.gd")
const Look := preload("res://look.gd")

const COURSE_X := -10.0      # コースのまんなかの x
const COURSE_W := 7.0        # コースの半分の幅 (m)。この外 COURSE_BANK で山の地肌へ戻る
const COURSE_BANK := 6.0
const SIDE_H := 1.2          # コースの両脇は、コースの雪面よりこれだけ高い（コースは溝になり、ソリが外へ出にくい）
const PATH_X := 10.0         # 登り道のまんなかの x
const PATH_W := 2.5          # 登り道の半分の幅
const PATH_BANK := 4.0
const RIDGE_HALF := 22.0     # 山の背の平らな幅の半分（コースと登り道を含む）
const RIDGE_FALL := 32.0     # 山の背から両脇へ下がる広がり（標準偏差, m）
const BOTTOM_Z := 225.0      # コースの下の端（流しの終わり）。ここから北は受け皿と上り返し
const BACK_SLOPE := 30.0     # 頂上の南（裏側）の下り (°)

## コースの区間（上から下へ）: 名前、水平の長さ (m)、下りの傾き (°)
const SECTIONS := [
	["頂上", 10.0, 4.0],
	["急 1", 30.0, 25.0],
	["なだらか 1", 25.0, 9.0],
	["急 2", 30.0, 27.0],
	["中腹", 30.0, 4.0],
	["助走", 18.0, 13.0],
	["着地", 26.0, 23.0],
	["こぶ", 36.0, 12.0],
	["なだらか 2（手すり）", 24.0, 7.0],
	["急 3", 22.0, 20.0],
	["流し", 20.0, 5.0],
]
const KICK_H := 1.4          # ジャンプ台の踏み切りの高さ（助走の雪面から, m）
const KICK_LEN := 7.0        # 踏み切りの盛り上がりの長さ (m)
const MOGUL_A := 0.45        # こぶの高さ（振れ幅, m）
const MOGUL_X := 5.5         # こぶの間隔（横, m）
const MOGUL_Z := 6.5         # こぶの間隔（縦, m）
const DIP_Z := 212.0         # 受け皿の底
const DIP_D := 1.5           # 受け皿の深さ（高台から下へ）
const DIP_HALF := 14.0
const BERM_Z := 186.0        # 上り返しの土手のてっぺん
const BERM_H := 2.0          # 土手の高さ（高台から上へ）
const BERM_HALF := 16.0
const RUN_W := 22.0          # 受け皿と土手の平らな幅の半分。この外 14 m で高台へ戻る
const RAIL_X := COURSE_X + 4.0   # 手すりの x（コースの東寄り）
const RAIL_H := 0.35         # 手すりの下の端の上面の、雪からの高さ（上の端は雪とほぼ同じ高さで、乗り入れやすい）

static var _prof := PackedFloat32Array()   # コースの雪面の高さ（高台から）。z = BOTTOM_Z から 1 m おき
static var _path := PackedFloat32Array()   # 登り道の雪面の高さ。同じ並び
static var _z := {}                        # 区間の名前 → [上の端の z, 下の端の z]
static var top_z := 0.0                    # 頂上の平らの南の端
static var top_h := 0.0                    # 頂上の高さ（高台から）


static func _build() -> void:
	if not _prof.is_empty():
		return
	var length := 0.0
	for s in SECTIONS:
		length += s[1]
	top_z = BOTTOM_Z + length
	# 下から上へ積む
	var edges := []   # [z, h]（下から）
	var z := BOTTOM_Z
	var h := 0.0
	edges.append([z, h])
	for i in range(SECTIONS.size() - 1, -1, -1):
		var s: Array = SECTIONS[i]
		var z1: float = z + s[1]
		_z[s[0]] = [z1, z]
		h += s[1] * tan(deg_to_rad(s[2]))
		z = z1
		edges.append([z, h])
	top_h = h
	var back := top_h / tan(deg_to_rad(BACK_SLOPE))
	var n := int(top_z + back - BOTTOM_Z) + 8
	var raw := PackedFloat32Array()
	raw.resize(n)
	var k := 0
	for i in n:
		var zz := BOTTOM_Z + i
		if zz >= top_z:
			raw[i] = maxf(0.0, top_h - (zz - top_z) * tan(deg_to_rad(BACK_SLOPE)))
			continue
		while k < edges.size() - 2 and zz > edges[k + 1][0]:
			k += 1
		var t: float = (zz - edges[k][0]) / (edges[k + 1][0] - edges[k][0])
		raw[i] = lerpf(edges[k][1], edges[k + 1][1], t)
	# 区間の継ぎ目の角を 7 m ずつならす（長い大のソリが、急から平らへ変わる所で雪に刺さらないよう。踏み切りは、あとで形を足す）
	_prof.resize(n)
	for i in n:
		var acc := 0.0
		var c := 0
		for d in range(-7, 8):
			var j := clampi(i + d, 0, n - 1)
			acc += raw[j]
			c += 1
		_prof[i] = acc / c
	# 登り道: 下の端（0）→ 中腹の下の端 → 中腹（平ら）→ 頂上の平らの下の端 → 頂上。区間の中はまっすぐ
	var mid: Array = _z["中腹"]
	var top: Array = _z["頂上"]
	var pts := [[BOTTOM_Z, 0.0], [mid[1], at_prof(mid[1])], [mid[0], at_prof(mid[1])], [top[1], at_prof(top[1])], [top_z, top_h]]
	_path.resize(n)
	for i in n:
		var zz := BOTTOM_Z + i
		if zz >= top_z:
			_path[i] = raw[i]
			continue
		for p in range(pts.size() - 1):
			if zz <= pts[p + 1][0]:
				_path[i] = lerpf(pts[p][1], pts[p + 1][1], (zz - pts[p][0]) / (pts[p + 1][0] - pts[p][0]))
				break


static func _sample(a: PackedFloat32Array, z: float) -> float:
	var f := z - BOTTOM_Z
	if f <= 0.0:
		return a[0]
	var i := int(f)
	if i >= a.size() - 1:
		return a[a.size() - 1]
	return lerpf(a[i], a[i + 1], f - i)


## コースのまんなかの雪面（ジャンプ台・こぶなし。高台から）
static func at_prof(z: float) -> float:
	_build()
	return _sample(_prof, z)


## 区間の [上の端の z, 下の端の z]
static func section(name: String) -> Array:
	_build()
	return _z[name]


## ジャンプ台の踏み切り: 助走の下の端（踏み切りの先）で KICK_H、そこから KICK_LEN 上で 0。下へ反り上がる形
static func _kicker(z: float) -> float:
	var lip: float = _z["助走"][1]
	if z < lip or z > lip + KICK_LEN:
		return 0.0
	var t := (lip + KICK_LEN - z) / KICK_LEN
	return KICK_H * t * t


static func _moguls(x: float, z: float) -> float:
	var s: Array = _z["こぶ"]
	if z > s[0] - 3.0 or z < s[1] + 3.0:
		return 0.0
	var fade := smoothstep(s[1] + 3.0, s[1] + 7.0, z) * (1.0 - smoothstep(s[0] - 7.0, s[0] - 3.0, z))
	return MOGUL_A * fade * sin(TAU * (x - COURSE_X) / MOGUL_X + z * 0.35) * sin(TAU * z / MOGUL_Z)


## 受け皿（DIP_Z で -DIP_D）と、その北の土手（BERM_Z で +BERM_H）。コースの幅より広く、高台へなめらかに戻る
static func _runout(x: float, z: float) -> float:
	var w := 1.0 - smoothstep(RUN_W, RUN_W + 14.0, absf(x - COURSE_X))
	if w <= 0.0:
		return 0.0
	var h := 0.0
	var t := (z - DIP_Z) / DIP_HALF
	if absf(t) < 1.0:
		h -= DIP_D * pow(cos(t * PI * 0.5), 2.0)
	t = (z - BERM_Z) / BERM_HALF
	if absf(t) < 1.0:
		h += BERM_H * pow(cos(t * PI * 0.5), 2.0)
	return h * w


## 地面に足す高さ（高台から）。山の外では 0
static func lift(x: float, z: float) -> float:
	if z < BERM_Z - BERM_HALF - 1.0:
		return 0.0
	_build()
	var h := _runout(x, z)
	if z <= BOTTOM_Z:
		return h
	# 山の地肌: 背（登り道と、コースより SIDE_H 高い所の高いほう）から両脇へ下がる。
	# 中腹では脇の土手をなくし、登り道とコースをひと続きの平らにする（一息ついて、下りてくるソリを眺められる）
	var mid: Array = _z["中腹"]
	var open := smoothstep(mid[1] - 6.0, mid[1] + 2.0, z) * (1.0 - smoothstep(mid[0] - 2.0, mid[0] + 6.0, z))
	var ridge := maxf(_sample(_path, z), _sample(_prof, z) + SIDE_H * (1.0 - open))
	var dx := absf(x - (COURSE_X + PATH_X) * 0.5)
	var g := 1.0 if dx < RIDGE_HALF else exp(-pow(dx - RIDGE_HALF, 2.0) / (2.0 * RIDGE_FALL * RIDGE_FALL))
	var ground := ridge * g
	# コース
	var wc := 1.0 - smoothstep(COURSE_W, COURSE_W + COURSE_BANK, absf(x - COURSE_X))
	if wc > 0.0:
		var c := _sample(_prof, z) + _kicker(z) + _moguls(x, z)
		ground = lerpf(ground, c, wc)
	# 登り道
	var wp := 1.0 - smoothstep(PATH_W, PATH_W + PATH_BANK, absf(x - PATH_X))
	if wp > 0.0 and z < top_z:
		ground = lerpf(ground, _sample(_path, z), wp)
	return h + ground


## 登り道の上で 1（雪の色を踏み固めた色にする用）
static func path_weight(x: float, z: float) -> float:
	if z < BOTTOM_Z - 4.0:
		return 0.0
	_build()
	if z > top_z:
		return 0.0
	return 1.0 - smoothstep(PATH_W - 0.5, PATH_W + 0.8, absf(x - PATH_X))


## コースの上で 1（雪の色を、圧雪した少し青い白にする用）
static func course_weight(x: float, z: float) -> float:
	if z < BOTTOM_Z - 2.0:
		return 0.0
	_build()
	if z > top_z:
		return 0.0
	return 1.0 - smoothstep(COURSE_W - 1.0, COURSE_W + 0.5, absf(x - COURSE_X))


## ジャンプ台の踏み切りの縁で 1（雪を藍に染めた帯にして、遠くから踏み切りが分かるように）
static func lip_weight(x: float, z: float) -> float:
	if z < BOTTOM_Z:
		return 0.0
	_build()
	var lip: float = _z["助走"][1]
	if z < lip - 0.5 or z > lip + 2.0:
		return 0.0
	return 1.0 - smoothstep(COURSE_W - 1.0, COURSE_W, absf(x - COURSE_X))


## コースの上（木を置かない用）
static func on_course(x: float, z: float, margin := 0.0) -> bool:
	_build()
	if z < BERM_Z - BERM_HALF or z > top_z + 6.0:
		return false
	if absf(x - COURSE_X) < COURSE_W + COURSE_BANK + margin:
		return true
	if absf(x - PATH_X) < PATH_W + PATH_BANK + margin:
		return true
	return z < BOTTOM_Z and absf(x - COURSE_X) < RUN_W + margin


# ---------------------------------------------------------------- 飾りと手すり

var world: Node3D


func _ready() -> void:
	_build()
	_flags()
	_fences()
	_rail()
	_trees()


func _y(x: float, z: float) -> float:
	return world.height(x, z)


func _put(path: String, x: float, z: float, yaw: float) -> Node3D:
	var n := Props.make(path)
	n.position = Vector3(x, _y(x, z) - 0.05, z)
	n.rotation.y = yaw
	add_child(n)
	return n


## コースの両脇の旗: 赤と藍を交互に、14 m おき
func _flags() -> void:
	var i := 0
	var z := BOTTOM_Z + 4.0
	while z < top_z:
		for side in [-1.0, 1.0]:
			_put("res://props/flag_%s.glb" % ("red" if i % 2 == 0 else "navy"), COURSE_X + side * (COURSE_W + 1.5), z, PI / 2 * side)
			i += 1
		z += 14.0


## いちばん急な所（急 2）とジャンプ台の着地の両脇に、毛糸の網の柵
func _fences() -> void:
	for name in ["急 2", "着地"]:
		var s: Array = _z[name]
		var z: float = s[1] + 1.5
		while z < s[0] - 1.0:
			for side in [-1.0, 1.0]:
				var x: float = COURSE_X + side * (COURSE_W + 2.6)
				var net := _put("res://props/net_span.glb", x, z, 0.0)
				# 坂に沿わせる（網は長い向きが z）
				var dz := _y(x, z + 1.25) - _y(x, z - 1.25)
				net.rotation.x = atan2(dz, 2.5)
			z += 2.5


## 手すり: なだらか 2 の東寄りに、毛糸を巻いた木の棒を 2 本並べた長いレール。上の端は雪とほぼ同じ高さで、下へ行くほど雪から浮く
## （乗り口で立ち上がると、ソリが勢いをなくして止まる）。
## 当たりは 2 本の棒にまたがる平らな板（細い棒 1 本だとソリが釣り合わず落ちる）。滑り木がよく滑るよう摩擦はほぼ 0
const RAIL_W := 0.9          # 当たりの板の幅 (m)
const RAIL_GAP := 0.36       # 2 本の棒の、まんなかからの距離 (m)

func _rail() -> void:
	var s: Array = _z["なだらか 2（手すり）"]
	var z0: float = s[0] - 2.0      # 上の端（乗り入れ）
	var z1: float = s[1] + 3.0      # 下の端
	var a := Vector3(RAIL_X, _y(RAIL_X, z0) - 0.06, z0)   # 雪にもぐって始まる（段に引っかからない）
	var b := Vector3(RAIL_X, _y(RAIL_X, z1) + RAIL_H, z1)
	var body := StaticBody3D.new()
	body.name = "MountainRail"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.02
	body.physics_material_override = pm
	add_child(body)
	var wood := Look.wood(Color(0.55, 0.38, 0.24))
	var yarns := [Look.felt(Color(0.80, 0.22, 0.18), 1.5), Look.felt(Color(0.95, 0.93, 0.86), 1.5), Look.felt(Color(0.20, 0.30, 0.55), 1.5)]
	for seg in [[a, b]]:
		var p: Vector3 = seg[0]
		var q: Vector3 = seg[1]
		var mid := (p + q) * 0.5
		var len := p.distance_to(q)
		var basis := Basis.looking_at((q - p).normalized(), Vector3.UP)
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(RAIL_W, 0.2, len + 0.1)
		col.shape = box
		col.transform = Transform3D(basis, mid - basis.y * 0.1)
		body.add_child(col)
		var bar_basis := basis * Basis(Vector3.RIGHT, PI / 2)
		for side in [-1.0, 1.0]:
			var off: Vector3 = basis.x * RAIL_GAP * side - basis.y * 0.1
			var bar := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.1
			cyl.bottom_radius = 0.1
			cyl.height = len
			cyl.radial_segments = 12
			bar.mesh = cyl
			bar.material_override = wood
			bar.transform = Transform3D(bar_basis, mid + off)
			add_child(bar)
			# 毛糸の巻き: 0.5 m おきに 3 色を順に（2 本でずらす）
			var steps := int(len / 0.5)
			for k in steps:
				var ring := MeshInstance3D.new()
				var rc := CylinderMesh.new()
				rc.top_radius = 0.115
				rc.bottom_radius = 0.115
				rc.height = 0.18
				rc.radial_segments = 12
				ring.mesh = rc
				ring.material_override = yarns[(k + (1 if side > 0.0 else 0)) % yarns.size()]
				ring.transform = Transform3D(bar_basis, p.lerp(q, (k + 0.5) / steps) + off)
				add_child(ring)
	# 支柱と、2 本をつなぐ横木: 3 m おき
	var z := z0 - 3.0
	while z > z1 - 0.1:
		var top := a.lerp(b, (z0 - z) / (z0 - z1))
		var ground := _y(RAIL_X, z)
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.06
			pc.bottom_radius = 0.07
			pc.height = top.y - ground + 0.2
			post.mesh = pc
			post.material_override = wood
			post.position = Vector3(RAIL_X + RAIL_GAP * side, (top.y - 0.1 + ground - 0.2) * 0.5, z)
			add_child(post)
		var tie := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(RAIL_GAP * 2.0 + 0.2, 0.08, 0.12)
		tie.mesh = tb
		tie.material_override = wood
		tie.position = Vector3(RAIL_X, top.y - 0.22, z)
		add_child(tie)
		z -= 3.0


## 山の地肌の木: コースの両脇に多く（森を切り開いたコースに見えるよう）、山の脇にもまばらに。コースと登り道は空ける。
## 急すぎる所には立てず、代わりに大きな岩を置く（遠くから山の形が読めるように）
func _trees() -> void:
	const TREES := ["res://props/tree_tall.glb", "res://props/tree_zigzag.glb", "res://props/tree_round.glb",
		"res://props/tree_little.glb"]
	const ROCKS := ["res://props/rock_a.glb", "res://props/rock_b.glb", "res://props/rock_c.glb"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var trees := 0
	var rocks := 0
	for k in 2000:
		if trees >= 150 and rocks >= 24:
			break
		var x: float
		var z := rng.randf_range(BERM_Z - 10.0, top_z + 60.0)
		if rng.randf() < 0.65:   # コースの脇の帯
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			x = COURSE_X + side * (COURSE_W + COURSE_BANK + rng.randf_range(3.0, 34.0))
		else:
			x = rng.randf_range(-118.0, 118.0)
		var hgt := rng.randf_range(4.0, 8.0)
		var yaw := rng.randf() * TAU
		if on_course(x, z, 3.0):
			continue
		var gx := _y(x + 1.0, z) - _y(x - 1.0, z)
		var gz := _y(x, z + 1.0) - _y(x, z - 1.0)
		var steep := Vector2(gx, gz).length() * 0.5
		if steep > 0.85:   # 40° より急: 岩
			if rocks >= 24:
				continue
			var rock := Props.make(ROCKS[k % ROCKS.size()])
			rock.scale = Vector3.ONE * rng.randf_range(4.0, 8.0)
			rock.position = Vector3(x, _y(x, z) - 0.6, z)
			rock.rotation.y = yaw
			add_child(rock)
			rocks += 1
			continue
		if trees >= 150:
			continue
		var tree := Props.make(TREES[k % TREES.size()])
		tree.scale = Vector3.ONE * hgt / 6.0
		tree.position = Vector3(x, _y(x, z) - 0.05, z)
		tree.rotation.y = yaw
		add_child(tree)
		trees += 1
