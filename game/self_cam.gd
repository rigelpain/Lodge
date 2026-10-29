extends CanvasLayer
## 右下の小窓: 自分の人形を前から映す（一人称では見えない「いま自分がどう見えているか」）。
## 刺繍枠（木の輪と真鍮のねじ）の丸窓に、赤い糸のランニングステッチで縁取り、中の絵はサテンステッチで縫ったように描く。
## カメラは人形の正面に付き、位置はぴったり付いて行き（速く滑っても外れない）、向きは少し遅れて回る（急に振り向いても酔わない）。
## 笠のてっぺん・上げた手から足もとまでの全身が、少し余白をもって収まる距離に置く。
## 映すのは自分だけ: 自分の体の層（層 2: 人形・連れのペット・手に持った物・手形のアップリケ・息）と、小窓専用の層（層 6: 足もとの丸い影・
## 自分のハイタッチの紙吹雪）。地面・ソリ・ほかの人・木・ロッジ・空は映さず、背景は枠に張った麻布の地。乗っていれば座った姿だけ。
## 小窓のカメラだけの環境（空・SSAO・照り返しなし）で、PX 四方に EVERY コマに 1 回だけ描く。
## 手に持った物は、一人称の右手にしか出ていなかったので、人形の右手にも持たせる（三人称と右上の映像にも出る）。

const Icons := preload("res://hud_icons.gd")
const Player := preload("res://player.gd")

const PX := 224               # 描く大きさ（正方形の px）。窓とほぼ同じ。刺繍の糸目は窓の側で描く
const STITCH_PX := 2.6        # 糸 1 本の、画面での幅（1080 のとき, px）
const EVERY := 2              # 何コマに 1 回描くか
const DIAM := 236.0           # 画面での丸窓の直径（1080 のとき, px）
const MARGIN := 18.0          # 画面の端からの間（1080 のとき, px）
const FOV := 36.0
const DIST := 3.0             # 人形からの距離の目安 (m)。実際は全身が収まるよう _extent() から決める
const MARGIN_K := 1.3         # 全身の高さに対する窓の高さ（上下の余白）
const ABOVE := -0.1           # 見る所からの高さ (m)。少し下から見上げ、前へ傾いても笠の下の顔が見える
const BELOW_WORK := 0.35      # ソリを押す・紐を引くときは前へ大きく傾くので、さらに下げる (m)
const TURN := 2.5             # 向きの追いつき（1/s）。小さいほどゆっくり回る
const AIM_K := 8.0            # 見る所（頭の少し下）の追いつき（1/s）。12 コマの姿勢の段を均す
const LAYER := 1 << 5         # 小窓だけに映す層（層 6）。本体の画面・右上の 360° 映像・三人称には映らない
const SHADOW_R := 0.42        # 足もとの丸い影の半径（人形の大きさのまま, m）
const CLOTH_AMB := 1.2        # 布の地が環境光（空）から受ける割合（雪のように明るい布）
const CLOTH_MAX := 1.4        # 布の地の明るさの上限。日なたでも白く飛ばず、生成りに見える
const SHADE_FILL := 1.8       # 陰・屋内で、人形への環境光を何倍にするか（本体の照り返しの代わり）
const SHADE_GLOW := 0.5       # 陰・屋内で、布の地に足す明るさ（ランプや壁の照り返しの代わり）
const CLOTH_K := 0.85         # 布の地の照り返しの強さ（日なたの雪より少し落とし、白く飛ばさない）
const ENV_EVERY := 0.5        # 本体の環境を写す間隔 (s)

var main: Node3D
var player: CharacterBody3D
var cam: Camera3D
var vp: SubViewport
var hidden := false
var plain_frame := false      # true なら、木の輪とねじは描かない（hud_plates.gd の立体の刺繍枠を重ねる）。赤い糸の縁取りだけ

