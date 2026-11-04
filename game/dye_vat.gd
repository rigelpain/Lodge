extends Node3D
## 1 階の人台（wardrobe.gd の子）の桶の中の染め液と、縁に掛けた染めたフェルト。桶そのものと櫂は人台の glb。
## 桶を見下ろして F を押すと、服を染める画面（dye_ui.gd）が開く（2026-11-01 代表「服の色変え」「染色桶をつくって、色に払うんじゃなくて染色代として払う」）。
## だれかが染めると（craft.gd の出来事 dye）、染め液と縁のフェルトが、その人の染めた色にじわっと変わる。人台の裾と長い布の色は変わらない。
## この節の +Z が桶の正面

const Look := preload("res://look.gd")

const R := 1.8               # 桶の口の半径 (m)。design/dye-wardrobe/ideas.py の tub と同じ
const H := 0.74              # 桶の高さ
const LIQUID_Y := 0.62       # 染め液の面の高さ
const START := Color(0.17, 0.21, 0.38)   # はじめの染め液（藍）
const SOAK := 1.2            # 染め液の色が変わりきるまでの秒

var player: Node3D           # main.gd が入れる
var craft: Node              # main.gd が入れる（だれかが染めたら、液の色を変える）
var _liquid: StandardMaterial3D
var _cloth: StandardMaterial3D
var _from := START
var _to := START
var _t := 1.0


func _ready() -> void:
	# 染め液: 縁の少し下に張った、色のフェルト（つるつるにしない）
	_liquid = Look.felt(START, 2.0)
	var liq := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = R * 0.98
	lc.bottom_radius = R * 0.98
	lc.radial_segments = 72
	lc.height = 0.02
	liq.mesh = lc
	liq.material_override = _liquid
	liq.position.y = LIQUID_Y
	add_child(liq)
	# 縁に掛けた、染めたフェルトの布（外へ垂れる）
	_cloth = Look.felt(START, 1.5)
	_cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var drape := Node3D.new()
	drape.position = Vector3(0, H + 0.01, R * 0.98)
	add_child(drape)
	for part in [[Vector3(0.24, 0.012, 0.14), Vector3(0, 0, -0.05), 0.15], [Vector3(0.24, 0.012, 0.26), Vector3(0, -0.12, 0.05), 1.35]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		mi.mesh = bm
		mi.material_override = _cloth
		mi.position = part[1]
		mi.rotation.x = part[2]
		drape.add_child(mi)
	if craft:
		craft.happened.connect(_on_craft)


## あなたが人台（親の wardrobe.gd）に手が届く所で、桶を見下ろしているか
func can_use(p: Node3D) -> bool:
	return p.looks_down() and get_parent().near_and_facing(p)


## 案内の絵を出す所: あなたの側の桶の縁の上
func hint_at(p: Node3D) -> Vector3:
	var d := p.global_position - global_position
	d.y = 0
	return global_position + d.normalized() * R + Vector3.UP * (H + 0.35)


## だれかが染めた: 染め液と縁の布を、その人の染めた色（主の色から順に、染めた最初の部位の色）へ
func _on_craft(ev: Dictionary) -> void:
	if ev.get("kind") != "dye":
		return
	for h in ev.get("colors", []):
		if String(h) != "":
			_from = _liquid.albedo_color
			_to = Color(String(h))
			_t = 0.0
			return


func _process(dt: float) -> void:
	if _t >= 1.0:
		return
	_t = minf(1.0, _t + dt / SOAK)
	var c := _from.lerp(_to, smoothstep(0.0, 1.0, _t))
	_liquid.albedo_color = c
	_cloth.albedo_color = c
