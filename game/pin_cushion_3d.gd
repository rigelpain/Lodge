extends SubViewport
## 左下の方位磁針: 3D のピンクッションと待ち針（代表の言葉:「剣山がいま 2D でペタンコなのも見づらいから、3D で作り直して」）。
## 小さな自分だけの世界に、ふっくらした四角いフェルトの枕（look.gd の felt）と玉縁のレースを置き、斜め上の後ろから見下ろす。
## 自分のソリ（owner_id が自分）の数だけ玉の付いた待ち針が刺さり、そのソリの方へ 3D で倒れる:
##   水平の向き = 自分の見ている向きを基準にした方角（奥が前、右が右）。ソリのある側の斜面に刺す
##   立ち上がり = ソリが上にあれば立ち、下にあれば寝る（35° ＋ 見上げる・見下ろす角度。8〜80°）。後ろのソリの針は、
##   見下ろすカメラの向きと重なって点にならないよう、寝かせる
##   乗っているソリの針は、クッションの上に寝かせる
## 玉はソリのメインカラーでつやがあり、針はクッションに影を落とす。明るさは本体の画面のトーンマップと露出に合わせる。
## hud.gd が、この絵を名札の上に描き、針の玉の所（head_points）に距離の巻尺を重ねる。

const Look := preload("res://look.gd")
const SledTags := preload("res://sled_tags.gd")

const PX := Vector2i(240, 200)     # 描く解像度（画面では HUD の大きさに合わせて伸び縮み）
const HALF := 0.5                  # クッションの半分の大きさ
const THICK := 0.2                 # まんなかの厚みの半分
const PIN_LEN := 0.62
const MAX_PINS := 8

var main: Node3D
var _cushion: MeshInstance3D
var _felt: StandardMaterial3D
var _lace: MultiMeshInstance3D
var _lace_mat: StandardMaterial3D
var _pins: Array[Node3D] = []
var _heads: Array[MeshInstance3D] = []
var _cam: Camera3D
var _env: Environment
var _col := Color(-1, 0, 0)
var head_points: Array = []        # [絵の中の玉の位置（px）, 距離 m（0 は乗っている）] 。hud.gd が巻尺を重ねる
var count := 0                     # 立っている針の数（0 なら hud.gd は描かない）


func _init() -> void:
	size = PX
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _ready() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.80, 0.84, 0.95)
	_env.ambient_light_energy = 0.35
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_white = 6.0
	_env.tonemap_exposure = 0.7
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	var sun := DirectionalLight3D.new()   # 左の奥の上から。ふくらみの右と手前に陰、針の影は右手前へ
	sun.rotation_degrees = Vector3(-38, -115, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.92, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 4.0
	sun.shadow_bias = 0.02
	add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 1.75
	_cam.position = Vector3(0, 1.65, 1.25)   # 斜め上の後ろから、約 50° で見下ろす
	add_child(_cam)
	_cam.look_at(Vector3(0, 0.22, 0))
	_cam.current = true
	_felt = Look.felt(Color(0.96, 0.78, 0.82), 3.0)
	_felt.rim = 0.12   # ふちの毛羽の光を弱く（強いと、淡い色のふくらみの陰が飛ぶ）
	_felt.normal_scale = 0.5
	_cushion = MeshInstance3D.new()
	_cushion.mesh = _pillow_mesh()
	_cushion.material_override = _felt
	add_child(_cushion)
	_make_lace()
	for i in MAX_PINS:
		_make_pin()


## ふっくらした四角い枕: 上と下の面が、縁で薄く合わさる（厚み = THICK × (1-|x|^4)^½ × (1-|z|^4)^½）
func _pillow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 22
	for side in [1.0, -1.0]:
		for j in n + 1:
			for i in n + 1:
				var x := -1.0 + 2.0 * i / n
				var z := -1.0 + 2.0 * j / n
				var t := THICK * sqrt(maxf(0.0, 1.0 - pow(absf(x), 4.0))) * sqrt(maxf(0.0, 1.0 - pow(absf(z), 4.0)))
				st.set_uv(Vector2(x, z) * 0.5 + Vector2(0.5, 0.5))
				st.add_vertex(Vector3(x * HALF, THICK + side * t, z * HALF))
	var row := n + 1
	for k in 2:
		var off := k * row * row
		for j in n:
			for i in n:
				var a := off + j * row + i
				var idx := [a, a + 1, a + row, a + 1, a + row + 1, a + row]
				if k == 1:
					idx = [a, a + row, a + 1, a + 1, a + row, a + row + 1]
				for q in idx:
					st.add_index(q)
	st.generate_normals()
	return st.commit()


## 玉縁のレース: 縫い目（縁、高さ THICK）にぽこぽこした白い玉
func _make_lace() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.032
	sm.height = 0.064
	sm.radial_segments = 8
	sm.rings = 4
	mm.mesh = sm
	var per := 18
	mm.instance_count = per * 4
	var k := 0
	for side in 4:
		for i in per:
			var t := -1.0 + 2.0 * (i + 0.5) / per
			var p: Vector2 = [Vector2(t, 1), Vector2(1, -t), Vector2(-t, -1), Vector2(-1, t)][side]
			mm.set_instance_transform(k, Transform3D(Basis(), Vector3(p.x * HALF * 1.02, THICK, p.y * HALF * 1.02)))
			k += 1
	_lace = MultiMeshInstance3D.new()
	_lace.multimesh = mm
	_lace_mat = Look.felt(Color(0.97, 0.95, 0.91), 6.0)
	_lace_mat.rim = 0.1
	_lace.material_override = _lace_mat
	add_child(_lace)


func _make_pin() -> void:
	var pivot := Node3D.new()
	add_child(pivot)
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.016
	cm.bottom_radius = 0.012
	cm.height = PIN_LEN
	cm.radial_segments = 6
	shaft.mesh = cm
	shaft.position.y = PIN_LEN * 0.5
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.86, 0.88, 0.92)
	steel.metallic = 0.5
	steel.roughness = 0.35
	shaft.material_override = steel
	pivot.add_child(shaft)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	head.mesh = sm
	head.position.y = PIN_LEN
	var gloss := StandardMaterial3D.new()
	gloss.roughness = 0.25
	gloss.metallic_specular = 0.8
	gloss.emission_enabled = true   # 陰でも色が沈まないよう、自分の色を少し光らせる
	gloss.emission_energy_multiplier = 0.25
	head.material_override = gloss
	pivot.add_child(head)
	pivot.visible = false
	_pins.append(pivot)
	_heads.append(head)


