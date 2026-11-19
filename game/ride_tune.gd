extends RefCounted
## テストプレイ用の乗り心地の調整（2026-11-19 代表「TPS視点とFPS視点で揺れの強度変えたい」「そこら辺のパラメータ（ソリのスピード、加速、
## ぶつかったときの飛び方、飛ぶ速度など）まとめてテストプレイ用のゲーム内ではいじれるようにして、しっくり来る設定を本番にいれれるようにjsonとかでコピーできるように」）。
##
## 値は sled.gd・flung.gd・player.gd の static var（もとは const）。ここは、どの値をどの範囲で動かすかの一覧と、値の読み書き・JSON への出し入れだけを持つ。
## 画面は ride_tune_ui.gd（設定の画面で「確かめ用の数字」を入れると出るボタンから開く）。
## 変えた値はその起動のあいだだけ効き、保存しない（本番の既定は、下の手順でソースに書き戻したものだけ）。
## つないで遊ぶときは、ソリの物理と放り投げる向き・強さはホストが決めるので、ホストの値で動く（画面の揺れは各自の値）。
##
## 本番に入れる手順:
##   1. 調整の画面で「JSON をコピー」。その JSON を Claude に渡して「本番に入れて」と言う
##   2. JSON を game/tools/ride_tune.json に置き、次を流すと、3 つの .gd の static var の既定値が書き換わる（変わった行を表示する）
##        $G --headless --path game -s res://tools/ride_tune_apply.gd -- res://tools/ride_tune.json
##   3. 変わった値の注釈と design/controls-and-physics.md を合わせて、PR にする

const FILES := {
	"sled": preload("res://sled.gd"),
	"flung": preload("res://flung.gd"),
	"player": preload("res://player.gd"),
}
const FORMAT := 1   # JSON の形の版

