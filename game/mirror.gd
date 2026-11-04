extends Node3D
## ロッジの入口の横の大きな鏡（2026-11-04 代表「染色台の左、ロッジ入口の内側のすぐ横の壁に天井までの高さの大きな鏡を置いてほしい。
## 染色やカスタムした自キャラをまじまじと大きく見たい」「アクセサリとミニオンも含めた自キャラね」）。案の絵と形の台本は design/lodge-mirror/。
## 枠は右下の小窓と同じ刺繍枠を縦長にしたもの（glb）。面は銀糸を織り込んだ布（ラメ）で、ふだんは布として光を受ける。
## 前で鏡の方を向いて F を押すと、布の上に自分の人形が鏡いっぱいに映る。もう一度 F か、離れると消える。
##
## 映すのは自分だけ: 自分の体の層（層 2: 人形・頭と肩の小物・手に持った物・手形・息）と、鏡だけの層（LAYER: 自分のミニオン）。
## ほかの人・ロッジ・地面は映らない。絵はこの画面だけの物で、ほかの人の画面の鏡には出ない（通信では何も送らない）。
## 映っていないときは描かない（SubViewport は初めて映すときに作り、消しているあいだは止める）。
##
## カメラは、人形から鏡の真ん中へ向かう向きの先に置く: 鏡の方を向けばいつも前から映り、見回すと人形の向きのとおりに斜めからの姿も見える。
## 絵は左右を反転する（右手を上げると、鏡の同じ側の手が上がる）。距離の出し方は小窓（self_cam.gd の extent）と同じに、小物とミニオンの分と横幅を足す。

const Props := preload("res://props.gd")
const SelfCam := preload("res://self_cam.gd")

const GLB := "res://props/lodge_mirror/lodge_mirror.glb"
const LAYER := 1 << 10        # 鏡だけに映す層（層 11）。本体の画面・右上の 360° の映像・小窓には映らない
const WIDTH := 3.10           # 枠の外の幅 (m)。design/lodge-mirror/ideas.py の W
const HEIGHT := 5.25          # 枠の外の高さ (m)。床から天井まで
const DEPTH := 0.26           # 枠の壁からの厚み (m)
const SURFACE := Vector2(2.56, 4.55)   # 鏡の面の幅と高さ (m)。ideas.py の SURFACE["A"]
const SURFACE_Y := 2.45       # 鏡の面の真ん中の高さ (m)
const CORNER := 0.42          # 鏡の面の角の丸み (m)
const SURFACE_Z := 0.075      # 鏡の面の壁からの距離 (m)。内の輪の下に入る
const PX_H := 1400            # 絵の高さ (px)。小窓（224 px）の 6 倍あまり
const EVERY := 2              # 何コマに 1 回描くか（姿勢は 12 コマ／秒なので、毎コマ描いても増えない）
const REACH := 6.0            # この距離の内で鏡の方を向いていれば、F で映せる (m)
const AWAY := 7.5             # これより離れると消える (m)
const FOV := 30.0
const MARGIN_K := 1.1         # 全身の高さに対する絵の高さ（上下の余白）
const MARGIN_W := 1.06        # 全身の幅に対する絵の幅
const ABOVE := -0.1           # 見る所からの高さ (m)。少し下から見上げ、笠の下の顔が見える
const AIM_K := 8.0            # 見る所の追いつき（1/s）。12 コマの姿勢の段を均す
const PET_FRONT := 0.4        # ミニオンの座る所: 人形から鏡の側へ (m)。絵では人形の裾の前に少し重なり、横幅を取りすぎない
const SHOW_FRAMES := 4        # 映る・消えるのにかかるコマ（人形の 12 コマ／秒で刻む）
const EXPOSURE := 0.5         # 絵は 1 までしか持てないので、明るさを落として描き、面で戻す（白く飛ばさない）

var player: CharacterBody3D   # main.gd が入れる
var main: Node3D
var shown := false

