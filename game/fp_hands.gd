extends RefCounted
## 一人称の手。自分の人形と同じ色と柄の袖口から、紙の手がのぞく。
## 人形の袖は平たい板なので、目の前に置くと線にしか見えない。一人称のぶんはここで作る。
## 手の所（Node3D）の -z が腕の先の向き。袖はそこから肩のほう（+z）へ伸びる。

const Look := preload("res://look.gd")

## 人形ごとの袖（右、左）と手の色
const STYLE := {
	"kasa": {"sleeve": [["mizutama", "3E6E66", "CFE0D6"], ["kikko", "2F5A8F", "5D86B8"]], "hand": "F0D2A6"},
	"origami": {"sleeve": [["paper", "3B5F99"], ["paper", "3B5F99"]], "hand": "D9BE97"},
	"news": {"sleeve": [["burlap", "66773F"], ["burlap", "66773F"]], "hand": "E6DCC6"},
}
const SLEEVE_LEN := 0.22
const MOUTH_R := 0.078       # 袖口の半径


## 片方の手（side: 1 右、-1 左）を作り、layers の層に置く
static func make(kind: String, side: int, layers: int) -> Node3D:
	var st: Dictionary = STYLE.get(kind, STYLE["kasa"])
	var root := Node3D.new()
	var spec: Array = st["sleeve"][0 if side > 0 else 1]
	var cloth: StandardMaterial3D
	match spec[0]:
		"paper":
			cloth = Look.paper(Color(spec[1]))
		"burlap":
			cloth = Look.cloth(Color(spec[1]), 14.0)
		_:
			cloth = Look.wagara(spec[0], Color(spec[1]), Color(spec[2]), 6.0)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 袖: 六角の筒。袖口がいちばん広く、肩のほうへ少しすぼまる。紙を折ったように面ごとに陰をつける
	var cm := CylinderMesh.new()
	cm.top_radius = MOUTH_R * 0.72
	cm.bottom_radius = MOUTH_R
	cm.height = SLEEVE_LEN
	cm.radial_segments = 6
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var sleeve := _part(_flat(cm), cloth, layers)
	# 筒の y を腕の向き（+z が肩）に。袖口が手の少しうしろに来るように
	sleeve.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2).rotated(Vector3.FORWARD, 0.18 * side), Vector3(0, 0, 0.03 + SLEEVE_LEN * 0.5))
	root.add_child(sleeve)

	# 袖口の奥は暗い（筒の中が見えて、手が袖から出ているとわかる）
	var dm := CylinderMesh.new()
	dm.top_radius = MOUTH_R * 0.9
	dm.bottom_radius = MOUTH_R * 0.9
	dm.height = 0.002
	dm.radial_segments = 6
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.13, 0.1, 0.08)
	inner.roughness = 1.0
	var deep := _part(dm, inner, layers)
	deep.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2).rotated(Vector3.FORWARD, 0.18 * side), Vector3(0, 0, 0.05))
	root.add_child(deep)

	# 手: 紙を折った、角のある小さなミトン。指先は袖から少し出て、親指は内側
	var skin := Look.paper(Color(st["hand"]))
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	var hand := _part(_flat(sm), skin, layers)
	hand.transform = Transform3D(Basis(Vector3.RIGHT, -0.3) * Basis.from_scale(Vector3(1.0, 0.6, 1.3)), Vector3(0, -0.01, -0.045))
	root.add_child(hand)
	var tm := SphereMesh.new()
	tm.radius = 0.017
	tm.height = 0.034
	tm.radial_segments = 5
	tm.rings = 2
	var thumb := _part(_flat(tm), skin, layers)
	thumb.transform = Transform3D(Basis.from_scale(Vector3(0.9, 0.8, 1.4)), Vector3(-0.042 * side, 0.0, -0.05))
	root.add_child(thumb)
	return root


static func _part(mesh: Mesh, mat: Material, layers: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.layers = layers
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## 面ごとに向きを分けて、折り紙のような角を出す
static func _flat(mesh: PrimitiveMesh) -> ArrayMesh:
	var a := mesh.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var p0 := v[idx[t]]
		var p1 := v[idx[t + 1]]
		var p2 := v[idx[t + 2]]
		var n := (p2 - p0).cross(p1 - p0)
		if n.length() < 1e-9:
			continue
		n = n.normalized()
		if n.dot(nn[idx[t]] + nn[idx[t + 1]] + nn[idx[t + 2]]) < 0.0:
			n = -n
		for k in 3:
			st.set_normal(n)
			st.set_uv(uv[idx[t + k]])
			st.add_vertex(v[idx[t + k]])
	return st.commit()
