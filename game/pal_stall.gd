extends Node3D
## 2 階の衣装掛けの横の、頭・肩の小物とミニオンの売り台（2026-11-01 代表「衣装掛けで買って替える」）。
## 店番はいない、木の台の無人の売り場: フェルトを掛けた台の上に、止まり木（木の T 字の棒）に小鳥と鶴とどんぐり、
## 台の端に子狐とカエルが座って並び、手前に木の料金箱（ボタンを入れる口）。前で F を押すと、買って付け替える画面（pals_ui.gd）が開く。
## 並べた品物は、あなたが近づいて（NEAR_LOAD）から置く。台の生き物は 12 コマでときどき首を振る。
## 置き方は main.gd の _put_wardrobe（衣装掛けの横）。この節の +Z が台の正面

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Pals := preload("res://pals.gd")

const TABLE := Vector3(1.3, 0.78, 0.6)   # 台の幅・高さ・奥行き (m)
const REACH := 2.3           # この距離 (m) の内で、台の方を向いていれば F で開ける
const NEAR_LOAD := 30.0      # あなたがこの距離まで来たら、品物を並べる
const SHOW_PERCH := [["chiyo_bird", Vector3(-0.38, 0.0, 0.0)], ["crane", Vector3(-0.06, 0.0, 0.0)], ["blue_bird", Vector3(0.26, 0.0, 0.0)]]
## ミニオンは山師の売り物になった（2026-11-02 代表「ミニオンは山師が育てているのを買う感じにしてほしい」。mountain_man.gd の柵）ので、台には並べない
const SHOW_PET := []

var player: Node3D           # main.gd が入れる
var _loaded := false
var _heads: Array = []       # 首を振る部品
var _frame := -1
var _check_t := 0.0


func _ready() -> void:
	var wood := Look.wood(Color(0.50, 0.33, 0.20))
	var dark := Look.wood(Color(0.36, 0.24, 0.15))
	# 台: 天板と 4 本の脚。天板に赤いフェルトを掛け、前に垂らす
	_box(Vector3(TABLE.x, 0.05, TABLE.z), Vector3(0, TABLE.y - 0.025, 0), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.06, TABLE.y - 0.05, 0.06), Vector3(sx * (TABLE.x / 2.0 - 0.06), (TABLE.y - 0.05) / 2.0, sz * (TABLE.z / 2.0 - 0.06)), dark)
	var felt := Look.felt(Color(0.72, 0.22, 0.20), 1.5)
	_box(Vector3(TABLE.x + 0.04, 0.012, TABLE.z + 0.04), Vector3(0, TABLE.y + 0.006, 0), felt)
	_box(Vector3(TABLE.x + 0.04, 0.22, 0.012), Vector3(0, TABLE.y - 0.1, TABLE.z / 2.0 + 0.02), felt)
	# 止まり木: 木の T 字の棒
	var top := TABLE.y + 0.012
	_box(Vector3(0.05, 0.36, 0.05), Vector3(-0.06, top + 0.18, -0.12), dark)
	_box(Vector3(0.9, 0.035, 0.035), Vector3(-0.06, top + 0.36, -0.12), dark)
	_box(Vector3(0.3, 0.03, 0.22), Vector3(-0.06, top + 0.015, -0.12), dark)
	# 料金箱: 木の箱に、ボタンを入れる口（黒い細い溝）と、真鍮のボタンを 1 枚
	_box(Vector3(0.22, 0.16, 0.16), Vector3(0.0, top + 0.08, 0.17), wood)
	_box(Vector3(0.12, 0.005, 0.018), Vector3(0.0, top + 0.162, 0.17), Look.felt(Color(0.08, 0.06, 0.05)))
	var coin := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 0.006
	coin.mesh = cm
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.78, 0.60, 0.26)
	brass.metallic = 0.7
	brass.roughness = 0.35
	coin.material_override = brass
	coin.position = Vector3(0.07, top + 0.165, 0.2)
	add_child(coin)
	# 当たり
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TABLE.x, TABLE.y + 0.1, TABLE.z)
	col.shape = box
	col.position.y = (TABLE.y + 0.1) / 2.0
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


## 品物を並べる（近づいてから一度だけ）
func _load_goods() -> void:
	_loaded = true
	var top := TABLE.y + 0.012
	for g in SHOW_PERCH:
		var n: Node3D = Pals.scene(g[0]).instantiate()
		Pals.paint(n, 1)
		n.position = Vector3(-0.06, top + 0.38, -0.12) + (g[1] as Vector3)
		n.scale = Vector3.ONE * 0.8
		add_child(n)
		var h := n.find_child("head", true, false)
		if h:
			_heads.append(h)
	for g in SHOW_PET:
		var n: Node3D = Pals.scene(g[0]).instantiate()
		Pals.paint(n, 1)
		n.position = Vector3(0, top, 0) + (g[1] as Vector3)
		n.scale = Vector3.ONE * float(g[2])
		n.rotation.y = PI + (0.4 if (g[1] as Vector3).x < 0 else -0.4)   # 正面（+Z）を向いて座る
		add_child(n)
		for c in n.get_children():
			(c as Node3D).visible = Pals.part_name(c) == "sit"
			if Pals.part_name(c) == "sit":
				var h := c.find_child("head*", false, false)
				if h:
					_heads.append(h)
	for h in _heads:
		(h as Node3D).rotation.y = 0.0


## あなたが台の前で、台の方を向いているか
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
	var f := Doll.frame_index()
	if f == _frame:
		return
	_frame = f
	# 12 コマで、並んだ生き物がときどき首を振る（品物ごとに違う間合い）
	for i in _heads.size():
		var k := (f + i * 13) % 50
		var h: Node3D = _heads[i]
		h.rotation = Vector3(0.0, 0.5 * sin(float((f + i * 13) / 50) * 2.1) if k < 30 else 0.0, 0.25 if k > 44 else 0.0)
