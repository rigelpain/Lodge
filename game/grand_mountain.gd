extends "res://mountain_deco.gd"
## 大山（おおやま。2026-11-04）。ロッジの東に立つ、いちばん大きな山。高さも広さも大きな山（mountain.gd）の倍。
## 2026-11-04 代表「今最も大きい山の倍大きい山を作ってほしい。斜面がなだらか（ほぼ平坦）になる段を一段、2/3ほど登ったところに作る感じで。」
## 置き場所は代表が地図の A（東）を選んだ。design/grand-mountain/ の絵。
##   - 地肌は、西（ロッジの側）へ長く東へ短い楕円の山。西の斜面を滑る
##   - 段: 西の斜面の、麓からの高さの 2/3 に、ほぼ平らな広い段が 1 つ（BENCH_R・BENCH_Y）。両脇はなめらかに斜面へ戻る
##   - 南の尾根: 頂上から段を通って麓まで下りる、幅の広い背。背の上の坂は RIDGE_MAX より急にならない（ソリを押して登る道）
##   - 沢・尾根・こぶ・ゆるい揺らぎ・麓の窪地・ジャンプ台・手すり・木と岩は、大きな山と同じ作りで大きさを倍に
## 高さは静的な関数（lift）で、main.gd の ground() が足す（当たり判定と見た目の雪面の両方に効く）。みんなの画面で同じ形になる。
## 形は 4 m おきの表に一度だけ焼く（起伏はいちばん細かくても 28 m の波なので足りる）。
## 見た目と当たりは、地面の広さが大きいので 2 m おき（main.gd の _make_grand_ground）

const Mountain := preload("res://mountain.gd")

## 山の地肌: 頂上 (SX, SZ)、高さ H。楕円の半径（西・東・南北）。POW は東の裏と脇の形、CAP は頂上の丸み
const SX := 710.0
const SZ := 32.0
const H := 141.0
const AXW := 540.0
const AXE := 250.0
const AZ := 240.0
const POW := 1.15
const CAP := 0.06

## 段: 西の斜面の、楕円の上の位置 r（頂上で 0、麓で 1）で BENCH_R.x 〜 BENCH_R.y。高さ（高台から）は BENCH_Y.x（奥）〜 BENCH_Y.y（縁）
const BENCH_R := Vector2(0.31, 0.45)     # 西へまっすぐ下りると、頂上から 167 〜 243 m（奥行き 76 m）
const BENCH_Y := Vector2(96.5, 94.0)     # 高さの 2/3（94 m）。76 m で 2.5 m 下がる: 1.9°
const BENCH_SOFT := 0.016                # 段の角の丸み（r。西へ ±9 m）
const POW_LOW := 1.05                    # 段の下の斜面の形。1 に近いほどまっすぐ
const BENCH_SIDE := Vector2(0.0, 0.6)  # 頂上から見た向きで、段が消える所〜全部ある所（真西を 1、真南北を 0 とする cos）

## 南の尾根（押して登る背）の折れ線。頂上から麓へ
## 上は頂上から段の奥へほぼまっすぐ、段の上を南へ渡り、段の下は斜面を斜めに横切って麓へ（まっすぐだと 15° に収まらない）
const RIDGE := [Vector2(698, 36), Vector2(650, 44), Vector2(595, 54), Vector2(545, 62), Vector2(520, 68), Vector2(500, 82),
		Vector2(480, 96), Vector2(450, 100), Vector2(380, 80), Vector2(305, 42), Vector2(232, 96), Vector2(165, 52), Vector2(146, 52)]
const RIDGE_MAX := 15.0      # 背の上の坂の上限 (°)
const RIDGE_CREST := 6.0     # 背の平らな幅の半分 (m)
const RIDGE_SIDE := 40.0     # 背から脇の地肌へ下りる広がり (m)
const RIDGE_LIFT := 1.0      # 背は地肌よりこれだけ高い (m)
const RIDGE_FAR := 90.0      # 背からこれより遠い所は、背の形が届かない (m)