var _frame: Control
var _mat: ShaderMaterial
var _yaw := INF               # INF のあいだは、まだ向きを決めていない
var _rot := Quaternion.IDENTITY   # 均した人形の向き
var _aim := Vector3.INF
var _fit := DIST              # 全身が収まる距離 (m)
var _env_t := ENV_EVERY
var _bg_energy := 1.0
var _light_t := 0
var _low := 0.0               # 押す・引くときに下げている分 (m)
var _shadow: MeshInstance3D   # 足もとの丸い影（地面を描かないので、浮いて見えないように）
var _tick := 0
var _held: Node3D             # 人形の右手に持たせた物
var _held_key := ""


func _ready() -> void:
	layer = 2
	vp = SubViewport.new()
	vp.size = Vector2i(PX, PX)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0   # ロッジの灯りの影は描かない
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	cam.far = 60.0
	cam.cull_mask = (1 << 1) | LAYER   # あなたの体と、小窓だけの物
	cam.environment = _fabric_env()
	vp.add_child(cam)
	cam.current = true
	if player and player.doll:
		_make_shadow()

	_frame = Frame.new()
	_frame.sc = self
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	var view := TextureRect.new()
	view.texture = vp.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.show_behind_parent = true
	var mat := ShaderMaterial.new()
	_mat = mat
	mat.shader = Shader.new()
	mat.shader.code = MASK_SHADER
	view.material = mat
	_frame.add_child(view)
	_frame.view = view


## 小窓のカメラだけの環境: 本体の環境（main.gd の _make_world、時刻で daycycle.gd が変える）の写しで、トーンマップ・露出・
## 環境光は本体と同じ。背景だけ麻布の色にし、その明るさは本体の光の当たり方（日なた・日かげ・夜・屋内）に合わせる（_sync_env）。
## 背景の色のままの所は縫わずに布の地として見せる。空・SSAO・照り返し・にじみ・霧は描かないので軽い
func _fabric_env() -> Environment:
	var e: Environment = main.env.duplicate() if main and main.env else Environment.new()   # 空の資源は共有（環境光が時刻で変わる）
	e.background_mode = Environment.BG_COLOR
	e.background_color = LINEN
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.glow_enabled = false
	e.fog_enabled = false
	e.volumetric_fog_enabled = false
	e.sdfgi_enabled = false
	return e


## 本体の時刻の変化を写し、布の地の明るさを決める。布は上を向いた紙のように、日なたなら陽と環境光、陰なら環境光だけで照らす
func _sync_env() -> void:
	var src: Environment = main.env
	var e := cam.environment
	if src == null or e == null:
		return
	e.tonemap_exposure = src.tonemap_exposure
	var sun: DirectionalLight3D = main.sun_light
	var shaded := sun == null or _in_shade(sun.global_basis.z)
	# 本体では、まわりの床・壁・雪の照り返し（SSIL）が人形の陰の側を明るくする。小窓には周りがないので、陰の中では環境光を足して補う
	e.ambient_light_energy = src.ambient_light_energy * (SHADE_FILL if shaded else 1.0)
	var lit := src.ambient_light_energy * CLOTH_AMB + (SHADE_GLOW if shaded else 0.0)
	if sun and sun.visible and not shaded:
		lit += sun.light_energy * maxf(sun.global_basis.z.dot(Vector3.UP), 0.0)   # 陽が上から当たる度合い
	lit = minf(lit * CLOTH_K, CLOTH_MAX)
	e.background_energy_multiplier = lit
	_bg_energy = lit
	if _shadow:
		(_shadow.material_override as ShaderMaterial).set_shader_parameter("bg_energy", lit)


## 灯り（太陽・月・ロッジのランプ）も描画の層に属し、カメラは自分の映す層の灯りしか当てない。
## 小窓は世界の層（層 1）を映さないので、灯りに小窓の層を足す（本体の画面の見え方は変わらない）。後から置かれる灯りのために、ときどき見直す
func _share_lights() -> void:
	for l in main.find_children("*", "Light3D", true, false):
		(l as Light3D).layers |= LAYER


