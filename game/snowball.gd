extends RigidBody3D

const Doll := preload("res://doll.gd")
## 雪玉。ちぎった綿を丸めた、軽いフェルトの玉。物として飛び、人・ソリ・地面・ロッジに当たると崩れる。
## 軽いので、当たったソリはほとんど動かない。人には痛みも押し戻しもなく、のけぞるだけ（emotes.gd の hit）。
## 人は乗っている間や押している間は当たりの形を切っているので、人への当たりは人形の背丈の筒で見る。
## 崩れると綿の粉が散り、当たった所に綿の雪が少し残って、しばらくで消える。

const RADIUS := Doll.BALL_R
const LIFE := 6.0            # どこにも当たらなかったら消える (s)
const BODY_R := 0.32         # 人の当たりの筒の半径 (m)

var hub: Node3D              # emotes.gd
var thrower := -1            # 投げた人の番号（自分には当たらない）
var _t := 0.0
var _last := Vector3.INF
var _vel := Vector3.ZERO      # 前のコマの速さ（当たった瞬間は跳ね返ったあとの速さになっているので）
var _done := false

func _ready() -> void:
	mass = 0.15
	gravity_scale = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	linear_damp = 0.05
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = RADIUS
	col.shape = sh
	add_child(col)
	var m := MeshInstance3D.new()
	m.mesh = Doll.ball_mesh()
	m.material_override = Doll.ball_material()
	add_child(m)
	# 投げた人の体には当たらない
	var me: Node3D = hub.who_of(thrower) if hub else null
	if me is PhysicsBody3D:
		add_collision_exception_with(me)
	body_entered.connect(_on_body)


func _physics_process(dt: float) -> void:
	_t += dt
	if _done:
		return
	if _t > LIFE or global_position.y < -50.0:
		queue_free()
		return
	var p := global_position
	if _last == Vector3.INF:
		_last = p
	# 人の背丈の筒と、このコマで進んだ線分が交わるか
	for id in hub.people:
		if id == thrower:
			continue
		var who: Node3D = hub.who_of(id)
		if who == null or who.get("doll") == null:
			continue
		var feet: Vector3 = who.doll.global_position
		var h: float = who.doll.height()
		var hit := _segment_vs_body(_last, p, feet, h)
		if hit != Vector3.INF:
			var dir := linear_velocity.normalized()
			_done = true
			hub.ball_hit_person(self, id, hit, dir)
			queue_free()
			return
	_last = p
	_vel = linear_velocity


## 線分 a→b が、足もと feet から高さ h の縦の筒に入る最初の所。入らなければ INF
func _segment_vs_body(a: Vector3, b: Vector3, feet: Vector3, h: float) -> Vector3:
	var steps := 4
	for i in steps + 1:
		var q := a.lerp(b, float(i) / steps)
		var d := Vector2(q.x - feet.x, q.z - feet.z).length()
		if d < BODY_R + RADIUS and q.y > feet.y + 0.05 and q.y < feet.y + h:
			return q
	return Vector3.INF


func _on_body(body: Node) -> void:
	if _done:
		return
	var dir := (_vel if _vel.length() > 0.1 else linear_velocity).normalized()
	# 人の体に当たったら、のけぞる側（歩いている人は当たりの形を持っている）
	for id in hub.people:
		if hub.people[id] == body and id != thrower:
			_done = true
			hub.ball_hit_person(self, id, global_position, dir)
			queue_free()
			return
	_done = true
	var p := global_position
	var n := -dir
	# 当たった面の向きを短い光線で確かめる（分からなければ、飛んできた向き）
	var q := PhysicsRayQueryParameters3D.create(p - dir * 0.3, p + dir * 0.4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		p = hit.position
		n = hit.normal
	hub.ball_splat(p, n, body)
	queue_free()


# ---------------------------------------------------------------- 崩れた雪

## 当たった所に、綿の粉を散らし、綿の雪を少し残す。on に付けて一緒に動かす（ソリに当たれば、ソリと滑っていく）
static func splat_at(on: Node3D, point: Vector3, normal: Vector3, small := false) -> void:
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.emitting = false
	puff.local_coords = false
	puff.amount = 5 if small else 8
	puff.lifetime = 0.9
	puff.explosiveness = 0.95
	puff.direction = Vector3(0, 0, 1)
	puff.spread = 70.0
	puff.initial_velocity_min = 0.6
	puff.initial_velocity_max = 1.6
	puff.gravity = Vector3(0, -2.5, 0)
	puff.damping_min = 2.0
	puff.damping_max = 3.0
	puff.angle_min = 0.0
	puff.angle_max = 360.0
	puff.scale_amount_min = 0.35
	puff.scale_amount_max = 0.7
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(1.0, 1.2))
	puff.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	puff.color_ramp = ramp
	puff.mesh = _cotton_quad(0.22)
	on.get_tree().root.add_child(puff)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	puff.global_transform = Transform3D(Basis.looking_at(-normal, up), point + normal * 0.03)
	puff.restart()
	puff.finished.connect(puff.queue_free)
	if small:
		return
	# 残る雪: 当たった面に貼りつく、ちぎった綿の平たい塊。8 秒で薄れて消える
	var patch := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.26, 0.26)
	patch.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = Doll.cotton_texture()
	mat.albedo_color = Color(0.98, 0.97, 0.94)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.uv1_scale = Vector3(0.5, 0.5, 1)
	mat.roughness = 1.0
	patch.material_override = mat
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	on.add_child(patch)
	patch.global_transform = Transform3D(Basis.looking_at(-normal, up).rotated(normal, randf() * TAU), point + normal * 0.015)
	var tw := patch.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 2.0)
	tw.tween_callback(patch.queue_free)


static var _quad: QuadMesh


## 白い息と同じ綿の板（カメラを向く）
static func _cotton_quad(size: float) -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(size, size)
		var sh := Shader.new()
		sh.code = Doll.BREATH_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("cotton", Doll.cotton_texture())
		_quad.material = mat
	return _quad
