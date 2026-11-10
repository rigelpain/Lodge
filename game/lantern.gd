extends Node3D
## 帯に提げたランタン（装備。craft.gd の lanterns）。人形（doll.gd）が 1 つ持ち、人形の lantern（形の名前）と lantern_lit を読む。
## 形は props/build_lantern.py の glb（提げる所が原点、体は下）。左の腰に提げる（右の腰は米袋、右手は紐と雪玉）。
## 揺れは人形と同じ 12 コマの時計で刻む: 歩くと前後に少し振れ、止まると垂れて戻る。居場所だけは毎フレーム帯を追う。
## 灯りは 1 つの OmniLight3D。揺れのコマで跳ばないよう、灯りはランタンの芯をなめらかに追う。
## 揺らぎは小さくゆっくり（±3% ほど、数秒の周期）。画面全体の明るさがちらつかないように、点け消しもふわっと変える。
## 影は落とさない: 腰の灯りは体の影で半分欠け、何人も持つと影の描画が重い。遠いランタンの灯りは消す（光る紙は見える）。
## 消す距離は、見ているカメラの寄り具合で延ばす（双眼鏡で寄ると、遠くの人のランタンの灯りも見える。2026-11-09 代表「ランタンの明かりは描写してほしい」）。
## 見た目だけ。通信には乗せない（誰が点けたかは craft.gd の lamp の出来事、どの形かは equip・lantern_buy の出来事、色は lantern_dye の出来事）。
##
## 形違い（2026-11-01 代表「ランタンのバリエーションも増やして売って欲しい」。絵 design/lantern-variety/01-sheet.jpg の L1〜L10）。
## 木の手提げと和紙の提灯ははじめから持つ。ほかの 8 つは、1 階のテントの紙細工屋さん（paper_lady.gd・paper_shop_ui.gd）で売る。
## 形ごとに、光の色（灯りと光る紙）と揺らぎ方（STYLE）が違う。値段は木のボタンの何個分。標準は素朴で丈夫、凝ったものほど高い
## 色替え（2026-11-10）: 紙細工屋さんで、光の色をキャラの色のパレット（craft.gd の COLORS）の色に染められる（craft.gd の lantern_dye）。
## 染めた色は、色合いと鮮やかさをそのまま、明るさだけ灯りの明るさにそろえる（暗い色を選んでも暗い灯りにならない。tint）。人形の lantern_color
## 黒（2026-11-10 代表「ランタンの染色ですが、黒いランタンは逆に周囲を暗くするようにしてほしいです。」）: パレットの中の、明るさが低く色みのほとんどない色
## （is_black。いまは墨の灰 COLORS[10] だけ）に染めたランタンは、点けるとランタンを中心に球の形で暗くする（代表「最も強くしてほしいし、
## 暗くする範囲は床でなく…球状に暗くしてほしい」「キャラ中心じゃなくてランタン中心だ」）:
##   暗がりの球（lantern_dark.gdshader）: ランタンの芯を中心に半径 DARK_RADIUS。球を通して見える物を墨の色へ寄せる（掛け算なので色みはずれない）
##   引く灯り（light_negative）: 同じ芯から、球の少し外まで、まわりの物に当たる光を引く。濃さ BLACK_ENERGY
## 紙は光らず、点けると墨を含ませた和紙のように深い黒、消すと消し炭の灰