## 沢（−）と小さな尾根（＋）: [折れ線, 高さ (m), 広がり σ (m)]
const LINES := [
	[[Vector2(636, -10), Vector2(550, -34), Vector2(462, -50), Vector2(370, -42), Vector2(290, -24), Vector2(216, -10)], -6.0, 24.0],   # 北の沢
	[[Vector2(670, -50), Vector2(576, -90), Vector2(456, -114), Vector2(326, -122)], 4.0, 28.0],   # 北の尾根
	[[Vector2(586, 146), Vector2(486, 158), Vector2(386, 162)], -4.0, 18.0],   # 南の小さな沢（尾根の向こう）
]
## 肩とこぶ: [x, z, 高さ, 東西の σ, 南北の σ]
const KNOLLS := [
	[615.0, 24.0, 4.8, 18.0, 30.0],    # 上の肩
	[330.0, 16.0, 6.0, 20.0, 30.0],    # 下のこぶ
	[390.0, -68.0, 5.2, 20.0, 26.0],   # 北のこぶ
	[252.0, -30.0, 4.0, 18.0, 26.0],   # 麓の前のこぶ
]
## ゆるい揺らぎ: [振れ幅 (m), 波の長さ (m), 向き (°), 位相]
const WAVES := [[1.6, 104.0, 70.0, 0.9], [1.2, 76.0, 155.0, 2.3], [0.56, 48.0, 112.0, 0.4], [0.24, 28.0, 20.0, 1.2]]
## 麓の窪地: まんなかの x、深さ、東西・南北の σ。ソリはここで止まる。継ぎ目（GX0）の手前で消す
const DIP_X := 160.0
const DIP_D := 1.2
const DIP_SX := 22.0
const DIP_SZ := 90.0

## ジャンプ台: [踏み切りの縁の x, z, 飛び出す向きの角度（水平から上へ, °）]
const KICKERS := [
	[607.0, 24.0, 8.0],    # 上の肩の先
	[458.0, 2.0, 7.0],     # 段の縁の先（まっすぐ下りる筋から外す。段で止まって動き出したソリが縁の台で止まらないように）
	[322.0, 16.0, 7.0],    # 下のこぶの先
	[380.0, -68.0, 7.0],   # 北のこぶの先
	[244.0, -30.0, 7.0],   # 麓の前のこぶの先
]

const FOOT_X := 128.0        # ここから東が大山（窪地を含む）。地面の継ぎ目で、雪面は平らな高台の高さ
const BOTTOM_X := 170.0      # 西の斜面の下の端
const START := Vector2(690.0, 32.0)      # 頂上の西の端（ソリを押し出して滑り出す所）
const REST := Vector2(505.0, 32.0)       # 段のまんなか（一息つく所）
## 西の斜面の帯の名前と、その帯の下の端の x（上から。確かめの台本が速さを帯ごとに数える用）
const ZONES := [["頂上", 680.0], ["上の斜面", 543.0], ["段", 455.0], ["下の斜面", 240.0], ["麓", BOTTOM_X]]
const FACE_Z := 22.0         # 西の斜面（滑る所）のまんなかの z
const FACE_W := 68.0         # 西の斜面の、ボタンを置く広がりの半分 (m)
const RAIL_TOP := Vector2(232.0, 22.0)      # 手すりの上の端
const RAIL_BOTTOM := Vector2(215.0, 22.0)   # 手すりの下の端

## 地面の広さ（main.gd の _make_grand_ground と同じ）
const GX0 := 128.0
const GZ0 := -224.0
const GX1 := 1024.0
const GZ1 := 288.0
const GSTEP := 4.0           # 焼いた表の間隔 (m)
const GNX := 225
const GNZ := 129