## 頭から陽の方へ、建物や木があるか（ロッジの屋根・木の陰）。丘の雪面は見ない（低い夕日だと遠くの斜面に当たってしまう）
func _in_shade(to_sun: Vector3) -> bool:
	var from: Vector3 = player.global_position + Vector3.UP * player.doll.height()
	var q := PhysicsRayQueryParameters3D.create(from, from + to_sun * 20.0)
	var ex: Array[RID] = [player.get_rid()]
	for _i in 4:
		q.exclude = ex
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return false
		if hit.collider is StaticBody3D and not _is_ground(hit.collider):
			return true
		ex.append(hit.rid)
	return false


var _ground_cache := {}

## 丘の雪面（高さの地図の当たり）か
func _is_ground(body: Object) -> bool:
	if not _ground_cache.has(body):
		var yes := false
		for c in (body as Node).get_children():
			if c is CollisionShape3D and c.shape is HeightMapShape3D:
				yes = true
		_ground_cache[body] = yes
	return _ground_cache[body]


## 足もとの丸い影。地面を描かないので、浮いて見えないように置く（小窓だけの層）。刺繍では濃い糸の楕円に縫われる
func _make_shadow() -> void:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
// 半透明はこの小窓で描かれないので、不透明にして縁を背景の布の色へ混ぜる（背景は無地なので透けて見える）
uniform vec3 bg : source_color;
uniform float bg_energy = 1.0;   // 背景の明るさ（_sync_env）
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = 0.6 * (1.0 - smoothstep(0.45, 1.0, r));
	if (a < 0.03) discard;
	ALBEDO = mix(bg, bg * vec3(0.3, 0.33, 0.5), a) * bg_energy;
}
"""
	m.set_shader_parameter("bg", LINEN)
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * 2.0
	_shadow = MeshInstance3D.new()
	_shadow.mesh = pm
	_shadow.material_override = m
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.layers = LAYER
	# 人形の子にして、人形と一緒に動き・傾く（乗っていれば座面に敷かれる）
	var d = player.doll
	_shadow.position = Vector3(0, 0.01, 0)
	_shadow.scale = Vector3(1.0, 1.0, 0.8) * SHADOW_R * d._scale
	d.add_child(_shadow)

const LINEN := Color(0.95, 0.92, 0.85)   # 枠に張った麻布

## 丸く切り抜き、サテンステッチで縫った絵にする。色を刺繍糸の色数に分け、色の塊ごとに糸の向きを変えて（ゆるく曲げて）面を埋める。
## 糸は 1 本ずつ丸みの陰を付け、刺し目の長さは糸ごとにずらす。艶は糸の向きと光の向きで決まり、向きの違う塊が違って光る。
## 色の境は濃い糸で縁取る（ステムステッチ）。背景（左上の隅と同じ色）は縫わず、麻布の地のまま
const MASK_SHADER := """
shader_type canvas_item;
uniform float px = 236.0;        // 窓の直径（画面の px）
uniform float pitch = 2.4;       // 糸 1 本の幅（画面の px）
const vec2 SHEEN_DIR = vec2(-0.55, -0.83);   // 左上からの光（艶の向き）

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash1(float x) { return fract(sin(x * 91.3458) * 47453.5453); }

vec3 soft(sampler2D t, vec2 uv, float e) {   // 毛羽のむらを均して読む
	return (texture(t, uv) * 2.0 + texture(t, uv + vec2(e, 0.0)) + texture(t, uv - vec2(e, 0.0))
		+ texture(t, uv + vec2(0.0, e)) + texture(t, uv - vec2(0.0, e))).rgb / 6.0;
}

vec3 thread_color(vec3 c) {
	c = clamp(mix(vec3(dot(c, vec3(0.3, 0.55, 0.15))), c, 1.3), 0.0, 1.0);   // 刺繍糸らしく少し鮮やかに（明るさは本体のまま）
	return floor(c * 7.0 + 0.5) / 7.0;
}

