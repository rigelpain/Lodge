extends RefCounted
## 机のある席で食べるときの、食べ物ごとの食べ方（2026-11-06 代表。design/food-look/table-eat.md）。
## 立って食べるとき、机のない席（ソファ・揺り椅子・ビーズクッション・長椅子）は、これまでの 3 口のまま（emotes.gd の eat）。
##
## 動きは出来事 {kind: "eat_t", who, dish, style, len, bites, first, last, frame}。中身は数と文字だけで、通信にそのまま乗る。
## 姿勢は pose() が「その空間の点」から決める。一人称はカメラの空間、人形は骨の空間の点を渡すので、どの画面でも同じ食べ方になる。
## 動きはコマ（12 コマ／秒）だけで決まる。
##
## 机の上の皿・手の道具・すすられる麺は Rig が描く。Rig は描く層ごとに 1 つ（一人称の手の層と、人形の層）。

const Food := preload("res://food.gd")
const Look := preload("res://look.gd")
const Props := preload("res://props.gd")

## 品ごとの食べ方
const STYLE_OF := {
	"onigiri": "gabu", "taiyaki": "hafu", "nikuman": "hafu", "korokke": "hafu", "hashbrown": "hafu", "hotsand": "hafu", "yakiimo": "hafu",
	"fries": "pinch", "hotcake": "cut", "sanma": "flake", "kaki": "flake",
	"yakisoba": "slurp", "ramen": "slurp", "udon": "slurp", "soba": "slurp",
	"cocoa": "cup", "corn": "cup", "greentea": "cup", "milk": "cup", "milktea": "cup",
	"oshiruko": "wan", "clam": "spoon",
}
## len: 1 回の長さ（コマ）、bite: ひと口を数えるコマ、hold: 器や品を持ち上げる手、tools: 手の道具 [右, 左]、snd: コマごとの音 [名前, 数]
const STYLES := {
	"slurp": {"len": 18, "bite": 17, "tools": ["hashi", ""], "snd": {6: ["eat_slurp", 2]}},   # 麺類: 箸ですする（押しているあいだ切れ目なく）
	"hafu": {"len": 32, "bite": 20, "hold": "both", "tools": ["", ""], "snd": {6: ["eat_hafu", 3], 11: ["eat_hafu", 3], 15: ["eat_hafu", 3], 20: ["eat_chew", 4]}},   # 熱い物: 両手で持ってはふはふ
	"gabu": {"len": 22, "bite": 8, "hold": "both", "tools": ["", ""], "snd": {7: ["eat_chew", 4]}},   # おにぎり: 両手でかぶりつく
	"flake": {"len": 30, "bite": 22, "tools": ["hashi", ""], "snd": {4: ["eat_cho", 3], 8: ["eat_cho", 3], 12: ["eat_cho", 3], 21: ["eat_chew", 4]}},   # 焼き魚・牡蠣: 箸でほぐして口へ
	"cut": {"len": 28, "bite": 20, "tools": ["knife", "fork"], "snd": {19: ["eat_chew", 4]}},   # ホットケーキ: 切ってフォークで
	"pinch": {"len": 16, "bite": 8, "tools": ["", ""], "snd": {7: ["eat_crunch", 4]}},   # ポテト: 箱から 1 本つまむ
	"spoon": {"len": 22, "bite": 12, "tools": ["spoon", ""], "snd": {10: ["eat_sip", 2]}},   # クラムチャウダー: さじで
	"cup": {"len": 26, "bite": 16, "hold": "both", "tools": ["", ""], "snd": {5: ["eat_blow", 2], 13: ["eat_sip", 2]}},   # 飲み物: 両手で包み、ふーっと吹いてすする
	"wan": {"len": 28, "bite": 18, "hold": "left", "tools": ["hashi", ""], "snd": {9: ["eat_sip", 2], 17: ["eat_chew", 4]}},   # お汁粉: 左手で椀を持ち、箸で餅を
}
const TABLE_SCALE := 0.8     # 机に置いた皿の大きさ（glb の何倍か）
const HOLD_W := 0.09        # 両手で持つ、手の間の半分 (m)
const TOOL_LEN := 0.2        # 手から道具の先まで (m)
const SLURP_LIFT := 6        # すすり始めの、箸で麺を持ち上げるコマ
## 麺（props/build_food.py の ramen・yakisoba と同じ数と太さ。色は毛糸の色）
const NOODLES := {
	"ramen": {"count": 15, "r": 0.0034, "wave": 0.0028, "color": "E3C070"},
	"udon": {"count": 12, "r": 0.0058, "wave": 0.0026, "color": "D8D0BC"},
	"soba": {"count": 22, "r": 0.0024, "wave": 0.0012, "color": "8A7A68"},
	"yakisoba": {"count": 40, "r": 0.0034, "color": "A9703C", "pile": true},
}
const BIT_COLOR := {"sanma": "EDE3CC", "kaki": "DCCB9E", "hotcake": "F4E2AE", "fries": "E8C878", "clam": "F2EAD4", "oshiruko": "F4EFE2"}


