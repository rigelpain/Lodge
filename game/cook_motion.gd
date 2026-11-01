extends RefCounted
## 厨房の装置の動く部品（cook_station.gd が 1 台に 1 つ持つ）。2026-11-01 代表「アイロンがけはしないしプレス機はプレスしないし
## 乾燥機は回らない。特に乾燥機は蓋を透明にしてほしい。中身が見えないと」。
## 動く部品は装置とは別の glb にしてあり（props/build_kitchen.py）、装置の目印に付けて、調理のコマ r（12 コマ／秒）で動かす:
##   iron   アイロン（giant_iron。目印 iron）: 鍋敷きから持ち上がって布（熱い楕円）の上へ下り、1 拍に 1 回、台の長さの向きに
##          行き来して当て布を押す（4 往復）。行き来の折り返しで湯気。最後に持ち上がって鍋敷きへ戻る
##   press  上の板（giant_heat_press_lid。目印 hinge）: ふだんは 38° 開いている。2 拍ごとに閉じながら柱にそって下りて押さえ（2 コマ）、
##          ゆっくり開いて上がる
##   dryer  胴（giant_dryer_drum。目印 drum）: 16 コマで 1 回り（人が入って回るのと同じ速さ）。料理の中身は cook_tumble.gd が胴の中で踊らせる
## 乾燥機の丸い戸の窓は、透明なビニール（vinyl.gdshader）に替える。
## どの動きもコマ r だけで決まるので、通信ではどの画面でも同じコマに同じ形になる

const Props := preload("res://props.gd")
const Tumble := preload("res://cook_tumble.gd")

const PART := {"iron": ["iron", "res://props/kitchen/giant_iron.glb"],
		"press": ["hinge", "res://props/kitchen/giant_heat_press_lid.glb"],
		"dryer": ["drum", "res://props/kitchen/giant_dryer_drum.glb"]}
const LID_OPEN := 38.0       # プレス機の上の板が休んでいる角 (度)
## プレス機の上の板の角（1 回の押し 12 コマ）: 下りて 2 コマで閉じ、2 コマ押さえ、ゆっくり開く
const LID_PRESS := [24.0, 8.0, 0.0, 0.0, 0.0, 3.0, 9.0, 17.0, 25.0, 31.0, 35.0, 37.0]
const SHUT := 2              # 押さえたコマ（ぼすっ・湯気）
const LID_DROP := 0.45       # 閉じきったとき、上の板が柱にそって下りる深さ (m。蝶番が高いので、回すだけでは下の熱板に届かない)
const IRON_UP := 0.45        # アイロンを持ち上げる高さ (m)
const IRON_ON := 0.07        # 布の上で、アイロンの底が熱い楕円から浮く高さ (m。ペレットを押さえる)
const IRON_GO := 6           # 鍋敷きから布の上へ（と、戻る）コマ
const STROKE := 12           # 1 往復のコマ（2 拍）
const REACH := 0.48          # 行き来の幅（片側, m）
const SPIN := TAU / 16.0     # 胴が 1 コマに回る角（cook_station.gd の SPIN と同じ）

var st: Node3D               # cook_station.gd
var dev: Node3D              # 装置
var part: Node3D             # 動く部品
var _home := Vector3.ZERO    # アイロン: 布の上の所（目印 iron から見て）
var _axis := Vector3.FORWARD # 胴の回る軸（目印 drum から見て。戸の向き）
var _bits: Node3D            # 胴の中で踊る中身（cook_tumble.gd）
var _lamp: OmniLight3D       # 胴の中の灯り（回っているあいだだけ。中で踊る物と人の形が窓ごしに分かるように）


func _init(station: Node3D, device: Node3D) -> void:
	st = station
	dev = device


## 目印 name（書き出しで名前に番号が付いて name_006 のようになることがある）
func mark(name: String) -> Node3D:
	for c in dev.find_children("*", "Node3D", true, false):
		var n := String(c.name)
		if n == name or n.begins_with(name + "_0"):
			return c
	return null


## 動く部品を目印に付ける（乾燥機は丸い窓を抜いたあとに呼ぶ: 胴の羽根が抜かれないように）
func mount() -> void:
	var kind: String = st.kind
	if kind == "dryer":
		_vinyl()
	if not PART.has(kind) or part:
		return
	var at := mark(PART[kind][0])
	if at == null:
		return
	part = Props.make(PART[kind][1])
	part.name = "Moving"
	at.add_child(part)
	match kind:
		"iron":
			var cook := mark("cook")
			if cook:
				_home = at.to_local(cook.global_position) + Vector3.UP * IRON_ON
		"dryer":
			_axis = (at.global_basis.inverse() * (st.front() as Vector3)).normalized()
			_two_sided(part)   # 胴の筒と底は外向きの面なので、窓から中を見ると裏が抜けて、乾燥機の後ろの壁が見えてしまう
			_lamp = OmniLight3D.new()
			_lamp.light_color = Color(1.0, 0.86, 0.66)
			_lamp.light_energy = 1.4
			_lamp.omni_range = 1.8
			_lamp.position = at.global_basis.inverse() * (Vector3.UP * 0.42 - (st.front() as Vector3) * 0.25)
			_lamp.visible = false
			at.add_child(_lamp)
	rest()