static var _grid := PackedFloat32Array()      # 焼いた高さ（高台から）
static var _near := PackedFloat32Array()      # 背までの距離（雪の色を塗る所を早く探す用）
static var _prof := PackedFloat32Array()      # 段のある斜面の形（r で引く）
static var _pts: Array = []                   # 角を丸めた背の折れ線（RIDGE から）。角が尖ると、内側で背の高さが飛んで小さな崖になる
static var _ridge := PackedFloat32Array()     # 背の上の高さ。背に沿って 1 m おき
static var _ridge_len := 0.0
static var _kick := []                        # ジャンプ台ごとの形
static var _line_box: Array[Rect2] = []       # 沢・尾根の線ごとの、効く範囲（σ の 4 倍まで）
const PROF_N := 1024


## 段のある斜面の形の、丸める前（r は楕円の上の位置）
static func _prof_raw(r: float) -> float:
	if r < BENCH_R.x:
		var t := r / BENCH_R.x
		var c := 0.19   # 頂上の丸み（CAP と同じ長さ）
		var re := (sqrt(t * t + c * c) - c) / (sqrt(1.0 + c * c) - c)
		return lerpf(BENCH_Y.x, H, 1.0 - re)
	if r < BENCH_R.y:
		return lerpf(BENCH_Y.x, BENCH_Y.y, (r - BENCH_R.x) / (BENCH_R.y - BENCH_R.x))
	return BENCH_Y.y * pow(maxf(1.0 - r, 0.0) / (1.0 - BENCH_R.y), POW_LOW)


static func _prof_at(r: float) -> float:
	var f := clampf(r, 0.0, 1.0) * (PROF_N - 1)
	var i := mini(int(f), PROF_N - 2)
	return lerpf(_prof[i], _prof[i + 1], f - i)


## 山の地肌の高さと、楕円の上の位置 r（頂上で 0、麓の縁で 1）と、段の濃さ（0 〜 1。向きで見て段のある斜面か）
static func _body(x: float, z: float) -> Vector3:
	var dx := x - SX
	var dz := z - SZ
	var ax := AXW if dx < 0.0 else AXE
	var r := sqrt(dx * dx / (ax * ax) + dz * dz / (AZ * AZ))
	if r >= 1.0:
		return Vector3(0.0, r, 0.0)
	var re := (sqrt(r * r + CAP * CAP) - CAP) / (sqrt(1.0 + CAP * CAP) - CAP)
	var plain := H * pow(1.0 - re, POW)
	if dx >= 0.0 or r < 0.001:
		return Vector3(plain, r, 0.0)
	var b := smoothstep(BENCH_SIDE.x, BENCH_SIDE.y, -dx / AXW / r)
	return Vector3(lerpf(plain, _prof_at(r), b), r, b)


## 段の上で 1（起伏を消して平らに保つ）
static func _bench_w(b: Vector3) -> float:
	return b.z * smoothstep(BENCH_R.x - 0.10, BENCH_R.x, b.y) * (1.0 - smoothstep(BENCH_R.y, BENCH_R.y + 0.12, b.y))


## 沢・尾根・肩・こぶ・揺らぎ。calm が 1 の所では揺らぎを消す（ジャンプ台のまわり）
static func _features(x: float, z: float, calm: float) -> float:
	var p := Vector2(x, z)
	var add := 0.0
	for li in LINES.size():
		var ln: Array = LINES[li]
		if not _line_box[li].has_point(p):   # 遠い線は飛ばす（焼く時間を短く）
			continue
		var s: Vector3 = Mountain._seg(p, ln[0])
		var t := s.y / s.z
		var amp: float = ln[1]
		var sig: float = ln[2]
		add += amp * exp(-s.x * s.x / (2.0 * sig * sig)) * smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.85, 1.0, t))
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
		c = maxf(c, 1.0 - smoothstep(18.0, 34.0, d))
	return c


