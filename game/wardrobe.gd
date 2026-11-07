extends Node3D
## 1 階の染めと着替えの施設: 大きな人台。人台の裾が布のスカートになって桶に浸かり、腰の輪に、選べる人形（doll.gd の KINDS）が
## 小さくなって 1 体ずつハンガーで掛かる。天井の輪から長い布が後ろを囲んで桶へ落ちる（2026-11-04 代表「染め桶と衣装掛けは一つの施設に」。
## 案の絵と形の台本は design/dye-wardrobe/）。人形の高さを見て F で人形を選び直す画面（wardrobe_ui.gd）、桶を見下ろして F で服を染める画面（dye_vat.gd）。
## いま自分が着ている人形のハンガーは空になる（その人形を着て出ている、と輪を見ればわかる。文字は出さない）。
## 掛かった人形は、輪の下で 12 コマで少し揺れる。人形の glb は重いので、あなたが近づいて（NEAR_LOAD）から掛ける。
## 人が近づくと、人形は腰の輪に沿ってぐるんと 1 周して止まり、長い布は液から昇る（dress_form_cloth.gd）。遠くでは人形を動かさない。
## 置き方は main.gd（ロッジの 1 階の南西の隅、紙細工屋さんのテントの南どなり）。この節の FRONT（+Z）が人台の正面。後ろは長い布

const Doll := preload("res://doll.gd")
const Look := preload("res://look.gd")
const Props := preload("res://props.gd")
const Sense := preload("res://stall_sense.gd")
const Cloth := preload("res://dress_form_cloth.gd")

const BODY_GLB := "res://props/dress_form/dress_form.glb"
const HOOP_R := 1.5          # 腰の輪の半径 (m)。design/dye-wardrobe/ideas.py と同じ
const TUB_R := 1.86          # 桶の外の半径
const ARC_STEP := PI / 5.0   # 人形の間の角度（36°）
const RAIL_Y := 3.12         # 腰の輪の高さ。胴のくびれ（design/dye-wardrobe/ideas.py の WAIST_Z）
const HANG := 0.62           # 掛けた人形の背丈 (m)。人形ごとの背の違いはそろえる（遠くからでも同じ大きさの札に見える）
const REACH := 3.5           # 人台の真ん中からこの距離 (m) の内で、人台の方を向いていれば F で開ける
const BACK_LIMIT := -0.8     # 人台の前からの位置がこれより後ろ（長い布の側）では、使えない
const NEAR_LOAD := 30.0      # あなたがこの距離まで来たら、人形を掛ける
const FRONT := Vector3.BACK  # 人台の正面（この節の座標）。ハンガーの節の +Z は、それぞれ外向き
const SENSE_R := 4.5         # 人台の真ん中からこの距離に人が来ると、人形が回り、長い布と染台の布が昇る (m)。桶の縁から約 2.6 m、F が届く距離（REACH）の 1 m 外。
                             # 2026-11-07 代表「トルソーの検知範囲広いかも。もっと近くで動き出すの」で 8 m から狭めた
const SPIN_ACCEL := 0.024    # 人形の輪: 勢いの増え方・減り方（コマごと、rad）
const SPIN_EASE := 0.14      # 人形の輪: 止まる所へ寄せる強さ
const SPIN_TOP := 0.34       # 人形の輪: いちばん速いとき（コマごと、rad。12 コマで見て回るのが分かる速さ）
const SWING := 1.3           # 回る速さのぶん、人形が外へ振れる
const SWING_MAX := 0.42
const TRAIL := 0.9           # 回る速さのぶん、人形が後ろへ遅れる
const TWIRLS := 1.0          # 輪が 1 周するあいだに、人形がかぎのまわりで回る数

