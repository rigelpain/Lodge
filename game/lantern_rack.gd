extends Node3D
## パッチワークのおじいさんの番台の横の、ランタン掛け（2026-11-01 代表「番台の横にランタン掛け」。案の絵 design/lantern-variety/01-sheet.jpg）。
## 店番はいない、木の掛け: 2 本の柱に竿を上下 2 本渡し、ランタン（lantern.gd の LOOKS）を 5 つずつ灯して提げる（上の段 L1〜L5、下の段 L6〜L10。
## 案の絵と同じ並び）。下に赤いフェルトを掛けた低い台と、木の料金箱（ボタンを入れる口）。
## 前で F を押すと、買って提げ替える画面（lantern_ui.gd）が開く。提げたランタンは 12 コマでゆらゆら揺れ、形ごとの揺らぎ方で光る。
## 並べるランタンは、あなたが近づいて（NEAR_LOAD）から置く。置き方は main.gd の _put_lantern_rack（番台の横）。この節の +Z が掛けの正面

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Lantern := preload("res://lantern.gd")

const WIDTH := 1.5           # 柱から柱まで (m)
const RODS := [1.92, 1.32]   # 竿の高さ（上の段・下の段, m）
const TABLE := Vector3(1.3, 0.62, 0.42)   # 下の台の幅・高さ・奥行き (m)
const SIZE := 1.15           # 提げるランタンの大きさ（帯に提げるのは人形に合わせて縮めるが、ここは実寸より少し大きく）
const REACH := 2.4           # この距離 (m) の内で、掛けの方を向いていれば F で開ける
const NEAR_LOAD := 30.0      # あなたがこの距離まで来たら、ランタンを並べる

var player: Node3D           # main.gd が入れる
var _loaded := false
var _hung: Array = []        # [節, 光る紙の素材, 揺らぎ方, ずらし]
var _frame := -1
var _check_t := 0.0
var _t := 0.0


func _ready() -> void:
	var wood := Look.wood(Color(0.50, 0.33, 0.20))
	var dark := Look.wood(Color(0.36, 0.24, 0.15))
	var top: float = RODS[0]
	# 柱と足（前後に広げた板）
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.06, top + 0.08, 0.06), Vector3(sx * WIDTH / 2.0, (top + 0.08) / 2.0, -0.12), dark)
		_box(Vector3(0.1, 0.05, 0.6), Vector3(sx * WIDTH / 2.0, 0.025, -0.08), dark)
	# 竿（丸い木）。両端に真鍮の小さなつまみ
	for y in RODS:
		var rod := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.018
		cm.height = WIDTH + 0.16
		rod.mesh = cm
		rod.material_override = wood
		rod.rotation.z = PI / 2.0
		rod.position = Vector3(0, float(y), -0.12)
		add_child(rod)
	# 下の台: 天板と脚。赤いフェルトを掛けて前に垂らす
	_box(Vector3(TABLE.x, 0.04, TABLE.z), Vector3(0, TABLE.y - 0.02, 0.12), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.05, TABLE.y - 0.04, 0.05), Vector3(sx * (TABLE.x / 2.0 - 0.05), (TABLE.y - 0.04) / 2.0, 0.12 + sz * (TABLE.z / 2.0 - 0.05)), dark)
	var felt := Look.felt(Color(0.72, 0.22, 0.20), 1.5)
	_box(Vector3(TABLE.x + 0.04, 0.012, TABLE.z + 0.04), Vector3(0, TABLE.y + 0.006, 0.12), felt)
	_box(Vector3(TABLE.x + 0.04, 0.2, 0.012), Vector3(0, TABLE.y - 0.09, 0.12 + TABLE.z / 2.0 + 0.02), felt)
	# 料金箱: 木の箱に、ボタンを入れる口（黒い細い溝）と、真鍮のボタンを 1 枚（2 階の売り台と同じ）
	var tt := TABLE.y + 0.012
	_box(Vector3(0.22, 0.16, 0.16), Vector3(0.38, tt + 0.08, 0.18), wood)
	_box(Vector3(0.12, 0.005, 0.018), Vector3(0.38, tt + 0.162, 0.18), Look.felt(Color(0.08, 0.06, 0.05)))
	var coin := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.025
	cc.bottom_radius = 0.025
	cc.height = 0.006
	coin.mesh = cc
	coin.material_override = Look.shine("brass")
	coin.position = Vector3(0.45, tt + 0.165, 0.21)
	add_child(coin)
	# 掛けのまわりをほんのり照らす灯り（ランタンごとには灯さない。影なし）
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.46)
	lamp.light_energy = 0.7
	lamp.omni_range = 3.2
	lamp.shadow_enabled = false
	lamp.position = Vector3(0, 1.5, 0.35)
	add_child(lamp)
	# 当たり（柱と台）
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH + 0.1, top + 0.1, 0.7)
	col.shape = box
	col.position = Vector3(0, (top + 0.1) / 2.0, 0.0)
	body.add_child(col)
	add_child(body)


func _box(size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	add_child(mi)


## ランタンを並べる（近づいてから一度だけ）。光る紙は 1 つずつ素材を写して、形ごとの揺らぎ方で明るさを変える
func _load_goods() -> void:
	_loaded = true
	var per := 5
	for i in Lantern.LOOKS.size():
		var look: String = Lantern.LOOKS[i]
		var row := i / per
		var x := (float(i % per) - (per - 1) / 2.0) * (WIDTH - 0.2) / (per - 1)
		var hang := Node3D.new()
		hang.position = Vector3(x, float(RODS[row]) - 0.012, -0.12)
		add_child(hang)
		var made := Lantern.make_body(look)
		var b: Node3D = made[0]
		b.scale = Vector3.ONE * SIZE
		hang.add_child(b)
		var mat: StandardMaterial3D = null
		for m in made[1]:
			if mat == null:
				var src := (m as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
				mat = src.duplicate() if src else null
			if mat:
				(m as MeshInstance3D).set_surface_override_material(0, mat)
		_hung.append([hang, mat, String(Lantern.LOOK[look].style), randf() * 100.0, b])


## あなたが掛けの前で、掛けの方を向いているか
func can_use(p: Node3D) -> bool:
	var d := global_position - p.global_position
	if absf(d.y) > 1.5:
		return false
	d.y = 0
	if d.length() > REACH:
		return false
	return (-p.global_basis.z).dot(d.normalized()) > 0.35 or d.length() < 0.8


func _process(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_check_t -= dt
	if not _loaded and _check_t <= 0.0:
		_check_t = 0.5
		if player.global_position.distance_to(global_position) < NEAR_LOAD:
			_load_goods()
	if not _loaded:
		return
	_t += dt
	for h in _hung:   # 光の揺らぎは毎フレーム（なめらかに）
		var m: StandardMaterial3D = h[1]
		if m:
			m.emission_energy_multiplier = 1.6 * Lantern.flicker(h[2], _t, h[3])
	var f := Doll.frame_index()
	if f == _frame:
		return
	_frame = f
	# 12 コマで、提げたランタンがゆらゆら揺れる（ランタンごとに違う間合い）。糸玉は提げ紐のまわりに回る
	for i in _hung.size():
		var h: Array = _hung[i]
		var k := float(f) / 12.0
		(h[0] as Node3D).rotation = Vector3(0.05 * sin(k * 1.1 + i * 1.7), 0.0, 0.07 * sin(k * 0.8 + i * 2.3))
		if h[2] == "spin":
			(h[4] as Node3D).rotation.y = k * 0.5