## 背までの距離と、背に沿った位置と、背の長さ。遠い所は角を丸める前の線で済ませる（焼く時間を短く。遠ければ位置は使わない）
static func _seg_fast(x: float, z: float) -> Vector3:
	var rough: Vector3 = Mountain._seg(Vector2(x, z), RIDGE)
	return rough if rough.x > RIDGE_FAR + 6.0 else Mountain._seg(Vector2(x, z), _pts)


## 焼く前の高さ（高台から）。seg は背までの距離（もう測ってあれば）
static func _raw(x: float, z: float, seg := Vector3.INF) -> float:
	var dip := -DIP_D * exp(-(pow(x - DIP_X, 2.0) / (2.0 * DIP_SX * DIP_SX) + pow(z - SZ, 2.0) / (2.0 * DIP_SZ * DIP_SZ))) * smoothstep(GX0 + 2.0, GX0 + 20.0, x)
	var b := _body(x, z)
	var s: Vector3 = _seg_fast(x, z) if seg == Vector3.INF else seg
	if b.y >= 1.0 and s.x > 60.0:   # 尾根の下の端は楕円の少し外まで出る
		return dip
	var w := smoothstep(0.02, 0.12, b.y) * (1.0 - smoothstep(0.80, 0.97, b.y)) * (1.0 - _bench_w(b))
	if s.x > RIDGE_FAR:   # 背は遠い
		return maxf(b.x + _features(x, z, _calm(x, z)) * w, 0.0) + dip
	var near := 1.0 - smoothstep(RIDGE_CREST, RIDGE_CREST + RIDGE_SIDE * 1.5, s.x)
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
	# 段のある斜面の形: 折れ線を BENCH_SOFT の幅でならす
	var tmp := PackedFloat32Array()
	tmp.resize(PROF_N)
	for i in PROF_N:
		tmp[i] = _prof_raw(float(i) / (PROF_N - 1))
	var soft := int(BENCH_SOFT * PROF_N)
	_prof.resize(PROF_N)
	for i in PROF_N:
		var sum := 0.0
		for d in range(-soft, soft + 1):
			sum += tmp[clampi(i + d, 0, PROF_N - 1)]
		_prof[i] = sum / (soft * 2 + 1)
	_line_box.clear()
	for ln in LINES:
		var box := Rect2(ln[0][0], Vector2.ZERO)
		for p in ln[0]:
			box = box.expand(p)
		_line_box.append(box.grow(ln[2] * 4.0))
	# 背の角を丸める（2 回切る）
	_pts = RIDGE.duplicate()
	for pass_i in 2:
		var cut := [_pts[0]]
		for i in _pts.size() - 1:
			var a: Vector2 = _pts[i]
			var b: Vector2 = _pts[i + 1]
			if i > 0:
				cut.append(a.lerp(b, 0.25))
			if i < _pts.size() - 2:
				cut.append(a.lerp(b, 0.75))
		cut.append(_pts[_pts.size() - 1])
		_pts = cut
	# 背の高さ: 地肌より RIDGE_LIFT 高く、上から下へ坂が RIDGE_MAX を超える所は持ち上げる。7 m でならし、下の端の 18 m で 0 へ
	var len: float = Mountain._seg(Vector2.ZERO, _pts).z
	var n := int(len) + 1
	var raw := PackedFloat32Array()
	raw.resize(n)
	var g := tan(deg_to_rad(RIDGE_MAX))
	for i in n:
		var p := _ridge_point(float(i))
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
		_ridge[i] = sum / 15.0 * smoothstep(0.0, 18.0, len - i)
	_ridge_len = len - 1.0
	# 表に焼く
	_near.resize(GNX * GNZ)
	var cells := PackedFloat32Array()
	cells.resize(GNX * GNZ)
	for j in GNZ:
		var z := GZ0 + j * GSTEP
		for i in GNX:
			var x := GX0 + i * GSTEP
			var seg := _seg_fast(x, z)
			cells[j * GNX + i] = _raw(x, z, seg)
			_near[j * GNX + i] = seg.x
	_grid = cells
	# ジャンプ台の形
	_kick.clear()
	for kk in KICKERS:
		_kick.append(_kicker_shape(kk[0], kk[1], kk[2]))


