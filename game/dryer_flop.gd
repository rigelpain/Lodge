extends RefCounted
## 乾燥機の胴の中で、人形がぐにゃんぐにゃんに回される物理（cook_station.gd が中の人ごとに 1 つ持つ）。
## 2026-11-01 代表「キャラが入るときはキャラの顔が窓から見えるようにして、体はぐにゃんぐにゃんの物理演算にしてほしい」。
## 胴の断面（戸の向きに垂直な面）の 2 次元で考える。x は下（重力の向き）、y は下を戸の向きのまわりに 90° 回した向き。
##   体     体は 1 つの点（人形の付け根）と向き。重力で落ち、胴の壁（半径 WALL）に当たると少し跳ね返る。
##          壁に着くと羽根に引っかかって、胴といっしょに持ち上げられ（体も壁に足を向けて回る）、てっぺんの手前で離れて落ちる。
##          離れる角は持ち上げられるたびに変わる。落ちるあいだは、離れたときの勢いでくるくる回る
##   手足と頭 体の向きに対して、戸の向きのまわりに振れるばね。見かけの重力（重力 − 体の加速度）に引かれて垂れ、
##          体が回りはじめると遅れてついてくる。ばねを弱く、揺れの止まりを遅くして、ぐにゃんぐにゃんにする
## 計算は 1 コマ（12 コマ／秒）を SUB 回に刻んで、入ってからのコマだけで進める。乱数は使わないので、通信ではどの画面でも
## 同じコマに同じ形になる。姿は人形の 12 コマで刻む

const SUB := 4               # 1 コマを刻む数
const DT := 1.0 / (12.0 * SUB)
const G := 9.8
const WALL := 0.38           # 胴の真ん中から、壁に着いた人形の付け根までの距離 (m)
const BOUNCE := 0.3          # 壁で跳ね返る強さ
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
var p := Vector2.ZERO        # 体の付け根（胴の真ん中から）
var v := Vector2.ZERO
var th := 0.0                # 体の向き（戸の向きのまわりに回った角。0 で立つ）
var w := 0.0                 # 体の回る速さ
var carried := false         # 羽根に持ち上げられている
var lift := 0                # 持ち上げられた回数（離れる角を変える）
var limb := []               # 手足ごとの [振れ, 振れる速さ]
var landed := false          # このコマで壁に落ちた（「ぽすっ」）
var _out: Array = []         # 入ってからのコマごとの {p, th, flop, land}


func _init(spin_per_s: float, start: Vector2) -> void:
	spin = spin_per_s
	p = start
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


func _snap() -> Dictionary:
	var flop := {}
	for i in LIMBS.size():
		flop[LIMBS[i][0]] = limb[i][0]
	return {"p": p, "th": th, "flop": flop, "land": landed}


## 持ち上げられて離れる角（下から。2.2〜2.9 rad、てっぺんの手前）
func _release() -> float:
	var f := fposmod(sin(lift * 12.9898 + 4.1) * 43758.5453, 1.0)
	return 2.2 + 0.7 * f


func _step() -> void:
	var v0 := v
	var w0 := w
	var a := atan2(p.y, p.x)   # 体のいる角（下から、胴の回る向きに）
	if carried:
		a += spin * DT
		p = Vector2(cos(a), sin(a)) * WALL
		v = Vector2(-sin(a), cos(a)) * spin * WALL
		w = spin
		th += spin * DT + wrapf(a - th, -PI, PI) * minf(1.0, 6.0 * DT)   # 足を壁へ向けていく
		if a >= _release():
			carried = false
			lift += 1
			w = spin * KICK   # 離れて、くるっと回りながら落ちる
	else:
		v += Vector2(G, 0.0) * DT
		p += v * DT
		th += w * DT
		w *= 1.0 - 0.4 * DT
		if p.length() > WALL:
			var n := p.normalized()
			p = n * WALL
			var vn := v.dot(n)
			if vn > 0.0:
				v -= n * vn * (1.0 + BOUNCE)
				if vn > 1.0:
					landed = true
			# 壁に着いた所が胴の下半分なら、羽根に引っかかって持ち上げられる。上のほうなら壁にそってすべり落ちる
			if n.x > 0.0:
				carried = true
				w = spin
	# 手足: 見かけの重力（体の座標で）に引かれ、体が回りはじめると遅れる
	var acc := (v - v0) / DT
	if acc.length() > 40.0:
		acc = acc.normalized() * 40.0
	var ga := (Vector2(G, 0.0) - acc).rotated(-th)
	var wa := (w - w0) / DT
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
