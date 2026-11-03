@tool
extends Node3D
## ロッジの中の火の灯りの道具（2026-11-01 代表「ロッジの中は真っ暗な部分がないようにライト、というかガス火とかキャンドルとか松明とか置いてほしい」）。
## lodge.gd が 1 つ置く（ロッジの子。置き物なので、通信の誰の画面でも同じ所に出る）。
## 道具は場所で選ぶ: 丸太の壁には松明、厨房・風除室・階段の壁にはガス灯、卓と窓のカウンターにはキャンドル、
## 窓ぎわの床には燭台、厨房の奥の台にはガスコンロの火。形は手芸の素材（look.gd）の箱と筒を組んで作る:
## 松明は木の柄に麻の布を巻き、鉄はこげ茶のフェルト。ガス灯は真鍮色のフェルトの腕に、透明なフィルムの窓と木の枠。
## キャンドルはクリームのフェルトの芯に紙の帯を巻き、木の皿に載せる。
## 炎は焚き火と同じ火の手本（game/flame.gd。赤・橙のフェルトと黄の紙を切って十字に差した炎。2026-11-02 代表が選んだ形。
## 12 コマの 2 コマごとに形を差し替える）を使う。灯りは道具ごとに 1 つこちらで持つので、手本の灯りは作らない（brightness 0）。
## flame.gd がまだない間（#108 が main に入る前）は、仮の炎（_fire と FIRE_SHADER。色は焚き火にそろえ、2 コマごとに 3 つの形を差し替える）。
## ガスコンロの青い火は、いまは仮の炎のまま（手本の色はまだ替えられない）。
## 灯りは影を落とさない OmniLight3D を、届く範囲を絞って置く（60 fps を保つため）。強さもコマで ±4% だけ揺らす。
## 確かめ用: --no-fire-lights で置かない（置く前と比べる。game/tools/lodge_light_shots.gd）

const Look := preload("res://look.gd")

const STEP := 1.0 / 12.0                   # 揺れのコマ（12 fps）
const FIRE := Color(1.0, 0.60, 0.32)       # 火の灯りの色。炉（lodge.gd の light_fire）と、部屋の電球色のあいだ
const FADE_BEGIN := 20.0                   # この距離から先は灯りを薄くして消す（外から見るとき・2 階から 1 階の遠く）
const FADE_LEN := 6.0
const DAY_DIM := 0.45                      # 昼の灯りの強さの倍率（daycycle.gd の daylight() が 1 のとき）
const FL1 := 0.45                          # 1 階の床（lodge/dims.py）
const FL2 := 6.10                          # 2 階の床

## 種類ごとの灯り: 強さ, 届く範囲 (m), 減り方（omni_attenuation。小さいほど遠くまでなだらかに届く。
## 1 階の床の板は暗い色なので、なだらかにして床まで届かせる）。強さ 0 は灯りなし（炎だけ光る）。
## 灯りが重なるほど重いので、卓と窓のカウンターのキャンドルは炎だけにし（食堂は天井の灯りがある）、届く範囲も絞る。
## 強さは重さに効かないので、範囲を絞ったぶん強めにする
const LIGHT := {
	"torch": [2.1, 6.5, 0.6],
	"gas": [1.7, 6.0, 0.6],
	"candle": [0.0, 0.0, 0.0],
	"stand": [1.6, 5.0, 0.6],
	"stove": [0.6, 2.5, 0.8],
	"wheel": [2.6, 8.5, 0.5],
}

## ロッジの目印（lodge/dims.py と同じ数。建物の形を変えたら、ここも dims.py に合わせる）。
## 壁の灯りの場所は、この壁の芯の線と丸太の段から決める（2026-11-02 代表「二回の松明が柱のないところ、壁でないとこに浮いてる。
## 壁につけてほしい」。前は 2 階の壁を、間取りを 2 倍にする前の位置で数で書いていて、2 階の松明 7 本が部屋の中に浮いていた）
const K := 1.818                           # 1 間
const G := K * 2.0                         # 間取りの格子
const X0 := -6.0 * G                       # 西の壁の芯（1 階・2 階）
const X1 := 6.0 * G                        # 東の壁の芯
const Y0 := -3.5 * G                       # 1 階の南の壁の芯
const Y1 := 3.5 * G                        # 北の壁の芯（1 階・2 階）
const Y2_0 := Y1 - 5.0 * G                 # 2 階の南の壁の芯（gy(5)）
const X2_0 := X0 + 2.75 * G                # 2 階の西の壁の芯（西の端はテラス。2026-11-03）
const LOG_D := 0.36                        # 丸太の径＝壁の厚み。部屋の側の面は芯から LOG_D / 2
const LOG_H := 0.35                        # 丸太 1 段の高さ
const CEIL1 := FL1 + 3.5 * 1.5             # 1 階の天井
const EAVE_N := FL2 + 2.45 * 1.5           # 2 階の北の壁の上端
const EAVE_S := FL2 + 4.30 * 1.5           # 2 階の南の壁の上端
const RAFTER_H := 0.32                     # 垂木の高さ。2 階の天井（野地板の下面）は屋根の下端の線から RAFTER_H - 0.025 上
const VEST_X1 := X0 + 3.5 * G - 0.30       # 風除室の東の外の面（壁は外の面から内へ LOG_D）
const VEST_X0 := VEST_X1 - 8.0
const BACKING := 0.10                      # 座金の裏の木の台の奥行き。丸太と丸太のあいだのくぼみ（0.08）を埋める