var _surface: MeshInstance3D
var _mat: ShaderMaterial
var _vp: SubViewport
var _cam: Camera3D
var _key: DirectionalLight3D  # 鏡の側から人形の顔を照らす灯り（鏡のカメラにだけ効く）
var _aim := Vector3.INF
var _fit := 3.0
var _side := 0.0              # 絵の真ん中の左右のずれ (m)。人形とミニオンの両方が入るように
var _to := Vector3.BACK       # 人形から鏡へ（水平）
var _last_body := Vector3.ZERO
var _reveal := 0.0
var _reveal_frame := -1
var _tick := 0
var _draw_tick := 0


func _ready() -> void:
	var body := Props.make(GLB)
	body.rotation.y = PI   # glb の正面（Blender の +Y＝Godot の -Z）を、この節の正面 +Z へ
	add_child(body)
	# 当たり（枠の厚み）。人の太さで、入口と人台の桶の前を通れる
	var solid := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, DEPTH)
	col.shape = box
	col.position = Vector3(0, HEIGHT / 2.0, DEPTH / 2.0)
	solid.add_child(col)
	add_child(solid)
	_surface = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SURFACE
	_surface.mesh = quad
	_surface.position = Vector3(0, SURFACE_Y, SURFACE_Z)
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = SURFACE_SHADER
	_mat.set_shader_parameter("size", SURFACE)
	_mat.set_shader_parameter("corner", CORNER)
	_mat.set_shader_parameter("gain", 1.0 / EXPOSURE)
	_surface.material_override = _mat
	add_child(_surface)
	set_physics_process(false)


## 鏡の前にいて、鏡の面の方を向いているか（カメラの見ている先が面に当たる）
func can_use(p: Node3D) -> bool:
	var at := to_local(p.global_position)
	if at.z < 0.0 or absf(at.y) > 1.5 or Vector2(at.x, at.z).length() > REACH:
		return false
	var cam: Camera3D = p.cam
	var from := to_local(cam.global_position)
	var dir := global_basis.inverse() * -cam.global_basis.z
	if dir.z >= -0.01:
		return false
	var hit := from + dir * ((SURFACE_Z - from.z) / dir.z)
	return absf(hit.x) < SURFACE.x / 2.0 and absf(hit.y - SURFACE_Y) < SURFACE.y / 2.0


## 案内の絵を出す所: 面の真ん中あたり、あなたの目より少し上
func hint_at() -> Vector3:
	return to_global(Vector3(0, 2.6, SURFACE_Z + 0.2))


func set_shown(on: bool) -> void:
	if on == shown:
		return
	shown = on
	if on:
		_build()
		_share_lights()
		_sync_env()
		_aim = Vector3.INF
		_to = _toward(player.doll.global_position)
		_fit_now()
		_place(1.0)
		_key.visible = true
	_call_pet(on)
	set_physics_process(true)   # 消えるコマのあいだも動かす。消えきったら止める（_physics_process）


## 映っているあいだだけ使う物を、初めて映すときに作る
func _build() -> void:
	if _vp:
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(roundi(PX_H * SURFACE.x / SURFACE.y), PX_H)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.transparent_bg = true
	_vp.positional_shadow_atlas_size = 0   # ロッジの灯りの影は描かない
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.near = 0.05
	_cam.far = 30.0
	_cam.cull_mask = (1 << 1) | LAYER   # あなたの体と、鏡だけの物
	_cam.environment = _make_env()
	_vp.add_child(_cam)
	_cam.current = true
	_key = DirectionalLight3D.new()
	_key.layers = LAYER           # 鏡のカメラの層にだけ置く（本体の画面の人形には当たらない）
	_key.light_color = Color(1.0, 0.93, 0.84)
	_key.light_energy = 0.75
	_key.shadow_enabled = false
	_key.top_level = true
	add_child(_key)
	_mat.set_shader_parameter("view", _vp.get_texture())


## 鏡のカメラだけの環境: トーンマップは本体の画面で一度だけかかるよう直線にし、環境光は色で決める。空も照り返しも描かないので軽い
func _make_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.92, 0.84)
	e.ambient_light_energy = 0.7
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = EXPOSURE
	return e


## 本体の環境光の強さを写す（ロッジの中は外の時刻で少し明るさが変わる）
func _sync_env() -> void:
	if main and main.get("env"):
		_cam.environment.ambient_light_energy = clampf(main.env.ambient_light_energy, 0.45, 0.9)