## [ファイル, 変数, 成分（"" はそのまま、"x"・"y" は Vector2 の成分、ほかは辞書の鍵）, 見出し, 下限, 上限, きざみ]。"#" で始まる行は見出し
const ITEMS := [
	["#", "ソリの速さ"],
	["sled", "FEEL", "glide", "雪の抵抗（小さいほど最高速度が速い）", 0.05, 1.0, 0.01],
	["sled", "FEEL", "pull", "坂の加速（重力に足す割合）", 0.0, 1.5, 0.01],
	["#", "隆起の跳ね"],
	["sled", "FEEL", "bumps", "跳ねの強さ（0 で無し）", 0.0, 3.0, 0.05],
	["sled", "BUMP_CHANCE", "", "隆起がある升の割合", 0.0, 1.0, 0.01],
	["sled", "BUMP_MIN", "", "跳ねはじめる速さ (m/s)", 0.0, 15.0, 0.1],
	["sled", "BUMP_UP", "", "突き上げ = 速さ × これ", 0.0, 0.2, 0.005],
	["sled", "BUMP_UP_MAX", "", "突き上げの上限 (m/s)", 0.0, 3.0, 0.05],
	["sled", "BUMP_PITCH", "", "つんのめり (rad/s)", 0.0, 4.0, 0.05],
	["sled", "BUMP_ROLL", "", "左右にがくっと傾く (rad/s)", 0.0, 3.0, 0.05],
	["sled", "BUMP_SPIN_AT", "", "回りがこの速さで前と同じ (m/s)", 1.0, 20.0, 0.5],
	["sled", "BUMP_SPIN_OVER", "", "回りの頭打ち（倍）", 0.5, 3.0, 0.05],
	["sled", "LAND_BOUNCE", "", "着地のはね返り（割合）", 0.0, 1.0, 0.01],
	["sled", "LAND_BOUNCE_MAX", "", "着地のはね返りの上限 (m/s)", 0.0, 5.0, 0.05],
	["#", "滑るときの画面の揺れ"],
	["player", "RATTLE_FIRST", "", "一人称の倍率", 0.0, 3.0, 0.05],
	["player", "RATTLE_THIRD", "", "三人称の倍率", 0.0, 3.0, 0.05],
	["sled", "FEEL", "rattle", "揺れ全体の強さ", 0.0, 2.0, 0.05],
	["player", "RATTLE_FULL", "", "この速さで揺れが全部 (m/s)", 2.0, 30.0, 0.5],
	["player", "RATTLE_OVER", "", "速さの比例の頭打ち（倍）", 1.0, 3.0, 0.05],
	["player", "RATTLE_Y", "", "目の上下 (m)", 0.0, 0.1, 0.001],
	["player", "RATTLE_PITCH", "", "うなずき (rad)", 0.0, 0.1, 0.001],
	["player", "RATTLE_ROLL", "", "左右の傾き (rad)", 0.0, 0.1, 0.001],
	["player", "RATTLE_BUMP", "", "隆起・着地の直後の倍率", 1.0, 5.0, 0.05],
	["player", "RATTLE_AIR", "", "宙にいるあいだの割合", 0.0, 1.0, 0.05],
	["#", "ソリが木・雪の塊にぶつかったとき"],
	["sled", "CRASH_SOFT_SPEED", "", "雪の塊で打ち上がる速さ (m/s)", 0.0, 15.0, 0.1],
	["sled", "CRASH_UP", "x", "上へ飛ぶ速さ: 遅く当たったとき (m/s)", 0.0, 30.0, 0.5],
	["sled", "CRASH_UP", "y", "上へ飛ぶ速さ: 速く当たったとき (m/s)", 0.0, 30.0, 0.5],
	["sled", "CRASH_UP_AT", "x", "「遅く」の速さ (m/s)", 0.0, 30.0, 0.5],
	["sled", "CRASH_UP_AT", "y", "「速く」の速さ (m/s)", 0.0, 30.0, 0.5],
	["sled", "CRASH_KEEP", "", "雪の塊: 前へ残る速さの割合", 0.0, 1.5, 0.01],
	["sled", "CRASH_BOUNCE", "", "木: 跳ね返る速さの割合", 0.0, 1.5, 0.01],
	["sled", "CRASH_FLY_T", "", "宙を進む距離 = 残る速さ × これ (s)", 0.0, 6.0, 0.05],
	["sled", "CRASH_SPIN", "x", "宙で回る速さ: 下限 (rad/s)", 0.0, 20.0, 0.5],
	["sled", "CRASH_SPIN", "y", "宙で回る速さ: 上限 (rad/s)", 0.0, 20.0, 0.5],
	["#", "乗っている人が放り投げられるとき"],
	["flung", "CRASH_MIN", "", "放り投げられる速さ (m/s)", 0.0, 20.0, 0.1],
	["flung", "THROW_DIST_K", "", "宙を飛ぶ距離 = 速さ × これ (m)", 0.0, 4.0, 0.05],
	["flung", "THROW_DIST_VAR", "x", "距離のばらつき: 下限（倍）", 0.0, 2.0, 0.01],
	["flung", "THROW_DIST_VAR", "y", "距離のばらつき: 上限（倍）", 0.0, 2.0, 0.01],
	["flung", "THROW_DIST_MAX", "", "宙を飛ぶ距離の上限 (m)", 0.0, 150.0, 1.0],
	["flung", "THROW_RISE", "x", "打ち上がる角度（上 ÷ 水平）: 下限", 0.0, 4.0, 0.05],
	["flung", "THROW_RISE", "y", "打ち上がる角度（上 ÷ 水平）: 上限", 0.0, 4.0, 0.05],
	["flung", "G_UP", "", "上がるあいだの重力 (m/s²。轢かれたときも)", 2.0, 40.0, 0.2],
	["flung", "G_DOWN", "", "下りるあいだの重力 (m/s²。轢かれたときも)", 2.0, 40.0, 0.2],
	["flung", "THROW_FAN", "", "左右へ広がる角度 (度)", 0.0, 180.0, 1.0],
	["flung", "THROW_FAN_MIN", "", "真っすぐ前を避ける角度 (度)", 0.0, 90.0, 1.0],
	["flung", "THROW_FAN_ONE", "", "1 人のとき、それる角度の端 (度)", 0.0, 90.0, 1.0],
	["flung", "THROW_JITTER", "", "向きのばらつき (度)", 0.0, 45.0, 1.0],
]

