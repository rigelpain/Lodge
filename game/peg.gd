extends Node3D
## ソリを斜面に留めるペグ（2026-11-01 代表「ペグを売って欲しい。斜面にそりを留める消耗品があると休憩したり焚き火ができる。」）。
## 形は大きな待ち針: 木の杭の先を尖らせ、上に毛糸を巻き、てっぺんにフェルトの玉。玉の色は刺した人のキャラの色。
## ソリの引き紐の先を、玉の下の巻きに結ぶ（sled_rope.gd が紐の先をここへ留める）。
## 留める力はソリが持つ（sled.gd の peg_to・unpeg）。これは見た目と、刺す・抜く動き（12 コマ／秒に刻む）だけ。
## 抜いたペグは先が曲がって使えなくなる（使い切り）。抜く動きのあと、雪の上に倒れて消える。

const Look := preload("res://look.gd")

const SCALE := 1.5           # 下の寸法をまとめて大きくする（ソリの横で、遠くからも待ち針の玉が見えるように）
const LEN := 0.62            # 杭の長さ（玉まで, m。SCALE の前）
const DEPTH := 0.24          # 雪に刺さる深さ (m)
const TIE_Y := 0.27          # 紐を結ぶ巻きの高さ（雪から, m）
const HEAD_R := 0.055        # 玉の半径 (m)
const SHAFT_R := 0.022       # 杭の太さ（半径, m）
const WOOD := Color(0.78, 0.62, 0.42)    # 白木
const YARN := Color(0.93, 0.89, 0.80)    # 生成りの毛糸

var color := Color(0.80, 0.24, 0.20)     # 玉の色（刺した人のキャラの色）
var _shape: Node3D
var _k := -1                 # 動きのコマ（-1 は止まっている）
var _pulling := false
var _t := 0.0


## ペグの形（原点が雪の面。+Y が上。SCALE 倍の大きさ）。手に持つ形にも使う（player.gd の held_shape）
static func make(head: Color) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * SCALE
	var wood := Look.wood(WOOD)
	var yarn := Look.knit(YARN, 14.0)
	var band := Look.knit(head.lerp(Color(0.95, 0.92, 0.85), 0.35), 14.0)
	var felt := Look.felt(head, 2.0)
	var below := LEN - DEPTH
	# 杭: 先を尖らせた白木（雪の中に DEPTH ぶん）
	var sh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = SHAFT_R
	cm.bottom_radius = SHAFT_R * 1.15
	cm.height = LEN - 0.1
	cm.radial_segments = 10
	sh.mesh = cm
	sh.material_override = wood
	sh.position.y = below - cm.height * 0.5
	root.add_child(sh)
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = SHAFT_R * 1.15
	tm.bottom_radius = 0.002
	tm.height = 0.1
	tm.radial_segments = 10
	tip.mesh = tm
	tip.material_override = wood
	tip.position.y = -DEPTH + 0.05
	root.add_child(tip)
	# 毛糸の巻き: 紐を結ぶ所（生成り、太め）と、その上に玉の色を淡くした細い巻きを 2 本
	_ring(root, TIE_Y, 0.06, SHAFT_R + 0.012, yarn)
	_ring(root, TIE_Y + 0.075, 0.018, SHAFT_R + 0.008, band)
	_ring(root, TIE_Y + 0.11, 0.018, SHAFT_R + 0.008, band)
	# 巻きの終わりの糸の垂れ（短い 2 本）
	for s in [-1.0, 1.0]:
		var tail := MeshInstance3D.new()
		var tl := CylinderMesh.new()
		tl.top_radius = 0.004
		tl.bottom_radius = 0.004
		tl.height = 0.07
		tl.radial_segments = 5
		tail.mesh = tl
		tail.material_override = yarn
		tail.position = Vector3(SHAFT_R + 0.012, TIE_Y - 0.05, s * 0.008)
		tail.rotation.z = 0.25 + s * 0.08
		root.add_child(tail)
	# 頭: 待ち針のフェルトの玉。てっぺんに縫い目の十字
	var hd := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = HEAD_R
	sm.height = HEAD_R * 1.9
	sm.radial_segments = 16
	sm.rings = 8
	hd.mesh = sm
	hd.material_override = felt
	hd.position.y = below + HEAD_R * 0.8
	root.add_child(hd)
	var thread := Look.felt(Color(0.97, 0.95, 0.90), 6.0)
	for r in [0.0, PI / 2]:
		var st := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(HEAD_R * 0.9, 0.006, 0.008)
		st.mesh = bm
		st.material_override = thread
		st.position.y = below + HEAD_R * 0.8 + HEAD_R * 0.93
		st.rotation.y = r
		root.add_child(st)
	return root


static func _ring(root: Node3D, y: float, h: float, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = m
	mi.position.y = y
	root.add_child(mi)


func _ready() -> void:
	top_level = true   # ソリの子だが、刺した所（世界）に留まる。ソリが消えると一緒に消える
	_shape = make(color)
	add_child(_shape)


## 紐を結ぶ所（世界）
func tie_point() -> Vector3:
	return global_position + Vector3.UP * TIE_Y * SCALE


## 刺す: 上から振り下ろして雪に打ち込む（4 コマ）。雪がぱっと散る
func drive() -> void:
	_k = 0
	_pulling = false
	_t = 0.0
	_shape.position.y = 0.45
	_puff()


## 抜く: 引き上げ、先の曲がったペグが雪の上に倒れて、沈んで消える（ペグは使い切り）
func pull_out() -> void:
	_k = 0
	_pulling = true
	_t = 0.0
	_puff()


func _process(dt: float) -> void:
	if _k < 0:
		return
	_t += dt
	var k := int(_t * 12.0)
	if k == _k:
		return
	_k = k
	if not _pulling:
		var ys := [0.45, 0.15, -0.04, 0.0]
		_shape.position.y = ys[mini(k, ys.size() - 1)]
		if k >= ys.size():
			_k = -1
		return
	# 抜く: 2 コマで引き上げ、3 コマで倒れ、そのあと雪に沈んで消える
	if k <= 2:
		_shape.position.y = DEPTH * SCALE * 0.5 * k
	elif k <= 5:
		var f := (k - 2) / 3.0
		_shape.position.y = lerpf(DEPTH * SCALE, 0.03, f)
		_shape.rotation.z = lerpf(0.0, PI / 2 - 0.1, f)
	elif k <= 14:
		_shape.position.y = 0.03 - (k - 5) * 0.012
		_shape.scale = Vector3.ONE * SCALE * lerpf(1.0, 0.6, (k - 5) / 9.0)
	else:
		queue_free()


## 雪がぱっと散る（白い綿の粒が数コマ跳ねる）
func _puff() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = Look.felt(Color(0.97, 0.97, 0.99), 4.0)
	p.position.y = 0.02
	add_child(p)
	p.emitting = true
