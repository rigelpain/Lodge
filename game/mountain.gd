extends "res://mountain_deco.gd"
## 大きな山（2026-10-30 に作り、2026-11-03 に形を直した）。ロッジの南に、高台から高さ約 70 m。
## 2026-11-03 代表「大きい山のほうが変に凹ませてあってコースっぽく見えるのが嫌だ。あと大きな段差があるが、押して登る前提なのだから
## そんな横長に段差作ったら迂回が大変でしょう。ジャンプ台になる段差は幅小さく作ってほしい。あとジャンプちゃんとできるように射出する角度を作ってほしい。」
## そこで、溝のコースと横長の段をやめ、雪の積もった自然な山にした:
##   - 地肌は、北（ロッジの側）へ長く南へ短い楕円の山。上ほど急で、麓へなだらかに下りる
##   - 東の尾根: 頂上から北北東へ曲がって麓まで下りる、幅の広い背。背の上の坂は RIDGE_MAX より急にならない（ソリを押して登る道）
##   - 西の沢・西の尾根・東の小さな沢、肩とこぶ、ゆるい揺らぎ。滑る速さの出る所・ゆるい所は、この起伏で作る
##   - 麓は広く浅い窪地（ソリがここで止まる）。土手は作らない
##   - ジャンプ台は地形とは別の、雪を固めた幅の狭い台（KICKERS）。斜面がその先で急になる所に置き、手前は上を向いた踏み切り、先は下りの斜面に着地する
## 地面の高さは静的な関数（lift）で、main.gd の ground() が足す（当たり判定と見た目の雪面の両方に効く）。
## 形は 2 m おきの表に一度だけ焼いて、あいだは直線でつなぐ（起伏はいちばん細かくても 14 m の波なので、2 m おきで足りる。焼く時間を短く）。
## このノードは、ジャンプ台・尾根の道しるべ・手すり・木と岩を置く

## 山の地肌: 頂上 (SX, SZ)、高さ H。楕円の半径（東西・北・南）。POW が大きいほど上が急で麓がなだらか。CAP は頂上の丸み
const SX := -5.0
const SZ := 492.0
const H := 70.0
const AX := 120.0
const AZN := 270.0
const AZS := 125.0
const POW := 1.15
const CAP := 0.06

## 東の尾根（押して登る背）の折れ線。頂上から麓へ
const RIDGE := [Vector2(-3, 486), Vector2(8, 462), Vector2(22, 428), Vector2(32, 385), Vector2(34, 340),
		Vector2(29, 298), Vector2(22, 262), Vector2(17, 236)]
const RIDGE_MAX := 15.0      # 背の上の坂の上限 (°)
const RIDGE_CREST := 6.0     # 背の平らな幅の半分 (m)
const RIDGE_SIDE := 20.0     # 背から脇の地肌へ下りる広がり (m)
const RIDGE_LIFT := 1.0      # 背は地肌よりこれだけ高い (m)

## 沢（−）と小さな尾根（＋）: [折れ線, 高さ (m), 広がり σ (m)]
const LINES := [
	[[Vector2(-26, 455), Vector2(-38, 412), Vector2(-46, 368), Vector2(-42, 322), Vector2(-33, 282), Vector2(-26, 245)], -3.0, 12.0],   # 西の沢
	[[Vector2(-46, 472), Vector2(-66, 425), Vector2(-78, 365), Vector2(-82, 300)], 2.0, 14.0],   # 西の尾根
	[[Vector2(52, 430), Vector2(58, 380), Vector2(60, 330)], -2.0, 9.0],   # 東の小さな沢（尾根の向こう）
]
## 肩とこぶ: [x, z, 高さ, 東西の σ, 南北の σ]
const KNOLLS := [
	[-12.0, 372.0, 3.6, 24.0, 15.0],   # 中腹の肩（手前は 7〜8°: 大のソリに 1 人でも止まりきらずにゆっくり流れる）
	[-8.0, 440.0, 2.4, 15.0, 9.0],     # 上の肩
	[-16.0, 302.0, 3.0, 15.0, 10.0],   # 下のこぶ
	[-58.0, 342.0, 2.6, 13.0, 10.0],   # 西のこぶ
]
## ゆるい揺らぎ: [振れ幅 (m), 波の長さ (m), 向き (°), 位相]
const WAVES := [[0.8, 52.0, 20.0, 0.3], [0.6, 38.0, 105.0, 1.7], [0.28, 24.0, 62.0, 2.9], [0.12, 14.0, 150.0, 0.8]]
## 麓の窪地: まんなかの z、深さ、東西・南北の σ
const DIP_Z := 205.0
const DIP_D := 1.0
const DIP_SX := 45.0
const DIP_SZ := 16.0