const Props := preload("res://props.gd")
## 形の名前 → {price 値段（0 ははじめから）, color 灯りの色, glow 光る紙の色, style 揺らぎ方, energy 灯りの強さの倍率}
## style: calm ゆっくり揺らぐ（±3%）/ steady じっと灯る / breath 息をするように明暗 / spin まだらの光がゆっくり回る（体が回る）/
##        candle ろうそくのようにちらつく / firefly 蛍が明滅する / shimmer 青白くきらめく
const LOOK := {
	"box": {"price": 0, "color": Color(1.0, 0.68, 0.40), "glow": Color(1.0, 0.74, 0.44), "style": "calm", "energy": 1.0},
	"paper": {"price": 0, "color": Color(1.0, 0.68, 0.40), "glow": Color(1.0, 0.74, 0.44), "style": "calm", "energy": 1.0},
	"spool": {"price": 40, "color": Color(1.0, 0.72, 0.36), "glow": Color(1.0, 0.76, 0.40), "style": "steady", "energy": 1.0},
	"knit": {"price": 80, "color": Color(1.0, 0.52, 0.40), "glow": Color(1.0, 0.58, 0.46), "style": "calm", "energy": 1.0},
	"hoop": {"price": 120, "color": Color(1.0, 0.90, 0.76), "glow": Color(1.0, 0.92, 0.80), "style": "breath", "energy": 0.95},
	"yarnball": {"price": 200, "color": Color(1.0, 0.64, 0.50), "glow": Color(1.0, 0.70, 0.55), "style": "spin", "energy": 1.0},
	"thimble": {"price": 300, "color": Color(1.0, 0.74, 0.28), "glow": Color(1.0, 0.80, 0.36), "style": "candle", "energy": 1.05},
	"hotaru": {"price": 500, "color": Color(0.74, 1.0, 0.40), "glow": Color(0.80, 1.0, 0.42), "style": "firefly", "energy": 0.9},
	"pearl": {"price": 1000, "color": Color(0.78, 0.87, 1.0), "glow": Color(0.86, 0.92, 1.0), "style": "shimmer", "energy": 1.0},
	"raden": {"price": 1500, "color": Color(1.0, 0.60, 0.20), "glow": Color(1.0, 0.66, 0.28), "style": "calm", "energy": 1.1},
}
const LOOKS := ["box", "paper", "spool", "knit", "hoop", "yarnball", "thimble", "hotaru", "pearl", "raden"]   # 並び（0 番が標準）
const COLOR := Color(1.0, 0.68, 0.40)    # ロッジの灯り（props.gd）と同じ、電球色より少し赤み
const ENERGY := 2.2
const RANGE := 7.0
const ATTEN := 1.2
const FADE := 0.35                       # 点け消しにかかる秒
const FAR := 40.0                        # この距離から先は灯りを薄くして消す（ふつうの画角のとき）
const FAR_LEN := 10.0                    # 薄くしてから消えるまでの幅
## 帯の左の腰の少し後ろ（glb の座標、人形の大きさのまま）。doll.gd の BELT（右）を左右に返す。後ろから（三人称で）見えるように外へ出す
const BELT := {"kasa": Vector3(-0.25, 0.6, 0.07), "origami": Vector3(-0.26, 0.8, 0.07), "news": Vector3(-0.27, 0.34, 0.07),
	"robo": Vector3(-0.21, 0.27, 0.07), "musha": Vector3(-0.19, 0.28, 0.07), "ningyo": Vector3(-0.21, 0.42, 0.07), "golem": Vector3(-0.38, 0.45, 0.1)}
## 人形の大きさに対するランタンの大きさ（小さい人形の足もとに着かないように）
const SIZE := {"kasa": 0.95, "origami": 1.0, "news": 0.72, "robo": 0.75, "musha": 0.72, "ningyo": 0.75, "golem": 1.0}

var doll: Node3D
var _anchor: Node3D            # 帯の所（腰の骨に付ける）
var _body: Node3D              # 形（glb）
var _look := ""
var _hex := ""                 # 染めた色（"" は形のもとの色）
var _papers: Array[MeshInstance3D] = []
var _paper_on: Material
var _light: OmniLight3D
var _core := Vector3(0, -0.21, 0)   # 灯りの芯（形の座標）
var _swing := Vector2.ZERO     # x 前後、z 左右（rad）。コマで決める
var _vel := Vector2.ZERO
var _level := 0.0              # 0 消えている … 1 点いている
var _seed := randf() * 100.0
var _t := 0.0
var _lit_paper := true
var _paper_off: Material
var _style := "calm"
var _fade_k := 1.0             # いま灯りを消す距離に掛けている、カメラの寄り具合（_fit_fade）
var _sub_t := 0.0              # 黒: 引く光の色を見直すまでの秒
var _sub_want := BLACK_SUB     # 黒: 寄せていく引く光の色
var _dark: MeshInstance3D      # 黒: 暗がりの球


