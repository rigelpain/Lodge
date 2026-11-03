extends Node3D
## 2 階の染め桶: 衣装掛けのとなりの、木の板を輪で締めた桶。中に染め液が張ってあり、縁に染めたフェルトが掛かり、櫂が立てかけてある。
## 前で F を押すと、服を染める画面（dye_ui.gd）が開く（2026-11-01 代表「服の色変え」「染色桶をつくって、色に払うんじゃなくて染色代として払う」）。
## だれかが染めると（craft.gd の出来事 dye）、染め液と縁のフェルトが、その人の染めた色にじわっと変わる。
## 置き方は main.gd の _put_wardrobe（衣装掛けの竿の端の、少し前）。この節の +Z が桶の正面

const Look := preload("res://look.gd")

const R := 0.36              # 桶の口の半径 (m)
const H := 0.58              # 桶の高さ
const STAVES := 14           # 側板の数
const REACH := 1.8           # この距離 (m) の内で、桶の方を向いていれば F で開ける
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
	var wood := Look.wood(Color(0.60, 0.43, 0.27))
	var dark := Look.wood(Color(0.38, 0.26, 0.16))
	# 側板: 口のほうが少し広い。板ごとに色をわずかに変える（寄せ木の桶）
	var w := TAU * R / STAVES * 1.04
	for i in STAVES:
		var a := TAU * i / STAVES
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, H, 0.035)
		mi.mesh = bm
		mi.material_override = wood if i % 3 else dark
		var out := Vector3(sin(a), 0, cos(a))
		mi.position = out * (R * 0.93) + Vector3.UP * H / 2.0
		mi.rotation = Vector3(0, a, 0)
		mi.rotate_object_local(Vector3.RIGHT, -0.06)   # 上へ開く
		add_child(mi)
	# 底
	var bottom := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = R * 0.9
	bc.bottom_radius = R * 0.9
	bc.height = 0.04
	bottom.mesh = bc
	bottom.material_override = dark
	bottom.position.y = 0.03
	add_child(bottom)
	# 締めの輪（撚った麻縄の色）2 本
	var rope := Look.cloth(Color(0.70, 0.58, 0.38), 18.0)
	for y in [0.12, H - 0.1]:
		var hoop := MeshInstance3D.new()
		var tm := TorusMesh.new()
		var rr: float = R * (0.93 + 0.1 * (y / H)) + 0.012
		tm.inner_radius = rr - 0.02
		tm.outer_radius = rr + 0.02
		tm.rings = 28
		hoop.mesh = tm
		hoop.material_override = rope
		hoop.position.y = y
		add_child(hoop)
	# 染め液: 縁の少し下に張った、色のフェルト（つるつるにしない）
	_liquid = Look.felt(START, 2.0)
	var liq := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = R * 0.97
	lc.bottom_radius = R * 0.97
	lc.height = 0.02
	liq.mesh = lc
	liq.material_override = _liquid
	liq.position.y = H - 0.07
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
	# 櫂（かき混ぜる板）: 桶の中から、うしろの縁に立てかける
	var paddle := Node3D.new()
	paddle.position = Vector3(0.08, H - 0.15, -R * 0.4)
	paddle.rotation = Vector3(-0.42, 0.3, 0.1)
	add_child(paddle)
	var shaft := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.016
	sc.bottom_radius = 0.016
	sc.height = 0.75
	shaft.mesh = sc
	shaft.material_override = wood
	shaft.position.y = 0.3
	paddle.add_child(shaft)
	var blade := MeshInstance3D.new()
	var blb := BoxMesh.new()
	blb.size = Vector3(0.11, 0.2, 0.02)
	blade.mesh = blb
	blade.material_override = wood
	blade.position.y = -0.12
	paddle.add_child(blade)
	# 当たり（桶は通り抜けられない）
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = R + 0.04
	cyl.height = H
	col.shape = cyl
	col.position.y = H / 2.0
	body.add_child(col)
	add_child(body)
	if craft:
		craft.happened.connect(_on_craft)


## あなたが桶の前で、桶の方を向いているか
func can_use(p: Node3D) -> bool:
	var d := global_position - p.global_position
	if absf(d.y) > 1.5:
		return false
	d.y = 0
	if d.length() > REACH:
		return false
	return (-p.global_basis.z).dot(d.normalized()) > 0.5 or d.length() < 0.7


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
