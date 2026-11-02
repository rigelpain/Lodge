extends Node3D
## おじいさんの番台（main.gd の Bandai_counter_patch）を囲む、パッチワークのカーテン。
## ふだんは閉じていて、人（あなた・仲間・つないでいるほかの人。emotes.gd の people）が番台の前の箱に入ると、
## 左右へ引き分けて開き、離れると閉まる（ロッジの自動ドア lodge.gd の _make_auto_door と同じ考え。ただ、つないでいる
## ほかの人の体は当たりの層が 0 で Area3D に入らないので、箱は人の位置で見る）。どの画面でも、それぞれ人の位置から決める（通信では送らない）。
## 開け閉めは人形と同じ 12 コマ／秒で刻む。竿の所が先に動き、裾は遅れてついてきて、止まると少し行き過ぎて戻る（布のたわみ）。
## 座標は番台の座標（-Z が客の側、原点は番台の真ん中の床）。前の幕が開く。横の幕は留めたまま（横からおじいさんが見えないように）。
## 2026-11-02 代表「パッチワークのおじさんもパッチワークのカーテンしまってて近づいたら開いてほしいな」
## 形は人形劇の舞台（3 案から代表が B を選んだ）: 幕はおじいさんのコートと同じ藍のフェルトに継ぎ当て、木の輪で木の竿に吊る。
## 竿の前に、裾を波の形に切ったパッチワークの飾り幕（番台と同じ暖色の端切れ）と、波の先にフェルトのぼんぼり。

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")

const W := 2.0            # 前の柱のあいだ (m)。番台（1.8 m）より少し広く、ミシンの台にはかからない
const Z_FRONT := -0.58    # 前の幕の線（番台の前の縁 -0.34 から少し前。上のレジとお皿に触れない）
const Z_BACK := 1.15      # 後ろの柱（おじいさんの立つ所 0.85 の後ろ）
const ROD_Y := 2.12       # 竿の高さ（床から）。頭の上の看板（下の縁 2.25）は竿の上に見えたまま
const HEM_Y := 0.05       # 裾の高さ
const OVERLAP := 0.04     # 閉じたとき、左右の幕が真ん中で重なる幅
const GATHER := 0.24      # 開いたとき、柱に寄せた幕の幅
const FOLDS := 5          # 片側の幕のひだの数
const COLS := 30
const ROWS := 12
const OPEN_FRAMES := 9    # 開くのにかかるコマ（12 コマ／秒で 0.75 秒）
const CLOSE_FRAMES := 14  # 閉じるのにかかるコマ
const SENSE_FRONT := 3.0  # 幕の前のこの奥行きに人が入ると開く (m)。話しかけられる距離（shopkeeper.gd の TALK_R）より広い
const PX := 150.0         # 布の絵の細かさ（1 m あたりの画素）

var world: Node            # main.gd（人の一覧 emotes.gd の people を見る。番台はその配り役より先に置かれる）
var shopkeeper: Node3D     # おじいさん（shopkeeper.gd）。売り台が開いているあいだは開けておく
var force := -1.0          # 0〜1 で開き具合を決めて止める（撮る用）。負なら人で開け閉め
var open := 0.0            # 竿の所の開き具合（コマで進む）
var _hem := 0.0            # 裾の開き具合（竿に遅れてついてくる）
var _hem_v := 0.0
var _frame := -1
var _shown := Vector2(-1, -1)
var _front: Array[MeshInstance3D] = []
var _tabs: Array = []      # [MeshInstance3D, 側 s, 布の位置 u]

static var _tex := {}      # 布の絵（部位ごと）: [色, 凹凸]