## 灯りも描く層に属し、カメラは自分の映す層の灯りしか当てない。ロッジの灯りと提灯を鏡の層にも足す。
## 太陽と月は足さない（鏡のカメラは屋根を描かないので、屋根の影が落ちず、中の人形に日が直接当たってしまう）
func _share_lights() -> void:
	for l in (main if main else get_parent()).find_children("*", "Light3D", true, false):
		if not l is DirectionalLight3D:
			(l as Light3D).layers |= LAYER


func _physics_process(dt: float) -> void:
	# 映る・消えるは 12 コマで刻む
	var f: int = player.doll.frame_index() if player and player.doll else _reveal_frame + 1
	if f != _reveal_frame:
		_reveal_frame = f
		_reveal = move_toward(_reveal, 1.0 if shown else 0.0, 1.0 / SHOW_FRAMES)
		_mat.set_shader_parameter("reveal", _reveal)
	if not shown:
		if _reveal <= 0.0:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_key.visible = false
			set_physics_process(false)
		return
	if player == null or not is_instance_valid(player) or player.doll == null or player.doll.skel == null:
		set_shown(false)
		return
	var at := to_local(player.global_position)
	if at.z < 0.0 or absf(at.y) > 2.0 or Vector2(at.x, at.z).length() > AWAY:
		set_shown(false)   # 離れた・入口から外へ出た
		return
	_tick += 1
	if _tick % 30 == 0:
		_sync_env()
	_place(dt)


## 描くのは _process のコマで（物理のコマは画面のコマと合わないことがあるので）
func _process(_dt: float) -> void:
	if _vp == null or not shown:
		return
	_draw_tick += 1
	if _draw_tick % EVERY == 0:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## 人形から鏡の真ん中へ（水平）
func _toward(from: Vector3) -> Vector3:
	var d := to_global(Vector3(0, 0, SURFACE_Z)) - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else global_basis.z * -1.0


## ミニオンの座る所（世界）: 人形の少し鏡寄りの、絵で人形の横に見える所。鏡の方に顔を向けて座る（companions.gd が読む）
func pet_spot(doll: Node3D) -> Vector3:
	var right := _to.cross(Vector3.UP).normalized()
	return doll.global_position + _to * PET_FRONT + right * _pet_side(doll)


func _pet_side(doll: Node3D) -> float:
	return clampf(doll.height() * 0.26, 0.26, 0.6)


## ミニオンが見る所（世界）: 鏡の面の、ミニオンの目の高さのあたり（首を上げすぎない）
func look_point() -> Vector3:
	return to_global(Vector3(0, 0.45, SURFACE_Z))


func _companions() -> Node:
	if player == null or not is_instance_valid(player):
		return null
	return (main if main else get_parent()).get_node_or_null("Pals%d" % int(player.get("id")))


func _call_pet(on: bool) -> void:
	var c := _companions()
	if c:
		c.mirror = self if on else null


## 映す物の上下と左右。[上の端（世界の高さ）, 下の端, 左右の真ん中のずれ（鏡から見た右が正, m）, 幅の半分（m）]
func _bounds() -> Array:
	var doll = player.doll
	var ext := SelfCam.extent(doll)
	var top := ext.x
	var bottom := ext.y
	var right := _to.cross(Vector3.UP).normalized()
	var o: Vector3 = doll.global_position
	var pad: float = doll.body_half_width() * 1.1   # 体の広がり（骨は体の芯にある）
	var lo := -pad
	var hi := pad
	var arm: float = 0.08 + 0.1 * doll.height()   # 腕の骨から、袖・手形の外まで
	for n in ["hand.L", "hand.R", "forearm.L", "forearm.R"]:
		var i: int = doll._id(n)
		if i >= 0:
			var p: Vector3 = doll.skel.global_transform * doll.skel.get_bone_global_pose(i).origin
			var x := (p - o).dot(right)
			lo = minf(lo, x - arm)
			hi = maxf(hi, x + arm)
	var c := _companions()
	if c:
		var box: AABB = c.worn_box()
		if box.has_volume():   # 頭・肩の小物
			top = maxf(top, box.end.y + 0.03)
			for k in 8:
				var x := (box.get_endpoint(k) - o).dot(right)
				lo = minf(lo, x)
				hi = maxf(hi, x)
		var pr: float = c.pet_radius()
		if pr > 0.0:   # ミニオンは座る所で見込む（駆けてくるあいだも、絵の大きさは変えない）
			# 人形より手前にいるので、絵では大きく、足もとは下に見える
			var near := _fit / maxf(_fit - PET_FRONT - pr, 1.0)
			hi = maxf(hi, (_pet_side(doll) + pr) * near)
			bottom -= (top - bottom) * 0.5 * (near - 1.0)
	return [top, bottom, (lo + hi) / 2.0, (hi - lo) / 2.0]


