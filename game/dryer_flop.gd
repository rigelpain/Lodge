extends RefCounted
## 乾燥機の胴の中で、人形がぐにゃんぐにゃんに回される物理（cook_station.gd が中の人ごとに 1 つ持つ）。
## 2026-11-01 代表「キャラが入るときはキャラの顔が窓から見えるようにして、体はぐにゃんぐにゃんの物理演算にしてほしい」。
## 胴の断面（戸の向きに垂直な面）の 2 次元で考える。x は下（重力の向き）、y は下を戸の向きのまわりに 90° 回した向き。
##   体     足もとから頭までの太さのある棒（両端の太さは、足もとは細く、頭は笠のつば・裾の広さ）。重力で落ち、両端が胴の壁に
##          当たると少し跳ね返り、当たった所の勢いで体がくるっと回る。胴の下のほうで壁に着くと羽根に引っかかって、
##          胴といっしょに持ち上げられ、てっぺんの手前で離れて落ちる。離れる角は持ち上げられるたびに変わる。
##          胴（半径 0.65 m）に収まらない大きな人形（笠・ゴーレム）は、収まるまで小さくする（fit。とび込むあいだに縮み、出るとき戻る）
##   手足と頭 体の向きに対して、戸の向きのまわりに振れるばね。見かけの重力（重力 − 体の加速度）に引かれて垂れ、
##          体が回りはじめると遅れてついてくる。ばねを弱く、揺れの止まりを遅くして、ぐにゃんぐにゃんにする
## 計算は 1 コマ（12 コマ／秒）を SUB 回に刻んで、入ってからのコマだけで進める。乱数は使わないので、通信ではどの画面でも
## 同じコマに同じ形になる。姿は人形の 12 コマで刻む

const SUB := 4               # 1 コマを刻む数
const DT := 1.0 / (12.0 * SUB)
const G := 9.8
const INNER := 0.62          # 胴の真ん中から、体が当たる壁までの距離 (m。胴の編み地の内側)
const FEET := 0.1            # 足もとの端の太さ (m)
const BOUNCE := 0.3          # 壁で跳ね返る強さ
const GRIP := 0.6            # 壁の摩擦
const KICK := 1.5            # 羽根から離れるとき、体が胴の回りより速く回る倍
## 手足と頭: [名前, 体の座標での向き（x 下、y 左）, 引かれる強さ, ばね, 止まり, 振れの限り]
const LIMBS := [
	["arm.L", Vector2(0.8, 0.6), 70.0, 18.0, 2.2, 1.6],
	["arm.R", Vector2(0.8, -0.6), 70.0, 18.0, 2.2, 1.6],
	["leg.L", Vector2(0.95, 0.3), 45.0, 22.0, 2.6, 1.0],
	["leg.R", Vector2(0.95, -0.3), 45.0, 22.0, 2.6, 1.0],
	["head", Vector2(-1.0, 0.0), 25.0, 45.0, 3.5, 0.6],
]

var spin := 0.0              # 胴が 1 秒に回る角 (rad)
var fit := 1.0               # 人形を小さくする倍（胴に収まるように）
var c := Vector2.ZERO        # 体の棒の真ん中（胴の真ん中から）
var v := Vector2.ZERO
var th := 0.0                # 体の向き（戸の向きのまわりに回った角。0 で立つ）
var w := 0.0                 # 体の回る速さ
var carried := false         # 羽根に持ち上げられている
var lift := 0                # 持ち上げられた回数（離れる角を変える）
var _turned := 0.0           # 持ち上げられてから回った角（持ち上げられた所の角から数える）
var limb := []               # 手足ごとの [振れ, 振れる速さ]
var landed := false          # このコマで壁に落ちた（「ぽすっ」）
var _a := 0.0                # 棒の半分の長さ
var _mid := 0.0              # 足もと（人形の付け根）から棒の真ん中までの高さ
var _rt := 0.2               # 頭の端の太さ
var _inertia := 0.1
var _out: Array = []         # 入ってからのコマごとの {p, th, flop, land}


