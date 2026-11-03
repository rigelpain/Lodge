@tool
extends Node3D
## ロッジ（lodge/ の Blender の台本で作った glb）。エディタで開いても手芸の素材と灯りで見えるよう @tool にする。
## 素材は glb の役割の名前（log, roof, snow …）で look.gd の素材に差し替え、灯りの目印（light_*）に暖色の灯りを灯す。
## 当たり判定は lodge_collision.glb（名前の -colonly で、見た目なしの当たり判定になる）。

const Look := preload("res://look.gd")

var fire_light: OmniLight3D
var _t := 0.0
var _auto_doors: Array[Node3D] = []   # 風除室の内の自動ドア（左右へ引き分ける）
var _auto_home: Array[float] = []
var _auto_sign: Array[float] = []
var _auto_area: Area3D
var _auto_open := 0.0
const AUTO_SLIDE := 1.40               # 引き分ける幅 (m)。開くと丸太の壁の中へ隠れる
## 開き戸（勝手口・西の戸・テラスへの戸）。戸ごとに {leaves: [{pivot, sign}], center, normal, area, side, a}（_make_swing_doors）
var _swing: Array = []
const SWING_OPEN := deg_to_rad(95.0)   # 開ききった角
const SWING_REACH := 2.4               # 戸の前後どこまで近づいたら開くか (m)


func _ready() -> void:
	var lamp := Look.paper(Color(0.96, 0.84, 0.63))
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.74, 0.44)
	lamp.emission_energy_multiplier = 1.6
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1.0, 0.54, 0.23)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.5, 0.18)
	fire.emission_energy_multiplier = 4.0
	var mats := {
		"log": _log_wood(),                                  # 丸太: 胴は木目と樹皮のむら、木口は年輪（2026-10-31 代表「丸太の段々を見たい」）
		"chink": _chink(),                                   # 丸太の継ぎ目に詰めた綿
		"roof": Look.felt(Color(0.16, 0.20, 0.41), 1.2),    # 藍のフェルト
		"snow": Look.snow(),
		"stone": Look.felt(Color(0.50, 0.46, 0.42), 2.0),   # フェルトの小石
		# 木はこげ茶（2026-10-31 代表「僕の記憶のロッジはもっともっとこげ茶色だった」）
		"post": Look.wood(Color(0.24, 0.14, 0.08)),
		"door": Look.wood(Color(0.27, 0.17, 0.10)),
		"board": _planks(Color(0.50, 0.35, 0.22)),          # 2 階の天井の羽目板、卓・棚
		"ceiling": _planks(Color(0.50, 0.35, 0.22)),        # 1 階の天井の羽目板
		"floor": _planks(Color(0.38, 0.26, 0.16)),          # 1 階の床も、幅の広い荒い板
		# 外の木の床と段板: 中の床と同じ荒い板（2026-11-02 代表「デッキやテラス、外階段もちゃんと木でできたものに」。
		# 雪は載せない。「吹雪とか天気実装したときは雪あってもいいけど今のところ雪なくていい」）
		"deck": _planks(DECK_BROWN),
		"tread": _planks(DECK_BROWN, true),
		"rail": Look.wood(Color(0.36, 0.24, 0.14)),
		"frame": Look.paper(Color(0.93, 0.88, 0.79)),
		"tatami": Look.paper(Color(0.85, 0.82, 0.66)),
		"cushion": Look.felt(Color(0.79, 0.54, 0.40)),
		"quilt": Look.felt(Color(0.62, 0.37, 0.32)),
		"felt_red": Look.felt(Color(0.71, 0.35, 0.29)),
		"felt_blue": Look.felt(Color(0.30, 0.44, 0.66)),
		"felt_green": Look.felt(Color(0.49, 0.60, 0.36)),
		"felt_yellow": Look.felt(Color(0.84, 0.64, 0.29)),
		"paper": lamp,
		"fire": fire,
		"metal": _metal(),
		"dark": Look.felt(Color(0.17, 0.16, 0.16), 2.0),   # 雪落としのマット、自販機の口
		# 出入り口のマット（2026-11-03 代表「出入り口の内外にマット敷きましょう」）: 外は雪を落とす目の粗い棕櫚と濃い縁の布、
		# 中は布を裂いて織った柔らかい裂き織りと、生成りの房
		"mat_out": _doormat(false),
		"mat_out_edge": Look.cloth(Color(0.20, 0.14, 0.10), 14.0),
		"mat_in": _doormat(true),
		"mat_fringe": Look.cloth(Color(0.80, 0.74, 0.62), 30.0),
		"glass": _glass(),                                   # 窓・ガラスの壁・戸のガラス（glb の濃い藍で 32% は暗く、外が見えにくかった）
	}
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and mats.has(src.resource_name):
				mi.set_surface_override_material(i, mats[src.resource_name])

	for e in find_children("light_*", "", true, false):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.68, 0.40)   # 電球色より少し赤み
		l.light_energy = 1.1
		l.omni_range = 6.5
		if e.name.begins_with("light_lamp"):      # 食堂の天井: 3 つで広く照らす
			l.omni_range = 11.0
			l.light_energy = 1.6
		elif e.name.begins_with("light_lantern"):  # 座敷: 2 つ
			l.omni_range = 9.0
			l.light_energy = 1.4
		if e.name == "light_fire":                 # 影は付けない（スマホでも軽く）
			l.light_color = Color(1.0, 0.45, 0.16)
			l.omni_range = 11.0                    # 大きな暖炉（hearth_nook.gd）: まわりの居場所の端の席まで
			l.light_energy = 2.0
			l.omni_attenuation = 0.6               # 夜、遠いソファまで火の色が届くように（lodge_lights.gd と同じ考え）
			l.position = Vector3(0, 0.8, 2.6)   # 炉の石の面から部屋の側へ離す（近いと小石が白く飛ぶ）
			fire_light = l
		e.add_child(l)

	add_child(preload("res://lodge_lights.gd").new())   # 暗い所に、火の灯りの道具（松明・ガス灯・キャンドル）
	_make_auto_door()
	_make_swing_doors()