## 形の glb（光る紙は形の色に染める）。ランタン掛けと売り台の札でも使う
static func model(look: String) -> String:
	return "res://props/lantern/lantern_%s.glb" % (look if LOOK.has(look) else "box")


static func price(look: String) -> int:
	return int(LOOK[look].price) if LOOK.has(look) else -1


static var BLACK_ENERGY := 1.6           # 黒いランタンの、引く灯りの強さ（ふつうの ENERGY 2.2 に対して。濃さの案 0.6・1.0・1.6 のいちばん強いもの）
static var DARK_RADIUS := 3.0            # 暗がりの球の半径 (m)
static var DARK_STRENGTH := 0.85         # 暗がりの球の、芯を通る視線での濃さ（1 で真っ黒）
const DARK_SHADER := preload("res://lantern_dark.gdshader")
const BLACK_SUB := Color(1.0, 0.96, 0.86)   # 引く光の色（札の中など、まわりの光が分からないとき）
## 引く光の色は、その場の光の色に寄せる（同じだけ引くと、少ない色から先に尽きて、夜は青、火のそばは赤の縁ができる）:
## 外は日・月の光の色（daycycle.gd の _sun）、焚き火に近ければ火の色、ロッジの中は灯りの色（COLOR）。BLACK_TINT_T 秒ごとに見直す
const BLACK_TINT_T := 0.4
const FIRE_TINT := Color(1.0, 0.55, 0.28)
const FIRE_NEAR := 7.0                     # 焚き火からこの距離 (m) の内で、火の色に寄せる
const INK := Color(0.06, 0.06, 0.08)       # 点いた黒い紙（墨を含ませた和紙）
const INK_OFF := Color(0.22, 0.22, 0.25)   # 消えた黒い紙（消し炭の和紙）

## 色 hex が「黒」か: 明るさが低く（0.4 未満）、色みがほとんどない（0.25 未満）。パレットでは墨の灰（craft.gd の COLORS[10]）だけ
static func is_black(hex: String) -> bool:
	if hex == "" or not hex.is_valid_html_color():
		return false
	var c := Color(hex)
	return c.v < 0.4 and c.s < 0.25


## 形 look を色 hex（"rrggbb"。"" は形のもとの色）に染めた光の色。glow なら光る紙の色、でなければ灯りの色。
## 色合い・鮮やかさは選んだ色、明るさは灯りの明るさ。光る紙は光って白に飛びやすいので、鮮やかさを少し足す
static func tint(look: String, hex: String, glow := false) -> Color:
	var L: Dictionary = LOOK.get(look, LOOK["box"])
	if hex == "" or not hex.is_valid_html_color():
		return L.glow if glow else L.color
	if is_black(hex):   # 黒: 紙は墨の色、灯りは引く光の色（light_negative で使う）
		return INK if glow else BLACK_SUB
	var c := Color(hex)
	return Color.from_hsv(c.h, minf(1.0, c.s * (1.25 if glow else 1.0)), 1.0)


## 揺らぎ: 灯りの強さの倍率（1 のまわり）。t は秒、seed は灯りごとのずらし
static func flicker(style: String, t: float, seed: float) -> float:
	match style:
		"steady":
			return 1.0
		"breath":   # 4 秒ほどでゆっくり明るく・暗く
			return 1.0 + 0.2 * sin(t * 1.5 + seed)
		"candle":   # 細かく速いちらつき（画面全体が明滅しないよう ±10% ほど）
			return 1.0 + 0.05 * sin(t * 7.3 + seed) + 0.035 * sin(t * 11.9 + seed * 2.3) + 0.025 * sin(t * 17.3 + seed * 0.7)
		"firefly":  # 薄い灯りの上に、蛍が 1 匹ずつ灯って消える（3 つの間合いの重なり）
			var b := 0.0
			for k in 3:
				b = maxf(b, pow(maxf(0.0, sin(t * (0.9 + 0.27 * k) + seed * (1.0 + k))), 6.0))
			return 0.55 + 0.6 * b
		"shimmer":  # 小さく速いきらめき
			return 1.0 + 0.05 * sin(t * 3.1 + seed) + 0.04 * sin(t * 5.7 + seed * 1.3) + 0.03 * sin(t * 9.4)
	return 1.0 + 0.02 * sin(t * 0.9 + seed) + 0.012 * sin(t * 2.1 + seed * 1.7)