## spin_per_s 胴の回る速さ、seat とび込んで着く足もと（胴の真ん中から）、ext 人形の大きさ（doll.gd の drum_extent: 足・頭のてっぺん・広さ）
func _init(spin_per_s: float, seat: Vector2, ext: Vector3) -> void:
	spin = spin_per_s
	var bot := ext.x + FEET
	var top := ext.y - minf(ext.z, 0.15)
	_rt = maxf(ext.z, FEET)
	var half := maxf((top - bot) * 0.5, 0.05) + _rt
	fit = minf(1.0, INNER / half)
	_a = maxf((top - bot) * 0.5, 0.05) * fit
	_mid = (top + bot) * 0.5 * fit
	_rt *= fit
	_inertia = _a * _a / 3.0 + _rt * _rt / 4.0
	c = seat + _up() * _mid
	for l in LIMBS:
		limb.append([0.0, 0.0])
	_out.append(_snap())


## 入ってからのコマ k の形（まだなら、そこまで計算する）
func at(k: int) -> Dictionary:
	k = maxi(k, 0)
	while _out.size() <= k:
		landed = false
		for i in SUB:
			_step()
		_out.append(_snap())
	return _out[k]


## 体の上の向き（足から頭へ）
func _up() -> Vector2:
	return Vector2(-1.0, 0.0).rotated(th)


func _snap() -> Dictionary:
	var flop := {}
	for i in LIMBS.size():
		flop[LIMBS[i][0]] = limb[i][0]
	return {"p": c - _up() * _mid, "th": th, "flop": flop, "land": landed, "fit": fit}


## 持ち上げられて離れる角（下から。2.2〜2.9 rad、てっぺんの手前）
func _release() -> float:
	var f := fposmod(sin(lift * 12.9898 + 4.1) * 43758.5453, 1.0)
	return 2.2 + 0.7 * f


static func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


static func _perp(a: Vector2) -> Vector2:
	return Vector2(-a.y, a.x)


func _step() -> void:
	var v0 := v
	var w0 := w
	if carried:
		# 羽根に引っかかって、胴といっしょに回る（胴の真ん中のまわりに、体ごと）
		var da := spin * DT
		c = c.rotated(da)
		th += da
		v = _perp(c) * spin
		w = spin
		_turned += da
		if _turned >= _release():
			carried = false
			lift += 1
			w = spin * KICK   # 離れて、くるっと回りながら落ちる
	else:
		v += Vector2(G, 0.0) * DT
		c += v * DT
		th += w * DT
		w *= 1.0 - 0.4 * DT
		for end in [[1.0, _rt], [-1.0, FEET * fit]]:
			var e: Vector2 = c + _up() * _a * float(end[0])
			var lim: float = INNER - float(end[1])
			if e.length() <= lim:
				continue
			var n := e.normalized()
			c -= n * (e.length() - lim)
			e = n * lim
			var r := e - c
			var ve := v + _perp(r) * w
			var vn := ve.dot(n)
			if vn > 0.0:
				var rn := _cross(r, n)
				var j := (1.0 + BOUNCE) * vn / (1.0 + rn * rn / _inertia)
				v -= n * j
				w -= rn * j / _inertia
				if vn > 1.0:
					landed = true
				# 壁の摩擦: 当たった所を、胴の壁の動きへ寄せる
				var t := _perp(n)
				var vt := (v + _perp(r) * w - _perp(e) * spin).dot(t)
				var rt := _cross(r, t)
				var jt := clampf(-vt / (1.0 + rt * rt / _inertia), -GRIP * j, GRIP * j)
				v += t * jt
				w += rt * jt / _inertia
			# 胴の下のほうで壁に着いたら、羽根に引っかかって持ち上げられる。上のほうなら、そのまま落ちる
			if n.x > 0.3:
				carried = true
				_turned = atan2(n.y, n.x)
				w = spin
	# 手足: 見かけの重力（体の座標で）に引かれ、体が回りはじめると遅れる
	var acc := (v - v0) / DT
	if acc.length() > 40.0:
		acc = acc.normalized() * 40.0
	var ga := (Vector2(G, 0.0) - acc).rotated(-th)
	var wa := clampf((w - w0) / DT, -60.0, 60.0)
	for i in LIMBS.size():
		var l: Array = LIMBS[i]
		var s: Array = limb[i]
		var d := (l[1] as Vector2).normalized().rotated(s[0])
		var pull := (d.x * ga.y - d.y * ga.x) / G   # d を見かけの重力へ向ける向き（正で回る向き）
		var aa: float = l[2] * pull - l[3] * s[0] - l[4] * s[1] - wa
		s[1] += aa * DT
		s[0] = clampf(s[0] + s[1] * DT, -l[5], l[5])
		if absf(s[0]) >= l[5]:
			s[1] *= -0.3   # 振れの限りで、少し跳ね返る