## 壁: 名前 → [壁の芯の線が通る軸（"y" は y = 一定の東西の壁、"x" は x = 一定の南北の壁）, 芯の位置, 向き（度。部屋の側）,
## 丸太の段の始まりの高さ, 下の半分の丸太（dims.py・build_lodge.py の offset）]
const WALLS := {
	"1F_N": ["y", Y1, 0.0, FL1, 0.0],
	"1F_S": ["y", Y0, 180.0, FL1, 0.0],                    # 西の 3.5 格子の丸太の壁（風除室の奥）
	"1F_E": ["x", X1, -90.0, FL1, LOG_H / 2.0],
	"VEST_E": ["x", VEST_X1 - LOG_D / 2.0, -90.0, FL1, LOG_H / 2.0],   # 風除室の東の壁
	"VEST_W": ["x", VEST_X0 + LOG_D / 2.0, 90.0, FL1, LOG_H / 2.0],    # 風除室の西の壁
	"2F_N": ["y", Y1, 0.0, FL2, 0.0],
	"2F_S": ["y", Y2_0, 180.0, FL2, 0.0],
	"2F_W": ["x", X2_0, 90.0, FL2, LOG_H / 2.0],
	"2F_W_OUT": ["x", X2_0, -90.0, FL2, LOG_H / 2.0],     # 2 階の西の壁のテラスの側
	"2F_E": ["x", X1, -90.0, FL2, LOG_H / 2.0],
}