## 形 look の光る紙を、形の色（染めていれば色 hex）に染めた点いた素材にする（読んだ glb の素材を写して使う。素材は形と色ごとに 1 つ）
static var _glow_mats := {}

static func glow_material(look: String, src: Material, hex := "") -> StandardMaterial3D:
	var key := look + ":" + hex
	if _glow_mats.has(key):
		return _glow_mats[key]
	var m := (src.duplicate() if src else StandardMaterial3D.new()) as StandardMaterial3D
	if m == null:
		return null
	var c := tint(look, hex, true)
	if is_black(hex):   # 黒い紙は光らない。墨を含ませた和紙（紙のすじは残す）
		m.emission_enabled = false
		m.albedo_color = c
		m.roughness = 1.0
		m.metallic_specular = 0.1
	else:
		m.emission_enabled = true
		m.emission = c
		m.albedo_color = Color(1, 1, 1).lerp(c, 0.35)
	_glow_mats[key] = m
	return m


## 形 look の体を作り、光る紙を形の色（染めていれば色 hex）に染める（灯りは付けない）。光る紙の部品の配列を返す [体, 光る紙の配列]
static func make_body(look: String, hex := "") -> Array:
	var body := Props.make(model(look))
	var papers: Array[MeshInstance3D] = []
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).ends_with("_paper"):   # 光る紙の組（prop_<形>_paper。和紙の提灯の形の名前にも paper が入るので、末尾で見る）
			papers.append(m)
			var g := glow_material(look, m.get_surface_override_material(0), hex)
			if g:
				m.set_surface_override_material(0, g)
	var mark := body.find_child("light*", true, false) as Node3D
	if mark:
		for c in mark.get_children():   # props.gd が目印にともす灯りは使わない
			c.queue_free()
	return [body, papers]


func _init(d: Node3D) -> void:
	doll = d


func setup(skel: Skeleton3D, hips_rest: Transform3D, kind: String, scale_k: float) -> void:
	var at := BoneAttachment3D.new()
	at.bone_name = "hips"
	skel.add_child(at)
	_anchor = Node3D.new()
	_anchor.position = hips_rest.affine_inverse() * (BELT.get(kind, BELT["kasa"]) as Vector3)
	at.add_child(_anchor)
	top_level = true
	scale = Vector3.ONE * scale_k * SIZE.get(kind, 1.0)
	_light = OmniLight3D.new()
	_light.top_level = true
	_light.light_color = COLOR
	_light.omni_range = RANGE
	_light.omni_attenuation = ATTEN
	_light.shadow_enabled = false
	_light.light_specular = 0.2
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = FAR
	_light.distance_fade_length = FAR_LEN
	_light.visible = false
	add_child(_light)
	_dark = MeshInstance3D.new()   # 黒の暗がりの球（黒に染めたときだけ見せる）
	_dark.top_level = true
	var sm := SphereMesh.new()
	sm.radial_segments = 24
	sm.rings = 12
	_dark.mesh = sm
	var dm := ShaderMaterial.new()
	dm.shader = DARK_SHADER
	_dark.material_override = dm
	_dark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dark.visible = false
	add_child(_dark)