func _fit_for(b: Array) -> float:
	var t := tan(deg_to_rad(FOV) / 2.0)
	var fh: float = (float(b[0]) - float(b[1])) * MARGIN_K / 2.0 / t
	var fw: float = float(b[3]) * MARGIN_W / (t * SURFACE.x / SURFACE.y)
	return maxf(fh, fw)


func _fit_now() -> void:
	var b := _bounds()
	_fit = _fit_for(b)
	_side = float(b[2])


## カメラを置く。位置は体と一緒に動かし（遅れない）、姿勢の段だけを均す
func _place(dt: float) -> void:
	var doll = player.doll
	var o: Vector3 = doll.global_position
	_to = _to.slerp(_toward(o), 1.0 - exp(-dt * 6.0)).normalized()
	var b := _bounds()
	var right := _to.cross(Vector3.UP).normalized()
	_side = lerpf(_side, float(b[2]), 1.0 - exp(-dt * 4.0))
	var want := Vector3(o.x, (float(b[0]) + float(b[1])) / 2.0, o.z) + right * _side
	if _aim == Vector3.INF or _aim.distance_to(want) > 3.0:
		_aim = want
	else:
		_aim += o - _last_body
		_aim = _aim.lerp(want, 1.0 - exp(-dt * AIM_K))
	_last_body = o
	var fit := _fit_for(b)
	_fit = lerpf(_fit, fit, 1.0 - exp(-dt * (6.0 if fit > _fit else 1.5)))
	var at := _aim + _to * _fit + Vector3.UP * ABOVE
	_cam.global_transform = Transform3D(Basis(), at).looking_at(_aim, Vector3.UP)
	# 灯りは鏡の側の少し上から、左へ少しずらして（のっぺりしないように）
	var from := at + Vector3.UP * 2.2 + right * -1.2
	_key.global_transform = Transform3D(Basis(), from).looking_at(_aim, Vector3.UP)
	_place_shadows(right)


## 足もとの丸い影（床を描かないので、浮いて見えないように。布の上に薄く落とす）。人形とミニオンの足もとを絵の上の所に直して面へ渡す
func _place_shadows(right: Vector3) -> void:
	var doll = player.doll
	_mat.set_shader_parameter("shadow_a", _shadow_of(doll.global_position, doll.height() * 0.42, right))
	var c := _companions()
	var pr: float = c.pet_radius() if c else 0.0
	var pet := Vector4.ZERO
	if pr > 0.0 and c.pet_at().distance_to(pet_spot(doll)) < 1.0:   # 駆けてくるあいだは出さない
		pet = _shadow_of(c.pet_at(), pr * 1.15, right)
	_mat.set_shader_parameter("shadow_b", pet)


## 足もと at の影を、絵の座標（u, v, 横の半径, 縦の半径）で
func _shadow_of(at: Vector3, r: float, right: Vector3) -> Vector4:
	var size := Vector2(_vp.size)
	var c := _cam.unproject_position(at) / size
	var e := (_cam.unproject_position(at + right * r) - _cam.unproject_position(at)) / size
	return Vector4(c.x, c.y, absf(e.x), absf(e.x) * 0.28 * size.x / size.y)