const DOOR_BROWN := Color(0.27, 0.17, 0.10)   # 外扉の茶（こげ茶）
const DECK_BROWN := Color(0.42, 0.29, 0.18)   # 外の木の床の茶（中の床 0.38, 0.26, 0.16 より雨風で少し明るい）
# 丸太の地の色。外扉と同じ値にすると、日なたで明るく赤く（橙に）出るので、日なたで扉の茶に見えるよう暗く、赤みを抑える
const LOG_BROWN := Color(0.15, 0.10, 0.07)   # こげ茶


## 丸太の継ぎ目の綿: 生成りの綿の毛羽。縁がふわっと明るい
static func _chink() -> StandardMaterial3D:
	var m := Look.felt(Color(0.52, 0.46, 0.38), 6.0)   # くぼみの陰にあるので、生成りより暗め（明るいと白い縞に見える）
	m.rim = 0.15
	m.rim_tint = 0.3
	return m


const LOG_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 bark : source_color = vec3(0.27, 0.21, 0.16);
uniform vec3 wood : source_color = vec3(0.24, 0.16, 0.10);   // 剥いた木肌。明るく赤いと、日なたで橙のれんがに見える
uniform vec3 core : source_color = vec3(0.50, 0.35, 0.21);
varying vec3 m_pos;
varying vec3 m_nrm;

void vertex() {
	m_pos = VERTEX;
	m_nrm = NORMAL;
}

