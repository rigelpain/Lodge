extends Node3D
## 1 階の染めと着替えの施設: 大きな人台。人台の裾が布のスカートになって桶に浸かり、腰の輪に、選べる人形（doll.gd の KINDS）が
## 小さくなって 1 体ずつハンガーで掛かる。天井の輪から長い布が後ろを囲んで桶へ落ちる（2026-11-04 代表「染め桶と衣装掛けは一つの施設に」。
## 案の絵と形の台本は design/dye-wardrobe/）。人形の高さを見て F で人形を選び直す画面（wardrobe_ui.gd）、桶を見下ろして F で服を染める画面（dye_vat.gd）。
## いま自分が着ている人形のハンガーは空になる（その人形を着て出ている、と輪を見ればわかる。文字は出さない）。
## 掛かった人形は、輪の下で 12 コマで少し揺れる。人形の glb は重いので、あなたが近づいて（NEAR_LOAD）から掛ける。
## 置き方は main.gd（ロッジの 1 階の東、紙細工屋さんのテントの東どなり）。この節の FRONT（+Z）が人台の正面。後ろは長い布

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Props := preload("res://props.gd")

const BODY_GLB := "res://props/dress_form/dress_form.glb"
const HOOP_R := 1.5          # 腰の輪の半径 (m)。design/dye-wardrobe/ideas.py と同じ
const TUB_R := 1.86          # 桶の外の半径
const ARC_STEP := PI / 5.0   # 人形の間の角度（36°）
const RAIL_Y := 1.85         # 腰の輪の高さ
const HANG := 0.62           # 掛けた人形の背丈 (m)。人形ごとの背の違いはそろえる（遠くからでも同じ大きさの札に見える）
const REACH := 3.5           # 人台の真ん中からこの距離 (m) の内で、人台の方を向いていれば F で開ける
const BACK_LIMIT := -0.8     # 人台の前からの位置がこれより後ろ（長い布の側）では、人形は選べない
const NEAR_LOAD := 30.0      # あなたがこの距離まで来たら、人形を掛ける
const FRONT := Vector3.BACK  # 人台の正面（この節の座標）。ハンガーの節の +Z は、それぞれ外向き

var player: Node3D           # main.gd が入れる
var _hangers := {}           # 人形 → [ハンガーの節（竿で揺れる）, 人形の節]
var _loaded := false
var _frame := -1
var _check_t := 0.0


func _ready() -> void:
	var body := Props.make(BODY_GLB)
	body.rotation.y = PI   # glb の正面（Blender の +Y＝Godot の -Z）を、この節の正面 +Z へ
	add_child(body)
	# 長い布と裾は 1 枚の面なので、裏からも見えるように
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is BaseMaterial3D:
				var both: BaseMaterial3D = mat.duplicate()
				both.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.set_surface_override_material(i, both)
	# 当たり（桶の中へは入れない。縁に跳び乗れないよう、高めの円柱）
	var solid := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = TUB_R
	cyl.height = 3.0
	col.shape = cyl
	col.position.y = 1.5
	solid.add_child(col)
	add_child(solid)
	# ハンガー（木の三角と、針金のかぎ）。腰の輪の前の側に並べ、外を向ける。人形は近づいてから掛ける
	var wood := Look.wood(Color(0.50, 0.33, 0.20))
	var n := Doll.KINDS.size()
	for i in n:
		var k: String = Doll.KINDS[i]
		var a := (i - (n - 1) * 0.5) * ARC_STEP
		var holder := Node3D.new()
		holder.position = Vector3(sin(a), 0, cos(a)) * HOOP_R + Vector3.UP * RAIL_Y
		holder.rotation.y = a
		add_child(holder)
		var pivot := Node3D.new()
		holder.add_child(pivot)
		_hanger(pivot, wood)
		_hangers[k] = [pivot, null]


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
		# 人形の体は -Z が前（doll.gd の _yaw と同じ）。ハンガーの節の外向き（+Z）へ向ける
		inst.basis = Basis(Vector3.UP, atan2(-FRONT.x, -FRONT.z)).scaled(Vector3.ONE * s)
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


## あなたが人台の前の側にいて、人形の高さを見ているか（桶を見下ろしていれば、染め桶のほう。dye_vat.gd）
func can_use(p: Node3D) -> bool:
	if to_local(p.global_position).dot(FRONT) < BACK_LIMIT or p.looks_down():
		return false
	return near_and_facing(p)


## 人台に手が届く所で、人台の方を向いているか（dye_vat.gd も使う）
func near_and_facing(p: Node3D) -> bool:
	var d := global_position - p.global_position
	if absf(d.y) > 1.5:
		return false
	d.y = 0
	return d.length() <= REACH and (-p.global_basis.z).dot(d.normalized()) > 0.5


## 案内の絵を出す所: あなたの側の腰の輪の上
func hint_at(p: Node3D) -> Vector3:
	var d := p.global_position - global_position
	d.y = 0
	return global_position + d.normalized() * HOOP_R + Vector3.UP * (RAIL_Y + 0.45)


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