## 形を替える（"" で外す）。hex は染めた色
func _set_look(look: String, hex := "") -> void:
	_look = look
	_hex = hex
	if _body:
		_body.queue_free()
		_body = null
	_papers.clear()
	visible = look != ""
	if look == "":
		return
	var made := make_body(look, hex)
	_body = made[0]
	add_child(_body)
	_style = String(LOOK.get(look, LOOK["box"]).style)
	_light.light_color = tint(look, hex)
	_light.light_negative = is_black(hex)   # 黒はまわりの光を引く
	_sub_t = 0.0
	_dark.layers = doll.layers | ((1 << 2) if doll.layers == 1 << 1 else 0)
	_light.light_specular = 0.0 if _light.light_negative else 0.2
	_light.omni_range = DARK_RADIUS + 1.0 if _light.light_negative else RANGE   # 黒は暗がりの球の少し外まで（床に広く落とさない）
	var mark := _body.find_child("light*", true, false) as Node3D
	if mark:
		_core = (global_transform.affine_inverse() * mark.global_transform).origin
	_paper_on = null
	_paper_off = null
	for m in made[1]:   # 光る紙（灯りの芯・提灯の紙・指ぬきの穴・蛍のおしり）。明滅する形は、灯りごとに素材を写して明るさを変える
		_papers.append(m)
		if _paper_on == null:
			var on := m.get_surface_override_material(0) as StandardMaterial3D
			_paper_on = on.duplicate() if on and _style in ["breath", "candle", "firefly", "shimmer"] else on
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.layers = doll.layers | ((1 << 2) if doll.layers == 1 << 1 else 0)   # あなたのランタンは一人称でも見える（見下ろすと腰に揺れている）
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_lit_paper = not (_level > 0.5)   # 読んだばかりの紙を、いまの点け消しの素材にする
	_show_paper(_level > 0.5)


## 光る紙の素材を、点いている・消えているで替える（消えた方は、形ごとに写しを 1 つ作って使う）
func _show_paper(on: bool) -> void:
	if on == _lit_paper or _paper_on == null:
		return
	_lit_paper = on
	if _paper_off == null:
		var m := _paper_on.duplicate() as StandardMaterial3D
		if m:
			m.emission_enabled = false
			m.albedo_color = INK_OFF if _light.light_negative else m.albedo_color.darkened(0.12)   # 黒は消すと消し炭の灰（点くと深くなる）
		_paper_off = m if m else _paper_on
	for p in _papers:
		p.set_surface_override_material(0, _paper_on if on else _paper_off)


## 人形が 12 コマごとに呼ぶ: 揺れを決める。speed は歩く速さ (m/s)、phase は歩みの位相、riding は乗っている
func step(speed: float, phase: float, accel: Vector2, riding: bool) -> void:
	if _look == "":
		return
	var dt := 1.0 / 12.0
	# 振り子: 歩みの上下で前後に振れ、速さの変わり目で後ろ・前へ振られる（コマで刻むので、少しかくっと動く）
	var walk := clampf(speed / 3.0, 0.0, 1.0) * (0.0 if riding else 1.0)
	var goal := Vector2(0.16 * walk * sin(phase) - clampf(accel.y * 0.05, -0.3, 0.3), 0.07 * walk * cos(phase * 0.5) - clampf(accel.x * 0.04, -0.2, 0.2))
	if riding:   # 乗っているときは、腰の横で外へ少し傾け、座面や雪にめり込まないように持ち上げる
		goal += Vector2(0.0, -0.9)
	_vel += (goal - _swing) * 55.0 * dt
	_vel *= 0.62
	_swing += _vel * dt
	_swing = _swing.clamp(Vector2(-1.2, -1.2), Vector2(1.2, 1.2))