func _ready() -> void:
	var wood := Look.wood(Color(0.36, 0.23, 0.13))
	var mat_front := _cloth_mat("front")
	var mat_side := _cloth_mat("side")
	for s in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "Curtain" + ("L" if s < 0 else "R")
		mi.material_override = mat_front
		add_child(mi)
		_front.append(mi)
		var side := MeshInstance3D.new()
		side.name = "Side" + ("L" if s < 0 else "R")
		side.mesh = _side_mesh(s)
		side.material_override = mat_side
		add_child(side)
		# 柱（前と後ろ）。竿は柱の上を通す
		for z in [Z_FRONT, Z_BACK]:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, ROD_Y + 0.08, 0.07)
			post.mesh = bm
			post.material_override = wood
			post.position = Vector3(s * (W / 2.0 + 0.05), (ROD_Y + 0.08) / 2.0, z)
			add_child(post)
		_rod(Vector3(s * (W / 2.0 + 0.05), ROD_Y, Z_FRONT), Vector3(s * (W / 2.0 + 0.05), ROD_Y, Z_BACK), 0.022, wood)
		# 横の幕が人を通さないよう、薄い当たり
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.1, ROD_Y, Z_BACK - Z_FRONT)
		cs.shape = box
		cs.position = Vector3(s * (W / 2.0 + 0.05), ROD_Y / 2.0, (Z_FRONT + Z_BACK) / 2.0)
		body.add_child(cs)
		add_child(body)
	_make_top(wood)
	_show(0.0, 0.0)


## 竿と木の玉、幕を吊る木の輪、飾り幕
func _make_top(wood: Material) -> void:
	_rod(Vector3(-W / 2.0 - 0.16, ROD_Y, Z_FRONT), Vector3(W / 2.0 + 0.16, ROD_Y, Z_FRONT), 0.026, wood)
	for s in [-1.0, 1.0]:   # 竿の先の木の玉
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		ball.mesh = sm
		ball.material_override = wood
		ball.position = Vector3(s * (W / 2.0 + 0.2), ROD_Y, Z_FRONT)
		add_child(ball)
	for s in [-1.0, 1.0]:
		for k in 7:
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.032
			tm.outer_radius = 0.042
			tm.rings = 16
			tm.ring_segments = 8
			t.mesh = tm
			t.rotation.z = PI / 2.0   # 輪の軸を竿の向きに
			t.material_override = wood
			add_child(t)
			_tabs.append([t, s, k / 6.0])
	_make_valance()


## 飾り幕: 竿の前に、波の形に裾を切ったパッチワークの帯。波の先にフェルトのぼんぼり
func _make_valance() -> void:
	var wv := W + 0.42
	var hv := 0.42
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 40
	for r in 3:
		for c in cols + 1:
			var u := float(c) / cols
			var v := r / 2.0
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(lerpf(-wv / 2.0, wv / 2.0, u), ROD_Y + 0.12 - v * hv, Z_FRONT - 0.07 + 0.012 * sin(u * 9.0 * TAU)))
	_grid_index(st, 2, cols)
	st.generate_normals()
	mi.mesh = st.commit()
	var m := _cloth_mat("valance")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	mi.material_override = m
	add_child(mi)
	var cols_pom := ["C99A3A", "EEE6D4", "B5636A", "C8925A"]
	for k in 9:
		var pom := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		pom.mesh = sm
		pom.material_override = Look.felt(Color(cols_pom[k % cols_pom.size()]), 6.0)
		pom.position = Vector3(lerpf(-wv / 2.0, wv / 2.0, (k + 0.5) / 9.0), ROD_Y + 0.12 - hv - 0.01, Z_FRONT - 0.075)
		add_child(pom)


