extends MultiMeshInstance3D
## ロッジ前の地図の看板に、このワールドにいる人（遊ぶ人・つないだ人・CPU）を小さなまち針で刺す。
## 2026-11-06 代表「ロッジ前の地図にこのワールドのキャラクター（CPU含む）を小さくて短いまち針でリアルタイムマッピングして欲しい。
## キャラカラーだけまち針に反映させて名前とかは表示しない感じにしたいです。」
## 名簿は emotes.gd の people（来た人・帰った人はここに出入りする）。色は craft.gd の color_of。どの画面でも、その画面の体の位置を読む。
## 位置は人形と同じ 12 コマ／秒で見直す。看板から遠いときは隠して、名簿も読まない。

const Doll := preload("res://doll.gd")

const HEAD_R := 0.055        # 玉の半径 (m)。ペグの玉と同じ
const LONG := 0.15           # 看板の面から玉の中心まで (m)
const NEEDLE_R := 0.007      # 針の太さ（半径, m）
const FACE_Z := 0.09         # 看板の面（area_flags.gd の face の位置）
const SEE := 60.0            # これより遠くから見ているときは隠す (m)。玉が 1 画素ほどになる距離
const ROOM := 16             # はじめに取っておく本数（人 8 ＋ CPU）。足りなければ増やす

var main: Node3D
var to_board: Callable       # 世界の (x, z) → 看板の上の (x, y)。area_flags.gd の _on_board
var _frame := -1


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # 12 コマ／秒で動くので、あいだを埋めない
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _pin_mesh()
	multimesh.instance_count = ROOM
	multimesh.visible_instance_count = 0
	# 刺さる範囲は看板の中だけ（入れ替えのたびに箱を測り直さない）
	multimesh.custom_aabb = AABB(Vector3(-5, 0, -0.1), Vector3(10, 8, LONG + HEAD_R * 2.0 + 0.2))


func _physics_process(_dt: float) -> void:
	var f := Doll.frame_index()
	if f == _frame:
		return
	_frame = f
	var cam := get_viewport().get_camera_3d()
	visible = cam != null and cam.global_position.distance_squared_to(global_position) < SEE * SEE
	if visible:
		_stick()


## 全員のまち針を、いまいる所へ
func _stick() -> void:
	var people: Dictionary = main.emotes.people
	if people.size() > multimesh.instance_count:
		multimesh.visible_instance_count = 0
		multimesh.instance_count = people.size() + 4
	var n := 0
	for id in people:
		var who: Node3D = people[id]
		if not is_instance_valid(who) or not who.is_inside_tree():
			continue
		var at: Vector3 = who.global_position
		var on: Vector2 = to_board.call(Vector2(at.x, at.z))
		# 少しずつ傾けて刺す（同じ所に集まっても、玉がぴったり重ならない）。向きは人ごとに決まっていて、動いても変わらない
		var tilt := Basis.from_euler(Vector3(-0.28 + 0.12 * sin(id * 1.7), 0.2 * sin(id * 2.3), 0.0))
		multimesh.set_instance_transform(n, Transform3D(tilt, Vector3(on.x, on.y, FACE_Z)))
		multimesh.set_instance_color(n, main.craft.color_of(id))
		n += 1
	multimesh.visible_instance_count = n


## いまのまち針（確かめの道具が読む）: [{at: 看板の上の位置, color}]
func pins() -> Array:
	var out := []
	for i in multimesh.visible_instance_count:
		var o := multimesh.get_instance_transform(i).origin
		out.append({"at": Vector2(o.x, o.y), "color": multimesh.get_instance_color(i)})
	return out


## 形（原点が看板の面。+Z が手前）: フェルトの玉と、細い針。玉の色は人ごとの色（フェルトの生地に掛ける）
static func _pin_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var head := SphereMesh.new()
	head.radius = HEAD_R
	head.height = HEAD_R * 1.9
	head.radial_segments = 12
	head.rings = 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(head, 0, Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0, 0)), Vector3(0, 0, LONG)))
	st.set_material(_head_material())
	st.commit(mesh)
	var needle := CylinderMesh.new()
	needle.top_radius = NEEDLE_R
	needle.bottom_radius = NEEDLE_R * 0.6
	needle.height = LONG + 0.02
	needle.radial_segments = 6
	needle.rings = 1
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(needle, 0, Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0, 0)), Vector3(0, 0, (LONG - 0.02) / 2.0)))
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.84, 0.88)   # 対決の円の待ち針と同じ（duel.gd）
	steel.metallic = 0.8
	steel.roughness = 0.3
	st.set_material(steel)
	st.commit(mesh)
	return mesh


static func _head_material() -> StandardMaterial3D:
	var felt := preload("res://look.gd").felt(Color.WHITE, 2.0)
	felt.vertex_color_use_as_albedo = true
	felt.vertex_color_is_srgb = true   # 人の色は札や HUD と同じ sRGB の値
	felt.albedo_color = Color(0.72, 0.72, 0.72)   # 看板の布と同じく、雪山の光で白く飛ばないように沈める（LIT）
	felt.rim_enabled = false   # 小さな玉はリムで色が抜けて、人の色に見えなくなる
	return felt
