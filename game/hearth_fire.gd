extends Node3D
## ロッジの大きな暖炉の火（hearth_nook.gd が暖炉の品物の子に置く）。外の焚き火（campfire.gd）と同じ手芸の形:
##   薪: 巻いたフェルトのロール（暖炉の glb に入っている。props/build_nook.py の logs_and_fire）
##   炎: 火の手本（flame.gd）の切ったフェルトの形（2026-11-02 代表が焚き火の炎の案の左から 2 つ目を選んだ）を、炉の口の幅に合わせて 5 つ並べる。熾火は小さな羊毛玉
## 座標は暖炉の glb の座標（前の面が z = 0、炉の奥が +z、床が y = 0。build_nook.py の HEARTH_H・OW と同じ）。
## 部屋を照らす灯りはロッジ（lodge.gd の light_fire）が持つ。炉の中を照らす小さな灯りだけ、真ん中の炎に持たせる

const Flame := preload("res://flame.gd")
const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

const HEARTH_H := 0.32       # 炉床の上（build_nook.py の HEARTH_H）
const DEPTH := 0.55          # 薪の真ん中の奥行き（前の面から）
## 炎: [横のずれ (m), 大きさ（1 で 0.9 m）, 炉の中の灯りの明るさ, 奥へのずれ]
const FLAMES := [[0.0, 1.55, 0.3, 0.05], [-0.5, 1.1, 0.0, 0.1], [0.52, 1.15, 0.0, 0.0], [-0.92, 0.7, 0.0, 0.2], [0.95, 0.75, 0.0, 0.15]]

var _embers: Array[MeshInstance3D] = []
var _k := -1


func _ready() -> void:
	name = "HearthFire"
	var ember := Look.felt(Color(0.95, 0.40, 0.12), 4.0)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.42, 0.12)
	ember.emission_energy_multiplier = 1.4
	for i in 11:
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.085
		sm.radial_segments = 8
		sm.rings = 4
		var e := MeshInstance3D.new()
		e.mesh = sm
		e.material_override = ember
		e.position = Vector3(-1.0 + i * 0.2, HEARTH_H + 0.05, DEPTH - 0.25 + 0.3 * float(i % 2))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(e)
		_embers.append(e)
	for i in FLAMES.size():
		var f: Node3D = Flame.new()
		f.size = FLAMES[i][1]
		f.brightness = FLAMES[i][2]
		f.light_range = 3.5
		f.seed = 31 + i * 5
		f.style = "felt"
		f.position = Vector3(float(FLAMES[i][0]), HEARTH_H + 0.18, DEPTH + float(FLAMES[i][3]))
		add_child(f)


## 熾火: 12 コマごとに、いくつかが明るく、いくつかが暗く（焚き火と同じ）
func _process(_dt: float) -> void:
	var k := Doll.frame_index()
	if k == _k:
		return
	_k = k
	for i in _embers.size():
		_embers[i].scale = Vector3.ONE * (1.0 if fposmod(sin(float(k * 11 + i) * 12.9898) * 43758.5453, 1.0) > 0.35 else 0.7)