var player: Node3D           # main.gd が入れる
var main: Node               # main.gd が入れる
var near := false            # 近くに人がいる（dress_form_cloth.gd も見る）
var _wheel: Node3D           # ハンガーをまとめて回す節（人台の真ん中）
var _turn := 0.0             # 輪の回った角 (rad)
var _speed := 0.0
var _goal := 0.0             # 輪を止める角（1 周ずつ増える）
var _sense_t := 0.0
var _rested := true          # 人形が振れ終わった
var _past: Array[float] = [] # 少し前までの輪の速さ（人形ごとの遅れに使う）
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
	# 長い布（ふだんは液の中。近づくと昇る）
	var cloth: Node3D = Cloth.new()
	cloth.name = "LongCloth"
	add_child(cloth)
	_wheel = Node3D.new()
	_wheel.name = "DollWheel"
	add_child(_wheel)
	# ハンガー（木の三角と、針金のかぎ）。腰の輪の前の側に並べ、外を向ける。人形は近づいてから掛ける
	var wood := Look.wood(Color(0.50, 0.33, 0.20))
	var n := Doll.KINDS.size()
	for i in n:
		var k: String = Doll.KINDS[i]
		var a := (i - (n - 1) * 0.5) * ARC_STEP
		var holder := Node3D.new()
		holder.position = Vector3(sin(a), 0, cos(a)) * HOOP_R + Vector3.UP * RAIL_Y
		holder.rotation.y = a
		_wheel.add_child(holder)
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


## あなたが人台の前で、人形の高さを見ているか（桶を見下ろしていれば、染め桶のほう。dye_vat.gd）
func can_use(p: Node3D) -> bool:
	return not p.looks_down() and near_and_facing(p)


## 人台の前の側で手が届く所にいて、人台の方を向いているか（dye_vat.gd も使う）。長い布の側とガラスの向こうからは使えない
func near_and_facing(p: Node3D) -> bool:
	if to_local(p.global_position).dot(FRONT) < BACK_LIMIT:
		return false
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
	_sense_t -= dt
	if _sense_t <= 0.0:
		_sense_t = Sense.CHECK
		var now := Sense.nearest(main, self, SENSE_R, BACK_LIMIT) != null
		if now and not near:   # 来るたびに、1 周ぐるんと回る
			_goal = (floorf(_turn / TAU) + 1.0) * TAU
		near = now
	if not near and is_zero_approx(_speed) and _rested:
		return   # 遠くでは人形を動かさない
	var f := Doll.frame_index()
	if f == _frame:
		return
	_frame = f
	_step_wheel()
	var i := 0
	for k in _hangers:
		var pv: Node3D = _hangers[k][0]
		var t := f / 12.0 + i * 1.7
		# 人形ごとに少し遅れて、輪の勢いのぶん外へ振れ、後ろへ遅れ、かぎのまわりで回る
		var v: float = _speed_at(i)
		var twirl := _turn * TWIRLS - float(i) * 0.25 * clampf(absf(_speed) * 6.0, 0.0, 1.0)
		pv.rotation = Vector3(0.035 * sin(t * 1.3) - minf(absf(v) * SWING, SWING_MAX),
				twirl + 0.12 * sin(t * 0.7), 0.025 * sin(t * 1.9) - v * TRAIL)
		i += 1


## 人形 i が感じる輪の速さ（i コマ前の速さ）
func _speed_at(i: int) -> float:
	return _past[mini(i, _past.size() - 1)] if not _past.is_empty() else 0.0


## 輪を 12 コマごとに進める。来るたびに 1 周: 勢いをつけて回り、止まる所を少し行き過ぎて戻る
## （2026-11-07 代表「トルソーにかかってる人形たちをぐるんとまわしてもいいのに」。回り続ける案と比べて、1 周して止まる案に決めた）
func _step_wheel() -> void:
	var want := clampf((_goal - _turn) * SPIN_EASE, -SPIN_TOP, SPIN_TOP)
	_speed = move_toward(_speed, want, SPIN_ACCEL)
	_turn += _speed
	if absf(_goal - _turn) < 0.004 and absf(_speed) < 0.004:
		_turn = _goal
		_speed = 0.0
	_wheel.rotation.y = _turn
	_past.push_front(_speed)
	if _past.size() > _hangers.size():
		_past.pop_back()
	_rested = _past.all(func(x): return is_zero_approx(x))