## 地面に足す高さ（高台から）。山の外では 0
static func lift(x: float, z: float) -> float:
	if x <= GX0 or x >= GX1 or z <= GZ0 or z >= GZ1:
		return 0.0
	_build()
	var fx := minf((x - GX0) / GSTEP, GNX - 1.001)
	var fz := minf((z - GZ0) / GSTEP, GNZ - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(_grid[j * GNX + i], _grid[j * GNX + i + 1], tx)
	var b := lerpf(_grid[(j + 1) * GNX + i], _grid[(j + 1) * GNX + i + 1], tx)
	return lerpf(a, b, tz)


## 大山の地面の上か（x は継ぎ目から東、z は地面の南北の幅）。main.gd が地面を分ける用
static func on_ground(x: float, z: float) -> bool:
	return x > GX0 and x < GX1 and z > GZ0 and z < GZ1


## 継ぎ目（x = GX0）の近くで 0、離れると 1。吹きだまりのうねりを消して、大きな山の側の地面（1 m おき）と雪面をそろえる
static func seam_fade(x: float, z: float) -> float:
	if z < GZ0 - 8.0 or z > GZ1 + 8.0:
		return 1.0
	return smoothstep(0.0, 8.0, absf(x - GX0))


## ジャンプ台の形。mountain.gd の _kicker_shape と同じ作り
static func _kicker_shape(x: float, z: float, launch: float) -> Dictionary:
	var e := 1.0
	var gx := (_raw(x + e, z) - _raw(x - e, z)) / (2.0 * e)
	var gz := (_raw(x, z + e) - _raw(x, z - e)) / (2.0 * e)
	var f := Vector2(-gx, -gz).normalized()
	var fall := (_raw(x - f.x * 2.0, z - f.y * 2.0) - _raw(x, z)) / 2.0
	var hl := KICK_L * (tan(deg_to_rad(launch)) + fall) * 0.5
	return {"lip": Vector2(x, z), "f": f, "fall": fall, "hl": hl, "launch": launch}


## ジャンプ台 i の形
static func kicker(i: int) -> Dictionary:
	_build()
	return _kick[i]


## ジャンプ台の手前と先（木を置かない所）
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


## 南の尾根の背の上で 1（雪の色を踏み固めた色にする用。押して登る道の目じるし）。
## 見た目の地面が 2 m おきなので、大きな山の背より少し広く塗る
static func path_weight(x: float, z: float) -> float:
	if x <= GX0 or x >= GX1 or z <= GZ0 or z >= GZ1:
		return 0.0
	_build()
	var fx := minf((x - GX0) / GSTEP, GNX - 1.001)
	var fz := minf((z - GZ0) / GSTEP, GNZ - 1.001)
	if _near[int(fz + 0.5) * GNX + int(fx + 0.5)] > 8.0:
		return 0.0
	var s: Vector3 = Mountain._seg(Vector2(x, z), _pts)
	if s.y > _ridge_len - 4.0:
		return 0.0
	return 1.0 - smoothstep(1.6, 3.2, s.x)


## 南の尾根の背の上（木を置かない用）
static func on_ridge(x: float, z: float, margin := 0.0) -> bool:
	_build()
	return Mountain._seg(Vector2(x, z), _pts).x < RIDGE_CREST + margin


## x の帯の名前（ZONES）
static func zone(x: float) -> String:
	if x > SX:
		return "裏"
	for zn in ZONES:
		if x >= zn[1]:
			return zn[0]
	return "窪地"


## 南の尾根を押して登るときの向き（水平の単位）: 背に沿って上へ、背のまんなかへ寄せる
static func ridge_guide(p: Vector2) -> Vector2:
	_build()
	var s: Vector3 = Mountain._seg(p, _pts)
	var at := _ridge_point(maxf(s.y - 8.0, 0.0))   # 8 m 上の背の点へ向かう
	return (at - p).normalized()


## 背に沿った位置 s (m、頂上から) の点
static func _ridge_point(s: float) -> Vector2:
	var acc := 0.0
	for k in _pts.size() - 1:
		var a: Vector2 = _pts[k]
		var b: Vector2 = _pts[k + 1]
		var l := a.distance_to(b)
		if s <= acc + l:
			return a.lerp(b, (s - acc) / l)
		acc += l
	return _pts[_pts.size() - 1]


## 西の斜面（滑る所）の上か（ボタンを置く用）
static func on_face(x: float, z: float) -> bool:
	return absf(z - FACE_Z) < FACE_W and x > BOTTOM_X + 4.0 and x < SX - 4.0


# ---------------------------------------------------------------- 飾りとジャンプ台と手すり

func _ready() -> void:
	_build()
	for i in KICKERS.size():
		_make_kicker(i, _kick[i])
	_markers()
	_rail(RAIL_TOP, RAIL_BOTTOM)
	_trees()


## 南の尾根の道しるべ: 背の脇に、藍の小さな旗を 36 m おきに左右かわるがわる（大きな山と同じ）
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


## 山の地肌の木: 大きな山と同じ置き方。沢の脇と山の脇に多く、西の斜面のまんなかはまばらに。尾根の背・ジャンプ台の手前と先・手すりは空ける。
## 急すぎる所には立てず、代わりに大きな岩を置く
func _trees() -> void:
	const TREES := ["res://props/tree_tall.glb", "res://props/tree_zigzag.glb", "res://props/tree_round.glb",
		"res://props/tree_little.glb"]
	const ROCKS := ["res://props/rock_a.glb", "res://props/rock_b.glb", "res://props/rock_c.glb"]
	const MAX_TREES := 340
	const MAX_ROCKS := 40
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var trees := 0
	var rocks := 0
	for k in 12000:
		if trees >= MAX_TREES and rocks >= MAX_ROCKS:
			break
		var x := rng.randf_range(BOTTOM_X - 6.0, SX + 240.0)
		var z := rng.randf_range(SZ - 236.0, SZ + 236.0)
		var keep := rng.randf()
		var hgt := rng.randf_range(4.0, 8.0)
		var yaw := rng.randf() * TAU
		var b := _body(x, z)
		if b.y > 0.97:
			continue
		if on_ridge(x, z, 3.0) or on_kicker_lane(x, z):
			continue
		if absf(z - RAIL_TOP.y) < 6.0 and x > RAIL_BOTTOM.x - 8.0 and x < RAIL_TOP.x + 6.0:
			continue
		# 西の斜面のまんなかは、開けた雪原（木は 1 割）
		if absf(z - FACE_Z) < FACE_W * 0.8 and x < SX and keep > 0.1:
			continue
		var gx := _y(x + 1.0, z) - _y(x - 1.0, z)
		var gz := _y(x, z + 1.0) - _y(x, z - 1.0)
		var steep := Vector2(gx, gz).length() * 0.5
		if steep > 0.85:   # 40° より急: 岩
			if rocks >= MAX_ROCKS:
				continue
			var rock := Props.make(ROCKS[k % ROCKS.size()])
			var sc := rng.randf_range(4.0, 8.0)
			var up: Vector3 = world.ground_normal(x, z, 0.6 * sc)
			rock.basis = Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
			rock.position = Vector3(x, _y(x, z) + world.snow_lift(x, z) - 0.12 * sc, z)
			add_child(rock)
			world.settle(rock)
			rocks += 1
			continue
		if trees >= MAX_TREES:
			continue
		var tree := _put(TREES[k % TREES.size()], x, z, yaw, 0.35 * hgt / 6.0)
		tree.scale = Vector3.ONE * hgt / 6.0
		trees += 1
