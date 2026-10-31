extends Node
## 気温（自動で読み込む。Temperature.at(位置) で、その位置・いまの時刻の気温 (°C) を引く）。
## いまの要素は 4 つ。あとで天気（吹雪など）や高い山を足しても、ここを引く側は変えなくてよい:
##   - 外は寒い。高い所ほど寒い（標高で下がる。丘は 18 m なので、本物より強めに下げる）
##   - 夜は昼より寒い（daycycle.gd の時刻。いちばん暖かいのは 14 時、いちばん寒いのは明け方 4 時）
##   - ロッジの中は暖かく、暖炉のそばはもっと暖かい。風除室はそのあいだ。中か外かは、音の屋内の判定（audio.gd の zone_at）と同じ
##   - 天気が足す寒さ（weather_chill。いまは 0。吹雪なら -8 など）
## breath(位置) は、その気温で白い息がどれだけ見えるか（0 見えない 〜 1 ふつうの寒さ 〜 1.6 とても寒い）。
## shiver_of(気温) は寒さのふるえ（0 〜 1）、calm_of(気温) は暖かさの落ち着き（0 〜 1。人形の揺れがゆっくりになる）。
## ロッジに置く巨大な温度計（チャコペンのモチーフ、案）も、この値を指す

const Audio := preload("res://audio.gd")

const DAY_PEAK := -2.0       # 外の、昼（14 時）の気温 (°C)
const NIGHT_LOW := -11.0     # 外の、明け方（4 時）の気温
const LAPSE := 0.25          # 高さ 1 m で下がる気温 (°C)。本物（0.0065）よりずっと強く: 丘の頂上（18 m）で 4.5 °C 寒い
const INDOOR := 18.0         # ロッジの中
const VESTIBULE := 6.0       # 風除室
const FIRE_WARM := 8.0       # 暖炉のすぐそばで、これだけ暖かい
const FIRE_R := 5.0          # 暖炉の暖かさが届く (m)
const FIRE_FALLBACK := Vector3(10.9, 1.0, -10.8)   # 暖炉の目印が見つからないときの所（ロッジの座標。audio.gd と同じ）
const BREATH_WARM := 8.0     # これより暖かいと、白い息は見えない
const BREATH_SPAN := 12.0    # そこから 12 °C 寒くなると、ふつうの白い息（1）
const SHIVER_FROM := 4.0     # これより寒いと、人形がふるえはじめる
const SHIVER_FULL := -8.0    # ここで、いちばん強くふるえる（ふもとの昼 −2 °C で半分、夜や丘の頂上でほぼいっぱい）
const CALM_FROM := 8.0       # これより暖かいと、人形の揺れがゆっくりになりはじめる
const CALM_FULL := 16.0      # ここで、いちばんゆっくり（ロッジの中）

var weather_chill := 0.0     # 天気が足す寒さ (°C、負で寒い)。吹雪などの天気ができたら、そこから入れる

var _lodge: Node3D
var _fire := Vector3.INF     # 暖炉の所（世界）
var _looked := -100000       # ロッジを最後に探した時 (ms)


## その位置・いまの時刻の気温 (°C)
func at(pos: Vector3) -> float:
	var lodge := _find_lodge()
	var zone := Audio.zone_at(lodge, pos) if lodge else 0
	if zone == 2:
		var warm := INDOOR
		if _fire != Vector3.INF:
			warm += FIRE_WARM * clampf(1.0 - pos.distance_to(_fire) / FIRE_R, 0.0, 1.0)
		return warm
	var outside := _outdoor(pos)
	return lerpf(outside, VESTIBULE, 0.6) if zone == 1 else outside


## 外の気温: 時刻と高さと天気
func _outdoor(pos: Vector3) -> float:
	var dc := get_node_or_null("/root/DayCycle")
	var h: float = dc.hour if dc else 12.0
	var day := 0.5 + 0.5 * cos((h - 14.0) / 24.0 * TAU)   # 14 時で 1、2 時で 0
	var t := lerpf(NIGHT_LOW, DAY_PEAK, day)
	return t - LAPSE * maxf(pos.y, 0.0) + weather_chill


## その気温で、白い息がどれだけ見えるか（0 〜 1.6）
func breath(pos: Vector3) -> float:
	return breath_of(at(pos))


static func breath_of(temp: float) -> float:
	return clampf((BREATH_WARM - temp) / BREATH_SPAN, 0.0, 1.6)


## その気温で、人形がどれだけふるえるか（0 〜 1）
static func shiver_of(temp: float) -> float:
	return smoothstep(SHIVER_FROM, SHIVER_FULL, temp)


## その気温で、人形の揺れがどれだけゆっくり落ち着くか（0 〜 1）
static func calm_of(temp: float) -> float:
	return smoothstep(CALM_FROM, CALM_FULL, temp)


func _find_lodge() -> Node3D:
	if _lodge and is_instance_valid(_lodge):
		return _lodge
	# ロッジがない場面（確かめ用の場面など）で毎回探さないよう、探すのは 2 秒に一度
	var now := Time.get_ticks_msec()
	if now - _looked < 2000:
		return null
	_looked = now
	_lodge = get_tree().root.find_child("Lodge", true, false) as Node3D
	_fire = Vector3.INF
	if _lodge:
		var mark := _lodge.find_child("light_fire", true, false) as Node3D
		_fire = mark.global_position if mark else _lodge.to_global(FIRE_FALLBACK)
	return _lodge
