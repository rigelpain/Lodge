extends RefCounted
## 山男の棚（山の道具の品書き。2026-11-01 代表「そういう道具類を売ってくれる山男？山師？みたいなキャラが欲しい」）。
## 売り場は mountain_ui.gd、売り子は mountain_man.gd。買うのは craft.gd の buy（ほかの店と同じ出来事。お金はボタン）。
##
## 差しこみ口: 品目ごとに 1 行。item は持ち物に入る形（craft.gd の bags にそのまま入る）、price は木のボタンの何個分、
## on は売るかどうか。on が false の品目は、棚に薄い絵だけ並び（まだ入荷していない札）、買えない（ホストも断る）。
##   焚き火セット {kind: "campfire"}  別の作業（feature/campfire。campfire.gd と craft.gd の fire_lay）が main に入ったら on にする
##   ペグ         {kind: "peg"}       別の作業（feature/sled-peg。斜面にソリを留める消耗品）が main に入ったら on にする。
##                                    束で売るなら item に数を足す（例 {kind: "peg", n: 5}）。値段もそちらの釣り合いで決め直す
## 品目を足すときも、ここに 1 行足し、絵を draw に足す（持ち物の列の絵も craft_icons.gd の item がここを呼ぶ）。

const Icons := preload("res://hud_icons.gd")

const SHELF := [
	{"item": {"kind": "campfire"}, "price": 15, "on": false},
	{"item": {"kind": "peg"}, "price": 5, "on": false},
]

## 確かめ用: true なら on でない品目も売る（--shelf-all。main.gd が入れる）
static var all_on := false


static func has(kind: String) -> bool:
	return entry(kind) != {}


static func entry(kind: String) -> Dictionary:
	for e in SHELF:
		if e.item.kind == kind:
			return e
	return {}


static func price(kind: String) -> int:
	return int(entry(kind).get("price", 99))


## 売っているか（棚にあって on）
static func sold(kind: String) -> bool:
	var e := entry(kind)
	return e != {} and (bool(e.on) or all_on)


## 持ち物の名前（日本語。持ち物の列の上に出す）
static func item_name(it: Dictionary) -> String:
	match it.get("kind", ""):
		"campfire":
			return "焚き火セット"
		"peg":
			return "ペグ"
	return ""


## 品物の絵（64 × 64 の箱。中心が原点、y は下向き。Icons._o と _s は呼ぶ側が決める）
static func draw(ci: CanvasItem, it: Dictionary, a := 1.0) -> void:
	match it.get("kind", ""):
		"campfire":
			_campfire(ci, a)
		"peg":
			_peg(ci, a)


## 焚き火セット: フェルトの石の輪に、毛糸を巻いた薪を三角に組み、布と紙を切った炎（campfire.gd の形）
static func _campfire(ci: CanvasItem, a: float) -> void:
	var stones := [Color(0.55, 0.53, 0.52), Color(0.46, 0.40, 0.36), Color(0.62, 0.60, 0.56), Color(0.42, 0.45, 0.50)]
	for k in 7:   # 奥の石
		var t := PI + PI * k / 6.0
		Icons.patch(ci, Icons.ell(Vector2(cos(t) * 22, 20 + sin(t) * 6), 6, 4.5, 12), stones[k % 4], a, false)
	var flame := [[Color(0.86, 0.26, 0.13), 1.0], [Color(0.96, 0.55, 0.16), 0.7], [Color(1.0, 0.86, 0.42), 0.42]]
	for f in flame:   # 炎（外から赤・橙のフェルト、黄の紙）
		var k: float = f[1]
		Icons.patch(ci, PackedVector2Array([Vector2(-11 * k, 18), Vector2(-9 * k, 4 - 8 * k), Vector2(-3 * k, 6 - 14 * k), Vector2(0, -6 - 20 * k),
				Vector2(4 * k, 4 - 12 * k), Vector2(9 * k, -2 - 6 * k), Vector2(11 * k, 18)]), f[0], a, false)
	var wood := Color(0.55, 0.38, 0.22)
	var yarn := [Color(0.80, 0.24, 0.20), Color(0.88, 0.66, 0.20), Color(0.24, 0.32, 0.55)]
	for k in 3:   # 薪 3 本を三角に。それぞれ毛糸を 2 巻き
		var x0: float = [-17.0, 17.0, -4.0][k]
		var x1: float = [5.0, -5.0, 2.0][k]
		var y0: float = [22.0, 22.0, 24.0][k]
		var d := Vector2(x1 - x0, -22.0).normalized()
		var n := Vector2(-d.y, d.x) * 3.2
		var p0 := Vector2(x0, y0)
		var p1 := Vector2(x1, y0 - 26)
		Icons.patch(ci, PackedVector2Array([p0 - n, p1 - n, p1 + n, p0 + n]), wood.darkened(0.1 * k), a, false)
		for s in [0.3, 0.62]:
			var c := p0.lerp(p1, s)
			Icons.thread(ci, PackedVector2Array([c - n * 1.1, c + n * 1.1]), yarn[k], 2.2, a)
	for k in 6:   # 手前の石
		var t := PI * (k + 0.5) / 6.0
		Icons.patch(ci, Icons.ell(Vector2(cos(t) * 24, 22 + sin(t) * 6), 6.5, 5, 12), stones[(k + 2) % 4], a, k % 2 == 0, Icons.CAP)


## ペグ: 木の杭 2 本を交差させ、頭に毛糸の輪（ソリの綱を掛ける所）。先はとがる
static func _peg(ci: CanvasItem, a: float) -> void:
	var wood := Color(0.62, 0.45, 0.28)
	for k in 2:
		var rot: float = [-0.42, 0.36][k]
		var c := Vector2([-6.0, 7.0][k], 2)
		var body := PackedVector2Array([Vector2(-4, -22), Vector2(4, -22), Vector2(4, 12), Vector2(0, 24), Vector2(-4, 12)])
		Icons.patch(ci, Icons.xf(body, rot, c), wood.darkened(0.12 * k), a, true, Icons.CAP)
		Icons.patch(ci, Icons.xf(Icons.rr(-6, -26, 12, 7, 2), rot, c), wood.darkened(0.3), a, false)   # 打つ頭
		var loop := PackedVector2Array()
		for i in 13:
			var t := TAU * i / 12.0
			loop.append(Vector2(cos(t) * 7, -14 + sin(t) * 4))
		Icons.thread(ci, Icons.xf(loop, rot, c), [Color(0.80, 0.24, 0.20), Color(0.24, 0.32, 0.55)][k], 2.0, a)