## 鏡の面: 銀糸を織り込んだ布（ラメ）。大きなゆるいしわと細かい織り目で光を受け、つるつるの CG に見えないように。
## 映っているときは、布の上に人形の絵を重ねる（絵は左右を反転。人形のない所は布のまま）
const SURFACE_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D view : source_color, filter_linear, repeat_disable;
uniform vec2 size = vec2(2.56, 4.55);
uniform float corner = 0.42;
uniform float reveal = 0.0;
uniform float gain = 2.0;
uniform vec4 shadow_a = vec4(0.0);   // 足もとの影: 絵の u, v, 横の半径, 縦の半径
uniform vec4 shadow_b = vec4(0.0);
const float PITCH = 0.016;        // 糸 1 本の幅 (m)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
// 張った布のゆるいしわの傾き: 縦に流れる長い波を、場所でずらして重ねる（なめらかで、はっきりした境が出ない）
vec2 folds(vec2 m) {
	float wx = m.x + 0.35 * sin(m.y * 0.9 + 1.0) + 0.12 * sin(m.y * 2.3);
	vec2 g = vec2(0.0);
	g.x += 0.55 * cos(wx * 2.7 + 0.6) * (0.7 + 0.3 * sin(m.y * 0.7));
	g.x += 0.35 * cos(wx * 6.1 + 2.0) * (0.6 + 0.4 * sin(m.y * 1.3 + 2.0));
	g.x += 0.16 * cos(wx * 13.0 + 4.0 + sin(m.y * 1.7));
	g.y += 0.10 * sin(m.y * 1.9 + wx * 1.4);
	return g;
}

void fragment() {
	vec2 m = (UV - 0.5) * size;
	vec2 q = abs(m) - (size * 0.5 - corner);
	if (length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner > 0.0) {
		discard;
	}
	// 織り目: 縦糸と横糸が交互に浮く。細かすぎる距離では、糸の筋だけを薄くする
	vec2 w = m / PITCH;
	vec2 cell = floor(w);
	vec2 f = fract(w) - 0.5;
	bool warp = mod(cell.x + cell.y, 2.0) < 1.0;
	float near = 1.0 - smoothstep(0.35, 1.1, length(fwidth(w)));
	vec2 slope = (warp ? vec2(f.x, 0.0) : vec2(0.0, f.y)) * 0.7 * near;
	float bulge = warp ? cos(f.x * 3.14159) : cos(f.y * 3.14159);   // 糸の丸み
	// しわ
	vec2 grad = folds(m);
	vec3 n = normalize(vec3(-grad.x * 0.2 + slope.x, grad.y * 0.2 - slope.y, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	// 銀糸: 糸ごとに少しむらがあり、見る向きが変わると、ところどころがきらっと光る（ラメ）
	float thread = hash(warp ? vec2(cell.x, 3.0) : vec2(9.0, cell.y));
	float slub = hash(vec2(floor(m.x / 0.032), 7.0));                        // 縦糸の太さのむらの、長い筋（遠くでも見える）
	vec3 silver = vec3(0.76, 0.73, 0.68) * mix(1.0, mix(0.82, 1.06, thread) * mix(0.8, 1.0, bulge), near) * (0.95 + 0.07 * slub);
	vec3 cloth = silver * (0.92 + 0.2 * grad.x);
	vec2 sc = floor(m / 0.011);
	float tw = step(0.992, hash(sc + floor(VIEW.xy * 18.0) * 3.0));
	// 足もとの影
	vec2 pu = vec2(1.0 - UV.x, UV.y);
	float sh = 0.0;
	if (shadow_a.z > 0.0) {
		sh = 1.0 - smoothstep(0.35, 1.0, length((pu - shadow_a.xy) / shadow_a.zw));
	}
	if (shadow_b.z > 0.0) {
		sh = max(sh, 1.0 - smoothstep(0.35, 1.0, length((pu - shadow_b.xy) / shadow_b.zw)));
	}
	cloth *= 1.0 - 0.55 * sh * reveal;
	float a = 0.0;
	vec3 img = vec3(0.0);
	if (reveal > 0.0) {
		vec4 t = texture(view, vec2(1.0 - UV.x, UV.y));
		a = clamp(t.a, 0.0, 1.0) * reveal;
		img = t.rgb * reveal * gain;
	}
	ALBEDO = cloth * (1.0 - a);
	METALLIC = 0.0;
	ROUGHNESS = 0.6;
	SPECULAR = 0.45 * (1.0 - a);
	EMISSION = img + cloth * tw * 0.22 * (1.0 - a);
}
"""