## 人形が毎物理フレーム呼ぶ: 帯を追い、灯りの強さを変える
func follow(dt: float, yaw: float) -> void:
	var want: String = doll.get("lantern")
	var hex: String = doll.get("lantern_color")
	if want != _look or hex != _hex:
		_set_look(want, hex)
	var lit: bool = doll.get("lantern_lit") and _look != ""
	_level = move_toward(_level, 1.0 if lit else 0.0, dt / FADE)
	_t += dt
	if _look == "":
		_light.visible = false
		_dark.visible = false
		return
	var turn := Basis(Vector3.UP, _t * 0.5 + _seed) if _style == "spin" else Basis()   # 糸玉は提げ紐のまわりにゆっくり回る
	global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(_swing.x, 0.0, _swing.y)) * turn * Basis.from_scale(scale), _anchor.global_position)
	_show_paper(_level > 0.5)
	_light.visible = _level > 0.001
	if _light.visible:
		_fit_fade()
		# 揺らぎ: 形ごとの揺らぎ方（flicker）。芯の所へ、なめらかに寄せる
		var flick := flicker(_style, _t, _seed)
		if _paper_on is StandardMaterial3D and _style in ["breath", "candle", "firefly", "shimmer"]:
			(_paper_on as StandardMaterial3D).emission_energy_multiplier = 1.6 * flick
		if _light.light_negative:
			_sub_t -= dt
			if _sub_t <= 0.0:
				_sub_t = BLACK_TINT_T
				_sub_want = _sub_color(_light.global_position)
			_light.light_color = _light.light_color.lerp(_sub_want, 1.0 - exp(-dt * 4.0))
		_light.light_energy = (BLACK_ENERGY if _light.light_negative else ENERGY) * float(LOOK.get(_look, LOOK["box"]).energy) * flick * smoothstep(0.0, 1.0, _level)
		var core := global_transform * _core
		_light.global_position = core if _light.global_position == Vector3.ZERO else _light.global_position.lerp(core, 1.0 - exp(-dt * 12.0))
	_dark.visible = _light.light_negative and _light.visible
	if _dark.visible:
		_dark.global_position = _light.global_position   # ランタンの芯（灯りと同じく、揺れのコマで跳ばないよう、なめらかに追う所）
		_dark.scale = Vector3.ONE * DARK_RADIUS * 1.02 / 0.5   # SphereMesh は半径 0.5
		var dm := _dark.material_override as ShaderMaterial
		dm.set_shader_parameter("radius", DARK_RADIUS)
		dm.set_shader_parameter("strength", DARK_STRENGTH)
		dm.set_shader_parameter("level", smoothstep(0.0, 1.0, _level) * clampf(flicker(_style, _t, _seed), 0.0, 1.2))


## 黒: 所 at の光の色（いちばん明るい成分を 1 にそろえる）。外は日・月、焚き火に近ければ火、ロッジの中は灯り
func _sub_color(at: Vector3) -> Color:
	var tree := get_tree()
	var c := BLACK_SUB
	var dc := tree.root.get_node_or_null("DayCycle")
	var sun = dc.get("_sun") if dc else null
	if sun is DirectionalLight3D and (sun as DirectionalLight3D).light_energy > 0.01:
		c = (sun as DirectionalLight3D).light_color.lerp(Color(0.62, 0.72, 1.0), 0.25)   # 日・月の光に、空の青を少し
	if not preload("res://campfire.gd").outside(tree, at):
		c = COLOR
	else:
		var near := FIRE_NEAR
		for f in tree.get_nodes_in_group("fires"):
			if is_instance_valid(f) and f.has_method("lit") and f.lit():
				near = minf(near, (f as Node3D).global_position.distance_to(at))
		c = c.lerp(FIRE_TINT, 1.0 - smoothstep(1.5, FIRE_NEAR, near))
	var m := maxf(c.r, maxf(c.g, c.b))
	return Color(c.r / m, c.g / m, c.b / m) if m > 0.0 else BLACK_SUB


## 灯りを消す距離を、見ているカメラの寄り具合に合わせる。寄り具合は doll.gd の view_lod と同じ（画角 75° を 1 として、狭いほど遠くまで）。
## 双眼鏡で 24° なら 125 m、遠見の双眼鏡やテラスの台で寄りきると 450〜600 m まで灯る。灯りの数は増えるが、狭い画角では描く物が減る
func _fit_fade() -> void:
	var cam := get_viewport().get_camera_3d()
	var k := clampf(cam.fov / 75.0, 0.02, 1.0) if cam else 1.0
	if absf(k - _fade_k) < 0.005:
		return
	_fade_k = k
	_light.distance_fade_begin = FAR / k
	_light.distance_fade_length = FAR_LEN / k


## 灯りの芯（世界）。消えていれば INF
func light_point() -> Vector3:
	return _light.global_position if _light and _light.visible else Vector3.INF