void fragment() {
	if (UV.x > 1.5) {
		// 木口: 年輪（まんなかから外へ、少し揺れる輪）、外側に樹皮の輪、放射状のひび
		vec2 d = (UV - vec2(2.5, 0.5)) * 4.0;
		float r = length(d);
		float wob = texture(noise, d * 0.35 + 0.5).r;
		float ring = 0.5 + 0.5 * sin((r + wob * 0.12) * 46.0);
		vec3 c = mix(core, wood, smoothstep(0.0, 0.9, r)) * (0.86 + 0.14 * ring);
		float crack = smoothstep(0.985, 1.0, abs(sin(atan(d.y, d.x) * 3.0 + wob * 2.0))) * step(0.15, r) * step(r, 0.8);
		c *= 1.0 - 0.35 * crack;
		c = mix(c, bark * 0.8, smoothstep(0.86, 0.96, r));
		ALBEDO = c;
		ROUGHNESS = 0.9;
	} else {
		// 胴: 丸太の向き（法線と直交する横の軸）に沿って流れる木目と、樹皮の残ったむら。下側は少し暗く
		vec3 n = normalize(m_nrm);
		float along = abs(n.x) < abs(n.z) ? m_pos.x : m_pos.z;
		float across = m_pos.y * 3.0 + (abs(n.x) < abs(n.z) ? m_pos.z : m_pos.x) * 1.3;
		float g = texture(noise, vec2(along * 0.05, across * 1.6)).r;
		float streak = texture(noise, vec2(along * 0.02 + 0.3, across * 0.4)).r;
		float patch = texture(noise, vec2(along * 0.12 + 0.7, across * 0.15 + 0.2)).r;
		vec3 c = mix(wood, bark, 0.35 + 0.5 * smoothstep(0.4, 0.65, patch));   // 樹皮が残った所と、剥いた木肌（差は控えめ）
		c *= 0.8 + 0.4 * g;                                          // 木目の筋
		c *= 0.88 + 0.16 * streak;
		c *= mix(0.72, 1.0, smoothstep(-0.7, 0.4, n.y));             // 下向きの面（継ぎ目のくぼみ）は暗く
		ALBEDO = c;
		ROUGHNESS = 0.92;
		NORMAL_MAP = normalize(vec3(0.5 + (g - 0.5) * 0.5, 0.5 + (streak - 0.5) * 0.3, 1.0)) * 0.5 + 0.5;
	}
	RIM = 0.15;
	RIM_TINT = 0.2;
}
"""

static var _log_mat: ShaderMaterial


## 丸太: 胴は剥いた木肌と残った樹皮のむら、丸太の向きに流れる木目。木口（build_lodge.py の cap_uv）は年輪とひび
static func _log_wood() -> ShaderMaterial:
	if _log_mat == null:
		var sh := Shader.new()
		sh.code = LOG_SHADER
		_log_mat = ShaderMaterial.new()
		_log_mat.shader = sh
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		fn.seed = 11
		nt.noise = fn
		nt.generate_mipmaps = true
		_log_mat.set_shader_parameter("noise", nt)
		_log_mat.set_shader_parameter("bark", Vector3(LOG_BROWN.r, LOG_BROWN.g, LOG_BROWN.b))
	return _log_mat


static var _plank_maps := {}   # 板の向き → [色の絵, 凹凸の絵]
const PLANK_SPAN := 2.4         # 板の絵がひと巡りする長さ (m)
const PLANK_BOARDS := 6         # その中の板の数（幅 40 cm。2026-10-31 代表「木の板が全部細い。もっと大きくして荒っぽく」）


## 床と天井の板: 幅 40 cm の手で切った荒い板。板ごとに濃さとわずかな色合いが違い、継ぎ目に溝、板ごとに高さが少し違う（段差）、
## 角は丸く落ち、長さの途中に突き合わせの継ぎ目、木目の筋と節。向きは物の座標で投影するので、UV の向きにかかわらず同じ大きさで出る。
## across なら板が東西に通る（外階段の段板・踊り場。上から見た板の向きが 90° 回る）
static func _planks(color: Color, across := false) -> StandardMaterial3D:
	var maps := _plank_images(across)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = maps[0]
	m.normal_enabled = true
	m.normal_texture = maps[1]
	m.normal_scale = 1.2
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / PLANK_SPAN   # PLANK_SPAN で一巡り
	return m


## 板の絵を焼く（向きごとに一度だけ）。across は縦横を入れ替える
static func _plank_images(across: bool) -> Array:
	if _plank_maps.has(across):
		return _plank_maps[across]
	var n := 384
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var bump := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var boards := PLANK_BOARDS
	var shade: Array[float] = []
	var warm: Array[float] = []
	var lift: Array[float] = []
	var joint: Array[float] = []
	var knots: Array = []
	for b in boards:
		shade.append(rng.randf_range(0.70, 1.12))
		warm.append(rng.randf_range(-0.05, 0.05))
		lift.append(rng.randf_range(0.55, 0.95))
		joint.append(rng.randf())
		var ks := []
		for k in rng.randi_range(0, 2):
			ks.append(Vector3(rng.randf_range(0.25, 0.75), rng.randf(), rng.randf_range(0.03, 0.06)))   # 板の中の x、長さの位置、大きさ
		knots.append(ks)
	var grain := FastNoiseLite.new()
	grain.frequency = 0.02
	grain.seed = 3
	var rough := FastNoiseLite.new()
	rough.frequency = 0.08
	rough.seed = 9
	for y in n:
		for x in n:
			var u := float(x) / n * boards
			var b := int(u) % boards
			var f := u - floorf(u)
			var v := float(y) / n
			var dj := absf(fposmod(v - joint[b], 1.0) - 0.5) * 2.0   # 突き合わせの継ぎ目からの近さ（1 で継ぎ目）
			var edge := minf(minf(f, 1.0 - f) / 0.06, (1.0 - dj) * 40.0)   # 板の縁までの近さ（0 で縁）
			var groove := edge < 0.25
			var g := grain.get_noise_2d(x * 0.18, y * 2.2 + b * 50.0) * 0.16 + rough.get_noise_2d(x, y + b * 31.0) * 0.04
			var kn := 0.0
			for k in knots[b]:
				var kv: Vector3 = k
				var dx := (f - kv.x) / kv.z * 0.4
				var dy := fposmod(v - kv.y + 0.5, 1.0) - 0.5
				var dd := sqrt(dx * dx + (dy / kv.z * 0.12) * (dy / kv.z * 0.12))
				if dd < 1.0:
					kn = maxf(kn, (1.0 - dd) * (0.55 + 0.45 * sin(dd * 14.0)))
			var round := clampf(edge, 0.0, 1.0)
			var val := 0.40 if groove else (shade[b] + g) * (0.82 + 0.18 * round) * (1.0 - 0.45 * kn)
			var c := Color(val * (1.0 + warm[b]), val, val * (1.0 - warm[b]))
			var hh := 0.0 if groove else lift[b] * (0.35 + 0.65 * sqrt(round)) + g * 0.6 - kn * 0.2
			var px := Vector2i(y, x) if across else Vector2i(x, y)
			img.set_pixelv(px, c)
			bump.set_pixelv(px, Color(hh, hh, hh))
	bump.bump_map_to_normal_map(9.0)
	img.generate_mipmaps()
	bump.generate_mipmaps()
	_plank_maps[across] = [ImageTexture.create_from_image(img), ImageTexture.create_from_image(bump)]
	return _plank_maps[across]


static var _doormat_maps := {}   # rag → [色の絵, 凹凸の絵]


## 出入り口のマット。rag でなければ棕櫚: 太い繊維の束を縦と横に交互に詰めた目の粗い網代（1 目 2 cm）、繊維の筋と毛羽、
## 束の境は深い溝。rag なら裂き織り: 裂いた布の横糸を 1 段ずつ打ち込み、布の色が数段ずつ替わる縞。たて糸の上下で横糸がうねる
static func _doormat(rag: bool) -> StandardMaterial3D:
	var maps := _doormat_images(rag)
	var m := StandardMaterial3D.new()
	m.albedo_texture = maps[0]
	m.normal_enabled = true
	m.normal_texture = maps[1]
	m.normal_scale = 1.6 if not rag else 1.0
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * (4.0 if not rag else 1.6)   # 棕櫚は 25 cm、裂き織りは 62 cm でひと巡り
	m.rim_enabled = true   # 毛羽が縁で光る（フェルトと同じ）
	m.rim = 0.35 if not rag else 0.45
	m.rim_tint = 0.6
	return m


static func _doormat_images(rag: bool) -> Array:
	if _doormat_maps.has(rag):
		return _doormat_maps[rag]
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var bump := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23 if rag else 17
	if not rag:
		var cell := 16
		var cells := n / cell
		var tone: Array[float] = []
		for i in cells * cells:
			tone.append(rng.randf_range(0.82, 1.12))
		var fib: Array[float] = []   # 繊維 1 本ずつの明るさ（束の中の筋）
		for i in n * 4:
			fib.append(rng.randf_range(0.70, 1.20))
		for y in n:
			for x in n:
				var cx := x / cell
				var cy := y / cell
				var across := (cx + cy) % 2 == 0   # 束の向きを 1 目ごとに替える
				var u := x % cell
				var v := y % cell
				var f: float = fib[(y + cx * 37) % (n * 4)] if across else fib[(x + cy * 53 + n) % (n * 4)]
				var t: float = tone[cy * cells + cx]
				var w := float(v if across else u) / float(cell - 1)   # 束の幅の中の位置（端ほど沈む）
				var dome := sin(w * PI)
				var hair := rng.randf_range(-0.10, 0.10)
				var k := clampf(t * f * (0.55 + 0.45 * dome) + hair, 0.0, 1.4)
				img.set_pixel(x, y, Color(0.45 * k, 0.35 * k, 0.23 * k))   # 棕櫚の枯れた茶（橙に寄せない）
				var h := clampf(0.15 + 0.75 * dome * (0.85 + 0.3 * (f - 0.95)) + hair * 0.6, 0.0, 1.0)
				bump.set_pixel(x, y, Color(h, h, h))
	else:
		# 布の色（くすんだ藍・錆・黄土・生成り・苔・小豆）。数段ずつ同じ布が続き、段ごとに少し濃さが違う
		var cloths := [Color(0.24, 0.30, 0.45), Color(0.60, 0.30, 0.22), Color(0.70, 0.52, 0.25), Color(0.80, 0.74, 0.62),
				Color(0.38, 0.45, 0.30), Color(0.45, 0.24, 0.28)]
		var row := 4
		var rows := n / row
		var col: Array[Color] = []
		var phase: Array[float] = []
		var left := 0
		var pick := 0
		for r in rows:
			if left <= 0:
				pick = (pick + 1 + rng.randi_range(0, cloths.size() - 2)) % cloths.size()
				left = rng.randi_range(2, 7)
			left -= 1
			col.append((cloths[pick] as Color) * rng.randf_range(0.86, 1.08))
			phase.append(rng.randf_range(0.0, TAU))
		for y in n:
			for x in n:
				var r := y / row
				var v := float(y % row) / float(row - 1)
				var warp := (x / 4 + r) % 2 == 0   # たて糸の上を通るか下をくぐるか
				var twist := 0.5 + 0.5 * sin(float(x) * 0.55 + phase[r])   # 裂いた布のよじれ
				var dome := sin(v * PI)
				var k := (0.62 + 0.38 * dome) * (1.0 if warp else 0.86) * (0.9 + 0.2 * twist) + rng.randf_range(-0.04, 0.04)
				var c: Color = col[r] * k
				img.set_pixel(x, y, Color(c.r, c.g, c.b))
				var h := clampf(0.2 + 0.6 * dome * (1.0 if warp else 0.8) + 0.1 * twist, 0.0, 1.0)
				bump.set_pixel(x, y, Color(h, h, h))
	bump.bump_map_to_normal_map(6.0 if not rag else 4.0)
	img.generate_mipmaps()
	bump.generate_mipmaps()
	_doormat_maps[rag] = [ImageTexture.create_from_image(img), ImageTexture.create_from_image(bump)]
	return _doormat_maps[rag]


## ガラス: ほとんど透けて、外の雪と空が見える。淡い水色をわずかにのせ、縁の照り返しで「ガラスがある」と分かる程度に
## （2026-11-03 代表「ロッジのガラスの透明度を挙げられますか？」）
static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.86, 0.93, 1.0, GLASS_ALPHA)
	m.roughness = 0.05
	m.metallic_specular = 0.7
	m.rim_enabled = true   # 斜めから見ると少し白く光る（板ガラスの縁の照り返し）
	m.rim = 0.25
	m.rim_tint = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # 中からも外からも同じに見える
	return m


const GLASS_ALPHA := 0.10   # ガラスの濃さ（0 で何もない、1 で不透明）


static func _metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()   # 鉄（金網、戸の帯、自動ドアの框）
	m.albedo_color = Color(0.20, 0.20, 0.22)
	m.metallic = 0.6
	m.roughness = 0.45
	return m


## 開き戸の板（glb の swingdoor_<名前>・swingdoor_<名前>_glass）を、蝶番の目印（hinge_swingdoor_<名前>）の軸のまわりに回せるよう、
## 軸に置いた回し台の下へ移す。名前の最後の _<番号> を除いたものが 1 つの戸（両開きなら 2 枚）
func _make_swing_doors() -> void:
	var groups := {}
	for h in find_children("hinge_swingdoor_*", "Node3D", true, false):
		var leaf_name := String(h.name).trim_prefix("hinge_")
		var door_id := leaf_name.substr(0, leaf_name.rfind("_"))
		var parts: Array[Node3D] = []
		for nm in [leaf_name, leaf_name + "_glass"]:
			var n := find_child(nm, true, false) as Node3D
			if n:
				parts.append(n)
		if parts.is_empty():
			continue
		var hinge: Vector3 = to_local((h as Node3D).global_position)
		var box := AABB()
		for i in parts.size():
			var mi := parts[i] as MeshInstance3D
			if mi:
				var bb := (global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
				box = bb if i == 0 else box.merge(bb)
		if Engine.is_editor_hint():
			continue
		var pivot := Node3D.new()
		pivot.name = "Swing_" + leaf_name
		add_child(pivot)
		pivot.position = hinge
		for n in parts:
			n.reparent(pivot, true)
		var along := box.get_center() - hinge   # 蝶番から板の真ん中へ（壁に沿う）
		along.y = 0.0
		var g: Dictionary = groups.get(door_id, {"leaves": [], "box": box})
		g.leaves.append({"pivot": pivot, "along": along.normalized()})
		g.box = g.box.merge(box)
		groups[door_id] = g
	for door_id in groups:
		var g: Dictionary = groups[door_id]
		var along: Vector3 = g.leaves[0].along
		var normal := Vector3.UP.cross(along).normalized()   # 戸の面に垂直（どちらの側か決める向き）
		for lf in g.leaves:
			# 角が正なら、板は UP×along の向きへ動く。戸の向き normal へ動くなら +1
			lf["sign"] = 1.0 if Vector3.UP.cross(lf.along).dot(normal) > 0.0 else -1.0
		var center: Vector3 = (g.box as AABB).get_center()
		var area := Area3D.new()
		area.name = "SwingSensor_" + door_id
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3((g.box as AABB).size.x, 3.0, (g.box as AABB).size.z)
		sh.size += (along.abs() * 0.8 + normal.abs() * SWING_REACH * 2.0)
		cs.shape = sh
		area.add_child(cs)
		area.position = center
		add_child(area)
		_swing.append({"leaves": g.leaves, "center": center, "normal": normal, "area": area, "side": 0, "a": 0.0})


## 自動ドア: 人（CharacterBody3D）が戸の前後 3 m に入ると左右へ開き、いなくなると閉まる
func _make_auto_door() -> void:
	var box := AABB()
	var first := true
	for side in ["l", "r"]:
		for nm in ["autodoor_" + side, "autodoor_glass_" + side]:
			var n := find_child(nm, true, false) as Node3D
			if n == null:
				continue
			_auto_doors.append(n)
			_auto_home.append(n.position.x)
			_auto_sign.append(-1.0 if side == "l" else 1.0)
			if n is MeshInstance3D:
				var b := (n as MeshInstance3D).get_aabb()
				b = (global_transform.affine_inverse() * n.global_transform) * b
				box = b if first else box.merge(b)
				first = false
	if _auto_doors.is_empty() or Engine.is_editor_hint():
		return
	_auto_area = Area3D.new()
	_auto_area.name = "AutoDoorSensor"
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(box.size.x + 1.0, 3.0, 6.0)
	cs.shape = sh
	_auto_area.add_child(cs)
	_auto_area.position = box.get_center()
	add_child(_auto_area)


func _process(dt: float) -> void:
	_t += dt
	if fire_light:   # 炉の火の揺らぎ
		fire_light.light_energy = 1.2 + 0.3 * sin(_t * 13.0) + 0.2 * sin(_t * 7.3 + 1.0)
	if _auto_area:
		var someone := false
		for b in _auto_area.get_overlapping_bodies():
			if b is CharacterBody3D:
				someone = true
				break
		_auto_open = move_toward(_auto_open, 1.0 if someone else 0.0, dt / (0.9 if someone else 1.6))
		var e := _auto_open * _auto_open * (3.0 - 2.0 * _auto_open)   # なめらかに
		for i in _auto_doors.size():
			_auto_doors[i].position.x = _auto_home[i] + _auto_sign[i] * AUTO_SLIDE * e
	for d in _swing:
		_swing_step(d, dt)


## 開き戸: 閉まっていれば、いちばん近い人から見て押す向き（人の向こう側）へ開く。開いているあいだは、その向きのまま
## （だれかが開けた向きなら、反対から来た人にもそのまま開けておく）。だれもいなくなると閉まり、閉じきったら向きを忘れる。
## 2026-11-02 代表「しまってる状態なら自分側から押して開く方に開いて、もし誰か開けてたりして引き戸の方に開いてたらそのまま開けて」。
## どの画面も、見えている人の位置で開く（通信は使わない。風除室の自動ドアと同じ）
func _swing_step(d: Dictionary, dt: float) -> void:
	var near: Node3D = null
	var best := INF
	for b in (d.area as Area3D).get_overlapping_bodies():
		if b is CharacterBody3D:
			var dist: float = (to_local(b.global_position) - d.center).length()
			if dist < best:
				best = dist
				near = b
	if near and d.side == 0:   # 閉まっている戸を開ける: 人の向こう側へ
		d.side = -1 if (to_local(near.global_position) - d.center).dot(d.normal) > 0.0 else 1
	d.a = move_toward(d.a, 1.0 if near else 0.0, dt / (0.45 if near else 1.2))
	if d.a <= 0.0:
		d.side = 0
	var e: float = d.a * d.a * (3.0 - 2.0 * d.a)   # なめらかに
	for lf in d.leaves:
		(lf.pivot as Node3D).rotation.y = d.side * lf.sign * SWING_OPEN * e