func _rod(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	_tube(self, [a, b], [r], mat, 12)


const TOP_Y := ROD_Y - 0.06   # 幕の上の縁（輪に掛ける）


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
	var want := 0.0
	if force >= 0.0:
		open = force
		_hem = force
		_hem_v = 0.0
		return
	if _someone_near() or (shopkeeper and shopkeeper.get("shop_open")):
		want = 1.0
	open = move_toward(open, want, 1.0 / (OPEN_FRAMES if want > open else CLOSE_FRAMES))
	# 裾はばねで竿を追う（遅れて、少し行き過ぎて戻る）
	_hem_v = _hem_v * 0.6 + (open - _hem) * 0.28
	_hem += _hem_v
	if absf(_hem - open) < 0.002 and absf(_hem_v) < 0.002:
		_hem = open
		_hem_v = 0.0


## 番台の前の箱（幅は柱の外へ 1 m ずつ、前の幕から SENSE_FRONT m 前まで、後ろの柱まで）に人がいるか
func _someone_near() -> bool:
	var emotes: Node = world.get("emotes") if world else null
	if emotes == null:
		return false
	for who in emotes.people.values():
		if not is_instance_valid(who):
			continue
		var l := to_local((who as Node3D).global_position)
		if absf(l.x) < W / 2.0 + 1.0 and l.z > Z_FRONT - SENSE_FRONT and l.z < Z_BACK and absf(l.y) < 2.0:
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
		_front[i].mesh = _front_mesh(-1.0 if i == 0 else 1.0, a, b)
	for t in _tabs:
		var p := _front_point(t[1], t[2], 0.0, a, b)
		(t[0] as Node3D).position = Vector3(p.x, ROD_Y, p.z)


static func _ease(e: float) -> float:
	var c := clampf(e, -0.2, 1.2)
	return c * c * (3.0 - 2.0 * c) if c >= 0.0 and c <= 1.0 else c


## 前の幕の点: 側 s（-1 左、1 右）、布の位置 u（0 柱の側、1 真ん中の側）、高さ h（0 上、1 裾）
func _front_point(s: float, u: float, h: float, et: float, eb: float) -> Vector3:
	var e := lerpf(et, eb, pow(h, 1.4))
	var full := W / 2.0 + OVERLAP
	var span := lerpf(full, GATHER, e)
	var amp := 0.018 + sqrt(maxf(full * full - span * span, 0.0)) / (4.0 * FOLDS)
	var x := s * (W / 2.0 - u * span)
	var y := lerpf(TOP_Y, HEM_Y, h)
	var z := Z_FRONT + s * 0.012 + amp * sin(u * FOLDS * TAU) * (1.0 - 0.3 * h)
	return Vector3(x, y, z)


func _front_mesh(s: float, et: float, eb: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var full := W / 2.0 + OVERLAP
	for r in ROWS + 1:
		var h := float(r) / ROWS
		for c in COLS + 1:
			var u := float(c) / COLS
			# 絵は閉じた幕 2 枚で一枚の布になるよう、左は左半分、右は右半分（真ん中で 0.5）
			var tx := u * 0.5 if s < 0 else 1.0 - u * 0.5
			st.set_uv(Vector2(tx, h))
			st.add_vertex(_front_point(s, u, h, et, eb))
	_grid_index(st, ROWS, COLS)
	st.generate_normals()
	return st.commit()


## 横の幕（留めたまま）: 前の柱から後ろの柱まで、ゆるいひだ
func _side_mesh(s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 20
	for r in ROWS + 1:
		var h := float(r) / ROWS
		for c in cols + 1:
			var u := float(c) / cols
			var z := lerpf(Z_FRONT + 0.04, Z_BACK - 0.04, u)
			st.set_uv(Vector2(u, h))
			st.add_vertex(Vector3(s * (W / 2.0 + 0.05 + 0.02 * sin(u * 4.0 * TAU)), lerpf(ROD_Y - 0.03, HEM_Y, h), z))
	_grid_index(st, ROWS, cols)
	st.generate_normals()
	return st.commit()


static func _grid_index(st: SurfaceTool, rows: int, cols: int) -> void:
	for r in rows:
		for c in cols:
			var a := r * (cols + 1) + c
			st.add_index(a)
			st.add_index(a + cols + 1)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + cols + 1)
			st.add_index(a + cols + 2)


## 管: 点の列に沿って（shopkeeper.gd の _tube と同じ作り）
static func _tube(parent: Node3D, pts: Array, radii: Array, mat: Material, sides := 10) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for i in n:
		var t: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.1:
			side = t.cross(Vector3.FORWARD)
		side = side.normalized()
		var up := side.cross(t)
		for j in sides + 1:
			var a := TAU * j / sides
			var nrm := side * cos(a) + up * sin(a)
			st.set_normal(nrm)
			st.add_vertex((pts[i] as Vector3) + nrm * float(radii[mini(i, radii.size() - 1)]))
	for i in n - 1:
		for j in sides:
			var a := i * (sides + 1) + j
			st.add_index(a)
			st.add_index(a + sides + 1)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + sides + 1)
			st.add_index(a + sides + 2)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# ---- 布の絵 ----------------------------------------------------------------------------

const WARM := ["A8532E", "C99A3A", "EEE6D4", "B5636A", "2E3F66", "C8925A"]   # 番台のパッチワーク（props/common.py の patch_warm）
const INDIGO := Color(0.20, 0.25, 0.46)   # おじいさんのコート（shopkeeper.gd）
const COAT_PATCHES := ["5C7AA8", "9E9E99", "E6D9B8", "73476A", "3D8585", "DBA33D", "B84D3D"]   # おじいさんのコートの継ぎ当て
const THREAD := Color("F1E8D2")


func _cloth_mat(part: String) -> StandardMaterial3D:
	var key := part
	if not _tex.has(key):
		var size := Vector2(W + 2.0 * OVERLAP, ROD_Y - HEM_Y)
		if part == "side":
			size = Vector2(Z_BACK - Z_FRONT, ROD_Y - HEM_Y)
		elif part == "valance":
			size = Vector2(W + 0.42, 0.42)
		_tex[key] = _quilt(part, size, hash(key) & 0xffff)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex[key][0]
	m.normal_enabled = true
	m.normal_texture = _tex[key][1]
	m.normal_scale = 0.9
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = 0.2
	m.rim_tint = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## 端切れ: 色・柄（0 無地、1 縞、2 水玉、3 ギンガム）・柄の色・三角の二枚目（null なら四角のまま）・三角の向き
func _piece(rng: RandomNumberGenerator, cols: Array, tri_rate: float) -> Dictionary:
	var c := Color(cols[rng.randi() % cols.size()])
	var c2: Variant = null
	if rng.randf() < tri_rate:
		var k := Color(cols[rng.randi() % cols.size()])
		while k.is_equal_approx(c):
			k = Color(cols[rng.randi() % cols.size()])
		c2 = k
	var ink := Color("EEE6D4") if c.get_luminance() < 0.55 else c.darkened(0.35)
	return {"c": c, "c2": c2, "print": rng.randi() % 4 if rng.randf() < 0.6 else 0, "ink": ink, "dir": rng.randi() % 2}


static func _print(p: Vector2, kind: int) -> float:
	match kind:
		1:
			return 1.0 if fposmod(p.x + p.y * 0.0, 0.04) < 0.013 else 0.0
		2:
			var g := Vector2(fposmod(p.x + floorf(p.y / 0.045) * 0.0225, 0.045), fposmod(p.y, 0.045)) - Vector2(0.0225, 0.0225)
			return 1.0 if g.length() < 0.008 else 0.0
		3:
			return (0.45 if fposmod(p.x, 0.032) < 0.016 else 0.0) + (0.45 if fposmod(p.y, 0.032) < 0.016 else 0.0)
	return 0.0


## 布の絵を描く: 色（アルファは飾り幕の波の裾）と凹凸。端切れはふっくら、継ぎ目は沈み、縁の内側になみ縫い
func _quilt(part: String, size: Vector2, seed: int) -> Array:
	var w := int(size.x * PX)
	var h := int(size.y * PX)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bump := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var fiber := FastNoiseLite.new()
	fiber.frequency = 0.25
	fiber.seed = seed
	var blot := FastNoiseLite.new()
	blot.frequency = 0.02
	blot.seed = seed + 1
	var quilt := part == "valance"   # 飾り幕は四角つなぎ。幕は藍に継ぎ当て
	var cell := 0.14
	var cols_n := int(ceil(size.x / cell)) + 1
	var rows_n := int(ceil(size.y / cell)) + 1
	var grid := []
	var patches := []      # 藍の上の継ぎ当て [Rect2, 端切れ]
	if quilt:
		for i in cols_n * rows_n:
			grid.append(_piece(rng, WARM, 0.5))
	else:
		var tries := 0
		while patches.size() < (14 if part == "front" else 9) and tries < 400:
			tries += 1
			var ps := Vector2(rng.randf_range(0.12, 0.26), rng.randf_range(0.10, 0.22))
			var r := Rect2(Vector2(rng.randf_range(0.04, size.x - ps.x - 0.04), rng.randf_range(0.12, size.y - ps.y - 0.08)), ps)
			var ok := true
			for q in patches:
				if (q[0] as Rect2).grow(0.06).intersects(r):
					ok = false
					break
			if ok:
				patches.append([r, _piece(rng, COAT_PATCHES, 0.0)])
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5) / PX
			var col := Color.WHITE
			var d := 1.0          # 継ぎ目までの距離 (m)
			var along := p.x      # 継ぎ目に沿った位置（なみ縫いの目）
			var pr := 0
			var ink := Color.WHITE
			var lift := 0.0       # 継ぎ当ての厚み
			var stitch := true
			if quilt:
				var ci := int(p.x / cell)
				var ri := int(p.y / cell)
				var f := Vector2(p.x / cell - ci, p.y / cell - ri)
				var pc: Dictionary = grid[(ri * cols_n + ci) % grid.size()]
				col = pc["c"]
				pr = pc["print"]
				ink = pc["ink"]
				var dx := minf(f.x, 1.0 - f.x) * cell
				var dy := minf(f.y, 1.0 - f.y) * cell
				d = minf(dx, dy)
				along = p.y if dx < dy else p.x
				if pc["c2"] != null:
					var diag := (f.x - f.y) if pc["dir"] == 0 else (f.x + f.y - 1.0)
					if diag > 0.0:
						col = pc["c2"]
						pr = 0
					var dd := absf(diag) * cell * 0.7071
					if dd < d:
						d = dd
						along = (p.x + p.y) * 0.7071 if pc["dir"] == 0 else (p.x - p.y) * 0.7071
			else:
				col = INDIGO
				d = 1.0
				stitch = false
				for q in patches:
					var r: Rect2 = q[0]
					if r.has_point(p):
						var pc: Dictionary = q[1]
						col = pc["c"]
						pr = pc["print"]
						ink = pc["ink"]
						var dx := minf(p.x - r.position.x, r.end.x - p.x)
						var dy := minf(p.y - r.position.y, r.end.y - p.y)
						d = minf(dx, dy)
						along = p.y if dx < dy else p.x
						lift = 0.35
						stitch = true
						break
			# 柄
			var pv := _print(p, pr)
			col = col.lerp(ink, pv * 0.8)
			# 布のむらと繊維
			var fb := fiber.get_noise_2d(x, y)
			col = col * (0.95 + 0.06 * blot.get_noise_2d(x, y) + 0.05 * fb)
			# 継ぎ目は沈んで暗く、端切れはふっくら
			var puff := smoothstep(0.0, 0.035, d)
			col = col * lerpf(0.62, 1.0, smoothstep(0.0, 0.007, d))
			var hh := 0.25 + 0.45 * puff + lift + 0.12 * fb
			# なみ縫い: 縁から 1.4 cm の内側に、長さ 7 mm の目
			if stitch and d > 0.011 and d < 0.015 and fposmod(along, 0.013) < 0.0075:
				var th := THREAD if col.get_luminance() < 0.7 else Color("8C6A3A")
				col = th
				hh += 0.25
			# 飾り幕: 裾を波の形に切る（波は 0.27 m ごと）
			var a := 1.0
			if part == "valance":
				var wv := 0.27
				var fx2 := fposmod(p.x, wv) / wv - 0.5
				var edge := size.y - 0.12 + 0.12 * sqrt(maxf(0.0, 1.0 - 4.0 * fx2 * fx2))
				if p.y > edge:
					a = 0.0
				elif p.y > edge - 0.012:
					col = THREAD.darkened(0.1)   # 縁をくるんだ生成りのテープ
			col = col * 0.84   # 番台の焼いた布の明るさにそろえる
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
			bump.set_pixel(x, y, Color(hh, hh, hh))
	bump.bump_map_to_normal_map(6.0)
	img.generate_mipmaps()
	bump.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(bump)]
