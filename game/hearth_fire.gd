extends Node3D
## ロッジの暖炉の火を、外の焚き火（campfire.gd）と同じ手芸の形にそろえる（2026-11-02 代表「揃えていいと思う」）。
##   薪: 巻いたフェルトのロール（木口に渦の糸。campfire.gd の felt_log）
##   炎: 火の手本（flame.gd。薄葉紙をくしゃっと重ねた炎）を、炉の口の幅に合わせて 3 つ並べる。熾火は小さな羊毛玉
## ロッジの形（lodge.glb の lodge_body）には、前の火（光る板 "fire" と、くべた丸太 3 本 "log"）が焼き込まれていて、それだけを外せない:
##   光る板: 素材が "fire" の面を、見えない素材に差し替えて隠す
##   丸太: 同じ軸に、少し太い巻いたフェルトのロールをかぶせて覆う（丸太の素材は壁の丸太と同じなので、面ごとは隠せない）
## 寸法は lodge/build_lodge.py の炉（CH・fire_w）と同じ。ロッジの座標は Blender の (x 東, y 北, 高さ) → Godot の (x, 高さ, -y)。
## 灯りはロッジ（lodge.gd の light_fire）が持つ。炉の中を照らす小さな灯りだけ、真ん中の炎に持たせる

const Campfire := preload("res://campfire.gd")
const Flame := preload("res://flame.gd")
const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

const CX := -10.4            # 炉の真ん中（Blender の x）
const Y0 := 11.126           # 炉の前の面（Blender の y）
const FL1 := 0.45            # 1 階の床の高さ
const FIRE_W := 1.8          # 炉の口の幅
## くべた丸太 3 本（build_lodge.py と同じ並び）: [横のずれ k, 高さのずれ dz]
const LOGS := [[-0.2, 0.0], [0.2, 0.0], [0.0, 0.1]]
const LOG_R := 0.115         # 前の丸太（半径 0.10）を覆う太さ
## 炎: [横のずれ (m), 大きさ（1 で 0.9 m）, 炉の中の灯りの明るさ]
const FLAMES := [[0.0, 1.15, 0.22], [-0.42, 0.8, 0.0], [0.4, 0.85, 0.0]]

var _embers: Array[MeshInstance3D] = []
var _k := -1


func _ready() -> void:
	name = "HearthFire"
	if "--old-hearth" in OS.get_cmdline_user_args():   # 確かめ用: 前の火のまま（見比べ）
		queue_free()
		return
	_hide_plate()
	for i in LOGS.size():
		var k: float = LOGS[i][0]
		var dz: float = LOGS[i][1]
		var p0 := _g(Vector3(CX - FIRE_W / 2.0 + 0.2, Y0 + 0.35 + k * 0.4, FL1 + 0.28 + dz))
		var p1 := _g(Vector3(CX + FIRE_W / 2.0 - 0.2, Y0 + 0.35 - k * 0.4, FL1 + 0.28 + dz))
		var tan := Campfire.FELT_TAN if i % 2 == 0 else Campfire.FELT_BROWN
		var end := Campfire.FELT_BROWN if i % 2 == 0 else Campfire.FELT_TAN
		var lg := Campfire.felt_log(LOG_R, p0.distance_to(p1) + 0.04, Look.felt(tan, 2.0), Look.felt(end, 4.0))
		lg.position = (p0 + p1) / 2.0
		lg.basis = Basis(Quaternion(Vector3.UP, (p1 - p0).normalized()))
		add_child(lg)
	var ember := Look.felt(Color(0.95, 0.40, 0.12), 4.0)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.42, 0.12)
	ember.emission_energy_multiplier = 1.4
	for i in 7:
		var sm := SphereMesh.new()
		sm.radius = 0.04
		sm.height = 0.07
		sm.radial_segments = 8
		sm.rings = 4
		var e := MeshInstance3D.new()
		e.mesh = sm
		e.material_override = ember
		e.position = _g(Vector3(CX - 0.6 + i * 0.2, Y0 + 0.2 + 0.25 * float(i % 2), FL1 + 0.2))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(e)
		_embers.append(e)
	for i in FLAMES.size():
		var f: Node3D = Flame.new()
		f.size = FLAMES[i][1]
		f.brightness = FLAMES[i][2]
		f.light_range = 3.0
		f.seed = 31 + i * 5
		f.position = _g(Vector3(CX + float(FLAMES[i][0]), Y0 + 0.35, FL1 + 0.3))
		add_child(f)


## Blender のロッジの座標 → このノード（ロッジの子）の座標
static func _g(b: Vector3) -> Vector3:
	return Vector3(b.x, b.z, -b.y)


## 前の火の光る板を隠す（ロッジの形の、素材が "fire" の面）
func _hide_plate() -> void:
	var lodge := get_parent()
	if lodge == null:
		return
	var clear := StandardMaterial3D.new()
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.albedo_color = Color(0, 0, 0, 0)
	clear.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for n in lodge.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == "fire":
				mi.set_surface_override_material(i, clear)


## 熾火: 12 コマごとに、いくつかが明るく、いくつかが暗く（焚き火と同じ）
func _process(_dt: float) -> void:
	var k := Doll.frame_index()
	if k == _k:
		return
	_k = k
	for i in _embers.size():
		_embers[i].scale = Vector3.ONE * (1.0 if fposmod(sin(float(k * 11 + i) * 12.9898) * 43758.5453, 1.0) > 0.35 else 0.7)