## ジャンプ台: [踏み切りの縁の x, z, 飛び出す向きの角度（水平から上へ, °）]。向きは、その場の斜面の下り
const KICKERS := [
	[-8.0, 436.0, 8.0],    # 上の肩の先
	[-12.0, 362.0, 7.0],   # 中腹の肩の先
	[-16.0, 298.0, 7.0],   # 下のこぶの先
	[-58.0, 335.0, 7.0],   # 西のこぶの先
]

const FOOT_Z := 182.0        # ここから南が大きな山（窪地を含む）
const BOTTOM_Z := 225.0      # 北の斜面の下の端（ここから北は窪地と高台）
const START := Vector2(-6.0, 482.0)   # 頂上の北の端（ソリを押し出して滑り出す所）
const REST := Vector2(-12.0, 372.0)   # 中腹の肩（一息つく所）
## 北の斜面の帯の名前と、その帯の下の端の z（上から。確かめの台本が速さを帯ごとに数える用）
const ZONES := [["頂上", 470.0], ["上の斜面", 410.0], ["中腹の肩", 345.0], ["下の斜面", 270.0], ["麓", BOTTOM_Z]]
const FACE_X := -14.0        # 北の斜面（滑る所）のまんなかの x
const FACE_W := 34.0         # 北の斜面の、ボタンを置く広がりの半分 (m)
const RAIL_X := -6.0         # 手すりの x（下の斜面のまんなか寄り。10° のまっすぐに近い雪面で、横に傾いていない。棒が雪に埋もれない）
const RAIL_Z := Vector2(258.0, 241.0)   # 手すりの上の端と下の端の z

const GX0 := -128.0          # 焼いた表の範囲
const GZ0 := 150.0
const GSTEP := 2.0           # 焼いた表の間隔 (m)
const GNX := 129
const GNZ := 246

static var _grid := PackedFloat32Array()   # 焼いた高さ（高台から）
static var _ridge := PackedFloat32Array()  # 背の上の高さ。背に沿って 1 m おき
static var _ridge_len := 0.0
static var _kick := []                     # ジャンプ台ごとの形（kicker()）
static var top_z := SZ                     # 頂上の z
static var top_h := H                      # 頂上の高さ（高台から）
static var _line_box: Array[Rect2] = []    # 沢・尾根の線ごとの、効く範囲（σ の 4 倍まで）