static func style_of(dish: String) -> String:
	return STYLE_OF.get(dish, "gabu")


## 手の品 it を、席 seat で食べるときの状況。机のない席、できあがっていない品なら空
static func ctx(seat: Dictionary, it: Dictionary) -> Dictionary:
	if seat.is_empty() or not seat.has("table") or not Food.done(it):
		return {}
	return {"dish": it.dish, "bites": int(it.get("bites", 0)), "at": seat.table, "face": seat.face}


static func event(who: int, c: Dictionary, first: bool) -> Dictionary:
	var style := style_of(c.dish)
	return {"kind": "eat_t", "who": who, "dish": c.dish, "style": style, "len": STYLES[style].len, "bites": c.bites, "first": first,
			"last": int(c.bites) >= Food.BITES - 1}


## 折れ線: [[コマ, 点], ...] の k での点
static func _seq(k: int, keys: Array) -> Vector3:
	if k <= int(keys[0][0]):
		return keys[0][1]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if k <= int(b[0]):
			return (a[1] as Vector3).lerp(b[1], float(k - int(a[0])) / maxf(1.0, float(int(b[0]) - int(a[0]))))
	return keys[-1][1]


## 道具の先 tip を持つ手の所: 体の側へ道具の長さ。皿の上では手が先より上（机に潜らない）、口もとでは少し下
static func _hand_of(tip: Vector3, rest: Vector3, mouth: Vector3, up: Vector3, tl: float) -> Vector3:
	var d := rest - tip
	d -= up * d.dot(up)
	var s := clampf(tip.distance_to(mouth) / (tl * 1.2), 0.0, 1.0)
	return tip + (d.normalized() * 0.82 + up * lerpf(-0.3, 0.58, s)).normalized() * tl