bool is_cloth(vec3 c, vec3 ground) {
	return length(c - ground) < 0.04;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float e = 1.0 / px;
	vec2 p = UV * px;
	vec3 ground = texture(TEXTURE, vec2(0.02, 0.02)).rgb;       // 背景の色（窓の外の隅には何も映らない）
	vec3 c = soft(TEXTURE, UV, e);
	vec3 q = thread_color(c);
	vec3 col = ground * (0.97 + 0.03 * sin(p.x * 2.6) * sin(p.y * 2.6));   // 麻布の織り目（明るさは本体の光で照らした背景のまま）
	if (!is_cloth(c, ground)) {
		// 糸の向き: 色の塊ごとに決め、場所でゆるく曲げる
		float ang = hash(q.rg * 7.0 + q.b * 3.0) * 3.14159 + 0.35 * sin(p.x * 0.045 + p.y * 0.03 + q.r * 5.0);
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 nrm = vec2(-dir.y, dir.x);
		float across = dot(p, nrm) / pitch;
		float row = floor(across);
		float t = fract(across);
		float along = dot(p, dir) / (pitch * (5.0 + 4.0 * hash1(row))) + hash1(row + 17.0);
		float s = fract(along);
		float bulge = sin(t * 3.14159);                          // 糸の丸み
		float dip = smoothstep(0.0, 0.08, s) * smoothstep(1.0, 0.92, s);   // 刺し目の端は布にもぐる
		float body = mix(0.78, 1.06, bulge) * mix(0.85, 1.0, dip);
		// 艶: 糸が光の向きに沿うほど、糸の背が明るく光る
		float sheen = pow(abs(dot(dir, SHEEN_DIR)), 3.0) * pow(bulge, 5.0) * dip;
		vec3 th = q * body + ground * sheen * 0.3;   // 艶の明るさも、まわりの光に合わせる
		// 色の境の縁取り（濃い糸）
		vec3 qx = thread_color(soft(TEXTURE, UV + vec2(1.6 * e, 0.0), e));
		vec3 qy = thread_color(soft(TEXTURE, UV + vec2(0.0, 1.6 * e), e));
		float edge = step(0.25, length(qx - q) + length(qy - q));
		th = mix(th, q * 0.5 * mix(0.8, 1.1, bulge), edge * 0.5);
		col = th;
	}
	col = mix(col, ground, smoothstep(0.9, 1.0, r) * 0.25);
	COLOR = vec4(col, 1.0 - smoothstep(0.985, 1.0, r));
}
"""


func set_shown(on: bool) -> void:
	hidden = not on
	visible = on
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE if on else SubViewport.UPDATE_DISABLED


## 1080 で 1 の大きさ（hud.gd と同じ）
func ui() -> float:
	return clampf(get_viewport().get_visible_rect().size.y / 1080.0, 0.6, 2.0)


## 丸窓が画面の右から占める幅（px）。日時計はこの左に置く
func width() -> float:
	return (DIAM + MARGIN) * ui() if not hidden else 0.0


func _process(dt: float) -> void:
	_layout()
	# 刺繍枠は、滑っているあいだ風を受けて小刻みに震える（hud.gd が入れる Icons.wind。止まるとふわっと戻る）
	_frame.pivot_offset = _frame.size * 0.5
	_frame.rotation = Icons.wind_angle(5.0, 0.0, 0.03)
	_frame.position += Icons.wind_offset(5.0, 2.5 * ui())
	var dc := get_node_or_null("/root/DayCycle")
	if dc and "dial_right" in dc:
		dc.dial_right = 16.0 + width()
	if hidden or player == null:
		return
	_env_t += dt
	if _env_t >= ENV_EVERY:
		_env_t = 0.0
		_sync_env()
		_light_t -= 1
		if _light_t <= 0:
			_light_t = 10
			_share_lights()
	_tick += 1
	if _tick % EVERY == 0:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## カメラは物理のコマで置く（人形もそこで動く）。描くときは物理の補間でなめらかになる
func _physics_process(dt: float) -> void:
	if hidden or player == null or player.doll == null or player.doll.skel == null:
		return
	_sync_held()
	_place(dt)


func _layout() -> void:
	var u := ui()
	var vs := get_viewport().get_visible_rect().size
	var d := DIAM * u
	_frame.position = vs - Vector2(d, d) - Vector2(MARGIN, MARGIN) * u
	_frame.size = Vector2(d, d)
	_frame.view.position = Vector2.ZERO
	_frame.view.size = _frame.size
	_mat.set_shader_parameter("px", d)
	_mat.set_shader_parameter("pitch", maxf(STITCH_PX * u, 2.2))   # 小さい画面でも糸が潰れないように
	_frame.queue_redraw()


## 骨の所（世界）。骨がなければ INF
func _bone(name: String) -> Vector3:
	var doll = player.doll
	var i: int = doll._id(name)
	if i < 0:
		return Vector3.INF
	return doll.skel.global_transform * doll.skel.get_bone_global_pose(i).origin


## 人形の上の端と下の端の高さ（世界）。笠のてっぺん・上げた手と、足もと（座っていればソリの上の足）
func _extent() -> Vector2:
	var doll = player.doll
	var h: float = doll.height()
	var head := _bone("head")
	var top: float = (head.y + 0.3 * h) if head != Vector3.INF else doll.global_position.y + h
	var bottom: float = doll.global_position.y
	for n in ["hand.L", "hand.R"]:
		var p := _bone(n)
		if p != Vector3.INF:
			top = maxf(top, p.y + 0.12)
			bottom = minf(bottom, p.y - 0.08)
	for n in ["foot.L", "foot.R"]:
		var p := _bone(n)
		if p != Vector3.INF:
			bottom = minf(bottom, p.y - 0.06)
	return Vector2(top, bottom)


func _place(dt: float) -> void:
	var doll = player.doll
	# 見る所: 全身の上下の真ん中。しゃがむ・座る・手を上げると、それに合わせて上下と距離が変わる
	var ext := _extent()
	var want := Vector3(doll.global_position.x, (ext.x + ext.y) / 2.0, doll.global_position.z)
	if _aim == Vector3.INF or _aim.distance_to(want) > 3.0:
		_aim = want
	else:
		# 位置は体と一緒に動かし（速く滑っても外れない）、姿勢の段だけを均す
		var body_move: Vector3 = doll.global_position - _last_body
		_aim += body_move
		_aim = _aim.lerp(want, 1.0 - exp(-dt * AIM_K))
	_last_body = doll.global_position
	# 全身が窓に MARGIN_K 倍の余白で収まる距離。広げるときは早く、寄るときはゆっくり
	var fit := (ext.x - ext.y) * MARGIN_K / 2.0 / tan(deg_to_rad(FOV) / 2.0)
	_fit = lerpf(_fit, fit, 1.0 - exp(-dt * (6.0 if fit > _fit else 1.5)))
	# 向きは人形の傾きごと追う（坂を滑るとき、人形はソリと一緒に前へ傾く）
	var q: Quaternion = doll.global_basis.orthonormalized().get_rotation_quaternion()
	if _yaw == INF:
		_yaw = 0.0
		_rot = q
	_rot = _rot.slerp(q, 1.0 - exp(-dt * TURN))
	var working: bool = player.mode == player.Mode.GRIP or player.mode == player.Mode.ROPE
	_low = lerpf(_low, BELOW_WORK if working else 0.0, 1.0 - exp(-dt * 2.0))
	var at := _aim + _offset()
	cam.global_transform = Transform3D(Basis(), at).looking_at(_aim, Basis(_rot).y)


## 見る所からカメラへ（全身が収まる距離、正面）
func _offset() -> Vector3:
	var b := Basis(_rot)
	return b * Vector3(0, 0, -_fit) + b.y * (ABOVE - _low)


var _last_body := Vector3.ZERO


## 持っている物（型紙・布・畳んだソリ）を人形の右手にも持たせる
func _sync_held() -> void:
	var doll = player.doll
	var it: Dictionary = player.held()
	var key := "" if it.is_empty() else "%s/%s/%s/%s" % [it.get("kind", ""), it.get("fabric", ""), it.get("tag", ""), it.get("sled", "")]
	if key != _held_key:
		_held_key = key
		if _held:
			_held.queue_free()
			_held = null
		if key != "":
			var att := BoneAttachment3D.new()
			att.bone_name = "hand.R"
			doll.skel.add_child(att)
			var shape := Player.held_shape(it)
			shape.scale = Vector3.ONE / doll._scale
			shape.position = Vector3(0, 0.06, -0.03) / doll._scale
			for mi in shape.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).layers = doll.layers
			att.add_child(shape)
			_held = att
	if _held:
		_held.visible = not doll.holding_ball and not doll._ball.visible
		if it.get("kind") == "folded" and _held.get_child_count() > 0:
			# 畳んだソリの包みは、名札を貼った面を人形の前へ向ける（小窓・ほかの人から見える）
			var f: Vector3 = -player.global_basis.z
			f.y = 0
			f = f.normalized()
			var b := Basis(f.cross(Vector3.DOWN), f, Vector3.DOWN).rotated(f.cross(Vector3.UP).normalized(), -0.3)
			var shape: Node3D = _held.get_child(0)
			shape.global_transform = Transform3D(b.scaled(Vector3.ONE * 2.0), _held.global_position + f * 0.1 + Vector3.UP * 0.05)


## 刺繍枠の丸窓
class Frame extends Control:
	var sc: Node
	var view: TextureRect

	func _draw() -> void:
		var u: float = sc.ui()
		var c := size / 2.0
		var r := size.x / 2.0
		Icons.screen()
		if sc.plain_frame:
			Icons.dashes(self, Icons.circ(c, r - 7.0 * u, 72), Icons.RED, 1.8 * u, 6.0 * u, 4.0 * u, 0.95, true)
			return
		# 落ち影（輪の外側だけ。窓の絵の上には重ねない）
		draw_arc(c + Vector2(1.5, 3.0) * u, r + 5.5 * u, 0.0, TAU, 64, Color(Icons.SHADOW, 0.22), 11.0 * u, true)
		# 外の輪（木）: 濃い縁、木の面、明るい筋
		draw_arc(c, r + 5.0 * u, 0.0, TAU, 64, Icons.WOOD.darkened(0.35), 11.0 * u, true)
		draw_arc(c, r + 5.0 * u, 0.0, TAU, 64, Icons.WOOD, 8.5 * u, true)
		draw_arc(c, r + 3.0 * u, PI * 1.1, PI * 1.75, 24, Color(Icons.WOOD.lightened(0.35), 0.7), 1.6 * u, true)
		draw_arc(c, r + 7.0 * u, PI * 0.15, PI * 0.6, 24, Color(Icons.WOOD.darkened(0.2), 0.6), 1.2 * u, true)
		# 内の輪（細い）
		draw_arc(c, r - 0.5 * u, 0.0, TAU, 64, Icons.WOOD.lightened(0.15), 2.6 * u, true)
		# 赤い糸のランニングステッチ（あなたの色）
		Icons.dashes(self, Icons.circ(c, r - 7.0 * u, 72), Icons.RED, 1.8 * u, 6.0 * u, 4.0 * u, 0.95, true)
		# 枠のねじ（上）: 輪の切れ目の 2 枚の耳と、真鍮のねじ
		var top := c + Vector2(0, -(r + 5.0 * u))
		for s in [-1.0, 1.0]:
			var ear := Rect2(top + Vector2(s * 6.5 * u - 4.0 * u, -12.0 * u), Vector2(8.0, 14.0) * u)
			draw_rect(ear.grow(1.0 * u), Icons.WOOD.darkened(0.35))
			draw_rect(ear, Icons.WOOD)
		var brass := Color(0.82, 0.66, 0.30)
		draw_line(top + Vector2(-14.0, -6.0) * u, top + Vector2(14.0, -6.0) * u, brass.darkened(0.3), 3.2 * u, true)
		draw_circle(top + Vector2(17.0, -6.0) * u, 4.6 * u, brass.darkened(0.3), true, -1.0, true)
		draw_circle(top + Vector2(17.0, -6.0) * u, 3.6 * u, brass, true, -1.0, true)
		draw_line(top + Vector2(17.0, -8.6) * u, top + Vector2(17.0, -3.4) * u, brass.darkened(0.45), 1.0 * u, true)
