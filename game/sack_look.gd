extends RefCounted
## 米袋の座り心地の見た目。乗ると、お尻の所がへこんで、まわりがふくらむ（わらが詰まっている感じ）。
## 乗っているあいだは少し厚くして、平らな袋の上に座っているのがわかるようにする。当たり判定は変えない。
## 形は米袋の glb の頂点を動かして作り、段ごとにソリに覚えておく（乗るたびに作り直さない）。
##   0 ふだん / 1 腰を下ろした瞬間（深くへこみ、横へ広がる） / 2 乗っているあいだ（厚く、浅いへこみ）

## 段ごとの [厚みの倍率, へこみの深さ (m), まわりのふくらみ (m), 横への広がり]
const STAGES := [[1.0, 0.0, 0.0, 1.0], [1.05, 0.06, 0.035, 1.07], [1.45, 0.05, 0.03, 1.04]]
const DENT_R := 0.17         # へこみの半径 (m)
const RING_R := 0.27         # ふくらむ輪の半径 (m)


## gs の米袋の形を段 stage にする。seat は座る所（ソリの座標）
static func set_stage(gs: Node3D, seat: Vector3, stage: int) -> void:
	var body: Node3D = gs.get("_body")
	if body == null:
		return
	var found := body.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		return
	var mi := found[0] as MeshInstance3D
	if not mi.has_meta("sack_rest"):
		mi.set_meta("sack_rest", mi.mesh)
	var key := "sack_stage_%d" % stage
	if stage == 0:
		mi.mesh = mi.get_meta("sack_rest")
		return
	if not mi.has_meta(key):
		mi.set_meta(key, _deform(mi.get_meta("sack_rest"), mi.transform.affine_inverse() * seat, STAGES[stage]))
	mi.mesh = mi.get_meta(key)


static func _deform(src: Mesh, seat: Vector3, st: Array) -> ArrayMesh:
	var a := src.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var top := 0.0
	for v in verts:
		top = maxf(top, v.y)
	for i in verts.size():
		var v := verts[i]
		var h := clampf(v.y / maxf(top, 0.01), 0.0, 1.0)
		var w := smoothstep(0.3, 1.0, h)                          # 上の面ほど動く
		var d := Vector2(v.x - seat.x, (v.z - seat.z) * 0.8).length()
		var dent := exp(-pow(d / DENT_R, 2.0))
		var ring := exp(-pow((d - RING_R) / 0.09, 2.0))
		var spread := 1.0 + (float(st[3]) - 1.0) * sin(PI * h)    # 横腹がふくらむ
		verts[i] = Vector3(v.x * spread, v.y * float(st[0]) + w * (-float(st[1]) * dent + float(st[2]) * ring), v.z * spread)
	a[Mesh.ARRAY_VERTEX] = verts
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var stool := SurfaceTool.new()
	stool.create_from(tmp, 0)
	stool.generate_normals()
	stool.generate_tangents()
	var out := stool.commit()
	out.surface_set_material(0, src.surface_get_material(0))
	return out


## 広げる動き（人形のコマ k）: 2 丸めた袋が前の宙で開きかける / 3 雪の上に落ちて、ばさっと広がる / 4〜 足もとに収まる
static func fling(gs: Node3D, k: int) -> void:
	var body: Node3D = gs.get("_body")
	if body == null:
		return
	var found := body.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		return
	var mi := found[0] as MeshInstance3D
	match k:
		2:
			mi.transform = Transform3D(Basis(Vector3.RIGHT, 0.5).scaled(Vector3(0.85, 1.0, 0.35)), Vector3(0, 0.38, -0.3))
		3:
			mi.transform = Transform3D(Basis.from_scale(Vector3(1.08, 0.7, 1.15)), Vector3(0, 0.0, -0.1))
		_:
			mi.transform = Transform3D.IDENTITY