## クッションの色（自分の名札の cushion の部品）と、本体の画面の露出をそろえる
func set_color(c: Color) -> void:
	if c.is_equal_approx(_col):
		return
	_col = c
	_felt.albedo_color = c.darkened(0.12)   # 淡い色は光で白く飛びやすいので、少し沈める


## 毎コマ: 自分のソリの向きで針を立てる。cam は本体のカメラ、me は自分
func update_pins(cam: Camera3D, me: Node3D) -> void:
	if main and main.get("env"):
		_env.tonemap_exposure = main.env.tonemap_exposure
	head_points = []
	count = 0
	if cam == null or me == null:
		_hide_from(0)
		return
	var fwd: Vector3 = -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var list := []
	for s in main.get_tree().get_nodes_in_group("sleds"):
		if is_instance_valid(s) and s.visible and int(s.get("owner_id")) == int(me.get("id")):
			list.append(s)
	for s in list:
		if count >= MAX_PINS:
			break
		var pin: Node3D = _pins[count]
		var head: MeshInstance3D = _heads[count]
		var hc: Color = s.color() if s.has_method("color") else Color(0.8, 0.24, 0.2)
		(head.material_override as StandardMaterial3D).albedo_color = hc
		(head.material_override as StandardMaterial3D).emission = hc
		pin.visible = true
		var riding: bool = me.get("mode") == 2 and me.get("sled") == s
		var dist := 0.0
		if riding:   # 乗っている: クッションの上に寝かせる
			pin.transform = Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(-0.3, THICK * 2.0 + 0.02, 0.05))
		else:
			var w: Vector3 = s.global_position + Vector3.UP * 0.3 - cam.global_position
			dist = w.length()
			var h := Vector2(w.dot(right), w.dot(fwd))
			var hd := h.normalized() if h.length() > 0.01 else Vector2(0, 1)
			var elev := atan2(w.y, maxf(h.length(), 0.01))
			var pa := clampf(deg_to_rad(35.0) + elev, deg_to_rad(8.0), deg_to_rad(80.0))
			if hd.y < 0.0:   # 後ろのソリ: 手前へ倒れる針は、見下ろすカメラの向きと重なって点になるので、寝かせる
				pa *= 1.0 + hd.y * 0.6
			var dir := (Vector3(hd.x, 0, -hd.y) * cos(pa) + Vector3.UP * sin(pa)).normalized()
			# 刺す所: ソリのある側の斜面の、上の面の上
			var q := hd * 0.36
			var top := THICK + THICK * sqrt(maxf(0.0, 1.0 - pow(q.x, 4.0))) * sqrt(maxf(0.0, 1.0 - pow(q.y, 4.0)))
			var at := Vector3(q.x * HALF, top - 0.02, -q.y * HALF)
			var y := dir
			var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
			pin.transform = Transform3D(Basis(x, y, x.cross(y)), at)
		head_points.append([_cam.unproject_position(pin.to_global(Vector3(0, PIN_LEN, 0))), dist])
		count += 1
	_hide_from(count)


func _hide_from(i: int) -> void:
	for k in range(i, _pins.size()):
		_pins[k].visible = false