static func _smooth(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


## 折れ線までの距離と、線に沿った位置 (m) と、線の長さ
static func _seg(p: Vector2, pts: Array) -> Vector3:
	var best := 1e9
	var along := 0.0
	var acc := 0.0
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var l := ab.length()
		var t := clampf((p - a).dot(ab) / (l * l), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			along = acc + t * l
		acc += l
	return Vector3(best, along, acc)


## 山の地肌（楕円の山）の高さと、楕円の上の位置 r（頂上で 0、麓の縁で 1）
static func _body(x: float, z: float) -> Vector2:
	var u := z - SZ
	var az := AZN if u < 0.0 else AZS
	var r := sqrt(pow((x - SX) / AX, 2.0) + pow(u / az, 2.0))
	var re := (sqrt(r * r + CAP * CAP) - CAP) / (sqrt(1.0 + CAP * CAP) - CAP)
	return Vector2(H * pow(clampf(1.0 - re, 0.0, 1.0), POW), r)


## 沢・尾根・肩・こぶ・揺らぎ。calm が 1 の所では揺らぎを消す（ジャンプ台のまわり）
static func _features(x: float, z: float, calm := 0.0) -> float:
	var p := Vector2(x, z)
	var add := 0.0
	for li in LINES.size():
		var ln: Array = LINES[li]
		if not _line_box[li].has_point(p):   # 遠い線は飛ばす（焼く時間を短く）
			continue
		var s := _seg(p, ln[0])
		var t := s.y / s.z
		var amp: float = ln[1]
		var sig: float = ln[2]
		add += amp * exp(-s.x * s.x / (2.0 * sig * sig)) * _smooth(0.0, 0.15, t) * (1.0 - _smooth(0.85, 1.0, t))
	for k in KNOLLS:
		if absf(x - k[0]) > k[3] * 4.0 or absf(z - k[1]) > k[4] * 4.0:
			continue
		add += k[2] * exp(-(pow(x - k[0], 2.0) / (2.0 * k[3] * k[3]) + pow(z - k[1], 2.0) / (2.0 * k[4] * k[4])))
	var waves := 0.0
	for w in WAVES:
		var th := deg_to_rad(w[2])
		waves += w[0] * sin(TAU / w[1] * (x * cos(th) + z * sin(th)) + w[3])
	return add + waves * (1.0 - calm)


## ジャンプ台のまわりで 1（揺らぎを消して、台がまっすぐな雪面に載るように）
static func _calm(x: float, z: float) -> float:
	var c := 0.0
	for k in KICKERS:
		var d := Vector2(x - k[0], z - k[1]).length()
		c = maxf(c, 1.0 - _smooth(18.0, 34.0, d))
	return c


## 焼く前の高さ（高台から）
static func _raw(x: float, z: float) -> float:
	var dip := -DIP_D * exp(-(pow(x - SX, 2.0) / (2.0 * DIP_SX * DIP_SX) + pow(z - DIP_Z, 2.0) / (2.0 * DIP_SZ * DIP_SZ)))
	var b := _body(x, z)
	if b.y >= 1.0:
		return dip
	var w := _smooth(0.02, 0.12, b.y) * (1.0 - _smooth(0.80, 0.97, b.y))
	var s := _seg(Vector2(x, z), RIDGE)
	var near := 1.0 - _smooth(RIDGE_CREST, RIDGE_CREST + RIDGE_SIDE * 1.5, s.x)
	var h := b.x + _features(x, z, _calm(x, z)) * w * (1.0 - 0.85 * near)
	# 背: 平らな幅の外は、放物線で脇へ下りる。地肌となめらかに大きいほうを取る（2 m でならす）
	var rh := _ridge_at(s.y)
	var crest := rh - (0.0 if s.x < RIDGE_CREST else pow((s.x - RIDGE_CREST) / RIDGE_SIDE, 2.0) * RIDGE_SIDE * 0.5)
	var hd := clampf(0.5 + 0.5 * (crest - h) / 2.0, 0.0, 1.0)
	h = lerpf(h, crest, hd) + 2.0 * hd * (1.0 - hd)
	return maxf(h, 0.0) + dip


static func _ridge_at(s: float) -> float:
	var f := clampf(s, 0.0, _ridge_len)
	var i := mini(int(f), _ridge.size() - 2)
	return lerpf(_ridge[i], _ridge[i + 1], f - i)


static func _build() -> void:
	if not _grid.is_empty():
		return
	# 背の高さ: 地肌より RIDGE_LIFT 高く、上から下へ坂が RIDGE_MAX を超える所は持ち上げる。7 m でならし、下の端の 18 m で 0 へ
	_line_box.clear()
	for ln in LINES:
		var box := Rect2(ln[0][0], Vector2.ZERO)
		for p in ln[0]:
			box = box.expand(p)
		_line_box.append(box.grow(ln[2] * 4.0))
	var len := _seg(Vector2.ZERO, RIDGE).z
	var n := int(len) + 1
	var raw := PackedFloat32Array()
	raw.resize(n)
	var g := tan(deg_to_rad(RIDGE_MAX))
	var acc := 0.0
	var k := 0
	for i in n:
		var s := float(i)
		while k < RIDGE.size() - 2 and s > acc + (RIDGE[k + 1] - RIDGE[k]).length():
			acc += (RIDGE[k + 1] - RIDGE[k]).length()
			k += 1
		var a: Vector2 = RIDGE[k]
		var b: Vector2 = RIDGE[k + 1]
		var p := a.lerp(b, clampf((s - acc) / (b - a).length(), 0.0, 1.0))
		raw[i] = _body(p.x, p.y).x + RIDGE_LIFT
		if i == 0:
			raw[i] = maxf(raw[i], H)
		else:
			raw[i] = maxf(raw[i], raw[i - 1] - g)
	_ridge.resize(n)
	for i in n:
		var sum := 0.0
		for d in range(-7, 8):
			sum += raw[clampi(i + d, 0, n - 1)]
		_ridge[i] = sum / 15.0 * _smooth(0.0, 18.0, len - i)
	_ridge_len = len - 1.0
	# 表に焼く
	_grid.resize(GNX * GNZ)
	for j in GNZ:
		for i in GNX:
			_grid[j * GNX + i] = _raw(GX0 + i * GSTEP, GZ0 + j * GSTEP)
	# ジャンプ台の形
	_kick.clear()
	for kk in KICKERS:
		_kick.append(_kicker_shape(kk[0], kk[1], kk[2]))


## 地面に足す高さ（高台から）。山の外では 0
static func lift(x: float, z: float) -> float:
	if z < GZ0:
		return 0.0
	_build()
	var fx := clampf((x - GX0) / GSTEP, 0.0, GNX - 1.001)
	var fz := clampf((z - GZ0) / GSTEP, 0.0, GNZ - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(_grid[j * GNX + i], _grid[j * GNX + i + 1], tx)
	var b := lerpf(_grid[(j + 1) * GNX + i], _grid[(j + 1) * GNX + i + 1], tx)
	return lerpf(a, b, tz)


## ジャンプ台の形: 縁の点 lip、下りの向き f（水平の単位）、縁での雪面の下り tan（正で下り）、縁の高さ（雪面から）。
## 踏み切りの坂は e(s) = 縁の高さ × (s / KICK_L)²（s は坂の出だしからの水平の長さ）。縁で、坂の向きが水平から launch° 上を向く
static func _kicker_shape(x: float, z: float, launch: float) -> Dictionary:
	var e := 1.0
	var gx := (_raw(x + e, z) - _raw(x - e, z)) / (2.0 * e)
	var gz := (_raw(x, z + e) - _raw(x, z - e)) / (2.0 * e)
	var f := Vector2(-gx, -gz).normalized()
	# 縁での雪面の下り: 縁の手前 2 m の平均
	var fall := (_raw(x - f.x * 2.0, z - f.y * 2.0) - _raw(x, z)) / 2.0
	var hl := KICK_L * (tan(deg_to_rad(launch)) + fall) * 0.5
	return {"lip": Vector2(x, z), "f": f, "fall": fall, "hl": hl, "launch": launch}


## ジャンプ台 i の形（_kicker_shape の辞書）
static func kicker(i: int) -> Dictionary:
	_build()
	return _kick[i]


## ジャンプ台の手前と先（木を置かない所）。margin だけ広げて測れる
static func on_kicker_lane(x: float, z: float, margin := 0.0) -> bool:
	_build()
	for k in _kick:
		var d := Vector2(x, z) - (k.lip as Vector2)
		var f: Vector2 = k.f
		var along := d.dot(f)
		var side := absf(d.cross(f))
		if along > -KICK_L - KICK_CLEAR * 0.5 - margin and along < KICK_CLEAR + margin and side < KICK_W * 0.5 + 4.0 + margin:
			return true
	return false


## 東の尾根の背の上で 1（雪の色を踏み固めた色にする用。押して登る道の目じるし）
static func path_weight(x: float, z: float) -> float:
	if z < BOTTOM_Z or z > SZ:
		return 0.0
	_build()
	var s := _seg(Vector2(x, z), RIDGE)
	if s.y > _ridge_len - 4.0:
		return 0.0
	return 1.0 - _smooth(1.6, 2.6, s.x)


## 東の尾根の背の上（木を置かない用）
static func on_ridge(x: float, z: float, margin := 0.0) -> bool:
	if z < BOTTOM_Z - 10.0 or z > SZ + 4.0:
		return false
	return _seg(Vector2(x, z), RIDGE).x < RIDGE_CREST + margin


## z の帯の名前（ZONES。北の斜面より北は「窪地」、頂上の南は「裏」）
static func zone(z: float) -> String:
	if z > top_z:
		return "裏"
	for zn in ZONES:
		if z >= zn[1]:
			return zn[0]
	return "窪地"


## 東の尾根を押して登るときの向き（水平の単位）: 背に沿って上へ、背のまんなかへ寄せる
static func ridge_guide(p: Vector2) -> Vector2:
	_build()
	var s := _seg(p, RIDGE)
	var at := _ridge_point(maxf(s.y - 8.0, 0.0))   # 8 m 上の背の点へ向かう
	return (at - p).normalized()


## 背に沿った位置 s (m、頂上から) の点
static func _ridge_point(s: float) -> Vector2:
	var acc := 0.0
	for k in RIDGE.size() - 1:
		var a: Vector2 = RIDGE[k]
		var b: Vector2 = RIDGE[k + 1]
		var l := a.distance_to(b)
		if s <= acc + l:
			return a.lerp(b, (s - acc) / l)
		acc += l
	return RIDGE[RIDGE.size() - 1]


## 北の斜面（滑る所）の上か（ボタンを置く用）
static func on_face(x: float, z: float) -> bool:
	return absf(x - FACE_X) < FACE_W and z > BOTTOM_Z + 4.0 and z < top_z - 4.0


# ---------------------------------------------------------------- 飾り（ジャンプ台と手すりの作りは mountain_deco.gd）

func _ready() -> void:
	_build()
	for i in KICKERS.size():
		_make_kicker(i, kicker(i))
	_markers()
	_rail(Vector2(RAIL_X, RAIL_Z.x), Vector2(RAIL_X, RAIL_Z.y))
	_trees()


## 東の尾根の道しるべ: 背の脇に、藍の小さな旗を 36 m おきに左右かわるがわる（押して登る人が、なだらかな背を見つけられるように）
func _markers() -> void:
	var i := 0
	var s := 20.0
	while s < _ridge_len - 10.0:
		var a := _ridge_point(s)
		var dir := (_ridge_point(s + 1.0) - a).normalized()
		var p := a + Vector2(-dir.y, dir.x) * (3.2 if i % 2 == 0 else -3.2)
		var flag := _put("res://props/flag_navy.glb", p.x, p.y, atan2(dir.x, dir.y))
		flag.scale = Vector3.ONE * 0.75
		i += 1
		s += 36.0


## 山の地肌の木: 沢の脇と山の脇に多く、北の斜面（滑る所）のまんなかはまばらに。尾根の背・ジャンプ台の手前と先・手すりは空ける。
## 急すぎる所には立てず、代わりに大きな岩を置く（遠くから山の形が読めるように）
func _trees() -> void:
	const TREES := ["res://props/tree_tall.glb", "res://props/tree_zigzag.glb", "res://props/tree_round.glb",
		"res://props/tree_little.glb"]
	const ROCKS := ["res://props/rock_a.glb", "res://props/rock_b.glb", "res://props/rock_c.glb"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var trees := 0
	var rocks := 0
	for k in 4000:
		if trees >= 170 and rocks >= 24:
			break
		var x := rng.randf_range(-118.0, 112.0)
		var z := rng.randf_range(BOTTOM_Z - 6.0, top_z + 110.0)
		var keep := rng.randf()
		var hgt := rng.randf_range(4.0, 8.0)
		var yaw := rng.randf() * TAU
		if _body(x, z).y > 0.97:
			continue
		if on_ridge(x, z, 3.0) or on_kicker_lane(x, z) or (absf(x - RAIL_X) < 6.0 and z > RAIL_Z.y - 8.0 and z < RAIL_Z.x + 6.0):
			continue
		# 北の斜面のまんなかは、開けた雪原（木は 1 割）
		if absf(x - FACE_X) < FACE_W * 0.8 and z < top_z and keep > 0.1:
			continue
		var gx := _y(x + 1.0, z) - _y(x - 1.0, z)
		var gz := _y(x, z + 1.0) - _y(x, z - 1.0)
		var steep := Vector2(gx, gz).length() * 0.5
		if steep > 0.85:   # 40° より急: 岩
			if rocks >= 24:
				continue
			# 岩は斜面に沿わせて寝かせ、雪へ少し沈める（大きいので、まっすぐ立てると下りの側が浮く）
			var rock := Props.make(ROCKS[k % ROCKS.size()])
			var sc := rng.randf_range(4.0, 8.0)
			var up: Vector3 = world.ground_normal(x, z, 0.6 * sc)
			rock.basis = Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
			rock.position = Vector3(x, _y(x, z) + world.snow_lift(x, z) - 0.12 * sc, z)
			add_child(rock)
			world.settle(rock)
			rocks += 1
			continue
		if trees >= 170:
			continue
		var tree := _put(TREES[k % TREES.size()], x, z, yaw, 0.35 * hgt / 6.0)
		tree.scale = Vector3.ONE * hgt / 6.0
		trees += 1