## 置き場: [種類, 場所, 向き（度。0 = 南、90 = 東、180 = 北、-90 = 西）]。場所はロッジの座標 (x 東, y 北, 高さ)。
## 壁の物（torch・gas）は [種類, 壁の名前（WALLS）, 壁に沿った位置（東西の壁は x、南北の壁は y）, 床からの高さ] と書き、
## 場所と向きは places() が壁の面から決める（高さは近い丸太の段の真ん中にそろえ、座金が丸太 1 本に載るように）。
## 吊りの車輪（wheel）の縄は、places() が天井（1 階は CEIL1、2 階は野地板の下面）まで伸ばす。
## 窓（lodge/dims.py の OPENINGS）・戸・柱（COLS）・煙突をよける
const PLACES := [
	# ---- 1 階の松明（丸太の壁）----
	["torch", "1F_N", -16.6, 2.5],      # 北西: 炉の左
	["torch", "1F_N", 14.0, 2.5],       # 北: 厨房の東、勝手口と窓のあいだ
	["torch", "1F_E", 5.8, 2.5],        # 東: 自販機の北、内階段の手前
	["torch", "1F_E", -4.4, 2.5],       # 東: 窓 2 つのあいだ
	["torch", "1F_E", -10.8, 2.5],      # 南東の隅
	["torch", "1F_S", -19.6, 2.5],      # 南西の隅（貸出の棚の上）
	["torch", "1F_S", -10.2, 2.5],      # 南: 内の自動ドアの東
	# ---- 1 階のガス灯 ----
	["gas", "1F_N", 1.7, 3.8],          # 厨房の奥の壁（巨大な装置より上）
	["gas", "1F_N", 8.2, 3.8],
	["gas", "1F_N", 19.2, 4.7],         # 内階段の踊り場の上（踊り場を歩く頭に当たらない高さ）
	["gas", "VEST_E", -15.2, 2.5],      # 風除室の東の壁
	["gas", "VEST_W", -15.2, 2.5],      # 風除室の西の壁
	# ---- 厨房の奥の台のガスコンロ ----
	["stove", Vector3(10.2, 12.05, FL1 + 0.90), 0.0],
	# ---- 天井から吊る車輪のシャンデリア（1 階の天井は 5.7。床の真ん中を照らす）----
	["wheel", Vector3(-15.0, -6.5, FL1 + 3.6), 0.0],   # 入口とミシン・番台のあいだ
	["wheel", Vector3(-16.5, 5.0, FL1 + 3.6), 15.0],   # 北西（炉の左の前）
	["wheel", Vector3(-4.5, 3.5, FL1 + 3.6), 0.0],     # 炉と厨房と食堂のあいだ
	["wheel", Vector3(6.5, 5.5, FL1 + 3.6), 20.0],     # 厨房の前
	["wheel", Vector3(16.0, 4.5, FL1 + 3.6), 0.0],     # 北東（内階段と自販機の前）
	# ---- 西のガラスの壁ぎわの燭台（床置き）----
	["stand", Vector3(-20.7, 9.6, FL1), 90.0],
	# ---- 食堂の卓 8 のキャンドル（卓の真ん中。lodge/dims.py の TABLE_CX・TABLE_CY、卓の高さ 0.72）----
	["candle", Vector3(-3.65, -2.8, FL1 + 0.72), 0.0],
	["candle", Vector3(3.55, -2.8, FL1 + 0.72), 0.0],
	["candle", Vector3(10.35, -2.8, FL1 + 0.72), 0.0],
	["candle", Vector3(17.15, -2.8, FL1 + 0.72), 0.0],
	["candle", Vector3(-3.65, -7.85, FL1 + 0.72), 0.0],
	["candle", Vector3(3.55, -7.85, FL1 + 0.72), 0.0],
	["candle", Vector3(10.35, -7.85, FL1 + 0.72), 0.0],
	["candle", Vector3(17.15, -7.85, FL1 + 0.72), 0.0],
	# ---- 窓向きのカウンターのキャンドル（WINDOW_BAR の高さ 1.05、奥行の真ん中。太くした柱にあわせて 0.18 北へ）----
	["candle", Vector3(-5.0, -12.0, FL1 + 1.05), 0.0],
	["candle", Vector3(2.0, -12.0, FL1 + 1.05), 0.0],
	["candle", Vector3(9.0, -12.0, FL1 + 1.05), 0.0],
	["candle", Vector3(16.0, -12.0, FL1 + 1.05), 0.0],
	# ---- 2 階の松明（2 階は南の壁 y = -5.45、北の壁 y = 12.73 の芯。南の窓・テラスの戸と北の窓・煙突のあいだ）----
	["torch", "2F_W", 6.1, 2.4],        # 西の壁: テラスへの戸（y 3.27）と北の窓のあいだ
	["torch", "2F_W", 0.6, 2.4],        # 西の壁: テラスへの戸と南の窓のあいだ
	["torch", "2F_N", 0.9, 2.4],
	["torch", "2F_N", 9.6, 2.4],
	["torch", "2F_S", -9.4, 2.4],       # 南: 西の壁の東
	["torch", "2F_S", 2.7, 2.4],
	["torch", "2F_S", 13.0, 2.4],
	["torch", "2F_E", 4.2, 2.4],        # 東の端: 衣装掛けの北（染め桶の上）。内階段の上がり口（y 6.2）より南
	# ---- 2 階のテラス（西の端。2026-11-03 代表「ごっそり外にしてテラス化」）: 戸の両脇の外の松明と、卓のキャンドル ----
	["torch", "2F_W_OUT", 4.85, 2.4],
	["torch", "2F_W_OUT", 1.7, 2.4],
	["candle", Vector3(-16.6, 8.4, FL2 + 0.75), 0.0],   # 卓（lodge/dims.py の TERRACE_TABLES）の天板の南寄り。北の端は雪
	["candle", Vector3(-16.6, 2.8, FL2 + 0.75), 0.0],
	["candle", Vector3(-16.6, -2.8, FL2 + 0.75), 0.0],
	["wheel", Vector3(19.0, 0.0, FL2 + 3.2), 0.0],     # 2 階の東の端（衣装掛けの前）。西の端の板の床はテラスになったので置かない
]


## 置き場を [種類, ロッジの座標 (x, y, 高さ), 向き（度）, 吊り縄の長さ（wheel だけ）] にそろえる。
## 壁の物は WALLS の壁の部屋の側の面に、吊りの車輪は天井に付ける（確かめ: game/tools/lodge_light_walls.gd）
static func places() -> Array:
	var out := []
	for p in PLACES:
		var kind: String = p[0]
		if p[1] is String:
			var w: Array = WALLS[p[1]]
			var deg: float = w[2]
			var face: float = w[1] + (LOG_D / 2.0) * (cos(deg_to_rad(deg)) * -1.0 if w[0] == "y" else sin(deg_to_rad(deg)))
			var z0: float = w[3] + w[4] + LOG_H / 2.0                       # いちばん下の丸太の芯の高さ
			var z: float = z0 + roundf((w[3] + p[3] - z0) / LOG_H) * LOG_H   # 近い丸太の段の真ん中
			var at := Vector3(p[2], face, z) if w[0] == "y" else Vector3(face, p[2], z)
			out.append([kind, at, deg])
		elif kind == "wheel":
			var at: Vector3 = p[1]
			out.append([kind, at, p[2], _ceiling(at) - at.z])
		else:
			out.append(p)
	return out