## 姿勢。A はその空間の点: mouth 口もと、near 顔の前、rest_r・rest_l 休める手、dish 机の皿、right 右、up 上、hold_w 手の間、tool 道具の長さ。
## 返すもの: r・l 手、item 持ち上げた品の所（null は机の上）、tilt 品の傾き（度）、tip・tip_l 道具の先、carry 道具の先に品のかけら、nod 頭の上下
static func pose(style: String, k: int, first: bool, A: Dictionary) -> Dictionary:
	var up: Vector3 = A.up
	var right: Vector3 = A.right
	var dish: Vector3 = A.dish
	var mouth: Vector3 = A.mouth
	var near: Vector3 = A.near
	var rr: Vector3 = A.rest_r
	var rl: Vector3 = A.rest_l
	var w: float = A.hold_w
	var tl: float = A.tool
	var out := {"r": rr, "l": rl, "item": null, "tilt": 0.0, "tip": null, "tip_l": null, "carry": false, "nod": 0.0}
	var back_r: Vector3 = (rr - mouth).normalized() * tl + up * tl * 0.2     # 休めるときの、道具の先から右手の所へ
	var dish_hi := dish + up * tl * 0.2
	var by_table: Vector3 = A.get("l_table", dish - right * tl * 0.95 + up * tl * 0.12)   # 皿のわきに添える左手（一人称では画面の外に休める）
	match style:
		"slurp":
			var tip: Vector3
			if first and k < SLURP_LIFT:
				tip = _seq(k, [[0, rr - back_r], [2, dish_hi], [3, dish_hi], [SLURP_LIFT, A.lift]])
			else:
				tip = (A.lift as Vector3) + up * (tl * 0.05 if k % 2 == 0 else 0.0)   # 箸で麺を高く持ち上げ、そこから口へ吸い込む
				out.nod = -0.05 if k % 4 < 2 else -0.11
			out.tip = tip
			# 持ち上げたら、手は箸の先より下へ（画面の上を袖でふさがない）
			var lifted_k := 1.0 if not first else clampf((k - 3) / 3.0, 0.0, 1.0)
			out.r = _hand_of(tip, rr, mouth, up, tl).lerp(tip + (right * 0.85 - up * 0.45).normalized() * tl, lifted_k)
			out.l = by_table
		"flake":
			var tip: Vector3
			if k < 3:
				tip = _seq(k, [[0, rr - back_r], [3, dish_hi]])
			elif k < 15:   # 身をつついてほぐす: 2 コマごとに上下、3 か所
				var sp: float = [-0.6, 0.15, 0.7][mini((k - 3) / 4, 2)] * tl * 0.55
				tip = dish + right * sp + up * (tl * 0.04 if k % 2 == 1 else tl * 0.22)
			elif k < 19:
				tip = _seq(k, [[15, dish_hi], [19, mouth]])
				out.carry = true
			elif k < 26:
				tip = mouth
				out.carry = k < 21
				out.nod = -0.04 if (k / 2) % 2 == 0 else 0.0
			else:
				tip = _seq(k, [[26, mouth], [29, rr - back_r]])
			out.tip = tip
			out.r = _hand_of(tip, rr, mouth, up, tl)
			out.l = by_table
			out.nod += -0.14 if k < 15 else 0.0
		"cut":
			var fork: Vector3
			var knife: Vector3
			var back_l: Vector3 = (rl - mouth).normalized() * tl + up * tl * 0.2
			if k < 4:
				knife = _seq(k, [[0, rr - back_r], [4, dish_hi + right * tl * 0.2]])
				fork = _seq(k, [[0, rl - back_l], [4, dish_hi - right * tl * 0.05]])
			elif k < 12:   # 押さえて、ナイフを前後に
				knife = dish + right * tl * 0.22 + up * tl * 0.08 + (right.cross(up)) * tl * (0.2 if k % 2 == 0 else -0.2)
				fork = dish - right * tl * 0.05 + up * tl * 0.06
			elif k < 17:
				knife = _seq(k, [[12, dish_hi + right * tl * 0.2], [17, rr - back_r]])
				fork = _seq(k, [[12, dish_hi], [17, mouth]])
				out.carry = true
			elif k < 25:
				knife = rr - back_r
				fork = mouth
				out.carry = k < 19
				out.nod = -0.04 if (k / 2) % 2 == 0 else 0.0
			else:
				knife = rr - back_r
				fork = _seq(k, [[25, mouth], [27, rl - back_l]])
			out.tip = knife
			out.tip_l = fork
			out.r = _hand_of(knife, rr, mouth, up, tl)
			out.l = _hand_of(fork, rl, mouth, up, tl)
			out.nod += -0.12 if k < 12 else 0.0
		"pinch":
			var tip := _seq(k, [[0, rr], [3, dish_hi], [4, dish_hi], [7, mouth], [12, mouth], [15, rr]])
			out.r = tip
			out.tip = tip
			out.carry = k >= 4 and k < 9
			out.l = by_table
			out.nod = -0.05 if k >= 8 and k < 12 and (k / 2) % 2 == 0 else 0.0
		"spoon":
			var tip := _seq(k, [[0, rr - back_r], [3, dish_hi], [5, dish + up * tl * 0.08], [7, dish_hi], [10, mouth], [15, mouth], [19, rr - back_r]])
			out.tip = tip
			out.r = _hand_of(tip, rr, mouth, up, tl)
			out.l = by_table
			out.carry = k >= 5 and k < 12
			out.nod = -0.12 if k < 6 else (-0.05 if k >= 12 and k < 15 else 0.0)
		"hafu":
			# 両手で持ち上げ、口の前ではふはふ（顔を引いて、口を開けて息を吐く）→ かじる → 噛みながら下ろす
			var item: Vector3
			if k < 4:
				item = _seq(k, [[0, dish], [4, near]])
			elif k < 18:
				item = near.lerp(mouth, 0.35 if (k / 2) % 2 == 0 else 0.0)
				out.nod = 0.09 if (k / 2) % 2 == 0 else 0.03
			elif k < 21:
				item = _seq(k, [[18, near], [20, mouth], [21, mouth]])
			elif k < 28:
				item = mouth.lerp(near, 0.5)
				out.nod = -0.05 if (k / 2) % 2 == 0 else 0.0
			else:
				item = _seq(k, [[28, near], [31, dish]])
			out.item = item
			out.r = item + right * w
			out.l = item - right * w
		"gabu":
			var item := _seq(k, [[0, dish], [4, near], [7, mouth], [9, mouth], [12, near], [17, near], [21, dish]])
			out.item = item
			out.r = item + right * w
			out.l = item - right * w
			out.nod = -0.05 if k >= 9 and k < 17 and (k / 2) % 2 == 0 else 0.0
		"cup":
			var item := _seq(k, [[0, dish], [4, near], [9, near], [12, mouth], [17, mouth], [20, near], [25, dish]])
			out.item = item
			out.tilt = 34.0 if k >= 12 and k < 18 else (14.0 if k >= 10 and k < 20 else 0.0)
			out.r = item + right * w
			out.l = item - right * w
			out.nod = 0.1 if k >= 5 and k < 9 else (-0.1 if k >= 12 and k < 18 else 0.0)
		"wan":
			var item := _seq(k, [[0, dish], [4, near], [24, near], [27, dish]])
			out.item = item
			out.l = item - right * w * 1.2
			var tip := _seq(k, [[0, rr - back_r], [3, rr - back_r], [6, item + up * tl * 0.12], [8, item + up * tl * 0.12], [11, mouth], [20, mouth], [23, rr - back_r]])
			out.tip = tip
			out.r = _hand_of(tip, rr, mouth, up, tl)
			out.carry = k >= 8 and k < 13
			out.nod = -0.05 if k >= 13 and k < 20 and (k / 2) % 2 == 0 else 0.0
	return out