static var _defaults := {}   # 起動したときの値（ソースの既定）。鍵は id()


## 項目の名前（"sled.CRASH_UP.x" など）
static func id(it: Array) -> String:
	return "%s.%s%s" % [it[0], it[1], ("." + it[2]) if it[2] != "" else ""]


static func items() -> Array:
	return ITEMS.filter(func(it): return it[0] != "#")


static func _remember() -> void:
	if _defaults.is_empty():
		for it in items():
			_defaults[id(it)] = _read(it)


static func _read(it: Array) -> float:
	var s: Script = FILES[it[0]]
	var v = s.get(it[1])
	match it[2]:
		"": return float(v)
		"x": return v.x
		"y": return v.y
		_: return float(v[it[2]])


static func value(it: Array) -> float:
	_remember()
	return _read(it)


static func default_value(it: Array) -> float:
	_remember()
	return _defaults[id(it)]


static func set_value(it: Array, x: float) -> void:
	_remember()
	var s: Script = FILES[it[0]]
	var v = s.get(it[1])
	match it[2]:
		"":
			s.set(it[1], x)
		"x", "y":
			v[it[2]] = x
			s.set(it[1], v)
		_:
			v[it[2]] = x   # 辞書（FEEL）はそのまま書き換わる
			if it[1] == "FEEL":
				s.set(it[2], x)   # いまのワールドの値（sled.gd の glide・pull・bumps・rattle）にもすぐ入れる。ワールドを移ると main.gd が FEEL から入れ直す


static func reset() -> void:
	for it in items():
		set_value(it, default_value(it))


## いまの値をすべて JSON に。{"lodge_ride_tune": 1, "sled": {"FEEL": {...}, "CRASH_UP": [x, y], ...}, "flung": {...}, "player": {...}}
static func to_json() -> String:
	var out := {"lodge_ride_tune": FORMAT}
	for it in items():
		var f: Dictionary = out.get_or_add(it[0], {})
		var s: Script = FILES[it[0]]
		var v = s.get(it[1])
		if v is Vector2:
			f[it[1]] = [_round(v.x), _round(v.y)]
		elif v is Dictionary:
			var d: Dictionary = f.get_or_add(it[1], {})
			d[it[2]] = _round(float(v[it[2]]))
		else:
			f[it[1]] = _round(float(v))
	return JSON.stringify(out, "  ", false)


## JSON から値を入れる。入れた項目の数を返す（読めなければ -1）。一覧にない鍵は無視する
static func from_json(text: String) -> int:
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		return -1
	var n := 0
	for it in items():
		var x = pick(data, it)
		if x != null:
			set_value(it, x)
			n += 1
	return n


## JSON を読んだ辞書から、その項目の数を取り出す（なければ null）
static func pick(data: Dictionary, it: Array):
	var f = data.get(it[0])
	if not f is Dictionary:
		return null
	var v = f.get(it[1])
	match it[2]:
		"":
			return float(v) if v is float or v is int else null
		"x", "y":
			if v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
				return float(v[0 if it[2] == "x" else 1])
			return null
		_:
			if v is Dictionary and (v.get(it[2]) is float or v.get(it[2]) is int):
				return float(v[it[2]])
			return null


## JSON に書く数は 5 桁で丸める（0.1 + 0.2 のような端の数を出さない）
static func _round(x: float) -> float:
	return snappedf(x, 0.00001)