## (x, y) の天井の高さ。1 階は CEIL1、2 階は片流れの屋根の下（垂木のあいだの野地板の下面。build_lodge.py の build_roof）
static func _ceiling(at: Vector3) -> float:
	if at.z < CEIL1:
		return CEIL1
	return EAVE_N + (Y1 - at.y) * (EAVE_S - EAVE_N) / (Y1 - Y2_0) + RAFTER_H - 0.025


var _flames: Array[MeshInstance3D] = []   # 炎（コマごとに形を差し替える）
var _lights: Array[OmniLight3D] = []
var _base: Array[float] = []
var _t := 0.0
var _step := -1

static var _mats := {}
static var _kits := {}                # 種類 → {mesh 道具の形を素材ごとに 1 つにまとめたもの, flames 炎の [置き方, 高さ, 幅, ガス], core 灯りの芯}
static var _fires := {}               # [形の番号, ガス] → 炎の ArrayMesh（赤・橙・黄の層を十字に重ねて 1 つ）
static var _fire_mat: ShaderMaterial
const FLAME_PART := "res://flame.gd"   # 焚き火と同じ火の手本（あれば使う）
static var _drops := {}               # [色の層, 形の番号] → しずくの ArrayMesh


func _ready() -> void:
	name = "LodgeLights"
	if not Engine.is_editor_hint() and "--no-fire-lights" in OS.get_cmdline_user_args():
		visible = false
		set_process(false)
		return
	var part: GDScript = load(FLAME_PART) if ResourceLoader.exists(FLAME_PART) else null
	for p in places():
		var kind: String = p[0]
		var rope: float = p[3] if p.size() > 3 else 0.0
		var key := "%s%.2f" % [kind, rope]
		if not _kits.has(key):
			_kits[key] = _bake(kind, rope)
		var kit: Dictionary = _kits[key]
		var root := Node3D.new()
		var at: Vector3 = p[1]
		root.position = Vector3(at.x, at.z, -at.y)   # ロッジの座標 → Godot（ロッジの子）
		root.rotation.y = deg_to_rad(p[2])
		add_child(root)
		# 形は 1 つの MeshInstance3D（素材ごとの面）、炎は 1 つずつ（描く回数を少なく）
		var body := MeshInstance3D.new()
		body.mesh = kit.mesh
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 小さな物の影は描かない（軽く）
		root.add_child(body)
		for fl in kit.flames:
			if part and not fl[3]:   # 火の手本: 原点が炎の根もと、大きさ 1 で高さ 0.9 m。炎はいつもまっすぐ上へ
				var fp: Node3D = part.new()
				fp.set("size", fl[1] / 0.9)
				fp.set("brightness", 0.0)
				fp.set("seed", _lights.size() * 7 + root.get_child_count())
				fp.position = fl[0].origin
				root.add_child(fp)
				continue
			var f := MeshInstance3D.new()
			f.mesh = _fire(0, fl[3])
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			f.set_meta("base", fl[0])
			f.set_meta("size", Vector2(fl[2], fl[1]))
			f.set_meta("gas", fl[3])
			f.transform = Transform3D(fl[0].basis * Basis.from_scale(Vector3(fl[2], fl[1], fl[2])), fl[0].origin)
			root.add_child(f)
			_flames.append(f)
		var spec: Array = LIGHT[kind]
		if spec[0] <= 0.0:
			continue
		var l := OmniLight3D.new()
		l.light_color = FIRE
		l.light_energy = spec[0]
		l.omni_range = spec[1]
		l.omni_attenuation = spec[2]
		l.light_specular = 0.3
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = FADE_BEGIN
		l.distance_fade_length = FADE_LEN
		l.position = kit.core
		root.add_child(l)
		_lights.append(l)
		_base.append(spec[0])


## 12 コマ: 炎の形を 2 コマごとに 3 つの中から差し替え、毎コマ高さ・幅・傾きを少し変える。灯りの強さも同じコマで少し揺らす
func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += dt
	var n := int(_t / STEP)
	if n == _step:
		return
	_step = n
	for i in _flames.size():
		var f := _flames[i]
		var h := hash(Vector2i(n, i))
		f.mesh = _fire(hash(Vector2i(n / 2, i)) % 3, f.get_meta("gas"))   # 形は 2 コマごとに差し替える（焚き火と同じ）
		var base: Transform3D = f.get_meta("base")
		var size: Vector2 = f.get_meta("size")
		var sx := size.x * (0.94 + 0.10 * ((h >> 4) % 7) / 6.0)
		var sy := size.y * (0.88 + 0.22 * ((h >> 8) % 9) / 8.0)
		var tilt := Basis.from_euler(Vector3(0.0, 0.25 * (((h >> 16) % 3) - 1), 0.10 * (((h >> 12) % 5) - 2) / 2.0))
		f.transform = Transform3D(base.basis * tilt * Basis.from_scale(Vector3(sx, sy, sx)), base.origin)
	# 昼は外の光が入るので、火の灯りは控えめに（昼まで夜と同じ強さだと、部屋じゅうが橙に染まる）
	var cycle := get_node_or_null("/root/DayCycle")
	var day: float = cycle.daylight() if cycle else 0.0
	var k := lerpf(1.0, DAY_DIM, day)
	for i in _lights.size():
		var h := hash(Vector2i(n, 1000 + i))
		_lights[i].light_energy = _base[i] * k * (0.96 + 0.08 * (h % 9) / 8.0)


