extends Node3D
## 山の飾りの共通の部品（mountain.gd と grand_mountain.gd の親）: ジャンプ台・手すり・小物を雪に立てる。
## 形はどの山でも同じ。どこに置くかは、それぞれの山が決める

const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const TreeHits := preload("res://tree_hits.gd")

const KICK_W := 4.4          # 台の幅 (m)。大きいソリ 2 台分
const KICK_L := 4.5          # 踏み切りの坂の長さ（水平, m）。5.5 m だと台が 1.6 m まで高くなり、遅い小のソリが縁の手前で止まった
const KICK_TOP := 0.6        # 縁の先の平らな所 (m)
const KICK_BURY := 0.06      # 坂の出だしは雪にもぐらせる (m)。地面との継ぎ目に段を作らない
const KICK_CLEAR := 26.0     # 台の手前と先の、木を置かない長さ (m)
const RAIL_H := 0.35         # 手すりの下の端の上面の、雪からの高さ（上の端は雪とほぼ同じ高さで、乗り入れやすい）

var world: Node3D


func _y(x: float, z: float) -> float:
	return world.height(x, z)


## 小物を雪に立てる。根もと（半径 r）のまわりで、見た目の雪面がいちばん低い所に合わせる（main.gd の foot_y）
func _put(path: String, x: float, z: float, yaw: float, r := 0.3) -> Node3D:
	var n := Props.make(path)
	n.position = Vector3(x, world.foot_y(x, z, r) - 0.05, z)
	n.rotation.y = yaw
	add_child(n)
	return n

## 置き終わった小物（木・岩・旗・縫い目など）の見た目を、同じ形・同じ素材ごと、BATCH_CELL 四方ごとに 1 つの MultiMesh にまとめる。
## 1 本ずつ別の形のままだと、山の上から見渡したとき 1 本ごとに描く数が 1 つ要った（2026-11-09 測定: 大山だけで画面の中に 514）。
## 当たり（木は tree_hits.gd、ジャンプ台は自分の体）は形と別に持っているので変わらない。動く物（スクリプト付き・骨付き）はまとめない。
## まとめた形の名前は元の名前を引き継ぐ（main.gd の _split_pip_layers が名前で 360° の小窓に映すかを決める）
const BATCH_CELL := 256.0      # 木はまばらに広く散っているので、64 m 四方では同じ形が 1〜2 本ずつにしか集まらない
const BATCH_MIN := 3          # 同じ組がこれより少なければ、まとめない