# ---------------------------------------------------------------- 描く役
class Rig extends Node3D:
	var layer_mask := 1
	var _path := ""
	var _dish: Node3D
	var _tools := [null, null]
	var _tool_kinds := ["", ""]
	var _bit: MeshInstance3D
	var _bit_key := ""
	var _noodles: MeshInstance3D
	var _noodle_key := ""
	var _noodle_mat: StandardMaterial3D
	var _noodle_of := ""
	var _strands: Array = []

	static func _wood_mesh(mesh: Mesh, xf: Transform3D, layers: int) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = Look.wood(Color("D2B07E"))
		mi.transform = xf
		mi.layers = layers
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi


	static func _stick(r0: float, r1: float, length: float, sides := 8) -> CylinderMesh:
		var c := CylinderMesh.new()
		c.top_radius = r1     # 先（-Z へ寝かせる）
		c.bottom_radius = r0
		c.height = length
		c.radial_segments = sides
		c.rings = 1
		return c


	## 道具: 原点が手の所で、-Z の TOOL_LEN 先が道具の先
	static func make_tool(kind: String, layers: int) -> Node3D:
		var root := Node3D.new()
		var lay := Basis(Vector3.RIGHT, -PI / 2.0)   # 円柱の +Y を -Z へ
		match kind:
			"hashi":
				for s in [-1.0, 1.0]:
					root.add_child(_wood_mesh(_stick(0.0055, 0.0028, TOOL_LEN + 0.05), Transform3D(lay.rotated(Vector3.UP, s * 0.03), Vector3(s * 0.007, 0, -(TOOL_LEN - 0.05) * 0.5)), layers))
			"spoon":
				root.add_child(_wood_mesh(_stick(0.0065, 0.0045, TOOL_LEN - 0.03), Transform3D(lay, Vector3(0, 0, -(TOOL_LEN - 0.03) * 0.5)), layers))
				var head := SphereMesh.new()
				head.radius = 0.024
				head.height = 0.048
				head.radial_segments = 14
				head.rings = 8
				root.add_child(_wood_mesh(head, Transform3D(Basis.from_scale(Vector3(0.8, 0.26, 1.0)), Vector3(0, 0, -TOOL_LEN + 0.012)), layers))
			"fork":
				root.add_child(_wood_mesh(_stick(0.0065, 0.0045, TOOL_LEN - 0.05), Transform3D(lay, Vector3(0, 0, -(TOOL_LEN - 0.05) * 0.5)), layers))
				var neck := BoxMesh.new()
				neck.size = Vector3(0.024, 0.004, 0.018)
				root.add_child(_wood_mesh(neck, Transform3D(Basis.IDENTITY, Vector3(0, 0, -TOOL_LEN + 0.05)), layers))
				for x in [-0.0085, 0.0, 0.0085]:
					var tine := BoxMesh.new()
					tine.size = Vector3(0.0042, 0.0032, 0.04)
					root.add_child(_wood_mesh(tine, Transform3D(Basis.IDENTITY, Vector3(x, 0, -TOOL_LEN + 0.02)), layers))
			"knife":
				root.add_child(_wood_mesh(_stick(0.0075, 0.0065, 0.09), Transform3D(lay, Vector3(0, 0, -0.045)), layers))
				var blade := BoxMesh.new()
				blade.size = Vector3(0.003, 0.02, TOOL_LEN - 0.08)
				root.add_child(_wood_mesh(blade, Transform3D(Basis.IDENTITY, Vector3(0, -0.002, -0.09 - (TOOL_LEN - 0.09) * 0.5)), layers))
		return root


	## 麺をどこまで食べたか（0〜1）。3 口に分けず、すすっているコマで増える
	static func slurp_done(bites: int, k: int, first: bool, length: int) -> float:
		var f := 0.0
		if k >= 0:
			f = clampf(float(k - SLURP_LIFT) / (length - SLURP_LIFT), 0.0, 1.0) if first else clampf(float(k) / length, 0.0, 1.0)
		return clampf((bites + f) / float(Food.BITES), 0.0, 1.0)

	func _init(mask: int) -> void:
		layer_mask = mask
		top_level = true

	## c: 机の状況（ctx）。ev: いまの eat_t の出来事か空。k: そのコマ。P: pose() の結果を世界の点にしたもの。
	## item_b: 持ち上げた品の向き（形の正面を顔へ）。item_s: その大きさ。tool_s: 道具の大きさ。mouth: 口もとの世界の点。
	func step(c: Dictionary, ev: Dictionary, k: int, P: Dictionary, item_b: Basis, item_s: float, tool_s: float, mouth: Vector3) -> void:
		visible = not c.is_empty()
		if c.is_empty():
			return
		var style: String = STYLE_OF.get(c.dish, "gabu")
		var spec: Dictionary = STYLES[style]
		var bites: int = c.bites
		var path: String = Food.noodle_glb(c.dish, bites) if style == "slurp" else Food.dish_glb(c.dish, bites)
		var fresh := false
		if path != _path:
			_path = path
			if _dish:
				_dish.queue_free()
			_dish = Props.make(path)
			add_child(_dish)
			for mi in _dish.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).layers = layer_mask
			for s in _dish.find_children("Smoke", "GPUParticles3D", true, false):
				(s as GPUParticles3D).amount_ratio = 0.15
				(s as GPUParticles3D).layers = layer_mask
			_noodle_key = ""
			_noodles = null
			fresh = true
		var face: Vector3 = c.face
		var at: Vector3 = c.at
		var table_b := Basis.looking_at(-face, Vector3.UP)
		var active := k >= 0 and not ev.is_empty()
		var lifted: bool = active and P.get("item") != null
		if lifted:
			var hold: Dictionary = Food.HOLD.get(c.dish, Food.HOLD_DRINK if c.dish in Food.DRINKS else Food.HOLD_DEFAULT)
			var b: Basis = item_b * Basis.from_euler(hold.rot * PI / 180.0, EULER_ORDER_YXZ) * Basis(Vector3.UP, deg_to_rad(float(hold.get("yaw", 0.0))))
			if float(P.tilt) != 0.0:
				b = Basis(item_b.x, deg_to_rad(float(P.tilt))) * b
			_dish.global_transform = Transform3D(b.scaled(Vector3.ONE * item_s), P.item - b.y * 0.03 * item_s)
		else:
			_dish.global_transform = Transform3D(table_b.scaled(Vector3.ONE * TABLE_SCALE), at)
		for smoke in _dish.find_children("Smoke", "GPUParticles3D", true, false):   # 持ち上げたら湯気は止める（机の上に残さない）
			(smoke as GPUParticles3D).visible = not lifted
		if fresh:   # 煙は世界に残るので、置いた所から出し直す
			for s in _dish.find_children("Smoke", "GPUParticles3D", true, false):
				(s as GPUParticles3D).restart()
		_place_tools(spec, active, P, at, face, tool_s)
		_place_bit(c.dish, active and bool(P.carry), P, tool_s)
		if style == "slurp":
			_place_noodles(c, ev, k, P, mouth)

	func _place_tools(spec: Dictionary, active: bool, P: Dictionary, at: Vector3, face: Vector3, tool_s: float) -> void:
		var right := face.cross(Vector3.UP).normalized()
		for i in 2:
			var kind: String = spec.tools[i]
			if kind != _tool_kinds[i]:
				_tool_kinds[i] = kind
				if _tools[i]:
					_tools[i].queue_free()
				_tools[i] = make_tool(kind, layer_mask) if kind != "" else null
				if _tools[i]:
					add_child(_tools[i])
			var t: Node3D = _tools[i]
			if t == null:
				continue
			var hand = P.get("r" if i == 0 else "l")
			var tip = P.get("tip" if i == 0 else "tip_l")
			if active and tip != null and hand != null and (hand as Vector3).distance_to(tip) > 0.01:
				var b := Basis.looking_at((tip as Vector3) - (hand as Vector3), Vector3.UP)
				t.global_transform = Transform3D(b.scaled(Vector3.ONE * tool_s), hand)
			else:   # 使っていないときは、皿のわきに置いておく
				var side := 1.0 if i == 0 else -1.0
				t.global_transform = Transform3D(Basis.looking_at(face, Vector3.UP).scaled(Vector3.ONE * TABLE_SCALE), at + right * side * 0.2 * TABLE_SCALE / 0.8 * 1.15 - face * 0.1 + Vector3.UP * 0.012)

	func _place_bit(dish: String, on: bool, P: Dictionary, tool_s: float) -> void:
		var tip = P.get("tip_l") if P.get("tip_l") != null else P.get("tip")
		if not on or tip == null:
			if _bit:
				_bit.visible = false
			return
		if _bit == null or _bit_key != dish:
			_bit_key = dish
			if _bit:
				_bit.queue_free()
			_bit = MeshInstance3D.new()
			if dish == "fries":
				var box := BoxMesh.new()
				box.size = Vector3(0.009, 0.009, 0.08)
				_bit.mesh = box
			else:
				var bead := SphereMesh.new()
				bead.radius = 0.015
				bead.height = 0.024
				bead.radial_segments = 10
				bead.rings = 5
				_bit.mesh = bead
			_bit.material_override = Look.felt(Color(BIT_COLOR.get(dish, "EDE3CC")))
			_bit.layers = layer_mask
			add_child(_bit)
		_bit.visible = true
		_bit.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * tool_s), tip)

	## 器の麺: 残りの本数だけ描き、いまの 1 本は器の側から短くなって箸の先へ続く
	func _place_noodles(c: Dictionary, ev: Dictionary, k: int, P: Dictionary, mouth: Vector3) -> void:
		var spec: Dictionary = NOODLES[c.dish]
		var length: int = ev.get("len", STYLES.slurp.len)
		var first: bool = ev.get("first", true)
		var active := k >= 0 and not ev.is_empty() and P.get("tip") != null
		var done: float = slurp_done(c.bites, k if active else -1, first, length)
		var left: float = spec.count * (1.0 - done)
		var key := "%s_%d_%.2f_%s" % [c.dish, c.bites, left, str(P.get("tip")) if active else ""]
		if key == _noodle_key:
			return
		_noodle_key = key
		if _noodles == null:
			_noodles = MeshInstance3D.new()
			_noodles.layers = layer_mask
			_noodles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_dish.add_child(_noodles)
		if _noodle_of != c.dish:
			_noodle_of = c.dish
			_noodle_mat = StandardMaterial3D.new()   # 毛糸の色をそのまま。縁の光を足すと、灯りの下で白く飛ぶ
			_noodle_mat.albedo_color = Color(spec.color)
			_noodle_mat.roughness = 1.0
			_noodle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_strands = _make_strands(c.dish, spec)
		_noodles.material_override = _noodle_mat
		var level_of := _level(c.dish, c.bites)
		var mesh := ArrayMesh.new()
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		var r: float = spec.r * 1.5
		var whole := int(floor(left))
		for i in mini(whole, _strands.size()):
			_tube(verts, norms, idx, _lifted(_strands[i], level_of), r)
		if active and bool(first or true) and left > 0.0 and whole < _strands.size() + 1:
			# いま吸われている束: 器の中の 1 本の残りから、箸の先を通って口へ。波打ちはコマで動く
			var to_local := _noodles.global_transform.affine_inverse()
			var tip: Vector3 = to_local * (P.tip as Vector3)
			var lip: Vector3 = to_local * mouth
			var src: Array = _lifted(_strands[mini(whole, _strands.size() - 1)], level_of)
			var frac := left - whole
			var n_src := maxi(2, int(src.size() * clampf(frac, 0.05, 1.0)))
			for b in 3:
				var pts: Array = src.slice(0, n_src) if b == 0 else [src[mini(n_src - 1, src.size() - 1)] + Vector3(0.012 * b, 0, -0.01 * b)]
				var start: Vector3 = pts[-1]
				for j in range(1, 9):
					var t := j / 8.0
					var q: Vector3 = start.lerp(tip, t)
					q += Vector3(sin(t * 12.0 + k * 1.7 + b * 2.0), 0, cos(t * 10.0 + k * 1.3 + b)) * 0.006 * sin(t * PI)
					pts.append(q)
				for j in range(1, 4):
					pts.append(tip.lerp(lip, j / 3.0))
				_tube(verts, norms, idx, pts, r * 1.25)
		if verts.is_empty():
			_noodles.mesh = null
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_noodles.mesh = mesh

	## 麺の水面の高さと、器の中の広がり（glb の座標。書き出しの 1.5 倍の前の値）: [水面, 山の半径, 山の高さ]
	func _level(dish: String, bites: int) -> Array:
		if dish == "yakisoba":
			var k: float = [1.0, 0.76, 0.46][bites]
			return [0.012, 0.074 * sqrt(k), 0.042 * k]
		return [[0.071, 0.063, 0.044][bites], 0.0, 0.0]

	## 1 本ずつの道筋（高さは _lifted で水面に合わせる）。乱数は決めた種で、どの画面でも同じ
	func _make_strands(dish: String, spec: Dictionary) -> Array:
		var rnd := RandomNumberGenerator.new()
		rnd.seed = hash(dish)
		var out := []
		var count: int = spec.count
		for k in count:
			var pts := []
			if spec.get("pile", false):
				var a0 := rnd.randf_range(0.0, TAU)
				var r0 := rnd.randf_range(0.1, 0.9)
				var da := rnd.randf_range(-2.6, 2.6)
				var dr := rnd.randf_range(-0.5, 0.5)
				var lift := rnd.randf_range(0.82, 1.12)
				for i in 15:
					var t := i / 14.0
					var rr := clampf(r0 + dr * (t - 0.5) + 0.07 * sin(t * 15.0 + k), 0.03, 1.0)
					var a := a0 + da * t + 0.2 * sin(t * 11.0 + k)
					pts.append([rr * cos(a), rr * sin(a), lift, 0.0026 * sin(t * 19.0 + k)])
			else:
				var f := (k + 0.5) / float(count)
				var y0 := -0.012 + 0.065 * f
				var half := 0.08
				var tilt := 0.12 * sin(k * 1.7)
				for i in 24:
					var t := i / 23.0
					var x := -half + 2.0 * half * t
					var w: float = spec.wave * sin(t * 34.0 + k * 1.3)
					var bump := pow(sin(t * PI), 0.5)
					var z := 0.0015 + 0.0085 * bump + 0.0022 * sin(t * 17.0 + k * 2.1) + (0.004 if k % 3 == 0 else 0.0) * bump
					pts.append([x, y0 + tilt * x + w, z])
			out.append(pts)
		return out

	func _lifted(strand: Array, lv: Array) -> Array:
		var out := []
		var pile: bool = lv[1] > 0.0
		for p in strand:
			if pile:
				var r2: float = p[0] * p[0] + p[1] * p[1]
				out.append(Vector3(p[0] * lv[1], lv[0] + lv[2] * (1.0 - r2) * p[2] + p[3], -p[1] * lv[1]) * 1.5)
			else:
				var edge := minf(1.0, sqrt(maxf(0.0, 1.0 - pow(float(p[1]) / 0.09, 2.0))) * 0.09 / 0.08)   # 水面が低いほど器がすぼまる
				var shrink := 1.0 if lv[0] > 0.06 else 0.8
				out.append(Vector3(p[0] * edge * shrink, lv[0] + p[2], -p[1] * shrink) * 1.5)
		return out

	func _tube(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array, pts: Array, r: float) -> void:
		const SIDES := 5
		var base := verts.size()
		var n := pts.size()
		for i in n:
			var p: Vector3 = pts[i]
			var d: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var u := d.cross(Vector3.UP)
			u = u.normalized() if u.length() > 0.01 else Vector3.RIGHT
			var v := d.cross(u).normalized()
			for s in SIDES:
				var a := TAU * s / SIDES
				var nrm := u * cos(a) + v * sin(a)
				verts.append(p + nrm * r)
				norms.append(nrm)
		for i in n - 1:
			for s in SIDES:
				var a0 := base + i * SIDES + s
				var a1 := base + i * SIDES + (s + 1) % SIDES
				var b0 := a0 + SIDES
				var b1 := a1 + SIDES
				idx.append_array([a0, b0, a1, a1, b0, b1])
