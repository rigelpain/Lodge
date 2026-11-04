extends RefCounted
## 標高の札の範囲（丘・大斜面・山）。2026-11-04 代表「タグで山ごとに識別できるように丘、大斜面、山、と3種類の標高表示を作ってほしい。
## 丘の範囲にあったら丘の標高マップ、大斜面の範囲にあったら大斜面の標高マップ、みたいにしてほしい。そしたらどの山の近くを探せばいいかわかるし」。
## 札は、ソリのいる範囲の断面を描く。地形の側は変えず、main.gd の height() を線に沿って測るだけ。
## 入るのは範囲の楕円の内側（IN）、出るのは少し外（OUT）。あいだでは今の札のままなので、境目でちらちら替わらない。
## 新しい山を足すときは、AREAS に 1 行足し、ORDER に名前を足す。絵と色は elev_card.gd の COLORS と cloth()、旗は area_flags.gd。

const Mountain := preload("res://mountain.gd")
const Grand := preload("res://grand_mountain.gd")

## どの範囲にも入らない所（ロッジのまわり）の札
const NONE := "lodge"

## 範囲ごとの断面: top は頂上 (x, z)、dir は頂上からロッジの側の麓へ向かう向き。
## rx・rn・rs は範囲の楕円の半径（横・手前・奥。m）。back は頂上の向こうに描く長さ、foot は手前に描く長さ（m）。
## tall は札の段の中の山の高さ（0〜1）。丘は低く、山は段いっぱいに
const AREAS := {
	"hill": {"top": Vector2(0, 0), "dir": Vector2(0, 1), "rx": 68.0, "rn": 68.0, "rs": 68.0, "back": 56.0, "foot": 76.0, "tall": 0.58},
	"slope": {"top": Vector2(Mountain.SX, Mountain.SZ), "dir": Vector2(0, -1), "rx": 170.0, "rn": 312.0, "rs": 135.0, "back": 100.0, "foot": 310.0, "tall": 0.82},
	# 大山（grand_mountain.gd）。ロッジの側（西）へ長い。範囲の手前の縁が地面の継ぎ目（FOOT_X = 128）
	"peak": {"top": Vector2(Grand.SX, Grand.SZ), "dir": Vector2(-1, 0), "rx": Grand.AZ + 20.0, "rn": Grand.SX - Grand.FOOT_X, "rs": Grand.AXE + 20.0, "back": 250.0, "foot": Grand.SX - Grand.FOOT_X, "tall": 1.0},
	# ロッジのまわり: 丘の裾から山の麓までの高台。rx を大きくして、奥行きだけで断面に移す
	"lodge": {"top": Vector2(-35, 134), "dir": Vector2(0, -1), "rx": 100000.0, "rn": 66.0, "rs": 66.0, "back": 66.0, "foot": 66.0, "tall": 0.0},
}
const IN := 1.0              # 楕円の半径の何倍の内側で入るか
const OUT := 1.12            # 楕円の半径の何倍の外側で出るか
const ORDER := ["hill", "slope", "peak"]

## 確かめの絵のための差し替え（地形のない所で札を描く用）: { 範囲の名前: 設定 }。設定の profile に断面の関数を渡せる
static var extra := {}
static var _sections := {}


static func info(id: String) -> Dictionary:
	return extra[id] if extra.has(id) else AREAS.get(id, {})


## 楕円の上の位置（頂上で 0、範囲の縁で 1）
static func rho(id: String, p: Vector2) -> float:
	var f := info(id)
	var d := p - (f.top as Vector2)
	var dir: Vector2 = f.dir
	var along := d.dot(dir)
	var side := d.dot(Vector2(dir.y, -dir.x))
	var ra: float = f.rn if along >= 0.0 else f.rs
	return sqrt(pow(side / f.rx, 2.0) + pow(along / ra, 2.0))


## いまの位置の範囲。now は今の札（入っていれば OUT まで離さない）
static func of(p: Vector2, now := "") -> String:
	if now in ORDER and rho(now, p) < OUT:
		return now
	for id in ORDER:
		if rho(id, p) < IN:
			return id
	return NONE


## 断面の上の位置（m。頂上で 0、手前が正、奥が負）。楕円の等高線に沿って断面へ移すので、脇にいても同じくらいの標高の所に出る
static func locate(id: String, p: Vector2) -> float:
	var f := info(id)
	var along := (p - (f.top as Vector2)).dot(f.dir as Vector2)
	var ra: float = f.rn if along >= 0.0 else f.rs
	return clampf(rho(id, p) * ra * (1.0 if along >= 0.0 else -1.0), -float(f.back), float(f.foot))


## 断面: [Vector2(断面の上の位置 m, 高さ 0〜1)] を 65 点（いちばん低い所が 0、いちばん高い所が 1）。一度だけ測る
static func section(id: String, height: Callable) -> PackedVector2Array:
	if _sections.has(id):
		return _sections[id]
	var f := info(id)
	var raw := PackedVector2Array()
	var low := INF
	var high := -INF
	for i in 65:
		var r := lerpf(-float(f.back), float(f.foot), i / 64.0)
		var at: Vector2 = (f.top as Vector2) + (f.dir as Vector2) * r
		var h: float = f.profile.call(r) if f.has("profile") else height.call(at.x, at.y)
		raw.append(Vector2(r, h))
		low = minf(low, h)
		high = maxf(high, h)
	for i in raw.size():
		raw[i].y = (raw[i].y - low) / maxf(high - low, 0.01)
	_sections[id] = raw
	return raw


## 断面の高さ（0〜1）。r は断面の上の位置
static func level(sec: PackedVector2Array, r: float) -> float:
	var t := clampf((r - sec[0].x) / (sec[sec.size() - 1].x - sec[0].x), 0.0, 1.0) * (sec.size() - 1)
	var i := mini(int(t), sec.size() - 2)
	return lerpf(sec[i].y, sec[i + 1].y, t - i)