func _batch_props() -> void:
	var groups := {}   # 組の鍵 → [見本の MeshInstance3D, 自分から見た置き方の配列, 元の形の配列]
	var inv := global_transform.affine_inverse()
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.mesh.get_surface_count() != 1 or m.skin != null or m.get_script() != null or not m.is_visible_in_tree():
			continue
		if m.visibility_range_end > 0.0 or (m.get_parent() != self and m.get_parent().get_script() != null):   # 山の直下（縫い目）はまとめてよい
			continue
		var mat := m.get_active_material(0)
		var xf: Transform3D = inv * m.global_transform
		var cell := Vector2i(floori(xf.origin.x / BATCH_CELL), floori(xf.origin.z / BATCH_CELL))
		var key := [m.mesh.get_rid(), mat.get_rid() if mat else RID(), m.cast_shadow, m.layers, cell]
		var hk := str(key)
		if not groups.has(hk):
			groups[hk] = [m, [], []]
		groups[hk][1].append(xf)
		groups[hk][2].append(m)
	for hk in groups:
		var g: Array = groups[hk]
		if g[1].size() < BATCH_MIN:
			continue
		var src: MeshInstance3D = g[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src.mesh
		mm.instance_count = g[1].size()
		for i in g[1].size():
			mm.set_instance_transform(i, g[1][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(src.name) + "_batch"
		mmi.multimesh = mm
		mmi.material_override = src.get_active_material(0)
		mmi.cast_shadow = src.cast_shadow
		mmi.layers = src.layers
		add_child(mmi)
		for m in g[2]:
			(m as MeshInstance3D).queue_free()


## ジャンプ台: 雪を固めた台（踏み切りの坂・縁の先の平ら・後ろと脇の斜め）。形は雪面の上に、その場の高さに沿って作る。
## 縁には藍に染めたリボンを渡して白い糸で留め、坂の両肩は赤い糸で縫い、縁の両脇に赤と藍の旗を立てる。
## 当たりは、見た目と同じ面と、その下の中身の詰まった芯（ソリが坂を上がって縁から飛ぶ。台の中へ抜けない）
func _make_kicker(idx: int, k: Dictionary) -> void:
	var lip: Vector2 = k.lip
	var f: Vector2 = k.f
	var q := Vector2(-f.y, f.x)   # 台の横
	var hl: float = k.hl
	var half := KICK_W * 0.5
	var at := func(s: float, w: float) -> Vector2: return lip + f * (s - KICK_L) + q * w
	# 雪面からの高さ: 坂は二次の曲線、縁の先は平ら
	var rise := func(s: float) -> float: return hl * pow(minf(s, KICK_L) / KICK_L, 2.0)
	var rows: Array[float] = []
	for i in 13:
		rows.append(KICK_L * i / 12.0)
	rows.append(KICK_L + KICK_TOP)
	var cols: Array[float] = [-1.0, -0.66, -0.33, 0.0, 0.33, 0.66, 1.0]
	var pts: Array[PackedVector3Array] = []
	for s in rows + [KICK_L + KICK_TOP + hl * 0.9]:
		var e: float = rise.call(minf(s, KICK_L + KICK_TOP))
		var back: bool = s > KICK_L + KICK_TOP + 0.01
		var row := PackedVector3Array()
		var side := maxf(e, 0.15) * 0.8
		for c in [-1.0] + cols + [1.0]:
			var outer: bool = (c == -1.0 and row.is_empty()) or (c == 1.0 and row.size() == cols.size() + 1)
			var w: float = c * half + (signf(c) * side if outer else 0.0)
			var p: Vector2 = at.call(s, w)
			var y := _y(p.x, p.y) + (-0.1 if outer or back else e - KICK_BURY)
			row.append(Vector3(p.x, y, p.y))
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in pts.size() - 1:
		for c in pts[r].size() - 1:
			var a: Vector3 = pts[r][c]
			var b: Vector3 = pts[r][c + 1]
			var d: Vector3 = pts[r + 1][c]
			var e: Vector3 = pts[r + 1][c + 1]
			for v in [a, d, b, b, d, e]:
				st.set_uv(Vector2(v.x, v.z) * 0.5)
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Kicker%d" % idx
	mi.mesh = mesh
	var snow := Look.snow()
	snow.albedo_color = Color(0.90, 0.93, 0.99)   # 固めた雪は、まわりより少し青い
	mi.material_override = snow
	add_child(mi)
	# 当たり: 見た目と同じなめらかな三角の面と、その 0.12 m 下に、坂の帯（行と行のあいだ）ごとの中身の詰まった凸の芯。
	# 面だけだと、速く斜めに当たったソリの角が面を抜けて台の中へ入り、中で止まった（大に 1 人、12 m/s）。芯がそれを外へ押し戻す。
	# 芯だけにすると、塊の継ぎ目でソリが少し引っかかり、縁での速さが落ちた
	var body := StaticBody3D.new()
	body.name = "KickerBody%d" % idx
	var skin := CollisionShape3D.new()
	skin.shape = mesh.create_trimesh_shape()
	body.add_child(skin)
	for r in pts.size() - 1:
		var hull := PackedVector3Array()
		for v in pts[r] + pts[r + 1]:
			hull.append(v - Vector3(0, 0.12, 0))
			hull.append(v - Vector3(0, 0.9, 0))
		var col := CollisionShape3D.new()
		var cs := ConvexPolygonShape3D.new()
		cs.points = hull
		col.shape = cs
		body.add_child(col)
	add_child(body)
	# 縁の向き（坂に沿って上を向く）
	var lip_y: float = _y(lip.x, lip.y) + hl - KICK_BURY
	var up_dir := Vector3(f.x, tan(deg_to_rad(k.launch)), f.y).normalized()
	var fwd3 := Vector3(f.x, 0, f.y)
	var side3 := Vector3(q.x, 0, q.y)
	var nrm := up_dir.cross(side3).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var lip_basis := Basis(side3, nrm, -up_dir).orthonormalized()
	# リボン: 縁に渡した藍のフェルトの帯
	var ribbon := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(KICK_W + 0.1, 0.03, 0.42)
	ribbon.mesh = rb
	ribbon.material_override = Look.felt(Color(0.20, 0.30, 0.62), 1.5)
	ribbon.transform = Transform3D(lip_basis, Vector3(lip.x, lip_y, lip.y) - up_dir * 0.2 + nrm * 0.03)
	add_child(ribbon)
	# 糸の目: リボンを留める白い目と、坂の両肩を縫う赤い目
	var thread_w := Look.felt(Color(0.96, 0.95, 0.90), 3.0)
	var thread_r := Look.felt(Color(0.78, 0.18, 0.16), 3.0)
	for i in 9:
		var w := -half + 0.25 + (KICK_W - 0.5) * i / 8.0
		var p := Vector3(lip.x, lip_y, lip.y) + side3 * w - up_dir * 0.2 + nrm * 0.05
		_stitch(p, lip_basis * Basis(Vector3.RIGHT, PI / 2), 0.34, thread_w)
	for sgn in [-1.0, 1.0]:
		var s := 1.2
		while s < KICK_L - 0.3:
			var p0: Vector2 = at.call(s, sgn * (half - 0.3))
			var p1: Vector2 = at.call(s + 0.3, sgn * (half - 0.3))
			var a := Vector3(p0.x, _y(p0.x, p0.y) + rise.call(s) - KICK_BURY + 0.02, p0.y)
			var b := Vector3(p1.x, _y(p1.x, p1.y) + rise.call(s + 0.3) - KICK_BURY + 0.02, p1.y)
			_stitch((a + b) * 0.5, Basis.looking_at(b - a, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2), a.distance_to(b), thread_r)
			s += 0.55
	# 旗: 縁の両脇の雪に
	for sgn in [-1.0, 1.0]:
		var p: Vector2 = at.call(KICK_L, sgn * (half + 1.1))
		var flag := _put("res://props/flag_%s.glb" % ("red" if sgn < 0.0 else "navy"), p.x, p.y, atan2(f.x, f.y) + PI / 2 * sgn)
		flag.scale = Vector3.ONE * 0.85


## 糸の 1 目（細い円柱）。basis の y が糸の向き
## 円柱は長さ 1 m の 1 つを使い回し、長さの分だけ糸の向きに伸ばす（同じ形なので、_batch_props でまとめて描ける）
static var _stitch_mesh: CylinderMesh

func _stitch(at: Vector3, basis: Basis, len: float, mat: Material) -> void:
	if _stitch_mesh == null:
		_stitch_mesh = CylinderMesh.new()
		_stitch_mesh.top_radius = 0.028
		_stitch_mesh.bottom_radius = 0.028
		_stitch_mesh.height = 1.0
		_stitch_mesh.radial_segments = 6
		_stitch_mesh.rings = 1
	var m := MeshInstance3D.new()
	m.mesh = _stitch_mesh
	m.material_override = mat
	m.transform = Transform3D(basis * Basis.from_scale(Vector3(1.0, len, 1.0)), at)
	add_child(m)


## 手すり: 下の斜面のまんなか寄りに、毛糸を巻いた木の棒を 2 本並べた長いレール。上の端は雪とほぼ同じ高さで、下へ行くほど雪から浮く
## （乗り口で立ち上がると、ソリが勢いをなくして止まる）。
## 当たりは 2 本の棒にまたがる平らな板（細い棒 1 本だとソリが釣り合わず落ちる）。滑り木がよく滑るよう摩擦はほぼ 0
const RAIL_W := 0.9          # 当たりの板の幅 (m)
const RAIL_GAP := 0.36       # 2 本の棒の、まんなかからの距離 (m)

func _rail(top: Vector2, bottom: Vector2) -> void:
	var a := Vector3(top.x, _y(top.x, top.y) - 0.06, top.y)   # 雪にもぐって始まる（段に引っかからない）
	var b := Vector3(bottom.x, _y(bottom.x, bottom.y) + RAIL_H, bottom.y)
	var along2 := (bottom - top).normalized()
	var length2 := top.distance_to(bottom)
	var body := StaticBody3D.new()
	body.name = "MountainRail"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.02
	body.physics_material_override = pm
	add_child(body)
	var wood := Look.wood(Color(0.55, 0.38, 0.24))
	var yarns := [Look.felt(Color(0.80, 0.22, 0.18), 1.5), Look.felt(Color(0.95, 0.93, 0.86), 1.5), Look.felt(Color(0.20, 0.30, 0.55), 1.5)]
	var mid := (a + b) * 0.5
	var len := a.distance_to(b)
	var basis := Basis.looking_at((b - a).normalized(), Vector3.UP)
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
			ring.transform = Transform3D(bar_basis, a.lerp(b, (k + 0.5) / steps) + off)
			add_child(ring)
	# 支柱と、2 本をつなぐ横木: 3 m おき
	var side3 := Vector3(-along2.y, 0, along2.x)   # 手すりの横（水平）
	var tie_basis := Basis(side3, Vector3.UP, side3.cross(Vector3.UP))
	var s := 3.0
	while s < length2 + 0.1:
		var p2 := top + along2 * s
		var at := a.lerp(b, s / length2)
		var ground := _y(p2.x, p2.y)
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.06
			pc.bottom_radius = 0.07
			pc.height = at.y - ground + 0.2
			post.mesh = pc
			post.material_override = wood
			var foot: Vector3 = side3 * RAIL_GAP * side
			post.position = Vector3(p2.x + foot.x, (at.y - 0.1 + ground - 0.2) * 0.5, p2.y + foot.z)
			add_child(post)
		var tie := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(RAIL_GAP * 2.0 + 0.2, 0.08, 0.12)
		tie.mesh = tb
		tie.material_override = wood
		tie.basis = tie_basis
		tie.position = Vector3(p2.x, at.y - 0.22, p2.y)
		add_child(tie)
		s += 3.0
