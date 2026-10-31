extends Node3D
## 2 階の衣装掛け: 木の竿に、選べる人形（doll.gd の KINDS）が小さくなって 1 体ずつハンガーに掛かっている。
## 前で F を押すと、人形を選び直す画面（wardrobe_ui.gd）が開く（2026-10-31 代表「キャラチェンジとほかキャラの実装も」。場所は 2 階の衣装掛け）。
## いま自分が着ている人形のハンガーは空になる（その人形を着て出ている、と竿を見ればわかる。文字は出さない）。
## 掛かった人形は、竿の下で 12 コマで少し揺れる。人形の glb は重いので、あなたが近づいて（NEAR_LOAD）から掛ける。
## 置き方は main.gd の _put_wardrobe（ロッジの 2 階、内階段を上がった東の端の壁ぎわ）。この節の +Z が竿の正面

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")

const WIDTH := 3.7           # 竿の長さ (m)
const RAIL_Y := 1.85         # 竿の高さ
const HANG := 0.62           # 掛けた人形の背丈 (m)。人形ごとの背の違いはそろえる（遠くからでも同じ大きさの札に見える）
const REACH := 2.3           # この距離 (m) の内で、竿の方を向いていれば F で開ける
const NEAR_LOAD := 30.0      # あなたがこの距離まで来たら、人形を掛ける

var player: Node3D           # main.gd が入れる
var _hangers := {}           # 人形 → [ハンガーの節（竿で揺れる）, 人形の節]
var _loaded := false
var _frame := -1
var _check_t := 0.0


func _ready() -> void:
	var wood := Look.wood(Color(0.50, 0.33, 0.20))
	var dark := Look.wood(Color(0.36, 0.24, 0.15))
	# 柱 2 本と、床に寝かせた脚。竿は丸棒
	for s in [-1.0, 1.0]:
		_box(Vector3(0.09, RAIL_Y + 0.08, 0.09), Vector3(s * (WIDTH / 2.0 + 0.04), (RAIL_Y + 0.08) / 2.0, 0), wood)
		_box(Vector3(0.12, 0.08, 0.7), Vector3(s * (WIDTH / 2.0 + 0.04), 0.04, 0), dark)
		var knob := MeshInstance3D.new()   # 柱の頭の丸い飾り
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.12
		knob.mesh = sm
		knob.material_override = dark
		knob.position = Vector3(s * (WIDTH / 2.0 + 0.04), RAIL_Y + 0.13, 0)
		add_child(knob)
	var rail := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.028
	cm.bottom_radius = 0.028
	cm.height = WIDTH + 0.1
	rail.mesh = cm
	rail.material_override = wood
	rail.rotation.z = PI / 2.0
	rail.position.y = RAIL_Y
	add_child(rail)
	# 足もとの藍のフェルトの敷物（ここで着替える所、と遠くからわかる）
	var mat := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(WIDTH + 0.6, 0.015, 1.5)
	mat.mesh = bm
	mat.material_override = Look.felt(Color(0.17, 0.21, 0.36), 1.5)
	mat.position = Vector3(0, 0.008, 0.55)
	add_child(mat)
	# 当たり（竿の下はくぐれない）
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH + 0.2, RAIL_Y + 0.2, 0.45)
	col.shape = box
	col.position.y = (RAIL_Y + 0.2) / 2.0
	body.add_child(col)
	add_child(body)
	# ハンガー（木の三角と、針金のかぎ）。人形は近づいてから掛ける
	var n := Doll.KINDS.size()
	for i in n:
		var k: String = Doll.KINDS[i]
		var pivot := Node3D.new()
		pivot.position = Vector3((i - (n - 1) * 0.5) * WIDTH / n, RAIL_Y, 0)
		add_child(pivot)
		_hanger(pivot, wood)
		_hangers[k] = [pivot, null]


func _box(size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	add_child(mi)


func _hanger(pivot: Node3D, wood: Material) -> void:
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.55, 0.55, 0.58)
	wire.metallic = 0.7
	wire.roughness = 0.4
	var hook := MeshInstance3D.new()   # 竿に掛かったかぎ
	var tm := TorusMesh.new()
	tm.inner_radius = 0.028
	tm.outer_radius = 0.04
	hook.mesh = tm
	hook.material_override = wire
	hook.rotation.z = PI / 2.0
	pivot.add_child(hook)
	var neck := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006
	cm.bottom_radius = 0.006
	cm.height = 0.07
	neck.mesh = cm
	neck.material_override = wire
	neck.position.y = -0.06
	pivot.add_child(neck)
	for s in [-1.0, 1.0]:   # 木の肩（なだらかな山形）
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.21, 0.025, 0.03)
		arm.mesh = bm
		arm.material_override = wood
		arm.position = Vector3(s * 0.095, -0.115, 0)
		arm.rotation.z = -0.32 * s
		pivot.add_child(arm)


## 人形を掛ける（近づいてから一度だけ）
func _load_dolls() -> void:
	_loaded = true
	for k in _hangers:
		var top: float = Doll.TOP[k]
		var s := HANG / top
		var inst: Node3D = (load(Doll.SCENES[k]) as PackedScene).instantiate()
		inst.scale = Vector3.ONE * s
		inst.position = Vector3(0, -0.1 - HANG, 0)   # 頭のてっぺんがハンガーの肩の下
		(_hangers[k][0] as Node3D).add_child(inst)
		_hangers[k][1] = inst


## いま着ている人形のハンガーを空にする
func _show_worn() -> void:
	var worn := ""
	if player and player.get("doll"):
		worn = player.doll.kind
	for k in _hangers:
		var d: Node3D = _hangers[k][1]
		if d:
			d.visible = k != worn


## あなたが竿の前で、竿の方を向いているか
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
			_load_dolls()
	if not _loaded:
		return
	_show_worn()
	# 12 コマで、掛かった人形が少しずつ違う向きに揺れる
	var f := Doll.frame_index()
	if f == _frame:
		return
	_frame = f
	var i := 0
	for k in _hangers:
		var pv: Node3D = _hangers[k][0]
		var t := f / 12.0 + i * 1.7
		pv.rotation = Vector3(0.035 * sin(t * 1.3), 0.12 * sin(t * 0.7), 0.025 * sin(t * 1.9))
		i += 1
