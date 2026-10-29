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

var main: Node3D
var player: CharacterBody3D
var cam: Camera3D
var vp: SubViewport
var hidden := false

var _frame: Control
var _mat: ShaderMaterial
var _yaw := INF               # INF のあいだは、まだ向きを決めていない
var _rot := Quaternion.IDENTITY   # 均した人形の向き
var _aim := Vector3.INF
var _fit := DIST              # 全身が収まる距離 (m)
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


## 小窓のカメラだけの環境: 背景は麻布の色。その色のままの所は縫わずに布の地として見せる（刺繍枠に、自分だけが縫ってある絵になる）。
## 空・SSAO・照り返し・にじみも描かないので軽い
func _fabric_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = LINEN
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.95, 0.93, 0.90)   # 逆光でも顔と着物の色が読めるよう、環境光を強めに
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES   # 本体の画面と同じ色の出方に
	e.tonemap_exposure = 0.85
	e.tonemap_white = 6.0
	return e


## 足もとの丸い影。地面を描かないので、浮いて見えないように置く（小窓だけの層）。刺繍では濃い糸の楕円に縫われる
func _make_shadow() -> void:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
// 半透明はこの小窓で描かれないので、不透明にして縁を背景の布の色へ混ぜる（背景は無地なので透けて見える）
uniform vec3 bg : source_color;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = 0.7 * (1.0 - smoothstep(0.45, 1.0, r));
	if (a < 0.03) discard;
	ALBEDO = mix(bg, vec3(0.12, 0.13, 0.25), a);
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
uniform vec3 linen = vec3(0.95, 0.92, 0.85);
const vec2 SHEEN_DIR = vec2(-0.55, -0.83);   // 左上からの光（艶の向き）

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash1(float x) { return fract(sin(x * 91.3458) * 47453.5453); }

vec3 soft(sampler2D t, vec2 uv, float e) {   // 毛羽のむらを均して読む
	return (texture(t, uv) * 2.0 + texture(t, uv + vec2(e, 0.0)) + texture(t, uv - vec2(e, 0.0))
		+ texture(t, uv + vec2(0.0, e)) + texture(t, uv - vec2(0.0, e))).rgb / 6.0;
}

vec3 thread_color(vec3 c) {
	c = pow(c, vec3(0.8)) * 1.12;                                 // 明るく持ち上げ
	c = clamp(mix(vec3(dot(c, vec3(0.3, 0.55, 0.15))), c, 1.45), 0.0, 1.0);   // 刺繍糸らしく鮮やかに
	return floor(c * 6.0 + 0.5) / 6.0;
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
	vec3 col = linen * (0.97 + 0.03 * sin(p.x * 2.6) * sin(p.y * 2.6));   // 麻布の織り目
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
		float body = mix(0.74, 1.04, bulge) * mix(0.85, 1.0, dip);
		// 艶: 糸が光の向きに沿うほど、糸の背が明るく光る
		float sheen = pow(abs(dot(dir, SHEEN_DIR)), 3.0) * pow(bulge, 5.0) * dip;
		vec3 th = q * body + vec3(1.0, 0.98, 0.94) * sheen * 0.38;
		// 色の境の縁取り（濃い糸）
		vec3 qx = thread_color(soft(TEXTURE, UV + vec2(1.6 * e, 0.0), e));
		vec3 qy = thread_color(soft(TEXTURE, UV + vec2(0.0, 1.6 * e), e));
		float edge = step(0.25, length(qx - q) + length(qy - q));
		th = mix(th, q * 0.5 * mix(0.8, 1.1, bulge), edge * 0.5);
		col = th;
	}
	col = mix(col, linen, smoothstep(0.9, 1.0, r) * 0.25);
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
	var dc := get_node_or_null("/root/DayCycle")
	if dc and "dial_right" in dc:
		dc.dial_right = 16.0 + width()
	if hidden or player == null:
		return
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


## 刺繍枠の丸窓
class Frame extends Control:
	var sc: Node
	var view: TextureRect

	func _draw() -> void:
		var u: float = sc.ui()
		var c := size / 2.0
		var r := size.x / 2.0
		Icons.screen()
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