## 休んでいる形（調理の前と、仕上がったあと）
func rest() -> void:
	if part == null:
		return
	part.transform = Transform3D.IDENTITY
	if st.kind == "press":
		part.rotation.x = deg_to_rad(LID_OPEN)
	if _lamp:
		_lamp.visible = false
	if _bits:
		_bits.queue_free()
		_bits = null


# ---------------------------------------------------------------- プレス機

## r コマ目の上の板。押さえたコマなら true（ぼすっ・湯気・粒が平たくなる）
func press(r: int) -> bool:
	if part == null:
		return false
	var c := r % LID_PRESS.size()
	var ang: float = LID_PRESS[c]
	part.rotation.x = deg_to_rad(ang)
	part.position = Vector3.DOWN * LID_DROP * pow(1.0 - ang / LID_OPEN, 1.5)
	return c == SHUT


# ---------------------------------------------------------------- アイロン台

## r コマ目のアイロン（run は調理のコマ数）。返すのは {land 布に下りた, lift 持ち上げた, turn 折り返した, press 押した割合 0〜1}
func iron(r: int, run: int) -> Dictionary:
	var out := {"land": false, "lift": false, "turn": false, "press": 0.0}
	if part == null:
		return out
	var back := run - IRON_GO        # 戻りはじめるコマ
	if r < IRON_GO:                  # 鍋敷きから布の上へ
		var s := (r + 1.0) / IRON_GO
		part.position = _home * s + Vector3.UP * IRON_UP * sin(PI * s)
		part.rotation = Vector3(0.35 * sin(PI * s), 0.0, 0.0)   # 先を上げて運ぶ
		out.land = r == IRON_GO - 1
		return out
	if r >= back:                    # 持ち上がって鍋敷きへ
		var s := (r - back + 1.0) / IRON_GO
		part.position = _home * (1.0 - s) + Vector3.UP * IRON_UP * sin(PI * s)
		part.rotation = Vector3(0.35 * sin(PI * s), 0.0, 0.0)
		out.lift = r == back
		if r == run - 1:
			part.transform = Transform3D.IDENTITY
		return out
	# 布の上を行き来する: 台の長さの向き（アイロンの前後 = 目印から見て Z）に 1 往復 12 コマ。横へも少しずれていく
	var t := r - IRON_GO
	var w := TAU * t / STROKE
	var go := -sin(w)                # 前（台の先）へ +
	var side := 0.14 * sin(TAU * t / (STROKE * 2))
	part.position = _home + Vector3(side, 0.0, -go * REACH)
	part.rotation = Vector3(0.06 * cos(w), 0.08 * sin(TAU * t / (STROKE * 2)), 0.03 * sin(w * 2.0))   # 押す向きへ少し傾く
	out.turn = t % (STROKE / 2) == STROKE / 4
	out.press = clampf(float(t) / (back - IRON_GO), 0.0, 1.0)
	return out


## アイロンの先（湯気を出す所。世界）
func iron_tip() -> Vector3:
	if part == null:
		return dev.global_position
	return part.global_position + part.global_basis * Vector3(0, 0.05, -0.55)


# ---------------------------------------------------------------- 乾燥機

## r コマ目の胴（dish は回している料理。"" なら中身なし: 人が入って回るとき）
func dryer(r: int, dish: String) -> void:
	if part == null:
		return
	var a := r * SPIN
	part.basis = Basis(_axis, a)
	_lamp.visible = true
	if dish != "" and Tumble.has(dish):
		if _bits == null:
			_bits = Tumble.new()
			_bits.name = "Tumble"
			st.main.add_child(_bits)
			_bits.build(dish, r)
		_bits.step(r, st.drum_center(), st.front(), a)


static func _two_sided(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat:
				mat = mat.duplicate()
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.set_surface_override_material(i, mat)


## 丸い戸の窓を透明なビニールに（つるつるのガラスにしない）
func _vinyl() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://vinyl.gdshader")
	mat.set_shader_parameter("wrinkle", _noise(true))
	mat.set_shader_parameter("lines", _noise(false))
	for mi in dev.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).ends_with("_glass"):
			(mi as MeshInstance3D).material_override = mat


static func _noise(normal: bool) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012 if normal else 0.008
	fn.fractal_octaves = 3 if normal else 2
	fn.seed = 7
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = fn
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	return t