## 道具 1 種類の形を組み、素材ごとに 1 つの面へまとめる（同じ種類はどこでも同じ形なので、1 度だけ作って使い回す）
func _bake(kind: String, rope: float) -> Dictionary:
	var tmp := Node3D.new()
	var core: Vector3
	match kind:
		"torch": core = _torch(tmp)
		"gas": core = _gas(tmp)
		"candle": core = _candle(tmp)
		"stand": core = _stand(tmp)
		"stove": core = _stove(tmp)
		"wheel": core = _wheel(tmp, rope)
	var groups := {}
	for mi: MeshInstance3D in tmp.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = mi.material_override
		if not groups.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[mat] = st
		(groups[mat] as SurfaceTool).append_from(mi.mesh, 0, _rel(mi, tmp))
	var mesh := ArrayMesh.new()
	for mat in groups:
		(groups[mat] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var flames := []
	for m: Node3D in tmp.find_children("*", "Node3D", true, false):
		if m.has_meta("flame"):
			flames.append([_rel(m, tmp), m.get_meta("h"), m.get_meta("w"), m.get_meta("gas")])
	tmp.free()
	return {"mesh": mesh, "flames": flames, "core": core}


## n の、top から見た置き方（木に入れる前なので global_transform は使えない）
static func _rel(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D()
	var c := n
	while c != top:
		xf = c.transform * xf
		c = c.get_parent()
	return xf


# ---------------------------------------------------------------- 道具の形（原点は付ける所。+Z が正面、+Y が上）

## 壁の松明: こげ茶の鉄（フェルト）の座金と腕、輪に木の柄を差し、先に麻の布を巻いて火をともす。柄は前へ少し倒す
func _torch(root: Node3D) -> Vector3:
	var iron := _mat("iron")
	_box(root, Vector3(0.18, 0.34, 0.04), Vector3(0, 0, 0.02), iron)            # 壁の座金
	_box(root, Vector3(0.16, 0.32, BACKING), Vector3(0, 0, -BACKING / 2.0), _mat("frame"))   # 座金の裏の木の台（丸太のくぼみを埋める）
	_box(root, Vector3(0.05, 0.05, 0.24), Vector3(0, -0.06, 0.14), iron)        # 腕
	_ring(root, 0.065, 0.016, Vector3(0, -0.06, 0.26), iron)                    # 柄を受ける輪
	var stick := Node3D.new()
	stick.position = Vector3(0, -0.06, 0.26)
	stick.rotation.x = deg_to_rad(18.0)                                          # 先を壁から離す
	root.add_child(stick)
	_cyl(stick, 0.035, 0.045, 0.62, Vector3(0, 0.0, 0), _mat("handle"))         # 木の柄
	for i in 3:                                                                   # 麻の布の巻き（段ごとに少し太さを変える）
		_cyl(stick, 0.072 - 0.006 * i, 0.068 - 0.004 * i, 0.07, Vector3(0, 0.27 + 0.065 * i, 0), _mat("hemp" if i != 1 else "cloth"))
	_cyl(stick, 0.05, 0.06, 0.03, Vector3(0, 0.43, 0), _mat("char"))           # 焦げた口
	_flame(stick, Vector3(0, 0.44, 0), 0.46, 0.24)
	return stick.position + stick.basis * Vector3(0, 0.62, 0)


## 壁のガス灯: 真鍮色のフェルトの腕で壁から出し、木の枠に透明なフィルムの窓 4 枚の箱。中の火口に小さな炎
func _gas(root: Node3D) -> Vector3:
	var brass := _mat("brass")
	_box(root, Vector3(0.14, 0.26, 0.04), Vector3(0, -0.05, 0.02), brass)       # 壁の座金
	_box(root, Vector3(0.12, 0.24, BACKING), Vector3(0, -0.05, -BACKING / 2.0), _mat("frame"))   # 座金の裏の木の台
	_box(root, Vector3(0.04, 0.04, 0.34), Vector3(0, 0.0, 0.19), brass)         # 腕
	_ring(root, 0.07, 0.012, Vector3(0, -0.13, 0.20), brass)                    # 腕の下の渦（飾り）
	var box := Node3D.new()
	box.position = Vector3(0, -0.02, 0.40)
	root.add_child(box)
	var wood := _mat("frame")
	_box(box, Vector3(0.26, 0.04, 0.26), Vector3(0, -0.20, 0), wood)            # 底
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:   # 四隅の柱
		_box(box, Vector3(0.025, 0.36, 0.025), Vector3(c.x * 0.115, -0.02, c.y * 0.115), wood)
	var film := _mat("film")
	for k in 4:                                                                   # 窓のフィルム
		var a := k * PI / 2.0
		var pane := _box(box, Vector3(0.22, 0.32, 0.004), Vector3(sin(a) * 0.115, -0.02, cos(a) * 0.115), film)
		pane.rotation.y = a
	var roof := CylinderMesh.new()                                                # 四角すいの屋根と煙出し
	roof.top_radius = 0.03
	roof.bottom_radius = 0.22
	roof.height = 0.12
	roof.radial_segments = 4
	roof.rings = 1
	var r := _mesh(box, roof, Vector3(0, 0.22, 0), brass)
	r.rotation.y = PI / 4.0
	_cyl(box, 0.035, 0.035, 0.06, Vector3(0, 0.30, 0), brass)
	_cyl(box, 0.012, 0.018, 0.08, Vector3(0, -0.15, 0), brass)                  # 火口
	_flame(box, Vector3(0, -0.11, 0), 0.15, 0.09)
	return box.position + Vector3(0, -0.04, 0)


## 卓のキャンドル: 木の皿に、太さの違うクリームのフェルトのろうそくを 3 本。紙の帯を巻き、垂れたろう（小さな玉）
func _candle(root: Node3D) -> Vector3:
	_cyl(root, 0.17, 0.18, 0.025, Vector3(0, 0.0125, 0), _mat("dish"))
	var tallest := Vector3.ZERO
	for c in [[Vector3(0.0, 0, 0.0), 0.05, 0.24], [Vector3(0.09, 0, 0.05), 0.04, 0.16], [Vector3(-0.07, 0, 0.07), 0.035, 0.11]]:
		var at: Vector3 = c[0] + Vector3(0, 0.025, 0)
		var rad: float = c[1]
		var h: float = c[2]
		_cyl(root, rad, rad, h, at + Vector3(0, h / 2.0, 0), _mat("wax"))
		_cyl(root, rad + 0.003, rad + 0.003, h * 0.22, at + Vector3(0, h * 0.35, 0), _mat("band"))   # 紙の帯
		var drip := SphereMesh.new()
		drip.radius = rad * 0.35
		drip.height = rad * 0.9
		drip.radial_segments = 8
		drip.rings = 4
		_mesh(root, drip, at + Vector3(rad * 0.85, h * 0.8, 0), _mat("wax"))
		_cyl(root, 0.004, 0.004, 0.03, at + Vector3(0, h + 0.012, 0), _mat("char"))   # 芯
		_flame(root, at + Vector3(0, h + 0.012, 0), 0.10 + rad * 0.6, 0.06)
		if h > tallest.y:
			tallest = at + Vector3(0, h + 0.06, 0)
	return tallest + Vector3(0, 0.06, 0)


## 床置きの燭台: 木の三つ脚の台に細い柱、上の受け皿にろうそく 3 本（人の背より少し高い）
func _stand(root: Node3D) -> Vector3:
	var wood := _mat("handle")
	for k in 3:
		var leg := _box(root, Vector3(0.05, 0.05, 0.42), Vector3(sin(k * TAU / 3.0) * 0.16, 0.06, cos(k * TAU / 3.0) * 0.16), wood)
		leg.rotation.y = k * TAU / 3.0
	_cyl(root, 0.035, 0.05, 1.7, Vector3(0, 0.85, 0), wood)
	_cyl(root, 0.20, 0.14, 0.05, Vector3(0, 1.72, 0), _mat("brass"))
	for k in 3:
		var at := Vector3(sin(k * TAU / 3.0 + 0.4) * 0.11, 1.745, cos(k * TAU / 3.0 + 0.4) * 0.11)
		var h := 0.20 + 0.05 * k
		_cyl(root, 0.04, 0.04, h, at + Vector3(0, h / 2.0, 0), _mat("wax"))
		_cyl(root, 0.043, 0.043, h * 0.2, at + Vector3(0, h * 0.4, 0), _mat("band"))
		_flame(root, at + Vector3(0, h + 0.01, 0), 0.13, 0.07)
	return Vector3(0, 2.15, 0)


## 吊りの車輪のシャンデリア: 木の車輪（輪とスポーク 6 本）を麻の縄 3 本で天井から吊り、輪の上にろうそく 6 本。
## 原点は車輪の真ん中。rope は天井までの縄の長さ
func _wheel(root: Node3D, rope: float) -> Vector3:
	var wood := _mat("handle")
	var R := 0.75
	_ring(root, R, 0.05, Vector3.ZERO, wood)
	_cyl(root, 0.09, 0.09, 0.10, Vector3.ZERO, wood)                             # こしき
	for k in 3:                                                                   # スポーク（3 本の棒を交差させて 6 本に見せる）
		var sp := _box(root, Vector3(2.0 * R, 0.04, 0.05), Vector3.ZERO, wood)
		sp.rotation.y = k * PI / 3.0
	var top := Vector3(0, rope, 0)
	for k in 3:                                                                   # 麻の縄: 輪の 3 か所から天井の 1 点へ
		var a := Vector3(sin(k * TAU / 3.0) * R, 0.0, cos(k * TAU / 3.0) * R)
		var r := _cyl(root, 0.012, 0.012, (top - a).length(), (top + a) / 2.0, _mat("hemp"))
		r.look_at_from_position(r.position, top, Vector3.FORWARD)
		r.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_cyl(root, 0.06, 0.06, 0.08, top - Vector3(0, 0.04, 0), _mat("iron"))      # 天井の金具
	for k in 6:
		var at := Vector3(sin(k * TAU / 6.0 + PI / 6.0) * R, 0.05, cos(k * TAU / 6.0 + PI / 6.0) * R)
		var h := 0.18 + 0.04 * (k % 3)
		_cyl(root, 0.055, 0.055, 0.02, at, _mat("brass"))                         # 受け皿
		_cyl(root, 0.035, 0.035, h, at + Vector3(0, h / 2.0, 0), _mat("wax"))
		_cyl(root, 0.038, 0.038, h * 0.2, at + Vector3(0, h * 0.4, 0), _mat("band"))
		_flame(root, at + Vector3(0, h + 0.01, 0), 0.13, 0.07)
	return Vector3(0, 0.15, 0)


## 奥の台のガスコンロ: こげ茶のフェルトの台に、五徳の輪 2 つ。輪のまわりに小さな炎（青い根もとの上に橙）が 8 つずつ
func _stove(root: Node3D) -> Vector3:
	_box(root, Vector3(0.80, 0.10, 0.45), Vector3(0, 0.05, 0), _mat("iron"))
	for x in [-0.2, 0.2]:
		_ring(root, 0.11, 0.015, Vector3(x, 0.12, 0), _mat("char"))
		_cyl(root, 0.05, 0.06, 0.03, Vector3(x, 0.115, 0), _mat("brass"))
		for k in 8:
			var a := k * TAU / 8.0
			var f := _flame(root, Vector3(x + sin(a) * 0.07, 0.125, cos(a) * 0.07), 0.07, 0.04, true)
			f.rotation.y = a
	return Vector3(0, 0.45, 0)


# ---------------------------------------------------------------- 炎（フェルトのしずく 3 枚を十字に）

## 炎の置き場の目印（at が根もと、高さ h・幅 w）。gas = true は根もとの層が青いガスの火。_bake が拾って炎を置く
func _flame(parent: Node3D, at: Vector3, h: float, w: float, gas := false) -> Node3D:
	var f := Node3D.new()
	f.position = at
	f.set_meta("flame", true)
	f.set_meta("h", h)
	f.set_meta("w", w)
	f.set_meta("gas", gas)
	parent.add_child(f)
	return f


## 炎 1 つ分の形（幅 1・高さ 1、根もとが原点）: しずくを赤（大）・橙・黄（小）と重ね、十字に 2 枚。
## 両面から見えるので、橙と黄は赤の両側に少し浮かせて重ねる（どちらから見ても黄が手前）。色は頂点の色
static func _fire(shape: int, gas: bool) -> ArrayMesh:
	var key := Vector2i(shape, int(gas))
	if _fires.has(key):
		return _fires[key]
	# 頂点の色の a は明るさ（0 赤の外側は落ち着いて、1 黄の芯ほど明るく。素材の FIRE_SHADER）
	# 色は焚き火（campfire.gd の FLAME_LAYERS）と同じ
	var cols := [Color(0.30, 0.45, 1.0, 0.1) if gas else Color(0.84, 0.22, 0.12, 0.0), Color(0.95, 0.50, 0.14, 0.3), Color(1.0, 0.82, 0.36, 1.0)]
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var uv := PackedVector2Array()
	var cl := PackedColorArray()
	for plane in 2:
		var rot := Basis(Vector3.UP, plane * PI / 2.0)
		for layer in 3:
			var d: Array = _drop(layer, (shape + layer) % 3).surface_get_arrays(0)
			for side in ([0.0] if layer == 0 else [-1.0, 1.0]):
				var off := Vector3(0, 0, side * 0.012 * layer)
				for i in (d[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
					v.append(rot * (d[Mesh.ARRAY_VERTEX][i] + off))
					nm.append(rot * Vector3(0, 0, 1))
					uv.append(d[Mesh.ARRAY_TEX_UV][i])
					cl.append(cols[layer])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = cl
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _fire_material())
	_fires[key] = m
	return m


const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D fiber : filter_linear_mipmap, repeat_enable;
uniform float energy = 1.0;

void fragment() {
	// フェルトの毛羽のむら（明るさを少しまだらに）。頂点の色の a が層の明るさ（外の赤は暗め、芯の黄は明るく）
	float f = texture(fiber, UV * 2.5).r;
	ALBEDO = COLOR.rgb * energy * (0.8 + 1.4 * COLOR.a) * (0.8 + 0.4 * f);
}
"""


## 炎の素材: 光るフェルト（頂点の色 × 明るさ、毛羽のむら）。影は描かない
static func _fire_material() -> ShaderMaterial:
	if _fire_mat == null:
		var sh := Shader.new()
		sh.code = FIRE_SHADER
		_fire_mat = ShaderMaterial.new()
		_fire_mat.shader = sh
		_fire_mat.set_shader_parameter("fiber", Look.fiber_normal(true))
	return _fire_mat


## しずく形（幅 1・高さ 1、根もとが原点、+Z 向きの平たい面）。layer 0 赤 1.0 / 1 橙 0.75 / 2 黄 0.5 の大きさ。
## 形の番号ごとに、揺れ（ふくらみの片寄りと先の曲がり）を変える
static func _drop(layer: int, shape: int) -> ArrayMesh:
	var key := Vector2i(layer, shape)
	if _drops.has(key):
		return _drops[key]
	var sc: float = [1.0, 0.75, 0.5][layer]
	var seed := float(shape) * 2.1 + layer * 0.7
	var pts := PackedVector3Array()
	var n := 20
	for i in n:
		var t := TAU * i / n
		var x: float = 0.5 * sc * sin(t) * (1.0 - 0.15 * cos(t))
		var z: float = sc * pow(0.5 - 0.5 * cos(t), 1.2)
		x += 0.07 * sin(z * 6.0 + seed) * z + 0.05 * (shape - 1) * z * z   # 先が左右へ流れる
		pts.append(Vector3(x, z, 0.0))
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := Vector3(0.0, 0.42 * sc, 0.0)
	for i in n:
		for p in [c, pts[i], pts[(i + 1) % n]]:
			v.append(p)
			nm.append(Vector3(0, 0, 1))
			uv.append(Vector2(p.x + 0.5, 1.0 - p.y))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_drops[key] = m
	return m


# ---------------------------------------------------------------- 素材

static func _mat(role: String) -> Material:
	if _mats.has(role):
		return _mats[role]
	var m: StandardMaterial3D
	match role:
		"iron": m = Look.felt(Color(0.13, 0.10, 0.09), 2.0)          # 鉄の代わりのこげ茶のフェルト
		"brass": m = Look.felt(Color(0.72, 0.52, 0.22), 2.0)         # 真鍮色のフェルト
		"handle": m = Look.wood(Color(0.33, 0.21, 0.12))
		"frame": m = Look.wood(Color(0.27, 0.17, 0.10))
		"dish": m = Look.wood(Color(0.46, 0.31, 0.19))
		"hemp": m = Look.felt(Color(0.55, 0.43, 0.29), 4.0)          # 麻の布
		"cloth": m = Look.felt(Color(0.62, 0.30, 0.22), 4.0)         # 赤茶の布
		"char": m = Look.felt(Color(0.08, 0.07, 0.07), 3.0)          # 焦げ・芯
		"wax": m = Look.felt(Color(0.93, 0.87, 0.74), 3.0)           # ろう（クリームのフェルト）
		"band": m = Look.paper(Color(0.70, 0.30, 0.24))              # ろうそくに巻いた紙の帯
		"film":                                                        # 透明なフィルム
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.95, 0.90, 0.80, 0.22)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.2
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[role] = m
	return m


# ---------------------------------------------------------------- 形の部品（同じ大きさの形は使い回す）

static var _shapes := {}


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 小さな物の影は描かない（軽く）
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var key := "box%s" % size
	if not _shapes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_shapes[key] = b
	return _mesh(parent, _shapes[key], at, mat)


func _cyl(parent: Node3D, top: float, bottom: float, h: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var key := "cyl%.3f_%.3f_%.3f" % [top, bottom, h]
	if not _shapes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = 12
		c.rings = 1
		_shapes[key] = c
	return _mesh(parent, _shapes[key], at, mat)


func _ring(parent: Node3D, r: float, t: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var key := "ring%.3f_%.3f" % [r, t]
	if not _shapes.has(key):
		var c := TorusMesh.new()
		c.inner_radius = r - t
		c.outer_radius = r + t
		c.rings = 16
		c.ring_segments = 6
		_shapes[key] = c
	return _mesh(parent, _shapes[key], at, mat)
